import 'dart:async';
import 'dart:io';

import 'package:execution_runtime/src/host/app_adapter_capture_bridge.dart';
import 'package:execution_runtime/src/host/host_workspace_service.dart';
import 'package:execution_runtime/src/lab/host_scenario_lab_runtime.dart';
import 'package:execution_runtime/src/lab/managed_process_scenario_lab_target.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/storage/filesystem_workspace_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test('capture bridge and classification must be configured together', () {
    final fixture = _Fixture();
    addTearDown(fixture.close);

    expect(
      () => fixture.createRuntime(captureBridge: fixture.bridge),
      throwsArgumentError,
    );
    expect(
      () => fixture.createRuntime(
        evidenceClassification: ArtifactClassification.internal,
      ),
      throwsArgumentError,
    );
    expect(fixture.bridge.pendingCount, 0);
  });

  test('Evidence adapter is optional and uses the workspace CAS', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);

    final withoutEvidence = fixture.createRuntime();
    fixture.runtimes.add(withoutEvidence);
    expect(withoutEvidence.evidence, isNull);
    expect(withoutEvidence.comparison, isNull);

    final withEvidence = fixture.createRuntime(
      captureBridge: fixture.bridge,
      evidenceClassification: ArtifactClassification.internal,
    );
    fixture.runtimes.add(withEvidence);
    expect(withEvidence.evidence, isNotNull);
    expect(withEvidence.comparison, isNotNull);
    expect(withEvidence.evidence!.captureBridge, same(fixture.bridge));
    expect(
      withEvidence.evidence!.evidenceRepository.store,
      same(fixture.store),
    );

    await expectLater(
      withEvidence.evidence!.issueCaptureUpload(
        runId: _runId,
        requirement: _requirement,
        runtimeInputs: _runtimeInputs,
        cancellation: _NeverCancelled(),
      ),
      throwsA(isA<ScenarioLabEvidenceInvalidInput>()),
    );
    expect(fixture.bridge.pendingCount, 0);
  });

  test('Evidence adapter rejects a bridge from another workspace', () async {
    final fixture = _Fixture();
    final otherRoot = Directory.systemTemp.createTempSync(
      'workspace-lab-evidence-other-',
    );
    final otherBridge = AppAdapterCaptureBridge(
      store: FileSystemWorkspaceStore(workspaceRoot: otherRoot.path),
      clock: fixture.clock,
      ids: _Ids('other'),
    );
    addTearDown(() async {
      await otherBridge.close();
      if (otherRoot.existsSync()) otherRoot.deleteSync(recursive: true);
      await fixture.close();
    });

    expect(
      () => fixture.createRuntime(
        captureBridge: otherBridge,
        evidenceClassification: ArtifactClassification.internal,
      ),
      throwsArgumentError,
    );
  });

  test(
    'Evidence adapter rejects a bridge from another distribution state',
    () async {
      final fixture = _Fixture();
      final otherBridge = AppAdapterCaptureBridge(
        store: FileSystemWorkspaceStore(
          workspaceRoot: fixture.root.path,
          distributionId: 'other-distribution',
        ),
        clock: fixture.clock,
        ids: _Ids('other-distribution'),
      );
      addTearDown(() async {
        await otherBridge.close();
        await fixture.close();
      });

      expect(
        () => fixture.createRuntime(
          captureBridge: otherBridge,
          evidenceClassification: ArtifactClassification.internal,
        ),
        throwsArgumentError,
      );
    },
  );

  test('owned launch context resolves exact origin and fingerprint only', () {
    final owned = ScenarioLabManagedLaunchContext(
      targetOrigin: _targetOrigin,
      executionFingerprint: _fingerprint,
      gateway: null,
    );

    final resolved = resolveHostScenarioLabEvidenceContext(
      launchContext: owned,
      runtimeInputs: _runtimeInputs,
      classification: ArtifactClassification.internal,
    );
    expect(resolved.targetOrigin, _targetOrigin);
    expect(resolved.executionFingerprint, same(_fingerprint));
    expect(resolved.classification, ArtifactClassification.internal);

    expect(
      () => resolveHostScenarioLabEvidenceContext(
        launchContext: null,
        runtimeInputs: _runtimeInputs,
        classification: ArtifactClassification.internal,
      ),
      throwsA(isA<ScenarioLabEvidenceInvalidInput>()),
    );
    expect(
      () => resolveHostScenarioLabEvidenceContext(
        launchContext: owned,
        runtimeInputs: ScenarioLabRuntimeInputBinding(
          executionFingerprintDigest: Digest.semantic('other-fingerprint'),
          executionTargetId: _fingerprint.targetId,
        ),
        classification: ArtifactClassification.internal,
      ),
      throwsA(isA<ScenarioLabEvidenceInvalidInput>()),
    );
    expect(
      () => resolveHostScenarioLabEvidenceContext(
        launchContext: owned,
        runtimeInputs: ScenarioLabRuntimeInputBinding(
          executionFingerprintDigest: _fingerprint.digest,
          executionTargetId: 'another-target',
        ),
        classification: ArtifactClassification.internal,
      ),
      throwsA(isA<ScenarioLabEvidenceInvalidInput>()),
    );
  });
}

final class _Fixture {
  _Fixture()
    : root = Directory.systemTemp.createTempSync(
        'workspace-lab-runtime-evidence-',
      ),
      clock = const _Clock(),
      ids = _Ids('fixture') {
    store = FileSystemWorkspaceStore(workspaceRoot: root.path);
    workspace = HostWorkspaceService(initialCatalog: _catalog(), clock: clock);
    bridge = AppAdapterCaptureBridge(store: store, clock: clock, ids: ids);
  }

  final Directory root;
  final _Clock clock;
  final _Ids ids;
  late final FileSystemWorkspaceStore store;
  late final HostWorkspaceService workspace;
  late final AppAdapterCaptureBridge bridge;
  final List<HostScenarioLabRuntime> runtimes = <HostScenarioLabRuntime>[];

  HostScenarioLabRuntime createRuntime({
    AppAdapterCaptureBridge? captureBridge,
    ArtifactClassification? evidenceClassification,
  }) => HostScenarioLabRuntime(
    workspaceRoot: root.path,
    workspaceStore: store,
    workspace: workspace,
    launchProfiles: const <String, LaunchProfile>{},
    clock: clock,
    ids: ids,
    captureBridge: captureBridge,
    evidenceClassification: evidenceClassification,
  );

  Future<void> close() async {
    for (final runtime in runtimes.reversed) {
      await runtime.close();
    }
    await bridge.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('sample');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Sample',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: const <Scenario>[],
    transitions: const <Transition>[],
  );
}

final _runId = ScenarioLabRunId('run-evidence-runtime');
final _targetOrigin = Uri.parse('http://127.0.0.1:8181');
final _catalogDigest = Digest.semantic('catalog');
final _fingerprint = ExecutionFingerprint(
  catalogDigest: _catalogDigest,
  launchProfileId: 'sample-web',
  targetId: 'sample-target',
  platform: 'web',
  renderer: 'flutter-web',
  runtimeFidelity: RuntimeFidelity.hostNative,
  backendMode: BackendMode.none,
  networkContainment: NetworkContainment.unconstrained,
  bootstrapAssessment: BootstrapAssessment.controlled,
  toolchain: const <String, String>{'dart': 'test'},
  capabilities: const <String>{'capture.app-adapter'},
);
final _runtimeInputs = ScenarioLabRuntimeInputBinding(
  executionFingerprintDigest: _fingerprint.digest,
  executionTargetId: _fingerprint.targetId,
);
final _requirement = RequiredEvidenceDefinition(
  id: RequiredEvidenceId('ready-visual'),
  scenarioId: ScenarioId('ready'),
  providerId: ModuleId('capture.app-adapter'),
  fidelity: RuntimeFidelity.hostNative,
  variantId: VariantId('desktop'),
  freshness: EvidenceFreshness.fresh,
  allowedClassifications: const <ArtifactClassification>{
    ArtifactClassification.internal,
  },
  evidencePolicyId: EvidencePolicyId('visual-v1'),
  comparisonPolicy: VisualComparisonPolicyReference(
    VisualComparisonPolicyId('pixel-v1'),
  ),
);

final class _Clock implements Clock {
  const _Clock();

  @override
  int monotonicMicroseconds() => 0;

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 14, 12);
}

final class _Ids implements IdGenerator {
  _Ids(this.prefix);

  final String prefix;
  var next = 0;

  @override
  String nextId() => '${prefix}_${(++next).toString().padLeft(16, '0')}';
}

final class _NeverCancelled implements ScenarioLabCancellationSignal {
  final Completer<void> _never = Completer<void>();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => _never.future;
}
