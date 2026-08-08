import 'package:experience_contracts/experience_contracts.dart';

final class GatewayCompileException implements Exception {
  GatewayCompileException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(issues);

  final List<String> issues;

  @override
  String toString() => issues.join('\n');
}

final class GatewayCompilation {
  const GatewayCompilation({required this.plan, required this.routingTable});

  final CompiledGatewayPlan plan;
  final RoutingTable routingTable;
}

final class GatewayPlanCompiler {
  const GatewayPlanCompiler();

  GatewayCompilation compile({
    required GatewayScope scope,
    required GatewayPreset preset,
    required Iterable<GatewayRoute> routes,
    required Iterable<GatewayFixture> fixtures,
    BackendMode backendMode = BackendMode.isolated,
  }) {
    final issues = <String>[];
    final routesById = _uniqueBy(
      routes,
      (route) => route.id,
      'GatewayRoute',
      issues,
    );
    final fixturesById = _uniqueBy(
      fixtures,
      (fixture) => fixture.id,
      'GatewayFixture',
      issues,
    );
    if (preset.scopeId != scope.id) {
      issues.add('GatewayPreset ${preset.id} does not belong to ${scope.id}');
    }
    final scopeRouteIds = scope.routeIds.toSet();
    if (scopeRouteIds.length != routesById.length ||
        !scopeRouteIds.containsAll(routesById.keys)) {
      issues.add(
        'GatewayScope.routeIds must equal the supplied route registry',
      );
    }
    for (final route in routesById.values) {
      if (route.scopeId != scope.id) {
        issues.add('GatewayRoute ${route.id} belongs to another scope');
      }
    }
    final applicable = routesById.values
        .where((route) => route.appliesTo.contains(preset.id))
        .map((route) => route.id)
        .toSet();
    final presetRouteIds = preset.routeIds.toSet();
    if (applicable.length != presetRouteIds.length ||
        !applicable.containsAll(presetRouteIds)) {
      issues.add(
        'GatewayPreset.routeIds must equal routes whose appliesTo contains ${preset.id}',
      );
    }
    final selectedRoutes = <GatewayRoute>[];
    final selectedFixtureIds = <GatewayFixtureId>{};
    for (final routeId in preset.routeIds) {
      final route = routesById[routeId];
      if (route == null) {
        issues.add('GatewayPreset references unknown route $routeId');
        continue;
      }
      selectedRoutes.add(route);
      final fixtureId = route.fixtureId;
      if (fixtureId != null) {
        selectedFixtureIds.add(fixtureId);
        if (!fixturesById.containsKey(fixtureId)) {
          issues.add(
            'GatewayRoute ${route.id} references missing fixture $fixtureId',
          );
        }
      }
      if (backendMode == BackendMode.isolated &&
          route.policy == GatewayRoutePolicy.upstreamOnly) {
        issues.add(
          'isolated plan cannot include upstreamOnly route ${route.id}',
        );
      }
    }
    if (selectedFixtureIds.length != fixturesById.length ||
        !selectedFixtureIds.containsAll(fixturesById.keys)) {
      issues.add('Fixture registry must contain exactly the selected fixtures');
    }
    _findAmbiguousRoutes(selectedRoutes, issues);
    if (backendMode == BackendMode.none) {
      issues.add('GatewayPlanCompiler requires isolated or hybrid mode');
    }
    if (issues.isNotEmpty) throw GatewayCompileException(issues);

    final selectedFixtures = selectedFixtureIds
        .map((id) => fixturesById[id]!)
        .toList(growable: false);
    final plan = CompiledGatewayPlan(
      scope: scope,
      preset: preset,
      routes: selectedRoutes,
      fixtures: selectedFixtures,
      backendMode: backendMode,
      networkContainment: NetworkContainment.gatewayOnly,
    );
    final routingTable = RoutingTable(
      scopeId: scope.id,
      presetId: preset.id,
      entries: <GatewayRouteId, GatewayRoutingDecision>{
        for (final route in selectedRoutes)
          route.id:
              backendMode == BackendMode.hybrid &&
                  route.policy == GatewayRoutePolicy.upstreamOnly
              ? GatewayRoutingDecision.passthrough
              : GatewayRoutingDecision.mock,
      },
    );
    return GatewayCompilation(plan: plan, routingTable: routingTable);
  }

  Map<K, T> _uniqueBy<T, K>(
    Iterable<T> values,
    K Function(T) keyOf,
    String kind,
    List<String> issues,
  ) {
    final output = <K, T>{};
    for (final value in values) {
      final key = keyOf(value);
      if (output.containsKey(key)) issues.add('duplicate $kind ID $key');
      output[key] = value;
    }
    return output;
  }

  void _findAmbiguousRoutes(List<GatewayRoute> routes, List<String> issues) {
    for (var leftIndex = 0; leftIndex < routes.length; leftIndex += 1) {
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < routes.length;
        rightIndex += 1
      ) {
        final left = routes[leftIndex];
        final right = routes[rightIndex];
        if (left.method == right.method &&
            _templatesOverlap(left.pathTemplate, right.pathTemplate) &&
            _queriesOverlap(left.requiredQuery, right.requiredQuery)) {
          issues.add('ambiguous routes ${left.id} and ${right.id}');
        }
      }
    }
  }

  bool _templatesOverlap(String left, String right) {
    final leftSegments = left.split('/');
    final rightSegments = right.split('/');
    if (leftSegments.length != rightSegments.length) return false;
    for (var index = 0; index < leftSegments.length; index += 1) {
      final leftSegment = leftSegments[index];
      final rightSegment = rightSegments[index];
      final leftParameter = leftSegment.startsWith('{');
      final rightParameter = rightSegment.startsWith('{');
      if (!leftParameter && !rightParameter && leftSegment != rightSegment) {
        return false;
      }
    }
    return true;
  }

  bool _queriesOverlap(Map<String, String> left, Map<String, String> right) {
    for (final key in left.keys.toSet().intersection(right.keys.toSet())) {
      if (left[key] != right[key]) return false;
    }
    return true;
  }
}
