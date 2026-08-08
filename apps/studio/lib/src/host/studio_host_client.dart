import 'package:experience_contracts/experience_contracts.dart';

import '../lab/studio_lab_relay_transport.dart';

abstract interface class StudioHostClient {
  Future<WorkspaceSnapshot> openWorkspace();

  Future<WorkspaceSnapshot> refreshWorkspace();

  Future<void> close();
}

/// One catalog-bound generation opened through the atomic content-set RPC.
final class StudioWorkspaceContent {
  StudioWorkspaceContent({
    required this.snapshot,
    this.experienceBundle,
    this.scenarioFacets,
    this.scenarioLab,
    this.motion,
    required this.identity,
  }) {
    if (experienceBundle != null &&
        experienceBundle!.catalogDigest != snapshot.catalog.digest) {
      throw ArgumentError(
        'Experience topology belongs to another workspace catalog',
      );
    }
    if (scenarioFacets != null &&
        scenarioFacets!.catalogDigest != snapshot.catalog.digest) {
      throw ArgumentError(
        'Scenario facets belong to another workspace catalog',
      );
    }
    if (scenarioLab != null &&
        scenarioLab!.catalogDigest != snapshot.catalog.digest) {
      throw ArgumentError('Scenario Lab belongs to another workspace catalog');
    }
    if (motion != null) {
      final topology = experienceBundle?.topology;
      if (topology == null) {
        throw ArgumentError('Motion requires Experience topology');
      }
      motion!.validateAgainst(catalog: snapshot.catalog, topology: topology);
    }
    if (identity.catalogDigest != snapshot.catalog.digest ||
        identity.workspaceSnapshotDigest != snapshot.digest ||
        identity.workspaceContentDigest != snapshot.workspaceContentDigest ||
        identity.experienceTopologyBundleDigest != experienceBundle?.digest ||
        identity.scenarioFacetManifestDigest != scenarioFacets?.digest ||
        identity.scenarioLabManifestDigest != scenarioLab?.digest ||
        identity.motionManifestDigest != motion?.digest) {
      throw ArgumentError(
        'Content identity does not match its decoded resources',
      );
    }
  }

  final WorkspaceSnapshot snapshot;
  final ExperienceTopologyBundle? experienceBundle;
  final ScenarioFacetManifest? scenarioFacets;
  final ScenarioLabManifest? scenarioLab;
  final MotionManifest? motion;

  final ExperienceContentSetIdentity identity;
}

/// Atomic read surface for one complete Host content generation.
abstract interface class StudioHostContentClient {
  Future<StudioWorkspaceContent> openContent();

  Future<StudioWorkspaceContent> refreshContent();
}

/// Optional canonical Experience read-model surface.
///
/// Returns `null` when the Host explicitly reports that no Experience topology
/// was authored for the current catalog.
abstract interface class StudioHostExperienceClient {
  Future<ExperienceTopologyBundle?> openExperience({
    required CatalogManifest catalog,
  });
}

/// Optional event surface implemented by transports that can receive Host
/// workspace revision notifications.
abstract interface class StudioHostWorkspaceEvents {
  Stream<void> get workspaceChanges;
}

/// Optional Host-authoritative Experience Authoring surface.
///
/// Query methods are grant-free. Every effect uses a request-bound,
/// single-use grant and callers must keep both capability and grant material
/// inside the transient grant-to-effect call stack.
abstract interface class StudioHostExperienceAuthoringClient {
  Future<ExperienceAuthoringDescription> describeExperienceAuthoring(
    ExperienceAuthoringDescribeRequest request,
  );

  Future<ExperienceAuthoringSubjectHeadResult> getExperienceAuthoringHead(
    ExperienceAuthoringSubjectHeadRequest request,
  );

  Future<LayoutDraftOpenResult> openExperienceLayoutDraft(
    LayoutDraftOpenRequest request,
  );

  Future<LayoutDraftGetResult> getExperienceLayoutDraft(
    LayoutDraftGetRequest request,
  );

  Future<AuthoringGrantResult> requestExperienceAuthoringGrant(
    AuthoringGrantRequest request,
  );

  Future<LayoutDraftMutationResult> mutateExperienceLayoutDraft(
    LayoutDraftMutationRequest request, {
    required AuthoringSubjectRef subject,
  });

  Future<ExperienceReviewPrepareResult> prepareExperienceReview(
    ExperienceReviewPrepareRequest request,
  );

  Future<ExperienceChangeSetGetResult> getExperienceChangeSet(
    ExperienceChangeSetGetRequest request,
  );

  Future<ExperienceReviewGetResult> getExperienceReview(
    ExperienceReviewGetRequest request,
  );

  Future<ExperienceReviewActionResult> applyExperienceReviewAction(
    ExperienceReviewActionRequest request,
  );

  Future<AuthoringGrantResult> requestExperienceDecisionGrant(
    ExperienceReviewDecisionGrantRequest request,
  );

  Future<LayoutDraftAbandonResult> abandonExperienceLayoutDraft(
    LayoutDraftAbandonRequest request,
  );

  Future<AuthoringGrantResult> requestExperiencePromotionGrant(
    ExperiencePromotionGrantRequest request,
  );

  Future<ExperiencePromotionApplyResult> applyExperiencePromotion(
    ExperiencePromotionApplyRequest request,
  );

  Future<ExperiencePromotionGetResult> getExperiencePromotion(
    ExperiencePromotionGetRequest request,
  );

  Future<ExperiencePromotionHistoryResult> getExperiencePromotionHistory(
    ExperiencePromotionHistoryRequest request,
  );
}

abstract interface class StudioHostContextBuilderClient {
  Future<ContextBuilderDescription> describeContextBuilder();

  Future<ContextBuildResult> buildContext(ContextBuildRequest request);
}

abstract interface class StudioHostPreviewClient {
  Future<Map<String, Object?>> collectPreview({
    required String applicationId,
    String? scenarioId,
    String? variantId,
    required bool syntheticDataConfirmed,
  });

  Future<Map<String, Object?>> previewStatus(String operationId);

  Future<Map<String, Object?>> cancelPreview(String operationId);
}

/// Optional local execution surface. It is only implemented when the Host
/// advertises the sessions RPC contribution; callers must still capability
/// gate the corresponding Studio route from [EffectiveKitManifest].
abstract interface class StudioHostSessionClient {
  Future<SessionSnapshot> startSession({
    required String launchProfileId,
    required Uri targetOrigin,
  });

  Future<SessionSnapshot> sessionStatus(String sessionId);

  Future<SessionSnapshot> resetSession(String sessionId);

  Future<SessionSnapshot> stopSession(String sessionId);

  Future<SessionSnapshot> cancelSession(String sessionId, {String? reason});
}

/// Optional Gateway sidecar surface. Plans remain Host-owned CAS artifacts;
/// the Studio sends only their digest and never reads workspace paths.
abstract interface class StudioHostGatewayClient {
  Future<List<GatewayPlanArtifactDescriptor>> gatewayPresets();

  Future<Map<String, Object?>> startGateway({
    required String ownerSessionId,
    required Digest planArtifactDigest,
  });

  Future<Map<String, Object?>> gatewayStatus(String gatewaySessionId);

  Future<List<Map<String, Object?>>> gatewayTraffic(
    String gatewaySessionId, {
    int afterSequence = 0,
    int limit = 100,
  });

  Future<Map<String, Object?>> resetGateway(String gatewaySessionId);

  Future<Map<String, Object?>> stopGateway(String gatewaySessionId);
}

/// Optional, Host-authoritative Scenario Lab relay surface.
///
/// The four calls are request/response only. In particular, commands and
/// capture upload grants must never be carried by workspace notifications or
/// any other broadcast channel.
abstract interface class StudioHostLabRelayClient {
  Future<StudioLabRelayDescription> describeLabRelay(
    StudioLabRelayRunBinding binding,
  );

  Future<ScenarioLabRelayHelloAcknowledgement> submitLabRelayHello(
    ScenarioLabRelayHelloSubmission submission,
  );

  Future<ScenarioLabRelayPollResponse> nextLabRelayCommand(
    ScenarioLabRelayPollRequest request,
  );

  Future<ScenarioLabRelayResultAcknowledgement> submitLabRelayResult(
    ScenarioLabRelayResultSubmission submission,
  );
}

/// Optional Host-authoritative Scenario Lab run lifecycle surface.
///
/// Every request and response is a closed public contract. Relay commands,
/// upload grants and process authority are deliberately absent.
abstract interface class StudioHostScenarioLabRunClient {
  Future<ScenarioLabRunSnapshot> startScenarioLabRun(
    ScenarioLabRunStartRequest request,
  );

  Future<ScenarioLabRunSnapshot> getScenarioLabRun(
    ScenarioLabRunReference reference,
  );

  Future<ScenarioLabRunSnapshot> cancelScenarioLabRun(
    ScenarioLabRunReference reference,
  );

  Future<ScenarioLabRunObservation> reattachScenarioLabRun(
    ScenarioLabRunObserveRequest request,
  );
}

/// Optional Host-authoritative human-review surface for one terminal Lab run.
///
/// The capability is all-or-none: implementations expose the complete public
/// quintet and callers fence every operation to an exact run-result digest.
abstract interface class StudioHostScenarioQualityClient {
  Future<ScenarioQualityDescribeResult> describeScenarioQuality(
    ScenarioQualityDescribeRequest request,
  );

  Future<ScenarioQualityReviewOpenResult> openScenarioQualityReview(
    ScenarioQualityReviewOpenRequest request,
  );

  Future<ScenarioQualityDecisionGrant> grantScenarioQualityDecision(
    ScenarioQualityDecisionGrantRequest request,
  );

  Future<ScenarioQualityDecisionAppendResult> appendScenarioQualityDecision(
    ScenarioQualityDecisionAppendRequest request,
  );

  Future<ScenarioQualityDecisionView> getScenarioQualityDecision(
    ScenarioQualityDecisionGetRequest request,
  );
}

/// HTTP resource validation paired with the Quality RPC quintet.
///
/// Handles remain transport-private. The controller addresses resources by
/// descriptor digest and receives only validated leases or public provenance
/// documents.
abstract interface class StudioHostScenarioQualityResourceClient {
  Future<Object> readScenarioQualityReviewProvenance({
    required ResourceHandle handle,
    required ScenarioQualityReviewProvenanceKind kind,
    required Digest expectedDigest,
  });

  Future<StudioResourceLease> openScenarioQualityReviewImage({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  });

  Future<void> validateScenarioQualityReviewArtifact({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  });
}

/// Raw JSON-RPC failure without the untrusted human-readable message.
///
/// Quality recognizes only its reserved error code. All other callers retain
/// the numeric code and structured data without parsing message text.
final class StudioHostJsonRpcFailure implements Exception {
  const StudioHostJsonRpcFailure({required this.code, required this.data});

  final int code;
  final Object? data;

  @override
  String toString() => 'StudioHostJsonRpcFailure($code)';
}

/// Optional resource surface implemented by transports that can validate and
/// lease Host-owned bytes for browser rendering.
///
/// The Studio must never put a raw [ResourceHandle.uri] into an image element:
/// the transport first validates origin, purpose, media type, byte length and
/// digest, then returns a short-lived local URI. Callers own the returned lease
/// and must release it when the component is replaced or disposed.
abstract interface class StudioHostResourceClient {
  Future<StudioResourceLease> openVisualArtifact(ResourceHandle handle);
}

final class StudioResourceLease {
  StudioResourceLease({
    required this.uri,
    required this.digest,
    required this.mediaType,
    required this.size,
    required this.releaseCallback,
  });

  final Uri uri;
  final Digest digest;
  final String mediaType;
  final int size;
  final void Function() releaseCallback;
  bool _released = false;

  bool get isReleased => _released;

  void release() {
    if (_released) return;
    _released = true;
    releaseCallback();
  }
}

typedef StudioHostClientFactory = StudioHostClient Function();
