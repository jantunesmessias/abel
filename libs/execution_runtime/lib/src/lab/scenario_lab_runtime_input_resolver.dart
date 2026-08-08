import 'package:experience_contracts/experience_contracts.dart';

/// A deterministic, closed failure raised before any Scenario Lab effect.
final class ScenarioLabRuntimeInputResolutionException implements Exception {
  ScenarioLabRuntimeInputResolutionException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(List<String>.of(issues)..sort());

  final List<String> issues;

  @override
  String toString() => issues.join('\n');
}

/// Runtime inputs and their semantic pins resolved at the Host boundary.
///
/// [executionFingerprint] is a frozen copy of the supplied fingerprint. Its
/// input digests include the exact catalog binding, launch profile and, when
/// present, compiled Gateway plan and routing table used to create
/// [runtimeInputBinding].
final class ScenarioLabResolvedRuntimeInputs {
  const ScenarioLabResolvedRuntimeInputs._({
    required this.executionFingerprint,
    required this.runtimeInputBinding,
    required this.executionBindingDigest,
    required this.launchProfileDigest,
    this.compiledGatewayPlanDigest,
    this.routingTableDigest,
  });

  final ExecutionFingerprint executionFingerprint;
  final ScenarioLabRuntimeInputBinding runtimeInputBinding;
  final Digest executionBindingDigest;
  final Digest launchProfileDigest;
  final Digest? compiledGatewayPlanDigest;
  final Digest? routingTableDigest;
}

/// Resolves the immutable inputs of one Scenario Lab run without side effects.
///
/// The caller supplies only Host-owned models. In particular, an origin is not
/// accepted: target readiness and attachment remain separate effect boundaries.
final class ScenarioLabRuntimeInputResolver {
  const ScenarioLabRuntimeInputResolver();

  static const String executionBindingInputDigestKey =
      'workspace.scenario-lab.execution-binding.v1';
  static const String launchProfileInputDigestKey =
      'workspace.scenario-lab.launch-profile.v1';
  static const String compiledGatewayPlanInputDigestKey =
      'workspace.scenario-lab.compiled-gateway-plan.v1';
  static const String routingTableInputDigestKey =
      'workspace.scenario-lab.routing-table.v1';

  static const Set<String> _gatewayInputDigestKeys = <String>{
    compiledGatewayPlanInputDigestKey,
    routingTableInputDigestKey,
  };

  ScenarioLabResolvedRuntimeInputs resolve({
    required Digest expectedCatalogDigest,
    required ScenarioExecutionBinding executionBinding,
    required LaunchProfile launchProfile,
    required ExecutionFingerprint executionFingerprint,
    CompiledGatewayPlan? compiledGatewayPlan,
    RoutingTable? routingTable,
  }) {
    final issues = <String>[];
    final executionBindingDigest = Digest.semantic(executionBinding.toJson());
    final launchProfileDigest = Digest.semantic(launchProfile.toJson());

    final bindingLaunchProfileId = executionBinding.launchProfileId;
    if (bindingLaunchProfileId == null) {
      issues.add(
        'ScenarioExecutionBinding ${executionBinding.id} uses a checkpoint; '
        'this resolver requires a launch profile',
      );
    } else if (bindingLaunchProfileId != launchProfile.id) {
      issues.add(
        'ScenarioExecutionBinding launchProfileId $bindingLaunchProfileId '
        'does not match LaunchProfile ${launchProfile.id}',
      );
    }

    if (executionFingerprint.catalogDigest != expectedCatalogDigest) {
      issues.add('ExecutionFingerprint catalog digest does not match the run');
    }
    if (executionFingerprint.launchProfileId != launchProfile.id) {
      issues.add(
        'ExecutionFingerprint launchProfileId '
        '${executionFingerprint.launchProfileId} does not match LaunchProfile '
        '${launchProfile.id}',
      );
    }
    if (executionFingerprint.targetId != executionBinding.targetId) {
      issues.add(
        'ExecutionFingerprint targetId ${executionFingerprint.targetId} does '
        'not match ScenarioExecutionBinding targetId '
        '${executionBinding.targetId}',
      );
    }
    if (executionFingerprint.platform != launchProfile.platform.name) {
      issues.add(
        'ExecutionFingerprint platform ${executionFingerprint.platform} does '
        'not match LaunchProfile platform ${launchProfile.platform.name}',
      );
    }

    _validateExistingPin(
      executionFingerprint,
      executionBindingInputDigestKey,
      executionBindingDigest,
      issues,
    );
    _validateExistingPin(
      executionFingerprint,
      launchProfileInputDigestKey,
      launchProfileDigest,
      issues,
    );

    final gatewayPresetValue = executionBinding.gatewayPresetId;
    Digest? compiledGatewayPlanDigest;
    Digest? routingTableDigest;
    if (gatewayPresetValue == null) {
      if (compiledGatewayPlan != null || routingTable != null) {
        issues.add(
          'Gateway inputs are forbidden when the execution binding has no '
          'gatewayPresetId',
        );
      }
      if (executionFingerprint.backendMode != BackendMode.none) {
        issues.add(
          'ExecutionFingerprint backendMode must be none without a Gateway '
          'preset',
        );
      }
      if (executionFingerprint.networkContainment ==
          NetworkContainment.gatewayOnly) {
        issues.add(
          'ExecutionFingerprint cannot claim gatewayOnly containment without '
          'a Gateway preset',
        );
      }
      for (final key in _gatewayInputDigestKeys) {
        if (executionFingerprint.inputDigests.containsKey(key)) {
          issues.add('ExecutionFingerprint contains stale Gateway pin $key');
        }
      }
    } else {
      if (compiledGatewayPlan == null || routingTable == null) {
        issues.add(
          'CompiledGatewayPlan and RoutingTable are required together for '
          'Gateway preset $gatewayPresetValue',
        );
      } else {
        compiledGatewayPlanDigest = compiledGatewayPlan.digest;
        routingTableDigest = routingTable.digest;
        _validateGateway(
          gatewayPresetValue: gatewayPresetValue,
          plan: compiledGatewayPlan,
          routingTable: routingTable,
          fingerprint: executionFingerprint,
          issues: issues,
        );
        _validateExistingPin(
          executionFingerprint,
          compiledGatewayPlanInputDigestKey,
          compiledGatewayPlanDigest,
          issues,
        );
        _validateExistingPin(
          executionFingerprint,
          routingTableInputDigestKey,
          routingTableDigest,
          issues,
        );
      }
    }

    if (issues.isNotEmpty) {
      throw ScenarioLabRuntimeInputResolutionException(issues);
    }

    final pinnedInputDigests = <String, Digest>{
      ...executionFingerprint.inputDigests,
      executionBindingInputDigestKey: executionBindingDigest,
      launchProfileInputDigestKey: launchProfileDigest,
      compiledGatewayPlanInputDigestKey: ?compiledGatewayPlanDigest,
      routingTableInputDigestKey: ?routingTableDigest,
    };
    final pinnedFingerprint = ExecutionFingerprint(
      catalogDigest: executionFingerprint.catalogDigest,
      launchProfileId: executionFingerprint.launchProfileId,
      targetId: executionFingerprint.targetId,
      platform: executionFingerprint.platform,
      renderer: executionFingerprint.renderer,
      runtimeFidelity: executionFingerprint.runtimeFidelity,
      backendMode: executionFingerprint.backendMode,
      networkContainment: executionFingerprint.networkContainment,
      bootstrapAssessment: executionFingerprint.bootstrapAssessment,
      toolchain: executionFingerprint.toolchain,
      capabilities: executionFingerprint.capabilities,
      inputDigests: pinnedInputDigests,
      policies: executionFingerprint.policies,
      sourceRevision: executionFingerprint.sourceRevision,
    );
    final gatewayPresetId = gatewayPresetValue == null
        ? null
        : GatewayPresetId(gatewayPresetValue);
    final runtimeInputBinding = ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest: pinnedFingerprint.digest,
      executionTargetId: executionBinding.targetId,
      gatewayPresetId: gatewayPresetId,
      compiledGatewayPlanDigest: compiledGatewayPlanDigest,
      routingTableDigest: routingTableDigest,
    );
    runtimeInputBinding.validateAgainst(executionBinding);

    return ScenarioLabResolvedRuntimeInputs._(
      executionFingerprint: pinnedFingerprint,
      runtimeInputBinding: runtimeInputBinding,
      executionBindingDigest: executionBindingDigest,
      launchProfileDigest: launchProfileDigest,
      compiledGatewayPlanDigest: compiledGatewayPlanDigest,
      routingTableDigest: routingTableDigest,
    );
  }

  static void _validateExistingPin(
    ExecutionFingerprint fingerprint,
    String key,
    Digest expected,
    List<String> issues,
  ) {
    final existing = fingerprint.inputDigests[key];
    if (existing != null && existing != expected) {
      issues.add('ExecutionFingerprint pin $key conflicts with resolved input');
    }
  }

  static void _validateGateway({
    required String gatewayPresetValue,
    required CompiledGatewayPlan plan,
    required RoutingTable routingTable,
    required ExecutionFingerprint fingerprint,
    required List<String> issues,
  }) {
    if (plan.preset.id.value != gatewayPresetValue) {
      issues.add(
        'CompiledGatewayPlan preset ${plan.preset.id} does not match '
        'ScenarioExecutionBinding gatewayPresetId $gatewayPresetValue',
      );
    }
    if (routingTable.presetId != plan.preset.id) {
      issues.add('RoutingTable preset does not match CompiledGatewayPlan');
    }
    if (routingTable.scopeId != plan.scope.id) {
      issues.add('RoutingTable scope does not match CompiledGatewayPlan');
    }
    if (plan.backendMode == BackendMode.none) {
      issues.add('CompiledGatewayPlan backendMode cannot be none');
    }
    if (fingerprint.backendMode != plan.backendMode) {
      issues.add(
        'ExecutionFingerprint backendMode does not match '
        'CompiledGatewayPlan',
      );
    }
    if (fingerprint.networkContainment != plan.networkContainment) {
      issues.add(
        'ExecutionFingerprint networkContainment does not match '
        'CompiledGatewayPlan',
      );
    }

    final routeIds = plan.routes.map((route) => route.id).toSet();
    final routingIds = routingTable.entries.keys.toSet();
    if (routeIds.length != routingIds.length ||
        !routeIds.containsAll(routingIds)) {
      issues.add('RoutingTable entries must equal compiled Gateway routes');
      return;
    }
    for (final route in plan.routes) {
      final expectedDecision =
          plan.backendMode == BackendMode.hybrid &&
              route.policy == GatewayRoutePolicy.upstreamOnly
          ? GatewayRoutingDecision.passthrough
          : GatewayRoutingDecision.mock;
      if (routingTable.entries[route.id] != expectedDecision) {
        issues.add(
          'RoutingTable decision for ${route.id} does not match the compiled '
          'Gateway policy',
        );
      }
    }
  }
}
