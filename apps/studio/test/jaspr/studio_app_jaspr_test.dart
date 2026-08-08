@TestOn('vm')
library;

import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/jaspr/studio_app.dart';
import 'package:studio/src/jaspr/verified_artifact_image.dart';
import 'package:studio_ui/studio_ui.dart';

void main() {
  testComponents('renders the authoritative workspace overview', (
    tester,
  ) async {
    final client = _PreviewClient(_workspaceSnapshot());
    tester.pumpComponent(
      StudioApplication(
        clientFactory: () => client,
        reconnectDelay: Duration.zero,
      ),
    );
    await tester.pump();

    expect(find.text('Host conectado'), findsOneComponent);
    expect(find.text('Visão geral'), findsComponents);
    expect(find.text('Cobertura visual'), findsOneComponent);
    expect(find.text('Primeira jornada'), findsOneComponent);
  });

  testComponents(
    'collects AutoPreview only after synthetic-data confirmation',
    (tester) async {
      final client = _PreviewClient(_workspaceSnapshot());
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(find.text('Descobrir'), findsComponents);
      expect(find.text('75%'), findsOneComponent);
      await tester.click(find.componentWithText(StudioButton, 'Ampliar'));
      expect(find.text('100%'), findsOneComponent);
      await tester.click(find.componentWithText(StudioButton, 'Ajustar'));
      expect(find.text('75%'), findsOneComponent);
      expect(find.text('Atualidade'), findsNothing);
      await tester.click(find.componentWithText(StudioButton, 'Filtros'));
      expect(find.text('Status'), findsOneComponent);
      expect(find.text('Atualidade'), findsOneComponent);
      expect(find.text('Fidelidade'), findsOneComponent);
      expect(find.text('Coletar AutoPreview'), findsOneComponent);
      await tester.click(
        find.componentWithText(StudioButton, 'Coletar AutoPreview'),
      );

      expect(find.text('Coletar AutoPreview?'), findsOneComponent);
      expect(client.collectCalls, 0);
      await tester.click(
        find.componentWithText(StudioButton, 'Confirmo dados sintéticos'),
      );
      await tester.pump();

      expect(client.collectCalls, 1);
      expect(client.lastApplicationId, 'sample-app');
      expect(client.lastScenarioId, 'discover');
      expect(client.lastVariantId, 'phone.light');
      expect(client.syntheticDataConfirmed, isTrue);
      expect(find.text('Coletar AutoPreview?'), findsNothing);
    },
    url: '/journeys/sample/scenarios/discover',
  );

  testComponents(
    'renders the authored nonlinear Journey projection and routes by NodeInstance',
    (tester) async {
      final snapshot = _workspaceSnapshot();
      final experience = _spatialExperienceBundle(snapshot.catalog);
      final layout = experience.layouts.single;
      final client = _PreviewClient(snapshot, experienceBundle: experience);

      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(client.contentCalls, 1);
      expect(client.lastContentCatalogDigest, snapshot.catalog.digest);
      expect(
        _domWithAttributes(<String, String>{
          'data-projection-id': 'sample-journey-spatial',
          'data-layout-digest': layout.digest.value,
          'data-canvas-width': '1000',
          'data-canvas-height': '514',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-node-instance-id': 'node-understand',
          'data-x': '374',
          'data-y': '68',
          'data-width': '198',
          'data-height': '126',
        }),
        findsOneComponent,
      );

      for (final nodeId in const <String>[
        'node-discover',
        'node-understand',
        'node-review',
      ]) {
        expect(
          _domWithAttributes(<String, String>{'data-node-instance-id': nodeId}),
          findsOneComponent,
        );
        expect(_domWithId('scenario-card-$nodeId'), findsOneComponent);
      }

      expect(
        _domWithAttributes(const <String, String>{
          'data-edge-instance-id': 'edge-discover-understand',
          'data-from-node-id': 'node-discover',
          'data-to-node-id': 'node-understand',
          'role': 'img',
          'aria-label':
              'EdgeInstance edge-discover-understand: node-discover para node-understand, discover-understand',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-edge-instance-id': 'edge-understand-review',
          'data-from-node-id': 'node-understand',
          'data-to-node-id': 'node-review',
          'role': 'img',
          'aria-label':
              'EdgeInstance edge-understand-review: node-understand para node-review, understand-review',
        }),
        findsOneComponent,
      );
      expect(
        _domWithTagAndAttributes('line', const <String, String>{
          'data-edge-instance-id': 'edge-discover-understand',
          'x1': '167',
          'y1': '329',
          'x2': '473',
          'y2': '131',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-edge-label-for': 'edge-discover-understand',
          'data-x': '320',
          'data-y': '230',
          'aria-hidden': 'true',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'role': 'region',
          'aria-label': 'Viewport do Journey Map',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-lane-id': 'lane-reviewer',
          'role': 'group',
          'aria-label': 'Lane Pessoa revisora',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-group-id': 'group-primary',
          'role': 'group',
          'aria-label': 'Group Fluxo principal',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-annotation-id': 'annotation-turn',
          'role': 'note',
        }),
        findsOneComponent,
      );
      expect(
        find.text('A geometria publicada faz uma curva explícita.'),
        findsOneComponent,
      );

      expect(
        _domWithAttributes(const <String, String>{
          'aria-current': 'step',
          'aria-label': 'NodeInstance node-understand, Scenario Compreender',
        }),
        findsOneComponent,
      );
      expect(find.text('NodeInstance'), findsOneComponent);
      expect(find.text('Projection'), findsOneComponent);
      expect(find.text('sample-journey-spatial'), findsOneComponent);
      expect(find.text('Layout digest'), findsOneComponent);
      expect(find.text(layout.digest.value), findsOneComponent);
      expect(_spatialGeometryWithInlineStyles(), findsNothing);
      expect(
        find.textContaining(
          'Este navegador não oferece o suporte necessário para aplicar a geometria autorada',
        ),
        findsOneComponent,
      );
    },
    url: '/journeys/sample/nodes/node-understand',
  );

  testComponents('renders an explicit semantic state when topology is absent', (
    tester,
  ) async {
    final client = _NoTopologyClient(_workspaceSnapshot());

    tester.pumpComponent(
      StudioApplication(
        clientFactory: () => client,
        reconnectDelay: Duration.zero,
      ),
    );
    await tester.pump();

    expect(client.openCalls, 1);
    expect(find.text('Layout espacial indisponível'), findsOneComponent);
    expect(
      find.textContaining(
        'O Host não publicou topologia de Experience para este catálogo.',
      ),
      findsOneComponent,
    );
    expect(
      find.textContaining(
        'A lista abaixo preserva somente a ordem semântica declarada pela Journey.',
      ),
      findsOneComponent,
    );
    expect(_domWithAttributeName('data-projection-id'), findsNothing);
    expect(_domWithId('scenario-card-discover'), findsOneComponent);
    expect(_domWithId('scenario-card-node-discover'), findsNothing);
  }, url: '/journeys/sample');

  testComponents(
    'routes an atomic Motion generation and preserves its static equivalent',
    (tester) async {
      final client = _MotionContextClient(_motionContextContent());
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();

      expect(find.text('Motion'), findsComponents);
      expect(find.text('Context Builder'), findsOneComponent);
      expect(find.text('Sequências temporais'), findsOneComponent);
      expect(
        find.text('Descobrir, compreender e então revisar.'),
        findsOneComponent,
      );
      expect(find.text('Full'), findsOneComponent);
      expect(find.text('Reduced'), findsOneComponent);
      expect(find.text('None'), findsOneComponent);
    },
    url: '/motion/sample-journey-spatial?scenarioId=understand',
  );

  testComponents(
    'routes semantic Context selection and exports it through the typed facade',
    (tester) async {
      final client = _MotionContextClient(_motionContextContent());
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () => client,
          reconnectDelay: Duration.zero,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Contexto determinístico'), findsOneComponent);
      expect(find.textContaining('scenario=understand'), findsOneComponent);
      await tester.click(
        find.componentWithText(StudioButton, 'Exportar contexto'),
      );
      await tester.pump();

      expect(client.buildCalls, 1);
      expect(
        client.lastRequest?.selection.boardId,
        BoardId('sample-product-board'),
      );
      expect(
        client.lastRequest?.selection.projectionId,
        ExperienceProjectionId('sample-journey-spatial'),
      );
      expect(
        client.lastRequest?.selection.scenarioId,
        ScenarioId('understand'),
      );
      expect(find.text('Export sanitizado'), findsOneComponent);
    },
    url: '/context/sample-journey-spatial?scenarioId=understand',
  );

  testComponents(
    'renders only a verified local artifact lease and releases it on dispose',
    (tester) async {
      final handle = ResourceHandle(
        uri: Uri.parse(
          'http://127.0.0.1:39011/resources/abcdefghijklmnopqrstuvwxyzABCDEF',
        ),
        digest: Digest.bytes(const <int>[1, 2, 3]),
        mediaType: 'image/png',
        size: 3,
        purpose: 'visual-artifact',
        expiresAt: DateTime.utc(2026, 8, 12),
      );
      final leaseCompleter = Completer<StudioResourceLease>();
      final client = _ResourceClient(leaseCompleter.future);
      var released = false;

      tester.pumpComponent(
        VerifiedArtifactImage(
          handle: handle,
          client: client,
          alt: 'Evidence verificada',
          classes: 'artifact',
        ),
      );
      await tester.pump();

      expect(client.openCalls, 1);
      expect(find.tag('img'), findsNothing);
      expect(find.text('Validando imagem'), findsOneComponent);

      leaseCompleter.complete(
        StudioResourceLease(
          uri: Uri.parse('blob:http://127.0.0.1/verified-artifact'),
          digest: handle.digest,
          mediaType: handle.mediaType,
          size: handle.size,
          releaseCallback: () => released = true,
        ),
      );
      await tester.pump();

      expect(
        find.byComponentPredicate(
          (component) =>
              component is DomComponent &&
              component.tag == 'img' &&
              component.attributes?['src'] ==
                  'blob:http://127.0.0.1/verified-artifact',
          description: 'verified blob image',
        ),
        findsOneComponent,
      );
      expect(
        find.byComponentPredicate(
          (component) =>
              component is DomComponent &&
              component.attributes?['src'] == handle.uri.toString(),
          description: 'raw Host resource URL',
        ),
        findsNothing,
      );

      tester.binding.detachRootComponent();
      await tester.pump();
      expect(released, isTrue);
    },
  );
}

WorkspaceSnapshot _workspaceSnapshot() {
  final catalog = sampleCatalogManifest();
  final providerId = ModuleId('evidence.auto-preview');
  final variant = Variant(
    id: VariantId('phone.light'),
    applicationId: ApplicationId('sample-app'),
    logicalWidth: 390,
    logicalHeight: 844,
    devicePixelRatio: 3,
    brightness: PreviewBrightness.light,
    localeTag: 'pt-BR',
  );
  return WorkspaceSnapshot(
    revision: 1,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: <Variant>[variant],
      sources: <VariantDefinitionSource>[
        VariantDefinitionSource(
          variantId: variant.id,
          sourceId: 'auto-preview.sample',
          sourceDigest: Digest.semantic(const <String, Object?>{'source': 1}),
        ),
      ],
    ),
    effectiveKitManifest: EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic(const <String, Object?>{'plan': 1}),
      modules: <EffectiveModuleState>[
        EffectiveModuleState(
          moduleId: providerId,
          state: ModuleRuntimeState.ready,
          health: ModuleHealth.healthy,
          effectiveCapabilities: <ModuleCapabilityRef>[
            ModuleCapabilityRef(id: 'evidence.visual', version: 1),
            ModuleCapabilityRef(id: 'evidence.auto-preview', version: 1),
          ],
        ),
        EffectiveModuleState(
          moduleId: ModuleId('studio.shell'),
          state: ModuleRuntimeState.ready,
          health: ModuleHealth.healthy,
          effectiveCapabilities: <ModuleCapabilityRef>[
            ModuleCapabilityRef(id: 'studio.shell', version: 1),
          ],
        ),
      ],
      commands: const <String>[],
      rpcMethods: const <String>[
        'preview.collect',
        'preview.status',
        'preview.cancel',
      ],
      studioContributions: const <String>['studio.shell', 'studio.journey-map'],
      generatedAt: DateTime.utc(2026, 8, 11),
    ),
    providers: <VisualEvidenceProviderState>[
      VisualEvidenceProviderState(
        providerId: providerId,
        displayName: 'AutoPreview',
        health: ModuleHealth.healthy,
        supportedFidelities: const <RuntimeFidelity>{
          RuntimeFidelity.structural,
        },
        supportsCollection: true,
      ),
    ],
    visualProjections: <VisualEvidenceProjection>[
      VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: ScenarioId('discover'),
        variantId: variant.id,
        capturePolicyId: 'static-v1',
        status: VisualEvidenceStatus.missing,
        freshness: EvidenceFreshness.missing,
      ),
    ],
    generatedAt: DateTime.utc(2026, 8, 11),
  );
}

ExperienceTopologyBundle _spatialExperienceBundle(CatalogManifest catalog) {
  final projectionId = ExperienceProjectionId('sample-journey-spatial');
  final boardId = BoardId('sample-product-board');
  final discoverNodeId = NodeInstanceId('node-discover');
  final understandNodeId = NodeInstanceId('node-understand');
  final reviewNodeId = NodeInstanceId('node-review');
  final discoverEdgeId = EdgeInstanceId('edge-discover-understand');
  final reviewEdgeId = EdgeInstanceId('edge-understand-review');
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Board espacial da amostra',
        projectionIds: <ExperienceProjectionId>[projectionId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: projectionId,
        boardId: boardId,
        applicationId: ApplicationId('sample-app'),
        title: 'Journey espacial da amostra',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('sample'),
        nodeInstanceIds: <NodeInstanceId>[
          discoverNodeId,
          understandNodeId,
          reviewNodeId,
        ],
        edgeInstanceIds: <EdgeInstanceId>[discoverEdgeId, reviewEdgeId],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: discoverNodeId,
        projectionId: projectionId,
        scenarioId: ScenarioId('discover'),
      ),
      NodeInstance(
        id: understandNodeId,
        projectionId: projectionId,
        scenarioId: ScenarioId('understand'),
      ),
      NodeInstance(
        id: reviewNodeId,
        projectionId: projectionId,
        scenarioId: ScenarioId('review'),
      ),
    ],

    edges: <EdgeInstance>[
      EdgeInstance(
        id: discoverEdgeId,
        projectionId: projectionId,
        transitionId: TransitionId('discover-understand'),
        fromNodeId: discoverNodeId,
        toNodeId: understandNodeId,
      ),
      EdgeInstance(
        id: reviewEdgeId,
        projectionId: projectionId,
        transitionId: TransitionId('understand-review'),
        fromNodeId: understandNodeId,
        toNodeId: reviewNodeId,
      ),
    ],
  );
  final groupId = ProjectionGroupId('group-primary');
  final laneId = ProjectionLaneId('lane-reviewer');
  final layout = ProjectionLayoutManifest(
    topologyDigest: topology.digest,
    projectionId: projectionId,
    nodeFrames: <ProjectionNodeFrame>[
      ProjectionNodeFrame(
        nodeInstanceId: discoverNodeId,
        x: 40,
        y: 260,
        width: 220,
        height: 140,
        groupId: groupId,
        laneId: laneId,
      ),
      ProjectionNodeFrame(
        nodeInstanceId: understandNodeId,
        x: 380,
        y: 40,
        width: 220,
        height: 140,
        groupId: groupId,
        laneId: laneId,
      ),
      ProjectionNodeFrame(
        nodeInstanceId: reviewNodeId,
        x: 760,
        y: 300,
        width: 220,
        height: 140,
        groupId: groupId,
        laneId: laneId,
      ),
    ],
    groups: <ProjectionGroup>[
      ProjectionGroup(
        id: groupId,
        title: 'Fluxo principal',
        x: 0,
        y: 0,
        width: 1040,
        height: 500,
      ),
    ],
    lanes: <ProjectionLane>[
      ProjectionLane(
        id: laneId,
        title: 'Pessoa revisora',
        x: 20,
        y: 20,
        width: 1000,
        height: 450,
      ),
    ],
    annotations: <ProjectionAnnotation>[
      ProjectionAnnotation(
        id: ProjectionAnnotationId('annotation-turn'),
        text: 'A geometria publicada faz uma curva explícita.',
        x: 360,
        y: 220,
        width: 280,
        height: 80,
      ),
    ],
    camera: ProjectionCamera(x: 300, y: 180, zoom: 0.9),
  );
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: <ProjectionLayoutManifest>[layout],
  );
}

Finder _domWithAttributes(Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM component with attributes $attributes',
    );

Finder _domWithTagAndAttributes(String tag, Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          component.tag == tag &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM <$tag> component with attributes $attributes',
    );

Finder _spatialGeometryWithInlineStyles() {
  const geometricClasses = <String>{
    'journey-map-stage',
    'journey-map-lane',
    'journey-map-group',
    'journey-map-edges',
    'journey-map-edge',
    'journey-map-edge__label',
    'journey-map-annotation',
    'journey-map-node',
  };
  return find.byComponentPredicate((component) {
    if (component is! DomComponent || component.styles == null) return false;
    final classes = component.classes?.split(RegExp(r'\s+')).toSet();
    return classes != null && classes.intersection(geometricClasses).isNotEmpty;
  }, description: 'spatial geometry component with inline styles');
}

Finder _domWithAttributeName(String attribute) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      (component.attributes?.containsKey(attribute) ?? false),
  description: 'DOM component with $attribute',
);

Finder _domWithId(String id) => find.byComponentPredicate(
  (component) => component is DomComponent && component.id == id,
  description: 'DOM component #$id',
);

final class _PreviewClient
    implements
        StudioHostClient,
        StudioHostPreviewClient,
        StudioHostContentClient {
  _PreviewClient(this.snapshot, {this.experienceBundle});

  final WorkspaceSnapshot snapshot;
  final ExperienceTopologyBundle? experienceBundle;
  int collectCalls = 0;
  int contentCalls = 0;
  String? lastApplicationId;
  String? lastScenarioId;
  String? lastVariantId;
  Digest? lastContentCatalogDigest;
  bool? syntheticDataConfirmed;

  @override
  Future<Map<String, Object?>> collectPreview({
    required String applicationId,
    String? scenarioId,
    String? variantId,
    required bool syntheticDataConfirmed,
  }) async {
    collectCalls += 1;
    lastApplicationId = applicationId;
    lastScenarioId = scenarioId;
    lastVariantId = variantId;
    this.syntheticDataConfirmed = syntheticDataConfirmed;
    return <String, Object?>{
      'operationId': 'preview-1',
      'state': 'completed',
      'completedItems': 1,
      'totalItems': 1,
      'failedItems': 0,
    };
  }

  @override
  Future<Map<String, Object?>> cancelPreview(String operationId) async =>
      <String, Object?>{
        'operationId': operationId,
        'state': 'cancelled',
        'completedItems': 0,
        'totalItems': 1,
        'failedItems': 0,
      };

  @override
  Future<void> close() async {}

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => snapshot;

  @override
  Future<StudioWorkspaceContent> openContent() async {
    contentCalls += 1;
    lastContentCatalogDigest = snapshot.catalog.digest;
    return _canonicalContent(snapshot, experienceBundle: experienceBundle);
  }

  @override
  Future<Map<String, Object?>> previewStatus(String operationId) async =>
      <String, Object?>{
        'operationId': operationId,
        'state': 'completed',
        'completedItems': 1,
        'totalItems': 1,
        'failedItems': 0,
      };

  @override
  Future<StudioWorkspaceContent> refreshContent() => openContent();

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => snapshot;
}

final class _MotionContextClient
    implements
        StudioHostClient,
        StudioHostContentClient,
        StudioHostContextBuilderClient {
  _MotionContextClient(this.content);

  final StudioWorkspaceContent content;
  var buildCalls = 0;
  ContextBuildRequest? lastRequest;

  @override
  Future<void> close() async {}

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => content.snapshot;

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => content.snapshot;

  @override
  Future<StudioWorkspaceContent> openContent() async => content;

  @override
  Future<StudioWorkspaceContent> refreshContent() async => content;

  @override
  Future<ContextBuilderDescription> describeContextBuilder() async =>
      ContextBuilderDescription(
        contentSetDigest: content.identity.contentSetDigest,
        supportedCategories: ContextCategory.values.toSet(),
        maximumBudgets: _contextBudgets(),
      );

  @override
  Future<ContextBuildResult> buildContext(ContextBuildRequest request) async {
    buildCalls += 1;
    lastRequest = request;
    return ContextBuildResult(
      bundle: ExperienceContextBundle(
        contentSetDigest: content.identity.contentSetDigest,
        selection: request.selection,
        inclusion: request.inclusion,
        requestedBudgets: request.budgets,
        effectiveBudgets: request.budgets,
        items: const <ContextItem>[],
        usage: <ContextCategory, ContextUsage>{
          for (final category in ContextCategory.values)
            category: ContextUsage(items: 0, bytes: 0),
        },
        omissions: <ContextOmission>[
          for (final category in ContextCategory.values)
            ContextOmission(
              category: category,
              subject: category.name,
              reason: ContextOmissionReason.unavailable,
            ),
        ],
      ),
    );
  }
}

StudioWorkspaceContent _motionContextContent() {
  final base = _workspaceSnapshot();
  final bundle = _spatialExperienceBundle(base.catalog);
  final motion = _motionForBundle(base.catalog, bundle);
  final snapshot = WorkspaceSnapshot(
    revision: base.revision,
    catalog: base.catalog,
    variantManifest: base.variantManifest,
    effectiveKitManifest: EffectiveKitManifest(
      resolvedPlanDigest: base.effectiveKitManifest.resolvedPlanDigest,
      modules: base.effectiveKitManifest.modules,
      commands: base.effectiveKitManifest.commands,
      rpcMethods: <String>[
        ...base.effectiveKitManifest.rpcMethods,
        'context.describe',
        'context.build',
      ],
      studioContributions: <String>[
        ...base.effectiveKitManifest.studioContributions,
        'studio.motion',
        'studio.context',
      ],
      generatedAt: base.effectiveKitManifest.generatedAt,
    ),
    providers: base.providers,
    visualProjections: base.visualProjections,
    generatedAt: base.generatedAt,
  );
  final identity = ExperienceContentSetIdentity(
    revision: 1,
    catalogDigest: snapshot.catalog.digest,
    workspaceSnapshotDigest: snapshot.digest,
    workspaceContentDigest: snapshot.workspaceContentDigest,
    experienceTopologyBundleDigest: bundle.digest,
    motionManifestDigest: motion.digest,
  );
  return StudioWorkspaceContent(
    snapshot: snapshot,
    experienceBundle: bundle,
    motion: motion,
    identity: identity,
  );
}

MotionManifest _motionForBundle(
  CatalogManifest catalog,
  ExperienceTopologyBundle bundle,
) => MotionManifest(
  catalogDigest: catalog.digest,
  topologyDigest: bundle.topology.digest,
  sequences: <MotionSequenceManifest>[
    MotionSequenceManifest(
      id: 'sample-motion',
      projectionId: ExperienceProjectionId('sample-journey-spatial'),
      title: 'Sample motion',
      staticSummary: 'Descobrir, compreender e então revisar.',
      steps: <MotionTransitionStep>[
        MotionTransitionStep(
          id: 'discover-to-understand',
          transitionId: TransitionId('discover-understand'),
          fromNodeId: NodeInstanceId('node-discover'),
          toNodeId: NodeInstanceId('node-understand'),
          startMs: 0,
          fullDurationMs: 420,
          reducedDurationMs: 80,
          easing: MotionEasing.easeInOut,
          observations: <MotionObservation>[
            MotionObservation(
              id: 'understand-visible',
              label: 'Compreender fica visível',
              atFraction: 1,
              kind: MotionObservationKind.stateVisible,
            ),
          ],
        ),
      ],
    ),
  ],
)..validateAgainst(catalog: catalog, topology: bundle.topology);

ContextBudgets _contextBudgets() => ContextBudgets(
  categories: <ContextCategory, ContextCategoryBudget>{
    for (final category in ContextCategory.values)
      category: ContextCategoryBudget(maxItems: 16, maxBytes: 64 * 1024),
  },
);

final class _NoTopologyClient
    implements StudioHostClient, StudioHostContentClient {
  _NoTopologyClient(this.snapshot);

  final WorkspaceSnapshot snapshot;
  int openCalls = 0;

  @override
  Future<void> close() async {}

  @override
  Future<StudioWorkspaceContent> openContent() async {
    openCalls += 1;
    return _canonicalContent(snapshot);
  }

  @override
  Future<StudioWorkspaceContent> refreshContent() => openContent();

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => snapshot;

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => snapshot;
}

StudioWorkspaceContent _canonicalContent(
  WorkspaceSnapshot snapshot, {
  ExperienceTopologyBundle? experienceBundle,
}) => StudioWorkspaceContent(
  snapshot: snapshot,
  experienceBundle: experienceBundle,
  identity: ExperienceContentSetIdentity(
    revision: snapshot.revision,
    catalogDigest: snapshot.catalog.digest,
    workspaceSnapshotDigest: snapshot.digest,
    workspaceContentDigest: snapshot.workspaceContentDigest,
    experienceTopologyBundleDigest: experienceBundle?.digest,
  ),
);

final class _ResourceClient implements StudioHostResourceClient {
  _ResourceClient(this.lease);

  final Future<StudioResourceLease> lease;
  int openCalls = 0;

  @override
  Future<StudioResourceLease> openVisualArtifact(ResourceHandle handle) {
    openCalls += 1;
    return lease;
  }
}
