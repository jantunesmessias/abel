import 'dart:io';

import 'package:path/path.dart' as p;

final class ImportRule {
  const ImportRule({
    required this.root,
    required this.forbiddenFragments,
    required this.reason,
  });

  final String root;
  final List<String> forbiddenFragments;
  final String reason;
}

void main() {
  final rules = <ImportRule>[
    const ImportRule(
      root: 'libs/experience_engine/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:execution_runtime/',
      ],
      reason: 'experience_engine must remain pure Dart and adapter-independent',
    ),
    const ImportRule(
      root: 'libs/flutter_app_adapter/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:experience_engine/',
        'package:execution_runtime/',
      ],
      reason:
          'flutter_app_adapter is an app-facing adapter over contracts only',
    ),
    const ImportRule(
      root: 'libs/interaction_model/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:experience_engine/',
        'package:execution_runtime/',
      ],
      reason: 'interaction_model must remain a pure-Dart interaction policy',
    ),
    const ImportRule(
      root: 'libs/studio_ui/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:experience_engine/',
        'package:execution_runtime/',
      ],
      reason: 'studio_ui must remain a Jaspr/HTML/CSS renderer',
    ),
    const ImportRule(
      root: 'apps/studio/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:go_router/',
        'package:experience_engine/',
        'package:execution_runtime/',
      ],
      reason:
          'Studio must use the owned UI System and typed Host client without privileged I/O',
    ),
    const ImportRule(
      root: 'apps/studio/lib/src/model',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
        'package:experience_engine/',
        'package:execution_runtime/',
      ],
      reason: 'Studio models must remain renderer-independent pure Dart',
    ),
    const ImportRule(
      root: 'apps/studio/lib/src/controllers',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
        'package:experience_engine/',
        'package:execution_runtime/',
      ],
      reason: 'Studio controllers must remain renderer-independent pure Dart',
    ),
    const ImportRule(
      root: 'apps/studio/lib/src/journey_map/journey_map_view_data.dart',
      forbiddenFragments: <String>[
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
      ],
      reason: 'Journey projections must remain reusable by the Jaspr renderer',
    ),
    const ImportRule(
      root: 'apps/studio/lib/src/journey_map/visual_evidence_presentation.dart',
      forbiddenFragments: <String>[
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
      ],
      reason: 'Evidence presentation policy must remain renderer-independent',
    ),
    const ImportRule(
      root: 'examples/sample_flutter/lib/main.dart',
      forbiddenFragments: <String>[
        'package:execution_runtime/',
        'package:experience_contracts/',
        'package:experience_engine/',
        'package:flutter_app_adapter/',
        'package:flutter_preview/',
        'package:interaction_model/',
        'package:studio_ui/',
        'package:testing_support/',
      ],
      reason: 'the production entrypoint must not import platform tooling',
    ),
  ];

  final violations = <String>[];
  for (final rule in rules) {
    final target = FileSystemEntity.typeSync(rule.root);
    final files = switch (target) {
      FileSystemEntityType.file => <File>[File(rule.root)],
      FileSystemEntityType.directory =>
        Directory(rule.root)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
      _ => <File>[],
    };
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final fragment in rule.forbiddenFragments) {
        if (isForbiddenArchitectureFragment(
          root: rule.root,
          filePath: file.path,
          source: source,
          fragment: fragment,
        )) {
          violations.add('${file.path}: $fragment (${rule.reason})');
        }
      }
    }
  }

  final forbiddenFiles = <String>{
    'apps/studio/lib/main.dart',
    'apps/studio/web/flutter_bootstrap.js',
  };
  for (final path in forbiddenFiles) {
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      violations.add('$path: legacy Flutter Studio artifact is forbidden');
    }
  }

  final packageRules = <String, List<String>>{
    'apps/studio/pubspec.yaml': <String>[
      'sdk: flutter',
      'flutter_riverpod:',
      'flutter_web_plugins:',
      'go_router:',
      'flutter_test:',
      'integration_test:',
    ],
    'libs/studio_ui/pubspec.yaml': <String>[
      'sdk: flutter',
      'flutter_test:',
      'lucide_icons_flutter:',
    ],
  };
  for (final entry in packageRules.entries) {
    final source = File(entry.key).readAsStringSync();
    for (final fragment in entry.value) {
      if (source.contains(fragment)) {
        violations.add(
          '${entry.key}: $fragment (Flutter is forbidden in the Jaspr Studio boundary)',
        );
      }
    }
  }

  final packageDirectories = <Directory>[Directory('apps'), Directory('libs')]
      .expand(
        (directory) =>
            directory.listSync(followLinks: false).whereType<Directory>(),
      );
  for (final directory in packageDirectories) {
    final name = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (name == 'core' || name == 'shared' || name == 'common') {
      violations.add(
        '${directory.path}: generic package boundary is forbidden',
      );
    }
  }

  final exampleImports = _examplePackageImports();
  for (final root in <Directory>[Directory('apps'), Directory('libs')]) {
    for (final file in _productionFiles(root)) {
      final source = file.readAsStringSync();
      final forbiddenReference = <String>[
        'examples/',
        r'examples\',
        for (final packageName in exampleImports) 'package:$packageName/',
      ].where(source.contains).firstOrNull;
      if (forbiddenReference != null) {
        violations.add(
          '${file.path}: $forbiddenReference '
          '(production code must not depend on reference consumers)',
        );
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Architecture boundary violations:');
    for (final violation in violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
  }
}

bool isForbiddenArchitectureFragment({
  required String root,
  required String filePath,
  required String source,
  required String fragment,
}) {
  if (!source.contains(fragment)) return false;
  if (root != 'apps/studio/lib' ||
      fragment != 'package:experience_engine/' ||
      !p.isWithin(
        p.normalize('apps/studio/lib/src/authoring'),
        p.normalize(filePath),
      )) {
    return true;
  }
  final withoutAllowedImport = source.replaceAll(
    RegExp(
      r"^import 'package:experience_engine/experience_engine\.dart';\s*$",
      multiLine: true,
    ),
    '',
  );
  return withoutAllowedImport.contains(fragment);
}

Set<String> _examplePackageImports() {
  final root = Directory('examples');
  if (!root.existsSync()) return const <String>{};
  final names = <String>{};
  for (final package
      in root.listSync(followLinks: false).whereType<Directory>()) {
    final pubspec = File(p.join(package.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;
    final match = RegExp(
      r'^name:\s*([a-z][a-z0-9_]*)\s*$',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());
    if (match != null) names.add(match.group(1)!);
  }
  return names;
}

Iterable<File> _productionFiles(Directory root) sync* {
  if (!root.existsSync()) return;
  const ignoredSegments = <String>{
    '.dart_tool',
    'build',
    'doc',
    'docs',
    'test',
    'tool',
  };
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: root.path);
    if (p.split(relative).any(ignoredSegments.contains) ||
        !_isProductionTextFile(entity)) {
      continue;
    }
    yield entity;
  }
}

bool _isProductionTextFile(File file) {
  final basename = p.basename(file.path);
  if (const <String>{
    'CHANGELOG',
    'CONTRIBUTING',
    'LICENSE',
    'README',
  }.contains(p.basenameWithoutExtension(file.path).toUpperCase())) {
    return false;
  }
  if (basename == 'Dockerfile') return true;
  return const <String>{
    '.css',
    '.dart',
    '.gradle',
    '.html',
    '.js',
    '.json',
    '.kts',
    '.lock',
    '.properties',
    '.sh',
    '.sql',
    '.toml',
    '.xml',
    '.yaml',
    '.yml',
  }.contains(p.extension(file.path).toLowerCase());
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
