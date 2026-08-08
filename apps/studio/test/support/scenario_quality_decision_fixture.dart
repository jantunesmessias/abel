import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/quality/studio_scenario_quality_transport.dart';

import 'scenario_lab_fixture.dart';

final class ScenarioQualityDecisionTestFixture {
  ScenarioQualityDecisionTestFixture({String captureSessionId = 'run-terminal'})
    : lab = ScenarioLabTestFixture() {
    final requiredReceipt = _receipt(
      'required',
      digest('review-required-artifact'),
      128,
      sessionId: captureSessionId,
    );
    final baselineProvenance = ScenarioLabSupplementalArtifactProvenance(
      artifactDigest: digest('review-baseline-artifact'),
      size: 96,
      mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      classification: ArtifactClassification.internal,
      sourceId: ScenarioLabSupplementalArtifactSourceId('baseline-source'),
      importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
        'fixture-policy',
      ),
    );
    result = lab.result(
      evidenceArtifactDigest: requiredReceipt.artifactDigest,
      evidenceProvenanceDigest: requiredReceipt.digest,
      comparisonBaselineDigest: baselineProvenance.artifactDigest,
    );
    quality = lab.quality(result);
    descriptor = descriptorFor(
      quality,
      requiredReceipt: requiredReceipt,
      baselineProvenance: baselineProvenance,
    );
    provenanceByDescriptor = <Digest, Object>{
      descriptor.artifacts[0].digest: requiredReceipt,
      descriptor.artifacts[1].digest: baselineProvenance,
      descriptor.artifacts[2].digest: requiredReceipt,
    };
  }

  final ScenarioLabTestFixture lab;
  late final ScenarioLabRunResult result;
  late final ScenarioQualitySnapshot quality;
  late final ScenarioQualityReviewDescriptor descriptor;
  late final Map<Digest, Object> provenanceByDescriptor;

  ScenarioQualityReviewDescriptor descriptorFor(
    ScenarioQualitySnapshot currentQuality, {
    AppAdapterCaptureReceipt? requiredReceipt,
    ScenarioLabSupplementalArtifactProvenance? baselineProvenance,
  }) {
    final required =
        requiredReceipt ??
        provenanceByDescriptor[descriptor.artifacts[0].digest]!
            as AppAdapterCaptureReceipt;
    final baseline =
        baselineProvenance ??
        provenanceByDescriptor[descriptor.artifacts[1].digest]!
            as ScenarioLabSupplementalArtifactProvenance;
    final evidenceResult = result.finalSnapshot.requiredEvidence.single;
    final comparison = result.finalSnapshot.comparisons.single;
    return ScenarioQualityReviewDescriptor(
      runId: result.finalSnapshot.runId,
      runResultDigest: result.digest,
      qualityDigest: currentQuality.digest,
      requirementId: HumanApprovalRequirementId('approval'),
      requirementScope: HumanApprovalScope.evidenceSet,
      reviewGuideId: ReviewGuideId('review-guide'),
      reviewGuideStepId: 'inspect-all',
      requiredEvidenceResultDigests: <Digest>[evidenceResult.digest],
      comparisonResultDigests: <Digest>[comparison.digest],
      artifacts: <ScenarioQualityReviewArtifactDescriptor>[
        ScenarioQualityReviewArtifactDescriptor(
          requiredEvidenceId: evidenceResult.requiredEvidenceId,
          requiredEvidenceResultDigest: evidenceResult.digest,
          role: ScenarioQualityReviewArtifactRole.requiredEvidence,
          artifactDigest: required.artifactDigest,
          provenanceDigest: required.digest,
          provenanceKind:
              ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
          classification: ArtifactClassification.internal,
          mediaType: 'image/png',
          size: required.size,
        ),
        ScenarioQualityReviewArtifactDescriptor(
          requiredEvidenceId: evidenceResult.requiredEvidenceId,
          requiredEvidenceResultDigest: evidenceResult.digest,
          role: ScenarioQualityReviewArtifactRole.comparisonBaseline,
          artifactDigest: baseline.artifactDigest,
          provenanceDigest: baseline.digest,
          provenanceKind:
              ScenarioQualityReviewProvenanceKind.supplementalArtifactImport,
          classification: baseline.classification,
          mediaType: baseline.mediaType.value,
          size: baseline.size,
          comparisonResultDigest: comparison.digest,
        ),
        ScenarioQualityReviewArtifactDescriptor(
          requiredEvidenceId: evidenceResult.requiredEvidenceId,
          requiredEvidenceResultDigest: evidenceResult.digest,
          role: ScenarioQualityReviewArtifactRole.comparisonCandidate,
          artifactDigest: required.artifactDigest,
          provenanceDigest: required.digest,
          provenanceKind:
              ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
          classification: ArtifactClassification.internal,
          mediaType: 'image/png',
          size: required.size,
          comparisonResultDigest: comparison.digest,
        ),
      ],
    );
  }

  ScenarioQualityDescribeResult describe({
    ScenarioQualitySnapshot? currentQuality,
    ScenarioQualityReviewAvailability availability =
        ScenarioQualityReviewAvailability.available,
    Digest? head,
    int decisionCount = 0,
  }) {
    final selectedQuality = currentQuality ?? quality;
    final selectedDescriptor =
        availability == ScenarioQualityReviewAvailability.available
        ? descriptorFor(selectedQuality)
        : null;
    return ScenarioQualityDescribeResult(
      description: ScenarioQualityDescription(
        runId: result.finalSnapshot.runId,
        runResultDigest: result.digest,
        quality: selectedQuality,
        availability: availability,
        requirementId:
            availability == ScenarioQualityReviewAvailability.available
            ? HumanApprovalRequirementId('approval')
            : null,
        headDecisionDigest: head,
        decisionCount: decisionCount,
      ),
      reviewDescriptor: selectedDescriptor,
    );
  }

  ScenarioQualityReviewOpenResult open(
    ScenarioQualityReviewDescriptor selectedDescriptor,
  ) => ScenarioQualityReviewOpenResult(
    reviewDescriptor: selectedDescriptor,
    resources: <ScenarioQualityReviewResourceBinding>[
      for (var index = 0; index < selectedDescriptor.artifacts.length; index++)
        _binding(selectedDescriptor.artifacts[index], index),
    ],
  );

  Object provenanceFor(ScenarioQualityReviewArtifactDescriptor artifact) {
    for (final value in provenanceByDescriptor.values) {
      if (switch (value) {
        final AppAdapterCaptureReceipt receipt =>
          receipt.digest == artifact.provenanceDigest,
        final ScenarioLabSupplementalArtifactProvenance provenance =>
          provenance.digest == artifact.provenanceDigest,
        _ => false,
      }) {
        return value;
      }
    }
    throw StateError('Fixture provenance is absent');
  }

  ScenarioQualitySnapshot reviewedQuality(HumanDecisionRecord record) =>
      ScenarioQualitySnapshot(
        subjectDigest: quality.subjectDigest,
        runId: quality.runId,
        scenarioId: quality.scenarioId,
        verificationState: quality.verificationState,
        humanDecision: HumanDecisionProjection(
          state: record.decision == HumanDecision.approved
              ? HumanDecisionState.approved
              : HumanDecisionState.rejected,
          decisionDigest: record.digest,
        ),
        requiredEvidence: quality.requiredEvidence,
        comparisonResultDigests: quality.comparisonResultDigests,
      );

  StudioWorkspaceContent content(WorkspaceSnapshot snapshot) =>
      StudioWorkspaceContent(
        snapshot: snapshot,
        scenarioLab: lab.manifest,
        identity: ExperienceContentSetIdentity(
          revision: 1,
          catalogDigest: snapshot.catalog.digest,
          workspaceSnapshotDigest: snapshot.digest,
          workspaceContentDigest: snapshot.workspaceContentDigest,
          scenarioLabManifestDigest: lab.manifest.digest,
        ),
      );
}

AppAdapterCaptureReceipt _receipt(
  String id,
  Digest artifactDigest,
  int size, {
  required String sessionId,
}) => AppAdapterCaptureReceipt(
  requestId: '${id}_capture',
  sessionId: sessionId,
  artifactDigest: artifactDigest,
  pixelDigest: digest('$id-pixels'),
  size: size,
  width: 8,
  height: 4,
  completedAt: time(8),
);

ScenarioQualityReviewResourceBinding _binding(
  ScenarioQualityReviewArtifactDescriptor descriptor,
  int index,
) => ScenarioQualityReviewResourceBinding(
  artifactDescriptorDigest: descriptor.digest,
  artifact: ResourceHandle(
    uri: Uri.parse('http://127.0.0.1:7367/resources/${'a' * 31}${index + 1}'),
    digest: descriptor.artifactDigest,
    mediaType: descriptor.mediaType,
    size: descriptor.size,
    purpose: 'scenario-quality-review-artifact',
    expiresAt: DateTime.utc(2030),
  ),
  provenance: ResourceHandle(
    uri: Uri.parse('http://127.0.0.1:7367/resources/${'b' * 31}${index + 1}'),
    digest: descriptor.provenanceDigest,
    mediaType: 'application/json',
    size: 1024,
    purpose: 'scenario-quality-review-provenance',
    expiresAt: DateTime.utc(2030),
  ),
);

final class FakeScenarioQualityHost
    implements
        StudioHostScenarioQualityClient,
        StudioHostScenarioQualityResourceClient {
  FakeScenarioQualityHost(
    this.fixture, {
    this.availability = ScenarioQualityReviewAvailability.available,
  });

  final ScenarioQualityDecisionTestFixture fixture;
  ScenarioQualityReviewAvailability availability;
  ScenarioQualityDecisionFailureFactory? failureFactory;
  Future<ScenarioQualityDescribeResult> Function(
    ScenarioQualityDescribeRequest request,
  )?
  describeOverride;
  Object? provenanceOverride;
  ScenarioQualityDecisionAppendResult Function(
    ScenarioQualityDecisionAppendResult result,
  )?
  appendResultTransform;
  ScenarioQualityDecisionView Function(ScenarioQualityDecisionView view)?
  getViewTransform;
  bool rejectImages = false;
  final List<ScenarioQualityDescribeRequest> describeRequests =
      <ScenarioQualityDescribeRequest>[];
  final List<ScenarioQualityReviewOpenRequest> openRequests =
      <ScenarioQualityReviewOpenRequest>[];
  final List<ScenarioQualityDecisionGrantRequest> grantRequests =
      <ScenarioQualityDecisionGrantRequest>[];
  final List<ScenarioQualityDecisionAppendRequest> appendRequests =
      <ScenarioQualityDecisionAppendRequest>[];
  final List<ScenarioQualityDecisionGetRequest> getRequests =
      <ScenarioQualityDecisionGetRequest>[];
  final List<_StoredDecision> _decisions = <_StoredDecision>[];
  final Map<ScenarioQualityDecisionGrantId, _IssuedGrant> _grants =
      <ScenarioQualityDecisionGrantId, _IssuedGrant>{};
  ScenarioQualitySnapshot? _currentQuality;
  int imageOpenCalls = 0;
  int provenanceReadCalls = 0;
  int artifactValidationCalls = 0;
  int releasedLeases = 0;

  ScenarioQualitySnapshot get currentQuality =>
      _currentQuality ?? fixture.quality;

  Digest? get head => _decisions.lastOrNull?.record.digest;

  @override
  Future<ScenarioQualityDescribeResult> describeScenarioQuality(
    ScenarioQualityDescribeRequest request,
  ) async {
    describeRequests.add(request);
    _maybeFail(ScenarioQualityDecisionOperation.describe, requestId: null);
    final override = describeOverride;
    if (override != null) return override(request);
    return fixture.describe(
      currentQuality: currentQuality,
      availability: availability,
      head: head,
      decisionCount: _decisions.length,
    );
  }

  @override
  Future<ScenarioQualityReviewOpenResult> openScenarioQualityReview(
    ScenarioQualityReviewOpenRequest request,
  ) async {
    openRequests.add(request);
    _maybeFail(ScenarioQualityDecisionOperation.open, requestId: null);
    return fixture.open(fixture.descriptorFor(currentQuality));
  }

  @override
  Future<ScenarioQualityDecisionGrant> grantScenarioQualityDecision(
    ScenarioQualityDecisionGrantRequest request,
  ) async {
    grantRequests.add(request);
    _maybeFail(
      ScenarioQualityDecisionOperation.grant,
      requestId: request.requestId,
    );
    final descriptor = fixture.descriptorFor(currentQuality);
    final issuedAt = DateTime.utc(2026, 8, 14, 12, 20 + _decisions.length);
    final grant = ScenarioQualityDecisionGrant(
      id: ScenarioQualityDecisionGrantId(
        'grant-${grantRequests.length.toString().padLeft(4, '0')}',
      ),
      requestId: request.requestId,
      requestDigest: request.digest,
      authorityId: ScenarioQualityAuthorityId('fixture-authority'),
      accessPolicyId: ScenarioQualityAccessPolicyId('fixture-policy'),
      principalId: ScenarioQualityPrincipalId('fixture-reviewer'),
      role: ScenarioQualityDecisionRole.reviewer,
      runId: request.runId,
      runResultDigest: request.expectedRunResultDigest,
      qualityDigest: request.expectedQualityDigest,
      reviewDescriptorDigest: request.expectedReviewDescriptorDigest,
      requirementId: descriptor.requirementId,
      requirementScope: descriptor.requirementScope,
      reviewGuideId: descriptor.reviewGuideId,
      reviewGuideStepId: descriptor.reviewGuideStepId,
      expectedPreviousDecisionDigest: request.expectedPreviousDecisionDigest,
      decision: request.decision,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(minutes: 2)),
    );
    _grants[grant.id] = _IssuedGrant(
      grant: grant,
      request: request,
      descriptor: descriptor,
    );
    return grant;
  }

  @override
  Future<ScenarioQualityDecisionAppendResult> appendScenarioQualityDecision(
    ScenarioQualityDecisionAppendRequest request,
  ) async {
    appendRequests.add(request);
    _maybeFail(
      ScenarioQualityDecisionOperation.append,
      requestId: request.requestId,
    );
    final issued = _grants[request.grantId]!;
    final record = HumanDecisionRecord(
      id: HumanDecisionRecordId(
        'decision-${(1 + _decisions.length).toString().padLeft(4, '0')}',
      ),
      subjectDigest: fixture.result.digest,
      principalId: issued.grant.principalId,
      decision: request.decision,
      decidedAt: DateTime.utc(2026, 8, 14, 12, 30 + _decisions.length),
      supersedesDecisionDigest: request.expectedPreviousDecisionDigest,
    );
    final attribution = ScenarioQualityDecisionAttribution(
      runId: request.runId,
      runResultDigest: request.expectedRunResultDigest,
      reviewDescriptorDigest: issued.descriptor.digest,
      requirementId: issued.grant.requirementId,
      requirementScope: issued.grant.requirementScope,
      reviewGuideId: issued.grant.reviewGuideId,
      reviewGuideStepId: issued.grant.reviewGuideStepId,
      authorityId: issued.grant.authorityId,
      accessPolicyId: issued.grant.accessPolicyId,
      principalId: issued.grant.principalId,
      role: issued.grant.role,
      grantDigest: issued.grant.digest,
      grantRequestDigest: issued.request.digest,
      decisionRequestDigest: request.digest,
    );
    final reviewed = fixture.reviewedQuality(record);
    _currentQuality = reviewed;
    _decisions.add(
      _StoredDecision(
        record: record,
        attribution: attribution,
        descriptor: issued.descriptor,
      ),
    );
    final result = ScenarioQualityDecisionAppendResult(
      requestId: request.requestId,
      requestDigest: request.digest,
      attribution: attribution,
      record: record,
      quality: reviewed,
    );
    return appendResultTransform?.call(result) ?? result;
  }

  @override
  Future<ScenarioQualityDecisionView> getScenarioQualityDecision(
    ScenarioQualityDecisionGetRequest request,
  ) async {
    getRequests.add(request);
    _maybeFail(ScenarioQualityDecisionOperation.get, requestId: null);
    final index = _decisions.indexWhere(
      (item) => item.record.digest == request.decisionDigest,
    );
    final stored = _decisions[index];
    final newer = index + 1 < _decisions.length ? _decisions[index + 1] : null;
    final view = ScenarioQualityDecisionView(
      record: stored.record,
      projection: newer == null
          ? HumanDecisionProjection(
              state: stored.record.decision == HumanDecision.approved
                  ? HumanDecisionState.approved
                  : HumanDecisionState.rejected,
              decisionDigest: stored.record.digest,
            )
          : HumanDecisionProjection(
              state: HumanDecisionState.superseded,
              decisionDigest: stored.record.digest,
              supersededByDecisionDigest: newer.record.digest,
            ),
      attribution: stored.attribution,
      reviewDescriptor: stored.descriptor,
    );
    return getViewTransform?.call(view) ?? view;
  }

  @override
  Future<Object> readScenarioQualityReviewProvenance({
    required ResourceHandle handle,
    required ScenarioQualityReviewProvenanceKind kind,
    required Digest expectedDigest,
  }) async {
    provenanceReadCalls += 1;
    final override = provenanceOverride;
    if (override != null) return override;
    final descriptor = fixture.descriptor.artifacts.firstWhere(
      (item) => item.provenanceDigest == expectedDigest,
    );
    return fixture.provenanceFor(descriptor);
  }

  @override
  Future<StudioResourceLease> openScenarioQualityReviewImage({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  }) async {
    imageOpenCalls += 1;
    if (rejectImages) {
      throw const FormatException('Fixture image tamper');
    }
    return StudioResourceLease(
      uri: Uri.parse('blob:fixture-$imageOpenCalls'),
      digest: descriptor.artifactDigest,
      mediaType: descriptor.mediaType,
      size: descriptor.size,
      releaseCallback: () => releasedLeases += 1,
    );
  }

  @override
  Future<void> validateScenarioQualityReviewArtifact({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  }) async {
    artifactValidationCalls += 1;
  }

  void _maybeFail(
    ScenarioQualityDecisionOperation operation, {
    required ScenarioQualityDecisionRequestId? requestId,
  }) {
    final failure = failureFactory?.call(operation, requestId);
    if (failure != null) throw StudioScenarioQualityDecisionFailure(failure);
  }
}

typedef ScenarioQualityDecisionFailureFactory =
    ScenarioQualityDecisionError? Function(
      ScenarioQualityDecisionOperation operation,
      ScenarioQualityDecisionRequestId? requestId,
    );

final class _IssuedGrant {
  const _IssuedGrant({
    required this.grant,
    required this.request,
    required this.descriptor,
  });

  final ScenarioQualityDecisionGrant grant;
  final ScenarioQualityDecisionGrantRequest request;
  final ScenarioQualityReviewDescriptor descriptor;
}

final class _StoredDecision {
  const _StoredDecision({
    required this.record,
    required this.attribution,
    required this.descriptor,
  });

  final HumanDecisionRecord record;
  final ScenarioQualityDecisionAttribution attribution;
  final ScenarioQualityReviewDescriptor descriptor;
}
