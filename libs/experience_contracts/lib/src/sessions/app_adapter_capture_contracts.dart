final class AppAdapterCaptureCommand {
  AppAdapterCaptureCommand({
    required this.requestId,
    required this.sessionId,
    required this.format,
    required Uri uploadUri,
    required this.expiresAt,
    required this.maxBytes,
  }) : uploadUri = uploadUri {
    if (!_identifier.hasMatch(requestId) || !_identifier.hasMatch(sessionId)) {
      throw const FormatException('Invalid App Adapter capture identity');
    }
    if (format != 'png') {
      throw const FormatException('Only lossless PNG capture is supported');
    }
    if (uploadUri.scheme != 'http' ||
        !_loopbackHosts.contains(uploadUri.host) ||
        uploadUri.port < 1 ||
        uploadUri.userInfo.isNotEmpty ||
        uploadUri.fragment.isNotEmpty ||
        uploadUri.path != '/capture-uploads/$requestId' ||
        uploadUri.queryParameters.length != 1 ||
        uploadUri.queryParametersAll['token']?.length != 1 ||
        !_identifier.hasMatch(uploadUri.queryParameters['token'] ?? '')) {
      throw const FormatException('Capture upload handle must be loopback');
    }
    if (!expiresAt.isUtc || maxBytes < 1024 || maxBytes > 32 * 1024 * 1024) {
      throw const FormatException('Invalid capture upload bounds');
    }
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
  static const Set<String> _loopbackHosts = <String>{
    '127.0.0.1',
    '::1',
    'localhost',
  };

  final String requestId;
  final String sessionId;
  final String format;
  final Uri uploadUri;
  final DateTime expiresAt;
  final int maxBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'AppAdapterCaptureCommand',
    'requestId': requestId,
    'sessionId': sessionId,
    'format': format,
    'uploadUri': uploadUri.toString(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'maxBytes': maxBytes,
  };

  factory AppAdapterCaptureCommand.fromJson(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value.length != 8 ||
        value['schemaVersion'] != 1 ||
        value['kind'] != 'AppAdapterCaptureCommand') {
      throw const FormatException('Invalid App Adapter capture command');
    }
    const fields = <String>{
      'schemaVersion',
      'kind',
      'requestId',
      'sessionId',
      'format',
      'uploadUri',
      'expiresAt',
      'maxBytes',
    };
    if (value.keys.any((key) => key is! String || !fields.contains(key))) {
      throw const FormatException('Unknown App Adapter capture command field');
    }
    final requestId = value['requestId'];
    final sessionId = value['sessionId'];
    final format = value['format'];
    final upload = value['uploadUri'];
    final expires = value['expiresAt'];
    final maxBytes = value['maxBytes'];
    if (requestId is! String ||
        sessionId is! String ||
        format is! String ||
        upload is! String ||
        expires is! String ||
        maxBytes is! int) {
      throw const FormatException('Invalid App Adapter capture value');
    }
    final uploadUri = Uri.tryParse(upload);
    final expiresAt = DateTime.tryParse(expires);
    if (uploadUri == null || expiresAt == null || !expiresAt.isUtc) {
      throw const FormatException('Invalid App Adapter capture URI or expiry');
    }
    return AppAdapterCaptureCommand(
      requestId: requestId,
      sessionId: sessionId,
      format: format,
      uploadUri: uploadUri,
      expiresAt: expiresAt,
      maxBytes: maxBytes,
    );
  }
}
