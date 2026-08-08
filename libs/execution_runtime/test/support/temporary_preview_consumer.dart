import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

final class TemporaryPreviewConsumer {
  TemporaryPreviewConsumer._({required this.root, required this.previewSource});

  static TemporaryPreviewConsumer create() {
    final repository = _repositoryRoot();
    final root = Directory.systemTemp.createTempSync(
      'workspace-preview-consumer-',
    );
    final lib = Directory(p.join(root.path, 'lib'))..createSync();
    final pubspec = File(p.join(root.path, 'pubspec.yaml'))
      ..writeAsStringSync('''
name: preview_test_consumer
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  flutter_preview: ^0.1.0-dev
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
''');
    final previewSource = File(p.join(lib.path, 'previews.dart'))
      ..writeAsStringSync(_validPreviewSource);
    _writeSanitizedPackageMetadata(repository: repository, consumerRoot: root);
    if (!pubspec.existsSync()) {
      throw StateError('Temporary consumer pubspec was not created');
    }
    return TemporaryPreviewConsumer._(root: root, previewSource: previewSource);
  }

  final Directory root;
  final File previewSource;

  String get packageConfigPath =>
      p.join(root.path, '.dart_tool', 'package_config.json');

  CatalogManifest catalog() {
    final layout = ConsumerLayout.standard;
    final workspaceId = WorkspaceId('preview-fixture');
    final applicationId = ApplicationId('fixture-app');
    final scenarioIds = <ScenarioId>[
      ScenarioId('dashboard-loading'),
      ScenarioId('dashboard-ready'),
      ScenarioId('toggle-delivery-task'),
      ScenarioId('dashboard-failed'),
      ScenarioId('inspect-gateway-traffic'),
    ];
    return CatalogManifest(
      distribution: DistributionDescriptor(
        id: 'full-local',
        displayName: 'Abel',
        coreCompatibility: '^0.1.0',
        defaultLayout: layout,
      ),
      layout: layout,
      workspace: Workspace(
        id: workspaceId,
        displayName: 'Temporary preview fixture',
      ),
      applications: <Application>[
        Application(
          id: applicationId,
          workspaceId: workspaceId,
          displayName: 'Fixture application',
          root: '.',
          target: 'flutter',
        ),
      ],
      journeys: <Journey>[
        Journey(
          id: JourneyId('fixture-journey'),
          applicationId: applicationId,
          title: 'Fixture journey',
          scenarioIds: scenarioIds,
        ),
      ],
      scenarios: <Scenario>[
        for (final scenarioId in scenarioIds)
          Scenario(
            id: scenarioId,
            applicationId: applicationId,
            title: scenarioId.value,
          ),
      ],
      transitions: const <Transition>[],
    );
  }

  File writeLibrary(String name, String source) {
    final target = File(p.join(root.path, 'lib', name));
    if (!p.isWithin(p.join(root.path, 'lib'), target.path)) {
      throw ArgumentError.value(name, 'name');
    }
    target.writeAsStringSync(source);
    return target;
  }

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

void _writeSanitizedPackageMetadata({
  required Directory repository,
  required Directory consumerRoot,
}) {
  final sourceFile = File(
    p.join(repository.path, '.dart_tool', 'package_config.json'),
  );
  if (!sourceFile.existsSync()) {
    throw StateError('Run flutter pub get before executing runtime tests');
  }
  final decoded = jsonDecode(sourceFile.readAsStringSync());
  if (decoded is! Map<String, Object?> ||
      decoded['packages'] is! List<Object?>) {
    throw const FormatException('Workspace package_config.json is invalid');
  }
  final sourceBase = sourceFile.parent.uri;
  final examplesRoot = p.join(repository.path, 'examples');
  final packages = <Map<String, Object?>>[];
  for (final raw in decoded['packages']! as List<Object?>) {
    if (raw is! Map<String, Object?> || raw['rootUri'] is! String) {
      throw const FormatException('Workspace package entry is invalid');
    }
    final absoluteRoot = sourceBase.resolve(raw['rootUri']! as String);
    if (absoluteRoot.scheme == 'file' &&
        (p.equals(File.fromUri(absoluteRoot).path, examplesRoot) ||
            p.isWithin(examplesRoot, File.fromUri(absoluteRoot).path))) {
      continue;
    }
    packages.add(<String, Object?>{...raw, 'rootUri': absoluteRoot.toString()});
  }
  packages.removeWhere((entry) => entry['name'] == 'preview_test_consumer');
  packages.add(<String, Object?>{
    'name': 'preview_test_consumer',
    'rootUri': consumerRoot.uri.toString(),
    'packageUri': 'lib/',
    'languageVersion': '3.12',
  });
  final output = <String, Object?>{...decoded, 'packages': packages};
  final target = File(
    p.join(consumerRoot.path, '.dart_tool', 'package_config.json'),
  )..parent.createSync(recursive: true);
  target.writeAsStringSync('${jsonEncode(output)}\n', flush: true);

  final includedNames = packages
      .map((entry) => entry['name'])
      .whereType<String>()
      .toSet();
  final graphFile = File(
    p.join(repository.path, '.dart_tool', 'package_graph.json'),
  );
  final sourceGraph = jsonDecode(graphFile.readAsStringSync());
  if (sourceGraph is! Map<String, Object?> ||
      sourceGraph['packages'] is! List<Object?>) {
    throw const FormatException('Workspace package_graph.json is invalid');
  }
  final graphPackages = <Object?>[
    for (final raw in sourceGraph['packages']! as List<Object?>)
      if (raw is Map<String, Object?> && includedNames.contains(raw['name']))
        raw,
    const <String, Object?>{
      'name': 'preview_test_consumer',
      'version': '0.0.0',
      'dependencies': <String>['flutter_preview', 'flutter'],
      'devDependencies': <String>['flutter_test'],
    },
  ];
  File(
    p.join(consumerRoot.path, '.dart_tool', 'package_graph.json'),
  ).writeAsStringSync(
    '${jsonEncode(<String, Object?>{
      'roots': <String>['preview_test_consumer'],
      'packages': graphPackages,
      'configVersion': sourceGraph['configVersion'] ?? 1,
    })}\n',
    flush: true,
  );
  final flutterVersion = decoded['flutterVersion'];
  if (flutterVersion is String) {
    File(
      p.join(consumerRoot.path, '.dart_tool', 'version'),
    ).writeAsStringSync(flutterVersion, flush: true);
  }
}

Directory _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current;
    }
    if (current.parent.path == current.path) {
      throw StateError('Abel repository root not found');
    }
    current = current.parent;
  }
}

const String _validPreviewSource = r'''
import 'package:flutter_preview/flutter_preview.dart';
import 'package:flutter/material.dart';

@AutoPreview(
  id: 'fixture.dashboard.loading',
  scenarioId: 'dashboard-loading',
  variantId: 'phone.light.en-us',
  size: Size(390, 844),
  devicePixelRatio: 3,
  localeTag: 'en-US',
  brightness: Brightness.light,
)
Widget dashboardLoadingPreview() => const _FixtureApp(label: 'Loading');

@AutoMultiPreview(
  id: 'fixture.dashboard.ready',
  scenarioId: 'dashboard-ready',
  variants: <AutoPreviewVariant>[
    AutoPreviewVariant(
      variantId: 'phone.light.en-us',
      size: Size(390, 844),
      devicePixelRatio: 3,
      localeTag: 'en-US',
      brightness: Brightness.light,
    ),
    AutoPreviewVariant(
      variantId: 'phone.dark.en-us',
      size: Size(390, 844),
      devicePixelRatio: 3,
      localeTag: 'en-US',
      brightness: Brightness.dark,
    ),
    AutoPreviewVariant(
      variantId: 'desktop.light.en-us',
      size: Size(1280, 900),
      localeTag: 'en-US',
      brightness: Brightness.light,
    ),
  ],
)
Widget dashboardReadyPreviews() => const _FixtureApp(label: 'Ready');

@AutoPreview(
  id: 'fixture.dashboard.task-toggled',
  scenarioId: 'toggle-delivery-task',
  variantId: 'phone.light.en-us',
  size: Size(390, 844),
  devicePixelRatio: 3,
  localeTag: 'en-US',
  brightness: Brightness.light,
)
Widget dashboardTaskToggledPreview() => const _FixtureApp(label: 'Toggled');

@AutoPreview(
  id: 'fixture.dashboard.gateway-traffic',
  scenarioId: 'inspect-gateway-traffic',
  variantId: 'desktop.light.en-us',
  size: Size(1280, 900),
  localeTag: 'en-US',
  brightness: Brightness.light,
)
Widget dashboardGatewayTrafficPreview() => const _FixtureApp(label: 'Traffic');

@AutoPreview(
  id: 'fixture.dashboard.failed',
  scenarioId: 'dashboard-failed',
  variantId: 'phone.light.en-us',
  size: Size(390, 844),
  devicePixelRatio: 3,
  localeTag: 'en-US',
  brightness: Brightness.light,
)
Widget dashboardFailedPreview() => const _FixtureApp(label: 'Failed');

final class _FixtureApp extends StatelessWidget {
  const _FixtureApp({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(body: Center(child: Text(label))),
      );
}
''';

const String invalidPreviewSource = r'''
import 'package:flutter_preview/flutter_preview.dart';
import 'package:flutter/material.dart';

const dynamic runtimeId = String.fromEnvironment('PREVIEW_ID');

@AutoPreview(
  id: 'private.preview',
  scenarioId: 'launch-sample',
  variantId: 'phone',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
)
Widget _privatePreview() => const SizedBox();

@AutoPreview(
  id: 'invalid.return',
  scenarioId: 'launch-sample',
  variantId: 'phone',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
)
int invalidReturn() => 1;

@AutoPreview(
  id: runtimeId,
  scenarioId: 'launch-sample',
  variantId: 'phone',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
)
Widget nonConstPreview() => const SizedBox();

@AutoMultiPreview(
  id: 'empty.preview',
  scenarioId: 'launch-sample',
  variants: <AutoPreviewVariant>[],
)
Widget emptyPreview() => const SizedBox();
''';
