import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Directory workspace;
  late HttpJsonRemoteConfigProvider provider;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('workspace-provider-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/missing':
          request.response.statusCode = 404;
        case '/empty':
          break;
        case '/empty-items':
          request.response.write('{"schemaVersion":1,"items":[]}');
        case '/incomplete':
          request.response.write('{"schemaVersion":1}');
        case '/invalid':
          request.response.write('{broken');
        case '/secret':
          request.response.write(
            '{"schemaVersion":1,"items":[{"id":"one","secretToken":"x"}]}',
          );
        case '/ready':
          request.response.write(
            '{"schemaVersion":1,"items":[{"id":"one","enabled":true}]}',
          );
        default:
          request.response.statusCode = 500;
      }
      await request.response.close();
    });
    provider = HttpJsonRemoteConfigProvider(
      credentials: EnvironmentCredentialResolver(environment: const {}),
      clock: const _FixedClock(),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    workspace.deleteSync(recursive: true);
  });

  test('classifies missing, empty, incomplete, invalid, and ready', () async {
    final expected = <String, RemoteConfigState>{
      '/missing': RemoteConfigState.missing,
      '/empty': RemoteConfigState.empty,
      '/empty-items': RemoteConfigState.empty,
      '/incomplete': RemoteConfigState.incomplete,
      '/invalid': RemoteConfigState.invalid,
      '/secret': RemoteConfigState.invalid,
      '/ready': RemoteConfigState.ready,
    };

    for (final entry in expected.entries) {
      final assessment = await provider.fetch(
        _configuration(server, entry.key),
      );
      expect(assessment.state, entry.value, reason: entry.key);
      expect(assessment.toJson().toString(), isNot(contains('secretToken')));
    }
  });

  test(
    'sync atomically preserves the last active digest after invalid input',
    () async {
      final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
      final service = RemoteConfigSyncService(
        provider: provider,
        repository: LocalRemoteConfigRepository(store),
      );

      final ready = await service.sync(_configuration(server, '/ready'));
      final invalid = await service.sync(_configuration(server, '/invalid'));

      expect(ready.observed.state, RemoteConfigState.ready);
      expect(ready.activeDocumentDigest, isNotNull);
      expect(invalid.observed.state, RemoteConfigState.invalid);
      expect(invalid.activeDocumentDigest, ready.activeDocumentDigest);
      final active =
          jsonDecode(utf8.decode(store.readBlob(ready.activeDocumentDigest!)!))
              as Map<String, Object?>;
      expect(
        (active['items']! as List<Object?>).single,
        containsPair('id', 'one'),
      );
      final stateBytes = store.readStateBytes(
        'gateway/providers/generic/state.json',
      )!;
      final stateText = utf8.decode(stateBytes);
      expect(stateText, endsWith('\n'));
      expect(stateText, isNot(contains('{broken')));
      expect(stateText, isNot(contains('secret')));
      expect(
        File(
          p.join(
            store.stateRoot,
            'gateway',
            'providers',
            'generic',
            'state.json',
          ),
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('loads providers strictly and reports only redacted configuration', () {
    File(p.join(workspace.path, 'workspace.local.yaml')).writeAsStringSync('''
schemaVersion: 1
gateway:
  upstreams:
    integration:
      baseUrl: http://127.0.0.1:${server.port}
      allowedHost: 127.0.0.1
      environment: development
      allowPrivateAddresses: true
      credentialHandle: env:REMOTE_ACCESS_TOKEN
  providers:
    generic:
      upstreamProfileId: integration
      requestPath: /ready
      query: {view: [summary, compact]}
''');

    final configurations = const LocalRemoteConfigProviderLoader().load(
      workspaceRoot: workspace.path,
    );
    final configuration = configurations['generic']!;
    final status = jsonEncode(configuration.redactedStatus());

    expect(configuration.query['view'], <String>['summary', 'compact']);
    expect(status, isNot(contains('REMOTE_ACCESS_TOKEN')));
    expect(status, isNot(contains(server.port.toString())));
    expect(status, contains('credentialConfigured'));
  });

  test('rejects provider IDs before constructing repository paths', () {
    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    expect(
      () => LocalRemoteConfigRepository(store).commit(
        RemoteConfigAssessment(
          providerId: '../escape',
          state: RemoteConfigState.invalid,
          observedAt: DateTime.utc(2026),
          statusCode: null,
          message: 'invalid',
        ),
      ),
      throwsFormatException,
    );
    expect(
      File(p.join(workspace.path, 'escape', 'state.json')).existsSync(),
      isFalse,
    );
  });
}

RemoteConfigProviderConfiguration _configuration(
  HttpServer server,
  String path,
) {
  final endpoint = GatewayUpstreamEndpoint(
    profileId: UpstreamProfileId('remote-config'),
    baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    allowedHost: '127.0.0.1',
    environment: UpstreamEnvironment.development,
    allowPrivateAddresses: true,
  );
  return RemoteConfigProviderConfiguration(
    id: 'generic',
    endpoint: endpoint,
    requestPath: path,
  );
}

final class _FixedClock implements Clock {
  const _FixedClock();

  @override
  int monotonicMicroseconds() => 1;

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 9, 15);
}
