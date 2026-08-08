import 'package:devex_contracts/devex_contracts.dart';
import 'package:http/http.dart' as http;

import 'devex_app_adapter.dart';

final class DevExCaptureUploadResult {
  const DevExCaptureUploadResult({required this.ok, required this.code});

  final bool ok;
  final String code;
}

/// Executes the binary portion of an App Adapter capture command.
///
/// The command itself is authenticated by the controller-to-target envelope.
/// Its upload URI is a short-lived, loopback-only, one-shot capability handle.
final class DevExAppAdapterCaptureUploader {
  DevExAppAdapterCaptureUploader({
    http.Client? client,
    DateTime Function()? nowUtc,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _nowUtc = nowUtc ?? _systemNowUtc;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _nowUtc;

  Future<DevExCaptureUploadResult> upload({
    required AppAdapterCaptureCommand command,
    required DevExAppAdapter adapter,
  }) async {
    if (!command.expiresAt.isAfter(_nowUtc())) {
      return const DevExCaptureUploadResult(
        ok: false,
        code: 'capture_handle_expired',
      );
    }
    try {
      final bytes = await adapter.capture(format: command.format);
      if (bytes.length > command.maxBytes) {
        return const DevExCaptureUploadResult(
          ok: false,
          code: 'capture_too_large',
        );
      }
      final request = http.Request('PUT', command.uploadUri)
        ..followRedirects = false
        ..headers['content-type'] = 'image/png'
        ..bodyBytes = bytes;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      await response.stream.drain<void>();
      if (response.statusCode == 201) {
        return const DevExCaptureUploadResult(
          ok: true,
          code: 'capture_uploaded',
        );
      }
      return const DevExCaptureUploadResult(
        ok: false,
        code: 'capture_upload_rejected',
      );
    } on Object {
      return const DevExCaptureUploadResult(ok: false, code: 'capture_failed');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

DateTime _systemNowUtc() => DateTime.now().toUtc();
