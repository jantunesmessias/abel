import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ExperienceTopologyManifest', () {
    test('round-trips, validates schema, and preserves catalog identity', () {
      final catalog = _catalog();
      final catalogBefore = const JcsCanonicalizer().canonicalize(
        catalog.toJson(),
      );
      final topology = _topology(catalog);

      final decoded = ExperienceTopologyManifest.fromJson(
        topology.toJson(),
        catalog: catalog,
      );
      final validator = _schemaValidator(
        'experience-topology-manifest.schema.json',
      );

      expect(decoded.toJson(), topology.toJson());
      expect(decoded.digest, topology.digest);
      expect(decoded.boards.single.projectionIds, <ExperienceProjectionId>[
        ExperienceProjectionId('comparison'),
        ExperienceProjectionId('journey'),
      ]);
      expect(
        decoded.nodes
            .singleWhere((item) => item.id == NodeInstanceId('baseline'))
            .comparisonRole,
        ComparisonRole.baseline,
      );
      expect(
        validator.validate(topology.toJson()).isValid,
        isTrue,
        reason: validator.validate(topology.toJson()).issues.join('\n'),
      );
      expect(
        const JcsCanonicalizer().canonicalize(catalog.toJson()),
        catalogBefore,
      );
      expect(CatalogManifest.schemaVersion, 1);
    });

    test('canonicalizes every entity and membership list', () {
      final catalog = _catalog();
      final forward = _topology(catalog);
      final reverse = ExperienceTopologyManifest(
        catalog: catalog,
        boards: forward.boards.reversed.toList(),
        projections: forward.projections.reversed.toList(),
        nodes: forward.nodes.reversed.toList(),
        edges: forward.edges.reversed.toList(),
      );

      expect(reverse.toJson(), forward.toJson());
      expect(reverse.digest, forward.digest);
    });

    test('rejects unknown fields, forged digest, and adjacent version', () {
      final catalog = _catalog();
      final topology = _topology(catalog);

      final unknown = _copy(topology.toJson())..['unexpected'] = true;
      expect(
        () => ExperienceTopologyManifest.fromJson(unknown, catalog: catalog),
        throwsFormatException,
      );

      final forged = _copy(topology.toJson())
        ..['digest'] = Digest.semantic('forged').value;
      expect(
        () => ExperienceTopologyManifest.fromJson(forged, catalog: catalog),
        throwsFormatException,
      );

      final adjacent = _copy(topology.toJson())..['schemaVersion'] = 2;
      _redigest(adjacent);
      expect(
        () => ExperienceTopologyManifest.fromJson(adjacent, catalog: catalog),
        throwsFormatException,
      );
    });

    test('rejects catalog digest mismatch and dangling membership', () {
      final catalog = _catalog();
      final topology = _topology(catalog);
      final otherCatalog = _catalog(workspaceName: 'Other workspace');

      expect(
        () => ExperienceTopologyManifest.fromJson(
          topology.toJson(),
          catalog: otherCatalog,
        ),
        throwsFormatException,
      );

      final dangling = _copy(topology.toJson());
      final projections = dangling['projections']! as List<Object?>;
      final journey = projections.cast<Map<String, Object?>>().singleWhere(
        (item) => item['id'] == 'journey',
      );
      journey['nodeInstanceIds'] = <String>[
        ...(journey['nodeInstanceIds']! as List<Object?>).cast<String>(),
        'missing-node',
      ];
      _redigest(dangling);

      expect(
        () => ExperienceTopologyManifest.fromJson(dangling, catalog: catalog),
        throwsArgumentError,
      );
    });

    test('rejects cross-Application nodes', () {
      final catalog = _catalog();
      final invalid = _copy(_topology(catalog).toJson());
      final nodes = invalid['nodes']! as List<Object?>;
      final start = nodes.cast<Map<String, Object?>>().singleWhere(
        (item) => item['id'] == 'start',
      );
      start['scenarioId'] = 'foreign';
      _redigest(invalid);

      expect(
        () => ExperienceTopologyManifest.fromJson(invalid, catalog: catalog),
        throwsArgumentError,
      );
    });

    test('scopes canonical, baseline and candidate roles to comparisons', () {
      final canonical = NodeInstance.fromJson(<String, Object?>{
        'id': 'canonical',
        'projectionId': 'comparison',
        'scenarioId': 'ready',
        'comparisonRole': 'canonical',
      });
      expect(canonical.comparisonRole, ComparisonRole.canonical);

      final catalog = _catalog();
      final roleOutsideComparison = _copy(_topology(catalog).toJson());
      final journeyNodes = roleOutsideComparison['nodes']! as List<Object?>;
      journeyNodes.cast<Map<String, Object?>>().singleWhere(
        (item) => item['id'] == 'start',
      )['comparisonRole'] = 'canonical';
      _redigest(roleOutsideComparison);
      expect(
        () => ExperienceTopologyManifest.fromJson(
          roleOutsideComparison,
          catalog: catalog,
        ),
        throwsArgumentError,
      );

      final missingCandidate = _copy(_topology(catalog).toJson());
      final comparisonNodes = missingCandidate['nodes']! as List<Object?>;
      comparisonNodes
          .cast<Map<String, Object?>>()
          .singleWhere((item) => item['id'] == 'candidate')
          .remove('comparisonRole');
      _redigest(missingCandidate);
      expect(
        () => ExperienceTopologyManifest.fromJson(
          missingCandidate,
          catalog: catalog,
        ),
        throwsArgumentError,
      );
    });

    test('rejects reversed or semantically mismatched edge endpoints', () {
      final catalog = _catalog();
      final invalid = _copy(_topology(catalog).toJson());
      final edges = invalid['edges']! as List<Object?>;
      final edge = edges.cast<Map<String, Object?>>().singleWhere(
        (item) => item['id'] == 'start-ready-edge',
      );
      edge
        ..['fromNodeId'] = 'ready'
        ..['toNodeId'] = 'start';
      _redigest(invalid);

      expect(
        () => ExperienceTopologyManifest.fromJson(invalid, catalog: catalog),
        throwsArgumentError,
      );
    });

    test('enforces unique IDs and bounded text', () {
      final catalog = _catalog();
      final topology = _topology(catalog);

      expect(
        () => ExperienceTopologyManifest(
          catalog: catalog,
          boards: <Board>[...topology.boards, topology.boards.single],
          projections: topology.projections,
          nodes: topology.nodes,
          edges: topology.edges,
        ),
        throwsArgumentError,
      );
      expect(
        () => Board(
          id: BoardId('oversized'),
          applicationId: ApplicationId('app'),
          title: 'x' * 2049,
          projectionIds: const <ExperienceProjectionId>[],
        ),
        throwsArgumentError,
      );
    });
  });
}

CatalogManifest _catalog({String workspaceName = 'Workspace'}) {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final appId = ApplicationId('app');
  final otherAppId = ApplicationId('other-app');
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
        id: appId,
        workspaceId: workspaceId,
        displayName: 'App',
        root: 'apps/app',
        target: 'web',
      ),
      Application(
        id: otherAppId,
        workspaceId: workspaceId,
        displayName: 'Other App',
        root: 'apps/other',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('delivery'),
        applicationId: appId,
        title: 'Delivery',
        scenarioIds: <ScenarioId>[ScenarioId('start'), ScenarioId('ready')],
      ),
      Journey(
        id: JourneyId('foreign-journey'),
        applicationId: otherAppId,
        title: 'Foreign',
        scenarioIds: <ScenarioId>[ScenarioId('foreign')],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(id: ScenarioId('start'), applicationId: appId, title: 'Start'),
      Scenario(id: ScenarioId('ready'), applicationId: appId, title: 'Ready'),
      Scenario(
        id: ScenarioId('foreign'),
        applicationId: otherAppId,
        title: 'Foreign',
      ),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('start-ready'),
        journeyId: JourneyId('delivery'),
        from: ScenarioId('start'),
        to: ScenarioId('ready'),
      ),
    ],
  );
}

ExperienceTopologyManifest _topology(CatalogManifest catalog) {
  final journeyId = ExperienceProjectionId('journey');
  final comparisonId = ExperienceProjectionId('comparison');
  return ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: BoardId('delivery-board'),
        applicationId: ApplicationId('app'),
        title: 'Delivery board',
        projectionIds: <ExperienceProjectionId>[journeyId, comparisonId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: journeyId,
        boardId: BoardId('delivery-board'),
        applicationId: ApplicationId('app'),
        title: 'Journey',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('delivery'),
        nodeInstanceIds: <NodeInstanceId>[
          NodeInstanceId('start'),
          NodeInstanceId('ready'),
        ],
        edgeInstanceIds: <EdgeInstanceId>[EdgeInstanceId('start-ready-edge')],
      ),
      ExperienceProjection(
        id: comparisonId,
        boardId: BoardId('delivery-board'),
        applicationId: ApplicationId('app'),
        title: 'Comparison',
        kind: ProjectionKind.comparison,
        nodeInstanceIds: <NodeInstanceId>[
          NodeInstanceId('baseline'),
          NodeInstanceId('candidate'),
        ],
        edgeInstanceIds: const <EdgeInstanceId>[],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: NodeInstanceId('start'),
        projectionId: journeyId,
        scenarioId: ScenarioId('start'),
      ),
      NodeInstance(
        id: NodeInstanceId('ready'),
        projectionId: journeyId,
        scenarioId: ScenarioId('ready'),
      ),
      NodeInstance(
        id: NodeInstanceId('baseline'),
        projectionId: comparisonId,
        scenarioId: ScenarioId('ready'),
        comparisonRole: ComparisonRole.baseline,
      ),
      NodeInstance(
        id: NodeInstanceId('candidate'),
        projectionId: comparisonId,
        scenarioId: ScenarioId('ready'),
        comparisonRole: ComparisonRole.candidate,
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: EdgeInstanceId('start-ready-edge'),
        projectionId: journeyId,
        transitionId: TransitionId('start-ready'),
        fromNodeId: NodeInstanceId('start'),
        toNodeId: NodeInstanceId('ready'),
      ),
    ],
  );
}

Draft202012Validator _schemaValidator(String name) => Draft202012Validator(
  jsonDecode(
        File(p.join(_root(), 'schemas', 'catalog', name)).readAsStringSync(),
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
