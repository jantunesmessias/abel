import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:web/web.dart' as web;

import 'app_adapter.dart';
import 'app_adapter_bridge.dart';
import 'app_adapter_capture_uploader.dart';
import 'app_adapter_relay.dart';
import 'target_binding.dart';

AppAdapterBridge startBridge({
  required TargetBinding binding,
  required AppAdapter adapter,
  AppAdapterRelay? relay,
}) {
  final controllerOrigin = binding.controllerOrigin;
  if (controllerOrigin == null) {
    throw StateError('Web App Adapter requires an exact controllerOrigin');
  }
  return _WebAppAdapterBridge(
    binding: binding,
    adapter: adapter,
    controllerOrigin: controllerOrigin,
    relay: relay,
  );
}

final class _WebAppAdapterBridge implements AppAdapterBridge {
  _WebAppAdapterBridge({
    required this.binding,
    required this.adapter,
    required this.controllerOrigin,
    required this.relay,
  }) {
    final activeRelay = relay;
    if (activeRelay != null &&
        (!identical(activeRelay.adapter, adapter) ||
            activeRelay.sessionId != binding.sessionId ||
            activeRelay.hello.nonce.value != binding.nonce)) {
      throw ArgumentError(
        'App Adapter relay does not bind this target instance',
      );
    }
    _listener = _onMessage.toJS;
    web.window.addEventListener('message', _listener);
    if (activeRelay != null) {
      scheduleMicrotask(() {
        if (!_disposed) _send(activeRelay.hello.toJson());
      });
    }
  }

  final TargetBinding binding;
  final AppAdapter adapter;
  final Uri controllerOrigin;
  final AppAdapterRelay? relay;
  final AppAdapterCaptureUploader _uploader = AppAdapterCaptureUploader();
  final Set<String> _activeRequests = <String>{};
  late final JSFunction _listener;
  var _lastInboundSequence = 0;
  var _outboundSequence = 0;
  var _disposed = false;

  void _onMessage(web.Event rawEvent) {
    final event = rawEvent as web.MessageEvent;
    final data = event.data;
    if (data == null || !data.isA<JSString>()) return;
    final Object? decoded;
    try {
      decoded = jsonDecode((data as JSString).toDart);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    try {
      final envelope = PostMessageEnvelope.decodeAndAuthorize(
        decoded,
        eventOrigin: Uri.parse(event.origin),
        expectedOrigin: controllerOrigin,
        // JS WindowProxy equality must not invoke Dart's operator dispatch:
        // reading dispatch metadata from a cross-origin parent is forbidden.
        sourceMatches: identical(event.source, web.window.parent),
        expectedSessionId: binding.sessionId,
        expectedNonce: binding.nonce,
        minimumSequence: _lastInboundSequence,
      );
      if (envelope.payload['kind'] == 'AppAdapterRelayCommand') {
        final activeRelay = relay;
        if (activeRelay == null) return;
        final command = AppAdapterRelayCommand.fromJson(envelope.payload);
        _lastInboundSequence = envelope.sequence;
        unawaited(_executeRelay(activeRelay, command));
        return;
      }
      final command = AppAdapterCaptureCommand.fromJson(envelope.payload);
      if (command.sessionId != binding.sessionId ||
          !binding.capabilities.contains('capture.png') ||
          !_activeRequests.add(command.requestId)) {
        return;
      }
      _lastInboundSequence = envelope.sequence;
      unawaited(_capture(command));
    } on FormatException {
      return;
    }
  }

  Future<void> _executeRelay(
    AppAdapterRelay activeRelay,
    AppAdapterRelayCommand command,
  ) async {
    try {
      final result = await activeRelay.execute(command);
      if (!_disposed) _send(result.toJson());
    } on Object {
      // Strict decoding and the relay state machine fail closed. No adjacent
      // result is synthesized when the local instance has already shut down.
    }
  }

  Future<void> _capture(AppAdapterCaptureCommand command) async {
    try {
      final result = await _uploader.upload(command: command, adapter: adapter);
      _activeRequests.remove(command.requestId);
      _send(<String, Object?>{
        'schemaVersion': 1,
        'kind': 'AppAdapterCaptureResult',
        'requestId': command.requestId,
        'sessionId': binding.sessionId,
        'ok': result.ok,
        'code': result.code,
      });
    } on Object {
      _activeRequests.remove(command.requestId);
      _send(<String, Object?>{
        'schemaVersion': 1,
        'kind': 'AppAdapterCaptureResult',
        'requestId': command.requestId,
        'sessionId': binding.sessionId,
        'ok': false,
        'code': 'capture_failed',
      });
    }
  }

  void _send(Map<String, Object?> payload) {
    final parent = web.window.parent;
    parent?.postMessage(
      jsonEncode(
        PostMessageEnvelope(
          protocolVersion: 1,
          sessionId: binding.sessionId,
          nonce: binding.nonce,
          sequence: ++_outboundSequence,
          payload: payload,
        ).toJson(),
      ).toJS,
      controllerOrigin.origin.toJS,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    web.window.removeEventListener('message', _listener);
    _activeRequests.clear();
    _uploader.close();
    relay?.dispose();
  }
}
