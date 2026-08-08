import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/journey_map/journey_map_view_data.dart';
import 'package:test/test.dart';

void main() {
  test('projects canonical collected/stale Evidence without local paths', () {
    final snapshot = _snapshot(collected: true);

    final projected = const WorkspaceJourneyProjector().project(
      snapshot: snapshot,
      providerId: ModuleId('evidence.auto-preview'),
    );
    final visual = projected[ScenarioId('discover')]!;

    expect(visual.status, VisualEvidenceStatus.collected);
    expect(visual.freshness, EvidenceFreshness.stale);
    expect(visual.fidelity, RuntimeFidelity.structural);
    expect(visual.selectedVariant.id, VariantId('phone.light'));
    expect(visual.artifact?.uri.path, startsWith('/resources/'));
    expect(visual.artifact?.uri.query, isEmpty);
  });

  test('does not substitute a failed projection or another provider', () {
    final snapshot = _snapshot(collected: false);

    final visual = const WorkspaceJourneyProjector().project(
      snapshot: snapshot,
      providerId: ModuleId('evidence.auto-preview'),
    )[ScenarioId('discover')]!;

    expect(visual.status, VisualEvidenceStatus.failed);
    expect(visual.artifact, isNull);
    expect(visual.providerId, ModuleId('evidence.auto-preview'));
  });

  test('does not invent a capture target for an unbound Scenario', () {
    final projected = const WorkspaceJourneyProjector().project(
      snapshot: _snapshot(collected: true),
      providerId: ModuleId('evidence.auto-preview'),
    );

    expect(projected, isNot(contains(ScenarioId('review'))));
  });

  test('preserves a canonical missing target declared by the Host', () {
    final visual = const WorkspaceJourneyProjector().project(
      snapshot: _snapshot(collected: true, declareMissingReview: true),
      providerId: ModuleId('evidence.auto-preview'),
    )[ScenarioId('review')]!;

    expect(visual.status, VisualEvidenceStatus.missing);
    expect(visual.freshness, EvidenceFreshness.missing);
    expect(visual.artifact, isNull);
  });
}

WorkspaceSnapshot _snapshot({
  required bool collected,
  bool declareMissingReview = false,
}) {
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
  final desktopVariant = Variant(
    id: VariantId('desktop.light'),
    applicationId: ApplicationId('sample-app'),
    logicalWidth: 1280,
    logicalHeight: 900,
    devicePixelRatio: 1,
    brightness: PreviewBrightness.light,
    localeTag: 'pt-BR',
  );
  final artifactDigest = Digest.bytes(const <int>[1, 2, 3]);
  return WorkspaceSnapshot(
    revision: 1,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: <Variant>[desktopVariant, variant],
      sources: <VariantDefinitionSource>[
        VariantDefinitionSource(
          variantId: desktopVariant.id,
          sourceId: 'auto-preview.desktop',
          sourceDigest: Digest.semantic(const <String, Object?>{
            'source': 'desktop',
          }),
        ),
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
          ],
        ),
      ],
      commands: const <String>[],
      rpcMethods: const <String>[],
      studioContributions: const <String>[],
      generatedAt: DateTime.utc(2026, 8, 10),
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
        evidenceDigest: Digest.semantic(const <String, Object?>{'evidence': 1}),
        artifactDigest: collected ? artifactDigest : null,
        captureKey: Digest.semantic(const <String, Object?>{'capture': 1}),
        status: collected
            ? VisualEvidenceStatus.collected
            : VisualEvidenceStatus.failed,
        freshness: collected
            ? EvidenceFreshness.stale
            : EvidenceFreshness.invalid,
        fidelity: collected ? RuntimeFidelity.structural : null,
        observedAt: collected ? DateTime.utc(2026, 8, 10) : null,
        artifactHandle: collected
            ? ResourceHandle(
                uri: Uri.parse(
                  'http://127.0.0.1:43123/resources/abcdefghijklmnopqrstuvwxyzABCDEF',
                ),
                digest: artifactDigest,
                mediaType: 'image/png',
                size: 3,
                purpose: 'visual-artifact',
                expiresAt: DateTime.utc(2030),
              )
            : null,
      ),
      if (declareMissingReview)
        VisualEvidenceProjection(
          providerId: providerId,
          scenarioId: ScenarioId('review'),
          variantId: variant.id,
          capturePolicyId: 'static-v1',
          status: VisualEvidenceStatus.missing,
          freshness: EvidenceFreshness.missing,
        ),
    ],
    generatedAt: DateTime.utc(2026, 8, 10),
  );
}
