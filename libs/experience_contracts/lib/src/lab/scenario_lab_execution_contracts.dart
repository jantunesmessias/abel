import '../catalog/catalog_contracts.dart';
import '../catalog/scenario_lab_contracts.dart';
import '../composition/kit_composition_contracts.dart';
import '../digest.dart';
import '../evidence/evidence_contracts.dart';
import '../gateway/gateway_contracts.dart';
import '../preview/preview_contracts.dart';
import '../studio/experience_content_contracts.dart';

final class ScenarioLabRunRequestId extends OpaqueId {
  factory ScenarioLabRunRequestId(String value) {
    _executionId(value, 'ScenarioLabRunRequest');
    return ScenarioLabRunRequestId._(value);
  }

  const ScenarioLabRunRequestId._(super.value);
}

final class ScenarioLabRunId extends OpaqueId {
  factory ScenarioLabRunId(String value) {
    _executionId(value, 'ScenarioLabRun');
    return ScenarioLabRunId._(value);
  }

  const ScenarioLabRunId._(super.value);
}

final class ScenarioLabCommandId extends OpaqueId {
  factory ScenarioLabCommandId(String value) {
    _executionId(value, 'ScenarioLabCommand');
    return ScenarioLabCommandId._(value);
  }

  const ScenarioLabCommandId._(super.value);
}

final class HumanDecisionRecordId extends OpaqueId {
  factory HumanDecisionRecordId(String value) {
    _executionId(value, 'HumanDecisionRecord');
    return HumanDecisionRecordId._(value);
  }

  const HumanDecisionRecordId._(super.value);
}

final class ScenarioQualityPrincipalId extends OpaqueId {
  factory ScenarioQualityPrincipalId(String value) {
    _executionId(value, 'ScenarioQualityPrincipal');
    return ScenarioQualityPrincipalId._(value);
  }

  const ScenarioQualityPrincipalId._(super.value);
}

enum ScenarioLabRunState {
  queued,
  starting,
  running,
  cancelling,
  succeeded,
  failed,
  cancelled;

  bool get isTerminal => switch (this) {
    succeeded || failed || cancelled => true,
    _ => false,
  };
}

enum ScenarioLabStepState {
  pending,
  running,
  succeeded,
  failed,
  cancelled,
  skipped;

  bool get isTerminal => switch (this) {
    succeeded || failed || cancelled || skipped => true,
    _ => false,
  };
}

enum ScenarioLabStepTerminalCause {
  completed,
  operationFailed,
  timedOut,
  cancelled,
  skippedDependency,
}

enum ScenarioLabTerminalCause {
  completed,
  acceptanceFailed,
  stepFailed,
  timedOut,
  cancelledByUser,
  hostShutdown,
  adapterDisconnected,
  cleanupFailed,
  internalError,
}

enum ScenarioLabFailureCause {
  adapterRejected,
  adapterDisconnected,
  invalidResponse,
  policyDenied,
  unsupported,
  timedOut,
  internalError,
}

enum RequiredEvidenceResultState {
  pending,
  collected,
  missing,
  failed,
  unsupported,
  policyDenied,
  cancelled,
}

enum ScenarioControlResultSource { read, write, reset }

enum ScenarioComparisonResultKind { visual, semantic }

enum ScenarioLabCleanupState {
  pending,
  running,
  succeeded,
  failed,
  notRequired,
}

enum VerificationState { notRun, passed, failed, error }

enum HumanDecisionState { unreviewed, approved, rejected, superseded }

enum HumanDecision { approved, rejected }

final class ScenarioLabFailure {
  const ScenarioLabFailure({required this.cause, this.diagnosticDigest});

  final ScenarioLabFailureCause cause;
  final Digest? diagnosticDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'cause': cause.name,
    if (diagnosticDigest != null) 'diagnosticDigest': diagnosticDigest!.value,
  };

  factory ScenarioLabFailure.fromJson(Object? value) {
    final json = _executionObject(value, 'ScenarioLabFailure');
    _executionOnly(json, const <String>{
      'cause',
      'diagnosticDigest',
    }, 'ScenarioLabFailure');
    return ScenarioLabFailure(
      cause: _executionEnum(
        ScenarioLabFailureCause.values,
        _executionString(json, 'cause', 'ScenarioLabFailure'),
        'ScenarioLabFailure.cause',
      ),
      diagnosticDigest: _executionOptionalDigest(
        json,
        'diagnosticDigest',
        'ScenarioLabFailure',
      ),
    );
  }
}

/// Host-resolved runtime inputs frozen before a run leaves `queued`.
///
/// Gateway fields are absent together for a binding without a Gateway preset,
/// and present together otherwise. This prevents the Content Set digest from
/// being mistaken for a digest of separately compiled Gateway inputs.
final class ScenarioLabRuntimeInputBinding {
  ScenarioLabRuntimeInputBinding({
    required this.executionFingerprintDigest,
    required this.executionTargetId,
    this.gatewayPresetId,
    this.compiledGatewayPlanDigest,
    this.routingTableDigest,
  }) {
    _executionId(executionTargetId, 'ExecutionTarget');
    final gatewayFields = <Object?>[
      gatewayPresetId,
      compiledGatewayPlanDigest,
      routingTableDigest,
    ];
    if (gatewayFields.any((value) => value != null) &&
        gatewayFields.any((value) => value == null)) {
      throw ArgumentError(
        'Gateway preset, compiled plan and routing table are present together',
      );
    }
  }

  final Digest executionFingerprintDigest;
  final String executionTargetId;
  final GatewayPresetId? gatewayPresetId;
  final Digest? compiledGatewayPlanDigest;
  final Digest? routingTableDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'executionFingerprintDigest': executionFingerprintDigest.value,
    'executionTargetId': executionTargetId,
    if (gatewayPresetId != null) 'gatewayPresetId': gatewayPresetId!.value,
    if (compiledGatewayPlanDigest != null)
      'compiledGatewayPlanDigest': compiledGatewayPlanDigest!.value,
    if (routingTableDigest != null)
      'routingTableDigest': routingTableDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRuntimeInputBinding.fromJson(Object? value) {
    final json = _executionObject(value, 'ScenarioLabRuntimeInputBinding');
    _executionOnly(json, const <String>{
      'executionFingerprintDigest',
      'executionTargetId',
      'gatewayPresetId',
      'compiledGatewayPlanDigest',
      'routingTableDigest',
      'digest',
    }, 'ScenarioLabRuntimeInputBinding');
    final gatewayPresetId = _executionOptionalString(
      json,
      'gatewayPresetId',
      'ScenarioLabRuntimeInputBinding',
    );
    final binding = ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest: Digest(
        _executionString(
          json,
          'executionFingerprintDigest',
          'ScenarioLabRuntimeInputBinding',
        ),
      ),
      executionTargetId: _executionString(
        json,
        'executionTargetId',
        'ScenarioLabRuntimeInputBinding',
      ),
      gatewayPresetId: gatewayPresetId == null
          ? null
          : GatewayPresetId(gatewayPresetId),
      compiledGatewayPlanDigest: _executionOptionalDigest(
        json,
        'compiledGatewayPlanDigest',
        'ScenarioLabRuntimeInputBinding',
      ),
      routingTableDigest: _executionOptionalDigest(
        json,
        'routingTableDigest',
        'ScenarioLabRuntimeInputBinding',
      ),
    );
    _executionVerifyDigest(
      json,
      binding.digest,
      'ScenarioLabRuntimeInputBinding',
    );
    return binding;
  }

  void validateAgainst(ScenarioExecutionBinding executionBinding) {
    final expectedGatewayPresetId = executionBinding.gatewayPresetId == null
        ? null
        : GatewayPresetId(executionBinding.gatewayPresetId!);
    if (executionTargetId != executionBinding.targetId ||
        gatewayPresetId != expectedGatewayPresetId) {
      throw ArgumentError(
        'Runtime input binding does not match catalog execution binding',
      );
    }
  }
}

/// Idempotent caller intent. Runtime values and policies are selected only
/// from the catalog-bound Scenario Lab manifest, never supplied by the caller.
final class ScenarioLabRunStartRequest {
  ScenarioLabRunStartRequest({
    required this.requestId,
    required this.expectedContentSetDigest,
    required this.expectedScenarioLabManifestDigest,
    required this.scenarioId,
    required this.scriptId,
    required DateTime requestedAt,
  }) : requestedAt = requestedAt.toUtc();

  static const int schemaVersion = 1;
  final ScenarioLabRunRequestId requestId;
  final Digest expectedContentSetDigest;
  final Digest expectedScenarioLabManifestDigest;
  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
  final DateTime requestedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRunStartRequest',
    'requestId': requestId.value,
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'expectedScenarioLabManifestDigest':
        expectedScenarioLabManifestDigest.value,
    'scenarioId': scenarioId.value,
    'scriptId': scriptId.value,
    'requestedAt': requestedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRunStartRequest.fromJson(Object? value) {
    final json =
        _executionDocument(value, 'ScenarioLabRunStartRequest', const <String>{
          'requestId',
          'expectedContentSetDigest',
          'expectedScenarioLabManifestDigest',
          'scenarioId',
          'scriptId',
          'requestedAt',
        });
    final request = ScenarioLabRunStartRequest(
      requestId: ScenarioLabRunRequestId(
        _executionString(json, 'requestId', 'ScenarioLabRunStartRequest'),
      ),
      expectedContentSetDigest: Digest(
        _executionString(
          json,
          'expectedContentSetDigest',
          'ScenarioLabRunStartRequest',
        ),
      ),
      expectedScenarioLabManifestDigest: Digest(
        _executionString(
          json,
          'expectedScenarioLabManifestDigest',
          'ScenarioLabRunStartRequest',
        ),
      ),
      scenarioId: ScenarioId(
        _executionString(json, 'scenarioId', 'ScenarioLabRunStartRequest'),
      ),
      scriptId: ScenarioScriptId(
        _executionString(json, 'scriptId', 'ScenarioLabRunStartRequest'),
      ),
      requestedAt: _executionTime(
        json,
        'requestedAt',
        'ScenarioLabRunStartRequest',
      ),
    );
    _executionVerifyDigest(json, request.digest, 'ScenarioLabRunStartRequest');
    return request;
  }

  void validateAgainst({
    required ExperienceContentSetIdentity contentSet,
    required ScenarioLabManifest scenarioLabManifest,
  }) {
    if (contentSet.contentSetDigest != expectedContentSetDigest ||
        contentSet.scenarioLabManifestDigest !=
            expectedScenarioLabManifestDigest ||
        scenarioLabManifest.digest != expectedScenarioLabManifestDigest ||
        scenarioLabManifest.catalogDigest != contentSet.catalogDigest) {
      throw ArgumentError(
        'Scenario Lab start request content binding mismatch',
      );
    }
    final matchingPlans = scenarioLabManifest.plans.where(
      (plan) => plan.scenarioId == scenarioId,
    );
    if (matchingPlans.length != 1 ||
        !matchingPlans.single.scriptIds.contains(scriptId)) {
      throw ArgumentError(
        'Scenario Lab start request selects an undeclared Scenario/script',
      );
    }
  }
}

final class ScenarioLabStepSnapshot {
  ScenarioLabStepSnapshot({
    required this.stepId,
    required this.state,
    DateTime? startedAt,
    DateTime? completedAt,
    this.terminalCause,
  }) : startedAt = startedAt?.toUtc(),
       completedAt = completedAt?.toUtc() {
    _executionId(stepId, 'ScenarioLabStep');
    if (this.startedAt != null &&
        this.completedAt != null &&
        this.completedAt!.isBefore(this.startedAt!)) {
      throw ArgumentError('Scenario Lab step completes before it starts');
    }
    switch (state) {
      case ScenarioLabStepState.pending:
        if (startedAt != null || completedAt != null || terminalCause != null) {
          throw ArgumentError('Pending step cannot have execution fields');
        }
      case ScenarioLabStepState.running:
        if (startedAt == null || completedAt != null || terminalCause != null) {
          throw ArgumentError('Running step has invalid execution fields');
        }
      case ScenarioLabStepState.succeeded:
        if (startedAt == null ||
            completedAt == null ||
            terminalCause != ScenarioLabStepTerminalCause.completed) {
          throw ArgumentError('Succeeded step requires completed cause');
        }
      case ScenarioLabStepState.failed:
        if (startedAt == null ||
            completedAt == null ||
            !const <ScenarioLabStepTerminalCause>{
              ScenarioLabStepTerminalCause.operationFailed,
              ScenarioLabStepTerminalCause.timedOut,
            }.contains(terminalCause)) {
          throw ArgumentError('Failed step requires failure terminal cause');
        }
      case ScenarioLabStepState.cancelled:
        if (completedAt == null ||
            terminalCause != ScenarioLabStepTerminalCause.cancelled) {
          throw ArgumentError('Cancelled step requires cancelled cause');
        }
      case ScenarioLabStepState.skipped:
        if (startedAt != null ||
            completedAt == null ||
            terminalCause != ScenarioLabStepTerminalCause.skippedDependency) {
          throw ArgumentError('Skipped step requires skipped-dependency cause');
        }
    }
  }

  final String stepId;
  final ScenarioLabStepState state;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final ScenarioLabStepTerminalCause? terminalCause;

  Map<String, Object?> toJson() => <String, Object?>{
    'stepId': stepId,
    'state': state.name,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (terminalCause != null) 'terminalCause': terminalCause!.name,
  };

  factory ScenarioLabStepSnapshot.fromJson(Object? value) {
    final json = _executionObject(value, 'ScenarioLabStepSnapshot');
    _executionOnly(json, const <String>{
      'stepId',
      'state',
      'startedAt',
      'completedAt',
      'terminalCause',
    }, 'ScenarioLabStepSnapshot');
    return ScenarioLabStepSnapshot(
      stepId: _executionString(json, 'stepId', 'ScenarioLabStepSnapshot'),
      state: _executionEnum(
        ScenarioLabStepState.values,
        _executionString(json, 'state', 'ScenarioLabStepSnapshot'),
        'ScenarioLabStepSnapshot.state',
      ),
      startedAt: _executionOptionalTime(
        json,
        'startedAt',
        'ScenarioLabStepSnapshot',
      ),
      completedAt: _executionOptionalTime(
        json,
        'completedAt',
        'ScenarioLabStepSnapshot',
      ),
      terminalCause: _executionOptionalEnum(
        ScenarioLabStepTerminalCause.values,
        json,
        'terminalCause',
        'ScenarioLabStepSnapshot',
      ),
    );
  }
}

final class ScenarioControlResult {
  const ScenarioControlResult({
    required this.controlId,
    required this.source,
    required this.value,
  });

  final ScenarioControlId controlId;
  final ScenarioControlResultSource source;
  final ScenarioControlValue value;

  Map<String, Object?> toJson() => <String, Object?>{
    'controlId': controlId.value,
    'source': source.name,
    'value': value.toJson(),
  };

  factory ScenarioControlResult.fromJson(Object? value) {
    final json = _executionObject(value, 'ScenarioControlResult');
    _executionOnly(json, const <String>{
      'controlId',
      'source',
      'value',
    }, 'ScenarioControlResult');
    return ScenarioControlResult(
      controlId: ScenarioControlId(
        _executionString(json, 'controlId', 'ScenarioControlResult'),
      ),
      source: _executionEnum(
        ScenarioControlResultSource.values,
        _executionString(json, 'source', 'ScenarioControlResult'),
        'ScenarioControlResult.source',
      ),
      value: ScenarioControlValue.fromJson(json['value']),
    );
  }
}

final class ScenarioEvidenceArtifactResult {
  const ScenarioEvidenceArtifactResult({
    required this.artifactDigest,
    required this.provenanceDigest,
    required this.classification,
  });

  final Digest artifactDigest;
  final Digest provenanceDigest;
  final ArtifactClassification classification;

  Map<String, Object?> toJson() => <String, Object?>{
    'artifactDigest': artifactDigest.value,
    'provenanceDigest': provenanceDigest.value,
    'classification': classification.name,
  };

  factory ScenarioEvidenceArtifactResult.fromJson(Object? value) {
    final json = _executionObject(value, 'ScenarioEvidenceArtifactResult');
    _executionOnly(json, const <String>{
      'artifactDigest',
      'provenanceDigest',
      'classification',
    }, 'ScenarioEvidenceArtifactResult');
    return ScenarioEvidenceArtifactResult(
      artifactDigest: Digest(
        _executionString(
          json,
          'artifactDigest',
          'ScenarioEvidenceArtifactResult',
        ),
      ),
      provenanceDigest: Digest(
        _executionString(
          json,
          'provenanceDigest',
          'ScenarioEvidenceArtifactResult',
        ),
      ),
      classification: _executionEnum(
        ArtifactClassification.values,
        _executionString(
          json,
          'classification',
          'ScenarioEvidenceArtifactResult',
        ),
        'ScenarioEvidenceArtifactResult.classification',
      ),
    );
  }
}

final class RequiredEvidenceRunResult {
  RequiredEvidenceRunResult({
    required this.requiredEvidenceId,
    required this.providerId,
    required this.fidelity,
    required this.variantId,
    required this.freshness,
    required this.state,
    this.evidenceDigest,
    Iterable<ScenarioEvidenceArtifactResult> artifacts =
        const <ScenarioEvidenceArtifactResult>[],
    this.failure,
  }) : artifacts = _executionSorted(
         artifacts,
         (item) => item.artifactDigest.value,
         'RequiredEvidenceRunResult.artifacts',
         maxItems: 64,
       ) {
    final hasOutput = evidenceDigest != null || this.artifacts.isNotEmpty;
    switch (state) {
      case RequiredEvidenceResultState.collected:
        if (evidenceDigest == null ||
            this.artifacts.isEmpty ||
            freshness != EvidenceFreshness.fresh ||
            failure != null) {
          throw ArgumentError(
            'Collected RequiredEvidence requires fresh typed artifacts',
          );
        }
      case RequiredEvidenceResultState.failed:
        if (hasOutput ||
            failure == null ||
            freshness == EvidenceFreshness.fresh) {
          throw ArgumentError('Failed RequiredEvidence has invalid fields');
        }
      case RequiredEvidenceResultState.pending ||
          RequiredEvidenceResultState.missing ||
          RequiredEvidenceResultState.unsupported ||
          RequiredEvidenceResultState.policyDenied ||
          RequiredEvidenceResultState.cancelled:
        if (hasOutput ||
            failure != null ||
            freshness == EvidenceFreshness.fresh) {
          throw ArgumentError(
            'Non-collected RequiredEvidence cannot advertise output',
          );
        }
    }
  }

  final RequiredEvidenceId requiredEvidenceId;
  final ModuleId providerId;
  final RuntimeFidelity fidelity;
  final VariantId variantId;
  final EvidenceFreshness freshness;
  final RequiredEvidenceResultState state;
  final Digest? evidenceDigest;
  final List<ScenarioEvidenceArtifactResult> artifacts;
  final ScenarioLabFailure? failure;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'requiredEvidenceId': requiredEvidenceId.value,
    'providerId': providerId.value,
    'fidelity': fidelity.name,
    'variantId': variantId.value,
    'freshness': freshness.name,
    'state': state.name,
    if (evidenceDigest != null) 'evidenceDigest': evidenceDigest!.value,
    'artifacts': artifacts.map((item) => item.toJson()).toList(),
    if (failure != null) 'failure': failure!.toJson(),
    if (includeDigest) 'digest': digest.value,
  };

  factory RequiredEvidenceRunResult.fromJson(Object? value) {
    final json = _executionObject(value, 'RequiredEvidenceRunResult');
    _executionOnly(json, const <String>{
      'requiredEvidenceId',
      'providerId',
      'fidelity',
      'variantId',
      'freshness',
      'state',
      'evidenceDigest',
      'artifacts',
      'failure',
      'digest',
    }, 'RequiredEvidenceRunResult');
    final result = RequiredEvidenceRunResult(
      requiredEvidenceId: RequiredEvidenceId(
        _executionString(
          json,
          'requiredEvidenceId',
          'RequiredEvidenceRunResult',
        ),
      ),
      providerId: ModuleId(
        _executionString(json, 'providerId', 'RequiredEvidenceRunResult'),
      ),
      fidelity: _executionEnum(
        RuntimeFidelity.values,
        _executionString(json, 'fidelity', 'RequiredEvidenceRunResult'),
        'RequiredEvidenceRunResult.fidelity',
      ),
      variantId: VariantId(
        _executionString(json, 'variantId', 'RequiredEvidenceRunResult'),
      ),
      freshness: _executionEnum(
        EvidenceFreshness.values,
        _executionString(json, 'freshness', 'RequiredEvidenceRunResult'),
        'RequiredEvidenceRunResult.freshness',
      ),
      state: _executionEnum(
        RequiredEvidenceResultState.values,
        _executionString(json, 'state', 'RequiredEvidenceRunResult'),
        'RequiredEvidenceRunResult.state',
      ),
      evidenceDigest: _executionOptionalDigest(
        json,
        'evidenceDigest',
        'RequiredEvidenceRunResult',
      ),
      artifacts: _executionList(
        json,
        'artifacts',
        'RequiredEvidenceRunResult',
        maxItems: 64,
      ).map(ScenarioEvidenceArtifactResult.fromJson),
      failure: json.containsKey('failure')
          ? ScenarioLabFailure.fromJson(json['failure'])
          : null,
    );
    _executionVerifyDigest(json, result.digest, 'RequiredEvidenceRunResult');
    return result;
  }
}

final class AutomatedAcceptanceResult {
  AutomatedAcceptanceResult({
    required this.criterionId,
    required this.verificationState,
    this.failure,
  }) {
    if ((verificationState == VerificationState.error) != (failure != null)) {
      throw ArgumentError(
        'Automated acceptance failure is present exactly for error state',
      );
    }
  }

  final AutomatedAcceptanceCriterionId criterionId;
  final VerificationState verificationState;
  final ScenarioLabFailure? failure;

  Map<String, Object?> toJson() => <String, Object?>{
    'criterionId': criterionId.value,
    'verificationState': verificationState.name,
    if (failure != null) 'failure': failure!.toJson(),
  };

  factory AutomatedAcceptanceResult.fromJson(Object? value) {
    final json = _executionObject(value, 'AutomatedAcceptanceResult');
    _executionOnly(json, const <String>{
      'criterionId',
      'verificationState',
      'failure',
    }, 'AutomatedAcceptanceResult');
    return AutomatedAcceptanceResult(
      criterionId: AutomatedAcceptanceCriterionId(
        _executionString(json, 'criterionId', 'AutomatedAcceptanceResult'),
      ),
      verificationState: _executionEnum(
        VerificationState.values,
        _executionString(
          json,
          'verificationState',
          'AutomatedAcceptanceResult',
        ),
        'AutomatedAcceptanceResult.verificationState',
      ),
      failure: json.containsKey('failure')
          ? ScenarioLabFailure.fromJson(json['failure'])
          : null,
    );
  }
}

sealed class ScenarioComparisonResult {
  ScenarioComparisonResult({
    required this.bindingId,
    required this.requiredEvidenceId,
    required this.baselineDigest,
    required this.candidateDigest,
    required this.policyDigest,
    required this.verificationState,
    this.failure,
  }) {
    if ((verificationState == VerificationState.error) != (failure != null)) {
      throw ArgumentError(
        'Comparison failure is present exactly for error state',
      );
    }
  }

  final ScenarioComparisonBindingId bindingId;
  final RequiredEvidenceId requiredEvidenceId;
  final Digest baselineDigest;
  final Digest candidateDigest;
  final Digest policyDigest;
  final VerificationState verificationState;
  final ScenarioLabFailure? failure;

  ScenarioComparisonResultKind get resultKind;

  Digest get digest;

  Map<String, Object?> toJson({bool includeDigest = true});

  factory ScenarioComparisonResult.fromJson(Object? value) {
    final json = _executionObject(value, 'ScenarioComparisonResult');
    final kind = _executionEnum(
      ScenarioComparisonResultKind.values,
      _executionString(json, 'resultKind', 'ScenarioComparisonResult'),
      'ScenarioComparisonResult.resultKind',
    );
    return switch (kind) {
      ScenarioComparisonResultKind.visual =>
        VisualScenarioComparisonResult.fromJson(json),
      ScenarioComparisonResultKind.semantic =>
        SemanticScenarioComparisonResult.fromJson(json),
    };
  }

  Map<String, Object?> commonJson() => <String, Object?>{
    'resultKind': resultKind.name,
    'bindingId': bindingId.value,
    'requiredEvidenceId': requiredEvidenceId.value,
    'baselineDigest': baselineDigest.value,
    'candidateDigest': candidateDigest.value,
    'policyDigest': policyDigest.value,
    'verificationState': verificationState.name,
    if (failure != null) 'failure': failure!.toJson(),
  };
}

final class VisualScenarioComparisonResult extends ScenarioComparisonResult {
  VisualScenarioComparisonResult({
    required super.bindingId,
    required super.requiredEvidenceId,
    required super.baselineDigest,
    required super.candidateDigest,
    required super.policyDigest,
    required super.verificationState,
    super.failure,
    this.comparedPixels,
    this.changedPixels,
    this.maxChannelDeltaObserved,
  }) {
    final measured = <Object?>[
      comparedPixels,
      changedPixels,
      maxChannelDeltaObserved,
    ];
    final requiresMetrics = const <VerificationState>{
      VerificationState.passed,
      VerificationState.failed,
    }.contains(verificationState);
    if (requiresMetrics != measured.every((value) => value != null) ||
        (!requiresMetrics && measured.any((value) => value != null))) {
      throw ArgumentError('Visual comparison metric presence is invalid');
    }
    if (requiresMetrics &&
        (comparedPixels! < 1 ||
            comparedPixels! > 1000000000 ||
            changedPixels! < 0 ||
            changedPixels! > comparedPixels! ||
            maxChannelDeltaObserved! < 0 ||
            maxChannelDeltaObserved! > 255)) {
      throw ArgumentError('Visual comparison metrics are out of bounds');
    }
  }

  final int? comparedPixels;
  final int? changedPixels;
  final int? maxChannelDeltaObserved;

  @override
  ScenarioComparisonResultKind get resultKind =>
      ScenarioComparisonResultKind.visual;

  @override
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    ...commonJson(),
    if (comparedPixels != null) 'comparedPixels': comparedPixels,
    if (changedPixels != null) 'changedPixels': changedPixels,
    if (maxChannelDeltaObserved != null)
      'maxChannelDeltaObserved': maxChannelDeltaObserved,
    if (includeDigest) 'digest': digest.value,
  };

  factory VisualScenarioComparisonResult.fromJson(Object? value) {
    final json = _executionObject(value, 'VisualScenarioComparisonResult');
    _comparisonOnly(json, const <String>{
      'comparedPixels',
      'changedPixels',
      'maxChannelDeltaObserved',
    }, 'VisualScenarioComparisonResult');
    if (json['resultKind'] != ScenarioComparisonResultKind.visual.name) {
      throw const FormatException('Invalid visual comparison result kind');
    }
    final result = VisualScenarioComparisonResult(
      bindingId: ScenarioComparisonBindingId(
        _executionString(json, 'bindingId', 'VisualScenarioComparisonResult'),
      ),
      requiredEvidenceId: RequiredEvidenceId(
        _executionString(
          json,
          'requiredEvidenceId',
          'VisualScenarioComparisonResult',
        ),
      ),
      baselineDigest: Digest(
        _executionString(
          json,
          'baselineDigest',
          'VisualScenarioComparisonResult',
        ),
      ),
      candidateDigest: Digest(
        _executionString(
          json,
          'candidateDigest',
          'VisualScenarioComparisonResult',
        ),
      ),
      policyDigest: Digest(
        _executionString(
          json,
          'policyDigest',
          'VisualScenarioComparisonResult',
        ),
      ),
      verificationState: _executionEnum(
        VerificationState.values,
        _executionString(
          json,
          'verificationState',
          'VisualScenarioComparisonResult',
        ),
        'VisualScenarioComparisonResult.verificationState',
      ),
      failure: json.containsKey('failure')
          ? ScenarioLabFailure.fromJson(json['failure'])
          : null,
      comparedPixels: _executionOptionalInteger(
        json,
        'comparedPixels',
        'VisualScenarioComparisonResult',
      ),
      changedPixels: _executionOptionalInteger(
        json,
        'changedPixels',
        'VisualScenarioComparisonResult',
      ),
      maxChannelDeltaObserved: _executionOptionalInteger(
        json,
        'maxChannelDeltaObserved',
        'VisualScenarioComparisonResult',
      ),
    );
    _executionVerifyDigest(
      json,
      result.digest,
      'VisualScenarioComparisonResult',
    );
    return result;
  }
}

final class SemanticScenarioComparisonResult extends ScenarioComparisonResult {
  SemanticScenarioComparisonResult({
    required super.bindingId,
    required super.requiredEvidenceId,
    required super.baselineDigest,
    required super.candidateDigest,
    required super.policyDigest,
    required super.verificationState,
    super.failure,
    this.comparedNodes,
    this.changedNodes,
  }) {
    final measured = <Object?>[comparedNodes, changedNodes];
    final requiresMetrics = const <VerificationState>{
      VerificationState.passed,
      VerificationState.failed,
    }.contains(verificationState);
    if (requiresMetrics != measured.every((value) => value != null) ||
        (!requiresMetrics && measured.any((value) => value != null))) {
      throw ArgumentError('Semantic comparison metric presence is invalid');
    }
    if (requiresMetrics &&
        (comparedNodes! < 1 ||
            comparedNodes! > 1000000 ||
            changedNodes! < 0 ||
            changedNodes! > comparedNodes!)) {
      throw ArgumentError('Semantic comparison metrics are out of bounds');
    }
  }

  final int? comparedNodes;
  final int? changedNodes;

  @override
  ScenarioComparisonResultKind get resultKind =>
      ScenarioComparisonResultKind.semantic;

  @override
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  @override
  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    ...commonJson(),
    if (comparedNodes != null) 'comparedNodes': comparedNodes,
    if (changedNodes != null) 'changedNodes': changedNodes,
    if (includeDigest) 'digest': digest.value,
  };

  factory SemanticScenarioComparisonResult.fromJson(Object? value) {
    final json = _executionObject(value, 'SemanticScenarioComparisonResult');
    _comparisonOnly(json, const <String>{
      'comparedNodes',
      'changedNodes',
    }, 'SemanticScenarioComparisonResult');
    if (json['resultKind'] != ScenarioComparisonResultKind.semantic.name) {
      throw const FormatException('Invalid semantic comparison result kind');
    }
    final result = SemanticScenarioComparisonResult(
      bindingId: ScenarioComparisonBindingId(
        _executionString(json, 'bindingId', 'SemanticScenarioComparisonResult'),
      ),
      requiredEvidenceId: RequiredEvidenceId(
        _executionString(
          json,
          'requiredEvidenceId',
          'SemanticScenarioComparisonResult',
        ),
      ),
      baselineDigest: Digest(
        _executionString(
          json,
          'baselineDigest',
          'SemanticScenarioComparisonResult',
        ),
      ),
      candidateDigest: Digest(
        _executionString(
          json,
          'candidateDigest',
          'SemanticScenarioComparisonResult',
        ),
      ),
      policyDigest: Digest(
        _executionString(
          json,
          'policyDigest',
          'SemanticScenarioComparisonResult',
        ),
      ),
      verificationState: _executionEnum(
        VerificationState.values,
        _executionString(
          json,
          'verificationState',
          'SemanticScenarioComparisonResult',
        ),
        'SemanticScenarioComparisonResult.verificationState',
      ),
      failure: json.containsKey('failure')
          ? ScenarioLabFailure.fromJson(json['failure'])
          : null,
      comparedNodes: _executionOptionalInteger(
        json,
        'comparedNodes',
        'SemanticScenarioComparisonResult',
      ),
      changedNodes: _executionOptionalInteger(
        json,
        'changedNodes',
        'SemanticScenarioComparisonResult',
      ),
    );
    _executionVerifyDigest(
      json,
      result.digest,
      'SemanticScenarioComparisonResult',
    );
    return result;
  }
}

final class ScenarioLabCleanupResult {
  ScenarioLabCleanupResult({
    required this.state,
    Iterable<ScenarioControlId> resetControlIds = const <ScenarioControlId>[],
    this.failure,
  }) : resetControlIds = _executionSorted(
         resetControlIds,
         (item) => item.value,
         'ScenarioLabCleanupResult.resetControlIds',
         maxItems: 10000,
       ) {
    if ((state == ScenarioLabCleanupState.failed) != (failure != null)) {
      throw ArgumentError(
        'Cleanup failure is present exactly for failed state',
      );
    }
    if (state == ScenarioLabCleanupState.notRequired &&
        this.resetControlIds.isNotEmpty) {
      throw ArgumentError('Not-required cleanup cannot reset controls');
    }
  }

  final ScenarioLabCleanupState state;
  final List<ScenarioControlId> resetControlIds;
  final ScenarioLabFailure? failure;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'resetControlIds': resetControlIds.map((item) => item.value).toList(),
    if (failure != null) 'failure': failure!.toJson(),
  };

  factory ScenarioLabCleanupResult.fromJson(Object? value) {
    final json = _executionObject(value, 'ScenarioLabCleanupResult');
    _executionOnly(json, const <String>{
      'state',
      'resetControlIds',
      'failure',
    }, 'ScenarioLabCleanupResult');
    return ScenarioLabCleanupResult(
      state: _executionEnum(
        ScenarioLabCleanupState.values,
        _executionString(json, 'state', 'ScenarioLabCleanupResult'),
        'ScenarioLabCleanupResult.state',
      ),
      resetControlIds: _executionStringList(
        json,
        'resetControlIds',
        'ScenarioLabCleanupResult',
        maxItems: 10000,
      ).map(ScenarioControlId.new),
      failure: json.containsKey('failure')
          ? ScenarioLabFailure.fromJson(json['failure'])
          : null,
    );
  }
}

/// Immutable observation of a run. A later observation has a larger sequence
/// and a different digest; this object is never mutated in place.
final class ScenarioLabRunSnapshot {
  ScenarioLabRunSnapshot({
    required this.runId,
    required this.startRequestDigest,
    required this.contentSetDigest,
    required this.catalogDigest,
    required this.scenarioLabManifestDigest,
    required this.scenarioId,
    required this.scriptId,
    required this.sequence,
    required DateTime observedAt,
    required this.state,
    this.runtimeInputs,
    required Iterable<ScenarioLabStepSnapshot> steps,
    Iterable<ScenarioControlResult> controls = const <ScenarioControlResult>[],
    Iterable<RequiredEvidenceRunResult> requiredEvidence =
        const <RequiredEvidenceRunResult>[],
    Iterable<AutomatedAcceptanceResult> automatedAcceptance =
        const <AutomatedAcceptanceResult>[],
    Iterable<ScenarioComparisonResult> comparisons =
        const <ScenarioComparisonResult>[],
    required this.cleanup,
    this.terminalCause,
  }) : observedAt = observedAt.toUtc(),
       steps = List<ScenarioLabStepSnapshot>.unmodifiable(steps),
       controls = _executionSorted(
         controls,
         (item) => item.controlId.value,
         'ScenarioLabRunSnapshot.controls',
         maxItems: 10000,
       ),
       requiredEvidence = _executionSorted(
         requiredEvidence,
         (item) => item.requiredEvidenceId.value,
         'ScenarioLabRunSnapshot.requiredEvidence',
         maxItems: 10000,
       ),
       automatedAcceptance = _executionSorted(
         automatedAcceptance,
         (item) => item.criterionId.value,
         'ScenarioLabRunSnapshot.automatedAcceptance',
         maxItems: 10000,
       ),
       comparisons = _executionSorted(
         comparisons,
         (item) => item.bindingId.value,
         'ScenarioLabRunSnapshot.comparisons',
         maxItems: 10000,
       ) {
    if (sequence < 0 || sequence > 9007199254740991) {
      throw ArgumentError.value(sequence, 'sequence', 'must be JSON-safe');
    }
    if (this.steps.isEmpty || this.steps.length > 1000) {
      throw ArgumentError('Scenario Lab snapshot requires bounded steps');
    }
    _unique(
      this.steps.map((item) => item.stepId),
      'ScenarioLabRunSnapshot.steps',
    );
    if ((state == ScenarioLabRunState.queued) != (runtimeInputs == null)) {
      throw ArgumentError(
        'Runtime inputs are absent exactly while the run is queued',
      );
    }
    if (state.isTerminal != (terminalCause != null)) {
      throw ArgumentError(
        'Terminal cause is present exactly for terminal run state',
      );
    }
    if (state == ScenarioLabRunState.succeeded &&
        terminalCause != ScenarioLabTerminalCause.completed) {
      throw ArgumentError('Succeeded run requires completed terminal cause');
    }
    if (state == ScenarioLabRunState.failed &&
        !const <ScenarioLabTerminalCause>{
          ScenarioLabTerminalCause.acceptanceFailed,
          ScenarioLabTerminalCause.stepFailed,
          ScenarioLabTerminalCause.timedOut,
          ScenarioLabTerminalCause.adapterDisconnected,
          ScenarioLabTerminalCause.cleanupFailed,
          ScenarioLabTerminalCause.internalError,
        }.contains(terminalCause)) {
      throw ArgumentError('Failed run has an invalid terminal cause');
    }
    if (state == ScenarioLabRunState.cancelled &&
        !const <ScenarioLabTerminalCause>{
          ScenarioLabTerminalCause.cancelledByUser,
          ScenarioLabTerminalCause.hostShutdown,
          ScenarioLabTerminalCause.timedOut,
          ScenarioLabTerminalCause.adapterDisconnected,
        }.contains(terminalCause)) {
      throw ArgumentError('Cancelled run has an invalid terminal cause');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunId runId;
  final Digest startRequestDigest;
  final Digest contentSetDigest;
  final Digest catalogDigest;
  final Digest scenarioLabManifestDigest;
  final ScenarioId scenarioId;
  final ScenarioScriptId scriptId;
  final int sequence;
  final DateTime observedAt;
  final ScenarioLabRunState state;
  final ScenarioLabRuntimeInputBinding? runtimeInputs;
  final List<ScenarioLabStepSnapshot> steps;
  final List<ScenarioControlResult> controls;
  final List<RequiredEvidenceRunResult> requiredEvidence;
  final List<AutomatedAcceptanceResult> automatedAcceptance;
  final List<ScenarioComparisonResult> comparisons;
  final ScenarioLabCleanupResult cleanup;
  final ScenarioLabTerminalCause? terminalCause;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRunSnapshot',
    'runId': runId.value,
    'startRequestDigest': startRequestDigest.value,
    'contentSetDigest': contentSetDigest.value,
    'catalogDigest': catalogDigest.value,
    'scenarioLabManifestDigest': scenarioLabManifestDigest.value,
    'scenarioId': scenarioId.value,
    'scriptId': scriptId.value,
    'sequence': sequence,
    'observedAt': observedAt.toIso8601String(),
    'state': state.name,
    if (runtimeInputs != null) 'runtimeInputs': runtimeInputs!.toJson(),
    'steps': steps.map((item) => item.toJson()).toList(),
    'controls': controls.map((item) => item.toJson()).toList(),
    'requiredEvidence': requiredEvidence.map((item) => item.toJson()).toList(),
    'automatedAcceptance': automatedAcceptance
        .map((item) => item.toJson())
        .toList(),
    'comparisons': comparisons.map((item) => item.toJson()).toList(),
    'cleanup': cleanup.toJson(),
    if (terminalCause != null) 'terminalCause': terminalCause!.name,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRunSnapshot.fromJson(Object? value) {
    final json =
        _executionDocument(value, 'ScenarioLabRunSnapshot', const <String>{
          'runId',
          'startRequestDigest',
          'contentSetDigest',
          'catalogDigest',
          'scenarioLabManifestDigest',
          'scenarioId',
          'scriptId',
          'sequence',
          'observedAt',
          'state',
          'runtimeInputs',
          'steps',
          'controls',
          'requiredEvidence',
          'automatedAcceptance',
          'comparisons',
          'cleanup',
          'terminalCause',
        });
    final snapshot = ScenarioLabRunSnapshot(
      runId: ScenarioLabRunId(
        _executionString(json, 'runId', 'ScenarioLabRunSnapshot'),
      ),
      startRequestDigest: Digest(
        _executionString(json, 'startRequestDigest', 'ScenarioLabRunSnapshot'),
      ),
      contentSetDigest: Digest(
        _executionString(json, 'contentSetDigest', 'ScenarioLabRunSnapshot'),
      ),
      catalogDigest: Digest(
        _executionString(json, 'catalogDigest', 'ScenarioLabRunSnapshot'),
      ),
      scenarioLabManifestDigest: Digest(
        _executionString(
          json,
          'scenarioLabManifestDigest',
          'ScenarioLabRunSnapshot',
        ),
      ),
      scenarioId: ScenarioId(
        _executionString(json, 'scenarioId', 'ScenarioLabRunSnapshot'),
      ),
      scriptId: ScenarioScriptId(
        _executionString(json, 'scriptId', 'ScenarioLabRunSnapshot'),
      ),
      sequence: _executionInteger(json, 'sequence', 'ScenarioLabRunSnapshot'),
      observedAt: _executionTime(json, 'observedAt', 'ScenarioLabRunSnapshot'),
      state: _executionEnum(
        ScenarioLabRunState.values,
        _executionString(json, 'state', 'ScenarioLabRunSnapshot'),
        'ScenarioLabRunSnapshot.state',
      ),
      runtimeInputs: json.containsKey('runtimeInputs')
          ? ScenarioLabRuntimeInputBinding.fromJson(json['runtimeInputs'])
          : null,
      steps: _executionList(
        json,
        'steps',
        'ScenarioLabRunSnapshot',
        minItems: 1,
        maxItems: 1000,
      ).map(ScenarioLabStepSnapshot.fromJson),
      controls: _executionList(
        json,
        'controls',
        'ScenarioLabRunSnapshot',
        maxItems: 10000,
      ).map(ScenarioControlResult.fromJson),
      requiredEvidence: _executionList(
        json,
        'requiredEvidence',
        'ScenarioLabRunSnapshot',
        maxItems: 10000,
      ).map(RequiredEvidenceRunResult.fromJson),
      automatedAcceptance: _executionList(
        json,
        'automatedAcceptance',
        'ScenarioLabRunSnapshot',
        maxItems: 10000,
      ).map(AutomatedAcceptanceResult.fromJson),
      comparisons: _executionList(
        json,
        'comparisons',
        'ScenarioLabRunSnapshot',
        maxItems: 10000,
      ).map(ScenarioComparisonResult.fromJson),
      cleanup: ScenarioLabCleanupResult.fromJson(json['cleanup']),
      terminalCause: _executionOptionalEnum(
        ScenarioLabTerminalCause.values,
        json,
        'terminalCause',
        'ScenarioLabRunSnapshot',
      ),
    );
    _executionVerifyDigest(json, snapshot.digest, 'ScenarioLabRunSnapshot');
    return snapshot;
  }

  void validateAgainstStart(ScenarioLabRunStartRequest request) {
    if (startRequestDigest != request.digest ||
        contentSetDigest != request.expectedContentSetDigest ||
        scenarioLabManifestDigest !=
            request.expectedScenarioLabManifestDigest ||
        scenarioId != request.scenarioId ||
        scriptId != request.scriptId) {
      throw ArgumentError('Scenario Lab snapshot start binding mismatch');
    }
  }
}

final class ScenarioLabRunResult {
  ScenarioLabRunResult({
    required this.finalSnapshot,
    required DateTime startedAt,
    required DateTime completedAt,
    required this.verificationState,
  }) : startedAt = startedAt.toUtc(),
       completedAt = completedAt.toUtc() {
    if (!finalSnapshot.state.isTerminal ||
        this.completedAt.isBefore(this.startedAt) ||
        finalSnapshot.steps.any((step) => !step.state.isTerminal) ||
        !const <ScenarioLabCleanupState>{
          ScenarioLabCleanupState.succeeded,
          ScenarioLabCleanupState.failed,
          ScenarioLabCleanupState.notRequired,
        }.contains(finalSnapshot.cleanup.state)) {
      throw ArgumentError('Scenario Lab result requires a terminal snapshot');
    }
    final derived = deriveVerificationState(
      finalSnapshot.automatedAcceptance.map((item) => item.verificationState),
    );
    if (verificationState != derived) {
      throw ArgumentError(
        'Scenario Lab result verification state does not match acceptance',
      );
    }
    if (finalSnapshot.state == ScenarioLabRunState.succeeded &&
        (verificationState == VerificationState.failed ||
            verificationState == VerificationState.error ||
            finalSnapshot.comparisons.any(
              (item) =>
                  item.verificationState == VerificationState.failed ||
                  item.verificationState == VerificationState.error,
            ))) {
      throw ArgumentError('Succeeded run cannot contain failed verification');
    }
    if ((finalSnapshot.cleanup.state == ScenarioLabCleanupState.failed) !=
        (finalSnapshot.terminalCause ==
            ScenarioLabTerminalCause.cleanupFailed)) {
      throw ArgumentError('Cleanup failure must be the run terminal cause');
    }
    final evidenceIds = finalSnapshot.requiredEvidence
        .map((item) => item.requiredEvidenceId)
        .toSet();
    if (finalSnapshot.comparisons.any(
      (comparison) => !evidenceIds.contains(comparison.requiredEvidenceId),
    )) {
      throw ArgumentError('Comparison result has no RequiredEvidence result');
    }
  }

  static const int schemaVersion = 1;
  final ScenarioLabRunSnapshot finalSnapshot;
  final DateTime startedAt;
  final DateTime completedAt;
  final VerificationState verificationState;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioLabRunResult',
    'finalSnapshot': finalSnapshot.toJson(),
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'verificationState': verificationState.name,
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioLabRunResult.fromJson(Object? value) {
    final json = _executionDocument(
      value,
      'ScenarioLabRunResult',
      const <String>{
        'finalSnapshot',
        'startedAt',
        'completedAt',
        'verificationState',
      },
    );
    final result = ScenarioLabRunResult(
      finalSnapshot: ScenarioLabRunSnapshot.fromJson(json['finalSnapshot']),
      startedAt: _executionTime(json, 'startedAt', 'ScenarioLabRunResult'),
      completedAt: _executionTime(json, 'completedAt', 'ScenarioLabRunResult'),
      verificationState: _executionEnum(
        VerificationState.values,
        _executionString(json, 'verificationState', 'ScenarioLabRunResult'),
        'ScenarioLabRunResult.verificationState',
      ),
    );
    _executionVerifyDigest(json, result.digest, 'ScenarioLabRunResult');
    return result;
  }
}

VerificationState deriveVerificationState(Iterable<VerificationState> states) {
  final values = states.toList(growable: false);
  if (values.any((state) => state == VerificationState.error)) {
    return VerificationState.error;
  }
  if (values.any((state) => state == VerificationState.failed)) {
    return VerificationState.failed;
  }
  if (values.isNotEmpty &&
      values.every((state) => state == VerificationState.passed)) {
    return VerificationState.passed;
  }
  return VerificationState.notRun;
}

/// Projection only. Supersession never rewrites a HumanDecisionRecord.
final class HumanDecisionProjection {
  HumanDecisionProjection({
    required this.state,
    this.decisionDigest,
    this.supersededByDecisionDigest,
  }) {
    switch (state) {
      case HumanDecisionState.unreviewed:
        if (decisionDigest != null || supersededByDecisionDigest != null) {
          throw ArgumentError('Unreviewed projection cannot reference records');
        }
      case HumanDecisionState.approved || HumanDecisionState.rejected:
        if (decisionDigest == null || supersededByDecisionDigest != null) {
          throw ArgumentError('Current decision projection is invalid');
        }
      case HumanDecisionState.superseded:
        if (decisionDigest == null ||
            supersededByDecisionDigest == null ||
            decisionDigest == supersededByDecisionDigest) {
          throw ArgumentError('Superseded decision projection is invalid');
        }
    }
  }

  final HumanDecisionState state;
  final Digest? decisionDigest;
  final Digest? supersededByDecisionDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    if (decisionDigest != null) 'decisionDigest': decisionDigest!.value,
    if (supersededByDecisionDigest != null)
      'supersededByDecisionDigest': supersededByDecisionDigest!.value,
  };

  factory HumanDecisionProjection.fromJson(Object? value) {
    final json = _executionObject(value, 'HumanDecisionProjection');
    _executionOnly(json, const <String>{
      'state',
      'decisionDigest',
      'supersededByDecisionDigest',
    }, 'HumanDecisionProjection');
    return HumanDecisionProjection(
      state: _executionEnum(
        HumanDecisionState.values,
        _executionString(json, 'state', 'HumanDecisionProjection'),
        'HumanDecisionProjection.state',
      ),
      decisionDigest: _executionOptionalDigest(
        json,
        'decisionDigest',
        'HumanDecisionProjection',
      ),
      supersededByDecisionDigest: _executionOptionalDigest(
        json,
        'supersededByDecisionDigest',
        'HumanDecisionProjection',
      ),
    );
  }
}

final class RequiredEvidenceVerification {
  const RequiredEvidenceVerification({
    required this.requiredEvidenceId,
    required this.resultDigest,
    required this.verificationState,
  });

  final RequiredEvidenceId requiredEvidenceId;
  final Digest resultDigest;
  final VerificationState verificationState;

  Map<String, Object?> toJson() => <String, Object?>{
    'requiredEvidenceId': requiredEvidenceId.value,
    'resultDigest': resultDigest.value,
    'verificationState': verificationState.name,
  };

  factory RequiredEvidenceVerification.fromJson(Object? value) {
    final json = _executionObject(value, 'RequiredEvidenceVerification');
    _executionOnly(json, const <String>{
      'requiredEvidenceId',
      'resultDigest',
      'verificationState',
    }, 'RequiredEvidenceVerification');
    return RequiredEvidenceVerification(
      requiredEvidenceId: RequiredEvidenceId(
        _executionString(
          json,
          'requiredEvidenceId',
          'RequiredEvidenceVerification',
        ),
      ),
      resultDigest: Digest(
        _executionString(json, 'resultDigest', 'RequiredEvidenceVerification'),
      ),
      verificationState: _executionEnum(
        VerificationState.values,
        _executionString(
          json,
          'verificationState',
          'RequiredEvidenceVerification',
        ),
        'RequiredEvidenceVerification.verificationState',
      ),
    );
  }
}

final class ScenarioQualitySnapshot {
  ScenarioQualitySnapshot({
    required this.subjectDigest,
    required this.runId,
    required this.scenarioId,
    required this.verificationState,
    required this.humanDecision,
    Iterable<RequiredEvidenceVerification> requiredEvidence =
        const <RequiredEvidenceVerification>[],
    Iterable<Digest> comparisonResultDigests = const <Digest>[],
  }) : requiredEvidence = _executionSorted(
         requiredEvidence,
         (item) => item.requiredEvidenceId.value,
         'ScenarioQualitySnapshot.requiredEvidence',
         maxItems: 10000,
       ),
       comparisonResultDigests = _executionSorted(
         comparisonResultDigests,
         (item) => item.value,
         'ScenarioQualitySnapshot.comparisonResultDigests',
         maxItems: 10000,
       ) {
    _executionId(scenarioId.value, 'ScenarioQualitySnapshot.scenarioId');
  }

  static const int schemaVersion = 1;
  final Digest subjectDigest;
  final ScenarioLabRunId runId;
  final ScenarioId scenarioId;
  final VerificationState verificationState;
  final HumanDecisionProjection humanDecision;
  final List<RequiredEvidenceVerification> requiredEvidence;
  final List<Digest> comparisonResultDigests;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioQualitySnapshot',
    'subjectDigest': subjectDigest.value,
    'runId': runId.value,
    'scenarioId': scenarioId.value,
    'verificationState': verificationState.name,
    'humanDecision': humanDecision.toJson(),
    'requiredEvidence': requiredEvidence.map((item) => item.toJson()).toList(),
    'comparisonResultDigests': comparisonResultDigests
        .map((item) => item.value)
        .toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioQualitySnapshot.fromJson(Object? value) {
    final json =
        _executionDocument(value, 'ScenarioQualitySnapshot', const <String>{
          'subjectDigest',
          'runId',
          'scenarioId',
          'verificationState',
          'humanDecision',
          'requiredEvidence',
          'comparisonResultDigests',
        });
    final snapshot = ScenarioQualitySnapshot(
      subjectDigest: Digest(
        _executionString(json, 'subjectDigest', 'ScenarioQualitySnapshot'),
      ),
      runId: ScenarioLabRunId(
        _executionString(json, 'runId', 'ScenarioQualitySnapshot'),
      ),
      scenarioId: ScenarioId(
        _executionString(json, 'scenarioId', 'ScenarioQualitySnapshot'),
      ),
      verificationState: _executionEnum(
        VerificationState.values,
        _executionString(json, 'verificationState', 'ScenarioQualitySnapshot'),
        'ScenarioQualitySnapshot.verificationState',
      ),
      humanDecision: HumanDecisionProjection.fromJson(json['humanDecision']),
      requiredEvidence: _executionList(
        json,
        'requiredEvidence',
        'ScenarioQualitySnapshot',
        maxItems: 10000,
      ).map(RequiredEvidenceVerification.fromJson),
      comparisonResultDigests: _executionStringList(
        json,
        'comparisonResultDigests',
        'ScenarioQualitySnapshot',
        maxItems: 10000,
      ).map(Digest.new),
    );
    _executionVerifyDigest(json, snapshot.digest, 'ScenarioQualitySnapshot');
    return snapshot;
  }

  void validateAgainstResult(ScenarioLabRunResult result) {
    if (subjectDigest != result.digest ||
        runId != result.finalSnapshot.runId ||
        scenarioId != result.finalSnapshot.scenarioId ||
        verificationState != result.verificationState) {
      throw ArgumentError('Quality snapshot does not bind its run result');
    }
    final actualComparisons = result.finalSnapshot.comparisons
        .map((item) => item.digest)
        .toSet();
    if (comparisonResultDigests.length != actualComparisons.length ||
        comparisonResultDigests.any(
          (digest) => !actualComparisons.contains(digest),
        )) {
      throw ArgumentError('Quality snapshot references an unknown comparison');
    }
    final actualEvidence = <RequiredEvidenceId, Digest>{
      for (final item in result.finalSnapshot.requiredEvidence)
        item.requiredEvidenceId: item.digest,
    };
    if (requiredEvidence.length != actualEvidence.length ||
        requiredEvidence.any(
          (item) =>
              actualEvidence[item.requiredEvidenceId] != item.resultDigest,
        )) {
      throw ArgumentError(
        'Quality snapshot does not bind all RequiredEvidence results',
      );
    }
  }
}

/// Immutable, append-only approval/rejection record.
///
/// `unreviewed` and `superseded` exist only in [HumanDecisionProjection].
final class HumanDecisionRecord {
  HumanDecisionRecord({
    required this.id,
    required this.subjectDigest,
    required this.principalId,
    required this.decision,
    required DateTime decidedAt,
    this.supersedesDecisionDigest,
  }) : decidedAt = decidedAt.toUtc();

  static const int schemaVersion = 1;
  final HumanDecisionRecordId id;
  final Digest subjectDigest;
  final ScenarioQualityPrincipalId principalId;
  final HumanDecision decision;
  final DateTime decidedAt;
  final Digest? supersedesDecisionDigest;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'HumanDecisionRecord',
    'id': id.value,
    'subjectDigest': subjectDigest.value,
    'principalId': principalId.value,
    'decision': decision.name,
    'decidedAt': decidedAt.toIso8601String(),
    if (supersedesDecisionDigest != null)
      'supersedesDecisionDigest': supersedesDecisionDigest!.value,
    if (includeDigest) 'digest': digest.value,
  };

  factory HumanDecisionRecord.fromJson(Object? value) {
    final json =
        _executionDocument(value, 'HumanDecisionRecord', const <String>{
          'id',
          'subjectDigest',
          'principalId',
          'decision',
          'decidedAt',
          'supersedesDecisionDigest',
        });
    final record = HumanDecisionRecord(
      id: HumanDecisionRecordId(
        _executionString(json, 'id', 'HumanDecisionRecord'),
      ),
      subjectDigest: Digest(
        _executionString(json, 'subjectDigest', 'HumanDecisionRecord'),
      ),
      principalId: ScenarioQualityPrincipalId(
        _executionString(json, 'principalId', 'HumanDecisionRecord'),
      ),
      decision: _executionEnum(
        HumanDecision.values,
        _executionString(json, 'decision', 'HumanDecisionRecord'),
        'HumanDecisionRecord.decision',
      ),
      decidedAt: _executionTime(json, 'decidedAt', 'HumanDecisionRecord'),
      supersedesDecisionDigest: _executionOptionalDigest(
        json,
        'supersedesDecisionDigest',
        'HumanDecisionRecord',
      ),
    );
    _executionVerifyDigest(json, record.digest, 'HumanDecisionRecord');
    return record;
  }

  void validateSupersedes(HumanDecisionRecord previous) {
    if (supersedesDecisionDigest != previous.digest ||
        id == previous.id ||
        subjectDigest != previous.subjectDigest ||
        !decidedAt.isAfter(previous.decidedAt)) {
      throw ArgumentError('Human decision supersession chain is invalid');
    }
  }
}

void _comparisonOnly(
  Map<String, Object?> json,
  Set<String> metrics,
  String path,
) {
  _executionOnly(json, <String>{
    'resultKind',
    'bindingId',
    'requiredEvidenceId',
    'baselineDigest',
    'candidateDigest',
    'policyDigest',
    'verificationState',
    'failure',
    ...metrics,
    'digest',
  }, path);
}

Map<String, Object?> _executionDocument(
  Object? value,
  String kind,
  Set<String> fields,
) {
  final json = _executionObject(value, kind);
  _executionOnly(json, <String>{
    'schemaVersion',
    'kind',
    ...fields,
    'digest',
  }, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind has invalid schemaVersion or kind');
  }
  return json;
}

Map<String, Object?> _executionObject(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$path must be an object');
  }
  final output = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings');
    }
    output[entry.key! as String] = entry.value;
  }
  return output;
}

void _executionOnly(
  Map<String, Object?> json,
  Set<String> allowed,
  String path,
) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _executionString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 256,
}) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('$path.$key must be a bounded string');
  }
  return value;
}

String? _executionOptionalString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 512,
}) {
  if (!json.containsKey(key)) return null;
  return _executionString(json, key, path, maxLength: maxLength);
}

int _executionInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

int? _executionOptionalInteger(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return _executionInteger(json, key, path);
}

List<Object?> _executionList(
  Map<String, Object?> json,
  String key,
  String path, {
  int minItems = 0,
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?> ||
      value.length < minItems ||
      value.length > maxItems) {
    throw FormatException('$path.$key must be a bounded list');
  }
  return value;
}

List<String> _executionStringList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final values = _executionList(json, key, path, maxItems: maxItems);
  if (values.any((value) => value is! String)) {
    throw FormatException('$path.$key must contain strings');
  }
  return values.cast<String>();
}

T _executionEnum<T extends Enum>(Iterable<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has unknown value $name');
}

T? _executionOptionalEnum<T extends Enum>(
  Iterable<T> values,
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return _executionEnum(
    values,
    _executionString(json, key, path),
    '$path.$key',
  );
}

Digest? _executionOptionalDigest(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return Digest(_executionString(json, key, path));
}

DateTime _executionTime(Map<String, Object?> json, String key, String path) {
  final source = _executionString(json, key, path);
  final parsed = DateTime.tryParse(source);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != source) {
    throw FormatException('$path.$key must be a canonical UTC date-time');
  }
  return parsed;
}

DateTime? _executionOptionalTime(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return _executionTime(json, key, path);
}

List<T> _executionSorted<T>(
  Iterable<T> values,
  String Function(T) keyOf,
  String path, {
  required int maxItems,
}) {
  final result = List<T>.of(values)
    ..sort((left, right) => keyOf(left).compareTo(keyOf(right)));
  if (result.length > maxItems) {
    throw ArgumentError('$path exceeds $maxItems items');
  }
  _unique(result.map(keyOf), path);
  return List<T>.unmodifiable(result);
}

void _unique(Iterable<String> values, String path) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      throw ArgumentError('$path contains duplicate $value');
    }
  }
}

void _executionVerifyDigest(
  Map<String, Object?> json,
  Digest actual,
  String path,
) {
  if (Digest(_executionString(json, 'digest', path)) != actual) {
    throw FormatException('$path.digest mismatch');
  }
}

void _executionId(String value, String path) {
  if (value.length > 256) throw FormatException('$path ID is too long');
  OpaqueId.validate(value, path);
}
