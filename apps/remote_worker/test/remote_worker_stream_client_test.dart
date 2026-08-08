import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_remote_worker/remote_worker.dart';
import 'package:test/test.dart';

void main() {
  test(
    'loopback stream client authenticates, relays, and reauthenticates',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<RemoteStreamFrame>();
      final serverDone = Completer<void>();
      final serverSubscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains(RemoteSessionGrant.protocol)
              ? RemoteSessionGrant.protocol
              : null,
        );
        addTearDown(socket.close);
        var controlSequence = 0;
        final subscription = socket.listen((message) {
          if (message is String) {
            final json = jsonDecode(message) as Map<String, Object?>;
            if (json['type'] == 'authenticate') {
              expect(json['token'], 'initial-capability');
              socket.add(
                jsonEncode(const <String, Object?>{'type': 'authenticated'}),
              );
              socket.add(
                jsonEncode(const <String, Object?>{'type': 'session.ready'}),
              );
              socket.add(
                RemoteStreamFrameCodec.encode(
                  RemoteStreamFrame(
                    channel: RemoteStreamChannel.control,
                    sequence: ++controlSequence,
                    payload: utf8.encode('{"type":"tap","x":10,"y":20}'),
                  ),
                ),
              );
            } else if (json['type'] == 'reauthenticate') {
              expect(json['token'], 'renewed-capability');
              socket.add(
                jsonEncode(const <String, Object?>{'type': 'reauthenticated'}),
              );
            }
          } else if (message is List<int> && !received.isCompleted) {
            received.complete(RemoteStreamFrameCodec.decode(message));
          }
        }, onDone: () => serverDone.complete());
        addTearDown(subscription.cancel);
      });
      addTearDown(() async {
        await serverSubscription.cancel();
        await server.close(force: true);
      });

      final client = LoopbackRemoteWorkerStreamClient(
        Uri.parse('ws://127.0.0.1:${server.port}/v1/sessions/run-001/worker'),
      );
      addTearDown(client.close);
      final controls = StreamIterator<RemoteStreamFrame>(client.controlFrames);
      addTearDown(controls.cancel);
      await client.connect('initial-capability');
      expect(await controls.moveNext(), isTrue);
      expect(controls.current.channel, RemoteStreamChannel.control);
      await client.publish(RemoteStreamChannel.videoH264, const <int>[
        0,
        0,
        0,
        1,
        0x67,
      ]);
      expect((await received.future).channel, RemoteStreamChannel.videoH264);
      await client.reauthenticate('renewed-capability');
      await client.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('worker stream client did not close'),
      );
      await serverDone.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('worker stream server did not close'),
      );
    },
  );

  test('stream client refuses non-loopback and credentialed endpoints', () {
    expect(
      () => LoopbackRemoteWorkerStreamClient(
        Uri.parse('wss://gateway.example.test/v1/sessions/run-001/worker'),
      ),
      throwsArgumentError,
    );
    expect(
      () => LoopbackRemoteWorkerStreamClient(
        Uri.parse('ws://token@127.0.0.1:27183/session'),
      ),
      throwsArgumentError,
    );
  });
}
