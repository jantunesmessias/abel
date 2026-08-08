import 'dart:convert';
import 'dart:io';

import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late File config;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('devex-config-migrate-');
    addTearDown(() => workspace.deleteSync(recursive: true));
    Directory(p.join(workspace.path, '.devex')).createSync();
    config = File(p.join(workspace.path, 'devex.yaml'))
      ..writeAsStringSync('''
schemaVersion: 1
content: {root: .devex}
workspace: {id: sample, displayName: Sample}
applications:
  app: {root: ., target: local}
''');
  });

  test('dry-run is pure and renders the legacy compatibility profile', () {
    final loaded = const WorkspaceConfigurationLoader().load(
      startPath: workspace.path,
    );
    final before = config.readAsStringSync();

    final report = const ConsumerConfigurationMigrator().migrate(
      configuration: loaded,
      apply: false,
    );

    expect(report.changed, isTrue);
    expect(report.applied, isFalse);
    expect(report.backupPath, isNull);
    expect(report.document['schemaVersion'], 2);
    expect(
      (report.document['kit']! as Map<String, Object?>)['profile'],
      'legacy-full-local-v1',
    );
    expect(config.readAsStringSync(), before);
    expect(File('${config.path}.v1.bak').existsSync(), isFalse);
  });

  test('apply keeps a backup and publishes a loadable v2 document', () {
    final loaded = const WorkspaceConfigurationLoader().load(
      startPath: workspace.path,
    );
    final before = config.readAsStringSync();

    final report = const ConsumerConfigurationMigrator().migrate(
      configuration: loaded,
      apply: true,
    );

    expect(report.applied, isTrue);
    expect(File(report.backupPath!).readAsStringSync(), before);
    expect(jsonDecode(config.readAsStringSync()), report.document);
    final reloaded = const WorkspaceConfigurationLoader().load(
      startPath: workspace.path,
    );
    expect(reloaded.schemaVersion, 2);
    expect(reloaded.kitPlanRequest.profileId, 'legacy-full-local-v1');
  });

  test('already-v2 migration is idempotent', () {
    config.writeAsStringSync('''
schemaVersion: 2
content: {root: .devex}
workspace: {id: sample}
applications: {}
kit: {profile: journey-preview, modules: {}}
''');
    final loaded = const WorkspaceConfigurationLoader().load(
      startPath: workspace.path,
    );

    final report = const ConsumerConfigurationMigrator().migrate(
      configuration: loaded,
      apply: true,
    );

    expect(report.changed, isFalse);
    expect(report.applied, isFalse);
    expect(File('${config.path}.v1.bak').existsSync(), isFalse);
  });
}
