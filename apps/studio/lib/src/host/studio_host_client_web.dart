import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../authoring/studio_experience_authoring_transport.dart';
import '../lab/studio_lab_relay_transport.dart';
import '../lab/studio_scenario_lab_run_transport.dart';
import '../quality/studio_scenario_quality_transport.dart';
import 'studio_bootstrap_transport.dart';
import 'studio_experience_transport.dart';
import 'studio_host_client.dart';

final class BrowserStudioHostClient
    implements
        StudioHostClient,
        StudioHostContentClient,
        StudioHostExperienceClient,
        StudioHostWorkspaceEvents,
        StudioHostExperienceAuthoringClient,
        StudioHostContextBuilderClient,
        StudioHostPreviewClient,
        StudioHostSessionClient,
        StudioHostGatewayClient,
        StudioHostLabRelayClient,
        StudioHostScenarioLabRunClient,
        StudioHostScenarioQualityClient,
        StudioHostScenarioQualityResourceClient,
        StudioHostResourceClient {
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Uri? _hostOrigin;
  Future<void> _serial = Future<void>.value();
  final Map<String, Completer<Object?>> _pending =
      <String, Completer<Object?>>{};
  final StreamController<void> _workspaceChanges =
      StreamController<void>.broadcast();
  var _nextRequest = 1;
  var _closed = false;
  Set<String> _capabilities = const <String>{};
  final Map<String, int> _labRelayGenerations = <String, int>{};
  final Map<String, Digest> _labRelayBindingDigests = <String, Digest>{};
  final Map<String, Digest> _labRelayReadyDescriptionDigests =
      <String, Digest>{};
  final Map<String, Digest> _labRelayDescriptorDigests = <String, Digest>{};
  final Map<String, AppAdapterRelayNonce> _labRelayNonces =
      <String, AppAdapterRelayNonce>{};
  final Set<String> _invalidatedLabRelayRuns = <String>{};
  var _connectionGeneration = 0;

  @override
  Stream<void> get workspaceChanges => _workspaceChanges.stream;

  @override
  Future<ContextBuilderDescription> describeContextBuilder() =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('context.describe');
        return ContextBuilderDescription.fromJson(
          await _call('context.describe', const <String, Object?>{}),
        );
      });

  @override
  Future<ContextBuildResult> buildContext(ContextBuildRequest request) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('context.build');
        return ContextBuildResult.fromJson(
          await _call('context.build', request.toJson()),
        );
      });

  @override
  Future<ExperienceAuthoringDescription> describeExperienceAuthoring(
    ExperienceAuthoringDescribeRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.describe,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.describe,
    decode: (value) =>
        decodeStudioExperienceAuthoringDescription(value, request),
  );

  @override
  Future<ExperienceAuthoringSubjectHeadResult> getExperienceAuthoringHead(
    ExperienceAuthoringSubjectHeadRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.getSubjectHead,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.getSubjectHead,
    decode: (value) => decodeStudioExperienceAuthoringHead(value, request),
  );

  @override
  Future<LayoutDraftOpenResult> openExperienceLayoutDraft(
    LayoutDraftOpenRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.openDraft,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.openDraft,
    decode: (value) => decodeStudioExperienceLayoutDraftOpen(value, request),
  );

  @override
  Future<LayoutDraftGetResult> getExperienceLayoutDraft(
    LayoutDraftGetRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.getDraft,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.getDraft,
    decode: (value) => decodeStudioExperienceLayoutDraftGet(value, request),
  );

  @override
  Future<AuthoringGrantResult> requestExperienceAuthoringGrant(
    AuthoringGrantRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.requestGrant,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: request.operation,
    decode: (value) => decodeStudioExperienceAuthoringGrant(value, request),
  );

  @override
  Future<LayoutDraftMutationResult> mutateExperienceLayoutDraft(
    LayoutDraftMutationRequest request, {
    required AuthoringSubjectRef subject,
  }) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.mutateDraft,
    params: request.toJson(),
    requestId: request.requestId,
    subject: subject,
    operation: switch (request.mutation) {
      LayoutDraftMutation.applyMove => AuthoringOperation.moveNode,
      LayoutDraftMutation.undo => AuthoringOperation.undo,
      LayoutDraftMutation.redo => AuthoringOperation.redo,
      LayoutDraftMutation.reset => AuthoringOperation.reset,
    },
    mutation: request.mutation,
    // The controller owns the previous draft and performs the cross-revision
    // validation immediately after this intrinsic closed-codec decode.
    decode: LayoutDraftMutationResult.fromJson,
  );

  @override
  Future<ExperienceReviewPrepareResult> prepareExperienceReview(
    ExperienceReviewPrepareRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.prepareReview,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.prepareReview,
    // The controller owns the exact draft required for cross-validation.
    decode: ExperienceReviewPrepareResult.fromJson,
  );

  @override
  Future<ExperienceChangeSetGetResult> getExperienceChangeSet(
    ExperienceChangeSetGetRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.getChangeSet,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.getChangeSet,
    decode: (value) => decodeStudioExperienceChangeSet(value, request),
  );

  @override
  Future<ExperienceReviewGetResult> getExperienceReview(
    ExperienceReviewGetRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.getReview,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.getReview,
    decode: (value) => decodeStudioExperienceReview(value, request),
  );

  @override
  Future<ExperienceReviewActionResult> applyExperienceReviewAction(
    ExperienceReviewActionRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.reviewAction,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.fence.subject,
    operation: request.operation,
    // The controller owns the previous packet and ChangeSet required for the
    // append-only history validation.
    decode: ExperienceReviewActionResult.fromJson,
  );

  @override
  Future<AuthoringGrantResult> requestExperienceDecisionGrant(
    ExperienceReviewDecisionGrantRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.requestDecisionGrant,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.decideReview,
    decode: (value) => decodeStudioExperienceAuthoringGrant(value, request),
  );

  @override
  Future<LayoutDraftAbandonResult> abandonExperienceLayoutDraft(
    LayoutDraftAbandonRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.abandonDraft,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.abandonDraft,
    decode: (value) => decodeStudioExperienceLayoutDraftAbandon(value, request),
  );

  @override
  Future<AuthoringGrantResult> requestExperiencePromotionGrant(
    ExperiencePromotionGrantRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.requestPromotionGrant,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.promote,
    decode: (value) => decodeStudioExperienceAuthoringGrant(value, request),
  );

  @override
  Future<ExperiencePromotionApplyResult> applyExperiencePromotion(
    ExperiencePromotionApplyRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.applyPromotion,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.promote,
    decode: (value) => decodeStudioExperiencePromotionApply(value, request),
  );

  @override
  Future<ExperiencePromotionGetResult> getExperiencePromotion(
    ExperiencePromotionGetRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.getPromotion,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.getPromotion,
    decode: (value) => decodeStudioExperiencePromotion(value, request),
  );

  @override
  Future<ExperiencePromotionHistoryResult> getExperiencePromotionHistory(
    ExperiencePromotionHistoryRequest request,
  ) => _experienceAuthoringCall(
    method: ExperienceAuthoringRpcMethod.getPromotionHistory,
    params: request.toJson(),
    requestId: request.requestId,
    subject: request.subject,
    operation: AuthoringOperation.getPromotionHistory,
    decode: (value) => decodeStudioExperiencePromotionHistory(value, request),
  );

  @override
  Future<ScenarioQualityDescribeResult> describeScenarioQuality(
    ScenarioQualityDescribeRequest request,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioQualityTransport();
    try {
      return decodeStudioScenarioQualityDescribe(
        await _call(
          'quality.describe',
          encodeStudioScenarioQualityDescribe(request),
        ),
        request,
      );
    } on StudioHostJsonRpcFailure catch (failure) {
      _throwScenarioQualityFailure(
        failure,
        operation: ScenarioQualityDecisionOperation.describe,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
      );
    }
  });

  @override
  Future<ScenarioQualityReviewOpenResult> openScenarioQualityReview(
    ScenarioQualityReviewOpenRequest request,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioQualityTransport();
    try {
      return decodeStudioScenarioQualityOpen(
        await _call('quality.open', encodeStudioScenarioQualityOpen(request)),
        request,
      );
    } on StudioHostJsonRpcFailure catch (failure) {
      _throwScenarioQualityFailure(
        failure,
        operation: ScenarioQualityDecisionOperation.open,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
      );
    }
  });

  @override
  Future<ScenarioQualityDecisionGrant> grantScenarioQualityDecision(
    ScenarioQualityDecisionGrantRequest request,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioQualityTransport();
    try {
      return decodeStudioScenarioQualityGrant(
        await _call(
          'quality.decision.grant',
          encodeStudioScenarioQualityGrant(request),
        ),
        request,
      );
    } on StudioHostJsonRpcFailure catch (failure) {
      _throwScenarioQualityFailure(
        failure,
        operation: ScenarioQualityDecisionOperation.grant,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
      );
    }
  });

  @override
  Future<ScenarioQualityDecisionAppendResult> appendScenarioQualityDecision(
    ScenarioQualityDecisionAppendRequest request,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioQualityTransport();
    try {
      return decodeStudioScenarioQualityAppend(
        await _call(
          'quality.decision.append',
          encodeStudioScenarioQualityAppend(request),
        ),
        request,
      );
    } on StudioHostJsonRpcFailure catch (failure) {
      _throwScenarioQualityFailure(
        failure,
        operation: ScenarioQualityDecisionOperation.append,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
        requestId: request.requestId,
      );
    }
  });

  @override
  Future<ScenarioQualityDecisionView> getScenarioQualityDecision(
    ScenarioQualityDecisionGetRequest request,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioQualityTransport();
    try {
      return decodeStudioScenarioQualityGet(
        await _call(
          'quality.decision.get',
          encodeStudioScenarioQualityGet(request),
        ),
        request,
      );
    } on StudioHostJsonRpcFailure catch (failure) {
      _throwScenarioQualityFailure(
        failure,
        operation: ScenarioQualityDecisionOperation.get,
        runId: request.runId,
        expectedRunResultDigest: request.expectedRunResultDigest,
      );
    }
  });

  @override
  Future<ScenarioLabRunSnapshot> startScenarioLabRun(
    ScenarioLabRunStartRequest request,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioLabRunTransport();
    return decodeStudioScenarioLabRunStart(
      await _call('lab.start', encodeStudioScenarioLabRunStart(request)),
      request,
    );
  });

  @override
  Future<ScenarioLabRunSnapshot> getScenarioLabRun(
    ScenarioLabRunReference reference,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioLabRunTransport();
    return decodeStudioScenarioLabRunReferenceResponse(
      await _call('lab.get', encodeStudioScenarioLabRunReference(reference)),
      reference,
    );
  });

  @override
  Future<ScenarioLabRunSnapshot> cancelScenarioLabRun(
    ScenarioLabRunReference reference,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioLabRunTransport();
    return decodeStudioScenarioLabRunReferenceResponse(
      await _call('lab.cancel', encodeStudioScenarioLabRunReference(reference)),
      reference,
    );
  });

  @override
  Future<ScenarioLabRunObservation> reattachScenarioLabRun(
    ScenarioLabRunObserveRequest request,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireScenarioLabRunTransport();
    return decodeStudioScenarioLabRunObservation(
      await _call('lab.reattach', encodeStudioScenarioLabRunObserve(request)),
      request,
    );
  });

  @override
  Future<StudioLabRelayDescription> describeLabRelay(
    StudioLabRelayRunBinding binding,
  ) => _serialized(() async {
    await _ensureConnected();
    final call = prepareStudioLabRelayDescribeCall(
      capabilities: _capabilities,
      binding: binding,
    );
    final key = binding.runId.value;
    if (_invalidatedLabRelayRuns.contains(key)) {
      throw StateError(
        'Scenario Lab relay cannot reconnect after transport loss',
      );
    }
    final previousBinding = _labRelayBindingDigests[key];
    if (previousBinding != null && previousBinding != binding.digest) {
      throw const FormatException(
        'Scenario Lab relay run binding changed on one Host connection',
      );
    }
    final generation = _labRelayGenerations.putIfAbsent(
      key,
      () => _connectionGeneration,
    );
    if (generation != _connectionGeneration) {
      throw StateError('Scenario Lab relay belongs to another Host connection');
    }
    _labRelayBindingDigests[key] = binding.digest;
    final description = decodeStudioLabRelayDescription(
      value: await _call(call.method, call.params),
      call: call,
      binding: binding,
    );
    if (description.descriptor case final descriptor?) {
      final previous = _labRelayDescriptorDigests[key];
      if (previous != null && previous != descriptor.digest) {
        throw const FormatException(
          'Scenario Lab relay target changed after authorization',
        );
      }
      final previousDescription = _labRelayReadyDescriptionDigests[key];
      if (previousDescription != null &&
          previousDescription != description.digest) {
        throw const FormatException(
          'Scenario Lab relay ready description changed after authorization',
        );
      }
      _labRelayReadyDescriptionDigests[key] = description.digest;
      _labRelayDescriptorDigests[key] = descriptor.digest;
      _labRelayNonces[key] = descriptor.nonce;
    }
    return description;
  });

  @override
  Future<ScenarioLabRelayHelloAcknowledgement> submitLabRelayHello(
    ScenarioLabRelayHelloSubmission submission,
  ) => _serialized(() async {
    _requireLabRelayBinding(
      submission.hello.runId,
      submission.descriptorDigest,
    );
    if (_labRelayNonces[submission.hello.runId.value] !=
        submission.hello.nonce) {
      throw const FormatException(
        'Scenario Lab relay hello nonce is inconsistent',
      );
    }
    final acknowledgement = ScenarioLabRelayHelloAcknowledgement.fromJson(
      await _call('lab.relay.hello', submission.toJson()),
    );
    if (acknowledgement.runId != submission.hello.runId ||
        acknowledgement.descriptorDigest != submission.descriptorDigest ||
        acknowledgement.acceptedHelloDigest != submission.hello.digest) {
      throw const FormatException(
        'Scenario Lab relay hello acknowledgement is inconsistent',
      );
    }
    return acknowledgement;
  });

  @override
  Future<ScenarioLabRelayPollResponse> nextLabRelayCommand(
    ScenarioLabRelayPollRequest request,
  ) async {
    // Do not hold the client's general serial queue during a long poll.
    final generation = await _serialized(() async {
      _requireLabRelayBinding(request.runId, request.descriptorDigest);
      return _connectionGeneration;
    });
    final response = ScenarioLabRelayPollResponse.fromJson(
      await _callOnRelayConnection(
        'lab.relay.next',
        request.toJson(),
        generation,
      ),
    );
    if (_connectionGeneration != generation ||
        response.runId != request.runId ||
        response.descriptorDigest != request.descriptorDigest ||
        response.afterSequence != request.afterSequence ||
        (response.command != null &&
            response.command!.nonce != _labRelayNonces[request.runId.value])) {
      throw const FormatException(
        'Scenario Lab relay poll response is inconsistent',
      );
    }
    return response;
  }

  @override
  Future<ScenarioLabRelayResultAcknowledgement> submitLabRelayResult(
    ScenarioLabRelayResultSubmission submission,
  ) async {
    // A result completes the Host-owned command currently holding the script
    // deadline. Validate and snapshot synchronously, then do not leave its
    // network submission behind unrelated workspace/run reads in `_serial`.
    _requireLabRelayBinding(
      submission.result.runId,
      submission.descriptorDigest,
    );
    if (_labRelayNonces[submission.result.runId.value] !=
        submission.result.nonce) {
      throw const FormatException(
        'Scenario Lab relay result nonce is inconsistent',
      );
    }
    final generation = _connectionGeneration;
    final acknowledgement = ScenarioLabRelayResultAcknowledgement.fromJson(
      await _callOnRelayConnection(
        'lab.relay.result',
        submission.toJson(),
        generation,
      ),
    );
    if (_connectionGeneration != generation ||
        acknowledgement.runId != submission.result.runId ||
        acknowledgement.descriptorDigest != submission.descriptorDigest ||
        acknowledgement.acceptedResultDigest !=
            submission.result.resultDigest) {
      throw const FormatException(
        'Scenario Lab relay result acknowledgement is inconsistent',
      );
    }
    return acknowledgement;
  }

  @override
  Future<SessionSnapshot> startSession({
    required String launchProfileId,
    required Uri targetOrigin,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('session.start');
    return SessionSnapshot.fromJson(
      await _call('session.start', <String, Object?>{
        'launchProfileId': launchProfileId,
        'targetOrigin': targetOrigin.toString(),
      }),
    );
  });

  @override
  Future<SessionSnapshot> sessionStatus(String sessionId) =>
      _sessionCall('session.get', sessionId);

  @override
  Future<SessionSnapshot> resetSession(String sessionId) =>
      _sessionCall('session.reset', sessionId);

  @override
  Future<SessionSnapshot> stopSession(String sessionId) =>
      _sessionCall('session.stop', sessionId);

  @override
  Future<SessionSnapshot> cancelSession(String sessionId, {String? reason}) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('session.cancel');
        return SessionSnapshot.fromJson(
          await _call('session.cancel', <String, Object?>{
            'sessionId': sessionId,
            'reason': ?reason,
          }),
        );
      });

  @override
  Future<Map<String, Object?>> startGateway({
    required String ownerSessionId,
    required Digest planArtifactDigest,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('gateway.start');
    return _object(
      await _call('gateway.start', <String, Object?>{
        'ownerSessionId': ownerSessionId,
        'planArtifactDigest': planArtifactDigest.value,
      }),
      'GatewaySession',
    );
  });

  @override
  Future<List<GatewayPlanArtifactDescriptor>> gatewayPresets() =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('gateway.presets');
        final value = await _call('gateway.presets', const <String, Object?>{});
        if (value is! List<Object?>) {
          throw const FormatException('Gateway presets must be a list');
        }
        return value
            .map(GatewayPlanArtifactDescriptor.fromJson)
            .toList(growable: false);
      });

  @override
  Future<Map<String, Object?>> gatewayStatus(String gatewaySessionId) =>
      _gatewayCall('gateway.status', gatewaySessionId);

  @override
  Future<List<Map<String, Object?>>> gatewayTraffic(
    String gatewaySessionId, {
    int afterSequence = 0,
    int limit = 100,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('gateway.traffic');
    final value = await _call('gateway.traffic', <String, Object?>{
      'gatewaySessionId': gatewaySessionId,
      'afterSequence': afterSequence,
      'limit': limit,
    });
    if (value is! List<Object?> ||
        !value.every((item) => item is Map<String, Object?>)) {
      throw const FormatException('Gateway traffic must be a list of objects');
    }
    return value.cast<Map<String, Object?>>();
  });

  @override
  Future<Map<String, Object?>> resetGateway(String gatewaySessionId) =>
      _gatewayCall('gateway.reset', gatewaySessionId);

  @override
  Future<Map<String, Object?>> stopGateway(String gatewaySessionId) =>
      _gatewayCall('gateway.stop', gatewaySessionId);

  @override
  Future<Map<String, Object?>> collectPreview({
    required String applicationId,
    String? scenarioId,
    String? variantId,
    required bool syntheticDataConfirmed,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('preview.collect');
    return _object(
      await _call('preview.collect', <String, Object?>{
        'applicationId': applicationId,
        'scenarioId': ?scenarioId,
        'variantId': ?variantId,
        'syntheticDataConfirmed': syntheticDataConfirmed,
      }),
      'PreviewCollectionOperation',
    );
  });

  @override
  Future<Map<String, Object?>> previewStatus(String operationId) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('preview.status');
        return _object(
          await _call('preview.status', <String, Object?>{
            'operationId': operationId,
          }),
          'PreviewCollectionOperation',
        );
      });

  @override
  Future<Map<String, Object?>> cancelPreview(String operationId) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('preview.cancel');
        return _object(
          await _call('preview.cancel', <String, Object?>{
            'operationId': operationId,
          }),
          'PreviewCollectionOperation',
        );
      });

  @override
  Future<StudioResourceLease> openVisualArtifact(ResourceHandle handle) =>
      _serialized(() async {
        await _ensureConnected();
        final hostOrigin = _hostOrigin!;
        if (handle.purpose != 'visual-artifact' ||
            handle.mediaType != 'image/png' ||
            handle.uri.origin != hostOrigin.origin ||
            handle.size <= 0 ||
            handle.size > 16 * 1024 * 1024 ||
            handle.isExpiredAt(DateTime.now().toUtc())) {
          throw const FormatException(
            'Visual artifact resource handle is not allowed',
          );
        }
        final response = await web.window
            .fetch(
              handle.uri.toString().toJS,
              web.RequestInit(
                method: 'GET',
                cache: 'no-store',
                credentials: 'omit',
                mode: 'cors',
                redirect: 'error',
                referrerPolicy: 'no-referrer',
              ),
            )
            .toDart;
        final declaredLength = int.tryParse(
          response.headers.get('content-length') ?? '',
        );
        if (!response.ok ||
            declaredLength != handle.size ||
            response.headers.get('content-type')?.split(';').first !=
                handle.mediaType) {
          throw StateError('Visual artifact resource response was rejected');
        }
        final arrayBuffer = await response.arrayBuffer().toDart;
        final bytes = arrayBuffer.toDart.asUint8List();
        if (bytes.length != handle.size ||
            Digest.bytes(bytes) != handle.digest ||
            handle.isExpiredAt(DateTime.now().toUtc())) {
          throw const FormatException(
            'Visual artifact resource digest mismatch',
          );
        }
        final blob = web.Blob(
          <JSAny>[arrayBuffer].toJS,
          web.BlobPropertyBag(type: handle.mediaType),
        );
        final localUri = Uri.parse(web.URL.createObjectURL(blob));
        return StudioResourceLease(
          uri: localUri,
          digest: handle.digest,
          mediaType: handle.mediaType,
          size: handle.size,
          releaseCallback: () => web.URL.revokeObjectURL(localUri.toString()),
        );
      });

  @override
  Future<Object> readScenarioQualityReviewProvenance({
    required ResourceHandle handle,
    required ScenarioQualityReviewProvenanceKind kind,
    required Digest expectedDigest,
  }) => _serialized(() async {
    await _ensureConnected();
    if (handle.digest != expectedDigest) {
      throw const FormatException(
        'Scenario Quality provenance handle crossed its descriptor fence',
      );
    }
    final bytes = await _fetchScenarioQualityResource(
      handle,
      purpose: 'scenario-quality-review-provenance',
      mediaType: 'application/json',
      maxBytes: 64 * 1024,
    );
    final decoded = jsonDecode(utf8.decode(bytes));
    return switch (kind) {
      ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt =>
        AppAdapterCaptureReceipt.fromJson(
          decoded,
          expectedDigest: expectedDigest,
        ),
      ScenarioQualityReviewProvenanceKind.supplementalArtifactImport =>
        ScenarioLabSupplementalArtifactProvenance.fromJson(
          decoded,
          expectedDigest: expectedDigest,
        ),
    };
  });

  @override
  Future<StudioResourceLease> openScenarioQualityReviewImage({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  }) => _serialized(() async {
    await _ensureConnected();
    _validateScenarioQualityArtifactHandle(handle, descriptor);
    if (descriptor.mediaType != 'image/png') {
      throw const FormatException(
        'Scenario Quality image renderer accepts PNG only',
      );
    }
    final hostOrigin = _hostOrigin!;
    if (handle.uri.origin != hostOrigin.origin ||
        handle.isExpiredAt(DateTime.now().toUtc())) {
      throw const FormatException(
        'Scenario Quality image resource handle is not allowed',
      );
    }
    final response = await web.window
        .fetch(
          handle.uri.toString().toJS,
          web.RequestInit(
            method: 'GET',
            cache: 'no-store',
            credentials: 'omit',
            mode: 'cors',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
          ),
        )
        .toDart;
    final declaredLength = int.tryParse(
      response.headers.get('content-length') ?? '',
    );
    if (!response.ok ||
        declaredLength != handle.size ||
        response.headers.get('content-type')?.split(';').first !=
            handle.mediaType) {
      throw StateError('Scenario Quality image response was rejected');
    }
    final arrayBuffer = await response.arrayBuffer().toDart;
    final bytes = arrayBuffer.toDart.asUint8List();
    if (bytes.length != handle.size ||
        Digest.bytes(bytes) != handle.digest ||
        handle.isExpiredAt(DateTime.now().toUtc())) {
      throw const FormatException(
        'Scenario Quality image resource digest mismatch',
      );
    }
    final blob = web.Blob(
      <JSAny>[arrayBuffer].toJS,
      web.BlobPropertyBag(type: handle.mediaType),
    );
    final localUri = Uri.parse(web.URL.createObjectURL(blob));
    return StudioResourceLease(
      uri: localUri,
      digest: handle.digest,
      mediaType: handle.mediaType,
      size: handle.size,
      releaseCallback: () => web.URL.revokeObjectURL(localUri.toString()),
    );
  });

  @override
  Future<void> validateScenarioQualityReviewArtifact({
    required ResourceHandle handle,
    required ScenarioQualityReviewArtifactDescriptor descriptor,
  }) => _serialized(() async {
    await _ensureConnected();
    _validateScenarioQualityArtifactHandle(handle, descriptor);
    await _fetchScenarioQualityResource(
      handle,
      purpose: 'scenario-quality-review-artifact',
      mediaType: descriptor.mediaType,
      maxBytes: 32 * 1024 * 1024,
    );
  });

  @override
  Future<WorkspaceSnapshot> openWorkspace() => _serialized(() async {
    await _ensureConnected();
    return _openCurrentWorkspace();
  });

  @override
  Future<StudioWorkspaceContent> openContent() => _serialized(() async {
    await _ensureConnected();
    return _openCurrentContent();
  });

  @override
  Future<ExperienceTopologyBundle?> openExperience({
    required CatalogManifest catalog,
  }) => _serialized(() async {
    await _ensureConnected();
    return _openCurrentExperience(catalog);
  });

  Future<ExperienceTopologyBundle?> _openCurrentExperience(
    CatalogManifest catalog,
  ) async {
    final hasDescribe = _capabilities.contains('experience.describe');
    final hasOpen = _capabilities.contains('experience.open');
    if (!hasDescribe && !hasOpen) return null;
    if (!hasDescribe || !hasOpen) {
      throw const FormatException(
        'Workspace Host exposes an incomplete Experience topology capability',
      );
    }
    final description = StudioExperienceDescription.fromJson(
      await _call('experience.describe', const <String, Object?>{}),
      catalog: catalog,
    );
    if (description.isAbsent) return null;
    final opened = StudioExperienceOpen.fromJson(
      await _call('experience.open', <String, Object?>{
        'expectedRevision': description.revision,
        'expectedBundleDigest': description.bundleDigest!.value,
      }),
      description: description,
      hostOrigin: _hostOrigin!,
      nowUtc: DateTime.now().toUtc(),
    );
    final bytes = await _fetchJsonResource(
      opened.resource,
      purpose: 'experience-topology-bundle',
      maxBytes: 64 * 1024 * 1024,
    );
    final bundle = ExperienceTopologyBundle.fromJson(
      jsonDecode(utf8.decode(bytes)),
      catalog: catalog,
    );
    description.validateBundle(bundle);
    return bundle;
  }

  @override
  Future<StudioWorkspaceContent> refreshContent() => _serialized(() async {
    await _ensureConnected();
    await _call('workspace.refresh', const <String, Object?>{});
    return _openCurrentContent();
  });

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() => _serialized(() async {
    await _ensureConnected();
    await _call('workspace.refresh', const <String, Object?>{});
    return _openCurrentWorkspace();
  });

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'Studio disposed');
    _channel = null;
    _labRelayGenerations.clear();
    _labRelayBindingDigests.clear();
    _labRelayReadyDescriptionDigests.clear();
    _labRelayDescriptorDigests.clear();
    _labRelayNonces.clear();
    _invalidatedLabRelayRuns.clear();
    _failPending(StateError('Studio Host client was closed'));
    await _workspaceChanges.close();
  }

  Future<WorkspaceSnapshot> _openCurrentWorkspace() async {
    final description = _object(
      await _call('workspace.describe', const <String, Object?>{}),
      'WorkspaceDescription',
    );
    final revision = description['revision'];
    final snapshotDigest = description['snapshotDigest'];
    if (revision is! int ||
        revision < 1 ||
        snapshotDigest is! String ||
        snapshotDigest.isEmpty) {
      throw const FormatException('WorkspaceDescription is invalid');
    }
    final opened = _object(
      await _call('workspace.open', <String, Object?>{
        'expectedRevision': revision,
      }),
      'WorkspaceOpen',
    );
    if (opened['revision'] != revision ||
        opened['snapshotDigest'] != snapshotDigest) {
      throw const FormatException('Workspace changed while opening snapshot');
    }
    final handle = ResourceHandle.fromJson(opened['resource']);
    final bytes = await _fetchJsonResource(
      handle,
      purpose: 'workspace-snapshot',
      maxBytes: 16 * 1024 * 1024,
    );
    final snapshot = WorkspaceSnapshot.fromJson(jsonDecode(utf8.decode(bytes)));
    if (snapshot.revision != revision ||
        snapshot.digest.value != snapshotDigest) {
      throw const FormatException('Workspace snapshot identity mismatch');
    }
    return snapshot;
  }

  Future<StudioWorkspaceContent> _openCurrentContent() async {
    requireStudioExperienceContentTransport(_capabilities);
    final description = ExperienceContentSetDescription.fromJson(
      await _call('experience.content.describe', const <String, Object?>{}),
    );
    final fenced = StudioExperienceContentOpen.fromRpc(
      description: description,
      openResponse: await _call('experience.content.open', <String, Object?>{
        'expectedRevision': description.identity.revision,
        'catalogDigest': description.identity.catalogDigest.value,
        'contentSetDigest': description.identity.contentSetDigest.value,
      }),
      hostOrigin: _hostOrigin!,
      nowUtc: DateTime.now().toUtc(),
    );
    final opened = fenced.opened;
    final pending = <Future<List<int>>>[
      _fetchJsonResource(
        opened.workspaceSnapshot,
        purpose: 'workspace-snapshot',
        maxBytes: 16 * 1024 * 1024,
      ),
      if (opened.experienceTopologyBundle case final handle?)
        _fetchJsonResource(
          handle,
          purpose: 'experience-topology-bundle',
          maxBytes: 64 * 1024 * 1024,
        ),
      if (opened.scenarioFacetManifest case final handle?)
        _fetchJsonResource(
          handle,
          purpose: 'scenario-facet-manifest',
          maxBytes: 64 * 1024 * 1024,
        ),
      if (opened.scenarioLabManifest case final handle?)
        _fetchJsonResource(
          handle,
          purpose: 'scenario-lab-manifest',
          maxBytes: 64 * 1024 * 1024,
        ),
      if (opened.motionManifest case final handle?)
        _fetchJsonResource(
          handle,
          purpose: 'motion-manifest',
          maxBytes: 64 * 1024 * 1024,
        ),
    ];
    final resources = await Future.wait(pending);
    var index = 0;
    final snapshotBytes = resources[index++];
    final topologyBytes = opened.experienceTopologyBundle == null
        ? null
        : resources[index++];
    final facetsBytes = opened.scenarioFacetManifest == null
        ? null
        : resources[index++];
    final labBytes = opened.scenarioLabManifest == null
        ? null
        : resources[index++];
    final motionBytes = opened.motionManifest == null
        ? null
        : resources[index++];
    return fenced.decode(
      workspaceSnapshotBytes: snapshotBytes,
      experienceTopologyBundleBytes: topologyBytes,
      scenarioFacetManifestBytes: facetsBytes,
      scenarioLabManifestBytes: labBytes,
      motionManifestBytes: motionBytes,
    );
  }

  Future<List<int>> _fetchJsonResource(
    ResourceHandle handle, {
    required String purpose,
    required int maxBytes,
  }) async {
    final hostOrigin = _hostOrigin!;
    if (handle.purpose != purpose ||
        handle.mediaType != 'application/json' ||
        handle.uri.origin != hostOrigin.origin ||
        handle.size <= 0 ||
        handle.size > maxBytes ||
        handle.isExpiredAt(DateTime.now().toUtc())) {
      throw FormatException('$purpose resource handle is not allowed');
    }
    final response = await web.window
        .fetch(
          handle.uri.toString().toJS,
          web.RequestInit(
            method: 'GET',
            cache: 'no-store',
            credentials: 'omit',
            mode: 'cors',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
          ),
        )
        .toDart;
    final declaredLength = int.tryParse(
      response.headers.get('content-length') ?? '',
    );
    if (!response.ok ||
        declaredLength != handle.size ||
        response.headers.get('content-type')?.split(';').first !=
            'application/json') {
      throw StateError('$purpose resource response was rejected');
    }
    final arrayBuffer = await response.arrayBuffer().toDart;
    final bytes = arrayBuffer.toDart.asUint8List();
    if (bytes.length != handle.size ||
        Digest.bytes(bytes) != handle.digest ||
        handle.isExpiredAt(DateTime.now().toUtc())) {
      throw FormatException('$purpose resource digest mismatch');
    }
    return bytes;
  }

  void _validateScenarioQualityArtifactHandle(
    ResourceHandle handle,
    ScenarioQualityReviewArtifactDescriptor descriptor,
  ) {
    if (handle.purpose != 'scenario-quality-review-artifact' ||
        handle.digest != descriptor.artifactDigest ||
        handle.mediaType != descriptor.mediaType ||
        handle.size != descriptor.size ||
        handle.size < 1 ||
        handle.size > 32 * 1024 * 1024) {
      throw const FormatException(
        'Scenario Quality artifact handle crossed its descriptor fence',
      );
    }
  }

  Future<List<int>> _fetchScenarioQualityResource(
    ResourceHandle handle, {
    required String purpose,
    required String mediaType,
    required int maxBytes,
  }) async {
    final hostOrigin = _hostOrigin!;
    if (handle.purpose != purpose ||
        handle.mediaType != mediaType ||
        handle.uri.origin != hostOrigin.origin ||
        handle.size < 1 ||
        handle.size > maxBytes ||
        handle.isExpiredAt(DateTime.now().toUtc())) {
      throw const FormatException(
        'Scenario Quality resource handle is not allowed',
      );
    }
    final response = await web.window
        .fetch(
          handle.uri.toString().toJS,
          web.RequestInit(
            method: 'GET',
            cache: 'no-store',
            credentials: 'omit',
            mode: 'cors',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
          ),
        )
        .toDart;
    final declaredLength = int.tryParse(
      response.headers.get('content-length') ?? '',
    );
    if (!response.ok ||
        declaredLength != handle.size ||
        response.headers.get('content-type')?.split(';').first != mediaType) {
      throw StateError('Scenario Quality resource response was rejected');
    }
    final arrayBuffer = await response.arrayBuffer().toDart;
    final bytes = arrayBuffer.toDart.asUint8List();
    if (bytes.length != handle.size ||
        Digest.bytes(bytes) != handle.digest ||
        handle.isExpiredAt(DateTime.now().toUtc())) {
      throw const FormatException('Scenario Quality resource digest mismatch');
    }
    return bytes;
  }

  Future<void> _ensureConnected() async {
    if (_closed) throw StateError('Studio Host client is closed');
    if (_channel != null) return;
    const configuredBootstrapUrl = String.fromEnvironment(
      studioBootstrapUrlEnvironmentKey,
    );
    final bootstrapUri = resolveStudioBootstrapUri(configuredBootstrapUrl);
    final externalBootstrap = bootstrapUri.isAbsolute;
    late final web.Response response;
    try {
      response = await web.window
          .fetch(
            bootstrapUri.toString().toJS,
            web.RequestInit(
              method: 'GET',
              cache: 'no-store',
              credentials: externalBootstrap ? 'omit' : 'same-origin',
              mode: externalBootstrap ? 'cors' : 'same-origin',
              redirect: 'error',
              referrerPolicy: 'no-referrer',
            ),
          )
          .toDart;
    } on Object {
      throw const StudioBootstrapException(
        'Não foi possível acessar o bootstrap do Workspace Host. Confirme que '
        '`workspace dev` está em execução e tente novamente.',
      );
    }
    final body = (await response.text().toDart).toDart;
    final bootstrap = decodeStudioBootstrapResponse(
      statusCode: response.status,
      contentType: response.headers.get('content-type'),
      body: body,
    );
    final unknown = bootstrap.keys.toSet().difference(const <String>{
      'schemaVersion',
      'protocolVersion',
      'hostOrigin',
      'rpcPath',
      'sessionToken',
      'effectiveKitManifest',
    });
    if (unknown.isNotEmpty ||
        bootstrap['schemaVersion'] != 1 ||
        bootstrap['protocolVersion'] != 1 ||
        bootstrap['rpcPath'] != '/rpc' ||
        bootstrap['hostOrigin'] is! String ||
        bootstrap['sessionToken'] is! String ||
        (bootstrap['sessionToken']! as String).length < 32) {
      throw const FormatException('Abel Studio bootstrap is invalid');
    }
    EffectiveKitManifest.fromJson(bootstrap['effectiveKitManifest']);
    final hostOrigin = Uri.parse(bootstrap['hostOrigin']! as String);
    if (hostOrigin.scheme != 'http' ||
        hostOrigin.host.isEmpty ||
        hostOrigin.path.isNotEmpty ||
        !_loopbackHost(hostOrigin.host)) {
      throw const FormatException('Workspace Host origin is not loopback HTTP');
    }
    final sessionToken = bootstrap['sessionToken']! as String;
    final rpcUri = hostOrigin.replace(scheme: 'ws', path: '/rpc');
    final channel = WebSocketChannel.connect(rpcUri);
    await channel.ready.timeout(const Duration(seconds: 10));
    _hostOrigin = hostOrigin;
    _channel = channel;
    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) =>
          _onDisconnected(error, stackTrace),
      onDone: () => _onDisconnected(
        StateError('Workspace Host closed the connection'),
        StackTrace.current,
      ),
      cancelOnError: true,
    );
    final initialized = _object(
      await _call('workspace.initialize', <String, Object?>{
        'protocolVersion': 1,
        'sessionToken': sessionToken,
      }),
      'InitializeResponse',
    );
    final capabilities = initialized['capabilities'];
    if (initialized['protocolVersion'] != 1 ||
        capabilities is! List<Object?> ||
        !capabilities.contains('workspace.describe') ||
        !capabilities.contains('workspace.open')) {
      throw const FormatException(
        'Workspace Host lacks workspace capabilities',
      );
    }
    _capabilities = capabilities.whereType<String>().toSet();
    _connectionGeneration += 1;
  }

  Future<Object?> _call(String method, Map<String, Object?> params) async {
    final channel = _channel;
    if (channel == null || _subscription == null) {
      throw StateError('Workspace Host connection is not initialized');
    }
    final requestId = 'studio-${_nextRequest++}';
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    channel.sink.add(
      JsonRpcRequest(method: method, id: requestId, params: params).encode(),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<Object?> _callOnRelayConnection(
    String method,
    Map<String, Object?> params,
    int expectedGeneration,
  ) {
    if (_connectionGeneration != expectedGeneration) {
      throw StateError(
        'Scenario Lab relay cannot continue on a reconnected Host',
      );
    }
    // `_call` captures the channel synchronously before its first suspension;
    // a later disconnect therefore fails this exact pending request.
    return _call(method, params);
  }

  void _onMessage(Object? raw) {
    if (raw is! String || utf8.encode(raw).length > 64 * 1024) {
      _onDisconnected(
        const FormatException('Workspace Host returned an invalid frame'),
        StackTrace.current,
      );
      return;
    }
    final JsonRpcMessage message;
    try {
      message = const JsonRpcCodec().decode(raw);
    } on Object catch (error, stackTrace) {
      _onDisconnected(error, stackTrace);
      return;
    }
    if (message is JsonRpcResponse) {
      final completer = _pending[message.id];
      if (completer == null || completer.isCompleted) return;
      if (message.isSuccess) {
        completer.complete(message.result);
      } else {
        completer.completeError(
          StudioHostJsonRpcFailure(
            code: message.error!.code,
            data: message.error!.data,
          ),
        );
      }
      return;
    }
    if (message is JsonRpcNotification) {
      if (observesExperienceGenerationEvent(
        capabilities: _capabilities,
        method: message.method,
      )) {
        _workspaceChanges.add(null);
      }
    }
  }

  void _onDisconnected(Object error, StackTrace stackTrace) {
    if (_closed || _channel == null) return;
    _channel = null;
    final subscription = _subscription;
    _subscription = null;
    _invalidatedLabRelayRuns.addAll(_labRelayGenerations.keys);
    _labRelayGenerations.clear();
    _labRelayBindingDigests.clear();
    _labRelayReadyDescriptionDigests.clear();
    _labRelayDescriptorDigests.clear();
    _labRelayNonces.clear();
    unawaited(subscription?.cancel());
    _failPending(error, stackTrace);
    _workspaceChanges.addError(error, stackTrace);
  }

  void _failPending(Object error, [StackTrace? stackTrace]) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace ?? StackTrace.current);
      }
    }
    _pending.clear();
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<SessionSnapshot> _sessionCall(String method, String sessionId) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability(method);
        return SessionSnapshot.fromJson(
          await _call(method, <String, Object?>{'sessionId': sessionId}),
        );
      });

  Future<Map<String, Object?>> _gatewayCall(
    String method,
    String gatewaySessionId,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireCapability(method);
    return _object(
      await _call(method, <String, Object?>{
        'gatewaySessionId': gatewaySessionId,
      }),
      'GatewaySession',
    );
  });

  Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }

  bool _loopbackHost(String host) =>
      host == '127.0.0.1' || host == '::1' || host == 'localhost';

  void _requireCapability(String method) {
    if (!_capabilities.contains(method)) {
      throw StateError('Host capability is unavailable: $method');
    }
  }

  void _requireLabRelayTransport() {
    if (selectStudioLabRelayTransport(_capabilities) ==
        StudioLabRelayTransportAvailability.unavailable) {
      throw const StudioLabRelayUnavailable();
    }
  }

  void _requireScenarioLabRunTransport() {
    if (selectStudioScenarioLabRunTransport(_capabilities) ==
        StudioScenarioLabRunTransportAvailability.unavailable) {
      throw const StudioScenarioLabRunUnavailable();
    }
  }

  void _requireScenarioQualityTransport() {
    if (selectStudioScenarioQualityTransport(_capabilities) ==
        StudioScenarioQualityTransportAvailability.unavailable) {
      throw const StudioScenarioQualityUnavailable();
    }
  }

  Future<T> _experienceAuthoringCall<T>({
    required String method,
    required Map<String, Object?> params,
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    LayoutDraftMutation? mutation,
    required T Function(Object? value) decode,
  }) => _serialized(() async {
    await _ensureConnected();
    final call = prepareStudioExperienceAuthoringCall(
      capabilities: _capabilities,
      method: method,
      params: params,
    );
    try {
      return decode(await _call(call.method, call.params));
    } on StudioHostJsonRpcFailure catch (failure) {
      _throwExperienceAuthoringFailure(
        failure,
        requestId: requestId,
        subject: subject,
        operation: operation,
        mutation: mutation,
      );
    }
  });

  Never _throwExperienceAuthoringFailure(
    StudioHostJsonRpcFailure failure, {
    required AuthoringRequestId requestId,
    required AuthoringSubjectRef subject,
    required AuthoringOperation operation,
    LayoutDraftMutation? mutation,
  }) {
    if (failure.code != ExperienceAuthoringError.jsonRpcCode) throw failure;
    throw decodeStudioExperienceAuthoringFailure(
      value: failure.data,
      requestId: requestId,
      subject: subject,
      operation: operation,
      mutation: mutation,
    );
  }

  Never _throwScenarioQualityFailure(
    StudioHostJsonRpcFailure failure, {
    required ScenarioQualityDecisionOperation operation,
    required ScenarioLabRunId runId,
    required Digest expectedRunResultDigest,
    ScenarioQualityDecisionRequestId? requestId,
  }) {
    if (failure.code != ScenarioQualityDecisionError.jsonRpcCode) {
      throw failure;
    }
    throw StudioScenarioQualityDecisionFailure(
      decodeStudioScenarioQualityDecisionError(
        jsonRpcCode: failure.code,
        data: failure.data,
        operation: operation,
        runId: runId,
        expectedRunResultDigest: expectedRunResultDigest,
        requestId: requestId,
      ),
    );
  }

  void _requireLabRelayBinding(
    ScenarioLabRunId runId,
    Digest descriptorDigest,
  ) {
    if (_closed || _channel == null || _subscription == null) {
      throw StateError('Scenario Lab relay Host connection is unavailable');
    }
    _requireLabRelayTransport();
    final key = runId.value;
    if (_invalidatedLabRelayRuns.contains(key) ||
        _labRelayGenerations[key] != _connectionGeneration ||
        _labRelayDescriptorDigests[key] != descriptorDigest) {
      throw StateError(
        'Scenario Lab relay is not bound to this Host connection',
      );
    }
  }
}
