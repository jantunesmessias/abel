import 'dart:async';
import 'dart:convert';

import 'package:execution_runtime/src/lab/scenario_lab_evidence_comparison_port.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_service.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  group('Scenario Lab comparison execution', () {
    test('comparison adapter returns sealed semantic metrics', () async {
      final baseline = _semantics(Digest.semantic('one'));
      final candidate = _semantics(Digest.semantic('two'));
      final baselineDescriptor = ScenarioLabComparisonArtifactDescriptor(
        artifactDigest: Digest.bytes(baseline),
        provenanceDigest: Digest.semantic('semantic-baseline-provenance'),
        classification: ArtifactClassification.internal,
      );
      final candidateDescriptor = ScenarioLabComparisonArtifactDescriptor(
        artifactDigest: Digest.bytes(candidate),
        provenanceDigest: Digest.semantic('semantic-candidate-provenance'),
        classification: ArtifactClassification.internal,
      );
      final bytes = <Digest, List<int>>{
        baselineDescriptor.artifactDigest: baseline,
        candidateDescriptor.artifactDigest: candidate,
      };
      final port = ScenarioLabEvidenceComparisonPort(
        resolveArtifact:
            ({
              required runId,
              required descriptor,
              required cancellation,
            }) async => ScenarioLabResolvedComparisonArtifact(
              descriptor: descriptor,
              bytes: bytes[descriptor.artifactDigest]!,
            ),
      );

      final metrics = await port.compareSemantic(
        runId: ScenarioLabRunId('run-semantic-1'),
        baseline: baselineDescriptor,
        candidate: candidateDescriptor,
        policy: SemanticComparisonPolicy(
          id: 'semantics-v1',
          maxChangedNodes: 0,
          ignoreBounds: true,
        ),
        cancellation: _NeverCancellation(),
      );

      expect(metrics.passed, isFalse);
      expect(metrics.comparedNodes, 1);
      expect(metrics.changedNodes, 1);
    });

    test(
      'identical pixels pass from exact Host-owned input identities',
      () async {
        final baseline = _png(const <int>[
          10,
          20,
          30,
          255,
          40,
          50,
          60,
          255,
        ], compressionLevel: 1);
        final candidate = _png(
          const <int>[10, 20, 30, 255, 40, 50, 60, 255],
          compressionLevel: 9,
          filter: 1,
        );
        final fixture = _Fixture(baseline: baseline, candidate: candidate);
        final resolver = _Resolver(fixture);
        final evidence = _EvidencePort(fixture);
        final store = InMemoryScenarioLabRunStore();
        final result = await _run(
          fixture,
          evidence: evidence,
          resolver: resolver,
          store: store,
        );

        final comparison =
            result.finalSnapshot.comparisons.single
                as VisualScenarioComparisonResult;
        expect(comparison.verificationState, VerificationState.passed);
        expect(comparison.comparedPixels, 2);
        expect(comparison.changedPixels, 0);
        expect(comparison.maxChannelDeltaObserved, 0);
        expect(comparison.baselineDigest, Digest.bytes(baseline));
        expect(comparison.candidateDigest, Digest.bytes(candidate));
        expect(result.finalSnapshot.state, ScenarioLabRunState.succeeded);
        expect(
          result.finalSnapshot.toJson().containsKey('humanDecision'),
          isFalse,
        );
        expect(evidence.cleanupCalls, 1);
        expect(resolver.requests, hasLength(2));
        expect(
          resolver.requests.first.provenanceDigest,
          fixture.baselineProvenanceDigest,
        );
        expect(
          resolver.requests.last.provenanceDigest,
          Digest.semantic(evidence.receipt!.toJson()),
        );
        final comparisonObservation = store
            .requireRun(result.finalSnapshot.runId)
            .snapshots
            .firstWhere((snapshot) => snapshot.comparisons.isNotEmpty);
        expect(
          comparisonObservation.automatedAcceptance.every(
            (item) => item.verificationState == VerificationState.notRun,
          ),
          isTrue,
          reason: 'comparison is persisted before final acceptance evaluation',
        );
      },
    );

    test('changed pixels can pass a bounded visual policy', () async {
      final baseline = _png(const <int>[10, 20, 30, 255, 40, 50, 60, 255]);
      final candidate = _png(const <int>[10, 20, 30, 255, 90, 50, 60, 255]);
      final fixture = _Fixture(
        baseline: baseline,
        candidate: candidate,
        maxChangedPixelRatio: 0.5,
      );
      final result = await _run(
        fixture,
        evidence: _EvidencePort(fixture),
        resolver: _Resolver(fixture),
      );
      final comparison =
          result.finalSnapshot.comparisons.single
              as VisualScenarioComparisonResult;

      expect(comparison.verificationState, VerificationState.passed);
      expect(comparison.changedPixels, 1);
      expect(comparison.maxChannelDeltaObserved, 50);
      expect(result.finalSnapshot.state, ScenarioLabRunState.succeeded);
    });

    test(
      'visual difference fails verification without becoming an error',
      () async {
        final baseline = _png(const <int>[10, 20, 30, 255, 40, 50, 60, 255]);
        final candidate = _png(const <int>[10, 20, 30, 255, 90, 50, 60, 255]);
        final fixture = _Fixture(baseline: baseline, candidate: candidate);
        final result = await _run(
          fixture,
          evidence: _EvidencePort(fixture),
          resolver: _Resolver(fixture),
        );
        final comparison =
            result.finalSnapshot.comparisons.single
                as VisualScenarioComparisonResult;

        expect(comparison.verificationState, VerificationState.failed);
        expect(comparison.failure, isNull);
        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.acceptanceFailed,
        );
        expect(
          result.finalSnapshot.automatedAcceptance.single.verificationState,
          VerificationState.passed,
          reason:
              'Evidence acceptance and comparison verification stay separate',
        );
      },
    );

    test('malformed visual baseline is an explicit input error', () async {
      final fixture = _Fixture(
        baseline: const <int>[1, 2, 3, 4],
        candidate: _png(const <int>[10, 20, 30, 255, 40, 50, 60, 255]),
      );
      final result = await _run(
        fixture,
        evidence: _EvidencePort(fixture),
        resolver: _Resolver(fixture),
      );
      final comparison = result.finalSnapshot.comparisons.single;

      expect(comparison.verificationState, VerificationState.error);
      expect(
        comparison.failure?.cause,
        ScenarioLabFailureCause.invalidResponse,
      );
    });

    test('missing exact bytes are notRun and remain fail-closed', () async {
      final fixture = _Fixture.simple();
      final evidence = _EvidencePort(fixture);
      final result = await _run(
        fixture,
        evidence: evidence,
        resolver: _Resolver(fixture, fault: _ResolverFault.missingBaseline),
      );
      final comparison = result.finalSnapshot.comparisons.single;

      expect(comparison.verificationState, VerificationState.notRun);
      expect(comparison.failure, isNull);
      expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
      expect(
        result.finalSnapshot.requiredEvidence.single.state,
        RequiredEvidenceResultState.collected,
      );
      expect(evidence.cleanupCalls, 1);
    });

    for (final fault in const <_ResolverFault>[
      _ResolverFault.tamperedArtifact,
      _ResolverFault.tamperedProvenance,
      _ResolverFault.tamperedClassification,
    ]) {
      test(
        '${fault.name} resolver identity is an invalid-response error',
        () async {
          final fixture = _Fixture.simple();
          final result = await _run(
            fixture,
            evidence: _EvidencePort(fixture),
            resolver: _Resolver(fixture, fault: fault),
          );
          final comparison = result.finalSnapshot.comparisons.single;

          expect(comparison.verificationState, VerificationState.error);
          expect(
            comparison.failure?.cause,
            ScenarioLabFailureCause.invalidResponse,
          );
        },
      );
    }

    test(
      'Host policy denial is distinct from missing and invalid input',
      () async {
        final fixture = _Fixture.simple();
        final result = await _run(
          fixture,
          evidence: _EvidencePort(fixture),
          resolver: _Resolver(fixture, fault: _ResolverFault.policyDenied),
        );
        final comparison = result.finalSnapshot.comparisons.single;

        expect(comparison.verificationState, VerificationState.error);
        expect(comparison.failure?.cause, ScenarioLabFailureCause.policyDenied);
      },
    );

    test(
      'direct Evidence input is ambiguous and never reaches resolver',
      () async {
        final fixture = _Fixture.simple(
          candidateInput: EvidenceComparisonInputReference(
            evidenceDigest: Digest.semantic('pinned-evidence'),
            provenanceDigest: Digest.semantic('pinned-provenance'),
            classification: ArtifactClassification.internal,
          ),
        );
        final resolver = _Resolver(fixture);
        final result = await _run(
          fixture,
          evidence: _EvidencePort(fixture),
          resolver: resolver,
        );
        final comparison = result.finalSnapshot.comparisons.single;

        expect(comparison.verificationState, VerificationState.error);
        expect(comparison.failure?.cause, ScenarioLabFailureCause.unsupported);
        expect(comparison.candidateDigest, Digest.semantic('pinned-evidence'));
        expect(resolver.requests, isEmpty);
      },
    );

    test(
      'semantic policy rejects PNG inputs as invalid, never visual metrics',
      () async {
        final fixture = _Fixture.simple(semantic: true);
        final result = await _run(
          fixture,
          evidence: _EvidencePort(fixture),
          resolver: _Resolver(fixture),
        );
        final comparison = result.finalSnapshot.comparisons.single;

        expect(comparison, isA<SemanticScenarioComparisonResult>());
        expect(comparison.verificationState, VerificationState.error);
        expect(
          comparison.failure?.cause,
          ScenarioLabFailureCause.invalidResponse,
        );
      },
    );

    test(
      'cancellation during comparison preserves Evidence and cleans capture',
      () async {
        final fixture = _Fixture.simple();
        final evidence = _EvidencePort(fixture);
        final resolver = _Resolver(
          fixture,
          fault: _ResolverFault.waitForCancellation,
        );
        final target = _Target(fixture.fingerprint);
        final service = _service(
          fixture,
          evidence: evidence,
          resolver: resolver,
          target: target,
        );
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await resolver.started.future;

        service.cancel(start.snapshot.runId);
        final result = await service.waitForResult(start.snapshot.runId);

        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.requiredEvidence.single.state,
          RequiredEvidenceResultState.collected,
        );
        expect(result.finalSnapshot.comparisons, isEmpty);
        expect(evidence.cleanupCalls, 1);
        expect(target.session!.closeCalls, 1);
      },
    );

    test('comparison deadline still cleans the issued capture grant', () async {
      final fixture = _Fixture.simple();
      final evidence = _EvidencePort(fixture);
      final result = await _run(
        fixture,
        evidence: evidence,
        resolver: _Resolver(fixture),
        deadlines: _Deadlines(throwAfterActionOnCall: 5),
      );

      expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
      expect(
        result.finalSnapshot.terminalCause,
        ScenarioLabTerminalCause.timedOut,
      );
      expect(
        result.finalSnapshot.requiredEvidence.single.state,
        RequiredEvidenceResultState.collected,
      );
      expect(evidence.cleanupCalls, 1);
      expect(
        result.finalSnapshot.cleanup.state,
        ScenarioLabCleanupState.succeeded,
      );
    });
  });
}

List<int> _png(List<int> pixels, {int compressionLevel = 6, int filter = 0}) =>
    rgbaPng(
      width: 2,
      height: 1,
      pixels: pixels,
      compressionLevel: compressionLevel,
      filter: filter,
    );

List<int> _semantics(Digest textDigest) => utf8.encode(
  '${const JcsCanonicalizer().canonicalize(<String, Object?>{
    'schemaVersion': 1,
    'kind': 'AndroidSemanticsSnapshot',
    'privacy': 'hashedTextV1',
    'nodes': <Object?>[
      <String, Object?>{'sequence': 0, 'textDigest': textDigest.value, 'bounds': '[0,0][1,1]'},
    ],
  })}\n',
);

Future<ScenarioLabRunResult> _run(
  _Fixture fixture, {
  required _EvidencePort evidence,
  required _Resolver resolver,
  InMemoryScenarioLabRunStore? store,
  _Deadlines? deadlines,
}) {
  final service = _service(
    fixture,
    evidence: evidence,
    resolver: resolver,
    store: store,
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

ScenarioLabExecutionService _service(
  _Fixture fixture, {
  required _EvidencePort evidence,
  required _Resolver resolver,
  _Target? target,
  InMemoryScenarioLabRunStore? store,
  _Deadlines? deadlines,
}) => ScenarioLabExecutionService(
  store: store ?? InMemoryScenarioLabRunStore(),
  clock: fixture.clock,
  identities: _Identities(),
  target: target ?? _Target(fixture.fingerprint),
  deadlines: deadlines ?? _Deadlines(),
  evidence: evidence,
  comparison: ScenarioLabEvidenceComparisonPort(
    resolveArtifact: resolver.resolve,
  ),
);

final _scenarioId = ScenarioId('ready');
final _bindingId = ScenarioExecutionBindingId('ready-web');
final _scriptId = ScenarioScriptId('compare-ready');
final _evidenceId = RequiredEvidenceId('ready-visual');
final _baselineId = SupplementalArtifactId('ready-baseline');
final _comparisonId = ScenarioComparisonBindingId('ready-comparison');
final _providerId = ModuleId('capture.app-adapter');
final _baseTime = DateTime.utc(2026, 8, 14, 12);

final class _Fixture {
  _Fixture({
    required this.baseline,
    required this.candidate,
    this.maxChangedPixelRatio = 0,
    this.semantic = false,
    ComparisonInputReference? candidateInput,
  }) : baselineProvenanceDigest = Digest.semantic('baseline-provenance') {
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
    final comparisonPolicy = semantic
        ? SemanticComparisonPolicyReference(
            SemanticComparisonPolicyId('semantics-v1'),
          )
        : VisualComparisonPolicyReference(VisualComparisonPolicyId('pixel-v1'));
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
          displayName: 'Collect and compare ready Evidence',
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
        EvidenceAcceptedAcceptanceCriterion(
          id: AutomatedAcceptanceCriterionId('evidence-accepted'),
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
          comparisonPolicy: comparisonPolicy,
        ),
      ],
      comparisonBindings: <ScenarioComparisonBinding>[
        ScenarioComparisonBinding(
          id: _comparisonId,
          scenarioId: _scenarioId,
          requiredEvidenceId: _evidenceId,
          baseline: ArtifactComparisonInputReference(artifactId: _baselineId),
          candidate:
              candidateInput ??
              RequiredEvidenceComparisonInputReference(
                requiredEvidenceId: _evidenceId,
              ),
        ),
      ],
      visualComparisonPolicies: semantic
          ? const <VisualComparisonPolicy>[]
          : <VisualComparisonPolicy>[
              VisualComparisonPolicy(
                id: 'pixel-v1',
                maxChannelDelta: 0,
                maxChangedPixelRatio: maxChangedPixelRatio,
              ),
            ],
      semanticComparisonPolicies: semantic
          ? <SemanticComparisonPolicy>[
              SemanticComparisonPolicy(
                id: 'semantics-v1',
                maxChangedNodes: 0,
                ignoreBounds: true,
              ),
            ]
          : const <SemanticComparisonPolicy>[],
      humanApprovalRequirements: const <HumanApprovalRequirement>[],
      supplementalArtifacts: <SupplementalArtifactReference>[
        SupplementalArtifactReference(
          id: _baselineId,
          scenarioId: _scenarioId,
          requiredEvidenceId: _evidenceId,
          role: SupplementalArtifactRole.comparisonBaseline,
          artifactDigest: Digest.bytes(baseline),
          provenanceDigest: baselineProvenanceDigest,
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
            AutomatedAcceptanceCriterionId('evidence-accepted'),
          ],
          requiredEvidenceIds: <RequiredEvidenceId>[_evidenceId],
          comparisonBindingIds: <ScenarioComparisonBindingId>[_comparisonId],
          humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
          supplementalArtifactIds: <SupplementalArtifactId>[_baselineId],
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
      requestId: ScenarioLabRunRequestId('request-comparison-1'),
      expectedContentSetDigest: contentSet.contentSetDigest,
      expectedScenarioLabManifestDigest: manifest.digest,
      scenarioId: _scenarioId,
      scriptId: _scriptId,
      requestedAt: _baseTime,
    );
  }

  factory _Fixture.simple({
    bool semantic = false,
    ComparisonInputReference? candidateInput,
  }) => _Fixture(
    baseline: _png(const <int>[10, 20, 30, 255, 40, 50, 60, 255]),
    candidate: _png(const <int>[10, 20, 30, 255, 40, 50, 60, 255]),
    semantic: semantic,
    candidateInput: candidateInput,
  );

  final List<int> baseline;
  final List<int> candidate;
  final double maxChangedPixelRatio;
  final bool semantic;
  final Digest baselineProvenanceDigest;
  final _Clock clock = _Clock();
  late final CatalogManifest catalog;
  late final ExecutionFingerprint fingerprint;
  late final ScenarioLabManifest manifest;
  late final ExperienceContentSetIdentity contentSet;
  late final ScenarioLabRunStartRequest request;
}

enum _ResolverFault {
  none,
  missingBaseline,
  tamperedArtifact,
  tamperedProvenance,
  tamperedClassification,
  policyDenied,
  waitForCancellation,
}

final class _Resolver {
  _Resolver(this.fixture, {this.fault = _ResolverFault.none});

  final _Fixture fixture;
  final _ResolverFault fault;
  final List<ScenarioLabComparisonArtifactDescriptor> requests =
      <ScenarioLabComparisonArtifactDescriptor>[];
  final Completer<void> started = Completer<void>();

  Future<ScenarioLabResolvedComparisonArtifact?> resolve({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor descriptor,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    requests.add(descriptor);
    if (!started.isCompleted) started.complete();
    if (fault == _ResolverFault.waitForCancellation) {
      await cancellation.whenCancelled;
      throw const ScenarioLabComparisonCancelled();
    }
    if (fault == _ResolverFault.policyDenied) {
      throw const ScenarioLabComparisonPolicyDenied();
    }
    final baselineDigest = Digest.bytes(fixture.baseline);
    if (fault == _ResolverFault.missingBaseline &&
        descriptor.artifactDigest == baselineDigest) {
      return null;
    }
    final bytes = descriptor.artifactDigest == baselineDigest
        ? fixture.baseline
        : descriptor.artifactDigest == Digest.bytes(fixture.candidate)
        ? fixture.candidate
        : null;
    if (bytes == null) return null;
    if (fault == _ResolverFault.tamperedArtifact) {
      final tampered = _png(const <int>[1, 2, 3, 255, 4, 5, 6, 255]);
      return ScenarioLabResolvedComparisonArtifact(
        descriptor: ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: Digest.bytes(tampered),
          provenanceDigest: descriptor.provenanceDigest,
          classification: descriptor.classification,
        ),
        bytes: tampered,
      );
    }
    if (fault == _ResolverFault.tamperedProvenance) {
      return ScenarioLabResolvedComparisonArtifact(
        descriptor: ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: descriptor.artifactDigest,
          provenanceDigest: Digest.semantic('other-provenance'),
          classification: descriptor.classification,
        ),
        bytes: bytes,
      );
    }
    if (fault == _ResolverFault.tamperedClassification) {
      return ScenarioLabResolvedComparisonArtifact(
        descriptor: ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: descriptor.artifactDigest,
          provenanceDigest: descriptor.provenanceDigest,
          classification: ArtifactClassification.public,
        ),
        bytes: bytes,
      );
    }
    return ScenarioLabResolvedComparisonArtifact(
      descriptor: descriptor,
      bytes: bytes,
    );
  }
}

final class _EvidencePort implements ScenarioLabEvidencePort {
  _EvidencePort(this.fixture);

  final _Fixture fixture;
  AppAdapterCaptureReceipt? receipt;
  var cleanupCalls = 0;

  @override
  Future<AppAdapterRelayCaptureUploadGrant> issueCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required ScenarioLabRuntimeInputBinding runtimeInputs,
    required ScenarioLabCancellationSignal cancellation,
  }) async => AppAdapterRelayCaptureUploadGrant(
    requestId: 'comparison_upload_0001',
    sessionId: 'comparison_session_0001',
    uploadUri: Uri.parse(
      'http://127.0.0.1:9191/capture-uploads/comparison_upload_0001?token=comparison_token_0001',
    ),
    expiresAt: _baseTime.add(const Duration(minutes: 1)),
    maxBytes: 1024 * 1024,
  );

  @override
  Future<ScenarioLabHostEvidenceCollection?> consumeCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required AppAdapterRelayCaptureUploadGrant uploadGrant,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    final value = AppAdapterCaptureReceipt(
      requestId: uploadGrant.requestId,
      sessionId: uploadGrant.sessionId,
      artifactDigest: Digest.bytes(fixture.candidate),
      pixelDigest: Digest.semantic('candidate-pixels'),
      size: fixture.candidate.length,
      width: 2,
      height: 1,
      completedAt: _baseTime,
    );
    receipt = value;
    return ScenarioLabHostEvidenceCollection(
      uploadReceipt: value,
      evidence: Evidence(
        id: 'evidence-comparison-upload-1',
        subjectDigest: fixture.catalog.digest,
        fingerprint: fixture.fingerprint,
        observedAt: value.completedAt,
        policyId: requirement.evidencePolicyId.value,
        artifacts: <Artifact>[
          Artifact(
            digest: value.artifactDigest,
            size: value.size,
            mediaType: 'image/png',
            classification: ArtifactClassification.internal,
            role: 'scenario-lab.capture.app-adapter',
            pixelDigest: value.pixelDigest,
            width: value.width,
            height: value.height,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> cleanupRun(ScenarioLabRunId runId) async {
    cleanupCalls += 1;
  }
}

final class _Target implements ScenarioLabTargetPort {
  _Target(this.fingerprint);

  final ExecutionFingerprint fingerprint;
  _Session? session;

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
  }) async => session = _Session(runId: runId, nonce: nonce);

  @override
  Future<void> abort(ScenarioLabRunId runId) async {}
}

final class _Session implements ScenarioLabTargetSession {
  _Session({
    required ScenarioLabRunId runId,
    required AppAdapterRelayNonce nonce,
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
  var closeCalls = 0;

  @override
  Future<AppAdapterRelayResult> execute(
    AppAdapterRelayCommand command, {
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (command is! CaptureAppAdapterRelayCommand) {
      throw StateError('Comparison fixture accepts capture only');
    }
    return CaptureAppAdapterRelayResult(
      runId: command.runId,
      commandId: command.commandId,
      sequence: command.sequence,
      nonce: command.nonce,
      state: AppAdapterRelayResultState.succeeded,
      uploadRequestId: command.uploadGrant.requestId,
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
  ScenarioLabRunId nextRunId() => ScenarioLabRunId('run-comparison-1');

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

final class _NeverCancellation implements ScenarioLabCancellationSignal {
  final Completer<void> _never = Completer<void>();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => _never.future;
}
