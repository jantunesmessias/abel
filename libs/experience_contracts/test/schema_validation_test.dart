import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  final schema = <String, Object?>{
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    'required': <String>['name'],
    'properties': <String, Object?>{
      'name': <String, Object?>{'type': 'string', 'minLength': 1},
      'tags': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
        'uniqueItems': true,
      },
    },
    'unevaluatedProperties': false,
  };

  test('validates a supported Draft 2020-12 document', () {
    final validator = Draft202012Validator(schema);

    expect(
      validator.validate(<String, Object?>{
        'name': 'Explore',
        'tags': <String>['current'],
      }).isValid,
      isTrue,
    );
  });

  test('reports every relevant validation issue', () {
    final validator = Draft202012Validator(schema);
    final result = validator.validate(<String, Object?>{
      'name': '',
      'tags': <String>['same', 'same'],
      'unknown': true,
    });

    expect(result.isValid, isFalse);
    expect(result.issues.length, greaterThanOrEqualTo(2));
  });

  test('fails closed for an unsupported required vocabulary', () {
    expect(
      () => Draft202012Validator(<String, Object?>{
        r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        r'$vocabulary': <String, bool>{'urn:example:unknown': true},
      }),
      throwsFormatException,
    );
  });

  test('rejects Draft features outside the verified schema profile', () {
    for (final unsupported in <Map<String, Object?>>[
      <String, Object?>{r'$dynamicRef': '#node'},
      <String, Object?>{r'$ref': 'https://example.test/schema.json'},
      <String, Object?>{'enum': <Object?>[]},
      <String, Object?>{'minItems': 1.0},
      <String, Object?>{'unevaluatedItems': false},
    ]) {
      expect(() => Draft202012Validator(unsupported), throwsFormatException);
    }
  });

  test('does not interpret property names as schema keywords', () {
    final validator = Draft202012Validator(<String, Object?>{
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
      'properties': <String, Object?>{
        'maxItems': <String, Object?>{'type': 'integer', 'minimum': 0},
        r'$ref': <String, Object?>{'type': 'string'},
      },
      'additionalProperties': false,
    });

    expect(
      validator.validate(<String, Object?>{
        'maxItems': 4,
        r'$ref': 'local',
      }).isValid,
      isTrue,
    );
  });
}
