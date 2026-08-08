import 'dart:async';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  final observedAt = DateTime.utc(2026, 8, 10, 12);

  test(
    'starts in dependency order and disabled modules have zero surface',
    () async {
      final log = <String>[];
      var disabledFactoryCalls = 0;
      late ModuleContext consumerContext;
      final catalog = _catalog(
        modules: <ModuleDescriptor>[
          _module('kernel', provides: const <String>['kernel.clock']),
          _module(
            'consumer',
            provides: const <String>['consumer.read'],
            requires: const <String>['kernel.clock'],
          ),
          _module('disabled', provides: const <String>['disabled.read']),
        ],
        enabled: const <String>['kernel', 'consumer'],
      );
      final plan = const KitPlanResolver().resolve(catalog: catalog);
      final coordinator = ModuleLifecycleCoordinator(
        catalog: catalog,
        plan: plan,
        clock: () => observedAt,
        factories: ModuleFactoryRegistry(<ModuleId, BuiltinModuleFactory>{
          ModuleId('kernel'): (context) => _TestModule(
            id: 'kernel',
            context: context,
            log: log,
            capabilities: <ModuleCapabilityRef, Object>{
              _capability('kernel.clock'): 'synthetic-clock',
            },
            contribution: ModuleContribution(
              commands: const <String>['kernel status'],
              rpcMethods: const <String>['workspace.kernel.status'],
            ),
          ),
          ModuleId('consumer'): (context) {
            consumerContext = context;
            return _TestModule(
              id: 'consumer',
              context: context,
              log: log,
              capabilities: <ModuleCapabilityRef, Object>{
                _capability('consumer.read'): Object(),
              },
              contribution: ModuleContribution(
                commands: const <String>['consumer read'],
                studioContributions: const <String>['consumer.panel'],
              ),
              beforeStart: () {
                expect(
                  context.capabilities.require<String>(
                    _capability('kernel.clock'),
                  ),
                  'synthetic-clock',
                );
              },
            );
          },
          ModuleId('disabled'): (context) {
            disabledFactoryCalls += 1;
            return _TestModule(
              id: 'disabled',
              context: context,
              log: log,
              capabilities: <ModuleCapabilityRef, Object>{
                _capability('disabled.read'): Object(),
              },
            );
          },
        }),
      );

      final manifest = await coordinator.start();

      expect(log, <String>[
        'kernel.create',
        'kernel.prepare',
        'kernel.start',
        'consumer.create',
        'consumer.prepare',
        'consumer.start',
      ]);
      expect(disabledFactoryCalls, 0);
      expect(consumerContext.settings, isEmpty);
      expect(manifest.resolvedPlanDigest, plan.digest);
      expect(manifest.generatedAt, observedAt);
      expect(manifest.commands, <String>['consumer read', 'kernel status']);
      expect(manifest.rpcMethods, <String>['workspace.kernel.status']);
      expect(manifest.studioContributions, <String>['consumer.panel']);
      expect(_state(manifest, 'disabled').state, ModuleRuntimeState.disabled);
      expect(_state(manifest, 'consumer').state, ModuleRuntimeState.ready);

      final stopped = await coordinator.stop();

      expect(log.skip(6), <String>[
        'consumer.stop',
        'consumer.dispose',
        'consumer.resource',
        'kernel.stop',
        'kernel.dispose',
        'kernel.resource',
      ]);
      expect(stopped.commands, isEmpty);
      expect(_state(stopped, 'consumer').state, ModuleRuntimeState.stopped);
    },
  );

  test(
    'startup failure rolls back in reverse and leaves no orphan resource',
    () async {
      final log = <String>[];
      var neverCreated = 0;
      final catalog = _catalog(
        modules: <ModuleDescriptor>[
          _module('module-a', provides: const <String>['a.read']),
          _module(
            'module-b',
            provides: const <String>['b.read'],
            requires: const <String>['a.read'],
          ),
          _module(
            'module-c',
            provides: const <String>['c.read'],
            requires: const <String>['b.read'],
          ),
        ],
        enabled: const <String>['module-a', 'module-b', 'module-c'],
      );
      final plan = const KitPlanResolver().resolve(catalog: catalog);
      final coordinator = ModuleLifecycleCoordinator(
        catalog: catalog,
        plan: plan,
        clock: () => observedAt,
        factories: ModuleFactoryRegistry(<ModuleId, BuiltinModuleFactory>{
          ModuleId('module-a'): (context) => _TestModule(
            id: 'module-a',
            context: context,
            log: log,
            capabilities: <ModuleCapabilityRef, Object>{
              _capability('a.read'): Object(),
            },
          ),
          ModuleId('module-b'): (context) => _TestModule(
            id: 'module-b',
            context: context,
            log: log,
            capabilities: <ModuleCapabilityRef, Object>{
              _capability('b.read'): Object(),
            },
            startError: Exception('injected'),
          ),
          ModuleId('module-c'): (context) {
            neverCreated += 1;
            return _TestModule(
              id: 'module-c',
              context: context,
              log: log,
              capabilities: <ModuleCapabilityRef, Object>{
                _capability('c.read'): Object(),
              },
            );
          },
        }),
      );

      late ModuleStartupException failure;
      try {
        await coordinator.start();
        fail('startup should fail');
      } on ModuleStartupException catch (error) {
        failure = error;
      }

      expect(failure.moduleId.value, 'module-b');
      expect(neverCreated, 0);
      expect(log, <String>[
        'module-a.create',
        'module-a.prepare',
        'module-a.start',
        'module-b.create',
        'module-b.prepare',
        'module-b.start',
        'module-b.stop',
        'module-b.dispose',
        'module-b.resource',
        'module-a.stop',
        'module-a.dispose',
        'module-a.resource',
      ]);
      expect(
        _state(failure.manifest, 'module-a').state,
        ModuleRuntimeState.stopped,
      );
      expect(
        _state(failure.manifest, 'module-b').state,
        ModuleRuntimeState.failed,
      );
      expect(
        _state(failure.manifest, 'module-c').state,
        ModuleRuntimeState.dependencyMissing,
      );
      expect(failure.manifest.commands, isEmpty);
    },
  );

  test(
    'shutdown during startup cancels and cleans the active module',
    () async {
      final log = <String>[];
      final enteredStart = Completer<void>();
      final catalog = _catalog(
        modules: <ModuleDescriptor>[
          _module('blocking', provides: const <String>['blocking.read']),
        ],
        enabled: const <String>['blocking'],
      );
      final plan = const KitPlanResolver().resolve(catalog: catalog);
      final coordinator = ModuleLifecycleCoordinator(
        catalog: catalog,
        plan: plan,
        clock: () => observedAt,
        factories: ModuleFactoryRegistry(<ModuleId, BuiltinModuleFactory>{
          ModuleId('blocking'): (context) => _BlockingModule(
            context: context,
            log: log,
            enteredStart: enteredStart,
          ),
        }),
      );

      final startup = coordinator.start();
      await enteredStart.future;
      final stopped = coordinator.stop();

      await expectLater(startup, throwsA(isA<ModuleStartupException>()));
      final manifest = await stopped;
      expect(log, <String>[
        'blocking.prepare',
        'blocking.start',
        'blocking.stop',
        'blocking.dispose',
        'blocking.resource',
      ]);
      expect(_state(manifest, 'blocking').state, ModuleRuntimeState.failed);
    },
  );

  test('health can move a ready module between healthy and degraded', () async {
    late ModuleContext context;
    final catalog = _catalog(
      modules: <ModuleDescriptor>[
        _module('health', provides: const <String>['health.read']),
      ],
      enabled: const <String>['health'],
    );
    final plan = const KitPlanResolver().resolve(catalog: catalog);
    final coordinator = ModuleLifecycleCoordinator(
      catalog: catalog,
      plan: plan,
      clock: () => observedAt,
      factories: ModuleFactoryRegistry(<ModuleId, BuiltinModuleFactory>{
        ModuleId('health'): (value) {
          context = value;
          return _TestModule(
            id: 'health',
            context: value,
            log: <String>[],
            capabilities: <ModuleCapabilityRef, Object>{
              _capability('health.read'): Object(),
            },
            beforeStart: () => value.health.degraded(
              code: 'health.synthetic.degraded',
              message: 'Synthetic dependency is slow',
            ),
          );
        },
      }),
    );

    final degraded = await coordinator.start();
    expect(_state(degraded, 'health').state, ModuleRuntimeState.degraded);
    expect(_state(degraded, 'health').health, ModuleHealth.degraded);

    context.health.healthy();
    expect(
      _state(coordinator.manifest, 'health').state,
      ModuleRuntimeState.ready,
    );
    expect(_state(coordinator.manifest, 'health').health, ModuleHealth.healthy);
    await coordinator.stop();
  });
}

final class _TestModule implements BuiltinModule {
  _TestModule({
    required this.id,
    required this.context,
    required this.log,
    required this.capabilities,
    this.contribution,
    this.beforeStart,
    this.startError,
  }) {
    log.add('$id.create');
    context.resources.own(() => log.add('$id.resource'));
  }

  final String id;
  final ModuleContext context;
  final List<String> log;
  final Map<ModuleCapabilityRef, Object> capabilities;
  final ModuleContribution? contribution;
  final void Function()? beforeStart;
  final Exception? startError;

  @override
  void prepare() => log.add('$id.prepare');

  @override
  ModuleStartResult start() {
    log.add('$id.start');
    beforeStart?.call();
    if (startError case final Exception error) throw error;
    return ModuleStartResult(
      capabilities: capabilities,
      contribution: contribution,
    );
  }

  @override
  void stop() => log.add('$id.stop');

  @override
  void dispose() => log.add('$id.dispose');
}

final class _BlockingModule implements BuiltinModule {
  _BlockingModule({
    required this.context,
    required this.log,
    required this.enteredStart,
  }) {
    context.resources.own(() => log.add('blocking.resource'));
  }

  final ModuleContext context;
  final List<String> log;
  final Completer<void> enteredStart;

  @override
  void prepare() => log.add('blocking.prepare');

  @override
  Future<ModuleStartResult> start() async {
    log.add('blocking.start');
    enteredStart.complete();
    await context.cancellation.whenCancelled;
    context.cancellation.throwIfCancelled();
    throw StateError('unreachable');
  }

  @override
  void stop() => log.add('blocking.stop');

  @override
  void dispose() => log.add('blocking.dispose');
}

ModuleDescriptor _module(
  String id, {
  required List<String> provides,
  List<String> requires = const <String>[],
}) => ModuleDescriptor(
  id: ModuleId(id),
  version: '1.0.0',
  coreCompatibility: '^0.1.0',
  provides: <ModuleCapabilityRef>[
    for (final capability in provides) _capability(capability),
  ],
  requires: <ModuleRequirement>[
    for (final capability in requires)
      ModuleRequirement(capability: _capability(capability)),
  ],
  supportedPlatforms: const <String>{'any'},
);

ModuleCapabilityRef _capability(String id) =>
    ModuleCapabilityRef(id: id, version: 1);

ModuleCatalog _catalog({
  required List<ModuleDescriptor> modules,
  required List<String> enabled,
}) => ModuleCatalog(
  distributionId: 'full-local',
  coreVersion: '0.1.0',
  platform: 'linux-x64',
  modules: modules,
  profiles: <KitProfile>[
    KitProfile(
      id: 'test',
      displayName: 'Test',
      selection: KitSelection(
        modules: <KitModuleSelection>[
          for (final id in enabled)
            KitModuleSelection(moduleId: ModuleId(id), enabled: true),
        ],
      ),
    ),
  ],
  defaultProfileId: 'test',
);

EffectiveModuleState _state(EffectiveKitManifest manifest, String moduleId) =>
    manifest.modules.singleWhere((item) => item.moduleId.value == moduleId);
