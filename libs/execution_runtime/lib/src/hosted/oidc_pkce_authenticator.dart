import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:experience_engine/experience_engine.dart';
import 'package:jose/jose.dart';

final class OidcConfiguration {
  OidcConfiguration({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.jwksUri,
    required this.clientId,
    required this.allowedAlgorithms,
  }) {
    for (final entry in <MapEntry<String, Uri>>[
      MapEntry<String, Uri>('issuer', issuer),
      MapEntry<String, Uri>('authorizationEndpoint', authorizationEndpoint),
      MapEntry<String, Uri>('tokenEndpoint', tokenEndpoint),
      MapEntry<String, Uri>('jwksUri', jwksUri),
    ]) {
      if (entry.value.scheme != 'https' ||
          entry.value.host.isEmpty ||
          entry.value.userInfo.isNotEmpty ||
          entry.value.fragment.isNotEmpty) {
        throw ArgumentError('${entry.key} must be an absolute HTTPS URI');
      }
    }
    if (clientId.isEmpty) throw ArgumentError.value(clientId, 'clientId');
    if (allowedAlgorithms.isEmpty ||
        allowedAlgorithms.contains('none') ||
        allowedAlgorithms.any(
          (value) => !const <String>{'RS256', 'PS256', 'ES256'}.contains(value),
        )) {
      throw ArgumentError(
        'OIDC algorithms must use the approved asymmetric set',
      );
    }
  }

  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri jwksUri;
  final String clientId;
  final Set<String> allowedAlgorithms;
}

final class OidcLoginStart {
  const OidcLoginStart({
    required this.authorizationUri,
    required this.state,
    required this.expiresAt,
  });

  final Uri authorizationUri;
  final String state;
  final DateTime expiresAt;
}

final class OidcIdentity {
  const OidcIdentity({
    required this.issuer,
    required this.subject,
    required this.displayName,
    required this.expiresAt,
    required this.claims,
  });

  final Uri issuer;
  final String subject;
  final String displayName;
  final DateTime expiresAt;
  final Map<String, Object?> claims;
}

final class OidcLoginResult {
  const OidcLoginResult({
    required this.identity,
    required this.accessToken,
    required this.accessTokenExpiresAt,
    this.refreshToken,
  });

  final OidcIdentity identity;
  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String? refreshToken;
}

final class OidcAuthenticationException implements Exception {
  const OidcAuthenticationException(this.message);

  final String message;

  @override
  String toString() => 'OidcAuthenticationException: $message';
}

abstract interface class OidcHttpTransport {
  Future<Map<String, Object?>> getJson(Uri uri);

  Future<Map<String, Object?>> postForm(Uri uri, Map<String, String> body);
}

final class DartIoOidcHttpTransport implements OidcHttpTransport {
  DartIoOidcHttpTransport({
    required Set<String> allowedOrigins,
    HttpClient? client,
  }) : _allowedOrigins = Set<String>.unmodifiable(allowedOrigins),
       _client = client ?? HttpClient();

  static const int _maximumResponseBytes = 1024 * 1024;
  final Set<String> _allowedOrigins;
  final HttpClient _client;

  @override
  Future<Map<String, Object?>> getJson(Uri uri) => _request('GET', uri);

  @override
  Future<Map<String, Object?>> postForm(Uri uri, Map<String, String> body) =>
      _request('POST', uri, form: body);

  Future<Map<String, Object?>> _request(
    String method,
    Uri uri, {
    Map<String, String>? form,
  }) async {
    if (uri.scheme != 'https' || !_allowedOrigins.contains(uri.origin)) {
      throw const OidcAuthenticationException(
        'OIDC endpoint is not allowlisted',
      );
    }
    final request = await _client.openUrl(method, uri);
    request
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        form.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}='
                  '${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      );
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw OidcAuthenticationException(
        'OIDC endpoint returned HTTP ${response.statusCode}',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > _maximumResponseBytes) {
        throw const OidcAuthenticationException('OIDC response is oversized');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const OidcAuthenticationException(
        'OIDC response must be an object',
      );
    }
    return decoded;
  }
}

final class OidcPkceAuthenticator {
  OidcPkceAuthenticator({
    required this._configuration,
    required this._transport,
    required this._clock,
    Random? secureRandom,
  }) : _random = secureRandom ?? Random.secure();

  final OidcConfiguration _configuration;
  final OidcHttpTransport _transport;
  final Clock _clock;
  final Random _random;
  final Map<String, _PendingLogin> _pending = <String, _PendingLogin>{};

  OidcLoginStart beginLogin({
    required Uri redirectUri,
    List<String> scopes = const <String>['openid', 'profile'],
  }) {
    if (!redirectUri.isAbsolute || redirectUri.fragment.isNotEmpty) {
      throw ArgumentError('redirectUri must be absolute and have no fragment');
    }
    if (!scopes.contains('openid') || scopes.toSet().length != scopes.length) {
      throw ArgumentError('OIDC scopes must be unique and include openid');
    }
    _discardExpired();
    final state = _randomValue(32);
    final nonce = _randomValue(32);
    final verifier = _randomValue(64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final expiresAt = _clock.nowUtc().add(const Duration(minutes: 10));
    _pending[state] = _PendingLogin(
      nonce: nonce,
      verifier: verifier,
      redirectUri: redirectUri,
      expiresAt: expiresAt,
    );
    return OidcLoginStart(
      authorizationUri: _configuration.authorizationEndpoint.replace(
        queryParameters: <String, String>{
          'response_type': 'code',
          'client_id': _configuration.clientId,
          'redirect_uri': redirectUri.toString(),
          'scope': scopes.join(' '),
          'state': state,
          'nonce': nonce,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
        },
      ),
      state: state,
      expiresAt: expiresAt,
    );
  }

  Future<OidcLoginResult> completeLogin({
    required String state,
    required String code,
  }) async {
    final pending = _pending.remove(state);
    if (pending == null || !pending.expiresAt.isAfter(_clock.nowUtc())) {
      throw const OidcAuthenticationException(
        'OIDC state is invalid or expired',
      );
    }
    if (code.isEmpty) {
      throw const OidcAuthenticationException('authorization code is missing');
    }
    final tokenResponse = await _transport
        .postForm(_configuration.tokenEndpoint, <String, String>{
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': pending.redirectUri.toString(),
          'client_id': _configuration.clientId,
          'code_verifier': pending.verifier,
        });
    final idToken = _requiredString(tokenResponse, 'id_token');
    final accessToken = _requiredString(tokenResponse, 'access_token');
    final identity = await verifyIdToken(idToken, nonce: pending.nonce);
    final expiresIn = tokenResponse['expires_in'];
    if (expiresIn is! int || expiresIn < 30 || expiresIn > 86400) {
      throw const OidcAuthenticationException('token expiry is invalid');
    }
    final refresh = tokenResponse['refresh_token'];
    if (refresh != null && refresh is! String) {
      throw const OidcAuthenticationException('refresh token is invalid');
    }
    return OidcLoginResult(
      identity: identity,
      accessToken: accessToken,
      accessTokenExpiresAt: _clock.nowUtc().add(Duration(seconds: expiresIn)),
      refreshToken: refresh as String?,
    );
  }

  Future<OidcIdentity> verifyIdToken(
    String compactToken, {
    required String nonce,
  }) async {
    final token = await _verifyToken(compactToken);
    final claims = token.claims.toJson().cast<String, Object?>();
    if (claims['nonce'] != nonce) {
      throw const OidcAuthenticationException('OIDC nonce does not match');
    }
    return _identity(claims);
  }

  Future<OidcIdentity> verifyBearerToken(String compactToken) async {
    final token = await _verifyToken(compactToken);
    return _identity(token.claims.toJson().cast<String, Object?>());
  }

  Future<JsonWebToken> _verifyToken(String compactToken) async {
    final jwks = await _transport.getJson(_configuration.jwksUri);
    final keyStore = JsonWebKeyStore()..addKeySet(JsonWebKeySet.fromJson(jwks));
    final JsonWebToken token;
    try {
      token = await JsonWebToken.decodeAndVerify(
        compactToken,
        keyStore,
        allowedArguments: _configuration.allowedAlgorithms.toList(),
      );
    } on Object {
      throw const OidcAuthenticationException('token signature is invalid');
    }
    _validateClaims(token.claims.toJson().cast<String, Object?>());
    return token;
  }

  void _validateClaims(Map<String, Object?> claims) {
    final issuer = claims['iss'];
    final subject = claims['sub'];
    final expiry = claims['exp'];
    final issuedAt = claims['iat'];
    final audience = claims['aud'];
    if (issuer != _configuration.issuer.toString() ||
        subject is! String ||
        subject.isEmpty ||
        expiry is! num ||
        issuedAt is! num) {
      throw const OidcAuthenticationException(
        'required token claims are invalid',
      );
    }
    final audiences = switch (audience) {
      final String value => <String>[value],
      final List<Object?> values
          when values.every((value) => value is String) =>
        values.cast<String>(),
      _ => const <String>[],
    };
    if (!audiences.contains(_configuration.clientId)) {
      throw const OidcAuthenticationException('token audience does not match');
    }
    if (audiences.length > 1 && claims['azp'] != _configuration.clientId) {
      throw const OidcAuthenticationException(
        'authorized party does not match',
      );
    }
    final nowSeconds = _clock.nowUtc().millisecondsSinceEpoch ~/ 1000;
    const skew = 60;
    if (expiry.toInt() <= nowSeconds - skew ||
        issuedAt.toInt() > nowSeconds + skew) {
      throw const OidcAuthenticationException(
        'token is expired or not yet valid',
      );
    }
    final notBefore = claims['nbf'];
    if (notBefore != null &&
        (notBefore is! num || notBefore.toInt() > nowSeconds + skew)) {
      throw const OidcAuthenticationException('token is not active');
    }
  }

  OidcIdentity _identity(Map<String, Object?> claims) {
    final expiry = DateTime.fromMillisecondsSinceEpoch(
      (claims['exp']! as num).toInt() * 1000,
      isUtc: true,
    );
    final displayName = <Object?>[
      claims['name'],
      claims['preferred_username'],
      claims['sub'],
    ].whereType<String>().firstWhere((value) => value.isNotEmpty);
    return OidcIdentity(
      issuer: _configuration.issuer,
      subject: claims['sub']! as String,
      displayName: displayName,
      expiresAt: expiry,
      claims: Map<String, Object?>.unmodifiable(claims),
    );
  }

  String _randomValue(int byteCount) => base64Url
      .encode(List<int>.generate(byteCount, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  void _discardExpired() {
    final now = _clock.nowUtc();
    _pending.removeWhere((_, value) => !value.expiresAt.isAfter(now));
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw OidcAuthenticationException('$key is missing');
    }
    return value;
  }
}

final class _PendingLogin {
  const _PendingLogin({
    required this.nonce,
    required this.verifier,
    required this.redirectUri,
    required this.expiresAt,
  });

  final String nonce;
  final String verifier;
  final Uri redirectUri;
  final DateTime expiresAt;
}
