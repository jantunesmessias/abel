import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory bundle;
  const repository = LocalDistributionBundleRepository();

  setUp(() {
    bundle = Directory.systemTemp.createTempSync('workspace-distribution-');
    Directory(p.join(bundle.path, 'bin')).createSync();
    Directory(p.join(bundle.path, 'studio')).createSync();
    Directory(p.join(bundle.path, 'modules')).createSync();
    for (final path in <String>[
      'bin/workspace',
      'bin/workspace_host',
      'bin/gateway_sidecar',
    ]) {
      final file = File(p.join(bundle.path, path))..writeAsStringSync(path);
      final chmod = Process.runSync('chmod', <String>['755', file.path]);
      if (chmod.exitCode != 0) throw StateError('chmod failed');
    }
    File(
      p.join(bundle.path, 'studio', 'index.html'),
    ).writeAsStringSync('<!doctype html>');
    File(
      p.join(bundle.path, 'modules', 'module-catalog.json'),
    ).writeAsStringSync(
      const JcsCanonicalizer().canonicalize(_catalog().toJson()),
    );
  });

  tearDown(() => bundle.deleteSync(recursive: true));

  test('creates and verifies a closed byte inventory', () async {
    final manifest = await repository.createManifest(
      directory: bundle.path,
      distribution: _descriptor(),
      releaseVersion: '0.1.0-preview.1',
      coreVersion: '0.1.0-dev',
      platform: 'linux-x64',
      moduleCatalog: _catalog(),
      profileIds: const <String>['full-local'],
      components: _components(),
      entrypoints: _entrypoints,
      fileModuleIds: _fileModuleIds,
    );
    repository.writeDescriptor(bundle.path, manifest);

    final verified = await repository.verify(bundle.path);

    expect(verified.digest, manifest.digest);
    expect(verified.files, hasLength(5));
  });

  test('rejects tampering, extras, and links', () async {
    final manifest = await repository.createManifest(
      directory: bundle.path,
      distribution: _descriptor(),
      releaseVersion: '0.1.0-preview.1',
      coreVersion: '0.1.0-dev',
      platform: 'linux-x64',
      moduleCatalog: _catalog(),
      profileIds: const <String>['full-local'],
      components: _components(),
      entrypoints: _entrypoints,
      fileModuleIds: _fileModuleIds,
    );
    repository.writeDescriptor(bundle.path, manifest);
    File(p.join(bundle.path, 'studio', 'index.html')).writeAsStringSync('bad');
    await expectLater(repository.verify(bundle.path), throwsFormatException);

    File(
      p.join(bundle.path, 'studio', 'index.html'),
    ).writeAsStringSync('<!doctype html>');
    File(p.join(bundle.path, 'extra')).writeAsStringSync('extra');
    await expectLater(repository.verify(bundle.path), throwsFormatException);
    File(p.join(bundle.path, 'extra')).deleteSync();
    Link(p.join(bundle.path, 'linked')).createSync('/tmp');
    await expectLater(
      repository.verify(bundle.path),
      throwsA(isA<FileSystemException>()),
    );
  });
}

DistributionDescriptor _descriptor() => DistributionDescriptor(
  id: 'full-local',
  displayName: 'Abel',
  coreCompatibility: '^0.1.0',
  defaultLayout: ConsumerLayout.standard,
  commandAliases: const <String>['workspace'],
);

ModuleCatalog _catalog() =>
    const BuiltinModuleCatalog().create(platform: 'linux-x64');

const Map<String, String> _entrypoints = <String, String>{
  'cli': 'bin/workspace',
  'host': 'bin/workspace_host',
  'gateway': 'bin/gateway_sidecar',
  'studio': 'studio/index.html',
};

List<DistributionComponent> _components() => <DistributionComponent>[
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
];

const Map<String, List<String>> _fileModuleIds = <String, List<String>>{
  'bin/workspace': <String>['catalog'],
  'bin/workspace_host': <String>['catalog'],
  'bin/gateway_sidecar': <String>['gateway.interceptor'],
  'studio/index.html': <String>['studio.shell'],
  'modules/module-catalog.json': <String>['catalog'],
};
