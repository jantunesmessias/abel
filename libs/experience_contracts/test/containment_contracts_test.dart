import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final report = TargetContainmentReport(
    targetId: 'chromium-namespace',
    adapterId: 'linux-user-netns-v1',
    platform: 'web',
    executedAt: DateTime.utc(2026, 8, 9),
    networkContainment: NetworkContainment.targetEnforced,
    probes: <ContainmentProbeResult>[
      ContainmentProbeResult(
        kind: ContainmentProbeKind.gatewayReachable,
        passed: true,
        detailCode: 'http_204',
      ),
      ContainmentProbeResult(
        kind: ContainmentProbeKind.directEgressDenied,
        passed: true,
        detailCode: 'network_unreachable',
      ),
    ],
  );

  test('round-trips and conforms to the external schema', () {
    final decoded = TargetContainmentReport.fromJson(report.toJson());
    expect(decoded.digest, report.digest);
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'gateway',
                'containment-report.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );
    expect(validator.validate(report.toJson()).isValid, isTrue);
  });

  test('cannot claim targetEnforced without both successful probes', () {
    expect(
      () => TargetContainmentReport(
        targetId: 'target',
        adapterId: 'adapter',
        platform: 'web',
        executedAt: DateTime.utc(2026),
        networkContainment: NetworkContainment.targetEnforced,
        probes: <ContainmentProbeResult>[
          ContainmentProbeResult(
            kind: ContainmentProbeKind.gatewayReachable,
            passed: true,
            detailCode: 'http_204',
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
