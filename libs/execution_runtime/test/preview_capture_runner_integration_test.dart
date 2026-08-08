import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

import 'support/temporary_preview_consumer.dart';

void main() {
  test(
    'captures all fixture AutoPreview variants in isolated Flutter processes',
    () async {
      final consumer = TemporaryPreviewConsumer.create();
      addTearDown(consumer.dispose);
      final scan = await const PreviewSourceScanner().scan(
        applicationRoot: consumer.root.path,
      );
      final catalog = consumer.catalog();
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
        applicationRoot: consumer.root.path,
        planDigest: planDigest,
        manifest: previewManifest,
        scan: scan,
      );
      final store = FileSystemWorkspaceStore(
        workspaceRoot: consumer.root.path,
        distributionId: 'workspace-preview-integration',
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
        applicationRoot: consumer.root.path,
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
          'packageConfig': Digest.bytes(
            File(consumer.packageConfigPath).readAsBytesSync(),
          ),
          'previewSource': Digest.bytes(
            consumer.previewSource.readAsBytesSync(),
          ),
        },
      );

      final diagnostics = <String>[
        for (final item in run.manifest.items)
          if (item.status != PreviewCaptureStatus.collected)
            '${item.key}: ${item.diagnostics.map((value) => '${value.code}: ${value.message}').join(' | ')}',
        for (final diagnostic in run.report.diagnostics)
          '${diagnostic.code}: ${diagnostic.message}',
      ].join('\n');
      expect(run.report.totalItems, 7);
      expect(run.report.collectedItems, 7, reason: diagnostics);
      expect(run.report.failedItems, 0, reason: diagnostics);
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
