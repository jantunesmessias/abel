import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final descriptor = DistributionDescriptor(
    id: 'devex-kit',
    displayName: 'DevExKit',
    coreCompatibility: '^0.1.0',
    defaultLayout: ConsumerLayout.devexDefault,
    commandAliases: const <String>['devex', 'devex-kit'],
  );
  final manifest = DistributionReleaseManifest(
    distribution: descriptor,
    releaseVersion: '0.1.0-preview.1',
    coreVersion: '0.1.0-dev',
    platform: 'linux-x64',
    entrypoints: const <String, String>{
      'cli': 'bin/devex',
      'host': 'bin/devex_host',
      'gateway': 'bin/backend_gateway',
      'studio': 'studio/index.html',
    },
    commandAliases: const <String, String>{
      'devex': 'bin/devex',
      'devex-kit': 'bin/devex',
    },
    files: <DistributionFile>[
      for (final path in <String>[
        'bin/devex',
        'bin/devex_host',
        'bin/backend_gateway',
        'studio/index.html',
      ])
        DistributionFile(
          path: path,
          digest: Digest.semantic(path),
          size: path.length,
          executable: path.startsWith('bin/'),
          role: path.startsWith('bin/') ? 'binary' : 'studio-asset',
        ),
    ],
  );

  test(
    'descriptor and release round-trip through closed codecs and schemas',
    () {
      expect(
        DistributionDescriptor.fromJson(descriptor.toJson()).toJson(),
        descriptor.toJson(),
      );
      expect(
        DistributionReleaseManifest.fromJson(manifest.toJson()).digest,
        manifest.digest,
      );
      for (final entry in <String, Object?>{
        'distribution-descriptor.schema.json': descriptor.toJson(),
        'distribution-release.schema.json': manifest.toJson(),
      }.entries) {
        final validator = Draft202012Validator(
          jsonDecode(
                File(
                  p.join(_repositoryRoot(), 'schemas', 'v1', entry.key),
                ).readAsStringSync(),
              )
              as Object,
        );
        final result = validator.validate(entry.value);
        expect(
          result.isValid,
          isTrue,
          reason: '${entry.key}: ${result.issues}',
        );
      }
    },
  );

  test('aliases and executable entrypoints fail closed', () {
    expect(
      () => DistributionReleaseManifest(
        distribution: descriptor,
        releaseVersion: '0.1.0',
        coreVersion: '0.1.0',
        platform: 'linux-x64',
        entrypoints: manifest.entrypoints,
        commandAliases: const <String, String>{'other': 'bin/devex'},
        files: manifest.files,
      ),
      throwsArgumentError,
    );
  });

  test('v2 supports a slim bundle and remains distinguishable from v1', () {
    final catalogDigest = Digest.semantic(const <String, Object?>{
      'catalog': 'journey-preview',
    });
    final catalogReference = DistributionDocumentReference(
      path: 'modules/module-catalog.json',
      digest: catalogDigest,
    );
    final descriptorV2 = DistributionDescriptorV2(
      id: descriptor.id,
      displayName: descriptor.displayName,
      coreCompatibility: descriptor.coreCompatibility,
      defaultLayout: descriptor.defaultLayout,
      commandAliases: descriptor.commandAliases,
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
    final manifestV2 = DistributionReleaseManifestV2(
      distribution: descriptorV2,
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
          path: 'bin/devex',
          moduleIds: const <String>['catalog', 'evidence.auto-preview'],
        ),
        DistributionComponent(
          id: 'host',
          kind: DistributionComponentKind.executable,
          path: 'bin/devex_host',
          moduleIds: const <String>['catalog', 'artifact-store.local'],
        ),
        DistributionComponent(
          id: 'studio',
          kind: DistributionComponentKind.webAssets,
          path: 'studio/index.html',
          moduleIds: const <String>['studio.shell', 'studio.journey-map'],
        ),
      ],
      entrypoints: const <String, String>{
        'cli': 'bin/devex',
        'host': 'bin/devex_host',
        'studio': 'studio/index.html',
      },
      commandAliases: const <String, String>{
        'devex': 'bin/devex',
        'devex-kit': 'bin/devex',
      },
      files: <DistributionFile>[
        file(
          'bin/devex',
          executable: true,
          moduleIds: const <String>['catalog'],
        ),
        file(
          'bin/devex_host',
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
          moduleIds: const <String>['studio.journey-map', 'studio.shell'],
        ),
      ],
    );

    final decoded = const DistributionReleaseCodec().fromJson(
      manifestV2.toJson(),
    );
    expect(decoded, isA<DistributionReleaseManifestV2>());
    expect(decoded.digest, manifestV2.digest);
    expect(decoded.entrypoints, isNot(contains('gateway')));
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'v2',
                'distribution-release.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );
    final result = validator.validate(manifestV2.toJson());
    expect(result.isValid, isTrue, reason: '${result.issues}');
  });
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
