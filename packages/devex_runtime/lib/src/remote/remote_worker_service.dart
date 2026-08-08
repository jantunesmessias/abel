import 'dart:async';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:path/path.dart' as p;

import 'jose_remote_execution_security.dart';

final class RemoteGeneratedArtifact {
  const RemoteGeneratedArtifact({
    required this.role,
    required this.file,
    required this.mediaType,
    required this.classification,
  });

  final String role;
  final File file;
  final String mediaType;
  final String classification;
}

final class RemoteBackendResult {
  const RemoteBackendResult({
    required this.artifacts,
    required this.interactiveTransport,
    this.interactiveSession,
  });

  final List<RemoteGeneratedArtifact> artifacts;
  final RemoteInteractiveTransport interactiveTransport;
  final RemoteWorkerInteractiveSession? interactiveSession;
}

abstract interface class RemoteWorkerInteractiveSession {
  RemoteInteractiveTransport get transport;

  Future<void> run({
    required RemoteWorkerStreamClient stream,
    required DateTime deadline,
  });

  Future<void> stop();
}

abstract interface class RemoteWorkerBackend {
  Future<RemoteBackendResult> execute({
    required RemoteExecutionPlan plan,
    required Map<String, File> inputsByRole,
    required Directory workspace,
  });

  Future<void> stop();
}

abstract interface class RemoteWorkerArtifactClient {
  Future<File> download({
    required VerifiedRemoteCapability capability,
    required RemoteArtifactInput artifact,
    required Directory destination,
  });

  Future<HostedBlobDescriptor> upload({
    required VerifiedRemoteCapability capability,
    required RemoteGeneratedArtifact artifact,
  });
}

abstract interface class RemoteWorkerControlClient {
  Future<void> state({
    required VerifiedRemoteCapability capability,
    required RemoteRunState state,
    String? failureCode,
  });

  Future<RemoteWorkerHeartbeat> heartbeat(VerifiedRemoteCapability capability);

  Future<void> complete({
    required VerifiedRemoteCapability capability,
    required RemoteArtifactManifest artifacts,
    required RemoteContainmentReport containment,
    required RemoteInteractiveTransport interactiveTransport,
  });
}

final class RemoteWorkerHeartbeat {
  const RemoteWorkerHeartbeat({required this.renewedCapabilityToken});

  final String renewedCapabilityToken;
}

abstract interface class RemoteWorkerStreamClient {
  Stream<RemoteStreamFrame> get controlFrames;

  Future<void> connect(String capabilityToken);

  Future<void> reauthenticate(String capabilityToken);

  Future<void> publish(RemoteStreamChannel channel, List<int> payload);

  Future<void> get done;

  Future<void> close();
}

final class RemoteWorkerOutcome {
  const RemoteWorkerOutcome({
    required this.artifacts,
    required this.containment,
    required this.interactiveTransport,
  });

  final RemoteArtifactManifest artifacts;
  final RemoteContainmentReport containment;
  final RemoteInteractiveTransport interactiveTransport;
}

final class RemoteWorkerService {
  const RemoteWorkerService({
    required this._verifier,
    required this._artifacts,
    required this._control,
    required this._backend,
    required this._clock,
    required this._workspaceRoot,
    required this._namespace,
    required this._serviceAccount,
    this.stream,
    this.heartbeatInterval = const Duration(seconds: 15),
    this.backendStopTimeout = const Duration(seconds: 10),
    this.completionReserve = const Duration(seconds: 15),
  });

  final RemoteWorkerTokenVerifier _verifier;
  final RemoteWorkerArtifactClient _artifacts;
  final RemoteWorkerControlClient _control;
  final RemoteWorkerBackend _backend;
  final Clock _clock;
  final Directory _workspaceRoot;
  final String _namespace;
  final String _serviceAccount;
  final RemoteWorkerStreamClient? stream;
  final Duration heartbeatInterval;
  final Duration backendStopTimeout;
  final Duration completionReserve;

  Future<RemoteWorkerOutcome> run({
    required String signedPlan,
    required String capabilityToken,
    required String workerId,
  }) async {
    final plan = await _verifier.verifyPlan(signedPlan);
    final capability = await _verifier.verifyCapability(
      capabilityToken,
      plan: plan,
      workerId: workerId,
      requiredScopes: <String>{
        'artifact:read',
        'artifact:write',
        'run:heartbeat',
        'run:complete',
        if (plan.mode == RemoteRunMode.interactive) 'stream:write',
      },
    );
    final workspace = Directory(p.join(_workspaceRoot.path, plan.runId));
    if (workspace.existsSync()) {
      throw StateError('remote workspace was not clean before execution');
    }
    workspace.createSync(recursive: true);
    var terminalReported = false;
    var backendStopped = false;
    var streamClosed = false;
    var workspaceWiped = false;
    var activeCapabilityToken = capabilityToken;
    try {
      await _control.state(
        capability: capability,
        state: RemoteRunState.provisioning,
      );
      final inputs = <String, File>{};
      for (final artifact in plan.artifacts) {
        final file = await _artifacts.download(
          capability: capability,
          artifact: artifact,
          destination: workspace,
        );
        _verifyInput(file, artifact);
        inputs[artifact.role] = file;
      }
      final initialHeartbeat = await _control.heartbeat(capability);
      activeCapabilityToken = initialHeartbeat.renewedCapabilityToken;
      await _control.state(
        capability: capability,
        state: RemoteRunState.running,
      );
      var streamConnected = false;
      final prepared = await _executeWithHeartbeats<_PreparedRemoteCompletion>(
        capability: capability,
        onRenewedCapability: (token) async {
          activeCapabilityToken = token;
          if (streamConnected) {
            await stream!.reauthenticate(token);
          }
        },
        execute: () async {
          final backendResult = await _backend.execute(
            plan: plan,
            inputsByRole: Map<String, File>.unmodifiable(inputs),
            workspace: workspace,
          );
          if (plan.mode == RemoteRunMode.interactive) {
            final session = backendResult.interactiveSession;
            final activeStream = stream;
            if (session == null ||
                activeStream == null ||
                backendResult.interactiveTransport != session.transport ||
                session.transport == RemoteInteractiveTransport.none) {
              throw StateError(
                'interactive run has no matching stream session',
              );
            }
            final deadline = plan.expiresAt.subtract(completionReserve);
            if (!deadline.isAfter(_clock.nowUtc())) {
              throw StateError('interactive completion reserve is exhausted');
            }
            await activeStream.connect(activeCapabilityToken);
            streamConnected = true;
            await session.run(stream: activeStream, deadline: deadline);
          } else if (backendResult.interactiveSession != null ||
              backendResult.interactiveTransport !=
                  RemoteInteractiveTransport.none) {
            throw StateError('batch backend returned an interactive session');
          }
          await _control.state(
            capability: capability,
            state: RemoteRunState.uploading,
          );
          final descriptors = <HostedBlobDescriptor>[];
          for (final artifact in backendResult.artifacts) {
            if (!artifact.file.existsSync() ||
                p.isWithin(workspace.path, artifact.file.path) == false) {
              throw StateError(
                'backend produced an artifact outside its workspace',
              );
            }
            descriptors.add(
              await _artifacts.upload(
                capability: capability,
                artifact: artifact,
              ),
            );
          }
          return _PreparedRemoteCompletion(
            backend: backendResult,
            artifacts: descriptors,
          );
        },
      );
      final backendResult = prepared.backend;
      final descriptors = prepared.artifacts;
      await stream?.close();
      streamClosed = true;
      await _backend.stop();
      backendStopped = true;
      workspace.deleteSync(recursive: true);
      workspaceWiped = true;
      final manifest = RemoteArtifactManifest(
        tenantId: plan.tenantId,
        runId: plan.runId,
        executionFingerprintDigest: plan.executionFingerprintDigest,
        interactiveTransport: backendResult.interactiveTransport,
        artifacts: descriptors,
        createdAt: _clock.nowUtc(),
      );
      final containment = RemoteContainmentReport(
        tenantId: plan.tenantId,
        runId: plan.runId,
        namespace: _namespace,
        serviceAccount: _serviceAccount,
        podSecurityProfile: plan.target == RemoteTargetKind.androidEmulator
            ? 'android-kvm-minimal'
            : 'restricted',
        defaultDenyEgress: true,
        allowedEndpointClasses: const <String>{
          'gateway',
          'artifact',
          'control',
          'dns',
        },
        ephemeralStorageWiped: workspaceWiped,
        // The worker cannot truthfully revoke its own scheduler lease. The
        // control plane replaces this with true in the same transaction that
        // removes the lease and persists the final containment report.
        leaseRevoked: false,
        observedAt: _clock.nowUtc(),
      );
      await _control.complete(
        capability: capability,
        artifacts: manifest,
        containment: containment,
        interactiveTransport: backendResult.interactiveTransport,
      );
      terminalReported = true;
      return RemoteWorkerOutcome(
        artifacts: manifest,
        containment: containment,
        interactiveTransport: backendResult.interactiveTransport,
      );
    } on Object {
      if (!terminalReported) {
        try {
          await _control.state(
            capability: capability,
            state: RemoteRunState.failed,
            failureCode: 'worker_execution_failed',
          );
        } on Object {
          // The scheduler lease reaper is authoritative when the control plane
          // is unreachable; the worker never reports implicit success.
        }
      }
      rethrow;
    } finally {
      if (!streamClosed) await stream?.close();
      if (!backendStopped) await _backend.stop();
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    }
  }

  Future<T> _executeWithHeartbeats<T>({
    required VerifiedRemoteCapability capability,
    required Future<T> Function() execute,
    required Future<void> Function(String token) onRenewedCapability,
  }) async {
    if (heartbeatInterval <= Duration.zero ||
        backendStopTimeout <= Duration.zero ||
        completionReserve <= Duration.zero) {
      throw StateError('remote worker heartbeat timings are invalid');
    }
    final failure = Completer<Object>();
    Future<void>? heartbeatInFlight;
    var stopped = false;
    late final Timer timer;

    void heartbeat() {
      if (stopped || heartbeatInFlight != null) return;
      final current = () async {
        final heartbeat = await _control.heartbeat(capability);
        await onRenewedCapability(heartbeat.renewedCapabilityToken);
      }();
      heartbeatInFlight = current;
      unawaited(
        current.then<void>(
          (_) => heartbeatInFlight = null,
          onError: (Object error, StackTrace _) {
            heartbeatInFlight = null;
            if (!failure.isCompleted) failure.complete(error);
          },
        ),
      );
    }

    timer = Timer.periodic(heartbeatInterval, (_) => heartbeat());
    final execution = execute();
    final race = await Future.any(<Future<_WorkerExecutionRace<T>>>[
      execution.then<_WorkerExecutionRace<T>>(
        _WorkerExecutionSucceeded<T>.new,
        onError: (Object error, StackTrace stackTrace) =>
            _WorkerExecutionFailed<T>(error, stackTrace),
      ),
      failure.future.then<_WorkerExecutionRace<T>>(
        _WorkerHeartbeatFailed<T>.new,
      ),
    ]);
    stopped = true;
    timer.cancel();
    final lastHeartbeat = heartbeatInFlight;
    if (lastHeartbeat != null) {
      try {
        await lastHeartbeat;
      } on Object {
        // The failure is represented by [failure] and handled below.
      }
    }
    if (failure.isCompleted && race is _WorkerExecutionSucceeded<T>) {
      final error = await failure.future;
      await _stopAfterLeaseFailure(execution);
      throw RemoteStateException(
        'remote worker heartbeat failed: ${error.runtimeType}',
      );
    }
    if (race case _WorkerExecutionSucceeded<T>(:final result)) return result;
    if (race case _WorkerExecutionFailed<T>(:final error, :final stackTrace)) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    final heartbeatFailure = (race as _WorkerHeartbeatFailed<T>).error;
    await _stopAfterLeaseFailure(execution);
    throw RemoteStateException(
      'remote worker heartbeat failed: ${heartbeatFailure.runtimeType}',
    );
  }

  Future<void> _stopAfterLeaseFailure(Future<Object?> execution) async {
    try {
      await _backend.stop().timeout(backendStopTimeout);
    } on Object {
      // The lease reaper remains authoritative. Cleanup is retried by finally.
    }
    try {
      await execution.timeout(backendStopTimeout);
    } on Object {
      // A backend that does not stop cannot turn the run into success.
    }
  }

  void _verifyInput(File file, RemoteArtifactInput expected) {
    final stat = file.statSync();
    if (stat.type != FileSystemEntityType.file || stat.size != expected.size) {
      throw StateError('downloaded artifact size or type is invalid');
    }
    final digest = Digest.bytes(file.readAsBytesSync());
    if (digest != expected.digest) {
      throw StateError('downloaded artifact digest does not match the plan');
    }
  }
}

final class _PreparedRemoteCompletion {
  const _PreparedRemoteCompletion({
    required this.backend,
    required this.artifacts,
  });

  final RemoteBackendResult backend;
  final List<HostedBlobDescriptor> artifacts;
}

sealed class _WorkerExecutionRace<T> {
  const _WorkerExecutionRace();
}

final class _WorkerExecutionSucceeded<T> extends _WorkerExecutionRace<T> {
  const _WorkerExecutionSucceeded(this.result);

  final T result;
}

final class _WorkerExecutionFailed<T> extends _WorkerExecutionRace<T> {
  const _WorkerExecutionFailed(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

final class _WorkerHeartbeatFailed<T> extends _WorkerExecutionRace<T> {
  const _WorkerHeartbeatFailed(this.error);

  final Object error;
}
