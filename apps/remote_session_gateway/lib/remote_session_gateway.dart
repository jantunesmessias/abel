import 'dart:async';
import 'dart:convert';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'src/remote_web_target_proxy.dart';

enum RemoteSessionEndpointRole { worker, viewer }

final class RemoteSessionGatewayApplication {
  RemoteSessionGatewayApplication({
    required RemoteWorkerTokenVerifier verifier,
    required this.expectedRunId,
    required Set<String> allowedViewerOrigins,
    required DateTime sessionDeadline,
    required Clock clock,
    Uri? webTargetOrigin,
    IdGenerator? ids,
  }) : _allowedViewerOrigins = Set<String>.unmodifiable(allowedViewerOrigins) {
    if (_allowedViewerOrigins.isEmpty ||
        _allowedViewerOrigins.any((origin) {
          final uri = Uri.tryParse(origin);
          return uri == null || uri.scheme != 'https' || uri.origin != origin;
        })) {
      throw ArgumentError('viewer origins must be exact HTTPS origins');
    }
    _webTarget = webTargetOrigin == null
        ? null
        : RemoteWebTargetProxy(
            runId: expectedRunId,
            targetOrigin: webTargetOrigin,
            allowedViewerOrigins: _allowedViewerOrigins,
            sessionDeadline: sessionDeadline,
            clock: clock,
            ids: ids ?? SecureIdGenerator(),
          );
    relay = RemoteSessionRelay(
      verifier: verifier,
      expectedRunId: expectedRunId,
      sessionDeadline: sessionDeadline,
      clock: clock,
      webTarget: _webTarget,
    );
  }

  final String expectedRunId;
  final Set<String> _allowedViewerOrigins;
  late final RemoteWebTargetProxy? _webTarget;
  late final RemoteSessionRelay relay;

  Handler get handler {
    final router = Router()
      ..get('/healthz', (_) => Response.ok('ok'))
      ..options('/v1/sessions/<runId>/web/bootstrap', _webPreflight)
      ..post('/v1/sessions/<runId>/web/bootstrap', _webBootstrap)
      ..get('/v1/sessions/<runId>/web/target/', _webTargetRoot)
      ..get('/v1/sessions/<runId>/web/target/<path|.*>', _webTargetPath)
      ..add('HEAD', '/v1/sessions/<runId>/web/target/', _webTargetRoot)
      ..add('HEAD', '/v1/sessions/<runId>/web/target/<path|.*>', _webTargetPath)
      ..get('/v1/sessions/<runId>/<role>', _upgrade)
      ..all('/<ignored|.*>', (_, _) => Response.notFound('not found'));
    return router.call;
  }

  FutureOr<Response> _upgrade(Request request, String runId, String roleName) {
    if (runId != expectedRunId) return Response.notFound('not found');
    final role = RemoteSessionEndpointRole.values
        .where((candidate) => candidate.name == roleName)
        .firstOrNull;
    if (role == null) return Response.notFound('not found');
    final origin = request.headers['origin'];
    if (role == RemoteSessionEndpointRole.viewer) {
      if (origin == null || !_allowedViewerOrigins.contains(origin)) {
        return Response.forbidden('viewer origin is not allowed');
      }
    } else if (origin != null) {
      return Response.forbidden(
        'worker connections cannot be browser-originated',
      );
    }
    return webSocketHandler(
      (channel, _) => relay.accept(channel, role),
      protocols: const <String>[RemoteSessionGrant.protocol],
      pingInterval: const Duration(seconds: 20),
    )(request);
  }

  Response _webPreflight(Request request, String runId) {
    final target = _webTarget;
    if (runId != expectedRunId || target == null) {
      return Response.notFound('not found');
    }
    return target.preflight(request);
  }

  Future<Response> _webBootstrap(Request request, String runId) async {
    final target = _webTarget;
    if (runId != expectedRunId || target == null) {
      return Response.notFound('not found');
    }
    return target.bootstrap(request);
  }

  Future<Response> _webTargetRoot(Request request, String runId) =>
      _webTargetPath(request, runId, '');

  Future<Response> _webTargetPath(
    Request request,
    String runId,
    String path,
  ) async {
    final target = _webTarget;
    if (runId != expectedRunId || target == null) {
      return Response.notFound('not found');
    }
    return target.proxy(request, path);
  }

  Future<void> close() async {
    await relay.close();
    _webTarget?.close();
  }
}

final class RemoteSessionRelay {
  RemoteSessionRelay({
    required this.verifier,
    required this.expectedRunId,
    required this.sessionDeadline,
    required this.clock,
    this.webTarget,
    this.authenticationTimeout = const Duration(seconds: 5),
  }) {
    if (!sessionDeadline.isUtc ||
        !sessionDeadline.isAfter(clock.nowUtc()) ||
        sessionDeadline.difference(clock.nowUtc()) > const Duration(hours: 1) ||
        authenticationTimeout <= Duration.zero) {
      throw ArgumentError('remote session relay lifetime is invalid');
    }
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_serialize(_enforceExpiry));
    });
  }

  final RemoteWorkerTokenVerifier verifier;
  final String expectedRunId;
  final DateTime sessionDeadline;
  final Clock clock;
  final RemoteWebTargetProxy? webTarget;
  final Duration authenticationTimeout;
  final Set<String> _usedViewerNonces = <String>{};
  Future<void> _tail = Future<void>.value();
  late final Timer _expiryTimer;
  _RemoteSessionPeer? _worker;
  _RemoteSessionPeer? _viewer;
  bool _closed = false;

  void accept(WebSocketChannel channel, RemoteSessionEndpointRole role) {
    if (_closed || !sessionDeadline.isAfter(clock.nowUtc())) {
      unawaited(channel.sink.close(4408, 'session expired'));
      return;
    }
    final peer = _RemoteSessionPeer(channel: channel, role: role);
    peer.authenticationTimer = Timer(authenticationTimeout, () {
      unawaited(
        _serialize(() => _reject(peer, 4401, 'authentication timeout')),
      );
    });
    peer.subscription = channel.stream.listen(
      (message) => unawaited(_serialize(() => _message(peer, message))),
      onError: (_) => unawaited(_serialize(() => _disconnected(peer))),
      onDone: () => unawaited(_serialize(() => _disconnected(peer))),
      cancelOnError: true,
    );
  }

  Future<void> _message(_RemoteSessionPeer peer, Object? message) async {
    if (_closed || peer.closed) return;
    if (!peer.authenticated) {
      await _authenticate(peer, message);
      return;
    }
    if (message is String) {
      await _text(peer, message);
      return;
    }
    if (message is! List<int>) {
      await _reject(peer, 1003, 'unsupported frame type');
      return;
    }
    final RemoteStreamFrame frame;
    try {
      frame = RemoteStreamFrameCodec.decode(message);
    } on RemoteStreamProtocolException {
      await _reject(peer, 1002, 'invalid binary frame');
      return;
    }
    if (frame.sequence != peer.lastSequence + 1) {
      await _reject(peer, 1008, 'non-monotonic frame sequence');
      return;
    }
    final allowed = switch (peer.role) {
      RemoteSessionEndpointRole.worker => const <RemoteStreamChannel>{
        RemoteStreamChannel.videoH264,
        RemoteStreamChannel.screenshotPng,
        RemoteStreamChannel.metadataJson,
      },
      RemoteSessionEndpointRole.viewer => const <RemoteStreamChannel>{
        RemoteStreamChannel.control,
      },
    };
    if (!allowed.contains(frame.channel)) {
      await _reject(peer, 1008, 'stream direction is not allowed');
      return;
    }
    peer.lastSequence = frame.sequence;
    final destination = peer.role == RemoteSessionEndpointRole.worker
        ? _viewer
        : _worker;
    if (destination != null && !destination.closed) {
      destination.channel.sink.add(RemoteStreamFrameCodec.encode(frame));
    }
  }

  Future<void> _authenticate(_RemoteSessionPeer peer, Object? message) async {
    final json = _authenticationMessage(message, expectedType: 'authenticate');
    if (json == null) {
      await _reject(peer, 4401, 'authentication message is invalid');
      return;
    }
    final token = json['token']! as String;
    try {
      switch (peer.role) {
        case RemoteSessionEndpointRole.worker:
          final credential = await verifier.verifyStreamWriter(
            token,
            runId: expectedRunId,
          );
          if (_worker != null && !_worker!.closed) {
            await _reject(peer, 4409, 'worker is already connected');
            return;
          }
          final viewer = _viewer;
          if (viewer != null && viewer.tenantId != credential.tenantId) {
            await _reject(peer, 4403, 'tenant binding differs');
            return;
          }
          peer
            ..tenantId = credential.tenantId
            ..principalId = credential.workerId
            ..tokenId = credential.tokenId
            ..generation = credential.generation
            ..credentialExpiresAt = credential.expiresAt;
          _worker = peer;
        case RemoteSessionEndpointRole.viewer:
          final ticket = await verifier.verifyViewerTicket(
            token,
            runId: expectedRunId,
          );
          if (_viewer != null && !_viewer!.closed) {
            await _reject(peer, 4409, 'target already has an exclusive viewer');
            return;
          }
          if (_usedViewerNonces.contains(ticket.nonce)) {
            await _reject(peer, 4409, 'viewer ticket was already consumed');
            return;
          }
          final worker = _worker;
          if (worker != null && worker.tenantId != ticket.tenantId) {
            await _reject(peer, 4403, 'tenant binding differs');
            return;
          }
          _usedViewerNonces.add(ticket.nonce);
          peer
            ..tenantId = ticket.tenantId
            ..principalId = ticket.principalId
            ..tokenId = ticket.nonce
            ..generation = 1
            ..credentialExpiresAt = ticket.expiresAt
            ..viewerTicket = ticket;
          _viewer = peer;
      }
    } on Object {
      await _reject(peer, 4401, 'authentication failed');
      return;
    }
    peer
      ..authenticated = true
      ..authenticationTimer?.cancel();
    peer.channel.sink.add(
      jsonEncode(<String, Object?>{
        'type': 'authenticated',
        'role': peer.role.name,
        'runId': expectedRunId,
        'sessionDeadline': sessionDeadline.toIso8601String(),
      }),
    );
    _notifyReady();
  }

  Future<void> _text(_RemoteSessionPeer peer, String message) async {
    if (peer.role != RemoteSessionEndpointRole.worker) {
      await _reject(peer, 1008, 'viewer text messages are not allowed');
      return;
    }
    final json = _authenticationMessage(
      message,
      expectedType: 'reauthenticate',
    );
    if (json == null) {
      await _reject(peer, 1008, 'worker reauthentication is invalid');
      return;
    }
    try {
      final credential = await verifier.verifyStreamWriter(
        json['token']! as String,
        runId: expectedRunId,
      );
      if (credential.tenantId != peer.tenantId ||
          credential.workerId != peer.principalId ||
          credential.tokenId != peer.tokenId ||
          credential.generation != peer.generation ||
          !credential.expiresAt.isAfter(clock.nowUtc())) {
        throw const RemoteStateException('stream lease fencing changed');
      }
      peer.credentialExpiresAt = credential.expiresAt;
      peer.channel.sink.add(
        jsonEncode(<String, Object?>{
          'type': 'reauthenticated',
          'expiresAt': credential.expiresAt.toIso8601String(),
        }),
      );
    } on Object {
      await _reject(peer, 4401, 'worker reauthentication failed');
    }
  }

  Map<String, Object?>? _authenticationMessage(
    Object? message, {
    required String expectedType,
  }) {
    if (message is! String || message.length > 20000) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?> ||
        decoded.keys.toSet().difference(const <String>{
          'type',
          'token',
        }).isNotEmpty ||
        decoded['type'] != expectedType ||
        decoded['token'] is! String ||
        (decoded['token']! as String).isEmpty ||
        (decoded['token']! as String).length > 16384) {
      return null;
    }
    return decoded;
  }

  void _notifyReady() {
    final worker = _worker;
    final viewer = _viewer;
    if (worker == null || viewer == null || worker.closed || viewer.closed) {
      return;
    }
    final message = jsonEncode(<String, Object?>{
      'type': 'session.ready',
      'runId': expectedRunId,
    });
    worker.channel.sink.add(message);
    viewer.channel.sink.add(message);
    final target = webTarget;
    final ticket = viewer.viewerTicket;
    if (target != null && ticket != null && !viewer.bootstrapIssued) {
      viewer.bootstrapIssued = true;
      viewer.channel.sink.add(
        jsonEncode(target.issueBootstrap(ticket).toJson()),
      );
    }
  }

  Future<void> _enforceExpiry() async {
    if (_closed) return;
    final now = clock.nowUtc();
    if (!sessionDeadline.isAfter(now)) {
      await close(code: 4408, reason: 'session expired');
      return;
    }
    final worker = _worker;
    if (worker != null &&
        worker.credentialExpiresAt != null &&
        !worker.credentialExpiresAt!.isAfter(now)) {
      await _reject(worker, 4401, 'worker capability expired');
      final viewer = _viewer;
      if (viewer != null) {
        await _reject(viewer, 1011, 'worker capability expired');
      }
    }
  }

  Future<void> _disconnected(_RemoteSessionPeer peer) async {
    if (peer.closed) return;
    peer
      ..closed = true
      ..authenticationTimer?.cancel();
    unawaited(peer.cancelSubscription());
    if (identical(_viewer, peer)) _viewer = null;
    if (peer.role == RemoteSessionEndpointRole.viewer && peer.tokenId != null) {
      webTarget?.revoke(peer.tokenId!);
    }
    if (identical(_worker, peer)) {
      _worker = null;
      final viewer = _viewer;
      if (viewer != null) {
        await _reject(viewer, 1011, 'worker disconnected');
      }
    }
  }

  Future<void> _reject(_RemoteSessionPeer peer, int code, String reason) async {
    if (peer.closed) return;
    peer
      ..closed = true
      ..authenticationTimer?.cancel();
    if (identical(_worker, peer)) _worker = null;
    if (identical(_viewer, peer)) _viewer = null;
    if (peer.role == RemoteSessionEndpointRole.viewer && peer.tokenId != null) {
      webTarget?.revoke(peer.tokenId!);
    }
    final closing = peer.channel.sink.close(code, reason);
    unawaited(peer.cancelSubscription());
    await closing;
  }

  Future<void> _serialize(FutureOr<void> Function() operation) {
    final scheduled = _tail.then((_) => operation());
    _tail = scheduled.catchError((Object _) async {
      await close(code: 1011, reason: 'gateway operation failed');
    });
    return _tail;
  }

  Future<void> close({
    int code = 1001,
    String reason = 'gateway stopping',
  }) async {
    if (_closed) return;
    _closed = true;
    _expiryTimer.cancel();
    final peers = <_RemoteSessionPeer>{?_worker, ?_viewer};
    _worker = null;
    _viewer = null;
    for (final peer in peers) {
      await _reject(peer, code, reason);
    }
  }
}

final class _RemoteSessionPeer {
  _RemoteSessionPeer({required this.channel, required this.role});

  final WebSocketChannel channel;
  final RemoteSessionEndpointRole role;
  // The relay owns this subscription and cancels it through
  // [cancelSubscription] on reject, disconnect, expiry, and shutdown.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? subscription;
  Timer? authenticationTimer;
  bool authenticated = false;
  bool closed = false;
  int lastSequence = 0;
  String? tenantId;
  String? principalId;
  String? tokenId;
  int? generation;
  DateTime? credentialExpiresAt;
  RemoteSessionTicket? viewerTicket;
  bool bootstrapIssued = false;

  Future<void> cancelSubscription() async {
    final current = subscription;
    subscription = null;
    await current?.cancel();
  }
}
