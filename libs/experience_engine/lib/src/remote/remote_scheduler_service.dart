import 'package:experience_contracts/experience_contracts.dart';

import '../hosted/hosted_collaboration_service.dart';
import '../ports.dart';

final class RemoteQuota {
  const RemoteQuota({
    required this.maximumQueued,
    required this.maximumConcurrent,
    required this.maximumInteractive,
  });

  final int maximumQueued;
  final int maximumConcurrent;
  final int maximumInteractive;
}

abstract interface class RemoteQuotaPolicy {
  RemoteQuota quotaFor(String tenantId);
}

abstract interface class RemoteDeviceImagePolicy {
  bool allows(DeviceImageDescriptor descriptor);
}

final class StaticRemoteDeviceImagePolicy implements RemoteDeviceImagePolicy {
  const StaticRemoteDeviceImagePolicy(this.allowed);

  final Set<DeviceImageDescriptor> allowed;

  @override
  bool allows(DeviceImageDescriptor descriptor) => allowed.any(
    (candidate) =>
        candidate.id == descriptor.id &&
        candidate.imageDigest == descriptor.imageDigest &&
        candidate.apiLevel == descriptor.apiLevel &&
        candidate.abi == descriptor.abi &&
        candidate.renderer == descriptor.renderer &&
        candidate.kvmRequired == descriptor.kvmRequired,
  );
}

final class DenyRemoteDeviceImagePolicy implements RemoteDeviceImagePolicy {
  const DenyRemoteDeviceImagePolicy();

  @override
  bool allows(DeviceImageDescriptor descriptor) => false;
}

final class StaticRemoteQuotaPolicy implements RemoteQuotaPolicy {
  const StaticRemoteQuotaPolicy({
    this.defaults = const RemoteQuota(
      maximumQueued: 20,
      maximumConcurrent: 4,
      maximumInteractive: 1,
    ),
  });

  final RemoteQuota defaults;

  @override
  RemoteQuota quotaFor(String tenantId) => defaults;
}

final class RemoteQuotaException implements Exception {
  const RemoteQuotaException(this.message);

  final String message;

  @override
  String toString() => 'RemoteQuotaException: $message';
}

final class RemoteStateException implements Exception {
  const RemoteStateException(this.message);

  final String message;

  @override
  String toString() => 'RemoteStateException: $message';
}

final class SignedRemoteExecutionPlan {
  const SignedRemoteExecutionPlan({
    required this.plan,
    required this.compactSignature,
    required this.signerKeyId,
  });

  final RemoteExecutionPlan plan;
  final String compactSignature;
  final String signerKeyId;
}

abstract interface class RemotePlanSigner {
  Future<SignedRemoteExecutionPlan> sign(RemoteExecutionPlan plan);
}

abstract interface class RemoteCapabilityIssuer {
  Future<String> issue({
    required RemoteExecutionPlan plan,
    required RemoteLease lease,
    required Set<String> scopes,
  });
}

abstract interface class RemoteSessionTicketIssuer {
  Future<String> issueViewerTicket(RemoteSessionTicket ticket);
}

final class RemoteAssignment {
  const RemoteAssignment({
    required this.run,
    required this.lease,
    required this.signedPlan,
    required this.capabilityToken,
  });

  final RemoteRun run;
  final RemoteLease lease;
  final SignedRemoteExecutionPlan signedPlan;
  final String capabilityToken;
}

final class RemoteLeaseRenewal {
  const RemoteLeaseRenewal({
    required this.lease,
    required this.capabilityToken,
  });

  final RemoteLease lease;
  final String capabilityToken;
}

/// Durable, tenant-scoped request to destroy the resources of one lease
/// generation before the run may be dispatched again or considered cleaned.
final class RemoteCleanupTask {
  RemoteCleanupTask({
    required this.tenantId,
    required this.runId,
    required this.generation,
    required this.requestedAt,
    required this.availableAt,
    required this.attempts,
    this.lastFailureCode,
  }) {
    if (tenantId.isEmpty ||
        runId.isEmpty ||
        generation < 1 ||
        generation > 10 ||
        attempts < 0 ||
        attempts > 1000000 ||
        !requestedAt.isUtc ||
        !availableAt.isUtc ||
        availableAt.isBefore(requestedAt) ||
        (lastFailureCode != null &&
            !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(lastFailureCode!))) {
      throw ArgumentError('remote cleanup task is invalid');
    }
  }

  final String tenantId;
  final String runId;
  final int generation;
  final DateTime requestedAt;
  final DateTime availableAt;
  final int attempts;
  final String? lastFailureCode;
}

abstract interface class RemoteSchedulerTransaction {
  Future<int> countQueued();

  Future<int> countConcurrent();

  Future<int> countInteractive();

  Future<void> insert({
    required RemoteExecutionRequest request,
    required RemoteExecutionPlan plan,
    required RemoteRun run,
  });

  Future<List<RemoteRun>> queuedFor(Set<RemoteTargetKind> targets);

  Future<RemoteExecutionPlan> planFor(String runId);

  Future<RemoteExecutionRequest> requestFor(String runId);

  Future<RemoteRun?> runById(String runId);

  Future<RemoteLease?> leaseFor(String runId);

  Future<int> activeLeaseCount(String workerId, DateTime now);

  Future<void> replaceRun(RemoteRun run, RemoteRunState expectedState);

  Future<void> putLease(RemoteLease lease);

  Future<void> removeLease(String runId, int generation);

  Future<void> putCompletion({
    required RemoteArtifactManifest artifacts,
    required RemoteContainmentReport containment,
  });

  Future<List<RemoteLease>> expiredLeases(DateTime now);

  Future<void> putCleanup(RemoteCleanupTask task);

  Future<List<RemoteCleanupTask>> readyCleanups(DateTime now, int limit);

  Future<void> completeCleanup(RemoteCleanupTask task);

  Future<void> deferCleanup(
    RemoteCleanupTask task, {
    required DateTime availableAt,
    required String failureCode,
  });
}

abstract interface class RemoteSchedulerRepository {
  Future<T> inTenantTransaction<T>(
    String tenantId,
    Future<T> Function(RemoteSchedulerTransaction transaction) operation,
  );

  Future<List<String>> tenantsWithExpiredLeases(DateTime now);

  Future<List<String>> tenantsWithQueuedRuns();

  Future<List<String>> tenantsWithPendingCleanups(DateTime now);
}

final class RemoteSchedulerService {
  const RemoteSchedulerService({
    required this._repository,
    required this._quotas,
    required this._signer,
    required this._capabilities,
    required this._clock,
    required this._ids,
    this._deviceImages = const DenyRemoteDeviceImagePolicy(),
  });

  final RemoteSchedulerRepository _repository;
  final RemoteQuotaPolicy _quotas;
  final RemotePlanSigner _signer;
  final RemoteCapabilityIssuer _capabilities;
  final Clock _clock;
  final IdGenerator _ids;
  final RemoteDeviceImagePolicy _deviceImages;

  Future<RemoteRun> enqueue(
    HostedRequestContext context,
    RemoteExecutionRequest request, {
    required Digest executionFingerprintDigest,
    required Digest containmentPolicyDigest,
    DeviceImageDescriptor? deviceImage,
  }) => _repository.inTenantTransaction(context.tenantId, (transaction) async {
    if (request.tenantId != context.tenantId ||
        request.requestedBy != context.principalId) {
      throw const HostedAuthorizationException(
        'remote request does not match authenticated tenant and principal',
      );
    }
    if (request.target == RemoteTargetKind.androidEmulator &&
        (deviceImage == null || !_deviceImages.allows(deviceImage))) {
      throw const HostedAuthorizationException(
        'Android device image is not present in the scheduler allowlist',
      );
    }
    final quota = _quotas.quotaFor(context.tenantId);
    if (await transaction.countQueued() >= quota.maximumQueued) {
      throw const RemoteQuotaException('tenant queued-run quota exceeded');
    }
    if (request.mode == RemoteRunMode.interactive &&
        await transaction.countInteractive() >= quota.maximumInteractive) {
      throw const RemoteQuotaException('tenant interactive-run quota exceeded');
    }
    final now = _clock.nowUtc();
    final runId = _ids.nextId();
    final plan = RemoteExecutionPlan(
      tenantId: context.tenantId,
      runId: runId,
      requestDigest: request.digest,
      target: request.target,
      mode: request.mode,
      interactiveTransport: request.interactiveTransport,
      artifacts: request.artifacts,
      executionFingerprintDigest: executionFingerprintDigest,
      containmentPolicyDigest: containmentPolicyDigest,
      issuedAt: now,
      expiresAt: now.add(
        Duration(seconds: request.maximumDurationSeconds.clamp(30, 3600)),
      ),
      nonce: _ids.nextId(),
      deviceImage: deviceImage,
    );
    final run = RemoteRun(
      tenantId: context.tenantId,
      id: runId,
      requestDigest: request.digest,
      planDigest: plan.digest,
      target: request.target,
      mode: request.mode,
      state: RemoteRunState.queued,
      attempt: 0,
      createdAt: now,
      updatedAt: now,
    );
    await transaction.insert(request: request, plan: plan, run: run);
    return run;
  });

  Future<RemoteAssignment?> acquire(
    String tenantId,
    RemoteWorkerDescriptor worker, {
    Duration leaseTtl = const Duration(seconds: 60),
  }) => _repository.inTenantTransaction(tenantId, (transaction) async {
    if (leaseTtl < const Duration(seconds: 20) ||
        leaseTtl > const Duration(minutes: 5)) {
      throw ArgumentError('lease TTL must be 20-300 seconds');
    }
    final now = _clock.nowUtc();
    if (now.difference(worker.lastHeartbeatAt) > const Duration(minutes: 2)) {
      throw const RemoteStateException('worker descriptor is stale');
    }
    if (await transaction.activeLeaseCount(worker.id, now) >=
        worker.maximumLeases) {
      return null;
    }
    final quota = _quotas.quotaFor(tenantId);
    if (await transaction.countConcurrent() >= quota.maximumConcurrent) {
      return null;
    }
    final candidates = await transaction.queuedFor(worker.targets);
    if (candidates.isEmpty) return null;
    RemoteRun? selected;
    RemoteExecutionPlan? selectedPlan;
    for (final candidate in candidates) {
      final plan = await transaction.planFor(candidate.id);
      if (!plan.expiresAt.isAfter(now)) {
        await transaction.replaceRun(
          _copyRun(
            candidate,
            state: RemoteRunState.failed,
            updatedAt: now,
            failureCode: 'plan_expired_before_schedule',
          ),
          RemoteRunState.queued,
        );
        continue;
      }
      selected = candidate;
      selectedPlan = plan;
      break;
    }
    if (selected == null || selectedPlan == null) return null;
    final plan = selectedPlan;
    final lease = RemoteLease(
      tenantId: tenantId,
      runId: selected.id,
      workerId: worker.id,
      tokenId: _ids.nextId(),
      generation: selected.attempt + 1,
      acquiredAt: now,
      heartbeatAt: now,
      expiresAt: now.add(leaseTtl),
    );
    final scheduled = _copyRun(
      selected,
      state: RemoteRunState.scheduled,
      attempt: lease.generation,
      updatedAt: now,
      workerId: worker.id,
    );
    await transaction.replaceRun(scheduled, RemoteRunState.queued);
    await transaction.putLease(lease);
    final signed = await _signer.sign(plan);
    final token = await _capabilities.issue(
      plan: plan,
      lease: lease,
      scopes: const <String>{
        'artifact:read',
        'artifact:write',
        'run:heartbeat',
        'run:complete',
        'stream:write',
      },
    );
    return RemoteAssignment(
      run: scheduled,
      lease: lease,
      signedPlan: signed,
      capabilityToken: token,
    );
  });

  Future<RemoteLease> heartbeat(
    RemoteLease presented, {
    Duration leaseTtl = const Duration(seconds: 60),
  }) => _repository.inTenantTransaction(presented.tenantId, (
    transaction,
  ) async {
    final stored = await transaction.leaseFor(presented.runId);
    if (stored == null ||
        stored.workerId != presented.workerId ||
        stored.tokenId != presented.tokenId ||
        stored.generation != presented.generation ||
        !stored.expiresAt.isAfter(_clock.nowUtc())) {
      throw const RemoteStateException('lease is missing, stale, or expired');
    }
    final now = _clock.nowUtc();
    final renewed = RemoteLease(
      tenantId: stored.tenantId,
      runId: stored.runId,
      workerId: stored.workerId,
      tokenId: stored.tokenId,
      generation: stored.generation,
      acquiredAt: stored.acquiredAt,
      heartbeatAt: now,
      expiresAt: now.add(leaseTtl),
    );
    await transaction.putLease(renewed);
    return renewed;
  });

  Future<RemoteLeaseRenewal> renew(RemoteLease presented) async {
    final lease = await heartbeat(presented);
    final plan = await planForTenant(lease.tenantId, lease.runId);
    final token = await _capabilities.issue(
      plan: plan,
      lease: lease,
      scopes: const <String>{
        'artifact:read',
        'artifact:write',
        'run:heartbeat',
        'run:complete',
        'stream:write',
      },
    );
    return RemoteLeaseRenewal(lease: lease, capabilityToken: token);
  }

  Future<RemoteExecutionPlan> planForTenant(String tenantId, String runId) =>
      _repository.inTenantTransaction(
        tenantId,
        (transaction) => transaction.planFor(runId),
      );

  Future<RemoteRun> runForTenant(String tenantId, String runId) =>
      _repository.inTenantTransaction(tenantId, (transaction) async {
        final run = await transaction.runById(runId);
        if (run == null) {
          throw const RemoteStateException('remote run not found');
        }
        return run;
      });

  Future<RemoteRun> transition(
    RemoteLease lease,
    RemoteRunState next, {
    String? failureCode,
  }) => _repository.inTenantTransaction(lease.tenantId, (transaction) async {
    final storedLease = await transaction.leaseFor(lease.runId);
    final current = await transaction.runById(lease.runId);
    if (current == null ||
        storedLease == null ||
        storedLease.workerId != lease.workerId ||
        storedLease.generation != lease.generation ||
        storedLease.tokenId != lease.tokenId ||
        !storedLease.expiresAt.isAfter(_clock.nowUtc())) {
      throw const RemoteStateException('worker does not own an active lease');
    }
    if (!_allowedTransitions[current.state]!.contains(next)) {
      throw RemoteStateException(
        'invalid remote transition ${current.state.name} -> ${next.name}',
      );
    }
    final updated = _copyRun(
      current,
      state: next,
      updatedAt: _clock.nowUtc(),
      failureCode: failureCode,
    );
    await transaction.replaceRun(updated, current.state);
    if (updated.terminal) {
      await _requestCleanup(transaction, updated, _clock.nowUtc());
      await transaction.removeLease(updated.id, lease.generation);
    }
    return updated;
  });

  Future<RemoteRun> complete(
    RemoteLease lease, {
    required RemoteArtifactManifest artifacts,
    required RemoteContainmentReport containment,
  }) => _repository.inTenantTransaction(lease.tenantId, (transaction) async {
    final storedLease = await transaction.leaseFor(lease.runId);
    final current = await transaction.runById(lease.runId);
    if (current == null ||
        storedLease == null ||
        storedLease.workerId != lease.workerId ||
        storedLease.generation != lease.generation ||
        storedLease.tokenId != lease.tokenId ||
        !storedLease.expiresAt.isAfter(_clock.nowUtc())) {
      throw const RemoteStateException('worker does not own an active lease');
    }
    final plan = await transaction.planFor(lease.runId);
    if (current.state != RemoteRunState.uploading ||
        artifacts.tenantId != lease.tenantId ||
        artifacts.runId != lease.runId ||
        artifacts.executionFingerprintDigest !=
            plan.executionFingerprintDigest ||
        containment.tenantId != lease.tenantId ||
        containment.runId != lease.runId ||
        !containment.defaultDenyEgress ||
        !containment.ephemeralStorageWiped ||
        containment.leaseRevoked) {
      throw const RemoteStateException(
        'remote completion evidence is incomplete or inconsistent',
      );
    }
    final authoritativeContainment = RemoteContainmentReport(
      tenantId: containment.tenantId,
      runId: containment.runId,
      namespace: containment.namespace,
      serviceAccount: containment.serviceAccount,
      podSecurityProfile: containment.podSecurityProfile,
      defaultDenyEgress: containment.defaultDenyEgress,
      allowedEndpointClasses: containment.allowedEndpointClasses,
      ephemeralStorageWiped: containment.ephemeralStorageWiped,
      leaseRevoked: true,
      observedAt: _clock.nowUtc(),
    );
    await transaction.putCompletion(
      artifacts: artifacts,
      containment: authoritativeContainment,
    );
    final updated = _copyRun(
      current,
      state: RemoteRunState.succeeded,
      updatedAt: _clock.nowUtc(),
    );
    await transaction.replaceRun(updated, RemoteRunState.uploading);
    await _requestCleanup(transaction, updated, _clock.nowUtc());
    await transaction.removeLease(updated.id, lease.generation);
    return updated;
  });

  Future<RemoteRun> cancel(HostedRequestContext context, String runId) =>
      _repository.inTenantTransaction(context.tenantId, (transaction) async {
        final current = await transaction.runById(runId);
        if (current == null) {
          throw const RemoteStateException('remote run not found');
        }
        final request = await transaction.requestFor(runId);
        if (request.requestedBy != context.principalId) {
          throw const HostedAuthorizationException(
            'only the requesting principal may cancel this remote run',
          );
        }
        if (current.terminal) return current;
        final updated = _copyRun(
          current,
          state: RemoteRunState.cancelled,
          updatedAt: _clock.nowUtc(),
          failureCode: 'cancelled_by_principal',
        );
        await transaction.replaceRun(updated, current.state);
        final lease = await transaction.leaseFor(runId);
        if (lease != null) {
          await _requestCleanup(transaction, updated, _clock.nowUtc());
          await transaction.removeLease(runId, lease.generation);
        }
        return updated;
      });

  Future<List<RemoteRun>> reapExpiredLeases() async {
    final now = _clock.nowUtc();
    final output = <RemoteRun>[];
    for (final tenantId in await _repository.tenantsWithExpiredLeases(now)) {
      output.addAll(
        await _repository.inTenantTransaction(tenantId, (transaction) async {
          final reaped = <RemoteRun>[];
          for (final lease in await transaction.expiredLeases(now)) {
            final current = await transaction.runById(lease.runId);
            if (current == null || current.terminal) {
              await transaction.removeLease(lease.runId, lease.generation);
              continue;
            }
            final retry =
                current.mode == RemoteRunMode.batch && current.attempt < 3;
            final updated = _copyRun(
              current,
              state: retry ? RemoteRunState.queued : RemoteRunState.unknown,
              updatedAt: now,
              workerId: retry ? null : current.workerId,
              clearWorker: retry,
              failureCode: retry ? null : 'worker_lease_expired',
            );
            await transaction.replaceRun(updated, current.state);
            await _requestCleanup(transaction, updated, now);
            await transaction.removeLease(lease.runId, lease.generation);
            reaped.add(updated);
          }
          return reaped;
        }),
      );
    }
    return output;
  }

  Future<List<String>> tenantsReadyForDispatch() =>
      _repository.tenantsWithQueuedRuns();

  Future<List<RemoteCleanupTask>> cleanupsReady({int limit = 32}) async {
    if (limit < 1 || limit > 256) {
      throw ArgumentError('cleanup limit must be 1-256');
    }
    final now = _clock.nowUtc();
    final output = <RemoteCleanupTask>[];
    for (final tenantId in await _repository.tenantsWithPendingCleanups(now)) {
      if (output.length >= limit) break;
      output.addAll(
        await _repository.inTenantTransaction(
          tenantId,
          (transaction) =>
              transaction.readyCleanups(now, limit - output.length),
        ),
      );
    }
    return List<RemoteCleanupTask>.unmodifiable(output);
  }

  Future<void> acknowledgeCleanup(RemoteCleanupTask task) =>
      _repository.inTenantTransaction(
        task.tenantId,
        (transaction) => transaction.completeCleanup(task),
      );

  Future<void> deferCleanup(RemoteCleanupTask task) {
    final exponent = task.attempts.clamp(0, 8);
    final seconds = 1 << exponent;
    final delay = Duration(seconds: seconds.clamp(1, 300));
    return _repository.inTenantTransaction(
      task.tenantId,
      (transaction) => transaction.deferCleanup(
        task,
        availableAt: _clock.nowUtc().add(delay),
        failureCode: 'namespace_cleanup_failed',
      ),
    );
  }

  Future<void> _requestCleanup(
    RemoteSchedulerTransaction transaction,
    RemoteRun run,
    DateTime now,
  ) async {
    if (run.attempt == 0) return;
    await transaction.putCleanup(
      RemoteCleanupTask(
        tenantId: run.tenantId,
        runId: run.id,
        generation: run.attempt,
        requestedAt: now,
        availableAt: now,
        attempts: 0,
      ),
    );
  }

  RemoteRun _copyRun(
    RemoteRun source, {
    required RemoteRunState state,
    required DateTime updatedAt,
    int? attempt,
    String? workerId,
    bool clearWorker = false,
    String? failureCode,
  }) => RemoteRun(
    tenantId: source.tenantId,
    id: source.id,
    requestDigest: source.requestDigest,
    planDigest: source.planDigest,
    target: source.target,
    mode: source.mode,
    state: state,
    attempt: attempt ?? source.attempt,
    createdAt: source.createdAt,
    updatedAt: updatedAt,
    workerId: clearWorker ? null : workerId ?? source.workerId,
    failureCode: failureCode,
  );

  static const Map<RemoteRunState, Set<RemoteRunState>> _allowedTransitions =
      <RemoteRunState, Set<RemoteRunState>>{
        RemoteRunState.queued: <RemoteRunState>{
          RemoteRunState.scheduled,
          RemoteRunState.cancelled,
        },
        RemoteRunState.scheduled: <RemoteRunState>{
          RemoteRunState.provisioning,
          RemoteRunState.failed,
          RemoteRunState.cancelled,
        },
        RemoteRunState.provisioning: <RemoteRunState>{
          RemoteRunState.running,
          RemoteRunState.failed,
          RemoteRunState.cancelled,
        },
        RemoteRunState.running: <RemoteRunState>{
          RemoteRunState.uploading,
          RemoteRunState.failed,
          RemoteRunState.cancelled,
        },
        RemoteRunState.uploading: <RemoteRunState>{
          RemoteRunState.failed,
          RemoteRunState.cancelled,
        },
        RemoteRunState.succeeded: <RemoteRunState>{},
        RemoteRunState.failed: <RemoteRunState>{},
        RemoteRunState.cancelled: <RemoteRunState>{},
        RemoteRunState.unknown: <RemoteRunState>{},
      };
}
