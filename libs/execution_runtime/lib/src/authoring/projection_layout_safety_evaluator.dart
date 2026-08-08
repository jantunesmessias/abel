import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart' as engine;

/// Host-owned orchestration for the frozen structural acceptance evaluator.
///
/// This makes no visual, behavioral, Evidence, or Scenario Lab claim. The
/// engine proves exact draft/change-set geometry and evaluates every candidate
/// frame for overlap in O(n log n). Touching edges remain valid.
final class HostProjectionLayoutSafetyAcceptance {
  const HostProjectionLayoutSafetyAcceptance({
    this.evaluator = const engine.ProjectionLayoutSafetyEvaluator(),
    this.reviewCompiler = const engine.ExperienceReviewPacketCompiler(),
  });

  final engine.ProjectionLayoutSafetyEvaluator evaluator;
  final engine.ExperienceReviewPacketCompiler reviewCompiler;

  ExperienceReviewPacket evaluateAndRecord({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
    required ProjectionLayoutManifest candidateLayout,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    required Digest currentSourceDigest,
    required Digest currentContentSetDigest,
    required DateTime recordedAt,
  }) {
    if (currentSourceDigest != draft.baseSourceDigest ||
        currentContentSetDigest != draft.contentSetDigest ||
        changeSet.baseSourceDigest != currentSourceDigest ||
        changeSet.expectedContentSetDigest != currentContentSetDigest) {
      throw StateError(
        'Projection layout acceptance is stale against source or content',
      );
    }
    reviewCompiler.validatePacket(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: allowedArtifactDigests,
    );
    final outcome = evaluator.evaluate(
      draft: draft,
      baseLayout: baseLayout,
      candidateLayout: candidateLayout,
      changeSet: changeSet,
    );
    return reviewCompiler.recordAcceptance(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: allowedArtifactDigests,
      outcome: outcome,
      recordedAt: recordedAt,
    );
  }
}
