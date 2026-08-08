import 'package:experience_contracts/experience_contracts.dart';

/// A closed resolution failure produced before any module is allowed to cause
/// effects.
final class KitPlanResolutionException implements Exception {
  KitPlanResolutionException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(issues.toSet().toList()..sort()) {
    if (this.issues.isEmpty) {
      throw ArgumentError('KitPlanResolutionException requires issues');
    }
  }

  final List<String> issues;

  @override
  String toString() => 'Kit plan resolution failed:\n${issues.join('\n')}';
}

/// Selects a profile without applying any hidden product behavior.
final class KitProfileExpander {
  const KitProfileExpander();

  KitProfile expand(ModuleCatalog catalog, {String? profileId}) {
    final selectedProfileId = profileId ?? catalog.defaultProfileId;
    for (final profile in catalog.profiles) {
      if (profile.id == selectedProfileId) return profile;
    }
    throw KitPlanResolutionException(<String>[
      'profile $selectedProfileId is not packaged by ${catalog.distributionId}',
    ]);
  }
}

/// Applies configuration layers in ascending precedence. A later module entry
/// replaces `enabled` and deep-merges settings; a later provider binding with
/// the same key replaces the earlier binding.
final class KitConfigurationNormalizer {
  const KitConfigurationNormalizer();

  KitSelection normalize(List<KitSelection> layers) {
    final modules = <ModuleId, KitModuleSelection>{};
    final bindings = <String, ProviderBinding>{};
    for (final layer in layers) {
      for (final module in layer.modules) {
        final previous = modules[module.moduleId];
        modules[module.moduleId] = KitModuleSelection(
          moduleId: module.moduleId,
          enabled: module.enabled,
          settings: _deepMerge(previous?.settings, module.settings),
        );
      }
      for (final binding in layer.providerBindings) {
        bindings[binding.key] = binding;
      }
    }
    return KitSelection(
      modules: modules.values.toList(growable: false),
      providerBindings: bindings.values.toList(growable: false),
    );
  }
}

/// Resolves a packaged module catalog and declarative overlays into one
/// canonical plan. This class is deliberately pure: it does not read files,
/// start processes, bind listeners, or probe devices.
final class KitPlanResolver {
  const KitPlanResolver();

  ResolvedKitPlan resolve({
    required ModuleCatalog catalog,
    String? profileId,
    List<KitSelection> defaults = const <KitSelection>[],
    List<KitSelection> overlays = const <KitSelection>[],
    Map<String, Object?> configurationSchemas = const <String, Object?>{},
    String startupPolicy = 'fail-required-v1',
  }) {
    final issues = <String>[];
    final profile = const KitProfileExpander().expand(
      catalog,
      profileId: profileId,
    );

    final selection = const KitConfigurationNormalizer().normalize(
      <KitSelection>[...defaults, profile.selection, ...overlays],
    );
    final descriptorsById = <ModuleId, ModuleDescriptor>{
      for (final descriptor in catalog.modules) descriptor.id: descriptor,
    };
    for (final module in selection.modules) {
      if (!descriptorsById.containsKey(module.moduleId)) {
        issues.add(
          'module ${module.moduleId.value} is not packaged by '
          '${catalog.distributionId}',
        );
      }
    }

    final enabledSelections = <ModuleId, KitModuleSelection>{
      for (final module in selection.modules)
        if (module.enabled && descriptorsById.containsKey(module.moduleId))
          module.moduleId: module,
    };
    if (enabledSelections.isEmpty) {
      issues.add('selection enables no packaged modules');
    }
    final enabledDescriptors = <ModuleId, ModuleDescriptor>{
      for (final entry in enabledSelections.entries)
        entry.key: descriptorsById[entry.key]!,
    };

    _validateCompatibility(catalog, enabledDescriptors.values, issues);
    _validateConflicts(enabledDescriptors, issues);
    _validateSettings(
      enabledSelections,
      enabledDescriptors,
      configurationSchemas,
      issues,
    );

    final bindingResolution = _resolveBindings(
      enabledDescriptors,
      selection.providerBindings,
      issues,
    );
    final dependencyOrder = _dependencyOrder(
      enabledDescriptors,
      bindingResolution.globalBindings,
      issues,
    );

    if (issues.isNotEmpty) throw KitPlanResolutionException(issues);

    return ResolvedKitPlan(
      distributionDigest: catalog.digest,
      profileId: profile.id,
      enabledModules: <ResolvedModule>[
        for (final entry in enabledSelections.entries)
          ResolvedModule(
            moduleId: entry.key,
            descriptorDigest: enabledDescriptors[entry.key]!.digest,
            settings: entry.value.settings,
          ),
      ],
      providerBindings: bindingResolution.effectiveBindings,
      dependencyOrder: dependencyOrder,
      startupPolicy: startupPolicy,
    );
  }
}

Map<String, Object?> _deepMerge(
  Map<String, Object?>? base,
  Map<String, Object?> overlay,
) {
  final merged = <String, Object?>{...?base};
  for (final entry in overlay.entries) {
    final previous = merged[entry.key];
    final next = entry.value;
    if (previous is Map<String, Object?> && next is Map<String, Object?>) {
      merged[entry.key] = _deepMerge(previous, next);
    } else {
      merged[entry.key] = next;
    }
  }
  return merged;
}

void _validateCompatibility(
  ModuleCatalog catalog,
  Iterable<ModuleDescriptor> descriptors,
  List<String> issues,
) {
  final coreVersion = _SemanticVersion.parse(catalog.coreVersion);
  for (final descriptor in descriptors) {
    if (!_allowsCaret(descriptor.coreCompatibility, coreVersion)) {
      issues.add(
        '${descriptor.id.value} requires core '
        '${descriptor.coreCompatibility}, but the distribution provides '
        '${catalog.coreVersion}',
      );
    }
    if (!descriptor.supportedPlatforms.contains('any') &&
        !descriptor.supportedPlatforms.contains(catalog.platform)) {
      issues.add('${descriptor.id.value} does not support ${catalog.platform}');
    }
  }
}

void _validateConflicts(
  Map<ModuleId, ModuleDescriptor> enabled,
  List<String> issues,
) {
  for (final descriptor in enabled.values) {
    for (final conflict in descriptor.conflicts) {
      if (enabled.containsKey(conflict)) {
        issues.add('${descriptor.id.value} conflicts with ${conflict.value}');
      }
    }
  }
}

void _validateSettings(
  Map<ModuleId, KitModuleSelection> selections,
  Map<ModuleId, ModuleDescriptor> descriptors,
  Map<String, Object?> configurationSchemas,
  List<String> issues,
) {
  for (final entry in selections.entries) {
    final descriptor = descriptors[entry.key]!;
    final schemaId = descriptor.configurationSchema;
    if (schemaId == null) {
      if (entry.value.settings.isNotEmpty) {
        issues.add(
          '${entry.key.value} declares settings but has no configuration schema',
        );
      }
      continue;
    }
    final schema = configurationSchemas[schemaId];
    if (schema == null) {
      issues.add(
        '${entry.key.value} has no registered configuration schema for '
        '$schemaId',
      );
      continue;
    }
    try {
      final result = Draft202012Validator(
        schema,
      ).validate(entry.value.settings);
      for (final issue in result.issues) {
        final path = issue.instancePath.isEmpty ? r'$' : issue.instancePath;
        issues.add('${entry.key.value} settings at $path: ${issue.message}');
      }
    } on FormatException catch (error) {
      issues.add('${entry.key.value} configuration schema is invalid: $error');
    }
  }
}

_BindingResolution _resolveBindings(
  Map<ModuleId, ModuleDescriptor> enabled,
  List<ProviderBinding> configuredBindings,
  List<String> issues,
) {
  final providersByCapability = <String, List<ModuleId>>{};
  for (final descriptor in enabled.values) {
    for (final capability in descriptor.provides) {
      providersByCapability
          .putIfAbsent(capability.key, () => <ModuleId>[])
          .add(descriptor.id);
    }
  }
  for (final providers in providersByCapability.values) {
    providers.sort((left, right) => left.value.compareTo(right.value));
  }

  final requirements = <String, List<_RequirementConsumer>>{};
  for (final descriptor in enabled.values) {
    for (final requirement in descriptor.requires) {
      requirements
          .putIfAbsent(
            requirement.capability.key,
            () => <_RequirementConsumer>[],
          )
          .add(
            _RequirementConsumer(descriptor.id, requirement, required: true),
          );
    }
    for (final requirement in descriptor.optionalRequires) {
      requirements
          .putIfAbsent(
            requirement.capability.key,
            () => <_RequirementConsumer>[],
          )
          .add(
            _RequirementConsumer(descriptor.id, requirement, required: false),
          );
    }
  }

  final configuredByKey = <String, ProviderBinding>{
    for (final binding in configuredBindings) binding.key: binding,
  };
  for (final binding in configuredBindings) {
    final consumers = requirements[binding.capability.key];
    if (consumers == null) {
      issues.add(
        'provider binding ${binding.key} is not required by an enabled module',
      );
    }
    _validateBinding(
      binding,
      consumers ?? const <_RequirementConsumer>[],
      enabled,
      issues,
    );
  }

  final effectiveBindings = <ProviderBinding>[...configuredBindings];
  final globalBindings = <String, ProviderBinding>{};
  final sortedCapabilityKeys = requirements.keys.toList()..sort();
  for (final capabilityKey in sortedCapabilityKeys) {
    final consumers = requirements[capabilityKey]!;
    final capability = consumers.first.requirement.capability;
    final providers =
        providersByCapability[capabilityKey] ?? const <ModuleId>[];
    final globalKey = '*:$capabilityKey';
    final explicit = configuredByKey[globalKey];
    if (explicit != null) {
      globalBindings[capabilityKey] = explicit;
      continue;
    }

    final requiredConsumers = consumers.where((item) => item.required).toList();
    if (providers.isEmpty) {
      for (final consumer in requiredConsumers) {
        issues.add(
          '${consumer.moduleId.value} requires missing capability '
          '$capabilityKey',
        );
      }
      continue;
    }
    if (providers.length > 1) {
      issues.add(
        'module selection requires an explicit provider binding for '
        '$capabilityKey',
      );
      continue;
    }

    final binding = ProviderBinding(
      capability: capability,
      providerModuleIds: providers,
      selectionPolicy: ProviderSelectionPolicy.orderedFirstAvailable,
    );
    effectiveBindings.add(binding);
    globalBindings[capabilityKey] = binding;
  }

  effectiveBindings.sort((left, right) => left.key.compareTo(right.key));
  return _BindingResolution(effectiveBindings, globalBindings);
}

void _validateBinding(
  ProviderBinding binding,
  List<_RequirementConsumer> consumers,
  Map<ModuleId, ModuleDescriptor> enabled,
  List<String> issues,
) {
  for (final providerId in binding.providerModuleIds) {
    final provider = enabled[providerId];
    if (provider == null) {
      issues.add(
        'provider binding ${binding.key} references disabled module '
        '${providerId.value}',
      );
      continue;
    }
    if (!provider.provides.contains(binding.capability)) {
      issues.add(
        '${providerId.value} does not provide ${binding.capability.key}',
      );
    }
  }
  if (binding.selectionPolicy == ProviderSelectionPolicy.all &&
      binding.providerModuleIds.length > 1 &&
      consumers.any(
        (item) => item.requirement.cardinality == ProviderCardinality.single,
      )) {
    issues.add(
      'provider binding ${binding.key} selects multiple providers for a '
      'single-cardinality requirement',
    );
  }
}

List<ModuleId> _dependencyOrder(
  Map<ModuleId, ModuleDescriptor> enabled,
  Map<String, ProviderBinding> globalBindings,
  List<String> issues,
) {
  final dependents = <ModuleId, Set<ModuleId>>{
    for (final moduleId in enabled.keys) moduleId: <ModuleId>{},
  };
  final incomingCount = <ModuleId, int>{
    for (final moduleId in enabled.keys) moduleId: 0,
  };
  for (final descriptor in enabled.values) {
    for (final requirement in <ModuleRequirement>[
      ...descriptor.requires,
      ...descriptor.optionalRequires,
    ]) {
      final binding = globalBindings[requirement.capability.key];
      if (binding == null) continue;
      for (final providerId in binding.providerModuleIds) {
        if (!enabled.containsKey(providerId) || providerId == descriptor.id) {
          continue;
        }
        if (dependents[providerId]!.add(descriptor.id)) {
          incomingCount[descriptor.id] = incomingCount[descriptor.id]! + 1;
        }
      }
    }
  }

  final ready =
      incomingCount.entries
          .where((entry) => entry.value == 0)
          .map((entry) => entry.key)
          .toList()
        ..sort((left, right) => left.value.compareTo(right.value));
  final ordered = <ModuleId>[];
  while (ready.isNotEmpty) {
    final current = ready.removeAt(0);
    ordered.add(current);
    final nextModules = dependents[current]!.toList()
      ..sort((left, right) => left.value.compareTo(right.value));
    for (final next in nextModules) {
      final remaining = incomingCount[next]! - 1;
      incomingCount[next] = remaining;
      if (remaining == 0) {
        ready.add(next);
        ready.sort((left, right) => left.value.compareTo(right.value));
      }
    }
  }
  if (ordered.length != enabled.length) {
    final cycle =
        incomingCount.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key.value)
            .toList()
          ..sort();
    issues.add('dependency cycle among ${cycle.join(', ')}');
  }
  return ordered;
}

bool _allowsCaret(String constraint, _SemanticVersion version) {
  final lower = _SemanticVersion.parse(constraint.substring(1));
  final upper = switch ((lower.major, lower.minor)) {
    (> 0, _) => _SemanticVersion(lower.major + 1, 0, 0),
    (0, > 0) => _SemanticVersion(0, lower.minor + 1, 0),
    _ => _SemanticVersion(0, 0, lower.patch + 1),
  };
  return version.compareTo(lower) >= 0 && version.compareTo(upper) < 0;
}

final class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(
    this.major,
    this.minor,
    this.patch, [
    this.preRelease = const <String>[],
  ]);

  factory _SemanticVersion.parse(String value) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid semantic version: $value');
    }
    return _SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4)?.split('.') ?? const <String>[],
    );
  }

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  @override
  int compareTo(_SemanticVersion other) {
    for (final pair in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final comparison = pair.$1.compareTo(pair.$2);
      if (comparison != 0) return comparison;
    }
    if (preRelease.isEmpty || other.preRelease.isEmpty) {
      if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
      return preRelease.isEmpty ? 1 : -1;
    }
    final length = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < length; index += 1) {
      final left = int.tryParse(preRelease[index]);
      final right = int.tryParse(other.preRelease[index]);
      final comparison = switch ((left, right)) {
        (final int left, final int right) => left.compareTo(right),
        (final int _, null) => -1,
        (null, final int _) => 1,
        _ => preRelease[index].compareTo(other.preRelease[index]),
      };
      if (comparison != 0) return comparison;
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }
}

final class _RequirementConsumer {
  const _RequirementConsumer(
    this.moduleId,
    this.requirement, {
    required this.required,
  });

  final ModuleId moduleId;
  final ModuleRequirement requirement;
  final bool required;
}

final class _BindingResolution {
  const _BindingResolution(this.effectiveBindings, this.globalBindings);

  final List<ProviderBinding> effectiveBindings;
  final Map<String, ProviderBinding> globalBindings;
}
