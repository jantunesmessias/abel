import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:devex_contracts/devex_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../secure_id_generator.dart';
import '../system_clock.dart';
import 'host_event_journal.dart';
import 'host_resource_registry.dart';

typedef HostRpcMethodHandler =
    FutureOr<Object?> Function(Map<String, Object?> params);

final class HostRpcServer {
  HostRpcServer({
    required this.studioOrigin,
    required this.sessionToken,
    InternetAddress? bindAddress,
    this.port = 0,
    this.maxMessageBytes = 64 * 1024,
    this.studioBootstrapManifest,
    HostEventJournal? journal,
    HostResourceRegistry? resourceRegistry,
    Map<String, HostRpcMethodHandler> applicationMethods =
        const <String, HostRpcMethodHandler>{},
  }) : bindAddress = bindAddress ?? InternetAddress.loopbackIPv4,
       journal = journal ?? HostEventJournal(),
       resources =
           resourceRegistry ??
           HostResourceRegistry(clock: SystemClock(), ids: SecureIdGenerator()),
       applicationMethods = Map<String, HostRpcMethodHandler>.unmodifiable(
         applicationMethods,
       ) {
    if (!this.bindAddress.isLoopback) {
      throw ArgumentError.value(
        this.bindAddress,
        'bindAddress',
        'must be loopback',
      );
    }
    if (studioOrigin.scheme != 'http' && studioOrigin.scheme != 'https') {
      throw ArgumentError.value(studioOrigin, 'studioOrigin');
    }
    if (sessionToken.length < 32) {
      throw ArgumentError.value(
        sessionToken,
        'sessionToken',
        'must contain at least 32 characters',
      );
    }
  }

  static const int protocolVersion = 1;
  static const int closeServerShutdown = 4001;
  static const int closeUnsupportedFrame = 4002;
  static const int closeMessageTooLarge = 4003;
  static const List<String> capabilities = <String>[
    'events.resume',
    'session.heartbeat',
  ];

  final Uri studioOrigin;
  final String sessionToken;
  final InternetAddress bindAddress;
  final int port;
  final int maxMessageBytes;
  final EffectiveKitManifest Function()? studioBootstrapManifest;
  final HostEventJournal journal;
  final HostResourceRegistry resources;
  final Map<String, HostRpcMethodHandler> applicationMethods;
  final JsonRpcCodec _codec = const JsonRpcCodec();
  final Set<WebSocketChannel> _connections = <WebSocketChannel>{};
  final Set<WebSocketChannel> _initializedConnections = <WebSocketChannel>{};

  HttpServer? _server;

  bool get isRunning => _server != null;
  int get activeConnections => _connections.length;

  Uri get httpUri {
    final server = _server;
    if (server == null) throw StateError('Host RPC server is not running');
    return Uri(scheme: 'http', host: server.address.address, port: server.port);
  }

  Uri get webSocketUri => httpUri.replace(scheme: 'ws', path: '/rpc');

  Future<void> start() async {
    if (_server != null) throw StateError('Host RPC server already started');
    final socketHandler = webSocketHandler(_onConnection);
    final handler = const Pipeline()
        .addMiddleware(_securityHeaders())
        .addHandler((request) => _route(request, socketHandler));
    _server = await shelf_io.serve(handler, bindAddress, port);
  }

  Future<void> close() async {
    final connections = List<WebSocketChannel>.of(_connections);
    _connections.clear();
    _initializedConnections.clear();
    await Future.wait<void>(
      connections.map(
        (connection) => connection.sink.close(
          closeServerShutdown,
          'DevEx Host shutting down',
        ),
      ),
    );
    final server = _server;
    _server = null;
    await server?.close(force: true);
    resources.clear();
  }

  Future<void> publishEvent(String method, Map<String, Object?> params) async {
    final preview = HostEvent(
      sequence: journal.latestSequence + 1,
      method: method,
      params: params,
    );
    final encoded = preview.toNotification().encode();
    if (utf8.encode(encoded).length > maxMessageBytes) {
      throw const FormatException('Host event exceeds maxMessageBytes');
    }
    journal.append(method, params);
    for (final connection in List<WebSocketChannel>.of(
      _initializedConnections,
    )) {
      connection.sink.add(encoded);
    }
  }

  FutureOr<Response> _route(Request request, Handler socketHandler) {
    if (request.url.path == 'devex/bootstrap.json' &&
        studioBootstrapManifest != null) {
      if (request.method != 'GET') {
        return Response(405, headers: const <String, String>{'allow': 'GET'});
      }
      if (request.url.hasQuery || !_originMatches(request.headers['origin'])) {
        return Response.forbidden('Bootstrap denied');
      }
      return Response.ok(
        const JcsCanonicalizer().canonicalize(<String, Object?>{
          'schemaVersion': 1,
          'protocolVersion': protocolVersion,
          'hostOrigin': httpUri.toString(),
          'rpcPath': '/rpc',
          'sessionToken': sessionToken,
          'effectiveKitManifest': studioBootstrapManifest!().toJson(),
        }),
        headers: <String, String>{
          'access-control-allow-origin': studioOrigin.origin,
          'content-type': 'application/json',
          'vary': 'Origin',
        },
      );
    }
    if (request.url.path == 'health' && request.method == 'GET') {
      return Response.ok(
        jsonEncode(<String, Object?>{
          'status': 'ready',
          'protocolVersion': protocolVersion,
        }),
        headers: <String, String>{'content-type': 'application/json'},
      );
    }
    if (request.url.pathSegments.firstOrNull == 'resources') {
      return resources.serve(request);
    }
    if (request.url.path != 'rpc') return Response.notFound('Not found');
    if (request.method != 'GET') {
      return Response(405, headers: <String, String>{'allow': 'GET'});
    }
    if (request.url.hasQuery) return Response.notFound('Not found');
    if (!_originMatches(request.headers['origin'])) {
      return Response.forbidden('Origin denied');
    }
    return socketHandler(request);
  }

  void _onConnection(WebSocketChannel channel, String? negotiatedProtocol) {
    _connections.add(channel);
    late final StreamSubscription<Object?> subscription;
    subscription = channel.stream.listen(
      (message) => _onMessage(channel, message),
      onError: (Object _) {
        _connections.remove(channel);
        _initializedConnections.remove(channel);
        unawaited(subscription.cancel());
      },
      onDone: () {
        _connections.remove(channel);
        _initializedConnections.remove(channel);
        unawaited(subscription.cancel());
      },
      cancelOnError: true,
    );
  }

  Future<void> _onMessage(WebSocketChannel channel, Object? message) async {
    if (message is! String) {
      await channel.sink.close(closeUnsupportedFrame, 'Text frames required');
      return;
    }
    if (utf8.encode(message).length > maxMessageBytes) {
      await channel.sink.close(closeMessageTooLarge, 'Message too large');
      return;
    }

    JsonRpcMessage decoded;
    try {
      decoded = _codec.decode(message);
    } on JsonRpcFormatException catch (error) {
      channel.sink.add(
        JsonRpcResponse.error(
          id: null,
          error: JsonRpcError(
            code: JsonRpcError.invalidRequest,
            message: error.message,
          ),
        ).encode(),
      );
      return;
    }
    if (decoded is! JsonRpcRequest) return;

    if (decoded.method != 'devex.initialize' &&
        !_initializedConnections.contains(channel)) {
      channel.sink.add(
        JsonRpcResponse.error(
          id: decoded.id,
          error: const JsonRpcError(
            code: -32001,
            message: 'devex.initialize is required first',
          ),
        ).encode(),
      );
      return;
    }

    final response = await _dispatch(decoded);
    if (decoded.method == 'devex.initialize' && response.isSuccess) {
      _initializedConnections.add(channel);
    }
    _sendResponse(channel, response);
  }

  void _sendResponse(WebSocketChannel channel, JsonRpcResponse response) {
    final encoded = response.encode();
    if (utf8.encode(encoded).length <= maxMessageBytes) {
      channel.sink.add(encoded);
      return;
    }
    channel.sink.add(
      JsonRpcResponse.error(
        id: response.id,
        error: const JsonRpcError(
          code: -32004,
          message: 'RPC response exceeds negotiated maxMessageBytes',
        ),
      ).encode(),
    );
  }

  Future<JsonRpcResponse> _dispatch(JsonRpcRequest request) async {
    switch (request.method) {
      case 'devex.initialize':
        return _initialize(request);
      case 'devex.resume':
        return _resume(request);
      case 'devex.ping':
        return JsonRpcResponse.success(
          id: request.id,
          result: <String, Object?>{'status': 'ok'},
        );
    }
    final handler = applicationMethods[request.method];
    if (handler == null) {
      return JsonRpcResponse.error(
        id: request.id,
        error: const JsonRpcError(
          code: JsonRpcError.methodNotFound,
          message: 'Method not found',
        ),
      );
    }
    final params = request.params;
    if (params != null && params is! Map<String, Object?>) {
      return JsonRpcResponse.error(
        id: request.id,
        error: const JsonRpcError(
          code: JsonRpcError.invalidParams,
          message: 'Application method params must be an object',
        ),
      );
    }
    try {
      return JsonRpcResponse.success(
        id: request.id,
        result: await handler(
          params as Map<String, Object?>? ?? const <String, Object?>{},
        ),
      );
    } on FormatException catch (error) {
      return JsonRpcResponse.error(
        id: request.id,
        error: JsonRpcError(
          code: JsonRpcError.invalidParams,
          message: error.message,
        ),
      );
    } on StateError catch (error) {
      return JsonRpcResponse.error(
        id: request.id,
        error: JsonRpcError(code: -32003, message: error.message),
      );
    } on Object {
      return JsonRpcResponse.error(
        id: request.id,
        error: const JsonRpcError(
          code: JsonRpcError.internalError,
          message: 'Application method failed',
        ),
      );
    }
  }

  JsonRpcResponse _initialize(JsonRpcRequest request) {
    final params = request.params;
    if (params is! Map<String, Object?> ||
        params.keys.toSet().difference(const <String>{
          'protocolVersion',
          'sessionToken',
        }).isNotEmpty ||
        params['protocolVersion'] != protocolVersion) {
      return JsonRpcResponse.error(
        id: request.id,
        error: const JsonRpcError(
          code: JsonRpcError.invalidParams,
          message: 'Unsupported protocol version',
        ),
      );
    }
    final suppliedToken = params['sessionToken'];
    if (suppliedToken is! String ||
        !_constantTimeEquals(suppliedToken, sessionToken)) {
      return JsonRpcResponse.error(
        id: request.id,
        error: const JsonRpcError(
          code: -32002,
          message: 'Authentication denied',
        ),
      );
    }
    return JsonRpcResponse.success(
      id: request.id,
      result: <String, Object?>{
        'protocolVersion': protocolVersion,
        'capabilities': <String>[
          ...capabilities,
          ...(applicationMethods.keys.toList()..sort()),
        ],
        'latestSequence': journal.latestSequence,
        'heartbeatSeconds': 15,
        'maxMessageBytes': maxMessageBytes,
      },
    );
  }

  JsonRpcResponse _resume(JsonRpcRequest request) {
    final params = request.params;
    final cursor = params is Map<String, Object?> ? params['cursor'] : null;
    if (cursor is! int || cursor < 0) {
      return JsonRpcResponse.error(
        id: request.id,
        error: const JsonRpcError(
          code: JsonRpcError.invalidParams,
          message: 'cursor must be a non-negative integer',
        ),
      );
    }
    try {
      return JsonRpcResponse.success(
        id: request.id,
        result: <String, Object?>{
          'events': journal
              .after(cursor)
              .map((event) => event.toJson())
              .toList(),
          'latestSequence': journal.latestSequence,
        },
      );
    } on HostCursorExpiredException {
      return JsonRpcResponse.error(
        id: request.id,
        error: const JsonRpcError(
          code: 1001,
          message: 'Cursor expired; request a snapshot',
        ),
      );
    }
  }

  bool _originMatches(String? origin) {
    if (origin == null) return false;
    final parsed = Uri.tryParse(origin);
    return parsed != null &&
        const <String>{'http', 'https'}.contains(parsed.scheme) &&
        parsed.host.isNotEmpty &&
        parsed.userInfo.isEmpty &&
        (parsed.path.isEmpty || parsed.path == '/') &&
        !parsed.hasQuery &&
        !parsed.hasFragment &&
        parsed.origin == studioOrigin.origin;
  }

  bool _constantTimeEquals(String supplied, String expected) {
    final suppliedDigest = sha256.convert(utf8.encode(supplied)).bytes;
    final expectedDigest = sha256.convert(utf8.encode(expected)).bytes;
    var difference = suppliedDigest.length ^ expectedDigest.length;
    for (var index = 0; index < suppliedDigest.length; index += 1) {
      difference |= suppliedDigest[index] ^ expectedDigest[index];
    }
    return difference == 0;
  }

  Middleware _securityHeaders() =>
      (innerHandler) => (request) async {
        final response = await innerHandler(request);
        return response.change(
          headers: <String, String>{
            ...response.headers,
            'cache-control': 'no-store',
            'referrer-policy': 'no-referrer',
            'x-content-type-options': 'nosniff',
          },
        );
      };
}
