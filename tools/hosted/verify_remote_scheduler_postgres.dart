import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final adminUrl = _requiredEnvironment('CONTROL_PLANE_DATABASE_URL');
  final applicationUrl = _requiredEnvironment('REMOTE_SCHEDULER_DATABASE_URL');
  final admin = Pool<String>.withUrl(adminUrl);
  final application = Pool<String>.withUrl(applicationUrl);
  final suffix = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  final tenantA = 'remote-pg-a-$suffix';
  final tenantB = 'remote-pg-b-$suffix';
  final principal = 'principal-$suffix';
  final workspace = 'workspace-$suffix';
  final clock = _MutableClock(DateTime.now().toUtc());
  try {
    await admin.run((session) async {
      await session.execute(
        Sql.named('''
          INSERT INTO control_plane.organizations
            (tenant_id, slug, display_name, created_at)
          VALUES
            (@tenant_a:text, @slug_a:text, 'Remote PG A', @now:timestamptz),
            (@tenant_b:text, @slug_b:text, 'Remote PG B', @now:timestamptz)
        '''),
        parameters: <String, Object?>{
          'tenant_a': tenantA,
          'tenant_b': tenantB,
          'slug_a': 'remotepga$suffix',
          'slug_b': 'remotepgb$suffix',
          'now': clock.nowUtc(),
        },
      );
      for (final tenant in <String>[tenantA, tenantB]) {
        await session.execute(
          Sql.named('''
            INSERT INTO control_plane.principals
              (tenant_id, principal_id, issuer, subject, display_name, created_at)
            VALUES
              (@tenant:text, @principal:text, 'https://issuer.example.test',
               @subject:text, 'Remote principal', @now:timestamptz)
          '''),
          parameters: <String, Object?>{
            'tenant': tenant,
            'principal': principal,
            'subject': '$tenant-subject',
            'now': clock.nowUtc(),
          },
        );
        await session.execute(
          Sql.named('''
            INSERT INTO control_plane.workspaces
              (tenant_id, workspace_id, display_name, created_at, created_by)
            VALUES
              (@tenant:text, @workspace:text, 'Remote workspace',
               @now:timestamptz, @principal:text)
          '''),
          parameters: <String, Object?>{
            'tenant': tenant,
            'workspace': workspace,
            'principal': principal,
            'now': clock.nowUtc(),
          },
        );
      }
    });
    final repository = PostgresRemoteSchedulerRepository(
      tenantDatabase: application,
      schedulerDatabase: application,
    );
    final scheduler = RemoteSchedulerService(
      repository: repository,
      quotas: const StaticRemoteQuotaPolicy(),
      signer: const _Security(),
      capabilities: const _Security(),
      clock: clock,
      ids: _Ids(suffix),
    );
    final context = HostedRequestContext(
      tenantId: tenantA,
      principalId: principal,
      correlationId: 'postgres-cleanup-$suffix',
    );

    final failed = await scheduler.enqueue(
      context,
      _request(context, workspace, 'failed-$suffix', clock.nowUtc()),
      executionFingerprintDigest: Digest.semantic('pg-failed-fingerprint'),
      containmentPolicyDigest: Digest.semantic('pg-failed-containment'),
    );
    final failedAssignment = await _acquire(scheduler, tenantA, clock);
    await scheduler.transition(
      failedAssignment.lease,
      RemoteRunState.failed,
      failureCode: 'postgres_probe_failure',
    );
    final firstCleanup = (await scheduler.cleanupsReady()).single;
    _expect(
      firstCleanup.runId == failed.id,
      'terminal cleanup was not durable',
    );
    await scheduler.acknowledgeCleanup(firstCleanup);
    _expect(
      (await scheduler.cleanupsReady()).isEmpty,
      'cleanup acknowledgement was not durable',
    );

    final retrying = await scheduler.enqueue(
      context,
      _request(context, workspace, 'retry-$suffix', clock.nowUtc()),
      executionFingerprintDigest: Digest.semantic('pg-retry-fingerprint'),
      containmentPolicyDigest: Digest.semantic('pg-retry-containment'),
    );
    final firstLease = await _acquire(
      scheduler,
      tenantA,
      clock,
      leaseTtl: const Duration(seconds: 20),
    );
    clock.advance(const Duration(seconds: 21));
    final reaped = await scheduler.reapExpiredLeases();
    _expect(
      reaped.single.id == retrying.id &&
          reaped.single.state == RemoteRunState.queued,
      'expired batch lease did not become a fenced retry',
    );
    _expect(
      await _acquireOrNull(scheduler, tenantA, clock) == null,
      'retry escaped before its previous namespace was cleaned',
    );
    final retryCleanup = (await scheduler.cleanupsReady()).single;
    await scheduler.acknowledgeCleanup(retryCleanup);
    final secondLease = await _acquire(scheduler, tenantA, clock);
    _expect(
      secondLease.lease.generation == firstLease.lease.generation + 1,
      'retry lease generation was not fenced',
    );

    try {
      await scheduler.runForTenant(tenantB, failed.id);
      throw StateError('cross-tenant remote run read unexpectedly succeeded');
    } on RemoteStateException {
      // Expected: tenant context and RLS hide tenant A from tenant B.
    }
    stdout.writeln(
      'PostgreSQL remote scheduler verified: RLS, durable cleanup, retry fencing.',
    );
  } finally {
    try {
      await admin.run((session) async {
        await session.execute(
          Sql.named('''
              DELETE FROM control_plane.remote_runs
              WHERE tenant_id = ANY(@tenants:_text)
            '''),
          parameters: <String, Object?>{
            'tenants': <String>[tenantA, tenantB],
          },
        );
        await session.execute(
          Sql.named('''
              DELETE FROM control_plane.workspaces
              WHERE tenant_id = ANY(@tenants:_text)
            '''),
          parameters: <String, Object?>{
            'tenants': <String>[tenantA, tenantB],
          },
        );
        await session.execute(
          Sql.named('''
            DELETE FROM control_plane.organizations
            WHERE tenant_id = ANY(@tenants:_text)
          '''),
          parameters: <String, Object?>{
            'tenants': <String>[tenantA, tenantB],
          },
        );
      });
    } finally {
      await application.close();
      await admin.close();
    }
  }
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) throw StateError('$name is required');
  return value;
}

RemoteExecutionRequest _request(
  HostedRequestContext context,
  String workspace,
  String id,
  DateTime now,
) => RemoteExecutionRequest(
  tenantId: context.tenantId,
  id: id,
  workspaceId: workspace,
  requestedBy: context.principalId,
  target: RemoteTargetKind.web,
  mode: RemoteRunMode.batch,
  interactiveTransport: RemoteInteractiveTransport.none,
  priority: 50,
  maximumDurationSeconds: 300,
  artifacts: <RemoteArtifactInput>[
    RemoteArtifactInput(
      role: 'webBuild',
      digest: Digest.semantic('$id-build'),
      size: 1024,
      mediaType: 'application/zip',
    ),
  ],
  requestedAt: now,
);

Future<RemoteAssignment> _acquire(
  RemoteSchedulerService scheduler,
  String tenantId,
  Clock clock, {
  Duration leaseTtl = const Duration(seconds: 60),
}) async =>
    await _acquireOrNull(scheduler, tenantId, clock, leaseTtl: leaseTtl) ??
    (throw StateError('expected a PostgreSQL-backed assignment'));

Future<RemoteAssignment?> _acquireOrNull(
  RemoteSchedulerService scheduler,
  String tenantId,
  Clock clock, {
  Duration leaseTtl = const Duration(seconds: 60),
}) => scheduler.acquire(
  tenantId,
  RemoteWorkerDescriptor(
    id: 'postgres-worker',
    pool: 'web',
    targets: const <RemoteTargetKind>{RemoteTargetKind.web},
    maximumLeases: 1,
    lastHeartbeatAt: clock.nowUtc(),
  ),
  leaseTtl: leaseTtl,
);

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final class _Security implements RemotePlanSigner, RemoteCapabilityIssuer {
  const _Security();

  @override
  Future<String> issue({
    required RemoteExecutionPlan plan,
    required RemoteLease lease,
    required Set<String> scopes,
  }) async => 'postgres-test-capability';

  @override
  Future<SignedRemoteExecutionPlan> sign(RemoteExecutionPlan plan) async =>
      SignedRemoteExecutionPlan(
        plan: plan,
        compactSignature: 'postgres-test-plan',
        signerKeyId: 'postgres-test-key',
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
  _Ids(this.suffix);

  final String suffix;
  int value = 0;

  @override
  String nextId() => 'pg-$suffix-${++value}';
}
