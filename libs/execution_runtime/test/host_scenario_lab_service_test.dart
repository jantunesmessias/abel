import 'dart:async';

import 'package:execution_runtime/src/gateway/gateway_sidecar_supervisor.dart';
import 'package:execution_runtime/src/lab/host_scenario_lab_service.dart';
import 'package:execution_runtime/src/lab/managed_process_scenario_lab_target.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_service.dart';
import 'package:execution_runtime/src/lab/scenario_lab_relay_broker.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test('idempotent start retry bypasses unavailable current content', () {
    var contentReads = 0;
    final fixture = _Fixture(
      readContent: () {
        contentReads += 1;
        throw StateError('Current Scenario Lab content was removed');
      },
    );

    final retry = fixture.host.start(fixture.request.toJson());

    expect(retry, fixture.store.requireRun(_runId).latestObservable.toJson());
    expect(ScenarioLabRunSnapshot.fromJson(retry).runId, _runId);
    expect(contentReads, 0);

    final divergent = ScenarioLabRunStartRequest(
      requestId: fixture.request.requestId,
      expectedContentSetDigest: fixture.request.expectedContentSetDigest,
      expectedScenarioLabManifestDigest:
          fixture.request.expectedScenarioLabManifestDigest,
      scenarioId: fixture.request.scenarioId,
      scriptId: fixture.request.scriptId,
      requestedAt: fixture.request.requestedAt.add(const Duration(seconds: 1)),
    );
    expect(() => fixture.host.start(divergent.toJson()), throwsStateError);
    expect(
      contentReads,
      0,
      reason: 'conflict must not read a newer generation',
    );
  });

  test('serves bounded current and catch-up views without relay material', () {
    final fixture = _Fixture()..appendStarting();
    final get = ScenarioLabRunSnapshot.fromJson(
      fixture.host.get(ScenarioLabRunReference(runId: _runId).toJson()),
    );
    expect(get.sequence, 1);

    final firstPage = ScenarioLabRunObservation.fromJson(
      fixture.host.observe(
        ScenarioLabRunObserveRequest(
          runId: _runId,
          afterSequence: -1,
          limit: 1,
        ).toJson(),
      ),
    );
    expect(firstPage.disposition, ScenarioLabRunDisposition.active);
    expect(firstPage.current.sequence, 1);
    expect(firstPage.observations.single.sequence, 0);
    expect(firstPage.hasMore, isTrue);
    expect(firstPage.toJson().toString(), isNot(contains(_nonce.value)));

    final secondPage = ScenarioLabRunObservation.fromJson(
      fixture.host.observe(
        ScenarioLabRunObserveRequest(
          runId: _runId,
          afterSequence: 0,
          limit: 1,
        ).toJson(),
      ),
    );
    expect(secondPage.observations.single.sequence, 1);
    expect(secondPage.hasMore, isFalse);
    expect(
      () => fixture.host.observe(
        ScenarioLabRunObserveRequest(runId: _runId, afterSequence: 2).toJson(),
      ),
      throwsStateError,
    );
  });

  test('relays one authorized command only through request/response', () async {
    final fixture = _Fixture();
    expect(
      ScenarioLabRelayDescription.fromJson(
        fixture.host.describeRelay(<String, Object?>{'runId': _runId.value}),
      ).status,
      ScenarioLabRelayDescriptionStatus.pending,
    );
    final descriptor = _descriptor();
    fixture.broker.open(descriptor);
    expect(
      ScenarioLabRelayDescription.fromJson(
        fixture.host.describeRelay(<String, Object?>{'runId': _runId.value}),
      ).descriptor?.digest,
      descriptor.digest,
    );

    final hello = _hello();
    final helloAck = ScenarioLabRelayHelloAcknowledgement.fromJson(
      fixture.host.acceptRelayHello(
        ScenarioLabRelayHelloSubmission(
          descriptorDigest: descriptor.digest,
          hello: hello,
        ).toJson(),
      ),
    );
    expect(helloAck.acceptedHelloDigest, hello.digest);

    final command = _command();
    final dispatched = fixture.broker.dispatch(command);
    final poll = ScenarioLabRelayPollResponse.fromJson(
      await fixture.host.nextRelayCommand(
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          waitMs: 0,
        ).toJson(),
      ),
    );
    expect(poll.state, ScenarioLabRelayPollState.command);
    expect(poll.command?.commandDigest, command.commandDigest);

    final result = _result(command);
    final resultAck = ScenarioLabRelayResultAcknowledgement.fromJson(
      fixture.host.acceptRelayResult(
        ScenarioLabRelayResultSubmission(
          descriptorDigest: descriptor.digest,
          result: result,
        ).toJson(),
      ),
    );
    expect(resultAck.acceptedResultDigest, result.resultDigest);
    expect((await dispatched).resultDigest, result.resultDigest);
    final idle = ScenarioLabRelayPollResponse.fromJson(
      await fixture.host.nextRelayCommand(
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 1,
          waitMs: 0,
        ).toJson(),
      ),
    );
    expect(idle.state, ScenarioLabRelayPollState.idle);
  });

  test('returns a fenced closed poll after the target detaches', () async {
    final fixture = _Fixture();
    final descriptor = _descriptor();
    fixture.broker
      ..open(descriptor)
      ..acceptHello(_hello());
    expect(
      ScenarioLabRelayDescription.fromJson(
        fixture.host.describeRelay(<String, Object?>{'runId': _runId.value}),
      ).descriptor?.digest,
      descriptor.digest,
    );

    fixture.broker.close(_runId);
    final closed = ScenarioLabRelayPollResponse.fromJson(
      await fixture.host.nextRelayCommand(
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          waitMs: 0,
        ).toJson(),
      ),
    );

    expect(closed.state, ScenarioLabRelayPollState.closed);
    await expectLater(
      fixture.host.nextRelayCommand(
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: Digest.semantic('wrong-descriptor'),
          afterSequence: 0,
          waitMs: 0,
        ).toJson(),
      ),
      throwsStateError,
    );
  });

  test('rejects a late result after relay revocation', () async {
    final fixture = _Fixture();
    final descriptor = _descriptor();
    fixture.broker
      ..open(descriptor)
      ..acceptHello(_hello());
    final command = _command();
    final dispatched = fixture.broker.dispatch(command);
    final before = fixture.store.requireRun(_runId).latest.digest;

    fixture.broker.close(_runId);

    await expectLater(dispatched, throwsA(isA<ScenarioLabRelayClosed>()));
    expect(
      () => fixture.host.acceptRelayResult(
        ScenarioLabRelayResultSubmission(
          descriptorDigest: descriptor.digest,
          result: _result(command),
        ).toJson(),
      ),
      throwsStateError,
    );
    expect(fixture.store.requireRun(_runId).latest.digest, before);
    expect(fixture.broker.activeCount, 0);
  });

  test('terminal v1 run revokes a pending command before poll', () async {
    final fixture = _Fixture()..appendStarting();
    final descriptor = _descriptor();
    fixture.broker
      ..open(descriptor)
      ..acceptHello(_hello());
    final command = _command();
    final dispatch = fixture.broker.dispatch(command);
    final dispatchClosed = expectLater(
      dispatch,
      throwsA(isA<ScenarioLabRelayClosed>()),
    );
    final terminal = _terminalSnapshot(fixture);
    fixture.store
      ..append(terminal)
      ..complete(_terminalResult(terminal));

    final description = ScenarioLabRelayDescription.fromJson(
      fixture.host.describeRelay(<String, Object?>{'runId': _runId.value}),
    );
    final poll = ScenarioLabRelayPollResponse.fromJson(
      await fixture.host.nextRelayCommand(
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          waitMs: 0,
        ).toJson(),
      ),
    );

    expect(description.status, ScenarioLabRelayDescriptionStatus.closed);
    expect(poll.state, ScenarioLabRelayPollState.closed);
    expect(poll.command, isNull);
    expect(fixture.broker.activeCount, 0);
    await dispatchClosed;
  });

  test(
    'interruption during a pending v2 poll cannot release command',
    () async {
      final fixture = _Fixture()..appendStarting();
      final descriptor = _descriptor();
      fixture.broker
        ..open(descriptor)
        ..acceptHello(_hello());
      final command = _command();
      final dispatch = fixture.broker.dispatch(command);
      final dispatchClosed = expectLater(
        dispatch,
        throwsA(isA<ScenarioLabRelayClosed>()),
      );

      final pollFuture = fixture.host.nextRelayCommand(
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          waitMs: 0,
        ).toJson(),
      );
      expect(fixture.store.interrupt(_runId), isTrue);
      final poll = ScenarioLabRelayPollResponse.fromJson(await pollFuture);
      final description = ScenarioLabRelayDescriptionV2.fromJson(
        fixture.host.describeRelayV2(
          ScenarioLabRelayDescribeRequestV2(
            runId: _runId,
            expectedStartRequestDigest: fixture.request.digest,
          ).toJson(),
        ),
      );

      expect(poll.state, ScenarioLabRelayPollState.closed);
      expect(poll.command, isNull);
      expect(description.status, ScenarioLabRelayDescriptionStatus.closed);
      expect(fixture.broker.activeCount, 0);
      await dispatchClosed;
    },
  );

  test('serves a fenced v2 description from Host-owned run state', () {
    final fixture = _Fixture()..appendStarting();
    final descriptor = _descriptor();
    fixture.broker.open(descriptor);
    final request = ScenarioLabRelayDescribeRequestV2(
      runId: _runId,
      expectedStartRequestDigest: fixture.request.digest,
    );

    final description = ScenarioLabRelayDescriptionV2.fromJson(
      fixture.host.describeRelayV2(request.toJson()),
    );

    description.validateAgainst(request);
    expect(description.status, ScenarioLabRelayDescriptionStatus.ready);
    expect(description.descriptor!.toJson(), descriptor.toJson());
    expect(description.runtimeInputs!.digest, fixture.runtimeInputs.digest);
    expect(description.gatewayDataOrigin, isNull);
    expect(description.requiresGateway, isFalse);
    expect(
      () => fixture.host.describeRelayV2(<String, Object?>{
        ...request.toJson(),
        'gatewayDataOrigin': 'http://127.0.0.1:1',
      }),
      throwsFormatException,
    );
    expect(
      () => fixture.host.describeRelayV2(
        ScenarioLabRelayDescribeRequestV2(
          runId: _runId,
          expectedStartRequestDigest: Digest.semantic('another-start'),
        ).toJson(),
      ),
      throwsStateError,
    );
  });

  test('replacement owner closes every surface and pending command', () async {
    final fixture = _Fixture()..appendStarting();
    final descriptor = _descriptor();
    fixture.broker
      ..open(descriptor)
      ..acceptHello(_hello());
    final dispatch = fixture.broker.dispatch(_command());
    final dispatchClosed = expectLater(
      dispatch,
      throwsA(isA<ScenarioLabRelayClosed>()),
    );
    final replacementExecution = ScenarioLabExecutionService(
      store: fixture.store,
      clock: _Clock(),
      identities: _Identities(),
      target: _Target(fixture.runtimeInputs),
      deadlines: _Deadlines(),
    );
    final replacement = HostScenarioLabService(
      execution: replacementExecution,
      readContent: () => HostScenarioLabContent(
        identity: fixture.content.identity,
        catalog: fixture.content.catalog,
        manifest: fixture.content.manifest,
      ),
      relay: fixture.broker,
      readResolvedRuntimeInputs: (_) => fixture.runtimeInputs,
      readManagedLaunchContext: (_) => fixture.launchContext,
    );
    final v2Request = ScenarioLabRelayDescribeRequestV2(
      runId: _runId,
      expectedStartRequestDigest: fixture.request.digest,
    );

    final observation = ScenarioLabRunObservation.fromJson(
      replacement.observe(
        ScenarioLabRunObserveRequest(runId: _runId, afterSequence: -1).toJson(),
      ),
    );
    final v1 = ScenarioLabRelayDescription.fromJson(
      replacement.describeRelay(<String, Object?>{'runId': _runId.value}),
    );
    final v2 = ScenarioLabRelayDescriptionV2.fromJson(
      replacement.describeRelayV2(v2Request.toJson()),
    );
    final poll = ScenarioLabRelayPollResponse.fromJson(
      await replacement.nextRelayCommand(
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          waitMs: 0,
        ).toJson(),
      ),
    );

    expect(observation.disposition, ScenarioLabRunDisposition.interrupted);
    expect(v1.status, ScenarioLabRelayDescriptionStatus.closed);
    expect(v2.status, ScenarioLabRelayDescriptionStatus.closed);
    expect(poll.state, ScenarioLabRelayPollState.closed);
    expect(poll.command, isNull);
    expect(fixture.broker.activeCount, 0);
    await dispatchClosed;
  });

  test(
    'failed-closed terminal preparation revokes a pending command',
    () async {
      final fixture = _Fixture()..appendStarting();
      final descriptor = _descriptor();
      fixture.broker
        ..open(descriptor)
        ..acceptHello(_hello());
      final command = _command();
      final dispatch = fixture.broker.dispatch(command);
      final dispatchClosed = expectLater(
        dispatch,
        throwsA(isA<ScenarioLabRelayClosed>()),
      );
      fixture.store.append(_terminalSnapshot(fixture));
      final request = ScenarioLabRelayDescribeRequestV2(
        runId: _runId,
        expectedStartRequestDigest: fixture.request.digest,
      );

      final observation = ScenarioLabRunObservation.fromJson(
        fixture.host.observe(
          ScenarioLabRunObserveRequest(
            runId: _runId,
            afterSequence: -1,
          ).toJson(),
        ),
      );
      final description = ScenarioLabRelayDescriptionV2.fromJson(
        fixture.host.describeRelayV2(request.toJson()),
      );
      final poll = ScenarioLabRelayPollResponse.fromJson(
        await fixture.host.nextRelayCommand(
          ScenarioLabRelayPollRequest(
            runId: _runId,
            descriptorDigest: descriptor.digest,
            afterSequence: 0,
            waitMs: 0,
          ).toJson(),
        ),
      );

      expect(observation.disposition, ScenarioLabRunDisposition.interrupted);
      expect(observation.current.state.isTerminal, isFalse);
      expect(observation.result, isNull);
      expect(description.status, ScenarioLabRelayDescriptionStatus.closed);
      expect(description.descriptor, isNull);
      expect(poll.state, ScenarioLabRelayPollState.closed);
      expect(poll.command, isNull);
      expect(fixture.broker.activeCount, 0);
      expect(
        () => fixture.host.acceptRelayHello(
          ScenarioLabRelayHelloSubmission(
            descriptorDigest: _descriptor().digest,
            hello: _hello(),
          ).toJson(),
        ),
        throwsStateError,
      );
      await dispatchClosed;
    },
  );

  test('Gateway-bound runs reject v1 in pending, ready and closed states', () {
    final fixture = _Fixture(gateway: true);
    final v1 = <String, Object?>{'runId': _runId.value};
    final v2 = ScenarioLabRelayDescribeRequestV2(
      runId: _runId,
      expectedStartRequestDigest: fixture.request.digest,
    );

    expect(() => fixture.host.describeRelay(v1), throwsStateError);
    final pending = ScenarioLabRelayDescriptionV2.fromJson(
      fixture.host.describeRelayV2(v2.toJson()),
    );
    expect(pending.status, ScenarioLabRelayDescriptionStatus.pending);
    expect(pending.descriptor, isNull);
    expect(pending.runtimeInputs, isNull);
    expect(pending.gatewayDataOrigin, isNull);

    fixture
      ..appendStarting()
      ..broker.open(_descriptor());
    expect(() => fixture.host.describeRelay(v1), throwsStateError);
    final ready = ScenarioLabRelayDescriptionV2.fromJson(
      fixture.host.describeRelayV2(v2.toJson()),
    );
    expect(ready.status, ScenarioLabRelayDescriptionStatus.ready);
    expect(ready.runtimeInputs!.digest, fixture.runtimeInputs.digest);
    expect(ready.gatewayDataOrigin, Uri.parse('http://127.0.0.1:9393'));
    expect(ready.requiresGateway, isTrue);

    fixture.store.interrupt(_runId);
    expect(() => fixture.host.describeRelay(v1), throwsStateError);
    final closed = ScenarioLabRelayDescriptionV2.fromJson(
      fixture.host.describeRelayV2(v2.toJson()),
    );
    expect(closed.status, ScenarioLabRelayDescriptionStatus.closed);
    expect(closed.descriptor, isNull);
    expect(closed.runtimeInputs, isNull);
    expect(closed.gatewayDataOrigin, isNull);
  });

  test('v2 fails closed when managed launch bindings disagree', () {
    final fixture = _Fixture(
      launchContextFingerprint: _executionFingerprint(targetId: 'other-target'),
    )..appendStarting();
    fixture.broker.open(_descriptor());

    expect(
      () => fixture.host.describeRelayV2(
        ScenarioLabRelayDescribeRequestV2(
          runId: _runId,
          expectedStartRequestDigest: fixture.request.digest,
        ).toJson(),
      ),
      throwsStateError,
    );

    final alteredDescriptor = _Fixture()..appendStarting();
    alteredDescriptor.broker.open(_descriptor(launchProfileId: 'another-web'));
    expect(
      () => alteredDescriptor.host.describeRelayV2(
        ScenarioLabRelayDescribeRequestV2(
          runId: _runId,
          expectedStartRequestDigest: alteredDescriptor.request.digest,
        ).toJson(),
      ),
      throwsStateError,
    );
  });

  test(
    'fails closed for altered descriptor, stale sequence and closed run',
    () async {
      final fixture = _Fixture();
      final descriptor = _descriptor();
      fixture.broker
        ..open(descriptor)
        ..acceptHello(_hello());

      final wrongDigest = Digest.semantic('wrong-descriptor');
      expect(
        () => fixture.host.acceptRelayHello(
          ScenarioLabRelayHelloSubmission(
            descriptorDigest: wrongDigest,
            hello: _hello(),
          ).toJson(),
        ),
        throwsFormatException,
      );
      await expectLater(
        fixture.host.nextRelayCommand(
          ScenarioLabRelayPollRequest(
            runId: _runId,
            descriptorDigest: descriptor.digest,
            afterSequence: 1,
            waitMs: 0,
          ).toJson(),
        ),
        throwsStateError,
      );

      fixture.store.interrupt(_runId);
      expect(
        ScenarioLabRelayDescription.fromJson(
          fixture.host.describeRelay(<String, Object?>{'runId': _runId.value}),
        ).status,
        ScenarioLabRelayDescriptionStatus.closed,
      );
      expect(
        () => fixture.host.describeRelay(const <String, Object?>{
          'runId': 'unknown-run',
        }),
        throwsStateError,
      );
      expect(
        () => fixture.host.cancel(
          ScenarioLabRunReference(
            runId: ScenarioLabRunId('unknown-run'),
          ).toJson(),
        ),
        throwsStateError,
      );
    },
  );
}

final ScenarioLabRunId _runId = ScenarioLabRunId('run-00000001');
final AppAdapterRelayNonce _nonce = AppAdapterRelayNonce(
  'relay-nonce-000000000001',
);
final DateTime _time = DateTime.utc(2026, 8, 14, 12);

final class _TestContent {
  const _TestContent({
    required this.catalog,
    required this.manifest,
    required this.identity,
    required this.request,
  });

  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
  final ExperienceContentSetIdentity identity;
  final ScenarioLabRunStartRequest request;
}

_TestContent _content({required bool gateway}) {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('application');
  final scenarioId = ScenarioId('scenario-ready');
  final bindingId = ScenarioExecutionBindingId('binding-ready');
  final scriptId = ScenarioScriptId('script-ready');
  final catalog = CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Application',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(id: scenarioId, applicationId: applicationId, title: 'Ready'),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: bindingId,
        scenarioId: scenarioId,
        targetId: 'target-web',
        launchProfileId: 'sample-web',
        gatewayPresetId: gateway ? 'delivery-ready' : null,
      ),
    ],
  );
  final manifest = ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: const <CapabilityDescriptor>[],
    controls: const <ScenarioControlDefinition>[],
    operations: const <ScenarioLabOperationDefinition>[],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: scriptId,
        scenarioId: scenarioId,
        displayName: 'Ready',
        timeoutMs: 30000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'step-ready',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
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
  final identity = ExperienceContentSetIdentity(
    revision: 1,
    catalogDigest: catalog.digest,
    workspaceSnapshotDigest: Digest.semantic('workspace-snapshot'),
    workspaceContentDigest: Digest.semantic('workspace-content'),
    scenarioLabManifestDigest: manifest.digest,
  );
  return _TestContent(
    catalog: catalog,
    manifest: manifest,
    identity: identity,
    request: ScenarioLabRunStartRequest(
      requestId: ScenarioLabRunRequestId('request-00000001'),
      expectedContentSetDigest: identity.contentSetDigest,
      expectedScenarioLabManifestDigest: manifest.digest,
      scenarioId: scenarioId,
      scriptId: scriptId,
      requestedAt: _time,
    ),
  );
}

final class _Fixture {
  _Fixture({
    bool gateway = false,
    ExecutionFingerprint? launchContextFingerprint,
    HostScenarioLabContentReader? readContent,
  }) {
    content = _content(gateway: gateway);
    request = content.request;
    runtimeInputs = _runtimeInputs(
      gateway: gateway,
      catalogDigest: content.catalog.digest,
    );
    launchContext = ScenarioLabManagedLaunchContext(
      targetOrigin: _descriptor().origin,
      executionFingerprint:
          launchContextFingerprint ??
          _executionFingerprint(catalogDigest: content.catalog.digest),
      gateway: gateway
          ? GatewaySidecarHandle(
              id: 'gateway-test-000001',
              ownerSessionId: 'scenario-lab-${_runId.value}',
              dataOrigin: Uri.parse('http://127.0.0.1:9393/'),
              planDigest: _gatewayPlanDigest,
              routingTableDigest: _routingTableDigest,
            )
          : null,
    );
    execution = ScenarioLabExecutionService(
      store: store,
      clock: _Clock(),
      identities: _Identities(),
      target: _Target(runtimeInputs),
      deadlines: _Deadlines(),
    );
    final started = execution.start(
      request: request,
      contentSet: content.identity,
      catalog: content.catalog,
      manifest: content.manifest,
    );
    if (started.snapshot.runId != _runId) {
      throw StateError('Host Scenario Lab fixture run identity changed');
    }
    host = HostScenarioLabService(
      execution: execution,
      readContent:
          readContent ??
          () => HostScenarioLabContent(
            identity: content.identity,
            catalog: content.catalog,
            manifest: content.manifest,
          ),
      relay: broker,
      readResolvedRuntimeInputs: (_) => runtimeInputs,
      readManagedLaunchContext: (_) => launchContext,
    );
  }

  final InMemoryScenarioLabRunStore store = InMemoryScenarioLabRunStore();
  final ScenarioLabRelayBroker broker = ScenarioLabRelayBroker();
  late final ScenarioLabExecutionService execution;
  late final HostScenarioLabService host;
  late final _TestContent content;
  late final ScenarioLabRunStartRequest request;
  late final ScenarioLabRuntimeInputBinding runtimeInputs;
  late final ScenarioLabManagedLaunchContext launchContext;

  void appendStarting() {
    final latest = store.requireRun(_runId).latest;
    if (latest.state != ScenarioLabRunState.starting) {
      throw StateError('Host Scenario Lab fixture did not reach starting');
    }
  }
}

ScenarioLabRunSnapshot _terminalSnapshot(_Fixture fixture) {
  final previous = fixture.store.requireRun(_runId).latest;
  return ScenarioLabRunSnapshot(
    runId: previous.runId,
    startRequestDigest: previous.startRequestDigest,
    contentSetDigest: previous.contentSetDigest,
    catalogDigest: previous.catalogDigest,
    scenarioLabManifestDigest: previous.scenarioLabManifestDigest,
    scenarioId: previous.scenarioId,
    scriptId: previous.scriptId,
    sequence: previous.sequence + 1,
    observedAt: previous.observedAt.add(const Duration(seconds: 1)),
    state: ScenarioLabRunState.failed,
    runtimeInputs: previous.runtimeInputs,
    steps: <ScenarioLabStepSnapshot>[
      ScenarioLabStepSnapshot(
        stepId: previous.steps.single.stepId,
        state: ScenarioLabStepState.failed,
        startedAt: previous.steps.single.startedAt,
        completedAt: previous.observedAt.add(const Duration(seconds: 1)),
        terminalCause: ScenarioLabStepTerminalCause.operationFailed,
      ),
    ],
    controls: previous.controls,
    requiredEvidence: previous.requiredEvidence,
    automatedAcceptance: previous.automatedAcceptance,
    comparisons: previous.comparisons,
    cleanup: ScenarioLabCleanupResult(
      state: ScenarioLabCleanupState.notRequired,
    ),
    terminalCause: ScenarioLabTerminalCause.internalError,
  );
}

ScenarioLabRunResult _terminalResult(ScenarioLabRunSnapshot terminal) =>
    ScenarioLabRunResult(
      finalSnapshot: terminal,
      startedAt: _time.add(const Duration(seconds: 1)),
      completedAt: terminal.observedAt,
      verificationState: VerificationState.notRun,
    );

ScenarioLabRelayTargetDescriptor _descriptor({
  String launchProfileId = 'sample-web',
}) => ScenarioLabRelayTargetDescriptor(
  runId: _runId,
  targetId: 'target-web',
  launchProfileId: launchProfileId,
  launchAttemptId: TargetLaunchAttemptId('launch-attempt-00000001'),
  origin: Uri.parse('http://127.0.0.1:8181'),
  nonce: _nonce,
);

final Digest _gatewayPlanDigest = Digest.semantic('gateway-plan');
final Digest _routingTableDigest = Digest.semantic('routing-table');

ScenarioLabRuntimeInputBinding _runtimeInputs({
  required bool gateway,
  required Digest catalogDigest,
}) => ScenarioLabRuntimeInputBinding(
  executionFingerprintDigest: _executionFingerprint(
    catalogDigest: catalogDigest,
  ).digest,
  executionTargetId: 'target-web',
  gatewayPresetId: gateway ? GatewayPresetId('delivery-ready') : null,
  compiledGatewayPlanDigest: gateway ? _gatewayPlanDigest : null,
  routingTableDigest: gateway ? _routingTableDigest : null,
);

ExecutionFingerprint _executionFingerprint({
  String targetId = 'target-web',
  Digest? catalogDigest,
}) => ExecutionFingerprint(
  catalogDigest: catalogDigest ?? _content(gateway: false).catalog.digest,
  launchProfileId: 'sample-web',
  targetId: targetId,
  platform: 'web',
  renderer: 'flutter-web',
  runtimeFidelity: RuntimeFidelity.simulated,
  backendMode: BackendMode.none,
  networkContainment: NetworkContainment.unconstrained,
  bootstrapAssessment: BootstrapAssessment.declared,
  toolchain: const <String, String>{'dart': 'test'},
  capabilities: const <String>{'app-adapter.relay'},
);

final AppAdapterCapabilityReference _capability = AppAdapterCapabilityReference(
  id: AppAdapterCapabilityId('sample.ready-control'),
  version: 1,
);

AppAdapterRelayHello _hello() => AppAdapterRelayHello(
  runId: _runId,
  adapterInstanceId: 'adapter-instance-1',
  sequence: 0,
  nonce: _nonce,
  capabilities: <AppAdapterCapabilityReference>[_capability],
);

ReadAppAdapterRelayCommand _command() => ReadAppAdapterRelayCommand(
  runId: _runId,
  commandId: ScenarioLabCommandId('command-00000001'),
  sequence: 1,
  nonce: _nonce,
  controlId: ScenarioControlId('ready-control'),
  capability: _capability,
  operationId: CapabilityOperationId('read'),
);

ReadAppAdapterRelayResult _result(ReadAppAdapterRelayCommand command) =>
    ReadAppAdapterRelayResult(
      runId: command.runId,
      commandId: command.commandId,
      sequence: command.sequence,
      nonce: command.nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(true),
    );

final class _Clock implements Clock {
  @override
  int monotonicMicroseconds() => 0;

  @override
  DateTime nowUtc() => _time;
}

final class _Identities implements ScenarioLabExecutionIdentityPort {
  @override
  ScenarioLabCommandId nextCommandId() =>
      ScenarioLabCommandId('unused-command');

  @override
  AppAdapterRelayNonce nextRelayNonce() => _nonce;

  @override
  ScenarioLabRunId nextRunId() => _runId;
}

final class _Deadlines implements ScenarioLabDeadlinePort {
  @override
  Future<T> run<T>({
    required Duration timeout,
    required Future<T> Function() action,
  }) => action();
}

final class _Target implements ScenarioLabTargetPort {
  _Target(this.runtimeInputs);

  final ScenarioLabRuntimeInputBinding runtimeInputs;

  @override
  Future<void> abort(ScenarioLabRunId runId) async {}

  @override
  Future<ScenarioLabTargetSession> attach({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
    required AppAdapterRelayNonce nonce,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    await cancellation.whenCancelled;
    throw const ScenarioLabTargetCancelled();
  }

  @override
  ScenarioLabRuntimeInputBinding resolveRuntimeInputs({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
  }) => runtimeInputs;
}
