import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:experience_contracts/experience_contracts.dart';
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

typedef HostRpcConnectionMethodHandler =
    FutureOr<Object?> Function(
      Map<String, Object?> params,
      HostRpcConnectionContext context,
    );

typedef HostRpcConnectionClosedHandler =
    FutureOr<void> Function(HostRpcConnectionContext context);

/// Host-owned identity for one accepted WebSocket connection.
///
/// The epoch is available only to in-process connection-aware handlers and is
/// deliberately absent from JSON-RPC and bootstrap payloads.
final class HostRpcConnectionContext {
  HostRpcConnectionContext._(this.connectionEpoch) {
    final byteLength = utf8.encode(connectionEpoch).length;
    if (byteLength < 1 || byteLength > maxEpochBytes) {
      throw ArgumentError.value(
        connectionEpoch,
        'connectionEpoch',
        'must contain between 1 and $maxEpochBytes UTF-8 bytes',
      );
    }
  }

  static const int maxEpochBytes = 128;

  final String connectionEpoch;

  @override
  String toString() => 'HostRpcConnectionContext(<opaque>)';
}

/// Typed application rejection preserved as JSON-RPC error data.
final class HostRpcApplicationException implements Exception {
  const HostRpcApplicationException({
    required this.code,
    required this.message,
    this.data,
  });

  final int code;
  final String message;
  final Object? data;
}

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
    Map<String, HostRpcConnectionMethodHandler> connectionAwareMethods =
        const <String, HostRpcConnectionMethodHandler>{},
    this.onConnectionClosed,
  }) : bindAddress = bindAddress ?? InternetAddress.loopbackIPv4,
       journal = journal ?? HostEventJournal(),
       resources =
           resourceRegistry ??
           HostResourceRegistry(clock: SystemClock(), ids: SecureIdGenerator()),
       applicationMethods = Map<String, HostRpcMethodHandler>.unmodifiable(
         applicationMethods,
       ),
       connectionAwareMethods =
           Map<String, HostRpcConnectionMethodHandler>.unmodifiable(
             connectionAwareMethods,
           ) {
    final duplicateMethods = this.applicationMethods.keys.toSet().intersection(
      this.connectionAwareMethods.keys.toSet(),
    );
    if (duplicateMethods.isNotEmpty) {
      final sortedDuplicates = duplicateMethods.toList()..sort();
      throw ArgumentError.value(
        sortedDuplicates,
        'connectionAwareMethods',
        'must not duplicate applicationMethods',
      );
    }
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
  static const int maxStringRequestIdLength = 128;
  static const int maxIntegerRequestId = 9007199254740991;
  static final Object _closeGuardInvocationZoneKey = Object();
  static const List<String> capabilities = <String>[
    'events.resume',
    'session.heartbeat',
  ];

  /// Request IDs accepted by the Host are a small I-JSON-safe subset. This
  /// bounds the exact response envelope independently of the caller input.
  static bool supportsRequestId(Object id) => switch (id) {
    final int value =>
      value >= -maxIntegerRequestId && value <= maxIntegerRequestId,
    final String value => RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(value),
    _ => false,
  };

  /// Proves a success payload fits even with the largest accepted response ID.
  static bool successPayloadFits(
    Object? result, {
    required int maxMessageBytes,
  }) {
    final representativeId = List<String>.filled(
      maxStringRequestIdLength,
      'x',
    ).join();
    final encoded = JsonRpcResponse.success(
      id: representativeId,
      result: result,
    ).encode();
    return utf8.encode(encoded).length <= maxMessageBytes;
  }

  final Uri studioOrigin;
  final String sessionToken;
  final InternetAddress bindAddress;
  final int port;
  final int maxMessageBytes;
  final EffectiveKitManifest Function()? studioBootstrapManifest;
  final HostEventJournal journal;
  final HostResourceRegistry resources;
  final Map<String, HostRpcMethodHandler> applicationMethods;
  final Map<String, HostRpcConnectionMethodHandler> connectionAwareMethods;
  final HostRpcConnectionClosedHandler? onConnectionClosed;
  final JsonRpcCodec _codec = const JsonRpcCodec();
  final SecureIdGenerator _connectionEpochIds = SecureIdGenerator();
  final Map<WebSocketChannel, _HostRpcConnectionState> _connections =
      <WebSocketChannel, _HostRpcConnectionState>{};
  final Set<WebSocketChannel> _initializedConnections = <WebSocketChannel>{};

  HttpServer? _server;
  Future<void>? _closing;
  var _acceptingConnections = false;
  var _nextConnectionEpoch = 0;

  bool get isRunning => _server != null;
  int get activeConnections => _connections.length;

  Uri get httpUri {
    final server = _server;
    if (server == null) throw StateError('Host RPC server is not running');
    return Uri(scheme: 'http', host: server.address.address, port: server.port);
  }

  Uri get webSocketUri => httpUri.replace(scheme: 'ws', path: '/rpc');

  Future<void> start() async {
    if (_server != null || _closing != null) {
      throw StateError('Host RPC server already started or closing');
    }
    final socketHandler = webSocketHandler(_onConnection);
    final handler = const Pipeline()
        .addMiddleware(_securityHeaders())
        .addHandler((request) => _route(request, socketHandler));
    _acceptingConnections = true;
    try {
      _server = await shelf_io.serve(handler, bindAddress, port);
    } on Object {
      _acceptingConnections = false;
      rethrow;
    }
  }

  Future<void> close() {
    final invocation = Zone.current[_closeGuardInvocationZoneKey];
    if (invocation is _HostRpcCloseGuardInvocation &&
        invocation.isActive &&
        identical(invocation.server, this)) {
      return Future<void>.error(
        StateError('Host RPC server cannot close from ${invocation.source}'),
      );
    }
    final closing = _closing;
    if (closing != null) return closing;
    late final Future<void> tracked;
    tracked = _close().whenComplete(() {
      if (identical(_closing, tracked)) _closing = null;
    });
    _closing = tracked;
    return tracked;
  }

  Future<void> _close() async {
    _acceptingConnections = false;
    final server = _server;
    _server = null;
    final connections = List<WebSocketChannel>.of(_connections.keys);

    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> record(Future<void> operation) async {
      try {
        await operation;
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    final operations = <Future<void>>[
      for (final connection in connections)
        _closeConnection(
          connection,
          closeServerShutdown,
          'Workspace Host shutting down',
          errorOwner: _HostRpcDropErrorOwner.caller,
        ),
      if (server != null) server.close(force: true).then<void>((_) {}),
    ];
    await Future.wait<void>(operations.map(record));

    while (_connections.isNotEmpty) {
      final remaining = List<WebSocketChannel>.of(_connections.keys);
      await Future.wait<void>(
        remaining.map(
          (connection) => record(
            _closeConnection(
              connection,
              closeServerShutdown,
              'Workspace Host shutting down',
              errorOwner: _HostRpcDropErrorOwner.caller,
            ),
          ),
        ),
      );
    }
    resources.clear();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
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
    if (request.url.path == 'studio/bootstrap.json' &&
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
    final state = _HostRpcConnectionState(_issueConnectionContext());
    if (!_acceptingConnections) {
      state
        ..isDropping = true
        ..claimDropErrorOwner(_HostRpcDropErrorOwner.caller);
    }
    _connections[channel] = state;
    state.subscription = channel.stream.listen(
      (message) => _runDetached(_onMessage(channel, message)),
      onError: (Object _) {
        _handleConnectionTermination(channel);
      },
      onDone: () {
        _handleConnectionTermination(channel);
      },
      cancelOnError: true,
    );
  }

  Future<void> _onMessage(WebSocketChannel channel, Object? message) async {
    final connection = _connections[channel];
    if (connection == null || connection.isDropping) return;
    if (message is! String) {
      await _closeConnection(
        channel,
        closeUnsupportedFrame,
        'Text frames required',
        errorOwner: _HostRpcDropErrorOwner.zone,
      );
      return;
    }
    if (utf8.encode(message).length > maxMessageBytes) {
      await _closeConnection(
        channel,
        closeMessageTooLarge,
        'Message too large',
        errorOwner: _HostRpcDropErrorOwner.zone,
      );
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
    if (!supportsRequestId(decoded.id)) {
      channel.sink.add(
        JsonRpcResponse.error(
          id: null,
          error: const JsonRpcError(
            code: JsonRpcError.invalidRequest,
            message: 'RPC request id is outside the Host profile',
          ),
        ).encode(),
      );
      return;
    }

    if (decoded.method != 'workspace.initialize' &&
        !_initializedConnections.contains(channel)) {
      channel.sink.add(
        JsonRpcResponse.error(
          id: decoded.id,
          error: const JsonRpcError(
            code: -32001,
            message: 'workspace.initialize is required first',
          ),
        ).encode(),
      );
      return;
    }

    final response = await _dispatch(decoded, connection);
    if (connection.isDropping) return;
    if (decoded.method == 'workspace.initialize' && response.isSuccess) {
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

  Future<JsonRpcResponse> _dispatch(
    JsonRpcRequest request,
    _HostRpcConnectionState connection,
  ) async {
    switch (request.method) {
      case 'workspace.initialize':
        return _initialize(request);
      case 'connection.resume':
        return _resume(request);
      case 'connection.ping':
        return JsonRpcResponse.success(
          id: request.id,
          result: <String, Object?>{'status': 'ok'},
        );
    }
    final handler = applicationMethods[request.method];
    final connectionHandler = connectionAwareMethods[request.method];
    if (handler == null && connectionHandler == null) {
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
      final Object? result;
      if (handler != null) {
        result = await handler(
          params as Map<String, Object?>? ?? const <String, Object?>{},
        );
      } else {
        result = await _invokeConnectionAware(
          connection,
          connectionHandler!,
          params as Map<String, Object?>? ?? const <String, Object?>{},
        );
      }
      return JsonRpcResponse.success(id: request.id, result: result);
    } on HostRpcApplicationException catch (error) {
      return JsonRpcResponse.error(
        id: request.id,
        error: JsonRpcError(
          code: error.code,
          message: error.message,
          data: error.data,
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
          ...(<String>{
            ...applicationMethods.keys,
            ...connectionAwareMethods.keys,
          }.toList()..sort()),
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

  Future<Object?> _invokeConnectionAware(
    _HostRpcConnectionState connection,
    HostRpcConnectionMethodHandler handler,
    Map<String, Object?> params,
  ) async {
    if (connection.isDropping) {
      throw StateError('RPC connection is closing');
    }
    final invocationCompleted = Completer<void>();
    final completion = invocationCompleted.future;
    final invocation = _HostRpcCloseGuardInvocation(
      this,
      'a connection-aware handler',
    );
    connection.inFlight.add(completion);
    try {
      return await runZoned<FutureOr<Object?>>(
        () => handler(params, connection.context),
        zoneValues: <Object?, Object?>{
          _closeGuardInvocationZoneKey: invocation,
        },
      );
    } finally {
      invocation.isActive = false;
      connection.inFlight.remove(completion);
      invocationCompleted.complete();
    }
  }

  HostRpcConnectionContext _issueConnectionContext() {
    final epoch = '${_connectionEpochIds.nextId()}.${_nextConnectionEpoch++}';
    final byteLength = utf8.encode(epoch).length;
    if (byteLength < 1 || byteLength > HostRpcConnectionContext.maxEpochBytes) {
      throw StateError('Host connection epoch generator violated its bound');
    }
    return HostRpcConnectionContext._(epoch);
  }

  Future<void> _closeConnection(
    WebSocketChannel channel,
    int closeCode,
    String closeReason, {
    required _HostRpcDropErrorOwner errorOwner,
  }) async {
    _connections[channel]?.claimDropErrorOwner(errorOwner);
    try {
      await channel.sink.close(closeCode, closeReason);
    } finally {
      await _dropConnection(channel, errorOwner: errorOwner);
    }
  }

  Future<void> _dropConnection(
    WebSocketChannel channel, {
    required _HostRpcDropErrorOwner errorOwner,
  }) {
    final connection = _connections[channel];
    if (connection == null) return Future<void>.value();
    connection.claimDropErrorOwner(errorOwner);
    final dropping = connection.dropFuture;
    if (dropping != null) return dropping;

    connection.isDropping = true;
    _initializedConnections.remove(channel);
    final dropped = Completer<void>();
    connection.dropFuture = dropped.future;
    unawaited(
      _completeConnectionDrop(channel, connection).then<void>(
        (_) => dropped.complete(),
        onError: (Object error, StackTrace stackTrace) {
          dropped.completeError(error, stackTrace);
        },
      ),
    );
    return dropped.future;
  }

  void _handleConnectionTermination(WebSocketChannel channel) {
    final connection = _connections[channel];
    if (connection == null ||
        connection.dropErrorOwner == _HostRpcDropErrorOwner.caller) {
      return;
    }
    unawaited(
      _dropConnection(channel, errorOwner: _HostRpcDropErrorOwner.zone),
    );
  }

  Future<void> _completeConnectionDrop(
    WebSocketChannel channel,
    _HostRpcConnectionState connection,
  ) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> record(Future<void> operation) async {
      try {
        await operation;
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    try {
      await record(connection.cancelSubscription());
      final inFlight = List<Future<void>>.of(connection.inFlight);
      if (inFlight.isNotEmpty) {
        await record(Future.wait<void>(inFlight));
      }
      final callback = onConnectionClosed;
      if (callback != null) {
        await record(_invokeConnectionClosed(callback, connection.context));
      }
    } finally {
      if (identical(_connections[channel], connection)) {
        _connections.remove(channel);
      }
    }
    if (firstError != null) {
      final errorOwner = connection.dropErrorOwner;
      if (errorOwner == _HostRpcDropErrorOwner.caller) {
        Error.throwWithStackTrace(firstError!, firstStackTrace!);
      }
      if (errorOwner == _HostRpcDropErrorOwner.zone) {
        connection.dropErrorZone!.handleUncaughtError(
          firstError!,
          firstStackTrace!,
        );
        return;
      }
      throw StateError('Host RPC drop completed without an error owner');
    }
  }

  Future<void> _invokeConnectionClosed(
    HostRpcConnectionClosedHandler callback,
    HostRpcConnectionContext context,
  ) async {
    final invocation = _HostRpcCloseGuardInvocation(
      this,
      'a revocation callback',
    );
    try {
      await runZoned<Future<void>>(
        () => Future<void>.sync(() => callback(context)),
        zoneValues: <Object?, Object?>{
          _closeGuardInvocationZoneKey: invocation,
        },
      );
    } finally {
      invocation.isActive = false;
    }
  }

  void _runDetached(Future<void> operation) {
    unawaited(
      operation.onError((Object error, StackTrace stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }),
    );
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

enum _HostRpcDropErrorOwner { caller, zone }

final class _HostRpcCloseGuardInvocation {
  _HostRpcCloseGuardInvocation(this.server, this.source);

  final HostRpcServer server;
  final String source;
  var isActive = true;
}

final class _HostRpcConnectionState {
  _HostRpcConnectionState(this.context);

  final HostRpcConnectionContext context;
  final Set<Future<void>> inFlight = <Future<void>>{};
  StreamSubscription<Object?>? subscription;
  Future<void>? dropFuture;
  _HostRpcDropErrorOwner? dropErrorOwner;
  Zone? dropErrorZone;
  var isDropping = false;

  void claimDropErrorOwner(_HostRpcDropErrorOwner owner) {
    if (dropErrorOwner != null) return;
    dropErrorOwner = owner;
    if (owner == _HostRpcDropErrorOwner.zone) dropErrorZone = Zone.current;
  }

  Future<void> cancelSubscription() async {
    await subscription?.cancel();
    subscription = null;
  }
}
