import 'dart:convert';
import 'dart:math';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import 'experience_authoring_store.dart';
import 'filesystem_experience_authoring_store.dart';
import 'projection_layout_safety_evaluator.dart';

typedef ExperienceAuthoringClock = DateTime Function();
typedef ExperienceAuthoringDiagnosticSink =
    void Function(Object error, StackTrace stackTrace);

/// Host-derived authority configuration. An empty settings object is a valid
/// query-only policy. A configured authority is all-or-none and never inferred
/// from a presentation role.
final class ExperienceAuthoringAuthoritySettings {
  ExperienceAuthoringAuthoritySettings._({
    required this.authorityId,
    required this.policyId,
    required this.principalId,
    required Set<AuthoringOperation> allowedOperations,
    required this.grantTtl,
  }) : allowedOperations = Set<AuthoringOperation>.unmodifiable(
         allowedOperations,
       );

  factory ExperienceAuthoringAuthoritySettings.fromJson(
    Map<String, Object?> settings,
  ) {
    const keys = <String>{
      'authorityId',
      'accessPolicyId',
      'principalId',
      'allowedOperations',
      'grantTtlSeconds',
    };
    if (settings.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unknown authoring.local setting');
    }
    if (settings.isEmpty) {
      return ExperienceAuthoringAuthoritySettings._(
        authorityId: null,
        policyId: null,
        principalId: null,
        allowedOperations: const <AuthoringOperation>{},
        grantTtl: Duration.zero,
      );
    }
    if (!settings.keys.toSet().containsAll(keys) || settings.length != 5) {
      throw const FormatException(
        'authoring.local authority settings must be complete',
      );
    }
    final authority = settings['authorityId'];
    final policy = settings['accessPolicyId'];
    final principal = settings['principalId'];
    final rawOperations = settings['allowedOperations'];
    final ttl = settings['grantTtlSeconds'];
    if (authority is! String ||
        policy is! String ||
        principal is! String ||
        rawOperations is! List<Object?> ||
        ttl is! int ||
        ttl < 1 ||
        ttl > 300) {
      throw const FormatException('Invalid authoring.local authority setting');
    }
    final operations = <AuthoringOperation>{};
    for (final raw in rawOperations) {
      if (raw is! String) {
        throw const FormatException('Authoring operation must be a string');
      }
      final matches = AuthoringOperation.values
          .where((operation) => operation.name == raw)
          .toList(growable: false);
      if (matches.length != 1 ||
          authoringEffectFor(matches.single) == AuthoringActionEffect.query) {
        throw FormatException('Unsupported granted authoring operation: $raw');
      }
      if (!operations.add(matches.single)) {
        throw FormatException('Duplicate authoring operation: $raw');
      }
    }
    if (operations.isEmpty) {
      throw const FormatException(
        'Configured authoring authority requires a non-query operation',
      );
    }
    return ExperienceAuthoringAuthoritySettings._(
      authorityId: AuthoringAuthorityId(authority),
      policyId: AuthoringPolicyId(policy),
      principalId: AuthoringPrincipalId(principal),
      allowedOperations: operations,
      grantTtl: Duration(seconds: ttl),
    );
  }

  final AuthoringAuthorityId? authorityId;
  final AuthoringPolicyId? policyId;
  final AuthoringPrincipalId? principalId;
  final Set<AuthoringOperation> allowedOperations;
  final Duration grantTtl;

  bool get hasAuthority =>
      authorityId != null && policyId != null && principalId != null;
}

/// Live module state used to derive a stable capability descriptor. The
/// generated-at manifest digest is deliberately not part of the capability.
final class ExperienceAuthoringModuleSupport {
  const ExperienceAuthoringModuleSupport({
    required this.resolvedPlanDigest,
    required this.active,
    required this.healthy,
  });

  final Digest resolvedPlanDigest;
  final bool active;
  final bool healthy;

  AuthoringCapability? capabilityFor(AuthoringSubjectRef subject) {
    if (!active || !healthy) return null;
    return AuthoringCapability(
      capability: ModuleCapabilityRef(id: 'experience.authoring', version: 1),
      moduleId: ModuleId('authoring.local'),
      resolvedPlanDigest: resolvedPlanDigest,
      subject: subject,
      effects: AuthoringActionEffect.values.toSet(),
      operations: AuthoringOperation.values.toSet(),
    );
  }
}

/// Exact, already bounded Host snapshot for one authoring subject.
///
/// Filesystem discovery and content-root routing live behind the resolver, so
/// no client request can select a path, URI, parser, or publication target.
final class ExperienceAuthoringWorkspaceSnapshot {
  ExperienceAuthoringWorkspaceSnapshot({
    required this.subject,
    required this.catalog,
    required this.topology,
    required this.layout,
    required this.contentSetDigest,
    required this.sourceDigest,
    this.scenarioLabManifest,
  }) {
    final projections = topology.projections
        .where((projection) => projection.id == subject.projectionId)
        .toList(growable: false);
    if (catalog.workspace.id != subject.workspaceId ||
        topology.catalogDigest != catalog.digest ||
        layout.topologyDigest != topology.digest ||
        layout.projectionId != subject.projectionId ||
        projections.length != 1 ||
        projections.single.applicationId != subject.applicationId ||
        scenarioLabManifest != null &&
            scenarioLabManifest!.catalogDigest != catalog.digest) {
      throw ArgumentError('Authoring workspace snapshot has stale authority');
    }
  }

  final AuthoringSubjectRef subject;
  final CatalogManifest catalog;
  final ExperienceTopologyManifest topology;
  final ProjectionLayoutManifest layout;
  final Digest contentSetDigest;
  final Digest? sourceDigest;
  final ScenarioLabManifest? scenarioLabManifest;

  ExecutableReviewGuideBinding reviewBinding({
    required ReviewGuideId guideId,
    required String stepId,
  }) {
    final guides = catalog.reviewGuides
        .where(
          (guide) =>
              guide.id == guideId &&
              guide.applicationId == subject.applicationId,
        )
        .toList(growable: false);
    if (guides.length != 1) {
      throw StateError('ReviewGuide is outside the authoring application');
    }
    final steps = guides.single.steps
        .where((step) => step.id == stepId)
        .toList(growable: false);
    if (steps.length != 1) {
      throw StateError('ReviewGuide step is unavailable');
    }
    final step = steps.single;
    final bindings = catalog.executionBindings
        .where(
          (binding) =>
              binding.id == step.bindingId &&
              binding.scenarioId == step.scenarioId,
        )
        .toList(growable: false);
    if (bindings.length != 1) {
      throw StateError('ReviewGuide binding is unavailable');
    }
    return ExecutableReviewGuideBinding(
      catalogDigest: catalog.digest,
      applicationId: subject.applicationId,
      reviewGuideId: guideId,
      stepId: stepId,
      scenarioId: step.scenarioId,
      bindingId: step.bindingId,
    );
  }

  Set<Digest> allowedArtifactDigests(ExecutableReviewGuideBinding binding) {
    if (binding.catalogDigest != catalog.digest ||
        binding.applicationId != subject.applicationId) {
      throw StateError('ReviewGuide binding is outside this snapshot');
    }
    final manifest = scenarioLabManifest;
    if (manifest == null) return const <Digest>{};
    final plans = manifest.plans
        .where(
          (plan) =>
              plan.scenarioId == binding.scenarioId &&
              plan.executionBindingIds.contains(binding.bindingId),
        )
        .toList(growable: false);
    if (plans.length != 1) {
      throw StateError('Scenario Lab plan is unavailable for ReviewGuide');
    }
    final ids = plans.single.supplementalArtifactIds.toSet();
    final artifacts = manifest.supplementalArtifacts
        .where(
          (artifact) =>
              ids.contains(artifact.id) &&
              artifact.scenarioId == binding.scenarioId,
        )
        .toList(growable: false);
    if (artifacts.length != ids.length) {
      throw StateError('Scenario Lab artifact authority is incomplete');
    }
    return Set<Digest>.unmodifiable(
      artifacts.map((artifact) => artifact.artifactDigest),
    );
  }
}

abstract interface class ExperienceAuthoringWorkspaceResolver {
  ExperienceAuthoringWorkspaceSnapshot resolve(AuthoringSubjectRef subject);
}

/// Host-owned promotion seam. Implementations bind a configured content root,
/// source loader, content authority, and atomic publisher. No request field can
/// select any of those routing decisions.
abstract interface class ExperienceAuthoringPromotionExecutor {
  ExperiencePromotionReceipt promote({
    required ExperiencePromotionApplyRequest request,
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket reviewPacket,
    required Set<Digest> allowedArtifactDigests,
    required DateTime promotedAt,
    required StoredAuthoringAttempt Function(ExperiencePromotionReceipt receipt)
    successAttemptFactory,
    required StoredAuthoringAttempt rollbackAttempt,
  });
}

abstract interface class ExperienceAuthoringIdFactory {
  String issue(String kind, Digest requestDigest);
}

final class SecureExperienceAuthoringIdFactory
    implements ExperienceAuthoringIdFactory {
  SecureExperienceAuthoringIdFactory() : _random = Random.secure();

  final Random _random;

  @override
  String issue(String kind, Digest requestDigest) {
    final nonce = List<int>.generate(32, (_) => _random.nextInt(256));
    final digest = Digest.semantic(<String, Object?>{
      'kind': kind,
      'requestDigest': requestDigest.value,
      'nonceDigest': Digest.bytes(nonce).value,
    }).value.substring('sha256:'.length);
    return '$kind-${digest.substring(0, 32)}';
  }
}

final class ExperienceAuthoringServiceException implements Exception {
  const ExperienceAuthoringServiceException(this.error);

  final ExperienceAuthoringError error;
}

/// Host-private outcome used to publish the content-set event only for the
/// call that durably created a successful promotion terminal. Exact RPC replay
/// returns the same public result with [durableCommitCreated] false.
final class ExperienceAuthoringPromotionApplyOutcome {
  const ExperienceAuthoringPromotionApplyOutcome({
    required this.result,
    required this.durableCommitCreated,
  });

  final ExperiencePromotionApplyResult result;
  final bool durableCommitCreated;
}

/// Restart-safe authority service for the closed Experience Authoring surface.
/// All effect handlers are synchronous so one store lock can fence the current
/// snapshot, grant, journal transition, and terminal replay record.
final class ExperienceAuthoringService {
  ExperienceAuthoringService({
    required this.store,
    required this.workspaceResolver,
    required this.moduleSupport,
    required this.settings,
    ExperienceAuthoringClock? clock,
    ExperienceAuthoringIdFactory? idFactory,
    this.draftEngine = const LayoutDraftEngine(),
    this.reviewCompiler = const ExperienceReviewPacketCompiler(),
    this.grantVerifier = const AuthoringGrantVerifier(),
    this.acceptance = const HostProjectionLayoutSafetyAcceptance(),
    this.promotionExecutor,
    this.diagnosticSink,
    bool revokeActiveGrantsOnStart = true,
  }) : clock = clock ?? _utcNow,
       idFactory = idFactory ?? SecureExperienceAuthoringIdFactory() {
    if (revokeActiveGrantsOnStart) {
      store.revokeAllActive(
        reason: 'service-restart',
        at: this.clock().toUtc(),
      );
    }
  }

  final FilesystemExperienceAuthoringStore store;
  final ExperienceAuthoringWorkspaceResolver workspaceResolver;
  final ExperienceAuthoringModuleSupport moduleSupport;
  final ExperienceAuthoringAuthoritySettings settings;
  final ExperienceAuthoringClock clock;
  final ExperienceAuthoringIdFactory idFactory;
  final LayoutDraftEngine draftEngine;
  final ExperienceReviewPacketCompiler reviewCompiler;
  final AuthoringGrantVerifier grantVerifier;
  final HostProjectionLayoutSafetyAcceptance acceptance;
  final ExperienceAuthoringPromotionExecutor? promotionExecutor;
  final ExperienceAuthoringDiagnosticSink? diagnosticSink;

  static final Set<AuthoringOperation> _queryOperations =
      Set<AuthoringOperation>.unmodifiable(
        AuthoringOperation.values.where(
          (operation) =>
              authoringEffectFor(operation) == AuthoringActionEffect.query,
        ),
      );

  Set<AuthoringOperation> _effectiveQueryOperations(
    AuthoringCapability capability,
  ) => Set<AuthoringOperation>.unmodifiable(
    _queryOperations.where(
      (operation) =>
          capability.operations.contains(operation) &&
          (operation != AuthoringOperation.getDraft ||
              settings.principalId != null),
    ),
  );

  ExperienceAuthoringDescription describe(
    ExperienceAuthoringDescribeRequest request,
  ) {
    final snapshot = _resolveSnapshot(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.describe,
    );
    final capability = moduleSupport.capabilityFor(request.subject);
    final supported =
        capability != null &&
        snapshot.sourceDigest != null &&
        store.isDurabilityAvailable;
    final queryOperations = capability == null
        ? const <AuthoringOperation>{}
        : _effectiveQueryOperations(capability);
    final allowed = !supported
        ? const <AuthoringOperation>{}
        : !settings.hasAuthority
        ? queryOperations
        : <AuthoringOperation>{
            ...queryOperations,
            ...settings.allowedOperations.where(capability.operations.contains),
          };
    final availability = !supported
        ? ExperienceAuthoringAvailability.unsupported
        : settings.hasAuthority &&
              allowed.any(
                (operation) =>
                    authoringEffectFor(operation) !=
                    AuthoringActionEffect.query,
              )
        ? ExperienceAuthoringAvailability.available
        : ExperienceAuthoringAvailability.policyDenied;
    final result = ExperienceAuthoringDescription(
      requestId: request.requestId,
      subject: request.subject,
      availability: availability,
      capability: supported ? capability : null,
      allowedEffects: allowed.map(authoringEffectFor).toSet(),
      allowedOperations: allowed,
      currentContentSetDigest: snapshot.contentSetDigest,
      currentSourceDigest: supported ? snapshot.sourceDigest : null,
      currentTopologyDigest: snapshot.topology.digest,
      currentLayoutDigest: snapshot.layout.digest,
    );
    result.validateAgainst(request);
    _requireDocument(result.toJson(includeDigest: false));
    _requireFrame(result.toJson(), result.digest);
    return result;
  }

  ExperienceAuthoringSubjectHeadResult getSubjectHead(
    ExperienceAuthoringSubjectHeadRequest request,
  ) {
    _requireQueryable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.getSubjectHead,
    );
    final result = ExperienceAuthoringSubjectHeadResult(
      requestId: request.requestId,
      head: store.subjectHead(request.subject),
    );
    result.validateAgainst(request);
    _requireDocument(result.toJson(includeDigest: false));
    _requireFrame(result.toJson(), result.digest);
    return result;
  }

  LayoutDraftGetResult getDraft(LayoutDraftGetRequest request) {
    _requireQueryable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.getDraft,
    );
    final stored = store.findDraftById(request.draftId);
    if (stored == null || stored.draft.subject != request.subject) {
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: request.requestId,
        subject: request.subject,
        operation: AuthoringOperation.getDraft,
        draftId: request.draftId,
      );
    }
    if (settings.principalId == null ||
        stored.ownerPrincipalId != settings.principalId) {
      _throwError(
        code: ExperienceAuthoringErrorCode.ownerDenied,
        requestId: request.requestId,
        subject: request.subject,
        operation: AuthoringOperation.getDraft,
        draftId: request.draftId,
        currentDraftDigest: stored.draft.digest,
      );
    }
    if (request.expectedDraftDigest != null &&
        request.expectedDraftDigest != stored.draft.digest) {
      _throwStale(
        requestId: request.requestId,
        subject: request.subject,
        operation: AuthoringOperation.getDraft,
        expectedDigest: request.expectedDraftDigest!,
        currentDraftDigest: stored.draft.digest,
        draftId: request.draftId,
      );
    }
    final result = LayoutDraftGetResult(
      requestId: request.requestId,
      draft: stored.draft,
      head: store.subjectHead(request.subject),
    );
    result.validateAgainst(request);
    _requireDocument(result.toJson(includeDigest: false));
    _requireFrame(result.toJson(), result.digest);
    return result;
  }

  ExperienceChangeSetGetResult getChangeSet(
    ExperienceChangeSetGetRequest request,
  ) {
    _requireQueryable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.getChangeSet,
    );
    final changeSet = store.findChangeSet(
      subject: request.subject,
      id: request.changeSetId,
      expectedDigest: request.expectedChangeSetDigest,
    );
    if (changeSet == null) {
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: request.requestId,
        subject: request.subject,
        operation: AuthoringOperation.getChangeSet,
        changeSetId: request.changeSetId,
      );
    }
    final result = ExperienceChangeSetGetResult(
      requestId: request.requestId,
      changeSet: changeSet,
    );
    result.validateAgainst(request);
    _requireDocument(result.toJson(includeDigest: false));
    _requireFrame(result.toJson(), result.digest);
    return result;
  }

  ExperienceReviewGetResult getReview(ExperienceReviewGetRequest request) {
    _requireQueryable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.getReview,
    );
    final packet = store.findReviewPacket(
      subject: request.subject,
      id: request.reviewPacketId,
      expectedDigest: request.expectedReviewPacketDigest,
    );
    if (packet == null) {
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: request.requestId,
        subject: request.subject,
        operation: AuthoringOperation.getReview,
        reviewPacketId: request.reviewPacketId,
      );
    }
    final result = ExperienceReviewGetResult(
      requestId: request.requestId,
      reviewPacket: packet,
    );
    result.validateAgainst(request);
    _requireDocument(result.toJson(includeDigest: false));
    _requireFrame(result.toJson(), result.digest);
    return result;
  }

  ExperiencePromotionGetResult getPromotion(
    ExperiencePromotionGetRequest request,
  ) {
    _requireQueryable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.getPromotion,
    );
    final receipt = store.findPromotionReceipt(
      subject: request.subject,
      id: request.receiptId,
      expectedDigest: request.expectedReceiptDigest,
    );
    if (receipt == null) {
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: request.requestId,
        subject: request.subject,
        operation: AuthoringOperation.getPromotion,
      );
    }
    final result = ExperiencePromotionGetResult(
      requestId: request.requestId,
      receipt: receipt,
    );
    result.validateAgainst(request);
    _requireDocument(result.toJson(includeDigest: false));
    _requireFrame(result.toJson(), result.digest);
    return result;
  }

  ExperiencePromotionHistoryResult getPromotionHistory(
    ExperiencePromotionHistoryRequest request,
  ) {
    _requireQueryable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.getPromotionHistory,
    );
    final page = store.promotionHistoryPage(
      request.subject,
      offset: request.offset,
      limit: request.limit,
    );
    final result = ExperiencePromotionHistoryResult(
      requestId: request.requestId,
      subject: request.subject,
      offset: page.offset,
      limit: page.limit,
      totalCount: page.totalCount,
      previousPageReceiptDigest: page.previousPageReceiptDigest,
      receipts: page.receipts,
    );
    result.validateAgainst(request);
    _requireDocument(result.toJson(includeDigest: false));
    _requireFrame(result.toJson(), result.digest);
    return result;
  }

  AuthoringGrantResult requestGrant(
    AuthoringGrantRequest request, {
    required String connectionEpoch,
  }) => _issueGrant(request, connectionEpoch: connectionEpoch);

  AuthoringGrantResult requestDecisionGrant(
    ExperienceReviewDecisionGrantRequest request, {
    required String connectionEpoch,
  }) {
    final replay = _replayGrantIfPresent(request);
    if (replay != null) return replay;
    final pair = _currentReviewPairForIntent(request);
    try {
      request.validateAgainst(changeSet: pair.changeSet, packet: pair.packet);
    } on Object {
      _throwStaleReviewIntent(request);
    }
    return _issueGrant(request, connectionEpoch: connectionEpoch);
  }

  AuthoringGrantResult requestPromotionGrant(
    ExperiencePromotionGrantRequest request, {
    required String connectionEpoch,
  }) {
    final replay = _replayGrantIfPresent(request);
    if (replay != null) return replay;
    final draft = store.findDraft(request.subject)?.draft;
    if (draft == null) {
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: request.requestId,
        subject: request.subject,
        operation: AuthoringOperation.promote,
      );
    }
    final pair = _currentReviewPairForIntent(request);
    try {
      request.validateAgainst(
        draft: draft,
        changeSet: pair.changeSet,
        reviewPacket: pair.packet,
      );
    } on Object {
      _throwStaleReviewIntent(request);
    }
    return _issueGrant(request, connectionEpoch: connectionEpoch);
  }

  AuthoringGrantResult _issueGrant(
    AuthoringGrantIntent intent, {
    required String connectionEpoch,
  }) {
    final replay = _findAttemptOrUnavailable(
      requestId: intent.requestId,
      subject: intent.subject,
      operation: intent.operation,
    );
    if (replay != null) {
      return _replay<AuthoringGrantResult>(
        replay,
        family: StoredAuthoringAttemptFamily.grantIssue,
        requestDigest: intent.digest,
        payloadDigest: intent.payloadDigest,
        subject: intent.subject,
        effect: intent.effect,
        operation: intent.operation,
        grantId: null,
        grantDigest: null,
        decode: AuthoringGrantResult.fromJson,
      );
    }
    final capability = _requireAvailable(
      requestId: intent.requestId,
      subject: intent.subject,
      operation: intent.operation,
      capabilityDigest: intent.capabilityDigest,
    );
    if (intent is AuthoringGrantRequest) _validateGrantFence(intent);
    final now = clock().toUtc();
    final grant = AuthoringActionGrant(
      id: AuthoringActionGrantId(idFactory.issue('grant', intent.digest)),
      requestId: intent.requestId,
      requestDigest: intent.digest,
      payloadDigest: intent.payloadDigest,
      authorityId: settings.authorityId!,
      policyId: settings.policyId!,
      principalId: settings.principalId!,
      capabilityDigest: capability.digest,
      subject: intent.subject,
      effect: intent.effect,
      operation: intent.operation,
      expectedDigest: intent.expectedDigest,
      expectedSourceDigest: intent.expectedSourceDigest,
      issuedAt: now,
      expiresAt: now.add(settings.grantTtl),
      singleUse: true,
    );
    final result = AuthoringGrantResult(
      requestId: intent.requestId,
      grant: grant,
    );
    result.validateAgainst(intent);
    try {
      _requireDocument(result.toJson(includeDigest: false));
      _requireFrame(result.toJson(), result.digest);
    } on ExperienceAuthoringFrameLimitFailure {
      final error = ExperienceAuthoringError(
        code: ExperienceAuthoringErrorCode.quotaExceeded,
        requestId: intent.requestId,
        subject: intent.subject,
        operation: intent.operation,
      );
      _requireFrame(error.toJson(), error.digest);
      _commitAndRecover(
        ExperienceAuthoringAtomicCommit(
          attempt: _attempt(
            family: StoredAuthoringAttemptFamily.grantIssue,
            requestId: intent.requestId,
            requestDigest: intent.digest,
            payloadDigest: intent.payloadDigest,
            subject: intent.subject,
            effect: intent.effect,
            operation: intent.operation,
            grantId: null,
            grantDigest: null,
            terminal: error.toJson(),
            isError: true,
            at: now,
          ),
        ),
      );
      throw ExperienceAuthoringServiceException(error);
    }
    final stored = StoredAuthoringGrant(
      grant: grant,
      intentKind: storedAuthoringGrantIntentKind(intent).wireName,
      intentJson: storedAuthoringGrantIntentJson(intent),
      connectionEpoch: _validatedEpoch(connectionEpoch),
      state: StoredAuthoringGrantState.active,
      stateChangedAt: now,
    );
    final attempt = _attempt(
      family: StoredAuthoringAttemptFamily.grantIssue,
      requestId: intent.requestId,
      requestDigest: intent.digest,
      payloadDigest: intent.payloadDigest,
      subject: intent.subject,
      effect: intent.effect,
      operation: intent.operation,
      grantId: null,
      grantDigest: null,
      terminal: result.toJson(),
      isError: false,
      at: now,
    );
    _commitAndRecover(
      ExperienceAuthoringAtomicCommit(attempt: attempt, issuedGrant: stored),
    );
    return result;
  }

  AuthoringGrantResult? _replayGrantIfPresent(AuthoringGrantIntent intent) {
    final attempt = _findAttemptOrUnavailable(
      requestId: intent.requestId,
      subject: intent.subject,
      operation: intent.operation,
    );
    if (attempt == null) return null;
    return _replay<AuthoringGrantResult>(
      attempt,
      family: StoredAuthoringAttemptFamily.grantIssue,
      requestDigest: intent.digest,
      payloadDigest: intent.payloadDigest,
      subject: intent.subject,
      effect: intent.effect,
      operation: intent.operation,
      grantId: null,
      grantDigest: null,
      decode: AuthoringGrantResult.fromJson,
    );
  }

  LayoutDraftOpenResult openDraft(
    LayoutDraftOpenRequest request, {
    required String connectionEpoch,
  }) {
    final replay = _findAttemptOrUnavailable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.openDraft,
    );
    if (replay != null) {
      return _replayEffect<LayoutDraftOpenResult>(
        replay,
        family: StoredAuthoringAttemptFamily.draftOpen,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: request.subject,
        operation: AuthoringOperation.openDraft,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: LayoutDraftOpenResult.fromJson,
      );
    }
    try {
      return store.withTransaction((transaction) {
        final verified = _bindGrant(
          requestId: request.requestId,
          subject: request.subject,
          effect: AuthoringActionEffect.authoring,
          operation: AuthoringOperation.openDraft,
          expectedDigest: request.expectedContentSetDigest,
          expectedSourceDigest: request.expectedSourceDigest,
          payloadDigest: request.payloadDigest,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          connectionEpoch: connectionEpoch,
        );
        request.validateAgainstGrantIntent(verified.intent);
        _rejectPreviouslyTerminalGrant(
          verified: verified,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.openDraft,
        );
        if (verified.stored.state == StoredAuthoringGrantState.active &&
            !clock().toUtc().isBefore(verified.stored.grant.expiresAt)) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftOpen,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.openDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.grantExpired,
          );
        }
        final snapshot = _resolveSnapshot(
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.openDraft,
        );
        final source = snapshot.sourceDigest;
        if (source == null ||
            request.expectedContentSetDigest != snapshot.contentSetDigest ||
            request.expectedSourceDigest != source) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftOpen,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.openDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.stale,
            expectedDigest: request.expectedContentSetDigest,
            currentContentSetDigest: snapshot.contentSetDigest,
            currentSourceDigest: source,
          );
        }
        final existing = transaction.findDraft(request.subject);
        if (existing != null &&
            existing.ownerPrincipalId != settings.principalId) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftOpen,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.openDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.ownerDenied,
            draftId: existing.draft.id,
            currentDraftDigest: existing.draft.digest,
          );
        }
        if (existing != null &&
            (existing.draft.baseSourceDigest != source ||
                existing.draft.contentSetDigest != snapshot.contentSetDigest ||
                existing.draft.baseLayoutDigest != snapshot.layout.digest)) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftOpen,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.openDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.stale,
            expectedDigest: existing.draft.digest,
            currentDraftDigest: existing.draft.digest,
            currentContentSetDigest: snapshot.contentSetDigest,
            currentSourceDigest: source,
            draftId: existing.draft.id,
          );
        }
        _requireActiveGrant(
          verified: verified,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.openDraft,
        );
        final currentHead = transaction.subjectHead(request.subject);
        final LayoutDraft draft;
        final bool resumed;
        final StoredLayoutDraft? nextDraft;
        if (existing != null) {
          draft = existing.draft;
          resumed = true;
          nextDraft = null;
        } else {
          draft = draftEngine.openDraft(
            id: LayoutDraftId(idFactory.issue('draft', request.digest)),
            subject: request.subject,
            baseLayout: snapshot.layout,
            baseSourceDigest: source,
            contentSetDigest: snapshot.contentSetDigest,
          );
          final blob = transaction.retainBaseLayout(snapshot.layout);
          nextDraft = StoredLayoutDraft(
            ownerPrincipalId: settings.principalId!,
            draft: draft,
            baseLayoutBlobDigest: blob,
          );
          resumed = false;
        }
        final result = LayoutDraftOpenResult(
          requestId: request.requestId,
          draft: draft,
          resumed: resumed,
          head: resumed
              ? currentHead
              : _head(
                  draft: draft,
                  latestPromotion: currentHead.latestPromotion,
                ),
        );
        result.validateAgainst(request);
        try {
          _requireDocument(result.toJson(includeDigest: false));
          _requireFrame(result.toJson(), result.digest);
        } on ExperienceAuthoringFrameLimitFailure {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftOpen,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.openDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.quotaExceeded,
            draftId: draft.id,
          );
        }
        final attempt = _attemptForEffect(
          StoredAuthoringAttemptFamily.draftOpen,
          requestId: request.requestId,
          requestDigest: request.digest,
          payloadDigest: request.payloadDigest,
          subject: request.subject,
          operation: AuthoringOperation.openDraft,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          terminal: result.toJson(),
        );
        transaction.commitAtomic(
          ExperienceAuthoringAtomicCommit(
            attempt: attempt,
            consumedGrantId: request.grantId,
            nextDraft: nextDraft,
          ),
        );
        return result;
      });
    } on ExperienceAuthoringServiceException {
      rethrow;
    } on Object catch (error, stackTrace) {
      return _recoverEffect<LayoutDraftOpenResult>(
        requestId: request.requestId,
        family: StoredAuthoringAttemptFamily.draftOpen,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: request.subject,
        operation: AuthoringOperation.openDraft,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: LayoutDraftOpenResult.fromJson,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  LayoutDraftMutationResult mutateDraft(
    LayoutDraftMutationRequest request, {
    required String connectionEpoch,
  }) {
    final replay = _findAttemptOrUnavailable(
      requestId: request.requestId,
      subject: _subjectForGrant(request.grantId, request.requestId),
      operation: _mutationOperation(request.mutation),
    );
    if (replay != null) {
      return _replayEffect<LayoutDraftMutationResult>(
        replay,
        family: StoredAuthoringAttemptFamily.draftMutation,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: replay.subject,
        operation: _mutationOperation(request.mutation),
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: LayoutDraftMutationResult.fromJson,
      );
    }
    try {
      return store.withTransaction((transaction) {
        final operation = _mutationOperation(request.mutation);
        final stored = transaction.findDraftById(request.draftId);
        final subject =
            stored?.draft.subject ??
            _subjectForGrant(request.grantId, request.requestId);
        final verified = _bindGrant(
          requestId: request.requestId,
          subject: subject,
          effect: AuthoringActionEffect.authoring,
          operation: operation,
          expectedDigest: request.expectedDraftDigest,
          expectedSourceDigest: _expectedSourceForGrant(request.grantId),
          payloadDigest: request.payloadDigest,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          connectionEpoch: connectionEpoch,
        );
        _rejectPreviouslyTerminalGrant(
          verified: verified,
          requestId: request.requestId,
          subject: subject,
          operation: operation,
        );
        if (verified.stored.state == StoredAuthoringGrantState.active &&
            !clock().toUtc().isBefore(verified.stored.grant.expiresAt)) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.grantExpired,
            mutation: request.mutation,
            draftId: request.draftId,
          );
        }
        if (stored == null) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            code: ExperienceAuthoringErrorCode.unavailable,
            requestId: request.requestId,
            subject: subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            mutation: request.mutation,
            draftId: request.draftId,
          );
        }
        final draft = stored.draft;
        if (stored.ownerPrincipalId != settings.principalId) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            code: ExperienceAuthoringErrorCode.ownerDenied,
            requestId: request.requestId,
            subject: draft.subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            mutation: request.mutation,
            draftId: draft.id,
            currentDraftDigest: draft.digest,
          );
        }
        if (draft.digest != request.expectedDraftDigest ||
            draft.revision != request.expectedDraftRevision) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            code: ExperienceAuthoringErrorCode.stale,
            requestId: request.requestId,
            subject: draft.subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            mutation: request.mutation,
            expectedDigest: request.expectedDraftDigest,
            currentDraftDigest: draft.digest,
            draftId: draft.id,
          );
        }
        final snapshot = _resolveSnapshot(
          requestId: request.requestId,
          subject: draft.subject,
          operation: operation,
        );
        if (snapshot.sourceDigest != draft.baseSourceDigest ||
            snapshot.contentSetDigest != draft.contentSetDigest) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            code: ExperienceAuthoringErrorCode.stale,
            requestId: request.requestId,
            subject: draft.subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            mutation: request.mutation,
            expectedDigest: draft.digest,
            currentDraftDigest: draft.digest,
            currentContentSetDigest: snapshot.contentSetDigest,
            currentSourceDigest: snapshot.sourceDigest,
            draftId: draft.id,
          );
        }
        _requireActiveGrant(
          verified: verified,
          requestId: request.requestId,
          subject: draft.subject,
          operation: operation,
        );
        request.validateAgainstGrantIntent(verified.intent, draft: draft);
        final base = transaction.requireBaseLayout(stored);
        final LayoutDraft next;
        try {
          next = switch (request.mutation) {
            LayoutDraftMutation.applyMove => draftEngine.applyMove(
              draft: draft,
              baseLayout: base,
              input: request.move!,
            ),
            LayoutDraftMutation.undo => draftEngine.undo(
              draft: draft,
              baseLayout: base,
            ),
            LayoutDraftMutation.redo => draftEngine.redo(
              draft: draft,
              baseLayout: base,
            ),
            LayoutDraftMutation.reset => draftEngine.reset(
              draft: draft,
              baseLayout: base,
            ),
          };
        } on Object {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: draft.subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: draft.revision >= experienceAuthoringMaxOperations
                ? ExperienceAuthoringErrorCode.quotaExceeded
                : ExperienceAuthoringErrorCode.invalidRequest,
            mutation: request.mutation,
            draftId: draft.id,
          );
        }
        final result = LayoutDraftMutationResult(
          requestId: request.requestId,
          draft: next,
          head: _head(
            draft: next,
            latestPromotion: transaction
                .subjectHead(draft.subject)
                .latestPromotion,
          ),
        );
        result.validateAgainst(request, previousDraft: draft);
        try {
          _requireDocument(result.toJson(includeDigest: false));
          _requireFrame(result.toJson(), result.digest);
        } on Object {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: draft.subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.quotaExceeded,
            mutation: request.mutation,
            draftId: draft.id,
          );
        }
        final nextStored = StoredLayoutDraft(
          ownerPrincipalId: stored.ownerPrincipalId,
          draft: next,
          baseLayoutBlobDigest: stored.baseLayoutBlobDigest,
        );
        try {
          transaction.commitAtomic(
            ExperienceAuthoringAtomicCommit(
              attempt: _attemptForEffect(
                StoredAuthoringAttemptFamily.draftMutation,
                requestId: request.requestId,
                requestDigest: request.digest,
                payloadDigest: request.payloadDigest,
                subject: draft.subject,
                operation: operation,
                grantId: request.grantId,
                grantDigest: request.grantDigest,
                terminal: result.toJson(),
              ),
              consumedGrantId: request.grantId,
              expectedDraftDigest: draft.digest,
              nextDraft: nextStored,
              clearReviewHead: true,
            ),
          );
        } on ExperienceAuthoringStoreFailure catch (failure) {
          if (failure.code != ExperienceAuthoringStoreErrorCode.quotaExceeded) {
            rethrow;
          }
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftMutation,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: draft.subject,
            operation: operation,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.quotaExceeded,
            mutation: request.mutation,
            draftId: draft.id,
            expectedDigest: request.expectedDraftDigest,
            currentDraftDigest: draft.digest,
          );
        }
        return result;
      });
    } on ExperienceAuthoringServiceException {
      rethrow;
    } on Object catch (error, stackTrace) {
      return _recoverEffect<LayoutDraftMutationResult>(
        requestId: request.requestId,
        family: StoredAuthoringAttemptFamily.draftMutation,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: _subjectForGrant(request.grantId, request.requestId),
        operation: _mutationOperation(request.mutation),
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: LayoutDraftMutationResult.fromJson,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  ExperienceReviewPrepareResult prepareReview(
    ExperienceReviewPrepareRequest request, {
    required String connectionEpoch,
  }) {
    final replay = _findAttemptOrUnavailable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.prepareReview,
    );
    if (replay != null) {
      return _replayEffect<ExperienceReviewPrepareResult>(
        replay,
        family: StoredAuthoringAttemptFamily.reviewPrepare,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: request.subject,
        operation: AuthoringOperation.prepareReview,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: ExperienceReviewPrepareResult.fromJson,
      );
    }
    try {
      return store.withTransaction((transaction) {
        final verified = _bindGrant(
          requestId: request.requestId,
          subject: request.subject,
          effect: AuthoringActionEffect.authoring,
          operation: AuthoringOperation.prepareReview,
          expectedDigest: request.expectedDraftDigest,
          expectedSourceDigest: request.expectedSourceDigest,
          payloadDigest: request.payloadDigest,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          connectionEpoch: connectionEpoch,
        );
        request.validateAgainstGrantIntent(verified.intent);
        _rejectPreviouslyTerminalGrant(
          verified: verified,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.prepareReview,
        );
        if (verified.stored.state == StoredAuthoringGrantState.active &&
            !clock().toUtc().isBefore(verified.stored.grant.expiresAt)) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.reviewPrepare,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.prepareReview,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.grantExpired,
            draftId: request.draftId,
          );
        }
        final stored = transaction.findDraft(request.subject);
        if (stored == null || stored.draft.id != request.draftId) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.reviewPrepare,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.prepareReview,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.unavailable,
            draftId: request.draftId,
          );
        }
        final draft = stored.draft;
        if (stored.ownerPrincipalId != settings.principalId) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.reviewPrepare,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.prepareReview,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.ownerDenied,
            draftId: draft.id,
            currentDraftDigest: draft.digest,
          );
        }
        final snapshot = _resolveSnapshot(
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.prepareReview,
        );
        if (draft.digest != request.expectedDraftDigest ||
            draft.revision != request.expectedDraftRevision ||
            draft.contentSetDigest != request.expectedContentSetDigest ||
            draft.baseSourceDigest != request.expectedSourceDigest ||
            snapshot.contentSetDigest != draft.contentSetDigest ||
            snapshot.sourceDigest != draft.baseSourceDigest) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.reviewPrepare,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.prepareReview,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.stale,
            draftId: draft.id,
            expectedDigest: request.expectedDraftDigest,
            currentDraftDigest: draft.digest,
            currentContentSetDigest: snapshot.contentSetDigest,
            currentSourceDigest: snapshot.sourceDigest,
          );
        }
        final oldHead = transaction.subjectHead(request.subject);
        if (oldHead.changeSet != null || oldHead.review != null) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.reviewPrepare,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.prepareReview,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.requestConflict,
            draftId: draft.id,
            currentDraftDigest: draft.digest,
            currentChangeSetDigest: oldHead.changeSet?.digest,
            currentReviewPacketDigest: oldHead.review?.digest,
          );
        }
        _requireActiveGrant(
          verified: verified,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.prepareReview,
        );
        final base = transaction.requireBaseLayout(stored);
        late final ExperienceChangeSet changeSet;
        late final ExperienceReviewPacket packet;
        late final ExperienceReviewPrepareResult result;
        try {
          changeSet = draftEngine.createChangeSet(
            id: ExperienceChangeSetId(
              idFactory.issue('changeset', request.digest),
            ),
            draft: draft,
            baseLayout: base,
            currentContentSetDigest: snapshot.contentSetDigest,
            currentSourceDigest: snapshot.sourceDigest!,
          );
          final binding = snapshot.reviewBinding(
            guideId: request.reviewGuideId,
            stepId: request.reviewGuideStepId,
          );
          packet = reviewCompiler.compile(
            id: ExperienceReviewPacketId(
              idFactory.issue('review', request.digest),
            ),
            changeSet: changeSet,
            catalog: snapshot.catalog,
            topology: snapshot.topology,
            allowedArtifactDigests: snapshot.allowedArtifactDigests(binding),
            reviewGuideBinding: binding,
            findings: const <ExperienceFindingRecord>[],
            concepts: const <ExperienceConceptProposalRecord>[],
            comments: const <ExperienceReviewCommentRecord>[],
            automatedAcceptance: null,
            humanDecisions: const <ExperienceHumanDecisionRecord>[],
          );
          result = ExperienceReviewPrepareResult(
            requestId: request.requestId,
            changeSet: changeSet,
            reviewPacket: packet,
            head: _head(
              draft: draft,
              changeSet: changeSet,
              packet: packet,
              latestPromotion: oldHead.latestPromotion,
            ),
          );
          result.validateAgainst(request, draft: draft);
          _requireDocument(result.toJson(includeDigest: false));
          _requireFrame(result.toJson(), result.digest);
        } on ExperienceAuthoringFrameLimitFailure {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.reviewPrepare,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.prepareReview,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.quotaExceeded,
            draftId: draft.id,
          );
        } on Object {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.reviewPrepare,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.prepareReview,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.invalidRequest,
            draftId: draft.id,
          );
        }
        transaction.commitAtomic(
          ExperienceAuthoringAtomicCommit(
            attempt: _attemptForEffect(
              StoredAuthoringAttemptFamily.reviewPrepare,
              requestId: request.requestId,
              requestDigest: request.digest,
              payloadDigest: request.payloadDigest,
              subject: request.subject,
              operation: AuthoringOperation.prepareReview,
              grantId: request.grantId,
              grantDigest: request.grantDigest,
              terminal: result.toJson(),
            ),
            consumedGrantId: request.grantId,
            expectedDraftDigest: draft.digest,
            changeSet: changeSet,
            reviewPacket: packet,
          ),
        );
        return result;
      });
    } on ExperienceAuthoringServiceException {
      rethrow;
    } on Object catch (error, stackTrace) {
      return _recoverEffect<ExperienceReviewPrepareResult>(
        requestId: request.requestId,
        family: StoredAuthoringAttemptFamily.reviewPrepare,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: request.subject,
        operation: AuthoringOperation.prepareReview,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: ExperienceReviewPrepareResult.fromJson,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  ExperienceReviewActionResult reviewAction(
    ExperienceReviewActionRequest request, {
    required String connectionEpoch,
  }) {
    final subject = request.fence.subject;
    final replay = _findAttemptOrUnavailable(
      requestId: request.requestId,
      subject: subject,
      operation: request.operation,
    );
    if (replay != null) {
      return _replayEffect<ExperienceReviewActionResult>(
        replay,
        family: StoredAuthoringAttemptFamily.reviewAction,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: subject,
        operation: request.operation,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: ExperienceReviewActionResult.fromJson,
      );
    }
    try {
      return store.withTransaction((transaction) {
        final verified = _bindGrant(
          requestId: request.requestId,
          subject: subject,
          effect: request.effect,
          operation: request.operation,
          expectedDigest: request.fence.reviewPacketDigest,
          expectedSourceDigest: request.fence.expectedSourceDigest,
          payloadDigest: request.payloadDigest,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          connectionEpoch: connectionEpoch,
        );
        request.validateAgainstGrantIntent(verified.intent);
        _rejectPreviouslyTerminalGrant(
          verified: verified,
          requestId: request.requestId,
          subject: subject,
          operation: request.operation,
        );
        if (verified.stored.state == StoredAuthoringGrantState.active &&
            !clock().toUtc().isBefore(verified.stored.grant.expiresAt)) {
          _consumeReviewError(
            transaction: transaction,
            request: request,
            code: ExperienceAuthoringErrorCode.grantExpired,
          );
        }
        final head = transaction.subjectHead(subject);
        final changeSet = transaction.findChangeSet(
          subject: subject,
          id: request.fence.changeSetId,
          expectedDigest: request.fence.changeSetDigest,
        );
        final previous = transaction.findReviewPacket(
          subject: subject,
          id: request.fence.reviewPacketId,
          expectedDigest: request.fence.reviewPacketDigest,
        );
        final snapshot = _resolveSnapshot(
          requestId: request.requestId,
          subject: subject,
          operation: request.operation,
        );
        if (changeSet == null ||
            previous == null ||
            head.changeSet?.digest != request.fence.changeSetDigest ||
            head.review?.digest != request.fence.reviewPacketDigest ||
            snapshot.sourceDigest != request.fence.expectedSourceDigest ||
            snapshot.contentSetDigest !=
                request.fence.expectedContentSetDigest) {
          _consumeReviewError(
            transaction: transaction,
            request: request,
            code: ExperienceAuthoringErrorCode.stale,
            expectedDigest: request.fence.reviewPacketDigest,
            currentDraftDigest: head.draft?.digest,
            currentChangeSetDigest: head.changeSet?.digest,
            currentContentSetDigest: snapshot.contentSetDigest,
            currentSourceDigest: snapshot.sourceDigest,
            currentReviewPacketDigest: head.review?.digest,
          );
        }
        try {
          request.fence.validateAgainst(changeSet: changeSet, packet: previous);
        } on Object {
          _consumeReviewError(
            transaction: transaction,
            request: request,
            code: ExperienceAuthoringErrorCode.stale,
            expectedDigest: request.fence.reviewPacketDigest,
            currentDraftDigest: head.draft?.digest,
            currentChangeSetDigest: head.changeSet?.digest,
            currentReviewPacketDigest: head.review?.digest,
          );
        }
        _requireActiveGrant(
          verified: verified,
          requestId: request.requestId,
          subject: subject,
          operation: request.operation,
        );
        final storedDraft = transaction.findDraft(subject);
        if (storedDraft == null ||
            storedDraft.draft.digest != changeSet.draftDigest) {
          _consumeReviewError(
            transaction: transaction,
            request: request,
            code: ExperienceAuthoringErrorCode.stale,
            expectedDigest: changeSet.draftDigest,
            currentDraftDigest: storedDraft?.draft.digest,
            currentChangeSetDigest: head.changeSet?.digest,
            currentReviewPacketDigest: head.review?.digest,
          );
        }
        if (request.operation == AuthoringOperation.decideReview) {
          if (verified.intent is! ExperienceReviewDecisionGrantRequest) {
            _consumeReviewError(
              transaction: transaction,
              request: request,
              code: ExperienceAuthoringErrorCode.grantMismatch,
            );
          }
          try {
            (verified.intent as ExperienceReviewDecisionGrantRequest)
                .validateAgainst(changeSet: changeSet, packet: previous);
          } on Object {
            _consumeReviewError(
              transaction: transaction,
              request: request,
              code: ExperienceAuthoringErrorCode.stale,
              expectedDigest: request.fence.reviewPacketDigest,
              currentReviewPacketDigest: previous.digest,
            );
          }
        }
        final base = transaction.requireBaseLayout(storedDraft);
        final candidate = draftEngine.materialize(
          draft: storedDraft.draft,
          baseLayout: base,
        );
        final allowed = snapshot.allowedArtifactDigests(
          previous.reviewGuideBinding,
        );
        late final ExperienceReviewPacket next;
        late final ExperienceReviewActionResult result;
        try {
          next = switch (request.operation) {
            AuthoringOperation.appendFinding => reviewCompiler.appendFinding(
              packet: previous,
              changeSet: changeSet,
              catalog: snapshot.catalog,
              topology: snapshot.topology,
              allowedArtifactDigests: allowed,
              id: ExperienceFindingId(
                idFactory.issue('finding', request.digest),
              ),
              input: request.finding!,
              principalId: settings.principalId!,
              authorityId: settings.authorityId!,
              grantDigest: request.grantDigest,
              recordedAt: clock().toUtc(),
            ),
            AuthoringOperation.proposeConcept => reviewCompiler.appendConcept(
              packet: previous,
              changeSet: changeSet,
              catalog: snapshot.catalog,
              topology: snapshot.topology,
              allowedArtifactDigests: allowed,
              id: ExperienceConceptProposalId(
                idFactory.issue('concept', request.digest),
              ),
              input: request.concept!,
              principalId: settings.principalId!,
              authorityId: settings.authorityId!,
              grantDigest: request.grantDigest,
              recordedAt: clock().toUtc(),
            ),
            AuthoringOperation.appendComment => reviewCompiler.appendComment(
              packet: previous,
              changeSet: changeSet,
              catalog: snapshot.catalog,
              topology: snapshot.topology,
              allowedArtifactDigests: allowed,
              id: ExperienceReviewCommentId(
                idFactory.issue('comment', request.digest),
              ),
              input: request.comment!,
              principalId: settings.principalId!,
              authorityId: settings.authorityId!,
              grantDigest: request.grantDigest,
              recordedAt: clock().toUtc(),
            ),
            AuthoringOperation.evaluateAutomatedAcceptance =>
              acceptance.evaluateAndRecord(
                packet: previous,
                changeSet: changeSet,
                draft: storedDraft.draft,
                baseLayout: base,
                candidateLayout: candidate,
                catalog: snapshot.catalog,
                topology: snapshot.topology,
                allowedArtifactDigests: allowed,
                currentSourceDigest: snapshot.sourceDigest!,
                currentContentSetDigest: snapshot.contentSetDigest,
                recordedAt: clock().toUtc(),
              ),
            AuthoringOperation.decideReview => reviewCompiler.appendDecision(
              packet: previous,
              changeSet: changeSet,
              catalog: snapshot.catalog,
              topology: snapshot.topology,
              allowedArtifactDigests: allowed,
              id: ExperienceHumanDecisionId(
                idFactory.issue('decision', request.digest),
              ),
              input: request.decision!,
              principalId: settings.principalId!,
              authorityId: settings.authorityId!,
              grantDigest: request.grantDigest,
              recordedAt: clock().toUtc(),
            ),
            _ => throw StateError('Unsupported review operation'),
          };
          result = _reviewResult(
            request: request,
            previous: previous,
            next: next,
            changeSet: changeSet,
            draft: storedDraft.draft,
            latestPromotion: head.latestPromotion,
          );
          result.validateAgainst(
            request,
            changeSet: changeSet,
            previousPacket: previous,
          );
          _requireDocument(result.toJson(includeDigest: false));
          _requireFrame(result.toJson(), result.digest);
        } on ExperienceAuthoringFrameLimitFailure {
          _consumeReviewError(
            transaction: transaction,
            request: request,
            code: ExperienceAuthoringErrorCode.quotaExceeded,
          );
        } on Object {
          _consumeReviewError(
            transaction: transaction,
            request: request,
            code: ExperienceAuthoringErrorCode.invalidRequest,
          );
        }
        transaction.commitAtomic(
          ExperienceAuthoringAtomicCommit(
            attempt: _attemptForEffect(
              StoredAuthoringAttemptFamily.reviewAction,
              requestId: request.requestId,
              requestDigest: request.digest,
              payloadDigest: request.payloadDigest,
              subject: subject,
              operation: request.operation,
              grantId: request.grantId,
              grantDigest: request.grantDigest,
              terminal: result.toJson(),
            ),
            consumedGrantId: request.grantId,
            reviewPacket: next,
          ),
        );
        return result;
      });
    } on ExperienceAuthoringServiceException {
      rethrow;
    } on Object catch (error, stackTrace) {
      return _recoverEffect<ExperienceReviewActionResult>(
        requestId: request.requestId,
        family: StoredAuthoringAttemptFamily.reviewAction,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: subject,
        operation: request.operation,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: ExperienceReviewActionResult.fromJson,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  LayoutDraftAbandonResult abandonDraft(
    LayoutDraftAbandonRequest request, {
    required String connectionEpoch,
  }) {
    final replay = _findAttemptOrUnavailable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.abandonDraft,
    );
    if (replay != null) {
      return _replayEffect<LayoutDraftAbandonResult>(
        replay,
        family: StoredAuthoringAttemptFamily.draftAbandon,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: request.subject,
        operation: AuthoringOperation.abandonDraft,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: LayoutDraftAbandonResult.fromJson,
      );
    }
    try {
      return store.withTransaction((transaction) {
        final verified = _bindGrant(
          requestId: request.requestId,
          subject: request.subject,
          effect: AuthoringActionEffect.authoring,
          operation: AuthoringOperation.abandonDraft,
          expectedDigest: request.expectedDraftDigest,
          expectedSourceDigest: request.expectedSourceDigest,
          payloadDigest: request.payloadDigest,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          connectionEpoch: connectionEpoch,
        );
        request.validateAgainstGrantIntent(verified.intent);
        _rejectPreviouslyTerminalGrant(
          verified: verified,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.abandonDraft,
        );
        if (verified.stored.state == StoredAuthoringGrantState.active &&
            !clock().toUtc().isBefore(verified.stored.grant.expiresAt)) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftAbandon,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.abandonDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.grantExpired,
            draftId: request.draftId,
          );
        }
        final stored = transaction.findDraft(request.subject);
        if (stored == null) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftAbandon,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            code: ExperienceAuthoringErrorCode.unavailable,
            requestId: request.requestId,
            subject: request.subject,
            operation: AuthoringOperation.abandonDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            draftId: request.draftId,
          );
        }
        final draft = stored.draft;
        if (stored.ownerPrincipalId != settings.principalId) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftAbandon,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            code: ExperienceAuthoringErrorCode.ownerDenied,
            requestId: request.requestId,
            subject: request.subject,
            operation: AuthoringOperation.abandonDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            draftId: draft.id,
            currentDraftDigest: draft.digest,
          );
        }
        if (draft.id != request.draftId ||
            draft.digest != request.expectedDraftDigest ||
            draft.revision != request.expectedDraftRevision ||
            draft.baseSourceDigest != request.expectedSourceDigest) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftAbandon,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            code: ExperienceAuthoringErrorCode.stale,
            requestId: request.requestId,
            subject: request.subject,
            operation: AuthoringOperation.abandonDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            expectedDigest: request.expectedDraftDigest,
            currentDraftDigest: draft.digest,
            draftId: draft.id,
          );
        }
        _requireActiveGrant(
          verified: verified,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.abandonDraft,
        );
        final now = clock().toUtc();
        final receipt = LayoutDraftAbandonReceipt(
          id: LayoutDraftAbandonReceiptId(
            idFactory.issue('abandon', request.digest),
          ),
          requestId: request.requestId,
          subject: request.subject,
          draftId: draft.id,
          finalDraftDigest: draft.digest,
          finalDraftRevision: draft.revision,
          sourceDigest: draft.baseSourceDigest,
          abandonedAt: now,
        );
        final oldHead = transaction.subjectHead(request.subject);
        final result = LayoutDraftAbandonResult(
          requestId: request.requestId,
          receipt: receipt,
          head: ExperienceAuthoringSubjectHead(
            subject: request.subject,
            latestPromotion: oldHead.latestPromotion,
          ),
        );
        result.validateAgainst(request);
        try {
          _requireDocument(result.toJson(includeDigest: false));
          _requireFrame(result.toJson(), result.digest);
        } on ExperienceAuthoringFrameLimitFailure {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.draftAbandon,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.abandonDraft,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.quotaExceeded,
            draftId: draft.id,
          );
        }
        transaction.commitAtomic(
          ExperienceAuthoringAtomicCommit(
            attempt: _attemptForEffect(
              StoredAuthoringAttemptFamily.draftAbandon,
              requestId: request.requestId,
              requestDigest: request.digest,
              payloadDigest: request.payloadDigest,
              subject: request.subject,
              operation: AuthoringOperation.abandonDraft,
              grantId: request.grantId,
              grantDigest: request.grantDigest,
              terminal: result.toJson(),
              at: now,
            ),
            consumedGrantId: request.grantId,
            expectedDraftDigest: draft.digest,
            removeDraft: true,
            clearReviewHead: true,
            abandonReceipt: receipt,
          ),
        );
        return result;
      });
    } on ExperienceAuthoringServiceException {
      rethrow;
    } on Object catch (error, stackTrace) {
      return _recoverEffect<LayoutDraftAbandonResult>(
        requestId: request.requestId,
        family: StoredAuthoringAttemptFamily.draftAbandon,
        requestDigest: request.digest,
        payloadDigest: request.payloadDigest,
        subject: request.subject,
        operation: AuthoringOperation.abandonDraft,
        grantId: request.grantId,
        grantDigest: request.grantDigest,
        decode: LayoutDraftAbandonResult.fromJson,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  ExperiencePromotionApplyResult applyPromotion(
    ExperiencePromotionApplyRequest request, {
    required String connectionEpoch,
  }) => applyPromotionWithCommitState(
    request,
    connectionEpoch: connectionEpoch,
  ).result;

  ExperienceAuthoringPromotionApplyOutcome applyPromotionWithCommitState(
    ExperiencePromotionApplyRequest request, {
    required String connectionEpoch,
  }) {
    final replay = _findAttemptOrUnavailable(
      requestId: request.requestId,
      subject: request.subject,
      operation: AuthoringOperation.promote,
    );
    if (replay != null) {
      return ExperienceAuthoringPromotionApplyOutcome(
        result: _replayEffect<ExperiencePromotionApplyResult>(
          replay,
          family: StoredAuthoringAttemptFamily.promotionApply,
          requestDigest: request.digest,
          payloadDigest: request.payloadDigest,
          subject: request.subject,
          operation: AuthoringOperation.promote,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          decode: ExperiencePromotionApplyResult.fromJson,
        ),
        durableCommitCreated: false,
      );
    }
    try {
      return store.withTransaction((transaction) {
        final concurrentReplay = transaction.findAttempt(request.requestId);
        if (concurrentReplay != null) {
          return ExperienceAuthoringPromotionApplyOutcome(
            result: _replayEffect<ExperiencePromotionApplyResult>(
              concurrentReplay,
              family: StoredAuthoringAttemptFamily.promotionApply,
              requestDigest: request.digest,
              payloadDigest: request.payloadDigest,
              subject: request.subject,
              operation: AuthoringOperation.promote,
              grantId: request.grantId,
              grantDigest: request.grantDigest,
              decode: ExperiencePromotionApplyResult.fromJson,
            ),
            durableCommitCreated: false,
          );
        }
        final verified = _bindGrant(
          requestId: request.requestId,
          subject: request.subject,
          effect: AuthoringActionEffect.authoring,
          operation: AuthoringOperation.promote,
          expectedDigest: request.reviewPacketDigest,
          expectedSourceDigest: request.expectedSourceDigest,
          payloadDigest: request.payloadDigest,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          connectionEpoch: connectionEpoch,
        );
        final intent = verified.intent;
        if (intent is! ExperiencePromotionGrantRequest) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.grantMismatch,
          );
        }
        try {
          request.validateAgainst(intent);
        } on Object {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.grantMismatch,
          );
        }
        _rejectPreviouslyTerminalGrant(
          verified: verified,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.promote,
        );
        final isPrepared =
            verified.stored.state == StoredAuthoringGrantState.inFlight;
        if (!isPrepared &&
            verified.stored.state == StoredAuthoringGrantState.active &&
            !clock().toUtc().isBefore(verified.stored.grant.expiresAt)) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.grantExpired,
          );
        }
        if (!isPrepared) {
          _requireActiveGrant(
            verified: verified,
            requestId: request.requestId,
            subject: request.subject,
            operation: AuthoringOperation.promote,
          );
        }
        final stored = transaction.findDraft(request.subject);
        final head = transaction.subjectHead(request.subject);
        final changeSet = transaction.findChangeSet(
          subject: request.subject,
          id: request.changeSetId,
          expectedDigest: request.changeSetDigest,
        );
        final packet = transaction.findReviewPacket(
          subject: request.subject,
          id: request.reviewPacketId,
          expectedDigest: request.reviewPacketDigest,
        );
        if (stored == null || changeSet == null || packet == null) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.unavailable,
            draftId: request.draftId,
            changeSetId: request.changeSetId,
            reviewPacketId: request.reviewPacketId,
          );
        }
        if (stored.ownerPrincipalId != settings.principalId) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.ownerDenied,
            draftId: stored.draft.id,
            currentDraftDigest: stored.draft.digest,
          );
        }
        try {
          intent.validateAgainst(
            draft: stored.draft,
            changeSet: changeSet,
            reviewPacket: packet,
          );
        } on Object {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.stale,
            expectedDigest: request.reviewPacketDigest,
            currentDraftDigest: head.draft?.digest,
            currentChangeSetDigest: head.changeSet?.digest,
            currentReviewPacketDigest: head.review?.digest,
            draftId: request.draftId,
            changeSetId: request.changeSetId,
            reviewPacketId: request.reviewPacketId,
          );
        }
        final snapshot = _resolveSnapshot(
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.promote,
        );
        if (!isPrepared &&
            (snapshot.sourceDigest != request.expectedSourceDigest ||
                snapshot.contentSetDigest != request.expectedContentSetDigest ||
                snapshot.layout.digest != stored.draft.baseLayoutDigest)) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.stale,
            expectedDigest: request.reviewPacketDigest,
            currentDraftDigest: head.draft?.digest,
            currentChangeSetDigest: head.changeSet?.digest,
            currentReviewPacketDigest: head.review?.digest,
            currentContentSetDigest: snapshot.contentSetDigest,
            currentSourceDigest: snapshot.sourceDigest,
            draftId: request.draftId,
            changeSetId: request.changeSetId,
            reviewPacketId: request.reviewPacketId,
          );
        }
        final executor = promotionExecutor;
        if (executor == null) {
          _consumeError(
            transaction: transaction,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestId: request.requestId,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            code: ExperienceAuthoringErrorCode.unavailable,
          );
        }
        final terminalAt = clock().toUtc();
        final rollbackError = ExperienceAuthoringError(
          code: ExperienceAuthoringErrorCode.unavailable,
          requestId: request.requestId,
          subject: request.subject,
          operation: AuthoringOperation.promote,
          draftId: request.draftId,
          changeSetId: request.changeSetId,
          reviewPacketId: request.reviewPacketId,
        );
        _requireDocument(rollbackError.toJson(includeDigest: false));
        _requireFrame(rollbackError.toJson(), rollbackError.digest);
        final rollbackAttempt = _attemptForEffect(
          StoredAuthoringAttemptFamily.promotionApply,
          requestId: request.requestId,
          requestDigest: request.digest,
          payloadDigest: request.payloadDigest,
          subject: request.subject,
          operation: AuthoringOperation.promote,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          terminal: rollbackError.toJson(),
          isError: true,
          at: terminalAt,
        );
        try {
          executor.promote(
            request: request,
            changeSet: changeSet,
            reviewPacket: packet,
            allowedArtifactDigests: snapshot.allowedArtifactDigests(
              packet.reviewGuideBinding,
            ),
            promotedAt: terminalAt,
            rollbackAttempt: rollbackAttempt,
            successAttemptFactory: (receipt) {
              final result = ExperiencePromotionApplyResult(
                requestId: request.requestId,
                receipt: receipt,
                head: ExperienceAuthoringSubjectHead(
                  subject: request.subject,
                  latestPromotion: ExperiencePromotionHeadRef.fromReceipt(
                    receipt,
                  ),
                ),
              );
              result.validateAgainst(request);
              _requireDocument(result.toJson(includeDigest: false));
              _requireFrame(result.toJson(), result.digest);
              return _attemptForEffect(
                StoredAuthoringAttemptFamily.promotionApply,
                requestId: request.requestId,
                requestDigest: request.digest,
                payloadDigest: request.payloadDigest,
                subject: request.subject,
                operation: AuthoringOperation.promote,
                grantId: request.grantId,
                grantDigest: request.grantDigest,
                terminal: result.toJson(),
                at: terminalAt,
              );
            },
          );
        } on Object catch (error, stackTrace) {
          final terminal = transaction.findAttempt(request.requestId);
          if (terminal != null) {
            return ExperienceAuthoringPromotionApplyOutcome(
              result: _replayEffect<ExperiencePromotionApplyResult>(
                terminal,
                family: StoredAuthoringAttemptFamily.promotionApply,
                requestDigest: request.digest,
                payloadDigest: request.payloadDigest,
                subject: request.subject,
                operation: AuthoringOperation.promote,
                grantId: request.grantId,
                grantDigest: request.grantDigest,
                decode: ExperiencePromotionApplyResult.fromJson,
              ),
              durableCommitCreated: true,
            );
          }
          final currentGrant = transaction.findGrant(request.grantId);
          if (currentGrant?.state == StoredAuthoringGrantState.active) {
            _consumeError(
              transaction: transaction,
              family: StoredAuthoringAttemptFamily.promotionApply,
              requestId: request.requestId,
              requestDigest: request.digest,
              payloadDigest: request.payloadDigest,
              subject: request.subject,
              operation: AuthoringOperation.promote,
              grantId: request.grantId,
              grantDigest: request.grantDigest,
              code: _isFrameLimit(error)
                  ? ExperienceAuthoringErrorCode.quotaExceeded
                  : ExperienceAuthoringErrorCode.unavailable,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        final terminal = transaction.findAttempt(request.requestId);
        if (terminal == null) {
          throw StateError('Promotion completed without a terminal attempt');
        }
        return ExperienceAuthoringPromotionApplyOutcome(
          result: _replayEffect<ExperiencePromotionApplyResult>(
            terminal,
            family: StoredAuthoringAttemptFamily.promotionApply,
            requestDigest: request.digest,
            payloadDigest: request.payloadDigest,
            subject: request.subject,
            operation: AuthoringOperation.promote,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
            decode: ExperiencePromotionApplyResult.fromJson,
          ),
          durableCommitCreated: true,
        );
      });
    } on ExperienceAuthoringServiceException {
      rethrow;
    } on Object catch (error, stackTrace) {
      return ExperienceAuthoringPromotionApplyOutcome(
        result: _recoverEffect<ExperiencePromotionApplyResult>(
          requestId: request.requestId,
          family: StoredAuthoringAttemptFamily.promotionApply,
          requestDigest: request.digest,
          payloadDigest: request.payloadDigest,
          subject: request.subject,
          operation: AuthoringOperation.promote,
          grantId: request.grantId,
          grantDigest: request.grantDigest,
          decode: ExperiencePromotionApplyResult.fromJson,
          cause: error,
          stackTrace: stackTrace,
        ),
        durableCommitCreated: true,
      );
    }
  }

  int revokeAllForSubject(
    AuthoringSubjectRef subject, {
    required String reason,
  }) => store.revokeAllForSubject(subject, reason: reason, at: clock().toUtc());

  int revokeAllForAuthority(
    AuthoringAuthorityId authorityId, {
    required String reason,
  }) => store.revokeAllForAuthority(
    authorityId,
    reason: reason,
    at: clock().toUtc(),
  );

  int revokeConnection(String connectionEpoch) =>
      store.revokeAllForConnectionEpoch(
        _validatedEpoch(connectionEpoch),
        reason: 'connection-closed',
        at: clock().toUtc(),
      );

  int close() =>
      store.revokeAllActive(reason: 'service-closed', at: clock().toUtc());

  ExperienceAuthoringWorkspaceSnapshot _resolveSnapshot({
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
  }) {
    try {
      final snapshot = workspaceResolver.resolve(subject);
      if (snapshot.subject != subject) {
        throw StateError('Workspace resolver returned another subject');
      }
      return snapshot;
    } on Object catch (error, stackTrace) {
      try {
        diagnosticSink?.call(error, stackTrace);
      } on Object {
        // Diagnostics are private best-effort and never affect the wire error.
      }
      _throwError(
        code: ExperienceAuthoringErrorCode.capabilityUnavailable,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
  }

  void _requireQueryable({
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
  }) {
    final capability = moduleSupport.capabilityFor(subject);
    final snapshot = _resolveSnapshot(
      requestId: requestId,
      subject: subject,
      operation: operation,
    );
    if (capability == null ||
        snapshot.sourceDigest == null ||
        !store.isDurabilityAvailable) {
      _throwError(
        code: ExperienceAuthoringErrorCode.capabilityUnavailable,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    if (!_effectiveQueryOperations(capability).contains(operation)) {
      _throwError(
        code: ExperienceAuthoringErrorCode.policyDenied,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
  }

  AuthoringCapability _requireAvailable({
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    Digest? capabilityDigest,
  }) {
    final capability = moduleSupport.capabilityFor(subject);
    final snapshot = _resolveSnapshot(
      requestId: requestId,
      subject: subject,
      operation: operation,
    );
    if (capability == null ||
        snapshot.sourceDigest == null ||
        !store.isDurabilityAvailable) {
      _throwError(
        code: ExperienceAuthoringErrorCode.capabilityUnavailable,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    if (!settings.hasAuthority ||
        !settings.allowedOperations.contains(operation)) {
      _throwError(
        code: ExperienceAuthoringErrorCode.policyDenied,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    if (capabilityDigest != null && capability.digest != capabilityDigest ||
        !capability.operations.contains(operation)) {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantMismatch,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    return capability;
  }

  void _validateGrantFence(AuthoringGrantIntent intent) {
    final snapshot = _resolveSnapshot(
      requestId: intent.requestId,
      subject: intent.subject,
      operation: intent.operation,
    );
    final source = snapshot.sourceDigest;
    if (source == null) {
      _throwError(
        code: ExperienceAuthoringErrorCode.unsupported,
        requestId: intent.requestId,
        subject: intent.subject,
        operation: intent.operation,
      );
    }
    final head = store.subjectHead(intent.subject);
    final storedDraft = store.findDraft(intent.subject);
    final valid = switch (intent.operation) {
      AuthoringOperation.openDraft =>
        intent.expectedDigest == snapshot.contentSetDigest &&
            intent.expectedSourceDigest == source,
      AuthoringOperation.moveNode ||
      AuthoringOperation.undo ||
      AuthoringOperation.redo ||
      AuthoringOperation.reset ||
      AuthoringOperation.prepareReview =>
        head.draft != null &&
            storedDraft != null &&
            intent.expectedDigest == head.draft!.digest &&
            intent.expectedSourceDigest == storedDraft.draft.baseSourceDigest &&
            source == storedDraft.draft.baseSourceDigest &&
            snapshot.contentSetDigest == storedDraft.draft.contentSetDigest,
      AuthoringOperation.abandonDraft =>
        head.draft != null &&
            storedDraft != null &&
            intent.expectedDigest == head.draft!.digest &&
            intent.expectedSourceDigest == storedDraft.draft.baseSourceDigest,
      AuthoringOperation.appendFinding ||
      AuthoringOperation.proposeConcept ||
      AuthoringOperation.appendComment ||
      AuthoringOperation.evaluateAutomatedAcceptance =>
        head.review != null &&
            intent.expectedDigest == head.review!.digest &&
            intent.expectedSourceDigest == source &&
            storedDraft != null &&
            storedDraft.draft.baseSourceDigest == source &&
            storedDraft.draft.contentSetDigest == snapshot.contentSetDigest,
      _ => false,
    };
    if (!valid) {
      _throwStale(
        requestId: intent.requestId,
        subject: intent.subject,
        operation: intent.operation,
        expectedDigest: intent.expectedDigest,
        currentDraftDigest: head.draft?.digest,
        currentContentSetDigest: snapshot.contentSetDigest,
        currentSourceDigest: source,
        currentReviewPacketDigest: head.review?.digest,
      );
    }
  }

  _VerifiedGrant _bindGrant({
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringActionEffect effect,
    required AuthoringOperation operation,
    required Digest expectedDigest,
    required Digest expectedSourceDigest,
    required Digest payloadDigest,
    required AuthoringActionGrantId grantId,
    required Digest grantDigest,
    required String connectionEpoch,
  }) {
    final stored = store.findGrant(grantId);
    if (stored == null || stored.grant.digest != grantDigest) {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantMismatch,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    final capability = _requireAvailable(
      requestId: requestId,
      subject: subject,
      operation: operation,
      capabilityDigest: stored.grant.capabilityDigest,
    );
    if (requestId == stored.grant.requestId) {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantMismatch,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    if (stored.connectionEpoch != _validatedEpoch(connectionEpoch)) {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantRevoked,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    final intent = store.grantIntent(stored);
    try {
      grantVerifier.verify(
        capability: capability,
        grant: stored.grant,
        intent: intent,
        authorityId: settings.authorityId!,
        policyId: settings.policyId!,
        principalId: settings.principalId!,
        currentResolvedPlanDigest: moduleSupport.resolvedPlanDigest,
        subject: subject,
        effect: effect,
        operation: operation,
        expectedDigest: expectedDigest,
        expectedSourceDigest: expectedSourceDigest,
        payloadDigest: payloadDigest,
        grantRevoked: false,
        grantConsumed: false,
        at: stored.grant.issuedAt,
      );
    } on Object {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantMismatch,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    return _VerifiedGrant(stored: stored, intent: intent);
  }

  void _rejectPreviouslyTerminalGrant({
    required _VerifiedGrant verified,
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
  }) {
    final stored = verified.stored;
    if (stored.state == StoredAuthoringGrantState.consumed) {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantConsumed,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    if (stored.state == StoredAuthoringGrantState.revoked &&
        stored.revocationReason != 'subject-head-changed') {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantRevoked,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
  }

  void _requireActiveGrant({
    required _VerifiedGrant verified,
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
  }) {
    if (verified.stored.state != StoredAuthoringGrantState.active) {
      _throwError(
        code: ExperienceAuthoringErrorCode.grantRevoked,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
  }

  _CurrentReviewPair _currentReviewPair(AuthoringSubjectRef subject) {
    final head = store.subjectHead(subject);
    final changeRef = head.changeSet;
    final reviewRef = head.review;
    if (changeRef == null || reviewRef == null) {
      throw StateError('Current review pair is unavailable');
    }
    final changeSet = store.findChangeSet(
      subject: subject,
      id: changeRef.id,
      expectedDigest: changeRef.digest,
    );
    final packet = store.findReviewPacket(
      subject: subject,
      id: reviewRef.id,
      expectedDigest: reviewRef.digest,
    );
    if (changeSet == null || packet == null) {
      throw const FormatException('Current review index is corrupt');
    }
    return _CurrentReviewPair(changeSet: changeSet, packet: packet);
  }

  _CurrentReviewPair _currentReviewPairForIntent(AuthoringGrantIntent intent) {
    try {
      return _currentReviewPair(intent.subject);
    } on Object {
      final head = store.subjectHead(intent.subject);
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: intent.requestId,
        subject: intent.subject,
        operation: intent.operation,
        currentDraftDigest: head.draft?.digest,
        currentChangeSetDigest: head.changeSet?.digest,
        currentReviewPacketDigest: head.review?.digest,
      );
    }
  }

  AuthoringSubjectRef _subjectForGrant(
    AuthoringActionGrantId grantId,
    AuthoringRequestId requestId,
  ) =>
      store.findGrant(grantId)?.grant.subject ??
      _subjectForGrantIdFallback(requestId);

  Digest _expectedSourceForGrant(AuthoringActionGrantId grantId) {
    final stored = store.findGrant(grantId);
    if (stored == null) throw StateError('Authoring grant is unavailable');
    return stored.grant.expectedSourceDigest;
  }

  AuthoringSubjectRef _subjectForGrantIdFallback(AuthoringRequestId requestId) {
    throw StateError('Cannot resolve authoring subject for ${requestId.value}');
  }

  Never _throwStaleReviewIntent(AuthoringGrantIntent intent) {
    final head = store.subjectHead(intent.subject);
    _throwStale(
      requestId: intent.requestId,
      subject: intent.subject,
      operation: intent.operation,
      expectedDigest: intent.expectedDigest,
      currentDraftDigest: head.draft?.digest,
      currentChangeSetDigest: head.changeSet?.digest,
      currentReviewPacketDigest: head.review?.digest,
    );
  }

  static AuthoringOperation _mutationOperation(LayoutDraftMutation mutation) =>
      switch (mutation) {
        LayoutDraftMutation.applyMove => AuthoringOperation.moveNode,
        LayoutDraftMutation.undo => AuthoringOperation.undo,
        LayoutDraftMutation.redo => AuthoringOperation.redo,
        LayoutDraftMutation.reset => AuthoringOperation.reset,
      };

  ExperienceReviewActionResult _reviewResult({
    required ExperienceReviewActionRequest request,
    required ExperienceReviewPacket previous,
    required ExperienceReviewPacket next,
    required ExperienceChangeSet changeSet,
    required LayoutDraft draft,
    required ExperiencePromotionHeadRef? latestPromotion,
  }) {
    final priorFindingDigests = previous.findings
        .map((record) => record.digest)
        .toSet();
    final priorConceptDigests = previous.concepts
        .map((record) => record.digest)
        .toSet();
    final finding = request.operation == AuthoringOperation.appendFinding
        ? next.findings.singleWhere(
            (record) => !priorFindingDigests.contains(record.digest),
          )
        : null;
    final concept = request.operation == AuthoringOperation.proposeConcept
        ? next.concepts.singleWhere(
            (record) => !priorConceptDigests.contains(record.digest),
          )
        : null;
    final comment = request.operation == AuthoringOperation.appendComment
        ? next.comments.last
        : null;
    final automatedAcceptance =
        request.operation == AuthoringOperation.evaluateAutomatedAcceptance
        ? next.automatedAcceptance
        : null;
    final decision = request.operation == AuthoringOperation.decideReview
        ? next.humanDecisions.last
        : null;
    return ExperienceReviewActionResult(
      requestId: request.requestId,
      operation: request.operation,
      reviewPacket: next,
      head: _head(
        draft: draft,
        changeSet: changeSet,
        packet: next,
        latestPromotion: latestPromotion,
      ),
      finding: finding,
      concept: concept,
      comment: comment,
      automatedAcceptance: automatedAcceptance,
      decision: decision,
    );
  }

  Never _consumeReviewError({
    required ExperienceAuthoringStoreTransaction transaction,
    required ExperienceReviewActionRequest request,
    required ExperienceAuthoringErrorCode code,
    Digest? expectedDigest,
    Digest? currentDraftDigest,
    Digest? currentChangeSetDigest,
    Digest? currentContentSetDigest,
    Digest? currentSourceDigest,
    Digest? currentReviewPacketDigest,
  }) => _consumeError(
    transaction: transaction,
    family: StoredAuthoringAttemptFamily.reviewAction,
    requestId: request.requestId,
    requestDigest: request.digest,
    payloadDigest: request.payloadDigest,
    subject: request.fence.subject,
    operation: request.operation,
    grantId: request.grantId,
    grantDigest: request.grantDigest,
    code: code,
    changeSetId: request.fence.changeSetId,
    reviewPacketId: request.fence.reviewPacketId,
    expectedDigest: expectedDigest,
    currentDraftDigest: currentDraftDigest,
    currentChangeSetDigest: currentChangeSetDigest,
    currentContentSetDigest: currentContentSetDigest,
    currentSourceDigest: currentSourceDigest,
    currentReviewPacketDigest: currentReviewPacketDigest,
  );

  StoredAuthoringAttempt _attemptForEffect(
    StoredAuthoringAttemptFamily family, {
    required AuthoringRequestId requestId,
    required Digest requestDigest,
    required Digest payloadDigest,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    required AuthoringActionGrantId grantId,
    required Digest grantDigest,
    required Map<String, Object?> terminal,
    DateTime? at,
    bool isError = false,
  }) => _attempt(
    family: family,
    requestId: requestId,
    requestDigest: requestDigest,
    payloadDigest: payloadDigest,
    subject: subject,
    effect: authoringEffectFor(operation),
    operation: operation,
    grantId: grantId,
    grantDigest: grantDigest,
    terminal: terminal,
    isError: isError,
    at: at ?? clock().toUtc(),
  );

  StoredAuthoringAttempt _attempt({
    required StoredAuthoringAttemptFamily family,
    required AuthoringRequestId requestId,
    required Digest requestDigest,
    required Digest payloadDigest,
    required AuthoringSubjectRef subject,
    required AuthoringActionEffect effect,
    required AuthoringOperation operation,
    required AuthoringActionGrantId? grantId,
    required Digest? grantDigest,
    required Map<String, Object?> terminal,
    required bool isError,
    required DateTime at,
  }) => StoredAuthoringAttempt(
    family: family,
    requestId: requestId,
    requestDigest: requestDigest,
    payloadDigest: payloadDigest,
    subject: subject,
    effect: effect,
    operation: operation,
    grantId: grantId,
    grantDigest: grantDigest,
    isError: isError,
    terminalJson: terminal,
    completedAt: at,
  );

  Never _consumeError({
    required ExperienceAuthoringStoreTransaction transaction,
    required StoredAuthoringAttemptFamily family,
    required AuthoringRequestId requestId,
    required Digest requestDigest,
    required Digest payloadDigest,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    required AuthoringActionGrantId grantId,
    required Digest grantDigest,
    required ExperienceAuthoringErrorCode code,
    LayoutDraftMutation? mutation,
    LayoutDraftId? draftId,
    ExperienceChangeSetId? changeSetId,
    ExperienceReviewPacketId? reviewPacketId,
    Digest? expectedDigest,
    Digest? currentDraftDigest,
    Digest? currentChangeSetDigest,
    Digest? currentContentSetDigest,
    Digest? currentSourceDigest,
    Digest? currentReviewPacketDigest,
  }) {
    final error = ExperienceAuthoringError(
      code: code,
      requestId: requestId,
      subject: subject,
      operation: operation,
      mutation: mutation,
      draftId: draftId,
      changeSetId: changeSetId,
      reviewPacketId: reviewPacketId,
      expectedDigest: expectedDigest,
      currentDraftDigest: currentDraftDigest,
      currentChangeSetDigest: currentChangeSetDigest,
      currentContentSetDigest: currentContentSetDigest,
      currentSourceDigest: currentSourceDigest,
      currentReviewPacketDigest: currentReviewPacketDigest,
    );
    _requireDocument(error.toJson(includeDigest: false));
    _requireFrame(error.toJson(), error.digest);
    transaction.commitAtomic(
      ExperienceAuthoringAtomicCommit(
        attempt: _attemptForEffect(
          family,
          requestId: requestId,
          requestDigest: requestDigest,
          payloadDigest: payloadDigest,
          subject: subject,
          operation: operation,
          grantId: grantId,
          grantDigest: grantDigest,
          terminal: error.toJson(),
          isError: true,
        ),
        consumedGrantId: grantId,
      ),
    );
    throw ExperienceAuthoringServiceException(error);
  }

  void _commitAndRecover(ExperienceAuthoringAtomicCommit commit) {
    try {
      store.commitAtomic(commit);
    } on Object catch (error, stackTrace) {
      final recovered = _findAttemptOrUnavailable(
        requestId: commit.attempt.requestId,
        subject: commit.attempt.subject,
        operation: commit.attempt.operation,
      );
      if (recovered != null && recovered.digest == commit.attempt.digest) {
        return;
      }
      _reportDiagnostic(error, stackTrace);
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: commit.attempt.requestId,
        subject: commit.attempt.subject,
        operation: commit.attempt.operation,
      );
    }
  }

  T _recoverEffect<T>({
    required AuthoringRequestId requestId,
    required StoredAuthoringAttemptFamily family,
    required Digest requestDigest,
    required Digest payloadDigest,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    required AuthoringActionGrantId grantId,
    required Digest grantDigest,
    required T Function(Object?) decode,
    required Object cause,
    required StackTrace stackTrace,
  }) {
    final attempt = _findAttemptOrUnavailable(
      requestId: requestId,
      subject: subject,
      operation: operation,
    );
    if (attempt == null) {
      _reportDiagnostic(cause, stackTrace);
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    return _replayEffect<T>(
      attempt,
      family: family,
      requestDigest: requestDigest,
      payloadDigest: payloadDigest,
      subject: subject,
      operation: operation,
      grantId: grantId,
      grantDigest: grantDigest,
      decode: decode,
    );
  }

  StoredAuthoringAttempt? _findAttemptOrUnavailable({
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
  }) {
    if (!store.isDurabilityAvailable) {
      _throwError(
        code: store.hasDurabilityUncertainty
            ? ExperienceAuthoringErrorCode.unavailable
            : ExperienceAuthoringErrorCode.capabilityUnavailable,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
    try {
      return store.findAttempt(requestId);
    } on ExperienceAuthoringStateDurabilityFailure catch (error, stackTrace) {
      _reportDiagnostic(error, stackTrace);
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    } on Object catch (error, stackTrace) {
      _reportDiagnostic(error, stackTrace);
      _throwError(
        code: ExperienceAuthoringErrorCode.unavailable,
        requestId: requestId,
        subject: subject,
        operation: operation,
      );
    }
  }

  void _reportDiagnostic(Object error, StackTrace stackTrace) {
    try {
      diagnosticSink?.call(error, stackTrace);
    } on Object {
      // Diagnostics are private best-effort and never affect the wire error.
    }
  }

  T _replayEffect<T>(
    StoredAuthoringAttempt attempt, {
    required StoredAuthoringAttemptFamily family,
    required Digest requestDigest,
    required Digest payloadDigest,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    required AuthoringActionGrantId grantId,
    required Digest grantDigest,
    required T Function(Object?) decode,
  }) => _replay<T>(
    attempt,
    family: family,
    requestDigest: requestDigest,
    payloadDigest: payloadDigest,
    subject: subject,
    effect: authoringEffectFor(operation),
    operation: operation,
    grantId: grantId,
    grantDigest: grantDigest,
    decode: decode,
  );

  T _replay<T>(
    StoredAuthoringAttempt attempt, {
    required StoredAuthoringAttemptFamily family,
    required Digest requestDigest,
    required Digest payloadDigest,
    required AuthoringSubjectRef subject,
    required AuthoringActionEffect effect,
    required AuthoringOperation operation,
    required AuthoringActionGrantId? grantId,
    required Digest? grantDigest,
    required T Function(Object?) decode,
  }) {
    if (attempt.family != family ||
        !attempt.matches(
          candidateRequestDigest: requestDigest,
          candidatePayloadDigest: payloadDigest,
          candidateSubject: subject,
          candidateEffect: effect,
          candidateOperation: operation,
          candidateGrantId: grantId,
          candidateGrantDigest: grantDigest,
        )) {
      _throwError(
        code: ExperienceAuthoringErrorCode.requestConflict,
        requestId: attempt.requestId,
        subject: subject,
        operation: operation,
      );
    }
    if (attempt.isError) {
      throw ExperienceAuthoringServiceException(
        ExperienceAuthoringError.fromJson(attempt.terminalJson),
      );
    }
    return decode(attempt.terminalJson);
  }

  static ExperienceAuthoringSubjectHead _head({
    required LayoutDraft draft,
    ExperienceChangeSet? changeSet,
    ExperienceReviewPacket? packet,
    ExperiencePromotionHeadRef? latestPromotion,
  }) => ExperienceAuthoringSubjectHead(
    subject: draft.subject,
    draft: LayoutDraftHeadRef.fromDraft(draft),
    changeSet: changeSet == null
        ? null
        : ExperienceChangeSetHeadRef.fromChangeSet(changeSet),
    review: packet == null ? null : ExperienceReviewHeadRef.fromPacket(packet),
    latestPromotion: latestPromotion,
  );

  static void _requireDocument(Map<String, Object?> json) {
    if (utf8.encode(jsonEncode(json)).length >
        experienceAuthoringMaxDocumentBytes) {
      throw const ExperienceAuthoringFrameLimitFailure();
    }
  }

  static void _requireFrame(Map<String, Object?> json, Digest digest) {
    if (digest.value.isEmpty ||
        utf8.encode(jsonEncode(json)).length >
            experienceAuthoringMaxFrameBytes) {
      throw const ExperienceAuthoringFrameLimitFailure();
    }
  }

  static bool _isFrameLimit(Object error) =>
      error is ExperienceAuthoringFrameLimitFailure;

  static String _validatedEpoch(String value) {
    final bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > 128) {
      throw ArgumentError.value(value, 'connectionEpoch');
    }
    return value;
  }

  Never _throwStale({
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    required Digest expectedDigest,
    LayoutDraftMutation? mutation,
    LayoutDraftId? draftId,
    Digest? currentDraftDigest,
    Digest? currentChangeSetDigest,
    Digest? currentContentSetDigest,
    Digest? currentSourceDigest,
    Digest? currentReviewPacketDigest,
  }) => _throwError(
    code: ExperienceAuthoringErrorCode.stale,
    requestId: requestId,
    subject: subject,
    operation: operation,
    mutation: mutation,
    draftId: draftId,
    expectedDigest: expectedDigest,
    currentDraftDigest: currentDraftDigest,
    currentChangeSetDigest: currentChangeSetDigest,
    currentContentSetDigest: currentContentSetDigest,
    currentSourceDigest: currentSourceDigest,
    currentReviewPacketDigest: currentReviewPacketDigest,
  );

  Never _throwError({
    required ExperienceAuthoringErrorCode code,
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    AuthoringOperation? operation,
    LayoutDraftMutation? mutation,
    LayoutDraftId? draftId,
    ExperienceChangeSetId? changeSetId,
    ExperienceReviewPacketId? reviewPacketId,
    Digest? expectedDigest,
    Digest? currentDraftDigest,
    Digest? currentChangeSetDigest,
    Digest? currentContentSetDigest,
    Digest? currentSourceDigest,
    Digest? currentReviewPacketDigest,
  }) {
    throw ExperienceAuthoringServiceException(
      ExperienceAuthoringError(
        code: code,
        requestId: requestId,
        subject: subject,
        operation: operation,
        mutation: mutation,
        draftId: draftId,
        changeSetId: changeSetId,
        reviewPacketId: reviewPacketId,
        expectedDigest: expectedDigest,
        currentDraftDigest: currentDraftDigest,
        currentChangeSetDigest: currentChangeSetDigest,
        currentContentSetDigest: currentContentSetDigest,
        currentSourceDigest: currentSourceDigest,
        currentReviewPacketDigest: currentReviewPacketDigest,
      ),
    );
  }
}

final class _VerifiedGrant {
  const _VerifiedGrant({required this.stored, required this.intent});

  final StoredAuthoringGrant stored;
  final AuthoringGrantIntent intent;
}

final class _CurrentReviewPair {
  const _CurrentReviewPair({required this.changeSet, required this.packet});

  final ExperienceChangeSet changeSet;
  final ExperienceReviewPacket packet;
}

/// Internal boundary signal used by the configured promotion executor before
/// it creates a filesystem WAL. Public RPC handlers always translate this to
/// the typed `quotaExceeded` authoring error.
final class ExperienceAuthoringFrameLimitFailure implements Exception {
  const ExperienceAuthoringFrameLimitFailure();
}

DateTime _utcNow() => DateTime.now().toUtc();
