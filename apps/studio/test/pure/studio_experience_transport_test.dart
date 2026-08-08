import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/host/studio_experience_transport.dart';
import 'package:test/test.dart';

void main() {
  test('requires and observes one canonical content transport', () {
    const unrelated = <String>{
      'workspace.describe',
      'workspace.open',
      'experience.describe',
      'experience.open',
    };
    const canonical = <String>{
      ...unrelated,
      'experience.content.describe',
      'experience.content.open',
    };

    expect(
      () => requireStudioExperienceContentTransport(unrelated),
      throwsFormatException,
    );
    expect(
      () => requireStudioExperienceContentTransport(const <String>{
        'experience.content.describe',
      }),
      throwsFormatException,
    );
    expect(
      () => requireStudioExperienceContentTransport(canonical),
      returnsNormally,
    );
    expect(
      observesExperienceGenerationEvent(
        capabilities: canonical,
        method: 'workspace.changed',
      ),
      isFalse,
    );
    expect(
      observesExperienceGenerationEvent(
        capabilities: canonical,
        method: 'experience.changed',
      ),
      isFalse,
    );
    expect(
      observesExperienceGenerationEvent(
        capabilities: canonical,
        method: 'experience.content.changed',
      ),
      isTrue,
    );
  });

  test('validates ready description, open identity and canonical bundle', () {
    final catalog = sampleCatalogManifest();
    final bundle = _emptyBundle(catalog);
    final description = StudioExperienceDescription.fromJson(
      _description(bundle),
      catalog: catalog,
    );
    final open = StudioExperienceOpen.fromJson(
      <String, Object?>{
        'revision': 7,
        'bundleDigest': bundle.digest.value,
        'resource': _resource(bundle.digest).toJson(),
      },
      description: description,
      hostOrigin: Uri.parse('http://127.0.0.1:43123'),
      nowUtc: DateTime.utc(2026, 8, 13),
    );

    expect(description.isAbsent, isFalse);
    expect(open.bundleDigest, bundle.digest);
    expect(open.resource.purpose, 'experience-topology-bundle');
    expect(() => description.validateBundle(bundle), returnsNormally);
  });

  test('keeps an absent topology explicit without content digests', () {
    final catalog = sampleCatalogManifest();

    final description = StudioExperienceDescription.fromJson(<String, Object?>{
      'schemaVersion': 1,
      'kind': 'ExperienceDescription',
      'status': 'absent',
      'revision': 1,
      'catalogDigest': catalog.digest.value,
    }, catalog: catalog);

    expect(description.isAbsent, isTrue);
    expect(description.topologyDigest, isNull);
    expect(description.layoutDigests, isEmpty);
  });

  test('rejects unknown fields, duplicate layouts and unsafe resources', () {
    final catalog = sampleCatalogManifest();
    final bundle = _emptyBundle(catalog);
    final withUnknown = <String, Object?>{
      ..._description(bundle),
      'workspacePath': '/private/workspace',
    };
    final duplicateLayouts = <String, Object?>{
      ..._description(bundle),
      'layoutDigests': <Object?>[
        <String, Object?>{
          'projectionId': 'sample-projection',
          'digest': bundle.digest.value,
        },
        <String, Object?>{
          'projectionId': 'sample-projection',
          'digest': bundle.digest.value,
        },
      ],
    };

    expect(
      () => StudioExperienceDescription.fromJson(withUnknown, catalog: catalog),
      throwsFormatException,
    );
    expect(
      () => StudioExperienceDescription.fromJson(
        duplicateLayouts,
        catalog: catalog,
      ),
      throwsFormatException,
    );

    final description = StudioExperienceDescription.fromJson(
      _description(bundle),
      catalog: catalog,
    );
    final wrongPurpose = _resource(
      bundle.digest,
      purpose: 'workspace-snapshot',
    );
    expect(
      () => StudioExperienceOpen.fromJson(
        <String, Object?>{
          'revision': 7,
          'bundleDigest': bundle.digest.value,
          'resource': wrongPurpose.toJson(),
        },
        description: description,
        hostOrigin: Uri.parse('http://127.0.0.1:43123'),
        nowUtc: DateTime.utc(2026, 8, 13),
      ),
      throwsFormatException,
    );
    expect(
      () => StudioExperienceOpen.fromJson(
        <String, Object?>{
          'revision': 7,
          'bundleDigest': bundle.digest.value,
          'resource': _resource(bundle.digest).toJson(),
        },
        description: description,
        hostOrigin: Uri.parse('http://127.0.0.1:43123'),
        nowUtc: DateTime.utc(2026, 8, 15),
      ),
      throwsFormatException,
    );
  });
}

ExperienceTopologyBundle _emptyBundle(CatalogManifest catalog) {
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: const <Board>[],
    projections: const <ExperienceProjection>[],
    nodes: const <NodeInstance>[],
    edges: const <EdgeInstance>[],
  );
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: const <ProjectionLayoutManifest>[],
  );
}

Map<String, Object?> _description(ExperienceTopologyBundle bundle) =>
    <String, Object?>{
      'schemaVersion': 1,
      'kind': 'ExperienceDescription',
      'status': 'ready',
      'revision': 7,
      'catalogDigest': bundle.catalogDigest.value,
      'topologyDigest': bundle.topology.digest.value,
      'layoutDigests': <Object?>[],
      'bundleDigest': bundle.digest.value,
    };

ResourceHandle _resource(
  Digest digest, {
  String purpose = 'experience-topology-bundle',
}) => ResourceHandle(
  uri: Uri.parse(
    'http://127.0.0.1:43123/resources/abcdefghijklmnopqrstuvwxyzABCDEF',
  ),
  digest: digest,
  mediaType: 'application/json',
  size: 1,
  purpose: purpose,
  expiresAt: DateTime.utc(2026, 8, 14),
);
