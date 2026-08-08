import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:shelf/shelf.dart';

/// Immutable input for one resource in an atomic Host grant set.
final class HostResourceGrantInput {
  const HostResourceGrantInput({
    required this.bytes,
    required this.mediaType,
    required this.purpose,
    this.classification = ArtifactClassification.internal,
    this.ttl = const Duration(minutes: 2),
  });

  final List<int> bytes;
  final String mediaType;
  final String purpose;
  final ArtifactClassification classification;
  final Duration ttl;
}

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
  }) => grantByteSet(
    hostOrigin: hostOrigin,
    audienceOrigin: audienceOrigin,
    inputs: <HostResourceGrantInput>[
      HostResourceGrantInput(
        bytes: bytes,
        mediaType: mediaType,
        purpose: purpose,
        classification: classification,
        ttl: ttl,
      ),
    ],
  ).single;

  /// Grants a set of immutable resources as one quota-checked operation.
  ///
  /// Every input is validated and every handle is staged before the registry
  /// becomes observable. A bad input, exhausted quota or token allocation
  /// failure therefore leaves the prior registry state intact.
  List<ResourceHandle> grantByteSet({
    required Uri hostOrigin,
    required Uri audienceOrigin,
    required List<HostResourceGrantInput> inputs,
  }) {
    if (inputs.isEmpty) {
      throw ArgumentError.value(inputs, 'inputs', 'must not be empty');
    }
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
    var inputBytes = 0;
    for (final input in inputs) {
      if (input.classification == ArtifactClassification.sensitive) {
        throw ArgumentError('Sensitive resources cannot be granted to Studio');
      }
      if (input.ttl <= Duration.zero || input.ttl > maxTtl) {
        throw ArgumentError.value(
          input.ttl,
          'ttl',
          'is outside the allowed range',
        );
      }
      if (input.bytes.length > maxResourceBytes) {
        throw ArgumentError.value(
          input.bytes.length,
          'bytes',
          'exceeds maxResourceBytes',
        );
      }
      if (input.mediaType.isEmpty || input.purpose.isEmpty) {
        throw ArgumentError('Resource mediaType and purpose must not be empty');
      }
      inputBytes += input.bytes.length;
    }
    _discardExpired();
    if (_grants.length + inputs.length > maxActiveResources ||
        _totalBytes + inputBytes > maxTotalBytes) {
      throw StateError('Host resource registry quota exceeded');
    }

    final now = clock.nowUtc();
    final reservedTokens = <String>{};
    final staged = <_StagedHostResource>[];
    for (final input in inputs) {
      final ownedBytes = ImmutableBytes.copyOf(input.bytes);
      final digest = Digest.bytes(ownedBytes);
      final token = _nextToken(reservedTokens);
      reservedTokens.add(token);
      final expiresAt = now.add(input.ttl);
      final grant = _HostResourceGrant(
        bytes: ownedBytes,
        digest: digest,
        mediaType: input.mediaType,
        purpose: input.purpose,
        classification: input.classification,
        audienceOrigin: audienceOrigin.origin,
        expiresAt: expiresAt,
      );
      final handle = ResourceHandle(
        uri: hostOrigin.replace(path: '/resources/$token'),
        digest: digest,
        mediaType: input.mediaType,
        size: ownedBytes.length,
        purpose: input.purpose,
        expiresAt: expiresAt,
      );
      staged.add(
        _StagedHostResource(token: token, grant: grant, handle: handle),
      );
    }

    for (final resource in staged) {
      _grants[resource.token] = resource.grant;
      _totalBytes += resource.grant.bytes.length;
    }
    return List<ResourceHandle>.unmodifiable(
      staged.map((resource) => resource.handle),
    );
  }

  /// Atomically replaces a caller-owned lease set without transiently leaking
  /// registry quota. A failed replacement restores every still-valid prior
  /// grant with the same opaque token and expiry.
  List<ResourceHandle> replaceByteSet({
    required Uri hostOrigin,
    required Uri audienceOrigin,
    required List<HostResourceGrantInput> inputs,
    required List<ResourceHandle> previous,
  }) {
    _discardExpired();
    final removed = _matchingGrants(previous);
    for (final token in removed.keys) {
      _remove(token);
    }
    try {
      return grantByteSet(
        hostOrigin: hostOrigin,
        audienceOrigin: audienceOrigin,
        inputs: inputs,
      );
    } on Object {
      for (final entry in removed.entries) {
        if (_grants.containsKey(entry.key)) {
          throw StateError('Host resource replacement token collision');
        }
        _grants[entry.key] = entry.value;
        _totalBytes += entry.value.bytes.length;
      }
      rethrow;
    }
  }

  /// Checks shared count and byte quota for a synchronous replacement without
  /// revoking the caller's existing handles.
  bool replacementFits({
    required List<HostResourceGrantInput> inputs,
    required List<ResourceHandle> previous,
  }) {
    _discardExpired();
    final removed = _matchingGrants(previous);
    final removedBytes = removed.values.fold<int>(
      0,
      (total, grant) => total + grant.bytes.length,
    );
    final inputBytes = inputs.fold<int>(
      0,
      (total, input) => total + input.bytes.length,
    );
    return _grants.length - removed.length + inputs.length <=
            maxActiveResources &&
        _totalBytes - removedBytes + inputBytes <= maxTotalBytes &&
        inputs.every((input) => input.bytes.length <= maxResourceBytes);
  }

  Map<String, _HostResourceGrant> _matchingGrants(
    List<ResourceHandle> handles,
  ) {
    final matching = <String, _HostResourceGrant>{};
    for (final handle in handles) {
      final segments = handle.uri.pathSegments;
      if (segments.length != 2 || segments.first != 'resources') continue;
      final token = segments.last;
      final grant = _grants[token];
      if (grant == null ||
          grant.digest != handle.digest ||
          grant.mediaType != handle.mediaType ||
          grant.bytes.length != handle.size ||
          grant.purpose != handle.purpose ||
          grant.expiresAt != handle.expiresAt) {
        continue;
      }
      matching[token] = grant;
    }
    return matching;
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

  String _nextToken([Set<String> reserved = const <String>{}]) {
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final buffer = StringBuffer();
      for (var part = 0; part < 8 && buffer.length < 32; part += 1) {
        final normalized = ids.nextId().replaceAll(
          RegExp(r'[^A-Za-z0-9_-]'),
          '',
        );
        final remaining = 32 - buffer.length;
        buffer.write(
          normalized.length <= remaining
              ? normalized
              : normalized.substring(0, remaining),
        );
      }
      final token = buffer.toString();
      if (token.length >= 32 &&
          !_grants.containsKey(token) &&
          !reserved.contains(token)) {
        return token;
      }
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

final class _StagedHostResource {
  const _StagedHostResource({
    required this.token,
    required this.grant,
    required this.handle,
  });

  final String token;
  final _HostResourceGrant grant;
  final ResourceHandle handle;
}
