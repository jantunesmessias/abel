import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = _root();

  test('all V2 schemas compile inside the closed DevExKit profile', () {
    final files =
        Directory(
            p.join(root, 'schemas', 'v2'),
          ).listSync(followLinks: false).whereType<File>().toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    expect(files, hasLength(3));
    for (final file in files) {
      expect(
        () =>
            Draft202012Validator(jsonDecode(file.readAsStringSync()) as Object),
        returnsNormally,
        reason: file.path,
      );
    }
  });

  test('consumer config v2 accepts explicit modules and rejects v1', () {
    final validator = _validator(root, 'consumer-config.schema.json');
    final document = <String, Object?>{
      'schemaVersion': 2,
      'content': <String, Object?>{'root': '.devex'},
      'workspace': <String, Object?>{'id': 'sample', 'displayName': 'Sample'},
      'applications': <String, Object?>{
        'sample': <String, Object?>{'root': '.', 'target': 'web'},
      },
      'launchProfiles': <String, Object?>{
        'sample-web': <String, Object?>{
          'applicationId': 'sample',
          'platform': 'web',
          'command': 'flutter',
          'arguments': <String>['run', '-d', 'web-server'],
          'workingDirectory': '.',
          'overlay': <String, String>{'DEVEX_EXAMPLE_MODE': 'full'},
          'bootstrapPolicy': <String, String>{
            'api': 'production',
            'gateway': 'overlay',
          },
        },
      },
      'kit': <String, Object?>{
        'profile': 'journey-preview',
        'modules': <String, Object?>{
          'catalog': <String, Object?>{'enabled': true},
          'evidence.auto-preview': <String, Object?>{
            'enabled': true,
            'settings': <String, Object?>{
              'renderer': 'flutter-test',
              'capturePolicy': 'static-v1',
            },
          },
        },
      },
    };
    expect(validator.validate(document).isValid, isTrue);
    expect(
      validator.validate(<String, Object?>{
        ...document,
        'schemaVersion': 1,
      }).isValid,
      isFalse,
    );
    expect(
      validator.validate(<String, Object?>{
        ...document,
        'unknown': true,
      }).isValid,
      isFalse,
    );
  });
}

Draft202012Validator _validator(String root, String name) =>
    Draft202012Validator(
      jsonDecode(File(p.join(root, 'schemas', 'v2', name)).readAsStringSync())
          as Object,
    );

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
