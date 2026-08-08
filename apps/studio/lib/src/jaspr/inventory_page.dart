import 'dart:math' as math;

import 'package:experience_contracts/experience_contracts.dart';
import 'package:interaction_model/interaction_model.dart'
    show
        SpatialPoint,
        SpatialRect,
        SpatialEdge,
        SpatialIndex,
        SpatialItem,
        SpatialViewport,
        SpatialWindowPolicy,
        SequenceWindowPolicy;
import 'package:jaspr/dom.dart' hide Transition;
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/inventory/inventory_catalog.dart';
import 'package:studio/src/inventory/inventory_projection.dart';
import 'package:studio/src/jaspr/verified_artifact_image.dart';
import 'package:studio/src/journey_map/visual_evidence_presentation.dart';
import 'package:studio_ui/studio_ui.dart';

final class InventoryPage extends StatelessComponent {
  const InventoryPage({
    required this.enabled,
    required this.journeyEnabled,
    required this.snapshot,
    required this.bundle,
    required this.facets,
    required this.queryParameters,
    this.projectionId,
    this.nodeId,
    this.resourceClient,
    super.key,
  });

  final bool enabled;
  final bool journeyEnabled;
  final WorkspaceSnapshot snapshot;
  final ExperienceTopologyBundle? bundle;
  final ScenarioFacetManifest? facets;
  final Map<String, String> queryParameters;
  final String? projectionId;
  final String? nodeId;
  final StudioHostResourceClient? resourceClient;

  @override
  Component build(BuildContext context) {
    if (!enabled) {
      return const StudioEmptyState(
        title: 'Inventory não habilitada',
        message:
            'O ResolvedKitPlan atual não publicou a contribution studio.inventory.',
        tone: PresentationTone.warning,
      );
    }
    final filters = InventoryFilters.fromQueryParameters(queryParameters);
    final index = InventoryProjectionIndex(
      catalog: snapshot.catalog,
      bundle: bundle,
    );
    final catalogAdapter = InventoryCatalogAdapter(
      catalog: snapshot.catalog,
      facets: facets,
    );
    final requestedProjectionId = projectionId;
    if (requestedProjectionId == null) {
      return _projectionIndex(
        context,
        index,
        catalogAdapter.resolve(filters),
        filters,
      );
    }
    return _projection(
      context,
      index,
      catalogAdapter,
      index.resolve(requestedProjectionId),
      filters,
    );
  }

  Component _projectionIndex(
    BuildContext context,
    InventoryProjectionIndex index,
    InventoryCatalogResolution catalogResolution,
    InventoryFilters filters,
  ) {
    final applicationsById = <ApplicationId, Application>{
      for (final application in snapshot.catalog.applications)
        application.id: application,
    };
    final query = filters.query.toLowerCase();
    final projections = index
        .inventoryProjections(applicationId: filters.applicationId)
        .where((projection) {
          final application = applicationsById[projection.applicationId];
          return query.isEmpty ||
              projection.id.value.toLowerCase().contains(query) ||
              projection.title.toLowerCase().contains(query) ||
              (application?.displayName.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    final applications = snapshot.catalog.applications;
    final manifest = facets;

    return section(classes: 'inventory-index page-stack', <Component>[
      StudioPageHeader(
        eyebrow: 'CATÁLOGO CANÔNICO + LENSES AUTORAIS',
        title: 'Inventory',
        description:
            'Todos os Scenarios do catálogo quando a taxonomia adjacente está publicada; projections espaciais permanecem lenses de occurrences separadas.',
      ),
      div(
        classes: 'inventory-index__filters',
        attributes: const <String, String>{
          'data-inventory-filter-source': 'url',
        },
        <Component>[
          StudioSearchField(
            id: 'inventory-index-query',
            label: 'Buscar Scenario',
            value: filters.query,
            placeholder: 'Título, ID ou taxonomia',
            onInput: (value) => _replaceFilter(
              context,
              path: '/inventory',
              filters: filters,
              key: 'q',
              value: value,
            ),
          ),
          StudioSelect(
            id: 'inventory-index-application',
            label: 'Application',
            value: filters.applicationId?.value ?? '',
            options: <StudioSelectOption>[
              const StudioSelectOption(value: '', label: 'Todas'),
              for (final application in applications)
                StudioSelectOption(
                  value: application.id.value,
                  label: application.displayName,
                ),
            ],
            onChange: (value) => _replaceFilter(
              context,
              path: '/inventory',
              filters: filters,
              key: 'application',
              value: value,
            ),
          ),
          if (manifest != null) ...<Component>[
            StudioSelect(
              id: 'inventory-index-lifecycle',
              label: 'Lifecycle',
              value: filters.lifecycle?.name ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todos'),
                for (final value in ScenarioLifecycle.values)
                  StudioSelectOption(value: value.name, label: value.name),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: '/inventory',
                filters: filters,
                key: 'lifecycle',
                value: value,
              ),
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-kind',
              label: 'Kind',
              key: 'kind',
              value: filters.scenarioKindId?.value,
              options: <(String, String)>[
                for (final item in manifest.scenarioKinds)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-surface',
              label: 'Surface',
              key: 'surface',
              value: filters.surfaceId?.value,
              options: <(String, String)>[
                for (final item in manifest.surfaces)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-state',
              label: 'State',
              key: 'state',
              value: filters.stateId?.value,
              options: <(String, String)>[
                for (final item in manifest.states)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-owner',
              label: 'Owner',
              key: 'owner',
              value: filters.ownershipAreaId?.value,
              options: <(String, String)>[
                for (final item in manifest.ownershipAreas)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-tag',
              label: 'Tag',
              key: 'tag',
              value: filters.tagId?.value,
              options: <(String, String)>[
                for (final item in manifest.tags)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-component',
              label: 'Component',
              key: 'component',
              value: filters.componentId?.value,
              options: <(String, String)>[
                for (final item in manifest.components)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-fixture',
              label: 'Fixture',
              key: 'fixture',
              value: filters.fixtureId?.value,
              options: <(String, String)>[
                for (final item in manifest.fixtures)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
            StudioSelect(
              id: 'inventory-index-render',
              label: 'Render source',
              value: filters.renderSourceKind?.name ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todos'),
                for (final value in ScenarioRenderSourceKind.values)
                  StudioSelectOption(value: value.name, label: value.name),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: '/inventory',
                filters: filters,
                key: 'render',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-index-frame',
              label: 'Frame',
              value: filters.frameKind?.name ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todos'),
                for (final value in PresentationFrameKind.values)
                  StudioSelectOption(value: value.name, label: value.name),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: '/inventory',
                filters: filters,
                key: 'frame',
                value: value,
              ),
            ),
            _taxonomySelect(
              context,
              id: 'inventory-index-form-factor',
              label: 'Form factor',
              key: 'formFactor',
              value: filters.formFactorId?.value,
              options: <(String, String)>[
                for (final item in manifest.formFactors)
                  (item.id.value, item.displayName),
              ],
              filters: filters,
            ),
          ],
          StudioButton(
            label: 'Limpar filtros',
            kind: StudioButtonKind.quiet,
            leadingIcon: StudioIconName.close,
            disabled: filters.toQueryParameters().isEmpty,
            onPressed: () => context.replace('/inventory'),
          ),
        ],
      ),
      _invalidFilters(filters),
      section(classes: 'inventory-catalog-section', <Component>[
        header(classes: 'inventory-section-heading', <Component>[
          div(<Component>[
            const span(classes: 'studio-ui-eyebrow', <Component>[
              Component.text('SCENARIO INVENTORY'),
            ]),
            h2(<Component>[
              Component.text(
                catalogResolution.isReady
                    ? '${catalogResolution.entries.length}/${snapshot.catalog.scenarios.length} Scenarios'
                    : 'Taxonomia indisponível',
              ),
            ]),
          ]),
          if (manifest != null)
            small(<Component>[
              Component.text('Facet digest ${manifest.digest.value}'),
            ]),
        ]),
        if (!catalogResolution.isReady)
          const StudioEmptyState(
            title: 'Scenario Inventory indisponível',
            message:
                'O Host não publicou ScenarioFacetManifest. Nenhuma faceta é inferida de IDs, títulos, Source ou layout.',
            tone: PresentationTone.warning,
          )
        else if (catalogResolution.entries.isEmpty)
          const StudioEmptyState(
            title: 'Nenhum Scenario corresponde aos filtros',
            message: 'Remova ou ajuste os filtros presentes na URL.',
          )
        else
          div(classes: 'inventory-scenario-grid', <Component>[
            for (final entry in catalogResolution.entries)
              _catalogScenarioCard(index, entry, filters),
          ]),
      ]),
      section(classes: 'inventory-spatial-section', <Component>[
        header(classes: 'inventory-section-heading', <Component>[
          div(<Component>[
            const span(classes: 'studio-ui-eyebrow', <Component>[
              Component.text('LENSES ESPACIAIS'),
            ]),
            h2(<Component>[const Component.text('Inventory Projections')]),
          ]),
          const small(<Component>[
            Component.text(
              'Occurrences autoradas; não substituem o Scenario Inventory canônico.',
            ),
          ]),
        ]),
        if (bundle == null)
          const StudioEmptyState(
            title: 'Inventory Projection indisponível',
            message:
                'O Host não publicou ExperienceTopologyBundle para este catálogo.',
            tone: PresentationTone.warning,
          )
        else if (projections.isEmpty)
          const StudioEmptyState(
            title: 'Nenhuma Inventory Projection visível',
            message: 'Remova ou ajuste busca/Application presentes na URL.',
          )
        else
          div(classes: 'inventory-projection-grid', <Component>[
            for (final projection in projections)
              _projectionCard(
                projection,
                application: applicationsById[projection.applicationId],
                filters: filters,
              ),
          ]),
      ]),
      _facetBoundary(manifest),
    ]);
  }

  Component _projectionCard(
    ExperienceProjection projection, {
    required Application? application,
    required InventoryFilters filters,
  }) {
    final layout = bundle?.layouts
        .where((item) => item.projectionId == projection.id)
        .firstOrNull;
    return article(
      classes: 'inventory-projection-card',
      attributes: <String, String>{
        'data-inventory-projection-id': projection.id.value,
      },
      <Component>[
        Link(
          to: _location(
            '/inventory/${projection.id.value}',
            filters.toQueryParameters(),
          ),
          classes: 'inventory-projection-card__link',
          attributes: <String, String>{
            'aria-label': 'Abrir Inventory Projection ${projection.title}',
          },
          children: <Component>[
            span(classes: 'studio-ui-eyebrow', <Component>[
              Component.text(application?.displayName ?? 'Application'),
            ]),
            h2(<Component>[Component.text(projection.title)]),
            p(<Component>[
              Component.text(
                '${projection.nodeInstanceIds.length} NodeInstances · ${projection.edgeInstanceIds.length} EdgeInstances',
              ),
            ]),
            small(<Component>[
              Component.text(
                layout == null
                    ? 'Sem ProjectionLayout'
                    : 'Layout ${layout.digest.value}',
              ),
            ]),
          ],
        ),
      ],
    );
  }

  Component _taxonomySelect(
    BuildContext context, {
    required String id,
    required String label,
    required String key,
    required String? value,
    required List<(String, String)> options,
    required InventoryFilters filters,
  }) => StudioSelect(
    id: id,
    label: label,
    value: value ?? '',
    options: <StudioSelectOption>[
      const StudioSelectOption(value: '', label: 'Todos'),
      for (final option in options)
        StudioSelectOption(value: option.$1, label: option.$2),
    ],
    onChange: (value) => _replaceFilter(
      context,
      path: '/inventory',
      filters: filters,
      key: key,
      value: value,
    ),
  );

  Component _catalogScenarioCard(
    InventoryProjectionIndex occurrenceIndex,
    InventoryCatalogEntry entry,
    InventoryFilters filters,
  ) {
    final manifest = facets!;
    final facet = entry.facets;
    final kind = manifest.scenarioKinds
        .where((item) => item.id == facet.scenarioKindId)
        .single;
    final surface = manifest.surfaces
        .where((item) => item.id == facet.surfaceId)
        .single;
    final state = manifest.states
        .where((item) => item.id == facet.stateId)
        .single;
    final owner = manifest.ownershipAreas
        .where((item) => item.id == facet.ownershipAreaId)
        .single;
    final fixture = manifest.fixtures
        .where((item) => item.id == facet.fixtureId)
        .single;
    final tagsById = <ScenarioTagId, ScenarioTagDefinition>{
      for (final item in manifest.tags) item.id: item,
    };
    final componentsById =
        <ExperienceComponentId, ExperienceComponentDefinition>{
          for (final item in manifest.components) item.id: item,
        };
    final framesById = <PresentationFrameId, PresentationFrameDefinition>{
      for (final item in manifest.presentationFrames) item.id: item,
    };
    final formFactorsById = <FormFactorId, FormFactorDefinition>{
      for (final item in manifest.formFactors) item.id: item,
    };
    final frames = facet.presentationFrameIds
        .map((id) => framesById[id]!)
        .toList(growable: false);
    final occurrenceTarget = occurrenceIndex.uniqueNodeForScenario(
      kind: ProjectionKind.inventory,
      applicationId: entry.scenario.applicationId,
      scenarioId: entry.scenario.id,
    );
    final contents = <Component>[
      header(classes: 'inventory-scenario-card__header', <Component>[
        span(classes: 'studio-ui-eyebrow', <Component>[
          Component.text(entry.scenario.id.value),
        ]),
        h3(<Component>[Component.text(entry.scenario.title)]),
        if (entry.scenario.description case final description?)
          p(<Component>[Component.text(description)]),
      ]),
      StudioDefinitionList(
        items: <(String, String)>[
          ('Lifecycle', facet.lifecycle.name),
          ('Kind', kind.displayName),
          ('Surface', surface.displayName),
          ('State', state.displayName),
          ('Owner', owner.displayName),
          ('Fixture', fixture.displayName),
          ('Render source', _renderSourceLabel(facet.renderSource)),
          (
            'Preferred frame',
            framesById[facet.preferredPresentationFrameId]!.displayName,
          ),
        ],
      ),
      div(classes: 'inventory-taxonomy-list', <Component>[
        strong(<Component>[const Component.text('Tags')]),
        p(<Component>[
          Component.text(
            facet.tagIds.map((id) => tagsById[id]!.displayName).join(' · '),
          ),
        ]),
      ]),
      div(classes: 'inventory-taxonomy-list', <Component>[
        strong(<Component>[const Component.text('Components')]),
        p(<Component>[
          Component.text(
            facet.componentIds
                .map((id) => componentsById[id]!.displayName)
                .join(' · '),
          ),
        ]),
      ]),
      div(classes: 'inventory-taxonomy-list', <Component>[
        strong(<Component>[const Component.text('Presentation frames')]),
        p(<Component>[
          Component.text(
            frames
                .map(
                  (frame) =>
                      '${frame.displayName} (${frame.kind.name}${frame.formFactorId == null ? '' : ' · ${formFactorsById[frame.formFactorId]!.displayName}'})',
                )
                .join(' · '),
          ),
        ]),
      ]),
      if (occurrenceTarget == null)
        const small(<Component>[
          Component.text(
            'Sem occurrence Inventory única; nenhum deep link foi escolhido arbitrariamente.',
          ),
        ]),
    ];
    final attributes = <String, String>{
      'data-inventory-scenario-id': entry.scenario.id.value,
      'data-inventory-application': entry.scenario.applicationId.value,
      'data-inventory-lifecycle': facet.lifecycle.name,
      'data-inventory-kind': facet.scenarioKindId.value,
      'data-inventory-surface': facet.surfaceId.value,
      'data-inventory-state': facet.stateId.value,
      'data-inventory-owner': facet.ownershipAreaId.value,
      'data-inventory-tags': facet.tagIds.map((id) => id.value).join(','),
      'data-inventory-components': facet.componentIds
          .map((id) => id.value)
          .join(','),
      'data-inventory-fixture': facet.fixtureId.value,
      'data-inventory-render': facet.renderSource.kind.name,
      'data-inventory-frames': frames.map((item) => item.kind.name).join(','),
      'data-inventory-form-factors': frames
          .map((item) => item.formFactorId?.value)
          .whereType<String>()
          .join(','),
    };
    return article(
      id: 'inventory-scenario-${entry.scenario.id.value}',
      classes: 'inventory-scenario-card',
      attributes: attributes,
      <Component>[
        if (occurrenceTarget == null)
          div(classes: 'inventory-scenario-card__body', contents)
        else
          Link(
            to: _location(
              '/inventory/${occurrenceTarget.projection.id.value}/nodes/${occurrenceTarget.node.id.value}',
              filters.toQueryParameters(),
            ),
            classes: 'inventory-scenario-card__body',
            attributes: <String, String>{
              'aria-label':
                  'Abrir NodeInstance ${occurrenceTarget.node.id.value} do Scenario ${entry.scenario.title}',
            },
            children: contents,
          ),
      ],
    );
  }

  String _renderSourceLabel(ScenarioRenderSource source) => switch (source) {
    PreviewDescriptorRenderSource(:final previewId) =>
      'previewDescriptor · ${previewId.value}',
    ExecutionBindingRenderSource(:final bindingId) =>
      'executionBinding · ${bindingId.value}',
    ExternalHarnessRenderSource(:final providerId, :final harnessId) =>
      'externalHarness · ${providerId.value}/${harnessId.value}',
    ArchiveArtifactRenderSource(:final artifactDigest) =>
      'archiveArtifact · ${artifactDigest.value}',
  };

  Component _projection(
    BuildContext context,
    InventoryProjectionIndex index,
    InventoryCatalogAdapter catalogAdapter,
    InventoryProjectionResolution resolution,
    InventoryFilters filters,
  ) {
    if (!resolution.hasProjection) {
      return StudioEmptyState(
        title: 'Inventory Projection indisponível',
        message: resolution.fallbackMessage,
        tone: PresentationTone.warning,
        action: const Link(
          to: '/inventory',
          classes: 'studio-ui-button studio-ui-button--secondary',
          child: Component.text('Voltar à Inventory'),
        ),
      );
    }
    if (resolution.status == InventoryProjectionStatus.projectionKindMismatch) {
      return StudioEmptyState(
        title: 'Projection não é Inventory',
        message: resolution.fallbackMessage,
        tone: PresentationTone.warning,
        action: const Link(
          to: '/inventory',
          classes: 'studio-ui-button studio-ui-button--secondary',
          child: Component.text('Voltar à Inventory'),
        ),
      );
    }

    final projection = resolution.projection!;
    final routeNodeId = nodeId;
    final selected = routeNodeId == null
        ? null
        : resolution.occurrences
              .where((item) => item.node.id.value == routeNodeId)
              .firstOrNull;
    final result = const InventoryOccurrenceFilter().apply(
      occurrences: resolution.occurrences,
      filters: filters,
      evidence: snapshot.visualProjections,
      scenarioScope: catalogAdapter.scenarioScope(filters),
      selectedNodeId: selected?.node.id,
    );
    final outlineWindow = const SequenceWindowPolicy(maximumVisibleItems: 48)
        .around(
          result.visible,
          selectedIndex: math.max(
            0,
            result.visible.indexWhere(
              (occurrence) => occurrence.node.id == selected?.node.id,
            ),
          ),
        );
    final previousOutline = outlineWindow.before == 0
        ? null
        : result.visible[outlineWindow.start - 1];
    final nextOutline = outlineWindow.after == 0
        ? null
        : result.visible[outlineWindow.endExclusive];
    final path = routeNodeId == null
        ? '/inventory/${projection.id.value}'
        : '/inventory/${projection.id.value}/nodes/$routeNodeId';
    final applications = snapshot.catalog.applications;
    final groups = resolution.layout?.groups ?? const <ProjectionGroup>[];
    final lanes = resolution.layout?.lanes ?? const <ProjectionLane>[];
    final repositories =
        resolution.occurrences
            .expand((item) => item.scenario.sourceReferences)
            .map((item) => item.repository)
            .toSet()
            .toList()
          ..sort();
    final variants = snapshot.variantManifest.variants
        .where((item) => item.applicationId == projection.applicationId)
        .toList(growable: false);
    final hostEvidence = selected == null
        ? const <VisualEvidenceProjection>[]
        : _evidenceFor(selected.scenario.id, filters);
    final selectedFacet = selected == null
        ? null
        : facets?.scenarioFacets
              .where((item) => item.scenarioId == selected.scenario.id)
              .firstOrNull;

    return section(classes: 'inventory-page', <Component>[
      header(classes: 'inventory-toolbar', <Component>[
        div(classes: 'inventory-toolbar__title', <Component>[
          StudioBreadcrumbs(
            items: <StudioBreadcrumbItem>[
              const StudioBreadcrumbItem(label: 'Visão geral', href: '/'),
              const StudioBreadcrumbItem(
                label: 'Inventory',
                href: '/inventory',
              ),
              StudioBreadcrumbItem(label: projection.title),
            ],
          ),
          h1(<Component>[Component.text(projection.title)]),
          p(<Component>[
            const Component.text(
              'Occurrences do catálogo atual, sem inferir facetas ausentes.',
            ),
          ]),
        ]),
        div(
          classes: 'inventory-toolbar__filters',
          attributes: const <String, String>{
            'data-inventory-filter-source': 'url',
          },
          <Component>[
            StudioSearchField(
              id: 'inventory-query',
              label: 'Buscar occurrence',
              value: filters.query,
              placeholder: 'Node, Scenario ou Source',
              onInput: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'q',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-application',
              label: 'Application',
              value: filters.applicationId?.value ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todas'),
                for (final application in applications)
                  StudioSelectOption(
                    value: application.id.value,
                    label: application.displayName,
                  ),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'application',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-group',
              label: 'Group autoral',
              value: filters.groupId?.value ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todos'),
                for (final group in groups)
                  StudioSelectOption(value: group.id.value, label: group.title),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'group',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-lane',
              label: 'Lane autoral',
              value: filters.laneId?.value ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todas'),
                for (final lane in lanes)
                  StudioSelectOption(value: lane.id.value, label: lane.title),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'lane',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-source-repository',
              label: 'Repositório de Source',
              value: filters.sourceRepository ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todos'),
                for (final repository in repositories)
                  StudioSelectOption(value: repository, label: repository),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'sourceRepository',
                value: value,
              ),
            ),
            StudioSearchField(
              id: 'inventory-source-path',
              label: 'Path ou symbol de Source',
              value: filters.sourcePath,
              placeholder: 'lib/ ou nome do símbolo',
              onInput: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'sourcePath',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-provider',
              label: 'Evidence provider',
              value: filters.providerId?.value ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todos'),
                for (final provider in snapshot.providers)
                  StudioSelectOption(
                    value: provider.providerId.value,
                    label: provider.displayName,
                  ),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'provider',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-variant',
              label: 'Variant',
              value: filters.variantId?.value ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todas'),
                for (final variant in variants)
                  StudioSelectOption(
                    value: variant.id.value,
                    label: variant.id.value,
                  ),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'variant',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-evidence-status',
              label: 'Evidence status',
              value: filters.evidenceStatus?.name ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todos'),
                for (final status in VisualEvidenceStatus.values)
                  StudioSelectOption(
                    value: status.name,
                    label: visualEvidenceStatusFilterLabel(status),
                  ),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'evidenceStatus',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-freshness',
              label: 'Atualidade',
              value: filters.freshness?.name ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todas'),
                for (final freshness in EvidenceFreshness.values)
                  StudioSelectOption(
                    value: freshness.name,
                    label: evidenceFreshnessLabel(freshness),
                  ),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'freshness',
                value: value,
              ),
            ),
            StudioSelect(
              id: 'inventory-fidelity',
              label: 'Fidelidade',
              value: filters.fidelity?.name ?? '',
              options: <StudioSelectOption>[
                const StudioSelectOption(value: '', label: 'Todas'),
                for (final fidelity in RuntimeFidelity.values)
                  StudioSelectOption(
                    value: fidelity.name,
                    label: runtimeFidelityLabel(fidelity),
                  ),
              ],
              onChange: (value) => _replaceFilter(
                context,
                path: path,
                filters: filters,
                key: 'fidelity',
                value: value,
              ),
            ),
            StudioButton(
              label: 'Limpar filtros',
              kind: StudioButtonKind.quiet,
              leadingIcon: StudioIconName.close,
              disabled: filters.toQueryParameters().isEmpty,
              onPressed: () => context.replace(path),
            ),
          ],
        ),
        div(classes: 'inventory-toolbar__summary', <Component>[
          StudioStatusPill(
            label:
                '${result.matches.length}/${resolution.occurrences.length} occurrences',
            tone: result.matches.isEmpty
                ? PresentationTone.warning
                : PresentationTone.neutral,
          ),
          small(<Component>[
            Component.text('Projection ${projection.id.value}'),
          ]),
        ]),
      ]),
      _invalidFilters(filters),
      if (filters.hasScenarioFacetFilter)
        p(
          classes: 'inventory-facet-scope',
          attributes: <String, String>{
            'role': facets == null ? 'alert' : 'status',
            'data-inventory-facet-scope': facets == null
                ? 'unavailable'
                : 'active',
          },
          <Component>[
            Component.text(
              facets == null
                  ? 'A URL solicita facetas canônicas, mas o Host não publicou ScenarioFacetManifest; nenhum resultado foi ampliado por inferência.'
                  : 'A Projection está limitada pelas facetas canônicas presentes na URL. Edite esse escopo no Scenario Inventory.',
            ),
            if (facets != null)
              Link(
                to: _location('/inventory', filters.toQueryParameters()),
                classes: 'studio-ui-button studio-ui-button--quiet',
                child: const Component.text('Editar facetas'),
              ),
          ],
        ),
      if (result.selectedWasPreserved)
        const p(
          classes: 'inventory-selection-notice',
          attributes: <String, String>{'role': 'status'},
          <Component>[
            Component.text(
              'O NodeInstance selecionado não corresponde aos filtros atuais e foi preservado explicitamente.',
            ),
          ],
        ),
      div(classes: 'inventory-layout', <Component>[
        aside(
          classes: 'inventory-outline',
          attributes: const <String, String>{
            'aria-label': 'Outline da Inventory',
          },
          <Component>[
            header(classes: 'outline-header', <Component>[
              span(classes: 'studio-ui-eyebrow', <Component>[
                const Component.text('OUTLINE'),
              ]),
              h2(<Component>[
                Component.text(
                  '${result.visible.length} NodeInstances visíveis',
                ),
              ]),
            ]),
            if (result.visible.isEmpty)
              const StudioEmptyState(
                title: 'Nenhuma occurrence visível',
                message: 'Remova ou ajuste os filtros presentes na URL.',
              )
            else
              div(<Component>[
                ol(
                  classes: 'scenario-outline-list',
                  attributes: <String, String>{
                    'data-outline-total': '${outlineWindow.total}',
                    'data-outline-rendered': '${outlineWindow.items.length}',
                    'data-outline-start': '${outlineWindow.start}',
                  },
                  <Component>[
                    for (final occurrence in outlineWindow.items)
                      li(<Component>[
                        Link(
                          to: _nodeLocation(occurrence, filters),
                          classes:
                              'scenario-outline-item${occurrence.node.id == selected?.node.id ? ' is-selected' : ''}',
                          attributes: <String, String>{
                            if (occurrence.node.id == selected?.node.id)
                              'aria-current': 'page',
                            'data-node-instance-id': occurrence.node.id.value,
                          },
                          children: <Component>[
                            span(
                              classes: 'scenario-outline-item__copy',
                              <Component>[
                                strong(<Component>[
                                  Component.text(occurrence.scenario.title),
                                ]),
                                small(<Component>[
                                  Component.text(occurrence.node.id.value),
                                ]),
                              ],
                            ),
                            if (_preferredEvidence(
                                  occurrence.scenario.id,
                                  filters,
                                )
                                case final evidence?)
                              StudioStatusPill(
                                label: visualEvidenceStatusLabel(
                                  evidence.status,
                                  evidence.freshness,
                                ),
                                tone: _evidenceTone(evidence),
                              ),
                          ],
                        ),
                      ]),
                  ],
                ),
                if (outlineWindow.isVirtualized)
                  nav(
                    classes: 'scenario-outline-window',
                    attributes: const <String, String>{
                      'aria-label': 'Navegação da janela do Outline',
                    },
                    <Component>[
                      p(<Component>[
                        Component.text(
                          'Itens ${outlineWindow.start + 1}–${outlineWindow.endExclusive} de ${outlineWindow.total}.',
                        ),
                      ]),
                      if (previousOutline != null)
                        Link(
                          to: _nodeLocation(previousOutline, filters),
                          classes: 'studio-ui-button studio-ui-button--quiet',
                          child: const Component.text('Janela anterior'),
                        ),
                      if (nextOutline != null)
                        Link(
                          to: _nodeLocation(nextOutline, filters),
                          classes: 'studio-ui-button studio-ui-button--quiet',
                          child: const Component.text('Próxima janela'),
                        ),
                    ],
                  ),
              ]),
          ],
        ),
        section(classes: 'inventory-canvas', <Component>[
          if (result.visible.isEmpty)
            const StudioEmptyState(
              title: 'Inventory sem resultados',
              message: 'Os filtros da URL ocultaram todas as occurrences.',
            )
          else if (resolution.isSpatial)
            _spatialInventory(
              resolution: resolution,
              occurrences: result.visible,
              selected: selected,
              filters: filters,
            )
          else
            div(classes: 'journey-map-fallback', <Component>[
              StudioEmptyState(
                title: 'Layout espacial indisponível',
                message:
                    '${resolution.fallbackMessage} A lista preserva somente as occurrences declaradas pela Projection.',
                tone: PresentationTone.warning,
              ),
              div(classes: 'scenario-board is-list', <Component>[
                for (final occurrence in outlineWindow.items)
                  _occurrenceCard(
                    occurrence,
                    filters: filters,
                    selected: occurrence.node.id == selected?.node.id,
                  ),
              ]),
            ]),
        ]),
        aside(
          classes: 'inventory-inspector',
          attributes: const <String, String>{
            'aria-label': 'Inspector da Inventory',
          },
          <Component>[
            if (routeNodeId != null && selected == null)
              StudioEmptyState(
                title: 'NodeInstance não encontrado',
                message:
                    'A Projection ${projection.id.value} não contém $routeNodeId.',
                tone: PresentationTone.warning,
              )
            else if (selected == null)
              const StudioEmptyState(
                title: 'Selecione uma occurrence',
                message:
                    'O Inspector mostra identidade, layout, Source e Evidence sem inferir facetas.',
              )
            else
              _inspector(
                index,
                selected,
                resolution,
                hostEvidence,
                selectedFacet,
              ),
          ],
        ),
      ]),
    ]);
  }

  Component _spatialInventory({
    required InventoryProjectionResolution resolution,
    required List<InventoryOccurrence> occurrences,
    required InventoryOccurrence? selected,
    required InventoryFilters filters,
  }) {
    final layout = resolution.layout!;
    final framesByNode = <NodeInstanceId, ProjectionNodeFrame>{
      for (final frame in layout.nodeFrames) frame.nodeInstanceId: frame,
    };
    final occurrenceIds = occurrences.map((item) => item.node.id).toSet();
    final declaredEdges = resolution.edges
        .where(
          (edge) =>
              occurrenceIds.contains(edge.fromNodeId) &&
              occurrenceIds.contains(edge.toNodeId),
        )
        .toList(growable: false);
    final index = SpatialIndex(
      items: <SpatialItem>[
        for (final occurrence in occurrences)
          SpatialItem(
            id: occurrence.node.id.value,
            bounds: SpatialRect.fromLTWH(
              framesByNode[occurrence.node.id]!.x,
              framesByNode[occurrence.node.id]!.y,
              framesByNode[occurrence.node.id]!.width,
              framesByNode[occurrence.node.id]!.height,
            ),
          ),
      ],
      edges: <SpatialEdge>[
        for (final edge in declaredEdges)
          SpatialEdge(
            id: edge.id.value,
            fromId: edge.fromNodeId.value,
            toId: edge.toNodeId.value,
          ),
      ],
    );
    final bounds = index.contentBounds!;
    final zoom = layout.camera.zoom;
    final window =
        SpatialWindowPolicy(
          maximumVisibleItems: 64,
          maximumRenderableEdges: 256,
          maximumBoundaryEdges: 256,
          overscan: 160,
          minimumZoom: 0.05,
          maximumZoom: 64,
        ).window(
          index: index,
          viewport: SpatialViewport(
            worldOrigin: SpatialPoint(bounds.left, bounds.top),
            width: math.max(bounds.width * zoom, 1),
            height: math.max(bounds.height * zoom, 1),
            zoom: zoom,
          ),
          selectedItemId: selected?.node.id.value,
        );
    final renderedIds = window.itemIds.toSet();
    final renderedEdgeIds = window.renderableEdges
        .map((item) => item.id)
        .toSet();
    final rendered = occurrences
        .where((item) => renderedIds.contains(item.node.id.value))
        .toList(growable: false);
    final renderedEdges = declaredEdges
        .where((item) => renderedEdgeIds.contains(item.id.value))
        .toList(growable: false);
    final geometry = _InventoryCanvasGeometry(layout: layout, zoom: zoom);
    final transitions = <TransitionId, Transition>{
      for (final transition in snapshot.catalog.transitions)
        transition.id: transition,
    };
    const maximumDecorationsPerKind = 128;

    return div(
      classes: 'journey-map-viewport inventory-map-viewport',
      attributes: const <String, String>{
        'role': 'region',
        'aria-label': 'Viewport da Inventory',
        'tabindex': '0',
        'aria-describedby': 'inventory-map-instructions',
      },
      <Component>[
        p(id: 'inventory-map-instructions', classes: 'sr-only', <Component>[
          const Component.text(
            'Use o Outline ou as barras de rolagem para percorrer as occurrences autoradas.',
          ),
        ]),
        div(
          classes: 'journey-map-stage inventory-map-stage is-spatial',
          attributes: <String, String>{
            'data-projection-id': resolution.projection!.id.value,
            'data-projection-kind': ProjectionKind.inventory.name,
            'data-inventory-projection-id': resolution.projection!.id.value,
            'data-layout-digest': layout.digest.value,
            ...geometry.canvasAttributes(),
            'data-camera-x': '${layout.camera.x}',
            'data-camera-y': '${layout.camera.y}',
            'data-camera-zoom': '${layout.camera.zoom}',
            'data-window-candidates': '${window.visibleCandidateCount}',
            'data-window-rendered': '${rendered.length}',
            'data-renderable-edge-total': '${window.renderableEdgeCount}',
            'data-renderable-edge-rendered': '${renderedEdges.length}',
            'data-boundary-edge-total': '${window.boundaryEdgeCount}',
            'data-boundary-edge-retained': '${window.boundaryEdges.length}',
            'data-declared-edge-count': '${resolution.edges.length}',
          },
          <Component>[
            for (final lane in layout.lanes.take(maximumDecorationsPerKind))
              div(
                classes: 'journey-map-lane inventory-map-lane',
                attributes: <String, String>{
                  ...geometry.positionAttributes(
                    lane.x,
                    lane.y,
                    lane.width,
                    lane.height,
                  ),
                  'role': 'group',
                  'aria-label': 'Lane ${lane.title}',
                  'data-lane-id': lane.id.value,
                },
                <Component>[
                  span(<Component>[Component.text(lane.title)]),
                ],
              ),
            for (final group in layout.groups.take(maximumDecorationsPerKind))
              div(
                classes: 'journey-map-group inventory-map-group',
                attributes: <String, String>{
                  ...geometry.positionAttributes(
                    group.x,
                    group.y,
                    group.width,
                    group.height,
                  ),
                  'role': 'group',
                  'aria-label': 'Group ${group.title}',
                  'data-group-id': group.id.value,
                },
                <Component>[
                  span(<Component>[Component.text(group.title)]),
                ],
              ),
            svg(
              <Component>[
                for (final edge in renderedEdges)
                  _edge(
                    edge,
                    transition: transitions[edge.transitionId],
                    from: framesByNode[edge.fromNodeId]!,
                    to: framesByNode[edge.toNodeId]!,
                    geometry: geometry,
                  ),
              ],
              viewBox: geometry.viewBox,
              classes: 'journey-map-edges inventory-map-edges',
              attributes: <String, String>{
                'width': geometry.number(geometry.width),
                'height': geometry.number(geometry.height),
                'role': 'group',
                'aria-label': 'EdgeInstances declaradas da Inventory',
              },
            ),
            for (final edge in renderedEdges)
              _edgeLabel(
                edge,
                transition: transitions[edge.transitionId],
                from: framesByNode[edge.fromNodeId]!,
                to: framesByNode[edge.toNodeId]!,
                geometry: geometry,
              ),
            for (final annotation in layout.annotations.take(
              maximumDecorationsPerKind,
            ))
              aside(
                classes: 'journey-map-annotation inventory-map-annotation',
                attributes: <String, String>{
                  ...geometry.positionAttributes(
                    annotation.x,
                    annotation.y,
                    annotation.width,
                    annotation.height,
                  ),
                  'role': 'note',
                  'data-annotation-id': annotation.id.value,
                },
                <Component>[Component.text(annotation.text)],
              ),
            for (final occurrence in rendered)
              div(
                classes: 'journey-map-node inventory-map-node is-authored',
                attributes: <String, String>{
                  ...geometry.frameAttributes(
                    framesByNode[occurrence.node.id]!,
                  ),
                  'data-node-instance-id': occurrence.node.id.value,
                  'data-scenario-id': occurrence.scenario.id.value,
                  'data-inventory-node-id': occurrence.node.id.value,
                  'data-inventory-scenario-id': occurrence.scenario.id.value,
                },
                <Component>[
                  _occurrenceCard(
                    occurrence,
                    filters: filters,
                    selected: occurrence.node.id == selected?.node.id,
                  ),
                ],
              ),
          ],
        ),
        const p(
          classes: 'journey-map-geometry-unsupported',
          attributes: <String, String>{'role': 'status'},
          <Component>[
            Component.text(
              'Este navegador não oferece o suporte necessário para aplicar a geometria autorada com a política de segurança ativa. Use o Outline da Inventory.',
            ),
          ],
        ),
        if (window.isTruncated ||
            window.boundaryEdgeCount > 0 ||
            window.renderableEdgesTruncated)
          p(classes: 'journey-map-notice', <Component>[
            Component.text(
              'Janela espacial limitada a ${rendered.length} NodeInstances; '
              '${window.renderableEdgeCount - renderedEdges.length} conexões internas omitidas e '
              '${window.boundaryEdgeCount} conexões declaradas cruzam o limite.',
            ),
          ]),
      ],
    );
  }

  Component _edge(
    EdgeInstance edge, {
    required Transition? transition,
    required ProjectionNodeFrame from,
    required ProjectionNodeFrame to,
    required _InventoryCanvasGeometry geometry,
  }) {
    final fromX = geometry.x(from.x + from.width / 2);
    final fromY = geometry.y(from.y + from.height / 2);
    final toX = geometry.x(to.x + to.width / 2);
    final toY = geometry.y(to.y + to.height / 2);
    final label = transition?.label ?? transition?.id.value ?? edge.id.value;
    return line(
      const <Component>[],
      x1: geometry.number(fromX),
      y1: geometry.number(fromY),
      x2: geometry.number(toX),
      y2: geometry.number(toY),
      classes: 'journey-map-edge inventory-map-edge',
      attributes: <String, String>{
        'role': 'img',
        'aria-label':
            'EdgeInstance ${edge.id.value}: ${edge.fromNodeId.value} para ${edge.toNodeId.value}, $label',
        'data-edge-instance-id': edge.id.value,
        'data-from-node-id': edge.fromNodeId.value,
        'data-to-node-id': edge.toNodeId.value,
      },
    );
  }

  Component _edgeLabel(
    EdgeInstance edge, {
    required Transition? transition,
    required ProjectionNodeFrame from,
    required ProjectionNodeFrame to,
    required _InventoryCanvasGeometry geometry,
  }) {
    final fromX = geometry.x(from.x + from.width / 2);
    final fromY = geometry.y(from.y + from.height / 2);
    final toX = geometry.x(to.x + to.width / 2);
    final toY = geometry.y(to.y + to.height / 2);
    final label = transition?.label ?? transition?.id.value ?? edge.id.value;
    return span(
      classes: 'journey-map-edge__label inventory-map-edge__label',
      attributes: <String, String>{
        ...geometry.pointAttributes((fromX + toX) / 2, (fromY + toY) / 2),
        'aria-hidden': 'true',
        'data-edge-label-for': edge.id.value,
      },
      <Component>[Component.text(label)],
    );
  }

  Component _occurrenceCard(
    InventoryOccurrence occurrence, {
    required InventoryFilters filters,
    required bool selected,
  }) {
    final evidence = _preferredEvidence(occurrence.scenario.id, filters);
    final artifact = evidence?.artifactHandle;
    return article(
      id: 'inventory-card-${occurrence.node.id.value}',
      classes: 'scenario-card inventory-card${selected ? ' is-selected' : ''}',
      attributes: <String, String>{
        'data-inventory-projection-id': occurrence.projection.id.value,
        'data-inventory-node-id': occurrence.node.id.value,
        'data-inventory-scenario-id': occurrence.scenario.id.value,
      },
      <Component>[
        Link(
          to: _nodeLocation(occurrence, filters),
          classes: 'scenario-card__link inventory-card__link',
          attributes: <String, String>{
            if (selected) 'aria-current': 'page',
            'aria-label':
                'NodeInstance ${occurrence.node.id.value}, Scenario ${occurrence.scenario.title}',
          },
          children: <Component>[
            div(classes: 'scenario-card__media', <Component>[
              if (artifact != null && resourceClient != null)
                VerifiedArtifactImage(
                  handle: artifact,
                  client: resourceClient,
                  alt: 'Evidence visual de ${occurrence.scenario.title}',
                  classes: 'scenario-card__image',
                  loading: MediaLoading.lazy,
                )
              else
                div(classes: 'scenario-card__placeholder', <Component>[
                  strong(<Component>[
                    Component.text(
                      evidence == null
                          ? 'Sem Evidence vinculada'
                          : visualEvidenceStatusLabel(
                              evidence.status,
                              evidence.freshness,
                            ),
                    ),
                  ]),
                  small(<Component>[
                    Component.text(
                      evidence?.providerId.value ?? occurrence.node.id.value,
                    ),
                  ]),
                ]),
            ]),
            div(classes: 'scenario-card__body', <Component>[
              div(classes: 'scenario-card__meta', <Component>[
                span(<Component>[Component.text(occurrence.node.id.value)]),
                if (evidence != null)
                  StudioStatusPill(
                    label: visualEvidenceStatusLabel(
                      evidence.status,
                      evidence.freshness,
                    ),
                    tone: _evidenceTone(evidence),
                  ),
              ]),
              h3(<Component>[Component.text(occurrence.scenario.title)]),
              p(<Component>[
                Component.text(
                  occurrence.scenario.description ??
                      occurrence.scenario.id.value,
                ),
              ]),
            ]),
          ],
        ),
      ],
    );
  }

  Component _inspector(
    InventoryProjectionIndex index,
    InventoryOccurrence occurrence,
    InventoryProjectionResolution resolution,
    List<VisualEvidenceProjection> evidence,
    ScenarioFacet? facet,
  ) {
    final journeyTarget = journeyEnabled
        ? index.uniqueNodeForScenario(
            kind: ProjectionKind.journey,
            applicationId: occurrence.projection.applicationId,
            scenarioId: occurrence.scenario.id,
          )
        : null;
    return div(classes: 'inspector-stack inventory-inspector__content', <
      Component
    >[
      header(classes: 'inspector-header', <Component>[
        span(classes: 'studio-ui-eyebrow', <Component>[
          Component.text(occurrence.node.id.value),
        ]),
        h2(<Component>[Component.text(occurrence.scenario.title)]),
      ]),
      StudioDefinitionList(
        items: <(String, String)>[
          ('NodeInstance', occurrence.node.id.value),
          ('Scenario', occurrence.scenario.id.value),
          ('Projection', occurrence.projection.id.value),
          ('Projection kind', occurrence.projection.kind.name),
          ('Application', occurrence.projection.applicationId.value),
          if (resolution.layout != null)
            ('Layout digest', resolution.layout!.digest.value),
          ('Group', occurrence.group?.title ?? 'Não declarado'),
          ('Lane', occurrence.lane?.title ?? 'Não declarada'),
        ],
      ),
      if (facet != null) _facetInspector(facet),
      StudioPanel(
        title: 'Source',
        description: 'Referências declaradas no Scenario.',
        children: <Component>[
          if (occurrence.scenario.sourceReferences.isEmpty)
            const p(<Component>[Component.text('Nenhuma SourceReference.')])
          else
            ul(classes: 'inventory-source-list', <Component>[
              for (final source in occurrence.scenario.sourceReferences)
                li(<Component>[
                  code(<Component>[
                    Component.text(
                      '${source.repository}:${source.path}${source.symbol == null ? '' : '#${source.symbol}'}',
                    ),
                  ]),
                ]),
            ]),
        ],
      ),
      StudioPanel(
        title: 'Evidence',
        description: 'Bindings publicados no WorkspaceSnapshot.',
        children: <Component>[
          if (evidence.isEmpty)
            const p(<Component>[
              Component.text('Nenhuma Evidence corresponde à seleção atual.'),
            ])
          else
            ul(classes: 'inventory-evidence-list', <Component>[
              for (final item in evidence)
                li(<Component>[
                  strong(<Component>[Component.text(item.providerId.value)]),
                  span(<Component>[
                    Component.text(
                      '${item.variantId?.value ?? 'sem Variant'} · ${visualEvidenceStatusLabel(item.status, item.freshness)}${item.fidelity == null ? '' : ' · ${runtimeFidelityLabel(item.fidelity!)}'}',
                    ),
                  ]),
                ]),
            ]),
        ],
      ),
      if (journeyTarget != null)
        Link(
          to: '/journeys/${journeyTarget.projection.journeyId!.value}/nodes/${journeyTarget.node.id.value}',
          classes: 'studio-ui-button studio-ui-button--secondary',
          attributes: const <String, String>{
            'data-cross-lens': 'inventory-to-journey',
          },
          child: const Component.text('Abrir occurrence única na Journey'),
        )
      else if (journeyEnabled)
        const p(classes: 'inventory-cross-lens-note', <Component>[
          Component.text(
            'Não há uma occurrence Journey única para este Scenario; nenhum destino foi escolhido arbitrariamente.',
          ),
        ]),
    ]);
  }

  Component _facetInspector(ScenarioFacet facet) {
    final manifest = facets!;
    final kind = manifest.scenarioKinds
        .where((item) => item.id == facet.scenarioKindId)
        .single;
    final surface = manifest.surfaces
        .where((item) => item.id == facet.surfaceId)
        .single;
    final state = manifest.states
        .where((item) => item.id == facet.stateId)
        .single;
    final owner = manifest.ownershipAreas
        .where((item) => item.id == facet.ownershipAreaId)
        .single;
    final fixture = manifest.fixtures
        .where((item) => item.id == facet.fixtureId)
        .single;
    final tagsById = <ScenarioTagId, ScenarioTagDefinition>{
      for (final item in manifest.tags) item.id: item,
    };
    final componentsById =
        <ExperienceComponentId, ExperienceComponentDefinition>{
          for (final item in manifest.components) item.id: item,
        };
    final framesById = <PresentationFrameId, PresentationFrameDefinition>{
      for (final item in manifest.presentationFrames) item.id: item,
    };
    return StudioPanel(
      title: 'Scenario facets',
      description:
          'Taxonomia canônica do ScenarioFacetManifest ${manifest.digest.value}.',
      children: <Component>[
        StudioDefinitionList(
          items: <(String, String)>[
            ('Lifecycle', facet.lifecycle.name),
            ('Kind', kind.displayName),
            ('Surface', surface.displayName),
            ('State', state.displayName),
            ('Owner', owner.displayName),
            (
              'Tags',
              facet.tagIds.map((id) => tagsById[id]!.displayName).join(' · '),
            ),
            (
              'Components',
              facet.componentIds
                  .map((id) => componentsById[id]!.displayName)
                  .join(' · '),
            ),
            ('Fixture', fixture.displayName),
            ('Render source', _renderSourceLabel(facet.renderSource)),
            (
              'Frames',
              facet.presentationFrameIds
                  .map((id) => framesById[id]!.displayName)
                  .join(' · '),
            ),
          ],
        ),
      ],
    );
  }

  List<VisualEvidenceProjection> _evidenceFor(
    ScenarioId scenarioId,
    InventoryFilters filters,
  ) => snapshot.visualProjections
      .where(
        (item) =>
            item.status != VisualEvidenceStatus.unbound &&
            item.scenarioId == scenarioId &&
            (filters.providerId == null ||
                item.providerId == filters.providerId) &&
            (filters.variantId == null ||
                item.variantId == filters.variantId) &&
            (filters.evidenceStatus == null ||
                item.status == filters.evidenceStatus) &&
            (filters.freshness == null ||
                item.freshness == filters.freshness) &&
            (filters.fidelity == null || item.fidelity == filters.fidelity),
      )
      .toList(growable: false);

  VisualEvidenceProjection? _preferredEvidence(
    ScenarioId scenarioId,
    InventoryFilters filters,
  ) => _evidenceFor(scenarioId, filters).firstOrNull;

  PresentationTone _evidenceTone(VisualEvidenceProjection evidence) {
    if (evidence.status == VisualEvidenceStatus.collected &&
        evidence.freshness == EvidenceFreshness.fresh) {
      return PresentationTone.positive;
    }
    if (evidence.status == VisualEvidenceStatus.failed ||
        evidence.freshness == EvidenceFreshness.invalid) {
      return PresentationTone.critical;
    }
    return PresentationTone.warning;
  }

  Component _invalidFilters(InventoryFilters filters) =>
      filters.invalidParameters.isEmpty
      ? const Component.fragment(<Component>[])
      : p(
          classes: 'inventory-filter-error',
          attributes: const <String, String>{'role': 'alert'},
          <Component>[
            Component.text(
              'Filtros inválidos na URL: ${filters.invalidParameters.join(', ')}. Nenhuma occurrence foi ampliada por valores inválidos.',
            ),
          ],
        );

  Component _facetBoundary(ScenarioFacetManifest? manifest) => aside(
    classes: 'inventory-facet-boundary',
    attributes: <String, String>{
      'data-inventory-facets': manifest == null ? 'absent' : 'ready',
      if (manifest != null)
        'data-inventory-facet-digest': manifest.digest.value,
    },
    <Component>[
      strong(<Component>[
        Component.text(
          manifest == null
              ? 'Limite do content-set atual'
              : 'Taxonomia canônica publicada',
        ),
      ]),
      p(<Component>[
        Component.text(
          manifest == null
              ? 'Lifecycle, Kind, Surface, State, Owner, Tag, Component, Fixture, Render source, Frame e Form factor não foram publicados. Esta Inventory não os infere de IDs, títulos, lanes ou Source.'
              : 'As facetas acima vêm do ScenarioFacetManifest ${manifest.digest.value}; Groups, Lanes e ProjectionLayout continuam metadados de apresentação separados.',
        ),
      ]),
    ],
  );

  String _nodeLocation(
    InventoryOccurrence occurrence,
    InventoryFilters filters,
  ) => _location(
    '/inventory/${occurrence.projection.id.value}/nodes/${occurrence.node.id.value}',
    filters.toQueryParameters(),
  );

  void _replaceFilter(
    BuildContext context, {
    required String path,
    required InventoryFilters filters,
    required String key,
    required String value,
  }) {
    final next = filters.toQueryParameters();
    if (value.isEmpty) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    context.replace(_location(path, next));
  }

  String _location(String path, Map<String, String> query) =>
      Uri(path: path, queryParameters: query.isEmpty ? null : query).toString();
}

final class _InventoryCanvasGeometry {
  _InventoryCanvasGeometry({
    required ProjectionLayoutManifest layout,
    required this.zoom,
  }) {
    var bounds = SpatialRect.fromLTWH(layout.camera.x, layout.camera.y, 1, 1);
    for (final frame in layout.nodeFrames) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(frame.x, frame.y, frame.width, frame.height),
      );
    }
    for (final group in layout.groups) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(group.x, group.y, group.width, group.height),
      );
    }
    for (final lane in layout.lanes) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(lane.x, lane.y, lane.width, lane.height),
      );
    }
    for (final annotation in layout.annotations) {
      bounds = bounds.union(
        SpatialRect.fromLTWH(
          annotation.x,
          annotation.y,
          annotation.width,
          annotation.height,
        ),
      );
    }
    _bounds = bounds;
  }

  static const double _padding = 32;
  final double zoom;
  late final SpatialRect _bounds;

  double get width => _bounds.width * zoom + _padding * 2;
  double get height => _bounds.height * zoom + _padding * 2;
  String get viewBox => '0 0 ${number(width)} ${number(height)}';

  double x(double worldX) => (worldX - _bounds.left) * zoom + _padding;
  double y(double worldY) => (worldY - _bounds.top) * zoom + _padding;

  String number(double value) {
    if (!value.isFinite) {
      throw StateError('Inventory canvas geometry must remain finite');
    }
    final encoded = value.toString();
    return encoded.endsWith('.0')
        ? encoded.substring(0, encoded.length - 2)
        : encoded;
  }

  Map<String, String> canvasAttributes() => <String, String>{
    'data-canvas-width': number(width),
    'data-canvas-height': number(height),
  };

  Map<String, String> frameAttributes(ProjectionNodeFrame frame) =>
      positionAttributes(frame.x, frame.y, frame.width, frame.height);

  Map<String, String> pointAttributes(double canvasX, double canvasY) =>
      <String, String>{'data-x': number(canvasX), 'data-y': number(canvasY)};

  Map<String, String> positionAttributes(
    double worldX,
    double worldY,
    double worldWidth,
    double worldHeight,
  ) => <String, String>{
    'data-x': number(x(worldX)),
    'data-y': number(y(worldY)),
    'data-width': number(worldWidth * zoom),
    'data-height': number(worldHeight * zoom),
  };
}
