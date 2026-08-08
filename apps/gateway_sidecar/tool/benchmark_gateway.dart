import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

Future<void> main() async {
  final workspace = Directory.systemTemp.createTempSync(
    'workspace-gateway-bench-',
  );
  try {
    final measurements = <Map<String, Object?>>[];
    for (final bodySize in const <int>[1024, 256 * 1024]) {
      measurements.add(await _measure(workspace, bodySize));
    }
    final worstP95 = measurements
        .map((measurement) => measurement['p95Microseconds']! as int)
        .reduce((left, right) => left > right ? left : right);
    final worstP99 = measurements
        .map((measurement) => measurement['p99Microseconds']! as int)
        .reduce((left, right) => left > right ? left : right);
    final passed = worstP95 <= 10000 && worstP99 <= 25000;
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'benchmark': 'gateway-isolated-http-v1',
        'mode': 'aot',
        'dartVersion': Platform.version.split(' ').first,
        'operatingSystem': Platform.operatingSystem,
        'samplesPerBodySize': 50,
        'warmupPerBodySize': 10,
        'measurements': measurements,
        'worstP95Microseconds': worstP95,
        'worstP99Microseconds': worstP99,
        'budgetP95Microseconds': 10000,
        'budgetP99Microseconds': 25000,
        'passed': passed,
      }),
    );
    await stdout.flush();
    if (!passed) exitCode = 1;
  } finally {
    workspace.deleteSync(recursive: true);
  }
}

Future<Map<String, Object?>> _measure(Directory workspace, int bodySize) async {
  final bytes = List<int>.generate(bodySize, (index) => index & 0xff);
  final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
  store.withExclusiveLock(() => store.putBlob(bytes));
  final runtime = GatewayRuntime(
    gatewaySessionId: 'benchmark-$bodySize',
    compilation: _compilation(bytes),
    mockHandler: CasGatewayMockHandler(store),
    clock: SystemClock(),
    delay: const SystemDelay(),
  );
  final server = GatewayHttpServer(runtime: runtime);
  final client = HttpClient()..maxConnectionsPerHost = 1;
  await server.start();
  try {
    final uri = server.origin.replace(path: '/benchmark');
    for (var index = 0; index < 10; index += 1) {
      await _request(client, uri, bodySize);
    }
    final samples = <int>[];
    for (var index = 0; index < 50; index += 1) {
      final stopwatch = Stopwatch()..start();
      await _request(client, uri, bodySize);
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }
    samples.sort();
    return <String, Object?>{
      'bodySize': bodySize,
      'p50Microseconds': _percentile(samples, 0.50),
      'p95Microseconds': _percentile(samples, 0.95),
      'p99Microseconds': _percentile(samples, 0.99),
      'maxMicroseconds': samples.last,
      'trafficEvents': runtime.traffic(limit: 10000).length,
      'evictedTrafficEvents': runtime.evictedEvents,
    };
  } finally {
    client.close(force: true);
    await server.close();
  }
}

Future<void> _request(HttpClient client, Uri uri, int expectedSize) async {
  final response = await (await client.getUrl(uri)).close();
  var observed = 0;
  await for (final chunk in response) {
    observed += chunk.length;
  }
  if (response.statusCode != 200 || observed != expectedSize) {
    throw StateError(
      'Unexpected benchmark response ${response.statusCode}/$observed',
    );
  }
}

int _percentile(List<int> sorted, double percentile) {
  final rank = (sorted.length * percentile).ceil() - 1;
  return sorted[rank.clamp(0, sorted.length - 1)];
}

GatewayCompilation _compilation(List<int> bytes) {
  final scopeId = GatewayScopeId('benchmark');
  final presetId = GatewayPresetId('default');
  final route = GatewayRoute(
    id: GatewayRouteId('benchmark'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/benchmark',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('body'),
  );
  return const GatewayPlanCompiler().compile(
    scope: GatewayScope(
      id: scopeId,
      displayName: 'Benchmark',
      routeIds: <GatewayRouteId>[route.id],
    ),
    preset: GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Benchmark',
      routeIds: <GatewayRouteId>[route.id],
    ),
    routes: <GatewayRoute>[route],
    fixtures: <GatewayFixture>[
      GatewayFixture(
        id: GatewayFixtureId('body'),
        status: 200,
        headers: const <String, String>{
          'content-type': 'application/octet-stream',
        },
        bodyDigest: Digest.bytes(bytes),
        bodySize: bytes.length,
        mediaType: 'application/octet-stream',
      ),
    ],
  );
}
