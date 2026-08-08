import 'package:experience_contracts/experience_contracts.dart';

enum ScenarioLabPresentationState {
  notStarted,
  queued,
  starting,
  running,
  cancelling,
  succeeded,
  failed,
  cancelled,
}

final class ScenarioLabProjection {
  const ScenarioLabProjection._({
    required this.scenario,
    required this.plan,
    required this.script,
    required this.steps,
    required this.controls,
    required this.requiredEvidence,
    required this.automatedAcceptance,
    required this.comparisons,
    required this.presentationState,
    required this.runSnapshot,
    required this.runResult,
    required this.qualitySnapshot,
  });

  final Scenario scenario;
  final ScenarioLabPlan plan;
  final ScenarioScriptDefinition script;
  final List<ScenarioLabStepProjection> steps;
  final List<ScenarioLabControlProjection> controls;
  final List<ScenarioLabRequiredEvidenceProjection> requiredEvidence;
  final List<ScenarioLabAcceptanceProjection> automatedAcceptance;
  final List<ScenarioLabComparisonProjection> comparisons;
  final ScenarioLabPresentationState presentationState;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final ScenarioQualitySnapshot? qualitySnapshot;
}

final class ScenarioLabStepProjection {
  const ScenarioLabStepProjection({
    required this.definition,
    required this.execution,
    this.operation,
    this.executionBinding,
  });

  final ScenarioScriptStep definition;
  final ScenarioLabStepSnapshot? execution;
  final ScenarioLabOperationDefinition? operation;
  final ScenarioExecutionBinding? executionBinding;
}

final class ScenarioLabControlProjection {
  const ScenarioLabControlProjection({
    required this.definition,
    required this.result,
  });

  final ScenarioControlDefinition definition;
  final ScenarioControlResult? result;
}

final class ScenarioLabRequiredEvidenceProjection {
  const ScenarioLabRequiredEvidenceProjection({
    required this.definition,
    required this.result,
    required this.verification,
  });

  final RequiredEvidenceDefinition definition;
  final RequiredEvidenceRunResult? result;
  final RequiredEvidenceVerification? verification;
}

final class ScenarioLabAcceptanceProjection {
  const ScenarioLabAcceptanceProjection({
    required this.definition,
    required this.result,
  });

  final AutomatedAcceptanceCriterion definition;
  final AutomatedAcceptanceResult? result;
}

final class ScenarioLabComparisonProjection {
  const ScenarioLabComparisonProjection({
    required this.definition,
    required this.result,
  });

  final ScenarioComparisonBinding definition;
  final ScenarioComparisonResult? result;
}

final class ScenarioLabResolver {
  const ScenarioLabResolver();

  ScenarioLabProjection resolve({
    required CatalogManifest catalog,
    required ScenarioLabManifest manifest,
    required ScenarioId scenarioId,
    required ScenarioScriptId scriptId,
    ScenarioLabRunSnapshot? runSnapshot,
    ScenarioLabRunResult? runResult,
    ScenarioQualitySnapshot? qualitySnapshot,
  }) {
    if (manifest.catalogDigest != catalog.digest) {
      throw ArgumentError('Scenario Lab manifest belongs to another Catalog');
    }

    final scenario = _exactlyOne(
      catalog.scenarios.where((item) => item.id == scenarioId),
      'Scenario is absent or ambiguous in Catalog',
    );
    final plan = _exactlyOne(
      manifest.plans.where((item) => item.scenarioId == scenarioId),
      'Scenario Lab plan is absent or ambiguous',
    );
    final script = _exactlyOne(
      manifest.scripts.where((item) => item.id == scriptId),
      'Scenario Lab script is absent or ambiguous',
    );
    if (script.scenarioId != scenarioId || !plan.scriptIds.contains(scriptId)) {
      throw ArgumentError('Scenario Lab script is outside the selected plan');
    }

    final effectiveSnapshot = _resolveSnapshot(runSnapshot, runResult);
    if (effectiveSnapshot != null) {
      _validateSnapshot(
        catalog: catalog,
        manifest: manifest,
        scenarioId: scenarioId,
        script: script,
        plan: plan,
        snapshot: effectiveSnapshot,
      );
    }
    if (qualitySnapshot != null) {
      final result = runResult;
      if (result == null) {
        throw ArgumentError(
          'Scenario Quality requires the complete bound Lab result',
        );
      }
      qualitySnapshot.validateAgainstResult(result);
    }

    final controlsById = <ScenarioControlId, ScenarioControlDefinition>{
      for (final definition in manifest.controls) definition.id: definition,
    };
    final operationsById =
        <ScenarioLabOperationId, ScenarioLabOperationDefinition>{
          for (final definition in manifest.operations)
            definition.id: definition,
        };
    final bindingsById = <ScenarioExecutionBindingId, ScenarioExecutionBinding>{
      for (final definition in catalog.executionBindings)
        definition.id: definition,
    };
    final evidenceById = <RequiredEvidenceId, RequiredEvidenceDefinition>{
      for (final definition in manifest.requiredEvidence)
        definition.id: definition,
    };
    final acceptanceById =
        <AutomatedAcceptanceCriterionId, AutomatedAcceptanceCriterion>{
          for (final definition in manifest.automatedAcceptanceCriteria)
            definition.id: definition,
        };
    final comparisonsById =
        <ScenarioComparisonBindingId, ScenarioComparisonBinding>{
          for (final definition in manifest.comparisonBindings)
            definition.id: definition,
        };
    final stepResultsById = <String, ScenarioLabStepSnapshot>{
      for (final result
          in effectiveSnapshot?.steps ?? const <ScenarioLabStepSnapshot>[])
        result.stepId: result,
    };
    final controlResultsById = <ScenarioControlId, ScenarioControlResult>{
      for (final result
          in effectiveSnapshot?.controls ?? const <ScenarioControlResult>[])
        result.controlId: result,
    };
    final evidenceResultsById = <RequiredEvidenceId, RequiredEvidenceRunResult>{
      for (final result
          in effectiveSnapshot?.requiredEvidence ??
              const <RequiredEvidenceRunResult>[])
        result.requiredEvidenceId: result,
    };
    final evidenceVerificationsById =
        <RequiredEvidenceId, RequiredEvidenceVerification>{
          for (final verification
              in qualitySnapshot?.requiredEvidence ??
                  const <RequiredEvidenceVerification>[])
            verification.requiredEvidenceId: verification,
        };
    final acceptanceResultsById =
        <AutomatedAcceptanceCriterionId, AutomatedAcceptanceResult>{
          for (final result
              in effectiveSnapshot?.automatedAcceptance ??
                  const <AutomatedAcceptanceResult>[])
            result.criterionId: result,
        };
    final comparisonResultsById =
        <ScenarioComparisonBindingId, ScenarioComparisonResult>{
          for (final result
              in effectiveSnapshot?.comparisons ??
                  const <ScenarioComparisonResult>[])
            result.bindingId: result,
        };

    final steps = <ScenarioLabStepProjection>[
      for (final step in script.steps)
        switch (step) {
          OperationScenarioScriptStep(:final operationId) =>
            ScenarioLabStepProjection(
              definition: step,
              execution: stepResultsById[step.id],
              operation: _required(
                operationsById[operationId],
                'Script references an unknown Lab operation',
              ),
            ),
          ExecutionBindingScenarioScriptStep(:final bindingId) =>
            ScenarioLabStepProjection(
              definition: step,
              execution: stepResultsById[step.id],
              executionBinding: _required(
                bindingsById[bindingId],
                'Script references an unknown execution binding',
              ),
            ),
        },
    ];
    final controls = <ScenarioLabControlProjection>[
      for (final id in plan.controlIds)
        ScenarioLabControlProjection(
          definition: _required(
            controlsById[id],
            'Plan references an unknown Scenario control',
          ),
          result: controlResultsById[id],
        ),
    ];
    final requiredEvidence = <ScenarioLabRequiredEvidenceProjection>[
      for (final id in plan.requiredEvidenceIds)
        ScenarioLabRequiredEvidenceProjection(
          definition: _required(
            evidenceById[id],
            'Plan references unknown Required Evidence',
          ),
          result: evidenceResultsById[id],
          verification: evidenceVerificationsById[id],
        ),
    ];
    final automatedAcceptance = <ScenarioLabAcceptanceProjection>[
      for (final id in plan.automatedAcceptanceCriterionIds)
        ScenarioLabAcceptanceProjection(
          definition: _required(
            acceptanceById[id],
            'Plan references an unknown acceptance criterion',
          ),
          result: acceptanceResultsById[id],
        ),
    ];
    final comparisons = <ScenarioLabComparisonProjection>[
      for (final id in plan.comparisonBindingIds)
        ScenarioLabComparisonProjection(
          definition: _required(
            comparisonsById[id],
            'Plan references an unknown comparison binding',
          ),
          result: comparisonResultsById[id],
        ),
    ];

    return ScenarioLabProjection._(
      scenario: scenario,
      plan: plan,
      script: script,
      steps: List.unmodifiable(steps),
      controls: List.unmodifiable(controls),
      requiredEvidence: List.unmodifiable(requiredEvidence),
      automatedAcceptance: List.unmodifiable(automatedAcceptance),
      comparisons: List.unmodifiable(comparisons),
      presentationState: _presentationState(effectiveSnapshot?.state),
      runSnapshot: effectiveSnapshot,
      runResult: runResult,
      qualitySnapshot: qualitySnapshot,
    );
  }
}

ScenarioLabRunSnapshot? _resolveSnapshot(
  ScenarioLabRunSnapshot? snapshot,
  ScenarioLabRunResult? result,
) {
  if (snapshot != null &&
      result != null &&
      snapshot.digest != result.finalSnapshot.digest) {
    throw ArgumentError('Lab snapshot and result are from different states');
  }
  return result?.finalSnapshot ?? snapshot;
}

void _validateSnapshot({
  required CatalogManifest catalog,
  required ScenarioLabManifest manifest,
  required ScenarioId scenarioId,
  required ScenarioScriptDefinition script,
  required ScenarioLabPlan plan,
  required ScenarioLabRunSnapshot snapshot,
}) {
  if (snapshot.catalogDigest != catalog.digest ||
      snapshot.scenarioLabManifestDigest != manifest.digest ||
      snapshot.scenarioId != scenarioId ||
      snapshot.scriptId != script.id) {
    throw ArgumentError('Lab observation is outside the selected content set');
  }
  final declaredStepIds = script.steps.map((item) => item.id).toList();
  final observedStepIds = snapshot.steps.map((item) => item.stepId).toList();
  if (!_sameOrdered(declaredStepIds, observedStepIds)) {
    throw ArgumentError('Lab observation does not match declared script steps');
  }

  final controls = <ScenarioControlId, ScenarioControlDefinition>{
    for (final item in manifest.controls)
      if (plan.controlIds.contains(item.id)) item.id: item,
  };
  for (final result in snapshot.controls) {
    final definition = controls[result.controlId];
    if (definition == null || !definition.domain.accepts(result.value)) {
      throw ArgumentError('Lab observation contains an undeclared control');
    }
  }

  final evidence = <RequiredEvidenceId, RequiredEvidenceDefinition>{
    for (final item in manifest.requiredEvidence)
      if (plan.requiredEvidenceIds.contains(item.id)) item.id: item,
  };
  for (final result in snapshot.requiredEvidence) {
    final definition = evidence[result.requiredEvidenceId];
    if (definition == null ||
        definition.providerId != result.providerId ||
        definition.fidelity != result.fidelity ||
        definition.variantId != result.variantId) {
      throw ArgumentError(
        'Lab observation contains undeclared Required Evidence',
      );
    }
  }

  final acceptanceIds = plan.automatedAcceptanceCriterionIds.toSet();
  if (snapshot.automatedAcceptance.any(
    (item) => !acceptanceIds.contains(item.criterionId),
  )) {
    throw ArgumentError('Lab observation contains undeclared acceptance');
  }
  final comparisonDefinitions =
      <ScenarioComparisonBindingId, ScenarioComparisonBinding>{
        for (final item in manifest.comparisonBindings)
          if (plan.comparisonBindingIds.contains(item.id)) item.id: item,
      };
  for (final result in snapshot.comparisons) {
    final definition = comparisonDefinitions[result.bindingId];
    if (definition == null ||
        definition.requiredEvidenceId != result.requiredEvidenceId) {
      throw ArgumentError('Lab observation contains undeclared comparison');
    }
  }

  final bindingStep = script.steps.first;
  if (bindingStep case ExecutionBindingScenarioScriptStep(:final bindingId)) {
    if (!plan.executionBindingIds.contains(bindingId)) {
      throw ArgumentError('Script binding is outside the selected plan');
    }
    final binding = _exactlyOne(
      catalog.executionBindings.where((item) => item.id == bindingId),
      'Script execution binding is absent or ambiguous',
    );
    snapshot.runtimeInputs?.validateAgainst(binding);
  }
}

ScenarioLabPresentationState _presentationState(ScenarioLabRunState? state) =>
    switch (state) {
      null => ScenarioLabPresentationState.notStarted,
      ScenarioLabRunState.queued => ScenarioLabPresentationState.queued,
      ScenarioLabRunState.starting => ScenarioLabPresentationState.starting,
      ScenarioLabRunState.running => ScenarioLabPresentationState.running,
      ScenarioLabRunState.cancelling => ScenarioLabPresentationState.cancelling,
      ScenarioLabRunState.succeeded => ScenarioLabPresentationState.succeeded,
      ScenarioLabRunState.failed => ScenarioLabPresentationState.failed,
      ScenarioLabRunState.cancelled => ScenarioLabPresentationState.cancelled,
    };

T _exactlyOne<T>(Iterable<T> values, String message) {
  final matches = values.toList(growable: false);
  if (matches.length != 1) throw ArgumentError(message);
  return matches.single;
}

T _required<T>(T? value, String message) {
  if (value == null) throw ArgumentError(message);
  return value;
}

bool _sameOrdered<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
