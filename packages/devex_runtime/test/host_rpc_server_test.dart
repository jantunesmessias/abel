import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  final studioOrigin = Uri.parse('http://127.0.0.1:8080');
  late HostRpcServer server;
  late _FakeClock clock;
  late HostResourceRegistry resources;

  setUp(() async {
    clock = _FakeClock(DateTime.utc(2026, 8, 10, 12));
    resources = HostResourceRegistry(clock: clock, ids: _TestIds());
    server = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: token,
      resourceRegistry: resources,
    );
    await server.start();
  });

  tearDown(() => server.close());

  test(
    'negotiates protocol over an authenticated loopback WebSocket',
    () async {
      expect(server.webSocketUri.hasQuery, isFalse);
      final channel = IOWebSocketChannel.connect(
        server.webSocketUri,
        headers: <String, String>{'Origin': studioOrigin.origin},
      );
      await channel.ready;
      channel.sink.add(
        const JsonRpcRequest(
          method: 'devex.initialize',
          id: 'initialize-1',
          params: <String, Object?>{
            'protocolVersion': 1,
            'sessionToken': token,
          },
        ).encode(),
      );

      final response = const JsonRpcCodec().decode(
        await channel.stream.first as String,
      );

      expect(response, isA<JsonRpcResponse>());
      final result =
          (response as JsonRpcResponse).result! as Map<String, Object?>;
      expect(result['protocolVersion'], 1);
      expect(result['capabilities'], contains('events.resume'));
      await channel.sink.close();
    },
  );

  test('rejects every RPC except initialize before authentication', () async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;
    channel.sink.add(
      const JsonRpcRequest(
        method: 'devex.ping',
        id: 'ping-before-auth',
        params: <String, Object?>{},
      ).encode(),
    );

    final response =
        const JsonRpcCodec().decode(await channel.stream.first as String)
            as JsonRpcResponse;
    expect(response.error?.code, -32001);
    await channel.sink.close();
  });

  test('rejects a mismatched Origin before upgrade', () async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': 'http://attacker.test'},
    );

    await expectLater(channel.ready, throwsA(anything));
  });

  test('rejects query-bearing RPC URLs before upgrade', () async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri.replace(
        queryParameters: <String, String>{
          'token': 'fedcba9876543210fedcba9876543210',
        },
      ),
      headers: <String, String>{'Origin': studioOrigin.origin},
    );

    await expectLater(channel.ready, throwsA(anything));
  });

  test('rejects a mismatched session token during initialize', () async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;
    channel.sink.add(
      const JsonRpcRequest(
        method: 'devex.initialize',
        id: 'initialize-denied',
        params: <String, Object?>{
          'protocolVersion': 1,
          'sessionToken': 'fedcba9876543210fedcba9876543210',
        },
      ).encode(),
    );

    final response =
        const JsonRpcCodec().decode(await channel.stream.first as String)
            as JsonRpcResponse;
    expect(response.error?.code, -32002);
    await channel.sink.close();
  });

  test(
    'closes a connection whose message exceeds the negotiated limit',
    () async {
      await server.close();
      server = HostRpcServer(
        studioOrigin: studioOrigin,
        sessionToken: token,
        maxMessageBytes: 64,
      );
      await server.start();
      final channel = IOWebSocketChannel.connect(
        server.webSocketUri,
        headers: <String, String>{'Origin': studioOrigin.origin},
      );
      await channel.ready;

      channel.sink.add('x' * 65);
      await channel.stream.drain<void>();
      await _waitUntil(() => server.activeConnections == 0);

      expect(server.activeConnections, 0);
    },
  );

  test('replays journal events after reconnect', () async {
    await server.publishEvent('devex.session.changed', <String, Object?>{
      'sessionId': 'session-1',
    });
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;
    final messages = StreamIterator<Object?>(channel.stream);
    channel.sink.add(
      const JsonRpcRequest(
        method: 'devex.initialize',
        id: 'initialize-resume',
        params: <String, Object?>{'protocolVersion': 1, 'sessionToken': token},
      ).encode(),
    );
    expect(await messages.moveNext(), isTrue);
    channel.sink.add(
      const JsonRpcRequest(
        method: 'devex.resume',
        id: 'resume-1',
        params: <String, Object?>{'cursor': 0},
      ).encode(),
    );

    expect(await messages.moveNext(), isTrue);
    final raw = messages.current! as String;
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    final result = decoded['result']! as Map<String, Object?>;
    final events = result['events']! as List<Object?>;

    expect(events, hasLength(1));
    expect((events.single! as Map<String, Object?>)['sequence'], 1);
    await messages.cancel();
    await channel.sink.close();
  });

  test(
    'replaces an oversized application response with a bounded error',
    () async {
      await server.close();
      server = HostRpcServer(
        studioOrigin: studioOrigin,
        sessionToken: token,
        maxMessageBytes: 1024,
        applicationMethods: <String, HostRpcMethodHandler>{
          'devex.large': (_) => <String, Object?>{'value': 'x' * 2048},
        },
      );
      await server.start();
      final channel = IOWebSocketChannel.connect(
        server.webSocketUri,
        headers: <String, String>{'Origin': studioOrigin.origin},
      );
      await channel.ready;
      final messages = StreamIterator<Object?>(channel.stream);
      channel.sink.add(
        const JsonRpcRequest(
          method: 'devex.initialize',
          id: 'initialize-large',
          params: <String, Object?>{
            'protocolVersion': 1,
            'sessionToken': token,
          },
        ).encode(),
      );
      expect(await messages.moveNext(), isTrue);
      channel.sink.add(
        const JsonRpcRequest(
          method: 'devex.large',
          id: 'large-1',
          params: <String, Object?>{},
        ).encode(),
      );

      expect(await messages.moveNext(), isTrue);
      final raw = messages.current! as String;
      final response = const JsonRpcCodec().decode(raw) as JsonRpcResponse;

      expect(utf8.encode(raw).length, lessThanOrEqualTo(1024));
      expect(response.error?.code, -32004);
      await messages.cancel();
      await channel.sink.close();
    },
  );

  test('rejects an oversized event before journaling it', () async {
    await server.close();
    server = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: token,
      maxMessageBytes: 128,
    );
    await server.start();

    await expectLater(
      server.publishEvent('devex.large', <String, Object?>{'value': 'x' * 256}),
      throwsFormatException,
    );
    expect(server.journal.latestSequence, 0);
  });

  test(
    'serves scoped resources only to the granted Origin until TTL',
    () async {
      final bytes = utf8.encode('{"workspace":"sample"}');
      final handle = resources.grantBytes(
        hostOrigin: server.httpUri,
        audienceOrigin: studioOrigin,
        bytes: bytes,
        mediaType: 'application/json',
        purpose: 'workspace-snapshot',
        ttl: const Duration(minutes: 1),
      );

      final accepted = await _get(handle.uri, origin: studioOrigin.origin);
      expect(accepted.statusCode, HttpStatus.ok);
      expect(accepted.bytes, bytes);
      expect(accepted.headers.value('cache-control'), 'no-store');
      expect(
        accepted.headers.value('access-control-allow-origin'),
        studioOrigin.origin,
      );

      final denied = await _get(handle.uri, origin: 'http://attacker.invalid');
      expect(denied.statusCode, HttpStatus.forbidden);
      final malformedOrigin = await _get(handle.uri, origin: '/relative');
      expect(malformedOrigin.statusCode, HttpStatus.forbidden);
      final queryBearing = await _get(
        handle.uri.replace(queryParameters: const <String, String>{'x': '1'}),
        origin: studioOrigin.origin,
      );
      expect(queryBearing.statusCode, HttpStatus.notFound);

      clock.advance(const Duration(minutes: 1));
      final expired = await _get(handle.uri, origin: studioOrigin.origin);
      expect(expired.statusCode, HttpStatus.notFound);
      expect(resources.activeCount, 0);
    },
  );

  test('rejects sensitive or quota-breaking resource grants', () {
    expect(
      () => resources.grantBytes(
        hostOrigin: server.httpUri,
        audienceOrigin: studioOrigin,
        bytes: const <int>[1],
        mediaType: 'application/octet-stream',
        purpose: 'workspace-snapshot',
        classification: ArtifactClassification.sensitive,
      ),
      throwsArgumentError,
    );
    expect(
      () => resources.grantBytes(
        hostOrigin: server.httpUri,
        audienceOrigin: studioOrigin,
        bytes: const <int>[1],
        mediaType: 'application/octet-stream',
        purpose: 'workspace-snapshot',
        ttl: const Duration(hours: 1),
      ),
      throwsArgumentError,
    );
  });
}

Future<_HttpResult> _get(Uri uri, {required String origin}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set('origin', origin);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (result, chunk) => result..addAll(chunk),
    );
    return _HttpResult(response.statusCode, response.headers, bytes);
  } finally {
    client.close(force: true);
  }
}

final class _HttpResult {
  const _HttpResult(this.statusCode, this.headers, this.bytes);

  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}

final class _FakeClock implements Clock {
  _FakeClock(this._now);

  DateTime _now;

  void advance(Duration duration) => _now = _now.add(duration);

  @override
  int monotonicMicroseconds() => 0;

  @override
  DateTime nowUtc() => _now;
}

final class _TestIds implements IdGenerator {
  var _next = 0;

  @override
  String nextId() => 'resource-${_next++}-${'x' * 32}';
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Condition was not met before the deadline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
