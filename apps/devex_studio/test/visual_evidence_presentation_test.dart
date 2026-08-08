import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/journey_map/visual_evidence_presentation.dart';
import 'package:test/test.dart';

void main() {
  test('counts scenario coverage independently from capture variants', () {
    final first = _collected('screen', 'phone.light');
    final second = _collected('screen', 'phone.dark');

    final coverage = VisualEvidenceCoverage.forScenarios(
      scenarioIds: <ScenarioId>[ScenarioId('screen'), ScenarioId('details')],
      projections: <VisualEvidenceProjection>[first, second],
    );

    expect(coverage.totalScenarios, 2);
    expect(coverage.currentScenarios, 1);
    expect(coverage.currentCaptures, 2);
    expect(coverage.scenariosWithoutCurrentCapture, 1);
    expect(coverage.isComplete, isFalse);
  });

  test('uses product language for fidelity and visual state', () {
    expect(runtimeFidelityLabel(RuntimeFidelity.structural), 'Estrutural');
    expect(
      visualEvidenceStatusLabel(
        VisualEvidenceStatus.collected,
        EvidenceFreshness.stale,
      ),
      'Desatualizada',
    );
    expect(
      visualEvidenceStatusLabel(
        VisualEvidenceStatus.missing,
        EvidenceFreshness.missing,
      ),
      'Sem captura',
    );
  });
}

VisualEvidenceProjection _collected(String scenarioId, String variantId) {
  final artifact = Digest.semantic(<String, Object?>{
    'scenarioId': scenarioId,
    'variantId': variantId,
  });
  return VisualEvidenceProjection(
    providerId: ModuleId('evidence.auto-preview'),
    scenarioId: ScenarioId(scenarioId),
    variantId: VariantId(variantId),
    evidenceDigest: Digest.semantic(<String, Object?>{
      'evidence': '$scenarioId:$variantId',
    }),
    artifactDigest: artifact,
    status: VisualEvidenceStatus.collected,
    freshness: EvidenceFreshness.fresh,
    fidelity: RuntimeFidelity.structural,
    observedAt: DateTime.utc(2026, 8, 10),
    artifactHandle: ResourceHandle(
      uri: Uri.parse(
        'http://127.0.0.1:39001/resources/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
      ),
      digest: artifact,
      mediaType: 'image/png',
      size: 8,
      purpose: 'visual-artifact',
      expiresAt: DateTime.utc(2026, 8, 10, 1),
    ),
  );
}
