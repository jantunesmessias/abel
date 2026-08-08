import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late FileSystemWorkspaceStore store;
  late _RecordingHandler handler;
  late GatewayCompilation compilation;
  late GatewayHttpServer server;
  late HttpContractProbeTransport transport;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('devex-probe-');
    store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    handler = _RecordingHandler();
    compilation = _compilation();
    final runtime = GatewayRuntime(
      gatewaySessionId: 'probe-session',
      compilation: compilation,
      mockHandler: handler,
      clock: SystemClock(),
      delay: const SystemDelay(),
    );
    server = GatewayHttpServer(runtime: runtime);
    await server.start();
    transport = HttpContractProbeTransport(origin: server.origin);
  });

  tearDown(() async {
    transport.close();
    await server.close();
    workspace.deleteSync(recursive: true);
  });

  test(
    'after/extract runs through the real data plane and classifies CAS',
    () async {
      final session = GatewayRouteId('session');
      final details = GatewayRouteId('details');
      final plan = ContractProbePlan(
        id: 'account-chain',
        presetId: GatewayPresetId('default'),
        steps: <ContractProbeStep>[
          ContractProbeStep(
            routeId: details,
            order: 0,
            after: <GatewayRouteId>{session},
            extract: <String, ProbeExtraction>{
              'account_id': ProbeExtraction(
                fromRouteId: session,
                paths: <String>['/missing', '/data/id'],
              ),
            },
          ),
          ContractProbeStep(
            routeId: session,
            order: 50,
            after: const <GatewayRouteId>{},
            extract: const <String, ProbeExtraction>{},
          ),
        ],
        parameterDefaults: const <String, String>{},
        artifactRetention: ProbeArtifactRetention.cas,
        artifactClassification: ArtifactClassification.sensitive,
      );

      final report = await ContractProbeExecutor(store: store).execute(
        plan: plan,
        gatewayPlan: compilation.plan,
        transport: transport,
      );

      expect(report.success, isTrue);
      expect(
        report.executions.map((execution) => execution.routeId.value),
        <String>['session', 'details'],
      );
      expect(handler.pathParameters, <Map<String, String>>[
        const <String, String>{},
        const <String, String>{'account_id': 'synthetic-42'},
      ]);
      expect(
        report.executions.every(
          (execution) =>
              execution.artifact?.classification ==
              ArtifactClassification.sensitive,
        ),
        isTrue,
      );
      for (final execution in report.executions) {
        expect(store.readBlob(execution.bodyDigest), isNotNull);
      }
      expect(
        Directory(
          '${store.stateRoot}/probe/temporary',
        ).listSync().whereType<File>(),
        hasLength(1),
      );
    },
  );

  test(
    'route outside appliesTo is rejected before network execution',
    () async {
      final plan = ContractProbePlan(
        id: 'outside',
        presetId: GatewayPresetId('default'),
        steps: <ContractProbeStep>[
          ContractProbeStep(
            routeId: GatewayRouteId('outside'),
            order: 0,
            after: const <GatewayRouteId>{},
            extract: const <String, ProbeExtraction>{},
          ),
        ],
        parameterDefaults: const <String, String>{},
      );

      await expectLater(
        ContractProbeExecutor().execute(
          plan: plan,
          gatewayPlan: compilation.plan,
          transport: transport,
        ),
        throwsStateError,
      );
      expect(handler.pathParameters, isEmpty);
    },
  );

  test('manual values override extracted parameters explicitly', () async {
    final session = GatewayRouteId('session');
    final details = GatewayRouteId('details');
    final plan = ContractProbePlan(
      id: 'manual-override',
      presetId: GatewayPresetId('default'),
      steps: <ContractProbeStep>[
        ContractProbeStep(
          routeId: session,
          order: 0,
          after: const <GatewayRouteId>{},
          extract: const <String, ProbeExtraction>{},
        ),
        ContractProbeStep(
          routeId: details,
          order: 1,
          after: <GatewayRouteId>{session},
          extract: <String, ProbeExtraction>{
            'account_id': ProbeExtraction(
              fromRouteId: session,
              paths: <String>['/data/id'],
            ),
          },
        ),
      ],
      parameterDefaults: const <String, String>{},
    );

    final report = await ContractProbeExecutor().execute(
      plan: plan,
      gatewayPlan: compilation.plan,
      transport: transport,
      manualParameters: const <String, String>{'account_id': 'manual-7'},
    );

    expect(report.success, isTrue);
    expect(handler.pathParameters.last['account_id'], 'manual-7');
    expect(
      report.executions.every((execution) => execution.artifact == null),
      isTrue,
    );
  });
}

GatewayCompilation _compilation() {
  final scope = GatewayScopeId('accounts');
  final preset = GatewayPresetId('default');
  final routes = <GatewayRoute>[
    GatewayRoute(
      id: GatewayRouteId('session'),
      scopeId: scope,
      method: 'GET',
      pathTemplate: '/session',
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{preset},
      policy: GatewayRoutePolicy.localOnly,
      fixtureId: GatewayFixtureId('session-body'),
    ),
    GatewayRoute(
      id: GatewayRouteId('details'),
      scopeId: scope,
      method: 'GET',
      pathTemplate: '/accounts/{account_id}',
      requiredQuery: const <String, String>{},
      appliesTo: <GatewayPresetId>{preset},
      policy: GatewayRoutePolicy.localOnly,
      fixtureId: GatewayFixtureId('details-body'),
    ),
  ];
  final bodies = <String, List<int>>{
    'session-body': utf8.encode('{"data":{"id":"synthetic-42"}}'),
    'details-body': utf8.encode('{"state":"ready"}'),
  };
  return const GatewayPlanCompiler().compile(
    scope: GatewayScope(
      id: scope,
      displayName: 'Accounts',
      routeIds: routes.map((route) => route.id).toList(),
    ),
    preset: GatewayPreset(
      id: preset,
      scopeId: scope,
      description: 'Default',
      routeIds: routes.map((route) => route.id).toList(),
    ),
    routes: routes,
    fixtures: <GatewayFixture>[
      for (final entry in bodies.entries)
        GatewayFixture(
          id: GatewayFixtureId(entry.key),
          status: 200,
          headers: const <String, String>{'content-type': 'application/json'},
          bodyDigest: Digest.bytes(entry.value),
          bodySize: entry.value.length,
          mediaType: 'application/json',
        ),
    ],
  );
}

final class _RecordingHandler implements MockHandlerPort {
  final List<Map<String, String>> pathParameters = <Map<String, String>>[];

  @override
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayFixture fixture,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  }) async {
    this.pathParameters.add(Map<String, String>.of(pathParameters));
    return GatewayMockResult(
      status: 200,
      headers: const <String, String>{'content-type': 'application/json'},
      body: route.id.value == 'session'
          ? utf8.encode('{"data":{"id":"synthetic-42"}}')
          : utf8.encode('{"state":"ready"}'),
    );
  }
}
