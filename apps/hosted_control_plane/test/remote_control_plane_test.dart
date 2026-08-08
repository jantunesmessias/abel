import 'dart:convert';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:hosted_control_plane/hosted_control_plane.dart';
import 'package:jose/jose.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test(
    'OIDC enqueue and capability-bound worker completion stay tenant scoped',
    () async {
      final clock = _Clock(DateTime.utc(2026, 8, 9, 12));
      final hosted = InMemoryHostedCollaborationRepository()
        ..seedMembership(
          Membership(
            tenantId: 'tenant-a',
            principalId: 'principal-a',
            role: MembershipRole.editor,
            createdAt: clock.nowUtc(),
          ),
        )
        ..seedMembership(
          Membership(
            tenantId: 'tenant-a',
            principalId: 'principal-viewer',
            role: MembershipRole.viewer,
            createdAt: clock.nowUtc(),
          ),
        );
      final remote = InMemoryRemoteSchedulerRepository();
      final generated = JsonWebKey.generate('RS256');
      final security = JoseRemoteExecutionSecurity(
        signingKey: generated,
        keyId: 'remote-key-001',
        algorithm: 'RS256',
      );
      final public = JsonWebKey.fromJson(<String, dynamic>{
        ...JsonWebKey.fromCryptoKeys(
          publicKey: generated.cryptoKeyPair.publicKey,
        ).toJson(),
        'kid': 'remote-key-001',
      });
      final verifier = RemoteWorkerTokenVerifier(
        trustedKeys: JsonWebKeySet.fromJson(<String, Object?>{
          'keys': <Object?>[public.toJson()],
        }),
        allowedAlgorithms: const <String>{'RS256'},
        clock: clock,
      );
      final scheduler = RemoteSchedulerService(
        repository: remote,
        quotas: const StaticRemoteQuotaPolicy(),
        signer: security,
        capabilities: security,
        clock: clock,
        ids: _Ids(),
      );
      final handler = HostedControlPlaneApplication(
        collaboration: HostedCollaborationService(
          repository: hosted,
          clock: clock,
          ids: _Ids(),
        ),
        objectStore: S3CompatibleObjectStore(
          configuration: S3ObjectStoreConfiguration(
            endpoint: Uri.parse('https://objects.example.test'),
            bucket: 'workspace-artifacts',
            region: 'us-test-1',
            credentials: const S3Credentials(
              accessKeyId: 'access',
              secretAccessKey: 'secret',
            ),
          ),
          clock: clock,
        ),
        identities: const _Identities(),
        principals: const _Principals(),
        ids: _Ids(),
        allowedWebSocketOrigins: const <String>{'https://studio.example.test'},
        remoteScheduler: scheduler,
        remoteTokenVerifier: verifier,
        remoteSessionTicketIssuer: security,
        remoteSessionGatewayOrigin: Uri.parse('https://gateway.example.test'),
        clock: clock,
      ).handler;
      final context = HostedRequestContext(
        tenantId: 'tenant-a',
        principalId: 'principal-a',
        correlationId: 'correlation-001',
      );
      final input = RemoteArtifactInput(
        role: 'webBuild',
        digest: Digest.semantic('web-build'),
        size: 1024,
        mediaType: 'application/zip',
      );
      final executionRequest = RemoteExecutionRequest(
        tenantId: context.tenantId,
        id: 'request-001',
        workspaceId: 'workspace-a',
        requestedBy: context.principalId,
        target: RemoteTargetKind.web,
        mode: RemoteRunMode.batch,
        interactiveTransport: RemoteInteractiveTransport.none,
        priority: 50,
        maximumDurationSeconds: 300,
        artifacts: <RemoteArtifactInput>[input],
        requestedAt: clock.nowUtc(),
      );
      final fingerprint = Digest.semantic('fingerprint');
      final enqueue = await handler(
        _oidcRequest(
          'POST',
          '/v1/remote/runs',
          token: 'editor-token',
          body: <String, Object?>{
            'request': executionRequest.toJson(),
            'executionFingerprintDigest': fingerprint.value,
            'containmentPolicyDigest': Digest.semantic('containment').value,
          },
        ),
      );
      expect(enqueue.statusCode, 202);
      final run = RemoteRun.fromJson(
        (jsonDecode(await enqueue.readAsString())
            as Map<String, Object?>)['run'],
      );
      final assignment = await scheduler.acquire(
        'tenant-a',
        RemoteWorkerDescriptor(
          id: 'worker-001',
          pool: 'web',
          targets: const <RemoteTargetKind>{RemoteTargetKind.web},
          maximumLeases: 1,
          lastHeartbeatAt: clock.nowUtc(),
        ),
      );
      expect(assignment, isNotNull);

      final crossTenant = await handler(
        _workerRequest(
          '/v1/remote/tenants/tenant-b/workers/worker-001/runs/${run.id}/state',
          assignment!.capabilityToken,
          <String, Object?>{'state': 'provisioning'},
        ),
      );
      expect(crossTenant.statusCode, 401);
      for (final state in <RemoteRunState>[
        RemoteRunState.provisioning,
        RemoteRunState.running,
        RemoteRunState.uploading,
      ]) {
        final response = await handler(
          _workerRequest(
            '/v1/remote/tenants/tenant-a/workers/worker-001/runs/${run.id}/state',
            assignment.capabilityToken,
            <String, Object?>{'state': state.name},
          ),
        );
        expect(response.statusCode, 200);
      }
      final outputDigest = Digest.semantic('screenshot');
      final manifest = RemoteArtifactManifest(
        tenantId: 'tenant-a',
        runId: run.id,
        executionFingerprintDigest: fingerprint,
        interactiveTransport: RemoteInteractiveTransport.none,
        artifacts: <HostedBlobDescriptor>[
          HostedBlobDescriptor(
            tenantId: 'tenant-a',
            digest: outputDigest,
            size: 2048,
            mediaType: 'image/png',
            classification: 'internal',
            objectKey:
                'tenants/tenant-a/blobs/sha256/${outputDigest.value.substring(7)}',
          ),
        ],
        createdAt: clock.nowUtc(),
      );
      final containment = RemoteContainmentReport(
        tenantId: 'tenant-a',
        runId: run.id,
        namespace: remoteNamespaceFor('tenant-a', run.id),
        serviceAccount: 'worker',
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
      );
      final forgedContainment = RemoteContainmentReport(
        tenantId: containment.tenantId,
        runId: containment.runId,
        namespace: 'workspace-run-forged',
        serviceAccount: containment.serviceAccount,
        podSecurityProfile: containment.podSecurityProfile,
        defaultDenyEgress: containment.defaultDenyEgress,
        allowedEndpointClasses: containment.allowedEndpointClasses,
        ephemeralStorageWiped: containment.ephemeralStorageWiped,
        leaseRevoked: containment.leaseRevoked,
        observedAt: containment.observedAt,
      );
      final forgedCompletion = await handler(
        _workerRequest(
          '/v1/remote/tenants/tenant-a/workers/worker-001/runs/${run.id}/complete',
          assignment.capabilityToken,
          <String, Object?>{
            'artifacts': manifest.toJson(),
            'containment': forgedContainment.toJson(),
            'interactiveTransport': 'none',
          },
        ),
      );
      expect(forgedCompletion.statusCode, 400);
      expect(remote.run('tenant-a', run.id)!.state, RemoteRunState.uploading);
      final completed = await handler(
        _workerRequest(
          '/v1/remote/tenants/tenant-a/workers/worker-001/runs/${run.id}/complete',
          assignment.capabilityToken,
          <String, Object?>{
            'artifacts': manifest.toJson(),
            'containment': containment.toJson(),
            'interactiveTransport': 'none',
          },
        ),
      );
      expect(completed.statusCode, 200);
      expect(remote.run('tenant-a', run.id)!.state, RemoteRunState.succeeded);
      expect(remote.lease('tenant-a', run.id), isNull);

      final interactiveRequest = RemoteExecutionRequest(
        tenantId: 'tenant-a',
        id: 'request-interactive',
        workspaceId: 'workspace-a',
        requestedBy: 'principal-a',
        target: RemoteTargetKind.web,
        mode: RemoteRunMode.interactive,
        interactiveTransport: RemoteInteractiveTransport.webDirect,
        priority: 50,
        maximumDurationSeconds: 300,
        artifacts: <RemoteArtifactInput>[input],
        requestedAt: clock.nowUtc(),
      );
      final interactiveResponse = await handler(
        _oidcRequest(
          'POST',
          '/v1/remote/runs',
          token: 'editor-token',
          body: <String, Object?>{
            'request': interactiveRequest.toJson(),
            'executionFingerprintDigest': fingerprint.value,
            'containmentPolicyDigest': Digest.semantic('containment').value,
          },
        ),
      );
      final interactiveRun = RemoteRun.fromJson(
        (jsonDecode(await interactiveResponse.readAsString())
            as Map<String, Object?>)['run'],
      );
      final interactiveAssignment = await scheduler.acquire(
        'tenant-a',
        RemoteWorkerDescriptor(
          id: 'worker-interactive',
          pool: 'web',
          targets: const <RemoteTargetKind>{RemoteTargetKind.web},
          maximumLeases: 1,
          lastHeartbeatAt: clock.nowUtc(),
        ),
      );
      await scheduler.transition(
        interactiveAssignment!.lease,
        RemoteRunState.provisioning,
      );
      await scheduler.transition(
        interactiveAssignment.lease,
        RemoteRunState.running,
      );
      final ticketResponse = await handler(
        _oidcRequest(
          'POST',
          '/v1/remote/runs/${interactiveRun.id}/session-ticket',
          token: 'viewer-token',
          body: const <String, Object?>{},
        ),
      );
      expect(ticketResponse.statusCode, 201);
      final ticketJson =
          (jsonDecode(await ticketResponse.readAsString())
                  as Map<String, Object?>)['session']!
              as Map<String, Object?>;
      expect(
        ticketJson['endpoint'],
        'wss://gateway.example.test/v1/sessions/${interactiveRun.id}/viewer',
      );
      expect(ticketJson['protocol'], RemoteSessionGrant.protocol);
      final verifiedTicket = await verifier.verifyViewerTicket(
        ticketJson['ticket']! as String,
        runId: interactiveRun.id,
      );
      expect(verifiedTicket.principalId, 'principal-viewer');
      expect(
        verifiedTicket.allowedTransports,
        const <RemoteInteractiveTransport>{
          RemoteInteractiveTransport.webDirect,
        },
      );

      final viewerRequest = RemoteExecutionRequest(
        tenantId: 'tenant-a',
        id: 'request-viewer',
        workspaceId: 'workspace-a',
        requestedBy: 'principal-viewer',
        target: RemoteTargetKind.web,
        mode: RemoteRunMode.batch,
        interactiveTransport: RemoteInteractiveTransport.none,
        priority: 50,
        maximumDurationSeconds: 300,
        artifacts: <RemoteArtifactInput>[input],
        requestedAt: clock.nowUtc(),
      );
      final viewer = await handler(
        _oidcRequest(
          'POST',
          '/v1/remote/runs',
          token: 'viewer-token',
          body: <String, Object?>{
            'request': viewerRequest.toJson(),
            'executionFingerprintDigest': fingerprint.value,
            'containmentPolicyDigest': Digest.semantic('containment').value,
          },
        ),
      );
      expect(viewer.statusCode, 403);
    },
  );
}

Request _oidcRequest(
  String method,
  String path, {
  required String token,
  required Map<String, Object?> body,
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: <String, String>{
    'authorization': 'Bearer $token',
    'x-workspace-tenant': 'tenant-a',
    'content-type': 'application/json',
  },
  body: jsonEncode(body),
);

Request _workerRequest(
  String path,
  String capability,
  Map<String, Object?> body,
) => Request(
  'POST',
  Uri.parse('http://localhost$path'),
  headers: <String, String>{
    'authorization': 'Bearer $capability',
    'content-type': 'application/json',
  },
  body: jsonEncode(body),
);

final class _Identities implements HostedIdentityVerifier {
  const _Identities();

  @override
  Future<OidcIdentity> verifyBearerToken(String compactToken) async =>
      OidcIdentity(
        issuer: Uri.parse('https://issuer.example.test'),
        subject: switch (compactToken) {
          'editor-token' => 'subject-a',
          'viewer-token' => 'subject-viewer',
          _ => throw const OidcAuthenticationException('invalid token'),
        },
        displayName: 'test',
        expiresAt: DateTime.utc(2026, 8, 9, 13),
        claims: const <String, Object?>{},
      );
}

final class _Principals implements HostedPrincipalDirectory {
  const _Principals();

  @override
  Future<String?> resolvePrincipal({
    required String tenantId,
    required Uri issuer,
    required String subject,
  }) async => switch ((tenantId, subject)) {
    ('tenant-a', 'subject-a') => 'principal-a',
    ('tenant-a', 'subject-viewer') => 'principal-viewer',
    _ => null,
  };
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
