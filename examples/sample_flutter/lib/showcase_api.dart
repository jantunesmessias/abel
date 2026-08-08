import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sample_flutter/showcase_models.dart';

abstract interface class ShowcaseApi {
  Future<ShowcaseDashboard> loadDashboard();

  Future<void> toggleTask(String projectId, String taskId);
}

final class HttpShowcaseApi implements ShowcaseApi {
  HttpShowcaseApi({required String baseUrl, http.Client? client})
    : _baseUri = _validatedBaseUri(baseUrl),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  final Uri _baseUri;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<ShowcaseDashboard> loadDashboard() async {
    final response = await _client
        .get(_baseUri.resolve('/v1/dashboard'))
        .timeout(const Duration(seconds: 8));
    return ShowcaseDashboard.fromJson(_decode(response));
  }

  @override
  Future<void> toggleTask(String projectId, String taskId) async {
    final response = await _client
        .post(
          _baseUri.resolve(
            '/v1/projects/${Uri.encodeComponent(projectId)}/tasks/'
            '${Uri.encodeComponent(taskId)}/toggle',
          ),
        )
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, Object?> _decode(http.Response response) {
    if (response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException('Showcase API response exceeds 1 MiB');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = body is Map<String, Object?> ? body['error'] : null;
      throw ShowcaseApiException(
        statusCode: response.statusCode,
        code: code is String ? code : 'HTTP_${response.statusCode}',
      );
    }
    if (body is! Map<String, Object?>) {
      throw const FormatException('Showcase API response must be an object');
    }
    return body;
  }
}

final class ShowcaseApiException implements Exception {
  const ShowcaseApiException({required this.statusCode, required this.code});

  final int statusCode;
  final String code;

  @override
  String toString() => 'ShowcaseApiException($statusCode, $code)';
}

Uri _validatedBaseUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isAbsolute ||
      !const <String>{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Invalid Showcase API base URL');
  }
  return uri;
}
