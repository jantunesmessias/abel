import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const builtins = BuiltinModuleCatalog();

  test(
    'packages the canonical inventory and all required profiles resolve',
    () {
      final catalog = builtins.create(platform: 'linux-x64');

      expect(catalog.modules, hasLength(28));
      expect(catalog.profiles.map((profile) => profile.id), <String>[
        'full-local',
        'gateway-lab',
        'gateway-lab-headless',
        'journey-android',
        'journey-preview',
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
      'studio.inventory',
      'studio.journey-map',
      'studio.lab',
      'studio.quality',
      'studio.shell',
    ]);
    expect(_moduleIds(preview), isNot(contains('target.android')));
    expect(_moduleIds(preview), isNot(contains('gateway.interceptor')));
    final inventory = catalog.modules.singleWhere(
      (module) => module.id.value == 'studio.inventory',
    );
    expect(inventory.provides.map((item) => item.id), <String>[
      'studio.inventory',
    ]);
    expect(inventory.effects, <ModuleEffect>{ModuleEffect.query});
    expect(inventory.surfaces, <ModuleSurface>{ModuleSurface.studio});
    expect(inventory.requires.map((item) => item.capability.id), <String>[
      'catalog.read',
    ]);
    expect(
      inventory.optionalRequires.map((item) => item.capability.id),
      <String>['evidence.visual'],
    );
    final lab = catalog.modules.singleWhere(
      (module) => module.id.value == 'studio.lab',
    );
    expect(lab.effects, <ModuleEffect>{ModuleEffect.query});
    expect(lab.requires.map((item) => item.capability.id), <String>[
      'catalog.read',
    ]);
    expect(lab.optionalRequires.map((item) => item.capability.id), <String>[
      'evidence.visual',
      'scenario.lab.execute',
    ]);
    final labRuntime = catalog.modules.singleWhere(
      (module) => module.id.value == 'scenario.lab.local',
    );
    expect(labRuntime.provides.map((item) => item.id), <String>[
      'scenario.lab.execute',
    ]);
    expect(labRuntime.effects, <ModuleEffect>{ModuleEffect.ephemeral});
    expect(_moduleIds(preview), isNot(contains('scenario.lab.local')));
    final quality = catalog.modules.singleWhere(
      (module) => module.id.value == 'studio.quality',
    );
    expect(quality.effects, <ModuleEffect>{ModuleEffect.query});
    expect(quality.optionalRequires.map((item) => item.capability.id), <String>[
      'evidence.visual',
    ]);
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

  test(
    'quality decision authority settings are closed and fail before Host composition',
    () {
      final schema = Draft202012Validator(
        builtins.configurationSchemas[BuiltinModuleCatalog
            .scenarioQualityDecisionSettingsSchema]!,
      );
      final reviewer = <String, Object?>{
        'authorityId': 'local-authority',
        'accessPolicyId': 'local-policy',
        'principalId': 'reviewer-1',
        'role': 'reviewer',
        'allowedRequirementIds': <Object?>['approval'],
        'allowedDecisions': <Object?>['approved', 'rejected'],
        'artifactClassifications': <Object?>['internal'],
        'grantTtlSeconds': 1.0,
      };
      expect(schema.validate(reviewer).isValid, isTrue);
      expect(
        HostScenarioQualityDecisionAuthority.fromSettings(reviewer)?.grantTtl,
        const Duration(seconds: 1),
      );
      expect(schema.validate(const <String, Object?>{}).isValid, isTrue);
      expect(
        HostScenarioQualityDecisionAuthority.fromSettings(
          const <String, Object?>{},
        ),
        isNull,
      );

      final observerMutation = <String, Object?>{
        ...reviewer,
        'role': 'observer',
      };
      expect(schema.validate(observerMutation).isValid, isFalse);
      expect(
        () =>
            HostScenarioQualityDecisionAuthority.fromSettings(observerMutation),
        throwsArgumentError,
      );
      expect(
        schema.validate(<String, Object?>{
          ...reviewer,
          'authorityId': 'a${'b' * 256}',
        }).isValid,
        isFalse,
      );
    },
  );

  test('Experience Authoring modules and authority settings are closed', () {
    final catalog = builtins.create(platform: 'linux-x64');
    final runtime = catalog.modules.singleWhere(
      (module) => module.id.value == 'authoring.local',
    );
    final studio = catalog.modules.singleWhere(
      (module) => module.id.value == 'studio.authoring',
    );
    expect(runtime.provides.map((item) => item.id), <String>[
      'experience.authoring',
    ]);
    expect(runtime.effects, <ModuleEffect>{
      ModuleEffect.authoring,
      ModuleEffect.decision,
    });
    expect(runtime.resourceRequirements, <ModuleResource>{
      ModuleResource.filesystemRead,
      ModuleResource.filesystemWrite,
    });
    expect(studio.effects, <ModuleEffect>{ModuleEffect.query});
    expect(studio.optionalRequires.map((item) => item.capability.id), <String>[
      'experience.authoring',
    ]);

    final schema = Draft202012Validator(
      builtins.configurationSchemas[BuiltinModuleCatalog
          .experienceAuthoringSettingsSchema]!,
    );
    expect(schema.validate(const <String, Object?>{}).isValid, isTrue);
    final author = <String, Object?>{
      'authorityId': 'local-authority',
      'accessPolicyId': 'local-policy',
      'principalId': 'local-author',
      'allowedOperations': <Object?>[
        'openDraft',
        'moveNode',
        'prepareReview',
        'decideReview',
        'promote',
      ],
      'grantTtlSeconds': 120,
    };
    expect(schema.validate(author).isValid, isTrue);
    expect(
      ExperienceAuthoringAuthoritySettings.fromJson(author).principalId,
      AuthoringPrincipalId('local-author'),
    );
    expect(
      schema.validate(<String, Object?>{
        ...author,
        'allowedOperations': <Object?>['getDraft'],
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate(<String, Object?>{
        ...author,
        'contentRoot': '/tmp/forbidden',
      }).isValid,
      isFalse,
    );
  });

  test('Motion and Context Builder remain explicit read-only capabilities', () {
    final catalog = builtins.create(platform: 'linux-x64');
    final full = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'full-local',
      configurationSchemas: builtins.configurationSchemas,
    );
    expect(
      _moduleIds(full),
      containsAll(<String>[
        'studio.motion',
        'motion.local',
        'studio.context',
        'context.builder.local',
      ]),
    );

    final motion = catalog.modules.singleWhere(
      (module) => module.id.value == 'motion.local',
    );
    expect(motion.provides.map((item) => item.id), <String>[
      'experience.motion',
    ]);
    expect(motion.effects, <ModuleEffect>{ModuleEffect.query});
    expect(motion.resourceRequirements, <ModuleResource>{
      ModuleResource.filesystemRead,
    });

    final context = catalog.modules.singleWhere(
      (module) => module.id.value == 'context.builder.local',
    );
    expect(context.provides.map((item) => item.id), <String>['context.build']);
    expect(context.effects, <ModuleEffect>{ModuleEffect.query});
    expect(context.resourceRequirements, <ModuleResource>{
      ModuleResource.filesystemRead,
    });
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
            KitModuleSelection(
              moduleId: ModuleId('studio.inventory'),
              enabled: false,
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

  test('Scenario Lab Evidence classification is consumer-owned and closed', () {
    final catalog = builtins.create(platform: 'linux-x64');
    final resolver = const KitPlanResolver();
    final configured = resolver.resolve(
      catalog: catalog,
      profileId: 'full-local',
      overlays: <KitSelection>[
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(
              moduleId: ModuleId('scenario.lab.local'),
              enabled: true,
              settings: const <String, Object?>{
                'evidenceClassification': 'internal',
              },
            ),
          ],
        ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );
    expect(
      configured.enabledModules
          .singleWhere(
            (module) => module.moduleId.value == 'scenario.lab.local',
          )
          .settings,
      const <String, Object?>{'evidenceClassification': 'internal'},
    );

    expect(
      () => resolver.resolve(
        catalog: catalog,
        profileId: 'full-local',
        overlays: <KitSelection>[
          KitSelection(
            modules: <KitModuleSelection>[
              KitModuleSelection(
                moduleId: ModuleId('scenario.lab.local'),
                enabled: true,
                settings: const <String, Object?>{
                  'evidenceClassification': 'secret',
                },
              ),
            ],
          ),
        ],
        configurationSchemas: builtins.configurationSchemas,
      ),
      throwsA(isA<KitPlanResolutionException>()),
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
