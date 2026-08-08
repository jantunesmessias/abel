import 'dart:async';

import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_service.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Scenario Lab App Adapter Evidence', () {
    test(
      'collects only Host Evidence, accepts it, and leaves comparison closed',
      () async {
        final fixture = _Fixture();
        final evidence = _FakeEvidencePort(fixture: fixture);
        final target = _FakeTarget(fingerprint: fixture.fingerprint);
        final store = InMemoryScenarioLabRunStore();
        final service = _service(
          fixture: fixture,
          evidence: evidence,
          target: target,
          store: store,
        );

        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        final result = await service.waitForResult(start.snapshot.runId);

        final collected = result.finalSnapshot.requiredEvidence.single;
        expect(collected.state, RequiredEvidenceResultState.collected);
        expect(collected.fidelity, RuntimeFidelity.hostNative);
        expect(collected.freshness, EvidenceFreshness.fresh);
        expect(
          collected.artifacts.single.provenanceDigest,
          Digest.semantic(evidence.lastReceipt!.toJson()),
        );
        expect(
          result.finalSnapshot.automatedAcceptance
              .singleWhere((item) => item.criterionId == _evidenceAcceptedId)
              .verificationState,
          VerificationState.passed,
        );
        expect(result.verificationState, VerificationState.passed);
        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.acceptanceFailed,
        );
        final comparison = result.finalSnapshot.comparisons.single;
        expect(comparison.verificationState, VerificationState.error);
        expect(comparison.failure?.cause, ScenarioLabFailureCause.unsupported);
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(evidence.issueCalls, 1);
        expect(evidence.consumeCalls, 1);
        expect(evidence.cleanupCalls, 1);
        expect(target.session!.closeCalls, 1);
        final command = target.session!.commands.single;
        expect(command, isA<CaptureAppAdapterRelayCommand>());
        expect(
          command.toJson().keys,
          isNot(
            contains(anyOf('evidenceDigest', 'classification', 'fidelity')),
          ),
        );
        final states = store
            .requireRun(start.snapshot.runId)
            .snapshots
            .expand((snapshot) => snapshot.requiredEvidence)
            .map((item) => item.state)
            .toSet();
        expect(
          states,
          containsAll(<RequiredEvidenceResultState>{
            RequiredEvidenceResultState.pending,
            RequiredEvidenceResultState.collected,
          }),
        );
      },
    );

    test(
      'missing Host upload is persisted as missing and fails the step',
      () async {
        final fixture = _Fixture();
        final evidence = _FakeEvidencePort(
          fixture: fixture,
          fault: _CollectionFault.missing,
        );
        final result = await _run(fixture, evidence: evidence);

        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.stepFailed,
        );
        expect(
          result.finalSnapshot.requiredEvidence.single.state,
          RequiredEvidenceResultState.missing,
        );
        expect(evidence.cleanupCalls, 1);
      },
    );

    for (final entry in <(_CollectionFault, String)>[
      (_CollectionFault.wrongRequest, 'wrong receipt request'),
      (_CollectionFault.wrongDigest, 'wrong artifact digest'),
      (_CollectionFault.wrongMediaType, 'wrong artifact media type'),
    ]) {
      test('${entry.$2} is rejected as invalid Host Evidence', () async {
        final fixture = _Fixture();
        final evidence = _FakeEvidencePort(fixture: fixture, fault: entry.$1);
        final result = await _run(fixture, evidence: evidence);
        final collection = result.finalSnapshot.requiredEvidence.single;

        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.stepFailed,
        );
        expect(collection.state, RequiredEvidenceResultState.failed);
        expect(collection.freshness, EvidenceFreshness.invalid);
        expect(
          collection.failure?.cause,
          ScenarioLabFailureCause.invalidResponse,
        );
        expect(evidence.cleanupCalls, 1);
      });
    }

    test('classification outside the requirement is policy denied', () async {
      final fixture = _Fixture();
      final evidence = _FakeEvidencePort(
        fixture: fixture,
        fault: _CollectionFault.wrongClassification,
      );
      final result = await _run(fixture, evidence: evidence);
      final collection = result.finalSnapshot.requiredEvidence.single;

      expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
      expect(collection.state, RequiredEvidenceResultState.policyDenied);
      expect(collection.artifacts, isEmpty);
      expect(collection.evidenceDigest, isNull);
      expect(evidence.cleanupCalls, 1);
    });

    test('observed fidelity must match the declared requirement', () async {
      final fixture = _Fixture();
      final simulated = ExecutionFingerprint(
        catalogDigest: fixture.catalog.digest,
        launchProfileId: 'app-web',
        targetId: 'chrome',
        platform: 'web',
        renderer: 'canvaskit',
        runtimeFidelity: RuntimeFidelity.simulated,
        backendMode: BackendMode.none,
        networkContainment: NetworkContainment.unconstrained,
        bootstrapAssessment: BootstrapAssessment.controlled,
        toolchain: const <String, String>{'flutter': '3.44.8'},
        capabilities: const <String>{'capture.app-adapter'},
        inputDigests: <String, Digest>{'catalog': fixture.catalog.digest},
        policies: const <String, String>{'capture': 'visual-v1'},
      );
      final evidence = _FakeEvidencePort(
        fixture: fixture,
        evidenceFingerprint: simulated,
      );
      final result = await _run(
        fixture,
        evidence: evidence,
        target: _FakeTarget(fingerprint: simulated),
      );

      expect(
        result.finalSnapshot.requiredEvidence.single.state,
        RequiredEvidenceResultState.failed,
      );
      expect(
        result.finalSnapshot.requiredEvidence.single.failure?.cause,
        ScenarioLabFailureCause.invalidResponse,
      );
    });

    test(
      'target acknowledgement cannot substitute another upload request',
      () async {
        final fixture = _Fixture();
        final evidence = _FakeEvidencePort(fixture: fixture);
        final target = _FakeTarget(
          fingerprint: fixture.fingerprint,
          wrongUploadAcknowledgement: true,
        );
        final result = await _run(fixture, evidence: evidence, target: target);

        expect(
          result.finalSnapshot.requiredEvidence.single.state,
          RequiredEvidenceResultState.failed,
        );
        expect(evidence.consumeCalls, 0);
        expect(evidence.cleanupCalls, 1);
      },
    );

    test(
      'collection deadline persists timed-out Evidence and cleans grant',
      () async {
        final fixture = _Fixture();
        final evidence = _FakeEvidencePort(fixture: fixture);
        final result = await _run(
          fixture,
          evidence: evidence,
          deadlines: _Deadlines(throwAfterActionOnCall: 4),
        );
        final collection = result.finalSnapshot.requiredEvidence.single;

        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.timedOut,
        );
        expect(collection.state, RequiredEvidenceResultState.failed);
        expect(collection.failure?.cause, ScenarioLabFailureCause.timedOut);
        expect(evidence.cleanupCalls, 1);
      },
    );

    test(
      'cancellation while awaiting receipt cancels collection and cleans',
      () async {
        final fixture = _Fixture();
        final evidence = _FakeEvidencePort(
          fixture: fixture,
          waitForCancellation: true,
        );
        final target = _FakeTarget(fingerprint: fixture.fingerprint);
        final service = _service(
          fixture: fixture,
          evidence: evidence,
          target: target,
        );
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await evidence.collectionStarted.future;

        service.cancel(start.snapshot.runId);
        final result = await service.waitForResult(start.snapshot.runId);

        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.requiredEvidence.single.state,
          RequiredEvidenceResultState.cancelled,
        );
        expect(evidence.cleanupCalls, 1);
        expect(target.session!.closeCalls, 1);
      },
    );

    test('Evidence cleanup failure overrides a completed collection', () async {
      final fixture = _Fixture();
      final evidence = _FakeEvidencePort(fixture: fixture, failCleanup: true);
      final result = await _run(fixture, evidence: evidence);

      expect(
        result.finalSnapshot.requiredEvidence.single.state,
        RequiredEvidenceResultState.collected,
      );
      expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
      expect(
        result.finalSnapshot.terminalCause,
        ScenarioLabTerminalCause.cleanupFailed,
      );
      expect(
        result.finalSnapshot.cleanup.state,
        ScenarioLabCleanupState.failed,
      );
      expect(evidence.cleanupCalls, 1);
    });
  });
}

Future<ScenarioLabRunResult> _run(
  _Fixture fixture, {
  required _FakeEvidencePort evidence,
  _FakeTarget? target,
  _Deadlines? deadlines,
}) {
  final service = _service(
    fixture: fixture,
    evidence: evidence,
    target: target ?? _FakeTarget(fingerprint: fixture.fingerprint),
    deadlines: deadlines,
  );
  final start = service.start(
    request: fixture.request,
    contentSet: fixture.contentSet,
    catalog: fixture.catalog,
    manifest: fixture.manifest,
  );
  return service.waitForResult(start.snapshot.runId);
}

ScenarioLabExecutionService _service({
  required _Fixture fixture,
  required _FakeEvidencePort evidence,
  required _FakeTarget target,
  InMemoryScenarioLabRunStore? store,
  _Deadlines? deadlines,
}) => ScenarioLabExecutionService(
  store: store ?? InMemoryScenarioLabRunStore(),
  clock: fixture.clock,
  identities: _Identities(),
  target: target,
  deadlines: deadlines ?? _Deadlines(),
  evidence: evidence,
);

final _scenarioId = ScenarioId('ready');
final _bindingId = ScenarioExecutionBindingId('ready-web');
final _scriptId = ScenarioScriptId('collect-ready');
final _evidenceId = RequiredEvidenceId('ready-visual');
final _evidenceAcceptedId = AutomatedAcceptanceCriterionId('evidence-accepted');
final _providerId = ModuleId('capture.app-adapter');

final class _Fixture {
  _Fixture() {
    final layout = ConsumerLayout.standard;
    final workspaceId = WorkspaceId('workspace');
    final applicationId = ApplicationId('app');
    catalog = CatalogManifest(
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
          displayName: 'App',
          root: '.',
          target: 'web',
        ),
      ],
      journeys: const <Journey>[],
      scenarios: <Scenario>[
        Scenario(id: _scenarioId, applicationId: applicationId, title: 'Ready'),
      ],
      transitions: const <Transition>[],
      executionBindings: <ScenarioExecutionBinding>[
        ScenarioExecutionBinding(
          id: _bindingId,
          scenarioId: _scenarioId,
          targetId: 'chrome',
          launchProfileId: 'app-web',
        ),
      ],
    );
    fingerprint = ExecutionFingerprint(
      catalogDigest: catalog.digest,
      launchProfileId: 'app-web',
      targetId: 'chrome',
      platform: 'web',
      renderer: 'canvaskit',
      runtimeFidelity: RuntimeFidelity.hostNative,
      backendMode: BackendMode.none,
      networkContainment: NetworkContainment.unconstrained,
      bootstrapAssessment: BootstrapAssessment.controlled,
      toolchain: const <String, String>{'flutter': '3.44.8'},
      capabilities: const <String>{'capture.app-adapter'},
      inputDigests: <String, Digest>{'catalog': catalog.digest},
      policies: const <String, String>{'capture': 'visual-v1'},
    );
    final operationId = ScenarioLabOperationId('collect-ready');
    final baselineId = SupplementalArtifactId('ready-baseline');
    final comparisonId = ScenarioComparisonBindingId('ready-comparison');
    manifest = ScenarioLabManifest(
      catalog: catalog,
      appAdapterCapabilities: const <CapabilityDescriptor>[],
      controls: const <ScenarioControlDefinition>[],
      operations: <ScenarioLabOperationDefinition>[
        CollectEvidenceOperationDefinition(
          id: operationId,
          scenarioId: _scenarioId,
          evidenceRequirementId: _evidenceId,
        ),
      ],
      scripts: <ScenarioScriptDefinition>[
        ScenarioScriptDefinition(
          id: _scriptId,
          scenarioId: _scenarioId,
          displayName: 'Collect ready Evidence',
          timeoutMs: 30000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
          steps: <ScenarioScriptStep>[
            ExecutionBindingScenarioScriptStep(
              id: 'attach',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
              bindingId: _bindingId,
            ),
            OperationScenarioScriptStep(
              id: 'collect',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
              operationId: operationId,
            ),
          ],
        ),
      ],
      automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
        ScriptSucceededAcceptanceCriterion(
          id: AutomatedAcceptanceCriterionId('script-succeeded'),
          scenarioId: _scenarioId,
          displayName: 'Script succeeded',
          scriptId: _scriptId,
        ),
        EvidenceAcceptedAcceptanceCriterion(
          id: _evidenceAcceptedId,
          scenarioId: _scenarioId,
          displayName: 'Evidence accepted',
          evidenceRequirementId: _evidenceId,
        ),
      ],
      requiredEvidence: <RequiredEvidenceDefinition>[
        RequiredEvidenceDefinition(
          id: _evidenceId,
          scenarioId: _scenarioId,
          providerId: _providerId,
          fidelity: RuntimeFidelity.hostNative,
          variantId: VariantId('desktop'),
          freshness: EvidenceFreshness.fresh,
          allowedClassifications: <ArtifactClassification>{
            ArtifactClassification.internal,
          },
          evidencePolicyId: EvidencePolicyId('visual-v1'),
          comparisonPolicy: VisualComparisonPolicyReference(
            VisualComparisonPolicyId('pixel-v1'),
          ),
        ),
      ],
      comparisonBindings: <ScenarioComparisonBinding>[
        ScenarioComparisonBinding(
          id: comparisonId,
          scenarioId: _scenarioId,
          requiredEvidenceId: _evidenceId,
          baseline: ArtifactComparisonInputReference(artifactId: baselineId),
          candidate: RequiredEvidenceComparisonInputReference(
            requiredEvidenceId: _evidenceId,
          ),
        ),
      ],
      visualComparisonPolicies: <VisualComparisonPolicy>[
        VisualComparisonPolicy(
          id: 'pixel-v1',
          maxChannelDelta: 0,
          maxChangedPixelRatio: 0,
        ),
      ],
      semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
      humanApprovalRequirements: const <HumanApprovalRequirement>[],
      supplementalArtifacts: <SupplementalArtifactReference>[
        SupplementalArtifactReference(
          id: baselineId,
          scenarioId: _scenarioId,
          requiredEvidenceId: _evidenceId,
          role: SupplementalArtifactRole.comparisonBaseline,
          artifactDigest: Digest.semantic('baseline-artifact'),
          provenanceDigest: Digest.semantic('baseline-provenance'),
          classification: ArtifactClassification.internal,
        ),
      ],
      plans: <ScenarioLabPlan>[
        ScenarioLabPlan(
          scenarioId: _scenarioId,
          executionBindingIds: <ScenarioExecutionBindingId>[_bindingId],
          controlIds: const <ScenarioControlId>[],
          operationIds: <ScenarioLabOperationId>[operationId],
          scriptIds: <ScenarioScriptId>[_scriptId],
          automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
            AutomatedAcceptanceCriterionId('script-succeeded'),
            _evidenceAcceptedId,
          ],
          requiredEvidenceIds: <RequiredEvidenceId>[_evidenceId],
          comparisonBindingIds: <ScenarioComparisonBindingId>[comparisonId],
          humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
          supplementalArtifactIds: <SupplementalArtifactId>[baselineId],
        ),
      ],
    );
    contentSet = ExperienceContentSetIdentity(
      revision: 1,
      catalogDigest: catalog.digest,
      workspaceSnapshotDigest: Digest.semantic('snapshot'),
      workspaceContentDigest: Digest.semantic('workspace-content'),
      scenarioLabManifestDigest: manifest.digest,
    );
    request = ScenarioLabRunStartRequest(
      requestId: ScenarioLabRunRequestId('request-evidence-1'),
      expectedContentSetDigest: contentSet.contentSetDigest,
      expectedScenarioLabManifestDigest: manifest.digest,
      scenarioId: _scenarioId,
      scriptId: _scriptId,
      requestedAt: _baseTime,
    );
  }

  final _Clock clock = _Clock();
  late final CatalogManifest catalog;
  late final ExecutionFingerprint fingerprint;
  late final ScenarioLabManifest manifest;
  late final ExperienceContentSetIdentity contentSet;
  late final ScenarioLabRunStartRequest request;
}

enum _CollectionFault {
  none,
  missing,
  wrongRequest,
  wrongDigest,
  wrongMediaType,
  wrongClassification,
}

final class _FakeEvidencePort implements ScenarioLabEvidencePort {
  _FakeEvidencePort({
    required this.fixture,
    this.fault = _CollectionFault.none,
    ExecutionFingerprint? evidenceFingerprint,
    this.waitForCancellation = false,
    this.failCleanup = false,
  }) : evidenceFingerprint = evidenceFingerprint ?? fixture.fingerprint;

  final _Fixture fixture;
  final _CollectionFault fault;
  final ExecutionFingerprint evidenceFingerprint;
  final bool waitForCancellation;
  final bool failCleanup;
  final Completer<void> collectionStarted = Completer<void>();
  var issueCalls = 0;
  var consumeCalls = 0;
  var cleanupCalls = 0;
  AppAdapterCaptureReceipt? lastReceipt;

  @override
  Future<AppAdapterRelayCaptureUploadGrant> issueCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required ScenarioLabRuntimeInputBinding runtimeInputs,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    issueCalls += 1;
    return AppAdapterRelayCaptureUploadGrant(
      requestId: 'upload_request_0001',
      sessionId: 'capture_session_0001',
      uploadUri: Uri.parse(
        'http://127.0.0.1:9191/capture-uploads/upload_request_0001?token=upload_token_0001',
      ),
      expiresAt: _baseTime.add(const Duration(minutes: 1)),
      maxBytes: 1024 * 1024,
    );
  }

  @override
  Future<ScenarioLabHostEvidenceCollection?> consumeCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required AppAdapterRelayCaptureUploadGrant uploadGrant,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    consumeCalls += 1;
    if (!collectionStarted.isCompleted) collectionStarted.complete();
    if (waitForCancellation) {
      await cancellation.whenCancelled;
      throw const ScenarioLabTargetCancelled();
    }
    if (fault == _CollectionFault.missing) return null;
    final receiptDigest = Digest.semantic('capture-artifact');
    final receipt = AppAdapterCaptureReceipt(
      requestId: fault == _CollectionFault.wrongRequest
          ? 'other_request_0001'
          : uploadGrant.requestId,
      sessionId: uploadGrant.sessionId,
      artifactDigest: receiptDigest,
      pixelDigest: Digest.semantic('pixels'),
      size: 64,
      width: 4,
      height: 4,
      completedAt: _baseTime,
    );
    lastReceipt = receipt;
    final wrongMedia = fault == _CollectionFault.wrongMediaType;
    final artifact = Artifact(
      digest: fault == _CollectionFault.wrongDigest
          ? Digest.semantic('other-artifact')
          : receiptDigest,
      size: receipt.size,
      mediaType: wrongMedia ? 'application/octet-stream' : 'image/png',
      classification: fault == _CollectionFault.wrongClassification
          ? ArtifactClassification.sensitive
          : ArtifactClassification.internal,
      role: 'capture.screen',
      pixelDigest: wrongMedia ? null : receipt.pixelDigest,
      width: wrongMedia ? null : receipt.width,
      height: wrongMedia ? null : receipt.height,
    );
    final evidence = Evidence(
      id: 'evidence-upload-request-0001',
      subjectDigest: fixture.catalog.digest,
      fingerprint: evidenceFingerprint,
      observedAt: receipt.completedAt,
      policyId: requirement.evidencePolicyId.value,
      artifacts: <Artifact>[artifact],
    );
    return ScenarioLabHostEvidenceCollection(
      uploadReceipt: receipt,
      evidence: evidence,
    );
  }

  @override
  Future<void> cleanupRun(ScenarioLabRunId runId) async {
    cleanupCalls += 1;
    if (failCleanup) throw StateError('capture cleanup failed');
  }
}

final class _FakeTarget implements ScenarioLabTargetPort {
  _FakeTarget({
    required this.fingerprint,
    this.wrongUploadAcknowledgement = false,
  });

  final ExecutionFingerprint fingerprint;
  final bool wrongUploadAcknowledgement;
  _FakeSession? session;

  @override
  ScenarioLabRuntimeInputBinding resolveRuntimeInputs({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
  }) => ScenarioLabRuntimeInputBinding(
    executionFingerprintDigest: fingerprint.digest,
    executionTargetId: binding.targetId,
  );

  @override
  Future<ScenarioLabTargetSession> attach({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
    required AppAdapterRelayNonce nonce,
    required ScenarioLabCancellationSignal cancellation,
  }) async => session = _FakeSession(
    runId: runId,
    nonce: nonce,
    wrongUploadAcknowledgement: wrongUploadAcknowledgement,
  );

  @override
  Future<void> abort(ScenarioLabRunId runId) async {}
}

final class _FakeSession implements ScenarioLabTargetSession {
  _FakeSession({
    required ScenarioLabRunId runId,
    required AppAdapterRelayNonce nonce,
    required this.wrongUploadAcknowledgement,
  }) : hello = AppAdapterRelayHello(
         runId: runId,
         adapterInstanceId: 'adapter-instance-1',
         sequence: 0,
         nonce: nonce,
         capabilities: const <AppAdapterCapabilityReference>[],
         evidenceProviderIds: <ModuleId>[_providerId],
       );

  @override
  final AppAdapterRelayHello hello;
  final bool wrongUploadAcknowledgement;
  final List<AppAdapterRelayCommand> commands = <AppAdapterRelayCommand>[];
  var closeCalls = 0;

  @override
  Future<AppAdapterRelayResult> execute(
    AppAdapterRelayCommand command, {
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    commands.add(command);
    if (command is! CaptureAppAdapterRelayCommand) {
      throw StateError('Evidence fixture accepts capture only');
    }
    return CaptureAppAdapterRelayResult(
      runId: command.runId,
      commandId: command.commandId,
      sequence: command.sequence,
      nonce: command.nonce,
      state: AppAdapterRelayResultState.succeeded,
      uploadRequestId: wrongUploadAcknowledgement
          ? 'other_upload_0001'
          : command.uploadGrant.requestId,
    );
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }
}

final class _Identities implements ScenarioLabExecutionIdentityPort {
  var command = 0;

  @override
  ScenarioLabRunId nextRunId() => ScenarioLabRunId('run-evidence-1');

  @override
  ScenarioLabCommandId nextCommandId() =>
      ScenarioLabCommandId('command-${++command}');

  @override
  AppAdapterRelayNonce nextRelayNonce() =>
      AppAdapterRelayNonce('relay_nonce_0000000001');
}

final class _Deadlines implements ScenarioLabDeadlinePort {
  _Deadlines({this.throwAfterActionOnCall});

  final int? throwAfterActionOnCall;
  var calls = 0;

  @override
  Future<T> run<T>({
    required Duration timeout,
    required Future<T> Function() action,
  }) async {
    final call = ++calls;
    final result = await action();
    if (call == throwAfterActionOnCall) {
      throw const ScenarioLabDeadlineExceeded();
    }
    return result;
  }
}

final DateTime _baseTime = DateTime.utc(2026, 8, 14, 12);

final class _Clock implements Clock {
  var ticks = 0;
  var micros = 0;

  @override
  DateTime nowUtc() => _baseTime.add(Duration(milliseconds: ticks++));

  @override
  int monotonicMicroseconds() {
    micros += 1000;
    return micros;
  }
}
