import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../composition/builtin_module_catalog.dart';
import '../composition/module_lifecycle.dart';
import '../gateway/gateway_sidecar_supervisor.dart';
import '../gateway/workspace_gateway_plan_compiler.dart';
import '../lab/host_scenario_lab_runtime.dart';
import '../lab/host_scenario_quality_service.dart';
import '../process/managed_process_supervisor.dart';
import '../secure_id_generator.dart';
import '../storage/filesystem_workspace_store.dart';
import '../system_clock.dart';
import '../workspace/workspace_catalog_loader.dart';
import 'app_adapter_capture_bridge.dart' hide AppAdapterCaptureReceipt;
import 'host_auto_preview_service.dart';
import 'host_context_builder_service.dart';
import 'host_experience_authoring_runtime.dart';
import 'host_module_kernel.dart';
import 'host_resource_registry.dart';
import 'host_rpc_server.dart';
import 'host_workspace_service.dart';

final class WorkspaceHost {
  factory WorkspaceHost({
    required Uri studioOrigin,
    required String sessionToken,
    required String workspaceRoot,
    required List<LaunchProfile> launchProfiles,
    String? gatewaySidecarCommand,
    List<String> gatewaySidecarArguments = const <String>[],
    String? gatewaySidecarWorkingDirectory,
    CatalogManifest? workspaceCatalog,
    ExperienceTopologyBundle? workspaceExperienceBundle,
    ScenarioFacetManifest? workspaceScenarioFacetManifest,
    ScenarioLabManifest? workspaceScenarioLabManifest,
    MotionManifest? workspaceMotionManifest,
    int rpcPort = 0,
    bool exposeStudioBootstrap = false,
  }) => WorkspaceHost.create(
    studioOrigin: studioOrigin,
    sessionToken: sessionToken,
    workspaceRoot: workspaceRoot,
    launchProfiles: launchProfiles,
    gatewaySidecarCommand: gatewaySidecarCommand,
    gatewaySidecarArguments: gatewaySidecarArguments,
    gatewaySidecarWorkingDirectory: gatewaySidecarWorkingDirectory,
    workspaceCatalog: workspaceCatalog,
    workspaceExperienceBundle: workspaceExperienceBundle,
    workspaceScenarioFacetManifest: workspaceScenarioFacetManifest,
    workspaceScenarioLabManifest: workspaceScenarioLabManifest,
    workspaceMotionManifest: workspaceMotionManifest,
    rpcPort: rpcPort,
    exposeStudioBootstrap: exposeStudioBootstrap,
  );

  factory WorkspaceHost.create({
    required Uri studioOrigin,
    required String sessionToken,
    required String workspaceRoot,
    required List<LaunchProfile> launchProfiles,
    String? gatewaySidecarCommand,
    List<String> gatewaySidecarArguments = const <String>[],
    String? gatewaySidecarWorkingDirectory,
    CatalogManifest? workspaceCatalog,
    ExperienceTopologyBundle? workspaceExperienceBundle,
    ScenarioFacetManifest? workspaceScenarioFacetManifest,
    ScenarioLabManifest? workspaceScenarioLabManifest,
    MotionManifest? workspaceMotionManifest,
    int rpcPort = 0,
    bool exposeStudioBootstrap = false,
  }) {
    const builtins = BuiltinModuleCatalog();
    final catalog = builtins.create(platform: _hostPlatformId());
    final plan = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'full-local',
      overlays: <KitSelection>[
        if (gatewaySidecarCommand == null)
          KitSelection(
            modules: <KitModuleSelection>[
              KitModuleSelection(
                moduleId: ModuleId('gateway.interceptor'),
                enabled: false,
              ),
            ],
          ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );
    return WorkspaceHost.fromResolvedPlan(
      studioOrigin: studioOrigin,
      sessionToken: sessionToken,
      workspaceRoot: workspaceRoot,
      launchProfiles: launchProfiles,
      catalog: catalog,
      plan: plan,
      gatewaySidecarCommand: gatewaySidecarCommand,
      gatewaySidecarArguments: gatewaySidecarArguments,
      gatewaySidecarWorkingDirectory: gatewaySidecarWorkingDirectory,
      workspaceCatalog: workspaceCatalog,
      workspaceExperienceBundle: workspaceExperienceBundle,
      workspaceScenarioFacetManifest: workspaceScenarioFacetManifest,
      workspaceScenarioLabManifest: workspaceScenarioLabManifest,
      workspaceMotionManifest: workspaceMotionManifest,
      rpcPort: rpcPort,
      exposeStudioBootstrap: exposeStudioBootstrap,
    );
  }

  factory WorkspaceHost.fromResolvedPlan({
    required Uri studioOrigin,
    required String sessionToken,
    required String workspaceRoot,
    required List<LaunchProfile> launchProfiles,
    required ModuleCatalog catalog,
    required ResolvedKitPlan plan,
    String? gatewaySidecarCommand,
    List<String> gatewaySidecarArguments = const <String>[],
    String? gatewaySidecarWorkingDirectory,
    CatalogManifest? workspaceCatalog,
    ExperienceTopologyBundle? workspaceExperienceBundle,
    ScenarioFacetManifest? workspaceScenarioFacetManifest,
    ScenarioLabManifest? workspaceScenarioLabManifest,
    MotionManifest? workspaceMotionManifest,
    int rpcPort = 0,
    bool exposeStudioBootstrap = false,
  }) {
    bool enabled(String moduleId) =>
        plan.enabledModules.any((module) => module.moduleId.value == moduleId);
    final sessionsEnabled = enabled('sessions.local');
    final captureEnabled = enabled('capture.app-adapter');
    final autoPreviewEnabled = enabled('evidence.auto-preview');
    final gatewayEnabled = enabled('gateway.interceptor');
    final scenarioLabEnabled = enabled('scenario.lab.local');
    final qualityDecisionsEnabled = enabled('quality.decisions.local');
    final authoringEnabled = enabled('authoring.local');
    final studioAuthoringEnabled = enabled('studio.authoring');
    final motionEnabled = enabled('motion.local');
    final contextBuilderEnabled = enabled('context.builder.local');
    final qualityDecisionAuthority = qualityDecisionsEnabled
        ? HostScenarioQualityDecisionAuthority.fromSettings(
            plan.enabledModules
                .singleWhere(
                  (module) =>
                      module.moduleId.value == 'quality.decisions.local',
                )
                .settings,
          )
        : null;
    final scenarioLabEvidenceClassification = scenarioLabEnabled
        ? _scenarioLabEvidenceClassification(plan)
        : null;
    final catalogEnabled = enabled('catalog');
    final studioEnabled = enabled('studio.shell');
    if (gatewayEnabled && gatewaySidecarCommand == null) {
      throw ArgumentError(
        'gateway.interceptor requires a packaged sidecar command',
      );
    }
    if (scenarioLabEvidenceClassification != null && !captureEnabled) {
      throw ArgumentError(
        'Scenario Lab Evidence classification requires capture.app-adapter',
      );
    }
    final ids = SecureIdGenerator();
    final clock = SystemClock();
    final coordinator = SessionCoordinator(clock: clock, ids: ids);
    late final WorkspaceHost application;
    final processes = ManagedProcessSupervisor(
      workspaceRoot: workspaceRoot,
      onExit: (ownerId, exitCode, stdoutTail, stderrTail) async {
        await application._onProcessExit(
          ownerId,
          exitCode,
          stdoutTail,
          stderrTail,
        );
      },
    );
    final profiles = <String, LaunchProfile>{
      for (final profile in launchProfiles) profile.id: profile,
    };
    final store = FileSystemWorkspaceStore(workspaceRoot: workspaceRoot);
    HostWorkspaceContent loadWorkspaceContent() {
      final loaded = const WorkspaceCatalogLoader().load(
        startPath: workspaceRoot,
      );
      final workspaceCatalog = const CatalogCompiler().compile(
        loaded.documents,
        layout: loaded.layout,
      );
      const topologyCompiler = ExperienceTopologyCompiler();
      final ExperienceTopologyBundle? experienceBundle;
      if (topologyCompiler.hasAuthoring(loaded.documents)) {
        final compiled = topologyCompiler.compile(
          loaded.documents,
          catalog: workspaceCatalog,
        );
        experienceBundle = ExperienceTopologyBundle(
          catalog: workspaceCatalog,
          topology: compiled.topology,
          layouts: compiled.layouts,
        );
      } else {
        experienceBundle = null;
      }
      const facetCompiler = ScenarioFacetCompiler();
      final scenarioFacetManifest = facetCompiler.hasAuthoring(loaded.documents)
          ? facetCompiler.compile(loaded.documents, catalog: workspaceCatalog)
          : null;
      const scenarioLabCompiler = ScenarioLabCompiler();
      final scenarioLabManifest =
          scenarioLabCompiler.hasAuthoring(loaded.documents)
          ? scenarioLabCompiler.compile(
              loaded.documents,
              catalog: workspaceCatalog,
            )
          : null;
      const motionCompiler = MotionManifestCompiler();
      final motionManifest =
          motionEnabled &&
              experienceBundle != null &&
              motionCompiler.hasAuthoring(loaded.documents)
          ? motionCompiler.compile(
              loaded.documents,
              catalog: workspaceCatalog,
              topology: experienceBundle.topology,
            )
          : null;
      return HostWorkspaceContent(
        catalog: workspaceCatalog,
        experienceBundle: experienceBundle,
        scenarioFacetManifest: scenarioFacetManifest,
        scenarioLabManifest: scenarioLabManifest,
        motionManifest: motionManifest,
      );
    }

    if ((workspaceExperienceBundle != null ||
            workspaceScenarioFacetManifest != null ||
            workspaceScenarioLabManifest != null ||
            workspaceMotionManifest != null) &&
        workspaceCatalog == null) {
      throw ArgumentError(
        'Injected Experience content requires workspaceCatalog for validation',
      );
    }
    final injectedContent = workspaceCatalog == null
        ? null
        : HostWorkspaceContent(
            catalog: workspaceCatalog,
            experienceBundle: workspaceExperienceBundle,
            scenarioFacetManifest: workspaceScenarioFacetManifest,
            scenarioLabManifest: workspaceScenarioLabManifest,
            motionManifest: workspaceMotionManifest,
          );
    final initialContent = catalogEnabled
        ? injectedContent ?? loadWorkspaceContent()
        : null;
    final workspace = !catalogEnabled
        ? null
        : HostWorkspaceService(
            initialCatalog: initialContent!.catalog,
            initialExperienceBundle: initialContent.experienceBundle,
            initialScenarioFacetManifest: initialContent.scenarioFacetManifest,
            initialScenarioLabManifest: initialContent.scenarioLabManifest,
            initialMotionManifest: initialContent.motionManifest,
            clock: clock,
            providerBindings: plan.providerBindings,
            reloadContent: injectedContent == null
                ? loadWorkspaceContent
                : null,
          );
    final captureBridge = AppAdapterCaptureBridge(
      store: store,
      clock: clock,
      ids: ids,
    );
    if (profiles.length != launchProfiles.length) {
      throw ArgumentError('LaunchProfile IDs must be unique');
    }
    final methods = <String, HostRpcMethodHandler>{};
    final gateways = !gatewayEnabled
        ? null
        : GatewaySidecarSupervisor(
            workspaceRoot: workspaceRoot,
            command: gatewaySidecarCommand!,
            arguments: gatewaySidecarArguments,
            workingDirectory: gatewaySidecarWorkingDirectory ?? workspaceRoot,
            ids: ids,
          );
    final scenarioLab = !scenarioLabEnabled
        ? null
        : HostScenarioLabRuntime(
            workspaceRoot: workspaceRoot,
            workspaceStore: store,
            workspace:
                workspace ??
                (throw StateError(
                  'scenario.lab.local requires catalog workspace',
                )),
            launchProfiles: profiles,
            gatewaySupervisor: gateways,
            captureBridge: scenarioLabEvidenceClassification == null
                ? null
                : captureBridge,
            evidenceClassification: scenarioLabEvidenceClassification,
            qualityDecisionsEnabled: qualityDecisionsEnabled,
            qualityDecisionAuthority: qualityDecisionAuthority,
            clock: clock,
            ids: ids,
          );
    final contributions = <ModuleId, ModuleContribution>{
      if (catalogEnabled)
        ModuleId('catalog'): ModuleContribution(
          rpcMethods: const <String>[
            'workspace.describe',
            'workspace.open',
            'workspace.refresh',
            'experience.describe',
            'experience.open',
            'experience.content.describe',
            'experience.content.open',
          ],
        ),
      if (sessionsEnabled)
        ModuleId('sessions.local'): ModuleContribution(
          rpcMethods: const <String>[
            'session.cancel',
            'session.get',
            'session.reset',
            'session.start',
            'session.stop',
          ],
          studioContributions: studioEnabled
              ? const <String>['studio.target']
              : const <String>[],
        ),
      if (captureEnabled)
        ModuleId('capture.app-adapter'): ModuleContribution(
          rpcMethods: const <String>['capture.request', 'capture.status'],
        ),
      if (autoPreviewEnabled)
        ModuleId('evidence.auto-preview'): ModuleContribution(
          rpcMethods: const <String>[
            'preview.collect',
            'preview.status',
            'preview.cancel',
          ],
        ),
      if (gatewayEnabled)
        ModuleId('gateway.interceptor'): ModuleContribution(
          rpcMethods: const <String>[
            'gateway.apply',
            'gateway.presets',
            'gateway.reset',
            'gateway.start',
            'gateway.status',
            'gateway.stop',
            'gateway.traffic',
            'gateway.verify',
          ],
          studioContributions: studioEnabled
              ? const <String>['studio.gateway']
              : const <String>[],
        ),
      if (enabled('studio.shell'))
        ModuleId('studio.shell'): ModuleContribution(
          studioContributions: const <String>['studio.shell'],
        ),
      if (enabled('studio.journey-map'))
        ModuleId('studio.journey-map'): ModuleContribution(
          studioContributions: const <String>['studio.journey-map'],
        ),
      if (enabled('studio.inventory'))
        ModuleId('studio.inventory'): ModuleContribution(
          studioContributions: const <String>['studio.inventory'],
        ),
      if (enabled('studio.lab'))
        ModuleId('studio.lab'): ModuleContribution(
          studioContributions: const <String>['studio.lab'],
        ),
      if (enabled('studio.quality'))
        ModuleId('studio.quality'): ModuleContribution(
          studioContributions: const <String>['studio.quality'],
        ),
      if (studioAuthoringEnabled)
        ModuleId('studio.authoring'): ModuleContribution(
          studioContributions: const <String>['studio.authoring'],
        ),
      if (enabled('studio.motion'))
        ModuleId('studio.motion'): ModuleContribution(
          studioContributions: const <String>['studio.motion'],
        ),
      if (enabled('studio.context'))
        ModuleId('studio.context'): ModuleContribution(
          studioContributions: const <String>['studio.context'],
        ),
      if (contextBuilderEnabled)
        ModuleId('context.builder.local'): ModuleContribution(
          rpcMethods: const <String>['context.describe', 'context.build'],
        ),
      if (authoringEnabled)
        ModuleId('authoring.local'): ModuleContribution(
          rpcMethods: ExperienceAuthoringRpcMethod.values.toList(
            growable: false,
          ),
        ),
      if (scenarioLabEnabled)
        ModuleId('scenario.lab.local'): ModuleContribution(
          rpcMethods: const <String>[
            'lab.cancel',
            'lab.get',
            'lab.reattach',
            'lab.relay.describe',
            'lab.relay.v2.describe',
            'lab.relay.hello',
            'lab.relay.next',
            'lab.relay.result',
            'lab.start',
          ],
        ),
      if (qualityDecisionsEnabled)
        ModuleId('quality.decisions.local'): ModuleContribution(
          rpcMethods: const <String>[
            'quality.decision.append',
            'quality.decision.get',
            'quality.decision.grant',
            'quality.describe',
            'quality.open',
          ],
        ),
      if (enabled('remote.execution'))
        ModuleId('remote.execution'): ModuleContribution(
          studioContributions: const <String>['studio.remote-session'],
        ),
      if (enabled('hosted.collaboration'))
        ModuleId('hosted.collaboration'): ModuleContribution(
          studioContributions: const <String>['studio.hosted'],
        ),
    };
    final kernel = HostModuleKernel(
      catalog: catalog,
      plan: plan,
      contributions: contributions,
    );
    late final HostRpcServer finalRpc;
    final authoring = !authoringEnabled
        ? null
        : HostExperienceAuthoringRuntime.create(
            workspaceRoot: workspaceRoot,
            workspaceStore: store,
            workspace:
                workspace ??
                (throw StateError(
                  'authoring.local requires catalog workspace',
                )),
            plan: plan,
            sourceBacked: injectedContent == null,
            publishEvent: (method, params) =>
                finalRpc.publishEvent(method, params),
            clock: clock.nowUtc,
          );
    final contextBuilder = !contextBuilderEnabled
        ? null
        : HostContextBuilderService(
            workspace:
                workspace ??
                (throw StateError(
                  'context.builder.local requires catalog workspace',
                )),
            workspaceRoot: workspaceRoot,
            sourceBacked: injectedContent == null,
          );
    application = WorkspaceHost._(
      coordinator: coordinator,
      processes: processes,
      profiles: profiles,
      gateways: gateways,
      store: store,
      captureBridge: captureBridge,
      kernel: kernel,
      captureEnabled: captureEnabled,
      workspace: workspace,
      scenarioLab: scenarioLab,
      authoring: authoring,
    );
    methods.addAll(<String, HostRpcMethodHandler>{
      'composition.describe': application._describeKit,
      'composition.health': application._kitHealth,
    });
    if (catalogEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'workspace.describe': application._describeWorkspace,
        'workspace.open': application._openWorkspace,
        'workspace.refresh': application._refreshWorkspace,
        'experience.describe': application._describeExperience,
        'experience.open': application._openExperience,
        'experience.content.describe': application._describeExperienceContent,
        'experience.content.open': application._openExperienceContent,
      });
    }
    if (sessionsEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'session.start': application._startSession,
        'session.get': application._getSession,
        'session.reset': application._resetSession,
        'session.stop': application._stopSession,
        'session.cancel': application._cancelSession,
      });
    }
    if (captureEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'capture.request': application._capture,
        'capture.status': application._captureStatus,
      });
    }
    if (autoPreviewEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'preview.collect': application._collectPreview,
        'preview.status': application._previewStatus,
        'preview.cancel': application._cancelPreview,
      });
    }
    if (gatewayEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'gateway.start': application._startGateway,
        'gateway.presets': application._gatewayPresets,
        'gateway.status': application._gatewayStatus,
        'gateway.apply': application._applyGateway,
        'gateway.verify': application._verifyGateway,
        'gateway.traffic': application._gatewayTraffic,
        'gateway.reset': application._resetGateway,
        'gateway.stop': application._stopGateway,
      });
    }
    if (scenarioLabEnabled) {
      final lab = scenarioLab!.host;
      methods.addAll(<String, HostRpcMethodHandler>{
        'lab.start': lab.start,
        'lab.get': lab.get,
        'lab.cancel': lab.cancel,
        'lab.reattach': lab.observe,
        'lab.relay.describe': lab.describeRelay,
        'lab.relay.v2.describe': lab.describeRelayV2,
        'lab.relay.hello': lab.acceptRelayHello,
        'lab.relay.next': lab.nextRelayCommand,
        'lab.relay.result': lab.acceptRelayResult,
      });
    }
    if (qualityDecisionsEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'quality.describe': application._describeQuality,
        'quality.open': application._openQuality,
        'quality.decision.grant': application._grantQualityDecision,
        'quality.decision.append': application._appendQualityDecision,
        'quality.decision.get': application._getQualityDecision,
      });
    }
    if (contextBuilderEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'context.describe': (params) {
          if (params.isNotEmpty) {
            throw const FormatException('context.describe accepts no params');
          }
          return contextBuilder!.describe().toJson();
        },
        'context.build': (params) => contextBuilder!
            .build(ContextBuildRequest.fromJson(params))
            .toJson(),
      });
    }

    finalRpc = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: sessionToken,
      port: rpcPort,
      resourceRegistry: HostResourceRegistry(clock: clock, ids: ids),
      applicationMethods: methods,
      connectionAwareMethods:
          authoring?.connectionAwareMethods ??
          const <String, HostRpcConnectionMethodHandler>{},
      onConnectionClosed: authoring?.onConnectionClosed,
      studioBootstrapManifest: exposeStudioBootstrap
          ? () => kernel.manifest
          : null,
    );
    application._rpc = finalRpc;
    if (autoPreviewEnabled) {
      final workspaceService = workspace;
      if (workspaceService == null) {
        throw StateError('evidence.auto-preview requires catalog workspace');
      }
      application._autoPreview = HostAutoPreviewService(
        workspace: workspaceService,
        store: store,
        plan: plan,
        platform: catalog.platform,
        resources: finalRpc.resources,
        hostOrigin: () => finalRpc.httpUri,
        studioOrigin: studioOrigin,
        publishEvent: finalRpc.publishEvent,
        clock: clock,
        ids: ids,
      );
    }
    return application;
  }

  WorkspaceHost._({
    required this.coordinator,
    required this.processes,
    required this.profiles,
    required this.gateways,
    required this.store,
    required this.captureBridge,
    required this.kernel,
    required this.captureEnabled,
    required this.workspace,
    required this.scenarioLab,
    required this.authoring,
  });

  final SessionCoordinator coordinator;
  final ManagedProcessSupervisor processes;
  final Map<String, LaunchProfile> profiles;
  final GatewaySidecarSupervisor? gateways;
  final FileSystemWorkspaceStore store;
  final AppAdapterCaptureBridge captureBridge;
  final HostModuleKernel kernel;
  final bool captureEnabled;
  final HostWorkspaceService? workspace;
  final HostScenarioLabRuntime? scenarioLab;
  final HostExperienceAuthoringRuntime? authoring;
  late final HostRpcServer _rpc;
  HostAutoPreviewService? _autoPreview;
  StreamSubscription<AppAdapterCaptureReceipt>? _captureSubscription;
  Future<void>? _closing;
  var _closed = false;

  HostRpcServer get rpc => _rpc;
  EffectiveKitManifest get effectiveKitManifest => kernel.manifest;
  String get effectiveKitManifestPath => p.join(
    store.workspaceRoot,
    '.dart_tool',
    'workspace',
    'effective-kit.json',
  );

  Future<void> start() async {
    await kernel.start();
    try {
      workspace?.initialize(effectiveKitManifest);
      authoring?.start();
      if (captureEnabled) {
        await captureBridge.start();
        _captureSubscription = captureBridge.completions.listen(
          (receipt) => unawaited(
            _rpc.publishEvent('capture.completed', receipt.toJson()),
          ),
        );
      }
      _persistEffectiveKitManifest();
      await _rpc.start();
      try {
        await _autoPreview?.initialize();
      } on Object {
        // The provider published a degraded diagnostic into the workspace.
      }
    } on Object {
      authoring?.close();
      await kernel.stop();
      rethrow;
    }
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    final closing = _closing;
    if (closing != null) return closing;
    late final Future<void> tracked;
    tracked = _close()
        .then((_) {
          _closed = true;
        })
        .whenComplete(() {
          if (identical(_closing, tracked)) _closing = null;
        });
    _closing = tracked;
    return tracked;
  }

  Future<void> _close() async {
    await _autoPreview?.close();
    await scenarioLab?.close();
    await _captureSubscription?.cancel();
    _captureSubscription = null;
    if (captureEnabled) await captureBridge.close();
    await gateways?.close();
    await processes.close();
    for (final session in coordinator.activeSessions) {
      if (session.state == SessionState.stopping) {
        coordinator.completeStop(session.id);
      } else {
        coordinator.cancel(session.id, 'host shutdown');
      }
    }
    await _rpc.close();
    authoring?.close();
    await kernel.stop();
  }

  Object? _describeKit(Map<String, Object?> _) => effectiveKitManifest.toJson();

  Object? _describeQuality(Map<String, Object?> params) => _qualityCall(
    () => _qualityService
        .describeRequest(ScenarioQualityDescribeRequest.fromJson(params))
        .toJson(),
  );

  Object? _openQuality(Map<String, Object?> params) => _qualityCall(
    () => _qualityService
        .openRequest(
          request: ScenarioQualityReviewOpenRequest.fromJson(params),
          resources: _rpc.resources,
          hostOrigin: _rpc.httpUri,
          audienceOrigin: _rpc.studioOrigin,
        )
        .toJson(),
  );

  Object? _grantQualityDecision(Map<String, Object?> params) => _qualityCall(
    () => _qualityService
        .grantRequest(ScenarioQualityDecisionGrantRequest.fromJson(params))
        .toJson(),
  );

  Object? _appendQualityDecision(Map<String, Object?> params) => _qualityCall(
    () => _qualityService
        .appendRequest(ScenarioQualityDecisionAppendRequest.fromJson(params))
        .toJson(),
  );

  Object? _getQualityDecision(Map<String, Object?> params) => _qualityCall(
    () => _qualityService
        .getRequest(ScenarioQualityDecisionGetRequest.fromJson(params))
        .toJson(),
  );

  HostScenarioQualityService get _qualityService =>
      scenarioLab?.quality ??
      (throw StateError('quality.decisions.local is disabled'));

  T _qualityCall<T>(T Function() action) {
    try {
      return action();
    } on HostScenarioQualityDecisionRejected catch (rejection) {
      throw HostRpcApplicationException(
        code: ScenarioQualityDecisionError.jsonRpcCode,
        message: 'Scenario Quality request rejected',
        data: rejection.error.toJson(),
      );
    }
  }

  Future<Object?> _describeWorkspace(Map<String, Object?> _) async {
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    await _autoPreview?.renewArtifactHandles();
    return service.describe();
  }

  Object? _describeExperience(Map<String, Object?> params) {
    if (params.isNotEmpty) {
      throw const FormatException('experience.describe accepts no params');
    }
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    return service.describeExperience();
  }

  Object? _describeExperienceContent(Map<String, Object?> params) {
    if (params.isNotEmpty) {
      throw const FormatException(
        'experience.content.describe accepts no params',
      );
    }
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    return service.describeContentSet().toJson();
  }

  Object? _openWorkspace(Map<String, Object?> params) {
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    final expectedRevision = params['expectedRevision'];
    if (expectedRevision != null && expectedRevision is! int) {
      throw const FormatException('expectedRevision must be an integer');
    }
    if (expectedRevision != null &&
        expectedRevision != service.snapshot.revision) {
      throw StateError('Workspace revision changed; describe it again');
    }
    final handle = service.open(
      resources: _rpc.resources,
      hostOrigin: _rpc.httpUri,
      studioOrigin: _rpc.studioOrigin,
    );
    return <String, Object?>{
      'revision': service.snapshot.revision,
      'snapshotDigest': service.snapshot.digest.value,
      'resource': handle.toJson(),
    };
  }

  Object? _openExperience(Map<String, Object?> params) {
    const allowed = <String>{'expectedRevision', 'expectedBundleDigest'};
    final unknown = params.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Unknown experience.open params: ${unknown.join(', ')}',
      );
    }
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    final expectedRevision = params['expectedRevision'];
    if (expectedRevision != null && expectedRevision is! int) {
      throw const FormatException('expectedRevision must be an integer');
    }
    if (expectedRevision != null &&
        expectedRevision != service.experienceRevision) {
      throw StateError('Experience revision changed; describe it again');
    }
    final bundle = service.experienceBundle;
    if (bundle == null) throw StateError('Experience topology is absent');
    final expectedBundleDigestValue = params['expectedBundleDigest'];
    if (expectedBundleDigestValue != null &&
        expectedBundleDigestValue is! String) {
      throw const FormatException('expectedBundleDigest must be a string');
    }
    if (expectedBundleDigestValue is String &&
        Digest(expectedBundleDigestValue) != bundle.digest) {
      throw StateError('Experience bundle changed; describe it again');
    }
    final handle = service.openExperience(
      resources: _rpc.resources,
      hostOrigin: _rpc.httpUri,
      studioOrigin: _rpc.studioOrigin,
    );
    return <String, Object?>{
      'revision': service.experienceRevision,
      'bundleDigest': bundle.digest.value,
      'resource': handle.toJson(),
    };
  }

  Object? _openExperienceContent(Map<String, Object?> params) {
    const required = <String>{
      'expectedRevision',
      'catalogDigest',
      'contentSetDigest',
    };
    final supplied = params.keys.toSet();
    if (supplied.length != required.length || !supplied.containsAll(required)) {
      throw const FormatException(
        'experience.content.open requires exactly expectedRevision, '
        'catalogDigest and contentSetDigest',
      );
    }
    final expectedRevision = params['expectedRevision'];
    if (expectedRevision is! int ||
        expectedRevision < 1 ||
        expectedRevision > JcsCanonicalizer.maxSafeInteger) {
      throw const FormatException(
        'expectedRevision must be a positive JSON-safe integer',
      );
    }
    final catalogDigestValue = params['catalogDigest'];
    if (catalogDigestValue is! String) {
      throw const FormatException('catalogDigest must be a string');
    }
    final contentSetDigestValue = params['contentSetDigest'];
    if (contentSetDigestValue is! String) {
      throw const FormatException('contentSetDigest must be a string');
    }
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    final current = service.contentSetIdentity;
    if (expectedRevision != current.revision) {
      throw StateError(
        'Experience content revision changed; describe it again',
      );
    }
    if (Digest(catalogDigestValue) != current.catalogDigest) {
      throw StateError('Experience content catalog changed; describe it again');
    }
    if (Digest(contentSetDigestValue) != current.contentSetDigest) {
      throw StateError('Experience content set changed; describe it again');
    }
    return service
        .openContentSet(
          resources: _rpc.resources,
          hostOrigin: _rpc.httpUri,
          studioOrigin: _rpc.studioOrigin,
        )
        .toJson();
  }

  Future<Object?> _refreshWorkspace(Map<String, Object?> _) async {
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    final previousRevision = service.snapshot.revision;
    final refresh = service.refreshContent(effectiveKitManifest);
    authoring?.contentAuthorityChanged();
    if (refresh.experienceChanged) {
      await _rpc.publishEvent(
        'experience.changed',
        service.describeExperience(),
      );
    }
    if (refresh.changed) {
      await _rpc.publishEvent(
        'experience.content.changed',
        service.describeContentSet().toJson(),
      );
    }
    final preview = _autoPreview;
    if (preview != null) {
      try {
        await preview.refreshProjection();
      } on Object {
        // The provider keeps the catalog visible and reports degradation.
      }
    } else if (preview == null && refresh.catalogChanged) {
      await _rpc.publishEvent('workspace.changed', service.describe());
    }
    return <String, Object?>{
      ...service.describe(),
      'changed': service.snapshot.revision != previousRevision,
    };
  }

  Object? _collectPreview(Map<String, Object?> params) =>
      (_autoPreview ?? (throw StateError('AutoPreview module is disabled')))
          .collect(params);

  Object? _previewStatus(Map<String, Object?> params) =>
      (_autoPreview ?? (throw StateError('AutoPreview module is disabled')))
          .status(params);

  Object? _cancelPreview(Map<String, Object?> params) =>
      (_autoPreview ?? (throw StateError('AutoPreview module is disabled')))
          .cancel(params);

  void _persistEffectiveKitManifest() {
    final file = File(effectiveKitManifestPath);
    file.parent.createSync(recursive: true);
    if (Link(file.path).existsSync()) {
      throw FileSystemException(
        'Effective Kit manifest cannot be a symlink',
        file.path,
      );
    }
    final staging = File('${file.path}.new-$pid');
    try {
      staging.writeAsStringSync(
        '${const JcsCanonicalizer().canonicalize(effectiveKitManifest.toJson())}\n',
        flush: true,
      );
      staging.renameSync(file.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }

  Object? _kitHealth(Map<String, Object?> _) {
    final manifest = effectiveKitManifest;
    final unhealthy = manifest.modules
        .where(
          (module) =>
              module.state == ModuleRuntimeState.failed ||
              module.health == ModuleHealth.unhealthy,
        )
        .length;
    final degraded = manifest.modules
        .where((module) => module.health == ModuleHealth.degraded)
        .length;
    return <String, Object?>{
      'schemaVersion': 1,
      'planDigest': manifest.resolvedPlanDigest.value,
      'manifestDigest': manifest.digest.value,
      'status': unhealthy > 0
          ? 'unhealthy'
          : degraded > 0
          ? 'degraded'
          : 'healthy',
      'unhealthyModules': unhealthy,
      'degradedModules': degraded,
    };
  }

  Future<Object?> _startSession(Map<String, Object?> params) async {
    final profileId = _requiredString(params, 'launchProfileId');
    final profile = profiles[profileId];
    if (profile == null) {
      throw FormatException('Unknown LaunchProfile $profileId');
    }
    final targetOrigin = Uri.parse(_requiredString(params, 'targetOrigin'));
    if (!_isLoopbackOrigin(targetOrigin)) {
      throw const FormatException('Target origin must be loopback');
    }
    final snapshot = coordinator.create(profile);
    try {
      await processes.start(snapshot.id, profile);
      await _waitForTargetOrigin(snapshot.id, targetOrigin);
      final target = ExecutionTarget(
        id: 'target-${snapshot.id}',
        platform: profile.platform,
        origin: targetOrigin,
        capabilities: <CapabilityDescriptor>[
          CapabilityDescriptor(
            id: 'workspace.simulated.locale',
            version: 1,
            operations: const <String>{'set', 'reset'},
          ),
          if (profile.platform == TargetPlatform.web)
            CapabilityDescriptor(
              id: 'capture.png',
              version: 1,
              operations: const <String>{'request', 'status'},
            ),
        ],
      );
      final ready = coordinator.markReady(snapshot.id, target);
      await _rpc.publishEvent('session.changed', ready.toJson());
      return ready.toJson();
    } on Object catch (error, stackTrace) {
      if (!coordinator.snapshot(snapshot.id).state.isTerminal) {
        coordinator.fail(snapshot.id, 'launch failed');
      }
      await processes.stop(snapshot.id);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _waitForTargetOrigin(String sessionId, Uri origin) async {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 1);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (coordinator.snapshot(sessionId).state.isTerminal) {
          throw StateError('Target process exited before readiness');
        }
        try {
          final request = await client.getUrl(origin);
          final response = await request.close().timeout(
            const Duration(seconds: 2),
          );
          await response.drain<void>();
          if (response.statusCode >= 200 && response.statusCode < 500) return;
        } on Object {
          // The managed target is still compiling or binding its loopback port.
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw TimeoutException('Target did not become ready at $origin');
    } finally {
      client.close(force: true);
    }
  }

  Object? _getSession(Map<String, Object?> params) =>
      coordinator.snapshot(_requiredString(params, 'sessionId')).toJson();

  Future<Object?> _resetSession(Map<String, Object?> params) async {
    final id = _requiredString(params, 'sessionId');
    captureBridge.discardSession(id);
    coordinator.requestReset(id);
    final ready = coordinator.completeReset(id);
    await _rpc.publishEvent('session.changed', ready.toJson());
    return ready.toJson();
  }

  Future<Object?> _stopSession(Map<String, Object?> params) async {
    final id = _requiredString(params, 'sessionId');
    coordinator.requestStop(id);
    await processes.stop(id);
    await gateways?.stopOwner(id);
    captureBridge.discardSession(id);
    final stopped = coordinator.completeStop(id);
    await _rpc.publishEvent('session.changed', stopped.toJson());
    return stopped.toJson();
  }

  Future<Object?> _cancelSession(Map<String, Object?> params) async {
    final id = _requiredString(params, 'sessionId');
    final cancelled = coordinator.cancel(
      id,
      params['reason'] is String ? params['reason']! as String : 'user',
    );
    await processes.stop(id);
    await gateways?.stopOwner(id);
    captureBridge.discardSession(id);
    await _rpc.publishEvent('session.changed', cancelled.toJson());
    return cancelled.toJson();
  }

  Object? _capture(Map<String, Object?> params) {
    final format = params['format'] is String
        ? params['format']! as String
        : 'png';
    if (format != 'png') {
      throw const FormatException('Only lossless PNG capture is supported');
    }
    final sessionId = _requiredString(params, 'sessionId');
    final target = coordinator.snapshot(sessionId).target;
    if (target == null ||
        !target.capabilities.any(
          (capability) => capability.id == 'capture.png',
        )) {
      throw StateError('Session target does not support lossless capture');
    }
    final request = coordinator.requestCapture(sessionId, format: format);
    return captureBridge
        .issue(
          requestId: request.id,
          sessionId: request.sessionId,
          targetOrigin: target.origin,
        )
        .toJson();
  }

  Object? _captureStatus(Map<String, Object?> params) => captureBridge
      .status(
        sessionId: _requiredString(params, 'sessionId'),
        requestId: _requiredString(params, 'requestId'),
      )
      .toJson();

  Future<Object?> _startGateway(Map<String, Object?> params) async {
    final supervisor = _requiredGateways();
    final ownerSessionId = _requiredString(params, 'ownerSessionId');
    final owner = coordinator.snapshot(ownerSessionId);
    if (owner.state != SessionState.ready) {
      throw StateError('Gateway owner Session must be ready');
    }
    final plan = _readPlan(params);
    final handle = await supervisor.start(
      ownerSessionId: ownerSessionId,
      targetOrigin: owner.target!.origin,
      plan: plan,
    );
    await _rpc.publishEvent('gateway.changed', <String, Object?>{
      ...handle.toJson(),
      'state': 'running',
    });
    return handle.toJson();
  }

  Object? _gatewayPresets(Map<String, Object?> params) {
    if (params.isNotEmpty) {
      throw const FormatException('gateway.presets accepts no params');
    }
    _requiredGateways();
    final loaded = const WorkspaceCatalogLoader().load(
      startPath: store.workspaceRoot,
    );
    final results = const WorkspaceGatewayPlanCompiler().compileAll(
      loaded,
      persist: true,
    );
    return <Object?>[
      for (final result in results)
        GatewayPlanArtifactDescriptor(
          presetId: result.compilation.plan.preset.id,
          description: result.compilation.plan.preset.description,
          backendMode: result.compilation.plan.backendMode,
          routeCount: result.compilation.plan.routes.length,
          planDigest: result.compilation.plan.digest,
          artifactDigest: result.planArtifactDigest!,
        ).toJson(),
    ];
  }

  Future<Object?> _gatewayStatus(Map<String, Object?> params) =>
      _gatewayCall(params, 'gateway.status');

  Future<Object?> _applyGateway(Map<String, Object?> params) async {
    final plan = _readPlan(params);
    return _gatewayCall(params, 'gateway.apply', <String, Object?>{
      'plan': plan.toJson(),
    });
  }

  Future<Object?> _verifyGateway(Map<String, Object?> params) async {
    final value =
        await _gatewayCall(params, 'gateway.verify', <String, Object?>{
          'method': _requiredString(params, 'method'),
          'path': _requiredString(params, 'path'),
          if (params['query'] != null) 'query': params['query'],
          if (params['bodyBase64'] != null) 'bodyBase64': params['bodyBase64'],
        });
    if (value is! Map<String, Object?>) {
      throw const FormatException('Gateway verify result must be an object');
    }
    final encodedBody = value['responseBodyBase64'];
    final response = value['response'];
    if (encodedBody is! String || response is! Map<String, Object?>) {
      throw const FormatException('Gateway verify result is incomplete');
    }
    final List<int> body;
    try {
      body = base64Decode(encodedBody);
    } on FormatException {
      throw const FormatException('Gateway verify returned invalid base64');
    }
    final declaredSize = response['bodySize'];
    final declaredDigest = response['bodyDigest'];
    if (declaredSize != body.length ||
        declaredDigest is! String ||
        Digest.bytes(body) != Digest(declaredDigest)) {
      throw const FormatException('Gateway verify body identity mismatch');
    }
    final artifactDigest = store.withExclusiveLock(() => store.putBlob(body));
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key != 'responseBodyBase64') entry.key: entry.value,
      'responseBodyArtifactDigest': artifactDigest.value,
    };
  }

  Future<Object?> _gatewayTraffic(Map<String, Object?> params) =>
      _gatewayCall(params, 'gateway.traffic', <String, Object?>{
        if (params['afterSequence'] != null)
          'afterSequence': params['afterSequence'],
        if (params['limit'] != null) 'limit': params['limit'],
      });

  Future<Object?> _resetGateway(Map<String, Object?> params) =>
      _gatewayCall(params, 'gateway.reset');

  Future<Object?> _stopGateway(Map<String, Object?> params) async {
    final supervisor = _requiredGateways();
    final id = _requiredString(params, 'gatewaySessionId');
    await supervisor.stop(id);
    await _rpc.publishEvent('gateway.changed', <String, Object?>{
      'id': id,
      'state': 'stopped',
    });
    return <String, Object?>{'id': id, 'state': 'stopped'};
  }

  Future<Object?> _gatewayCall(
    Map<String, Object?> params,
    String method, [
    Map<String, Object?> childParams = const <String, Object?>{},
  ]) => _requiredGateways().call(
    _requiredString(params, 'gatewaySessionId'),
    method,
    childParams,
  );

  GatewaySidecarSupervisor _requiredGateways() {
    final value = gateways;
    if (value == null) {
      throw StateError('Gateway sidecar capability is unavailable');
    }
    return value;
  }

  CompiledGatewayPlan _readPlan(Map<String, Object?> params) {
    final digest = Digest(_requiredString(params, 'planArtifactDigest'));
    final bytes = store.readBlob(digest);
    if (bytes == null) {
      throw StateError('CompiledGatewayPlan artifact is missing');
    }
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('CompiledGatewayPlan exceeds 1 MiB');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException(
        'CompiledGatewayPlan artifact is invalid JSON',
      );
    }
    final plan = CompiledGatewayPlan.fromJson(decoded);
    final canonical = utf8.encode(
      const JcsCanonicalizer().canonicalize(plan.toJson()),
    );
    if (!_sameBytes(bytes, canonical)) {
      throw const FormatException(
        'CompiledGatewayPlan artifact must be canonical JCS',
      );
    }
    return plan;
  }

  Future<void> _onProcessExit(
    String sessionId,
    int exitCode,
    String stdoutTail,
    String stderrTail,
  ) async {
    SessionSnapshot snapshot;
    try {
      snapshot = coordinator.snapshot(sessionId);
    } on StateError {
      return;
    }
    if (snapshot.state.isTerminal || snapshot.state == SessionState.stopping) {
      return;
    }
    await gateways?.stopOwner(sessionId);
    captureBridge.discardSession(sessionId);
    snapshot = coordinator.snapshot(sessionId);
    if (snapshot.state.isTerminal || snapshot.state == SessionState.stopping) {
      return;
    }
    final failed = coordinator.fail(sessionId, 'target exited with $exitCode');
    await _rpc.publishEvent('session.changed', <String, Object?>{
      ...failed.toJson(),
      'stdoutTail': stdoutTail,
      'stderrTail': stderrTail,
    });
  }

  String _requiredString(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  bool _isLoopbackOrigin(Uri origin) {
    if (origin.scheme != 'http' && origin.scheme != 'https') return false;
    if (origin.userInfo.isNotEmpty ||
        origin.query.isNotEmpty ||
        origin.fragment.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      return false;
    }
    if (origin.host == 'localhost') return true;
    final address = InternetAddress.tryParse(origin.host);
    return address?.isLoopback ?? false;
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

ArtifactClassification? _scenarioLabEvidenceClassification(
  ResolvedKitPlan plan,
) {
  final settings = plan.enabledModules
      .singleWhere((module) => module.moduleId.value == 'scenario.lab.local')
      .settings;
  if (settings.keys.any((key) => key != 'evidenceClassification')) {
    throw const FormatException('Invalid scenario.lab.local settings');
  }
  final raw = settings['evidenceClassification'];
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException(
      'scenario.lab.local evidenceClassification must be a string',
    );
  }
  try {
    return ArtifactClassification.values.byName(raw);
  } on ArgumentError {
    throw const FormatException(
      'scenario.lab.local evidenceClassification is unsupported',
    );
  }
}

String _hostPlatformId() => switch (Platform.operatingSystem) {
  'linux' => 'linux-x64',
  'macos' => 'macos-arm64',
  'windows' => 'windows-x64',
  final value => '$value-native',
};
