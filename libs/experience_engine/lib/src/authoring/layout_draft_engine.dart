import 'package:experience_contracts/experience_contracts.dart';

final class LayoutDraftEngine {
  const LayoutDraftEngine();

  LayoutDraft openDraft({
    required LayoutDraftId id,
    required AuthoringSubjectRef subject,
    required ProjectionLayoutManifest baseLayout,
    required Digest baseSourceDigest,
    required Digest contentSetDigest,
  }) {
    _validateBase(subject: subject, draft: null, baseLayout: baseLayout);
    return LayoutDraft(
      id: id,
      subject: subject,
      baseLayoutDigest: baseLayout.digest,
      candidateLayoutDigest: baseLayout.digest,
      baseSourceDigest: baseSourceDigest,
      topologyDigest: baseLayout.topologyDigest,
      contentSetDigest: contentSetDigest,
      history: const <LayoutMoveNodeOperation>[],
      cursor: 0,
      revision: 0,
      previousDraftDigest: null,
    );
  }

  void validateDraft({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    _validateBase(subject: draft.subject, draft: draft, baseLayout: baseLayout);
    final frames = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in baseLayout.nodeFrames) frame.nodeInstanceId: frame,
    };
    var candidateDigest = baseLayout.digest;
    for (var index = 0; index < draft.history.length; index += 1) {
      final operation = draft.history[index];
      final frame = frames[operation.nodeInstanceId];
      if (frame == null ||
          frame.x != operation.fromX ||
          frame.y != operation.fromY) {
        throw StateError('Layout operation history is stale or non-contiguous');
      }
      frames[operation.nodeInstanceId] = _moveFrame(
        frame,
        x: operation.toX,
        y: operation.toY,
      );
      if (index + 1 == draft.cursor) {
        candidateDigest = _layoutFromFrames(baseLayout, frames).digest;
      }
    }
    if (candidateDigest != draft.candidateLayoutDigest) {
      throw StateError(
        'LayoutDraft candidate digest does not match its cursor',
      );
    }
  }

  ProjectionLayoutManifest materialize({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    validateDraft(draft: draft, baseLayout: baseLayout);
    final frames = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in baseLayout.nodeFrames) frame.nodeInstanceId: frame,
    };
    for (final operation in draft.history.take(draft.cursor)) {
      final frame = frames[operation.nodeInstanceId];
      if (frame == null) {
        throw StateError('Layout operation references an unknown node');
      }
      if (frame.x != operation.fromX || frame.y != operation.fromY) {
        throw StateError('Layout operation history is stale or non-contiguous');
      }
      frames[operation.nodeInstanceId] = _moveFrame(
        frame,
        x: operation.toX,
        y: operation.toY,
      );
    }
    final candidate = ProjectionLayoutManifest(
      topologyDigest: baseLayout.topologyDigest,
      projectionId: baseLayout.projectionId,
      nodeFrames: frames.values.toList(growable: false),
      groups: baseLayout.groups,
      lanes: baseLayout.lanes,
      annotations: baseLayout.annotations,
      camera: baseLayout.camera,
    );
    if (candidate.digest != draft.candidateLayoutDigest) {
      throw StateError(
        'LayoutDraft candidate digest does not match its history',
      );
    }
    return candidate;
  }

  LayoutDraft applyMove({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
    required LayoutMoveNodeInput input,
  }) {
    final current = materialize(draft: draft, baseLayout: baseLayout);
    final matching = current.nodeFrames
        .where((frame) => frame.nodeInstanceId == input.nodeInstanceId)
        .toList(growable: false);
    if (matching.length != 1) {
      throw StateError('Layout move references an unknown node');
    }
    final frame = matching.single;
    if (frame.x == input.toX && frame.y == input.toY) {
      throw StateError('Layout move must change the current node frame');
    }
    final operation = LayoutMoveNodeOperation(
      id: _operationId(draft),
      nodeInstanceId: input.nodeInstanceId,
      fromX: frame.x,
      fromY: frame.y,
      toX: input.toX,
      toY: input.toY,
    );
    final retained = draft.history.take(draft.cursor).toList(growable: true);
    retained.add(operation);
    if (retained.length > experienceAuthoringMaxOperations) {
      throw StateError('Layout draft operation quota exceeded');
    }
    return _withHistory(
      draft: draft,
      baseLayout: baseLayout,
      history: retained,
      cursor: retained.length,
    );
  }

  LayoutDraft undo({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    materialize(draft: draft, baseLayout: baseLayout);
    if (draft.cursor == 0) throw StateError('Layout draft has nothing to undo');
    return _withHistory(
      draft: draft,
      baseLayout: baseLayout,
      history: draft.history,
      cursor: draft.cursor - 1,
    );
  }

  LayoutDraft redo({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    materialize(draft: draft, baseLayout: baseLayout);
    if (draft.cursor >= draft.history.length) {
      throw StateError('Layout draft has nothing to redo');
    }
    return _withHistory(
      draft: draft,
      baseLayout: baseLayout,
      history: draft.history,
      cursor: draft.cursor + 1,
    );
  }

  LayoutDraft reset({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    materialize(draft: draft, baseLayout: baseLayout);
    if (draft.history.isEmpty && draft.cursor == 0) {
      throw StateError('An unchanged draft cannot be reset');
    }
    return LayoutDraft(
      id: draft.id,
      subject: draft.subject,
      baseLayoutDigest: draft.baseLayoutDigest,
      candidateLayoutDigest: draft.baseLayoutDigest,
      baseSourceDigest: draft.baseSourceDigest,
      topologyDigest: draft.topologyDigest,
      contentSetDigest: draft.contentSetDigest,
      history: const <LayoutMoveNodeOperation>[],
      cursor: 0,
      revision: draft.revision + 1,
      previousDraftDigest: draft.digest,
    );
  }

  ExperienceChangeSet createChangeSet({
    required ExperienceChangeSetId id,
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
    required Digest currentContentSetDigest,
    required Digest currentSourceDigest,
  }) {
    if (currentContentSetDigest != draft.contentSetDigest ||
        currentSourceDigest != draft.baseSourceDigest) {
      throw StateError('Layout draft is stale against the current source head');
    }
    if (draft.cursor == 0) {
      throw StateError('An unchanged layout draft cannot become a change set');
    }
    final candidate = materialize(draft: draft, baseLayout: baseLayout);
    if (candidate.digest == baseLayout.digest) {
      throw StateError('A draft that returns to its base cannot be reviewed');
    }
    final before = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in baseLayout.nodeFrames) frame.nodeInstanceId: frame,
    };
    final changes = <LayoutFrameChange>[];
    for (final frame in candidate.nodeFrames) {
      final previous = before[frame.nodeInstanceId];
      if (previous == null) {
        throw StateError('Candidate layout contains a node outside its base');
      }
      if (previous.x != frame.x || previous.y != frame.y) {
        changes.add(
          LayoutFrameChange(
            nodeInstanceId: frame.nodeInstanceId,
            beforeX: previous.x,
            beforeY: previous.y,
            afterX: frame.x,
            afterY: frame.y,
          ),
        );
      }
    }
    final comparison = LayoutComparison(
      topologyDigest: draft.topologyDigest,
      projectionId: draft.subject.projectionId,
      beforeLayoutDigest: draft.baseLayoutDigest,
      afterLayoutDigest: candidate.digest,
      changedFrames: changes,
    );
    final result = ExperienceChangeSet(
      id: id,
      subject: draft.subject,
      baseSourceDigest: draft.baseSourceDigest,
      expectedContentSetDigest: draft.contentSetDigest,
      draftDigest: draft.digest,
      draftRevision: draft.revision,
      comparison: comparison,
      operations: draft.history.take(draft.cursor).toList(growable: false),
    );
    validateChangeSet(changeSet: result, draft: draft, baseLayout: baseLayout);
    return result;
  }

  void validateChangeSet({
    required ExperienceChangeSet changeSet,
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    final appliedOperations = draft.history
        .take(draft.cursor)
        .toList(growable: false);
    if (changeSet.draftDigest != draft.digest ||
        changeSet.draftRevision != draft.revision ||
        changeSet.subject != draft.subject ||
        changeSet.baseSourceDigest != draft.baseSourceDigest ||
        changeSet.expectedContentSetDigest != draft.contentSetDigest ||
        changeSet.operations.length != appliedOperations.length ||
        !List<Object?>.generate(
          appliedOperations.length,
          (index) =>
              changeSet.operations[index].digest ==
              appliedOperations[index].digest,
        ).every((value) => value == true) ||
        changeSet.baseLayoutDigest != baseLayout.digest ||
        changeSet.comparison.topologyDigest != baseLayout.topologyDigest ||
        changeSet.subject.projectionId != baseLayout.projectionId) {
      throw StateError('ExperienceChangeSet belongs to another base layout');
    }
    final frames = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in baseLayout.nodeFrames) frame.nodeInstanceId: frame,
    };
    for (final operation in changeSet.operations) {
      final frame = frames[operation.nodeInstanceId];
      if (frame == null ||
          frame.x != operation.fromX ||
          frame.y != operation.fromY) {
        throw StateError('ExperienceChangeSet operation history is invalid');
      }
      frames[operation.nodeInstanceId] = _moveFrame(
        frame,
        x: operation.toX,
        y: operation.toY,
      );
    }
    final candidate = _layoutFromFrames(baseLayout, frames);
    final before = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in baseLayout.nodeFrames) frame.nodeInstanceId: frame,
    };
    final expectedChanges = <LayoutFrameChange>[];
    for (final frame in candidate.nodeFrames) {
      final previous = before[frame.nodeInstanceId]!;
      if (previous.x != frame.x || previous.y != frame.y) {
        expectedChanges.add(
          LayoutFrameChange(
            nodeInstanceId: frame.nodeInstanceId,
            beforeX: previous.x,
            beforeY: previous.y,
            afterX: frame.x,
            afterY: frame.y,
          ),
        );
      }
    }
    final expectedComparison = LayoutComparison(
      topologyDigest: baseLayout.topologyDigest,
      projectionId: baseLayout.projectionId,
      beforeLayoutDigest: baseLayout.digest,
      afterLayoutDigest: candidate.digest,
      changedFrames: expectedChanges,
    );
    if (expectedComparison.digest != changeSet.comparison.digest) {
      throw StateError(
        'ExperienceChangeSet operations do not match its comparison',
      );
    }
  }

  LayoutDraft _withHistory({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
    required List<LayoutMoveNodeOperation> history,
    required int cursor,
  }) {
    final provisional = LayoutDraft(
      id: draft.id,
      subject: draft.subject,
      baseLayoutDigest: draft.baseLayoutDigest,
      candidateLayoutDigest: cursor == 0
          ? draft.baseLayoutDigest
          : Digest.semantic(<String, Object?>{
              'provisional': true,
              'cursor': cursor,
              'history': history
                  .take(cursor)
                  .map((item) => item.toJson())
                  .toList(),
            }),
      baseSourceDigest: draft.baseSourceDigest,
      topologyDigest: draft.topologyDigest,
      contentSetDigest: draft.contentSetDigest,
      history: history,
      cursor: cursor,
      revision: draft.revision + 1,
      previousDraftDigest: draft.digest,
    );
    final candidate = _materializeUnchecked(
      draft: provisional,
      baseLayout: baseLayout,
    );
    return LayoutDraft(
      id: draft.id,
      subject: draft.subject,
      baseLayoutDigest: draft.baseLayoutDigest,
      candidateLayoutDigest: candidate.digest,
      baseSourceDigest: draft.baseSourceDigest,
      topologyDigest: draft.topologyDigest,
      contentSetDigest: draft.contentSetDigest,
      history: history,
      cursor: cursor,
      revision: draft.revision + 1,
      previousDraftDigest: draft.digest,
    );
  }

  ProjectionLayoutManifest _materializeUnchecked({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    _validateBase(subject: draft.subject, draft: draft, baseLayout: baseLayout);
    final frames = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in baseLayout.nodeFrames) frame.nodeInstanceId: frame,
    };
    for (final operation in draft.history.take(draft.cursor)) {
      final frame = frames[operation.nodeInstanceId];
      if (frame == null ||
          frame.x != operation.fromX ||
          frame.y != operation.fromY) {
        throw StateError('Layout operation history is stale or invalid');
      }
      frames[operation.nodeInstanceId] = _moveFrame(
        frame,
        x: operation.toX,
        y: operation.toY,
      );
    }
    return ProjectionLayoutManifest(
      topologyDigest: baseLayout.topologyDigest,
      projectionId: baseLayout.projectionId,
      nodeFrames: frames.values.toList(growable: false),
      groups: baseLayout.groups,
      lanes: baseLayout.lanes,
      annotations: baseLayout.annotations,
      camera: baseLayout.camera,
    );
  }

  ProjectionLayoutManifest _layoutFromFrames(
    ProjectionLayoutManifest baseLayout,
    Map<NodeInstanceId, ProjectionNodeFrame> frames,
  ) => ProjectionLayoutManifest(
    topologyDigest: baseLayout.topologyDigest,
    projectionId: baseLayout.projectionId,
    nodeFrames: frames.values.toList(growable: false),
    groups: baseLayout.groups,
    lanes: baseLayout.lanes,
    annotations: baseLayout.annotations,
    camera: baseLayout.camera,
  );

  void _validateBase({
    required AuthoringSubjectRef subject,
    required LayoutDraft? draft,
    required ProjectionLayoutManifest baseLayout,
  }) {
    if (subject.projectionId != baseLayout.projectionId ||
        (draft != null &&
            (draft.baseLayoutDigest != baseLayout.digest ||
                draft.topologyDigest != baseLayout.topologyDigest))) {
      throw StateError('Layout draft is bound to another base layout');
    }
  }

  ProjectionNodeFrame _moveFrame(
    ProjectionNodeFrame frame, {
    required double x,
    required double y,
  }) => ProjectionNodeFrame(
    nodeInstanceId: frame.nodeInstanceId,
    x: x,
    y: y,
    width: frame.width,
    height: frame.height,
    groupId: frame.groupId,
    laneId: frame.laneId,
  );

  LayoutOperationId _operationId(LayoutDraft draft) {
    final hex = Digest.semantic(<String, Object?>{
      'draftId': draft.id.value,
      'revision': draft.revision + 1,
    }).value.substring('sha256:'.length);
    return LayoutOperationId('op-$hex');
  }
}

/// Exact O(n log n) structural evaluator for the Host-only v1 acceptance.
final class ProjectionLayoutSafetyEvaluator {
  const ProjectionLayoutSafetyEvaluator({
    this.draftEngine = const LayoutDraftEngine(),
  });

  final LayoutDraftEngine draftEngine;

  AutomatedAcceptanceOutcome evaluate({
    required LayoutDraft draft,
    required ProjectionLayoutManifest baseLayout,
    required ProjectionLayoutManifest candidateLayout,
    required ExperienceChangeSet changeSet,
  }) {
    draftEngine.validateChangeSet(
      changeSet: changeSet,
      draft: draft,
      baseLayout: baseLayout,
    );
    final materialized = draftEngine.materialize(
      draft: draft,
      baseLayout: baseLayout,
    );
    if (candidateLayout.digest != materialized.digest ||
        candidateLayout.digest != changeSet.candidateLayoutDigest ||
        candidateLayout.topologyDigest != baseLayout.topologyDigest ||
        candidateLayout.projectionId != baseLayout.projectionId) {
      throw StateError('Layout safety candidate does not match the draft head');
    }
    return _hasOverlap(candidateLayout.nodeFrames)
        ? AutomatedAcceptanceOutcome.failed
        : AutomatedAcceptanceOutcome.passed;
  }

  bool _hasOverlap(List<ProjectionNodeFrame> frames) {
    if (frames.length < 2) return false;
    final yBounds = <double>[];
    final rawEvents = <_RawLayoutSweepEvent>[];
    for (final frame in frames) {
      final right = frame.x + frame.width;
      final bottom = frame.y + frame.height;
      if (!frame.x.isFinite ||
          !frame.y.isFinite ||
          !frame.width.isFinite ||
          !frame.height.isFinite ||
          !right.isFinite ||
          !bottom.isFinite ||
          frame.width <= 0 ||
          frame.height <= 0) {
        throw StateError('Layout safety requires finite positive extents');
      }
      yBounds
        ..add(frame.y)
        ..add(bottom);
      rawEvents
        ..add(
          _RawLayoutSweepEvent(
            x: frame.x,
            starts: true,
            lowY: frame.y,
            highY: bottom,
          ),
        )
        ..add(
          _RawLayoutSweepEvent(
            x: right,
            starts: false,
            lowY: frame.y,
            highY: bottom,
          ),
        );
    }
    yBounds.sort();
    final uniqueY = <double>[];
    for (final value in yBounds) {
      if (uniqueY.isEmpty || uniqueY.last != value) uniqueY.add(value);
    }
    final yIndex = <double, int>{
      for (var index = 0; index < uniqueY.length; index += 1)
        uniqueY[index]: index,
    };
    final events =
        rawEvents
            .map(
              (event) => _LayoutSweepEvent(
                x: event.x,
                starts: event.starts,
                low: yIndex[event.lowY]!,
                high: yIndex[event.highY]! - 1,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byX = left.x.compareTo(right.x);
            if (byX != 0) return byX;
            if (left.starts == right.starts) return 0;
            return left.starts ? 1 : -1;
          });

    final tree = _RangeAddMaxTree(uniqueY.length - 1);
    var cursor = 0;
    while (cursor < events.length) {
      final x = events[cursor].x;
      var end = cursor + 1;
      while (end < events.length && events[end].x == x) {
        end += 1;
      }
      for (var index = cursor; index < end; index += 1) {
        final event = events[index];
        if (!event.starts) tree.add(event.low, event.high, -1);
      }
      for (var index = cursor; index < end; index += 1) {
        final event = events[index];
        if (!event.starts) continue;
        if (tree.maximum(event.low, event.high) > 0) return true;
        tree.add(event.low, event.high, 1);
      }
      cursor = end;
    }
    return false;
  }
}

final class _RawLayoutSweepEvent {
  const _RawLayoutSweepEvent({
    required this.x,
    required this.starts,
    required this.lowY,
    required this.highY,
  });

  final double x;
  final bool starts;
  final double lowY;
  final double highY;
}

final class _LayoutSweepEvent {
  const _LayoutSweepEvent({
    required this.x,
    required this.starts,
    required this.low,
    required this.high,
  });

  final double x;
  final bool starts;
  final int low;
  final int high;
}

final class _RangeAddMaxTree {
  _RangeAddMaxTree(this.length)
    : _maximum = List<int>.filled(length * 4 + 8, 0),
      _lazy = List<int>.filled(length * 4 + 8, 0) {
    if (length <= 0) throw ArgumentError('Segment tree requires intervals');
  }

  final int length;
  final List<int> _maximum;
  final List<int> _lazy;

  void add(int low, int high, int delta) {
    if (low > high) return;
    _add(1, 0, length - 1, low, high, delta);
  }

  int maximum(int low, int high) {
    if (low > high) return 0;
    return _query(1, 0, length - 1, low, high);
  }

  void _add(int node, int left, int right, int low, int high, int delta) {
    if (low <= left && right <= high) {
      _maximum[node] += delta;
      _lazy[node] += delta;
      return;
    }
    final middle = (left + right) >> 1;
    if (low <= middle) _add(node * 2, left, middle, low, high, delta);
    if (high > middle) {
      _add(node * 2 + 1, middle + 1, right, low, high, delta);
    }
    _maximum[node] =
        _lazy[node] +
        (_maximum[node * 2] > _maximum[node * 2 + 1]
            ? _maximum[node * 2]
            : _maximum[node * 2 + 1]);
  }

  int _query(int node, int left, int right, int low, int high) {
    if (low <= left && right <= high) return _maximum[node];
    final middle = (left + right) >> 1;
    var result = 0;
    if (low <= middle) result = _query(node * 2, left, middle, low, high);
    if (high > middle) {
      final candidate = _query(node * 2 + 1, middle + 1, right, low, high);
      if (candidate > result) result = candidate;
    }
    return _lazy[node] + result;
  }
}

final class AuthoringGrantVerifier {
  const AuthoringGrantVerifier();

  void verify({
    required AuthoringCapability capability,
    required AuthoringActionGrant grant,
    required AuthoringGrantIntent intent,
    required AuthoringAuthorityId authorityId,
    required AuthoringPolicyId policyId,
    required AuthoringPrincipalId principalId,
    required Digest currentResolvedPlanDigest,
    required AuthoringSubjectRef subject,
    required AuthoringActionEffect effect,
    required AuthoringOperation operation,
    required Digest expectedDigest,
    required Digest expectedSourceDigest,
    required Digest payloadDigest,
    required bool grantRevoked,
    required bool grantConsumed,
    required DateTime at,
  }) {
    final now = at.toUtc();
    if (grantRevoked ||
        grantConsumed ||
        capability.resolvedPlanDigest != currentResolvedPlanDigest ||
        capability.digest != grant.capabilityDigest ||
        intent.requestId != grant.requestId ||
        intent.digest != grant.requestDigest ||
        intent.capabilityDigest != capability.digest ||
        intent.subject != subject ||
        intent.effect != effect ||
        intent.operation != operation ||
        intent.expectedDigest != expectedDigest ||
        intent.expectedSourceDigest != expectedSourceDigest ||
        intent.payloadDigest != payloadDigest ||
        grant.authorityId != authorityId ||
        grant.policyId != policyId ||
        grant.principalId != principalId ||
        capability.subject != subject ||
        grant.subject != subject ||
        !capability.effects.contains(effect) ||
        !capability.operations.contains(operation) ||
        grant.effect != effect ||
        grant.operation != operation ||
        grant.expectedDigest != expectedDigest ||
        grant.expectedSourceDigest != expectedSourceDigest ||
        grant.payloadDigest != payloadDigest ||
        now.isBefore(grant.issuedAt) ||
        !now.isBefore(grant.expiresAt)) {
      throw StateError('Authoring action is not covered by the exact grant');
    }
  }

  void verifyPromotion({
    required AuthoringCapability capability,
    required AuthoringActionGrant grant,
    required ExperiencePromotionGrantRequest intent,
    required AuthoringAuthorityId authorityId,
    required AuthoringPolicyId policyId,
    required AuthoringPrincipalId principalId,
    required Digest currentResolvedPlanDigest,
    required LayoutDraft draft,
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket reviewPacket,
    required bool grantRevoked,
    required bool grantConsumed,
    required DateTime at,
  }) {
    intent.validateAgainst(
      draft: draft,
      changeSet: changeSet,
      reviewPacket: reviewPacket,
    );
    verify(
      capability: capability,
      grant: grant,
      intent: intent,
      authorityId: authorityId,
      policyId: policyId,
      principalId: principalId,
      currentResolvedPlanDigest: currentResolvedPlanDigest,
      subject: changeSet.subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.promote,
      expectedDigest: reviewPacket.digest,
      expectedSourceDigest: changeSet.baseSourceDigest,
      payloadDigest: intent.payloadDigest,
      grantRevoked: grantRevoked,
      grantConsumed: grantConsumed,
      at: at,
    );
    if (reviewPacket.subject != changeSet.subject ||
        reviewPacket.changeSetId != changeSet.id ||
        reviewPacket.changeSetDigest != changeSet.digest ||
        reviewPacket.comparisonDigest != changeSet.comparison.digest ||
        reviewPacket.baseSourceDigest != changeSet.baseSourceDigest ||
        !reviewPacket.isPromotable) {
      throw StateError('Promotion requires an accepted current review packet');
    }
  }
}

final class ExperienceReviewPacketCompiler {
  const ExperienceReviewPacketCompiler();

  ExperienceReviewPacket compile({
    required ExperienceReviewPacketId id,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    required ExecutableReviewGuideBinding reviewGuideBinding,
    required List<ExperienceFindingRecord> findings,
    required List<ExperienceConceptProposalRecord> concepts,
    required List<ExperienceReviewCommentRecord> comments,
    required AutomatedAcceptanceRecord? automatedAcceptance,
    required List<ExperienceHumanDecisionRecord> humanDecisions,
    int revision = 0,
    Digest? previousReviewPacketDigest,
  }) {
    final result = ExperienceReviewPacket(
      id: id,
      subject: changeSet.subject,
      changeSetId: changeSet.id,
      changeSetDigest: changeSet.digest,
      comparisonDigest: changeSet.comparison.digest,
      baseSourceDigest: changeSet.baseSourceDigest,
      findings: findings,
      concepts: concepts,
      comments: comments,
      reviewGuideBinding: reviewGuideBinding,
      automatedAcceptance: automatedAcceptance,
      humanDecisions: humanDecisions,
      revision: revision,
      previousReviewPacketDigest: previousReviewPacketDigest,
    );
    validatePacket(
      packet: result,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: allowedArtifactDigests,
    );
    return result;
  }

  ExperienceReviewPacket recordAcceptance({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    required AutomatedAcceptanceOutcome outcome,
    required DateTime recordedAt,
  }) {
    if (packet.automatedAcceptance != null ||
        packet.humanDecisions.isNotEmpty) {
      throw StateError('Automated acceptance is a one-shot review transition');
    }
    return _successor(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: allowedArtifactDigests,
      automatedAcceptance: AutomatedAcceptanceRecord(
        changeSetDigest: changeSet.digest,
        evaluatorId: projectionLayoutSafetyEvaluatorId,
        outcome: outcome,
        summary: projectionLayoutSafetySummary(outcome),
        recordedAt: recordedAt,
      ),
    );
  }

  ExperienceReviewPacket appendFinding({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    required ExperienceFindingId id,
    required AppendExperienceFindingInput input,
    required AuthoringPrincipalId principalId,
    required AuthoringAuthorityId authorityId,
    required Digest grantDigest,
    required DateTime recordedAt,
  }) => _successor(
    packet: packet,
    changeSet: changeSet,
    catalog: catalog,
    topology: topology,
    allowedArtifactDigests: allowedArtifactDigests,
    findings: <ExperienceFindingRecord>[
      ...packet.findings,
      ExperienceFindingRecord(
        id: id,
        subject: input.subject,
        severity: input.severity,
        summary: input.summary,
        detail: input.detail,
        principalId: principalId,
        authorityId: authorityId,
        grantDigest: grantDigest,
        recordedAt: recordedAt,
      ),
    ],
  );

  ExperienceReviewPacket appendConcept({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    required ExperienceConceptProposalId id,
    required ProposeExperienceConceptInput input,
    required AuthoringPrincipalId principalId,
    required AuthoringAuthorityId authorityId,
    required Digest grantDigest,
    required DateTime recordedAt,
  }) => _successor(
    packet: packet,
    changeSet: changeSet,
    catalog: catalog,
    topology: topology,
    allowedArtifactDigests: allowedArtifactDigests,
    concepts: <ExperienceConceptProposalRecord>[
      ...packet.concepts,
      ExperienceConceptProposalRecord(
        id: id,
        scenarioId: input.scenarioId,
        lifecycle: ScenarioLifecycle.concept,
        title: input.title,
        rationale: input.rationale,
        principalId: principalId,
        authorityId: authorityId,
        grantDigest: grantDigest,
        recordedAt: recordedAt,
      ),
    ],
  );

  ExperienceReviewPacket appendComment({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    required ExperienceReviewCommentId id,
    required AppendExperienceReviewCommentInput input,
    required AuthoringPrincipalId principalId,
    required AuthoringAuthorityId authorityId,
    required Digest grantDigest,
    required DateTime recordedAt,
  }) => _successor(
    packet: packet,
    changeSet: changeSet,
    catalog: catalog,
    topology: topology,
    allowedArtifactDigests: allowedArtifactDigests,
    comments: <ExperienceReviewCommentRecord>[
      ...packet.comments,
      ExperienceReviewCommentRecord(
        id: id,
        sequence: packet.comments.length + 1,
        subject: input.subject,
        principalId: principalId,
        authorityId: authorityId,
        grantDigest: grantDigest,
        body: input.body,
        recordedAt: recordedAt,
        previousCommentDigest: packet.comments.isEmpty
            ? null
            : packet.comments.last.digest,
      ),
    ],
  );

  ExperienceReviewPacket appendDecision({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    required ExperienceHumanDecisionId id,
    required AppendExperienceHumanDecisionInput input,
    required AuthoringPrincipalId principalId,
    required AuthoringAuthorityId authorityId,
    required Digest grantDigest,
    required DateTime recordedAt,
  }) {
    if (packet.automatedAcceptance == null) {
      throw StateError('Automated acceptance must precede human decision');
    }
    return _successor(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: allowedArtifactDigests,
      humanDecisions: <ExperienceHumanDecisionRecord>[
        ...packet.humanDecisions,
        ExperienceHumanDecisionRecord(
          id: id,
          sequence: packet.humanDecisions.length + 1,
          changeSetDigest: changeSet.digest,
          reviewPacketDigest: packet.digest,
          principalId: principalId,
          authorityId: authorityId,
          grantDigest: grantDigest,
          decision: input.decision,
          rationale: input.rationale,
          recordedAt: recordedAt,
          previousDecisionDigest: packet.humanDecisions.isEmpty
              ? null
              : packet.humanDecisions.last.digest,
        ),
      ],
    );
  }

  ExperienceReviewPacket _successor({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
    List<ExperienceFindingRecord>? findings,
    List<ExperienceConceptProposalRecord>? concepts,
    List<ExperienceReviewCommentRecord>? comments,
    AutomatedAcceptanceRecord? automatedAcceptance,
    List<ExperienceHumanDecisionRecord>? humanDecisions,
  }) {
    final result = ExperienceReviewPacket(
      id: packet.id,
      subject: packet.subject,
      changeSetId: packet.changeSetId,
      changeSetDigest: packet.changeSetDigest,
      comparisonDigest: packet.comparisonDigest,
      baseSourceDigest: packet.baseSourceDigest,
      findings: findings ?? packet.findings,
      concepts: concepts ?? packet.concepts,
      comments: comments ?? packet.comments,
      reviewGuideBinding: packet.reviewGuideBinding,
      automatedAcceptance: automatedAcceptance ?? packet.automatedAcceptance,
      humanDecisions: humanDecisions ?? packet.humanDecisions,
      revision: packet.revision + 1,
      previousReviewPacketDigest: packet.digest,
    );
    validatePacket(
      packet: result,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: allowedArtifactDigests,
    );
    return result;
  }

  void validatePacket({
    required ExperienceReviewPacket packet,
    required ExperienceChangeSet changeSet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
  }) {
    if (packet.subject != changeSet.subject ||
        packet.changeSetId != changeSet.id ||
        packet.changeSetDigest != changeSet.digest ||
        packet.comparisonDigest != changeSet.comparison.digest ||
        packet.baseSourceDigest != changeSet.baseSourceDigest ||
        topology.catalogDigest != catalog.digest ||
        changeSet.comparison.topologyDigest != topology.digest) {
      throw StateError('Review packet does not match its exact change set');
    }
    final projections = topology.projections
        .where((item) => item.id == packet.subject.projectionId)
        .toList(growable: false);
    if (projections.length != 1 ||
        projections.single.applicationId != packet.subject.applicationId) {
      throw StateError('Review packet projection is outside its application');
    }
    _validateReviewGuide(
      catalog,
      packet.reviewGuideBinding,
      applicationId: packet.subject.applicationId,
    );
    _validateReviewSubject(
      ExperienceReviewSubject.scenario(packet.reviewGuideBinding.scenarioId),
      packet: packet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: allowedArtifactDigests,
    );
    final changedNodeIds = changeSet.comparison.changedFrames
        .map((frame) => frame.nodeInstanceId)
        .toSet();
    final changedNodes = topology.nodes
        .where((node) => changedNodeIds.contains(node.id))
        .toList(growable: false);
    if (changedNodes.length != changedNodeIds.length ||
        changedNodes.any(
          (node) =>
              node.projectionId != packet.subject.projectionId ||
              node.scenarioId != packet.reviewGuideBinding.scenarioId,
        )) {
      throw StateError(
        'Every changed frame must be covered by the bound ReviewGuide scenario',
      );
    }
    for (final finding in packet.findings) {
      _validateReviewSubject(
        finding.subject,
        packet: packet,
        catalog: catalog,
        topology: topology,
        allowedArtifactDigests: allowedArtifactDigests,
      );
    }
    for (final comment in packet.comments) {
      _validateReviewSubject(
        comment.subject,
        packet: packet,
        catalog: catalog,
        topology: topology,
        allowedArtifactDigests: allowedArtifactDigests,
      );
    }
    final currentScenarioIds = catalog.scenarios
        .map((scenario) => scenario.id)
        .toSet();
    for (final concept in packet.concepts) {
      if (currentScenarioIds.contains(concept.scenarioId)) {
        throw StateError(
          'Concept proposal collides with an existing current catalog scenario',
        );
      }
    }
  }

  void _validateReviewSubject(
    ExperienceReviewSubject subject, {
    required ExperienceReviewPacket packet,
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
    required Set<Digest> allowedArtifactDigests,
  }) {
    switch (subject.kind) {
      case ExperienceReviewSubjectKind.scenario:
        final scenarios = catalog.scenarios
            .where(
              (scenario) =>
                  scenario.id == subject.scenarioId &&
                  scenario.applicationId == packet.subject.applicationId,
            )
            .toList(growable: false);
        final nodes = topology.nodes
            .where(
              (node) =>
                  node.projectionId == packet.subject.projectionId &&
                  node.scenarioId == subject.scenarioId,
            )
            .toList(growable: false);
        if (scenarios.length != 1 || nodes.isEmpty) {
          throw StateError('Review scenario subject is outside the projection');
        }
      case ExperienceReviewSubjectKind.transition:
        final transitions = catalog.transitions
            .where((transition) => transition.id == subject.transitionId)
            .toList(growable: false);
        final edges = topology.edges
            .where(
              (edge) =>
                  edge.projectionId == packet.subject.projectionId &&
                  edge.transitionId == subject.transitionId,
            )
            .toList(growable: false);
        if (transitions.length != 1 || edges.isEmpty) {
          throw StateError(
            'Review transition subject is outside the projection',
          );
        }
        final journeys = catalog.journeys
            .where(
              (journey) =>
                  journey.id == transitions.single.journeyId &&
                  journey.applicationId == packet.subject.applicationId,
            )
            .toList(growable: false);
        if (journeys.length != 1) {
          throw StateError(
            'Review transition subject is outside the application',
          );
        }
      case ExperienceReviewSubjectKind.artifact:
        if (!allowedArtifactDigests.contains(subject.artifactDigest)) {
          throw StateError('Review artifact subject is not explicitly allowed');
        }
    }
  }

  void _validateReviewGuide(
    CatalogManifest catalog,
    ExecutableReviewGuideBinding binding, {
    required ApplicationId applicationId,
  }) {
    if (catalog.digest != binding.catalogDigest ||
        binding.applicationId != applicationId) {
      throw StateError('ReviewGuide binding uses a stale catalog');
    }
    final guides = catalog.reviewGuides
        .where((guide) => guide.id == binding.reviewGuideId)
        .toList(growable: false);
    if (guides.length != 1 || guides.single.applicationId != applicationId) {
      throw StateError('ReviewGuide is outside the authoring application');
    }
    final steps = guides.single.steps
        .where((step) => step.id == binding.stepId)
        .toList(growable: false);
    if (steps.length != 1 ||
        steps.single.scenarioId != binding.scenarioId ||
        steps.single.bindingId != binding.bindingId) {
      throw StateError('ReviewGuide step does not grant the exact binding');
    }
    final executionBindings = catalog.executionBindings
        .where((item) => item.id == binding.bindingId)
        .toList(growable: false);
    if (executionBindings.length != 1 ||
        executionBindings.single.scenarioId != binding.scenarioId) {
      throw StateError('ReviewGuide execution binding is unavailable');
    }
  }
}
