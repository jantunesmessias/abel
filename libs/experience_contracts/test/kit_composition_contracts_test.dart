import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final catalogModule = ModuleDescriptor(
    id: ModuleId('catalog'),
    version: '1.0.0',
    coreCompatibility: '^0.1.0',
    provides: <ModuleCapabilityRef>[
      ModuleCapabilityRef(id: 'catalog.read', version: 1),
    ],
    supportedPlatforms: const <String>{'any'},
    surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.studio},
    effects: const <ModuleEffect>{ModuleEffect.query},
    resourceRequirements: const <ModuleResource>{ModuleResource.filesystemRead},
  );
  final artifactModule = ModuleDescriptor(
    id: ModuleId('artifact-store.local'),
    version: '1.0.0',
    coreCompatibility: '^0.1.0',
    provides: <ModuleCapabilityRef>[
      ModuleCapabilityRef(id: 'artifact.store', version: 1),
    ],
    supportedPlatforms: const <String>{'linux-x64'},
    surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
    effects: const <ModuleEffect>{ModuleEffect.ephemeral},
    resourceRequirements: const <ModuleResource>{
      ModuleResource.filesystemRead,
      ModuleResource.filesystemWrite,
    },
  );
  final previewModule = ModuleDescriptor(
    id: ModuleId('evidence.auto-preview'),
    version: '1.0.0',
    coreCompatibility: '^0.1.0',
    provides: <ModuleCapabilityRef>[
      ModuleCapabilityRef(id: 'evidence.visual.preview', version: 1),
    ],
    requires: <ModuleRequirement>[
      ModuleRequirement(
        capability: ModuleCapabilityRef(id: 'catalog.read', version: 1),
      ),
      ModuleRequirement(
        capability: ModuleCapabilityRef(id: 'artifact.store', version: 1),
      ),
    ],
    supportedPlatforms: const <String>{'linux-x64'},
    surfaces: const <ModuleSurface>{ModuleSurface.cli, ModuleSurface.host},
    effects: const <ModuleEffect>{ModuleEffect.ephemeral},
    resourceRequirements: const <ModuleResource>{
      ModuleResource.process,
      ModuleResource.filesystemRead,
      ModuleResource.filesystemWrite,
    },
    configurationSchema:
        'https://github.com/jantunesmessias/abel/schemas/configuration/auto-preview-settings',
  );
  final profile = KitProfile(
    id: 'journey-preview',
    displayName: 'Journey + AutoPreview',
    selection: KitSelection(
      modules: <KitModuleSelection>[
        KitModuleSelection(moduleId: catalogModule.id, enabled: true),
        KitModuleSelection(moduleId: artifactModule.id, enabled: true),
        KitModuleSelection(
          moduleId: previewModule.id,
          enabled: true,
          settings: const <String, Object?>{
            'capturePolicy': 'static-v1',
            'renderer': 'flutter-test',
          },
        ),
      ],
    ),
  );
  final moduleCatalog = ModuleCatalog(
    distributionId: 'full-local',
    coreVersion: '0.1.0',
    platform: 'linux-x64',
    modules: <ModuleDescriptor>[catalogModule, artifactModule, previewModule],
    profiles: <KitProfile>[profile],
    defaultProfileId: profile.id,
  );

  test(
    'composition documents are closed, canonical, and schema conformant',
    () {
      final binding = ProviderBinding(
        capability: ModuleCapabilityRef(
          id: 'evidence.visual.preview',
          version: 1,
        ),
        providerModuleIds: <ModuleId>[previewModule.id],
        selectionPolicy: ProviderSelectionPolicy.orderedFirstAvailable,
      );
      final plan = ResolvedKitPlan(
        distributionDigest: moduleCatalog.digest,
        profileId: profile.id,
        enabledModules: <ResolvedModule>[
          ResolvedModule(
            moduleId: catalogModule.id,
            descriptorDigest: catalogModule.digest,
          ),
          ResolvedModule(
            moduleId: artifactModule.id,
            descriptorDigest: artifactModule.digest,
          ),
          ResolvedModule(
            moduleId: previewModule.id,
            descriptorDigest: previewModule.digest,
            settings: const <String, Object?>{
              'renderer': 'flutter-test',
              'capturePolicy': 'static-v1',
            },
          ),
        ],
        providerBindings: <ProviderBinding>[binding],
        dependencyOrder: <ModuleId>[
          catalogModule.id,
          artifactModule.id,
          previewModule.id,
        ],
        startupPolicy: 'fail-required-v1',
      );
      final observedAt = DateTime.utc(2026, 8, 10, 3);
      final manifest = EffectiveKitManifest(
        resolvedPlanDigest: plan.digest,
        modules: <EffectiveModuleState>[
          EffectiveModuleState(
            moduleId: catalogModule.id,
            state: ModuleRuntimeState.ready,
            health: ModuleHealth.healthy,
            effectiveCapabilities: catalogModule.provides,
          ),
          EffectiveModuleState(
            moduleId: artifactModule.id,
            state: ModuleRuntimeState.ready,
            health: ModuleHealth.healthy,
            effectiveCapabilities: artifactModule.provides,
          ),
          EffectiveModuleState(
            moduleId: previewModule.id,
            state: ModuleRuntimeState.ready,
            health: ModuleHealth.healthy,
            effectiveCapabilities: previewModule.provides,
          ),
        ],
        commands: const <String>['evidence collect-previews'],
        rpcMethods: const <String>['composition.describe'],
        studioContributions: const <String>['studio.journey-map'],
        generatedAt: observedAt,
      );
      final validator = Draft202012Validator(
        jsonDecode(
              File(
                p.join(
                  _root(),
                  'schemas/distribution/kit-composition.schema.json',
                ),
              ).readAsStringSync(),
            )
            as Object,
      );
      final documents = <Map<String, Object?>>[
        catalogModule.toJson(),
        profile.toJson(),
        moduleCatalog.toJson(),
        plan.toJson(),
        manifest.toJson(),
      ];
      for (final document in documents) {
        expect(
          validator.validate(document).isValid,
          isTrue,
          reason: '$document',
        );
      }

      expect(
        ModuleDescriptor.fromJson(catalogModule.toJson()).digest,
        catalogModule.digest,
      );
      expect(KitProfile.fromJson(profile.toJson()).toJson(), profile.toJson());
      expect(
        ModuleCatalog.fromJson(moduleCatalog.toJson()).digest,
        moduleCatalog.digest,
      );
      expect(ResolvedKitPlan.fromJson(plan.toJson()).digest, plan.digest);
      expect(
        EffectiveKitManifest.fromJson(manifest.toJson()).digest,
        manifest.digest,
      );
    },
  );

  test('digests and ordering are independent of caller collection order', () {
    final reversed = ModuleCatalog(
      distributionId: moduleCatalog.distributionId,
      coreVersion: moduleCatalog.coreVersion,
      platform: moduleCatalog.platform,
      modules: <ModuleDescriptor>[previewModule, artifactModule, catalogModule],
      profiles: <KitProfile>[profile],
      defaultProfileId: profile.id,
    );
    expect(reversed.digest, moduleCatalog.digest);
    expect(
      reversed.modules.map((module) => module.id.value),
      orderedEquals(<String>[
        'artifact-store.local',
        'catalog',
        'evidence.auto-preview',
      ]),
    );
  });

  test('invalid dependency and profile references fail closed', () {
    expect(
      () => ModuleDescriptor(
        id: ModuleId('self'),
        version: '1.0.0',
        coreCompatibility: '^0.1.0',
        provides: <ModuleCapabilityRef>[
          ModuleCapabilityRef(id: 'self.read', version: 1),
        ],
        requires: <ModuleRequirement>[
          ModuleRequirement(
            capability: ModuleCapabilityRef(id: 'self.read', version: 1),
          ),
        ],
        supportedPlatforms: const <String>{'any'},
      ),
      throwsArgumentError,
    );
    expect(
      () => ModuleCatalog(
        distributionId: 'full-local',
        coreVersion: '0.1.0',
        platform: 'linux-x64',
        modules: <ModuleDescriptor>[catalogModule],
        profiles: <KitProfile>[profile],
        defaultProfileId: profile.id,
      ),
      throwsArgumentError,
    );
    final unknown = catalogModule.toJson()..['unknown'] = true;
    expect(() => ModuleDescriptor.fromJson(unknown), throwsFormatException);
  });

  test('runtime state enforces health and immutable settings', () {
    expect(
      () => EffectiveModuleState(
        moduleId: catalogModule.id,
        state: ModuleRuntimeState.ready,
        health: ModuleHealth.notApplicable,
        effectiveCapabilities: catalogModule.provides,
      ),
      throwsArgumentError,
    );
    final mutable = <String, Object?>{
      'nested': <Object?>[
        <String, Object?>{'value': 1},
      ],
    };
    final selection = KitModuleSelection(
      moduleId: previewModule.id,
      enabled: true,
      settings: mutable,
    );
    (mutable['nested']! as List<Object?>).clear();
    expect(selection.settings['nested'], hasLength(1));
  });
}

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
