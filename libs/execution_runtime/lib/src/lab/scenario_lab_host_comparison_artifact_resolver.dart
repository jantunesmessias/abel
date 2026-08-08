import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';

import '../evidence/local_evidence_repository.dart';
import '../evidence/png_capture_inspector.dart';
import '../storage/filesystem_workspace_store.dart';
import 'scenario_lab_execution_ports.dart';
import 'scenario_lab_run_store.dart';
import 'scenario_lab_supplemental_artifact_cas_resolver.dart';

/// Resolves comparison inputs from their exact Host-owned provenance.
///
/// A descriptor that is present in the selected run's collected Evidence is
/// validated as an App Adapter capture receipt. Every other descriptor is
/// delegated to the closed supplemental-artifact provenance resolver. Neither
/// path enumerates CAS or substitutes another run, Evidence, or artifact.
final class ScenarioLabHostComparisonArtifactResolver {
  ScenarioLabHostComparisonArtifactResolver({
    required this.store,
    required this.runStore,
    required this.evidenceRepository,
    ScenarioLabSupplementalArtifactCasResolver? supplemental,
    this.pngInspector = const PngCaptureInspector(),
  }) : supplemental =
           supplemental ??
           ScenarioLabSupplementalArtifactCasResolver(store: store) {
    if (evidenceRepository.store.workspaceRoot != store.workspaceRoot ||
        evidenceRepository.store.stateRoot != store.stateRoot) {
      throw ArgumentError(
        'Scenario Lab comparison repositories belong to different workspaces',
      );
    }
    if (this.supplemental.store.workspaceRoot != store.workspaceRoot ||
        this.supplemental.store.stateRoot != store.stateRoot) {
      throw ArgumentError(
        'Scenario Lab supplemental resolver belongs to another workspace',
      );
    }
  }

  final FileSystemWorkspaceStore store;
  final ScenarioLabRunStore runStore;
  final LocalEvidenceRepository evidenceRepository;
  final ScenarioLabSupplementalArtifactCasResolver supplemental;
  final PngCaptureInspector pngInspector;

  Future<ScenarioLabResolvedComparisonArtifact?> resolve({
    required ScenarioLabRunId runId,
    required ScenarioLabComparisonArtifactDescriptor descriptor,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) {
      throw const ScenarioLabComparisonCancelled();
    }

    final ScenarioLabStoredRun run;
    try {
      run = runStore.requireRun(runId);
    } on ScenarioLabRunNotFound {
      throw const ScenarioLabComparisonInputInvalid();
    } on FileSystemException {
      throw const ScenarioLabComparisonInputInvalid();
    } on FormatException {
      throw const ScenarioLabComparisonInputInvalid();
    } on StateError {
      throw const ScenarioLabComparisonInputInvalid();
    }

    final matches = <_CollectedArtifact>[];
    for (final result in run.latest.requiredEvidence) {
      if (result.state != RequiredEvidenceResultState.collected) continue;
      for (final artifact in result.artifacts) {
        if (artifact.artifactDigest == descriptor.artifactDigest &&
            artifact.provenanceDigest == descriptor.provenanceDigest &&
            artifact.classification == descriptor.classification) {
          matches.add(_CollectedArtifact(result: result, artifact: artifact));
        }
      }
    }
    if (matches.length > 1) {
      throw const ScenarioLabComparisonInputInvalid();
    }
    if (matches.isEmpty) {
      return supplemental.resolve(
        runId: runId,
        descriptor: descriptor,
        cancellation: cancellation,
      );
    }
    return _resolveCurrentCollection(
      runId: runId,
      snapshot: run.latest,
      match: matches.single,
      descriptor: descriptor,
      cancellation: cancellation,
    );
  }

  Future<ScenarioLabResolvedComparisonArtifact> _resolveCurrentCollection({
    required ScenarioLabRunId runId,
    required ScenarioLabRunSnapshot snapshot,
    required _CollectedArtifact match,
    required ScenarioLabComparisonArtifactDescriptor descriptor,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) {
      throw const ScenarioLabComparisonCancelled();
    }
    final result = match.result;
    final runtimeInputs = snapshot.runtimeInputs;
    final evidenceDigest = result.evidenceDigest;
    if (runtimeInputs == null ||
        evidenceDigest == null ||
        result.providerId.value != 'capture.app-adapter' ||
        result.freshness != EvidenceFreshness.fresh ||
        result.artifacts.length != 1) {
      throw const ScenarioLabComparisonInputInvalid();
    }

    try {
      final evidence = evidenceRepository.readEvidence(evidenceDigest);
      if (evidence == null ||
          evidence.digest != evidenceDigest ||
          evidence.artifacts.length != 1 ||
          evidence.subjectDigest != snapshot.catalogDigest ||
          evidence.fingerprint.catalogDigest != snapshot.catalogDigest ||
          evidence.fingerprint.digest !=
              runtimeInputs.executionFingerprintDigest ||
          evidence.fingerprint.targetId != runtimeInputs.executionTargetId ||
          evidence.fingerprint.runtimeFidelity != result.fidelity) {
        throw const FormatException('Collected Evidence binding mismatch');
      }
      final artifact = evidence.artifacts.single;
      if (artifact.digest != descriptor.artifactDigest ||
          artifact.classification != descriptor.classification ||
          artifact.mediaType !=
              AppAdapterRelayCaptureUploadGrant.expectedMediaType ||
          artifact.role != 'scenario-lab.capture.app-adapter' ||
          artifact.pixelDigest == null ||
          artifact.width == null ||
          artifact.height == null) {
        throw const FormatException('Collected Evidence artifact mismatch');
      }

      final artifactBytes = store.readBlob(descriptor.artifactDigest);
      final provenanceBytes = store.readBlob(descriptor.provenanceDigest);
      if (artifactBytes == null ||
          provenanceBytes == null ||
          provenanceBytes.isEmpty ||
          provenanceBytes.length > 64 * 1024 ||
          artifactBytes.length != artifact.size ||
          Digest.bytes(artifactBytes) != descriptor.artifactDigest) {
        throw const FormatException('Collected Evidence CAS input mismatch');
      }
      final receipt = AppAdapterCaptureReceipt.fromJson(
        jsonDecode(utf8.decode(provenanceBytes, allowMalformed: false)),
        expectedDigest: descriptor.provenanceDigest,
      );
      final inspection = pngInspector.inspect(artifactBytes);
      if (!_sameBytes(provenanceBytes, receipt.canonicalBytes) ||
          receipt.sessionId != runId.value ||
          receipt.artifactDigest != artifact.digest ||
          receipt.size != artifact.size ||
          receipt.pixelDigest != artifact.pixelDigest ||
          receipt.width != artifact.width ||
          receipt.height != artifact.height ||
          receipt.completedAt != evidence.observedAt ||
          inspection.pixelDigest != artifact.pixelDigest ||
          inspection.width != artifact.width ||
          inspection.height != artifact.height) {
        throw const FormatException('Capture receipt provenance mismatch');
      }
      if (cancellation.isCancelled) {
        throw const ScenarioLabComparisonCancelled();
      }
      return ScenarioLabResolvedComparisonArtifact(
        descriptor: descriptor,
        bytes: artifactBytes,
      );
    } on ScenarioLabComparisonCancelled {
      rethrow;
    } on FileSystemException {
      throw const ScenarioLabComparisonInputInvalid();
    } on FormatException {
      throw const ScenarioLabComparisonInputInvalid();
    } on ArgumentError {
      throw const ScenarioLabComparisonInputInvalid();
    } on StateError {
      throw const ScenarioLabComparisonInputInvalid();
    }
  }
}

final class _CollectedArtifact {
  const _CollectedArtifact({required this.result, required this.artifact});

  final RequiredEvidenceRunResult result;
  final ScenarioEvidenceArtifactResult artifact;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
