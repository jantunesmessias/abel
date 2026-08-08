import 'package:experience_contracts/experience_contracts.dart';

import '../host/studio_host_client.dart';
import 'studio_scenario_quality_transport.dart';

enum ScenarioQualityDecisionOperationState {
  detached,
  loading,
  ready,
  submitting,
  conflict,
  protocolViolation,
  transportFailure,
  closed,
}

enum ScenarioQualityReviewResourceState {
  validating,
  validated,
  rendered,
  rejected,
}

final class ScenarioQualityReviewResourceSnapshot {
  const ScenarioQualityReviewResourceSnapshot({
    required this.descriptorDigest,
    required this.role,
    required this.artifactDigest,
    required this.provenanceKind,
    required this.mediaType,
    required this.state,
  });

  final Digest descriptorDigest;
  final ScenarioQualityReviewArtifactRole role;
  final Digest artifactDigest;
  final ScenarioQualityReviewProvenanceKind provenanceKind;
  final String mediaType;
  final ScenarioQualityReviewResourceState state;

  bool get isImage => mediaType == 'image/png';
}

/// Sanitized history presentation. Host authority and grant material stay out
/// of the public controller snapshot.
final class ScenarioQualityDecisionHistoryItem {
  const ScenarioQualityDecisionHistoryItem({
    required this.recordId,
    required this.decisionDigest,
    required this.decision,
    required this.decidedAt,
    required this.state,
    required this.policyId,
    required this.requirementId,
    this.supersededByDecisionDigest,
  });

  final HumanDecisionRecordId recordId;
  final Digest decisionDigest;
  final HumanDecision decision;
  final DateTime decidedAt;
  final HumanDecisionState state;
  final ScenarioQualityAccessPolicyId policyId;
  final HumanApprovalRequirementId requirementId;
  final Digest? supersededByDecisionDigest;
}

final class ScenarioQualityDecisionControllerSnapshot {
  const ScenarioQualityDecisionControllerSnapshot({
    required this.operation,
    required this.availability,
    required this.decisionCount,
    required this.resourceGeneration,
    required this.resources,
    required this.history,
    this.quality,
    this.requirementId,
    this.headDecisionDigest,
    this.policyId,
    this.reviewGuideTitle,
    this.reviewInstruction,
    this.reviewCriteria,
    this.pendingDecision,
  });

  final ScenarioQualityDecisionOperationState operation;
  final ScenarioQualityReviewAvailability availability;
  final ScenarioQualitySnapshot? quality;
  final HumanApprovalRequirementId? requirementId;
  final Digest? headDecisionDigest;
  final ScenarioQualityAccessPolicyId? policyId;
  final int decisionCount;
  final int resourceGeneration;
  final String? reviewGuideTitle;
  final String? reviewInstruction;
  final String? reviewCriteria;
  final HumanDecision? pendingDecision;
  final List<ScenarioQualityReviewResourceSnapshot> resources;
  final List<ScenarioQualityDecisionHistoryItem> history;

  bool get resourcesReady =>
      resources.isNotEmpty &&
      resources.every(
        (resource) => resource.isImage
            ? resource.state == ScenarioQualityReviewResourceState.rendered
            : resource.state == ScenarioQualityReviewResourceState.validated,
      );

  bool get canDecide =>
      operation == ScenarioQualityDecisionOperationState.ready &&
      availability == ScenarioQualityReviewAvailability.available &&
      resourcesReady &&
      reviewInstruction != null &&
      reviewCriteria != null;
}

typedef ScenarioQualityDecisionStateListener =
    void Function(ScenarioQualityDecisionControllerSnapshot snapshot);
typedef ScenarioQualityDecisionRequestIdFactory =
    ScenarioQualityDecisionRequestId Function(String purpose, int sequence);

/// Pure coordinator for Host-authoritative human decisions.
///
/// Every async response is epoch-fenced. Resource handles and grants live only
/// in private fields or stack locals and never enter [snapshot].
final class ScenarioQualityDecisionController {
  ScenarioQualityDecisionController({
    required this.host,
    required this.resourceClient,
    required this.catalog,
    required this.manifest,
    required this.runSnapshot,
    required this.runResult,
    this.onStateChanged,
    this.initialProtocolViolation = false,
    ScenarioQualityDecisionRequestIdFactory? requestIdFactory,
  }) : _requestIdFactory = requestIdFactory ?? _defaultRequestId {
    if (manifest.catalogDigest != catalog.digest) {
      throw ArgumentError(
        'Scenario Quality controller requires one pinned Catalog generation',
      );
    }
    if (initialProtocolViolation) {
      _operation = ScenarioQualityDecisionOperationState.protocolViolation;
    }
  }

  final StudioHostScenarioQualityClient? host;
  final StudioHostScenarioQualityResourceClient? resourceClient;
  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
  final ScenarioLabRunSnapshot? runSnapshot;
  final ScenarioLabRunResult? runResult;
  final bool initialProtocolViolation;
  final ScenarioQualityDecisionRequestIdFactory _requestIdFactory;
  ScenarioQualityDecisionStateListener? onStateChanged;

  ScenarioQualityDecisionOperationState _operation =
      ScenarioQualityDecisionOperationState.detached;
  ScenarioQualityReviewAvailability _availability =
      ScenarioQualityReviewAvailability.unsupported;
  ScenarioQualitySnapshot? _quality;
  HumanApprovalRequirementId? _requirementId;
  Digest? _headDecisionDigest;
  int _decisionCount = 0;
  String? _reviewGuideTitle;
  String? _reviewInstruction;
  String? _reviewCriteria;
  HumanDecision? _pendingDecision;
  final Map<Digest, _ReviewResource> _reviewResources =
      <Digest, _ReviewResource>{};
  List<ScenarioQualityDecisionHistoryItem> _history =
      const <ScenarioQualityDecisionHistoryItem>[];
  var _epoch = 0;
  var _requestSequence = 0;
  var _resourceGeneration = 0;

  ScenarioQualityDecisionControllerSnapshot get snapshot {
    final resources = _reviewResources.values
        .map((resource) => resource.snapshot)
        .toList(growable: false);
    final history = List<ScenarioQualityDecisionHistoryItem>.unmodifiable(
      _history,
    );
    return ScenarioQualityDecisionControllerSnapshot(
      operation: _operation,
      availability: _availability,
      quality: _quality,
      requirementId: _requirementId,
      headDecisionDigest: _headDecisionDigest,
      policyId: history.firstOrNull?.policyId,
      decisionCount: _decisionCount,
      resourceGeneration: _resourceGeneration,
      reviewGuideTitle: _reviewGuideTitle,
      reviewInstruction: _reviewInstruction,
      reviewCriteria: _reviewCriteria,
      pendingDecision: _pendingDecision,
      resources: List<ScenarioQualityReviewResourceSnapshot>.unmodifiable(
        resources,
      ),
      history: history,
    );
  }

  void setStateListener(ScenarioQualityDecisionStateListener? listener) {
    onStateChanged = listener;
  }

  Future<void> load() async {
    if (_operation == ScenarioQualityDecisionOperationState.closed) return;
    if (initialProtocolViolation) {
      _transition(ScenarioQualityDecisionOperationState.protocolViolation);
      return;
    }
    final result = runResult;
    final terminal = runSnapshot;
    if (result == null || terminal == null || !terminal.state.isTerminal) {
      _clearReviewState();
      _transition(ScenarioQualityDecisionOperationState.detached);
      return;
    }
    if (!_exactTerminalBinding(terminal, result)) {
      _clearReviewState();
      _transition(ScenarioQualityDecisionOperationState.protocolViolation);
      return;
    }
    if (host == null) {
      _clearReviewState();
      _availability = ScenarioQualityReviewAvailability.unsupported;
      _transition(ScenarioQualityDecisionOperationState.ready);
      return;
    }

    final operationEpoch = ++_epoch;
    _clearReviewState();
    _transition(ScenarioQualityDecisionOperationState.loading);
    try {
      await _loadFenced(operationEpoch, result);
      if (_isCurrent(operationEpoch)) {
        _transition(ScenarioQualityDecisionOperationState.ready);
      }
    } on StudioScenarioQualityDecisionFailure catch (failure) {
      _handleTypedFailure(
        operationEpoch,
        failure.error,
        expectedOperation: failure.error.operation,
      );
    } on FormatException {
      _failIfCurrent(
        operationEpoch,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
    } on ArgumentError {
      _failIfCurrent(
        operationEpoch,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
    } on Object {
      _failIfCurrent(
        operationEpoch,
        ScenarioQualityDecisionOperationState.transportFailure,
      );
    }
  }

  Future<void> refresh() => load();

  void requestDecision(HumanDecision decision) {
    if (!snapshot.canDecide || _pendingDecision != null) return;
    _pendingDecision = decision;
    _notify();
  }

  void cancelDecision() {
    if (_operation != ScenarioQualityDecisionOperationState.ready ||
        _pendingDecision == null) {
      return;
    }
    _pendingDecision = null;
    _notify();
  }

  /// Grants only after inline confirmation and appends immediately. The grant
  /// is a stack local and cannot survive success, failure, refresh or close.
  Future<void> submitConfirmedDecision() async {
    final decision = _pendingDecision;
    final result = runResult;
    final descriptor = _currentReviewDescriptor;
    final currentQuality = _quality;
    final activeHost = host;
    if (decision == null ||
        result == null ||
        descriptor == null ||
        currentQuality == null ||
        activeHost == null ||
        !snapshot.canDecide) {
      return;
    }

    final expectedHead = _headDecisionDigest;
    final previousCount = _decisionCount;
    final operationEpoch = ++_epoch;
    _transition(ScenarioQualityDecisionOperationState.submitting);
    final grantRequest = ScenarioQualityDecisionGrantRequest(
      requestId: _nextRequestId('grant'),
      runId: result.finalSnapshot.runId,
      expectedRunResultDigest: result.digest,
      expectedQualityDigest: currentQuality.digest,
      expectedReviewDescriptorDigest: descriptor.digest,
      decision: decision,
      expectedPreviousDecisionDigest: expectedHead,
    );
    try {
      final grant = await activeHost.grantScenarioQualityDecision(grantRequest);
      if (!_isCurrent(operationEpoch)) return;
      _validateGrant(grant, grantRequest, descriptor);
      final appendRequest = ScenarioQualityDecisionAppendRequest(
        requestId: _nextRequestId('append'),
        runId: result.finalSnapshot.runId,
        expectedRunResultDigest: result.digest,
        expectedQualityDigest: currentQuality.digest,
        expectedReviewDescriptorDigest: descriptor.digest,
        grantId: grant.id,
        grantDigest: grant.digest,
        decision: decision,
        expectedPreviousDecisionDigest: expectedHead,
      );
      final appended = await activeHost.appendScenarioQualityDecision(
        appendRequest,
      );
      if (!_isCurrent(operationEpoch)) return;
      _validateAppend(
        appended,
        appendRequest,
        grant: grant,
        grantRequest: grantRequest,
        descriptor: descriptor,
        priorQuality: currentQuality,
      );
      _pendingDecision = null;
      await _loadFenced(
        operationEpoch,
        result,
        expectedHead: appended.record.digest,
        expectedDecisionCount: previousCount + 1,
      );
      if (_isCurrent(operationEpoch)) {
        _transition(ScenarioQualityDecisionOperationState.ready);
      }
    } on StudioScenarioQualityDecisionFailure catch (failure) {
      _handleTypedFailure(
        operationEpoch,
        failure.error,
        expectedOperation: failure.error.operation,
      );
    } on FormatException {
      _failIfCurrent(
        operationEpoch,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
    } on ArgumentError {
      _failIfCurrent(
        operationEpoch,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
    } on Object {
      _failIfCurrent(
        operationEpoch,
        ScenarioQualityDecisionOperationState.transportFailure,
      );
    }
  }

  Future<StudioResourceLease> openReviewImage(
    Digest descriptorDigest, {
    required int expectedResourceGeneration,
  }) async {
    final resource = _reviewResources[descriptorDigest];
    final activeClient = resourceClient;
    if (resource == null ||
        activeClient == null ||
        !resource.isImage ||
        expectedResourceGeneration != _resourceGeneration ||
        _operation == ScenarioQualityDecisionOperationState.closed) {
      throw StateError('Scenario Quality review image is unavailable');
    }
    final operationEpoch = _epoch;
    try {
      final lease = await activeClient.openScenarioQualityReviewImage(
        handle: resource.binding.artifact,
        descriptor: resource.descriptor,
      );
      if (!_isCurrent(operationEpoch) ||
          _reviewResources[descriptorDigest] != resource) {
        lease.release();
        throw StateError('Scenario Quality review image became stale');
      }
      resource.artifactValidated = true;
      _notify();
      return lease;
    } on Object {
      if (_isCurrent(operationEpoch) &&
          _reviewResources[descriptorDigest] == resource) {
        resource.rejected = true;
        _transition(ScenarioQualityDecisionOperationState.protocolViolation);
      }
      rethrow;
    }
  }

  void markReviewImageRendered(
    Digest descriptorDigest, {
    required int expectedResourceGeneration,
  }) {
    final resource = _reviewResources[descriptorDigest];
    if (resource == null ||
        expectedResourceGeneration != _resourceGeneration ||
        !resource.isImage ||
        !resource.artifactValidated ||
        resource.rejected) {
      return;
    }
    if (!resource.imageRendered) {
      resource.imageRendered = true;
      _notify();
    }
  }

  void rejectReviewImage(
    Digest descriptorDigest, {
    required int expectedResourceGeneration,
  }) {
    final resource = _reviewResources[descriptorDigest];
    if (resource == null ||
        expectedResourceGeneration != _resourceGeneration ||
        resource.rejected) {
      return;
    }
    resource.rejected = true;
    _transition(ScenarioQualityDecisionOperationState.protocolViolation);
  }

  void close() {
    if (_operation == ScenarioQualityDecisionOperationState.closed) return;
    _epoch += 1;
    _clearReviewState();
    _operation = ScenarioQualityDecisionOperationState.closed;
    _notify();
    onStateChanged = null;
  }

  ScenarioQualityReviewDescriptor? _currentReviewDescriptor;

  Future<void> _loadFenced(
    int operationEpoch,
    ScenarioLabRunResult result, {
    Digest? expectedHead,
    int? expectedDecisionCount,
  }) async {
    final activeHost = host!;
    final describeRequest = ScenarioQualityDescribeRequest(
      runId: result.finalSnapshot.runId,
      expectedRunResultDigest: result.digest,
    );
    final described = await activeHost.describeScenarioQuality(describeRequest);
    if (!_isCurrent(operationEpoch)) return;
    _validateDescription(described, describeRequest, result);
    final description = described.description;
    if (expectedHead != null &&
        description.headDecisionDigest != expectedHead) {
      throw const FormatException(
        'Scenario Quality append was not published as the current head',
      );
    }
    if (expectedDecisionCount != null &&
        description.decisionCount != expectedDecisionCount) {
      throw const FormatException(
        'Scenario Quality decision count did not advance exactly once',
      );
    }
    _availability = description.availability;
    _quality = description.quality;
    _requirementId = description.requirementId;
    _headDecisionDigest = description.headDecisionDigest;
    _decisionCount = description.decisionCount;
    _currentReviewDescriptor = described.reviewDescriptor;
    _reviewResources.clear();
    _resourceGeneration += 1;
    _history = const <ScenarioQualityDecisionHistoryItem>[];

    _history = await _loadHistory(
      operationEpoch,
      result,
      description.headDecisionDigest,
      description.decisionCount,
    );
    if (!_isCurrent(operationEpoch)) return;
    _notify();

    if (_availability != ScenarioQualityReviewAvailability.available) {
      _reviewGuideTitle = null;
      _reviewInstruction = null;
      _reviewCriteria = null;
      _notify();
      return;
    }
    final descriptor = described.reviewDescriptor!;
    _resolvePinnedReviewGuide(descriptor, result);
    final activeResources = resourceClient;
    if (activeResources == null) {
      throw const FormatException(
        'Scenario Quality resource transport is unavailable',
      );
    }
    final openRequest = ScenarioQualityReviewOpenRequest(
      runId: result.finalSnapshot.runId,
      expectedRunResultDigest: result.digest,
      expectedQualityDigest: description.quality.digest,
      expectedReviewDescriptorDigest: descriptor.digest,
    );
    final opened = await activeHost.openScenarioQualityReview(openRequest);
    if (!_isCurrent(operationEpoch)) return;
    _validateOpen(opened, openRequest);
    for (final binding in opened.resources) {
      final artifact = descriptor.artifacts.singleWhere(
        (candidate) => candidate.digest == binding.artifactDescriptorDigest,
      );
      _reviewResources[artifact.digest] = _ReviewResource(
        descriptor: artifact,
        binding: binding,
      );
    }
    _notify();
    for (final resource in _reviewResources.values) {
      final provenance = await activeResources
          .readScenarioQualityReviewProvenance(
            handle: resource.binding.provenance,
            kind: resource.descriptor.provenanceKind,
            expectedDigest: resource.descriptor.provenanceDigest,
          );
      if (!_isCurrent(operationEpoch)) return;
      _validateProvenance(
        resource.descriptor,
        provenance,
        result.finalSnapshot.runId,
      );
      resource.provenanceValidated = true;
      if (!resource.isImage) {
        await activeResources.validateScenarioQualityReviewArtifact(
          handle: resource.binding.artifact,
          descriptor: resource.descriptor,
        );
        if (!_isCurrent(operationEpoch)) return;
        resource.artifactValidated = true;
      }
      _notify();
    }
  }

  List<ScenarioQualityDecisionHistoryItem> _sanitizeHistory(
    List<ScenarioQualityDecisionView> views,
  ) => List<ScenarioQualityDecisionHistoryItem>.unmodifiable(<
    ScenarioQualityDecisionHistoryItem
  >[
    for (final view in views)
      ScenarioQualityDecisionHistoryItem(
        recordId: view.record.id,
        decisionDigest: view.record.digest,
        decision: view.record.decision,
        decidedAt: view.record.decidedAt,
        state: view.projection.state,
        policyId: view.attribution.accessPolicyId,
        requirementId: view.attribution.requirementId,
        supersededByDecisionDigest: view.projection.supersededByDecisionDigest,
      ),
  ]);

  Future<List<ScenarioQualityDecisionHistoryItem>> _loadHistory(
    int operationEpoch,
    ScenarioLabRunResult result,
    Digest? head,
    int count,
  ) async {
    if (head == null) return const <ScenarioQualityDecisionHistoryItem>[];
    final activeHost = host!;
    final views = <ScenarioQualityDecisionView>[];
    var cursor = head;
    for (var index = 0; index < count; index++) {
      final view = await activeHost.getScenarioQualityDecision(
        ScenarioQualityDecisionGetRequest(
          runId: result.finalSnapshot.runId,
          expectedRunResultDigest: result.digest,
          decisionDigest: cursor,
        ),
      );
      if (!_isCurrent(operationEpoch)) {
        return const <ScenarioQualityDecisionHistoryItem>[];
      }
      _validateHistoryView(view, result, cursor, views.firstOrNull);
      views.add(view);
      final previous = view.record.supersedesDecisionDigest;
      if (index + 1 == count) {
        if (previous != null) {
          throw const FormatException(
            'Scenario Quality history exceeds its declared decision count',
          );
        }
      } else if (previous == null) {
        throw const FormatException(
          'Scenario Quality history ended before its declared decision count',
        );
      }
      if (previous != null) cursor = previous;
    }
    _validateHistoryDescriptorChain(views);
    _validateHistoryQualityChain(views);
    return _sanitizeHistory(views);
  }

  void _validateHistoryDescriptorChain(
    List<ScenarioQualityDecisionView> views,
  ) {
    if (views.isEmpty) return;
    final chainArtifactSet = _reviewArtifactSetDigest(
      views.first.reviewDescriptor,
    );
    final current = _currentReviewDescriptor;
    if (current != null &&
        _reviewArtifactSetDigest(current) != chainArtifactSet) {
      throw const FormatException(
        'Scenario Quality history artifacts differ from the current review',
      );
    }
    if (views
        .skip(1)
        .any(
          (view) =>
              _reviewArtifactSetDigest(view.reviewDescriptor) !=
              chainArtifactSet,
        )) {
      throw const FormatException(
        'Scenario Quality history changed its immutable review artifacts',
      );
    }
  }

  void _validateHistoryQualityChain(List<ScenarioQualityDecisionView> views) {
    final automated = _quality;
    if (automated == null) {
      throw const FormatException(
        'Scenario Quality history has no current Quality projection',
      );
    }
    for (var index = 0; index < views.length; index++) {
      final view = views[index];
      final prior = index + 1 < views.length ? views[index + 1].record : null;
      final priorProjection = prior == null
          ? HumanDecisionProjection(state: HumanDecisionState.unreviewed)
          : HumanDecisionProjection(
              state: switch (prior.decision) {
                HumanDecision.approved => HumanDecisionState.approved,
                HumanDecision.rejected => HumanDecisionState.rejected,
              },
              decisionDigest: prior.digest,
            );
      final priorQuality = ScenarioQualitySnapshot(
        subjectDigest: automated.subjectDigest,
        runId: automated.runId,
        scenarioId: automated.scenarioId,
        verificationState: automated.verificationState,
        humanDecision: priorProjection,
        requiredEvidence: automated.requiredEvidence,
        comparisonResultDigests: automated.comparisonResultDigests,
      );
      if (view.reviewDescriptor.qualityDigest != priorQuality.digest) {
        throw const FormatException(
          'Scenario Quality history review did not bind the prior Quality',
        );
      }
    }
  }

  Digest _reviewArtifactSetDigest(ScenarioQualityReviewDescriptor descriptor) =>
      Digest.semantic(<String, Object?>{
        'requirementId': descriptor.requirementId.value,
        'requirementScope': descriptor.requirementScope.name,
        'reviewGuideId': descriptor.reviewGuideId.value,
        'reviewGuideStepId': descriptor.reviewGuideStepId,
        'requiredEvidenceResultDigests': descriptor
            .requiredEvidenceResultDigests
            .map((digest) => digest.value)
            .toList(),
        'comparisonResultDigests': descriptor.comparisonResultDigests
            .map((digest) => digest.value)
            .toList(),
        'artifacts': descriptor.artifacts
            .map((artifact) => artifact.toJson())
            .toList(),
      });

  bool _exactTerminalBinding(
    ScenarioLabRunSnapshot terminal,
    ScenarioLabRunResult result,
  ) {
    if (result.finalSnapshot.digest != terminal.digest ||
        result.finalSnapshot.runId != terminal.runId ||
        terminal.catalogDigest != catalog.digest ||
        terminal.scenarioLabManifestDigest != manifest.digest ||
        !terminal.state.isTerminal) {
      return false;
    }
    final plans = manifest.plans
        .where(
          (plan) =>
              plan.scenarioId == terminal.scenarioId &&
              plan.scriptIds.contains(terminal.scriptId),
        )
        .toList(growable: false);
    if (plans.length != 1) return false;
    final plan = plans.single;
    return _sameStringSet(
          plan.requiredEvidenceIds.map((id) => id.value),
          terminal.requiredEvidence.map(
            (result) => result.requiredEvidenceId.value,
          ),
        ) &&
        _sameStringSet(
          plan.automatedAcceptanceCriterionIds.map((id) => id.value),
          terminal.automatedAcceptance.map(
            (result) => result.criterionId.value,
          ),
        ) &&
        _sameStringSet(
          plan.comparisonBindingIds.map((id) => id.value),
          terminal.comparisons.map((result) => result.bindingId.value),
        );
  }

  bool _sameStringSet(Iterable<String> left, Iterable<String> right) {
    final leftSet = left.toSet();
    final rightSet = right.toSet();
    return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
  }

  void _validateDescription(
    ScenarioQualityDescribeResult described,
    ScenarioQualityDescribeRequest request,
    ScenarioLabRunResult result,
  ) {
    final description = described.description;
    if (description.runId != request.runId ||
        description.runResultDigest != request.expectedRunResultDigest ||
        description.quality.runId != request.runId ||
        description.quality.subjectDigest != request.expectedRunResultDigest ||
        description.quality.scenarioId != result.finalSnapshot.scenarioId) {
      throw const FormatException(
        'Scenario Quality description crossed its terminal-run fence',
      );
    }
    description.quality.validateAgainstResult(result);
    if (described.reviewDescriptor case final descriptor?) {
      _validateReviewArtifacts(descriptor, result);
    }
  }

  void _validateReviewArtifacts(
    ScenarioQualityReviewDescriptor descriptor,
    ScenarioLabRunResult result,
  ) {
    final snapshot = result.finalSnapshot;
    final evidenceByDigest = <Digest, RequiredEvidenceRunResult>{
      for (final evidence in snapshot.requiredEvidence)
        evidence.digest: evidence,
    };
    final evidenceById = <RequiredEvidenceId, RequiredEvidenceRunResult>{
      for (final evidence in snapshot.requiredEvidence)
        evidence.requiredEvidenceId: evidence,
    };
    final comparisonsByDigest = <Digest, ScenarioComparisonResult>{
      for (final comparison in snapshot.comparisons)
        comparison.digest: comparison,
    };
    final bindingsById =
        <ScenarioComparisonBindingId, ScenarioComparisonBinding>{
          for (final binding in manifest.comparisonBindings)
            binding.id: binding,
        };
    if (!_sameDigestSet(
          descriptor.requiredEvidenceResultDigests,
          evidenceByDigest.keys,
        ) ||
        !_sameDigestSet(
          descriptor.comparisonResultDigests,
          comparisonsByDigest.keys,
        )) {
      throw const FormatException(
        'Scenario Quality review artifacts do not cover the terminal result',
      );
    }
    for (final artifact in descriptor.artifacts) {
      final evidence = evidenceByDigest[artifact.requiredEvidenceResultDigest];
      if (evidence == null ||
          evidence.requiredEvidenceId != artifact.requiredEvidenceId) {
        throw const FormatException(
          'Scenario Quality artifact does not bind exact RequiredEvidence',
        );
      }
      switch (artifact.role) {
        case ScenarioQualityReviewArtifactRole.requiredEvidence:
          _validateCollectedReviewArtifact(artifact, evidence);
        case ScenarioQualityReviewArtifactRole.comparisonBaseline ||
            ScenarioQualityReviewArtifactRole.comparisonCandidate:
          final comparison =
              comparisonsByDigest[artifact.comparisonResultDigest];
          if (comparison == null ||
              (artifact.role ==
                          ScenarioQualityReviewArtifactRole.comparisonBaseline
                      ? comparison.baselineDigest
                      : comparison.candidateDigest) !=
                  artifact.artifactDigest) {
            throw const FormatException(
              'Scenario Quality artifact crossed its comparison digest fence',
            );
          }
          final binding = bindingsById[comparison.bindingId];
          if (binding == null ||
              binding.scenarioId != snapshot.scenarioId ||
              binding.requiredEvidenceId != comparison.requiredEvidenceId) {
            throw const FormatException(
              'Scenario Quality comparison binding is unavailable',
            );
          }
          final input =
              artifact.role ==
                  ScenarioQualityReviewArtifactRole.comparisonBaseline
              ? binding.baseline
              : binding.candidate;
          _validateComparisonReviewArtifact(
            artifact,
            input,
            evidenceById,
            snapshot.scenarioId,
          );
      }
    }
  }

  void _validateComparisonReviewArtifact(
    ScenarioQualityReviewArtifactDescriptor artifact,
    ComparisonInputReference input,
    Map<RequiredEvidenceId, RequiredEvidenceRunResult> evidenceById,
    ScenarioId scenarioId,
  ) {
    switch (input) {
      case RequiredEvidenceComparisonInputReference(:final requiredEvidenceId):
        final evidence = evidenceById[requiredEvidenceId];
        if (evidence == null) {
          throw const FormatException(
            'Scenario Quality comparison RequiredEvidence is absent',
          );
        }
        _validateCollectedReviewArtifact(artifact, evidence);
      case ArtifactComparisonInputReference(:final artifactId):
        final references = manifest.supplementalArtifacts
            .where((reference) => reference.id == artifactId)
            .toList(growable: false);
        final expectedRole =
            artifact.role ==
                ScenarioQualityReviewArtifactRole.comparisonBaseline
            ? SupplementalArtifactRole.comparisonBaseline
            : SupplementalArtifactRole.comparisonCandidate;
        if (references.length != 1) {
          throw const FormatException(
            'Scenario Quality supplemental comparison input is absent',
          );
        }
        final reference = references.single;
        final evidence = evidenceById[reference.requiredEvidenceId];
        if (reference.scenarioId != scenarioId ||
            reference.role != expectedRole ||
            evidence == null ||
            evidence.digest != artifact.requiredEvidenceResultDigest ||
            artifact.requiredEvidenceId != reference.requiredEvidenceId ||
            artifact.artifactDigest != reference.artifactDigest ||
            artifact.provenanceDigest != reference.provenanceDigest ||
            artifact.classification != reference.classification ||
            artifact.provenanceKind !=
                ScenarioQualityReviewProvenanceKind
                    .supplementalArtifactImport) {
          throw const FormatException(
            'Scenario Quality supplemental artifact crossed its manifest fence',
          );
        }
      case EvidenceComparisonInputReference():
        throw const FormatException(
          'Scenario Quality raw Evidence comparison is unsupported for review',
        );
    }
  }

  void _validateCollectedReviewArtifact(
    ScenarioQualityReviewArtifactDescriptor artifact,
    RequiredEvidenceRunResult evidence,
  ) {
    if (evidence.state != RequiredEvidenceResultState.collected ||
        evidence.artifacts.length != 1 ||
        artifact.requiredEvidenceId != evidence.requiredEvidenceId ||
        artifact.requiredEvidenceResultDigest != evidence.digest) {
      throw const FormatException(
        'Scenario Quality collected artifact crossed its result fence',
      );
    }
    final collected = evidence.artifacts.single;
    if (artifact.artifactDigest != collected.artifactDigest ||
        artifact.provenanceDigest != collected.provenanceDigest ||
        artifact.classification != collected.classification ||
        artifact.provenanceKind !=
            ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt) {
      throw const FormatException(
        'Scenario Quality collected artifact crossed its provenance fence',
      );
    }
  }

  bool _sameDigestSet(Iterable<Digest> left, Iterable<Digest> right) {
    final leftSet = left.toSet();
    final rightSet = right.toSet();
    return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
  }

  void _resolvePinnedReviewGuide(
    ScenarioQualityReviewDescriptor descriptor,
    ScenarioLabRunResult result,
  ) {
    final resolved = _validatePinnedReviewGuide(descriptor, result);
    _reviewGuideTitle = resolved.guide.title;
    _reviewInstruction = resolved.step.instruction;
    _reviewCriteria = resolved.step.observationCriteria;
  }

  ({ReviewGuide guide, ReviewGuideStep step}) _validatePinnedReviewGuide(
    ScenarioQualityReviewDescriptor descriptor,
    ScenarioLabRunResult result,
  ) {
    final requirements = manifest.humanApprovalRequirements
        .where((item) => item.id == descriptor.requirementId)
        .toList(growable: false);
    final guides = catalog.reviewGuides
        .where((item) => item.id == descriptor.reviewGuideId)
        .toList(growable: false);
    if (requirements.length != 1 || guides.length != 1) {
      throw const FormatException(
        'Scenario Quality review policy is absent from the pinned Catalog',
      );
    }
    final requirement = requirements.single;
    final guide = guides.single;
    final plans = manifest.plans
        .where(
          (plan) =>
              plan.scenarioId == result.finalSnapshot.scenarioId &&
              plan.scriptIds.contains(result.finalSnapshot.scriptId) &&
              plan.humanApprovalRequirementIds.contains(requirement.id),
        )
        .toList(growable: false);
    final steps = guide.steps
        .where((item) => item.id == descriptor.reviewGuideStepId)
        .toList(growable: false);
    if (plans.length != 1 ||
        steps.length != 1 ||
        requirement.scenarioId != result.finalSnapshot.scenarioId ||
        requirement.reviewGuideId != descriptor.reviewGuideId ||
        requirement.reviewGuideStepId != descriptor.reviewGuideStepId ||
        requirement.scope != descriptor.requirementScope ||
        steps.single.scenarioId != result.finalSnapshot.scenarioId) {
      throw const FormatException(
        'Scenario Quality review guide crossed its Catalog fence',
      );
    }
    return (guide: guide, step: steps.single);
  }

  void _validateOpen(
    ScenarioQualityReviewOpenResult opened,
    ScenarioQualityReviewOpenRequest request,
  ) {
    final descriptor = opened.reviewDescriptor;
    if (descriptor.runId != request.runId ||
        descriptor.runResultDigest != request.expectedRunResultDigest ||
        descriptor.qualityDigest != request.expectedQualityDigest ||
        descriptor.digest != request.expectedReviewDescriptorDigest) {
      throw const FormatException(
        'Scenario Quality open response crossed its immutable fence',
      );
    }
  }

  void _validateProvenance(
    ScenarioQualityReviewArtifactDescriptor descriptor,
    Object provenance,
    ScenarioLabRunId runId,
  ) {
    switch ((descriptor.provenanceKind, provenance)) {
      case (
        ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
        final AppAdapterCaptureReceipt receipt,
      ):
        if (receipt.digest != descriptor.provenanceDigest ||
            receipt.artifactDigest != descriptor.artifactDigest ||
            receipt.size != descriptor.size ||
            receipt.sessionId != runId.value ||
            descriptor.mediaType != 'image/png') {
          throw const FormatException(
            'App Adapter capture provenance crossed its artifact fence',
          );
        }
      case (
        ScenarioQualityReviewProvenanceKind.supplementalArtifactImport,
        final ScenarioLabSupplementalArtifactProvenance supplemental,
      ):
        if (supplemental.digest != descriptor.provenanceDigest ||
            supplemental.artifactDigest != descriptor.artifactDigest ||
            supplemental.size != descriptor.size ||
            supplemental.mediaType.value != descriptor.mediaType ||
            supplemental.classification != descriptor.classification) {
          throw const FormatException(
            'Supplemental artifact provenance crossed its artifact fence',
          );
        }
      default:
        throw const FormatException(
          'Scenario Quality provenance kind is inconsistent',
        );
    }
  }

  void _validateGrant(
    ScenarioQualityDecisionGrant grant,
    ScenarioQualityDecisionGrantRequest request,
    ScenarioQualityReviewDescriptor descriptor,
  ) {
    if (grant.requestId != request.requestId ||
        grant.requestDigest != request.digest ||
        grant.runId != request.runId ||
        grant.runResultDigest != request.expectedRunResultDigest ||
        grant.qualityDigest != request.expectedQualityDigest ||
        grant.reviewDescriptorDigest !=
            request.expectedReviewDescriptorDigest ||
        grant.requirementId != descriptor.requirementId ||
        grant.requirementScope != descriptor.requirementScope ||
        grant.reviewGuideId != descriptor.reviewGuideId ||
        grant.reviewGuideStepId != descriptor.reviewGuideStepId ||
        grant.expectedPreviousDecisionDigest !=
            request.expectedPreviousDecisionDigest ||
        grant.decision != request.decision) {
      throw const FormatException(
        'Scenario Quality grant crossed its confirmation fence',
      );
    }
  }

  void _validateAppend(
    ScenarioQualityDecisionAppendResult appended,
    ScenarioQualityDecisionAppendRequest request, {
    required ScenarioQualityDecisionGrant grant,
    required ScenarioQualityDecisionGrantRequest grantRequest,
    required ScenarioQualityReviewDescriptor descriptor,
    required ScenarioQualitySnapshot priorQuality,
  }) {
    final attribution = appended.attribution;
    if (appended.requestId != request.requestId ||
        appended.requestDigest != request.digest ||
        attribution.runId != grant.runId ||
        attribution.runResultDigest != grant.runResultDigest ||
        attribution.reviewDescriptorDigest != grant.reviewDescriptorDigest ||
        attribution.reviewDescriptorDigest != descriptor.digest ||
        attribution.requirementId != grant.requirementId ||
        attribution.requirementScope != grant.requirementScope ||
        attribution.reviewGuideId != grant.reviewGuideId ||
        attribution.reviewGuideStepId != grant.reviewGuideStepId ||
        attribution.authorityId != grant.authorityId ||
        attribution.accessPolicyId != grant.accessPolicyId ||
        attribution.principalId != grant.principalId ||
        attribution.role != grant.role ||
        attribution.grantDigest != grant.digest ||
        attribution.grantRequestDigest != grantRequest.digest ||
        attribution.decisionRequestDigest != request.digest ||
        grant.requestDigest != grantRequest.digest ||
        appended.record.principalId != grant.principalId ||
        appended.record.decision != request.decision ||
        appended.record.supersedesDecisionDigest !=
            request.expectedPreviousDecisionDigest ||
        appended.quality.runId != request.runId ||
        appended.quality.subjectDigest != request.expectedRunResultDigest ||
        !_sameAutomatedQuality(priorQuality, appended.quality)) {
      throw const FormatException(
        'Scenario Quality append changed an automated Quality axis',
      );
    }
  }

  void _validateHistoryView(
    ScenarioQualityDecisionView view,
    ScenarioLabRunResult result,
    Digest expectedDigest,
    ScenarioQualityDecisionView? newer,
  ) {
    if (view.record.digest != expectedDigest ||
        view.record.subjectDigest != result.digest ||
        view.attribution.runId != result.finalSnapshot.runId ||
        view.attribution.runResultDigest != result.digest ||
        view.reviewDescriptor.runId != result.finalSnapshot.runId ||
        view.reviewDescriptor.runResultDigest != result.digest ||
        (_requirementId != null &&
            view.reviewDescriptor.requirementId != _requirementId)) {
      throw const FormatException(
        'Scenario Quality history view crossed its terminal-run fence',
      );
    }
    _validatePinnedReviewGuide(view.reviewDescriptor, result);
    _validateReviewArtifacts(view.reviewDescriptor, result);
    if (newer == null) {
      final projected = _quality?.humanDecision;
      final expectedState = switch (view.record.decision) {
        HumanDecision.approved => HumanDecisionState.approved,
        HumanDecision.rejected => HumanDecisionState.rejected,
      };
      if (projected == null ||
          view.projection.state != projected.state ||
          view.projection.decisionDigest != projected.decisionDigest ||
          view.projection.supersededByDecisionDigest !=
              projected.supersededByDecisionDigest ||
          view.projection.state != expectedState) {
        throw const FormatException(
          'Scenario Quality head does not match the current Quality projection',
        );
      }
    } else {
      newer.record.validateSupersedes(view.record);
      if (view.projection.state != HumanDecisionState.superseded ||
          view.projection.supersededByDecisionDigest != newer.record.digest) {
        throw const FormatException(
          'Scenario Quality supersession projection is inconsistent',
        );
      }
    }
  }

  bool _sameAutomatedQuality(
    ScenarioQualitySnapshot left,
    ScenarioQualitySnapshot right,
  ) =>
      left.runId == right.runId &&
      left.subjectDigest == right.subjectDigest &&
      left.scenarioId == right.scenarioId &&
      left.verificationState == right.verificationState &&
      Digest.semantic(<String, Object?>{
            'requiredEvidence': left.requiredEvidence
                .map((item) => item.toJson())
                .toList(),
            'comparisons': left.comparisonResultDigests
                .map((item) => item.value)
                .toList(),
          }) ==
          Digest.semantic(<String, Object?>{
            'requiredEvidence': right.requiredEvidence
                .map((item) => item.toJson())
                .toList(),
            'comparisons': right.comparisonResultDigests
                .map((item) => item.value)
                .toList(),
          });

  void _handleTypedFailure(
    int operationEpoch,
    ScenarioQualityDecisionError error, {
    required ScenarioQualityDecisionOperation expectedOperation,
  }) {
    final result = runResult;
    if (!_isCurrent(operationEpoch) || result == null) return;
    if (error.operation != expectedOperation ||
        error.runId != result.finalSnapshot.runId ||
        error.expectedRunResultDigest != result.digest) {
      _failIfCurrent(
        operationEpoch,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      return;
    }
    switch (error.code) {
      case ScenarioQualityDecisionErrorCode.unavailable:
        _availability = ScenarioQualityReviewAvailability.unavailable;
        _transition(ScenarioQualityDecisionOperationState.ready);
      case ScenarioQualityDecisionErrorCode.policyDenied ||
          ScenarioQualityDecisionErrorCode.decisionDenied:
        _availability = ScenarioQualityReviewAvailability.policyDenied;
        _transition(ScenarioQualityDecisionOperationState.ready);
      case ScenarioQualityDecisionErrorCode.unsupported:
        _availability = ScenarioQualityReviewAvailability.unsupported;
        _transition(ScenarioQualityDecisionOperationState.ready);
      default:
        _transition(ScenarioQualityDecisionOperationState.conflict);
    }
  }

  void _clearReviewState() {
    _quality = null;
    _requirementId = null;
    _headDecisionDigest = null;
    _decisionCount = 0;
    _reviewGuideTitle = null;
    _reviewInstruction = null;
    _reviewCriteria = null;
    _pendingDecision = null;
    _currentReviewDescriptor = null;
    _reviewResources.clear();
    _resourceGeneration += 1;
    _history = const <ScenarioQualityDecisionHistoryItem>[];
  }

  ScenarioQualityDecisionRequestId _nextRequestId(String purpose) =>
      _requestIdFactory(purpose, ++_requestSequence);

  bool _isCurrent(int operationEpoch) =>
      _operation != ScenarioQualityDecisionOperationState.closed &&
      operationEpoch == _epoch;

  void _failIfCurrent(
    int operationEpoch,
    ScenarioQualityDecisionOperationState state,
  ) {
    if (_isCurrent(operationEpoch)) _transition(state);
  }

  void _transition(ScenarioQualityDecisionOperationState operation) {
    if (_operation == ScenarioQualityDecisionOperationState.closed &&
        operation != ScenarioQualityDecisionOperationState.closed) {
      return;
    }
    _operation = operation;
    _notify();
  }

  void _notify() => onStateChanged?.call(snapshot);
}

final class _ReviewResource {
  _ReviewResource({required this.descriptor, required this.binding});

  final ScenarioQualityReviewArtifactDescriptor descriptor;
  final ScenarioQualityReviewResourceBinding binding;
  bool provenanceValidated = false;
  bool artifactValidated = false;
  bool imageRendered = false;
  bool rejected = false;

  bool get isImage => descriptor.mediaType == 'image/png';

  ScenarioQualityReviewResourceSnapshot get snapshot =>
      ScenarioQualityReviewResourceSnapshot(
        descriptorDigest: descriptor.digest,
        role: descriptor.role,
        artifactDigest: descriptor.artifactDigest,
        provenanceKind: descriptor.provenanceKind,
        mediaType: descriptor.mediaType,
        state: rejected
            ? ScenarioQualityReviewResourceState.rejected
            : provenanceValidated && artifactValidated
            ? isImage
                  ? imageRendered
                        ? ScenarioQualityReviewResourceState.rendered
                        : ScenarioQualityReviewResourceState.validated
                  : ScenarioQualityReviewResourceState.validated
            : ScenarioQualityReviewResourceState.validating,
      );
}

ScenarioQualityDecisionRequestId _defaultRequestId(
  String purpose,
  int sequence,
) => ScenarioQualityDecisionRequestId(
  'studio-$purpose-${DateTime.now().toUtc().microsecondsSinceEpoch}-$sequence',
);
