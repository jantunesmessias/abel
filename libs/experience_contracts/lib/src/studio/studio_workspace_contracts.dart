import '../catalog/catalog_contracts.dart';
import '../composition/kit_composition_contracts.dart';
import '../digest.dart';
import '../evidence/evidence_contracts.dart';
import '../preview/preview_contracts.dart';

enum VisualEvidenceStatus {
  unbound,
  collected,
  missing,
  failed,
  unsupported,
  policyDenied,
}

final class ResourceHandle {
  ResourceHandle({
    required this.uri,
    required this.digest,
    required this.mediaType,
    required this.size,
    required this.purpose,
    required DateTime expiresAt,
  }) : expiresAt = expiresAt.toUtc() {
    if (uri.toString().length > 4096 ||
        !uri.hasScheme ||
        !const <String>{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !uri.path.startsWith('/resources/') ||
        uri.pathSegments.length != 2 ||
        !RegExp(r'^[A-Za-z0-9_-]{32,}$').hasMatch(uri.pathSegments.last) ||
        uri.path != '/resources/${uri.pathSegments.last}') {
      throw ArgumentError(
        'ResourceHandle requires an opaque HTTP(S) resource URI',
      );
    }
    if (size < 0 || size > 64 * 1024 * 1024) {
      throw ArgumentError.value(size, 'size', 'must be between 0 and 64 MiB');
    }
    if (!RegExp(
      r'^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$',
    ).hasMatch(mediaType)) {
      throw FormatException('Invalid ResourceHandle mediaType: $mediaType');
    }
    OpaqueId.validate(purpose, 'ResourcePurpose');
  }

  final Uri uri;
  final Digest digest;
  final String mediaType;
  final int size;
  final String purpose;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime instant) => !instant.toUtc().isBefore(expiresAt);

  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri.toString(),
    'digest': digest.value,
    'mediaType': mediaType,
    'size': size,
    'purpose': purpose,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory ResourceHandle.fromJson(Object? value) {
    final json = _object(value, 'ResourceHandle');
    _only(json, const <String>{
      'uri',
      'digest',
      'mediaType',
      'size',
      'purpose',
      'expiresAt',
    }, 'ResourceHandle');
    final expiresAtSource = _string(
      json,
      'expiresAt',
      'ResourceHandle',
      maxLength: 64,
    );
    final expiresAt = _utcDateTime(json, 'expiresAt', 'ResourceHandle');
    if (expiresAt.toIso8601String() != expiresAtSource) {
      throw const FormatException(
        'ResourceHandle.expiresAt must be canonical UTC',
      );
    }
    return ResourceHandle(
      uri: Uri.parse(_string(json, 'uri', 'ResourceHandle', maxLength: 4096)),
      digest: Digest(_string(json, 'digest', 'ResourceHandle')),
      mediaType: _string(json, 'mediaType', 'ResourceHandle', maxLength: 256),
      size: _integer(json, 'size', 'ResourceHandle'),
      purpose: _string(json, 'purpose', 'ResourceHandle', maxLength: 256),
      expiresAt: expiresAt,
    );
  }
}

final class VariantDefinitionSource {
  VariantDefinitionSource({
    required this.variantId,
    required this.sourceId,
    required this.sourceDigest,
  }) {
    OpaqueId.validate(sourceId, 'VariantSource');
  }

  final VariantId variantId;
  final String sourceId;
  final Digest sourceDigest;

  String get key => '${variantId.value}:$sourceId';

  Map<String, Object?> toJson() => <String, Object?>{
    'variantId': variantId.value,
    'sourceId': sourceId,
    'sourceDigest': sourceDigest.value,
  };

  factory VariantDefinitionSource.fromJson(Object? value) {
    final json = _object(value, 'VariantDefinitionSource');
    _only(json, const <String>{
      'variantId',
      'sourceId',
      'sourceDigest',
    }, 'VariantDefinitionSource');
    return VariantDefinitionSource(
      variantId: VariantId(
        _string(json, 'variantId', 'VariantDefinitionSource'),
      ),
      sourceId: _string(
        json,
        'sourceId',
        'VariantDefinitionSource',
        maxLength: 256,
      ),
      sourceDigest: Digest(
        _string(json, 'sourceDigest', 'VariantDefinitionSource'),
      ),
    );
  }
}

final class VariantManifest {
  VariantManifest({
    required this.catalogDigest,
    required List<Variant> variants,
    required List<VariantDefinitionSource> sources,
  }) : variants = _sortedUnique(
         variants,
         (item) => item.id.value,
         'VariantManifest.variants',
         maxItems: 100000,
       ),
       sources = _sortedUnique(
         sources,
         (item) => item.key,
         'VariantManifest.sources',
         maxItems: 500000,
       ) {
    final variantIds = this.variants.map((item) => item.id).toSet();
    if (this.sources.any((source) => !variantIds.contains(source.variantId))) {
      throw ArgumentError(
        'VariantManifest source references an unknown Variant',
      );
    }
    final sourcedVariants = this.sources
        .map((source) => source.variantId)
        .toSet();
    if (variantIds.any((id) => !sourcedVariants.contains(id))) {
      throw ArgumentError(
        'Every Variant requires at least one definition source',
      );
    }
  }

  static const int schemaVersion = 1;
  final Digest catalogDigest;
  final List<Variant> variants;
  final List<VariantDefinitionSource> sources;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'VariantManifest',
    'catalogDigest': catalogDigest.value,
    'variants': <Object?>[for (final variant in variants) variant.toJson()],
    'sources': <Object?>[for (final source in sources) source.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory VariantManifest.fromJson(Object? value) {
    final json = _document(value, 'VariantManifest', const <String>{
      'catalogDigest',
      'variants',
      'sources',
    });
    final manifest = VariantManifest(
      catalogDigest: Digest(_string(json, 'catalogDigest', 'VariantManifest')),
      variants: _list(
        json,
        'variants',
        'VariantManifest',
        maxItems: 100000,
      ).map(Variant.fromJson).toList(growable: false),
      sources: _list(
        json,
        'sources',
        'VariantManifest',
        maxItems: 500000,
      ).map(VariantDefinitionSource.fromJson).toList(growable: false),
    );
    _verifyDigest(json, manifest.digest, 'VariantManifest');
    return manifest;
  }
}

final class VisualEvidenceProviderState {
  VisualEvidenceProviderState({
    required this.providerId,
    required this.displayName,
    required this.health,
    required Set<RuntimeFidelity> supportedFidelities,
    required this.supportsCollection,
    List<ModuleDiagnostic> diagnostics = const <ModuleDiagnostic>[],
  }) : supportedFidelities = Set<RuntimeFidelity>.unmodifiable(
         supportedFidelities,
       ),
       diagnostics = List<ModuleDiagnostic>.unmodifiable(diagnostics) {
    _bounded(displayName, 'VisualEvidenceProviderState.displayName', 512);
    if (this.supportedFidelities.isEmpty) {
      throw ArgumentError('Visual Evidence provider requires a fidelity claim');
    }
    if (this.supportedFidelities.length > RuntimeFidelity.values.length) {
      throw ArgumentError('Visual Evidence provider has too many fidelities');
    }
    _boundedDiagnostics(
      this.diagnostics,
      'VisualEvidenceProviderState.diagnostics',
      1000,
    );
    if (providerId.value == 'evidence.auto-preview' &&
        (this.supportedFidelities.length != 1 ||
            !this.supportedFidelities.contains(RuntimeFidelity.structural))) {
      throw ArgumentError(
        'evidence.auto-preview supports structural fidelity only',
      );
    }
  }

  final ModuleId providerId;
  final String displayName;
  final ModuleHealth health;
  final Set<RuntimeFidelity> supportedFidelities;
  final bool supportsCollection;
  final List<ModuleDiagnostic> diagnostics;

  Map<String, Object?> toJson() => <String, Object?>{
    'providerId': providerId.value,
    'displayName': displayName,
    'health': health.name,
    'supportedFidelities': supportedFidelities.map((item) => item.name).toList()
      ..sort(),
    'supportsCollection': supportsCollection,
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
  };

  factory VisualEvidenceProviderState.fromJson(Object? value) {
    final json = _object(value, 'VisualEvidenceProviderState');
    _only(json, const <String>{
      'providerId',
      'displayName',
      'health',
      'supportedFidelities',
      'supportsCollection',
      'diagnostics',
    }, 'VisualEvidenceProviderState');
    return VisualEvidenceProviderState(
      providerId: ModuleId(
        _string(json, 'providerId', 'VisualEvidenceProviderState'),
      ),
      displayName: _string(
        json,
        'displayName',
        'VisualEvidenceProviderState',
        maxLength: 512,
      ),
      health: _enumValue(
        ModuleHealth.values,
        _string(json, 'health', 'VisualEvidenceProviderState'),
        'VisualEvidenceProviderState.health',
      ),
      supportedFidelities:
          _stringList(
                json,
                'supportedFidelities',
                'VisualEvidenceProviderState',
                maxItems: RuntimeFidelity.values.length,
              )
              .map(
                (name) => _enumValue(
                  RuntimeFidelity.values,
                  name,
                  'VisualEvidenceProviderState.supportedFidelities',
                ),
              )
              .toSet(),
      supportsCollection: _boolean(
        json,
        'supportsCollection',
        'VisualEvidenceProviderState',
      ),
      diagnostics: _list(
        json,
        'diagnostics',
        'VisualEvidenceProviderState',
        maxItems: 1000,
      ).map(ModuleDiagnostic.fromJson).toList(growable: false),
    );
  }
}

final class VisualEvidenceProjection {
  VisualEvidenceProjection({
    required this.providerId,
    required this.status,
    required this.freshness,
    this.scenarioId,
    this.variantId,
    this.evidenceDigest,
    this.artifactDigest,
    this.captureKey,
    this.executionFingerprintDigest,
    this.capturePolicyId,
    this.fidelity,
    DateTime? observedAt,
    this.artifactHandle,
    List<ModuleDiagnostic> diagnostics = const <ModuleDiagnostic>[],
  }) : observedAt = observedAt?.toUtc(),
       diagnostics = List<ModuleDiagnostic>.unmodifiable(diagnostics) {
    if (capturePolicyId != null) {
      OpaqueId.validate(capturePolicyId!, 'CapturePolicy');
    }
    _boundedDiagnostics(
      this.diagnostics,
      'VisualEvidenceProjection.diagnostics',
      1000,
    );
    final bound = scenarioId != null && variantId != null;
    if (status == VisualEvidenceStatus.unbound) {
      if (scenarioId != null || variantId != null || evidenceDigest == null) {
        throw ArgumentError(
          'Unbound visual Evidence requires an Evidence digest and no binding',
        );
      }
    } else if (!bound) {
      throw ArgumentError(
        'Bound visual Evidence requires Scenario and Variant',
      );
    }
    if (status == VisualEvidenceStatus.collected) {
      if (evidenceDigest == null ||
          artifactDigest == null ||
          fidelity == null ||
          this.observedAt == null ||
          artifactHandle == null ||
          !const <EvidenceFreshness>{
            EvidenceFreshness.fresh,
            EvidenceFreshness.stale,
          }.contains(freshness)) {
        throw ArgumentError(
          'Collected visual Evidence requires artifact, handle, fidelity, time and fresh/stale state',
        );
      }
    } else if (status != VisualEvidenceStatus.unbound &&
        (artifactDigest != null || artifactHandle != null)) {
      throw ArgumentError(
        'Non-collected bound Evidence cannot expose an artifact',
      );
    }
    if (artifactHandle != null &&
        (artifactDigest == null || artifactHandle!.digest != artifactDigest)) {
      throw ArgumentError('Visual artifact handle digest mismatch');
    }
    if (artifactHandle != null &&
        (artifactHandle!.mediaType != 'image/png' ||
            artifactHandle!.purpose != 'visual-artifact')) {
      throw ArgumentError(
        'Visual artifact handle must be an image/png visual-artifact',
      );
    }
    if (providerId.value == 'evidence.auto-preview' &&
        fidelity != null &&
        fidelity != RuntimeFidelity.structural) {
      throw ArgumentError(
        'evidence.auto-preview cannot project fidelity above structural',
      );
    }
  }

  final ModuleId providerId;
  final ScenarioId? scenarioId;
  final VariantId? variantId;
  final Digest? evidenceDigest;
  final Digest? artifactDigest;
  final Digest? captureKey;
  final Digest? executionFingerprintDigest;
  final String? capturePolicyId;
  final VisualEvidenceStatus status;
  final EvidenceFreshness freshness;
  final RuntimeFidelity? fidelity;
  final DateTime? observedAt;
  final ResourceHandle? artifactHandle;
  final List<ModuleDiagnostic> diagnostics;

  String get key => status == VisualEvidenceStatus.unbound
      ? '${providerId.value}:unbound:${evidenceDigest!.value}'
      : '${providerId.value}:${scenarioId!.value}:${variantId!.value}';

  Map<String, Object?> toJson() => <String, Object?>{
    'providerId': providerId.value,
    if (scenarioId != null) 'scenarioId': scenarioId!.value,
    if (variantId != null) 'variantId': variantId!.value,
    if (evidenceDigest != null) 'evidenceDigest': evidenceDigest!.value,
    if (artifactDigest != null) 'artifactDigest': artifactDigest!.value,
    if (captureKey != null) 'captureKey': captureKey!.value,
    if (executionFingerprintDigest != null)
      'executionFingerprintDigest': executionFingerprintDigest!.value,
    if (capturePolicyId != null) 'capturePolicyId': capturePolicyId,
    'status': status.name,
    'freshness': freshness.name,
    if (fidelity != null) 'fidelity': fidelity!.name,
    if (observedAt != null) 'observedAt': observedAt!.toIso8601String(),
    if (artifactHandle != null) 'artifactHandle': artifactHandle!.toJson(),
    'diagnostics': <Object?>[
      for (final diagnostic in diagnostics) diagnostic.toJson(),
    ],
  };

  factory VisualEvidenceProjection.fromJson(Object? value) {
    final json = _object(value, 'VisualEvidenceProjection');
    _only(json, const <String>{
      'providerId',
      'scenarioId',
      'variantId',
      'evidenceDigest',
      'artifactDigest',
      'captureKey',
      'executionFingerprintDigest',
      'capturePolicyId',
      'status',
      'freshness',
      'fidelity',
      'observedAt',
      'artifactHandle',
      'diagnostics',
    }, 'VisualEvidenceProjection');
    final scenarioId = _optionalString(
      json,
      'scenarioId',
      'VisualEvidenceProjection',
    );
    final variantId = _optionalString(
      json,
      'variantId',
      'VisualEvidenceProjection',
    );
    final evidenceDigest = _optionalString(
      json,
      'evidenceDigest',
      'VisualEvidenceProjection',
    );
    final artifactDigest = _optionalString(
      json,
      'artifactDigest',
      'VisualEvidenceProjection',
    );
    final captureKey = _optionalString(
      json,
      'captureKey',
      'VisualEvidenceProjection',
    );
    final executionFingerprintDigest = _optionalString(
      json,
      'executionFingerprintDigest',
      'VisualEvidenceProjection',
    );
    final capturePolicyId = _optionalString(
      json,
      'capturePolicyId',
      'VisualEvidenceProjection',
      maxLength: 256,
    );
    final fidelity = _optionalString(
      json,
      'fidelity',
      'VisualEvidenceProjection',
    );
    final observedAt = _optionalUtcDateTime(
      json,
      'observedAt',
      'VisualEvidenceProjection',
    );
    return VisualEvidenceProjection(
      providerId: ModuleId(
        _string(json, 'providerId', 'VisualEvidenceProjection'),
      ),
      scenarioId: scenarioId == null ? null : ScenarioId(scenarioId),
      variantId: variantId == null ? null : VariantId(variantId),
      evidenceDigest: evidenceDigest == null ? null : Digest(evidenceDigest),
      artifactDigest: artifactDigest == null ? null : Digest(artifactDigest),
      captureKey: captureKey == null ? null : Digest(captureKey),
      executionFingerprintDigest: executionFingerprintDigest == null
          ? null
          : Digest(executionFingerprintDigest),
      capturePolicyId: capturePolicyId,
      status: _enumValue(
        VisualEvidenceStatus.values,
        _string(json, 'status', 'VisualEvidenceProjection'),
        'VisualEvidenceProjection.status',
      ),
      freshness: _enumValue(
        EvidenceFreshness.values,
        _string(json, 'freshness', 'VisualEvidenceProjection'),
        'VisualEvidenceProjection.freshness',
      ),
      fidelity: fidelity == null
          ? null
          : _enumValue(
              RuntimeFidelity.values,
              fidelity,
              'VisualEvidenceProjection.fidelity',
            ),
      observedAt: observedAt,
      artifactHandle: json['artifactHandle'] == null
          ? null
          : ResourceHandle.fromJson(json['artifactHandle']),
      diagnostics: _list(
        json,
        'diagnostics',
        'VisualEvidenceProjection',
        maxItems: 1000,
      ).map(ModuleDiagnostic.fromJson).toList(growable: false),
    );
  }
}

final class WorkspaceSnapshot {
  WorkspaceSnapshot({
    required this.revision,
    required this.catalog,
    required this.variantManifest,
    required this.effectiveKitManifest,
    List<ProviderBinding> providerBindings = const <ProviderBinding>[],
    required List<VisualEvidenceProviderState> providers,
    required List<VisualEvidenceProjection> visualProjections,
    List<ModuleDiagnostic> moduleDiagnostics = const <ModuleDiagnostic>[],
    required DateTime generatedAt,
  }) : providerBindings = _sortedUnique(
         providerBindings,
         (item) => item.key,
         'WorkspaceSnapshot.providerBindings',
         maxItems: 10000,
       ),
       providers = _sortedUnique(
         providers,
         (item) => item.providerId.value,
         'WorkspaceSnapshot.providers',
         maxItems: 256,
       ),
       visualProjections = _sortedUnique(
         visualProjections,
         (item) => item.key,
         'WorkspaceSnapshot.visualProjections',
         maxItems: 500000,
       ),
       moduleDiagnostics = List<ModuleDiagnostic>.unmodifiable(
         moduleDiagnostics,
       ),
       generatedAt = generatedAt.toUtc() {
    if (revision < 1 || revision > 9007199254740991) {
      throw ArgumentError.value(
        revision,
        'revision',
        'must be a safe positive integer',
      );
    }
    if (catalog.digest != variantManifest.catalogDigest) {
      throw ArgumentError('VariantManifest belongs to another CatalogManifest');
    }
    _boundedDiagnostics(
      this.moduleDiagnostics,
      'WorkspaceSnapshot.moduleDiagnostics',
      10000,
    );
    final applicationIds = catalog.applications.map((item) => item.id).toSet();
    if (variantManifest.variants.any(
      (variant) => !applicationIds.contains(variant.applicationId),
    )) {
      throw ArgumentError(
        'VariantManifest references an unknown catalog Application',
      );
    }
    final providerIds = this.providers.map((item) => item.providerId).toSet();
    final effectiveModuleIds = effectiveKitManifest.modules
        .map((item) => item.moduleId)
        .toSet();
    if (providerIds.any((id) => !effectiveModuleIds.contains(id))) {
      throw ArgumentError(
        'Visual provider is absent from EffectiveKitManifest',
      );
    }
    if (this.visualProjections.any(
      (projection) => !providerIds.contains(projection.providerId),
    )) {
      throw ArgumentError('Visual projection references an unknown provider');
    }
    for (final binding in this.providerBindings) {
      if (binding.applicationId != null &&
          !applicationIds.any((id) => id.value == binding.applicationId)) {
        throw ArgumentError(
          'Provider binding references an unknown catalog Application',
        );
      }
      if (binding.capability.id == 'evidence.visual' &&
          binding.providerModuleIds.any((id) => !providerIds.contains(id))) {
        throw ArgumentError(
          'Visual provider binding references an unavailable provider',
        );
      }
    }
    final scenarios = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final variants = <VariantId, Variant>{
      for (final variant in variantManifest.variants) variant.id: variant,
    };
    for (final projection in this.visualProjections) {
      if (projection.status == VisualEvidenceStatus.unbound) continue;
      final scenario = scenarios[projection.scenarioId];
      final variant = variants[projection.variantId];
      if (scenario == null ||
          variant == null ||
          scenario.applicationId != variant.applicationId) {
        throw ArgumentError(
          'Visual projection has an unknown or cross-Application binding',
        );
      }
    }
  }

  static const int schemaVersion = 1;
  final int revision;
  final CatalogManifest catalog;
  final VariantManifest variantManifest;
  final EffectiveKitManifest effectiveKitManifest;
  final List<ProviderBinding> providerBindings;
  final List<VisualEvidenceProviderState> providers;
  final List<VisualEvidenceProjection> visualProjections;
  final List<ModuleDiagnostic> moduleDiagnostics;
  final DateTime generatedAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  /// Stable identity for the semantic content carried by this snapshot.
  ///
  /// Unlike [digest], this value deliberately excludes observation metadata
  /// and renewable transport grants. It is therefore stable when an
  /// equivalent workspace is reconstructed with a new revision, timestamps,
  /// or resource handles.
  late final Digest workspaceContentDigest = Digest.semantic(
    _workspaceContentJson(),
  );

  Map<String, Object?> _workspaceContentJson() {
    final content = toJson(includeDigest: false)
      ..remove('revision')
      ..remove('generatedAt')
      ..remove('catalog')
      ..['catalogDigest'] = catalog.digest.value;
    final effectiveKit = effectiveKitManifest.toJson(includeDigest: false)
      ..remove('generatedAt');
    content['effectiveKitManifest'] = effectiveKit;
    content['visualProjections'] = <Object?>[
      for (final projection in visualProjections)
        _visualProjectionContentJson(projection),
    ];
    return content;
  }

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'WorkspaceSnapshot',
    'revision': revision,
    'catalog': catalog.toJson(),
    'variantManifest': variantManifest.toJson(),
    'effectiveKitManifest': effectiveKitManifest.toJson(),
    'providerBindings': <Object?>[
      for (final binding in providerBindings) binding.toJson(),
    ],
    'providers': <Object?>[for (final provider in providers) provider.toJson()],
    'visualProjections': <Object?>[
      for (final projection in visualProjections) projection.toJson(),
    ],
    'moduleDiagnostics': <Object?>[
      for (final diagnostic in moduleDiagnostics) diagnostic.toJson(),
    ],
    'generatedAt': generatedAt.toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory WorkspaceSnapshot.fromJson(Object? value) {
    final json = _document(value, 'WorkspaceSnapshot', const <String>{
      'revision',
      'catalog',
      'variantManifest',
      'effectiveKitManifest',
      'providerBindings',
      'providers',
      'visualProjections',
      'moduleDiagnostics',
      'generatedAt',
    });
    final snapshot = WorkspaceSnapshot(
      revision: _integer(json, 'revision', 'WorkspaceSnapshot'),
      catalog: CatalogManifest.fromJson(json['catalog']),
      variantManifest: VariantManifest.fromJson(json['variantManifest']),
      effectiveKitManifest: EffectiveKitManifest.fromJson(
        json['effectiveKitManifest'],
      ),
      providerBindings: _list(
        json,
        'providerBindings',
        'WorkspaceSnapshot',
        maxItems: 10000,
      ).map(ProviderBinding.fromJson).toList(growable: false),
      providers: _list(
        json,
        'providers',
        'WorkspaceSnapshot',
        maxItems: 256,
      ).map(VisualEvidenceProviderState.fromJson).toList(growable: false),
      visualProjections: _list(
        json,
        'visualProjections',
        'WorkspaceSnapshot',
        maxItems: 500000,
      ).map(VisualEvidenceProjection.fromJson).toList(growable: false),
      moduleDiagnostics: _list(
        json,
        'moduleDiagnostics',
        'WorkspaceSnapshot',
        maxItems: 10000,
      ).map(ModuleDiagnostic.fromJson).toList(growable: false),
      generatedAt: _utcDateTime(json, 'generatedAt', 'WorkspaceSnapshot'),
    );
    _verifyDigest(json, snapshot.digest, 'WorkspaceSnapshot');
    return snapshot;
  }
}

Map<String, Object?> _visualProjectionContentJson(
  VisualEvidenceProjection projection,
) {
  final content = projection.toJson()..remove('observedAt');
  final artifactHandle = content['artifactHandle'];
  if (artifactHandle is Map<String, Object?>) {
    content['artifactHandle'] = <String, Object?>{...artifactHandle}
      ..remove('uri')
      ..remove('expiresAt');
  }
  return content;
}

List<T> _sortedUnique<T>(
  Iterable<T> values,
  String Function(T) key,
  String path, {
  required int maxItems,
}) {
  final result = List<T>.of(values)
    ..sort((left, right) => key(left).compareTo(key(right)));
  if (result.length > maxItems || _duplicates(result.map(key))) {
    throw ArgumentError(
      '$path must be unique and contain at most $maxItems items',
    );
  }
  return List<T>.unmodifiable(result);
}

Map<String, Object?> _document(Object? value, String kind, Set<String> fields) {
  final json = _object(value, kind);
  _only(json, <String>{'schemaVersion', 'kind', ...fields, 'digest'}, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind has invalid schemaVersion or kind');
  }
  return json;
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _string(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 4096,
}) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('$path.$key must be a bounded non-empty string');
  }
  return value;
}

String? _optionalString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 4096,
}) {
  if (!json.containsKey(key)) return null;
  return _string(json, key, path, maxLength: maxLength);
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! num ||
      !value.isFinite ||
      value != value.truncateToDouble() ||
      value.abs() > 9007199254740991) {
    throw FormatException('$path.$key must be an I-JSON-safe integer');
  }
  return value.toInt();
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

List<Object?> _list(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be an array');
  }
  if (value.length > maxItems) {
    throw FormatException('$path.$key exceeds $maxItems items');
  }
  return value;
}

List<String> _stringList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final values = _list(json, key, path, maxItems: maxItems);
  if (values.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path.$key must contain non-empty strings');
  }
  return values.cast<String>();
}

DateTime _utcDateTime(Map<String, Object?> json, String key, String path) {
  final value = _string(json, key, path, maxLength: 64);
  if (!value.endsWith('Z')) {
    throw FormatException('$path.$key must be UTC');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$path.$key must be an ISO-8601 time');
  }
  return parsed.toUtc();
}

DateTime? _optionalUtcDateTime(
  Map<String, Object?> json,
  String key,
  String path,
) => json.containsKey(key) ? _utcDateTime(json, key, path) : null;

T _enumValue<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has unsupported value $name');
}

void _verifyDigest(Map<String, Object?> json, Digest actual, String path) {
  if (_string(json, 'digest', path) != actual.value) {
    throw FormatException('$path digest mismatch');
  }
}

void _bounded(String value, String path, int maxLength) {
  if (value.isEmpty || value.length > maxLength) {
    throw ArgumentError('$path must be bounded and non-empty');
  }
}

void _boundedDiagnostics(
  List<ModuleDiagnostic> diagnostics,
  String path,
  int maxItems,
) {
  if (diagnostics.length > maxItems) {
    throw ArgumentError('$path must contain at most $maxItems items');
  }
}

bool _duplicates(Iterable<String> values) {
  final seen = <String>{};
  return values.any((value) => !seen.add(value));
}
