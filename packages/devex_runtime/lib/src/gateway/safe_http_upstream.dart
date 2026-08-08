import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';

import '../workspace/workspace_configuration_loader.dart';

final class GatewayUpstreamEndpoint {
  GatewayUpstreamEndpoint({
    required this.profileId,
    required this.baseUri,
    required this.allowedHost,
    required this.environment,
    this.allowPrivateAddresses = false,
    this.credentialHandle,
    String credentialHeader = 'authorization',
    this.maxResponseBytes = 1024 * 1024,
    this.timeout = const Duration(seconds: 10),
  }) : credentialHeader = credentialHeader.toLowerCase() {
    if ((baseUri.scheme != 'http' && baseUri.scheme != 'https') ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment) {
      throw ArgumentError.value(baseUri, 'baseUri', 'must be an HTTP origin');
    }
    if (allowedHost.toLowerCase() != baseUri.host.toLowerCase()) {
      throw ArgumentError('allowedHost must exactly match baseUri.host');
    }
    if (environment == UpstreamEnvironment.staging &&
        baseUri.scheme != 'https') {
      throw ArgumentError('staging upstream requires HTTPS');
    }
    final host = allowedHost.toLowerCase();
    if (host == 'production' ||
        host == 'prod' ||
        host.endsWith('.production') ||
        host.endsWith('.prod')) {
      throw ArgumentError('production-like upstream host is forbidden');
    }
    final environmentHandle =
        credentialHandle?.startsWith('env:DEVEX_') == true &&
        credentialHandle!.length > 'env:DEVEX_'.length;
    final capturedSessionHandle = credentialHandle == 'session:authorization';
    if (credentialHandle != null &&
        !environmentHandle &&
        !capturedSessionHandle) {
      throw ArgumentError(
        'credentialHandle must be env:DEVEX_* or session:authorization',
      );
    }
    if (capturedSessionHandle && credentialHeader != 'authorization') {
      throw ArgumentError(
        'session:authorization requires the authorization header',
      );
    }
    if (credentialHandle == null && credentialHeader != 'authorization') {
      throw ArgumentError('credentialHeader requires credentialHandle');
    }
    if (credentialHeader != 'authorization' &&
        credentialHeader != 'x-api-key') {
      throw ArgumentError('Unsupported credentialHeader');
    }
    if (maxResponseBytes <= 0 || maxResponseBytes > 1024 * 1024) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
  }

  final UpstreamProfileId profileId;
  final Uri baseUri;
  final String allowedHost;
  final UpstreamEnvironment environment;
  final bool allowPrivateAddresses;
  final String? credentialHandle;
  final String credentialHeader;
  final int maxResponseBytes;
  final Duration timeout;

  Map<String, Object?> redactedStatus() => <String, Object?>{
    'profileId': profileId.value,
    'environment': environment.name,
    'scheme': baseUri.scheme,
    'hostAllowed': true,
    'privateAddressesAllowed': allowPrivateAddresses,
    'credentialConfigured': credentialHandle != null,
    'maxResponseBytes': maxResponseBytes,
  };
}

final class CredentialValue {
  const CredentialValue._(this.value);

  factory CredentialValue(String value) {
    if (value.isEmpty || value.length > 8192) {
      throw const FormatException('Credential value has an invalid length');
    }
    return CredentialValue._(value);
  }

  final String value;

  @override
  String toString() => '<redacted>';
}

abstract interface class CredentialResolver {
  Future<CredentialValue?> resolve(String handle);
}

final class EnvironmentCredentialResolver implements CredentialResolver {
  EnvironmentCredentialResolver({Map<String, String>? environment})
    : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  @override
  Future<CredentialValue?> resolve(String handle) async {
    if (!handle.startsWith('env:DEVEX_')) {
      throw const FormatException('Unsupported credential handle');
    }
    final value = _environment[handle.substring('env:'.length)];
    return value == null ? null : CredentialValue(value);
  }
}

abstract interface class GatewayAddressResolver {
  Future<List<InternetAddress>> lookup(String host);
}

final class SystemGatewayAddressResolver implements GatewayAddressResolver {
  const SystemGatewayAddressResolver();

  @override
  Future<List<InternetAddress>> lookup(String host) =>
      InternetAddress.lookup(host);
}

final class SafeHttpGatewayUpstreamHandler implements UpstreamHandlerPort {
  SafeHttpGatewayUpstreamHandler({
    required Map<UpstreamProfileId, GatewayUpstreamEndpoint> endpoints,
    required this.credentials,
    this.addresses = const SystemGatewayAddressResolver(),
  }) : endpoints = Map<UpstreamProfileId, GatewayUpstreamEndpoint>.unmodifiable(
         endpoints,
       );

  final Map<UpstreamProfileId, GatewayUpstreamEndpoint> endpoints;
  final CredentialResolver credentials;
  final GatewayAddressResolver addresses;

  @override
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  }) async {
    final profileId = route.upstreamProfileId;
    final endpoint = profileId == null ? null : endpoints[profileId];
    if (endpoint == null || route.policy != GatewayRoutePolicy.upstreamOnly) {
      throw StateError('Route has no allowlisted upstream');
    }
    return _send(endpoint, request).timeout(endpoint.timeout);
  }

  Future<GatewayMockResult> _send(
    GatewayUpstreamEndpoint endpoint,
    GatewayRequest request,
  ) async {
    final resolved = await addresses.lookup(endpoint.allowedHost);
    if (resolved.isEmpty) throw StateError('Upstream DNS returned no address');
    final permitted =
        resolved
            .where(
              (address) =>
                  endpoint.allowPrivateAddresses ||
                  !_isPrivateOrReserved(address),
            )
            .toList(growable: false)
          ..sort((left, right) => left.address.compareTo(right.address));
    if (permitted.length != resolved.length || permitted.isEmpty) {
      throw StateError('Upstream DNS resolved to a forbidden address');
    }
    final pinnedAddress = permitted.first;
    final target = endpoint.baseUri.replace(
      path: _joinPaths(endpoint.baseUri.path, request.path),
      queryParameters: request.query.isEmpty ? null : request.query,
    );
    if (target.host.toLowerCase() != endpoint.allowedHost.toLowerCase()) {
      throw StateError('Upstream host escaped its allowlist');
    }
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = endpoint.timeout
      ..findProxy = ((Uri _) => 'DIRECT')
      ..connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) =>
          _connectPinned(uri, pinnedAddress);
    try {
      final outbound = await client.openUrl(request.method, target);
      outbound.followRedirects = false;
      outbound.persistentConnection = false;
      if (request.body.isNotEmpty) {
        outbound.headers.contentType = ContentType.binary;
        outbound.contentLength = request.body.length;
        outbound.add(request.body);
      }
      final handle = endpoint.credentialHandle;
      if (handle != null) {
        final credential = await credentials.resolve(handle);
        if (credential == null) {
          throw StateError('Required upstream credential is unavailable');
        }
        outbound.headers.set(endpoint.credentialHeader, credential.value);
      }
      final response = await outbound.close();
      if (response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400)) {
        throw StateError('Upstream redirects are forbidden');
      }
      final contentEncoding = response.headers.value('content-encoding');
      if (contentEncoding != null &&
          contentEncoding.toLowerCase() != 'identity') {
        throw StateError('Encoded upstream responses are forbidden');
      }
      final body = await _readBounded(response, endpoint.maxResponseBytes);
      return GatewayMockResult(
        status: response.statusCode,
        headers: _safeResponseHeaders(response.headers),
        body: body,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<ConnectionTask<Socket>> _connectPinned(
    Uri uri,
    InternetAddress address,
  ) async {
    final port = uri.hasPort
        ? uri.port
        : uri.scheme == 'https'
        ? 443
        : 80;
    final task = await Socket.startConnect(address, port);
    if (uri.scheme == 'http') return task;
    final secure = task.socket.then<Socket>(
      (socket) => SecureSocket.secure(socket, host: uri.host),
    );
    return ConnectionTask.fromSocket<Socket>(secure, task.cancel);
  }

  Future<ImmutableBytes> _readBounded(
    HttpClientResponse response,
    int limit,
  ) async {
    final declared = response.contentLength;
    if (declared > limit) throw StateError('Upstream response is oversized');
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response) {
      length += chunk.length;
      if (length > limit) throw StateError('Upstream response is oversized');
      builder.add(chunk);
    }
    return ImmutableBytes.copyOf(builder.takeBytes());
  }

  Map<String, String> _safeResponseHeaders(HttpHeaders source) {
    const allowed = <String>{
      'cache-control',
      'content-language',
      'content-type',
      'etag',
      'last-modified',
    };
    return <String, String>{
      for (final name in allowed)
        if (source.value(name) case final String value) name: value,
    };
  }

  String _joinPaths(String prefix, String requestPath) {
    final normalizedPrefix = prefix == '/' || prefix.isEmpty
        ? ''
        : prefix.endsWith('/')
        ? prefix.substring(0, prefix.length - 1)
        : prefix;
    return '$normalizedPrefix$requestPath';
  }

  bool _isPrivateOrReserved(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      return _isPrivateOrReservedV4(bytes);
    }
    final unspecifiedOrLoopback = bytes.take(15).every((byte) => byte == 0);
    final mappedV4 =
        bytes.take(10).every((byte) => byte == 0) &&
        bytes[10] == 0xff &&
        bytes[11] == 0xff;
    return unspecifiedOrLoopback ||
        (mappedV4 && _isPrivateOrReservedV4(bytes.sublist(12))) ||
        (bytes[0] & 0xfe) == 0xfc ||
        (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
        bytes[0] == 0xff ||
        (bytes[0] == 0x20 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0x0d &&
            bytes[3] == 0xb8);
  }

  bool _isPrivateOrReservedV4(List<int> bytes) {
    final first = bytes[0];
    final second = bytes[1];
    return first == 0 ||
        first == 10 ||
        first == 127 ||
        first >= 224 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 198 && (second == 18 || second == 19));
  }
}

final class LocalGatewayConfigurationLoader {
  const LocalGatewayConfigurationLoader();

  Map<UpstreamProfileId, GatewayUpstreamEndpoint> load({
    required String workspaceRoot,
    String relativePath = 'devex.local.yaml',
  }) {
    final document = loadDocument(
      workspaceRoot: workspaceRoot,
      relativePath: relativePath,
    );
    return parseDocument(document);
  }

  /// Interprets the already loaded local document. Composition roots should
  /// prefer this API so feature modules never reopen configuration files.
  Map<UpstreamProfileId, GatewayUpstreamEndpoint> parseDocument(
    Map<String, Object?> document,
  ) {
    if (document.isEmpty || document['schemaVersion'] == 2) {
      return const <UpstreamProfileId, GatewayUpstreamEndpoint>{};
    }
    final gateway = _object(document['gateway'], r'$.gateway');
    final rawUpstreams = gateway['upstreams'];
    if (rawUpstreams == null) {
      return const <UpstreamProfileId, GatewayUpstreamEndpoint>{};
    }
    final upstreams = _object(rawUpstreams, r'$.gateway.upstreams');
    final output = <UpstreamProfileId, GatewayUpstreamEndpoint>{};
    for (final entry in upstreams.entries) {
      final value = _object(entry.value, r'$.gateway.upstreams.${entry.key}');
      _only(value, const <String>{
        'baseUrl',
        'allowedHost',
        'environment',
        'allowPrivateAddresses',
        'credentialHandle',
        'credentialHeader',
        'maxResponseBytes',
        'timeoutMilliseconds',
      }, r'$.gateway.upstreams.${entry.key}');
      final id = UpstreamProfileId(entry.key);
      output[id] = GatewayUpstreamEndpoint(
        profileId: id,
        baseUri: Uri.parse(_string(value, 'baseUrl')),
        allowedHost: _string(value, 'allowedHost'),
        environment: UpstreamEnvironment.values.byName(
          _string(value, 'environment'),
        ),
        allowPrivateAddresses: _optionalBool(value, 'allowPrivateAddresses'),
        credentialHandle: _optionalString(value, 'credentialHandle'),
        credentialHeader:
            _optionalString(value, 'credentialHeader') ?? 'authorization',
        maxResponseBytes:
            _optionalInt(value, 'maxResponseBytes') ?? 1024 * 1024,
        timeout: Duration(
          milliseconds: _optionalInt(value, 'timeoutMilliseconds') ?? 10000,
        ),
      );
    }
    return Map<UpstreamProfileId, GatewayUpstreamEndpoint>.unmodifiable(output);
  }

  /// Parses the ignored, machine-local configuration without resolving any
  /// credential handle. An absent file is represented by an empty document.
  Map<String, Object?> loadDocument({
    required String workspaceRoot,
    String relativePath = 'devex.local.yaml',
  }) => const WorkspaceConfigurationLoader().loadLocalConfiguration(
    workspaceRoot: workspaceRoot,
    relativePath: relativePath,
  );

  Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }

  void _only(Map<String, Object?> value, Set<String> allowed, String path) {
    for (final key in value.keys) {
      if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
    }
  }

  String _string(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item is! String || item.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return item;
  }

  String? _optionalString(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item == null) return null;
    if (item is! String || item.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return item;
  }

  int? _optionalInt(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item == null) return null;
    if (item is! int) throw FormatException('$key must be an integer');
    return item;
  }

  bool _optionalBool(Map<String, Object?> value, String key) {
    final item = value[key];
    if (item == null) return false;
    if (item is! bool) throw FormatException('$key must be a boolean');
    return item;
  }
}
