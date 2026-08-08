import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../storage/filesystem_workspace_store.dart';
import '../workspace/workspace_catalog_loader.dart';

final class WorkspaceGatewayPlanResult {
  const WorkspaceGatewayPlanResult({
    required this.compilation,
    required this.planArtifactDigest,
  });

  final GatewayCompilation compilation;
  final Digest? planArtifactDigest;
}

/// Compiles Gateway authoring without giving the pure Dart engine filesystem
/// ownership. Fixture bodies become immutable CAS handles; they are persisted
/// only when [persist] is explicitly requested.
final class WorkspaceGatewayPlanCompiler {
  const WorkspaceGatewayPlanCompiler();

  List<String> presetIds(LoadedWorkspaceCatalog loaded) =>
      loaded.documents
          .where((document) => document.kind == AuthoringKind.gatewayPreset)
          .map((document) => document.id)
          .toList(growable: false)
        ..sort();

  List<WorkspaceGatewayPlanResult> compileAll(
    LoadedWorkspaceCatalog loaded, {
    bool persist = false,
  }) => <WorkspaceGatewayPlanResult>[
    for (final presetId in presetIds(loaded))
      compilePreset(loaded, presetId: presetId, persist: persist),
  ];

  WorkspaceGatewayPlanResult compilePreset(
    LoadedWorkspaceCatalog loaded, {
    required String presetId,
    bool persist = false,
  }) {
    final documents = loaded.documents;
    final presetDocument = _single(
      documents,
      AuthoringKind.gatewayPreset,
      presetId,
    );
    final preset = GatewayPreset(
      id: GatewayPresetId(presetDocument.id),
      scopeId: GatewayScopeId(_string(presetDocument, 'scopeId')),
      description: _string(presetDocument, 'description'),
      routeIds: _stringList(
        presetDocument,
        'routeIds',
      ).map(GatewayRouteId.new).toList(growable: false),
      initialState: _optionalObject(presetDocument, 'initialState'),
    );
    final scopeDocument = _single(
      documents,
      AuthoringKind.gatewayScope,
      preset.scopeId.value,
    );
    final scope = GatewayScope(
      id: GatewayScopeId(scopeDocument.id),
      displayName: _string(scopeDocument, 'displayName'),
      routeIds: _stringList(
        scopeDocument,
        'routeIds',
      ).map(GatewayRouteId.new).toList(growable: false),
    );
    final routeDocuments = documents
        .where(
          (document) =>
              document.kind == AuthoringKind.gatewayRoute &&
              document.spec['scopeId'] == scope.id.value,
        )
        .toList(growable: false);
    final routes = <GatewayRoute>[
      for (final document in routeDocuments) _route(document),
    ];
    final selectedFixtureIds = routes
        .where((route) => preset.routeIds.contains(route.id))
        .map((route) => route.fixtureId)
        .whereType<GatewayFixtureId>()
        .toSet();
    final fixtureBytes = <GatewayFixtureId, List<int>>{};
    final fixtures = <GatewayFixture>[];
    for (final fixtureId in selectedFixtureIds) {
      final document = _single(
        documents,
        AuthoringKind.gatewayFixture,
        fixtureId.value,
      );
      final bytes = _fixtureBytes(loaded, document);
      fixtureBytes[fixtureId] = bytes;
      fixtures.add(
        GatewayFixture(
          id: fixtureId,
          status: _integer(document, 'status'),
          headers: _optionalStringMap(document, 'headers'),
          bodyDigest: Digest.bytes(bytes),
          bodySize: bytes.length,
          mediaType: _string(document, 'mediaType'),
        ),
      );
    }
    final compilation = const GatewayPlanCompiler().compile(
      scope: scope,
      preset: preset,
      routes: routes,
      fixtures: fixtures,
      backendMode: _optionalBackendMode(presetDocument),
    );
    if (!persist) {
      return WorkspaceGatewayPlanResult(
        compilation: compilation,
        planArtifactDigest: null,
      );
    }
    final store = FileSystemWorkspaceStore(workspaceRoot: loaded.workspaceRoot);
    late final Digest planArtifactDigest;
    store.withExclusiveLock(() {
      for (final entry in fixtureBytes.entries) {
        final stored = store.putBlob(entry.value);
        if (stored != Digest.bytes(entry.value)) {
          throw StateError('CAS rejected GatewayFixture ${entry.key}');
        }
      }
      final canonical = utf8.encode(
        const JcsCanonicalizer().canonicalize(compilation.plan.toJson()),
      );
      planArtifactDigest = store.putBlob(canonical);
      store.rebuildCasIndex();
    });
    return WorkspaceGatewayPlanResult(
      compilation: compilation,
      planArtifactDigest: planArtifactDigest,
    );
  }

  GatewayRoute _route(AuthoringDocument document) {
    final faultValue = document.spec['faultProfile'];
    return GatewayRoute(
      id: GatewayRouteId(document.id),
      scopeId: GatewayScopeId(_string(document, 'scopeId')),
      method: _string(document, 'method'),
      pathTemplate: _string(document, 'pathTemplate'),
      requiredQuery: _optionalStringMap(document, 'requiredQuery'),
      appliesTo: _stringList(
        document,
        'appliesTo',
      ).map(GatewayPresetId.new).toSet(),
      policy: _enumValue(
        GatewayRoutePolicy.values,
        _string(document, 'policy'),
        '${document.sourceName}: spec.policy',
      ),
      fixtureId: document.spec['fixtureId'] == null
          ? null
          : GatewayFixtureId(_string(document, 'fixtureId')),
      upstreamProfileId: document.spec['upstreamProfileId'] == null
          ? null
          : UpstreamProfileId(_string(document, 'upstreamProfileId')),
      faultProfile: faultValue == null
          ? null
          : GatewayFaultProfile.fromJson(faultValue),
    );
  }

  List<int> _fixtureBytes(
    LoadedWorkspaceCatalog loaded,
    AuthoringDocument document,
  ) {
    final reference = _string(document, 'bodyFile');
    final sourceFile = File(document.sourceName);
    final candidate = File(
      p.normalize(p.join(sourceFile.parent.path, reference)),
    );
    if (!p.isWithin(loaded.workspaceRoot, candidate.path)) {
      throw FileSystemException(
        'GatewayFixture body escapes workspace',
        candidate.path,
      );
    }
    if (!candidate.existsSync()) {
      throw FileSystemException(
        'GatewayFixture body not found',
        candidate.path,
      );
    }
    final resolved = candidate.resolveSymbolicLinksSync();
    if (!p.isWithin(loaded.workspaceRoot, resolved)) {
      throw FileSystemException(
        'GatewayFixture body resolves outside workspace',
        candidate.path,
      );
    }
    final file = File(resolved);
    if (file.lengthSync() > 256 * 1024) {
      throw FileSystemException(
        'GatewayFixture body exceeds 256 KiB',
        candidate.path,
      );
    }
    return file.readAsBytesSync();
  }

  AuthoringDocument _single(
    Iterable<AuthoringDocument> documents,
    AuthoringKind kind,
    String id,
  ) {
    final matches = documents
        .where((document) => document.kind == kind && document.id == id)
        .toList(growable: false);
    if (matches.length != 1) {
      throw FormatException(
        'Expected exactly one ${kind.name}:$id, found ${matches.length}',
      );
    }
    return matches.single;
  }

  String _string(AuthoringDocument document, String key) {
    final value = document.spec[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        '${document.sourceName}: spec.$key must be a non-empty string',
      );
    }
    return value;
  }

  int _integer(AuthoringDocument document, String key) {
    final value = document.spec[key];
    if (value is! int) {
      throw FormatException(
        '${document.sourceName}: spec.$key must be an integer',
      );
    }
    return value;
  }

  List<String> _stringList(AuthoringDocument document, String key) {
    final value = document.spec[key];
    if (value is! List<Object?> || !value.every((item) => item is String)) {
      throw FormatException(
        '${document.sourceName}: spec.$key must be a string array',
      );
    }
    return value.cast<String>();
  }

  Map<String, String> _optionalStringMap(
    AuthoringDocument document,
    String key,
  ) {
    final value = document.spec[key];
    if (value == null) return const <String, String>{};
    if (value is! Map<String, Object?> ||
        value.values.any((item) => item is! String)) {
      throw FormatException(
        '${document.sourceName}: spec.$key must be a string map',
      );
    }
    return value.cast<String, String>();
  }

  Map<String, Object?> _optionalObject(AuthoringDocument document, String key) {
    final value = document.spec[key];
    if (value == null) return const <String, Object?>{};
    if (value is! Map<String, Object?>) {
      throw FormatException(
        '${document.sourceName}: spec.$key must be an object',
      );
    }
    return value;
  }

  BackendMode _optionalBackendMode(AuthoringDocument document) {
    final value = document.spec['backendMode'];
    if (value == null) return BackendMode.isolated;
    if (value is! String) {
      throw FormatException(
        '${document.sourceName}: spec.backendMode must be a string',
      );
    }
    final mode = _enumValue(
      BackendMode.values,
      value,
      '${document.sourceName}: spec.backendMode',
    );
    if (mode == BackendMode.none) {
      throw FormatException(
        '${document.sourceName}: GatewayPreset cannot use backendMode none',
      );
    }
    return mode;
  }

  T _enumValue<T extends Enum>(List<T> values, String name, String path) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('$path has unsupported value $name');
  }
}
