import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:path/path.dart' as p;

import '../composition/builtin_module_catalog.dart';
import '../composition/module_lifecycle.dart';
import '../gateway/gateway_sidecar_supervisor.dart';
import '../gateway/workspace_gateway_plan_compiler.dart';
import '../process/managed_process_supervisor.dart';
import '../secure_id_generator.dart';
import '../storage/filesystem_workspace_store.dart';
import '../system_clock.dart';
import '../workspace/workspace_catalog_loader.dart';
import 'app_adapter_capture_bridge.dart';
import 'host_auto_preview_service.dart';
import 'host_module_kernel.dart';
import 'host_resource_registry.dart';
import 'host_rpc_server.dart';
import 'host_workspace_service.dart';

final class DevExHostApplication {
  factory DevExHostApplication({
    required Uri studioOrigin,
    required String sessionToken,
    required String workspaceRoot,
    required List<LaunchProfile> launchProfiles,
    String? gatewaySidecarCommand,
    List<String> gatewaySidecarArguments = const <String>[],
    String? gatewaySidecarWorkingDirectory,
    CatalogManifest? workspaceCatalog,
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
    return DevExHostApplication.fromResolvedPlan(
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
      rpcPort: rpcPort,
      exposeStudioBootstrap: exposeStudioBootstrap,
    );
  }

  factory DevExHostApplication.fromResolvedPlan({
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
    int rpcPort = 0,
    bool exposeStudioBootstrap = false,
  }) {
    bool enabled(String moduleId) =>
        plan.enabledModules.any((module) => module.moduleId.value == moduleId);
    final sessionsEnabled = enabled('sessions.local');
    final captureEnabled = enabled('capture.app-adapter');
    final autoPreviewEnabled = enabled('evidence.auto-preview');
    final gatewayEnabled = enabled('gateway.interceptor');
    final catalogEnabled = enabled('catalog');
    final studioEnabled = enabled('studio.shell');
    if (gatewayEnabled && gatewaySidecarCommand == null) {
      throw ArgumentError(
        'gateway.interceptor requires a packaged sidecar command',
      );
    }
    final ids = SecureIdGenerator();
    final clock = SystemClock();
    final coordinator = SessionCoordinator(clock: clock, ids: ids);
    late final DevExHostApplication application;
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
    CatalogManifest loadWorkspaceCatalog() {
      final loaded = const WorkspaceCatalogLoader().load(
        startPath: workspaceRoot,
      );
      return const CatalogCompiler().compile(
        loaded.documents,
        layout: loaded.layout,
      );
    }

    final workspace = !catalogEnabled
        ? null
        : HostWorkspaceService(
            initialCatalog: workspaceCatalog ?? loadWorkspaceCatalog(),
            clock: clock,
            providerBindings: plan.providerBindings,
            reloadCatalog: workspaceCatalog == null
                ? loadWorkspaceCatalog
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
    final contributions = <ModuleId, ModuleContribution>{
      if (catalogEnabled)
        ModuleId('catalog'): ModuleContribution(
          rpcMethods: const <String>[
            'devex.workspace.describe',
            'devex.workspace.open',
            'devex.workspace.refresh',
          ],
        ),
      if (sessionsEnabled)
        ModuleId('sessions.local'): ModuleContribution(
          rpcMethods: const <String>[
            'devex.session.cancel',
            'devex.session.get',
            'devex.session.reset',
            'devex.session.start',
            'devex.session.stop',
          ],
          studioContributions: studioEnabled
              ? const <String>['studio.target']
              : const <String>[],
        ),
      if (captureEnabled)
        ModuleId('capture.app-adapter'): ModuleContribution(
          rpcMethods: const <String>[
            'devex.capture.request',
            'devex.capture.status',
          ],
        ),
      if (autoPreviewEnabled)
        ModuleId('evidence.auto-preview'): ModuleContribution(
          rpcMethods: const <String>[
            'devex.preview.collect',
            'devex.preview.status',
            'devex.preview.cancel',
          ],
        ),
      if (gatewayEnabled)
        ModuleId('gateway.interceptor'): ModuleContribution(
          rpcMethods: const <String>[
            'devex.gateway.apply',
            'devex.gateway.presets',
            'devex.gateway.reset',
            'devex.gateway.start',
            'devex.gateway.status',
            'devex.gateway.stop',
            'devex.gateway.traffic',
            'devex.gateway.verify',
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
    application = DevExHostApplication._(
      coordinator: coordinator,
      processes: processes,
      profiles: profiles,
      gateways: gateways,
      store: store,
      captureBridge: captureBridge,
      kernel: kernel,
      captureEnabled: captureEnabled,
      workspace: workspace,
    );
    methods.addAll(<String, HostRpcMethodHandler>{
      'devex.kit.describe': application._describeKit,
      'devex.kit.health': application._kitHealth,
    });
    if (catalogEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'devex.workspace.describe': application._describeWorkspace,
        'devex.workspace.open': application._openWorkspace,
        'devex.workspace.refresh': application._refreshWorkspace,
      });
    }
    if (sessionsEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'devex.session.start': application._startSession,
        'devex.session.get': application._getSession,
        'devex.session.reset': application._resetSession,
        'devex.session.stop': application._stopSession,
        'devex.session.cancel': application._cancelSession,
      });
    }
    if (captureEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'devex.capture.request': application._capture,
        'devex.capture.status': application._captureStatus,
      });
    }
    if (autoPreviewEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'devex.preview.collect': application._collectPreview,
        'devex.preview.status': application._previewStatus,
        'devex.preview.cancel': application._cancelPreview,
      });
    }
    if (gatewayEnabled) {
      methods.addAll(<String, HostRpcMethodHandler>{
        'devex.gateway.start': application._startGateway,
        'devex.gateway.presets': application._gatewayPresets,
        'devex.gateway.status': application._gatewayStatus,
        'devex.gateway.apply': application._applyGateway,
        'devex.gateway.verify': application._verifyGateway,
        'devex.gateway.traffic': application._gatewayTraffic,
        'devex.gateway.reset': application._resetGateway,
        'devex.gateway.stop': application._stopGateway,
      });
    }
    // HostRpcServer copies the map, so construct the final server after methods.
    final finalRpc = HostRpcServer(
      studioOrigin: studioOrigin,
      sessionToken: sessionToken,
      port: rpcPort,
      resourceRegistry: HostResourceRegistry(clock: clock, ids: ids),
      applicationMethods: methods,
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

  DevExHostApplication._({
    required this.coordinator,
    required this.processes,
    required this.profiles,
    required this.gateways,
    required this.store,
    required this.captureBridge,
    required this.kernel,
    required this.captureEnabled,
    required this.workspace,
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
  late final HostRpcServer _rpc;
  HostAutoPreviewService? _autoPreview;
  StreamSubscription<AppAdapterCaptureReceipt>? _captureSubscription;

  HostRpcServer get rpc => _rpc;
  EffectiveKitManifest get effectiveKitManifest => kernel.manifest;
  String get effectiveKitManifestPath =>
      p.join(store.workspaceRoot, '.dart_tool', 'devex', 'effective-kit.json');

  Future<void> start() async {
    await kernel.start();
    try {
      workspace?.initialize(effectiveKitManifest);
      if (captureEnabled) {
        await captureBridge.start();
        _captureSubscription = captureBridge.completions.listen(
          (receipt) => unawaited(
            _rpc.publishEvent('devex.capture.completed', receipt.toJson()),
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
      await kernel.stop();
      rethrow;
    }
  }

  Future<void> close() async {
    await _autoPreview?.close();
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
    await kernel.stop();
  }

  Object? _describeKit(Map<String, Object?> _) => effectiveKitManifest.toJson();

  Future<Object?> _describeWorkspace(Map<String, Object?> _) async {
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    await _autoPreview?.renewArtifactHandles();
    return service.describe();
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

  Future<Object?> _refreshWorkspace(Map<String, Object?> _) async {
    final service =
        workspace ?? (throw StateError('Workspace module is disabled'));
    final previousRevision = service.snapshot.revision;
    final catalogChanged = service.refresh(effectiveKitManifest);
    final preview = _autoPreview;
    if (preview != null) {
      try {
        // Preview inputs include source, assets and toolchain state outside the
        // catalog documents. Refresh them even when CatalogManifest is stable.
        await preview.refreshProjection();
      } on Object {
        // The provider keeps the catalog visible and reports degradation.
      }
    } else if (catalogChanged) {
      await _rpc.publishEvent('devex.workspace.changed', service.describe());
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
            id: 'devex.simulated.locale',
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
      await _rpc.publishEvent('devex.session.changed', ready.toJson());
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
    await _rpc.publishEvent('devex.session.changed', ready.toJson());
    return ready.toJson();
  }

  Future<Object?> _stopSession(Map<String, Object?> params) async {
    final id = _requiredString(params, 'sessionId');
    coordinator.requestStop(id);
    await processes.stop(id);
    await gateways?.stopOwner(id);
    captureBridge.discardSession(id);
    final stopped = coordinator.completeStop(id);
    await _rpc.publishEvent('devex.session.changed', stopped.toJson());
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
    await _rpc.publishEvent('devex.session.changed', cancelled.toJson());
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
    await _rpc.publishEvent('devex.gateway.changed', <String, Object?>{
      ...handle.toJson(),
      'state': 'running',
    });
    return handle.toJson();
  }

  Object? _gatewayPresets(Map<String, Object?> params) {
    if (params.isNotEmpty) {
      throw const FormatException('devex.gateway.presets accepts no params');
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
      _gatewayCall(params, 'devex.gateway.status');

  Future<Object?> _applyGateway(Map<String, Object?> params) async {
    final plan = _readPlan(params);
    return _gatewayCall(params, 'devex.gateway.apply', <String, Object?>{
      'plan': plan.toJson(),
    });
  }

  Future<Object?> _verifyGateway(Map<String, Object?> params) async {
    final value =
        await _gatewayCall(params, 'devex.gateway.verify', <String, Object?>{
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
      _gatewayCall(params, 'devex.gateway.traffic', <String, Object?>{
        if (params['afterSequence'] != null)
          'afterSequence': params['afterSequence'],
        if (params['limit'] != null) 'limit': params['limit'],
      });

  Future<Object?> _resetGateway(Map<String, Object?> params) =>
      _gatewayCall(params, 'devex.gateway.reset');

  Future<Object?> _stopGateway(Map<String, Object?> params) async {
    final supervisor = _requiredGateways();
    final id = _requiredString(params, 'gatewaySessionId');
    await supervisor.stop(id);
    await _rpc.publishEvent('devex.gateway.changed', <String, Object?>{
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
    await _rpc.publishEvent('devex.session.changed', <String, Object?>{
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

String _hostPlatformId() => switch (Platform.operatingSystem) {
  'linux' => 'linux-x64',
  'macos' => 'macos-arm64',
  'windows' => 'windows-x64',
  final value => '$value-native',
};
