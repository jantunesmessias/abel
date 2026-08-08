import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../evidence/local_evidence_repository.dart';
import '../evidence/png_capture_inspector.dart';
import '../host/host_resource_registry.dart';
import '../host/host_rpc_server.dart';
import '../storage/filesystem_workspace_store.dart';
import 'filesystem_scenario_quality_decision_store.dart';
import 'host_scenario_lab_service.dart';
import 'scenario_lab_run_store.dart';

const int _maxReviewAggregateBytes = 64 * 1024 * 1024;
const int _maxReviewProvenanceBytes = 1024 * 1024;

final class HostScenarioQualityDecisionAuthority {
  HostScenarioQualityDecisionAuthority({
    required this.authorityId,
    required this.accessPolicyId,
    required this.principalId,
    required this.role,
    required Iterable<HumanApprovalRequirementId> allowedRequirementIds,
    required Iterable<HumanDecision> allowedDecisions,
    required Iterable<ArtifactClassification> artifactClassifications,
    this.grantTtl = const Duration(minutes: 2),
  }) : allowedRequirementIds = Set<HumanApprovalRequirementId>.unmodifiable(
         allowedRequirementIds,
       ),
       allowedDecisions = Set<HumanDecision>.unmodifiable(allowedDecisions),
       artifactClassifications = Set<ArtifactClassification>.unmodifiable(
         artifactClassifications,
       ) {
    if (this.allowedRequirementIds.length != allowedRequirementIds.length ||
        this.allowedRequirementIds.length > 1000 ||
        this.allowedDecisions.length != allowedDecisions.length ||
        this.artifactClassifications.length != artifactClassifications.length ||
        this.artifactClassifications.contains(
          ArtifactClassification.sensitive,
        ) ||
        grantTtl <= Duration.zero ||
        grantTtl > const Duration(minutes: 5) ||
        (role == ScenarioQualityDecisionRole.observer &&
            this.allowedDecisions.isNotEmpty)) {
      throw ArgumentError('Scenario Quality Host authority is invalid');
    }
  }

  final ScenarioQualityAuthorityId authorityId;
  final ScenarioQualityAccessPolicyId accessPolicyId;
  final ScenarioQualityPrincipalId principalId;
  final ScenarioQualityDecisionRole role;
  final Set<HumanApprovalRequirementId> allowedRequirementIds;
  final Set<HumanDecision> allowedDecisions;
  final Set<ArtifactClassification> artifactClassifications;
  final Duration grantTtl;

  static HostScenarioQualityDecisionAuthority? fromSettings(
    Map<String, Object?> settings,
  ) {
    if (settings.isEmpty) return null;
    const keys = <String>{
      'authorityId',
      'accessPolicyId',
      'principalId',
      'role',
      'allowedRequirementIds',
      'allowedDecisions',
      'artifactClassifications',
      'grantTtlSeconds',
    };
    if (settings.keys.toSet().length != keys.length ||
        !settings.keys.toSet().containsAll(keys)) {
      throw const FormatException('Invalid quality.decisions.local settings');
    }
    String string(String key) {
      final value = settings[key];
      if (value is! String) {
        throw FormatException('quality.decisions.local $key must be a string');
      }
      return value;
    }

    List<Object?> list(String key, int max) {
      final value = settings[key];
      if (value is! List<Object?> || value.length > max) {
        throw FormatException('quality.decisions.local $key is invalid');
      }
      return value;
    }

    T enumeration<T extends Enum>(Iterable<T> values, Object? raw, String key) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
      throw FormatException('quality.decisions.local $key is unsupported');
    }

    final ttlSource = settings['grantTtlSeconds'];
    if (ttlSource is! num ||
        !ttlSource.isFinite ||
        ttlSource != ttlSource.truncateToDouble() ||
        ttlSource < 1 ||
        ttlSource > 300 ||
        ttlSource.abs() > 9007199254740991) {
      throw const FormatException(
        'quality.decisions.local grantTtlSeconds is invalid',
      );
    }
    final ttl = ttlSource.toInt();
    final requirementIds = list('allowedRequirementIds', 1000)
        .map(
          (value) => value is String
              ? HumanApprovalRequirementId(value)
              : (throw const FormatException(
                  'quality.decisions.local requirement ID is invalid',
                )),
        )
        .toList();
    final decisions = list('allowedDecisions', 2)
        .map(
          (value) =>
              enumeration(HumanDecision.values, value, 'allowedDecisions'),
        )
        .toList();
    final classifications = list('artifactClassifications', 2)
        .map(
          (value) => enumeration(
            ArtifactClassification.values,
            value,
            'artifactClassifications',
          ),
        )
        .toList();
    if (requirementIds.toSet().length != requirementIds.length ||
        decisions.toSet().length != decisions.length ||
        classifications.toSet().length != classifications.length) {
      throw const FormatException(
        'quality.decisions.local allowlists must be unique',
      );
    }
    return HostScenarioQualityDecisionAuthority(
      authorityId: ScenarioQualityAuthorityId(string('authorityId')),
      accessPolicyId: ScenarioQualityAccessPolicyId(string('accessPolicyId')),
      principalId: ScenarioQualityPrincipalId(string('principalId')),
      role: enumeration(
        ScenarioQualityDecisionRole.values,
        settings['role'],
        'role',
      ),
      allowedRequirementIds: requirementIds,
      allowedDecisions: decisions,
      artifactClassifications: classifications,
      grantTtl: Duration(seconds: ttl),
    );
  }
}

final class HostScenarioQualityDecisionRejected implements Exception {
  const HostScenarioQualityDecisionRejected(this.error);

  final ScenarioQualityDecisionError error;
}

/// Host-owned review projection, artifact leases and mutation authority.
final class HostScenarioQualityService {
  HostScenarioQualityService({
    required this.workspaceStore,
    required this.runStore,
    required this.decisionStore,
    required this.evidenceRepository,
    required this.readContent,
    required this.clock,
    required this.ids,
    this.authority,
    this.pngInspector = const PngCaptureInspector(),
    this.maxRpcMessageBytes = 64 * 1024,
    this.maxReviewAggregateBytes = _maxReviewAggregateBytes,
  }) {
    if (evidenceRepository.store.workspaceRoot !=
            workspaceStore.workspaceRoot ||
        evidenceRepository.store.stateRoot != workspaceStore.stateRoot ||
        decisionStore.workspaceStore.workspaceRoot !=
            workspaceStore.workspaceRoot ||
        decisionStore.workspaceStore.stateRoot != workspaceStore.stateRoot) {
      throw ArgumentError(
        'Scenario Quality repositories belong to different workspaces',
      );
    }
    if (maxRpcMessageBytes < 1024) {
      throw ArgumentError.value(maxRpcMessageBytes, 'maxRpcMessageBytes');
    }
    if (maxReviewAggregateBytes < 1 ||
        maxReviewAggregateBytes > _maxReviewAggregateBytes) {
      throw ArgumentError.value(
        maxReviewAggregateBytes,
        'maxReviewAggregateBytes',
      );
    }
  }

  final FileSystemWorkspaceStore workspaceStore;
  final ScenarioLabRunStore runStore;
  final FilesystemScenarioQualityDecisionStore decisionStore;
  final LocalEvidenceRepository evidenceRepository;
  final HostScenarioLabContentReader readContent;
  final Clock clock;
  final IdGenerator ids;
  final HostScenarioQualityDecisionAuthority? authority;
  final PngCaptureInspector pngInspector;
  final int maxRpcMessageBytes;
  final int maxReviewAggregateBytes;

  final Map<String, _ReviewLease> _leases = <String, _ReviewLease>{};
  var _closed = false;

  ScenarioQualityDescribeResult describeRequest(
    ScenarioQualityDescribeRequest request,
  ) {
    final exact = _exact(
      request.runId,
      request.expectedRunResultDigest,
      operation: ScenarioQualityDecisionOperation.describe,
    );
    final review = _review(exact);
    if (review.failureCode case final code?) {
      _reject(
        operation: ScenarioQualityDecisionOperation.describe,
        code: code,
        exact: exact,
      );
    }
    final result = ScenarioQualityDescribeResult(
      description: ScenarioQualityDescription(
        runId: request.runId,
        runResultDigest: exact.result.digest,
        quality: exact.history.quality,
        availability: review.availability,
        requirementId: review.requirement?.id,
        headDecisionDigest: exact.history.head?.digest,
        decisionCount: exact.history.records.length,
      ),
      reviewDescriptor:
          review.availability == ScenarioQualityReviewAvailability.available
          ? review.descriptor
          : null,
    );
    if (!HostRpcServer.successPayloadFits(
      result.toJson(),
      maxMessageBytes: maxRpcMessageBytes,
    )) {
      _reject(
        operation: ScenarioQualityDecisionOperation.describe,
        code: ScenarioQualityDecisionErrorCode.quotaExceeded,
        exact: exact,
      );
    }
    return result;
  }

  ScenarioQualityReviewOpenResult openRequest({
    required ScenarioQualityReviewOpenRequest request,
    required HostResourceRegistry resources,
    required Uri hostOrigin,
    required Uri audienceOrigin,
  }) {
    _ensureOpen();
    final exact = _exact(
      request.runId,
      request.expectedRunResultDigest,
      operation: ScenarioQualityDecisionOperation.open,
    );
    final review = _requireAvailableReview(
      exact,
      ScenarioQualityDecisionOperation.open,
    );
    final descriptor = review.availableDescriptor;
    if (request.expectedQualityDigest != exact.history.quality.digest ||
        request.expectedReviewDescriptorDigest != descriptor.digest) {
      _reject(
        operation: ScenarioQualityDecisionOperation.open,
        code: ScenarioQualityDecisionErrorCode.staleQuality,
        exact: exact,
      );
    }
    final key = request.runId.value;
    final previous = _leases[key];
    final inputs = <HostResourceGrantInput>[];
    for (final artifact in review.artifacts) {
      inputs.add(
        HostResourceGrantInput(
          bytes: artifact.bytes,
          mediaType: artifact.descriptor.mediaType,
          purpose: 'scenario-quality-review-artifact',
          classification: artifact.descriptor.classification,
          ttl: const Duration(minutes: 2),
        ),
      );
      inputs.add(
        HostResourceGrantInput(
          bytes: artifact.provenanceBytes,
          mediaType: 'application/json',
          purpose: 'scenario-quality-review-provenance',
          classification: artifact.descriptor.classification,
          ttl: const Duration(minutes: 2),
        ),
      );
    }
    final preview = _previewOpenResult(
      descriptor: descriptor,
      artifacts: review.artifacts,
      hostOrigin: hostOrigin,
    );
    if (!HostRpcServer.successPayloadFits(
      preview.toJson(),
      maxMessageBytes: maxRpcMessageBytes,
    )) {
      _reject(
        operation: ScenarioQualityDecisionOperation.open,
        code: ScenarioQualityDecisionErrorCode.quotaExceeded,
        exact: exact,
      );
    }
    final replaceablePrevious =
        previous != null && identical(previous.resources, resources)
        ? previous.handles
        : const <ResourceHandle>[];
    if (!resources.replacementFits(
      inputs: inputs,
      previous: replaceablePrevious,
    )) {
      _reject(
        operation: ScenarioQualityDecisionOperation.open,
        code: ScenarioQualityDecisionErrorCode.quotaExceeded,
        exact: exact,
      );
    }
    final List<ResourceHandle> handles;
    try {
      handles = resources.replaceByteSet(
        hostOrigin: hostOrigin,
        audienceOrigin: audienceOrigin,
        inputs: inputs,
        previous: replaceablePrevious,
      );
    } on StateError {
      _reject(
        operation: ScenarioQualityDecisionOperation.open,
        code: ScenarioQualityDecisionErrorCode.quotaExceeded,
        exact: exact,
      );
    }
    final bindings = <ScenarioQualityReviewResourceBinding>[];
    for (var index = 0; index < review.artifacts.length; index += 1) {
      bindings.add(
        ScenarioQualityReviewResourceBinding(
          artifactDescriptorDigest: review.artifacts[index].descriptor.digest,
          artifact: handles[index * 2],
          provenance: handles[index * 2 + 1],
        ),
      );
    }
    if (previous != null && !identical(previous.resources, resources)) {
      for (final handle in previous.handles) {
        previous.resources.revoke(handle);
      }
    }
    _leases[key] = _ReviewLease(
      resources: resources,
      handles: handles,
      descriptorDigest: descriptor.digest,
    );
    return ScenarioQualityReviewOpenResult(
      reviewDescriptor: descriptor,
      resources: bindings,
    );
  }

  ScenarioQualityDecisionGrant grantRequest(
    ScenarioQualityDecisionGrantRequest request,
  ) {
    _ensureOpen();
    try {
      final replay = decisionStore.replayGrant(request);
      if (replay != null) {
        if (!HostRpcServer.successPayloadFits(
          replay.toJson(),
          maxMessageBytes: maxRpcMessageBytes,
        )) {
          _rejectWithoutExact(
            operation: ScenarioQualityDecisionOperation.grant,
            code: ScenarioQualityDecisionErrorCode.quotaExceeded,
            runId: request.runId,
            resultDigest: request.expectedRunResultDigest,
            requestId: request.requestId,
            currentQualityDigest: replay.qualityDigest,
            currentDecisionDigest: replay.expectedPreviousDecisionDigest,
          );
        }
        return replay;
      }
    } on ScenarioQualityDecisionStoreFailure catch (failure) {
      _rejectWithoutExact(
        operation: ScenarioQualityDecisionOperation.grant,
        code: failure.code,
        runId: request.runId,
        resultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
        currentQualityDigest: failure.currentQualityDigest,
        currentDecisionDigest: failure.currentDecisionDigest,
      );
    }
    final exact = _exact(
      request.runId,
      request.expectedRunResultDigest,
      operation: ScenarioQualityDecisionOperation.grant,
      requestId: request.requestId,
    );
    final review = _requireAvailableReview(
      exact,
      ScenarioQualityDecisionOperation.grant,
      requestId: request.requestId,
    );
    final resolvedAuthority =
        authority ??
        (throw StateError('Available review has no Host authority'));
    final descriptor = review.availableDescriptor;
    final requirement = review.availableRequirement;
    final now = clock.nowUtc();
    final lease = _leases[request.runId.value];
    if (lease == null ||
        lease.descriptorDigest != descriptor.digest ||
        lease.handles.length != descriptor.artifacts.length * 2 ||
        lease.handles.any((handle) => !now.isBefore(handle.expiresAt))) {
      _reject(
        operation: ScenarioQualityDecisionOperation.grant,
        code: ScenarioQualityDecisionErrorCode.unavailable,
        exact: exact,
        requestId: request.requestId,
      );
    }
    if (!resolvedAuthority.allowedDecisions.contains(request.decision)) {
      _reject(
        operation: ScenarioQualityDecisionOperation.grant,
        code: ScenarioQualityDecisionErrorCode.decisionDenied,
        exact: exact,
        requestId: request.requestId,
      );
    }
    try {
      return decisionStore.issueGrant(
        request: request,
        baseQuality: exact.baseQuality,
        result: exact.result,
        reviewDescriptor: descriptor,
        now: now,
        createGrant: (quality, head) {
          final grant = ScenarioQualityDecisionGrant(
            id: ScenarioQualityDecisionGrantId(_nextId('quality-grant')),
            requestId: request.requestId,
            requestDigest: request.digest,
            authorityId: resolvedAuthority.authorityId,
            accessPolicyId: resolvedAuthority.accessPolicyId,
            principalId: resolvedAuthority.principalId,
            role: resolvedAuthority.role,
            runId: request.runId,
            runResultDigest: exact.result.digest,
            qualityDigest: quality.digest,
            reviewDescriptorDigest: descriptor.digest,
            requirementId: requirement.id,
            requirementScope: requirement.scope,
            reviewGuideId: requirement.reviewGuideId,
            reviewGuideStepId: requirement.reviewGuideStepId,
            expectedPreviousDecisionDigest: head?.digest,
            decision: request.decision,
            issuedAt: now,
            expiresAt: now.add(resolvedAuthority.grantTtl),
          );
          if (!HostRpcServer.successPayloadFits(
            grant.toJson(),
            maxMessageBytes: maxRpcMessageBytes,
          )) {
            throw ScenarioQualityDecisionStoreFailure(
              ScenarioQualityDecisionErrorCode.quotaExceeded,
              currentQualityDigest: quality.digest,
              currentDecisionDigest: head?.digest,
            );
          }
          return grant;
        },
      );
    } on ScenarioQualityDecisionStoreFailure catch (failure) {
      _rejectStore(
        operation: ScenarioQualityDecisionOperation.grant,
        requestId: request.requestId,
        exact: exact,
        failure: failure,
      );
    }
  }

  ScenarioQualityDecisionAppendResult appendRequest(
    ScenarioQualityDecisionAppendRequest request,
  ) {
    _ensureOpen();
    try {
      final replay = decisionStore.replayAppend(request);
      if (replay != null) {
        if (!HostRpcServer.successPayloadFits(
          replay.toJson(),
          maxMessageBytes: maxRpcMessageBytes,
        )) {
          _rejectWithoutExact(
            operation: ScenarioQualityDecisionOperation.append,
            code: ScenarioQualityDecisionErrorCode.quotaExceeded,
            runId: request.runId,
            resultDigest: request.expectedRunResultDigest,
            requestId: request.requestId,
            currentQualityDigest: replay.quality.digest,
            currentDecisionDigest: replay.record.digest,
          );
        }
        return replay;
      }
    } on ScenarioQualityDecisionStoreFailure catch (failure) {
      _rejectWithoutExact(
        operation: ScenarioQualityDecisionOperation.append,
        code: failure.code,
        runId: request.runId,
        resultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
        currentQualityDigest: failure.currentQualityDigest,
        currentDecisionDigest: failure.currentDecisionDigest,
      );
    }
    final attemptNow = clock.nowUtc();
    try {
      decisionStore.prepareAppendAttempt(request: request, now: attemptNow);
    } on ScenarioQualityDecisionStoreFailure catch (failure) {
      _rejectWithoutExact(
        operation: ScenarioQualityDecisionOperation.append,
        code: failure.code,
        runId: request.runId,
        resultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
        currentQualityDigest: failure.currentQualityDigest,
        currentDecisionDigest: failure.currentDecisionDigest,
      );
    }
    final _ExactQuality exact;
    try {
      exact = _exact(
        request.runId,
        request.expectedRunResultDigest,
        operation: ScenarioQualityDecisionOperation.append,
        requestId: request.requestId,
      );
    } on HostScenarioQualityDecisionRejected catch (rejection) {
      try {
        decisionStore.consumePreparedAttempt(
          request: request,
          now: attemptNow,
          code: rejection.error.code,
          currentQualityDigest: rejection.error.currentQualityDigest,
          currentDecisionDigest: rejection.error.currentDecisionDigest,
        );
      } on ScenarioQualityDecisionStoreFailure catch (failure) {
        _rejectWithoutExact(
          operation: ScenarioQualityDecisionOperation.append,
          code: failure.code,
          runId: request.runId,
          resultDigest: request.expectedRunResultDigest,
          requestId: request.requestId,
          currentQualityDigest: failure.currentQualityDigest,
          currentDecisionDigest: failure.currentDecisionDigest,
        );
      }
    }
    final review = _review(exact);
    final resolvedAuthority = authority;
    final preflightRejection =
        review.failureCode ??
        switch (review.availability) {
          ScenarioQualityReviewAvailability.available => null,
          ScenarioQualityReviewAvailability.policyDenied =>
            ScenarioQualityDecisionErrorCode.policyDenied,
          ScenarioQualityReviewAvailability.unsupported =>
            ScenarioQualityDecisionErrorCode.unsupported,
          ScenarioQualityReviewAvailability.unavailable =>
            ScenarioQualityDecisionErrorCode.unavailable,
        };
    try {
      return decisionStore.append(
        request: request,
        baseQuality: exact.baseQuality,
        result: exact.result,
        reviewDescriptor: review.descriptor,
        preflightRejection: preflightRejection,
        currentAuthorityId: resolvedAuthority?.authorityId,
        currentAccessPolicyId: resolvedAuthority?.accessPolicyId,
        currentPrincipalId: resolvedAuthority?.principalId,
        currentRole: resolvedAuthority?.role,
        decisionCurrentlyAllowed:
            resolvedAuthority?.allowedDecisions.contains(request.decision) ??
            false,
        now: attemptNow,
        createRecordId: () =>
            HumanDecisionRecordId(_nextId('quality-decision')),
        canReturnResult: (result) => HostRpcServer.successPayloadFits(
          result.toJson(),
          maxMessageBytes: maxRpcMessageBytes,
        ),
      );
    } on ScenarioQualityDecisionStoreFailure catch (failure) {
      _rejectStore(
        operation: ScenarioQualityDecisionOperation.append,
        requestId: request.requestId,
        exact: exact,
        failure: failure,
      );
    }
  }

  ScenarioQualityDecisionView getRequest(
    ScenarioQualityDecisionGetRequest request,
  ) {
    final exact = _exact(
      request.runId,
      request.expectedRunResultDigest,
      operation: ScenarioQualityDecisionOperation.get,
    );
    final view = decisionStore.getDecision(
      baseQuality: exact.baseQuality,
      result: exact.result,
      decisionDigest: request.decisionDigest,
    );
    if (view == null) {
      _reject(
        operation: ScenarioQualityDecisionOperation.get,
        code: ScenarioQualityDecisionErrorCode.notFound,
        exact: exact,
      );
    }
    if (!HostRpcServer.successPayloadFits(
      view.toJson(),
      maxMessageBytes: maxRpcMessageBytes,
    )) {
      _reject(
        operation: ScenarioQualityDecisionOperation.get,
        code: ScenarioQualityDecisionErrorCode.quotaExceeded,
        exact: exact,
      );
    }
    return view;
  }

  bool revokeGrant(ScenarioQualityDecisionGrantId grantId) =>
      decisionStore.revokeGrant(grantId: grantId, revokedAt: clock.nowUtc());

  Map<String, Object?> describe(Map<String, Object?> params) =>
      describeRequest(ScenarioQualityDescribeRequest.fromJson(params)).toJson();

  Map<String, Object?> grant(Map<String, Object?> params) => grantRequest(
    ScenarioQualityDecisionGrantRequest.fromJson(params),
  ).toJson();

  Map<String, Object?> append(Map<String, Object?> params) => appendRequest(
    ScenarioQualityDecisionAppendRequest.fromJson(params),
  ).toJson();

  Map<String, Object?> get(Map<String, Object?> params) =>
      getRequest(ScenarioQualityDecisionGetRequest.fromJson(params)).toJson();

  void close() {
    if (_closed) return;
    _closed = true;
    for (final lease in _leases.values) {
      for (final handle in lease.handles) {
        lease.resources.revoke(handle);
      }
    }
    _leases.clear();
  }

  _ExactQuality _exact(
    ScenarioLabRunId runId,
    Digest expectedResultDigest, {
    required ScenarioQualityDecisionOperation operation,
    ScenarioQualityDecisionRequestId? requestId,
  }) {
    final ScenarioLabStoredRun stored;
    try {
      stored = runStore.requireRun(runId);
    } on ScenarioLabRunNotFound {
      throw HostScenarioQualityDecisionRejected(
        ScenarioQualityDecisionError(
          operation: operation,
          code: ScenarioQualityDecisionErrorCode.notFound,
          runId: runId,
          expectedRunResultDigest: expectedResultDigest,
          requestId: requestId,
        ),
      );
    }
    final result = stored.result;
    if (result == null) {
      throw HostScenarioQualityDecisionRejected(
        ScenarioQualityDecisionError(
          operation: operation,
          code: ScenarioQualityDecisionErrorCode.runNotTerminal,
          runId: runId,
          expectedRunResultDigest: expectedResultDigest,
          requestId: requestId,
        ),
      );
    }
    if (result.digest != expectedResultDigest) {
      throw HostScenarioQualityDecisionRejected(
        ScenarioQualityDecisionError(
          operation: operation,
          code: ScenarioQualityDecisionErrorCode.subjectMismatch,
          runId: runId,
          expectedRunResultDigest: expectedResultDigest,
          requestId: requestId,
        ),
      );
    }
    if (result.finalSnapshot.requiredEvidence.length > 32 ||
        result.finalSnapshot.comparisons.length > 32 ||
        result.finalSnapshot.requiredEvidence.length +
                (result.finalSnapshot.comparisons.length * 2) >
            32) {
      throw HostScenarioQualityDecisionRejected(
        ScenarioQualityDecisionError(
          operation: operation,
          code: ScenarioQualityDecisionErrorCode.quotaExceeded,
          runId: runId,
          expectedRunResultDigest: expectedResultDigest,
          requestId: requestId,
        ),
      );
    }
    final base = _baseQuality(result);
    final history = decisionStore.history(baseQuality: base, result: result);
    return _ExactQuality(result: result, baseQuality: base, history: history);
  }

  _ResolvedReview _review(_ExactQuality exact) {
    final HostScenarioLabContent content;
    try {
      content = readContent();
    } on Object {
      return _ResolvedReview.unavailable();
    }
    final snapshot = exact.result.finalSnapshot;
    if (content.identity.contentSetDigest != snapshot.contentSetDigest ||
        content.identity.catalogDigest != snapshot.catalogDigest ||
        content.identity.scenarioLabManifestDigest !=
            snapshot.scenarioLabManifestDigest ||
        content.catalog.digest != snapshot.catalogDigest ||
        content.manifest.digest != snapshot.scenarioLabManifestDigest) {
      return _ResolvedReview.unavailable();
    }
    final plans = content.manifest.plans.where(
      (plan) =>
          plan.scenarioId == snapshot.scenarioId &&
          plan.scriptIds.contains(snapshot.scriptId),
    );
    if (plans.length != 1) return _ResolvedReview.unavailable();
    final plan = plans.single;
    if (plan.humanApprovalRequirementIds.length != 1) {
      return _ResolvedReview.unavailable();
    }
    final requirements = content.manifest.humanApprovalRequirements.where(
      (item) => item.id == plan.humanApprovalRequirementIds.single,
    );
    if (requirements.length != 1) return _ResolvedReview.unavailable();
    final requirement = requirements.single;
    if (requirement.scope != HumanApprovalScope.evidenceSet) {
      return _ResolvedReview.unsupported(requirement);
    }
    final resolvedAuthority = authority;
    if (resolvedAuthority == null ||
        resolvedAuthority.role != ScenarioQualityDecisionRole.reviewer ||
        resolvedAuthority.allowedDecisions.isEmpty ||
        !resolvedAuthority.allowedRequirementIds.contains(requirement.id)) {
      return _ResolvedReview.policyDenied(requirement);
    }
    if (!_knownClassificationsAllowed(
      snapshot: snapshot,
      content: content,
      authority: resolvedAuthority,
    )) {
      return _ResolvedReview.policyDenied(requirement);
    }
    final evidenceStates = snapshot.requiredEvidence.map((item) => item.state);
    if (evidenceStates.contains(RequiredEvidenceResultState.policyDenied)) {
      return _ResolvedReview.policyDenied(requirement);
    }
    if (evidenceStates.contains(RequiredEvidenceResultState.unsupported)) {
      return _ResolvedReview.unsupported(requirement);
    }
    if (evidenceStates.any(
      (state) => state != RequiredEvidenceResultState.collected,
    )) {
      return _ResolvedReview.unavailable(requirement);
    }
    try {
      final artifacts = _resolveArtifacts(
        exact: exact,
        content: content,
        plan: plan,
      );
      if (artifacts.length > 32) {
        return _ResolvedReview.quotaExceeded(requirement);
      }
      if (artifacts.any(
        (artifact) => !resolvedAuthority.artifactClassifications.contains(
          artifact.descriptor.classification,
        ),
      )) {
        return _ResolvedReview.policyDenied(requirement);
      }
      if (artifacts.any(
        (artifact) => artifact.descriptor.mediaType != 'image/png',
      )) {
        return _ResolvedReview.unsupported(requirement);
      }
      final descriptor = ScenarioQualityReviewDescriptor(
        runId: snapshot.runId,
        runResultDigest: exact.result.digest,
        qualityDigest: exact.history.quality.digest,
        requirementId: requirement.id,
        requirementScope: requirement.scope,
        reviewGuideId: requirement.reviewGuideId,
        reviewGuideStepId: requirement.reviewGuideStepId,
        requiredEvidenceResultDigests: snapshot.requiredEvidence.map(
          (result) => result.digest,
        ),
        comparisonResultDigests: snapshot.comparisons.map(
          (result) => result.digest,
        ),
        artifacts: artifacts.map((artifact) => artifact.descriptor),
      );
      return _ResolvedReview.available(
        requirement: requirement,
        descriptor: descriptor,
        artifacts: artifacts,
      );
    } on _ReviewQuotaExceeded {
      return _ResolvedReview.quotaExceeded(requirement);
    } on _ReviewUnsupported {
      return _ResolvedReview.unsupported(requirement);
    } on Object {
      return _ResolvedReview.unavailable(requirement);
    }
  }

  bool _knownClassificationsAllowed({
    required ScenarioLabRunSnapshot snapshot,
    required HostScenarioLabContent content,
    required HostScenarioQualityDecisionAuthority authority,
  }) {
    for (final result in snapshot.requiredEvidence) {
      for (final artifact in result.artifacts) {
        if (!authority.artifactClassifications.contains(
          artifact.classification,
        )) {
          return false;
        }
      }
    }
    for (final comparison in snapshot.comparisons) {
      final bindings = content.manifest.comparisonBindings.where(
        (binding) => binding.id == comparison.bindingId,
      );
      if (bindings.length != 1) continue;
      for (final input in <ComparisonInputReference>[
        bindings.single.baseline,
        bindings.single.candidate,
      ]) {
        if (input case ArtifactComparisonInputReference(:final artifactId)) {
          final references = content.manifest.supplementalArtifacts.where(
            (artifact) => artifact.id == artifactId,
          );
          if (references.length == 1 &&
              !authority.artifactClassifications.contains(
                references.single.classification,
              )) {
            return false;
          }
        }
      }
    }
    return true;
  }

  List<_ResolvedReviewArtifact> _resolveArtifacts({
    required _ExactQuality exact,
    required HostScenarioLabContent content,
    required ScenarioLabPlan plan,
  }) {
    final snapshot = exact.result.finalSnapshot;
    if (plan.requiredEvidenceIds.length != snapshot.requiredEvidence.length ||
        !plan.requiredEvidenceIds.toSet().containsAll(
          snapshot.requiredEvidence.map((result) => result.requiredEvidenceId),
        ) ||
        plan.comparisonBindingIds.length != snapshot.comparisons.length ||
        !plan.comparisonBindingIds.toSet().containsAll(
          snapshot.comparisons.map((result) => result.bindingId),
        )) {
      throw const FormatException('Review plan/result set mismatch');
    }
    final byteBudget = _ReviewByteBudget(maxReviewAggregateBytes);
    final required = <RequiredEvidenceId, _CollectedReviewArtifact>{};
    final artifacts = <_ResolvedReviewArtifact>[];
    for (final result in snapshot.requiredEvidence) {
      final collected = _resolveCollected(snapshot, result, byteBudget);
      required[result.requiredEvidenceId] = collected;
      artifacts.add(
        collected.withRole(ScenarioQualityReviewArtifactRole.requiredEvidence),
      );
    }
    for (final comparison in snapshot.comparisons) {
      final bindings = content.manifest.comparisonBindings.where(
        (binding) => binding.id == comparison.bindingId,
      );
      if (bindings.length != 1) {
        throw const FormatException('Comparison binding is unavailable');
      }
      final binding = bindings.single;
      final baseline = _resolveComparisonInput(
        input: binding.baseline,
        content: content,
        required: required,
        byteBudget: byteBudget,
        role: ScenarioQualityReviewArtifactRole.comparisonBaseline,
        comparisonDigest: comparison.digest,
      );
      final candidate = _resolveComparisonInput(
        input: binding.candidate,
        content: content,
        required: required,
        byteBudget: byteBudget,
        role: ScenarioQualityReviewArtifactRole.comparisonCandidate,
        comparisonDigest: comparison.digest,
      );
      if (baseline.descriptor.artifactDigest != comparison.baselineDigest ||
          candidate.descriptor.artifactDigest != comparison.candidateDigest) {
        throw const FormatException('Comparison review identity mismatch');
      }
      artifacts.addAll(<_ResolvedReviewArtifact>[baseline, candidate]);
    }
    final outputBytes = artifacts.fold<int>(
      0,
      (total, artifact) =>
          total + artifact.bytes.length + artifact.provenanceBytes.length,
    );
    if (outputBytes + byteBudget.evidenceDocumentBytes >
        maxReviewAggregateBytes) {
      throw const _ReviewQuotaExceeded();
    }
    return List<_ResolvedReviewArtifact>.unmodifiable(artifacts);
  }

  _CollectedReviewArtifact _resolveCollected(
    ScenarioLabRunSnapshot snapshot,
    RequiredEvidenceRunResult result,
    _ReviewByteBudget byteBudget,
  ) {
    if (result.state != RequiredEvidenceResultState.collected ||
        result.evidenceDigest == null ||
        snapshot.runtimeInputs == null) {
      throw const FormatException('Required Evidence is not reviewable');
    }
    if (result.artifacts.length != 1 ||
        result.providerId.value != 'capture.app-adapter') {
      throw const _ReviewUnsupported();
    }
    final evidenceDocument = evidenceRepository.readEvidenceDocument(
      result.evidenceDigest!,
      reserveEncodedBytes: byteBudget.consumeEvidenceDocument,
    );
    final evidence = evidenceDocument?.evidence;
    if (evidence == null ||
        evidence.digest != result.evidenceDigest ||
        evidence.artifacts.length != 1 ||
        evidence.subjectDigest != snapshot.catalogDigest ||
        evidence.fingerprint.digest !=
            snapshot.runtimeInputs!.executionFingerprintDigest ||
        evidence.fingerprint.targetId !=
            snapshot.runtimeInputs!.executionTargetId ||
        evidence.fingerprint.runtimeFidelity != result.fidelity) {
      throw const FormatException('Collected Evidence binding mismatch');
    }
    final resultArtifact = result.artifacts.single;
    final artifact = evidence.artifacts.single;
    if (artifact.digest != resultArtifact.artifactDigest ||
        artifact.classification != resultArtifact.classification ||
        artifact.size < 1) {
      throw const FormatException('Collected Evidence artifact mismatch');
    }
    if (artifact.mediaType != 'image/png') {
      throw const _ReviewUnsupported();
    }
    final bytes = _readReviewBlob(
      artifact.digest,
      byteBudget: byteBudget,
      expectedSize: artifact.size,
      maxIndividualBytes: 32 * 1024 * 1024,
    );
    final provenanceBytes = _readReviewBlob(
      resultArtifact.provenanceDigest,
      byteBudget: byteBudget,
      maxIndividualBytes: _maxReviewProvenanceBytes,
    );
    if (bytes == null ||
        provenanceBytes == null ||
        bytes.length != artifact.size ||
        Digest.bytes(bytes) != artifact.digest ||
        Digest.bytes(provenanceBytes) != resultArtifact.provenanceDigest) {
      throw const FormatException('Collected Evidence CAS mismatch');
    }
    final receipt = AppAdapterCaptureReceipt.fromJson(
      jsonDecode(utf8.decode(provenanceBytes, allowMalformed: false)),
      expectedDigest: resultArtifact.provenanceDigest,
    );
    final inspection = pngInspector.inspect(bytes);
    if (!_sameBytes(provenanceBytes, receipt.canonicalBytes) ||
        receipt.sessionId != snapshot.runId.value ||
        receipt.artifactDigest != artifact.digest ||
        receipt.size != artifact.size ||
        receipt.pixelDigest != artifact.pixelDigest ||
        receipt.width != artifact.width ||
        receipt.height != artifact.height ||
        receipt.completedAt != evidence.observedAt ||
        inspection.pixelDigest != artifact.pixelDigest ||
        inspection.width != artifact.width ||
        inspection.height != artifact.height) {
      throw const FormatException('Capture review provenance mismatch');
    }
    return _CollectedReviewArtifact(
      requiredEvidenceId: result.requiredEvidenceId,
      resultDigest: result.digest,
      artifactDigest: artifact.digest,
      provenanceDigest: resultArtifact.provenanceDigest,
      classification: artifact.classification,
      mediaType: artifact.mediaType,
      size: artifact.size,
      provenanceKind:
          ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
      bytes: bytes,
      provenanceBytes: provenanceBytes,
    );
  }

  _ResolvedReviewArtifact _resolveComparisonInput({
    required ComparisonInputReference input,
    required HostScenarioLabContent content,
    required Map<RequiredEvidenceId, _CollectedReviewArtifact> required,
    required _ReviewByteBudget byteBudget,
    required ScenarioQualityReviewArtifactRole role,
    required Digest comparisonDigest,
  }) => switch (input) {
    RequiredEvidenceComparisonInputReference(:final requiredEvidenceId) =>
      (required[requiredEvidenceId] ??
              (throw const FormatException('Required Evidence is absent')))
          .withRole(role, comparisonDigest: comparisonDigest),
    ArtifactComparisonInputReference(:final artifactId) => _resolveSupplemental(
      content,
      required,
      byteBudget,
      artifactId,
      role,
      comparisonDigest,
    ),
    EvidenceComparisonInputReference() => throw const _ReviewUnsupported(),
  };

  _ResolvedReviewArtifact _resolveSupplemental(
    HostScenarioLabContent content,
    Map<RequiredEvidenceId, _CollectedReviewArtifact> required,
    _ReviewByteBudget byteBudget,
    SupplementalArtifactId id,
    ScenarioQualityReviewArtifactRole role,
    Digest comparisonDigest,
  ) {
    final references = content.manifest.supplementalArtifacts.where(
      (artifact) => artifact.id == id,
    );
    if (references.length != 1) {
      throw const FormatException('Supplemental artifact is unavailable');
    }
    final reference = references.single;
    final provenanceBytes = _readReviewBlob(
      reference.provenanceDigest,
      byteBudget: byteBudget,
      maxIndividualBytes: _maxReviewProvenanceBytes,
    );
    if (provenanceBytes == null) {
      throw const FormatException('Supplemental artifact CAS is incomplete');
    }
    final provenance = ScenarioLabSupplementalArtifactProvenance.fromJson(
      jsonDecode(utf8.decode(provenanceBytes, allowMalformed: false)),
      expectedDigest: reference.provenanceDigest,
    );
    if (!_sameBytes(provenanceBytes, provenance.canonicalBytes) ||
        provenance.artifactDigest != reference.artifactDigest ||
        provenance.classification != reference.classification) {
      throw const FormatException('Supplemental provenance mismatch');
    }
    final bytes = _readReviewBlob(
      reference.artifactDigest,
      byteBudget: byteBudget,
      expectedSize: provenance.size,
      maxIndividualBytes: 32 * 1024 * 1024,
    );
    if (bytes == null || Digest.bytes(bytes) != reference.artifactDigest) {
      throw const FormatException('Supplemental artifact CAS is incomplete');
    }
    if (provenance.mediaType.value == 'image/png') {
      pngInspector.inspect(bytes);
    } else {
      throw const _ReviewUnsupported();
    }
    return _ResolvedReviewArtifact(
      descriptor: ScenarioQualityReviewArtifactDescriptor(
        requiredEvidenceId: reference.requiredEvidenceId,
        requiredEvidenceResultDigest:
            required[reference.requiredEvidenceId]?.resultDigest ??
            (throw const FormatException(
              'Supplemental artifact has no Required Evidence result',
            )),
        role: role,
        artifactDigest: reference.artifactDigest,
        provenanceDigest: reference.provenanceDigest,
        provenanceKind:
            ScenarioQualityReviewProvenanceKind.supplementalArtifactImport,
        classification: reference.classification,
        mediaType: provenance.mediaType.value,
        size: provenance.size,
        comparisonResultDigest: comparisonDigest,
      ),
      bytes: bytes,
      provenanceBytes: provenanceBytes,
    );
  }

  List<int>? _readReviewBlob(
    Digest digest, {
    required _ReviewByteBudget byteBudget,
    required int maxIndividualBytes,
    int? expectedSize,
  }) {
    final size = workspaceStore.blobSize(digest);
    if (size == null) return null;
    if (expectedSize != null && size != expectedSize) {
      throw const FormatException('Review CAS size mismatch');
    }
    if (size > maxIndividualBytes || size > byteBudget.remainingBytes) {
      throw const _ReviewQuotaExceeded();
    }
    final bytes = workspaceStore.readBlobBounded(
      digest,
      maxBytes: size,
      expectedSize: size,
    );
    if (bytes != null) byteBudget.consume(bytes.length);
    return bytes;
  }

  ScenarioQualityReviewOpenResult _previewOpenResult({
    required ScenarioQualityReviewDescriptor descriptor,
    required List<_ResolvedReviewArtifact> artifacts,
    required Uri hostOrigin,
  }) {
    final uri = hostOrigin.replace(
      path: '/resources/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    );
    final longestUtc = DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999);
    return ScenarioQualityReviewOpenResult(
      reviewDescriptor: descriptor,
      resources: artifacts.map(
        (artifact) => ScenarioQualityReviewResourceBinding(
          artifactDescriptorDigest: artifact.descriptor.digest,
          artifact: ResourceHandle(
            uri: uri,
            digest: artifact.descriptor.artifactDigest,
            mediaType: artifact.descriptor.mediaType,
            size: artifact.bytes.length,
            purpose: 'scenario-quality-review-artifact',
            expiresAt: longestUtc,
          ),
          provenance: ResourceHandle(
            uri: uri,
            digest: artifact.descriptor.provenanceDigest,
            mediaType: 'application/json',
            size: artifact.provenanceBytes.length,
            purpose: 'scenario-quality-review-provenance',
            expiresAt: longestUtc,
          ),
        ),
      ),
    );
  }

  _ResolvedReview _requireAvailableReview(
    _ExactQuality exact,
    ScenarioQualityDecisionOperation operation, {
    ScenarioQualityDecisionRequestId? requestId,
  }) {
    final review = _review(exact);
    if (review.availability != ScenarioQualityReviewAvailability.available) {
      _reject(
        operation: operation,
        code:
            review.failureCode ??
            switch (review.availability) {
              ScenarioQualityReviewAvailability.policyDenied =>
                ScenarioQualityDecisionErrorCode.policyDenied,
              ScenarioQualityReviewAvailability.unsupported =>
                ScenarioQualityDecisionErrorCode.unsupported,
              _ => ScenarioQualityDecisionErrorCode.unavailable,
            },
        exact: exact,
        requestId: requestId,
      );
    }
    return review;
  }

  Never _rejectStore({
    required ScenarioQualityDecisionOperation operation,
    required ScenarioQualityDecisionRequestId requestId,
    required _ExactQuality exact,
    required ScenarioQualityDecisionStoreFailure failure,
  }) => _reject(
    operation: operation,
    code: failure.code,
    exact: exact,
    requestId: requestId,
    currentQualityDigest: failure.currentQualityDigest,
    currentDecisionDigest: failure.currentDecisionDigest,
  );

  Never _reject({
    required ScenarioQualityDecisionOperation operation,
    required ScenarioQualityDecisionErrorCode code,
    required _ExactQuality exact,
    ScenarioQualityDecisionRequestId? requestId,
    Digest? currentQualityDigest,
    Digest? currentDecisionDigest,
  }) {
    throw HostScenarioQualityDecisionRejected(
      ScenarioQualityDecisionError(
        operation: operation,
        code: code,
        runId: exact.result.finalSnapshot.runId,
        expectedRunResultDigest: exact.result.digest,
        requestId: requestId,
        currentQualityDigest:
            currentQualityDigest ?? exact.history.quality.digest,
        currentDecisionDigest:
            currentDecisionDigest ?? exact.history.head?.digest,
      ),
    );
  }

  Never _rejectWithoutExact({
    required ScenarioQualityDecisionOperation operation,
    required ScenarioQualityDecisionErrorCode code,
    required ScenarioLabRunId runId,
    required Digest resultDigest,
    ScenarioQualityDecisionRequestId? requestId,
    Digest? currentQualityDigest,
    Digest? currentDecisionDigest,
  }) {
    throw HostScenarioQualityDecisionRejected(
      ScenarioQualityDecisionError(
        operation: operation,
        code: code,
        runId: runId,
        expectedRunResultDigest: resultDigest,
        requestId: requestId,
        currentQualityDigest: currentQualityDigest,
        currentDecisionDigest: currentDecisionDigest,
      ),
    );
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Scenario Quality service is closed');
  }

  String _nextId(String prefix) =>
      '$prefix-${Digest.semantic(ids.nextId()).value.substring(7, 39)}';
}

ScenarioQualitySnapshot _baseQuality(ScenarioLabRunResult result) =>
    ScenarioQualitySnapshot(
      subjectDigest: result.digest,
      runId: result.finalSnapshot.runId,
      scenarioId: result.finalSnapshot.scenarioId,
      verificationState: result.verificationState,
      humanDecision: HumanDecisionProjection(
        state: HumanDecisionState.unreviewed,
      ),
      requiredEvidence: result.finalSnapshot.requiredEvidence.map(
        (item) => RequiredEvidenceVerification(
          requiredEvidenceId: item.requiredEvidenceId,
          resultDigest: item.digest,
          verificationState: switch (item.state) {
            RequiredEvidenceResultState.collected => VerificationState.passed,
            RequiredEvidenceResultState.missing ||
            RequiredEvidenceResultState.failed => VerificationState.failed,
            RequiredEvidenceResultState.unsupported ||
            RequiredEvidenceResultState.policyDenied => VerificationState.error,
            RequiredEvidenceResultState.pending ||
            RequiredEvidenceResultState.cancelled => VerificationState.notRun,
          },
        ),
      ),
      comparisonResultDigests: result.finalSnapshot.comparisons.map(
        (item) => item.digest,
      ),
    );

final class _ExactQuality {
  const _ExactQuality({
    required this.result,
    required this.baseQuality,
    required this.history,
  });

  final ScenarioLabRunResult result;
  final ScenarioQualitySnapshot baseQuality;
  final ScenarioQualityDecisionHistory history;
}

final class _ResolvedReview {
  const _ResolvedReview._({
    required this.availability,
    this.requirement,
    this.descriptor,
    this.artifacts = const <_ResolvedReviewArtifact>[],
    this.failureCode,
  });

  factory _ResolvedReview.available({
    required HumanApprovalRequirement requirement,
    required ScenarioQualityReviewDescriptor descriptor,
    required List<_ResolvedReviewArtifact> artifacts,
  }) => _ResolvedReview._(
    availability: ScenarioQualityReviewAvailability.available,
    requirement: requirement,
    descriptor: descriptor,
    artifacts: artifacts,
  );

  factory _ResolvedReview.unavailable([
    HumanApprovalRequirement? requirement,
  ]) => _ResolvedReview._(
    availability: ScenarioQualityReviewAvailability.unavailable,
    requirement: requirement,
  );

  factory _ResolvedReview.unsupported(HumanApprovalRequirement requirement) =>
      _ResolvedReview._(
        availability: ScenarioQualityReviewAvailability.unsupported,
        requirement: requirement,
      );

  factory _ResolvedReview.policyDenied(HumanApprovalRequirement requirement) =>
      _ResolvedReview._(
        availability: ScenarioQualityReviewAvailability.policyDenied,
        requirement: requirement,
      );

  factory _ResolvedReview.quotaExceeded(HumanApprovalRequirement requirement) =>
      _ResolvedReview._(
        availability: ScenarioQualityReviewAvailability.unavailable,
        requirement: requirement,
        failureCode: ScenarioQualityDecisionErrorCode.quotaExceeded,
      );

  final ScenarioQualityReviewAvailability availability;
  final HumanApprovalRequirement? requirement;
  final ScenarioQualityReviewDescriptor? descriptor;
  final List<_ResolvedReviewArtifact> artifacts;
  final ScenarioQualityDecisionErrorCode? failureCode;

  ScenarioQualityReviewDescriptor get availableDescriptor =>
      descriptor ?? (throw StateError('Review descriptor is unavailable'));

  HumanApprovalRequirement get availableRequirement =>
      requirement ?? (throw StateError('Review requirement is unavailable'));
}

final class _CollectedReviewArtifact {
  const _CollectedReviewArtifact({
    required this.requiredEvidenceId,
    required this.resultDigest,
    required this.artifactDigest,
    required this.provenanceDigest,
    required this.provenanceKind,
    required this.classification,
    required this.mediaType,
    required this.size,
    required this.bytes,
    required this.provenanceBytes,
  });

  final RequiredEvidenceId requiredEvidenceId;
  final Digest resultDigest;
  final Digest artifactDigest;
  final Digest provenanceDigest;
  final ScenarioQualityReviewProvenanceKind provenanceKind;
  final ArtifactClassification classification;
  final String mediaType;
  final int size;
  final List<int> bytes;
  final List<int> provenanceBytes;

  _ResolvedReviewArtifact withRole(
    ScenarioQualityReviewArtifactRole role, {
    Digest? comparisonDigest,
  }) => _ResolvedReviewArtifact(
    descriptor: ScenarioQualityReviewArtifactDescriptor(
      requiredEvidenceId: requiredEvidenceId,
      requiredEvidenceResultDigest: resultDigest,
      role: role,
      artifactDigest: artifactDigest,
      provenanceDigest: provenanceDigest,
      provenanceKind: provenanceKind,
      classification: classification,
      mediaType: mediaType,
      size: size,
      comparisonResultDigest: comparisonDigest,
    ),
    bytes: bytes,
    provenanceBytes: provenanceBytes,
  );
}

final class _ResolvedReviewArtifact {
  const _ResolvedReviewArtifact({
    required this.descriptor,
    required this.bytes,
    required this.provenanceBytes,
  });

  final ScenarioQualityReviewArtifactDescriptor descriptor;
  final List<int> bytes;
  final List<int> provenanceBytes;
}

final class _ReviewLease {
  const _ReviewLease({
    required this.resources,
    required this.handles,
    required this.descriptorDigest,
  });

  final HostResourceRegistry resources;
  final List<ResourceHandle> handles;
  final Digest descriptorDigest;
}

final class _ReviewUnsupported implements Exception {
  const _ReviewUnsupported();
}

final class _ReviewQuotaExceeded implements Exception {
  const _ReviewQuotaExceeded();
}

final class _ReviewByteBudget {
  _ReviewByteBudget(this.remainingBytes);

  int remainingBytes;
  int evidenceDocumentBytes = 0;

  void consume(int bytes) {
    if (bytes < 0 || bytes > remainingBytes) {
      throw const _ReviewQuotaExceeded();
    }
    remainingBytes -= bytes;
  }

  void consumeEvidenceDocument(int bytes) {
    consume(bytes);
    evidenceDocumentBytes += bytes;
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
