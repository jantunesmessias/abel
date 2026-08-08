import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../storage/filesystem_workspace_store.dart';

final class SystemDelay implements DelayPort {
  const SystemDelay();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

final class CasGatewayMockHandler implements MockHandlerPort {
  CasGatewayMockHandler(this.store, {this.maxCacheBytes = 64 * 1024 * 1024}) {
    if (maxCacheBytes < 256 * 1024) {
      throw ArgumentError.value(maxCacheBytes, 'maxCacheBytes');
    }
  }

  final FileSystemWorkspaceStore store;
  final int maxCacheBytes;
  final Map<Digest, ImmutableBytes> _cache = <Digest, ImmutableBytes>{};
  final ListQueue<Digest> _cacheOrder = ListQueue<Digest>();
  var _cacheBytes = 0;

  @override
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayFixture fixture,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  }) async {
    final cached = _cache[fixture.bodyDigest];
    if (cached != null) {
      return _result(fixture, cached);
    }
    final body = store.readBlob(fixture.bodyDigest);
    if (body == null) {
      throw StateError('Fixture blob ${fixture.bodyDigest.value} is missing');
    }
    if (body.length != fixture.bodySize ||
        Digest.bytes(body) != fixture.bodyDigest) {
      throw StateError('Fixture blob ${fixture.bodyDigest.value} is invalid');
    }
    while (_cacheBytes + body.length > maxCacheBytes &&
        _cacheOrder.isNotEmpty) {
      final evicted = _cacheOrder.removeFirst();
      _cacheBytes -= _cache.remove(evicted)!.length;
    }
    final immutableBody = ImmutableBytes.copyOf(body);
    _cache[fixture.bodyDigest] = immutableBody;
    _cacheOrder.addLast(fixture.bodyDigest);
    _cacheBytes += body.length;
    return _result(fixture, immutableBody);
  }

  GatewayMockResult _result(GatewayFixture fixture, List<int> body) =>
      GatewayMockResult(
        status: fixture.status,
        headers: <String, String>{
          ...fixture.headers,
          if (!fixture.headers.containsKey('content-type'))
            'content-type': fixture.mediaType,
        },
        body: body,
      );
}

final class GatewayHttpServer {
  GatewayHttpServer({
    required this.runtime,
    Set<Uri> allowedOrigins = const <Uri>{},
    this.port = 0,
    this.maxRequestBodyBytes = 256 * 1024,
  }) : allowedOrigins = Set<String>.unmodifiable(
         allowedOrigins.map(_canonicalAllowedOrigin),
       ) {
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    if (maxRequestBodyBytes <= 0 || maxRequestBodyBytes > 256 * 1024) {
      throw ArgumentError.value(maxRequestBodyBytes, 'maxRequestBodyBytes');
    }
  }

  final GatewayRuntime runtime;
  final Set<String> allowedOrigins;
  final int port;
  final int maxRequestBodyBytes;
  HttpServer? _server;

  Uri get origin {
    final server = _server;
    if (server == null) throw StateError('Gateway data plane is not running');
    return Uri(scheme: 'http', host: server.address.address, port: server.port);
  }

  Future<void> start() async {
    if (_server != null) {
      throw StateError('Gateway data plane is already running');
    }
    _server = await shelf_io.serve(
      _handle,
      InternetAddress.loopbackIPv4,
      port,
      poweredByHeader: null,
    );
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<Response> _handle(Request request) async {
    final requestOrigin = request.headers['origin'];
    if (requestOrigin != null && !allowedOrigins.contains(requestOrigin)) {
      return _error(403, 'DEVEX_GATEWAY_ORIGIN_DENIED');
    }
    if (request.method == 'OPTIONS' &&
        request.headers['access-control-request-method'] != null) {
      if (requestOrigin == null) {
        return _error(400, 'DEVEX_GATEWAY_PREFLIGHT_INVALID');
      }
      return Response(204, headers: _corsHeaders(requestOrigin));
    }
    try {
      final declaredLength = request.contentLength;
      if (declaredLength != null && declaredLength > maxRequestBodyBytes) {
        throw const _RequestTooLarge();
      }
      final body = await _readBounded(request.read());
      final normalized = GatewayRequest(
        method: request.method,
        path: request.requestedUri.path,
        query: request.requestedUri.queryParametersAll,
        body: body,
      );
      final response = await runtime.handle(normalized);
      if (response.disconnected) {
        request.hijack((channel) {
          unawaited(channel.sink.close());
        });
      }
      return Response(
        response.status,
        headers: <String, String>{
          ...response.headers,
          ...?_optionalCorsHeaders(requestOrigin),
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
        },
        body: response.body,
      );
    } on HijackException {
      rethrow;
    } on _RequestTooLarge {
      return _error(
        413,
        'DEVEX_GATEWAY_REQUEST_TOO_LARGE',
        origin: requestOrigin,
      );
    } on FormatException {
      return _error(
        400,
        'DEVEX_GATEWAY_REQUEST_INVALID',
        origin: requestOrigin,
      );
    } on Object {
      return _error(500, 'DEVEX_GATEWAY_INTERNAL', origin: requestOrigin);
    }
  }

  Future<List<int>> _readBounded(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      if (length > maxRequestBodyBytes) throw const _RequestTooLarge();
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Response _error(int status, String code, {String? origin}) => Response(
    status,
    headers: <String, String>{
      ...?_optionalCorsHeaders(origin),
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      'x-devex-gateway': 'denied',
    },
    body: jsonEncode(<String, Object?>{'error': code}),
  );

  Map<String, String>? _optionalCorsHeaders(String? origin) =>
      origin == null ? null : _corsHeaders(origin);

  Map<String, String> _corsHeaders(String origin) => <String, String>{
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'access-control-allow-headers': 'content-type',
    'access-control-max-age': '600',
    'vary': 'origin',
  };
}

String _canonicalAllowedOrigin(Uri value) {
  final address = InternetAddress.tryParse(value.host);
  if (!value.isAbsolute ||
      !const <String>{'http', 'https'}.contains(value.scheme) ||
      (value.host != 'localhost' && address?.isLoopback != true) ||
      value.userInfo.isNotEmpty ||
      value.hasQuery ||
      value.hasFragment ||
      (value.path.isNotEmpty && value.path != '/')) {
    throw ArgumentError.value(value, 'allowedOrigins');
  }
  return value.origin;
}

final class _RequestTooLarge implements Exception {
  const _RequestTooLarge();
}
