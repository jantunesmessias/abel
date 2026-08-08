import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  const builtins = BuiltinModuleCatalog();

  test(
    'packages the canonical inventory and all required profiles resolve',
    () {
      final catalog = builtins.create(platform: 'linux-x64');

      expect(catalog.modules, hasLength(17));
      expect(catalog.profiles.map((profile) => profile.id), <String>[
        'full-local',
        'gateway-lab',
        'gateway-lab-headless',
        'journey-android',
        'journey-preview',
        'legacy-full-local-v1',
      ]);
      for (final profile in catalog.profiles) {
        final plan = const KitPlanResolver().resolve(
          catalog: catalog,
          profileId: profile.id,
          configurationSchemas: builtins.configurationSchemas,
        );
        expect(plan.profileId, profile.id);
        expect(plan.dependencyOrder, hasLength(plan.enabledModules.length));
        expect(ResolvedKitPlan.fromJson(plan.toJson()).digest, plan.digest);
      }
    },
  );

  test('minimal profiles do not imply Android or Gateway', () {
    final catalog = builtins.create(platform: 'linux-x64');
    final preview = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'journey-preview',
      configurationSchemas: builtins.configurationSchemas,
    );
    final android = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'journey-android',
      configurationSchemas: builtins.configurationSchemas,
    );
    final gateway = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'gateway-lab',
      configurationSchemas: builtins.configurationSchemas,
    );

    expect(_moduleIds(preview), <String>[
      'artifact-store.local',
      'catalog',
      'evidence.auto-preview',
      'studio.journey-map',
      'studio.shell',
    ]);
    expect(_moduleIds(preview), isNot(contains('target.android')));
    expect(_moduleIds(preview), isNot(contains('gateway.interceptor')));
    expect(
      preview.providerBindings
          .singleWhere((binding) => binding.capability.id == 'evidence.visual')
          .providerModuleIds
          .single
          .value,
      'evidence.auto-preview',
    );

    expect(
      _moduleIds(android),
      containsAll(<String>['target.android', 'evidence.android']),
    );
    expect(_moduleIds(android), isNot(contains('evidence.auto-preview')));
    expect(_moduleIds(android), isNot(contains('gateway.interceptor')));

    expect(_moduleIds(gateway), contains('gateway.interceptor'));
    expect(_moduleIds(gateway), isNot(contains('target.android')));
    expect(_moduleIds(gateway), isNot(contains('evidence.auto-preview')));
  });

  test('legacy v1 translation reaches the same full modular runtime', () {
    final catalog = builtins.create(platform: 'linux-x64');
    final legacy = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: const LegacyV1ConfigurationTranslator().profileId,
      configurationSchemas: builtins.configurationSchemas,
    );
    final full = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'full-local',
      configurationSchemas: builtins.configurationSchemas,
    );

    expect(_moduleIds(legacy), _moduleIds(full));
    expect(
      legacy.providerBindings.map((binding) => binding.toJson()),
      full.providerBindings.map((binding) => binding.toJson()),
    );
    expect(
      legacy.enabledModules.map((module) => module.settings),
      full.enabledModules.map((module) => module.settings),
    );
  });

  test('resolves the required Studio reconstruction provider matrix', () {
    final catalog = builtins.create(platform: 'linux-x64');
    final resolver = const KitPlanResolver();

    final withoutEvidence = resolver.resolve(
      catalog: catalog,
      profileId: 'gateway-lab',
      overlays: <KitSelection>[
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(
              moduleId: ModuleId('artifact-store.local'),
              enabled: false,
            ),
            KitModuleSelection(
              moduleId: ModuleId('sessions.local'),
              enabled: false,
            ),
            KitModuleSelection(
              moduleId: ModuleId('gateway.interceptor'),
              enabled: false,
            ),
            KitModuleSelection(
              moduleId: ModuleId('studio.journey-map'),
              enabled: true,
            ),
          ],
        ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );
    expect(_moduleIds(withoutEvidence), <String>[
      'catalog',
      'studio.journey-map',
      'studio.shell',
    ]);
    expect(
      withoutEvidence.providerBindings,
      isNot(
        contains(
          predicate<ProviderBinding>(
            (binding) => binding.capability.id == 'evidence.visual',
          ),
        ),
      ),
    );

    final autoAndAndroid = resolver.resolve(
      catalog: catalog,
      profileId: 'journey-preview',
      overlays: <KitSelection>[
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(
              moduleId: ModuleId('target.android'),
              enabled: true,
            ),
            KitModuleSelection(
              moduleId: ModuleId('evidence.android'),
              enabled: true,
            ),
          ],
          providerBindings: <ProviderBinding>[
            _visualBinding(<String>[
              'evidence.auto-preview',
              'evidence.android',
            ]),
          ],
        ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );
    expect(_visualProviders(autoAndAndroid), <String>[
      'evidence.auto-preview',
      'evidence.android',
    ]);

    final adapterAndAuto = resolver.resolve(
      catalog: catalog,
      profileId: 'journey-preview',
      overlays: <KitSelection>[
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(
              moduleId: ModuleId('sessions.local'),
              enabled: true,
            ),
            KitModuleSelection(
              moduleId: ModuleId('capture.app-adapter'),
              enabled: true,
            ),
          ],
          providerBindings: <ProviderBinding>[
            _visualBinding(<String>[
              'capture.app-adapter',
              'evidence.auto-preview',
            ]),
          ],
        ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );
    expect(_visualProviders(adapterAndAuto), <String>[
      'capture.app-adapter',
      'evidence.auto-preview',
    ]);
  });

  test('catalog and configuration schema maps are canonical and immutable', () {
    final first = builtins.create(platform: 'linux-x64');
    final second = builtins.create(platform: 'linux-x64');

    expect(first.digest, second.digest);
    expect(
      () => builtins.configurationSchemas['unexpected'] = <String, Object?>{},
      throwsUnsupportedError,
    );
  });
}

List<String> _moduleIds(ResolvedKitPlan plan) =>
    plan.enabledModules.map((module) => module.moduleId.value).toList();

ProviderBinding _visualBinding(List<String> providers) => ProviderBinding(
  capability: ModuleCapabilityRef(id: 'evidence.visual', version: 1),
  providerModuleIds: providers.map(ModuleId.new).toList(growable: false),
  selectionPolicy: ProviderSelectionPolicy.orderedFirstAvailable,
);

List<String> _visualProviders(ResolvedKitPlan plan) => plan.providerBindings
    .singleWhere((binding) => binding.capability.id == 'evidence.visual')
    .providerModuleIds
    .map((item) => item.value)
    .toList(growable: false);
