import '../canonical_json.dart';
import '../catalog/catalog_contracts.dart';
import '../digest.dart';
import '../evidence/evidence_contracts.dart';
import 'gateway_contracts.dart';

enum ProbeArtifactRetention { ephemeral, cas }

final class ProbeExtraction {
  ProbeExtraction({required this.fromRouteId, required List<String> paths})
    : paths = List<String>.unmodifiable(paths) {
    if (paths.isEmpty || paths.length > 8) {
      throw ArgumentError('Probe extraction requires 1 through 8 paths');
    }
    for (final path in paths) {
      if (!_jsonPointer.hasMatch(path) || path.length > 512) {
        throw FormatException('Probe extraction path must be a JSON Pointer');
      }
    }
  }

  final GatewayRouteId fromRouteId;
  final List<String> paths;

  Map<String, Object?> toJson() => <String, Object?>{
    'fromRouteId': fromRouteId.value,
    'paths': paths,
  };

  factory ProbeExtraction.fromJson(Object? value) {
    final json = _probeObject(value, 'ProbeExtraction');
    _probeOnly(json, const <String>{'fromRouteId', 'paths'}, 'ProbeExtraction');
    return ProbeExtraction(
      fromRouteId: GatewayRouteId(
        _probeString(json, 'fromRouteId', 'ProbeExtraction'),
      ),
      paths: _probeStringList(json['paths'], 'ProbeExtraction.paths'),
    );
  }
}

final class ContractProbeStep {
  ContractProbeStep({
    required this.routeId,
    required this.order,
    required Set<GatewayRouteId> after,
    required Map<String, ProbeExtraction> extract,
    Object? requestBodyTemplate,
  }) : after = Set<GatewayRouteId>.unmodifiable(after),
       extract = Map<String, ProbeExtraction>.unmodifiable(extract),
       requestBodyTemplate = requestBodyTemplate == null
           ? null
           : _freezeProbeJson(requestBodyTemplate) {
    if (order < 0 || order > 10000) {
      throw ArgumentError.value(order, 'order');
    }
    if (after.contains(routeId)) {
      throw ArgumentError('Probe step cannot depend on itself');
    }
    for (final entry in extract.entries) {
      if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(entry.key)) {
        throw FormatException('Invalid probe parameter name');
      }
      if (!after.contains(entry.value.fromRouteId)) {
        throw ArgumentError('Probe extraction must reference an after route');
      }
    }
    if (requestBodyTemplate != null &&
        const JcsCanonicalizer().canonicalize(requestBodyTemplate).length >
            64 * 1024) {
      throw ArgumentError('Probe request body template exceeds 64 KiB');
    }
  }

  final GatewayRouteId routeId;
  final int order;
  final Set<GatewayRouteId> after;
  final Map<String, ProbeExtraction> extract;
  final Object? requestBodyTemplate;

  Map<String, Object?> toJson() => <String, Object?>{
    'routeId': routeId.value,
    'order': order,
    'after': after.map((value) => value.value).toList()..sort(),
    'extract': <String, Object?>{
      for (final key in extract.keys.toList()..sort())
        key: extract[key]!.toJson(),
    },
    if (requestBodyTemplate != null) 'requestBodyTemplate': requestBodyTemplate,
  };

  factory ContractProbeStep.fromJson(Object? value) {
    final json = _probeObject(value, 'ContractProbeStep');
    _probeOnly(json, const <String>{
      'routeId',
      'order',
      'after',
      'extract',
      'requestBodyTemplate',
    }, 'ContractProbeStep');
    final extractionJson = _probeObject(
      json['extract'],
      'ContractProbeStep.extract',
    );
    return ContractProbeStep(
      routeId: GatewayRouteId(
        _probeString(json, 'routeId', 'ContractProbeStep'),
      ),
      order: _probeInteger(json, 'order', 'ContractProbeStep'),
      after: _probeStringList(
        json['after'],
        'ContractProbeStep.after',
      ).map(GatewayRouteId.new).toSet(),
      extract: <String, ProbeExtraction>{
        for (final entry in extractionJson.entries)
          entry.key: ProbeExtraction.fromJson(entry.value),
      },
      requestBodyTemplate: json['requestBodyTemplate'],
    );
  }
}

final class ContractProbePlan {
  ContractProbePlan({
    required this.id,
    required this.presetId,
    required List<ContractProbeStep> steps,
    required Map<String, String> parameterDefaults,
    this.artifactRetention = ProbeArtifactRetention.ephemeral,
    this.artifactClassification = ArtifactClassification.sensitive,
  }) : steps = List<ContractProbeStep>.unmodifiable(steps),
       parameterDefaults = Map<String, String>.unmodifiable(parameterDefaults) {
    OpaqueId.validate(id, 'ContractProbePlan');
    if (steps.isEmpty || steps.length > 128) {
      throw ArgumentError('ContractProbePlan requires 1 through 128 steps');
    }
    final routeIds = steps.map((step) => step.routeId).toSet();
    if (routeIds.length != steps.length) {
      throw ArgumentError('ContractProbePlan route IDs must be unique');
    }
    for (final step in steps) {
      if (!routeIds.containsAll(step.after)) {
        throw ArgumentError('ContractProbePlan has an unknown dependency');
      }
    }
    _topologicalSteps(steps);
    for (final entry in parameterDefaults.entries) {
      if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(entry.key) ||
          entry.value.isEmpty ||
          entry.value.length > 4096) {
        throw FormatException('Invalid probe parameter default');
      }
    }
    if (artifactRetention == ProbeArtifactRetention.cas &&
        artifactClassification == ArtifactClassification.public) {
      throw ArgumentError('Probe response artifacts cannot be public');
    }
  }

  static const int schemaVersion = 1;

  final String id;
  final GatewayPresetId presetId;
  final List<ContractProbeStep> steps;
  final Map<String, String> parameterDefaults;
  final ProbeArtifactRetention artifactRetention;
  final ArtifactClassification artifactClassification;

  List<ContractProbeStep> get orderedSteps => _topologicalSteps(steps);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ContractProbePlan',
    'id': id,
    'presetId': presetId.value,
    'steps': <Object?>[for (final step in steps) step.toJson()],
    'parameterDefaults': <String, String>{
      for (final key in parameterDefaults.keys.toList()..sort())
        key: parameterDefaults[key]!,
    },
    'artifactRetention': artifactRetention.name,
    'artifactClassification': artifactClassification.name,
  };

  factory ContractProbePlan.fromJson(Object? value) {
    final json = _probeObject(value, 'ContractProbePlan');
    _probeOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'presetId',
      'steps',
      'parameterDefaults',
      'artifactRetention',
      'artifactClassification',
    }, 'ContractProbePlan');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ContractProbePlan') {
      throw const FormatException('Invalid ContractProbePlan version or kind');
    }
    final defaults = _probeObject(
      json['parameterDefaults'],
      'ContractProbePlan.parameterDefaults',
    );
    return ContractProbePlan(
      id: _probeString(json, 'id', 'ContractProbePlan'),
      presetId: GatewayPresetId(
        _probeString(json, 'presetId', 'ContractProbePlan'),
      ),
      steps: _probeList(
        json['steps'],
        'ContractProbePlan.steps',
      ).map(ContractProbeStep.fromJson).toList(),
      parameterDefaults: <String, String>{
        for (final entry in defaults.entries)
          entry.key: entry.value is String
              ? entry.value! as String
              : throw const FormatException(
                  'Probe parameter defaults must be strings',
                ),
      },
      artifactRetention: _probeEnum(
        ProbeArtifactRetention.values,
        _probeString(json, 'artifactRetention', 'ContractProbePlan'),
        'ContractProbePlan.artifactRetention',
      ),
      artifactClassification: _probeEnum(
        ArtifactClassification.values,
        _probeString(json, 'artifactClassification', 'ContractProbePlan'),
        'ContractProbePlan.artifactClassification',
      ),
    );
  }

  Digest get digest => Digest.semantic(toJson());
}

final class ContractProbeExecution {
  ContractProbeExecution({
    required this.routeId,
    required this.status,
    required this.bodyDigest,
    required this.bodySize,
    required Set<String> extractedParameters,
    this.artifact,
  }) : extractedParameters = Set<String>.unmodifiable(extractedParameters) {
    if (status < 100 || status > 599 || bodySize < 0) {
      throw ArgumentError('Invalid contract probe execution');
    }
  }

  final GatewayRouteId routeId;
  final int status;
  final Digest bodyDigest;
  final int bodySize;
  final Set<String> extractedParameters;
  final Artifact? artifact;

  Map<String, Object?> toJson() => <String, Object?>{
    'routeId': routeId.value,
    'status': status,
    'bodyDigest': bodyDigest.value,
    'bodySize': bodySize,
    'extractedParameters': extractedParameters.toList()..sort(),
    if (artifact != null) 'artifact': artifact!.toJson(),
  };
}

final class ContractProbeReport {
  ContractProbeReport({
    required this.planDigest,
    required this.gatewayPlanDigest,
    required this.presetId,
    required this.success,
    required List<ContractProbeExecution> executions,
  }) : executions = List<ContractProbeExecution>.unmodifiable(executions);

  final Digest planDigest;
  final Digest gatewayPlanDigest;
  final GatewayPresetId presetId;
  final bool success;
  final List<ContractProbeExecution> executions;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'ContractProbeReport',
    'planDigest': planDigest.value,
    'gatewayPlanDigest': gatewayPlanDigest.value,
    'presetId': presetId.value,
    'success': success,
    'executions': <Object?>[
      for (final execution in executions) execution.toJson(),
    ],
  };

  Digest get digest => Digest.semantic(toJson());
}

List<ContractProbeStep> _topologicalSteps(List<ContractProbeStep> steps) {
  final remaining = <GatewayRouteId, ContractProbeStep>{
    for (final step in steps) step.routeId: step,
  };
  final completed = <GatewayRouteId>{};
  final ordered = <ContractProbeStep>[];
  while (remaining.isNotEmpty) {
    final ready =
        remaining.values
            .where((step) => completed.containsAll(step.after))
            .toList()
          ..sort((left, right) {
            final byOrder = left.order.compareTo(right.order);
            return byOrder != 0
                ? byOrder
                : left.routeId.value.compareTo(right.routeId.value);
          });
    if (ready.isEmpty) {
      throw ArgumentError('ContractProbePlan has a cycle');
    }
    final next = ready.first;
    remaining.remove(next.routeId);
    completed.add(next.routeId);
    ordered.add(next);
  }
  return List<ContractProbeStep>.unmodifiable(ordered);
}

Object? _freezeProbeJson(Object? value) => switch (value) {
  null || bool() || num() || String() => value,
  List<Object?>() => List<Object?>.unmodifiable(value.map(_freezeProbeJson)),
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in value.entries) entry.key: _freezeProbeJson(entry.value),
  }),
  _ => throw const FormatException('Probe template must be JSON-compatible'),
};

final RegExp _jsonPointer = RegExp(r'^(?:/(?:[^~/]|~[01])*)*$');

Map<String, Object?> _probeObject(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$context must be an object');
  }
  return <String, Object?>{
    for (final entry in value.entries)
      entry.key is String
              ? entry.key! as String
              : throw FormatException('$context keys must be strings'):
          entry.value,
  };
}

List<Object?> _probeList(Object? value, String context) {
  if (value is! List<Object?>) {
    throw FormatException('$context must be an array');
  }
  return value;
}

void _probeOnly(Map<String, Object?> json, Set<String> fields, String context) {
  if (json.keys.any((key) => !fields.contains(key))) {
    throw FormatException('$context has unknown fields');
  }
}

String _probeString(Map<String, Object?> json, String key, String context) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$context.$key must be a non-empty string');
  }
  return value;
}

int _probeInteger(Map<String, Object?> json, String key, String context) {
  final value = json[key];
  if (value is! int) throw FormatException('$context.$key must be an integer');
  return value;
}

List<String> _probeStringList(Object? value, String context) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$context must be a string array');
  }
  final output = value.cast<String>();
  if (output.toSet().length != output.length) {
    throw FormatException('$context must contain unique values');
  }
  return output;
}

T _probeEnum<T extends Enum>(List<T> values, String value, String context) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$context has an invalid value');
}
