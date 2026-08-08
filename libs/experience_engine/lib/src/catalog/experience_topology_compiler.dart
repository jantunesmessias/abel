import 'package:experience_contracts/experience_contracts.dart';

import 'authoring_parser.dart';
import 'catalog_compiler.dart';

final class CompiledExperienceTopology {
  CompiledExperienceTopology({
    required this.topology,
    required List<ProjectionLayoutManifest> layouts,
  }) : layouts = List<ProjectionLayoutManifest>.unmodifiable(
         List<ProjectionLayoutManifest>.of(layouts)..sort(
           (left, right) =>
               left.projectionId.value.compareTo(right.projectionId.value),
         ),
       ) {
    final projectionIds = this.layouts
        .map((layout) => layout.projectionId)
        .toList(growable: false);
    if (projectionIds.toSet().length != projectionIds.length) {
      throw ArgumentError('Only one layout is allowed per Projection');
    }
    for (final layout in this.layouts) {
      layout.validateAgainst(topology);
    }
  }

  final ExperienceTopologyManifest topology;
  final List<ProjectionLayoutManifest> layouts;

  late final Digest digest = Digest.semantic(<String, Object?>{
    'topologyDigest': topology.digest.value,
    'layoutDigests': <String>[
      for (final layout in layouts) layout.digest.value,
    ],
  });
}

/// Compiles adjacent authoring v2 into topology and independently digested
/// layouts. The v1 [CatalogManifest] remains the semantic authority for
/// Applications, Scenarios, Journeys and Transitions.
final class ExperienceTopologyCompiler {
  const ExperienceTopologyCompiler();

  bool hasAuthoring(Iterable<AuthoringDocument> source) =>
      source.any((document) => _experienceKinds.contains(document.kind));

  CompiledExperienceTopology compile(
    Iterable<AuthoringDocument> source, {
    required CatalogManifest catalog,
  }) {
    final documents = source
        .where((document) => _experienceKinds.contains(document.kind))
        .toList(growable: false);
    final issues = <String>[];
    final keys = <String>{};
    for (final document in documents) {
      if (document.schemaVersion != 2) {
        issues.add('${document.sourceName}: topology authoring must use v2');
      }
      final key = '${document.kind.name}:${document.id}';
      if (!keys.add(key)) issues.add('duplicate document $key');
      _validateSpecShape(document, issues);
    }

    final boards = <Board>[];
    for (final document in _ofKind(documents, AuthoringKind.board)) {
      _capture(document, issues, () {
        boards.add(
          Board(
            id: BoardId(document.id),
            applicationId: ApplicationId(
              _requiredString(document, 'applicationId'),
            ),
            title: _requiredString(document, 'title'),
            projectionIds: _stringList(
              document,
              'projectionIds',
            ).map(ExperienceProjectionId.new).toList(growable: false),
          ),
        );
      });
    }

    final projections = <ExperienceProjection>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.experienceProjection,
    )) {
      _capture(document, issues, () {
        final journeyId = _optionalString(document, 'journeyId');
        projections.add(
          ExperienceProjection(
            id: ExperienceProjectionId(document.id),
            boardId: BoardId(_requiredString(document, 'boardId')),
            applicationId: ApplicationId(
              _requiredString(document, 'applicationId'),
            ),
            title: _requiredString(document, 'title'),
            kind: _enumValue(
              ProjectionKind.values,
              _requiredString(document, 'projectionKind'),
              'projectionKind',
            ),
            journeyId: journeyId == null ? null : JourneyId(journeyId),
            nodeInstanceIds: _stringList(
              document,
              'nodeInstanceIds',
            ).map(NodeInstanceId.new).toList(growable: false),
            edgeInstanceIds: _stringList(
              document,
              'edgeInstanceIds',
            ).map(EdgeInstanceId.new).toList(growable: false),
          ),
        );
      });
    }

    final nodes = <NodeInstance>[];
    for (final document in _ofKind(documents, AuthoringKind.nodeInstance)) {
      _capture(document, issues, () {
        final role = _optionalString(document, 'comparisonRole');
        nodes.add(
          NodeInstance(
            id: NodeInstanceId(document.id),
            projectionId: ExperienceProjectionId(
              _requiredString(document, 'projectionId'),
            ),
            scenarioId: ScenarioId(_requiredString(document, 'scenarioId')),
            comparisonRole: role == null
                ? null
                : _enumValue(ComparisonRole.values, role, 'comparisonRole'),
          ),
        );
      });
    }

    final edges = <EdgeInstance>[];
    for (final document in _ofKind(documents, AuthoringKind.edgeInstance)) {
      _capture(document, issues, () {
        edges.add(
          EdgeInstance(
            id: EdgeInstanceId(document.id),
            projectionId: ExperienceProjectionId(
              _requiredString(document, 'projectionId'),
            ),
            transitionId: TransitionId(
              _requiredString(document, 'transitionId'),
            ),
            fromNodeId: NodeInstanceId(_requiredString(document, 'fromNodeId')),
            toNodeId: NodeInstanceId(_requiredString(document, 'toNodeId')),
          ),
        );
      });
    }

    ExperienceTopologyManifest? topology;
    _captureSynthetic('experience-topology', issues, () {
      topology = ExperienceTopologyManifest(
        catalog: catalog,
        boards: boards,
        projections: projections,
        nodes: nodes,
        edges: edges,
      );
    });
    if (issues.isNotEmpty || topology == null) {
      throw CatalogCompileException(issues);
    }

    final layouts = <ProjectionLayoutManifest>[];
    for (final document in _ofKind(documents, AuthoringKind.projectionLayout)) {
      _capture(document, issues, () {
        final projectionId = ExperienceProjectionId(
          _requiredString(document, 'projectionId'),
        );
        if (document.id != projectionId.value) {
          throw FormatException(
            'metadata.id must equal spec.projectionId for ProjectionLayout',
          );
        }
        final layout = ProjectionLayoutManifest(
          topologyDigest: topology!.digest,
          projectionId: projectionId,
          nodeFrames: _objectList(
            document,
            'nodeFrames',
          ).map(ProjectionNodeFrame.fromJson).toList(growable: false),
          groups: _objectList(
            document,
            'groups',
          ).map(ProjectionGroup.fromJson).toList(growable: false),
          lanes: _objectList(
            document,
            'lanes',
          ).map(ProjectionLane.fromJson).toList(growable: false),
          annotations: _objectList(
            document,
            'annotations',
          ).map(ProjectionAnnotation.fromJson).toList(growable: false),
          camera: ProjectionCamera.fromJson(
            _requiredObject(document, 'camera'),
          ),
        );
        layout.validateAgainst(topology!);
        layouts.add(layout);
      });
    }
    CompiledExperienceTopology? compilation;
    _captureSynthetic('compiled-experience-topology', issues, () {
      compilation = CompiledExperienceTopology(
        topology: topology!,
        layouts: layouts,
      );
    });
    if (issues.isNotEmpty || compilation == null) {
      throw CatalogCompileException(issues);
    }
    return compilation!;
  }
}

const Set<AuthoringKind> _experienceKinds = <AuthoringKind>{
  AuthoringKind.board,
  AuthoringKind.experienceProjection,
  AuthoringKind.nodeInstance,
  AuthoringKind.edgeInstance,
  AuthoringKind.projectionLayout,
};

Iterable<AuthoringDocument> _ofKind(
  Iterable<AuthoringDocument> documents,
  AuthoringKind kind,
) => documents.where((document) => document.kind == kind);

void _capture(
  AuthoringDocument document,
  List<String> issues,
  void Function() body,
) {
  try {
    body();
  } on ArgumentError catch (error) {
    issues.add('${document.sourceName}: ${error.message}');
  } on FormatException catch (error) {
    issues.add('${document.sourceName}: ${error.message}');
  }
}

void _captureSynthetic(
  String sourceName,
  List<String> issues,
  void Function() body,
) {
  try {
    body();
  } on ArgumentError catch (error) {
    issues.add('$sourceName: ${error.message}');
  } on FormatException catch (error) {
    issues.add('$sourceName: ${error.message}');
  }
}

String _requiredString(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('spec.$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('spec.$key must be a non-empty string');
  }
  return value;
}

List<String> _stringList(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value is! List<Object?> ||
      value.any((item) => item is! String || item.trim().isEmpty)) {
    throw FormatException('spec.$key must be an array of non-empty strings');
  }
  return value.cast<String>();
}

Map<String, Object?> _requiredObject(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('spec.$key must be an object');
  }
  return value;
}

List<Map<String, Object?>> _objectList(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value is! List<Object?> ||
      value.any((item) => item is! Map<String, Object?>)) {
    throw FormatException('spec.$key must be an array of objects');
  }
  return value.cast<Map<String, Object?>>();
}

T _enumValue<T extends Enum>(Iterable<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('spec.$field has an unsupported value: $name');
}

void _validateSpecShape(AuthoringDocument document, List<String> issues) {
  final allowed = switch (document.kind) {
    AuthoringKind.board => const <String>{
      'applicationId',
      'title',
      'projectionIds',
    },
    AuthoringKind.experienceProjection => const <String>{
      'boardId',
      'applicationId',
      'title',
      'journeyId',
      'projectionKind',
      'nodeInstanceIds',
      'edgeInstanceIds',
    },
    AuthoringKind.nodeInstance => const <String>{
      'projectionId',
      'scenarioId',
      'comparisonRole',
    },
    AuthoringKind.edgeInstance => const <String>{
      'projectionId',
      'transitionId',
      'fromNodeId',
      'toNodeId',
    },
    AuthoringKind.projectionLayout => const <String>{
      'projectionId',
      'nodeFrames',
      'groups',
      'lanes',
      'annotations',
      'camera',
    },
    _ => const <String>{},
  };
  for (final key in document.spec.keys) {
    if (!allowed.contains(key)) {
      issues.add('${document.sourceName}: unknown field spec.$key');
    }
  }
}
