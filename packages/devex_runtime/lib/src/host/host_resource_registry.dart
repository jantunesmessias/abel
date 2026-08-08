import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:shelf/shelf.dart';

/// Issues short-lived, audience-bound HTTP capabilities for Host resources.
///
/// Tokens are deliberately unrelated to paths or digests. Bytes are owned by
/// the registry, revalidated before delivery and never exposed through a local
/// filesystem path.
final class HostResourceRegistry {
  HostResourceRegistry({
    required this.clock,
    required this.ids,
    this.maxActiveResources = 1024,
    this.maxTotalBytes = 128 * 1024 * 1024,
    this.maxResourceBytes = 64 * 1024 * 1024,
    this.maxTtl = const Duration(minutes: 15),
  }) {
    if (maxActiveResources < 1 ||
        maxTotalBytes < 1 ||
        maxResourceBytes < 1 ||
        maxResourceBytes > maxTotalBytes ||
        maxTtl <= Duration.zero) {
      throw ArgumentError('Host resource registry limits are invalid');
    }
  }

  final Clock clock;
  final IdGenerator ids;
  final int maxActiveResources;
  final int maxTotalBytes;
  final int maxResourceBytes;
  final Duration maxTtl;

  final Map<String, _HostResourceGrant> _grants =
      <String, _HostResourceGrant>{};
  var _totalBytes = 0;

  int get activeCount {
    _discardExpired();
    return _grants.length;
  }

  int get totalBytes {
    _discardExpired();
    return _totalBytes;
  }

  ResourceHandle grantBytes({
    required Uri hostOrigin,
    required Uri audienceOrigin,
    required List<int> bytes,
    required String mediaType,
    required String purpose,
    ArtifactClassification classification = ArtifactClassification.internal,
    Duration ttl = const Duration(minutes: 2),
  }) {
    if (!hostOrigin.hasScheme ||
        !const <String>{'http', 'https'}.contains(hostOrigin.scheme) ||
        hostOrigin.host.isEmpty ||
        hostOrigin.userInfo.isNotEmpty ||
        hostOrigin.path.isNotEmpty ||
        hostOrigin.hasQuery ||
        hostOrigin.hasFragment) {
      throw ArgumentError.value(hostOrigin, 'hostOrigin');
    }
    if (!audienceOrigin.hasScheme ||
        !const <String>{'http', 'https'}.contains(audienceOrigin.scheme) ||
        audienceOrigin.host.isEmpty ||
        audienceOrigin.userInfo.isNotEmpty ||
        (audienceOrigin.path.isNotEmpty && audienceOrigin.path != '/') ||
        audienceOrigin.hasQuery ||
        audienceOrigin.hasFragment) {
      throw ArgumentError.value(audienceOrigin, 'audienceOrigin');
    }
    if (classification == ArtifactClassification.sensitive) {
      throw ArgumentError('Sensitive resources cannot be granted to Studio');
    }
    if (ttl <= Duration.zero || ttl > maxTtl) {
      throw ArgumentError.value(ttl, 'ttl', 'is outside the allowed range');
    }
    if (bytes.length > maxResourceBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'exceeds maxResourceBytes',
      );
    }
    _discardExpired();
    if (_grants.length >= maxActiveResources ||
        _totalBytes + bytes.length > maxTotalBytes) {
      throw StateError('Host resource registry quota exceeded');
    }

    final ownedBytes = ImmutableBytes.copyOf(bytes);
    final digest = Digest.bytes(ownedBytes);
    final token = _nextToken();
    final expiresAt = clock.nowUtc().add(ttl);
    _grants[token] = _HostResourceGrant(
      bytes: ownedBytes,
      digest: digest,
      mediaType: mediaType,
      purpose: purpose,
      classification: classification,
      audienceOrigin: audienceOrigin.origin,
      expiresAt: expiresAt,
    );
    _totalBytes += ownedBytes.length;
    return ResourceHandle(
      uri: hostOrigin.replace(path: '/resources/$token'),
      digest: digest,
      mediaType: mediaType,
      size: ownedBytes.length,
      purpose: purpose,
      expiresAt: expiresAt,
    );
  }

  Response serve(Request request) {
    if (request.method != 'GET') {
      return Response(405, headers: const <String, String>{'allow': 'GET'});
    }
    if (request.url.hasQuery) return Response.notFound('Not found');
    final segments = request.url.pathSegments;
    if (segments.length != 2 || segments.first != 'resources') {
      return Response.notFound('Not found');
    }
    final token = segments.last;
    final grant = _grants[token];
    if (grant == null) return Response.notFound('Not found');
    if (!clock.nowUtc().isBefore(grant.expiresAt)) {
      _remove(token);
      return Response.notFound('Not found');
    }
    final origin = _httpOrigin(request.headers['origin']);
    if (origin != grant.audienceOrigin) {
      return Response.forbidden('Origin denied');
    }
    if (Digest.bytes(grant.bytes) != grant.digest) {
      _remove(token);
      throw StateError('Host resource digest changed after grant');
    }
    return Response.ok(
      grant.bytes,
      headers: <String, String>{
        'access-control-allow-origin': grant.audienceOrigin,
        'cache-control': 'no-store',
        'content-length': '${grant.bytes.length}',
        'content-type': grant.mediaType,
        'etag': '"${grant.digest.value}"',
        'vary': 'Origin',
        'x-content-type-options': 'nosniff',
      },
    );
  }

  void revoke(ResourceHandle handle) {
    final segments = handle.uri.pathSegments;
    if (segments.length == 2 && segments.first == 'resources') {
      _remove(segments.last);
    }
  }

  void clear() {
    _grants.clear();
    _totalBytes = 0;
  }

  String _nextToken() {
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final buffer = StringBuffer();
      for (var part = 0; part < 8 && buffer.length < 32; part += 1) {
        buffer.write(ids.nextId().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), ''));
      }
      final token = buffer.toString();
      if (token.length >= 32 && !_grants.containsKey(token)) return token;
    }
    throw StateError('Could not allocate a unique Host resource capability');
  }

  void _discardExpired() {
    final now = clock.nowUtc();
    for (final entry in _grants.entries.toList(growable: false)) {
      if (!now.isBefore(entry.value.expiresAt)) _remove(entry.key);
    }
  }

  void _remove(String token) {
    final removed = _grants.remove(token);
    if (removed != null) _totalBytes -= removed.bytes.length;
  }

  String? _httpOrigin(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null ||
        !const <String>{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    return uri.origin;
  }
}

final class _HostResourceGrant {
  const _HostResourceGrant({
    required this.bytes,
    required this.digest,
    required this.mediaType,
    required this.purpose,
    required this.classification,
    required this.audienceOrigin,
    required this.expiresAt,
  });

  final ImmutableBytes bytes;
  final Digest digest;
  final String mediaType;
  final String purpose;
  final ArtifactClassification classification;
  final String audienceOrigin;
  final DateTime expiresAt;
}
