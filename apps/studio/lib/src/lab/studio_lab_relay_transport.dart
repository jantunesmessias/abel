import 'package:experience_contracts/experience_contracts.dart';

const String studioLabRelayV1DescribeRpcMethod = 'lab.relay.describe';
const String studioLabRelayV2DescribeRpcMethod = 'lab.relay.v2.describe';

const Set<String> _studioLabRelaySharedRpcMethods = <String>{
  'lab.relay.hello',
  'lab.relay.next',
  'lab.relay.result',
};

/// The byte-compatible relay v1 quartet.
const Set<String> studioLabRelayRpcMethods = <String>{
  studioLabRelayV1DescribeRpcMethod,
  ..._studioLabRelaySharedRpcMethods,
};

/// The gateway-aware describe plus the unchanged v1 relay lifecycle trio.
const Set<String> studioLabRelayV2RpcMethods = <String>{
  studioLabRelayV2DescribeRpcMethod,
  ..._studioLabRelaySharedRpcMethods,
};

const Set<String> _studioLabRelayKnownRpcMethods = <String>{
  studioLabRelayV1DescribeRpcMethod,
  studioLabRelayV2DescribeRpcMethod,
  ..._studioLabRelaySharedRpcMethods,
};

enum StudioLabRelayTransportAvailability { unavailable, v1, v2 }

/// Raised by a concrete Host client when none of the additive relay RPCs is
/// advertised. Controllers map this to an unavailable fallback, not to a
/// protocol or execution failure.
final class StudioLabRelayUnavailable implements Exception {
  const StudioLabRelayUnavailable();

  @override
  String toString() => 'StudioLabRelayUnavailable';
}

/// Raised before transport when a Gateway-bound run cannot use describe v2.
final class StudioLabRelayGatewayV2Required implements Exception {
  const StudioLabRelayGatewayV2Required();

  @override
  String toString() => 'StudioLabRelayGatewayV2Required';
}

/// Immutable, non-secret fence derived from one accepted run snapshot and its
/// exact initial execution binding.
///
/// No target or Gateway origin and no relay nonce can enter this value.
final class StudioLabRelayRunBinding {
  StudioLabRelayRunBinding._({
    required this.runId,
    required this.startRequestDigest,
    required this.runtimeInputs,
    required this.executionBinding,
  }) {
    final launchProfileId = executionBinding.launchProfileId;
    if (launchProfileId == null) {
      throw ArgumentError(
        'Scenario Lab relay requires the exact managed execution binding',
      );
    }
    runtimeInputs.validateAgainst(executionBinding);
  }

  factory StudioLabRelayRunBinding.fromSnapshot({
    required ScenarioLabRunSnapshot snapshot,
    required CatalogManifest catalog,
    required ScenarioLabManifest manifest,
  }) {
    if (snapshot.catalogDigest != catalog.digest ||
        snapshot.scenarioLabManifestDigest != manifest.digest ||
        manifest.catalogDigest != catalog.digest) {
      throw ArgumentError(
        'Scenario Lab relay run does not match the current Catalog generation',
      );
    }
    final runtimeInputs = snapshot.runtimeInputs;
    if (runtimeInputs == null || snapshot.state.isTerminal) {
      throw ArgumentError(
        'Scenario Lab relay requires non-terminal resolved runtime inputs',
      );
    }
    final scripts = manifest.scripts.where(
      (script) =>
          script.id == snapshot.scriptId &&
          script.scenarioId == snapshot.scenarioId,
    );
    if (scripts.length != 1 ||
        scripts.single.steps.isEmpty ||
        scripts.single.steps.first is! ExecutionBindingScenarioScriptStep) {
      throw ArgumentError(
        'Scenario Lab relay script has no exact initial execution binding',
      );
    }
    final bindingId =
        (scripts.single.steps.first as ExecutionBindingScenarioScriptStep)
            .bindingId;
    final bindings = catalog.executionBindings.where(
      (binding) =>
          binding.id == bindingId && binding.scenarioId == snapshot.scenarioId,
    );
    final plans = manifest.plans.where(
      (plan) =>
          plan.scenarioId == snapshot.scenarioId &&
          plan.scriptIds.contains(snapshot.scriptId) &&
          plan.executionBindingIds.contains(bindingId),
    );
    if (bindings.length != 1 || plans.length != 1) {
      throw ArgumentError(
        'Scenario Lab relay binding is not uniquely allowlisted by its plan',
      );
    }
    final binding = bindings.single;
    if (binding.launchProfileId == null) {
      throw ArgumentError(
        'Scenario Lab relay requires a managed launch profile binding',
      );
    }
    return StudioLabRelayRunBinding._(
      runId: snapshot.runId,
      startRequestDigest: snapshot.startRequestDigest,
      runtimeInputs: runtimeInputs,
      executionBinding: binding,
    );
  }

  final ScenarioLabRunId runId;
  final Digest startRequestDigest;
  final ScenarioLabRuntimeInputBinding runtimeInputs;
  final ScenarioExecutionBinding executionBinding;

  ScenarioId get scenarioId => executionBinding.scenarioId;

  bool get requiresGateway => executionBinding.gatewayPresetId != null;

  String get targetId => executionBinding.targetId;

  String get launchProfileId => executionBinding.launchProfileId!;

  late final Digest digest = Digest.semantic(<String, Object?>{
    'runId': runId.value,
    'startRequestDigest': startRequestDigest.value,
    'runtimeInputsDigest': runtimeInputs.digest.value,
    'executionBindingId': executionBinding.id.value,
    'targetId': targetId,
    'launchProfileId': launchProfileId,
    'requiresGateway': requiresGateway,
  });
}

/// Resolves both relay generations as atomic transport surfaces.
///
/// Describe v2 wins whenever advertised with the unchanged hello/next/result
/// trio. A malformed partial generation fails closed. Describe v1 is selected
/// only when v2 is absent and the exact run binding does not require Gateway.
StudioLabRelayTransportAvailability selectStudioLabRelayTransport(
  Set<String> capabilities, {
  bool requiresGateway = false,
}) {
  final present = capabilities.intersection(_studioLabRelayKnownRpcMethods);
  if (present.isEmpty) {
    return StudioLabRelayTransportAvailability.unavailable;
  }
  final hasV1 = capabilities.containsAll(studioLabRelayRpcMethods);
  final hasV2 = capabilities.containsAll(studioLabRelayV2RpcMethods);
  if (!hasV1 && !hasV2) {
    throw const FormatException(
      'Workspace Host exposes an incomplete Scenario Lab relay capability',
    );
  }
  if (hasV2) return StudioLabRelayTransportAvailability.v2;
  if (requiresGateway) throw const StudioLabRelayGatewayV2Required();
  return StudioLabRelayTransportAvailability.v1;
}

/// Closed method/params pair consumed by the browser Host facade.
final class StudioLabRelayDescribeCall {
  const StudioLabRelayDescribeCall._({
    required this.transport,
    required this.method,
    required this.params,
    this.v2Request,
  });

  final StudioLabRelayTransportAvailability transport;
  final String method;
  final Map<String, Object?> params;
  final ScenarioLabRelayDescribeRequestV2? v2Request;
}

StudioLabRelayDescribeCall prepareStudioLabRelayDescribeCall({
  required Set<String> capabilities,
  required StudioLabRelayRunBinding binding,
}) {
  final transport = selectStudioLabRelayTransport(
    capabilities,
    requiresGateway: binding.requiresGateway,
  );
  switch (transport) {
    case StudioLabRelayTransportAvailability.unavailable:
      throw const StudioLabRelayUnavailable();
    case StudioLabRelayTransportAvailability.v1:
      return StudioLabRelayDescribeCall._(
        transport: transport,
        method: studioLabRelayV1DescribeRpcMethod,
        params: <String, Object?>{'runId': binding.runId.value},
      );
    case StudioLabRelayTransportAvailability.v2:
      final request = ScenarioLabRelayDescribeRequestV2(
        runId: binding.runId,
        expectedStartRequestDigest: binding.startRequestDigest,
      );
      return StudioLabRelayDescribeCall._(
        transport: transport,
        method: studioLabRelayV2DescribeRpcMethod,
        params: request.toJson(),
        v2Request: request,
      );
  }
}

/// A validated relay description used only between the Host facade,
/// controller and its single TargetFrame mount.
///
/// Observable controller state exposes [gatewayBound], never the Gateway data
/// origin.
final class StudioLabRelayDescription {
  const StudioLabRelayDescription._({
    required this.transport,
    required this.status,
    required this.digest,
    required this.gatewayBound,
    required Digest bindingDigest,
    this.descriptor,
    Uri? gatewayDataOrigin,
  }) : _privateInputs = (
         bindingDigest: bindingDigest,
         gatewayDataOrigin: gatewayDataOrigin,
       );

  final StudioLabRelayTransportAvailability transport;
  final ScenarioLabRelayDescriptionStatus status;
  final ScenarioLabRelayTargetDescriptor? descriptor;
  final Digest digest;
  final bool gatewayBound;
  final ({Digest bindingDigest, Uri? gatewayDataOrigin}) _privateInputs;

  /// Releases the transport-private launch input only to the exact run fence
  /// that decoded this response. It must never enter observable state, a DOM
  /// attribute, a log record or a caller-supplied URL.
  Uri? gatewayDataOriginFor(StudioLabRelayRunBinding binding) {
    if (_privateInputs.bindingDigest != binding.digest) {
      throw ArgumentError('Scenario Lab relay response binding mismatch');
    }
    return _privateInputs.gatewayDataOrigin;
  }
}

StudioLabRelayDescription decodeStudioLabRelayDescription({
  required Object? value,
  required StudioLabRelayDescribeCall call,
  required StudioLabRelayRunBinding binding,
}) {
  if (call.transport == StudioLabRelayTransportAvailability.v1) {
    if (binding.requiresGateway) {
      throw const StudioLabRelayGatewayV2Required();
    }
    final description = ScenarioLabRelayDescription.fromJson(value);
    if (description.runId != binding.runId) {
      throw const FormatException(
        'Scenario Lab relay description belongs to another run',
      );
    }
    final descriptor = description.descriptor;
    if (descriptor != null) _validateDescriptor(descriptor, binding);
    return StudioLabRelayDescription._(
      transport: call.transport,
      status: description.status,
      descriptor: descriptor,
      digest: description.digest,
      gatewayBound: false,
      bindingDigest: binding.digest,
    );
  }

  if (call.transport != StudioLabRelayTransportAvailability.v2) {
    throw const StudioLabRelayUnavailable();
  }
  final request = call.v2Request;
  if (request == null) {
    throw const FormatException(
      'Scenario Lab relay v2 request fence is unavailable',
    );
  }
  final ScenarioLabRelayDescriptionV2 description;
  try {
    description = ScenarioLabRelayDescriptionV2.fromJson(value);
    description.validateAgainst(request);
  } on ArgumentError {
    throw const FormatException(
      'Scenario Lab relay v2 description crossed its closed fence',
    );
  }
  final descriptor = description.descriptor;
  final runtimeInputs = description.runtimeInputs;
  if (description.status == ScenarioLabRelayDescriptionStatus.ready) {
    if (descriptor == null ||
        runtimeInputs == null ||
        runtimeInputs.digest != binding.runtimeInputs.digest ||
        description.requiresGateway != binding.requiresGateway) {
      throw const FormatException(
        'Scenario Lab relay v2 runtime binding mismatch',
      );
    }
    _validateDescriptor(descriptor, binding);
  }
  return StudioLabRelayDescription._(
    transport: call.transport,
    status: description.status,
    descriptor: descriptor,
    digest: description.digest,
    gatewayBound:
        description.status == ScenarioLabRelayDescriptionStatus.ready &&
        description.requiresGateway,
    bindingDigest: binding.digest,
    gatewayDataOrigin: description.gatewayDataOrigin,
  );
}

void _validateDescriptor(
  ScenarioLabRelayTargetDescriptor descriptor,
  StudioLabRelayRunBinding binding,
) {
  if (descriptor.runId != binding.runId ||
      descriptor.targetId != binding.targetId ||
      descriptor.launchProfileId != binding.launchProfileId ||
      descriptor.targetId != binding.runtimeInputs.executionTargetId) {
    throw const FormatException(
      'Scenario Lab relay target descriptor crossed its run binding',
    );
  }
}
