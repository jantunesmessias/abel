@TestOn('vm')
library;

import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/jaspr/scenario_lab_quality_pages.dart';
import 'package:studio/src/jaspr/studio_app.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:studio/src/lab/studio_scenario_lab_run_transport.dart';
import 'package:studio/src/target_frame/target_frame.dart';
import 'package:studio_ui/studio_ui.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  testComponents(
    'v2 manifest and independent contributions publish nav and stable indexes',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot();
      tester.pumpComponent(
        StudioApplication(clientFactory: () => _v2Client(fixture, snapshot)),
      );
      await tester.pump();

      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href': '/lab',
          'data-studio-contribution': 'studio.lab',
          'aria-current': 'page',
        }),
        findsOneComponent,
      );
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href': '/quality',
          'data-studio-contribution': 'studio.quality',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(<String, String>{
          'data-lab-route-state': 'index',
          'data-scenario-lab-manifest-digest': fixture.manifest.digest.value,
          'aria-label': 'Índice de Scenario Lab',
        }),
        findsOneComponent,
      );
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href': '/lab/scenarios/scenario-ready/scripts/exercise-ready',
          'data-lab-deep-link': 'true',
          'aria-label':
              'Abrir Scenario Lab para Ready state, script Exercise ready state',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'aria-label': 'Deep links de Scenario Lab',
        }),
        findsOneComponent,
      );
      expect(_scenarioSurfaceWithInlineStyles(), findsNothing);
    },
    url: '/lab',
  );

  testComponents(
    'Lab deep link selects the exact Scenario and script without run actions',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot();
      tester.pumpComponent(
        StudioApplication(clientFactory: () => _v2Client(fixture, snapshot)),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-route-state': 'ready',
          'data-lab-scenario-id': 'scenario-ready',
          'data-lab-script-id': 'exercise-ready',
          'aria-label': 'Scenario Lab selecionado',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-run-state': 'notStarted',
          'data-lab-scenario-id': 'scenario-ready',
          'data-lab-script-id': 'exercise-ready',
        }),
        findsOneComponent,
      );
      expect(find.text('Executar'), findsNothing);
      expect(find.text('Cancelar execução'), findsNothing);
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href': '/quality/scenarios/scenario-ready/scripts/exercise-ready',
          'data-scenario-cross-surface': 'lab-to-quality',
        }),
        findsOneComponent,
      );
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'Quality deep link is read-only, unverified and human-decision independent',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot();
      tester.pumpComponent(
        StudioApplication(clientFactory: () => _v2Client(fixture, snapshot)),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-route-state': 'ready',
          'data-quality-scenario-id': 'scenario-ready',
          'data-quality-script-id': 'exercise-ready',
          'aria-label': 'Quality selecionado',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-state': 'unverified',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'aria-label': 'Decisão humana',
          'data-quality-human-decision': 'notAvailable',
        }),
        findsOneComponent,
      );
      expect(
        find.textContaining('Nenhuma projeção de decisão'),
        findsOneComponent,
      );
      expect(find.text('Executar'), findsNothing);
      expect(find.text('Cancelar'), findsNothing);
    },
    url: '/quality/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'historical Quality offers recollection in the current Lab without a run ID',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result();
      tester.pumpComponent(
        ScenarioQualityRoutePage(
          enabled: true,
          labEnabled: true,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
          hasContentGeneration: true,
          scenarioId: fixture.scenarioId.value,
          scriptId: fixture.scriptId.value,
          selectedRunId: result.finalSnapshot.runId,
          runSnapshot: result.finalSnapshot,
          runResult: result,
          qualitySnapshot: fixture.quality(result),
          currentContentSetDigest: digest('new-content-generation'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href': '/lab/scenarios/scenario-ready/scripts/exercise-ready',
          'data-quality-action': 'recollect',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-currentness-notice': 'stale',
        }),
        findsOneComponent,
      );
    },
  );

  testComponents(
    'Quality can be composed without Lab while direct Lab route stays disabled',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot(
        contributions: const <String>['studio.shell', 'studio.quality'],
      );
      tester.pumpComponent(
        StudioApplication(clientFactory: () => _v2Client(fixture, snapshot)),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-route-state': 'disabled',
          'aria-label': 'Estado de Scenario Lab',
        }),
        findsOneComponent,
      );
      expect(find.text('Scenario Lab não habilitado'), findsOneComponent);
      expect(
        _domWithAttributes(const <String, String>{
          'data-studio-contribution': 'studio.lab',
        }),
        findsNothing,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-studio-contribution': 'studio.quality',
        }),
        findsOneComponent,
      );
    },
    url: '/lab',
  );

  testComponents('invalid deep link is explicit and never broadens selection', (
    tester,
  ) async {
    final fixture = ScenarioLabTestFixture();
    final snapshot = fixture.workspaceSnapshot();
    tester.pumpComponent(
      StudioApplication(clientFactory: () => _v2Client(fixture, snapshot)),
    );
    await tester.pump();

    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-route-state': 'notFound',
        'aria-label': 'Estado de Scenario Lab',
      }),
      findsOneComponent,
    );
    expect(
      find.text('Seleção de Scenario Lab não encontrada'),
      findsOneComponent,
    );
    expect(find.textContaining('scenario-missing'), findsOneComponent);
    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-run-state': 'notStarted',
      }),
      findsNothing,
    );
  }, url: '/lab/scenarios/scenario-missing/scripts/exercise-ready');

  testComponents(
    'content without Lab keeps absence explicit and hides both navs',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot();
      tester.pumpComponent(
        StudioApplication(
          clientFactory: () =>
              _v2Client(fixture, snapshot, includeManifest: false),
        ),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-route-state': 'manifestAbsent',
        }),
        findsOneComponent,
      );
      expect(
        find.textContaining('geração content-set atual'),
        findsOneComponent,
      );
      expect(_domWithAttribute('data-studio-contribution'), findsNothing);
    },
    url: '/quality',
  );

  testComponents(
    'canonical content without Lab stays explicit and never exposes Lab',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot();
      final content = StudioWorkspaceContent(
        snapshot: snapshot,
        identity: ExperienceContentSetIdentity(
          revision: 1,
          catalogDigest: snapshot.catalog.digest,
          workspaceSnapshotDigest: snapshot.digest,
          workspaceContentDigest: snapshot.workspaceContentDigest,
        ),
      );
      tester.pumpComponent(
        StudioApplication(clientFactory: () => _ContentClient(content)),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-route-state': 'manifestAbsent',
        }),
        findsOneComponent,
      );
      expect(
        find.textContaining('geração content-set atual'),
        findsOneComponent,
      );
      expect(_domWithAttribute('data-studio-contribution'), findsNothing);
    },
    url: '/lab',
  );

  testComponents('route component rejects a cross-catalog Lab manifest', (
    tester,
  ) async {
    final manifestFixture = ScenarioLabTestFixture();
    final catalogFixture = ScenarioLabTestFixture();
    final otherCatalog = CatalogManifest(
      distribution: catalogFixture.catalog.distribution,
      layout: catalogFixture.catalog.layout,
      workspace: Workspace(
        id: catalogFixture.catalog.workspace.id,
        displayName: 'Other workspace',
      ),
      applications: catalogFixture.catalog.applications,
      journeys: catalogFixture.catalog.journeys,
      scenarios: catalogFixture.catalog.scenarios,
      transitions: catalogFixture.catalog.transitions,
      executionBindings: catalogFixture.catalog.executionBindings,
    );
    tester.pumpComponent(
      ScenarioLabRoutePage(
        enabled: true,
        qualityEnabled: false,
        catalog: otherCatalog,
        manifest: manifestFixture.manifest,
        hasContentGeneration: true,
      ),
    );
    await tester.pump();

    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-route-state': 'fencingMismatch',
      }),
      findsOneComponent,
    );
    expect(find.text('Geração Scenario Lab inconsistente'), findsOneComponent);
  });

  testComponents(
    'complete quartets start, mount relay automatically and cancel on Lab only',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
      );
      final client = _ExecutableContentClient(fixture, snapshot);
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-run-capability': 'available',
          'data-lab-relay-capability': 'available',
          'data-lab-run-actions-state': 'ready',
        }),
        findsOneComponent,
      );
      expect(
        find.componentWithText(StudioButton, 'Iniciar execução'),
        findsOneComponent,
      );
      expect(
        _domWithTagAndAttributes('button', const <String, String>{
          'data-lab-run-action': 'start',
        }),
        findsOneComponent,
      );
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      await tester.pump();
      await tester.pump();

      expect(client.startRequests, hasLength(1));
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-selected-run-id': 'run-00000001',
          'data-lab-run-lifecycle': 'nonTerminal',
        }),
        findsOneComponent,
      );
      for (final action in const <String>['reattach', 'cancel', 'relay']) {
        expect(
          _domWithTagAndAttributes('button', <String, String>{
            'data-lab-run-action': action,
          }),
          findsOneComponent,
        );
      }
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href':
              '/quality/scenarios/scenario-ready/scripts/exercise-ready?runId=run-00000001',
          'data-scenario-cross-surface': 'lab-to-quality',
        }),
        findsOneComponent,
      );
      await tester.pump();

      expect(client.describeCalls, 1);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-relay-run-id': 'run-00000001',
          'data-lab-relay-state': 'awaitingHello',
        }),
        findsOneComponent,
      );

      await tester.click(
        find.componentWithText(StudioButton, 'Cancelar execução'),
      );
      await tester.pump();

      expect(client.cancelCalls, 1);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-run-lifecycle': 'terminal',
        }),
        findsOneComponent,
      );
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'terminal relay automatically observes the terminal run and result',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
      );
      final client = _ExecutableContentClient(
        fixture,
        snapshot,
        firstGetState: ScenarioLabRunState.starting,
        relayClosesOnDescribe: true,
      );
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      for (var turn = 0; turn < 5; turn += 1) {
        await tester.pump();
      }

      expect(client.getCalls, 1);
      expect(client.describeCalls, 1);
      expect(client.reattachCalls, 1);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-run-lifecycle': 'terminal',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(<String, String>{
          'data-lab-run-state': 'succeeded',
          'data-lab-result-digest': client.lastResult!.digest.value,
        }),
        findsOneComponent,
      );
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'terminal relay defers one exact observation behind a manual reattach',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
      );
      final manualReattachGate = Completer<void>();
      final relayCloseGate = Completer<void>();
      final client = _ExecutableContentClient(
        fixture,
        snapshot,
        firstReattachGate: manualReattachGate,
        firstReattachReturnsActive: true,
        relayCloseGate: relayCloseGate,
      );
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      await _pumpTurns(tester, 3);
      await tester.click(
        find.componentWithText(StudioButton, 'Reanexar / atualizar'),
      );
      await tester.pump();
      expect(client.reattachCalls, 1);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-run-lifecycle': 'reattaching',
        }),
        findsOneComponent,
      );

      relayCloseGate.complete();
      await _pumpTurns(tester, 3);
      expect(client.reattachCalls, 1);

      manualReattachGate.complete();
      await _pumpTurns(tester, 6);
      expect(client.reattachCalls, 2);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-run-lifecycle': 'terminal',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-run-state': 'succeeded',
        }),
        findsOneComponent,
      );
      expect(client.lastResult, isNotNull);
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'Lab to Quality disposal releases the relay and permits an exact remount',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
      );
      final client = _ExecutableContentClient(fixture, snapshot);
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      await _pumpTurns(tester, 3);
      expect(client.describeCalls, 1);
      expect(_domWithAttribute('data-lab-relay-run-id'), findsOneComponent);

      await _pushTestRoute(
        '/quality/scenarios/scenario-ready/scripts/exercise-ready?runId=run-00000001',
      );
      await _pumpTurns(tester, 3);
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);

      await _pushTestRoute(
        '/lab/scenarios/scenario-ready/scripts/exercise-ready?runId=run-00000001',
      );
      await _pumpTurns(tester, 2);
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);
      expect(
        find.componentWithText(StudioButton, 'Conectar target'),
        findsOneComponent,
      );

      await tester.click(
        find.componentWithText(StudioButton, 'Conectar target'),
      );
      await _pumpTurns(tester, 3);
      expect(client.describeCalls, 2);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-relay-run-id': 'run-00000001',
          'data-lab-relay-state': 'awaitingHello',
        }),
        findsOneComponent,
      );
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'a same-run URL never mounts a relay under another Scenario binding',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final alternate = _alternateScenarioContent(fixture);
      final client = _ExecutableContentClient(
        fixture,
        alternate.snapshot,
        manifest: alternate.manifest,
      );
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      await _pumpTurns(tester, 3);
      expect(_domWithAttribute('data-lab-relay-run-id'), findsOneComponent);

      await _pushTestRoute(
        '/lab/scenarios/scenario-alternate/scripts/exercise-alternate?runId=run-00000001',
      );
      await _pumpTurns(tester, 3);

      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-scenario-id': 'scenario-alternate',
          'data-lab-script-id': 'exercise-alternate',
          'aria-label': 'Scenario Lab: Alternate state',
        }),
        findsOneComponent,
      );
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);
      expect(client.describeCalls, 1);
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'Quality reattaches a URL-selected run read-only and preserves the link',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
      );
      final client = _ExecutableContentClient(fixture, snapshot);
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      expect(find.text('Iniciar execução'), findsNothing);
      expect(find.text('Cancelar execução'), findsNothing);
      expect(
        find.componentWithText(StudioButton, 'Reanexar / atualizar'),
        findsOneComponent,
      );
      expect(
        _domWithTagAndAttributes('button', const <String, String>{
          'data-lab-run-action': 'reattach',
        }),
        findsOneComponent,
      );

      await tester.click(
        find.componentWithText(StudioButton, 'Reanexar / atualizar'),
      );
      await tester.pump();

      expect(client.reattachCalls, 1);
      expect(
        _domWithAttributes(<String, String>{
          'data-quality-run-id': 'run-00000001',
          'data-quality-result-digest': client.lastResult!.digest.value,
          'data-quality-human-decision': 'notAvailable',
        }),
        findsOneComponent,
      );
      expect(
        _domWithTagAndAttributes('a', const <String, String>{
          'href':
              '/lab/scenarios/scenario-ready/scripts/exercise-ready?runId=run-00000001',
          'data-scenario-cross-surface': 'quality-to-lab',
        }),
        findsOneComponent,
      );
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);
    },
    url:
        '/quality/scenarios/scenario-ready/scripts/exercise-ready?runId=run-00000001',
  );

  testComponents('partial lifecycle quartet exposes no execution action', (
    tester,
  ) async {
    final fixture = ScenarioLabTestFixture();
    final snapshot = fixture.workspaceSnapshot(
      rpcMethods: <String>{
        ...studioScenarioLabRunRpcMethods.difference(const <String>{
          'lab.cancel',
        }),
        ...studioLabRelayRpcMethods,
      },
    );
    tester.pumpComponent(
      StudioApplication(
        clientFactory: () => _ExecutableContentClient(fixture, snapshot),
      ),
    );
    await tester.pump();

    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-run-capability': 'rpcIncomplete',
        'data-lab-run-actions-state': 'unavailable',
      }),
      findsOneComponent,
    );
    expect(
      find.textContaining('quartet lifecycle incompleto'),
      findsOneComponent,
    );
    expect(find.text('Iniciar execução'), findsNothing);
    expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);
  }, url: '/lab/scenarios/scenario-ready/scripts/exercise-ready');

  testComponents('invalid URL run ID fails closed before every Host call', (
    tester,
  ) async {
    final fixture = ScenarioLabTestFixture();
    final snapshot = fixture.workspaceSnapshot(
      rpcMethods: <String>{
        ...studioScenarioLabRunRpcMethods,
        ...studioLabRelayRpcMethods,
      },
    );
    final client = _ExecutableContentClient(fixture, snapshot);
    tester.pumpComponent(StudioApplication(clientFactory: () => client));
    await tester.pump();

    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-run-actions-state': 'invalidRunId',
      }),
      findsOneComponent,
    );
    expect(find.text('Run ID inválido'), findsOneComponent);
    expect(find.text('Iniciar execução'), findsNothing);
    expect(find.text('Reanexar / atualizar'), findsNothing);
    expect(client.startRequests, isEmpty);
    expect(client.reattachCalls, 0);
    expect(client.describeCalls, 0);
  }, url: '/lab/scenarios/scenario-ready/scripts/exercise-ready?runId=bad!');

  testComponents(
    'complete run quartet without relay quartet never mounts a target',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: studioScenarioLabRunRpcMethods,
      );
      final client = _ExecutableContentClient(fixture, snapshot);
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      await tester.pump();
      await tester.pump();

      expect(client.startRequests, hasLength(1));
      expect(client.describeCalls, 0);
      expect(_domWithAttribute('data-lab-relay-run-id'), findsNothing);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-relay-state': 'rpcUnavailable',
        }),
        findsOneComponent,
      );
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'Gateway-bound run mounts only the v2 Host-owned origin without DOM leaks',
    (tester) async {
      final fixture = ScenarioLabTestFixture(gateway: true);
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
          ...studioLabRelayV2RpcMethods,
        },
      );
      final client = _ExecutableContentClient(fixture, snapshot);
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(client.describeCalls, 1);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-relay-state': 'awaitingHello',
          'data-lab-relay-gateway-bound': 'true',
        }),
        findsOneComponent,
      );
      expect(
        find.byComponentPredicate(
          (component) =>
              component is TargetFrame &&
              component.scenarioLabRunId == 'run-00000001' &&
              component.gatewayOrigin == null &&
              component.gatewayBound,
          description: 'Gateway-bound relay TargetFrame',
        ),
        findsOneComponent,
      );
      expect(find.textContaining('http://127.0.0.1:8090'), findsNothing);
      expect(_domAttributeContaining('http://127.0.0.1:8090'), findsNothing);
      expect(_domAttributeContaining('relay-nonce-000000000001'), findsNothing);
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );

  testComponents(
    'Gateway-bound run refuses v1 before describe and mounts no frame',
    (tester) async {
      final fixture = ScenarioLabTestFixture(gateway: true);
      final snapshot = fixture.workspaceSnapshot(
        rpcMethods: <String>{
          ...studioScenarioLabRunRpcMethods,
          ...studioLabRelayRpcMethods,
        },
      );
      final client = _ExecutableContentClient(fixture, snapshot);
      tester.pumpComponent(StudioApplication(clientFactory: () => client));
      await tester.pump();

      await tester.click(
        find.componentWithText(StudioButton, 'Iniciar execução'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(client.describeCalls, 0);
      expect(
        _domWithAttributes(const <String, String>{
          'data-lab-relay-capability': 'gatewayV2Required',
        }),
        findsOneComponent,
      );
      expect(
        find.textContaining('nenhum downgrade v1 será tentado'),
        findsOneComponent,
      );
      expect(find.byType(TargetFrame), findsNothing);
    },
    url: '/lab/scenarios/scenario-ready/scripts/exercise-ready',
  );
}

_ContentClient _v2Client(
  ScenarioLabTestFixture fixture,
  WorkspaceSnapshot snapshot, {
  bool includeManifest = true,
}) {
  final manifest = includeManifest ? fixture.manifest : null;
  return _ContentClient(
    StudioWorkspaceContent(
      snapshot: snapshot,
      scenarioLab: manifest,
      identity: ExperienceContentSetIdentity(
        revision: 1,
        catalogDigest: snapshot.catalog.digest,
        workspaceSnapshotDigest: snapshot.digest,
        workspaceContentDigest: snapshot.workspaceContentDigest,
        scenarioLabManifestDigest: manifest?.digest,
      ),
    ),
  );
}

({WorkspaceSnapshot snapshot, ScenarioLabManifest manifest})
_alternateScenarioContent(ScenarioLabTestFixture fixture) {
  final sourceCatalog = fixture.catalog;
  final sourceManifest = fixture.manifest;
  final baseSnapshot = fixture.workspaceSnapshot(
    rpcMethods: <String>{
      ...studioScenarioLabRunRpcMethods,
      ...studioLabRelayRpcMethods,
    },
  );
  final alternateScenarioId = ScenarioId('scenario-alternate');
  final alternateScriptId = ScenarioScriptId('exercise-alternate');
  final alternateBindingId = ScenarioExecutionBindingId('alternate-web');
  final catalog = CatalogManifest(
    distribution: sourceCatalog.distribution,
    layout: sourceCatalog.layout,
    workspace: sourceCatalog.workspace,
    applications: sourceCatalog.applications,
    journeys: sourceCatalog.journeys,
    scenarios: <Scenario>[
      ...sourceCatalog.scenarios,
      Scenario(
        id: alternateScenarioId,
        applicationId: sourceCatalog.scenarios.single.applicationId,
        title: 'Alternate state',
      ),
    ],
    transitions: sourceCatalog.transitions,
    executionBindings: <ScenarioExecutionBinding>[
      ...sourceCatalog.executionBindings,
      ScenarioExecutionBinding(
        id: alternateBindingId,
        scenarioId: alternateScenarioId,
        targetId: 'browser-alternate',
        launchProfileId: 'lab-web-alternate',
      ),
    ],
    reviewGuides: sourceCatalog.reviewGuides,
  );
  final manifest = ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: sourceManifest.appAdapterCapabilities,
    controls: sourceManifest.controls,
    operations: sourceManifest.operations,
    scripts: <ScenarioScriptDefinition>[
      ...sourceManifest.scripts,
      ScenarioScriptDefinition(
        id: alternateScriptId,
        scenarioId: alternateScenarioId,
        displayName: 'Exercise alternate state',
        timeoutMs: 10000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'bind-alternate',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
            bindingId: alternateBindingId,
          ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: sourceManifest.automatedAcceptanceCriteria,
    requiredEvidence: sourceManifest.requiredEvidence,
    comparisonBindings: sourceManifest.comparisonBindings,
    visualComparisonPolicies: sourceManifest.visualComparisonPolicies,
    semanticComparisonPolicies: sourceManifest.semanticComparisonPolicies,
    humanApprovalRequirements: sourceManifest.humanApprovalRequirements,
    supplementalArtifacts: sourceManifest.supplementalArtifacts,
    plans: <ScenarioLabPlan>[
      ...sourceManifest.plans,
      ScenarioLabPlan(
        scenarioId: alternateScenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[alternateBindingId],
        controlIds: const <ScenarioControlId>[],
        operationIds: const <ScenarioLabOperationId>[],
        scriptIds: <ScenarioScriptId>[alternateScriptId],
        automatedAcceptanceCriterionIds:
            const <AutomatedAcceptanceCriterionId>[],
        requiredEvidenceIds: const <RequiredEvidenceId>[],
        comparisonBindingIds: const <ScenarioComparisonBindingId>[],
        humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
        supplementalArtifactIds: const <SupplementalArtifactId>[],
      ),
    ],
  );
  final snapshot = WorkspaceSnapshot(
    revision: baseSnapshot.revision,
    catalog: catalog,
    variantManifest: VariantManifest(
      catalogDigest: catalog.digest,
      variants: baseSnapshot.variantManifest.variants,
      sources: baseSnapshot.variantManifest.sources,
    ),
    effectiveKitManifest: baseSnapshot.effectiveKitManifest,
    providerBindings: baseSnapshot.providerBindings,
    providers: baseSnapshot.providers,
    visualProjections: baseSnapshot.visualProjections,
    moduleDiagnostics: baseSnapshot.moduleDiagnostics,
    generatedAt: baseSnapshot.generatedAt,
  );
  return (snapshot: snapshot, manifest: manifest);
}

Future<void> _pumpTurns(ComponentTester tester, int turns) async {
  for (var turn = 0; turn < turns; turn += 1) {
    await tester.pump();
  }
}

Future<void> _pushTestRoute(String location) async {
  final element = find.byType(Router).evaluate().single as StatefulElement;
  final router = element.state as RouterState;
  try {
    await router.push(location);
  } on UnimplementedError {
    element.markNeedsBuild();
  }
}

final class _ContentClient
    implements StudioHostClient, StudioHostContentClient {
  const _ContentClient(this.content);

  final StudioWorkspaceContent content;

  @override
  Future<void> close() async {}

  @override
  Future<StudioWorkspaceContent> openContent() async => content;

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => content.snapshot;

  @override
  Future<StudioWorkspaceContent> refreshContent() async => content;

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => content.snapshot;
}

final class _ExecutableContentClient
    implements
        StudioHostClient,
        StudioHostContentClient,
        StudioHostScenarioLabRunClient,
        StudioHostLabRelayClient {
  _ExecutableContentClient(
    this.fixture,
    WorkspaceSnapshot snapshot, {
    ScenarioLabManifest? manifest,
    this.firstGetState = ScenarioLabRunState.running,
    this.relayClosesOnDescribe = false,
    this.firstReattachGate,
    this.firstReattachReturnsActive = false,
    this.relayCloseGate,
  }) : manifest = manifest ?? fixture.manifest,
       identity = ExperienceContentSetIdentity(
         revision: 1,
         catalogDigest: snapshot.catalog.digest,
         workspaceSnapshotDigest: snapshot.digest,
         workspaceContentDigest: snapshot.workspaceContentDigest,
         scenarioLabManifestDigest: (manifest ?? fixture.manifest).digest,
       ) {
    content = StudioWorkspaceContent(
      snapshot: snapshot,
      scenarioLab: this.manifest,
      identity: identity,
    );
  }

  final ScenarioLabTestFixture fixture;
  final ScenarioLabManifest manifest;
  final ExperienceContentSetIdentity identity;
  final ScenarioLabRunState firstGetState;
  final bool relayClosesOnDescribe;
  final Completer<void>? firstReattachGate;
  final bool firstReattachReturnsActive;
  final Completer<void>? relayCloseGate;
  late final StudioWorkspaceContent content;
  final List<ScenarioLabRunStartRequest> startRequests =
      <ScenarioLabRunStartRequest>[];
  Digest? _persistedStartDigest;
  ScenarioLabRunSnapshot? _current;
  ScenarioLabRunResult? lastResult;
  var cancelCalls = 0;
  var getCalls = 0;
  var reattachCalls = 0;
  var describeCalls = 0;

  static final ScenarioLabRunId _runId = ScenarioLabRunId('run-00000001');

  @override
  Future<StudioWorkspaceContent> openContent() async => content;

  @override
  Future<StudioWorkspaceContent> refreshContent() async => content;

  @override
  Future<WorkspaceSnapshot> openWorkspace() async => content.snapshot;

  @override
  Future<WorkspaceSnapshot> refreshWorkspace() async => content.snapshot;

  @override
  Future<void> close() async {}

  @override
  Future<ScenarioLabRunSnapshot> startScenarioLabRun(
    ScenarioLabRunStartRequest request,
  ) async {
    startRequests.add(request);
    _persistedStartDigest = request.digest;
    return _current = _snapshot(
      runId: _runId,
      startDigest: request.digest,
      sequence: 0,
      state: ScenarioLabRunState.queued,
    );
  }

  @override
  Future<ScenarioLabRunSnapshot> getScenarioLabRun(
    ScenarioLabRunReference reference,
  ) async {
    getCalls += 1;
    final current = _current!;
    if (current.state != ScenarioLabRunState.queued) return current;
    return _current = _snapshot(
      runId: reference.runId,
      startDigest: _startDigest,
      sequence: current.sequence + 1,
      state: firstGetState,
    );
  }

  @override
  Future<ScenarioLabRunSnapshot> cancelScenarioLabRun(
    ScenarioLabRunReference reference,
  ) async {
    cancelCalls += 1;
    final current = _current;
    return _current = _snapshot(
      runId: reference.runId,
      startDigest: _startDigest,
      sequence: (current?.sequence ?? 0) + 1,
      state: ScenarioLabRunState.cancelled,
    );
  }

  @override
  Future<ScenarioLabRunObservation> reattachScenarioLabRun(
    ScenarioLabRunObserveRequest request,
  ) async {
    reattachCalls += 1;
    if (reattachCalls == 1) {
      await firstReattachGate?.future;
      if (firstReattachReturnsActive) {
        final active = _snapshot(
          runId: request.runId,
          startDigest: _startDigest,
          sequence: request.afterSequence + 1,
          state: ScenarioLabRunState.running,
        );
        _current = active;
        return ScenarioLabRunObservation(
          runId: request.runId,
          disposition: ScenarioLabRunDisposition.active,
          afterSequence: request.afterSequence,
          current: active,
          observations: <ScenarioLabRunSnapshot>[active],
          hasMore: false,
        );
      }
    }
    final terminal = _snapshot(
      runId: request.runId,
      startDigest: _startDigest,
      sequence: request.afterSequence + 1,
      state: ScenarioLabRunState.succeeded,
    );
    final result = ScenarioLabRunResult(
      finalSnapshot: terminal,
      startedAt: time(0),
      completedAt: time(1),
      verificationState: VerificationState.notRun,
    );
    _current = terminal;
    lastResult = result;
    return ScenarioLabRunObservation(
      runId: request.runId,
      disposition: ScenarioLabRunDisposition.terminal,
      afterSequence: request.afterSequence,
      current: terminal,
      observations: <ScenarioLabRunSnapshot>[terminal],
      hasMore: false,
      result: result,
    );
  }

  Digest get _startDigest =>
      _persistedStartDigest ??= digest('persisted-start-request');

  ScenarioLabRunSnapshot _snapshot({
    required ScenarioLabRunId runId,
    required Digest startDigest,
    required int sequence,
    required ScenarioLabRunState state,
  }) {
    final terminal = state.isTerminal;
    final cancelled = state == ScenarioLabRunState.cancelled;
    return ScenarioLabRunSnapshot(
      runId: runId,
      startRequestDigest: startDigest,
      contentSetDigest: identity.contentSetDigest,
      catalogDigest: content.snapshot.catalog.digest,
      scenarioLabManifestDigest: manifest.digest,
      scenarioId: fixture.scenarioId,
      scriptId: fixture.scriptId,
      sequence: sequence,
      observedAt: time(sequence),
      state: state,
      runtimeInputs: state == ScenarioLabRunState.queued
          ? null
          : fixture.runtimeInputs,
      steps: <ScenarioLabStepSnapshot>[
        for (final stepId in const <String>[
          'bind',
          'enable',
          'capture',
          'reset',
        ])
          if (state == ScenarioLabRunState.queued)
            pendingStep(stepId)
          else if (cancelled)
            ScenarioLabStepSnapshot(
              stepId: stepId,
              state: ScenarioLabStepState.cancelled,
              completedAt: time(sequence),
              terminalCause: ScenarioLabStepTerminalCause.cancelled,
            )
          else
            completedStep(stepId, 0, sequence),
      ],
      cleanup: ScenarioLabCleanupResult(
        state: terminal
            ? ScenarioLabCleanupState.succeeded
            : ScenarioLabCleanupState.pending,
      ),
      terminalCause: !terminal
          ? null
          : cancelled
          ? ScenarioLabTerminalCause.cancelledByUser
          : ScenarioLabTerminalCause.completed,
    );
  }

  @override
  Future<StudioLabRelayDescription> describeLabRelay(
    StudioLabRelayRunBinding binding,
  ) async {
    describeCalls += 1;
    await relayCloseGate?.future;
    final call = prepareStudioLabRelayDescribeCall(
      capabilities: content.snapshot.effectiveKitManifest.rpcMethods.toSet(),
      binding: binding,
    );
    final descriptor = ScenarioLabRelayTargetDescriptor(
      runId: binding.runId,
      targetId: binding.targetId,
      launchProfileId: binding.launchProfileId,
      launchAttemptId: TargetLaunchAttemptId('launch-attempt-0001'),
      origin: Uri.parse('http://127.0.0.1:8181'),
      nonce: AppAdapterRelayNonce('relay-nonce-000000000001'),
    );
    final relayClosed = relayClosesOnDescribe || relayCloseGate != null;
    final status = relayClosed
        ? ScenarioLabRelayDescriptionStatus.closed
        : ScenarioLabRelayDescriptionStatus.ready;
    final Object response = switch (call.transport) {
      StudioLabRelayTransportAvailability.v1 => ScenarioLabRelayDescription(
        runId: binding.runId,
        status: status,
        descriptor: relayClosed ? null : descriptor,
      ).toJson(),
      StudioLabRelayTransportAvailability.v2 => ScenarioLabRelayDescriptionV2(
        runId: binding.runId,
        startRequestDigest: binding.startRequestDigest,
        status: status,
        descriptor: relayClosed ? null : descriptor,
        runtimeInputs: relayClosed ? null : binding.runtimeInputs,
        gatewayDataOrigin: !relayClosed && binding.requiresGateway
            ? Uri.parse('http://127.0.0.1:8090')
            : null,
      ).toJson(),
      StudioLabRelayTransportAvailability.unavailable =>
        throw const StudioLabRelayUnavailable(),
    };
    return decodeStudioLabRelayDescription(
      value: response,
      call: call,
      binding: binding,
    );
  }

  @override
  Future<ScenarioLabRelayPollResponse> nextLabRelayCommand(
    ScenarioLabRelayPollRequest request,
  ) => throw UnsupportedError('VM TargetFrame emits no Hello');

  @override
  Future<ScenarioLabRelayHelloAcknowledgement> submitLabRelayHello(
    ScenarioLabRelayHelloSubmission submission,
  ) => throw UnsupportedError('VM TargetFrame emits no Hello');

  @override
  Future<ScenarioLabRelayResultAcknowledgement> submitLabRelayResult(
    ScenarioLabRelayResultSubmission submission,
  ) => throw UnsupportedError('VM TargetFrame emits no Result');
}

Finder _domWithAttributes(Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM component with attributes $attributes',
    );

Finder _domWithTagAndAttributes(String tag, Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          component.tag == tag &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM <$tag> component with attributes $attributes',
    );

Finder _domWithAttribute(String attribute) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      (component.attributes?.containsKey(attribute) ?? false),
  description: 'DOM component with $attribute',
);

Finder _domAttributeContaining(String value) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      (component.attributes?.values.any((item) => item.contains(value)) ??
          false),
  description: 'DOM attribute containing a protected relay value',
);

Finder _scenarioSurfaceWithInlineStyles() => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      component.styles != null &&
      (component.classes
              ?.split(RegExp(r'\s+'))
              .any(
                (name) =>
                    name.startsWith('scenario-surface') ||
                    name.startsWith('scenario-lab') ||
                    name.startsWith('scenario-quality'),
              ) ??
          false),
  description: 'Lab or Quality component with inline Styles',
);
