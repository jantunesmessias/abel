import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  String option(String name) {
    final index = arguments.indexOf('--$name');
    if (index < 0 || index + 1 >= arguments.length) {
      throw FormatException('--$name is required');
    }
    return arguments[index + 1];
  }

  final serial = option('serial');
  final output = Directory(option('output-dir')).absolute;
  output.createSync(recursive: true);
  final containment = TargetContainmentReport(
    targetId: serial,
    adapterId: 'adb-reverse-v1',
    platform: 'androidEmulator',
    executedAt: DateTime.now().toUtc(),
    networkContainment: NetworkContainment.gatewayOnly,
    probes: <ContainmentProbeResult>[
      ContainmentProbeResult(
        kind: ContainmentProbeKind.gatewayReachable,
        passed: true,
        detailCode: 'adb_reverse_and_health_verified',
      ),
    ],
  );
  final visual = VisualComparisonPolicy(
    id: 'android-pixel-exact-v1',
    maxChannelDelta: 0,
    maxChangedPixelRatio: 0,
  );
  final semantic = SemanticComparisonPolicy(
    id: 'android-semantic-exact-v1',
    maxChangedNodes: 0,
    ignoreBounds: true,
  );
  final documents = <String, Map<String, Object?>>{
    'containment.json': containment.toJson(),
    'visual-policy.json': visual.toJson(),
    'semantic-policy.json': semantic.toJson(),
  };
  for (final entry in documents.entries) {
    final file = File(p.join(output.path, entry.key));
    final bytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(entry.value)}\n',
    );
    if (file.existsSync()) {
      if (!_same(file.readAsBytesSync(), bytes)) {
        throw StateError('${file.path} exists with different content');
      }
      continue;
    }
    final staging = File('${file.path}.new-$pid');
    try {
      staging.writeAsBytesSync(bytes, flush: true);
      staging.renameSync(file.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'containmentDigest': containment.digest.value,
      'visualPolicyDigest': visual.digest.value,
      'semanticPolicyDigest': semantic.digest.value,
      'outputDirectory': output.path,
    }),
  );
}

bool _same(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
