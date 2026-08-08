import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  final catalog = const CatalogCompiler().compile(_catalogDocuments());
  final compiled = const ExperienceTopologyCompiler().compile(
    _topologyDocuments(),
    catalog: catalog,
  );
  final topology = compiled.topology;

  test('Motion compiler binds scripts to exact topology transitions', () {
    final manifest = const MotionManifestCompiler().compile(
      <AuthoringDocument>[_motionDocument()],
      catalog: catalog,
      topology: topology,
    );

    expect(manifest.sequences, hasLength(1));
    expect(manifest.sequences.single.totalDurationFor(MotionMode.full), 400);
    expect(manifest.sequences.single.totalDurationFor(MotionMode.reduced), 80);
    expect(manifest.sequences.single.totalDurationFor(MotionMode.none), 0);
    expect(
      () => const MotionManifestCompiler().compile(
        <AuthoringDocument>[_motionDocument(toNodeId: 'first-node')],
        catalog: catalog,
        topology: topology,
      ),
      throwsA(isA<CatalogCompileException>()),
    );
  });

  test(
    'Context builder is deterministic and declares independent omissions',
    () {
      final motion = const MotionManifestCompiler().compile(
        <AuthoringDocument>[_motionDocument()],
        catalog: catalog,
        topology: topology,
      );
      final request = ContextBuildRequest(
        expectedContentSetDigest: Digest.semantic('content'),
        selection: ContextSelection(
          boardId: BoardId('board'),
          projectionId: ExperienceProjectionId('projection'),
          journeyId: JourneyId('journey'),
          scenarioId: ScenarioId('second'),
          changeSetDigest: Digest.semantic('change'),
        ),
        inclusion: const ContextInclusion(
          sources: true,
          images: true,
          evidence: true,
          history: true,
          changes: true,
        ),
        budgets: _budgets(sourceBytes: 4096),
      );
      final inputs = ExperienceContextBuildInputs(
        catalog: catalog,
        topology: topology,
        layouts: compiled.layouts,
        documents: <AuthoringDocument>[
          ..._catalogDocuments(),
          ..._topologyDocuments(),
          _motionDocument(),
          AuthoringDocument(
            schemaVersion: 2,
            kind: AuthoringKind.scenarioFacet,
            id: 'second',
            sourceName: 'secret-poison.yaml',
            spec: const <String, Object?>{
              'scenarioId': 'second',
              'token': 'Bearer CONTEXT_REDACTION_SECRET',
            },
          ),
        ],
        motion: motion,
      );
      const builder = ExperienceContextBuilder();
      final first = builder.build(
        request: request,
        currentContentSetDigest: request.expectedContentSetDigest,
        inputs: inputs,
      );
      final second = builder.build(
        request: request,
        currentContentSetDigest: request.expectedContentSetDigest,
        inputs: inputs,
      );

      expect(first.digest, second.digest);
      expect(first.toJson(), second.toJson());
      expect(first.items, isNotEmpty);
      expect(
        first.items.map((item) => item.content).join(),
        isNot(contains('CONTEXT_REDACTION_SECRET')),
      );
      expect(
        first.omissions,
        contains(
          isA<ContextOmission>()
              .having(
                (item) => item.category,
                'category',
                ContextCategory.evidence,
              )
              .having(
                (item) => item.reason,
                'reason',
                ContextOmissionReason.unavailable,
              ),
        ),
      );

      final tiny = builder.build(
        request: ContextBuildRequest(
          expectedContentSetDigest: request.expectedContentSetDigest,
          selection: request.selection,
          inclusion: request.inclusion,
          budgets: _budgets(sourceBytes: 1),
        ),
        currentContentSetDigest: request.expectedContentSetDigest,
        inputs: inputs,
      );
      expect(tiny.usage[ContextCategory.sources]!.items, 0);
      expect(
        tiny.omissions.any(
          (item) =>
              item.category == ContextCategory.sources &&
              item.reason == ContextOmissionReason.budgetExceeded,
        ),
        isTrue,
      );
    },
  );
}

List<AuthoringDocument> _catalogDocuments() => <AuthoringDocument>[
  _document(1, AuthoringKind.workspace, 'workspace', <String, Object?>{
    'displayName': 'Workspace',
  }),
  _document(1, AuthoringKind.application, 'app', <String, Object?>{
    'workspaceId': 'workspace',
    'displayName': 'Application',
    'root': '.',
    'target': 'web',
  }),
  _document(1, AuthoringKind.scenario, 'first', <String, Object?>{
    'applicationId': 'app',
    'title': 'First',
  }),
  _document(1, AuthoringKind.scenario, 'second', <String, Object?>{
    'applicationId': 'app',
    'title': 'Second',
  }),
  _document(1, AuthoringKind.journey, 'journey', <String, Object?>{
    'applicationId': 'app',
    'title': 'Journey',
    'scenarioIds': <String>['first', 'second'],
  }),
  _document(1, AuthoringKind.transition, 'next', <String, Object?>{
    'journeyId': 'journey',
    'from': 'first',
    'to': 'second',
  }),
];

List<AuthoringDocument> _topologyDocuments() => <AuthoringDocument>[
  _document(2, AuthoringKind.board, 'board', <String, Object?>{
    'applicationId': 'app',
    'title': 'Board',
    'projectionIds': <String>['projection'],
  }),
  _document(
    2,
    AuthoringKind.experienceProjection,
    'projection',
    <String, Object?>{
      'boardId': 'board',
      'applicationId': 'app',
      'title': 'Projection',
      'projectionKind': 'journey',
      'journeyId': 'journey',
      'nodeInstanceIds': <String>['first-node', 'second-node'],
      'edgeInstanceIds': <String>['next-edge'],
    },
  ),
  _document(2, AuthoringKind.nodeInstance, 'first-node', <String, Object?>{
    'projectionId': 'projection',
    'scenarioId': 'first',
  }),
  _document(2, AuthoringKind.nodeInstance, 'second-node', <String, Object?>{
    'projectionId': 'projection',
    'scenarioId': 'second',
  }),
  _document(2, AuthoringKind.edgeInstance, 'next-edge', <String, Object?>{
    'projectionId': 'projection',
    'transitionId': 'next',
    'fromNodeId': 'first-node',
    'toNodeId': 'second-node',
  }),
  _document(2, AuthoringKind.projectionLayout, 'projection', <String, Object?>{
    'projectionId': 'projection',
    'nodeFrames': <Object?>[
      <String, Object?>{
        'nodeInstanceId': 'first-node',
        'x': 0,
        'y': 0,
        'width': 200,
        'height': 120,
      },
      <String, Object?>{
        'nodeInstanceId': 'second-node',
        'x': 260,
        'y': 0,
        'width': 200,
        'height': 120,
      },
    ],
    'groups': <Object?>[],
    'lanes': <Object?>[],
    'annotations': <Object?>[],
    'camera': <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
  }),
];

AuthoringDocument _motionDocument({String toNodeId = 'second-node'}) =>
    _document(
      2,
      AuthoringKind.motionSequence,
      'ready-sequence',
      <String, Object?>{
        'projectionId': 'projection',
        'title': 'Ready transition',
        'staticSummary': 'First state is followed by the ready state.',
        'steps': <Object?>[
          <String, Object?>{
            'id': 'show-ready',
            'transitionId': 'next',
            'fromNodeId': 'first-node',
            'toNodeId': toNodeId,
            'startMs': 0,
            'fullDurationMs': 400,
            'reducedDurationMs': 80,
            'easing': 'easeInOut',
            'observations': <Object?>[
              <String, Object?>{
                'id': 'ready-visible',
                'label': 'Ready content is visible',
                'atFraction': 1,
                'kind': 'stateVisible',
              },
            ],
          },
        ],
      },
    );

AuthoringDocument _document(
  int version,
  AuthoringKind kind,
  String id,
  Map<String, Object?> spec,
) => AuthoringDocument(
  schemaVersion: version,
  kind: kind,
  id: id,
  spec: spec,
  sourceName: '${kind.name}/$id.yaml',
);

ContextBudgets _budgets({required int sourceBytes}) => ContextBudgets(
  categories: <ContextCategory, ContextCategoryBudget>{
    for (final category in ContextCategory.values)
      category: ContextCategoryBudget(
        maxItems: 16,
        maxBytes: category == ContextCategory.sources ? sourceBytes : 4096,
      ),
  },
);
