import 'dart:convert';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';

import 'host_resource_registry.dart';

typedef WorkspaceCatalogReload = CatalogManifest Function();

/// Owns the canonical Host-side read model consumed by DevEx Studio.
final class HostWorkspaceService {
  HostWorkspaceService({
    required CatalogManifest initialCatalog,
    required this.clock,
    this.providerBindings = const <ProviderBinding>[],
    this.reloadCatalog,
  }) : _catalog = initialCatalog;

  final Clock clock;
  final List<ProviderBinding> providerBindings;
  final WorkspaceCatalogReload? reloadCatalog;

  CatalogManifest _catalog;
  VariantManifest? _variantManifest;
  List<VisualEvidenceProjection> _visualProjections =
      const <VisualEvidenceProjection>[];
  Map<ModuleId, List<ModuleDiagnostic>> _providerDiagnostics =
      const <ModuleId, List<ModuleDiagnostic>>{};
  WorkspaceSnapshot? _snapshot;
  var _revision = 1;

  WorkspaceSnapshot get snapshot =>
      _snapshot ?? (throw StateError('Workspace service is not initialized'));

  WorkspaceSnapshot initialize(EffectiveKitManifest manifest) {
    if (_snapshot != null) {
      throw StateError('Workspace service already initialized');
    }
    _snapshot = _buildSnapshot(manifest);
    return snapshot;
  }

  Map<String, Object?> describe() {
    final current = snapshot;
    return <String, Object?>{
      'schemaVersion': 1,
      'kind': 'WorkspaceDescription',
      'status': 'ready',
      'revision': current.revision,
      'workspaceId': current.catalog.workspace.id.value,
      'catalogDigest': current.catalog.digest.value,
      'variantManifestDigest': current.variantManifest.digest.value,
      'effectiveKitManifestDigest': current.effectiveKitManifest.digest.value,
      'snapshotDigest': current.digest.value,
      'generatedAt': current.generatedAt.toIso8601String(),
    };
  }

  bool refresh(EffectiveKitManifest manifest) {
    final reload = reloadCatalog;
    if (reload == null) return false;
    final nextCatalog = reload();
    if (nextCatalog.digest == _catalog.digest) return false;
    _catalog = nextCatalog;
    _variantManifest = null;
    _visualProjections = const <VisualEvidenceProjection>[];
    _revision += 1;
    _snapshot = _buildSnapshot(manifest);
    return true;
  }

  bool replaceVisualState({
    required VariantManifest variantManifest,
    required List<VisualEvidenceProjection> projections,
    Map<ModuleId, List<ModuleDiagnostic>> providerDiagnostics =
        const <ModuleId, List<ModuleDiagnostic>>{},
  }) {
    if (variantManifest.catalogDigest != _catalog.digest) {
      throw ArgumentError('Visual state belongs to another CatalogManifest');
    }
    final previousVariant = _variantManifest;
    final previousProjectionDigest = Digest.semantic(<Object?>[
      for (final projection in _visualProjections) projection.toJson(),
    ]);
    final nextProjectionDigest = Digest.semantic(<Object?>[
      for (final projection in projections) projection.toJson(),
    ]);
    Digest diagnosticsDigest(
      Map<ModuleId, List<ModuleDiagnostic>> diagnostics,
    ) => Digest.semantic(<String, Object?>{
      for (final id
          in diagnostics.keys.toList()
            ..sort((left, right) => left.value.compareTo(right.value)))
        id.value: <Object?>[
          for (final diagnostic in diagnostics[id]!) diagnostic.toJson(),
        ],
    });
    final diagnosticsChanged =
        diagnosticsDigest(_providerDiagnostics) !=
        diagnosticsDigest(providerDiagnostics);
    if (previousVariant?.digest == variantManifest.digest &&
        previousProjectionDigest == nextProjectionDigest &&
        !diagnosticsChanged) {
      return false;
    }
    _variantManifest = variantManifest;
    _visualProjections = List<VisualEvidenceProjection>.unmodifiable(
      projections,
    );
    _providerDiagnostics = Map<ModuleId, List<ModuleDiagnostic>>.unmodifiable(
      providerDiagnostics.map(
        (key, value) => MapEntry<ModuleId, List<ModuleDiagnostic>>(
          key,
          List<ModuleDiagnostic>.unmodifiable(value),
        ),
      ),
    );
    _revision += 1;
    _snapshot = _buildSnapshot(snapshot.effectiveKitManifest);
    return true;
  }

  ResourceHandle open({
    required HostResourceRegistry resources,
    required Uri hostOrigin,
    required Uri studioOrigin,
  }) {
    final bytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(snapshot.toJson())}\n',
    );
    return resources.grantBytes(
      hostOrigin: hostOrigin,
      audienceOrigin: studioOrigin,
      bytes: bytes,
      mediaType: 'application/json',
      purpose: 'workspace-snapshot',
    );
  }

  WorkspaceSnapshot _buildSnapshot(EffectiveKitManifest manifest) {
    final providers = <VisualEvidenceProviderState>[];
    for (final module in manifest.modules) {
      if (module.state == ModuleRuntimeState.disabled) continue;
      final fidelities = switch (module.moduleId.value) {
        'evidence.auto-preview' => const <RuntimeFidelity>{
          RuntimeFidelity.structural,
        },
        'capture.app-adapter' => const <RuntimeFidelity>{
          RuntimeFidelity.simulated,
        },
        'evidence.android' => const <RuntimeFidelity>{
          RuntimeFidelity.hostNative,
        },
        _ => null,
      };
      if (fidelities == null) continue;
      providers.add(
        VisualEvidenceProviderState(
          providerId: module.moduleId,
          displayName: switch (module.moduleId.value) {
            'evidence.auto-preview' => 'AutoPreview',
            'capture.app-adapter' => 'App Adapter',
            'evidence.android' => 'Android',
            _ => module.moduleId.value,
          },
          health:
              (_providerDiagnostics[module.moduleId]?.any(
                    (item) => item.severity == ModuleDiagnosticSeverity.error,
                  ) ??
                  false)
              ? ModuleHealth.degraded
              : module.health,
          supportedFidelities: fidelities,
          supportsCollection:
              (module.moduleId.value == 'evidence.auto-preview' ||
                  module.moduleId.value == 'capture.app-adapter') &&
              (module.state == ModuleRuntimeState.ready ||
                  module.state == ModuleRuntimeState.degraded),
          diagnostics: <ModuleDiagnostic>[
            ...module.diagnostics,
            ...?_providerDiagnostics[module.moduleId],
          ],
        ),
      );
    }
    return WorkspaceSnapshot(
      revision: _revision,
      catalog: _catalog,
      variantManifest:
          _variantManifest ??
          VariantManifest(
            catalogDigest: _catalog.digest,
            variants: const <Variant>[],
            sources: const <VariantDefinitionSource>[],
          ),
      effectiveKitManifest: manifest,
      providerBindings: providerBindings,
      providers: providers,
      visualProjections: _visualProjections,
      moduleDiagnostics: <ModuleDiagnostic>[
        for (final module in manifest.modules) ...module.diagnostics,
      ],
      generatedAt: clock.nowUtc(),
    );
  }
}
