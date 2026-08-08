import 'package:experience_engine/experience_engine.dart';

import 'kubernetes_remote_job.dart';

final class RemoteCleanupCycle {
  const RemoteCleanupCycle({
    required this.inspected,
    required this.cleaned,
    required this.deferred,
  });

  final int inspected;
  final int cleaned;
  final int deferred;
}

/// Reconciles durable cleanup tasks with Kubernetes. A task is acknowledged
/// only after the launcher has observed that the complete run namespace no
/// longer exists. Namespace deletion covers the Job, pod, Secret, Service,
/// HTTPRoute, ConfigMap, ServiceAccount, NetworkPolicy, and ephemeral volumes.
final class RemoteCleanupReconciler {
  const RemoteCleanupReconciler({
    required this.scheduler,
    required this.launcher,
    this.maximumPerCycle = 32,
  });

  final RemoteSchedulerService scheduler;
  final RemoteJobLauncher launcher;
  final int maximumPerCycle;

  Future<RemoteCleanupCycle> reconcileOnce() async {
    if (maximumPerCycle < 1 || maximumPerCycle > 256) {
      throw StateError('cleanup reconciler limit must be 1-256');
    }
    final tasks = await scheduler.cleanupsReady(limit: maximumPerCycle);
    var cleaned = 0;
    var deferred = 0;
    for (final task in tasks) {
      try {
        await launcher.cleanup(remoteNamespaceFor(task.tenantId, task.runId));
        await scheduler.acknowledgeCleanup(task);
        cleaned += 1;
      } on Object {
        await scheduler.deferCleanup(task);
        deferred += 1;
      }
    }
    return RemoteCleanupCycle(
      inspected: tasks.length,
      cleaned: cleaned,
      deferred: deferred,
    );
  }
}
