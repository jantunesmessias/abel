import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'dispatches queued work and launch failure is terminal with cleanup',
    () async {
      final repository = InMemoryRemoteSchedulerRepository();
      final clock = _Clock(DateTime.utc(2026, 8, 9, 12));
      final scheduler = RemoteSchedulerService(
        repository: repository,
        quotas: const StaticRemoteQuotaPolicy(),
        signer: const _Security(),
        capabilities: const _Security(),
        clock: clock,
        ids: _Ids(),
      );
      final context = HostedRequestContext(
        tenantId: 'tenant-a',
        principalId: 'principal-a',
        correlationId: 'correlation-001',
      );
      final first = await scheduler.enqueue(
        context,
        _request(context, 'request-001'),
        executionFingerprintDigest: Digest.semantic('fingerprint-001'),
        containmentPolicyDigest: Digest.semantic('containment-001'),
      );
      final second = await scheduler.enqueue(
        context,
        _request(context, 'request-002'),
        executionFingerprintDigest: Digest.semantic('fingerprint-002'),
        containmentPolicyDigest: Digest.semantic('containment-002'),
      );
      final launcher = _Launcher()..failRunId = second.id;
      final dispatcher = RemoteKubernetesDispatcher(
        scheduler: scheduler,
        builder: KubernetesRemoteJobBuilder(
          KubernetesRemoteJobConfiguration(
            webWorkerImage:
                'registry.example.test/workspace-worker-web@sha256:'
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            androidWorkerImage:
                'registry.example.test/workspace-worker-android@sha256:'
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            controlPlaneOrigin: Uri.parse('https://control.example.test'),
            artifactOrigin: Uri.parse('https://artifacts.example.test'),
            gatewayOrigin: Uri.parse('https://gateway.example.test'),
            trustedJwksJson:
                '{"keys":[{"kty":"EC","crv":"P-256","x":"x","y":"y"}]}',
            androidImageDigest: Digest.semantic('android-image'),
            androidScrcpyServerDigest: Digest.semantic('scrcpy-server'),
            allowedStudioOrigins: const <String>['https://studio.example.test'],
            allowedEgressCidrs: const <String>['10.0.0.0/24'],
          ),
        ),
        launcher: launcher,
        clock: clock,
        webCapacity: 2,
        androidCapacity: 0,
      );

      final dispatched = await dispatcher.dispatchOnce();
      expect(dispatched.map((assignment) => assignment.run.id), <String>[
        first.id,
      ]);
      expect(
        repository.run('tenant-a', first.id)!.state,
        RemoteRunState.scheduled,
      );
      expect(
        repository.run('tenant-a', second.id)!.state,
        RemoteRunState.failed,
      );
      expect(
        repository.run('tenant-a', second.id)!.failureCode,
        'kubernetes_launch_failed',
      );
      expect(launcher.cleaned, hasLength(1));
    },
  );
}

RemoteExecutionRequest _request(HostedRequestContext context, String id) =>
    RemoteExecutionRequest(
      tenantId: context.tenantId,
      id: id,
      workspaceId: 'workspace-a',
      requestedBy: context.principalId,
      target: RemoteTargetKind.web,
      mode: RemoteRunMode.batch,
      interactiveTransport: RemoteInteractiveTransport.none,
      priority: id.endsWith('001') ? 100 : 50,
      maximumDurationSeconds: 300,
      artifacts: <RemoteArtifactInput>[
        RemoteArtifactInput(
          role: 'webBuild',
          digest: Digest.semantic('$id-web'),
          size: 100,
          mediaType: 'application/zip',
        ),
      ],
      requestedAt: DateTime.utc(2026, 8, 9, 12),
    );

final class _Launcher implements RemoteJobLauncher {
  String? failRunId;
  final List<String> cleaned = <String>[];

  @override
  Future<void> cleanup(String namespace) async => cleaned.add(namespace);

  @override
  Future<void> launch(KubernetesRemoteJobBundle bundle) async {
    if (bundle.runId == failRunId) throw StateError('synthetic launch failure');
  }
}

final class _Security implements RemotePlanSigner, RemoteCapabilityIssuer {
  const _Security();

  @override
  Future<String> issue({
    required RemoteExecutionPlan plan,
    required RemoteLease lease,
    required Set<String> scopes,
  }) async => 'capability-${lease.runId}';

  @override
  Future<SignedRemoteExecutionPlan> sign(RemoteExecutionPlan plan) async =>
      SignedRemoteExecutionPlan(
        plan: plan,
        compactSignature: 'plan-${plan.runId}',
        signerKeyId: 'test-key',
      );
}

final class _Clock implements Clock {
  const _Clock(this.value);

  final DateTime value;

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
