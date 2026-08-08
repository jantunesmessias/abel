import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:studio/src/remote/remote_session_machine.dart';
import 'package:studio/src/remote/remote_session_transport.dart';
import 'package:studio_ui/studio_ui.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

Future<bool> remoteH264WebCodecsSupported({
  String codec = 'avc1.42E01E',
  int width = 16,
  int height = 16,
}) async {
  try {
    final support = await web.VideoDecoder.isConfigSupported(
      web.VideoDecoderConfig(
        codec: codec,
        codedWidth: width,
        codedHeight: height,
        optimizeForLatency: true,
      ),
    ).toDart.timeout(const Duration(seconds: 2));
    return support.supported;
  } on Object {
    return false;
  }
}

final class RemoteSessionSurface extends StatefulComponent {
  const RemoteSessionSurface({
    required this.grant,
    this.onClosed,
    this.connectionFactory,
    this.webBootstrapper,
    super.key,
  });

  final RemoteSessionGrant grant;
  final VoidCallback? onClosed;
  final RemoteSessionConnectionFactory? connectionFactory;
  final RemoteWebSessionBootstrapper? webBootstrapper;

  @override
  State<RemoteSessionSurface> createState() => _RemoteSessionSurfaceState();
}

final class _RemoteSessionSurfaceState extends State<RemoteSessionSurface> {
  late final RemoteSessionMessageMachine _machine = RemoteSessionMessageMachine(
    component.grant,
  );
  late final String _canvasId =
      'workspace-remote-canvas-${identityHashCode(this)}';
  StreamSubscription<Object?>? _subscription;
  RemoteSessionConnection? _channel;
  Future<void> _messageTail = Future<void>.value();
  web.HTMLCanvasElement? _canvas;
  _H264CanvasDecoder? _decoder;
  JSFunction? _pointerDown;
  JSFunction? _pointerMove;
  JSFunction? _pointerUp;
  JSFunction? _keyDown;
  final List<RemoteH264Packet> _pendingPackets = <RemoteH264Packet>[];
  Uri? _webTarget;
  Uri? _screenshotUri;
  String _status = 'Conectando à execução remota…';
  Object? _error;
  int? _videoWidth;
  int? _videoHeight;
  var _controlSequence = 0;
  var _canvasActivationScheduled = false;
  var _videoReady = false;
  var _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      final channel = (component.connectionFactory ?? _connectWebSocket)(
        component.grant,
      );
      _channel = channel;
      _subscription = channel.messages.listen(
        (message) {
          _messageTail = _messageTail.then((_) => _message(message));
          unawaited(_messageTail.catchError(_fail));
        },
        onError: _fail,
        onDone: () {
          if (!_closed && _error == null) {
            _fail(StateError('A sessão remota foi encerrada.'));
          }
        },
        cancelOnError: true,
      );
      await channel.ready.timeout(const Duration(seconds: 10));
      channel.send(
        jsonEncode(<String, Object?>{
          'type': 'authenticate',
          'token': component.grant.compactTicket,
        }),
      );
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  Future<void> _message(Object? message) async {
    for (final event in _machine.handle(message)) {
      switch (event) {
        case RemoteViewerAuthenticated():
          _setStatus('Autenticado; aguardando o target…');
        case RemoteViewerReady():
          _setStatus('Target remoto conectado.');
        case RemoteWebBootstrapRequired():
          await _bootstrapWeb(event);
        case RemoteWebTargetReady():
          _setStatus('Aplicação web remota pronta.');
        case RemoteVideoSessionChanged(:final width, :final height):
          if (!mounted) return;
          setState(() {
            _videoWidth = width;
            _videoHeight = height;
            _videoReady = true;
            _status = 'Emulador Android conectado.';
          });
          _activateCanvas();
        case RemoteH264PacketReceived(:final packet):
          final decoder = _decoder;
          if (decoder == null) {
            if (_pendingPackets.length == 16) _pendingPackets.removeAt(0);
            _pendingPackets.add(packet);
          } else {
            await decoder.add(packet);
          }
        case RemoteScreenshotReceived(:final png):
          _showScreenshot(png);
      }
    }
  }

  Future<void> _bootstrapWeb(RemoteWebBootstrapRequired event) async {
    final target =
        await (component.webBootstrapper ??
                const _BrowserRemoteWebBootstrapper())
            .bootstrap(
              session: component.grant,
              endpointPath: event.endpoint,
              oneTimeGrant: event.grant,
            );
    if (!mounted) return;
    setState(() {
      _webTarget = target;
      _status = 'Aplicação web remota autenticada.';
    });
  }

  void _showScreenshot(Uint8List png) {
    final previous = _screenshotUri;
    if (previous != null) web.URL.revokeObjectURL(previous.toString());
    final blob = web.Blob(
      <JSAny>[png.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final uri = Uri.parse(web.URL.createObjectURL(blob));
    if (!mounted) {
      web.URL.revokeObjectURL(uri.toString());
      return;
    }
    setState(() {
      _screenshotUri = uri;
      _status = 'Fallback read-only por capturas periódicas.';
    });
  }

  void _activateCanvas() {
    if (_canvas != null || _canvasActivationScheduled || !_videoReady) return;
    _canvasActivationScheduled = true;
    scheduleMicrotask(() async {
      _canvasActivationScheduled = false;
      if (!mounted || _canvas != null || !_videoReady) return;
      final element = web.document.getElementById(_canvasId);
      if (element == null || !element.isA<web.HTMLCanvasElement>()) return;
      final canvas = element as web.HTMLCanvasElement;
      canvas
        ..width = _videoWidth ?? 1
        ..height = _videoHeight ?? 1
        ..tabIndex = 0;
      final decoder = _H264CanvasDecoder(canvas, _fail);
      _canvas = canvas;
      _decoder = decoder;
      _pointerDown = ((web.Event event) => _pointer(event, 'down')).toJS;
      _pointerMove = ((web.Event event) => _pointer(event, 'move')).toJS;
      _pointerUp = ((web.Event event) => _pointer(event, 'up')).toJS;
      _keyDown = _onKeyDown.toJS;
      canvas
        ..addEventListener('pointerdown', _pointerDown)
        ..addEventListener('pointermove', _pointerMove)
        ..addEventListener('pointerup', _pointerUp)
        ..addEventListener('pointercancel', _pointerUp)
        ..addEventListener('keydown', _keyDown);
      decoder.updateSession(width: _videoWidth ?? 1, height: _videoHeight ?? 1);
      final pending = List<RemoteH264Packet>.of(_pendingPackets);
      _pendingPackets.clear();
      for (final packet in pending) {
        await decoder.add(packet);
      }
    });
  }

  void _pointer(web.Event rawEvent, String action) {
    final canvas = _canvas;
    if (!_videoReady || _closed || canvas == null) return;
    final event = rawEvent as web.PointerEvent;
    if (action == 'move' && event.buttons == 0) return;
    final rect = canvas.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return;
    final x = ((event.clientX - rect.left) / rect.width * canvas.width)
        .floor()
        .clamp(0, canvas.width - 1);
    final y = ((event.clientY - rect.top) / rect.height * canvas.height)
        .floor()
        .clamp(0, canvas.height - 1);
    if (action == 'down') {
      canvas.focus();
      canvas.setPointerCapture(event.pointerId);
    } else if (action == 'up' && canvas.hasPointerCapture(event.pointerId)) {
      canvas.releasePointerCapture(event.pointerId);
    }
    event.preventDefault();
    _sendControl(<String, Object?>{
      'type': 'pointer',
      'action': action,
      'pointerId': event.pointerId,
      'x': x,
      'y': y,
      'screenWidth': canvas.width,
      'screenHeight': canvas.height,
      'pressure': action == 'up' ? 0 : event.pressure.clamp(0, 1),
      'actionButton': action == 'up' ? 0 : 1,
      'buttons': action == 'up' ? 0 : 1,
    });
  }

  void _onKeyDown(web.Event rawEvent) {
    if (!_videoReady || _closed) return;
    final event = rawEvent as web.KeyboardEvent;
    final name = switch (event.key) {
      'Enter' => 'ENTER',
      'Escape' => 'BACK',
      'Home' => 'HOME',
      _ => null,
    };
    if (name != null) {
      event.preventDefault();
      _sendControl(<String, Object?>{'type': 'key', 'key': name});
    } else if (event.key.length == 1 && !event.ctrlKey && !event.metaKey) {
      event.preventDefault();
      _sendControl(<String, Object?>{'type': 'text', 'text': event.key});
    }
  }

  void _sendControl(Map<String, Object?> document) {
    final channel = _channel;
    if (channel == null ||
        !component.grant.allowedTransports.contains(
          RemoteInteractiveTransport.scrcpyH264Control,
        )) {
      return;
    }
    channel.send(
      RemoteStreamFrameCodec.encode(
        RemoteStreamFrame(
          channel: RemoteStreamChannel.control,
          sequence: ++_controlSequence,
          payload: utf8.encode(jsonEncode(document)),
        ),
      ),
    );
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (_error != null || _closed) return;
    _error = error;
    final channel = _channel;
    if (channel != null) {
      unawaited(channel.close(1002, 'remote session failed'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _endSession() async {
    if (_closed) return;
    if (component.grant.allowedTransports.contains(
      RemoteInteractiveTransport.scrcpyH264Control,
    )) {
      _sendControl(const <String, Object?>{'type': 'session.end'});
    }
    _closed = true;
    await _channel?.close(1000, 'viewer ended session');
    component.onClosed?.call();
    if (mounted) setState(() {});
  }

  @override
  Component build(BuildContext context) {
    if (_videoReady) _activateCanvas();
    final error = _error;
    return section(
      classes: 'remote-session-surface',
      attributes: <String, String>{
        'aria-label': 'Sessão remota ${component.grant.runId}',
      },
      <Component>[
        header(classes: 'remote-session-surface__toolbar', <Component>[
          p(
            attributes: const <String, String>{
              'role': 'status',
              'aria-live': 'polite',
            },
            <Component>[
              Component.text(error == null ? _status : 'Falha segura: $error'),
            ],
          ),
          StudioButton(
            label: 'Encerrar',
            leadingIcon: StudioIconName.stop,
            kind: StudioButtonKind.danger,
            onPressed: _closed ? null : () => unawaited(_endSession()),
            disabled: _closed,
          ),
        ]),
        div(classes: 'remote-session-surface__content', <Component>[
          if (error != null)
            const StudioEmptyState(
              title: 'Sessão encerrada',
              message:
                  'A credencial efêmera foi descartada e não será reutilizada.',
              tone: PresentationTone.critical,
            )
          else if (_webTarget case final target?)
            iframe(
              const <Component>[],
              src: target.toString(),
              classes: 'remote-web-frame',
              sandbox: 'allow-scripts allow-same-origin allow-forms',
              referrerPolicy: ReferrerPolicy.noReferrer,
              attributes: const <String, String>{
                'title': 'Aplicação web remota',
                'aria-label': 'Aplicação web remota',
              },
            )
          else if (_screenshotUri case final uri?)
            img(
              src: uri.toString(),
              alt: 'Captura do emulador remoto em modo somente leitura',
              classes: 'remote-screenshot',
            )
          else if (_videoReady)
            Component.element(
              tag: 'canvas',
              id: _canvasId,
              classes: 'remote-video-canvas',
              attributes: const <String, String>{
                'role': 'application',
                'aria-label': 'Emulador Android remoto',
                'tabindex': '0',
              },
              children: const <Component>[],
            )
          else
            StudioProgress(label: _status),
        ]),
      ],
    );
  }

  @override
  void dispose() {
    _closed = true;
    _machine.close();
    final canvas = _canvas;
    if (canvas != null) {
      if (_pointerDown case final listener?) {
        canvas.removeEventListener('pointerdown', listener);
      }
      if (_pointerMove case final listener?) {
        canvas.removeEventListener('pointermove', listener);
      }
      if (_pointerUp case final listener?) {
        canvas
          ..removeEventListener('pointerup', listener)
          ..removeEventListener('pointercancel', listener);
      }
      if (_keyDown case final listener?) {
        canvas.removeEventListener('keydown', listener);
      }
    }
    _decoder?.close();
    _decoder = null;
    _canvas = null;
    unawaited(_subscription?.cancel());
    final channel = _channel;
    if (channel != null) {
      unawaited(channel.close(1000, 'viewer disposed'));
    }
    final screenshotUri = _screenshotUri;
    if (screenshotUri != null) {
      web.URL.revokeObjectURL(screenshotUri.toString());
    }
    super.dispose();
  }
}

RemoteSessionConnection _connectWebSocket(RemoteSessionGrant grant) =>
    _WebSocketRemoteSessionConnection(
      WebSocketChannel.connect(
        grant.endpoint,
        protocols: const <String>[RemoteSessionGrant.protocol],
      ),
    );

final class _WebSocketRemoteSessionConnection
    implements RemoteSessionConnection {
  const _WebSocketRemoteSessionConnection(this.channel);

  final WebSocketChannel channel;

  @override
  Stream<Object?> get messages => channel.stream;

  @override
  Future<void> get ready => channel.ready;

  @override
  void send(Object message) => channel.sink.add(message);

  @override
  Future<void> close(int code, String reason) =>
      channel.sink.close(code, reason);
}

final class _BrowserRemoteWebBootstrapper
    implements RemoteWebSessionBootstrapper {
  const _BrowserRemoteWebBootstrapper();

  @override
  Future<Uri> bootstrap({
    required RemoteSessionGrant session,
    required String endpointPath,
    required String oneTimeGrant,
  }) async {
    final endpoint = session.endpoint.replace(
      scheme: 'https',
      path: endpointPath,
      query: null,
      fragment: null,
    );
    final headers = web.Headers()
      ..set('content-type', 'application/json; charset=utf-8');
    final response = await web.window
        .fetch(
          endpoint.toString().toJS,
          web.RequestInit(
            method: 'POST',
            headers: headers,
            body: jsonEncode(<String, Object?>{'grant': oneTimeGrant}).toJS,
            credentials: 'include',
            cache: 'no-store',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
          ),
        )
        .toDart;
    final body = (await response.text().toDart).toDart;
    if (!response.ok || body.length > 4096) {
      throw StateError('O bootstrap web remoto foi rejeitado.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(const <String>{'target'}).isNotEmpty ||
        decoded['target'] is! String) {
      throw const FormatException('Resposta de bootstrap web inválida.');
    }
    final expectedPath = '/v1/sessions/${session.runId}/web/target/';
    if (decoded['target'] != expectedPath) {
      throw const FormatException('Target web remoto diverge do run.');
    }
    return endpoint.replace(path: expectedPath);
  }
}

final class _H264CanvasDecoder {
  _H264CanvasDecoder(this.canvas, this.onError);

  final web.HTMLCanvasElement canvas;
  final void Function(Object error, [StackTrace? stackTrace]) onError;
  web.VideoDecoder? _decoder;
  Uint8List? _configuration;
  int? _width;
  int? _height;
  var _configured = false;
  var _closed = false;

  void updateSession({required int width, required int height}) {
    if (_width == width && _height == height) return;
    _decoder?.reset();
    _configured = false;
    _configuration = null;
    _width = width;
    _height = height;
    canvas
      ..width = width
      ..height = height;
  }

  Future<void> add(RemoteH264Packet packet) async {
    if (_closed) return;
    if (packet.configuration) {
      _configuration = Uint8List.fromList(packet.data);
      _configured = false;
      return;
    }
    final width = _width;
    final height = _height;
    final configuration = _configuration;
    if (width == null || height == null || configuration == null) return;
    if (!_configured) {
      if (!packet.keyFrame) return;
      final codec = _avcCodec(configuration);
      final config = web.VideoDecoderConfig(
        codec: codec,
        codedWidth: width,
        codedHeight: height,
        optimizeForLatency: true,
      );
      final support = await web.VideoDecoder.isConfigSupported(
        config,
      ).toDart.timeout(const Duration(seconds: 2));
      if (!support.supported) {
        throw StateError('WebCodecs não suporta o perfil $codec.');
      }
      _decoder ??= web.VideoDecoder(
        web.VideoDecoderInit(
          output: ((web.VideoFrame frame) {
            try {
              final context =
                  canvas.getContext('2d')! as web.CanvasRenderingContext2D;
              context.drawImage(frame, 0, 0, canvas.width, canvas.height);
            } finally {
              frame.close();
            }
          }).toJS,
          error: ((web.DOMException error) => onError(error)).toJS,
        ),
      );
      _decoder!.configure(config);
      _configured = true;
    }
    final decoder = _decoder!;
    if (decoder.decodeQueueSize > 8 && !packet.keyFrame) return;
    final bytes = packet.keyFrame
        ? Uint8List.fromList(<int>[...configuration, ...packet.data])
        : packet.data;
    decoder.decode(
      web.EncodedVideoChunk(
        web.EncodedVideoChunkInit(
          type: packet.keyFrame ? 'key' : 'delta',
          timestamp: packet.timestampMicros!,
          data: bytes.toJS,
        ),
      ),
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _decoder?.close();
    _decoder = null;
  }

  String _avcCodec(List<int> annexB) {
    for (var index = 0; index + 7 < annexB.length; index += 1) {
      final start3 =
          annexB[index] == 0 &&
          annexB[index + 1] == 0 &&
          annexB[index + 2] == 1;
      final start4 =
          index + 4 < annexB.length &&
          annexB[index] == 0 &&
          annexB[index + 1] == 0 &&
          annexB[index + 2] == 0 &&
          annexB[index + 3] == 1;
      if (!start3 && !start4) continue;
      final nal = index + (start4 ? 4 : 3);
      if (nal + 3 >= annexB.length || annexB[nal] & 0x1f != 7) continue;
      String hex(int value) =>
          value.toRadixString(16).padLeft(2, '0').toUpperCase();
      return 'avc1.${hex(annexB[nal + 1])}${hex(annexB[nal + 2])}${hex(annexB[nal + 3])}';
    }
    throw const FormatException('SPS H.264 ausente no pacote de configuração.');
  }
}
