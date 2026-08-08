import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FilesystemExperienceAuthoringStore', () {
    late Directory workspace;
    late FileSystemWorkspaceStore workspaceStore;
    late _Fixture fixture;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync(
        'workspace-experience-authoring-store-',
      );
      workspaceStore = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
      fixture = _Fixture();
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('persists a bounded draft and its base layout across restart', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );

      final opened = store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );

      expect(opened.resumed, isFalse);
      expect(opened.draft.toJson(), fixture.draft.toJson());
      expect(opened.ownerPrincipalId, fixture.owner);
      expect(
        store.requireBaseLayout(opened.storedDraft).toJson(),
        fixture.baseLayout.toJson(),
      );

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      final resumed = restarted.requireDraft(fixture.subject);
      expect(resumed.draft.toJson(), fixture.draft.toJson());
      expect(
        restarted.requireBaseLayout(resumed).digest,
        fixture.baseLayout.digest,
      );
    });

    test(
      'proves fd-relative CAS durability before the journal without leaking FDs',
      () {
        final fsyncTargets = <ExperienceAuthoringStateFsyncTarget>[];
        final writer = _RecordingStateWriter(
          DefaultExperienceAuthoringStateWriter(beforeFsync: fsyncTargets.add),
        );
        final store = FilesystemExperienceAuthoringStore(
          workspaceStore: workspaceStore,
          writer: writer,
        );
        final beforeDescriptors = _openDescriptors();

        store.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        );

        expect(writer.started, hasLength(2));
        expect(writer.completed, writer.started);
        expect(writer.completed.first, startsWith('cas/sha256/'));
        expect(
          writer.completed.last,
          FilesystemExperienceAuthoringStore.statePath,
        );
        expect(
          fsyncTargets.where(
            (target) =>
                target !=
                ExperienceAuthoringStateFsyncTarget.stateDirectoryParent,
          ),
          <ExperienceAuthoringStateFsyncTarget>[
            ExperienceAuthoringStateFsyncTarget.stagingFile,
            ExperienceAuthoringStateFsyncTarget.destinationParent,
            ExperienceAuthoringStateFsyncTarget.existingFile,
            ExperienceAuthoringStateFsyncTarget.existingParent,
            ExperienceAuthoringStateFsyncTarget.stagingFile,
            ExperienceAuthoringStateFsyncTarget.destinationParent,
          ],
        );
        expect(
          fsyncTargets.where(
            (target) =>
                target ==
                ExperienceAuthoringStateFsyncTarget.stateDirectoryParent,
          ),
          isNotEmpty,
        );
        expect(_openDescriptors(), beforeDescriptors);
      },
    );

    test(
      'restart re-proves a visible CAS after parent fsync failure before WAL',
      () {
        final firstFault = _FsyncFault()..failDestinationAt = 1;
        final failedStore = FilesystemExperienceAuthoringStore(
          workspaceStore: workspaceStore,
          writer: DefaultExperienceAuthoringStateWriter(
            beforeFsync: firstFault.call,
          ),
        );

        expect(
          () => failedStore.openOrResumeDraft(
            ownerPrincipalId: fixture.owner,
            draft: fixture.draft,
            baseLayout: fixture.baseLayout,
          ),
          throwsA(isA<ExperienceAuthoringStateDurabilityFailure>()),
        );
        expect(File(failedStore.stateFilePath).existsSync(), isFalse);

        final writer = _RecordingStateWriter(
          const DefaultExperienceAuthoringStateWriter(),
        );
        final restarted = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
          writer: writer,
        );
        final beforeDescriptors = _openDescriptors();

        restarted.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        );

        expect(writer.operations, hasLength(2));
        expect(writer.operations.first, startsWith('reprove:cas/sha256/'));
        expect(
          writer.operations.last,
          'write:${FilesystemExperienceAuthoringStore.statePath}',
        );
        expect(
          restarted.requireDraft(fixture.subject).draft.toJson(),
          fixture.draft.toJson(),
        );
        expect(_openDescriptors(), beforeDescriptors);
      },
    );

    test('shared CAS is re-proven before authoring WAL', () {
      final baseBytes = utf8.encode(
        '${const JcsCanonicalizer().canonicalize(fixture.baseLayout.toJson())}\n',
      );
      final sharedDigest = workspaceStore.putBlob(baseBytes);
      final writer = _RecordingStateWriter(
        const DefaultExperienceAuthoringStateWriter(),
      );
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: writer,
      );

      final opened = store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );

      expect(opened.baseLayoutBlobDigest, sharedDigest);
      expect(writer.operations, hasLength(2));
      expect(writer.operations.first, startsWith('reprove:cas/sha256/'));
      expect(
        writer.operations.last,
        'write:${FilesystemExperienceAuthoringStore.statePath}',
      );
    });

    test(
      'restart fails closed when existing journal durability is unproven',
      () {
        final initial = FilesystemExperienceAuthoringStore(
          workspaceStore: workspaceStore,
        );
        initial.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        );
        final journal = File(initial.stateFilePath);
        final beforeBytes = journal.readAsBytesSync();
        final beforeDescriptors = _openDescriptors();
        var existingParentCount = 0;
        final restarted = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
          writer: DefaultExperienceAuthoringStateWriter(
            beforeFsync: (target) {
              if (target ==
                  ExperienceAuthoringStateFsyncTarget.existingParent) {
                existingParentCount += 1;
              }
              if (existingParentCount == 2) {
                throw StateError('injected existing parent fsync failure');
              }
            },
          ),
        );

        expect(
          () => restarted.requireDraft(fixture.subject),
          throwsA(
            isA<ExperienceAuthoringStateDurabilityFailure>().having(
              (failure) => failure.code,
              'code',
              ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
            ),
          ),
        );
        expect(restarted.hasDurabilityUncertainty, isTrue);
        expect(journal.readAsBytesSync(), beforeBytes);
        expect(
          () => restarted.requireDraft(fixture.subject),
          throwsA(
            isA<ExperienceAuthoringStateDurabilityFailure>().having(
              (failure) => failure.code,
              'code',
              ExperienceAuthoringStateDurabilityFailureCode.unproven,
            ),
          ),
        );
        expect(_openDescriptors(), beforeDescriptors);
      },
    );

    test('restart re-proves journal CAS antecedents before the journal', () {
      final initial = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      initial.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final writer = _RecordingStateWriter(
        const DefaultExperienceAuthoringStateWriter(),
      );
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        writer: writer,
      );

      restarted.requireDraft(fixture.subject);

      expect(writer.operations, hasLength(2));
      expect(writer.operations.first, startsWith('reprove:cas/sha256/'));
      expect(
        writer.operations.last,
        'reprove:${FilesystemExperienceAuthoringStore.statePath}',
      );
    });

    test('writer rejects a symlink in an intermediate workspace component', () {
      final base = Directory(p.join(workspace.path, 'path-boundary'))
        ..createSync();
      final authorityParent = Directory(p.join(base.path, 'authority'))
        ..createSync();
      final nestedWorkspace = Directory(p.join(authorityParent.path, 'ws'))
        ..createSync();
      final nestedStore = FileSystemWorkspaceStore(
        workspaceRoot: nestedWorkspace.path,
      );
      final saved = Directory('${authorityParent.path}.saved');
      authorityParent.renameSync(saved.path);
      final attacker = Directory(p.join(base.path, 'attacker'))..createSync();
      Directory(p.join(attacker.path, 'ws')).createSync();
      Link(authorityParent.path).createSync(attacker.path);
      final beforeDescriptors = _openDescriptors();

      expect(
        () => const DefaultExperienceAuthoringStateWriter().write(
          workspaceStore: nestedStore,
          relativePath: 'probe/state.bin',
          bytes: const <int>[1, 2, 3],
        ),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
          ),
        ),
      );
      expect(
        Directory(p.join(attacker.path, 'ws', '.dart_tool')).existsSync(),
        isFalse,
      );
      expect(_openDescriptors(), beforeDescriptors);
    });

    test('writer rejects a workspace-root rename before first install', () {
      final saved = Directory('${workspace.path}.saved');
      var injected = false;
      final writer = DefaultExperienceAuthoringStateWriter(
        beforeFsync: (target) {
          if (injected ||
              target != ExperienceAuthoringStateFsyncTarget.stagingFile) {
            return;
          }
          injected = true;
          workspace.renameSync(saved.path);
          Directory(workspace.path).createSync();
        },
      );
      try {
        expect(
          () => writer.write(
            workspaceStore: workspaceStore,
            relativePath: 'probe/state.bin',
            bytes: const <int>[4, 5, 6],
          ),
          throwsA(
            isA<ExperienceAuthoringStateDurabilityFailure>().having(
              (failure) => failure.code,
              'code',
              ExperienceAuthoringStateDurabilityFailureCode.unproven,
            ),
          ),
        );
        expect(injected, isTrue);
        expect(
          File(
            p.join(workspace.path, '.dart_tool', 'probe', 'state.bin'),
          ).existsSync(),
          isFalse,
        );
        expect(
          File(
            p.join(saved.path, '.dart_tool', 'probe', 'state.bin'),
          ).existsSync(),
          isFalse,
        );
      } finally {
        if (workspace.existsSync()) workspace.deleteSync(recursive: true);
        if (saved.existsSync()) saved.renameSync(workspace.path);
      }
    });

    test('pre-rename failures retire their exact private staging inode', () {
      final beforeDescriptors = _openDescriptors();
      for (var attempt = 0; attempt < 3; attempt += 1) {
        final store = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
          writer: DefaultExperienceAuthoringStateWriter(
            beforeFsync: (target) {
              if (target == ExperienceAuthoringStateFsyncTarget.stagingFile) {
                throw StateError('injected pre-rename staging failure');
              }
            },
          ),
        );
        expect(
          () => store.openOrResumeDraft(
            ownerPrincipalId: fixture.owner,
            draft: fixture.draft,
            baseLayout: fixture.baseLayout,
          ),
          throwsA(isA<ExperienceAuthoringStateDurabilityFailure>()),
        );
        final stateRoot = Directory(store.workspaceStore.stateRoot);
        final stagingNames = stateRoot.existsSync()
            ? stateRoot
                  .listSync(recursive: true, followLinks: false)
                  .where(
                    (entity) =>
                        p.basename(entity.path).contains('.authoring-stage-'),
                  )
                  .toList()
            : const <FileSystemEntity>[];
        expect(stagingNames, isEmpty, reason: 'attempt $attempt');
        expect(File(store.stateFilePath).existsSync(), isFalse);
      }
      expect(_openDescriptors(), beforeDescriptors);
    });

    test('reproof rejects a basename replacement after opening the inode', () {
      final initial = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      initial.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final journal = File(initial.stateFilePath);
      final bytes = journal.readAsBytesSync();
      final displaced = File('${journal.path}.displaced');
      var existingParentCount = 0;
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        writer: DefaultExperienceAuthoringStateWriter(
          beforeFsync: (target) {
            if (target == ExperienceAuthoringStateFsyncTarget.existingParent) {
              existingParentCount += 1;
            }
            if (existingParentCount == 2) {
              journal.renameSync(displaced.path);
              journal.writeAsBytesSync(bytes, flush: true);
            }
          },
        ),
      );

      expect(
        () => restarted.requireDraft(fixture.subject),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          ),
        ),
      );
      expect(restarted.hasDurabilityUncertainty, isTrue);
      expect(journal.readAsBytesSync(), bytes);
      expect(displaced.readAsBytesSync(), bytes);
    });

    test(
      'reproof validates captured bytes before issuing their file fsync',
      () {
        final initial = FilesystemExperienceAuthoringStore(
          workspaceStore: workspaceStore,
        );
        initial.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        );
        final journal = File(initial.stateFilePath);
        final replacement = '${'x' * (journal.lengthSync() - 1)}\n';
        var existingFileCount = 0;
        final targets = <ExperienceAuthoringStateFsyncTarget>[];
        final restarted = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
          writer: DefaultExperienceAuthoringStateWriter(
            beforeFsync: (target) {
              targets.add(target);
              if (target == ExperienceAuthoringStateFsyncTarget.existingFile) {
                existingFileCount += 1;
                if (existingFileCount == 2) {
                  journal.writeAsStringSync(replacement);
                }
              }
            },
          ),
        );

        expect(
          () => restarted.requireDraft(fixture.subject),
          throwsA(
            isA<ExperienceAuthoringStateDurabilityFailure>().having(
              (failure) => failure.code,
              'code',
              ExperienceAuthoringStateDurabilityFailureCode.unproven,
            ),
          ),
        );
        expect(existingFileCount, 2);
        expect(targets.last, ExperienceAuthoringStateFsyncTarget.existingFile);
        expect(
          targets
              .where(
                (target) =>
                    target ==
                    ExperienceAuthoringStateFsyncTarget.existingParent,
              )
              .length,
          1,
        );
        expect(journal.readAsStringSync(), replacement);
        expect(restarted.hasDurabilityUncertainty, isTrue);
      },
    );

    test('CAS fsync failure cannot create a WAL authority', () {
      final fault = _FsyncFault();
      fault.failDestinationAt = 1;
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: DefaultExperienceAuthoringStateWriter(beforeFsync: fault.call),
      );
      final beforeDescriptors = _openDescriptors();

      expect(
        () => store.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        ),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          ),
        ),
      );

      expect(store.isDurabilityAvailable, isFalse);
      expect(File(store.stateFilePath).existsSync(), isFalse);
      expect(
        () => store.findDraft(fixture.subject),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          ),
        ),
      );
      expect(_openDescriptors(), beforeDescriptors);
    });

    test('journal parent fsync failure never returns a durable draft', () {
      final fault = _FsyncFault();
      fault.failDestinationAt = 2;
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: DefaultExperienceAuthoringStateWriter(beforeFsync: fault.call),
      );
      final beforeDescriptors = _openDescriptors();

      expect(
        () => store.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        ),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          ),
        ),
      );

      expect(store.isDurabilityAvailable, isFalse);
      expect(
        () => store.findDraft(fixture.subject),
        throwsA(isA<ExperienceAuthoringStateDurabilityFailure>()),
      );
      expect(_openDescriptors(), beforeDescriptors);
    });

    test(
      'journal updates exchange through one durable private previous slot',
      () {
        final store = FilesystemExperienceAuthoringStore(
          workspaceStore: workspaceStore,
        );
        store.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        );
        final journal = File(store.stateFilePath);
        final previousSlot = File(
          p.join(
            journal.parent.path,
            '.${p.basename(journal.path)}.authoring-previous',
          ),
        );
        final revisionZeroBytes = journal.readAsBytesSync();
        expect(previousSlot.existsSync(), isFalse);

        final moved = const LayoutDraftEngine().applyMove(
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
          input: LayoutMoveNodeInput(
            nodeInstanceId: NodeInstanceId('node'),
            toX: 120,
            toY: 240,
          ),
        );
        store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: fixture.draft.digest,
          draft: moved,
        );
        final revisionOneBytes = journal.readAsBytesSync();
        expect(previousSlot.readAsBytesSync(), revisionZeroBytes);
        expect(_permissionBits(previousSlot.path), 0x180);

        final reset = const LayoutDraftEngine().reset(
          draft: moved,
          baseLayout: fixture.baseLayout,
        );
        store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: moved.digest,
          draft: reset,
        );

        expect(previousSlot.readAsBytesSync(), revisionOneBytes);
        expect(
          journal.parent
              .listSync(followLinks: false)
              .where(
                (entity) =>
                    p.basename(entity.path).contains('.authoring-previous'),
              ),
          hasLength(1),
        );
        expect(
          journal.parent
              .listSync(followLinks: false)
              .where(
                (entity) =>
                    p.basename(entity.path).contains('.authoring-stage-'),
              ),
          isEmpty,
        );
      },
    );

    test('0644 journal mode is normalized without blocking later updates', () {
      final initial = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      initial.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final journal = File(initial.stateFilePath);
      expect(
        Process.runSync('chmod', <String>['644', journal.path]).exitCode,
        0,
      );

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      restarted.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final previousSlot = File(
        p.join(
          journal.parent.path,
          '.${p.basename(journal.path)}.authoring-previous',
        ),
      );
      expect(_permissionBits(previousSlot.path), 0x180);

      final reset = const LayoutDraftEngine().reset(
        draft: moved,
        baseLayout: fixture.baseLayout,
      );
      restarted.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: moved.digest,
        draft: reset,
      );
      expect(
        restarted.requireDraft(fixture.subject).draft.digest,
        reset.digest,
      );
      expect(_permissionBits(previousSlot.path), 0x180);
    });

    test('journal slot basename replacement is rejected before exchange', () {
      final initial = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      initial.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final journal = File(initial.stateFilePath);
      final journalBytes = journal.readAsBytesSync();
      final previousSlot = File(
        p.join(
          journal.parent.path,
          '.${p.basename(journal.path)}.authoring-previous',
        ),
      );
      final displacedSlot = File('${previousSlot.path}.displaced');
      var substituted = false;
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        writer: DefaultExperienceAuthoringStateWriter(
          beforeFsync: (target) {
            if (!substituted &&
                target == ExperienceAuthoringStateFsyncTarget.stagingFile) {
              substituted = true;
              previousSlot.renameSync(displacedSlot.path);
              previousSlot.writeAsBytesSync(const <int>[9, 8, 7]);
            }
          },
        ),
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );

      expect(
        () => restarted.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: fixture.draft.digest,
          draft: moved,
        ),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          ),
        ),
      );
      expect(substituted, isTrue);
      expect(journal.readAsBytesSync(), journalBytes);
      expect(previousSlot.readAsBytesSync(), const <int>[9, 8, 7]);
      expect(displacedSlot.existsSync(), isTrue);
    });

    test('restart proves a journal left installed by parent fsync failure', () {
      final initial = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      initial.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final journal = File(initial.stateFilePath);
      final oldBytes = journal.readAsBytesSync();
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      final faulted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        writer: DefaultExperienceAuthoringStateWriter(
          beforeFsync: (target) {
            if (target ==
                ExperienceAuthoringStateFsyncTarget.destinationParent) {
              throw StateError('injected post-exchange parent fsync failure');
            }
          },
        ),
      );

      expect(
        () => faulted.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: fixture.draft.digest,
          draft: moved,
        ),
        throwsA(isA<ExperienceAuthoringStateDurabilityFailure>()),
      );
      final previousSlot = File(
        p.join(
          journal.parent.path,
          '.${p.basename(journal.path)}.authoring-previous',
        ),
      );
      expect(previousSlot.readAsBytesSync(), oldBytes);

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      expect(
        restarted.requireDraft(fixture.subject).draft.digest,
        moved.digest,
      );
    });

    test('same owner resumes the exact mutated head without a write', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final journalBytes = File(store.stateFilePath).readAsBytesSync();

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      final resumed = restarted.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );

      expect(resumed.resumed, isTrue);
      expect(resumed.draft.toJson(), moved.toJson());
      expect(File(store.stateFilePath).readAsBytesSync(), journalBytes);
    });

    test('enforces one durable owner for a projection draft', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );

      expect(
        () =>
            FilesystemExperienceAuthoringStore(
              workspaceStore: FileSystemWorkspaceStore(
                workspaceRoot: workspace.path,
              ),
            ).openOrResumeDraft(
              ownerPrincipalId: AuthoringPrincipalId('another-author'),
              draft: fixture.draft,
              baseLayout: fixture.baseLayout,
            ),
        throwsA(
          isA<ExperienceAuthoringStoreFailure>().having(
            (error) => error.code,
            'code',
            ExperienceAuthoringStoreErrorCode.ownerConflict,
          ),
        ),
      );
    });

    test('uses the monotonic draft head as an ABA-safe CAS fence', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );

      final updated = store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      expect(updated.draft.digest, moved.digest);

      final reset = const LayoutDraftEngine().reset(
        draft: moved,
        baseLayout: fixture.baseLayout,
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: moved.digest,
        draft: reset,
      );
      expect(reset.candidateLayoutDigest, fixture.baseLayout.digest);
      expect(reset.digest, isNot(fixture.draft.digest));

      expect(
        () => store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: fixture.draft.digest,
          draft: moved,
        ),
        throwsA(
          isA<ExperienceAuthoringStoreFailure>()
              .having(
                (error) => error.code,
                'code',
                ExperienceAuthoringStoreErrorCode.staleDraft,
              )
              .having(
                (error) => error.currentDigest,
                'currentDigest',
                reset.digest,
              ),
        ),
      );
    });

    test('fails closed when the durable journal is not canonical', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final journal = File(store.stateFilePath);
      journal.writeAsStringSync(' ${journal.readAsStringSync()}');

      expect(
        () => FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        ).requireDraft(fixture.subject),
        throwsFormatException,
      );
    });

    test('rejects symlinked journal and CAS entries before reading', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      final opened = store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final external = File('${workspace.path}/external.json')
        ..writeAsStringSync('{}\n');
      final cas = File(
        '${workspaceStore.stateRoot}/cas/sha256/'
        '${opened.baseLayoutBlobDigest.value.substring('sha256:'.length)}',
      );
      cas.deleteSync();
      Link(cas.path).createSync(external.path);

      expect(
        () => FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        ).requireDraft(fixture.subject),
        throwsA(isA<FileSystemException>()),
      );

      Link(cas.path).deleteSync();
      final journal = File(store.stateFilePath);
      final journalCopy = File('${workspace.path}/journal-copy.json')
        ..writeAsBytesSync(journal.readAsBytesSync());
      journal.deleteSync();
      Link(journal.path).createSync(journalCopy.path);
      expect(
        () => FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        ).requireDraft(fixture.subject),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects an oversized existing CAS entry before materializing it', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      final opened = store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final cas = File(
        '${workspaceStore.stateRoot}/cas/sha256/'
        '${opened.baseLayoutBlobDigest.value.substring('sha256:'.length)}',
      );
      final handle = cas.openSync(mode: FileMode.write);
      try {
        handle.truncateSync(17 * 1024 * 1024);
      } finally {
        handle.closeSync();
      }

      expect(
        () => FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        ).requireDraft(fixture.subject),
        throwsStateError,
      );
    });

    test('a failed journal writer leaves the prior head recoverable', () {
      final writer = _FailingStateWriter();
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: writer,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      writer.failNext = true;

      expect(
        () => store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: fixture.draft.digest,
          draft: moved,
        ),
        throwsStateError,
      );
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      expect(
        restarted.requireDraft(fixture.subject).draft.digest,
        fixture.draft.digest,
      );
    });

    test('one transaction reuses its guard for nested store operations', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        guardTimeout: const Duration(milliseconds: 50),
      );

      final result = store.withTransaction((transaction) {
        final opened = transaction.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: fixture.draft,
          baseLayout: fixture.baseLayout,
        );
        final current = transaction.requireDraft(fixture.subject);
        final base = transaction.requireBaseLayout(current);
        return <Digest>[opened.draft.digest, current.draft.digest, base.digest];
      });

      expect(result, <Digest>[
        fixture.draft.digest,
        fixture.draft.digest,
        fixture.baseLayout.digest,
      ]);
    });

    test('rejects async transaction callbacks before invoking them', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final before = File(store.stateFilePath).readAsBytesSync();
      var invoked = false;

      expect(
        () => store.withTransaction<Future<void>>((transaction) async {
          invoked = true;
          transaction.closeDraft(
            ownerPrincipalId: fixture.owner,
            subject: fixture.subject,
            expectedDraftDigest: fixture.draft.digest,
          );
        }),
        throwsStateError,
      );

      expect(invoked, isFalse);
      expect(File(store.stateFilePath).readAsBytesSync(), before);
      expect(
        store.requireDraft(fixture.subject).draft.digest,
        fixture.draft.digest,
      );
    });

    test('expires a transaction facade when its synchronous scope ends', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      late ExperienceAuthoringStoreTransaction escaped;

      store.withTransaction<void>((transaction) {
        escaped = transaction;
      });

      expect(() => escaped.findDraft(fixture.subject), throwsStateError);
    });

    test('rejects a writer that returns without replacing the journal', () {
      final writer = _UnfaithfulStateWriter();
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: writer,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final before = File(store.stateFilePath).readAsBytesSync();
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      writer.nextBehavior = _UnfaithfulWriterBehavior.noOp;

      expect(
        () => store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: fixture.draft.digest,
          draft: moved,
        ),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.unproven,
          ),
        ),
      );
      expect(File(store.stateFilePath).readAsBytesSync(), before);

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      expect(
        restarted.requireDraft(fixture.subject).draft.digest,
        fixture.draft.digest,
      );
    });

    test('fails closed when a writer corrupts the committed journal', () {
      final writer = _UnfaithfulStateWriter();
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: writer,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      writer.nextBehavior = _UnfaithfulWriterBehavior.truncate;

      expect(
        () => store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: fixture.draft.digest,
          draft: moved,
        ),
        throwsA(isA<ExperienceAuthoringStateDurabilityFailure>()),
      );
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      expect(
        () => restarted.requireDraft(fixture.subject),
        throwsA(anyOf(isA<StateError>(), isA<FormatException>())),
      );
    });

    test('draft mutation quota reserves abandon and checkpoint capacity', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        maxJournalEntries: 2,
        maxDraftMutations: 1,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final reset = const LayoutDraftEngine().reset(
        draft: moved,
        baseLayout: fixture.baseLayout,
      );

      expect(
        () => store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: moved.digest,
          draft: reset,
        ),
        throwsA(
          isA<ExperienceAuthoringStoreFailure>().having(
            (error) => error.code,
            'code',
            ExperienceAuthoringStoreErrorCode.quotaExceeded,
          ),
        ),
      );

      final abandoned = store.abandonDraft(
        ownerPrincipalId: fixture.owner,
        receipt: LayoutDraftAbandonReceipt(
          id: LayoutDraftAbandonReceiptId('abandon-1'),
          requestId: AuthoringRequestId('request-abandon-1'),
          subject: fixture.subject,
          draftId: moved.id,
          finalDraftDigest: moved.digest,
          finalDraftRevision: moved.revision,
          sourceDigest: moved.baseSourceDigest,
          abandonedAt: DateTime.utc(2026, 8, 17),
        ),
      );
      expect(abandoned.finalDraftDigest, moved.digest);
      expect(store.findDraft(fixture.subject), isNull);

      final nextDraft = const LayoutDraftEngine().openDraft(
        id: LayoutDraftId('draft-2'),
        subject: fixture.subject,
        baseLayout: fixture.baseLayout,
        baseSourceDigest: fixture.draft.baseSourceDigest,
        contentSetDigest: fixture.draft.contentSetDigest,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: nextDraft,
        baseLayout: fixture.baseLayout,
      );

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        maxJournalEntries: 2,
        maxDraftMutations: 1,
      );
      expect(restarted.requireDraft(fixture.subject).draft.id, nextDraft.id);
      expect(
        restarted.abandonHistory(fixture.subject).single.digest,
        abandoned.digest,
      );
    });

    test('promotion CAS blobs are durable before their prepare WAL', () {
      final writer = _RecordingStateWriter(
        const DefaultExperienceAuthoringStateWriter(),
      );
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: writer,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      writer.started.clear();
      writer.completed.clear();
      final original = <int>[1, 2, 3];
      final candidate = <int>[4, 5, 6];

      store.preparePromotion(
        promotion: _promotion(
          fixture: fixture,
          draft: moved,
          original: original,
          candidate: candidate,
        ),
        originalSourceBytes: original,
        candidateSourceBytes: candidate,
      );

      expect(writer.started, hasLength(3));
      expect(writer.completed, writer.started);
      expect(writer.completed.take(2), everyElement(startsWith('cas/sha256/')));
      expect(
        writer.completed.last,
        FilesystemExperienceAuthoringStore.statePath,
      );
    });

    test('prepare WAL fsync failure stops after durable CAS blobs', () {
      final fault = _FsyncFault();
      final writer = _RecordingStateWriter(
        DefaultExperienceAuthoringStateWriter(beforeFsync: fault.call),
      );
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: writer,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      writer.started.clear();
      writer.completed.clear();
      fault.destinationCount = 0;
      fault.failDestinationAt = 3;
      final original = <int>[1, 2, 3];
      final candidate = <int>[14, 15, 16];
      final beforeDescriptors = _openDescriptors();

      expect(
        () => store.preparePromotion(
          promotion: _promotion(
            fixture: fixture,
            draft: moved,
            original: original,
            candidate: candidate,
          ),
          originalSourceBytes: original,
          candidateSourceBytes: candidate,
        ),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          ),
        ),
      );

      expect(writer.started, hasLength(3));
      expect(writer.completed, hasLength(2));
      expect(writer.completed, everyElement(startsWith('cas/sha256/')));
      expect(store.isDurabilityAvailable, isFalse);
      expect(
        store.pendingPromotions,
        throwsA(isA<ExperienceAuthoringStateDurabilityFailure>()),
      );
      expect(_openDescriptors(), beforeDescriptors);
    });

    test('promotion WAL and receipt survive checkpoint and restart', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        maxJournalEntries: 2,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final original = <int>[1, 2, 3];
      final candidate = <int>[4, 5, 6];
      final promotion = _promotion(
        fixture: fixture,
        draft: moved,
        original: original,
        candidate: candidate,
      );

      store.preparePromotion(
        promotion: promotion,
        originalSourceBytes: original,
        candidateSourceBytes: candidate,
      );
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        maxJournalEntries: 2,
      );
      final restartedPending = restarted.pendingPromotions().single;
      expect(restartedPending.intentId, 'promotion-1');
      expect(
        restartedPending.replaceProtocol,
        projectionLayoutPreservingSwapProtocol,
      );
      expect(
        restartedPending.replaceProviderKind,
        projectionLayoutLinuxX64SwapProvider,
      );
      expect(restartedPending.recoverySlot, promotion.recoverySlot);
      expect(
        restarted.readPromotionSourceBlob(promotion.candidateSourceBlobDigest),
        candidate,
      );

      final receipt = restarted.commitPromotion(intentId: 'promotion-1');
      expect(receipt.digest, promotion.receipt.digest);
      expect(restarted.findDraft(fixture.subject), isNull);
      expect(
        restarted.commitPromotion(intentId: 'promotion-1').digest,
        receipt.digest,
      );

      final restartedAgain = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        maxJournalEntries: 2,
      );
      expect(
        restartedAgain.promotionHistory(fixture.subject).single.digest,
        receipt.digest,
      );
    });

    test('restart re-proves every pending WAL CAS before its journal', () {
      final initial = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      initial.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      initial.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final promotion = _promotion(
        fixture: fixture,
        draft: moved,
        original: const <int>[1, 2, 3],
        candidate: const <int>[4, 5, 6],
      );
      initial.preparePromotion(
        promotion: promotion,
        originalSourceBytes: const <int>[1, 2, 3],
        candidateSourceBytes: const <int>[4, 5, 6],
      );
      final writer = _RecordingStateWriter(
        const DefaultExperienceAuthoringStateWriter(),
      );
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        writer: writer,
      );

      expect(restarted.pendingPromotions(), hasLength(1));

      expect(writer.operations, hasLength(4));
      expect(
        writer.operations.take(3),
        everyElement(startsWith('reprove:cas/sha256/')),
      );
      expect(
        writer.operations.last,
        'reprove:${FilesystemExperienceAuthoringStore.statePath}',
      );
    });

    test('promotion receipt is not returned before journal parent fsync', () {
      final fault = _FsyncFault();
      final writer = _RecordingStateWriter(
        DefaultExperienceAuthoringStateWriter(beforeFsync: fault.call),
      );
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        writer: writer,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      const original = <int>[1, 2, 3];
      const candidate = <int>[4, 5, 6];
      store.preparePromotion(
        promotion: _promotion(
          fixture: fixture,
          draft: moved,
          original: original,
          candidate: candidate,
        ),
        originalSourceBytes: original,
        candidateSourceBytes: candidate,
      );
      writer.started.clear();
      writer.completed.clear();
      fault.destinationCount = 0;
      fault.failDestinationAt = 1;

      expect(
        () => store.commitPromotion(intentId: 'promotion-1'),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          ),
        ),
      );

      expect(writer.started, <String>[
        FilesystemExperienceAuthoringStore.statePath,
      ]);
      expect(writer.completed, isEmpty);
      expect(store.hasDurabilityUncertainty, isTrue);
    });

    test('rehashed checkpoint rejects consumed grant changed to active', () {
      final authority = _writeAuthorityCheckpoint(
        workspaceStore: workspaceStore,
        fixture: fixture,
      );

      _mutateAndRehashCheckpoint(authority.journal, (payload) {
        final grants = payload['grants']! as List<Object?>;
        final grant = grants.single! as Map<String, Object?>;
        expect(grant['state'], StoredAuthoringGrantState.consumed.name);
        grant['state'] = StoredAuthoringGrantState.active.name;
      });

      _expectAuthorityCheckpointRejected(
        workspace: workspace,
        grantId: authority.grant.id,
        message: 'Effect attempt does not bind one consumed exact grant',
      );
    });

    test(
      'rehashed checkpoint rejects repointed or digest-tampered effect attempt',
      () {
        final authority = _writeAuthorityCheckpoint(
          workspaceStore: workspaceStore,
          fixture: fixture,
        );
        final baseline = authority.journal.readAsBytesSync();

        for (final mutation
            in <({String label, void Function(Map<String, Object?>) apply})>[
              (
                label: 'repointed grantId',
                apply: (attempt) {
                  attempt['grantId'] = 'grant-forged-repoint';
                },
              ),
              (
                label: 'forged grantDigest',
                apply: (attempt) {
                  attempt['grantDigest'] = Digest.semantic(
                    'forged-effect-grant-digest',
                  ).value;
                },
              ),
            ]) {
          authority.journal.writeAsBytesSync(baseline, flush: true);
          _mutateAndRehashCheckpoint(authority.journal, (payload) {
            final attempt = _checkpointAttempt(
              payload,
              authority.effectRequestId,
            );
            mutation.apply(attempt);
            _rehashStoredAttempt(attempt);
          });

          expect(
            () => FilesystemExperienceAuthoringStore(
              workspaceStore: FileSystemWorkspaceStore(
                workspaceRoot: workspace.path,
              ),
            ).findGrant(authority.grant.id),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                'Effect attempt does not bind one consumed exact grant',
              ),
            ),
            reason: mutation.label,
          );
        }
      },
    );

    test(
      'rehashed checkpoint rejects grant without exact successful issuance',
      () {
        final authority = _writeAuthorityCheckpoint(
          workspaceStore: workspaceStore,
          fixture: fixture,
        );

        _mutateAndRehashCheckpoint(authority.journal, (payload) {
          final attempts = payload['attempts']! as List<Object?>;
          attempts.removeWhere(
            (raw) =>
                (raw! as Map<String, Object?>)['requestId'] ==
                authority.grant.requestId.value,
          );
        });

        _expectAuthorityCheckpointRejected(
          workspace: workspace,
          grantId: authority.grant.id,
          message: 'Durable grant does not bind its exact issuance attempt',
        );
      },
    );

    test(
      'rehashed checkpoint rejects successful issuance without its grant',
      () {
        final authority = _writeAuthorityCheckpoint(
          workspaceStore: workspaceStore,
          fixture: fixture,
        );

        _mutateAndRehashCheckpoint(authority.journal, (payload) {
          final grants = payload['grants']! as List<Object?>;
          grants.clear();
          final attempts = payload['attempts']! as List<Object?>;
          attempts.removeWhere(
            (raw) =>
                (raw! as Map<String, Object?>)['requestId'] ==
                authority.effectRequestId.value,
          );
        });

        _expectAuthorityCheckpointRejected(
          workspace: workspace,
          grantId: authority.grant.id,
          message: 'Successful grant issuance has no exact durable grant',
        );
      },
    );

    test('rehashed journal cannot forge the preserving-swap binding', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final original = <int>[1, 2, 3];
      final candidate = <int>[4, 5, 6];
      store.preparePromotion(
        promotion: _promotion(
          fixture: fixture,
          draft: moved,
          original: original,
          candidate: candidate,
        ),
        originalSourceBytes: original,
        candidateSourceBytes: candidate,
      );
      final journal = File(store.stateFilePath);
      final document =
          jsonDecode(journal.readAsStringSync()) as Map<String, Object?>;
      final entries = document['entries']! as List<Object?>;
      final last = entries.last! as Map<String, Object?>;
      final payload = last['payload']! as Map<String, Object?>;
      final promotion = payload['promotion']! as Map<String, Object?>;
      promotion['recoverySlot'] = '.forged-independent-slot.stage';
      final withoutDigest = Map<String, Object?>.of(last)..remove('digest');
      last['digest'] = Digest.semantic(withoutDigest).value;
      journal.writeAsStringSync(
        '${const JcsCanonicalizer().canonicalize(document)}\n',
        flush: true,
      );

      expect(
        () => FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        ).pendingPromotions(),
        throwsFormatException,
      );
    });

    test('WAL without swap authority fails closed without inference', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final original = <int>[1, 2, 3];
      final candidate = <int>[4, 5, 6];
      store.preparePromotion(
        promotion: _promotion(
          fixture: fixture,
          draft: moved,
          original: original,
          candidate: candidate,
        ),
        originalSourceBytes: original,
        candidateSourceBytes: candidate,
      );
      final journal = File(store.stateFilePath);
      final document =
          jsonDecode(journal.readAsStringSync()) as Map<String, Object?>;
      final entries = document['entries']! as List<Object?>;
      final last = entries.last! as Map<String, Object?>;
      final payload = last['payload']! as Map<String, Object?>;
      final promotion = payload['promotion']! as Map<String, Object?>;
      promotion
        ..remove('replaceProtocol')
        ..remove('replaceProviderKind')
        ..remove('recoverySlot')
        ..remove('configurationAuthorityDigest')
        ..remove('sourceMetadataDigest');
      final withoutDigest = Map<String, Object?>.of(last)..remove('digest');
      last['digest'] = Digest.semantic(withoutDigest).value;
      journal.writeAsStringSync(
        '${const JcsCanonicalizer().canonicalize(document)}\n',
        flush: true,
      );

      expect(
        () => FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        ).pendingPromotions(),
        throwsFormatException,
      );
    });

    test('stored promotion rejects every non-exact swap authority', () {
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      for (final invalid in <StoredProjectionLayoutPromotion Function()>[
        () => _promotion(
          fixture: fixture,
          draft: moved,
          original: <int>[1],
          candidate: <int>[2],
          replaceProtocol: 'rename-v0',
        ),
        () => _promotion(
          fixture: fixture,
          draft: moved,
          original: <int>[1],
          candidate: <int>[2],
          replaceProviderKind: 'portable-rename',
        ),
        () => _promotion(
          fixture: fixture,
          draft: moved,
          original: <int>[1],
          candidate: <int>[2],
          recoverySlot: '.arbitrary.stage',
        ),
        () => _promotion(
          fixture: fixture,
          draft: moved,
          original: <int>[1],
          candidate: <int>[2],
          recoverySlot: '/tmp/absolute.stage',
        ),
        () => _promotion(
          fixture: fixture,
          draft: moved,
          original: <int>[1],
          candidate: <int>[2],
          recoverySlot: '../traversal.stage',
        ),
      ]) {
        expect(invalid, throwsArgumentError);
      }
    });

    test('pending promotion rejects an oversized tampered CAS blob', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      store.openOrResumeDraft(
        ownerPrincipalId: fixture.owner,
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: fixture.draft,
        baseLayout: fixture.baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 120,
          toY: 240,
        ),
      );
      store.replaceDraft(
        ownerPrincipalId: fixture.owner,
        expectedDraftDigest: fixture.draft.digest,
        draft: moved,
      );
      final promotion = _promotion(
        fixture: fixture,
        draft: moved,
        original: <int>[1, 2, 3],
        candidate: <int>[4, 5, 6],
      );
      store.preparePromotion(
        promotion: promotion,
        originalSourceBytes: const <int>[1, 2, 3],
        candidateSourceBytes: const <int>[4, 5, 6],
      );
      final candidateCas = File(
        '${workspaceStore.stateRoot}/cas/sha256/'
        '${promotion.candidateSourceDigest.value.substring('sha256:'.length)}',
      );
      final handle = candidateCas.openSync(mode: FileMode.write);
      try {
        handle.truncateSync(2 * 1024 * 1024);
      } finally {
        handle.closeSync();
      }

      expect(
        () => FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        ).pendingPromotions(),
        throwsStateError,
      );
    });

    test('promotion history keeps and pages the full receipt chain', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        maxJournalEntries: 4,
      );
      Digest? previousReceiptDigest;
      for (var index = 0; index < 17; index += 1) {
        final opened = const LayoutDraftEngine().openDraft(
          id: LayoutDraftId('draft-chain-$index'),
          subject: fixture.subject,
          baseLayout: fixture.baseLayout,
          baseSourceDigest: Digest.bytes(const <int>[1, 2, 3]),
          contentSetDigest: Digest.semantic('content-chain-$index'),
        );
        store.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: opened,
          baseLayout: fixture.baseLayout,
        );
        final moved = const LayoutDraftEngine().applyMove(
          draft: opened,
          baseLayout: fixture.baseLayout,
          input: LayoutMoveNodeInput(
            nodeInstanceId: NodeInstanceId('node'),
            toX: (120 + index).toDouble(),
            toY: 240,
          ),
        );
        store.replaceDraft(
          ownerPrincipalId: fixture.owner,
          expectedDraftDigest: opened.digest,
          draft: moved,
        );
        final promotion = _promotion(
          fixture: fixture,
          draft: moved,
          original: const <int>[1, 2, 3],
          candidate: <int>[4, 5, index],
          intentId: 'promotion-chain-$index',
          receiptId: 'receipt-chain-$index',
          sequence: index + 1,
          previousReceiptDigest: previousReceiptDigest,
        );
        store.preparePromotion(
          promotion: promotion,
          originalSourceBytes: const <int>[1, 2, 3],
          candidateSourceBytes: <int>[4, 5, index],
        );
        final receipt = store.commitPromotion(
          intentId: 'promotion-chain-$index',
        );
        previousReceiptDigest = receipt.digest;
      }

      final first = store.promotionHistoryPage(
        fixture.subject,
        offset: 0,
        limit: 16,
      );
      final second = store.promotionHistoryPage(
        fixture.subject,
        offset: 16,
        limit: 16,
      );
      expect(first.totalCount, 17);
      expect(
        first.receipts.map((receipt) => receipt.sequence),
        List<int>.generate(16, (index) => index + 1),
      );
      expect(first.previousPageReceiptDigest, isNull);
      expect(second.receipts.single.sequence, 17);
      expect(second.previousPageReceiptDigest, first.receipts.last.digest);

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        maxJournalEntries: 4,
      );
      expect(
        restarted
            .promotionHistoryPage(fixture.subject, offset: 0, limit: 1)
            .receipts
            .single
            .sequence,
        1,
      );
    });

    test('checkpoint retains more than one wire page of abandon receipts', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        maxJournalEntries: 3,
      );
      for (var index = 0; index < 17; index += 1) {
        final draft = const LayoutDraftEngine().openDraft(
          id: LayoutDraftId('draft-abandon-$index'),
          subject: fixture.subject,
          baseLayout: fixture.baseLayout,
          baseSourceDigest: Digest.semantic('source-abandon-$index'),
          contentSetDigest: Digest.semantic('content-abandon-$index'),
        );
        store.openOrResumeDraft(
          ownerPrincipalId: fixture.owner,
          draft: draft,
          baseLayout: fixture.baseLayout,
        );
        store.abandonDraft(
          ownerPrincipalId: fixture.owner,
          receipt: LayoutDraftAbandonReceipt(
            id: LayoutDraftAbandonReceiptId('abandon-chain-$index'),
            requestId: AuthoringRequestId('abandon-request-$index'),
            subject: fixture.subject,
            draftId: draft.id,
            finalDraftDigest: draft.digest,
            finalDraftRevision: draft.revision,
            sourceDigest: draft.baseSourceDigest,
            abandonedAt: DateTime.utc(2026, 8, 17, 3, index),
          ),
        );
      }

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
        maxJournalEntries: 3,
      );
      expect(restarted.abandonReceiptCount(fixture.subject), 17);
      expect(
        restarted
            .findAbandonReceipt(AuthoringRequestId('abandon-request-0'))!
            .id
            .value,
        'abandon-chain-0',
      );
    });

    test('kernel guard rejects an independent FD in the same process', () {
      var independentlyLocked = true;
      late final FilesystemExperienceAuthoringStore store;
      store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        guardBoundaryHook: (boundary) {
          if (boundary != ExperienceAuthoringGuardBoundary.afterAcquire) {
            return;
          }
          independentlyLocked = _tryIndependentFlock(store.guardFilePath);
        },
      );

      expect(store.findDraft(fixture.subject), isNull);

      expect(independentlyLocked, isFalse);
      expect(File(store.guardFilePath).existsSync(), isTrue);
    });

    test('guard remains private under a permissive process umask', () {
      int? directoryMode;
      int? guardMode;
      late final FilesystemExperienceAuthoringStore store;
      store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        guardBoundaryHook: (boundary) {
          if (boundary !=
              ExperienceAuthoringGuardBoundary.afterCreateBeforeWrite) {
            return;
          }
          directoryMode = _permissionBits(
            File(store.guardFilePath).parent.path,
          );
          guardMode = _permissionBits(store.guardFilePath);
        },
      );
      final beforeDescriptors = _openDescriptors();

      final result = _withUmask(0, () => store.findDraft(fixture.subject));

      expect(result, isNull);
      expect(directoryMode, 0x1c0);
      expect(guardMode, 0x180);
      expect(File(store.guardFilePath).existsSync(), isTrue);
      expect(File(store.guardFilePath).lengthSync(), 0);
      expect(_openDescriptors(), beforeDescriptors);
    });

    test('kernel guard releases after a locking process is killed', () async {
      final bootstrap = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      expect(bootstrap.findDraft(fixture.subject), isNull);
      final guard = File(bootstrap.guardFilePath);
      final locker = await Process.start('flock', <String>[
        '-F',
        '-x',
        guard.path,
        'sh',
        '-c',
        'echo acquired; exec sleep 30',
      ]);
      addTearDown(() {
        locker.kill(ProcessSignal.sigkill);
      });
      expect(await locker.stdout.transform(utf8.decoder).first, 'acquired\n');
      final blocked = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        guardTimeout: const Duration(milliseconds: 20),
      );

      expect(
        () => blocked.findDraft(fixture.subject),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.ioFailure,
          ),
        ),
      );

      expect(locker.kill(ProcessSignal.sigkill), isTrue);
      await locker.exitCode;
      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      final beforeDescriptors = _openDescriptors();

      expect(restarted.findDraft(fixture.subject), isNull);

      expect(guard.existsSync(), isTrue);
      expect(guard.lengthSync(), 0);
      expect(_openDescriptors(), beforeDescriptors);
    });

    test('non-empty predecessor guard fails closed without reclamation', () {
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
      );
      final guard = File(store.guardFilePath);
      guard.parent.createSync(recursive: true);
      guard.writeAsStringSync('999999999-dead-claim\n', flush: true);
      expect(
        Process.runSync('chmod', <String>['700', guard.parent.path]).exitCode,
        0,
      );
      expect(Process.runSync('chmod', <String>['600', guard.path]).exitCode, 0);

      expect(
        () => store.findDraft(fixture.subject),
        throwsA(
          isA<ExperienceAuthoringStateDurabilityFailure>().having(
            (failure) => failure.code,
            'code',
            ExperienceAuthoringStateDurabilityFailureCode.unsafeEntity,
          ),
        ),
      );

      expect(guard.readAsStringSync(), '999999999-dead-claim\n');
    });

    test('guard rejects a workspace-root rename before entering action', () {
      final saved = Directory('${workspace.path}.saved');
      var injected = false;
      final store = FilesystemExperienceAuthoringStore(
        workspaceStore: workspaceStore,
        guardBoundaryHook: (boundary) {
          if (injected ||
              boundary != ExperienceAuthoringGuardBoundary.afterAcquire) {
            return;
          }
          injected = true;
          workspace.renameSync(saved.path);
          Directory(workspace.path).createSync();
        },
      );
      try {
        expect(
          () => store.findDraft(fixture.subject),
          throwsA(
            isA<ExperienceAuthoringStateDurabilityFailure>().having(
              (failure) => failure.code,
              'code',
              ExperienceAuthoringStateDurabilityFailureCode.unproven,
            ),
          ),
        );
        expect(injected, isTrue);
        expect(Directory(workspace.path).listSync(), isEmpty);
      } finally {
        if (workspace.existsSync()) workspace.deleteSync(recursive: true);
        if (saved.existsSync()) saved.renameSync(workspace.path);
      }
    });

    for (final boundary in ExperienceAuthoringGuardBoundary.values) {
      test(
        'guard basename substitution at ${boundary.name} is fail-closed',
        () {
          final target = File(p.join(workspace.path, 'guard-target.txt'))
            ..writeAsStringSync('target-must-remain-untouched\n');
          var injected = false;
          late final FilesystemExperienceAuthoringStore store;
          store = FilesystemExperienceAuthoringStore(
            workspaceStore: workspaceStore,
            guardBoundaryHook: (observed) {
              if (injected || observed != boundary) return;
              injected = true;
              final guard = File(store.guardFilePath);
              guard.renameSync('${guard.path}.displaced');
              Link(guard.path).createSync(target.path);
            },
          );
          final beforeDescriptors = _openDescriptors();

          expect(
            () => store.findDraft(fixture.subject),
            throwsA(
              isA<ExperienceAuthoringStateDurabilityFailure>().having(
                (failure) => failure.code,
                'code',
                ExperienceAuthoringStateDurabilityFailureCode.unproven,
              ),
            ),
          );

          expect(injected, isTrue);
          expect(target.readAsStringSync(), 'target-must-remain-untouched\n');
          expect(
            FileSystemEntity.typeSync(store.guardFilePath, followLinks: false),
            FileSystemEntityType.link,
          );
          expect(File('${store.guardFilePath}.displaced').existsSync(), isTrue);
          expect(_openDescriptors(), beforeDescriptors);
        },
      );
    }
  });
}

({File journal, AuthoringActionGrant grant, AuthoringRequestId effectRequestId})
_writeAuthorityCheckpoint({
  required FileSystemWorkspaceStore workspaceStore,
  required _Fixture fixture,
}) {
  final store = FilesystemExperienceAuthoringStore(
    workspaceStore: workspaceStore,
    maxJournalEntries: 2,
  );
  final issuedAt = DateTime.utc(2026, 8, 17, 10);
  final intent = AuthoringGrantRequest(
    requestId: AuthoringRequestId('checkpoint-grant-request'),
    capabilityDigest: Digest.semantic('checkpoint-capability'),
    subject: fixture.subject,
    effect: AuthoringActionEffect.authoring,
    operation: AuthoringOperation.openDraft,
    expectedDigest: Digest.semantic('checkpoint-content-head'),
    expectedSourceDigest: fixture.draft.baseSourceDigest,
    payloadDigest: Digest.semantic('checkpoint-effect-payload'),
  );
  final grant = AuthoringActionGrant(
    id: AuthoringActionGrantId('checkpoint-grant'),
    requestId: intent.requestId,
    requestDigest: intent.digest,
    payloadDigest: intent.payloadDigest,
    authorityId: AuthoringAuthorityId('checkpoint-authority'),
    policyId: AuthoringPolicyId('checkpoint-policy'),
    principalId: fixture.owner,
    capabilityDigest: intent.capabilityDigest,
    subject: intent.subject,
    effect: intent.effect,
    operation: intent.operation,
    expectedDigest: intent.expectedDigest,
    expectedSourceDigest: intent.expectedSourceDigest,
    issuedAt: issuedAt,
    expiresAt: issuedAt.add(const Duration(minutes: 2)),
    singleUse: true,
  );
  final issuanceResult = AuthoringGrantResult(
    requestId: intent.requestId,
    grant: grant,
  );
  store.commitAtomic(
    ExperienceAuthoringAtomicCommit(
      attempt: StoredAuthoringAttempt(
        family: StoredAuthoringAttemptFamily.grantIssue,
        requestId: intent.requestId,
        requestDigest: intent.digest,
        payloadDigest: intent.payloadDigest,
        subject: intent.subject,
        effect: intent.effect,
        operation: intent.operation,
        grantId: null,
        grantDigest: null,
        isError: false,
        terminalJson: issuanceResult.toJson(),
        completedAt: issuedAt,
      ),
      issuedGrant: StoredAuthoringGrant(
        grant: grant,
        intentKind: storedAuthoringGrantIntentKind(intent).wireName,
        intentJson: storedAuthoringGrantIntentJson(intent),
        connectionEpoch: 'checkpoint-connection',
        state: StoredAuthoringGrantState.active,
        stateChangedAt: issuedAt,
      ),
    ),
  );

  final effectRequestId = AuthoringRequestId('checkpoint-effect-request');
  final effectCompletedAt = issuedAt.add(const Duration(seconds: 1));
  final effectError = ExperienceAuthoringError(
    code: ExperienceAuthoringErrorCode.unavailable,
    requestId: effectRequestId,
    subject: fixture.subject,
    operation: intent.operation,
  );
  store.commitAtomic(
    ExperienceAuthoringAtomicCommit(
      attempt: StoredAuthoringAttempt(
        family: StoredAuthoringAttemptFamily.draftOpen,
        requestId: effectRequestId,
        requestDigest: Digest.semantic('checkpoint-effect-request'),
        payloadDigest: grant.payloadDigest,
        subject: grant.subject,
        effect: grant.effect,
        operation: grant.operation,
        grantId: grant.id,
        grantDigest: grant.digest,
        isError: true,
        terminalJson: effectError.toJson(),
        completedAt: effectCompletedAt,
      ),
      consumedGrantId: grant.id,
    ),
  );

  final compactionRequestId = AuthoringRequestId(
    'checkpoint-compaction-request',
  );
  final compactionError = ExperienceAuthoringError(
    code: ExperienceAuthoringErrorCode.unavailable,
    requestId: compactionRequestId,
    subject: fixture.subject,
    operation: intent.operation,
  );
  store.commitAtomic(
    ExperienceAuthoringAtomicCommit(
      attempt: StoredAuthoringAttempt(
        family: StoredAuthoringAttemptFamily.grantIssue,
        requestId: compactionRequestId,
        requestDigest: Digest.semantic('checkpoint-compaction-request'),
        payloadDigest: Digest.semantic('checkpoint-compaction-payload'),
        subject: fixture.subject,
        effect: intent.effect,
        operation: intent.operation,
        grantId: null,
        grantDigest: null,
        isError: true,
        terminalJson: compactionError.toJson(),
        completedAt: effectCompletedAt.add(const Duration(seconds: 1)),
      ),
    ),
  );

  final journal = File(store.stateFilePath);
  final document =
      jsonDecode(journal.readAsStringSync()) as Map<String, Object?>;
  final entries = document['entries']! as List<Object?>;
  expect(entries, hasLength(1));
  expect((entries.single! as Map<String, Object?>)['type'], 'checkpoint');
  expect(store.findGrant(grant.id)!.state, StoredAuthoringGrantState.consumed);
  return (journal: journal, grant: grant, effectRequestId: effectRequestId);
}

void _mutateAndRehashCheckpoint(
  File journal,
  void Function(Map<String, Object?> payload) mutate,
) {
  final document =
      jsonDecode(journal.readAsStringSync()) as Map<String, Object?>;
  final entries = document['entries']! as List<Object?>;
  final checkpoint = entries.single! as Map<String, Object?>;
  expect(checkpoint['type'], 'checkpoint');
  final payload = checkpoint['payload']! as Map<String, Object?>;
  mutate(payload);
  final withoutDigest = Map<String, Object?>.of(checkpoint)..remove('digest');
  checkpoint['digest'] = Digest.semantic(withoutDigest).value;
  journal.writeAsStringSync(
    '${const JcsCanonicalizer().canonicalize(document)}\n',
    flush: true,
  );
}

Map<String, Object?> _checkpointAttempt(
  Map<String, Object?> payload,
  AuthoringRequestId requestId,
) {
  final attempts = payload['attempts']! as List<Object?>;
  return attempts.cast<Map<String, Object?>>().singleWhere(
    (attempt) => attempt['requestId'] == requestId.value,
  );
}

void _rehashStoredAttempt(Map<String, Object?> attempt) {
  final withoutDigest = Map<String, Object?>.of(attempt)..remove('digest');
  attempt['digest'] = Digest.semantic(withoutDigest).value;
}

void _expectAuthorityCheckpointRejected({
  required Directory workspace,
  required AuthoringActionGrantId grantId,
  required String message,
}) {
  expect(
    () => FilesystemExperienceAuthoringStore(
      workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
    ).findGrant(grantId),
    throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        message,
      ),
    ),
  );
}

StoredProjectionLayoutPromotion _promotion({
  required _Fixture fixture,
  required LayoutDraft draft,
  required List<int> original,
  required List<int> candidate,
  String intentId = 'promotion-1',
  String receiptId = 'receipt-1',
  int sequence = 1,
  Digest? previousReceiptDigest,
  String replaceProtocol = projectionLayoutPreservingSwapProtocol,
  String replaceProviderKind = projectionLayoutLinuxX64SwapProvider,
  String? recoverySlot,
}) {
  final originalDigest = Digest.bytes(original);
  final candidateDigest = Digest.bytes(candidate);
  return StoredProjectionLayoutPromotion(
    intentId: intentId,
    subject: fixture.subject,
    relativeSourcePath: 'projection-layout.json',
    replaceProtocol: replaceProtocol,
    replaceProviderKind: replaceProviderKind,
    recoverySlot:
        recoverySlot ??
        const FilesystemProjectionLayoutAtomicFileWriter().recoverySlot(
          subject: fixture.subject,
          relativeSourcePath: 'projection-layout.json',
        ),
    configurationAuthorityDigest: Digest.semantic(
      'fixture-workspace-configuration-authority',
    ),
    sourceMetadataDigest: Digest.semantic(
      'fixture-projection-layout-source-metadata',
    ),
    originalSourceBlobDigest: originalDigest,
    candidateSourceBlobDigest: candidateDigest,
    originalCompiledCorpusDigest: Digest.semantic(
      'compiled-original-$intentId',
    ),
    candidateCompiledCorpusDigest: Digest.semantic(
      'compiled-candidate-$intentId',
    ),
    receipt: ExperiencePromotionReceipt(
      id: ExperiencePromotionReceiptId(receiptId),
      sequence: sequence,
      previousReceiptDigest: previousReceiptDigest,
      subject: fixture.subject,
      draftId: draft.id,
      draftDigest: draft.digest,
      draftRevision: draft.revision,
      sourceDigest: originalDigest,
      resultSourceDigest: candidateDigest,
      previousContentSetDigest: draft.contentSetDigest,
      resultContentSetDigest: Digest.semantic('content-set-after-$intentId'),
      layoutDigest: draft.candidateLayoutDigest,
      changeSetId: ExperienceChangeSetId('changeset-1'),
      changeSetDigest: Digest.semantic('changeset-1'),
      reviewPacketId: ExperienceReviewPacketId('review-1'),
      reviewPacketDigest: Digest.semantic('review-1'),
      promotedAt: DateTime.utc(2026, 8, 17, 1),
    ),
    grantDigest: Digest.semantic('grant-$intentId'),
    preparedAt: DateTime.utc(2026, 8, 17),
  );
}

final class _RecordingStateWriter implements ExperienceAuthoringStateWriter {
  _RecordingStateWriter(this.delegate);

  final ExperienceAuthoringStateWriter delegate;
  final List<String> started = <String>[];
  final List<String> completed = <String>[];
  final List<String> operations = <String>[];

  @override
  bool get isDurabilitySupported => delegate.isDurabilitySupported;

  @override
  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  }) {
    started.add(relativePath);
    operations.add('write:$relativePath');
    final receipt = delegate.write(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
      expectedCurrentBytes: expectedCurrentBytes,
    );
    completed.add(relativePath);
    return receipt;
  }

  @override
  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
  }) {
    operations.add('reprove:$relativePath');
    return delegate.reproveExisting(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
    );
  }
}

final class _FsyncFault {
  int destinationCount = 0;
  int? failDestinationAt;

  void call(ExperienceAuthoringStateFsyncTarget target) {
    if (target != ExperienceAuthoringStateFsyncTarget.destinationParent) {
      return;
    }
    destinationCount += 1;
    if (destinationCount == failDestinationAt) {
      throw StateError('injected directory fsync failure');
    }
  }
}

final class _FailingStateWriter implements ExperienceAuthoringStateWriter {
  bool failNext = false;

  @override
  bool get isDurabilitySupported =>
      const DefaultExperienceAuthoringStateWriter().isDurabilitySupported;

  @override
  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  }) {
    if (failNext) {
      failNext = false;
      throw StateError('injected authoring journal failure');
    }
    return const DefaultExperienceAuthoringStateWriter().write(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
      expectedCurrentBytes: expectedCurrentBytes,
    );
  }

  @override
  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
  }) => const DefaultExperienceAuthoringStateWriter().reproveExisting(
    workspaceStore: workspaceStore,
    relativePath: relativePath,
    bytes: bytes,
  );
}

enum _UnfaithfulWriterBehavior { faithful, noOp, truncate }

final class _UnfaithfulStateWriter implements ExperienceAuthoringStateWriter {
  _UnfaithfulWriterBehavior nextBehavior = _UnfaithfulWriterBehavior.faithful;
  ExperienceAuthoringDurableWriteReceipt? _lastReceipt;

  @override
  bool get isDurabilitySupported =>
      const DefaultExperienceAuthoringStateWriter().isDurabilitySupported;

  @override
  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  }) {
    final behavior = nextBehavior;
    nextBehavior = _UnfaithfulWriterBehavior.faithful;
    if (behavior == _UnfaithfulWriterBehavior.noOp) return _lastReceipt!;
    final receipt = const DefaultExperienceAuthoringStateWriter().write(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
      expectedCurrentBytes: expectedCurrentBytes,
    );
    if (behavior == _UnfaithfulWriterBehavior.truncate) {
      File(
        p.join(workspaceStore.stateRoot, relativePath),
      ).writeAsBytesSync(const <int>[0], flush: true);
    }
    return _lastReceipt = receipt;
  }

  @override
  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
  }) => const DefaultExperienceAuthoringStateWriter().reproveExisting(
    workspaceStore: workspaceStore,
    relativePath: relativePath,
    bytes: bytes,
  );
}

int _openDescriptors() => Directory('/proc/self/fd').listSync().length;

bool _tryIndependentFlock(String path) {
  final library = ffi.DynamicLibrary.process();
  final open = library.lookupFunction<_OpenNative, _OpenDart>('open');
  final flock = library.lookupFunction<_FlockNative, _FlockDart>('flock');
  final close = library.lookupFunction<_CloseNative, _CloseDart>('close');
  final pointer = path.toNativeUtf8();
  final descriptor = open(pointer, 0x2 | 0x20000 | 0x80000, 0);
  calloc.free(pointer);
  if (descriptor < 0) return false;
  try {
    final acquired = flock(descriptor, 2 | 4) == 0;
    if (acquired) flock(descriptor, 8);
    return acquired;
  } finally {
    close(descriptor);
  }
}

int _permissionBits(String path) => FileStat.statSync(path).mode & 0xfff;

T _withUmask<T>(int mask, T Function() action) {
  final umask = ffi.DynamicLibrary.process()
      .lookupFunction<_UmaskNative, _UmaskDart>('umask');
  final previous = umask(mask);
  try {
    return action();
  } finally {
    umask(previous);
  }
}

typedef _UmaskNative = ffi.Uint32 Function(ffi.Uint32);
typedef _UmaskDart = int Function(int);
typedef _OpenNative =
    ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32, ffi.Uint32);
typedef _OpenDart = int Function(ffi.Pointer<Utf8>, int, int);
typedef _FlockNative = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _FlockDart = int Function(int, int);
typedef _CloseNative = ffi.Int32 Function(ffi.Int32);
typedef _CloseDart = int Function(int);

final class _Fixture {
  _Fixture() {
    draft = const LayoutDraftEngine().openDraft(
      id: LayoutDraftId('draft'),
      subject: subject,
      baseLayout: baseLayout,
      baseSourceDigest: Digest.bytes(<int>[1, 2, 3]),
      contentSetDigest: Digest.semantic('content-set'),
    );
  }

  final AuthoringPrincipalId owner = AuthoringPrincipalId('local-author');
  final AuthoringSubjectRef subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace'),
    applicationId: ApplicationId('app'),
    projectionId: ExperienceProjectionId('projection'),
  );
  final ProjectionLayoutManifest baseLayout = ProjectionLayoutManifest(
    topologyDigest: Digest.semantic('topology'),
    projectionId: ExperienceProjectionId('projection'),
    nodeFrames: <ProjectionNodeFrame>[
      ProjectionNodeFrame(
        nodeInstanceId: NodeInstanceId('node'),
        x: 10,
        y: 20,
        width: 300,
        height: 180,
      ),
    ],
    groups: const <ProjectionGroup>[],
    lanes: const <ProjectionLane>[],
    annotations: const <ProjectionAnnotation>[],
    camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
  );

  late final LayoutDraft draft;
}
