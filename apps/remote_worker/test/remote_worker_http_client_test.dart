import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_remote_worker/remote_worker.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('worker transfers are scoped and heartbeat rotates its bearer token', () async {
    final root = Directory.systemTemp.createTempSync('devex-worker-http-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = Uri.parse('http://127.0.0.1:${server.port}');
    final inputBytes = <int>[1, 2, 3, 4];
    final inputDigest = Digest.bytes(inputBytes);
    var uploaded = <int>[];
    var currentToken = 'initial-token';
    final requests = <String>[];
    final subscription = server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      if (request.uri.path.startsWith('/v1/')) {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer $currentToken',
        );
      }
      if (request.method == 'POST' &&
          request.uri.path.endsWith('/artifacts/download-grant')) {
        await request.drain<void>();
        await _json(
          request.response,
          _grant(
            origin.resolve('/objects/input'),
            'GET',
            _descriptor(inputDigest, inputBytes.length),
          ),
        );
      } else if (request.method == 'GET' &&
          request.uri.path == '/objects/input') {
        request.response
          ..statusCode = 200
          ..contentLength = inputBytes.length
          ..add(inputBytes);
        await request.response.close();
      } else if (request.method == 'POST' &&
          request.uri.path.endsWith('/artifacts/upload-grant')) {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        final descriptor = _descriptor(
          Digest(body['digest']! as String),
          body['size']! as int,
          mediaType: body['mediaType']! as String,
          classification: body['classification']! as String,
        );
        await _json(
          request.response,
          _grant(origin.resolve('/objects/output'), 'PUT', descriptor),
        );
      } else if (request.method == 'PUT' &&
          request.uri.path == '/objects/output') {
        uploaded = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        request.response.statusCode = 200;
        await request.response.close();
      } else if (request.method == 'POST' &&
          request.uri.path.endsWith('/heartbeat')) {
        await request.drain<void>();
        currentToken = 'rotated-token';
        await _json(request.response, <String, Object?>{
          'ok': true,
          'capabilityToken': currentToken,
        });
      } else if (request.method == 'POST' &&
          request.uri.path.endsWith('/state')) {
        await request.drain<void>();
        await _json(request.response, const <String, Object?>{'ok': true});
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    final capability = _capability(inputDigest);
    final client = RemoteWorkerHttpClient(
      controlOrigin: origin,
      artifactOrigin: origin,
      capabilityToken: currentToken,
      allowInsecureLoopback: true,
    );
    addTearDown(client.close);
    final downloaded = await client.download(
      capability: capability,
      artifact: RemoteArtifactInput(
        role: 'webBuild',
        digest: inputDigest,
        size: inputBytes.length,
        mediaType: 'application/octet-stream',
      ),
      destination: root,
    );
    expect(downloaded.readAsBytesSync(), inputBytes);

    final output = File('${root.path}/result.png')
      ..writeAsBytesSync(<int>[9, 8, 7]);
    final descriptor = await client.upload(
      capability: capability,
      artifact: RemoteGeneratedArtifact(
        role: 'screenshot',
        file: output,
        mediaType: 'image/png',
        classification: 'internal',
      ),
    );
    expect(descriptor.digest, Digest.bytes(<int>[9, 8, 7]));
    expect(uploaded, <int>[9, 8, 7]);

    await client.heartbeat(capability);
    await client.state(capability: capability, state: RemoteRunState.running);
    expect(
      requests,
      containsAll(<String>[
        'POST /v1/remote/tenants/tenant-a/workers/worker-001/runs/run-001/artifacts/download-grant',
        'POST /v1/remote/tenants/tenant-a/workers/worker-001/runs/run-001/artifacts/upload-grant',
        'POST /v1/remote/tenants/tenant-a/workers/worker-001/runs/run-001/heartbeat',
        'POST /v1/remote/tenants/tenant-a/workers/worker-001/runs/run-001/state',
      ]),
    );
  });
}

VerifiedRemoteCapability _capability(Digest input) => VerifiedRemoteCapability(
  tenantId: 'tenant-a',
  runId: 'run-001',
  workerId: 'worker-001',
  tokenId: 'token-001',
  generation: 1,
  planDigest: Digest.semantic('plan'),
  artifactDigests: <Digest>{input},
  scopes: const <String>{
    'artifact:read',
    'artifact:write',
    'run:heartbeat',
    'run:complete',
  },
  expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
);

HostedBlobDescriptor _descriptor(
  Digest digest,
  int size, {
  String mediaType = 'application/octet-stream',
  String classification = 'internal',
}) => HostedBlobDescriptor(
  tenantId: 'tenant-a',
  digest: digest,
  size: size,
  mediaType: mediaType,
  classification: classification,
  objectKey: 'tenants/tenant-a/blobs/sha256/${digest.value.substring(7)}',
);

Map<String, Object?> _grant(
  Uri uri,
  String method,
  HostedBlobDescriptor descriptor,
) => <String, Object?>{
  'ok': true,
  'transfer': <String, Object?>{
    'method': method,
    'url': uri.toString(),
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
    'descriptor': descriptor.toJson(),
    'requiredHeaders': const <String, String>{},
  },
};

Future<void> _json(HttpResponse response, Map<String, Object?> body) async {
  response
    ..statusCode = 200
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await response.close();
}
