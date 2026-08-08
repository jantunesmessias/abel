import 'dart:convert';

import 'package:execution_runtime/src/lab/scenario_lab_runtime_input_resolver.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const resolver = ScenarioLabRuntimeInputResolver();
  final catalogDigest = Digest.semantic('catalog');

  test(
    'pins launch inputs without accepting target origin or Gateway data',
    () {
      final binding = _binding();
      final profile = _profile();
      final consumerPin = Digest.semantic('consumer-input');
      final fingerprint = _fingerprint(
        catalogDigest: catalogDigest,
        inputDigests: <String, Digest>{'consumer.input': consumerPin},
      );

      final resolved = resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: binding,
        launchProfile: profile,
        executionFingerprint: fingerprint,
      );

      expect(
        resolved.executionBindingDigest,
        Digest.semantic(binding.toJson()),
      );
      expect(resolved.launchProfileDigest, Digest.semantic(profile.toJson()));
      expect(resolved.compiledGatewayPlanDigest, isNull);
      expect(resolved.routingTableDigest, isNull);
      expect(
        resolved.executionFingerprint.inputDigests,
        containsPair('consumer.input', consumerPin),
      );
      expect(
        resolved
            .executionFingerprint
            .inputDigests[ScenarioLabRuntimeInputResolver
            .executionBindingInputDigestKey],
        resolved.executionBindingDigest,
      );
      expect(
        resolved
            .executionFingerprint
            .inputDigests[ScenarioLabRuntimeInputResolver
            .launchProfileInputDigestKey],
        resolved.launchProfileDigest,
      );
      expect(
        resolved.runtimeInputBinding.executionFingerprintDigest,
        resolved.executionFingerprint.digest,
      );
      expect(resolved.runtimeInputBinding.executionTargetId, binding.targetId);
      expect(resolved.runtimeInputBinding.gatewayPresetId, isNull);
      expect(
        fingerprint.inputDigests,
        equals(<String, Digest>{'consumer.input': consumerPin}),
        reason: 'resolution must not mutate the caller fingerprint',
      );
    },
  );

  test(
    'pins compiled Gateway plan and exact routing table used by the run',
    () {
      final gateway = _gatewayCompilation();
      final binding = _binding(gatewayPresetId: gateway.plan.preset.id.value);

      final resolved = resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: binding,
        launchProfile: _profile(),
        executionFingerprint: _fingerprint(
          catalogDigest: catalogDigest,
          backendMode: gateway.plan.backendMode,
          networkContainment: gateway.plan.networkContainment,
        ),
        compiledGatewayPlan: gateway.plan,
        routingTable: gateway.routingTable,
      );

      expect(resolved.compiledGatewayPlanDigest, gateway.plan.digest);
      expect(resolved.routingTableDigest, gateway.routingTable.digest);
      expect(
        resolved.runtimeInputBinding.gatewayPresetId,
        gateway.plan.preset.id,
      );
      expect(
        resolved.runtimeInputBinding.compiledGatewayPlanDigest,
        gateway.plan.digest,
      );
      expect(
        resolved.runtimeInputBinding.routingTableDigest,
        gateway.routingTable.digest,
      );
      expect(
        resolved
            .executionFingerprint
            .inputDigests[ScenarioLabRuntimeInputResolver
            .compiledGatewayPlanInputDigestKey],
        gateway.plan.digest,
      );
      expect(
        resolved
            .executionFingerprint
            .inputDigests[ScenarioLabRuntimeInputResolver
            .routingTableInputDigestKey],
        gateway.routingTable.digest,
      );
      expect(
        () => resolved.runtimeInputBinding.validateAgainst(binding),
        returnsNormally,
      );
    },
  );

  test('is deterministic and accepts only identical pre-existing pins', () {
    final gatewayA = _gatewayCompilation(reverseInputs: false);
    final gatewayB = _gatewayCompilation(reverseInputs: true);
    final binding = _binding(gatewayPresetId: gatewayA.plan.preset.id.value);
    final firstFingerprint = _fingerprint(
      catalogDigest: catalogDigest,
      backendMode: gatewayA.plan.backendMode,
      networkContainment: gatewayA.plan.networkContainment,
      toolchain: <String, String>{'flutter': '3.44.8', 'dart': '3.12.2'},
      capabilities: <String>{'write', 'read'},
      inputDigests: <String, Digest>{
        'z.input': Digest.semantic('z'),
        'a.input': Digest.semantic('a'),
      },
      policies: <String, String>{'z.policy': '2', 'a.policy': '1'},
    );
    final secondFingerprint = _fingerprint(
      catalogDigest: catalogDigest,
      backendMode: gatewayB.plan.backendMode,
      networkContainment: gatewayB.plan.networkContainment,
      toolchain: <String, String>{'dart': '3.12.2', 'flutter': '3.44.8'},
      capabilities: <String>{'read', 'write'},
      inputDigests: <String, Digest>{
        'a.input': Digest.semantic('a'),
        'z.input': Digest.semantic('z'),
      },
      policies: <String, String>{'a.policy': '1', 'z.policy': '2'},
    );

    final first = resolver.resolve(
      expectedCatalogDigest: catalogDigest,
      executionBinding: binding,
      launchProfile: _profile(),
      executionFingerprint: firstFingerprint,
      compiledGatewayPlan: gatewayA.plan,
      routingTable: gatewayA.routingTable,
    );
    final second = resolver.resolve(
      expectedCatalogDigest: catalogDigest,
      executionBinding: binding,
      launchProfile: _profile(),
      executionFingerprint: secondFingerprint,
      compiledGatewayPlan: gatewayB.plan,
      routingTable: gatewayB.routingTable,
    );
    final repeated = resolver.resolve(
      expectedCatalogDigest: catalogDigest,
      executionBinding: binding,
      launchProfile: _profile(),
      executionFingerprint: first.executionFingerprint,
      compiledGatewayPlan: gatewayA.plan,
      routingTable: gatewayA.routingTable,
    );

    expect(gatewayA.plan.digest, gatewayB.plan.digest);
    expect(gatewayA.routingTable.digest, gatewayB.routingTable.digest);
    expect(
      first.executionFingerprint.digest,
      second.executionFingerprint.digest,
    );
    expect(first.runtimeInputBinding.digest, second.runtimeInputBinding.digest);
    expect(
      repeated.executionFingerprint.digest,
      first.executionFingerprint.digest,
    );
    expect(
      repeated.runtimeInputBinding.digest,
      first.runtimeInputBinding.digest,
    );
  });

  test('fails closed for target, profile, platform and catalog mismatch', () {
    final fingerprint = _fingerprint(
      catalogDigest: Digest.semantic('other-catalog'),
      launchProfileId: 'other-profile',
      targetId: 'other-target',
      platform: TargetPlatform.androidEmulator.name,
    );

    expect(
      () => resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: _binding(launchProfileId: 'bound-profile'),
        launchProfile: _profile(),
        executionFingerprint: fingerprint,
      ),
      throwsA(
        isA<ScenarioLabRuntimeInputResolutionException>().having(
          (error) => error.issues,
          'sorted issues',
          orderedEquals(<String>[
            'ExecutionFingerprint catalog digest does not match the run',
            'ExecutionFingerprint launchProfileId other-profile does not match LaunchProfile web-default',
            'ExecutionFingerprint platform androidEmulator does not match LaunchProfile platform web',
            'ExecutionFingerprint targetId other-target does not match ScenarioExecutionBinding targetId web-target',
            'ScenarioExecutionBinding launchProfileId bound-profile does not match LaunchProfile web-default',
          ]),
        ),
      ),
    );
  });

  test('rejects checkpoint bindings and conflicting reserved pins', () {
    final conflictingFingerprint = _fingerprint(
      catalogDigest: catalogDigest,
      inputDigests: <String, Digest>{
        ScenarioLabRuntimeInputResolver.executionBindingInputDigestKey:
            Digest.semantic('wrong-binding'),
        ScenarioLabRuntimeInputResolver.launchProfileInputDigestKey:
            Digest.semantic('wrong-profile'),
      },
    );

    expect(
      () => resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: _checkpointBinding(),
        launchProfile: _profile(),
        executionFingerprint: conflictingFingerprint,
      ),
      throwsA(
        isA<ScenarioLabRuntimeInputResolutionException>()
            .having(
              (error) => error.issues,
              'issues',
              contains(contains('uses a checkpoint; this resolver requires')),
            )
            .having(
              (error) => error.issues,
              'conflict count',
              containsAll(<Matcher>[
                contains('execution-binding.v1 conflicts'),
                contains('launch-profile.v1 conflicts'),
              ]),
            ),
      ),
    );
  });

  test('requires the complete Gateway pair and rejects stale Gateway pins', () {
    final gateway = _gatewayCompilation();
    final gatewayBinding = _binding(
      gatewayPresetId: gateway.plan.preset.id.value,
    );
    final gatewayFingerprint = _fingerprint(
      catalogDigest: catalogDigest,
      backendMode: gateway.plan.backendMode,
      networkContainment: gateway.plan.networkContainment,
    );

    expect(
      () => resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: gatewayBinding,
        launchProfile: _profile(),
        executionFingerprint: gatewayFingerprint,
        compiledGatewayPlan: gateway.plan,
      ),
      _resolutionFailureContaining('required together'),
    );
    expect(
      () => resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: _binding(),
        launchProfile: _profile(),
        executionFingerprint: _fingerprint(
          catalogDigest: catalogDigest,
          inputDigests: <String, Digest>{
            ScenarioLabRuntimeInputResolver.routingTableInputDigestKey:
                gateway.routingTable.digest,
          },
        ),
      ),
      _resolutionFailureContaining('stale Gateway pin'),
    );
    expect(
      () => resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: _binding(),
        launchProfile: _profile(),
        executionFingerprint: _fingerprint(
          catalogDigest: catalogDigest,
          backendMode: gateway.plan.backendMode,
          networkContainment: gateway.plan.networkContainment,
        ),
        compiledGatewayPlan: gateway.plan,
        routingTable: gateway.routingTable,
      ),
      _resolutionFailureContaining('forbidden'),
    );
  });

  test('rejects inconsistent preset, routing, mode and containment', () {
    final gateway = _gatewayCompilation();
    final wrongRouting = RoutingTable(
      scopeId: GatewayScopeId('other-scope'),
      presetId: GatewayPresetId('other-preset'),
      entries: <GatewayRouteId, GatewayRoutingDecision>{
        gateway.plan.routes.single.id: GatewayRoutingDecision.deny,
      },
    );
    final binding = _binding(gatewayPresetId: 'binding-preset');

    expect(
      () => resolver.resolve(
        expectedCatalogDigest: catalogDigest,
        executionBinding: binding,
        launchProfile: _profile(),
        executionFingerprint: _fingerprint(
          catalogDigest: catalogDigest,
          backendMode: BackendMode.hybrid,
          networkContainment: NetworkContainment.targetEnforced,
        ),
        compiledGatewayPlan: gateway.plan,
        routingTable: wrongRouting,
      ),
      throwsA(
        isA<ScenarioLabRuntimeInputResolutionException>().having(
          (error) => error.issues,
          'issues',
          containsAll(<Matcher>[
            contains('does not match ScenarioExecutionBinding gatewayPresetId'),
            contains('RoutingTable preset does not match'),
            contains('RoutingTable scope does not match'),
            contains('RoutingTable decision'),
            contains('backendMode does not match'),
            contains('networkContainment does not match'),
          ]),
        ),
      ),
    );
  });

  test(
    'rejects a routing table whose route registry differs from the plan',
    () {
      final gateway = _gatewayCompilation();
      final wrongRouting = RoutingTable(
        scopeId: gateway.routingTable.scopeId,
        presetId: gateway.routingTable.presetId,
        entries: <GatewayRouteId, GatewayRoutingDecision>{
          GatewayRouteId('not-compiled'): GatewayRoutingDecision.mock,
        },
      );

      expect(
        () => resolver.resolve(
          expectedCatalogDigest: catalogDigest,
          executionBinding: _binding(
            gatewayPresetId: gateway.plan.preset.id.value,
          ),
          launchProfile: _profile(),
          executionFingerprint: _fingerprint(
            catalogDigest: catalogDigest,
            backendMode: gateway.plan.backendMode,
            networkContainment: gateway.plan.networkContainment,
          ),
          compiledGatewayPlan: gateway.plan,
          routingTable: wrongRouting,
        ),
        _resolutionFailureContaining(
          'RoutingTable entries must equal compiled Gateway routes',
        ),
      );
    },
  );
}

Matcher _resolutionFailureContaining(String text) => throwsA(
  isA<ScenarioLabRuntimeInputResolutionException>().having(
    (error) => error.issues,
    'issues',
    contains(contains(text)),
  ),
);

ScenarioExecutionBinding _binding({
  String launchProfileId = 'web-default',
  String? gatewayPresetId,
}) => ScenarioExecutionBinding(
  id: ScenarioExecutionBindingId('scenario-binding'),
  scenarioId: ScenarioId('scenario'),
  targetId: 'web-target',
  launchProfileId: launchProfileId,
  gatewayPresetId: gatewayPresetId,
);

ScenarioExecutionBinding _checkpointBinding() => ScenarioExecutionBinding(
  id: ScenarioExecutionBindingId('scenario-checkpoint-binding'),
  scenarioId: ScenarioId('scenario'),
  targetId: 'web-target',
  checkpointId: 'checkpoint',
);

LaunchProfile _profile() => LaunchProfile(
  id: 'web-default',
  applicationId: ApplicationId('sample'),
  platform: TargetPlatform.web,
  command: 'flutter',
  arguments: const <String>['run', '-d', 'web-server'],
  workingDirectory: '.',
  overlay: RuntimeConfigurationOverlay(const <String, String>{}),
  bootstrapPolicy: ApplicationBootstrapPolicy(
    const <String, BootstrapDependencyPolicy>{},
  ),
);

ExecutionFingerprint _fingerprint({
  required Digest catalogDigest,
  String launchProfileId = 'web-default',
  String targetId = 'web-target',
  String platform = 'web',
  BackendMode backendMode = BackendMode.none,
  NetworkContainment networkContainment = NetworkContainment.unconstrained,
  Map<String, String> toolchain = const <String, String>{'dart': '3.12.2'},
  Set<String> capabilities = const <String>{'read'},
  Map<String, Digest> inputDigests = const <String, Digest>{},
  Map<String, String> policies = const <String, String>{},
}) => ExecutionFingerprint(
  catalogDigest: catalogDigest,
  launchProfileId: launchProfileId,
  targetId: targetId,
  platform: platform,
  renderer: 'canvaskit',
  runtimeFidelity: RuntimeFidelity.hostNative,
  backendMode: backendMode,
  networkContainment: networkContainment,
  bootstrapAssessment: BootstrapAssessment.controlled,
  toolchain: toolchain,
  capabilities: capabilities,
  inputDigests: inputDigests,
  policies: policies,
  sourceRevision: 'revision',
);

GatewayCompilation _gatewayCompilation({bool reverseInputs = false}) {
  final scopeId = GatewayScopeId('delivery');
  final presetId = GatewayPresetId('delivery-ready');
  final route = GatewayRoute(
    id: GatewayRouteId('dashboard'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/dashboard',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('dashboard-ready'),
  );
  final fixtureBytes = utf8.encode('{"state":"ready"}');
  final fixture = GatewayFixture(
    id: GatewayFixtureId('dashboard-ready'),
    status: 200,
    headers: const <String, String>{'content-type': 'application/json'},
    bodyDigest: Digest.bytes(fixtureBytes),
    bodySize: fixtureBytes.length,
    mediaType: 'application/json',
  );
  final routes = <GatewayRoute>[route];
  final fixtures = <GatewayFixture>[fixture];
  return const GatewayPlanCompiler().compile(
    scope: GatewayScope(
      id: scopeId,
      displayName: 'Delivery',
      routeIds: <GatewayRouteId>[route.id],
    ),
    preset: GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Delivery ready',
      routeIds: <GatewayRouteId>[route.id],
    ),
    routes: reverseInputs ? routes.reversed : routes,
    fixtures: reverseInputs ? fixtures.reversed : fixtures,
  );
}
