import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory base;
  late Directory workspace;
  const composer = LocalConsumerDistributionComposer();

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync(
      'workspace-consumer-distribution-',
    );
    base = await _baseBundle(temporary);
    workspace = _consumerWorkspace(temporary);
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test(
    'composes deterministic headless bundle with consumer content and plan',
    () async {
      final first = Directory(p.join(temporary.path, 'consumer-a'));
      final second = Directory(p.join(temporary.path, 'consumer-b'));

      final result = await composer.compose(
        baseBundleDirectory: base.path,
        consumerWorkspaceDirectory: workspace.path,
        specification: _spec('1.0.0'),
        outputDirectory: first.path,
        configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
      );
      final repeated = await composer.compose(
        baseBundleDirectory: base.path,
        consumerWorkspaceDirectory: workspace.path,
        specification: _spec('1.0.0'),
        outputDirectory: second.path,
        configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
      );

      expect(result.release.digest, repeated.release.digest);
      expect(
        File(p.join(first.path, 'distribution.json')).readAsBytesSync(),
        File(p.join(second.path, 'distribution.json')).readAsBytesSync(),
      );
      expect(result.release.distributionId, 'acme-experience');
      expect(result.release.entrypoints.keys, <String>[
        'cli',
        'gateway',
        'host',
      ]);
      expect(Directory(p.join(first.path, 'studio')).existsSync(), isFalse);
      expect(result.inventory.studioAssets, ConsumerStudioAssets.absent);
      expect(
        result.inventory.modules.map((module) => module.id),
        isNot(contains('studio.shell')),
      );
      expect(
        result.inventory.files.map((file) => file.role),
        contains('content'),
      );
      expect(
        File(
          p.join(
            first.path,
            'consumer',
            'workspace',
            '.experience',
            'ready.yaml',
          ),
        ).existsSync(),
        isTrue,
      );

      final catalog = CatalogManifest.fromJson(
        jsonDecode(
          File(
            p.join(first.path, 'consumer', 'catalog.json'),
          ).readAsStringSync(),
        ),
      );
      expect(catalog.distribution.id, 'acme-experience');
      expect(catalog.workspace.id.value, 'acme-workspace');
      expect(catalog.scenarios.single.id.value, 'ready');

      final packagedCatalog = ModuleCatalog.fromJson(
        jsonDecode(
          File(
            p.join(first.path, 'modules', 'module-catalog.json'),
          ).readAsStringSync(),
        ),
      );
      final plan = const ResolvedKitPlanFile().read(
        path: p.join(first.path, result.resolvedPlanPath),
        catalog: packagedCatalog,
        expectedDigest: result.inventory.resolvedPlanDigest,
      );
      expect(plan.profileId, 'gateway-lab-headless');
      expect(
        plan.enabledModules.map((module) => module.moduleId.value),
        contains('gateway.interceptor'),
      );

      final manager = LocalDistributionManager(
        installRoot: p.join(temporary.path, 'install'),
      );
      expect((await manager.install(first.path)).healthy, isTrue);
      expect((await manager.status()).distributionId, 'acme-experience');
    },
  );

  test('updates and rolls back independently composed releases', () async {
    final first = Directory(p.join(temporary.path, 'consumer-1'));
    final second = Directory(p.join(temporary.path, 'consumer-2'));
    await composer.compose(
      baseBundleDirectory: base.path,
      consumerWorkspaceDirectory: workspace.path,
      specification: _spec('1.0.0'),
      outputDirectory: first.path,
      configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
    );
    await composer.compose(
      baseBundleDirectory: base.path,
      consumerWorkspaceDirectory: workspace.path,
      specification: _spec('1.0.1'),
      outputDirectory: second.path,
      configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
    );
    final manager = LocalDistributionManager(
      installRoot: p.join(temporary.path, 'install'),
    );

    await manager.install(first.path);
    expect((await manager.install(second.path)).currentVersion, '1.0.1');
    expect((await manager.rollback()).currentVersion, '1.0.0');
  });

  test(
    'keeps Studio assets only when the resolved profile enables them',
    () async {
      final config = File(p.join(workspace.path, 'workspace.yaml'));
      config.writeAsStringSync(
        config.readAsStringSync().replaceAll(
          'gateway-lab-headless',
          'gateway-lab',
        ),
      );
      final output = Directory(p.join(temporary.path, 'consumer-studio'));
      final result = await composer.compose(
        baseBundleDirectory: base.path,
        consumerWorkspaceDirectory: workspace.path,
        specification: ConsumerDistributionSpec(
          distribution: _distribution(),
          releaseVersion: '1.0.0',
          profileId: 'gateway-lab',
          studioAssets: ConsumerStudioAssets.included,
          compatibility: ConsumerDistributionCompatibility(
            coreCompatibility: '^0.1.0',
          ),
        ),
        outputDirectory: output.path,
        configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
      );

      expect(result.release.entrypoints['studio'], 'studio/index.html');
      expect(
        File(p.join(output.path, 'studio', 'index.html')).existsSync(),
        isTrue,
      );
      expect(
        result.inventory.modules.map((module) => module.id),
        contains('studio.shell'),
      );
    },
  );

  test('fails before output on local overlays and Studio mismatch', () async {
    File(p.join(workspace.path, 'workspace.local.yaml')).writeAsStringSync('''
schemaVersion: 2
kit: {modules: {}}
''');
    final output = Directory(p.join(temporary.path, 'rejected'));

    await expectLater(
      composer.compose(
        baseBundleDirectory: base.path,
        consumerWorkspaceDirectory: workspace.path,
        specification: _spec('1.0.0'),
        outputDirectory: output.path,
        configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
      ),
      throwsFormatException,
    );
    expect(output.existsSync(), isFalse);

    File(p.join(workspace.path, 'workspace.local.yaml')).deleteSync();
    await expectLater(
      composer.compose(
        baseBundleDirectory: base.path,
        consumerWorkspaceDirectory: workspace.path,
        specification: ConsumerDistributionSpec(
          distribution: _distribution(),
          releaseVersion: '1.0.0',
          profileId: 'gateway-lab-headless',
          studioAssets: ConsumerStudioAssets.included,
          compatibility: ConsumerDistributionCompatibility(
            coreCompatibility: '^0.1.0',
          ),
        ),
        outputDirectory: output.path,
        configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
      ),
      throwsFormatException,
    );
    expect(output.existsSync(), isFalse);

    final missingParent = Directory(
      p.join(temporary.path, 'missing-parent', 'rejected'),
    );
    await expectLater(
      composer.compose(
        baseBundleDirectory: base.path,
        consumerWorkspaceDirectory: workspace.path,
        specification: _spec('1.0.0'),
        outputDirectory: missingParent.path,
        configurationSchemas: const BuiltinModuleCatalog().configurationSchemas,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(missingParent.parent.existsSync(), isFalse);
  });
}

Future<Directory> _baseBundle(Directory root) async {
  final directory = Directory(p.join(root.path, 'base'))..createSync();
  Directory(p.join(directory.path, 'bin')).createSync();
  Directory(p.join(directory.path, 'studio')).createSync();
  Directory(p.join(directory.path, 'modules')).createSync();
  for (final name in <String>[
    'workspace',
    'workspace_host',
    'gateway_sidecar',
  ]) {
    final file = File(p.join(directory.path, 'bin', name))
      ..writeAsStringSync('#!/bin/sh\nprintf "$name\\n"\n');
    expect(Process.runSync('chmod', <String>['755', file.path]).exitCode, 0);
  }
  File(
    p.join(directory.path, 'studio', 'index.html'),
  ).writeAsStringSync('<!doctype html><title>Studio</title>');
  const builtins = BuiltinModuleCatalog();
  final catalog = builtins.create(platform: 'linux-x64');
  File(
    p.join(directory.path, 'modules', 'module-catalog.json'),
  ).writeAsStringSync(const JcsCanonicalizer().canonicalize(catalog.toJson()));
  const bundles = LocalDistributionBundleRepository();
  final manifest = await bundles.createManifest(
    directory: directory.path,
    distribution: DistributionDescriptor(
      id: catalog.distributionId,
      displayName: 'Base Distribution',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
      commandAliases: const <String>['workspace'],
    ),
    releaseVersion: '0.1.0',
    coreVersion: '0.1.0',
    platform: 'linux-x64',
    moduleCatalog: catalog,
    profileIds: catalog.profiles.map((profile) => profile.id).toList(),
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
    fileModuleIds: <String, List<String>>{
      'bin/workspace': const <String>['catalog'],
      'bin/workspace_host': const <String>['catalog'],
      'bin/gateway_sidecar': const <String>['gateway.interceptor'],
      'studio/index.html': const <String>['studio.shell'],
      'modules/module-catalog.json': catalog.modules
          .map((module) => module.id.value)
          .toList(),
    },
  );
  bundles.writeDescriptor(directory.path, manifest);
  return directory;
}

Directory _consumerWorkspace(Directory root) {
  final workspace = Directory(p.join(root.path, 'workspace'))..createSync();
  Directory(p.join(workspace.path, '.experience')).createSync();
  File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
distribution: {id: acme-experience}
content: {root: .experience}
workspace: {id: acme-workspace, displayName: Acme Workspace}
applications:
  app: {root: ., target: web, displayName: Acme App}
kit:
  profile: gateway-lab-headless
  modules: {}
  providerBindings: []
  startupPolicy: fail-required-v1
''');
  File(p.join(workspace.path, '.experience', 'ready.yaml')).writeAsStringSync(
    '''
schemaVersion: 1
kind: Scenario
metadata:
  id: ready
spec:
  applicationId: app
  title: Ready
''',
  );
  return workspace;
}

ConsumerDistributionSpec _spec(String version) => ConsumerDistributionSpec(
  distribution: _distribution(),
  releaseVersion: version,
  profileId: 'gateway-lab-headless',
  studioAssets: ConsumerStudioAssets.absent,
  compatibility: ConsumerDistributionCompatibility(coreCompatibility: '^0.1.0'),
);

DistributionDescriptor _distribution() => DistributionDescriptor(
  id: 'acme-experience',
  displayName: 'Acme Experience',
  coreCompatibility: '^0.1.0',
  defaultLayout: ConsumerLayout.standard,
  commandAliases: const <String>['acme-experience'],
);
