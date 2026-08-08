import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';

import '../evidence/png_capture_inspector.dart';
import '../storage/filesystem_workspace_store.dart';

final class AppAdapterCaptureReceipt {
  const AppAdapterCaptureReceipt({
    required this.requestId,
    required this.sessionId,
    required this.artifactDigest,
    required this.pixelDigest,
    required this.size,
    required this.width,
    required this.height,
    required this.completedAt,
  });

  final String requestId;
  final String sessionId;
  final Digest artifactDigest;
  final Digest pixelDigest;
  final int size;
  final int width;
  final int height;
  final DateTime completedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'requestId': requestId,
    'sessionId': sessionId,
    'artifactDigest': artifactDigest.value,
    'pixelDigest': pixelDigest.value,
    'size': size,
    'width': width,
    'height': height,
    'mediaType': 'image/png',
    'completedAt': completedAt.toUtc().toIso8601String(),
  };
}

final class AppAdapterCaptureStatus {
  const AppAdapterCaptureStatus({
    required this.requestId,
    required this.sessionId,
    required this.state,
    this.receipt,
    this.failureCode,
  });

  final String requestId;
  final String sessionId;
  final String state;
  final AppAdapterCaptureReceipt? receipt;
  final String? failureCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'requestId': requestId,
    'sessionId': sessionId,
    'state': state,
    if (receipt != null) 'receipt': receipt!.toJson(),
    if (failureCode != null) 'failureCode': failureCode,
  };
}

final class AppAdapterCaptureBridge {
  AppAdapterCaptureBridge({
    required this.store,
    required this.clock,
    required this.ids,
    this.maxCaptureBytes = 32 * 1024 * 1024,
    this.handleTtl = const Duration(minutes: 2),
    this.maxPending = 32,
    this.inspector = const PngCaptureInspector(),
  }) {
    if (maxCaptureBytes < 1024 || maxCaptureBytes > 32 * 1024 * 1024) {
      throw ArgumentError.value(maxCaptureBytes, 'maxCaptureBytes');
    }
    if (handleTtl <= Duration.zero || handleTtl > const Duration(minutes: 5)) {
      throw ArgumentError.value(handleTtl, 'handleTtl');
    }
    if (maxPending < 1 || maxPending > 256) {
      throw ArgumentError.value(maxPending, 'maxPending');
    }
  }

  final FileSystemWorkspaceStore store;
  final Clock clock;
  final IdGenerator ids;
  final PngCaptureInspector inspector;
  final int maxCaptureBytes;
  final Duration handleTtl;
  final int maxPending;
  final Map<String, _PendingCapture> _pending = <String, _PendingCapture>{};
  final StreamController<AppAdapterCaptureReceipt> _completions =
      StreamController<AppAdapterCaptureReceipt>.broadcast(sync: true);
  final Set<Future<void>> _handlers = <Future<void>>{};
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;

  Stream<AppAdapterCaptureReceipt> get completions => _completions.stream;
  int get pendingCount => _pending.length;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _requests = server.listen((request) {
      late final Future<void> handler;
      handler = _handleSafely(request).whenComplete(() {
        _handlers.remove(handler);
      });
      _handlers.add(handler);
    });
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await _requests?.cancel();
    _requests = null;
    _pending.clear();
    await server?.close(force: true);
    await Future.wait<void>(_handlers.toList(growable: false));
    await _completions.close();
  }

  AppAdapterCaptureCommand issue({
    required String requestId,
    required String sessionId,
    required Uri targetOrigin,
  }) {
    final server = _server;
    if (server == null) throw StateError('Capture bridge is not running');
    _purgeExpired();
    if (_pending.values.where((pending) => !pending.isTerminal).length >=
        maxPending) {
      throw StateError('Capture bridge pending quota is exhausted');
    }
    _pruneTerminalHistory();
    if (_pending.containsKey(requestId)) {
      throw StateError('Capture request already exists');
    }
    if (!targetOrigin.hasScheme || targetOrigin.host.isEmpty) {
      throw const FormatException('Target origin must be absolute');
    }
    final token = ids.nextId();
    final expiresAt = clock.nowUtc().add(handleTtl);
    final uploadUri = Uri(
      scheme: 'http',
      host: server.address.address,
      port: server.port,
      path: '/capture-uploads/$requestId',
      queryParameters: <String, String>{'token': token},
    );
    final command = AppAdapterCaptureCommand(
      requestId: requestId,
      sessionId: sessionId,
      format: 'png',
      uploadUri: uploadUri,
      expiresAt: expiresAt,
      maxBytes: maxCaptureBytes,
    );
    _pending[requestId] = _PendingCapture(
      command: command,
      targetOrigin: targetOrigin.origin,
      token: token,
    );
    return command;
  }

  AppAdapterCaptureStatus status({
    required String sessionId,
    required String requestId,
  }) {
    _purgeExpired();
    final pending = _pending[requestId];
    if (pending == null || pending.command.sessionId != sessionId) {
      throw StateError('Unknown App Adapter capture request');
    }
    return AppAdapterCaptureStatus(
      requestId: requestId,
      sessionId: sessionId,
      state: pending.receipt != null
          ? 'completed'
          : pending.failureCode != null
          ? 'failed'
          : pending.uploading
          ? 'uploading'
          : 'pending',
      receipt: pending.receipt,
      failureCode: pending.failureCode,
    );
  }

  void discardSession(String sessionId) {
    _pending.removeWhere(
      (_, pending) => pending.command.sessionId == sessionId,
    );
  }

  Future<void> _handleSafely(HttpRequest request) async {
    try {
      await _handle(request);
    } on Object {
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..contentLength = 0;
        await request.response.close();
      } on Object {
        // The peer may already have closed after a partial upload.
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.set('x-content-type-options', 'nosniff');
    final segments = request.uri.pathSegments;
    if (segments.length != 2 || segments.first != 'capture-uploads') {
      return _respond(response, HttpStatus.notFound);
    }
    _purgeExpired();
    final pending = _pending[segments[1]];
    final origin = request.headers.value('origin');
    final token = request.uri.queryParameters['token'];
    if (pending == null ||
        origin != pending.targetOrigin ||
        token == null ||
        !_constantTimeEquals(token, pending.token)) {
      return _respond(response, HttpStatus.forbidden);
    }
    response.headers.set(HttpHeaders.accessControlAllowOriginHeader, origin!);
    response.headers.set(HttpHeaders.varyHeader, 'Origin');
    if (request.method == 'OPTIONS') {
      final requestedMethod = request.headers.value(
        'access-control-request-method',
      );
      if (requestedMethod != 'PUT') {
        return _respond(response, HttpStatus.forbidden);
      }
      response.headers.set(HttpHeaders.accessControlAllowMethodsHeader, 'PUT');
      response.headers.set(
        HttpHeaders.accessControlAllowHeadersHeader,
        'content-type',
      );
      return _respond(response, HttpStatus.noContent);
    }
    if (request.method != 'PUT' ||
        request.headers.contentType?.mimeType != 'image/png') {
      return _fail(pending, response, 'invalid_request', HttpStatus.badRequest);
    }
    if (pending.uploading ||
        pending.receipt != null ||
        pending.failureCode != null) {
      return _respond(response, HttpStatus.conflict);
    }
    if (request.contentLength > maxCaptureBytes) {
      return _fail(
        pending,
        response,
        'capture_too_large',
        HttpStatus.requestEntityTooLarge,
      );
    }
    pending.uploading = true;
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in request) {
        if (bytes.length + chunk.length > maxCaptureBytes) {
          return _fail(
            pending,
            response,
            'capture_too_large',
            HttpStatus.requestEntityTooLarge,
          );
        }
        bytes.add(chunk);
      }
      final value = bytes.takeBytes();
      final inspection = inspector.inspect(value);
      late final Digest artifactDigest;
      store.withExclusiveLock(() {
        artifactDigest = store.putBlob(value);
        store.rebuildCasIndex();
      });
      final receipt = AppAdapterCaptureReceipt(
        requestId: pending.command.requestId,
        sessionId: pending.command.sessionId,
        artifactDigest: artifactDigest,
        pixelDigest: inspection.pixelDigest,
        size: value.length,
        width: inspection.width,
        height: inspection.height,
        completedAt: clock.nowUtc(),
      );
      pending
        ..uploading = false
        ..token = ''
        ..terminalAt = receipt.completedAt
        ..receipt = receipt;
      _completions.add(receipt);
      response.headers.contentType = ContentType.json;
      response.statusCode = HttpStatus.created;
      response.write(jsonEncode(receipt.toJson()));
      await response.close();
    } on FormatException {
      await _fail(
        pending,
        response,
        'invalid_png',
        HttpStatus.unprocessableEntity,
      );
    } on Object {
      await _fail(
        pending,
        response,
        'capture_processing_failed',
        HttpStatus.internalServerError,
      );
    }
  }

  Future<void> _fail(
    _PendingCapture pending,
    HttpResponse response,
    String code,
    int status,
  ) async {
    pending
      ..uploading = false
      ..token = ''
      ..terminalAt = clock.nowUtc()
      ..failureCode = code;
    await _respond(response, status);
  }

  Future<void> _respond(HttpResponse response, int status) async {
    response.statusCode = status;
    response.contentLength = 0;
    await response.close();
  }

  void _purgeExpired() {
    final now = clock.nowUtc();
    _pending.removeWhere(
      (_, pending) => pending.isTerminal
          ? !pending.terminalAt!.add(handleTtl).isAfter(now)
          : !pending.command.expiresAt.isAfter(now),
    );
  }

  void _pruneTerminalHistory() {
    final maximumRecords = maxPending * 4;
    if (_pending.length < maximumRecords) return;
    final terminal =
        _pending.entries
            .where((entry) => entry.value.isTerminal)
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.value.terminalAt!.compareTo(right.value.terminalAt!),
          );
    for (final entry in terminal) {
      if (_pending.length < maximumRecords) break;
      _pending.remove(entry.key);
    }
  }
}

final class _PendingCapture {
  _PendingCapture({
    required this.command,
    required this.targetOrigin,
    required this.token,
  });

  final AppAdapterCaptureCommand command;
  final String targetOrigin;
  String token;
  bool uploading = false;
  DateTime? terminalAt;
  AppAdapterCaptureReceipt? receipt;
  String? failureCode;

  bool get isTerminal => receipt != null || failureCode != null;
}

bool _constantTimeEquals(String left, String right) {
  final leftBytes = utf8.encode(left);
  final rightBytes = utf8.encode(right);
  var difference = leftBytes.length ^ rightBytes.length;
  final length = leftBytes.length > rightBytes.length
      ? leftBytes.length
      : rightBytes.length;
  for (var index = 0; index < length; index += 1) {
    final a = index < leftBytes.length ? leftBytes[index] : 0;
    final b = index < rightBytes.length ? rightBytes[index] : 0;
    difference |= a ^ b;
  }
  return difference == 0;
}
