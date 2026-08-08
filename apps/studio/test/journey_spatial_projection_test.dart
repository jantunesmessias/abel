import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/journey_map/journey_spatial_projection.dart';
import 'package:test/test.dart';

void main() {
  test('keeps missing topology explicit', () {
    final journey = sampleCatalogManifest().journeys.single;

    final resolution = JourneySpatialProjectionResolution.resolve(
      bundle: null,
      journey: journey,
    );

    expect(resolution.status, JourneySpatialProjectionStatus.topologyAbsent);
    expect(resolution.isReady, isFalse);
    expect(resolution.fallbackMessage, contains('não publicou topologia'));
  });

  test('resolves authored node instances, edges and layout by Journey ID', () {
    final catalog = sampleCatalogManifest();
    final journey = catalog.journeys.single;
    final projectionId = ExperienceProjectionId('sample-journey');
    final firstNode = NodeInstanceId('node-discover');
    final secondNode = NodeInstanceId('node-plan');
    final topology = ExperienceTopologyManifest(
      catalog: catalog,
      boards: <Board>[
        Board(
          id: BoardId('sample-board'),
          applicationId: journey.applicationId,
          title: 'Sample board',
          projectionIds: <ExperienceProjectionId>[projectionId],
        ),
      ],
      projections: <ExperienceProjection>[
        ExperienceProjection(
          id: projectionId,
          boardId: BoardId('sample-board'),
          applicationId: journey.applicationId,
          title: 'Sample projection',
          kind: ProjectionKind.journey,
          journeyId: journey.id,
          nodeInstanceIds: <NodeInstanceId>[firstNode, secondNode],
          edgeInstanceIds: <EdgeInstanceId>[
            EdgeInstanceId('edge-discover-plan'),
          ],
        ),
      ],
      nodes: <NodeInstance>[
        NodeInstance(
          id: firstNode,
          projectionId: projectionId,
          scenarioId: journey.scenarioIds.first,
        ),
        NodeInstance(
          id: secondNode,
          projectionId: projectionId,
          scenarioId: journey.scenarioIds[1],
        ),
      ],
      edges: <EdgeInstance>[
        EdgeInstance(
          id: EdgeInstanceId('edge-discover-plan'),
          projectionId: projectionId,
          transitionId: catalog.transitions.first.id,
          fromNodeId: firstNode,
          toNodeId: secondNode,
        ),
      ],
    );
    final layout = ProjectionLayoutManifest(
      topologyDigest: topology.digest,
      projectionId: projectionId,
      nodeFrames: <ProjectionNodeFrame>[
        ProjectionNodeFrame(
          nodeInstanceId: firstNode,
          x: 0,
          y: 0,
          width: 200,
          height: 120,
        ),
        ProjectionNodeFrame(
          nodeInstanceId: secondNode,
          x: 320,
          y: 180,
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

    final resolution = JourneySpatialProjectionResolution.resolve(
      bundle: bundle,
      journey: journey,
    );

    expect(resolution.status, JourneySpatialProjectionStatus.ready);
    expect(resolution.projection?.id, projectionId);
    expect(resolution.layout, same(layout));
    expect(resolution.nodes.map((node) => node.id), <NodeInstanceId>[
      firstNode,
      secondNode,
    ]);
    expect(resolution.edges.single.fromNodeId, firstNode);
  });
}
