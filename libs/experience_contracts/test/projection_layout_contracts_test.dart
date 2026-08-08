import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ProjectionLayoutManifest', () {
    test('round-trips, validates schema, and binds to its topology', () {
      final topology = _topology();
      final layout = _layout(topology);

      final decoded = ProjectionLayoutManifest.fromJson(layout.toJson());
      decoded.validateAgainst(topology);
      final validator = _schemaValidator(
        'projection-layout-manifest.schema.json',
      );

      expect(decoded.toJson(), layout.toJson());
      expect(decoded.digest, layout.digest);
      expect(decoded.nodeFrames.first.nodeInstanceId, NodeInstanceId('ready'));
      expect(
        validator.validate(layout.toJson()).isValid,
        isTrue,
        reason: validator.validate(layout.toJson()).issues.join('\n'),
      );
    });

    test('canonicalizes collections without changing topology identity', () {
      final topology = _topology();
      final forward = _layout(topology);
      final reverse = ProjectionLayoutManifest(
        topologyDigest: topology.digest,
        projectionId: ExperienceProjectionId('journey'),
        nodeFrames: forward.nodeFrames.reversed.toList(),
        groups: forward.groups.reversed.toList(),
        lanes: forward.lanes.reversed.toList(),
        annotations: forward.annotations.reversed.toList(),
        camera: forward.camera,
      );
      final moved = ProjectionLayoutManifest(
        topologyDigest: topology.digest,
        projectionId: forward.projectionId,
        nodeFrames: <ProjectionNodeFrame>[
          for (final frame in forward.nodeFrames)
            ProjectionNodeFrame(
              nodeInstanceId: frame.nodeInstanceId,
              x: frame.x + 10,
              y: frame.y,
              width: frame.width,
              height: frame.height,
              groupId: frame.groupId,
              laneId: frame.laneId,
            ),
        ],
        groups: forward.groups,
        lanes: forward.lanes,
        annotations: forward.annotations,
        camera: forward.camera,
      );

      expect(reverse.toJson(), forward.toJson());
      expect(reverse.digest, forward.digest);
      expect(moved.digest, isNot(forward.digest));
      expect(moved.topologyDigest, topology.digest);
      expect(topology.digest, _topology().digest);
    });

    test('rejects unknown fields, forged digest, and adjacent version', () {
      final layout = _layout(_topology());

      final unknown = _copy(layout.toJson())..['unexpected'] = true;
      expect(
        () => ProjectionLayoutManifest.fromJson(unknown),
        throwsFormatException,
      );

      final forged = _copy(layout.toJson())
        ..['digest'] = Digest.semantic('forged').value;
      expect(
        () => ProjectionLayoutManifest.fromJson(forged),
        throwsFormatException,
      );

      final adjacent = _copy(layout.toJson())..['schemaVersion'] = 2;
      _redigest(adjacent);
      expect(
        () => ProjectionLayoutManifest.fromJson(adjacent),
        throwsFormatException,
      );
    });

    test('rejects dangling topology, projection, group, and node refs', () {
      final topology = _topology();
      final layout = _layout(topology);
      final wrongDigest = ProjectionLayoutManifest(
        topologyDigest: Digest.semantic('other'),
        projectionId: layout.projectionId,
        nodeFrames: layout.nodeFrames,
        groups: layout.groups,
        lanes: layout.lanes,
        annotations: layout.annotations,
        camera: layout.camera,
      );
      expect(() => wrongDigest.validateAgainst(topology), throwsArgumentError);

      final unknownGroup = _copy(layout.toJson());
      final frames = unknownGroup['nodeFrames']! as List<Object?>;
      (frames.first! as Map<String, Object?>)['groupId'] = 'missing-group';
      _redigest(unknownGroup);
      expect(
        () => ProjectionLayoutManifest.fromJson(
          unknownGroup,
        ).validateAgainst(topology),
        throwsArgumentError,
      );

      final unknownNode = _copy(layout.toJson());
      final unknownNodeFrames = unknownNode['nodeFrames']! as List<Object?>;
      (unknownNodeFrames.first! as Map<String, Object?>)['nodeInstanceId'] =
          'missing-node';
      _redigest(unknownNode);
      expect(
        () => ProjectionLayoutManifest.fromJson(
          unknownNode,
        ).validateAgainst(topology),
        throwsArgumentError,
      );
    });

    test('rejects non-finite, negative-zero, and out-of-bound geometry', () {
      for (final value in <double>[
        double.nan,
        double.infinity,
        -double.infinity,
        -0.0,
        1000001,
      ]) {
        expect(
          () => ProjectionNodeFrame(
            nodeInstanceId: NodeInstanceId('node'),
            x: value,
            y: 0,
            width: 100,
            height: 100,
          ),
          throwsArgumentError,
          reason: '$value',
        );
      }
      expect(
        () => ProjectionCamera(x: 0, y: 0, zoom: 64.01),
        throwsArgumentError,
      );
      expect(
        () => ProjectionAnnotation(
          id: ProjectionAnnotationId('oversized'),
          text: 'x' * 16385,
          x: 0,
          y: 0,
          width: 100,
          height: 100,
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate frame IDs and incomplete projection coverage', () {
      final topology = _topology();
      final layout = _layout(topology);

      expect(
        () => ProjectionLayoutManifest(
          topologyDigest: topology.digest,
          projectionId: layout.projectionId,
          nodeFrames: <ProjectionNodeFrame>[
            layout.nodeFrames.first,
            layout.nodeFrames.first,
          ],
          groups: layout.groups,
          lanes: layout.lanes,
          annotations: layout.annotations,
          camera: layout.camera,
        ),
        throwsArgumentError,
      );

      final incomplete = ProjectionLayoutManifest(
        topologyDigest: topology.digest,
        projectionId: layout.projectionId,
        nodeFrames: <ProjectionNodeFrame>[layout.nodeFrames.first],
        groups: layout.groups,
        lanes: layout.lanes,
        annotations: layout.annotations,
        camera: layout.camera,
      );
      expect(() => incomplete.validateAgainst(topology), throwsArgumentError);
    });
  });
}

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final appId = ApplicationId('app');
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
        id: appId,
        workspaceId: workspaceId,
        displayName: 'App',
        root: 'apps/app',
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
    ],
    scenarios: <Scenario>[
      Scenario(id: ScenarioId('start'), applicationId: appId, title: 'Start'),
      Scenario(id: ScenarioId('ready'), applicationId: appId, title: 'Ready'),
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

ExperienceTopologyManifest _topology() {
  final catalog = _catalog();
  final projectionId = ExperienceProjectionId('journey');
  return ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: BoardId('delivery-board'),
        applicationId: ApplicationId('app'),
        title: 'Delivery',
        projectionIds: <ExperienceProjectionId>[projectionId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: projectionId,
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
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: NodeInstanceId('start'),
        projectionId: projectionId,
        scenarioId: ScenarioId('start'),
      ),
      NodeInstance(
        id: NodeInstanceId('ready'),
        projectionId: projectionId,
        scenarioId: ScenarioId('ready'),
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: EdgeInstanceId('start-ready-edge'),
        projectionId: projectionId,
        transitionId: TransitionId('start-ready'),
        fromNodeId: NodeInstanceId('start'),
        toNodeId: NodeInstanceId('ready'),
      ),
    ],
  );
}

ProjectionLayoutManifest _layout(ExperienceTopologyManifest topology) =>
    ProjectionLayoutManifest(
      topologyDigest: topology.digest,
      projectionId: ExperienceProjectionId('journey'),
      nodeFrames: <ProjectionNodeFrame>[
        ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('start'),
          x: 0,
          y: 0,
          width: 390,
          height: 844,
          groupId: ProjectionGroupId('main-flow'),
          laneId: ProjectionLaneId('customer'),
        ),
        ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('ready'),
          x: 520,
          y: 0,
          width: 390,
          height: 844,
          groupId: ProjectionGroupId('main-flow'),
          laneId: ProjectionLaneId('customer'),
        ),
      ],
      groups: <ProjectionGroup>[
        ProjectionGroup(
          id: ProjectionGroupId('main-flow'),
          title: 'Main flow',
          x: -40,
          y: -40,
          width: 990,
          height: 924,
        ),
      ],
      lanes: <ProjectionLane>[
        ProjectionLane(
          id: ProjectionLaneId('customer'),
          title: 'Customer',
          x: -20,
          y: -20,
          width: 950,
          height: 884,
        ),
      ],
      annotations: <ProjectionAnnotation>[
        ProjectionAnnotation(
          id: ProjectionAnnotationId('intent'),
          text: 'Inspect the delivery states.',
          x: 0,
          y: -180,
          width: 420,
          height: 100,
        ),
      ],
      camera: ProjectionCamera(x: 400, y: 360, zoom: 0.8),
    );

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
