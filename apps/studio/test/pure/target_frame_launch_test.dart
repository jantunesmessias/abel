import 'dart:convert';

import 'package:studio/src/target_frame/target_frame_launch.dart';
import 'package:test/test.dart';

void main() {
  test('normal Session launch never opts into Scenario Lab relay', () {
    final uri = buildTargetFrameLaunchUri(
      targetUri: Uri.parse('http://127.0.0.1:8181'),
      sessionId: 'session-1',
      nonce: 'session-nonce',
      controllerOrigin: 'http://127.0.0.1:7367',
    );

    expect(_launch(uri), <String, Object?>{
      'SESSION_ID': 'session-1',
      'SESSION_NONCE': 'session-nonce',
      'TARGET_CONTROLLER_ORIGIN': 'http://127.0.0.1:7367',
    });
  });

  test('explicit relay mount carries only its exact Scenario Lab run', () {
    final uri = buildTargetFrameLaunchUri(
      targetUri: Uri.parse('http://127.0.0.1:8181'),
      sessionId: 'run-00000001',
      nonce: 'relay-nonce',
      controllerOrigin: 'http://127.0.0.1:7367',
      scenarioLabRunId: 'run-00000001',
    );

    final launch = _launch(uri);
    expect(launch['SCENARIO_LAB_RUN_ID'], 'run-00000001');
    expect(launch, isNot(contains('GATEWAY_ORIGIN')));
  });

  test('relay injects only its Host-owned v2 Gateway data origin', () {
    final uri = buildTargetFrameLaunchUri(
      targetUri: Uri.parse('http://127.0.0.1:8181'),
      sessionId: 'run-00000001',
      nonce: 'relay-nonce',
      controllerOrigin: 'http://127.0.0.1:7367',
      scenarioLabRunId: 'run-00000001',
      gatewayDataOrigin: Uri.parse('http://127.0.0.1:8090'),
    );

    expect(_launch(uri)['GATEWAY_ORIGIN'], 'http://127.0.0.1:8090');
  });

  test('Gateway-bound relay rejects a Studio-same-origin target', () {
    expect(
      () => buildTargetFrameLaunchUri(
        targetUri: Uri.parse('http://127.0.0.1:7367/target'),
        sessionId: 'run-00000001',
        nonce: 'relay-nonce',
        controllerOrigin: 'http://127.0.0.1:7367',
        scenarioLabRunId: 'run-00000001',
        gatewayDataOrigin: Uri.parse('http://127.0.0.1:8090'),
      ),
      throwsArgumentError,
    );
  });

  test('relay rejects gatewayOrigin and non-relay gatewayDataOrigin', () {
    expect(
      () => buildTargetFrameLaunchUri(
        targetUri: Uri.parse('http://127.0.0.1:8181'),
        sessionId: 'run-00000001',
        nonce: 'relay-nonce',
        controllerOrigin: 'http://127.0.0.1:7367',
        scenarioLabRunId: 'run-00000001',
        gatewayOrigin: Uri.parse('http://127.0.0.1:8090'),
      ),
      throwsArgumentError,
    );
    expect(
      () => buildTargetFrameLaunchUri(
        targetUri: Uri.parse('http://127.0.0.1:8181'),
        sessionId: 'session-1',
        nonce: 'session-nonce',
        controllerOrigin: 'http://127.0.0.1:7367',
        gatewayDataOrigin: Uri.parse('http://127.0.0.1:8090'),
      ),
      throwsArgumentError,
    );
  });

  test('relay launch rejects a run and session identity mismatch', () {
    expect(
      () => buildTargetFrameLaunchUri(
        targetUri: Uri.parse('http://127.0.0.1:8181'),
        sessionId: 'run-00000001',
        nonce: 'relay-nonce',
        controllerOrigin: 'http://127.0.0.1:7367',
        scenarioLabRunId: 'run-00000002',
      ),
      throwsArgumentError,
    );
  });

  test('controller and listener are active before target navigation', () {
    final operations = <String>[];

    activateTargetFrameInOrder(
      attachController: () => operations.add('controller'),
      registerAuthorizedListener: () => operations.add('listener'),
      navigate: () => operations.add('navigate'),
    );

    expect(operations, <String>['controller', 'listener', 'navigate']);
  });

  test('rendered iframe source never contains the launch location', () {
    expect(targetFrameRenderedSource(), 'about:blank');
  });
}

Map<String, Object?> _launch(Uri uri) {
  final fragment = uri.fragment;
  expect(fragment, startsWith('target-launch='));
  final encoded = fragment.substring('target-launch='.length);
  final decoded = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
  );
  return (decoded as Map<Object?, Object?>).cast<String, Object?>();
}
