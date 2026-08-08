import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = _repositoryRoot();

  test('all source schemas are valid closed-profile schemas', () {
    final schemaFiles =
        Directory(
            p.join(root, 'schemas', 'source'),
          ).listSync().whereType<File>().toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    expect(schemaFiles.map((file) => p.basename(file.path)), const <String>[
      'catalog-authoring-document.schema.json',
      'experience-authoring-document.schema.json',
      'plugin-manifest.schema.json',
      'source-automation.schema.json',
      'source-reference.schema.json',
    ]);
    for (final file in schemaFiles) {
      expect(
        () =>
            Draft202012Validator(jsonDecode(file.readAsStringSync()) as Object),
        returnsNormally,
        reason: file.path,
      );
    }
  });

  test(
    'authoring fixtures cover valid, invalid, and unsupported documents',
    () {
      final schema = jsonDecode(
        File(
          p.join(
            root,
            'schemas',
            'source',
            'catalog-authoring-document.schema.json',
          ),
        ).readAsStringSync(),
      );
      final validator = Draft202012Validator(schema as Object);
      Object fixture(String state) =>
          jsonDecode(
                File(
                  p.join(
                    root,
                    'tests',
                    'conformance',
                    'authoring',
                    state,
                    'authoring-document.json',
                  ),
                ).readAsStringSync(),
              )
              as Object;

      expect(validator.validate(fixture('valid')).isValid, isTrue);
      expect(validator.validate(fixture('invalid')).isValid, isFalse);
      expect(validator.validate(fixture('unsupported')).isValid, isFalse);
    },
  );
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
