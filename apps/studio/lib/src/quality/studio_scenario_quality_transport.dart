import 'package:experience_contracts/experience_contracts.dart';

const Set<String> studioScenarioQualityRpcMethods = <String>{
  'quality.describe',
  'quality.open',
  'quality.decision.grant',
  'quality.decision.append',
  'quality.decision.get',
};

enum StudioScenarioQualityTransportAvailability { unavailable, available }

final class StudioScenarioQualityUnavailable implements Exception {
  const StudioScenarioQualityUnavailable();

  @override
  String toString() => 'StudioScenarioQualityUnavailable';
}

final class StudioScenarioQualityDecisionFailure implements Exception {
  const StudioScenarioQualityDecisionFailure(this.error);

  final ScenarioQualityDecisionError error;

  @override
  String toString() =>
      'StudioScenarioQualityDecisionFailure(${error.code.name})';
}

StudioScenarioQualityTransportAvailability selectStudioScenarioQualityTransport(
  Set<String> capabilities,
) {
  final present = capabilities.intersection(studioScenarioQualityRpcMethods);
  if (present.isEmpty) {
    return StudioScenarioQualityTransportAvailability.unavailable;
  }
  if (present.length != studioScenarioQualityRpcMethods.length) {
    throw const FormatException(
      'Workspace Host exposes an incomplete Scenario Quality capability',
    );
  }
  return StudioScenarioQualityTransportAvailability.available;
}

Map<String, Object?> encodeStudioScenarioQualityDescribe(
  ScenarioQualityDescribeRequest request,
) => request.toJson();

Map<String, Object?> encodeStudioScenarioQualityOpen(
  ScenarioQualityReviewOpenRequest request,
) => request.toJson();

Map<String, Object?> encodeStudioScenarioQualityGrant(
  ScenarioQualityDecisionGrantRequest request,
) => request.toJson();

Map<String, Object?> encodeStudioScenarioQualityAppend(
  ScenarioQualityDecisionAppendRequest request,
) => request.toJson();

Map<String, Object?> encodeStudioScenarioQualityGet(
  ScenarioQualityDecisionGetRequest request,
) => request.toJson();

ScenarioQualityDescribeResult decodeStudioScenarioQualityDescribe(
  Object? value,
  ScenarioQualityDescribeRequest request,
) {
  final result = ScenarioQualityDescribeResult.fromJson(value);
  if (result.description.runId != request.runId ||
      result.description.runResultDigest != request.expectedRunResultDigest) {
    throw const FormatException(
      'Scenario Quality description crossed its run-result fence',
    );
  }
  return result;
}

ScenarioQualityReviewOpenResult decodeStudioScenarioQualityOpen(
  Object? value,
  ScenarioQualityReviewOpenRequest request,
) {
  final result = ScenarioQualityReviewOpenResult.fromJson(value);
  final descriptor = result.reviewDescriptor;
  if (descriptor.runId != request.runId ||
      descriptor.runResultDigest != request.expectedRunResultDigest ||
      descriptor.qualityDigest != request.expectedQualityDigest ||
      descriptor.digest != request.expectedReviewDescriptorDigest) {
    throw const FormatException(
      'Scenario Quality review resources crossed their immutable fence',
    );
  }
  return result;
}

ScenarioQualityDecisionGrant decodeStudioScenarioQualityGrant(
  Object? value,
  ScenarioQualityDecisionGrantRequest request,
) {
  final grant = ScenarioQualityDecisionGrant.fromJson(value);
  if (grant.requestId != request.requestId ||
      grant.requestDigest != request.digest ||
      grant.runId != request.runId ||
      grant.runResultDigest != request.expectedRunResultDigest ||
      grant.qualityDigest != request.expectedQualityDigest ||
      grant.reviewDescriptorDigest != request.expectedReviewDescriptorDigest ||
      grant.expectedPreviousDecisionDigest !=
          request.expectedPreviousDecisionDigest ||
      grant.decision != request.decision) {
    throw const FormatException(
      'Scenario Quality decision grant does not bind its request',
    );
  }
  return grant;
}

ScenarioQualityDecisionAppendResult decodeStudioScenarioQualityAppend(
  Object? value,
  ScenarioQualityDecisionAppendRequest request,
) {
  final result = ScenarioQualityDecisionAppendResult.fromJson(value);
  if (result.requestId != request.requestId ||
      result.requestDigest != request.digest ||
      result.attribution.runId != request.runId ||
      result.attribution.runResultDigest != request.expectedRunResultDigest ||
      result.attribution.reviewDescriptorDigest !=
          request.expectedReviewDescriptorDigest ||
      result.attribution.grantDigest != request.grantDigest ||
      result.record.decision != request.decision ||
      result.record.supersedesDecisionDigest !=
          request.expectedPreviousDecisionDigest) {
    throw const FormatException(
      'Scenario Quality append result does not bind its request',
    );
  }
  return result;
}

ScenarioQualityDecisionView decodeStudioScenarioQualityGet(
  Object? value,
  ScenarioQualityDecisionGetRequest request,
) {
  final view = ScenarioQualityDecisionView.fromJson(value);
  if (view.record.digest != request.decisionDigest ||
      view.attribution.runId != request.runId ||
      view.attribution.runResultDigest != request.expectedRunResultDigest ||
      view.record.subjectDigest != request.expectedRunResultDigest) {
    throw const FormatException(
      'Scenario Quality decision view crossed its history fence',
    );
  }
  return view;
}

ScenarioQualityDecisionError decodeStudioScenarioQualityDecisionError({
  required int jsonRpcCode,
  required Object? data,
  required ScenarioQualityDecisionOperation operation,
  required ScenarioLabRunId runId,
  required Digest expectedRunResultDigest,
  ScenarioQualityDecisionRequestId? requestId,
}) {
  if (jsonRpcCode != ScenarioQualityDecisionError.jsonRpcCode) {
    throw ArgumentError.value(jsonRpcCode, 'jsonRpcCode');
  }
  final error = ScenarioQualityDecisionError.fromJson(data);
  if (error.operation != operation ||
      error.runId != runId ||
      error.expectedRunResultDigest != expectedRunResultDigest ||
      error.requestId != requestId) {
    throw const FormatException(
      'Scenario Quality decision error crossed its request fence',
    );
  }
  return error;
}
