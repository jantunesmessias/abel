import 'package:experience_contracts/experience_contracts.dart';

/// The statically packaged inventory. Consumer configuration can select these
/// modules, but cannot add factories or load Dart code.
final class BuiltinModuleCatalog {
  const BuiltinModuleCatalog();

  static const String autoPreviewSettingsSchema =
      'https://github.com/jantunesmessias/abel/schemas/configuration/auto-preview-settings';
  static const String scenarioLabSettingsSchema =
      'https://github.com/jantunesmessias/abel/schemas/configuration/scenario-lab-settings';
  static const String scenarioQualityDecisionSettingsSchema =
      'https://github.com/jantunesmessias/abel/schemas/configuration/scenario-quality-decision-settings';
  static const String experienceAuthoringSettingsSchema =
      'https://github.com/jantunesmessias/abel/schemas/configuration/experience-authoring-settings';

  ModuleCatalog create({
    required String platform,
    String distributionId = 'full-local',
    String coreVersion = '0.1.0',
  }) => ModuleCatalog(
    distributionId: distributionId,
    coreVersion: coreVersion,
    platform: platform,
    modules: _modules(),
    profiles: _profiles(),
    defaultProfileId: 'full-local',
  );

  Map<String, Object?> get configurationSchemas =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        autoPreviewSettingsSchema: const <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$id': autoPreviewSettingsSchema,
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['renderer', 'capturePolicy'],
          'properties': <String, Object?>{
            'renderer': <String, Object?>{
              'enum': <String>['flutter-test'],
            },
            'capturePolicy': <String, Object?>{
              'type': 'string',
              'pattern': r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
            },
            'parallelism': <String, Object?>{
              'type': 'integer',
              'minimum': 1,

              'maximum': 1,
            },
          },
        },
        scenarioLabSettingsSchema: const <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$id': scenarioLabSettingsSchema,
          'type': 'object',
          'additionalProperties': false,
          'properties': <String, Object?>{
            'evidenceClassification': <String, Object?>{
              'enum': <String>['public', 'internal', 'sensitive'],
            },
          },
        },
        scenarioQualityDecisionSettingsSchema: const <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$id': scenarioQualityDecisionSettingsSchema,
          'type': 'object',
          'additionalProperties': false,
          'properties': <String, Object?>{
            'authorityId': <String, Object?>{r'$ref': r'#/$defs/id'},
            'accessPolicyId': <String, Object?>{r'$ref': r'#/$defs/id'},
            'principalId': <String, Object?>{r'$ref': r'#/$defs/id'},
            'role': <String, Object?>{
              'enum': <String>['reviewer', 'observer'],
            },
            'allowedRequirementIds': <String, Object?>{
              'type': 'array',
              'maxItems': 1000,
              'uniqueItems': true,
              'items': <String, Object?>{r'$ref': r'#/$defs/id'},
            },
            'allowedDecisions': <String, Object?>{
              'type': 'array',
              'maxItems': 2,
              'uniqueItems': true,
              'items': <String, Object?>{
                'enum': <String>['approved', 'rejected'],
              },
            },
            'artifactClassifications': <String, Object?>{
              'type': 'array',
              'maxItems': 2,
              'uniqueItems': true,
              'items': <String, Object?>{
                'enum': <String>['public', 'internal'],
              },
            },
            'grantTtlSeconds': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 300,
            },
          },
          r'$defs': <String, Object?>{
            'id': <String, Object?>{
              'type': 'string',
              'pattern': r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
              'maxLength': 256,
            },
          },
          'allOf': <Object?>[
            <String, Object?>{
              'if': <String, Object?>{
                'properties': <String, Object?>{
                  'role': <String, Object?>{'const': 'observer'},
                },
                'required': <String>['role'],
              },
              'then': <String, Object?>{
                'properties': <String, Object?>{
                  'allowedDecisions': <String, Object?>{'maxItems': 0},
                },
              },
            },
          ],
          'oneOf': <Object?>[
            <String, Object?>{'maxProperties': 0},
            <String, Object?>{
              'required': <String>[
                'authorityId',
                'accessPolicyId',
                'principalId',
                'role',
                'allowedRequirementIds',
                'allowedDecisions',
                'artifactClassifications',
                'grantTtlSeconds',
              ],
            },
          ],
        },
        experienceAuthoringSettingsSchema: const <String, Object?>{
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
          r'$id': experienceAuthoringSettingsSchema,
          'type': 'object',
          'additionalProperties': false,
          'properties': <String, Object?>{
            'authorityId': <String, Object?>{r'$ref': r'#/$defs/id'},
            'accessPolicyId': <String, Object?>{r'$ref': r'#/$defs/id'},
            'principalId': <String, Object?>{r'$ref': r'#/$defs/id'},
            'allowedOperations': <String, Object?>{
              'type': 'array',
              'minItems': 1,
              'maxItems': 13,
              'uniqueItems': true,
              'items': <String, Object?>{
                'enum': <String>[
                  'openDraft',
                  'abandonDraft',
                  'moveNode',
                  'undo',
                  'redo',
                  'reset',
                  'appendFinding',
                  'proposeConcept',
                  'appendComment',
                  'prepareReview',
                  'evaluateAutomatedAcceptance',
                  'decideReview',
                  'promote',
                ],
              },
            },
            'grantTtlSeconds': <String, Object?>{
              'type': 'integer',
              'minimum': 1,
              'maximum': 300,
            },
          },
          r'$defs': <String, Object?>{
            'id': <String, Object?>{
              'type': 'string',
              'pattern': r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$',
              'maxLength': 256,
            },
          },
          'oneOf': <Object?>[
            <String, Object?>{'maxProperties': 0},
            <String, Object?>{
              'required': <String>[
                'authorityId',
                'accessPolicyId',
                'principalId',
                'allowedOperations',
                'grantTtlSeconds',
              ],
            },
          ],
        },
      });

  List<ModuleDescriptor> _modules() => <ModuleDescriptor>[
    _module(
      'catalog',
      provides: const <String>['catalog.read'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.query},
      resources: const <ModuleResource>{ModuleResource.filesystemRead},
    ),
    _module(
      'artifact-store.local',
      provides: const <String>['artifact.store'],
      surfaces: const <ModuleSurface>{ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.authoring},
      resources: const <ModuleResource>{
        ModuleResource.filesystemRead,
        ModuleResource.filesystemWrite,
      },
    ),
    _module(
      'studio.shell',
      provides: const <String>['studio.shell'],
      optionalRequires: const <String>['catalog.read'],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'studio.journey-map',
      provides: const <String>['studio.journey-map'],
      requires: const <String>['catalog.read'],
      optionalRequires: const <String>['evidence.visual'],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'studio.inventory',
      provides: const <String>['studio.inventory'],
      requires: const <String>['catalog.read'],
      optionalRequires: const <String>['evidence.visual'],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'studio.lab',
      provides: const <String>['studio.lab'],
      requires: const <String>['catalog.read'],
      optionalRequires: const <String>[
        'scenario.lab.execute',
        'evidence.visual',
      ],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'scenario.lab.local',
      provides: const <String>['scenario.lab.execute'],
      requires: const <String>[
        'catalog.read',
        'sessions.local',
        'artifact.store',
      ],
      optionalRequires: const <String>['gateway.session', 'evidence.visual'],
      surfaces: const <ModuleSurface>{ModuleSurface.host, ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.ephemeral},
      resources: const <ModuleResource>{
        ModuleResource.filesystemRead,
        ModuleResource.filesystemWrite,
        ModuleResource.process,
        ModuleResource.network,
      },
      configurationSchema: scenarioLabSettingsSchema,
    ),
    _module(
      'studio.quality',
      provides: const <String>['studio.quality'],
      requires: const <String>['catalog.read'],
      optionalRequires: const <String>['evidence.visual'],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'studio.authoring',
      provides: const <String>['studio.authoring'],
      requires: const <String>['catalog.read'],
      optionalRequires: const <String>['experience.authoring'],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'studio.motion',
      provides: const <String>['studio.motion'],
      requires: const <String>['catalog.read'],
      optionalRequires: const <String>['experience.motion'],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'motion.local',
      provides: const <String>['experience.motion'],
      requires: const <String>['catalog.read'],
      surfaces: const <ModuleSurface>{ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.query},
      resources: const <ModuleResource>{ModuleResource.filesystemRead},
    ),
    _module(
      'studio.context',
      provides: const <String>['studio.context'],
      requires: const <String>['catalog.read'],
      optionalRequires: const <String>['context.build'],
      surfaces: const <ModuleSurface>{ModuleSurface.studio},
      effects: const <ModuleEffect>{ModuleEffect.query},
    ),
    _module(
      'context.builder.local',
      provides: const <String>['context.build'],
      requires: const <String>['catalog.read'],
      surfaces: const <ModuleSurface>{ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.query},
      resources: const <ModuleResource>{ModuleResource.filesystemRead},
    ),
    _module(
      'authoring.local',
      provides: const <String>['experience.authoring'],
      requires: const <String>['catalog.read'],
      surfaces: const <ModuleSurface>{ModuleSurface.host},
      effects: const <ModuleEffect>{
        ModuleEffect.authoring,
        ModuleEffect.decision,
      },
      resources: const <ModuleResource>{
        ModuleResource.filesystemRead,
        ModuleResource.filesystemWrite,
      },
      configurationSchema: experienceAuthoringSettingsSchema,
    ),
    _module(
      'quality.decisions.local',
      provides: const <String>['quality.decisions'],
      requires: const <String>[
        'catalog.read',
        'scenario.lab.execute',
        'artifact.store',
      ],
      surfaces: const <ModuleSurface>{ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.decision},
      resources: const <ModuleResource>{
        ModuleResource.filesystemRead,
        ModuleResource.filesystemWrite,
      },
      configurationSchema: scenarioQualityDecisionSettingsSchema,
    ),
    _module(
      'sessions.local',
      provides: const <String>['sessions.local'],
      surfaces: const <ModuleSurface>{
        ModuleSurface.cli,
        ModuleSurface.host,
        ModuleSurface.studio,
      },
      effects: const <ModuleEffect>{ModuleEffect.ephemeral},
      resources: const <ModuleResource>{ModuleResource.process},
    ),
    _module(
      'capture.app-adapter',
      provides: const <String>['evidence.visual'],
      requires: const <String>['sessions.local', 'artifact.store'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.authoring},
      resources: const <ModuleResource>{
        ModuleResource.listener,
        ModuleResource.filesystemWrite,
      },
    ),
    _module(
      'gateway.interceptor',
      provides: const <String>['gateway.session'],
      requires: const <String>['sessions.local'],
      surfaces: const <ModuleSurface>{
        ModuleSurface.cli,
        ModuleSurface.host,
        ModuleSurface.gateway,
        ModuleSurface.studio,
      },
      effects: const <ModuleEffect>{ModuleEffect.infrastructure},
      resources: const <ModuleResource>{
        ModuleResource.process,
        ModuleResource.network,
        ModuleResource.listener,
      },
    ),
    _module(
      'evidence.tests',
      provides: const <String>['evidence.tests'],
      requires: const <String>['artifact.store'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.authoring},
      resources: const <ModuleResource>{
        ModuleResource.process,
        ModuleResource.filesystemWrite,
      },
    ),
    _module(
      'source.impact',
      provides: const <String>['source.impact'],
      requires: const <String>['catalog.read'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.query},
      resources: const <ModuleResource>{ModuleResource.filesystemRead},
    ),
    _module(
      'target.android',
      provides: const <String>['target.android'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.infrastructure},
      resources: const <ModuleResource>{
        ModuleResource.process,
        ModuleResource.device,
      },
    ),
    _module(
      'evidence.android',
      provides: const <String>['evidence.visual', 'evidence.android'],
      requires: const <String>['target.android', 'artifact.store'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.authoring},
      resources: const <ModuleResource>{
        ModuleResource.process,
        ModuleResource.device,
        ModuleResource.filesystemWrite,
      },
    ),
    _module(
      'evidence.auto-preview',
      provides: const <String>['evidence.visual', 'evidence.auto-preview'],
      requires: const <String>['catalog.read', 'artifact.store'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.authoring},
      resources: const <ModuleResource>{
        ModuleResource.process,
        ModuleResource.filesystemRead,
        ModuleResource.filesystemWrite,
      },
      configurationSchema: autoPreviewSettingsSchema,
    ),
    _module(
      'release.local',
      provides: const <String>['release.local'],
      requires: const <String>['catalog.read', 'artifact.store'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{
        ModuleEffect.authoring,
        ModuleEffect.decision,
      },
      resources: const <ModuleResource>{
        ModuleResource.filesystemRead,
        ModuleResource.filesystemWrite,
      },
    ),
    _module(
      'plugins.external',
      provides: const <String>['plugins.external'],
      surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.ephemeral},
      resources: const <ModuleResource>{ModuleResource.process},
    ),
    _module(
      'automation.mcp',
      provides: const <String>['automation.mcp'],
      requires: const <String>['catalog.read'],
      surfaces: const <ModuleSurface>{ModuleSurface.host},
      effects: const <ModuleEffect>{ModuleEffect.query},
      resources: const <ModuleResource>{ModuleResource.listener},
    ),
    _module(
      'hosted.collaboration',
      provides: const <String>['hosted.collaboration'],
      surfaces: const <ModuleSurface>{
        ModuleSurface.cli,
        ModuleSurface.host,
        ModuleSurface.studio,
      },
      effects: const <ModuleEffect>{ModuleEffect.infrastructure},
      resources: const <ModuleResource>{ModuleResource.network},
    ),
    _module(
      'remote.execution',
      provides: const <String>['remote.execution'],
      surfaces: const <ModuleSurface>{
        ModuleSurface.cli,
        ModuleSurface.host,
        ModuleSurface.studio,
      },
      effects: const <ModuleEffect>{ModuleEffect.infrastructure},
      resources: const <ModuleResource>{
        ModuleResource.network,
        ModuleResource.process,
      },
    ),
  ];

  List<KitProfile> _profiles() => <KitProfile>[
    _profile(
      'journey-preview',
      'Journey Map with AutoPreview',
      const <String>[
        'catalog',
        'artifact-store.local',
        'studio.shell',
        'studio.journey-map',
        'studio.inventory',
        'studio.lab',
        'studio.quality',
        'evidence.auto-preview',
      ],
      previewSettings: true,
      visualProvider: 'evidence.auto-preview',
    ),
    _profile(
      'journey-android',
      'Journey Map with Android evidence',
      const <String>[
        'catalog',
        'artifact-store.local',
        'studio.shell',
        'studio.journey-map',
        'studio.inventory',
        'studio.lab',
        'studio.quality',
        'sessions.local',
        'target.android',
        'evidence.android',
      ],
      visualProvider: 'evidence.android',
    ),
    _profile('gateway-lab', 'Gateway laboratory', const <String>[
      'catalog',
      'artifact-store.local',
      'sessions.local',
      'gateway.interceptor',
      'studio.shell',
    ]),
    _profile(
      'gateway-lab-headless',
      'Gateway laboratory without Studio',
      const <String>[
        'catalog',
        'artifact-store.local',
        'sessions.local',
        'gateway.interceptor',
      ],
    ),
    _profile(
      'full-local',
      'Complete local Abel',
      _allModuleIds,
      previewSettings: true,
      visualProvider: 'capture.app-adapter',
    ),
  ];
}

const List<String> _allModuleIds = <String>[
  'catalog',
  'artifact-store.local',
  'studio.shell',
  'studio.journey-map',
  'studio.inventory',
  'studio.lab',
  'studio.quality',
  'studio.authoring',
  'studio.motion',
  'motion.local',
  'studio.context',
  'context.builder.local',
  'authoring.local',
  'quality.decisions.local',
  'scenario.lab.local',
  'sessions.local',
  'capture.app-adapter',
  'gateway.interceptor',
  'evidence.tests',
  'source.impact',
  'target.android',
  'evidence.android',
  'evidence.auto-preview',
  'release.local',
  'plugins.external',
  'automation.mcp',
  'hosted.collaboration',
  'remote.execution',
];

ModuleDescriptor _module(
  String id, {
  required List<String> provides,
  List<String> requires = const <String>[],
  List<String> optionalRequires = const <String>[],
  Set<ModuleSurface> surfaces = const <ModuleSurface>{},
  Set<ModuleEffect> effects = const <ModuleEffect>{},
  Set<ModuleResource> resources = const <ModuleResource>{},
  String? configurationSchema,
}) => ModuleDescriptor(
  id: ModuleId(id),
  version: '0.1.0',
  coreCompatibility: '^0.1.0',
  provides: <ModuleCapabilityRef>[
    for (final capability in provides) _capability(capability),
  ],
  requires: <ModuleRequirement>[
    for (final capability in requires)
      ModuleRequirement(capability: _capability(capability)),
  ],
  optionalRequires: <ModuleRequirement>[
    for (final capability in optionalRequires)
      ModuleRequirement(capability: _capability(capability)),
  ],
  supportedPlatforms: const <String>{'any'},
  surfaces: surfaces,
  effects: effects,
  resourceRequirements: resources,
  configurationSchema: configurationSchema,
);

KitProfile _profile(
  String id,
  String displayName,
  List<String> moduleIds, {
  bool previewSettings = false,
  String? visualProvider,
}) => KitProfile(
  id: id,
  displayName: displayName,
  selection: KitSelection(
    modules: <KitModuleSelection>[
      for (final moduleId in moduleIds)
        KitModuleSelection(
          moduleId: ModuleId(moduleId),
          enabled: true,
          settings: previewSettings && moduleId == 'evidence.auto-preview'
              ? const <String, Object?>{
                  'renderer': 'flutter-test',
                  'capturePolicy': 'static-v1',
                }
              : const <String, Object?>{},
        ),
    ],
    providerBindings: <ProviderBinding>[
      if (visualProvider != null)
        ProviderBinding(
          capability: _capability('evidence.visual'),
          providerModuleIds: <ModuleId>[ModuleId(visualProvider)],
          selectionPolicy: ProviderSelectionPolicy.orderedFirstAvailable,
        ),
    ],
  ),
);

ModuleCapabilityRef _capability(String id) =>
    ModuleCapabilityRef(id: id, version: 1);
