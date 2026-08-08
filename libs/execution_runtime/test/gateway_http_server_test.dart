import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late FileSystemWorkspaceStore store;
  late GatewayRuntime runtime;
  late GatewayHttpServer server;
  late List<int> fixtureBytes;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('workspace-gateway-http-');
    store = FileSystemWorkspaceStore(workspaceRoot: temporary.path);
    fixtureBytes = utf8.encode('{"id":"synthetic"}');
    store.withExclusiveLock(() => store.putBlob(fixtureBytes));
    runtime = GatewayRuntime(
      gatewaySessionId: 'gateway-http-1',
      compilation: _compilation(fixtureBytes),
      mockHandler: CasGatewayMockHandler(store),
      clock: SystemClock(),
      delay: const SystemDelay(),
    );
    server = GatewayHttpServer(runtime: runtime);
    await server.start();
  });

  tearDown(() async {
    await server.close();
    temporary.deleteSync(recursive: true);
  });

  test(
    'serves CAS fixture and verify preserves selected raw response',
    () async {
      final uri = server.origin.replace(
        path: '/users/42',
        queryParameters: const <String, String>{'view': 'summary'},
      );
      final api = await _get(uri);
      final report = await runtime.verify(
        GatewayRequest(
          method: 'GET',
          path: '/users/42',
          query: const <String, List<String>>{
            'view': <String>['summary'],
          },
          body: const <int>[],
        ),
      );

      expect(api.status, 200);
      expect(api.body, fixtureBytes);
      expect(api.headers['x-workspace-gateway']?.single, 'mock');
      expect(api.headers['authorization'], isNull);
      expect(report.response.status, api.status);
      expect(report.response.body, api.body);
      expect(
        report.response.headers['content-type'],
        api.headers['content-type']?.single,
      );
      expect(report.response.headers['x-workspace-gateway'], 'mock');
    },
  );

  test(
    'unknown route denies and oversized request fails before matching',
    () async {
      final unknown = await _get(server.origin.replace(path: '/outside'));
      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.postUrl(
        server.origin.replace(path: '/users'),
      );
      request.contentLength = 256 * 1024 + 1;
      request.add(List<int>.filled(256 * 1024 + 1, 1));
      final oversized = await request.close();
      final oversizedBody = await oversized.fold<List<int>>(
        <int>[],
        (output, chunk) => output..addAll(chunk),
      );

      expect(unknown.status, 404);
      expect(unknown.headers['x-workspace-gateway']?.single, 'denied');
      expect(oversized.statusCode, 413);
      expect(utf8.decode(oversizedBody), contains('REQUEST_TOO_LARGE'));
      expect(runtime.traffic(), hasLength(1));
    },
  );

  test('closes its loopback listener', () async {
    final origin = server.origin;
    await server.close();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    addTearDown(client.close);
    await expectLater(client.getUrl(origin), throwsA(isA<SocketException>()));
  });

  test('serves the exact 256 KiB fixture boundary', () async {
    final maximumBody = List<int>.generate(256 * 1024, (index) => index & 0xff);
    store.withExclusiveLock(() => store.putBlob(maximumBody));
    runtime.apply(_compilation(maximumBody));

    final response = await _get(
      server.origin.replace(
        path: '/users/42',
        queryParameters: const <String, String>{'view': 'summary'},
      ),
    );

    expect(response.status, 200);
    expect(response.body, maximumBody);
  });

  test('CORS is exact for the owning loopback Target origin', () async {
    await server.close();
    final targetOrigin = Uri.parse('http://127.0.0.1:8080');
    server = GatewayHttpServer(
      runtime: runtime,
      allowedOrigins: <Uri>{targetOrigin},
    );
    await server.start();
    final client = HttpClient();
    addTearDown(client.close);
    final uri = server.origin.replace(
      path: '/users/42',
      queryParameters: const <String, String>{'view': 'summary'},
    );

    final allowedRequest = await client.getUrl(uri);
    allowedRequest.headers.set('origin', targetOrigin.origin);
    final allowed = await allowedRequest.close();
    await allowed.drain<void>();
    expect(allowed.statusCode, 200);
    expect(
      allowed.headers.value('access-control-allow-origin'),
      targetOrigin.origin,
    );
    expect(allowed.headers.value('vary'), contains('origin'));

    final preflightRequest = await client.openUrl('OPTIONS', uri);
    preflightRequest.headers
      ..set('origin', targetOrigin.origin)
      ..set('access-control-request-method', 'GET');
    final preflight = await preflightRequest.close();
    await preflight.drain<void>();
    expect(preflight.statusCode, 204);
    expect(
      preflight.headers.value('access-control-allow-origin'),
      targetOrigin.origin,
    );

    final deniedRequest = await client.getUrl(uri);
    deniedRequest.headers.set('origin', 'http://127.0.0.1:9999');
    final denied = await deniedRequest.close();
    await denied.drain<void>();
    expect(denied.statusCode, 403);
    expect(denied.headers.value('access-control-allow-origin'), isNull);
  });

  test(
    'FaultProfile disconnect closes the data socket deterministically',
    () async {
      runtime.apply(_compilation(fixtureBytes, disconnect: true));
      final uri = server.origin.replace(
        path: '/users/42',
        queryParameters: const <String, String>{'view': 'summary'},
      );

      await expectLater(
        _get(uri),
        throwsA(anyOf(isA<HttpException>(), isA<SocketException>())),
      );
      final event = runtime.traffic().single;
      expect(event.outcome, GatewayOutcome.error);
      expect(event.status, 503);
    },
  );

  test(
    'aborted request body does not poison the listener or next request',
    () async {
      final socket = await Socket.connect(
        server.origin.host,
        server.origin.port,
      );
      socket.add(
        ascii.encode(
          'POST /users HTTP/1.1\r\n'
          'Host: ${server.origin.host}\r\n'
          'Content-Length: 1000\r\n'
          'Connection: close\r\n\r\n'
          'partial',
        ),
      );
      await socket.flush();
      await socket.close();

      final next = await _get(
        server.origin.replace(
          path: '/users/42',
          queryParameters: const <String, String>{'view': 'summary'},
        ),
      );
      expect(next.status, 200);
      expect(next.body, fixtureBytes);
    },
  );
}

Future<({int status, HttpHeaders headers, List<int> body})> _get(
  Uri uri,
) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(uri)).close();
    final body = await response.fold<List<int>>(
      <int>[],
      (output, chunk) => output..addAll(chunk),
    );
    return (status: response.statusCode, headers: response.headers, body: body);
  } finally {
    client.close();
  }
}

GatewayCompilation _compilation(
  List<int> fixtureBytes, {
  bool disconnect = false,
}) {
  final scopeId = GatewayScopeId('accounts');
  final presetId = GatewayPresetId('default');
  final route = GatewayRoute(
    id: GatewayRouteId('get-user'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/users/{id}',
    requiredQuery: const <String, String>{'view': 'summary'},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('user'),
    faultProfile: disconnect ? GatewayFaultProfile(disconnect: true) : null,
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
