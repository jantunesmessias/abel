import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:jose/jose.dart';

final class JoseRemoteExecutionSecurity
    implements
        RemotePlanSigner,
        RemoteCapabilityIssuer,
        RemoteSessionTicketIssuer {
  JoseRemoteExecutionSecurity({
    required JsonWebKey signingKey,
    required this.keyId,
    required this.algorithm,
  }) : _signingKey = JsonWebKey.fromJson(<String, dynamic>{
         ...signingKey.toJson(),
         'kid': keyId,
       }) {
    if (!const <String>{'RS256', 'PS256', 'ES256'}.contains(algorithm)) {
      throw ArgumentError('remote signing algorithm is not approved');
    }
    if (keyId.isEmpty) throw ArgumentError.value(keyId, 'keyId');
  }

  final JsonWebKey _signingKey;
  final String keyId;
  final String algorithm;

  @override
  Future<SignedRemoteExecutionPlan> sign(RemoteExecutionPlan plan) async {
    final compact = _sign(<String, Object?>{
      'iss': 'devex-scheduler',
      'aud': 'devex-worker',
      'sub': plan.runId,
      'jti': plan.nonce,
      'iat': plan.issuedAt.millisecondsSinceEpoch ~/ 1000,
      'exp': plan.expiresAt.millisecondsSinceEpoch ~/ 1000,
      'planDigest': plan.digest.value,
      'plan': plan.toJson(),
    }, typ: 'devex-remote-plan+jwt');
    return SignedRemoteExecutionPlan(
      plan: plan,
      compactSignature: compact,
      signerKeyId: keyId,
    );
  }

  @override
  Future<String> issue({
    required RemoteExecutionPlan plan,
    required RemoteLease lease,
    required Set<String> scopes,
  }) async {
    if (lease.tenantId != plan.tenantId || lease.runId != plan.runId) {
      throw ArgumentError('capability lease does not match plan');
    }
    const allowed = <String>{
      'artifact:read',
      'artifact:write',
      'run:heartbeat',
      'run:complete',
      'stream:write',
    };
    if (scopes.isEmpty || !allowed.containsAll(scopes)) {
      throw ArgumentError('remote capability scopes are invalid');
    }
    return _sign(<String, Object?>{
      'iss': 'devex-scheduler',
      'aud': 'devex-worker',
      'sub': lease.workerId,
      'jti': lease.tokenId,
      'iat': lease.heartbeatAt.millisecondsSinceEpoch ~/ 1000,
      'exp': lease.expiresAt.millisecondsSinceEpoch ~/ 1000,
      'tenantId': lease.tenantId,
      'runId': lease.runId,
      'generation': lease.generation,
      'planDigest': plan.digest.value,
      'artifactDigests': <String>[
        for (final digest in plan.artifactDigests) digest.value,
      ],
      'scope': scopes.toList()..sort(),
    }, typ: 'devex-worker-capability+jwt');
  }

  @override
  Future<String> issueViewerTicket(RemoteSessionTicket ticket) async =>
      _sign(<String, Object?>{
        'iss': 'devex-scheduler',
        'aud': 'devex-session-gateway',
        'sub': ticket.principalId,
        'jti': ticket.nonce,
        'iat': ticket.issuedAt.millisecondsSinceEpoch ~/ 1000,
        'exp': ticket.expiresAt.millisecondsSinceEpoch ~/ 1000,
        'ticket': ticket.toJson(),
      }, typ: 'devex-session-ticket+jwt');

  String _sign(Map<String, Object?> claims, {required String typ}) {
    final builder = JsonWebSignatureBuilder()
      ..jsonContent = claims
      ..setProtectedHeader('typ', typ)
      ..addRecipient(_signingKey, algorithm: algorithm);
    return builder.build().toCompactSerialization();
  }
}

final class VerifiedRemoteCapability {
  const VerifiedRemoteCapability({
    required this.tenantId,
    required this.runId,
    required this.workerId,
    required this.tokenId,
    required this.generation,
    required this.planDigest,
    required this.artifactDigests,
    required this.scopes,
    required this.expiresAt,
  });

  final String tenantId;
  final String runId;
  final String workerId;
  final String tokenId;
  final int generation;
  final Digest planDigest;
  final Set<Digest> artifactDigests;
  final Set<String> scopes;
  final DateTime expiresAt;
}

final class VerifiedRemoteStreamWriter {
  const VerifiedRemoteStreamWriter({
    required this.tenantId,
    required this.runId,
    required this.workerId,
    required this.tokenId,
    required this.generation,
    required this.expiresAt,
  });

  final String tenantId;
  final String runId;
  final String workerId;
  final String tokenId;
  final int generation;
  final DateTime expiresAt;
}

final class RemoteWorkerTokenVerifier {
  RemoteWorkerTokenVerifier({
    required JsonWebKeySet trustedKeys,
    required Set<String> allowedAlgorithms,
    required this._clock,
  }) : _keys = JsonWebKeyStore()..addKeySet(trustedKeys),
       _allowedAlgorithms = Set<String>.unmodifiable(allowedAlgorithms) {
    if (_allowedAlgorithms.isEmpty ||
        _allowedAlgorithms.contains('none') ||
        _allowedAlgorithms.any(
          (value) => !const <String>{'RS256', 'PS256', 'ES256'}.contains(value),
        )) {
      throw ArgumentError('remote verification algorithms are invalid');
    }
  }

  final JsonWebKeyStore _keys;
  final Set<String> _allowedAlgorithms;
  final Clock _clock;

  Future<RemoteExecutionPlan> verifyPlan(String compact) async {
    final claims = await _claims(compact);
    if (claims['iss'] != 'devex-scheduler' ||
        claims['aud'] != 'devex-worker' ||
        claims['plan'] is! Map<String, Object?>) {
      throw const RemoteStateException('signed remote plan claims are invalid');
    }
    final plan = RemoteExecutionPlan.fromJson(claims['plan']);
    if (claims['sub'] != plan.runId ||
        claims['jti'] != plan.nonce ||
        claims['planDigest'] != plan.digest.value) {
      throw const RemoteStateException('signed remote plan binding is invalid');
    }
    return plan;
  }

  Future<VerifiedRemoteCapability> verifyCapability(
    String compact, {
    required RemoteExecutionPlan plan,
    required String workerId,
    required Set<String> requiredScopes,
  }) async {
    final claims = await _claims(compact);
    final scopes = _stringSet(claims['scope'], 'scope');
    final artifacts = _stringSet(
      claims['artifactDigests'],
      'artifactDigests',
    ).map(Digest.new).toSet();
    if (claims['iss'] != 'devex-scheduler' ||
        claims['aud'] != 'devex-worker' ||
        claims['sub'] != workerId ||
        claims['tenantId'] != plan.tenantId ||
        claims['runId'] != plan.runId ||
        claims['planDigest'] != plan.digest.value ||
        !scopes.containsAll(requiredScopes) ||
        artifacts.length != plan.artifactDigests.length ||
        !artifacts.containsAll(plan.artifactDigests)) {
      throw const RemoteStateException('worker capability binding is invalid');
    }
    final generation = claims['generation'];
    final tokenId = claims['jti'];
    final expiry = claims['exp'];
    if (generation is! int ||
        generation < 1 ||
        tokenId is! String ||
        tokenId.isEmpty ||
        expiry is! num) {
      throw const RemoteStateException('worker capability fields are invalid');
    }
    return VerifiedRemoteCapability(
      tenantId: plan.tenantId,
      runId: plan.runId,
      workerId: workerId,
      tokenId: tokenId,
      generation: generation,
      planDigest: plan.digest,
      artifactDigests: Set<Digest>.unmodifiable(artifacts),
      scopes: Set<String>.unmodifiable(scopes),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiry.toInt() * 1000,
        isUtc: true,
      ),
    );
  }

  Future<VerifiedRemoteStreamWriter> verifyStreamWriter(
    String compact, {
    required String runId,
  }) async {
    final claims = await _claims(compact);
    final scopes = _stringSet(claims['scope'], 'scope');
    final tenantId = claims['tenantId'];
    final claimedRunId = claims['runId'];
    final workerId = claims['sub'];
    final tokenId = claims['jti'];
    final generation = claims['generation'];
    final expiry = claims['exp'];
    if (claims['iss'] != 'devex-scheduler' ||
        claims['aud'] != 'devex-worker' ||
        tenantId is! String ||
        tenantId.isEmpty ||
        claimedRunId != runId ||
        workerId is! String ||
        workerId.isEmpty ||
        tokenId is! String ||
        tokenId.isEmpty ||
        generation is! int ||
        generation < 1 ||
        expiry is! num ||
        !scopes.contains('stream:write')) {
      throw const RemoteStateException(
        'remote stream-writer capability is invalid',
      );
    }
    return VerifiedRemoteStreamWriter(
      tenantId: tenantId,
      runId: runId,
      workerId: workerId,
      tokenId: tokenId,
      generation: generation,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiry.toInt() * 1000,
        isUtc: true,
      ),
    );
  }

  Future<RemoteSessionTicket> verifyViewerTicket(
    String compact, {
    required String runId,
  }) async {
    final claims = await _claims(compact);
    if (claims['iss'] != 'devex-scheduler' ||
        claims['aud'] != 'devex-session-gateway' ||
        claims['ticket'] is! Map<String, Object?>) {
      throw const RemoteStateException('remote viewer ticket is invalid');
    }
    final ticket = RemoteSessionTicket.fromJson(claims['ticket']);
    final expiry = claims['exp'];
    final issuedAt = claims['iat'];
    if (ticket.runId != runId ||
        ticket.role != RemoteSessionRole.viewer ||
        claims['sub'] != ticket.principalId ||
        claims['jti'] != ticket.nonce ||
        expiry is! num ||
        issuedAt is! num ||
        expiry.toInt() != ticket.expiresAt.millisecondsSinceEpoch ~/ 1000 ||
        issuedAt.toInt() != ticket.issuedAt.millisecondsSinceEpoch ~/ 1000) {
      throw const RemoteStateException(
        'remote viewer ticket binding is invalid',
      );
    }
    return ticket;
  }

  Future<Map<String, Object?>> _claims(String compact) async {
    final JsonWebToken token;
    try {
      token = await JsonWebToken.decodeAndVerify(
        compact,
        _keys,
        allowedArguments: _allowedAlgorithms.toList(),
      );
    } on Object {
      throw const RemoteStateException('remote token signature is invalid');
    }
    final claims = token.claims.toJson().cast<String, Object?>();
    final expiry = claims['exp'];
    final issuedAt = claims['iat'];
    final now = _clock.nowUtc().millisecondsSinceEpoch ~/ 1000;
    if (expiry is! num ||
        issuedAt is! num ||
        expiry.toInt() <= now ||
        issuedAt.toInt() > now + 30) {
      throw const RemoteStateException('remote token lifetime is invalid');
    }
    return claims;
  }

  Set<String> _stringSet(Object? value, String name) {
    if (value is! List<Object?> ||
        value.isEmpty ||
        value.any((item) => item is! String || item.isEmpty)) {
      throw RemoteStateException('$name claim is invalid');
    }
    final output = value.cast<String>().toSet();
    if (output.length != value.length) {
      throw RemoteStateException('$name claim contains duplicates');
    }
    return output;
  }
}
