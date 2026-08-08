import 'package:experience_contracts/experience_contracts.dart';

import 'managed_process_scenario_lab_target.dart';
import 'scenario_lab_execution_service.dart';
import 'scenario_lab_relay_broker.dart';
import 'scenario_lab_run_store.dart';

/// One atomically observed Host content generation used to authorize a start.
final class HostScenarioLabContent {
  HostScenarioLabContent({
    required this.identity,
    required this.catalog,
    required this.manifest,
  }) {
    if (identity.catalogDigest != catalog.digest ||
        identity.scenarioLabManifestDigest != manifest.digest ||
        manifest.catalogDigest != catalog.digest) {
      throw ArgumentError('Scenario Lab Host content generation is mixed');
    }
  }

  final ExperienceContentSetIdentity identity;
  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
}

typedef HostScenarioLabContentReader = HostScenarioLabContent Function();

typedef HostScenarioLabResolvedRuntimeInputReader =
    ScenarioLabRuntimeInputBinding? Function(ScenarioLabRunId runId);

typedef HostScenarioLabManagedLaunchContextReader =
    ScenarioLabManagedLaunchContext? Function(ScenarioLabRunId runId);

/// Host-owned typed boundary for run lifecycle and the private iframe relay.
///
/// Run observation is bounded and contains no relay command, nonce or upload
/// grant. Relay traffic is request/response only and never enters Host events.
final class HostScenarioLabService {
  HostScenarioLabService({
    required this.execution,
    required this.readContent,
    required this.relay,
    required this.readResolvedRuntimeInputs,
    required this.readManagedLaunchContext,
  });

  final ScenarioLabExecutionService execution;
  final HostScenarioLabContentReader readContent;
  final ScenarioLabRelayBroker relay;
  final HostScenarioLabResolvedRuntimeInputReader readResolvedRuntimeInputs;
  final HostScenarioLabManagedLaunchContextReader readManagedLaunchContext;
  final Map<String, Digest> _relayDescriptorDigests = <String, Digest>{};

  Map<String, Object?> start(Map<String, Object?> params) {
    final request = _decode(
      () => ScenarioLabRunStartRequest.fromJson(params),
      'Invalid Scenario Lab start request',
    );
    final existing = execution.store.findByRequestId(request.requestId);
    if (existing != null) {
      if (existing.request.digest != request.digest) {
        throw StateError('Scenario Lab request ID is already bound');
      }
      return existing.latestObservable.toJson();
    }
    final content = readContent();
    try {
      return execution
          .start(
            request: request,
            contentSet: content.identity,
            catalog: content.catalog,
            manifest: content.manifest,
          )
          .snapshot
          .toJson();
    } on ScenarioLabRequestConflict {
      throw StateError('Scenario Lab request ID is already bound');
    } on ScenarioLabUnsupportedExecutionPlan catch (error) {
      throw StateError(error.toString());
    } on ArgumentError {
      throw StateError(
        'Scenario Lab content changed or the requested plan is unavailable',
      );
    }
  }

  Map<String, Object?> get(Map<String, Object?> params) {
    final reference = _decode(
      () => ScenarioLabRunReference.fromJson(params),
      'Invalid Scenario Lab run reference',
    );
    return _stored(reference.runId).latestObservable.toJson();
  }

  Map<String, Object?> cancel(Map<String, Object?> params) {
    final reference = _decode(
      () => ScenarioLabRunReference.fromJson(params),
      'Invalid Scenario Lab run reference',
    );
    _stored(reference.runId);
    try {
      return execution.cancel(reference.runId).toJson();
    } on ScenarioLabInterruptedRun {
      throw StateError('Scenario Lab run was interrupted and cannot resume');
    }
  }

  Map<String, Object?> observe(Map<String, Object?> params) {
    final request = _decode(
      () => ScenarioLabRunObserveRequest.fromJson(params),
      'Invalid Scenario Lab observation request',
    );
    final stored = _stored(request.runId);
    final current = stored.latestObservable;
    if (request.afterSequence > current.sequence) {
      throw StateError('Scenario Lab observation sequence is ahead of the run');
    }
    final available = execution.store
        .observationsAfter(request.runId, request.afterSequence)
        .where((snapshot) => snapshot.sequence <= current.sequence)
        .toList(growable: false);
    final page = available.take(request.limit).toList(growable: false);
    final disposition = switch (execution.runDisposition(request.runId)) {
      ScenarioLabReattachDisposition.active => ScenarioLabRunDisposition.active,
      ScenarioLabReattachDisposition.terminal =>
        ScenarioLabRunDisposition.terminal,
      ScenarioLabReattachDisposition.interrupted =>
        ScenarioLabRunDisposition.interrupted,
    };
    return ScenarioLabRunObservation(
      runId: request.runId,
      disposition: disposition,
      afterSequence: request.afterSequence,
      current: current,
      observations: page,
      hasMore: page.length < available.length,
      result: stored.result,
    ).toJson();
  }

  Map<String, Object?> describeRelay(Map<String, Object?> params) {
    if (params.length != 1 || params['runId'] is! String) {
      throw const FormatException('lab.relay.describe requires exactly runId');
    }
    final runId = _decode(
      () => ScenarioLabRunId(params['runId']! as String),
      'Invalid Scenario Lab run ID',
    );
    final stored = _stored(runId);
    final runtimeInputs = _runtimeInputs(stored);
    if (runtimeInputs.gatewayPresetId != null) {
      throw StateError(
        'Gateway-bound Scenario Lab relays require the v2 description',
      );
    }
    final descriptor = relay.describe(runId);
    if (descriptor != null) {
      _relayDescriptorDigests[runId.value] = descriptor.digest;
    }
    final closed = _relayClosed(stored);
    return ScenarioLabRelayDescription(
      runId: runId,
      status: closed
          ? ScenarioLabRelayDescriptionStatus.closed
          : descriptor == null
          ? ScenarioLabRelayDescriptionStatus.pending
          : ScenarioLabRelayDescriptionStatus.ready,
      descriptor: closed ? null : descriptor,
    ).toJson();
  }

  Map<String, Object?> describeRelayV2(Map<String, Object?> params) {
    final request = _decode(
      () => ScenarioLabRelayDescribeRequestV2.fromJson(params),
      'Invalid Scenario Lab relay v2 description request',
    );
    final stored = _stored(request.runId);
    if (stored.request.digest != request.expectedStartRequestDigest) {
      throw StateError('Scenario Lab relay start request changed');
    }
    final descriptor = relay.describe(request.runId);
    final status = _relayClosed(stored)
        ? ScenarioLabRelayDescriptionStatus.closed
        : descriptor == null
        ? ScenarioLabRelayDescriptionStatus.pending
        : ScenarioLabRelayDescriptionStatus.ready;
    if (status != ScenarioLabRelayDescriptionStatus.ready) {
      return ScenarioLabRelayDescriptionV2(
        runId: request.runId,
        startRequestDigest: stored.request.digest,
        status: status,
      ).toJson();
    }
    final runtimeInputs = _runtimeInputs(stored);
    final launchContext = readManagedLaunchContext(request.runId);
    if (launchContext == null) {
      throw StateError('Scenario Lab managed launch context is unavailable');
    }
    _validateReadyRelayV2(
      descriptor: descriptor!,
      runtimeInputs: runtimeInputs,
      launchContext: launchContext,
    );
    _relayDescriptorDigests[request.runId.value] = descriptor.digest;
    return ScenarioLabRelayDescriptionV2(
      runId: request.runId,
      startRequestDigest: stored.request.digest,
      status: status,
      descriptor: descriptor,
      runtimeInputs: runtimeInputs,
      gatewayDataOrigin: launchContext.gatewayDataOrigin,
    ).toJson();
  }

  Map<String, Object?> acceptRelayHello(Map<String, Object?> params) {
    final submission = _decode(
      () => ScenarioLabRelayHelloSubmission.fromJson(params),
      'Invalid Scenario Lab relay hello',
    );
    final descriptor = _descriptor(submission.hello.runId);
    _decode(
      () => submission.validateAgainst(descriptor),
      'Scenario Lab relay hello does not bind the target',
    );
    final accepted = _decode(
      () => relay.acceptHello(submission.hello),
      'Scenario Lab relay hello was rejected',
    );
    return ScenarioLabRelayHelloAcknowledgement(
      runId: descriptor.runId,
      descriptorDigest: descriptor.digest,
      acceptedHelloDigest: accepted.digest,
    ).toJson();
  }

  Future<Map<String, Object?>> nextRelayCommand(
    Map<String, Object?> params,
  ) async {
    final request = _decode(
      () => ScenarioLabRelayPollRequest.fromJson(params),
      'Invalid Scenario Lab relay poll',
    );
    final stored = _stored(request.runId);
    final descriptor = relay.describe(request.runId);
    if (descriptor != null) {
      _relayDescriptorDigests[request.runId.value] = descriptor.digest;
    }
    final knownDigest =
        descriptor?.digest ?? _relayDescriptorDigests[request.runId.value];
    if (_relayClosed(stored)) {
      return _closedRelayPoll(request, knownDigest);
    }
    if (descriptor == null) {
      if (knownDigest == null || knownDigest != request.descriptorDigest) {
        throw StateError('Scenario Lab relay target is not ready');
      }
      return _closedRelayPoll(request, knownDigest);
    }
    if (request.descriptorDigest != descriptor.digest) {
      throw StateError('Scenario Lab relay target changed');
    }
    try {
      final command = await relay.nextCommand(
        request.runId,
        afterSequence: request.afterSequence,
        wait: Duration(milliseconds: request.waitMs),
      );
      final current = _stored(request.runId);
      if (_relayClosed(current)) {
        return _closedRelayPoll(request, descriptor.digest);
      }
      final currentDescriptor = relay.describe(request.runId);
      if (currentDescriptor != null &&
          currentDescriptor.digest != descriptor.digest) {
        relay.close(request.runId);
        throw StateError('Scenario Lab relay target changed');
      }
      return ScenarioLabRelayPollResponse(
        runId: request.runId,
        descriptorDigest: descriptor.digest,
        afterSequence: request.afterSequence,
        state: currentDescriptor == null
            ? ScenarioLabRelayPollState.closed
            : command == null
            ? ScenarioLabRelayPollState.idle
            : ScenarioLabRelayPollState.command,
        command: command,
      ).toJson();
    } on ScenarioLabRelayClosed {
      return ScenarioLabRelayPollResponse(
        runId: request.runId,
        descriptorDigest: descriptor.digest,
        afterSequence: request.afterSequence,
        state: ScenarioLabRelayPollState.closed,
      ).toJson();
    }
  }

  Map<String, Object?> _closedRelayPoll(
    ScenarioLabRelayPollRequest request,
    Digest? descriptorDigest,
  ) {
    relay.close(request.runId);
    if (descriptorDigest == null ||
        descriptorDigest != request.descriptorDigest) {
      throw StateError('Scenario Lab relay target is not ready');
    }
    return ScenarioLabRelayPollResponse(
      runId: request.runId,
      descriptorDigest: descriptorDigest,
      afterSequence: request.afterSequence,
      state: ScenarioLabRelayPollState.closed,
    ).toJson();
  }

  Map<String, Object?> acceptRelayResult(Map<String, Object?> params) {
    final submission = _decode(
      () => ScenarioLabRelayResultSubmission.fromJson(params),
      'Invalid Scenario Lab relay result',
    );
    final descriptor = _descriptor(submission.result.runId);
    if (submission.descriptorDigest != descriptor.digest ||
        submission.result.nonce != descriptor.nonce) {
      throw StateError('Scenario Lab relay result changed target identity');
    }
    final accepted = _decode(
      () => relay.acceptResult(submission.result),
      'Scenario Lab relay result was rejected',
    );
    return ScenarioLabRelayResultAcknowledgement(
      runId: descriptor.runId,
      descriptorDigest: descriptor.digest,
      acceptedResultDigest: accepted.resultDigest,
    ).toJson();
  }

  void close() {
    relay.closeAll();
    _relayDescriptorDigests.clear();
  }

  ScenarioLabStoredRun _stored(ScenarioLabRunId runId) {
    try {
      return execution.store.requireRun(runId);
    } on ScenarioLabRunNotFound {
      throw StateError('Unknown Scenario Lab run ${runId.value}');
    }
  }

  ScenarioLabRelayTargetDescriptor _descriptor(ScenarioLabRunId runId) {
    final stored = _stored(runId);
    if (_relayClosed(stored)) {
      throw StateError('Scenario Lab relay is closed');
    }
    final descriptor =
        relay.describe(runId) ??
        (throw StateError('Scenario Lab relay target is not ready'));
    _relayDescriptorDigests[runId.value] = descriptor.digest;
    return descriptor;
  }

  bool _relayClosed(ScenarioLabStoredRun stored) =>
      execution.runDisposition(stored.latest.runId) !=
      ScenarioLabReattachDisposition.active;

  ScenarioLabRuntimeInputBinding _runtimeInputs(ScenarioLabStoredRun stored) {
    final persisted = stored.latest.runtimeInputs;
    if (persisted != null) return persisted;
    final resolved = readResolvedRuntimeInputs(stored.latest.runId);
    if (resolved != null) return resolved;
    throw StateError('Scenario Lab runtime input binding is unavailable');
  }

  void _validateReadyRelayV2({
    required ScenarioLabRelayTargetDescriptor descriptor,
    required ScenarioLabRuntimeInputBinding runtimeInputs,
    required ScenarioLabManagedLaunchContext launchContext,
  }) {
    final fingerprint = launchContext.executionFingerprint;
    final gateway = launchContext.gateway;
    if (descriptor.origin != launchContext.targetOrigin ||
        descriptor.targetId != runtimeInputs.executionTargetId ||
        descriptor.launchProfileId != fingerprint.launchProfileId ||
        fingerprint.digest != runtimeInputs.executionFingerprintDigest ||
        fingerprint.targetId != runtimeInputs.executionTargetId ||
        (runtimeInputs.gatewayPresetId != null) != (gateway != null) ||
        (gateway != null &&
            (gateway.planDigest != runtimeInputs.compiledGatewayPlanDigest ||
                gateway.routingTableDigest !=
                    runtimeInputs.routingTableDigest))) {
      throw StateError('Scenario Lab relay v2 bindings are inconsistent');
    }
    if (gateway != null) {
      canonicalScenarioLabGatewayDataOrigin(gateway.dataOrigin);
    }
  }
}

T _decode<T>(T Function() decode, String message) {
  try {
    return decode();
  } on FormatException {
    throw FormatException(message);
  } on ArgumentError {
    throw FormatException(message);
  } on StateError {
    throw FormatException(message);
  }
}
