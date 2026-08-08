import 'package:experience_contracts/experience_contracts.dart';

enum InventoryProjectionStatus {
  topologyAbsent,
  projectionAbsent,
  projectionKindMismatch,
  layoutAbsent,
  ready,
}

final class InventoryOccurrence {
  const InventoryOccurrence({
    required this.projection,
    required this.node,
    required this.scenario,
    this.frame,
    this.group,
    this.lane,
  });

  final ExperienceProjection projection;
  final NodeInstance node;
  final Scenario scenario;
  final ProjectionNodeFrame? frame;
  final ProjectionGroup? group;
  final ProjectionLane? lane;
}

final class ExperienceOccurrenceTarget {
  const ExperienceOccurrenceTarget({
    required this.projection,
    required this.node,
  });

  final ExperienceProjection projection;
  final NodeInstance node;
}

final class InventoryProjectionIndex {
  InventoryProjectionIndex({required this.catalog, required this.bundle}) {
    if (bundle != null && bundle!.catalogDigest != catalog.digest) {
      throw ArgumentError(
        'ExperienceTopologyBundle belongs to another CatalogManifest',
      );
    }
  }

  final CatalogManifest catalog;
  final ExperienceTopologyBundle? bundle;

  List<ExperienceProjection> inventoryProjections({
    ApplicationId? applicationId,
  }) => List<ExperienceProjection>.unmodifiable(
    bundle?.topology.projections.where(
          (projection) =>
              projection.kind == ProjectionKind.inventory &&
              (applicationId == null ||
                  projection.applicationId == applicationId),
        ) ??
        const <ExperienceProjection>[],
  );

  InventoryProjectionResolution resolve(String projectionId) {
    final currentBundle = bundle;
    if (currentBundle == null) {
      return const InventoryProjectionResolution._(
        status: InventoryProjectionStatus.topologyAbsent,
      );
    }
    final projection = currentBundle.topology.projections
        .where((item) => item.id.value == projectionId)
        .firstOrNull;
    if (projection == null) {
      return const InventoryProjectionResolution._(
        status: InventoryProjectionStatus.projectionAbsent,
      );
    }
    if (projection.kind != ProjectionKind.inventory) {
      return InventoryProjectionResolution._(
        status: InventoryProjectionStatus.projectionKindMismatch,
        projection: projection,
      );
    }

    final layout = currentBundle.layouts
        .where((item) => item.projectionId == projection.id)
        .firstOrNull;
    final nodesById = <NodeInstanceId, NodeInstance>{
      for (final node in currentBundle.topology.nodes) node.id: node,
    };
    final edgesById = <EdgeInstanceId, EdgeInstance>{
      for (final edge in currentBundle.topology.edges) edge.id: edge,
    };
    final scenariosById = <ScenarioId, Scenario>{
      for (final scenario in catalog.scenarios) scenario.id: scenario,
    };
    final framesById = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in layout?.nodeFrames ?? const <ProjectionNodeFrame>[])
        frame.nodeInstanceId: frame,
    };
    final groupsById = <ProjectionGroupId, ProjectionGroup>{
      for (final group in layout?.groups ?? const <ProjectionGroup>[])
        group.id: group,
    };
    final lanesById = <ProjectionLaneId, ProjectionLane>{
      for (final lane in layout?.lanes ?? const <ProjectionLane>[])
        lane.id: lane,
    };
    final occurrences = <InventoryOccurrence>[
      for (final nodeId in projection.nodeInstanceIds)
        if (nodesById[nodeId] case final node?)
          if (scenariosById[node.scenarioId] case final scenario?)
            InventoryOccurrence(
              projection: projection,
              node: node,
              scenario: scenario,
              frame: framesById[node.id],
              group: groupsById[framesById[node.id]?.groupId],
              lane: lanesById[framesById[node.id]?.laneId],
            ),
    ];
    return InventoryProjectionResolution._(
      status: layout == null
          ? InventoryProjectionStatus.layoutAbsent
          : InventoryProjectionStatus.ready,
      projection: projection,
      layout: layout,
      occurrences: List<InventoryOccurrence>.unmodifiable(occurrences),
      edges: List<EdgeInstance>.unmodifiable(
        projection.edgeInstanceIds.map((id) => edgesById[id]!),
      ),
    );
  }

  List<ExperienceOccurrenceTarget> nodesForScenario({
    required ProjectionKind kind,
    required ApplicationId applicationId,
    required ScenarioId scenarioId,
  }) {
    final currentBundle = bundle;
    if (currentBundle == null) return const <ExperienceOccurrenceTarget>[];
    final projectionsById = <ExperienceProjectionId, ExperienceProjection>{
      for (final projection in currentBundle.topology.projections)
        if (projection.kind == kind &&
            projection.applicationId == applicationId)
          projection.id: projection,
    };
    return List<ExperienceOccurrenceTarget>.unmodifiable(
      <ExperienceOccurrenceTarget>[
        for (final node in currentBundle.topology.nodes)
          if (node.scenarioId == scenarioId)
            if (projectionsById[node.projectionId] case final projection?)
              ExperienceOccurrenceTarget(projection: projection, node: node),
      ],
    );
  }

  ExperienceOccurrenceTarget? uniqueNodeForScenario({
    required ProjectionKind kind,
    required ApplicationId applicationId,
    required ScenarioId scenarioId,
  }) {
    final matches = nodesForScenario(
      kind: kind,
      applicationId: applicationId,
      scenarioId: scenarioId,
    );
    return matches.length == 1 ? matches.single : null;
  }
}

final class InventoryProjectionResolution {
  const InventoryProjectionResolution._({
    required this.status,
    this.projection,
    this.layout,
    this.occurrences = const <InventoryOccurrence>[],
    this.edges = const <EdgeInstance>[],
  });

  final InventoryProjectionStatus status;
  final ExperienceProjection? projection;
  final ProjectionLayoutManifest? layout;
  final List<InventoryOccurrence> occurrences;
  final List<EdgeInstance> edges;

  bool get hasProjection => projection != null;
  bool get isSpatial => status == InventoryProjectionStatus.ready;

  String get fallbackMessage => switch (status) {
    InventoryProjectionStatus.topologyAbsent =>
      'O Host não publicou topologia de Experience para este catálogo.',
    InventoryProjectionStatus.projectionAbsent =>
      'A Projection solicitada não existe no ExperienceTopologyBundle.',
    InventoryProjectionStatus.projectionKindMismatch =>
      'A Projection solicitada não é uma lens Inventory.',
    InventoryProjectionStatus.layoutAbsent =>
      'A Inventory Projection existe, mas não possui ProjectionLayout publicado.',
    InventoryProjectionStatus.ready => '',
  };
}

final class InventoryFilters {
  InventoryFilters({
    this.query = '',
    this.applicationId,
    this.lifecycle,
    this.scenarioKindId,
    this.surfaceId,
    this.stateId,
    this.ownershipAreaId,
    this.tagId,
    this.componentId,
    this.fixtureId,
    this.renderSourceKind,
    this.frameKind,
    this.formFactorId,
    this.groupId,
    this.laneId,
    this.sourceRepository,
    this.sourcePath = '',
    this.providerId,
    this.variantId,
    this.evidenceStatus,
    this.freshness,
    this.fidelity,
    Set<String> invalidParameters = const <String>{},
  }) : invalidParameters = Set<String>.unmodifiable(invalidParameters);

  factory InventoryFilters.fromQueryParameters(Map<String, String> values) {
    final invalid = <String>{};
    final query = _boundedQuery(values['q'], 'q', 2048, invalid);
    final sourceRepository = _boundedOptional(
      values['sourceRepository'],
      'sourceRepository',
      512,
      invalid,
    );
    final sourcePath = _boundedQuery(
      values['sourcePath'],
      'sourcePath',
      4096,
      invalid,
    );
    return InventoryFilters(
      query: query,
      applicationId: _opaque(
        values['application'],
        'application',
        ApplicationId.new,
        invalid,
      ),
      lifecycle: _enumValue(
        values['lifecycle'],
        'lifecycle',
        ScenarioLifecycle.values,
        invalid,
      ),
      scenarioKindId: _opaque(
        values['kind'],
        'kind',
        ScenarioKindId.new,
        invalid,
      ),
      surfaceId: _opaque(
        values['surface'],
        'surface',
        ExperienceSurfaceId.new,
        invalid,
      ),
      stateId: _opaque(values['state'], 'state', ScenarioStateId.new, invalid),
      ownershipAreaId: _opaque(
        values['owner'],
        'owner',
        OwnershipAreaId.new,
        invalid,
      ),
      tagId: _opaque(values['tag'], 'tag', ScenarioTagId.new, invalid),
      componentId: _opaque(
        values['component'],
        'component',
        ExperienceComponentId.new,
        invalid,
      ),
      fixtureId: _opaque(
        values['fixture'],
        'fixture',
        ScenarioFixtureId.new,
        invalid,
      ),
      renderSourceKind: _enumValue(
        values['render'],
        'render',
        ScenarioRenderSourceKind.values,
        invalid,
      ),
      frameKind: _enumValue(
        values['frame'],
        'frame',
        PresentationFrameKind.values,
        invalid,
      ),
      formFactorId: _opaque(
        values['formFactor'],
        'formFactor',
        FormFactorId.new,
        invalid,
      ),
      groupId: _opaque(
        values['group'],
        'group',
        ProjectionGroupId.new,
        invalid,
      ),
      laneId: _opaque(values['lane'], 'lane', ProjectionLaneId.new, invalid),
      sourceRepository: sourceRepository,
      sourcePath: sourcePath,
      providerId: _opaque(
        values['provider'],
        'provider',
        ModuleId.new,
        invalid,
      ),
      variantId: _opaque(values['variant'], 'variant', VariantId.new, invalid),
      evidenceStatus: _enumValue(
        values['evidenceStatus'],
        'evidenceStatus',
        VisualEvidenceStatus.values,
        invalid,
      ),
      freshness: _enumValue(
        values['freshness'],
        'freshness',
        EvidenceFreshness.values,
        invalid,
      ),
      fidelity: _enumValue(
        values['fidelity'],
        'fidelity',
        RuntimeFidelity.values,
        invalid,
      ),
      invalidParameters: invalid,
    );
  }

  final String query;
  final ApplicationId? applicationId;
  final ScenarioLifecycle? lifecycle;
  final ScenarioKindId? scenarioKindId;
  final ExperienceSurfaceId? surfaceId;
  final ScenarioStateId? stateId;
  final OwnershipAreaId? ownershipAreaId;
  final ScenarioTagId? tagId;
  final ExperienceComponentId? componentId;
  final ScenarioFixtureId? fixtureId;
  final ScenarioRenderSourceKind? renderSourceKind;
  final PresentationFrameKind? frameKind;
  final FormFactorId? formFactorId;
  final ProjectionGroupId? groupId;
  final ProjectionLaneId? laneId;
  final String? sourceRepository;
  final String sourcePath;
  final ModuleId? providerId;
  final VariantId? variantId;
  final VisualEvidenceStatus? evidenceStatus;
  final EvidenceFreshness? freshness;
  final RuntimeFidelity? fidelity;
  final Set<String> invalidParameters;

  bool get hasEvidenceFilter =>
      providerId != null ||
      variantId != null ||
      evidenceStatus != null ||
      freshness != null ||
      fidelity != null;

  bool get hasScenarioFacetFilter =>
      lifecycle != null ||
      scenarioKindId != null ||
      surfaceId != null ||
      stateId != null ||
      ownershipAreaId != null ||
      tagId != null ||
      componentId != null ||
      fixtureId != null ||
      renderSourceKind != null ||
      frameKind != null ||
      formFactorId != null;

  Map<String, String> toQueryParameters() => <String, String>{
    if (query.isNotEmpty) 'q': query,
    if (applicationId != null) 'application': applicationId!.value,
    if (lifecycle != null) 'lifecycle': lifecycle!.name,
    if (scenarioKindId != null) 'kind': scenarioKindId!.value,
    if (surfaceId != null) 'surface': surfaceId!.value,
    if (stateId != null) 'state': stateId!.value,
    if (ownershipAreaId != null) 'owner': ownershipAreaId!.value,
    if (tagId != null) 'tag': tagId!.value,
    if (componentId != null) 'component': componentId!.value,
    if (fixtureId != null) 'fixture': fixtureId!.value,
    if (renderSourceKind != null) 'render': renderSourceKind!.name,
    if (frameKind != null) 'frame': frameKind!.name,
    if (formFactorId != null) 'formFactor': formFactorId!.value,
    if (groupId != null) 'group': groupId!.value,
    if (laneId != null) 'lane': laneId!.value,
    'sourceRepository': ?sourceRepository,
    if (sourcePath.isNotEmpty) 'sourcePath': sourcePath,
    if (providerId != null) 'provider': providerId!.value,
    if (variantId != null) 'variant': variantId!.value,
    if (evidenceStatus != null) 'evidenceStatus': evidenceStatus!.name,
    if (freshness != null) 'freshness': freshness!.name,
    if (fidelity != null) 'fidelity': fidelity!.name,
  };
}

final class InventoryFilterResult {
  const InventoryFilterResult({
    required this.matches,
    required this.visible,
    required this.selectedWasPreserved,
  });

  final List<InventoryOccurrence> matches;
  final List<InventoryOccurrence> visible;
  final bool selectedWasPreserved;
}

final class InventoryOccurrenceFilter {
  const InventoryOccurrenceFilter();

  InventoryFilterResult apply({
    required Iterable<InventoryOccurrence> occurrences,
    required InventoryFilters filters,
    Iterable<VisualEvidenceProjection> evidence =
        const <VisualEvidenceProjection>[],
    Set<ScenarioId>? scenarioScope,
    NodeInstanceId? selectedNodeId,
  }) {
    final source = List<InventoryOccurrence>.of(occurrences);
    final evidenceByScenario = <ScenarioId, List<VisualEvidenceProjection>>{};
    for (final projection in evidence) {
      if (projection.scenarioId case final scenarioId?) {
        evidenceByScenario
            .putIfAbsent(scenarioId, () => <VisualEvidenceProjection>[])
            .add(projection);
      }
    }
    final matches = filters.invalidParameters.isNotEmpty
        ? <InventoryOccurrence>[]
        : source
              .where(
                (item) => _matches(
                  item,
                  filters,
                  evidenceByScenario[item.scenario.id] ??
                      const <VisualEvidenceProjection>[],
                  scenarioScope,
                ),
              )
              .toList(growable: false);
    final matchedIds = matches.map((item) => item.node.id).toSet();
    final selected = selectedNodeId == null
        ? null
        : source.where((item) => item.node.id == selectedNodeId).firstOrNull;
    final preserveSelected =
        selected != null && !matchedIds.contains(selected.node.id);
    return InventoryFilterResult(
      matches: List<InventoryOccurrence>.unmodifiable(matches),
      visible: List<InventoryOccurrence>.unmodifiable(<InventoryOccurrence>[
        ...matches,
        if (preserveSelected) selected,
      ]),
      selectedWasPreserved: preserveSelected,
    );
  }

  bool _matches(
    InventoryOccurrence item,
    InventoryFilters filters,
    List<VisualEvidenceProjection> evidence,
    Set<ScenarioId>? scenarioScope,
  ) {
    if (scenarioScope != null && !scenarioScope.contains(item.scenario.id)) {
      return false;
    }
    if (filters.applicationId != null &&
        item.projection.applicationId != filters.applicationId) {
      return false;
    }
    if (filters.groupId != null && item.group?.id != filters.groupId) {
      return false;
    }
    if (filters.laneId != null && item.lane?.id != filters.laneId) {
      return false;
    }
    if (filters.sourceRepository != null &&
        !item.scenario.sourceReferences.any(
          (source) => source.repository == filters.sourceRepository,
        )) {
      return false;
    }
    final sourcePath = filters.sourcePath.toLowerCase();
    if (sourcePath.isNotEmpty &&
        !item.scenario.sourceReferences.any(
          (source) =>
              source.path.toLowerCase().contains(sourcePath) ||
              (source.symbol?.toLowerCase().contains(sourcePath) ?? false),
        )) {
      return false;
    }
    final query = filters.query.toLowerCase();
    if (query.isNotEmpty && !_searchText(item).contains(query)) return false;
    if (filters.hasEvidenceFilter &&
        !evidence.any((projection) => _matchesEvidence(projection, filters))) {
      return false;
    }
    return true;
  }

  String _searchText(InventoryOccurrence item) => <String>[
    item.node.id.value,
    item.scenario.id.value,
    item.scenario.title,
    item.scenario.description ?? '',
    item.projection.id.value,
    item.projection.title,
    item.group?.id.value ?? '',
    item.group?.title ?? '',
    item.lane?.id.value ?? '',
    item.lane?.title ?? '',
    for (final source in item.scenario.sourceReferences) ...<String>[
      source.repository,
      source.path,
      source.symbol ?? '',
    ],
  ].join('\n').toLowerCase();

  bool _matchesEvidence(
    VisualEvidenceProjection projection,
    InventoryFilters filters,
  ) =>
      projection.status != VisualEvidenceStatus.unbound &&
      (filters.providerId == null ||
          projection.providerId == filters.providerId) &&
      (filters.variantId == null ||
          projection.variantId == filters.variantId) &&
      (filters.evidenceStatus == null ||
          projection.status == filters.evidenceStatus) &&
      (filters.freshness == null ||
          projection.freshness == filters.freshness) &&
      (filters.fidelity == null || projection.fidelity == filters.fidelity);
}

T? _opaque<T>(
  String? value,
  String key,
  T Function(String) create,
  Set<String> invalid,
) {
  if (value == null || value.isEmpty) return null;
  try {
    return create(value);
  } on FormatException {
    invalid.add(key);
    return null;
  }
}

T? _enumValue<T extends Enum>(
  String? value,
  String key,
  List<T> values,
  Set<String> invalid,
) {
  if (value == null || value.isEmpty) return null;
  final match = values.where((item) => item.name == value).firstOrNull;
  if (match == null) invalid.add(key);
  return match;
}

String _boundedQuery(
  String? value,
  String key,
  int maximumLength,
  Set<String> invalid,
) {
  if (value == null || value.isEmpty) return '';
  if (value.length > maximumLength) {
    invalid.add(key);
    return '';
  }
  return value;
}

String? _boundedOptional(
  String? value,
  String key,
  int maximumLength,
  Set<String> invalid,
) {
  if (value == null || value.isEmpty) return null;
  if (value.length > maximumLength) {
    invalid.add(key);
    return null;
  }
  return value;
}
