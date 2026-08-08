import 'dart:convert';

import 'package:yaml/yaml.dart';

enum AuthoringKind {
  workspace,
  application,
  journey,
  scenario,
  transition,
  gatewayScope,
  gatewayPreset,
  gatewayRoute,
  gatewayFixture,
  scenarioExecutionBinding,
  reviewGuide,
  board,
  experienceProjection,
  nodeInstance,
  edgeInstance,
  projectionLayout,
  scenarioKindDefinition,
  experienceSurface,
  scenarioState,
  ownershipArea,
  scenarioTag,
  experienceComponent,
  scenarioFixture,
  formFactor,
  presentationFrame,
  scenarioFacet,
  appAdapterCapability,
  scenarioControl,
  scenarioLabOperation,
  scenarioScript,
  automatedAcceptanceCriterion,
  requiredEvidence,
  scenarioComparisonBinding,
  visualComparisonPolicy,
  semanticComparisonPolicy,
  humanApprovalRequirement,
  supplementalArtifact,
  scenarioLabPlan,
  motionSequence,
}

const Set<AuthoringKind> _v1AuthoringKinds = <AuthoringKind>{
  AuthoringKind.workspace,
  AuthoringKind.application,
  AuthoringKind.journey,
  AuthoringKind.scenario,
  AuthoringKind.transition,
  AuthoringKind.gatewayScope,
  AuthoringKind.gatewayPreset,
  AuthoringKind.gatewayRoute,
  AuthoringKind.gatewayFixture,
  AuthoringKind.scenarioExecutionBinding,
  AuthoringKind.reviewGuide,
};

const Set<AuthoringKind> _v2AuthoringKinds = <AuthoringKind>{
  AuthoringKind.board,
  AuthoringKind.experienceProjection,
  AuthoringKind.nodeInstance,
  AuthoringKind.edgeInstance,
  AuthoringKind.projectionLayout,
  AuthoringKind.scenarioKindDefinition,
  AuthoringKind.experienceSurface,
  AuthoringKind.scenarioState,
  AuthoringKind.ownershipArea,
  AuthoringKind.scenarioTag,
  AuthoringKind.experienceComponent,
  AuthoringKind.scenarioFixture,
  AuthoringKind.formFactor,
  AuthoringKind.presentationFrame,
  AuthoringKind.scenarioFacet,
  AuthoringKind.appAdapterCapability,
  AuthoringKind.scenarioControl,
  AuthoringKind.scenarioLabOperation,
  AuthoringKind.scenarioScript,
  AuthoringKind.automatedAcceptanceCriterion,
  AuthoringKind.requiredEvidence,
  AuthoringKind.scenarioComparisonBinding,
  AuthoringKind.visualComparisonPolicy,
  AuthoringKind.semanticComparisonPolicy,
  AuthoringKind.humanApprovalRequirement,
  AuthoringKind.supplementalArtifact,
  AuthoringKind.scenarioLabPlan,
  AuthoringKind.motionSequence,
};

final class AuthoringDocument {
  AuthoringDocument({
    required this.schemaVersion,
    required this.kind,
    required this.id,
    required Map<String, Object?> spec,
    required this.sourceName,
  }) : spec = Map<String, Object?>.unmodifiable(spec);

  final int schemaVersion;
  final AuthoringKind kind;
  final String id;
  final Map<String, Object?> spec;
  final String sourceName;
}

final class AuthoringParseException implements FormatException {
  const AuthoringParseException(this.message, {required this.sourceName});

  @override
  final String message;
  final String sourceName;

  @override
  Object? get source => sourceName;

  @override
  int? get offset => null;

  @override
  String toString() => '$sourceName: $message';
}

final class SafeAuthoringParser {
  const SafeAuthoringParser({
    this.maxSourceBytes = 1024 * 1024,
    this.maxDepth = 32,
    this.maxNodes = 100000,
  });

  final int maxSourceBytes;
  final int maxDepth;
  final int maxNodes;

  AuthoringDocument parse(String source, {required String sourceName}) {
    return _decode(parseObject(source, sourceName: sourceName), sourceName);
  }

  Map<String, Object?> parseObject(
    String source, {
    required String sourceName,
  }) {
    if (utf8.encode(source).length > maxSourceBytes) {
      throw AuthoringParseException(
        'document exceeds $maxSourceBytes bytes',
        sourceName: sourceName,
      );
    }
    final Object? raw;
    try {
      if (_looksLikeJson(source)) {
        _rejectDuplicateJsonKeys(source, sourceName);
        raw = jsonDecode(source);
        _validateJsonTree(raw, sourceName);
      } else {
        raw = _yamlToJson(loadYaml(source), sourceName);
      }
    } on FormatException catch (error) {
      throw AuthoringParseException(error.message, sourceName: sourceName);
    }
    if (raw is! Map<String, Object?>) {
      throw AuthoringParseException(
        'document root must be an object',
        sourceName: sourceName,
      );
    }
    return raw;
  }

  bool _looksLikeJson(String source) {
    final trimmed = source.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  void _rejectDuplicateJsonKeys(String source, String sourceName) {
    final objectKeys = <Set<String>?>[];
    var index = 0;

    int skipWhitespace(int offset) {
      while (offset < source.length) {
        final unit = source.codeUnitAt(offset);
        if (unit != 0x20 && unit != 0x09 && unit != 0x0a && unit != 0x0d) {
          break;
        }
        offset += 1;
      }
      return offset;
    }

    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      if (unit == 0x22) {
        final start = index;
        index += 1;
        var escaped = false;
        while (index < source.length) {
          final current = source.codeUnitAt(index);
          index += 1;
          if (escaped) {
            escaped = false;
          } else if (current == 0x5c) {
            escaped = true;
          } else if (current == 0x22) {
            break;
          }
        }
        if (index > source.length || source.codeUnitAt(index - 1) != 0x22) {
          return;
        }
        final next = skipWhitespace(index);
        if (objectKeys.isNotEmpty &&
            objectKeys.last != null &&
            next < source.length &&
            source.codeUnitAt(next) == 0x3a) {
          final key = jsonDecode(source.substring(start, index));
          if (key is String && !objectKeys.last!.add(key)) {
            throw AuthoringParseException(
              'duplicate key: $key',
              sourceName: sourceName,
            );
          }
        }
        continue;
      }
      if (unit == 0x7b) {
        objectKeys.add(<String>{});
      } else if (unit == 0x5b) {
        objectKeys.add(null);
      } else if ((unit == 0x7d || unit == 0x5d) && objectKeys.isNotEmpty) {
        objectKeys.removeLast();
      }
      index += 1;
    }
  }

  void _validateJsonTree(Object? root, String sourceName) {
    var nodes = 0;

    void visit(Object? value, int depth) {
      nodes += 1;
      if (nodes > maxNodes) {
        throw AuthoringParseException(
          'document exceeds $maxNodes parsed nodes',
          sourceName: sourceName,
        );
      }
      if (depth > maxDepth) {
        throw AuthoringParseException(
          'document exceeds nesting depth $maxDepth',
          sourceName: sourceName,
        );
      }
      if (value is num) {
        const maxSafeInteger = 9007199254740991;
        final isNegativeZero =
            value is double && value == 0 && value.isNegative;
        final isUnsafeInteger = switch (value) {
          int() => value.abs() > maxSafeInteger,
          double() =>
            value.isFinite &&
                value.truncateToDouble() == value &&
                value.abs() > maxSafeInteger,
        };
        if (!value.isFinite || isNegativeZero || isUnsafeInteger) {
          throw AuthoringParseException(
            'document contains a non-interoperable number',
            sourceName: sourceName,
          );
        }
        return;
      }
      if (value == null || value is String || value is bool) return;
      if (value is List<Object?>) {
        for (final item in value) {
          visit(item, depth + 1);
        }
        return;
      }
      if (value is Map<String, Object?>) {
        for (final entry in value.entries) {
          visit(entry.value, depth + 1);
        }
        return;
      }
      throw AuthoringParseException(
        'unsupported JSON value ${value.runtimeType}',
        sourceName: sourceName,
      );
    }

    visit(root, 0);
  }

  Object? _yamlToJson(Object? root, String sourceName) {
    var nodes = 0;
    final active = Set<Object>.identity();

    Object? convert(Object? value, int depth) {
      nodes += 1;
      if (nodes > maxNodes) {
        throw AuthoringParseException(
          'document exceeds $maxNodes parsed nodes',
          sourceName: sourceName,
        );
      }
      if (depth > maxDepth) {
        throw AuthoringParseException(
          'document exceeds nesting depth $maxDepth',
          sourceName: sourceName,
        );
      }
      if (value == null || value is String || value is bool || value is num) {
        if (value is num) _validateJsonTree(value, sourceName);
        return value;
      }
      if (!active.add(value)) {
        throw AuthoringParseException(
          'YAML aliases must not form a cycle',
          sourceName: sourceName,
        );
      }
      try {
        if (value is YamlList || value is List<Object?>) {
          return <Object?>[
            for (final item in value as Iterable<Object?>)
              convert(item, depth + 1),
          ];
        }
        if (value is YamlMap || value is Map<Object?, Object?>) {
          final output = <String, Object?>{};
          for (final entry in (value as Map<Object?, Object?>).entries) {
            if (entry.key is! String) {
              throw AuthoringParseException(
                'object keys must be strings',
                sourceName: sourceName,
              );
            }
            final key = entry.key! as String;
            if (output.containsKey(key)) {
              throw AuthoringParseException(
                'duplicate key: $key',
                sourceName: sourceName,
              );
            }
            output[key] = convert(entry.value, depth + 1);
          }
          return output;
        }
      } finally {
        active.remove(value);
      }
      throw AuthoringParseException(
        'unsupported YAML value ${value.runtimeType}',
        sourceName: sourceName,
      );
    }

    return convert(root, 0);
  }

  AuthoringDocument _decode(Map<String, Object?> input, String sourceName) {
    final version = input['schemaVersion'];
    if (version != 1 && version != 2) {
      throw AuthoringParseException(
        'schemaVersion must equal 1 or 2',
        sourceName: sourceName,
      );
    }
    const allowed = <String>{'schemaVersion', 'kind', 'metadata', 'spec'};
    _rejectUnknown(input, allowed, sourceName, r'$');
    final kind = _kind(
      input['kind'],
      sourceName,
      allowedKinds: version == 1 ? _v1AuthoringKinds : _v2AuthoringKinds,
    );
    final metadata = _object(input['metadata'], sourceName, r'$.metadata');
    _rejectUnknown(metadata, const <String>{'id'}, sourceName, r'$.metadata');
    final id = _requiredString(metadata, 'id', sourceName, r'$.metadata');
    final spec = _object(input['spec'], sourceName, r'$.spec');
    return AuthoringDocument(
      schemaVersion: version! as int,
      kind: kind,
      id: id,
      spec: spec,
      sourceName: sourceName,
    );
  }

  AuthoringKind _kind(
    Object? value,
    String sourceName, {
    required Set<AuthoringKind> allowedKinds,
  }) {
    if (value is! String) {
      throw AuthoringParseException(
        'kind must be a string',
        sourceName: sourceName,
      );
    }
    for (final kind in allowedKinds) {
      if (kind.name.toLowerCase() == value.toLowerCase()) return kind;
    }
    throw AuthoringParseException(
      'unsupported kind: $value',
      sourceName: sourceName,
    );
  }

  Map<String, Object?> _object(Object? value, String sourceName, String path) {
    if (value is! Map<String, Object?>) {
      throw AuthoringParseException(
        '$path must be an object',
        sourceName: sourceName,
      );
    }
    return value;
  }

  String _requiredString(
    Map<String, Object?> value,
    String key,
    String sourceName,
    String path,
  ) {
    final item = value[key];
    if (item is! String || item.trim().isEmpty) {
      throw AuthoringParseException(
        '$path.$key must be a non-empty string',
        sourceName: sourceName,
      );
    }
    return item;
  }

  void _rejectUnknown(
    Map<String, Object?> value,
    Set<String> allowed,
    String sourceName,
    String path,
  ) {
    for (final key in value.keys) {
      if (!allowed.contains(key)) {
        throw AuthoringParseException(
          'unknown field $path.$key',
          sourceName: sourceName,
        );
      }
    }
  }
}
