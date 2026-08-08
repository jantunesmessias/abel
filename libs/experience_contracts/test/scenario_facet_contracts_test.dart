import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ScenarioFacetManifest', () {
    test('round-trips, validates its schema and binds the Catalog digest', () {
      final catalog = _catalog();
      final manifest = _manifest(catalog);
      final decoded = ScenarioFacetManifest.fromJson(
        manifest.toJson(),
        catalog: catalog,
      );
      final validator = _schemaValidator();
      final validation = validator.validate(manifest.toJson());

      expect(decoded.toJson(), manifest.toJson());
      expect(decoded.digest, manifest.digest);
      expect(decoded.catalogDigest, catalog.digest);
      expect(validation.isValid, isTrue, reason: validation.issues.join('\n'));
      expect(
        decoded.scenarioFacets.map((item) => item.scenarioId.value),
        <String>['loading', 'ready'],
      );
      expect(
        decoded.scenarioFacets.first.tagIds.map((item) => item.value),
        <String>['async-state', 'dashboard'],
      );
    });

    test('JCS canonicalizes registries, facets and membership IDs', () {
      final catalog = _catalog();
      final forward = _manifest(catalog);
      final reverse = ScenarioFacetManifest(
        catalog: catalog,
        scenarioKinds: forward.scenarioKinds.reversed,
        surfaces: forward.surfaces.reversed,
        states: forward.states.reversed,
        ownershipAreas: forward.ownershipAreas.reversed,
        tags: forward.tags.reversed,
        components: forward.components.reversed,
        fixtures: forward.fixtures.reversed,
        formFactors: forward.formFactors.reversed,
        presentationFrames: forward.presentationFrames.reversed,
        scenarioFacets: forward.scenarioFacets.reversed.map(
          (facet) => ScenarioFacet(
            scenarioId: facet.scenarioId,
            lifecycle: facet.lifecycle,
            scenarioKindId: facet.scenarioKindId,
            surfaceId: facet.surfaceId,
            stateId: facet.stateId,
            ownershipAreaId: facet.ownershipAreaId,
            tagIds: facet.tagIds.reversed,
            componentIds: facet.componentIds.reversed,
            fixtureId: facet.fixtureId,
            renderSource: facet.renderSource,
            presentationFrameIds: facet.presentationFrameIds.reversed,
            preferredPresentationFrameId: facet.preferredPresentationFrameId,
          ),
        ),
      );

      expect(reverse.toJson(), forward.toJson());
      expect(reverse.digest, forward.digest);
      expect(
        const JcsCanonicalizer().canonicalize(reverse.toJson()),
        const JcsCanonicalizer().canonicalize(forward.toJson()),
      );
    });

    test('rejects unknown fields, adjacent versions and forged digests', () {
      final catalog = _catalog();
      final base = _manifest(catalog).toJson();

      final unknown = _copy(base)..['metadata'] = <String, Object?>{};
      expect(
        () => ScenarioFacetManifest.fromJson(unknown, catalog: catalog),
        throwsFormatException,
      );

      final adjacent = _copy(base)..['schemaVersion'] = 2;
      _redigest(adjacent);
      expect(
        () => ScenarioFacetManifest.fromJson(adjacent, catalog: catalog),
        throwsFormatException,
      );

      final forged = _copy(base)..['digest'] = Digest.semantic('forged').value;
      expect(
        () => ScenarioFacetManifest.fromJson(forged, catalog: catalog),
        throwsFormatException,
      );
    });

    test('rejects catalog mismatch and incomplete Scenario coverage', () {
      final catalog = _catalog();
      final manifest = _manifest(catalog);
      final differentCatalog = _catalog(workspaceName: 'Different');

      expect(
        () => ScenarioFacetManifest.fromJson(
          manifest.toJson(),
          catalog: differentCatalog,
        ),
        throwsFormatException,
      );
      expect(
        () => ScenarioFacetManifest(
          catalog: catalog,
          scenarioKinds: manifest.scenarioKinds,
          surfaces: manifest.surfaces,
          states: manifest.states,
          ownershipAreas: manifest.ownershipAreas,
          tags: manifest.tags,
          components: manifest.components,
          fixtures: manifest.fixtures,
          formFactors: manifest.formFactors,
          presentationFrames: manifest.presentationFrames,
          scenarioFacets: manifest.scenarioFacets.take(1),
        ),
        throwsArgumentError,
      );
    });

    test('rejects cross-Surface, dangling and binding mismatches', () {
      final catalog = _catalog();
      final base = _manifest(catalog);
      final loading = base.scenarioFacets.first;

      expect(
        () => ScenarioFacetManifest(
          catalog: catalog,
          scenarioKinds: base.scenarioKinds,
          surfaces: base.surfaces,
          states: base.states,
          ownershipAreas: base.ownershipAreas,
          tags: base.tags,
          components: base.components,
          fixtures: base.fixtures,
          formFactors: base.formFactors,
          presentationFrames: base.presentationFrames,
          scenarioFacets: <ScenarioFacet>[
            ScenarioFacet(
              scenarioId: loading.scenarioId,
              lifecycle: loading.lifecycle,
              scenarioKindId: loading.scenarioKindId,
              surfaceId: ExperienceSurfaceId('gateway-surface'),
              stateId: loading.stateId,
              ownershipAreaId: loading.ownershipAreaId,
              tagIds: loading.tagIds,
              componentIds: loading.componentIds,
              fixtureId: loading.fixtureId,
              renderSource: loading.renderSource,
              presentationFrameIds: loading.presentationFrameIds,
              preferredPresentationFrameId:
                  loading.preferredPresentationFrameId,
            ),
            base.scenarioFacets.last,
          ],
        ),
        throwsArgumentError,
      );

      final ready = base.scenarioFacets.last;
      expect(
        () => ScenarioFacetManifest(
          catalog: catalog,
          scenarioKinds: base.scenarioKinds,
          surfaces: base.surfaces,
          states: base.states,
          ownershipAreas: base.ownershipAreas,
          tags: base.tags,
          components: base.components,
          fixtures: base.fixtures,
          formFactors: base.formFactors,
          presentationFrames: base.presentationFrames,
          scenarioFacets: <ScenarioFacet>[
            loading,
            ScenarioFacet(
              scenarioId: ready.scenarioId,
              lifecycle: ready.lifecycle,
              scenarioKindId: ready.scenarioKindId,
              surfaceId: ready.surfaceId,
              stateId: ready.stateId,
              ownershipAreaId: ready.ownershipAreaId,
              tagIds: ready.tagIds,
              componentIds: ready.componentIds,
              fixtureId: ready.fixtureId,
              renderSource: ExecutionBindingRenderSource(
                bindingId: ScenarioExecutionBindingId('missing-binding'),
              ),
              presentationFrameIds: ready.presentationFrameIds,
              preferredPresentationFrameId: ready.preferredPresentationFrameId,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('render sources and frames form a closed discriminated corpus', () {
      final digest = Digest.semantic('archive');
      final corpus = <ScenarioRenderSource>[
        PreviewDescriptorRenderSource(
          previewId: AutoPreviewId('sample.loading'),
        ),
        ExecutionBindingRenderSource(
          bindingId: ScenarioExecutionBindingId('ready-web'),
        ),
        ExternalHarnessRenderSource(
          providerId: RenderProviderId('storybook'),
          harnessId: RenderHarnessId('delivery-card'),
        ),
        ArchiveArtifactRenderSource(artifactDigest: digest),
      ];
      for (final source in corpus) {
        expect(
          ScenarioRenderSource.fromJson(source.toJson()).toJson(),
          source.toJson(),
        );
      }
      expect(
        () => ScenarioRenderSource.fromJson(<String, Object?>{
          'kind': 'previewDescriptor',
          'previewId': 'sample.loading',
          'metadata': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => ScenarioRenderSource.fromJson(<String, Object?>{
          'kind': 'futureRenderer',
          'previewId': 'sample.loading',
        }),
        throwsFormatException,
      );
      expect(
        () => PresentationFrameDefinition(
          id: PresentationFrameId('invalid-none'),
          displayName: 'Invalid',
          kind: PresentationFrameKind.none,
          formFactorId: FormFactorId('phone'),
        ),
        throwsArgumentError,
      );
      expect(
        () => ScenarioFacet(
          scenarioId: ScenarioId('archive-current'),
          lifecycle: ScenarioLifecycle.current,
          scenarioKindId: ScenarioKindId('state'),
          surfaceId: ExperienceSurfaceId('dashboard'),
          stateId: ScenarioStateId('ready'),
          ownershipAreaId: OwnershipAreaId('experience'),
          tagIds: <ScenarioTagId>[ScenarioTagId('dashboard')],
          componentIds: <ExperienceComponentId>[
            ExperienceComponentId('dashboard-page'),
          ],
          fixtureId: ScenarioFixtureId('sample.ready'),
          renderSource: ArchiveArtifactRenderSource(artifactDigest: digest),
          presentationFrameIds: <PresentationFrameId>[
            PresentationFrameId('phone-device'),
          ],
          preferredPresentationFrameId: PresentationFrameId('phone-device'),
        ),
        throwsArgumentError,
      );
    });

    test('enforces ID, collection and display-name limits', () {
      expect(() => ScenarioKindId('a${'x' * 256}'), throwsFormatException);
      expect(
        () => ScenarioKindDefinition(
          id: ScenarioKindId('state'),
          displayName: 'x' * 513,
        ),
        throwsArgumentError,
      );
      expect(
        () => ScenarioFacet(
          scenarioId: ScenarioId('duplicate-tags'),
          lifecycle: ScenarioLifecycle.current,
          scenarioKindId: ScenarioKindId('state'),
          surfaceId: ExperienceSurfaceId('dashboard'),
          stateId: ScenarioStateId('ready'),
          ownershipAreaId: OwnershipAreaId('experience'),
          tagIds: <ScenarioTagId>[
            ScenarioTagId('dashboard'),
            ScenarioTagId('dashboard'),
          ],
          componentIds: <ExperienceComponentId>[
            ExperienceComponentId('dashboard-page'),
          ],
          fixtureId: ScenarioFixtureId('sample.ready'),
          renderSource: PreviewDescriptorRenderSource(
            previewId: AutoPreviewId('sample.ready'),
          ),
          presentationFrameIds: <PresentationFrameId>[
            PresentationFrameId('phone-device'),
          ],
          preferredPresentationFrameId: PresentationFrameId('phone-device'),
        ),
        throwsArgumentError,
      );
    });
  });
}

CatalogManifest _catalog({String workspaceName = 'Workspace'}) {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('sample');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: workspaceName),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Sample',
        root: 'apps/sample',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(
        id: ScenarioId('loading'),
        applicationId: applicationId,
        title: 'Loading',
      ),
      Scenario(
        id: ScenarioId('ready'),
        applicationId: applicationId,
        title: 'Ready',
      ),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('ready-web'),
        scenarioId: ScenarioId('ready'),
        targetId: 'chrome',
        launchProfileId: 'sample-web',
      ),
    ],
  );
}

ScenarioFacetManifest _manifest(CatalogManifest catalog) {
  return ScenarioFacetManifest(
    catalog: catalog,
    scenarioKinds: <ScenarioKindDefinition>[
      ScenarioKindDefinition(
        id: ScenarioKindId('observable-state'),
        displayName: 'Observable state',
      ),
    ],
    surfaces: <ExperienceSurfaceDefinition>[
      ExperienceSurfaceDefinition(
        id: ExperienceSurfaceId('delivery-dashboard'),
        applicationId: ApplicationId('sample'),
        displayName: 'Delivery dashboard',
      ),
      ExperienceSurfaceDefinition(
        id: ExperienceSurfaceId('gateway-surface'),
        applicationId: ApplicationId('sample'),
        displayName: 'Gateway traffic',
      ),
    ],
    states: <ScenarioStateDefinition>[
      ScenarioStateDefinition(
        id: ScenarioStateId('loading'),
        surfaceId: ExperienceSurfaceId('delivery-dashboard'),
        displayName: 'Loading',
      ),
      ScenarioStateDefinition(
        id: ScenarioStateId('ready'),
        surfaceId: ExperienceSurfaceId('delivery-dashboard'),
        displayName: 'Ready',
      ),
    ],
    ownershipAreas: <OwnershipAreaDefinition>[
      OwnershipAreaDefinition(
        id: OwnershipAreaId('experience'),
        displayName: 'Experience team',
      ),
    ],
    tags: <ScenarioTagDefinition>[
      ScenarioTagDefinition(
        id: ScenarioTagId('dashboard'),
        displayName: 'Dashboard',
      ),
      ScenarioTagDefinition(
        id: ScenarioTagId('async-state'),
        displayName: 'Async state',
      ),
    ],
    components: <ExperienceComponentDefinition>[
      ExperienceComponentDefinition(
        id: ExperienceComponentId('dashboard-page'),
        applicationId: ApplicationId('sample'),
        displayName: 'Dashboard page',
      ),
    ],
    fixtures: <ScenarioFixtureDefinition>[
      ScenarioFixtureDefinition(
        id: ScenarioFixtureId('sample.loading'),
        applicationId: ApplicationId('sample'),
        displayName: 'Pending dashboard',
      ),
      ScenarioFixtureDefinition(
        id: ScenarioFixtureId('sample.ready'),
        applicationId: ApplicationId('sample'),
        displayName: 'Ready dashboard',
      ),
    ],
    formFactors: <FormFactorDefinition>[
      FormFactorDefinition(id: FormFactorId('phone'), displayName: 'Phone'),
      FormFactorDefinition(id: FormFactorId('desktop'), displayName: 'Desktop'),
    ],
    presentationFrames: <PresentationFrameDefinition>[
      PresentationFrameDefinition(
        id: PresentationFrameId('phone-device'),
        displayName: 'Phone device',
        kind: PresentationFrameKind.device,
        formFactorId: FormFactorId('phone'),
      ),
      PresentationFrameDefinition(
        id: PresentationFrameId('desktop-browser'),
        displayName: 'Desktop browser',
        kind: PresentationFrameKind.browser,
        formFactorId: FormFactorId('desktop'),
      ),
    ],
    scenarioFacets: <ScenarioFacet>[
      ScenarioFacet(
        scenarioId: ScenarioId('ready'),
        lifecycle: ScenarioLifecycle.current,
        scenarioKindId: ScenarioKindId('observable-state'),
        surfaceId: ExperienceSurfaceId('delivery-dashboard'),
        stateId: ScenarioStateId('ready'),
        ownershipAreaId: OwnershipAreaId('experience'),
        tagIds: <ScenarioTagId>[ScenarioTagId('dashboard')],
        componentIds: <ExperienceComponentId>[
          ExperienceComponentId('dashboard-page'),
        ],
        fixtureId: ScenarioFixtureId('sample.ready'),
        renderSource: ExecutionBindingRenderSource(
          bindingId: ScenarioExecutionBindingId('ready-web'),
        ),
        presentationFrameIds: <PresentationFrameId>[
          PresentationFrameId('desktop-browser'),
          PresentationFrameId('phone-device'),
        ],
        preferredPresentationFrameId: PresentationFrameId('phone-device'),
      ),
      ScenarioFacet(
        scenarioId: ScenarioId('loading'),
        lifecycle: ScenarioLifecycle.current,
        scenarioKindId: ScenarioKindId('observable-state'),
        surfaceId: ExperienceSurfaceId('delivery-dashboard'),
        stateId: ScenarioStateId('loading'),
        ownershipAreaId: OwnershipAreaId('experience'),
        tagIds: <ScenarioTagId>[
          ScenarioTagId('dashboard'),
          ScenarioTagId('async-state'),
        ],
        componentIds: <ExperienceComponentId>[
          ExperienceComponentId('dashboard-page'),
        ],
        fixtureId: ScenarioFixtureId('sample.loading'),
        renderSource: PreviewDescriptorRenderSource(
          previewId: AutoPreviewId('sample.loading'),
        ),
        presentationFrameIds: <PresentationFrameId>[
          PresentationFrameId('phone-device'),
        ],
        preferredPresentationFrameId: PresentationFrameId('phone-device'),
      ),
    ],
  );
}

Draft202012Validator _schemaValidator() => Draft202012Validator(
  jsonDecode(
        File(
          p.join(
            _root(),
            'schemas',
            'catalog',
            'scenario-facet-manifest.schema.json',
          ),
        ).readAsStringSync(),
      )
      as Object,
);

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

void _redigest(Map<String, Object?> value) {
  final semantic = Map<String, Object?>.of(value)..remove('digest');
  value['digest'] = Digest.semantic(semantic).value;
}

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
