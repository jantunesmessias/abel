import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final catalogDigest = Digest.semantic(const <String, Object?>{
    'catalog': 'journey-preview',
  });
  final catalogReference = DistributionDocumentReference(
    path: 'modules/module-catalog.json',
    digest: catalogDigest,
  );
  final descriptor = DistributionReleaseDescriptor(
    id: 'full-local',
    displayName: 'Abel',
    coreCompatibility: '^0.1.0',
    defaultLayout: ConsumerLayout.standard,
    commandAliases: const <String>['workspace'],
    moduleCatalog: catalogReference,
    defaultProfileId: 'journey-preview',
  );
  DistributionFile file(
    String path, {
    bool executable = false,
    List<String> moduleIds = const <String>[],
    Digest? digest,
  }) => DistributionFile(
    path: path,
    digest: digest ?? Digest.semantic(path),
    size: path.length,
    executable: executable,
    role: executable ? 'binary' : 'distribution-asset',
    moduleIds: moduleIds,
  );
  final manifest = DistributionReleaseManifest(
    distribution: descriptor,
    releaseVersion: '0.2.0',
    coreVersion: '0.1.0',
    platform: 'linux-x64',
    moduleCatalog: catalogReference,
    modules: const <String>[
      'artifact-store.local',
      'catalog',
      'evidence.auto-preview',
      'studio.journey-map',
      'studio.shell',
    ],
    profiles: const <String>['journey-preview'],
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
        moduleIds: const <String>['studio.shell', 'studio.journey-map'],
      ),
    ],
    entrypoints: const <String, String>{
      'cli': 'bin/workspace',
      'host': 'bin/workspace_host',
      'studio': 'studio/index.html',
    },
    commandAliases: const <String, String>{'workspace': 'bin/workspace'},
    files: <DistributionFile>[
      file(
        'bin/workspace',
        executable: true,
        moduleIds: const <String>['catalog', 'evidence.auto-preview'],
      ),
      file(
        'bin/workspace_host',
        executable: true,
        moduleIds: const <String>['artifact-store.local', 'catalog'],
      ),
      file(
        'modules/module-catalog.json',
        digest: catalogDigest,
        moduleIds: const <String>['catalog'],
      ),
      file(
        'studio/index.html',
        moduleIds: const <String>['studio.shell', 'studio.journey-map'],
      ),
    ],
  );

  test('canonical release round-trips through its closed codec and schema', () {
    final decoded = const DistributionReleaseCodec().fromJson(
      manifest.toJson(),
    );
    expect(decoded.digest, manifest.digest);
    expect(decoded.entrypoints, isNot(contains('gateway')));
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'distribution',
                'distribution-release.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );
    final result = validator.validate(manifest.toJson());
    expect(result.isValid, isTrue, reason: '${result.issues}');
  });

  test('rejects unpublished and structurally divergent releases', () {
    expect(
      () => const DistributionReleaseCodec().fromJson(<String, Object?>{
        ...manifest.toJson(),
        'schemaVersion': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => DistributionReleaseManifest(
        distribution: descriptor,
        releaseVersion: manifest.releaseVersion,
        coreVersion: manifest.coreVersion,
        platform: manifest.platform,
        moduleCatalog: manifest.moduleCatalog,
        modules: manifest.modules,
        profiles: manifest.profiles,
        components: manifest.components,
        entrypoints: manifest.entrypoints,
        commandAliases: const <String, String>{'other': 'bin/workspace'},
        files: manifest.files,
      ),
      throwsArgumentError,
    );
  });
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
