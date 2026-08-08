import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'layout-only refresh is atomic and preserves Workspace Evidence state',
    () {
      final catalog = _catalog();
      final initialBundle = _bundle(catalog, cameraX: 0);
      var nextContent = HostWorkspaceContent(
        catalog: catalog,
        experienceBundle: initialBundle,
      );
      final workspace = HostWorkspaceService(
        initialCatalog: catalog,
        initialExperienceBundle: initialBundle,
        clock: SystemClock(),
        reloadContent: () => nextContent,
      )..initialize(_kitManifest());
      final variant = Variant(
        id: VariantId('phone'),
        applicationId: ApplicationId('app'),
        logicalWidth: 390,
        logicalHeight: 844,
        devicePixelRatio: 1,
        brightness: PreviewBrightness.light,
        localeTag: 'en-US',
      );
      final artifactDigest = Digest.semantic('artifact');
      final handle = ResourceHandle(
        uri: Uri.parse(
          'http://127.0.0.1:4000/resources/'
          '0123456789abcdef0123456789abcdef',
        ),
        digest: artifactDigest,
        mediaType: 'image/png',
        size: 1,
        purpose: 'visual-artifact',
        expiresAt: DateTime.utc(2026, 8, 13, 13),
      );
      workspace.replaceVisualState(
        variantManifest: VariantManifest(
          catalogDigest: catalog.digest,
          variants: <Variant>[variant],
          sources: <VariantDefinitionSource>[
            VariantDefinitionSource(
              variantId: variant.id,
              sourceId: 'test.source',
              sourceDigest: Digest.semantic('source'),
            ),
          ],
        ),
        projections: <VisualEvidenceProjection>[
          VisualEvidenceProjection(
            providerId: ModuleId('evidence.auto-preview'),
            scenarioId: ScenarioId('a'),
            variantId: variant.id,
            evidenceDigest: Digest.semantic('evidence'),
            artifactDigest: artifactDigest,
            status: VisualEvidenceStatus.collected,
            freshness: EvidenceFreshness.fresh,
            fidelity: RuntimeFidelity.structural,
            observedAt: DateTime.utc(2026, 8, 13, 12),
            artifactHandle: handle,
          ),
        ],
      );
      final beforeSnapshot = workspace.snapshot;
      final beforeDescription = workspace.describeExperience();

      nextContent = HostWorkspaceContent(
        catalog: catalog,
        experienceBundle: _bundle(catalog, cameraX: 250),
      );
      final result = workspace.refreshContent(_kitManifest());

      expect(result.catalogChanged, isFalse);
      expect(result.experienceChanged, isTrue);
      expect(result.layoutOnlyChanged, isTrue);
      expect(identical(workspace.snapshot, beforeSnapshot), isTrue);
      expect(workspace.snapshot.catalog.digest, catalog.digest);
      expect(
        workspace.snapshot.variantManifest.digest,
        beforeSnapshot.variantManifest.digest,
      );
      expect(
        workspace.snapshot.visualProjections.single.toJson(),
        beforeSnapshot.visualProjections.single.toJson(),
      );
      expect(
        workspace.describeExperience()['revision'],
        (beforeDescription['revision']! as int) + 1,
      );
      expect(
        workspace.describeExperience()['topologyDigest'],
        beforeDescription['topologyDigest'],
      );
      expect(
        workspace.describeExperience()['bundleDigest'],
        isNot(beforeDescription['bundleDigest']),
      );
    },
  );

  test(
    'failed content reload leaves catalog and Experience atomically intact',
    () {
      final catalog = _catalog();
      final bundle = _bundle(catalog, cameraX: 0);
      final workspace = HostWorkspaceService(
        initialCatalog: catalog,
        initialExperienceBundle: bundle,
        clock: SystemClock(),
        reloadContent: () => throw const FormatException('invalid content'),
      )..initialize(_kitManifest());
      final beforeSnapshot = workspace.snapshot;
      final beforeExperience = workspace.describeExperience();

      expect(
        () => workspace.refreshContent(_kitManifest()),
        throwsFormatException,
      );
      expect(identical(workspace.snapshot, beforeSnapshot), isTrue);
      expect(workspace.describeExperience(), beforeExperience);
    },
  );
}

EffectiveKitManifest _kitManifest() => EffectiveKitManifest(
  resolvedPlanDigest: Digest.semantic('plan'),
  modules: <EffectiveModuleState>[
    EffectiveModuleState(
      moduleId: ModuleId('evidence.auto-preview'),
      state: ModuleRuntimeState.ready,
      health: ModuleHealth.healthy,
      effectiveCapabilities: const <ModuleCapabilityRef>[],
    ),
  ],
  commands: const <String>[],
  rpcMethods: const <String>[],
  studioContributions: const <String>[],
  generatedAt: DateTime.utc(2026, 8, 13, 12),
);

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('app');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
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
  );
}

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
