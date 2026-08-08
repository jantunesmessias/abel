import '../digest.dart';
import 'evidence_contracts.dart';

final class TestEvidenceSummary {
  TestEvidenceSummary({
    required this.providerId,
    required this.runnerProtocolVersion,
    required this.runnerVersion,
    required this.success,
    required this.total,
    required this.passed,
    required this.failed,
    required this.skipped,
    required this.durationMilliseconds,
    required Set<String> platforms,
    required this.reportArtifact,
    required List<Artifact> referencedArtifacts,
  }) : platforms = Set<String>.unmodifiable(platforms),
       referencedArtifacts = List<Artifact>.unmodifiable(referencedArtifacts) {
    _nonEmpty(providerId, 'providerId');
    _nonEmpty(runnerProtocolVersion, 'runnerProtocolVersion');
    _nonEmpty(runnerVersion, 'runnerVersion');
    if (<int>[
      total,
      passed,
      failed,
      skipped,
      durationMilliseconds,
    ].any((value) => value < 0)) {
      throw ArgumentError('Test evidence counters must be non-negative');
    }
    if (passed + failed + skipped != total) {
      throw ArgumentError('Test evidence counters do not add up');
    }
    if (success != (failed == 0)) {
      throw ArgumentError('Test evidence success contradicts failed count');
    }
    if (platforms.isEmpty || platforms.any((value) => value.isEmpty)) {
      throw ArgumentError('Test evidence requires runner platforms');
    }
    final digests = <Digest>{reportArtifact.digest};
    for (final artifact in referencedArtifacts) {
      if (!digests.add(artifact.digest)) {
        throw ArgumentError('Test evidence artifact digests must be unique');
      }
    }
  }

  static const int schemaVersion = 1;

  final String providerId;
  final String runnerProtocolVersion;
  final String runnerVersion;
  final bool success;
  final int total;
  final int passed;
  final int failed;
  final int skipped;
  final int durationMilliseconds;
  final Set<String> platforms;
  final Artifact reportArtifact;
  final List<Artifact> referencedArtifacts;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'TestEvidenceSummary',
    'providerId': providerId,
    'runnerProtocolVersion': runnerProtocolVersion,
    'runnerVersion': runnerVersion,
    'success': success,
    'total': total,
    'passed': passed,
    'failed': failed,
    'skipped': skipped,
    'durationMilliseconds': durationMilliseconds,
    'platforms': platforms.toList()..sort(),
    'reportArtifact': reportArtifact.toJson(),
    'referencedArtifacts': referencedArtifacts
        .map((artifact) => artifact.toJson())
        .toList(growable: false),
    if (includeDigest) 'digest': digest.value,
  };

  factory TestEvidenceSummary.fromJson(Object? value) {
    final json = _object(value, 'TestEvidenceSummary');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'providerId',
      'runnerProtocolVersion',
      'runnerVersion',
      'success',
      'total',
      'passed',
      'failed',
      'skipped',
      'durationMilliseconds',
      'platforms',
      'reportArtifact',
      'referencedArtifacts',
      'digest',
    }, 'TestEvidenceSummary');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'TestEvidenceSummary') {
      throw const FormatException('Invalid TestEvidenceSummary version');
    }
    final summary = TestEvidenceSummary(
      providerId: _string(json, 'providerId', 'TestEvidenceSummary'),
      runnerProtocolVersion: _string(
        json,
        'runnerProtocolVersion',
        'TestEvidenceSummary',
      ),
      runnerVersion: _string(json, 'runnerVersion', 'TestEvidenceSummary'),
      success: _boolean(json, 'success', 'TestEvidenceSummary'),
      total: _integer(json, 'total', 'TestEvidenceSummary'),
      passed: _integer(json, 'passed', 'TestEvidenceSummary'),
      failed: _integer(json, 'failed', 'TestEvidenceSummary'),
      skipped: _integer(json, 'skipped', 'TestEvidenceSummary'),
      durationMilliseconds: _integer(
        json,
        'durationMilliseconds',
        'TestEvidenceSummary',
      ),
      platforms: _stringList(
        json['platforms'],
        'TestEvidenceSummary.platforms',
      ).toSet(),
      reportArtifact: Artifact.fromJson(json['reportArtifact']),
      referencedArtifacts: _list(
        json['referencedArtifacts'],
        'TestEvidenceSummary.referencedArtifacts',
      ).map(Artifact.fromJson).toList(growable: false),
    );
    if (summary.digest !=
        Digest(_string(json, 'digest', 'TestEvidenceSummary'))) {
      throw const FormatException('TestEvidenceSummary digest mismatch');
    }
    return summary;
  }
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path must be a list');
  return value;
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

List<String> _stringList(Object? value, String path) {
  final list = _list(value, path);
  if (list.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path must contain non-empty strings');
  }
  return list.cast<String>();
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

void _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name);
}
