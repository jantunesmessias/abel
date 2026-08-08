import 'dart:convert';

import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes the bounded web launch fragment', () {
    final encoded = base64Url
        .encode(
          utf8.encode(
            jsonEncode(const <String, String>{
              'SESSION_ID': 'session-1',
              'SESSION_NONCE': '0123456789abcdef',
              'TARGET_CONTROLLER_ORIGIN': 'http://127.0.0.1:7368',
              'SCENARIO_LAB_RUN_ID': 'run-1',
            }),
          ),
        )
        .replaceAll('=', '');

    final overlay = RuntimeOverlay.readWebLaunchOverlay(
      uri: Uri.parse('http://127.0.0.1:8080/#target-launch=$encoded'),
    );

    expect(overlay['SESSION_ID'], 'session-1');
    expect(overlay['TARGET_CONTROLLER_ORIGIN'], 'http://127.0.0.1:7368');
    expect(overlay['SCENARIO_LAB_RUN_ID'], 'run-1');
  });

  test('rejects malformed or secret-like web overlay entries', () {
    String fragment(Map<String, String> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

    expect(
      () => RuntimeOverlay.readWebLaunchOverlay(
        uri: Uri.parse('http://localhost/#target-launch=not-json'),
      ),
      throwsFormatException,
    );
    expect(
      () => RuntimeOverlay.readWebLaunchOverlay(
        uri: Uri.parse(
          'http://localhost/#target-launch=${fragment(const <String, String>{'TARGET_ACCESS_TOKEN': 'plain'})}',
        ),
      ),
      throwsFormatException,
    );
  });
}
