import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import 'kubernetes_remote_job.dart';

final class RemoteKubernetesDispatcher {
  const RemoteKubernetesDispatcher({
    required this.scheduler,
    required this.builder,
    required this.launcher,
    required this.clock,
    required this.webCapacity,
    required this.androidCapacity,
  });

  final RemoteSchedulerService scheduler;
  final KubernetesRemoteJobBuilder builder;
  final RemoteJobLauncher launcher;
  final Clock clock;
  final int webCapacity;
  final int androidCapacity;

  Future<List<RemoteAssignment>> dispatchOnce() async {
    if (webCapacity < 0 || androidCapacity < 0) {
      throw StateError('remote dispatcher capacities must not be negative');
    }
    final assignments = <RemoteAssignment>[];
    for (final tenantId in await scheduler.tenantsReadyForDispatch()) {
      await _fill(
        tenantId,
        target: RemoteTargetKind.androidEmulator,
        capacity: androidCapacity,
        output: assignments,
      );
      await _fill(
        tenantId,
        target: RemoteTargetKind.web,
        capacity: webCapacity,
        output: assignments,
      );
    }
    return List<RemoteAssignment>.unmodifiable(assignments);
  }

  Future<void> _fill(
    String tenantId, {
    required RemoteTargetKind target,
    required int capacity,
    required List<RemoteAssignment> output,
  }) async {
    if (capacity == 0) return;
    final worker = RemoteWorkerDescriptor(
      id: 'k8s-${target.name}',
      pool: target == RemoteTargetKind.web ? 'web' : 'android-kvm',
      targets: <RemoteTargetKind>{target},
      maximumLeases: capacity,
      lastHeartbeatAt: clock.nowUtc(),
    );
    for (var index = 0; index < capacity; index++) {
      final assignment = await scheduler.acquire(tenantId, worker);
      if (assignment == null) return;
      final bundle = builder.build(assignment);
      try {
        await launcher.launch(bundle);
        output.add(assignment);
      } on Object {
        try {
          await launcher.cleanup(bundle.namespace);
        } on Object {
          // The namespace janitor is the second cleanup line. The run still
          // becomes failed so it can never be interpreted as successful.
        }
        await scheduler.transition(
          assignment.lease,
          RemoteRunState.failed,
          failureCode: 'kubernetes_launch_failed',
        );
      }
    }
  }
}
