import '../digest.dart';
import 'evidence_contracts.dart';

enum ContainmentProbeKind { gatewayReachable, directEgressDenied }

final class ContainmentProbeResult {
  ContainmentProbeResult({
    required this.kind,
    required this.passed,
    required this.detailCode,
  }) {
    if (!RegExp(r'^[a-z][a-z0-9_.-]{0,127}$').hasMatch(detailCode)) {
      throw ArgumentError.value(detailCode, 'detailCode');
    }
  }

  final ContainmentProbeKind kind;
  final bool passed;
  final String detailCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'passed': passed,
    'detailCode': detailCode,
  };

  factory ContainmentProbeResult.fromJson(Object? value) {
    final json = _object(value, 'ContainmentProbeResult');
    _only(json, const <String>{'kind', 'passed', 'detailCode'}, 'probe');
    return ContainmentProbeResult(
      kind: _enumValue(
        ContainmentProbeKind.values,
        _string(json, 'kind', 'probe'),
        'probe.kind',
      ),
      passed: _boolean(json, 'passed', 'probe'),
      detailCode: _string(json, 'detailCode', 'probe'),
    );
  }
}

/// Executed proof for a target-side network containment adapter.
///
/// A Gateway plan remains `gatewayOnly`; only this report may establish that
/// the target itself was prevented from bypassing the Gateway.
final class TargetContainmentReport {
  TargetContainmentReport({
    required this.targetId,
    required this.adapterId,
    required this.platform,
    required this.executedAt,
    required this.networkContainment,
    required List<ContainmentProbeResult> probes,
  }) : probes = List<ContainmentProbeResult>.unmodifiable(probes) {
    _nonEmpty(targetId, 'targetId');
    _nonEmpty(adapterId, 'adapterId');
    if (platform != 'web' && platform != 'androidEmulator') {
      throw ArgumentError('Unsupported containment platform');
    }
    if (!executedAt.isUtc) throw ArgumentError('executedAt must be UTC');
    if (networkContainment == NetworkContainment.unconstrained) {
      throw ArgumentError('A containment adapter cannot report unconstrained');
    }
    if (_duplicates(this.probes.map((probe) => probe.kind))) {
      throw ArgumentError('Containment probes must be unique');
    }
    if (networkContainment == NetworkContainment.targetEnforced) {
      final passed = <ContainmentProbeKind>{
        for (final probe in this.probes)
          if (probe.passed) probe.kind,
      };
      if (!passed.containsAll(ContainmentProbeKind.values)) {
        throw ArgumentError(
          'targetEnforced requires successful Gateway and egress probes',
        );
      }
    }
  }

  static const int schemaVersion = 1;

  final String targetId;
  final String adapterId;
  final String platform;
  final DateTime executedAt;
  final NetworkContainment networkContainment;
  final List<ContainmentProbeResult> probes;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'TargetContainmentReport',
    'targetId': targetId,
    'adapterId': adapterId,
    'platform': platform,
    'executedAt': executedAt.toIso8601String(),
    'networkContainment': networkContainment.name,
    'probes': probes.map((probe) => probe.toJson()).toList(growable: false),
    if (includeDigest) 'digest': digest.value,
  };

  factory TargetContainmentReport.fromJson(Object? value) {
    final json = _object(value, 'TargetContainmentReport');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'targetId',
      'adapterId',
      'platform',
      'executedAt',
      'networkContainment',
      'probes',
      'digest',
    }, 'TargetContainmentReport');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'TargetContainmentReport') {
      throw const FormatException('Invalid TargetContainmentReport version');
    }
    final report = TargetContainmentReport(
      targetId: _string(json, 'targetId', 'TargetContainmentReport'),
      adapterId: _string(json, 'adapterId', 'TargetContainmentReport'),
      platform: _string(json, 'platform', 'TargetContainmentReport'),
      executedAt: DateTime.parse(
        _string(json, 'executedAt', 'TargetContainmentReport'),
      ),
      networkContainment: _enumValue(
        NetworkContainment.values,
        _string(json, 'networkContainment', 'TargetContainmentReport'),
        'TargetContainmentReport.networkContainment',
      ),
      probes: _list(
        json['probes'],
        'TargetContainmentReport.probes',
      ).map(ContainmentProbeResult.fromJson).toList(growable: false),
    );
    if (Digest(_string(json, 'digest', 'TargetContainmentReport')) !=
        report.digest) {
      throw const FormatException('TargetContainmentReport digest mismatch');
    }
    return report;
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

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

T _enumValue<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path is invalid');
}

void _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name);
}

bool _duplicates(Iterable<Object?> values) {
  final seen = <Object?>{};
  for (final value in values) {
    if (!seen.add(value)) return true;
  }
  return false;
}
