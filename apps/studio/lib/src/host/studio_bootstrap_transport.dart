import 'dart:convert';

const String studioBootstrapUrlEnvironmentKey = 'STUDIO_BOOTSTRAP_URL';

final class StudioBootstrapException implements Exception {
  const StudioBootstrapException(this.message);

  final String message;

  @override
  String toString() => message;
}

Uri resolveStudioBootstrapUri(String configuredUrl) {
  if (configuredUrl.isEmpty) return Uri(path: '/studio/bootstrap.json');
  final uri = Uri.tryParse(configuredUrl);
  final loopback =
      uri != null &&
      const <String>{'127.0.0.1', 'localhost', '::1'}.contains(uri.host);
  if (uri == null ||
      !uri.isAbsolute ||
      uri.scheme != 'http' ||
      !loopback ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/studio/bootstrap.json' ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const StudioBootstrapException(
      'STUDIO_BOOTSTRAP_URL deve apontar exatamente para '
      'http://<loopback>:<porta>/studio/bootstrap.json.',
    );
  }
  return uri;
}

Map<String, Object?> decodeStudioBootstrapResponse({
  required int statusCode,
  required String? contentType,
  required String body,
}) {
  if (utf8.encode(body).length > 1024 * 1024) {
    throw const StudioBootstrapException(
      'A resposta de bootstrap do Abel Studio excedeu o limite permitido.',
    );
  }
  final mediaType = contentType?.split(';').first.trim().toLowerCase();
  if (statusCode == 200 && mediaType != 'application/json') {
    throw const StudioBootstrapException(
      'O Studio foi iniciado sem o Workspace Host. Execute `workspace dev` ou, para '
      'hot reload, configure STUDIO_BOOTSTRAP_URL conforme o runbook.',
    );
  }
  if (statusCode != 200) {
    throw StudioBootstrapException(
      'O Workspace Host rejeitou o bootstrap do Studio (HTTP $statusCode). '
      'Verifique o processo `workspace dev` e tente novamente.',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const StudioBootstrapException(
      'O Workspace Host retornou um bootstrap JSON inválido.',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const StudioBootstrapException(
      'O bootstrap do Abel Studio deve ser um objeto JSON.',
    );
  }
  return decoded;
}
