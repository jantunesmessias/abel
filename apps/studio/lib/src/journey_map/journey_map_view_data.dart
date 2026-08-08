import 'package:experience_contracts/experience_contracts.dart';

final class JourneyMapNodeViewData {
  JourneyMapNodeViewData({
    required this.scenarioId,
    required this.selectedVariant,
    required this.projection,
  }) {
    if (projection.status == VisualEvidenceStatus.unbound ||
        projection.scenarioId != scenarioId ||
        projection.variantId != selectedVariant.id) {
      throw ArgumentError(
        'Journey visual must be explicitly bound to its Scenario and Variant',
      );
    }
  }

  final ScenarioId scenarioId;
  final Variant selectedVariant;
  final VisualEvidenceProjection projection;

  ModuleId get providerId => projection.providerId;
  ResourceHandle? get artifact => projection.artifactHandle;
  RuntimeFidelity? get fidelity => projection.fidelity;
  VisualEvidenceStatus get status => projection.status;
  EvidenceFreshness get freshness => projection.freshness;
  List<ModuleDiagnostic> get diagnostics => projection.diagnostics;
}

final class WorkspaceJourneyProjector {
  const WorkspaceJourneyProjector();

  Map<ScenarioId, JourneyMapNodeViewData> project({
    required WorkspaceSnapshot snapshot,
    required ModuleId providerId,
    Map<ScenarioId, VariantId> selectedVariants =
        const <ScenarioId, VariantId>{},
  }) {
    if (!snapshot.providers.any((item) => item.providerId == providerId)) {
      throw ArgumentError(
        'Unknown visual Evidence provider: ${providerId.value}',
      );
    }
    final variantsByApplication = <ApplicationId, List<Variant>>{};
    for (final variant in snapshot.variantManifest.variants) {
      variantsByApplication
          .putIfAbsent(variant.applicationId, () => <Variant>[])
          .add(variant);
    }
    final projections = <String, VisualEvidenceProjection>{
      for (final projection in snapshot.visualProjections)
        if (projection.status != VisualEvidenceStatus.unbound &&
            projection.providerId == providerId)
          '${projection.scenarioId!.value}:${projection.variantId!.value}':
              projection,
    };

    final result = <ScenarioId, JourneyMapNodeViewData>{};
    for (final scenario in snapshot.catalog.scenarios) {
      final variants = variantsByApplication[scenario.applicationId];
      if (variants == null || variants.isEmpty) continue;
      final requested = selectedVariants[scenario.id];
      late final Variant selected;
      late final VisualEvidenceProjection projection;
      if (requested != null) {
        final requestedVariant = variants
            .where((item) => item.id == requested)
            .firstOrNull;
        if (requestedVariant == null) continue;
        final requestedProjection =
            projections['${scenario.id.value}:${requestedVariant.id.value}'];
        if (requestedProjection == null) continue;
        selected = requestedVariant;
        projection = requestedProjection;
      } else {
        final candidates = <(Variant, VisualEvidenceProjection)>[
          for (final variant in variants)
            if (projections['${scenario.id.value}:${variant.id.value}']
                case final candidate?)
              (variant, candidate),
        ]..sort(_compareAutomaticCandidates);
        if (candidates.isEmpty) continue;
        selected = candidates.first.$1;
        projection = candidates.first.$2;
      }
      result[scenario.id] = JourneyMapNodeViewData(
        scenarioId: scenario.id,
        selectedVariant: selected,
        projection: projection,
      );
    }
    return Map<ScenarioId, JourneyMapNodeViewData>.unmodifiable(result);
  }
}

int _compareAutomaticCandidates(
  (Variant, VisualEvidenceProjection) left,
  (Variant, VisualEvidenceProjection) right,
) {
  final projection = _projectionRank(
    left.$2,
  ).compareTo(_projectionRank(right.$2));
  if (projection != 0) return projection;
  final brightness = _brightnessRank(
    left.$1,
  ).compareTo(_brightnessRank(right.$1));
  if (brightness != 0) return brightness;
  final leftArea = left.$1.logicalWidth * left.$1.logicalHeight;
  final rightArea = right.$1.logicalWidth * right.$1.logicalHeight;
  final area = leftArea.compareTo(rightArea);
  if (area != 0) return area;
  return left.$1.id.value.compareTo(right.$1.id.value);
}

int _projectionRank(VisualEvidenceProjection projection) =>
    switch ((projection.status, projection.freshness)) {
      (VisualEvidenceStatus.collected, EvidenceFreshness.fresh) => 0,
      (VisualEvidenceStatus.collected, _) => 1,
      (VisualEvidenceStatus.missing, _) => 2,
      (VisualEvidenceStatus.failed, _) => 3,
      (VisualEvidenceStatus.unsupported, _) => 4,
      (VisualEvidenceStatus.policyDenied, _) => 5,
      (VisualEvidenceStatus.unbound, _) => 6,
    };

int _brightnessRank(Variant variant) => switch (variant.brightness) {
  PreviewBrightness.light => 0,
  PreviewBrightness.dark => 1,
};
