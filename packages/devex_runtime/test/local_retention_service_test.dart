import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late FileSystemWorkspaceStore store;
  late DateTime now;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('devex-retention-');
    store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    now = DateTime.utc(2026, 8, 1, 12);
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  test('defaults are 10 GiB, seven days and 24-hour grace', () {
    const policy = LocalRetentionPolicy();
    expect(policy.quotaBytes, 10 * 1024 * 1024 * 1024);
    expect(policy.temporaryTtl, const Duration(days: 7));
    expect(policy.unreachableGrace, const Duration(hours: 24));
  });

  test(
    'mark/sweep preserves roots and releases, expires temp and honors grace',
    () {
      late final Digest reachable;
      late final Digest pinned;
      late final Digest unreachable;
      late final Digest temporaryOnly;
      store.withExclusiveLock(() {
        reachable = store.putBlob(utf8.encode('reachable'));
        pinned = store.putBlob(utf8.encode('release-pinned'));
        unreachable = store.putBlob(utf8.encode('unreachable'));
        temporaryOnly = store.putBlob(utf8.encode('temporary-only'));
        store.atomicWrite(
          'roots.json',
          utf8.encode(jsonEncode(<String, Object?>{'digest': reachable.value})),
        );
        store.atomicWrite(
          p.join(
            'releases',
            'sha256',
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'bundle.json',
          ),
          utf8.encode(jsonEncode(<String, Object?>{'artifact': pinned.value})),
        );
        final temporary = store.atomicWrite(
          'probe/temporary/report.json',
          utf8.encode(
            jsonEncode(<String, Object?>{'artifact': temporaryOnly.value}),
          ),
        );
        temporary.setLastModifiedSync(now.subtract(const Duration(days: 8)));
        store.rebuildCasIndex();
      });
      final service = LocalRetentionService(
        workspaceRoot: workspace.path,
        nowUtc: () => now,
      );

      final preview = service.run(apply: false);
      expect(preview.deletedBlobs, 0);
      expect(preview.deletedTemporaryFiles, 1);
      expect(store.readStateBytes('retention/sweep-v1.json'), isNull);

      final first = service.run(apply: true);
      expect(first.graceBlobs, 2);
      expect(first.deletedTemporaryFiles, 1);
      expect(store.readBlob(unreachable), isNotNull);
      expect(store.readBlob(temporaryOnly), isNotNull);

      now = now.add(const Duration(hours: 23));
      expect(service.run(apply: true).deletedBlobs, 0);
      now = now.add(const Duration(hours: 2));
      final swept = service.run(apply: true);

      expect(swept.deletedBlobs, 2);
      expect(swept.pinnedReleases, 1);
      expect(store.readBlob(unreachable), isNull);
      expect(store.readBlob(temporaryOnly), isNull);
      expect(store.readBlob(reachable), isNotNull);
      expect(store.readBlob(pinned), isNotNull);
    },
  );

  test('30-day corpus stays bounded while pinned release remains', () {
    late final Digest pinned;
    store.withExclusiveLock(() {
      pinned = store.putBlob(utf8.encode('permanent-release-artifact'));
      store.atomicWrite(
        p.join(
          'releases',
          'sha256',
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          'bundle.json',
        ),
        utf8.encode(jsonEncode(<String, Object?>{'artifact': pinned.value})),
      );
    });
    final service = LocalRetentionService(
      workspaceRoot: workspace.path,
      nowUtc: () => now,
      policy: const LocalRetentionPolicy(quotaBytes: 1024 * 1024),
    );

    for (var day = 0; day < 30; day++) {
      store.withExclusiveLock(() {
        store.putBlob(utf8.encode('unreachable-day-$day'));
      });
      service.run(apply: true);
      now = now.add(const Duration(days: 1));
    }
    final report = service.run(apply: true);
    final casFiles = Directory(
      p.join(store.stateRoot, 'cas', 'sha256'),
    ).listSync().whereType<File>().length;

    expect(report.quotaSatisfied, isTrue);
    expect(casFiles, lessThanOrEqualTo(2));
    expect(store.readBlob(pinned), isNotNull);
  });

  test(
    'an interrupted moved transaction is rolled back before a new sweep',
    () {
      late final Digest digest;
      store.withExclusiveLock(() {
        digest = store.putBlob(utf8.encode('recover-me'));
        store.rebuildCasIndex();
      });
      final name = digest.value.substring('sha256:'.length);
      final originRelative = p.join('cas', 'sha256', name);
      final trashRelative = p.join('.trash', 'retention-recovery', 'cas', name);
      final origin = File(p.join(store.stateRoot, originRelative));
      final trash = File(p.join(store.stateRoot, trashRelative));
      trash.parent.createSync(recursive: true);
      origin.renameSync(trash.path);
      store.atomicWrite(
        'retention/transaction-v1.json',
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'phase': 'moved',
            'moves': <Object?>[
              <String, Object?>{
                'origin': originRelative,
                'trash': trashRelative,
              },
            ],
            'nextSweep': <String, Object?>{},
          }),
        ),
      );

      final report = LocalRetentionService(
        workspaceRoot: workspace.path,
        nowUtc: () => now,
      ).run(apply: true);

      expect(report.recoveredTransaction, isTrue);
      expect(store.readBlob(digest), utf8.encode('recover-me'));
      expect(store.readStateBytes('retention/transaction-v1.json'), isNull);
      expect(
        Directory(p.join(store.stateRoot, '.trash')).existsSync(),
        isFalse,
      );
    },
  );
}
