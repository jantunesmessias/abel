import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
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
          method: 'workspace.initialize',
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
      expect(result['maxMessageBytes'], 64 * 1024);
      expect(server.maxMessageBytes, 64 * 1024);
      await channel.sink.close();
    },
  );

  test(
    'preserves params-only methods and advertises the deterministic union',
    () async {
      await server.close();
      HostRpcConnectionContext? observedContext;
      server = HostRpcServer(
        studioOrigin: studioOrigin,
        sessionToken: token,
        applicationMethods: <String, HostRpcMethodHandler>{
          'test.params': (params) => <String, Object?>{
            'params': params['value'],
          },
        },
        connectionAwareMethods: <String, HostRpcConnectionMethodHandler>{
          'test.contextual': (params, context) {
            observedContext = context;
            return <String, Object?>{'context': 'available'};
          },
        },
      );
      await server.start();
      final channel = IOWebSocketChannel.connect(
        server.webSocketUri,
        headers: <String, String>{'Origin': studioOrigin.origin},
      );
      await channel.ready;
      final messages = StreamIterator<Object?>(channel.stream);

      final initialize = await _rpcRequest(
        channel,
        messages,
        const JsonRpcRequest(
          method: 'workspace.initialize',
          id: 'initialize-union',
          params: <String, Object?>{
            'protocolVersion': 1,
            'sessionToken': token,
          },
        ),
      );
      final initializeResult = initialize.result! as Map<String, Object?>;
      expect(initializeResult['capabilities'], <String>[
        'events.resume',
        'session.heartbeat',
        'test.contextual',
        'test.params',
      ]);

      final paramsOnly = await _rpcRequest(
        channel,
        messages,
        const JsonRpcRequest(
          method: 'test.params',
          id: 'params-1',
          params: <String, Object?>{'value': 'preserved'},
        ),
      );
      expect(paramsOnly.result, <String, Object?>{'params': 'preserved'});

      final contextual = await _rpcRequest(
        channel,
        messages,
        const JsonRpcRequest(
          method: 'test.contextual',
          id: 'context-1',
          params: <String, Object?>{},
        ),
      );
      expect(contextual.result, <String, Object?>{'context': 'available'});
      expect(observedContext, isNotNull);
      await messages.cancel();
      await channel.sink.close();
    },
  );

  test('rejects method keys shared by both application maps', () async {
    await server.close();

    expect(
      () => HostRpcServer(
        studioOrigin: studioOrigin,
        sessionToken: token,
        applicationMethods: <String, HostRpcMethodHandler>{
          'test.duplicate': (_) => null,
        },
        connectionAwareMethods: <String, HostRpcConnectionMethodHandler>{
          'test.duplicate': (_, _) => null,
        },
      ),
      throwsArgumentError,
    );
  });

  test(
    'keeps epochs in-process and issues a new epoch after reconnect',
    () async {
      await server.close();
      final observedContexts = <HostRpcConnectionContext>[];
      final revokedEpochs = <String>[];
      server = HostRpcServer(
        studioOrigin: studioOrigin,
        sessionToken: token,
        studioBootstrapManifest: _kitManifest,
        connectionAwareMethods: <String, HostRpcConnectionMethodHandler>{
          'test.observeContext': (_, context) {
            observedContexts.add(context);
            return <String, Object?>{'status': 'ok'};
          },
        },
        onConnectionClosed: (context) async {
          await Future<void>.delayed(Duration.zero);
          revokedEpochs.add(context.connectionEpoch);
        },
      );
      await server.start();

      final wireFrames = <String>[];
      for (var connection = 0; connection < 2; connection += 1) {
        final channel = IOWebSocketChannel.connect(
          server.webSocketUri,
          headers: <String, String>{'Origin': studioOrigin.origin},
        );
        await channel.ready;
        final messages = StreamIterator<Object?>(channel.stream);
        wireFrames.add(
          await _rpcRequestRaw(
            channel,
            messages,
            JsonRpcRequest(
              method: 'workspace.initialize',
              id: 'initialize-context-$connection',
              params: const <String, Object?>{
                'protocolVersion': 1,
                'sessionToken': token,
              },
            ),
          ),
        );
        wireFrames.add(
          await _rpcRequestRaw(
            channel,
            messages,
            JsonRpcRequest(
              method: 'test.observeContext',
              id: 'observe-context-$connection',
              params: const <String, Object?>{},
            ),
          ),
        );
        await messages.cancel();
        await channel.sink.close();
        await _waitUntil(() => revokedEpochs.length == connection + 1);
      }

      expect(observedContexts, hasLength(2));
      final firstEpoch = observedContexts.first.connectionEpoch;
      final secondEpoch = observedContexts.last.connectionEpoch;
      expect(firstEpoch, isNot(secondEpoch));
      for (final context in observedContexts) {
        final byteLength = utf8.encode(context.connectionEpoch).length;
        expect(byteLength, inInclusiveRange(1, 128));
        expect(context.toString(), isNot(contains(context.connectionEpoch)));
      }
      expect(revokedEpochs, <String>[firstEpoch, secondEpoch]);
      for (final frame in wireFrames) {
        expect(frame, isNot(contains(firstEpoch)));
        expect(frame, isNot(contains(secondEpoch)));
        expect(frame, isNot(contains('connectionEpoch')));
      }

      final bootstrap = await _get(
        server.httpUri.replace(path: '/studio/bootstrap.json'),
        origin: studioOrigin.origin,
      );
      final bootstrapBody = utf8.decode(bootstrap.bytes);
      expect(bootstrap.statusCode, HttpStatus.ok);
      expect(bootstrapBody, isNot(contains(firstEpoch)));
      expect(bootstrapBody, isNot(contains(secondEpoch)));
      expect(bootstrapBody, isNot(contains('connectionEpoch')));

      await server.close();
      expect(revokedEpochs, hasLength(2));
    },
  );

  test('revokes once after a graceful client disconnect', () async {
    await server.close();
    final revokedEpochs = <String>[];
    server = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: token,
      onConnectionClosed: (context) async {
        await Future<void>.delayed(Duration.zero);
        revokedEpochs.add(context.connectionEpoch);
      },
    );
    await server.start();
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;

    await channel.sink.close();
    await _waitUntil(() => revokedEpochs.length == 1);
    await server.close();

    expect(revokedEpochs, hasLength(1));
  });

  test(
    'drains an in-flight contextual call before revoking its epoch',
    () async {
      await server.close();
      final handlerStarted = Completer<void>();
      final allowHandlerToFinish = Completer<void>();
      final lifecycle = <String>[];
      server = HostRpcServer(
        studioOrigin: studioOrigin,
        sessionToken: token,
        connectionAwareMethods: <String, HostRpcConnectionMethodHandler>{
          'test.inFlight': (_, _) async {
            handlerStarted.complete();
            await allowHandlerToFinish.future;
            lifecycle.add('handler');
            return null;
          },
        },
        onConnectionClosed: (_) {
          lifecycle.add('revoke');
        },
      );
      await server.start();
      final channel = IOWebSocketChannel.connect(
        server.webSocketUri,
        headers: <String, String>{'Origin': studioOrigin.origin},
      );
      await channel.ready;
      final messages = StreamIterator<Object?>(channel.stream);
      await _rpcRequest(
        channel,
        messages,
        const JsonRpcRequest(
          method: 'workspace.initialize',
          id: 'initialize-in-flight',
          params: <String, Object?>{
            'protocolVersion': 1,
            'sessionToken': token,
          },
        ),
      );
      channel.sink.add(
        const JsonRpcRequest(
          method: 'test.inFlight',
          id: 'in-flight-1',
          params: <String, Object?>{},
        ).encode(),
      );
      await handlerStarted.future;

      await channel.sink.close();
      await Future<void>.delayed(Duration.zero);
      expect(lifecycle, isEmpty);
      allowHandlerToFinish.complete();
      await _waitUntil(() => lifecycle.length == 2);

      expect(lifecycle, <String>['handler', 'revoke']);
      await messages.cancel();
    },
  );

  test('fails fast when a contextual handler awaits server close', () async {
    await server.close();
    final revokedEpochs = <String>[];
    server = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: token,
      connectionAwareMethods: <String, HostRpcConnectionMethodHandler>{
        'test.closeFromHandler': (_, _) async {
          await server.close();
          return null;
        },
      },
      onConnectionClosed: (context) {
        revokedEpochs.add(context.connectionEpoch);
      },
    );
    await server.start();
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;
    final messages = StreamIterator<Object?>(channel.stream);
    await _rpcRequest(
      channel,
      messages,
      const JsonRpcRequest(
        method: 'workspace.initialize',
        id: 'initialize-reentrant-close',
        params: <String, Object?>{'protocolVersion': 1, 'sessionToken': token},
      ),
    );

    final raw = await _rpcRequestRaw(
      channel,
      messages,
      const JsonRpcRequest(
        method: 'test.closeFromHandler',
        id: 'reentrant-close-1',
        params: <String, Object?>{},
      ),
    ).timeout(const Duration(seconds: 1));
    final response = const JsonRpcCodec().decode(raw) as JsonRpcResponse;

    expect(response.error?.code, -32003);
    expect(response.error?.message, contains('connection-aware handler'));
    expect(utf8.encode(raw).length, lessThanOrEqualTo(server.maxMessageBytes));
    expect(server.isRunning, isTrue);
    await server.close();
    await messages.cancel();
    expect(revokedEpochs, hasLength(1));
  });

  test(
    'fails fast when a revocation callback awaits the outer server close',
    () async {
      await server.close();
      final callbackEntered = Completer<void>();
      final callbackExited = Completer<void>();
      final callbackErrors = <StateError>[];
      final zoneErrors = <Object>[];
      var callbackCalls = 0;

      await runZonedGuarded<Future<void>>(() async {
        server = HostRpcServer(
          studioOrigin: studioOrigin,
          sessionToken: token,
          onConnectionClosed: (_) async {
            callbackCalls += 1;
            if (callbackCalls == 1) callbackEntered.complete();
            try {
              await server.close().timeout(const Duration(seconds: 1));
              fail('Reentrant close completed from revocation callback');
            } on StateError catch (error) {
              callbackErrors.add(error);
            }
            if (callbackCalls == 1) callbackExited.complete();
          },
        );
        await server.start();
        final first = IOWebSocketChannel.connect(
          server.webSocketUri,
          headers: <String, String>{'Origin': studioOrigin.origin},
        );
        await first.ready;
        await _waitUntil(() => server.activeConnections == 1);

        final outerClose = server.close().timeout(const Duration(seconds: 1));
        await callbackEntered.future.timeout(const Duration(seconds: 1));
        await callbackExited.future.timeout(const Duration(seconds: 1));
        await outerClose;
        await first.stream.drain<void>();

        expect(callbackCalls, 1);
        expect(callbackErrors, hasLength(1));
        expect(callbackErrors.single.message, contains('revocation callback'));
        expect(server.activeConnections, 0);
        expect(server.isRunning, isFalse);

        await server.close().timeout(const Duration(seconds: 1));
        await server.start();
        final second = IOWebSocketChannel.connect(
          server.webSocketUri,
          headers: <String, String>{'Origin': studioOrigin.origin},
        );
        await second.ready;
        await _waitUntil(() => server.activeConnections == 1);
        await server.close().timeout(const Duration(seconds: 1));
        await second.stream.drain<void>();

        expect(callbackCalls, 2);
        expect(callbackErrors, hasLength(2));
        expect(server.activeConnections, 0);
        expect(server.isRunning, isFalse);
      }, (error, _) => zoneErrors.add(error))!;

      expect(zoneErrors, isEmpty);
    },
  );

  test('revokes once after an abnormal client transport error', () async {
    await server.close();
    final revokedEpochs = <String>[];
    server = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: token,
      onConnectionClosed: (context) {
        revokedEpochs.add(context.connectionEpoch);
      },
    );
    await server.start();

    await _abortRawWebSocket(server.webSocketUri, origin: studioOrigin.origin);
    await _waitUntil(() => revokedEpochs.length == 1);
    await server.close();

    expect(revokedEpochs, hasLength(1));
  });

  test('revokes once for each protocol-enforced close', () async {
    await server.close();
    final revokedEpochs = <String>[];
    server = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: token,
      maxMessageBytes: 64,
      onConnectionClosed: (context) {
        revokedEpochs.add(context.connectionEpoch);
      },
    );
    await server.start();

    final binary = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await binary.ready;
    binary.sink.add(const <int>[1, 2, 3]);
    await binary.stream.drain<void>();
    expect(binary.closeCode, HostRpcServer.closeUnsupportedFrame);

    final oversized = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await oversized.ready;
    oversized.sink.add('x' * 65);
    await oversized.stream.drain<void>();
    expect(oversized.closeCode, HostRpcServer.closeMessageTooLarge);

    await _waitUntil(() => revokedEpochs.length == 2);
    expect(revokedEpochs.toSet(), hasLength(2));
    await server.close();
    expect(revokedEpochs, hasLength(2));
  });

  test('a protocol close reports one revoke error to one Zone', () async {
    await server.close();
    final failure = _TestDropFailure('protocol revoke failed');
    final zoneErrors = <Object>[];
    var callbackCalls = 0;

    await runZonedGuarded<Future<void>>(() async {
      server = HostRpcServer(
        studioOrigin: studioOrigin,
        sessionToken: token,
        onConnectionClosed: (_) {
          callbackCalls += 1;
          throw failure;
        },
      );
      await server.start();
      final channel = IOWebSocketChannel.connect(
        server.webSocketUri,
        headers: <String, String>{'Origin': studioOrigin.origin},
      );
      await channel.ready;

      channel.sink.add(const <int>[1, 2, 3]);
      await channel.stream.drain<void>();
      await _waitUntil(() => callbackCalls == 1 && zoneErrors.length == 1);
      await server.close();
    }, (error, _) => zoneErrors.add(error))!;

    expect(callbackCalls, 1);
    expect(zoneErrors, <Object>[failure]);
  });

  test(
    'fails fast from revocation callbacks on natural and protocol drops',
    () async {
      await server.close();
      final callbackErrors = <StateError>[];
      final zoneErrors = <Object>[];
      var callbackCalls = 0;

      await runZonedGuarded<Future<void>>(() async {
        server = HostRpcServer(
          studioOrigin: studioOrigin,
          sessionToken: token,
          onConnectionClosed: (_) async {
            callbackCalls += 1;
            try {
              await server.close().timeout(const Duration(seconds: 1));
              fail('Reentrant close completed from revocation callback');
            } on StateError catch (error) {
              callbackErrors.add(error);
            }
          },
        );
        await server.start();

        final graceful = IOWebSocketChannel.connect(
          server.webSocketUri,
          headers: <String, String>{'Origin': studioOrigin.origin},
        );
        await graceful.ready;
        await _waitUntil(() => server.activeConnections == 1);
        await graceful.sink.close();
        await graceful.stream.drain<void>();
        await _waitUntil(
          () => callbackCalls == 1 && server.activeConnections == 0,
        );

        final protocol = IOWebSocketChannel.connect(
          server.webSocketUri,
          headers: <String, String>{'Origin': studioOrigin.origin},
        );
        await protocol.ready;
        protocol.sink.add(const <int>[1, 2, 3]);
        await protocol.stream.drain<void>();
        expect(protocol.closeCode, HostRpcServer.closeUnsupportedFrame);
        await _waitUntil(
          () => callbackCalls == 2 && server.activeConnections == 0,
        );

        expect(callbackErrors, hasLength(2));
        expect(
          callbackErrors.map((error) => error.message),
          everyElement(contains('revocation callback')),
        );
        expect(server.isRunning, isTrue);

        await server.close().timeout(const Duration(seconds: 1));
        await server.close().timeout(const Duration(seconds: 1));
        await server.start();
        await server.close().timeout(const Duration(seconds: 1));
      }, (error, _) => zoneErrors.add(error))!;

      expect(zoneErrors, isEmpty);
    },
  );

  test('server shutdown closes sockets and drains async revocation', () async {
    await server.close();
    final revokedEpochs = <String>[];
    final bothRevokesStarted = Completer<void>();
    final allowRevokesToFinish = Completer<void>();
    server = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: token,
      onConnectionClosed: (context) async {
        revokedEpochs.add(context.connectionEpoch);
        if (revokedEpochs.length == 2) bothRevokesStarted.complete();
        await allowRevokesToFinish.future;
      },
    );
    await server.start();
    final first = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    final second = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await Future.wait<void>(<Future<void>>[first.ready, second.ready]);
    await _waitUntil(() => server.activeConnections == 2);

    var shutdownCompleted = false;
    final shutdown = server.close().whenComplete(() {
      shutdownCompleted = true;
    });
    await bothRevokesStarted.future;
    expect(shutdownCompleted, isFalse);
    allowRevokesToFinish.complete();
    await shutdown;

    expect(revokedEpochs.toSet(), hasLength(2));
    expect(server.activeConnections, 0);
    await Future.wait<void>(<Future<void>>[
      first.stream.drain<void>(),
      second.stream.drain<void>(),
    ]);
    expect(first.closeCode, HostRpcServer.closeServerShutdown);
    expect(second.closeCode, HostRpcServer.closeServerShutdown);
  });

  test(
    'explicit close owns revoke error and supports second close and restart',
    () async {
      await server.close();
      final failure = _TestDropFailure('explicit revoke failed');
      final zoneErrors = <Object>[];
      var callbackCalls = 0;

      await runZonedGuarded<Future<void>>(() async {
        server = HostRpcServer(
          studioOrigin: studioOrigin,
          sessionToken: token,
          onConnectionClosed: (_) async {
            callbackCalls += 1;
            await Future<void>.delayed(Duration.zero);
            if (callbackCalls == 1) throw failure;
          },
        );
        await server.start();
        final first = IOWebSocketChannel.connect(
          server.webSocketUri,
          headers: <String, String>{'Origin': studioOrigin.origin},
        );
        await first.ready;

        await expectLater(server.close(), throwsA(same(failure)));
        await first.stream.drain<void>();
        expect(callbackCalls, 1);
        expect(server.isRunning, isFalse);

        await server.close();
        await server.start();
        final second = IOWebSocketChannel.connect(
          server.webSocketUri,
          headers: <String, String>{'Origin': studioOrigin.origin},
        );
        await second.ready;
        await server.close();
        await second.stream.drain<void>();
        expect(callbackCalls, 2);
        expect(server.isRunning, isFalse);
      }, (error, _) => zoneErrors.add(error))!;

      expect(zoneErrors, isEmpty);
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
        method: 'connection.ping',
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
        method: 'workspace.initialize',
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
    await server.publishEvent('session.changed', <String, Object?>{
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
        method: 'workspace.initialize',
        id: 'initialize-resume',
        params: <String, Object?>{'protocolVersion': 1, 'sessionToken': token},
      ).encode(),
    );
    expect(await messages.moveNext(), isTrue);
    channel.sink.add(
      const JsonRpcRequest(
        method: 'connection.resume',
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
          'test.large': (_) => <String, Object?>{'value': 'x' * 2048},
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
          method: 'workspace.initialize',
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
          method: 'test.large',
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
      server.publishEvent('test.large', <String, Object?>{'value': 'x' * 256}),
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

Future<void> _abortRawWebSocket(Uri uri, {required String origin}) async {
  final socket = await Socket.connect(uri.host, uri.port);
  final responseBytes = <int>[];
  final upgraded = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  subscription = socket.listen(
    (bytes) {
      if (upgraded.isCompleted) return;
      responseBytes.addAll(bytes);
      final response = latin1.decode(responseBytes, allowInvalid: true);
      if (!response.contains('\r\n\r\n')) return;
      if (!response.startsWith('HTTP/1.1 101 ')) {
        upgraded.completeError(
          StateError(
            'Raw WebSocket upgrade failed: ${response.split('\r\n').first}',
          ),
        );
        return;
      }
      upgraded.complete();
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!upgraded.isCompleted) upgraded.completeError(error, stackTrace);
    },
    onDone: () {
      if (!upgraded.isCompleted) {
        upgraded.completeError(
          StateError('Raw WebSocket closed before upgrade completed'),
        );
      }
    },
  );
  socket.add(
    ascii.encode(
      'GET ${uri.path} HTTP/1.1\r\n'
      'Host: ${uri.host}:${uri.port}\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n'
      'Sec-WebSocket-Version: 13\r\n'
      'Origin: $origin\r\n'
      '\r\n',
    ),
  );
  await socket.flush();
  await upgraded.future;
  socket.add(const <int>[0x81, 0x82, 0, 0, 0, 0, 0xc3, 0x28]);
  await socket.flush();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  socket.destroy();
  await subscription.cancel();
}

Future<JsonRpcResponse> _rpcRequest(
  IOWebSocketChannel channel,
  StreamIterator<Object?> messages,
  JsonRpcRequest request,
) async =>
    const JsonRpcCodec().decode(
          await _rpcRequestRaw(channel, messages, request),
        )
        as JsonRpcResponse;

Future<String> _rpcRequestRaw(
  IOWebSocketChannel channel,
  StreamIterator<Object?> messages,
  JsonRpcRequest request,
) async {
  channel.sink.add(request.encode());
  if (!await messages.moveNext()) {
    throw StateError('RPC connection closed before the response');
  }
  return messages.current! as String;
}

EffectiveKitManifest _kitManifest() => EffectiveKitManifest(
  resolvedPlanDigest: Digest.semantic('host-rpc-test-plan'),
  modules: const <EffectiveModuleState>[],
  commands: const <String>[],
  rpcMethods: const <String>[],
  studioContributions: const <String>[],
  generatedAt: DateTime.utc(2026, 8, 17, 12),
);

final class _HttpResult {
  const _HttpResult(this.statusCode, this.headers, this.bytes);

  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}

final class _TestDropFailure implements Exception {
  const _TestDropFailure(this.message);

  final String message;

  @override
  String toString() => '_TestDropFailure: $message';
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
