import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late LoadedWorkspaceCatalog loaded;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync(
      'workspace-gateway-authoring-',
    );
    _writeWorkspace(workspace);
    loaded = const WorkspaceCatalogLoader().load(startPath: workspace.path);
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  test('compiles authoring without writes, then persists lazy CAS handles', () {
    const compiler = WorkspaceGatewayPlanCompiler();
    final observedFixture = File(
      p.join(workspace.path, '.experience', 'fixtures', 'user.body'),
    ).readAsBytesSync();

    final inspected = compiler.compilePreset(loaded, presetId: 'default');

    expect(inspected.planArtifactDigest, isNull);
    expect(inspected.compilation.plan.backendMode, BackendMode.isolated);
    expect(
      inspected.compilation.plan.fixtures.single.bodyDigest,
      Digest.bytes(observedFixture),
    );
    expect(
      Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
      isFalse,
    );

    final persisted = compiler.compilePreset(
      loaded,
      presetId: 'default',
      persist: true,
    );
    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    expect(persisted.planArtifactDigest, isNotNull);
    expect(
      store.readBlob(inspected.compilation.plan.fixtures.single.bodyDigest),
      observedFixture,
    );
    final planBytes = store.readBlob(persisted.planArtifactDigest!)!;
    expect(
      CompiledGatewayPlan.fromJson(jsonDecode(utf8.decode(planBytes))).digest,
      inspected.compilation.plan.digest,
    );
  });

  test('rejects missing presets and fixture traversal', () {
    const compiler = WorkspaceGatewayPlanCompiler();
    expect(
      () => compiler.compilePreset(loaded, presetId: 'missing'),
      throwsFormatException,
    );
    final fixture = File(p.join(workspace.path, '.experience', 'fixture.yaml'));
    fixture.writeAsStringSync(
      fixture.readAsStringSync().replaceFirst(
        'fixtures/user.body',
        '../../../outside.body',
      ),
    );
    loaded = const WorkspaceCatalogLoader().load(startPath: workspace.path);
    expect(
      () => compiler.compilePreset(loaded, presetId: 'default'),
      throwsA(isA<FileSystemException>()),
    );
  });
}

void _writeWorkspace(Directory workspace) {
  final content = Directory(p.join(workspace.path, '.experience'))
    ..createSync();
  Directory(p.join(content.path, 'fixtures')).createSync();
  File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample, displayName: Sample}
applications:
  app: {root: ., target: local}
kit: {profile: full-local, modules: {}}
''');
  File(p.join(content.path, 'scenario.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata: {id: first}
spec: {applicationId: app, title: First}
''');
  File(p.join(content.path, 'journey.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Flow, scenarioIds: [first]}
''');
  File(p.join(content.path, 'scope.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayScope
metadata: {id: accounts}
spec: {displayName: Accounts, routeIds: [get-user]}
''');
  File(p.join(content.path, 'preset.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayPreset
metadata: {id: default}
spec:
  scopeId: accounts
  description: Synthetic account
  routeIds: [get-user]
  initialState: {epoch: 0}
''');
  File(p.join(content.path, 'route.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayRoute
metadata: {id: get-user}
spec:
  scopeId: accounts
  method: GET
  pathTemplate: /users/{id}
  requiredQuery: {view: summary}
  appliesTo: [default]
  policy: localOnly
  fixtureId: user
''');
  File(p.join(content.path, 'fixture.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayFixture
metadata: {id: user}
spec:
  status: 200
  headers: {content-type: application/json}
  bodyFile: fixtures/user.body
  mediaType: application/json
''');
  File(
    p.join(content.path, 'fixtures', 'user.body'),
  ).writeAsStringSync('{"id":"synthetic"}');
}
