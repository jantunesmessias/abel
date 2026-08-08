import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../gateway/gateway_sidecar_supervisor.dart';
import '../process/managed_process_supervisor.dart';
import '../secure_id_generator.dart';
import 'scenario_lab_execution_ports.dart';
import 'scenario_lab_relay_broker.dart';

/// Host-owned launch inputs for one Catalog-bound Scenario Lab target.
///
/// There is intentionally no origin in this object. The relay origin is
/// accepted only from the child-bound [TargetReadinessRecord] returned by
/// [ManagedProcessSupervisor.startTarget].
final class ScenarioLabManagedTargetConfiguration {
  const ScenarioLabManagedTargetConfiguration({
    required this.launchProfile,
    required this.executionFingerprint,
    required this.runtimeInputs,
    this.gatewayPlan,
  });

  final LaunchProfile launchProfile;
  final ExecutionFingerprint executionFingerprint;
  final ScenarioLabRuntimeInputBinding runtimeInputs;
  final CompiledGatewayPlan? gatewayPlan;

  void validateAgainst(ScenarioExecutionBinding binding) {
    final launchProfileId = binding.launchProfileId;
    if (launchProfileId == null) {
      throw UnsupportedError(
        'Managed Scenario Lab targets require a launch profile binding',
      );
    }
    if (launchProfile.id != launchProfileId) {
      throw ArgumentError(
        'Managed Scenario Lab launch profile does not match the binding',
      );
    }
    runtimeInputs.validateAgainst(binding);
    if (runtimeInputs.executionFingerprintDigest !=
        executionFingerprint.digest) {
      throw ArgumentError(
        'Managed Scenario Lab fingerprint does not match runtime inputs',
      );
    }
    final plan = gatewayPlan;
    final requiresGateway = binding.gatewayPresetId != null;
    if (requiresGateway != (plan != null)) {
      throw ArgumentError(
        'Managed Scenario Lab Gateway plan does not match the binding',
      );
    }
    if (plan != null &&
        (plan.preset.id.value != binding.gatewayPresetId ||
            runtimeInputs.compiledGatewayPlanDigest != plan.digest)) {
      throw ArgumentError(
        'Managed Scenario Lab Gateway plan does not match runtime inputs',
      );
    }
  }
}

typedef ScenarioLabManagedTargetConfigurationResolver =
    ScenarioLabManagedTargetConfiguration Function(
      ScenarioLabRunId runId,
      ScenarioExecutionBinding binding,
    );

/// Immutable observation from the supervisor callback. Output is bounded by
/// [ManagedProcessSupervisor] and is never persisted by this adapter.
final class ScenarioLabManagedProcessExit {
  const ScenarioLabManagedProcessExit({
    required this.ownerId,
    required this.exitCode,
    required this.stdoutTail,
    required this.stderrTail,
  });

  final String ownerId;
  final int exitCode;
  final String stdoutTail;
  final String stderrTail;
}

/// One process that has passed the supervisor's child-binding and health
/// checks.
abstract interface class ScenarioLabManagedProcessHandle {
  TargetReadinessRecord get readiness;

  Future<ScenarioLabManagedProcessExit> get exited;

  Future<void> stop();
}

/// Narrow launch seam used by the target adapter and its process-free tests.
abstract interface class ScenarioLabManagedProcessLauncher {
  Future<ScenarioLabManagedProcessHandle> launch({
    required String ownerId,
    required LaunchProfile profile,
    required String targetId,
    required TargetLaunchAttemptId launchAttemptId,
    required Duration timeout,
  });

  Future<void> abort(String ownerId);

  Future<void> close();
}

/// Narrow, owner-scoped Gateway lifecycle used by the managed target.
///
/// Stopping by owner makes cleanup fail closed even when sidecar startup
/// throws after reserving a child but before returning its handle.
abstract interface class ScenarioLabGatewayLifecyclePort {
  Future<GatewaySidecarHandle> start({
    required String ownerSessionId,
    required Uri targetOrigin,
    required CompiledGatewayPlan plan,
  });

  Future<void> stopOwner(String ownerSessionId);
}

/// Production adapter for the Host-owned Gateway supervisor.
final class GatewaySidecarScenarioLabGatewayLifecyclePort
    implements ScenarioLabGatewayLifecyclePort {
  const GatewaySidecarScenarioLabGatewayLifecyclePort(this.supervisor);

  final GatewaySidecarSupervisor supervisor;

  @override
  Future<GatewaySidecarHandle> start({
    required String ownerSessionId,
    required Uri targetOrigin,
    required CompiledGatewayPlan plan,
  }) => supervisor.start(
    ownerSessionId: ownerSessionId,
    targetOrigin: targetOrigin,
    plan: plan,
  );

  @override
  Future<void> stopOwner(String ownerSessionId) =>
      supervisor.stopOwner(ownerSessionId);
}

/// Host-internal launch context. It is deliberately not part of a public
/// contract or relay descriptor.
final class ScenarioLabManagedLaunchContext {
  const ScenarioLabManagedLaunchContext({
    required this.targetOrigin,
    required this.executionFingerprint,
    required this.gateway,
  });

  final Uri targetOrigin;
  final ExecutionFingerprint executionFingerprint;
  final GatewaySidecarHandle? gateway;

  Uri? get gatewayDataOrigin => gateway?.dataOrigin;
}

/// Production launcher backed by one owned [ManagedProcessSupervisor].
///
/// Owning construction is important: the supervisor's exit callback is fixed
/// at construction time, so accepting an arbitrary pre-built supervisor would
/// make per-run exit detection impossible to prove.
final class ManagedProcessScenarioLabLauncher
    implements ScenarioLabManagedProcessLauncher {
  ManagedProcessScenarioLabLauncher({
    required String workspaceRoot,
    int maxCapturedOutputBytes = 256 * 1024,
  }) {
    _supervisor = ManagedProcessSupervisor(
      workspaceRoot: workspaceRoot,
      maxCapturedOutputBytes: maxCapturedOutputBytes,
      onExit: _acceptExit,
    );
  }

  late final ManagedProcessSupervisor _supervisor;
  final Map<String, Completer<ScenarioLabManagedProcessExit>> _exits =
      <String, Completer<ScenarioLabManagedProcessExit>>{};
  final Map<String, _ManagedProcessLaunchOperation> _launches =
      <String, _ManagedProcessLaunchOperation>{};
  var _closed = false;

  @override
  Future<ScenarioLabManagedProcessHandle> launch({
    required String ownerId,
    required LaunchProfile profile,
    required String targetId,
    required TargetLaunchAttemptId launchAttemptId,
    required Duration timeout,
  }) async {
    if (_closed) throw StateError('Scenario Lab process launcher is closed');
    if (_exits.containsKey(ownerId) || _launches.containsKey(ownerId)) {
      throw StateError('Scenario Lab process owner is already active');
    }
    final exit = Completer<ScenarioLabManagedProcessExit>();
    final operation = _ManagedProcessLaunchOperation();
    _exits[ownerId] = exit;
    _launches[ownerId] = operation;
    try {
      final readiness = await _supervisor.startTarget(
        ownerId,
        profile,
        targetId: targetId,
        launchAttemptId: launchAttemptId,
        timeout: timeout,
      );
      if (operation.aborted) {
        await _supervisor.stop(ownerId);
        throw const ScenarioLabTargetCancelled();
      }
      return _SupervisorScenarioLabManagedProcessHandle(
        ownerId: ownerId,
        readiness: readiness,
        exited: exit.future,
        stopProcess: _stop,
      );
    } on Object {
      _exits.remove(ownerId);
      rethrow;
    } finally {
      if (!operation.done.isCompleted) operation.done.complete();
      if (identical(_launches[ownerId], operation)) {
        _launches.remove(ownerId);
      }
    }
  }

  @override
  Future<void> abort(String ownerId) async {
    final operation = _launches[ownerId];
    if (operation == null) {
      await _supervisor.stop(ownerId);
      return;
    }
    operation.aborted = true;
    while (!operation.done.isCompleted) {
      await _supervisor.stop(ownerId);
      if (operation.done.isCompleted) break;
      await Future.any<void>(<Future<void>>[
        operation.done.future,
        Future<void>.delayed(const Duration(milliseconds: 10)),
      ]);
    }
    await _supervisor.stop(ownerId);
  }

  Future<void> _acceptExit(
    String ownerId,
    int exitCode,
    String stdoutTail,
    String stderrTail,
  ) async {
    final exit = _exits.remove(ownerId);
    if (exit != null && !exit.isCompleted) {
      exit.complete(
        ScenarioLabManagedProcessExit(
          ownerId: ownerId,
          exitCode: exitCode,
          stdoutTail: stdoutTail,
          stderrTail: stderrTail,
        ),
      );
    }
  }

  Future<void> _stop(String ownerId) => _supervisor.stop(ownerId);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final ownerId in _launches.keys.toList(growable: false)) {
      await abort(ownerId);
    }
    await _supervisor.close();
  }
}

final class _ManagedProcessLaunchOperation {
  final Completer<void> done = Completer<void>();
  var aborted = false;
}

final class _SupervisorScenarioLabManagedProcessHandle
    implements ScenarioLabManagedProcessHandle {
  _SupervisorScenarioLabManagedProcessHandle({
    required this.ownerId,
    required this.readiness,
    required this.exited,
    required this._stopProcess,
  });

  final String ownerId;

  @override
  final TargetReadinessRecord readiness;

  @override
  final Future<ScenarioLabManagedProcessExit> exited;

  final Future<void> Function(String ownerId) _stopProcess;
  Future<void>? _stopping;

  @override
  Future<void> stop() => _stopping ??= _stopProcess(ownerId);
}

/// [ScenarioLabTargetPort] backed by a managed child and the RPC relay broker.
///
/// A session becomes observable to the execution service only after the broker
/// has accepted a nonce-bound Hello. Commands remain request/response calls
/// through [ScenarioLabRelayBroker.dispatch].
final class ManagedProcessScenarioLabTargetPort
    implements ScenarioLabTargetPort {
  ManagedProcessScenarioLabTargetPort({
    required this.launcher,
    required this.broker,
    required this.resolveConfiguration,
    this.gateway,
    IdGenerator? ids,
    this.readinessTimeout = const Duration(minutes: 2),
    this.helloTimeout = const Duration(seconds: 30),
  }) : _ids = ids ?? SecureIdGenerator() {
    if (readinessTimeout <= Duration.zero) {
      throw ArgumentError.value(readinessTimeout, 'readinessTimeout');
    }
    if (helloTimeout <= Duration.zero) {
      throw ArgumentError.value(helloTimeout, 'helloTimeout');
    }
  }

  final ScenarioLabManagedProcessLauncher launcher;
  final ScenarioLabRelayBroker broker;
  final ScenarioLabManagedTargetConfigurationResolver resolveConfiguration;
  final ScenarioLabGatewayLifecyclePort? gateway;
  final Duration readinessTimeout;
  final Duration helloTimeout;
  final IdGenerator _ids;
  final Map<String, _ResolvedManagedTarget> _resolved =
      <String, _ResolvedManagedTarget>{};
  final Map<String, ScenarioLabManagedProcessHandle> _processes =
      <String, ScenarioLabManagedProcessHandle>{};
  final Map<String, _ManagedTargetAttachment> _attachments =
      <String, _ManagedTargetAttachment>{};
  final Map<String, _ManagedProcessScenarioLabTargetSession> _sessions =
      <String, _ManagedProcessScenarioLabTargetSession>{};
  final Map<String, ScenarioLabManagedLaunchContext> _launchContexts =
      <String, ScenarioLabManagedLaunchContext>{};
  final Map<String, _ManagedTargetCleanupFailure> _cleanupFailures =
      <String, _ManagedTargetCleanupFailure>{};
  var _closed = false;

  int get activeProcessCount => _processes.length;

  int get activeSessionCount => _sessions.length;

  int get activeGatewayCount =>
      _launchContexts.values.where((context) => context.gateway != null).length;

  ScenarioLabManagedLaunchContext? launchContext(ScenarioLabRunId runId) =>
      _launchContexts[runId.value];

  ScenarioLabRuntimeInputBinding? resolvedRuntimeInputs(
    ScenarioLabRunId runId,
  ) => _resolved[runId.value]?.configuration.runtimeInputs;

  @override
  ScenarioLabRuntimeInputBinding resolveRuntimeInputs({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
  }) => _resolve(runId, binding).configuration.runtimeInputs;

  @override
  Future<ScenarioLabTargetSession> attach({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
    required AppAdapterRelayNonce nonce,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (_closed) throw StateError('Scenario Lab target port is closed');
    if (_processes.containsKey(runId.value) ||
        _sessions.containsKey(runId.value) ||
        _attachments.containsKey(runId.value)) {
      throw StateError('Scenario Lab target is already attached');
    }
    if (cancellation.isCancelled) {
      _resolved.remove(runId.value);
      throw const ScenarioLabTargetCancelled();
    }
    final resolved = _resolve(runId, binding);
    final gatewayPlan = resolved.configuration.gatewayPlan;
    final profile = resolved.configuration.launchProfile;
    final attempt = TargetLaunchAttemptId(_ids.nextId());
    final ownerId = _ownerId(runId);
    final attachment = _ManagedTargetAttachment();
    _attachments[runId.value] = attachment;
    unawaited(
      cancellation.whenCancelled.then<void>(
        (_) => attachment.cancel(),
        onError: (Object error, StackTrace stackTrace) => attachment.cancel(),
      ),
    );
    ScenarioLabManagedProcessHandle? process;
    GatewaySidecarHandle? gatewayHandle;
    var relayOpened = false;
    _ManagedTargetCleanupFailure? cleanupFailure;
    try {
      final launch = launcher.launch(
        ownerId: ownerId,
        profile: profile,
        targetId: binding.targetId,
        launchAttemptId: attempt,
        timeout: readinessTimeout,
      );
      final attachedProcess =
          await _raceAttachmentStage<ScenarioLabManagedProcessHandle>(
            stage: launch,
            attachment: attachment,
            interrupt: () => launcher.abort(ownerId),
            acceptCancelledValue: (value) => process = value,
          );
      process = attachedProcess;
      _validateReadiness(
        attachedProcess.readiness,
        binding: binding,
        profile: profile,
        attempt: attempt,
      );
      _processes[runId.value] = attachedProcess;
      _throwIfAttachmentStopped(attachment);
      if (gatewayPlan != null) {
        final startingGateway = gateway!.start(
          ownerSessionId: ownerId,
          targetOrigin: attachedProcess.readiness.origin,
          plan: gatewayPlan,
        );
        final attachedGateway =
            await _raceAttachmentStage<GatewaySidecarHandle>(
              stage: startingGateway,
              attachment: attachment,
              interrupt: () => gateway!.stopOwner(ownerId),
              acceptCancelledValue: (value) => gatewayHandle = value,
            );
        gatewayHandle = attachedGateway;
        _validateGateway(
          attachedGateway,
          ownerId: ownerId,
          configuration: resolved.configuration,
        );
      }
      _launchContexts[runId.value] = ScenarioLabManagedLaunchContext(
        targetOrigin: attachedProcess.readiness.origin,
        executionFingerprint: resolved.configuration.executionFingerprint,
        gateway: gatewayHandle,
      );
      _throwIfAttachmentStopped(attachment);
      final descriptor = ScenarioLabRelayTargetDescriptor(
        runId: runId,
        targetId: attachedProcess.readiness.targetId,
        launchProfileId: attachedProcess.readiness.launchProfileId,
        launchAttemptId: attachedProcess.readiness.launchAttemptId,
        origin: attachedProcess.readiness.origin,
        nonce: nonce,
      );
      broker.open(descriptor);
      relayOpened = true;
      final hello = await _waitForHello(
        runId: runId,
        process: attachedProcess,
        cancellation: attachment,
      );
      _throwIfAttachmentStopped(attachment);
      final session = _ManagedProcessScenarioLabTargetSession(
        broker: broker,
        process: attachedProcess,
        gateway: gatewayHandle == null ? null : gateway,
        gatewayOwnerId: ownerId,
        hello: hello,
        onClosed: () {
          _sessions.remove(runId.value);
          _processes.remove(runId.value);
          _launchContexts.remove(runId.value);
          _resolved.remove(runId.value);
        },
      );
      _sessions[runId.value] = session;
      return session;
    } on Object catch (error, stackTrace) {
      if (relayOpened) broker.close(runId);
      _processes.remove(runId.value);
      _launchContexts.remove(runId.value);
      _resolved.remove(runId.value);
      try {
        await _cleanupOwner(
          ownerId: ownerId,
          process: process,
          stopGateway: gatewayPlan != null,
        );
      } on Object catch (cleanupError, cleanupStackTrace) {
        cleanupFailure = _ManagedTargetCleanupFailure(
          cleanupError,
          cleanupStackTrace,
        );
        _cleanupFailures[runId.value] = cleanupFailure;
      }
      if (cleanupFailure case final failure?) {
        Error.throwWithStackTrace(failure.error, failure.stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      attachment.complete();
      if (identical(_attachments[runId.value], attachment)) {
        _attachments.remove(runId.value);
      }
    }
  }

  @override
  Future<void> abort(ScenarioLabRunId runId) async {
    final session = _sessions[runId.value];
    if (session != null) {
      await session.close();
      return;
    }
    final attachment = _attachments[runId.value];
    if (attachment != null) {
      attachment.cancel();
      await attachment.done;
    } else {
      broker.close(runId);
      final process = _processes.remove(runId.value);
      _launchContexts.remove(runId.value);
      _resolved.remove(runId.value);
      try {
        await _cleanupOwner(
          ownerId: _ownerId(runId),
          process: process,
          stopGateway: gateway != null,
        );
      } on Object catch (error, stackTrace) {
        _cleanupFailures[runId.value] = _ManagedTargetCleanupFailure(
          error,
          stackTrace,
        );
      }
    }
    _resolved.remove(runId.value);
    final failure = _cleanupFailures.remove(runId.value);
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  Future<T> _raceAttachmentStage<T>({
    required Future<T> stage,
    required _ManagedTargetAttachment attachment,
    required Future<void> Function() interrupt,
    required void Function(T value) acceptCancelledValue,
  }) async {
    final settled = Completer<_ManagedTargetStageOutcome<T>>();
    unawaited(
      stage.then<void>(
        (value) {
          if (!settled.isCompleted) {
            settled.complete(_ManagedTargetStageSucceeded<T>(value));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!settled.isCompleted) {
            settled.complete(_ManagedTargetStageFailed<T>(error, stackTrace));
          }
        },
      ),
    );
    final first = await Future.any<_ManagedTargetStageOutcome<T>>(
      <Future<_ManagedTargetStageOutcome<T>>>[
        settled.future,
        attachment.whenCancelled.then<_ManagedTargetStageOutcome<T>>(
          (_) => _ManagedTargetStageCancelled<T>(),
        ),
      ],
    );
    if (first case _ManagedTargetStageSucceeded<T>(:final value)) {
      if (attachment.isCancelled) {
        acceptCancelledValue(value);
        throw const ScenarioLabTargetCancelled();
      }
      return value;
    }
    if (first case _ManagedTargetStageFailed<T>(
      :final error,
      :final stackTrace,
    )) {
      Error.throwWithStackTrace(error, stackTrace);
    }

    while (!settled.isCompleted) {
      try {
        await interrupt();
      } on Object {
        // The complete owner cleanup below retries every resource boundary.
      }
      if (settled.isCompleted) break;
      await Future.any<void>(<Future<void>>[
        settled.future.then<void>((_) {}),
        Future<void>.delayed(const Duration(milliseconds: 10)),
      ]);
    }
    try {
      await interrupt();
    } on Object {
      // The complete owner cleanup below retries every resource boundary.
    }
    final late = await settled.future;
    if (late case _ManagedTargetStageSucceeded<T>(:final value)) {
      acceptCancelledValue(value);
    }
    throw const ScenarioLabTargetCancelled();
  }

  void _throwIfAttachmentStopped(_ManagedTargetAttachment attachment) {
    if (attachment.isCancelled) throw const ScenarioLabTargetCancelled();
    if (_closed) throw const ScenarioLabAdapterDisconnected();
  }

  _ResolvedManagedTarget _resolve(
    ScenarioLabRunId runId,
    ScenarioExecutionBinding binding,
  ) {
    final bindingDigest = Digest.semantic(binding.toJson());
    final existing = _resolved[runId.value];
    if (existing != null) {
      if (existing.bindingDigest != bindingDigest) {
        throw StateError('Scenario Lab run reused with another binding');
      }
      return existing;
    }
    final configuration = resolveConfiguration(runId, binding);
    configuration.validateAgainst(binding);
    if (configuration.gatewayPlan != null && gateway == null) {
      throw UnsupportedError(
        'Scenario Lab binding requires a Host-owned Gateway supervisor',
      );
    }
    final resolved = _ResolvedManagedTarget(
      bindingDigest: bindingDigest,
      configuration: configuration,
    );
    _resolved[runId.value] = resolved;
    return resolved;
  }

  Future<AppAdapterRelayHello> _waitForHello({
    required ScenarioLabRunId runId,
    required ScenarioLabManagedProcessHandle process,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    final completion = Completer<_HelloOutcome>();

    void complete(_HelloOutcome outcome) {
      if (!completion.isCompleted) completion.complete(outcome);
    }

    unawaited(
      broker
          .waitForHello(runId)
          .then(
            (hello) => complete(_HelloAccepted(hello)),
            onError: (Object error, StackTrace stackTrace) =>
                complete(_HelloFailed(error, stackTrace)),
          ),
    );
    unawaited(
      process.exited.then(
        (_) => complete(const _HelloProcessExited()),
        onError: (Object error, StackTrace stackTrace) =>
            complete(_HelloFailed(error, stackTrace)),
      ),
    );
    unawaited(
      cancellation.whenCancelled.then(
        (_) => complete(const _HelloCancelled()),
        onError: (Object error, StackTrace stackTrace) =>
            complete(_HelloFailed(error, stackTrace)),
      ),
    );
    final timer = Timer(helloTimeout, () => complete(const _HelloTimedOut()));
    try {
      final outcome = await completion.future;
      return switch (outcome) {
        _HelloAccepted(:final hello) => hello,
        _HelloTimedOut() => throw TimeoutException(
          'Scenario Lab App Adapter Hello',
          helloTimeout,
        ),
        _HelloCancelled() => throw const ScenarioLabTargetCancelled(),
        _HelloProcessExited() => throw const ScenarioLabAdapterDisconnected(),
        _HelloFailed(:final error, :final stackTrace) =>
          Error.throwWithStackTrace(error, stackTrace),
      };
    } finally {
      timer.cancel();
    }
  }

  void _validateReadiness(
    TargetReadinessRecord readiness, {
    required ScenarioExecutionBinding binding,
    required LaunchProfile profile,
    required TargetLaunchAttemptId attempt,
  }) {
    if (readiness.launchAttemptId != attempt ||
        readiness.targetId != binding.targetId ||
        readiness.launchProfileId != profile.id) {
      throw const FormatException(
        'Managed Scenario Lab readiness does not bind the launch',
      );
    }
  }

  void _validateGateway(
    GatewaySidecarHandle handle, {
    required String ownerId,
    required ScenarioLabManagedTargetConfiguration configuration,
  }) {
    final plan = configuration.gatewayPlan;
    canonicalScenarioLabGatewayDataOrigin(handle.dataOrigin);
    if (plan == null ||
        handle.ownerSessionId != ownerId ||
        handle.planDigest != plan.digest ||
        handle.routingTableDigest !=
            configuration.runtimeInputs.routingTableDigest) {
      throw const FormatException(
        'Scenario Lab Gateway readiness does not bind the launch inputs',
      );
    }
  }

  Future<void> _cleanupOwner({
    required String ownerId,
    required ScenarioLabManagedProcessHandle? process,
    required bool stopGateway,
  }) async {
    Object? failure;
    StackTrace? failureStackTrace;
    if (stopGateway && gateway != null) {
      try {
        await gateway!.stopOwner(ownerId);
      } on Object catch (error, stackTrace) {
        failure = error;
        failureStackTrace = stackTrace;
      }
    }
    try {
      await launcher.abort(ownerId);
    } on Object catch (error, stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    }
    if (process != null) {
      try {
        await process.stop();
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }

  String _ownerId(ScenarioLabRunId runId) => 'scenario-lab-${runId.value}';

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    Object? failure;
    StackTrace? failureStackTrace;
    for (final runId
        in _attachments.keys
            .map(ScenarioLabRunId.new)
            .toList(growable: false)) {
      try {
        await abort(runId);
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }
    for (final session in _sessions.values.toList(growable: false)) {
      try {
        await session.close();
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }
    for (final entry in _processes.entries.toList(growable: false)) {
      broker.close(ScenarioLabRunId(entry.key));
      try {
        await _cleanupOwner(
          ownerId: _ownerId(ScenarioLabRunId(entry.key)),
          process: entry.value,
          stopGateway: gateway != null,
        );
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }
    _sessions.clear();
    _processes.clear();
    _launchContexts.clear();
    _resolved.clear();
    try {
      await launcher.close();
    } on Object catch (error, stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    }
    _attachments.clear();
    if (_cleanupFailures.isNotEmpty) {
      final first = _cleanupFailures.values.first;
      failure ??= first.error;
      failureStackTrace ??= first.stackTrace;
      _cleanupFailures.clear();
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }
}

final class _ManagedTargetAttachment implements ScenarioLabCancellationSignal {
  final Completer<void> _cancelled = Completer<void>();
  final Completer<void> _done = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  Future<void> get done => _done.future;

  void cancel() {
    if (!_cancelled.isCompleted && !_done.isCompleted) _cancelled.complete();
  }

  void complete() {
    if (!_done.isCompleted) _done.complete();
  }
}

final class _ManagedTargetCleanupFailure {
  const _ManagedTargetCleanupFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

sealed class _ManagedTargetStageOutcome<T> {
  const _ManagedTargetStageOutcome();
}

final class _ManagedTargetStageSucceeded<T>
    extends _ManagedTargetStageOutcome<T> {
  const _ManagedTargetStageSucceeded(this.value);

  final T value;
}

final class _ManagedTargetStageFailed<T> extends _ManagedTargetStageOutcome<T> {
  const _ManagedTargetStageFailed(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _ManagedTargetStageCancelled<T>
    extends _ManagedTargetStageOutcome<T> {
  const _ManagedTargetStageCancelled();
}

final class _ResolvedManagedTarget {
  const _ResolvedManagedTarget({
    required this.bindingDigest,
    required this.configuration,
  });

  final Digest bindingDigest;
  final ScenarioLabManagedTargetConfiguration configuration;
}

final class _ManagedProcessScenarioLabTargetSession
    implements ScenarioLabTargetSession {
  _ManagedProcessScenarioLabTargetSession({
    required this.broker,
    required this.process,
    required this.gateway,
    required this.gatewayOwnerId,
    required this.hello,
    required this.onClosed,
  }) {
    unawaited(_monitorProcessExit());
  }

  final ScenarioLabRelayBroker broker;
  final ScenarioLabManagedProcessHandle process;
  final ScenarioLabGatewayLifecyclePort? gateway;
  final String gatewayOwnerId;

  @override
  final AppAdapterRelayHello hello;

  final void Function() onClosed;
  final Completer<void> _disconnected = Completer<void>();
  Future<void>? _closing;

  @override
  Future<AppAdapterRelayResult> execute(
    AppAdapterRelayCommand command, {
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    if (_closing != null || _disconnected.isCompleted) {
      throw const ScenarioLabAdapterDisconnected();
    }
    if (cancellation.isCancelled) {
      throw const ScenarioLabTargetCancelled();
    }
    final completion = Completer<_DispatchOutcome>();

    void complete(_DispatchOutcome outcome) {
      if (!completion.isCompleted) completion.complete(outcome);
    }

    final Future<AppAdapterRelayResult> dispatch;
    try {
      dispatch = broker.dispatch(command);
    } on ScenarioLabRelayClosed {
      throw const ScenarioLabAdapterDisconnected();
    }
    unawaited(
      dispatch.then(
        (result) => complete(_DispatchCompleted(result)),
        onError: (Object error, StackTrace stackTrace) =>
            complete(_DispatchFailed(error, stackTrace)),
      ),
    );
    unawaited(
      _disconnected.future.then((_) => complete(const _DispatchDisconnected())),
    );
    unawaited(
      cancellation.whenCancelled.then(
        (_) => complete(const _DispatchDisconnected()),
        onError: (Object error, StackTrace stackTrace) =>
            complete(_DispatchFailed(error, stackTrace)),
      ),
    );
    final outcome = await completion.future;
    return switch (outcome) {
      _DispatchCompleted(:final result) => result,
      _DispatchDisconnected() =>
        cancellation.isCancelled
            ? throw const ScenarioLabTargetCancelled()
            : throw const ScenarioLabAdapterDisconnected(),
      _DispatchFailed(error: ScenarioLabRelayClosed()) =>
        throw const ScenarioLabAdapterDisconnected(),
      _DispatchFailed(:final error, :final stackTrace) =>
        Error.throwWithStackTrace(error, stackTrace),
    };
  }

  void _disconnect() {
    broker.close(hello.runId);
    if (!_disconnected.isCompleted) _disconnected.complete();
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _monitorProcessExit() async {
    try {
      await process.exited;
    } on Object {
      // A failed exit observation is still a terminal disconnect.
    }
    try {
      await close();
    } on Object {
      // The explicit owner of the adapter receives cleanup errors from close;
      // an exit observer has no secondary error channel.
    }
  }

  Future<void> _close() async {
    _disconnect();
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      if (gateway != null) await gateway!.stopOwner(gatewayOwnerId);
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }
    try {
      await process.stop();
    } on Object catch (error, stackTrace) {
      failure ??= error;
      failureStackTrace ??= stackTrace;
    } finally {
      onClosed();
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }
}

sealed class _HelloOutcome {
  const _HelloOutcome();
}

final class _HelloAccepted extends _HelloOutcome {
  const _HelloAccepted(this.hello);

  final AppAdapterRelayHello hello;
}

final class _HelloTimedOut extends _HelloOutcome {
  const _HelloTimedOut();
}

final class _HelloCancelled extends _HelloOutcome {
  const _HelloCancelled();
}

final class _HelloProcessExited extends _HelloOutcome {
  const _HelloProcessExited();
}

final class _HelloFailed extends _HelloOutcome {
  const _HelloFailed(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

sealed class _DispatchOutcome {
  const _DispatchOutcome();
}

final class _DispatchCompleted extends _DispatchOutcome {
  const _DispatchCompleted(this.result);

  final AppAdapterRelayResult result;
}

final class _DispatchDisconnected extends _DispatchOutcome {
  const _DispatchDisconnected();
}

final class _DispatchFailed extends _DispatchOutcome {
  const _DispatchFailed(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
