import 'dart:async';
import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/catalog/sample_catalog.dart';
import 'package:studio/src/controllers/studio_workspace_controller.dart';
import 'package:studio/src/host/studio_experience_transport.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/model/workspace_state.dart';
import 'package:test/test.dart';

void main() {
  test('decodes one atomic generation including Lab and Motion', () {
    final fixture = _fixture();
    final fenced = StudioExperienceContentOpen.fromRpc(
      description: fixture.description,
      openResponse: fixture.opened.toJson(),
      hostOrigin: fixture.hostOrigin,
      nowUtc: DateTime.utc(2026, 8, 14),
    );

    final content = fenced.decode(
      workspaceSnapshotBytes: fixture.snapshotBytes,
      experienceTopologyBundleBytes: fixture.topologyBytes,
      scenarioFacetManifestBytes: fixture.facetsBytes,
      scenarioLabManifestBytes: fixture.labBytes,
      motionManifestBytes: fixture.motionBytes,
    );

    expect(content.snapshot.digest, fixture.snapshot.digest);
    expect(
      content.snapshot.workspaceContentDigest,
      fixture.identity.workspaceContentDigest,
    );
    expect(content.experienceBundle?.digest, fixture.bundle.digest);
    expect(content.scenarioFacets?.digest, fixture.facets.digest);
    expect(content.scenarioLab?.digest, fixture.lab?.digest);
    expect(content.motion?.digest, fixture.motion.digest);
    expect(content.identity, same(fenced.identity));
  });

  test('keeps Scenario Lab absence explicit inside a valid generation', () {
    final fixture = _fixture(includeLab: false);
    final fenced = StudioExperienceContentOpen.fromRpc(
      description: fixture.description,
      openResponse: fixture.opened.toJson(),
      hostOrigin: fixture.hostOrigin,
      nowUtc: DateTime.utc(2026, 8, 14),
    );

    final content = fenced.decode(
      workspaceSnapshotBytes: fixture.snapshotBytes,
      experienceTopologyBundleBytes: fixture.topologyBytes,
      scenarioFacetManifestBytes: fixture.facetsBytes,
      motionManifestBytes: fixture.motionBytes,
    );

    expect(content.scenarioLab, isNull);
    expect(content.identity.scenarioLabManifestDigest, isNull);
  });

  test('rejects generation fencing mismatch before decoding resources', () {
    final fixture = _fixture();
    final nextIdentity = ExperienceContentSetIdentity(
      revision: fixture.identity.revision + 1,
      catalogDigest: fixture.identity.catalogDigest,
      workspaceSnapshotDigest: fixture.identity.workspaceSnapshotDigest,
      workspaceContentDigest: fixture.identity.workspaceContentDigest,
      experienceTopologyBundleDigest:
          fixture.identity.experienceTopologyBundleDigest,
      scenarioFacetManifestDigest: fixture.identity.scenarioFacetManifestDigest,
      scenarioLabManifestDigest: fixture.identity.scenarioLabManifestDigest,
      motionManifestDigest: fixture.identity.motionManifestDigest,
    );
    final nextOpen = ExperienceContentSetOpenResult(
      identity: nextIdentity,
      workspaceSnapshot: fixture.opened.workspaceSnapshot,
      experienceTopologyBundle: fixture.opened.experienceTopologyBundle,
      scenarioFacetManifest: fixture.opened.scenarioFacetManifest,
      scenarioLabManifest: fixture.opened.scenarioLabManifest,
      motionManifest: fixture.opened.motionManifest,
    );

    expect(
      () => StudioExperienceContentOpen.fromRpc(
        description: fixture.description,
        openResponse: nextOpen.toJson(),
        hostOrigin: fixture.hostOrigin,
        nowUtc: DateTime.utc(2026, 8, 14),
      ),
      throwsFormatException,
    );
  });

  test('rejects wrong-origin handles and bytes that do not match a grant', () {
    final fixture = _fixture();
    final openJson = _copy(fixture.opened.toJson());
    final resources = _copy(openJson['resources']! as Map<String, Object?>);
    final lab = _copy(resources['scenarioLabManifest']! as Map<String, Object?>)
      ..['uri'] =
          'http://localhost:43124/resources/dddddddddddddddddddddddddddddddd';
    resources['scenarioLabManifest'] = lab;
    openJson['resources'] = resources;

    expect(
      () => StudioExperienceContentOpen.fromRpc(
        description: fixture.description,
        openResponse: openJson,
        hostOrigin: fixture.hostOrigin,
        nowUtc: DateTime.utc(2026, 8, 14),
      ),
      throwsFormatException,
    );

    final fenced = StudioExperienceContentOpen.fromRpc(
      description: fixture.description,
      openResponse: fixture.opened.toJson(),
      hostOrigin: fixture.hostOrigin,
      nowUtc: DateTime.utc(2026, 8, 14),
    );
    expect(
      () => fenced.decode(
        workspaceSnapshotBytes: fixture.snapshotBytes,
        experienceTopologyBundleBytes: fixture.topologyBytes,
        scenarioFacetManifestBytes: fixture.facetsBytes,
        scenarioLabManifestBytes: <int>[...fixture.labBytes!, 0],
        motionManifestBytes: fixture.motionBytes,
      ),
      throwsFormatException,
    );
  });

  test('rejects a workspace semantic digest that does not match the bytes', () {
    final fixture = _fixture();
    final tamperedIdentity = ExperienceContentSetIdentity(
      revision: fixture.identity.revision,
      catalogDigest: fixture.identity.catalogDigest,
      workspaceSnapshotDigest: fixture.identity.workspaceSnapshotDigest,
      workspaceContentDigest: Digest.semantic('tampered-workspace-content'),
      experienceTopologyBundleDigest:
          fixture.identity.experienceTopologyBundleDigest,
      scenarioFacetManifestDigest: fixture.identity.scenarioFacetManifestDigest,
      scenarioLabManifestDigest: fixture.identity.scenarioLabManifestDigest,
      motionManifestDigest: fixture.identity.motionManifestDigest,
    );
    final fenced = StudioExperienceContentOpen.fromRpc(
      description: ExperienceContentSetDescription(identity: tamperedIdentity),
      openResponse: ExperienceContentSetOpenResult(
        identity: tamperedIdentity,
        workspaceSnapshot: fixture.opened.workspaceSnapshot,
        experienceTopologyBundle: fixture.opened.experienceTopologyBundle,
        scenarioFacetManifest: fixture.opened.scenarioFacetManifest,
        scenarioLabManifest: fixture.opened.scenarioLabManifest,
        motionManifest: fixture.opened.motionManifest,
      ).toJson(),
      hostOrigin: fixture.hostOrigin,
      nowUtc: DateTime.utc(2026, 8, 14),
    );

    expect(
      () => StudioWorkspaceContent(
        snapshot: fixture.snapshot,
        experienceBundle: fixture.bundle,
        scenarioFacets: fixture.facets,
        scenarioLab: fixture.lab,
        motion: fixture.motion,
        identity: tamperedIdentity,
      ),
      throwsArgumentError,
    );

    expect(
      () => fenced.decode(
        workspaceSnapshotBytes: fixture.snapshotBytes,
        experienceTopologyBundleBytes: fixture.topologyBytes,
        scenarioFacetManifestBytes: fixture.facetsBytes,
        scenarioLabManifestBytes: fixture.labBytes,
        motionManifestBytes: fixture.motionBytes,
      ),
      throwsFormatException,
    );
  });

  test('controller publishes each complete generation atomically', () async {
    final firstFixture = _fixture(snapshotRevision: 3, contentRevision: 9);
    final secondFixture = _fixture(snapshotRevision: 4, contentRevision: 10);
    final first = _decode(firstFixture);
    final second = _decode(secondFixture);
    final client = _ContentClient(<StudioWorkspaceContent>[first, second]);
    final controller = StudioWorkspaceController(clientFactory: () => client);
    final published = <StudioWorkspaceState>[];
    final subscription = controller.changes.listen((state) {
      if (!state.isConnecting && state.snapshot != null) published.add(state);
    });

    await controller.connect();
    await controller.refreshWorkspace();

    expect(published, hasLength(2));
    expect(published.first.snapshot?.digest, first.snapshot.digest);
    expect(published.first.scenarioLab?.digest, first.scenarioLab?.digest);
    expect(published.first.motion?.digest, first.motion?.digest);
    expect(published.first.contentIdentity, same(first.identity));
    expect(published.last.snapshot?.digest, second.snapshot.digest);
    expect(published.last.scenarioLab?.digest, second.scenarioLab?.digest);
    expect(published.last.motion?.digest, second.motion?.digest);
    expect(published.last.contentIdentity, same(second.identity));
    expect(client.splitCalls, 0);

    await subscription.cancel();
    await controller.close();
  });
}

final class _ContentClient
    implements StudioHostClient, StudioHostContentClient {
  _ContentClient(this.contents);

  final List<StudioWorkspaceContent> contents;
  var _next = 0;
  var splitCalls = 0;

  @override
  Future<StudioWorkspaceContent> openContent() async => contents[_next++];

  @override
  Future<StudioWorkspaceContent> refreshContent() => openContent();

  @override
  Future<WorkspaceSnapshot> openWorkspace() async {
    splitCalls += 1;
    throw StateError('split workspace transport must not be used');
  }

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() => openWorkspace();

  @override
  Future<void> close() async {}
}

final class _ContentFixture {
  const _ContentFixture({
    required this.hostOrigin,
    required this.snapshot,
    required this.bundle,
    required this.facets,
    required this.lab,
    required this.motion,
    required this.identity,
    required this.description,
    required this.opened,
    required this.snapshotBytes,
    required this.topologyBytes,
    required this.facetsBytes,
    required this.labBytes,
    required this.motionBytes,
  });

  final Uri hostOrigin;
  final WorkspaceSnapshot snapshot;
  final ExperienceTopologyBundle bundle;
  final ScenarioFacetManifest facets;
  final ScenarioLabManifest? lab;
  final MotionManifest motion;
  final ExperienceContentSetIdentity identity;
  final ExperienceContentSetDescription description;
  final ExperienceContentSetOpenResult opened;
  final List<int> snapshotBytes;
  final List<int> topologyBytes;
  final List<int> facetsBytes;
  final List<int>? labBytes;
  final List<int> motionBytes;
}

_ContentFixture _fixture({
  bool includeLab = true,
  int snapshotRevision = 3,
  int contentRevision = 9,
}) {
  final hostOrigin = Uri.parse('http://127.0.0.1:43123');
  final catalog = _catalog();
  final snapshot = _snapshot(catalog, revision: snapshotRevision);
  final bundle = _bundle(catalog);
  final facets = _facets(catalog);
  final lab = includeLab ? _lab(catalog) : null;
  final motion = MotionManifest(
    catalogDigest: catalog.digest,
    topologyDigest: bundle.topology.digest,
    sequences: const <MotionSequenceManifest>[],
  )..validateAgainst(catalog: catalog, topology: bundle.topology);
  final snapshotBytes = _bytes(snapshot.toJson());
  final topologyBytes = _bytes(bundle.toJson());
  final facetsBytes = _bytes(facets.toJson());
  final labBytes = lab == null ? null : _bytes(lab.toJson());
  final motionBytes = _bytes(motion.toJson());
  final identity = ExperienceContentSetIdentity(
    revision: contentRevision,
    catalogDigest: catalog.digest,
    workspaceSnapshotDigest: snapshot.digest,
    workspaceContentDigest: snapshot.workspaceContentDigest,
    experienceTopologyBundleDigest: bundle.digest,
    scenarioFacetManifestDigest: facets.digest,
    scenarioLabManifestDigest: lab?.digest,
    motionManifestDigest: motion.digest,
  );
  final description = ExperienceContentSetDescription(identity: identity);
  final opened = ExperienceContentSetOpenResult(
    identity: identity,
    workspaceSnapshot: _resource(
      hostOrigin,
      'workspace-snapshot',
      snapshotBytes,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    experienceTopologyBundle: _resource(
      hostOrigin,
      'experience-topology-bundle',
      topologyBytes,
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    ),
    scenarioFacetManifest: _resource(
      hostOrigin,
      'scenario-facet-manifest',
      facetsBytes,
      'cccccccccccccccccccccccccccccccc',
    ),
    scenarioLabManifest: labBytes == null
        ? null
        : _resource(
            hostOrigin,
            'scenario-lab-manifest',
            labBytes,
            'dddddddddddddddddddddddddddddddd',
          ),
    motionManifest: _resource(
      hostOrigin,
      'motion-manifest',
      motionBytes,
      'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    ),
  );
  return _ContentFixture(
    hostOrigin: hostOrigin,
    snapshot: snapshot,
    bundle: bundle,
    facets: facets,
    lab: lab,
    motion: motion,
    identity: identity,
    description: description,
    opened: opened,
    snapshotBytes: snapshotBytes,
    topologyBytes: topologyBytes,
    facetsBytes: facetsBytes,
    labBytes: labBytes,
    motionBytes: motionBytes,
  );
}

StudioWorkspaceContent _decode(_ContentFixture fixture) {
  final fenced = StudioExperienceContentOpen.fromRpc(
    description: fixture.description,
    openResponse: fixture.opened.toJson(),
    hostOrigin: fixture.hostOrigin,
    nowUtc: DateTime.utc(2026, 8, 14),
  );
  return fenced.decode(
    workspaceSnapshotBytes: fixture.snapshotBytes,
    experienceTopologyBundleBytes: fixture.topologyBytes,
    scenarioFacetManifestBytes: fixture.facetsBytes,
    scenarioLabManifestBytes: fixture.labBytes,
    motionManifestBytes: fixture.motionBytes,
  );
}

CatalogManifest _catalog() {
  final source = sampleCatalogManifest();
  return CatalogManifest(
    distribution: source.distribution,
    layout: source.layout,
    workspace: source.workspace,
    applications: source.applications,
    journeys: source.journeys,
    scenarios: source.scenarios,
    transitions: source.transitions,
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('discover-web'),
        scenarioId: source.scenarios.first.id,
        targetId: 'sample-web',
        launchProfileId: 'sample-web',
      ),
    ],
  );
}

WorkspaceSnapshot _snapshot(CatalogManifest catalog, {required int revision}) =>
    WorkspaceSnapshot(
      revision: revision,
      catalog: catalog,
      variantManifest: VariantManifest(
        catalogDigest: catalog.digest,
        variants: const <Variant>[],
        sources: const <VariantDefinitionSource>[],
      ),
      effectiveKitManifest: EffectiveKitManifest(
        resolvedPlanDigest: Digest.semantic('studio-content-test-$revision'),
        modules: const <EffectiveModuleState>[],
        commands: const <String>[],
        rpcMethods: const <String>[],
        studioContributions: const <String>['studio.shell'],
        generatedAt: DateTime.utc(2026, 8, 14),
      ),
      providers: const <VisualEvidenceProviderState>[],
      visualProjections: const <VisualEvidenceProjection>[],
      generatedAt: DateTime.utc(2026, 8, 14),
    );

ExperienceTopologyBundle _bundle(CatalogManifest catalog) {
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: const <Board>[],
    projections: const <ExperienceProjection>[],
    nodes: const <NodeInstance>[],
    edges: const <EdgeInstance>[],
  );
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: const <ProjectionLayoutManifest>[],
  );
}

ScenarioFacetManifest _facets(CatalogManifest catalog) {
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

ScenarioLabManifest _lab(CatalogManifest catalog) {
  final scenarioId = catalog.scenarios.first.id;
  final bindingId = catalog.executionBindings.single.id;
  final scriptId = ScenarioScriptId('open-discover');
  return ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: const <CapabilityDescriptor>[],
    controls: const <ScenarioControlDefinition>[],
    operations: const <ScenarioLabOperationDefinition>[],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: scriptId,
        scenarioId: scenarioId,
        displayName: 'Open discover',
        timeoutMs: 10000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'open',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
            bindingId: bindingId,
          ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: const <AutomatedAcceptanceCriterion>[],
    requiredEvidence: const <RequiredEvidenceDefinition>[],
    comparisonBindings: const <ScenarioComparisonBinding>[],
    visualComparisonPolicies: const <VisualComparisonPolicy>[],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: const <HumanApprovalRequirement>[],
    supplementalArtifacts: const <SupplementalArtifactReference>[],
    plans: <ScenarioLabPlan>[
      ScenarioLabPlan(
        scenarioId: scenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[bindingId],
        controlIds: const <ScenarioControlId>[],
        operationIds: const <ScenarioLabOperationId>[],
        scriptIds: <ScenarioScriptId>[scriptId],
        automatedAcceptanceCriterionIds:
            const <AutomatedAcceptanceCriterionId>[],
        requiredEvidenceIds: const <RequiredEvidenceId>[],
        comparisonBindingIds: const <ScenarioComparisonBindingId>[],
        humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
        supplementalArtifactIds: const <SupplementalArtifactId>[],
      ),
    ],
  );
}

List<int> _bytes(Map<String, Object?> value) =>
    utf8.encode('${const JcsCanonicalizer().canonicalize(value)}\n');

ResourceHandle _resource(
  Uri hostOrigin,
  String purpose,
  List<int> bytes,
  String token,
) => ResourceHandle(
  uri: hostOrigin.replace(path: '/resources/$token'),
  digest: Digest.bytes(bytes),
  mediaType: 'application/json',
  size: bytes.length,
  purpose: purpose,
  expiresAt: DateTime.utc(2026, 8, 20),
);

Map<String, Object?> _copy(Map<String, Object?> source) => <String, Object?>{
  ...source,
};
