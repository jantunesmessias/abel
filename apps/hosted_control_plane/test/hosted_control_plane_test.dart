import 'dart:convert';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:hosted_control_plane/hosted_control_plane.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Handler handler;
  final base = Digest.semantic('base');

  setUp(() {
    final repository = InMemoryHostedCollaborationRepository()
      ..seedMembership(
        Membership(
          tenantId: 'tenant-a',
          principalId: 'principal-a',
          role: MembershipRole.editor,
          createdAt: DateTime.utc(2026, 8, 9),
        ),
      )
      ..seedMembership(
        Membership(
          tenantId: 'tenant-b',
          principalId: 'principal-b',
          role: MembershipRole.editor,
          createdAt: DateTime.utc(2026, 8, 9),
        ),
      )
      ..seedWorkspaceHead(
        tenantId: 'tenant-a',
        workspaceId: 'workspace-a',
        digest: base,
      )
      ..seedWorkspaceHead(
        tenantId: 'tenant-b',
        workspaceId: 'workspace-a',
        digest: base,
      );
    final clock = _FixedClock(DateTime.utc(2026, 8, 9, 12));
    handler = HostedControlPlaneApplication(
      collaboration: HostedCollaborationService(
        repository: repository,
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
    ).handler;
  });

  test(
    'authenticated push returns conflict instead of silent overwrite',
    () async {
      final proposed = Digest.semantic('proposal-a');
      final first = await handler(
        _request(
          'POST',
          '/v1/workspaces/workspace-a/push',
          token: 'token-a',
          tenant: 'tenant-a',
          body: _change('tenant-a', 'principal-a', base, proposed, 'idem-001'),
        ),
      );
      expect(first.statusCode, 200);
      final firstJson =
          jsonDecode(await first.readAsString()) as Map<String, Object?>;
      expect(firstJson['ok'], isTrue);

      final second = await handler(
        _request(
          'POST',
          '/v1/workspaces/workspace-a/push',
          token: 'token-a',
          tenant: 'tenant-a',
          body: _change(
            'tenant-a',
            'principal-a',
            base,
            Digest.semantic('proposal-b'),
            'idem-002',
          ),
        ),
      );
      expect(second.statusCode, 409);
      final conflict =
          jsonDecode(await second.readAsString()) as Map<String, Object?>;
      expect(conflict['code'], 'CONTROL_PLANE_CONFLICT');
      expect(
        (conflict['conflict']! as Map<String, Object?>).keys,
        containsAll(<String>['baseDigest', 'currentDigest', 'proposedDigest']),
      );
    },
  );

  test(
    'authentication, principal membership, and tenant replay fail closed',
    () async {
      final unauthenticated = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/workspaces/workspace-a/events'),
        ),
      );
      expect(unauthenticated.statusCode, 401);

      final mismatched = await handler(
        _request(
          'GET',
          '/v1/workspaces/workspace-a/events',
          token: 'token-a',
          tenant: 'tenant-b',
        ),
      );
      expect(mismatched.statusCode, 403);

      await handler(
        _request(
          'POST',
          '/v1/workspaces/workspace-a/push',
          token: 'token-a',
          tenant: 'tenant-a',
          body: _change(
            'tenant-a',
            'principal-a',
            base,
            Digest.semantic('private-a'),
            'idem-003',
          ),
        ),
      );
      final tenantB = await handler(
        _request(
          'GET',
          '/v1/workspaces/workspace-a/events?after=0',
          token: 'token-b',
          tenant: 'tenant-b',
        ),
      );
      final body =
          jsonDecode(await tenantB.readAsString()) as Map<String, Object?>;
      expect(body['events'], isEmpty);
    },
  );

  test('artifact grant is HTTPS, scoped, short-lived, and uncached', () async {
    final digest = Digest.semantic('blob');
    final response = await handler(
      _request(
        'POST',
        '/v1/artifacts/upload-grants',
        token: 'token-a',
        tenant: 'tenant-a',
        body: <String, Object?>{
          'digest': digest.value,
          'size': 4,
          'mediaType': 'application/octet-stream',
          'classification': 'internal',
        },
      ),
    );
    expect(response.statusCode, 201);
    expect(response.headers['cache-control'], 'no-store');
    final json =
        jsonDecode(await response.readAsString()) as Map<String, Object?>;
    final transfer = json['transfer']! as Map<String, Object?>;
    expect(transfer['url'], startsWith('https://objects.example.test/'));
    expect(transfer['url'], contains('/tenants/tenant-a/'));
  });
}

Request _request(
  String method,
  String path, {
  required String token,
  required String tenant,
  Map<String, Object?>? body,
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: <String, String>{
    'authorization': 'Bearer $token',
    'x-workspace-tenant': tenant,
    if (body != null) 'content-type': 'application/json',
  },
  body: body == null ? null : jsonEncode(body),
);

Map<String, Object?> _change(
  String tenant,
  String principal,
  Digest expected,
  Digest proposed,
  String key,
) => WorkspaceChangeSet(
  tenantId: tenant,
  workspaceId: 'workspace-a',
  baseDigest: expected,
  expectedDigest: expected,
  proposedDigest: proposed,
  principalId: principal,
  idempotencyKey: key,
  metadata: const <String, Object?>{'source': 'api-test'},
).toJson();

final class _Identities implements HostedIdentityVerifier {
  const _Identities();

  @override
  Future<OidcIdentity> verifyBearerToken(String compactToken) async {
    final subject = switch (compactToken) {
      'token-a' => 'subject-a',
      'token-b' => 'subject-b',
      _ => throw const OidcAuthenticationException('invalid token'),
    };
    return OidcIdentity(
      issuer: Uri.parse('https://issuer.example.test'),
      subject: subject,
      displayName: subject,
      expiresAt: DateTime.utc(2026, 8, 9, 13),
      claims: const <String, Object?>{},
    );
  }
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
    ('tenant-b', 'subject-b') => 'principal-b',
    _ => null,
  };
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

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
