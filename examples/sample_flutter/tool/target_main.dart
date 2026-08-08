import 'package:flutter/widgets.dart';
import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:sample_flutter/app_factory.dart';
import 'package:sample_flutter/showcase_models.dart';

import 'target_launch_context.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchOverlay = <String, String>{
    ...await RuntimeOverlay.readAndroidLaunchOverlay(),
    ...RuntimeOverlay.readWebLaunchOverlay(),
  };
  const apiBaseUrl = String.fromEnvironment(
    'EXAMPLE_API_URL',
    defaultValue: 'http://127.0.0.1:8181',
  );
  const dashboardState = String.fromEnvironment(
    'EXAMPLE_DASHBOARD_STATE',
    defaultValue: 'ready',
  );
  const sessionId = String.fromEnvironment(
    'SESSION_ID',
    defaultValue: 'sample-session',
  );
  const nonce = String.fromEnvironment(
    'SESSION_NONCE',
    defaultValue: '0123456789abcdef',
  );
  const controllerOrigin = String.fromEnvironment(
    'TARGET_CONTROLLER_ORIGIN',
    defaultValue: 'http://127.0.0.1:7368',
  );
  final effectiveApiBaseUrl = launchOverlay['GATEWAY_ORIGIN'] ?? apiBaseUrl;
  final effectiveDashboardState =
      launchOverlay['EXAMPLE_DASHBOARD_STATE'] ?? dashboardState;
  final effectiveSessionId = launchOverlay['SESSION_ID'] ?? sessionId;
  final effectiveNonce = launchOverlay['SESSION_NONCE'] ?? nonce;
  final effectiveControllerOrigin =
      launchOverlay['TARGET_CONTROLLER_ORIGIN'] ?? controllerOrigin;
  final readyHighlight = ValueNotifier<bool>(false);
  final readyHighlightControl = BooleanControlCapability(
    id: 'sample.dashboard.ready-control',
    readOperation: 'read-enabled',
    writeOperation: 'write-enabled',
    resetOperation: 'reset-enabled',
    read: () => readyHighlight.value,
    write: (value) => readyHighlight.value = value,
    reset: () => readyHighlight.value = false,
  );
  final binding = TargetBinding(
    sessionId: effectiveSessionId,
    nonce: effectiveNonce,
    runtimeConfiguration: <String, String>{
      'EXAMPLE_API_URL': effectiveApiBaseUrl,
      'EXAMPLE_DASHBOARD_STATE': effectiveDashboardState,
    },
    capabilities: const <String>{
      'capture.png',
      'checkpoint.open',
      'sample.dashboard.ready-control',
    },
    controllerOrigin: Uri.parse(effectiveControllerOrigin),
  );

  runFlutterTarget(
    binding: binding,
    capabilities: <AppCapability>[readyHighlightControl],
    relayConfiguration: sampleRelayConfiguration(
      launchOverlay: launchOverlay,
      sessionId: effectiveSessionId,
      nonce: effectiveNonce,
    ),
    app: createSampleApp(
      SampleAppConfig(
        apiBaseUrl: effectiveApiBaseUrl,
        environment: 'workspace-tooling',
        dashboardState: ShowcaseDashboardState.parse(effectiveDashboardState),
      ),
      readyHighlight: readyHighlight,
    ),
  );
}
