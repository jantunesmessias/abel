@TestOn('vm')
library;

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_studio/src/catalog/sample_catalog.dart';
import 'package:devex_studio/src/host/studio_host_client.dart';
import 'package:devex_studio/src/jaspr/capability_pages.dart';
import 'package:devex_studio/src/remote/remote_session_grant_vault.dart';
import 'package:devex_studio/src/target_frame/target_frame.dart';
import 'package:devex_ui_system/devex_ui_system.dart';
import 'package:jaspr_test/jaspr_test.dart';

void main() {
  test('TargetFrame VM facade fails closed', () {
    final controller = TargetFrameController();
    expect(controller.isAttached, isFalse);
    expect(
      () => controller.send(const <String, Object?>{'type': 'probe'}),
      throwsUnsupportedError,
    );
  });

  testComponents('target route starts a Host session before mounting iframe', (
    tester,
  ) async {
    final client = _SessionClient();
    SessionSnapshot? published;
    tester.pumpComponent(
      TargetSessionPage(
        enabled: true,
        snapshot: _snapshot(),
        client: client,
        onSessionChanged: (session) => published = session,
      ),
    );
    await tester.pump();

    expect(find.text('Target'), findsComponents);
    await tester.click(find.componentWithText(DevExButton, 'Iniciar target'));
    await tester.pump();

    expect(client.startCalls, 1);
    expect(client.launchProfileId, 'sample-web');
    expect(client.targetOrigin, Uri.parse('http://127.0.0.1:8080'));
    expect(published?.id, 'session-test');
    expect(find.text('Target indisponível'), findsOneComponent);
    expect(find.textContaining('Target pronto'), findsOneComponent);

    await tester.click(find.componentWithText(DevExButton, 'Encerrar'));
    await tester.pump();

    expect(client.stopCalls, 1);
    expect(published?.state, SessionState.stopped);
    expect(find.textContaining('Target encerrado'), findsOneComponent);
  });

  testComponents(
    'Gateway route discovers presets and derives the owner Session',
    (tester) async {
      final client = _GatewayClient();
      Map<String, Object?>? published;
      tester.pumpComponent(
        GatewayLabPage(
          enabled: true,
          client: client,
          ownerSession: _readySession(),
          onStatusChanged: (status) => published = status,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('showcase-hybrid'), findsComponents);
      expect(find.text('session-test'), findsOneComponent);
      await tester.click(
        find.componentWithText(DevExButton, 'Iniciar Gateway'),
      );
      await tester.pump();
      await tester.pump();

      expect(client.ownerSessionId, 'session-test');
      expect(client.planArtifactDigest, client.preset.artifactDigest);
      expect(published?['state'], 'running');
      expect(find.text('/v1/dashboard'), findsOneComponent);
    },
  );

  testComponents('disabled Gateway route exposes its capability boundary', (
    tester,
  ) async {
    tester.pumpComponent(
      const GatewayLabPage(enabled: false, client: null, ownerSession: null),
    );
    await tester.pump();

    expect(find.text('Gateway não habilitado'), findsOneComponent);
    expect(find.textContaining('studio.gateway'), findsOneComponent);
  });

  testComponents('remote route consumes its ephemeral grant exactly once', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 11);
    final vault = RemoteSessionGrantVault(nowUtc: () => now);
    vault.stage(
      RemoteSessionGrant(
        runId: 'run-test',
        endpoint: Uri.parse(
          'wss://gateway.example.test/v1/sessions/run-test/viewer',
        ),
        compactTicket: 'signed-viewer-ticket',
        allowedTransports: const <RemoteInteractiveTransport>{
          RemoteInteractiveTransport.webDirect,
        },
        expiresAt: now.add(const Duration(minutes: 5)),
      ),
    );
    tester.pumpComponent(
      RemoteSessionPage(enabled: true, runId: 'run-test', grants: vault),
    );
    await tester.pump();

    expect(find.text('Sessão remota indisponível'), findsOneComponent);
    expect(
      find.text('A superfície remota exige execução no browser.'),
      findsOneComponent,
    );
    expect(vault.take('run-test'), isNull);
  });
}

WorkspaceSnapshot _snapshot() {
  final base = sampleCatalogManifest();
  final scenario = base.scenarios.first;
  final catalog = CatalogManifest(
    distribution: base.distribution,
    layout: base.layout,
    workspace: base.workspace,
    applications: base.applications,
    journeys: base.journeys,
    scenarios: base.scenarios,
    transitions: base.transitions,
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('sample-binding'),
        scenarioId: scenario.id,
        targetId: 'sample-target',
        launchProfileId: 'sample-web',
      ),
    ],
  );
  return WorkspaceSnapshot(
    revision: 1,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: const <Variant>[],
      sources: const <VariantDefinitionSource>[],
    ),
    effectiveKitManifest: EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic(const <String, Object?>{
        'profile': 'target-test',
      }),
      modules: const <EffectiveModuleState>[],
      commands: const <String>[],
      rpcMethods: const <String>['devex.session.start'],
      studioContributions: const <String>['studio.shell', 'studio.target'],
      generatedAt: DateTime.utc(2026, 8, 11),
    ),
    providers: const <VisualEvidenceProviderState>[],
    visualProjections: const <VisualEvidenceProjection>[],
    generatedAt: DateTime.utc(2026, 8, 11),
  );
}

final class _SessionClient implements StudioHostSessionClient {
  var startCalls = 0;
  var stopCalls = 0;
  String? launchProfileId;
  Uri? targetOrigin;

  SessionSnapshot get _ready => SessionSnapshot(
    id: 'session-test',
    launchProfileId: launchProfileId ?? 'sample-web',
    state: SessionState.ready,
    createdAt: DateTime.utc(2026, 8, 11),
    updatedAt: DateTime.utc(2026, 8, 11),
    trace: const <SessionTraceEntry>[],
    target: ExecutionTarget(
      id: 'target-session-test',
      platform: TargetPlatform.web,
      origin: targetOrigin ?? Uri.parse('http://127.0.0.1:8080'),
      capabilities: const <CapabilityDescriptor>[],
    ),
  );

  @override
  Future<SessionSnapshot> startSession({
    required String launchProfileId,
    required Uri targetOrigin,
  }) async {
    startCalls += 1;
    this.launchProfileId = launchProfileId;
    this.targetOrigin = targetOrigin;
    return _ready;
  }

  @override
  Future<SessionSnapshot> cancelSession(
    String sessionId, {
    String? reason,
  }) async => _ready;

  @override
  Future<SessionSnapshot> resetSession(String sessionId) async => _ready;

  @override
  Future<SessionSnapshot> sessionStatus(String sessionId) async => _ready;

  @override
  Future<SessionSnapshot> stopSession(String sessionId) async {
    stopCalls += 1;
    return SessionSnapshot(
      id: _ready.id,
      launchProfileId: _ready.launchProfileId,
      state: SessionState.stopped,
      createdAt: _ready.createdAt,
      updatedAt: _ready.updatedAt.add(const Duration(seconds: 1)),
      trace: _ready.trace,
      target: _ready.target,
    );
  }
}

SessionSnapshot _readySession() => SessionSnapshot(
  id: 'session-test',
  launchProfileId: 'sample-web',
  state: SessionState.ready,
  createdAt: DateTime.utc(2026, 8, 11),
  updatedAt: DateTime.utc(2026, 8, 11),
  trace: const <SessionTraceEntry>[],
  target: ExecutionTarget(
    id: 'target-session-test',
    platform: TargetPlatform.web,
    origin: Uri.parse('http://127.0.0.1:8080'),
    capabilities: const <CapabilityDescriptor>[],
  ),
);

final class _GatewayClient implements StudioHostGatewayClient {
  final preset = GatewayPlanArtifactDescriptor(
    presetId: GatewayPresetId('showcase-hybrid'),
    description: 'Hybrid showcase API',
    backendMode: BackendMode.hybrid,
    routeCount: 3,
    planDigest: Digest.semantic(const <String, Object?>{'plan': 1}),
    artifactDigest: Digest.semantic(const <String, Object?>{'artifact': 1}),
  );
  String? ownerSessionId;
  Digest? planArtifactDigest;

  @override
  Future<List<GatewayPlanArtifactDescriptor>> gatewayPresets() async =>
      <GatewayPlanArtifactDescriptor>[preset];

  @override
  Future<Map<String, Object?>> startGateway({
    required String ownerSessionId,
    required Digest planArtifactDigest,
  }) async {
    this.ownerSessionId = ownerSessionId;
    this.planArtifactDigest = planArtifactDigest;
    return <String, Object?>{
      'id': 'gateway-test',
      'ownerSessionId': ownerSessionId,
    };
  }

  @override
  Future<Map<String, Object?>> gatewayStatus(String gatewaySessionId) async =>
      <String, Object?>{
        'gatewaySessionId': gatewaySessionId,
        'state': 'running',
        'dataOrigin': 'http://127.0.0.1:8090',
        'backendMode': 'hybrid',
        'networkContainment': 'gatewayOnly',
        'trafficEvents': 1,
      };

  @override
  Future<List<Map<String, Object?>>> gatewayTraffic(
    String gatewaySessionId, {
    int afterSequence = 0,
    int limit = 100,
  }) async => <Map<String, Object?>>[
    <String, Object?>{
      'sequence': 1,
      'method': 'GET',
      'routeTemplate': '/v1/dashboard',
      'outcome': 'passthrough',
      'status': 200,
      'durationMicroseconds': 900,
    },
  ];

  @override
  Future<Map<String, Object?>> resetGateway(String gatewaySessionId) =>
      gatewayStatus(gatewaySessionId);

  @override
  Future<Map<String, Object?>> stopGateway(String gatewaySessionId) async =>
      <String, Object?>{'id': gatewaySessionId, 'state': 'stopped'};
}
