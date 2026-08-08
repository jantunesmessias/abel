import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'isolates process, listener, fixture, traffic, and reset per session',
    () async {
      final repositoryRoot = _repositoryRoot();
      final firstRoot = Directory.systemTemp.createTempSync(
        'workspace-sidecar-one-',
      );
      final secondRoot = Directory.systemTemp.createTempSync(
        'workspace-sidecar-two-',
      );
      addTearDown(() => firstRoot.deleteSync(recursive: true));
      addTearDown(() => secondRoot.deleteSync(recursive: true));
      final firstBytes = utf8.encode('{"sidecar":"one"}');
      final secondBytes = utf8.encode('{"sidecar":"two"}');
      FileSystemWorkspaceStore(workspaceRoot: firstRoot.path).withExclusiveLock(
        () => FileSystemWorkspaceStore(
          workspaceRoot: firstRoot.path,
        ).putBlob(firstBytes),
      );
      FileSystemWorkspaceStore(
        workspaceRoot: secondRoot.path,
      ).withExclusiveLock(
        () => FileSystemWorkspaceStore(
          workspaceRoot: secondRoot.path,
        ).putBlob(secondBytes),
      );
      final first = await _Sidecar.start(repositoryRoot);
      final second = await _Sidecar.start(repositoryRoot);
      addTearDown(first.kill);
      addTearDown(second.kill);

      final firstReady = await first
          .call('gateway.initialize', <String, Object?>{
            'protocolVersion': 1,
            'gatewaySessionId': 'gateway-one',
            'workspaceRoot': firstRoot.path,
            'plan': _plan(firstBytes, suffix: 'one').toJson(),
          });
      final secondReady = await second
          .call('gateway.initialize', <String, Object?>{
            'protocolVersion': 1,
            'gatewaySessionId': 'gateway-two',
            'workspaceRoot': secondRoot.path,
            'plan': _plan(secondBytes, suffix: 'two').toJson(),
          });
      final firstOrigin = Uri.parse(
        (firstReady.result! as Map<String, Object?>)['dataOrigin']! as String,
      );
      final secondOrigin = Uri.parse(
        (secondReady.result! as Map<String, Object?>)['dataOrigin']! as String,
      );

      expect(firstOrigin.port, isNot(secondOrigin.port));
      expect(await _get(firstOrigin.replace(path: '/value')), firstBytes);
      expect(await _get(secondOrigin.replace(path: '/value')), secondBytes);
      final verified = await first.call(
        'gateway.verify',
        const <String, Object?>{'method': 'GET', 'path': '/value'},
      );
      final verifiedResult = verified.result! as Map<String, Object?>;
      expect(
        base64Decode(verifiedResult['responseBodyBase64']! as String),
        firstBytes,
      );

      final firstTraffic = await first.call(
        'gateway.traffic',
        const <String, Object?>{},
      );
      final secondTraffic = await second.call(
        'gateway.traffic',
        const <String, Object?>{},
      );
      expect(firstTraffic.result, hasLength(2));
      expect(secondTraffic.result, hasLength(1));
      await first.call('gateway.reset', const <String, Object?>{});
      expect(
        (await first.call('gateway.traffic', const <String, Object?>{})).result,
        isEmpty,
      );
      expect(
        (await second.call(
          'gateway.traffic',
          const <String, Object?>{},
        )).result,
        hasLength(1),
      );

      await first.stop();
      await second.stop();
      await expectLater(_get(firstOrigin), throwsA(isA<SocketException>()));
      await expectLater(_get(secondOrigin), throwsA(isA<SocketException>()));
      expect(await first.stderrText, isEmpty);
      expect(await second.stderrText, isEmpty);
    },
  );

  test(
    'hybrid sidecar proxies only an allowlisted route and denies unknown',
    () async {
      final repositoryRoot = _repositoryRoot();
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-sidecar-hybrid-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      var upstreamCalls = 0;
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) async {
        upstreamCalls += 1;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"source":"allowlisted-upstream"}');
        await request.response.close();
      });
      File(p.join(workspace.path, 'workspace.local.yaml')).writeAsStringSync('''
schemaVersion: 1
gateway:
  upstreams:
    development:
      baseUrl: http://127.0.0.1:${upstream.port}
      allowedHost: 127.0.0.1
      environment: development
      allowPrivateAddresses: true
''');
      final sidecar = await _Sidecar.start(repositoryRoot);
      addTearDown(sidecar.kill);
      final initialized = await sidecar
          .call('gateway.initialize', <String, Object?>{
            'protocolVersion': 1,
            'gatewaySessionId': 'gateway-hybrid',
            'workspaceRoot': workspace.path,
            'plan': _hybridPlan().toJson(),
          });
      final origin = Uri.parse(
        (initialized.result! as Map<String, Object?>)['dataOrigin']! as String,
      );

      final api = await _httpGet(origin.replace(path: '/remote/value'));
      final unknown = await _httpGet(origin.replace(path: '/unknown'));
      final verified = await sidecar.call(
        'gateway.verify',
        const <String, Object?>{'method': 'GET', 'path': '/remote/value'},
      );
      final traffic = await sidecar.call(
        'gateway.traffic',
        const <String, Object?>{},
      );

      expect(api.status, 200);
      expect(utf8.decode(api.body), '{"source":"allowlisted-upstream"}');
      expect(api.headers['x-workspace-gateway']?.single, 'passthrough');
      expect(unknown.status, 404);
      expect(upstreamCalls, 2);
      final verifiedResult = verified.result! as Map<String, Object?>;
      expect(
        base64Decode(verifiedResult['responseBodyBase64']! as String),
        api.body,
      );
      expect(
        (traffic.result! as List<Object?>).map(
          (item) => (item! as Map<String, Object?>)['outcome'],
        ),
        <Object?>['passthrough', 'unmatched', 'passthrough'],
      );
      await sidecar.stop();
    },
  );
}

CompiledGatewayPlan _hybridPlan() {
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
  return const GatewayPlanCompiler()
      .compile(
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
      )
      .plan;
}

CompiledGatewayPlan _plan(List<int> bytes, {required String suffix}) {
  final scopeId = GatewayScopeId('scope-$suffix');
  final presetId = GatewayPresetId('preset-$suffix');
  final route = GatewayRoute(
    id: GatewayRouteId('value-$suffix'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/value',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('fixture-$suffix'),
  );
  return const GatewayPlanCompiler()
      .compile(
        scope: GatewayScope(
          id: scopeId,
          displayName: 'Scope $suffix',
          routeIds: <GatewayRouteId>[route.id],
        ),
        preset: GatewayPreset(
          id: presetId,
          scopeId: scopeId,
          description: 'Preset $suffix',
          routeIds: <GatewayRouteId>[route.id],
        ),
        routes: <GatewayRoute>[route],
        fixtures: <GatewayFixture>[
          GatewayFixture(
            id: GatewayFixtureId('fixture-$suffix'),
            status: 200,
            headers: const <String, String>{'content-type': 'application/json'},
            bodyDigest: Digest.bytes(bytes),
            bodySize: bytes.length,
            mediaType: 'application/json',
          ),
        ],
      )
      .plan;
}

Future<List<int>> _get(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final response = await (await client.getUrl(uri)).close();
    return await response.fold<List<int>>(
      <int>[],
      (output, chunk) => output..addAll(chunk),
    );
  } finally {
    client.close();
  }
}

Future<({int status, HttpHeaders headers, List<int> body})> _httpGet(
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
    client.close(force: true);
  }
}

final class _Sidecar {
  _Sidecar(this.process, this.lines, this.stderrText);

  final Process process;
  final StreamIterator<String> lines;
  final Future<String> stderrText;
  var nextId = 1;
  var stopped = false;

  static Future<_Sidecar> start(String repositoryRoot) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      const <String>['run', 'apps/gateway_sidecar/bin/gateway_sidecar.dart'],
      workingDirectory: repositoryRoot,
    );
    return _Sidecar(
      process,
      StreamIterator<String>(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
      process.stderr.transform(utf8.decoder).join(),
    );
  }

  Future<JsonRpcResponse> call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = 'request-${nextId++}';
    process.stdin.writeln(
      JsonRpcRequest(method: method, id: id, params: params).encode(),
    );
    await process.stdin.flush();
    if (!await lines.moveNext()) {
      throw StateError('Sidecar closed before responding to $method');
    }
    final response = const JsonRpcCodec().decode(lines.current);
    if (response is! JsonRpcResponse || response.id != id) {
      throw StateError('Unexpected sidecar response for $method');
    }
    if (!response.isSuccess) {
      throw StateError('${response.error!.code}: ${response.error!.message}');
    }
    return response;
  }

  Future<void> stop() async {
    if (stopped) return;
    await call('gateway.stop', const <String, Object?>{});
    await process.stdin.close();
    expect(await process.exitCode, 0);
    stopped = true;
  }

  Future<void> kill() async {
    if (stopped) return;
    process.kill(ProcessSignal.sigterm);
    await process.exitCode;
    stopped = true;
  }
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
