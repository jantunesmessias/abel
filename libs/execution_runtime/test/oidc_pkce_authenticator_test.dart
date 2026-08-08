import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:jose/jose.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9, 12);
  late JsonWebKey signingKey;
  late _FakeOidcTransport transport;
  late OidcPkceAuthenticator authenticator;

  setUp(() {
    signingKey = JsonWebKey.generate('RS256');
    transport = _FakeOidcTransport(
      publicJwk: JsonWebKey.fromCryptoKeys(
        publicKey: signingKey.cryptoKeyPair.publicKey,
      ).toJson().cast<String, Object?>(),
    );
    authenticator = OidcPkceAuthenticator(
      configuration: OidcConfiguration(
        issuer: Uri.parse('https://issuer.example.test'),
        authorizationEndpoint: Uri.parse(
          'https://issuer.example.test/oauth2/authorize',
        ),
        tokenEndpoint: Uri.parse('https://issuer.example.test/oauth2/token'),
        jwksUri: Uri.parse('https://issuer.example.test/.well-known/jwks.json'),
        clientId: 'workspace-cli',
        allowedAlgorithms: const <String>{'RS256'},
      ),
      transport: transport,
      clock: _FixedClock(now),
      secureRandom: Random(7),
    );
  });

  test('authorization code flow uses S256 and consumes state once', () async {
    final start = authenticator.beginLogin(
      redirectUri: Uri.parse('http://127.0.0.1:43123/callback'),
    );
    final query = start.authorizationUri.queryParameters;
    expect(query['response_type'], 'code');
    expect(query['code_challenge_method'], 'S256');
    expect(query['state'], start.state);
    expect(query['nonce'], isNotEmpty);

    transport.tokenResponse = <String, Object?>{
      'id_token': _token(
        signingKey,
        now: now,
        nonce: query['nonce']!,
        audience: 'workspace-cli',
      ),
      'access_token': 'ephemeral-access-token',
      'expires_in': 300,
    };
    final result = await authenticator.completeLogin(
      state: start.state,
      code: 'authorization-code',
    );
    expect(result.identity.subject, 'subject-001');
    expect(result.identity.displayName, 'Example User');
    final verifier = transport.lastForm!['code_verifier']!;
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    expect(challenge, query['code_challenge']);
    expect(transport.lastForm!['client_secret'], isNull);

    expect(
      () => authenticator.completeLogin(
        state: start.state,
        code: 'authorization-code',
      ),
      throwsA(isA<OidcAuthenticationException>()),
    );
  });

  test(
    'signature, nonce, issuer, audience, and algorithm fail closed',
    () async {
      final valid = _token(
        signingKey,
        now: now,
        nonce: 'nonce-001',
        audience: 'workspace-cli',
      );
      expect(
        (await authenticator.verifyIdToken(valid, nonce: 'nonce-001')).subject,
        'subject-001',
      );
      expect(
        () => authenticator.verifyIdToken(valid, nonce: 'different'),
        throwsA(isA<OidcAuthenticationException>()),
      );
      final wrongAudience = _token(
        signingKey,
        now: now,
        nonce: 'nonce-001',
        audience: 'another-client',
      );
      expect(
        () => authenticator.verifyIdToken(wrongAudience, nonce: 'nonce-001'),
        throwsA(isA<OidcAuthenticationException>()),
      );
      expect(
        () => OidcConfiguration(
          issuer: Uri.parse('https://issuer.example.test'),
          authorizationEndpoint: Uri.parse('https://issuer.example.test/auth'),
          tokenEndpoint: Uri.parse('https://issuer.example.test/token'),
          jwksUri: Uri.parse('https://issuer.example.test/jwks'),
          clientId: 'workspace-cli',
          allowedAlgorithms: const <String>{'none'},
        ),
        throwsArgumentError,
      );
    },
  );
}

String _token(
  JsonWebKey key, {
  required DateTime now,
  required String nonce,
  required String audience,
}) {
  final seconds = now.millisecondsSinceEpoch ~/ 1000;
  final builder = JsonWebSignatureBuilder()
    ..jsonContent = <String, Object?>{
      'iss': 'https://issuer.example.test',
      'sub': 'subject-001',
      'aud': audience,
      'iat': seconds,
      'exp': seconds + 300,
      'nonce': nonce,
      'name': 'Example User',
    }
    ..setProtectedHeader('typ', 'JWT')
    ..addRecipient(key, algorithm: 'RS256');
  return builder.build().toCompactSerialization();
}

final class _FakeOidcTransport implements OidcHttpTransport {
  _FakeOidcTransport({required this.publicJwk});

  final Map<String, Object?> publicJwk;
  Map<String, Object?>? tokenResponse;
  Map<String, String>? lastForm;

  @override
  Future<Map<String, Object?>> getJson(Uri uri) async => <String, Object?>{
    'keys': <Object?>[publicJwk],
  };

  @override
  Future<Map<String, Object?>> postForm(
    Uri uri,
    Map<String, String> body,
  ) async {
    lastForm = Map<String, String>.of(body);
    return tokenResponse!;
  }
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  int monotonicMicroseconds() => value.microsecondsSinceEpoch;

  @override
  DateTime nowUtc() => value;
}
