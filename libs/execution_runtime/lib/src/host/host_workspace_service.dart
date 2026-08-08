import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import 'host_resource_registry.dart';

typedef WorkspaceCatalogReload = CatalogManifest Function();
typedef WorkspaceContentReload = HostWorkspaceContent Function();

/// Catalog and optional adjacent Experience manifests compiled from one
/// authoritative set of workspace documents.
final class HostWorkspaceContent {
  HostWorkspaceContent({
    required this.catalog,
    this.experienceBundle,
    this.scenarioFacetManifest,
    this.scenarioLabManifest,
    this.motionManifest,
  }) {
    if (experienceBundle != null &&
        experienceBundle!.catalogDigest != catalog.digest) {
      throw ArgumentError(
        'ExperienceTopologyBundle belongs to another CatalogManifest',
      );
    }
    if (scenarioFacetManifest != null &&
        scenarioFacetManifest!.catalogDigest != catalog.digest) {
      throw ArgumentError(
        'ScenarioFacetManifest belongs to another CatalogManifest',
      );
    }
    if (scenarioLabManifest != null &&
        scenarioLabManifest!.catalogDigest != catalog.digest) {
      throw ArgumentError(
        'ScenarioLabManifest belongs to another CatalogManifest',
      );
    }
    if (motionManifest != null) {
      final topology = experienceBundle?.topology;
      if (topology == null) {
        throw ArgumentError('MotionManifest requires Experience topology');
      }
      motionManifest!.validateAgainst(catalog: catalog, topology: topology);
    }
  }

  final CatalogManifest catalog;
  final ExperienceTopologyBundle? experienceBundle;
  final ScenarioFacetManifest? scenarioFacetManifest;
  final ScenarioLabManifest? scenarioLabManifest;
  final MotionManifest? motionManifest;
}

/// Result of one atomic content reload.
final class HostWorkspaceRefreshResult {
  const HostWorkspaceRefreshResult({
    required this.catalogChanged,
    required this.experienceChanged,
    required this.layoutOnlyChanged,
    this.facetsChanged = false,
    this.scenarioLabChanged = false,
    this.motionChanged = false,
  });

  final bool catalogChanged;
  final bool experienceChanged;
  final bool layoutOnlyChanged;
  final bool facetsChanged;
  final bool scenarioLabChanged;
  final bool motionChanged;

  bool get changed =>
      catalogChanged ||
      experienceChanged ||
      facetsChanged ||
      scenarioLabChanged ||
      motionChanged;
}

/// Owns the canonical Host-side read model consumed by Abel Studio.
final class HostWorkspaceService {
  HostWorkspaceService({
    required CatalogManifest initialCatalog,
    required this.clock,
    ExperienceTopologyBundle? initialExperienceBundle,
    ScenarioFacetManifest? initialScenarioFacetManifest,
    ScenarioLabManifest? initialScenarioLabManifest,
    MotionManifest? initialMotionManifest,
    this.providerBindings = const <ProviderBinding>[],
    this.reloadCatalog,
    this.reloadContent,
  }) : _catalog = initialCatalog,
       _experienceBundle = initialExperienceBundle,
       _scenarioFacetManifest = initialScenarioFacetManifest,
       _scenarioLabManifest = initialScenarioLabManifest,
       _motionManifest = initialMotionManifest {
    if (reloadCatalog != null && reloadContent != null) {
      throw ArgumentError('Provide reloadCatalog or reloadContent, not both');
    }
    if (initialExperienceBundle != null &&
        initialExperienceBundle.catalogDigest != initialCatalog.digest) {
      throw ArgumentError(
        'ExperienceTopologyBundle belongs to another CatalogManifest',
      );
    }
    if (initialScenarioFacetManifest != null &&
        initialScenarioFacetManifest.catalogDigest != initialCatalog.digest) {
      throw ArgumentError(
        'ScenarioFacetManifest belongs to another CatalogManifest',
      );
    }
    if (initialScenarioLabManifest != null &&
        initialScenarioLabManifest.catalogDigest != initialCatalog.digest) {
      throw ArgumentError(
        'ScenarioLabManifest belongs to another CatalogManifest',
      );
    }
    if (initialMotionManifest != null) {
      final topology = initialExperienceBundle?.topology;
      if (topology == null) {
        throw ArgumentError('MotionManifest requires Experience topology');
      }
      initialMotionManifest.validateAgainst(
        catalog: initialCatalog,
        topology: topology,
      );
    }
  }

  final Clock clock;
  final List<ProviderBinding> providerBindings;
  final WorkspaceCatalogReload? reloadCatalog;
  final WorkspaceContentReload? reloadContent;

  CatalogManifest _catalog;
  ExperienceTopologyBundle? _experienceBundle;
  ScenarioFacetManifest? _scenarioFacetManifest;
  ScenarioLabManifest? _scenarioLabManifest;
  MotionManifest? _motionManifest;
  VariantManifest? _variantManifest;
  List<VisualEvidenceProjection> _visualProjections =
      const <VisualEvidenceProjection>[];
  Map<ModuleId, List<ModuleDiagnostic>> _providerDiagnostics =
      const <ModuleId, List<ModuleDiagnostic>>{};
  WorkspaceSnapshot? _snapshot;
  var _revision = 1;
  var _experienceRevision = 1;
  var _contentRevision = 1;

  WorkspaceSnapshot get snapshot =>
      _snapshot ?? (throw StateError('Workspace service is not initialized'));
  ExperienceTopologyBundle? get experienceBundle => _experienceBundle;
  ScenarioFacetManifest? get scenarioFacetManifest => _scenarioFacetManifest;
  ScenarioLabManifest? get scenarioLabManifest => _scenarioLabManifest;
  MotionManifest? get motionManifest => _motionManifest;
  int get experienceRevision => _experienceRevision;
  int get contentRevision => _contentRevision;

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

  Map<String, Object?> describeExperience() {
    snapshot;
    final bundle = _experienceBundle;
    return <String, Object?>{
      'schemaVersion': 1,
      'kind': 'ExperienceDescription',
      'status': bundle == null ? 'absent' : 'ready',
      'revision': _experienceRevision,
      'catalogDigest': _catalog.digest.value,
      if (bundle != null) ...<String, Object?>{
        'topologyDigest': bundle.topology.digest.value,
        'layoutDigests': <Object?>[
          for (final layout in bundle.layouts)
            <String, Object?>{
              'projectionId': layout.projectionId.value,
              'digest': layout.digest.value,
            },
        ],
        'bundleDigest': bundle.digest.value,
      },
    };
  }

  ExperienceContentSetIdentity get contentSetIdentity {
    final current = snapshot;
    return ExperienceContentSetIdentity(
      revision: _contentRevision,
      catalogDigest: current.catalog.digest,
      workspaceSnapshotDigest: current.digest,
      workspaceContentDigest: current.workspaceContentDigest,
      experienceTopologyBundleDigest: _experienceBundle?.digest,
      scenarioFacetManifestDigest: _scenarioFacetManifest?.digest,
      scenarioLabManifestDigest: _scenarioLabManifest?.digest,
      motionManifestDigest: _motionManifest?.digest,
    );
  }

  ExperienceContentSetDescription describeContentSet() =>
      ExperienceContentSetDescription(identity: contentSetIdentity);

  /// Computes the content-set identity for already compiled content without
  /// mutating the live workspace or emitting an event. Projection authoring
  /// uses this before its filesystem WAL is prepared.
  Digest previewPrecompiledContentSetDigest(HostWorkspaceContent content) {
    _requireCompatiblePrecompiledContent(content);
    final current = snapshot;
    return ExperienceContentSetIdentity(
      revision: _contentRevision + 1,
      catalogDigest: content.catalog.digest,
      workspaceSnapshotDigest: current.digest,
      workspaceContentDigest: current.workspaceContentDigest,
      experienceTopologyBundleDigest: content.experienceBundle?.digest,
      scenarioFacetManifestDigest: content.scenarioFacetManifest?.digest,
      scenarioLabManifestDigest: content.scenarioLabManifest?.digest,
      motionManifestDigest: content.motionManifest?.digest,
    ).contentSetDigest;
  }

  /// Installs one validated, precompiled content set silently. The caller owns
  /// the durable commit and may publish the public event only afterwards.
  Digest installPrecompiledContentSilently(HostWorkspaceContent content) {
    final expectedDigest = previewPrecompiledContentSetDigest(content);
    final experienceChanged =
        _experienceBundle?.digest != content.experienceBundle?.digest;
    final facetsChanged =
        _scenarioFacetManifest?.digest != content.scenarioFacetManifest?.digest;
    final scenarioLabChanged =
        _scenarioLabManifest?.digest != content.scenarioLabManifest?.digest;
    final motionChanged =
        _motionManifest?.digest != content.motionManifest?.digest;
    if (!experienceChanged &&
        !facetsChanged &&
        !scenarioLabChanged &&
        !motionChanged) {
      final currentDigest = contentSetIdentity.contentSetDigest;
      if (currentDigest != expectedDigest) {
        throw StateError('Precompiled content preview is not idempotent');
      }
      return currentDigest;
    }

    _experienceBundle = content.experienceBundle;
    _scenarioFacetManifest = content.scenarioFacetManifest;
    _scenarioLabManifest = content.scenarioLabManifest;
    _motionManifest = content.motionManifest;
    if (experienceChanged) _experienceRevision += 1;
    _contentRevision += 1;
    final publishedDigest = contentSetIdentity.contentSetDigest;
    if (publishedDigest != expectedDigest) {
      throw StateError('Published precompiled content identity drifted');
    }
    return publishedDigest;
  }

  void _requireCompatiblePrecompiledContent(HostWorkspaceContent content) {
    final current = snapshot;
    if (content.catalog.digest != _catalog.digest ||
        content.catalog.digest != current.catalog.digest) {
      throw ArgumentError(
        'Precompiled authoring content cannot replace the workspace catalog',
      );
    }
  }

  bool refresh(EffectiveKitManifest manifest) {
    return refreshContent(manifest).catalogChanged;
  }

  HostWorkspaceRefreshResult refreshContent(EffectiveKitManifest manifest) {
    final contentReload = reloadContent;
    final catalogReload = reloadCatalog;
    if (contentReload == null && catalogReload == null) {
      return const HostWorkspaceRefreshResult(
        catalogChanged: false,
        experienceChanged: false,
        layoutOnlyChanged: false,
        facetsChanged: false,
        scenarioLabChanged: false,
        motionChanged: false,
      );
    }

    final HostWorkspaceContent next;
    if (contentReload != null) {
      next = contentReload();
    } else {
      final nextCatalog = catalogReload!();
      next = HostWorkspaceContent(
        catalog: nextCatalog,
        experienceBundle: nextCatalog.digest == _catalog.digest
            ? _experienceBundle
            : null,
        scenarioFacetManifest: nextCatalog.digest == _catalog.digest
            ? _scenarioFacetManifest
            : null,
        scenarioLabManifest: nextCatalog.digest == _catalog.digest
            ? _scenarioLabManifest
            : null,
        motionManifest: nextCatalog.digest == _catalog.digest
            ? _motionManifest
            : null,
      );
    }
    final catalogChanged = next.catalog.digest != _catalog.digest;
    final previousExperience = _experienceBundle;
    final nextExperience = catalogChanged && contentReload == null
        ? null
        : next.experienceBundle;
    final previousFacets = _scenarioFacetManifest;
    final nextFacets = catalogChanged && contentReload == null
        ? null
        : next.scenarioFacetManifest;
    final previousScenarioLab = _scenarioLabManifest;
    final nextScenarioLab = catalogChanged && contentReload == null
        ? null
        : next.scenarioLabManifest;
    final experienceChanged =
        previousExperience?.digest != nextExperience?.digest || catalogChanged;
    final facetsChanged = previousFacets?.digest != nextFacets?.digest;
    final scenarioLabChanged =
        previousScenarioLab?.digest != nextScenarioLab?.digest;
    final previousMotion = _motionManifest;
    final nextMotion = catalogChanged && contentReload == null
        ? null
        : next.motionManifest;
    final motionChanged = previousMotion?.digest != nextMotion?.digest;
    final layoutOnlyChanged =
        !catalogChanged &&
        !facetsChanged &&
        !scenarioLabChanged &&
        !motionChanged &&
        previousExperience != null &&
        nextExperience != null &&
        previousExperience.topology.digest == nextExperience.topology.digest &&
        previousExperience.digest != nextExperience.digest;
    if (!catalogChanged &&
        !experienceChanged &&
        !facetsChanged &&
        !scenarioLabChanged &&
        !motionChanged) {
      return const HostWorkspaceRefreshResult(
        catalogChanged: false,
        experienceChanged: false,
        layoutOnlyChanged: false,
        facetsChanged: false,
        scenarioLabChanged: false,
        motionChanged: false,
      );
    }

    final nextRevision = catalogChanged ? _revision + 1 : _revision;
    final nextSnapshot = catalogChanged
        ? _buildSnapshotFor(
            manifest,
            catalog: next.catalog,
            variantManifest: null,
            visualProjections: const <VisualEvidenceProjection>[],
            providerDiagnostics: _providerDiagnostics,
            revision: nextRevision,
          )
        : null;

    _catalog = next.catalog;
    _experienceBundle = nextExperience;
    _scenarioFacetManifest = nextFacets;
    _scenarioLabManifest = nextScenarioLab;
    _motionManifest = nextMotion;
    if (catalogChanged) {
      _variantManifest = null;
      _visualProjections = const <VisualEvidenceProjection>[];
      _revision = nextRevision;
      _snapshot = nextSnapshot;
    }
    if (experienceChanged) _experienceRevision += 1;
    _contentRevision += 1;
    return HostWorkspaceRefreshResult(
      catalogChanged: catalogChanged,
      experienceChanged: experienceChanged,
      layoutOnlyChanged: layoutOnlyChanged,
      facetsChanged: facetsChanged,
      scenarioLabChanged: scenarioLabChanged,
      motionChanged: motionChanged,
    );
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
    final nextVisualProjections = List<VisualEvidenceProjection>.unmodifiable(
      projections,
    );
    final nextProviderDiagnostics =
        Map<ModuleId, List<ModuleDiagnostic>>.unmodifiable(
          providerDiagnostics.map(
            (key, value) => MapEntry<ModuleId, List<ModuleDiagnostic>>(
              key,
              List<ModuleDiagnostic>.unmodifiable(value),
            ),
          ),
        );
    final nextRevision = _revision + 1;
    final nextSnapshot = _buildSnapshotFor(
      snapshot.effectiveKitManifest,
      catalog: _catalog,
      variantManifest: variantManifest,
      visualProjections: nextVisualProjections,
      providerDiagnostics: nextProviderDiagnostics,
      revision: nextRevision,
    );
    _variantManifest = variantManifest;
    _visualProjections = nextVisualProjections;
    _providerDiagnostics = nextProviderDiagnostics;
    _revision = nextRevision;
    _snapshot = nextSnapshot;
    _contentRevision += 1;
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

  ResourceHandle openExperience({
    required HostResourceRegistry resources,
    required Uri hostOrigin,
    required Uri studioOrigin,
  }) {
    snapshot;
    final bundle = _experienceBundle;
    if (bundle == null) {
      throw StateError('Experience topology is absent');
    }
    final bytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(bundle.toJson())}\n',
    );
    return resources.grantBytes(
      hostOrigin: hostOrigin,
      audienceOrigin: studioOrigin,
      bytes: bytes,
      mediaType: 'application/json',
      purpose: 'experience-topology-bundle',
    );
  }

  ExperienceContentSetOpenResult openContentSet({
    required HostResourceRegistry resources,
    required Uri hostOrigin,
    required Uri studioOrigin,
  }) {
    final currentSnapshot = snapshot;
    final currentExperience = _experienceBundle;
    final currentFacets = _scenarioFacetManifest;
    final currentLab = _scenarioLabManifest;
    final currentMotion = _motionManifest;
    final identity = ExperienceContentSetIdentity(
      revision: _contentRevision,
      catalogDigest: currentSnapshot.catalog.digest,
      workspaceSnapshotDigest: currentSnapshot.digest,
      workspaceContentDigest: currentSnapshot.workspaceContentDigest,
      experienceTopologyBundleDigest: currentExperience?.digest,
      scenarioFacetManifestDigest: currentFacets?.digest,
      scenarioLabManifestDigest: currentLab?.digest,
      motionManifestDigest: currentMotion?.digest,
    );
    List<int> jsonBytes(Map<String, Object?> json) =>
        utf8.encode('${const JcsCanonicalizer().canonicalize(json)}\n');

    final handles = resources.grantByteSet(
      hostOrigin: hostOrigin,
      audienceOrigin: studioOrigin,
      inputs: <HostResourceGrantInput>[
        HostResourceGrantInput(
          bytes: jsonBytes(currentSnapshot.toJson()),
          mediaType: 'application/json',
          purpose: 'workspace-snapshot',
        ),
        if (currentExperience != null)
          HostResourceGrantInput(
            bytes: jsonBytes(currentExperience.toJson()),
            mediaType: 'application/json',
            purpose: 'experience-topology-bundle',
          ),
        if (currentFacets != null)
          HostResourceGrantInput(
            bytes: jsonBytes(currentFacets.toJson()),
            mediaType: 'application/json',
            purpose: 'scenario-facet-manifest',
          ),
        if (currentLab != null)
          HostResourceGrantInput(
            bytes: jsonBytes(currentLab.toJson()),
            mediaType: 'application/json',
            purpose: 'scenario-lab-manifest',
          ),
        if (currentMotion != null)
          HostResourceGrantInput(
            bytes: jsonBytes(currentMotion.toJson()),
            mediaType: 'application/json',
            purpose: 'motion-manifest',
          ),
      ],
    );
    var index = 0;
    final workspaceSnapshot = handles[index++];
    final experienceTopologyBundle = currentExperience == null
        ? null
        : handles[index++];
    final scenarioFacetManifest = currentFacets == null
        ? null
        : handles[index++];
    final scenarioLabManifest = currentLab == null ? null : handles[index++];
    final motionManifest = currentMotion == null ? null : handles[index++];
    return ExperienceContentSetOpenResult(
      identity: identity,
      workspaceSnapshot: workspaceSnapshot,
      experienceTopologyBundle: experienceTopologyBundle,
      scenarioFacetManifest: scenarioFacetManifest,
      scenarioLabManifest: scenarioLabManifest,
      motionManifest: motionManifest,
    );
  }

  WorkspaceSnapshot _buildSnapshot(EffectiveKitManifest manifest) =>
      _buildSnapshotFor(
        manifest,
        catalog: _catalog,
        variantManifest: _variantManifest,
        visualProjections: _visualProjections,
        providerDiagnostics: _providerDiagnostics,
        revision: _revision,
      );

  WorkspaceSnapshot _buildSnapshotFor(
    EffectiveKitManifest manifest, {
    required CatalogManifest catalog,
    required VariantManifest? variantManifest,
    required List<VisualEvidenceProjection> visualProjections,
    required Map<ModuleId, List<ModuleDiagnostic>> providerDiagnostics,
    required int revision,
  }) {
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
              (providerDiagnostics[module.moduleId]?.any(
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
            ...?providerDiagnostics[module.moduleId],
          ],
        ),
      );
    }
    return WorkspaceSnapshot(
      revision: revision,
      catalog: catalog,
      variantManifest:
          variantManifest ??
          VariantManifest(
            catalogDigest: catalog.digest,
            variants: const <Variant>[],
            sources: const <VariantDefinitionSource>[],
          ),
      effectiveKitManifest: manifest,
      providerBindings: providerBindings,
      providers: providers,
      visualProjections: visualProjections,
      moduleDiagnostics: <ModuleDiagnostic>[
        for (final module in manifest.modules) ...module.diagnostics,
      ],
      generatedAt: clock.nowUtc(),
    );
  }
}
