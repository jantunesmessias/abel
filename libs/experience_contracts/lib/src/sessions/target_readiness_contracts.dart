import '../digest.dart';

final class TargetLaunchAttemptId {
  factory TargetLaunchAttemptId(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value)) {
      throw FormatException('Target launch attempt ID is invalid');
    }
    return TargetLaunchAttemptId._(value);
  }

  const TargetLaunchAttemptId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is TargetLaunchAttemptId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// One readiness observation emitted by a Host-owned child process.
///
/// The launch attempt is an opaque correlation value, not a relay credential.
/// The Host must additionally compare [processId] with the process it started
/// and probe [origin] before publishing an execution target.
final class TargetReadinessRecord {
  TargetReadinessRecord({
    required this.launchAttemptId,
    required this.targetId,
    required this.launchProfileId,
    required Uri origin,
    required this.processId,
  }) : origin = _canonicalLoopbackOrigin(origin) {
    _readinessId(targetId, 'targetId');
    _readinessId(launchProfileId, 'launchProfileId');
    if (processId < 1 || processId > 9007199254740991) {
      throw ArgumentError.value(
        processId,
        'processId',
        'must be a positive JSON-safe integer',
      );
    }
  }

  static const int schemaVersion = 1;

  final TargetLaunchAttemptId launchAttemptId;
  final String targetId;
  final String launchProfileId;
  final Uri origin;
  final int processId;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'TargetReadinessRecord',
    'launchAttemptId': launchAttemptId.value,
    'targetId': targetId,
    'launchProfileId': launchProfileId,
    'origin': origin.toString(),
    'processId': processId,
    if (includeDigest) 'digest': digest.value,
  };

  factory TargetReadinessRecord.fromJson(Object? value) {
    final json = _readinessObject(value);
    const fields = <String>{
      'schemaVersion',
      'kind',
      'launchAttemptId',
      'targetId',
      'launchProfileId',
      'origin',
      'processId',
      'digest',
    };
    if (json.keys.any((key) => !fields.contains(key)) ||
        json.length != fields.length ||
        json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'TargetReadinessRecord') {
      throw const FormatException('Invalid TargetReadinessRecord document');
    }
    final originValue = _readinessString(json, 'origin');
    final parsedOrigin = Uri.tryParse(originValue);
    if (parsedOrigin == null) {
      throw const FormatException('Target readiness origin is invalid');
    }
    final processId = json['processId'];
    if (processId is! int) {
      throw const FormatException('Target readiness processId must be integer');
    }
    final record = TargetReadinessRecord(
      launchAttemptId: TargetLaunchAttemptId(
        _readinessString(json, 'launchAttemptId'),
      ),
      targetId: _readinessString(json, 'targetId'),
      launchProfileId: _readinessString(json, 'launchProfileId'),
      origin: parsedOrigin,
      processId: processId,
    );
    if (originValue != record.origin.toString()) {
      throw const FormatException('Target readiness origin is not canonical');
    }
    if (Digest(_readinessString(json, 'digest')) != record.digest) {
      throw const FormatException('Target readiness digest mismatch');
    }
    return record;
  }
}

Uri _canonicalLoopbackOrigin(Uri value) {
  if (!const <String>{'http', 'https'}.contains(value.scheme) ||
      !const <String>{'localhost', '127.0.0.1', '::1'}.contains(value.host) ||
      value.port < 1 ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw FormatException(
      'Target readiness requires a loopback HTTP(S) origin',
    );
  }
  return Uri.parse(value.origin);
}

void _readinessId(String value, String field) {
  if (value.length > 256 ||
      !RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(value)) {
    throw FormatException('Target readiness $field is invalid');
  }
}

Map<String, Object?> _readinessObject(Object? value) {
  if (value is! Map) {
    throw const FormatException('TargetReadinessRecord must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('TargetReadinessRecord keys must be strings');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _readinessString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 2048) {
    throw FormatException('Target readiness $key must be a bounded string');
  }
  return value;
}
