import 'dart:async';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/png_fixture.dart';

void main() {
  test(
    'Host persists captured Evidence and compares exact supplemental pixels',
    () async {
      final fixture = await _HostEvidenceFixture.create(
        persistExactBaseline: true,
        requestId: 'request-host-evidence-positive',
      );
      addTearDown(fixture.close);
      _RpcClient? rpc;
      addTearDown(() async => rpc?.close());
      rpc = await _RpcClient.connect(
        fixture.application.rpc,
        fixture.studio.origin,
      );

      final run = await _executeCaptureRun(fixture, rpc);
      final current = run.terminal.current;
      final result = run.terminal.result!;

      expect(fixture.baselineBytes, isNot(fixture.candidateBytes));
      expect(
        Digest.bytes(fixture.baselineBytes),
        isNot(Digest.bytes(fixture.candidateBytes)),
      );
      expect(
        const PngCaptureInspector().inspect(fixture.baselineBytes).pixelDigest,
        const PngCaptureInspector().inspect(fixture.candidateBytes).pixelDigest,
      );
      expect(
        current.state,
        ScenarioLabRunState.succeeded,
        reason: '${current.toJson()}',
      );
      expect(current.terminalCause, ScenarioLabTerminalCause.completed);
      expect(current.cleanup.state, ScenarioLabCleanupState.succeeded);
      expect(
        current.steps.map((step) => step.state),
        everyElement(ScenarioLabStepState.succeeded),
      );
      expect(
        current.automatedAcceptance.map(
          (acceptance) => acceptance.verificationState,
        ),
        everyElement(VerificationState.passed),
      );
      expect(result.verificationState, VerificationState.passed);

      final required = current.requiredEvidence.single;
      expect(required.requiredEvidenceId, _evidenceId);
      expect(required.providerId, _providerId);
      expect(required.fidelity, RuntimeFidelity.simulated);
      expect(required.variantId, VariantId('desktop'));
      expect(required.freshness, EvidenceFreshness.fresh);
      expect(required.state, RequiredEvidenceResultState.collected);
      expect(required.artifacts, hasLength(1));
      final candidateArtifact = required.artifacts.single;
      expect(
        candidateArtifact.artifactDigest,
        Digest.bytes(fixture.candidateBytes),
      );
      expect(candidateArtifact.provenanceDigest, run.receipt.digest);
      expect(candidateArtifact.classification, ArtifactClassification.internal);

      final comparison = current.comparisons.single;
      expect(comparison, isA<VisualScenarioComparisonResult>());
      final visual = comparison as VisualScenarioComparisonResult;
      expect(visual.bindingId, _comparisonId);
      expect(visual.baselineDigest, fixture.baselineProvenance.artifactDigest);
      expect(visual.candidateDigest, candidateArtifact.artifactDigest);
      expect(
        visual.policyDigest,
        fixture.manifest.visualComparisonPolicies.single.digest,
      );
      expect(visual.verificationState, VerificationState.passed);
      expect(visual.comparedPixels, 2);
      expect(visual.changedPixels, 0);
      expect(visual.maxChannelDeltaObserved, 0);
      expect(visual.baselineDigest, isNot(fixture.decoyArtifactDigest));

      final evidenceDigest = required.evidenceDigest!;
      final evidence = LocalEvidenceRepository(
        store: fixture.store,
      ).readEvidence(evidenceDigest);
      expect(evidence, isNotNull);
      expect(evidence!.digest, evidenceDigest);
      expect(evidence.subjectDigest, fixture.catalog.digest);
      expect(
        evidence.freshnessFor(fixture.catalog.digest, artifactsValid: true),
        EvidenceFreshness.fresh,
      );
      expect(evidence.policyId, 'vertical-visual-v1');
      expect(evidence.observedAt, run.receipt.completedAt);
      expect(
        evidence.artifacts.single.digest,
        candidateArtifact.artifactDigest,
      );
      expect(evidence.artifacts.single.pixelDigest, run.receipt.pixelDigest);
      expect(evidence.artifacts.single.width, 2);
      expect(evidence.artifacts.single.height, 1);
      expect(
        fixture.store.readBlob(candidateArtifact.artifactDigest),
        fixture.candidateBytes,
      );
      expect(
        fixture.store.readBlob(candidateArtifact.provenanceDigest),
        run.receipt.canonicalBytes,
      );
      expect(
        fixture.store.readBlob(fixture.baselineProvenance.digest),
        fixture.baselineProvenance.canonicalBytes,
      );
      expect(
        fixture.store.readBlob(fixture.decoyArtifactDigest),
        fixture.decoyBytes,
      );
      expect(
        fixture.store.readBlob(fixture.decoyProvenance.digest),
        fixture.decoyProvenance.canonicalBytes,
      );
      _expectRuntimeClean(fixture.application, run);

      final terminalDigest = current.digest;
      final resultDigest = result.digest;
      await rpc.close();
      rpc = null;
      await fixture.restartApplication();
      rpc = await _RpcClient.connect(
        fixture.application.rpc,
        fixture.studio.origin,
      );
      await rpc.initialize();

      final reopenedResponse = await rpc.call(
        'lab.reattach',
        ScenarioLabRunObserveRequest(
          runId: run.started.runId,
          afterSequence: -1,
        ).toJson(),
      );
      expect(reopenedResponse.isSuccess, isTrue);
      final reopened = ScenarioLabRunObservation.fromJson(
        reopenedResponse.result,
      );
      expect(reopened.disposition, ScenarioLabRunDisposition.terminal);
      expect(reopened.current.digest, terminalDigest);
      expect(reopened.result?.digest, resultDigest);
      expect(
        LocalEvidenceRepository(
          store: fixture.store,
        ).readEvidence(evidenceDigest)?.digest,
        evidenceDigest,
      );

      final retryResponse = await rpc.call('lab.start', run.request.toJson());
      expect(retryResponse.isSuccess, isTrue);
      expect(
        ScenarioLabRunSnapshot.fromJson(retryResponse.result).digest,
        terminalDigest,
      );
      expect(fixture.application.captureBridge.pendingCount, 0);
      expect(fixture.application.scenarioLab!.host.relay.activeCount, 0);
      expect(fixture.application.scenarioLab!.target.activeProcessCount, 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'missing exact baseline fails notRun without selecting a decoy',
    () async {
      final fixture = await _HostEvidenceFixture.create(
        persistExactBaseline: false,
        requestId: 'request-host-evidence-missing-baseline',
      );
      addTearDown(fixture.close);
      final rpc = await _RpcClient.connect(
        fixture.application.rpc,
        fixture.studio.origin,
      );
      addTearDown(rpc.close);

      expect(
        fixture.store.readBlob(fixture.baselineProvenance.artifactDigest),
        isNull,
      );
      expect(fixture.store.readBlob(fixture.baselineProvenance.digest), isNull);
      expect(
        fixture.store.readBlob(fixture.decoyArtifactDigest),
        fixture.decoyBytes,
      );
      expect(
        fixture.store.readBlob(fixture.decoyProvenance.digest),
        fixture.decoyProvenance.canonicalBytes,
      );

      final run = await _executeCaptureRun(fixture, rpc);
      final current = run.terminal.current;

      expect(current.state, ScenarioLabRunState.failed);
      expect(current.terminalCause, ScenarioLabTerminalCause.acceptanceFailed);
      expect(current.cleanup.state, ScenarioLabCleanupState.succeeded);
      expect(
        current.automatedAcceptance.map(
          (acceptance) => acceptance.verificationState,
        ),
        everyElement(VerificationState.passed),
        reason: 'the exact comparison, not collection, must fail the run',
      );
      final required = current.requiredEvidence.single;
      expect(required.state, RequiredEvidenceResultState.collected);
      expect(required.freshness, EvidenceFreshness.fresh);
      expect(
        required.artifacts.single.artifactDigest,
        run.receipt.artifactDigest,
      );

      final comparison =
          current.comparisons.single as VisualScenarioComparisonResult;
      expect(comparison.verificationState, VerificationState.notRun);
      expect(
        comparison.baselineDigest,
        fixture.baselineProvenance.artifactDigest,
      );
      expect(comparison.baselineDigest, isNot(fixture.decoyArtifactDigest));
      expect(comparison.candidateDigest, run.receipt.artifactDigest);
      expect(comparison.failure, isNull);
      expect(comparison.comparedPixels, isNull);
      expect(comparison.changedPixels, isNull);
      expect(comparison.maxChannelDeltaObserved, isNull);
      expect(
        LocalEvidenceRepository(
          store: fixture.store,
        ).readEvidence(required.evidenceDigest!)?.digest,
        required.evidenceDigest,
      );
      _expectRuntimeClean(fixture.application, run);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

final ScenarioId _scenarioId = ScenarioId('ready');
final ScenarioScriptId _scriptId = ScenarioScriptId('capture-ready');
final ScenarioExecutionBindingId _bindingId = ScenarioExecutionBindingId(
  'ready-web',
);
final RequiredEvidenceId _evidenceId = RequiredEvidenceId('ready-visual');
final SupplementalArtifactId _baselineId = SupplementalArtifactId(
  'ready-baseline',
);
final ScenarioComparisonBindingId _comparisonId = ScenarioComparisonBindingId(
  'ready-visual-comparison',
);
final ModuleId _providerId = ModuleId('capture.app-adapter');
final VisualComparisonPolicyId _policyId = VisualComparisonPolicyId(
  'pixel-exact',
);

final class _HostEvidenceFixture {
  _HostEvidenceFixture._({
    required this.temporary,
    required this.studio,
    required this.targetScript,
    required this.store,
    required this.catalog,
    required this.manifest,
    required this.requestId,
    required this.baselineBytes,
    required this.candidateBytes,
    required this.decoyBytes,
    required this.baselineProvenance,
    required this.decoyProvenance,
    required this.decoyArtifactDigest,
  });

  static Future<_HostEvidenceFixture> create({
    required bool persistExactBaseline,
    required String requestId,
  }) async {
    final temporary = Directory.systemTemp.createTempSync(
      'workspace-scenario-lab-evidence-host-',
    );
    final studioRoot = Directory(p.join(temporary.path, 'studio'))
      ..createSync();
    File(p.join(studioRoot.path, 'index.html')).writeAsStringSync('studio');
    final studio = StaticWebOriginServer(rootDirectory: studioRoot.path);
    try {
      await studio.start();
      final pixels = <int>[12, 34, 56, 255, 78, 90, 123, 255];
      final baselineBytes = rgbaPng(
        width: 2,
        height: 1,
        pixels: pixels,
        filter: 0,
        compressionLevel: 1,
      );
      final candidateBytes = rgbaPng(
        width: 2,
        height: 1,
        pixels: pixels,
        filter: 1,
        compressionLevel: 9,
      );
      final decoyBytes = rgbaPng(
        width: 2,
        height: 1,
        pixels: const <int>[1, 2, 3, 255, 4, 5, 6, 255],
      );
      if (Digest.bytes(baselineBytes) == Digest.bytes(candidateBytes)) {
        throw StateError('Vertical PNG encodings must differ');
      }
      final store = FileSystemWorkspaceStore(workspaceRoot: temporary.path);
      final baselineProvenance = ScenarioLabSupplementalArtifactProvenance(
        artifactDigest: Digest.bytes(baselineBytes),
        size: baselineBytes.length,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
        classification: ArtifactClassification.internal,
        sourceId: ScenarioLabSupplementalArtifactSourceId(
          'vertical-ready-baseline',
        ),
        importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
          'vertical-test-v1',
        ),
      );
      final decoyProvenance = ScenarioLabSupplementalArtifactProvenance(
        artifactDigest: Digest.bytes(decoyBytes),
        size: decoyBytes.length,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
        classification: ArtifactClassification.internal,
        sourceId: ScenarioLabSupplementalArtifactSourceId(
          'vertical-ready-decoy',
        ),
        importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
          'vertical-test-v1',
        ),
      );
      late final Digest decoyArtifactDigest;
      store.withExclusiveLock(() {
        if (persistExactBaseline) {
          final artifact = store.putBlob(baselineBytes);
          final provenance = store.putBlob(baselineProvenance.canonicalBytes);
          if (artifact != baselineProvenance.artifactDigest ||
              provenance != baselineProvenance.digest) {
            throw StateError('Exact baseline CAS persistence changed digest');
          }
        }
        decoyArtifactDigest = store.putBlob(decoyBytes);
        final decoyProvenanceDigest = store.putBlob(
          decoyProvenance.canonicalBytes,
        );
        if (decoyArtifactDigest != decoyProvenance.artifactDigest ||
            decoyProvenanceDigest != decoyProvenance.digest) {
          throw StateError('Decoy CAS persistence changed digest');
        }
        store.rebuildCasIndex();
      });
      final catalog = _catalog();
      final manifest = _manifest(catalog, baselineProvenance);
      final fixture = _HostEvidenceFixture._(
        temporary: temporary,
        studio: studio,
        targetScript: _writeTargetProcess(temporary),
        store: store,
        catalog: catalog,
        manifest: manifest,
        requestId: requestId,
        baselineBytes: baselineBytes,
        candidateBytes: candidateBytes,
        decoyBytes: decoyBytes,
        baselineProvenance: baselineProvenance,
        decoyProvenance: decoyProvenance,
        decoyArtifactDigest: decoyArtifactDigest,
      );
      await fixture.restartApplication();
      return fixture;
    } on Object {
      await studio.close();
      if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      rethrow;
    }
  }

  static const String sessionToken = '0123456789abcdef0123456789abcdef';

  final Directory temporary;
  final StaticWebOriginServer studio;
  final File targetScript;
  final FileSystemWorkspaceStore store;
  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
  final String requestId;
  final List<int> baselineBytes;
  final List<int> candidateBytes;
  final List<int> decoyBytes;
  final ScenarioLabSupplementalArtifactProvenance baselineProvenance;
  final ScenarioLabSupplementalArtifactProvenance decoyProvenance;
  final Digest decoyArtifactDigest;
  WorkspaceHost? _application;

  WorkspaceHost get application => _application!;

  Future<void> restartApplication() async {
    final previous = _application;
    _application = null;
    await previous?.close();
    final next = _newApplication();
    _application = next;
    try {
      await next.start();
    } on Object {
      _application = null;
      await next.close();
      rethrow;
    }
  }

  WorkspaceHost _newApplication() {
    const builtins = BuiltinModuleCatalog();
    final kitCatalog = builtins.create(platform: _hostPlatform());
    final plan = const KitPlanResolver().resolve(
      catalog: kitCatalog,
      profileId: 'full-local',
      overlays: <KitSelection>[
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(
              moduleId: ModuleId('gateway.interceptor'),
              enabled: false,
            ),
            KitModuleSelection(
              moduleId: ModuleId('scenario.lab.local'),
              enabled: true,
              settings: <String, Object?>{'evidenceClassification': 'internal'},
            ),
          ],
        ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );
    return WorkspaceHost.fromResolvedPlan(
      studioOrigin: studio.origin,
      sessionToken: sessionToken,
      workspaceRoot: temporary.path,
      launchProfiles: <LaunchProfile>[
        LaunchProfile(
          id: 'lab-web',
          applicationId: ApplicationId('app'),
          platform: TargetPlatform.web,
          command: Platform.resolvedExecutable,
          arguments: <String>[
            '--packages=${p.join(_repositoryRoot(), '.dart_tool', 'package_config.json')}',
            targetScript.path,
          ],
          workingDirectory: '.',
          overlay: RuntimeConfigurationOverlay(const <String, String>{}),
          bootstrapPolicy: ApplicationBootstrapPolicy(
            const <String, BootstrapDependencyPolicy>{},
          ),
        ),
      ],
      catalog: kitCatalog,
      plan: plan,
      workspaceCatalog: catalog,
      workspaceScenarioLabManifest: manifest,
    );
  }

  Future<void> close() async {
    final application = _application;
    _application = null;
    try {
      await application?.close();
    } finally {
      try {
        await studio.close();
      } finally {
        if (temporary.existsSync()) temporary.deleteSync(recursive: true);
      }
    }
  }
}

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('app');
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
        targetId: 'target-web',
        launchProfileId: 'lab-web',
      ),
    ],
  );
}

ScenarioLabManifest _manifest(
  CatalogManifest catalog,
  ScenarioLabSupplementalArtifactProvenance baseline,
) {
  final operationId = ScenarioLabOperationId('collect-ready');
  return ScenarioLabManifest(
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
        displayName: 'Capture and compare ready',
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
            id: 'capture',
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
        fidelity: RuntimeFidelity.simulated,
        variantId: VariantId('desktop'),
        freshness: EvidenceFreshness.fresh,
        allowedClassifications: <ArtifactClassification>{
          ArtifactClassification.internal,
        },
        evidencePolicyId: EvidencePolicyId('vertical-visual-v1'),
        comparisonPolicy: VisualComparisonPolicyReference(_policyId),
      ),
    ],
    comparisonBindings: <ScenarioComparisonBinding>[
      ScenarioComparisonBinding(
        id: _comparisonId,
        scenarioId: _scenarioId,
        requiredEvidenceId: _evidenceId,
        baseline: ArtifactComparisonInputReference(artifactId: _baselineId),
        candidate: RequiredEvidenceComparisonInputReference(
          requiredEvidenceId: _evidenceId,
        ),
      ),
    ],
    visualComparisonPolicies: <VisualComparisonPolicy>[
      VisualComparisonPolicy(
        id: _policyId.value,
        maxChannelDelta: 0,
        maxChangedPixelRatio: 0,
      ),
    ],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: const <HumanApprovalRequirement>[],
    supplementalArtifacts: <SupplementalArtifactReference>[
      SupplementalArtifactReference(
        id: _baselineId,
        scenarioId: _scenarioId,
        requiredEvidenceId: _evidenceId,
        role: SupplementalArtifactRole.comparisonBaseline,
        artifactDigest: baseline.artifactDigest,
        provenanceDigest: baseline.digest,
        classification: baseline.classification,
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
          AutomatedAcceptanceCriterionId('evidence-accepted'),
        ],
        requiredEvidenceIds: <RequiredEvidenceId>[_evidenceId],
        comparisonBindingIds: <ScenarioComparisonBindingId>[_comparisonId],
        humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
        supplementalArtifactIds: <SupplementalArtifactId>[_baselineId],
      ),
    ],
  );
}

Future<
  ({
    ScenarioLabRunStartRequest request,
    ScenarioLabRunSnapshot started,
    ScenarioLabRunObservation terminal,
    AppAdapterRelayCaptureUploadGrant uploadGrant,
    AppAdapterCaptureReceipt receipt,
  })
>
_executeCaptureRun(_HostEvidenceFixture fixture, _RpcClient rpc) async {
  final initialized = await rpc.initialize();
  final capabilities =
      (initialized.result! as Map<String, Object?>)['capabilities']!
          as List<Object?>;
  expect(
    capabilities,
    containsAll(<String>[
      'lab.start',
      'lab.reattach',
      'lab.relay.describe',
      'lab.relay.hello',
      'lab.relay.next',
      'lab.relay.result',
    ]),
  );
  final identity = fixture.application.workspace!.contentSetIdentity;
  final request = ScenarioLabRunStartRequest(
    requestId: ScenarioLabRunRequestId(fixture.requestId),
    expectedContentSetDigest: identity.contentSetDigest,
    expectedScenarioLabManifestDigest: fixture.manifest.digest,
    scenarioId: _scenarioId,
    scriptId: _scriptId,
    requestedAt: DateTime.utc(2026, 8, 14, 12),
  );
  final startResponse = await rpc.call('lab.start', request.toJson());
  expect(startResponse.isSuccess, isTrue, reason: '${startResponse.error}');
  final started = ScenarioLabRunSnapshot.fromJson(startResponse.result);
  expect(started.state, ScenarioLabRunState.queued);

  final description = await _waitForRelay(rpc, started.runId);
  final descriptor = description.descriptor!;
  final hello = AppAdapterRelayHello(
    runId: started.runId,
    adapterInstanceId: 'adapter-instance-evidence-1',
    sequence: 0,
    nonce: descriptor.nonce,
    capabilities: const <AppAdapterCapabilityReference>[],
    evidenceProviderIds: <ModuleId>[_providerId],
  );
  final helloResponse = await rpc.call(
    'lab.relay.hello',
    ScenarioLabRelayHelloSubmission(
      descriptorDigest: descriptor.digest,
      hello: hello,
    ).toJson(),
  );
  expect(helloResponse.isSuccess, isTrue, reason: '${helloResponse.error}');

  final pollResponse = await rpc.call(
    'lab.relay.next',
    ScenarioLabRelayPollRequest(
      runId: started.runId,
      descriptorDigest: descriptor.digest,
      afterSequence: 0,
      waitMs: 5000,
    ).toJson(),
  );
  expect(pollResponse.isSuccess, isTrue, reason: '${pollResponse.error}');
  final poll = ScenarioLabRelayPollResponse.fromJson(pollResponse.result);
  expect(poll.state, ScenarioLabRelayPollState.command);
  expect(poll.command, isA<CaptureAppAdapterRelayCommand>());
  final command = poll.command! as CaptureAppAdapterRelayCommand;
  expect(command.requiredEvidenceId, _evidenceId);
  expect(command.providerId, _providerId);
  final uploadGrant = command.uploadGrant;

  final uploadStatus = await _putPng(
    uploadGrant.uploadUri,
    origin: descriptor.origin.origin,
    bytes: fixture.candidateBytes,
  );
  expect(uploadStatus, HttpStatus.created);
  final bridgeStatus = fixture.application.captureBridge.status(
    sessionId: uploadGrant.sessionId,
    requestId: uploadGrant.requestId,
  );
  expect(bridgeStatus.state, 'completed');
  final receipt = bridgeStatus.receipt!;
  expect(receipt.requestId, uploadGrant.requestId);
  expect(receipt.sessionId, uploadGrant.sessionId);
  expect(receipt.artifactDigest, Digest.bytes(fixture.candidateBytes));
  expect(receipt.width, 2);
  expect(receipt.height, 1);

  final relayResult = CaptureAppAdapterRelayResult(
    runId: command.runId,
    commandId: command.commandId,
    sequence: command.sequence,
    nonce: command.nonce,
    state: AppAdapterRelayResultState.succeeded,
    uploadRequestId: uploadGrant.requestId,
  );
  final resultResponse = await rpc.call(
    'lab.relay.result',
    ScenarioLabRelayResultSubmission(
      descriptorDigest: descriptor.digest,
      result: relayResult,
    ).toJson(),
  );
  expect(resultResponse.isSuccess, isTrue, reason: '${resultResponse.error}');

  final terminal = await _waitForTerminal(rpc, started.runId);
  expect(terminal.result, isNotNull);
  return (
    request: request,
    started: started,
    terminal: terminal,
    uploadGrant: uploadGrant,
    receipt: receipt,
  );
}

void _expectRuntimeClean(
  WorkspaceHost application,
  ({
    ScenarioLabRunStartRequest request,
    ScenarioLabRunSnapshot started,
    ScenarioLabRunObservation terminal,
    AppAdapterRelayCaptureUploadGrant uploadGrant,
    AppAdapterCaptureReceipt receipt,
  })
  run,
) {
  expect(application.captureBridge.pendingCount, 0);
  expect(application.scenarioLab!.host.relay.activeCount, 0);
  expect(application.scenarioLab!.target.activeProcessCount, 0);
  expect(
    () => application.captureBridge.status(
      sessionId: run.uploadGrant.sessionId,
      requestId: run.uploadGrant.requestId,
    ),
    throwsStateError,
  );
}

Future<int> _putPng(
  Uri uri, {
  required String origin,
  required List<int> bytes,
}) async {
  final client = HttpClient();
  try {
    final request = await client.putUrl(uri);
    request.headers
      ..set('origin', origin)
      ..contentType = ContentType('image', 'png');
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

File _writeTargetProcess(Directory workspace) {
  final script = File(p.join(workspace.path, 'lab_target.dart'));
  script.writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final origin = Uri.parse('http://${server.address.address}:${server.port}');
  stdout.writeln(jsonEncode(TargetReadinessRecord(
    launchAttemptId: TargetLaunchAttemptId(
      Platform.environment['TARGET_LAUNCH_ATTEMPT_ID']!,
    ),
    targetId: Platform.environment['TARGET_ID']!,
    launchProfileId: Platform.environment['TARGET_LAUNCH_PROFILE_ID']!,
    origin: origin,
    processId: pid,
  ).toJson()));
  await for (final request in server) {
    if (request.uri.path == '/health') {
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"status":"ready"}');
    } else {
      request.response.write('<!doctype html><title>Lab target</title>');
    }
    await request.response.close();
  }
}
''');
  return script;
}

Future<ScenarioLabRelayDescription> _waitForRelay(
  _RpcClient rpc,
  ScenarioLabRunId runId,
) async {
  const timeout = Duration(seconds: 10);
  final stopwatch = Stopwatch()..start();
  ScenarioLabRelayDescriptionStatus? lastStatus;
  while (stopwatch.elapsed < timeout) {
    final response = await rpc.call('lab.relay.describe', <String, Object?>{
      'runId': runId.value,
    });
    expect(response.isSuccess, isTrue, reason: '${response.error}');
    final description = ScenarioLabRelayDescription.fromJson(response.result);
    lastStatus = description.status;
    if (description.status == ScenarioLabRelayDescriptionStatus.ready) {
      return description;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError(
    'Scenario Lab relay did not become ready within '
    '${timeout.inSeconds}s; last status: ${lastStatus?.name ?? 'none'}',
  );
}

Future<ScenarioLabRunObservation> _waitForTerminal(
  _RpcClient rpc,
  ScenarioLabRunId runId,
) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    final response = await rpc.call(
      'lab.reattach',
      ScenarioLabRunObserveRequest(runId: runId, afterSequence: -1).toJson(),
    );
    expect(response.isSuccess, isTrue, reason: '${response.error}');
    final observation = ScenarioLabRunObservation.fromJson(response.result);
    if (observation.disposition == ScenarioLabRunDisposition.terminal) {
      return observation;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('Scenario Lab run did not become terminal');
}

final class _RpcClient {
  _RpcClient(this.channel, this.iterator, this.sessionToken);

  final IOWebSocketChannel channel;
  final StreamIterator<Object?> iterator;
  final String sessionToken;
  var nextId = 1;

  static Future<_RpcClient> connect(
    HostRpcServer server,
    Uri studioOrigin,
  ) async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;
    return _RpcClient(
      channel,
      StreamIterator<Object?>(channel.stream),
      server.sessionToken,
    );
  }

  Future<JsonRpcResponse> initialize() => call(
    'workspace.initialize',
    <String, Object?>{'protocolVersion': 1, 'sessionToken': sessionToken},
  );

  Future<JsonRpcResponse> call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = 'request-${nextId++}';
    channel.sink.add(
      JsonRpcRequest(method: method, id: id, params: params).encode(),
    );
    while (await iterator.moveNext()) {
      final message = const JsonRpcCodec().decode(iterator.current! as String);
      if (message is JsonRpcResponse && message.id == id) return message;
    }
    throw StateError('RPC connection closed before response $id');
  }

  Future<void> close() async {
    await iterator.cancel();
    await channel.sink.close();
  }
}

String _hostPlatform() => switch (Platform.operatingSystem) {
  'linux' => 'linux-x64',
  'macos' => 'macos-arm64',
  'windows' => 'windows-x64',
  final value => '$value-native',
};

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(current.path, 'libs')).existsSync()) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
