import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/inventory/inventory_projection.dart';

enum InventoryCatalogStatus { facetsAbsent, ready }

final class InventoryCatalogEntry {
  const InventoryCatalogEntry({required this.scenario, required this.facets});

  final Scenario scenario;
  final ScenarioFacet facets;
}

final class InventoryCatalogResolution {
  const InventoryCatalogResolution._({
    required this.status,
    required this.entries,
  });

  const InventoryCatalogResolution.facetsAbsent()
    : this._(
        status: InventoryCatalogStatus.facetsAbsent,
        entries: const <InventoryCatalogEntry>[],
      );

  InventoryCatalogResolution.ready(Iterable<InventoryCatalogEntry> entries)
    : this._(
        status: InventoryCatalogStatus.ready,
        entries: List<InventoryCatalogEntry>.unmodifiable(entries),
      );

  final InventoryCatalogStatus status;
  final List<InventoryCatalogEntry> entries;

  bool get isReady => status == InventoryCatalogStatus.ready;
}

final class InventoryCatalogAdapter {
  InventoryCatalogAdapter({required this.catalog, required this.facets}) {
    final manifest = facets;
    if (manifest == null) return;
    manifest.validateAgainst(catalog);
    _scenarioKinds = <ScenarioKindId, ScenarioKindDefinition>{
      for (final item in manifest.scenarioKinds) item.id: item,
    };
    _surfaces = <ExperienceSurfaceId, ExperienceSurfaceDefinition>{
      for (final item in manifest.surfaces) item.id: item,
    };
    _states = <ScenarioStateId, ScenarioStateDefinition>{
      for (final item in manifest.states) item.id: item,
    };
    _owners = <OwnershipAreaId, OwnershipAreaDefinition>{
      for (final item in manifest.ownershipAreas) item.id: item,
    };
    _tags = <ScenarioTagId, ScenarioTagDefinition>{
      for (final item in manifest.tags) item.id: item,
    };
    _components = <ExperienceComponentId, ExperienceComponentDefinition>{
      for (final item in manifest.components) item.id: item,
    };
    _fixtures = <ScenarioFixtureId, ScenarioFixtureDefinition>{
      for (final item in manifest.fixtures) item.id: item,
    };
    _frames = <PresentationFrameId, PresentationFrameDefinition>{
      for (final item in manifest.presentationFrames) item.id: item,
    };
    final facetByScenario = <ScenarioId, ScenarioFacet>{
      for (final item in manifest.scenarioFacets) item.scenarioId: item,
    };
    _entries = List<InventoryCatalogEntry>.unmodifiable(<InventoryCatalogEntry>[
      for (final scenario in catalog.scenarios)
        InventoryCatalogEntry(
          scenario: scenario,
          facets: facetByScenario[scenario.id]!,
        ),
    ]);
    _searchText = <ScenarioId, String>{
      for (final entry in _entries)
        entry.scenario.id: _searchableText(entry).toLowerCase(),
    };
  }

  final CatalogManifest catalog;
  final ScenarioFacetManifest? facets;
  Map<ScenarioKindId, ScenarioKindDefinition> _scenarioKinds =
      const <ScenarioKindId, ScenarioKindDefinition>{};
  Map<ExperienceSurfaceId, ExperienceSurfaceDefinition> _surfaces =
      const <ExperienceSurfaceId, ExperienceSurfaceDefinition>{};
  Map<ScenarioStateId, ScenarioStateDefinition> _states =
      const <ScenarioStateId, ScenarioStateDefinition>{};
  Map<OwnershipAreaId, OwnershipAreaDefinition> _owners =
      const <OwnershipAreaId, OwnershipAreaDefinition>{};
  Map<ScenarioTagId, ScenarioTagDefinition> _tags =
      const <ScenarioTagId, ScenarioTagDefinition>{};
  Map<ExperienceComponentId, ExperienceComponentDefinition> _components =
      const <ExperienceComponentId, ExperienceComponentDefinition>{};
  Map<ScenarioFixtureId, ScenarioFixtureDefinition> _fixtures =
      const <ScenarioFixtureId, ScenarioFixtureDefinition>{};
  Map<PresentationFrameId, PresentationFrameDefinition> _frames =
      const <PresentationFrameId, PresentationFrameDefinition>{};
  List<InventoryCatalogEntry> _entries = const <InventoryCatalogEntry>[];
  Map<ScenarioId, String> _searchText = const <ScenarioId, String>{};

  InventoryCatalogResolution resolve(InventoryFilters filters) {
    if (facets == null) {
      return const InventoryCatalogResolution.facetsAbsent();
    }
    if (filters.invalidParameters.isNotEmpty) {
      return InventoryCatalogResolution.ready(const <InventoryCatalogEntry>[]);
    }
    return InventoryCatalogResolution.ready(
      _entries.where((entry) => _matches(entry, filters)),
    );
  }

  Set<ScenarioId>? scenarioScope(InventoryFilters filters) {
    if (!filters.hasScenarioFacetFilter) return null;
    return resolve(filters).entries.map((item) => item.scenario.id).toSet();
  }

  bool _matches(InventoryCatalogEntry entry, InventoryFilters filters) {
    final scenario = entry.scenario;
    final facet = entry.facets;
    final frames = facet.presentationFrameIds
        .map((id) => _frames[id]!)
        .toList(growable: false);
    final text = filters.query.trim().toLowerCase();
    return (filters.applicationId == null ||
            scenario.applicationId == filters.applicationId) &&
        (filters.lifecycle == null || facet.lifecycle == filters.lifecycle) &&
        (filters.scenarioKindId == null ||
            facet.scenarioKindId == filters.scenarioKindId) &&
        (filters.surfaceId == null || facet.surfaceId == filters.surfaceId) &&
        (filters.stateId == null || facet.stateId == filters.stateId) &&
        (filters.ownershipAreaId == null ||
            facet.ownershipAreaId == filters.ownershipAreaId) &&
        (filters.tagId == null || facet.tagIds.contains(filters.tagId)) &&
        (filters.componentId == null ||
            facet.componentIds.contains(filters.componentId)) &&
        (filters.fixtureId == null || facet.fixtureId == filters.fixtureId) &&
        (filters.renderSourceKind == null ||
            facet.renderSource.kind == filters.renderSourceKind) &&
        (filters.frameKind == null ||
            frames.any((frame) => frame.kind == filters.frameKind)) &&
        (filters.formFactorId == null ||
            frames.any(
              (frame) => frame.formFactorId == filters.formFactorId,
            )) &&
        (text.isEmpty || _searchText[scenario.id]!.contains(text));
  }

  String _searchableText(InventoryCatalogEntry entry) {
    final scenario = entry.scenario;
    final facet = entry.facets;
    return <String>[
      scenario.id.value,
      scenario.title,
      scenario.description ?? '',
      facet.lifecycle.name,
      facet.scenarioKindId.value,
      _scenarioKinds[facet.scenarioKindId]!.displayName,
      facet.surfaceId.value,
      _surfaces[facet.surfaceId]!.displayName,
      facet.stateId.value,
      _states[facet.stateId]!.displayName,
      facet.ownershipAreaId.value,
      _owners[facet.ownershipAreaId]!.displayName,
      for (final id in facet.tagIds) ...<String>[
        id.value,
        _tags[id]!.displayName,
      ],
      for (final id in facet.componentIds) ...<String>[
        id.value,
        _components[id]!.displayName,
      ],
      facet.fixtureId.value,
      _fixtures[facet.fixtureId]!.displayName,
      facet.renderSource.kind.name,
      for (final id in facet.presentationFrameIds) ...<String>[
        id.value,
        _frames[id]!.displayName,
        _frames[id]!.kind.name,
        if (_frames[id]!.formFactorId case final formFactorId?)
          formFactorId.value,
      ],
    ].join('\n');
  }
}
