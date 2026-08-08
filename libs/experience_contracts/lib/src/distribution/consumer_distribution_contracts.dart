import '../catalog/catalog_contracts.dart';
import '../digest.dart';

enum ConsumerStudioAssets { included, absent }

final class ConsumerDistributionCompatibility {
  ConsumerDistributionCompatibility({
    required this.coreCompatibility,
    this.distributionReleaseSchemaVersion = 2,
    this.consumerConfigurationSchemaVersion = 2,
    List<int> authoringDocumentSchemaVersions = const <int>[1, 2],
  }) : authoringDocumentSchemaVersions = List<int>.unmodifiable(
         List<int>.of(authoringDocumentSchemaVersions)..sort(),
       ) {
    _caretVersion(coreCompatibility, 'coreCompatibility');
    if (distributionReleaseSchemaVersion != 2) {
      throw ArgumentError.value(
        distributionReleaseSchemaVersion,
        'distributionReleaseSchemaVersion',
      );
    }
    if (consumerConfigurationSchemaVersion != 2) {
      throw ArgumentError.value(
        consumerConfigurationSchemaVersion,
        'consumerConfigurationSchemaVersion',
      );
    }
    if (this.authoringDocumentSchemaVersions.isEmpty ||
        _duplicates(this.authoringDocumentSchemaVersions) ||
        this.authoringDocumentSchemaVersions.any(
          (version) => version != 1 && version != 2,
        )) {
      throw ArgumentError(
        'Authoring document schema compatibility must contain v1 or v2',
      );
    }
  }

  final String coreCompatibility;
  final int distributionReleaseSchemaVersion;
  final int consumerConfigurationSchemaVersion;
  final List<int> authoringDocumentSchemaVersions;

  Map<String, Object?> toJson() => <String, Object?>{
    'core': coreCompatibility,
    'distributionReleaseSchemaVersion': distributionReleaseSchemaVersion,
    'consumerConfigurationSchemaVersion': consumerConfigurationSchemaVersion,
    'authoringDocumentSchemaVersions': authoringDocumentSchemaVersions,
  };

  factory ConsumerDistributionCompatibility.fromJson(Object? value) {
    final json = _object(value, 'ConsumerDistributionCompatibility');
    _only(json, const <String>{
      'core',
      'distributionReleaseSchemaVersion',
      'consumerConfigurationSchemaVersion',
      'authoringDocumentSchemaVersions',
    }, 'ConsumerDistributionCompatibility');
    return ConsumerDistributionCompatibility(
      coreCompatibility: _string(
        json,
        'core',
        'ConsumerDistributionCompatibility',
      ),
      distributionReleaseSchemaVersion: _integer(
        json,
        'distributionReleaseSchemaVersion',
        'ConsumerDistributionCompatibility',
      ),
      consumerConfigurationSchemaVersion: _integer(
        json,
        'consumerConfigurationSchemaVersion',
        'ConsumerDistributionCompatibility',
      ),
      authoringDocumentSchemaVersions: _integerList(
        json['authoringDocumentSchemaVersions'],
        'ConsumerDistributionCompatibility.authoringDocumentSchemaVersions',
      ),
    );
  }
}

final class ConsumerDistributionSpec {
  ConsumerDistributionSpec({
    required this.distribution,
    required this.releaseVersion,
    required this.profileId,
    required this.studioAssets,
    required this.compatibility,
  }) {
    _semanticVersion(releaseVersion, 'releaseVersion');
    OpaqueId.validate(profileId, 'KitProfile');
    if (distribution.coreCompatibility != compatibility.coreCompatibility) {
      throw ArgumentError(
        'Distribution and consumer core compatibility must be identical',
      );
    }
  }

  static const int schemaVersion = 1;
  final DistributionDescriptor distribution;
  final String releaseVersion;
  final String profileId;
  final ConsumerStudioAssets studioAssets;
  final ConsumerDistributionCompatibility compatibility;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ConsumerDistributionSpec',
    'distribution': distribution.toJson(),
    'releaseVersion': releaseVersion,
    'profileId': profileId,
    'studioAssets': studioAssets.name,
    'compatibility': compatibility.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ConsumerDistributionSpec.fromJson(Object? value) {
    final json = _object(value, 'ConsumerDistributionSpec');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'distribution',
      'releaseVersion',
      'profileId',
      'studioAssets',
      'compatibility',
      'digest',
    }, 'ConsumerDistributionSpec');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ConsumerDistributionSpec') {
      throw const FormatException('Invalid ConsumerDistributionSpec version');
    }
    final spec = ConsumerDistributionSpec(
      distribution: DistributionDescriptor.fromJson(json['distribution']),
      releaseVersion: _string(
        json,
        'releaseVersion',
        'ConsumerDistributionSpec',
      ),
      profileId: _string(json, 'profileId', 'ConsumerDistributionSpec'),
      studioAssets: _enumValue(
        ConsumerStudioAssets.values,
        _string(json, 'studioAssets', 'ConsumerDistributionSpec'),
        'ConsumerDistributionSpec.studioAssets',
      ),
      compatibility: ConsumerDistributionCompatibility.fromJson(
        json['compatibility'],
      ),
    );
    _verifyDigest(json, spec.digest, 'ConsumerDistributionSpec');
    return spec;
  }
}

final class ConsumerDistributionModuleInventory {
  ConsumerDistributionModuleInventory({
    required this.id,
    required this.version,
    required this.coreCompatibility,
    required this.descriptorDigest,
    required List<String> surfaces,
  }) : surfaces = List<String>.unmodifiable(List<String>.of(surfaces)..sort()) {
    OpaqueId.validate(id, 'Module');
    _semanticVersion(version, 'module version');
    _caretVersion(coreCompatibility, 'module coreCompatibility');
    if (_duplicates(this.surfaces) ||
        this.surfaces.any(
          (surface) => !const <String>{
            'cli',
            'host',
            'gateway',
            'studio',
          }.contains(surface),
        )) {
      throw ArgumentError('Consumer distribution module surfaces are invalid');
    }
  }

  final String id;
  final String version;
  final String coreCompatibility;
  final Digest descriptorDigest;
  final List<String> surfaces;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'version': version,
    'coreCompatibility': coreCompatibility,
    'descriptorDigest': descriptorDigest.value,
    'surfaces': surfaces,
  };

  factory ConsumerDistributionModuleInventory.fromJson(Object? value) {
    final json = _object(value, 'ConsumerDistributionModuleInventory');
    _only(json, const <String>{
      'id',
      'version',
      'coreCompatibility',
      'descriptorDigest',
      'surfaces',
    }, 'ConsumerDistributionModuleInventory');
    return ConsumerDistributionModuleInventory(
      id: _string(json, 'id', 'ConsumerDistributionModuleInventory'),
      version: _string(json, 'version', 'ConsumerDistributionModuleInventory'),
      coreCompatibility: _string(
        json,
        'coreCompatibility',
        'ConsumerDistributionModuleInventory',
      ),
      descriptorDigest: Digest(
        _string(
          json,
          'descriptorDigest',
          'ConsumerDistributionModuleInventory',
        ),
      ),
      surfaces: _stringList(
        json['surfaces'],
        'ConsumerDistributionModuleInventory.surfaces',
      ),
    );
  }
}

final class ConsumerDistributionFileInventory {
  ConsumerDistributionFileInventory({
    required this.path,
    required this.digest,
    required this.size,
    required this.role,
  }) {
    _relativePath(path);
    if (size < 0) throw ArgumentError.value(size, 'size');
    OpaqueId.validate(role, 'ConsumerDistributionFileRole');
  }

  final String path;
  final Digest digest;
  final int size;
  final String role;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'digest': digest.value,
    'size': size,
    'role': role,
  };

  factory ConsumerDistributionFileInventory.fromJson(Object? value) {
    final json = _object(value, 'ConsumerDistributionFileInventory');
    _only(json, const <String>{
      'path',
      'digest',
      'size',
      'role',
    }, 'ConsumerDistributionFileInventory');
    return ConsumerDistributionFileInventory(
      path: _string(json, 'path', 'ConsumerDistributionFileInventory'),
      digest: Digest(
        _string(json, 'digest', 'ConsumerDistributionFileInventory'),
      ),
      size: _integer(json, 'size', 'ConsumerDistributionFileInventory'),
      role: _string(json, 'role', 'ConsumerDistributionFileInventory'),
    );
  }
}

final class ConsumerDistributionInventory {
  ConsumerDistributionInventory({
    required this.distributionId,
    required this.releaseVersion,
    required this.coreVersion,
    required this.profileId,
    required this.studioAssets,
    required this.compatibility,
    required this.specDigest,
    required this.baseReleaseDigest,
    required this.moduleCatalogDigest,
    required this.resolvedPlanDigest,
    required this.consumerConfigurationDigest,
    required this.catalogDigest,
    required List<ConsumerDistributionModuleInventory> modules,
    required List<ConsumerDistributionFileInventory> files,
  }) : modules = List<ConsumerDistributionModuleInventory>.unmodifiable(
         List<ConsumerDistributionModuleInventory>.of(modules)
           ..sort((left, right) => left.id.compareTo(right.id)),
       ),
       files = List<ConsumerDistributionFileInventory>.unmodifiable(
         List<ConsumerDistributionFileInventory>.of(files)
           ..sort((left, right) => left.path.compareTo(right.path)),
       ) {
    OpaqueId.validate(distributionId, 'Distribution');
    OpaqueId.validate(profileId, 'KitProfile');
    _semanticVersion(releaseVersion, 'releaseVersion');
    _semanticVersion(coreVersion, 'coreVersion');
    if (this.modules.isEmpty ||
        _duplicates(this.modules.map((module) => module.id))) {
      throw ArgumentError('Consumer distribution modules are invalid');
    }
    if (this.files.length < 4 ||
        _duplicates(this.files.map((file) => file.path)) ||
        this.files.where((file) => file.role == 'configuration').length != 1 ||
        this.files.where((file) => file.role == 'catalog').length != 1 ||
        this.files.where((file) => file.role == 'resolved-plan').length != 1 ||
        this.files.where((file) => file.role == 'specification').length != 1) {
      throw ArgumentError('Consumer distribution file inventory is invalid');
    }
    final studioModules = this.modules.where(
      (module) => module.id == 'studio.shell',
    );
    if ((studioAssets == ConsumerStudioAssets.included) !=
        studioModules.isNotEmpty) {
      throw ArgumentError(
        'Studio asset mode differs from the enabled module inventory',
      );
    }
  }

  static const int schemaVersion = 1;
  final String distributionId;
  final String releaseVersion;
  final String coreVersion;
  final String profileId;
  final ConsumerStudioAssets studioAssets;
  final ConsumerDistributionCompatibility compatibility;
  final Digest specDigest;
  final Digest baseReleaseDigest;
  final Digest moduleCatalogDigest;
  final Digest resolvedPlanDigest;
  final Digest consumerConfigurationDigest;
  final Digest catalogDigest;
  final List<ConsumerDistributionModuleInventory> modules;
  final List<ConsumerDistributionFileInventory> files;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ConsumerDistributionInventory',
    'distributionId': distributionId,
    'releaseVersion': releaseVersion,
    'coreVersion': coreVersion,
    'profileId': profileId,
    'studioAssets': studioAssets.name,
    'compatibility': compatibility.toJson(),
    'specDigest': specDigest.value,
    'baseReleaseDigest': baseReleaseDigest.value,
    'moduleCatalogDigest': moduleCatalogDigest.value,
    'resolvedPlanDigest': resolvedPlanDigest.value,
    'consumerConfigurationDigest': consumerConfigurationDigest.value,
    'catalogDigest': catalogDigest.value,
    'modules': <Object?>[for (final module in modules) module.toJson()],
    'files': <Object?>[for (final file in files) file.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory ConsumerDistributionInventory.fromJson(Object? value) {
    final json = _object(value, 'ConsumerDistributionInventory');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'distributionId',
      'releaseVersion',
      'coreVersion',
      'profileId',
      'studioAssets',
      'compatibility',
      'specDigest',
      'baseReleaseDigest',
      'moduleCatalogDigest',
      'resolvedPlanDigest',
      'consumerConfigurationDigest',
      'catalogDigest',
      'modules',
      'files',
      'digest',
    }, 'ConsumerDistributionInventory');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ConsumerDistributionInventory') {
      throw const FormatException(
        'Invalid ConsumerDistributionInventory version',
      );
    }
    final inventory = ConsumerDistributionInventory(
      distributionId: _string(
        json,
        'distributionId',
        'ConsumerDistributionInventory',
      ),
      releaseVersion: _string(
        json,
        'releaseVersion',
        'ConsumerDistributionInventory',
      ),
      coreVersion: _string(
        json,
        'coreVersion',
        'ConsumerDistributionInventory',
      ),
      profileId: _string(json, 'profileId', 'ConsumerDistributionInventory'),
      studioAssets: _enumValue(
        ConsumerStudioAssets.values,
        _string(json, 'studioAssets', 'ConsumerDistributionInventory'),
        'ConsumerDistributionInventory.studioAssets',
      ),
      compatibility: ConsumerDistributionCompatibility.fromJson(
        json['compatibility'],
      ),
      specDigest: Digest(
        _string(json, 'specDigest', 'ConsumerDistributionInventory'),
      ),
      baseReleaseDigest: Digest(
        _string(json, 'baseReleaseDigest', 'ConsumerDistributionInventory'),
      ),
      moduleCatalogDigest: Digest(
        _string(json, 'moduleCatalogDigest', 'ConsumerDistributionInventory'),
      ),
      resolvedPlanDigest: Digest(
        _string(json, 'resolvedPlanDigest', 'ConsumerDistributionInventory'),
      ),
      consumerConfigurationDigest: Digest(
        _string(
          json,
          'consumerConfigurationDigest',
          'ConsumerDistributionInventory',
        ),
      ),
      catalogDigest: Digest(
        _string(json, 'catalogDigest', 'ConsumerDistributionInventory'),
      ),
      modules: _list(json['modules'], 'ConsumerDistributionInventory.modules')
          .map(ConsumerDistributionModuleInventory.fromJson)
          .toList(growable: false),
      files: _list(
        json['files'],
        'ConsumerDistributionInventory.files',
      ).map(ConsumerDistributionFileInventory.fromJson).toList(growable: false),
    );
    _verifyDigest(json, inventory.digest, 'ConsumerDistributionInventory');
    return inventory;
  }
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

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

List<int> _integerList(Object? value, String path) {
  final list = _list(value, path);
  if (list.any((item) => item is! int)) {
    throw FormatException('$path must contain integers');
  }
  return list.cast<int>();
}

List<String> _stringList(Object? value, String path) {
  final list = _list(value, path);
  if (list.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path must contain non-empty strings');
  }
  return list.cast<String>();
}

T _enumValue<T extends Enum>(List<T> values, String value, String path) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$path is invalid: $value');
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

void _verifyDigest(Map<String, Object?> json, Digest actual, String path) {
  final advertised = Digest(_string(json, 'digest', path));
  if (advertised != actual) throw FormatException('$path digest mismatch');
}

void _semanticVersion(String value, String path) {
  if (!RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
  ).hasMatch(value)) {
    throw FormatException('Invalid $path: $value');
  }
}

void _caretVersion(String value, String path) {
  if (!RegExp(r'^\^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(value)) {
    throw FormatException('Invalid $path: $value');
  }
}

void _relativePath(String value) {
  final normalized = value.replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.split('/').contains('..')) {
    throw FormatException('Path must be relative: $value');
  }
}

bool _duplicates(Iterable<Object?> values) {
  final seen = <Object?>{};
  for (final value in values) {
    if (!seen.add(value)) return true;
  }
  return false;
}
