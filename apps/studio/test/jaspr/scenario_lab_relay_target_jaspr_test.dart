@TestOn('vm')
library;

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/lab/scenario_lab_relay_controller.dart';
import 'package:studio/src/lab/scenario_lab_relay_target.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:studio/src/target_frame/target_frame.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  testComponents('mounts only the exact Host-owned relay target', (
    tester,
  ) async {
    final frameController = TargetFrameController();
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: _ReadyRelayHost(),
      target: TargetFrameRelayCommandTarget(frameController),
    );
    tester.pumpComponent(
      ScenarioLabRelayTarget(
        controller: controller,
        frameController: frameController,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      _domWithAttributes(<String, String>{
        'aria-label': 'Target do Scenario Lab',
        'data-lab-relay-run-id': _runId.value,
        'data-lab-relay-state': 'awaitingHello',
        'data-lab-relay-gateway-bound': 'false',
        'data-lab-relay-descriptor-digest': _descriptor.digest.value,
      }),
      findsOneComponent,
    );
    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-relay-target-id': 'browser',
        'data-lab-relay-launch-profile-id': 'lab-web',
        'data-lab-relay-launch-attempt-id': 'launch-attempt-0001',
      }),
      findsOneComponent,
    );
    expect(find.text('Target indisponível'), findsOneComponent);
    expect(
      find.byComponentPredicate(
        (component) =>
            component is TargetFrame &&
            component.scenarioLabRunId == _runId.value,
        description: 'relay TargetFrame with exact Scenario Lab run marker',
      ),
      findsOneComponent,
    );
    expect(_domTag('button'), findsNothing);
    expect(_domAttribute('data-lab-relay-command'), findsNothing);
    expect(_domAttribute('data-lab-relay-grant'), findsNothing);
    expect(_domAttribute('data-lab-relay-nonce'), findsNothing);
  });

  testComponents('renders the unavailable Host state without a frame', (
    tester,
  ) async {
    final frameController = TargetFrameController();
    tester.pumpComponent(
      ScenarioLabRelayTarget(
        controller: ScenarioLabRelayController(
          binding: _binding,
          host: null,
          target: TargetFrameRelayCommandTarget(frameController),
        ),
        frameController: frameController,
      ),
    );
    await tester.pump();

    expect(find.text('Relay indisponível neste Host.'), findsOneComponent);
    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-relay-state': 'unavailable',
      }),
      findsOneComponent,
    );
    expect(find.text('Target indisponível'), findsNothing);
  });

  test('rejects a controller wired to another TargetFrameController', () {
    final commandFrame = TargetFrameController();
    final mountedFrame = TargetFrameController();
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: _ReadyRelayHost(),
      target: TargetFrameRelayCommandTarget(commandFrame),
    );

    expect(
      () => ScenarioLabRelayTarget(
        controller: controller,
        frameController: mountedFrame,
      ),
      throwsArgumentError,
    );
  });
}

final _runId = ScenarioLabRunId('run-00000001');
final _fixture = ScenarioLabTestFixture();
final _binding = StudioLabRelayRunBinding.fromSnapshot(
  snapshot: _fixture.runningSnapshot(runId: _runId),
  catalog: _fixture.catalog,
  manifest: _fixture.manifest,
);
final _nonce = AppAdapterRelayNonce('relay-nonce-000000000001');

ScenarioLabRelayTargetDescriptor get _descriptor =>
    ScenarioLabRelayTargetDescriptor(
      runId: _runId,
      targetId: 'browser',
      launchProfileId: 'lab-web',
      launchAttemptId: TargetLaunchAttemptId('launch-attempt-0001'),
      origin: Uri.parse('http://127.0.0.1:8181'),
      nonce: _nonce,
    );

final class _ReadyRelayHost implements StudioHostLabRelayClient {
  @override
  Future<StudioLabRelayDescription> describeLabRelay(
    StudioLabRelayRunBinding binding,
  ) async {
    final call = prepareStudioLabRelayDescribeCall(
      capabilities: studioLabRelayRpcMethods,
      binding: binding,
    );
    return decodeStudioLabRelayDescription(
      value: ScenarioLabRelayDescription(
        runId: binding.runId,
        status: ScenarioLabRelayDescriptionStatus.ready,
        descriptor: _descriptor,
      ).toJson(),
      call: call,
      binding: binding,
    );
  }

  @override
  Future<ScenarioLabRelayPollResponse> nextLabRelayCommand(
    ScenarioLabRelayPollRequest request,
  ) => throw UnsupportedError('Target did not send Hello in the VM facade');

  @override
  Future<ScenarioLabRelayHelloAcknowledgement> submitLabRelayHello(
    ScenarioLabRelayHelloSubmission submission,
  ) => throw UnsupportedError('Target did not send Hello in the VM facade');

  @override
  Future<ScenarioLabRelayResultAcknowledgement> submitLabRelayResult(
    ScenarioLabRelayResultSubmission submission,
  ) => throw UnsupportedError('Target did not send Result in the VM facade');
}

Finder _domWithAttributes(Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM component with attributes $attributes',
    );

Finder _domAttribute(String attribute) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      component.attributes?.containsKey(attribute) == true,
  description: 'DOM component with attribute $attribute',
);

Finder _domTag(String tag) => find.byComponentPredicate(
  (component) => component is DomComponent && component.tag == tag,
  description: 'DOM <$tag>',
);
