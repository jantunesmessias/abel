import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:web/web.dart' as web;

final class TargetFrameController {
  web.HTMLIFrameElement? _iframe;
  Uri? _targetUri;
  String? _sessionId;
  String? _nonce;
  var _sequence = 0;

  bool get isAttached => _iframe != null;

  void send(Map<String, Object?> payload) {
    final iframe = _iframe;
    final targetUri = _targetUri;
    final sessionId = _sessionId;
    final nonce = _nonce;
    if (iframe == null ||
        targetUri == null ||
        sessionId == null ||
        nonce == null) {
      throw StateError('TargetFrameController is not attached');
    }
    iframe.contentWindow?.postMessage(
      jsonEncode(
        PostMessageEnvelope(
          protocolVersion: 1,
          sessionId: sessionId,
          nonce: nonce,
          sequence: ++_sequence,
          payload: payload,
        ).toJson(),
      ).toJS,
      targetUri.origin.toJS,
    );
  }

  void _attach({
    required web.HTMLIFrameElement iframe,
    required Uri targetUri,
    required String sessionId,
    required String nonce,
  }) {
    if (_iframe != null && !identical(_iframe, iframe)) {
      throw StateError('TargetFrameController is already attached');
    }
    _iframe = iframe;
    _targetUri = targetUri;
    _sessionId = sessionId;
    _nonce = nonce;
    _sequence = 0;
  }

  void _detach(web.HTMLIFrameElement iframe) {
    if (!identical(_iframe, iframe)) return;
    _iframe = null;
    _targetUri = null;
    _sessionId = null;
    _nonce = null;
    _sequence = 0;
  }
}

final class TargetFrame extends StatefulComponent {
  TargetFrame({
    required this.targetUri,
    required this.sessionId,
    required this.nonce,
    required this.controller,
    required this.onAuthorizedMessage,
    this.gatewayOrigin,
    super.key,
  }) {
    if ((targetUri.scheme != 'http' && targetUri.scheme != 'https') ||
        targetUri.host.isEmpty ||
        targetUri.userInfo.isNotEmpty ||
        targetUri.fragment.isNotEmpty) {
      throw ArgumentError('TargetFrame requires an HTTP(S) origin');
    }
    final gateway = gatewayOrigin;
    if (gateway != null &&
        ((gateway.scheme != 'http' && gateway.scheme != 'https') ||
            !const <String>{
              'localhost',
              '127.0.0.1',
              '::1',
            }.contains(gateway.host) ||
            gateway.userInfo.isNotEmpty ||
            gateway.hasQuery ||
            gateway.hasFragment ||
            (gateway.path.isNotEmpty && gateway.path != '/'))) {
      throw ArgumentError('TargetFrame requires a loopback Gateway origin');
    }
  }

  final Uri targetUri;
  final String sessionId;
  final String nonce;
  final TargetFrameController controller;
  final void Function(PostMessageEnvelope envelope) onAuthorizedMessage;
  final Uri? gatewayOrigin;

  @override
  State<TargetFrame> createState() => _TargetFrameState();
}

final class _TargetFrameState extends State<TargetFrame> {
  late final String _frameId = 'devex-target-${identityHashCode(this)}';
  JSFunction? _messageListener;
  web.HTMLIFrameElement? _iframe;
  var _lastSequence = 0;
  var _activationScheduled = false;

  @override
  Component build(BuildContext context) {
    _activate();
    final launchContext = base64Url
        .encode(
          utf8.encode(
            jsonEncode(<String, String>{
              'DEVEX_SESSION_ID': component.sessionId,
              'DEVEX_SESSION_NONCE': component.nonce,
              'DEVEX_CONTROLLER_ORIGIN': web.window.location.origin,
              if (component.gatewayOrigin != null)
                'DEVEX_GATEWAY_ORIGIN': component.gatewayOrigin.toString(),
            }),
          ),
        )
        .replaceAll('=', '');
    final frameUri = component.targetUri.replace(
      fragment: 'devex-launch=$launchContext',
    );
    return iframe(
      const <Component>[],
      id: _frameId,
      src: frameUri.toString(),
      classes: 'target-frame',
      sandbox: 'allow-scripts allow-same-origin allow-forms',
      referrerPolicy: ReferrerPolicy.noReferrer,
      attributes: const <String, String>{
        'title': 'Aplicação em execução',
        'aria-label': 'Aplicação em execução',
      },
    );
  }

  void _activate() {
    if (_iframe != null || _activationScheduled) return;
    _activationScheduled = true;
    scheduleMicrotask(() {
      _activationScheduled = false;
      if (!mounted || _iframe != null) return;
      final element = web.document.getElementById(_frameId);
      if (element == null || !element.isA<web.HTMLIFrameElement>()) return;
      final frame = element as web.HTMLIFrameElement;
      _iframe = frame;
      component.controller._attach(
        iframe: frame,
        targetUri: component.targetUri,
        sessionId: component.sessionId,
        nonce: component.nonce,
      );
      final listener = _onMessage.toJS;
      _messageListener = listener;
      web.window.addEventListener('message', listener);
    });
  }

  void _onMessage(web.Event rawEvent) {
    final frame = _iframe;
    if (frame == null || !rawEvent.isA<web.MessageEvent>()) return;
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
        expectedOrigin: component.targetUri,
        sourceMatches: event.source == frame.contentWindow,
        expectedSessionId: component.sessionId,
        expectedNonce: component.nonce,
        minimumSequence: _lastSequence,
      );
      _lastSequence = envelope.sequence;
      component.onAuthorizedMessage(envelope);
    } on FormatException {
      // Invalid origin, source, nonce, session or sequence fails closed.
    }
  }

  @override
  void dispose() {
    final listener = _messageListener;
    if (listener != null) web.window.removeEventListener('message', listener);
    final frame = _iframe;
    if (frame != null) component.controller._detach(frame);
    _iframe = null;
    _messageListener = null;
    super.dispose();
  }
}
