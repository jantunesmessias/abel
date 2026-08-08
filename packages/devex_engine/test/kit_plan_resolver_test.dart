import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:test/test.dart';

void main() {
  const resolver = KitPlanResolver();

  test(
    'expands profile, overlays settings, binds providers, and orders dependencies',
    () {
      final catalog = _catalog(
        <ModuleDescriptor>[
          _module('catalog', provides: const <String>['catalog.read']),
          _module(
            'artifact-store.local',
            provides: const <String>['artifact.store'],
          ),
          _module(
            'studio.journey-map',
            provides: const <String>['studio.journey-map'],
            requires: const <String>['catalog.read', 'evidence.visual'],
          ),
          _module(
            'evidence.auto-preview',
            provides: const <String>['evidence.visual'],
            requires: const <String>['catalog.read', 'artifact.store'],
            configurationSchema: 'urn:devex:test:auto-preview-settings:v1',
          ),
        ],
        profileModules: const <String>[
          'studio.journey-map',
          'catalog',
          'evidence.auto-preview',
          'artifact-store.local',
        ],
      );
      final plan = resolver.resolve(
        catalog: catalog,
        profileId: 'journey-preview',
        overlays: <KitSelection>[
          KitSelection(
            modules: <KitModuleSelection>[
              KitModuleSelection(
                moduleId: ModuleId('evidence.auto-preview'),
                enabled: true,
                settings: const <String, Object?>{
                  'capture': <String, Object?>{'renderer': 'flutter-test'},
                },
              ),
            ],
          ),
          KitSelection(
            modules: <KitModuleSelection>[
              KitModuleSelection(
                moduleId: ModuleId('evidence.auto-preview'),
                enabled: true,
                settings: const <String, Object?>{
                  'capture': <String, Object?>{'policy': 'static-v1'},
                },
              ),
            ],
          ),
        ],
        configurationSchemas: <String, Object?>{
          'urn:devex:test:auto-preview-settings:v1': <String, Object?>{
            r'$schema': 'https://json-schema.org/draft/2020-12/schema',
            'type': 'object',
            'additionalProperties': false,
            'required': <String>['capture'],
            'properties': <String, Object?>{
              'capture': <String, Object?>{
                'type': 'object',
                'additionalProperties': false,
                'required': <String>['renderer', 'policy'],
                'properties': <String, Object?>{
                  'renderer': <String, Object?>{'const': 'flutter-test'},
                  'policy': <String, Object?>{'const': 'static-v1'},
                },
              },
            },
          },
        },
      );

      expect(plan.profileId, 'journey-preview');
      expect(plan.dependencyOrder.map((id) => id.value), <String>[
        'artifact-store.local',
        'catalog',
        'evidence.auto-preview',
        'studio.journey-map',
      ]);
      expect(
        plan.enabledModules
            .singleWhere(
              (item) => item.moduleId.value == 'evidence.auto-preview',
            )
            .settings,
        <String, Object?>{
          'capture': <String, Object?>{
            'policy': 'static-v1',
            'renderer': 'flutter-test',
          },
        },
      );
      expect(
        plan.providerBindings
            .singleWhere((item) => item.capability.id == 'evidence.visual')
            .providerModuleIds
            .single
            .value,
        'evidence.auto-preview',
      );
      expect(ResolvedKitPlan.fromJson(plan.toJson()).digest, plan.digest);
    },
  );

  test('does not auto-enable a required provider', () {
    final catalog = _catalog(
      <ModuleDescriptor>[
        _module('catalog', provides: const <String>['catalog.read']),
        _module(
          'consumer',
          provides: const <String>['consumer.read'],
          requires: const <String>['catalog.read'],
        ),
      ],
      profileModules: const <String>['consumer'],
    );

    expect(
      () => resolver.resolve(catalog: catalog, profileId: 'journey-preview'),
      throwsA(
        isA<KitPlanResolutionException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          contains('consumer requires missing capability catalog.read@1'),
        ),
      ),
    );
  });

  test('rejects ambiguous providers without an explicit binding', () {
    final catalog = _catalog(
      <ModuleDescriptor>[
        _module('provider-a', provides: const <String>['visual.read']),
        _module('provider-b', provides: const <String>['visual.read']),
        _module(
          'consumer',
          provides: const <String>['consumer.read'],
          requires: const <String>['visual.read'],
        ),
      ],
      profileModules: const <String>['provider-a', 'provider-b', 'consumer'],
    );

    expect(
      () => resolver.resolve(catalog: catalog, profileId: 'journey-preview'),
      throwsA(
        isA<KitPlanResolutionException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          contains('requires an explicit provider binding for visual.read@1'),
        ),
      ),
    );
  });

  test('rejects dependency cycles, conflicts, and unsupported platform', () {
    final cycle = _catalog(
      <ModuleDescriptor>[
        _module(
          'module-a',
          provides: const <String>['a.read'],
          requires: const <String>['b.read'],
        ),
        _module(
          'module-b',
          provides: const <String>['b.read'],
          requires: const <String>['a.read'],
        ),
      ],
      profileModules: const <String>['module-a', 'module-b'],
    );
    expect(
      () => resolver.resolve(catalog: cycle, profileId: 'journey-preview'),
      throwsA(
        isA<KitPlanResolutionException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          contains('dependency cycle'),
        ),
      ),
    );

    final incompatible = _catalog(
      <ModuleDescriptor>[
        _module(
          'module-a',
          provides: const <String>['a.read'],
          conflicts: const <String>['module-b'],
        ),
        _module('module-b', provides: const <String>['b.read']),
        _module(
          'mac-only',
          provides: const <String>['mac.read'],
          platforms: const <String>{'macos-arm64'},
        ),
      ],
      profileModules: const <String>['module-a', 'module-b', 'mac-only'],
    );
    expect(
      () =>
          resolver.resolve(catalog: incompatible, profileId: 'journey-preview'),
      throwsA(
        isA<KitPlanResolutionException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          allOf(
            contains('conflicts with module-b'),
            contains('does not support linux-x64'),
          ),
        ),
      ),
    );
  });

  test('rejects settings without a registered closed schema', () {
    final catalog = _catalog(
      <ModuleDescriptor>[
        _module(
          'configured',
          provides: const <String>['configured.read'],
          configurationSchema: 'urn:devex:test:configured:v1',
        ),
      ],
      profileModules: const <String>['configured'],
      profileSettings: const <String, Object?>{
        'configured': <String, Object?>{'unknown': true},
      },
    );
    expect(
      () => resolver.resolve(catalog: catalog, profileId: 'journey-preview'),
      throwsA(
        isA<KitPlanResolutionException>().having(
          (error) => error.issues.join('\n'),
          'issues',
          contains('has no registered configuration schema'),
        ),
      ),
    );
  });
}

ModuleDescriptor _module(
  String id, {
  required List<String> provides,
  List<String> requires = const <String>[],
  List<String> optionalRequires = const <String>[],
  List<String> conflicts = const <String>[],
  Set<String> platforms = const <String>{'linux-x64'},
  String? configurationSchema,
}) => ModuleDescriptor(
  id: ModuleId(id),
  version: '1.0.0',
  coreCompatibility: '^0.1.0',
  provides: <ModuleCapabilityRef>[
    for (final capability in provides)
      ModuleCapabilityRef(id: capability, version: 1),
  ],
  requires: <ModuleRequirement>[
    for (final capability in requires)
      ModuleRequirement(
        capability: ModuleCapabilityRef(id: capability, version: 1),
      ),
  ],
  optionalRequires: <ModuleRequirement>[
    for (final capability in optionalRequires)
      ModuleRequirement(
        capability: ModuleCapabilityRef(id: capability, version: 1),
      ),
  ],
  conflicts: <ModuleId>[for (final conflict in conflicts) ModuleId(conflict)],
  supportedPlatforms: platforms,
  configurationSchema: configurationSchema,
);

ModuleCatalog _catalog(
  List<ModuleDescriptor> modules, {
  required List<String> profileModules,
  Map<String, Object?> profileSettings = const <String, Object?>{},
}) => ModuleCatalog(
  distributionId: 'devex-kit',
  coreVersion: '0.1.0',
  platform: 'linux-x64',
  modules: modules,
  profiles: <KitProfile>[
    KitProfile(
      id: 'journey-preview',
      displayName: 'Journey Preview',
      selection: KitSelection(
        modules: <KitModuleSelection>[
          for (final id in profileModules)
            KitModuleSelection(
              moduleId: ModuleId(id),
              enabled: true,
              settings:
                  profileSettings[id] as Map<String, Object?>? ??
                  const <String, Object?>{},
            ),
        ],
      ),
    ),
  ],
  defaultProfileId: 'journey-preview',
);
