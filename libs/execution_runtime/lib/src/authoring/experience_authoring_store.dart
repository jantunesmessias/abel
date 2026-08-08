import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import 'projection_layout_preserving_swap.dart';

enum ExperienceAuthoringStoreErrorCode {
  draftNotFound,
  ownerConflict,
  staleDraft,
  requestConflict,
  grantMismatch,
  grantExpired,
  grantRevoked,
  grantConsumed,
  staleReview,
  promotionConflict,
  quotaExceeded,
}

final class ExperienceAuthoringStoreFailure implements Exception {
  const ExperienceAuthoringStoreFailure(
    this.code, {
    this.currentDigest,
    this.currentRevision,
  });

  final ExperienceAuthoringStoreErrorCode code;
  final Digest? currentDigest;
  final int? currentRevision;
}

/// Host-private durable ownership and CAS metadata for one bounded draft.
final class StoredLayoutDraft {
  const StoredLayoutDraft({
    required this.ownerPrincipalId,
    required this.draft,
    required this.baseLayoutBlobDigest,
  });

  final AuthoringPrincipalId ownerPrincipalId;
  final LayoutDraft draft;
  final Digest baseLayoutBlobDigest;

  Digest get headDigest => draft.digest;
  int get headRevision => draft.revision;
}

final class StoredLayoutDraftOpenResult {
  const StoredLayoutDraftOpenResult({
    required this.storedDraft,
    required this.resumed,
  });

  final StoredLayoutDraft storedDraft;
  final bool resumed;

  AuthoringPrincipalId get ownerPrincipalId => storedDraft.ownerPrincipalId;
  LayoutDraft get draft => storedDraft.draft;
  Digest get baseLayoutBlobDigest => storedDraft.baseLayoutBlobDigest;
}

/// Host-private WAL record. Routing and CAS links never cross the RPC wire.
final class StoredProjectionLayoutPromotion {
  StoredProjectionLayoutPromotion({
    required this.intentId,
    required this.subject,
    required this.relativeSourcePath,
    required this.replaceProtocol,
    required this.replaceProviderKind,
    required this.recoverySlot,
    required this.configurationAuthorityDigest,
    required this.sourceMetadataDigest,
    required this.originalSourceBlobDigest,
    required this.candidateSourceBlobDigest,
    required this.originalCompiledCorpusDigest,
    required this.candidateCompiledCorpusDigest,
    required this.receipt,
    required this.grantDigest,
    this.successAttempt,
    this.rollbackAttempt,
    required DateTime preparedAt,
  }) : preparedAt = preparedAt.toUtc() {
    if (intentId.isEmpty ||
        relativeSourcePath.isEmpty ||
        p.isAbsolute(relativeSourcePath) ||
        p.normalize(relativeSourcePath) != relativeSourcePath ||
        relativeSourcePath == '.' ||
        relativeSourcePath.split('/').contains('..') ||
        replaceProtocol != projectionLayoutPreservingSwapProtocol ||
        replaceProviderKind != projectionLayoutLinuxX64SwapProvider ||
        !_validStoredPromotionRecoverySlot(
          subject: subject,
          relativeSourcePath: relativeSourcePath,
          recoverySlot: recoverySlot,
        ) ||
        subject != receipt.subject ||
        originalSourceBlobDigest == candidateSourceBlobDigest ||
        originalSourceDigest == candidateSourceDigest ||
        originalCompiledCorpusDigest == candidateCompiledCorpusDigest ||
        (successAttempt == null) != (rollbackAttempt == null)) {
      throw ArgumentError('Invalid stored ProjectionLayout promotion');
    }
    final success = successAttempt;
    final rollback = rollbackAttempt;
    if (success != null && rollback != null) {
      if (success.family != StoredAuthoringAttemptFamily.promotionApply ||
          success.isError ||
          rollback.family != StoredAuthoringAttemptFamily.promotionApply ||
          !rollback.isError ||
          success.requestId != rollback.requestId ||
          success.requestDigest != rollback.requestDigest ||
          success.payloadDigest != rollback.payloadDigest ||
          success.subject != subject ||
          rollback.subject != subject ||
          success.effect != AuthoringActionEffect.authoring ||
          rollback.effect != AuthoringActionEffect.authoring ||
          success.operation != AuthoringOperation.promote ||
          rollback.operation != AuthoringOperation.promote ||
          success.grantId == null ||
          success.grantId != rollback.grantId ||
          success.grantDigest != grantDigest ||
          rollback.grantDigest != grantDigest) {
        throw ArgumentError('Invalid stored promotion effect binding');
      }
      final result = ExperiencePromotionApplyResult.fromJson(
        success.terminalJson,
      );
      if (result.receipt.digest != receipt.digest ||
          result.receipt.id != receipt.id ||
          result.head.latestPromotion?.digest != receipt.digest) {
        throw ArgumentError('Promotion success does not bind its receipt');
      }
    }
  }

  final String intentId;
  final AuthoringSubjectRef subject;
  final String relativeSourcePath;
  final String replaceProtocol;
  final String replaceProviderKind;
  final String recoverySlot;
  final Digest configurationAuthorityDigest;
  final Digest sourceMetadataDigest;
  final Digest originalSourceBlobDigest;
  final Digest candidateSourceBlobDigest;
  final Digest originalCompiledCorpusDigest;
  final Digest candidateCompiledCorpusDigest;
  final ExperiencePromotionReceipt receipt;
  final Digest grantDigest;
  final StoredAuthoringAttempt? successAttempt;
  final StoredAuthoringAttempt? rollbackAttempt;
  final DateTime preparedAt;

  Digest get originalSourceDigest => receipt.sourceDigest;
  Digest get candidateSourceDigest => receipt.resultSourceDigest;
}

bool _validStoredPromotionRecoverySlot({
  required AuthoringSubjectRef subject,
  required String relativeSourcePath,
  required String recoverySlot,
}) {
  if (recoverySlot.isEmpty ||
      p.isAbsolute(relativeSourcePath) ||
      p.isAbsolute(recoverySlot) ||
      p.normalize(relativeSourcePath) != relativeSourcePath ||
      p.normalize(recoverySlot) != recoverySlot ||
      recoverySlot == '.' ||
      relativeSourcePath == recoverySlot) {
    return false;
  }
  if (recoverySlot.split('/').contains('..')) return false;
  return recoverySlot ==
      projectionLayoutPromotionRecoverySlot(
        subject: subject,
        relativeSourcePath: relativeSourcePath,
      );
}

final class StoredPromotionReceiptPage {
  StoredPromotionReceiptPage({
    required this.offset,
    required this.limit,
    required this.totalCount,
    required this.previousPageReceiptDigest,
    required List<ExperiencePromotionReceipt> receipts,
  }) : receipts = List<ExperiencePromotionReceipt>.unmodifiable(receipts);

  final int offset;
  final int limit;
  final int totalCount;
  final Digest? previousPageReceiptDigest;
  final List<ExperiencePromotionReceipt> receipts;
}

enum StoredAuthoringGrantState { active, inFlight, consumed, revoked }

/// Closed, durable discriminator for the three grant-intent codecs supported
/// by the v1 authoring journal. This is intentionally independent of
/// `runtimeType`, whose textual form is not stable across AOT compilation or
/// refactors.
enum StoredAuthoringGrantIntentKind {
  authoringGrantRequest('AuthoringGrantRequest'),
  reviewDecisionGrantRequest('ExperienceReviewDecisionGrantRequest'),
  promotionGrantRequest('ExperiencePromotionGrantRequest');

  const StoredAuthoringGrantIntentKind(this.wireName);

  final String wireName;
}

StoredAuthoringGrantIntentKind storedAuthoringGrantIntentKind(
  AuthoringGrantIntent intent,
) => switch (intent) {
  AuthoringGrantRequest() =>
    StoredAuthoringGrantIntentKind.authoringGrantRequest,
  ExperienceReviewDecisionGrantRequest() =>
    StoredAuthoringGrantIntentKind.reviewDecisionGrantRequest,
  ExperiencePromotionGrantRequest() =>
    StoredAuthoringGrantIntentKind.promotionGrantRequest,
  _ => throw ArgumentError('Unsupported authoring grant intent'),
};

Map<String, Object?> storedAuthoringGrantIntentJson(
  AuthoringGrantIntent intent,
) => switch (intent) {
  final AuthoringGrantRequest value => value.toJson(),
  final ExperienceReviewDecisionGrantRequest value => value.toJson(),
  final ExperiencePromotionGrantRequest value => value.toJson(),
  _ => throw ArgumentError('Unsupported authoring grant intent'),
};

AuthoringGrantIntent decodeStoredAuthoringGrantIntent(
  String kind,
  Map<String, Object?> json,
) {
  final storedKind = StoredAuthoringGrantIntentKind.values
      .where((candidate) => candidate.wireName == kind)
      .firstOrNull;
  return switch (storedKind) {
    StoredAuthoringGrantIntentKind.authoringGrantRequest =>
      AuthoringGrantRequest.fromJson(json),
    StoredAuthoringGrantIntentKind.reviewDecisionGrantRequest =>
      ExperienceReviewDecisionGrantRequest.fromJson(json),
    StoredAuthoringGrantIntentKind.promotionGrantRequest =>
      ExperiencePromotionGrantRequest.fromJson(json),
    null => throw const FormatException('Unknown stored grant intent kind'),
  };
}

/// Host-private grant state. The connection epoch and original intent never
/// cross the public authoring wire, but are retained for restart-safe replay
/// and revocation checks.
final class StoredAuthoringGrant {
  StoredAuthoringGrant({
    required this.grant,
    required this.intentKind,
    required Map<String, Object?> intentJson,
    required this.connectionEpoch,
    required this.state,
    required DateTime stateChangedAt,
    this.revocationReason,
  }) : intentJson = Map<String, Object?>.unmodifiable(intentJson),
       stateChangedAt = stateChangedAt.toUtc() {
    if (intentKind.isEmpty || connectionEpoch.isEmpty) {
      throw ArgumentError('Stored authoring grant metadata is incomplete');
    }
    if ((state == StoredAuthoringGrantState.revoked) !=
        (revocationReason != null)) {
      throw ArgumentError('Stored authoring grant revocation is inconsistent');
    }
  }

  final AuthoringActionGrant grant;
  final String intentKind;
  final Map<String, Object?> intentJson;
  final String connectionEpoch;
  final StoredAuthoringGrantState state;
  final DateTime stateChangedAt;
  final String? revocationReason;

  StoredAuthoringGrant withState(
    StoredAuthoringGrantState next, {
    required DateTime at,
    String? reason,
  }) => StoredAuthoringGrant(
    grant: grant,
    intentKind: intentKind,
    intentJson: intentJson,
    connectionEpoch: connectionEpoch,
    state: next,
    stateChangedAt: at,
    revocationReason: reason,
  );
}

enum StoredAuthoringAttemptFamily {
  grantIssue,
  draftOpen,
  draftMutation,
  reviewPrepare,
  reviewAction,
  draftAbandon,
  promotionApply,
}

/// One terminal, replayable write attempt. [terminalJson] is a closed public
/// Result or ExperienceAuthoringError document, never an exception string.
final class StoredAuthoringAttempt {
  StoredAuthoringAttempt({
    required this.family,
    required this.requestId,
    required this.requestDigest,
    required this.payloadDigest,
    required this.subject,
    required this.effect,
    required this.operation,
    required this.grantId,
    required this.grantDigest,
    required this.isError,
    required Map<String, Object?> terminalJson,
    required DateTime completedAt,
  }) : terminalJson = Map<String, Object?>.unmodifiable(terminalJson),
       completedAt = completedAt.toUtc();

  final StoredAuthoringAttemptFamily family;
  final AuthoringRequestId requestId;
  final Digest requestDigest;
  final Digest payloadDigest;
  final AuthoringSubjectRef subject;
  final AuthoringActionEffect effect;
  final AuthoringOperation operation;
  final AuthoringActionGrantId? grantId;
  final Digest? grantDigest;
  final bool isError;
  final Map<String, Object?> terminalJson;
  final DateTime completedAt;

  late final Digest digest = Digest.semantic(<String, Object?>{
    'family': family.name,
    'requestId': requestId.value,
    'requestDigest': requestDigest.value,
    'payloadDigest': payloadDigest.value,
    'subject': subject.toJson(),
    'effect': effect.name,
    'operation': operation.name,
    if (grantId != null) 'grantId': grantId!.value,
    if (grantDigest != null) 'grantDigest': grantDigest!.value,
    'isError': isError,
    'terminal': terminalJson,
    'completedAt': completedAt.toIso8601String(),
  });

  bool matches({
    required Digest candidateRequestDigest,
    required Digest candidatePayloadDigest,
    required AuthoringSubjectRef candidateSubject,
    required AuthoringActionEffect candidateEffect,
    required AuthoringOperation candidateOperation,
    required AuthoringActionGrantId? candidateGrantId,
    required Digest? candidateGrantDigest,
  }) =>
      requestDigest == candidateRequestDigest &&
      payloadDigest == candidatePayloadDigest &&
      subject == candidateSubject &&
      effect == candidateEffect &&
      operation == candidateOperation &&
      grantId == candidateGrantId &&
      grantDigest == candidateGrantDigest;
}

/// Delta committed with a terminal attempt and (for effects) grant consume.
/// Immutable review objects remain retained even when [clearReviewHead] moves
/// the subject's current discovery index away from them.
final class ExperienceAuthoringAtomicCommit {
  const ExperienceAuthoringAtomicCommit({
    required this.attempt,
    this.issuedGrant,
    this.consumedGrantId,
    this.expectedDraftDigest,
    this.nextDraft,
    this.removeDraft = false,
    this.clearReviewHead = false,
    this.changeSet,
    this.reviewPacket,
    this.abandonReceipt,
    this.promotionIntentId,
    this.promotionOutcome,
  });

  final StoredAuthoringAttempt attempt;
  final StoredAuthoringGrant? issuedGrant;
  final AuthoringActionGrantId? consumedGrantId;
  final Digest? expectedDraftDigest;
  final StoredLayoutDraft? nextDraft;
  final bool removeDraft;
  final bool clearReviewHead;
  final ExperienceChangeSet? changeSet;
  final ExperienceReviewPacket? reviewPacket;
  final LayoutDraftAbandonReceipt? abandonReceipt;
  final String? promotionIntentId;
  final StoredPromotionFinalization? promotionOutcome;
}

/// Terminal transition for a prepared promotion effect. [failed] preserves
/// the WAL after a third-party source divergence while still making the exact
/// client request terminal and its single-use grant non-reusable.
enum StoredPromotionFinalization { committed, rolledBack, failed }
