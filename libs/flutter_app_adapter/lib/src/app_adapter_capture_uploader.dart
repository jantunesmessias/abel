import 'package:experience_contracts/experience_contracts.dart';
import 'package:http/http.dart' as http;

import 'app_adapter.dart';

final class CaptureUploadResult {
  const CaptureUploadResult({required this.ok, required this.code});

  final bool ok;
  final String code;
}

/// Executes the binary portion of an App Adapter capture command.
///
/// The command itself is authenticated by the controller-to-target envelope.
/// Its upload URI is a short-lived, loopback-only, one-shot capability handle.
final class AppAdapterCaptureUploader {
  AppAdapterCaptureUploader({http.Client? client, DateTime Function()? nowUtc})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _nowUtc = nowUtc ?? _systemNowUtc;

  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _nowUtc;

  Future<CaptureUploadResult> upload({
    required AppAdapterCaptureCommand command,
    required AppAdapter adapter,
  }) async {
    if (isExpired(command.expiresAt)) {
      return const CaptureUploadResult(
        ok: false,
        code: 'capture_handle_expired',
      );
    }
    try {
      final bytes = await adapter.capture(format: command.format);
      return await _uploadPng(
        bytes: bytes,
        uploadUri: command.uploadUri,
        expiresAt: command.expiresAt,
        maxBytes: command.maxBytes,
      );
    } on Object {
      return const CaptureUploadResult(ok: false, code: 'capture_failed');
    }
  }

  /// Uploads bytes already captured for one relay command.
  ///
  /// Keeping capture outside this method lets a relay retry a renewed PUT
  /// grant without observing the widget tree a second time.
  Future<CaptureUploadResult> uploadRelay({
    required AppAdapterRelayCaptureUploadGrant grant,
    required List<int> pngBytes,
  }) => _uploadPng(
    bytes: pngBytes,
    uploadUri: grant.uploadUri,
    expiresAt: grant.expiresAt,
    maxBytes: grant.maxBytes,
  );

  bool isExpired(DateTime expiresAt) => !expiresAt.isAfter(_nowUtc());

  Future<CaptureUploadResult> _uploadPng({
    required List<int> bytes,
    required Uri uploadUri,
    required DateTime expiresAt,
    required int maxBytes,
  }) async {
    if (isExpired(expiresAt)) {
      return const CaptureUploadResult(
        ok: false,
        code: 'capture_handle_expired',
      );
    }
    if (bytes.length > maxBytes) {
      return const CaptureUploadResult(ok: false, code: 'capture_too_large');
    }
    try {
      final request = http.Request('PUT', uploadUri)
        ..followRedirects = false
        ..headers['content-type'] = 'image/png'
        ..bodyBytes = bytes;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      await response.stream.drain<void>();
      if (response.statusCode == 201) {
        return const CaptureUploadResult(ok: true, code: 'capture_uploaded');
      }
      return const CaptureUploadResult(
        ok: false,
        code: 'capture_upload_rejected',
      );
    } on Object {
      return const CaptureUploadResult(ok: false, code: 'capture_failed');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

DateTime _systemNowUtc() => DateTime.now().toUtc();
