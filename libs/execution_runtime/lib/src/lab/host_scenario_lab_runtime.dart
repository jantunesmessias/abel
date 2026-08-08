import 'dart:async';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../evidence/local_evidence_repository.dart';
import '../gateway/gateway_sidecar_supervisor.dart';
import '../gateway/workspace_gateway_plan_compiler.dart';
import '../host/app_adapter_capture_bridge.dart';
import '../host/host_workspace_service.dart';
import '../secure_id_generator.dart';
import '../storage/filesystem_workspace_store.dart';
import '../workspace/workspace_catalog_loader.dart';
import 'filesystem_scenario_lab_run_store.dart';
import 'filesystem_scenario_quality_decision_store.dart';
import 'host_scenario_lab_service.dart';
import 'host_scenario_quality_service.dart';
import 'managed_process_scenario_lab_target.dart';
import 'scenario_lab_app_adapter_evidence_port.dart';
import 'scenario_lab_evidence_comparison_port.dart';
import 'scenario_lab_execution_ports.dart';
import 'scenario_lab_execution_service.dart';
import 'scenario_lab_host_comparison_artifact_resolver.dart';
import 'scenario_lab_relay_broker.dart';
import 'scenario_lab_runtime_input_resolver.dart';

/// Production composition of the durable local Scenario Lab boundary.
final class HostScenarioLabRuntime {
  factory HostScenarioLabRuntime({
    required String workspaceRoot,
    required FileSystemWorkspaceStore workspaceStore,
    required HostWorkspaceService workspace,
    required Map<String, LaunchProfile> launchProfiles,
    required Clock clock,
    GatewaySidecarSupervisor? gatewaySupervisor,
    AppAdapterCaptureBridge? captureBridge,
    ArtifactClassification? evidenceClassification,
    bool qualityDecisionsEnabled = false,
    HostScenarioQualityDecisionAuthority? qualityDecisionAuthority,
    IdGenerator? ids,
  }) {
    if ((captureBridge == null) != (evidenceClassification == null)) {
      throw ArgumentError(
        'Scenario Lab capture bridge and classification are required together',
      );
    }
    if (!qualityDecisionsEnabled && qualityDecisionAuthority != null) {
      throw ArgumentError(
        'Scenario Quality authority requires quality.decisions.local',
      );
    }
    final resolvedRoot = Directory(workspaceRoot).resolveSymbolicLinksSync();
    if (resolvedRoot != workspaceStore.workspaceRoot) {
      throw ArgumentError('Scenario Lab workspace roots do not match');
    }
    if (captureBridge != null &&
        (captureBridge.store.workspaceRoot != workspaceStore.workspaceRoot ||
            captureBridge.store.stateRoot != workspaceStore.stateRoot)) {
      throw ArgumentError(
        'Scenario Lab capture bridge belongs to another workspace',
      );
    }
    final secureIds = ids ?? SecureIdGenerator();
    final broker = ScenarioLabRelayBroker();
    final runStore = FilesystemScenarioLabRunStore(
      rootPath: p.join(workspaceStore.stateRoot, 'scenario-lab', 'runs'),
    );
    final launcher = ManagedProcessScenarioLabLauncher(
      workspaceRoot: resolvedRoot,
    );
    final target = ManagedProcessScenarioLabTargetPort(
      launcher: launcher,
      broker: broker,
      gateway: gatewaySupervisor == null
          ? null
          : GatewaySidecarScenarioLabGatewayLifecyclePort(gatewaySupervisor),
      ids: secureIds,
      resolveConfiguration: (runId, binding) => _resolveConfiguration(
        workspaceRoot: resolvedRoot,
        workspace: workspace,
        launchProfiles: launchProfiles,
        binding: binding,
      ),
    );
    final evidenceRepository = captureBridge == null && !qualityDecisionsEnabled
        ? null
        : LocalEvidenceRepository(
            store: workspaceStore,
            clock: clock,
            ids: secureIds,
          );
    final evidence = captureBridge == null
        ? null
        : ScenarioLabAppAdapterEvidencePort(
            captureBridge: captureBridge,
            evidenceRepository: evidenceRepository!,
            ids: secureIds,
            resolveContext: (runId, _, runtimeInputs) =>
                resolveHostScenarioLabEvidenceContext(
                  launchContext: target.launchContext(runId),
                  runtimeInputs: runtimeInputs,
                  classification: evidenceClassification!,
                ),
          );
    final comparison = captureBridge == null
        ? null
        : ScenarioLabEvidenceComparisonPort(
            resolveArtifact: ScenarioLabHostComparisonArtifactResolver(
              store: workspaceStore,
              runStore: runStore,
              evidenceRepository: evidenceRepository!,
            ).resolve,
          );
    final execution = ScenarioLabExecutionService(
      store: runStore,
      clock: clock,
      identities: _HostScenarioLabIdentities(secureIds),
      target: target,
      deadlines: const _HostScenarioLabDeadlines(),
      evidence: evidence,
      comparison: comparison,
    );
    HostScenarioLabContent readContent() {
      final manifest = workspace.scenarioLabManifest;
      if (manifest == null) {
        throw StateError('Scenario Lab manifest is absent');
      }
      return HostScenarioLabContent(
        identity: workspace.contentSetIdentity,
        catalog: workspace.snapshot.catalog,
        manifest: manifest,
      );
    }

    final host = HostScenarioLabService(
      execution: execution,
      readContent: readContent,
      relay: broker,
      readResolvedRuntimeInputs: target.resolvedRuntimeInputs,
      readManagedLaunchContext: target.launchContext,
    );
    final quality = !qualityDecisionsEnabled
        ? null
        : HostScenarioQualityService(
            workspaceStore: workspaceStore,
            runStore: runStore,
            decisionStore: FilesystemScenarioQualityDecisionStore(
              workspaceStore: workspaceStore,
            ),
            evidenceRepository: evidenceRepository!,
            readContent: readContent,
            clock: clock,
            ids: secureIds,
            authority: qualityDecisionAuthority,
          );
    return HostScenarioLabRuntime._(
      host: host,
      target: target,
      runStore: runStore,
      evidence: evidence,
      comparison: comparison,
      quality: quality,
    );
  }

  HostScenarioLabRuntime._({
    required this.host,
    required this.target,
    required this.runStore,
    required this.evidence,
    required this.comparison,
    required this.quality,
  });

  final HostScenarioLabService host;
  final ManagedProcessScenarioLabTargetPort target;
  final FilesystemScenarioLabRunStore runStore;
  final ScenarioLabAppAdapterEvidencePort? evidence;
  final ScenarioLabEvidenceComparisonPort? comparison;
  final HostScenarioQualityService? quality;
  Future<void>? _closing;
  var _closed = false;

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
    Object? firstFailure;
    StackTrace? firstFailureStackTrace;
    void preserveFailure(Object error, StackTrace stackTrace) {
      firstFailure ??= error;
      firstFailureStackTrace ??= stackTrace;
    }

    try {
      quality?.close();
    } on Object catch (error, stackTrace) {
      preserveFailure(error, stackTrace);
    }
    Object? executionFailure;
    StackTrace? executionFailureStackTrace;
    try {
      await host.execution.close();
    } on Object catch (error, stackTrace) {
      executionFailure = error;
      executionFailureStackTrace = stackTrace;
      preserveFailure(error, stackTrace);
    }
    if (host.execution.activeRunCount != 0) {
      final failure = executionFailure;
      if (failure != null) {
        Error.throwWithStackTrace(failure, executionFailureStackTrace!);
      }
      throw StateError(
        'Scenario Lab runtime shutdown retained active executions',
      );
    }
    try {
      host.close();
    } on Object catch (error, stackTrace) {
      preserveFailure(error, stackTrace);
    }
    try {
      await target.close();
    } on Object catch (error, stackTrace) {
      preserveFailure(error, stackTrace);
    }
    if (firstFailure case final failure?) {
      Error.throwWithStackTrace(failure, firstFailureStackTrace!);
    }
  }
}

/// Resolves capture authority exclusively from the currently owned target.
///
/// This stays outside the public wire: neither origin, fingerprint nor
/// classification is accepted from a Studio or App Adapter request.
ScenarioLabAppAdapterEvidenceContext resolveHostScenarioLabEvidenceContext({
  required ScenarioLabManagedLaunchContext? launchContext,
  required ScenarioLabRuntimeInputBinding runtimeInputs,
  required ArtifactClassification classification,
}) {
  final context = launchContext;
  if (context == null ||
      context.executionFingerprint.digest !=
          runtimeInputs.executionFingerprintDigest ||
      context.executionFingerprint.targetId !=
          runtimeInputs.executionTargetId) {
    throw const ScenarioLabEvidenceInvalidInput();
  }
  return ScenarioLabAppAdapterEvidenceContext(
    targetOrigin: context.targetOrigin,
    executionFingerprint: context.executionFingerprint,
    classification: classification,
  );
}

ScenarioLabManagedTargetConfiguration _resolveConfiguration({
  required String workspaceRoot,
  required HostWorkspaceService workspace,
  required Map<String, LaunchProfile> launchProfiles,
  required ScenarioExecutionBinding binding,
}) {
  final profileId = binding.launchProfileId;
  if (profileId == null) {
    throw UnsupportedError(
      'Local Scenario Lab execution does not support checkpoints',
    );
  }
  final profile = launchProfiles[profileId];
  if (profile == null) {
    throw StateError('Scenario Lab LaunchProfile $profileId is unavailable');
  }
  final identity = workspace.contentSetIdentity;
  final catalog = workspace.snapshot.catalog;
  final manifest = workspace.scenarioLabManifest;
  if (manifest == null ||
      identity.catalogDigest != catalog.digest ||
      identity.scenarioLabManifestDigest != manifest.digest) {
    throw StateError('Scenario Lab content generation changed');
  }

  GatewayCompilation? gateway;
  Digest? gatewayPlanArtifactDigest;
  if (binding.gatewayPresetId != null) {
    final loaded = const WorkspaceCatalogLoader().load(
      startPath: workspaceRoot,
    );
    final loadedCatalog = const CatalogCompiler().compile(
      loaded.documents,
      layout: loaded.layout,
    );
    if (loadedCatalog.digest != catalog.digest) {
      throw StateError(
        'Workspace source changed before Scenario Lab runtime resolution',
      );
    }
    final persisted = const WorkspaceGatewayPlanCompiler().compilePreset(
      loaded,
      presetId: binding.gatewayPresetId!,
      persist: true,
    );
    gateway = persisted.compilation;
    gatewayPlanArtifactDigest = persisted.planArtifactDigest;
    if (gatewayPlanArtifactDigest == null) {
      throw StateError('Scenario Lab Gateway plan was not persisted');
    }
  }

  final fingerprint = ExecutionFingerprint(
    catalogDigest: catalog.digest,
    launchProfileId: profile.id,
    targetId: binding.targetId,
    platform: profile.platform.name,
    renderer: switch (profile.platform) {
      TargetPlatform.web => 'flutter-web',
      TargetPlatform.androidEmulator => 'flutter-android',
    },
    runtimeFidelity: RuntimeFidelity.simulated,
    backendMode: gateway?.plan.backendMode ?? BackendMode.none,
    networkContainment:
        gateway?.plan.networkContainment ?? NetworkContainment.unconstrained,
    bootstrapAssessment: BootstrapAssessment.declared,
    toolchain: <String, String>{
      'dart': Platform.version.split(RegExp(r'\s+')).first,
    },
    capabilities: const <String>{'app-adapter.relay'},
    inputDigests: <String, Digest>{
      'workspace.scenario-lab.content-set': identity.contentSetDigest,
      'workspace.scenario-lab.manifest.v1': manifest.digest,
      'gateway.plan-artifact.v1': ?gatewayPlanArtifactDigest,
    },
    policies: const <String, String>{
      'runtime-input-resolution': 'host-local-v1',
    },
  );
  final resolved = const ScenarioLabRuntimeInputResolver().resolve(
    expectedCatalogDigest: catalog.digest,
    executionBinding: binding,
    launchProfile: profile,
    executionFingerprint: fingerprint,
    compiledGatewayPlan: gateway?.plan,
    routingTable: gateway?.routingTable,
  );
  return ScenarioLabManagedTargetConfiguration(
    launchProfile: profile,
    executionFingerprint: resolved.executionFingerprint,
    runtimeInputs: resolved.runtimeInputBinding,
    gatewayPlan: gateway?.plan,
  );
}

final class _HostScenarioLabIdentities
    implements ScenarioLabExecutionIdentityPort {
  _HostScenarioLabIdentities(this.ids);

  final IdGenerator ids;

  @override
  ScenarioLabRunId nextRunId() => ScenarioLabRunId(_opaque('run'));

  @override
  ScenarioLabCommandId nextCommandId() =>
      ScenarioLabCommandId(_opaque('command'));

  @override
  AppAdapterRelayNonce nextRelayNonce() => AppAdapterRelayNonce(ids.nextId());

  String _opaque(String prefix) {
    final digest = Digest.semantic(ids.nextId()).value;
    return '$prefix-${digest.substring('sha256:'.length, 39)}';
  }
}

final class _HostScenarioLabDeadlines implements ScenarioLabDeadlinePort {
  const _HostScenarioLabDeadlines();

  @override
  Future<T> run<T>({
    required Duration timeout,
    required Future<T> Function() action,
  }) => action().timeout(
    timeout,
    onTimeout: () => throw const ScenarioLabDeadlineExceeded(),
  );
}
