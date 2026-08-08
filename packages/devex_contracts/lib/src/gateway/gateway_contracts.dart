import 'dart:collection';

import '../catalog/catalog_contracts.dart';
import '../digest.dart';
import '../evidence/evidence_contracts.dart';
import '../immutable_bytes.dart';

final class GatewayScopeId extends OpaqueId {
  factory GatewayScopeId(String value) {
    OpaqueId.validate(value, 'GatewayScope');
    return GatewayScopeId._(value);
  }

  const GatewayScopeId._(super.value);
}

final class GatewayPresetId extends OpaqueId {
  factory GatewayPresetId(String value) {
    OpaqueId.validate(value, 'GatewayPreset');
    return GatewayPresetId._(value);
  }

  const GatewayPresetId._(super.value);
}

final class GatewayRouteId extends OpaqueId {
  factory GatewayRouteId(String value) {
    OpaqueId.validate(value, 'GatewayRoute');
    return GatewayRouteId._(value);
  }

  const GatewayRouteId._(super.value);
}

final class GatewayFixtureId extends OpaqueId {
  factory GatewayFixtureId(String value) {
    OpaqueId.validate(value, 'GatewayFixture');
    return GatewayFixtureId._(value);
  }

  const GatewayFixtureId._(super.value);
}

final class UpstreamProfileId extends OpaqueId {
  factory UpstreamProfileId(String value) {
    OpaqueId.validate(value, 'UpstreamProfile');
    return UpstreamProfileId._(value);
  }

  const UpstreamProfileId._(super.value);
}

enum GatewayRoutePolicy {
  catalogControlled,
  mockWhenOverridden,
  localOnly,
  upstreamOnly,
}

enum GatewayRoutingDecision { mock, passthrough, deny }

enum GatewayOutcome { mock, passthrough, denied, unmatched, error }

enum GatewaySessionState { created, running, stopped, failed }

enum UpstreamEnvironment { development, test, staging }

final class GatewaySession {
  GatewaySession({
    required this.id,
    required this.ownerSessionId,
    required this.planDigest,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.activeScopeId,
    this.terminalReason,
  }) {
    _gatewayRuntimeId(id, 'GatewaySession.id');
    _gatewayRuntimeId(ownerSessionId, 'GatewaySession.ownerSessionId');
    if (updatedAt.toUtc().isBefore(createdAt.toUtc())) {
      throw ArgumentError('GatewaySession.updatedAt precedes createdAt');
    }
    if (terminalReason != null && terminalReason!.trim().isEmpty) {
      throw ArgumentError(
        'GatewaySession.terminalReason must be non-empty when present',
      );
    }
    switch (state) {
      case GatewaySessionState.created:
        if (activeScopeId != null || terminalReason != null) {
          throw ArgumentError(
            'Created GatewaySession cannot have active or terminal state',
          );
        }
      case GatewaySessionState.running:
        if (activeScopeId == null || terminalReason != null) {
          throw ArgumentError(
            'Running GatewaySession requires activeScopeId and no terminalReason',
          );
        }
      case GatewaySessionState.stopped:
        if (activeScopeId != null) {
          throw ArgumentError(
            'Stopped GatewaySession cannot retain activeScopeId',
          );
        }
      case GatewaySessionState.failed:
        if (activeScopeId != null ||
            terminalReason == null ||
            terminalReason!.trim().isEmpty) {
          throw ArgumentError(
            'Failed GatewaySession requires terminalReason and no activeScopeId',
          );
        }
    }
  }

  static const int schemaVersion = 1;

  final String id;
  final String ownerSessionId;
  final Digest planDigest;
  final GatewaySessionState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final GatewayScopeId? activeScopeId;
  final String? terminalReason;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'GatewaySession',
    'id': id,
    'ownerSessionId': ownerSessionId,
    'planDigest': planDigest.value,
    'state': state.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (activeScopeId != null) 'activeScopeId': activeScopeId!.value,
    if (terminalReason != null) 'terminalReason': terminalReason,
    if (includeDigest) 'digest': digest.value,
  };

  factory GatewaySession.fromJson(Object? value) {
    final json = _object(value, 'GatewaySession');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'ownerSessionId',
      'planDigest',
      'state',
      'createdAt',
      'updatedAt',
      'activeScopeId',
      'terminalReason',
      'digest',
    }, 'GatewaySession');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'GatewaySession') {
      throw const FormatException('Invalid GatewaySession version or kind');
    }
    final session = GatewaySession(
      id: _string(json, 'id', 'GatewaySession'),
      ownerSessionId: _string(json, 'ownerSessionId', 'GatewaySession'),
      planDigest: Digest(_string(json, 'planDigest', 'GatewaySession')),
      state: _enumValue(
        GatewaySessionState.values,
        _string(json, 'state', 'GatewaySession'),
        'GatewaySession.state',
      ),
      createdAt: _gatewayDateTime(json, 'createdAt', 'GatewaySession'),
      updatedAt: _gatewayDateTime(json, 'updatedAt', 'GatewaySession'),
      activeScopeId: json['activeScopeId'] == null
          ? null
          : GatewayScopeId(_string(json, 'activeScopeId', 'GatewaySession')),
      terminalReason: _optionalString(json, 'terminalReason', 'GatewaySession'),
    );
    if (Digest(_string(json, 'digest', 'GatewaySession')) != session.digest) {
      throw const FormatException('GatewaySession digest mismatch');
    }
    return session;
  }
}

final class UpstreamProfile {
  UpstreamProfile({
    required this.id,
    required this.environment,
    required Map<String, Uri> origins,
    required this.updatedAt,
    this.credentialHandleId,
  }) : origins = Map<String, Uri>.unmodifiable(
         Map<String, Uri>.fromEntries(
           origins.entries.toList()
             ..sort((left, right) => left.key.compareTo(right.key)),
         ),
       ) {
    if (this.origins.isEmpty) {
      throw ArgumentError('UpstreamProfile requires at least one origin');
    }
    for (final entry in this.origins.entries) {
      if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(entry.key)) {
        throw FormatException('Invalid UpstreamProfile alias ${entry.key}');
      }
      final origin = entry.value;
      if (!const <String>{'http', 'https'}.contains(origin.scheme) ||
          origin.host.isEmpty ||
          origin.userInfo.isNotEmpty ||
          origin.query.isNotEmpty ||
          origin.fragment.isNotEmpty ||
          (origin.path.isNotEmpty && origin.path != '/')) {
        throw FormatException(
          'UpstreamProfile origin ${entry.key} must be a credential-free origin',
        );
      }
    }
    if (credentialHandleId != null) {
      _gatewayRuntimeId(
        credentialHandleId!,
        'UpstreamProfile.credentialHandleId',
      );
    }
  }

  static const int schemaVersion = 1;

  final UpstreamProfileId id;
  final UpstreamEnvironment environment;
  final Map<String, Uri> origins;
  final DateTime updatedAt;
  final String? credentialHandleId;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'UpstreamProfile',
    'id': id.value,
    'environment': environment.name,
    'origins': <String, String>{
      for (final entry in origins.entries) entry.key: entry.value.toString(),
    },
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (credentialHandleId != null) 'credentialHandleId': credentialHandleId,
    if (includeDigest) 'digest': digest.value,
  };

  factory UpstreamProfile.fromJson(Object? value) {
    final json = _object(value, 'UpstreamProfile');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'environment',
      'origins',
      'updatedAt',
      'credentialHandleId',
      'digest',
    }, 'UpstreamProfile');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'UpstreamProfile') {
      throw const FormatException('Invalid UpstreamProfile version or kind');
    }
    final profile = UpstreamProfile(
      id: UpstreamProfileId(_string(json, 'id', 'UpstreamProfile')),
      environment: _enumValue(
        UpstreamEnvironment.values,
        _string(json, 'environment', 'UpstreamProfile'),
        'UpstreamProfile.environment',
      ),
      origins: _uriMap(json['origins'], 'UpstreamProfile.origins'),
      updatedAt: _gatewayDateTime(json, 'updatedAt', 'UpstreamProfile'),
      credentialHandleId: _optionalString(
        json,
        'credentialHandleId',
        'UpstreamProfile',
      ),
    );
    if (Digest(_string(json, 'digest', 'UpstreamProfile')) != profile.digest) {
      throw const FormatException('UpstreamProfile digest mismatch');
    }
    return profile;
  }
}

final class GatewayFaultProfile {
  GatewayFaultProfile({
    this.fixedLatencyMilliseconds = 0,
    this.forcedStatus,
    this.disconnect = false,
  }) {
    if (fixedLatencyMilliseconds < 0 || fixedLatencyMilliseconds > 30000) {
      throw ArgumentError.value(
        fixedLatencyMilliseconds,
        'fixedLatencyMilliseconds',
      );
    }
    if (forcedStatus != null && (forcedStatus! < 100 || forcedStatus! > 599)) {
      throw ArgumentError.value(forcedStatus, 'forcedStatus');
    }
  }

  final int fixedLatencyMilliseconds;
  final int? forcedStatus;
  final bool disconnect;

  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'fixedLatencyMilliseconds': fixedLatencyMilliseconds,
    if (forcedStatus != null) 'forcedStatus': forcedStatus,
    'disconnect': disconnect,
  };

  factory GatewayFaultProfile.fromJson(Object? value) {
    final json = _object(value, 'GatewayFaultProfile');
    _only(json, const <String>{
      'fixedLatencyMilliseconds',
      'forcedStatus',
      'disconnect',
    }, 'GatewayFaultProfile');
    return GatewayFaultProfile(
      fixedLatencyMilliseconds: _integer(
        json,
        'fixedLatencyMilliseconds',
        'GatewayFaultProfile',
      ),
      forcedStatus: _optionalInteger(
        json,
        'forcedStatus',
        'GatewayFaultProfile',
      ),
      disconnect: _boolean(json, 'disconnect', 'GatewayFaultProfile'),
    );
  }
}

final class GatewayFixture {
  GatewayFixture({
    required this.id,
    required this.status,
    required Map<String, String> headers,
    required this.bodyDigest,
    required this.bodySize,
    required this.mediaType,
  }) : headers = _headers(headers) {
    if (status < 100 || status > 599) {
      throw ArgumentError.value(status, 'status');
    }
    if (bodySize < 0 || bodySize > 256 * 1024) {
      throw ArgumentError.value(bodySize, 'bodySize', 'must be <= 256 KiB');
    }
    if (mediaType.trim().isEmpty) {
      throw ArgumentError.value(mediaType, 'mediaType');
    }
  }

  final GatewayFixtureId id;
  final int status;
  final Map<String, String> headers;
  final Digest bodyDigest;
  final int bodySize;
  final String mediaType;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'status': status,
    'headers': _sortedStrings(headers),
    'bodyDigest': bodyDigest.value,
    'bodySize': bodySize,
    'mediaType': mediaType,
  };

  factory GatewayFixture.fromJson(Object? value) {
    final json = _object(value, 'GatewayFixture');
    _only(json, const <String>{
      'id',
      'status',
      'headers',
      'bodyDigest',
      'bodySize',
      'mediaType',
    }, 'GatewayFixture');
    return GatewayFixture(
      id: GatewayFixtureId(_string(json, 'id', 'GatewayFixture')),
      status: _integer(json, 'status', 'GatewayFixture'),
      headers: _stringMap(json['headers'], 'GatewayFixture.headers'),
      bodyDigest: Digest(_string(json, 'bodyDigest', 'GatewayFixture')),
      bodySize: _integer(json, 'bodySize', 'GatewayFixture'),
      mediaType: _string(json, 'mediaType', 'GatewayFixture'),
    );
  }
}

final class GatewayRoute {
  GatewayRoute({
    required this.id,
    required this.scopeId,
    required String method,
    required this.pathTemplate,
    required Map<String, String> requiredQuery,
    required Set<GatewayPresetId> appliesTo,
    required this.policy,
    required this.fixtureId,
    this.upstreamProfileId,
    this.faultProfile,
  }) : method = _httpMethod(method),
       requiredQuery = Map<String, String>.unmodifiable(requiredQuery),
       appliesTo = Set<GatewayPresetId>.unmodifiable(appliesTo) {
    _validatePathTemplate(pathTemplate);
    if (appliesTo.isEmpty) {
      throw ArgumentError('GatewayRoute.appliesTo must not be empty');
    }
    for (final entry in requiredQuery.entries) {
      if (entry.key.isEmpty || entry.value.isEmpty) {
        throw ArgumentError('Required query entries must be non-empty');
      }
    }
    if (policy != GatewayRoutePolicy.upstreamOnly && fixtureId == null) {
      throw ArgumentError('Mock-capable route requires fixtureId');
    }
    if (policy == GatewayRoutePolicy.upstreamOnly && fixtureId != null) {
      throw ArgumentError('upstreamOnly route cannot declare fixtureId');
    }
    if (policy == GatewayRoutePolicy.upstreamOnly &&
        upstreamProfileId == null) {
      throw ArgumentError('upstreamOnly route requires upstreamProfileId');
    }
  }

  final GatewayRouteId id;
  final GatewayScopeId scopeId;
  final String method;
  final String pathTemplate;
  final Map<String, String> requiredQuery;
  final Set<GatewayPresetId> appliesTo;
  final GatewayRoutePolicy policy;
  final GatewayFixtureId? fixtureId;
  final UpstreamProfileId? upstreamProfileId;
  final GatewayFaultProfile? faultProfile;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scopeId': scopeId.value,
    'method': method,
    'pathTemplate': pathTemplate,
    'requiredQuery': _sortedStrings(requiredQuery),
    'appliesTo': appliesTo.map((value) => value.value).toList()..sort(),
    'policy': policy.name,
    if (fixtureId != null) 'fixtureId': fixtureId!.value,
    if (upstreamProfileId != null)
      'upstreamProfileId': upstreamProfileId!.value,
    if (faultProfile != null) 'faultProfile': faultProfile!.toJson(),
  };

  factory GatewayRoute.fromJson(Object? value) {
    final json = _object(value, 'GatewayRoute');
    _only(json, const <String>{
      'id',
      'scopeId',
      'method',
      'pathTemplate',
      'requiredQuery',
      'appliesTo',
      'policy',
      'fixtureId',
      'upstreamProfileId',
      'faultProfile',
    }, 'GatewayRoute');
    return GatewayRoute(
      id: GatewayRouteId(_string(json, 'id', 'GatewayRoute')),
      scopeId: GatewayScopeId(_string(json, 'scopeId', 'GatewayRoute')),
      method: _string(json, 'method', 'GatewayRoute'),
      pathTemplate: _string(json, 'pathTemplate', 'GatewayRoute'),
      requiredQuery: _stringMap(
        json['requiredQuery'],
        'GatewayRoute.requiredQuery',
      ),
      appliesTo: _stringList(
        json['appliesTo'],
        'GatewayRoute.appliesTo',
      ).map(GatewayPresetId.new).toSet(),
      policy: _enumValue(
        GatewayRoutePolicy.values,
        _string(json, 'policy', 'GatewayRoute'),
        'GatewayRoute.policy',
      ),
      fixtureId: _optionalFixtureId(json, 'fixtureId', 'GatewayRoute'),
      upstreamProfileId: _optionalUpstreamProfileId(
        json,
        'upstreamProfileId',
        'GatewayRoute',
      ),
      faultProfile: json['faultProfile'] == null
          ? null
          : GatewayFaultProfile.fromJson(json['faultProfile']),
    );
  }
}

final class GatewayScope {
  GatewayScope({
    required this.id,
    required this.displayName,
    required List<GatewayRouteId> routeIds,
  }) : routeIds = _uniqueSortedIds(routeIds, 'GatewayScope.routeIds') {
    if (displayName.trim().isEmpty) {
      throw ArgumentError.value(displayName, 'displayName');
    }
    if (routeIds.isEmpty) throw ArgumentError('GatewayScope requires routes');
  }

  final GatewayScopeId id;
  final String displayName;
  final List<GatewayRouteId> routeIds;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
    'routeIds': routeIds.map((value) => value.value).toList(),
  };

  factory GatewayScope.fromJson(Object? value) {
    final json = _object(value, 'GatewayScope');
    _only(json, const <String>{
      'id',
      'displayName',
      'routeIds',
    }, 'GatewayScope');
    return GatewayScope(
      id: GatewayScopeId(_string(json, 'id', 'GatewayScope')),
      displayName: _string(json, 'displayName', 'GatewayScope'),
      routeIds: _stringList(
        json['routeIds'],
        'GatewayScope.routeIds',
      ).map(GatewayRouteId.new).toList(growable: false),
    );
  }
}

final class GatewayPreset {
  GatewayPreset({
    required this.id,
    required this.scopeId,
    required this.description,
    required List<GatewayRouteId> routeIds,
    Map<String, Object?> initialState = const <String, Object?>{},
  }) : routeIds = _uniqueSortedIds(routeIds, 'GatewayPreset.routeIds'),
       initialState = _freezeJson(initialState) as Map<String, Object?> {
    if (description.trim().isEmpty) {
      throw ArgumentError.value(description, 'description');
    }
  }

  final GatewayPresetId id;
  final GatewayScopeId scopeId;
  final String description;
  final List<GatewayRouteId> routeIds;
  final Map<String, Object?> initialState;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'scopeId': scopeId.value,
    'description': description,
    'routeIds': routeIds.map((value) => value.value).toList(),
    'initialState': initialState,
  };

  factory GatewayPreset.fromJson(Object? value) {
    final json = _object(value, 'GatewayPreset');
    _only(json, const <String>{
      'id',
      'scopeId',
      'description',
      'routeIds',
      'initialState',
    }, 'GatewayPreset');
    return GatewayPreset(
      id: GatewayPresetId(_string(json, 'id', 'GatewayPreset')),
      scopeId: GatewayScopeId(_string(json, 'scopeId', 'GatewayPreset')),
      description: _string(json, 'description', 'GatewayPreset'),
      routeIds: _stringList(
        json['routeIds'],
        'GatewayPreset.routeIds',
      ).map(GatewayRouteId.new).toList(growable: false),
      initialState: _object(json['initialState'], 'GatewayPreset.initialState'),
    );
  }
}

/// Host-owned, Studio-safe reference to a compiled Gateway plan in the CAS.
///
/// The descriptor exposes the identity and operational shape needed to select
/// a preset without leaking a workspace path or requiring users to copy an
/// implementation digest manually.
final class GatewayPlanArtifactDescriptor {
  const GatewayPlanArtifactDescriptor({
    required this.presetId,
    required this.description,
    required this.backendMode,
    required this.routeCount,
    required this.planDigest,
    required this.artifactDigest,
  });

  final GatewayPresetId presetId;
  final String description;
  final BackendMode backendMode;
  final int routeCount;
  final Digest planDigest;
  final Digest artifactDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'presetId': presetId.value,
    'description': description,
    'backendMode': backendMode.name,
    'routeCount': routeCount,
    'planDigest': planDigest.value,
    'artifactDigest': artifactDigest.value,
  };

  factory GatewayPlanArtifactDescriptor.fromJson(Object? value) {
    final json = _object(value, 'GatewayPlanArtifactDescriptor');
    _only(json, const <String>{
      'presetId',
      'description',
      'backendMode',
      'routeCount',
      'planDigest',
      'artifactDigest',
    }, 'GatewayPlanArtifactDescriptor');
    final routeCount = _integer(
      json,
      'routeCount',
      'GatewayPlanArtifactDescriptor',
    );
    if (routeCount < 0) {
      throw const FormatException(
        'GatewayPlanArtifactDescriptor.routeCount must be non-negative',
      );
    }
    return GatewayPlanArtifactDescriptor(
      presetId: GatewayPresetId(
        _string(json, 'presetId', 'GatewayPlanArtifactDescriptor'),
      ),
      description: _string(
        json,
        'description',
        'GatewayPlanArtifactDescriptor',
      ),
      backendMode: _enumValue(
        BackendMode.values,
        _string(json, 'backendMode', 'GatewayPlanArtifactDescriptor'),
        'GatewayPlanArtifactDescriptor.backendMode',
      ),
      routeCount: routeCount,
      planDigest: Digest(
        _string(json, 'planDigest', 'GatewayPlanArtifactDescriptor'),
      ),
      artifactDigest: Digest(
        _string(json, 'artifactDigest', 'GatewayPlanArtifactDescriptor'),
      ),
    );
  }
}

final class CompiledGatewayPlan {
  CompiledGatewayPlan({
    required this.scope,
    required this.preset,
    required List<GatewayRoute> routes,
    required List<GatewayFixture> fixtures,
    required this.backendMode,
    required this.networkContainment,
  }) : routes = List<GatewayRoute>.unmodifiable(
         List<GatewayRoute>.of(routes)
           ..sort((left, right) => left.id.value.compareTo(right.id.value)),
       ),
       fixtures = List<GatewayFixture>.unmodifiable(
         List<GatewayFixture>.of(fixtures)
           ..sort((left, right) => left.id.value.compareTo(right.id.value)),
       ) {
    if (scope.id != preset.scopeId) {
      throw ArgumentError('GatewayPreset does not belong to GatewayScope');
    }
    if (_duplicates(this.routes.map((route) => route.id)) ||
        _duplicates(this.fixtures.map((fixture) => fixture.id))) {
      throw ArgumentError('CompiledGatewayPlan IDs must be unique');
    }
    final scopeRoutes = scope.routeIds.toSet();
    final presetRoutes = preset.routeIds.toSet();
    final compiledRoutes = this.routes.map((route) => route.id).toSet();
    if (!scopeRoutes.containsAll(presetRoutes) ||
        presetRoutes.length != compiledRoutes.length ||
        !presetRoutes.containsAll(compiledRoutes)) {
      throw ArgumentError('Compiled routes must equal the preset route set');
    }
    for (final route in this.routes) {
      if (route.scopeId != scope.id || !route.appliesTo.contains(preset.id)) {
        throw ArgumentError(
          'Compiled route ${route.id} violates scope/appliesTo',
        );
      }
      if (backendMode == BackendMode.isolated &&
          route.policy == GatewayRoutePolicy.upstreamOnly) {
        throw ArgumentError('isolated plan cannot compile upstreamOnly routes');
      }
    }
    final fixtureIds = this.fixtures.map((fixture) => fixture.id).toSet();
    final referencedFixtures = this.routes
        .map((route) => route.fixtureId)
        .whereType<GatewayFixtureId>()
        .toSet();
    if (fixtureIds.length != referencedFixtures.length ||
        !fixtureIds.containsAll(referencedFixtures)) {
      throw ArgumentError('Compiled fixtures must equal referenced fixtures');
    }
    if (backendMode != BackendMode.none &&
        networkContainment != NetworkContainment.gatewayOnly) {
      throw ArgumentError('local Gateway plan reports gatewayOnly containment');
    }
  }

  static const int schemaVersion = 1;

  final GatewayScope scope;
  final GatewayPreset preset;
  final List<GatewayRoute> routes;
  final List<GatewayFixture> fixtures;
  final BackendMode backendMode;
  final NetworkContainment networkContainment;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'CompiledGatewayPlan',
    'scope': scope.toJson(),
    'preset': preset.toJson(),
    'routes': routes.map((value) => value.toJson()).toList(),
    'fixtures': fixtures.map((value) => value.toJson()).toList(),
    'backendMode': backendMode.name,
    'networkContainment': networkContainment.name,
    if (includeDigest) 'digest': digest.value,
  };

  factory CompiledGatewayPlan.fromJson(Object? value) {
    final json = _object(value, 'CompiledGatewayPlan');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'scope',
      'preset',
      'routes',
      'fixtures',
      'backendMode',
      'networkContainment',
      'digest',
    }, 'CompiledGatewayPlan');
    if (json['schemaVersion'] != 1 || json['kind'] != 'CompiledGatewayPlan') {
      throw const FormatException(
        'Invalid CompiledGatewayPlan version or kind',
      );
    }
    final plan = CompiledGatewayPlan(
      scope: GatewayScope.fromJson(json['scope']),
      preset: GatewayPreset.fromJson(json['preset']),
      routes: _list(
        json['routes'],
        'CompiledGatewayPlan.routes',
      ).map(GatewayRoute.fromJson).toList(growable: false),
      fixtures: _list(
        json['fixtures'],
        'CompiledGatewayPlan.fixtures',
      ).map(GatewayFixture.fromJson).toList(growable: false),
      backendMode: _enumValue(
        BackendMode.values,
        _string(json, 'backendMode', 'CompiledGatewayPlan'),
        'CompiledGatewayPlan.backendMode',
      ),
      networkContainment: _enumValue(
        NetworkContainment.values,
        _string(json, 'networkContainment', 'CompiledGatewayPlan'),
        'CompiledGatewayPlan.networkContainment',
      ),
    );
    if (Digest(_string(json, 'digest', 'CompiledGatewayPlan')) != plan.digest) {
      throw const FormatException('CompiledGatewayPlan digest mismatch');
    }
    return plan;
  }
}

final class RoutingTable {
  RoutingTable({
    required this.scopeId,
    required this.presetId,
    required Map<GatewayRouteId, GatewayRoutingDecision> entries,
  }) : entries = UnmodifiableMapView<GatewayRouteId, GatewayRoutingDecision>(
         Map<GatewayRouteId, GatewayRoutingDecision>.fromEntries(
           entries.entries.toList()
             ..sort((left, right) => left.key.value.compareTo(right.key.value)),
         ),
       );

  final GatewayScopeId scopeId;
  final GatewayPresetId presetId;
  final Map<GatewayRouteId, GatewayRoutingDecision> entries;

  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'scopeId': scopeId.value,
    'presetId': presetId.value,
    'entries': <String, String>{
      for (final entry in entries.entries) entry.key.value: entry.value.name,
    },
  };
}

final class GatewayRequest {
  GatewayRequest({
    required String method,
    required this.path,
    required Map<String, List<String>> query,
    required List<int> body,
  }) : method = _httpMethod(method),
       query = Map<String, List<String>>.unmodifiable(<String, List<String>>{
         for (final entry in query.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }),
       body = ImmutableBytes.copyOf(body) {
    if (!path.startsWith('/') || Uri.tryParse(path) == null) {
      throw FormatException('GatewayRequest.path must be an absolute path');
    }
    if (body.length > 256 * 1024) {
      throw const FormatException('GatewayRequest body exceeds 256 KiB');
    }
  }

  final String method;
  final String path;
  final Map<String, List<String>> query;
  final List<int> body;

  Digest get bodyDigest => Digest.bytes(body);
}

final class GatewayResponse {
  GatewayResponse({
    required this.status,
    required Map<String, String> headers,
    required List<int> body,
    required this.outcome,
    this.routeId,
    this.presetId,
    this.disconnected = false,
  }) : headers = _headers(headers),
       body = ImmutableBytes.copyOf(body) {
    if (status < 100 || status > 599) {
      throw ArgumentError.value(status, 'status');
    }
  }

  final int status;
  final Map<String, String> headers;
  final List<int> body;
  final GatewayOutcome outcome;
  final GatewayRouteId? routeId;
  final GatewayPresetId? presetId;
  final bool disconnected;

  Digest get bodyDigest => Digest.bytes(body);

  Map<String, Object?> toJson({bool includeBody = false}) => <String, Object?>{
    'status': status,
    'headers': _sortedStrings(headers),
    'bodyDigest': bodyDigest.value,
    'bodySize': body.length,
    'outcome': outcome.name,
    if (routeId != null) 'routeId': routeId!.value,
    if (presetId != null) 'presetId': presetId!.value,
    if (disconnected) 'disconnected': true,
    if (includeBody) 'body': body,
  };
}

final class TrafficEvent {
  const TrafficEvent({
    required this.sequence,
    required this.gatewaySessionId,
    required this.monotonicMicroseconds,
    required this.method,
    required this.routeTemplate,
    required this.outcome,
    required this.status,
    required this.durationMicroseconds,
    required this.requestSize,
    required this.responseSize,
    required this.redactionSummary,
    this.routeId,
    this.errorCode,
  });

  final int sequence;
  final String gatewaySessionId;
  final int monotonicMicroseconds;
  final String method;
  final String routeTemplate;
  final GatewayRouteId? routeId;
  final GatewayOutcome outcome;
  final int status;
  final int durationMicroseconds;
  final int requestSize;
  final int responseSize;
  final String? errorCode;
  final String redactionSummary;

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'gatewaySessionId': gatewaySessionId,
    'monotonicMicroseconds': monotonicMicroseconds,
    'method': method,
    'routeTemplate': routeTemplate,
    if (routeId != null) 'routeId': routeId!.value,
    'outcome': outcome.name,
    'status': status,
    'durationMicroseconds': durationMicroseconds,
    'requestSize': requestSize,
    'responseSize': responseSize,
    if (errorCode != null) 'errorCode': errorCode,
    'redactionSummary': redactionSummary,
  };
}

final class VerificationReport {
  VerificationReport({
    required this.planDigest,
    required this.requestMethod,
    required this.requestPath,
    required this.response,
  });

  final Digest planDigest;
  final String requestMethod;
  final String requestPath;
  final GatewayResponse response;

  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'planDigest': planDigest.value,
    'request': <String, Object?>{'method': requestMethod, 'path': requestPath},
    'response': response.toJson(),
  };
}

Map<String, String> _headers(Map<String, String> values) {
  const forbidden = <String>{
    'authorization',
    'connection',
    'content-length',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };
  final output = <String, String>{};
  for (final entry in values.entries) {
    final name = entry.key.toLowerCase();
    if (!_headerName.hasMatch(name) || forbidden.contains(name)) {
      throw FormatException('Forbidden response header ${entry.key}');
    }
    if (entry.value.contains('\r') || entry.value.contains('\n')) {
      throw const FormatException('Header value contains a line break');
    }
    output[name] = entry.value;
  }
  return Map<String, String>.unmodifiable(output);
}

final RegExp _headerName = RegExp(r"^[!#$%&'*+.^_`|~0-9a-z-]+$");

String _httpMethod(String value) {
  final method = value.toUpperCase();
  if (!const <String>{
    'DELETE',
    'GET',
    'HEAD',
    'OPTIONS',
    'PATCH',
    'POST',
    'PUT',
  }.contains(method)) {
    throw FormatException('Unsupported HTTP method $value');
  }
  return method;
}

void _validatePathTemplate(String value) {
  if (!value.startsWith('/') || value.contains('?') || value.contains('#')) {
    throw FormatException('Gateway path template must be an absolute path');
  }
  final parameters = <String>{};
  for (final segment in value.split('/').skip(1)) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw FormatException('Gateway path template has an invalid segment');
    }
    if (segment.startsWith('{') && segment.endsWith('}')) {
      final parameter = segment.substring(1, segment.length - 1);
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(parameter) ||
          !parameters.add(parameter)) {
        throw FormatException('Gateway path parameter is invalid or duplicate');
      }
    } else if (segment.contains('{') || segment.contains('}')) {
      throw FormatException('Gateway path parameters occupy a full segment');
    }
  }
}

List<T> _uniqueSortedIds<T extends OpaqueId>(List<T> values, String name) {
  if (values.toSet().length != values.length) {
    throw ArgumentError('$name must be unique');
  }
  return List<T>.unmodifiable(
    List<T>.of(values)
      ..sort((left, right) => left.value.compareTo(right.value)),
  );
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path must be an array');
  return value;
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

GatewayFixtureId? _optionalFixtureId(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = _optionalString(json, key, path);
  return value == null ? null : GatewayFixtureId(value);
}

UpstreamProfileId? _optionalUpstreamProfileId(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = _optionalString(json, key, path);
  return value == null ? null : UpstreamProfileId(value);
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

int? _optionalInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

List<String> _stringList(Object? value, String path) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$path must be an array of strings');
  }
  return value.cast<String>();
}

Map<String, String> _stringMap(Object? value, String path) {
  final map = _object(value, path);
  return <String, String>{
    for (final entry in map.entries)
      entry.key: entry.value is String
          ? entry.value! as String
          : throw FormatException('$path.${entry.key} must be a string'),
  };
}

Map<String, Uri> _uriMap(Object? value, String path) {
  final map = _object(value, path);
  return Map<String, Uri>.unmodifiable(<String, Uri>{
    for (final entry in map.entries)
      entry.key: entry.value is String
          ? Uri.parse(entry.value! as String)
          : throw FormatException('$path.${entry.key} must be a URI string'),
  });
}

DateTime _gatewayDateTime(Map<String, Object?> json, String key, String path) {
  final source = _string(json, key, path);
  final value = DateTime.tryParse(source);
  if (value == null || !value.isUtc || value.toIso8601String() != source) {
    throw FormatException('$path.$key must be a canonical UTC date-time');
  }
  return value;
}

void _gatewayRuntimeId(String value, String path) {
  if (!RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
    throw FormatException('$path is not a valid runtime identifier: $value');
  }
}

T _enumValue<T extends Enum>(List<T> values, String value, String path) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$path has unsupported value $value');
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path has unknown field $key');
    }
  }
}

bool _duplicates<T>(Iterable<T> values) {
  final seen = <T>{};
  for (final value in values) {
    if (!seen.add(value)) return true;
  }
  return false;
}

Object? _freezeJson(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    Digest.semantic(value);
    return value;
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries) entry.key: _freezeJson(entry.value),
    });
  }
  throw FormatException('Gateway runtime state must be an I-JSON value');
}

Map<String, String> _sortedStrings(Map<String, String> values) =>
    Map<String, String>.fromEntries(
      values.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    );
