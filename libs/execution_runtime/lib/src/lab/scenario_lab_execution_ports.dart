import 'package:experience_contracts/experience_contracts.dart';

/// Typed identity source owned by the Host execution boundary.
abstract interface class ScenarioLabExecutionIdentityPort {
  ScenarioLabRunId nextRunId();

  ScenarioLabCommandId nextCommandId();

  AppAdapterRelayNonce nextRelayNonce();
}

/// Read-only cancellation signal passed to side-effect ports.
abstract interface class ScenarioLabCancellationSignal {
  bool get isCancelled;

  Future<void> get whenCancelled;
}

/// Raised only by [ScenarioLabDeadlinePort] when its bounded action expires.
final class ScenarioLabDeadlineExceeded implements Exception {
  const ScenarioLabDeadlineExceeded();

  @override
  String toString() => 'ScenarioLabDeadlineExceeded';
}

/// Runs one asynchronous port call under a caller-supplied deadline.
abstract interface class ScenarioLabDeadlinePort {
  Future<T> run<T>({
    required Duration timeout,
    required Future<T> Function() action,
  });
}

/// Host-owned result of one completed capture upload.
///
/// The port must return this value only after the receipt's artifact has been
/// re-read and verified in the Host CAS and [evidence] has been persisted. The
/// App Adapter never supplies Evidence identity, provenance, classification or
/// fidelity through this boundary.
final class ScenarioLabHostEvidenceCollection {
  const ScenarioLabHostEvidenceCollection({
    required this.uploadReceipt,
    required this.evidence,
  });

  final AppAdapterCaptureReceipt uploadReceipt;
  final Evidence evidence;
}

/// Host policy rejected the collection before target-controlled bytes count.
final class ScenarioLabEvidencePolicyDenied implements Exception {
  const ScenarioLabEvidencePolicyDenied();

  @override
  String toString() => 'ScenarioLabEvidencePolicyDenied';
}

/// Host receipt, CAS or fingerprint state cannot prove the collection.
final class ScenarioLabEvidenceInvalidInput implements Exception {
  const ScenarioLabEvidenceInvalidInput();

  @override
  String toString() => 'ScenarioLabEvidenceInvalidInput';
}

/// Host authority for App Adapter capture grants and collected Evidence.
///
/// Implementations own the upload registry and CAS. They derive target origin
/// from Host-owned readiness state; no caller-provided origin is accepted by
/// this interface.
abstract interface class ScenarioLabEvidencePort {
  Future<AppAdapterRelayCaptureUploadGrant> issueCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required ScenarioLabRuntimeInputBinding runtimeInputs,
    required ScenarioLabCancellationSignal cancellation,
  });

  /// Returns `null` only when the acknowledged upload has no Host receipt.
  Future<ScenarioLabHostEvidenceCollection?> consumeCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required AppAdapterRelayCaptureUploadGrant uploadGrant,
    required ScenarioLabCancellationSignal cancellation,
  });

  /// Revokes pending grants and removes per-run receipt state.
  Future<void> cleanupRun(ScenarioLabRunId runId);
}

/// Exact Host-owned identity of one comparison artifact.
///
/// The artifact bytes are addressed independently from provenance. The
/// classification is the value already proven by the manifest or collected
/// Evidence; it is never inferred from the bytes or supplied by the target.
final class ScenarioLabComparisonArtifactDescriptor {
  const ScenarioLabComparisonArtifactDescriptor({
    required this.artifactDigest,
    required this.provenanceDigest,
    required this.classification,
  });

  final Digest artifactDigest;
  final Digest provenanceDigest;
  final ArtifactClassification classification;

  bool hasSameIdentity(ScenarioLabComparisonArtifactDescriptor other) =>
      artifactDigest == other.artifactDigest &&
      provenanceDigest == other.provenanceDigest &&
      classification == other.classification;
}

/// Bytes returned by a Host-owned resolver for an exact descriptor.
final class ScenarioLabResolvedComparisonArtifact {
  ScenarioLabResolvedComparisonArtifact({
    required this.descriptor,
    required Iterable<int> bytes,
  }) : bytes = List<int>.unmodifiable(bytes) {
    if (this.bytes.isEmpty ||
        this.bytes.length > 32 * 1024 * 1024 ||
        Digest.bytes(this.bytes) != descriptor.artifactDigest) {
      throw const FormatException(
        'Resolved comparison artifact does not match its digest',
      );
    }
  }

  final ScenarioLabComparisonArtifactDescriptor descriptor;
  final List<int> bytes;
}

/// Closed metrics returned by the comparison port to the coordinator.
sealed class ScenarioLabComparisonMetrics {
  const ScenarioLabComparisonMetrics();

  bool get passed;
}

final class ScenarioLabVisualComparisonMetrics
    extends ScenarioLabComparisonMetrics {
  ScenarioLabVisualComparisonMetrics({
    required this.passed,
    required this.comparedPixels,
    required this.changedPixels,
    required this.maxChannelDeltaObserved,
  }) {
    if (comparedPixels < 1 ||
        comparedPixels > 1000000000 ||
        changedPixels < 0 ||
        changedPixels > comparedPixels ||
        maxChannelDeltaObserved < 0 ||
        maxChannelDeltaObserved > 255) {
      throw ArgumentError('Visual comparison metrics are out of bounds');
    }
  }

  @override
  final bool passed;
  final int comparedPixels;
  final int changedPixels;
  final int maxChannelDeltaObserved;
}

final class ScenarioLabSemanticComparisonMetrics
    extends ScenarioLabComparisonMetrics {
  ScenarioLabSemanticComparisonMetrics({
    required this.passed,
    required this.comparedNodes,
    required this.changedNodes,
  }) {
    if (comparedNodes < 1 ||
        comparedNodes > 1000000 ||
        changedNodes < 0 ||
        changedNodes > comparedNodes) {
      throw ArgumentError('Semantic comparison metrics are out of bounds');
    }
  }

  @override
  final bool passed;
  final int comparedNodes;
  final int changedNodes;
}

final class ScenarioLabComparisonInputMissing implements Exception {
  const ScenarioLabComparisonInputMissing();

  @override
  String toString() => 'ScenarioLabComparisonInputMissing';
}

final class ScenarioLabComparisonInputInvalid implements Exception {
  const ScenarioLabComparisonInputInvalid();

  @override
  String toString() => 'ScenarioLabComparisonInputInvalid';
}

final class ScenarioLabComparisonPolicyDenied implements Exception {
  const ScenarioLabComparisonPolicyDenied();

  @override
  String toString() => 'ScenarioLabComparisonPolicyDenied';
}

final class ScenarioLabComparisonUnsupported implements Exception {
  const ScenarioLabComparisonUnsupported();

  @override
  String toString() => 'ScenarioLabComparisonUnsupported';
}

final class ScenarioLabComparisonCancelled implements Exception {
  const ScenarioLabComparisonCancelled();

  @override
  String toString() => 'ScenarioLabComparisonCancelled';
}

/// Host boundary for deterministic comparison over exact artifact identities.
///
/// Implementations must resolve both artifact and provenance digests from
/// Host-owned storage and verify the requested classification before comparing
/// bytes. Direct `Evidence` lookup and any first/latest selection are forbidden.
abstract interface class ScenarioLabComparisonPort {
  Future<ScenarioLabVisualComparisonMetrics> compareVisual({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
    required VisualComparisonPolicy policy,
    required ScenarioLabCancellationSignal cancellation,
  });

  Future<ScenarioLabSemanticComparisonMetrics> compareSemantic({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
    required SemanticComparisonPolicy policy,
    required ScenarioLabCancellationSignal cancellation,
  });
}

/// Explicit adapter-disconnection signal. Arbitrary port errors are internal.
final class ScenarioLabAdapterDisconnected implements Exception {
  const ScenarioLabAdapterDisconnected();

  @override
  String toString() => 'ScenarioLabAdapterDisconnected';
}

/// Raised by a target port when the caller cancellation wins a target wait.
///
/// This is distinct from an adapter disconnect so the coordinator can retain
/// the user-authorized terminal cause after cleaning partial target effects.
final class ScenarioLabTargetCancelled implements Exception {
  const ScenarioLabTargetCancelled();

  @override
  String toString() => 'ScenarioLabTargetCancelled';
}

/// Typed boundary that prepares and attaches an execution target.
///
/// Runtime inputs are resolved synchronously before the queued run is reserved.
/// Implementations must keep that resolution pure: attachment and other target
/// effects begin only in [attach]. This lets every later, including failed,
/// snapshot carry the frozen binding required by the public contracts.
abstract interface class ScenarioLabTargetPort {
  ScenarioLabRuntimeInputBinding resolveRuntimeInputs({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
  });

  Future<ScenarioLabTargetSession> attach({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
    required AppAdapterRelayNonce nonce,
    required ScenarioLabCancellationSignal cancellation,
  });

  /// Aborts and drains every target effect owned by [runId].
  ///
  /// This operation is idempotent and must also cover an attachment that has
  /// started but has not produced a [ScenarioLabTargetSession] yet. Completion
  /// proves that no process, Gateway or relay owned by the run remains active.
  Future<void> abort(ScenarioLabRunId runId);
}

/// One typed target attachment. No transport or relay implementation is
/// implied by this interface.
abstract interface class ScenarioLabTargetSession {
  AppAdapterRelayHello get hello;

  Future<AppAdapterRelayResult> execute(
    AppAdapterRelayCommand command, {
    required ScenarioLabCancellationSignal cancellation,
  });

  Future<void> close();
}
