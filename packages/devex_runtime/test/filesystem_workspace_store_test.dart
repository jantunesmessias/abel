import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late FileSystemWorkspaceStore store;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('devex-store-');
    store = FileSystemWorkspaceStore(workspaceRoot: temporary.path);
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  test('writes and verifies content-addressed blobs', () {
    final digest = store.withExclusiveLock(
      () => store.putBlob(utf8.encode('artifact')),
    );

    expect(utf8.decode(store.readBlob(digest)!), 'artifact');
    final index = store.withExclusiveLock(store.rebuildCasIndex);
    expect(index['blobs'], hasLength(1));
  });

  test('read of a missing blob is side-effect free', () {
    final before = temporary.listSync(recursive: true);
    final result = store.readBlob(Digest('sha256:${'0' * 64}'));

    expect(result, isNull);
    expect(temporary.listSync(recursive: true), hasLength(before.length));
  });

  test('atomic writes reject traversal', () {
    expect(
      () => store.atomicWrite('../escape', const <int>[1]),
      throwsArgumentError,
    );
  });

  test('rejects parent and final symlinks before any state write', () {
    final outside = Directory.systemTemp.createTempSync('devex-store-outside-');
    addTearDown(() => outside.deleteSync(recursive: true));
    Link(p.join(temporary.path, '.dart_tool')).createSync(outside.path);

    expect(
      () => store.withExclusiveLock(() => store.putBlob(const <int>[1])),
      throwsA(isA<FileSystemException>()),
    );
    expect(outside.listSync(), isEmpty);

    Link(p.join(temporary.path, '.dart_tool')).deleteSync();
    Directory(p.join(store.stateRoot, 'evidence')).createSync(recursive: true);
    final outsideFile = File(p.join(outside.path, 'outside.json'))
      ..writeAsStringSync('outside');
    Link(
      p.join(store.stateRoot, 'evidence', 'latest.json'),
    ).createSync(outsideFile.path);
    expect(
      () => store.readStateBytes('evidence/latest.json'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
