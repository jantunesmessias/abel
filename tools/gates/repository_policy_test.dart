import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'repository_policy.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('repository-policy-');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('accepts canonical public package boundaries and local links', () {
    _write(root, 'pubspec.yaml', 'name: fixture_workspace\n');
    _write(root, 'libs/contracts/pubspec.yaml', 'name: contracts\n');
    _write(
      root,
      'libs/contracts/lib/contracts.dart',
      'class PublicContract {}\n',
    );
    _write(root, 'apps/host/pubspec.yaml', 'name: host\n');
    _write(
      root,
      'apps/host/lib/host.dart',
      "import 'package:contracts/contracts.dart';\nvoid use(PublicContract value) {}\n",
    );
    _write(root, 'docs/README.md', '[Architecture](../ARCHITECTURE.md)\n');
    _write(root, 'ARCHITECTURE.md', '# Architecture\n');

    expect(RepositoryPolicy(root: root.path).check(), isEmpty);
  });

  test(
    'reports technical paths, private imports, generated state, and links',
    () {
      const retiredName =
          'dev'
          'ex';
      _write(root, 'pubspec.yaml', 'name: fixture_workspace\n');
      _write(root, 'libs/contracts/pubspec.yaml', 'name: contracts\n');
      _write(root, 'libs/contracts/lib/src/private.dart', 'class Private {}\n');
      _write(root, 'apps/host/pubspec.yaml', 'name: host\n');
      _write(
        root,
        'apps/host/lib/host.dart',
        "import 'package:contracts/src/private.dart';\nvoid use(Private value) {}\n",
      );
      _write(root, 'tools/$retiredName-helper.sh', '#!/usr/bin/env bash\n');
      _write(root, 'apps/host/build/output.txt', 'generated\n');
      _write(root, 'docs/README.md', '[Missing](missing.md)\n');

      final codes = RepositoryPolicy(
        root: root.path,
      ).check().map((violation) => violation.code).toSet();

      expect(codes, contains('cross-package-private-import'));
      expect(codes, contains('technical-identity-path'));
      expect(codes, contains('markdown-link'));
      expect(codes, isNot(contains('tracked-generated')));
    },
  );

  test('fallback inventory excludes generated directories', () {
    const retiredName =
        'dev'
        'ex';
    _write(root, 'pubspec.yaml', 'name: fixture_workspace\n');
    _write(root, 'build/$retiredName-output.txt', 'generated\n');
    _write(root, '.dart_tool/state.txt', 'generated\n');
    _write(
      root,
      'examples/consumer/.flutter-plugins-dependencies',
      '{"root":"/tmp/$retiredName-generated"}\n',
    );
    _write(
      root,
      'examples/sample_flutter/android/local.properties',
      'sdk.dir=/tmp/$retiredName-sdk\n',
    );
    _write(
      root,
      'examples/sample_flutter/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
      'class ${retiredName}Generated {}\n',
    );

    expect(RepositoryPolicy(root: root.path).check(), isEmpty);
  });

  test('rejects the retired abbreviated CSS identity', () {
    const retiredCssClass =
        'd'
        'x-button';
    _write(root, 'pubspec.yaml', 'name: fixture_workspace\n');
    _write(root, 'apps/studio/web/styles.css', '.$retiredCssClass {}\n');

    expect(
      RepositoryPolicy(
        root: root.path,
      ).check().map((violation) => violation.code),
      contains('technical-identity-text'),
    );
  });
}

void _write(Directory root, String relativePath, String content) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
