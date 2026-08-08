import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'captures all sample AutoPreview variants in isolated Flutter processes',
    () async {
      final repositoryRoot = p.normalize(p.absolute('.'));
      final sampleRoot = p.join(repositoryRoot, 'examples', 'sample_flutter');
      final scan = await const PreviewSourceScanner().scan(
        applicationRoot: sampleRoot,
      );
      final loaded = const WorkspaceCatalogLoader().load(startPath: sampleRoot);
      final catalog = const CatalogCompiler().compile(loaded.documents);
      final previewManifest = const PreviewManifestCompiler().compile(
        candidates: scan.candidates,
        catalog: catalog,
        flutterCompatibility: PreviewSourceScanner.flutterCompatibility,
      );
      final planDigest = Digest.semantic(const <String, Object?>{
        'profile': 'journey-preview',
        'test': 'capture-integration',
      });
      final registry = await const EphemeralPreviewRegistryWriter().write(
        applicationRoot: sampleRoot,
        planDigest: planDigest,
        manifest: previewManifest,
        scan: scan,
      );
      final store = FileSystemWorkspaceStore(
        workspaceRoot: sampleRoot,
        distributionId: 'devex-preview-integration',
      );
      addTearDown(() async {
        final registryDirectory = Directory(registry.directory);
        if (registryDirectory.existsSync()) {
          await registryDirectory.delete(recursive: true);
        }
        final stateDirectory = Directory(store.stateRoot);
        if (stateDirectory.existsSync()) {
          await stateDirectory.delete(recursive: true);
        }
      });
      final toolchainDigest = Digest.semantic(const <String, Object?>{
        'flutter': '3.44.8',
        'dart': '3.12.2',
        'renderer': 'flutter-test',
      });
      final fingerprint = ExecutionFingerprint(
        catalogDigest: catalog.digest,
        launchProfileId: 'preview-static-v1',
        targetId: 'preview.flutter-test',
        platform: 'linux-x64',
        renderer: 'flutter-test',
        runtimeFidelity: RuntimeFidelity.structural,
        backendMode: BackendMode.none,
        networkContainment: NetworkContainment.unconstrained,
        bootstrapAssessment: BootstrapAssessment.controlled,
        toolchain: const <String, String>{
          'flutter': '3.44.8',
          'dart': '3.12.2',
        },
        capabilities: const <String>{'evidence.visual.preview'},
        inputDigests: <String, Digest>{
          'plan': planDigest,
          'previewManifest': previewManifest.digest,
        },
        policies: const <String, String>{'capture': 'static-v1'},
      );
      final run = await PreviewCaptureRunner(store: store).run(
        applicationRoot: sampleRoot,
        previewManifest: previewManifest,
        registry: registry,
        fingerprint: fingerprint,
        planDigest: planDigest,
        toolchainDigest: toolchainDigest,
        policies: <String, PreviewStabilizationPolicy>{
          'static-v1': PreviewStabilizationPolicy(id: 'static-v1'),
        },
        syntheticDataConfirmed: true,
        inputDigests: <String, Digest>{
          'pubspecLock': Digest.bytes(
            File(p.join(repositoryRoot, 'pubspec.lock')).readAsBytesSync(),
          ),
        },
      );

      expect(run.report.totalItems, 7);
      expect(run.report.collectedItems, 7);
      expect(run.report.failedItems, 0);
      for (final item in run.manifest.items) {
        expect(item.status, PreviewCaptureStatus.collected);
        expect(item.pixelWidth, greaterThanOrEqualTo(1170));
        expect(item.pixelHeight, greaterThanOrEqualTo(900));
        expect(store.readBlob(item.artifactDigest!), isNotNull);
      }
      expect(
        Directory(registry.directory).listSync().whereType<File>(),
        hasLength(2),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
