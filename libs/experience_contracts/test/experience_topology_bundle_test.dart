import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ExperienceTopologyBundle', () {
    test('round-trips, validates schema and canonically orders layouts', () {
      final catalog = _catalog();
      final topology = _topology(catalog);
      final bundle = ExperienceTopologyBundle(
        catalog: catalog,
        topology: topology,
        layouts: <ProjectionLayoutManifest>[
          _layout(topology, 'z-layout', 'z-node', x: 300),
          _layout(topology, 'a-layout', 'a-node', x: 0),
        ],
      );

      expect(
        bundle.layouts.map((layout) => layout.projectionId.value),
        <String>['a-layout', 'z-layout'],
      );
      expect(_validator().validate(bundle.toJson()).isValid, isTrue);

      final decoded = ExperienceTopologyBundle.fromJson(
        jsonDecode(jsonEncode(bundle.toJson())),
        catalog: catalog,
      );
      expect(decoded.digest, bundle.digest);
      expect(decoded.toJson(), bundle.toJson());
    });

    test('strict codec rejects unknown fields and digest tampering', () {
      final catalog = _catalog();
      final topology = _topology(catalog);
      final bundle = ExperienceTopologyBundle(
        catalog: catalog,
        topology: topology,
        layouts: <ProjectionLayoutManifest>[
          _layout(topology, 'a-layout', 'a-node', x: 0),
          _layout(topology, 'z-layout', 'z-node', x: 300),
        ],
      );
      final unknown = _copy(bundle.toJson())..['extra'] = true;
      expect(
        () => ExperienceTopologyBundle.fromJson(unknown, catalog: catalog),
        throwsFormatException,
      );

      final tampered = _copy(bundle.toJson());
      final layouts = tampered['layouts']! as List<Object?>;
      final first = layouts.first! as Map<String, Object?>;
      final camera = first['camera']! as Map<String, Object?>;
      camera['x'] = 99;
      expect(
        () => ExperienceTopologyBundle.fromJson(tampered, catalog: catalog),
        throwsFormatException,
      );
    });

    test('rejects duplicate layouts and catalog mismatch', () {
      final catalog = _catalog();
      final topology = _topology(catalog);
      final layout = _layout(topology, 'a-layout', 'a-node', x: 0);
      expect(
        () => ExperienceTopologyBundle(
          catalog: catalog,
          topology: topology,
          layouts: <ProjectionLayoutManifest>[layout, layout],
        ),
        throwsArgumentError,
      );

      final otherCatalog = CatalogManifest(
        distribution: catalog.distribution,
        layout: catalog.layout,
        workspace: Workspace(
          id: catalog.workspace.id,
          displayName: 'Changed workspace',
        ),
        applications: catalog.applications,
        journeys: catalog.journeys,
        scenarios: catalog.scenarios,
        transitions: catalog.transitions,
      );
      expect(
        () => ExperienceTopologyBundle.fromJson(
          ExperienceTopologyBundle(
            catalog: catalog,
            topology: topology,
            layouts: <ProjectionLayoutManifest>[
              _layout(topology, 'a-layout', 'a-node', x: 0),
              _layout(topology, 'z-layout', 'z-node', x: 300),
            ],
          ).toJson(),
          catalog: otherCatalog,
        ),
        throwsFormatException,
      );
    });
  });
}

CatalogManifest _catalog() {
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('app');
  final layout = ConsumerLayout.standard;
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
        root: 'apps/app',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('flow'),
        applicationId: applicationId,
        title: 'Flow',
        scenarioIds: <ScenarioId>[ScenarioId('a'), ScenarioId('z')],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(id: ScenarioId('a'), applicationId: applicationId, title: 'A'),
      Scenario(id: ScenarioId('z'), applicationId: applicationId, title: 'Z'),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('a-z'),
        journeyId: JourneyId('flow'),
        from: ScenarioId('a'),
        to: ScenarioId('z'),
      ),
    ],
  );
}

ExperienceTopologyManifest _topology(CatalogManifest catalog) {
  final aProjection = ExperienceProjectionId('a-layout');
  final zProjection = ExperienceProjectionId('z-layout');
  return ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: BoardId('board'),
        applicationId: ApplicationId('app'),
        title: 'Board',
        projectionIds: <ExperienceProjectionId>[zProjection, aProjection],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: zProjection,
        boardId: BoardId('board'),
        applicationId: ApplicationId('app'),
        title: 'Z',
        kind: ProjectionKind.inventory,
        nodeInstanceIds: <NodeInstanceId>[NodeInstanceId('z-node')],
        edgeInstanceIds: const <EdgeInstanceId>[],
      ),
      ExperienceProjection(
        id: aProjection,
        boardId: BoardId('board'),
        applicationId: ApplicationId('app'),
        title: 'A',
        kind: ProjectionKind.inventory,
        nodeInstanceIds: <NodeInstanceId>[NodeInstanceId('a-node')],
        edgeInstanceIds: const <EdgeInstanceId>[],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: NodeInstanceId('z-node'),
        projectionId: zProjection,
        scenarioId: ScenarioId('z'),
      ),
      NodeInstance(
        id: NodeInstanceId('a-node'),
        projectionId: aProjection,
        scenarioId: ScenarioId('a'),
      ),
    ],
    edges: const <EdgeInstance>[],
  );
}

ProjectionLayoutManifest _layout(
  ExperienceTopologyManifest topology,
  String projectionId,
  String nodeId, {
  required double x,
}) => ProjectionLayoutManifest(
  topologyDigest: topology.digest,
  projectionId: ExperienceProjectionId(projectionId),
  nodeFrames: <ProjectionNodeFrame>[
    ProjectionNodeFrame(
      nodeInstanceId: NodeInstanceId(nodeId),
      x: x,
      y: 0,
      width: 100,
      height: 100,
    ),
  ],
  groups: const <ProjectionGroup>[],
  lanes: const <ProjectionLane>[],
  annotations: const <ProjectionAnnotation>[],
  camera: ProjectionCamera(x: x, y: 0, zoom: 1),
);

Draft202012Validator _validator() => Draft202012Validator(
  jsonDecode(
        File(
          p.join(
            _root(),
            'schemas/catalog/experience-topology-bundle.schema.json',
          ),
        ).readAsStringSync(),
      )
      as Object,
);

Map<String, Object?> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

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
