import '../digest.dart';
import '../sessions/session_contracts.dart';

enum AndroidTargetOwnership { attached, managed }

enum AndroidGatewayRouteStrategy { adbReverse, emulatorHostAlias }

enum AndroidLifecycleOperation {
  discover,
  bootstrap,
  update,
  remove,
  verify,
  install,
  launch,
  reset,
  capture,
  start,
  stop,
}

enum AndroidLifecycleMode { inspect, dryRun, apply }

final class AndroidTargetDescriptor {
  AndroidTargetDescriptor({
    required this.serial,
    required this.avdName,
    required this.apiLevel,
    required this.abi,
    required this.ownership,
    required Set<String> capabilities,
  }) : capabilities = Set<String>.unmodifiable(capabilities) {
    if (!RegExp(r'^emulator-[0-9]{4,5}$').hasMatch(serial)) {
      throw FormatException('Android target must be an emulator serial');
    }
    _androidSafeName(avdName, 'avdName');
    if (apiLevel < 21 || apiLevel > 999) {
      throw ArgumentError.value(apiLevel, 'apiLevel');
    }
    if (!RegExp(r'^[a-z0-9_]{2,32}$').hasMatch(abi)) {
      throw FormatException('Invalid Android ABI');
    }
    if (capabilities.isEmpty ||
        capabilities.any(
          (value) => !RegExp(r'^[a-z][a-z0-9.-]{1,63}$').hasMatch(value),
        )) {
      throw FormatException('Invalid Android target capabilities');
    }
  }

  static const int schemaVersion = 1;

  final String serial;
  final String avdName;
  final int apiLevel;
  final String abi;
  final AndroidTargetOwnership ownership;
  final Set<String> capabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'serial': serial,
    'avdName': avdName,
    'apiLevel': apiLevel,
    'abi': abi,
    'ownership': ownership.name,
    'capabilities': capabilities.toList()..sort(),
  };

  factory AndroidTargetDescriptor.fromJson(Object? value) {
    final json = _androidObject(value, 'AndroidTargetDescriptor');
    _androidOnly(json, const <String>{
      'schemaVersion',
      'serial',
      'avdName',
      'apiLevel',
      'abi',
      'ownership',
      'capabilities',
    }, 'AndroidTargetDescriptor');
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported Android target schemaVersion');
    }
    return AndroidTargetDescriptor(
      serial: _androidString(json, 'serial', 'AndroidTargetDescriptor'),
      avdName: _androidString(json, 'avdName', 'AndroidTargetDescriptor'),
      apiLevel: _androidInteger(json, 'apiLevel', 'AndroidTargetDescriptor'),
      abi: _androidString(json, 'abi', 'AndroidTargetDescriptor'),
      ownership: _androidEnum(
        AndroidTargetOwnership.values,
        _androidString(json, 'ownership', 'AndroidTargetDescriptor'),
        'AndroidTargetDescriptor.ownership',
      ),
      capabilities: _androidStringList(
        json['capabilities'],
        'AndroidTargetDescriptor.capabilities',
      ).toSet(),
    );
  }

  Digest get digest => Digest.semantic(toJson());
}

final class AndroidGatewayPairing {
  AndroidGatewayPairing({
    required this.strategy,
    required this.hostPort,
    required this.targetPort,
    required this.tls,
  }) {
    for (final entry in <String, int>{
      'hostPort': hostPort,
      'targetPort': targetPort,
    }.entries) {
      if (entry.value < 1 || entry.value > 65535) {
        throw ArgumentError.value(entry.value, entry.key);
      }
    }
    if (strategy == AndroidGatewayRouteStrategy.emulatorHostAlias &&
        hostPort != targetPort) {
      throw ArgumentError(
        'emulatorHostAlias requires the target and host ports to match',
      );
    }
  }

  final AndroidGatewayRouteStrategy strategy;
  final int hostPort;
  final int targetPort;
  final bool tls;

  String get targetHost => switch (strategy) {
    AndroidGatewayRouteStrategy.adbReverse => '127.0.0.1',
    AndroidGatewayRouteStrategy.emulatorHostAlias => '10.0.2.2',
  };

  Uri get targetOrigin =>
      Uri(scheme: tls ? 'https' : 'http', host: targetHost, port: targetPort);

  Map<String, Object?> toJson() => <String, Object?>{
    'strategy': strategy.name,
    'hostPort': hostPort,
    'targetPort': targetPort,
    'tls': tls,
    'targetOrigin': targetOrigin.toString(),
  };

  factory AndroidGatewayPairing.fromJson(Object? value) {
    final json = _androidObject(value, 'AndroidGatewayPairing');
    _androidOnly(json, const <String>{
      'strategy',
      'hostPort',
      'targetPort',
      'tls',
      'targetOrigin',
    }, 'AndroidGatewayPairing');
    final pairing = AndroidGatewayPairing(
      strategy: _androidEnum(
        AndroidGatewayRouteStrategy.values,
        _androidString(json, 'strategy', 'AndroidGatewayPairing'),
        'AndroidGatewayPairing.strategy',
      ),
      hostPort: _androidInteger(json, 'hostPort', 'AndroidGatewayPairing'),
      targetPort: _androidInteger(json, 'targetPort', 'AndroidGatewayPairing'),
      tls: _androidBoolean(json, 'tls', 'AndroidGatewayPairing'),
    );
    if (_androidString(json, 'targetOrigin', 'AndroidGatewayPairing') !=
        pairing.targetOrigin.toString()) {
      throw const FormatException('Android targetOrigin is not canonical');
    }
    return pairing;
  }
}

final class AndroidLaunchRequest {
  AndroidLaunchRequest({
    required this.packageName,
    required this.activity,
    required this.pairing,
    required this.overlay,
  }) {
    _androidPackage(packageName, 'packageName');
    if (!RegExp(
      r'^(?:\.[A-Za-z][A-Za-z0-9_]*|[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)*)$',
    ).hasMatch(activity)) {
      throw FormatException('Invalid Android activity');
    }
  }

  final String packageName;
  final String activity;
  final AndroidGatewayPairing pairing;
  final RuntimeConfigurationOverlay overlay;

  String get component => '$packageName/$activity';

  Map<String, Object?> toJson() => <String, Object?>{
    'packageName': packageName,
    'activity': activity,
    'pairing': pairing.toJson(),
    'overlay': overlay.toJson(),
  };
}

final class AndroidLifecycleReport {
  AndroidLifecycleReport({
    required this.operation,
    required this.mode,
    required this.changed,
    required this.verified,
    required List<String> actions,
    this.target,
    this.pairing,
    this.artifactDigest,
  }) : actions = List<String>.unmodifiable(actions) {
    if (actions.any(
      (value) => value.isEmpty || value.length > 256 || value.contains('\n'),
    )) {
      throw FormatException('Invalid Android lifecycle action');
    }
    if (operation == AndroidLifecycleOperation.capture &&
        mode == AndroidLifecycleMode.apply &&
        artifactDigest == null) {
      throw ArgumentError('Applied capture requires artifactDigest');
    }
  }

  static const int schemaVersion = 1;

  final AndroidLifecycleOperation operation;
  final AndroidLifecycleMode mode;
  final bool changed;
  final bool verified;
  final List<String> actions;
  final AndroidTargetDescriptor? target;
  final AndroidGatewayPairing? pairing;
  final Digest? artifactDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'operation': operation.name,
    'mode': mode.name,
    'changed': changed,
    'verified': verified,
    'actions': actions,
    if (target != null) 'target': target!.toJson(),
    if (pairing != null) 'pairing': pairing!.toJson(),
    if (artifactDigest != null) 'artifactDigest': artifactDigest!.value,
  };

  factory AndroidLifecycleReport.fromJson(Object? value) {
    final json = _androidObject(value, 'AndroidLifecycleReport');
    _androidOnly(json, const <String>{
      'schemaVersion',
      'operation',
      'mode',
      'changed',
      'verified',
      'actions',
      'target',
      'pairing',
      'artifactDigest',
    }, 'AndroidLifecycleReport');
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException(
        'Unsupported Android lifecycle schemaVersion',
      );
    }
    return AndroidLifecycleReport(
      operation: _androidEnum(
        AndroidLifecycleOperation.values,
        _androidString(json, 'operation', 'AndroidLifecycleReport'),
        'AndroidLifecycleReport.operation',
      ),
      mode: _androidEnum(
        AndroidLifecycleMode.values,
        _androidString(json, 'mode', 'AndroidLifecycleReport'),
        'AndroidLifecycleReport.mode',
      ),
      changed: _androidBoolean(json, 'changed', 'AndroidLifecycleReport'),
      verified: _androidBoolean(json, 'verified', 'AndroidLifecycleReport'),
      actions: _androidStringList(
        json['actions'],
        'AndroidLifecycleReport.actions',
      ),
      target: json['target'] == null
          ? null
          : AndroidTargetDescriptor.fromJson(json['target']),
      pairing: json['pairing'] == null
          ? null
          : AndroidGatewayPairing.fromJson(json['pairing']),
      artifactDigest: json['artifactDigest'] == null
          ? null
          : Digest(
              _androidString(json, 'artifactDigest', 'AndroidLifecycleReport'),
            ),
    );
  }

  Digest get digest => Digest.semantic(toJson());
}

void _androidPackage(String value, String field) {
  if (value.length > 255 ||
      !RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$').hasMatch(value)) {
    throw FormatException('Invalid Android $field');
  }
}

void _androidSafeName(String value, String field) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_. -]{0,127}$').hasMatch(value)) {
    throw FormatException('Invalid Android $field');
  }
}

Map<String, Object?> _androidObject(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$context must be an object');
  }
  final output = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$context keys must be strings');
    }
    output[entry.key! as String] = entry.value;
  }
  return output;
}

void _androidOnly(
  Map<String, Object?> json,
  Set<String> allowed,
  String context,
) {
  final extras = json.keys.where((key) => !allowed.contains(key)).toList();
  if (extras.isNotEmpty) {
    throw FormatException('$context has unknown fields: ${extras.join(', ')}');
  }
}

String _androidString(Map<String, Object?> json, String key, String context) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$context.$key must be a non-empty string');
  }
  return value;
}

int _androidInteger(Map<String, Object?> json, String key, String context) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$context.$key must be an integer');
  }
  return value;
}

bool _androidBoolean(Map<String, Object?> json, String key, String context) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('$context.$key must be a boolean');
  }
  return value;
}

List<String> _androidStringList(Object? value, String context) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$context must be a string array');
  }
  final result = value.cast<String>();
  if (result.toSet().length != result.length) {
    throw FormatException('$context must contain unique values');
  }
  return result;
}

T _androidEnum<T extends Enum>(List<T> values, String value, String context) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$context has invalid value');
}
