import 'dart:convert';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final hostOrigin = Uri.parse('http://127.0.0.1:7367');
  final studioOrigin = Uri.parse('http://127.0.0.1:7368');

  test('describes and opens one exact three-resource generation', () async {
    final catalog = _catalog();
    final bundle = _bundle(catalog, cameraX: 0);
    final facets = _facets(catalog, tagLabel: 'Primary');
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: bundle,
      initialScenarioFacetManifest: facets,
      clock: _FixedClock(),
    )..initialize(_kitManifest());
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
    );

    final description = workspace.describeContentSet();
    final opened = workspace.openContentSet(
      resources: registry,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
    );

    expect(opened.identity.toJson(), description.identity.toJson());
    expect(description.identity.revision, 1);
    expect(description.identity.catalogDigest, catalog.digest);
    expect(
      description.identity.workspaceSnapshotDigest,
      workspace.snapshot.digest,
    );
    expect(description.identity.experienceTopologyBundleDigest, bundle.digest);
    expect(description.identity.scenarioFacetManifestDigest, facets.digest);
    expect(registry.activeCount, 3);

    final snapshot = WorkspaceSnapshot.fromJson(
      await _readJson(registry, opened.workspaceSnapshot, studioOrigin),
    );
    final decodedBundle = ExperienceTopologyBundle.fromJson(
      await _readJson(registry, opened.experienceTopologyBundle!, studioOrigin),
      catalog: snapshot.catalog,
    );
    final decodedFacets = ScenarioFacetManifest.fromJson(
      await _readJson(registry, opened.scenarioFacetManifest!, studioOrigin),
      catalog: snapshot.catalog,
    );
    expect(snapshot.digest, description.identity.workspaceSnapshotDigest);
    expect(decodedBundle.digest, bundle.digest);
    expect(decodedFacets.digest, facets.digest);
  });

  test('describes and opens one exact five-resource generation', () async {
    final catalog = _catalog();
    final bundle = _bundle(catalog, cameraX: 0);
    final facets = _facets(catalog, tagLabel: 'Primary');
    final lab = _lab(catalog, scriptName: 'Inspect ready state');
    final motion = _motion(catalog, bundle);
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: bundle,
      initialScenarioFacetManifest: facets,
      initialScenarioLabManifest: lab,
      initialMotionManifest: motion,
      clock: _FixedClock(),
    )..initialize(_kitManifest());
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
    );

    final description = workspace.describeContentSet();
    final opened = workspace.openContentSet(
      resources: registry,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
    );

    expect(opened.identity.toJson(), description.identity.toJson());
    expect(description.identity.revision, 1);
    expect(description.identity.catalogDigest, catalog.digest);
    expect(
      description.identity.workspaceSnapshotDigest,
      workspace.snapshot.digest,
    );
    expect(
      description.identity.workspaceContentDigest,
      workspace.snapshot.workspaceContentDigest,
    );
    expect(description.identity.experienceTopologyBundleDigest, bundle.digest);
    expect(description.identity.scenarioFacetManifestDigest, facets.digest);
    expect(description.identity.scenarioLabManifestDigest, lab.digest);
    expect(description.identity.motionManifestDigest, motion.digest);
    expect(registry.activeCount, 5);

    final snapshot = WorkspaceSnapshot.fromJson(
      await _readJson(registry, opened.workspaceSnapshot, studioOrigin),
    );
    final decodedBundle = ExperienceTopologyBundle.fromJson(
      await _readJson(registry, opened.experienceTopologyBundle!, studioOrigin),
      catalog: snapshot.catalog,
    );
    final decodedFacets = ScenarioFacetManifest.fromJson(
      await _readJson(registry, opened.scenarioFacetManifest!, studioOrigin),
      catalog: snapshot.catalog,
    );
    final decodedLab = ScenarioLabManifest.fromJson(
      await _readJson(registry, opened.scenarioLabManifest!, studioOrigin),
      catalog: snapshot.catalog,
    );
    final decodedMotion = MotionManifest.fromJson(
      await _readJson(registry, opened.motionManifest!, studioOrigin),
      catalog: snapshot.catalog,
      topology: decodedBundle.topology,
    );
    expect(snapshot.digest, description.identity.workspaceSnapshotDigest);
    expect(
      snapshot.workspaceContentDigest,
      description.identity.workspaceContentDigest,
    );
    expect(decodedBundle.digest, bundle.digest);
    expect(decodedFacets.digest, facets.digest);
    expect(decodedLab.digest, lab.digest);
    expect(decodedMotion.digest, motion.digest);
  });

  test(
    'content identity survives equivalent Host restart but fences semantics',
    () {
      final catalog = _catalog();
      final bundle = _bundle(catalog, cameraX: 0);
      final facets = _facets(catalog, tagLabel: 'Primary');
      final lab = _lab(catalog, scriptName: 'Inspect ready state');
      HostWorkspaceService host({
        required DateTime observedAt,
        required DateTime kitGeneratedAt,
        String planMarker = 'plan',
      }) =>
          HostWorkspaceService(
            initialCatalog: catalog,
            initialExperienceBundle: bundle,
            initialScenarioFacetManifest: facets,
            initialScenarioLabManifest: lab,
            clock: _FixedClock(observedAt),
          )..initialize(
            _kitManifest(generatedAt: kitGeneratedAt, planMarker: planMarker),
          );

      final first = host(
        observedAt: DateTime.utc(2026, 8, 13, 12),
        kitGeneratedAt: DateTime.utc(2026, 8, 13, 11),
      );
      final restarted = host(
        observedAt: DateTime.utc(2026, 8, 14, 9),
        kitGeneratedAt: DateTime.utc(2026, 8, 14, 8),
      );

      expect(restarted.snapshot.digest, isNot(first.snapshot.digest));
      expect(
        restarted.snapshot.workspaceContentDigest,
        first.snapshot.workspaceContentDigest,
      );
      expect(
        restarted.contentSetIdentity.workspaceSnapshotDigest,
        isNot(first.contentSetIdentity.workspaceSnapshotDigest),
      );
      expect(
        restarted.contentSetIdentity.workspaceContentDigest,
        first.contentSetIdentity.workspaceContentDigest,
      );
      expect(
        restarted.contentSetIdentity.contentSetDigest,
        first.contentSetIdentity.contentSetDigest,
      );

      final changed = host(
        observedAt: DateTime.utc(2026, 8, 14, 9),
        kitGeneratedAt: DateTime.utc(2026, 8, 14, 8),
        planMarker: 'changed-plan',
      );
      expect(
        changed.snapshot.workspaceContentDigest,
        isNot(first.snapshot.workspaceContentDigest),
      );
      expect(
        changed.contentSetIdentity.contentSetDigest,
        isNot(first.contentSetIdentity.contentSetDigest),
      );
    },
  );

  test('absence is explicit and opens only the mandatory snapshot', () {
    final catalog = _catalog();
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      clock: _FixedClock(),
    )..initialize(_kitManifest());
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
    );

    final description = workspace.describeContentSet();
    final opened = workspace.openContentSet(
      resources: registry,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
    );

    expect(description.identity.experienceTopologyBundleDigest, isNull);
    expect(description.identity.scenarioFacetManifestDigest, isNull);
    expect(opened.experienceTopologyBundle, isNull);
    expect(opened.scenarioFacetManifest, isNull);
    expect(registry.activeCount, 1);
  });

  test(
    'revision fences layout-only, facet-only and snapshot-only changes once',
    () {
      final catalog = _catalog();
      final initialBundle = _bundle(catalog, cameraX: 0);
      final initialFacets = _facets(catalog, tagLabel: 'Primary');
      var next = HostWorkspaceContent(
        catalog: catalog,
        experienceBundle: initialBundle,
        scenarioFacetManifest: initialFacets,
      );
      final workspace = HostWorkspaceService(
        initialCatalog: catalog,
        initialExperienceBundle: initialBundle,
        initialScenarioFacetManifest: initialFacets,
        clock: _FixedClock(),
        reloadContent: () => next,
      )..initialize(_kitManifest());

      final initial = workspace.contentSetIdentity;
      final initialSnapshot = workspace.snapshot;
      final layoutBundle = _bundle(catalog, cameraX: 250);
      next = HostWorkspaceContent(
        catalog: catalog,
        experienceBundle: layoutBundle,
        scenarioFacetManifest: initialFacets,
      );
      final layoutRefresh = workspace.refreshContent(_kitManifest());
      final afterLayout = workspace.contentSetIdentity;
      expect(layoutRefresh.layoutOnlyChanged, isTrue);
      expect(layoutRefresh.facetsChanged, isFalse);
      expect(afterLayout.revision, initial.revision + 1);
      expect(
        afterLayout.workspaceSnapshotDigest,
        initial.workspaceSnapshotDigest,
      );
      expect(afterLayout.contentSetDigest, isNot(initial.contentSetDigest));
      expect(identical(workspace.snapshot, initialSnapshot), isTrue);

      final changedFacets = _facets(catalog, tagLabel: 'Critical');
      next = HostWorkspaceContent(
        catalog: catalog,
        experienceBundle: layoutBundle,
        scenarioFacetManifest: changedFacets,
      );
      final facetRefresh = workspace.refreshContent(_kitManifest());
      final afterFacets = workspace.contentSetIdentity;
      expect(facetRefresh.catalogChanged, isFalse);
      expect(facetRefresh.experienceChanged, isFalse);
      expect(facetRefresh.facetsChanged, isTrue);
      expect(afterFacets.revision, afterLayout.revision + 1);
      expect(
        afterFacets.workspaceSnapshotDigest,
        afterLayout.workspaceSnapshotDigest,
      );
      expect(
        afterFacets.experienceTopologyBundleDigest,
        afterLayout.experienceTopologyBundleDigest,
      );
      expect(afterFacets.scenarioFacetManifestDigest, changedFacets.digest);

      final combinedBundle = _bundle(catalog, cameraX: 500);
      final combinedFacets = _facets(catalog, tagLabel: 'Secondary');
      next = HostWorkspaceContent(
        catalog: catalog,
        experienceBundle: combinedBundle,
        scenarioFacetManifest: combinedFacets,
      );
      final beforeCombined = workspace.contentSetIdentity;
      final combinedRefresh = workspace.refreshContent(_kitManifest());
      final afterCombined = workspace.contentSetIdentity;
      expect(combinedRefresh.experienceChanged, isTrue);
      expect(combinedRefresh.facetsChanged, isTrue);
      expect(combinedRefresh.layoutOnlyChanged, isFalse);
      expect(afterCombined.revision, beforeCombined.revision + 1);
      expect(
        afterCombined.experienceTopologyBundleDigest,
        combinedBundle.digest,
      );
      expect(afterCombined.scenarioFacetManifestDigest, combinedFacets.digest);

      final variant = Variant(
        id: VariantId('phone'),
        applicationId: ApplicationId('app'),
        logicalWidth: 390,
        logicalHeight: 844,
        devicePixelRatio: 1,
        brightness: PreviewBrightness.light,
        localeTag: 'en-US',
      );
      final visualChanged = workspace.replaceVisualState(
        variantManifest: VariantManifest(
          catalogDigest: catalog.digest,
          variants: <Variant>[variant],
          sources: <VariantDefinitionSource>[
            VariantDefinitionSource(
              variantId: variant.id,
              sourceId: 'test',
              sourceDigest: Digest.semantic('variant-source'),
            ),
          ],
        ),
        projections: const <VisualEvidenceProjection>[],
      );
      final afterSnapshot = workspace.contentSetIdentity;
      expect(visualChanged, isTrue);
      expect(afterSnapshot.revision, afterCombined.revision + 1);
      expect(
        afterSnapshot.workspaceSnapshotDigest,
        isNot(afterCombined.workspaceSnapshotDigest),
      );
      expect(
        afterSnapshot.experienceTopologyBundleDigest,
        afterCombined.experienceTopologyBundleDigest,
      );
      expect(
        afterSnapshot.scenarioFacetManifestDigest,
        afterCombined.scenarioFacetManifestDigest,
      );
    },
  );

  test('failed reload leaves the complete generation intact', () {
    final catalog = _catalog();
    final bundle = _bundle(catalog, cameraX: 0);
    final facets = _facets(catalog, tagLabel: 'Primary');
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: bundle,
      initialScenarioFacetManifest: facets,
      clock: _FixedClock(),
      reloadContent: () => throw const FormatException('invalid content'),
    )..initialize(_kitManifest());
    final before = workspace.describeContentSet().toJson();

    expect(
      () => workspace.refreshContent(_kitManifest()),
      throwsFormatException,
    );
    expect(workspace.describeContentSet().toJson(), before);
  });

  test('failed candidate snapshot construction commits no partial state', () {
    final catalog = _catalog();
    final nextCatalog = _catalog(
      workspaceName: 'Next workspace',
      applicationValue: 'other-app',
    );
    final bundle = _bundle(catalog, cameraX: 0);
    final facets = _facets(catalog, tagLabel: 'Primary');
    final lab = _lab(catalog, scriptName: 'Inspect ready state');
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: bundle,
      initialScenarioFacetManifest: facets,
      initialScenarioLabManifest: lab,
      clock: _FixedClock(),
      providerBindings: <ProviderBinding>[
        ProviderBinding(
          capability: ModuleCapabilityRef(id: 'sample.query', version: 1),
          providerModuleIds: <ModuleId>[ModuleId('sample-provider')],
          selectionPolicy: ProviderSelectionPolicy.orderedFirstAvailable,
          applicationId: 'app',
        ),
      ],
      reloadContent: () => HostWorkspaceContent(catalog: nextCatalog),
    )..initialize(_kitManifest());
    final beforeSnapshot = workspace.snapshot;
    final beforeV1 = workspace.contentSetIdentity.toJson();
    final beforeV2 = workspace.contentSetIdentity.toJson();
    final beforeExperience = workspace.describeExperience();
    final beforeExperienceRevision = workspace.experienceRevision;
    final beforeContentRevision = workspace.contentRevision;
    final beforeContentV2Revision = workspace.contentRevision;

    expect(() => workspace.refreshContent(_kitManifest()), throwsArgumentError);

    expect(identical(workspace.snapshot, beforeSnapshot), isTrue);
    expect(workspace.snapshot.catalog.digest, catalog.digest);
    expect(workspace.experienceBundle?.digest, bundle.digest);
    expect(workspace.scenarioFacetManifest?.digest, facets.digest);
    expect(workspace.scenarioLabManifest?.digest, lab.digest);
    expect(workspace.contentSetIdentity.toJson(), beforeV1);
    expect(workspace.contentSetIdentity.toJson(), beforeV2);
    expect(workspace.describeExperience(), beforeExperience);
    expect(workspace.experienceRevision, beforeExperienceRevision);
    expect(workspace.contentRevision, beforeContentRevision);
    expect(workspace.contentRevision, beforeContentV2Revision);
  });

  test('Lab-only refresh advances the complete content generation', () {
    final catalog = _catalog();
    final bundle = _bundle(catalog, cameraX: 0);
    final facets = _facets(catalog, tagLabel: 'Primary');
    final initialLab = _lab(catalog, scriptName: 'Inspect ready state');
    var next = HostWorkspaceContent(
      catalog: catalog,
      experienceBundle: bundle,
      scenarioFacetManifest: facets,
      scenarioLabManifest: initialLab,
    );
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: bundle,
      initialScenarioFacetManifest: facets,
      initialScenarioLabManifest: initialLab,
      clock: _FixedClock(),
      reloadContent: () => next,
    )..initialize(_kitManifest());
    final before = workspace.describeContentSet();
    final beforeRevision = workspace.contentRevision;

    final changedLab = _lab(catalog, scriptName: 'Inspect current ready state');
    next = HostWorkspaceContent(
      catalog: catalog,
      experienceBundle: bundle,
      scenarioFacetManifest: facets,
      scenarioLabManifest: changedLab,
    );
    final refresh = workspace.refreshContent(_kitManifest());

    expect(refresh.changed, isTrue);
    expect(refresh.scenarioLabChanged, isTrue);
    expect(refresh.catalogChanged, isFalse);
    expect(refresh.experienceChanged, isFalse);
    expect(refresh.facetsChanged, isFalse);
    expect(refresh.layoutOnlyChanged, isFalse);
    expect(workspace.contentRevision, beforeRevision + 1);
    expect(
      workspace.describeContentSet().identity.contentSetDigest,
      isNot(before.identity.contentSetDigest),
    );
    expect(workspace.scenarioLabManifest?.digest, changedLab.digest);

    final unchanged = workspace.refreshContent(_kitManifest());
    expect(unchanged.changed, isFalse);
    expect(workspace.contentRevision, beforeRevision + 1);
  });

  test('tracks Lab presence, absence and combined layout changes once', () {
    final catalog = _catalog();
    final initialBundle = _bundle(catalog, cameraX: 0);
    final facets = _facets(catalog, tagLabel: 'Primary');
    var next = HostWorkspaceContent(
      catalog: catalog,
      experienceBundle: initialBundle,
      scenarioFacetManifest: facets,
    );
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: initialBundle,
      initialScenarioFacetManifest: facets,
      clock: _FixedClock(),
      reloadContent: () => next,
    )..initialize(_kitManifest());
    final initial = workspace.contentSetIdentity;
    expect(initial.scenarioLabManifestDigest, isNull);

    final lab = _lab(catalog, scriptName: 'Inspect ready state');
    next = HostWorkspaceContent(
      catalog: catalog,
      experienceBundle: initialBundle,
      scenarioFacetManifest: facets,
      scenarioLabManifest: lab,
    );
    final added = workspace.refreshContent(_kitManifest());
    final afterAdded = workspace.contentSetIdentity;
    expect(added.scenarioLabChanged, isTrue);
    expect(added.layoutOnlyChanged, isFalse);
    expect(afterAdded.revision, initial.revision + 1);
    expect(afterAdded.scenarioLabManifestDigest, lab.digest);

    next = HostWorkspaceContent(
      catalog: catalog,
      experienceBundle: initialBundle,
      scenarioFacetManifest: facets,
    );
    final removed = workspace.refreshContent(_kitManifest());
    final afterRemoved = workspace.contentSetIdentity;
    expect(removed.scenarioLabChanged, isTrue);
    expect(afterRemoved.revision, afterAdded.revision + 1);
    expect(afterRemoved.scenarioLabManifestDigest, isNull);
    expect(afterRemoved.contentSetDigest, initial.contentSetDigest);

    final movedBundle = _bundle(catalog, cameraX: 250);
    next = HostWorkspaceContent(
      catalog: catalog,
      experienceBundle: movedBundle,
      scenarioFacetManifest: facets,
      scenarioLabManifest: lab,
    );
    final combined = workspace.refreshContent(_kitManifest());
    final afterCombined = workspace.contentSetIdentity;
    expect(combined.experienceChanged, isTrue);
    expect(combined.scenarioLabChanged, isTrue);
    expect(combined.layoutOnlyChanged, isFalse);
    expect(afterCombined.revision, afterRemoved.revision + 1);
    expect(afterCombined.experienceTopologyBundleDigest, movedBundle.digest);
    expect(afterCombined.scenarioLabManifestDigest, lab.digest);
  });

  test('quota failure grants none of a complete generation', () {
    final catalog = _catalog();
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: _bundle(catalog, cameraX: 0),
      initialScenarioFacetManifest: _facets(catalog, tagLabel: 'Primary'),
      clock: _FixedClock(),
    )..initialize(_kitManifest());
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
      maxActiveResources: 2,
    );

    expect(
      () => workspace.openContentSet(
        resources: registry,
        hostOrigin: hostOrigin,
        studioOrigin: studioOrigin,
      ),
      throwsStateError,
    );
    expect(registry.activeCount, 0);
    expect(registry.totalBytes, 0);
  });

  test('quota failure grants none of a four-resource generation', () {
    final catalog = _catalog();
    final workspace = HostWorkspaceService(
      initialCatalog: catalog,
      initialExperienceBundle: _bundle(catalog, cameraX: 0),
      initialScenarioFacetManifest: _facets(catalog, tagLabel: 'Primary'),
      initialScenarioLabManifest: _lab(
        catalog,
        scriptName: 'Inspect ready state',
      ),
      clock: _FixedClock(),
    )..initialize(_kitManifest());
    final registry = HostResourceRegistry(
      clock: _FixedClock(),
      ids: _SequentialIds(),
      maxActiveResources: 3,
    );

    expect(
      () => workspace.openContentSet(
        resources: registry,
        hostOrigin: hostOrigin,
        studioOrigin: studioOrigin,
      ),
      throwsStateError,
    );
    expect(registry.activeCount, 0);
    expect(registry.totalBytes, 0);
  });

  test('rejects adjacent manifests from another catalog', () {
    final catalog = _catalog();
    final otherCatalog = _catalog(workspaceName: 'Other workspace');
    final bundle = _bundle(otherCatalog, cameraX: 0);
    final facets = _facets(otherCatalog, tagLabel: 'Primary');
    final lab = _lab(otherCatalog, scriptName: 'Inspect ready state');
    final motion = _motion(otherCatalog, bundle);

    expect(
      () =>
          HostWorkspaceContent(catalog: catalog, scenarioFacetManifest: facets),
      throwsArgumentError,
    );
    expect(
      () => HostWorkspaceContent(catalog: catalog, experienceBundle: bundle),
      throwsArgumentError,
    );
    expect(
      () => HostWorkspaceContent(catalog: catalog, scenarioLabManifest: lab),
      throwsArgumentError,
    );
    expect(
      () => HostWorkspaceContent(
        catalog: catalog,
        experienceBundle: bundle,
        motionManifest: motion,
      ),
      throwsArgumentError,
    );
    expect(
      () => HostWorkspaceService(
        initialCatalog: catalog,
        initialScenarioFacetManifest: facets,
        clock: _FixedClock(),
      ),
      throwsArgumentError,
    );
    expect(
      () => HostWorkspaceService(
        initialCatalog: catalog,
        initialExperienceBundle: bundle,
        clock: _FixedClock(),
      ),
      throwsArgumentError,
    );
    expect(
      () => HostWorkspaceService(
        initialCatalog: catalog,
        initialScenarioLabManifest: lab,
        clock: _FixedClock(),
      ),
      throwsArgumentError,
    );
    expect(
      () => HostWorkspaceService(
        initialCatalog: catalog,
        initialExperienceBundle: bundle,
        initialMotionManifest: motion,
        clock: _FixedClock(),
      ),
      throwsArgumentError,
    );
  });
}

Future<Object?> _readJson(
  HostResourceRegistry registry,
  ResourceHandle handle,
  Uri studioOrigin,
) async {
  final response = registry.serve(
    Request(
      'GET',
      handle.uri,
      headers: <String, String>{'origin': studioOrigin.origin},
    ),
  );
  expect(response.statusCode, 200);
  return jsonDecode(await response.readAsString());
}

EffectiveKitManifest _kitManifest({
  DateTime? generatedAt,
  String planMarker = 'plan',
}) => EffectiveKitManifest(
  resolvedPlanDigest: Digest.semantic(planMarker),
  modules: const <EffectiveModuleState>[],
  commands: const <String>[],
  rpcMethods: const <String>[],
  studioContributions: const <String>[],
  generatedAt: generatedAt ?? DateTime.utc(2026, 8, 13, 12),
);

CatalogManifest _catalog({
  String workspaceName = 'Workspace',
  String applicationValue = 'app',
}) {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId(applicationValue);
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
        displayName: 'App',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('flow'),
        applicationId: applicationId,
        title: 'Flow',
        scenarioIds: <ScenarioId>[ScenarioId('a'), ScenarioId('b')],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(id: ScenarioId('a'), applicationId: applicationId, title: 'A'),
      Scenario(id: ScenarioId('b'), applicationId: applicationId, title: 'B'),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('a-b'),
        journeyId: JourneyId('flow'),
        from: ScenarioId('a'),
        to: ScenarioId('b'),
      ),
    ],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('a-web'),
        scenarioId: ScenarioId('a'),
        targetId: 'chrome',
        launchProfileId: 'app-web',
      ),
    ],
  );
}

ScenarioLabManifest _lab(
  CatalogManifest catalog, {
  required String scriptName,
}) => ScenarioLabManifest(
  catalog: catalog,
  appAdapterCapabilities: const <CapabilityDescriptor>[],
  controls: const <ScenarioControlDefinition>[],
  operations: const <ScenarioLabOperationDefinition>[],
  scripts: <ScenarioScriptDefinition>[
    ScenarioScriptDefinition(
      id: ScenarioScriptId('inspect-a'),
      scenarioId: ScenarioId('a'),
      displayName: scriptName,
      timeoutMs: 30000,
      timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
      cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
      steps: <ScenarioScriptStep>[
        ExecutionBindingScenarioScriptStep(
          id: 'launch-a',
          timeoutMs: 10000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          bindingId: ScenarioExecutionBindingId('a-web'),
        ),
      ],
    ),
  ],
  automatedAcceptanceCriteria: const <AutomatedAcceptanceCriterion>[],
  requiredEvidence: const <RequiredEvidenceDefinition>[],
  comparisonBindings: const <ScenarioComparisonBinding>[],
  visualComparisonPolicies: const <VisualComparisonPolicy>[],
  semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
  humanApprovalRequirements: const <HumanApprovalRequirement>[],
  supplementalArtifacts: const <SupplementalArtifactReference>[],
  plans: <ScenarioLabPlan>[
    ScenarioLabPlan(
      scenarioId: ScenarioId('a'),
      executionBindingIds: <ScenarioExecutionBindingId>[
        ScenarioExecutionBindingId('a-web'),
      ],
      controlIds: const <ScenarioControlId>[],
      operationIds: const <ScenarioLabOperationId>[],
      scriptIds: <ScenarioScriptId>[ScenarioScriptId('inspect-a')],
      automatedAcceptanceCriterionIds: const <AutomatedAcceptanceCriterionId>[],
      requiredEvidenceIds: const <RequiredEvidenceId>[],
      comparisonBindingIds: const <ScenarioComparisonBindingId>[],
      humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
      supplementalArtifactIds: const <SupplementalArtifactId>[],
    ),
  ],
);

ExperienceTopologyBundle _bundle(
  CatalogManifest catalog, {
  required double cameraX,
}) {
  final projectionId = ExperienceProjectionId('flow-projection');
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: BoardId('flow-board'),
        applicationId: ApplicationId('app'),
        title: 'Flow',
        projectionIds: <ExperienceProjectionId>[projectionId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: projectionId,
        boardId: BoardId('flow-board'),
        applicationId: ApplicationId('app'),
        title: 'Flow',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('flow'),
        nodeInstanceIds: <NodeInstanceId>[
          NodeInstanceId('a-node'),
          NodeInstanceId('b-node'),
        ],
        edgeInstanceIds: <EdgeInstanceId>[EdgeInstanceId('a-b-edge')],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: NodeInstanceId('a-node'),
        projectionId: projectionId,
        scenarioId: ScenarioId('a'),
      ),
      NodeInstance(
        id: NodeInstanceId('b-node'),
        projectionId: projectionId,
        scenarioId: ScenarioId('b'),
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: EdgeInstanceId('a-b-edge'),
        projectionId: projectionId,
        transitionId: TransitionId('a-b'),
        fromNodeId: NodeInstanceId('a-node'),
        toNodeId: NodeInstanceId('b-node'),
      ),
    ],
  );
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: <ProjectionLayoutManifest>[
      ProjectionLayoutManifest(
        topologyDigest: topology.digest,
        projectionId: projectionId,
        nodeFrames: <ProjectionNodeFrame>[
          ProjectionNodeFrame(
            nodeInstanceId: NodeInstanceId('a-node'),
            x: 0,
            y: 0,
            width: 100,
            height: 100,
          ),
          ProjectionNodeFrame(
            nodeInstanceId: NodeInstanceId('b-node'),
            x: 200,
            y: 0,
            width: 100,
            height: 100,
          ),
        ],
        groups: const <ProjectionGroup>[],
        lanes: const <ProjectionLane>[],
        annotations: const <ProjectionAnnotation>[],
        camera: ProjectionCamera(x: cameraX, y: 0, zoom: 1),
      ),
    ],
  );
}

MotionManifest _motion(
  CatalogManifest catalog,
  ExperienceTopologyBundle bundle,
) => MotionManifest(
  catalogDigest: catalog.digest,
  topologyDigest: bundle.topology.digest,
  sequences: <MotionSequenceManifest>[
    MotionSequenceManifest(
      id: 'flow-motion',
      projectionId: ExperienceProjectionId('flow-projection'),
      title: 'Flow motion',
      staticSummary: 'A is followed by B.',
      steps: <MotionTransitionStep>[
        MotionTransitionStep(
          id: 'a-to-b',
          transitionId: TransitionId('a-b'),
          fromNodeId: NodeInstanceId('a-node'),
          toNodeId: NodeInstanceId('b-node'),
          startMs: 0,
          fullDurationMs: 420,
          reducedDurationMs: 80,
          easing: MotionEasing.easeInOut,
          observations: <MotionObservation>[
            MotionObservation(
              id: 'b-visible',
              label: 'B is visible',
              atFraction: 1,
              kind: MotionObservationKind.stateVisible,
            ),
          ],
        ),
      ],
    ),
  ],
)..validateAgainst(catalog: catalog, topology: bundle.topology);

ScenarioFacetManifest _facets(
  CatalogManifest catalog, {
  required String tagLabel,
}) => ScenarioFacetManifest(
  catalog: catalog,
  scenarioKinds: <ScenarioKindDefinition>[
    ScenarioKindDefinition(id: ScenarioKindId('state'), displayName: 'State'),
  ],
  surfaces: <ExperienceSurfaceDefinition>[
    ExperienceSurfaceDefinition(
      id: ExperienceSurfaceId('surface'),
      applicationId: ApplicationId('app'),
      displayName: 'Surface',
    ),
  ],
  states: <ScenarioStateDefinition>[
    ScenarioStateDefinition(
      id: ScenarioStateId('ready'),
      surfaceId: ExperienceSurfaceId('surface'),
      displayName: 'Ready',
    ),
  ],
  ownershipAreas: <OwnershipAreaDefinition>[
    OwnershipAreaDefinition(id: OwnershipAreaId('owner'), displayName: 'Owner'),
  ],
  tags: <ScenarioTagDefinition>[
    ScenarioTagDefinition(id: ScenarioTagId('primary'), displayName: tagLabel),
  ],
  components: <ExperienceComponentDefinition>[
    ExperienceComponentDefinition(
      id: ExperienceComponentId('screen'),
      applicationId: ApplicationId('app'),
      displayName: 'Screen',
    ),
  ],
  fixtures: <ScenarioFixtureDefinition>[
    for (final scenarioId in const <String>['a', 'b'])
      ScenarioFixtureDefinition(
        id: ScenarioFixtureId('$scenarioId-fixture'),
        applicationId: ApplicationId('app'),
        displayName: '$scenarioId fixture',
      ),
  ],
  formFactors: <FormFactorDefinition>[
    FormFactorDefinition(id: FormFactorId('phone'), displayName: 'Phone'),
  ],
  presentationFrames: <PresentationFrameDefinition>[
    PresentationFrameDefinition(
      id: PresentationFrameId('phone-frame'),
      displayName: 'Phone frame',
      kind: PresentationFrameKind.device,
      formFactorId: FormFactorId('phone'),
    ),
  ],
  scenarioFacets: <ScenarioFacet>[
    for (final scenarioId in const <String>['a', 'b'])
      ScenarioFacet(
        scenarioId: ScenarioId(scenarioId),
        lifecycle: ScenarioLifecycle.current,
        scenarioKindId: ScenarioKindId('state'),
        surfaceId: ExperienceSurfaceId('surface'),
        stateId: ScenarioStateId('ready'),
        ownershipAreaId: OwnershipAreaId('owner'),
        tagIds: <ScenarioTagId>[ScenarioTagId('primary')],
        componentIds: <ExperienceComponentId>[ExperienceComponentId('screen')],
        fixtureId: ScenarioFixtureId('$scenarioId-fixture'),
        renderSource: PreviewDescriptorRenderSource(
          previewId: AutoPreviewId('$scenarioId-preview'),
        ),
        presentationFrameIds: <PresentationFrameId>[
          PresentationFrameId('phone-frame'),
        ],
        preferredPresentationFrameId: PresentationFrameId('phone-frame'),
      ),
  ],
);

final class _FixedClock implements Clock {
  _FixedClock([DateTime? value])
    : value = value ?? DateTime.utc(2026, 8, 13, 12);

  final DateTime value;

  @override
  DateTime nowUtc() => value;

  @override
  int monotonicMicroseconds() => 0;
}

final class _SequentialIds implements IdGenerator {
  var _next = 0;

  @override
  String nextId() {
    _next += 1;
    return _next.toRadixString(16).padLeft(16, '0');
  }
}
