import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../storage/filesystem_workspace_store.dart';
import 'safe_http_upstream.dart';

enum RemoteConfigState { missing, empty, incomplete, invalid, ready }

final class RemoteConfigProviderConfiguration {
  RemoteConfigProviderConfiguration({
    required this.id,
    required this.endpoint,
    required this.requestPath,
    Map<String, List<String>> query = const <String, List<String>>{},
  }) : query = Map<String, List<String>>.unmodifiable(<String, List<String>>{
         for (final entry in query.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }) {
    OpaqueId.validate(id, 'RemoteConfigProvider');
    if (!requestPath.startsWith('/')) {
      throw ArgumentError('Invalid provider ID or requestPath');
    }
  }

  final String id;
  final GatewayUpstreamEndpoint endpoint;
  final String requestPath;
  final Map<String, List<String>> query;

  Map<String, Object?> redactedStatus() => <String, Object?>{
    'providerId': id,
    'upstreamProfileId': endpoint.profileId.value,
    'requestPath': requestPath,
    'queryKeys': query.keys.toList(growable: false)..sort(),
    'endpoint': endpoint.redactedStatus(),
  };
}

/// Loads generic provider mappings from the same ignored local configuration
/// as Gateway upstreams. It never resolves or serializes credential values.
final class LocalRemoteConfigProviderLoader {
  const LocalRemoteConfigProviderLoader();

  Map<String, RemoteConfigProviderConfiguration> load({
    required String workspaceRoot,
    String relativePath = 'workspace.local.yaml',
  }) {
    const local = LocalGatewayConfigurationLoader();
    final document = local.loadDocument(
      workspaceRoot: workspaceRoot,
      relativePath: relativePath,
    );
    return parseDocument(document);
  }

  /// Interprets an immutable local document supplied by the composition root.
  Map<String, RemoteConfigProviderConfiguration> parseDocument(
    Map<String, Object?> document,
  ) {
    const local = LocalGatewayConfigurationLoader();
    if (document.isEmpty || document['schemaVersion'] == 2) {
      return const <String, RemoteConfigProviderConfiguration>{};
    }
    final endpoints = local.parseDocument(document);
    final gateway = _object(document['gateway'], r'$.gateway');
    final rawProviders = gateway['providers'];
    if (rawProviders == null) {
      return const <String, RemoteConfigProviderConfiguration>{};
    }
    final providers = _object(rawProviders, r'$.gateway.providers');
    final output = <String, RemoteConfigProviderConfiguration>{};
    for (final entry in providers.entries) {
      OpaqueId.validate(entry.key, 'RemoteConfigProvider');
      final path = r'$.gateway.providers.' + entry.key;
      final value = _object(entry.value, path);
      _only(value, const <String>{
        'upstreamProfileId',
        'requestPath',
        'query',
      }, path);
      final profileId = UpstreamProfileId(
        _requiredString(value, 'upstreamProfileId', path),
      );
      final endpoint = endpoints[profileId];
      if (endpoint == null) {
        throw FormatException(
          '$path.upstreamProfileId references an unknown upstream',
        );
      }
      output[entry.key] = RemoteConfigProviderConfiguration(
        id: entry.key,
        endpoint: endpoint,
        requestPath: _requiredString(value, 'requestPath', path),
        query: _query(value['query'], '$path.query'),
      );
    }
    return Map<String, RemoteConfigProviderConfiguration>.unmodifiable(output);
  }

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

  String _requiredString(Map<String, Object?> value, String key, String path) {
    final item = value[key];
    if (item is! String || item.isEmpty) {
      throw FormatException('$path.$key must be a non-empty string');
    }
    return item;
  }

  Map<String, List<String>> _query(Object? value, String path) {
    if (value == null) return const <String, List<String>>{};
    final source = _object(value, path);
    final result = <String, List<String>>{};
    for (final entry in source.entries) {
      if (entry.key.isEmpty) throw FormatException('$path key is empty');
      final raw = entry.value;
      final values = raw is String
          ? <String>[raw]
          : raw is List<Object?> && raw.every((item) => item is String)
          ? raw.cast<String>()
          : throw FormatException('$path.${entry.key} must be text or a list');
      if (values.isEmpty || values.any((item) => item.isEmpty)) {
        throw FormatException('$path.${entry.key} must not be empty');
      }
      result[entry.key] = List<String>.unmodifiable(values);
    }
    return Map<String, List<String>>.unmodifiable(result);
  }
}

final class RemoteConfigAssessment {
  const RemoteConfigAssessment({
    required this.providerId,
    required this.state,
    required this.observedAt,
    required this.statusCode,
    required this.message,
    this.document,
  });

  final String providerId;
  final RemoteConfigState state;
  final DateTime observedAt;
  final int? statusCode;
  final String message;
  final Map<String, Object?>? document;

  Digest? get documentDigest =>
      document == null ? null : Digest.semantic(document!);

  Map<String, Object?> toJson() => <String, Object?>{
    'providerId': providerId,
    'state': state.name,
    'observedAt': observedAt.toUtc().toIso8601String(),
    if (statusCode != null) 'statusCode': statusCode,
    'message': message,
    if (documentDigest != null) 'documentDigest': documentDigest!.value,
  };
}

abstract interface class RemoteConfigProviderPort {
  Future<RemoteConfigAssessment> fetch(
    RemoteConfigProviderConfiguration configuration,
  );
}

final class HttpJsonRemoteConfigProvider implements RemoteConfigProviderPort {
  HttpJsonRemoteConfigProvider({
    required this.credentials,
    required this.clock,
    this.addresses = const SystemGatewayAddressResolver(),
  });

  final CredentialResolver credentials;
  final Clock clock;
  final GatewayAddressResolver addresses;

  @override
  Future<RemoteConfigAssessment> fetch(
    RemoteConfigProviderConfiguration configuration,
  ) async {
    final route = GatewayRoute(
      id: GatewayRouteId('provider-fetch'),
      scopeId: GatewayScopeId('provider'),
      method: 'GET',
      pathTemplate: configuration.requestPath,
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{GatewayPresetId('provider')},
      policy: GatewayRoutePolicy.upstreamOnly,
      fixtureId: null,
      upstreamProfileId: configuration.endpoint.profileId,
    );
    try {
      final result =
          await SafeHttpGatewayUpstreamHandler(
            endpoints: <UpstreamProfileId, GatewayUpstreamEndpoint>{
              configuration.endpoint.profileId: configuration.endpoint,
            },
            credentials: credentials,
            addresses: addresses,
          ).handle(
            route: route,
            request: GatewayRequest(
              method: 'GET',
              path: configuration.requestPath,
              query: configuration.query,
              body: const <int>[],
            ),
            pathParameters: const <String, String>{},
            runtimeState: const <String, Object?>{},
          );
      return _assess(configuration.id, result.status, result.body);
    } on Object {
      return RemoteConfigAssessment(
        providerId: configuration.id,
        state: RemoteConfigState.invalid,
        observedAt: clock.nowUtc(),
        statusCode: null,
        message: 'provider request failed',
      );
    }
  }

  RemoteConfigAssessment _assess(
    String providerId,
    int statusCode,
    List<int> bytes,
  ) {
    RemoteConfigAssessment result(
      RemoteConfigState state,
      String message, {
      Map<String, Object?>? document,
    }) => RemoteConfigAssessment(
      providerId: providerId,
      state: state,
      observedAt: clock.nowUtc(),
      statusCode: statusCode,
      message: message,
      document: document,
    );

    if (statusCode == 404) {
      return result(RemoteConfigState.missing, 'provider document is missing');
    }
    if (statusCode < 200 || statusCode >= 300) {
      return result(RemoteConfigState.invalid, 'provider returned non-success');
    }
    if (bytes.isEmpty) {
      return result(
        RemoteConfigState.empty,
        'provider document is empty',
        document: const <String, Object?>{
          'schemaVersion': 1,
          'items': <Object?>[],
        },
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return result(RemoteConfigState.invalid, 'provider JSON is invalid');
    }
    if (decoded is! Map<String, Object?>) {
      return result(
        RemoteConfigState.invalid,
        'provider root is not an object',
      );
    }
    if (decoded.keys.any(
      (key) => !const <String>{'schemaVersion', 'items'}.contains(key),
    )) {
      return result(RemoteConfigState.invalid, 'provider has unknown fields');
    }
    if (decoded['schemaVersion'] == null || decoded['items'] == null) {
      return result(
        RemoteConfigState.incomplete,
        'provider fields are missing',
      );
    }
    if (decoded['schemaVersion'] != 1 || decoded['items'] is! List<Object?>) {
      return result(RemoteConfigState.invalid, 'provider fields are invalid');
    }
    final items = decoded['items']! as List<Object?>;
    if (items.isEmpty) {
      return result(
        RemoteConfigState.empty,
        'provider has no items',
        document: const <String, Object?>{
          'schemaVersion': 1,
          'items': <Object?>[],
        },
      );
    }
    var nodes = 0;
    for (final item in items) {
      if (item is! Map<String, Object?> ||
          item['id'] is! String ||
          (item['id']! as String).isEmpty) {
        return result(
          RemoteConfigState.incomplete,
          'provider item is incomplete',
        );
      }
      if (!_safeJson(item, depth: 0, nodes: () => nodes += 1)) {
        return result(
          RemoteConfigState.invalid,
          'provider item violates data hygiene limits',
        );
      }
    }
    final normalized = <String, Object?>{'schemaVersion': 1, 'items': items};
    try {
      const JcsCanonicalizer().canonicalize(normalized);
    } on CanonicalJsonException {
      return result(RemoteConfigState.invalid, 'provider JSON is not I-JSON');
    }
    return result(
      RemoteConfigState.ready,
      'provider is ready',
      document: normalized,
    );
  }

  bool _safeJson(
    Object? value, {
    required int depth,
    required int Function() nodes,
  }) {
    if (depth > 32 || nodes() > 100000) return false;
    if (value == null || value is String || value is bool || value is num) {
      return true;
    }
    if (value is List<Object?>) {
      return value.every(
        (item) => _safeJson(item, depth: depth + 1, nodes: nodes),
      );
    }
    if (value is Map<String, Object?>) {
      for (final entry in value.entries) {
        final normalizedKey = entry.key.toLowerCase();
        if (normalizedKey.contains('secret') ||
            normalizedKey.contains('token') ||
            normalizedKey.contains('password') ||
            normalizedKey == 'authorization' ||
            normalizedKey == 'cookie') {
          return false;
        }
        if (!_safeJson(entry.value, depth: depth + 1, nodes: nodes)) {
          return false;
        }
      }
      return true;
    }
    return false;
  }
}

final class RemoteConfigSyncResult {
  const RemoteConfigSyncResult({
    required this.observed,
    required this.activeDocumentDigest,
  });

  final RemoteConfigAssessment observed;
  final Digest? activeDocumentDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'observed': observed.toJson(),
    if (activeDocumentDigest != null)
      'activeDocumentDigest': activeDocumentDigest!.value,
  };
}

final class LocalRemoteConfigRepository {
  const LocalRemoteConfigRepository(this.store);

  final FileSystemWorkspaceStore store;

  RemoteConfigSyncResult commit(RemoteConfigAssessment assessment) {
    OpaqueId.validate(assessment.providerId, 'RemoteConfigProvider');
    return store.withExclusiveLock(() {
      final path = 'gateway/providers/${assessment.providerId}/state.json';
      Digest? active = _currentActive(path);
      if ((assessment.state == RemoteConfigState.ready ||
              assessment.state == RemoteConfigState.empty) &&
          assessment.document != null) {
        final canonical = utf8.encode(
          const JcsCanonicalizer().canonicalize(assessment.document),
        );
        active = store.putBlob(canonical);
      }
      final state = <String, Object?>{
        'schemaVersion': 1,
        'providerId': assessment.providerId,
        'observed': assessment.toJson(),
        if (active != null) 'activeDocumentDigest': active.value,
      };
      store.atomicWrite(
        path,
        utf8.encode('${const JcsCanonicalizer().canonicalize(state)}\n'),
      );
      return RemoteConfigSyncResult(
        observed: assessment,
        activeDocumentDigest: active,
      );
    });
  }

  Digest? _currentActive(String path) {
    final bytes = store.readStateBytes(path);
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Remote config state is invalid');
    }
    final value = decoded['activeDocumentDigest'];
    return value == null
        ? null
        : value is String
        ? Digest(value)
        : throw const FormatException('activeDocumentDigest is invalid');
  }
}

final class RemoteConfigSyncService {
  const RemoteConfigSyncService({
    required this.provider,
    required this.repository,
  });

  final RemoteConfigProviderPort provider;
  final LocalRemoteConfigRepository repository;

  Future<RemoteConfigSyncResult> sync(
    RemoteConfigProviderConfiguration configuration,
  ) async => repository.commit(await provider.fetch(configuration));
}
