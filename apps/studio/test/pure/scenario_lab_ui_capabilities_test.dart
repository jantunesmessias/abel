import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/lab/scenario_lab_ui_capabilities.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:studio/src/lab/studio_scenario_lab_run_transport.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  late ScenarioLabTestFixture fixture;
  late ExperienceContentSetIdentity identity;

  setUp(() {
    fixture = ScenarioLabTestFixture();
    identity = ExperienceContentSetIdentity(
      revision: 1,
      catalogDigest: fixture.catalog.digest,
      workspaceSnapshotDigest: digest('workspace'),
      workspaceContentDigest: digest('workspace-content'),
      scenarioLabManifestDigest: fixture.manifest.digest,
    );
  });

  test(
    'requires module, atomic content, client and both complete quartets',
    () {
      final capabilities = ScenarioLabUiCapabilities.resolve(
        labModuleEnabled: true,
        hasContentGeneration: true,
        contentIdentity: identity,
        manifest: fixture.manifest,
        client: _FullClient(),
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
      );

      expect(capabilities.runAvailable, isTrue);
      expect(capabilities.relayAvailable, isTrue);
    },
  );

  test('never treats a Studio contribution as execution authority', () {
    final capabilities = ScenarioLabUiCapabilities.resolve(
      labModuleEnabled: true,
      hasContentGeneration: true,
      contentIdentity: identity,
      manifest: fixture.manifest,
      client: _FullClient(),
      rpcMethods: const <String>{'studio.lab'},
    );

    expect(capabilities.run, ScenarioLabUiCapabilityState.rpcUnavailable);
    expect(capabilities.relay, ScenarioLabUiCapabilityState.runUnavailable);
  });

  test('partial run or relay capability fails closed independently', () {
    final partialRun = ScenarioLabUiCapabilities.resolve(
      labModuleEnabled: true,
      hasContentGeneration: true,
      contentIdentity: identity,
      manifest: fixture.manifest,
      client: _FullClient(),
      rpcMethods: studioScenarioLabRunRpcMethods.difference(const <String>{
        'lab.cancel',
      }),
    );
    expect(partialRun.run, ScenarioLabUiCapabilityState.rpcIncomplete);

    final partialRelay = ScenarioLabUiCapabilities.resolve(
      labModuleEnabled: true,
      hasContentGeneration: true,
      contentIdentity: identity,
      manifest: fixture.manifest,
      client: _FullClient(),
      rpcMethods: <String>{
        ...studioScenarioLabRunRpcMethods,
        ...studioLabRelayRpcMethods.difference(const <String>{
          'lab.relay.result',
        }),
      },
    );
    expect(partialRelay.runAvailable, isTrue);
    expect(partialRelay.relay, ScenarioLabUiCapabilityState.rpcIncomplete);
  });

  test('Gateway run requires v2 while no-Gateway v1 remains available', () {
    final gatewayInputs = ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest: digest('gateway-fingerprint'),
      executionTargetId: 'browser',
      gatewayPresetId: GatewayPresetId('lab-gateway'),
      compiledGatewayPlanDigest: digest('gateway-plan'),
      routingTableDigest: digest('gateway-routes'),
    );
    final v1Only = ScenarioLabUiCapabilities.resolve(
      labModuleEnabled: true,
      hasContentGeneration: true,
      contentIdentity: identity,
      manifest: fixture.manifest,
      client: _FullClient(),
      rpcMethods: <String>{
        ...studioScenarioLabRunRpcMethods,
        ...studioLabRelayRpcMethods,
      },
      runtimeInputs: gatewayInputs,
    );
    final v2 = ScenarioLabUiCapabilities.resolve(
      labModuleEnabled: true,
      hasContentGeneration: true,
      contentIdentity: identity,
      manifest: fixture.manifest,
      client: _FullClient(),
      rpcMethods: <String>{
        ...studioScenarioLabRunRpcMethods,
        ...studioLabRelayV2RpcMethods,
      },
      runtimeInputs: gatewayInputs,
    );

    expect(v1Only.relay, ScenarioLabUiCapabilityState.gatewayV2Required);
    expect(v2.relayAvailable, isTrue);
    expect(
      ScenarioLabUiCapabilities.resolve(
        labModuleEnabled: true,
        hasContentGeneration: true,
        contentIdentity: identity,
        manifest: fixture.manifest,
        client: _FullClient(),
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
        runtimeInputs: fixture.runtimeInputs,
      ).relayAvailable,
      isTrue,
    );
  });

  test('v1, disabled module and missing typed client remain explicit', () {
    expect(
      ScenarioLabUiCapabilities.resolve(
        labModuleEnabled: false,
        hasContentGeneration: true,
        contentIdentity: identity,
        manifest: fixture.manifest,
        client: _FullClient(),
        rpcMethods: studioScenarioLabRunRpcMethods,
      ).run,
      ScenarioLabUiCapabilityState.moduleDisabled,
    );
    expect(
      ScenarioLabUiCapabilities.resolve(
        labModuleEnabled: true,
        hasContentGeneration: false,
        contentIdentity: null,
        manifest: fixture.manifest,
        client: _FullClient(),
        rpcMethods: studioScenarioLabRunRpcMethods,
      ).run,
      ScenarioLabUiCapabilityState.contentUnavailable,
    );
    expect(
      ScenarioLabUiCapabilities.resolve(
        labModuleEnabled: true,
        hasContentGeneration: true,
        contentIdentity: identity,
        manifest: fixture.manifest,
        client: _WorkspaceOnlyClient(),
        rpcMethods: studioScenarioLabRunRpcMethods,
      ).run,
      ScenarioLabUiCapabilityState.clientUnavailable,
    );
  });
}

final class _WorkspaceOnlyClient implements StudioHostClient {
  @override
  Future<void> close() async {}

  @override
  Future<WorkspaceSnapshot> openWorkspace() => throw UnimplementedError();

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() => throw UnimplementedError();
}

final class _FullClient extends _WorkspaceOnlyClient
    implements StudioHostScenarioLabRunClient, StudioHostLabRelayClient {
  @override
  Future<ScenarioLabRunSnapshot> startScenarioLabRun(
    ScenarioLabRunStartRequest request,
  ) => throw UnimplementedError();

  @override
  Future<ScenarioLabRunSnapshot> getScenarioLabRun(
    ScenarioLabRunReference reference,
  ) => throw UnimplementedError();

  @override
  Future<ScenarioLabRunSnapshot> cancelScenarioLabRun(
    ScenarioLabRunReference reference,
  ) => throw UnimplementedError();

  @override
  Future<ScenarioLabRunObservation> reattachScenarioLabRun(
    ScenarioLabRunObserveRequest request,
  ) => throw UnimplementedError();

  @override
  Future<StudioLabRelayDescription> describeLabRelay(
    StudioLabRelayRunBinding binding,
  ) => throw UnimplementedError();

  @override
  Future<ScenarioLabRelayPollResponse> nextLabRelayCommand(
    ScenarioLabRelayPollRequest request,
  ) => throw UnimplementedError();

  @override
  Future<ScenarioLabRelayHelloAcknowledgement> submitLabRelayHello(
    ScenarioLabRelayHelloSubmission submission,
  ) => throw UnimplementedError();

  @override
  Future<ScenarioLabRelayResultAcknowledgement> submitLabRelayResult(
    ScenarioLabRelayResultSubmission submission,
  ) => throw UnimplementedError();
}
