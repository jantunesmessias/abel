import 'dart:convert';

import '../catalog/catalog_contracts.dart';
import '../catalog/experience_topology_contracts.dart';
import '../catalog/scenario_facet_contracts.dart';
import '../composition/kit_composition_contracts.dart';
import '../digest.dart';

part 'experience_authoring_rpc_contracts.dart';
part 'experience_authoring_review_rpc_contracts.dart';
part 'experience_authoring_review_action_rpc_contracts.dart';
part 'experience_authoring_lifecycle_rpc_contracts.dart';

const int experienceAuthoringMaxFrameBytes = 64 * 1024;
const int experienceAuthoringMaxDocumentBytes = 60 * 1024;
const int experienceAuthoringMaxReviewPacketBytes = 52 * 1024;
const int experienceAuthoringMaxChangeSetBytes = 40 * 1024;
const int experienceAuthoringMaxDraftBytes = 40 * 1024;
const int experienceAuthoringMaxOperations = 64;
const int experienceAuthoringMaxFindings = 4;
const int experienceAuthoringMaxConcepts = 4;
const int experienceAuthoringMaxComments = 8;
const int experienceAuthoringMaxDecisions = 8;
const int experienceAuthoringMaxPromotionReceipts = 16;
const int experienceAuthoringMaxSafeInteger = 9007199254740991;
const String projectionLayoutSafetyEvaluatorId = 'projection-layout-safety.v1';
const String projectionLayoutSafetyPassedSummary =
    'Projection layout safety passed';
const String projectionLayoutSafetyFailedSummary =
    'Projection layout safety failed';

final class AuthoringActionGrantId extends OpaqueId {
  factory AuthoringActionGrantId(String value) {
    _authoringId(value, 'AuthoringActionGrant');
    return AuthoringActionGrantId._(value);
  }

  const AuthoringActionGrantId._(super.value);
}

final class AuthoringRequestId extends OpaqueId {
  factory AuthoringRequestId(String value) {
    _authoringId(value, 'AuthoringRequest');
    return AuthoringRequestId._(value);
  }

  const AuthoringRequestId._(super.value);
}

final class AuthoringAuthorityId extends OpaqueId {
  factory AuthoringAuthorityId(String value) {
    _authoringId(value, 'AuthoringAuthority');
    return AuthoringAuthorityId._(value);
  }

  const AuthoringAuthorityId._(super.value);
}

final class AuthoringPolicyId extends OpaqueId {
  factory AuthoringPolicyId(String value) {
    _authoringId(value, 'AuthoringPolicy');
    return AuthoringPolicyId._(value);
  }

  const AuthoringPolicyId._(super.value);
}

final class AuthoringPrincipalId extends OpaqueId {
  factory AuthoringPrincipalId(String value) {
    _authoringId(value, 'AuthoringPrincipal');
    return AuthoringPrincipalId._(value);
  }

  const AuthoringPrincipalId._(super.value);
}

final class LayoutDraftId extends OpaqueId {
  factory LayoutDraftId(String value) {
    _authoringId(value, 'LayoutDraft');
    return LayoutDraftId._(value);
  }

  const LayoutDraftId._(super.value);
}

final class LayoutOperationId extends OpaqueId {
  factory LayoutOperationId(String value) {
    _authoringId(value, 'LayoutOperation');
    return LayoutOperationId._(value);
  }

  const LayoutOperationId._(super.value);
}

final class ExperienceChangeSetId extends OpaqueId {
  factory ExperienceChangeSetId(String value) {
    _authoringId(value, 'ExperienceChangeSet');
    return ExperienceChangeSetId._(value);
  }

  const ExperienceChangeSetId._(super.value);
}

final class ExperienceReviewPacketId extends OpaqueId {
  factory ExperienceReviewPacketId(String value) {
    _authoringId(value, 'ExperienceReviewPacket');
    return ExperienceReviewPacketId._(value);
  }

  const ExperienceReviewPacketId._(super.value);
}

final class ExperienceFindingId extends OpaqueId {
  factory ExperienceFindingId(String value) {
    _authoringId(value, 'ExperienceFinding');
    return ExperienceFindingId._(value);
  }

  const ExperienceFindingId._(super.value);
}

final class ExperienceConceptProposalId extends OpaqueId {
  factory ExperienceConceptProposalId(String value) {
    _authoringId(value, 'ExperienceConceptProposal');
    return ExperienceConceptProposalId._(value);
  }

  const ExperienceConceptProposalId._(super.value);
}

final class ExperienceReviewCommentId extends OpaqueId {
  factory ExperienceReviewCommentId(String value) {
    _authoringId(value, 'ExperienceReviewComment');
    return ExperienceReviewCommentId._(value);
  }

  const ExperienceReviewCommentId._(super.value);
}

final class ExperienceHumanDecisionId extends OpaqueId {
  factory ExperienceHumanDecisionId(String value) {
    _authoringId(value, 'ExperienceHumanDecision');
    return ExperienceHumanDecisionId._(value);
  }

  const ExperienceHumanDecisionId._(super.value);
}

final class ExperiencePromotionReceiptId extends OpaqueId {
  factory ExperiencePromotionReceiptId(String value) {
    _authoringId(value, 'ExperiencePromotionReceipt');
    return ExperiencePromotionReceiptId._(value);
  }

  const ExperiencePromotionReceiptId._(super.value);
}

final class LayoutDraftAbandonReceiptId extends OpaqueId {
  factory LayoutDraftAbandonReceiptId(String value) {
    _authoringId(value, 'LayoutDraftAbandonReceipt');
    return LayoutDraftAbandonReceiptId._(value);
  }

  const LayoutDraftAbandonReceiptId._(super.value);
}

enum AuthoringActionEffect { query, authoring, decision }

enum AuthoringOperation {
  describe,
  getSubjectHead,
  openDraft,
  getDraft,
  abandonDraft,
  moveNode,
  undo,
  redo,
  reset,
  getChangeSet,
  getReview,
  getPromotion,
  getPromotionHistory,
  appendFinding,
  proposeConcept,
  appendComment,
  prepareReview,
  evaluateAutomatedAcceptance,
  decideReview,
  promote,
}

AuthoringActionEffect authoringEffectFor(AuthoringOperation operation) =>
    switch (operation) {
      AuthoringOperation.describe ||
      AuthoringOperation.getSubjectHead ||
      AuthoringOperation.getDraft ||
      AuthoringOperation.getChangeSet ||
      AuthoringOperation.getReview ||
      AuthoringOperation.getPromotion ||
      AuthoringOperation.getPromotionHistory => AuthoringActionEffect.query,
      AuthoringOperation.openDraft ||
      AuthoringOperation.abandonDraft ||
      AuthoringOperation.moveNode ||
      AuthoringOperation.undo ||
      AuthoringOperation.redo ||
      AuthoringOperation.reset ||
      AuthoringOperation.proposeConcept ||
      AuthoringOperation.prepareReview ||
      AuthoringOperation.promote => AuthoringActionEffect.authoring,
      AuthoringOperation.appendFinding ||
      AuthoringOperation.appendComment ||
      AuthoringOperation.evaluateAutomatedAcceptance ||
      AuthoringOperation.decideReview => AuthoringActionEffect.decision,
    };

final class AuthoringSubjectRef {
  AuthoringSubjectRef({
    required this.workspaceId,
    required this.applicationId,
    required this.projectionId,
  }) {
    for (final value in <String>[
      workspaceId.value,
      applicationId.value,
      projectionId.value,
    ]) {
      if (utf8.encode(value).length > 128) {
        throw ArgumentError('Authoring subject IDs are limited to 128 bytes');
      }
    }
  }

  final WorkspaceId workspaceId;
  final ApplicationId applicationId;
  final ExperienceProjectionId projectionId;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId.value,
    'applicationId': applicationId.value,
    'projectionId': projectionId.value,
  };

  factory AuthoringSubjectRef.fromJson(Object? value) {
    final json = _authoringObject(value, 'AuthoringSubjectRef');
    _authoringOnly(json, const <String>{
      'workspaceId',
      'applicationId',
      'projectionId',
    }, 'AuthoringSubjectRef');
    return AuthoringSubjectRef(
      workspaceId: WorkspaceId(
        _authoringString(json, 'workspaceId', 'AuthoringSubjectRef'),
      ),
      applicationId: ApplicationId(
        _authoringString(json, 'applicationId', 'AuthoringSubjectRef'),
      ),
      projectionId: ExperienceProjectionId(
        _authoringString(json, 'projectionId', 'AuthoringSubjectRef'),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AuthoringSubjectRef &&
      other.workspaceId == workspaceId &&
      other.applicationId == applicationId &&
      other.projectionId == projectionId;

  @override
  int get hashCode => Object.hash(workspaceId, applicationId, projectionId);
}

/// Stable declaration that a live module supports a bounded authoring surface.
final class AuthoringCapability {
  AuthoringCapability({
    required this.capability,
    required this.moduleId,
    required this.resolvedPlanDigest,
    required this.subject,
    required Set<AuthoringActionEffect> effects,
    required Set<AuthoringOperation> operations,
  }) : effects = Set<AuthoringActionEffect>.unmodifiable(effects),
       operations = Set<AuthoringOperation>.unmodifiable(operations) {
    _authoringId(capability.id, 'ModuleCapability');
    _authoringExternalId(moduleId, 'Module');
    if (capability.id != 'experience.authoring' ||
        capability.version != 1 ||
        moduleId.value != 'authoring.local') {
      throw ArgumentError(
        'AuthoringCapability must declare authoring.local support for experience.authoring@1',
      );
    }
    if (this.effects.isEmpty || this.operations.isEmpty) {
      throw ArgumentError('AuthoringCapability support sets must be non-empty');
    }
    for (final operation in this.operations) {
      if (!this.effects.contains(authoringEffectFor(operation))) {
        throw ArgumentError(
          'AuthoringCapability operation lacks its required effect',
        );
      }
    }
  }

  static const int schemaVersion = 1;
  final ModuleCapabilityRef capability;
  final ModuleId moduleId;
  final Digest resolvedPlanDigest;
  final AuthoringSubjectRef subject;
  final Set<AuthoringActionEffect> effects;
  final Set<AuthoringOperation> operations;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AuthoringCapability',
    'capability': capability.toJson(),
    'moduleId': moduleId.value,
    'resolvedPlanDigest': resolvedPlanDigest.value,
    'subject': subject.toJson(),
    'effects': effects.map((value) => value.name).toList()..sort(),
    'operations': operations.map((value) => value.name).toList()..sort(),
    if (includeDigest) 'digest': digest.value,
  };

  factory AuthoringCapability.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'AuthoringCapability', const <String>{
          'capability',
          'moduleId',
          'resolvedPlanDigest',
          'subject',
          'effects',
          'operations',
        });
    final result = AuthoringCapability(
      capability: ModuleCapabilityRef.fromJson(json['capability']),
      moduleId: ModuleId(
        _authoringString(json, 'moduleId', 'AuthoringCapability'),
      ),
      resolvedPlanDigest: Digest(
        _authoringString(json, 'resolvedPlanDigest', 'AuthoringCapability'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      effects: _authoringEnumSet(
        AuthoringActionEffect.values,
        json['effects'],
        'AuthoringCapability.effects',
      ),
      operations: _authoringEnumSet(
        AuthoringOperation.values,
        json['operations'],
        'AuthoringCapability.operations',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'AuthoringCapability');
    return result;
  }
}

/// Short-lived, single-use authority for one exact operation and source head.
final class AuthoringActionGrant {
  AuthoringActionGrant({
    required this.id,
    required this.requestId,
    required this.requestDigest,
    required this.payloadDigest,
    required this.authorityId,
    required this.policyId,
    required this.principalId,
    required this.capabilityDigest,
    required this.subject,
    required this.effect,
    required this.operation,
    required this.expectedDigest,
    required this.expectedSourceDigest,
    required DateTime issuedAt,
    required DateTime expiresAt,
    required this.singleUse,
  }) : issuedAt = issuedAt.toUtc(),
       expiresAt = expiresAt.toUtc() {
    if (!singleUse ||
        !this.expiresAt.isAfter(this.issuedAt) ||
        this.expiresAt.difference(this.issuedAt) > const Duration(minutes: 5) ||
        effect == AuthoringActionEffect.query ||
        effect != authoringEffectFor(operation)) {
      throw ArgumentError('AuthoringActionGrant is not a valid bounded grant');
    }
  }

  static const int schemaVersion = 1;
  final AuthoringActionGrantId id;
  final AuthoringRequestId requestId;
  final Digest requestDigest;
  final Digest payloadDigest;
  final AuthoringAuthorityId authorityId;
  final AuthoringPolicyId policyId;
  final AuthoringPrincipalId principalId;
  final Digest capabilityDigest;
  final AuthoringSubjectRef subject;
  final AuthoringActionEffect effect;
  final AuthoringOperation operation;
  final Digest expectedDigest;
  final Digest expectedSourceDigest;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final bool singleUse;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AuthoringActionGrant',
    'id': id.value,
    'requestId': requestId.value,
    'requestDigest': requestDigest.value,
    'payloadDigest': payloadDigest.value,
    'authorityId': authorityId.value,
    'policyId': policyId.value,
    'principalId': principalId.value,
    'capabilityDigest': capabilityDigest.value,
    'subject': subject.toJson(),
    'effect': effect.name,
    'operation': operation.name,
    'expectedDigest': expectedDigest.value,
    'expectedSourceDigest': expectedSourceDigest.value,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'singleUse': singleUse,
    if (includeDigest) 'digest': digest.value,
  };

  factory AuthoringActionGrant.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'AuthoringActionGrant', const <String>{
          'id',
          'requestId',
          'requestDigest',
          'payloadDigest',
          'authorityId',
          'policyId',
          'principalId',
          'capabilityDigest',
          'subject',
          'effect',
          'operation',
          'expectedDigest',
          'expectedSourceDigest',
          'issuedAt',
          'expiresAt',
          'singleUse',
        });
    final result = AuthoringActionGrant(
      id: AuthoringActionGrantId(
        _authoringString(json, 'id', 'AuthoringActionGrant'),
      ),
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'AuthoringActionGrant'),
      ),
      requestDigest: _authoringDigest(
        json,
        'requestDigest',
        'AuthoringActionGrant',
      ),
      payloadDigest: _authoringDigest(
        json,
        'payloadDigest',
        'AuthoringActionGrant',
      ),
      authorityId: AuthoringAuthorityId(
        _authoringString(json, 'authorityId', 'AuthoringActionGrant'),
      ),
      policyId: AuthoringPolicyId(
        _authoringString(json, 'policyId', 'AuthoringActionGrant'),
      ),
      principalId: AuthoringPrincipalId(
        _authoringString(json, 'principalId', 'AuthoringActionGrant'),
      ),
      capabilityDigest: _authoringDigest(
        json,
        'capabilityDigest',
        'AuthoringActionGrant',
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      effect: _authoringEnum(
        AuthoringActionEffect.values,
        _authoringString(json, 'effect', 'AuthoringActionGrant'),
        'AuthoringActionGrant.effect',
      ),
      operation: _authoringEnum(
        AuthoringOperation.values,
        _authoringString(json, 'operation', 'AuthoringActionGrant'),
        'AuthoringActionGrant.operation',
      ),
      expectedDigest: _authoringDigest(
        json,
        'expectedDigest',
        'AuthoringActionGrant',
      ),
      expectedSourceDigest: _authoringDigest(
        json,
        'expectedSourceDigest',
        'AuthoringActionGrant',
      ),
      issuedAt: _authoringTime(json, 'issuedAt', 'AuthoringActionGrant'),
      expiresAt: _authoringTime(json, 'expiresAt', 'AuthoringActionGrant'),
      singleUse: _authoringBool(json, 'singleUse', 'AuthoringActionGrant'),
    );
    _authoringVerifyDigest(json, result.digest, 'AuthoringActionGrant');
    return result;
  }
}

abstract interface class AuthoringGrantIntent {
  AuthoringRequestId get requestId;
  Digest get capabilityDigest;
  AuthoringSubjectRef get subject;
  AuthoringActionEffect get effect;
  AuthoringOperation get operation;
  Digest get expectedDigest;
  Digest get expectedSourceDigest;
  Digest get payloadDigest;
  Digest get digest;
}

final class LayoutMoveNodeInput {
  LayoutMoveNodeInput({
    required this.nodeInstanceId,
    required this.toX,
    required this.toY,
  }) {
    _authoringExternalId(nodeInstanceId, 'NodeInstance');
    _authoringCoordinate(toX, 'LayoutMoveNodeInput.toX');
    _authoringCoordinate(toY, 'LayoutMoveNodeInput.toY');
  }

  final NodeInstanceId nodeInstanceId;
  final double toX;
  final double toY;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeInstanceId': nodeInstanceId.value,
    'toX': toX,
    'toY': toY,
  };

  factory LayoutMoveNodeInput.fromJson(Object? value) {
    final json = _authoringObject(value, 'LayoutMoveNodeInput');
    _authoringOnly(json, const <String>{
      'nodeInstanceId',
      'toX',
      'toY',
    }, 'LayoutMoveNodeInput');
    return LayoutMoveNodeInput(
      nodeInstanceId: NodeInstanceId(
        _authoringString(json, 'nodeInstanceId', 'LayoutMoveNodeInput'),
      ),
      toX: _authoringNumber(json, 'toX', 'LayoutMoveNodeInput'),
      toY: _authoringNumber(json, 'toY', 'LayoutMoveNodeInput'),
    );
  }
}

final class LayoutMoveNodeOperation {
  LayoutMoveNodeOperation({
    required this.id,
    required this.nodeInstanceId,
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  }) {
    _authoringExternalId(nodeInstanceId, 'NodeInstance');
    for (final entry in <MapEntry<String, double>>[
      MapEntry<String, double>('fromX', fromX),
      MapEntry<String, double>('fromY', fromY),
      MapEntry<String, double>('toX', toX),
      MapEntry<String, double>('toY', toY),
    ]) {
      _authoringCoordinate(entry.value, 'LayoutMoveNodeOperation.${entry.key}');
    }
    if (fromX == toX && fromY == toY) {
      throw ArgumentError('LayoutMoveNodeOperation must change the frame');
    }
  }

  final LayoutOperationId id;
  final NodeInstanceId nodeInstanceId;
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'kind': 'moveNode',
    'id': id.value,
    'nodeInstanceId': nodeInstanceId.value,
    'fromX': fromX,
    'fromY': fromY,
    'toX': toX,
    'toY': toY,
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutMoveNodeOperation.fromJson(Object? value) {
    final json = _authoringObject(value, 'LayoutMoveNodeOperation');
    _authoringOnly(json, const <String>{
      'kind',
      'id',
      'nodeInstanceId',
      'fromX',
      'fromY',
      'toX',
      'toY',
      'digest',
    }, 'LayoutMoveNodeOperation');
    if (json['kind'] != 'moveNode') {
      throw const FormatException('Layout operation must be moveNode');
    }
    final result = LayoutMoveNodeOperation(
      id: LayoutOperationId(
        _authoringString(json, 'id', 'LayoutMoveNodeOperation'),
      ),
      nodeInstanceId: NodeInstanceId(
        _authoringString(json, 'nodeInstanceId', 'LayoutMoveNodeOperation'),
      ),
      fromX: _authoringNumber(json, 'fromX', 'LayoutMoveNodeOperation'),
      fromY: _authoringNumber(json, 'fromY', 'LayoutMoveNodeOperation'),
      toX: _authoringNumber(json, 'toX', 'LayoutMoveNodeOperation'),
      toY: _authoringNumber(json, 'toY', 'LayoutMoveNodeOperation'),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutMoveNodeOperation');
    return result;
  }
}

final class LayoutDraft {
  LayoutDraft({
    required this.id,
    required this.subject,
    required this.baseLayoutDigest,
    required this.candidateLayoutDigest,
    required this.baseSourceDigest,
    required this.topologyDigest,
    required this.contentSetDigest,
    required List<LayoutMoveNodeOperation> history,
    required this.cursor,
    required this.revision,
    required this.previousDraftDigest,
  }) : history = List<LayoutMoveNodeOperation>.unmodifiable(history) {
    if (this.history.length > experienceAuthoringMaxOperations ||
        cursor < 0 ||
        cursor > this.history.length ||
        this.history.map((item) => item.id).toSet().length !=
            this.history.length) {
      throw ArgumentError('LayoutDraft history or cursor is invalid');
    }
    if (revision < 0 ||
        revision > experienceAuthoringMaxSafeInteger ||
        (revision == 0) != (previousDraftDigest == null)) {
      throw ArgumentError('LayoutDraft revision chain is invalid');
    }
    if (cursor == 0 && candidateLayoutDigest != baseLayoutDigest) {
      throw ArgumentError('An unmodified draft must retain its base layout');
    }
    _authoringRequireEncodedBytes(
      toJson(includeDigest: false),
      'LayoutDraft',
      experienceAuthoringMaxDraftBytes,
    );
  }

  static const int schemaVersion = 1;
  final LayoutDraftId id;
  final AuthoringSubjectRef subject;
  final Digest baseLayoutDigest;
  final Digest candidateLayoutDigest;
  final Digest baseSourceDigest;
  final Digest topologyDigest;
  final Digest contentSetDigest;
  final List<LayoutMoveNodeOperation> history;
  final int cursor;
  final int revision;
  final Digest? previousDraftDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraft',
    'id': id.value,
    'subject': subject.toJson(),
    'baseLayoutDigest': baseLayoutDigest.value,
    'candidateLayoutDigest': candidateLayoutDigest.value,
    'baseSourceDigest': baseSourceDigest.value,
    'topologyDigest': topologyDigest.value,
    'contentSetDigest': contentSetDigest.value,
    'history': history.map((item) => item.toJson()).toList(),
    'cursor': cursor,
    'revision': revision,
    if (previousDraftDigest != null)
      'previousDraftDigest': previousDraftDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraft.fromJson(Object? value) {
    final json = _authoringDocument(value, 'LayoutDraft', const <String>{
      'id',
      'subject',
      'baseLayoutDigest',
      'candidateLayoutDigest',
      'baseSourceDigest',
      'topologyDigest',
      'contentSetDigest',
      'history',
      'cursor',
      'revision',
      'previousDraftDigest',
    });
    final result = LayoutDraft(
      id: LayoutDraftId(_authoringString(json, 'id', 'LayoutDraft')),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      baseLayoutDigest: _authoringDigest(
        json,
        'baseLayoutDigest',
        'LayoutDraft',
      ),
      candidateLayoutDigest: _authoringDigest(
        json,
        'candidateLayoutDigest',
        'LayoutDraft',
      ),
      baseSourceDigest: _authoringDigest(
        json,
        'baseSourceDigest',
        'LayoutDraft',
      ),
      topologyDigest: _authoringDigest(json, 'topologyDigest', 'LayoutDraft'),
      contentSetDigest: _authoringDigest(
        json,
        'contentSetDigest',
        'LayoutDraft',
      ),
      history: _authoringList(
        json,
        'history',
        'LayoutDraft',
        maxItems: experienceAuthoringMaxOperations,
      ).map(LayoutMoveNodeOperation.fromJson).toList(growable: false),
      cursor: _authoringInt(json, 'cursor', 'LayoutDraft'),
      revision: _authoringInt(json, 'revision', 'LayoutDraft'),
      previousDraftDigest: _authoringOptionalDigest(
        json,
        'previousDraftDigest',
        'LayoutDraft',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraft');
    return result;
  }
}

final class LayoutFrameChange {
  LayoutFrameChange({
    required this.nodeInstanceId,
    required this.beforeX,
    required this.beforeY,
    required this.afterX,
    required this.afterY,
  }) {
    _authoringExternalId(nodeInstanceId, 'NodeInstance');
    for (final entry in <MapEntry<String, double>>[
      MapEntry<String, double>('beforeX', beforeX),
      MapEntry<String, double>('beforeY', beforeY),
      MapEntry<String, double>('afterX', afterX),
      MapEntry<String, double>('afterY', afterY),
    ]) {
      _authoringCoordinate(entry.value, 'LayoutFrameChange.${entry.key}');
    }
    if (beforeX == afterX && beforeY == afterY) {
      throw ArgumentError('LayoutFrameChange must describe a change');
    }
  }

  final NodeInstanceId nodeInstanceId;
  final double beforeX;
  final double beforeY;
  final double afterX;
  final double afterY;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeInstanceId': nodeInstanceId.value,
    'beforeX': beforeX,
    'beforeY': beforeY,
    'afterX': afterX,
    'afterY': afterY,
  };

  factory LayoutFrameChange.fromJson(Object? value) {
    final json = _authoringObject(value, 'LayoutFrameChange');
    _authoringOnly(json, const <String>{
      'nodeInstanceId',
      'beforeX',
      'beforeY',
      'afterX',
      'afterY',
    }, 'LayoutFrameChange');
    return LayoutFrameChange(
      nodeInstanceId: NodeInstanceId(
        _authoringString(json, 'nodeInstanceId', 'LayoutFrameChange'),
      ),
      beforeX: _authoringNumber(json, 'beforeX', 'LayoutFrameChange'),
      beforeY: _authoringNumber(json, 'beforeY', 'LayoutFrameChange'),
      afterX: _authoringNumber(json, 'afterX', 'LayoutFrameChange'),
      afterY: _authoringNumber(json, 'afterY', 'LayoutFrameChange'),
    );
  }
}

final class LayoutComparison {
  LayoutComparison({
    required this.topologyDigest,
    required this.projectionId,
    required this.beforeLayoutDigest,
    required this.afterLayoutDigest,
    required List<LayoutFrameChange> changedFrames,
  }) : changedFrames = _authoringSorted(
         changedFrames,
         (item) => item.nodeInstanceId.value,
         'LayoutComparison.changedFrames',
         maxItems: experienceAuthoringMaxOperations,
       ) {
    _authoringExternalId(projectionId, 'ExperienceProjection');
    if (beforeLayoutDigest == afterLayoutDigest || this.changedFrames.isEmpty) {
      throw ArgumentError('LayoutComparison must contain a real change');
    }
  }

  static const int schemaVersion = 1;
  final Digest topologyDigest;
  final ExperienceProjectionId projectionId;
  final Digest beforeLayoutDigest;
  final Digest afterLayoutDigest;
  final List<LayoutFrameChange> changedFrames;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutComparison',
    'topologyDigest': topologyDigest.value,
    'projectionId': projectionId.value,
    'beforeLayoutDigest': beforeLayoutDigest.value,
    'afterLayoutDigest': afterLayoutDigest.value,
    'changedFrames': changedFrames.map((item) => item.toJson()).toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutComparison.fromJson(Object? value) {
    final json = _authoringDocument(value, 'LayoutComparison', const <String>{
      'topologyDigest',
      'projectionId',
      'beforeLayoutDigest',
      'afterLayoutDigest',
      'changedFrames',
    });
    final result = LayoutComparison(
      topologyDigest: _authoringDigest(
        json,
        'topologyDigest',
        'LayoutComparison',
      ),
      projectionId: ExperienceProjectionId(
        _authoringString(json, 'projectionId', 'LayoutComparison'),
      ),
      beforeLayoutDigest: _authoringDigest(
        json,
        'beforeLayoutDigest',
        'LayoutComparison',
      ),
      afterLayoutDigest: _authoringDigest(
        json,
        'afterLayoutDigest',
        'LayoutComparison',
      ),
      changedFrames: _authoringList(
        json,
        'changedFrames',
        'LayoutComparison',
        maxItems: experienceAuthoringMaxOperations,
      ).map(LayoutFrameChange.fromJson).toList(growable: false),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutComparison');
    return result;
  }
}

final class ExperienceChangeSet {
  ExperienceChangeSet({
    required this.id,
    required this.subject,
    required this.baseSourceDigest,
    required this.expectedContentSetDigest,
    required this.draftDigest,
    required this.draftRevision,
    required this.comparison,
    required List<LayoutMoveNodeOperation> operations,
  }) : operations = List<LayoutMoveNodeOperation>.unmodifiable(operations) {
    if (this.operations.isEmpty ||
        this.operations.length > experienceAuthoringMaxOperations ||
        this.operations.map((item) => item.id).toSet().length !=
            this.operations.length ||
        subject.projectionId != comparison.projectionId) {
      throw ArgumentError('ExperienceChangeSet is invalid');
    }
    if (draftRevision <= 0 ||
        draftRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('ExperienceChangeSet requires a mutated draft head');
    }
    _authoringRequireEncodedBytes(
      toJson(includeDigest: false),
      'ExperienceChangeSet',
      experienceAuthoringMaxChangeSetBytes,
    );
  }

  static const int schemaVersion = 1;
  final ExperienceChangeSetId id;
  final AuthoringSubjectRef subject;
  final Digest baseSourceDigest;
  final Digest expectedContentSetDigest;
  final Digest draftDigest;
  final int draftRevision;
  final LayoutComparison comparison;
  final List<LayoutMoveNodeOperation> operations;

  Digest get baseLayoutDigest => comparison.beforeLayoutDigest;
  Digest get candidateLayoutDigest => comparison.afterLayoutDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceChangeSet',
    'id': id.value,
    'subject': subject.toJson(),
    'baseSourceDigest': baseSourceDigest.value,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'draftDigest': draftDigest.value,
    'draftRevision': draftRevision,
    'comparison': comparison.toJson(),
    'operations': operations.map((item) => item.toJson()).toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceChangeSet.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'ExperienceChangeSet', const <String>{
          'id',
          'subject',
          'baseSourceDigest',
          'expectedContentSetDigest',
          'draftDigest',
          'draftRevision',
          'comparison',
          'operations',
        });
    final result = ExperienceChangeSet(
      id: ExperienceChangeSetId(
        _authoringString(json, 'id', 'ExperienceChangeSet'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      baseSourceDigest: _authoringDigest(
        json,
        'baseSourceDigest',
        'ExperienceChangeSet',
      ),
      expectedContentSetDigest: _authoringDigest(
        json,
        'expectedContentSetDigest',
        'ExperienceChangeSet',
      ),
      draftDigest: _authoringDigest(json, 'draftDigest', 'ExperienceChangeSet'),
      draftRevision: _authoringInt(
        json,
        'draftRevision',
        'ExperienceChangeSet',
      ),
      comparison: LayoutComparison.fromJson(json['comparison']),
      operations: _authoringList(
        json,
        'operations',
        'ExperienceChangeSet',
        maxItems: experienceAuthoringMaxOperations,
      ).map(LayoutMoveNodeOperation.fromJson).toList(growable: false),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceChangeSet');
    return result;
  }
}

enum ExperienceReviewSubjectKind { scenario, transition, artifact }

final class ExperienceReviewSubject {
  ExperienceReviewSubject._({
    required this.kind,
    this.scenarioId,
    this.transitionId,
    this.artifactDigest,
  });

  factory ExperienceReviewSubject.scenario(ScenarioId id) =>
      ExperienceReviewSubject._checked(
        kind: ExperienceReviewSubjectKind.scenario,
        scenarioId: id,
      );

  factory ExperienceReviewSubject.transition(TransitionId id) =>
      ExperienceReviewSubject._checked(
        kind: ExperienceReviewSubjectKind.transition,
        transitionId: id,
      );

  factory ExperienceReviewSubject.artifact(Digest digest) =>
      ExperienceReviewSubject._checked(
        kind: ExperienceReviewSubjectKind.artifact,
        artifactDigest: digest,
      );

  final ExperienceReviewSubjectKind kind;
  final ScenarioId? scenarioId;
  final TransitionId? transitionId;
  final Digest? artifactDigest;

  factory ExperienceReviewSubject._checked({
    required ExperienceReviewSubjectKind kind,
    ScenarioId? scenarioId,
    TransitionId? transitionId,
    Digest? artifactDigest,
  }) {
    if (scenarioId != null) _authoringExternalId(scenarioId, 'Scenario');
    if (transitionId != null) _authoringExternalId(transitionId, 'Transition');
    return ExperienceReviewSubject._(
      kind: kind,
      scenarioId: scenarioId,
      transitionId: transitionId,
      artifactDigest: artifactDigest,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    if (scenarioId != null) 'scenarioId': scenarioId!.value,
    if (transitionId != null) 'transitionId': transitionId!.value,
    if (artifactDigest != null) 'artifactDigest': artifactDigest!.value,
  };

  factory ExperienceReviewSubject.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceReviewSubject');
    _authoringOnly(json, const <String>{
      'kind',
      'scenarioId',
      'transitionId',
      'artifactDigest',
    }, 'ExperienceReviewSubject');
    final kind = _authoringEnum(
      ExperienceReviewSubjectKind.values,
      _authoringString(json, 'kind', 'ExperienceReviewSubject'),
      'ExperienceReviewSubject.kind',
    );
    final expectedKeys = switch (kind) {
      ExperienceReviewSubjectKind.scenario => const <String>{
        'kind',
        'scenarioId',
      },
      ExperienceReviewSubjectKind.transition => const <String>{
        'kind',
        'transitionId',
      },
      ExperienceReviewSubjectKind.artifact => const <String>{
        'kind',
        'artifactDigest',
      },
    };
    if (json.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException(
        'ExperienceReviewSubject payload does not match its kind',
      );
    }
    return switch (kind) {
      ExperienceReviewSubjectKind.scenario => ExperienceReviewSubject.scenario(
        ScenarioId(
          _authoringString(json, 'scenarioId', 'ExperienceReviewSubject'),
        ),
      ),
      ExperienceReviewSubjectKind.transition =>
        ExperienceReviewSubject.transition(
          TransitionId(
            _authoringString(json, 'transitionId', 'ExperienceReviewSubject'),
          ),
        ),
      ExperienceReviewSubjectKind.artifact => ExperienceReviewSubject.artifact(
        _authoringDigest(json, 'artifactDigest', 'ExperienceReviewSubject'),
      ),
    };
  }
}

enum ExperienceFindingSeverity { info, warning, blocking }

final class AppendExperienceFindingInput {
  AppendExperienceFindingInput({
    required this.subject,
    required this.severity,
    required this.summary,
    required this.detail,
  }) {
    _authoringText(summary, 'AppendExperienceFindingInput.summary', 512);
    _authoringText(detail, 'AppendExperienceFindingInput.detail', 2048);
  }

  final ExperienceReviewSubject subject;
  final ExperienceFindingSeverity severity;
  final String summary;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'subject': subject.toJson(),
    'severity': severity.name,
    'summary': summary,
    'detail': detail,
  };

  factory AppendExperienceFindingInput.fromJson(Object? value) {
    final json = _authoringObject(value, 'AppendExperienceFindingInput');
    _authoringOnly(json, const <String>{
      'subject',
      'severity',
      'summary',
      'detail',
    }, 'AppendExperienceFindingInput');
    return AppendExperienceFindingInput(
      subject: ExperienceReviewSubject.fromJson(json['subject']),
      severity: _authoringEnum(
        ExperienceFindingSeverity.values,
        _authoringString(json, 'severity', 'AppendExperienceFindingInput'),
        'AppendExperienceFindingInput.severity',
      ),
      summary: _authoringString(
        json,
        'summary',
        'AppendExperienceFindingInput',
        maxLength: 512,
      ),
      detail: _authoringString(
        json,
        'detail',
        'AppendExperienceFindingInput',
        maxLength: 2048,
      ),
    );
  }
}

final class ExperienceFindingRecord {
  ExperienceFindingRecord({
    required this.id,
    required this.subject,
    required this.severity,
    required this.summary,
    required this.detail,
    required this.principalId,
    required this.authorityId,
    required this.grantDigest,
    required DateTime recordedAt,
  }) : recordedAt = recordedAt.toUtc() {
    _authoringText(summary, 'ExperienceFindingRecord.summary', 512);
    _authoringText(detail, 'ExperienceFindingRecord.detail', 2048);
  }

  final ExperienceFindingId id;
  final ExperienceReviewSubject subject;
  final ExperienceFindingSeverity severity;
  final String summary;
  final String detail;
  final AuthoringPrincipalId principalId;
  final AuthoringAuthorityId authorityId;
  final Digest grantDigest;
  final DateTime recordedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'id': id.value,
    'subject': subject.toJson(),
    'severity': severity.name,
    'summary': summary,
    'detail': detail,
    'principalId': principalId.value,
    'authorityId': authorityId.value,
    'grantDigest': grantDigest.value,
    'recordedAt': recordedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceFindingRecord.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceFindingRecord');
    _authoringOnly(json, const <String>{
      'id',
      'subject',
      'severity',
      'summary',
      'detail',
      'principalId',
      'authorityId',
      'grantDigest',
      'recordedAt',
      'digest',
    }, 'ExperienceFindingRecord');
    final input = AppendExperienceFindingInput.fromJson(<String, Object?>{
      'subject': json['subject'],
      'severity': json['severity'],
      'summary': json['summary'],
      'detail': json['detail'],
    });
    final result = ExperienceFindingRecord(
      id: ExperienceFindingId(
        _authoringString(json, 'id', 'ExperienceFindingRecord'),
      ),
      subject: input.subject,
      severity: input.severity,
      summary: input.summary,
      detail: input.detail,
      principalId: AuthoringPrincipalId(
        _authoringString(json, 'principalId', 'ExperienceFindingRecord'),
      ),
      authorityId: AuthoringAuthorityId(
        _authoringString(json, 'authorityId', 'ExperienceFindingRecord'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'ExperienceFindingRecord',
      ),
      recordedAt: _authoringTime(json, 'recordedAt', 'ExperienceFindingRecord'),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceFindingRecord');
    return result;
  }
}

final class ProposeExperienceConceptInput {
  ProposeExperienceConceptInput({
    required this.scenarioId,
    required this.title,
    required this.rationale,
  }) {
    _authoringExternalId(scenarioId, 'Scenario');
    _authoringText(title, 'ProposeExperienceConceptInput.title', 256);
    _authoringText(rationale, 'ProposeExperienceConceptInput.rationale', 1024);
  }

  final ScenarioId scenarioId;
  final String title;
  final String rationale;

  Map<String, Object?> toJson() => <String, Object?>{
    'scenarioId': scenarioId.value,
    'title': title,
    'rationale': rationale,
  };

  factory ProposeExperienceConceptInput.fromJson(Object? value) {
    final json = _authoringObject(value, 'ProposeExperienceConceptInput');
    _authoringOnly(json, const <String>{
      'scenarioId',
      'title',
      'rationale',
    }, 'ProposeExperienceConceptInput');
    return ProposeExperienceConceptInput(
      scenarioId: ScenarioId(
        _authoringString(json, 'scenarioId', 'ProposeExperienceConceptInput'),
      ),
      title: _authoringString(
        json,
        'title',
        'ProposeExperienceConceptInput',
        maxLength: 256,
      ),
      rationale: _authoringString(
        json,
        'rationale',
        'ProposeExperienceConceptInput',
        maxLength: 1024,
      ),
    );
  }
}

final class ExperienceConceptProposalRecord {
  ExperienceConceptProposalRecord({
    required this.id,
    required this.scenarioId,
    required this.lifecycle,
    required this.title,
    required this.rationale,
    required this.principalId,
    required this.authorityId,
    required this.grantDigest,
    required DateTime recordedAt,
  }) : recordedAt = recordedAt.toUtc() {
    _authoringExternalId(scenarioId, 'Scenario');
    if (lifecycle != ScenarioLifecycle.concept) {
      throw ArgumentError('Concept proposals must remain explicitly concept');
    }
    _authoringText(title, 'ExperienceConceptProposalRecord.title', 256);
    _authoringText(
      rationale,
      'ExperienceConceptProposalRecord.rationale',
      1024,
    );
  }

  final ExperienceConceptProposalId id;
  final ScenarioId scenarioId;
  final ScenarioLifecycle lifecycle;
  final String title;
  final String rationale;
  final AuthoringPrincipalId principalId;
  final AuthoringAuthorityId authorityId;
  final Digest grantDigest;
  final DateTime recordedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'id': id.value,
    'scenarioId': scenarioId.value,
    'lifecycle': lifecycle.name,
    'title': title,
    'rationale': rationale,
    'principalId': principalId.value,
    'authorityId': authorityId.value,
    'grantDigest': grantDigest.value,
    'recordedAt': recordedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceConceptProposalRecord.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceConceptProposalRecord');
    _authoringOnly(json, const <String>{
      'id',
      'scenarioId',
      'lifecycle',
      'title',
      'rationale',
      'principalId',
      'authorityId',
      'grantDigest',
      'recordedAt',
      'digest',
    }, 'ExperienceConceptProposalRecord');
    final result = ExperienceConceptProposalRecord(
      id: ExperienceConceptProposalId(
        _authoringString(json, 'id', 'ExperienceConceptProposalRecord'),
      ),
      scenarioId: ScenarioId(
        _authoringString(json, 'scenarioId', 'ExperienceConceptProposalRecord'),
      ),
      lifecycle: _authoringEnum(
        ScenarioLifecycle.values,
        _authoringString(json, 'lifecycle', 'ExperienceConceptProposalRecord'),
        'ExperienceConceptProposalRecord.lifecycle',
      ),
      title: _authoringString(
        json,
        'title',
        'ExperienceConceptProposalRecord',
        maxLength: 256,
      ),
      rationale: _authoringString(
        json,
        'rationale',
        'ExperienceConceptProposalRecord',
        maxLength: 1024,
      ),
      principalId: AuthoringPrincipalId(
        _authoringString(
          json,
          'principalId',
          'ExperienceConceptProposalRecord',
        ),
      ),
      authorityId: AuthoringAuthorityId(
        _authoringString(
          json,
          'authorityId',
          'ExperienceConceptProposalRecord',
        ),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'ExperienceConceptProposalRecord',
      ),
      recordedAt: _authoringTime(
        json,
        'recordedAt',
        'ExperienceConceptProposalRecord',
      ),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceConceptProposalRecord',
    );
    return result;
  }
}

final class AppendExperienceReviewCommentInput {
  AppendExperienceReviewCommentInput({
    required this.subject,
    required this.body,
  }) {
    _authoringText(body, 'AppendExperienceReviewCommentInput.body', 1024);
  }

  final ExperienceReviewSubject subject;
  final String body;

  Map<String, Object?> toJson() => <String, Object?>{
    'subject': subject.toJson(),
    'body': body,
  };

  factory AppendExperienceReviewCommentInput.fromJson(Object? value) {
    final json = _authoringObject(value, 'AppendExperienceReviewCommentInput');
    _authoringOnly(json, const <String>{
      'subject',
      'body',
    }, 'AppendExperienceReviewCommentInput');
    return AppendExperienceReviewCommentInput(
      subject: ExperienceReviewSubject.fromJson(json['subject']),
      body: _authoringString(
        json,
        'body',
        'AppendExperienceReviewCommentInput',
        maxLength: 1024,
      ),
    );
  }
}

final class ExperienceReviewCommentRecord {
  ExperienceReviewCommentRecord({
    required this.id,
    required this.sequence,
    required this.subject,
    required this.principalId,
    required this.authorityId,
    required this.grantDigest,
    required this.body,
    required DateTime recordedAt,
    this.previousCommentDigest,
  }) : recordedAt = recordedAt.toUtc() {
    if (sequence <= 0 ||
        sequence > experienceAuthoringMaxSafeInteger ||
        (sequence == 1) != (previousCommentDigest == null)) {
      throw ArgumentError('ExperienceReviewCommentRecord chain is invalid');
    }
    _authoringText(body, 'ExperienceReviewCommentRecord.body', 1024);
  }

  final ExperienceReviewCommentId id;
  final int sequence;
  final ExperienceReviewSubject subject;
  final AuthoringPrincipalId principalId;
  final AuthoringAuthorityId authorityId;
  final Digest grantDigest;
  final String body;
  final DateTime recordedAt;
  final Digest? previousCommentDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'id': id.value,
    'sequence': sequence,
    'subject': subject.toJson(),
    'principalId': principalId.value,
    'authorityId': authorityId.value,
    'grantDigest': grantDigest.value,
    'body': body,
    'recordedAt': recordedAt.toIso8601String(),
    if (previousCommentDigest != null)
      'previousCommentDigest': previousCommentDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewCommentRecord.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceReviewCommentRecord');
    _authoringOnly(json, const <String>{
      'id',
      'sequence',
      'subject',
      'principalId',
      'authorityId',
      'grantDigest',
      'body',
      'recordedAt',
      'previousCommentDigest',
      'digest',
    }, 'ExperienceReviewCommentRecord');
    final result = ExperienceReviewCommentRecord(
      id: ExperienceReviewCommentId(
        _authoringString(json, 'id', 'ExperienceReviewCommentRecord'),
      ),
      sequence: _authoringInt(
        json,
        'sequence',
        'ExperienceReviewCommentRecord',
      ),
      subject: ExperienceReviewSubject.fromJson(json['subject']),
      principalId: AuthoringPrincipalId(
        _authoringString(json, 'principalId', 'ExperienceReviewCommentRecord'),
      ),
      authorityId: AuthoringAuthorityId(
        _authoringString(json, 'authorityId', 'ExperienceReviewCommentRecord'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'ExperienceReviewCommentRecord',
      ),
      body: _authoringString(
        json,
        'body',
        'ExperienceReviewCommentRecord',
        maxLength: 1024,
      ),
      recordedAt: _authoringTime(
        json,
        'recordedAt',
        'ExperienceReviewCommentRecord',
      ),
      previousCommentDigest: _authoringOptionalDigest(
        json,
        'previousCommentDigest',
        'ExperienceReviewCommentRecord',
      ),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceReviewCommentRecord',
    );
    return result;
  }
}

final class ExecutableReviewGuideBinding {
  ExecutableReviewGuideBinding({
    required this.catalogDigest,
    required this.applicationId,
    required this.reviewGuideId,
    required this.stepId,
    required this.scenarioId,
    required this.bindingId,
  }) {
    _authoringExternalId(applicationId, 'Application');
    _authoringExternalId(reviewGuideId, 'ReviewGuide');
    _authoringExternalId(scenarioId, 'Scenario');
    _authoringExternalId(bindingId, 'ScenarioExecutionBinding');
    _authoringId(stepId, 'ReviewGuideStep');
  }

  final Digest catalogDigest;
  final ApplicationId applicationId;
  final ReviewGuideId reviewGuideId;
  final String stepId;
  final ScenarioId scenarioId;
  final ScenarioExecutionBindingId bindingId;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'catalogDigest': catalogDigest.value,
    'applicationId': applicationId.value,
    'reviewGuideId': reviewGuideId.value,
    'stepId': stepId,
    'scenarioId': scenarioId.value,
    'bindingId': bindingId.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExecutableReviewGuideBinding.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExecutableReviewGuideBinding');
    _authoringOnly(json, const <String>{
      'catalogDigest',
      'applicationId',
      'reviewGuideId',
      'stepId',
      'scenarioId',
      'bindingId',
      'digest',
    }, 'ExecutableReviewGuideBinding');
    final result = ExecutableReviewGuideBinding(
      catalogDigest: _authoringDigest(
        json,
        'catalogDigest',
        'ExecutableReviewGuideBinding',
      ),
      applicationId: ApplicationId(
        _authoringString(json, 'applicationId', 'ExecutableReviewGuideBinding'),
      ),
      reviewGuideId: ReviewGuideId(
        _authoringString(json, 'reviewGuideId', 'ExecutableReviewGuideBinding'),
      ),
      stepId: _authoringString(json, 'stepId', 'ExecutableReviewGuideBinding'),
      scenarioId: ScenarioId(
        _authoringString(json, 'scenarioId', 'ExecutableReviewGuideBinding'),
      ),
      bindingId: ScenarioExecutionBindingId(
        _authoringString(json, 'bindingId', 'ExecutableReviewGuideBinding'),
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'ExecutableReviewGuideBinding');
    return result;
  }
}

enum AutomatedAcceptanceOutcome { passed, failed }

final class AutomatedAcceptanceRecord {
  AutomatedAcceptanceRecord({
    required this.changeSetDigest,
    required this.evaluatorId,
    required this.outcome,
    required this.summary,
    required DateTime recordedAt,
  }) : recordedAt = recordedAt.toUtc() {
    if (evaluatorId != projectionLayoutSafetyEvaluatorId ||
        summary != projectionLayoutSafetySummary(outcome)) {
      throw ArgumentError(
        'Automated acceptance must be the versioned layout-safety evaluator',
      );
    }
    _authoringText(summary, 'AutomatedAcceptanceRecord.summary', 1024);
  }

  final Digest changeSetDigest;
  final String evaluatorId;
  final AutomatedAcceptanceOutcome outcome;
  final String summary;
  final DateTime recordedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'changeSetDigest': changeSetDigest.value,
    'evaluatorId': evaluatorId,
    'outcome': outcome.name,
    'summary': summary,
    'recordedAt': recordedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory AutomatedAcceptanceRecord.fromJson(Object? value) {
    final json = _authoringObject(value, 'AutomatedAcceptanceRecord');
    _authoringOnly(json, const <String>{
      'changeSetDigest',
      'evaluatorId',
      'outcome',
      'summary',
      'recordedAt',
      'digest',
    }, 'AutomatedAcceptanceRecord');
    final result = AutomatedAcceptanceRecord(
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'AutomatedAcceptanceRecord',
      ),
      evaluatorId: _authoringString(
        json,
        'evaluatorId',
        'AutomatedAcceptanceRecord',
      ),
      outcome: _authoringEnum(
        AutomatedAcceptanceOutcome.values,
        _authoringString(json, 'outcome', 'AutomatedAcceptanceRecord'),
        'AutomatedAcceptanceRecord.outcome',
      ),
      summary: _authoringString(
        json,
        'summary',
        'AutomatedAcceptanceRecord',
        maxLength: 1024,
      ),
      recordedAt: _authoringTime(
        json,
        'recordedAt',
        'AutomatedAcceptanceRecord',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'AutomatedAcceptanceRecord');
    return result;
  }
}

String projectionLayoutSafetySummary(AutomatedAcceptanceOutcome outcome) =>
    switch (outcome) {
      AutomatedAcceptanceOutcome.passed => projectionLayoutSafetyPassedSummary,
      AutomatedAcceptanceOutcome.failed => projectionLayoutSafetyFailedSummary,
    };

enum ExperienceHumanDecision { approve, reject }

final class AppendExperienceHumanDecisionInput {
  AppendExperienceHumanDecisionInput({
    required this.decision,
    required this.rationale,
  }) {
    _authoringText(
      rationale,
      'AppendExperienceHumanDecisionInput.rationale',
      1024,
    );
  }

  final ExperienceHumanDecision decision;
  final String rationale;

  Map<String, Object?> toJson() => <String, Object?>{
    'decision': decision.name,
    'rationale': rationale,
  };

  factory AppendExperienceHumanDecisionInput.fromJson(Object? value) {
    final json = _authoringObject(value, 'AppendExperienceHumanDecisionInput');
    _authoringOnly(json, const <String>{
      'decision',
      'rationale',
    }, 'AppendExperienceHumanDecisionInput');
    return AppendExperienceHumanDecisionInput(
      decision: _authoringEnum(
        ExperienceHumanDecision.values,
        _authoringString(
          json,
          'decision',
          'AppendExperienceHumanDecisionInput',
        ),
        'AppendExperienceHumanDecisionInput.decision',
      ),
      rationale: _authoringString(
        json,
        'rationale',
        'AppendExperienceHumanDecisionInput',
        maxLength: 1024,
      ),
    );
  }
}

final class ExperienceHumanDecisionRecord {
  ExperienceHumanDecisionRecord({
    required this.id,
    required this.sequence,
    required this.changeSetDigest,
    required this.reviewPacketDigest,
    required this.principalId,
    required this.authorityId,
    required this.grantDigest,
    required this.decision,
    required this.rationale,
    required DateTime recordedAt,
    this.previousDecisionDigest,
  }) : recordedAt = recordedAt.toUtc() {
    if (sequence <= 0 ||
        sequence > experienceAuthoringMaxSafeInteger ||
        (sequence == 1) != (previousDecisionDigest == null)) {
      throw ArgumentError('ExperienceHumanDecisionRecord chain is invalid');
    }
    _authoringText(rationale, 'ExperienceHumanDecisionRecord.rationale', 1024);
  }

  final ExperienceHumanDecisionId id;
  final int sequence;
  final Digest changeSetDigest;
  final Digest reviewPacketDigest;
  final AuthoringPrincipalId principalId;
  final AuthoringAuthorityId authorityId;
  final Digest grantDigest;
  final ExperienceHumanDecision decision;
  final String rationale;
  final DateTime recordedAt;
  final Digest? previousDecisionDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'id': id.value,
    'sequence': sequence,
    'changeSetDigest': changeSetDigest.value,
    'reviewPacketDigest': reviewPacketDigest.value,
    'principalId': principalId.value,
    'authorityId': authorityId.value,
    'grantDigest': grantDigest.value,
    'decision': decision.name,
    'rationale': rationale,
    'recordedAt': recordedAt.toIso8601String(),
    if (previousDecisionDigest != null)
      'previousDecisionDigest': previousDecisionDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceHumanDecisionRecord.fromJson(Object? value) {
    final json = _authoringObject(value, 'ExperienceHumanDecisionRecord');
    _authoringOnly(json, const <String>{
      'id',
      'sequence',
      'changeSetDigest',
      'reviewPacketDigest',
      'principalId',
      'authorityId',
      'grantDigest',
      'decision',
      'rationale',
      'recordedAt',
      'previousDecisionDigest',
      'digest',
    }, 'ExperienceHumanDecisionRecord');
    final result = ExperienceHumanDecisionRecord(
      id: ExperienceHumanDecisionId(
        _authoringString(json, 'id', 'ExperienceHumanDecisionRecord'),
      ),
      sequence: _authoringInt(
        json,
        'sequence',
        'ExperienceHumanDecisionRecord',
      ),
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'ExperienceHumanDecisionRecord',
      ),
      reviewPacketDigest: _authoringDigest(
        json,
        'reviewPacketDigest',
        'ExperienceHumanDecisionRecord',
      ),
      principalId: AuthoringPrincipalId(
        _authoringString(json, 'principalId', 'ExperienceHumanDecisionRecord'),
      ),
      authorityId: AuthoringAuthorityId(
        _authoringString(json, 'authorityId', 'ExperienceHumanDecisionRecord'),
      ),
      grantDigest: _authoringDigest(
        json,
        'grantDigest',
        'ExperienceHumanDecisionRecord',
      ),
      decision: _authoringEnum(
        ExperienceHumanDecision.values,
        _authoringString(json, 'decision', 'ExperienceHumanDecisionRecord'),
        'ExperienceHumanDecisionRecord.decision',
      ),
      rationale: _authoringString(
        json,
        'rationale',
        'ExperienceHumanDecisionRecord',
        maxLength: 1024,
      ),
      recordedAt: _authoringTime(
        json,
        'recordedAt',
        'ExperienceHumanDecisionRecord',
      ),
      previousDecisionDigest: _authoringOptionalDigest(
        json,
        'previousDecisionDigest',
        'ExperienceHumanDecisionRecord',
      ),
    );
    _authoringVerifyDigest(
      json,
      result.digest,
      'ExperienceHumanDecisionRecord',
    );
    return result;
  }
}

final class ExperienceReviewPacket {
  ExperienceReviewPacket({
    required this.id,
    required this.subject,
    required this.changeSetId,
    required this.changeSetDigest,
    required this.comparisonDigest,
    required this.baseSourceDigest,
    required List<ExperienceFindingRecord> findings,
    required List<ExperienceConceptProposalRecord> concepts,
    required List<ExperienceReviewCommentRecord> comments,
    required this.reviewGuideBinding,
    required this.automatedAcceptance,
    required List<ExperienceHumanDecisionRecord> humanDecisions,
    required this.revision,
    required this.previousReviewPacketDigest,
  }) : findings = _authoringSorted(
         findings,
         (item) => item.id.value,
         'ExperienceReviewPacket.findings',
         maxItems: experienceAuthoringMaxFindings,
       ),
       concepts = _authoringSorted(
         concepts,
         (item) => item.id.value,
         'ExperienceReviewPacket.concepts',
         maxItems: experienceAuthoringMaxConcepts,
       ),
       comments = List<ExperienceReviewCommentRecord>.unmodifiable(comments),
       humanDecisions = List<ExperienceHumanDecisionRecord>.unmodifiable(
         humanDecisions,
       ) {
    if (this.comments.length > experienceAuthoringMaxComments ||
        this.humanDecisions.length > experienceAuthoringMaxDecisions ||
        (this.humanDecisions.isNotEmpty && automatedAcceptance == null) ||
        reviewGuideBinding.applicationId != subject.applicationId ||
        this.concepts.map((concept) => concept.scenarioId).toSet().length !=
            this.concepts.length ||
        (automatedAcceptance != null &&
            automatedAcceptance!.changeSetDigest != changeSetDigest)) {
      throw ArgumentError('ExperienceReviewPacket exceeds its bounded profile');
    }
    _authoringValidateCommentChain(this.comments);
    _authoringValidateDecisionChain(this.humanDecisions, changeSetDigest);
    if (revision < 0 ||
        revision > experienceAuthoringMaxSafeInteger ||
        (revision == 0) != (previousReviewPacketDigest == null)) {
      throw ArgumentError('ExperienceReviewPacket revision chain is invalid');
    }
    _authoringRequireEncodedBytes(
      toJson(includeDigest: false),
      'ExperienceReviewPacket',
      experienceAuthoringMaxReviewPacketBytes,
    );
  }

  static const int schemaVersion = 1;
  final ExperienceReviewPacketId id;
  final AuthoringSubjectRef subject;
  final ExperienceChangeSetId changeSetId;
  final Digest changeSetDigest;
  final Digest comparisonDigest;
  final Digest baseSourceDigest;
  final List<ExperienceFindingRecord> findings;
  final List<ExperienceConceptProposalRecord> concepts;
  final List<ExperienceReviewCommentRecord> comments;
  final ExecutableReviewGuideBinding reviewGuideBinding;
  final AutomatedAcceptanceRecord? automatedAcceptance;
  final List<ExperienceHumanDecisionRecord> humanDecisions;
  final int revision;
  final Digest? previousReviewPacketDigest;

  ExperienceHumanDecisionRecord? get headDecision =>
      humanDecisions.isEmpty ? null : humanDecisions.last;

  bool get isPromotable =>
      automatedAcceptance?.outcome == AutomatedAcceptanceOutcome.passed &&
      headDecision?.decision == ExperienceHumanDecision.approve &&
      headDecision?.reviewPacketDigest == previousReviewPacketDigest &&
      !findings.any(
        (finding) => finding.severity == ExperienceFindingSeverity.blocking,
      );

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceReviewPacket',
    'id': id.value,
    'subject': subject.toJson(),
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
    'comparisonDigest': comparisonDigest.value,
    'baseSourceDigest': baseSourceDigest.value,
    'findings': findings.map((item) => item.toJson()).toList(),
    'concepts': concepts.map((item) => item.toJson()).toList(),
    'comments': comments.map((item) => item.toJson()).toList(),
    'reviewGuideBinding': reviewGuideBinding.toJson(),
    if (automatedAcceptance != null)
      'automatedAcceptance': automatedAcceptance!.toJson(),
    'humanDecisions': humanDecisions.map((item) => item.toJson()).toList(),
    'revision': revision,
    if (previousReviewPacketDigest != null)
      'previousReviewPacketDigest': previousReviewPacketDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceReviewPacket.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'ExperienceReviewPacket', const <String>{
          'id',
          'subject',
          'changeSetId',
          'changeSetDigest',
          'comparisonDigest',
          'baseSourceDigest',
          'findings',
          'concepts',
          'comments',
          'reviewGuideBinding',
          'automatedAcceptance',
          'humanDecisions',
          'revision',
          'previousReviewPacketDigest',
        });
    final result = ExperienceReviewPacket(
      id: ExperienceReviewPacketId(
        _authoringString(json, 'id', 'ExperienceReviewPacket'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      changeSetId: ExperienceChangeSetId(
        _authoringString(json, 'changeSetId', 'ExperienceReviewPacket'),
      ),
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'ExperienceReviewPacket',
      ),
      comparisonDigest: _authoringDigest(
        json,
        'comparisonDigest',
        'ExperienceReviewPacket',
      ),
      baseSourceDigest: _authoringDigest(
        json,
        'baseSourceDigest',
        'ExperienceReviewPacket',
      ),
      findings: _authoringList(
        json,
        'findings',
        'ExperienceReviewPacket',
        maxItems: experienceAuthoringMaxFindings,
      ).map(ExperienceFindingRecord.fromJson).toList(growable: false),
      concepts: _authoringList(
        json,
        'concepts',
        'ExperienceReviewPacket',
        maxItems: experienceAuthoringMaxConcepts,
      ).map(ExperienceConceptProposalRecord.fromJson).toList(growable: false),
      comments: _authoringList(
        json,
        'comments',
        'ExperienceReviewPacket',
        maxItems: experienceAuthoringMaxComments,
      ).map(ExperienceReviewCommentRecord.fromJson).toList(growable: false),
      reviewGuideBinding: ExecutableReviewGuideBinding.fromJson(
        json['reviewGuideBinding'],
      ),
      automatedAcceptance: json.containsKey('automatedAcceptance')
          ? AutomatedAcceptanceRecord.fromJson(json['automatedAcceptance'])
          : null,
      humanDecisions: _authoringList(
        json,
        'humanDecisions',
        'ExperienceReviewPacket',
        maxItems: experienceAuthoringMaxDecisions,
      ).map(ExperienceHumanDecisionRecord.fromJson).toList(growable: false),
      revision: _authoringInt(json, 'revision', 'ExperienceReviewPacket'),
      previousReviewPacketDigest: _authoringOptionalDigest(
        json,
        'previousReviewPacketDigest',
        'ExperienceReviewPacket',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperienceReviewPacket');
    return result;
  }
}

/// Durable, authority-free tombstone proving that an owner released a draft.
final class LayoutDraftAbandonReceipt {
  LayoutDraftAbandonReceipt({
    required this.id,
    required this.requestId,
    required this.subject,
    required this.draftId,
    required this.finalDraftDigest,
    required this.finalDraftRevision,
    required this.sourceDigest,
    required DateTime abandonedAt,
  }) : abandonedAt = abandonedAt.toUtc() {
    if (finalDraftRevision < 0 ||
        finalDraftRevision > experienceAuthoringMaxSafeInteger) {
      throw ArgumentError('Abandon receipt has an invalid draft revision');
    }
  }

  static const int schemaVersion = 1;
  final LayoutDraftAbandonReceiptId id;
  final AuthoringRequestId requestId;
  final AuthoringSubjectRef subject;
  final LayoutDraftId draftId;
  final Digest finalDraftDigest;
  final int finalDraftRevision;
  final Digest sourceDigest;
  final DateTime abandonedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'LayoutDraftAbandonReceipt',
    'id': id.value,
    'requestId': requestId.value,
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'finalDraftDigest': finalDraftDigest.value,
    'finalDraftRevision': finalDraftRevision,
    'sourceDigest': sourceDigest.value,
    'abandonedAt': abandonedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory LayoutDraftAbandonReceipt.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'LayoutDraftAbandonReceipt', const <String>{
          'id',
          'requestId',
          'subject',
          'draftId',
          'finalDraftDigest',
          'finalDraftRevision',
          'sourceDigest',
          'abandonedAt',
        });
    final result = LayoutDraftAbandonReceipt(
      id: LayoutDraftAbandonReceiptId(
        _authoringString(json, 'id', 'LayoutDraftAbandonReceipt'),
      ),
      requestId: AuthoringRequestId(
        _authoringString(json, 'requestId', 'LayoutDraftAbandonReceipt'),
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'LayoutDraftAbandonReceipt'),
      ),
      finalDraftDigest: _authoringDigest(
        json,
        'finalDraftDigest',
        'LayoutDraftAbandonReceipt',
      ),
      finalDraftRevision: _authoringInt(
        json,
        'finalDraftRevision',
        'LayoutDraftAbandonReceipt',
      ),
      sourceDigest: _authoringDigest(
        json,
        'sourceDigest',
        'LayoutDraftAbandonReceipt',
      ),
      abandonedAt: _authoringTime(
        json,
        'abandonedAt',
        'LayoutDraftAbandonReceipt',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'LayoutDraftAbandonReceipt');
    return result;
  }
}

/// Durable, sanitized receipt for a completed atomic promotion.
final class ExperiencePromotionReceipt {
  ExperiencePromotionReceipt({
    required this.id,
    required this.sequence,
    required this.previousReceiptDigest,
    required this.subject,
    required this.draftId,
    required this.draftDigest,
    required this.draftRevision,
    required this.sourceDigest,
    required this.resultSourceDigest,
    required this.previousContentSetDigest,
    required this.resultContentSetDigest,
    required this.layoutDigest,
    required this.changeSetId,
    required this.changeSetDigest,
    required this.reviewPacketId,
    required this.reviewPacketDigest,
    required DateTime promotedAt,
  }) : promotedAt = promotedAt.toUtc() {
    if (sequence <= 0 ||
        sequence > experienceAuthoringMaxSafeInteger ||
        (sequence == 1) != (previousReceiptDigest == null) ||
        draftRevision <= 0 ||
        draftRevision > experienceAuthoringMaxSafeInteger ||
        sourceDigest == resultSourceDigest ||
        previousContentSetDigest == resultContentSetDigest) {
      throw ArgumentError('Promotion receipt has invalid durable fences');
    }
  }

  static const int schemaVersion = 1;
  final ExperiencePromotionReceiptId id;
  final int sequence;
  final Digest? previousReceiptDigest;
  final AuthoringSubjectRef subject;
  final LayoutDraftId draftId;
  final Digest draftDigest;
  final int draftRevision;
  final Digest sourceDigest;
  final Digest resultSourceDigest;
  final Digest previousContentSetDigest;
  final Digest resultContentSetDigest;
  final Digest layoutDigest;
  final ExperienceChangeSetId changeSetId;
  final Digest changeSetDigest;
  final ExperienceReviewPacketId reviewPacketId;
  final Digest reviewPacketDigest;
  final DateTime promotedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperiencePromotionReceipt',
    'id': id.value,
    'sequence': sequence,
    if (previousReceiptDigest != null)
      'previousReceiptDigest': previousReceiptDigest!.value,
    'subject': subject.toJson(),
    'draftId': draftId.value,
    'draftDigest': draftDigest.value,
    'draftRevision': draftRevision,
    'sourceDigest': sourceDigest.value,
    'resultSourceDigest': resultSourceDigest.value,
    'previousContentSetDigest': previousContentSetDigest.value,
    'resultContentSetDigest': resultContentSetDigest.value,
    'layoutDigest': layoutDigest.value,
    'changeSetId': changeSetId.value,
    'changeSetDigest': changeSetDigest.value,
    'reviewPacketId': reviewPacketId.value,
    'reviewPacketDigest': reviewPacketDigest.value,
    'promotedAt': promotedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperiencePromotionReceipt.fromJson(Object? value) {
    final json =
        _authoringDocument(value, 'ExperiencePromotionReceipt', const <String>{
          'id',
          'sequence',
          'previousReceiptDigest',
          'subject',
          'draftId',
          'draftDigest',
          'draftRevision',
          'sourceDigest',
          'resultSourceDigest',
          'previousContentSetDigest',
          'resultContentSetDigest',
          'layoutDigest',
          'changeSetId',
          'changeSetDigest',
          'reviewPacketId',
          'reviewPacketDigest',
          'promotedAt',
        });
    final result = ExperiencePromotionReceipt(
      id: ExperiencePromotionReceiptId(
        _authoringString(json, 'id', 'ExperiencePromotionReceipt'),
      ),
      sequence: _authoringInt(json, 'sequence', 'ExperiencePromotionReceipt'),
      previousReceiptDigest: _authoringOptionalDigest(
        json,
        'previousReceiptDigest',
        'ExperiencePromotionReceipt',
      ),
      subject: AuthoringSubjectRef.fromJson(json['subject']),
      draftId: LayoutDraftId(
        _authoringString(json, 'draftId', 'ExperiencePromotionReceipt'),
      ),
      draftDigest: _authoringDigest(
        json,
        'draftDigest',
        'ExperiencePromotionReceipt',
      ),
      draftRevision: _authoringInt(
        json,
        'draftRevision',
        'ExperiencePromotionReceipt',
      ),
      sourceDigest: _authoringDigest(
        json,
        'sourceDigest',
        'ExperiencePromotionReceipt',
      ),
      resultSourceDigest: _authoringDigest(
        json,
        'resultSourceDigest',
        'ExperiencePromotionReceipt',
      ),
      previousContentSetDigest: _authoringDigest(
        json,
        'previousContentSetDigest',
        'ExperiencePromotionReceipt',
      ),
      resultContentSetDigest: _authoringDigest(
        json,
        'resultContentSetDigest',
        'ExperiencePromotionReceipt',
      ),
      layoutDigest: _authoringDigest(
        json,
        'layoutDigest',
        'ExperiencePromotionReceipt',
      ),
      changeSetId: ExperienceChangeSetId(
        _authoringString(json, 'changeSetId', 'ExperiencePromotionReceipt'),
      ),
      changeSetDigest: _authoringDigest(
        json,
        'changeSetDigest',
        'ExperiencePromotionReceipt',
      ),
      reviewPacketId: ExperienceReviewPacketId(
        _authoringString(json, 'reviewPacketId', 'ExperiencePromotionReceipt'),
      ),
      reviewPacketDigest: _authoringDigest(
        json,
        'reviewPacketDigest',
        'ExperiencePromotionReceipt',
      ),
      promotedAt: _authoringTime(
        json,
        'promotedAt',
        'ExperiencePromotionReceipt',
      ),
    );
    _authoringVerifyDigest(json, result.digest, 'ExperiencePromotionReceipt');
    return result;
  }
}

void _authoringValidateCommentChain(
  List<ExperienceReviewCommentRecord> values,
) {
  for (var index = 0; index < values.length; index += 1) {
    final value = values[index];
    final previous = index == 0 ? null : values[index - 1].digest;
    if (value.sequence != index + 1 ||
        value.previousCommentDigest != previous) {
      throw ArgumentError('Experience review comment chain is not append-only');
    }
  }
}

void _authoringValidateDecisionChain(
  List<ExperienceHumanDecisionRecord> values,
  Digest changeSetDigest,
) {
  for (var index = 0; index < values.length; index += 1) {
    final value = values[index];
    final previous = index == 0 ? null : values[index - 1].digest;
    if (value.sequence != index + 1 ||
        value.previousDecisionDigest != previous ||
        value.changeSetDigest != changeSetDigest) {
      throw ArgumentError('Experience human decision chain is not append-only');
    }
  }
}

void _authoringId(String value, String kind) {
  OpaqueId.validate(value, kind);
  if (utf8.encode(value).length > 128) {
    throw FormatException('$kind ID exceeds 128 bytes');
  }
}

void _authoringExternalId(OpaqueId value, String kind) {
  if (utf8.encode(value.value).length > 128) {
    throw ArgumentError('$kind ID exceeds 128 UTF-8 bytes');
  }
}

void _authoringCoordinate(double value, String path) {
  if (!value.isFinite ||
      (value == 0 && value.isNegative) ||
      value < -1000000 ||
      value > 1000000) {
    throw ArgumentError('$path is outside the layout coordinate profile');
  }
}

void _authoringText(String value, String path, int maxLength) {
  if (value.trim().isEmpty || utf8.encode(value).length > maxLength) {
    throw ArgumentError('$path must be a bounded non-empty string');
  }
}

Map<String, Object?> _authoringObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _authoringOnly(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

Map<String, Object?> _authoringDocument(
  Object? value,
  String kind,
  Set<String> fields,
) {
  final json = _authoringObject(value, kind);
  _authoringRequireEncodedBytes(
    json,
    kind,
    experienceAuthoringMaxDocumentBytes,
  );
  _authoringOnly(json, <String>{
    'schemaVersion',
    'kind',
    'digest',
    ...fields,
  }, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind has an invalid version or kind');
  }
  return json;
}

void _authoringRequireEncodedBytes(Object? value, String path, int maxBytes) {
  if (utf8.encode(jsonEncode(value)).length > maxBytes) {
    throw FormatException('$path exceeds its UTF-8 JSON frame profile');
  }
}

Digest _authoringFrameDigest(Map<String, Object?> value) {
  _authoringRequireEncodedBytes(
    value,
    'Experience authoring document',
    experienceAuthoringMaxDocumentBytes,
  );
  return Digest.semantic(value);
}

String _authoringString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 128,
}) {
  final value = json[key];
  if (value is! String ||
      value.trim().isEmpty ||
      utf8.encode(value).length > maxLength) {
    throw FormatException('$path.$key must be a bounded non-empty string');
  }
  return value;
}

bool _authoringBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

int _authoringInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int ||
      value < -experienceAuthoringMaxSafeInteger ||
      value > experienceAuthoringMaxSafeInteger) {
    throw FormatException('$path.$key must be a safe JSON integer');
  }
  return value;
}

double _authoringNumber(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! num) throw FormatException('$path.$key must be a number');
  return value.toDouble();
}

Digest _authoringDigest(Map<String, Object?> json, String key, String path) =>
    Digest(_authoringString(json, key, path, maxLength: 71));

Digest? _authoringOptionalDigest(
  Map<String, Object?> json,
  String key,
  String path,
) => json.containsKey(key) ? _authoringDigest(json, key, path) : null;

DateTime _authoringTime(Map<String, Object?> json, String key, String path) {
  final raw = _authoringString(json, key, path, maxLength: 40);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || parsed.toUtc().toIso8601String() != raw) {
    throw FormatException('$path.$key must be a canonical UTC timestamp');
  }
  return parsed.toUtc();
}

T _authoringEnum<T extends Enum>(List<T> values, String raw, String path) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw FormatException('$path has an unsupported value');
}

Set<T> _authoringEnumSet<T extends Enum>(
  List<T> values,
  Object? raw,
  String path,
) {
  if (raw is! List<Object?> || raw.isEmpty || raw.length > values.length) {
    throw FormatException('$path must be a bounded non-empty array');
  }
  final result = <T>{};
  for (final item in raw) {
    if (item is! String || !result.add(_authoringEnum(values, item, path))) {
      throw FormatException('$path must contain unique enum values');
    }
  }
  return result;
}

Set<T> _authoringOptionalEnumSet<T extends Enum>(
  List<T> values,
  Object? raw,
  String path,
) {
  if (raw is! List<Object?> || raw.length > values.length) {
    throw FormatException('$path must be a bounded array');
  }
  final result = <T>{};
  for (final item in raw) {
    if (item is! String || !result.add(_authoringEnum(values, item, path))) {
      throw FormatException('$path must contain unique enum values');
    }
  }
  return result;
}

List<Object?> _authoringList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?> || value.length > maxItems) {
    throw FormatException('$path.$key exceeds its bounded array profile');
  }
  return value;
}

List<T> _authoringSorted<T>(
  Iterable<T> values,
  String Function(T) key,
  String path, {
  required int maxItems,
}) {
  final result = List<T>.of(values);
  if (result.length > maxItems) throw ArgumentError('$path exceeds $maxItems');
  result.sort((left, right) => key(left).compareTo(key(right)));
  final keys = result.map(key).toList(growable: false);
  if (keys.toSet().length != keys.length) {
    throw ArgumentError('$path contains duplicate IDs');
  }
  return List<T>.unmodifiable(result);
}

void _authoringVerifyDigest(
  Map<String, Object?> json,
  Digest expected,
  String path,
) {
  if (_authoringDigest(json, 'digest', path) != expected) {
    throw FormatException('$path digest mismatch');
  }
}
