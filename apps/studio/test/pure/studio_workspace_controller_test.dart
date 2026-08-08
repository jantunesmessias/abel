import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/controllers/studio_workspace_controller.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:test/test.dart';

void main() {
  test('opens a workspace and accepts Host revision events', () async {
    final first = _snapshot(1);
    final second = _snapshot(2);
    final client = _FakeHostClient(<WorkspaceSnapshot>[first, second]);
    final controller = StudioWorkspaceController(clientFactory: () => client);

    await controller.connect();
    expect(controller.state.snapshot?.revision, 1);
    expect(controller.state.experienceBundle, isNull);
    expect(controller.state.connection.connected, isTrue);

    client.notifyWorkspaceChanged();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.snapshot?.revision, 2);
    expect(controller.state.connection.connected, isTrue);
    await controller.close();
  });

  test(
    'loads and refreshes an optional Experience topology atomically',
    () async {
      final firstSnapshot = _snapshot(1);
      final secondSnapshot = _snapshot(2);
      final firstBundle = _experienceBundle(firstSnapshot.catalog);
      final secondBundle = _experienceBundle(secondSnapshot.catalog, x: 144);
      final client = _FakeExperienceHostClient(
        <WorkspaceSnapshot>[firstSnapshot, secondSnapshot],
        <Object?>[firstBundle, secondBundle],
      );
      final controller = StudioWorkspaceController(clientFactory: () => client);

      await controller.connect();
      expect(controller.state.snapshot, same(firstSnapshot));
      expect(controller.state.experienceBundle, same(firstBundle));
      expect(client.requestedCatalogs.single, same(firstSnapshot.catalog));

      await controller.refreshWorkspace();

      expect(controller.state.snapshot, same(secondSnapshot));
      expect(controller.state.experienceBundle, same(secondBundle));
      expect(secondBundle.topology.digest, firstBundle.topology.digest);
      expect(secondBundle.digest, isNot(firstBundle.digest));
      expect(client.requestedCatalogs.last, same(secondSnapshot.catalog));
      await controller.close();
    },
  );

  test(
    'prefers one atomic content generation including Scenario facets',
    () async {
      final firstSnapshot = _snapshot(1);
      final secondSnapshot = _snapshot(2);
      final first = _content(firstSnapshot, contentRevision: 10);
      final second = _content(secondSnapshot, contentRevision: 11, x: 144);
      final client = _FakeContentHostClient(<Object?>[first, second]);
      final controller = StudioWorkspaceController(clientFactory: () => client);

      await controller.connect();
      expect(controller.state.snapshot, same(first.snapshot));
      expect(controller.state.experienceBundle, same(first.experienceBundle));
      expect(controller.state.scenarioFacets, same(first.scenarioFacets));
      expect(controller.state.contentIdentity, same(first.identity));
      expect(controller.state.scenarioLab, isNull);
      expect(controller.state.hasContentGeneration, isTrue);
      expect(client.splitOpenCalls, 0);

      await controller.refreshWorkspace();
      expect(controller.state.snapshot, same(second.snapshot));
      expect(controller.state.experienceBundle, same(second.experienceBundle));
      expect(controller.state.scenarioFacets, same(second.scenarioFacets));
      expect(controller.state.contentIdentity, same(second.identity));
      expect(client.splitOpenCalls, 0);
      await controller.close();
    },
  );

  test('reloads snapshot and Experience topology on Host events', () async {
    final snapshot = _snapshot(1);
    final firstBundle = _experienceBundle(snapshot.catalog);
    final secondBundle = _experienceBundle(snapshot.catalog, x: 96);
    final client = _FakeExperienceHostClient(
      <WorkspaceSnapshot>[snapshot, snapshot],
      <Object?>[firstBundle, secondBundle],
    );
    final controller = StudioWorkspaceController(clientFactory: () => client);

    await controller.connect();
    client.notifyWorkspaceChanged();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.snapshot, same(snapshot));
    expect(controller.state.experienceBundle, same(secondBundle));
    expect(controller.state.connection.connected, isTrue);
    await controller.close();
  });

  test('preserves the last atomic pair when Experience reload fails', () async {
    final firstSnapshot = _snapshot(1);
    final secondSnapshot = _snapshot(2);
    final firstBundle = _experienceBundle(firstSnapshot.catalog);
    final client = _FakeExperienceHostClient(
      <WorkspaceSnapshot>[firstSnapshot, secondSnapshot],
      <Object?>[
        firstBundle,
        const _ExperienceFailure('Experience resource digest mismatch'),
      ],
    );
    final controller = StudioWorkspaceController(
      clientFactory: () => client,
      reconnectDelay: const Duration(days: 1),
    );

    await controller.connect();
    client.notifyWorkspaceChanged();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.snapshot, same(firstSnapshot));
    expect(controller.state.experienceBundle, same(firstBundle));
    expect(controller.state.connection.connected, isFalse);
    expect(controller.state.connection.isStale, isTrue);
    expect(
      controller.state.connection.message,
      contains('Experience resource digest mismatch'),
    );
    await controller.close();
  });

  test('preserves stale state and reconnects with a new client', () async {
    final firstClient = _FakeHostClient(<WorkspaceSnapshot>[_snapshot(1)]);
    final secondClient = _FakeHostClient(<WorkspaceSnapshot>[_snapshot(2)]);
    final clients = <_FakeHostClient>[firstClient, secondClient];
    var nextClient = 0;
    final controller = StudioWorkspaceController(
      clientFactory: () => clients[nextClient++],
      reconnectDelay: Duration.zero,
    );

    await controller.connect();
    firstClient.disconnect(StateError('transport lost'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.state.snapshot?.revision, 2);
    expect(controller.state.connection.connected, isTrue);
    expect(firstClient.closed, isTrue);
    await controller.close();
  });

  test(
    'keeps an initial failure explicit and retries without user action',
    () async {
      final failing = _FakeHostClient(
        const <WorkspaceSnapshot>[],
        openError: StateError('Host unavailable'),
      );
      final recovered = _FakeHostClient(<WorkspaceSnapshot>[_snapshot(1)]);
      final clients = <_FakeHostClient>[failing, recovered];
      var nextClient = 0;
      final controller = StudioWorkspaceController(
        clientFactory: () => clients[nextClient++],
        reconnectDelay: Duration.zero,
      );

      await controller.connect();
      expect(controller.state.snapshot, isNull);
      expect(controller.state.failureMessage, contains('Host unavailable'));
      expect(nextClient, 1);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.state.snapshot?.revision, 1);
      expect(controller.state.failureMessage, isNull);
      expect(nextClient, 2);
      await controller.close();
    },
  );
}

final class _FakeHostClient
    implements
        StudioHostClient,
        StudioHostContentClient,
        StudioHostWorkspaceEvents {
  _FakeHostClient(this.snapshots, {this.openError});

  final List<WorkspaceSnapshot> snapshots;
  final Object? openError;
  final StreamController<void> _events = StreamController<void>.broadcast();
  var _nextSnapshot = 0;
  bool closed = false;

  @override
  Stream<void> get workspaceChanges => _events.stream;

  @override
  Future<StudioWorkspaceContent> openContent() async {
    if (openError case final error?) {
      return Future<StudioWorkspaceContent>.error(error);
    }
    return _snapshotContent(snapshots[_nextSnapshot++]);
  }

  @override
  Future<StudioWorkspaceContent> refreshContent() => openContent();

  @override
  Future<WorkspaceSnapshot> openWorkspace() async =>
      (await openContent()).snapshot;

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async =>
      (await refreshContent()).snapshot;

  void notifyWorkspaceChanged() => _events.add(null);

  void disconnect(Object error) => _events.addError(error);

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }
}

final class _FakeExperienceHostClient
    implements
        StudioHostClient,
        StudioHostContentClient,
        StudioHostWorkspaceEvents {
  _FakeExperienceHostClient(this.snapshots, this.experiences);

  final List<WorkspaceSnapshot> snapshots;
  final List<Object?> experiences;
  final List<CatalogManifest> requestedCatalogs = <CatalogManifest>[];
  final StreamController<void> _events = StreamController<void>.broadcast();
  var _nextSnapshot = 0;
  var _nextExperience = 0;

  @override
  Stream<void> get workspaceChanges => _events.stream;

  @override
  Future<StudioWorkspaceContent> openContent() async {
    final snapshot = snapshots[_nextSnapshot++];
    requestedCatalogs.add(snapshot.catalog);
    final result = experiences[_nextExperience++];
    if (result case final _ExperienceFailure failure) {
      throw StateError(failure.message);
    }
    return _snapshotContent(
      snapshot,
      experienceBundle: result as ExperienceTopologyBundle?,
    );
  }

  @override
  Future<StudioWorkspaceContent> refreshContent() => openContent();

  @override
  Future<WorkspaceSnapshot> openWorkspace() async =>
      (await openContent()).snapshot;

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async =>
      (await refreshContent()).snapshot;

  void notifyWorkspaceChanged() => _events.add(null);

  @override
  Future<void> close() => _events.close();
}

final class _FakeContentHostClient
    implements
        StudioHostClient,
        StudioHostContentClient,
        StudioHostWorkspaceEvents {
  _FakeContentHostClient(this.contents);

  final List<Object?> contents;
  final StreamController<void> _events = StreamController<void>.broadcast();
  var _nextContent = 0;
  var splitOpenCalls = 0;

  @override
  Stream<void> get workspaceChanges => _events.stream;

  @override
  Future<StudioWorkspaceContent> openContent() => _next();

  @override
  Future<StudioWorkspaceContent> refreshContent() => _next();

  Future<StudioWorkspaceContent> _next() async {
    final value = contents[_nextContent++];
    if (value case final _ExperienceFailure failure) {
      throw StateError(failure.message);
    }
    return value! as StudioWorkspaceContent;
  }

  @override
  Future<WorkspaceSnapshot> openWorkspace() async {
    splitOpenCalls += 1;
    throw StateError('split workspace transport must not be called');
  }

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() => openWorkspace();

  void notifyWorkspaceChanged() => _events.add(null);

  @override
  Future<void> close() => _events.close();
}

final class _ExperienceFailure {
  const _ExperienceFailure(this.message);

  final String message;
}

WorkspaceSnapshot _snapshot(int revision) {
  final catalog = sampleCatalogManifest();
  return WorkspaceSnapshot(
    revision: revision,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: const <Variant>[],
      sources: const <VariantDefinitionSource>[],
    ),
    effectiveKitManifest: EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic(<String, Object?>{
        'revision': revision,
      }),
      modules: const <EffectiveModuleState>[],
      commands: const <String>[],
      rpcMethods: const <String>[],
      studioContributions: const <String>['studio.shell'],
      generatedAt: DateTime.utc(2026, 8, 10),
    ),
    providers: const <VisualEvidenceProviderState>[],
    visualProjections: const <VisualEvidenceProjection>[],
    generatedAt: DateTime.utc(2026, 8, 10),
  );
}

ExperienceTopologyBundle _experienceBundle(
  CatalogManifest catalog, {
  double x = 0,
}) {
  final journey = catalog.journeys.single;
  final projectionId = ExperienceProjectionId('sample-journey');
  final firstNodeId = NodeInstanceId('node-discover');
  final secondNodeId = NodeInstanceId('node-understand');
  final edgeId = EdgeInstanceId('edge-discover-understand');
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: BoardId('sample-board'),
        applicationId: journey.applicationId,
        title: 'Sample board',
        projectionIds: <ExperienceProjectionId>[projectionId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: projectionId,
        boardId: BoardId('sample-board'),
        applicationId: journey.applicationId,
        title: 'Sample journey projection',
        kind: ProjectionKind.journey,
        journeyId: journey.id,
        nodeInstanceIds: <NodeInstanceId>[firstNodeId, secondNodeId],
        edgeInstanceIds: <EdgeInstanceId>[edgeId],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: firstNodeId,
        projectionId: projectionId,
        scenarioId: journey.scenarioIds.first,
      ),
      NodeInstance(
        id: secondNodeId,
        projectionId: projectionId,
        scenarioId: journey.scenarioIds[1],
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: edgeId,
        projectionId: projectionId,
        transitionId: catalog.transitions.first.id,
        fromNodeId: firstNodeId,
        toNodeId: secondNodeId,
      ),
    ],
  );
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: <ProjectionLayoutManifest>[
      ProjectionLayoutManifest(
        topologyDigest: topology.digest,
        projectionId: projectionId,
        nodeFrames: <ProjectionNodeFrame>[
          ProjectionNodeFrame(
            nodeInstanceId: firstNodeId,
            x: x,
            y: 0,
            width: 200,
            height: 120,
          ),
          ProjectionNodeFrame(
            nodeInstanceId: secondNodeId,
            x: 320,
            y: 180,
            width: 200,
            height: 120,
          ),
        ],
        groups: const <ProjectionGroup>[],
        lanes: const <ProjectionLane>[],
        annotations: const <ProjectionAnnotation>[],
        camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
      ),
    ],
  );
}

StudioWorkspaceContent _content(
  WorkspaceSnapshot snapshot, {
  required int contentRevision,
  double x = 0,
}) {
  final bundle = _experienceBundle(snapshot.catalog, x: x);
  final facets = _scenarioFacets(snapshot.catalog);
  final identity = ExperienceContentSetIdentity(
    revision: contentRevision,
    catalogDigest: snapshot.catalog.digest,
    workspaceSnapshotDigest: snapshot.digest,
    workspaceContentDigest: snapshot.workspaceContentDigest,
    experienceTopologyBundleDigest: bundle.digest,
    scenarioFacetManifestDigest: facets.digest,
  );
  return StudioWorkspaceContent(
    snapshot: snapshot,
    experienceBundle: bundle,
    scenarioFacets: facets,
    identity: identity,
  );
}

StudioWorkspaceContent _snapshotContent(
  WorkspaceSnapshot snapshot, {
  ExperienceTopologyBundle? experienceBundle,
}) {
  final identity = ExperienceContentSetIdentity(
    revision: snapshot.revision,
    catalogDigest: snapshot.catalog.digest,
    workspaceSnapshotDigest: snapshot.digest,
    workspaceContentDigest: snapshot.workspaceContentDigest,
    experienceTopologyBundleDigest: experienceBundle?.digest,
  );
  return StudioWorkspaceContent(
    snapshot: snapshot,
    experienceBundle: experienceBundle,
    identity: identity,
  );
}

ScenarioFacetManifest _scenarioFacets(CatalogManifest catalog) {
  final applicationId = catalog.applications.single.id;
  final kindId = ScenarioKindId('screen');
  final surfaceId = ExperienceSurfaceId('primary');
  final stateId = ScenarioStateId('ready');
  final ownerId = OwnershipAreaId('delivery');
  final tagId = ScenarioTagId('core');
  final componentId = ExperienceComponentId('shell');
  final fixtureId = ScenarioFixtureId('synthetic');
  final formFactorId = FormFactorId('responsive');
  final frameId = PresentationFrameId('browser');
  return ScenarioFacetManifest(
    catalog: catalog,
    scenarioKinds: <ScenarioKindDefinition>[
      ScenarioKindDefinition(id: kindId, displayName: 'Screen'),
    ],
    surfaces: <ExperienceSurfaceDefinition>[
      ExperienceSurfaceDefinition(
        id: surfaceId,
        applicationId: applicationId,
        displayName: 'Primary',
      ),
    ],
    states: <ScenarioStateDefinition>[
      ScenarioStateDefinition(
        id: stateId,
        surfaceId: surfaceId,
        displayName: 'Ready',
      ),
    ],
    ownershipAreas: <OwnershipAreaDefinition>[
      OwnershipAreaDefinition(id: ownerId, displayName: 'Delivery'),
    ],
    tags: <ScenarioTagDefinition>[
      ScenarioTagDefinition(id: tagId, displayName: 'Core'),
    ],
    components: <ExperienceComponentDefinition>[
      ExperienceComponentDefinition(
        id: componentId,
        applicationId: applicationId,
        displayName: 'Shell',
      ),
    ],
    fixtures: <ScenarioFixtureDefinition>[
      ScenarioFixtureDefinition(
        id: fixtureId,
        applicationId: applicationId,
        displayName: 'Synthetic',
      ),
    ],
    formFactors: <FormFactorDefinition>[
      FormFactorDefinition(id: formFactorId, displayName: 'Responsive'),
    ],
    presentationFrames: <PresentationFrameDefinition>[
      PresentationFrameDefinition(
        id: frameId,
        displayName: 'Browser',
        kind: PresentationFrameKind.browser,
        formFactorId: formFactorId,
      ),
    ],
    scenarioFacets: <ScenarioFacet>[
      for (final scenario in catalog.scenarios)
        ScenarioFacet(
          scenarioId: scenario.id,
          lifecycle: ScenarioLifecycle.current,
          scenarioKindId: kindId,
          surfaceId: surfaceId,
          stateId: stateId,
          ownershipAreaId: ownerId,
          tagIds: <ScenarioTagId>[tagId],
          componentIds: <ExperienceComponentId>[componentId],
          fixtureId: fixtureId,
          renderSource: PreviewDescriptorRenderSource(
            previewId: AutoPreviewId(scenario.id.value),
          ),
          presentationFrameIds: <PresentationFrameId>[frameId],
          preferredPresentationFrameId: frameId,
        ),
    ],
  );
}
