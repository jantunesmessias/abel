import 'dart:collection';
import 'dart:convert';

import 'package:devex_contracts/devex_contracts.dart';

import '../ports.dart';
import 'gateway_plan_compiler.dart';

final class GatewayMockResult {
  GatewayMockResult({
    required this.status,
    required Map<String, String> headers,
    required List<int> body,
  }) : headers = Map<String, String>.unmodifiable(headers),
       body = ImmutableBytes.copyOf(body);

  final int status;
  final Map<String, String> headers;
  final List<int> body;
}

abstract interface class MockHandlerPort {
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayFixture fixture,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  });
}

abstract interface class DelayPort {
  Future<void> delay(Duration duration);
}

abstract interface class UpstreamHandlerPort {
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  });
}

final class GatewayRuntime {
  GatewayRuntime({
    required this.gatewaySessionId,
    required GatewayCompilation compilation,
    required this.mockHandler,
    required this.clock,
    required this.delay,
    this.upstreamHandler,
    this.maxTrafficEvents = 10000,
    this.maxTrafficBytes = 64 * 1024 * 1024,
  }) {
    if (gatewaySessionId.isEmpty) {
      throw ArgumentError.value(gatewaySessionId, 'gatewaySessionId');
    }
    if (maxTrafficEvents <= 0 || maxTrafficBytes <= 0) {
      throw ArgumentError('Traffic limits must be positive');
    }
    apply(compilation);
  }

  final String gatewaySessionId;
  final MockHandlerPort mockHandler;
  final Clock clock;
  final DelayPort delay;
  final UpstreamHandlerPort? upstreamHandler;
  final int maxTrafficEvents;
  final int maxTrafficBytes;

  late CompiledGatewayPlan _plan;
  late RoutingTable _routingTable;
  late Map<String, Object?> _runtimeState;
  final ListQueue<TrafficEvent> _traffic = ListQueue<TrafficEvent>();
  final ListQueue<int> _trafficSizes = ListQueue<int>();
  var _trafficBytes = 0;
  var _nextSequence = 1;
  var _evictedEvents = 0;

  CompiledGatewayPlan get plan => _plan;
  RoutingTable get routingTable => _routingTable;
  int get evictedEvents => _evictedEvents;
  int get trafficBytes => _trafficBytes;
  Digest get runtimeStateDigest => Digest.semantic(_runtimeState);

  void apply(GatewayCompilation compilation) {
    if ((compilation.plan.backendMode != BackendMode.isolated &&
            compilation.plan.backendMode != BackendMode.hybrid) ||
        compilation.plan.networkContainment != NetworkContainment.gatewayOnly) {
      throw ArgumentError(
        'Gateway runtime accepts isolated/hybrid gatewayOnly plans',
      );
    }
    if (compilation.routingTable.scopeId != compilation.plan.scope.id ||
        compilation.routingTable.presetId != compilation.plan.preset.id) {
      throw ArgumentError(
        'RoutingTable does not belong to CompiledGatewayPlan',
      );
    }
    final routeIds = compilation.plan.routes.map((route) => route.id).toSet();
    if (routeIds.length != compilation.routingTable.entries.length ||
        !routeIds.containsAll(compilation.routingTable.entries.keys)) {
      throw ArgumentError('RoutingTable must cover every compiled route');
    }
    final hasPassthrough = compilation.routingTable.entries.values.contains(
      GatewayRoutingDecision.passthrough,
    );
    if (compilation.plan.backendMode == BackendMode.isolated &&
        hasPassthrough) {
      throw ArgumentError('isolated runtime cannot materialize passthrough');
    }
    if (hasPassthrough && upstreamHandler == null) {
      throw ArgumentError('hybrid passthrough requires UpstreamHandlerPort');
    }
    _plan = compilation.plan;
    _routingTable = compilation.routingTable;
    _runtimeState = _copyState(compilation.plan.preset.initialState);
  }

  void reset() {
    _runtimeState = _copyState(_plan.preset.initialState);
    _evictedEvents += _traffic.length;
    _traffic.clear();
    _trafficSizes.clear();
    _trafficBytes = 0;
  }

  List<TrafficEvent> traffic({int afterSequence = 0, int limit = 1000}) {
    if (afterSequence < 0 || limit <= 0 || limit > 10000) {
      throw ArgumentError('Invalid traffic cursor or limit');
    }
    return List<TrafficEvent>.unmodifiable(
      _traffic.where((event) => event.sequence > afterSequence).take(limit),
    );
  }

  Future<GatewayResponse> handle(GatewayRequest request) async {
    final started = clock.monotonicMicroseconds();
    final match = _match(request);
    if (match == null) {
      final response = _denied(
        status: 404,
        outcome: GatewayOutcome.unmatched,
        code: 'DEVEX_GATEWAY_ROUTE_UNMATCHED',
      );
      _record(request, response, started, routeTemplate: '<unmatched>');
      return response;
    }
    final route = match.route;
    final decision = _routingTable.entries[route.id];
    if (decision == GatewayRoutingDecision.deny) {
      final response = _denied(
        status: 403,
        outcome: GatewayOutcome.denied,
        code: 'DEVEX_GATEWAY_ROUTE_DENIED',
        route: route,
      );
      _record(request, response, started, routeTemplate: route.pathTemplate);
      return response;
    }
    final fault = route.faultProfile;
    if (fault != null && fault.fixedLatencyMilliseconds > 0) {
      await delay.delay(Duration(milliseconds: fault.fixedLatencyMilliseconds));
    }
    if (fault?.disconnect ?? false) {
      final response = _denied(
        status: 503,
        outcome: GatewayOutcome.error,
        code: 'DEVEX_GATEWAY_FAULT_DISCONNECT',
        route: route,
        disconnected: true,
      );
      _record(request, response, started, routeTemplate: route.pathTemplate);
      return response;
    }
    if (decision == GatewayRoutingDecision.passthrough) {
      try {
        final upstream = await upstreamHandler!.handle(
          route: route,
          request: request,
          pathParameters: match.pathParameters,
          runtimeState: Map<String, Object?>.unmodifiable(_runtimeState),
        );
        final response = GatewayResponse(
          status: fault?.forcedStatus ?? upstream.status,
          headers: <String, String>{
            ...upstream.headers,
            'x-devex-gateway': 'passthrough',
            'x-devex-preset': _plan.preset.id.value,
          },
          body: upstream.body,
          outcome: GatewayOutcome.passthrough,
          routeId: route.id,
          presetId: _plan.preset.id,
        );
        _record(request, response, started, routeTemplate: route.pathTemplate);
        return response;
      } on Object {
        final response = _denied(
          status: 502,
          outcome: GatewayOutcome.error,
          code: 'DEVEX_GATEWAY_UPSTREAM_FAILED',
          route: route,
        );
        _record(request, response, started, routeTemplate: route.pathTemplate);
        return response;
      }
    }
    final fixtureId = route.fixtureId;
    final fixture = _plan.fixtures
        .where((candidate) => candidate.id == fixtureId)
        .firstOrNull;
    if (fixture == null) {
      final response = _denied(
        status: 500,
        outcome: GatewayOutcome.error,
        code: 'DEVEX_GATEWAY_FIXTURE_MISSING',
        route: route,
      );
      _record(request, response, started, routeTemplate: route.pathTemplate);
      return response;
    }
    try {
      final mock = await mockHandler.handle(
        route: route,
        fixture: fixture,
        request: request,
        pathParameters: match.pathParameters,
        runtimeState: Map<String, Object?>.unmodifiable(_runtimeState),
      );
      final response = GatewayResponse(
        status: fault?.forcedStatus ?? mock.status,
        headers: <String, String>{
          ...mock.headers,
          'x-devex-gateway': 'mock',
          'x-devex-preset': _plan.preset.id.value,
        },
        body: mock.body,
        outcome: GatewayOutcome.mock,
        routeId: route.id,
        presetId: _plan.preset.id,
      );
      _record(request, response, started, routeTemplate: route.pathTemplate);
      return response;
    } on Object {
      final response = _denied(
        status: 500,
        outcome: GatewayOutcome.error,
        code: 'DEVEX_GATEWAY_MOCK_FAILED',
        route: route,
      );
      _record(request, response, started, routeTemplate: route.pathTemplate);
      return response;
    }
  }

  Future<VerificationReport> verify(GatewayRequest request) async {
    final response = await handle(request);
    return VerificationReport(
      planDigest: _plan.digest,
      requestMethod: request.method,
      requestPath: request.path,
      response: response,
    );
  }

  _RouteMatch? _match(GatewayRequest request) {
    for (final route in _plan.routes) {
      if (route.method != request.method || !_queryMatches(route, request)) {
        continue;
      }
      final parameters = _pathParameters(route.pathTemplate, request.path);
      if (parameters != null) {
        return _RouteMatch(route: route, pathParameters: parameters);
      }
    }
    return null;
  }

  bool _queryMatches(GatewayRoute route, GatewayRequest request) {
    for (final entry in route.requiredQuery.entries) {
      if (!(request.query[entry.key]?.contains(entry.value) ?? false)) {
        return false;
      }
    }
    return true;
  }

  Map<String, String>? _pathParameters(String template, String path) {
    final templateSegments = template.split('/').skip(1).toList();
    final pathSegments = Uri.parse(path).pathSegments;
    if (templateSegments.length != pathSegments.length) return null;
    final parameters = <String, String>{};
    for (var index = 0; index < templateSegments.length; index += 1) {
      final expected = templateSegments[index];
      final actual = pathSegments[index];
      if (expected.startsWith('{')) {
        parameters[expected.substring(1, expected.length - 1)] = actual;
      } else if (expected != actual) {
        return null;
      }
    }
    return parameters;
  }

  GatewayResponse _denied({
    required int status,
    required GatewayOutcome outcome,
    required String code,
    GatewayRoute? route,
    bool disconnected = false,
  }) => GatewayResponse(
    status: status,
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'x-devex-gateway': outcome == GatewayOutcome.unmatched
          ? 'denied'
          : outcome.name,
      'x-devex-preset': _plan.preset.id.value,
    },
    body: utf8.encode(jsonEncode(<String, Object?>{'error': code})),
    outcome: outcome,
    routeId: route?.id,
    presetId: _plan.preset.id,
    disconnected: disconnected,
  );

  void _record(
    GatewayRequest request,
    GatewayResponse response,
    int started, {
    required String routeTemplate,
  }) {
    final event = TrafficEvent(
      sequence: _nextSequence++,
      gatewaySessionId: gatewaySessionId,
      monotonicMicroseconds: started,
      method: request.method,
      routeTemplate: routeTemplate,
      routeId: response.routeId,
      outcome: response.outcome,
      status: response.status,
      durationMicroseconds: clock.monotonicMicroseconds() - started,
      requestSize: request.body.length,
      responseSize: response.body.length,
      errorCode: response.outcome == GatewayOutcome.error
          ? 'DEVEX_GATEWAY_RUNTIME_ERROR'
          : null,
      redactionSummary: 'headers=omitted;body=omitted',
    );
    final size = utf8.encode(jsonEncode(event.toJson())).length;
    _traffic.add(event);
    _trafficSizes.add(size);
    _trafficBytes += size;
    while (_traffic.length > maxTrafficEvents ||
        _trafficBytes > maxTrafficBytes) {
      _traffic.removeFirst();
      _trafficBytes -= _trafficSizes.removeFirst();
      _evictedEvents += 1;
    }
  }

  Map<String, Object?> _copyState(Map<String, Object?> source) =>
      jsonDecode(jsonEncode(source)) as Map<String, Object?>;
}

final class _RouteMatch {
  const _RouteMatch({required this.route, required this.pathParameters});

  final GatewayRoute route;
  final Map<String, String> pathParameters;
}
