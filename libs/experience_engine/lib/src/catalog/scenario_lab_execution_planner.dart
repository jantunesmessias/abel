import 'package:experience_contracts/experience_contracts.dart';

/// A closed planning failure raised before Scenario Lab effects are possible.
final class ScenarioLabPlanningException implements Exception {
  ScenarioLabPlanningException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(issues.toSet().toList()..sort()) {
    if (this.issues.isEmpty) {
      throw ArgumentError('ScenarioLabPlanningException requires issues');
    }
  }

  final List<String> issues;

  @override
  String toString() => 'Scenario Lab planning failed:\n${issues.join('\n')}';
}

/// One authored script step with its catalog or manifest reference resolved.
///
/// These types carry declarative data only. They do not invoke adapters,
/// collect Evidence, start Sessions or otherwise apply effects.
sealed class PlannedScenarioLabStep {
  const PlannedScenarioLabStep._(this.step);

  final ScenarioScriptStep step;

  Map<String, Object?> toJson();
}

/// The initial, catalog-bound execution selection authored by the script.
final class PlannedScenarioLabExecutionBindingStep
    extends PlannedScenarioLabStep {
  const PlannedScenarioLabExecutionBindingStep._({
    required ExecutionBindingScenarioScriptStep step,
    required this.binding,
  }) : super._(step);

  @override
  ExecutionBindingScenarioScriptStep get step =>
      super.step as ExecutionBindingScenarioScriptStep;

  final ScenarioExecutionBinding binding;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'step': step.toJson(),
    'binding': binding.toJson(),
  };
}

/// One allowlisted Scenario Lab operation selected by the authored script.
final class PlannedScenarioLabOperationStep extends PlannedScenarioLabStep {
  const PlannedScenarioLabOperationStep._({
    required OperationScenarioScriptStep step,
    required this.operation,
  }) : super._(step);

  @override
  OperationScenarioScriptStep get step =>
      super.step as OperationScenarioScriptStep;

  final ScenarioLabOperationDefinition operation;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'step': step.toJson(),
    'operation': operation.toJson(),
  };
}

/// A deterministic, digest-fenced materialization of one authored Lab script.
///
/// Construction is private so callers cannot add operations or replace steps.
/// Only [ScenarioLabExecutionPlanner] can produce this value.
final class ScenarioLabExecutionPlan {
  ScenarioLabExecutionPlan._({
    required this.catalogDigest,
    required this.scenarioLabManifestDigest,
    required this.scenarioId,
    required this.plan,
    required this.script,
    required this.initialBinding,
    required Iterable<PlannedScenarioLabStep> steps,
  }) : steps = List<PlannedScenarioLabStep>.unmodifiable(steps);

  final Digest catalogDigest;
  final Digest scenarioLabManifestDigest;
  final ScenarioId scenarioId;
  final ScenarioLabPlan plan;
  final ScenarioScriptDefinition script;
  final ScenarioExecutionBinding initialBinding;
  final List<PlannedScenarioLabStep> steps;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'catalogDigest': catalogDigest.value,
    'scenarioLabManifestDigest': scenarioLabManifestDigest.value,
    'scenarioId': scenarioId.value,
    'plan': plan.toJson(),
    'script': script.toJson(),
    'initialBinding': initialBinding.toJson(),
    'steps': <Object?>[for (final step in steps) step.toJson()],
    if (includeDigest) 'digest': digest.value,
  };
}

/// Resolves exactly one catalog-bound Scenario Lab script without effects.
///
/// The caller can select only an existing [ScenarioId] and
/// [ScenarioScriptId]. Operations, arguments and free-form configuration are
/// deliberately absent from this API.
final class ScenarioLabExecutionPlanner {
  const ScenarioLabExecutionPlanner();

  ScenarioLabExecutionPlan plan({
    required CatalogManifest catalog,
    required ScenarioLabManifest manifest,
    required ScenarioId scenarioId,
    required ScenarioScriptId scriptId,
    required Digest expectedCatalogDigest,
    required Digest expectedScenarioLabManifestDigest,
  }) {
    final fenceIssues = <String>[];
    if (catalog.digest != expectedCatalogDigest) {
      fenceIssues.add('expected Catalog digest does not match the Catalog');
    }
    if (manifest.digest != expectedScenarioLabManifestDigest) {
      fenceIssues.add(
        'expected Scenario Lab manifest digest does not match the manifest',
      );
    }
    if (manifest.catalogDigest != catalog.digest) {
      fenceIssues.add('Scenario Lab manifest does not belong to the Catalog');
    }
    if (fenceIssues.isNotEmpty) {
      throw ScenarioLabPlanningException(fenceIssues);
    }

    try {
      manifest.validateAgainst(catalog);
    } on ArgumentError catch (error) {
      throw ScenarioLabPlanningException(<String>[
        'Scenario Lab manifest is invalid for the Catalog: ${error.message}',
      ]);
    }

    final issues = <String>[];
    final scenarios = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final bindings = <ScenarioExecutionBindingId, ScenarioExecutionBinding>{
      for (final binding in catalog.executionBindings) binding.id: binding,
    };
    final operations = <ScenarioLabOperationId, ScenarioLabOperationDefinition>{
      for (final operation in manifest.operations) operation.id: operation,
    };

    if (!scenarios.containsKey(scenarioId)) {
      issues.add('unknown Scenario ${scenarioId.value}');
    }

    final matchingPlans = manifest.plans
        .where((candidate) => candidate.scenarioId == scenarioId)
        .toList(growable: false);
    final selectedPlan = matchingPlans.length == 1
        ? matchingPlans.single
        : null;
    if (selectedPlan == null) {
      issues.add('missing or ambiguous Lab plan for ${scenarioId.value}');
    }

    final matchingScripts = manifest.scripts
        .where((candidate) => candidate.id == scriptId)
        .toList(growable: false);
    final selectedScript = matchingScripts.length == 1
        ? matchingScripts.single
        : null;
    if (selectedScript == null) {
      issues.add('missing or ambiguous Lab script ${scriptId.value}');
    } else if (selectedScript.scenarioId != scenarioId) {
      issues.add(
        'Lab script ${scriptId.value} crosses Scenario ${scenarioId.value}',
      );
    }

    if (selectedPlan != null &&
        selectedScript != null &&
        !selectedPlan.scriptIds.contains(selectedScript.id)) {
      issues.add(
        'Lab script ${selectedScript.id.value} is not allowlisted by the plan',
      );
    }
    if (issues.isNotEmpty || selectedPlan == null || selectedScript == null) {
      throw ScenarioLabPlanningException(issues);
    }

    final plannedSteps = <PlannedScenarioLabStep>[];
    ScenarioExecutionBinding? initialBinding;
    var bindingStepCount = 0;
    for (var index = 0; index < selectedScript.steps.length; index += 1) {
      final step = selectedScript.steps[index];
      switch (step) {
        case ExecutionBindingScenarioScriptStep():
          bindingStepCount += 1;
          if (index != 0 || bindingStepCount != 1) {
            issues.add(
              'Lab script ${selectedScript.id.value} has a non-initial binding step',
            );
            continue;
          }
          if (!selectedPlan.executionBindingIds.contains(step.bindingId)) {
            issues.add(
              'execution binding ${step.bindingId.value} is not allowlisted by the plan',
            );
            continue;
          }
          final binding = bindings[step.bindingId];
          if (binding == null) {
            issues.add('missing execution binding ${step.bindingId.value}');
            continue;
          }
          if (binding.scenarioId != scenarioId) {
            issues.add(
              'execution binding ${step.bindingId.value} crosses Scenario ${scenarioId.value}',
            );
            continue;
          }
          initialBinding = binding;
          plannedSteps.add(
            PlannedScenarioLabExecutionBindingStep._(
              step: step,
              binding: binding,
            ),
          );
        case OperationScenarioScriptStep():
          if (!selectedPlan.operationIds.contains(step.operationId)) {
            issues.add(
              'operation ${step.operationId.value} is not allowlisted by the plan',
            );
            continue;
          }
          final operation = operations[step.operationId];
          if (operation == null) {
            issues.add('missing Lab operation ${step.operationId.value}');
            continue;
          }
          if (operation.scenarioId != scenarioId) {
            issues.add(
              'Lab operation ${step.operationId.value} crosses Scenario ${scenarioId.value}',
            );
            continue;
          }
          plannedSteps.add(
            PlannedScenarioLabOperationStep._(step: step, operation: operation),
          );
      }
    }

    if (bindingStepCount != 1 || initialBinding == null) {
      issues.add(
        'Lab script ${selectedScript.id.value} requires one initial execution binding',
      );
    }
    if (plannedSteps.length != selectedScript.steps.length) {
      issues.add(
        'Lab script ${selectedScript.id.value} could not be materialized exactly',
      );
    }
    if (issues.isNotEmpty || initialBinding == null) {
      throw ScenarioLabPlanningException(issues);
    }

    return ScenarioLabExecutionPlan._(
      catalogDigest: catalog.digest,
      scenarioLabManifestDigest: manifest.digest,
      scenarioId: scenarioId,
      plan: selectedPlan,
      script: selectedScript,
      initialBinding: initialBinding,
      steps: plannedSteps,
    );
  }
}
