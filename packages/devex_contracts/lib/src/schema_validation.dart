import 'package:json_schema/json_schema.dart';

final class SchemaValidationIssue {
  const SchemaValidationIssue({
    required this.instancePath,
    required this.schemaPath,
    required this.message,
  });

  final String instancePath;
  final String schemaPath;
  final String message;
}

final class SchemaValidationResult {
  const SchemaValidationResult(this.issues);

  final List<SchemaValidationIssue> issues;

  bool get isValid => issues.isEmpty;
}

/// Closed wrapper around the selected Draft 2020-12 implementation.
final class Draft202012Validator {
  Draft202012Validator(Object schema) : _schema = _createSchema(schema);

  static const Set<String> _integerCountKeywords = <String>{
    'maxContains',
    'maxItems',
    'maxLength',
    'maxProperties',
    'minContains',
    'minItems',
    'minLength',
    'minProperties',
  };

  static const Set<String> _unsupportedProfileKeywords = <String>{
    r'$dynamicAnchor',
    r'$dynamicRef',
    'contentSchema',
    'unevaluatedItems',
  };

  static const Set<String> _supportedVocabularies = <String>{
    'https://json-schema.org/draft/2020-12/vocab/core',
    'https://json-schema.org/draft/2020-12/vocab/applicator',
    'https://json-schema.org/draft/2020-12/vocab/unevaluated',
    'https://json-schema.org/draft/2020-12/vocab/validation',
    'https://json-schema.org/draft/2020-12/vocab/meta-data',
    'https://json-schema.org/draft/2020-12/vocab/format-annotation',
    'https://json-schema.org/draft/2020-12/vocab/format-assertion',
    'https://json-schema.org/draft/2020-12/vocab/content',
  };

  final JsonSchema _schema;

  SchemaValidationResult validate(Object? instance) {
    final result = _schema.validate(instance);
    return SchemaValidationResult(
      List<SchemaValidationIssue>.unmodifiable(
        result.errors.map(
          (error) => SchemaValidationIssue(
            instancePath: error.instancePath,
            schemaPath: error.schemaPath,
            message: error.message,
          ),
        ),
      ),
    );
  }

  static JsonSchema _createSchema(Object schema) {
    _validateProfile(schema, r'$');
    if (schema case final Map<Object?, Object?> schemaMap) {
      final declaredSchema = schemaMap[r'$schema'];
      if (declaredSchema != null &&
          declaredSchema != 'https://json-schema.org/draft/2020-12/schema') {
        throw FormatException('Only JSON Schema Draft 2020-12 is supported');
      }
      final vocabulary = schemaMap[r'$vocabulary'];
      if (vocabulary case final Map<Object?, Object?> entries) {
        for (final entry in entries.entries) {
          if (entry.value == true &&
              entry.key is String &&
              !_supportedVocabularies.contains(entry.key)) {
            throw FormatException(
              'Unsupported required JSON Schema vocabulary: ${entry.key}',
            );
          }
        }
      }
    }
    return JsonSchema.create(schema, schemaVersion: SchemaVersion.draft2020_12);
  }

  static void _validateProfile(Object? value, String path) {
    if (value case final Map<Object?, Object?> map) {
      for (final entry in map.entries) {
        final key = entry.key;
        if (key is! String) {
          throw FormatException('Schema key must be a string at $path');
        }
        if (_unsupportedProfileKeywords.contains(key)) {
          throw FormatException('$key is outside the DevExKit schema profile');
        }
        if (key == r'$ref' &&
            entry.value is String &&
            !(entry.value! as String).startsWith('#')) {
          throw const FormatException(
            'External references are outside the DevExKit v1 schema profile',
          );
        }
        if (key == 'enum' &&
            entry.value is List<Object?> &&
            (entry.value! as List<Object?>).isEmpty) {
          throw const FormatException('enum must not be empty');
        }
        if (_integerCountKeywords.contains(key) && entry.value is! int) {
          throw FormatException('$key must use an integer JSON representation');
        }
        _validateProfile(entry.value, '$path.$key');
      }
    } else if (value case final List<Object?> list) {
      for (var index = 0; index < list.length; index += 1) {
        _validateProfile(list[index], '$path[$index]');
      }
    }
  }
}
