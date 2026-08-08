import 'dart:convert';

import 'package:execution_runtime/src/host/host_rpc_server.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('worst-case Host results for all five Quality RPCs fit a frame', () {
    const maxFrameBytes = 64 * 1024;
    final fixture = _frameFixture();
    final results = <String, Object?>{
      'quality.describe': fixture.describe.toJson(),
      'quality.open': fixture.open.toJson(),
      'quality.decision.grant': fixture.grant.toJson(),
      'quality.decision.append': fixture.append.toJson(),
      'quality.decision.get': fixture.view.toJson(),
    };

    for (final entry in results.entries) {
      final encoded = JsonRpcResponse.success(
        id: 'x' * HostRpcServer.maxStringRequestIdLength,
        result: entry.value,
      ).encode();
      final encodedBytes = utf8.encode(encoded).length;
      expect(
        HostRpcServer.successPayloadFits(
          entry.value,
          maxMessageBytes: maxFrameBytes,
        ),
        isTrue,
        reason: '${entry.key} uses $encodedBytes bytes',
      );
      expect(encodedBytes, lessThanOrEqualTo(maxFrameBytes), reason: entry.key);
    }
  });
}

final class _FrameFixture {
  const _FrameFixture({
    required this.describe,
    required this.open,
    required this.grant,
    required this.append,
    required this.view,
  });

  final ScenarioQualityDescribeResult describe;
  final ScenarioQualityReviewOpenResult open;
  final ScenarioQualityDecisionGrant grant;
  final ScenarioQualityDecisionAppendResult append;
  final ScenarioQualityDecisionView view;
}

_FrameFixture _frameFixture() {
  final runId = ScenarioLabRunId(_maxId('run'));
  final runResultDigest = _digest('run-result');
  final requirementId = HumanApprovalRequirementId(_maxId('requirement'));
  final evidence = List<RequiredEvidenceVerification>.generate(32, (index) {
    return RequiredEvidenceVerification(
      requiredEvidenceId: RequiredEvidenceId(_maxId('evidence', index)),
      resultDigest: _digest('evidence-result-$index'),
      verificationState: VerificationState.passed,
    );
  });
  final previous = HumanDecisionRecord(
    id: HumanDecisionRecordId(_maxId('previous-decision')),
    subjectDigest: runResultDigest,
    principalId: ScenarioQualityPrincipalId(_maxId('principal')),
    decision: HumanDecision.approved,
    decidedAt: DateTime.utc(2026, 8, 14, 11, 59),
  );
  final quality = ScenarioQualitySnapshot(
    subjectDigest: runResultDigest,
    runId: runId,
    scenarioId: ScenarioId(_maxId('scenario')),
    verificationState: VerificationState.passed,
    humanDecision: HumanDecisionProjection(
      state: HumanDecisionState.approved,
      decisionDigest: previous.digest,
    ),
    requiredEvidence: evidence,
  );
  const mediaType = 'image/png';
  final artifacts = <ScenarioQualityReviewArtifactDescriptor>[
    for (var index = 0; index < evidence.length; index++)
      ScenarioQualityReviewArtifactDescriptor(
        requiredEvidenceId: evidence[index].requiredEvidenceId,
        requiredEvidenceResultDigest: evidence[index].resultDigest,
        role: ScenarioQualityReviewArtifactRole.requiredEvidence,
        artifactDigest: _digest('artifact-$index'),
        provenanceDigest: _digest('provenance-$index'),
        provenanceKind:
            ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
        classification: ArtifactClassification.internal,
        mediaType: mediaType,
        size: 32 * 1024 * 1024,
      ),
  ];
  final descriptor = ScenarioQualityReviewDescriptor(
    runId: runId,
    runResultDigest: runResultDigest,
    qualityDigest: quality.digest,
    requirementId: requirementId,
    requirementScope: HumanApprovalScope.evidenceSet,
    reviewGuideId: ReviewGuideId(_maxId('review-guide')),
    reviewGuideStepId: _maxId('review-step'),
    requiredEvidenceResultDigests: evidence.map((item) => item.resultDigest),
    comparisonResultDigests: const <Digest>[],
    artifacts: artifacts,
  );
  final description = ScenarioQualityDescription(
    runId: runId,
    runResultDigest: runResultDigest,
    quality: quality,
    availability: ScenarioQualityReviewAvailability.available,
    requirementId: requirementId,
    headDecisionDigest: previous.digest,
    decisionCount: 100,
  );
  final describe = ScenarioQualityDescribeResult(
    description: description,
    reviewDescriptor: descriptor,
  );
  final expiresAt = DateTime.utc(2026, 8, 14, 12, 5);
  final open = ScenarioQualityReviewOpenResult(
    reviewDescriptor: descriptor,
    resources: <ScenarioQualityReviewResourceBinding>[
      for (var index = 0; index < artifacts.length; index++)
        ScenarioQualityReviewResourceBinding(
          artifactDescriptorDigest: artifacts[index].digest,
          artifact: ResourceHandle(
            uri: _resourceUri(index * 2),
            digest: artifacts[index].artifactDigest,
            mediaType: artifacts[index].mediaType,
            size: artifacts[index].size,
            purpose: 'scenario-quality-review-artifact',
            expiresAt: expiresAt,
          ),
          provenance: ResourceHandle(
            uri: _resourceUri((index * 2) + 1),
            digest: artifacts[index].provenanceDigest,
            mediaType: 'application/json',
            size: 1024 * 1024,
            purpose: 'scenario-quality-review-provenance',
            expiresAt: expiresAt,
          ),
        ),
    ],
  );
  final grantRequestDigest = _digest('grant-request');
  final grant = ScenarioQualityDecisionGrant(
    id: ScenarioQualityDecisionGrantId(_maxId('grant')),
    requestId: ScenarioQualityDecisionRequestId(_maxId('grant-request')),
    requestDigest: grantRequestDigest,
    authorityId: ScenarioQualityAuthorityId(_maxId('authority')),
    accessPolicyId: ScenarioQualityAccessPolicyId(_maxId('access-policy')),
    principalId: previous.principalId,
    role: ScenarioQualityDecisionRole.reviewer,
    runId: runId,
    runResultDigest: runResultDigest,
    qualityDigest: quality.digest,
    reviewDescriptorDigest: descriptor.digest,
    requirementId: requirementId,
    requirementScope: HumanApprovalScope.evidenceSet,
    reviewGuideId: descriptor.reviewGuideId,
    reviewGuideStepId: descriptor.reviewGuideStepId,
    expectedPreviousDecisionDigest: previous.digest,
    decision: HumanDecision.rejected,
    issuedAt: DateTime.utc(2026, 8, 14, 12),
    expiresAt: DateTime.utc(2026, 8, 14, 12, 5),
  );
  final decisionRequestDigest = _digest('decision-request');
  final record = HumanDecisionRecord(
    id: HumanDecisionRecordId(_maxId('decision')),
    subjectDigest: runResultDigest,
    principalId: grant.principalId,
    decision: HumanDecision.rejected,
    decidedAt: DateTime.utc(2026, 8, 14, 12, 1),
    supersedesDecisionDigest: previous.digest,
  );
  final attribution = ScenarioQualityDecisionAttribution(
    runId: runId,
    runResultDigest: runResultDigest,
    reviewDescriptorDigest: descriptor.digest,
    requirementId: requirementId,
    requirementScope: HumanApprovalScope.evidenceSet,
    reviewGuideId: descriptor.reviewGuideId,
    reviewGuideStepId: descriptor.reviewGuideStepId,
    authorityId: grant.authorityId,
    accessPolicyId: grant.accessPolicyId,
    principalId: grant.principalId,
    role: ScenarioQualityDecisionRole.reviewer,
    grantDigest: grant.digest,
    grantRequestDigest: grantRequestDigest,
    decisionRequestDigest: decisionRequestDigest,
  );
  final decidedQuality = ScenarioQualitySnapshot(
    subjectDigest: runResultDigest,
    runId: runId,
    scenarioId: quality.scenarioId,
    verificationState: quality.verificationState,
    humanDecision: HumanDecisionProjection(
      state: HumanDecisionState.rejected,
      decisionDigest: record.digest,
    ),
    requiredEvidence: quality.requiredEvidence,
  );
  final append = ScenarioQualityDecisionAppendResult(
    requestId: ScenarioQualityDecisionRequestId(_maxId('append-request')),
    requestDigest: decisionRequestDigest,
    attribution: attribution,
    record: record,
    quality: decidedQuality,
  );
  final view = ScenarioQualityDecisionView(
    record: record,
    projection: HumanDecisionProjection(
      state: HumanDecisionState.rejected,
      decisionDigest: record.digest,
    ),
    attribution: attribution,
    reviewDescriptor: descriptor,
  );
  return _FrameFixture(
    describe: describe,
    open: open,
    grant: grant,
    append: append,
    view: view,
  );
}

String _maxId(String prefix, [int? index]) {
  final stem = index == null ? '$prefix-' : '$prefix-$index-';
  return '$stem${'x' * (256 - stem.length)}';
}

Uri _resourceUri(int index) {
  final suffix = index.toRadixString(36);
  final token = '${'a' * (32 - suffix.length)}$suffix';
  return Uri.parse('http://127.0.0.1:65535/resources/$token');
}

Digest _digest(String seed) => Digest.semantic(seed);
