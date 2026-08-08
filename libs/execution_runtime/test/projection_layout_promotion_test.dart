import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _nativeSwapSubject = AuthoringSubjectRef(
  workspaceId: WorkspaceId('native-swap-workspace'),
  applicationId: ApplicationId('native-swap-app'),
  projectionId: ExperienceProjectionId('native-swap-projection'),
);

void main() {
  group('BoundedWorkspaceAuthoringLoader', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync(
        'workspace-bounded-authoring-',
      );
      _writeWorkspace(workspace);
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('rejects an oversized sparse source before parsing it', () {
      final layout = File(p.join(workspace.path, '.experience', 'layout.yaml'));
      final handle = layout.openSync(mode: FileMode.write);
      try {
        handle.truncateSync(const SafeAuthoringParser().maxSourceBytes + 1);
      } finally {
        handle.closeSync();
      }

      expect(
        () => const BoundedWorkspaceAuthoringLoader().load(
          startPath: workspace.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('detects growth between stat and the bounded read', () {
      var mutated = false;
      final loader = BoundedWorkspaceAuthoringLoader(
        beforeRead: (file, _) {
          if (!mutated && p.basename(file.path) == 'layout.yaml') {
            mutated = true;
            file.writeAsStringSync(' ', mode: FileMode.append, flush: true);
          }
        },
      );

      expect(
        () => loader.load(startPath: workspace.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(mutated, isTrue);
    });

    test('rejects links anywhere in the authoring corpus', () {
      final external = File(p.join(workspace.path, 'external.json'))
        ..writeAsStringSync('{}');
      Link(
        p.join(workspace.path, '.experience', 'linked.json'),
      ).createSync(external.path);

      expect(
        () => const BoundedWorkspaceAuthoringLoader().load(
          startPath: workspace.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects aggregate corpus bytes before opening any source', () {
      var openedSources = 0;
      final loader = BoundedWorkspaceAuthoringLoader(
        maxAggregateBytes: 32,
        beforeRead: (_, _) => openedSources += 1,
      );

      expect(
        () => loader.load(startPath: workspace.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(openedSources, 0);
    });

    test('bounds irrelevant filesystem entries before parsing', () {
      final content = Directory(p.join(workspace.path, '.experience'));
      for (var index = 0; index < 10; index += 1) {
        File(p.join(content.path, 'ignored-$index.txt')).writeAsStringSync('x');
      }
      var openedSources = 0;
      final loader = BoundedWorkspaceAuthoringLoader(
        maxFiles: 8,
        maxEntries: 8,
        maxDirectories: 8,
        beforeRead: (_, _) => openedSources += 1,
      );

      expect(
        () => loader.load(startPath: workspace.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(openedSources, 0);
    });
  });

  group('Linux x64 preserving source swap', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync(
        'workspace-preserving-source-swap-',
      );
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('real exchange preserves both files and closes every descriptor', () {
      const primitive = LinuxX64ProjectionLayoutPreservingSwap();
      if (!primitive.isSupported) return;
      final root = Directory(p.join(workspace.path, 'content'))..createSync();
      final destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      expect(
        Process.runSync('chmod', <String>['751', destination.path]).exitCode,
        0,
      );
      final authoritativeOwnerGroup = _ownerGroup(destination.path);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final candidate = utf8.encode('candidate\n');
      final firstStage = primitive.stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: candidate,
        maxBytes: 1024,
      );
      final slot = File(p.join(workspace.path, slotRelativePath));
      final original = destination.readAsBytesSync();
      expect(_permissionBits(slot.path), 0x1e9);
      expect(_ownerGroup(slot.path), authoritativeOwnerGroup);
      final descriptorsBefore = _openDescriptors();

      final installed = primitive.exchange(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        expectedDestinationDigest: Digest.bytes(original),
        expectedStagingDigest: Digest.bytes(candidate),
        expectedDestinationMetadataDigest: firstStage.sourceMetadataDigest,
        expectedStagingMetadataDigest: firstStage.sourceMetadataDigest,
        maxBytes: 1024,
      );

      expect(installed.installedDigest, Digest.bytes(candidate));
      expect(installed.displacedDigest, Digest.bytes(original));
      expect(destination.readAsBytesSync(), candidate);
      expect(slot.readAsBytesSync(), original);
      expect(_permissionBits(destination.path), 0x1e9);
      expect(_permissionBits(slot.path), 0x1e9);
      expect(_ownerGroup(destination.path), authoritativeOwnerGroup);
      expect(_ownerGroup(slot.path), authoritativeOwnerGroup);

      final restored = primitive.exchange(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        expectedDestinationDigest: Digest.bytes(candidate),
        expectedStagingDigest: Digest.bytes(original),
        expectedDestinationMetadataDigest: firstStage.sourceMetadataDigest,
        expectedStagingMetadataDigest: firstStage.sourceMetadataDigest,
        maxBytes: 1024,
      );
      expect(restored.installedDigest, Digest.bytes(original));
      expect(restored.displacedDigest, Digest.bytes(candidate));
      expect(destination.readAsBytesSync(), original);
      expect(slot.readAsBytesSync(), candidate);
      expect(_permissionBits(destination.path), 0x1e9);
      expect(_permissionBits(slot.path), 0x1e9);

      expect(
        Process.runSync('chmod', <String>['640', destination.path]).exitCode,
        0,
      );
      final noExecutableCandidate = utf8.encode('candidate-without-exec\n');
      final noExecutableStage = primitive.stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: noExecutableCandidate,
        maxBytes: 1024,
      );
      expect(_permissionBits(slot.path), 0x1a0);
      primitive.exchange(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        expectedDestinationDigest: Digest.bytes(original),
        expectedStagingDigest: Digest.bytes(noExecutableCandidate),
        expectedDestinationMetadataDigest:
            noExecutableStage.sourceMetadataDigest,
        expectedStagingMetadataDigest: noExecutableStage.sourceMetadataDigest,
        maxBytes: 1024,
      );
      expect(destination.readAsBytesSync(), noExecutableCandidate);
      expect(_permissionBits(destination.path), 0x1a0);
      expect(_permissionBits(slot.path), 0x1a0);
      expect(_openDescriptors(), descriptorsBefore);
    });

    test('stage rejects a source and private slot that alias one inode', () {
      const primitive = LinuxX64ProjectionLayoutPreservingSwap();
      if (!primitive.isSupported) return;
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final slot = File(p.join(workspace.path, slotRelativePath));
      slot.parent.createSync(recursive: true);
      expect(
        Process.runSync('chmod', <String>['700', slot.parent.path]).exitCode,
        0,
      );
      final original = utf8.encode('authoritative-slot-source\n');
      slot.writeAsBytesSync(original, flush: true);
      expect(Process.runSync('chmod', <String>['600', slot.path]).exitCode, 0);
      final descriptorsBefore = _openDescriptors();

      expect(
        () => primitive.stage(
          contentRoot: workspace.path,
          destinationRelativePath: slotRelativePath,
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          bytes: utf8.encode('must-not-truncate-source\n'),
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
          ),
        ),
      );

      expect(slot.readAsBytesSync(), original);
      expect(_openDescriptors(), descriptorsBefore);
    });

    for (final replacementKind in <String>['regular', 'symlink']) {
      test('stage rejects a $replacementKind rebound after parent fsync', () {
        if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) {
          return;
        }
        final root = Directory(
          p.join(workspace.path, 'stage-rebound-$replacementKind'),
        )..createSync();
        final destination = File(p.join(root.path, 'layout.json'))
          ..writeAsStringSync('original\n', flush: true);
        final slotRelativePath = projectionLayoutPromotionRecoverySlot(
          subject: _nativeSwapSubject,
          relativeSourcePath: 'layout.json',
        );
        final slot = File(p.join(workspace.path, slotRelativePath));
        final detached = File('${slot.path}.detached');
        final target = File(p.join(workspace.path, 'stage-rebound-target'))
          ..writeAsStringSync('target-must-remain-untouched\n');
        var injected = false;
        final primitive = LinuxX64ProjectionLayoutPreservingSwap(
          beforeFsync: (observed) {
            if (injected ||
                observed !=
                    ProjectionLayoutPreservingSwapFsyncTarget.stagingParent) {
              return;
            }
            injected = true;
            slot.renameSync(detached.path);
            if (replacementKind == 'regular') {
              slot.writeAsStringSync('third-party\n', flush: true);
            } else {
              Link(slot.path).createSync(target.path);
            }
          },
        );
        final descriptorsBefore = _openDescriptors();

        expect(
          () => primitive.stage(
            contentRoot: root.path,
            destinationRelativePath: 'layout.json',
            workspaceRoot: workspace.path,
            stagingRelativePath: slotRelativePath,
            bytes: utf8.encode('candidate\n'),
            maxBytes: 1024,
          ),
          throwsA(isA<ProjectionLayoutPreservingSwapFailure>()),
        );

        expect(injected, isTrue);
        expect(destination.readAsStringSync(), 'original\n');
        expect(detached.readAsStringSync(), 'candidate\n');
        if (replacementKind == 'regular') {
          expect(slot.readAsStringSync(), 'third-party\n');
        } else {
          expect(Link(slot.path).targetSync(), target.path);
          expect(target.readAsStringSync(), 'target-must-remain-untouched\n');
        }
        expect(_openDescriptors(), descriptorsBefore);
      });
    }

    test('in-place candidate mutation is rejected before exchange', () {
      if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) return;
      final root = Directory(p.join(workspace.path, 'candidate-mutation'))
        ..createSync();
      final destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      const candidateText = 'candidate\n';
      final staged = const LinuxX64ProjectionLayoutPreservingSwap().stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: utf8.encode(candidateText),
        maxBytes: 1024,
      );
      final slot = File(p.join(workspace.path, slotRelativePath));
      var injected = false;
      final primitive = LinuxX64ProjectionLayoutPreservingSwap(
        beforeExchangeSyscall: () {
          injected = true;
          slot.writeAsStringSync('mutated-candidate\n', flush: true);
        },
      );
      final descriptorsBefore = _openDescriptors();

      expect(
        () => primitive.exchange(
          contentRoot: root.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
          expectedStagingDigest: Digest.bytes(utf8.encode(candidateText)),
          expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
          expectedStagingMetadataDigest: staged.sourceMetadataDigest,
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.ioFailure,
          ),
        ),
      );

      expect(injected, isTrue);
      expect(destination.readAsStringSync(), 'original\n');
      expect(slot.readAsStringSync(), 'mutated-candidate\n');
      expect(_openDescriptors(), descriptorsBefore);
    });

    test('content-root rename before exchange is rejected before syscall', () {
      if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) return;
      final root = Directory(p.join(workspace.path, 'root-rebind-pre'))
        ..createSync();
      final detachedRoot = Directory('${root.path}.detached');
      File(
        p.join(root.path, 'layout.json'),
      ).writeAsStringSync('original\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final staged = const LinuxX64ProjectionLayoutPreservingSwap().stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: utf8.encode('candidate\n'),
        maxBytes: 1024,
      );
      var injected = false;
      final primitive = LinuxX64ProjectionLayoutPreservingSwap(
        beforeExchangeSyscall: () {
          injected = true;
          root.renameSync(detachedRoot.path);
          root.createSync();
          File(
            p.join(root.path, 'layout.json'),
          ).writeAsStringSync('replacement-root\n', flush: true);
        },
      );

      expect(
        () => primitive.exchange(
          contentRoot: root.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
          expectedStagingDigest: Digest.bytes(utf8.encode('candidate\n')),
          expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
          expectedStagingMetadataDigest: staged.sourceMetadataDigest,
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.ioFailure,
          ),
        ),
      );

      expect(injected, isTrue);
      expect(
        File(p.join(detachedRoot.path, 'layout.json')).readAsStringSync(),
        'original\n',
      );
      expect(
        File(p.join(root.path, 'layout.json')).readAsStringSync(),
        'replacement-root\n',
      );
      expect(
        File(p.join(workspace.path, slotRelativePath)).readAsStringSync(),
        'candidate\n',
      );
    });

    test('content-root rename after exchange preserves pair as unknown', () {
      if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) return;
      final root = Directory(p.join(workspace.path, 'root-rebind-post'))
        ..createSync();
      final detachedRoot = Directory('${root.path}.detached');
      File(
        p.join(root.path, 'layout.json'),
      ).writeAsStringSync('original\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final staged = const LinuxX64ProjectionLayoutPreservingSwap().stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: utf8.encode('candidate\n'),
        maxBytes: 1024,
      );
      var injected = false;
      final primitive = LinuxX64ProjectionLayoutPreservingSwap(
        beforeFsync: (target) {
          if (injected ||
              target !=
                  ProjectionLayoutPreservingSwapFsyncTarget.destinationParent) {
            return;
          }
          injected = true;
          root.renameSync(detachedRoot.path);
          root.createSync();
          File(
            p.join(root.path, 'layout.json'),
          ).writeAsStringSync('replacement-root\n', flush: true);
        },
      );

      expect(
        () => primitive.exchange(
          contentRoot: root.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
          expectedStagingDigest: Digest.bytes(utf8.encode('candidate\n')),
          expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
          expectedStagingMetadataDigest: staged.sourceMetadataDigest,
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
          ),
        ),
      );

      expect(injected, isTrue);
      expect(
        File(p.join(detachedRoot.path, 'layout.json')).readAsStringSync(),
        'candidate\n',
      );
      expect(
        File(p.join(workspace.path, slotRelativePath)).readAsStringSync(),
        'original\n',
      );
      expect(
        File(p.join(root.path, 'layout.json')).readAsStringSync(),
        'replacement-root\n',
      );
    });

    test('post-swap parent callback mutation remains outcome-unknown', () {
      if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) return;
      final root = Directory(p.join(workspace.path, 'post-swap-parent-hook'))
        ..createSync();
      final destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final staged = const LinuxX64ProjectionLayoutPreservingSwap().stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: utf8.encode('candidate\n'),
        maxBytes: 1024,
      );
      final slot = File(p.join(workspace.path, slotRelativePath));
      var injected = false;
      final primitive = LinuxX64ProjectionLayoutPreservingSwap(
        beforeFsync: (target) {
          if (injected ||
              target !=
                  ProjectionLayoutPreservingSwapFsyncTarget.destinationParent) {
            return;
          }
          injected = true;
          slot.writeAsStringSync('post-swap-third-party\n', flush: true);
        },
      );

      expect(
        () => primitive.exchange(
          contentRoot: root.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
          expectedStagingDigest: Digest.bytes(utf8.encode('candidate\n')),
          expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
          expectedStagingMetadataDigest: staged.sourceMetadataDigest,
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
          ),
        ),
      );

      expect(injected, isTrue);
      expect(destination.readAsStringSync(), 'candidate\n');
      expect(slot.readAsStringSync(), 'post-swap-third-party\n');
    });

    for (final replacementKind in <String>['directory', 'symlink']) {
      test(
        'post-swap $replacementKind slot substitution is never exchanged back',
        () {
          if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) {
            return;
          }
          final root = Directory(
            p.join(workspace.path, 'post-swap-slot-$replacementKind'),
          )..createSync();
          final destination = File(p.join(root.path, 'layout.json'))
            ..writeAsStringSync('original\n', flush: true);
          final slotRelativePath = projectionLayoutPromotionRecoverySlot(
            subject: _nativeSwapSubject,
            relativeSourcePath: 'layout.json',
          );
          final staged = const LinuxX64ProjectionLayoutPreservingSwap().stage(
            contentRoot: root.path,
            destinationRelativePath: 'layout.json',
            workspaceRoot: workspace.path,
            stagingRelativePath: slotRelativePath,
            bytes: utf8.encode('candidate\n'),
            maxBytes: 1024,
          );
          final slot = File(p.join(workspace.path, slotRelativePath));
          final target = File(p.join(workspace.path, 'post-swap-target'))
            ..writeAsStringSync('target-must-remain-untouched\n');
          var injected = false;
          final primitive = LinuxX64ProjectionLayoutPreservingSwap(
            afterExchangeSyscall: () {
              injected = true;
              slot.deleteSync();
              if (replacementKind == 'directory') {
                Directory(slot.path).createSync();
              } else {
                Link(slot.path).createSync(target.path);
              }
            },
          );

          expect(
            () => primitive.exchange(
              contentRoot: root.path,
              destinationRelativePath: 'layout.json',
              workspaceRoot: workspace.path,
              stagingRelativePath: slotRelativePath,
              expectedDestinationDigest: Digest.bytes(
                utf8.encode('original\n'),
              ),
              expectedStagingDigest: Digest.bytes(utf8.encode('candidate\n')),
              expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
              expectedStagingMetadataDigest: staged.sourceMetadataDigest,
              maxBytes: 1024,
            ),
            throwsA(
              isA<ProjectionLayoutPreservingSwapFailure>().having(
                (failure) => failure.code,
                'code',
                ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
              ),
            ),
          );

          expect(injected, isTrue);
          expect(destination.readAsStringSync(), 'candidate\n');
          if (replacementKind == 'directory') {
            expect(
              FileSystemEntity.typeSync(slot.path, followLinks: false),
              FileSystemEntityType.directory,
            );
          } else {
            expect(Link(slot.path).targetSync(), target.path);
            expect(target.readAsStringSync(), 'target-must-remain-untouched\n');
          }
        },
      );
    }

    test('fsync call order fences stage before both exchanged directories', () {
      final targets = <ProjectionLayoutPreservingSwapFsyncTarget>[];
      final primitive = LinuxX64ProjectionLayoutPreservingSwap(
        beforeFsync: targets.add,
      );
      if (!primitive.isSupported) return;
      final root = Directory(p.join(workspace.path, 'content'))..createSync();
      final destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final candidate = utf8.encode('candidate\n');

      final staged = primitive.stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: candidate,
        maxBytes: 1024,
      );
      expect(
        targets.sublist(targets.length - 2),
        <ProjectionLayoutPreservingSwapFsyncTarget>[
          ProjectionLayoutPreservingSwapFsyncTarget.stagingFile,
          ProjectionLayoutPreservingSwapFsyncTarget.stagingParent,
        ],
      );
      expect(
        targets,
        contains(
          ProjectionLayoutPreservingSwapFsyncTarget.privateDirectoryParent,
        ),
      );

      targets.clear();
      primitive.exchange(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
        expectedStagingDigest: Digest.bytes(candidate),
        expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
        expectedStagingMetadataDigest: staged.sourceMetadataDigest,
        maxBytes: 1024,
      );
      expect(targets, <ProjectionLayoutPreservingSwapFsyncTarget>[
        ProjectionLayoutPreservingSwapFsyncTarget.stagingFile,
        ProjectionLayoutPreservingSwapFsyncTarget.destinationFile,
        ProjectionLayoutPreservingSwapFsyncTarget.destinationParent,
        ProjectionLayoutPreservingSwapFsyncTarget.stagingParent,
      ]);
      expect(destination.readAsBytesSync(), candidate);
    });

    test('every native fsync failure preserves a recoverable file pair', () {
      const stageTargets = <ProjectionLayoutPreservingSwapFsyncTarget>[
        ProjectionLayoutPreservingSwapFsyncTarget.privateDirectoryParent,
        ProjectionLayoutPreservingSwapFsyncTarget.stagingFile,
        ProjectionLayoutPreservingSwapFsyncTarget.stagingParent,
      ];
      const exchangeTargets = <ProjectionLayoutPreservingSwapFsyncTarget>[
        ProjectionLayoutPreservingSwapFsyncTarget.stagingFile,
        ProjectionLayoutPreservingSwapFsyncTarget.destinationFile,
        ProjectionLayoutPreservingSwapFsyncTarget.destinationParent,
        ProjectionLayoutPreservingSwapFsyncTarget.stagingParent,
      ];
      if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) return;

      for (final target in stageTargets) {
        final caseRoot = Directory(
          p.join(workspace.path, 'stage-${target.name}'),
        )..createSync();
        final content = Directory(p.join(caseRoot.path, 'content'))
          ..createSync();
        final destination = File(p.join(content.path, 'layout.json'))
          ..writeAsStringSync('original\n', flush: true);
        var failed = false;
        final primitive = LinuxX64ProjectionLayoutPreservingSwap(
          beforeFsync: (observed) {
            if (!failed && observed == target) {
              failed = true;
              throw StateError('injected ${target.name} failure');
            }
          },
        );
        final descriptorsBefore = _openDescriptors();
        expect(
          () => primitive.stage(
            contentRoot: content.path,
            destinationRelativePath: 'layout.json',
            workspaceRoot: caseRoot.path,
            stagingRelativePath: projectionLayoutPromotionRecoverySlot(
              subject: _nativeSwapSubject,
              relativeSourcePath: 'layout.json',
            ),
            bytes: utf8.encode('candidate\n'),
            maxBytes: 1024,
          ),
          throwsA(
            isA<ProjectionLayoutPreservingSwapFailure>().having(
              (failure) => failure.code,
              'code',
              ProjectionLayoutPreservingSwapFailureCode.ioFailure,
            ),
          ),
          reason: target.name,
        );
        expect(destination.readAsStringSync(), 'original\n');
        expect(failed, isTrue);
        expect(_openDescriptors(), descriptorsBefore);
      }

      for (final target in exchangeTargets) {
        final caseRoot = Directory(
          p.join(workspace.path, 'exchange-${target.name}'),
        )..createSync();
        final content = Directory(p.join(caseRoot.path, 'content'))
          ..createSync();
        final destination = File(p.join(content.path, 'layout.json'))
          ..writeAsStringSync('original\n', flush: true);
        final slotRelativePath = projectionLayoutPromotionRecoverySlot(
          subject: _nativeSwapSubject,
          relativeSourcePath: 'layout.json',
        );
        final candidate = utf8.encode('candidate\n');
        final staged = const LinuxX64ProjectionLayoutPreservingSwap().stage(
          contentRoot: content.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: caseRoot.path,
          stagingRelativePath: slotRelativePath,
          bytes: candidate,
          maxBytes: 1024,
        );
        final slot = File(p.join(caseRoot.path, slotRelativePath));
        var failed = false;
        final primitive = LinuxX64ProjectionLayoutPreservingSwap(
          beforeFsync: (observed) {
            if (!failed && observed == target) {
              failed = true;
              throw StateError('injected ${target.name} failure');
            }
          },
        );
        final descriptorsBefore = _openDescriptors();
        final failedAfterExchange =
            target ==
                ProjectionLayoutPreservingSwapFsyncTarget.destinationParent ||
            target == ProjectionLayoutPreservingSwapFsyncTarget.stagingParent;

        expect(
          () => primitive.exchange(
            contentRoot: content.path,
            destinationRelativePath: 'layout.json',
            workspaceRoot: caseRoot.path,
            stagingRelativePath: slotRelativePath,
            expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
            expectedStagingDigest: Digest.bytes(candidate),
            expectedDestinationMetadataDigest: staged.sourceMetadataDigest,
            expectedStagingMetadataDigest: staged.sourceMetadataDigest,
            maxBytes: 1024,
          ),
          throwsA(
            isA<ProjectionLayoutPreservingSwapFailure>().having(
              (failure) => failure.code,
              'code',
              failedAfterExchange
                  ? ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown
                  : ProjectionLayoutPreservingSwapFailureCode.ioFailure,
            ),
          ),
          reason: target.name,
        );
        expect(
          destination.readAsBytesSync(),
          failedAfterExchange ? candidate : utf8.encode('original\n'),
        );
        expect(
          slot.readAsBytesSync(),
          failedAfterExchange ? utf8.encode('original\n') : candidate,
        );
        expect(failed, isTrue);
        expect(_openDescriptors(), descriptorsBefore);
      }
    });

    test('post-comparison edit is displaced, detected, and restored', () {
      var injected = false;
      late final File destination;
      final primitive = LinuxX64ProjectionLayoutPreservingSwap(
        beforeExchangeSyscall: () {
          if (injected) return;
          injected = true;
          destination.writeAsStringSync('third-party\n', flush: true);
        },
      );
      if (!primitive.isSupported) return;
      final root = Directory(p.join(workspace.path, 'content'))..createSync();
      destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final writer = FilesystemProjectionLayoutAtomicFileWriter(
        maxBytes: 1024,
        swapPrimitive: primitive,
      );
      final candidate = utf8.encode('candidate\n');
      final staged = writer.stage(
        workspaceRoot: workspace.path,
        contentRoot: root.path,
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
        bytes: candidate,
      );
      final descriptorsBefore = _openDescriptors();

      expect(
        () => writer.replace(
          staged,
          expectedCurrentDigest: Digest.bytes(utf8.encode('original\n')),
        ),
        throwsA(isA<ProjectionLayoutSourceConflict>()),
      );

      expect(destination.readAsStringSync(), 'third-party\n');
      expect(File(staged.stagingPath).readAsBytesSync(), candidate);
      expect(injected, isTrue);
      expect(_openDescriptors(), descriptorsBefore);
    });

    for (final replacementKind in <String>['directory', 'symlink']) {
      test(
        'raw exchange-back restores a displaced $replacementKind without following it',
        () {
          if (!const LinuxX64ProjectionLayoutPreservingSwap().isSupported) {
            return;
          }
          final root = Directory(
            p.join(workspace.path, 'content-unsafe-$replacementKind'),
          )..createSync();
          final destination = File(p.join(root.path, 'layout.json'))
            ..writeAsStringSync('original\n', flush: true);
          final movedOriginal = File(p.join(root.path, 'original-moved.json'));
          final target = File(p.join(root.path, 'symlink-target.txt'));
          var injected = false;
          final primitive = LinuxX64ProjectionLayoutPreservingSwap(
            beforeExchangeSyscall: () {
              if (injected) return;
              injected = true;
              destination.renameSync(movedOriginal.path);
              if (replacementKind == 'directory') {
                Directory(destination.path).createSync();
              } else {
                target.writeAsStringSync('target-must-remain-untouched\n');
                Link(destination.path).createSync(target.path);
              }
            },
          );
          final writer = FilesystemProjectionLayoutAtomicFileWriter(
            maxBytes: 1024,
            swapPrimitive: primitive,
          );
          final candidate = utf8.encode('candidate\n');
          final staged = writer.stage(
            workspaceRoot: workspace.path,
            contentRoot: root.path,
            subject: _nativeSwapSubject,
            relativeSourcePath: 'layout.json',
            bytes: candidate,
          );
          final descriptorsBefore = _openDescriptors();

          expect(
            () => writer.replace(
              staged,
              expectedCurrentDigest: Digest.bytes(utf8.encode('original\n')),
            ),
            throwsA(
              isA<ProjectionLayoutPreservingSwapFailure>().having(
                (failure) => failure.code,
                'code',
                ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
              ),
            ),
          );

          expect(injected, isTrue);
          expect(movedOriginal.readAsStringSync(), 'original\n');
          expect(File(staged.stagingPath).readAsBytesSync(), candidate);
          if (replacementKind == 'directory') {
            expect(
              FileSystemEntity.typeSync(destination.path, followLinks: false),
              FileSystemEntityType.directory,
            );
          } else {
            expect(
              FileSystemEntity.typeSync(destination.path, followLinks: false),
              FileSystemEntityType.link,
            );
            expect(Link(destination.path).targetSync(), target.path);
            expect(target.readAsStringSync(), 'target-must-remain-untouched\n');
          }
          expect(_openDescriptors(), descriptorsBefore);
        },
      );
    }

    test('metadata edit at the syscall boundary is preserved and rejected', () {
      var injected = false;
      late final File destination;
      final primitive = LinuxX64ProjectionLayoutPreservingSwap(
        beforeExchangeSyscall: () {
          if (injected) return;
          injected = true;
          final changed = Process.runSync('chmod', <String>[
            '751',
            destination.path,
          ]);
          if (changed.exitCode != 0) {
            throw StateError('Unable to mutate fixture metadata');
          }
        },
      );
      if (!primitive.isSupported) return;
      final root = Directory(p.join(workspace.path, 'content'))..createSync();
      destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      expect(
        Process.runSync('chmod', <String>['640', destination.path]).exitCode,
        0,
      );
      final writer = FilesystemProjectionLayoutAtomicFileWriter(
        maxBytes: 1024,
        swapPrimitive: primitive,
      );
      final staged = writer.stage(
        workspaceRoot: workspace.path,
        contentRoot: root.path,
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
        bytes: utf8.encode('candidate\n'),
      );
      final descriptorsBefore = _openDescriptors();

      expect(
        () => writer.replace(
          staged,
          expectedCurrentDigest: Digest.bytes(utf8.encode('original\n')),
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.ioFailure,
          ),
        ),
      );

      expect(destination.readAsStringSync(), 'original\n');
      expect(_permissionBits(destination.path), 0x1e9);
      expect(File(staged.stagingPath).readAsStringSync(), 'candidate\n');
      expect(_permissionBits(staged.stagingPath), 0x1a0);
      expect(_openDescriptors(), descriptorsBefore);
    });

    test('cross-device private slot is unsupported before source mutation', () {
      const primitive = LinuxX64ProjectionLayoutPreservingSwap();
      if (!primitive.isSupported || !Directory('/dev/shm').existsSync()) return;
      final otherRoot = Directory(
        '/dev/shm',
      ).createTempSync('workspace-preserving-source-swap-');
      addTearDown(() {
        if (otherRoot.existsSync()) otherRoot.deleteSync(recursive: true);
      });
      if (_deviceId(otherRoot.path) == _deviceId(workspace.path)) return;
      final destination = File(p.join(otherRoot.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );

      expect(
        () => primitive.stage(
          contentRoot: otherRoot.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          bytes: utf8.encode('candidate\n'),
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.unsupported,
          ),
        ),
      );
      expect(destination.readAsStringSync(), 'original\n');
      expect(
        File(p.join(workspace.path, slotRelativePath)).existsSync(),
        isFalse,
      );
    });

    test('private rotating slot directory requires exact mode 0700', () {
      const primitive = LinuxX64ProjectionLayoutPreservingSwap();
      if (!primitive.isSupported) return;
      final root = Directory(p.join(workspace.path, 'content'))..createSync();
      final destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final candidate = utf8.encode('candidate\n');
      primitive.stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: candidate,
        maxBytes: 1024,
      );
      final slot = File(p.join(workspace.path, slotRelativePath));
      final privateDirectory = p.dirname(slot.path);
      expect(
        Process.runSync('chmod', <String>['2700', privateDirectory]).exitCode,
        0,
      );

      expect(
        () => primitive.observe(
          contentRoot: root.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
          ),
        ),
      );
      expect(destination.readAsStringSync(), 'original\n');
      expect(slot.readAsBytesSync(), candidate);
    });

    test('native boundary rejects symlinks and multi-link files', () {
      const primitive = LinuxX64ProjectionLayoutPreservingSwap();
      if (!primitive.isSupported) return;
      final root = Directory(p.join(workspace.path, 'content'))..createSync();
      final destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final external = File(p.join(workspace.path, 'external'))
        ..writeAsStringSync('candidate\n', flush: true);
      final slotRelativePath = projectionLayoutPromotionRecoverySlot(
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
      );
      final symlinkStage = primitive.stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: utf8.encode('candidate\n'),
        maxBytes: 1024,
      );
      final slotPath = p.join(workspace.path, slotRelativePath);
      File(slotPath).deleteSync();
      Link(slotPath).createSync(external.path);
      final descriptorsBeforeSymlinkFailure = _openDescriptors();

      expect(
        () => primitive.exchange(
          contentRoot: root.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
          expectedStagingDigest: Digest.bytes(utf8.encode('candidate\n')),
          expectedDestinationMetadataDigest: symlinkStage.sourceMetadataDigest,
          expectedStagingMetadataDigest: symlinkStage.sourceMetadataDigest,
          maxBytes: 1024,
        ),
        throwsA(isA<ProjectionLayoutPreservingSwapFailure>()),
      );
      expect(destination.readAsStringSync(), 'original\n');
      expect(_openDescriptors(), descriptorsBeforeSymlinkFailure);
      Link(slotPath).deleteSync();
      final hardLinkStage = primitive.stage(
        contentRoot: root.path,
        destinationRelativePath: 'layout.json',
        workspaceRoot: workspace.path,
        stagingRelativePath: slotRelativePath,
        bytes: utf8.encode('candidate\n'),
        maxBytes: 1024,
      );
      final hardLink = p.join(root.path, 'layout-hardlink.json');
      final linked = Process.runSync('ln', <String>[
        destination.path,
        hardLink,
      ]);
      if (linked.exitCode != 0) return;
      final descriptorsBeforeHardLinkFailure = _openDescriptors();

      expect(
        () => primitive.exchange(
          contentRoot: root.path,
          destinationRelativePath: 'layout.json',
          workspaceRoot: workspace.path,
          stagingRelativePath: slotRelativePath,
          expectedDestinationDigest: Digest.bytes(utf8.encode('original\n')),
          expectedStagingDigest: Digest.bytes(utf8.encode('candidate\n')),
          expectedDestinationMetadataDigest: hardLinkStage.sourceMetadataDigest,
          expectedStagingMetadataDigest: hardLinkStage.sourceMetadataDigest,
          maxBytes: 1024,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
          ),
        ),
      );
      expect(destination.readAsStringSync(), 'original\n');
      expect(File(hardLink).readAsStringSync(), 'original\n');
      expect(_openDescriptors(), descriptorsBeforeHardLinkFailure);
    });

    test('unsupported provider never falls back to destructive rename', () {
      final root = Directory(p.join(workspace.path, 'content'))..createSync();
      final destination = File(p.join(root.path, 'layout.json'))
        ..writeAsStringSync('original\n', flush: true);
      final writer = FilesystemProjectionLayoutAtomicFileWriter(
        maxBytes: 1024,
        swapPrimitive: const _UnsupportedAtExchangeSwapPrimitive(),
      );
      final staged = writer.stage(
        workspaceRoot: workspace.path,
        contentRoot: root.path,
        subject: _nativeSwapSubject,
        relativeSourcePath: 'layout.json',
        bytes: utf8.encode('candidate\n'),
      );

      expect(
        () => writer.replace(
          staged,
          expectedCurrentDigest: Digest.bytes(utf8.encode('original\n')),
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.unsupported,
          ),
        ),
      );
      expect(destination.readAsStringSync(), 'original\n');
      expect(File(staged.stagingPath).readAsStringSync(), 'candidate\n');
    });
  });

  group('ProjectionLayoutPromotionCompiler', () {
    late Directory workspace;
    late BoundedWorkspaceAuthoringCorpus corpus;
    late AuthoringSubjectRef subject;
    late ProjectionLayoutManifest baseLayout;
    late ProjectionLayoutManifest candidateLayout;
    late BoundedAuthoringSource layoutSource;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync(
        'workspace-layout-promotion-compiler-',
      );
      _writeWorkspace(workspace);
      corpus = const BoundedWorkspaceAuthoringLoader().load(
        startPath: workspace.path,
      );
      final catalog = const CatalogCompiler().compile(
        corpus.documents,
        layout: corpus.configuration.layout,
      );
      final experience = const ExperienceTopologyCompiler().compile(
        corpus.documents,
        catalog: catalog,
      );
      baseLayout = experience.layouts.single;
      subject = AuthoringSubjectRef(
        workspaceId: WorkspaceId('workspace'),
        applicationId: ApplicationId('app'),
        projectionId: ExperienceProjectionId('projection'),
      );
      final draft = const LayoutDraftEngine().openDraft(
        id: LayoutDraftId('draft'),
        subject: subject,
        baseLayout: baseLayout,
        baseSourceDigest: Digest.semantic('fixture-projection-layout-source'),
        contentSetDigest: Digest.semantic('content'),
      );
      final moved = const LayoutDraftEngine().applyMove(
        draft: draft,
        baseLayout: baseLayout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node'),
          toX: 125,
          toY: 245,
        ),
      );
      candidateLayout = const LayoutDraftEngine().materialize(
        draft: moved,
        baseLayout: baseLayout,
      );
      final layoutDocument = corpus.documents.singleWhere(
        (document) => document.kind == AuthoringKind.projectionLayout,
      );
      layoutSource = corpus.sources[layoutDocument.sourceName]!;
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('serializes only x/y into a valid canonical v2 source', () {
      final prepared = const ProjectionLayoutPromotionCompiler().prepare(
        corpus: corpus,
        subject: subject,
        expectedBaseLayoutDigest: baseLayout.digest,
        expectedSourceDigest: layoutSource.digest,
        candidateLayout: candidateLayout,
      );

      expect(prepared.relativeSourcePath, 'layout.yaml');
      expect(prepared.originalSourceDigest, layoutSource.digest);
      expect(prepared.candidateLayout.digest, candidateLayout.digest);
      expect(
        prepared.currentContent.catalog.digest,
        prepared.candidateContent.catalog.digest,
      );
      expect(
        prepared.currentContent.experienceBundle!.topology.digest,
        prepared.candidateContent.experienceBundle!.topology.digest,
      );

      final text = utf8.decode(prepared.candidateSourceBytes);
      final decoded = jsonDecode(text) as Map<String, Object?>;
      expect(text, '${const JcsCanonicalizer().canonicalize(decoded)}\n');
      expect(decoded.keys, <String>[
        'kind',
        'metadata',
        'schemaVersion',
        'spec',
      ]);
      expect(decoded, isNot(contains('topologyDigest')));
      expect(decoded, isNot(contains('digest')));
      final spec = decoded['spec']! as Map<String, Object?>;
      final frame =
          (spec['nodeFrames']! as List<Object?>).single as Map<String, Object?>;
      expect(frame['x'], 125);
      expect(frame['y'], 245);
      expect(frame['width'], 300);
      expect(frame['height'], 180);
      expect(spec['camera'], <String, Object?>{'x': 0, 'y': 0, 'zoom': 1});
    });

    test('rejects stale source bytes without accepting a client path', () {
      expect(
        () => const ProjectionLayoutPromotionCompiler().prepare(
          corpus: corpus,
          subject: subject,
          expectedBaseLayoutDigest: baseLayout.digest,
          expectedSourceDigest: Digest.semantic('stale-source'),
          candidateLayout: candidateLayout,
        ),
        throwsStateError,
      );
    });
  });

  group('ProjectionLayoutPromotionCoordinator', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync(
        'workspace-layout-promotion-coordinator-',
      );
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('promotes one source and commits its receipt under one lock', () {
      final fixture = _PromotionFixture(workspace);
      final original = fixture.layoutFile.readAsBytesSync();

      final receipt = fixture.coordinator.promote(
        configuration: fixture.configuration,
        subject: fixture.subject,
        intentId: 'promotion-1',
        receiptId: ExperiencePromotionReceiptId('receipt-1'),
        changeSet: fixture.changeSet,
        reviewPacket: fixture.reviewPacket,
        allowedArtifactDigests: const <Digest>{},
        grantDigest: Digest.semantic('promotion-grant'),
        promotedAt: DateTime.utc(2026, 8, 17, 2),
        contentAuthority: fixture.contentAuthority,
      );

      expect(fixture.layoutFile.readAsBytesSync(), isNot(original));
      expect(
        Digest.bytes(fixture.layoutFile.readAsBytesSync()),
        receipt.resultSourceDigest,
      );
      expect(fixture.store.findDraft(fixture.subject), isNull);
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(
        fixture.store.promotionHistory(fixture.subject).single.digest,
        receipt.digest,
      );
      expect(
        fixture.contentAuthority.publishedDigest,
        receipt.resultContentSetDigest,
      );

      final restarted = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      expect(
        restarted.promotionHistory(fixture.subject).single.digest,
        receipt.digest,
      );
    });

    test('unsupported provider is rejected before WAL or source writes', () {
      final writer = FilesystemProjectionLayoutAtomicFileWriter(
        swapPrimitive: const _UnavailableSwapPrimitive(),
      );
      final fixture = _PromotionFixture(workspace, fileWriter: writer);
      final original = fixture.layoutFile.readAsBytesSync();

      expect(
        fixture.promote,
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.unsupported,
          ),
        ),
      );

      expect(fixture.layoutFile.readAsBytesSync(), original);
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(fixture.store.findDraft(fixture.subject), isNotNull);
    });

    test('unsupported filesystem syscall rolls back without fallback', () {
      final writer = FilesystemProjectionLayoutAtomicFileWriter(
        swapPrimitive: const _UnsupportedAtExchangeSwapPrimitive(),
      );
      final fixture = _PromotionFixture(workspace, fileWriter: writer);
      final original = fixture.layoutFile.readAsBytesSync();

      expect(
        fixture.promote,
        throwsA(
          isA<ProjectionLayoutPromotionFailure>()
              .having(
                (failure) => failure.phase,
                'phase',
                ProjectionLayoutPromotionPhase.replace,
              )
              .having(
                (failure) => failure.cause,
                'cause',
                isA<ProjectionLayoutPreservingSwapFailure>().having(
                  (cause) => cause.code,
                  'code',
                  ProjectionLayoutPreservingSwapFailureCode.unsupported,
                ),
              ),
        ),
      );

      expect(fixture.layoutFile.readAsBytesSync(), original);
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
      expect(fixture.store.findDraft(fixture.subject), isNotNull);
    });

    test('CAS or prepare-WAL fsync failure occurs before source exchange', () {
      for (final failAt in <int>[1, 2, 3]) {
        final caseWorkspace = Directory(
          p.join(workspace.path, 'prepare-fsync-$failAt'),
        )..createSync();
        var destinationFsyncs = 0;
        var armed = false;
        final stateWriter = DefaultExperienceAuthoringStateWriter(
          beforeFsync: (target) {
            if (target !=
                ExperienceAuthoringStateFsyncTarget.destinationParent) {
              return;
            }
            destinationFsyncs += 1;
            if (armed && destinationFsyncs == failAt) {
              throw StateError('injected prepare durability failure');
            }
          },
        );
        final fixture = _PromotionFixture(
          caseWorkspace,
          stateWriter: stateWriter,
        );
        final original = fixture.layoutFile.readAsBytesSync();
        destinationFsyncs = 0;
        armed = true;

        expect(
          fixture.promote,
          throwsA(
            isA<ProjectionLayoutPromotionFailure>().having(
              (failure) => failure.phase,
              'phase',
              ProjectionLayoutPromotionPhase.prepare,
            ),
          ),
          reason: 'durability boundary $failAt',
        );
        expect(fixture.layoutFile.readAsBytesSync(), original);
        expect(fixture.store.hasDurabilityUncertainty, isTrue);
        expect(fixture.contentAuthority.publishCount, 0);
      }
    });

    test('rename move-then-error restores original and retains the draft', () {
      final writer = _FaultingAtomicWriter(moveThenError: true);
      final fixture = _PromotionFixture(workspace, fileWriter: writer);
      final original = fixture.layoutFile.readAsBytesSync();

      expect(
        () => fixture.promote(),
        throwsA(
          isA<ProjectionLayoutPromotionFailure>().having(
            (error) => error.phase,
            'phase',
            ProjectionLayoutPromotionPhase.replace,
          ),
        ),
      );

      expect(fixture.layoutFile.readAsBytesSync(), original);
      expect(
        fixture.store.requireDraft(fixture.subject).draft.digest,
        fixture.draft.digest,
      );
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
      expect(
        fixture.contentAuthority.publishedDigest,
        fixture.draft.contentSetDigest,
      );
    });

    test('external edit before rename is never overwritten', () {
      final writer = _FaultingAtomicWriter(
        beforeReplace: (staged) {
          File(
            staged.destinationPath,
          ).writeAsStringSync('{"thirdParty":true}\n', flush: true);
        },
      );
      final fixture = _PromotionFixture(workspace, fileWriter: writer);
      final thirdParty = utf8.encode('{"thirdParty":true}\n');

      expect(
        () => fixture.promote(),
        throwsA(isA<ProjectionLayoutPromotionFailure>()),
      );

      expect(fixture.layoutFile.readAsBytesSync(), thirdParty);
      expect(fixture.contentAuthority.publishCount, 0);
      final pending = fixture.store.pendingPromotions().single;
      expect(pending.intentId, 'promotion-1');
      final pair = fixture.atomicWriter.inspectRecoverySlot(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        relativeSourcePath: pending.relativeSourcePath,
        recoverySlot: pending.recoverySlot,
      );
      expect(pair.destinationDigest, Digest.bytes(thirdParty));
      expect(pair.stagingDigest, pending.candidateSourceDigest);
      expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
    });

    test(
      'publish failure rolls source and live content back before WAL terminal',
      () {
        final fixture = _PromotionFixture(workspace);
        final original = fixture.layoutFile.readAsBytesSync();
        fixture.contentAuthority.failNextPublish = true;

        expect(
          () => fixture.promote(),
          throwsA(
            isA<ProjectionLayoutPromotionFailure>().having(
              (error) => error.phase,
              'phase',
              ProjectionLayoutPromotionPhase.publish,
            ),
          ),
        );

        expect(fixture.layoutFile.readAsBytesSync(), original);
        expect(fixture.store.pendingPromotions(), isEmpty);
        expect(
          fixture.store.requireDraft(fixture.subject).draft.digest,
          fixture.draft.digest,
        );
        expect(
          fixture.contentAuthority.publishedDigest,
          fixture.draft.contentSetDigest,
        );
      },
    );

    test(
      'external edit after linearization remains newer than the receipt',
      () {
        final fixture = _PromotionFixture(workspace);
        final thirdParty = utf8.encode('{"thirdPartyAfterPublish":true}\n');
        fixture.contentAuthority.afterPublish = () {
          fixture.layoutFile.writeAsBytesSync(thirdParty, flush: true);
        };

        final receipt = fixture.promote();

        expect(fixture.layoutFile.readAsBytesSync(), thirdParty);
        expect(Digest.bytes(thirdParty), isNot(receipt.resultSourceDigest));
        expect(fixture.store.pendingPromotions(), isEmpty);
        final pair = fixture.atomicWriter.inspectRecoverySlot(
          workspaceRoot: fixture.configuration.workspaceRoot,
          contentRoot: fixture.configuration.contentRoot,
          relativeSourcePath: p.relative(
            fixture.source.path,
            from: fixture.configuration.contentRoot,
          ),
          recoverySlot: fixture.atomicWriter.recoverySlot(
            subject: fixture.subject,
            relativeSourcePath: p.relative(
              fixture.source.path,
              from: fixture.configuration.contentRoot,
            ),
          ),
        );
        expect(pair.destinationDigest, Digest.bytes(thirdParty));
        expect(pair.stagingDigest, receipt.sourceDigest);
        expect(
          fixture.store.promotionHistory(fixture.subject).single.digest,
          receipt.digest,
        );
        expect(fixture.store.findDraft(fixture.subject), isNull);
        expect(
          fixture.contentAuthority.publishedDigest,
          receipt.resultContentSetDigest,
        );
      },
    );

    test('commit persisted-then-error is replayed as exact success', () {
      final stateWriter = _MoveThenErrorStateWriter();
      final fixture = _PromotionFixture(workspace, stateWriter: stateWriter);
      stateWriter.failOnWrite = stateWriter.writeCount + 2;

      final receipt = fixture.promote();

      expect(stateWriter.didFail, isTrue);
      expect(
        Digest.bytes(fixture.layoutFile.readAsBytesSync()),
        receipt.resultSourceDigest,
      );
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(fixture.store.findDraft(fixture.subject), isNull);
      expect(
        fixture.store.promotionHistory(fixture.subject).single.digest,
        receipt.digest,
      );
    });

    test('commit directory fsync uncertainty never rolls source backward', () {
      var destinationFsyncs = 0;
      var failAt = 0;
      final stateWriter = DefaultExperienceAuthoringStateWriter(
        beforeFsync: (target) {
          if (target != ExperienceAuthoringStateFsyncTarget.destinationParent) {
            return;
          }
          destinationFsyncs += 1;
          if (failAt != 0 && destinationFsyncs == failAt) {
            throw StateError('injected commit directory fsync failure');
          }
        },
      );
      final fixture = _PromotionFixture(workspace, stateWriter: stateWriter);
      destinationFsyncs = 0;
      failAt = 4;

      expect(
        fixture.promote,
        throwsA(
          isA<ProjectionLayoutPromotionFailure>()
              .having(
                (failure) => failure.phase,
                'phase',
                ProjectionLayoutPromotionPhase.commit,
              )
              .having(
                (failure) => failure.cause,
                'cause',
                isA<ExperienceAuthoringStateDurabilityFailure>(),
              )
              .having(
                (failure) => failure.recoveryCause,
                'recoveryCause',
                isA<ProjectionLayoutPreservingSwapFailure>().having(
                  (failure) => failure.code,
                  'code',
                  ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
                ),
              ),
        ),
      );

      expect(fixture.store.hasDurabilityUncertainty, isTrue);
      final visible = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      final receipt = visible.promotionHistory(fixture.subject).single;
      expect(
        Digest.bytes(fixture.layoutFile.readAsBytesSync()),
        receipt.resultSourceDigest,
      );
      expect(visible.pendingPromotions(), isEmpty);
      expect(fixture.contentAuthority.publishCount, 1);
    });

    test('commit retains one stable private backup slot per source', () {
      final writer = _FaultingAtomicWriter();
      final fixture = _PromotionFixture(workspace, fileWriter: writer);
      final original = fixture.layoutFile.readAsBytesSync();
      final slot = writer.recoverySlot(
        subject: fixture.subject,
        relativeSourcePath: p.relative(
          fixture.source.path,
          from: fixture.configuration.contentRoot,
        ),
      );

      final receipt = fixture.promote();

      expect(
        Digest.bytes(fixture.layoutFile.readAsBytesSync()),
        receipt.resultSourceDigest,
      );
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(
        fixture.store.promotionHistory(fixture.subject).single.digest,
        receipt.digest,
      );
      expect(
        File(
          p.join(fixture.configuration.workspaceRoot, slot),
        ).readAsBytesSync(),
        original,
      );
    });

    test(
      'effect prepare reserves grant and candidate recovery atomically finalizes success',
      () {
        final fixture = _PromotionFixture(workspace);
        final effect = fixture.issuePromotionEffect();
        final pending = fixture.prepareEffectWal(effect);
        expect(
          fixture.store.findGrant(effect.grant.id)!.state,
          StoredAuthoringGrantState.inFlight,
        );
        expect(fixture.store.findAttempt(effect.request.requestId), isNull);

        final candidate = fixture.store.readPromotionSourceBlob(
          pending.candidateSourceBlobDigest,
        );
        final staged = fixture.atomicWriter.stage(
          workspaceRoot: fixture.configuration.workspaceRoot,
          contentRoot: fixture.configuration.contentRoot,
          subject: fixture.subject,
          relativeSourcePath: pending.relativeSourcePath,
          bytes: candidate,
        );
        fixture.atomicWriter.replace(
          staged,
          expectedCurrentDigest: pending.originalSourceDigest,
        );

        final restartedStore = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        );
        final recovered =
            ProjectionLayoutPromotionCoordinator(
              store: restartedStore,
            ).recoverPending(
              configuration: fixture.configuration,
              contentAuthority: _TestContentAuthority(),
            );

        expect(recovered.single.digest, pending.receipt.digest);
        expect(restartedStore.pendingPromotions(), isEmpty);
        expect(restartedStore.findDraft(fixture.subject), isNull);
        expect(
          restartedStore.findGrant(effect.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );
        final terminal = restartedStore.findAttempt(effect.request.requestId)!;
        expect(terminal.isError, isFalse);
        expect(
          ExperiencePromotionApplyResult.fromJson(
            terminal.terminalJson,
          ).receipt.digest,
          pending.receipt.digest,
        );
      },
    );

    test(
      'effect recovery on original source consumes grant and records exact rollback error',
      () {
        final fixture = _PromotionFixture(workspace);
        final effect = fixture.issuePromotionEffect();
        fixture.prepareEffectWal(effect);

        final restartedStore = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        );
        ProjectionLayoutPromotionCoordinator(
          store: restartedStore,
        ).recoverPending(
          configuration: fixture.configuration,
          contentAuthority: _TestContentAuthority(),
        );

        expect(restartedStore.pendingPromotions(), isEmpty);
        expect(restartedStore.findDraft(fixture.subject), isNotNull);
        expect(restartedStore.promotionHistory(fixture.subject), isEmpty);
        expect(
          restartedStore.findGrant(effect.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );
        final terminal = restartedStore.findAttempt(effect.request.requestId)!;
        expect(terminal.digest, effect.rollbackAttempt.digest);
        expect(
          ExperienceAuthoringError.fromJson(terminal.terminalJson).code,
          ExperienceAuthoringErrorCode.unavailable,
        );
      },
    );

    test(
      'terminal failed WAL never becomes success and is resolved only at original authority',
      () {
        final fixture = _PromotionFixture(workspace);
        final effect = fixture.issuePromotionEffect();
        final pending = fixture.prepareEffectWal(effect);
        final original = fixture.store.readPromotionSourceBlob(
          pending.originalSourceBlobDigest,
        );
        final thirdParty = utf8.encode('{"thirdPartyTerminal":true}\n');
        fixture.layoutFile.writeAsBytesSync(thirdParty, flush: true);

        expect(
          () => fixture.coordinator.recoverPending(
            configuration: fixture.configuration,
            contentAuthority: fixture.contentAuthority,
          ),
          throwsA(isA<ProjectionLayoutPromotionFailure>()),
        );
        final terminal = fixture.store.findAttempt(effect.request.requestId)!;
        expect(terminal.digest, effect.rollbackAttempt.digest);
        expect(fixture.store.pendingPromotions(), hasLength(1));
        expect(fixture.store.promotionHistory(fixture.subject), isEmpty);

        fixture.layoutFile.writeAsBytesSync(original, flush: true);
        final restartedStore = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        );
        ProjectionLayoutPromotionCoordinator(
          store: restartedStore,
        ).recoverPending(
          configuration: fixture.configuration,
          contentAuthority: _TestContentAuthority(),
        );

        expect(restartedStore.pendingPromotions(), isEmpty);
        expect(restartedStore.promotionHistory(fixture.subject), isEmpty);
        expect(
          restartedStore.findAttempt(effect.request.requestId)!.digest,
          terminal.digest,
        );
        expect(
          restartedStore.findGrant(effect.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );
      },
    );

    test(
      'terminal failed WAL at candidate restores original without creating a receipt',
      () {
        final fixture = _PromotionFixture(workspace);
        final effect = fixture.issuePromotionEffect();
        final pending = fixture.prepareEffectWal(effect);
        final original = fixture.store.readPromotionSourceBlob(
          pending.originalSourceBlobDigest,
        );
        final candidate = fixture.store.readPromotionSourceBlob(
          pending.candidateSourceBlobDigest,
        );
        final staged = fixture.atomicWriter.stage(
          workspaceRoot: fixture.configuration.workspaceRoot,
          contentRoot: fixture.configuration.contentRoot,
          subject: fixture.subject,
          relativeSourcePath: pending.relativeSourcePath,
          bytes: candidate,
        );
        fixture.atomicWriter.replace(
          staged,
          expectedCurrentDigest: pending.originalSourceDigest,
        );
        fixture.store.finalizePromotionEffect(
          intentId: pending.intentId,
          outcome: StoredPromotionFinalization.failed,
        );

        final restartedStore = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
        );
        final authority = _TestContentAuthority();
        ProjectionLayoutPromotionCoordinator(
          store: restartedStore,
        ).recoverPending(
          configuration: fixture.configuration,
          contentAuthority: authority,
        );

        expect(fixture.layoutFile.readAsBytesSync(), original);
        expect(restartedStore.pendingPromotions(), isEmpty);
        expect(restartedStore.promotionHistory(fixture.subject), isEmpty);
        expect(
          restartedStore.findAttempt(effect.request.requestId)!.digest,
          effect.rollbackAttempt.digest,
        );
        expect(
          authority.publishedDigest,
          pending.receipt.previousContentSetDigest,
        );
      },
    );

    test('recovery retains the stable candidate slot and rolls WAL back', () {
      final fixture = _PromotionFixture(workspace);
      final pending = fixture.prepareWal();
      final candidate = fixture.store.readPromotionSourceBlob(
        pending.candidateSourceBlobDigest,
      );
      final staged = fixture.atomicWriter.stage(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        subject: fixture.subject,
        relativeSourcePath: pending.relativeSourcePath,
        bytes: candidate,
      );
      expect(File(staged.stagingPath).existsSync(), isTrue);

      final recovered = fixture.coordinator.recoverPending(
        configuration: fixture.configuration,
        contentAuthority: fixture.contentAuthority,
      );

      expect(recovered, isEmpty);
      expect(File(staged.stagingPath).readAsBytesSync(), candidate);
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(
        fixture.store.requireDraft(fixture.subject).draft.digest,
        fixture.draft.digest,
      );
    });

    test('recovery does not roll back a source with changed metadata', () {
      final fixture = _PromotionFixture(workspace);
      final pending = fixture.prepareWal();
      final slot = File(
        p.join(fixture.configuration.workspaceRoot, pending.recoverySlot),
      );
      final sourceBefore = fixture.layoutFile.readAsBytesSync();
      final slotBefore = slot.readAsBytesSync();
      expect(
        Process.runSync('chmod', <String>[
          '751',
          fixture.layoutFile.path,
        ]).exitCode,
        0,
      );

      expect(
        () => fixture.coordinator.recoverPending(
          configuration: fixture.configuration,
          contentAuthority: fixture.contentAuthority,
        ),
        throwsA(isA<ProjectionLayoutPromotionFailure>()),
      );

      expect(fixture.layoutFile.readAsBytesSync(), sourceBefore);
      expect(slot.readAsBytesSync(), slotBefore);
      expect(_permissionBits(fixture.layoutFile.path), 0x1e9);
      expect(
        fixture.store.pendingPromotions().single.intentId,
        pending.intentId,
      );
      expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
      expect(fixture.contentAuthority.publishCount, 0);
    });

    test(
      'recovery rejects another workspace authority without touching WAL',
      () {
        final fixture = _PromotionFixture(workspace);
        final pending = fixture.prepareWal();
        final otherWorkspace = Directory.systemTemp.createTempSync(
          'workspace-promotion-other-authority-',
        );
        addTearDown(() {
          if (otherWorkspace.existsSync()) {
            otherWorkspace.deleteSync(recursive: true);
          }
        });
        final other = _PromotionFixture(otherWorkspace);
        final sourceBefore = fixture.layoutFile.readAsBytesSync();
        final otherSourceBefore = other.layoutFile.readAsBytesSync();
        final authority = _TestContentAuthority();

        expect(
          () => fixture.coordinator.recoverPending(
            configuration: other.configuration,
            contentAuthority: authority,
          ),
          throwsStateError,
        );

        expect(fixture.layoutFile.readAsBytesSync(), sourceBefore);
        expect(other.layoutFile.readAsBytesSync(), otherSourceBefore);
        expect(
          fixture.store.pendingPromotions().single.intentId,
          pending.intentId,
        );
        expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
        expect(authority.publishCount, 0);
      },
    );

    test('recovery rejects configuration drift at the same root', () {
      final fixture = _PromotionFixture(workspace);
      final pending = fixture.prepareWal();
      final sourceBefore = fixture.layoutFile.readAsBytesSync();
      final configFile = File(p.join(workspace.path, 'workspace.yaml'));
      configFile.writeAsStringSync(
        configFile.readAsStringSync().replaceFirst(
          'displayName: Workspace',
          'displayName: Workspace Drifted',
        ),
        flush: true,
      );
      final drifted = const WorkspaceConfigurationLoader().load(
        startPath: workspace.path,
      );
      expect(drifted.workspaceId, fixture.configuration.workspaceId);
      expect(
        drifted.documentDigest,
        isNot(fixture.configuration.documentDigest),
      );
      final authority = _TestContentAuthority();

      expect(
        () => fixture.coordinator.recoverPending(
          configuration: drifted,
          contentAuthority: authority,
        ),
        throwsStateError,
      );

      expect(fixture.layoutFile.readAsBytesSync(), sourceBefore);
      expect(
        fixture.store.pendingPromotions().single.intentId,
        pending.intentId,
      );
      expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
      expect(authority.publishCount, 0);
    });

    test('recovery finalizes an exact installed candidate after restart', () {
      final fixture = _PromotionFixture(workspace);
      expect(
        Process.runSync('chmod', <String>[
          '751',
          fixture.layoutFile.path,
        ]).exitCode,
        0,
      );
      final pending = fixture.prepareWal();
      final candidate = fixture.store.readPromotionSourceBlob(
        pending.candidateSourceBlobDigest,
      );
      final staged = fixture.atomicWriter.stage(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        subject: fixture.subject,
        relativeSourcePath: pending.relativeSourcePath,
        bytes: candidate,
      );
      fixture.atomicWriter.replace(
        staged,
        expectedCurrentDigest: pending.originalSourceDigest,
      );

      final restartedStore = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      final restartedAuthority = _TestContentAuthority();
      final recovered =
          ProjectionLayoutPromotionCoordinator(
            store: restartedStore,
          ).recoverPending(
            configuration: fixture.configuration,
            contentAuthority: restartedAuthority,
          );

      expect(recovered.single.digest, pending.receipt.digest);
      expect(restartedStore.pendingPromotions(), isEmpty);
      expect(restartedStore.findDraft(fixture.subject), isNull);
      expect(
        restartedStore.promotionHistory(fixture.subject).single.digest,
        pending.receipt.digest,
      );
      expect(
        restartedAuthority.publishedDigest,
        pending.receipt.resultContentSetDigest,
      );
      expect(_permissionBits(fixture.layoutFile.path), 0x1e9);
      expect(_permissionBits(staged.stagingPath), 0x1e9);
    });

    test('post-swap interruption is recovered from the preserved pair', () {
      final fixture = _PromotionFixture(workspace);
      expect(
        Process.runSync('chmod', <String>[
          '751',
          fixture.layoutFile.path,
        ]).exitCode,
        0,
      );
      final pending = fixture.prepareWal();
      final candidate = fixture.store.readPromotionSourceBlob(
        pending.candidateSourceBlobDigest,
      );
      var interrupted = false;
      final writer = FilesystemProjectionLayoutAtomicFileWriter(
        swapPrimitive: LinuxX64ProjectionLayoutPreservingSwap(
          afterExchangeSyscall: () {
            if (interrupted) return;
            interrupted = true;
            throw StateError('injected interruption after renameat2 exchange');
          },
        ),
      );
      if (!writer.swapPrimitive.isSupported) return;
      final staged = writer.stage(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        subject: fixture.subject,
        relativeSourcePath: pending.relativeSourcePath,
        bytes: candidate,
      );

      expect(
        () => writer.replace(
          staged,
          expectedCurrentDigest: pending.originalSourceDigest,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.outcomeUnknown,
          ),
        ),
      );
      final interruptedPair = const FilesystemProjectionLayoutAtomicFileWriter()
          .inspectRecoverySlot(
            workspaceRoot: fixture.configuration.workspaceRoot,
            contentRoot: fixture.configuration.contentRoot,
            relativeSourcePath: pending.relativeSourcePath,
            recoverySlot: pending.recoverySlot,
          );
      expect(interruptedPair.destinationDigest, pending.candidateSourceDigest);
      expect(interruptedPair.stagingDigest, pending.originalSourceDigest);

      final restartedStore = FilesystemExperienceAuthoringStore(
        workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      );
      final recovered =
          ProjectionLayoutPromotionCoordinator(
            store: restartedStore,
          ).recoverPending(
            configuration: fixture.configuration,
            contentAuthority: _TestContentAuthority(),
          );

      expect(recovered.single.digest, pending.receipt.digest);
      expect(restartedStore.pendingPromotions(), isEmpty);
      expect(
        Digest.bytes(File(staged.stagingPath).readAsBytesSync()),
        pending.originalSourceDigest,
      );
      expect(
        Digest.bytes(fixture.layoutFile.readAsBytesSync()),
        pending.candidateSourceDigest,
      );
      expect(_permissionBits(fixture.layoutFile.path), 0x1e9);
      expect(_permissionBits(staged.stagingPath), 0x1e9);
    });

    test(
      'candidate with unknown recovery bytes restores unknown and stops',
      () {
        final fixture = _PromotionFixture(workspace);
        final pending = fixture.prepareWal();
        final authoritativeMode = _permissionBits(fixture.layoutFile.path);
        final candidate = fixture.store.readPromotionSourceBlob(
          pending.candidateSourceBlobDigest,
        );
        final staged = fixture.atomicWriter.stage(
          workspaceRoot: fixture.configuration.workspaceRoot,
          contentRoot: fixture.configuration.contentRoot,
          subject: fixture.subject,
          relativeSourcePath: pending.relativeSourcePath,
          bytes: candidate,
        );
        fixture.atomicWriter.replace(
          staged,
          expectedCurrentDigest: pending.originalSourceDigest,
        );
        final unknown = utf8.encode('{"externalRecovery":true}\n');
        File(staged.stagingPath).writeAsBytesSync(unknown, flush: true);
        expect(
          Process.runSync('chmod', <String>[
            '751',
            staged.stagingPath,
          ]).exitCode,
          0,
        );

        expect(
          () => fixture.coordinator.recoverPending(
            configuration: fixture.configuration,
            contentAuthority: fixture.contentAuthority,
          ),
          throwsA(isA<ProjectionLayoutPromotionFailure>()),
        );

        expect(fixture.layoutFile.readAsBytesSync(), unknown);
        expect(File(staged.stagingPath).readAsBytesSync(), candidate);
        expect(_permissionBits(fixture.layoutFile.path), 0x1e9);
        expect(_permissionBits(staged.stagingPath), authoritativeMode);
        expect(fixture.store.pendingPromotions(), hasLength(1));
        expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
        expect(fixture.contentAuthority.publishCount, 0);
      },
    );

    test('candidate without its recovery slot commits from exact source', () {
      final fixture = _PromotionFixture(workspace);
      final pending = fixture.prepareWal();
      final candidate = fixture.store.readPromotionSourceBlob(
        pending.candidateSourceBlobDigest,
      );
      final staged = fixture.atomicWriter.stage(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        subject: fixture.subject,
        relativeSourcePath: pending.relativeSourcePath,
        bytes: candidate,
      );
      fixture.atomicWriter.replace(
        staged,
        expectedCurrentDigest: pending.originalSourceDigest,
      );
      File(staged.stagingPath).deleteSync();

      final recovered = fixture.coordinator.recoverPending(
        configuration: fixture.configuration,
        contentAuthority: fixture.contentAuthority,
      );

      expect(recovered.single.digest, pending.receipt.digest);
      expect(fixture.layoutFile.readAsBytesSync(), candidate);
      expect(File(staged.stagingPath).existsSync(), isFalse);
      expect(fixture.store.pendingPromotions(), isEmpty);
      expect(
        fixture.store.promotionHistory(fixture.subject).single.digest,
        pending.receipt.digest,
      );
      expect(fixture.contentAuthority.publishCount, 1);
    });

    test('candidate without backup rejects changed source metadata', () {
      final fixture = _PromotionFixture(workspace);
      final pending = fixture.prepareWal();
      final candidate = fixture.store.readPromotionSourceBlob(
        pending.candidateSourceBlobDigest,
      );
      final staged = fixture.atomicWriter.stage(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        subject: fixture.subject,
        relativeSourcePath: pending.relativeSourcePath,
        bytes: candidate,
      );
      fixture.atomicWriter.replace(
        staged,
        expectedCurrentDigest: pending.originalSourceDigest,
      );
      File(staged.stagingPath).deleteSync();
      expect(
        Process.runSync('chmod', <String>[
          '751',
          fixture.layoutFile.path,
        ]).exitCode,
        0,
      );

      expect(
        () => fixture.coordinator.recoverPending(
          configuration: fixture.configuration,
          contentAuthority: fixture.contentAuthority,
        ),
        throwsA(isA<ProjectionLayoutPromotionFailure>()),
      );

      expect(fixture.layoutFile.readAsBytesSync(), candidate);
      expect(_permissionBits(fixture.layoutFile.path), 0x1e9);
      expect(File(staged.stagingPath).existsSync(), isFalse);
      expect(
        fixture.store.pendingPromotions().single.intentId,
        pending.intentId,
      );
      expect(fixture.store.promotionHistory(fixture.subject), isEmpty);
      expect(fixture.contentAuthority.publishCount, 0);
    });

    test('recovery fails closed on a third source digest', () {
      final fixture = _PromotionFixture(workspace);
      fixture.prepareWal();
      final thirdParty = utf8.encode('{"thirdParty":true}\n');
      fixture.layoutFile.writeAsBytesSync(thirdParty, flush: true);

      expect(
        () => fixture.coordinator.recoverPending(
          configuration: fixture.configuration,
          contentAuthority: fixture.contentAuthority,
        ),
        throwsA(isA<ProjectionLayoutPromotionFailure>()),
      );
      expect(fixture.layoutFile.readAsBytesSync(), thirdParty);
      expect(fixture.store.pendingPromotions().single.intentId, 'promotion-1');
      expect(fixture.contentAuthority.publishCount, 0);
    });

    test('recovery preserves a conflicting orphan staging payload', () {
      final fixture = _PromotionFixture(workspace);
      final pending = fixture.prepareWal();
      final candidate = fixture.store.readPromotionSourceBlob(
        pending.candidateSourceBlobDigest,
      );
      final staged = fixture.atomicWriter.stage(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        subject: fixture.subject,
        relativeSourcePath: pending.relativeSourcePath,
        bytes: candidate,
      );
      final conflict = List<int>.filled(candidate.length, 0x20);
      File(staged.stagingPath).writeAsBytesSync(conflict, flush: true);

      expect(
        () => fixture.coordinator.recoverPending(
          configuration: fixture.configuration,
          contentAuthority: fixture.contentAuthority,
        ),
        throwsA(
          isA<ProjectionLayoutPromotionFailure>().having(
            (error) => error.phase,
            'phase',
            ProjectionLayoutPromotionPhase.recovery,
          ),
        ),
      );
      expect(File(staged.stagingPath).readAsBytesSync(), conflict);
      expect(
        fixture.store.pendingPromotions().single.intentId,
        pending.intentId,
      );
    });

    test('staging writer rejects a symlink at its deterministic path', () {
      final fixture = _PromotionFixture(workspace);
      final pending = fixture.prepareWal();
      final candidate = fixture.store.readPromotionSourceBlob(
        pending.candidateSourceBlobDigest,
      );
      final staged = fixture.atomicWriter.stage(
        workspaceRoot: fixture.configuration.workspaceRoot,
        contentRoot: fixture.configuration.contentRoot,
        subject: fixture.subject,
        relativeSourcePath: pending.relativeSourcePath,
        bytes: candidate,
      );
      File(staged.stagingPath).deleteSync();
      final external = File(p.join(workspace.path, 'external-stage'))
        ..writeAsBytesSync(candidate);
      Link(staged.stagingPath).createSync(external.path);

      expect(
        () => fixture.atomicWriter.stage(
          workspaceRoot: fixture.configuration.workspaceRoot,
          contentRoot: fixture.configuration.contentRoot,
          subject: fixture.subject,
          relativeSourcePath: pending.relativeSourcePath,
          bytes: candidate,
        ),
        throwsA(
          isA<ProjectionLayoutPreservingSwapFailure>().having(
            (failure) => failure.code,
            'code',
            ProjectionLayoutPreservingSwapFailureCode.unsafeEntity,
          ),
        ),
      );
      expect(Link(staged.stagingPath).existsSync(), isTrue);
      expect(external.readAsBytesSync(), candidate);
    });
  });
}

final class _PromotionFixture {
  _PromotionFixture(
    this.workspace, {
    ExperienceAuthoringStateWriter? stateWriter,
    ProjectionLayoutAtomicFileWriter? fileWriter,
  }) {
    _writeWorkspace(workspace);
    final corpus = const BoundedWorkspaceAuthoringLoader().load(
      startPath: workspace.path,
    );
    configuration = corpus.configuration;
    currentContent = const ProjectionLayoutPromotionCompiler().compileCurrent(
      corpus,
    );
    baseLayout = currentContent.experienceBundle!.layouts.single;
    final sourceDocument = corpus.documents.singleWhere(
      (document) => document.kind == AuthoringKind.projectionLayout,
    );
    source = corpus.sources[sourceDocument.sourceName]!;
    contentAuthority = _TestContentAuthority();
    final opened = const LayoutDraftEngine().openDraft(
      id: LayoutDraftId('draft'),
      subject: subject,
      baseLayout: baseLayout,
      baseSourceDigest: source.digest,
      contentSetDigest: contentAuthority.previewContentSetDigest(
        currentContent,
      ),
    );
    store = FilesystemExperienceAuthoringStore(
      workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
      writer: stateWriter ?? const DefaultExperienceAuthoringStateWriter(),
      guardTimeout: const Duration(milliseconds: 250),
    );
    store.openOrResumeDraft(
      ownerPrincipalId: owner,
      draft: opened,
      baseLayout: baseLayout,
    );
    draft = const LayoutDraftEngine().applyMove(
      draft: opened,
      baseLayout: baseLayout,
      input: LayoutMoveNodeInput(
        nodeInstanceId: NodeInstanceId('node'),
        toX: 125,
        toY: 245,
      ),
    );
    store.replaceDraft(
      ownerPrincipalId: owner,
      expectedDraftDigest: opened.digest,
      draft: draft,
    );
    changeSet = const LayoutDraftEngine().createChangeSet(
      id: ExperienceChangeSetId('changeset-1'),
      draft: draft,
      baseLayout: baseLayout,
      currentContentSetDigest: draft.contentSetDigest,
      currentSourceDigest: draft.baseSourceDigest,
    );
    final topology = currentContent.experienceBundle!.topology;
    const reviewCompiler = ExperienceReviewPacketCompiler();
    final initial = reviewCompiler.compile(
      id: ExperienceReviewPacketId('review-1'),
      changeSet: changeSet,
      catalog: currentContent.catalog,
      topology: topology,
      allowedArtifactDigests: const <Digest>{},
      reviewGuideBinding: ExecutableReviewGuideBinding(
        catalogDigest: currentContent.catalog.digest,
        applicationId: subject.applicationId,
        reviewGuideId: ReviewGuideId('layout-review'),
        stepId: 'inspect-layout',
        scenarioId: ScenarioId('scenario'),
        bindingId: ScenarioExecutionBindingId('scenario-binding'),
      ),
      findings: const <ExperienceFindingRecord>[],
      concepts: const <ExperienceConceptProposalRecord>[],
      comments: const <ExperienceReviewCommentRecord>[],
      automatedAcceptance: null,
      humanDecisions: const <ExperienceHumanDecisionRecord>[],
    );
    final accepted = reviewCompiler.recordAcceptance(
      packet: initial,
      changeSet: changeSet,
      catalog: currentContent.catalog,
      topology: topology,
      allowedArtifactDigests: const <Digest>{},
      outcome: AutomatedAcceptanceOutcome.passed,
      recordedAt: DateTime.utc(2026, 8, 17),
    );
    reviewPacket = reviewCompiler.appendDecision(
      packet: accepted,
      changeSet: changeSet,
      catalog: currentContent.catalog,
      topology: topology,
      allowedArtifactDigests: const <Digest>{},
      id: ExperienceHumanDecisionId('decision-1'),
      input: AppendExperienceHumanDecisionInput(
        decision: ExperienceHumanDecision.approve,
        rationale: 'The moved frame remains legible.',
      ),
      principalId: owner,
      authorityId: AuthoringAuthorityId('local-authority'),
      grantDigest: Digest.semantic('decision-grant'),
      recordedAt: DateTime.utc(2026, 8, 17, 1),
    );
    atomicWriter =
        fileWriter ?? const FilesystemProjectionLayoutAtomicFileWriter();
    coordinator = ProjectionLayoutPromotionCoordinator(
      store: store,
      fileWriter: atomicWriter,
    );
  }

  final Directory workspace;
  final AuthoringPrincipalId owner = AuthoringPrincipalId('local-author');
  final AuthoringSubjectRef subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace'),
    applicationId: ApplicationId('app'),
    projectionId: ExperienceProjectionId('projection'),
  );

  late final LoadedWorkspaceConfiguration configuration;
  late final HostWorkspaceContent currentContent;
  late final ProjectionLayoutManifest baseLayout;
  late final BoundedAuthoringSource source;
  late final FilesystemExperienceAuthoringStore store;
  late final LayoutDraft draft;
  late final ExperienceChangeSet changeSet;
  late final ExperienceReviewPacket reviewPacket;
  late final _TestContentAuthority contentAuthority;
  late final ProjectionLayoutAtomicFileWriter atomicWriter;
  late final ProjectionLayoutPromotionCoordinator coordinator;

  File get layoutFile => File(p.join(configuration.contentRoot, 'layout.yaml'));

  ExperiencePromotionReceipt promote() => coordinator.promote(
    configuration: configuration,
    subject: subject,
    intentId: 'promotion-1',
    receiptId: ExperiencePromotionReceiptId('receipt-1'),
    changeSet: changeSet,
    reviewPacket: reviewPacket,
    allowedArtifactDigests: const <Digest>{},
    grantDigest: Digest.semantic('promotion-grant'),
    promotedAt: DateTime.utc(2026, 8, 17, 2),
    contentAuthority: contentAuthority,
  );

  _EffectPromotionBinding issuePromotionEffect() {
    final intent = ExperiencePromotionGrantRequest(
      requestId: AuthoringRequestId('promotion-grant-request'),
      capabilityDigest: Digest.semantic('fixture-authoring-capability'),
      subject: subject,
      draftId: draft.id,
      draftDigest: draft.digest,
      draftRevision: draft.revision,
      changeSetId: changeSet.id,
      changeSetDigest: changeSet.digest,
      reviewPacketId: reviewPacket.id,
      reviewPacketDigest: reviewPacket.digest,
      expectedSourceDigest: draft.baseSourceDigest,
      expectedContentSetDigest: draft.contentSetDigest,
      candidateLayoutDigest: draft.candidateLayoutDigest,
    );
    final grant = AuthoringActionGrant(
      id: AuthoringActionGrantId('promotion-effect-grant'),
      requestId: intent.requestId,
      requestDigest: intent.digest,
      payloadDigest: intent.payloadDigest,
      authorityId: AuthoringAuthorityId('local-authority'),
      policyId: AuthoringPolicyId('local-policy'),
      principalId: owner,
      capabilityDigest: intent.capabilityDigest,
      subject: subject,
      effect: intent.effect,
      operation: intent.operation,
      expectedDigest: intent.expectedDigest,
      expectedSourceDigest: intent.expectedSourceDigest,
      issuedAt: DateTime.utc(2026, 8, 17, 1, 30),
      expiresAt: DateTime.utc(2026, 8, 17, 1, 35),
      singleUse: true,
    );
    final grantResult = AuthoringGrantResult(
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
          subject: subject,
          effect: intent.effect,
          operation: intent.operation,
          grantId: null,
          grantDigest: null,
          isError: false,
          terminalJson: grantResult.toJson(),
          completedAt: grant.issuedAt,
        ),
        issuedGrant: StoredAuthoringGrant(
          grant: grant,
          intentKind: 'ExperiencePromotionGrantRequest',
          intentJson: intent.toJson(),
          connectionEpoch: 'connection-1',
          state: StoredAuthoringGrantState.active,
          stateChangedAt: grant.issuedAt,
        ),
      ),
    );
    final request = ExperiencePromotionApplyRequest(
      requestId: AuthoringRequestId('promotion-effect-request'),
      subject: subject,
      draftId: draft.id,
      draftDigest: draft.digest,
      draftRevision: draft.revision,
      changeSetId: changeSet.id,
      changeSetDigest: changeSet.digest,
      reviewPacketId: reviewPacket.id,
      reviewPacketDigest: reviewPacket.digest,
      expectedSourceDigest: draft.baseSourceDigest,
      expectedContentSetDigest: draft.contentSetDigest,
      candidateLayoutDigest: draft.candidateLayoutDigest,
      grantId: grant.id,
      grantDigest: grant.digest,
    );
    final error = ExperienceAuthoringError(
      code: ExperienceAuthoringErrorCode.unavailable,
      requestId: request.requestId,
      subject: subject,
      operation: AuthoringOperation.promote,
      draftId: draft.id,
      changeSetId: changeSet.id,
      reviewPacketId: reviewPacket.id,
    );
    final rollbackAttempt = StoredAuthoringAttempt(
      family: StoredAuthoringAttemptFamily.promotionApply,
      requestId: request.requestId,
      requestDigest: request.digest,
      payloadDigest: request.payloadDigest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.promote,
      grantId: grant.id,
      grantDigest: grant.digest,
      isError: true,
      terminalJson: error.toJson(),
      completedAt: DateTime.utc(2026, 8, 17, 2),
    );
    return _EffectPromotionBinding(
      intent: intent,
      grant: grant,
      request: request,
      rollbackAttempt: rollbackAttempt,
    );
  }

  StoredProjectionLayoutPromotion prepareEffectWal(
    _EffectPromotionBinding effect,
  ) {
    final corpus = const BoundedWorkspaceAuthoringLoader()
        .loadFromConfiguration(configuration);
    final candidateLayout = const LayoutDraftEngine().materialize(
      draft: draft,
      baseLayout: baseLayout,
    );
    final prepared = const ProjectionLayoutPromotionCompiler().prepare(
      corpus: corpus,
      subject: subject,
      expectedBaseLayoutDigest: draft.baseLayoutDigest,
      expectedSourceDigest: draft.baseSourceDigest,
      candidateLayout: candidateLayout,
    );
    final receipt = ExperiencePromotionReceipt(
      id: ExperiencePromotionReceiptId('receipt-effect'),
      sequence: 1,
      previousReceiptDigest: null,
      subject: subject,
      draftId: draft.id,
      draftDigest: draft.digest,
      draftRevision: draft.revision,
      sourceDigest: prepared.originalSourceDigest,
      resultSourceDigest: prepared.candidateSourceDigest,
      previousContentSetDigest: contentAuthority.previewContentSetDigest(
        prepared.currentContent,
      ),
      resultContentSetDigest: contentAuthority.previewContentSetDigest(
        prepared.candidateContent,
      ),
      layoutDigest: prepared.candidateLayout.digest,
      changeSetId: changeSet.id,
      changeSetDigest: changeSet.digest,
      reviewPacketId: reviewPacket.id,
      reviewPacketDigest: reviewPacket.digest,
      promotedAt: DateTime.utc(2026, 8, 17, 2),
    );
    final result = ExperiencePromotionApplyResult(
      requestId: effect.request.requestId,
      receipt: receipt,
      head: ExperienceAuthoringSubjectHead(
        subject: subject,
        latestPromotion: ExperiencePromotionHeadRef.fromReceipt(receipt),
      ),
    );
    final successAttempt = StoredAuthoringAttempt(
      family: StoredAuthoringAttemptFamily.promotionApply,
      requestId: effect.request.requestId,
      requestDigest: effect.request.digest,
      payloadDigest: effect.request.payloadDigest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.promote,
      grantId: effect.grant.id,
      grantDigest: effect.grant.digest,
      isError: false,
      terminalJson: result.toJson(),
      completedAt: DateTime.utc(2026, 8, 17, 2),
    );
    final staged = atomicWriter.stage(
      workspaceRoot: configuration.workspaceRoot,
      contentRoot: configuration.contentRoot,
      subject: subject,
      relativeSourcePath: prepared.relativeSourcePath,
      bytes: prepared.candidateSourceBytes,
    );
    return store.preparePromotion(
      promotion: StoredProjectionLayoutPromotion(
        intentId: 'promotion-effect',
        subject: subject,
        relativeSourcePath: prepared.relativeSourcePath,
        replaceProtocol: projectionLayoutPreservingSwapProtocol,
        replaceProviderKind: projectionLayoutLinuxX64SwapProvider,
        recoverySlot: const FilesystemProjectionLayoutAtomicFileWriter()
            .recoverySlot(
              subject: subject,
              relativeSourcePath: prepared.relativeSourcePath,
            ),
        configurationAuthorityDigest:
            projectionLayoutPromotionConfigurationAuthorityDigest(
              configuration,
              subject,
            ),
        sourceMetadataDigest: staged.sourceMetadataDigest,
        originalSourceBlobDigest: prepared.originalSourceDigest,
        candidateSourceBlobDigest: prepared.candidateSourceDigest,
        originalCompiledCorpusDigest: projectionLayoutPromotionContentDigest(
          prepared.currentContent,
        ),
        candidateCompiledCorpusDigest: projectionLayoutPromotionContentDigest(
          prepared.candidateContent,
        ),
        receipt: receipt,
        grantDigest: effect.grant.digest,
        successAttempt: successAttempt,
        rollbackAttempt: effect.rollbackAttempt,
        preparedAt: DateTime.utc(2026, 8, 17, 2),
      ),
      originalSourceBytes: prepared.originalSourceBytes,
      candidateSourceBytes: prepared.candidateSourceBytes,
    );
  }

  StoredProjectionLayoutPromotion prepareWal() {
    final corpus = const BoundedWorkspaceAuthoringLoader()
        .loadFromConfiguration(configuration);
    final candidateLayout = const LayoutDraftEngine().materialize(
      draft: draft,
      baseLayout: baseLayout,
    );
    final prepared = const ProjectionLayoutPromotionCompiler().prepare(
      corpus: corpus,
      subject: subject,
      expectedBaseLayoutDigest: draft.baseLayoutDigest,
      expectedSourceDigest: draft.baseSourceDigest,
      candidateLayout: candidateLayout,
    );
    final staged = atomicWriter.stage(
      workspaceRoot: configuration.workspaceRoot,
      contentRoot: configuration.contentRoot,
      subject: subject,
      relativeSourcePath: prepared.relativeSourcePath,
      bytes: prepared.candidateSourceBytes,
    );
    final pending = StoredProjectionLayoutPromotion(
      intentId: 'promotion-1',
      subject: subject,
      relativeSourcePath: prepared.relativeSourcePath,
      replaceProtocol: projectionLayoutPreservingSwapProtocol,
      replaceProviderKind: projectionLayoutLinuxX64SwapProvider,
      recoverySlot: const FilesystemProjectionLayoutAtomicFileWriter()
          .recoverySlot(
            subject: subject,
            relativeSourcePath: prepared.relativeSourcePath,
          ),
      configurationAuthorityDigest:
          projectionLayoutPromotionConfigurationAuthorityDigest(
            configuration,
            subject,
          ),
      sourceMetadataDigest: staged.sourceMetadataDigest,
      originalSourceBlobDigest: prepared.originalSourceDigest,
      candidateSourceBlobDigest: prepared.candidateSourceDigest,
      originalCompiledCorpusDigest: projectionLayoutPromotionContentDigest(
        prepared.currentContent,
      ),
      candidateCompiledCorpusDigest: projectionLayoutPromotionContentDigest(
        prepared.candidateContent,
      ),
      receipt: ExperiencePromotionReceipt(
        id: ExperiencePromotionReceiptId('receipt-1'),
        sequence: 1,
        previousReceiptDigest: null,
        subject: subject,
        draftId: draft.id,
        draftDigest: draft.digest,
        draftRevision: draft.revision,
        sourceDigest: prepared.originalSourceDigest,
        resultSourceDigest: prepared.candidateSourceDigest,
        previousContentSetDigest: contentAuthority.previewContentSetDigest(
          prepared.currentContent,
        ),
        resultContentSetDigest: contentAuthority.previewContentSetDigest(
          prepared.candidateContent,
        ),
        layoutDigest: prepared.candidateLayout.digest,
        changeSetId: changeSet.id,
        changeSetDigest: changeSet.digest,
        reviewPacketId: reviewPacket.id,
        reviewPacketDigest: reviewPacket.digest,
        promotedAt: DateTime.utc(2026, 8, 17, 2),
      ),
      grantDigest: Digest.semantic('promotion-grant'),
      preparedAt: DateTime.utc(2026, 8, 17, 2),
    );
    return store.preparePromotion(
      promotion: pending,
      originalSourceBytes: prepared.originalSourceBytes,
      candidateSourceBytes: prepared.candidateSourceBytes,
    );
  }
}

final class _EffectPromotionBinding {
  const _EffectPromotionBinding({
    required this.intent,
    required this.grant,
    required this.request,
    required this.rollbackAttempt,
  });

  final ExperiencePromotionGrantRequest intent;
  final AuthoringActionGrant grant;
  final ExperiencePromotionApplyRequest request;
  final StoredAuthoringAttempt rollbackAttempt;
}

final class _TestContentAuthority implements ProjectionLayoutContentAuthority {
  bool failNextPublish = false;
  void Function()? afterPublish;
  int publishCount = 0;
  Digest? publishedDigest;

  @override
  Digest previewContentSetDigest(HostWorkspaceContent content) =>
      Digest.semantic(<String, Object?>{
        'testContentSet': projectionLayoutPromotionContentDigest(content).value,
      });

  @override
  Digest publish(HostWorkspaceContent content) {
    publishCount += 1;
    if (failNextPublish) {
      failNextPublish = false;
      throw StateError('injected content publication failure');
    }
    final result = publishedDigest = previewContentSetDigest(content);
    afterPublish?.call();
    return result;
  }
}

final class _FaultingAtomicWriter implements ProjectionLayoutAtomicFileWriter {
  _FaultingAtomicWriter({this.moveThenError = false, this.beforeReplace});

  final bool moveThenError;
  final void Function(ProjectionLayoutStagedWrite staged)? beforeReplace;
  final FilesystemProjectionLayoutAtomicFileWriter delegate =
      const FilesystemProjectionLayoutAtomicFileWriter();
  var _beforeReplaceCalled = false;

  @override
  String get replaceProtocol => delegate.replaceProtocol;

  @override
  String get replaceProviderKind => delegate.replaceProviderKind;

  @override
  void requireSupported() => delegate.requireSupported();

  @override
  String recoverySlot({
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
  }) => delegate.recoverySlot(
    subject: subject,
    relativeSourcePath: relativeSourcePath,
  );

  @override
  ProjectionLayoutStagedWrite stage({
    required String workspaceRoot,
    required String contentRoot,
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
    required List<int> bytes,
  }) => delegate.stage(
    workspaceRoot: workspaceRoot,
    contentRoot: contentRoot,
    subject: subject,
    relativeSourcePath: relativeSourcePath,
    bytes: bytes,
  );

  @override
  ProjectionLayoutStagedWrite bindStaged({
    required String workspaceRoot,
    required String contentRoot,
    required AuthoringSubjectRef subject,
    required String relativeSourcePath,
    required Digest digest,
    required int byteLength,
    required Digest sourceMetadataDigest,
  }) => delegate.bindStaged(
    workspaceRoot: workspaceRoot,
    contentRoot: contentRoot,
    subject: subject,
    relativeSourcePath: relativeSourcePath,
    digest: digest,
    byteLength: byteLength,
    sourceMetadataDigest: sourceMetadataDigest,
  );

  @override
  ProjectionLayoutAtomicReplaceReceipt replace(
    ProjectionLayoutStagedWrite staged, {
    required Digest expectedCurrentDigest,
  }) {
    if (!_beforeReplaceCalled && beforeReplace != null) {
      _beforeReplaceCalled = true;
      beforeReplace!(staged);
    }
    final receipt = delegate.replace(
      staged,
      expectedCurrentDigest: expectedCurrentDigest,
    );
    if (moveThenError) {
      throw StateError('injected error after preserving swap');
    }
    return receipt;
  }

  @override
  ProjectionLayoutRecoverySlotObservation inspectRecoverySlot({
    required String workspaceRoot,
    required String contentRoot,
    required String relativeSourcePath,
    required String recoverySlot,
  }) => delegate.inspectRecoverySlot(
    workspaceRoot: workspaceRoot,
    contentRoot: contentRoot,
    relativeSourcePath: relativeSourcePath,
    recoverySlot: recoverySlot,
  );

  @override
  ProjectionLayoutAtomicReplaceReceipt exchangeRecoverySlot({
    required String workspaceRoot,
    required String contentRoot,
    required String relativeSourcePath,
    required String recoverySlot,
    required Digest expectedDestinationDigest,
    required Digest expectedRecoveryDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedRecoveryMetadataDigest,
  }) => delegate.exchangeRecoverySlot(
    workspaceRoot: workspaceRoot,
    contentRoot: contentRoot,
    relativeSourcePath: relativeSourcePath,
    recoverySlot: recoverySlot,
    expectedDestinationDigest: expectedDestinationDigest,
    expectedRecoveryDigest: expectedRecoveryDigest,
    expectedDestinationMetadataDigest: expectedDestinationMetadataDigest,
    expectedRecoveryMetadataDigest: expectedRecoveryMetadataDigest,
  );

  @override
  List<int> readStaged(ProjectionLayoutStagedWrite staged) =>
      delegate.readStaged(staged);
}

final class _UnsupportedAtExchangeSwapPrimitive
    implements ProjectionLayoutPreservingSwapPrimitive {
  const _UnsupportedAtExchangeSwapPrimitive();

  @override
  String get providerKind => projectionLayoutLinuxX64SwapProvider;

  @override
  bool get isSupported => true;

  @override
  ProjectionLayoutPrivateStageResult stage({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required List<int> bytes,
    required int maxBytes,
  }) => const LinuxX64ProjectionLayoutPreservingSwap().stage(
    contentRoot: contentRoot,
    destinationRelativePath: destinationRelativePath,
    workspaceRoot: workspaceRoot,
    stagingRelativePath: stagingRelativePath,
    bytes: bytes,
    maxBytes: maxBytes,
  );

  @override
  Uint8List readStaging({
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) => const LinuxX64ProjectionLayoutPreservingSwap().readStaging(
    workspaceRoot: workspaceRoot,
    stagingRelativePath: stagingRelativePath,
    maxBytes: maxBytes,
  );

  @override
  ProjectionLayoutPreservingSwapResult exchange({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required Digest expectedDestinationDigest,
    required Digest expectedStagingDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedStagingMetadataDigest,
    required int maxBytes,
  }) => throw const ProjectionLayoutPreservingSwapFailure.unsupported();

  @override
  ProjectionLayoutPreservingSwapObservation observe({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) => const LinuxX64ProjectionLayoutPreservingSwap().observe(
    contentRoot: contentRoot,
    destinationRelativePath: destinationRelativePath,
    workspaceRoot: workspaceRoot,
    stagingRelativePath: stagingRelativePath,
    maxBytes: maxBytes,
  );
}

final class _UnavailableSwapPrimitive
    implements ProjectionLayoutPreservingSwapPrimitive {
  const _UnavailableSwapPrimitive();

  @override
  String get providerKind => projectionLayoutLinuxX64SwapProvider;

  @override
  bool get isSupported => false;

  @override
  ProjectionLayoutPrivateStageResult stage({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required List<int> bytes,
    required int maxBytes,
  }) => throw const ProjectionLayoutPreservingSwapFailure.unsupported();

  @override
  Uint8List readStaging({
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) => throw const ProjectionLayoutPreservingSwapFailure.unsupported();

  @override
  ProjectionLayoutPreservingSwapResult exchange({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required Digest expectedDestinationDigest,
    required Digest expectedStagingDigest,
    required Digest expectedDestinationMetadataDigest,
    required Digest expectedStagingMetadataDigest,
    required int maxBytes,
  }) => throw const ProjectionLayoutPreservingSwapFailure.unsupported();

  @override
  ProjectionLayoutPreservingSwapObservation observe({
    required String contentRoot,
    required String destinationRelativePath,
    required String workspaceRoot,
    required String stagingRelativePath,
    required int maxBytes,
  }) => throw const ProjectionLayoutPreservingSwapFailure.unsupported();
}

final class _MoveThenErrorStateWriter
    implements ExperienceAuthoringStateWriter {
  int writeCount = 0;
  int? failOnWrite;
  bool didFail = false;

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
    final receipt = const DefaultExperienceAuthoringStateWriter().write(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
      expectedCurrentBytes: expectedCurrentBytes,
    );
    if (relativePath == FilesystemExperienceAuthoringStore.statePath) {
      writeCount += 1;
    }
    if (relativePath == FilesystemExperienceAuthoringStore.statePath &&
        writeCount == failOnWrite) {
      didFail = true;
      throw StateError('injected error after journal replacement');
    }
    return receipt;
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

int _permissionBits(String path) => FileStat.statSync(path).mode & 0xfff;

String _ownerGroup(String path) {
  final result = Process.runSync('stat', <String>['-c', '%u:%g', path]);
  if (result.exitCode != 0) {
    throw StateError('Unable to inspect fixture ownership');
  }
  return (result.stdout as String).trim();
}

String _deviceId(String path) {
  final result = Process.runSync('stat', <String>['-c', '%d', path]);
  if (result.exitCode != 0) {
    throw StateError('Unable to inspect fixture device');
  }
  return (result.stdout as String).trim();
}

void _writeWorkspace(Directory workspace) {
  final content = Directory(p.join(workspace.path, '.experience'))
    ..createSync();
  File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: workspace, displayName: Workspace}
applications:
  app: {root: ., target: web, displayName: App}
kit: {profile: full-local, modules: {}}
''');
  _writeJson(File(p.join(content.path, 'scenario.json')), <String, Object?>{
    'schemaVersion': 1,
    'kind': 'Scenario',
    'metadata': <String, Object?>{'id': 'scenario'},
    'spec': <String, Object?>{'applicationId': 'app', 'title': 'Scenario'},
  });
  _writeJson(File(p.join(content.path, 'binding.json')), <String, Object?>{
    'schemaVersion': 1,
    'kind': 'ScenarioExecutionBinding',
    'metadata': <String, Object?>{'id': 'scenario-binding'},
    'spec': <String, Object?>{
      'scenarioId': 'scenario',
      'targetId': 'browser',
      'launchProfileId': 'app-web',
    },
  });
  _writeJson(File(p.join(content.path, 'review.json')), <String, Object?>{
    'schemaVersion': 1,
    'kind': 'ReviewGuide',
    'metadata': <String, Object?>{'id': 'layout-review'},
    'spec': <String, Object?>{
      'applicationId': 'app',
      'title': 'Layout review',
      'steps': <Object?>[
        <String, Object?>{
          'id': 'inspect-layout',
          'instruction': 'Inspect the moved frame.',
          'observationCriteria': 'The frame remains legible.',
          'scenarioId': 'scenario',
          'bindingId': 'scenario-binding',
        },
      ],
    },
  });
  _writeJson(File(p.join(content.path, 'board.json')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'Board',
    'metadata': <String, Object?>{'id': 'board'},
    'spec': <String, Object?>{
      'applicationId': 'app',
      'title': 'Board',
      'projectionIds': <String>['projection'],
    },
  });
  _writeJson(File(p.join(content.path, 'projection.json')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'ExperienceProjection',
    'metadata': <String, Object?>{'id': 'projection'},
    'spec': <String, Object?>{
      'boardId': 'board',
      'applicationId': 'app',
      'title': 'Projection',
      'projectionKind': 'inventory',
      'nodeInstanceIds': <String>['node'],
      'edgeInstanceIds': <String>[],
    },
  });
  _writeJson(File(p.join(content.path, 'node.json')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'NodeInstance',
    'metadata': <String, Object?>{'id': 'node'},
    'spec': <String, Object?>{
      'projectionId': 'projection',
      'scenarioId': 'scenario',
    },
  });
  _writeJson(File(p.join(content.path, 'layout.yaml')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'ProjectionLayout',
    'metadata': <String, Object?>{'id': 'projection'},
    'spec': <String, Object?>{
      'projectionId': 'projection',
      'nodeFrames': <Object?>[
        <String, Object?>{
          'nodeInstanceId': 'node',
          'x': 10,
          'y': 20,
          'width': 300,
          'height': 180,
        },
      ],
      'groups': <Object?>[],
      'lanes': <Object?>[],
      'annotations': <Object?>[],
      'camera': <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
    },
  });
}

void _writeJson(File file, Map<String, Object?> value) {
  file.writeAsStringSync('${jsonEncode(value)}\n');
}
