import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sample_flutter/showcase_models.dart';

abstract interface class ShowcaseApi {
  Future<ShowcaseDashboardResult> loadDashboard();

  Future<void> toggleTask(String projectId, String taskId);
}

final class HttpShowcaseApi implements ShowcaseApi {
  HttpShowcaseApi({
    required String baseUrl,
    this.dashboardState = ShowcaseDashboardState.ready,
    http.Client? client,
  }) : _baseUri = _validatedBaseUri(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri _baseUri;
  final ShowcaseDashboardState dashboardState;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<ShowcaseDashboardResult> loadDashboard() async {
    final endpoint = _baseUri
        .resolve('/v1/dashboard')
        .replace(
          queryParameters: <String, String>{'state': dashboardState.name},
        );
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 8));
    final result = ShowcaseDashboardResult.fromJson(_decodeBody(response));
    _validateDashboardStatus(response.statusCode, result.state);
    return result;
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
    _decodeSuccessful(response);
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, Object?> _decodeSuccessful(http.Response response) {
    final body = _decodeBody(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = body['error'];
      throw ShowcaseApiException(
        statusCode: response.statusCode,
        code: code is String ? code : 'HTTP_${response.statusCode}',
      );
    }
    return body;
  }

  Map<String, Object?> _decodeBody(http.Response response) {
    if (response.bodyBytes.length > 1024 * 1024) {
      throw const FormatException('Showcase API response exceeds 1 MiB');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, Object?>) {
      throw const FormatException('Showcase API response must be an object');
    }
    return body;
  }
}

void _validateDashboardStatus(int statusCode, ShowcaseDashboardState state) {
  final expected = switch (state) {
    ShowcaseDashboardState.ready ||
    ShowcaseDashboardState.empty ||
    ShowcaseDashboardState.stale => 200,
    ShowcaseDashboardState.loading => 202,
    ShowcaseDashboardState.unavailable => 503,
    ShowcaseDashboardState.failure => 500,
  };
  if (statusCode != expected) {
    throw FormatException(
      'Dashboard state ${state.name} requires HTTP $expected, got $statusCode',
    );
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
