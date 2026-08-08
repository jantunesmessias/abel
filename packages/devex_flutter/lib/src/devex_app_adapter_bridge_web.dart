import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:web/web.dart' as web;

import 'devex_app_adapter.dart';
import 'devex_app_adapter_bridge.dart';
import 'devex_app_adapter_capture_uploader.dart';
import 'devex_flutter_binding.dart';

DevExAppAdapterBridge startBridge({
  required DevExFlutterBinding binding,
  required DevExAppAdapter adapter,
}) {
  final controllerOrigin = binding.controllerOrigin;
  if (controllerOrigin == null) {
    throw StateError('Web App Adapter requires an exact controllerOrigin');
  }
  return _WebAppAdapterBridge(
    binding: binding,
    adapter: adapter,
    controllerOrigin: controllerOrigin,
  );
}

final class _WebAppAdapterBridge implements DevExAppAdapterBridge {
  _WebAppAdapterBridge({
    required this.binding,
    required this.adapter,
    required this.controllerOrigin,
  }) {
    _listener = _onMessage.toJS;
    web.window.addEventListener('message', _listener);
  }

  final DevExFlutterBinding binding;
  final DevExAppAdapter adapter;
  final Uri controllerOrigin;
  final DevExAppAdapterCaptureUploader _uploader =
      DevExAppAdapterCaptureUploader();
  final Set<String> _activeRequests = <String>{};
  late final JSFunction _listener;
  var _lastInboundSequence = 0;
  var _outboundSequence = 0;

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
        sourceMatches: event.source == web.window.parent,
        expectedSessionId: binding.sessionId,
        expectedNonce: binding.nonce,
        minimumSequence: _lastInboundSequence,
      );
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
    web.window.removeEventListener('message', _listener);
    _activeRequests.clear();
    _uploader.close();
  }
}
