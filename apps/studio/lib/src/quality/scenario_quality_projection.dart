import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/lab/scenario_lab_projection.dart';

enum ScenarioQualityState {
  passing,
  changed,
  failing,
  stale,
  unverified,
  missing,
  unsupported,
  policyDenied,
}

enum ScenarioQualityFindingSource {
  run,
  requiredEvidence,
  automatedAcceptance,
  comparison,
}

final class ScenarioQualityFinding {
  const ScenarioQualityFinding({
    required this.state,
    required this.source,
    required this.sourceId,
    required this.detail,
  });

  final ScenarioQualityState state;
  final ScenarioQualityFindingSource source;
  final String sourceId;
  final String detail;
}

final class ScenarioQualityProjection {
  const ScenarioQualityProjection._({
    required this.lab,
    required this.states,
    required this.findings,
    required this.verificationState,
    required this.humanDecisionState,
  });

  final ScenarioLabProjection lab;
  final List<ScenarioQualityState> states;
  final List<ScenarioQualityFinding> findings;
  final VerificationState? verificationState;
  final HumanDecisionState? humanDecisionState;

  bool hasState(ScenarioQualityState state) => states.contains(state);
}

final class ScenarioQualityResolver {
  const ScenarioQualityResolver();

  ScenarioQualityProjection resolve({
    required CatalogManifest catalog,
    required ScenarioLabManifest manifest,
    required ScenarioId scenarioId,
    required ScenarioScriptId scriptId,
    ScenarioLabRunSnapshot? runSnapshot,
    ScenarioLabRunResult? runResult,
    ScenarioQualitySnapshot? qualitySnapshot,
    Digest? currentContentSetDigest,
  }) {
    final lab = const ScenarioLabResolver().resolve(
      catalog: catalog,
      manifest: manifest,
      scenarioId: scenarioId,
      scriptId: scriptId,
      runSnapshot: runSnapshot,
      runResult: runResult,
      qualitySnapshot: qualitySnapshot,
    );
    final snapshot = lab.runSnapshot;
    final verificationState =
        qualitySnapshot?.verificationState ??
        runResult?.verificationState ??
        (snapshot == null
            ? null
            : deriveVerificationState(
                snapshot.automatedAcceptance.map(
                  (item) => item.verificationState,
                ),
              ));
    final findings = <ScenarioQualityFinding>[];

    if (snapshot != null) {
      if (currentContentSetDigest != null &&
          snapshot.contentSetDigest != currentContentSetDigest) {
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.stale,
            source: ScenarioQualityFindingSource.run,
            sourceId: snapshot.runId.value,
            detail: 'content-generation-changed',
          ),
        );
      }
      _evidenceFindings(snapshot, qualitySnapshot, findings);
      _acceptanceFindings(snapshot, findings);
      _comparisonFindings(snapshot, findings);
    }

    final hasCompleteResult = runResult != null;
    final hasCompleteCoverage =
        hasCompleteResult &&
        _sameIds(
          lab.plan.requiredEvidenceIds,
          snapshot!.requiredEvidence.map((item) => item.requiredEvidenceId),
        ) &&
        _sameIds(
          lab.plan.automatedAcceptanceCriterionIds,
          snapshot.automatedAcceptance.map((item) => item.criterionId),
        ) &&
        _sameIds(
          lab.plan.comparisonBindingIds,
          snapshot.comparisons.map((item) => item.bindingId),
        );
    final verificationIsConclusive =
        verificationState == VerificationState.passed ||
        verificationState == VerificationState.failed;
    if (!hasCompleteResult ||
        !hasCompleteCoverage ||
        !verificationIsConclusive) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.unverified,
          source: ScenarioQualityFindingSource.run,
          sourceId: snapshot?.runId.value ?? scenarioId.value,
          detail: !hasCompleteResult
              ? 'terminal-result-absent'
              : !hasCompleteCoverage
              ? 'declared-results-incomplete'
              : 'verification-${verificationState?.name ?? 'absent'}',
        ),
      );
    }

    if (verificationState == VerificationState.failed) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.failing,
          source: ScenarioQualityFindingSource.run,
          sourceId: snapshot!.runId.value,
          detail: 'automated-verification-failed',
        ),
      );
    }

    final blockingStates = <ScenarioQualityState>{
      for (final finding in findings) finding.state,
    };
    if (hasCompleteResult &&
        hasCompleteCoverage &&
        verificationState == VerificationState.passed &&
        !blockingStates.contains(ScenarioQualityState.failing) &&
        !blockingStates.contains(ScenarioQualityState.stale) &&
        !blockingStates.contains(ScenarioQualityState.unverified) &&
        !blockingStates.contains(ScenarioQualityState.missing) &&
        !blockingStates.contains(ScenarioQualityState.unsupported) &&
        !blockingStates.contains(ScenarioQualityState.policyDenied)) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.passing,
          source: ScenarioQualityFindingSource.run,
          sourceId: snapshot.runId.value,
          detail: 'typed-verification-passed',
        ),
      );
    }

    final states = <ScenarioQualityState>[
      for (final state in ScenarioQualityState.values)
        if (findings.any((finding) => finding.state == state)) state,
    ];
    return ScenarioQualityProjection._(
      lab: lab,
      states: List.unmodifiable(states),
      findings: List.unmodifiable(findings),
      verificationState: verificationState,
      humanDecisionState: qualitySnapshot?.humanDecision.state,
    );
  }
}

void _evidenceFindings(
  ScenarioLabRunSnapshot snapshot,
  ScenarioQualitySnapshot? quality,
  List<ScenarioQualityFinding> findings,
) {
  final verifications = <RequiredEvidenceId, RequiredEvidenceVerification>{
    for (final item
        in quality?.requiredEvidence ?? const <RequiredEvidenceVerification>[])
      item.requiredEvidenceId: item,
  };
  for (final evidence in snapshot.requiredEvidence) {
    final id = evidence.requiredEvidenceId.value;
    if (evidence.freshness == EvidenceFreshness.stale) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.stale,
          source: ScenarioQualityFindingSource.requiredEvidence,
          sourceId: id,
          detail: 'freshness-stale',
        ),
      );
    }
    switch (evidence.state) {
      case RequiredEvidenceResultState.failed:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.failing,
            source: ScenarioQualityFindingSource.requiredEvidence,
            sourceId: id,
            detail: 'collection-failed',
          ),
        );
      case RequiredEvidenceResultState.missing:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.missing,
            source: ScenarioQualityFindingSource.requiredEvidence,
            sourceId: id,
            detail: 'result-missing',
          ),
        );
      case RequiredEvidenceResultState.unsupported:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.unsupported,
            source: ScenarioQualityFindingSource.requiredEvidence,
            sourceId: id,
            detail: 'result-unsupported',
          ),
        );
      case RequiredEvidenceResultState.policyDenied:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.policyDenied,
            source: ScenarioQualityFindingSource.requiredEvidence,
            sourceId: id,
            detail: 'result-policy-denied',
          ),
        );
      case RequiredEvidenceResultState.pending ||
          RequiredEvidenceResultState.cancelled:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.unverified,
            source: ScenarioQualityFindingSource.requiredEvidence,
            sourceId: id,
            detail: 'result-${evidence.state.name}',
          ),
        );
      case RequiredEvidenceResultState.collected:
        break;
    }
    if (evidence.freshness == EvidenceFreshness.invalid) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.unverified,
          source: ScenarioQualityFindingSource.requiredEvidence,
          sourceId: id,
          detail: 'freshness-invalid',
        ),
      );
    }
    _failureFinding(
      evidence.failure,
      source: ScenarioQualityFindingSource.requiredEvidence,
      sourceId: id,
      findings: findings,
    );
    final verification = verifications[evidence.requiredEvidenceId];
    if (verification?.verificationState == VerificationState.failed) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.failing,
          source: ScenarioQualityFindingSource.requiredEvidence,
          sourceId: id,
          detail: 'evidence-verification-failed',
        ),
      );
    } else if (verification?.verificationState == VerificationState.notRun ||
        verification?.verificationState == VerificationState.error) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.unverified,
          source: ScenarioQualityFindingSource.requiredEvidence,
          sourceId: id,
          detail:
              'evidence-verification-${verification!.verificationState.name}',
        ),
      );
    }
  }
}

void _acceptanceFindings(
  ScenarioLabRunSnapshot snapshot,
  List<ScenarioQualityFinding> findings,
) {
  for (final acceptance in snapshot.automatedAcceptance) {
    final id = acceptance.criterionId.value;
    switch (acceptance.verificationState) {
      case VerificationState.failed:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.failing,
            source: ScenarioQualityFindingSource.automatedAcceptance,
            sourceId: id,
            detail: 'criterion-failed',
          ),
        );
      case VerificationState.notRun || VerificationState.error:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.unverified,
            source: ScenarioQualityFindingSource.automatedAcceptance,
            sourceId: id,
            detail: 'criterion-${acceptance.verificationState.name}',
          ),
        );
      case VerificationState.passed:
        break;
    }
    _failureFinding(
      acceptance.failure,
      source: ScenarioQualityFindingSource.automatedAcceptance,
      sourceId: id,
      findings: findings,
    );
  }
}

void _comparisonFindings(
  ScenarioLabRunSnapshot snapshot,
  List<ScenarioQualityFinding> findings,
) {
  for (final comparison in snapshot.comparisons) {
    final id = comparison.bindingId.value;
    final changedUnits = switch (comparison) {
      VisualScenarioComparisonResult(:final changedPixels) => changedPixels,
      SemanticScenarioComparisonResult(:final changedNodes) => changedNodes,
    };
    if (changedUnits != null && changedUnits > 0) {
      findings.add(
        ScenarioQualityFinding(
          state: ScenarioQualityState.changed,
          source: ScenarioQualityFindingSource.comparison,
          sourceId: id,
          detail: 'measured-changed-units-$changedUnits',
        ),
      );
    }
    switch (comparison.verificationState) {
      case VerificationState.failed:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.failing,
            source: ScenarioQualityFindingSource.comparison,
            sourceId: id,
            detail: 'comparison-failed',
          ),
        );
      case VerificationState.notRun || VerificationState.error:
        findings.add(
          ScenarioQualityFinding(
            state: ScenarioQualityState.unverified,
            source: ScenarioQualityFindingSource.comparison,
            sourceId: id,
            detail: 'comparison-${comparison.verificationState.name}',
          ),
        );
      case VerificationState.passed:
        break;
    }
    _failureFinding(
      comparison.failure,
      source: ScenarioQualityFindingSource.comparison,
      sourceId: id,
      findings: findings,
    );
  }
}

void _failureFinding(
  ScenarioLabFailure? failure, {
  required ScenarioQualityFindingSource source,
  required String sourceId,
  required List<ScenarioQualityFinding> findings,
}) {
  final state = switch (failure?.cause) {
    ScenarioLabFailureCause.unsupported => ScenarioQualityState.unsupported,
    ScenarioLabFailureCause.policyDenied => ScenarioQualityState.policyDenied,
    _ => null,
  };
  if (state != null) {
    findings.add(
      ScenarioQualityFinding(
        state: state,
        source: source,
        sourceId: sourceId,
        detail: 'failure-${failure!.cause.name}',
      ),
    );
  }
}

bool _sameIds<T>(Iterable<T> declared, Iterable<T> observed) {
  final left = declared.toSet();
  final right = observed.toSet();
  return left.length == right.length && left.containsAll(right);
}
