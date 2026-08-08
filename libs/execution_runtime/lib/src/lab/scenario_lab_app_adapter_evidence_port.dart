import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../evidence/local_evidence_repository.dart';
import '../host/app_adapter_capture_bridge.dart';
import 'scenario_lab_execution_ports.dart';

/// Host-resolved authority used to materialize App Adapter capture Evidence.
///
/// [targetOrigin] must come from the validated target readiness record. The
/// classification and fingerprint are Host policy/runtime facts, never values
/// returned by the App Adapter.
final class ScenarioLabAppAdapterEvidenceContext {
  ScenarioLabAppAdapterEvidenceContext({
    required Uri targetOrigin,
    required this.executionFingerprint,
    required this.classification,
  }) : targetOrigin = _canonicalLoopbackOrigin(targetOrigin);

  final Uri targetOrigin;
  final ExecutionFingerprint executionFingerprint;
  final ArtifactClassification classification;
}

typedef ScenarioLabAppAdapterEvidenceContextResolver =
    ScenarioLabAppAdapterEvidenceContext Function(
      ScenarioLabRunId runId,
      RequiredEvidenceDefinition requirement,
      ScenarioLabRuntimeInputBinding runtimeInputs,
    );

/// App Adapter Evidence port backed by the existing PUT registry and CAS.
///
/// This adapter has no RPC-facing inputs. It issues origin-bound upload grants,
/// consumes only Host receipts, re-reads the artifact from CAS, and persists a
/// typed [Evidence] document before returning to the execution core.
final class ScenarioLabAppAdapterEvidencePort
    implements ScenarioLabEvidencePort {
  ScenarioLabAppAdapterEvidencePort({
    required this.captureBridge,
    required this.evidenceRepository,
    required this.ids,
    required this.resolveContext,
  });

  final AppAdapterCaptureBridge captureBridge;
  final LocalEvidenceRepository evidenceRepository;
  final IdGenerator ids;
  final ScenarioLabAppAdapterEvidenceContextResolver resolveContext;

  final Map<String, String> _sessionIds = <String, String>{};
  final Map<String, _PendingScenarioLabCapture> _pending =
      <String, _PendingScenarioLabCapture>{};
  final Set<String> _requirementKeys = <String>{};

  @override
  Future<AppAdapterRelayCaptureUploadGrant> issueCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required ScenarioLabRuntimeInputBinding runtimeInputs,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) throw const ScenarioLabTargetCancelled();
    if (requirement.providerId.value != 'capture.app-adapter') {
      throw const ScenarioLabEvidenceInvalidInput();
    }
    final requirementKey = '${runId.value}/${requirement.id.value}';
    if (!_requirementKeys.add(requirementKey)) {
      throw StateError('Scenario Lab Evidence requirement is already issued');
    }
    try {
      final context = resolveContext(runId, requirement, runtimeInputs);
      if (context.executionFingerprint.digest !=
              runtimeInputs.executionFingerprintDigest ||
          context.executionFingerprint.runtimeFidelity !=
              requirement.fidelity) {
        throw const ScenarioLabEvidenceInvalidInput();
      }
      if (!requirement.allowedClassifications.contains(
        context.classification,
      )) {
        throw const ScenarioLabEvidencePolicyDenied();
      }
      final sessionId = _sessionIds.putIfAbsent(runId.value, () => runId.value);
      final requestId = _freshTransportId('capture');
      final command = captureBridge.issue(
        requestId: requestId,
        sessionId: sessionId,
        targetOrigin: context.targetOrigin,
      );
      final grant = AppAdapterRelayCaptureUploadGrant(
        requestId: command.requestId,
        sessionId: command.sessionId,
        uploadUri: command.uploadUri,
        expiresAt: command.expiresAt,
        maxBytes: command.maxBytes,
      );
      _pending[requestId] = _PendingScenarioLabCapture(
        runId: runId,
        requirementId: requirement.id,
        context: context,
        grantDigest: Digest.semantic(grant.toJson()),
      );
      return grant;
    } on Object {
      _requirementKeys.remove(requirementKey);
      rethrow;
    }
  }

  @override
  Future<ScenarioLabHostEvidenceCollection?> consumeCaptureUpload({
    required ScenarioLabRunId runId,
    required RequiredEvidenceDefinition requirement,
    required AppAdapterRelayCaptureUploadGrant uploadGrant,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) throw const ScenarioLabTargetCancelled();
    final pending = _pending[uploadGrant.requestId];
    if (pending == null ||
        pending.runId != runId ||
        pending.requirementId != requirement.id ||
        pending.grantDigest != Digest.semantic(uploadGrant.toJson())) {
      throw const ScenarioLabEvidenceInvalidInput();
    }
    final existing = pending.collection;
    if (existing != null) return existing;

    final AppAdapterCaptureStatus status;
    try {
      status = captureBridge.status(
        sessionId: uploadGrant.sessionId,
        requestId: uploadGrant.requestId,
      );
    } on StateError {
      return null;
    }
    if (status.state == 'pending' || status.state == 'uploading') return null;
    if (status.state != 'completed' || status.receipt == null) {
      throw const ScenarioLabEvidenceInvalidInput();
    }
    try {
      final receipt = status.receipt!;
      final bytes = evidenceRepository.store.readBlob(receipt.artifactDigest);
      if (bytes == null ||
          bytes.length != receipt.size ||
          Digest.bytes(bytes) != receipt.artifactDigest) {
        throw const ScenarioLabEvidenceInvalidInput();
      }
      final provenanceDigest = receipt.digest;
      final provenanceBytes = receipt.canonicalBytes;
      final storedProvenanceDigest = evidenceRepository.store.withExclusiveLock(
        () => evidenceRepository.store.putBlob(provenanceBytes),
      );
      if (storedProvenanceDigest != provenanceDigest) {
        throw const ScenarioLabEvidenceInvalidInput();
      }
      final artifact = Artifact(
        digest: receipt.artifactDigest,
        size: receipt.size,
        mediaType: AppAdapterRelayCaptureUploadGrant.expectedMediaType,
        classification: pending.context.classification,
        role: 'scenario-lab.capture.app-adapter',
        pixelDigest: receipt.pixelDigest,
        width: receipt.width,
        height: receipt.height,
      );
      final evidence = Evidence(
        id: 'evidence-${_freshTransportId('capture')}',
        subjectDigest: pending.context.executionFingerprint.catalogDigest,
        fingerprint: pending.context.executionFingerprint,
        observedAt: receipt.completedAt,
        policyId: requirement.evidencePolicyId.value,
        artifacts: <Artifact>[artifact],
      );
      final persisted = evidenceRepository.persistEvidence(evidence);
      final collection = ScenarioLabHostEvidenceCollection(
        uploadReceipt: receipt,
        evidence: persisted,
      );
      pending.collection = collection;
      return collection;
    } on ScenarioLabEvidenceInvalidInput {
      rethrow;
    } on Object {
      throw const ScenarioLabEvidenceInvalidInput();
    }
  }

  @override
  Future<void> cleanupRun(ScenarioLabRunId runId) async {
    final sessionId = _sessionIds.remove(runId.value);
    if (sessionId != null) captureBridge.discardSession(sessionId);
    _pending.removeWhere((_, pending) => pending.runId == runId);
    _requirementKeys.removeWhere((key) => key.startsWith('${runId.value}/'));
  }

  String _freshTransportId(String prefix) =>
      _stableTransportId(prefix, ids.nextId());

  String _stableTransportId(String prefix, String value) =>
      '${prefix}_${Digest.semantic(value).value.substring(7, 39)}';
}

final class _PendingScenarioLabCapture {
  _PendingScenarioLabCapture({
    required this.runId,
    required this.requirementId,
    required this.context,
    required this.grantDigest,
  });

  final ScenarioLabRunId runId;
  final RequiredEvidenceId requirementId;
  final ScenarioLabAppAdapterEvidenceContext context;
  final Digest grantDigest;
  ScenarioLabHostEvidenceCollection? collection;
}

Uri _canonicalLoopbackOrigin(Uri value) {
  if (!const <String>{'http', 'https'}.contains(value.scheme) ||
      !const <String>{'localhost', '127.0.0.1', '::1'}.contains(value.host) ||
      value.port < 1 ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw const FormatException(
      'Scenario Lab Evidence requires a Host-owned loopback target origin',
    );
  }
  return Uri.parse(value.origin);
}
