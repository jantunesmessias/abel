@TestOn('vm')
library;

import 'dart:async';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/catalog/sample_catalog.dart';
import 'package:devex_studio/src/host/studio_host_client.dart';
import 'package:devex_studio/src/jaspr/studio_app.dart';
import 'package:devex_studio/src/jaspr/verified_artifact_image.dart';
import 'package:devex_ui_system/devex_ui_system.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';

void main() {
  testComponents('renders the authoritative workspace overview', (
    tester,
  ) async {
    final client = _PreviewClient(_workspaceSnapshot());
    tester.pumpComponent(
      DevExStudioApp(
        clientFactory: () => client,
        reconnectDelay: Duration.zero,
      ),
    );
    await tester.pump();

    expect(find.text('Host conectado'), findsOneComponent);
    expect(find.text('Visão geral'), findsComponents);
    expect(find.text('Cobertura visual'), findsOneComponent);
    expect(find.text('Primeira jornada'), findsOneComponent);
  });

  testComponents(
    'collects AutoPreview only after synthetic-data confirmation',
    (tester) async {
      final client = _PreviewClient(_workspaceSnapshot());
      tester.pumpComponent(
        DevExStudioApp(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(find.text('Descobrir'), findsComponents);
      expect(find.text('75%'), findsOneComponent);
      await tester.click(find.componentWithText(DevExButton, 'Ampliar'));
      expect(find.text('100%'), findsOneComponent);
      await tester.click(find.componentWithText(DevExButton, 'Ajustar'));
      expect(find.text('75%'), findsOneComponent);
      expect(find.text('Atualidade'), findsNothing);
      await tester.click(find.componentWithText(DevExButton, 'Filtros'));
      expect(find.text('Status'), findsOneComponent);
      expect(find.text('Atualidade'), findsOneComponent);
      expect(find.text('Fidelidade'), findsOneComponent);
      expect(find.text('Coletar AutoPreview'), findsOneComponent);
      await tester.click(
        find.componentWithText(DevExButton, 'Coletar AutoPreview'),
      );

      expect(find.text('Coletar AutoPreview?'), findsOneComponent);
      expect(client.collectCalls, 0);
      await tester.click(
        find.componentWithText(DevExButton, 'Confirmo dados sintéticos'),
      );
      await tester.pump();

      expect(client.collectCalls, 1);
      expect(client.lastApplicationId, 'sample-app');
      expect(client.lastScenarioId, 'discover');
      expect(client.lastVariantId, 'phone.light');
      expect(client.syntheticDataConfirmed, isTrue);
      expect(find.text('Coletar AutoPreview?'), findsNothing);
    },
    url: '/journeys/sample/scenarios/discover',
  );

  testComponents(
    'renders only a verified local artifact lease and releases it on dispose',
    (tester) async {
      final handle = ResourceHandle(
        uri: Uri.parse(
          'http://127.0.0.1:39011/resources/abcdefghijklmnopqrstuvwxyzABCDEF',
        ),
        digest: Digest.bytes(const <int>[1, 2, 3]),
        mediaType: 'image/png',
        size: 3,
        purpose: 'visual-artifact',
        expiresAt: DateTime.utc(2026, 8, 12),
      );
      final leaseCompleter = Completer<StudioResourceLease>();
      final client = _ResourceClient(leaseCompleter.future);
      var released = false;

      tester.pumpComponent(
        VerifiedArtifactImage(
          handle: handle,
          client: client,
          alt: 'Evidence verificada',
          classes: 'artifact',
        ),
      );
      await tester.pump();

      expect(client.openCalls, 1);
      expect(find.tag('img'), findsNothing);
      expect(find.text('Validando imagem'), findsOneComponent);

      leaseCompleter.complete(
        StudioResourceLease(
          uri: Uri.parse('blob:http://127.0.0.1/verified-artifact'),
          digest: handle.digest,
          mediaType: handle.mediaType,
          size: handle.size,
          releaseCallback: () => released = true,
        ),
      );
      await tester.pump();

      expect(
        find.byComponentPredicate(
          (component) =>
              component is DomComponent &&
              component.tag == 'img' &&
              component.attributes?['src'] ==
                  'blob:http://127.0.0.1/verified-artifact',
          description: 'verified blob image',
        ),
        findsOneComponent,
      );
      expect(
        find.byComponentPredicate(
          (component) =>
              component is DomComponent &&
              component.attributes?['src'] == handle.uri.toString(),
          description: 'raw Host resource URL',
        ),
        findsNothing,
      );

      tester.binding.detachRootComponent();
      await tester.pump();
      expect(released, isTrue);
    },
  );
}

WorkspaceSnapshot _workspaceSnapshot() {
  final catalog = sampleCatalogManifest();
  final providerId = ModuleId('evidence.auto-preview');
  final variant = Variant(
    id: VariantId('phone.light'),
    applicationId: ApplicationId('sample-app'),
    logicalWidth: 390,
    logicalHeight: 844,
    devicePixelRatio: 3,
    brightness: PreviewBrightness.light,
    localeTag: 'pt-BR',
  );
  return WorkspaceSnapshot(
    revision: 1,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: <Variant>[variant],
      sources: <VariantDefinitionSource>[
        VariantDefinitionSource(
          variantId: variant.id,
          sourceId: 'auto-preview.sample',
          sourceDigest: Digest.semantic(const <String, Object?>{'source': 1}),
        ),
      ],
    ),
    effectiveKitManifest: EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic(const <String, Object?>{'plan': 1}),
      modules: <EffectiveModuleState>[
        EffectiveModuleState(
          moduleId: providerId,
          state: ModuleRuntimeState.ready,
          health: ModuleHealth.healthy,
          effectiveCapabilities: <ModuleCapabilityRef>[
            ModuleCapabilityRef(id: 'evidence.visual', version: 1),
            ModuleCapabilityRef(id: 'evidence.auto-preview', version: 1),
          ],
        ),
        EffectiveModuleState(
          moduleId: ModuleId('studio.shell'),
          state: ModuleRuntimeState.ready,
          health: ModuleHealth.healthy,
          effectiveCapabilities: <ModuleCapabilityRef>[
            ModuleCapabilityRef(id: 'studio.shell', version: 1),
          ],
        ),
      ],
      commands: const <String>[],
      rpcMethods: const <String>[
        'devex.preview.collect',
        'devex.preview.status',
        'devex.preview.cancel',
      ],
      studioContributions: const <String>['studio.shell', 'studio.journey-map'],
      generatedAt: DateTime.utc(2026, 8, 11),
    ),
    providers: <VisualEvidenceProviderState>[
      VisualEvidenceProviderState(
        providerId: providerId,
        displayName: 'AutoPreview',
        health: ModuleHealth.healthy,
        supportedFidelities: const <RuntimeFidelity>{
          RuntimeFidelity.structural,
        },
        supportsCollection: true,
      ),
    ],
    visualProjections: <VisualEvidenceProjection>[
      VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: ScenarioId('discover'),
        variantId: variant.id,
        capturePolicyId: 'static-v1',
        status: VisualEvidenceStatus.missing,
        freshness: EvidenceFreshness.missing,
      ),
    ],
    generatedAt: DateTime.utc(2026, 8, 11),
  );
}

final class _PreviewClient
    implements StudioHostClient, StudioHostPreviewClient {
  _PreviewClient(this.snapshot);

  final WorkspaceSnapshot snapshot;
  int collectCalls = 0;
  String? lastApplicationId;
  String? lastScenarioId;
  String? lastVariantId;
  bool? syntheticDataConfirmed;

  @override
  Future<Map<String, Object?>> collectPreview({
    required String applicationId,
    String? scenarioId,
    String? variantId,
    required bool syntheticDataConfirmed,
  }) async {
    collectCalls += 1;
    lastApplicationId = applicationId;
    lastScenarioId = scenarioId;
    lastVariantId = variantId;
    this.syntheticDataConfirmed = syntheticDataConfirmed;
    return <String, Object?>{
      'operationId': 'preview-1',
      'state': 'completed',
      'completedItems': 1,
      'totalItems': 1,
      'failedItems': 0,
    };
  }

  @override
  Future<Map<String, Object?>> cancelPreview(String operationId) async =>
      <String, Object?>{
        'operationId': operationId,
        'state': 'cancelled',
        'completedItems': 0,
        'totalItems': 1,
        'failedItems': 0,
      };

  @override
  Future<void> close() async {}

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => snapshot;

  @override
  Future<Map<String, Object?>> previewStatus(String operationId) async =>
      <String, Object?>{
        'operationId': operationId,
        'state': 'completed',
        'completedItems': 1,
        'totalItems': 1,
        'failedItems': 0,
      };

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => snapshot;
}

final class _ResourceClient implements StudioHostResourceClient {
  _ResourceClient(this.lease);

  final Future<StudioResourceLease> lease;
  int openCalls = 0;

  @override
  Future<StudioResourceLease> openVisualArtifact(ResourceHandle handle) {
    openCalls += 1;
    return lease;
  }
}
