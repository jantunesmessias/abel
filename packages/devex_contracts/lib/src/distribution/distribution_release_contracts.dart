import '../catalog/catalog_contracts.dart';
import '../digest.dart';

final class DistributionFile {
  DistributionFile({
    required this.path,
    required this.digest,
    required this.size,
    required this.executable,
    required this.role,
    List<String> moduleIds = const <String>[],
  }) : moduleIds = List<String>.unmodifiable(
         List<String>.of(moduleIds)..sort(),
       ) {
    _relativePath(path);
    if (size < 0) throw ArgumentError.value(size, 'size');
    if (role.isEmpty) throw ArgumentError.value(role, 'role');
    if (_duplicates(this.moduleIds)) {
      throw ArgumentError('Distribution file module IDs must be unique');
    }
    for (final moduleId in this.moduleIds) {
      OpaqueId.validate(moduleId, 'Module');
    }
  }

  final String path;
  final Digest digest;
  final int size;
  final bool executable;
  final String role;
  final List<String> moduleIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'digest': digest.value,
    'size': size,
    'executable': executable,
    'role': role,
    if (moduleIds.isNotEmpty) 'moduleIds': moduleIds,
  };

  factory DistributionFile.fromJson(Object? value) {
    final json = _object(value, 'DistributionFile');
    _only(json, const <String>{
      'path',
      'digest',
      'size',
      'executable',
      'role',
      'moduleIds',
    }, 'DistributionFile');
    return DistributionFile(
      path: _string(json, 'path', 'DistributionFile'),
      digest: Digest(_string(json, 'digest', 'DistributionFile')),
      size: _integer(json, 'size', 'DistributionFile'),
      executable: _boolean(json, 'executable', 'DistributionFile'),
      role: _string(json, 'role', 'DistributionFile'),
      moduleIds: json['moduleIds'] == null
          ? const <String>[]
          : _stringList(json['moduleIds'], 'DistributionFile.moduleIds'),
    );
  }
}

abstract interface class DistributionRelease {
  int get manifestVersion;
  String get distributionId;
  List<String> get distributionCommandAliases;
  String get releaseVersion;
  String get coreVersion;
  String get platform;
  Map<String, String> get entrypoints;
  Map<String, String> get commandAliases;
  List<DistributionFile> get files;
  Digest get digest;
  Map<String, Object?> toJson({bool includeDigest = true});
}

final class DistributionReleaseManifest implements DistributionRelease {
  DistributionReleaseManifest({
    required this.distribution,
    required this.releaseVersion,
    required this.coreVersion,
    required this.platform,
    required Map<String, String> entrypoints,
    required Map<String, String> commandAliases,
    required List<DistributionFile> files,
  }) : entrypoints = Map<String, String>.unmodifiable(entrypoints),
       commandAliases = Map<String, String>.unmodifiable(commandAliases),
       files = List<DistributionFile>.unmodifiable(
         List<DistributionFile>.of(files)
           ..sort((left, right) => left.path.compareTo(right.path)),
       ) {
    _semanticVersion(releaseVersion, 'releaseVersion');
    _semanticVersion(coreVersion, 'coreVersion');
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(platform)) {
      throw FormatException('Invalid distribution platform: $platform');
    }
    const requiredEntrypoints = <String>{'cli', 'host', 'gateway', 'studio'};
    if (entrypoints.keys.toSet().length != requiredEntrypoints.length ||
        !entrypoints.keys.toSet().containsAll(requiredEntrypoints)) {
      throw ArgumentError('Distribution entrypoints are incomplete');
    }
    for (final path in entrypoints.values) {
      _relativePath(path);
    }
    final aliasKeys = commandAliases.keys.toSet();
    final descriptorAliases = distribution.commandAliases.toSet();
    if (aliasKeys.length != descriptorAliases.length ||
        !aliasKeys.containsAll(descriptorAliases)) {
      throw ArgumentError('Manifest aliases differ from descriptor aliases');
    }
    for (final entry in commandAliases.entries) {
      if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(entry.key) ||
          entry.key == 'devex_host' ||
          entry.key == 'backend_gateway' ||
          entry.value != entrypoints['cli']) {
        throw ArgumentError('Distribution command alias is invalid');
      }
    }
    if (this.files.isEmpty ||
        _duplicates(this.files.map((file) => file.path))) {
      throw ArgumentError('Distribution files must be non-empty and unique');
    }
    final paths = this.files.map((file) => file.path).toSet();
    if (!paths.containsAll(entrypoints.values)) {
      throw ArgumentError('Distribution entrypoints are not packaged files');
    }
    for (final key in <String>['cli', 'host', 'gateway']) {
      final file = this.files.singleWhere(
        (candidate) => candidate.path == entrypoints[key],
      );
      if (!file.executable) {
        throw ArgumentError('Distribution $key entrypoint is not executable');
      }
    }
  }

  static const int schemaVersion = 1;

  @override
  int get manifestVersion => schemaVersion;

  @override
  String get distributionId => distribution.id;

  @override
  List<String> get distributionCommandAliases => distribution.commandAliases;

  final DistributionDescriptor distribution;
  @override
  final String releaseVersion;
  @override
  final String coreVersion;
  @override
  final String platform;
  @override
  final Map<String, String> entrypoints;
  @override
  final Map<String, String> commandAliases;
  @override
  final List<DistributionFile> files;

  @override
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'DistributionReleaseManifest',
    'distribution': distribution.toJson(),
    'releaseVersion': releaseVersion,
    'coreVersion': coreVersion,
    'platform': platform,
    'entrypoints': entrypoints,
    'commandAliases': commandAliases,
    'files': files.map((file) => file.toJson()).toList(growable: false),
    if (includeDigest) 'digest': digest.value,
  };

  factory DistributionReleaseManifest.fromJson(Object? value) {
    final json = _object(value, 'DistributionReleaseManifest');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'distribution',
      'releaseVersion',
      'coreVersion',
      'platform',
      'entrypoints',
      'commandAliases',
      'files',
      'digest',
    }, 'DistributionReleaseManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'DistributionReleaseManifest') {
      throw const FormatException(
        'Invalid DistributionReleaseManifest version',
      );
    }
    final manifest = DistributionReleaseManifest(
      distribution: DistributionDescriptor.fromJson(json['distribution']),
      releaseVersion: _string(
        json,
        'releaseVersion',
        'DistributionReleaseManifest',
      ),
      coreVersion: _string(json, 'coreVersion', 'DistributionReleaseManifest'),
      platform: _string(json, 'platform', 'DistributionReleaseManifest'),
      entrypoints: _stringMap(
        json['entrypoints'],
        'DistributionReleaseManifest.entrypoints',
      ),
      commandAliases: _stringMap(
        json['commandAliases'],
        'DistributionReleaseManifest.commandAliases',
      ),
      files: _list(
        json['files'],
        'DistributionReleaseManifest.files',
      ).map(DistributionFile.fromJson).toList(growable: false),
    );
    if (manifest.digest !=
        Digest(_string(json, 'digest', 'DistributionReleaseManifest'))) {
      throw const FormatException('Distribution release digest mismatch');
    }
    return manifest;
  }
}

final class DistributionDocumentReference {
  DistributionDocumentReference({required this.path, required this.digest}) {
    _relativePath(path);
  }

  final String path;
  final Digest digest;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'digest': digest.value,
  };

  factory DistributionDocumentReference.fromJson(Object? value) {
    final json = _object(value, 'DistributionDocumentReference');
    _only(json, const <String>{
      'path',
      'digest',
    }, 'DistributionDocumentReference');
    return DistributionDocumentReference(
      path: _string(json, 'path', 'DistributionDocumentReference'),
      digest: Digest(_string(json, 'digest', 'DistributionDocumentReference')),
    );
  }
}

final class DistributionDescriptorV2 {
  DistributionDescriptorV2({
    required this.id,
    required this.displayName,
    required this.coreCompatibility,
    required this.defaultLayout,
    required this.moduleCatalog,
    required this.defaultProfileId,
    List<String> commandAliases = const <String>[],
  }) : commandAliases = List<String>.unmodifiable(commandAliases) {
    OpaqueId.validate(id, 'Distribution');
    if (displayName.isEmpty) {
      throw ArgumentError.value(displayName, 'displayName');
    }
    if (!RegExp(r'^\^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(coreCompatibility)) {
      throw FormatException('Invalid coreCompatibility: $coreCompatibility');
    }
    OpaqueId.validate(defaultProfileId, 'KitProfile');
    if (_duplicates(commandAliases)) {
      throw ArgumentError('Distribution aliases must be unique');
    }
    for (final alias in commandAliases) {
      if (!RegExp(r'^[a-z][a-z0-9_-]{0,63}$').hasMatch(alias)) {
        throw ArgumentError('Distribution command alias is invalid');
      }
    }
  }

  static const int schemaVersion = 2;
  final String id;
  final String displayName;
  final String coreCompatibility;
  final ConsumerLayout defaultLayout;
  final List<String> commandAliases;
  final DistributionDocumentReference moduleCatalog;
  final String defaultProfileId;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'displayName': displayName,
    'coreCompatibility': coreCompatibility,
    'defaultLayout': defaultLayout.toJson(),
    'commandAliases': commandAliases,
    'moduleCatalog': moduleCatalog.toJson(),
    'defaultProfileId': defaultProfileId,
  };

  factory DistributionDescriptorV2.fromJson(Object? value) {
    final json = _object(value, 'DistributionDescriptorV2');
    _only(json, const <String>{
      'schemaVersion',
      'id',
      'displayName',
      'coreCompatibility',
      'defaultLayout',
      'commandAliases',
      'moduleCatalog',
      'defaultProfileId',
    }, 'DistributionDescriptorV2');
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Invalid DistributionDescriptorV2 version');
    }
    return DistributionDescriptorV2(
      id: _string(json, 'id', 'DistributionDescriptorV2'),
      displayName: _string(json, 'displayName', 'DistributionDescriptorV2'),
      coreCompatibility: _string(
        json,
        'coreCompatibility',
        'DistributionDescriptorV2',
      ),
      defaultLayout: ConsumerLayout.fromJson(json['defaultLayout']),
      commandAliases: _stringList(
        json['commandAliases'],
        'DistributionDescriptorV2.commandAliases',
      ),
      moduleCatalog: DistributionDocumentReference.fromJson(
        json['moduleCatalog'],
      ),
      defaultProfileId: _string(
        json,
        'defaultProfileId',
        'DistributionDescriptorV2',
      ),
    );
  }
}

enum DistributionComponentKind { executable, webAssets }

final class DistributionComponent {
  DistributionComponent({
    required this.id,
    required this.kind,
    required this.path,
    required List<String> moduleIds,
  }) : moduleIds = List<String>.unmodifiable(
         List<String>.of(moduleIds)..sort(),
       ) {
    OpaqueId.validate(id, 'DistributionComponent');
    _relativePath(path);
    if (_duplicates(this.moduleIds)) {
      throw ArgumentError('Distribution component module IDs must be unique');
    }
    for (final moduleId in this.moduleIds) {
      OpaqueId.validate(moduleId, 'Module');
    }
  }

  final String id;
  final DistributionComponentKind kind;
  final String path;
  final List<String> moduleIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'path': path,
    'moduleIds': moduleIds,
  };

  factory DistributionComponent.fromJson(Object? value) {
    final json = _object(value, 'DistributionComponent');
    _only(json, const <String>{
      'id',
      'kind',
      'path',
      'moduleIds',
    }, 'DistributionComponent');
    final kind = _string(json, 'kind', 'DistributionComponent');
    return DistributionComponent(
      id: _string(json, 'id', 'DistributionComponent'),
      kind: DistributionComponentKind.values.singleWhere(
        (candidate) => candidate.name == kind,
        orElse: () =>
            throw FormatException('Invalid DistributionComponent.kind: $kind'),
      ),
      path: _string(json, 'path', 'DistributionComponent'),
      moduleIds: _stringList(
        json['moduleIds'],
        'DistributionComponent.moduleIds',
      ),
    );
  }
}

final class DistributionReleaseManifestV2 implements DistributionRelease {
  DistributionReleaseManifestV2({
    required this.distribution,
    required this.releaseVersion,
    required this.coreVersion,
    required this.platform,
    required this.moduleCatalog,
    required List<String> modules,
    required List<String> profiles,
    required List<DistributionComponent> components,
    required Map<String, String> entrypoints,
    required Map<String, String> commandAliases,
    required List<DistributionFile> files,
  }) : modules = List<String>.unmodifiable(List<String>.of(modules)..sort()),
       profiles = List<String>.unmodifiable(List<String>.of(profiles)..sort()),
       components = List<DistributionComponent>.unmodifiable(
         List<DistributionComponent>.of(components)
           ..sort((left, right) => left.id.compareTo(right.id)),
       ),
       entrypoints = Map<String, String>.unmodifiable(entrypoints),
       commandAliases = Map<String, String>.unmodifiable(commandAliases),
       files = List<DistributionFile>.unmodifiable(
         List<DistributionFile>.of(files)
           ..sort((left, right) => left.path.compareTo(right.path)),
       ) {
    _semanticVersion(releaseVersion, 'releaseVersion');
    _semanticVersion(coreVersion, 'coreVersion');
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(platform)) {
      throw FormatException('Invalid distribution platform: $platform');
    }
    for (final id in <String>[...this.modules, ...this.profiles]) {
      OpaqueId.validate(id, 'Packaged item');
    }
    if (this.modules.isEmpty ||
        this.profiles.isEmpty ||
        this.components.isEmpty ||
        this.files.isEmpty ||
        _duplicates(this.modules) ||
        _duplicates(this.profiles) ||
        _duplicates(this.components.map((item) => item.id)) ||
        _duplicates(this.files.map((item) => item.path))) {
      throw ArgumentError(
        'Distribution v2 inventories must be non-empty and unique',
      );
    }
    if (distribution.moduleCatalog.path != moduleCatalog.path ||
        distribution.moduleCatalog.digest != moduleCatalog.digest ||
        !this.profiles.contains(distribution.defaultProfileId)) {
      throw ArgumentError('Distribution v2 descriptor differs from inventory');
    }
    if (entrypoints['cli'] == null) {
      throw ArgumentError('Distribution v2 requires the CLI entrypoint');
    }
    for (final path in entrypoints.values) {
      _relativePath(path);
    }
    final paths = this.files.map((file) => file.path).toSet();
    if (!paths.contains(moduleCatalog.path) ||
        !paths.containsAll(entrypoints.values)) {
      throw ArgumentError('Distribution v2 entrypoints or catalog are missing');
    }
    final packagedModules = this.modules.toSet();
    for (final component in this.components) {
      if (!paths.contains(component.path) ||
          !packagedModules.containsAll(component.moduleIds)) {
        throw ArgumentError('Distribution component is not packaged exactly');
      }
    }
    for (final file in this.files) {
      if (!packagedModules.containsAll(file.moduleIds)) {
        throw ArgumentError(
          'Distribution file references an unpackaged module',
        );
      }
    }
    final aliasKeys = commandAliases.keys.toSet();
    if (aliasKeys.length != distribution.commandAliases.length ||
        !aliasKeys.containsAll(distribution.commandAliases) ||
        commandAliases.values.any((path) => path != entrypoints['cli'])) {
      throw ArgumentError('Distribution v2 aliases differ from descriptor');
    }
    for (final entry in entrypoints.entries) {
      if (entry.key == 'studio') continue;
      final file = this.files.singleWhere(
        (candidate) => candidate.path == entry.value,
      );
      if (!file.executable) {
        throw ArgumentError(
          'Distribution ${entry.key} entrypoint is not executable',
        );
      }
    }
  }

  static const int schemaVersion = 2;
  @override
  int get manifestVersion => schemaVersion;
  final DistributionDescriptorV2 distribution;
  @override
  String get distributionId => distribution.id;
  @override
  List<String> get distributionCommandAliases => distribution.commandAliases;
  @override
  final String releaseVersion;
  @override
  final String coreVersion;
  @override
  final String platform;
  final DistributionDocumentReference moduleCatalog;
  final List<String> modules;
  final List<String> profiles;
  final List<DistributionComponent> components;
  @override
  final Map<String, String> entrypoints;
  @override
  final Map<String, String> commandAliases;
  @override
  final List<DistributionFile> files;

  @override
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'DistributionReleaseManifest',
    'distribution': distribution.toJson(),
    'releaseVersion': releaseVersion,
    'coreVersion': coreVersion,
    'platform': platform,
    'moduleCatalog': moduleCatalog.toJson(),
    'modules': modules,
    'profiles': profiles,
    'components': <Object?>[
      for (final component in components) component.toJson(),
    ],
    'entrypoints': entrypoints,
    'commandAliases': commandAliases,
    'files': <Object?>[
      for (final file in files)
        <String, Object?>{...file.toJson(), 'moduleIds': file.moduleIds},
    ],
    if (includeDigest) 'digest': digest.value,
  };

  factory DistributionReleaseManifestV2.fromJson(Object? value) {
    final json = _object(value, 'DistributionReleaseManifestV2');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'distribution',
      'releaseVersion',
      'coreVersion',
      'platform',
      'moduleCatalog',
      'modules',
      'profiles',
      'components',
      'entrypoints',
      'commandAliases',
      'files',
      'digest',
    }, 'DistributionReleaseManifestV2');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'DistributionReleaseManifest') {
      throw const FormatException(
        'Invalid DistributionReleaseManifestV2 version',
      );
    }
    final manifest = DistributionReleaseManifestV2(
      distribution: DistributionDescriptorV2.fromJson(json['distribution']),
      releaseVersion: _string(
        json,
        'releaseVersion',
        'DistributionReleaseManifestV2',
      ),
      coreVersion: _string(
        json,
        'coreVersion',
        'DistributionReleaseManifestV2',
      ),
      platform: _string(json, 'platform', 'DistributionReleaseManifestV2'),
      moduleCatalog: DistributionDocumentReference.fromJson(
        json['moduleCatalog'],
      ),
      modules: _stringList(
        json['modules'],
        'DistributionReleaseManifestV2.modules',
      ),
      profiles: _stringList(
        json['profiles'],
        'DistributionReleaseManifestV2.profiles',
      ),
      components: _list(
        json['components'],
        'DistributionReleaseManifestV2.components',
      ).map(DistributionComponent.fromJson).toList(growable: false),
      entrypoints: _stringMap(
        json['entrypoints'],
        'DistributionReleaseManifestV2.entrypoints',
      ),
      commandAliases: _stringMap(
        json['commandAliases'],
        'DistributionReleaseManifestV2.commandAliases',
      ),
      files: _list(
        json['files'],
        'DistributionReleaseManifestV2.files',
      ).map(DistributionFile.fromJson).toList(growable: false),
    );
    if (manifest.digest !=
        Digest(_string(json, 'digest', 'DistributionReleaseManifestV2'))) {
      throw const FormatException('Distribution v2 release digest mismatch');
    }
    return manifest;
  }
}

final class DistributionReleaseCodec {
  const DistributionReleaseCodec();

  DistributionRelease fromJson(Object? value) {
    final json = _object(value, 'DistributionReleaseManifest');
    return switch (json['schemaVersion']) {
      1 => DistributionReleaseManifest.fromJson(json),
      2 => DistributionReleaseManifestV2.fromJson(json),
      _ => throw const FormatException(
        'Unsupported distribution release version',
      ),
    };
  }
}

void _semanticVersion(String value, String name) {
  if (!RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
  ).hasMatch(value)) {
    throw FormatException('Invalid $name: $value');
  }
}

void _relativePath(String value) {
  final normalized = value.replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized.split('/').contains('..')) {
    throw FormatException('Distribution path must be relative: $value');
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

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

Map<String, String> _stringMap(Object? value, String path) {
  final object = _object(value, path);
  if (object.values.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path must contain non-empty strings');
  }
  return object.cast<String, String>();
}

List<String> _stringList(Object? value, String path) {
  final list = _list(value, path);
  if (list.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path must contain non-empty strings');
  }
  return list.cast<String>();
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

bool _duplicates(Iterable<Object?> values) {
  final seen = <Object?>{};
  for (final value in values) {
    if (!seen.add(value)) return true;
  }
  return false;
}
