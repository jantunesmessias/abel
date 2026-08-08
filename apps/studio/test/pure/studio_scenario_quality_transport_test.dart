import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/quality/studio_scenario_quality_transport.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';
import '../support/scenario_quality_decision_fixture.dart';

void main() {
  group('Scenario Quality transport selection', () {
    test('requires the complete quintet all-or-none', () {
      expect(
        selectStudioScenarioQualityTransport(const <String>{}),
        StudioScenarioQualityTransportAvailability.unavailable,
      );
      expect(
        selectStudioScenarioQualityTransport(studioScenarioQualityRpcMethods),
        StudioScenarioQualityTransportAvailability.available,
      );
      expect(
        () => selectStudioScenarioQualityTransport(
          studioScenarioQualityRpcMethods.difference(const <String>{
            'quality.decision.get',
          }),
        ),
        throwsFormatException,
      );
    });
  });

  test('describe and open decoders preserve every immutable fence', () {
    final fixture = ScenarioQualityDecisionTestFixture();
    final describeRequest = ScenarioQualityDescribeRequest(
      runId: fixture.result.finalSnapshot.runId,
      expectedRunResultDigest: fixture.result.digest,
    );
    final described = fixture.describe();
    expect(
      decodeStudioScenarioQualityDescribe(
        described.toJson(),
        describeRequest,
      ).digest,
      described.digest,
    );

    final openRequest = ScenarioQualityReviewOpenRequest(
      runId: fixture.result.finalSnapshot.runId,
      expectedRunResultDigest: fixture.result.digest,
      expectedQualityDigest: fixture.quality.digest,
      expectedReviewDescriptorDigest: fixture.descriptor.digest,
    );
    expect(
      decodeStudioScenarioQualityOpen(
        fixture.open(fixture.descriptor).toJson(),
        openRequest,
      ).reviewDescriptor.digest,
      fixture.descriptor.digest,
    );
    expect(
      () => decodeStudioScenarioQualityOpen(
        fixture.open(fixture.descriptor).toJson(),
        ScenarioQualityReviewOpenRequest(
          runId: fixture.result.finalSnapshot.runId,
          expectedRunResultDigest: fixture.result.digest,
          expectedQualityDigest: fixture.quality.digest,
          expectedReviewDescriptorDigest: digest('another-review'),
        ),
      ),
      throwsFormatException,
    );
  });

  test('typed errors are decoded only for the reserved JSON-RPC code', () {
    final fixture = ScenarioQualityDecisionTestFixture();
    final error = ScenarioQualityDecisionError(
      operation: ScenarioQualityDecisionOperation.describe,
      code: ScenarioQualityDecisionErrorCode.policyDenied,
      runId: fixture.result.finalSnapshot.runId,
      expectedRunResultDigest: fixture.result.digest,
    );
    expect(
      decodeStudioScenarioQualityDecisionError(
        jsonRpcCode: ScenarioQualityDecisionError.jsonRpcCode,
        data: error.toJson(),
        operation: ScenarioQualityDecisionOperation.describe,
        runId: fixture.result.finalSnapshot.runId,
        expectedRunResultDigest: fixture.result.digest,
      ).code,
      ScenarioQualityDecisionErrorCode.policyDenied,
    );
    expect(
      () => decodeStudioScenarioQualityDecisionError(
        jsonRpcCode: JsonRpcError.internalError,
        data: error.toJson(),
        operation: ScenarioQualityDecisionOperation.describe,
        runId: fixture.result.finalSnapshot.runId,
        expectedRunResultDigest: fixture.result.digest,
      ),
      throwsArgumentError,
    );
    expect(
      () => decodeStudioScenarioQualityDecisionError(
        jsonRpcCode: ScenarioQualityDecisionError.jsonRpcCode,
        data: error.toJson(),
        operation: ScenarioQualityDecisionOperation.open,
        runId: fixture.result.finalSnapshot.runId,
        expectedRunResultDigest: fixture.result.digest,
      ),
      throwsFormatException,
    );
  });

  test(
    'append decoder binds durable attribution to the requested grant',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final grantRequest = ScenarioQualityDecisionGrantRequest(
        requestId: ScenarioQualityDecisionRequestId('transport-grant'),
        runId: fixture.result.finalSnapshot.runId,
        expectedRunResultDigest: fixture.result.digest,
        expectedQualityDigest: fixture.quality.digest,
        expectedReviewDescriptorDigest: fixture.descriptor.digest,
        decision: HumanDecision.approved,
      );
      final grant = await host.grantScenarioQualityDecision(grantRequest);
      final appendRequest = ScenarioQualityDecisionAppendRequest(
        requestId: ScenarioQualityDecisionRequestId('transport-append'),
        runId: fixture.result.finalSnapshot.runId,
        expectedRunResultDigest: fixture.result.digest,
        expectedQualityDigest: fixture.quality.digest,
        expectedReviewDescriptorDigest: fixture.descriptor.digest,
        grantId: grant.id,
        grantDigest: grant.digest,
        decision: HumanDecision.approved,
      );
      final appended = await host.appendScenarioQualityDecision(appendRequest);
      final attribution = appended.attribution;
      final forged = ScenarioQualityDecisionAppendResult(
        requestId: appended.requestId,
        requestDigest: appended.requestDigest,
        attribution: ScenarioQualityDecisionAttribution(
          runId: attribution.runId,
          runResultDigest: attribution.runResultDigest,
          reviewDescriptorDigest: attribution.reviewDescriptorDigest,
          requirementId: attribution.requirementId,
          requirementScope: attribution.requirementScope,
          reviewGuideId: attribution.reviewGuideId,
          reviewGuideStepId: attribution.reviewGuideStepId,
          authorityId: attribution.authorityId,
          accessPolicyId: attribution.accessPolicyId,
          principalId: attribution.principalId,
          role: attribution.role,
          grantDigest: digest('another-grant'),
          grantRequestDigest: attribution.grantRequestDigest,
          decisionRequestDigest: attribution.decisionRequestDigest,
        ),
        record: appended.record,
        quality: appended.quality,
      );

      expect(
        () => decodeStudioScenarioQualityAppend(forged.toJson(), appendRequest),
        throwsFormatException,
      );
    },
  );
}
