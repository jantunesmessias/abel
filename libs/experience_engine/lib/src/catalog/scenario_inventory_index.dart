import 'package:experience_contracts/experience_contracts.dart';

final class ScenarioInventoryEntry {
  const ScenarioInventoryEntry({required this.scenario, required this.facets});

  final Scenario scenario;
  final ScenarioFacet facets;
}

/// Typed filter request. Values within one axis use OR semantics; populated
/// axes are combined with AND semantics.
final class ScenarioInventoryQuery {
  ScenarioInventoryQuery({
    Iterable<ApplicationId> applicationIds = const <ApplicationId>[],
    Iterable<ScenarioLifecycle> lifecycles = const <ScenarioLifecycle>[],
    Iterable<ScenarioKindId> scenarioKindIds = const <ScenarioKindId>[],
    Iterable<ExperienceSurfaceId> surfaceIds = const <ExperienceSurfaceId>[],
    Iterable<ScenarioStateId> stateIds = const <ScenarioStateId>[],
    Iterable<OwnershipAreaId> ownershipAreaIds = const <OwnershipAreaId>[],
    Iterable<ScenarioTagId> tagIds = const <ScenarioTagId>[],
    Iterable<ExperienceComponentId> componentIds =
        const <ExperienceComponentId>[],
    Iterable<ScenarioFixtureId> fixtureIds = const <ScenarioFixtureId>[],
    Iterable<ScenarioRenderSourceKind> renderSourceKinds =
        const <ScenarioRenderSourceKind>[],
    Iterable<PresentationFrameKind> frameKinds =
        const <PresentationFrameKind>[],
    Iterable<FormFactorId> formFactorIds = const <FormFactorId>[],
    this.text,
  }) : applicationIds = Set<ApplicationId>.unmodifiable(applicationIds),
       lifecycles = Set<ScenarioLifecycle>.unmodifiable(lifecycles),
       scenarioKindIds = Set<ScenarioKindId>.unmodifiable(scenarioKindIds),
       surfaceIds = Set<ExperienceSurfaceId>.unmodifiable(surfaceIds),
       stateIds = Set<ScenarioStateId>.unmodifiable(stateIds),
       ownershipAreaIds = Set<OwnershipAreaId>.unmodifiable(ownershipAreaIds),
       tagIds = Set<ScenarioTagId>.unmodifiable(tagIds),
       componentIds = Set<ExperienceComponentId>.unmodifiable(componentIds),
       fixtureIds = Set<ScenarioFixtureId>.unmodifiable(fixtureIds),
       renderSourceKinds = Set<ScenarioRenderSourceKind>.unmodifiable(
         renderSourceKinds,
       ),
       frameKinds = Set<PresentationFrameKind>.unmodifiable(frameKinds),
       formFactorIds = Set<FormFactorId>.unmodifiable(formFactorIds) {
    if (text != null && text!.length > 2048) {
      throw ArgumentError.value(
        text,
        'text',
        'must not exceed 2048 characters',
      );
    }
  }

  final Set<ApplicationId> applicationIds;
  final Set<ScenarioLifecycle> lifecycles;
  final Set<ScenarioKindId> scenarioKindIds;
  final Set<ExperienceSurfaceId> surfaceIds;
  final Set<ScenarioStateId> stateIds;
  final Set<OwnershipAreaId> ownershipAreaIds;
  final Set<ScenarioTagId> tagIds;
  final Set<ExperienceComponentId> componentIds;
  final Set<ScenarioFixtureId> fixtureIds;
  final Set<ScenarioRenderSourceKind> renderSourceKinds;
  final Set<PresentationFrameKind> frameKinds;
  final Set<FormFactorId> formFactorIds;
  final String? text;
}

/// Deterministic in-memory read model for Inventory. It consumes only a
/// canonical CatalogManifest and its matching adjacent ScenarioFacetManifest.
final class ScenarioInventoryIndex {
  ScenarioInventoryIndex({
    required CatalogManifest catalog,
    required ScenarioFacetManifest facets,
  }) : _scenarioKinds = <ScenarioKindId, ScenarioKindDefinition>{
         for (final item in facets.scenarioKinds) item.id: item,
       },
       _surfaces = <ExperienceSurfaceId, ExperienceSurfaceDefinition>{
         for (final item in facets.surfaces) item.id: item,
       },
       _states = <ScenarioStateId, ScenarioStateDefinition>{
         for (final item in facets.states) item.id: item,
       },
       _owners = <OwnershipAreaId, OwnershipAreaDefinition>{
         for (final item in facets.ownershipAreas) item.id: item,
       },
       _tags = <ScenarioTagId, ScenarioTagDefinition>{
         for (final item in facets.tags) item.id: item,
       },
       _components = <ExperienceComponentId, ExperienceComponentDefinition>{
         for (final item in facets.components) item.id: item,
       },
       _fixtures = <ScenarioFixtureId, ScenarioFixtureDefinition>{
         for (final item in facets.fixtures) item.id: item,
       },
       _frames = <PresentationFrameId, PresentationFrameDefinition>{
         for (final item in facets.presentationFrames) item.id: item,
       } {
    facets.validateAgainst(catalog);
    final facetByScenario = <ScenarioId, ScenarioFacet>{
      for (final item in facets.scenarioFacets) item.scenarioId: item,
    };
    entries =
        List<ScenarioInventoryEntry>.unmodifiable(<ScenarioInventoryEntry>[
          for (final scenario in catalog.scenarios)
            ScenarioInventoryEntry(
              scenario: scenario,
              facets: facetByScenario[scenario.id]!,
            ),
        ]);
    _entryByScenario = <ScenarioId, ScenarioInventoryEntry>{
      for (final entry in entries) entry.scenario.id: entry,
    };
    _searchText = <ScenarioId, String>{
      for (final entry in entries)
        entry.scenario.id: _searchableText(entry).toLowerCase(),
    };
  }

  final Map<ScenarioKindId, ScenarioKindDefinition> _scenarioKinds;
  final Map<ExperienceSurfaceId, ExperienceSurfaceDefinition> _surfaces;
  final Map<ScenarioStateId, ScenarioStateDefinition> _states;
  final Map<OwnershipAreaId, OwnershipAreaDefinition> _owners;
  final Map<ScenarioTagId, ScenarioTagDefinition> _tags;
  final Map<ExperienceComponentId, ExperienceComponentDefinition> _components;
  final Map<ScenarioFixtureId, ScenarioFixtureDefinition> _fixtures;
  final Map<PresentationFrameId, PresentationFrameDefinition> _frames;
  late final Map<ScenarioId, ScenarioInventoryEntry> _entryByScenario;
  late final Map<ScenarioId, String> _searchText;

  late final List<ScenarioInventoryEntry> entries;

  ScenarioInventoryEntry? byScenarioId(ScenarioId id) => _entryByScenario[id];

  List<ScenarioInventoryEntry> query([ScenarioInventoryQuery? request]) {
    final filters = request ?? ScenarioInventoryQuery();
    final normalizedText = filters.text?.trim().toLowerCase();
    return List<ScenarioInventoryEntry>.unmodifiable(
      entries.where((entry) {
        final scenario = entry.scenario;
        final facet = entry.facets;
        final frames = facet.presentationFrameIds
            .map((id) => _frames[id]!)
            .toList(growable: false);
        return _contains(filters.applicationIds, scenario.applicationId) &&
            _contains(filters.lifecycles, facet.lifecycle) &&
            _contains(filters.scenarioKindIds, facet.scenarioKindId) &&
            _contains(filters.surfaceIds, facet.surfaceId) &&
            _contains(filters.stateIds, facet.stateId) &&
            _contains(filters.ownershipAreaIds, facet.ownershipAreaId) &&
            _intersects(filters.tagIds, facet.tagIds) &&
            _intersects(filters.componentIds, facet.componentIds) &&
            _contains(filters.fixtureIds, facet.fixtureId) &&
            _contains(filters.renderSourceKinds, facet.renderSource.kind) &&
            _intersects(
              filters.frameKinds,
              frames.map((frame) => frame.kind),
            ) &&
            _intersects(
              filters.formFactorIds,
              frames
                  .map((frame) => frame.formFactorId)
                  .whereType<FormFactorId>(),
            ) &&
            (normalizedText == null ||
                normalizedText.isEmpty ||
                _searchText[scenario.id]!.contains(normalizedText));
      }),
    );
  }

  String _searchableText(ScenarioInventoryEntry entry) {
    final scenario = entry.scenario;
    final facet = entry.facets;
    return <String>[
      scenario.id.value,
      scenario.title,
      if (scenario.description != null) scenario.description!,
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
        if (_frames[id]!.formFactorId != null) _frames[id]!.formFactorId!.value,
      ],
    ].join('\n');
  }
}

bool _contains<T>(Set<T> requested, T candidate) =>
    requested.isEmpty || requested.contains(candidate);

bool _intersects<T>(Set<T> requested, Iterable<T> candidates) =>
    requested.isEmpty || candidates.any(requested.contains);
