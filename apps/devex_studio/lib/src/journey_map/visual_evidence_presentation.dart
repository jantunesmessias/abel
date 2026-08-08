import 'package:devex_contracts/devex_contracts.dart';

final class VisualEvidenceCoverage {
  const VisualEvidenceCoverage._({
    required this.totalScenarios,
    required this.currentScenarios,
    required this.currentCaptures,
  });

  factory VisualEvidenceCoverage.forScenarios({
    required Iterable<ScenarioId> scenarioIds,
    required Iterable<VisualEvidenceProjection> projections,
  }) {
    final expected = scenarioIds.toSet();
    final current = projections.where(
      (item) =>
          item.scenarioId != null &&
          expected.contains(item.scenarioId) &&
          item.status == VisualEvidenceStatus.collected &&
          item.freshness == EvidenceFreshness.fresh,
    );
    return VisualEvidenceCoverage._(
      totalScenarios: expected.length,
      currentScenarios: current.map((item) => item.scenarioId!).toSet().length,
      currentCaptures: current.length,
    );
  }

  final int totalScenarios;
  final int currentScenarios;
  final int currentCaptures;

  int get scenariosWithoutCurrentCapture => totalScenarios - currentScenarios;
  bool get isComplete =>
      totalScenarios > 0 && currentScenarios == totalScenarios;
}

String visualEvidenceStatusLabel(
  VisualEvidenceStatus status,
  EvidenceFreshness freshness,
) => switch (status) {
  VisualEvidenceStatus.collected => switch (freshness) {
    EvidenceFreshness.fresh => 'Atual',
    EvidenceFreshness.stale => 'Desatualizada',
    EvidenceFreshness.invalid => 'Inválida',
    EvidenceFreshness.missing => 'Sem captura',
  },
  VisualEvidenceStatus.unbound => 'Sem vínculo',
  VisualEvidenceStatus.missing => 'Sem captura',
  VisualEvidenceStatus.failed => 'Falhou',
  VisualEvidenceStatus.unsupported => 'Não suportada',
  VisualEvidenceStatus.policyDenied => 'Bloqueada por política',
};

String visualEvidenceStatusFilterLabel(VisualEvidenceStatus value) =>
    switch (value) {
      VisualEvidenceStatus.unbound => 'Sem vínculo',
      VisualEvidenceStatus.collected => 'Coletada',
      VisualEvidenceStatus.missing => 'Sem captura',
      VisualEvidenceStatus.failed => 'Falhou',
      VisualEvidenceStatus.unsupported => 'Não suportada',
      VisualEvidenceStatus.policyDenied => 'Bloqueada por política',
    };

String evidenceFreshnessLabel(EvidenceFreshness value) => switch (value) {
  EvidenceFreshness.missing => 'Ausente',
  EvidenceFreshness.fresh => 'Atual',
  EvidenceFreshness.stale => 'Desatualizada',
  EvidenceFreshness.invalid => 'Inválida',
};

String runtimeFidelityLabel(RuntimeFidelity value) => switch (value) {
  RuntimeFidelity.structural => 'Estrutural',
  RuntimeFidelity.simulated => 'Simulada',
  RuntimeFidelity.hostNative => 'Host nativo',
  RuntimeFidelity.deviceAttested => 'Dispositivo atestado',
};
