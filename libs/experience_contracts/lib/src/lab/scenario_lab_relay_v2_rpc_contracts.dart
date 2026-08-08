import '../digest.dart';
import 'scenario_lab_execution_contracts.dart';
import 'scenario_lab_relay_rpc_contracts.dart';

/// Closed RPC parameters for the fenced relay v2 description.
final class ScenarioLabRelayDescribeRequestV2 {
  const ScenarioLabRelayDescribeRequestV2({
    required this.runId,
    required this.expectedStartRequestDigest,
  });

  final ScenarioLabRunId runId;
  final Digest expectedStartRequestDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId.value,
    'expectedStartRequestDigest': expectedStartRequestDigest.value,
  };

  factory ScenarioLabRelayDescribeRequestV2.fromJson(Object? value) {
    final json = _relayV2Object(value, 'ScenarioLabRelayDescribeRequestV2');
    _relayV2Only(json, const <String>{
      'runId',
      'expectedStartRequestDigest',
    }, 'ScenarioLabRelayDescribeRequestV2');
    return ScenarioLabRelayDescribeRequestV2(
      runId: ScenarioLabRunId(
        _relayV2String(json, 'runId', 'ScenarioLabRelayDescribeRequestV2'),
      ),
      expectedStartRequestDigest: Digest(
        _relayV2String(
          json,
          'expectedStartRequestDigest',
          'ScenarioLabRelayDescribeRequestV2',
        ),
      ),
    );
  }
}

/// Fenced relay description that can safely expose a Host-owned Gateway.
///
/// The v1 descriptor remains byte-for-byte the nested v1 document used by the
/// hello, next and result RPCs. Runtime inputs and the optional Gateway origin
/// are added only when all ready-state bindings can be observed atomically.
final class ScenarioLabRelayDescriptionV2 {
  ScenarioLabRelayDescriptionV2({
    required this.runId,
    required this.startRequestDigest,
    required this.status,
    this.descriptor,
    this.runtimeInputs,
    Uri? gatewayDataOrigin,
  }) : gatewayDataOrigin = gatewayDataOrigin == null
           ? null
           : canonicalScenarioLabGatewayDataOrigin(gatewayDataOrigin) {
    final ready = status == ScenarioLabRelayDescriptionStatus.ready;
    if (ready != (descriptor != null) ||
        ready != (runtimeInputs != null) ||
        (!ready && this.gatewayDataOrigin != null)) {
      throw ArgumentError(
        'Scenario Lab relay v2 ready fields must be present together',
      );
    }
    if (!ready) return;
    final target = descriptor!;
    final inputs = runtimeInputs!;
    if (target.runId != runId || target.targetId != inputs.executionTargetId) {
      throw ArgumentError(
        'Scenario Lab relay v2 target does not match its runtime inputs',
      );
    }
    if ((inputs.gatewayPresetId != null) != (this.gatewayDataOrigin != null)) {
      throw ArgumentError(
        'Scenario Lab relay v2 Gateway origin does not match runtime inputs',
      );
    }
  }

  static const int schemaVersion = 2;
  final ScenarioLabRunId runId;
  final Digest startRequestDigest;
  final ScenarioLabRelayDescriptionStatus status;
  final ScenarioLabRelayTargetDescriptor? descriptor;
  final ScenarioLabRuntimeInputBinding? runtimeInputs;
  final Uri? gatewayDataOrigin;

  bool get requiresGateway => runtimeInputs?.gatewayPresetId != null;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  void validateAgainst(ScenarioLabRelayDescribeRequestV2 request) {
    if (runId != request.runId ||
        startRequestDigest != request.expectedStartRequestDigest) {
      throw ArgumentError(
        'Scenario Lab relay v2 description does not match its request',
      );
    }
  }

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayDescription',
    'runId': runId.value,
    'startRequestDigest': startRequestDigest.value,
    'status': status.name,
    if (descriptor != null) 'descriptor': descriptor!.toJson(),
    if (runtimeInputs != null) 'runtimeInputs': runtimeInputs!.toJson(),
    if (gatewayDataOrigin != null)
      'gatewayDataOrigin': gatewayDataOrigin!.toString(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayDescriptionV2.fromJson(Object? value) {
    final json = _relayV2Object(value, 'ScenarioLabRelayDescriptionV2');
    _relayV2Only(json, const <String>{
      'schemaVersion',
      'kind',
      'runId',
      'startRequestDigest',
      'status',
      'descriptor',
      'runtimeInputs',
      'gatewayDataOrigin',
      'digest',
    }, 'ScenarioLabRelayDescriptionV2');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ScenarioLabRelayDescription' ||
        !json.keys.toSet().containsAll(const <String>{
          'schemaVersion',
          'kind',
          'runId',
          'startRequestDigest',
          'status',
          'digest',
        })) {
      throw const FormatException(
        'Invalid ScenarioLabRelayDescriptionV2 document',
      );
    }
    final rawGatewayDataOrigin = json['gatewayDataOrigin'];
    final gatewayDataOrigin = rawGatewayDataOrigin == null
        ? null
        : Uri.tryParse(
            _relayV2String(
              json,
              'gatewayDataOrigin',
              'ScenarioLabRelayDescriptionV2',
            ),
          );
    if (rawGatewayDataOrigin != null && gatewayDataOrigin == null) {
      throw const FormatException(
        'ScenarioLabRelayDescriptionV2.gatewayDataOrigin must be a URI',
      );
    }
    final description = ScenarioLabRelayDescriptionV2(
      runId: ScenarioLabRunId(
        _relayV2String(json, 'runId', 'ScenarioLabRelayDescriptionV2'),
      ),
      startRequestDigest: Digest(
        _relayV2String(
          json,
          'startRequestDigest',
          'ScenarioLabRelayDescriptionV2',
        ),
      ),
      status: _relayV2Status(
        _relayV2String(json, 'status', 'ScenarioLabRelayDescriptionV2'),
      ),
      descriptor: json.containsKey('descriptor')
          ? ScenarioLabRelayTargetDescriptor.fromJson(json['descriptor'])
          : null,
      runtimeInputs: json.containsKey('runtimeInputs')
          ? ScenarioLabRuntimeInputBinding.fromJson(json['runtimeInputs'])
          : null,
      gatewayDataOrigin: gatewayDataOrigin,
    );
    final encodedDigest = Digest(
      _relayV2String(json, 'digest', 'ScenarioLabRelayDescriptionV2'),
    );
    if (encodedDigest != description.digest) {
      throw const FormatException(
        'ScenarioLabRelayDescriptionV2 digest mismatch',
      );
    }
    return description;
  }
}

Map<String, Object?> _relayV2Object(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$path must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

void _relayV2Only(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _relayV2String(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 4096) {
    throw FormatException('$path.$key must be a bounded string');
  }
  return value;
}

ScenarioLabRelayDescriptionStatus _relayV2Status(String value) {
  for (final status in ScenarioLabRelayDescriptionStatus.values) {
    if (status.name == value) return status;
  }
  throw const FormatException(
    'ScenarioLabRelayDescriptionV2.status has an unknown value',
  );
}

/// Validates and normalizes the only Gateway origin accepted by relay v2.
Uri canonicalScenarioLabGatewayDataOrigin(Uri value) {
  const hosts = <String>{'127.0.0.1', '::1', 'localhost'};
  if (value.scheme != 'http' ||
      !hosts.contains(value.host) ||
      !value.hasPort ||
      value.port < 1 ||
      value.port > 65535 ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw const FormatException(
      'Scenario Lab Gateway data origin must be a canonical HTTP loopback origin',
    );
  }
  return value.replace(path: '');
}
