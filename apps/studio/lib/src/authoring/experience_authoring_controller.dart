import 'dart:async';
import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../host/studio_host_client.dart';
import 'studio_experience_authoring_transport.dart';

enum ExperienceAuthoringControllerPhase {
  detached,
  loading,
  ready,
  submitting,
  conflict,
  protocolViolation,
  transportFailure,
  closed,
}

final class ExperienceAuthoringNodeView {
  const ExperienceAuthoringNodeView({
    required this.id,
    required this.scenarioId,
    required this.scenarioTitle,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.changed,
  });

  final NodeInstanceId id;
  final ScenarioId scenarioId;
  final String scenarioTitle;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool changed;
}

final class ExperienceAuthoringDraftView {
  ExperienceAuthoringDraftView({
    required this.id,
    required this.revision,
    required this.cursor,
    required this.historyLength,
    required this.candidateLayoutDigest,
    required List<ExperienceAuthoringNodeView> nodes,
  }) : nodes = List<ExperienceAuthoringNodeView>.unmodifiable(nodes);

  final LayoutDraftId id;
  final int revision;
  final int cursor;
  final int historyLength;
  final Digest candidateLayoutDigest;
  final List<ExperienceAuthoringNodeView> nodes;

  bool get canUndo => cursor > 0;
  bool get canRedo => cursor < historyLength;
  bool get canReset => historyLength > 0 || cursor > 0;
  bool get changed => cursor > 0;
}

final class ExperienceAuthoringFrameChangeView {
  const ExperienceAuthoringFrameChangeView({
    required this.nodeInstanceId,
    required this.beforeX,
    required this.beforeY,
    required this.afterX,
    required this.afterY,
  });

  final NodeInstanceId nodeInstanceId;
  final double beforeX;
  final double beforeY;
  final double afterX;
  final double afterY;
}

final class ExperienceAuthoringComparisonView {
  ExperienceAuthoringComparisonView({
    required this.changeSetId,
    required this.changeSetDigest,
    required this.beforeLayoutDigest,
    required this.afterLayoutDigest,
    required List<ExperienceAuthoringFrameChangeView> changedFrames,
  }) : changedFrames = List<ExperienceAuthoringFrameChangeView>.unmodifiable(
         changedFrames,
       );

  final ExperienceChangeSetId changeSetId;
  final Digest changeSetDigest;
  final Digest beforeLayoutDigest;
  final Digest afterLayoutDigest;
  final List<ExperienceAuthoringFrameChangeView> changedFrames;
}

final class ExperienceReviewSubjectOption {
  const ExperienceReviewSubjectOption({
    required this.key,
    required this.label,
    required this.subject,
  });

  final String key;
  final String label;
  final ExperienceReviewSubject subject;
}

final class ExperienceFindingView {
  const ExperienceFindingView({
    required this.subjectLabel,
    required this.severity,
    required this.summary,
    required this.detail,
    required this.recordedAt,
  });

  final String subjectLabel;
  final ExperienceFindingSeverity severity;
  final String summary;
  final String detail;
  final DateTime recordedAt;
}

final class ExperienceConceptView {
  const ExperienceConceptView({
    required this.scenarioId,
    required this.lifecycle,
    required this.title,
    required this.rationale,
    required this.recordedAt,
  });

  final ScenarioId scenarioId;
  final ScenarioLifecycle lifecycle;
  final String title;
  final String rationale;
  final DateTime recordedAt;
}

final class ExperienceCommentView {
  const ExperienceCommentView({
    required this.sequence,
    required this.subjectLabel,
    required this.body,
    required this.recordedAt,
  });

  final int sequence;
  final String subjectLabel;
  final String body;
  final DateTime recordedAt;
}

final class ExperienceAutomatedAcceptanceView {
  const ExperienceAutomatedAcceptanceView({
    required this.outcome,
    required this.summary,
    required this.recordedAt,
  });

  final AutomatedAcceptanceOutcome outcome;
  final String summary;
  final DateTime recordedAt;
}

final class ExperienceHumanDecisionView {
  const ExperienceHumanDecisionView({
    required this.sequence,
    required this.decision,
    required this.rationale,
    required this.recordedAt,
    required this.isHead,
  });

  final int sequence;
  final ExperienceHumanDecision decision;
  final String rationale;
  final DateTime recordedAt;
  final bool isHead;

  bool get isSuperseded => !isHead;
}

final class ExecutableReviewGuideView {
  const ExecutableReviewGuideView({
    required this.id,
    required this.title,
    required this.stepId,
    required this.instruction,
    required this.observationCriteria,
    required this.scenarioId,
    required this.bindingId,
    required this.labRoute,
  });

  final ReviewGuideId id;
  final String title;
  final String stepId;
  final String instruction;
  final String observationCriteria;
  final ScenarioId scenarioId;
  final ScenarioExecutionBindingId bindingId;
  final String? labRoute;
}

final class ExperienceAuthoringReviewView {
  ExperienceAuthoringReviewView({
    required this.packetId,
    required this.packetDigest,
    required this.revision,
    required this.guide,
    required this.syntheticConceptScenarioId,
    required this.automatedAcceptance,
    required this.promotable,
    required List<ExperienceReviewSubjectOption> subjectOptions,
    required List<ExperienceFindingView> findings,
    required List<ExperienceConceptView> concepts,
    required List<ExperienceCommentView> comments,
    required List<ExperienceHumanDecisionView> decisions,
  }) : subjectOptions = List<ExperienceReviewSubjectOption>.unmodifiable(
         subjectOptions,
       ),
       findings = List<ExperienceFindingView>.unmodifiable(findings),
       concepts = List<ExperienceConceptView>.unmodifiable(concepts),
       comments = List<ExperienceCommentView>.unmodifiable(comments),
       decisions = List<ExperienceHumanDecisionView>.unmodifiable(decisions);

  final ExperienceReviewPacketId packetId;
  final Digest packetDigest;
  final int revision;
  final ExecutableReviewGuideView guide;
  final ScenarioId syntheticConceptScenarioId;
  final ExperienceAutomatedAcceptanceView? automatedAcceptance;
  final bool promotable;
  final List<ExperienceReviewSubjectOption> subjectOptions;
  final List<ExperienceFindingView> findings;
  final List<ExperienceConceptView> concepts;
  final List<ExperienceCommentView> comments;
  final List<ExperienceHumanDecisionView> decisions;
}

final class ExperiencePromotionView {
  const ExperiencePromotionView({
    required this.id,
    required this.sequence,
    required this.resultContentSetDigest,
    required this.layoutDigest,
    required this.promotedAt,
  });

  final ExperiencePromotionReceiptId id;
  final int sequence;
  final Digest resultContentSetDigest;
  final Digest layoutDigest;
  final DateTime promotedAt;
}

final class ExperienceAuthoringControllerSnapshot {
  ExperienceAuthoringControllerSnapshot({
    required this.phase,
    required this.availability,
    required this.projectionId,
    required this.projectionTitle,
    required Set<AuthoringOperation> allowedOperations,
    required List<ExperienceAuthoringNodeView> baseNodes,
    required List<ExperiencePromotionView> promotions,
    required this.promotionTotalCount,
    required this.promotionHistoryTruncated,
    required this.draft,
    required this.comparison,
    required this.review,
    required this.latestPromotion,
    required this.failureCode,
    required this.pendingContentRefreshDigest,
  }) : allowedOperations = Set<AuthoringOperation>.unmodifiable(
         allowedOperations,
       ),
       baseNodes = List<ExperienceAuthoringNodeView>.unmodifiable(baseNodes),
       promotions = List<ExperiencePromotionView>.unmodifiable(promotions);

  final ExperienceAuthoringControllerPhase phase;
  final ExperienceAuthoringAvailability availability;
  final ExperienceProjectionId projectionId;
  final String projectionTitle;
  final Set<AuthoringOperation> allowedOperations;
  final List<ExperienceAuthoringNodeView> baseNodes;
  final List<ExperiencePromotionView> promotions;
  final int? promotionTotalCount;
  final bool promotionHistoryTruncated;
  final ExperienceAuthoringDraftView? draft;
  final ExperienceAuthoringComparisonView? comparison;
  final ExperienceAuthoringReviewView? review;
  final ExperiencePromotionView? latestPromotion;
  final ExperienceAuthoringErrorCode? failureCode;
  final Digest? pendingContentRefreshDigest;

  bool get isAuthor =>
      availability == ExperienceAuthoringAvailability.available;
  bool get isViewer =>
      availability == ExperienceAuthoringAvailability.policyDenied;
  bool get busy =>
      phase == ExperienceAuthoringControllerPhase.loading ||
      phase == ExperienceAuthoringControllerPhase.submitting;
  bool allows(AuthoringOperation operation) =>
      allowedOperations.contains(operation);
}

typedef ExperienceAuthoringStateListener =
    void Function(ExperienceAuthoringControllerSnapshot snapshot);
typedef ExperienceAuthoringRequestIdFactory =
    AuthoringRequestId Function(String purpose, int sequence);
typedef ExperiencePromotionRefresh =
    Future<void> Function(Digest expectedContentSetDigest);

/// Pure coordinator for the reference-consumer authoring route.
///
/// Full review packets and capability/grant records exist only in async method
/// locals. Published snapshots contain an attribution-free projection.
final class ExperienceAuthoringController {
  factory ExperienceAuthoringController({
    required StudioHostExperienceAuthoringClient? host,
    required CatalogManifest catalog,
    required ExperienceTopologyBundle bundle,
    required Digest contentSetDigest,
    required Digest resolvedPlanDigest,
    required ExperienceProjectionId projectionId,
    ScenarioLabManifest? scenarioLab,
    ExperienceAuthoringStateListener? onStateChanged,
    ExperiencePromotionRefresh? onPromotionRefresh,
    ExperienceAuthoringRequestIdFactory? requestIdFactory,
  }) {
    if (bundle.catalogDigest != catalog.digest ||
        (scenarioLab != null && scenarioLab.catalogDigest != catalog.digest)) {
      throw ArgumentError(
        'Experience Authoring requires one atomic Catalog generation',
      );
    }
    final projections = bundle.topology.projections
        .where((candidate) => candidate.id == projectionId)
        .toList(growable: false);
    final layouts = bundle.layouts
        .where((candidate) => candidate.projectionId == projectionId)
        .toList(growable: false);
    if (projections.length != 1 || layouts.length != 1) {
      throw ArgumentError(
        'Experience Authoring requires one exact Projection and layout',
      );
    }
    final projection = projections.single;
    if (projection.applicationId.value.isEmpty) {
      throw ArgumentError('Authoring Projection has no application');
    }
    return ExperienceAuthoringController._(
      host: host,
      catalog: catalog,
      bundle: bundle,
      contentSetDigest: contentSetDigest,
      resolvedPlanDigest: resolvedPlanDigest,
      projection: projection,
      baseLayout: layouts.single,
      scenarioLab: scenarioLab,
      onStateChanged: onStateChanged,
      onPromotionRefresh: onPromotionRefresh,
      requestIdFactory: requestIdFactory ?? _defaultRequestId,
    );
  }

  ExperienceAuthoringController._({
    required this.host,
    required this.catalog,
    required this.bundle,
    required this.contentSetDigest,
    required this.resolvedPlanDigest,
    required this.projection,
    required this.baseLayout,
    required this.scenarioLab,
    required this.onStateChanged,
    required this.onPromotionRefresh,
    required this._requestIdFactory,
  }) : subject = AuthoringSubjectRef(
         workspaceId: catalog.workspace.id,
         applicationId: projection.applicationId,
         projectionId: projection.id,
       );

  final StudioHostExperienceAuthoringClient? host;
  final CatalogManifest catalog;
  final ExperienceTopologyBundle bundle;
  final Digest contentSetDigest;
  final Digest resolvedPlanDigest;
  final ExperienceProjection projection;
  final ProjectionLayoutManifest baseLayout;
  final ScenarioLabManifest? scenarioLab;
  final AuthoringSubjectRef subject;
  final ExperienceAuthoringRequestIdFactory _requestIdFactory;
  ExperienceAuthoringStateListener? onStateChanged;
  final ExperiencePromotionRefresh? onPromotionRefresh;

  ExperienceAuthoringControllerPhase _phase =
      ExperienceAuthoringControllerPhase.detached;
  ExperienceAuthoringAvailability _availability =
      ExperienceAuthoringAvailability.unsupported;
  Set<AuthoringOperation> _allowedOperations = const <AuthoringOperation>{};
  LayoutDraft? _draft;
  ExperienceAuthoringDraftView? _draftView;
  ExperienceAuthoringComparisonView? _comparisonView;
  ExperienceAuthoringReviewView? _reviewView;
  ExperiencePromotionView? _latestPromotion;
  List<ExperiencePromotionView> _promotions = const <ExperiencePromotionView>[];
  int? _promotionTotalCount;
  var _promotionHistoryTruncated = false;
  ExperienceAuthoringErrorCode? _failureCode;
  Digest? _pendingContentRefreshDigest;
  var _epoch = 0;
  var _requestSequence = 0;

  ExperienceAuthoringControllerSnapshot get snapshot =>
      ExperienceAuthoringControllerSnapshot(
        phase: _phase,
        availability: _availability,
        projectionId: projection.id,
        projectionTitle: projection.title,
        allowedOperations: _allowedOperations,
        baseNodes: _nodesFor(baseLayout),
        promotions: _promotions,
        promotionTotalCount: _promotionTotalCount,
        promotionHistoryTruncated: _promotionHistoryTruncated,
        draft: _draftView,
        comparison: _comparisonView,
        review: _reviewView,
        latestPromotion: _latestPromotion,
        failureCode: _failureCode,
        pendingContentRefreshDigest: _pendingContentRefreshDigest,
      );

  void setStateListener(ExperienceAuthoringStateListener? listener) {
    onStateChanged = listener;
  }

  Future<void> load() async {
    if (_phase == ExperienceAuthoringControllerPhase.closed) return;
    final activeHost = host;
    final operationEpoch = ++_epoch;
    _failureCode = null;
    _transition(ExperienceAuthoringControllerPhase.loading);
    if (activeHost == null) {
      _clearMutableState();
      _availability = ExperienceAuthoringAvailability.unsupported;
      _allowedOperations = const <AuthoringOperation>{};
      _transition(ExperienceAuthoringControllerPhase.ready);
      return;
    }
    try {
      final description = await _describe(activeHost, 'load');
      if (!_isCurrent(operationEpoch)) return;
      _acceptDescription(description);
      if (description.availability ==
          ExperienceAuthoringAvailability.unsupported) {
        _clearMutableState();
        _transition(ExperienceAuthoringControllerPhase.ready);
        return;
      }
      if (!description.allowedOperations.contains(
        AuthoringOperation.getSubjectHead,
      )) {
        _clearMutableState();
        _transition(ExperienceAuthoringControllerPhase.ready);
        return;
      }
      final headRequest = ExperienceAuthoringSubjectHeadRequest(
        requestId: _nextRequestId('head'),
        subject: subject,
      );
      final headResult = await activeHost.getExperienceAuthoringHead(
        headRequest,
      );
      headResult.validateAgainst(headRequest);
      if (!_isCurrent(operationEpoch)) return;
      await _loadHead(activeHost, headResult.head, operationEpoch);
      if (_isCurrent(operationEpoch)) {
        _transition(ExperienceAuthoringControllerPhase.ready);
      }
    } on Object catch (error) {
      _handleFailure(operationEpoch, error);
    }
  }

  Future<void> refresh() => load();

  Future<void> _loadHead(
    StudioHostExperienceAuthoringClient activeHost,
    ExperienceAuthoringSubjectHead head,
    int operationEpoch,
  ) async {
    _clearMutableState();
    if (head.draft case final draftHead?) {
      if (_allowedOperations.contains(AuthoringOperation.getDraft)) {
        final request = LayoutDraftGetRequest(
          requestId: _nextRequestId('draft-get'),
          subject: subject,
          draftId: draftHead.id,
          expectedDraftDigest: draftHead.digest,
        );
        final result = await activeHost.getExperienceLayoutDraft(request);
        result.validateAgainst(request);
        if (!_isCurrent(operationEpoch)) return;
        _acceptDraft(result.draft);
      }
      if (head.review != null && head.changeSet != null) {
        final pair = await _readReviewPair(
          activeHost,
          head,
          operationEpoch: operationEpoch,
        );
        if (!_isCurrent(operationEpoch)) return;
        if (pair != null) _acceptReview(pair.changeSet, pair.packet);
      }
    }
    if (head.latestPromotion case final promotionHead?
        when _allowedOperations.contains(AuthoringOperation.getPromotion)) {
      final request = ExperiencePromotionGetRequest(
        requestId: _nextRequestId('promotion-get'),
        subject: subject,
        receiptId: promotionHead.id,
        expectedReceiptDigest: promotionHead.digest,
      );
      final result = await activeHost.getExperiencePromotion(request);
      result.validateAgainst(request);
      if (!_isCurrent(operationEpoch)) return;
      _latestPromotion = _promotionView(result.receipt);
      if (head.draft == null) {
        final pair = await _readReviewPair(
          activeHost,
          head,
          operationEpoch: operationEpoch,
          changeSetId: result.receipt.changeSetId,
          changeSetDigest: result.receipt.changeSetDigest,
          reviewPacketId: result.receipt.reviewPacketId,
          reviewPacketDigest: result.receipt.reviewPacketDigest,
        );
        if (!_isCurrent(operationEpoch)) return;
        if (pair != null) _acceptReview(pair.changeSet, pair.packet);
      }
    }
    if (_allowedOperations.contains(AuthoringOperation.getPromotionHistory)) {
      await _loadPromotionHistory(activeHost, head, operationEpoch);
    }
  }

  Future<void> _loadPromotionHistory(
    StudioHostExperienceAuthoringClient activeHost,
    ExperienceAuthoringSubjectHead head,
    int operationEpoch,
  ) async {
    final probeRequest = ExperiencePromotionHistoryRequest(
      requestId: _nextRequestId('promotion-history-probe'),
      subject: subject,
      offset: 0,
      limit: 1,
    );
    final probe = await activeHost.getExperiencePromotionHistory(probeRequest);
    probe.validateAgainst(probeRequest);
    _validatePromotionHistoryPage(probe);
    if (!_isCurrent(operationEpoch)) return;
    final totalCount = probe.totalCount;
    var finalPage = probe;
    if (totalCount > probe.receipts.length) {
      final finalOffset = totalCount > experienceAuthoringMaxPromotionReceipts
          ? totalCount - experienceAuthoringMaxPromotionReceipts
          : 0;
      final finalRequest = ExperiencePromotionHistoryRequest(
        requestId: _nextRequestId('promotion-history-final'),
        subject: subject,
        offset: finalOffset,
        limit: experienceAuthoringMaxPromotionReceipts,
      );
      final result = await activeHost.getExperiencePromotionHistory(
        finalRequest,
      );
      result.validateAgainst(finalRequest);
      _validatePromotionHistoryPage(result);
      if (!_isCurrent(operationEpoch)) return;
      if (result.totalCount != totalCount ||
          (finalOffset == 0 &&
              probe.receipts.firstOrNull?.digest !=
                  result.receipts.firstOrNull?.digest) ||
          (finalOffset == probe.receipts.length &&
              result.previousPageReceiptDigest !=
                  probe.receipts.lastOrNull?.digest)) {
        throw const FormatException(
          'Promotion history changed or disconnected between probe and final page',
        );
      }
      finalPage = result;
    }
    finalPage.validateLatestHead(head);
    if (!_isCurrent(operationEpoch)) return;
    final receipts = finalPage.receipts;
    _promotions = receipts.map(_promotionView).toList(growable: false);
    _promotionTotalCount = totalCount;
    _promotionHistoryTruncated = totalCount > receipts.length;
    if (receipts.lastOrNull case final latest?) {
      _latestPromotion = _promotionView(latest);
    }
  }

  void _validatePromotionHistoryPage(ExperiencePromotionHistoryResult result) {
    var previousDigest = result.previousPageReceiptDigest;
    for (final receipt in result.receipts) {
      if (receipt.previousReceiptDigest != previousDigest) {
        throw const FormatException(
          'Promotion history page contains a disconnected receipt chain',
        );
      }
      previousDigest = receipt.digest;
    }
  }

  Future<_TransientReviewPair?> _readReviewPair(
    StudioHostExperienceAuthoringClient activeHost,
    ExperienceAuthoringSubjectHead head, {
    required int operationEpoch,
    ExperienceChangeSetId? changeSetId,
    Digest? changeSetDigest,
    ExperienceReviewPacketId? reviewPacketId,
    Digest? reviewPacketDigest,
  }) async {
    if (!_allowedOperations.contains(AuthoringOperation.getChangeSet) ||
        !_allowedOperations.contains(AuthoringOperation.getReview)) {
      return null;
    }
    final selectedChangeSetId = changeSetId ?? head.changeSet?.id;
    final selectedChangeSetDigest = changeSetDigest ?? head.changeSet?.digest;
    final selectedReviewId = reviewPacketId ?? head.review?.id;
    final selectedReviewDigest = reviewPacketDigest ?? head.review?.digest;
    if (selectedChangeSetId == null ||
        selectedChangeSetDigest == null ||
        selectedReviewId == null ||
        selectedReviewDigest == null) {
      throw const FormatException('Experience review heads are incomplete');
    }
    final changeRequest = ExperienceChangeSetGetRequest(
      requestId: _nextRequestId('changeset-get'),
      subject: subject,
      changeSetId: selectedChangeSetId,
      expectedChangeSetDigest: selectedChangeSetDigest,
    );
    final changeResult = await activeHost.getExperienceChangeSet(changeRequest);
    changeResult.validateAgainst(changeRequest);
    if (!_isCurrent(operationEpoch)) return null;
    final reviewRequest = ExperienceReviewGetRequest(
      requestId: _nextRequestId('review-get'),
      subject: subject,
      reviewPacketId: selectedReviewId,
      expectedReviewPacketDigest: selectedReviewDigest,
    );
    final reviewResult = await activeHost.getExperienceReview(reviewRequest);
    reviewResult.validateAgainst(reviewRequest);
    reviewResult.validateWithChangeSet(changeResult);
    if (!_isCurrent(operationEpoch)) return null;
    return (
      changeSet: changeResult.changeSet,
      packet: reviewResult.reviewPacket,
    );
  }

  void _acceptDescription(ExperienceAuthoringDescription description) {
    final capability = description.capability;
    if (description.subject != subject ||
        description.currentContentSetDigest != contentSetDigest ||
        description.currentTopologyDigest != bundle.topology.digest ||
        description.currentLayoutDigest != baseLayout.digest ||
        (capability != null &&
            capability.resolvedPlanDigest != resolvedPlanDigest)) {
      throw const FormatException(
        'Experience Authoring description belongs to another generation',
      );
    }
    _availability = description.availability;
    _allowedOperations = description.allowedOperations;
  }

  Future<ExperienceAuthoringDescription> _describe(
    StudioHostExperienceAuthoringClient activeHost,
    String purpose,
  ) async {
    final request = ExperienceAuthoringDescribeRequest(
      requestId: _nextRequestId('describe-$purpose'),
      subject: subject,
    );
    final result = await activeHost.describeExperienceAuthoring(request);
    result.validateAgainst(request);
    return result;
  }

  Future<void> openDraft() => _submit(AuthoringOperation.openDraft, (
    activeHost,
    capability,
    description,
    operationEpoch,
  ) async {
    if (_draft != null) return;
    final sourceDigest = description.currentSourceDigest;
    if (sourceDigest == null) {
      throw const FormatException('Authoring source identity is absent');
    }
    final effectRequestId = _nextRequestId('draft-open-effect');
    final provisional = LayoutDraftOpenRequest(
      requestId: effectRequestId,
      subject: subject,
      expectedContentSetDigest: description.currentContentSetDigest,
      expectedSourceDigest: sourceDigest,
      grantId: _transientGrantId(),
      grantDigest: _transientGrantDigest(),
    );
    final intent = AuthoringGrantRequest(
      requestId: _nextRequestId('draft-open-grant'),
      capabilityDigest: capability.digest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.openDraft,
      expectedDigest: description.currentContentSetDigest,
      expectedSourceDigest: sourceDigest,
      payloadDigest: provisional.payloadDigest,
    );
    final grant = await _requestGrant(activeHost, intent, operationEpoch);
    if (grant == null) return;
    final request = LayoutDraftOpenRequest(
      requestId: effectRequestId,
      subject: subject,
      expectedContentSetDigest: description.currentContentSetDigest,
      expectedSourceDigest: sourceDigest,
      grantId: grant.id,
      grantDigest: grant.digest,
    );
    request.validateAgainstGrantIntent(intent);
    final result = await activeHost.openExperienceLayoutDraft(request);
    result.validateAgainst(request);
    if (!_isCurrent(operationEpoch)) return;
    _acceptDraft(result.draft);
    _comparisonView = null;
    _reviewView = null;
  });

  Future<void> abandonDraft() => _submit(AuthoringOperation.abandonDraft, (
    activeHost,
    capability,
    description,
    operationEpoch,
  ) async {
    final draft = _draft;
    if (draft == null) return;
    final effectRequestId = _nextRequestId('draft-abandon-effect');
    final provisional = LayoutDraftAbandonRequest(
      requestId: effectRequestId,
      subject: subject,
      draftId: draft.id,
      expectedDraftDigest: draft.digest,
      expectedDraftRevision: draft.revision,
      expectedSourceDigest: draft.baseSourceDigest,
      grantId: _transientGrantId(),
      grantDigest: _transientGrantDigest(),
    );
    final intent = AuthoringGrantRequest(
      requestId: _nextRequestId('draft-abandon-grant'),
      capabilityDigest: capability.digest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.abandonDraft,
      expectedDigest: draft.digest,
      expectedSourceDigest: draft.baseSourceDigest,
      payloadDigest: provisional.payloadDigest,
    );
    final grant = await _requestGrant(activeHost, intent, operationEpoch);
    if (grant == null) return;
    final request = LayoutDraftAbandonRequest(
      requestId: effectRequestId,
      subject: subject,
      draftId: draft.id,
      expectedDraftDigest: draft.digest,
      expectedDraftRevision: draft.revision,
      expectedSourceDigest: draft.baseSourceDigest,
      grantId: grant.id,
      grantDigest: grant.digest,
    );
    request.validateAgainstGrantIntent(intent);
    final result = await activeHost.abandonExperienceLayoutDraft(request);
    result.validateAgainst(request);
    if (!_isCurrent(operationEpoch)) return;
    _draft = null;
    _draftView = null;
    _comparisonView = null;
    _reviewView = null;
  });

  Future<void> restartDraft() async {
    if (_draft != null) {
      await abandonDraft();
      if (_phase != ExperienceAuthoringControllerPhase.ready ||
          _draft != null) {
        return;
      }
    }
    await openDraft();
  }

  Future<void> moveNode(
    NodeInstanceId nodeInstanceId, {
    required double toX,
    required double toY,
  }) {
    if (!_validCoordinate(toX) || !_validCoordinate(toY)) {
      return _rejectInvalidInput();
    }
    return _mutateDraft(
      mutation: LayoutDraftMutation.applyMove,
      move: LayoutMoveNodeInput(
        nodeInstanceId: nodeInstanceId,
        toX: toX,
        toY: toY,
      ),
    );
  }

  Future<void> moveNodeBy(
    NodeInstanceId nodeInstanceId, {
    required double dx,
    required double dy,
  }) {
    final node = _draftView?.nodes
        .where((candidate) => candidate.id == nodeInstanceId)
        .singleOrNull;
    if (node == null) return Future<void>.value();
    return moveNode(nodeInstanceId, toX: node.x + dx, toY: node.y + dy);
  }

  Future<void> undo() => _mutateDraft(mutation: LayoutDraftMutation.undo);

  Future<void> redo() => _mutateDraft(mutation: LayoutDraftMutation.redo);

  Future<void> reset() => _mutateDraft(mutation: LayoutDraftMutation.reset);

  Future<void> _mutateDraft({
    required LayoutDraftMutation mutation,
    LayoutMoveNodeInput? move,
  }) {
    final operation = switch (mutation) {
      LayoutDraftMutation.applyMove => AuthoringOperation.moveNode,
      LayoutDraftMutation.undo => AuthoringOperation.undo,
      LayoutDraftMutation.redo => AuthoringOperation.redo,
      LayoutDraftMutation.reset => AuthoringOperation.reset,
    };
    return _submit(operation, (
      activeHost,
      capability,
      description,
      operationEpoch,
    ) async {
      final draft = _draft;
      if (draft == null) return;
      final effectRequestId = _nextRequestId('draft-${mutation.name}-effect');
      final provisional = LayoutDraftMutationRequest(
        requestId: effectRequestId,
        draftId: draft.id,
        expectedDraftDigest: draft.digest,
        expectedDraftRevision: draft.revision,
        grantId: _transientGrantId(),
        grantDigest: _transientGrantDigest(),
        mutation: mutation,
        move: move,
      );
      final intent = AuthoringGrantRequest(
        requestId: _nextRequestId('draft-${mutation.name}-grant'),
        capabilityDigest: capability.digest,
        subject: subject,
        effect: AuthoringActionEffect.authoring,
        operation: operation,
        expectedDigest: draft.digest,
        expectedSourceDigest: draft.baseSourceDigest,
        payloadDigest: provisional.payloadDigest,
      );
      final grant = await _requestGrant(activeHost, intent, operationEpoch);
      if (grant == null) return;
      final request = LayoutDraftMutationRequest(
        requestId: effectRequestId,
        draftId: draft.id,
        expectedDraftDigest: draft.digest,
        expectedDraftRevision: draft.revision,
        grantId: grant.id,
        grantDigest: grant.digest,
        mutation: mutation,
        move: move,
      );
      request.validateAgainstGrantIntent(intent, draft: draft);
      final result = await activeHost.mutateExperienceLayoutDraft(
        request,
        subject: subject,
      );
      result.validateAgainst(request, previousDraft: draft);
      if (!_isCurrent(operationEpoch)) return;
      _acceptDraft(result.draft);
      _comparisonView = null;
      _reviewView = null;
    });
  }

  Future<void> prepareReview() => _submit(AuthoringOperation.prepareReview, (
    activeHost,
    capability,
    description,
    operationEpoch,
  ) async {
    final draft = _draft;
    if (draft == null || draft.cursor == 0) return;
    final selection = _selectReviewGuide();
    final effectRequestId = _nextRequestId('review-prepare-effect');
    final provisional = ExperienceReviewPrepareRequest(
      requestId: effectRequestId,
      subject: subject,
      draftId: draft.id,
      expectedDraftDigest: draft.digest,
      expectedDraftRevision: draft.revision,
      expectedContentSetDigest: draft.contentSetDigest,
      expectedSourceDigest: draft.baseSourceDigest,
      reviewGuideId: selection.guide.id,
      reviewGuideStepId: selection.step.id,
      grantId: _transientGrantId(),
      grantDigest: _transientGrantDigest(),
    );
    final intent = AuthoringGrantRequest(
      requestId: _nextRequestId('review-prepare-grant'),
      capabilityDigest: capability.digest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.prepareReview,
      expectedDigest: draft.digest,
      expectedSourceDigest: draft.baseSourceDigest,
      payloadDigest: provisional.payloadDigest,
    );
    final grant = await _requestGrant(activeHost, intent, operationEpoch);
    if (grant == null) return;
    final request = ExperienceReviewPrepareRequest(
      requestId: effectRequestId,
      subject: subject,
      draftId: draft.id,
      expectedDraftDigest: draft.digest,
      expectedDraftRevision: draft.revision,
      expectedContentSetDigest: draft.contentSetDigest,
      expectedSourceDigest: draft.baseSourceDigest,
      reviewGuideId: selection.guide.id,
      reviewGuideStepId: selection.step.id,
      grantId: grant.id,
      grantDigest: grant.digest,
    );
    request.validateAgainstGrantIntent(intent);
    final result = await activeHost.prepareExperienceReview(request);
    result.validateAgainst(request, draft: draft);
    if (!_isCurrent(operationEpoch)) return;
    _acceptReview(result.changeSet, result.reviewPacket);
  });

  Future<void> appendFinding({
    required ExperienceReviewSubject subject,
    required ExperienceFindingSeverity severity,
    required String summary,
    required String detail,
  }) {
    if (!_validText(summary, 512) || !_validText(detail, 2048)) {
      return _rejectInvalidInput();
    }
    return _applyReviewAction(
      operation: AuthoringOperation.appendFinding,
      finding: AppendExperienceFindingInput(
        subject: subject,
        severity: severity,
        summary: summary,
        detail: detail,
      ),
    );
  }

  Future<void> proposeConcept({
    required String title,
    required String rationale,
  }) {
    if (!_validText(title, 256) || !_validText(rationale, 1024)) {
      return _rejectInvalidInput();
    }
    final scenarioId = _reviewView?.syntheticConceptScenarioId;
    if (scenarioId == null) return Future<void>.value();
    return _applyReviewAction(
      operation: AuthoringOperation.proposeConcept,
      concept: ProposeExperienceConceptInput(
        scenarioId: scenarioId,
        title: title,
        rationale: rationale,
      ),
    );
  }

  Future<void> appendComment({
    required ExperienceReviewSubject subject,
    required String body,
  }) {
    if (!_validText(body, 1024)) return _rejectInvalidInput();
    return _applyReviewAction(
      operation: AuthoringOperation.appendComment,
      comment: AppendExperienceReviewCommentInput(subject: subject, body: body),
    );
  }

  Future<void> evaluateAutomatedAcceptance() {
    if (_reviewView?.automatedAcceptance != null) return Future<void>.value();
    return _applyReviewAction(
      operation: AuthoringOperation.evaluateAutomatedAcceptance,
    );
  }

  Future<void> decide({
    required ExperienceHumanDecision decision,
    required String rationale,
  }) {
    if (!_validText(rationale, 1024)) return _rejectInvalidInput();
    return _applyReviewAction(
      operation: AuthoringOperation.decideReview,
      decision: AppendExperienceHumanDecisionInput(
        decision: decision,
        rationale: rationale,
      ),
    );
  }

  Future<void> _applyReviewAction({
    required AuthoringOperation operation,
    AppendExperienceFindingInput? finding,
    ProposeExperienceConceptInput? concept,
    AppendExperienceReviewCommentInput? comment,
    AppendExperienceHumanDecisionInput? decision,
  }) => _submit(operation, (
    activeHost,
    capability,
    description,
    operationEpoch,
  ) async {
    if (!_allowedOperations.contains(AuthoringOperation.getSubjectHead)) return;
    final head = await _getCurrentHead(activeHost);
    if (!_isCurrent(operationEpoch)) return;
    final draft = _draft;
    if (head.review == null ||
        head.changeSet == null ||
        draft == null ||
        head.draft?.digest != draft.digest) {
      throw const _ExperienceAuthoringLocalConflict();
    }
    final pair = await _readReviewPair(
      activeHost,
      head,
      operationEpoch: operationEpoch,
    );
    if (!_isCurrent(operationEpoch) || pair == null) return;
    if (operation == AuthoringOperation.evaluateAutomatedAcceptance &&
        pair.packet.automatedAcceptance != null) {
      return;
    }
    final fence = ExperienceReviewMutationFence(
      subject: subject,
      changeSetId: pair.changeSet.id,
      changeSetDigest: pair.changeSet.digest,
      reviewPacketId: pair.packet.id,
      reviewPacketDigest: pair.packet.digest,
      reviewPacketRevision: pair.packet.revision,
      expectedSourceDigest: pair.changeSet.baseSourceDigest,
      expectedContentSetDigest: pair.changeSet.expectedContentSetDigest,
    );
    final effectRequestId = _nextRequestId('review-${operation.name}-effect');
    final acceptanceDigest = operation == AuthoringOperation.decideReview
        ? pair.packet.automatedAcceptance?.digest
        : null;
    if (operation == AuthoringOperation.decideReview &&
        acceptanceDigest == null) {
      throw const _ExperienceAuthoringLocalConflict();
    }
    final provisional = ExperienceReviewActionRequest(
      requestId: effectRequestId,
      fence: fence,
      operation: operation,
      grantId: _transientGrantId(),
      grantDigest: _transientGrantDigest(),
      finding: finding,
      concept: concept,
      comment: comment,
      decision: decision,
      expectedAutomatedAcceptanceDigest: acceptanceDigest,
    );
    final AuthoringGrantIntent intent;
    final AuthoringActionGrant grant;
    if (operation == AuthoringOperation.decideReview) {
      final decisionIntent = ExperienceReviewDecisionGrantRequest(
        requestId: _nextRequestId('review-${operation.name}-grant'),
        capabilityDigest: capability.digest,
        fence: fence,
        decision: decision!,
        automatedAcceptanceDigest: acceptanceDigest!,
      );
      intent = decisionIntent;
      if (!_isCurrent(operationEpoch)) return;
      final result = await activeHost.requestExperienceDecisionGrant(
        decisionIntent,
      );
      result.validateAgainst(decisionIntent);
      if (!_isCurrent(operationEpoch)) return;
      grant = result.grant;
    } else {
      final genericIntent = AuthoringGrantRequest(
        requestId: _nextRequestId('review-${operation.name}-grant'),
        capabilityDigest: capability.digest,
        subject: subject,
        effect: authoringEffectFor(operation),
        operation: operation,
        expectedDigest: pair.packet.digest,
        expectedSourceDigest: pair.changeSet.baseSourceDigest,
        payloadDigest: provisional.payloadDigest,
      );
      intent = genericIntent;
      if (!_isCurrent(operationEpoch)) return;
      final result = await activeHost.requestExperienceAuthoringGrant(
        genericIntent,
      );
      result.validateAgainst(genericIntent);
      if (!_isCurrent(operationEpoch)) return;
      grant = result.grant;
    }
    final request = ExperienceReviewActionRequest(
      requestId: effectRequestId,
      fence: fence,
      operation: operation,
      grantId: grant.id,
      grantDigest: grant.digest,
      finding: finding,
      concept: concept,
      comment: comment,
      decision: decision,
      expectedAutomatedAcceptanceDigest: acceptanceDigest,
    );
    request.validateAgainstGrantIntent(intent);
    final result = await activeHost.applyExperienceReviewAction(request);
    result.validateAgainst(
      request,
      changeSet: pair.changeSet,
      previousPacket: pair.packet,
    );
    if (!_isCurrent(operationEpoch)) return;
    _acceptReview(pair.changeSet, result.reviewPacket);
  });

  Future<void> promote() => _submit(AuthoringOperation.promote, (
    activeHost,
    capability,
    description,
    operationEpoch,
  ) async {
    final draft = _draft;
    if (draft == null) return;
    if (!_allowedOperations.contains(AuthoringOperation.getSubjectHead)) return;
    final head = await _getCurrentHead(activeHost);
    if (!_isCurrent(operationEpoch)) return;
    if (head.draft?.digest != draft.digest ||
        head.review == null ||
        head.changeSet == null) {
      throw const _ExperienceAuthoringLocalConflict();
    }
    final pair = await _readReviewPair(
      activeHost,
      head,
      operationEpoch: operationEpoch,
    );
    if (!_isCurrent(operationEpoch) || pair == null) return;
    if (!pair.packet.isPromotable) return;
    final effectRequestId = _nextRequestId('promotion-effect');
    final intent = ExperiencePromotionGrantRequest(
      requestId: _nextRequestId('promotion-grant'),
      capabilityDigest: capability.digest,
      subject: subject,
      draftId: draft.id,
      draftDigest: draft.digest,
      draftRevision: draft.revision,
      changeSetId: pair.changeSet.id,
      changeSetDigest: pair.changeSet.digest,
      reviewPacketId: pair.packet.id,
      reviewPacketDigest: pair.packet.digest,
      expectedSourceDigest: draft.baseSourceDigest,
      expectedContentSetDigest: draft.contentSetDigest,
      candidateLayoutDigest: draft.candidateLayoutDigest,
    );
    intent.validateAgainst(
      draft: draft,
      changeSet: pair.changeSet,
      reviewPacket: pair.packet,
    );
    if (!_isCurrent(operationEpoch)) return;
    final grantResult = await activeHost.requestExperiencePromotionGrant(
      intent,
    );
    grantResult.validateAgainst(intent);
    if (!_isCurrent(operationEpoch)) return;
    final grant = grantResult.grant;
    final request = ExperiencePromotionApplyRequest(
      requestId: effectRequestId,
      subject: subject,
      draftId: draft.id,
      draftDigest: draft.digest,
      draftRevision: draft.revision,
      changeSetId: pair.changeSet.id,
      changeSetDigest: pair.changeSet.digest,
      reviewPacketId: pair.packet.id,
      reviewPacketDigest: pair.packet.digest,
      expectedSourceDigest: draft.baseSourceDigest,
      expectedContentSetDigest: draft.contentSetDigest,
      candidateLayoutDigest: draft.candidateLayoutDigest,
      grantId: grant.id,
      grantDigest: grant.digest,
    );
    request.validateAgainst(intent);
    final result = await activeHost.applyExperiencePromotion(request);
    result.validateAgainst(request);
    if (!_isCurrent(operationEpoch)) return;
    final promotion = _promotionView(result.receipt);
    _draft = null;
    _draftView = null;
    _latestPromotion = promotion;
    final promotions = <ExperiencePromotionView>[..._promotions, promotion];
    _promotions = promotions.length <= experienceAuthoringMaxPromotionReceipts
        ? promotions
        : promotions.sublist(
            promotions.length - experienceAuthoringMaxPromotionReceipts,
          );
    if (_promotionTotalCount case final totalCount?) {
      _promotionTotalCount = totalCount + 1;
      _promotionHistoryTruncated = _promotionTotalCount! > _promotions.length;
    }
    _pendingContentRefreshDigest = result.receipt.resultContentSetDigest;
    _notify();
    final refresh = onPromotionRefresh;
    if (refresh != null) {
      try {
        await refresh(result.receipt.resultContentSetDigest);
      } on Object {
        // Promotion already committed. The Host event remains authoritative
        // and the pending digest keeps the UI honest until refresh succeeds.
      }
    }
  });

  Future<ExperienceAuthoringSubjectHead> _getCurrentHead(
    StudioHostExperienceAuthoringClient activeHost,
  ) async {
    final request = ExperienceAuthoringSubjectHeadRequest(
      requestId: _nextRequestId('head-current'),
      subject: subject,
    );
    final result = await activeHost.getExperienceAuthoringHead(request);
    result.validateAgainst(request);
    return result.head;
  }

  Future<AuthoringActionGrant?> _requestGrant(
    StudioHostExperienceAuthoringClient activeHost,
    AuthoringGrantRequest intent,
    int operationEpoch,
  ) async {
    final result = await activeHost.requestExperienceAuthoringGrant(intent);
    result.validateAgainst(intent);
    return _isCurrent(operationEpoch) ? result.grant : null;
  }

  Future<void> _submit(
    AuthoringOperation operation,
    Future<void> Function(
      StudioHostExperienceAuthoringClient host,
      AuthoringCapability capability,
      ExperienceAuthoringDescription description,
      int operationEpoch,
    )
    action,
  ) async {
    if (_phase == ExperienceAuthoringControllerPhase.closed ||
        _phase == ExperienceAuthoringControllerPhase.loading ||
        _phase == ExperienceAuthoringControllerPhase.submitting) {
      return;
    }
    final activeHost = host;
    if (activeHost == null) return;
    final operationEpoch = ++_epoch;
    _failureCode = null;
    _transition(ExperienceAuthoringControllerPhase.submitting);
    try {
      final description = await _describe(activeHost, operation.name);
      if (!_isCurrent(operationEpoch)) return;
      _acceptDescription(description);
      final capability = description.capability;
      if (description.availability !=
              ExperienceAuthoringAvailability.available ||
          capability == null ||
          !description.allowedOperations.contains(operation)) {
        _transition(ExperienceAuthoringControllerPhase.ready);
        return;
      }
      await action(activeHost, capability, description, operationEpoch);
      if (_isCurrent(operationEpoch)) {
        _transition(ExperienceAuthoringControllerPhase.ready);
      }
    } on Object catch (error) {
      _handleFailure(operationEpoch, error);
    }
  }

  void _acceptDraft(LayoutDraft draft) {
    if (draft.subject != subject ||
        draft.contentSetDigest != contentSetDigest ||
        draft.baseLayoutDigest != baseLayout.digest ||
        draft.topologyDigest != bundle.topology.digest) {
      throw const FormatException(
        'Experience layout draft belongs to another generation',
      );
    }
    final materialized = const LayoutDraftEngine().materialize(
      draft: draft,
      baseLayout: baseLayout,
    );
    _draft = draft;
    _draftView = ExperienceAuthoringDraftView(
      id: draft.id,
      revision: draft.revision,
      cursor: draft.cursor,
      historyLength: draft.history.length,
      candidateLayoutDigest: materialized.digest,
      nodes: _nodesFor(materialized),
    );
  }

  _ReviewGuideSelection _selectReviewGuide() {
    final changedScenarioIds = _draftView?.nodes
        .where((node) => node.changed)
        .map((node) => node.scenarioId)
        .toSet();
    if (changedScenarioIds == null || changedScenarioIds.length != 1) {
      throw StateError(
        'One ReviewGuide scenario must cover every changed frame',
      );
    }
    final scenarioId = changedScenarioIds.single;
    final bindings = <ScenarioExecutionBindingId>{
      for (final binding in catalog.executionBindings)
        if (binding.scenarioId == scenarioId) binding.id,
    };
    final candidates = <_ReviewGuideSelection>[
      for (final guide in catalog.reviewGuides)
        if (guide.applicationId == subject.applicationId)
          for (final step in guide.steps)
            if (step.scenarioId == scenarioId &&
                bindings.contains(step.bindingId))
              (guide: guide, step: step),
    ];
    candidates.sort((left, right) {
      final leftExecutable =
          _labRouteFor(left.step.scenarioId, left.step.bindingId) != null;
      final rightExecutable =
          _labRouteFor(right.step.scenarioId, right.step.bindingId) != null;
      if (leftExecutable != rightExecutable) return leftExecutable ? -1 : 1;
      final byGuide = left.guide.id.value.compareTo(right.guide.id.value);
      return byGuide != 0 ? byGuide : left.step.id.compareTo(right.step.id);
    });
    if (candidates.isEmpty) {
      throw StateError('No exact ReviewGuide covers the changed frame');
    }
    return candidates.first;
  }

  void _acceptReview(
    ExperienceChangeSet changeSet,
    ExperienceReviewPacket packet,
  ) {
    final allowedArtifacts = _allowedArtifactDigestsFor(
      packet.reviewGuideBinding,
    );
    const ExperienceReviewPacketCompiler().validatePacket(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: bundle.topology,
      allowedArtifactDigests: allowedArtifacts,
    );
    _comparisonView = ExperienceAuthoringComparisonView(
      changeSetId: changeSet.id,
      changeSetDigest: changeSet.digest,
      beforeLayoutDigest: changeSet.comparison.beforeLayoutDigest,
      afterLayoutDigest: changeSet.comparison.afterLayoutDigest,
      changedFrames: <ExperienceAuthoringFrameChangeView>[
        for (final frame in changeSet.comparison.changedFrames)
          ExperienceAuthoringFrameChangeView(
            nodeInstanceId: frame.nodeInstanceId,
            beforeX: frame.beforeX,
            beforeY: frame.beforeY,
            afterX: frame.afterX,
            afterY: frame.afterY,
          ),
      ],
    );
    _reviewView = _sanitizeReview(packet);
  }

  ExperienceAuthoringReviewView _sanitizeReview(ExperienceReviewPacket packet) {
    final binding = packet.reviewGuideBinding;
    final guides = catalog.reviewGuides
        .where(
          (guide) =>
              guide.id == binding.reviewGuideId &&
              guide.applicationId == binding.applicationId,
        )
        .toList(growable: false);
    if (guides.length != 1 ||
        binding.catalogDigest != catalog.digest ||
        binding.applicationId != subject.applicationId) {
      throw const FormatException('ReviewGuide binding is not current');
    }
    final guide = guides.single;
    final steps = guide.steps
        .where(
          (step) =>
              step.id == binding.stepId &&
              step.scenarioId == binding.scenarioId &&
              step.bindingId == binding.bindingId,
        )
        .toList(growable: false);
    if (steps.length != 1) {
      throw const FormatException('ReviewGuide step binding is incomplete');
    }
    final step = steps.single;
    final options = _reviewSubjectOptions(binding);
    final labels = <String, String>{
      for (final option in options) option.key: option.label,
    };
    final currentScenarioIds = catalog.scenarios
        .map((scenario) => scenario.id.value)
        .toSet();
    final proposedScenarioIds = packet.concepts
        .map((concept) => concept.scenarioId.value)
        .toSet();
    var suffix = 1;
    var syntheticValue = '${binding.scenarioId.value}-concept';
    while (currentScenarioIds.contains(syntheticValue) ||
        proposedScenarioIds.contains(syntheticValue)) {
      suffix += 1;
      syntheticValue = '${binding.scenarioId.value}-concept-$suffix';
    }
    return ExperienceAuthoringReviewView(
      packetId: packet.id,
      packetDigest: packet.digest,
      revision: packet.revision,
      guide: ExecutableReviewGuideView(
        id: guide.id,
        title: guide.title,
        stepId: step.id,
        instruction: step.instruction,
        observationCriteria: step.observationCriteria,
        scenarioId: step.scenarioId,
        bindingId: step.bindingId,
        labRoute: _labRouteFor(step.scenarioId, step.bindingId),
      ),
      syntheticConceptScenarioId: ScenarioId(syntheticValue),
      automatedAcceptance: packet.automatedAcceptance == null
          ? null
          : ExperienceAutomatedAcceptanceView(
              outcome: packet.automatedAcceptance!.outcome,
              summary: packet.automatedAcceptance!.summary,
              recordedAt: packet.automatedAcceptance!.recordedAt,
            ),
      promotable: packet.isPromotable,
      subjectOptions: options,
      findings: <ExperienceFindingView>[
        for (final finding in packet.findings)
          ExperienceFindingView(
            subjectLabel:
                labels[_reviewSubjectKey(finding.subject)] ??
                _reviewSubjectLabel(finding.subject),
            severity: finding.severity,
            summary: finding.summary,
            detail: finding.detail,
            recordedAt: finding.recordedAt,
          ),
      ],
      concepts: <ExperienceConceptView>[
        for (final concept in packet.concepts)
          ExperienceConceptView(
            scenarioId: concept.scenarioId,
            lifecycle: concept.lifecycle,
            title: concept.title,
            rationale: concept.rationale,
            recordedAt: concept.recordedAt,
          ),
      ],
      comments: <ExperienceCommentView>[
        for (final comment in packet.comments)
          ExperienceCommentView(
            sequence: comment.sequence,
            subjectLabel:
                labels[_reviewSubjectKey(comment.subject)] ??
                _reviewSubjectLabel(comment.subject),
            body: comment.body,
            recordedAt: comment.recordedAt,
          ),
      ],
      decisions: <ExperienceHumanDecisionView>[
        for (var index = 0; index < packet.humanDecisions.length; index += 1)
          ExperienceHumanDecisionView(
            sequence: packet.humanDecisions[index].sequence,
            decision: packet.humanDecisions[index].decision,
            rationale: packet.humanDecisions[index].rationale,
            recordedAt: packet.humanDecisions[index].recordedAt,
            isHead: index == packet.humanDecisions.length - 1,
          ),
      ],
    );
  }

  List<ExperienceReviewSubjectOption> _reviewSubjectOptions(
    ExecutableReviewGuideBinding binding,
  ) {
    final scenarioId = binding.scenarioId;
    final scenarios = catalog.scenarios
        .where(
          (scenario) =>
              scenario.id == scenarioId &&
              scenario.applicationId == subject.applicationId,
        )
        .toList(growable: false);
    if (scenarios.length != 1) {
      throw const FormatException('Review scenario is outside the application');
    }
    final options = <ExperienceReviewSubjectOption>[
      ExperienceReviewSubjectOption(
        key: 'scenario:${scenarioId.value}',
        label: 'Scenario · ${scenarios.single.title}',
        subject: ExperienceReviewSubject.scenario(scenarioId),
      ),
    ];
    final transitionIds = bundle.topology.edges
        .where((edge) => edge.projectionId == projection.id)
        .map((edge) => edge.transitionId)
        .toSet();
    for (final transition in catalog.transitions) {
      if (!transitionIds.contains(transition.id)) continue;
      options.add(
        ExperienceReviewSubjectOption(
          key: 'transition:${transition.id.value}',
          label: 'Transition · ${transition.label ?? transition.id.value}',
          subject: ExperienceReviewSubject.transition(transition.id),
        ),
      );
    }
    final allowedArtifactDigests = _allowedArtifactDigestsFor(binding);
    final manifest = scenarioLab;
    if (manifest != null) {
      for (final artifact in manifest.supplementalArtifacts) {
        if (!allowedArtifactDigests.contains(artifact.artifactDigest)) continue;
        options.add(
          ExperienceReviewSubjectOption(
            key: 'artifact:${artifact.artifactDigest.value}',
            label: 'Artifact · ${artifact.id.value}',
            subject: ExperienceReviewSubject.artifact(artifact.artifactDigest),
          ),
        );
      }
    }
    return options;
  }

  Set<Digest> _allowedArtifactDigestsFor(ExecutableReviewGuideBinding binding) {
    final manifest = scenarioLab;
    if (manifest == null) return const <Digest>{};
    if (manifest.catalogDigest != catalog.digest) {
      throw const FormatException('Scenario Lab generation is not current');
    }
    final plans = manifest.plans
        .where(
          (plan) =>
              plan.scenarioId == binding.scenarioId &&
              plan.executionBindingIds.contains(binding.bindingId),
        )
        .toList(growable: false);
    if (plans.length != 1) {
      throw const FormatException(
        'ReviewGuide binding must resolve to one Scenario Lab plan',
      );
    }
    final artifactIds = plans.single.supplementalArtifactIds.toSet();
    final artifacts = manifest.supplementalArtifacts
        .where((artifact) => artifactIds.contains(artifact.id))
        .toList(growable: false);
    if (artifacts.length != artifactIds.length ||
        artifacts.any(
          (artifact) => artifact.scenarioId != binding.scenarioId,
        )) {
      throw const FormatException(
        'Review artifacts must resolve inside the bound Scenario Lab plan',
      );
    }
    return <Digest>{for (final artifact in artifacts) artifact.artifactDigest};
  }

  String _reviewSubjectKey(ExperienceReviewSubject value) =>
      switch (value.kind) {
        ExperienceReviewSubjectKind.scenario =>
          'scenario:${value.scenarioId!.value}',
        ExperienceReviewSubjectKind.transition =>
          'transition:${value.transitionId!.value}',
        ExperienceReviewSubjectKind.artifact =>
          'artifact:${value.artifactDigest!.value}',
      };

  String _reviewSubjectLabel(ExperienceReviewSubject value) =>
      switch (value.kind) {
        ExperienceReviewSubjectKind.scenario =>
          'Scenario · ${value.scenarioId!.value}',
        ExperienceReviewSubjectKind.transition =>
          'Transition · ${value.transitionId!.value}',
        ExperienceReviewSubjectKind.artifact => 'Artifact catalogado',
      };

  String? _labRouteFor(
    ScenarioId scenarioId,
    ScenarioExecutionBindingId bindingId,
  ) {
    final manifest = scenarioLab;
    if (manifest == null || manifest.catalogDigest != catalog.digest) {
      return null;
    }
    final plans = manifest.plans
        .where(
          (plan) =>
              plan.scenarioId == scenarioId &&
              plan.executionBindingIds.contains(bindingId),
        )
        .toList(growable: false);
    final scriptIds = <ScenarioScriptId>{};
    for (final plan in plans) {
      for (final scriptId in plan.scriptIds) {
        final matches = manifest.scripts.where(
          (script) =>
              script.id == scriptId &&
              script.scenarioId == scenarioId &&
              script.steps.first is ExecutionBindingScenarioScriptStep &&
              (script.steps.first as ExecutionBindingScenarioScriptStep)
                      .bindingId ==
                  bindingId,
        );
        if (matches.length == 1) scriptIds.add(scriptId);
      }
    }
    if (scriptIds.length != 1) return null;
    return Uri(
      pathSegments: <String>[
        'lab',
        'scenarios',
        scenarioId.value,
        'scripts',
        scriptIds.single.value,
      ],
    ).path;
  }

  List<ExperienceAuthoringNodeView> _nodesFor(ProjectionLayoutManifest layout) {
    final nodes = <NodeInstanceId, NodeInstance>{
      for (final node in bundle.topology.nodes)
        if (node.projectionId == projection.id) node.id: node,
    };
    final scenarios = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final baseFrames = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in baseLayout.nodeFrames) frame.nodeInstanceId: frame,
    };
    return <ExperienceAuthoringNodeView>[
      for (final frame in layout.nodeFrames)
        if (nodes[frame.nodeInstanceId] case final node?)
          ExperienceAuthoringNodeView(
            id: node.id,
            scenarioId: node.scenarioId,
            scenarioTitle:
                scenarios[node.scenarioId]?.title ?? node.scenarioId.value,
            x: frame.x,
            y: frame.y,
            width: frame.width,
            height: frame.height,
            changed:
                baseFrames[frame.nodeInstanceId]?.x != frame.x ||
                baseFrames[frame.nodeInstanceId]?.y != frame.y,
          ),
    ]..sort((left, right) => left.id.value.compareTo(right.id.value));
  }

  void _clearMutableState() {
    _draft = null;
    _draftView = null;
    _comparisonView = null;
    _reviewView = null;
    _latestPromotion = null;
    _promotions = const <ExperiencePromotionView>[];
    _promotionTotalCount = null;
    _promotionHistoryTruncated = false;
  }

  void _transition(ExperienceAuthoringControllerPhase phase) {
    if (_phase == ExperienceAuthoringControllerPhase.closed) return;
    _phase = phase;
    onStateChanged?.call(snapshot);
  }

  void _notify() {
    if (_phase != ExperienceAuthoringControllerPhase.closed) {
      onStateChanged?.call(snapshot);
    }
  }

  bool _isCurrent(int operationEpoch) =>
      _phase != ExperienceAuthoringControllerPhase.closed &&
      operationEpoch == _epoch;

  void _handleFailure(int operationEpoch, Object error) {
    if (!_isCurrent(operationEpoch)) return;
    if (error is _ExperienceAuthoringLocalConflict) {
      _failureCode = ExperienceAuthoringErrorCode.stale;
      _transition(ExperienceAuthoringControllerPhase.conflict);
      return;
    }
    if (error case StudioExperienceAuthoringFailure(:final error)) {
      _failureCode = error.code;
      if (error.code == ExperienceAuthoringErrorCode.policyDenied) {
        _availability = ExperienceAuthoringAvailability.policyDenied;
        _allowedOperations = _allowedOperations
            .where(
              (operation) =>
                  authoringEffectFor(operation) == AuthoringActionEffect.query,
            )
            .toSet();
        _transition(ExperienceAuthoringControllerPhase.ready);
      } else if (error.code == ExperienceAuthoringErrorCode.stale ||
          error.code == ExperienceAuthoringErrorCode.ownerDenied ||
          error.code == ExperienceAuthoringErrorCode.requestConflict) {
        _transition(ExperienceAuthoringControllerPhase.conflict);
      } else {
        _transition(ExperienceAuthoringControllerPhase.transportFailure);
      }
      return;
    }
    if (error is FormatException ||
        error is ArgumentError ||
        error is StateError) {
      _transition(ExperienceAuthoringControllerPhase.protocolViolation);
      return;
    }
    _transition(ExperienceAuthoringControllerPhase.transportFailure);
  }

  AuthoringRequestId _nextRequestId(String purpose) =>
      _requestIdFactory(_canonicalRequestPurpose(purpose), ++_requestSequence);

  Future<void> _rejectInvalidInput() {
    if (_phase == ExperienceAuthoringControllerPhase.closed ||
        _phase == ExperienceAuthoringControllerPhase.loading ||
        _phase == ExperienceAuthoringControllerPhase.submitting) {
      return Future<void>.value();
    }
    _failureCode = ExperienceAuthoringErrorCode.invalidRequest;
    _transition(ExperienceAuthoringControllerPhase.ready);
    return Future<void>.value();
  }

  void close() {
    if (_phase == ExperienceAuthoringControllerPhase.closed) return;
    _epoch += 1;
    _clearMutableState();
    _allowedOperations = const <AuthoringOperation>{};
    _phase = ExperienceAuthoringControllerPhase.closed;
    onStateChanged = null;
  }
}

typedef _TransientReviewPair = ({
  ExperienceChangeSet changeSet,
  ExperienceReviewPacket packet,
});

typedef _ReviewGuideSelection = ({ReviewGuide guide, ReviewGuideStep step});

final class _ExperienceAuthoringLocalConflict implements Exception {
  const _ExperienceAuthoringLocalConflict();
}

AuthoringActionGrantId _transientGrantId() =>
    AuthoringActionGrantId('transient-placeholder');

Digest _transientGrantDigest() =>
    Digest.semantic(const <String, Object?>{'transient': 'grant-placeholder'});

AuthoringRequestId _defaultRequestId(String purpose, int sequence) =>
    AuthoringRequestId('studio-authoring-$purpose-$sequence');

ExperiencePromotionView _promotionView(ExperiencePromotionReceipt receipt) =>
    ExperiencePromotionView(
      id: receipt.id,
      sequence: receipt.sequence,
      resultContentSetDigest: receipt.resultContentSetDigest,
      layoutDigest: receipt.layoutDigest,
      promotedAt: receipt.promotedAt,
    );

String _canonicalRequestPurpose(String value) => value
    .replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => '-${match.group(0)!.toLowerCase()}',
    )
    .replaceAll(RegExp('[^a-z0-9._-]+'), '-')
    .replaceAll(RegExp('-+'), '-');

bool _validCoordinate(double value) =>
    value.isFinite &&
    !(value == 0 && value.isNegative) &&
    value >= -1000000 &&
    value <= 1000000;

bool _validText(String value, int maxBytes) =>
    value.trim().isNotEmpty && utf8.encode(value).length <= maxBytes;
