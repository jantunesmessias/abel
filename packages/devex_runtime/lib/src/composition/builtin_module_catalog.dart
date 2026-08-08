import 'package:devex_contracts/devex_contracts.dart';

/// The statically packaged inventory. Consumer configuration can select these
/// modules, but cannot add factories or load Dart code.
final class BuiltinModuleCatalog {
  const BuiltinModuleCatalog();

  static const String autoPreviewSettingsSchema =
      'urn:devex:schema:module:auto-preview-settings:v1';

  ModuleCatalog create({
    required String platform,
    String distributionId = 'devex-kit',
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
              // The v1 runner deliberately executes one isolated Flutter
              // subprocess at a time. Raise this only with a conformance test
              // proving deterministic, bounded parallel capture.
              'maximum': 1,
            },
          },
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
      'Complete local DevExKit',
      _allModuleIds,
      previewSettings: true,
      visualProvider: 'capture.app-adapter',
    ),
    _profile(
      'legacy-full-local-v1',
      'Consumer configuration v1 compatibility',
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
