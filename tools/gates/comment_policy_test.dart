import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'comment_policy.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('comment-policy-');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('Dart tokenizer distinguishes strings and public API documentation', () {
    _write(root, 'pubspec.yaml', 'name: fixture\n');
    _write(
      root,
      'libs/contracts/lib/contracts.dart',
      "/// External contract.\nclass Contract {\n  final uri = 'https://host/path//value';\n}\n",
    );
    _write(
      root,
      'apps/studio/lib/studio.dart',
      "final uri = 'https://host/path//value';\n// Internal narration.\nvoid render() {}\n",
    );

    final violations = CommentPolicy(root: root.path).check();

    expect(violations, hasLength(1));
    expect(violations.single.preview, '// Internal narration.');
  });

  test('Dart tokenizer preserves a required empty-catch rationale', () {
    _write(root, 'pubspec.yaml', 'name: fixture\n');
    _write(
      root,
      'apps/studio/lib/studio.dart',
      'void close() {\n'
          '  try {\n'
          '    throw StateError("closed");\n'
          '  } catch (_) {\n'
          '    // Cleanup is best-effort.\n'
          '  }\n'
          '}\n',
    );

    expect(CommentPolicy(root: root.path).check(), isEmpty);
  });

  test('shell scanner preserves shebang directives strings and heredocs', () {
    _write(root, 'pubspec.yaml', 'name: fixture\n');
    _write(root, 'tools/verify/check.sh', r'''#!/usr/bin/env bash
# shellcheck disable=SC2034
url="https://host/#fragment"
count=${#items[@]}
cat <<'PAYLOAD'
# payload data
PAYLOAD
# narration
''');

    final violations = CommentPolicy(root: root.path).check();

    expect(violations, hasLength(1));
    expect(violations.single.preview, '# narration');
    expect(
      CommentPolicy(root: root.path).removeNonEssentialComments(
        'tools/verify/check.sh',
        File(p.join(root.path, 'tools/verify/check.sh')).readAsStringSync(),
      ),
      contains(r'${#items[@]}'),
    );
  });

  test('CSS and YAML scanners ignore strings and block scalar data', () {
    _write(root, 'pubspec.yaml', 'name: fixture\n');
    _write(
      root,
      'apps/studio/web/styles.css',
      'a[href="https://host/*value*/"] {}\n/* narration */\n',
    );
    _write(
      root,
      'examples/sample/workspace.yaml',
      "value: 'literal # value'\nscript: |\n  # payload\n# narration\n",
    );

    final violations = CommentPolicy(root: root.path).check();

    expect(violations.map((violation) => violation.preview), <String>[
      '/* narration */',
      '# narration',
    ]);
  });

  test('fallback inventory excludes Flutter generated platform files', () {
    _write(root, 'pubspec.yaml', 'name: fixture\n');
    _write(
      root,
      'examples/sample_flutter/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
      '/** Generated file. Do not edit. */\n',
    );
    _write(
      root,
      'examples/sample_flutter/android/local.properties',
      '# Generated SDK location.\n',
    );

    expect(CommentPolicy(root: root.path).check(), isEmpty);
  });

  test('rewriter removes only comments rejected by the policy', () {
    final policy = CommentPolicy(root: root.path);
    final source =
        "final uri = 'https://host//value'; // narration\n"
        '// ignore: close_sinks\n'
        'void close() {}\n';

    expect(
      policy.removeNonEssentialComments('apps/host/lib/host.dart', source),
      "final uri = 'https://host//value'; \n"
      '// ignore: close_sinks\n'
      'void close() {}\n',
    );
  });

  test('rewriter removes a rejected comment-only line with its line break', () {
    final policy = CommentPolicy(root: root.path);

    expect(
      policy.removeNonEssentialComments(
        'tools/verify/check.sh',
        'before\n  # narration\nafter\n',
      ),
      'before\nafter\n',
    );
  });
}

void _write(Directory root, String relativePath, String content) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
