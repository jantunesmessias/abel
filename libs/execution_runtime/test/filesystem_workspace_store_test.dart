import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late FileSystemWorkspaceStore store;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('workspace-store-');
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

  test(
    'bounded state reads reject oversize before materializing the document',
    () {
      store.atomicWrite('bounded/state.bin', List<int>.filled(9, 1));
      expect(
        () => store.readStateBytesBounded('bounded/state.bin', maxBytes: 8),
        throwsStateError,
      );
      expect(
        store.readStateBytesBounded('bounded/state.bin', maxBytes: 9),
        List<int>.filled(9, 1),
      );
    },
  );

  test('bounded state and CAS reads fence growth at the reserved size', () {
    store.atomicWrite('bounded/growth.bin', const <int>[1, 2]);
    final stateFile = File(p.join(store.stateRoot, 'bounded', 'growth.bin'));
    var observedStateSize = -1;
    expect(
      () => store.readStateBytesBounded(
        'bounded/growth.bin',
        maxBytes: 16 * 1024 * 1024,
        beforeRead: (size) {
          observedStateSize = size;
          stateFile.writeAsBytesSync(List<int>.filled(1024 * 1024, 3));
        },
      ),
      throwsStateError,
    );
    expect(observedStateSize, 2);

    final digest = store.putBlob(const <int>[4, 5]);
    final blobFile = File(
      p.join(
        store.stateRoot,
        'cas',
        'sha256',
        digest.value.substring('sha256:'.length),
      ),
    );
    var observedBlobSize = -1;
    expect(
      () => store.readBlobBounded(
        digest,
        maxBytes: 16 * 1024 * 1024,
        beforeRead: (size) {
          observedBlobSize = size;
          blobFile.writeAsBytesSync(List<int>.filled(1024 * 1024, 6));
        },
      ),
      throwsStateError,
    );
    expect(observedBlobSize, 2);
  });

  test('rejects parent and final symlinks before any state write', () {
    final outside = Directory.systemTemp.createTempSync(
      'workspace-store-outside-',
    );
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
