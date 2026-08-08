import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'scrcpy v4 reader survives fragmentation and preserves access units',
    () async {
      final wire = _videoWire();
      final chunks = <List<int>>[
        wire.sublist(0, 1),
        wire.sublist(1, 7),
        wire.sublist(7, 23),
        wire.sublist(23, 41),
        wire.sublist(41),
      ];
      final events = await ScrcpyVideoPacketReader(
        Stream<List<int>>.fromIterable(chunks),
      ).read().toList();
      expect(events, hasLength(3));
      expect(
        events.first,
        isA<ScrcpyVideoSession>()
            .having((value) => value.width, 'width', 1080)
            .having((value) => value.height, 'height', 1920),
      );
      final configuration = events[1] as ScrcpyVideoPacket;
      expect(configuration.configuration, isTrue);
      expect(configuration.timestampMicros, isNull);
      expect(configuration.data, <int>[0, 0, 0, 1, 0x67]);
      final keyFrame = events[2] as ScrcpyVideoPacket;
      expect(keyFrame.keyFrame, isTrue);
      expect(keyFrame.timestampMicros, 123456);
      expect(keyFrame.data, <int>[0, 0, 0, 1, 0x65, 1, 2, 3]);

      await expectLater(
        ScrcpyVideoPacketReader(
          Stream<List<int>>.value(wire.sublist(0, wire.length - 1)),
        ).read().drain<void>(),
        throwsA(isA<RemoteStreamProtocolException>()),
      );
    },
  );

  test('scrcpy controls match the official v4 serialization vectors', () {
    final key = ScrcpyControlMessageCodec.decodeViewerPayload(
      utf8.encode(
        jsonEncode(const <String, Object?>{
          'type': 'key',
          'action': 'up',
          'key': 'ENTER',
          'repeat': 5,
          'metaState': 0x41,
        }),
      ),
    );
    expect(key.messages.single, <int>[
      0,
      1,
      0,
      0,
      0,
      0x42,
      0,
      0,
      0,
      5,
      0,
      0,
      0,
      0x41,
    ]);

    final text = ScrcpyControlMessageCodec.decodeViewerPayload(
      utf8.encode('{"type":"text","text":"hello, world!"}'),
    );
    expect(text.messages.single, <int>[
      1,
      0,
      0,
      0,
      13,
      ...utf8.encode('hello, world!'),
    ]);

    final pointer = ScrcpyControlMessageCodec.decodeViewerPayload(
      utf8.encode(
        jsonEncode(const <String, Object?>{
          'type': 'pointer',
          'action': 'down',
          'pointerId': 0x12345678876543,
          'x': 100,
          'y': 200,
          'screenWidth': 1080,
          'screenHeight': 1920,
          'pressure': 1,
          'actionButton': 1,
          'buttons': 1,
        }),
      ),
    );
    expect(pointer.messages.single, <int>[
      2,
      0,
      0,
      0x12,
      0x34,
      0x56,
      0x78,
      0x87,
      0x65,
      0x43,
      0,
      0,
      0,
      100,
      0,
      0,
      0,
      200,
      0x04,
      0x38,
      0x07,
      0x80,
      0xff,
      0xff,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
    ]);

    expect(
      ScrcpyControlMessageCodec.decodeViewerPayload(
        utf8.encode('{"type":"session.end"}'),
      ).endSession,
      isTrue,
    );
    expect(
      () => ScrcpyControlMessageCodec.decodeViewerPayload(
        utf8.encode('{"type":"text","text":"ok","secret":"leak"}'),
      ),
      throwsFormatException,
    );
  });

  test(
    'scrcpy session streams timed H.264 and forwards bounded controls',
    () async {
      final transport = _Transport();
      final factory = _TransportFactory(transport);
      final stream = _WorkerStream();
      final session = ScrcpyRemoteInteractiveSession(
        factory: factory,
        target: _target(),
        clock: const _Clock(),
      );
      final running = session.run(
        stream: stream,
        deadline: const _Clock().nowUtc().add(const Duration(minutes: 1)),
      );
      await factory.connected.future;
      transport.video.add(_videoWire());
      await _waitUntil(() => stream.published.length == 3);
      stream.controls.add(
        RemoteStreamFrame(
          channel: RemoteStreamChannel.control,
          sequence: 1,
          payload: utf8.encode('{"type":"key","key":"ENTER"}'),
        ),
      );
      await _waitUntil(() => transport.controls.length == 2);
      stream.controls.add(
        RemoteStreamFrame(
          channel: RemoteStreamChannel.control,
          sequence: 2,
          payload: utf8.encode('{"type":"session.end"}'),
        ),
      );
      await running;

      expect(transport.closed, isTrue);
      expect(stream.published.first.$1, RemoteStreamChannel.metadataJson);
      final configuration = RemoteH264PacketCodec.decode(
        stream.published[1].$2,
      );
      final keyFrame = RemoteH264PacketCodec.decode(stream.published[2].$2);
      expect(configuration.configuration, isTrue);
      expect(keyFrame.keyFrame, isTrue);
      expect(keyFrame.timestampMicros, 123456);
      expect(transport.controls.first.first, 0);
      expect(transport.controls.last.first, 0);
    },
  );
}

Uint8List _videoWire() {
  final output = BytesBuilder(copy: false);
  output.add(_u32(0x68323634));
  final session = ByteData(12)
    ..setUint32(0, 0x80000000, Endian.big)
    ..setUint32(4, 1080, Endian.big)
    ..setUint32(8, 1920, Endian.big);
  output.add(session.buffer.asUint8List());
  output.add(_media(0x4000000000000000, <int>[0, 0, 0, 1, 0x67]));
  output.add(
    _media(0x2000000000000000 | 123456, <int>[0, 0, 0, 1, 0x65, 1, 2, 3]),
  );
  return output.takeBytes();
}

Uint8List _media(int flagsAndTimestamp, List<int> payload) {
  final output = Uint8List(12 + payload.length);
  ByteData.sublistView(output)
    ..setUint64(0, flagsAndTimestamp, Endian.big)
    ..setUint32(8, payload.length, Endian.big);
  output.setRange(12, output.length, payload);
  return output;
}

Uint8List _u32(int value) {
  final output = ByteData(4)..setUint32(0, value, Endian.big);
  return output.buffer.asUint8List();
}

AndroidTargetDescriptor _target() => AndroidTargetDescriptor(
  serial: 'emulator-5554',
  avdName: 'workspace-api-35',
  apiLevel: 35,
  abi: 'x86_64',
  ownership: AndroidTargetOwnership.managed,
  capabilities: <String>{'android.capture.png'},
);

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('test condition was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _TransportFactory implements ScrcpyTransportFactory {
  _TransportFactory(this.transport);

  final _Transport transport;
  final Completer<void> connected = Completer<void>();

  @override
  Future<ScrcpyTransport> connect(AndroidTargetDescriptor target) async {
    connected.complete();
    return transport;
  }
}

final class _Transport implements ScrcpyTransport {
  final StreamController<List<int>> video = StreamController<List<int>>();
  final Completer<void> _done = Completer<void>();
  final List<List<int>> controls = <List<int>>[];
  bool closed = false;

  @override
  Stream<List<int>> get videoBytes => video.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> writeControl(List<int> message) async {
    controls.add(List<int>.from(message));
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_done.isCompleted) _done.complete();
    await video.close();
  }
}

final class _WorkerStream implements RemoteWorkerStreamClient {
  final StreamController<RemoteStreamFrame> controls =
      StreamController<RemoteStreamFrame>.broadcast();
  final Completer<void> _done = Completer<void>();
  final List<(RemoteStreamChannel, List<int>)> published =
      <(RemoteStreamChannel, List<int>)>[];

  @override
  Stream<RemoteStreamFrame> get controlFrames => controls.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> connect(String capabilityToken) async {}

  @override
  Future<void> reauthenticate(String capabilityToken) async {}

  @override
  Future<void> publish(RemoteStreamChannel channel, List<int> payload) async {
    published.add((channel, List<int>.from(payload)));
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await controls.close();
  }
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 9, 12);

  @override
  int monotonicMicroseconds() => 0;
}
