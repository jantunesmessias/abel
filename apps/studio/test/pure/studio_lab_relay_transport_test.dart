import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  test('Host without relay methods has an explicit unavailable state', () {
    expect(
      selectStudioLabRelayTransport(const <String>{
        'workspace.describe',
        'workspace.open',
      }),
      StudioLabRelayTransportAvailability.unavailable,
    );
  });

  test('v2 is preferred while the complete v1 quartet stays compatible', () {
    expect(
      selectStudioLabRelayTransport(studioLabRelayRpcMethods),
      StudioLabRelayTransportAvailability.v1,
    );
    expect(
      selectStudioLabRelayTransport(studioLabRelayV2RpcMethods),
      StudioLabRelayTransportAvailability.v2,
    );
    expect(
      selectStudioLabRelayTransport(<String>{
        ...studioLabRelayRpcMethods,
        ...studioLabRelayV2RpcMethods,
      }),
      StudioLabRelayTransportAvailability.v2,
    );
  });

  test('partial v1 or v2 relay capability fails closed', () {
    for (final quartet in <Set<String>>[
      studioLabRelayRpcMethods,
      studioLabRelayV2RpcMethods,
    ]) {
      for (final missing in quartet) {
        expect(
          () => selectStudioLabRelayTransport(
            quartet.difference(<String>{missing}),
          ),
          throwsFormatException,
          reason: 'missing $missing',
        );
      }
    }
  });

  test('Gateway-bound run cannot downgrade to the complete v1 quartet', () {
    expect(
      () => selectStudioLabRelayTransport(
        studioLabRelayRpcMethods,
        requiresGateway: true,
      ),
      throwsA(isA<StudioLabRelayGatewayV2Required>()),
    );
  });

  test('run binding is derived only from the exact snapshot plan', () {
    final fixture = ScenarioLabTestFixture(gateway: true);
    final snapshot = fixture.runningSnapshot();
    final binding = StudioLabRelayRunBinding.fromSnapshot(
      snapshot: snapshot,
      catalog: fixture.catalog,
      manifest: fixture.manifest,
    );

    expect(binding.runId, snapshot.runId);
    expect(binding.startRequestDigest, snapshot.startRequestDigest);
    expect(binding.runtimeInputs.digest, snapshot.runtimeInputs!.digest);
    expect(binding.targetId, 'browser');
    expect(binding.launchProfileId, 'lab-web');
    expect(binding.requiresGateway, isTrue);
  });

  test(
    'run binding rejects runtime inputs outside the exact catalog binding',
    () {
      final fixture = ScenarioLabTestFixture(gateway: true);
      final mismatchedInputs = ScenarioLabRuntimeInputBinding(
        executionFingerprintDigest: digest('other-fingerprint'),
        executionTargetId: 'browser',
        gatewayPresetId: GatewayPresetId('other-gateway'),
        compiledGatewayPlanDigest: digest('other-plan'),
        routingTableDigest: digest('other-routes'),
      );

      expect(
        () => StudioLabRelayRunBinding.fromSnapshot(
          snapshot: fixture.runningSnapshot(
            runtimeInputBinding: mismatchedInputs,
          ),
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        ),
        throwsArgumentError,
      );
    },
  );
}
