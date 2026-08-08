import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'runtime_overlay_history_stub.dart'
    if (dart.library.js_interop) 'runtime_overlay_history_web.dart'
    as history;

final class RuntimeOverlay {
  RuntimeOverlay._();

  static const MethodChannel _channel = MethodChannel(
    'app_adapter/runtime_configuration',
  );

  static Future<Map<String, String>> readAndroidLaunchOverlay() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const <String, String>{};
    }
    final raw = await _channel.invokeMapMethod<String, String>(
      'readLaunchOverlay',
    );
    return _validatedOverlay(
      raw ?? const <String, String>{},
      source: 'Android',
    );
  }

  /// Reads the short-lived launch context injected into a sandboxed web
  /// target's URL fragment by Abel Studio. Fragments are not sent to the
  /// target HTTP server and the iframe uses a no-referrer policy.
  static Map<String, String> readWebLaunchOverlay({Uri? uri}) {
    final readsCurrentLocation = uri == null;
    if (!kIsWeb && readsCurrentLocation) return const <String, String>{};
    final source = uri ?? Uri.base;
    final fragment = source.fragment;
    const prefix = 'target-launch=';
    if (!fragment.startsWith(prefix)) return const <String, String>{};
    try {
      final encoded = fragment.substring(prefix.length);
      if (encoded.isEmpty || encoded.length > 16 * 1024) {
        throw const FormatException('Invalid web launch overlay');
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
        );
      } on Object {
        throw const FormatException('Invalid web launch overlay');
      }
      if (decoded is! Map<String, Object?> ||
          decoded.values.any((value) => value is! String)) {
        throw const FormatException('Invalid web launch overlay');
      }
      return _validatedOverlay(decoded.cast<String, String>(), source: 'web');
    } finally {
      if (readsCurrentLocation) {
        history.replaceCurrentLocation(source.removeFragment());
      }
    }
  }

  static Map<String, String> _validatedOverlay(
    Map<String, String> values, {
    required String source,
  }) {
    if (values.length > 64) {
      throw FormatException('$source launch overlay exceeds 64 values');
    }
    final output = <String, String>{};
    final secret = RegExp(
      r'(secret|token|password|credential|private[_-]?key)',
      caseSensitive: false,
    );
    for (final entry in values.entries) {
      if (!RegExp(r'^[A-Z][A-Z0-9_]{0,63}$').hasMatch(entry.key) ||
          secret.hasMatch(entry.key) ||
          entry.value.isEmpty ||
          entry.value.length > 4096 ||
          entry.value.contains('\u0000')) {
        throw FormatException('Invalid $source launch overlay value');
      }
      output[entry.key] = entry.value;
    }
    return Map<String, String>.unmodifiable(output);
  }
}
