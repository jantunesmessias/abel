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
}

final class AuthoringDocument {
  AuthoringDocument({
    required this.schemaVersion,
    required this.kind,
    required this.id,
    required Map<String, Object?> spec,
    required this.sourceName,
    this.wasMigrated = false,
  }) : spec = Map<String, Object?>.unmodifiable(spec);

  final int schemaVersion;
  final AuthoringKind kind;
  final String id;
  final Map<String, Object?> spec;
  final String sourceName;
  final bool wasMigrated;
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
      raw = _looksLikeJson(source)
          ? jsonDecode(source)
          : _yamlToJson(loadYaml(source), sourceName);
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
    if (version == 0) return _migrateV0(input, sourceName);
    if (version != 1) {
      throw AuthoringParseException(
        'schemaVersion must equal 1',
        sourceName: sourceName,
      );
    }
    const allowed = <String>{'schemaVersion', 'kind', 'metadata', 'spec'};
    _rejectUnknown(input, allowed, sourceName, r'$');
    final kind = _kind(input['kind'], sourceName);
    final metadata = _object(input['metadata'], sourceName, r'$.metadata');
    _rejectUnknown(metadata, const <String>{'id'}, sourceName, r'$.metadata');
    final id = _requiredString(metadata, 'id', sourceName, r'$.metadata');
    final spec = _object(input['spec'], sourceName, r'$.spec');
    return AuthoringDocument(
      schemaVersion: 1,
      kind: kind,
      id: id,
      spec: spec,
      sourceName: sourceName,
    );
  }

  AuthoringDocument _migrateV0(Map<String, Object?> input, String sourceName) {
    const allowed = <String>{'schemaVersion', 'type', 'id', 'properties'};
    _rejectUnknown(input, allowed, sourceName, r'$');
    final kind = _kind(input['type'], sourceName);
    final id = input['id'];
    if (id is! String || id.isEmpty) {
      throw AuthoringParseException(
        'legacy id must be a string',
        sourceName: sourceName,
      );
    }
    return AuthoringDocument(
      schemaVersion: 1,
      kind: kind,
      id: id,
      spec: _object(input['properties'], sourceName, r'$.properties'),
      sourceName: sourceName,
      wasMigrated: true,
    );
  }

  AuthoringKind _kind(Object? value, String sourceName) {
    if (value is! String) {
      throw AuthoringParseException(
        'kind must be a string',
        sourceName: sourceName,
      );
    }
    for (final kind in AuthoringKind.values) {
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
