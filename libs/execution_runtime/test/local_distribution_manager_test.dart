import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory installRoot;
  late LocalDistributionManager manager;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('workspace-install-');
    installRoot = Directory(p.join(temporary.path, 'installation'));
    manager = LocalDistributionManager(installRoot: installRoot.path);
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'installs, updates, aliases, and rolls back verified releases',
    () async {
      final first = await _bundle(temporary, '0.1.0-preview.1', 'first');
      final second = await _bundle(temporary, '0.1.0-preview.2', 'second');

      final installed = await manager.install(first.path);
      expect(installed.healthy, isTrue);
      expect(installed.currentVersion, '0.1.0-preview.1');
      expect(_invoke(installRoot, 'workspace'), 'first');

      final updated = await manager.install(second.path);
      expect(updated.healthy, isTrue);
      expect(updated.currentVersion, '0.1.0-preview.2');
      expect(updated.previousVersion, '0.1.0-preview.1');
      expect(_invoke(installRoot, 'workspace'), 'second');

      final rolledBack = await manager.rollback();
      expect(rolledBack.healthy, isTrue);
      expect(rolledBack.currentVersion, '0.1.0-preview.1');
      expect(rolledBack.previousVersion, '0.1.0-preview.2');
      expect(_invoke(installRoot, 'workspace'), 'first');
    },
  );

  test('rejects tampered input before changing current install', () async {
    final first = await _bundle(temporary, '0.1.0-preview.1', 'first');
    final second = await _bundle(temporary, '0.1.0-preview.2', 'second');
    await manager.install(first.path);
    File(p.join(second.path, 'bin', 'workspace')).writeAsStringSync('tampered');

    await expectLater(manager.install(second.path), throwsFormatException);

    expect((await manager.status()).currentVersion, '0.1.0-preview.1');
    expect(_invoke(installRoot, 'workspace'), 'first');
  });

  test('rejects unpublished install state schemas', () async {
    final first = await _bundle(temporary, '0.1.0-preview.1', 'first');
    final installed = await manager.install(first.path);
    final state = File(p.join(installRoot.path, 'install-state.json'));
    state.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 0, 'distributionId': 'full-local', 'version': installed.currentVersion, 'digest': installed.currentDigest!.value})}\n',
    );

    await expectLater(manager.status(), throwsFormatException);
    await expectLater(manager.install(first.path), throwsFormatException);
    expect(
      (jsonDecode(state.readAsStringSync())
          as Map<String, Object?>)['schemaVersion'],
      0,
    );
  });

  test(
    'updates from complete to slim and restores optional launchers on rollback',
    () async {
      final full = await _bundle(temporary, '0.1.0', 'full');
      final slim = await _slimBundle(temporary, '0.2.0', 'slim');

      expect((await manager.install(full.path)).healthy, isTrue);
      expect(
        Link(p.join(installRoot.path, 'bin', 'gateway_sidecar')).existsSync(),
        isTrue,
      );

      final updated = await manager.install(slim.path);
      expect(updated.healthy, isTrue);
      expect(_invoke(installRoot, 'workspace'), 'slim');
      expect(
        Link(p.join(installRoot.path, 'bin', 'workspace_host')).existsSync(),
        isTrue,
      );
      expect(
        Link(p.join(installRoot.path, 'bin', 'gateway_sidecar')).existsSync(),
        isFalse,
      );

      final rolledBack = await manager.rollback();
      expect(rolledBack.healthy, isTrue);
      expect(_invoke(installRoot, 'workspace'), 'full');
      expect(
        Link(p.join(installRoot.path, 'bin', 'gateway_sidecar')).existsSync(),
        isTrue,
      );
    },
  );
}

Future<Directory> _bundle(
  Directory parent,
  String version,
  String label,
) async {
  final directory = Directory(p.join(parent.path, 'bundle-$version'))
    ..createSync();
  Directory(p.join(directory.path, 'bin')).createSync();
  Directory(p.join(directory.path, 'studio')).createSync();
  Directory(p.join(directory.path, 'modules')).createSync();
  for (final name in <String>[
    'workspace',
    'workspace_host',
    'gateway_sidecar',
  ]) {
    final file = File(p.join(directory.path, 'bin', name))
      ..writeAsStringSync('#!/bin/sh\nprintf "$label\\n"\n');
    final chmod = Process.runSync('chmod', <String>['755', file.path]);
    if (chmod.exitCode != 0) throw StateError('chmod failed');
  }
  File(
    p.join(directory.path, 'studio', 'index.html'),
  ).writeAsStringSync('<!doctype html><title>$label</title>');
  const builtins = BuiltinModuleCatalog();
  final catalog = builtins.create(platform: 'linux-x64');
  File(
    p.join(directory.path, 'modules', 'module-catalog.json'),
  ).writeAsStringSync(
    const JcsCanonicalizer().canonicalize(catalog.toJson()),
    flush: true,
  );
  const bundles = LocalDistributionBundleRepository();
  final manifest = await bundles.createManifest(
    directory: directory.path,
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
      commandAliases: const <String>['workspace'],
    ),
    releaseVersion: version,
    coreVersion: '0.1.0-dev',
    platform: 'linux-x64',
    moduleCatalog: catalog,
    profileIds: const <String>['full-local'],
    components: <DistributionComponent>[
      DistributionComponent(
        id: 'cli',
        kind: DistributionComponentKind.executable,
        path: 'bin/workspace',
        moduleIds: const <String>['catalog'],
      ),
      DistributionComponent(
        id: 'host',
        kind: DistributionComponentKind.executable,
        path: 'bin/workspace_host',
        moduleIds: const <String>['catalog'],
      ),
      DistributionComponent(
        id: 'gateway',
        kind: DistributionComponentKind.executable,
        path: 'bin/gateway_sidecar',
        moduleIds: const <String>['gateway.interceptor'],
      ),
      DistributionComponent(
        id: 'studio',
        kind: DistributionComponentKind.webAssets,
        path: 'studio/index.html',
        moduleIds: const <String>['studio.shell'],
      ),
    ],
    entrypoints: const <String, String>{
      'cli': 'bin/workspace',
      'host': 'bin/workspace_host',
      'gateway': 'bin/gateway_sidecar',
      'studio': 'studio/index.html',
    },
    fileModuleIds: const <String, List<String>>{
      'bin/workspace': <String>['catalog'],
      'bin/workspace_host': <String>['catalog'],
      'bin/gateway_sidecar': <String>['gateway.interceptor'],
      'studio/index.html': <String>['studio.shell'],
      'modules/module-catalog.json': <String>['catalog'],
    },
  );
  bundles.writeDescriptor(directory.path, manifest);
  return directory;
}

Future<Directory> _slimBundle(
  Directory parent,
  String version,
  String label,
) async {
  final directory = Directory(p.join(parent.path, 'bundle-slim-$version'))
    ..createSync();
  Directory(p.join(directory.path, 'bin')).createSync();
  Directory(p.join(directory.path, 'studio')).createSync();
  Directory(p.join(directory.path, 'modules')).createSync();
  for (final name in <String>['workspace', 'workspace_host']) {
    final file = File(p.join(directory.path, 'bin', name))
      ..writeAsStringSync('#!/bin/sh\nprintf "$label\\n"\n');
    final chmod = Process.runSync('chmod', <String>['755', file.path]);
    if (chmod.exitCode != 0) throw StateError('chmod failed');
  }
  File(
    p.join(directory.path, 'studio', 'index.html'),
  ).writeAsStringSync('<!doctype html><title>$label</title>');
  const builtins = BuiltinModuleCatalog();
  final complete = builtins.create(platform: 'linux-x64');
  final profile = complete.profiles.singleWhere(
    (item) => item.id == 'journey-preview',
  );
  final enabledIds = profile.selection.modules
      .where((module) => module.enabled)
      .map((module) => module.moduleId)
      .toSet();
  final catalog = ModuleCatalog(
    distributionId: complete.distributionId,
    coreVersion: complete.coreVersion,
    platform: complete.platform,
    modules: complete.modules
        .where((module) => enabledIds.contains(module.id))
        .toList(growable: false),
    profiles: <KitProfile>[profile],
    defaultProfileId: profile.id,
  );
  final catalogFile =
      File(p.join(directory.path, 'modules', 'module-catalog.json'))
        ..writeAsStringSync(
          const JcsCanonicalizer().canonicalize(catalog.toJson()),
          flush: true,
        );
  expect(
    ModuleCatalog.fromJson(jsonDecode(catalogFile.readAsStringSync())).digest,
    catalog.digest,
  );
  const bundles = LocalDistributionBundleRepository();
  final manifest = await bundles.createManifest(
    directory: directory.path,
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
      commandAliases: const <String>['workspace'],
    ),
    releaseVersion: version,
    coreVersion: '0.1.0-dev',
    platform: 'linux-x64',
    moduleCatalog: catalog,
    profileIds: const <String>['journey-preview'],
    components: <DistributionComponent>[
      DistributionComponent(
        id: 'cli',
        kind: DistributionComponentKind.executable,
        path: 'bin/workspace',
        moduleIds: const <String>['catalog', 'evidence.auto-preview'],
      ),
      DistributionComponent(
        id: 'host',
        kind: DistributionComponentKind.executable,
        path: 'bin/workspace_host',
        moduleIds: const <String>['artifact-store.local', 'catalog'],
      ),
      DistributionComponent(
        id: 'studio',
        kind: DistributionComponentKind.webAssets,
        path: 'studio/index.html',
        moduleIds: const <String>['studio.journey-map', 'studio.shell'],
      ),
    ],
    entrypoints: const <String, String>{
      'cli': 'bin/workspace',
      'host': 'bin/workspace_host',
      'studio': 'studio/index.html',
    },
    fileModuleIds: const <String, List<String>>{
      'bin/workspace': <String>['catalog', 'evidence.auto-preview'],
      'bin/workspace_host': <String>['artifact-store.local', 'catalog'],
      'modules/module-catalog.json': <String>['catalog'],
      'studio/index.html': <String>['studio.journey-map', 'studio.shell'],
    },
  );
  bundles.writeDescriptor(directory.path, manifest);
  return directory;
}

String _invoke(Directory root, String command) {
  final result = Process.runSync(p.join(root.path, 'bin', command), const []);
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return '${result.stdout}'.trim();
}
