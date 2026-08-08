import 'package:experience_contracts/experience_contracts.dart';

import 'authoring_parser.dart';
import 'catalog_compiler.dart';

/// Compiles adjacent authoring v2 into catalog-bound Scenario Lab and Quality
/// inputs. It declares data only; execution remains outside this compiler.
final class ScenarioLabCompiler {
  const ScenarioLabCompiler();

  bool hasAuthoring(Iterable<AuthoringDocument> source) =>
      source.any((document) => _scenarioLabKinds.contains(document.kind));

  ScenarioLabManifest compile(
    Iterable<AuthoringDocument> source, {
    required CatalogManifest catalog,
  }) {
    final documents = source
        .where((document) => _scenarioLabKinds.contains(document.kind))
        .toList(growable: false);
    final issues = <String>[];
    final keys = <String>{};
    for (final document in documents) {
      if (document.schemaVersion != 2) {
        issues.add(
          '${document.sourceName}: Scenario Lab authoring must use v2',
        );
      }
      final key = '${document.kind.name}:${document.id}';
      if (!keys.add(key)) issues.add('duplicate document $key');
      _validateSpecShape(document, issues);
    }

    final capabilities = <CapabilityDescriptor>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.appAdapterCapability,
    )) {
      _capture(document, issues, () {
        capabilities.add(CapabilityDescriptor.fromJson(_entityJson(document)));
      });
    }

    final controls = <ScenarioControlDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.scenarioControl)) {
      _capture(document, issues, () {
        controls.add(ScenarioControlDefinition.fromJson(_entityJson(document)));
      });
    }

    final operations = <ScenarioLabOperationDefinition>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.scenarioLabOperation,
    )) {
      _capture(document, issues, () {
        operations.add(
          ScenarioLabOperationDefinition.fromJson(_entityJson(document)),
        );
      });
    }

    final scripts = <ScenarioScriptDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.scenarioScript)) {
      _capture(document, issues, () {
        scripts.add(ScenarioScriptDefinition.fromJson(_entityJson(document)));
      });
    }

    final criteria = <AutomatedAcceptanceCriterion>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.automatedAcceptanceCriterion,
    )) {
      _capture(document, issues, () {
        criteria.add(
          AutomatedAcceptanceCriterion.fromJson(_entityJson(document)),
        );
      });
    }

    final requiredEvidence = <RequiredEvidenceDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.requiredEvidence)) {
      _capture(document, issues, () {
        requiredEvidence.add(
          RequiredEvidenceDefinition.fromJson(_entityJson(document)),
        );
      });
    }

    final comparisonBindings = <ScenarioComparisonBinding>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.scenarioComparisonBinding,
    )) {
      _capture(document, issues, () {
        comparisonBindings.add(
          ScenarioComparisonBinding.fromJson(_entityJson(document)),
        );
      });
    }

    final visualPolicies = <VisualComparisonPolicy>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.visualComparisonPolicy,
    )) {
      _capture(document, issues, () {
        visualPolicies.add(
          VisualComparisonPolicy.fromJson(<String, Object?>{
            'schemaVersion': 1,
            'kind': 'VisualComparisonPolicy',
            ...document.spec,
            'id': document.id,
          }),
        );
      });
    }

    final semanticPolicies = <SemanticComparisonPolicy>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.semanticComparisonPolicy,
    )) {
      _capture(document, issues, () {
        semanticPolicies.add(
          SemanticComparisonPolicy.fromJson(<String, Object?>{
            'schemaVersion': 1,
            'kind': 'SemanticComparisonPolicy',
            ...document.spec,
            'id': document.id,
          }),
        );
      });
    }

    final humanApprovals = <HumanApprovalRequirement>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.humanApprovalRequirement,
    )) {
      _capture(document, issues, () {
        humanApprovals.add(
          HumanApprovalRequirement.fromJson(_entityJson(document)),
        );
      });
    }

    final supplementalArtifacts = <SupplementalArtifactReference>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.supplementalArtifact,
    )) {
      _capture(document, issues, () {
        supplementalArtifacts.add(
          SupplementalArtifactReference.fromJson(_entityJson(document)),
        );
      });
    }

    final plans = <ScenarioLabPlan>[];
    for (final document in _ofKind(documents, AuthoringKind.scenarioLabPlan)) {
      _capture(document, issues, () {
        final plan = ScenarioLabPlan.fromJson(document.spec);
        if (document.id != plan.scenarioId.value) {
          throw const FormatException(
            'metadata.id must equal spec.scenarioId for ScenarioLabPlan',
          );
        }
        plans.add(plan);
      });
    }

    ScenarioLabManifest? manifest;
    _captureSynthetic('scenario-lab-manifest', issues, () {
      manifest = ScenarioLabManifest(
        catalog: catalog,
        appAdapterCapabilities: capabilities,
        controls: controls,
        operations: operations,
        scripts: scripts,
        automatedAcceptanceCriteria: criteria,
        requiredEvidence: requiredEvidence,
        comparisonBindings: comparisonBindings,
        visualComparisonPolicies: visualPolicies,
        semanticComparisonPolicies: semanticPolicies,
        humanApprovalRequirements: humanApprovals,
        supplementalArtifacts: supplementalArtifacts,
        plans: plans,
      );
    });
    if (issues.isNotEmpty || manifest == null) {
      throw CatalogCompileException(issues);
    }
    return manifest!;
  }
}

const Set<AuthoringKind> _scenarioLabKinds = <AuthoringKind>{
  AuthoringKind.appAdapterCapability,
  AuthoringKind.scenarioControl,
  AuthoringKind.scenarioLabOperation,
  AuthoringKind.scenarioScript,
  AuthoringKind.automatedAcceptanceCriterion,
  AuthoringKind.requiredEvidence,
  AuthoringKind.scenarioComparisonBinding,
  AuthoringKind.visualComparisonPolicy,
  AuthoringKind.semanticComparisonPolicy,
  AuthoringKind.humanApprovalRequirement,
  AuthoringKind.supplementalArtifact,
  AuthoringKind.scenarioLabPlan,
};

Iterable<AuthoringDocument> _ofKind(
  Iterable<AuthoringDocument> documents,
  AuthoringKind kind,
) => documents.where((document) => document.kind == kind);

Map<String, Object?> _entityJson(AuthoringDocument document) =>
    <String, Object?>{...document.spec, 'id': document.id};

void _capture(
  AuthoringDocument document,
  List<String> issues,
  void Function() body,
) {
  try {
    body();
  } on ArgumentError catch (error) {
    issues.add('${document.sourceName}: ${error.message}');
  } on FormatException catch (error) {
    issues.add('${document.sourceName}: ${error.message}');
  }
}

void _captureSynthetic(
  String sourceName,
  List<String> issues,
  void Function() body,
) {
  try {
    body();
  } on ArgumentError catch (error) {
    issues.add('$sourceName: ${error.message}');
  } on FormatException catch (error) {
    issues.add('$sourceName: ${error.message}');
  }
}

void _validateSpecShape(AuthoringDocument document, List<String> issues) {
  final allowed = switch (document.kind) {
    AuthoringKind.appAdapterCapability => const <String>{
      'version',
      'operations',
    },
    AuthoringKind.scenarioControl => const <String>{
      'scenarioId',
      'displayName',
      'capability',
      'readOperationId',
      'writeOperationId',
      'resetOperationId',
      'domain',
    },
    AuthoringKind.scenarioLabOperation => const <String>{
      'scenarioId',
      'kind',
      'controlId',
      'value',
      'evidenceRequirementId',
    },
    AuthoringKind.scenarioScript => const <String>{
      'scenarioId',
      'displayName',
      'timeoutMs',
      'timeoutOutcome',
      'cancellationPolicy',
      'steps',
    },
    AuthoringKind.automatedAcceptanceCriterion => const <String>{
      'scenarioId',
      'displayName',
      'kind',
      'scriptId',
      'evidenceRequirementId',
      'controlId',
      'expectedValue',
    },
    AuthoringKind.requiredEvidence => const <String>{
      'scenarioId',
      'providerId',
      'fidelity',
      'variantId',
      'freshness',
      'allowedClassifications',
      'evidencePolicyId',
      'comparisonPolicy',
    },
    AuthoringKind.scenarioComparisonBinding => const <String>{
      'scenarioId',
      'requiredEvidenceId',
      'baseline',
      'candidate',
    },
    AuthoringKind.visualComparisonPolicy => const <String>{
      'maxChannelDelta',
      'maxChangedPixelRatio',
    },
    AuthoringKind.semanticComparisonPolicy => const <String>{
      'maxChangedNodes',
      'ignoreBounds',
    },
    AuthoringKind.humanApprovalRequirement => const <String>{
      'scenarioId',
      'reviewGuideId',
      'reviewGuideStepId',
      'scope',
    },
    AuthoringKind.supplementalArtifact => const <String>{
      'scenarioId',
      'requiredEvidenceId',
      'role',
      'artifactDigest',
      'provenanceDigest',
      'classification',
    },
    AuthoringKind.scenarioLabPlan => const <String>{
      'scenarioId',
      'executionBindingIds',
      'controlIds',
      'operationIds',
      'scriptIds',
      'automatedAcceptanceCriterionIds',
      'requiredEvidenceIds',
      'comparisonBindingIds',
      'humanApprovalRequirementIds',
      'supplementalArtifactIds',
    },
    _ => const <String>{},
  };
  for (final key in document.spec.keys) {
    if (!allowed.contains(key)) {
      issues.add('${document.sourceName}: unknown field spec.$key');
    }
  }
}
