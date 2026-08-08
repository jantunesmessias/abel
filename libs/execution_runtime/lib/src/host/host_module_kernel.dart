import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';

import '../composition/module_lifecycle.dart';

final class HostModuleKernel {
  HostModuleKernel({
    required ModuleCatalog catalog,
    required ResolvedKitPlan plan,
    required Map<ModuleId, ModuleContribution> contributions,
  }) : _coordinator = ModuleLifecycleCoordinator(
         catalog: catalog,
         plan: plan,
         factories: ModuleFactoryRegistry(<ModuleId, BuiltinModuleFactory>{
           for (final descriptor in catalog.modules)
             if (plan.enabledModules.any(
               (module) => module.moduleId == descriptor.id,
             ))
               descriptor.id: (context) => _HostBuiltinModule(
                 descriptor: descriptor,
                 contribution:
                     contributions[descriptor.id] ?? ModuleContribution.none,
               ),
         }),
       );

  final ModuleLifecycleCoordinator _coordinator;

  EffectiveKitManifest get manifest => _coordinator.manifest;

  Future<EffectiveKitManifest> start() => _coordinator.start();

  Future<EffectiveKitManifest> stop() => _coordinator.stop();
}

final class _HostBuiltinModule implements BuiltinModule {
  _HostBuiltinModule({required this.descriptor, required this.contribution});

  final ModuleDescriptor descriptor;
  final ModuleContribution contribution;

  @override
  FutureOr<void> prepare() {}

  @override
  ModuleStartResult start() => ModuleStartResult(
    capabilities: <ModuleCapabilityRef, Object>{
      for (final capability in descriptor.provides)
        capability: _HostCapabilityToken(descriptor.id, capability),
    },
    contribution: contribution,
  );

  @override
  FutureOr<void> stop() {}

  @override
  FutureOr<void> dispose() {}
}

final class _HostCapabilityToken {
  const _HostCapabilityToken(this.moduleId, this.capability);

  final ModuleId moduleId;
  final ModuleCapabilityRef capability;
}
