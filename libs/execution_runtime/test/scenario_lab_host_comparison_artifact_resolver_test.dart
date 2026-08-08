import 'dart:async';
import 'dart:io';

import 'package:execution_runtime/src/evidence/local_evidence_repository.dart';
import 'package:execution_runtime/src/evidence/png_capture_inspector.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/lab/scenario_lab_host_comparison_artifact_resolver.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:execution_runtime/src/lab/scenario_lab_supplemental_artifact_cas_resolver.dart';
import 'package:execution_runtime/src/storage/filesystem_workspace_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  test(
    'resolves exact current collection receipt and supplemental input',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.close);

      final current = await fixture.resolver.resolve(
        runId: fixture.runId,
        descriptor: fixture.currentDescriptor,
        cancellation: _Cancellation(),
      );
      expect(current?.bytes, fixture.currentBytes);

      final supplementalBytes = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[3, 4, 5, 255, 6, 7, 8, 255],
      );
      final artifactDigest = fixture.store.putBlob(supplementalBytes);
      final provenance = ScenarioLabSupplementalArtifactProvenance(
        artifactDigest: artifactDigest,
        size: supplementalBytes.length,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
        classification: ArtifactClassification.internal,
        sourceId: ScenarioLabSupplementalArtifactSourceId('golden-dashboard'),
        importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
          'workspace-import-v1',
        ),
      );
      fixture.store.putBlob(provenance.canonicalBytes);
      final supplemental = await fixture.resolver.resolve(
        runId: fixture.runId,
        descriptor: ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: artifactDigest,
          provenanceDigest: provenance.digest,
          classification: ArtifactClassification.internal,
        ),
        cancellation: _Cancellation(),
      );
      expect(supplemental?.bytes, supplementalBytes);
    },
  );

  test('never substitutes another current or supplemental artifact', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);

    expect(
      await fixture.resolver.resolve(
        runId: fixture.runId,
        descriptor: ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: fixture.currentDescriptor.artifactDigest,
          provenanceDigest: Digest.semantic('absent-provenance'),
          classification: ArtifactClassification.internal,
        ),
        cancellation: _Cancellation(),
      ),
      isNull,
    );
    await expectLater(
      fixture.resolver.resolve(
        runId: ScenarioLabRunId('another-run'),
        descriptor: fixture.currentDescriptor,
        cancellation: _Cancellation(),
      ),
      throwsA(isA<ScenarioLabComparisonInputInvalid>()),
    );
  });

  test(
    'fails closed for receipt, Evidence, and PNG provenance mismatch',
    () async {
      for (final fault in _Fault.values) {
        final fixture = _Fixture(fault: fault);
        addTearDown(fixture.close);
        await expectLater(
          fixture.resolver.resolve(
            runId: fixture.runId,
            descriptor: fixture.currentDescriptor,
            cancellation: _Cancellation(),
          ),
          throwsA(isA<ScenarioLabComparisonInputInvalid>()),
          reason: fault.name,
        );
      }
    },
  );

  test('rejects ambiguous run matches and observes cancellation', () async {
    final ambiguous = _Fixture(duplicateResult: true);
    addTearDown(ambiguous.close);
    await expectLater(
      ambiguous.resolver.resolve(
        runId: ambiguous.runId,
        descriptor: ambiguous.currentDescriptor,
        cancellation: _Cancellation(),
      ),
      throwsA(isA<ScenarioLabComparisonInputInvalid>()),
    );

    final cancelled = _Fixture();
    addTearDown(cancelled.close);
    await expectLater(
      cancelled.resolver.resolve(
        runId: cancelled.runId,
        descriptor: cancelled.currentDescriptor,
        cancellation: _Cancellation(cancelled: true),
      ),
      throwsA(isA<ScenarioLabComparisonCancelled>()),
    );
  });

  test('rejects a supplemental resolver owned by another store', () {
    final fixture = _Fixture();
    final otherRoot = Directory.systemTemp.createTempSync(
      'workspace-lab-host-compare-other-',
    );
    addTearDown(() {
      if (otherRoot.existsSync()) otherRoot.deleteSync(recursive: true);
      fixture.close();
    });

    for (final supplementalStore in <FileSystemWorkspaceStore>[
      FileSystemWorkspaceStore(workspaceRoot: otherRoot.path),
      FileSystemWorkspaceStore(
        workspaceRoot: fixture.root.path,
        distributionId: 'other-distribution',
      ),
    ]) {
      expect(
        () => ScenarioLabHostComparisonArtifactResolver(
          store: fixture.store,
          runStore: fixture.resolver.runStore,
          evidenceRepository: fixture.evidenceRepository,
          supplemental: ScenarioLabSupplementalArtifactCasResolver(
            store: supplementalStore,
          ),
        ),
        throwsArgumentError,
      );
    }
  });
}

enum _Fault { wrongSession, wrongFingerprint, wrongPixels }

final class _Fixture {
  _Fixture({_Fault? fault, bool duplicateResult = false})
    : root = Directory.systemTemp.createTempSync('workspace-lab-host-compare-'),
      runId = ScenarioLabRunId('run-host-comparison') {
    store = FileSystemWorkspaceStore(workspaceRoot: root.path);
    evidenceRepository = LocalEvidenceRepository(
      store: store,
      clock: const _Clock(),
      ids: _Ids(),
    );
    currentBytes = fault == _Fault.wrongPixels
        ? rgbaPng(
            width: 2,
            height: 1,
            pixels: const <int>[9, 9, 9, 255, 8, 8, 8, 255],
          )
        : rgbaPng(
            width: 2,
            height: 1,
            pixels: const <int>[1, 2, 3, 255, 4, 5, 6, 255],
          );
    final inspection = const PngCaptureInspector().inspect(currentBytes);
    final artifactDigest = store.putBlob(currentBytes);
    final receipt = AppAdapterCaptureReceipt(
      requestId: 'request-host-comparison',
      sessionId: fault == _Fault.wrongSession
          ? 'lab_wrong_session'
          : _expectedSessionId(runId),
      artifactDigest: artifactDigest,
      pixelDigest: fault == _Fault.wrongPixels
          ? Digest.semantic('wrong-pixels')
          : inspection.pixelDigest,
      size: currentBytes.length,
      width: 2,
      height: 1,
      completedAt: _observedAt,
    );
    expect(store.putBlob(receipt.canonicalBytes), receipt.digest);

    final catalogDigest = Digest.semantic('catalog-host-comparison');
    final goodFingerprint = _fingerprint(catalogDigest);
    final evidenceFingerprint = fault == _Fault.wrongFingerprint
        ? _fingerprint(Digest.semantic('other-catalog'))
        : goodFingerprint;
    final artifact = Artifact(
      digest: artifactDigest,
      size: currentBytes.length,
      mediaType: 'image/png',
      classification: ArtifactClassification.internal,
      role: 'scenario-lab.capture.app-adapter',
      pixelDigest: inspection.pixelDigest,
      width: receipt.width,
      height: receipt.height,
    );
    final evidence = evidenceRepository.persistEvidence(
      Evidence(
        id: 'evidence-host-comparison',
        subjectDigest: catalogDigest,
        fingerprint: evidenceFingerprint,
        observedAt: _observedAt,
        policyId: 'visual-policy-v1',
        artifacts: <Artifact>[artifact],
      ),
    );
    currentDescriptor = ScenarioLabComparisonArtifactDescriptor(
      artifactDigest: artifactDigest,
      provenanceDigest: receipt.digest,
      classification: ArtifactClassification.internal,
    );
    final result = RequiredEvidenceRunResult(
      requiredEvidenceId: RequiredEvidenceId('dashboard-visual'),
      providerId: ModuleId('capture.app-adapter'),
      fidelity: RuntimeFidelity.simulated,
      variantId: VariantId('desktop'),
      freshness: EvidenceFreshness.fresh,
      state: RequiredEvidenceResultState.collected,
      evidenceDigest: evidence.digest,
      artifacts: <ScenarioEvidenceArtifactResult>[
        ScenarioEvidenceArtifactResult(
          artifactDigest: artifactDigest,
          provenanceDigest: receipt.digest,
          classification: ArtifactClassification.internal,
        ),
      ],
    );
    final request = ScenarioLabRunStartRequest(
      requestId: ScenarioLabRunRequestId('request-host-comparison'),
      expectedContentSetDigest: Digest.semantic('content-host-comparison'),
      expectedScenarioLabManifestDigest: Digest.semantic(
        'manifest-host-comparison',
      ),
      scenarioId: ScenarioId('dashboard-ready'),
      scriptId: ScenarioScriptId('exercise-dashboard-ready'),
      requestedAt: _observedAt,
    );
    final snapshot = ScenarioLabRunSnapshot(
      runId: runId,
      startRequestDigest: request.digest,
      contentSetDigest: request.expectedContentSetDigest,
      catalogDigest: catalogDigest,
      scenarioLabManifestDigest: request.expectedScenarioLabManifestDigest,
      scenarioId: request.scenarioId,
      scriptId: request.scriptId,
      sequence: 1,
      observedAt: _observedAt,
      state: ScenarioLabRunState.starting,
      runtimeInputs: ScenarioLabRuntimeInputBinding(
        executionFingerprintDigest: goodFingerprint.digest,
        executionTargetId: goodFingerprint.targetId,
      ),
      steps: <ScenarioLabStepSnapshot>[
        ScenarioLabStepSnapshot(
          stepId: 'open-dashboard-ready',
          state: ScenarioLabStepState.running,
          startedAt: _observedAt,
        ),
      ],
      requiredEvidence: <RequiredEvidenceRunResult>[
        result,
        if (duplicateResult)
          RequiredEvidenceRunResult(
            requiredEvidenceId: RequiredEvidenceId('dashboard-visual-copy'),
            providerId: result.providerId,
            fidelity: result.fidelity,
            variantId: result.variantId,
            freshness: result.freshness,
            state: result.state,
            evidenceDigest: result.evidenceDigest,
            artifacts: result.artifacts,
          ),
      ],
      cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.pending),
    );
    final runStore = _FixedRunStore(
      ScenarioLabStoredRun(
        request: request,
        snapshots: <ScenarioLabRunSnapshot>[snapshot],
        result: null,
        interrupted: false,
      ),
    );
    resolver = ScenarioLabHostComparisonArtifactResolver(
      store: store,
      runStore: runStore,
      evidenceRepository: evidenceRepository,
    );
  }

  final Directory root;
  final ScenarioLabRunId runId;
  late final FileSystemWorkspaceStore store;
  late final LocalEvidenceRepository evidenceRepository;
  late final List<int> currentBytes;
  late final ScenarioLabComparisonArtifactDescriptor currentDescriptor;
  late final ScenarioLabHostComparisonArtifactResolver resolver;

  void close() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

final class _FixedRunStore implements ScenarioLabRunStore {
  const _FixedRunStore(this.run);

  final ScenarioLabStoredRun run;

  @override
  int get length => 1;

  @override
  List<ScenarioLabStoredRun> get runs => <ScenarioLabStoredRun>[run];

  @override
  ScenarioLabStoredRun? findByRequestId(ScenarioLabRunRequestId requestId) =>
      requestId == run.request.requestId ? run : null;

  @override
  ScenarioLabStoredRun? findByRunId(ScenarioLabRunId runId) =>
      runId == run.latest.runId ? run : null;

  @override
  ScenarioLabStoredRun requireRun(ScenarioLabRunId runId) {
    final found = findByRunId(runId);
    if (found == null) throw ScenarioLabRunNotFound(runId);
    return found;
  }

  @override
  void append(ScenarioLabRunSnapshot snapshot) =>
      throw UnsupportedError('read-only test store');

  @override
  void complete(ScenarioLabRunResult result) =>
      throw UnsupportedError('read-only test store');

  @override
  bool interrupt(ScenarioLabRunId runId) =>
      throw UnsupportedError('read-only test store');

  @override
  List<ScenarioLabRunSnapshot> observationsAfter(
    ScenarioLabRunId runId,
    int sequence,
  ) => <ScenarioLabRunSnapshot>[if (run.latest.sequence > sequence) run.latest];

  @override
  ScenarioLabRunRegistration register({
    required ScenarioLabRunStartRequest request,
    required ScenarioLabRunSnapshot initialSnapshot,
  }) => throw UnsupportedError('read-only test store');
}

final class _Cancellation implements ScenarioLabCancellationSignal {
  _Cancellation({this.cancelled = false});

  final bool cancelled;
  final Completer<void> _never = Completer<void>();

  @override
  bool get isCancelled => cancelled;

  @override
  Future<void> get whenCancelled =>
      cancelled ? Future<void>.value() : _never.future;
}

final class _Clock implements Clock {
  const _Clock();

  @override
  int monotonicMicroseconds() => 0;

  @override
  DateTime nowUtc() => _observedAt;
}

final class _Ids implements IdGenerator {
  var next = 0;

  @override
  String nextId() => 'id_${++next}_host_comparison';
}

ExecutionFingerprint _fingerprint(Digest catalogDigest) => ExecutionFingerprint(
  catalogDigest: catalogDigest,
  launchProfileId: 'sample-web',
  targetId: 'sample-target',
  platform: 'web',
  renderer: 'flutter-web',
  runtimeFidelity: RuntimeFidelity.simulated,
  backendMode: BackendMode.none,
  networkContainment: NetworkContainment.unconstrained,
  bootstrapAssessment: BootstrapAssessment.controlled,
  toolchain: const <String, String>{'dart': 'test'},
  capabilities: const <String>{'capture.app-adapter'},
);

String _expectedSessionId(ScenarioLabRunId runId) => runId.value;

final DateTime _observedAt = DateTime.utc(2026, 8, 14, 12);
