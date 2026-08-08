import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  late _Clock clock;
  late SessionCaptureVault vault;

  setUp(() {
    clock = _Clock();
    vault = SessionCaptureVault(clock: clock, ids: _Ids());
  });

  tearDown(() => vault.close());

  test('binds captured hints to principal, target, generation, and TTL', () {
    final descriptor = vault.capture(
      principalId: 'reviewer',
      targetId: 'web-target',
      targetGeneration: 'account-1:revision-1',
      hints: const <String, String>{
        'Authorization': 'Bearer synthetic-session',
        'x-csrf-token': 'synthetic-csrf',
      },
      ttl: const Duration(minutes: 5),
    );

    final material = vault.resolve(
      captureId: descriptor.id,
      principalId: 'reviewer',
      targetId: 'web-target',
      targetGeneration: 'account-1:revision-1',
    );

    expect(material.value('authorization'), 'Bearer synthetic-session');
    expect(material.toString(), '<redacted-session-material>');
    expect(descriptor.toJson().toString(), isNot(contains('Bearer')));
    expect(descriptor.toJson(), containsPair('storage', 'processMemoryOnly'));
    expect(
      () => vault.resolve(
        captureId: descriptor.id,
        principalId: 'another',
        targetId: 'web-target',
        targetGeneration: 'account-1:revision-1',
      ),
      throwsStateError,
    );

    clock.advance(const Duration(minutes: 6));
    expect(vault.activeCount, 0);
  });

  test(
    'invalidates on target/account context change and rejects unknown hints',
    () {
      final descriptor = vault.capture(
        principalId: 'reviewer',
        targetId: 'web-target',
        targetGeneration: 'account-1',
        hints: const <String, String>{'x-session-id': 'synthetic'},
        ttl: const Duration(minutes: 5),
      );

      expect(vault.invalidateTarget('web-target'), 1);
      expect(
        () => vault.resolve(
          captureId: descriptor.id,
          principalId: 'reviewer',
          targetId: 'web-target',
          targetGeneration: 'account-1',
        ),
        throwsStateError,
      );
      expect(
        () => vault.capture(
          principalId: 'reviewer',
          targetId: 'web-target',
          targetGeneration: 'account-1',
          hints: const <String, String>{'cookie': 'forbidden'},
          ttl: const Duration(minutes: 5),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'feeds an allowlisted hybrid request without exposing its value',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) async {
        expect(request.headers.value('authorization'), 'Bearer captured');
        request.response.statusCode = 204;
        await request.response.close();
      });
      final descriptor = vault.capture(
        principalId: 'reviewer',
        targetId: 'web-target',
        targetGeneration: 'account-1',
        hints: const <String, String>{'authorization': 'Bearer captured'},
        ttl: const Duration(minutes: 5),
      );
      final endpoint = GatewayUpstreamEndpoint(
        profileId: UpstreamProfileId('captured'),
        baseUri: Uri.parse('http://127.0.0.1:${upstream.port}'),
        allowedHost: '127.0.0.1',
        environment: UpstreamEnvironment.development,
        allowPrivateAddresses: true,
        credentialHandle: 'session:authorization',
      );
      final handler = SafeHttpGatewayUpstreamHandler(
        endpoints: <UpstreamProfileId, GatewayUpstreamEndpoint>{
          endpoint.profileId: endpoint,
        },
        credentials: NamespacedCredentialResolver(
          environment: EnvironmentCredentialResolver(environment: const {}),
          session: SessionCaptureCredentialResolver(
            vault: vault,
            captureId: descriptor.id,
            principalId: 'reviewer',
            targetId: 'web-target',
            targetGeneration: 'account-1',
          ),
        ),
      );
      final route = GatewayRoute(
        id: GatewayRouteId('captured'),
        scopeId: GatewayScopeId('scope'),
        method: 'GET',
        pathTemplate: '/captured',
        requiredQuery: const <String, String>{},
        appliesTo: <GatewayPresetId>{GatewayPresetId('default')},
        policy: GatewayRoutePolicy.upstreamOnly,
        fixtureId: null,
        upstreamProfileId: endpoint.profileId,
      );

      final result = await handler.handle(
        route: route,
        request: GatewayRequest(
          method: 'GET',
          path: '/captured',
          query: const <String, List<String>>{},
          body: const <int>[],
        ),
        pathParameters: const <String, String>{},
        runtimeState: const <String, Object?>{},
      );

      expect(result.status, 204);
      expect(
        endpoint.redactedStatus().toString(),
        isNot(contains('session:authorization')),
      );
      expect(descriptor.toJson().toString(), isNot(contains('Bearer')));
    },
  );
}

final class _Ids implements IdGenerator {
  var next = 1;

  @override
  String nextId() => '${next++}';
}

final class _Clock implements Clock {
  var value = DateTime.utc(2026, 8, 9, 15);

  void advance(Duration duration) => value = value.add(duration);

  @override
  int monotonicMicroseconds() => value.microsecondsSinceEpoch;

  @override
  DateTime nowUtc() => value;
}
