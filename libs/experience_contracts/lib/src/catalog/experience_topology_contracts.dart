import '../digest.dart';
import 'catalog_contracts.dart';

final class BoardId extends OpaqueId {
  factory BoardId(String value) {
    OpaqueId.validate(value, 'Board');
    return BoardId._(value);
  }

  const BoardId._(super.value);
}

final class ExperienceProjectionId extends OpaqueId {
  factory ExperienceProjectionId(String value) {
    OpaqueId.validate(value, 'ExperienceProjection');
    return ExperienceProjectionId._(value);
  }

  const ExperienceProjectionId._(super.value);
}

final class NodeInstanceId extends OpaqueId {
  factory NodeInstanceId(String value) {
    OpaqueId.validate(value, 'NodeInstance');
    return NodeInstanceId._(value);
  }

  const NodeInstanceId._(super.value);
}

final class EdgeInstanceId extends OpaqueId {
  factory EdgeInstanceId(String value) {
    OpaqueId.validate(value, 'EdgeInstance');
    return EdgeInstanceId._(value);
  }

  const EdgeInstanceId._(super.value);
}

enum ProjectionKind { journey, inventory, history, comparison, changeset }

enum ComparisonRole { canonical, baseline, candidate }

final class Board {
  Board({
    required this.id,
    required this.applicationId,
    required this.title,
    required List<ExperienceProjectionId> projectionIds,
  }) : projectionIds = _topologySortedIds(
         projectionIds,
         'Board.projectionIds',
         maxItems: 50000,
       ) {
    _topologyText(title, 'Board.title', maxLength: 2048);
  }

  final BoardId id;
  final ApplicationId applicationId;
  final String title;
  final List<ExperienceProjectionId> projectionIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'applicationId': applicationId.value,
    'title': title,
    'projectionIds': projectionIds.map((item) => item.value).toList(),
  };

  factory Board.fromJson(Object? value) {
    final json = _topologyObject(value, 'Board');
    _topologyOnly(json, const <String>{
      'id',
      'applicationId',
      'title',
      'projectionIds',
    }, 'Board');
    return Board(
      id: BoardId(_topologyString(json, 'id', 'Board')),
      applicationId: ApplicationId(
        _topologyString(json, 'applicationId', 'Board'),
      ),
      title: _topologyString(json, 'title', 'Board', maxLength: 2048),
      projectionIds: _topologyStringList(
        json,
        'projectionIds',
        'Board',
        maxItems: 50000,
      ).map(ExperienceProjectionId.new).toList(growable: false),
    );
  }
}

final class ExperienceProjection {
  ExperienceProjection({
    required this.id,
    required this.boardId,
    required this.applicationId,
    required this.title,
    required this.kind,
    this.journeyId,
    required List<NodeInstanceId> nodeInstanceIds,
    required List<EdgeInstanceId> edgeInstanceIds,
  }) : nodeInstanceIds = _topologySortedIds(
         nodeInstanceIds,
         'ExperienceProjection.nodeInstanceIds',
         maxItems: 500000,
       ),
       edgeInstanceIds = _topologySortedIds(
         edgeInstanceIds,
         'ExperienceProjection.edgeInstanceIds',
         maxItems: 1000000,
       ) {
    _topologyText(title, 'ExperienceProjection.title', maxLength: 2048);
    if (kind == ProjectionKind.journey && journeyId == null) {
      throw ArgumentError(
        'ExperienceProjection of kind journey requires journeyId',
      );
    }
  }

  final ExperienceProjectionId id;
  final BoardId boardId;
  final ApplicationId applicationId;
  final String title;
  final ProjectionKind kind;
  final JourneyId? journeyId;
  final List<NodeInstanceId> nodeInstanceIds;
  final List<EdgeInstanceId> edgeInstanceIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'boardId': boardId.value,
    'applicationId': applicationId.value,
    'title': title,
    'kind': kind.name,
    if (journeyId != null) 'journeyId': journeyId!.value,
    'nodeInstanceIds': nodeInstanceIds.map((item) => item.value).toList(),
    'edgeInstanceIds': edgeInstanceIds.map((item) => item.value).toList(),
  };

  factory ExperienceProjection.fromJson(Object? value) {
    final json = _topologyObject(value, 'ExperienceProjection');
    _topologyOnly(json, const <String>{
      'id',
      'boardId',
      'applicationId',
      'title',
      'kind',
      'journeyId',
      'nodeInstanceIds',
      'edgeInstanceIds',
    }, 'ExperienceProjection');
    final journeyId = _topologyOptionalString(
      json,
      'journeyId',
      'ExperienceProjection',
    );
    return ExperienceProjection(
      id: ExperienceProjectionId(
        _topologyString(json, 'id', 'ExperienceProjection'),
      ),
      boardId: BoardId(
        _topologyString(json, 'boardId', 'ExperienceProjection'),
      ),
      applicationId: ApplicationId(
        _topologyString(json, 'applicationId', 'ExperienceProjection'),
      ),
      title: _topologyString(
        json,
        'title',
        'ExperienceProjection',
        maxLength: 2048,
      ),
      kind: _topologyEnum(
        ProjectionKind.values,
        _topologyString(json, 'kind', 'ExperienceProjection'),
        'ExperienceProjection.kind',
      ),
      journeyId: journeyId == null ? null : JourneyId(journeyId),
      nodeInstanceIds: _topologyStringList(
        json,
        'nodeInstanceIds',
        'ExperienceProjection',
        maxItems: 500000,
      ).map(NodeInstanceId.new).toList(growable: false),
      edgeInstanceIds: _topologyStringList(
        json,
        'edgeInstanceIds',
        'ExperienceProjection',
        maxItems: 1000000,
      ).map(EdgeInstanceId.new).toList(growable: false),
    );
  }
}

final class NodeInstance {
  const NodeInstance({
    required this.id,
    required this.projectionId,
    required this.scenarioId,
    this.comparisonRole,
  });

  final NodeInstanceId id;
  final ExperienceProjectionId projectionId;
  final ScenarioId scenarioId;
  final ComparisonRole? comparisonRole;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'projectionId': projectionId.value,
    'scenarioId': scenarioId.value,
    if (comparisonRole != null) 'comparisonRole': comparisonRole!.name,
  };

  factory NodeInstance.fromJson(Object? value) {
    final json = _topologyObject(value, 'NodeInstance');
    _topologyOnly(json, const <String>{
      'id',
      'projectionId',
      'scenarioId',
      'comparisonRole',
    }, 'NodeInstance');
    final comparisonRole = _topologyOptionalString(
      json,
      'comparisonRole',
      'NodeInstance',
    );
    return NodeInstance(
      id: NodeInstanceId(_topologyString(json, 'id', 'NodeInstance')),
      projectionId: ExperienceProjectionId(
        _topologyString(json, 'projectionId', 'NodeInstance'),
      ),
      scenarioId: ScenarioId(
        _topologyString(json, 'scenarioId', 'NodeInstance'),
      ),
      comparisonRole: comparisonRole == null
          ? null
          : _topologyEnum(
              ComparisonRole.values,
              comparisonRole,
              'NodeInstance.comparisonRole',
            ),
    );
  }
}

final class EdgeInstance {
  const EdgeInstance({
    required this.id,
    required this.projectionId,
    required this.transitionId,
    required this.fromNodeId,
    required this.toNodeId,
  });

  final EdgeInstanceId id;
  final ExperienceProjectionId projectionId;
  final TransitionId transitionId;
  final NodeInstanceId fromNodeId;
  final NodeInstanceId toNodeId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'projectionId': projectionId.value,
    'transitionId': transitionId.value,
    'fromNodeId': fromNodeId.value,
    'toNodeId': toNodeId.value,
  };

  factory EdgeInstance.fromJson(Object? value) {
    final json = _topologyObject(value, 'EdgeInstance');
    _topologyOnly(json, const <String>{
      'id',
      'projectionId',
      'transitionId',
      'fromNodeId',
      'toNodeId',
    }, 'EdgeInstance');
    return EdgeInstance(
      id: EdgeInstanceId(_topologyString(json, 'id', 'EdgeInstance')),
      projectionId: ExperienceProjectionId(
        _topologyString(json, 'projectionId', 'EdgeInstance'),
      ),
      transitionId: TransitionId(
        _topologyString(json, 'transitionId', 'EdgeInstance'),
      ),
      fromNodeId: NodeInstanceId(
        _topologyString(json, 'fromNodeId', 'EdgeInstance'),
      ),
      toNodeId: NodeInstanceId(
        _topologyString(json, 'toNodeId', 'EdgeInstance'),
      ),
    );
  }
}

final class ExperienceTopologyManifest {
  ExperienceTopologyManifest({
    required CatalogManifest catalog,
    required List<Board> boards,
    required List<ExperienceProjection> projections,
    required List<NodeInstance> nodes,
    required List<EdgeInstance> edges,
  }) : catalogDigest = catalog.digest,
       boards = _topologySortedEntities(
         boards,
         (item) => item.id.value,
         'ExperienceTopologyManifest.boards',
         maxItems: 10000,
       ),
       projections = _topologySortedEntities(
         projections,
         (item) => item.id.value,
         'ExperienceTopologyManifest.projections',
         maxItems: 50000,
       ),
       nodes = _topologySortedEntities(
         nodes,
         (item) => item.id.value,
         'ExperienceTopologyManifest.nodes',
         maxItems: 500000,
       ),
       edges = _topologySortedEntities(
         edges,
         (item) => item.id.value,
         'ExperienceTopologyManifest.edges',
         maxItems: 1000000,
       ) {
    validateAgainst(catalog);
  }

  static const int schemaVersion = 1;

  final Digest catalogDigest;
  final List<Board> boards;
  final List<ExperienceProjection> projections;
  final List<NodeInstance> nodes;
  final List<EdgeInstance> edges;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceTopologyManifest',
    'catalogDigest': catalogDigest.value,
    'boards': boards.map((item) => item.toJson()).toList(),
    'projections': projections.map((item) => item.toJson()).toList(),
    'nodes': nodes.map((item) => item.toJson()).toList(),
    'edges': edges.map((item) => item.toJson()).toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceTopologyManifest.fromJson(
    Object? value, {
    required CatalogManifest catalog,
  }) {
    final json = _topologyObject(value, 'ExperienceTopologyManifest');
    _topologyOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'catalogDigest',
      'boards',
      'projections',
      'nodes',
      'edges',
      'digest',
    }, 'ExperienceTopologyManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ExperienceTopologyManifest') {
      throw const FormatException(
        'ExperienceTopologyManifest has invalid schemaVersion or kind',
      );
    }
    final declaredCatalogDigest = Digest(
      _topologyString(json, 'catalogDigest', 'ExperienceTopologyManifest'),
    );
    if (declaredCatalogDigest != catalog.digest) {
      throw const FormatException(
        'ExperienceTopologyManifest catalogDigest mismatch',
      );
    }
    final manifest = ExperienceTopologyManifest(
      catalog: catalog,
      boards: _topologyList(
        json,
        'boards',
        'ExperienceTopologyManifest',
        maxItems: 10000,
      ).map(Board.fromJson).toList(growable: false),
      projections: _topologyList(
        json,
        'projections',
        'ExperienceTopologyManifest',
        maxItems: 50000,
      ).map(ExperienceProjection.fromJson).toList(growable: false),
      nodes: _topologyList(
        json,
        'nodes',
        'ExperienceTopologyManifest',
        maxItems: 500000,
      ).map(NodeInstance.fromJson).toList(growable: false),
      edges: _topologyList(
        json,
        'edges',
        'ExperienceTopologyManifest',
        maxItems: 1000000,
      ).map(EdgeInstance.fromJson).toList(growable: false),
    );
    final declaredDigest = Digest(
      _topologyString(json, 'digest', 'ExperienceTopologyManifest'),
    );
    if (declaredDigest != manifest.digest) {
      throw const FormatException('ExperienceTopologyManifest digest mismatch');
    }
    return manifest;
  }

  void validateAgainst(CatalogManifest catalog) {
    if (catalog.digest != catalogDigest) {
      throw ArgumentError(
        'ExperienceTopologyManifest belongs to another CatalogManifest',
      );
    }

    final applications = <ApplicationId, Application>{
      for (final application in catalog.applications)
        application.id: application,
    };
    final scenarios = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final journeys = <JourneyId, Journey>{
      for (final journey in catalog.journeys) journey.id: journey,
    };
    final transitions = <TransitionId, Transition>{
      for (final transition in catalog.transitions) transition.id: transition,
    };
    final boardById = <BoardId, Board>{
      for (final board in boards) board.id: board,
    };
    final projectionById = <ExperienceProjectionId, ExperienceProjection>{
      for (final projection in projections) projection.id: projection,
    };
    final nodeById = <NodeInstanceId, NodeInstance>{
      for (final node in nodes) node.id: node,
    };
    final edgeById = <EdgeInstanceId, EdgeInstance>{
      for (final edge in edges) edge.id: edge,
    };

    for (final board in boards) {
      if (!applications.containsKey(board.applicationId)) {
        throw ArgumentError(
          'Board ${board.id} references an unknown Application',
        );
      }
      final actualProjectionIds = projections
          .where((item) => item.boardId == board.id)
          .map((item) => item.id)
          .toSet();
      if (!_topologySetEquals(
        board.projectionIds.toSet(),
        actualProjectionIds,
      )) {
        throw ArgumentError(
          'Board ${board.id} projection membership is inconsistent',
        );
      }
    }

    for (final projection in projections) {
      final board = boardById[projection.boardId];
      final journey = projection.journeyId == null
          ? null
          : journeys[projection.journeyId];
      if (board == null ||
          board.applicationId != projection.applicationId ||
          !applications.containsKey(projection.applicationId) ||
          (projection.journeyId != null &&
              (journey == null ||
                  journey.applicationId != projection.applicationId))) {
        throw ArgumentError(
          'ExperienceProjection ${projection.id} has an invalid Board/Application',
        );
      }
      final actualNodeIds = nodes
          .where((item) => item.projectionId == projection.id)
          .map((item) => item.id)
          .toSet();
      final actualEdgeIds = edges
          .where((item) => item.projectionId == projection.id)
          .map((item) => item.id)
          .toSet();
      if (!_topologySetEquals(
            projection.nodeInstanceIds.toSet(),
            actualNodeIds,
          ) ||
          !_topologySetEquals(
            projection.edgeInstanceIds.toSet(),
            actualEdgeIds,
          )) {
        throw ArgumentError(
          'ExperienceProjection ${projection.id} membership is inconsistent',
        );
      }
      if (projection.kind == ProjectionKind.comparison) {
        final roles = nodes
            .where((item) => item.projectionId == projection.id)
            .map((item) => item.comparisonRole)
            .toSet();
        if (!roles.contains(ComparisonRole.baseline) ||
            !roles.contains(ComparisonRole.candidate)) {
          throw ArgumentError(
            'Comparison Projection ${projection.id} requires baseline and '
            'candidate NodeInstances',
          );
        }
      }
    }

    for (final node in nodes) {
      final projection = projectionById[node.projectionId];
      final scenario = scenarios[node.scenarioId];
      if (projection == null ||
          scenario == null ||
          scenario.applicationId != projection.applicationId) {
        throw ArgumentError(
          'NodeInstance ${node.id} has an unknown or cross-Application reference',
        );
      }
      final isComparison = projection.kind == ProjectionKind.comparison;
      if (isComparison != (node.comparisonRole != null)) {
        throw ArgumentError(
          'NodeInstance ${node.id} must declare comparisonRole exactly when '
          'its Projection is comparison',
        );
      }
    }

    for (final edge in edges) {
      final projection = projectionById[edge.projectionId];
      final transition = transitions[edge.transitionId];
      final fromNode = nodeById[edge.fromNodeId];
      final toNode = nodeById[edge.toNodeId];
      if (projection == null ||
          transition == null ||
          fromNode == null ||
          toNode == null ||
          fromNode.projectionId != projection.id ||
          toNode.projectionId != projection.id) {
        throw ArgumentError(
          'EdgeInstance ${edge.id} has an unknown or cross-Projection reference',
        );
      }
      final journey = journeys[transition.journeyId];
      final fromScenario = scenarios[transition.from];
      final toScenario = scenarios[transition.to];
      if (journey == null ||
          journey.applicationId != projection.applicationId ||
          fromScenario == null ||
          toScenario == null ||
          fromScenario.applicationId != projection.applicationId ||
          toScenario.applicationId != projection.applicationId ||
          !journey.scenarioIds.contains(transition.from) ||
          !journey.scenarioIds.contains(transition.to) ||
          fromNode.scenarioId != transition.from ||
          toNode.scenarioId != transition.to) {
        throw ArgumentError(
          'EdgeInstance ${edge.id} does not match its Transition/Journey endpoints',
        );
      }
    }

    if (boardById.length != boards.length ||
        projectionById.length != projections.length ||
        nodeById.length != nodes.length ||
        edgeById.length != edges.length) {
      throw ArgumentError('ExperienceTopologyManifest contains duplicate IDs');
    }
  }
}

List<T> _topologySortedEntities<T>(
  Iterable<T> values,
  String Function(T) key,
  String path, {
  required int maxItems,
}) {
  final result = List<T>.of(values);
  if (result.length > maxItems) {
    throw ArgumentError('$path exceeds $maxItems items');
  }
  result.sort((left, right) => key(left).compareTo(key(right)));
  if (_topologyDuplicates(result.map(key))) {
    throw ArgumentError('$path IDs must be unique');
  }
  return List<T>.unmodifiable(result);
}

List<T> _topologySortedIds<T extends OpaqueId>(
  Iterable<T> values,
  String path, {
  required int maxItems,
}) => _topologySortedEntities(
  values,
  (item) => item.value,
  path,
  maxItems: maxItems,
);

bool _topologyDuplicates(Iterable<String> values) {
  final seen = <String>{};
  return values.any((value) => !seen.add(value));
}

bool _topologySetEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

void _topologyText(String value, String path, {required int maxLength}) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw ArgumentError('$path must be a bounded non-empty string');
  }
}

Map<String, Object?> _topologyObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _topologyOnly(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('Unknown $path.$key');
    }
  }
}

String _topologyString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 4096,
}) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('$path.$key must be a bounded non-empty string');
  }
  return value;
}

String? _topologyOptionalString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 4096,
}) => json.containsKey(key)
    ? _topologyString(json, key, path, maxLength: maxLength)
    : null;

List<Object?> _topologyList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be an array');
  }
  if (value.length > maxItems) {
    throw FormatException('$path.$key exceeds $maxItems items');
  }
  return value;
}

List<String> _topologyStringList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final values = _topologyList(json, key, path, maxItems: maxItems);
  if (values.any((item) => item is! String || item.trim().isEmpty)) {
    throw FormatException('$path.$key must contain non-empty strings');
  }
  return values.cast<String>();
}

T _topologyEnum<T extends Enum>(Iterable<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has an unsupported value: $name');
}
