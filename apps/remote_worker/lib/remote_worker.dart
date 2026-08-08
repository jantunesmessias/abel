import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';

final class RemoteWorkerHttpClient
    implements RemoteWorkerArtifactClient, RemoteWorkerControlClient {
  RemoteWorkerHttpClient({
    required this.controlOrigin,
    required this.artifactOrigin,
    required this._capabilityToken,
    this.allowInsecureLoopback = false,
    HttpClient? client,
  }) : _client = client ?? HttpClient() {
    for (final origin in <Uri>[controlOrigin, artifactOrigin]) {
      final loopback =
          origin.host == '127.0.0.1' ||
          origin.host == '::1' ||
          origin.host == 'localhost';
      if ((origin.scheme != 'https' && !(allowInsecureLoopback && loopback)) ||
          origin.origin == 'null') {
        throw ArgumentError('remote worker endpoints must use HTTPS');
      }
    }
  }

  static const int _maximumControlResponseBytes = 1024 * 1024;
  final Uri controlOrigin;
  final Uri artifactOrigin;
  final bool allowInsecureLoopback;
  final HttpClient _client;
  String _capabilityToken;

  @override
  Future<File> download({
    required VerifiedRemoteCapability capability,
    required RemoteArtifactInput artifact,
    required Directory destination,
  }) async {
    final response =
        await _post(capability, 'artifacts/download-grant', <String, Object?>{
          'digest': artifact.digest.value,
          'size': artifact.size,
          'mediaType': artifact.mediaType,
        });
    final transfer = _transfer(response, expectedMethod: 'GET');
    final descriptor = HostedBlobDescriptor.fromJson(transfer['descriptor']);
    if (descriptor.tenantId != capability.tenantId ||
        descriptor.digest != artifact.digest ||
        descriptor.size != artifact.size ||
        descriptor.mediaType != artifact.mediaType) {
      throw StateError('download grant differs from the signed artifact');
    }
    final uri = _transferUri(transfer);
    final request = await _client.getUrl(uri);
    request
      ..followRedirects = false
      ..maxRedirects = 0;
    _headers(request, transfer['requiredHeaders']);
    final downloaded = await request.close().timeout(
      const Duration(seconds: 30),
    );
    if (downloaded.statusCode != HttpStatus.ok ||
        downloaded.isRedirect ||
        downloaded.contentLength > artifact.size) {
      await downloaded.drain<void>();
      throw HttpException('artifact download was rejected', uri: uri);
    }
    final partial = File(
      '${destination.path}/.${artifact.digest.value.substring(7)}.partial',
    );
    final output = partial.openWrite();
    var size = 0;
    try {
      await for (final chunk in downloaded) {
        size += chunk.length;
        if (size > artifact.size) {
          throw StateError('artifact download exceeded its signed size');
        }
        output.add(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (size != artifact.size) {
      if (partial.existsSync()) partial.deleteSync();
      throw StateError('artifact download is truncated');
    }
    final file = File(
      '${destination.path}/artifact-${artifact.digest.value.substring(7)}',
    );
    partial.renameSync(file.path);
    return file;
  }

  @override
  Future<HostedBlobDescriptor> upload({
    required VerifiedRemoteCapability capability,
    required RemoteGeneratedArtifact artifact,
  }) async {
    final bytes = artifact.file.readAsBytesSync();
    final digest = Digest.bytes(bytes);
    final response =
        await _post(capability, 'artifacts/upload-grant', <String, Object?>{
          'digest': digest.value,
          'size': bytes.length,
          'mediaType': artifact.mediaType,
          'classification': artifact.classification,
        });
    final transfer = _transfer(response, expectedMethod: 'PUT');
    final descriptor = HostedBlobDescriptor.fromJson(transfer['descriptor']);
    if (descriptor.tenantId != capability.tenantId ||
        descriptor.digest != digest ||
        descriptor.size != bytes.length ||
        descriptor.mediaType != artifact.mediaType ||
        descriptor.classification != artifact.classification) {
      throw StateError('upload grant differs from the generated artifact');
    }
    final uri = _transferUri(transfer);
    final request = await _client.putUrl(uri);
    request
      ..followRedirects = false
      ..maxRedirects = 0
      ..contentLength = bytes.length;
    _headers(request, transfer['requiredHeaders']);
    request.add(bytes);
    final uploaded = await request.close().timeout(const Duration(minutes: 5));
    if (uploaded.statusCode < 200 ||
        uploaded.statusCode >= 300 ||
        uploaded.isRedirect) {
      await uploaded.drain<void>();
      throw HttpException('artifact upload was rejected', uri: uri);
    }
    await uploaded.drain<void>();
    return descriptor;
  }

  @override
  Future<void> state({
    required VerifiedRemoteCapability capability,
    required RemoteRunState state,
    String? failureCode,
  }) async {
    await _post(capability, 'state', <String, Object?>{
      'state': state.name,
      'failureCode': ?failureCode,
    });
  }

  @override
  Future<RemoteWorkerHeartbeat> heartbeat(
    VerifiedRemoteCapability capability,
  ) async {
    final response = await _post(
      capability,
      'heartbeat',
      const <String, Object?>{},
    );
    final token = response['capabilityToken'];
    if (token is! String || token.isEmpty || token.length > 16384) {
      throw StateError('control plane returned an invalid renewed capability');
    }
    _capabilityToken = token;
    return RemoteWorkerHeartbeat(renewedCapabilityToken: token);
  }

  @override
  Future<void> complete({
    required VerifiedRemoteCapability capability,
    required RemoteArtifactManifest artifacts,
    required RemoteContainmentReport containment,
    required RemoteInteractiveTransport interactiveTransport,
  }) async {
    await _post(capability, 'complete', <String, Object?>{
      'artifacts': artifacts.toJson(),
      'containment': containment.toJson(),
      'interactiveTransport': interactiveTransport.name,
    });
  }

  Future<Map<String, Object?>> _post(
    VerifiedRemoteCapability capability,
    String operation,
    Map<String, Object?> body,
  ) async {
    final path = <String>[
      'v1',
      'remote',
      'tenants',
      capability.tenantId,
      'workers',
      capability.workerId,
      'runs',
      capability.runId,
      ...operation.split('/'),
    ].map(Uri.encodeComponent).join('/');
    final uri = controlOrigin.resolve('/$path');
    final request = await _client.postUrl(uri);
    request
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $_capabilityToken')
      ..write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = await _bounded(response, _maximumControlResponseBytes);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.isRedirect) {
      throw HttpException(
        'control plane rejected $operation with ${response.statusCode}',
        uri: uri,
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<Object?, Object?>) {
      throw StateError('control plane response is not a JSON object');
    }
    final json = decoded.cast<String, Object?>();
    if (json['ok'] != true) {
      throw StateError('control plane response is not successful');
    }
    return json;
  }

  Map<String, Object?> _transfer(
    Map<String, Object?> response, {
    required String expectedMethod,
  }) {
    final value = response['transfer'];
    if (value is! Map<Object?, Object?>) {
      throw StateError('object transfer grant is absent');
    }
    final transfer = value.cast<String, Object?>();
    final expiresAt = DateTime.tryParse('${transfer['expiresAt']}');
    if (transfer['method'] != expectedMethod ||
        expiresAt == null ||
        !expiresAt.isUtc ||
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw StateError('object transfer grant is invalid or expired');
    }
    return transfer;
  }

  Uri _transferUri(Map<String, Object?> transfer) {
    final uri = Uri.tryParse('${transfer['url']}');
    if (uri == null ||
        (uri.scheme != 'https' && !allowInsecureLoopback) ||
        uri.origin != artifactOrigin.origin ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw StateError('object transfer URL escaped the configured origin');
    }
    return uri;
  }

  void _headers(HttpClientRequest request, Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw StateError('object transfer headers are invalid');
    }
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw StateError('object transfer header is invalid');
      }
      final name = entry.key! as String;
      if (const <String>{
        'authorization',
        'cookie',
        'host',
        'content-length',
      }.contains(name.toLowerCase())) {
        throw StateError('object transfer attempted a forbidden header');
      }
      request.headers.set(name, entry.value! as String);
    }
  }

  Future<List<int>> _bounded(HttpClientResponse response, int maximum) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > maximum) {
        throw StateError('control plane response exceeded its size limit');
      }
    }
    return bytes;
  }

  void close() => _client.close(force: true);
}

final class LoopbackRemoteWorkerStreamClient
    implements RemoteWorkerStreamClient {
  LoopbackRemoteWorkerStreamClient(this.endpoint) {
    final loopback =
        endpoint.host == '127.0.0.1' ||
        endpoint.host == '::1' ||
        endpoint.host == 'localhost';
    if (endpoint.scheme != 'ws' ||
        !endpoint.hasAuthority ||
        !loopback ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.query.isNotEmpty ||
        endpoint.fragment.isNotEmpty) {
      throw ArgumentError(
        'worker stream endpoint must be an uncredentialed loopback WebSocket',
      );
    }
  }

  final Uri endpoint;
  final StreamController<RemoteStreamFrame> _controls =
      StreamController<RemoteStreamFrame>();
  final Completer<void> _done = Completer<void>();
  WebSocket? _socket;

  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _subscription;
  Completer<void>? _authentication;
  Completer<void>? _reauthentication;
  int _sequence = 0;
  bool _closed = false;

  @override
  Stream<RemoteStreamFrame> get controlFrames => _controls.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> connect(String capabilityToken) async {
    _token(capabilityToken);
    if (_socket != null || _closed) {
      throw StateError('worker stream client is already used');
    }
    final socket = await WebSocket.connect(
      endpoint.toString(),
      protocols: const <String>[RemoteSessionGrant.protocol],
    ).timeout(const Duration(seconds: 10));
    if (socket.protocol != RemoteSessionGrant.protocol) {
      await socket.close(1002, 'session subprotocol was not negotiated');
      throw StateError('remote session subprotocol was not negotiated');
    }
    _socket = socket;
    _authentication = Completer<void>();
    _subscription = socket.listen(
      _message,
      onError: (Object error, StackTrace stackTrace) {
        _finish(error, stackTrace);
      },
      onDone: _finish,
      cancelOnError: true,
    );
    socket.add(
      jsonEncode(<String, Object?>{
        'type': 'authenticate',
        'token': capabilityToken,
      }),
    );
    await _authentication!.future.timeout(const Duration(seconds: 5));
  }

  @override
  Future<void> reauthenticate(String capabilityToken) async {
    _token(capabilityToken);
    final socket = _socket;
    if (socket == null || _closed || _authentication?.isCompleted != true) {
      throw StateError('worker stream is not connected');
    }
    if (_reauthentication != null && !_reauthentication!.isCompleted) {
      throw StateError('worker stream reauthentication is already in flight');
    }
    _reauthentication = Completer<void>();
    socket.add(
      jsonEncode(<String, Object?>{
        'type': 'reauthenticate',
        'token': capabilityToken,
      }),
    );
    await _reauthentication!.future.timeout(const Duration(seconds: 5));
  }

  @override
  Future<void> publish(RemoteStreamChannel channel, List<int> payload) async {
    if (!const <RemoteStreamChannel>{
      RemoteStreamChannel.videoH264,
      RemoteStreamChannel.screenshotPng,
      RemoteStreamChannel.metadataJson,
    }.contains(channel)) {
      throw ArgumentError('worker cannot publish the control channel');
    }
    final socket = _socket;
    if (socket == null || _closed || _authentication?.isCompleted != true) {
      throw StateError('worker stream is not connected');
    }
    socket.add(
      RemoteStreamFrameCodec.encode(
        RemoteStreamFrame(
          channel: channel,
          sequence: ++_sequence,
          payload: payload,
        ),
      ),
    );
  }

  void _message(Object? message) {
    if (_closed) return;
    if (message is String) {
      if (message.length > 65536) {
        unawaited(_fail('remote session metadata is oversized'));
        return;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(message);
      } on FormatException {
        unawaited(_fail('remote session metadata is invalid'));
        return;
      }
      if (decoded is! Map<String, Object?> || decoded['type'] is! String) {
        unawaited(_fail('remote session metadata is invalid'));
        return;
      }
      switch (decoded['type']) {
        case 'authenticated':
          if (_authentication == null || _authentication!.isCompleted) {
            unawaited(_fail('duplicate remote stream authentication'));
          } else {
            _authentication!.complete();
          }
        case 'reauthenticated':
          final current = _reauthentication;
          if (current == null || current.isCompleted) {
            unawaited(_fail('unexpected remote stream reauthentication'));
          } else {
            current.complete();
          }
        case 'session.ready':
          break;
        default:
          unawaited(_fail('unknown remote session metadata'));
      }
      return;
    }
    if (message is! List<int>) {
      unawaited(_fail('remote session frame type is invalid'));
      return;
    }
    try {
      final frame = RemoteStreamFrameCodec.decode(message);
      if (frame.channel != RemoteStreamChannel.control) {
        throw const RemoteStreamProtocolException(
          'worker received a non-control binary frame',
        );
      }
      _controls.add(frame);
    } on RemoteStreamProtocolException {
      unawaited(_fail('remote session frame is invalid'));
    }
  }

  void _finish([Object? error, StackTrace? stackTrace]) {
    if (_done.isCompleted) return;
    _closed = true;
    if (error == null) {
      _done.complete();
    } else {
      _done.completeError(error, stackTrace);
    }
  }

  Future<void> _fail(String reason) async {
    if (_closed) return;
    final socket = _socket;
    if (socket != null) unawaited(socket.close(1002, reason));
    _finish(StateError(reason), StackTrace.current);
  }

  void _token(String value) {
    if (value.isEmpty || value.length > 16384) {
      throw ArgumentError('remote stream capability is invalid');
    }
  }

  @override
  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      final socket = _socket;
      _socket = null;
      if (socket != null) {
        unawaited(socket.close(1000, 'worker stream complete'));
      }
      if (!_done.isCompleted) _done.complete();
    }
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (!_controls.isClosed) unawaited(_controls.close());
  }
}
