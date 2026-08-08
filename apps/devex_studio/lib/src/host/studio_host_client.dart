import 'package:devex_contracts/devex_contracts.dart';

abstract interface class StudioHostClient {
  Future<WorkspaceSnapshot> openWorkspace();

  Future<WorkspaceSnapshot> refreshWorkspace();

  Future<void> close();
}

/// Optional event surface implemented by transports that can receive Host
/// workspace revision notifications.
abstract interface class StudioHostWorkspaceEvents {
  Stream<void> get workspaceChanges;
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
