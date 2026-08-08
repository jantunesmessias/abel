import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'studio_bootstrap_transport.dart';
import 'studio_host_client.dart';

final class BrowserStudioHostClient
    implements
        StudioHostClient,
        StudioHostWorkspaceEvents,
        StudioHostPreviewClient,
        StudioHostSessionClient,
        StudioHostGatewayClient,
        StudioHostResourceClient {
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  Uri? _hostOrigin;
  Future<void> _serial = Future<void>.value();
  final Map<String, Completer<Object?>> _pending =
      <String, Completer<Object?>>{};
  final StreamController<void> _workspaceChanges =
      StreamController<void>.broadcast();
  var _nextRequest = 1;
  var _closed = false;
  Set<String> _capabilities = const <String>{};

  @override
  Stream<void> get workspaceChanges => _workspaceChanges.stream;

  @override
  Future<SessionSnapshot> startSession({
    required String launchProfileId,
    required Uri targetOrigin,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('devex.session.start');
    return SessionSnapshot.fromJson(
      await _call('devex.session.start', <String, Object?>{
        'launchProfileId': launchProfileId,
        'targetOrigin': targetOrigin.toString(),
      }),
    );
  });

  @override
  Future<SessionSnapshot> sessionStatus(String sessionId) =>
      _sessionCall('devex.session.get', sessionId);

  @override
  Future<SessionSnapshot> resetSession(String sessionId) =>
      _sessionCall('devex.session.reset', sessionId);

  @override
  Future<SessionSnapshot> stopSession(String sessionId) =>
      _sessionCall('devex.session.stop', sessionId);

  @override
  Future<SessionSnapshot> cancelSession(String sessionId, {String? reason}) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('devex.session.cancel');
        return SessionSnapshot.fromJson(
          await _call('devex.session.cancel', <String, Object?>{
            'sessionId': sessionId,
            'reason': ?reason,
          }),
        );
      });

  @override
  Future<Map<String, Object?>> startGateway({
    required String ownerSessionId,
    required Digest planArtifactDigest,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('devex.gateway.start');
    return _object(
      await _call('devex.gateway.start', <String, Object?>{
        'ownerSessionId': ownerSessionId,
        'planArtifactDigest': planArtifactDigest.value,
      }),
      'GatewaySession',
    );
  });

  @override
  Future<List<GatewayPlanArtifactDescriptor>> gatewayPresets() =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('devex.gateway.presets');
        final value = await _call(
          'devex.gateway.presets',
          const <String, Object?>{},
        );
        if (value is! List<Object?>) {
          throw const FormatException('Gateway presets must be a list');
        }
        return value
            .map(GatewayPlanArtifactDescriptor.fromJson)
            .toList(growable: false);
      });

  @override
  Future<Map<String, Object?>> gatewayStatus(String gatewaySessionId) =>
      _gatewayCall('devex.gateway.status', gatewaySessionId);

  @override
  Future<List<Map<String, Object?>>> gatewayTraffic(
    String gatewaySessionId, {
    int afterSequence = 0,
    int limit = 100,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('devex.gateway.traffic');
    final value = await _call('devex.gateway.traffic', <String, Object?>{
      'gatewaySessionId': gatewaySessionId,
      'afterSequence': afterSequence,
      'limit': limit,
    });
    if (value is! List<Object?> ||
        !value.every((item) => item is Map<String, Object?>)) {
      throw const FormatException('Gateway traffic must be a list of objects');
    }
    return value.cast<Map<String, Object?>>();
  });

  @override
  Future<Map<String, Object?>> resetGateway(String gatewaySessionId) =>
      _gatewayCall('devex.gateway.reset', gatewaySessionId);

  @override
  Future<Map<String, Object?>> stopGateway(String gatewaySessionId) =>
      _gatewayCall('devex.gateway.stop', gatewaySessionId);

  @override
  Future<Map<String, Object?>> collectPreview({
    required String applicationId,
    String? scenarioId,
    String? variantId,
    required bool syntheticDataConfirmed,
  }) => _serialized(() async {
    await _ensureConnected();
    _requireCapability('devex.preview.collect');
    return _object(
      await _call('devex.preview.collect', <String, Object?>{
        'applicationId': applicationId,
        'scenarioId': ?scenarioId,
        'variantId': ?variantId,
        'syntheticDataConfirmed': syntheticDataConfirmed,
      }),
      'PreviewCollectionOperation',
    );
  });

  @override
  Future<Map<String, Object?>> previewStatus(String operationId) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('devex.preview.status');
        return _object(
          await _call('devex.preview.status', <String, Object?>{
            'operationId': operationId,
          }),
          'PreviewCollectionOperation',
        );
      });

  @override
  Future<Map<String, Object?>> cancelPreview(String operationId) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability('devex.preview.cancel');
        return _object(
          await _call('devex.preview.cancel', <String, Object?>{
            'operationId': operationId,
          }),
          'PreviewCollectionOperation',
        );
      });

  @override
  Future<StudioResourceLease> openVisualArtifact(ResourceHandle handle) =>
      _serialized(() async {
        await _ensureConnected();
        final hostOrigin = _hostOrigin!;
        if (handle.purpose != 'visual-artifact' ||
            handle.mediaType != 'image/png' ||
            handle.uri.origin != hostOrigin.origin ||
            handle.size <= 0 ||
            handle.size > 16 * 1024 * 1024 ||
            handle.isExpiredAt(DateTime.now().toUtc())) {
          throw const FormatException(
            'Visual artifact resource handle is not allowed',
          );
        }
        final response = await web.window
            .fetch(
              handle.uri.toString().toJS,
              web.RequestInit(
                method: 'GET',
                cache: 'no-store',
                credentials: 'omit',
                mode: 'cors',
                redirect: 'error',
                referrerPolicy: 'no-referrer',
              ),
            )
            .toDart;
        final declaredLength = int.tryParse(
          response.headers.get('content-length') ?? '',
        );
        if (!response.ok ||
            declaredLength != handle.size ||
            response.headers.get('content-type')?.split(';').first !=
                handle.mediaType) {
          throw StateError('Visual artifact resource response was rejected');
        }
        final arrayBuffer = await response.arrayBuffer().toDart;
        final bytes = arrayBuffer.toDart.asUint8List();
        if (bytes.length != handle.size ||
            Digest.bytes(bytes) != handle.digest ||
            handle.isExpiredAt(DateTime.now().toUtc())) {
          throw const FormatException(
            'Visual artifact resource digest mismatch',
          );
        }
        final blob = web.Blob(
          <JSAny>[arrayBuffer].toJS,
          web.BlobPropertyBag(type: handle.mediaType),
        );
        final localUri = Uri.parse(web.URL.createObjectURL(blob));
        return StudioResourceLease(
          uri: localUri,
          digest: handle.digest,
          mediaType: handle.mediaType,
          size: handle.size,
          releaseCallback: () => web.URL.revokeObjectURL(localUri.toString()),
        );
      });

  @override
  Future<WorkspaceSnapshot> openWorkspace() => _serialized(() async {
    await _ensureConnected();
    return _openCurrentWorkspace();
  });

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() => _serialized(() async {
    await _ensureConnected();
    await _call('devex.workspace.refresh', const <String, Object?>{});
    return _openCurrentWorkspace();
  });

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'Studio disposed');
    _channel = null;
    _failPending(StateError('Studio Host client was closed'));
    await _workspaceChanges.close();
  }

  Future<WorkspaceSnapshot> _openCurrentWorkspace() async {
    final description = _object(
      await _call('devex.workspace.describe', const <String, Object?>{}),
      'WorkspaceDescription',
    );
    final revision = description['revision'];
    final snapshotDigest = description['snapshotDigest'];
    if (revision is! int ||
        revision < 1 ||
        snapshotDigest is! String ||
        snapshotDigest.isEmpty) {
      throw const FormatException('WorkspaceDescription is invalid');
    }
    final opened = _object(
      await _call('devex.workspace.open', <String, Object?>{
        'expectedRevision': revision,
      }),
      'WorkspaceOpen',
    );
    if (opened['revision'] != revision ||
        opened['snapshotDigest'] != snapshotDigest) {
      throw const FormatException('Workspace changed while opening snapshot');
    }
    final handle = ResourceHandle.fromJson(opened['resource']);
    final hostOrigin = _hostOrigin!;
    if (handle.purpose != 'workspace-snapshot' ||
        handle.mediaType != 'application/json' ||
        handle.uri.origin != hostOrigin.origin ||
        handle.size > 16 * 1024 * 1024) {
      throw const FormatException('Workspace resource handle is not allowed');
    }
    final response = await web.window
        .fetch(
          handle.uri.toString().toJS,
          web.RequestInit(
            method: 'GET',
            cache: 'no-store',
            credentials: 'omit',
            mode: 'cors',
            redirect: 'error',
            referrerPolicy: 'no-referrer',
          ),
        )
        .toDart;
    final declaredLength = int.tryParse(
      response.headers.get('content-length') ?? '',
    );
    if (!response.ok ||
        declaredLength != handle.size ||
        response.headers.get('content-type')?.split(';').first !=
            'application/json') {
      throw StateError('Workspace resource response was rejected');
    }
    final body = (await response.text().toDart).toDart;
    final bytes = utf8.encode(body);
    if (bytes.length != handle.size || Digest.bytes(bytes) != handle.digest) {
      throw const FormatException('Workspace resource digest mismatch');
    }
    final snapshot = WorkspaceSnapshot.fromJson(jsonDecode(body));
    if (snapshot.revision != revision ||
        snapshot.digest.value != snapshotDigest) {
      throw const FormatException('Workspace snapshot identity mismatch');
    }
    return snapshot;
  }

  Future<void> _ensureConnected() async {
    if (_closed) throw StateError('Studio Host client is closed');
    if (_channel != null) return;
    const configuredBootstrapUrl = String.fromEnvironment(
      studioBootstrapUrlEnvironmentKey,
    );
    final bootstrapUri = resolveStudioBootstrapUri(configuredBootstrapUrl);
    final externalBootstrap = bootstrapUri.isAbsolute;
    late final web.Response response;
    try {
      response = await web.window
          .fetch(
            bootstrapUri.toString().toJS,
            web.RequestInit(
              method: 'GET',
              cache: 'no-store',
              credentials: externalBootstrap ? 'omit' : 'same-origin',
              mode: externalBootstrap ? 'cors' : 'same-origin',
              redirect: 'error',
              referrerPolicy: 'no-referrer',
            ),
          )
          .toDart;
    } on Object {
      throw const StudioBootstrapException(
        'Não foi possível acessar o bootstrap do DevEx Host. Confirme que '
        '`devex dev` está em execução e tente novamente.',
      );
    }
    final body = (await response.text().toDart).toDart;
    final bootstrap = decodeStudioBootstrapResponse(
      statusCode: response.status,
      contentType: response.headers.get('content-type'),
      body: body,
    );
    final unknown = bootstrap.keys.toSet().difference(const <String>{
      'schemaVersion',
      'protocolVersion',
      'hostOrigin',
      'rpcPath',
      'sessionToken',
      'effectiveKitManifest',
    });
    if (unknown.isNotEmpty ||
        bootstrap['schemaVersion'] != 1 ||
        bootstrap['protocolVersion'] != 1 ||
        bootstrap['rpcPath'] != '/rpc' ||
        bootstrap['hostOrigin'] is! String ||
        bootstrap['sessionToken'] is! String ||
        (bootstrap['sessionToken']! as String).length < 32) {
      throw const FormatException('DevEx Studio bootstrap is invalid');
    }
    EffectiveKitManifest.fromJson(bootstrap['effectiveKitManifest']);
    final hostOrigin = Uri.parse(bootstrap['hostOrigin']! as String);
    if (hostOrigin.scheme != 'http' ||
        hostOrigin.host.isEmpty ||
        hostOrigin.path.isNotEmpty ||
        !_loopbackHost(hostOrigin.host)) {
      throw const FormatException('DevEx Host origin is not loopback HTTP');
    }
    final sessionToken = bootstrap['sessionToken']! as String;
    final rpcUri = hostOrigin.replace(scheme: 'ws', path: '/rpc');
    final channel = WebSocketChannel.connect(rpcUri);
    await channel.ready.timeout(const Duration(seconds: 10));
    _hostOrigin = hostOrigin;
    _channel = channel;
    _subscription = channel.stream.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) =>
          _onDisconnected(error, stackTrace),
      onDone: () => _onDisconnected(
        StateError('DevEx Host closed the connection'),
        StackTrace.current,
      ),
      cancelOnError: true,
    );
    final initialized = _object(
      await _call('devex.initialize', <String, Object?>{
        'protocolVersion': 1,
        'sessionToken': sessionToken,
      }),
      'InitializeResponse',
    );
    final capabilities = initialized['capabilities'];
    if (initialized['protocolVersion'] != 1 ||
        capabilities is! List<Object?> ||
        !capabilities.contains('devex.workspace.describe') ||
        !capabilities.contains('devex.workspace.open')) {
      throw const FormatException('DevEx Host lacks workspace capabilities');
    }
    _capabilities = capabilities.whereType<String>().toSet();
  }

  Future<Object?> _call(String method, Map<String, Object?> params) async {
    final channel = _channel;
    if (channel == null || _subscription == null) {
      throw StateError('DevEx Host connection is not initialized');
    }
    final requestId = 'studio-${_nextRequest++}';
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    channel.sink.add(
      JsonRpcRequest(method: method, id: requestId, params: params).encode(),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      _pending.remove(requestId);
    }
  }

  void _onMessage(Object? raw) {
    if (raw is! String || utf8.encode(raw).length > 64 * 1024) {
      _onDisconnected(
        const FormatException('DevEx Host returned an invalid frame'),
        StackTrace.current,
      );
      return;
    }
    final JsonRpcMessage message;
    try {
      message = const JsonRpcCodec().decode(raw);
    } on Object catch (error, stackTrace) {
      _onDisconnected(error, stackTrace);
      return;
    }
    if (message is JsonRpcResponse) {
      final completer = _pending[message.id];
      if (completer == null || completer.isCompleted) return;
      if (message.isSuccess) {
        completer.complete(message.result);
      } else {
        completer.completeError(
          StateError(
            'Host RPC ${message.error!.code}: ${message.error!.message}',
          ),
        );
      }
      return;
    }
    if (message is JsonRpcNotification &&
        message.method == 'devex.workspace.changed') {
      _workspaceChanges.add(null);
    }
  }

  void _onDisconnected(Object error, StackTrace stackTrace) {
    if (_closed || _channel == null) return;
    _channel = null;
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    _failPending(error, stackTrace);
    _workspaceChanges.addError(error, stackTrace);
  }

  void _failPending(Object error, [StackTrace? stackTrace]) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace ?? StackTrace.current);
      }
    }
    _pending.clear();
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<SessionSnapshot> _sessionCall(String method, String sessionId) =>
      _serialized(() async {
        await _ensureConnected();
        _requireCapability(method);
        return SessionSnapshot.fromJson(
          await _call(method, <String, Object?>{'sessionId': sessionId}),
        );
      });

  Future<Map<String, Object?>> _gatewayCall(
    String method,
    String gatewaySessionId,
  ) => _serialized(() async {
    await _ensureConnected();
    _requireCapability(method);
    return _object(
      await _call(method, <String, Object?>{
        'gatewaySessionId': gatewaySessionId,
      }),
      'GatewaySession',
    );
  });

  Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }

  bool _loopbackHost(String host) =>
      host == '127.0.0.1' || host == '::1' || host == 'localhost';

  void _requireCapability(String method) {
    if (!_capabilities.contains(method)) {
      throw StateError('Host capability is unavailable: $method');
    }
  }
}
