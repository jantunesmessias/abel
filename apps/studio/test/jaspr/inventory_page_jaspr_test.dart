@TestOn('vm')
library;

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/jaspr/studio_app.dart';

void main() {
  testComponents(
    'renders the URL-selected Inventory occurrence without inventing edges',
    (tester) async {
      final snapshot = _inventorySnapshot();
      final bundle = _inventoryBundle(snapshot.catalog);
      final inventoryLayout = bundle.layouts
          .where((item) => item.projectionId.value == _inventoryProjectionId)
          .single;
      final facets = _inventoryFacets(snapshot.catalog);
      final client = _ContentClient(snapshot, bundle, facets);

      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(client.contentCalls, 1);
      expect(client.lastCatalogDigest, snapshot.catalog.digest);
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href': '/inventory',
        }),
        findsComponents,
      );
      expect(
        _domWithAttributes(<String, String>{
          'data-projection-id': _inventoryProjectionId,
          'data-projection-kind': 'inventory',
          'data-layout-digest': inventoryLayout.digest.value,
          'data-declared-edge-count': '0',
          'data-window-rendered': '3',
        }),
        findsOneComponent,
      );

      for (final nodeId in const <String>[
        'inventory-discover',
        'inventory-understand',
        'inventory-review',
      ]) {
        expect(
          _domWithAttributes(<String, String>{'data-node-instance-id': nodeId}),
          findsComponents,
        );
        expect(_domWithId('inventory-card-$nodeId'), findsOneComponent);
      }
      expect(_domWithAttributeName('data-edge-instance-id'), findsNothing);
      expect(
        _domWithAttributes(const <String, String>{
          'data-group-id': 'group-features',
          'role': 'group',
          'aria-label': 'Group Features autoradas',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-lane-id': 'lane-product',
          'role': 'group',
          'aria-label': 'Lane Produto',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-annotation-id': 'inventory-note',
          'role': 'note',
        }),
        findsOneComponent,
      );
      expect(
        find.text(
          'Occurrences autoradas; não um inventário canônico completo.',
        ),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-node-instance-id': 'inventory-understand',
          'aria-current': 'page',
        }),
        findsOneComponent,
      );
      expect(find.text('NodeInstance'), findsOneComponent);
      expect(find.text('inventory-understand'), findsComponents);
      expect(find.text('Layout digest'), findsOneComponent);
      expect(find.text(inventoryLayout.digest.value), findsOneComponent);
      expect(find.text('Source'), findsOneComponent);
      expect(find.textContaining('lib/understand.dart'), findsOneComponent);
      expect(find.text('Evidence'), findsOneComponent);
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'data-cross-lens': 'inventory-to-journey',
          'href': '/journeys/sample/nodes/journey-understand',
        }),
        findsOneComponent,
      );
      expect(find.text('Surface'), findsOneComponent);
      expect(find.text('Lifecycle'), findsOneComponent);
      expect(_spatialGeometryWithInlineStyles(), findsNothing);
    },
    url:
        '/inventory/$_inventoryProjectionId/nodes/inventory-understand?q=sample&application=sample-app&lifecycle=current&kind=state&surface=sample-surface&state=ready&owner=sample-team&tag=sample&component=sample-panel&fixture=synthetic&render=externalHarness&frame=device&formFactor=phone&group=group-features&lane=lane-product&sourceRepository=workspace&sourcePath=lib%2F&provider=evidence.auto-preview&variant=phone.light&evidenceStatus=collected&freshness=fresh&fidelity=structural',
  );

  testComponents(
    'renders every canonical Scenario and all published facet axes',
    (tester) async {
      final snapshot = _inventorySnapshot();
      final bundle = _inventoryBundle(snapshot.catalog);
      final facets = _inventoryFacets(snapshot.catalog);
      final client = _ContentClient(snapshot, bundle, facets);
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(find.text('3/3 Scenarios'), findsOneComponent);
      expect(
        _domWithAttributes(<String, String>{
          'data-inventory-facets': 'ready',
          'data-inventory-facet-digest': facets.digest.value,
        }),
        findsOneComponent,
      );
      for (final scenarioId in const <String>[
        'discover',
        'understand',
        'review',
      ]) {
        expect(_domWithId('inventory-scenario-$scenarioId'), findsOneComponent);
      }
      expect(
        _domWithAttributes(const <String, String>{
          'data-inventory-scenario-id': 'understand',
          'data-inventory-application': 'sample-app',
          'data-inventory-lifecycle': 'current',
          'data-inventory-kind': 'state',
          'data-inventory-surface': 'sample-surface',
          'data-inventory-state': 'ready',
          'data-inventory-owner': 'sample-team',
          'data-inventory-tags': 'sample',
          'data-inventory-components': 'sample-panel',
          'data-inventory-fixture': 'synthetic',
          'data-inventory-render': 'externalHarness',
          'data-inventory-frames': 'device',
          'data-inventory-form-factors': 'phone',
        }),
        findsOneComponent,
      );
      for (final label in const <String>[
        'Lifecycle',
        'Kind',
        'Surface',
        'State',
        'Owner',
        'Tag',
        'Component',
        'Fixture',
        'Render source',
        'Frame',
        'Form factor',
      ]) {
        expect(find.text(label), findsComponents);
      }
    },
    url:
        '/inventory?lifecycle=current&kind=state&surface=sample-surface&state=ready&owner=sample-team&tag=sample&component=sample-panel&fixture=synthetic&render=externalHarness&frame=device&formFactor=phone',
  );

  testComponents(
    'preserves an exact deep-linked NodeInstance outside URL filters',
    (tester) async {
      final snapshot = _inventorySnapshot();
      final client = _ExperienceClient(
        snapshot,
        _inventoryBundle(snapshot.catalog),
      );
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('foi preservado explicitamente'),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-window-rendered': '1',
          'data-declared-edge-count': '0',
        }),
        findsOneComponent,
      );
      expect(
        _domWithId('inventory-card-inventory-understand'),
        findsOneComponent,
      );
      expect(_domWithId('inventory-card-inventory-discover'), findsNothing);
      expect(_domWithId('inventory-card-inventory-review'), findsNothing);
    },
    url:
        '/inventory/$_inventoryProjectionId/nodes/inventory-understand?q=nao-existe',
  );

  testComponents(
    'links Journey to Inventory only through a unique Scenario occurrence',
    (tester) async {
      final snapshot = _inventorySnapshot();
      final client = _ExperienceClient(
        snapshot,
        _inventoryBundle(snapshot.catalog),
      );
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'data-cross-lens': 'journey-to-inventory',
          'href':
              '/inventory/$_inventoryProjectionId/nodes/inventory-understand',
        }),
        findsOneComponent,
      );
    },
    url: '/journeys/sample/nodes/journey-understand',
  );

  testComponents('shows an explicit Inventory state when topology is absent', (
    tester,
  ) async {
    final client = _NoTopologyClient(_inventorySnapshot());
    tester.pumpComponent(
      StudioApplication(
        clientFactory: () => client,
        reconnectDelay: Duration.zero,
      ),
    );
    await tester.pump();

    expect(client.openCalls, 1);
    expect(find.text('Inventory Projection indisponível'), findsOneComponent);
    expect(
      find.textContaining('O Host não publicou ExperienceTopologyBundle'),
      findsOneComponent,
    );
    expect(_domWithAttributeName('data-projection-id'), findsNothing);
  }, url: '/inventory');

  testComponents(
    'gates Inventory navigation and direct route by studio.inventory',
    (tester) async {
      final snapshot = _inventorySnapshot(inventoryEnabled: false);
      final client = _ExperienceClient(
        snapshot,
        _inventoryBundle(snapshot.catalog),
      );
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(find.text('Inventory não habilitada'), findsOneComponent);
      expect(find.textContaining('studio.inventory'), findsOneComponent);
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href': '/inventory',
        }),
        findsNothing,
      );
    },
    url: '/inventory',
  );
}

const String _inventoryProjectionId = 'sample-inventory';

WorkspaceSnapshot _inventorySnapshot({bool inventoryEnabled = true}) {
  final catalog = _inventoryCatalog();
  final providerId = ModuleId('evidence.auto-preview');
  final variant = Variant(
    id: VariantId('phone.light'),
    applicationId: ApplicationId('sample-app'),
    logicalWidth: 390,
    logicalHeight: 844,
    devicePixelRatio: 3,
    brightness: PreviewBrightness.light,
    localeTag: 'pt-BR',
  );
  return WorkspaceSnapshot(
    revision: 1,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: <Variant>[variant],
      sources: <VariantDefinitionSource>[
        VariantDefinitionSource(
          variantId: variant.id,
          sourceId: 'inventory.test',
          sourceDigest: Digest.semantic(const <String, Object?>{'source': 1}),
        ),
      ],
    ),
    effectiveKitManifest: EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic(const <String, Object?>{'plan': 1}),
      modules: <EffectiveModuleState>[
        for (final moduleId in <ModuleId>[
          ModuleId('studio.shell'),
          ModuleId('studio.journey-map'),
          if (inventoryEnabled) ModuleId('studio.inventory'),
          providerId,
        ])
          EffectiveModuleState(
            moduleId: moduleId,
            state: ModuleRuntimeState.ready,
            health: ModuleHealth.healthy,
            effectiveCapabilities: <ModuleCapabilityRef>[
              ModuleCapabilityRef(id: moduleId.value, version: 1),
            ],
          ),
      ],
      commands: const <String>[],
      rpcMethods: const <String>[],
      studioContributions: <String>[
        'studio.shell',
        'studio.journey-map',
        if (inventoryEnabled) 'studio.inventory',
      ],
      generatedAt: DateTime.utc(2026, 8, 13),
    ),
    providers: <VisualEvidenceProviderState>[
      VisualEvidenceProviderState(
        providerId: providerId,
        displayName: 'AutoPreview',
        health: ModuleHealth.healthy,
        supportedFidelities: const <RuntimeFidelity>{
          RuntimeFidelity.structural,
        },
        supportsCollection: false,
      ),
    ],
    visualProjections: <VisualEvidenceProjection>[
      for (final scenarioId in const <String>[
        'discover',
        'understand',
        'review',
      ])
        _collectedEvidence(providerId, variant.id, ScenarioId(scenarioId)),
    ],
    generatedAt: DateTime.utc(2026, 8, 13),
  );
}

VisualEvidenceProjection _collectedEvidence(
  ModuleId providerId,
  VariantId variantId,
  ScenarioId scenarioId,
) {
  final bytes = scenarioId.value.codeUnits;
  final artifactDigest = Digest.bytes(bytes);
  return VisualEvidenceProjection(
    providerId: providerId,
    scenarioId: scenarioId,
    variantId: variantId,
    status: VisualEvidenceStatus.collected,
    freshness: EvidenceFreshness.fresh,
    evidenceDigest: Digest.semantic(<String, Object?>{
      'scenario': scenarioId.value,
    }),
    artifactDigest: artifactDigest,
    fidelity: RuntimeFidelity.structural,
    observedAt: DateTime.utc(2026, 8, 13),
    artifactHandle: ResourceHandle(
      uri: Uri.parse(
        'http://127.0.0.1:39011/resources/abcdefghijklmnopqrstuvwxyzABCDEF_${scenarioId.value}',
      ),
      digest: artifactDigest,
      mediaType: 'image/png',
      size: bytes.length,
      purpose: 'visual-artifact',
      expiresAt: DateTime.utc(2030),
    ),
  );
}

CatalogManifest _inventoryCatalog() {
  final layout = ConsumerLayout.standard;
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: WorkspaceId('sample'), displayName: 'Sample'),
    applications: <Application>[
      Application(
        id: ApplicationId('sample-app'),
        workspaceId: WorkspaceId('sample'),
        displayName: 'Sample App',
        root: '.',
        target: 'local',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('sample'),
        applicationId: ApplicationId('sample-app'),
        title: 'Primeira jornada',
        scenarioIds: <ScenarioId>[
          ScenarioId('discover'),
          ScenarioId('understand'),
          ScenarioId('review'),
        ],
      ),
    ],
    scenarios: <Scenario>[
      _scenario('discover', 'Descobrir', 'lib/discover.dart'),
      _scenario('understand', 'Compreender', 'lib/understand.dart'),
      _scenario('review', 'Revisar', 'lib/review.dart'),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('discover-understand'),
        journeyId: JourneyId('sample'),
        from: ScenarioId('discover'),
        to: ScenarioId('understand'),
      ),
      Transition(
        id: TransitionId('understand-review'),
        journeyId: JourneyId('sample'),
        from: ScenarioId('understand'),
        to: ScenarioId('review'),
      ),
    ],
  );
}

Scenario _scenario(String id, String title, String path) => Scenario(
  id: ScenarioId(id),
  applicationId: ApplicationId('sample-app'),
  title: title,
  description: 'Scenario $title da amostra Inventory.',
  sourceReferences: <SourceReference>[
    SourceReference(repository: 'workspace', path: path, symbol: 'build'),
  ],
);

ScenarioFacetManifest _inventoryFacets(CatalogManifest catalog) {
  final frameId = PresentationFrameId('phone-frame');
  return ScenarioFacetManifest(
    catalog: catalog,
    scenarioKinds: <ScenarioKindDefinition>[
      ScenarioKindDefinition(id: ScenarioKindId('state'), displayName: 'State'),
    ],
    surfaces: <ExperienceSurfaceDefinition>[
      ExperienceSurfaceDefinition(
        id: ExperienceSurfaceId('sample-surface'),
        applicationId: ApplicationId('sample-app'),
        displayName: 'Sample surface',
      ),
    ],
    states: <ScenarioStateDefinition>[
      ScenarioStateDefinition(
        id: ScenarioStateId('ready'),
        surfaceId: ExperienceSurfaceId('sample-surface'),
        displayName: 'Ready',
      ),
    ],
    ownershipAreas: <OwnershipAreaDefinition>[
      OwnershipAreaDefinition(
        id: OwnershipAreaId('sample-team'),
        displayName: 'Sample team',
      ),
    ],
    tags: <ScenarioTagDefinition>[
      ScenarioTagDefinition(id: ScenarioTagId('sample'), displayName: 'Sample'),
    ],
    components: <ExperienceComponentDefinition>[
      ExperienceComponentDefinition(
        id: ExperienceComponentId('sample-panel'),
        applicationId: ApplicationId('sample-app'),
        displayName: 'Sample panel',
      ),
    ],
    fixtures: <ScenarioFixtureDefinition>[
      ScenarioFixtureDefinition(
        id: ScenarioFixtureId('synthetic'),
        applicationId: ApplicationId('sample-app'),
        displayName: 'Synthetic',
      ),
    ],
    formFactors: <FormFactorDefinition>[
      FormFactorDefinition(id: FormFactorId('phone'), displayName: 'Phone'),
    ],
    presentationFrames: <PresentationFrameDefinition>[
      PresentationFrameDefinition(
        id: frameId,
        displayName: 'Phone frame',
        kind: PresentationFrameKind.device,
        formFactorId: FormFactorId('phone'),
      ),
    ],
    scenarioFacets: <ScenarioFacet>[
      for (final scenario in catalog.scenarios)
        ScenarioFacet(
          scenarioId: scenario.id,
          lifecycle: ScenarioLifecycle.current,
          scenarioKindId: ScenarioKindId('state'),
          surfaceId: ExperienceSurfaceId('sample-surface'),
          stateId: ScenarioStateId('ready'),
          ownershipAreaId: OwnershipAreaId('sample-team'),
          tagIds: <ScenarioTagId>[ScenarioTagId('sample')],
          componentIds: <ExperienceComponentId>[
            ExperienceComponentId('sample-panel'),
          ],
          fixtureId: ScenarioFixtureId('synthetic'),
          renderSource: ExternalHarnessRenderSource(
            providerId: RenderProviderId('sample-provider'),
            harnessId: RenderHarnessId('sample-harness'),
          ),
          presentationFrameIds: <PresentationFrameId>[frameId],
          preferredPresentationFrameId: frameId,
        ),
    ],
  );
}

ExperienceTopologyBundle _inventoryBundle(CatalogManifest catalog) {
  final boardId = BoardId('sample-board');
  final inventoryId = ExperienceProjectionId(_inventoryProjectionId);
  final journeyId = ExperienceProjectionId('sample-journey');
  final inventoryNodes = <NodeInstance>[
    _node('inventory-discover', inventoryId, 'discover'),
    _node('inventory-understand', inventoryId, 'understand'),
    _node('inventory-review', inventoryId, 'review'),
  ];
  final journeyNodes = <NodeInstance>[
    _node('journey-discover', journeyId, 'discover'),
    _node('journey-understand', journeyId, 'understand'),
    _node('journey-review', journeyId, 'review'),
  ];
  final journeyEdges = <EdgeInstance>[
    EdgeInstance(
      id: EdgeInstanceId('journey-edge-discover-understand'),
      projectionId: journeyId,
      transitionId: TransitionId('discover-understand'),
      fromNodeId: NodeInstanceId('journey-discover'),
      toNodeId: NodeInstanceId('journey-understand'),
    ),
    EdgeInstance(
      id: EdgeInstanceId('journey-edge-understand-review'),
      projectionId: journeyId,
      transitionId: TransitionId('understand-review'),
      fromNodeId: NodeInstanceId('journey-understand'),
      toNodeId: NodeInstanceId('journey-review'),
    ),
  ];
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Board da amostra',
        projectionIds: <ExperienceProjectionId>[inventoryId, journeyId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: inventoryId,
        boardId: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Sample Inventory',
        kind: ProjectionKind.inventory,
        nodeInstanceIds: inventoryNodes.map((item) => item.id).toList(),
        edgeInstanceIds: const <EdgeInstanceId>[],
      ),
      ExperienceProjection(
        id: journeyId,
        boardId: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Sample Journey',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('sample'),
        nodeInstanceIds: journeyNodes.map((item) => item.id).toList(),
        edgeInstanceIds: journeyEdges.map((item) => item.id).toList(),
      ),
    ],
    nodes: <NodeInstance>[...inventoryNodes, ...journeyNodes],
    edges: journeyEdges,
  );
  final groupId = ProjectionGroupId('group-features');
  final laneId = ProjectionLaneId('lane-product');
  final inventoryLayout = ProjectionLayoutManifest(
    topologyDigest: topology.digest,
    projectionId: inventoryId,
    nodeFrames: <ProjectionNodeFrame>[
      _frame(inventoryNodes[0].id, 40, 80, groupId, laneId),
      _frame(inventoryNodes[1].id, 360, 80, groupId, laneId),
      _frame(inventoryNodes[2].id, 680, 280, groupId, laneId),
    ],
    groups: <ProjectionGroup>[
      ProjectionGroup(
        id: groupId,
        title: 'Features autoradas',
        x: 0,
        y: 0,
        width: 1000,
        height: 520,
      ),
    ],
    lanes: <ProjectionLane>[
      ProjectionLane(
        id: laneId,
        title: 'Produto',
        x: 20,
        y: 30,
        width: 940,
        height: 430,
      ),
    ],
    annotations: <ProjectionAnnotation>[
      ProjectionAnnotation(
        id: ProjectionAnnotationId('inventory-note'),
        text: 'Occurrences autoradas; não um inventário canônico completo.',
        x: 340,
        y: 300,
        width: 300,
        height: 80,
      ),
    ],
    camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
  );
  final journeyLayout = ProjectionLayoutManifest(
    topologyDigest: topology.digest,
    projectionId: journeyId,
    nodeFrames: <ProjectionNodeFrame>[
      _frame(journeyNodes[0].id, 40, 80, null, null),
      _frame(journeyNodes[1].id, 360, 80, null, null),
      _frame(journeyNodes[2].id, 680, 80, null, null),
    ],
    groups: const <ProjectionGroup>[],
    lanes: const <ProjectionLane>[],
    annotations: const <ProjectionAnnotation>[],
    camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
  );
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: <ProjectionLayoutManifest>[inventoryLayout, journeyLayout],
  );
}

NodeInstance _node(
  String id,
  ExperienceProjectionId projectionId,
  String scenarioId,
) => NodeInstance(
  id: NodeInstanceId(id),
  projectionId: projectionId,
  scenarioId: ScenarioId(scenarioId),
);

ProjectionNodeFrame _frame(
  NodeInstanceId nodeId,
  double x,
  double y,
  ProjectionGroupId? groupId,
  ProjectionLaneId? laneId,
) => ProjectionNodeFrame(
  nodeInstanceId: nodeId,
  x: x,
  y: y,
  width: 220,
  height: 140,
  groupId: groupId,
  laneId: laneId,
);

Finder _domWithAttributes(Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM component with attributes $attributes',
    );

Finder _domWithTagAndAttributes(String tag, Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          component.tag == tag &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM <$tag> component with attributes $attributes',
    );

Finder _domWithAttributeName(String attribute) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      (component.attributes?.containsKey(attribute) ?? false),
  description: 'DOM component with $attribute',
);

Finder _domWithId(String id) => find.byComponentPredicate(
  (component) => component is DomComponent && component.id == id,
  description: 'DOM component #$id',
);

Finder _spatialGeometryWithInlineStyles() {
  const geometricClasses = <String>{
    'inventory-map-stage',
    'inventory-map-lane',
    'inventory-map-group',
    'inventory-map-edges',
    'inventory-map-edge',
    'inventory-map-edge__label',
    'inventory-map-annotation',
    'inventory-map-node',
  };
  return find.byComponentPredicate((component) {
    if (component is! DomComponent || component.styles == null) return false;
    final classes = component.classes?.split(RegExp(r'\s+')).toSet();
    return classes != null && classes.intersection(geometricClasses).isNotEmpty;
  }, description: 'Inventory spatial geometry with inline styles');
}

final class _ContentClient
    implements StudioHostClient, StudioHostContentClient {
  _ContentClient(this.snapshot, this.bundle, this.facets);

  final WorkspaceSnapshot snapshot;
  final ExperienceTopologyBundle bundle;
  final ScenarioFacetManifest facets;
  int contentCalls = 0;
  Digest? lastCatalogDigest;

  StudioWorkspaceContent _content() {
    contentCalls += 1;
    lastCatalogDigest = snapshot.catalog.digest;
    return StudioWorkspaceContent(
      snapshot: snapshot,
      experienceBundle: bundle,
      scenarioFacets: facets,
      identity: ExperienceContentSetIdentity(
        revision: 1,
        catalogDigest: snapshot.catalog.digest,
        workspaceSnapshotDigest: snapshot.digest,
        workspaceContentDigest: snapshot.workspaceContentDigest,
        experienceTopologyBundleDigest: bundle.digest,
        scenarioFacetManifestDigest: facets.digest,
      ),
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<StudioWorkspaceContent> openContent() async => _content();

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => snapshot;

  @override
  Future<StudioWorkspaceContent> refreshContent() async => _content();

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => snapshot;
}

final class _ExperienceClient
    implements StudioHostClient, StudioHostContentClient {
  _ExperienceClient(this.snapshot, this.bundle);

  final WorkspaceSnapshot snapshot;
  final ExperienceTopologyBundle bundle;
  int experienceCalls = 0;
  Digest? lastCatalogDigest;

  @override
  Future<void> close() async {}

  @override
  Future<StudioWorkspaceContent> openContent() async {
    experienceCalls += 1;
    lastCatalogDigest = snapshot.catalog.digest;
    return _canonicalContent(snapshot, experienceBundle: bundle);
  }

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => snapshot;

  @override
  Future<StudioWorkspaceContent> refreshContent() => openContent();

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => snapshot;
}

final class _NoTopologyClient
    implements StudioHostClient, StudioHostContentClient {
  _NoTopologyClient(this.snapshot);

  final WorkspaceSnapshot snapshot;
  int openCalls = 0;

  @override
  Future<void> close() async {}

  @override
  Future<StudioWorkspaceContent> openContent() async {
    openCalls += 1;
    return _canonicalContent(snapshot);
  }

  @override
  Future<StudioWorkspaceContent> refreshContent() => openContent();

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => snapshot;

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => snapshot;
}

StudioWorkspaceContent _canonicalContent(
  WorkspaceSnapshot snapshot, {
  ExperienceTopologyBundle? experienceBundle,
}) => StudioWorkspaceContent(
  snapshot: snapshot,
  experienceBundle: experienceBundle,
  identity: ExperienceContentSetIdentity(
    revision: snapshot.revision,
    catalogDigest: snapshot.catalog.digest,
    workspaceSnapshotDigest: snapshot.digest,
    workspaceContentDigest: snapshot.workspaceContentDigest,
    experienceTopologyBundleDigest: experienceBundle?.digest,
  ),
);
