import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory installRoot;
  late LocalDistributionManager manager;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('devex-install-');
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
      expect(_invoke(installRoot, 'devex'), 'first');
      expect(_invoke(installRoot, 'devex-kit'), 'first');

      final updated = await manager.install(second.path);
      expect(updated.healthy, isTrue);
      expect(updated.currentVersion, '0.1.0-preview.2');
      expect(updated.previousVersion, '0.1.0-preview.1');
      expect(_invoke(installRoot, 'devex'), 'second');

      final rolledBack = await manager.rollback();
      expect(rolledBack.healthy, isTrue);
      expect(rolledBack.currentVersion, '0.1.0-preview.1');
      expect(rolledBack.previousVersion, '0.1.0-preview.2');
      expect(_invoke(installRoot, 'devex'), 'first');
      expect(_invoke(installRoot, 'devex-kit'), 'first');
    },
  );

  test('rejects tampered input before changing current install', () async {
    final first = await _bundle(temporary, '0.1.0-preview.1', 'first');
    final second = await _bundle(temporary, '0.1.0-preview.2', 'second');
    await manager.install(first.path);
    File(p.join(second.path, 'bin', 'devex')).writeAsStringSync('tampered');

    await expectLater(manager.install(second.path), throwsFormatException);

    expect((await manager.status()).currentVersion, '0.1.0-preview.1');
    expect(_invoke(installRoot, 'devex'), 'first');
  });

  test('migrates legacy state with dry-run, backup, verify, and undo', () async {
    final first = await _bundle(temporary, '0.1.0-preview.1', 'first');
    final installed = await manager.install(first.path);
    final state = File(p.join(installRoot.path, 'install-state.json'));
    state.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schemaVersion': 0, 'distributionId': 'devex-kit', 'version': installed.currentVersion, 'digest': installed.currentDigest!.value})}\n',
    );

    final preview = await manager.migrateState(apply: false);
    expect(preview.required, isTrue);
    expect(
      (jsonDecode(state.readAsStringSync())
          as Map<String, Object?>)['schemaVersion'],
      0,
    );

    final migrated = await manager.migrateState(apply: true);
    expect(migrated.required, isFalse);
    expect(migrated.backupPresent, isTrue);
    expect((await manager.status()).healthy, isTrue);

    final undone = await manager.rollbackMigration();
    expect(undone.required, isTrue);
    expect(undone.backupPresent, isFalse);
    expect((await manager.status()).migrationRequired, isTrue);
  });

  test(
    'updates from v1 to slim v2 and restores optional launchers on rollback',
    () async {
      final full = await _bundle(temporary, '0.1.0', 'full');
      final slim = await _v2Bundle(temporary, '0.2.0', 'slim');

      expect((await manager.install(full.path)).healthy, isTrue);
      expect(
        Link(p.join(installRoot.path, 'bin', 'backend_gateway')).existsSync(),
        isTrue,
      );

      final updated = await manager.install(slim.path);
      expect(updated.healthy, isTrue);
      expect(_invoke(installRoot, 'devex'), 'slim');
      expect(
        Link(p.join(installRoot.path, 'bin', 'devex_host')).existsSync(),
        isTrue,
      );
      expect(
        Link(p.join(installRoot.path, 'bin', 'backend_gateway')).existsSync(),
        isFalse,
      );

      final rolledBack = await manager.rollback();
      expect(rolledBack.healthy, isTrue);
      expect(_invoke(installRoot, 'devex'), 'full');
      expect(
        Link(p.join(installRoot.path, 'bin', 'backend_gateway')).existsSync(),
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
  for (final name in <String>['devex', 'devex_host', 'backend_gateway']) {
    final file = File(p.join(directory.path, 'bin', name))
      ..writeAsStringSync('#!/bin/sh\nprintf "$label\\n"\n');
    final chmod = Process.runSync('chmod', <String>['755', file.path]);
    if (chmod.exitCode != 0) throw StateError('chmod failed');
  }
  File(
    p.join(directory.path, 'studio', 'index.html'),
  ).writeAsStringSync('<!doctype html><title>$label</title>');
  const bundles = LocalDistributionBundleRepository();
  final manifest = await bundles.createManifest(
    directory: directory.path,
    distribution: DistributionDescriptor(
      id: 'devex-kit',
      displayName: 'DevExKit',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.devexDefault,
      commandAliases: const <String>['devex', 'devex-kit'],
    ),
    releaseVersion: version,
    coreVersion: '0.1.0-dev',
    platform: 'linux-x64',
  );
  bundles.writeDescriptor(directory.path, manifest);
  return directory;
}

Future<Directory> _v2Bundle(
  Directory parent,
  String version,
  String label,
) async {
  final directory = Directory(p.join(parent.path, 'bundle-v2-$version'))
    ..createSync();
  Directory(p.join(directory.path, 'bin')).createSync();
  Directory(p.join(directory.path, 'studio')).createSync();
  Directory(p.join(directory.path, 'modules')).createSync();
  for (final name in <String>['devex', 'devex_host']) {
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
  final manifest = await bundles.createManifestV2(
    directory: directory.path,
    distribution: DistributionDescriptor(
      id: 'devex-kit',
      displayName: 'DevExKit',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.devexDefault,
      commandAliases: const <String>['devex', 'devex-kit'],
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
        path: 'bin/devex',
        moduleIds: const <String>['catalog', 'evidence.auto-preview'],
      ),
      DistributionComponent(
        id: 'host',
        kind: DistributionComponentKind.executable,
        path: 'bin/devex_host',
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
      'cli': 'bin/devex',
      'host': 'bin/devex_host',
      'studio': 'studio/index.html',
    },
    fileModuleIds: const <String, List<String>>{
      'bin/devex': <String>['catalog', 'evidence.auto-preview'],
      'bin/devex_host': <String>['artifact-store.local', 'catalog'],
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
