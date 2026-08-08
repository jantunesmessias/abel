import 'dart:convert';

import 'package:devex_flutter/devex_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes the bounded web launch fragment', () {
    final encoded = base64Url
        .encode(
          utf8.encode(
            jsonEncode(const <String, String>{
              'DEVEX_SESSION_ID': 'session-1',
              'DEVEX_SESSION_NONCE': '0123456789abcdef',
              'DEVEX_CONTROLLER_ORIGIN': 'http://127.0.0.1:7368',
            }),
          ),
        )
        .replaceAll('=', '');

    final overlay = DevExRuntimeOverlay.readWebLaunchOverlay(
      uri: Uri.parse('http://127.0.0.1:8080/#devex-launch=$encoded'),
    );

    expect(overlay['DEVEX_SESSION_ID'], 'session-1');
    expect(overlay['DEVEX_CONTROLLER_ORIGIN'], 'http://127.0.0.1:7368');
  });

  test('rejects malformed or secret-like web overlay entries', () {
    String fragment(Map<String, String> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

    expect(
      () => DevExRuntimeOverlay.readWebLaunchOverlay(
        uri: Uri.parse('http://localhost/#devex-launch=not-json'),
      ),
      throwsFormatException,
    );
    expect(
      () => DevExRuntimeOverlay.readWebLaunchOverlay(
        uri: Uri.parse(
          'http://localhost/#devex-launch=${fragment(const <String, String>{'DEVEX_ACCESS_TOKEN': 'plain'})}',
        ),
      ),
      throwsFormatException,
    );
  });
}
