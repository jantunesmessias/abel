import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

/// Serves the packaged Studio and a same-origin, non-cacheable bootstrap.
final class DevExStudioServer {
  DevExStudioServer({required String assetRoot})
    : assetRoot = Directory(assetRoot).absolute.path;

  final String assetRoot;
  HttpServer? _server;
  _StudioBootstrap? _bootstrap;
  List<int>? _indexBytes;

  bool get isRunning => _server != null;
  bool get isReady => _bootstrap != null;

  Uri get origin {
    final server = _server;
    if (server == null) throw StateError('Studio server is not running');
    return Uri(scheme: 'http', host: server.address.address, port: server.port);
  }

  Future<void> start({int port = 0}) async {
    if (_server != null) throw StateError('Studio server already started');
    if (port < 0 || port > 65535) throw ArgumentError.value(port, 'port');
    final root = Directory(assetRoot);
    if (!root.existsSync() ||
        !File(p.join(root.path, 'index.html')).existsSync()) {
      throw FileSystemException(
        'Packaged Studio assets are incomplete',
        root.path,
      );
    }
    if (Link(root.path).existsSync()) {
      throw FileSystemException(
        'Studio asset root cannot be a link',
        root.path,
      );
    }
    final indexBytes = File(p.join(root.path, 'index.html')).readAsBytesSync();
    if (indexBytes.isEmpty || indexBytes.length > 2 * 1024 * 1024) {
      throw const FormatException('Studio index.html exceeds its size budget');
    }
    _indexBytes = List<int>.unmodifiable(indexBytes);
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FileSystemException(
          'Studio assets cannot contain links',
          entity.path,
        );
      }
    }
    final staticHandler = createStaticHandler(
      root.resolveSymbolicLinksSync(),
      defaultDocument: 'index.html',
    );
    final handler = const Pipeline()
        .addMiddleware(_securityHeaders())
        .addHandler((request) => _route(request, staticHandler));
    _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
  }

  void configure({
    required Uri hostOrigin,
    required String sessionToken,
    required EffectiveKitManifest effectiveKitManifest,
  }) {
    if (_server == null) throw StateError('Studio server is not running');
    if (_bootstrap != null) {
      throw StateError('Studio bootstrap already configured');
    }
    if (sessionToken.length < 32) {
      throw ArgumentError.value(sessionToken, 'sessionToken');
    }
    _bootstrap = _StudioBootstrap(
      hostOrigin: hostOrigin,
      sessionToken: sessionToken,
      effectiveKitManifest: effectiveKitManifest,
    );
  }

  Future<void> close() async {
    _bootstrap = null;
    _indexBytes = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<Response> _route(Request request, Handler staticHandler) async {
    if (request.url.path == 'health') {
      if (request.method != 'GET') {
        return Response(405, headers: const <String, String>{'allow': 'GET'});
      }
      return Response.ok(
        jsonEncode(<String, Object?>{'status': isReady ? 'ready' : 'starting'}),
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    if (request.url.path == 'devex/bootstrap.json') {
      if (request.method != 'GET') {
        return Response(405, headers: const <String, String>{'allow': 'GET'});
      }
      if (request.url.hasQuery ||
          request.headers['sec-fetch-site'] != 'same-origin') {
        return Response.forbidden('Bootstrap denied');
      }
      final bootstrap = _bootstrap;
      if (bootstrap == null) return Response(503, body: 'Studio is starting');
      return Response.ok(
        const JcsCanonicalizer().canonicalize(bootstrap.toJson()),
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    final response = await staticHandler(request);
    if (response.statusCode != HttpStatus.notFound ||
        request.method != 'GET' ||
        p.extension(request.url.path).isNotEmpty) {
      return response;
    }
    final indexBytes = _indexBytes;
    if (indexBytes == null) return Response(503, body: 'Studio is starting');
    return Response.ok(
      indexBytes,
      headers: <String, String>{
        'content-type': 'text/html; charset=utf-8',
        'content-length': '${indexBytes.length}',
      },
    );
  }

  Middleware _securityHeaders() =>
      (inner) => (request) async {
        final response = await inner(request);
        return response.change(
          headers: <String, String>{
            ...response.headers,
            'cache-control': 'no-store',
            'content-security-policy': _contentSecurityPolicy(),
            'cross-origin-opener-policy': 'same-origin',
            'referrer-policy': 'no-referrer',
            'x-content-type-options': 'nosniff',
          },
        );
      };

  String _contentSecurityPolicy() {
    final hostOrigin = _bootstrap?.hostOrigin;
    final hostHttp = hostOrigin?.origin;
    final hostWebSocket = hostOrigin == null
        ? null
        : '${hostOrigin.scheme == 'https' ? 'wss' : 'ws'}://${hostOrigin.authority}';
    return <String>[
      "default-src 'none'",
      "base-uri 'none'",
      "object-src 'none'",
      "frame-ancestors 'none'",
      "form-action 'none'",
      "script-src 'self'",
      "style-src 'self'",
      ["img-src 'self' data: blob:", ?hostHttp].join(' '),
      "font-src 'self'",
      "worker-src 'none'",
      "media-src 'none'",
      "frame-src http://127.0.0.1:* http://localhost:*",
      ["connect-src 'self'", ?hostHttp, ?hostWebSocket].join(' '),
    ].join('; ');
  }
}

final class _StudioBootstrap {
  const _StudioBootstrap({
    required this.hostOrigin,
    required this.sessionToken,
    required this.effectiveKitManifest,
  });

  final Uri hostOrigin;
  final String sessionToken;
  final EffectiveKitManifest effectiveKitManifest;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'protocolVersion': 1,
    'hostOrigin': hostOrigin.toString(),
    'rpcPath': '/rpc',
    'sessionToken': sessionToken,
    'effectiveKitManifest': effectiveKitManifest.toJson(),
  };
}
