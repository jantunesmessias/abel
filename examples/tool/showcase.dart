import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

Future<void> main(List<String> arguments) async {
  final options = _ShowcaseOptions.parse(arguments);
  final repository = _repositoryRoot();
  final flutterWorkspace = Directory(
    '${repository.path}/examples/sample_flutter',
  );
  final studioAssets = Directory('${repository.path}/apps/studio/build/jaspr');
  final targetAssets = Directory('${flutterWorkspace.path}/build/web');
  _ensureLocalConfiguration(flutterWorkspace);
  _verifyReferenceTopology(flutterWorkspace);
  _verifyReferenceTaxonomy(flutterWorkspace);
  _verifyReferenceScenarioLab(flutterWorkspace);
  _verifyReferenceQualityDecisionConfiguration(flutterWorkspace);
  _verifyReferenceAuthoringConfiguration(flutterWorkspace);
  _verifyReferenceMotionContext(flutterWorkspace);

  if (options.buildStudio ||
      !File('${studioAssets.path}/index.html').existsSync()) {
    await _runChecked(
      'jaspr',
      const <String>['build'],
      workingDirectory: '${repository.path}/apps/studio',
      label: 'Building the Jaspr Studio',
    );
  }

  if (options.buildTarget ||
      (!options.checkOnly &&
          _targetBuildRequired(repository, flutterWorkspace, targetAssets))) {
    await _runChecked(
      'flutter',
      const <String>[
        'build',
        'web',
        '--release',
        '--target=tool/target_main.dart',
        '--dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181',
        '--dart-define=TARGET_CONTROLLER_ORIGIN=http://127.0.0.1:7368',
      ],
      workingDirectory: flutterWorkspace.path,
      label: 'Building the precompiled Flutter Target',
    );
  } else if (options.checkOnly &&
      _targetBuildRequired(repository, flutterWorkspace, targetAssets)) {
    stdout.writeln(
      'The precompiled Flutter Target is missing or stale. '
      'Run without --check, or pass --build-target, before starting it.',
    );
  }

  final compilation = await _runJson(
    Platform.resolvedExecutable,
    <String>[
      'run',
      'apps/workspace_cli/bin/workspace.dart',
      '--json',
      'compile',
      '--config',
      'examples/sample_flutter/workspace.yaml',
    ],
    workingDirectory: repository.path,
    label: 'Compiling the showcase catalog and Gateway presets',
  );
  _printGatewayPlans(compilation);
  if (options.checkOnly) {
    stdout.writeln(
      'Showcase configuration is valid. No services were started.',
    );
    return;
  }

  for (final port in const <int>[8181, 7367, 7368, 8080]) {
    await _requireAvailablePort(port);
  }

  final processes = <Process>[];
  final stopping = Completer<void>();
  Future<void> stopProcesses() async {
    final current = processes.reversed.toList(growable: false);
    processes.clear();
    for (final process in current) {
      process.kill(ProcessSignal.sigint);
    }
    for (final process in current) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        process.kill(ProcessSignal.sigterm);
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
        }
      }
    }
  }

  Future<void> shutdown() async {
    if (!stopping.isCompleted) stopping.complete();
    await stopProcesses();
  }

  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown())),
    ProcessSignal.sigterm.watch().listen((_) => unawaited(shutdown())),
  ];
  try {
    var generation = 0;
    while (!stopping.isCompleted) {
      if (generation > 0) {
        await _waitForAvailablePorts(const <int>[8181, 7367, 7368, 8080]);
      }
      final generationEnded = Completer<void>();
      final failure = Completer<String>();
      try {
        final api = await Process.start(
          Platform.resolvedExecutable,
          const <String>[
            'run',
            'examples/sample_api/bin/server.dart',
            '--port',
            '8181',
          ],
          workingDirectory: repository.path,
        );
        processes.add(api);
        _forwardErrors(api, 'sample-api');
        await _watchForReadiness(api, label: 'sample-api');
        await _waitForHealth(Uri.parse('http://127.0.0.1:8181/health'));

        final workspaceArguments = <String>[
          'run',
          'apps/workspace_cli/bin/workspace.dart',
          '--json',
          'dev',
          '--config',
          'examples/sample_flutter/workspace.yaml',
          '--host-port',
          '7367',
          '--studio-port',
          '7368',
          '--studio-assets',
          studioAssets.path,
          if (options.noOpen || generation > 0) '--no-open',
        ];
        final workspace = await Process.start(
          Platform.resolvedExecutable,
          workspaceArguments,
          workingDirectory: repository.path,
        );
        processes.add(workspace);
        _forwardErrors(workspace, 'workspace');
        final ready = await _watchForReadiness(workspace, label: 'workspace');
        final result = ready['result']! as Map<String, Object?>;

        stdout.writeln();
        stdout.writeln(
          generation == 0
              ? 'Abel complete showcase is ready:'
              : 'Abel complete showcase recovered (generation ${generation + 1}):',
        );
        stdout.writeln('  Studio: ${result['studioOrigin']}');
        stdout.writeln('  Host:   ${result['hostOrigin']}');
        stdout.writeln('  API:    http://127.0.0.1:8181');
        stdout.writeln(
          '  Target: http://127.0.0.1:8080 '
          '(prebuilt release assets, started from Studio)',
        );
        stdout.writeln();
        stdout.writeln(
          'All packaged modules are enabled by profile full-local.',
        );
        stdout.writeln(
          'A watchdog will restart the local stack after a process exit or '
          'three failed health probes.',
        );
        stdout.writeln(
          'Press Ctrl+C to stop the API, Host, Studio and managed targets.',
        );

        void watchExit(Process process, String label) {
          unawaited(
            process.exitCode.then((code) {
              if (!stopping.isCompleted && !failure.isCompleted) {
                failure.complete('$label exited unexpectedly with code $code');
              }
            }),
          );
        }

        watchExit(api, 'sample-api');
        watchExit(workspace, 'workspace');
        unawaited(
          _watchHealth(<Uri>[
            Uri(scheme: 'http', host: '127.0.0.1', port: 8181, path: '/health'),
            Uri(scheme: 'http', host: '127.0.0.1', port: 7367, path: '/health'),
            Uri(scheme: 'http', host: '127.0.0.1', port: 7368, path: '/health'),
          ], generationEnded.future).then((message) {
            if (message != null &&
                !stopping.isCompleted &&
                !failure.isCompleted) {
              failure.complete(message);
            }
          }),
        );
        await Future.any<void>(<Future<void>>[
          stopping.future,
          failure.future.then((message) {
            stderr.writeln('[showcase-watchdog] $message; restarting stack.');
          }),
        ]);
      } on Object catch (error, stackTrace) {
        if (!stopping.isCompleted) {
          stderr.writeln('[showcase-watchdog] startup failed: $error');
          stderr.writeln(stackTrace);
        }
      } finally {
        if (!generationEnded.isCompleted) generationEnded.complete();
        await stopProcesses();
      }
      if (!stopping.isCompleted) {
        generation += 1;
        final delay = Duration(seconds: generation > 5 ? 5 : generation);
        await Future.any<void>(<Future<void>>[
          stopping.future,
          Future<void>.delayed(delay),
        ]);
      }
    }
  } finally {
    await shutdown();
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
  }
}

void _verifyReferenceTopology(Directory flutterWorkspace) {
  final loaded = const WorkspaceCatalogLoader().load(
    startPath: flutterWorkspace.path,
    explicitConfigPath: '${flutterWorkspace.path}/workspace.yaml',
  );
  final catalog = const CatalogCompiler().compile(
    loaded.documents,
    layout: loaded.layout,
  );
  const compiler = ExperienceTopologyCompiler();
  _requireReferenceFact(
    compiler.hasAuthoring(loaded.documents),
    'Delivery Lab must contain public topology authoring documents',
  );
  final compilation = compiler.compile(loaded.documents, catalog: catalog);
  final topology = compilation.topology;

  _requireReferenceFact(topology.boards.length == 1, 'expected 1 Board');
  _requireReferenceFact(
    topology.projections.length == 2,
    'expected 2 Projections',
  );
  _requireReferenceFact(
    topology.nodes.length == 10,
    'expected 10 NodeInstances',
  );
  _requireReferenceFact(topology.edges.length == 5, 'expected 5 EdgeInstances');
  _requireReferenceFact(compilation.layouts.length == 2, 'expected 2 layouts');

  final journey = topology.projections.singleWhere(
    (projection) => projection.id.value == 'delivery-journey',
  );
  final inventory = topology.projections.singleWhere(
    (projection) => projection.id.value == 'delivery-inventory',
  );
  _requireReferenceFact(
    journey.journeyId?.value == 'operate-delivery-workspace',
    'Journey Projection must bind operate-delivery-workspace explicitly',
  );
  _requireReferenceFact(
    inventory.journeyId == null,
    'Inventory Projection must remain independent from a Journey lens',
  );

  final journeyNodes = topology.nodes
      .where((node) => node.projectionId == journey.id)
      .toList(growable: false);
  final inventoryNodes = topology.nodes
      .where((node) => node.projectionId == inventory.id)
      .toList(growable: false);
  final journeyScenarios = journeyNodes
      .map((node) => node.scenarioId.value)
      .toSet();
  final inventoryScenarios = inventoryNodes
      .map((node) => node.scenarioId.value)
      .toSet();
  _requireReferenceFact(
    journeyScenarios.length == 5 &&
        journeyScenarios.containsAll(inventoryScenarios) &&
        inventoryScenarios.containsAll(journeyScenarios),
    'both Projections must reuse the same 5 Scenarios',
  );
  _requireReferenceFact(
    journeyNodes
        .map((node) => node.id.value)
        .toSet()
        .intersection(inventoryNodes.map((node) => node.id.value).toSet())
        .isEmpty,
    'each Projection must own distinct NodeInstances',
  );

  final journeyTransitions = topology.edges
      .where((edge) => edge.projectionId == journey.id)
      .map((edge) => edge.transitionId.value)
      .toSet();
  _requireReferenceFact(
    journeyTransitions.containsAll(const <String>{
          'loading-to-ready',
          'ready-to-failed',
          'ready-to-gateway',
          'ready-to-toggle',
          'toggle-to-gateway',
        }) &&
        journeyTransitions.length == 5,
    'Journey Projection must instantiate all 5 Transitions',
  );

  for (final layout in compilation.layouts) {
    _requireReferenceFact(
      layout.nodeFrames.length == 5 &&
          layout.groups.isNotEmpty &&
          layout.lanes.isNotEmpty &&
          layout.annotations.isNotEmpty,
      '${layout.projectionId} must have a curated spatial layout',
    );
  }
  final journeyLayout = compilation.layouts.singleWhere(
    (layout) => layout.projectionId == journey.id,
  );
  final scenarioByNode = <String, String>{
    for (final node in journeyNodes) node.id.value: node.scenarioId.value,
  };
  final yByScenario = <String, double>{
    for (final frame in journeyLayout.nodeFrames)
      scenarioByNode[frame.nodeInstanceId.value]!: frame.y,
  };
  _requireReferenceFact(
    yByScenario['toggle-delivery-task']! < yByScenario['dashboard-ready']! &&
        yByScenario['inspect-gateway-traffic'] ==
            yByScenario['dashboard-ready'],
    'Journey layout must render the task branch above its direct merge path',
  );

  stdout.writeln(
    'Reference topology is valid: 1 Board, 2 Projections, '
    '10 NodeInstances, 5 EdgeInstances and 2 curated layouts.',
  );
}

void _verifyReferenceTaxonomy(Directory flutterWorkspace) {
  final loaded = const WorkspaceCatalogLoader().load(
    startPath: flutterWorkspace.path,
    explicitConfigPath: '${flutterWorkspace.path}/workspace.yaml',
  );
  const catalogCompiler = CatalogCompiler();
  final catalog = catalogCompiler.compile(
    loaded.documents,
    layout: loaded.layout,
  );
  final v1OnlyCatalog = catalogCompiler.compile(
    loaded.documents.where((document) => document.schemaVersion == 1),
    layout: loaded.layout,
  );
  _requireTaxonomyFact(
    catalog.digest == v1OnlyCatalog.digest &&
        jsonEncode(catalog.toJson()) == jsonEncode(v1OnlyCatalog.toJson()),
    'taxonomy v2 must not alter CatalogManifest v1 bytes or digest',
  );

  const facetCompiler = ScenarioFacetCompiler();
  _requireTaxonomyFact(
    facetCompiler.hasAuthoring(loaded.documents),
    'Delivery Lab must contain public Scenario taxonomy authoring documents',
  );
  final facets = facetCompiler.compile(loaded.documents, catalog: catalog);
  final index = ScenarioInventoryIndex(catalog: catalog, facets: facets);
  const expectedScenarioIds = <String>{
    'dashboard-empty',
    'dashboard-failed',
    'dashboard-loading',
    'dashboard-ready',
    'dashboard-stale',
    'dashboard-unavailable',
    'inspect-gateway-traffic',
    'toggle-delivery-task',
  };
  final actualScenarioIds = facets.scenarioFacets
      .map((facet) => facet.scenarioId.value)
      .toSet();
  _requireTaxonomyFact(
    catalog.scenarios.length == 8 &&
        facets.scenarioFacets.length == 8 &&
        actualScenarioIds.length == expectedScenarioIds.length &&
        actualScenarioIds.containsAll(expectedScenarioIds),
    'ScenarioFacetManifest must cover exactly the 8 Catalog Scenarios',
  );
  _requireTaxonomyFact(
    facets.scenarioFacets.every(
      (facet) => facet.lifecycle == ScenarioLifecycle.current,
    ),
    'all synthetic Delivery Lab Scenarios must be current',
  );

  const expectedFixtureByScenario = <String, String>{
    'dashboard-empty': 'sample.dashboard.empty',
    'dashboard-failed': 'sample.dashboard.failure',
    'dashboard-loading': 'sample.dashboard.pending',
    'dashboard-ready': 'sample.dashboard.synthetic',
    'dashboard-stale': 'sample.dashboard.stale',
    'dashboard-unavailable': 'sample.dashboard.unavailable',
    'inspect-gateway-traffic': 'sample.dashboard.gateway-hybrid',
    'toggle-delivery-task': 'sample.dashboard.task-toggled',
  };
  const expectedPreviewByScenario = <String, String>{
    'dashboard-empty': 'sample.dashboard.empty',
    'dashboard-failed': 'sample.dashboard.failed',
    'dashboard-loading': 'sample.dashboard.loading',
    'dashboard-ready': 'sample.dashboard.ready',
    'dashboard-stale': 'sample.dashboard.stale',
    'dashboard-unavailable': 'sample.dashboard.unavailable',
    'inspect-gateway-traffic': 'sample.dashboard.gateway-traffic',
    'toggle-delivery-task': 'sample.dashboard.task-toggled',
  };
  for (final facet in facets.scenarioFacets) {
    final source = facet.renderSource;
    _requireTaxonomyFact(
      facet.fixtureId.value ==
          expectedFixtureByScenario[facet.scenarioId.value],
      '${facet.scenarioId} must retain its declared fixture identity',
    );
    _requireTaxonomyFact(
      source is PreviewDescriptorRenderSource &&
          source.previewId.value ==
              expectedPreviewByScenario[facet.scenarioId.value],
      '${facet.scenarioId} must retain its AutoPreview render source',
    );
  }

  void expectCount(ScenarioInventoryQuery query, int count, String label) {
    _requireTaxonomyFact(
      index.query(query).length == count,
      '$label Inventory query must return $count Scenarios',
    );
  }

  expectCount(
    ScenarioInventoryQuery(
      lifecycles: const <ScenarioLifecycle>[ScenarioLifecycle.current],
    ),
    8,
    'current lifecycle',
  );
  expectCount(
    ScenarioInventoryQuery(
      scenarioKindIds: <ScenarioKindId>[ScenarioKindId('observable-state')],
    ),
    6,
    'observable-state kind',
  );
  expectCount(
    ScenarioInventoryQuery(
      surfaceIds: <ExperienceSurfaceId>[
        ExperienceSurfaceId('delivery-dashboard'),
      ],
    ),
    7,
    'delivery-dashboard surface',
  );
  expectCount(
    ScenarioInventoryQuery(
      stateIds: <ScenarioStateId>[ScenarioStateId('gateway.hybrid-traffic')],
    ),
    1,
    'gateway traffic state',
  );
  expectCount(
    ScenarioInventoryQuery(
      ownershipAreaIds: <OwnershipAreaId>[OwnershipAreaId('delivery-platform')],
    ),
    1,
    'delivery-platform owner',
  );
  expectCount(
    ScenarioInventoryQuery(
      tagIds: <ScenarioTagId>[ScenarioTagId('resilience')],
    ),
    3,
    'resilience tag',
  );
  expectCount(
    ScenarioInventoryQuery(
      componentIds: <ExperienceComponentId>[
        ExperienceComponentId('showcase-gateway-traffic-panel'),
      ],
    ),
    1,
    'Gateway component',
  );
  expectCount(
    ScenarioInventoryQuery(
      fixtureIds: <ScenarioFixtureId>[
        ScenarioFixtureId('sample.dashboard.failure'),
      ],
    ),
    1,
    'failure fixture',
  );
  expectCount(
    ScenarioInventoryQuery(
      renderSourceKinds: const <ScenarioRenderSourceKind>[
        ScenarioRenderSourceKind.previewDescriptor,
      ],
    ),
    8,
    'PreviewDescriptor render source',
  );
  expectCount(
    ScenarioInventoryQuery(
      frameKinds: const <PresentationFrameKind>[PresentationFrameKind.browser],
      formFactorIds: <FormFactorId>[FormFactorId('desktop')],
    ),
    3,
    'desktop browser frame/form factor',
  );
  expectCount(
    ScenarioInventoryQuery(text: 'Hybrid Gateway traffic'),
    1,
    'typed taxonomy text',
  );

  const topologyCompiler = ExperienceTopologyCompiler();
  const topologyKinds = <AuthoringKind>{
    AuthoringKind.board,
    AuthoringKind.experienceProjection,
    AuthoringKind.nodeInstance,
    AuthoringKind.edgeInstance,
    AuthoringKind.projectionLayout,
  };
  final topologyOnly = topologyCompiler.compile(
    loaded.documents.where((document) => topologyKinds.contains(document.kind)),
    catalog: catalog,
  );
  final topologyWithFacets = topologyCompiler.compile(
    loaded.documents,
    catalog: catalog,
  );
  final topologyOnlyBundle = ExperienceTopologyBundle(
    catalog: catalog,
    topology: topologyOnly.topology,
    layouts: topologyOnly.layouts,
  );
  final topologyWithFacetsBundle = ExperienceTopologyBundle(
    catalog: catalog,
    topology: topologyWithFacets.topology,
    layouts: topologyWithFacets.layouts,
  );
  _requireTaxonomyFact(
    topologyOnlyBundle.digest == topologyWithFacetsBundle.digest &&
        jsonEncode(topologyOnlyBundle.toJson()) ==
            jsonEncode(topologyWithFacetsBundle.toJson()),
    'taxonomy v2 must not alter ExperienceTopologyBundle v1 bytes or digest',
  );

  stdout.writeln(
    'Reference taxonomy is valid: 8 fully faceted Scenarios, '
    'typed Inventory queries, and unchanged Catalog/Topology v1 wires.',
  );
}

void _verifyReferenceScenarioLab(Directory flutterWorkspace) {
  final loaded = const WorkspaceCatalogLoader().load(
    startPath: flutterWorkspace.path,
    explicitConfigPath: '${flutterWorkspace.path}/workspace.yaml',
  );
  const labKinds = <AuthoringKind>{
    AuthoringKind.appAdapterCapability,
    AuthoringKind.scenarioControl,
    AuthoringKind.scenarioLabOperation,
    AuthoringKind.scenarioScript,
    AuthoringKind.automatedAcceptanceCriterion,
    AuthoringKind.requiredEvidence,
    AuthoringKind.scenarioComparisonBinding,
    AuthoringKind.visualComparisonPolicy,
    AuthoringKind.semanticComparisonPolicy,
    AuthoringKind.humanApprovalRequirement,
    AuthoringKind.supplementalArtifact,
    AuthoringKind.scenarioLabPlan,
  };
  final documentsWithoutLab = loaded.documents
      .where((document) => !labKinds.contains(document.kind))
      .toList(growable: false);

  const catalogCompiler = CatalogCompiler();
  final catalogWithoutLab = catalogCompiler.compile(
    documentsWithoutLab,
    layout: loaded.layout,
  );
  final catalogWithLab = catalogCompiler.compile(
    loaded.documents,
    layout: loaded.layout,
  );

  const labCompiler = ScenarioLabCompiler();
  _requireLabFact(
    labCompiler.hasAuthoring(loaded.documents),
    'Delivery Lab must contain public Scenario Lab authoring documents',
  );
  final lab = labCompiler.compile(loaded.documents, catalog: catalogWithLab);
  _requireLabFact(
    lab.catalogDigest == catalogWithLab.digest &&
        ScenarioLabManifest.schemaVersion == 1,
    'ScenarioLabManifest must be catalog-bound on wire v1',
  );

  bool sameStrings(Iterable<String> actual, Set<String> expected) {
    final values = actual.toSet();
    return values.length == actual.length &&
        values.length == expected.length &&
        values.containsAll(expected);
  }

  _requireLabFact(
    lab.appAdapterCapabilities.length == 1 &&
        lab.appAdapterCapabilities.single.id ==
            'sample.dashboard.ready-control' &&
        lab.appAdapterCapabilities.single.version == 1 &&
        sameStrings(
          lab.appAdapterCapabilities.single.operations,
          const <String>{'read-enabled', 'write-enabled', 'reset-enabled'},
        ),
    'expected one closed read/write/reset AppAdapter capability',
  );

  final control = lab.controls.single;
  final controlDomain = control.domain;
  _requireLabFact(
    control.id.value == 'dashboard-ready-highlight-enabled' &&
        control.scenarioId.value == 'dashboard-ready' &&
        control.capability.id.value == 'sample.dashboard.ready-control' &&
        control.readOperationId.value == 'read-enabled' &&
        control.writeOperationId.value == 'write-enabled' &&
        control.resetOperationId?.value == 'reset-enabled' &&
        controlDomain is BooleanScenarioControlDomain &&
        !controlDomain.defaultValue.value,
    'dashboard-ready must expose one typed boolean control with reset',
  );

  _requireLabFact(
    lab.operations.length == 3 &&
        lab.operations.whereType<AssignControlOperationDefinition>().length ==
            1 &&
        lab.operations.whereType<ResetControlOperationDefinition>().length ==
            1 &&
        lab.operations.whereType<CollectEvidenceOperationDefinition>().length ==
            1 &&
        sameStrings(
          lab.operations.map((operation) => operation.id.value),
          const <String>{
            'enable-dashboard-ready-highlight',
            'collect-dashboard-ready-visual',
            'reset-dashboard-ready-highlight',
          },
        ),
    'expected exact assign/reset/collect-Evidence operations',
  );

  final script = lab.scripts.single;
  final firstStep = script.steps.first;
  final labBinding = catalogWithLab.executionBindings.singleWhere(
    (binding) => binding.id.value == 'dashboard-ready-lab-web',
  );
  _requireLabFact(
    script.id.value == 'exercise-dashboard-ready-lab' &&
        script.scenarioId.value == 'dashboard-ready' &&
        script.timeoutMs == 90000 &&
        script.timeoutOutcome == ScenarioScriptTimeoutOutcome.fail &&
        script.cancellationPolicy ==
            ScenarioScriptCancellationPolicy.afterCurrentStep &&
        script.steps.length == 4 &&
        firstStep is ExecutionBindingScenarioScriptStep &&
        firstStep.bindingId.value == 'dashboard-ready-lab-web' &&
        labBinding.targetId == 'sample-lab-web' &&
        labBinding.launchProfileId == 'sample-lab-web' &&
        labBinding.gatewayPresetId == 'showcase-offline' &&
        firstStep.timeoutMs == 45000 &&
        script.steps.every((step) => step.timeoutMs > 0) &&
        sameStrings(
          script.steps.whereType<OperationScenarioScriptStep>().map(
            (step) => step.operationId.value,
          ),
          const <String>{
            'enable-dashboard-ready-highlight',
            'collect-dashboard-ready-visual',
            'reset-dashboard-ready-highlight',
          },
        ),
    'script must begin with the exact Gateway-bound Catalog binding and use bounded policies',
  );

  _requireLabFact(
    lab.automatedAcceptanceCriteria.length == 3 &&
        sameStrings(
          lab.automatedAcceptanceCriteria.map(
            (criterion) => criterion.id.value,
          ),
          const <String>{
            'dashboard-ready-script-succeeds',
            'dashboard-ready-visual-accepted',
            'dashboard-ready-control-restored',
          },
        ) &&
        lab.automatedAcceptanceCriteria
                .whereType<ScriptSucceededAcceptanceCriterion>()
                .length ==
            1 &&
        lab.automatedAcceptanceCriteria
                .whereType<EvidenceAcceptedAcceptanceCriterion>()
                .length ==
            1 &&
        lab.automatedAcceptanceCriteria
                .whereType<ControlEqualsAcceptanceCriterion>()
                .length ==
            1,
    'automated acceptance must remain explicit and separate from approval',
  );

  final evidence = lab.requiredEvidence.single;
  _requireLabFact(
    evidence.id.value == 'dashboard-ready-visual' &&
        evidence.scenarioId.value == 'dashboard-ready' &&
        evidence.providerId.value == 'capture.app-adapter' &&
        evidence.fidelity == RuntimeFidelity.simulated &&
        evidence.variantId.value == 'phone.light.en-us' &&
        evidence.freshness == EvidenceFreshness.fresh &&
        sameStrings(
          evidence.allowedClassifications.map((value) => value.name),
          const <String>{'public', 'internal'},
        ) &&
        evidence.evidencePolicyId.value == 'static-v1' &&
        evidence.comparisonPolicy is VisualComparisonPolicyReference &&
        evidence.comparisonPolicy.policyId == 'dashboard-ready-pixel-v1',
    'expected one fresh live-adapter visual Evidence requirement for the synthetic variant',
  );

  final comparison = lab.comparisonBindings.single;
  final baseline = comparison.baseline;
  final candidate = comparison.candidate;
  final visualPolicy = lab.visualComparisonPolicies.single;
  _requireLabFact(
    comparison.id.value == 'dashboard-ready-baseline-candidate' &&
        comparison.scenarioId.value == 'dashboard-ready' &&
        comparison.requiredEvidenceId == evidence.id &&
        baseline is ArtifactComparisonInputReference &&
        baseline.artifactId.value == 'dashboard-ready-synthetic-baseline' &&
        candidate is RequiredEvidenceComparisonInputReference &&
        candidate.requiredEvidenceId == evidence.id &&
        lab.visualComparisonPolicies.length == 1 &&
        visualPolicy.id == 'dashboard-ready-pixel-v1' &&
        visualPolicy.maxChannelDelta == 8 &&
        visualPolicy.maxChangedPixelRatio == 0.005 &&
        lab.semanticComparisonPolicies.isEmpty,
    'visual comparison must bind the explicit baseline to the artifact collected by this run',
  );

  final approval = lab.humanApprovalRequirements.single;
  _requireLabFact(
    approval.id.value == 'approve-dashboard-ready-visual' &&
        approval.scenarioId.value == 'dashboard-ready' &&
        approval.reviewGuideId.value == 'delivery-workspace-review' &&
        approval.reviewGuideStepId == 'review-ready-lab' &&
        approval.scope == HumanApprovalScope.evidenceSet,
    'human approval must bind the exact dashboard-ready ReviewGuide step',
  );

  final reviewGuide = catalogWithLab.reviewGuides.singleWhere(
    (guide) => guide.id == approval.reviewGuideId,
  );
  final reviewStep = reviewGuide.steps.singleWhere(
    (step) => step.id == approval.reviewGuideStepId,
  );
  _requireLabFact(
    reviewGuide.applicationId.value == 'sample' &&
        reviewGuide.title == 'Delivery workspace review' &&
        reviewStep.scenarioId == approval.scenarioId &&
        reviewStep.bindingId.value == 'dashboard-ready-lab-web' &&
        reviewStep.instruction ==
            'Run the dashboard-ready Scenario Lab script and inspect its collected Evidence.' &&
        reviewStep.observationCriteria ==
            'Automated acceptance and the human Evidence decision remain separate.',
    'approval must preserve the exact consumer-owned ReviewGuide narrative',
  );

  final supplementalBaseline = lab.supplementalArtifacts.single;
  _requireLabFact(
    supplementalBaseline.id.value == 'dashboard-ready-synthetic-baseline' &&
        supplementalBaseline.role ==
            SupplementalArtifactRole.comparisonBaseline &&
        supplementalBaseline.scenarioId.value == 'dashboard-ready' &&
        supplementalBaseline.requiredEvidenceId == evidence.id &&
        supplementalBaseline.artifactDigest ==
            Digest(
              'sha256:545700e983724de6acf0afda331ce881f9eb1332e358a88fcfa937b43b06a60b',
            ) &&
        supplementalBaseline.provenanceDigest ==
            Digest(
              'sha256:ce9b73a9435a6ab0c2409f0ac557baa79e386caf50d699175df3b231363d916a',
            ) &&
        supplementalBaseline.classification ==
            ArtifactClassification.internal &&
        evidence.allowedClassifications.contains(
          supplementalBaseline.classification,
        ),
    'comparison baseline must have explicit synthetic identity and provenance',
  );

  final plan = lab.plans.single;
  _requireLabFact(
    plan.scenarioId.value == 'dashboard-ready' &&
        sameStrings(
          plan.executionBindingIds.map((id) => id.value),
          const <String>{'dashboard-ready-lab-web'},
        ) &&
        sameStrings(plan.controlIds.map((id) => id.value), const <String>{
          'dashboard-ready-highlight-enabled',
        }) &&
        sameStrings(plan.operationIds.map((id) => id.value), const <String>{
          'enable-dashboard-ready-highlight',
          'collect-dashboard-ready-visual',
          'reset-dashboard-ready-highlight',
        }) &&
        sameStrings(plan.scriptIds.map((id) => id.value), const <String>{
          'exercise-dashboard-ready-lab',
        }) &&
        sameStrings(
          plan.automatedAcceptanceCriterionIds.map((id) => id.value),
          const <String>{
            'dashboard-ready-script-succeeds',
            'dashboard-ready-visual-accepted',
            'dashboard-ready-control-restored',
          },
        ) &&
        sameStrings(
          plan.requiredEvidenceIds.map((id) => id.value),
          const <String>{'dashboard-ready-visual'},
        ) &&
        sameStrings(
          plan.comparisonBindingIds.map((id) => id.value),
          const <String>{'dashboard-ready-baseline-candidate'},
        ) &&
        sameStrings(
          plan.humanApprovalRequirementIds.map((id) => id.value),
          const <String>{'approve-dashboard-ready-visual'},
        ) &&
        sameStrings(
          plan.supplementalArtifactIds.map((id) => id.value),
          const <String>{'dashboard-ready-synthetic-baseline'},
        ),
    'ScenarioLabPlan must exactly allowlist every dashboard-ready Lab entity',
  );

  const facetCompiler = ScenarioFacetCompiler();
  final facetsWithoutLab = facetCompiler.compile(
    documentsWithoutLab,
    catalog: catalogWithoutLab,
  );
  final facetsWithLab = facetCompiler.compile(
    loaded.documents,
    catalog: catalogWithLab,
  );
  final readyFacet = facetsWithLab.scenarioFacets.singleWhere(
    (facet) => facet.scenarioId.value == 'dashboard-ready',
  );
  _requireLabFact(
    readyFacet.fixtureId.value == 'sample.dashboard.synthetic',
    'dashboard-ready Lab may use only its declared synthetic fixture',
  );

  const topologyCompiler = ExperienceTopologyCompiler();
  final topologyWithoutLab = topologyCompiler.compile(
    documentsWithoutLab,
    catalog: catalogWithoutLab,
  );
  final topologyWithLab = topologyCompiler.compile(
    loaded.documents,
    catalog: catalogWithLab,
  );
  final bundleWithoutLab = ExperienceTopologyBundle(
    catalog: catalogWithoutLab,
    topology: topologyWithoutLab.topology,
    layouts: topologyWithoutLab.layouts,
  );
  final bundleWithLab = ExperienceTopologyBundle(
    catalog: catalogWithLab,
    topology: topologyWithLab.topology,
    layouts: topologyWithLab.layouts,
  );
  bool sameWire(Object? left, Object? right) =>
      const JcsCanonicalizer().canonicalize(left) ==
      const JcsCanonicalizer().canonicalize(right);
  _requireLabFact(
    CatalogManifest.schemaVersion == 1 &&
        catalogWithLab.digest == catalogWithoutLab.digest &&
        sameWire(catalogWithLab.toJson(), catalogWithoutLab.toJson()),
    'Scenario Lab v2 must not alter CatalogManifest v1 bytes or digest',
  );
  _requireLabFact(
    ExperienceTopologyManifest.schemaVersion == 1 &&
        ExperienceTopologyBundle.schemaVersion == 1 &&
        topologyWithLab.topology.digest == topologyWithoutLab.topology.digest &&
        bundleWithLab.digest == bundleWithoutLab.digest &&
        sameWire(bundleWithLab.toJson(), bundleWithoutLab.toJson()),
    'Scenario Lab v2 must not alter Topology/Layout bundle v1 bytes or digest',
  );
  _requireLabFact(
    ScenarioFacetManifest.schemaVersion == 1 &&
        facetsWithLab.digest == facetsWithoutLab.digest &&
        sameWire(facetsWithLab.toJson(), facetsWithoutLab.toJson()),
    'Scenario Lab v2 must not alter ScenarioFacetManifest v1 bytes or digest',
  );

  stdout.writeln(
    'Reference Scenario Lab is valid: dashboard-ready has one typed boolean '
    'control, one bounded script, explicit automated/human criteria, one '
    'visual comparison, one static baseline and a candidate collected by the '
    'current run; '
    'no supplemental artifact bytes were resolved.',
  );
}

void _verifyReferenceQualityDecisionConfiguration(Directory flutterWorkspace) {
  const builtin = BuiltinModuleCatalog();
  final moduleCatalog = builtin.create(platform: Platform.operatingSystem);
  final loaded = const WorkspaceCatalogLoader().load(
    startPath: flutterWorkspace.path,
    explicitConfigPath: '${flutterWorkspace.path}/workspace.yaml',
  );
  final request = loaded.configuration.kitPlanRequest;
  final plan = request.resolve(
    catalog: moduleCatalog,
    configurationSchemas: builtin.configurationSchemas,
  );
  final qualityModuleId = ModuleId('quality.decisions.local');
  final descriptors = moduleCatalog.modules
      .where((descriptor) => descriptor.id == qualityModuleId)
      .toList(growable: false);
  final resolvedModules = plan.enabledModules
      .where((module) => module.moduleId == qualityModuleId)
      .toList(growable: false);
  _requireQualityFact(
    plan.profileId == 'full-local' &&
        plan.enabledModules.length == moduleCatalog.modules.length &&
        descriptors.length == 1 &&
        resolvedModules.length == 1,
    'full-local must enable every packaged Module, including quality.decisions.local',
  );

  final descriptor = descriptors.single;
  final resolved = resolvedModules.single;
  _requireQualityFact(
    descriptor.configurationSchema ==
            BuiltinModuleCatalog.scenarioQualityDecisionSettingsSchema &&
        descriptor.surfaces.length == 1 &&
        descriptor.surfaces.contains(ModuleSurface.host) &&
        descriptor.effects.length == 1 &&
        descriptor.effects.contains(ModuleEffect.decision) &&
        descriptor.provides.length == 1 &&
        descriptor.provides.single.id == 'quality.decisions' &&
        descriptor.provides.single.version == 1 &&
        resolved.descriptorDigest == descriptor.digest,
    'quality decisions must remain a Host-only decision effect with one declared capability',
  );

  const expectedSettings = <String, Object?>{
    'authorityId': 'delivery-lab.local',
    'accessPolicyId': 'delivery-lab.review-v1',
    'principalId': 'delivery-lab.reviewer',
    'role': 'reviewer',
    'allowedRequirementIds': <String>['approve-dashboard-ready-visual'],
    'allowedDecisions': <String>['approved', 'rejected'],
    'artifactClassifications': <String>['internal'],
    'grantTtlSeconds': 120,
  };
  bool sameJson(Object? left, Object? right) =>
      const JcsCanonicalizer().canonicalize(left) ==
      const JcsCanonicalizer().canonicalize(right);
  _requireQualityFact(
    sameJson(resolved.settings, expectedSettings),
    'resolved authority settings must equal the consumer-owned allowlists exactly',
  );

  final schemaValue =
      builtin.configurationSchemas[BuiltinModuleCatalog
          .scenarioQualityDecisionSettingsSchema];
  _requireQualityFact(
    schemaValue is Map<String, Object?> &&
        schemaValue['additionalProperties'] == false,
    'quality decision settings must use a closed public configuration schema',
  );
  var adjacentSettingRejected = false;
  try {
    KitPlanRequest(
      profileId: request.profileId,
      overlays: <KitSelection>[
        ...request.overlays,
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(
              moduleId: qualityModuleId,
              enabled: true,
              settings: const <String, Object?>{'adjacent': true},
            ),
          ],
        ),
      ],
      startupPolicy: request.startupPolicy,
    ).resolve(
      catalog: moduleCatalog,
      configurationSchemas: builtin.configurationSchemas,
    );
  } on KitPlanResolutionException {
    adjacentSettingRejected = true;
  }
  _requireQualityFact(
    adjacentSettingRejected,
    'an adjacent authority setting must fail before any Module effect',
  );

  bool sameStrings(Iterable<String> actual, Set<String> expected) {
    final values = actual.toSet();
    return values.length == actual.length &&
        values.length == expected.length &&
        values.containsAll(expected);
  }

  _requireQualityFact(
    sameStrings(
          ScenarioQualityDecisionOperation.values.map((value) => value.name),
          const <String>{'describe', 'open', 'grant', 'append', 'get'},
        ) &&
        !descriptor.toJson().containsKey('rpcMethods') &&
        !plan.toJson().containsKey('rpcMethods'),
    'static descriptors may declare the closed operation contract, but RPC availability requires an EffectiveKitManifest',
  );

  final noProviderLoaded = const WorkspaceCatalogLoader().load(
    startPath: flutterWorkspace.path,
    explicitConfigPath: '${flutterWorkspace.path}/journey-no-evidence.yaml',
  );
  final noProviderPlan = noProviderLoaded.configuration.kitPlanRequest.resolve(
    catalog: moduleCatalog,
    configurationSchemas: builtin.configurationSchemas,
  );
  _requireQualityFact(
    noProviderPlan.enabledModules.every(
      (module) => module.moduleId != qualityModuleId,
    ),
    'the no-provider profile must not acquire a decision authority',
  );

  stdout.writeln(
    'Reference Quality configuration is valid: consumer-owned reviewer '
    'allowlists are closed, quality.decisions.local is a Host decision '
    'capability, evidenceSet remains authored, and runtime RPC availability '
    'is not claimed by this static check.',
  );
}

void _verifyReferenceAuthoringConfiguration(Directory flutterWorkspace) {
  const builtin = BuiltinModuleCatalog();
  final moduleCatalog = builtin.create(platform: Platform.operatingSystem);
  final loaded = const WorkspaceCatalogLoader().load(
    startPath: flutterWorkspace.path,
    explicitConfigPath: '${flutterWorkspace.path}/workspace.yaml',
  );
  final plan = loaded.configuration.kitPlanRequest.resolve(
    catalog: moduleCatalog,
    configurationSchemas: builtin.configurationSchemas,
  );
  final runtimeDescriptor = moduleCatalog.modules.singleWhere(
    (descriptor) => descriptor.id.value == 'authoring.local',
  );
  final studioDescriptor = moduleCatalog.modules.singleWhere(
    (descriptor) => descriptor.id.value == 'studio.authoring',
  );
  final resolved = plan.enabledModules.singleWhere(
    (module) => module.moduleId.value == 'authoring.local',
  );

  const expectedSettings = <String, Object?>{
    'authorityId': 'delivery-lab.authoring-local',
    'accessPolicyId': 'delivery-lab.authoring-v1',
    'principalId': 'delivery-lab.author',
    'allowedOperations': <String>[
      'openDraft',
      'abandonDraft',
      'moveNode',
      'undo',
      'redo',
      'reset',
      'appendFinding',
      'proposeConcept',
      'appendComment',
      'prepareReview',
      'evaluateAutomatedAcceptance',
      'decideReview',
      'promote',
    ],
    'grantTtlSeconds': 120,
  };
  bool sameJson(Object? left, Object? right) =>
      const JcsCanonicalizer().canonicalize(left) ==
      const JcsCanonicalizer().canonicalize(right);
  _requireAuthoringFact(
    runtimeDescriptor.provides.map((item) => item.id).single ==
            'experience.authoring' &&
        runtimeDescriptor.surfaces.length == 1 &&
        runtimeDescriptor.surfaces.contains(ModuleSurface.host) &&
        runtimeDescriptor.effects.containsAll(const <ModuleEffect>{
          ModuleEffect.authoring,
          ModuleEffect.decision,
        }) &&
        runtimeDescriptor.resourceRequirements.containsAll(
          const <ModuleResource>{
            ModuleResource.filesystemRead,
            ModuleResource.filesystemWrite,
          },
        ) &&
        studioDescriptor.surfaces.contains(ModuleSurface.studio) &&
        studioDescriptor.effects.length == 1 &&
        studioDescriptor.effects.contains(ModuleEffect.query),
    'authoring.local must own Host effects while studio.authoring remains query-only',
  );
  _requireAuthoringFact(
    sameJson(resolved.settings, expectedSettings),
    'consumer-owned authoring authority settings must resolve byte-semantically',
  );
  final schemaValue =
      builtin.configurationSchemas[BuiltinModuleCatalog
          .experienceAuthoringSettingsSchema];
  _requireAuthoringFact(
    schemaValue is Map<String, Object?> &&
        schemaValue['additionalProperties'] == false &&
        !expectedSettings.containsKey('path') &&
        !expectedSettings.containsKey('contentRoot'),
    'authoring settings must be closed and must not expose filesystem routing',
  );
  _requireAuthoringFact(
    ExperienceAuthoringRpcMethod.values.length == 16 &&
        ExperienceAuthoringRpcMethod.values.every(
          (method) => method.startsWith('experience.authoring.'),
        ),
    'Experience Authoring v1 must remain an exact sixteen-method surface',
  );

  stdout.writeln(
    'Reference Authoring configuration is valid: the consumer supplies a '
    'closed local authority, the Studio remains query-only, and no path or '
    'routing authority is present in the public settings.',
  );
}

void _verifyReferenceMotionContext(Directory flutterWorkspace) {
  const builtin = BuiltinModuleCatalog();
  final moduleCatalog = builtin.create(platform: Platform.operatingSystem);
  final loaded = const WorkspaceCatalogLoader().load(
    startPath: flutterWorkspace.path,
    explicitConfigPath: '${flutterWorkspace.path}/workspace.yaml',
  );
  final plan = loaded.configuration.kitPlanRequest.resolve(
    catalog: moduleCatalog,
    configurationSchemas: builtin.configurationSchemas,
  );
  final catalog = const CatalogCompiler().compile(
    loaded.documents,
    layout: loaded.layout,
  );
  final topology = const ExperienceTopologyCompiler()
      .compile(loaded.documents, catalog: catalog)
      .topology;
  const compiler = MotionManifestCompiler();
  _requireMotionContextFact(
    compiler.hasAuthoring(loaded.documents),
    'the reference corpus must author a MotionSequence v2 document',
  );
  final motion = compiler.compile(
    loaded.documents,
    catalog: catalog,
    topology: topology,
  );
  final sequence = motion.sequences.single;
  _requireMotionContextFact(
    sequence.id == 'delivery-review-motion' &&
        sequence.projectionId.value == 'delivery-journey' &&
        sequence.steps.length == 2 &&
        sequence.totalDurationFor(MotionMode.full) == 880 &&
        sequence.totalDurationFor(MotionMode.reduced) == 580 &&
        sequence.totalDurationFor(MotionMode.none) == 0 &&
        sequence.staticSummary.contains('Loading resolves to ready'),
    'Motion must expose two exact transitions and a complete static equivalent',
  );
  _requireMotionContextFact(
    MotionManifest.fromJson(
          motion.toJson(),
          catalog: catalog,
          topology: topology,
        ).digest ==
        motion.digest,
    'Motion wire v1 must round-trip against the same catalog/topology pair',
  );

  final moduleIds = plan.enabledModules
      .map((module) => module.moduleId.value)
      .toSet();
  _requireMotionContextFact(
    moduleIds.containsAll(const <String>{
      'studio.motion',
      'motion.local',
      'studio.context',
      'context.builder.local',
    }),
    'full-local must resolve the four explicit Motion/Context modules',
  );
  final contextRuntime = moduleCatalog.modules.singleWhere(
    (module) => module.id.value == 'context.builder.local',
  );
  final motionRuntime = moduleCatalog.modules.singleWhere(
    (module) => module.id.value == 'motion.local',
  );
  _requireMotionContextFact(
    contextRuntime.effects.length == 1 &&
        contextRuntime.effects.contains(ModuleEffect.query) &&
        contextRuntime.provides.single.id == 'context.build' &&
        motionRuntime.effects.length == 1 &&
        motionRuntime.effects.contains(ModuleEffect.query) &&
        motionRuntime.provides.single.id == 'experience.motion',
    'Motion and Context runtime providers must remain read-only capabilities',
  );

  stdout.writeln(
    'Reference Motion/Context configuration is valid: two temporal '
    'transitions provide full/reduced/none modes with a complete static '
    'equivalent, and Context Builder remains an explicit read-only Host '
    'capability with independent budgets and omissions.',
  );
}

void _requireLabFact(bool condition, String message) {
  if (!condition) throw StateError('Invalid dashboard-ready Lab: $message');
}

void _requireQualityFact(bool condition, String message) {
  if (!condition) {
    throw StateError('Invalid Delivery Lab Quality configuration: $message');
  }
}

void _requireAuthoringFact(bool condition, String message) {
  if (!condition) {
    throw StateError('Invalid Delivery Lab Authoring configuration: $message');
  }
}

void _requireMotionContextFact(bool condition, String message) {
  if (!condition) {
    throw StateError(
      'Invalid Delivery Lab Motion/Context configuration: $message',
    );
  }
}

void _requireTaxonomyFact(bool condition, String message) {
  if (!condition) throw StateError('Invalid Delivery Lab taxonomy: $message');
}

void _requireReferenceFact(bool condition, String message) {
  if (!condition) throw StateError('Invalid Delivery Lab topology: $message');
}

Directory _repositoryRoot() {
  var current = File.fromUri(Platform.script).parent;
  while (current.parent.path != current.path) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('Abel repository root not found');
}

void _ensureLocalConfiguration(Directory workspace) {
  final local = File('${workspace.path}/workspace.local.yaml');
  if (local.existsSync()) return;
  final template = File('${workspace.path}/workspace.local.example.yaml');
  if (!template.existsSync()) {
    throw FileSystemException(
      'Missing local configuration template',
      template.path,
    );
  }
  local.writeAsBytesSync(template.readAsBytesSync(), flush: true);
  stdout.writeln(
    'Created ignored workspace.local.yaml from the safe loopback template.',
  );
}

bool _targetBuildRequired(
  Directory repository,
  Directory workspace,
  Directory targetAssets,
) {
  final index = File('${targetAssets.path}/index.html');
  if (!index.existsSync()) return true;
  final builtAt = index.lastModifiedSync();
  final inputs = <File>[
    File('${workspace.path}/pubspec.yaml'),
    File('${repository.path}/pubspec.lock'),
    File('${workspace.path}/tool/target_main.dart'),
    ..._sourceFiles(Directory('${workspace.path}/lib')),
    ..._sourceFiles(Directory('${workspace.path}/web')),
  ];
  return inputs.any(
    (input) => input.existsSync() && input.lastModifiedSync().isAfter(builtAt),
  );
}

Iterable<File> _sourceFiles(Directory directory) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) yield entity;
  }
}

Future<void> _requireAvailablePort(int port) async {
  ServerSocket? socket;
  try {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException {
    throw StateError('Required showcase port $port is already in use');
  } finally {
    await socket?.close();
  }
}

Future<void> _waitForAvailablePorts(List<int> ports) async {
  Object? lastError;
  for (var attempt = 0; attempt < 50; attempt += 1) {
    try {
      for (final port in ports) {
        await _requireAvailablePort(port);
      }
      return;
    } on Object catch (error) {
      lastError = error;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw StateError('Showcase ports were not released: $lastError');
}

Future<String?> _watchHealth(
  List<Uri> healthUris,
  Future<void> generationEnded,
) async {
  var ended = false;
  unawaited(generationEnded.then((_) => ended = true));
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = const Duration(seconds: 2);
  var consecutiveFailures = 0;
  try {
    while (!ended) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (ended) return null;
      final failed = <Uri>[];
      for (final uri in healthUris) {
        try {
          final request = await client.getUrl(uri);
          final response = await request.close().timeout(
            const Duration(seconds: 2),
          );
          await response.drain<void>();
          if (response.statusCode != HttpStatus.ok) failed.add(uri);
        } on Object {
          failed.add(uri);
        }
      }
      if (failed.isEmpty) {
        consecutiveFailures = 0;
        continue;
      }
      consecutiveFailures += 1;
      if (consecutiveFailures >= 3) {
        return 'health probes failed three times for '
            '${failed.map((uri) => uri.origin).join(', ')}';
      }
    }
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _watchForReadiness(
  Process process, {
  required String label,
}) {
  final ready = Completer<Map<String, Object?>>();
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      stdout.writeln('[$label] $line');
      if (ready.isCompleted) return;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, Object?> &&
            decoded['ok'] != false &&
            (decoded['status'] == 'ready' ||
                (decoded['result'] as Map<String, Object?>?)?['status'] ==
                    'ready')) {
          ready.complete(decoded);
        }
      } on FormatException {
        // Tooling may emit non-JSON progress before its canonical ready line.
      }
    },
  );
  unawaited(
    process.exitCode.then((code) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError('$label exited with $code before reporting readiness'),
        );
      }
    }),
  );
  return ready.future.timeout(const Duration(minutes: 2));
}

void _forwardErrors(Process process, String label) {
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr.writeln('[$label] $line'));
}

Future<void> _waitForHealth(Uri uri) async {
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    for (var attempt = 0; attempt < 40; attempt += 1) {
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) return;
      } on SocketException {
        // The process has reported readiness, but the listener may need one
        // more scheduler turn before accepting the probe.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Health endpoint did not become ready: $uri');
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _runJson(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String label,
}) async {
  stdout.writeln('$label…');
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stderr}\n${result.stdout}',
      result.exitCode,
    );
  }
  final decoded = jsonDecode((result.stdout as String).trim());
  if (decoded is! Map<String, Object?> || decoded['ok'] != true) {
    throw StateError('$label failed: ${result.stdout}');
  }
  return decoded;
}

Future<void> _runChecked(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String label,
}) async {
  stdout.writeln('$label…');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, label, exitCode);
  }
}

void _printGatewayPlans(Map<String, Object?> compilation) {
  final result = compilation['result']! as Map<String, Object?>;
  final plans = result['gatewayPlans']! as List<Object?>;
  stdout.writeln('Gateway plans persisted in the consumer CAS:');
  for (final raw in plans.cast<Map<String, Object?>>()) {
    stdout.writeln(
      '  ${raw['presetId']}: ${raw['artifactDigest']} '
      '(plan ${raw['planDigest']})',
    );
  }
}

final class _ShowcaseOptions {
  const _ShowcaseOptions({
    required this.buildStudio,
    required this.buildTarget,
    required this.noOpen,
    required this.checkOnly,
  });

  final bool buildStudio;
  final bool buildTarget;
  final bool noOpen;
  final bool checkOnly;

  factory _ShowcaseOptions.parse(List<String> arguments) {
    final supported = const <String>{
      '--build-studio',
      '--build-target',
      '--no-open',
      '--check',
    };
    final unknown = arguments.where(
      (argument) => !supported.contains(argument),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown showcase option ${unknown.first}');
    }
    return _ShowcaseOptions(
      buildStudio: arguments.contains('--build-studio'),
      buildTarget: arguments.contains('--build-target'),
      noOpen: arguments.contains('--no-open'),
      checkOnly: arguments.contains('--check'),
    );
  }
}
