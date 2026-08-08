import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('Android lifecycle report round-trips through its closed schema', () {
    final target = AndroidTargetDescriptor(
      serial: 'emulator-5554',
      avdName: 'Neutral_API_35',
      apiLevel: 35,
      abi: 'x86_64',
      ownership: AndroidTargetOwnership.attached,
      capabilities: const <String>{'android.capture.png'},
    );
    final pairing = AndroidGatewayPairing(
      strategy: AndroidGatewayRouteStrategy.adbReverse,
      hostPort: 41234,
      targetPort: 51234,
      tls: false,
    );
    final report = AndroidLifecycleReport(
      operation: AndroidLifecycleOperation.bootstrap,
      mode: AndroidLifecycleMode.apply,
      changed: true,
      verified: true,
      actions: const <String>['apply adbReverse gateway pairing'],
      target: target,
      pairing: pairing,
    );

    expect(
      AndroidLifecycleReport.fromJson(report.toJson()).digest,
      report.digest,
    );
    final schema = jsonDecode(
      File(
        p.join(
          _repositoryRoot(),
          'schemas',
          'runtime',
          'android-lifecycle-report.schema.json',
        ),
      ).readAsStringSync(),
    );
    final result = Draft202012Validator(
      schema as Object,
    ).validate(report.toJson());
    expect(result.isValid, isTrue, reason: '${result.issues}');
  });

  test('pairing resolves target origins without domain hardcode', () {
    expect(
      AndroidGatewayPairing(
        strategy: AndroidGatewayRouteStrategy.adbReverse,
        hostPort: 41000,
        targetPort: 51000,
        tls: false,
      ).targetOrigin,
      Uri.parse('http://127.0.0.1:51000'),
    );
    expect(
      AndroidGatewayPairing(
        strategy: AndroidGatewayRouteStrategy.emulatorHostAlias,
        hostPort: 41000,
        targetPort: 41000,
        tls: true,
      ).targetOrigin,
      Uri.parse('https://10.0.2.2:41000'),
    );
  });

  test('physical devices and secret overlays fail closed', () {
    expect(
      () => AndroidTargetDescriptor(
        serial: 'R58M123456A',
        avdName: 'device',
        apiLevel: 35,
        abi: 'arm64_v8a',
        ownership: AndroidTargetOwnership.attached,
        capabilities: const <String>{'android.capture.png'},
      ),
      throwsFormatException,
    );
    expect(
      () => AndroidLaunchRequest(
        packageName: 'io.github.jantunesmessias.sample',
        activity: '.MainActivity',
        pairing: AndroidGatewayPairing(
          strategy: AndroidGatewayRouteStrategy.adbReverse,
          hostPort: 41000,
          targetPort: 51000,
          tls: false,
        ),
        overlay: RuntimeConfigurationOverlay(const <String, String>{
          'ACCESS_TOKEN': 'forbidden',
        }),
      ),
      throwsFormatException,
    );
  });
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    current = current.parent;
  }
  throw StateError('Repository root not found');
}
