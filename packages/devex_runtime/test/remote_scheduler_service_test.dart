import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:jose/jose.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryRemoteSchedulerRepository repository;
  late _MutableClock clock;
  late RemoteSchedulerService scheduler;
  late RemoteWorkerTokenVerifier verifier;
  late JoseRemoteExecutionSecurity security;

  setUp(() {
    repository = InMemoryRemoteSchedulerRepository();
    clock = _MutableClock(DateTime.utc(2026, 8, 9, 12));
    final generated = JsonWebKey.generate('RS256');
    security = JoseRemoteExecutionSecurity(
      signingKey: generated,
      keyId: 'remote-signing-001',
      algorithm: 'RS256',
    );
    final publicKey = JsonWebKey.fromJson(<String, dynamic>{
      ...JsonWebKey.fromCryptoKeys(
        publicKey: generated.cryptoKeyPair.publicKey,
      ).toJson(),
      'kid': 'remote-signing-001',
    });
    verifier = RemoteWorkerTokenVerifier(
      trustedKeys: JsonWebKeySet.fromJson(<String, Object?>{
        'keys': <Object?>[publicKey.toJson()],
      }),
      allowedAlgorithms: const <String>{'RS256'},
      clock: clock,
    );
    scheduler = RemoteSchedulerService(
      repository: repository,
      quotas: const StaticRemoteQuotaPolicy(),
      signer: security,
      capabilities: security,
      clock: clock,
      ids: _Ids(),
    );
  });

  test(
    'signed assignment is exclusive and reaches one terminal success',
    () async {
      final context = _context('tenant-a', 'principal-a');
      final run = await scheduler.enqueue(
        context,
        _request(context, 'request-001'),
        executionFingerprintDigest: Digest.semantic('fingerprint'),
        containmentPolicyDigest: Digest.semantic('deny-default-egress-v1'),
      );
      expect(run.state, RemoteRunState.queued);
      final worker = RemoteWorkerDescriptor(
        id: 'worker-001',
        pool: 'web-pool',
        targets: const <RemoteTargetKind>{RemoteTargetKind.web},
        maximumLeases: 1,
        lastHeartbeatAt: clock.nowUtc(),
      );
      final assignment = await scheduler.acquire('tenant-a', worker);
      expect(assignment, isNotNull);
      expect(await scheduler.acquire('tenant-a', worker), isNull);
      final plan = await verifier.verifyPlan(
        assignment!.signedPlan.compactSignature,
      );
      expect(plan.digest, assignment.signedPlan.plan.digest);
      final capability = await verifier.verifyCapability(
        assignment.capabilityToken,
        plan: plan,
        workerId: worker.id,
        requiredScopes: const <String>{'artifact:read', 'run:complete'},
      );
      expect(capability.tenantId, 'tenant-a');
      expect(capability.artifactDigests, plan.artifactDigests.toSet());

      var current = await scheduler.transition(
        assignment.lease,
        RemoteRunState.provisioning,
      );
      current = await scheduler.transition(
        assignment.lease,
        RemoteRunState.running,
      );
      current = await scheduler.transition(
        assignment.lease,
        RemoteRunState.uploading,
      );
      current = await scheduler.complete(
        assignment.lease,
        artifacts: RemoteArtifactManifest(
          tenantId: 'tenant-a',
          runId: run.id,
          executionFingerprintDigest: plan.executionFingerprintDigest,
          interactiveTransport: RemoteInteractiveTransport.none,
          artifacts: <HostedBlobDescriptor>[
            HostedBlobDescriptor(
              tenantId: 'tenant-a',
              digest: Digest.semantic('remote-screenshot'),
              size: 1024,
              mediaType: 'image/png',
              classification: 'internal',
              objectKey:
                  'tenants/tenant-a/blobs/sha256/'
                  '${Digest.semantic('remote-screenshot').value.substring(7)}',
            ),
          ],
          createdAt: clock.nowUtc(),
        ),
        containment: RemoteContainmentReport(
          tenantId: 'tenant-a',
          runId: run.id,
          namespace: 'devex-run-001',
          serviceAccount: 'worker-001',
          podSecurityProfile: 'restricted',
          defaultDenyEgress: true,
          allowedEndpointClasses: const <String>{
            'gateway',
            'artifact',
            'control',
            'dns',
          },
          ephemeralStorageWiped: true,
          leaseRevoked: false,
          observedAt: clock.nowUtc(),
        ),
      );
      expect(current.state, RemoteRunState.succeeded);
      expect(current.terminal, isTrue);
      expect(repository.lease('tenant-a', current.id), isNull);
      expect(
        repository.containment('tenant-a', current.id)!.leaseRevoked,
        isTrue,
      );
      expect(
        () => scheduler.transition(assignment.lease, RemoteRunState.succeeded),
        throwsA(isA<RemoteStateException>()),
      );
    },
  );

  test(
    'session tickets and stream-writer capabilities are audience-bound',
    () async {
      final context = _context('tenant-a', 'principal-a');
      final run = await scheduler.enqueue(
        context,
        _request(
          context,
          'session-request-001',
          mode: RemoteRunMode.interactive,
        ),
        executionFingerprintDigest: Digest.semantic('session-fingerprint'),
        containmentPolicyDigest: Digest.semantic('session-containment'),
      );
      final assignment = await scheduler.acquire(
        context.tenantId,
        RemoteWorkerDescriptor(
          id: 'worker-001',
          pool: 'web-pool',
          targets: const <RemoteTargetKind>{RemoteTargetKind.web},
          maximumLeases: 1,
          lastHeartbeatAt: clock.nowUtc(),
        ),
      );
      final writer = await verifier.verifyStreamWriter(
        assignment!.capabilityToken,
        runId: run.id,
      );
      expect(writer.tenantId, context.tenantId);
      expect(writer.workerId, 'worker-001');

      final ticket = RemoteSessionTicket(
        tenantId: context.tenantId,
        runId: run.id,
        principalId: context.principalId,
        role: RemoteSessionRole.viewer,
        allowedTransports: const <RemoteInteractiveTransport>{
          RemoteInteractiveTransport.webDirect,
        },
        issuedAt: clock.nowUtc(),
        expiresAt: clock.nowUtc().add(const Duration(minutes: 1)),
        nonce: 'viewer-ticket-001',
      );
      final compact = await security.issueViewerTicket(ticket);
      expect(
        (await verifier.verifyViewerTicket(compact, runId: run.id)).tenantId,
        context.tenantId,
      );
      await expectLater(
        verifier.verifyStreamWriter(compact, runId: run.id),
        throwsA(isA<RemoteStateException>()),
      );
      await expectLater(
        verifier.verifyViewerTicket(assignment.capabilityToken, runId: run.id),
        throwsA(isA<RemoteStateException>()),
      );
    },
  );

  test(
    'expired batch lease retries; expired interactive lease becomes unknown',
    () async {
      final context = _context('tenant-a', 'principal-a');
      final worker = RemoteWorkerDescriptor(
        id: 'worker-001',
        pool: 'web-pool',
        targets: const <RemoteTargetKind>{RemoteTargetKind.web},
        maximumLeases: 2,
        lastHeartbeatAt: clock.nowUtc(),
      );
      final batch = await scheduler.enqueue(
        context,
        _request(context, 'request-batch'),
        executionFingerprintDigest: Digest.semantic('fingerprint'),
        containmentPolicyDigest: Digest.semantic('containment'),
      );
      final batchAssignment = await scheduler.acquire(
        'tenant-a',
        worker,
        leaseTtl: const Duration(seconds: 20),
      );
      expect(batchAssignment!.run.id, batch.id);
      clock.advance(const Duration(seconds: 21));
      final firstReap = await scheduler.reapExpiredLeases();
      expect(firstReap.single.state, RemoteRunState.queued);
      expect(firstReap.single.attempt, 1);
      await scheduler.cancel(context, batch.id);

      final interactive = await scheduler.enqueue(
        context,
        _request(
          context,
          'request-interactive',
          mode: RemoteRunMode.interactive,
        ),
        executionFingerprintDigest: Digest.semantic('fingerprint'),
        containmentPolicyDigest: Digest.semantic('containment'),
      );
      final interactiveAssignment = await scheduler.acquire(
        'tenant-a',
        worker,
        leaseTtl: const Duration(seconds: 20),
      );
      expect(interactiveAssignment!.run.id, interactive.id);
      clock.advance(const Duration(seconds: 21));
      final secondReap = await scheduler.reapExpiredLeases();
      expect(
        secondReap.singleWhere((run) => run.id == interactive.id).state,
        RemoteRunState.unknown,
      );
      expect(
        repository.run('tenant-a', interactive.id)!.failureCode,
        'worker_lease_expired',
      );
    },
  );

  test('quota and authenticated tenant binding fail closed', () async {
    final context = _context('tenant-a', 'principal-a');
    expect(
      () => scheduler.enqueue(
        context,
        _request(_context('tenant-b', 'principal-b'), 'request-cross'),
        executionFingerprintDigest: Digest.semantic('fingerprint'),
        containmentPolicyDigest: Digest.semantic('containment'),
      ),
      throwsA(isA<HostedAuthorizationException>()),
    );
    await scheduler.enqueue(
      context,
      _request(context, 'interactive-001', mode: RemoteRunMode.interactive),
      executionFingerprintDigest: Digest.semantic('fingerprint'),
      containmentPolicyDigest: Digest.semantic('containment'),
    );
    expect(
      () => scheduler.enqueue(
        context,
        _request(context, 'interactive-002', mode: RemoteRunMode.interactive),
        executionFingerprintDigest: Digest.semantic('fingerprint'),
        containmentPolicyDigest: Digest.semantic('containment'),
      ),
      throwsA(isA<RemoteQuotaException>()),
    );
  });

  test(
    'expired queued plans fail explicitly and cancellation is owner-bound',
    () async {
      final owner = _context('tenant-a', 'principal-a');
      final run = await scheduler.enqueue(
        owner,
        _request(owner, 'expiring-001'),
        executionFingerprintDigest: Digest.semantic('fingerprint'),
        containmentPolicyDigest: Digest.semantic('containment'),
      );
      expect(
        () => scheduler.cancel(_context('tenant-a', 'principal-b'), run.id),
        throwsA(isA<HostedAuthorizationException>()),
      );
      clock.advance(const Duration(minutes: 6));
      final assignment = await scheduler.acquire(
        'tenant-a',
        RemoteWorkerDescriptor(
          id: 'worker-001',
          pool: 'web-pool',
          targets: const <RemoteTargetKind>{RemoteTargetKind.web},
          maximumLeases: 1,
          lastHeartbeatAt: clock.nowUtc(),
        ),
      );
      expect(assignment, isNull);
      expect(repository.run('tenant-a', run.id)!.state, RemoteRunState.failed);
      expect(
        repository.run('tenant-a', run.id)!.failureCode,
        'plan_expired_before_schedule',
      );
    },
  );
}

HostedRequestContext _context(String tenant, String principal) =>
    HostedRequestContext(
      tenantId: tenant,
      principalId: principal,
      correlationId: 'correlation-001',
    );

RemoteExecutionRequest _request(
  HostedRequestContext context,
  String id, {
  RemoteRunMode mode = RemoteRunMode.batch,
}) => RemoteExecutionRequest(
  tenantId: context.tenantId,
  id: id,
  workspaceId: 'workspace-a',
  requestedBy: context.principalId,
  target: RemoteTargetKind.web,
  mode: mode,
  interactiveTransport: mode == RemoteRunMode.interactive
      ? RemoteInteractiveTransport.webDirect
      : RemoteInteractiveTransport.none,
  priority: 50,
  maximumDurationSeconds: 300,
  artifacts: <RemoteArtifactInput>[
    RemoteArtifactInput(
      role: 'webBuild',
      digest: Digest.semantic('$id-web-build'),
      size: 1024,
      mediaType: 'application/zip',
    ),
  ],
  requestedAt: DateTime.utc(2026, 8, 9, 12),
);

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
