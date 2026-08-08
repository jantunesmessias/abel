import 'package:flutter_test/flutter_test.dart';

import '../tool/target_launch_context.dart';

void main() {
  test('ordinary Target launch does not activate the Scenario Lab relay', () {
    expect(
      sampleRelayConfiguration(
        launchOverlay: const <String, String>{},
        sessionId: 'session-ordinary',
        nonce: '0123456789abcdef',
      ),
      isNull,
    );
  });

  test('explicit Lab launch creates one exact run and provider binding', () {
    final configuration = sampleRelayConfiguration(
      launchOverlay: const <String, String>{
        sampleScenarioLabRunOverlayKey: 'run-1234',
      },
      sessionId: 'run-1234',
      nonce: 'relay_nonce_value_123456',
      createAdapterInstanceId: () => 'sample-adapter-fixed',
    );

    expect(configuration, isNotNull);
    expect(configuration!.runId.value, 'run-1234');
    expect(configuration.adapterInstanceId, 'sample-adapter-fixed');
    expect(configuration.nonce.value, 'relay_nonce_value_123456');
    expect(
      configuration.evidenceProviderIds.single.value,
      'capture.app-adapter',
    );
  });

  test('mixed Scenario Lab run and target session fails closed', () {
    expect(
      () => sampleRelayConfiguration(
        launchOverlay: const <String, String>{
          sampleScenarioLabRunOverlayKey: 'run-a',
        },
        sessionId: 'run-b',
        nonce: '0123456789abcdef',
      ),
      throwsFormatException,
    );
  });
}
