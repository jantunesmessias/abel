import 'dart:convert';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:test/test.dart';

void main() {
  test('compiles deterministic isolated plan and round-trips its digest', () {
    final source = _catalog();
    final first = const GatewayPlanCompiler().compile(
      scope: source.scope,
      preset: source.preset,
      routes: source.routes,
      fixtures: source.fixtures,
    );
    final second = const GatewayPlanCompiler().compile(
      scope: source.scope,
      preset: source.preset,
      routes: source.routes.reversed,
      fixtures: source.fixtures.reversed,
    );

    expect(first.plan.digest, second.plan.digest);
    expect(first.routingTable.digest, second.routingTable.digest);
    expect(
      CompiledGatewayPlan.fromJson(first.plan.toJson()).digest,
      first.plan.digest,
    );
    final tampered =
        jsonDecode(jsonEncode(first.plan.toJson())) as Map<String, Object?>;
    tampered['backendMode'] = 'hybrid';
    expect(
      () => CompiledGatewayPlan.fromJson(tampered),
      anyOf(throwsArgumentError, throwsFormatException),
    );
  });

  test('rejects appliesTo mismatch and upstream route in isolated', () {
    final source = _catalog();
    final invalidPreset = GatewayPreset(
      id: source.preset.id,
      scopeId: source.scope.id,
      description: 'Invalid',
      routeIds: <GatewayRouteId>[source.routes.first.id],
    );
    expect(
      () => const GatewayPlanCompiler().compile(
        scope: source.scope,
        preset: invalidPreset,
        routes: source.routes,
        fixtures: source.fixtures,
      ),
      throwsA(isA<GatewayCompileException>()),
    );
    final upstream = GatewayRoute(
      id: source.routes.first.id,
      scopeId: source.scope.id,
      method: 'GET',
      pathTemplate: '/users/{id}',
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{source.preset.id},
      policy: GatewayRoutePolicy.upstreamOnly,
      fixtureId: null,
      upstreamProfileId: UpstreamProfileId('development'),
    );
    final upstreamScope = GatewayScope(
      id: source.scope.id,
      displayName: 'Scope',
      routeIds: <GatewayRouteId>[upstream.id],
    );
    final upstreamPreset = GatewayPreset(
      id: source.preset.id,
      scopeId: source.scope.id,
      description: 'Upstream',
      routeIds: <GatewayRouteId>[upstream.id],
    );
    expect(
      () => const GatewayPlanCompiler().compile(
        scope: upstreamScope,
        preset: upstreamPreset,
        routes: <GatewayRoute>[upstream],
        fixtures: const <GatewayFixture>[],
      ),
      throwsA(isA<GatewayCompileException>()),
    );
  });

  test('rejects route patterns that can match the same request', () {
    final presetId = GatewayPresetId('default');
    final scopeId = GatewayScopeId('accounts');
    GatewayRoute route(String id, String path) => GatewayRoute(
      id: GatewayRouteId(id),
      scopeId: scopeId,
      method: 'GET',
      pathTemplate: path,
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{presetId},
      policy: GatewayRoutePolicy.localOnly,
      fixtureId: GatewayFixtureId('fixture'),
    );
    final routes = <GatewayRoute>[
      route('by-id', '/users/{id}'),
      route('current', '/users/current'),
    ];
    final scope = GatewayScope(
      id: scopeId,
      displayName: 'Accounts',
      routeIds: routes.map((value) => value.id).toList(),
    );
    final preset = GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Default',
      routeIds: routes.map((value) => value.id).toList(),
    );

    expect(
      () => const GatewayPlanCompiler().compile(
        scope: scope,
        preset: preset,
        routes: routes,
        fixtures: <GatewayFixture>[_fixture()],
      ),
      throwsA(isA<GatewayCompileException>()),
    );
  });

  test('hybrid compiles only an explicit upstream route as passthrough', () {
    final scopeId = GatewayScopeId('remote');
    final presetId = GatewayPresetId('remote-default');
    final route = GatewayRoute(
      id: GatewayRouteId('remote-value'),
      scopeId: scopeId,
      method: 'GET',
      pathTemplate: '/remote/value',
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{presetId},
      policy: GatewayRoutePolicy.upstreamOnly,
      fixtureId: null,
      upstreamProfileId: UpstreamProfileId('development'),
    );

    final result = const GatewayPlanCompiler().compile(
      scope: GatewayScope(
        id: scopeId,
        displayName: 'Remote',
        routeIds: <GatewayRouteId>[route.id],
      ),
      preset: GatewayPreset(
        id: presetId,
        scopeId: scopeId,
        description: 'Remote default',
        routeIds: <GatewayRouteId>[route.id],
      ),
      routes: <GatewayRoute>[route],
      fixtures: const <GatewayFixture>[],
      backendMode: BackendMode.hybrid,
    );

    expect(result.plan.backendMode, BackendMode.hybrid);
    expect(result.plan.fixtures, isEmpty);
    expect(
      result.routingTable.entries[route.id],
      GatewayRoutingDecision.passthrough,
    );
  });
}

({
  GatewayScope scope,
  GatewayPreset preset,
  List<GatewayRoute> routes,
  List<GatewayFixture> fixtures,
})
_catalog() {
  final presetId = GatewayPresetId('default');
  final scopeId = GatewayScopeId('accounts');
  final routes = <GatewayRoute>[
    GatewayRoute(
      id: GatewayRouteId('get-user'),
      scopeId: scopeId,
      method: 'GET',
      pathTemplate: '/users/{id}',
      requiredQuery: const <String, String>{'view': 'summary'},
      appliesTo: <GatewayPresetId>{presetId},
      policy: GatewayRoutePolicy.localOnly,
      fixtureId: GatewayFixtureId('fixture'),
    ),
    GatewayRoute(
      id: GatewayRouteId('create-user'),
      scopeId: scopeId,
      method: 'POST',
      pathTemplate: '/users',
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{presetId},
      policy: GatewayRoutePolicy.catalogControlled,
      fixtureId: GatewayFixtureId('fixture'),
    ),
  ];
  return (
    scope: GatewayScope(
      id: scopeId,
      displayName: 'Accounts',
      routeIds: routes.map((value) => value.id).toList(),
    ),
    preset: GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Default',
      routeIds: routes.map((value) => value.id).toList(),
    ),
    routes: routes,
    fixtures: <GatewayFixture>[_fixture()],
  );
}

GatewayFixture _fixture() {
  final bytes = utf8.encode('{"id":"synthetic"}');
  return GatewayFixture(
    id: GatewayFixtureId('fixture'),
    status: 200,
    headers: const <String, String>{'content-type': 'application/json'},
    bodyDigest: Digest.bytes(bytes),
    bodySize: bytes.length,
    mediaType: 'application/json',
  );
}
