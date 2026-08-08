import 'dart:convert';

const String studioBootstrapUrlEnvironmentKey = 'DEVEX_STUDIO_BOOTSTRAP_URL';

final class StudioBootstrapException implements Exception {
  const StudioBootstrapException(this.message);

  final String message;

  @override
  String toString() => message;
}

Uri resolveStudioBootstrapUri(String configuredUrl) {
  if (configuredUrl.isEmpty) return Uri(path: '/devex/bootstrap.json');
  final uri = Uri.tryParse(configuredUrl);
  final loopback =
      uri != null &&
      const <String>{'127.0.0.1', 'localhost', '::1'}.contains(uri.host);
  if (uri == null ||
      !uri.isAbsolute ||
      uri.scheme != 'http' ||
      !loopback ||
      uri.userInfo.isNotEmpty ||
      uri.path != '/devex/bootstrap.json' ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const StudioBootstrapException(
      'DEVEX_STUDIO_BOOTSTRAP_URL deve apontar exatamente para '
      'http://<loopback>:<porta>/devex/bootstrap.json.',
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
      'A resposta de bootstrap do DevEx Studio excedeu o limite permitido.',
    );
  }
  final mediaType = contentType?.split(';').first.trim().toLowerCase();
  if (statusCode == 200 && mediaType != 'application/json') {
    throw const StudioBootstrapException(
      'O Studio foi iniciado sem o DevEx Host. Execute `devex dev` ou, para '
      'hot reload, configure DEVEX_STUDIO_BOOTSTRAP_URL conforme o runbook.',
    );
  }
  if (statusCode != 200) {
    throw StudioBootstrapException(
      'O DevEx Host rejeitou o bootstrap do Studio (HTTP $statusCode). '
      'Verifique o processo `devex dev` e tente novamente.',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const StudioBootstrapException(
      'O DevEx Host retornou um bootstrap JSON inválido.',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const StudioBootstrapException(
      'O bootstrap do DevEx Studio deve ser um objeto JSON.',
    );
  }
  return decoded;
}
