@TestOn('vm')
library;

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/jaspr/motion_context_pages.dart';
import 'package:studio_ui/studio_ui.dart';

void main() {
  testComponents('Motion keeps a complete static equivalent in every mode', (
    tester,
  ) async {
    final fixture = _motionFixture();
    tester.pumpComponent(
      MotionPage(
        enabled: true,
        projectionId: fixture.projectionId,
        bundle: fixture.bundle,
        motion: fixture.motion,
        scenarioId: ScenarioId('understand'),
      ),
    );

    expect(find.text('Full'), findsOneComponent);
    expect(find.text('Reduced'), findsOneComponent);
    expect(find.text('None'), findsOneComponent);
    expect(
      find.text('Descobrir aparece antes de compreender.'),
      findsOneComponent,
    );
    expect(
      find.textContaining('movimento não contém informação exclusiva'),
      findsOneComponent,
    );
    expect(_domWithAttribute('data-motion-mode', 'full'), findsOneComponent);

    await tester.click(find.componentWithText(StudioButton, 'None'));
    await tester.click(
      find.componentWithText(StudioButton, 'Executar sequência'),
    );

    expect(_domWithAttribute('data-motion-mode', 'none'), findsOneComponent);
    expect(find.textContaining('1 etapas · 0 ms'), findsOneComponent);
    expect(
      find.text('Descobrir aparece antes de compreender.'),
      findsOneComponent,
    );
  });

  testComponents(
    'Context Builder exposes independent budgets and a deterministic result',
    (tester) async {
      final digest = Digest.semantic('content');
      final selection = ContextSelection(
        boardId: BoardId('board'),
        projectionId: ExperienceProjectionId('projection'),
        journeyId: JourneyId('sample'),
        scenarioId: ScenarioId('understand'),
      );
      final client = _ContextClient(digest);
      tester.pumpComponent(
        ContextBuilderPage(
          enabled: true,
          contentSetDigest: digest,
          selection: selection,
          client: client,
        ),
      );
      await tester.pump();

      for (final label in const <String>[
        'Fontes',
        'Imagens',
        'Evidências',
        'História',
        'Mudanças',
      ]) {
        expect(find.text(label), findsOneComponent);
      }
      for (final category in ContextCategory.values) {
        expect(find.text(category.name), findsOneComponent);
      }

      await tester.click(
        find.componentWithText(StudioButton, 'Exportar contexto'),
      );
      await tester.pump();

      expect(client.buildCalls, 1);
      expect(
        client.lastRequest?.selection.scenarioId,
        ScenarioId('understand'),
      );
      expect(find.text('Export sanitizado'), findsOneComponent);
      expect(find.textContaining('0 itens · 5 omissões'), findsOneComponent);
      expect(
        _domWithAttribute('data-context-state', 'ready'),
        findsOneComponent,
      );
      expect(find.textContaining('/home/'), findsNothing);
      expect(find.textContaining('Bearer '), findsNothing);
    },
  );
}

final class _ContextClient implements StudioHostContextBuilderClient {
  _ContextClient(this.contentSetDigest);

  final Digest contentSetDigest;
  var buildCalls = 0;
  ContextBuildRequest? lastRequest;

  @override
  Future<ContextBuilderDescription> describeContextBuilder() async =>
      ContextBuilderDescription(
        contentSetDigest: contentSetDigest,
        supportedCategories: ContextCategory.values.toSet(),
        maximumBudgets: _budgets(),
      );

  @override
  Future<ContextBuildResult> buildContext(ContextBuildRequest request) async {
    buildCalls += 1;
    lastRequest = request;
    return ContextBuildResult(
      bundle: ExperienceContextBundle(
        contentSetDigest: contentSetDigest,
        selection: request.selection,
        inclusion: request.inclusion,
        requestedBudgets: request.budgets,
        effectiveBudgets: request.budgets,
        items: const <ContextItem>[],
        usage: <ContextCategory, ContextUsage>{
          for (final category in ContextCategory.values)
            category: ContextUsage(items: 0, bytes: 0),
        },
        omissions: <ContextOmission>[
          for (final category in ContextCategory.values)
            ContextOmission(
              category: category,
              subject: category.name,
              reason: ContextOmissionReason.unavailable,
            ),
        ],
      ),
    );
  }
}

ContextBudgets _budgets() => ContextBudgets(
  categories: <ContextCategory, ContextCategoryBudget>{
    for (final category in ContextCategory.values)
      category: ContextCategoryBudget(maxItems: 32, maxBytes: 128 * 1024),
  },
);

_MotionFixture _motionFixture() {
  final catalog = sampleCatalogManifest();
  final projectionId = ExperienceProjectionId('projection');
  final boardId = BoardId('board');
  final from = NodeInstanceId('discover-node');
  final to = NodeInstanceId('understand-node');
  final edge = EdgeInstanceId('discover-understand-edge');
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Board',
        projectionIds: <ExperienceProjectionId>[projectionId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: projectionId,
        boardId: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Projection',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('sample'),
        nodeInstanceIds: <NodeInstanceId>[from, to],
        edgeInstanceIds: <EdgeInstanceId>[edge],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: from,
        projectionId: projectionId,
        scenarioId: ScenarioId('discover'),
      ),
      NodeInstance(
        id: to,
        projectionId: projectionId,
        scenarioId: ScenarioId('understand'),
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: edge,
        projectionId: projectionId,
        transitionId: TransitionId('discover-understand'),
        fromNodeId: from,
        toNodeId: to,
      ),
    ],
  );
  final layout = ProjectionLayoutManifest(
    topologyDigest: topology.digest,
    projectionId: projectionId,
    nodeFrames: <ProjectionNodeFrame>[
      ProjectionNodeFrame(
        nodeInstanceId: from,
        x: 0,
        y: 0,
        width: 200,
        height: 120,
      ),
      ProjectionNodeFrame(
        nodeInstanceId: to,
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
        title: 'Fluxo de compreensão',
        staticSummary: 'Descobrir aparece antes de compreender.',
        steps: <MotionTransitionStep>[
          MotionTransitionStep(
            id: 'discover-to-understand',
            transitionId: TransitionId('discover-understand'),
            fromNodeId: from,
            toNodeId: to,
            startMs: 0,
            fullDurationMs: 420,
            reducedDurationMs: 80,
            easing: MotionEasing.easeInOut,
            observations: <MotionObservation>[
              MotionObservation(
                id: 'understand-visible',
                label: 'Compreender fica visível',
                atFraction: 1,
                kind: MotionObservationKind.stateVisible,
              ),
            ],
          ),
        ],
      ),
    ],
  )..validateAgainst(catalog: catalog, topology: topology);
  return _MotionFixture(
    projectionId: projectionId,
    bundle: bundle,
    motion: motion,
  );
}

final class _MotionFixture {
  const _MotionFixture({
    required this.projectionId,
    required this.bundle,
    required this.motion,
  });

  final ExperienceProjectionId projectionId;
  final ExperienceTopologyBundle bundle;
  final MotionManifest motion;
}

Finder _domWithAttribute(String name, String value) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent && component.attributes?[name] == value,
      description: 'DOM component with $name=$value',
    );
