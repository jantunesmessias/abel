import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Host exports one deterministic context generation without source paths',
    () {
      final fixture = _fixture();
      final workspace = HostWorkspaceService(
        initialCatalog: fixture.catalog,
        initialExperienceBundle: fixture.bundle,
        initialMotionManifest: fixture.motion,
        clock: _Clock(),
      )..initialize(_manifest());
      final service = HostContextBuilderService(
        workspace: workspace,
        workspaceRoot: '.',
        sourceBacked: false,
      );
      final description = service.describe();
      final request = ContextBuildRequest(
        expectedContentSetDigest: description.contentSetDigest,
        selection: ContextSelection(
          boardId: BoardId('board'),
          projectionId: ExperienceProjectionId('projection'),
          journeyId: JourneyId('sample'),
          scenarioId: ScenarioId('understand'),
        ),
        inclusion: const ContextInclusion(
          sources: true,
          images: true,
          evidence: true,
          history: true,
          changes: true,
        ),
        budgets: description.maximumBudgets,
      );

      final first = service.build(request);
      final second = service.build(request);

      expect(
        description.supportedCategories,
        isNot(contains(ContextCategory.sources)),
      );
      expect(first.bundle.digest, second.bundle.digest);
      expect(first.bundle.toJson(), second.bundle.toJson());
      expect(
        first.bundle.items.any(
          (item) =>
              item.category == ContextCategory.images &&
              item.content.contains('"imageBytesIncluded":false'),
        ),
        isTrue,
      );
      expect(
        first.bundle.items.any(
          (item) =>
              item.category == ContextCategory.history &&
              item.content.contains(fixture.motion.digest.value),
        ),
        isTrue,
      );
      expect(
        first.bundle.omissions.any(
          (item) =>
              item.category == ContextCategory.sources &&
              item.reason == ContextOmissionReason.unavailable,
        ),
        isTrue,
      );
      expect(first.bundle.toJson().toString(), isNot(contains('/home/')));
      expect(first.bundle.toJson().toString(), isNot(contains('contentRoot')));
    },
  );

  test('Host fences stale and cross-projection Context selections', () {
    final fixture = _fixture();
    final workspace = HostWorkspaceService(
      initialCatalog: fixture.catalog,
      initialExperienceBundle: fixture.bundle,
      initialMotionManifest: fixture.motion,
      clock: _Clock(),
    )..initialize(_manifest());
    final service = HostContextBuilderService(
      workspace: workspace,
      workspaceRoot: '.',
      sourceBacked: false,
    );
    final budgets = service.describe().maximumBudgets;

    expect(
      () => service.build(
        ContextBuildRequest(
          expectedContentSetDigest: Digest.semantic('stale'),
          selection: ContextSelection(
            boardId: BoardId('board'),
            projectionId: ExperienceProjectionId('projection'),
          ),
          inclusion: const ContextInclusion(
            sources: false,
            images: false,
            evidence: false,
            history: true,
            changes: false,
          ),
          budgets: budgets,
        ),
      ),
      throwsStateError,
    );
    expect(
      () => service.build(
        ContextBuildRequest(
          expectedContentSetDigest:
              workspace.contentSetIdentity.contentSetDigest,
          selection: ContextSelection(
            boardId: BoardId('board'),
            projectionId: ExperienceProjectionId('projection'),
            scenarioId: ScenarioId('review'),
          ),
          inclusion: const ContextInclusion(
            sources: false,
            images: false,
            evidence: false,
            history: true,
            changes: false,
          ),
          budgets: budgets,
        ),
      ),
      throwsArgumentError,
    );
  });
}

_Fixture _fixture() {
  final catalog = _catalog();
  final projectionId = ExperienceProjectionId('projection');
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: BoardId('board'),
        applicationId: ApplicationId('app'),
        title: 'Board',
        projectionIds: <ExperienceProjectionId>[projectionId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: projectionId,
        boardId: BoardId('board'),
        applicationId: ApplicationId('app'),
        title: 'Projection',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('sample'),
        nodeInstanceIds: <NodeInstanceId>[
          NodeInstanceId('discover-node'),
          NodeInstanceId('understand-node'),
        ],
        edgeInstanceIds: <EdgeInstanceId>[EdgeInstanceId('next-edge')],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: NodeInstanceId('discover-node'),
        projectionId: projectionId,
        scenarioId: ScenarioId('discover'),
      ),
      NodeInstance(
        id: NodeInstanceId('understand-node'),
        projectionId: projectionId,
        scenarioId: ScenarioId('understand'),
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: EdgeInstanceId('next-edge'),
        projectionId: projectionId,
        transitionId: TransitionId('next'),
        fromNodeId: NodeInstanceId('discover-node'),
        toNodeId: NodeInstanceId('understand-node'),
      ),
    ],
  );
  final layout = ProjectionLayoutManifest(
    topologyDigest: topology.digest,
    projectionId: projectionId,
    nodeFrames: <ProjectionNodeFrame>[
      ProjectionNodeFrame(
        nodeInstanceId: NodeInstanceId('discover-node'),
        x: 0,
        y: 0,
        width: 200,
        height: 120,
      ),
      ProjectionNodeFrame(
        nodeInstanceId: NodeInstanceId('understand-node'),
        x: 280,
        y: 0,
        width: 200,
        height: 120,
      ),
    ],
    groups: const <ProjectionGroup>[],
    lanes: const <ProjectionLane>[],
    annotations: const <ProjectionAnnotation>[],
    camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
  );
  final bundle = ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: <ProjectionLayoutManifest>[layout],
  );
  final motion = MotionManifest(
    catalogDigest: catalog.digest,
    topologyDigest: topology.digest,
    sequences: <MotionSequenceManifest>[
      MotionSequenceManifest(
        id: 'review-motion',
        projectionId: projectionId,
        title: 'Review motion',
        staticSummary: 'Discover is followed by understand.',
        steps: <MotionTransitionStep>[
          MotionTransitionStep(
            id: 'show-understand',
            transitionId: TransitionId('next'),
            fromNodeId: NodeInstanceId('discover-node'),
            toNodeId: NodeInstanceId('understand-node'),
            startMs: 0,
            fullDurationMs: 420,
            reducedDurationMs: 80,
            easing: MotionEasing.easeInOut,
            observations: <MotionObservation>[
              MotionObservation(
                id: 'understand-visible',
                label: 'Understand is visible',
                atFraction: 1,
                kind: MotionObservationKind.stateVisible,
              ),
            ],
          ),
        ],
      ),
    ],
  )..validateAgainst(catalog: catalog, topology: topology);
  return _Fixture(catalog: catalog, bundle: bundle, motion: motion);
}

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(
      id: WorkspaceId('workspace'),
      displayName: 'Workspace',
    ),
    applications: <Application>[
      Application(
        id: ApplicationId('app'),
        workspaceId: WorkspaceId('workspace'),
        displayName: 'App',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('sample'),
        applicationId: ApplicationId('app'),
        title: 'Sample',
        scenarioIds: <ScenarioId>[
          ScenarioId('discover'),
          ScenarioId('understand'),
          ScenarioId('review'),
        ],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(
        id: ScenarioId('discover'),
        applicationId: ApplicationId('app'),
        title: 'Discover',
      ),
      Scenario(
        id: ScenarioId('understand'),
        applicationId: ApplicationId('app'),
        title: 'Understand',
      ),
      Scenario(
        id: ScenarioId('review'),
        applicationId: ApplicationId('app'),
        title: 'Review',
      ),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('next'),
        journeyId: JourneyId('sample'),
        from: ScenarioId('discover'),
        to: ScenarioId('understand'),
      ),
    ],
  );
}

EffectiveKitManifest _manifest() => EffectiveKitManifest(
  resolvedPlanDigest: Digest.semantic('plan'),
  modules: const <EffectiveModuleState>[],
  commands: const <String>[],
  rpcMethods: const <String>[],
  studioContributions: const <String>[],
  generatedAt: DateTime.utc(2026, 8, 17),
);

final class _Clock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 17, 12);

  @override
  int monotonicMicroseconds() => 0;
}

final class _Fixture {
  const _Fixture({
    required this.catalog,
    required this.bundle,
    required this.motion,
  });

  final CatalogManifest catalog;
  final ExperienceTopologyBundle bundle;
  final MotionManifest motion;
}
