import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  late _FakeClock clock;
  late _FakeDelay delay;
  late _MockHandler handler;
  late GatewayRuntime runtime;
  late List<int> fixtureBytes;

  setUp(() {
    clock = _FakeClock();
    delay = _FakeDelay(clock);
    fixtureBytes = utf8.encode('{"id":"synthetic"}');
    handler = _MockHandler(fixtureBytes);
    runtime = GatewayRuntime(
      gatewaySessionId: 'gateway-session-1',
      compilation: _compilation(fixtureBytes),
      mockHandler: handler,
      clock: clock,
      delay: delay,
      maxTrafficEvents: 2,
      maxTrafficBytes: 4096,
    );
  });

  test('matches method, path parameters, and required query', () async {
    final response = await runtime.handle(
      GatewayRequest(
        method: 'get',
        path: '/users/42',
        query: const <String, List<String>>{
          'view': <String>['summary'],
        },
        body: const <int>[],
      ),
    );

    expect(response.status, 200);
    expect(response.outcome, GatewayOutcome.mock);
    expect(response.body, fixtureBytes);
    expect(handler.pathParameters, <String, String>{'id': '42'});
    expect(response.headers['x-workspace-gateway'], 'mock');
  });

  test(
    'unknown and non-applicable requests are denied without a handler',
    () async {
      final wrongQuery = await runtime.handle(
        GatewayRequest(
          method: 'GET',
          path: '/users/42',
          query: const <String, List<String>>{},
          body: const <int>[],
        ),
      );
      final unknown = await runtime.handle(
        GatewayRequest(
          method: 'GET',
          path: '/outside',
          query: const <String, List<String>>{},
          body: const <int>[],
        ),
      );

      expect(wrongQuery.outcome, GatewayOutcome.unmatched);
      expect(unknown.outcome, GatewayOutcome.unmatched);
      expect(handler.calls, 0);
      expect(runtime.traffic(), hasLength(2));
      expect(
        runtime.traffic().every(
          (event) => event.redactionSummary == 'headers=omitted;body=omitted',
        ),
        isTrue,
      );
    },
  );

  test(
    'verify traverses the same handler and preserves raw response identity',
    () async {
      final request = GatewayRequest(
        method: 'GET',
        path: '/users/7',
        query: const <String, List<String>>{
          'view': <String>['summary'],
        },
        body: const <int>[],
      );
      final api = await runtime.handle(request);
      final report = await runtime.verify(request);

      expect(report.response.status, api.status);
      expect(report.response.headers, api.headers);
      expect(report.response.bodyDigest, api.bodyDigest);
      expect(handler.calls, 2);
    },
  );

  test('applies deterministic latency and explicitly evicts traffic', () async {
    final request = GatewayRequest(
      method: 'GET',
      path: '/users/7',
      query: const <String, List<String>>{
        'view': <String>['summary'],
      },
      body: const <int>[],
    );
    await runtime.handle(request);
    await runtime.handle(request);
    await runtime.handle(request);

    expect(delay.durations, <Duration>[
      for (var i = 0; i < 3; i++) const Duration(milliseconds: 5),
    ]);
    expect(runtime.traffic(), hasLength(2));
    expect(runtime.evictedEvents, 1);
    expect(runtime.traffic().first.sequence, 2);
    runtime.reset();
    expect(runtime.traffic(), isEmpty);
    expect(runtime.evictedEvents, 3);
  });

  test('enforces the default 10000 event and 64 MiB traffic quotas', () async {
    final bounded = GatewayRuntime(
      gatewaySessionId: 'gateway-bounded',
      compilation: _compilation(fixtureBytes),
      mockHandler: handler,
      clock: clock,
      delay: delay,
    );
    final request = GatewayRequest(
      method: 'GET',
      path: '/users/7',
      query: const <String, List<String>>{
        'view': <String>['summary'],
      },
      body: const <int>[],
    );

    for (var index = 0; index < 10001; index += 1) {
      await bounded.handle(request);
    }

    expect(bounded.traffic(limit: 10000), hasLength(10000));
    expect(bounded.evictedEvents, 1);
    expect(bounded.trafficBytes, lessThanOrEqualTo(64 * 1024 * 1024));
    expect(bounded.traffic(limit: 1).single.sequence, 2);
  });

  test(
    'hybrid delegates only an explicit passthrough routing decision',
    () async {
      final upstream = _FakeUpstream(utf8.encode('{"source":"upstream"}'));
      final hybrid = GatewayRuntime(
        gatewaySessionId: 'gateway-hybrid',
        compilation: _hybridCompilation(),
        mockHandler: handler,
        upstreamHandler: upstream,
        clock: clock,
        delay: delay,
      );
      final request = GatewayRequest(
        method: 'GET',
        path: '/remote/42',
        query: const <String, List<String>>{},
        body: const <int>[],
      );

      final api = await hybrid.handle(request);
      final verify = await hybrid.verify(request);
      final unknown = await hybrid.handle(
        GatewayRequest(
          method: 'GET',
          path: '/unknown',
          query: const <String, List<String>>{},
          body: const <int>[],
        ),
      );

      expect(api.outcome, GatewayOutcome.passthrough);
      expect(api.headers['x-workspace-gateway'], 'passthrough');
      expect(verify.response.bodyDigest, api.bodyDigest);
      expect(unknown.outcome, GatewayOutcome.unmatched);
      expect(upstream.calls, 2);
      expect(handler.calls, 0);
    },
  );
}

GatewayCompilation _hybridCompilation() {
  final scopeId = GatewayScopeId('remote');
  final presetId = GatewayPresetId('remote-default');
  final route = GatewayRoute(
    id: GatewayRouteId('remote-value'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/remote/{id}',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.upstreamOnly,
    fixtureId: null,
    upstreamProfileId: UpstreamProfileId('development'),
  );
  return const GatewayPlanCompiler().compile(
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
}

GatewayCompilation _compilation(List<int> fixtureBytes) {
  final presetId = GatewayPresetId('default');
  final scopeId = GatewayScopeId('accounts');
  final route = GatewayRoute(
    id: GatewayRouteId('get-user'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/users/{id}',
    requiredQuery: const <String, String>{'view': 'summary'},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('user'),
    faultProfile: GatewayFaultProfile(fixedLatencyMilliseconds: 5),
  );
  return const GatewayPlanCompiler().compile(
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
      initialState: const <String, Object?>{'epoch': 0},
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
  );
}

final class _MockHandler implements MockHandlerPort {
  _MockHandler(this.body);

  final List<int> body;
  var calls = 0;
  Map<String, String>? pathParameters;

  @override
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayFixture fixture,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  }) async {
    calls += 1;
    this.pathParameters = pathParameters;
    expect(runtimeState, <String, Object?>{'epoch': 0});
    expect(Digest.bytes(body), fixture.bodyDigest);
    return GatewayMockResult(
      status: fixture.status,
      headers: fixture.headers,
      body: body,
    );
  }
}

final class _FakeUpstream implements UpstreamHandlerPort {
  _FakeUpstream(this.body);

  final List<int> body;
  var calls = 0;

  @override
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  }) async {
    calls += 1;
    expect(route.upstreamProfileId, UpstreamProfileId('development'));
    expect(pathParameters, <String, String>{'id': '42'});
    return GatewayMockResult(
      status: 200,
      headers: const <String, String>{'content-type': 'application/json'},
      body: body,
    );
  }
}

final class _FakeDelay implements DelayPort {
  _FakeDelay(this.clock);

  final _FakeClock clock;
  final durations = <Duration>[];

  @override
  Future<void> delay(Duration duration) async {
    durations.add(duration);
    clock.elapsed += duration.inMicroseconds;
  }
}

final class _FakeClock implements Clock {
  var elapsed = 0;

  @override
  int monotonicMicroseconds() => elapsed++;

  @override
  DateTime nowUtc() =>
      DateTime.utc(2026, 8, 9).add(Duration(microseconds: elapsed));
}
