import 'package:experience_contracts/experience_contracts.dart';

enum JourneySpatialProjectionStatus {
  topologyAbsent,
  projectionAbsent,
  projectionAmbiguous,
  layoutAbsent,
  ready,
}

final class JourneySpatialProjectionResolution {
  const JourneySpatialProjectionResolution._({
    required this.status,
    this.projection,
    this.layout,
    this.nodes = const <NodeInstance>[],
    this.edges = const <EdgeInstance>[],
  });

  factory JourneySpatialProjectionResolution.resolve({
    required ExperienceTopologyBundle? bundle,
    required Journey journey,
  }) {
    if (bundle == null) {
      return const JourneySpatialProjectionResolution._(
        status: JourneySpatialProjectionStatus.topologyAbsent,
      );
    }
    final matches = bundle.topology.projections
        .where(
          (projection) =>
              projection.kind == ProjectionKind.journey &&
              projection.journeyId == journey.id &&
              projection.applicationId == journey.applicationId,
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      return const JourneySpatialProjectionResolution._(
        status: JourneySpatialProjectionStatus.projectionAbsent,
      );
    }
    if (matches.length != 1) {
      return const JourneySpatialProjectionResolution._(
        status: JourneySpatialProjectionStatus.projectionAmbiguous,
      );
    }

    final projection = matches.single;
    final layouts = bundle.layouts
        .where((layout) => layout.projectionId == projection.id)
        .toList(growable: false);
    if (layouts.isEmpty) {
      return JourneySpatialProjectionResolution._(
        status: JourneySpatialProjectionStatus.layoutAbsent,
        projection: projection,
      );
    }

    final nodesById = <NodeInstanceId, NodeInstance>{
      for (final node in bundle.topology.nodes) node.id: node,
    };
    final edgesById = <EdgeInstanceId, EdgeInstance>{
      for (final edge in bundle.topology.edges) edge.id: edge,
    };
    return JourneySpatialProjectionResolution._(
      status: JourneySpatialProjectionStatus.ready,
      projection: projection,
      layout: layouts.single,
      nodes: List<NodeInstance>.unmodifiable(
        projection.nodeInstanceIds.map((id) => nodesById[id]!),
      ),
      edges: List<EdgeInstance>.unmodifiable(
        projection.edgeInstanceIds.map((id) => edgesById[id]!),
      ),
    );
  }

  final JourneySpatialProjectionStatus status;
  final ExperienceProjection? projection;
  final ProjectionLayoutManifest? layout;
  final List<NodeInstance> nodes;
  final List<EdgeInstance> edges;

  bool get isReady => status == JourneySpatialProjectionStatus.ready;

  String get fallbackMessage => switch (status) {
    JourneySpatialProjectionStatus.topologyAbsent =>
      'O Host não publicou topologia de Experience para este catálogo.',
    JourneySpatialProjectionStatus.projectionAbsent =>
      'Nenhuma Projection autoral referencia esta Journey.',
    JourneySpatialProjectionStatus.projectionAmbiguous =>
      'Mais de uma Projection referencia esta Journey; selecione uma Projection por uma rota de Board.',
    JourneySpatialProjectionStatus.layoutAbsent =>
      'A Projection existe, mas não possui ProjectionLayout publicado.',
    JourneySpatialProjectionStatus.ready => '',
  };
}
