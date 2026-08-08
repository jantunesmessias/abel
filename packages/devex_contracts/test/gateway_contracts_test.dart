import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixtureBytes = utf8.encode('{"id":"synthetic"}');
  final plan = _plan(fixtureBytes);

  test('CompiledGatewayPlan round-trips with a verified semantic digest', () {
    final decoded = CompiledGatewayPlan.fromJson(plan.toJson());

    expect(decoded.digest, plan.digest);
    expect(decoded.backendMode, BackendMode.isolated);
    expect(decoded.networkContainment, NetworkContainment.gatewayOnly);
    expect(decoded.fixtures.single.bodyDigest, Digest.bytes(fixtureBytes));
  });

  test('Gateway plan artifact descriptor is closed and round-trips', () {
    final descriptor = GatewayPlanArtifactDescriptor(
      presetId: plan.preset.id,
      description: plan.preset.description,
      backendMode: plan.backendMode,
      routeCount: plan.routes.length,
      planDigest: plan.digest,
      artifactDigest: Digest.semantic(const <String, Object?>{
        'artifact': 'gateway-plan',
      }),
    );

    expect(
      GatewayPlanArtifactDescriptor.fromJson(descriptor.toJson()).toJson(),
      descriptor.toJson(),
    );
    expect(
      () => GatewayPlanArtifactDescriptor.fromJson(
        descriptor.toJson()..['workspacePath'] = '/secret',
      ),
      throwsFormatException,
    );
  });

  test('GatewaySession and UpstreamProfile round-trip as strict documents', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    final session = GatewaySession(
      id: 'gateway-1',
      ownerSessionId: 'session-1',
      planDigest: plan.digest,
      state: GatewaySessionState.running,
      createdAt: now,
      updatedAt: now.add(const Duration(seconds: 1)),
      activeScopeId: plan.scope.id,
    );
    final profile = UpstreamProfile(
      id: UpstreamProfileId('integration'),
      environment: UpstreamEnvironment.test,
      origins: <String, Uri>{
        'accounts': Uri.parse('https://accounts.example.test'),
      },
      updatedAt: now,
      credentialHandleId: 'credential.integration',
    );

    expect(GatewaySession.fromJson(session.toJson()).digest, session.digest);
    expect(UpstreamProfile.fromJson(profile.toJson()).digest, profile.digest);

    final tampered = session.toJson()..['activeScopeId'] = 'other';
    expect(() => GatewaySession.fromJson(tampered), throwsFormatException);
    final production = profile.toJson()..['environment'] = 'production';
    expect(() => UpstreamProfile.fromJson(production), throwsFormatException);
  });

  test('Gateway runtime contracts fail closed on unsafe state and origins', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    expect(
      () => GatewaySession(
        id: 'gateway-1',
        ownerSessionId: 'session-1',
        planDigest: plan.digest,
        state: GatewaySessionState.running,
        createdAt: now,
        updatedAt: now,
      ),
      throwsArgumentError,
    );
    expect(
      () => UpstreamProfile(
        id: UpstreamProfileId('integration'),
        environment: UpstreamEnvironment.staging,
        origins: <String, Uri>{
          'accounts': Uri.parse('https://secret@example.test'),
        },
        updatedAt: now,
      ),
      throwsFormatException,
    );
  });

  test(
    'rejects plan tampering, unknown fields, and unsafe fixture headers',
    () {
      final tampered = plan.toJson();
      tampered['backendMode'] = 'hybrid';
      expect(
        () => CompiledGatewayPlan.fromJson(tampered),
        throwsFormatException,
      );

      final unknown = plan.toJson()..['unknown'] = true;
      expect(
        () => CompiledGatewayPlan.fromJson(unknown),
        throwsFormatException,
      );

      expect(
        () => GatewayFixture(
          id: GatewayFixtureId('unsafe'),
          status: 200,
          headers: const <String, String>{'authorization': 'secret'},
          bodyDigest: Digest.bytes(const <int>[]),
          bodySize: 0,
          mediaType: 'application/json',
        ),
        throwsFormatException,
      );
    },
  );

  test('emitted Gateway documents conform to the public V1 schema', () {
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'v1',
                'gateway-plan.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );
    final routing = RoutingTable(
      scopeId: plan.scope.id,
      presetId: plan.preset.id,
      entries: <GatewayRouteId, GatewayRoutingDecision>{
        plan.routes.single.id: GatewayRoutingDecision.mock,
      },
    );
    final response = GatewayResponse(
      status: 200,
      headers: const <String, String>{'content-type': 'application/json'},
      body: fixtureBytes,
      outcome: GatewayOutcome.mock,
      routeId: plan.routes.single.id,
      presetId: plan.preset.id,
    );
    final verification = VerificationReport(
      planDigest: plan.digest,
      requestMethod: 'GET',
      requestPath: '/users/7',
      response: response,
    );
    final traffic = TrafficEvent(
      sequence: 1,
      gatewaySessionId: 'gateway-1',
      monotonicMicroseconds: 1,
      method: 'GET',
      routeTemplate: '/users/{id}',
      routeId: plan.routes.single.id,
      outcome: GatewayOutcome.mock,
      status: 200,
      durationMicroseconds: 2,
      requestSize: 0,
      responseSize: fixtureBytes.length,
      redactionSummary: 'headers=omitted;body=omitted',
    );
    final now = DateTime.utc(2026, 8, 9, 12);
    final session = GatewaySession(
      id: 'gateway-1',
      ownerSessionId: 'session-1',
      planDigest: plan.digest,
      state: GatewaySessionState.running,
      createdAt: now,
      updatedAt: now,
      activeScopeId: plan.scope.id,
    );
    final profile = UpstreamProfile(
      id: UpstreamProfileId('integration'),
      environment: UpstreamEnvironment.test,
      origins: <String, Uri>{
        'accounts': Uri.parse('https://accounts.example.test'),
      },
      updatedAt: now,
      credentialHandleId: 'credential.integration',
    );

    final hybrid = _hybridPlan();
    for (final document in <Map<String, Object?>>[
      plan.toJson(),
      hybrid.toJson(),
      routing.toJson(),
      verification.toJson(),
      traffic.toJson(),
      session.toJson(),
      profile.toJson(),
    ]) {
      final result = validator.validate(document);
      expect(result.isValid, isTrue, reason: '${result.issues}\n$document');
    }
    expect(
      validator.validate(<String, Object?>{
        ...plan.toJson(),
        'extra': 1,
      }).isValid,
      isFalse,
    );
  });
}

CompiledGatewayPlan _hybridPlan() {
  final scopeId = GatewayScopeId('remote');
  final presetId = GatewayPresetId('hybrid');
  final route = GatewayRoute(
    id: GatewayRouteId('remote-config'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/config',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.upstreamOnly,
    fixtureId: null,
    upstreamProfileId: UpstreamProfileId('integration'),
  );
  return CompiledGatewayPlan(
    scope: GatewayScope(
      id: scopeId,
      displayName: 'Remote',
      routeIds: <GatewayRouteId>[route.id],
    ),
    preset: GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Hybrid',
      routeIds: <GatewayRouteId>[route.id],
    ),
    routes: <GatewayRoute>[route],
    fixtures: const <GatewayFixture>[],
    backendMode: BackendMode.hybrid,
    networkContainment: NetworkContainment.gatewayOnly,
  );
}

CompiledGatewayPlan _plan(List<int> fixtureBytes) {
  final scopeId = GatewayScopeId('accounts');
  final presetId = GatewayPresetId('default');
  final route = GatewayRoute(
    id: GatewayRouteId('get-user'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/users/{id}',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('user'),
  );
  return CompiledGatewayPlan(
    scope: GatewayScope(
      id: scopeId,
      displayName: 'Accounts',
      routeIds: <GatewayRouteId>[route.id],
    ),
    preset: GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Default',
      routeIds: <GatewayRouteId>[route.id],
    ),
    routes: <GatewayRoute>[route],
    fixtures: <GatewayFixture>[
      GatewayFixture(
        id: GatewayFixtureId('user'),
        status: 200,
        headers: const <String, String>{'content-type': 'application/json'},
        bodyDigest: Digest.bytes(fixtureBytes),
        bodySize: fixtureBytes.length,
        mediaType: 'application/json',
      ),
    ],
    backendMode: BackendMode.isolated,
    networkContainment: NetworkContainment.gatewayOnly,
  );
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
