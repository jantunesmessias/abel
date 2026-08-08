import '../catalog/catalog_contracts.dart';
import '../digest.dart';

enum ModuleSurface {
  cli,
  host,
  studio,
  gateway,
  hostedControlPlane,
  remoteWorker,
}

enum ModuleEffect { query, ephemeral, authoring, infrastructure, decision }

enum ModuleResource {
  filesystemRead,
  filesystemWrite,
  process,
  network,
  listener,
  device,
}

enum ProviderCardinality { single, multiple }

enum ProviderSelectionPolicy { orderedFirstAvailable, all }

enum ModuleDiagnosticSeverity { info, warning, error }

enum ModuleRuntimeState {
  disabled,
  notPackaged,
  unsupported,
  dependencyMissing,
  policyDenied,
  starting,
  ready,
  degraded,
  failed,
  stopping,
  stopped,
}

enum ModuleHealth { notApplicable, unknown, healthy, degraded, unhealthy }

final class ModuleId extends OpaqueId {
  factory ModuleId(String value) {
    OpaqueId.validate(value, 'Module');
    return ModuleId._(value);
  }

  const ModuleId._(super.value);
}

final class ModuleCapabilityRef {
  ModuleCapabilityRef({required this.id, required this.version}) {
    OpaqueId.validate(id, 'ModuleCapability');
    if (version <= 0) throw ArgumentError.value(version, 'version');
  }

  final String id;
  final int version;

  String get key => '$id@$version';

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'version': version,
  };

  factory ModuleCapabilityRef.fromJson(Object? value) {
    final json = _object(value, 'ModuleCapabilityRef');
    _only(json, const <String>{'id', 'version'}, 'ModuleCapabilityRef');
    return ModuleCapabilityRef(
      id: _string(json, 'id', 'ModuleCapabilityRef'),
      version: _integer(json, 'version', 'ModuleCapabilityRef'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ModuleCapabilityRef &&
      other.id == id &&
      other.version == version;

  @override
  int get hashCode => Object.hash(id, version);
}

final class ModuleRequirement {
  ModuleRequirement({
    required this.capability,
    this.cardinality = ProviderCardinality.single,
  });

  final ModuleCapabilityRef capability;
  final ProviderCardinality cardinality;

  Map<String, Object?> toJson() => <String, Object?>{
    'capability': capability.toJson(),
    'cardinality': cardinality.name,
  };

  factory ModuleRequirement.fromJson(Object? value) {
    final json = _object(value, 'ModuleRequirement');
    _only(json, const <String>{
      'capability',
      'cardinality',
    }, 'ModuleRequirement');
    return ModuleRequirement(
      capability: ModuleCapabilityRef.fromJson(json['capability']),
      cardinality: _enumValue(
        ProviderCardinality.values,
        _string(json, 'cardinality', 'ModuleRequirement'),
        'ModuleRequirement.cardinality',
      ),
    );
  }
}

final class ModuleDescriptor {
  ModuleDescriptor({
    required this.id,
    required this.version,
    required this.coreCompatibility,
    required List<ModuleCapabilityRef> provides,
    List<ModuleRequirement> requires = const <ModuleRequirement>[],
    List<ModuleRequirement> optionalRequires = const <ModuleRequirement>[],
    List<ModuleId> conflicts = const <ModuleId>[],
    required Set<String> supportedPlatforms,
    Set<ModuleSurface> surfaces = const <ModuleSurface>{},
    Set<ModuleEffect> effects = const <ModuleEffect>{},
    Set<ModuleResource> resourceRequirements = const <ModuleResource>{},
    this.configurationSchema,
  }) : provides = _sortedCapabilities(provides),
       requires = _sortedRequirements(requires),
       optionalRequires = _sortedRequirements(optionalRequires),
       conflicts = _sortedModuleIds(conflicts),
       supportedPlatforms = Set<String>.unmodifiable(
         supportedPlatforms.toList()..sort(),
       ),
       surfaces = Set<ModuleSurface>.unmodifiable(surfaces),
       effects = Set<ModuleEffect>.unmodifiable(effects),
       resourceRequirements = Set<ModuleResource>.unmodifiable(
         resourceRequirements,
       ) {
    _semanticVersion(version, 'ModuleDescriptor.version');
    _coreCompatibility(coreCompatibility, 'ModuleDescriptor.coreCompatibility');
    if (this.provides.isEmpty ||
        _duplicates(this.provides.map((item) => item.key))) {
      throw ArgumentError(
        'ModuleDescriptor.provides must be non-empty and unique',
      );
    }
    if (_duplicates(this.requires.map((item) => item.capability.key)) ||
        _duplicates(this.optionalRequires.map((item) => item.capability.key))) {
      throw ArgumentError('Module requirements must be unique');
    }
    final providedIds = this.provides.map((item) => item.id).toSet();
    final requiredKeys = this.requires
        .map((item) => item.capability.key)
        .toSet();
    final optionalKeys = this.optionalRequires
        .map((item) => item.capability.key)
        .toSet();
    if (this.requires.any((item) => providedIds.contains(item.capability.id)) ||
        this.optionalRequires.any(
          (item) => providedIds.contains(item.capability.id),
        )) {
      throw ArgumentError('A module cannot require a capability it provides');
    }
    if (requiredKeys.intersection(optionalKeys).isNotEmpty) {
      throw ArgumentError('Required and optional capabilities overlap');
    }
    if (_duplicates(this.conflicts.map((item) => item.value)) ||
        this.conflicts.contains(id)) {
      throw ArgumentError('Module conflicts are invalid');
    }
    if (this.supportedPlatforms.isEmpty ||
        this.supportedPlatforms.any(
          (item) =>
              !RegExp(r'^(?:any|[a-z0-9]+(?:-[a-z0-9]+)*)$').hasMatch(item),
        )) {
      throw ArgumentError('Module supported platforms are invalid');
    }
    if (configurationSchema != null) {
      final uri = Uri.tryParse(configurationSchema!);
      if (uri == null ||
          !uri.hasScheme ||
          configurationSchema!.contains(RegExp(r'\s'))) {
        throw FormatException(
          'Module configurationSchema must be an absolute URI',
        );
      }
    }
  }

  static const int schemaVersion = 1;
  final ModuleId id;
  final String version;
  final String coreCompatibility;
  final List<ModuleCapabilityRef> provides;
  final List<ModuleRequirement> requires;
  final List<ModuleRequirement> optionalRequires;
  final List<ModuleId> conflicts;
  final Set<String> supportedPlatforms;
  final Set<ModuleSurface> surfaces;
  final Set<ModuleEffect> effects;
  final Set<ModuleResource> resourceRequirements;
  final String? configurationSchema;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ModuleDescriptor',
    'id': id.value,
    'version': version,
    'coreCompatibility': coreCompatibility,
    'provides': <Object?>[for (final item in provides) item.toJson()],
    'requires': <Object?>[for (final item in requires) item.toJson()],
    'optionalRequires': <Object?>[
      for (final item in optionalRequires) item.toJson(),
    ],
    'conflicts': <String>[for (final item in conflicts) item.value],
    'supportedPlatforms': supportedPlatforms.toList()..sort(),
    'surfaces': surfaces.map((item) => item.name).toList()..sort(),
    'effects': effects.map((item) => item.name).toList()..sort(),
    'resourceRequirements':
        resourceRequirements.map((item) => item.name).toList()..sort(),
    if (configurationSchema != null) 'configurationSchema': configurationSchema,
    if (includeDigest) 'digest': digest.value,
  };

  factory ModuleDescriptor.fromJson(Object? value) {
    final json = _document(value, 'ModuleDescriptor', const <String>{
      'id',
      'version',
      'coreCompatibility',
      'provides',
      'requires',
      'optionalRequires',
      'conflicts',
      'supportedPlatforms',
      'surfaces',
      'effects',
      'resourceRequirements',
      'configurationSchema',
    });
    final descriptor = ModuleDescriptor(
      id: ModuleId(_string(json, 'id', 'ModuleDescriptor')),
      version: _string(json, 'version', 'ModuleDescriptor'),
      coreCompatibility: _string(json, 'coreCompatibility', 'ModuleDescriptor'),
      provides: _list(
        json,
        'provides',
        'ModuleDescriptor',
      ).map(ModuleCapabilityRef.fromJson).toList(growable: false),
      requires: _list(
        json,
        'requires',
        'ModuleDescriptor',
      ).map(ModuleRequirement.fromJson).toList(growable: false),
      optionalRequires: _list(
        json,
        'optionalRequires',
        'ModuleDescriptor',
      ).map(ModuleRequirement.fromJson).toList(growable: false),
      conflicts: _stringList(
        json,
        'conflicts',
        'ModuleDescriptor',
      ).map(ModuleId.new).toList(growable: false),
      supportedPlatforms: _stringList(
        json,
        'supportedPlatforms',
        'ModuleDescriptor',
      ).toSet(),
      surfaces: _enumSet(
        ModuleSurface.values,
        json['surfaces'],
        'ModuleDescriptor.surfaces',
      ),
      effects: _enumSet(
        ModuleEffect.values,
        json['effects'],
        'ModuleDescriptor.effects',
      ),
      resourceRequirements: _enumSet(
        ModuleResource.values,
        json['resourceRequirements'],
        'ModuleDescriptor.resourceRequirements',
      ),
      configurationSchema: _optionalString(
        json,
        'configurationSchema',
        'ModuleDescriptor',
      ),
    );
    _verifyDigest(json, descriptor.digest, 'ModuleDescriptor');
    return descriptor;
  }
}

final class KitModuleSelection {
  KitModuleSelection({
    required this.moduleId,
    required this.enabled,
    Map<String, Object?> settings = const <String, Object?>{},
  }) : settings = _immutableMap(settings, 'KitModuleSelection.settings');

  final ModuleId moduleId;
  final bool enabled;
  final Map<String, Object?> settings;

  Map<String, Object?> toJson() => <String, Object?>{
    'moduleId': moduleId.value,
    'enabled': enabled,
    'settings': settings,
  };

  factory KitModuleSelection.fromJson(Object? value) {
    final json = _object(value, 'KitModuleSelection');
    _only(json, const <String>{
      'moduleId',
      'enabled',
      'settings',
    }, 'KitModuleSelection');
    return KitModuleSelection(
      moduleId: ModuleId(_string(json, 'moduleId', 'KitModuleSelection')),
      enabled: _boolean(json, 'enabled', 'KitModuleSelection'),
      settings: _jsonMap(json['settings'], 'KitModuleSelection.settings'),
    );
  }
}

final class ProviderBinding {
  ProviderBinding({
    required this.capability,
    required List<ModuleId> providerModuleIds,
    required this.selectionPolicy,
    this.applicationId,
    Map<String, Object?> settings = const <String, Object?>{},
  }) : providerModuleIds = List<ModuleId>.unmodifiable(providerModuleIds),
       settings = _immutableMap(settings, 'ProviderBinding.settings') {
    if (this.providerModuleIds.isEmpty ||
        _duplicates(this.providerModuleIds.map((item) => item.value))) {
      throw ArgumentError(
        'ProviderBinding providers must be non-empty and unique',
      );
    }
    if (applicationId != null) OpaqueId.validate(applicationId!, 'Application');
    if (selectionPolicy == ProviderSelectionPolicy.orderedFirstAvailable &&
        this.providerModuleIds.isEmpty) {
      throw ArgumentError('Ordered provider binding requires providers');
    }
  }

  final ModuleCapabilityRef capability;
  final List<ModuleId> providerModuleIds;
  final ProviderSelectionPolicy selectionPolicy;
  final String? applicationId;
  final Map<String, Object?> settings;

  String get key => '${applicationId ?? '*'}:${capability.key}';

  Map<String, Object?> toJson() => <String, Object?>{
    'capability': capability.toJson(),
    'providerModuleIds': <String>[
      for (final provider in providerModuleIds) provider.value,
    ],
    'selectionPolicy': selectionPolicy.name,
    if (applicationId != null) 'applicationId': applicationId,
    'settings': settings,
  };

  factory ProviderBinding.fromJson(Object? value) {
    final json = _object(value, 'ProviderBinding');
    _only(json, const <String>{
      'capability',
      'providerModuleIds',
      'selectionPolicy',
      'applicationId',
      'settings',
    }, 'ProviderBinding');
    return ProviderBinding(
      capability: ModuleCapabilityRef.fromJson(json['capability']),
      providerModuleIds: _stringList(
        json,
        'providerModuleIds',
        'ProviderBinding',
      ).map(ModuleId.new).toList(growable: false),
      selectionPolicy: _enumValue(
        ProviderSelectionPolicy.values,
        _string(json, 'selectionPolicy', 'ProviderBinding'),
        'ProviderBinding.selectionPolicy',
      ),
      applicationId: _optionalString(json, 'applicationId', 'ProviderBinding'),
      settings: _jsonMap(json['settings'], 'ProviderBinding.settings'),
    );
  }
}

final class KitSelection {
  KitSelection({
    required List<KitModuleSelection> modules,
    List<ProviderBinding> providerBindings = const <ProviderBinding>[],
  }) : modules = List<KitModuleSelection>.unmodifiable(
         List<KitModuleSelection>.of(modules)..sort(
           (left, right) => left.moduleId.value.compareTo(right.moduleId.value),
         ),
       ),
       providerBindings = List<ProviderBinding>.unmodifiable(
         List<ProviderBinding>.of(providerBindings)
           ..sort((left, right) => left.key.compareTo(right.key)),
       ) {
    if (_duplicates(this.modules.map((item) => item.moduleId.value)) ||
        _duplicates(this.providerBindings.map((item) => item.key))) {
      throw ArgumentError('KitSelection entries must be unique');
    }
  }

  final List<KitModuleSelection> modules;
  final List<ProviderBinding> providerBindings;

  Map<String, Object?> toJson() => <String, Object?>{
    'modules': <Object?>[for (final module in modules) module.toJson()],
    'providerBindings': <Object?>[
      for (final binding in providerBindings) binding.toJson(),
    ],
  };

  factory KitSelection.fromJson(Object? value) {
    final json = _object(value, 'KitSelection');
    _only(json, const <String>{'modules', 'providerBindings'}, 'KitSelection');
    return KitSelection(
      modules: _list(
        json,
        'modules',
        'KitSelection',
      ).map(KitModuleSelection.fromJson).toList(growable: false),
      providerBindings: _list(
        json,
        'providerBindings',
        'KitSelection',
      ).map(ProviderBinding.fromJson).toList(growable: false),
    );
  }
}

final class KitProfile {
  KitProfile({
    required this.id,
    required this.displayName,
    required this.selection,
  }) {
    OpaqueId.validate(id, 'KitProfile');
    _nonEmpty(displayName, 'KitProfile.displayName');
  }

  static const int schemaVersion = 1;
  final String id;
  final String displayName;
  final KitSelection selection;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'KitProfile',
    'id': id,
    'displayName': displayName,
    'selection': selection.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory KitProfile.fromJson(Object? value) {
    final json = _document(value, 'KitProfile', const <String>{
      'id',
      'displayName',
      'selection',
    });
    final profile = KitProfile(
      id: _string(json, 'id', 'KitProfile'),
      displayName: _string(json, 'displayName', 'KitProfile'),
      selection: KitSelection.fromJson(json['selection']),
    );
    _verifyDigest(json, profile.digest, 'KitProfile');
    return profile;
  }
}

final class ModuleCatalog {
  ModuleCatalog({
    required this.distributionId,
    required this.coreVersion,
    required this.platform,
    required List<ModuleDescriptor> modules,
    required List<KitProfile> profiles,
    required this.defaultProfileId,
  }) : modules = List<ModuleDescriptor>.unmodifiable(
         List<ModuleDescriptor>.of(modules)
           ..sort((left, right) => left.id.value.compareTo(right.id.value)),
       ),
       profiles = List<KitProfile>.unmodifiable(
         List<KitProfile>.of(profiles)
           ..sort((left, right) => left.id.compareTo(right.id)),
       ) {
    OpaqueId.validate(distributionId, 'Distribution');
    _semanticVersion(coreVersion, 'ModuleCatalog.coreVersion');
    _platform(platform, 'ModuleCatalog.platform');
    OpaqueId.validate(defaultProfileId, 'KitProfile');
    if (this.modules.isEmpty ||
        _duplicates(this.modules.map((item) => item.id.value)) ||
        this.profiles.isEmpty ||
        _duplicates(this.profiles.map((item) => item.id))) {
      throw ArgumentError('ModuleCatalog modules/profiles are invalid');
    }
    final moduleIds = this.modules.map((item) => item.id).toSet();
    if (!this.profiles.any((item) => item.id == defaultProfileId)) {
      throw ArgumentError('ModuleCatalog default profile is missing');
    }
    for (final profile in this.profiles) {
      final referenced = <ModuleId>{
        ...profile.selection.modules.map((item) => item.moduleId),
        ...profile.selection.providerBindings.expand(
          (item) => item.providerModuleIds,
        ),
      };
      if (!moduleIds.containsAll(referenced)) {
        throw ArgumentError(
          'KitProfile ${profile.id} references unpackaged modules',
        );
      }
    }
  }

  static const int schemaVersion = 1;
  final String distributionId;
  final String coreVersion;
  final String platform;
  final List<ModuleDescriptor> modules;
  final List<KitProfile> profiles;
  final String defaultProfileId;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ModuleCatalog',
    'distributionId': distributionId,
    'coreVersion': coreVersion,
    'platform': platform,
    'modules': <Object?>[for (final module in modules) module.toJson()],
    'profiles': <Object?>[for (final profile in profiles) profile.toJson()],
    'defaultProfileId': defaultProfileId,
    if (includeDigest) 'digest': digest.value,
  };

  factory ModuleCatalog.fromJson(Object? value) {
    final json = _document(value, 'ModuleCatalog', const <String>{
      'distributionId',
      'coreVersion',
      'platform',
      'modules',
      'profiles',
      'defaultProfileId',
    });
    final catalog = ModuleCatalog(
      distributionId: _string(json, 'distributionId', 'ModuleCatalog'),
      coreVersion: _string(json, 'coreVersion', 'ModuleCatalog'),
      platform: _string(json, 'platform', 'ModuleCatalog'),
      modules: _list(
        json,
        'modules',
        'ModuleCatalog',
      ).map(ModuleDescriptor.fromJson).toList(growable: false),
      profiles: _list(
        json,
        'profiles',
        'ModuleCatalog',
      ).map(KitProfile.fromJson).toList(growable: false),
      defaultProfileId: _string(json, 'defaultProfileId', 'ModuleCatalog'),
    );
    _verifyDigest(json, catalog.digest, 'ModuleCatalog');
    return catalog;
  }
}

final class ModuleDiagnostic {
  ModuleDiagnostic({
    this.moduleId,
    required this.code,
    required this.severity,
    required this.message,
  }) {
    OpaqueId.validate(code, 'ModuleDiagnostic');
    _boundedText(message, 'ModuleDiagnostic.message', 2048);
  }

  final ModuleId? moduleId;
  final String code;
  final ModuleDiagnosticSeverity severity;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    if (moduleId != null) 'moduleId': moduleId!.value,
    'code': code,
    'severity': severity.name,
    'message': message,
  };

  factory ModuleDiagnostic.fromJson(Object? value) {
    final json = _object(value, 'ModuleDiagnostic');
    _only(json, const <String>{
      'moduleId',
      'code',
      'severity',
      'message',
    }, 'ModuleDiagnostic');
    final moduleId = _optionalString(json, 'moduleId', 'ModuleDiagnostic');
    return ModuleDiagnostic(
      moduleId: moduleId == null ? null : ModuleId(moduleId),
      code: _string(json, 'code', 'ModuleDiagnostic'),
      severity: _enumValue(
        ModuleDiagnosticSeverity.values,
        _string(json, 'severity', 'ModuleDiagnostic'),
        'ModuleDiagnostic.severity',
      ),
      message: _string(json, 'message', 'ModuleDiagnostic'),
    );
  }
}

final class ResolvedModule {
  ResolvedModule({
    required this.moduleId,
    required this.descriptorDigest,
    Map<String, Object?> settings = const <String, Object?>{},
  }) : settings = _immutableMap(settings, 'ResolvedModule.settings');

  final ModuleId moduleId;
  final Digest descriptorDigest;
  final Map<String, Object?> settings;

  Map<String, Object?> toJson() => <String, Object?>{
    'moduleId': moduleId.value,
    'descriptorDigest': descriptorDigest.value,
    'settings': settings,
  };

  factory ResolvedModule.fromJson(Object? value) {
    final json = _object(value, 'ResolvedModule');
    _only(json, const <String>{
      'moduleId',
      'descriptorDigest',
      'settings',
    }, 'ResolvedModule');
    return ResolvedModule(
      moduleId: ModuleId(_string(json, 'moduleId', 'ResolvedModule')),
      descriptorDigest: Digest(
        _string(json, 'descriptorDigest', 'ResolvedModule'),
      ),
      settings: _jsonMap(json['settings'], 'ResolvedModule.settings'),
    );
  }
}

final class ResolvedKitPlan {
  ResolvedKitPlan({
    required this.distributionDigest,
    required this.profileId,
    required List<ResolvedModule> enabledModules,
    List<ProviderBinding> providerBindings = const <ProviderBinding>[],
    required List<ModuleId> dependencyOrder,
    required this.startupPolicy,
    List<ModuleDiagnostic> diagnostics = const <ModuleDiagnostic>[],
  }) : enabledModules = List<ResolvedModule>.unmodifiable(
         List<ResolvedModule>.of(enabledModules)..sort(
           (left, right) => left.moduleId.value.compareTo(right.moduleId.value),
         ),
       ),
       providerBindings = List<ProviderBinding>.unmodifiable(
         List<ProviderBinding>.of(providerBindings)
           ..sort((left, right) => left.key.compareTo(right.key)),
       ),
       dependencyOrder = List<ModuleId>.unmodifiable(dependencyOrder),
       diagnostics = List<ModuleDiagnostic>.unmodifiable(diagnostics) {
    OpaqueId.validate(profileId, 'KitProfile');
    OpaqueId.validate(startupPolicy, 'StartupPolicy');
    if (this.enabledModules.isEmpty ||
        _duplicates(this.enabledModules.map((item) => item.moduleId.value)) ||
        _duplicates(this.providerBindings.map((item) => item.key)) ||
        _duplicates(this.dependencyOrder.map((item) => item.value))) {
      throw ArgumentError('ResolvedKitPlan entries are invalid');
    }
    final enabledIds = this.enabledModules.map((item) => item.moduleId).toSet();
    if (this.dependencyOrder.length != enabledIds.length ||
        !enabledIds.containsAll(this.dependencyOrder)) {
      throw ArgumentError(
        'dependencyOrder must contain every enabled module once',
      );
    }
    for (final binding in this.providerBindings) {
      if (!enabledIds.containsAll(binding.providerModuleIds)) {
        throw ArgumentError('Provider binding references a disabled module');
      }
    }
  }

  static const int schemaVersion = 1;
  final Digest distributionDigest;
  final String profileId;
  final List<ResolvedModule> enabledModules;
  final List<ProviderBinding> providerBindings;
  final List<ModuleId> dependencyOrder;
  final String startupPolicy;
  final List<ModuleDiagnostic> diagnostics;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ResolvedKitPlan',
    'distributionDigest': distributionDigest.value,
    'profileId': profileId,
    'enabledModules': <Object?>[
      for (final module in enabledModules) module.toJson(),
    ],
    'providerBindings': <Object?>[
      for (final binding in providerBindings) binding.toJson(),
    ],
    'dependencyOrder': <String>[
      for (final module in dependencyOrder) module.value,
    ],
    'startupPolicy': startupPolicy,
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
    if (includeDigest) 'digest': digest.value,
  };

  factory ResolvedKitPlan.fromJson(Object? value) {
    final json = _document(value, 'ResolvedKitPlan', const <String>{
      'distributionDigest',
      'profileId',
      'enabledModules',
      'providerBindings',
      'dependencyOrder',
      'startupPolicy',
      'diagnostics',
    });
    final plan = ResolvedKitPlan(
      distributionDigest: Digest(
        _string(json, 'distributionDigest', 'ResolvedKitPlan'),
      ),
      profileId: _string(json, 'profileId', 'ResolvedKitPlan'),
      enabledModules: _list(
        json,
        'enabledModules',
        'ResolvedKitPlan',
      ).map(ResolvedModule.fromJson).toList(growable: false),
      providerBindings: _list(
        json,
        'providerBindings',
        'ResolvedKitPlan',
      ).map(ProviderBinding.fromJson).toList(growable: false),
      dependencyOrder: _stringList(
        json,
        'dependencyOrder',
        'ResolvedKitPlan',
      ).map(ModuleId.new).toList(growable: false),
      startupPolicy: _string(json, 'startupPolicy', 'ResolvedKitPlan'),
      diagnostics: _list(
        json,
        'diagnostics',
        'ResolvedKitPlan',
      ).map(ModuleDiagnostic.fromJson).toList(growable: false),
    );
    _verifyDigest(json, plan.digest, 'ResolvedKitPlan');
    return plan;
  }
}

final class EffectiveModuleState {
  EffectiveModuleState({
    required this.moduleId,
    required this.state,
    required this.health,
    List<ModuleCapabilityRef> effectiveCapabilities =
        const <ModuleCapabilityRef>[],
    List<ModuleDiagnostic> diagnostics = const <ModuleDiagnostic>[],
  }) : effectiveCapabilities = _sortedCapabilities(effectiveCapabilities),
       diagnostics = List<ModuleDiagnostic>.unmodifiable(diagnostics) {
    final validHealth = switch (state) {
      ModuleRuntimeState.ready =>
        health == ModuleHealth.healthy || health == ModuleHealth.degraded,
      ModuleRuntimeState.degraded => health == ModuleHealth.degraded,
      ModuleRuntimeState.failed => health == ModuleHealth.unhealthy,
      ModuleRuntimeState.starting ||
      ModuleRuntimeState.stopping => health == ModuleHealth.unknown,
      _ => health == ModuleHealth.notApplicable,
    };
    if (!validHealth) {
      throw ArgumentError(
        'Module state ${state.name} is incompatible with ${health.name}',
      );
    }
    if (state != ModuleRuntimeState.ready &&
        state != ModuleRuntimeState.degraded &&
        this.effectiveCapabilities.isNotEmpty) {
      throw ArgumentError(
        'Inactive modules cannot expose effective capabilities',
      );
    }
  }

  final ModuleId moduleId;
  final ModuleRuntimeState state;
  final ModuleHealth health;
  final List<ModuleCapabilityRef> effectiveCapabilities;
  final List<ModuleDiagnostic> diagnostics;

  Map<String, Object?> toJson() => <String, Object?>{
    'moduleId': moduleId.value,
    'state': state.name,
    'health': health.name,
    'effectiveCapabilities': <Object?>[
      for (final capability in effectiveCapabilities) capability.toJson(),
    ],
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
  };

  factory EffectiveModuleState.fromJson(Object? value) {
    final json = _object(value, 'EffectiveModuleState');
    _only(json, const <String>{
      'moduleId',
      'state',
      'health',
      'effectiveCapabilities',
      'diagnostics',
    }, 'EffectiveModuleState');
    return EffectiveModuleState(
      moduleId: ModuleId(_string(json, 'moduleId', 'EffectiveModuleState')),
      state: _enumValue(
        ModuleRuntimeState.values,
        _string(json, 'state', 'EffectiveModuleState'),
        'EffectiveModuleState.state',
      ),
      health: _enumValue(
        ModuleHealth.values,
        _string(json, 'health', 'EffectiveModuleState'),
        'EffectiveModuleState.health',
      ),
      effectiveCapabilities: _list(
        json,
        'effectiveCapabilities',
        'EffectiveModuleState',
      ).map(ModuleCapabilityRef.fromJson).toList(growable: false),
      diagnostics: _list(
        json,
        'diagnostics',
        'EffectiveModuleState',
      ).map(ModuleDiagnostic.fromJson).toList(growable: false),
    );
  }
}

final class EffectiveKitManifest {
  EffectiveKitManifest({
    required this.resolvedPlanDigest,
    required List<EffectiveModuleState> modules,
    required List<String> commands,
    required List<String> rpcMethods,
    required List<String> studioContributions,
    required DateTime generatedAt,
  }) : modules = List<EffectiveModuleState>.unmodifiable(
         List<EffectiveModuleState>.of(modules)..sort(
           (left, right) => left.moduleId.value.compareTo(right.moduleId.value),
         ),
       ),
       commands = _sortedStrings(commands, 'EffectiveKitManifest.commands'),
       rpcMethods = _sortedStrings(
         rpcMethods,
         'EffectiveKitManifest.rpcMethods',
       ),
       studioContributions = _sortedStrings(
         studioContributions,
         'EffectiveKitManifest.studioContributions',
       ),
       generatedAt = generatedAt.toUtc() {
    if (_duplicates(this.modules.map((item) => item.moduleId.value))) {
      throw ArgumentError('EffectiveKitManifest modules must be unique');
    }
  }

  static const int schemaVersion = 1;
  final Digest resolvedPlanDigest;
  final List<EffectiveModuleState> modules;
  final List<String> commands;
  final List<String> rpcMethods;
  final List<String> studioContributions;
  final DateTime generatedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'EffectiveKitManifest',
    'resolvedPlanDigest': resolvedPlanDigest.value,
    'modules': <Object?>[for (final module in modules) module.toJson()],
    'commands': commands,
    'rpcMethods': rpcMethods,
    'studioContributions': studioContributions,
    'generatedAt': generatedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory EffectiveKitManifest.fromJson(Object? value) {
    final json = _document(value, 'EffectiveKitManifest', const <String>{
      'resolvedPlanDigest',
      'modules',
      'commands',
      'rpcMethods',
      'studioContributions',
      'generatedAt',
    });
    final manifest = EffectiveKitManifest(
      resolvedPlanDigest: Digest(
        _string(json, 'resolvedPlanDigest', 'EffectiveKitManifest'),
      ),
      modules: _list(
        json,
        'modules',
        'EffectiveKitManifest',
      ).map(EffectiveModuleState.fromJson).toList(growable: false),
      commands: _stringList(json, 'commands', 'EffectiveKitManifest'),
      rpcMethods: _stringList(json, 'rpcMethods', 'EffectiveKitManifest'),
      studioContributions: _stringList(
        json,
        'studioContributions',
        'EffectiveKitManifest',
      ),
      generatedAt: _dateTime(json, 'generatedAt', 'EffectiveKitManifest'),
    );
    _verifyDigest(json, manifest.digest, 'EffectiveKitManifest');
    return manifest;
  }
}

List<ModuleCapabilityRef> _sortedCapabilities(
  Iterable<ModuleCapabilityRef> values,
) {
  final result = List<ModuleCapabilityRef>.of(values)
    ..sort((left, right) => left.key.compareTo(right.key));
  if (_duplicates(result.map((item) => item.key))) {
    throw ArgumentError('Module capabilities must be unique');
  }
  return List<ModuleCapabilityRef>.unmodifiable(result);
}

List<ModuleRequirement> _sortedRequirements(
  Iterable<ModuleRequirement> values,
) => List<ModuleRequirement>.unmodifiable(
  List<ModuleRequirement>.of(
    values,
  )..sort((left, right) => left.capability.key.compareTo(right.capability.key)),
);

List<ModuleId> _sortedModuleIds(Iterable<ModuleId> values) =>
    List<ModuleId>.unmodifiable(
      List<ModuleId>.of(values)
        ..sort((left, right) => left.value.compareTo(right.value)),
    );

List<String> _sortedStrings(Iterable<String> values, String path) {
  final result = List<String>.of(values)..sort();
  if (result.any((item) => item.isEmpty || item.length > 256) ||
      _duplicates(result)) {
    throw ArgumentError('$path must contain unique bounded strings');
  }
  return List<String>.unmodifiable(result);
}

Map<String, Object?> _document(Object? value, String kind, Set<String> fields) {
  final json = _object(value, kind);
  _only(json, <String>{'schemaVersion', 'kind', ...fields, 'digest'}, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind has invalid schemaVersion or kind');
  }
  return json;
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string when present');
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

List<Object?> _list(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be an array');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> json, String key, String path) {
  final values = _list(json, key, path);
  if (values.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path.$key must contain non-empty strings');
  }
  return values.cast<String>();
}

Map<String, Object?> _jsonMap(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

T _enumValue<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has invalid value $name');
}

Set<T> _enumSet<T extends Enum>(List<T> values, Object? raw, String path) {
  if (raw is! List<Object?> || raw.any((item) => item is! String)) {
    throw FormatException('$path must be a string array');
  }
  final result = raw
      .cast<String>()
      .map((item) => _enumValue(values, item, path))
      .toSet();
  if (result.length != raw.length) {
    throw FormatException('$path must be unique');
  }
  return result;
}

DateTime _dateTime(Map<String, Object?> json, String key, String path) {
  final raw = _string(json, key, path);
  final value = DateTime.tryParse(raw);
  if (value == null || !value.isUtc || !raw.endsWith('Z')) {
    throw FormatException('$path.$key must be UTC RFC 3339');
  }
  return value;
}

void _verifyDigest(Map<String, Object?> json, Digest expected, String path) {
  final actual = Digest(_string(json, 'digest', path));
  if (actual != expected) throw FormatException('$path digest mismatch');
}

Map<String, Object?> _immutableMap(Map<String, Object?> value, String path) {
  final sortedKeys = value.keys.toList()..sort();
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final key in sortedKeys) key: _immutableJson(value[key], '$path.$key'),
  });
}

Object? _immutableJson(Object? value, String path) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double && value.isFinite) return value;
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(<Object?>[
      for (var index = 0; index < value.length; index += 1)
        _immutableJson(value[index], '$path[$index]'),
    ]);
  }
  if (value is Map<String, Object?>) return _immutableMap(value, path);
  throw FormatException('$path is not a JSON value');
}

bool _duplicates(Iterable<Object?> values) {
  final seen = <Object?>{};
  for (final value in values) {
    if (!seen.add(value)) return true;
  }
  return false;
}

void _semanticVersion(String value, String path) {
  if (!RegExp(
    r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$',
  ).hasMatch(value)) {
    throw FormatException('$path must be a semantic version');
  }
}

void _coreCompatibility(String value, String path) {
  if (!RegExp(r'^\^[0-9]+\.[0-9]+\.[0-9]+$').hasMatch(value)) {
    throw FormatException('$path must be a caret semantic version');
  }
}

void _platform(String value, String path) {
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value)) {
    throw FormatException('$path is invalid');
  }
}

void _nonEmpty(String value, String path) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, path);
}

void _boundedText(String value, String path, int maxLength) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw ArgumentError.value(value, path);
  }
}
