import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/inventory/inventory_catalog.dart';
import 'package:studio/src/inventory/inventory_projection.dart';
import 'package:test/test.dart';

void main() {
  group('InventoryProjectionIndex', () {
    test(
      'resolves authored Inventory occurrences without changing identity',
      () {
        final catalog = _catalog();
        final index = InventoryProjectionIndex(
          catalog: catalog,
          bundle: _bundle(catalog),
        );

        expect(
          index.inventoryProjections().map((item) => item.id.value),
          <String>['inventory-map'],
        );
        final resolution = index.resolve('inventory-map');
        expect(resolution.status, InventoryProjectionStatus.ready);
        expect(
          resolution.occurrences.map((item) => item.node.id.value),
          <String>['inventory-alpha', 'inventory-beta'],
        );
        expect(resolution.occurrences.first.scenario.id.value, 'alpha');
        expect(resolution.occurrences.first.group?.id.value, 'group-alpha');
        expect(resolution.occurrences.first.lane?.id.value, 'lane-state');
        expect(
          resolution.layout?.annotations.single.id.value,
          'inventory-note',
        );
        expect(resolution.edges, isEmpty);
      },
    );

    test('keeps absence and a wrong Projection kind explicit', () {
      final catalog = _catalog();
      expect(
        InventoryProjectionIndex(
          catalog: catalog,
          bundle: null,
        ).resolve('inventory-map').status,
        InventoryProjectionStatus.topologyAbsent,
      );
      final withoutLayout = InventoryProjectionIndex(
        catalog: catalog,
        bundle: _bundle(catalog, includeInventoryLayout: false),
      );
      expect(
        withoutLayout.resolve('missing').status,
        InventoryProjectionStatus.projectionAbsent,
      );
      expect(
        withoutLayout.resolve('journey-map').status,
        InventoryProjectionStatus.projectionKindMismatch,
      );
      expect(
        withoutLayout.resolve('inventory-map').status,
        InventoryProjectionStatus.layoutAbsent,
      );
      expect(withoutLayout.resolve('inventory-map').occurrences, hasLength(2));
    });

    test(
      'links lenses only when Scenario has one occurrence in the target',
      () {
        final catalog = _catalog();
        final unique = InventoryProjectionIndex(
          catalog: catalog,
          bundle: _bundle(catalog),
        );

        expect(
          unique
              .uniqueNodeForScenario(
                kind: ProjectionKind.inventory,
                applicationId: ApplicationId('sample-app'),
                scenarioId: ScenarioId('alpha'),
              )
              ?.node
              .id
              .value,
          'inventory-alpha',
        );
        expect(
          unique
              .uniqueNodeForScenario(
                kind: ProjectionKind.journey,
                applicationId: ApplicationId('sample-app'),
                scenarioId: ScenarioId('alpha'),
              )
              ?.node
              .id
              .value,
          'journey-alpha',
        );

        final ambiguous = InventoryProjectionIndex(
          catalog: catalog,
          bundle: _bundle(catalog, repeatInventoryAlpha: true),
        );
        expect(
          ambiguous.uniqueNodeForScenario(
            kind: ProjectionKind.inventory,
            applicationId: ApplicationId('sample-app'),
            scenarioId: ScenarioId('alpha'),
          ),
          isNull,
        );
      },
    );
  });

  group('InventoryOccurrenceFilter', () {
    test(
      'combines real facets and explicitly preserves selected occurrence',
      () {
        final catalog = _catalog();
        final occurrences = InventoryProjectionIndex(
          catalog: catalog,
          bundle: _bundle(catalog),
        ).resolve('inventory-map').occurrences;
        final filters =
            InventoryFilters.fromQueryParameters(const <String, String>{
              'q': 'AlphaPanel',
              'application': 'sample-app',
              'group': 'group-alpha',
              'lane': 'lane-state',
              'sourceRepository': 'workspace',
              'sourcePath': 'lib/alpha',
              'provider': 'evidence.auto-preview',
              'variant': 'phone.light',
              'evidenceStatus': 'missing',
              'freshness': 'missing',
            });

        final result = const InventoryOccurrenceFilter().apply(
          occurrences: occurrences,
          filters: filters,
          evidence: <VisualEvidenceProjection>[
            VisualEvidenceProjection(
              providerId: ModuleId('evidence.auto-preview'),
              scenarioId: ScenarioId('alpha'),
              variantId: VariantId('phone.light'),
              capturePolicyId: 'static-v1',
              status: VisualEvidenceStatus.missing,
              freshness: EvidenceFreshness.missing,
            ),
          ],
          selectedNodeId: NodeInstanceId('inventory-beta'),
        );

        expect(result.matches.map((item) => item.node.id.value), <String>[
          'inventory-alpha',
        ]);
        expect(result.visible.map((item) => item.node.id.value), <String>[
          'inventory-alpha',
          'inventory-beta',
        ]);
        expect(result.selectedWasPreserved, isTrue);
        expect(filters.toQueryParameters(), containsPair('q', 'AlphaPanel'));
      },
    );

    test('invalid URL filter is explicit and never broadens results', () {
      final catalog = _catalog();
      final filters = InventoryFilters.fromQueryParameters(
        const <String, String>{'evidenceStatus': 'ready'},
      );
      final result = const InventoryOccurrenceFilter().apply(
        occurrences: InventoryProjectionIndex(
          catalog: catalog,
          bundle: _bundle(catalog),
        ).resolve('inventory-map').occurrences,
        filters: filters,
      );

      expect(filters.invalidParameters, <String>{'evidenceStatus'});
      expect(result.matches, isEmpty);
      expect(result.visible, isEmpty);
    });
  });

  group('InventoryCatalogAdapter', () {
    test('indexes every Catalog Scenario through canonical facets', () {
      final catalog = _catalog();
      final adapter = InventoryCatalogAdapter(
        catalog: catalog,
        facets: _facets(catalog),
      );

      final all = adapter.resolve(InventoryFilters());
      expect(all.isReady, isTrue);
      expect(all.entries.map((item) => item.scenario.id.value), <String>[
        'alpha',
        'beta',
      ]);

      final filters =
          InventoryFilters.fromQueryParameters(const <String, String>{
            'application': 'sample-app',
            'lifecycle': 'current',
            'kind': 'state',
            'surface': 'sample-surface',
            'state': 'ready',
            'owner': 'team-a',
            'tag': 'critical',
            'component': 'alpha-panel',
            'fixture': 'fixture-a',
            'render': 'externalHarness',
            'frame': 'device',
            'formFactor': 'phone',
          });
      final filtered = adapter.resolve(filters);

      expect(filtered.entries.map((item) => item.scenario.id.value), <String>[
        'alpha',
      ]);
      expect(filters.toQueryParameters(), containsPair('formFactor', 'phone'));
      expect(adapter.scenarioScope(filters), <ScenarioId>{ScenarioId('alpha')});
    });

    test('keeps absent facets and invalid values fail-closed', () {
      final catalog = _catalog();
      final absent = InventoryCatalogAdapter(catalog: catalog, facets: null);
      final requested = InventoryFilters.fromQueryParameters(
        const <String, String>{'surface': 'sample-surface'},
      );
      expect(absent.resolve(requested).isReady, isFalse);
      expect(absent.scenarioScope(requested), isEmpty);

      final invalid = InventoryFilters.fromQueryParameters(
        const <String, String>{'lifecycle': 'active'},
      );
      final resolution = InventoryCatalogAdapter(
        catalog: catalog,
        facets: _facets(catalog),
      ).resolve(invalid);
      expect(invalid.invalidParameters, <String>{'lifecycle'});
      expect(resolution.entries, isEmpty);
    });
  });
}

CatalogManifest _catalog() => CatalogManifest(
  distribution: DistributionDescriptor(
    id: 'full-local',
    displayName: 'Abel',
    coreCompatibility: '^0.1.0',
    defaultLayout: ConsumerLayout.standard,
  ),
  layout: ConsumerLayout.standard,
  workspace: Workspace(
    id: WorkspaceId('sample-workspace'),
    displayName: 'Sample workspace',
  ),
  applications: <Application>[
    Application(
      id: ApplicationId('sample-app'),
      workspaceId: WorkspaceId('sample-workspace'),
      displayName: 'Sample app',
      root: '.',
      target: 'web',
    ),
  ],
  journeys: <Journey>[
    Journey(
      id: JourneyId('sample-journey'),
      applicationId: ApplicationId('sample-app'),
      title: 'Sample Journey',
      scenarioIds: <ScenarioId>[ScenarioId('alpha'), ScenarioId('beta')],
    ),
  ],
  scenarios: <Scenario>[
    Scenario(
      id: ScenarioId('alpha'),
      applicationId: ApplicationId('sample-app'),
      title: 'Alpha state',
      description: 'First observable state',
      sourceReferences: <SourceReference>[
        SourceReference(
          repository: 'workspace',
          path: 'lib/alpha.dart',
          symbol: 'AlphaPanel',
        ),
      ],
    ),
    Scenario(
      id: ScenarioId('beta'),
      applicationId: ApplicationId('sample-app'),
      title: 'Beta operation',
      sourceReferences: <SourceReference>[
        SourceReference(repository: 'workspace', path: 'lib/beta.dart'),
      ],
    ),
  ],
  transitions: <Transition>[
    Transition(
      id: TransitionId('alpha-beta'),
      journeyId: JourneyId('sample-journey'),
      from: ScenarioId('alpha'),
      to: ScenarioId('beta'),
    ),
  ],
);

ExperienceTopologyBundle _bundle(
  CatalogManifest catalog, {
  bool includeInventoryLayout = true,
  bool repeatInventoryAlpha = false,
}) {
  final boardId = BoardId('sample-board');
  final inventoryId = ExperienceProjectionId('inventory-map');
  final journeyId = ExperienceProjectionId('journey-map');
  final inventoryNodeIds = <NodeInstanceId>[
    NodeInstanceId('inventory-alpha'),
    NodeInstanceId('inventory-beta'),
    if (repeatInventoryAlpha) NodeInstanceId('inventory-alpha-copy'),
  ];
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Sample board',
        projectionIds: <ExperienceProjectionId>[inventoryId, journeyId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: inventoryId,
        boardId: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Inventory',
        kind: ProjectionKind.inventory,
        nodeInstanceIds: inventoryNodeIds,
        edgeInstanceIds: const <EdgeInstanceId>[],
      ),
      ExperienceProjection(
        id: journeyId,
        boardId: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Journey',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('sample-journey'),
        nodeInstanceIds: <NodeInstanceId>[
          NodeInstanceId('journey-alpha'),
          NodeInstanceId('journey-beta'),
        ],
        edgeInstanceIds: <EdgeInstanceId>[EdgeInstanceId('journey-edge')],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: NodeInstanceId('inventory-alpha'),
        projectionId: inventoryId,
        scenarioId: ScenarioId('alpha'),
      ),
      NodeInstance(
        id: NodeInstanceId('inventory-beta'),
        projectionId: inventoryId,
        scenarioId: ScenarioId('beta'),
      ),
      if (repeatInventoryAlpha)
        NodeInstance(
          id: NodeInstanceId('inventory-alpha-copy'),
          projectionId: inventoryId,
          scenarioId: ScenarioId('alpha'),
        ),
      NodeInstance(
        id: NodeInstanceId('journey-alpha'),
        projectionId: journeyId,
        scenarioId: ScenarioId('alpha'),
      ),
      NodeInstance(
        id: NodeInstanceId('journey-beta'),
        projectionId: journeyId,
        scenarioId: ScenarioId('beta'),
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: EdgeInstanceId('journey-edge'),
        projectionId: journeyId,
        transitionId: TransitionId('alpha-beta'),
        fromNodeId: NodeInstanceId('journey-alpha'),
        toNodeId: NodeInstanceId('journey-beta'),
      ),
    ],
  );
  final groupAlpha = ProjectionGroupId('group-alpha');
  final groupBeta = ProjectionGroupId('group-beta');
  final laneState = ProjectionLaneId('lane-state');
  final laneOperation = ProjectionLaneId('lane-operation');
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: <ProjectionLayoutManifest>[
      if (includeInventoryLayout)
        ProjectionLayoutManifest(
          topologyDigest: topology.digest,
          projectionId: inventoryId,
          nodeFrames: <ProjectionNodeFrame>[
            ProjectionNodeFrame(
              nodeInstanceId: NodeInstanceId('inventory-alpha'),
              x: 20,
              y: 20,
              width: 200,
              height: 120,
              groupId: groupAlpha,
              laneId: laneState,
            ),
            ProjectionNodeFrame(
              nodeInstanceId: NodeInstanceId('inventory-beta'),
              x: 280,
              y: 220,
              width: 200,
              height: 120,
              groupId: groupBeta,
              laneId: laneOperation,
            ),
            if (repeatInventoryAlpha)
              ProjectionNodeFrame(
                nodeInstanceId: NodeInstanceId('inventory-alpha-copy'),
                x: 540,
                y: 20,
                width: 200,
                height: 120,
                groupId: groupAlpha,
                laneId: laneState,
              ),
          ],
          groups: <ProjectionGroup>[
            ProjectionGroup(
              id: groupAlpha,
              title: 'Alpha group',
              x: 0,
              y: 0,
              width: 250,
              height: 180,
            ),
            ProjectionGroup(
              id: groupBeta,
              title: 'Beta group',
              x: 250,
              y: 180,
              width: 260,
              height: 180,
            ),
          ],
          lanes: <ProjectionLane>[
            ProjectionLane(
              id: laneState,
              title: 'States',
              x: 0,
              y: 0,
              width: 760,
              height: 180,
            ),
            ProjectionLane(
              id: laneOperation,
              title: 'Operations',
              x: 0,
              y: 180,
              width: 760,
              height: 180,
            ),
          ],
          annotations: <ProjectionAnnotation>[
            ProjectionAnnotation(
              id: ProjectionAnnotationId('inventory-note'),
              text: 'Authored Inventory lens',
              x: 520,
              y: 220,
              width: 200,
              height: 80,
            ),
          ],
          camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
        ),
    ],
  );
}

ScenarioFacetManifest _facets(CatalogManifest catalog) => ScenarioFacetManifest(
  catalog: catalog,
  scenarioKinds: <ScenarioKindDefinition>[
    ScenarioKindDefinition(
      id: ScenarioKindId('operation'),
      displayName: 'Operation',
    ),
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
      id: ScenarioStateId('loading'),
      surfaceId: ExperienceSurfaceId('sample-surface'),
      displayName: 'Loading',
    ),
    ScenarioStateDefinition(
      id: ScenarioStateId('ready'),
      surfaceId: ExperienceSurfaceId('sample-surface'),
      displayName: 'Ready',
    ),
  ],
  ownershipAreas: <OwnershipAreaDefinition>[
    OwnershipAreaDefinition(
      id: OwnershipAreaId('team-a'),
      displayName: 'Team A',
    ),
    OwnershipAreaDefinition(
      id: OwnershipAreaId('team-b'),
      displayName: 'Team B',
    ),
  ],
  tags: <ScenarioTagDefinition>[
    ScenarioTagDefinition(
      id: ScenarioTagId('critical'),
      displayName: 'Critical',
    ),
    ScenarioTagDefinition(
      id: ScenarioTagId('secondary'),
      displayName: 'Secondary',
    ),
  ],
  components: <ExperienceComponentDefinition>[
    ExperienceComponentDefinition(
      id: ExperienceComponentId('alpha-panel'),
      applicationId: ApplicationId('sample-app'),
      displayName: 'Alpha panel',
    ),
    ExperienceComponentDefinition(
      id: ExperienceComponentId('beta-panel'),
      applicationId: ApplicationId('sample-app'),
      displayName: 'Beta panel',
    ),
  ],
  fixtures: <ScenarioFixtureDefinition>[
    ScenarioFixtureDefinition(
      id: ScenarioFixtureId('fixture-a'),
      applicationId: ApplicationId('sample-app'),
      displayName: 'Fixture A',
    ),
    ScenarioFixtureDefinition(
      id: ScenarioFixtureId('fixture-b'),
      applicationId: ApplicationId('sample-app'),
      displayName: 'Fixture B',
    ),
  ],
  formFactors: <FormFactorDefinition>[
    FormFactorDefinition(id: FormFactorId('desktop'), displayName: 'Desktop'),
    FormFactorDefinition(id: FormFactorId('phone'), displayName: 'Phone'),
  ],
  presentationFrames: <PresentationFrameDefinition>[
    PresentationFrameDefinition(
      id: PresentationFrameId('desktop-frame'),
      displayName: 'Desktop frame',
      kind: PresentationFrameKind.browser,
      formFactorId: FormFactorId('desktop'),
    ),
    PresentationFrameDefinition(
      id: PresentationFrameId('phone-frame'),
      displayName: 'Phone frame',
      kind: PresentationFrameKind.device,
      formFactorId: FormFactorId('phone'),
    ),
  ],
  scenarioFacets: <ScenarioFacet>[
    ScenarioFacet(
      scenarioId: ScenarioId('alpha'),
      lifecycle: ScenarioLifecycle.current,
      scenarioKindId: ScenarioKindId('state'),
      surfaceId: ExperienceSurfaceId('sample-surface'),
      stateId: ScenarioStateId('ready'),
      ownershipAreaId: OwnershipAreaId('team-a'),
      tagIds: <ScenarioTagId>[ScenarioTagId('critical')],
      componentIds: <ExperienceComponentId>[
        ExperienceComponentId('alpha-panel'),
      ],
      fixtureId: ScenarioFixtureId('fixture-a'),
      renderSource: ExternalHarnessRenderSource(
        providerId: RenderProviderId('provider-a'),
        harnessId: RenderHarnessId('harness-a'),
      ),
      presentationFrameIds: <PresentationFrameId>[
        PresentationFrameId('phone-frame'),
      ],
      preferredPresentationFrameId: PresentationFrameId('phone-frame'),
    ),
    ScenarioFacet(
      scenarioId: ScenarioId('beta'),
      lifecycle: ScenarioLifecycle.concept,
      scenarioKindId: ScenarioKindId('operation'),
      surfaceId: ExperienceSurfaceId('sample-surface'),
      stateId: ScenarioStateId('loading'),
      ownershipAreaId: OwnershipAreaId('team-b'),
      tagIds: <ScenarioTagId>[ScenarioTagId('secondary')],
      componentIds: <ExperienceComponentId>[
        ExperienceComponentId('beta-panel'),
      ],
      fixtureId: ScenarioFixtureId('fixture-b'),
      renderSource: ExternalHarnessRenderSource(
        providerId: RenderProviderId('provider-b'),
        harnessId: RenderHarnessId('harness-b'),
      ),
      presentationFrameIds: <PresentationFrameId>[
        PresentationFrameId('desktop-frame'),
      ],
      preferredPresentationFrameId: PresentationFrameId('desktop-frame'),
    ),
  ],
);
