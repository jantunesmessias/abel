import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    throw const FormatException('showcase_smoke does not accept arguments');
  }
  final root = _repositoryRoot();
  final sampleRoot = '${root.path}/examples/sample_flutter';
  final loaded = const WorkspaceCatalogLoader().load(startPath: sampleRoot);
  final compiled = const WorkspaceGatewayPlanCompiler().compilePreset(
    loaded,
    presetId: 'showcase-hybrid',
    persist: true,
  );
  final artifactDigest = compiled.planArtifactDigest!;

  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  WebSocket? socket;
  StreamIterator<Object?>? messages;
  String? sessionId;
  String? gatewaySessionId;
  late Future<Object?> Function(String, Map<String, Object?>) call;
  try {
    final studioOrigin = Uri.parse('http://127.0.0.1:7368');
    final bootstrapRequest = await client.getUrl(
      studioOrigin.resolve('/devex/bootstrap.json'),
    );
    bootstrapRequest.headers.set('sec-fetch-site', 'same-origin');
    final bootstrapResponse = await bootstrapRequest.close();
    final bootstrapBody = await utf8.decoder.bind(bootstrapResponse).join();
    final bootstrap = jsonDecode(bootstrapBody) as Map<String, Object?>;
    if (bootstrapResponse.statusCode != 200) {
      throw StateError('Studio bootstrap is unavailable');
    }
    final hostOrigin = Uri.parse(bootstrap['hostOrigin']! as String);
    final token = bootstrap['sessionToken']! as String;
    socket = await WebSocket.connect(
      hostOrigin.replace(scheme: 'ws', path: '/rpc').toString(),
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    final connectedSocket = socket;
    final connectedMessages = StreamIterator<Object?>(connectedSocket);
    messages = connectedMessages;
    var requestSequence = 0;
    call = (method, params) async {
      final requestId = 'showcase-smoke-${requestSequence++}';
      connectedSocket.add(
        JsonRpcRequest(method: method, id: requestId, params: params).encode(),
      );
      while (await connectedMessages.moveNext()) {
        final raw = connectedMessages.current;
        if (raw is! String) continue;
        final decoded = const JsonRpcCodec().decode(raw);
        if (decoded is! JsonRpcResponse || decoded.id != requestId) continue;
        if (!decoded.isSuccess) {
          throw StateError(decoded.error!.message);
        }
        return decoded.result;
      }
      throw StateError('Host closed the RPC connection');
    };

    final initialized =
        await call('devex.initialize', <String, Object?>{
              'protocolVersion': 1,
              'sessionToken': token,
            })
            as Map<String, Object?>;
    final capabilities = (initialized['capabilities']! as List<Object?>)
        .cast<String>();
    for (final required in const <String>[
      'devex.session.start',
      'devex.gateway.start',
      'devex.gateway.traffic',
    ]) {
      if (!capabilities.contains(required)) {
        throw StateError('Missing Host capability $required');
      }
    }

    final session =
        await call('devex.session.start', const <String, Object?>{
              'launchProfileId': 'sample-web',
              'targetOrigin': 'http://127.0.0.1:8080',
            })
            as Map<String, Object?>;
    sessionId = session['id']! as String;
    await _waitForHttp(client, Uri.parse('http://127.0.0.1:8080'));

    final gateway =
        await call('devex.gateway.start', <String, Object?>{
              'ownerSessionId': sessionId,
              'planArtifactDigest': artifactDigest.value,
            })
            as Map<String, Object?>;
    gatewaySessionId = gateway['id']! as String;
    final gatewayOrigin = Uri.parse(gateway['dataOrigin']! as String);

    final dashboard = await _jsonRequest(
      client,
      gatewayOrigin.resolve('/v1/dashboard'),
    );
    final fixture = await _jsonRequest(
      client,
      gatewayOrigin.resolve('/v1/runtime/configuration?view=tooling'),
    );
    final traffic =
        await call('devex.gateway.traffic', <String, Object?>{
              'gatewaySessionId': gatewaySessionId,
              'afterSequence': 0,
              'limit': 100,
            })
            as List<Object?>;

    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': 'passed',
        'profile': 'full-local',
        'launchProfile': 'sample-web',
        'gatewayPreset': 'showcase-hybrid',
        'gatewayPlanDigest': compiled.compilation.plan.digest.value,
        'dashboardProjects': (dashboard['projects']! as List<Object?>).length,
        'fixtureMode': fixture['mode'],
        'trafficEvents': traffic.length,
      }),
    );
  } finally {
    if (gatewaySessionId != null) {
      try {
        await call('devex.gateway.stop', <String, Object?>{
          'gatewaySessionId': gatewaySessionId,
        });
      } on Object {
        // Continue cleanup with the owning Session.
      }
    }
    if (sessionId != null) {
      try {
        await call('devex.session.stop', <String, Object?>{
          'sessionId': sessionId,
        });
      } on Object {
        // Host shutdown owns any remaining process.
      }
    }
    await messages?.cancel();
    await socket?.close();
    client.close(force: true);
  }
}

Future<void> _waitForHttp(HttpClient client, Uri uri) async {
  for (var attempt = 0; attempt < 240; attempt += 1) {
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == 200) return;
    } on SocketException {
      // Flutter web-server is still compiling or binding.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('Flutter target did not become ready at $uri');
}

Future<Map<String, Object?>> _jsonRequest(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  final bytes = await response.fold<List<int>>(
    <int>[],
    (output, chunk) => output..addAll(chunk),
  );
  if (response.statusCode != 200 || bytes.length > 1024 * 1024) {
    throw StateError('Unexpected response ${response.statusCode} from $uri');
  }
  return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
}

Directory _repositoryRoot() {
  var current = File.fromUri(Platform.script).parent;
  while (current.parent.path != current.path) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('DevExKit repository root not found');
}
