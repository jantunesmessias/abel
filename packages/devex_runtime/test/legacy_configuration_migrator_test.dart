import 'dart:convert';
import 'dart:io';

import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late File source;
  late File mapping;
  late LegacyConfigurationMigrator migrator;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('devex-legacy-migration-');
    source = File(p.join(workspace.path, 'legacy.yaml'))
      ..writeAsStringSync('''
workspace:
  id: imported-workspace
  name: Imported Workspace
application:
  id: imported-app
  title: Imported App
''');
    mapping = File(p.join(workspace.path, 'mapping.yaml'))
      ..writeAsStringSync('''
schemaVersion: 1
migrationId: generic-v1
documents:
  - output: workspace.json
    kind: Workspace
    id: {pointer: /workspace/id}
    spec:
      displayName: {pointer: /workspace/name}
  - output: application.json
    kind: Application
    id: {pointer: /application/id}
    spec:
      workspaceId: {pointer: /workspace/id}
      displayName: {pointer: /application/title}
      root: {literal: .}
      target: {literal: local}
''');
    migrator = LegacyConfigurationMigrator(workspaceRoot: workspace.path);
  });

  tearDown(() {
    workspace.deleteSync(recursive: true);
  });

  test('dry-run is pure and apply is atomic, verified and idempotent', () {
    final preview = migrator.migrate(
      sourcePath: source.path,
      mappingPath: mapping.path,
      outputRoot: '.devex/imported',
      apply: false,
    );

    expect(preview.mode, LegacyMigrationMode.dryRun);
    expect(preview.documents.keys, <String>{
      'application.json',
      'workspace.json',
    });
    expect(
      Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
      isFalse,
    );
    expect(Directory(p.join(workspace.path, '.devex')).existsSync(), isFalse);

    final applied = migrator.migrate(
      sourcePath: source.path,
      mappingPath: mapping.path,
      outputRoot: '.devex/imported',
      apply: true,
    );
    expect(applied.verified, isTrue);
    expect(migrator.verify(outputRoot: '.devex/imported').verified, isTrue);
    var retentionNow = DateTime.utc(2026, 8, 1);
    final retention = LocalRetentionService(
      workspaceRoot: workspace.path,
      nowUtc: () => retentionNow,
    );
    retention.run(apply: true);
    retentionNow = retentionNow.add(const Duration(days: 2));
    retention.run(apply: true);
    expect(
      migrator.verify(outputRoot: '.devex/imported').verified,
      isTrue,
      reason: 'active migration backups are retention roots',
    );
    expect(
      migrator
          .migrate(
            sourcePath: source.path,
            mappingPath: mapping.path,
            outputRoot: '.devex/imported',
            apply: true,
          )
          .changed,
      isFalse,
    );
    final parser = const SafeAuthoringParser();
    final imported = parser.parse(
      File(
        p.join(workspace.path, '.devex', 'imported', 'application.json'),
      ).readAsStringSync(),
      sourceName: 'application.json',
    );
    expect(imported.kind, AuthoringKind.application);
    expect(imported.id, 'imported-app');
  });

  test(
    'rollback refuses modifications then moves exact output to quarantine',
    () {
      migrator.migrate(
        sourcePath: source.path,
        mappingPath: mapping.path,
        outputRoot: '.devex/imported',
        apply: true,
      );
      final application = File(
        p.join(workspace.path, '.devex', 'imported', 'application.json'),
      );
      final original = application.readAsBytesSync();
      application.writeAsStringSync('{"modified":true}\n');

      expect(
        () => migrator.rollback(outputRoot: '.devex/imported', apply: true),
        throwsStateError,
      );
      expect(application.existsSync(), isTrue);

      application.writeAsBytesSync(original);
      final preview = migrator.rollback(
        outputRoot: '.devex/imported',
        apply: false,
      );
      expect(preview.mode, LegacyMigrationMode.dryRun);
      final rolledBack = migrator.rollback(
        outputRoot: '.devex/imported',
        apply: true,
      );
      expect(rolledBack.verified, isTrue);
      expect(
        Directory(p.join(workspace.path, '.devex', 'imported')).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          p.join(workspace.path, rolledBack.quarantinePath!),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('mapping output traversal fails before any write', () {
    final invalid = File(p.join(workspace.path, 'invalid-mapping.json'))
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'migrationId': 'invalid',
          'documents': <Object?>[
            <String, Object?>{
              'output': '../escape.json',
              'kind': 'Workspace',
              'id': <String, Object?>{'literal': 'workspace'},
              'spec': <String, Object?>{
                'displayName': <String, Object?>{'literal': 'Workspace'},
              },
            },
          ],
        }),
      );

    expect(
      () => migrator.migrate(
        sourcePath: source.path,
        mappingPath: invalid.path,
        outputRoot: '.devex/imported',
        apply: true,
      ),
      throwsFormatException,
    );
    expect(
      File(p.join(workspace.parent.path, 'escape.json')).existsSync(),
      isFalse,
    );
  });
}
