import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = _repositoryRoot();

  test('all V1 schemas are valid closed-profile schemas', () {
    final schemaFiles =
        Directory(
            p.join(root, 'schemas', 'v1'),
          ).listSync().whereType<File>().toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    expect(schemaFiles, isNotEmpty);
    for (final file in schemaFiles) {
      expect(
        () =>
            Draft202012Validator(jsonDecode(file.readAsStringSync()) as Object),
        returnsNormally,
        reason: file.path,
      );
    }
  });

  test('authoring fixtures cover valid and invalid V1 plus adjacent V0', () {
    final schema = jsonDecode(
      File(
        p.join(root, 'schemas', 'v1', 'authoring-document.schema.json'),
      ).readAsStringSync(),
    );
    final validator = Draft202012Validator(schema as Object);
    Object fixture(String state) =>
        jsonDecode(
              File(
                p.join(
                  root,
                  'test',
                  'conformance',
                  'v0_a',
                  state,
                  state == 'adjacent'
                      ? 'authoring-document-v0.json'
                      : 'authoring-document.json',
                ),
              ).readAsStringSync(),
            )
            as Object;

    expect(validator.validate(fixture('valid')).isValid, isTrue);
    expect(validator.validate(fixture('invalid')).isValid, isFalse);
    expect(validator.validate(fixture('adjacent')).isValid, isFalse);
  });
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
