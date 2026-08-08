import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:jose/jose.dart';
import 'package:remote_session_gateway/remote_session_gateway.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

void main() {
  test(
    'relays bounded directional frames and rejects ticket replay/cross-tenant access',
    () async {
      final clock = _Clock(DateTime.utc(2026, 8, 9, 12));
      final generated = JsonWebKey.generate('RS256');
      final security = JoseRemoteExecutionSecurity(
        signingKey: generated,
        keyId: 'remote-session-key-001',
        algorithm: 'RS256',
      );
      final public = JsonWebKey.fromJson(<String, dynamic>{
        ...JsonWebKey.fromCryptoKeys(
          publicKey: generated.cryptoKeyPair.publicKey,
        ).toJson(),
        'kid': 'remote-session-key-001',
      });
      final verifier = RemoteWorkerTokenVerifier(
        trustedKeys: JsonWebKeySet.fromJson(<String, Object?>{
          'keys': <Object?>[public.toJson()],
        }),
        allowedAlgorithms: const <String>{'RS256'},
        clock: clock,
      );
      final plan = _plan(clock.nowUtc());
      final capability = await security.issue(
        plan: plan,
        lease: RemoteLease(
          tenantId: plan.tenantId,
          runId: plan.runId,
          workerId: 'worker-001',
          tokenId: 'lease-token-001',
          generation: 1,
          acquiredAt: clock.nowUtc(),
          heartbeatAt: clock.nowUtc(),
          expiresAt: clock.nowUtc().add(const Duration(minutes: 1)),
        ),
        scopes: const <String>{
          'artifact:read',
          'artifact:write',
          'run:heartbeat',
          'run:complete',
          'stream:write',
        },
      );
      final viewerTicket = await security.issueViewerTicket(
        _viewerTicket(clock, tenantId: 'tenant-a', nonce: 'viewer-ticket-001'),
      );
      final application = RemoteSessionGatewayApplication(
        verifier: verifier,
        expectedRunId: plan.runId,
        allowedViewerOrigins: const <String>{'https://studio.example.test'},
        sessionDeadline: plan.expiresAt,
        clock: clock,
      );
      final server = await shelf_io.serve(
        application.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
        await application.close();
      });
      final base = Uri.parse('ws://127.0.0.1:${server.port}');
      final worker = await WebSocket.connect(
        base.resolve('/v1/sessions/run-001/worker').toString(),
        protocols: const <String>[RemoteSessionGrant.protocol],
      );
      final viewer = await WebSocket.connect(
        base.resolve('/v1/sessions/run-001/viewer').toString(),
        protocols: const <String>[RemoteSessionGrant.protocol],
        headers: const <String, String>{
          'Origin': 'https://studio.example.test',
        },
      );
      addTearDown(() async {
        await worker.close();
        await viewer.close();
      });
      final workerMessages = StreamIterator<Object?>(worker);
      final viewerMessages = StreamIterator<Object?>(viewer);

      worker.add(_authentication(capability));
      expect(await workerMessages.moveNext(), isTrue);
      expect(_type(workerMessages.current), 'authenticated');
      viewer.add(_authentication(viewerTicket));
      expect(await viewerMessages.moveNext(), isTrue);
      expect(_type(viewerMessages.current), 'authenticated');
      expect(await workerMessages.moveNext(), isTrue);
      expect(_type(workerMessages.current), 'session.ready');
      expect(await viewerMessages.moveNext(), isTrue);
      expect(_type(viewerMessages.current), 'session.ready');

      worker.add(
        RemoteStreamFrameCodec.encode(
          RemoteStreamFrame(
            channel: RemoteStreamChannel.videoH264,
            sequence: 1,
            payload: const <int>[0, 0, 0, 1, 0x67],
          ),
        ),
      );
      expect(await viewerMessages.moveNext(), isTrue);
      final video = RemoteStreamFrameCodec.decode(
        viewerMessages.current! as List<int>,
      );
      expect(video.channel, RemoteStreamChannel.videoH264);
      expect(video.sequence, 1);

      viewer.add(
        RemoteStreamFrameCodec.encode(
          RemoteStreamFrame(
            channel: RemoteStreamChannel.control,
            sequence: 1,
            payload: utf8.encode('{"type":"key","key":"ENTER"}'),
          ),
        ),
      );
      expect(await workerMessages.moveNext(), isTrue);
      final control = RemoteStreamFrameCodec.decode(
        workerMessages.current! as List<int>,
      );
      expect(control.channel, RemoteStreamChannel.control);

      await viewer.close();
      await viewer.done;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final replay = await WebSocket.connect(
        base.resolve('/v1/sessions/run-001/viewer').toString(),
        protocols: const <String>[RemoteSessionGrant.protocol],
        headers: const <String, String>{
          'Origin': 'https://studio.example.test',
        },
      );
      final replaySubscription = replay.listen((_) {});
      replay.add(_authentication(viewerTicket));
      await replay.done.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('replayed viewer was not closed'),
      );
      expect(replay.closeCode, 4409);
      await replaySubscription.cancel();
      await replay.close();

      final crossTenant = await security.issueViewerTicket(
        _viewerTicket(clock, tenantId: 'tenant-b', nonce: 'viewer-ticket-002'),
      );
      final cross = await WebSocket.connect(
        base.resolve('/v1/sessions/run-001/viewer').toString(),
        protocols: const <String>[RemoteSessionGrant.protocol],
        headers: const <String, String>{
          'Origin': 'https://studio.example.test',
        },
      );
      final crossSubscription = cross.listen((_) {});
      cross.add(_authentication(crossTenant));
      await cross.done.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('cross-tenant viewer was not closed'),
      );
      expect(cross.closeCode, 4403);
      await crossSubscription.cancel();
      await cross.close();
    },
  );

  test(
    'bootstraps a cookie-bound web target and revokes it with the viewer',
    () async {
      final clock = _Clock(DateTime.utc(2026, 8, 9, 12));
      final generated = JsonWebKey.generate('RS256');
      final security = JoseRemoteExecutionSecurity(
        signingKey: generated,
        keyId: 'remote-session-key-002',
        algorithm: 'RS256',
      );
      final public = JsonWebKey.fromJson(<String, dynamic>{
        ...JsonWebKey.fromCryptoKeys(
          publicKey: generated.cryptoKeyPair.publicKey,
        ).toJson(),
        'kid': 'remote-session-key-002',
      });
      final verifier = RemoteWorkerTokenVerifier(
        trustedKeys: JsonWebKeySet.fromJson(<String, Object?>{
          'keys': <Object?>[public.toJson()],
        }),
        allowedAlgorithms: const <String>{'RS256'},
        clock: clock,
      );
      final plan = _plan(clock.nowUtc());
      final capability = await security.issue(
        plan: plan,
        lease: RemoteLease(
          tenantId: plan.tenantId,
          runId: plan.runId,
          workerId: 'worker-web',
          tokenId: 'lease-token-web',
          generation: 1,
          acquiredAt: clock.nowUtc(),
          heartbeatAt: clock.nowUtc(),
          expiresAt: clock.nowUtc().add(const Duration(minutes: 1)),
        ),
        scopes: const <String>{
          'artifact:read',
          'artifact:write',
          'run:heartbeat',
          'run:complete',
          'stream:write',
        },
      );
      final viewerTicket = await security.issueViewerTicket(
        _viewerTicket(clock, tenantId: 'tenant-a', nonce: 'viewer-ticket-web'),
      );
      final forwardedCookies = <String?>[];
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final targetSubscription = target.listen((request) async {
        forwardedCookies.add(request.headers.value(HttpHeaders.cookieHeader));
        if (request.uri.path == '/') {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<!doctype html><head><base href="/"></head><body>target</body>',
          );
        } else if (request.uri.path == '/main.dart.js') {
          request.response.headers.contentType = ContentType(
            'application',
            'javascript',
          );
          request.response.write('self.targetMarker=true;');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      addTearDown(() async {
        await targetSubscription.cancel();
        await target.close(force: true);
      });
      final application = RemoteSessionGatewayApplication(
        verifier: verifier,
        expectedRunId: plan.runId,
        allowedViewerOrigins: const <String>{'https://studio.example.test'},
        sessionDeadline: plan.expiresAt,
        clock: clock,
        webTargetOrigin: Uri.parse('http://127.0.0.1:${target.port}'),
        ids: _Ids(),
      );
      final server = await shelf_io.serve(
        application.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
        await application.close();
      });
      final webSocketBase = Uri.parse('ws://127.0.0.1:${server.port}');
      final httpBase = Uri.parse('http://127.0.0.1:${server.port}');
      final worker = await WebSocket.connect(
        webSocketBase.resolve('/v1/sessions/run-001/worker').toString(),
        protocols: const <String>[RemoteSessionGrant.protocol],
      );
      final viewer = await WebSocket.connect(
        webSocketBase.resolve('/v1/sessions/run-001/viewer').toString(),
        protocols: const <String>[RemoteSessionGrant.protocol],
        headers: const <String, String>{
          'Origin': 'https://studio.example.test',
        },
      );
      final workerMessages = StreamIterator<Object?>(worker);
      final viewerMessages = StreamIterator<Object?>(viewer);
      addTearDown(() async {
        await workerMessages.cancel();
        await viewerMessages.cancel();
        await worker.close();
        await viewer.close();
      });

      worker.add(_authentication(capability));
      expect(await workerMessages.moveNext(), isTrue);
      viewer.add(_authentication(viewerTicket));
      expect(await viewerMessages.moveNext(), isTrue);
      expect(await workerMessages.moveNext(), isTrue);
      expect(_type(workerMessages.current), 'session.ready');
      expect(await viewerMessages.moveNext(), isTrue);
      expect(_type(viewerMessages.current), 'session.ready');
      expect(await viewerMessages.moveNext(), isTrue);
      final notice =
          jsonDecode(viewerMessages.current! as String) as Map<String, Object?>;
      expect(notice['type'], 'web.bootstrap.required');
      expect(notice['endpoint'], '/v1/sessions/run-001/web/bootstrap');

      final browser = HttpClient();
      addTearDown(() => browser.close(force: true));
      final denied = await browser.postUrl(
        httpBase.resolve('/v1/sessions/run-001/web/bootstrap'),
      );
      denied.headers
        ..contentType = ContentType.json
        ..set('origin', 'https://attacker.example.test');
      denied.write(jsonEncode(<String, Object?>{'grant': notice['grant']}));
      final deniedResponse = await denied.close();
      expect(deniedResponse.statusCode, HttpStatus.forbidden);
      await deniedResponse.drain<void>();

      final bootstrap = await browser.postUrl(
        httpBase.resolve('/v1/sessions/run-001/web/bootstrap'),
      );
      bootstrap.headers
        ..contentType = ContentType.json
        ..set('origin', 'https://studio.example.test');
      bootstrap.write(jsonEncode(<String, Object?>{'grant': notice['grant']}));
      final bootstrapResponse = await bootstrap.close();
      expect(bootstrapResponse.statusCode, HttpStatus.created);
      final setCookie = bootstrapResponse.headers.value(
        HttpHeaders.setCookieHeader,
      );
      expect(setCookie, contains('Secure; HttpOnly; SameSite=None'));
      final cookie = setCookie!.split(';').first;
      final bootstrapJson =
          jsonDecode(await utf8.decoder.bind(bootstrapResponse).join())
              as Map<String, Object?>;
      expect(bootstrapJson['target'], '/v1/sessions/run-001/web/target/');

      final index = await browser.getUrl(
        httpBase.resolve('/v1/sessions/run-001/web/target/'),
      );
      index.headers.set(HttpHeaders.cookieHeader, cookie);
      final indexResponse = await index.close();
      expect(indexResponse.statusCode, HttpStatus.ok);
      final html = await utf8.decoder.bind(indexResponse).join();
      expect(html, contains('<base href="/v1/sessions/run-001/web/target/">'));

      final asset = await browser.getUrl(
        httpBase.resolve('/v1/sessions/run-001/web/target/main.dart.js'),
      );
      asset.headers.set(HttpHeaders.cookieHeader, cookie);
      final assetResponse = await asset.close();
      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(
        await utf8.decoder.bind(assetResponse).join(),
        contains('targetMarker'),
      );
      expect(forwardedCookies, everyElement(isNull));

      await viewer.close();
      await viewer.done;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final revoked = await browser.getUrl(
        httpBase.resolve('/v1/sessions/run-001/web/target/'),
      );
      revoked.headers.set(HttpHeaders.cookieHeader, cookie);
      final revokedResponse = await revoked.close();
      expect(revokedResponse.statusCode, HttpStatus.forbidden);
      await revokedResponse.drain<void>();
    },
  );
}

String _authentication(String token) =>
    jsonEncode(<String, Object?>{'type': 'authenticate', 'token': token});

String? _type(Object? message) {
  if (message is! String) return null;
  return (jsonDecode(message) as Map<String, Object?>)['type'] as String?;
}

RemoteExecutionPlan _plan(DateTime now) {
  final artifact = RemoteArtifactInput(
    role: 'webBuild',
    digest: Digest.semantic('web-build'),
    size: 1024,
    mediaType: 'application/zip',
  );
  return RemoteExecutionPlan(
    tenantId: 'tenant-a',
    runId: 'run-001',
    requestDigest: Digest.semantic('request'),
    target: RemoteTargetKind.web,
    mode: RemoteRunMode.interactive,
    interactiveTransport: RemoteInteractiveTransport.webDirect,
    artifacts: <RemoteArtifactInput>[artifact],
    executionFingerprintDigest: Digest.semantic('fingerprint'),
    containmentPolicyDigest: Digest.semantic('containment'),
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
    nonce: 'plan-nonce-001',
  );
}

RemoteSessionTicket _viewerTicket(
  _Clock clock, {
  required String tenantId,
  required String nonce,
}) => RemoteSessionTicket(
  tenantId: tenantId,
  runId: 'run-001',
  principalId: tenantId == 'tenant-a' ? 'principal-a' : 'principal-b',
  role: RemoteSessionRole.viewer,
  allowedTransports: const <RemoteInteractiveTransport>{
    RemoteInteractiveTransport.webDirect,
  },
  issuedAt: clock.nowUtc(),
  expiresAt: clock.nowUtc().add(const Duration(minutes: 1)),
  nonce: nonce,
);

final class _Clock implements Clock {
  const _Clock(this.value);

  final DateTime value;

  @override
  int monotonicMicroseconds() => value.microsecondsSinceEpoch;

  @override
  DateTime nowUtc() => value;
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String nextId() => 'gateway-secret-${++_value}-xxxxxxxxxxxxxxxxxxxxxxxx';
}
