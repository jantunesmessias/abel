import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('devex-source-test.'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test(
    'filesystem snapshot is deterministic and marks symlinks incomplete',
    () {
      File(p.join(temp.path, 'lib/a.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('a');
      final first = const FilesystemSourceAdapter().inspect(root: temp.path);
      final second = const FilesystemSourceAdapter().inspect(root: temp.path);
      expect(first.digest, second.digest);
      expect(first.completeness, SnapshotCompleteness.complete);

      Link(p.join(temp.path, 'link')).createSync('lib/a.dart');
      final linked = const FilesystemSourceAdapter().inspect(root: temp.path);
      expect(linked.completeness, SnapshotCompleteness.partial);
      expect(linked.omissions.single, contains('symlink'));
    },
  );

  test(
    'Git adapter distinguishes immutable revision and current worktree',
    () async {
      await _git(temp, const <String>['init']);
      await _git(temp, const <String>[
        'config',
        'user.email',
        'test@example.test',
      ]);
      await _git(temp, const <String>['config', 'user.name', 'DevEx Test']);
      File(p.join(temp.path, 'tracked.txt')).writeAsStringSync('one');
      await _git(temp, const <String>['add', 'tracked.txt']);
      await _git(temp, const <String>['commit', '-m', 'initial']);
      final head = (await _git(temp, const <String>[
        'rev-parse',
        'HEAD',
      ])).trim();
      File(p.join(temp.path, 'untracked.txt')).writeAsStringSync('two');

      final revision = await const GitSourceAdapter().inspect(
        root: temp.path,
        revision: head,
      );
      final worktree = await const GitSourceAdapter().inspect(root: temp.path);
      expect(revision.revision, head);
      expect(revision.files.map((file) => file.path), <String>['tracked.txt']);
      expect(
        worktree.files.map((file) => file.path),
        containsAll(<String>['tracked.txt', 'untracked.txt']),
      );
      expect(worktree.revision, startsWith('worktree:$head:'));
    },
  );

  test(
    'ContextBundle requires explicit files, verifies snapshot, and redacts secrets',
    () {
      File(
        p.join(temp.path, 'safe.txt'),
      ).writeAsStringSync('Authorization: Bearer secret\nhello');
      File(p.join(temp.path, '.env')).writeAsStringSync('TOKEN=secret');
      final snapshot = const FilesystemSourceAdapter().inspect(root: temp.path);
      final context = const LocalContextBundleExporter().export(
        snapshot: snapshot,
        root: temp.path,
        paths: <String>['safe.txt', '.env'],
      );
      expect(context.files.single.path, 'safe.txt');
      expect(context.files.single.content, contains('[REDACTED]'));
      expect(context.files.single.content, isNot(contains('Bearer secret')));
      expect(
        context.redactions,
        containsAll(<String>[
          '.env:secret-like-path',
          'safe.txt:secret-pattern',
        ]),
      );
      expect(ContextBundle.fromJson(context.toJson()).digest, context.digest);
    },
  );
}

Future<String> _git(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    <String>['-C', root.path, ...arguments],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return result.stdout as String;
}
