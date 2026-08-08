import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'renews expired visual artifact handles without recollecting pixels',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'workspace-preview-renewal-',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final clock = _MutableClock(DateTime.utc(2026, 8, 10, 12));
      final ids = _Ids();
      final store = FileSystemWorkspaceStore(workspaceRoot: temporary.path);
      final resources = HostResourceRegistry(clock: clock, ids: ids);
      final catalog = _catalog();
      const builtins = BuiltinModuleCatalog();
      final moduleCatalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: moduleCatalog,
        profileId: 'journey-preview',
        configurationSchemas: builtins.configurationSchemas,
      );
      final manifest = EffectiveKitManifest(
        resolvedPlanDigest: plan.digest,
        modules: <EffectiveModuleState>[
          EffectiveModuleState(
            moduleId: ModuleId('evidence.auto-preview'),
            state: ModuleRuntimeState.ready,
            health: ModuleHealth.healthy,
            effectiveCapabilities: <ModuleCapabilityRef>[
              ModuleCapabilityRef(id: 'evidence.visual', version: 1),
            ],
          ),
        ],
        commands: const <String>[],
        rpcMethods: const <String>[],
        studioContributions: const <String>[],
        generatedAt: clock.nowUtc(),
      );
      final workspace = HostWorkspaceService(
        initialCatalog: catalog,
        clock: clock,
      )..initialize(manifest);
      final variant = Variant(
        id: VariantId('phone.light'),
        applicationId: ApplicationId('app'),
        logicalWidth: 390,
        logicalHeight: 844,
        devicePixelRatio: 3,
        brightness: PreviewBrightness.light,
        localeTag: 'pt-BR',
      );
      final bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      final artifactDigest = store.putBlob(bytes);
      final oldHandle = resources.grantBytes(
        hostOrigin: Uri.parse('http://127.0.0.1:39001'),
        audienceOrigin: Uri.parse('http://127.0.0.1:39002'),
        bytes: bytes,
        mediaType: 'image/png',
        purpose: 'visual-artifact',
        ttl: const Duration(minutes: 2),
      );
      workspace.replaceVisualState(
        variantManifest: VariantManifest(
          catalogDigest: catalog.digest,
          variants: <Variant>[variant],
          sources: <VariantDefinitionSource>[
            VariantDefinitionSource(
              variantId: variant.id,
              sourceId: 'auto-preview.screen',
              sourceDigest: Digest.semantic(const <String, Object?>{
                'source': 'screen',
              }),
            ),
          ],
        ),
        projections: <VisualEvidenceProjection>[
          VisualEvidenceProjection(
            providerId: ModuleId('evidence.auto-preview'),
            scenarioId: ScenarioId('screen'),
            variantId: variant.id,
            evidenceDigest: Digest.semantic(const <String, Object?>{
              'evidence': 1,
            }),
            artifactDigest: artifactDigest,
            status: VisualEvidenceStatus.collected,
            freshness: EvidenceFreshness.fresh,
            fidelity: RuntimeFidelity.structural,
            observedAt: clock.nowUtc(),
            artifactHandle: oldHandle,
          ),
        ],
      );
      final published = <String>[];
      final service = HostAutoPreviewService(
        workspace: workspace,
        store: store,
        plan: plan,
        platform: 'linux-x64',
        resources: resources,
        hostOrigin: () => Uri.parse('http://127.0.0.1:39001'),
        studioOrigin: Uri.parse('http://127.0.0.1:39002'),
        publishEvent: (method, _) async => published.add(method),
        clock: clock,
        ids: ids,
      );

      clock.value = clock.value.add(const Duration(minutes: 2));
      final previousRevision = workspace.snapshot.revision;
      final previousSnapshotDigest = workspace.snapshot.digest;
      final previousWorkspaceContentDigest =
          workspace.snapshot.workspaceContentDigest;
      final previousContentRevision = workspace.contentRevision;
      final previousContentSetDigest =
          workspace.contentSetIdentity.contentSetDigest;
      final renewals = await Future.wait<bool>(<Future<bool>>[
        service.renewArtifactHandles(),
        service.renewArtifactHandles(),
        service.renewArtifactHandles(),
      ]);
      expect(renewals.where((item) => item), hasLength(1));

      final renewed =
          workspace.snapshot.visualProjections.single.artifactHandle!;
      expect(renewed.uri, isNot(oldHandle.uri));
      expect(renewed.digest, artifactDigest);
      expect(renewed.isExpiredAt(clock.nowUtc()), isFalse);
      expect(workspace.snapshot.revision, previousRevision + 1);
      expect(workspace.snapshot.digest, isNot(previousSnapshotDigest));
      expect(
        workspace.snapshot.workspaceContentDigest,
        previousWorkspaceContentDigest,
      );
      expect(workspace.contentRevision, previousContentRevision + 1);
      expect(
        workspace.contentSetIdentity.contentSetDigest,
        previousContentSetDigest,
      );
      expect(published, <String>[
        'workspace.changed',
        'experience.content.changed',
      ]);
      expect(await service.renewArtifactHandles(), isFalse);
      await service.close();
    },
  );

  test(
    'renews multiple handles atomically when resource quota is exhausted',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'workspace-preview-renewal-atomic-',
      );
      addTearDown(() => temporary.deleteSync(recursive: true));
      final clock = _MutableClock(DateTime.utc(2026, 8, 10, 12));
      final ids = _Ids();
      final store = FileSystemWorkspaceStore(workspaceRoot: temporary.path);
      final resources = HostResourceRegistry(
        clock: clock,
        ids: ids,
        maxActiveResources: 3,
      );
      final catalog = _catalog();
      const builtins = BuiltinModuleCatalog();
      final moduleCatalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: moduleCatalog,
        profileId: 'journey-preview',
        configurationSchemas: builtins.configurationSchemas,
      );
      final manifest = EffectiveKitManifest(
        resolvedPlanDigest: plan.digest,
        modules: <EffectiveModuleState>[
          EffectiveModuleState(
            moduleId: ModuleId('evidence.auto-preview'),
            state: ModuleRuntimeState.ready,
            health: ModuleHealth.healthy,
            effectiveCapabilities: <ModuleCapabilityRef>[
              ModuleCapabilityRef(id: 'evidence.visual', version: 1),
            ],
          ),
        ],
        commands: const <String>[],
        rpcMethods: const <String>[],
        studioContributions: const <String>[],
        generatedAt: clock.nowUtc(),
      );
      final workspace = HostWorkspaceService(
        initialCatalog: catalog,
        clock: clock,
      )..initialize(manifest);
      final variants = <Variant>[
        Variant(
          id: VariantId('phone.light'),
          applicationId: ApplicationId('app'),
          logicalWidth: 390,
          logicalHeight: 844,
          devicePixelRatio: 3,
          brightness: PreviewBrightness.light,
          localeTag: 'pt-BR',
        ),
        Variant(
          id: VariantId('tablet.light'),
          applicationId: ApplicationId('app'),
          logicalWidth: 1024,
          logicalHeight: 768,
          devicePixelRatio: 2,
          brightness: PreviewBrightness.light,
          localeTag: 'pt-BR',
        ),
      ];
      final bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      final artifactDigest = store.putBlob(bytes);
      final oldHandles = <ResourceHandle>[
        for (final _ in variants)
          resources.grantBytes(
            hostOrigin: Uri.parse('http://127.0.0.1:39001'),
            audienceOrigin: Uri.parse('http://127.0.0.1:39002'),
            bytes: bytes,
            mediaType: 'image/png',
            purpose: 'visual-artifact',
            ttl: const Duration(minutes: 2),
          ),
      ];
      workspace.replaceVisualState(
        variantManifest: VariantManifest(
          catalogDigest: catalog.digest,
          variants: variants,
          sources: <VariantDefinitionSource>[
            for (final variant in variants)
              VariantDefinitionSource(
                variantId: variant.id,
                sourceId: 'auto-preview.screen',
                sourceDigest: Digest.semantic(<String, Object?>{
                  'source': 'screen',
                  'variantId': variant.id.value,
                }),
              ),
          ],
        ),
        projections: <VisualEvidenceProjection>[
          for (var index = 0; index < variants.length; index += 1)
            VisualEvidenceProjection(
              providerId: ModuleId('evidence.auto-preview'),
              scenarioId: ScenarioId('screen'),
              variantId: variants[index].id,
              evidenceDigest: Digest.semantic(<String, Object?>{
                'evidence': index,
              }),
              artifactDigest: artifactDigest,
              status: VisualEvidenceStatus.collected,
              freshness: EvidenceFreshness.fresh,
              fidelity: RuntimeFidelity.structural,
              observedAt: clock.nowUtc(),
              artifactHandle: oldHandles[index],
            ),
        ],
      );
      final published = <String>[];
      final service = HostAutoPreviewService(
        workspace: workspace,
        store: store,
        plan: plan,
        platform: 'linux-x64',
        resources: resources,
        hostOrigin: () => Uri.parse('http://127.0.0.1:39001'),
        studioOrigin: Uri.parse('http://127.0.0.1:39002'),
        publishEvent: (method, _) async => published.add(method),
        clock: clock,
        ids: ids,
      );

      clock.value = clock.value.add(const Duration(minutes: 2));
      expect(await service.renewArtifactHandles(), isTrue);
      expect(resources.activeCount, 2);
      published.clear();
      final beforeSnapshot = workspace.snapshot;
      final beforeV1 = workspace.contentSetIdentity.toJson();
      final beforeV2 = workspace.contentSetIdentity.toJson();
      final beforeHandles = <Uri>[
        for (final projection in beforeSnapshot.visualProjections)
          projection.artifactHandle!.uri,
      ];

      await expectLater(
        service.renewArtifactHandles(force: true),
        throwsStateError,
      );

      expect(identical(workspace.snapshot, beforeSnapshot), isTrue);
      expect(workspace.contentSetIdentity.toJson(), beforeV1);
      expect(workspace.contentSetIdentity.toJson(), beforeV2);
      expect(<Uri>[
        for (final projection in workspace.snapshot.visualProjections)
          projection.artifactHandle!.uri,
      ], beforeHandles);
      expect(resources.activeCount, 2);
      expect(published, isEmpty);
      await service.close();
    },
  );
}

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(
      id: WorkspaceId('workspace'),
      displayName: 'Workspace',
    ),
    applications: <Application>[
      Application(
        id: ApplicationId('app'),
        workspaceId: WorkspaceId('workspace'),
        displayName: 'App',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('flow'),
        applicationId: ApplicationId('app'),
        title: 'Flow',
        scenarioIds: <ScenarioId>[ScenarioId('screen')],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(
        id: ScenarioId('screen'),
        applicationId: ApplicationId('app'),
        title: 'Screen',
      ),
    ],
    transitions: const <Transition>[],
  );
}

final class _MutableClock implements Clock {
  _MutableClock(this.value);

  DateTime value;
  var _monotonicMicroseconds = 0;

  @override
  DateTime nowUtc() => value.toUtc();

  @override
  int monotonicMicroseconds() => _monotonicMicroseconds++;
}

final class _Ids implements IdGenerator {
  var _next = 0;

  @override
  String nextId() {
    final current = _next++;
    return 'id-${current.toString().padLeft(12, '0')}';
  }
}
