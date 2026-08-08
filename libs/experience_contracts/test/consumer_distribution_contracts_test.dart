import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final spec = ConsumerDistributionSpec(
    distribution: _distribution(),
    releaseVersion: '1.2.3',
    profileId: 'gateway-lab-headless',
    studioAssets: ConsumerStudioAssets.absent,
    compatibility: ConsumerDistributionCompatibility(
      coreCompatibility: '^0.1.0',
    ),
  );
  final inventory = ConsumerDistributionInventory(
    distributionId: 'acme-experience',
    releaseVersion: '1.2.3',
    coreVersion: '0.1.0',
    profileId: 'gateway-lab-headless',
    studioAssets: ConsumerStudioAssets.absent,
    compatibility: spec.compatibility,
    specDigest: spec.digest,
    baseReleaseDigest: Digest.semantic('base'),
    moduleCatalogDigest: Digest.semantic('modules'),
    resolvedPlanDigest: Digest.semantic('plan'),
    consumerConfigurationDigest: Digest.semantic('configuration'),
    catalogDigest: Digest.semantic('catalog'),
    modules: <ConsumerDistributionModuleInventory>[
      ConsumerDistributionModuleInventory(
        id: 'catalog',
        version: '0.1.0',
        coreCompatibility: '^0.1.0',
        descriptorDigest: Digest.semantic('catalog-module'),
        surfaces: const <String>['cli', 'host'],
      ),
    ],
    files: <ConsumerDistributionFileInventory>[
      for (final entry in const <String, String>{
        'consumer/distribution-spec.json': 'specification',
        'consumer/workspace/workspace.yaml': 'configuration',
        'consumer/catalog.json': 'catalog',
        'consumer/resolved-kit-plan.json': 'resolved-plan',
      }.entries)
        ConsumerDistributionFileInventory(
          path: entry.key,
          digest: Digest.semantic(entry.key),
          size: entry.key.length,
          role: entry.value,
        ),
    ],
  );

  test('specification and inventory round-trip through the closed schema', () {
    expect(
      ConsumerDistributionSpec.fromJson(spec.toJson()).digest,
      spec.digest,
    );
    expect(
      ConsumerDistributionInventory.fromJson(inventory.toJson()).digest,
      inventory.digest,
    );

    final schema =
        jsonDecode(
              File(
                p.join(
                  _repositoryRoot(),
                  'schemas',
                  'distribution',
                  'consumer-distribution.schema.json',
                ),
              ).readAsStringSync(),
            )
            as Object;
    final validator = Draft202012Validator(schema);
    for (final document in <Map<String, Object?>>[
      spec.toJson(),
      inventory.toJson(),
    ]) {
      final result = validator.validate(document);
      expect(result.isValid, isTrue, reason: '${result.issues}');
    }
  });

  test('compatibility, Studio mode, and digest mismatches fail closed', () {
    expect(
      () => ConsumerDistributionSpec(
        distribution: _distribution(),
        releaseVersion: '1.2.3',
        profileId: 'gateway-lab-headless',
        studioAssets: ConsumerStudioAssets.absent,
        compatibility: ConsumerDistributionCompatibility(
          coreCompatibility: '^0.2.0',
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => ConsumerDistributionInventory(
        distributionId: inventory.distributionId,
        releaseVersion: inventory.releaseVersion,
        coreVersion: inventory.coreVersion,
        profileId: inventory.profileId,
        studioAssets: ConsumerStudioAssets.included,
        compatibility: inventory.compatibility,
        specDigest: inventory.specDigest,
        baseReleaseDigest: inventory.baseReleaseDigest,
        moduleCatalogDigest: inventory.moduleCatalogDigest,
        resolvedPlanDigest: inventory.resolvedPlanDigest,
        consumerConfigurationDigest: inventory.consumerConfigurationDigest,
        catalogDigest: inventory.catalogDigest,
        modules: inventory.modules,
        files: inventory.files,
      ),
      throwsArgumentError,
    );
    final tampered = <String, Object?>{...spec.toJson(), 'profileId': 'other'};
    expect(
      () => ConsumerDistributionSpec.fromJson(tampered),
      throwsFormatException,
    );
  });
}

DistributionDescriptor _distribution() => DistributionDescriptor(
  id: 'acme-experience',
  displayName: 'Acme Experience',
  coreCompatibility: '^0.1.0',
  defaultLayout: ConsumerLayout.standard,
  commandAliases: const <String>['acme-experience'],
);

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
