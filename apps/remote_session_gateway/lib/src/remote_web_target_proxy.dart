import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:shelf/shelf.dart';

final class RemoteWebBootstrapNotice {
  const RemoteWebBootstrapNotice({
    required this.endpoint,
    required this.grant,
    required this.expiresAt,
  });

  final String endpoint;
  final String grant;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'web.bootstrap.required',
    'endpoint': endpoint,
    'grant': grant,
    'expiresAt': expiresAt.toIso8601String(),
  };
}

final class RemoteWebTargetProxy {
  RemoteWebTargetProxy({
    required this.runId,
    required this.targetOrigin,
    required Set<String> allowedViewerOrigins,
    required this.sessionDeadline,
    required this.clock,
    required this.ids,
    HttpClient? client,
  }) : _allowedViewerOrigins = Set<String>.unmodifiable(allowedViewerOrigins),
       _client = client ?? HttpClient() {
    final loopback =
        targetOrigin.host == '127.0.0.1' ||
        targetOrigin.host == '::1' ||
        targetOrigin.host == 'localhost';
    if (targetOrigin.scheme != 'http' ||
        !targetOrigin.hasAuthority ||
        !loopback ||
        targetOrigin.userInfo.isNotEmpty ||
        targetOrigin.query.isNotEmpty ||
        targetOrigin.fragment.isNotEmpty ||
        (targetOrigin.path.isNotEmpty && targetOrigin.path != '/')) {
      throw ArgumentError(
        'remote web target must be an uncredentialed loopback HTTP origin',
      );
    }
    if (!sessionDeadline.isUtc ||
        !sessionDeadline.isAfter(clock.nowUtc()) ||
        _allowedViewerOrigins.isEmpty) {
      throw ArgumentError('remote web target session is invalid');
    }
  }

  static const String cookieName = '__Secure-DevExWebSession';
  static const int _maximumBootstrapBytes = 4096;
  static const int _maximumIndexBytes = 4 * 1024 * 1024;
  static const int _maximumAssetBytes = 512 * 1024 * 1024;

  final String runId;
  final Uri targetOrigin;
  final Set<String> _allowedViewerOrigins;
  final DateTime sessionDeadline;
  final Clock clock;
  final IdGenerator ids;
  final HttpClient _client;
  String? _viewerNonce;
  String? _bootstrapGrant;
  String? _cookieSecret;
  bool _closed = false;

  String get bootstrapPath => '/v1/sessions/$runId/web/bootstrap';

  String get targetPath => '/v1/sessions/$runId/web/target/';

  RemoteWebBootstrapNotice issueBootstrap(RemoteSessionTicket ticket) {
    if (_closed ||
        ticket.runId != runId ||
        !ticket.allowedTransports.contains(
          RemoteInteractiveTransport.webDirect,
        ) ||
        !sessionDeadline.isAfter(clock.nowUtc())) {
      throw StateError('viewer cannot bootstrap this web target');
    }
    final grant = ids.nextId();
    if (grant.length < 16 || grant.length > 256) {
      throw StateError('bootstrap grant generator returned an invalid value');
    }
    _viewerNonce = ticket.nonce;
    _bootstrapGrant = grant;
    _cookieSecret = null;
    return RemoteWebBootstrapNotice(
      endpoint: bootstrapPath,
      grant: grant,
      expiresAt: sessionDeadline,
    );
  }

  Response preflight(Request request) {
    final origin = request.headers['origin'];
    if (origin == null || !_allowedViewerOrigins.contains(origin)) {
      return Response.forbidden('viewer origin is not allowed');
    }
    final requestedMethod = request.headers['access-control-request-method'];
    if (requestedMethod != 'POST') {
      return Response.forbidden('bootstrap method is not allowed');
    }
    return Response.ok(
      '',
      headers: <String, String>{
        ..._cors(origin),
        'access-control-allow-methods': 'POST',
        'access-control-allow-headers': 'content-type',
        'access-control-max-age': '60',
      },
    );
  }

  Future<Response> bootstrap(Request request) async {
    final origin = request.headers['origin'];
    if (origin == null || !_allowedViewerOrigins.contains(origin)) {
      return Response.forbidden('viewer origin is not allowed');
    }
    if (_closed ||
        _viewerNonce == null ||
        _bootstrapGrant == null ||
        !sessionDeadline.isAfter(clock.nowUtc())) {
      return Response(HttpStatus.gone, body: 'web session is not available');
    }
    final contentType = request.headers[HttpHeaders.contentTypeHeader];
    if (contentType == null ||
        !contentType.toLowerCase().startsWith('application/json')) {
      return Response(HttpStatus.unsupportedMediaType);
    }
    final bytes = await _readBounded(request.read(), _maximumBootstrapBytes);
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return Response.badRequest(body: 'bootstrap document is invalid');
    }
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(const <String>{'grant'}).isNotEmpty ||
        decoded['grant'] is! String ||
        !_constantTimeEquals(decoded['grant']! as String, _bootstrapGrant!)) {
      return Response.forbidden('bootstrap grant is invalid');
    }
    _bootstrapGrant = null;
    final cookieSecret = ids.nextId();
    if (cookieSecret.length < 16 || cookieSecret.length > 256) {
      throw StateError('cookie generator returned an invalid value');
    }
    _cookieSecret = cookieSecret;
    final maximumAge = sessionDeadline.difference(clock.nowUtc()).inSeconds;
    return Response(
      HttpStatus.created,
      body: jsonEncode(<String, Object?>{'target': targetPath}),
      headers: <String, String>{
        ..._cors(origin),
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-store',
        HttpHeaders.setCookieHeader:
            '$cookieName=$cookieSecret; Path=$targetPath; Max-Age=$maximumAge; '
            'Secure; HttpOnly; SameSite=None',
      },
    );
  }

  Future<Response> proxy(Request request, String path) async {
    if (_closed || !sessionDeadline.isAfter(clock.nowUtc())) {
      return Response(HttpStatus.gone, body: 'web session expired');
    }
    final cookie = _cookie(request.headers[HttpHeaders.cookieHeader]);
    final expected = _cookieSecret;
    if (expected == null ||
        cookie == null ||
        !_constantTimeEquals(cookie, expected)) {
      return Response.forbidden('web target authentication failed');
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(HttpStatus.methodNotAllowed);
    }
    if (path.contains('\\') ||
        path.contains('\u0000') ||
        path.split('/').contains('..')) {
      return Response.badRequest(body: 'web target path is invalid');
    }
    final target = targetOrigin.replace(
      path: '/$path',
      query: request.url.hasQuery ? request.url.query : null,
    );
    final upstream = await _client.openUrl(request.method, target);
    upstream
      ..followRedirects = false
      ..maxRedirects = 0;
    for (final name in const <String>[
      HttpHeaders.acceptHeader,
      HttpHeaders.acceptLanguageHeader,
      HttpHeaders.ifModifiedSinceHeader,
      HttpHeaders.ifNoneMatchHeader,
      HttpHeaders.rangeHeader,
    ]) {
      final value = request.headers[name];
      if (value != null) upstream.headers.set(name, value);
    }
    final response = await upstream.close().timeout(
      const Duration(seconds: 15),
    );
    if (response.isRedirect || response.contentLength > _maximumAssetBytes) {
      await response.drain<void>();
      return Response(
        HttpStatus.badGateway,
        body: 'web target response was rejected',
      );
    }
    final headers = <String, String>{
      HttpHeaders.cacheControlHeader: 'no-store',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
    };
    for (final name in const <String>[
      HttpHeaders.acceptRangesHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.contentTypeHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.lastModifiedHeader,
    ]) {
      final value = response.headers.value(name);
      if (value != null) headers[name] = value;
    }
    final isIndex =
        request.method == 'GET' &&
        (path.isEmpty || path == 'index.html') &&
        response.statusCode == HttpStatus.ok;
    if (isIndex) {
      final bytes = await _readBounded(response, _maximumIndexBytes);
      final html = utf8.decode(bytes, allowMalformed: false);
      return Response(
        response.statusCode,
        body: _rewriteBase(html),
        headers: headers,
      );
    }
    return Response(
      response.statusCode,
      body: request.method == 'HEAD'
          ? null
          : _boundedResponse(response, _maximumAssetBytes),
      headers: headers,
    );
  }

  void revoke(String viewerNonce) {
    if (_viewerNonce != viewerNonce) return;
    _viewerNonce = null;
    _bootstrapGrant = null;
    _cookieSecret = null;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _viewerNonce = null;
    _bootstrapGrant = null;
    _cookieSecret = null;
    _client.close(force: true);
  }

  Map<String, String> _cors(String origin) => <String, String>{
    'access-control-allow-origin': origin,
    'access-control-allow-credentials': 'true',
    HttpHeaders.varyHeader: 'origin',
  };

  String? _cookie(String? header) {
    if (header == null || header.length > 4096) return null;
    String? found;
    for (final field in header.split(';')) {
      final separator = field.indexOf('=');
      if (separator < 1) continue;
      if (field.substring(0, separator).trim() != cookieName) continue;
      if (found != null) return null;
      found = field.substring(separator + 1).trim();
    }
    return found;
  }

  String _rewriteBase(String html) {
    final base = '<base href="$targetPath">';
    final expression = RegExp(
      r'''<base\s+href\s*=\s*(["']).*?\1\s*/?>''',
      caseSensitive: false,
    );
    if (expression.hasMatch(html)) {
      return html.replaceFirst(expression, base);
    }
    final head = RegExp(r'<head(?:\s[^>]*)?>', caseSensitive: false);
    final match = head.firstMatch(html);
    if (match == null) return '$base$html';
    return html.replaceRange(match.end, match.end, base);
  }
}

Future<List<int>> _readBounded(Stream<List<int>> input, int maximum) async {
  final bytes = <int>[];
  await for (final chunk in input) {
    bytes.addAll(chunk);
    if (bytes.length > maximum) {
      throw StateError('remote web payload exceeded its size limit');
    }
  }
  return bytes;
}

Stream<List<int>> _boundedResponse(
  Stream<List<int>> input,
  int maximum,
) async* {
  var total = 0;
  await for (final chunk in input) {
    total += chunk.length;
    if (total > maximum) {
      throw StateError('remote web response exceeded its size limit');
    }
    yield chunk;
  }
}

bool _constantTimeEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  var difference = leftBytes.length ^ rightBytes.length;
  final maximum = leftBytes.length > rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  for (var index = 0; index < maximum; index += 1) {
    final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
    final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}
