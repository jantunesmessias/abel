import '../catalog/catalog_contracts.dart';
import '../digest.dart';

enum AdoptionFileState {
  planned,
  ownedUnmodified,
  modified,
  missing,
  preexisting,
}

final class AdoptionFileRecord {
  AdoptionFileRecord({
    required this.path,
    required this.role,
    required this.contentDigest,
  }) {
    _relativePath(path);
    _nonEmpty(role, 'role');
  }

  final String path;
  final String role;
  final Digest contentDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'role': role,
    'contentDigest': contentDigest.value,
  };

  factory AdoptionFileRecord.fromJson(Object? value) {
    final json = _object(value, 'AdoptionFileRecord');
    _only(json, const <String>{
      'path',
      'role',
      'contentDigest',
    }, 'AdoptionFileRecord');
    return AdoptionFileRecord(
      path: _string(json, 'path', 'AdoptionFileRecord'),
      role: _string(json, 'role', 'AdoptionFileRecord'),
      contentDigest: Digest(
        _string(json, 'contentDigest', 'AdoptionFileRecord'),
      ),
    );
  }
}

final class AdoptionManifest {
  AdoptionManifest({
    required this.distributionId,
    required List<AdoptionFileRecord> files,
  }) : files = List<AdoptionFileRecord>.unmodifiable(
         List<AdoptionFileRecord>.of(files)
           ..sort((left, right) => left.path.compareTo(right.path)),
       ) {
    OpaqueId.validate(distributionId, 'Distribution');
    if (this.files.isEmpty) throw ArgumentError('files must not be empty');
    if (_duplicates(this.files.map((file) => file.path))) {
      throw ArgumentError('Adoption paths must be unique');
    }
  }

  static const int schemaVersion = 1;

  final String distributionId;
  final List<AdoptionFileRecord> files;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AdoptionManifest',
    'distributionId': distributionId,
    'files': files.map((file) => file.toJson()).toList(growable: false),
    if (includeDigest) 'digest': digest.value,
  };

  factory AdoptionManifest.fromJson(Object? value) {
    final json = _object(value, 'AdoptionManifest');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'distributionId',
      'files',
      'digest',
    }, 'AdoptionManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'AdoptionManifest') {
      throw const FormatException('Invalid AdoptionManifest version');
    }
    final manifest = AdoptionManifest(
      distributionId: _string(json, 'distributionId', 'AdoptionManifest'),
      files: _list(
        json['files'],
        'AdoptionManifest.files',
      ).map(AdoptionFileRecord.fromJson).toList(growable: false),
    );
    if (manifest.digest !=
        Digest(_string(json, 'digest', 'AdoptionManifest'))) {
      throw const FormatException('AdoptionManifest digest mismatch');
    }
    return manifest;
  }
}

final class AdoptionFileObservation {
  AdoptionFileObservation({
    required this.path,
    required this.role,
    required this.state,
    this.expectedDigest,
    this.observedDigest,
  }) {
    _relativePath(path);
    _nonEmpty(role, 'role');
  }

  final String path;
  final String role;
  final AdoptionFileState state;
  final Digest? expectedDigest;
  final Digest? observedDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'role': role,
    'state': state.name,
    if (expectedDigest != null) 'expectedDigest': expectedDigest!.value,
    if (observedDigest != null) 'observedDigest': observedDigest!.value,
  };
}

final class AdoptionReport {
  AdoptionReport({
    required this.distributionId,
    required this.adopted,
    required this.canApply,
    required this.canDetach,
    required List<AdoptionFileObservation> files,
    this.manifestDigest,
  }) : files = List<AdoptionFileObservation>.unmodifiable(
         List<AdoptionFileObservation>.of(files)
           ..sort((left, right) => left.path.compareTo(right.path)),
       ) {
    OpaqueId.validate(distributionId, 'Distribution');
  }

  static const int schemaVersion = 1;

  final String distributionId;
  final bool adopted;
  final bool canApply;
  final bool canDetach;
  final Digest? manifestDigest;
  final List<AdoptionFileObservation> files;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AdoptionReport',
    'distributionId': distributionId,
    'adopted': adopted,
    'canApply': canApply,
    'canDetach': canDetach,
    if (manifestDigest != null) 'manifestDigest': manifestDigest!.value,
    'files': files.map((file) => file.toJson()).toList(growable: false),
  };
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path must be a list');
  return value;
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

void _relativePath(String value) {
  final normalized = value.replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.split('/').contains('..')) {
    throw FormatException('Adoption path must be workspace-relative: $value');
  }
}

void _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name);
}

bool _duplicates(Iterable<Object?> values) {
  final seen = <Object?>{};
  for (final value in values) {
    if (!seen.add(value)) return true;
  }
  return false;
}
