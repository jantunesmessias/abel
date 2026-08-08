import 'dart:io';

import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() => temporary = Directory.systemTemp.createTempSync('devex-loader-'));
  tearDown(() => temporary.deleteSync(recursive: true));

  test('loads default layout without writing during the query', () {
    Directory(
      p.join(temporary.path, '.devex', 'journeys'),
    ).createSync(recursive: true);
    File(p.join(temporary.path, 'devex.yaml')).writeAsStringSync(_config());
    File(
      p.join(temporary.path, '.devex', 'journeys', 'flow.yaml'),
    ).writeAsStringSync(_journey());
    File(
      p.join(temporary.path, '.devex', 'journeys', 'first.yaml'),
    ).writeAsStringSync(_scenario('first'));
    final before = _tree(temporary);

    final loaded = const WorkspaceCatalogLoader().load(
      startPath: temporary.path,
    );
    final manifest = const CatalogCompiler().compile(
      loaded.documents,
      layout: loaded.layout,
    );

    expect(manifest.workspace.id.value, 'sample');
    expect(manifest.journeys, hasLength(1));
    expect(_tree(temporary), before);
  });

  test('supports monorepo applications and an explicit custom layout', () {
    Directory(
      p.join(temporary.path, 'catalog', 'docs'),
    ).createSync(recursive: true);
    File(p.join(temporary.path, 'catalog', 'custom.yaml')).writeAsStringSync(
      _config(
        contentRoot: 'docs',
        applications: const <String>['primary', 'companion'],
      ),
    );
    File(
      p.join(temporary.path, 'catalog', 'docs', 'flow.json'),
    ).writeAsStringSync(
      '{"schemaVersion":1,"kind":"Journey","metadata":{"id":"flow"},"spec":{"applicationId":"primary","title":"Flow","scenarioIds":["first"]}}',
    );
    File(
      p.join(temporary.path, 'catalog', 'docs', 'first.yaml'),
    ).writeAsStringSync(_scenario('first', applicationId: 'primary'));

    final loaded = const WorkspaceCatalogLoader().load(
      startPath: temporary.path,
      explicitConfigPath: 'catalog/custom.yaml',
    );
    final manifest = const CatalogCompiler().compile(
      loaded.documents,
      layout: loaded.layout,
    );

    expect(manifest.applications.map((value) => value.id.value), <String>[
      'companion',
      'primary',
    ]);
    expect(loaded.layout.contentRoot, 'docs');
  });

  test('uses explicit config before DEVEX_CONFIG before discovery', () {
    Directory(p.join(temporary.path, 'default')).createSync();
    Directory(p.join(temporary.path, 'environment')).createSync();
    Directory(p.join(temporary.path, 'explicit')).createSync();
    File(
      p.join(temporary.path, 'devex.yaml'),
    ).writeAsStringSync(_config(contentRoot: 'default'));
    File(
      p.join(temporary.path, 'environment.yaml'),
    ).writeAsStringSync(_config(contentRoot: 'environment'));
    File(
      p.join(temporary.path, 'explicit.yaml'),
    ).writeAsStringSync(_config(contentRoot: 'explicit'));
    const loader = WorkspaceCatalogLoader();

    final fromEnvironment = loader.load(
      startPath: temporary.path,
      environment: const <String, String>{'DEVEX_CONFIG': 'environment.yaml'},
    );
    final fromExplicit = loader.load(
      startPath: temporary.path,
      explicitConfigPath: 'explicit.yaml',
      environment: const <String, String>{'DEVEX_CONFIG': 'environment.yaml'},
    );

    expect(p.basename(fromEnvironment.configPath), 'environment.yaml');
    expect(p.basename(fromExplicit.configPath), 'explicit.yaml');
  });

  test('rejects links in the authoring content root', () {
    final content = Directory(p.join(temporary.path, '.devex'))..createSync();
    final outside = File(p.join(temporary.path, 'outside.yaml'))
      ..writeAsStringSync(_scenario('first'));
    Link(p.join(content.path, 'linked.yaml')).createSync(outside.path);
    File(p.join(temporary.path, 'devex.yaml')).writeAsStringSync(_config());

    expect(
      () => const WorkspaceCatalogLoader().load(startPath: temporary.path),
      throwsA(isA<FileSystemException>()),
    );
  });
}

String _config({
  String contentRoot = '.devex',
  List<String> applications = const <String>['app'],
}) =>
    '''
schemaVersion: 1
content:
  root: $contentRoot
workspace:
  id: sample
  displayName: Sample
applications:
${applications.map((id) => '  $id:\n    root: apps/$id\n    target: local').join('\n')}
''';

String _scenario(String id, {String applicationId = 'app'}) =>
    '''
schemaVersion: 1
kind: Scenario
metadata: {id: $id}
spec:
  applicationId: $applicationId
  title: Scenario $id
''';

String _journey() => '''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec:
  applicationId: app
  title: Flow
  scenarioIds: [first]
''';

List<String> _tree(Directory root) =>
    root
        .listSync(recursive: true, followLinks: false)
        .map((entity) => p.relative(entity.path, from: root.path))
        .toList()
      ..sort();
