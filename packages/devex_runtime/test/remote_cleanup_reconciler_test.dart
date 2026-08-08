import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('cleanup failure backs off and acknowledgement is idempotent', () async {
    final fixture = _Fixture();
    final run = await fixture.enqueue('run-failure');
    final assignment = await fixture.acquire();
    await fixture.scheduler.transition(
      assignment.lease,
      RemoteRunState.failed,
      failureCode: 'synthetic_failure',
    );
    expect(fixture.repository.cleanupTasks('tenant-a'), hasLength(1));

    fixture.launcher.failuresRemaining = 1;
    final reconciler = fixture.reconciler();
    final failed = await reconciler.reconcileOnce();
    expect(failed.deferred, 1);
    final deferred = fixture.repository.cleanupTasks('tenant-a').single;
    expect(deferred.attempts, 1);
    expect(deferred.lastFailureCode, 'namespace_cleanup_failed');
    expect(await reconciler.reconcileOnce(), _emptyCycle);

    fixture.clock.advance(const Duration(seconds: 1));
    final recovered = await reconciler.reconcileOnce();
    expect(recovered.cleaned, 1);
    expect(fixture.repository.cleanupTasks('tenant-a'), isEmpty);
    expect(
      fixture.launcher.cleaned.last,
      remoteNamespaceFor('tenant-a', run.id),
    );
  });

  test(
    'expired worker cannot be retried before old namespace is gone',
    () async {
      final fixture = _Fixture();
      final run = await fixture.enqueue('run-node-loss');
      final first = await fixture.acquire(
        leaseTtl: const Duration(seconds: 20),
      );
      fixture.clock.advance(const Duration(seconds: 21));
      final reaped = await fixture.scheduler.reapExpiredLeases();
      expect(reaped.single.state, RemoteRunState.queued);
      expect(await fixture.acquireOrNull(), isNull);

      expect((await fixture.reconciler().reconcileOnce()).cleaned, 1);
      final second = await fixture.acquire();
      expect(second.run.id, run.id);
      expect(second.lease.generation, first.lease.generation + 1);
    },
  );

  test(
    'soak cleanup leaves no durable task after mixed terminal phases',
    () async {
      final fixture = _Fixture();
      const runs = 80;
      for (var index = 0; index < runs; index++) {
        await fixture.enqueue('soak-$index');
        final assignment = await fixture.acquire();
        if (index % 4 >= 1) {
          await fixture.scheduler.transition(
            assignment.lease,
            RemoteRunState.provisioning,
          );
        }
        if (index % 4 >= 2) {
          await fixture.scheduler.transition(
            assignment.lease,
            RemoteRunState.running,
          );
        }
        if (index % 4 == 3) {
          await fixture.scheduler.transition(
            assignment.lease,
            RemoteRunState.uploading,
          );
        }
        if (index.isEven) {
          await fixture.scheduler.cancel(fixture.context, assignment.run.id);
        } else {
          await fixture.scheduler.transition(
            assignment.lease,
            RemoteRunState.failed,
            failureCode: 'soak_failure',
          );
        }
      }
      expect(fixture.repository.cleanupTasks('tenant-a'), hasLength(runs));

      final reconciler = fixture.reconciler(maximumPerCycle: 11);
      var inspected = 0;
      while (fixture.repository.cleanupTasks('tenant-a').isNotEmpty) {
        inspected += (await reconciler.reconcileOnce()).inspected;
      }
      expect(inspected, runs);
      expect(fixture.launcher.cleaned.toSet(), hasLength(runs));
    },
  );
}

final _emptyCycle = isA<RemoteCleanupCycle>()
    .having((cycle) => cycle.inspected, 'inspected', 0)
    .having((cycle) => cycle.cleaned, 'cleaned', 0)
    .having((cycle) => cycle.deferred, 'deferred', 0);

final class _Fixture {
  final InMemoryRemoteSchedulerRepository repository =
      InMemoryRemoteSchedulerRepository();
  final _MutableClock clock = _MutableClock(DateTime.utc(2026, 8, 9, 12));
  final _Ids ids = _Ids();
  final _Launcher launcher = _Launcher();
  late final RemoteSchedulerService scheduler = RemoteSchedulerService(
    repository: repository,
    quotas: const StaticRemoteQuotaPolicy(),
    signer: const _Security(),
    capabilities: const _Security(),
    clock: clock,
    ids: ids,
  );
  final HostedRequestContext context = const HostedRequestContext(
    tenantId: 'tenant-a',
    principalId: 'principal-a',
    correlationId: 'cleanup-test',
  );

  Future<RemoteRun> enqueue(String requestId) => scheduler.enqueue(
    context,
    RemoteExecutionRequest(
      tenantId: context.tenantId,
      id: requestId,
      workspaceId: 'workspace-a',
      requestedBy: context.principalId,
      target: RemoteTargetKind.web,
      mode: RemoteRunMode.batch,
      interactiveTransport: RemoteInteractiveTransport.none,
      priority: 50,
      maximumDurationSeconds: 300,
      artifacts: <RemoteArtifactInput>[
        RemoteArtifactInput(
          role: 'webBuild',
          digest: Digest.semantic('$requestId-build'),
          size: 10,
          mediaType: 'application/zip',
        ),
      ],
      requestedAt: clock.nowUtc(),
    ),
    executionFingerprintDigest: Digest.semantic('$requestId-fingerprint'),
    containmentPolicyDigest: Digest.semantic('$requestId-containment'),
  );

  Future<RemoteAssignment> acquire({
    Duration leaseTtl = const Duration(seconds: 60),
  }) async =>
      await acquireOrNull(leaseTtl: leaseTtl) ??
      (throw StateError('expected a remote assignment'));

  Future<RemoteAssignment?> acquireOrNull({
    Duration leaseTtl = const Duration(seconds: 60),
  }) => scheduler.acquire(
    context.tenantId,
    RemoteWorkerDescriptor(
      id: 'worker-001',
      pool: 'web',
      targets: const <RemoteTargetKind>{RemoteTargetKind.web},
      maximumLeases: 1,
      lastHeartbeatAt: clock.nowUtc(),
    ),
    leaseTtl: leaseTtl,
  );

  RemoteCleanupReconciler reconciler({int maximumPerCycle = 32}) =>
      RemoteCleanupReconciler(
        scheduler: scheduler,
        launcher: launcher,
        maximumPerCycle: maximumPerCycle,
      );
}

final class _Launcher implements RemoteJobLauncher {
  int failuresRemaining = 0;
  final List<String> cleaned = <String>[];

  @override
  Future<void> cleanup(String namespace) async {
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StateError('synthetic cleanup failure');
    }
    cleaned.add(namespace);
  }

  @override
  Future<void> launch(KubernetesRemoteJobBundle bundle) async {}
}

final class _Security implements RemotePlanSigner, RemoteCapabilityIssuer {
  const _Security();

  @override
  Future<String> issue({
    required RemoteExecutionPlan plan,
    required RemoteLease lease,
    required Set<String> scopes,
  }) async => 'capability-${lease.runId}-${lease.generation}';

  @override
  Future<SignedRemoteExecutionPlan> sign(RemoteExecutionPlan plan) async =>
      SignedRemoteExecutionPlan(
        plan: plan,
        compactSignature: 'signed-${plan.runId}',
        signerKeyId: 'test-key',
      );
}

final class _MutableClock implements Clock {
  _MutableClock(this.value);

  DateTime value;

  void advance(Duration duration) => value = value.add(duration);

  @override
  int monotonicMicroseconds() => value.microsecondsSinceEpoch;

  @override
  DateTime nowUtc() => value;
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String nextId() => 'generated-${++value}';
}
