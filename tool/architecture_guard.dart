import 'dart:io';

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
      root: 'packages/devex_engine/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:devex_runtime/',
      ],
      reason: 'devex_engine must remain pure Dart and adapter-independent',
    ),
    const ImportRule(
      root: 'packages/devex_flutter/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:devex_engine/',
        'package:devex_runtime/',
      ],
      reason: 'devex_flutter is an app-facing adapter over contracts only',
    ),
    const ImportRule(
      root: 'packages/devex_ux_system/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:devex_engine/',
        'package:devex_runtime/',
      ],
      reason: 'devex_ux_system must remain a pure-Dart interaction policy',
    ),
    const ImportRule(
      root: 'packages/devex_ui_system/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:devex_engine/',
        'package:devex_runtime/',
      ],
      reason: 'devex_ui_system must remain a Jaspr/HTML/CSS renderer',
    ),
    const ImportRule(
      root: 'apps/devex_studio/lib',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:go_router/',
        'package:devex_engine/',
        'package:devex_runtime/',
      ],
      reason:
          'Studio must use the owned UI System and typed Host client without privileged I/O',
    ),
    const ImportRule(
      root: 'apps/devex_studio/lib/src/model',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
        'package:devex_engine/',
        'package:devex_runtime/',
      ],
      reason: 'Studio models must remain renderer-independent pure Dart',
    ),
    const ImportRule(
      root: 'apps/devex_studio/lib/src/controllers',
      forbiddenFragments: <String>[
        "import 'dart:io'",
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
        'package:devex_engine/',
        'package:devex_runtime/',
      ],
      reason: 'Studio controllers must remain renderer-independent pure Dart',
    ),
    const ImportRule(
      root: 'apps/devex_studio/lib/src/journey_map/journey_map_view_data.dart',
      forbiddenFragments: <String>[
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
      ],
      reason: 'Journey projections must remain reusable by the Jaspr renderer',
    ),
    const ImportRule(
      root:
          'apps/devex_studio/lib/src/journey_map/visual_evidence_presentation.dart',
      forbiddenFragments: <String>[
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:jaspr/',
      ],
      reason: 'Evidence presentation policy must remain renderer-independent',
    ),
    const ImportRule(
      root: 'examples/sample_flutter/lib/main.dart',
      forbiddenFragments: <String>['package:devex_'],
      reason: 'the production entrypoint must not import DevExKit tooling',
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
        if (source.contains(fragment)) {
          violations.add('${file.path}: $fragment (${rule.reason})');
        }
      }
    }
  }

  final forbiddenFiles = <String>{
    'apps/devex_studio/lib/main.dart',
    'apps/devex_studio/web/flutter_bootstrap.js',
  };
  for (final path in forbiddenFiles) {
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      violations.add('$path: legacy Flutter Studio artifact is forbidden');
    }
  }

  final packageRules = <String, List<String>>{
    'apps/devex_studio/pubspec.yaml': <String>[
      'sdk: flutter',
      'flutter_riverpod:',
      'flutter_web_plugins:',
      'go_router:',
      'flutter_test:',
      'integration_test:',
    ],
    'packages/devex_ui_system/pubspec.yaml': <String>[
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

  final packageDirectories =
      <Directory>[Directory('apps'), Directory('packages')].expand(
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

  if (violations.isNotEmpty) {
    stderr.writeln('Architecture boundary violations:');
    for (final violation in violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
  }
}
