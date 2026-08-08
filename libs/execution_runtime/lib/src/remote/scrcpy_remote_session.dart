import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../targets/android_target_provider.dart';
import 'remote_worker_service.dart';

sealed class ScrcpyVideoEvent {
  const ScrcpyVideoEvent();
}

final class ScrcpyVideoSession extends ScrcpyVideoEvent {
  const ScrcpyVideoSession({
    required this.width,
    required this.height,
    required this.clientResized,
  });

  final int width;
  final int height;
  final bool clientResized;
}

final class ScrcpyVideoPacket extends ScrcpyVideoEvent {
  ScrcpyVideoPacket({
    required this.configuration,
    required this.keyFrame,
    required this.timestampMicros,
    required List<int> data,
  }) : data = Uint8List.fromList(data);

  final bool configuration;
  final bool keyFrame;
  final int? timestampMicros;
  final Uint8List data;
}

final class ScrcpyVideoPacketReader {
  ScrcpyVideoPacketReader(Stream<List<int>> input)
    : _reader = _ExactByteReader(input);

  static const int _h264CodecId = 0x68323634;
  static const int _sessionFlag = 0x8000000000000000;
  static const int _configurationFlag = 0x4000000000000000;
  static const int _keyFrameFlag = 0x2000000000000000;
  static const int _timestampMask = 0x1FFFFFFFFFFFFFFF;

  final _ExactByteReader _reader;

  Stream<ScrcpyVideoEvent> read() async* {
    final codec = await _reader.readExact(4);
    if (ByteData.sublistView(codec).getUint32(0, Endian.big) != _h264CodecId) {
      throw const RemoteStreamProtocolException(
        'scrcpy video codec is not H.264',
      );
    }
    while (true) {
      final header = await _reader.readExactOrNull(12);
      if (header == null) return;
      final data = ByteData.sublistView(header);
      final flagsAndTimestamp = data.getUint64(0, Endian.big);
      if (flagsAndTimestamp & _sessionFlag != 0) {
        final flags = data.getUint32(0, Endian.big);
        final width = data.getUint32(4, Endian.big);
        final height = data.getUint32(8, Endian.big);
        if (flags & ~0x80000001 != 0 ||
            width < 1 ||
            width > 16384 ||
            height < 1 ||
            height > 16384) {
          throw const RemoteStreamProtocolException(
            'scrcpy video session packet is invalid',
          );
        }
        yield ScrcpyVideoSession(
          width: width,
          height: height,
          clientResized: flags & 1 != 0,
        );
        continue;
      }
      final configuration = flagsAndTimestamp & _configurationFlag != 0;
      final keyFrame = flagsAndTimestamp & _keyFrameFlag != 0;
      final timestamp = flagsAndTimestamp & _timestampMask;
      final size = data.getUint32(8, Endian.big);
      if (configuration && keyFrame ||
          configuration && timestamp != 0 ||
          size < 1 ||
          size > RemoteH264PacketCodec.maximumDataBytes) {
        throw const RemoteStreamProtocolException(
          'scrcpy video media packet is invalid',
        );
      }
      yield ScrcpyVideoPacket(
        configuration: configuration,
        keyFrame: keyFrame,
        timestampMicros: configuration ? null : timestamp,
        data: await _reader.readExact(size),
      );
    }
  }
}

final class ScrcpyControlBatch {
  const ScrcpyControlBatch({required this.endSession, required this.messages});

  final bool endSession;
  final List<Uint8List> messages;
}

abstract final class ScrcpyControlMessageCodec {
  static const int _injectKeycode = 0;
  static const int _injectText = 1;
  static const int _injectTouch = 2;
  static const int _injectScroll = 3;
  static const int _maximumTextBytes = 300;

  static ScrcpyControlBatch decodeViewerPayload(List<int> payload) {
    if (payload.isEmpty || payload.length > 64 * 1024) {
      throw const FormatException('scrcpy viewer control is invalid');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(payload));
    } on FormatException {
      throw const FormatException('scrcpy viewer control is invalid');
    }
    if (decoded is! Map<String, Object?> || decoded['type'] is! String) {
      throw const FormatException('scrcpy viewer control is invalid');
    }
    return switch (decoded['type']) {
      'session.end' => _end(decoded),
      'key' => _key(decoded),
      'text' => _text(decoded),
      'pointer' => _pointer(decoded),
      'scroll' => _scroll(decoded),
      _ => throw const FormatException('scrcpy control type is unsupported'),
    };
  }

  static ScrcpyControlBatch _end(Map<String, Object?> json) {
    _exact(json, const <String>{'type'});
    return const ScrcpyControlBatch(endSession: true, messages: <Uint8List>[]);
  }

  static ScrcpyControlBatch _key(Map<String, Object?> json) {
    _exact(json, const <String>{
      'type',
      'action',
      'key',
      'keyCode',
      'repeat',
      'metaState',
    });
    final named = json['key'];
    final numeric = json['keyCode'];
    if (named != null && numeric != null) {
      throw const FormatException('scrcpy key identity is ambiguous');
    }
    final keyCode = switch ((named, numeric)) {
      (final String name, null) => const <String, int>{
        'BACK': 4,
        'HOME': 3,
        'ENTER': 66,
        'APP_SWITCH': 187,
      }[name],
      (null, final int code) => code,
      _ => null,
    };
    final repeat = json['repeat'] ?? 0;
    final metaState = json['metaState'] ?? 0;
    if (keyCode == null ||
        keyCode < 0 ||
        keyCode > 1000 ||
        repeat is! int ||
        repeat < 0 ||
        repeat > 1000 ||
        metaState is! int ||
        metaState < 0 ||
        metaState > 0x7FFFFFFF) {
      throw const FormatException('scrcpy key control is invalid');
    }
    final action = json['action'];
    if (action != null && action != 'down' && action != 'up') {
      throw const FormatException('scrcpy key action is invalid');
    }
    Uint8List message(int wireAction) {
      final output = Uint8List(14);
      ByteData.sublistView(output)
        ..setUint8(0, _injectKeycode)
        ..setUint8(1, wireAction)
        ..setUint32(2, keyCode, Endian.big)
        ..setUint32(6, repeat, Endian.big)
        ..setUint32(10, metaState, Endian.big);
      return output;
    }

    return ScrcpyControlBatch(
      endSession: false,
      messages: action == null
          ? <Uint8List>[message(0), message(1)]
          : <Uint8List>[message(action == 'down' ? 0 : 1)],
    );
  }

  static ScrcpyControlBatch _text(Map<String, Object?> json) {
    _exact(json, const <String>{'type', 'text'});
    final value = json['text'];
    if (value is! String) {
      throw const FormatException('scrcpy text control is invalid');
    }
    final bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > _maximumTextBytes) {
      throw const FormatException('scrcpy text control is invalid');
    }
    final output = Uint8List(5 + bytes.length);
    ByteData.sublistView(output)
      ..setUint8(0, _injectText)
      ..setUint32(1, bytes.length, Endian.big);
    output.setRange(5, output.length, bytes);
    return ScrcpyControlBatch(endSession: false, messages: <Uint8List>[output]);
  }

  static ScrcpyControlBatch _pointer(Map<String, Object?> json) {
    _exact(json, const <String>{
      'type',
      'action',
      'pointerId',
      'x',
      'y',
      'screenWidth',
      'screenHeight',
      'pressure',
      'actionButton',
      'buttons',
    });
    final action = switch (json['action']) {
      'down' => 0,
      'up' => 1,
      'move' => 2,
      _ => null,
    };
    final pointerId = json['pointerId'] ?? 0;
    final x = json['x'];
    final y = json['y'];
    final width = json['screenWidth'];
    final height = json['screenHeight'];
    final pressure = json['pressure'] ?? (action == 1 ? 0 : 1);
    final actionButton = json['actionButton'] ?? 1;
    final buttons = json['buttons'] ?? (action == 1 ? 0 : 1);
    if (action == null ||
        pointerId is! int ||
        pointerId < 0 ||
        pointerId > 0x1FFFFFFFFFFFFF ||
        x is! int ||
        x < 0 ||
        y is! int ||
        y < 0 ||
        width is! int ||
        width < 1 ||
        width > 65535 ||
        height is! int ||
        height < 1 ||
        height > 65535 ||
        x >= width ||
        y >= height ||
        pressure is! num ||
        pressure < 0 ||
        pressure > 1 ||
        actionButton is! int ||
        actionButton < 0 ||
        actionButton > 0x7FFFFFFF ||
        buttons is! int ||
        buttons < 0 ||
        buttons > 0x7FFFFFFF) {
      throw const FormatException('scrcpy pointer control is invalid');
    }
    final output = Uint8List(32);
    ByteData.sublistView(output)
      ..setUint8(0, _injectTouch)
      ..setUint8(1, action)
      ..setUint64(2, pointerId, Endian.big)
      ..setUint32(10, x, Endian.big)
      ..setUint32(14, y, Endian.big)
      ..setUint16(18, width, Endian.big)
      ..setUint16(20, height, Endian.big)
      ..setUint16(22, (pressure * 65535).round(), Endian.big)
      ..setUint32(24, actionButton, Endian.big)
      ..setUint32(28, buttons, Endian.big);
    return ScrcpyControlBatch(endSession: false, messages: <Uint8List>[output]);
  }

  static ScrcpyControlBatch _scroll(Map<String, Object?> json) {
    _exact(json, const <String>{
      'type',
      'x',
      'y',
      'screenWidth',
      'screenHeight',
      'horizontal',
      'vertical',
      'buttons',
    });
    final x = json['x'];
    final y = json['y'];
    final width = json['screenWidth'];
    final height = json['screenHeight'];
    final horizontal = json['horizontal'];
    final vertical = json['vertical'];
    final buttons = json['buttons'] ?? 0;
    if (x is! int ||
        x < 0 ||
        y is! int ||
        y < 0 ||
        width is! int ||
        width < 1 ||
        width > 65535 ||
        height is! int ||
        height < 1 ||
        height > 65535 ||
        x >= width ||
        y >= height ||
        horizontal is! num ||
        horizontal < -16 ||
        horizontal > 16 ||
        vertical is! num ||
        vertical < -16 ||
        vertical > 16 ||
        buttons is! int ||
        buttons < 0 ||
        buttons > 0x7FFFFFFF) {
      throw const FormatException('scrcpy scroll control is invalid');
    }
    final output = Uint8List(21);
    ByteData.sublistView(output)
      ..setUint8(0, _injectScroll)
      ..setUint32(1, x, Endian.big)
      ..setUint32(5, y, Endian.big)
      ..setUint16(9, width, Endian.big)
      ..setUint16(11, height, Endian.big)
      ..setInt16(13, _scrollValue(horizontal), Endian.big)
      ..setInt16(15, _scrollValue(vertical), Endian.big)
      ..setUint32(17, buttons, Endian.big);
    return ScrcpyControlBatch(endSession: false, messages: <Uint8List>[output]);
  }

  static int _scrollValue(num value) =>
      value >= 0 ? (value / 16 * 32767).round() : (value / 16 * 32768).round();

  static void _exact(Map<String, Object?> json, Set<String> allowed) {
    if (json.keys.toSet().difference(allowed).isNotEmpty) {
      throw const FormatException('scrcpy control has unknown fields');
    }
  }
}

abstract interface class ScrcpyTransport {
  Stream<List<int>> get videoBytes;

  Future<void> writeControl(List<int> message);

  Future<void> get done;

  Future<void> close();
}

abstract interface class ScrcpyTransportFactory {
  Future<ScrcpyTransport> connect(AndroidTargetDescriptor target);
}

final class SystemScrcpyTransportFactory implements ScrcpyTransportFactory {
  SystemScrcpyTransportFactory({
    required this.provider,
    required this.serverJar,
    required this.serverDigest,
    this.version = '4.0',
    this.localPort = 27185,
    Random? random,
  }) : _random = random ?? Random.secure() {
    if (!RegExp(r'^[0-9]+\.[0-9]+(?:\.[0-9]+)?$').hasMatch(version) ||
        localPort < 1024 ||
        localPort > 65535) {
      throw ArgumentError('scrcpy runtime configuration is invalid');
    }
  }

  static const String _remoteServer =
      '/data/local/tmp/workspace-scrcpy-server.jar';

  final AndroidTargetProvider provider;
  final File serverJar;
  final Digest serverDigest;
  final String version;
  final int localPort;
  final Random _random;

  @override
  Future<ScrcpyTransport> connect(AndroidTargetDescriptor target) async {
    if (!serverJar.existsSync() ||
        Link(serverJar.path).existsSync() ||
        serverJar.lengthSync() < 1 ||
        serverJar.lengthSync() > 128 * 1024 * 1024 ||
        Digest.bytes(serverJar.readAsBytesSync()) != serverDigest) {
      throw StateError('scrcpy server artifact is absent or has wrong digest');
    }
    final scid = _random.nextInt(0x7FFFFFFF);
    final scidHex = scid.toRadixString(16).padLeft(8, '0');
    final forward = 'tcp:$localPort';
    try {
      await provider.runManagedAdb(target, <String>[
        'forward',
        '--remove',
        forward,
      ]);
    } on Object {
      // A fresh emulator normally has no existing forwarding rule.
    }
    await provider.runManagedAdb(target, <String>[
      'push',
      serverJar.path,
      _remoteServer,
    ], timeout: const Duration(minutes: 1));
    await provider.runManagedAdb(target, <String>[
      'forward',
      forward,
      'localabstract:scrcpy_$scidHex',
    ]);
    Process? process;
    Socket? video;
    Socket? control;
    try {
      process = await Process.start(provider.adbExecutable, <String>[
        '-s',
        target.serial,
        'shell',
        'CLASSPATH=$_remoteServer',
        'app_process',
        '/',
        'com.genymobile.scrcpy.Server',
        version,
        'scid=$scidHex',
        'log_level=warn',
        'tunnel_forward=true',
        'audio=false',
        'control=true',
        'video_codec=h264',
        'clipboard_autosync=false',
        'cleanup=true',
        'send_device_meta=false',
        'send_dummy_byte=false',
        'send_frame_meta=true',
        'send_stream_meta=true',
        'max_size=1920',
        'max_fps=60',
      ]);
      video = await _connectSocket(localPort);
      control = await _connectSocket(localPort);
      return _SystemScrcpyTransport(
        video: video,
        control: control,
        process: process,
        cleanup: () => _cleanup(target, forward),
      );
    } on Object {
      video?.destroy();
      control?.destroy();
      process?.kill();
      await _cleanup(target, forward);
      rethrow;
    }
  }

  Future<Socket> _connectSocket(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        return await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 500),
        );
      } on Object catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError(
      'scrcpy socket did not become ready: ${lastError.runtimeType}',
    );
  }

  Future<void> _cleanup(AndroidTargetDescriptor target, String forward) async {
    try {
      await provider.runManagedAdb(target, <String>[
        'forward',
        '--remove',
        forward,
      ]);
    } on Object {
      // Emulator teardown is authoritative if adb is already unavailable.
    }
    try {
      await provider.runManagedAdb(target, const <String>[
        'shell',
        'rm',
        '-f',
        _remoteServer,
      ]);
    } on Object {
      // The ephemeral emulator userdata is wiped after the Job.
    }
  }
}

final class ScrcpyRemoteInteractiveSession
    implements RemoteWorkerInteractiveSession {
  ScrcpyRemoteInteractiveSession({
    required this.factory,
    required this.target,
    required this.clock,
  });

  final ScrcpyTransportFactory factory;
  final AndroidTargetDescriptor target;
  final Clock clock;
  final Completer<void> _stopped = Completer<void>();
  ScrcpyTransport? _transport;

  @override
  RemoteInteractiveTransport get transport =>
      RemoteInteractiveTransport.scrcpyH264Control;

  @override
  Future<void> run({
    required RemoteWorkerStreamClient stream,
    required DateTime deadline,
  }) async {
    if (_transport != null) {
      throw StateError('scrcpy session is already running');
    }
    final transport = await factory.connect(target);
    _transport = transport;
    final endRequested = Completer<void>();
    final controlFailure = Completer<void>();
    var controlTail = Future<void>.value();
    final controlSubscription = stream.controlFrames.listen((frame) {
      controlTail = controlTail.then((_) async {
        final batch = ScrcpyControlMessageCodec.decodeViewerPayload(
          frame.payload,
        );
        if (batch.endSession) {
          if (!endRequested.isCompleted) endRequested.complete();
          return;
        }
        for (final message in batch.messages) {
          await transport.writeControl(message);
        }
      });
      unawaited(
        controlTail.catchError((Object error, StackTrace stackTrace) {
          if (!controlFailure.isCompleted) {
            controlFailure.completeError(error, stackTrace);
          }
        }),
      );
    });
    final video = _pumpVideo(transport, stream);
    try {
      final remaining = deadline.difference(clock.nowUtc());
      if (remaining <= Duration.zero) return;
      await _waitForScrcpySignal(remaining, <Future<void>>[
        _stopped.future,
        stream.done,
        endRequested.future,
        video.then<void>(
          (_) => throw StateError('scrcpy video ended unexpectedly'),
        ),
        transport.done.then<void>(
          (_) => throw StateError('scrcpy transport ended unexpectedly'),
        ),
        controlFailure.future,
      ]);
      await controlTail;
    } finally {
      await controlSubscription.cancel();
      await transport.close();
      _transport = null;
    }
  }

  Future<void> _pumpVideo(
    ScrcpyTransport transport,
    RemoteWorkerStreamClient stream,
  ) async {
    await for (final event in ScrcpyVideoPacketReader(
      transport.videoBytes,
    ).read()) {
      switch (event) {
        case ScrcpyVideoSession(
          :final width,
          :final height,
          :final clientResized,
        ):
          await stream.publish(
            RemoteStreamChannel.metadataJson,
            utf8.encode(
              jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'type': 'video.session',
                'codec': 'avc1',
                'width': width,
                'height': height,
                'clientResized': clientResized,
              }),
            ),
          );
        case ScrcpyVideoPacket(
          :final configuration,
          :final keyFrame,
          :final timestampMicros,
          :final data,
        ):
          await stream.publish(
            RemoteStreamChannel.videoH264,
            RemoteH264PacketCodec.encode(
              RemoteH264Packet(
                configuration: configuration,
                keyFrame: keyFrame,
                timestampMicros: timestampMicros,
                data: data,
              ),
            ),
          );
      }
    }
  }

  @override
  Future<void> stop() async {
    if (!_stopped.isCompleted) _stopped.complete();
    await _transport?.close();
  }
}

Future<void> _waitForScrcpySignal(
  Duration timeout,
  List<Future<void>> signals,
) async {
  if (timeout <= Duration.zero) return;
  final timedOut = Completer<void>();
  final timer = Timer(timeout, timedOut.complete);
  try {
    await Future.any<void>(<Future<void>>[timedOut.future, ...signals]);
  } finally {
    timer.cancel();
  }
}

final class _SystemScrcpyTransport implements ScrcpyTransport {
  _SystemScrcpyTransport({
    required this._video,
    required this._control,
    required this._process,
    required this._cleanup,
  }) {
    // ignore: cancel_subscriptions
    _controlInput = _control.listen(
      (bytes) {
        _controlResponseBytes += bytes.length;
        if (_controlResponseBytes > 1024 * 1024) {
          unawaited(close());
        }
      },
      onError: _finish,
      onDone: _finish,
      cancelOnError: true,
    );
    // ignore: cancel_subscriptions
    _stdout = _process.stdout.listen(
      _serverOutput,
      onError: _finish,
      cancelOnError: true,
    );
    // ignore: cancel_subscriptions
    _stderr = _process.stderr.listen(
      _serverOutput,
      onError: _finish,
      cancelOnError: true,
    );
    unawaited(_process.exitCode.then((_) => _finish()));
  }

  final Socket _video;
  final Socket _control;
  final Process _process;
  final Future<void> Function() _cleanup;
  final Completer<void> _done = Completer<void>();
  // ignore: cancel_subscriptions
  late final StreamSubscription<List<int>> _controlInput;
  // ignore: cancel_subscriptions
  late final StreamSubscription<List<int>> _stdout;
  // ignore: cancel_subscriptions
  late final StreamSubscription<List<int>> _stderr;
  int _controlResponseBytes = 0;
  int _serverOutputBytes = 0;
  Future<void>? _closing;

  @override
  Stream<List<int>> get videoBytes => _video;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> writeControl(List<int> message) async {
    if (_closing != null || message.isEmpty || message.length > 256 * 1024) {
      throw StateError('scrcpy control transport is unavailable');
    }
    _control.add(message);
    await _control.flush();
  }

  void _serverOutput(List<int> bytes) {
    _serverOutputBytes += bytes.length;
    if (_serverOutputBytes > 1024 * 1024) unawaited(close());
  }

  void _finish([Object? error, StackTrace? stackTrace]) {
    if (_done.isCompleted) return;
    if (error == null) {
      _done.complete();
    } else {
      _done.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _video.destroy();
    _control.destroy();
    _process.kill();
    await Future.wait<void>(<Future<void>>[
      _controlInput.cancel(),
      _stdout.cancel(),
      _stderr.cancel(),
    ]);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      if (!Platform.isWindows) _process.kill(ProcessSignal.sigkill);
    }
    await _cleanup();
    _finish();
  }
}

final class _ExactByteReader {
  _ExactByteReader(Stream<List<int>> stream)
    : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  Uint8List _current = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> readExact(int count) async {
    final value = await _read(count, allowCleanEof: false);
    return value!;
  }

  Future<Uint8List?> readExactOrNull(int count) =>
      _read(count, allowCleanEof: true);

  Future<Uint8List?> _read(int count, {required bool allowCleanEof}) async {
    final output = Uint8List(count);
    var written = 0;
    while (written < count) {
      if (_offset == _current.length) {
        if (!await _iterator.moveNext()) {
          if (allowCleanEof && written == 0) return null;
          throw const RemoteStreamProtocolException(
            'scrcpy stream ended inside a packet',
          );
        }
        _current = Uint8List.fromList(_iterator.current);
        _offset = 0;
        if (_current.isEmpty) continue;
      }
      final available = _current.length - _offset;
      final needed = count - written;
      final copied = available < needed ? available : needed;
      output.setRange(written, written + copied, _current, _offset);
      written += copied;
      _offset += copied;
    }
    return output;
  }
}
