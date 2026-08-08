import 'package:experience_contracts/experience_contracts.dart';

import '../evidence/evidence_comparison_service.dart';
import 'scenario_lab_execution_ports.dart';

/// Resolves an exact comparison descriptor from Host-owned storage.
///
/// A resolver must verify both digests and classification against its typed
/// provenance before returning bytes. `null` means that the exact input is not
/// available; selecting another Evidence or artifact is forbidden.
typedef ScenarioLabComparisonArtifactResolver =
    Future<ScenarioLabResolvedComparisonArtifact?> Function({
      required ScenarioLabRunId runId,
      required ScenarioLabComparisonArtifactDescriptor descriptor,
      required ScenarioLabCancellationSignal cancellation,
    });

/// Deterministic comparison adapter over Host-resolved immutable bytes.
final class ScenarioLabEvidenceComparisonPort
    implements ScenarioLabComparisonPort {
  const ScenarioLabEvidenceComparisonPort({
    required this.resolveArtifact,
    this.comparisonService = const EvidenceComparisonService(),
  });

  final ScenarioLabComparisonArtifactResolver resolveArtifact;
  final EvidenceComparisonService comparisonService;

  @override
  Future<ScenarioLabVisualComparisonMetrics> compareVisual({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
    required VisualComparisonPolicy policy,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    final inputs = await _resolvePair(
      runId: runId,
      baseline: baseline,
      candidate: candidate,
      cancellation: cancellation,
    );
    final EvidenceComparisonReport report;
    try {
      report = comparisonService.compareVisual(
        expected: inputs.$1.bytes,
        actual: inputs.$2.bytes,
        policy: policy,
      );
    } on FormatException {
      throw const ScenarioLabComparisonInputInvalid();
    }
    if (report.comparisonKind != 'visual' ||
        report.expectedDigest != baseline.artifactDigest ||
        report.actualDigest != candidate.artifactDigest ||
        report.policyDigest != policy.digest) {
      throw const ScenarioLabComparisonInputInvalid();
    }
    final maxDelta = report.metrics['maxObservedChannelDelta'];
    if (maxDelta is! int) {
      throw const ScenarioLabComparisonInputInvalid();
    }
    return ScenarioLabVisualComparisonMetrics(
      passed: report.passed,
      comparedPixels: report.comparedUnits,
      changedPixels: report.changedUnits,
      maxChannelDeltaObserved: maxDelta,
    );
  }

  @override
  Future<ScenarioLabSemanticComparisonMetrics> compareSemantic({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
    required SemanticComparisonPolicy policy,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    final inputs = await _resolvePair(
      runId: runId,
      baseline: baseline,
      candidate: candidate,
      cancellation: cancellation,
    );
    final EvidenceComparisonReport report;
    try {
      report = comparisonService.compareSemantic(
        expected: inputs.$1.bytes,
        actual: inputs.$2.bytes,
        policy: policy,
      );
    } on FormatException {
      throw const ScenarioLabComparisonInputInvalid();
    }
    if (report.comparisonKind != 'semantic' ||
        report.expectedDigest != baseline.artifactDigest ||
        report.actualDigest != candidate.artifactDigest ||
        report.policyDigest != policy.digest ||
        report.comparedUnits < 1) {
      throw const ScenarioLabComparisonInputInvalid();
    }
    return ScenarioLabSemanticComparisonMetrics(
      passed: report.passed,
      comparedNodes: report.comparedUnits,
      changedNodes: report.changedUnits,
    );
  }

  Future<
    (
      ScenarioLabResolvedComparisonArtifact,
      ScenarioLabResolvedComparisonArtifact,
    )
  >
  _resolvePair({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    final resolvedBaseline = await _resolve(
      runId: runId,
      descriptor: baseline,
      cancellation: cancellation,
    );
    final resolvedCandidate = await _resolve(
      runId: runId,
      descriptor: candidate,
      cancellation: cancellation,
    );
    return (resolvedBaseline, resolvedCandidate);
  }

  Future<ScenarioLabResolvedComparisonArtifact> _resolve({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor descriptor,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) {
      throw const ScenarioLabComparisonCancelled();
    }
    final ScenarioLabResolvedComparisonArtifact? resolved;
    try {
      resolved = await resolveArtifact(
        runId: runId,
        descriptor: descriptor,
        cancellation: cancellation,
      );
    } on ScenarioLabComparisonInputMissing {
      rethrow;
    } on ScenarioLabComparisonInputInvalid {
      rethrow;
    } on ScenarioLabComparisonPolicyDenied {
      rethrow;
    } on ScenarioLabComparisonUnsupported {
      rethrow;
    } on ScenarioLabComparisonCancelled {
      rethrow;
    } on FormatException {
      throw const ScenarioLabComparisonInputInvalid();
    }
    if (cancellation.isCancelled) {
      throw const ScenarioLabComparisonCancelled();
    }
    if (resolved == null) {
      throw const ScenarioLabComparisonInputMissing();
    }
    if (!resolved.descriptor.hasSameIdentity(descriptor)) {
      throw const ScenarioLabComparisonInputInvalid();
    }
    return resolved;
  }
}
