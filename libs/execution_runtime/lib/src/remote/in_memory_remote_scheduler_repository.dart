import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

final class InMemoryRemoteSchedulerRepository
    implements RemoteSchedulerRepository {
  final Map<String, _RemoteTenantState> _tenants =
      <String, _RemoteTenantState>{};
  Future<void> _tail = Future<void>.value();

  RemoteRun? run(String tenantId, String runId) =>
      _tenants[tenantId]?.runs[runId];

  RemoteLease? lease(String tenantId, String runId) =>
      _tenants[tenantId]?.leases[runId];

  RemoteContainmentReport? containment(String tenantId, String runId) =>
      _tenants[tenantId]?.containmentReports[runId];

  List<RemoteCleanupTask> cleanupTasks(String tenantId) =>
      List<RemoteCleanupTask>.unmodifiable(
        _tenants[tenantId]?.cleanups.values ?? const <RemoteCleanupTask>[],
      );

  @override
  Future<T> inTenantTransaction<T>(
    String tenantId,
    Future<T> Function(RemoteSchedulerTransaction transaction) operation,
  ) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    try {
      final working = (_tenants[tenantId] ?? _RemoteTenantState()).copy();
      final result = await operation(_InMemoryRemoteTransaction(working));
      _tenants[tenantId] = working;
      return result;
    } finally {
      release.complete();
    }
  }

  @override
  Future<List<String>> tenantsWithExpiredLeases(DateTime now) async {
    final tenants = <String>[
      for (final entry in _tenants.entries)
        if (entry.value.leases.values.any(
          (lease) => !lease.expiresAt.isAfter(now),
        ))
          entry.key,
    ]..sort();
    return tenants;
  }

  @override
  Future<List<String>> tenantsWithQueuedRuns() async {
    final tenants = <String>[
      for (final entry in _tenants.entries)
        if (entry.value.runs.values.any(
          (run) => run.state == RemoteRunState.queued,
        ))
          entry.key,
    ]..sort();
    return tenants;
  }

  @override
  Future<List<String>> tenantsWithPendingCleanups(DateTime now) async {
    final tenants = <String>[
      for (final entry in _tenants.entries)
        if (entry.value.cleanups.values.any(
          (task) => !task.availableAt.isAfter(now),
        ))
          entry.key,
    ]..sort();
    return tenants;
  }
}

final class _RemoteTenantState {
  final Map<Digest, RemoteExecutionRequest> requests =
      <Digest, RemoteExecutionRequest>{};
  final Map<String, RemoteExecutionPlan> plans =
      <String, RemoteExecutionPlan>{};
  final Map<String, RemoteRun> runs = <String, RemoteRun>{};
  final Map<String, RemoteLease> leases = <String, RemoteLease>{};
  final Map<String, RemoteArtifactManifest> artifactManifests =
      <String, RemoteArtifactManifest>{};
  final Map<String, RemoteContainmentReport> containmentReports =
      <String, RemoteContainmentReport>{};
  final Map<String, RemoteCleanupTask> cleanups = <String, RemoteCleanupTask>{};

  _RemoteTenantState copy() {
    final result = _RemoteTenantState();
    result.requests.addAll(requests);
    result.plans.addAll(plans);
    result.runs.addAll(runs);
    result.leases.addAll(leases);
    result.artifactManifests.addAll(artifactManifests);
    result.containmentReports.addAll(containmentReports);
    result.cleanups.addAll(cleanups);
    return result;
  }
}

final class _InMemoryRemoteTransaction implements RemoteSchedulerTransaction {
  const _InMemoryRemoteTransaction(this.state);

  final _RemoteTenantState state;

  static const Set<RemoteRunState> _concurrent = <RemoteRunState>{
    RemoteRunState.scheduled,
    RemoteRunState.provisioning,
    RemoteRunState.running,
    RemoteRunState.uploading,
  };

  @override
  Future<int> countQueued() async => state.runs.values
      .where((run) => run.state == RemoteRunState.queued)
      .length;

  @override
  Future<int> countConcurrent() async =>
      state.runs.values.where((run) => _concurrent.contains(run.state)).length;

  @override
  Future<int> countInteractive() async => state.runs.values
      .where((run) => run.mode == RemoteRunMode.interactive && !run.terminal)
      .length;

  @override
  Future<void> insert({
    required RemoteExecutionRequest request,
    required RemoteExecutionPlan plan,
    required RemoteRun run,
  }) async {
    if (request.tenantId != run.tenantId ||
        plan.tenantId != run.tenantId ||
        request.digest != run.requestDigest ||
        plan.digest != run.planDigest ||
        state.runs.containsKey(run.id)) {
      throw StateError('remote insert invariants failed');
    }
    state.requests[request.digest] = request;
    state.plans[run.id] = plan;
    state.runs[run.id] = run;
  }

  @override
  Future<List<RemoteRun>> queuedFor(Set<RemoteTargetKind> targets) async {
    final output =
        state.runs.values
            .where(
              (run) =>
                  run.state == RemoteRunState.queued &&
                  !state.cleanups.values.any((task) => task.runId == run.id) &&
                  targets.contains(run.target),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final leftRequest = state.requests[left.requestDigest]!;
            final rightRequest = state.requests[right.requestDigest]!;
            final priority = rightRequest.priority.compareTo(
              leftRequest.priority,
            );
            if (priority != 0) return priority;
            final time = left.createdAt.compareTo(right.createdAt);
            return time == 0 ? left.id.compareTo(right.id) : time;
          });
    return List<RemoteRun>.unmodifiable(output);
  }

  @override
  Future<RemoteExecutionPlan> planFor(String runId) async =>
      state.plans[runId] ?? (throw StateError('remote plan not found'));

  @override
  Future<RemoteExecutionRequest> requestFor(String runId) async {
    final run = state.runs[runId];
    if (run == null) throw StateError('remote run not found');
    return state.requests[run.requestDigest] ??
        (throw StateError('remote request not found'));
  }

  @override
  Future<RemoteRun?> runById(String runId) async => state.runs[runId];

  @override
  Future<RemoteLease?> leaseFor(String runId) async => state.leases[runId];

  @override
  Future<int> activeLeaseCount(String workerId, DateTime now) async => state
      .leases
      .values
      .where(
        (lease) => lease.workerId == workerId && lease.expiresAt.isAfter(now),
      )
      .length;

  @override
  Future<void> replaceRun(RemoteRun run, RemoteRunState expectedState) async {
    final current = state.runs[run.id];
    if (current == null ||
        current.tenantId != run.tenantId ||
        current.state != expectedState) {
      throw const RemoteStateException('remote run compare-and-set failed');
    }
    state.runs[run.id] = run;
  }

  @override
  Future<void> putLease(RemoteLease lease) async {
    final run = state.runs[lease.runId];
    final previous = state.leases[lease.runId];
    if (run == null ||
        run.tenantId != lease.tenantId ||
        (previous != null &&
            (previous.workerId != lease.workerId ||
                previous.generation != lease.generation ||
                previous.tokenId != lease.tokenId))) {
      throw const RemoteStateException('exclusive remote lease rejected');
    }
    state.leases[lease.runId] = lease;
  }

  @override
  Future<void> removeLease(String runId, int generation) async {
    final current = state.leases[runId];
    if (current != null && current.generation != generation) {
      throw const RemoteStateException(
        'stale lease cannot remove current lease',
      );
    }
    state.leases.remove(runId);
  }

  @override
  Future<void> putCompletion({
    required RemoteArtifactManifest artifacts,
    required RemoteContainmentReport containment,
  }) async {
    if (artifacts.runId != containment.runId ||
        state.artifactManifests.containsKey(artifacts.runId) ||
        state.containmentReports.containsKey(containment.runId)) {
      throw const RemoteStateException('remote completion already exists');
    }
    state.artifactManifests[artifacts.runId] = artifacts;
    state.containmentReports[containment.runId] = containment;
  }

  @override
  Future<List<RemoteLease>> expiredLeases(DateTime now) async =>
      List<RemoteLease>.unmodifiable(
        state.leases.values.where((lease) => !lease.expiresAt.isAfter(now)),
      );

  @override
  Future<void> putCleanup(RemoteCleanupTask task) async {
    if (task.tenantId != state.runs[task.runId]?.tenantId) {
      throw const RemoteStateException('remote cleanup tenant mismatch');
    }
    final key = _cleanupKey(task.runId, task.generation);
    final current = state.cleanups[key];
    if (current != null &&
        (current.requestedAt != task.requestedAt || current.attempts != 0)) {
      throw const RemoteStateException('remote cleanup task conflict');
    }
    state.cleanups.putIfAbsent(key, () => task);
  }

  @override
  Future<List<RemoteCleanupTask>> readyCleanups(DateTime now, int limit) async {
    final output =
        state.cleanups.values
            .where((task) => !task.availableAt.isAfter(now))
            .toList(growable: false)
          ..sort((left, right) {
            final available = left.availableAt.compareTo(right.availableAt);
            if (available != 0) return available;
            final run = left.runId.compareTo(right.runId);
            return run == 0 ? left.generation.compareTo(right.generation) : run;
          });
    return List<RemoteCleanupTask>.unmodifiable(output.take(limit));
  }

  @override
  Future<void> completeCleanup(RemoteCleanupTask task) async {
    final key = _cleanupKey(task.runId, task.generation);
    final current = state.cleanups[key];
    if (current == null) return;
    if (!_sameCleanupRevision(current, task)) {
      throw const RemoteStateException('stale remote cleanup acknowledgement');
    }
    state.cleanups.remove(key);
  }

  @override
  Future<void> deferCleanup(
    RemoteCleanupTask task, {
    required DateTime availableAt,
    required String failureCode,
  }) async {
    final key = _cleanupKey(task.runId, task.generation);
    final current = state.cleanups[key];
    if (current == null) return;
    if (!_sameCleanupRevision(current, task)) {
      throw const RemoteStateException('stale remote cleanup deferral');
    }
    state.cleanups[key] = RemoteCleanupTask(
      tenantId: task.tenantId,
      runId: task.runId,
      generation: task.generation,
      requestedAt: task.requestedAt,
      availableAt: availableAt,
      attempts: task.attempts + 1,
      lastFailureCode: failureCode,
    );
  }

  String _cleanupKey(String runId, int generation) => '$runId:$generation';

  bool _sameCleanupRevision(
    RemoteCleanupTask? current,
    RemoteCleanupTask presented,
  ) =>
      current != null &&
      current.tenantId == presented.tenantId &&
      current.runId == presented.runId &&
      current.generation == presented.generation &&
      current.attempts == presented.attempts &&
      current.availableAt == presented.availableAt;
}
