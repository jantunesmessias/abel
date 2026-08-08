import 'package:experience_contracts/experience_contracts.dart';

final class ScenarioLabTestFixture {
  ScenarioLabTestFixture({this.gateway = false})
    : scenarioId = ScenarioId('scenario-ready'),
      scriptId = ScenarioScriptId('exercise-ready') {
    catalog = _catalog(scenarioId, gateway: gateway);
    manifest = _manifest(catalog, scenarioId, scriptId);
  }

  final bool gateway;
  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
  late final CatalogManifest catalog;
  late final ScenarioLabManifest manifest;

  WorkspaceSnapshot workspaceSnapshot({
    Iterable<String> contributions = const <String>[
      'studio.shell',
      'studio.lab',
      'studio.quality',
    ],
    Iterable<String> rpcMethods = const <String>[],
  }) {
    final published = contributions.toList(growable: false);
    final publishedRpcMethods = rpcMethods.toList(growable: false);
    return WorkspaceSnapshot(
      revision: 1,
      catalog: catalog,
      variantManifest: VariantManifest(
        catalogDigest: catalog.digest,
        variants: const <Variant>[],
        sources: const <VariantDefinitionSource>[],
      ),
      effectiveKitManifest: EffectiveKitManifest(
        resolvedPlanDigest: digest('studio-lab-plan'),
        modules: <EffectiveModuleState>[
          for (final contribution in published)
            EffectiveModuleState(
              moduleId: ModuleId(contribution),
              state: ModuleRuntimeState.ready,
              health: ModuleHealth.healthy,
              effectiveCapabilities: <ModuleCapabilityRef>[
                ModuleCapabilityRef(id: contribution, version: 1),
              ],
            ),
        ],
        commands: const <String>[],
        rpcMethods: publishedRpcMethods,
        studioContributions: published,
        generatedAt: time(0),
      ),
      providers: const <VisualEvidenceProviderState>[],
      visualProjections: const <VisualEvidenceProjection>[],
      generatedAt: time(0),
    );
  }

  ScenarioLabRunSnapshot runningSnapshot({
    RequiredEvidenceRunResult? evidence,
    ScenarioLabRunId? runId,
    Digest? startRequestDigest,
    ScenarioLabRuntimeInputBinding? runtimeInputBinding,
  }) => ScenarioLabRunSnapshot(
    runId: runId ?? ScenarioLabRunId('run-active'),
    startRequestDigest: startRequestDigest ?? digest('start-active'),
    contentSetDigest: digest('content-set'),
    catalogDigest: catalog.digest,
    scenarioLabManifestDigest: manifest.digest,
    scenarioId: scenarioId,
    scriptId: scriptId,
    sequence: 2,
    observedAt: time(2),
    state: ScenarioLabRunState.running,
    runtimeInputs: runtimeInputBinding ?? runtimeInputs,
    steps: <ScenarioLabStepSnapshot>[
      completedStep('bind', 0, 1),
      ScenarioLabStepSnapshot(
        stepId: 'enable',
        state: ScenarioLabStepState.running,
        startedAt: time(1),
      ),
      pendingStep('capture'),
      pendingStep('reset'),
    ],
    controls: const <ScenarioControlResult>[],
    requiredEvidence: evidence == null
        ? const <RequiredEvidenceRunResult>[]
        : <RequiredEvidenceRunResult>[evidence],
    automatedAcceptance: const <AutomatedAcceptanceResult>[],
    comparisons: const <ScenarioComparisonResult>[],
    cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.pending),
  );

  ScenarioLabRunResult result({
    RequiredEvidenceResultState evidenceState =
        RequiredEvidenceResultState.collected,
    EvidenceFreshness freshness = EvidenceFreshness.fresh,
    VerificationState acceptanceState = VerificationState.passed,
    VerificationState comparisonState = VerificationState.passed,
    int changedPixels = 0,
    Digest? evidenceArtifactDigest,
    Digest? evidenceProvenanceDigest,
    Digest? comparisonBaselineDigest,
  }) {
    final evidence = evidenceResult(
      state: evidenceState,
      freshness: freshness,
      artifactDigest: evidenceArtifactDigest,
      provenanceDigest: evidenceProvenanceDigest,
    );
    final acceptance = <AutomatedAcceptanceResult>[
      for (final id in const <String>['script-succeeds', 'evidence-accepted'])
        AutomatedAcceptanceResult(
          criterionId: AutomatedAcceptanceCriterionId(id),
          verificationState: acceptanceState,
          failure: acceptanceState == VerificationState.error
              ? ScenarioLabFailure(cause: ScenarioLabFailureCause.internalError)
              : null,
        ),
    ];
    final comparison = VisualScenarioComparisonResult(
      bindingId: ScenarioComparisonBindingId('visual-comparison'),
      requiredEvidenceId: RequiredEvidenceId('required-visual'),
      baselineDigest:
          comparisonBaselineDigest ??
          _fixtureBaselineProvenance().artifactDigest,
      candidateDigest:
          evidenceArtifactDigest ?? _fixtureCaptureReceipt().artifactDigest,
      policyDigest: digest('policy-observed'),
      verificationState: comparisonState,
      failure: comparisonState == VerificationState.error
          ? ScenarioLabFailure(cause: ScenarioLabFailureCause.internalError)
          : null,
      comparedPixels:
          comparisonState == VerificationState.passed ||
              comparisonState == VerificationState.failed
          ? 100
          : null,
      changedPixels:
          comparisonState == VerificationState.passed ||
              comparisonState == VerificationState.failed
          ? changedPixels
          : null,
      maxChannelDeltaObserved:
          comparisonState == VerificationState.passed ||
              comparisonState == VerificationState.failed
          ? (changedPixels == 0 ? 0 : 8)
          : null,
    );
    final verification = deriveVerificationState(
      acceptance.map((item) => item.verificationState),
    );
    final failed =
        verification == VerificationState.failed ||
        verification == VerificationState.error ||
        comparisonState == VerificationState.failed ||
        comparisonState == VerificationState.error;
    final snapshot = ScenarioLabRunSnapshot(
      runId: ScenarioLabRunId('run-terminal'),
      startRequestDigest: digest('start-terminal'),
      contentSetDigest: digest('content-set'),
      catalogDigest: catalog.digest,
      scenarioLabManifestDigest: manifest.digest,
      scenarioId: scenarioId,
      scriptId: scriptId,
      sequence: 8,
      observedAt: time(8),
      state: failed
          ? ScenarioLabRunState.failed
          : ScenarioLabRunState.succeeded,
      runtimeInputs: runtimeInputs,
      steps: <ScenarioLabStepSnapshot>[
        completedStep('bind', 0, 1),
        completedStep('enable', 1, 2),
        completedStep('capture', 2, 3),
        completedStep('reset', 3, 4),
      ],
      controls: <ScenarioControlResult>[
        ScenarioControlResult(
          controlId: ScenarioControlId('highlight'),
          source: ScenarioControlResultSource.reset,
          value: const BooleanScenarioControlValue(false),
        ),
      ],
      requiredEvidence: <RequiredEvidenceRunResult>[evidence],
      automatedAcceptance: acceptance,
      comparisons: <ScenarioComparisonResult>[comparison],
      cleanup: ScenarioLabCleanupResult(
        state: ScenarioLabCleanupState.succeeded,
        resetControlIds: <ScenarioControlId>[ScenarioControlId('highlight')],
      ),
      terminalCause: failed
          ? ScenarioLabTerminalCause.acceptanceFailed
          : ScenarioLabTerminalCause.completed,
    );
    return ScenarioLabRunResult(
      finalSnapshot: snapshot,
      startedAt: time(0),
      completedAt: time(8),
      verificationState: verification,
    );
  }

  ScenarioQualitySnapshot quality(
    ScenarioLabRunResult result, {
    HumanDecisionState humanDecision = HumanDecisionState.unreviewed,
    VerificationState evidenceVerification = VerificationState.passed,
  }) {
    final evidence = result.finalSnapshot.requiredEvidence.single;
    final comparison = result.finalSnapshot.comparisons.single;
    return ScenarioQualitySnapshot(
      subjectDigest: result.digest,
      runId: result.finalSnapshot.runId,
      scenarioId: result.finalSnapshot.scenarioId,
      verificationState: result.verificationState,
      humanDecision: _humanDecision(humanDecision),
      requiredEvidence: <RequiredEvidenceVerification>[
        RequiredEvidenceVerification(
          requiredEvidenceId: evidence.requiredEvidenceId,
          resultDigest: evidence.digest,
          verificationState: evidenceVerification,
        ),
      ],
      comparisonResultDigests: <Digest>[comparison.digest],
    );
  }

  RequiredEvidenceRunResult evidenceResult({
    required RequiredEvidenceResultState state,
    required EvidenceFreshness freshness,
    Digest? artifactDigest,
    Digest? provenanceDigest,
  }) => RequiredEvidenceRunResult(
    requiredEvidenceId: RequiredEvidenceId('required-visual'),
    providerId: ModuleId('capture.typed'),
    fidelity: RuntimeFidelity.simulated,
    variantId: VariantId('default'),
    freshness: freshness,
    state: state,
    evidenceDigest: state == RequiredEvidenceResultState.collected
        ? digest('evidence-collected')
        : null,
    artifacts: state == RequiredEvidenceResultState.collected
        ? <ScenarioEvidenceArtifactResult>[
            ScenarioEvidenceArtifactResult(
              artifactDigest:
                  artifactDigest ?? _fixtureCaptureReceipt().artifactDigest,
              provenanceDigest:
                  provenanceDigest ?? _fixtureCaptureReceipt().digest,
              classification: ArtifactClassification.internal,
            ),
          ]
        : const <ScenarioEvidenceArtifactResult>[],
    failure: state == RequiredEvidenceResultState.failed
        ? ScenarioLabFailure(cause: ScenarioLabFailureCause.invalidResponse)
        : null,
  );

  ScenarioLabRuntimeInputBinding get runtimeInputs =>
      ScenarioLabRuntimeInputBinding(
        executionFingerprintDigest: digest('fingerprint'),
        executionTargetId: 'browser',
        gatewayPresetId: gateway ? GatewayPresetId('lab-gateway') : null,
        compiledGatewayPlanDigest: gateway
            ? digest('compiled-gateway-plan')
            : null,
        routingTableDigest: gateway ? digest('gateway-routing-table') : null,
      );
}

CatalogManifest _catalog(ScenarioId scenarioId, {required bool gateway}) {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('lab-workspace');
  final applicationId = ApplicationId('lab-app');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'lab-distribution',
      displayName: 'Lab distribution',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Lab workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Lab application',
        root: 'apps/lab',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(
        id: scenarioId,
        applicationId: applicationId,
        title: 'Ready state',
      ),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('ready-web'),
        scenarioId: scenarioId,
        targetId: 'browser',
        launchProfileId: 'lab-web',
        gatewayPresetId: gateway ? 'lab-gateway' : null,
      ),
    ],
    reviewGuides: <ReviewGuide>[
      ReviewGuide(
        id: ReviewGuideId('review-guide'),
        applicationId: applicationId,
        title: 'Inspect the complete evidence set',
        steps: <ReviewGuideStep>[
          ReviewGuideStep(
            id: 'inspect-all',
            instruction: 'Compare every required artifact before deciding.',
            observationCriteria:
                'The required state is legible and matches the expected baseline.',
            scenarioId: scenarioId,
            bindingId: ScenarioExecutionBindingId('ready-web'),
          ),
        ],
      ),
    ],
  );
}

ScenarioLabManifest _manifest(
  CatalogManifest catalog,
  ScenarioId scenarioId,
  ScenarioScriptId scriptId,
) {
  final controlId = ScenarioControlId('highlight');
  final evidenceId = RequiredEvidenceId('required-visual');
  return ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: <CapabilityDescriptor>[
      CapabilityDescriptor(
        id: 'lab.highlight',
        version: 1,
        operations: <String>{'read', 'write', 'reset'},
      ),
    ],
    controls: <ScenarioControlDefinition>[
      ScenarioControlDefinition(
        id: controlId,
        scenarioId: scenarioId,
        displayName: 'Highlight',
        capability: AppAdapterCapabilityReference(
          id: AppAdapterCapabilityId('lab.highlight'),
          version: 1,
        ),
        readOperationId: CapabilityOperationId('read'),
        writeOperationId: CapabilityOperationId('write'),
        resetOperationId: CapabilityOperationId('reset'),
        domain: BooleanScenarioControlDomain(defaultValue: false),
      ),
    ],
    operations: <ScenarioLabOperationDefinition>[
      AssignControlOperationDefinition(
        id: ScenarioLabOperationId('enable-highlight'),
        scenarioId: scenarioId,
        controlId: controlId,
        value: const BooleanScenarioControlValue(true),
      ),
      CollectEvidenceOperationDefinition(
        id: ScenarioLabOperationId('collect-visual'),
        scenarioId: scenarioId,
        evidenceRequirementId: evidenceId,
      ),
      ResetControlOperationDefinition(
        id: ScenarioLabOperationId('reset-highlight'),
        scenarioId: scenarioId,
        controlId: controlId,
      ),
    ],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: scriptId,
        scenarioId: scenarioId,
        displayName: 'Exercise ready state',
        timeoutMs: 30000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'bind',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
            bindingId: ScenarioExecutionBindingId('ready-web'),
          ),
          OperationScenarioScriptStep(
            id: 'enable',
            timeoutMs: 2000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: ScenarioLabOperationId('enable-highlight'),
          ),
          OperationScenarioScriptStep(
            id: 'capture',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: ScenarioLabOperationId('collect-visual'),
          ),
          OperationScenarioScriptStep(
            id: 'reset',
            timeoutMs: 2000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: ScenarioLabOperationId('reset-highlight'),
          ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
      ScriptSucceededAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('script-succeeds'),
        scenarioId: scenarioId,
        displayName: 'Script succeeds',
        scriptId: scriptId,
      ),
      EvidenceAcceptedAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('evidence-accepted'),
        scenarioId: scenarioId,
        displayName: 'Evidence accepted',
        evidenceRequirementId: evidenceId,
      ),
    ],
    requiredEvidence: <RequiredEvidenceDefinition>[
      RequiredEvidenceDefinition(
        id: evidenceId,
        scenarioId: scenarioId,
        providerId: ModuleId('capture.typed'),
        fidelity: RuntimeFidelity.simulated,
        variantId: VariantId('default'),
        freshness: EvidenceFreshness.fresh,
        allowedClassifications: <ArtifactClassification>{
          ArtifactClassification.internal,
        },
        evidencePolicyId: EvidencePolicyId('lab-policy'),
        comparisonPolicy: VisualComparisonPolicyReference(
          VisualComparisonPolicyId('pixel-policy'),
        ),
      ),
    ],
    comparisonBindings: <ScenarioComparisonBinding>[
      ScenarioComparisonBinding(
        id: ScenarioComparisonBindingId('visual-comparison'),
        scenarioId: scenarioId,
        requiredEvidenceId: evidenceId,
        baseline: ArtifactComparisonInputReference(
          artifactId: SupplementalArtifactId('baseline-artifact'),
        ),
        candidate: RequiredEvidenceComparisonInputReference(
          requiredEvidenceId: evidenceId,
        ),
      ),
    ],
    visualComparisonPolicies: <VisualComparisonPolicy>[
      VisualComparisonPolicy(
        id: 'pixel-policy',
        maxChannelDelta: 8,
        maxChangedPixelRatio: 0.01,
      ),
    ],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: <HumanApprovalRequirement>[
      HumanApprovalRequirement(
        id: HumanApprovalRequirementId('approval'),
        scenarioId: scenarioId,
        reviewGuideId: ReviewGuideId('review-guide'),
        reviewGuideStepId: 'inspect-all',
        scope: HumanApprovalScope.evidenceSet,
      ),
    ],
    supplementalArtifacts: <SupplementalArtifactReference>[
      SupplementalArtifactReference(
        id: SupplementalArtifactId('baseline-artifact'),
        scenarioId: scenarioId,
        requiredEvidenceId: evidenceId,
        role: SupplementalArtifactRole.comparisonBaseline,
        artifactDigest: _fixtureBaselineProvenance().artifactDigest,
        provenanceDigest: _fixtureBaselineProvenance().digest,
        classification: ArtifactClassification.internal,
      ),
    ],
    plans: <ScenarioLabPlan>[
      ScenarioLabPlan(
        scenarioId: scenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[
          ScenarioExecutionBindingId('ready-web'),
        ],
        controlIds: <ScenarioControlId>[controlId],
        operationIds: <ScenarioLabOperationId>[
          ScenarioLabOperationId('enable-highlight'),
          ScenarioLabOperationId('collect-visual'),
          ScenarioLabOperationId('reset-highlight'),
        ],
        scriptIds: <ScenarioScriptId>[scriptId],
        automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
          AutomatedAcceptanceCriterionId('script-succeeds'),
          AutomatedAcceptanceCriterionId('evidence-accepted'),
        ],
        requiredEvidenceIds: <RequiredEvidenceId>[evidenceId],
        comparisonBindingIds: <ScenarioComparisonBindingId>[
          ScenarioComparisonBindingId('visual-comparison'),
        ],
        humanApprovalRequirementIds: <HumanApprovalRequirementId>[
          HumanApprovalRequirementId('approval'),
        ],
        supplementalArtifactIds: <SupplementalArtifactId>[
          SupplementalArtifactId('baseline-artifact'),
        ],
      ),
    ],
  );
}

HumanDecisionProjection _humanDecision(HumanDecisionState state) =>
    switch (state) {
      HumanDecisionState.unreviewed => HumanDecisionProjection(
        state: HumanDecisionState.unreviewed,
      ),
      HumanDecisionState.approved => HumanDecisionProjection(
        state: HumanDecisionState.approved,
        decisionDigest: digest('decision-approved'),
      ),
      HumanDecisionState.rejected => HumanDecisionProjection(
        state: HumanDecisionState.rejected,
        decisionDigest: digest('decision-rejected'),
      ),
      HumanDecisionState.superseded => HumanDecisionProjection(
        state: HumanDecisionState.superseded,
        decisionDigest: digest('decision-old'),
        supersededByDecisionDigest: digest('decision-new'),
      ),
    };

ScenarioLabStepSnapshot completedStep(
  String id,
  int startedMinute,
  int completedMinute,
) => ScenarioLabStepSnapshot(
  stepId: id,
  state: ScenarioLabStepState.succeeded,
  startedAt: time(startedMinute),
  completedAt: time(completedMinute),
  terminalCause: ScenarioLabStepTerminalCause.completed,
);

ScenarioLabStepSnapshot pendingStep(String id) =>
    ScenarioLabStepSnapshot(stepId: id, state: ScenarioLabStepState.pending);

DateTime time(int minute) => DateTime.utc(2026, 8, 14, 12, minute);

Digest digest(String value) => Digest.semantic(value);

AppAdapterCaptureReceipt _fixtureCaptureReceipt() => AppAdapterCaptureReceipt(
  requestId: 'required_capture',
  sessionId: 'run-terminal',
  artifactDigest: digest('review-required-artifact'),
  pixelDigest: digest('required-pixels'),
  size: 128,
  width: 8,
  height: 4,
  completedAt: time(8),
);

ScenarioLabSupplementalArtifactProvenance _fixtureBaselineProvenance() =>
    ScenarioLabSupplementalArtifactProvenance(
      artifactDigest: digest('review-baseline-artifact'),
      size: 96,
      mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      classification: ArtifactClassification.internal,
      sourceId: ScenarioLabSupplementalArtifactSourceId('baseline-source'),
      importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
        'fixture-policy',
      ),
    );
