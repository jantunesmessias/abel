import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late HttpServer upstream;
  late GatewayRoute route;
  late var requests = 0;

  setUp(() async {
    requests = 0;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      requests += 1;
      switch (request.uri.path) {
        case '/api/ok':
          expect(request.headers.value('authorization'), 'Bearer synthetic');
          expect(request.uri.queryParameters['view'], 'summary');
          request.response.statusCode = 201;
          request.response.headers.contentType = ContentType.json;
          request.response.cookies.add(Cookie('secret', 'not-forwarded'));
          request.response.write('{"source":"upstream"}');
        case '/api/redirect':
          request.response.statusCode = 302;
          request.response.headers.set('location', 'http://attacker.test/');
        case '/api/large':
          request.response.add(List<int>.filled(1025, 1));
        case '/api/encoded':
          request.response.headers.set('content-encoding', 'gzip');
          request.response.add(const <int>[1, 2, 3]);
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
    route = GatewayRoute(
      id: GatewayRouteId('remote'),
      scopeId: GatewayScopeId('scope'),
      method: 'GET',
      pathTemplate: '/{path}',
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{GatewayPresetId('default')},
      policy: GatewayRoutePolicy.upstreamOnly,
      fixtureId: null,
      upstreamProfileId: UpstreamProfileId('development'),
    );
  });

  tearDown(() => upstream.close(force: true));

  test(
    'pins an allowlisted address and forwards only configured auth',
    () async {
      final handler = _handler(upstream, maxResponseBytes: 2048);

      final result = await handler.handle(
        route: route,
        request: _request(
          '/ok',
          query: const <String, List<String>>{
            'view': <String>['summary'],
          },
        ),
        pathParameters: const <String, String>{},
        runtimeState: const <String, Object?>{},
      );

      expect(result.status, 201);
      expect(utf8.decode(result.body), '{"source":"upstream"}');
      expect(result.headers['content-type'], startsWith('application/json'));
      expect(result.headers, isNot(contains('set-cookie')));
      expect(requests, 1);
    },
  );

  test('rejects redirects, encoded bodies, and oversized responses', () async {
    final handler = _handler(upstream, maxResponseBytes: 1024);

    for (final path in <String>['/redirect', '/encoded', '/large']) {
      await expectLater(
        handler.handle(
          route: route,
          request: _request(path),
          pathParameters: const <String, String>{},
          runtimeState: const <String, Object?>{},
        ),
        throwsStateError,
        reason: path,
      );
    }
    expect(requests, 3);
  });

  test('rejects private DNS unless local policy opts in explicitly', () async {
    final endpoint = GatewayUpstreamEndpoint(
      profileId: UpstreamProfileId('development'),
      baseUri: Uri.parse('http://example.test:${upstream.port}/api'),
      allowedHost: 'example.test',
      environment: UpstreamEnvironment.development,
    );
    final handler = SafeHttpGatewayUpstreamHandler(
      endpoints: <UpstreamProfileId, GatewayUpstreamEndpoint>{
        endpoint.profileId: endpoint,
      },
      credentials: EnvironmentCredentialResolver(environment: const {}),
      addresses: _FixedResolver(<InternetAddress>[
        InternetAddress.loopbackIPv4,
      ]),
    );

    await expectLater(
      handler.handle(
        route: route,
        request: _request('/ok'),
        pathParameters: const <String, String>{},
        runtimeState: const <String, Object?>{},
      ),
      throwsStateError,
    );
    expect(requests, 0);
  });

  test('pins resolved IP while preserving the allowlisted HTTP host', () async {
    final endpoint = GatewayUpstreamEndpoint(
      profileId: UpstreamProfileId('development'),
      baseUri: Uri.parse('http://allowlisted.test:${upstream.port}/api'),
      allowedHost: 'allowlisted.test',
      environment: UpstreamEnvironment.development,
      allowPrivateAddresses: true,
      credentialHandle: 'env:DEVEX_UPSTREAM_TOKEN',
      maxResponseBytes: 2048,
    );
    final handler = SafeHttpGatewayUpstreamHandler(
      endpoints: <UpstreamProfileId, GatewayUpstreamEndpoint>{
        endpoint.profileId: endpoint,
      },
      credentials: EnvironmentCredentialResolver(
        environment: const <String, String>{
          'DEVEX_UPSTREAM_TOKEN': 'Bearer synthetic',
        },
      ),
      addresses: _FixedResolver(<InternetAddress>[
        InternetAddress.loopbackIPv4,
      ]),
    );

    final result = await handler.handle(
      route: route,
      request: _request(
        '/ok',
        query: const <String, List<String>>{
          'view': <String>['summary'],
        },
      ),
      pathParameters: const <String, String>{},
      runtimeState: const <String, Object?>{},
    );

    expect(result.status, 201);
    expect(requests, 1);
  });

  test('rejects mixed and IPv4-mapped private DNS answers', () async {
    final endpoint = GatewayUpstreamEndpoint(
      profileId: UpstreamProfileId('development'),
      baseUri: Uri.parse('http://allowlisted.test:${upstream.port}/api'),
      allowedHost: 'allowlisted.test',
      environment: UpstreamEnvironment.development,
    );
    for (final answers in <List<InternetAddress>>[
      <InternetAddress>[
        InternetAddress('8.8.8.8'),
        InternetAddress.loopbackIPv4,
      ],
      <InternetAddress>[InternetAddress('::ffff:127.0.0.1')],
    ]) {
      final handler = SafeHttpGatewayUpstreamHandler(
        endpoints: <UpstreamProfileId, GatewayUpstreamEndpoint>{
          endpoint.profileId: endpoint,
        },
        credentials: EnvironmentCredentialResolver(environment: const {}),
        addresses: _FixedResolver(answers),
      );
      await expectLater(
        handler.handle(
          route: route,
          request: _request('/ok'),
          pathParameters: const <String, String>{},
          runtimeState: const <String, Object?>{},
        ),
        throwsStateError,
      );
    }
    expect(requests, 0);
  });

  test('validates local configuration without resolving credential values', () {
    final workspace = Directory.systemTemp.createTempSync(
      'devex-local-config-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    File(p.join(workspace.path, 'devex.local.yaml')).writeAsStringSync('''
schemaVersion: 1
gateway:
  upstreams:
    development:
      baseUrl: http://127.0.0.1:${upstream.port}/api
      allowedHost: 127.0.0.1
      environment: development
      allowPrivateAddresses: true
      credentialHandle: env:DEVEX_UPSTREAM_TOKEN
      credentialHeader: authorization
      maxResponseBytes: 2048
      timeoutMilliseconds: 2000
''');

    final endpoints = const LocalGatewayConfigurationLoader().load(
      workspaceRoot: workspace.path,
    );
    final endpoint = endpoints[UpstreamProfileId('development')]!;

    expect(endpoint.baseUri.port, upstream.port);
    expect(endpoint.redactedStatus(), isNot(contains('credentialHandle')));
    expect(endpoint.redactedStatus(), isNot(contains('baseUrl')));
  });

  test('forbids production-like hosts and allowlist mismatch', () {
    expect(
      () => GatewayUpstreamEndpoint(
        profileId: UpstreamProfileId('development'),
        baseUri: Uri.parse('https://api.prod'),
        allowedHost: 'api.prod',
        environment: UpstreamEnvironment.development,
      ),
      throwsArgumentError,
    );
    expect(
      () => GatewayUpstreamEndpoint(
        profileId: UpstreamProfileId('development'),
        baseUri: Uri.parse('https://one.example.test'),
        allowedHost: 'two.example.test',
        environment: UpstreamEnvironment.development,
      ),
      throwsArgumentError,
    );
  });
}

SafeHttpGatewayUpstreamHandler _handler(
  HttpServer upstream, {
  required int maxResponseBytes,
}) {
  final endpoint = GatewayUpstreamEndpoint(
    profileId: UpstreamProfileId('development'),
    baseUri: Uri.parse('http://127.0.0.1:${upstream.port}/api'),
    allowedHost: '127.0.0.1',
    environment: UpstreamEnvironment.development,
    allowPrivateAddresses: true,
    credentialHandle: 'env:DEVEX_UPSTREAM_TOKEN',
    maxResponseBytes: maxResponseBytes,
  );
  return SafeHttpGatewayUpstreamHandler(
    endpoints: <UpstreamProfileId, GatewayUpstreamEndpoint>{
      endpoint.profileId: endpoint,
    },
    credentials: EnvironmentCredentialResolver(
      environment: const <String, String>{
        'DEVEX_UPSTREAM_TOKEN': 'Bearer synthetic',
      },
    ),
  );
}

GatewayRequest _request(
  String path, {
  Map<String, List<String>> query = const <String, List<String>>{},
}) => GatewayRequest(method: 'GET', path: path, query: query, body: const []);

final class _FixedResolver implements GatewayAddressResolver {
  const _FixedResolver(this.addresses);

  final List<InternetAddress> addresses;

  @override
  Future<List<InternetAddress>> lookup(String host) async => addresses;
}
