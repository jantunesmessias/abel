import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final environment = AndroidDeviceEnvironment(
    imageDescriptor: 'Neutral_API_35|sdk/test|api-35|x86_64',
    imageDigest: Digest.semantic('android-image'),
    apiLevel: 35,
    abi: 'x86_64',
    renderer: 'skiagl',
    locale: 'pt-BR',
    timezone: 'America/Sao_Paulo',
    toolchain: const <String, String>{
      'adb': 'Android Debug Bridge version 1.0.41',
      'dart': '3.12.2',
    },
  );
  final manifest = AndroidEvidenceManifest(
    correlationId: 'android-correlation-1',
    targetId: 'emulator-5556',
    environment: environment,
    containmentReportDigest: Digest.semantic('containment'),
    collectedAt: DateTime.utc(2026, 8, 9, 12),
    syntheticDataConfirmed: true,
    observations: <AndroidEvidenceObservation>[
      AndroidEvidenceObservation(
        role: 'android.screenshot',
        status: AndroidEvidenceStatus.collected,
        detailCode: 'collected',
        artifactDigest: Digest.semantic('screenshot'),
      ),
      AndroidEvidenceObservation(
        role: 'android.performance-trace',
        status: AndroidEvidenceStatus.unavailable,
        detailCode: 'target_command_unavailable',
      ),
    ],
  );
  final visual = VisualComparisonPolicy(
    id: 'visual-strict-v1',
    maxChannelDelta: 1,
    maxChangedPixelRatio: 0.01,
  );
  final semantic = SemanticComparisonPolicy(
    id: 'semantic-strict-v1',
    maxChangedNodes: 0,
    ignoreBounds: true,
  );
  final report = EvidenceComparisonReport(
    comparisonKind: 'visual',
    expectedDigest: Digest.semantic('expected'),
    actualDigest: Digest.semantic('actual'),
    policyDigest: visual.digest,
    passed: true,
    comparedUnits: 10,
    changedUnits: 0,
    metrics: const <String, Object?>{'changedPixelRatio': 0.0},
  );

  test('Android evidence documents round-trip through the closed schema', () {
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(_root(), 'schemas/v1/android-evidence.schema.json'),
            ).readAsStringSync(),
          )
          as Object,
    );
    for (final document in <Map<String, Object?>>[
      manifest.toJson(),
      visual.toJson(),
      semantic.toJson(),
      report.toJson(),
    ]) {
      expect(validator.validate(document).isValid, isTrue, reason: '$document');
    }
    expect(
      AndroidEvidenceManifest.fromJson(manifest.toJson()).digest,
      manifest.digest,
    );
    expect(
      VisualComparisonPolicy.fromJson(visual.toJson()).digest,
      visual.digest,
    );
    expect(
      SemanticComparisonPolicy.fromJson(semantic.toJson()).digest,
      semantic.digest,
    );
    expect(
      EvidenceComparisonReport.fromJson(report.toJson()).digest,
      report.digest,
    );
  });

  test('observation status and artifact digest cannot disagree', () {
    expect(
      () => AndroidEvidenceObservation(
        role: 'android.logcat',
        status: AndroidEvidenceStatus.failed,
        detailCode: 'collection_failed',
        artifactDigest: Digest.semantic('forbidden'),
      ),
      throwsArgumentError,
    );
    final invalid = manifest.toJson();
    final observations = invalid['observations']! as List<Object?>;
    final collected = observations.cast<Map<String, Object?>>().singleWhere(
      (item) => item['status'] == 'collected',
    );
    collected.remove('artifactDigest');
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(_root(), 'schemas/v1/android-evidence.schema.json'),
            ).readAsStringSync(),
          )
          as Object,
    );
    expect(validator.validate(invalid).isValid, isFalse);
  });
}

String _root() {
  var directory = Directory.current.absolute;
  while (!File(
    p.join(directory.path, 'pubspec.yaml'),
  ).readAsStringSync().contains('name: devex_workspace')) {
    directory = directory.parent;
  }
  return directory.path;
}
