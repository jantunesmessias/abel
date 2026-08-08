import 'dart:async';

import 'package:devex_contracts/devex_contracts.dart';

typedef BuiltinModuleFactory = BuiltinModule Function(ModuleContext context);
typedef ModuleClock = DateTime Function();
typedef ModuleCleanup = FutureOr<void> Function();

abstract interface class BuiltinModule {
  FutureOr<void> prepare();

  FutureOr<ModuleStartResult> start();

  FutureOr<void> stop();

  FutureOr<void> dispose();
}

final class ModuleContribution {
  ModuleContribution({
    List<String> commands = const <String>[],
    List<String> rpcMethods = const <String>[],
    List<String> studioContributions = const <String>[],
  }) : commands = _sortedUnique(commands, 'commands'),
       rpcMethods = _sortedUnique(rpcMethods, 'rpcMethods'),
       studioContributions = _sortedUnique(
         studioContributions,
         'studioContributions',
       );

  final List<String> commands;
  final List<String> rpcMethods;
  final List<String> studioContributions;

  static final ModuleContribution none = ModuleContribution();
}

final class ModuleStartResult {
  ModuleStartResult({
    required Map<ModuleCapabilityRef, Object> capabilities,
    ModuleContribution? contribution,
  }) : capabilities = Map<ModuleCapabilityRef, Object>.unmodifiable(
         capabilities,
       ),
       contribution = contribution ?? ModuleContribution.none;

  final Map<ModuleCapabilityRef, Object> capabilities;
  final ModuleContribution contribution;
}

final class ModuleCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void throwIfCancelled() {
    if (isCancelled) throw const ModuleStartupCancelled();
  }

  void _cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class ModuleStartupCancelled implements Exception {
  const ModuleStartupCancelled();

  @override
  String toString() => 'Module startup was cancelled';
}

final class ModuleResourceOwner {
  final List<ModuleCleanup> _cleanups = <ModuleCleanup>[];
  var _released = false;

  void own(ModuleCleanup cleanup) {
    if (_released) throw StateError('Module resources were already released');
    _cleanups.add(cleanup);
  }

  Future<List<Object>> releaseAll() async {
    if (_released) return const <Object>[];
    _released = true;
    final failures = <Object>[];
    for (final cleanup in _cleanups.reversed) {
      try {
        await cleanup();
      } on Object catch (error) {
        failures.add(error);
      }
    }
    _cleanups.clear();
    return failures;
  }
}

final class ModuleHealthReporter {
  ModuleHealthReporter._(this._moduleId, this._onChanged);

  final ModuleId _moduleId;
  final void Function(ModuleId, bool, ModuleDiagnostic?) _onChanged;

  void degraded({required String code, required String message}) {
    _onChanged(
      _moduleId,
      true,
      ModuleDiagnostic(
        moduleId: _moduleId,
        code: code,
        severity: ModuleDiagnosticSeverity.warning,
        message: message,
      ),
    );
  }

  void healthy() => _onChanged(_moduleId, false, null);
}

final class ModuleCapabilityAccess {
  ModuleCapabilityAccess._({
    required this.moduleId,
    required this._requiredCapabilities,
    required this._optionalCapabilities,
    required this._bindings,
    required this._exports,
  });

  final ModuleId moduleId;
  final Set<ModuleCapabilityRef> _requiredCapabilities;
  final Set<ModuleCapabilityRef> _optionalCapabilities;
  final Map<String, ProviderBinding> _bindings;
  final Map<ModuleId, Map<ModuleCapabilityRef, Object>> _exports;

  T require<T>(ModuleCapabilityRef capability) {
    if (!_requiredCapabilities.contains(capability)) {
      throw StateError(
        '${moduleId.value} did not declare required ${capability.key}',
      );
    }
    final values = _values<T>(capability);
    if (values.isEmpty) {
      throw StateError('Required capability ${capability.key} is not ready');
    }
    return values.first;
  }

  T? optional<T>(ModuleCapabilityRef capability) {
    if (!_optionalCapabilities.contains(capability)) {
      throw StateError(
        '${moduleId.value} did not declare optional ${capability.key}',
      );
    }
    return _values<T>(capability).firstOrNull;
  }

  List<T> all<T>(ModuleCapabilityRef capability) {
    if (!_requiredCapabilities.contains(capability) &&
        !_optionalCapabilities.contains(capability)) {
      throw StateError('${moduleId.value} did not declare ${capability.key}');
    }
    return List<T>.unmodifiable(_values<T>(capability));
  }

  List<T> _values<T>(ModuleCapabilityRef capability) {
    final binding = _bindings[capability.key];
    if (binding == null) return <T>[];
    final values = <T>[];
    for (final providerId in binding.providerModuleIds) {
      final value = _exports[providerId]?[capability];
      if (value == null) continue;
      if (value case final T typedValue) {
        values.add(typedValue);
      } else {
        throw StateError(
          '${providerId.value} exported '
          '${capability.key} with an invalid type',
        );
      }
      if (binding.selectionPolicy ==
          ProviderSelectionPolicy.orderedFirstAvailable) {
        break;
      }
    }
    return values;
  }
}

final class ModuleContext {
  ModuleContext._({
    required this.moduleId,
    required this.settings,
    required this.capabilities,
    required this.cancellation,
    required this.resources,
    required this.health,
  });

  final ModuleId moduleId;
  final Map<String, Object?> settings;
  final ModuleCapabilityAccess capabilities;
  final ModuleCancellationToken cancellation;
  final ModuleResourceOwner resources;
  final ModuleHealthReporter health;
}

final class ModuleFactoryRegistry {
  ModuleFactoryRegistry(Map<ModuleId, BuiltinModuleFactory> factories)
    : _factories = Map<ModuleId, BuiltinModuleFactory>.unmodifiable(factories) {
    if (factories.isEmpty) {
      throw ArgumentError('ModuleFactoryRegistry must not be empty');
    }
  }

  final Map<ModuleId, BuiltinModuleFactory> _factories;

  Set<ModuleId> get moduleIds => Set<ModuleId>.unmodifiable(_factories.keys);

  BuiltinModule create(ModuleId moduleId, ModuleContext context) {
    final factory = _factories[moduleId];
    if (factory == null) {
      throw StateError('No packaged factory for ${moduleId.value}');
    }
    return factory(context);
  }
}

final class ModuleStartupException implements Exception {
  const ModuleStartupException({
    required this.moduleId,
    required this.cause,
    required this.manifest,
  });

  final ModuleId moduleId;
  final Object cause;
  final EffectiveKitManifest manifest;

  @override
  String toString() =>
      'Module ${moduleId.value} failed during startup: ${cause.runtimeType}';
}

final class ModuleLifecycleCoordinator {
  ModuleLifecycleCoordinator({
    required this.catalog,
    required this.plan,
    required this.factories,
    ModuleClock? clock,
  }) : clock = clock ?? _systemModuleClock {
    if (plan.distributionDigest != catalog.digest) {
      throw ArgumentError('Resolved plan does not belong to this catalog');
    }
    final descriptors = <ModuleId, ModuleDescriptor>{
      for (final descriptor in catalog.modules) descriptor.id: descriptor,
    };
    for (final module in plan.enabledModules) {
      final descriptor = descriptors[module.moduleId];
      if (descriptor == null || descriptor.digest != module.descriptorDigest) {
        throw ArgumentError(
          'Resolved module ${module.moduleId.value} is not packaged exactly',
        );
      }
      if (!factories.moduleIds.contains(module.moduleId)) {
        throw ArgumentError(
          'Resolved module ${module.moduleId.value} has no packaged factory',
        );
      }
    }
    _descriptors = descriptors;
    _settings = <ModuleId, Map<String, Object?>>{
      for (final module in plan.enabledModules)
        module.moduleId: module.settings,
    };
    _globalBindings = <String, ProviderBinding>{
      for (final binding in plan.providerBindings)
        if (binding.applicationId == null) binding.capability.key: binding,
    };
    for (final descriptor in catalog.modules) {
      _states[descriptor.id] = _MutableModuleState(
        state: _settings.containsKey(descriptor.id)
            ? ModuleRuntimeState.stopped
            : ModuleRuntimeState.disabled,
        health: ModuleHealth.notApplicable,
      );
    }
  }

  final ModuleCatalog catalog;
  final ResolvedKitPlan plan;
  final ModuleFactoryRegistry factories;
  final ModuleClock clock;
  late final Map<ModuleId, ModuleDescriptor> _descriptors;
  late final Map<ModuleId, Map<String, Object?>> _settings;
  late final Map<String, ProviderBinding> _globalBindings;
  final Map<ModuleId, _MutableModuleState> _states =
      <ModuleId, _MutableModuleState>{};
  final Map<ModuleId, _ModuleInstance> _instances =
      <ModuleId, _ModuleInstance>{};
  final Map<ModuleId, Map<ModuleCapabilityRef, Object>> _exports =
      <ModuleId, Map<ModuleCapabilityRef, Object>>{};
  final ModuleCancellationToken _cancellation = ModuleCancellationToken();
  Future<EffectiveKitManifest>? _startup;
  _CoordinatorPhase _phase = _CoordinatorPhase.idle;
  late DateTime _generatedAt = clock();

  EffectiveKitManifest get manifest => _manifest();

  Future<EffectiveKitManifest> start() {
    if (_startup != null || _phase != _CoordinatorPhase.idle) {
      throw StateError('Module lifecycle has already started');
    }
    _phase = _CoordinatorPhase.starting;
    return _startup = _start();
  }

  Future<EffectiveKitManifest> _start() async {
    ModuleId? activeModuleId;
    try {
      for (final moduleId in plan.dependencyOrder) {
        activeModuleId = moduleId;
        _cancellation.throwIfCancelled();
        final descriptor = _descriptors[moduleId]!;
        final resources = ModuleResourceOwner();
        final context = ModuleContext._(
          moduleId: moduleId,
          settings: _settings[moduleId]!,
          capabilities: ModuleCapabilityAccess._(
            moduleId: moduleId,
            requiredCapabilities: descriptor.requires
                .map((item) => item.capability)
                .toSet(),
            optionalCapabilities: descriptor.optionalRequires
                .map((item) => item.capability)
                .toSet(),
            bindings: _globalBindings,
            exports: _exports,
          ),
          cancellation: _cancellation,
          resources: resources,
          health: ModuleHealthReporter._(moduleId, _setHealth),
        );
        late final BuiltinModule module;
        try {
          module = factories.create(moduleId, context);
        } on Object {
          await resources.releaseAll();
          rethrow;
        }
        final instance = _ModuleInstance(module: module, resources: resources);
        _instances[moduleId] = instance;
        _setState(moduleId, ModuleRuntimeState.starting, ModuleHealth.unknown);
        await instance.module.prepare();
        _cancellation.throwIfCancelled();
        instance.startInvoked = true;
        final result = await instance.module.start();
        _cancellation.throwIfCancelled();
        _validateExports(descriptor, result.capabilities);
        _validateContribution(moduleId, result.contribution);
        instance.result = result;
        _exports[moduleId] = result.capabilities;
        final degraded = _states[moduleId]!.degradedRequested;
        _setState(
          moduleId,
          degraded ? ModuleRuntimeState.degraded : ModuleRuntimeState.ready,
          degraded ? ModuleHealth.degraded : ModuleHealth.healthy,
        );
      }
      _phase = _CoordinatorPhase.ready;
      return _manifest();
    } on Object catch (error) {
      final failedId = activeModuleId ?? plan.dependencyOrder.first;
      await _failAndRollback(failedId, error);
      _phase = _CoordinatorPhase.failed;
      throw ModuleStartupException(
        moduleId: failedId,
        cause: error,
        manifest: _manifest(),
      );
    }
  }

  Future<EffectiveKitManifest> stop() async {
    _cancellation._cancel();
    final startup = _startup;
    if (_phase == _CoordinatorPhase.starting && startup != null) {
      try {
        await startup;
      } on ModuleStartupException {
        return _manifest();
      }
    }
    if (_phase == _CoordinatorPhase.failed ||
        _phase == _CoordinatorPhase.stopped) {
      return _manifest();
    }
    _phase = _CoordinatorPhase.stopping;
    for (final moduleId in plan.dependencyOrder.reversed) {
      final instance = _instances[moduleId];
      if (instance == null) continue;
      await _cleanupInstance(moduleId, instance, preserveFailure: false);
    }
    _exports.clear();
    _phase = _CoordinatorPhase.stopped;
    return _manifest();
  }

  Future<void> _failAndRollback(ModuleId failedId, Object error) async {
    final failedState = _states[failedId]!;
    failedState.diagnostics.add(
      ModuleDiagnostic(
        moduleId: failedId,
        code: error is ModuleStartupCancelled
            ? 'module.start.cancelled'
            : 'module.start.failed',
        severity: ModuleDiagnosticSeverity.error,
        message: error is ModuleStartupCancelled
            ? 'Startup cancelled'
            : 'Startup failed with ${error.runtimeType}',
      ),
    );
    _setState(failedId, ModuleRuntimeState.failed, ModuleHealth.unhealthy);
    final failedInstance = _instances[failedId];
    if (failedInstance != null) {
      await _cleanupInstance(failedId, failedInstance, preserveFailure: true);
    }
    for (final moduleId in plan.dependencyOrder.reversed) {
      if (moduleId == failedId) continue;
      final state = _states[moduleId]!;
      final instance = _instances[moduleId];
      if (instance != null &&
          (state.state == ModuleRuntimeState.ready ||
              state.state == ModuleRuntimeState.degraded)) {
        await _cleanupInstance(moduleId, instance, preserveFailure: false);
      } else if (state.state == ModuleRuntimeState.stopped) {
        state.state = ModuleRuntimeState.dependencyMissing;
        state.diagnostics.add(
          ModuleDiagnostic(
            moduleId: moduleId,
            code: 'module.start.aborted',
            severity: ModuleDiagnosticSeverity.error,
            message: 'Startup aborted after ${failedId.value} failed',
          ),
        );
      }
    }
    _exports.clear();
  }

  Future<void> _cleanupInstance(
    ModuleId moduleId,
    _ModuleInstance instance, {
    required bool preserveFailure,
  }) async {
    if (!preserveFailure) {
      _setState(moduleId, ModuleRuntimeState.stopping, ModuleHealth.unknown);
    }
    final failures = <Object>[];
    if (instance.startInvoked) {
      try {
        await instance.module.stop();
      } on Object catch (error) {
        failures.add(error);
      }
    }
    try {
      await instance.module.dispose();
    } on Object catch (error) {
      failures.add(error);
    }
    failures.addAll(await instance.resources.releaseAll());
    final state = _states[moduleId]!;
    for (final failure in failures) {
      state.diagnostics.add(
        ModuleDiagnostic(
          moduleId: moduleId,
          code: 'module.cleanup.failed',
          severity: ModuleDiagnosticSeverity.error,
          message: 'Cleanup failed with ${failure.runtimeType}',
        ),
      );
    }
    _exports.remove(moduleId);
    if (!preserveFailure) {
      _setState(
        moduleId,
        failures.isEmpty
            ? ModuleRuntimeState.stopped
            : ModuleRuntimeState.failed,
        failures.isEmpty ? ModuleHealth.notApplicable : ModuleHealth.unhealthy,
      );
    }
  }

  void _validateExports(
    ModuleDescriptor descriptor,
    Map<ModuleCapabilityRef, Object> exports,
  ) {
    final expected = descriptor.provides.toSet();
    if (exports.length != expected.length ||
        !expected.containsAll(exports.keys)) {
      throw StateError(
        '${descriptor.id.value} exports do not match its descriptor',
      );
    }
  }

  void _validateContribution(
    ModuleId moduleId,
    ModuleContribution contribution,
  ) {
    final commands = <String>{};
    final rpcMethods = <String>{};
    final studioContributions = <String>{};
    for (final instance in _instances.values) {
      final existing = instance.result?.contribution;
      if (existing == null) continue;
      commands.addAll(existing.commands);
      rpcMethods.addAll(existing.rpcMethods);
      studioContributions.addAll(existing.studioContributions);
    }
    final collisions = <String>{
      ...commands.intersection(contribution.commands.toSet()),
      ...rpcMethods.intersection(contribution.rpcMethods.toSet()),
      ...studioContributions.intersection(
        contribution.studioContributions.toSet(),
      ),
    }.toList()..sort();
    if (collisions.isNotEmpty) {
      throw StateError(
        '${moduleId.value} contribution collides on ${collisions.join(', ')}',
      );
    }
  }

  void _setHealth(
    ModuleId moduleId,
    bool degraded,
    ModuleDiagnostic? diagnostic,
  ) {
    final state = _states[moduleId]!;
    state.degradedRequested = degraded;
    if (diagnostic != null) state.diagnostics.add(diagnostic);
    if (state.state == ModuleRuntimeState.ready ||
        state.state == ModuleRuntimeState.degraded) {
      _setState(
        moduleId,
        degraded ? ModuleRuntimeState.degraded : ModuleRuntimeState.ready,
        degraded ? ModuleHealth.degraded : ModuleHealth.healthy,
      );
    }
  }

  void _setState(
    ModuleId moduleId,
    ModuleRuntimeState state,
    ModuleHealth health,
  ) {
    final current = _states[moduleId]!;
    current.state = state;
    current.health = health;
    _generatedAt = clock();
  }

  EffectiveKitManifest _manifest() {
    final commands = <String>[];
    final rpcMethods = <String>[];
    final studioContributions = <String>[];
    for (final entry in _instances.entries) {
      final state = _states[entry.key]!.state;
      if (state != ModuleRuntimeState.ready &&
          state != ModuleRuntimeState.degraded) {
        continue;
      }
      final contribution = entry.value.result?.contribution;
      if (contribution == null) continue;
      commands.addAll(contribution.commands);
      rpcMethods.addAll(contribution.rpcMethods);
      studioContributions.addAll(contribution.studioContributions);
    }
    return EffectiveKitManifest(
      resolvedPlanDigest: plan.digest,
      modules: <EffectiveModuleState>[
        for (final descriptor in catalog.modules)
          EffectiveModuleState(
            moduleId: descriptor.id,
            state: _states[descriptor.id]!.state,
            health: _states[descriptor.id]!.health,
            effectiveCapabilities:
                _states[descriptor.id]!.state == ModuleRuntimeState.ready ||
                    _states[descriptor.id]!.state == ModuleRuntimeState.degraded
                ? descriptor.provides
                : const <ModuleCapabilityRef>[],
            diagnostics: _states[descriptor.id]!.diagnostics,
          ),
      ],
      commands: commands,
      rpcMethods: rpcMethods,
      studioContributions: studioContributions,
      generatedAt: _generatedAt,
    );
  }
}

final class _ModuleInstance {
  _ModuleInstance({required this.module, required this.resources});

  final BuiltinModule module;
  final ModuleResourceOwner resources;
  bool startInvoked = false;
  ModuleStartResult? result;
}

final class _MutableModuleState {
  _MutableModuleState({required this.state, required this.health});

  ModuleRuntimeState state;
  ModuleHealth health;
  bool degradedRequested = false;
  final List<ModuleDiagnostic> diagnostics = <ModuleDiagnostic>[];
}

enum _CoordinatorPhase { idle, starting, ready, stopping, stopped, failed }

DateTime _systemModuleClock() => DateTime.now().toUtc();

List<String> _sortedUnique(List<String> values, String name) {
  if (values.any((value) => value.isEmpty) ||
      values.toSet().length != values.length) {
    throw ArgumentError(
      'Module contribution $name must be unique and non-empty',
    );
  }
  return List<String>.unmodifiable(List<String>.of(values)..sort());
}
