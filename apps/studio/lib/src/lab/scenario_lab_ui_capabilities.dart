import 'package:experience_contracts/experience_contracts.dart';

import '../host/studio_host_client.dart';
import 'studio_lab_relay_transport.dart';
import 'studio_scenario_lab_run_transport.dart';

enum ScenarioLabUiCapabilityState {
  available,
  moduleDisabled,
  contentUnavailable,
  clientUnavailable,
  rpcUnavailable,
  rpcIncomplete,
  gatewayV2Required,
  runUnavailable,
}

final class ScenarioLabUiCapabilities {
  const ScenarioLabUiCapabilities({required this.run, required this.relay});

  factory ScenarioLabUiCapabilities.resolve({
    required bool labModuleEnabled,
    required bool hasContentGeneration,
    required ExperienceContentSetIdentity? contentIdentity,
    required ScenarioLabManifest? manifest,
    required StudioHostClient? client,
    required Iterable<String> rpcMethods,
    ScenarioLabRuntimeInputBinding? runtimeInputs,
  }) {
    final rpcSet = Set<String>.unmodifiable(rpcMethods);
    final run = _runState(
      labModuleEnabled: labModuleEnabled,
      hasContentGeneration: hasContentGeneration,
      contentIdentity: contentIdentity,
      manifest: manifest,
      client: client,
      rpcMethods: rpcSet,
    );
    return ScenarioLabUiCapabilities(
      run: run,
      relay: _relayState(
        run: run,
        client: client,
        rpcMethods: rpcSet,
        runtimeInputs: runtimeInputs,
      ),
    );
  }

  final ScenarioLabUiCapabilityState run;
  final ScenarioLabUiCapabilityState relay;

  bool get runAvailable => run == ScenarioLabUiCapabilityState.available;
  bool get relayAvailable => relay == ScenarioLabUiCapabilityState.available;
}

ScenarioLabUiCapabilityState _runState({
  required bool labModuleEnabled,
  required bool hasContentGeneration,
  required ExperienceContentSetIdentity? contentIdentity,
  required ScenarioLabManifest? manifest,
  required StudioHostClient? client,
  required Set<String> rpcMethods,
}) {
  if (!labModuleEnabled) return ScenarioLabUiCapabilityState.moduleDisabled;
  if (!hasContentGeneration ||
      contentIdentity == null ||
      manifest == null ||
      contentIdentity.scenarioLabManifestDigest != manifest.digest ||
      contentIdentity.catalogDigest != manifest.catalogDigest) {
    return ScenarioLabUiCapabilityState.contentUnavailable;
  }
  if (client is! StudioHostScenarioLabRunClient) {
    return ScenarioLabUiCapabilityState.clientUnavailable;
  }
  try {
    return selectStudioScenarioLabRunTransport(rpcMethods) ==
            StudioScenarioLabRunTransportAvailability.available
        ? ScenarioLabUiCapabilityState.available
        : ScenarioLabUiCapabilityState.rpcUnavailable;
  } on FormatException {
    return ScenarioLabUiCapabilityState.rpcIncomplete;
  }
}

ScenarioLabUiCapabilityState _relayState({
  required ScenarioLabUiCapabilityState run,
  required StudioHostClient? client,
  required Set<String> rpcMethods,
  required ScenarioLabRuntimeInputBinding? runtimeInputs,
}) {
  if (run != ScenarioLabUiCapabilityState.available) {
    return ScenarioLabUiCapabilityState.runUnavailable;
  }
  if (client is! StudioHostLabRelayClient) {
    return ScenarioLabUiCapabilityState.clientUnavailable;
  }
  try {
    return selectStudioLabRelayTransport(
              rpcMethods,
              requiresGateway: runtimeInputs?.gatewayPresetId != null,
            ) !=
            StudioLabRelayTransportAvailability.unavailable
        ? ScenarioLabUiCapabilityState.available
        : ScenarioLabUiCapabilityState.rpcUnavailable;
  } on StudioLabRelayGatewayV2Required {
    return ScenarioLabUiCapabilityState.gatewayV2Required;
  } on FormatException {
    return ScenarioLabUiCapabilityState.rpcIncomplete;
  }
}
