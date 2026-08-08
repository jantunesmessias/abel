import '../catalog/catalog_contracts.dart';
import '../digest.dart';

enum TargetPlatform { web, androidEmulator }

enum SessionState {
  created,
  starting,
  ready,
  resetting,
  stopping,
  stopped,
  cancelled,
  failed;

  bool get isTerminal => switch (this) {
    SessionState.stopped ||
    SessionState.cancelled ||
    SessionState.failed => true,
    _ => false,
  };
}

enum BootstrapDependencyPolicy { production, overlay, simulated, blocked }

final class CapabilityDescriptor {
  CapabilityDescriptor({
    required this.id,
    required this.version,
    required Set<String> operations,
  }) : operations = Set<String>.unmodifiable(operations) {
    OpaqueId.validate(id, 'CapabilityDescriptor');
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'must be positive');
    }
    if (this.operations.isEmpty) {
      throw ArgumentError('CapabilityDescriptor requires an operation');
    }
    for (final operation in this.operations) {
      OpaqueId.validate(operation, 'CapabilityOperation');
    }
  }

  final String id;
  final int version;
  final Set<String> operations;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'version': version,
    'operations': operations.toList()..sort(),
  };

  factory CapabilityDescriptor.fromJson(Object? value) {
    final json = _sessionObject(value, 'CapabilityDescriptor');
    _sessionOnly(json, const <String>{
      'id',
      'version',
      'operations',
    }, 'CapabilityDescriptor');
    return CapabilityDescriptor(
      id: _sessionString(json, 'id', 'CapabilityDescriptor'),
      version: _sessionInteger(json, 'version', 'CapabilityDescriptor'),
      operations: _sessionStringList(
        json,
        'operations',
        'CapabilityDescriptor',
      ).toSet(),
    );
  }
}

final class RuntimeConfigurationOverlay {
  RuntimeConfigurationOverlay(Map<String, String> values)
    : values = Map<String, String>.unmodifiable(values) {
    for (final key in values.keys) {
      if (RegExp(
        r'(secret|token|password|credential|private[_-]?key)',
        caseSensitive: false,
      ).hasMatch(key)) {
        throw FormatException(
          'Runtime overlay must not contain secret-like key $key',
        );
      }
    }
  }

  final Map<String, String> values;

  Map<String, Object?> toJson() => <String, Object?>{'values': values};
}

final class ApplicationBootstrapPolicy {
  ApplicationBootstrapPolicy(
    Map<String, BootstrapDependencyPolicy> dependencies,
  ) : dependencies = Map<String, BootstrapDependencyPolicy>.unmodifiable(
        dependencies,
      );

  final Map<String, BootstrapDependencyPolicy> dependencies;

  Map<String, Object?> toJson() => <String, Object?>{
    'dependencies': <String, String>{
      for (final entry in dependencies.entries) entry.key: entry.value.name,
    },
  };
}

final class LaunchProfile {
  LaunchProfile({
    required this.id,
    required this.applicationId,
    required this.platform,
    required this.command,
    required List<String> arguments,
    required this.workingDirectory,
    required this.overlay,
    required this.bootstrapPolicy,
  }) : arguments = List<String>.unmodifiable(arguments) {
    OpaqueId.validate(id, 'LaunchProfile');
    if (command.isEmpty) throw ArgumentError.value(command, 'command');
    if (workingDirectory.isEmpty) {
      throw ArgumentError.value(workingDirectory, 'workingDirectory');
    }
  }

  final String id;
  final ApplicationId applicationId;
  final TargetPlatform platform;
  final String command;
  final List<String> arguments;
  final String workingDirectory;
  final RuntimeConfigurationOverlay overlay;
  final ApplicationBootstrapPolicy bootstrapPolicy;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'applicationId': applicationId.value,
    'platform': platform.name,
    'command': command,
    'arguments': arguments,
    'workingDirectory': workingDirectory,
    'overlay': overlay.toJson(),
    'bootstrapPolicy': bootstrapPolicy.toJson(),
  };
}

final class ExecutionTarget {
  ExecutionTarget({
    required this.id,
    required this.platform,
    required Uri origin,
    required List<CapabilityDescriptor> capabilities,
  }) : origin = origin,
       capabilities = List<CapabilityDescriptor>.unmodifiable(capabilities) {
    _sessionIdentifier(id, 'ExecutionTarget.id');
    if (!const <String>{'http', 'https'}.contains(origin.scheme) ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.query.isNotEmpty ||
        origin.fragment.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw FormatException(
        'ExecutionTarget origin must be a canonical origin',
      );
    }
    if (this.capabilities.map((capability) => capability.id).toSet().length !=
        this.capabilities.length) {
      throw ArgumentError('ExecutionTarget capabilities must have unique IDs');
    }
  }

  final String id;
  final TargetPlatform platform;
  final Uri origin;
  final List<CapabilityDescriptor> capabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'platform': platform.name,
    'origin': origin.toString(),
    'capabilities': <Object?>[
      for (final capability in capabilities) capability.toJson(),
    ],
  };

  factory ExecutionTarget.fromJson(Object? value) {
    final json = _sessionObject(value, 'ExecutionTarget');
    _sessionOnly(json, const <String>{
      'id',
      'platform',
      'origin',
      'capabilities',
    }, 'ExecutionTarget');
    return ExecutionTarget(
      id: _sessionString(json, 'id', 'ExecutionTarget'),
      platform: _sessionEnum(
        TargetPlatform.values,
        _sessionString(json, 'platform', 'ExecutionTarget'),
        'ExecutionTarget.platform',
      ),
      origin: Uri.parse(_sessionString(json, 'origin', 'ExecutionTarget')),
      capabilities: _sessionList(
        json,
        'capabilities',
        'ExecutionTarget',
      ).map(CapabilityDescriptor.fromJson).toList(growable: false),
    );
  }
}

final class SessionCheckpoint {
  SessionCheckpoint({
    required this.sequence,
    required this.recordedAt,
    required this.reason,
  }) {
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence', 'must be non-negative');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'must be non-empty');
    }
  }

  static const int schemaVersion = 1;
  final int sequence;
  final DateTime recordedAt;
  final String reason;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'Checkpoint',
    'sequence': sequence,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'reason': reason,
    if (includeDigest) 'digest': digest.value,
  };

  factory SessionCheckpoint.fromJson(Object? value) {
    final json = _sessionObject(value, 'Checkpoint');
    _sessionDocument(json, 'Checkpoint', const <String>{
      'sequence',
      'recordedAt',
      'reason',
    });
    final checkpoint = SessionCheckpoint(
      sequence: _sessionInteger(json, 'sequence', 'Checkpoint'),
      recordedAt: _sessionDateTime(json, 'recordedAt', 'Checkpoint'),
      reason: _sessionString(json, 'reason', 'Checkpoint'),
    );
    _sessionDigest(json, checkpoint.digest, 'Checkpoint');
    return checkpoint;
  }
}

final class SessionTraceEntry {
  SessionTraceEntry({
    required this.sequence,
    required this.recordedAt,
    required this.event,
    required Map<String, Object?> data,
  }) : data = Map<String, Object?>.unmodifiable(<String, Object?>{
         for (final entry in data.entries)
           entry.key: _sessionFreezeJson(entry.value),
       }) {
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence', 'must be non-negative');
    }
    if (event.trim().isEmpty) {
      throw ArgumentError.value(event, 'event', 'must be non-empty');
    }
  }

  final int sequence;
  final DateTime recordedAt;
  final String event;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'event': event,
    'data': data,
  };

  factory SessionTraceEntry.fromJson(Object? value) {
    final json = _sessionObject(value, 'SessionTraceEntry');
    _sessionOnly(json, const <String>{
      'sequence',
      'recordedAt',
      'event',
      'data',
    }, 'SessionTraceEntry');
    return SessionTraceEntry(
      sequence: _sessionInteger(json, 'sequence', 'SessionTraceEntry'),
      recordedAt: _sessionDateTime(json, 'recordedAt', 'SessionTraceEntry'),
      event: _sessionString(json, 'event', 'SessionTraceEntry'),
      data: _sessionObject(json['data'], 'SessionTraceEntry.data'),
    );
  }
}

final class SessionSnapshot {
  SessionSnapshot({
    required this.id,
    required this.launchProfileId,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    required List<SessionTraceEntry> trace,
    this.target,
    this.terminalReason,
  }) : trace = List<SessionTraceEntry>.unmodifiable(trace) {
    _sessionIdentifier(id, 'Session.id');
    OpaqueId.validate(launchProfileId, 'LaunchProfile');
    if (updatedAt.toUtc().isBefore(createdAt.toUtc())) {
      throw ArgumentError('Session.updatedAt precedes createdAt');
    }
    var previousSequence = -1;
    DateTime? previousRecordedAt;
    for (final entry in this.trace) {
      if (entry.sequence <= previousSequence) {
        throw ArgumentError('Session trace sequence must strictly increase');
      }
      final recordedAt = entry.recordedAt.toUtc();
      if (recordedAt.isBefore(createdAt.toUtc()) ||
          recordedAt.isAfter(updatedAt.toUtc()) ||
          (previousRecordedAt != null &&
              recordedAt.isBefore(previousRecordedAt))) {
        throw ArgumentError(
          'Session trace timestamps must be ordered within the session window',
        );
      }
      previousSequence = entry.sequence;
      previousRecordedAt = recordedAt;
    }
    if (terminalReason != null && terminalReason!.trim().isEmpty) {
      throw ArgumentError(
        'Session.terminalReason must be non-empty when present',
      );
    }
    if (state == SessionState.failed &&
        (terminalReason == null || terminalReason!.trim().isEmpty)) {
      throw ArgumentError('Failed Session requires terminalReason');
    }
    if (!state.isTerminal && terminalReason != null) {
      throw ArgumentError('Non-terminal Session cannot have terminalReason');
    }
  }

  static const int schemaVersion = 1;
  final String id;
  final String launchProfileId;
  final SessionState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SessionTraceEntry> trace;
  final ExecutionTarget? target;
  final String? terminalReason;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'Session',
    'id': id,
    'launchProfileId': launchProfileId,
    'state': state.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'trace': <Object?>[for (final entry in trace) entry.toJson()],
    if (target != null) 'target': target!.toJson(),
    if (terminalReason != null) 'terminalReason': terminalReason,
    if (includeDigest) 'digest': digest.value,
  };

  factory SessionSnapshot.fromJson(Object? value) {
    final json = _sessionObject(value, 'Session');
    _sessionDocument(json, 'Session', const <String>{
      'id',
      'launchProfileId',
      'state',
      'createdAt',
      'updatedAt',
      'trace',
      'target',
      'terminalReason',
    });
    final session = SessionSnapshot(
      id: _sessionString(json, 'id', 'Session'),
      launchProfileId: _sessionString(json, 'launchProfileId', 'Session'),
      state: _sessionEnum(
        SessionState.values,
        _sessionString(json, 'state', 'Session'),
        'Session.state',
      ),
      createdAt: _sessionDateTime(json, 'createdAt', 'Session'),
      updatedAt: _sessionDateTime(json, 'updatedAt', 'Session'),
      trace: _sessionList(
        json,
        'trace',
        'Session',
      ).map(SessionTraceEntry.fromJson).toList(growable: false),
      target: json['target'] == null
          ? null
          : ExecutionTarget.fromJson(json['target']),
      terminalReason: _sessionOptionalString(json, 'terminalReason', 'Session'),
    );
    _sessionDigest(json, session.digest, 'Session');
    return session;
  }
}

final class CaptureRequest {
  const CaptureRequest({
    required this.id,
    required this.sessionId,
    required this.format,
  });

  final String id;
  final String sessionId;
  final String format;
}

void _sessionDocument(
  Map<String, Object?> json,
  String kind,
  Set<String> fields,
) {
  _sessionOnly(json, <String>{
    'schemaVersion',
    'kind',
    ...fields,
    'digest',
  }, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind version or kind is invalid');
  }
}

void _sessionDigest(Map<String, Object?> json, Digest expected, String path) {
  if (Digest(_sessionString(json, 'digest', path)) != expected) {
    throw FormatException('$path.digest does not match canonical content');
  }
}

Map<String, Object?> _sessionObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _sessionOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _sessionString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

String? _sessionOptionalString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

int _sessionInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

DateTime _sessionDateTime(Map<String, Object?> json, String key, String path) {
  final source = _sessionString(json, key, path);
  final value = DateTime.tryParse(source);
  if (value == null || !value.isUtc || value.toIso8601String() != source) {
    throw FormatException('$path.$key must be canonical UTC RFC 3339');
  }
  return value;
}

List<Object?> _sessionList(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be an array');
  }
  return value;
}

List<String> _sessionStringList(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final values = _sessionList(json, key, path);
  if (values.any((value) => value is! String || value.isEmpty)) {
    throw FormatException('$path.$key must contain non-empty strings');
  }
  return values.cast<String>();
}

T _sessionEnum<T extends Enum>(List<T> values, String source, String path) {
  for (final value in values) {
    if (value.name == source) return value;
  }
  throw FormatException('$path is invalid: $source');
}

Object? _sessionFreezeJson(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    Digest.semantic(value);
    return value;
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_sessionFreezeJson));
  }
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries)
        entry.key: _sessionFreezeJson(entry.value),
    });
  }
  throw FormatException('Session trace data contains unsupported JSON value');
}

void _sessionIdentifier(String value, String path) {
  if (!RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
    throw FormatException('$path is not a valid runtime identifier: $value');
  }
}
