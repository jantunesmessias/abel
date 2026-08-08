enum PluginEffect { query, ephemeral, authoring, infrastructure, decision }

final class PluginCapability {
  PluginCapability({required this.name, required this.effect}) {
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(name)) {
      throw FormatException('Invalid plugin capability: $name');
    }
  }

  final String name;
  final PluginEffect effect;
  bool get mutating => effect != PluginEffect.query;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'effect': effect.name,
  };

  factory PluginCapability.fromJson(Object? value) {
    final json = _pluginObject(value, 'PluginCapability');
    _pluginOnly(json, const <String>{'name', 'effect'}, 'PluginCapability');
    final effectName = _pluginString(json, 'effect', 'PluginCapability');
    final effect = PluginEffect.values
        .where((item) => item.name == effectName)
        .firstOrNull;
    if (effect == null) {
      throw FormatException('Invalid PluginCapability.effect: $effectName');
    }
    return PluginCapability(
      name: _pluginString(json, 'name', 'PluginCapability'),
      effect: effect,
    );
  }
}

final class PluginManifest {
  PluginManifest({
    required this.id,
    required this.executable,
    required this.coreCompatibility,
    required List<int> protocolVersions,
    required List<PluginCapability> capabilities,
  }) : protocolVersions = List<int>.unmodifiable(
         List<int>.of(protocolVersions)..sort(),
       ),
       capabilities = List<PluginCapability>.unmodifiable(
         List<PluginCapability>.of(capabilities)
           ..sort((a, b) => a.name.compareTo(b.name)),
       ) {
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(id)) {
      throw FormatException('Invalid plugin ID: $id');
    }
    if (executable.isEmpty || executable.contains('\u0000')) {
      throw const FormatException('Invalid plugin executable');
    }
    if (!RegExp(r'^\^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(coreCompatibility)) {
      throw const FormatException('Invalid plugin core compatibility');
    }
    if (this.protocolVersions.isEmpty ||
        this.protocolVersions.toSet().length != this.protocolVersions.length ||
        this.protocolVersions.any((version) => version <= 0)) {
      throw ArgumentError('Plugin protocol versions are invalid');
    }
    if (this.capabilities.isEmpty ||
        this.capabilities.map((item) => item.name).toSet().length !=
            this.capabilities.length) {
      throw ArgumentError('Plugin capabilities are invalid');
    }
  }

  static const int schemaVersion = 1;
  final String id;
  final String executable;
  final String coreCompatibility;
  final List<int> protocolVersions;
  final List<PluginCapability> capabilities;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'PluginManifest',
    'id': id,
    'executable': executable,
    'coreCompatibility': coreCompatibility,
    'protocolVersions': protocolVersions,
    'capabilities': <Object?>[
      for (final capability in capabilities) capability.toJson(),
    ],
  };

  factory PluginManifest.fromJson(Object? value) {
    final json = _pluginObject(value, 'PluginManifest');
    _pluginOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'executable',
      'coreCompatibility',
      'protocolVersions',
      'capabilities',
    }, 'PluginManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'PluginManifest') {
      throw const FormatException('Invalid PluginManifest version or kind');
    }
    final versions = json['protocolVersions'];
    final capabilities = json['capabilities'];
    if (versions is! List<Object?> ||
        versions.any((item) => item is! int) ||
        capabilities is! List<Object?>) {
      throw const FormatException('Invalid PluginManifest arrays');
    }
    return PluginManifest(
      id: _pluginString(json, 'id', 'PluginManifest'),
      executable: _pluginString(json, 'executable', 'PluginManifest'),
      coreCompatibility: _pluginString(
        json,
        'coreCompatibility',
        'PluginManifest',
      ),
      protocolVersions: versions.cast<int>(),
      capabilities: capabilities
          .map(PluginCapability.fromJson)
          .toList(growable: false),
    );
  }
}

Map<String, Object?> _pluginObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _pluginOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _pluginString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}
