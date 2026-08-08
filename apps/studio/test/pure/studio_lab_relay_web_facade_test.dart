import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  test('browser facade prefers v2 and sends exactly the closed request', () {
    final binding = _binding(gateway: false);
    final call = prepareStudioLabRelayDescribeCall(
      capabilities: <String>{
        ...studioLabRelayRpcMethods,
        ...studioLabRelayV2RpcMethods,
      },
      binding: binding,
    );

    expect(call.transport, StudioLabRelayTransportAvailability.v2);
    expect(call.method, 'lab.relay.v2.describe');
    expect(call.params, <String, Object?>{
      'runId': binding.runId.value,
      'expectedStartRequestDigest': binding.startRequestDigest.value,
    });
  });

  test('browser facade accepts the exact Gateway-bound v2 description', () {
    final binding = _binding(gateway: true);
    final call = prepareStudioLabRelayDescribeCall(
      capabilities: studioLabRelayV2RpcMethods,
      binding: binding,
    );
    final gatewayDataOrigin = Uri.parse('http://127.0.0.1:8090');
    final decoded = decodeStudioLabRelayDescription(
      value: _v2Description(
        binding,
        gatewayDataOrigin: gatewayDataOrigin,
      ).toJson(),
      call: call,
      binding: binding,
    );

    expect(decoded.status, ScenarioLabRelayDescriptionStatus.ready);
    expect(decoded.gatewayBound, isTrue);
    expect(decoded.gatewayDataOriginFor(binding), gatewayDataOrigin);
    expect(decoded.descriptor!.digest, _descriptor(binding).digest);
  });

  test('browser facade keeps no-Gateway v1 and v2 origins absent', () {
    final binding = _binding(gateway: false);
    final v1Call = prepareStudioLabRelayDescribeCall(
      capabilities: studioLabRelayRpcMethods,
      binding: binding,
    );
    final v1 = decodeStudioLabRelayDescription(
      value: ScenarioLabRelayDescription(
        runId: binding.runId,
        status: ScenarioLabRelayDescriptionStatus.ready,
        descriptor: _descriptor(binding),
      ).toJson(),
      call: v1Call,
      binding: binding,
    );
    final v2Call = prepareStudioLabRelayDescribeCall(
      capabilities: studioLabRelayV2RpcMethods,
      binding: binding,
    );
    final v2 = decodeStudioLabRelayDescription(
      value: _v2Description(binding).toJson(),
      call: v2Call,
      binding: binding,
    );

    expect(v1.transport, StudioLabRelayTransportAvailability.v1);
    expect(v2.transport, StudioLabRelayTransportAvailability.v2);
    expect(v1.gatewayBound, isFalse);
    expect(v2.gatewayBound, isFalse);
    expect(v1.gatewayDataOriginFor(binding), isNull);
    expect(v2.gatewayDataOriginFor(binding), isNull);
  });

  test('browser facade rejects Gateway origin iff mismatches', () {
    final noGatewayBinding = _binding(gateway: false);
    final noGatewayCall = prepareStudioLabRelayDescribeCall(
      capabilities: studioLabRelayV2RpcMethods,
      binding: noGatewayBinding,
    );
    final unexpectedOrigin = _v2Description(noGatewayBinding).toJson()
      ..['gatewayDataOrigin'] = 'http://127.0.0.1:8090';
    expect(
      () => decodeStudioLabRelayDescription(
        value: unexpectedOrigin,
        call: noGatewayCall,
        binding: noGatewayBinding,
      ),
      throwsFormatException,
    );

    final gatewayBinding = _binding(gateway: true);
    final gatewayCall = prepareStudioLabRelayDescribeCall(
      capabilities: studioLabRelayV2RpcMethods,
      binding: gatewayBinding,
    );
    final missingOrigin = _v2Description(
      gatewayBinding,
      gatewayDataOrigin: Uri.parse('http://127.0.0.1:8090'),
    ).toJson()..remove('gatewayDataOrigin');
    expect(
      () => decodeStudioLabRelayDescription(
        value: missingOrigin,
        call: gatewayCall,
        binding: gatewayBinding,
      ),
      throwsFormatException,
    );
  });

  test(
    'browser facade rejects start, runtime, profile and digest mismatch',
    () {
      final binding = _binding(gateway: true);
      final call = prepareStudioLabRelayDescribeCall(
        capabilities: studioLabRelayV2RpcMethods,
        binding: binding,
      );
      final gatewayDataOrigin = Uri.parse('http://127.0.0.1:8090');

      final wrongStart = ScenarioLabRelayDescriptionV2(
        runId: binding.runId,
        startRequestDigest: _digest('wrong-start'),
        status: ScenarioLabRelayDescriptionStatus.ready,
        descriptor: _descriptor(binding),
        runtimeInputs: binding.runtimeInputs,
        gatewayDataOrigin: gatewayDataOrigin,
      );
      expect(
        () => decodeStudioLabRelayDescription(
          value: wrongStart.toJson(),
          call: call,
          binding: binding,
        ),
        throwsFormatException,
      );

      final wrongRuntimeInputs = ScenarioLabRuntimeInputBinding(
        executionFingerprintDigest: _digest('wrong-fingerprint'),
        executionTargetId: binding.runtimeInputs.executionTargetId,
        gatewayPresetId: binding.runtimeInputs.gatewayPresetId,
        compiledGatewayPlanDigest:
            binding.runtimeInputs.compiledGatewayPlanDigest,
        routingTableDigest: binding.runtimeInputs.routingTableDigest,
      );
      final wrongRuntime = ScenarioLabRelayDescriptionV2(
        runId: binding.runId,
        startRequestDigest: binding.startRequestDigest,
        status: ScenarioLabRelayDescriptionStatus.ready,
        descriptor: _descriptor(binding),
        runtimeInputs: wrongRuntimeInputs,
        gatewayDataOrigin: gatewayDataOrigin,
      );
      expect(
        () => decodeStudioLabRelayDescription(
          value: wrongRuntime.toJson(),
          call: call,
          binding: binding,
        ),
        throwsFormatException,
      );

      final wrongProfile = ScenarioLabRelayDescriptionV2(
        runId: binding.runId,
        startRequestDigest: binding.startRequestDigest,
        status: ScenarioLabRelayDescriptionStatus.ready,
        descriptor: ScenarioLabRelayTargetDescriptor(
          runId: binding.runId,
          targetId: binding.targetId,
          launchProfileId: 'other-profile',
          launchAttemptId: TargetLaunchAttemptId('launch-attempt-0001'),
          origin: Uri.parse('http://127.0.0.1:8181'),
          nonce: AppAdapterRelayNonce('relay-nonce-000000000001'),
        ),
        runtimeInputs: binding.runtimeInputs,
        gatewayDataOrigin: gatewayDataOrigin,
      );
      expect(
        () => decodeStudioLabRelayDescription(
          value: wrongProfile.toJson(),
          call: call,
          binding: binding,
        ),
        throwsFormatException,
      );

      final tampered = _v2Description(
        binding,
        gatewayDataOrigin: gatewayDataOrigin,
      ).toJson()..['digest'] = _digest('tampered').value;
      expect(
        () => decodeStudioLabRelayDescription(
          value: tampered,
          call: call,
          binding: binding,
        ),
        throwsFormatException,
      );
    },
  );

  test('browser facade refuses Gateway downgrade before a v1 RPC exists', () {
    final binding = _binding(gateway: true);

    expect(
      () => prepareStudioLabRelayDescribeCall(
        capabilities: studioLabRelayRpcMethods,
        binding: binding,
      ),
      throwsA(isA<StudioLabRelayGatewayV2Required>()),
    );
  });
}

StudioLabRelayRunBinding _binding({required bool gateway}) {
  final fixture = ScenarioLabTestFixture(gateway: gateway);
  return StudioLabRelayRunBinding.fromSnapshot(
    snapshot: fixture.runningSnapshot(),
    catalog: fixture.catalog,
    manifest: fixture.manifest,
  );
}

ScenarioLabRelayTargetDescriptor _descriptor(
  StudioLabRelayRunBinding binding,
) => ScenarioLabRelayTargetDescriptor(
  runId: binding.runId,
  targetId: binding.targetId,
  launchProfileId: binding.launchProfileId,
  launchAttemptId: TargetLaunchAttemptId('launch-attempt-0001'),
  origin: Uri.parse('http://127.0.0.1:8181'),
  nonce: AppAdapterRelayNonce('relay-nonce-000000000001'),
);

ScenarioLabRelayDescriptionV2 _v2Description(
  StudioLabRelayRunBinding binding, {
  Uri? gatewayDataOrigin,
}) => ScenarioLabRelayDescriptionV2(
  runId: binding.runId,
  startRequestDigest: binding.startRequestDigest,
  status: ScenarioLabRelayDescriptionStatus.ready,
  descriptor: _descriptor(binding),
  runtimeInputs: binding.runtimeInputs,
  gatewayDataOrigin: gatewayDataOrigin,
);

Digest _digest(String value) => Digest.semantic(value);
