import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client.dart';

import 'scenario_lab_fixture.dart';

final class ScenarioQualityMixedOriginFixture {
  ScenarioQualityMixedOriginFixture() {
    final base = ScenarioLabTestFixture();
    catalog = base.catalog;
    final original = base.manifest;
    final currentId = RequiredEvidenceId('required-visual');
    final sourceId = RequiredEvidenceId('required-baseline');
    final currentDefinition = original.requiredEvidence.single;
    final sourceDefinition = RequiredEvidenceDefinition(
      id: sourceId,
      scenarioId: base.scenarioId,
      providerId: currentDefinition.providerId,
      fidelity: currentDefinition.fidelity,
      variantId: currentDefinition.variantId,
      freshness: currentDefinition.freshness,
      allowedClassifications: currentDefinition.allowedClassifications,
      evidencePolicyId: currentDefinition.evidencePolicyId,
      comparisonPolicy: currentDefinition.comparisonPolicy,
    );
    final collectSourceId = ScenarioLabOperationId('collect-baseline');
    final sourceCriterionId = AutomatedAcceptanceCriterionId(
      'baseline-evidence-accepted',
    );
    final originalScript = original.scripts.single;
    final originalPlan = original.plans.single;
    final currentCandidateId = SupplementalArtifactId('current-candidate');
    final sourceBaselineId = SupplementalArtifactId('source-baseline');

    currentReceipt = _receipt(
      id: 'mixed-current',
      artifactDigest: digest('mixed-current-artifact'),
      size: 128,
    );
    sourceReceipt = _receipt(
      id: 'mixed-source',
      artifactDigest: digest('mixed-source-artifact'),
      size: 144,
    );
    currentCandidate = _supplemental(
      id: 'mixed-current-candidate',
      artifactDigest: digest('mixed-current-candidate-artifact'),
      size: 112,
    );
    sourceBaseline = _supplemental(
      id: 'mixed-source-baseline',
      artifactDigest: digest('mixed-source-baseline-artifact'),
      size: 104,
    );

    manifest = ScenarioLabManifest(
      catalog: catalog,
      appAdapterCapabilities: original.appAdapterCapabilities,
      controls: original.controls,
      operations: <ScenarioLabOperationDefinition>[
        ...original.operations,
        CollectEvidenceOperationDefinition(
          id: collectSourceId,
          scenarioId: base.scenarioId,
          evidenceRequirementId: sourceId,
        ),
      ],
      scripts: <ScenarioScriptDefinition>[
        ScenarioScriptDefinition(
          id: originalScript.id,
          scenarioId: originalScript.scenarioId,
          displayName: originalScript.displayName,
          timeoutMs: originalScript.timeoutMs,
          timeoutOutcome: originalScript.timeoutOutcome,
          cancellationPolicy: originalScript.cancellationPolicy,
          steps: <ScenarioScriptStep>[
            ...originalScript.steps.take(originalScript.steps.length - 1),
            OperationScenarioScriptStep(
              id: 'capture-baseline',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
              operationId: collectSourceId,
            ),
            originalScript.steps.last,
          ],
        ),
      ],
      automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
        ...original.automatedAcceptanceCriteria,
        EvidenceAcceptedAcceptanceCriterion(
          id: sourceCriterionId,
          scenarioId: base.scenarioId,
          displayName: 'Baseline evidence accepted',
          evidenceRequirementId: sourceId,
        ),
      ],
      requiredEvidence: <RequiredEvidenceDefinition>[
        currentDefinition,
        sourceDefinition,
      ],
      comparisonBindings: <ScenarioComparisonBinding>[
        ScenarioComparisonBinding(
          id: ScenarioComparisonBindingId('visual-comparison'),
          scenarioId: base.scenarioId,
          requiredEvidenceId: currentId,
          baseline: RequiredEvidenceComparisonInputReference(
            requiredEvidenceId: sourceId,
          ),
          candidate: ArtifactComparisonInputReference(
            artifactId: currentCandidateId,
          ),
        ),
        ScenarioComparisonBinding(
          id: ScenarioComparisonBindingId('baseline-comparison'),
          scenarioId: base.scenarioId,
          requiredEvidenceId: sourceId,
          baseline: ArtifactComparisonInputReference(
            artifactId: sourceBaselineId,
          ),
          candidate: RequiredEvidenceComparisonInputReference(
            requiredEvidenceId: sourceId,
          ),
        ),
      ],
      visualComparisonPolicies: original.visualComparisonPolicies,
      semanticComparisonPolicies: original.semanticComparisonPolicies,
      humanApprovalRequirements: original.humanApprovalRequirements,
      supplementalArtifacts: <SupplementalArtifactReference>[
        SupplementalArtifactReference(
          id: currentCandidateId,
          scenarioId: base.scenarioId,
          requiredEvidenceId: currentId,
          role: SupplementalArtifactRole.comparisonCandidate,
          artifactDigest: currentCandidate.artifactDigest,
          provenanceDigest: currentCandidate.digest,
          classification: currentCandidate.classification,
        ),
        SupplementalArtifactReference(
          id: sourceBaselineId,
          scenarioId: base.scenarioId,
          requiredEvidenceId: sourceId,
          role: SupplementalArtifactRole.comparisonBaseline,
          artifactDigest: sourceBaseline.artifactDigest,
          provenanceDigest: sourceBaseline.digest,
          classification: sourceBaseline.classification,
        ),
      ],
      plans: <ScenarioLabPlan>[
        ScenarioLabPlan(
          scenarioId: originalPlan.scenarioId,
          executionBindingIds: originalPlan.executionBindingIds,
          controlIds: originalPlan.controlIds,
          operationIds: <ScenarioLabOperationId>[
            ...originalPlan.operationIds,
            collectSourceId,
          ],
          scriptIds: originalPlan.scriptIds,
          automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
            ...originalPlan.automatedAcceptanceCriterionIds,
            sourceCriterionId,
          ],
          requiredEvidenceIds: <RequiredEvidenceId>[currentId, sourceId],
          comparisonBindingIds: <ScenarioComparisonBindingId>[
            ScenarioComparisonBindingId('visual-comparison'),
            ScenarioComparisonBindingId('baseline-comparison'),
          ],
          humanApprovalRequirementIds: originalPlan.humanApprovalRequirementIds,
          supplementalArtifactIds: <SupplementalArtifactId>[
            currentCandidateId,
            sourceBaselineId,
          ],
        ),
      ],
    );

    final currentEvidence = _evidence(currentId, currentReceipt);
    final sourceEvidence = _evidence(sourceId, sourceReceipt);
    final currentComparison = _comparison(
      id: 'visual-comparison',
      requiredEvidenceId: currentId,
      baseline: sourceReceipt.artifactDigest,
      candidate: currentCandidate.artifactDigest,
    );
    final sourceComparison = _comparison(
      id: 'baseline-comparison',
      requiredEvidenceId: sourceId,
      baseline: sourceBaseline.artifactDigest,
      candidate: sourceReceipt.artifactDigest,
    );
    final snapshot = ScenarioLabRunSnapshot(
      runId: ScenarioLabRunId('run-terminal'),
      startRequestDigest: digest('mixed-start'),
      contentSetDigest: digest('mixed-content'),
      catalogDigest: catalog.digest,
      scenarioLabManifestDigest: manifest.digest,
      scenarioId: base.scenarioId,
      scriptId: base.scriptId,
      sequence: 8,
      observedAt: time(8),
      state: ScenarioLabRunState.succeeded,
      runtimeInputs: base.runtimeInputs,
      steps: <ScenarioLabStepSnapshot>[
        completedStep('bind', 0, 1),
        completedStep('enable', 1, 2),
        completedStep('capture', 2, 3),
        completedStep('capture-baseline', 3, 4),
        completedStep('reset', 4, 5),
      ],
      controls: base.result().finalSnapshot.controls,
      requiredEvidence: <RequiredEvidenceRunResult>[
        currentEvidence,
        sourceEvidence,
      ],
      automatedAcceptance: <AutomatedAcceptanceResult>[
        for (final criterion in manifest.automatedAcceptanceCriteria)
          AutomatedAcceptanceResult(
            criterionId: criterion.id,
            verificationState: VerificationState.passed,
          ),
      ],
      comparisons: <ScenarioComparisonResult>[
        currentComparison,
        sourceComparison,
      ],
      cleanup: ScenarioLabCleanupResult(
        state: ScenarioLabCleanupState.succeeded,
        resetControlIds: <ScenarioControlId>[ScenarioControlId('highlight')],
      ),
      terminalCause: ScenarioLabTerminalCause.completed,
    );
    result = ScenarioLabRunResult(
      finalSnapshot: snapshot,
      startedAt: time(0),
      completedAt: time(8),
      verificationState: VerificationState.passed,
    );
    quality = ScenarioQualitySnapshot(
      subjectDigest: result.digest,
      runId: snapshot.runId,
      scenarioId: snapshot.scenarioId,
      verificationState: VerificationState.passed,
      humanDecision: HumanDecisionProjection(
        state: HumanDecisionState.unreviewed,
      ),
      requiredEvidence: <RequiredEvidenceVerification>[
        RequiredEvidenceVerification(
          requiredEvidenceId: currentId,
          resultDigest: currentEvidence.digest,
          verificationState: VerificationState.passed,
        ),
        RequiredEvidenceVerification(
          requiredEvidenceId: sourceId,
          resultDigest: sourceEvidence.digest,
          verificationState: VerificationState.passed,
        ),
      ],
      comparisonResultDigests: <Digest>[
        currentComparison.digest,
        sourceComparison.digest,
      ],
    );
    descriptor = ScenarioQualityReviewDescriptor(
      runId: snapshot.runId,
      runResultDigest: result.digest,
      qualityDigest: quality.digest,
      requirementId: HumanApprovalRequirementId('approval'),
      requirementScope: HumanApprovalScope.evidenceSet,
      reviewGuideId: ReviewGuideId('review-guide'),
      reviewGuideStepId: 'inspect-all',
      requiredEvidenceResultDigests: <Digest>[
        currentEvidence.digest,
        sourceEvidence.digest,
      ],
      comparisonResultDigests: <Digest>[
        currentComparison.digest,
        sourceComparison.digest,
      ],
      artifacts: <ScenarioQualityReviewArtifactDescriptor>[
        _collectedDescriptor(currentEvidence, currentReceipt),
        _collectedDescriptor(sourceEvidence, sourceReceipt),
        _collectedDescriptor(
          sourceEvidence,
          sourceReceipt,
          role: ScenarioQualityReviewArtifactRole.comparisonBaseline,
          comparisonResultDigest: currentComparison.digest,
        ),
        _supplementalDescriptor(
          currentEvidence,
          currentCandidate,
          role: ScenarioQualityReviewArtifactRole.comparisonCandidate,
          comparisonResultDigest: currentComparison.digest,
        ),
        _supplementalDescriptor(
          sourceEvidence,
          sourceBaseline,
          role: ScenarioQualityReviewArtifactRole.comparisonBaseline,
          comparisonResultDigest: sourceComparison.digest,
        ),
        _collectedDescriptor(
          sourceEvidence,
          sourceReceipt,
          role: ScenarioQualityReviewArtifactRole.comparisonCandidate,
          comparisonResultDigest: sourceComparison.digest,
        ),
      ],
    );
    provenance = <Digest, Object>{
      for (final artifact in descriptor.artifacts)
        artifact.provenanceDigest: switch (artifact.provenanceDigest) {
          final digestValue when digestValue == currentReceipt.digest =>
            currentReceipt,
          final digestValue when digestValue == sourceReceipt.digest =>
            sourceReceipt,
          final digestValue when digestValue == currentCandidate.digest =>
            currentCandidate,
          _ => sourceBaseline,
        },
    };
  }

  late final CatalogManifest catalog;
  late final ScenarioLabManifest manifest;
  late final ScenarioLabRunResult result;
  late final ScenarioQualitySnapshot quality;
  late final ScenarioQualityReviewDescriptor descriptor;
  late final AppAdapterCaptureReceipt currentReceipt;
  late final AppAdapterCaptureReceipt sourceReceipt;
  late final ScenarioLabSupplementalArtifactProvenance currentCandidate;
  late final ScenarioLabSupplementalArtifactProvenance sourceBaseline;
  late final Map<Digest, Object> provenance;
}

final class MixedOriginQualityHost
    implements
        StudioHostScenarioQualityClient,
        StudioHostScenarioQualityResourceClient {
  MixedOriginQualityHost(this.fixture);

  final ScenarioQualityMixedOriginFixture fixture;

  @override
  Future<ScenarioQualityDescribeResult> describeScenarioQuality(
    ScenarioQualityDescribeRequest request,
  ) async => ScenarioQualityDescribeResult(
    description: ScenarioQualityDescription(
      runId: fixture.result.finalSnapshot.runId,
      runResultDigest: fixture.result.digest,
      quality: fixture.quality,
      availability: ScenarioQualityReviewAvailability.available,
      requirementId: HumanApprovalRequirementId('approval'),
      decisionCount: 0,
    ),
    reviewDescriptor: fixture.descriptor,
  );

  @override
  Future<ScenarioQualityReviewOpenResult> openScenarioQualityReview(
    ScenarioQualityReviewOpenRequest request,
  ) async => ScenarioQualityReviewOpenResult(
    reviewDescriptor: fixture.descriptor,
    resources: <ScenarioQualityReviewResourceBinding>[
      for (var index = 0; index < fixture.descriptor.artifacts.length; index++)
        _binding(fixture.descriptor.artifacts[index], index),
    ],
  );

  @override
  Future<Object> readScenarioQualityReviewProvenance({
    required ResourceHandle handle,
    required ScenarioQualityReviewProvenanceKind kind,
    required Digest expectedDigest,
  }) async => fixture.provenance[expectedDigest]!;

  @override
  Future<StudioResourceLease> openScenarioQualityReviewImage({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  }) async => StudioResourceLease(
    uri: Uri.parse('blob:mixed-${descriptor.digest.value}'),
    digest: descriptor.artifactDigest,
    mediaType: descriptor.mediaType,
    size: descriptor.size,
    releaseCallback: () {},
  );

  @override
  Future<void> validateScenarioQualityReviewArtifact({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  }) async {}

  @override
  Future<ScenarioQualityDecisionGrant> grantScenarioQualityDecision(
    ScenarioQualityDecisionGrantRequest request,
  ) => throw StateError('not used');

  @override
  Future<ScenarioQualityDecisionAppendResult> appendScenarioQualityDecision(
    ScenarioQualityDecisionAppendRequest request,
  ) => throw StateError('not used');

  @override
  Future<ScenarioQualityDecisionView> getScenarioQualityDecision(
    ScenarioQualityDecisionGetRequest request,
  ) => throw StateError('not used');
}

RequiredEvidenceRunResult _evidence(
  RequiredEvidenceId id,
  AppAdapterCaptureReceipt receipt,
) => RequiredEvidenceRunResult(
  requiredEvidenceId: id,
  providerId: ModuleId('capture.typed'),
  fidelity: RuntimeFidelity.simulated,
  variantId: VariantId('default'),
  freshness: EvidenceFreshness.fresh,
  state: RequiredEvidenceResultState.collected,
  evidenceDigest: digest('evidence-${id.value}'),
  artifacts: <ScenarioEvidenceArtifactResult>[
    ScenarioEvidenceArtifactResult(
      artifactDigest: receipt.artifactDigest,
      provenanceDigest: receipt.digest,
      classification: ArtifactClassification.internal,
    ),
  ],
);

VisualScenarioComparisonResult _comparison({
  required String id,
  required RequiredEvidenceId requiredEvidenceId,
  required Digest baseline,
  required Digest candidate,
}) => VisualScenarioComparisonResult(
  bindingId: ScenarioComparisonBindingId(id),
  requiredEvidenceId: requiredEvidenceId,
  baselineDigest: baseline,
  candidateDigest: candidate,
  policyDigest: digest('policy-$id'),
  verificationState: VerificationState.passed,
  comparedPixels: 100,
  changedPixels: 0,
  maxChannelDeltaObserved: 0,
);

ScenarioQualityReviewArtifactDescriptor _collectedDescriptor(
  RequiredEvidenceRunResult evidence,
  AppAdapterCaptureReceipt receipt, {
  ScenarioQualityReviewArtifactRole role =
      ScenarioQualityReviewArtifactRole.requiredEvidence,
  Digest? comparisonResultDigest,
}) => ScenarioQualityReviewArtifactDescriptor(
  requiredEvidenceId: evidence.requiredEvidenceId,
  requiredEvidenceResultDigest: evidence.digest,
  role: role,
  artifactDigest: receipt.artifactDigest,
  provenanceDigest: receipt.digest,
  provenanceKind: ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
  classification: ArtifactClassification.internal,
  mediaType: 'image/png',
  size: receipt.size,
  comparisonResultDigest: comparisonResultDigest,
);

ScenarioQualityReviewArtifactDescriptor _supplementalDescriptor(
  RequiredEvidenceRunResult evidence,
  ScenarioLabSupplementalArtifactProvenance provenance, {
  required ScenarioQualityReviewArtifactRole role,
  required Digest comparisonResultDigest,
}) => ScenarioQualityReviewArtifactDescriptor(
  requiredEvidenceId: evidence.requiredEvidenceId,
  requiredEvidenceResultDigest: evidence.digest,
  role: role,
  artifactDigest: provenance.artifactDigest,
  provenanceDigest: provenance.digest,
  provenanceKind:
      ScenarioQualityReviewProvenanceKind.supplementalArtifactImport,
  classification: provenance.classification,
  mediaType: provenance.mediaType.value,
  size: provenance.size,
  comparisonResultDigest: comparisonResultDigest,
);

AppAdapterCaptureReceipt _receipt({
  required String id,
  required Digest artifactDigest,
  required int size,
}) => AppAdapterCaptureReceipt(
  requestId: '${id}_capture',
  sessionId: 'run-terminal',
  artifactDigest: artifactDigest,
  pixelDigest: digest('$id-pixels'),
  size: size,
  width: 8,
  height: 4,
  completedAt: time(8),
);

ScenarioLabSupplementalArtifactProvenance _supplemental({
  required String id,
  required Digest artifactDigest,
  required int size,
}) => ScenarioLabSupplementalArtifactProvenance(
  artifactDigest: artifactDigest,
  size: size,
  mediaType: ScenarioLabSupplementalArtifactMediaType.png,
  classification: ArtifactClassification.internal,
  sourceId: ScenarioLabSupplementalArtifactSourceId(id),
  importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
    'fixture-policy',
  ),
);

ScenarioQualityReviewResourceBinding _binding(
  ScenarioQualityReviewArtifactDescriptor descriptor,
  int index,
) => ScenarioQualityReviewResourceBinding(
  artifactDescriptorDigest: descriptor.digest,
  artifact: ResourceHandle(
    uri: Uri.parse('http://127.0.0.1:7367/resources/${'c' * 31}${index + 1}'),
    digest: descriptor.artifactDigest,
    mediaType: descriptor.mediaType,
    size: descriptor.size,
    purpose: 'scenario-quality-review-artifact',
    expiresAt: DateTime.utc(2030),
  ),
  provenance: ResourceHandle(
    uri: Uri.parse('http://127.0.0.1:7367/resources/${'d' * 31}${index + 1}'),
    digest: descriptor.provenanceDigest,
    mediaType: 'application/json',
    size: 1024,
    purpose: 'scenario-quality-review-provenance',
    expiresAt: DateTime.utc(2030),
  ),
);
