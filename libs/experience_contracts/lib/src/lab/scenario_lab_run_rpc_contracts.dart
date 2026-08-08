import '../canonical_json.dart';
import '../digest.dart';
import 'scenario_lab_execution_contracts.dart';

enum ScenarioLabRunDisposition { active, terminal, interrupted }

/// Closed, digested reference used by read and cancellation RPCs.
final class ScenarioLabRunReference {
  ScenarioLabRunReference({required this.runId});

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRunReference',
    'runId': runId.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRunReference.fromJson(Object? value) {
    final json = _runRpcDocument(
      value,
      'ScenarioLabRunReference',
      const <String>{'runId'},
    );
    final reference = ScenarioLabRunReference(
      runId: ScenarioLabRunId(
        _runRpcString(json, 'runId', 'ScenarioLabRunReference'),
      ),
    );
    _runRpcVerifyDigest(json, reference.digest, 'ScenarioLabRunReference');
    return reference;
  }
}

/// Bounded observer catch-up request.
final class ScenarioLabRunObserveRequest {
  ScenarioLabRunObserveRequest({
    required this.runId,
    required this.afterSequence,
    this.limit = 100,
  }) {
    if (afterSequence < -1 || afterSequence > JcsCanonicalizer.maxSafeInteger) {
      throw ArgumentError.value(afterSequence, 'afterSequence');
    }
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final int afterSequence;
  final int limit;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRunObserveRequest',
    'runId': runId.value,
    'afterSequence': afterSequence,
    'limit': limit,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRunObserveRequest.fromJson(Object? value) {
    final json = _runRpcDocument(
      value,
      'ScenarioLabRunObserveRequest',
      const <String>{'runId', 'afterSequence', 'limit'},
    );
    final request = ScenarioLabRunObserveRequest(
      runId: ScenarioLabRunId(
        _runRpcString(json, 'runId', 'ScenarioLabRunObserveRequest'),
      ),
      afterSequence: _runRpcInteger(
        json,
        'afterSequence',
        'ScenarioLabRunObserveRequest',
      ),
      limit: _runRpcInteger(json, 'limit', 'ScenarioLabRunObserveRequest'),
    );
    _runRpcVerifyDigest(json, request.digest, 'ScenarioLabRunObserveRequest');
    return request;
  }
}

/// Sanitized, bounded run view. Relay payloads never enter this document.
final class ScenarioLabRunObservation {
  ScenarioLabRunObservation({
    required this.runId,
    required this.disposition,
    required this.afterSequence,
    required this.current,
    required Iterable<ScenarioLabRunSnapshot> observations,
    required this.hasMore,
    this.result,
  }) : observations = List<ScenarioLabRunSnapshot>.unmodifiable(observations) {
    if (afterSequence < -1 ||
        afterSequence > JcsCanonicalizer.maxSafeInteger ||
        afterSequence > current.sequence ||
        current.runId != runId ||
        this.observations.length > 100 ||
        this.observations.any((item) => item.runId != runId)) {
      throw ArgumentError('Scenario Lab run observation is inconsistent');
    }
    var expectedSequence = afterSequence + 1;
    for (final observation in this.observations) {
      if (observation.sequence != expectedSequence ||
          observation.sequence > current.sequence) {
        throw ArgumentError(
          'Scenario Lab run observations must be contiguous and bounded',
        );
      }
      expectedSequence += 1;
    }
    final observedThrough = this.observations.isEmpty
        ? afterSequence
        : this.observations.last.sequence;
    if (hasMore != (observedThrough < current.sequence)) {
      throw ArgumentError('Scenario Lab run pagination marker is invalid');
    }
    switch (disposition) {
      case ScenarioLabRunDisposition.active:
        if (current.state.isTerminal || result != null) {
          throw ArgumentError('Active Scenario Lab run cannot be terminal');
        }
      case ScenarioLabRunDisposition.terminal:
        if (!current.state.isTerminal ||
            result == null ||
            result!.finalSnapshot.digest != current.digest) {
          throw ArgumentError('Terminal Scenario Lab result is inconsistent');
        }
      case ScenarioLabRunDisposition.interrupted:
        if (current.state.isTerminal || result != null) {
          throw ArgumentError(
            'Interrupted Scenario Lab run preserves a non-terminal snapshot',
          );
        }
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final ScenarioLabRunDisposition disposition;
  final int afterSequence;
  final ScenarioLabRunSnapshot current;
  final List<ScenarioLabRunSnapshot> observations;
  final bool hasMore;
  final ScenarioLabRunResult? result;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRunObservation',
    'runId': runId.value,
    'disposition': disposition.name,
    'afterSequence': afterSequence,
    'current': current.toJson(),
    'observations': observations.map((item) => item.toJson()).toList(),
    'hasMore': hasMore,
    if (result != null) 'result': result!.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRunObservation.fromJson(Object? value) {
    final json = _runRpcDocument(
      value,
      'ScenarioLabRunObservation',
      const <String>{
        'runId',
        'disposition',
        'afterSequence',
        'current',
        'observations',
        'hasMore',
      },
      optional: const <String>{'result'},
    );
    final rawObservations = json['observations'];
    if (rawObservations is! List<Object?> || rawObservations.length > 100) {
      throw const FormatException(
        'ScenarioLabRunObservation.observations must be a bounded list',
      );
    }
    final observation = ScenarioLabRunObservation(
      runId: ScenarioLabRunId(
        _runRpcString(json, 'runId', 'ScenarioLabRunObservation'),
      ),
      disposition: _runRpcEnum(
        ScenarioLabRunDisposition.values,
        _runRpcString(json, 'disposition', 'ScenarioLabRunObservation'),
        'ScenarioLabRunObservation.disposition',
      ),
      afterSequence: _runRpcInteger(
        json,
        'afterSequence',
        'ScenarioLabRunObservation',
      ),
      current: ScenarioLabRunSnapshot.fromJson(json['current']),
      observations: rawObservations.map(ScenarioLabRunSnapshot.fromJson),
      hasMore: _runRpcBoolean(json, 'hasMore', 'ScenarioLabRunObservation'),
      result: json.containsKey('result')
          ? ScenarioLabRunResult.fromJson(json['result'])
          : null,
    );
    _runRpcVerifyDigest(json, observation.digest, 'ScenarioLabRunObservation');
    return observation;
  }
}

Map<String, Object?> _runRpcDocument(
  Object? value,
  String kind,
  Set<String> required, {
  Set<String> optional = const <String>{},
}) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$kind must be an object');
  }
  final requiredKeys = <String>{'schemaVersion', 'kind', 'digest', ...required};
  final allowedKeys = <String>{...requiredKeys, ...optional};
  if (value['schemaVersion'] != 1 ||
      value['kind'] != kind ||
      !value.keys.toSet().containsAll(requiredKeys) ||
      value.keys.any((key) => !allowedKeys.contains(key))) {
    throw FormatException('Invalid $kind document');
  }
  return value;
}

String _runRpcString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 4096) {
    throw FormatException('$path.$key must be a bounded string');
  }
  return value;
}

int _runRpcInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int || value < -1 || value > JcsCanonicalizer.maxSafeInteger) {
    throw FormatException('$path.$key must be a JSON-safe integer');
  }
  return value;
}

bool _runRpcBoolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

T _runRpcEnum<T extends Enum>(Iterable<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has an unknown value');
}

void _runRpcVerifyDigest(
  Map<String, Object?> json,
  Digest expected,
  String path,
) {
  final raw = json['digest'];
  if (raw is! String || Digest(raw) != expected) {
    throw FormatException('$path digest mismatch');
  }
}
