@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  late Uri originalUri;
  late JSAny? originalState;

  setUp(() {
    originalUri = Uri.parse(web.window.location.href);
    originalState = web.window.history.state;
  });

  tearDown(() {
    web.window.history.replaceState(originalState, '', originalUri.toString());
  });

  test('consumes the real launch fragment without adding history', () {
    final launchUri = _currentUriWith(
      queryMarker: 'success',
      fragment: 'target-launch=${_encodedOverlay()}',
    );
    _replaceLocation(launchUri, stateMarker: 'success');
    final historyLength = web.window.history.length;
    final state = web.window.history.state?.dartify();
    final path = web.window.location.pathname;
    final query = web.window.location.search;

    final overlay = RuntimeOverlay.readWebLaunchOverlay();

    expect(overlay['GATEWAY_ORIGIN'], 'http://127.0.0.1:8090');
    expect(web.window.location.hash, isEmpty);
    expect(web.window.location.pathname, path);
    expect(web.window.location.search, query);
    expect(web.window.history.state?.dartify(), state);
    expect(web.window.history.length, historyLength);
  });

  test('scrubs every rejected real launch fragment before throwing', () {
    final rejected = <String, String>{
      'empty': '',
      'malformed': 'not-json',
      'invalid-value': _encoded(const <String, String>{
        'TARGET_ACCESS_TOKEN': 'plain',
      }),
    };
    for (final entry in rejected.entries) {
      final launchUri = _currentUriWith(
        queryMarker: entry.key,
        fragment: 'target-launch=${entry.value}',
      );
      _replaceLocation(launchUri, stateMarker: entry.key);
      final historyLength = web.window.history.length;
      final state = web.window.history.state?.dartify();
      final path = web.window.location.pathname;
      final query = web.window.location.search;

      expect(
        RuntimeOverlay.readWebLaunchOverlay,
        throwsFormatException,
        reason: entry.key,
      );

      expect(web.window.location.hash, isEmpty, reason: entry.key);
      expect(web.window.location.pathname, path, reason: entry.key);
      expect(web.window.location.search, query, reason: entry.key);
      expect(web.window.history.state?.dartify(), state, reason: entry.key);
      expect(web.window.history.length, historyLength, reason: entry.key);
    }
  });

  test('leaves a foreign real fragment untouched', () {
    final launchUri = _currentUriWith(
      queryMarker: 'foreign',
      fragment: 'keep-this-fragment',
    );
    _replaceLocation(launchUri, stateMarker: 'foreign');
    final href = web.window.location.href;
    final historyLength = web.window.history.length;
    final state = web.window.history.state?.dartify();

    expect(RuntimeOverlay.readWebLaunchOverlay(), const <String, String>{});
    expect(web.window.location.href, href);
    expect(web.window.history.state?.dartify(), state);
    expect(web.window.history.length, historyLength);
  });

  test('keeps an explicit URI read pure', () {
    final browserUri = _currentUriWith(
      queryMarker: 'explicit',
      fragment: 'keep-browser-fragment',
    );
    _replaceLocation(browserUri, stateMarker: 'explicit');
    final href = web.window.location.href;
    final historyLength = web.window.history.length;
    final state = web.window.history.state?.dartify();
    final explicitUri = Uri.parse(
      'http://127.0.0.1:8080/#target-launch=${_encodedOverlay()}',
    );

    final overlay = RuntimeOverlay.readWebLaunchOverlay(uri: explicitUri);

    expect(overlay['GATEWAY_ORIGIN'], 'http://127.0.0.1:8090');
    expect(web.window.location.href, href);
    expect(web.window.history.state?.dartify(), state);
    expect(web.window.history.length, historyLength);
  });
}

Uri _currentUriWith({required String queryMarker, required String fragment}) {
  final current = Uri.parse(web.window.location.href);
  final query = current.hasQuery
      ? '${current.query}&overlayCase=$queryMarker'
      : 'overlayCase=$queryMarker';
  return current.replace(query: query, fragment: fragment);
}

void _replaceLocation(Uri uri, {required String stateMarker}) {
  web.window.history.replaceState(
    <String, Object?>{'marker': stateMarker}.jsify(),
    '',
    uri.toString(),
  );
}

String _encodedOverlay() => _encoded(const <String, String>{
  'SESSION_ID': 'run-00000001',
  'SESSION_NONCE': '0123456789abcdef',
  'TARGET_CONTROLLER_ORIGIN': 'http://127.0.0.1:7368',
  'SCENARIO_LAB_RUN_ID': 'run-00000001',
  'GATEWAY_ORIGIN': 'http://127.0.0.1:8090',
});

String _encoded(Map<String, String> value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
