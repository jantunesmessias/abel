import 'package:experience_contracts/experience_contracts.dart';

enum StudioExperienceAuthoringTransportAvailability { unavailable, v1 }

StudioExperienceAuthoringTransportAvailability
selectStudioExperienceAuthoringTransport(Set<String> capabilities) {
  final present = ExperienceAuthoringRpcMethod.values
      .where(capabilities.contains)
      .toSet();
  if (present.isEmpty) {
    return StudioExperienceAuthoringTransportAvailability.unavailable;
  }
  if (present.length != ExperienceAuthoringRpcMethod.values.length) {
    throw const FormatException(
      'Workspace Host exposes an incomplete Experience Authoring capability set',
    );
  }
  return StudioExperienceAuthoringTransportAvailability.v1;
}

final class StudioExperienceAuthoringRpcCall {
  const StudioExperienceAuthoringRpcCall({
    required this.method,
    required this.params,
  });

  final String method;
  final Map<String, Object?> params;
}

StudioExperienceAuthoringRpcCall prepareStudioExperienceAuthoringCall({
  required Set<String> capabilities,
  required String method,
  required Map<String, Object?> params,
}) {
  if (selectStudioExperienceAuthoringTransport(capabilities) !=
          StudioExperienceAuthoringTransportAvailability.v1 ||
      !ExperienceAuthoringRpcMethod.values.contains(method)) {
    throw const StudioExperienceAuthoringUnavailable();
  }
  return StudioExperienceAuthoringRpcCall(method: method, params: params);
}

final class StudioExperienceAuthoringUnavailable implements Exception {
  const StudioExperienceAuthoringUnavailable();

  @override
  String toString() => 'Experience Authoring is unavailable';
}

final class StudioExperienceAuthoringFailure implements Exception {
  const StudioExperienceAuthoringFailure(this.error);

  final ExperienceAuthoringError error;

  @override
  String toString() => 'Experience Authoring failed with ${error.code.name}';
}

ExperienceAuthoringDescription decodeStudioExperienceAuthoringDescription(
  Object? value,
  ExperienceAuthoringDescribeRequest request,
) {
  final result = ExperienceAuthoringDescription.fromJson(value);
  result.validateAgainst(request);
  return result;
}

ExperienceAuthoringSubjectHeadResult decodeStudioExperienceAuthoringHead(
  Object? value,
  ExperienceAuthoringSubjectHeadRequest request,
) {
  final result = ExperienceAuthoringSubjectHeadResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

LayoutDraftOpenResult decodeStudioExperienceLayoutDraftOpen(
  Object? value,
  LayoutDraftOpenRequest request,
) {
  final result = LayoutDraftOpenResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

LayoutDraftGetResult decodeStudioExperienceLayoutDraftGet(
  Object? value,
  LayoutDraftGetRequest request,
) {
  final result = LayoutDraftGetResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

AuthoringGrantResult decodeStudioExperienceAuthoringGrant(
  Object? value,
  AuthoringGrantIntent request,
) {
  final result = AuthoringGrantResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

LayoutDraftMutationResult decodeStudioExperienceLayoutDraftMutation(
  Object? value,
  LayoutDraftMutationRequest request, {
  required LayoutDraft previousDraft,
}) {
  final result = LayoutDraftMutationResult.fromJson(value);
  result.validateAgainst(request, previousDraft: previousDraft);
  return result;
}

ExperienceReviewPrepareResult decodeStudioExperienceReviewPrepare(
  Object? value,
  ExperienceReviewPrepareRequest request, {
  required LayoutDraft draft,
}) {
  final result = ExperienceReviewPrepareResult.fromJson(value);
  result.validateAgainst(request, draft: draft);
  return result;
}

ExperienceChangeSetGetResult decodeStudioExperienceChangeSet(
  Object? value,
  ExperienceChangeSetGetRequest request,
) {
  final result = ExperienceChangeSetGetResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

ExperienceReviewGetResult decodeStudioExperienceReview(
  Object? value,
  ExperienceReviewGetRequest request,
) {
  final result = ExperienceReviewGetResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

ExperienceReviewActionResult decodeStudioExperienceReviewAction(
  Object? value,
  ExperienceReviewActionRequest request, {
  required ExperienceChangeSet changeSet,
  required ExperienceReviewPacket previousPacket,
}) {
  final result = ExperienceReviewActionResult.fromJson(value);
  result.validateAgainst(
    request,
    changeSet: changeSet,
    previousPacket: previousPacket,
  );
  return result;
}

LayoutDraftAbandonResult decodeStudioExperienceLayoutDraftAbandon(
  Object? value,
  LayoutDraftAbandonRequest request,
) {
  final result = LayoutDraftAbandonResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

ExperiencePromotionApplyResult decodeStudioExperiencePromotionApply(
  Object? value,
  ExperiencePromotionApplyRequest request,
) {
  final result = ExperiencePromotionApplyResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

ExperiencePromotionGetResult decodeStudioExperiencePromotion(
  Object? value,
  ExperiencePromotionGetRequest request,
) {
  final result = ExperiencePromotionGetResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

ExperiencePromotionHistoryResult decodeStudioExperiencePromotionHistory(
  Object? value,
  ExperiencePromotionHistoryRequest request,
) {
  final result = ExperiencePromotionHistoryResult.fromJson(value);
  result.validateAgainst(request);
  return result;
}

StudioExperienceAuthoringFailure decodeStudioExperienceAuthoringFailure({
  required Object? value,
  required AuthoringRequestId requestId,
  required AuthoringSubjectRef subject,
  AuthoringOperation? operation,
  LayoutDraftMutation? mutation,
}) {
  final error = ExperienceAuthoringError.fromJson(value);
  if (error.requestId != requestId ||
      error.subject != subject ||
      (operation != null && error.operation != operation) ||
      (mutation != null && error.mutation != mutation)) {
    throw const FormatException(
      'Experience Authoring error does not match its request',
    );
  }
  return StudioExperienceAuthoringFailure(error);
}
