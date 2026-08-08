import '../digest.dart';
import 'catalog_contracts.dart';
import 'experience_topology_contracts.dart';

final class ProjectionGroupId extends OpaqueId {
  factory ProjectionGroupId(String value) {
    OpaqueId.validate(value, 'ProjectionGroup');
    return ProjectionGroupId._(value);
  }

  const ProjectionGroupId._(super.value);
}

final class ProjectionLaneId extends OpaqueId {
  factory ProjectionLaneId(String value) {
    OpaqueId.validate(value, 'ProjectionLane');
    return ProjectionLaneId._(value);
  }

  const ProjectionLaneId._(super.value);
}

final class ProjectionAnnotationId extends OpaqueId {
  factory ProjectionAnnotationId(String value) {
    OpaqueId.validate(value, 'ProjectionAnnotation');
    return ProjectionAnnotationId._(value);
  }

  const ProjectionAnnotationId._(super.value);
}

final class ProjectionNodeFrame {
  ProjectionNodeFrame({
    required this.nodeInstanceId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.groupId,
    this.laneId,
  }) {
    _layoutCoordinate(x, 'ProjectionNodeFrame.x');
    _layoutCoordinate(y, 'ProjectionNodeFrame.y');
    _layoutExtent(width, 'ProjectionNodeFrame.width');
    _layoutExtent(height, 'ProjectionNodeFrame.height');
  }

  final NodeInstanceId nodeInstanceId;
  final double x;
  final double y;
  final double width;
  final double height;
  final ProjectionGroupId? groupId;
  final ProjectionLaneId? laneId;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeInstanceId': nodeInstanceId.value,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    if (groupId != null) 'groupId': groupId!.value,
    if (laneId != null) 'laneId': laneId!.value,
  };

  factory ProjectionNodeFrame.fromJson(Object? value) {
    final json = _layoutObject(value, 'ProjectionNodeFrame');
    _layoutOnly(json, const <String>{
      'nodeInstanceId',
      'x',
      'y',
      'width',
      'height',
      'groupId',
      'laneId',
    }, 'ProjectionNodeFrame');
    final groupId = _layoutOptionalString(
      json,
      'groupId',
      'ProjectionNodeFrame',
    );
    final laneId = _layoutOptionalString(json, 'laneId', 'ProjectionNodeFrame');
    return ProjectionNodeFrame(
      nodeInstanceId: NodeInstanceId(
        _layoutString(json, 'nodeInstanceId', 'ProjectionNodeFrame'),
      ),
      x: _layoutNumber(json, 'x', 'ProjectionNodeFrame'),
      y: _layoutNumber(json, 'y', 'ProjectionNodeFrame'),
      width: _layoutNumber(json, 'width', 'ProjectionNodeFrame'),
      height: _layoutNumber(json, 'height', 'ProjectionNodeFrame'),
      groupId: groupId == null ? null : ProjectionGroupId(groupId),
      laneId: laneId == null ? null : ProjectionLaneId(laneId),
    );
  }
}

final class ProjectionGroup {
  ProjectionGroup({
    required this.id,
    required this.title,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    _layoutText(title, 'ProjectionGroup.title', maxLength: 2048);
    _layoutCoordinate(x, 'ProjectionGroup.x');
    _layoutCoordinate(y, 'ProjectionGroup.y');
    _layoutExtent(width, 'ProjectionGroup.width');
    _layoutExtent(height, 'ProjectionGroup.height');
  }

  final ProjectionGroupId id;
  final String title;
  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'title': title,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory ProjectionGroup.fromJson(Object? value) {
    final json = _layoutObject(value, 'ProjectionGroup');
    _layoutOnly(json, const <String>{
      'id',
      'title',
      'x',
      'y',
      'width',
      'height',
    }, 'ProjectionGroup');
    return ProjectionGroup(
      id: ProjectionGroupId(_layoutString(json, 'id', 'ProjectionGroup')),
      title: _layoutString(json, 'title', 'ProjectionGroup', maxLength: 2048),
      x: _layoutNumber(json, 'x', 'ProjectionGroup'),
      y: _layoutNumber(json, 'y', 'ProjectionGroup'),
      width: _layoutNumber(json, 'width', 'ProjectionGroup'),
      height: _layoutNumber(json, 'height', 'ProjectionGroup'),
    );
  }
}

final class ProjectionLane {
  ProjectionLane({
    required this.id,
    required this.title,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    _layoutText(title, 'ProjectionLane.title', maxLength: 2048);
    _layoutCoordinate(x, 'ProjectionLane.x');
    _layoutCoordinate(y, 'ProjectionLane.y');
    _layoutExtent(width, 'ProjectionLane.width');
    _layoutExtent(height, 'ProjectionLane.height');
  }

  final ProjectionLaneId id;
  final String title;
  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'title': title,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory ProjectionLane.fromJson(Object? value) {
    final json = _layoutObject(value, 'ProjectionLane');
    _layoutOnly(json, const <String>{
      'id',
      'title',
      'x',
      'y',
      'width',
      'height',
    }, 'ProjectionLane');
    return ProjectionLane(
      id: ProjectionLaneId(_layoutString(json, 'id', 'ProjectionLane')),
      title: _layoutString(json, 'title', 'ProjectionLane', maxLength: 2048),
      x: _layoutNumber(json, 'x', 'ProjectionLane'),
      y: _layoutNumber(json, 'y', 'ProjectionLane'),
      width: _layoutNumber(json, 'width', 'ProjectionLane'),
      height: _layoutNumber(json, 'height', 'ProjectionLane'),
    );
  }
}

final class ProjectionAnnotation {
  ProjectionAnnotation({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    _layoutText(text, 'ProjectionAnnotation.text', maxLength: 16384);
    _layoutCoordinate(x, 'ProjectionAnnotation.x');
    _layoutCoordinate(y, 'ProjectionAnnotation.y');
    _layoutExtent(width, 'ProjectionAnnotation.width');
    _layoutExtent(height, 'ProjectionAnnotation.height');
  }

  final ProjectionAnnotationId id;
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'text': text,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory ProjectionAnnotation.fromJson(Object? value) {
    final json = _layoutObject(value, 'ProjectionAnnotation');
    _layoutOnly(json, const <String>{
      'id',
      'text',
      'x',
      'y',
      'width',
      'height',
    }, 'ProjectionAnnotation');
    return ProjectionAnnotation(
      id: ProjectionAnnotationId(
        _layoutString(json, 'id', 'ProjectionAnnotation'),
      ),
      text: _layoutString(
        json,
        'text',
        'ProjectionAnnotation',
        maxLength: 16384,
      ),
      x: _layoutNumber(json, 'x', 'ProjectionAnnotation'),
      y: _layoutNumber(json, 'y', 'ProjectionAnnotation'),
      width: _layoutNumber(json, 'width', 'ProjectionAnnotation'),
      height: _layoutNumber(json, 'height', 'ProjectionAnnotation'),
    );
  }
}

final class ProjectionCamera {
  ProjectionCamera({required this.x, required this.y, required this.zoom}) {
    _layoutCoordinate(x, 'ProjectionCamera.x');
    _layoutCoordinate(y, 'ProjectionCamera.y');
    if (!zoom.isFinite ||
        _layoutNegativeZero(zoom) ||
        zoom < 0.05 ||
        zoom > 64) {
      throw ArgumentError(
        'ProjectionCamera.zoom must be finite and between 0.05 and 64',
      );
    }
  }

  final double x;
  final double y;
  final double zoom;

  Map<String, Object?> toJson() => <String, Object?>{
    'x': x,
    'y': y,
    'zoom': zoom,
  };

  factory ProjectionCamera.fromJson(Object? value) {
    final json = _layoutObject(value, 'ProjectionCamera');
    _layoutOnly(json, const <String>{'x', 'y', 'zoom'}, 'ProjectionCamera');
    return ProjectionCamera(
      x: _layoutNumber(json, 'x', 'ProjectionCamera'),
      y: _layoutNumber(json, 'y', 'ProjectionCamera'),
      zoom: _layoutNumber(json, 'zoom', 'ProjectionCamera'),
    );
  }
}

final class ProjectionLayoutManifest {
  ProjectionLayoutManifest({
    required this.topologyDigest,
    required this.projectionId,
    required List<ProjectionNodeFrame> nodeFrames,
    required List<ProjectionGroup> groups,
    required List<ProjectionLane> lanes,
    required List<ProjectionAnnotation> annotations,
    required this.camera,
  }) : nodeFrames = _layoutSorted(
         nodeFrames,
         (item) => item.nodeInstanceId.value,
         'ProjectionLayoutManifest.nodeFrames',
         maxItems: 500000,
       ),
       groups = _layoutSorted(
         groups,
         (item) => item.id.value,
         'ProjectionLayoutManifest.groups',
         maxItems: 100000,
       ),
       lanes = _layoutSorted(
         lanes,
         (item) => item.id.value,
         'ProjectionLayoutManifest.lanes',
         maxItems: 100000,
       ),
       annotations = _layoutSorted(
         annotations,
         (item) => item.id.value,
         'ProjectionLayoutManifest.annotations',
         maxItems: 100000,
       );

  static const int schemaVersion = 1;

  final Digest topologyDigest;
  final ExperienceProjectionId projectionId;
  final List<ProjectionNodeFrame> nodeFrames;
  final List<ProjectionGroup> groups;
  final List<ProjectionLane> lanes;
  final List<ProjectionAnnotation> annotations;
  final ProjectionCamera camera;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ProjectionLayoutManifest',
    'topologyDigest': topologyDigest.value,
    'projectionId': projectionId.value,
    'nodeFrames': nodeFrames.map((item) => item.toJson()).toList(),
    'groups': groups.map((item) => item.toJson()).toList(),
    'lanes': lanes.map((item) => item.toJson()).toList(),
    'annotations': annotations.map((item) => item.toJson()).toList(),
    'camera': camera.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ProjectionLayoutManifest.fromJson(Object? value) {
    final json = _layoutObject(value, 'ProjectionLayoutManifest');
    _layoutOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'topologyDigest',
      'projectionId',
      'nodeFrames',
      'groups',
      'lanes',
      'annotations',
      'camera',
      'digest',
    }, 'ProjectionLayoutManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ProjectionLayoutManifest') {
      throw const FormatException(
        'ProjectionLayoutManifest has invalid schemaVersion or kind',
      );
    }
    final manifest = ProjectionLayoutManifest(
      topologyDigest: Digest(
        _layoutString(json, 'topologyDigest', 'ProjectionLayoutManifest'),
      ),
      projectionId: ExperienceProjectionId(
        _layoutString(json, 'projectionId', 'ProjectionLayoutManifest'),
      ),
      nodeFrames: _layoutList(
        json,
        'nodeFrames',
        'ProjectionLayoutManifest',
        maxItems: 500000,
      ).map(ProjectionNodeFrame.fromJson).toList(growable: false),
      groups: _layoutList(
        json,
        'groups',
        'ProjectionLayoutManifest',
        maxItems: 100000,
      ).map(ProjectionGroup.fromJson).toList(growable: false),
      lanes: _layoutList(
        json,
        'lanes',
        'ProjectionLayoutManifest',
        maxItems: 100000,
      ).map(ProjectionLane.fromJson).toList(growable: false),
      annotations: _layoutList(
        json,
        'annotations',
        'ProjectionLayoutManifest',
        maxItems: 100000,
      ).map(ProjectionAnnotation.fromJson).toList(growable: false),
      camera: ProjectionCamera.fromJson(json['camera']),
    );
    final declaredDigest = Digest(
      _layoutString(json, 'digest', 'ProjectionLayoutManifest'),
    );
    if (declaredDigest != manifest.digest) {
      throw const FormatException('ProjectionLayoutManifest digest mismatch');
    }
    return manifest;
  }

  void validateAgainst(ExperienceTopologyManifest topology) {
    if (topology.digest != topologyDigest) {
      throw ArgumentError(
        'ProjectionLayoutManifest belongs to another topology',
      );
    }
    final matchingProjections = topology.projections
        .where((item) => item.id == projectionId)
        .toList(growable: false);
    if (matchingProjections.length != 1) {
      throw ArgumentError(
        'ProjectionLayoutManifest references an unknown Projection',
      );
    }
    final projection = matchingProjections.single;
    final topologyNodes = <NodeInstanceId, NodeInstance>{
      for (final node in topology.nodes) node.id: node,
    };
    final frameNodeIds = nodeFrames.map((item) => item.nodeInstanceId).toSet();
    if (!_layoutSetEquals(projection.nodeInstanceIds.toSet(), frameNodeIds)) {
      throw ArgumentError(
        'ProjectionLayoutManifest must frame every Projection node exactly once',
      );
    }
    final groupIds = groups.map((item) => item.id).toSet();
    final laneIds = lanes.map((item) => item.id).toSet();
    for (final frame in nodeFrames) {
      final node = topologyNodes[frame.nodeInstanceId];
      if (node == null || node.projectionId != projectionId) {
        throw ArgumentError(
          'ProjectionNodeFrame ${frame.nodeInstanceId} is outside its Projection',
        );
      }
      if (frame.groupId != null && !groupIds.contains(frame.groupId)) {
        throw ArgumentError(
          'ProjectionNodeFrame ${frame.nodeInstanceId} references an unknown Group',
        );
      }
      if (frame.laneId != null && !laneIds.contains(frame.laneId)) {
        throw ArgumentError(
          'ProjectionNodeFrame ${frame.nodeInstanceId} references an unknown Lane',
        );
      }
    }
  }
}

const double _layoutMaxCoordinate = 1000000;
const double _layoutMaxExtent = 1000000;

void _layoutCoordinate(double value, String path) {
  if (!value.isFinite ||
      _layoutNegativeZero(value) ||
      value < -_layoutMaxCoordinate ||
      value > _layoutMaxCoordinate) {
    throw ArgumentError(
      '$path must be finite and between -$_layoutMaxCoordinate and $_layoutMaxCoordinate',
    );
  }
}

void _layoutExtent(double value, String path) {
  if (!value.isFinite ||
      _layoutNegativeZero(value) ||
      value <= 0 ||
      value > _layoutMaxExtent) {
    throw ArgumentError(
      '$path must be finite, positive, and at most $_layoutMaxExtent',
    );
  }
}

bool _layoutNegativeZero(double value) => value == 0 && value.isNegative;

void _layoutText(String value, String path, {required int maxLength}) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw ArgumentError('$path must be a bounded non-empty string');
  }
}

List<T> _layoutSorted<T>(
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
  final seen = <String>{};
  if (result.any((item) => !seen.add(key(item)))) {
    throw ArgumentError('$path IDs must be unique');
  }
  return List<T>.unmodifiable(result);
}

bool _layoutSetEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);

Map<String, Object?> _layoutObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _layoutOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('Unknown $path.$key');
    }
  }
}

String _layoutString(
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

String? _layoutOptionalString(
  Map<String, Object?> json,
  String key,
  String path,
) => json.containsKey(key) ? _layoutString(json, key, path) : null;

double _layoutNumber(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! num) {
    throw FormatException('$path.$key must be a number');
  }
  return value.toDouble();
}

List<Object?> _layoutList(
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
