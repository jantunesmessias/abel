import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/authoring/studio_experience_authoring_transport.dart';
import 'package:test/test.dart';

void main() {
  test('selects the sixteen Experience Authoring RPC methods all-or-none', () {
    expect(
      selectStudioExperienceAuthoringTransport(const <String>{}),
      StudioExperienceAuthoringTransportAvailability.unavailable,
    );
    expect(
      selectStudioExperienceAuthoringTransport(
        ExperienceAuthoringRpcMethod.values.toSet(),
      ),
      StudioExperienceAuthoringTransportAvailability.v1,
    );
    expect(
      () => selectStudioExperienceAuthoringTransport(
        ExperienceAuthoringRpcMethod.values
            .where(
              (method) =>
                  method != ExperienceAuthoringRpcMethod.getPromotionHistory,
            )
            .toSet(),
      ),
      throwsFormatException,
    );
  });

  test('rejects a typed error bound to another request', () {
    final subject = AuthoringSubjectRef(
      workspaceId: WorkspaceId('workspace'),
      applicationId: ApplicationId('application'),
      projectionId: ExperienceProjectionId('projection'),
    );
    final error = ExperienceAuthoringError(
      requestId: AuthoringRequestId('other-request'),
      subject: subject,
      operation: AuthoringOperation.moveNode,
      mutation: LayoutDraftMutation.applyMove,
      code: ExperienceAuthoringErrorCode.stale,
      expectedDigest: Digest.semantic('expected'),
      currentDraftDigest: Digest.semantic('current'),
    );

    expect(
      () => decodeStudioExperienceAuthoringFailure(
        value: error.toJson(),
        requestId: AuthoringRequestId('current-request'),
        subject: subject,
        operation: AuthoringOperation.moveNode,
        mutation: LayoutDraftMutation.applyMove,
      ),
      throwsFormatException,
    );
  });
}
