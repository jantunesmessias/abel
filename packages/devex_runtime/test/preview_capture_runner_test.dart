import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory root;
  late FileSystemWorkspaceStore store;
  late PreviewManifest previewManifest;
  late PreviewSourceScanResult scan;
  late EphemeralPreviewRegistry registry;
  late ExecutionFingerprint fingerprint;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('devex-preview-runner-');
    store = FileSystemWorkspaceStore(workspaceRoot: root.path);
    previewManifest = _manifest();
    scan = _scan();
    registry = await const EphemeralPreviewRegistryWriter().write(
      applicationRoot: root.path,
      planDigest: Digest.semantic(const <String, Object?>{'test': 'registry'}),
      manifest: previewManifest,
      scan: scan,
    );
    fingerprint = _fingerprint(previewManifest.catalogDigest);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('keeps a valid capture when another item fails', () async {
    final executor = _FakeExecutor(writeCount: 1, exitCode: 1);
    final run =
        await PreviewCaptureRunner(
          store: store,
          processExecutor: executor,
          clock: const _Clock(),
        ).run(
          applicationRoot: root.path,
          previewManifest: previewManifest,
          registry: registry,
          fingerprint: fingerprint,
          planDigest: _planDigest,
          toolchainDigest: _toolchainDigest,
          policies: _policies,
          syntheticDataConfirmed: true,
        );

    expect(executor.calls, 2);
    expect(run.report.collectedItems, 1);
    expect(run.report.failedItems, 1);
    expect(
      run.manifest.items.map((item) => item.status),
      <PreviewCaptureStatus>[
        PreviewCaptureStatus.collected,
        PreviewCaptureStatus.failed,
      ],
    );
    final collected = run.manifest.items.first;
    expect(store.readBlob(collected.artifactDigest!), isNotNull);
    expect(
      Directory(registry.directory).listSync().whereType<File>(),
      hasLength(2),
    );
  });

  test(
    'denies pixels before execution without synthetic confirmation',
    () async {
      final executor = _FakeExecutor(writeCount: 2);
      final run =
          await PreviewCaptureRunner(
            store: store,
            processExecutor: executor,
            clock: const _Clock(),
          ).run(
            applicationRoot: root.path,
            previewManifest: previewManifest,
            registry: registry,
            fingerprint: fingerprint,
            planDigest: _planDigest,
            toolchainDigest: _toolchainDigest,
            policies: _policies,
            syntheticDataConfirmed: false,
          );

      expect(executor.calls, 0);
      expect(
        run.manifest.items.map((item) => item.status).toSet(),
        <PreviewCaptureStatus>{PreviewCaptureStatus.policyDenied},
      );
    },
  );

  test('invalid PNG is isolated and timeout has a closed diagnostic', () async {
    final invalid =
        await PreviewCaptureRunner(
          store: store,
          processExecutor: _FakeExecutor(writeCount: 2, invalid: true),
          clock: const _Clock(),
        ).run(
          applicationRoot: root.path,
          previewManifest: previewManifest,
          registry: registry,
          fingerprint: fingerprint,
          planDigest: _planDigest,
          toolchainDigest: _toolchainDigest,
          policies: _policies,
          syntheticDataConfirmed: true,
        );
    expect(
      invalid.manifest.items.map((item) => item.status).toSet(),
      <PreviewCaptureStatus>{PreviewCaptureStatus.invalid},
    );

    final timedOut =
        await PreviewCaptureRunner(
          store: store,
          processExecutor: _FakeExecutor(writeCount: 0, timedOut: true),
          clock: const _Clock(),
        ).run(
          applicationRoot: root.path,
          previewManifest: previewManifest,
          registry: registry,
          fingerprint: fingerprint,
          planDigest: _planDigest,
          toolchainDigest: _toolchainDigest,
          policies: _policies,
          syntheticDataConfirmed: true,
        );
    expect(
      timedOut.manifest.items.first.diagnostics.single.code,
      'preview.capture.timeout',
    );
    expect(
      Directory(registry.directory).listSync().whereType<File>(),
      hasLength(2),
    );
  });

  test('cancellation prevents remaining preview subprocesses', () async {
    final token = PreviewCancellationToken();
    final executor = _FakeExecutor(
      writeCount: 0,
      cancellationTokenToTrigger: token,
    );
    final progress = <int>[];

    final run =
        await PreviewCaptureRunner(
          store: store,
          processExecutor: executor,
          clock: const _Clock(),
        ).run(
          applicationRoot: root.path,
          previewManifest: previewManifest,
          registry: registry,
          fingerprint: fingerprint,
          planDigest: _planDigest,
          toolchainDigest: _toolchainDigest,
          policies: _policies,
          syntheticDataConfirmed: true,
          cancellationToken: token,
          onProgress: (completed, _) => progress.add(completed),
        );

    expect(executor.calls, 1);
    expect(token.isCancelled, isTrue);
    expect(run.report.failedItems, 2);
    expect(
      run.manifest.items.last.diagnostics.single.code,
      'preview.capture.cancelled',
    );
    expect(progress.last, 2);
  });

  test(
    'equivalent runs have equivalent manifests and deduplicated Evidence',
    () async {
      Future<PreviewCaptureRun> capture() =>
          PreviewCaptureRunner(
            store: store,
            processExecutor: _FakeExecutor(writeCount: 2),
            clock: const _Clock(),
          ).run(
            applicationRoot: root.path,
            previewManifest: previewManifest,
            registry: registry,
            fingerprint: fingerprint,
            planDigest: _planDigest,
            toolchainDigest: _toolchainDigest,
            policies: _policies,
            syntheticDataConfirmed: true,
          );

      final first = await capture();
      final second = await capture();
      expect(first.manifest.digest, second.manifest.digest);
      expect(first.report.digest, second.report.digest);
      expect(
        first.manifest.items.map((item) => item.artifactDigest).toSet(),
        hasLength(1),
      );

      final repository = LocalEvidenceRepository(
        store: store,
        clock: const _Clock(),
        ids: _Ids(),
      );
      final evidence = PreviewEvidenceProvider(
        store: store,
        repository: repository,
        clock: const _Clock(),
        ids: _Ids(),
      ).persist(run: first, fingerprint: fingerprint);
      expect(evidence.fingerprint.runtimeFidelity, RuntimeFidelity.structural);
      expect(evidence.artifacts, hasLength(2));
      expect(repository.readLatestEvidence()!.digest, evidence.digest);
    },
  );
}

final _planDigest = Digest(
  'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
);
final _toolchainDigest = Digest(
  'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
);

final Map<String, PreviewStabilizationPolicy> _policies =
    <String, PreviewStabilizationPolicy>{
      'static-v1': PreviewStabilizationPolicy(id: 'static-v1'),
    };

PreviewManifest _manifest() => PreviewManifest(
  catalogDigest: Digest.semantic(const <String, Object?>{'catalog': 1}),
  flutterCompatibility: '3.44.x',
  descriptors: <PreviewDescriptor>[
    _descriptor('dark', PreviewBrightness.dark),
    _descriptor('light', PreviewBrightness.light),
  ],
);

PreviewDescriptor _descriptor(String id, PreviewBrightness brightness) =>
    PreviewDescriptor(
      id: AutoPreviewId('sample.launch'),
      scenarioId: ScenarioId('launch-sample'),
      variant: Variant(
        id: VariantId('phone.$id'),
        applicationId: ApplicationId('sample'),
        logicalWidth: 2,
        logicalHeight: 2,
        devicePixelRatio: 1,
        brightness: brightness,
        localeTag: 'pt-BR',
      ),
      sourceUri: 'package:sample_flutter/previews/launch_previews.dart',
      declarationName: 'launchSamplePreviews',
      capturePolicyId: 'static-v1',
      fixtureRef: 'sample.launch.synthetic',
    );

PreviewSourceScanResult _scan() =>
    PreviewSourceScanResult(<ScannedPreviewDeclaration>[
      ScannedPreviewDeclaration(
        candidate: PreviewDeclarationCandidate(
          id: 'sample.launch',
          scenarioId: 'launch-sample',
          sourceUri: 'package:sample_flutter/previews/launch_previews.dart',
          declarationName: 'launchSamplePreviews',
          capturePolicyId: 'static-v1',
          fixtureRef: 'sample.launch.synthetic',
          variants: <PreviewVariantCandidate>[
            _variant('phone.dark', PreviewBrightness.dark),
            _variant('phone.light', PreviewBrightness.light),
          ],
        ),
        returnKind: PreviewFactoryReturnKind.widget,
      ),
    ]);

PreviewVariantCandidate _variant(String id, PreviewBrightness brightness) =>
    PreviewVariantCandidate(
      id: id,
      logicalWidth: 2,
      logicalHeight: 2,
      devicePixelRatio: 1,
      brightness: brightness,
      localeTag: 'pt-BR',
      textScaleFactor: 1,
    );

ExecutionFingerprint _fingerprint(Digest catalogDigest) => ExecutionFingerprint(
  catalogDigest: catalogDigest,
  launchProfileId: 'preview-static-v1',
  targetId: 'preview.flutter-test',
  platform: 'linux-x64',
  renderer: 'flutter-test',
  runtimeFidelity: RuntimeFidelity.structural,
  backendMode: BackendMode.none,
  networkContainment: NetworkContainment.unconstrained,
  bootstrapAssessment: BootstrapAssessment.controlled,
  toolchain: const <String, String>{'flutter': '3.44.8', 'dart': '3.12.2'},
  capabilities: const <String>{'evidence.visual.preview'},
  inputDigests: <String, Digest>{'plan': _planDigest},
  policies: const <String, String>{'capture': 'static-v1'},
);

final class _FakeExecutor implements PreviewProcessExecutor {
  _FakeExecutor({
    required int writeCount,
    this.exitCode = 0,
    this.invalid = false,
    this.timedOut = false,
    this.cancellationTokenToTrigger,
  }) : _remainingWrites = writeCount;

  int _remainingWrites;
  final int exitCode;
  final bool invalid;
  final bool timedOut;
  final PreviewCancellationToken? cancellationTokenToTrigger;
  int calls = 0;

  @override
  Future<PreviewProcessResult> execute({
    required String workingDirectory,
    required String testPath,
    required Duration timeout,
    required Set<String> completionMarkers,
    PreviewCancellationToken? cancellationToken,
  }) async {
    calls += 1;
    cancellationTokenToTrigger?.cancel();
    final source = File(testPath).readAsStringSync();
    final paths = RegExp(r'DEVEX_OUTPUT ("[^"]+")')
        .allMatches(source)
        .map((match) => jsonDecode(match.group(1)!) as String)
        .where((path) => path.endsWith('.png'));
    final selectedPaths = paths.take(_remainingWrites).toList(growable: false);
    _remainingWrites -= selectedPaths.length;
    for (final path in selectedPaths) {
      File(path).writeAsBytesSync(
        invalid
            ? const <int>[1, 2, 3]
            : rgbaPng(
                width: 2,
                height: 2,
                pixels: const <int>[
                  255,
                  0,
                  0,
                  255,
                  0,
                  255,
                  0,
                  255,
                  0,
                  0,
                  255,
                  255,
                  255,
                  255,
                  255,
                  255,
                ],
              ),
      );
    }
    return PreviewProcessResult(
      exitCode: timedOut ? -9 : exitCode,
      timedOut: timedOut,
      stdoutTail: '',
      stderrTail: exitCode == 0 ? '' : 'synthetic widget failure',
    );
  }
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 10, 12);

  @override
  int monotonicMicroseconds() => 1;
}

final class _Ids implements IdGenerator {
  var value = 0;

  @override
  String nextId() => 'preview-${value++}';
}
