import 'dart:math';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:flutter_app_adapter/flutter_app_adapter.dart';

const String sampleScenarioLabRunOverlayKey = 'SCENARIO_LAB_RUN_ID';

AppAdapterRelayConfiguration? sampleRelayConfiguration({
  required Map<String, String> launchOverlay,
  required String sessionId,
  required String nonce,
  String Function()? createAdapterInstanceId,
}) {
  final encodedRunId = launchOverlay[sampleScenarioLabRunOverlayKey];
  if (encodedRunId == null) return null;
  final runId = ScenarioLabRunId(encodedRunId);
  if (runId.value != sessionId) {
    throw const FormatException(
      'Scenario Lab run must match the target session binding',
    );
  }
  return AppAdapterRelayConfiguration(
    runId: runId,
    adapterInstanceId: (createAdapterInstanceId ?? _newAdapterInstanceId)
        .call(),
    nonce: AppAdapterRelayNonce(nonce),
    evidenceProviderIds: <ModuleId>[ModuleId('capture.app-adapter')],
  );
}

String _newAdapterInstanceId() {
  final random = Random.secure();
  final entropy = List<int>.generate(16, (_) => random.nextInt(256));
  final suffix = entropy
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'sample-adapter-$suffix';
}
