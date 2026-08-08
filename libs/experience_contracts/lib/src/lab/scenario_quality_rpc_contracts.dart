import '../catalog/catalog_contracts.dart';
import '../catalog/scenario_lab_contracts.dart';
import '../digest.dart';
import '../evidence/evidence_contracts.dart';
import '../studio/studio_workspace_contracts.dart';
import 'scenario_lab_execution_contracts.dart';

final class ScenarioQualityDecisionRequestId extends OpaqueId {
  factory ScenarioQualityDecisionRequestId(String value) {
    _qualityRpcId(value, 'ScenarioQualityDecisionRequest');
    return ScenarioQualityDecisionRequestId._(value);
  }

  const ScenarioQualityDecisionRequestId._(super.value);
}

final class ScenarioQualityDecisionGrantId extends OpaqueId {
  factory ScenarioQualityDecisionGrantId(String value) {
    _qualityRpcId(value, 'ScenarioQualityDecisionGrant');
    return ScenarioQualityDecisionGrantId._(value);
  }

  const ScenarioQualityDecisionGrantId._(super.value);
}

final class ScenarioQualityAuthorityId extends OpaqueId {
  factory ScenarioQualityAuthorityId(String value) {
    _qualityRpcId(value, 'ScenarioQualityAuthority');
    return ScenarioQualityAuthorityId._(value);
  }

  const ScenarioQualityAuthorityId._(super.value);
}

final class ScenarioQualityAccessPolicyId extends OpaqueId {
  factory ScenarioQualityAccessPolicyId(String value) {
    _qualityRpcId(value, 'ScenarioQualityAccessPolicy');
    return ScenarioQualityAccessPolicyId._(value);
  }

  const ScenarioQualityAccessPolicyId._(super.value);
}

enum ScenarioQualityDecisionRole { reviewer, observer }

enum ScenarioQualityReviewAvailability {
  available,
  unavailable,
  unsupported,
  policyDenied,
}

enum ScenarioQualityDecisionOperation { describe, open, grant, append, get }

enum ScenarioQualityDecisionErrorCode {
  unavailable,
  policyDenied,
  requestConflict,
  staleQuality,
  stalePreviousDecision,
  grantMismatch,
  grantExpired,
  grantRevoked,
  grantConsumed,
  decisionDenied,
  unsupported,
  quotaExceeded,
  notFound,
  runNotTerminal,
  subjectMismatch,
}

/// Short-lived, Host-issued mutation authority.
///
/// Append accepts only this document's ID and digest. Principal, role, policy
/// and fences remain Host-authored output rather than caller-selected input.
final class ScenarioQualityDecisionGrant {
  ScenarioQualityDecisionGrant({
    required this.id,
    required this.requestId,
    required this.requestDigest,
    required this.authorityId,
    required this.accessPolicyId,
    required this.principalId,
    required this.role,
    required this.runId,
    required this.runResultDigest,
    required this.qualityDigest,
    required this.reviewDescriptorDigest,
    required this.requirementId,
    required this.requirementScope,
    required this.reviewGuideId,
    required this.reviewGuideStepId,
    required this.expectedPreviousDecisionDigest,
    required this.decision,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) : issuedAt = issuedAt.toUtc(),
       expiresAt = expiresAt.toUtc() {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
    _qualityRpcId(requirementId.value, 'HumanApprovalRequirement');
    _qualityRpcId(reviewGuideId.value, 'ReviewGuide');
    _qualityRpcId(reviewGuideStepId, 'ReviewGuideStep');
    if (role != ScenarioQualityDecisionRole.reviewer ||
        requirementScope != HumanApprovalScope.evidenceSet ||
        !this.expiresAt.isAfter(this.issuedAt) ||
        this.expiresAt.difference(this.issuedAt) > const Duration(minutes: 5)) {
      throw ArgumentError('Scenario Quality decision grant is invalid');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioQualityDecisionGrantId id;
  final ScenarioQualityDecisionRequestId requestId;
  final Digest requestDigest;
  final ScenarioQualityAuthorityId authorityId;
  final ScenarioQualityAccessPolicyId accessPolicyId;
  final ScenarioQualityPrincipalId principalId;
  final ScenarioQualityDecisionRole role;
  final ScenarioLabRunId runId;
  final Digest runResultDigest;
  final Digest qualityDigest;
  final Digest reviewDescriptorDigest;
  final HumanApprovalRequirementId requirementId;
  final HumanApprovalScope requirementScope;
  final ReviewGuideId reviewGuideId;
  final String reviewGuideStepId;
  final Digest? expectedPreviousDecisionDigest;
  final HumanDecision decision;
  final DateTime issuedAt;
  final DateTime expiresAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDecisionGrant',
    'id': id.value,
    'requestId': requestId.value,
    'requestDigest': requestDigest.value,
    'authorityId': authorityId.value,
    'accessPolicyId': accessPolicyId.value,
    'principalId': principalId.value,
    'role': role.name,
    'runId': runId.value,
    'runResultDigest': runResultDigest.value,
    'qualityDigest': qualityDigest.value,
    'reviewDescriptorDigest': reviewDescriptorDigest.value,
    'requirementId': requirementId.value,
    'requirementScope': requirementScope.name,
    'reviewGuideId': reviewGuideId.value,
    'reviewGuideStepId': reviewGuideStepId,
    if (expectedPreviousDecisionDigest != null)
      'expectedPreviousDecisionDigest': expectedPreviousDecisionDigest!.value,
    'decision': decision.name,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionGrant.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDecisionGrant',
      const <String>{
        'id',
        'requestId',
        'requestDigest',
        'authorityId',
        'accessPolicyId',
        'principalId',
        'role',
        'runId',
        'runResultDigest',
        'qualityDigest',
        'reviewDescriptorDigest',
        'requirementId',
        'requirementScope',
        'reviewGuideId',
        'reviewGuideStepId',
        'decision',
        'issuedAt',
        'expiresAt',
      },
      optional: const <String>{'expectedPreviousDecisionDigest'},
    );
    final grant = ScenarioQualityDecisionGrant(
      id: ScenarioQualityDecisionGrantId(
        _qualityRpcString(json, 'id', 'ScenarioQualityDecisionGrant'),
      ),
      requestId: ScenarioQualityDecisionRequestId(
        _qualityRpcString(json, 'requestId', 'ScenarioQualityDecisionGrant'),
      ),
      requestDigest: Digest(
        _qualityRpcString(
          json,
          'requestDigest',
          'ScenarioQualityDecisionGrant',
        ),
      ),
      authorityId: ScenarioQualityAuthorityId(
        _qualityRpcString(json, 'authorityId', 'ScenarioQualityDecisionGrant'),
      ),
      accessPolicyId: ScenarioQualityAccessPolicyId(
        _qualityRpcString(
          json,
          'accessPolicyId',
          'ScenarioQualityDecisionGrant',
        ),
      ),
      principalId: ScenarioQualityPrincipalId(
        _qualityRpcString(json, 'principalId', 'ScenarioQualityDecisionGrant'),
      ),
      role: _qualityRpcEnum(
        ScenarioQualityDecisionRole.values,
        _qualityRpcString(json, 'role', 'ScenarioQualityDecisionGrant'),
        'ScenarioQualityDecisionGrant.role',
      ),
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityDecisionGrant'),
      ),
      runResultDigest: Digest(
        _qualityRpcString(
          json,
          'runResultDigest',
          'ScenarioQualityDecisionGrant',
        ),
      ),
      qualityDigest: Digest(
        _qualityRpcString(
          json,
          'qualityDigest',
          'ScenarioQualityDecisionGrant',
        ),
      ),
      reviewDescriptorDigest: Digest(
        _qualityRpcString(
          json,
          'reviewDescriptorDigest',
          'ScenarioQualityDecisionGrant',
        ),
      ),
      requirementId: HumanApprovalRequirementId(
        _qualityRpcString(
          json,
          'requirementId',
          'ScenarioQualityDecisionGrant',
        ),
      ),
      requirementScope: _qualityRpcEnum(
        HumanApprovalScope.values,
        _qualityRpcString(
          json,
          'requirementScope',
          'ScenarioQualityDecisionGrant',
        ),
        'ScenarioQualityDecisionGrant.requirementScope',
      ),
      reviewGuideId: ReviewGuideId(
        _qualityRpcString(
          json,
          'reviewGuideId',
          'ScenarioQualityDecisionGrant',
        ),
      ),
      reviewGuideStepId: _qualityRpcString(
        json,
        'reviewGuideStepId',
        'ScenarioQualityDecisionGrant',
      ),
      expectedPreviousDecisionDigest:
          json.containsKey('expectedPreviousDecisionDigest')
          ? Digest(
              _qualityRpcString(
                json,
                'expectedPreviousDecisionDigest',
                'ScenarioQualityDecisionGrant',
              ),
            )
          : null,
      decision: _qualityRpcEnum(
        HumanDecision.values,
        _qualityRpcString(json, 'decision', 'ScenarioQualityDecisionGrant'),
        'ScenarioQualityDecisionGrant.decision',
      ),
      issuedAt: _qualityRpcTime(
        json,
        'issuedAt',
        'ScenarioQualityDecisionGrant',
      ),
      expiresAt: _qualityRpcTime(
        json,
        'expiresAt',
        'ScenarioQualityDecisionGrant',
      ),
    );
    _qualityRpcVerifyDigest(json, grant.digest, 'ScenarioQualityDecisionGrant');
    return grant;
  }
}

/// Durable attribution copied into every append result and historical view.
final class ScenarioQualityDecisionAttribution {
  ScenarioQualityDecisionAttribution({
    required this.runId,
    required this.runResultDigest,
    required this.reviewDescriptorDigest,
    required this.requirementId,
    required this.requirementScope,
    required this.reviewGuideId,
    required this.reviewGuideStepId,
    required this.authorityId,
    required this.accessPolicyId,
    required this.principalId,
    required this.role,
    required this.grantDigest,
    required this.grantRequestDigest,
    required this.decisionRequestDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
    _qualityRpcId(requirementId.value, 'HumanApprovalRequirement');
    _qualityRpcId(reviewGuideId.value, 'ReviewGuide');
    _qualityRpcId(reviewGuideStepId, 'ReviewGuideStep');
    if (role != ScenarioQualityDecisionRole.reviewer ||
        requirementScope != HumanApprovalScope.evidenceSet) {
      throw ArgumentError('Decision attribution requires a reviewer');
    }
  }

  final ScenarioLabRunId runId;
  final Digest runResultDigest;
  final Digest reviewDescriptorDigest;
  final HumanApprovalRequirementId requirementId;
  final HumanApprovalScope requirementScope;
  final ReviewGuideId reviewGuideId;
  final String reviewGuideStepId;
  final ScenarioQualityAuthorityId authorityId;
  final ScenarioQualityAccessPolicyId accessPolicyId;
  final ScenarioQualityPrincipalId principalId;
  final ScenarioQualityDecisionRole role;
  final Digest grantDigest;
  final Digest grantRequestDigest;
  final Digest decisionRequestDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'runId': runId.value,
    'runResultDigest': runResultDigest.value,
    'reviewDescriptorDigest': reviewDescriptorDigest.value,
    'requirementId': requirementId.value,
    'requirementScope': requirementScope.name,
    'reviewGuideId': reviewGuideId.value,
    'reviewGuideStepId': reviewGuideStepId,
    'authorityId': authorityId.value,
    'accessPolicyId': accessPolicyId.value,
    'principalId': principalId.value,
    'role': role.name,
    'grantDigest': grantDigest.value,
    'grantRequestDigest': grantRequestDigest.value,
    'decisionRequestDigest': decisionRequestDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionAttribution.fromJson(Object? value) {
    final json = _qualityRpcObject(
      value,
      'ScenarioQualityDecisionAttribution',
      const <String>{
        'runId',
        'runResultDigest',
        'reviewDescriptorDigest',
        'requirementId',
        'requirementScope',
        'reviewGuideId',
        'reviewGuideStepId',
        'authorityId',
        'accessPolicyId',
        'principalId',
        'role',
        'grantDigest',
        'grantRequestDigest',
        'decisionRequestDigest',
        'digest',
      },
    );
    final attribution = ScenarioQualityDecisionAttribution(
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityDecisionAttribution'),
      ),
      runResultDigest: Digest(
        _qualityRpcString(
          json,
          'runResultDigest',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      reviewDescriptorDigest: Digest(
        _qualityRpcString(
          json,
          'reviewDescriptorDigest',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      requirementId: HumanApprovalRequirementId(
        _qualityRpcString(
          json,
          'requirementId',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      requirementScope: _qualityRpcEnum(
        HumanApprovalScope.values,
        _qualityRpcString(
          json,
          'requirementScope',
          'ScenarioQualityDecisionAttribution',
        ),
        'ScenarioQualityDecisionAttribution.requirementScope',
      ),
      reviewGuideId: ReviewGuideId(
        _qualityRpcString(
          json,
          'reviewGuideId',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      reviewGuideStepId: _qualityRpcString(
        json,
        'reviewGuideStepId',
        'ScenarioQualityDecisionAttribution',
      ),
      authorityId: ScenarioQualityAuthorityId(
        _qualityRpcString(
          json,
          'authorityId',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      accessPolicyId: ScenarioQualityAccessPolicyId(
        _qualityRpcString(
          json,
          'accessPolicyId',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      principalId: ScenarioQualityPrincipalId(
        _qualityRpcString(
          json,
          'principalId',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      role: _qualityRpcEnum(
        ScenarioQualityDecisionRole.values,
        _qualityRpcString(json, 'role', 'ScenarioQualityDecisionAttribution'),
        'ScenarioQualityDecisionAttribution.role',
      ),
      grantDigest: Digest(
        _qualityRpcString(
          json,
          'grantDigest',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      grantRequestDigest: Digest(
        _qualityRpcString(
          json,
          'grantRequestDigest',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
      decisionRequestDigest: Digest(
        _qualityRpcString(
          json,
          'decisionRequestDigest',
          'ScenarioQualityDecisionAttribution',
        ),
      ),
    );
    _qualityRpcVerifyDigest(
      json,
      attribution.digest,
      'ScenarioQualityDecisionAttribution',
    );
    return attribution;
  }
}

/// Exact-result fence used to discover the Host-owned review authority.
final class ScenarioQualityDescribeRequest {
  ScenarioQualityDescribeRequest({
    required this.runId,
    required this.expectedRunResultDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest expectedRunResultDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDescribeRequest',
    'runId': runId.value,
    'expectedRunResultDigest': expectedRunResultDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDescribeRequest.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDescribeRequest',
      const <String>{'runId', 'expectedRunResultDigest'},
    );
    final request = ScenarioQualityDescribeRequest(
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityDescribeRequest'),
      ),
      expectedRunResultDigest: Digest(
        _qualityRpcString(
          json,
          'expectedRunResultDigest',
          'ScenarioQualityDescribeRequest',
        ),
      ),
    );
    _qualityRpcVerifyDigest(
      json,
      request.digest,
      'ScenarioQualityDescribeRequest',
    );
    return request;
  }
}

/// Current Quality projection and the separate availability of human review.
final class ScenarioQualityDescription {
  ScenarioQualityDescription({
    required this.runId,
    required this.runResultDigest,
    required this.quality,
    required this.availability,
    required this.decisionCount,
    this.requirementId,
    this.headDecisionDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
    if (requirementId != null) {
      _qualityRpcId(requirementId!.value, 'HumanApprovalRequirement');
    }
    _qualityRpcQualityProfile(quality, 'ScenarioQualityDescription.quality');
    if (quality.runId != runId || quality.subjectDigest != runResultDigest) {
      throw ArgumentError('Quality description does not bind its run result');
    }
    if (decisionCount < 0 || decisionCount > 100) {
      throw ArgumentError.value(decisionCount, 'decisionCount');
    }
    if ((decisionCount == 0) != (headDecisionDigest == null)) {
      throw ArgumentError('Quality decision count and head are inconsistent');
    }
    if (decisionCount == 0) {
      if (quality.humanDecision.state != HumanDecisionState.unreviewed) {
        throw ArgumentError('Quality without decisions must be unreviewed');
      }
    } else if (quality.humanDecision.decisionDigest != headDecisionDigest ||
        quality.humanDecision.state == HumanDecisionState.unreviewed ||
        quality.humanDecision.state == HumanDecisionState.superseded) {
      throw ArgumentError('Quality does not project the current decision');
    }
    if (availability == ScenarioQualityReviewAvailability.available &&
        requirementId == null) {
      throw ArgumentError('Available review requires an exact policy');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest runResultDigest;
  final ScenarioQualitySnapshot quality;
  final ScenarioQualityReviewAvailability availability;
  final HumanApprovalRequirementId? requirementId;
  final Digest? headDecisionDigest;
  final int decisionCount;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDescription',
    'runId': runId.value,
    'runResultDigest': runResultDigest.value,
    'quality': quality.toJson(),
    'availability': availability.name,
    if (requirementId != null) 'requirementId': requirementId!.value,
    if (headDecisionDigest != null)
      'headDecisionDigest': headDecisionDigest!.value,
    'decisionCount': decisionCount,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDescription.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDescription',
      const <String>{
        'runId',
        'runResultDigest',
        'quality',
        'availability',
        'decisionCount',
      },
      optional: const <String>{'requirementId', 'headDecisionDigest'},
    );
    final description = ScenarioQualityDescription(
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityDescription'),
      ),
      runResultDigest: Digest(
        _qualityRpcString(
          json,
          'runResultDigest',
          'ScenarioQualityDescription',
        ),
      ),
      quality: ScenarioQualitySnapshot.fromJson(json['quality']),
      availability: _qualityRpcEnum(
        ScenarioQualityReviewAvailability.values,
        _qualityRpcString(json, 'availability', 'ScenarioQualityDescription'),
        'ScenarioQualityDescription.availability',
      ),
      requirementId: json.containsKey('requirementId')
          ? HumanApprovalRequirementId(
              _qualityRpcString(
                json,
                'requirementId',
                'ScenarioQualityDescription',
              ),
            )
          : null,
      headDecisionDigest: json.containsKey('headDecisionDigest')
          ? Digest(
              _qualityRpcString(
                json,
                'headDecisionDigest',
                'ScenarioQualityDescription',
              ),
            )
          : null,
      decisionCount: _qualityRpcInteger(
        json,
        'decisionCount',
        'ScenarioQualityDescription',
      ),
    );
    _qualityRpcVerifyDigest(
      json,
      description.digest,
      'ScenarioQualityDescription',
    );
    return description;
  }
}

enum ScenarioQualityReviewArtifactRole {
  requiredEvidence,
  comparisonBaseline,
  comparisonCandidate,
}

enum ScenarioQualityReviewProvenanceKind {
  appAdapterCaptureReceipt,
  supplementalArtifactImport,
}

/// Stable CAS identity reviewed by a human; no resource URI or lease is here.
final class ScenarioQualityReviewArtifactDescriptor {
  ScenarioQualityReviewArtifactDescriptor({
    required this.requiredEvidenceId,
    required this.requiredEvidenceResultDigest,
    required this.role,
    required this.artifactDigest,
    required this.provenanceDigest,
    required this.provenanceKind,
    required this.classification,
    required this.mediaType,
    required this.size,
    this.comparisonResultDigest,
  }) {
    _qualityRpcId(requiredEvidenceId.value, 'RequiredEvidence');
    final comparisonRole =
        role != ScenarioQualityReviewArtifactRole.requiredEvidence;
    if (comparisonRole != (comparisonResultDigest != null) ||
        size < 1 ||
        size > 32 * 1024 * 1024 ||
        mediaType.length > 256 ||
        !_qualityRpcMediaType.hasMatch(mediaType)) {
      throw ArgumentError('Scenario Quality review artifact is invalid');
    }
  }

  final RequiredEvidenceId requiredEvidenceId;
  final Digest requiredEvidenceResultDigest;
  final ScenarioQualityReviewArtifactRole role;
  final Digest artifactDigest;
  final Digest provenanceDigest;
  final ScenarioQualityReviewProvenanceKind provenanceKind;
  final ArtifactClassification classification;
  final String mediaType;
  final int size;
  final Digest? comparisonResultDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'requiredEvidenceId': requiredEvidenceId.value,
    'requiredEvidenceResultDigest': requiredEvidenceResultDigest.value,
    'role': role.name,
    'artifactDigest': artifactDigest.value,
    'provenanceDigest': provenanceDigest.value,
    'provenanceKind': provenanceKind.name,
    'classification': classification.name,
    'mediaType': mediaType,
    'size': size,
    if (comparisonResultDigest != null)
      'comparisonResultDigest': comparisonResultDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityReviewArtifactDescriptor.fromJson(Object? value) {
    final json = _qualityRpcObject(
      value,
      'ScenarioQualityReviewArtifactDescriptor',
      const <String>{
        'requiredEvidenceId',
        'requiredEvidenceResultDigest',
        'role',
        'artifactDigest',
        'provenanceDigest',
        'provenanceKind',
        'classification',
        'mediaType',
        'size',
        'digest',
      },
      optional: const <String>{'comparisonResultDigest'},
    );
    final descriptor = ScenarioQualityReviewArtifactDescriptor(
      requiredEvidenceId: RequiredEvidenceId(
        _qualityRpcString(
          json,
          'requiredEvidenceId',
          'ScenarioQualityReviewArtifactDescriptor',
        ),
      ),
      requiredEvidenceResultDigest: Digest(
        _qualityRpcString(
          json,
          'requiredEvidenceResultDigest',
          'ScenarioQualityReviewArtifactDescriptor',
        ),
      ),
      role: _qualityRpcEnum(
        ScenarioQualityReviewArtifactRole.values,
        _qualityRpcString(
          json,
          'role',
          'ScenarioQualityReviewArtifactDescriptor',
        ),
        'ScenarioQualityReviewArtifactDescriptor.role',
      ),
      artifactDigest: Digest(
        _qualityRpcString(
          json,
          'artifactDigest',
          'ScenarioQualityReviewArtifactDescriptor',
        ),
      ),
      provenanceDigest: Digest(
        _qualityRpcString(
          json,
          'provenanceDigest',
          'ScenarioQualityReviewArtifactDescriptor',
        ),
      ),
      provenanceKind: _qualityRpcEnum(
        ScenarioQualityReviewProvenanceKind.values,
        _qualityRpcString(
          json,
          'provenanceKind',
          'ScenarioQualityReviewArtifactDescriptor',
        ),
        'ScenarioQualityReviewArtifactDescriptor.provenanceKind',
      ),
      classification: _qualityRpcEnum(
        ArtifactClassification.values,
        _qualityRpcString(
          json,
          'classification',
          'ScenarioQualityReviewArtifactDescriptor',
        ),
        'ScenarioQualityReviewArtifactDescriptor.classification',
      ),
      mediaType: _qualityRpcString(
        json,
        'mediaType',
        'ScenarioQualityReviewArtifactDescriptor',
      ),
      size: _qualityRpcInteger(
        json,
        'size',
        'ScenarioQualityReviewArtifactDescriptor',
      ),
      comparisonResultDigest: json.containsKey('comparisonResultDigest')
          ? Digest(
              _qualityRpcString(
                json,
                'comparisonResultDigest',
                'ScenarioQualityReviewArtifactDescriptor',
              ),
            )
          : null,
    );
    _qualityRpcVerifyDigest(
      json,
      descriptor.digest,
      'ScenarioQualityReviewArtifactDescriptor',
    );
    return descriptor;
  }
}

final class ScenarioQualityReviewDescriptor {
  ScenarioQualityReviewDescriptor({
    required this.runId,
    required this.runResultDigest,
    required this.qualityDigest,
    required this.requirementId,
    required this.requirementScope,
    required this.reviewGuideId,
    required this.reviewGuideStepId,
    required Iterable<Digest> requiredEvidenceResultDigests,
    required Iterable<Digest> comparisonResultDigests,
    required Iterable<ScenarioQualityReviewArtifactDescriptor> artifacts,
  }) : requiredEvidenceResultDigests = _qualityRpcSortedDigests(
         requiredEvidenceResultDigests,
         'ScenarioQualityReviewDescriptor.requiredEvidenceResultDigests',
       ),
       comparisonResultDigests = _qualityRpcSortedDigests(
         comparisonResultDigests,
         'ScenarioQualityReviewDescriptor.comparisonResultDigests',
       ),
       artifacts = _qualityRpcSortedArtifacts(artifacts) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
    _qualityRpcId(requirementId.value, 'HumanApprovalRequirement');
    _qualityRpcId(reviewGuideId.value, 'ReviewGuide');
    _qualityRpcId(reviewGuideStepId, 'ReviewGuideStep');
    final expectedArtifactCount =
        this.requiredEvidenceResultDigests.length +
        (2 * this.comparisonResultDigests.length);
    if (requirementScope != HumanApprovalScope.evidenceSet ||
        this.artifacts.isEmpty ||
        this.artifacts.length != expectedArtifactCount ||
        this.artifacts.any(
          (artifact) =>
              !this.requiredEvidenceResultDigests.contains(
                artifact.requiredEvidenceResultDigest,
              ) ||
              (artifact.comparisonResultDigest != null &&
                  !this.comparisonResultDigests.contains(
                    artifact.comparisonResultDigest,
                  )),
        )) {
      throw ArgumentError('Scenario Quality review set is incomplete');
    }
    for (final resultDigest in this.requiredEvidenceResultDigests) {
      final requiredArtifacts = this.artifacts.where(
        (artifact) =>
            artifact.requiredEvidenceResultDigest == resultDigest &&
            artifact.role == ScenarioQualityReviewArtifactRole.requiredEvidence,
      );
      if (requiredArtifacts.length != 1) {
        throw ArgumentError(
          'Every RequiredEvidence result needs exactly one review artifact',
        );
      }
    }
    for (final comparisonDigest in this.comparisonResultDigests) {
      final comparisonArtifacts = this.artifacts.where(
        (artifact) => artifact.comparisonResultDigest == comparisonDigest,
      );
      final baselineCount = comparisonArtifacts
          .where(
            (artifact) =>
                artifact.role ==
                ScenarioQualityReviewArtifactRole.comparisonBaseline,
          )
          .length;
      final candidateCount = comparisonArtifacts
          .where(
            (artifact) =>
                artifact.role ==
                ScenarioQualityReviewArtifactRole.comparisonCandidate,
          )
          .length;
      if (comparisonArtifacts.length != 2 ||
          baselineCount != 1 ||
          candidateCount != 1) {
        throw ArgumentError(
          'Every comparison needs exact baseline and candidate artifacts',
        );
      }
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest runResultDigest;
  final Digest qualityDigest;
  final HumanApprovalRequirementId requirementId;
  final HumanApprovalScope requirementScope;
  final ReviewGuideId reviewGuideId;
  final String reviewGuideStepId;
  final List<Digest> requiredEvidenceResultDigests;
  final List<Digest> comparisonResultDigests;
  final List<ScenarioQualityReviewArtifactDescriptor> artifacts;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityReviewDescriptor',
    'runId': runId.value,
    'runResultDigest': runResultDigest.value,
    'qualityDigest': qualityDigest.value,
    'requirementId': requirementId.value,
    'requirementScope': requirementScope.name,
    'reviewGuideId': reviewGuideId.value,
    'reviewGuideStepId': reviewGuideStepId,
    'requiredEvidenceResultDigests': requiredEvidenceResultDigests
        .map((digest) => digest.value)
        .toList(),
    'comparisonResultDigests': comparisonResultDigests
        .map((digest) => digest.value)
        .toList(),
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityReviewDescriptor.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityReviewDescriptor',
      const <String>{
        'runId',
        'runResultDigest',
        'qualityDigest',
        'requirementId',
        'requirementScope',
        'reviewGuideId',
        'reviewGuideStepId',
        'requiredEvidenceResultDigests',
        'comparisonResultDigests',
        'artifacts',
      },
    );
    final descriptor = ScenarioQualityReviewDescriptor(
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityReviewDescriptor'),
      ),
      runResultDigest: Digest(
        _qualityRpcString(
          json,
          'runResultDigest',
          'ScenarioQualityReviewDescriptor',
        ),
      ),
      qualityDigest: Digest(
        _qualityRpcString(
          json,
          'qualityDigest',
          'ScenarioQualityReviewDescriptor',
        ),
      ),
      requirementId: HumanApprovalRequirementId(
        _qualityRpcString(
          json,
          'requirementId',
          'ScenarioQualityReviewDescriptor',
        ),
      ),
      requirementScope: _qualityRpcEnum(
        HumanApprovalScope.values,
        _qualityRpcString(
          json,
          'requirementScope',
          'ScenarioQualityReviewDescriptor',
        ),
        'ScenarioQualityReviewDescriptor.requirementScope',
      ),
      reviewGuideId: ReviewGuideId(
        _qualityRpcString(
          json,
          'reviewGuideId',
          'ScenarioQualityReviewDescriptor',
        ),
      ),
      reviewGuideStepId: _qualityRpcString(
        json,
        'reviewGuideStepId',
        'ScenarioQualityReviewDescriptor',
      ),
      requiredEvidenceResultDigests: _qualityRpcDigestList(
        json,
        'requiredEvidenceResultDigests',
        'ScenarioQualityReviewDescriptor',
      ),
      comparisonResultDigests: _qualityRpcDigestList(
        json,
        'comparisonResultDigests',
        'ScenarioQualityReviewDescriptor',
      ),
      artifacts: _qualityRpcList(
        json,
        'artifacts',
        'ScenarioQualityReviewDescriptor',
      ).map(ScenarioQualityReviewArtifactDescriptor.fromJson),
    );
    _qualityRpcVerifyDigest(
      json,
      descriptor.digest,
      'ScenarioQualityReviewDescriptor',
    );
    return descriptor;
  }
}

final class ScenarioQualityDescribeResult {
  ScenarioQualityDescribeResult({
    required this.description,
    this.reviewDescriptor,
  }) {
    if ((description.availability ==
            ScenarioQualityReviewAvailability.available) !=
        (reviewDescriptor != null)) {
      throw ArgumentError('Review descriptor availability is inconsistent');
    }
    if (reviewDescriptor != null &&
        (reviewDescriptor!.runId != description.runId ||
            reviewDescriptor!.runResultDigest != description.runResultDigest ||
            reviewDescriptor!.qualityDigest != description.quality.digest ||
            reviewDescriptor!.requirementId != description.requirementId)) {
      throw ArgumentError('Review descriptor does not bind the description');
    }
    if (reviewDescriptor != null) {
      final evidenceByResult = <Digest, RequiredEvidenceId>{
        for (final item in description.quality.requiredEvidence)
          item.resultDigest: item.requiredEvidenceId,
      };
      if (evidenceByResult.length !=
          description.quality.requiredEvidence.length) {
        throw ArgumentError(
          'Quality has ambiguous RequiredEvidence result bindings',
        );
      }
      final evidence = evidenceByResult.keys.toSet();
      final describedEvidence = reviewDescriptor!.requiredEvidenceResultDigests
          .toSet();
      final comparisons = description.quality.comparisonResultDigests.toSet();
      final describedComparisons = reviewDescriptor!.comparisonResultDigests
          .toSet();
      if (evidence.length != describedEvidence.length ||
          !evidence.containsAll(describedEvidence) ||
          comparisons.length != describedComparisons.length ||
          !comparisons.containsAll(describedComparisons)) {
        throw ArgumentError(
          'Review descriptor must cover the complete Quality result set',
        );
      }
      for (final artifact in reviewDescriptor!.artifacts) {
        if (evidenceByResult[artifact.requiredEvidenceResultDigest] !=
            artifact.requiredEvidenceId) {
          throw ArgumentError(
            'Review artifact does not bind the exact RequiredEvidence result',
          );
        }
      }
    }
  }

  static const int schemaVersion = 1;
  final ScenarioQualityDescription description;
  final ScenarioQualityReviewDescriptor? reviewDescriptor;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDescribeResult',
    'description': description.toJson(),
    if (reviewDescriptor != null)
      'reviewDescriptor': reviewDescriptor!.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDescribeResult.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDescribeResult',
      const <String>{'description'},
      optional: const <String>{'reviewDescriptor'},
    );
    final result = ScenarioQualityDescribeResult(
      description: ScenarioQualityDescription.fromJson(json['description']),
      reviewDescriptor: json.containsKey('reviewDescriptor')
          ? ScenarioQualityReviewDescriptor.fromJson(json['reviewDescriptor'])
          : null,
    );
    _qualityRpcVerifyDigest(
      json,
      result.digest,
      'ScenarioQualityDescribeResult',
    );
    return result;
  }
}

final class ScenarioQualityReviewOpenRequest {
  ScenarioQualityReviewOpenRequest({
    required this.runId,
    required this.expectedRunResultDigest,
    required this.expectedQualityDigest,
    required this.expectedReviewDescriptorDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest expectedRunResultDigest;
  final Digest expectedQualityDigest;
  final Digest expectedReviewDescriptorDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityReviewOpenRequest',
    'runId': runId.value,
    'expectedRunResultDigest': expectedRunResultDigest.value,
    'expectedQualityDigest': expectedQualityDigest.value,
    'expectedReviewDescriptorDigest': expectedReviewDescriptorDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityReviewOpenRequest.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityReviewOpenRequest',
      const <String>{
        'runId',
        'expectedRunResultDigest',
        'expectedQualityDigest',
        'expectedReviewDescriptorDigest',
      },
    );
    final request = ScenarioQualityReviewOpenRequest(
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityReviewOpenRequest'),
      ),
      expectedRunResultDigest: Digest(
        _qualityRpcString(
          json,
          'expectedRunResultDigest',
          'ScenarioQualityReviewOpenRequest',
        ),
      ),
      expectedQualityDigest: Digest(
        _qualityRpcString(
          json,
          'expectedQualityDigest',
          'ScenarioQualityReviewOpenRequest',
        ),
      ),
      expectedReviewDescriptorDigest: Digest(
        _qualityRpcString(
          json,
          'expectedReviewDescriptorDigest',
          'ScenarioQualityReviewOpenRequest',
        ),
      ),
    );
    _qualityRpcVerifyDigest(
      json,
      request.digest,
      'ScenarioQualityReviewOpenRequest',
    );
    return request;
  }
}

final class ScenarioQualityReviewResourceBinding {
  ScenarioQualityReviewResourceBinding({
    required this.artifactDescriptorDigest,
    required this.artifact,
    required this.provenance,
  }) {
    if (artifact.purpose != 'scenario-quality-review-artifact' ||
        provenance.purpose != 'scenario-quality-review-provenance' ||
        provenance.mediaType != 'application/json' ||
        artifact.size < 1 ||
        provenance.size < 1) {
      throw ArgumentError('Scenario Quality review resources are invalid');
    }
  }

  final Digest artifactDescriptorDigest;
  final ResourceHandle artifact;
  final ResourceHandle provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'artifactDescriptorDigest': artifactDescriptorDigest.value,
    'artifact': artifact.toJson(),
    'provenance': provenance.toJson(),
  };

  factory ScenarioQualityReviewResourceBinding.fromJson(Object? value) {
    final json = _qualityRpcObject(
      value,
      'ScenarioQualityReviewResourceBinding',
      const <String>{'artifactDescriptorDigest', 'artifact', 'provenance'},
    );
    return ScenarioQualityReviewResourceBinding(
      artifactDescriptorDigest: Digest(
        _qualityRpcString(
          json,
          'artifactDescriptorDigest',
          'ScenarioQualityReviewResourceBinding',
        ),
      ),
      artifact: ResourceHandle.fromJson(json['artifact']),
      provenance: ResourceHandle.fromJson(json['provenance']),
    );
  }
}

/// Ephemeral leases are deliberately outside every semantic decision digest.
final class ScenarioQualityReviewOpenResult {
  ScenarioQualityReviewOpenResult({
    required this.reviewDescriptor,
    required Iterable<ScenarioQualityReviewResourceBinding> resources,
  }) : resources = List<ScenarioQualityReviewResourceBinding>.unmodifiable(
         resources,
       ) {
    final expected = reviewDescriptor.artifacts
        .map((artifact) => artifact.digest)
        .toSet();
    final actual = this.resources
        .map((resource) => resource.artifactDescriptorDigest)
        .toSet();
    if (actual.length != this.resources.length ||
        actual.length != expected.length ||
        !actual.containsAll(expected)) {
      throw ArgumentError('Review resources do not cover every artifact');
    }
    for (final binding in this.resources) {
      final descriptor = reviewDescriptor.artifacts.singleWhere(
        (artifact) => artifact.digest == binding.artifactDescriptorDigest,
      );
      if (binding.artifact.digest != descriptor.artifactDigest ||
          binding.artifact.mediaType != descriptor.mediaType ||
          binding.artifact.size != descriptor.size ||
          binding.provenance.digest != descriptor.provenanceDigest) {
        throw ArgumentError('Review resource does not bind its descriptor');
      }
    }
  }

  static const int schemaVersion = 1;
  final ScenarioQualityReviewDescriptor reviewDescriptor;
  final List<ScenarioQualityReviewResourceBinding> resources;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityReviewOpenResult',
    'reviewDescriptor': reviewDescriptor.toJson(),
    'resources': resources.map((resource) => resource.toJson()).toList(),
  };

  factory ScenarioQualityReviewOpenResult.fromJson(Object? value) {
    final json = _qualityRpcObject(
      value,
      'ScenarioQualityReviewOpenResult',
      const <String>{'schemaVersion', 'kind', 'reviewDescriptor', 'resources'},
    );
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ScenarioQualityReviewOpenResult') {
      throw const FormatException('Invalid ScenarioQualityReviewOpenResult');
    }
    return ScenarioQualityReviewOpenResult(
      reviewDescriptor: ScenarioQualityReviewDescriptor.fromJson(
        json['reviewDescriptor'],
      ),
      resources: _qualityRpcList(
        json,
        'resources',
        'ScenarioQualityReviewOpenResult',
      ).map(ScenarioQualityReviewResourceBinding.fromJson),
    );
  }
}

/// Explicit, idempotent request for one decision-scoped mutation grant.
final class ScenarioQualityDecisionGrantRequest {
  ScenarioQualityDecisionGrantRequest({
    required this.requestId,
    required this.runId,
    required this.expectedRunResultDigest,
    required this.expectedQualityDigest,
    required this.expectedReviewDescriptorDigest,
    required this.decision,
    this.expectedPreviousDecisionDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
  }

  static const int schemaVersion = 1;
  final ScenarioQualityDecisionRequestId requestId;
  final ScenarioLabRunId runId;
  final Digest expectedRunResultDigest;
  final Digest expectedQualityDigest;
  final Digest expectedReviewDescriptorDigest;
  final HumanDecision decision;
  final Digest? expectedPreviousDecisionDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDecisionGrantRequest',
    'requestId': requestId.value,
    'runId': runId.value,
    'expectedRunResultDigest': expectedRunResultDigest.value,
    'expectedQualityDigest': expectedQualityDigest.value,
    'expectedReviewDescriptorDigest': expectedReviewDescriptorDigest.value,
    'decision': decision.name,
    if (expectedPreviousDecisionDigest != null)
      'expectedPreviousDecisionDigest': expectedPreviousDecisionDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionGrantRequest.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDecisionGrantRequest',
      const <String>{
        'requestId',
        'runId',
        'expectedRunResultDigest',
        'expectedQualityDigest',
        'expectedReviewDescriptorDigest',
        'decision',
      },
      optional: const <String>{'expectedPreviousDecisionDigest'},
    );
    final request = ScenarioQualityDecisionGrantRequest(
      requestId: ScenarioQualityDecisionRequestId(
        _qualityRpcString(
          json,
          'requestId',
          'ScenarioQualityDecisionGrantRequest',
        ),
      ),
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityDecisionGrantRequest'),
      ),
      expectedRunResultDigest: Digest(
        _qualityRpcString(
          json,
          'expectedRunResultDigest',
          'ScenarioQualityDecisionGrantRequest',
        ),
      ),
      expectedQualityDigest: Digest(
        _qualityRpcString(
          json,
          'expectedQualityDigest',
          'ScenarioQualityDecisionGrantRequest',
        ),
      ),
      expectedReviewDescriptorDigest: Digest(
        _qualityRpcString(
          json,
          'expectedReviewDescriptorDigest',
          'ScenarioQualityDecisionGrantRequest',
        ),
      ),
      decision: _qualityRpcEnum(
        HumanDecision.values,
        _qualityRpcString(
          json,
          'decision',
          'ScenarioQualityDecisionGrantRequest',
        ),
        'ScenarioQualityDecisionGrantRequest.decision',
      ),
      expectedPreviousDecisionDigest:
          json.containsKey('expectedPreviousDecisionDigest')
          ? Digest(
              _qualityRpcString(
                json,
                'expectedPreviousDecisionDigest',
                'ScenarioQualityDecisionGrantRequest',
              ),
            )
          : null,
    );
    _qualityRpcVerifyDigest(
      json,
      request.digest,
      'ScenarioQualityDecisionGrantRequest',
    );
    return request;
  }
}

/// Caller intent only. Identity, role, policy, record ID and time are Host-owned.
final class ScenarioQualityDecisionAppendRequest {
  ScenarioQualityDecisionAppendRequest({
    required this.requestId,
    required this.runId,
    required this.expectedRunResultDigest,
    required this.expectedQualityDigest,
    required this.expectedReviewDescriptorDigest,
    required this.grantId,
    required this.grantDigest,
    required this.decision,
    this.expectedPreviousDecisionDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
  }

  static const int schemaVersion = 1;
  final ScenarioQualityDecisionRequestId requestId;
  final ScenarioLabRunId runId;
  final Digest expectedRunResultDigest;
  final Digest expectedQualityDigest;
  final Digest expectedReviewDescriptorDigest;
  final ScenarioQualityDecisionGrantId grantId;
  final Digest grantDigest;
  final HumanDecision decision;
  final Digest? expectedPreviousDecisionDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDecisionAppendRequest',
    'requestId': requestId.value,
    'runId': runId.value,
    'expectedRunResultDigest': expectedRunResultDigest.value,
    'expectedQualityDigest': expectedQualityDigest.value,
    'expectedReviewDescriptorDigest': expectedReviewDescriptorDigest.value,
    'grantId': grantId.value,
    'grantDigest': grantDigest.value,
    'decision': decision.name,
    if (expectedPreviousDecisionDigest != null)
      'expectedPreviousDecisionDigest': expectedPreviousDecisionDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionAppendRequest.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDecisionAppendRequest',
      const <String>{
        'requestId',
        'runId',
        'expectedRunResultDigest',
        'expectedQualityDigest',
        'expectedReviewDescriptorDigest',
        'grantId',
        'grantDigest',
        'decision',
      },
      optional: const <String>{'expectedPreviousDecisionDigest'},
    );
    final request = ScenarioQualityDecisionAppendRequest(
      requestId: ScenarioQualityDecisionRequestId(
        _qualityRpcString(
          json,
          'requestId',
          'ScenarioQualityDecisionAppendRequest',
        ),
      ),
      runId: ScenarioLabRunId(
        _qualityRpcString(
          json,
          'runId',
          'ScenarioQualityDecisionAppendRequest',
        ),
      ),
      expectedRunResultDigest: Digest(
        _qualityRpcString(
          json,
          'expectedRunResultDigest',
          'ScenarioQualityDecisionAppendRequest',
        ),
      ),
      expectedQualityDigest: Digest(
        _qualityRpcString(
          json,
          'expectedQualityDigest',
          'ScenarioQualityDecisionAppendRequest',
        ),
      ),
      expectedReviewDescriptorDigest: Digest(
        _qualityRpcString(
          json,
          'expectedReviewDescriptorDigest',
          'ScenarioQualityDecisionAppendRequest',
        ),
      ),
      grantId: ScenarioQualityDecisionGrantId(
        _qualityRpcString(
          json,
          'grantId',
          'ScenarioQualityDecisionAppendRequest',
        ),
      ),
      grantDigest: Digest(
        _qualityRpcString(
          json,
          'grantDigest',
          'ScenarioQualityDecisionAppendRequest',
        ),
      ),
      decision: _qualityRpcEnum(
        HumanDecision.values,
        _qualityRpcString(
          json,
          'decision',
          'ScenarioQualityDecisionAppendRequest',
        ),
        'ScenarioQualityDecisionAppendRequest.decision',
      ),
      expectedPreviousDecisionDigest:
          json.containsKey('expectedPreviousDecisionDigest')
          ? Digest(
              _qualityRpcString(
                json,
                'expectedPreviousDecisionDigest',
                'ScenarioQualityDecisionAppendRequest',
              ),
            )
          : null,
    );
    _qualityRpcVerifyDigest(
      json,
      request.digest,
      'ScenarioQualityDecisionAppendRequest',
    );
    return request;
  }
}

final class ScenarioQualityDecisionAppendResult {
  ScenarioQualityDecisionAppendResult({
    required this.requestId,
    required this.requestDigest,
    required this.attribution,
    required this.record,
    required this.quality,
  }) {
    _qualityRpcQualityProfile(
      quality,
      'ScenarioQualityDecisionAppendResult.quality',
    );
    final expectedState = switch (record.decision) {
      HumanDecision.approved => HumanDecisionState.approved,
      HumanDecision.rejected => HumanDecisionState.rejected,
    };
    if (requestDigest != attribution.decisionRequestDigest ||
        attribution.runId != quality.runId ||
        attribution.runResultDigest != record.subjectDigest ||
        record.principalId != attribution.principalId ||
        record.subjectDigest != quality.subjectDigest ||
        quality.humanDecision.state != expectedState ||
        quality.humanDecision.decisionDigest != record.digest ||
        quality.humanDecision.supersededByDecisionDigest != null) {
      throw ArgumentError('Append result does not project its decision');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioQualityDecisionRequestId requestId;
  final Digest requestDigest;
  final ScenarioQualityDecisionAttribution attribution;
  final HumanDecisionRecord record;
  final ScenarioQualitySnapshot quality;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDecisionAppendResult',
    'requestId': requestId.value,
    'requestDigest': requestDigest.value,
    'attribution': attribution.toJson(),
    'record': record.toJson(),
    'quality': quality.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionAppendResult.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDecisionAppendResult',
      const <String>{
        'requestId',
        'requestDigest',
        'attribution',
        'record',
        'quality',
      },
    );
    final result = ScenarioQualityDecisionAppendResult(
      requestId: ScenarioQualityDecisionRequestId(
        _qualityRpcString(
          json,
          'requestId',
          'ScenarioQualityDecisionAppendResult',
        ),
      ),
      requestDigest: Digest(
        _qualityRpcString(
          json,
          'requestDigest',
          'ScenarioQualityDecisionAppendResult',
        ),
      ),
      attribution: ScenarioQualityDecisionAttribution.fromJson(
        json['attribution'],
      ),
      record: HumanDecisionRecord.fromJson(json['record']),
      quality: ScenarioQualitySnapshot.fromJson(json['quality']),
    );
    _qualityRpcVerifyDigest(
      json,
      result.digest,
      'ScenarioQualityDecisionAppendResult',
    );
    return result;
  }
}

final class ScenarioQualityDecisionGetRequest {
  ScenarioQualityDecisionGetRequest({
    required this.runId,
    required this.expectedRunResultDigest,
    required this.decisionDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest expectedRunResultDigest;
  final Digest decisionDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDecisionGetRequest',
    'runId': runId.value,
    'expectedRunResultDigest': expectedRunResultDigest.value,
    'decisionDigest': decisionDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionGetRequest.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDecisionGetRequest',
      const <String>{'runId', 'expectedRunResultDigest', 'decisionDigest'},
    );
    final request = ScenarioQualityDecisionGetRequest(
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityDecisionGetRequest'),
      ),
      expectedRunResultDigest: Digest(
        _qualityRpcString(
          json,
          'expectedRunResultDigest',
          'ScenarioQualityDecisionGetRequest',
        ),
      ),
      decisionDigest: Digest(
        _qualityRpcString(
          json,
          'decisionDigest',
          'ScenarioQualityDecisionGetRequest',
        ),
      ),
    );
    _qualityRpcVerifyDigest(
      json,
      request.digest,
      'ScenarioQualityDecisionGetRequest',
    );
    return request;
  }
}

final class ScenarioQualityDecisionView {
  ScenarioQualityDecisionView({
    required this.record,
    required this.projection,
    required this.attribution,
    required this.reviewDescriptor,
  }) {
    if (record.principalId != attribution.principalId ||
        record.subjectDigest != attribution.runResultDigest ||
        reviewDescriptor.digest != attribution.reviewDescriptorDigest ||
        reviewDescriptor.runId != attribution.runId ||
        reviewDescriptor.runResultDigest != attribution.runResultDigest ||
        reviewDescriptor.requirementId != attribution.requirementId ||
        reviewDescriptor.requirementScope != attribution.requirementScope ||
        reviewDescriptor.reviewGuideId != attribution.reviewGuideId ||
        reviewDescriptor.reviewGuideStepId != attribution.reviewGuideStepId ||
        projection.decisionDigest != record.digest ||
        projection.state == HumanDecisionState.unreviewed) {
      throw ArgumentError('Decision view projection is inconsistent');
    }
    final expectedState = switch (record.decision) {
      HumanDecision.approved => HumanDecisionState.approved,
      HumanDecision.rejected => HumanDecisionState.rejected,
    };
    if (projection.state != HumanDecisionState.superseded &&
        projection.state != expectedState) {
      throw ArgumentError('Current decision view has the wrong state');
    }
  }

  static const int schemaVersion = 1;
  final HumanDecisionRecord record;
  final HumanDecisionProjection projection;
  final ScenarioQualityDecisionAttribution attribution;
  final ScenarioQualityReviewDescriptor reviewDescriptor;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDecisionView',
    'record': record.toJson(),
    'projection': projection.toJson(),
    'attribution': attribution.toJson(),
    'reviewDescriptor': reviewDescriptor.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionView.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDecisionView',
      const <String>{'record', 'projection', 'attribution', 'reviewDescriptor'},
    );
    final view = ScenarioQualityDecisionView(
      record: HumanDecisionRecord.fromJson(json['record']),
      projection: HumanDecisionProjection.fromJson(json['projection']),
      attribution: ScenarioQualityDecisionAttribution.fromJson(
        json['attribution'],
      ),
      reviewDescriptor: ScenarioQualityReviewDescriptor.fromJson(
        json['reviewDescriptor'],
      ),
    );
    _qualityRpcVerifyDigest(json, view.digest, 'ScenarioQualityDecisionView');
    return view;
  }
}

/// Typed JSON-RPC error data; consumers never need to parse an error message.
final class ScenarioQualityDecisionError {
  ScenarioQualityDecisionError({
    required this.operation,
    required this.code,
    required this.runId,
    required this.expectedRunResultDigest,
    this.requestId,
    this.currentQualityDigest,
    this.currentDecisionDigest,
  }) {
    _qualityRpcId(runId.value, 'ScenarioLabRun');
    if ((const <ScenarioQualityDecisionOperation>{
          ScenarioQualityDecisionOperation.grant,
          ScenarioQualityDecisionOperation.append,
        }.contains(operation)) !=
        (requestId != null)) {
      throw ArgumentError(
        'Grant and append errors alone carry a decision request ID',
      );
    }
  }

  static const int schemaVersion = 1;
  static const int jsonRpcCode = -32120;
  final ScenarioQualityDecisionOperation operation;
  final ScenarioQualityDecisionErrorCode code;
  final ScenarioLabRunId runId;
  final Digest expectedRunResultDigest;
  final ScenarioQualityDecisionRequestId? requestId;
  final Digest? currentQualityDigest;
  final Digest? currentDecisionDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualityDecisionError',
    'operation': operation.name,
    'code': code.name,
    'runId': runId.value,
    'expectedRunResultDigest': expectedRunResultDigest.value,
    if (requestId != null) 'requestId': requestId!.value,
    if (currentQualityDigest != null)
      'currentQualityDigest': currentQualityDigest!.value,
    if (currentDecisionDigest != null)
      'currentDecisionDigest': currentDecisionDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualityDecisionError.fromJson(Object? value) {
    final json = _qualityRpcDocument(
      value,
      'ScenarioQualityDecisionError',
      const <String>{'operation', 'code', 'runId', 'expectedRunResultDigest'},
      optional: const <String>{
        'requestId',
        'currentQualityDigest',
        'currentDecisionDigest',
      },
    );
    final error = ScenarioQualityDecisionError(
      operation: _qualityRpcEnum(
        ScenarioQualityDecisionOperation.values,
        _qualityRpcString(json, 'operation', 'ScenarioQualityDecisionError'),
        'ScenarioQualityDecisionError.operation',
      ),
      code: _qualityRpcEnum(
        ScenarioQualityDecisionErrorCode.values,
        _qualityRpcString(json, 'code', 'ScenarioQualityDecisionError'),
        'ScenarioQualityDecisionError.code',
      ),
      runId: ScenarioLabRunId(
        _qualityRpcString(json, 'runId', 'ScenarioQualityDecisionError'),
      ),
      expectedRunResultDigest: Digest(
        _qualityRpcString(
          json,
          'expectedRunResultDigest',
          'ScenarioQualityDecisionError',
        ),
      ),
      requestId: json.containsKey('requestId')
          ? ScenarioQualityDecisionRequestId(
              _qualityRpcString(
                json,
                'requestId',
                'ScenarioQualityDecisionError',
              ),
            )
          : null,
      currentQualityDigest: json.containsKey('currentQualityDigest')
          ? Digest(
              _qualityRpcString(
                json,
                'currentQualityDigest',
                'ScenarioQualityDecisionError',
              ),
            )
          : null,
      currentDecisionDigest: json.containsKey('currentDecisionDigest')
          ? Digest(
              _qualityRpcString(
                json,
                'currentDecisionDigest',
                'ScenarioQualityDecisionError',
              ),
            )
          : null,
    );
    _qualityRpcVerifyDigest(json, error.digest, 'ScenarioQualityDecisionError');
    return error;
  }
}

Map<String, Object?> _qualityRpcDocument(
  Object? value,
  String kind,
  Set<String> required, {
  Set<String> optional = const <String>{},
}) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$kind must be an object');
  }
  final requiredKeys = <String>{'schemaVersion', 'kind', 'digest', ...required};
  final allowedKeys = <String>{...requiredKeys, ...optional};
  if (value['schemaVersion'] != 1 ||
      value['kind'] != kind ||
      !value.keys.toSet().containsAll(requiredKeys) ||
      value.keys.any((key) => !allowedKeys.contains(key))) {
    throw FormatException('Invalid $kind document');
  }
  return value;
}

Map<String, Object?> _qualityRpcObject(
  Object? value,
  String path,
  Set<String> required, {
  Set<String> optional = const <String>{},
}) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  final allowed = <String>{...required, ...optional};
  if (!value.keys.toSet().containsAll(required) ||
      value.keys.any((key) => !allowed.contains(key))) {
    throw FormatException('Invalid $path object');
  }
  return value;
}

String _qualityRpcString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 4096) {
    throw FormatException('$path.$key must be a bounded string');
  }
  return value;
}

int _qualityRpcInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! num ||
      !value.isFinite ||
      value != value.truncateToDouble() ||
      value.abs() > 9007199254740991) {
    throw FormatException('$path.$key must be an I-JSON-safe integer');
  }
  return value.toInt();
}

List<Object?> _qualityRpcList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value is! List<Object?> || value.length > 32) {
    throw FormatException('$path.$key must be a bounded list');
  }
  return value;
}

Iterable<Digest> _qualityRpcDigestList(
  Map<String, Object?> json,
  String key,
  String path,
) => _qualityRpcList(json, key, path).map((value) {
  if (value is! String) {
    throw FormatException('$path.$key must contain digests');
  }
  return Digest(value);
});

List<Digest> _qualityRpcSortedDigests(Iterable<Digest> values, String path) {
  final output = values.toList()..sort((a, b) => a.value.compareTo(b.value));
  if (output.length > 32 || output.toSet().length != output.length) {
    throw ArgumentError('$path must be bounded and unique');
  }
  return List<Digest>.unmodifiable(output);
}

List<ScenarioQualityReviewArtifactDescriptor> _qualityRpcSortedArtifacts(
  Iterable<ScenarioQualityReviewArtifactDescriptor> values,
) {
  final output = values.toList()
    ..sort((a, b) => a.digest.value.compareTo(b.digest.value));
  if (output.length > 32 ||
      output.map((item) => item.digest).toSet().length != output.length) {
    throw ArgumentError(
      'ScenarioQualityReviewDescriptor.artifacts must be bounded and unique',
    );
  }
  return List<ScenarioQualityReviewArtifactDescriptor>.unmodifiable(output);
}

DateTime _qualityRpcTime(Map<String, Object?> json, String key, String path) {
  final raw = _qualityRpcString(json, key, path);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null ||
      !raw.endsWith('Z') ||
      parsed.toUtc().toIso8601String() != raw) {
    throw FormatException('$path.$key must be canonical UTC');
  }
  return parsed.toUtc();
}

T _qualityRpcEnum<T extends Enum>(
  Iterable<T> values,
  String value,
  String path,
) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$path is unsupported');
}

void _qualityRpcVerifyDigest(
  Map<String, Object?> json,
  Digest expected,
  String path,
) {
  final supplied = _qualityRpcString(json, 'digest', path);
  if (supplied != expected.value) {
    throw FormatException('$path digest mismatch');
  }
}

void _qualityRpcId(String value, String kind) {
  if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(value) ||
      value.length > 256) {
    throw ArgumentError.value(value, kind, 'must be a valid opaque ID');
  }
}

void _qualityRpcQualityProfile(ScenarioQualitySnapshot quality, String path) {
  _qualityRpcId(quality.runId.value, '$path.runId');
  _qualityRpcId(quality.scenarioId.value, '$path.scenarioId');
  for (final evidence in quality.requiredEvidence) {
    _qualityRpcId(
      evidence.requiredEvidenceId.value,
      '$path.requiredEvidence.requiredEvidenceId',
    );
  }
  if (quality.requiredEvidence.length > 32 ||
      quality.comparisonResultDigests.length > 32) {
    throw ArgumentError('$path exceeds the Scenario Quality RPC profile');
  }
}

final RegExp _qualityRpcMediaType = RegExp(
  r'^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$',
);
