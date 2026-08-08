import 'package:studio/src/lab/studio_scenario_lab_run_transport.dart';
import 'package:test/test.dart';

void main() {
  test('keeps the additive run lifecycle explicitly unavailable', () {
    expect(
      selectStudioScenarioLabRunTransport(const <String>{'studio.lab'}),
      StudioScenarioLabRunTransportAvailability.unavailable,
    );
  });

  test('requires the complete canonical lifecycle quartet', () {
    expect(studioScenarioLabRunRpcMethods, <String>{
      'lab.start',
      'lab.get',
      'lab.cancel',
      'lab.reattach',
    });
    expect(
      selectStudioScenarioLabRunTransport(studioScenarioLabRunRpcMethods),
      StudioScenarioLabRunTransportAvailability.available,
    );

    for (final missing in studioScenarioLabRunRpcMethods) {
      expect(
        () => selectStudioScenarioLabRunTransport(
          studioScenarioLabRunRpcMethods.difference(<String>{missing}),
        ),
        throwsFormatException,
        reason: 'missing $missing must fail closed',
      );
    }
  });
}
