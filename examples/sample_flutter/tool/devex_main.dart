import 'package:devex_flutter/devex_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:sample_flutter/app_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchOverlay = <String, String>{
    ...await DevExRuntimeOverlay.readAndroidLaunchOverlay(),
    ...DevExRuntimeOverlay.readWebLaunchOverlay(),
  };
  const apiBaseUrl = String.fromEnvironment(
    'EXAMPLE_API_URL',
    defaultValue: 'http://127.0.0.1:8181',
  );
  const sessionId = String.fromEnvironment(
    'DEVEX_SESSION_ID',
    defaultValue: 'sample-session',
  );
  const nonce = String.fromEnvironment(
    'DEVEX_SESSION_NONCE',
    defaultValue: '0123456789abcdef',
  );
  const controllerOrigin = String.fromEnvironment(
    'DEVEX_CONTROLLER_ORIGIN',
    defaultValue: 'http://127.0.0.1:7368',
  );
  final effectiveApiBaseUrl =
      launchOverlay['DEVEX_GATEWAY_ORIGIN'] ?? apiBaseUrl;
  final effectiveSessionId = launchOverlay['DEVEX_SESSION_ID'] ?? sessionId;
  final effectiveNonce = launchOverlay['DEVEX_SESSION_NONCE'] ?? nonce;
  final effectiveControllerOrigin =
      launchOverlay['DEVEX_CONTROLLER_ORIGIN'] ?? controllerOrigin;
  final binding = DevExFlutterBinding(
    sessionId: effectiveSessionId,
    nonce: effectiveNonce,
    runtimeConfiguration: <String, String>{
      'EXAMPLE_API_URL': effectiveApiBaseUrl,
    },
    capabilities: const <String>{'capture.png', 'checkpoint.open'},
    controllerOrigin: Uri.parse(effectiveControllerOrigin),
  );

  runDevExFlutterTarget(
    binding: binding,
    app: createSampleApp(
      SampleAppConfig(
        apiBaseUrl: effectiveApiBaseUrl,
        environment: 'devex-tooling',
      ),
    ),
  );
}
