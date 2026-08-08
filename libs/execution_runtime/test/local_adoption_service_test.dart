import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late LocalAdoptionService service;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('workspace-adoption-');
    File(
      p.join(workspace.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: consumer\n');
    File(
      p.join(workspace.path, 'pubspec.lock'),
    ).writeAsStringSync('packages: {}\n');
    service = LocalAdoptionService(workspaceRoot: workspace.path);
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  test('dry-run is side-effect free and detach preserves modified files', () {
    final pubspecBefore = File(
      p.join(workspace.path, 'pubspec.yaml'),
    ).readAsBytesSync();
    final lockBefore = File(
      p.join(workspace.path, 'pubspec.lock'),
    ).readAsBytesSync();

    final plan = service.planInit(workspaceId: 'sample', displayName: 'Sample');
    expect(plan.canApply, isTrue);
    expect(
      Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
      isFalse,
    );

    final applied = service.applyInit(
      workspaceId: 'sample',
      displayName: 'Sample',
    );
    expect(applied.adopted, isTrue);
    expect(
      applied.files.map((file) => file.state),
      everyElement(AdoptionFileState.ownedUnmodified),
    );
    expect(
      File(p.join(workspace.path, 'pubspec.yaml')).readAsBytesSync(),
      pubspecBefore,
    );
    expect(
      File(p.join(workspace.path, 'pubspec.lock')).readAsBytesSync(),
      lockBefore,
    );

    final scenario = File(
      p.join(workspace.path, '.experience', 'scenario.yaml'),
    )..writeAsStringSync('\n# consumer edit\n', mode: FileMode.append);
    final preview = service.detach(apply: false);
    expect(preview.files, hasLength(4));
    expect(scenario.existsSync(), isTrue);

    final partial = service.detach(apply: true);
    expect(partial.adopted, isTrue);
    expect(partial.files, hasLength(1));
    expect(partial.files.single.state, AdoptionFileState.modified);
    expect(scenario.existsSync(), isTrue);
    expect(
      File(p.join(workspace.path, 'workspace.yaml')).existsSync(),
      isFalse,
    );

    scenario.deleteSync();
    final detached = service.detach(apply: true);
    expect(detached.adopted, isFalse);
    expect(
      Directory(p.join(workspace.path, '.experience')).existsSync(),
      isFalse,
    );
    expect(
      Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
      isFalse,
    );
  });

  test('pre-existing files block apply without overwrite', () {
    final config = File(p.join(workspace.path, 'workspace.yaml'))
      ..writeAsStringSync('consumer-owned\n');

    final plan = service.planInit();

    expect(plan.canApply, isFalse);
    expect(
      plan.files.singleWhere((file) => file.path == 'workspace.yaml').state,
      AdoptionFileState.preexisting,
    );
    expect(() => service.applyInit(), throwsStateError);
    expect(config.readAsStringSync(), 'consumer-owned\n');
  });

  test('symlinked content roots fail before writing outside workspace', () {
    final outside = Directory.systemTemp.createTempSync('workspace-outside-');
    addTearDown(() => outside.deleteSync(recursive: true));
    Link(p.join(workspace.path, '.experience')).createSync(outside.path);

    expect(() => service.planInit(), throwsA(isA<FileSystemException>()));
    expect(outside.listSync(), isEmpty);
  });
}
