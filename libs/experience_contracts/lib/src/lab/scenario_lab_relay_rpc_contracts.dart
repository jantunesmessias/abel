import '../catalog/catalog_contracts.dart';
import '../digest.dart';
import '../sessions/app_adapter_relay_contracts.dart';
import '../sessions/target_readiness_contracts.dart';
import 'scenario_lab_execution_contracts.dart';

enum ScenarioLabRelayDescriptionStatus { pending, ready, closed }

enum ScenarioLabRelayPollState { command, idle, closed }

final class ScenarioLabRelayTargetDescriptor {
  ScenarioLabRelayTargetDescriptor({
    required this.runId,
    required this.targetId,
    required this.launchProfileId,
    required this.launchAttemptId,
    required Uri origin,
    required this.nonce,
  }) : origin = _relayRpcLoopbackOrigin(origin) {
    OpaqueId.validate(targetId, 'ScenarioLabRelayTarget.targetId');
    OpaqueId.validate(
      launchProfileId,
      'ScenarioLabRelayTarget.launchProfileId',
    );
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final String targetId;
  final String launchProfileId;
  final TargetLaunchAttemptId launchAttemptId;
  final Uri origin;
  final AppAdapterRelayNonce nonce;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayTargetDescriptor',
    'runId': runId.value,
    'targetId': targetId,
    'launchProfileId': launchProfileId,
    'launchAttemptId': launchAttemptId.value,
    'origin': origin.toString(),
    'nonce': nonce.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayTargetDescriptor.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayTargetDescriptor',
      const <String>{
        'runId',
        'targetId',
        'launchProfileId',
        'launchAttemptId',
        'origin',
        'nonce',
      },
    );
    final origin = Uri.tryParse(
      _relayRpcString(json, 'origin', 'ScenarioLabRelayTargetDescriptor'),
    );
    if (origin == null) {
      throw const FormatException('Invalid Scenario Lab relay target origin');
    }
    final descriptor = ScenarioLabRelayTargetDescriptor(
      runId: ScenarioLabRunId(
        _relayRpcString(json, 'runId', 'ScenarioLabRelayTargetDescriptor'),
      ),
      targetId: _relayRpcString(
        json,
        'targetId',
        'ScenarioLabRelayTargetDescriptor',
      ),
      launchProfileId: _relayRpcString(
        json,
        'launchProfileId',
        'ScenarioLabRelayTargetDescriptor',
      ),
      launchAttemptId: TargetLaunchAttemptId(
        _relayRpcString(
          json,
          'launchAttemptId',
          'ScenarioLabRelayTargetDescriptor',
        ),
      ),
      origin: origin,
      nonce: AppAdapterRelayNonce(
        _relayRpcString(json, 'nonce', 'ScenarioLabRelayTargetDescriptor'),
      ),
    );
    _relayRpcDigest(
      json,
      descriptor.digest,
      'ScenarioLabRelayTargetDescriptor',
    );
    return descriptor;
  }
}

final class ScenarioLabRelayDescription {
  ScenarioLabRelayDescription({
    required this.runId,
    required this.status,
    this.descriptor,
  }) {
    if ((status == ScenarioLabRelayDescriptionStatus.ready) !=
            (descriptor != null) ||
        (descriptor != null && descriptor!.runId != runId)) {
      throw ArgumentError('Scenario Lab relay description is inconsistent');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final ScenarioLabRelayDescriptionStatus status;
  final ScenarioLabRelayTargetDescriptor? descriptor;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayDescription',
    'runId': runId.value,
    'status': status.name,
    if (descriptor != null) 'descriptor': descriptor!.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayDescription.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayDescription',
      const <String>{'runId', 'status'},
      optional: const <String>{'descriptor'},
    );
    final description = ScenarioLabRelayDescription(
      runId: ScenarioLabRunId(
        _relayRpcString(json, 'runId', 'ScenarioLabRelayDescription'),
      ),
      status: _relayRpcEnum(
        ScenarioLabRelayDescriptionStatus.values,
        _relayRpcString(json, 'status', 'ScenarioLabRelayDescription'),
        'ScenarioLabRelayDescription.status',
      ),
      descriptor: json.containsKey('descriptor')
          ? ScenarioLabRelayTargetDescriptor.fromJson(json['descriptor'])
          : null,
    );
    _relayRpcDigest(json, description.digest, 'ScenarioLabRelayDescription');
    return description;
  }
}

final class ScenarioLabRelayHelloSubmission {
  ScenarioLabRelayHelloSubmission({
    required this.descriptorDigest,
    required this.hello,
  });

  static const int schemaVersion = 1;
  final Digest descriptorDigest;
  final AppAdapterRelayHello hello;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  void validateAgainst(ScenarioLabRelayTargetDescriptor descriptor) {
    if (descriptor.digest != descriptorDigest ||
        descriptor.runId != hello.runId ||
        descriptor.nonce != hello.nonce) {
      throw ArgumentError('Relay hello submission does not bind the target');
    }
  }

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayHelloSubmission',
    'descriptorDigest': descriptorDigest.value,
    'hello': hello.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayHelloSubmission.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayHelloSubmission',
      const <String>{'descriptorDigest', 'hello'},
    );
    final submission = ScenarioLabRelayHelloSubmission(
      descriptorDigest: _relayRpcRequiredDigest(
        json,
        'descriptorDigest',
        'ScenarioLabRelayHelloSubmission',
      ),
      hello: AppAdapterRelayHello.fromJson(json['hello']),
    );
    _relayRpcDigest(json, submission.digest, 'ScenarioLabRelayHelloSubmission');
    return submission;
  }
}

final class ScenarioLabRelayHelloAcknowledgement {
  ScenarioLabRelayHelloAcknowledgement({
    required this.runId,
    required this.descriptorDigest,
    required this.acceptedHelloDigest,
  });

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest descriptorDigest;
  final Digest acceptedHelloDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayHelloAcknowledgement',
    'runId': runId.value,
    'descriptorDigest': descriptorDigest.value,
    'acceptedHelloDigest': acceptedHelloDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayHelloAcknowledgement.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayHelloAcknowledgement',
      const <String>{'runId', 'descriptorDigest', 'acceptedHelloDigest'},
    );
    final acknowledgement = ScenarioLabRelayHelloAcknowledgement(
      runId: ScenarioLabRunId(
        _relayRpcString(json, 'runId', 'ScenarioLabRelayHelloAcknowledgement'),
      ),
      descriptorDigest: _relayRpcRequiredDigest(
        json,
        'descriptorDigest',
        'ScenarioLabRelayHelloAcknowledgement',
      ),
      acceptedHelloDigest: _relayRpcRequiredDigest(
        json,
        'acceptedHelloDigest',
        'ScenarioLabRelayHelloAcknowledgement',
      ),
    );
    _relayRpcDigest(
      json,
      acknowledgement.digest,
      'ScenarioLabRelayHelloAcknowledgement',
    );
    return acknowledgement;
  }
}

final class ScenarioLabRelayPollRequest {
  ScenarioLabRelayPollRequest({
    required this.runId,
    required this.descriptorDigest,
    required this.afterSequence,
    required this.waitMs,
  }) {
    if (afterSequence < 0 || afterSequence > 9007199254740991) {
      throw ArgumentError.value(afterSequence, 'afterSequence');
    }
    if (waitMs < 0 || waitMs > 30000) {
      throw ArgumentError.value(waitMs, 'waitMs');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest descriptorDigest;
  final int afterSequence;
  final int waitMs;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayPollRequest',
    'runId': runId.value,
    'descriptorDigest': descriptorDigest.value,
    'afterSequence': afterSequence,
    'waitMs': waitMs,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayPollRequest.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayPollRequest',
      const <String>{'runId', 'descriptorDigest', 'afterSequence', 'waitMs'},
    );
    final request = ScenarioLabRelayPollRequest(
      runId: ScenarioLabRunId(
        _relayRpcString(json, 'runId', 'ScenarioLabRelayPollRequest'),
      ),
      descriptorDigest: _relayRpcRequiredDigest(
        json,
        'descriptorDigest',
        'ScenarioLabRelayPollRequest',
      ),
      afterSequence: _relayRpcInteger(
        json,
        'afterSequence',
        'ScenarioLabRelayPollRequest',
      ),
      waitMs: _relayRpcInteger(json, 'waitMs', 'ScenarioLabRelayPollRequest'),
    );
    _relayRpcDigest(json, request.digest, 'ScenarioLabRelayPollRequest');
    return request;
  }
}

final class ScenarioLabRelayPollResponse {
  ScenarioLabRelayPollResponse({
    required this.runId,
    required this.descriptorDigest,
    required this.afterSequence,
    required this.state,
    this.command,
  }) {
    if (afterSequence < 0 ||
        afterSequence > 9007199254740991 ||
        (state == ScenarioLabRelayPollState.command) != (command != null) ||
        (command != null &&
            (command!.runId != runId ||
                command!.sequence != afterSequence + 1))) {
      throw ArgumentError('Scenario Lab relay poll response is inconsistent');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest descriptorDigest;
  final int afterSequence;
  final ScenarioLabRelayPollState state;
  final AppAdapterRelayCommand? command;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayPollResponse',
    'runId': runId.value,
    'descriptorDigest': descriptorDigest.value,
    'afterSequence': afterSequence,
    'state': state.name,
    if (command != null) 'command': command!.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayPollResponse.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayPollResponse',
      const <String>{'runId', 'descriptorDigest', 'afterSequence', 'state'},
      optional: const <String>{'command'},
    );
    final response = ScenarioLabRelayPollResponse(
      runId: ScenarioLabRunId(
        _relayRpcString(json, 'runId', 'ScenarioLabRelayPollResponse'),
      ),
      descriptorDigest: _relayRpcRequiredDigest(
        json,
        'descriptorDigest',
        'ScenarioLabRelayPollResponse',
      ),
      afterSequence: _relayRpcInteger(
        json,
        'afterSequence',
        'ScenarioLabRelayPollResponse',
      ),
      state: _relayRpcEnum(
        ScenarioLabRelayPollState.values,
        _relayRpcString(json, 'state', 'ScenarioLabRelayPollResponse'),
        'ScenarioLabRelayPollResponse.state',
      ),
      command: json.containsKey('command')
          ? AppAdapterRelayCommand.fromJson(json['command'])
          : null,
    );
    _relayRpcDigest(json, response.digest, 'ScenarioLabRelayPollResponse');
    return response;
  }
}

final class ScenarioLabRelayResultSubmission {
  ScenarioLabRelayResultSubmission({
    required this.descriptorDigest,
    required this.result,
  });

  static const int schemaVersion = 1;
  final Digest descriptorDigest;
  final AppAdapterRelayResult result;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayResultSubmission',
    'descriptorDigest': descriptorDigest.value,
    'result': result.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayResultSubmission.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayResultSubmission',
      const <String>{'descriptorDigest', 'result'},
    );
    final submission = ScenarioLabRelayResultSubmission(
      descriptorDigest: _relayRpcRequiredDigest(
        json,
        'descriptorDigest',
        'ScenarioLabRelayResultSubmission',
      ),
      result: AppAdapterRelayResult.fromJson(json['result']),
    );
    _relayRpcDigest(
      json,
      submission.digest,
      'ScenarioLabRelayResultSubmission',
    );
    return submission;
  }
}

final class ScenarioLabRelayResultAcknowledgement {
  ScenarioLabRelayResultAcknowledgement({
    required this.runId,
    required this.descriptorDigest,
    required this.acceptedResultDigest,
  });

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest descriptorDigest;
  final Digest acceptedResultDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRelayResultAcknowledgement',
    'runId': runId.value,
    'descriptorDigest': descriptorDigest.value,
    'acceptedResultDigest': acceptedResultDigest.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRelayResultAcknowledgement.fromJson(Object? value) {
    final json = _relayRpcDocument(
      value,
      'ScenarioLabRelayResultAcknowledgement',
      const <String>{'runId', 'descriptorDigest', 'acceptedResultDigest'},
    );
    final acknowledgement = ScenarioLabRelayResultAcknowledgement(
      runId: ScenarioLabRunId(
        _relayRpcString(json, 'runId', 'ScenarioLabRelayResultAcknowledgement'),
      ),
      descriptorDigest: _relayRpcRequiredDigest(
        json,
        'descriptorDigest',
        'ScenarioLabRelayResultAcknowledgement',
      ),
      acceptedResultDigest: _relayRpcRequiredDigest(
        json,
        'acceptedResultDigest',
        'ScenarioLabRelayResultAcknowledgement',
      ),
    );
    _relayRpcDigest(
      json,
      acknowledgement.digest,
      'ScenarioLabRelayResultAcknowledgement',
    );
    return acknowledgement;
  }
}

Map<String, Object?> _relayRpcDocument(
  Object? value,
  String kind,
  Set<String> required, {
  Set<String> optional = const <String>{},
}) {
  final json = _relayRpcObject(value, kind);
  final base = <String>{'schemaVersion', 'kind', 'digest'};
  final requiredFields = <String>{...base, ...required};
  final allowed = <String>{...requiredFields, ...optional};
  if (json['schemaVersion'] != 1 ||
      json['kind'] != kind ||
      json.keys.any((key) => !allowed.contains(key)) ||
      !json.keys.toSet().containsAll(requiredFields)) {
    throw FormatException('Invalid $kind document');
  }
  return json;
}

Map<String, Object?> _relayRpcObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

String _relayRpcString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 4096) {
    throw FormatException('$path.$key must be a bounded string');
  }
  return value;
}

int _relayRpcInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw FormatException('$path.$key must be a JSON-safe integer');
  }
  return value;
}

T _relayRpcEnum<T extends Enum>(Iterable<T> values, String value, String path) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('$path has an unknown value');
}

Digest _relayRpcRequiredDigest(
  Map<String, Object?> json,
  String key,
  String path,
) => Digest(_relayRpcString(json, key, path));

void _relayRpcDigest(Map<String, Object?> json, Digest expected, String path) {
  if (_relayRpcRequiredDigest(json, 'digest', path) != expected) {
    throw FormatException('$path digest mismatch');
  }
}

Uri _relayRpcLoopbackOrigin(Uri value) {
  const hosts = <String>{'127.0.0.1', '::1', 'localhost'};
  if (!const <String>{'http', 'https'}.contains(value.scheme) ||
      !hosts.contains(value.host) ||
      !value.hasPort ||
      value.port < 1 ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw const FormatException(
      'Scenario Lab relay target must be a canonical loopback origin',
    );
  }
  return value.replace(path: '');
}
