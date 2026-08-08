import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/lab/scenario_lab_run_controller.dart';
import 'package:studio/src/lab/studio_scenario_lab_run_transport.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  late ScenarioLabTestFixture fixture;
  late ExperienceContentSetIdentity identity;
  late ScenarioLabRunStartRequest request;

  setUp(() {
    fixture = ScenarioLabTestFixture();
    identity = _identity(fixture);
    request = _request(fixture, identity);
  });

  test('requires a matching atomic content generation', () {
    expect(
      () => ScenarioLabRunController(
        host: null,
        contentIdentity: ExperienceContentSetIdentity(
          revision: 1,
          catalogDigest: digest('another-catalog'),
          workspaceSnapshotDigest: digest('workspace'),
          workspaceContentDigest: digest('workspace-content'),
          scenarioLabManifestDigest: fixture.manifest.digest,
        ),
        manifest: fixture.manifest,
      ),
      throwsArgumentError,
    );
    expect(
      () => ScenarioLabRunController(
        host: null,
        contentIdentity: identity,
        manifest: fixture.manifest,
        reattachPageSize: 101,
      ),
      throwsArgumentError,
    );
  });

  test(
    'reports both absent and unavailable Host lifecycle explicitly',
    () async {
      final absent = _controller(
        fixture: fixture,
        identity: identity,
        host: null,
      );
      await absent.start(request);
      expect(absent.status, ScenarioLabRunControllerStatus.unavailable);
      expect(absent.snapshot.failure, isNull);

      final unavailable = _controller(
        fixture: fixture,
        identity: identity,
        host: _RunHost(startError: const StudioScenarioLabRunUnavailable()),
      );
      await unavailable.start(request);
      expect(unavailable.status, ScenarioLabRunControllerStatus.unavailable);
      expect(unavailable.current, isNull);
    },
  );

  test('starts, polls and cancels only the same fenced run', () async {
    final queued = _snapshot(fixture, identity, request, sequence: 0);
    final running = _snapshot(fixture, identity, request, sequence: 1);
    final cancelled = _snapshot(
      fixture,
      identity,
      request,
      sequence: 2,
      state: ScenarioLabRunState.cancelled,
    );
    final host = _RunHost(
      startResponses: <ScenarioLabRunSnapshot>[queued],
      getResponses: <ScenarioLabRunSnapshot>[running],
      cancelResponses: <ScenarioLabRunSnapshot>[cancelled],
    );
    final observed = <ScenarioLabRunControllerSnapshot>[];
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: host,
      listener: observed.add,
    );

    await controller.start(request);
    expect(controller.status, ScenarioLabRunControllerStatus.nonTerminal);
    expect(controller.snapshot.disposition, isNull);
    expect(host.startRequests.single.digest, request.digest);

    await controller.poll();
    expect(controller.current?.sequence, 1);
    expect(host.getReferences.single.runId, _runId);

    await controller.cancel();
    expect(controller.status, ScenarioLabRunControllerStatus.terminal);
    expect(controller.current?.state, ScenarioLabRunState.cancelled);
    expect(host.cancelReferences.single.runId, _runId);
    expect(controller.result, isNull);
    expect(observed.last.failure, isNull);
  });

  test('cancel epoch ignores a superseded late poll response', () async {
    final queued = _snapshot(fixture, identity, request, sequence: 0);
    final latePoll = Completer<ScenarioLabRunSnapshot>();
    final cancelled = _snapshot(
      fixture,
      identity,
      request,
      sequence: 2,
      state: ScenarioLabRunState.cancelled,
    );
    final host = _RunHost(
      startResponses: <ScenarioLabRunSnapshot>[queued],
      pendingGet: latePoll,
      cancelResponses: <ScenarioLabRunSnapshot>[cancelled],
    );
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: host,
    );
    await controller.start(request);

    final poll = controller.poll();
    await _tick();
    expect(controller.status, ScenarioLabRunControllerStatus.polling);
    await controller.cancel();
    expect(controller.current?.sequence, 2);

    latePoll.complete(_snapshot(fixture, identity, request, sequence: 1));
    await poll;

    expect(controller.current?.sequence, 2);
    expect(controller.current?.state, ScenarioLabRunState.cancelled);
    expect(controller.status, ScenarioLabRunControllerStatus.terminal);
  });

  test('cancel waits for the first fenced reattach observation', () async {
    final latePage = Completer<ScenarioLabRunObservation>();
    final cancelled = _snapshot(
      fixture,
      identity,
      request,
      sequence: 1,
      state: ScenarioLabRunState.cancelled,
    );
    final host = _RunHost(
      pendingReattach: latePage,
      cancelResponses: <ScenarioLabRunSnapshot>[cancelled],
    );
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: host,
    );

    final reattach = controller.reattachKnownRun(
      runId: _runId,
      scenarioId: fixture.scenarioId,
      scriptId: fixture.scriptId,
      allowHistoricalTerminalContent: true,
    );
    await _tick();
    expect(controller.snapshot.runId, _runId);
    expect(controller.status, ScenarioLabRunControllerStatus.reattaching);

    await controller.cancel();
    expect(host.cancelReferences, isEmpty);
    expect(controller.status, ScenarioLabRunControllerStatus.reattaching);

    final queued = _snapshot(fixture, identity, request, sequence: 0);
    latePage.complete(
      ScenarioLabRunObservation(
        runId: _runId,
        disposition: ScenarioLabRunDisposition.active,
        afterSequence: -1,
        current: queued,
        observations: <ScenarioLabRunSnapshot>[queued],
        hasMore: false,
      ),
    );
    await reattach;

    expect(controller.status, ScenarioLabRunControllerStatus.active);
    expect(controller.current?.digest, queued.digest);

    await controller.cancel();
    expect(controller.status, ScenarioLabRunControllerStatus.terminal);
    expect(controller.current?.state, ScenarioLabRunState.cancelled);
    expect(controller.current?.digest, cancelled.digest);
    expect(host.cancelReferences.single.runId, _runId);
  });

  test(
    'reattaches through bounded contiguous pages and publishes result',
    () async {
      final snapshots = <ScenarioLabRunSnapshot>[
        for (var sequence = 0; sequence <= 3; sequence += 1)
          _snapshot(
            fixture,
            identity,
            request,
            sequence: sequence,
            state: sequence == 3
                ? ScenarioLabRunState.succeeded
                : sequence == 0
                ? ScenarioLabRunState.queued
                : ScenarioLabRunState.running,
          ),
      ];
      final result = _result(snapshots.last);
      final host = _RunHost(
        reattachResponses: <ScenarioLabRunObservation>[
          ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.terminal,
            afterSequence: -1,
            current: snapshots.last,
            observations: snapshots.take(2),
            hasMore: true,
            result: result,
          ),
          ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.terminal,
            afterSequence: 1,
            current: snapshots.last,
            observations: snapshots.skip(2),
            hasMore: false,
            result: result,
          ),
        ],
      );
      final controller = _controller(
        fixture: fixture,
        identity: identity,
        host: host,
        pageSize: 2,
        maxRetained: 3,
      );

      await controller.reattach(runId: _runId, request: request);

      expect(controller.status, ScenarioLabRunControllerStatus.terminal);
      expect(
        controller.snapshot.disposition,
        ScenarioLabRunDisposition.terminal,
      );
      expect(controller.result?.digest, result.digest);
      expect(controller.snapshot.resultDigest, result.digest);
      expect(host.observeRequests.map((item) => item.afterSequence), <int>[
        -1,
        1,
      ]);
      expect(host.observeRequests.every((item) => item.limit == 2), isTrue);
      expect(
        controller.retainedObservations.map((item) => item.sequence),
        <int>[1, 2, 3],
      );
      expect(controller.snapshot.historyTruncated, isTrue);
    },
  );

  test(
    'preserves interrupted as a distinct non-terminal observation',
    () async {
      final current = _snapshot(fixture, identity, request, sequence: 1);
      final host = _RunHost(
        reattachResponses: <ScenarioLabRunObservation>[
          ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.interrupted,
            afterSequence: -1,
            current: current,
            observations: <ScenarioLabRunSnapshot>[
              _snapshot(fixture, identity, request, sequence: 0),
              current,
            ],
            hasMore: false,
          ),
        ],
      );
      final controller = _controller(
        fixture: fixture,
        identity: identity,
        host: host,
      );

      await controller.reattach(runId: _runId, request: request);

      expect(controller.status, ScenarioLabRunControllerStatus.interrupted);
      expect(
        controller.snapshot.disposition,
        ScenarioLabRunDisposition.interrupted,
      );
      expect(controller.current?.state.isTerminal, isFalse);
      expect(controller.result, isNull);
    },
  );

  test(
    'reattaches after reload by fixing the first observed start digest',
    () async {
      final first = _snapshot(fixture, identity, request, sequence: 0);
      final current = _snapshot(fixture, identity, request, sequence: 1);
      final host = _RunHost(
        reattachResponses: <ScenarioLabRunObservation>[
          ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.active,
            afterSequence: -1,
            current: current,
            observations: <ScenarioLabRunSnapshot>[first, current],
            hasMore: false,
          ),
        ],
      );
      final controller = _controller(
        fixture: fixture,
        identity: identity,
        host: host,
      );

      await controller.reattachKnownRun(
        runId: _runId,
        scenarioId: fixture.scenarioId,
        scriptId: fixture.scriptId,
      );

      expect(controller.status, ScenarioLabRunControllerStatus.active);
      expect(controller.current?.startRequestDigest, request.digest);
      expect(controller.snapshot.runId, _runId);
    },
  );

  test(
    'Quality may reattach one historical terminal generation only',
    () async {
      final historicalIdentity = ExperienceContentSetIdentity(
        revision: identity.revision,
        catalogDigest: fixture.catalog.digest,
        workspaceSnapshotDigest: digest('historical-workspace-snapshot'),
        workspaceContentDigest: digest('historical-workspace-content'),
        scenarioLabManifestDigest: fixture.manifest.digest,
      );
      final historicalRequest = _request(fixture, historicalIdentity);
      final historical = <ScenarioLabRunSnapshot>[
        _snapshot(fixture, historicalIdentity, historicalRequest, sequence: 0),
        _snapshot(
          fixture,
          historicalIdentity,
          historicalRequest,
          sequence: 1,
          state: ScenarioLabRunState.succeeded,
        ),
      ];
      final result = _result(historical.last);
      ScenarioLabRunObservation response() => ScenarioLabRunObservation(
        runId: _runId,
        disposition: ScenarioLabRunDisposition.terminal,
        afterSequence: -1,
        current: historical.last,
        observations: historical,
        hasMore: false,
        result: result,
      );

      final strict = _controller(
        fixture: fixture,
        identity: identity,
        host: _RunHost(
          reattachResponses: <ScenarioLabRunObservation>[response()],
        ),
      );
      await strict.reattachKnownRun(
        runId: _runId,
        scenarioId: fixture.scenarioId,
        scriptId: fixture.scriptId,
      );
      expect(strict.status, ScenarioLabRunControllerStatus.failed);
      expect(
        strict.snapshot.failure,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );

      final historicalReview = _controller(
        fixture: fixture,
        identity: identity,
        host: _RunHost(
          reattachResponses: <ScenarioLabRunObservation>[response()],
        ),
      );
      await historicalReview.reattachKnownRun(
        runId: _runId,
        scenarioId: fixture.scenarioId,
        scriptId: fixture.scriptId,
        allowHistoricalTerminalContent: true,
      );
      expect(historicalReview.status, ScenarioLabRunControllerStatus.terminal);
      expect(
        historicalReview.current?.contentSetDigest,
        historicalIdentity.contentSetDigest,
      );
      expect(historicalReview.result?.digest, result.digest);
    },
  );

  test('historical reattach rejects a nonterminal run', () async {
    final historicalIdentity = ExperienceContentSetIdentity(
      revision: identity.revision,
      catalogDigest: fixture.catalog.digest,
      workspaceSnapshotDigest: digest('historical-active-workspace'),
      workspaceContentDigest: digest('historical-active-content'),
      scenarioLabManifestDigest: fixture.manifest.digest,
    );
    final historicalRequest = _request(fixture, historicalIdentity);
    final active = _snapshot(
      fixture,
      historicalIdentity,
      historicalRequest,
      sequence: 1,
    );
    final queued = _snapshot(
      fixture,
      historicalIdentity,
      historicalRequest,
      sequence: 0,
    );
    final host = _RunHost(
      reattachResponses: <ScenarioLabRunObservation>[
        ScenarioLabRunObservation(
          runId: _runId,
          disposition: ScenarioLabRunDisposition.active,
          afterSequence: -1,
          current: active,
          observations: <ScenarioLabRunSnapshot>[queued, active],
          hasMore: false,
        ),
      ],
    );
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: host,
    );

    await controller.reattachKnownRun(
      runId: _runId,
      scenarioId: fixture.scenarioId,
      scriptId: fixture.scriptId,
      allowHistoricalTerminalContent: true,
    );

    expect(controller.status, ScenarioLabRunControllerStatus.failed);
    expect(
      controller.snapshot.failure,
      ScenarioLabRunControllerFailure.fencingMismatch,
    );

    await controller.cancel();
    expect(host.cancelReferences, isEmpty);
  });

  test('historical reattach still rejects a different Catalog', () async {
    final historicalIdentity = ExperienceContentSetIdentity(
      revision: identity.revision,
      catalogDigest: fixture.catalog.digest,
      workspaceSnapshotDigest: digest('historical-catalog-workspace'),
      workspaceContentDigest: digest('historical-catalog-content'),
      scenarioLabManifestDigest: fixture.manifest.digest,
    );
    final historicalRequest = _request(fixture, historicalIdentity);
    final terminal = _snapshot(
      fixture,
      historicalIdentity,
      historicalRequest,
      sequence: 0,
      state: ScenarioLabRunState.succeeded,
      catalogDigest: digest('different-catalog'),
    );
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: _RunHost(
        reattachResponses: <ScenarioLabRunObservation>[
          ScenarioLabRunObservation(
            runId: _runId,
            disposition: ScenarioLabRunDisposition.terminal,
            afterSequence: -1,
            current: terminal,
            observations: <ScenarioLabRunSnapshot>[terminal],
            hasMore: false,
            result: _result(terminal),
          ),
        ],
      ),
    );

    await controller.reattachKnownRun(
      runId: _runId,
      scenarioId: fixture.scenarioId,
      scriptId: fixture.scriptId,
      allowHistoricalTerminalContent: true,
    );

    expect(controller.status, ScenarioLabRunControllerStatus.failed);
    expect(controller.current, isNull);
    expect(
      controller.snapshot.failure,
      ScenarioLabRunControllerFailure.fencingMismatch,
    );
  });

  test(
    'reload reattach rejects undeclared selection before transport',
    () async {
      final host = _RunHost();
      final controller = _controller(
        fixture: fixture,
        identity: identity,
        host: host,
      );

      await controller.reattachKnownRun(
        runId: _runId,
        scenarioId: ScenarioId('scenario-missing'),
        scriptId: fixture.scriptId,
      );

      expect(controller.status, ScenarioLabRunControllerStatus.failed);
      expect(
        controller.snapshot.failure,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
      expect(host.observeRequests, isEmpty);
    },
  );

  test('fails closed when bounded catch-up cannot be drained', () async {
    final current = _snapshot(fixture, identity, request, sequence: 2);
    final host = _RunHost(
      reattachResponses: <ScenarioLabRunObservation>[
        ScenarioLabRunObservation(
          runId: _runId,
          disposition: ScenarioLabRunDisposition.active,
          afterSequence: -1,
          current: current,
          observations: <ScenarioLabRunSnapshot>[
            _snapshot(fixture, identity, request, sequence: 0),
          ],
          hasMore: true,
        ),
      ],
    );
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: host,
      pageSize: 1,
      maxPages: 1,
    );

    await controller.reattach(runId: _runId, request: request);

    expect(controller.status, ScenarioLabRunControllerStatus.failed);
    expect(
      controller.snapshot.failure,
      ScenarioLabRunControllerFailure.paginationLimit,
    );
    expect(host.observeRequests, hasLength(1));
  });

  test('rejects start and snapshot content-fence mismatches', () async {
    final wrongRequest = ScenarioLabRunStartRequest(
      requestId: ScenarioLabRunRequestId('request-wrong'),
      expectedContentSetDigest: digest('wrong-content'),
      expectedScenarioLabManifestDigest: fixture.manifest.digest,
      scenarioId: fixture.scenarioId,
      scriptId: fixture.scriptId,
      requestedAt: time(0),
    );
    final unusedHost = _RunHost();
    final invalidRequestController = _controller(
      fixture: fixture,
      identity: identity,
      host: unusedHost,
    );
    await invalidRequestController.start(wrongRequest);
    expect(
      invalidRequestController.snapshot.failure,
      ScenarioLabRunControllerFailure.fencingMismatch,
    );
    expect(unusedHost.startRequests, isEmpty);

    final wrongCatalog = _snapshot(
      fixture,
      identity,
      request,
      sequence: 0,
      catalogDigest: digest('wrong-catalog'),
    );
    final responseController = _controller(
      fixture: fixture,
      identity: identity,
      host: _RunHost(startResponses: <ScenarioLabRunSnapshot>[wrongCatalog]),
    );
    await responseController.start(request);
    expect(
      responseController.snapshot.failure,
      ScenarioLabRunControllerFailure.fencingMismatch,
    );
  });

  test('rejects protocol rollback and altered immutable sequence', () async {
    final initial = _snapshot(fixture, identity, request, sequence: 1);
    final altered = _snapshot(
      fixture,
      identity,
      request,
      sequence: 1,
      observedMinute: 9,
    );
    final host = _RunHost(
      startResponses: <ScenarioLabRunSnapshot>[initial],
      getResponses: <ScenarioLabRunSnapshot>[altered],
    );
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: host,
    );
    await controller.start(request);
    await controller.poll();

    expect(controller.status, ScenarioLabRunControllerStatus.failed);
    expect(
      controller.snapshot.failure,
      ScenarioLabRunControllerFailure.protocolViolation,
    );
    expect(controller.current?.digest, initial.digest);
  });

  test('close clears typed material and ignores a late start', () async {
    final delayed = Completer<ScenarioLabRunSnapshot>();
    final controller = _controller(
      fixture: fixture,
      identity: identity,
      host: _RunHost(pendingStart: delayed),
    );
    final start = controller.start(request);
    await _tick();
    controller.close();

    delayed.complete(_snapshot(fixture, identity, request, sequence: 0));
    await start;

    expect(controller.status, ScenarioLabRunControllerStatus.closed);
    expect(controller.current, isNull);
    expect(controller.result, isNull);
    expect(controller.retainedObservations, isEmpty);
    expect(controller.snapshot.runId, isNull);
  });

  test(
    'maps wire decoding and transport failures to sanitized categories',
    () async {
      for (final entry in <(Object, ScenarioLabRunControllerFailure)>[
        (
          const StudioScenarioLabRunFencingMismatch(),
          ScenarioLabRunControllerFailure.fencingMismatch,
        ),
        (
          const FormatException('secret malformed bytes'),
          ScenarioLabRunControllerFailure.protocolViolation,
        ),
        (
          StateError('secret Host error'),
          ScenarioLabRunControllerFailure.transport,
        ),
      ]) {
        final controller = _controller(
          fixture: fixture,
          identity: identity,
          host: _RunHost(startError: entry.$1),
        );
        await controller.start(request);

        expect(controller.snapshot.failure, entry.$2);
        expect(controller.snapshot.toString(), isNot(contains('secret')));
      }
    },
  );

  test('Web codecs send direct closed documents and validate bindings', () {
    final queued = _snapshot(fixture, identity, request, sequence: 0);
    final reference = ScenarioLabRunReference(runId: _runId);
    final observe = ScenarioLabRunObserveRequest(
      runId: _runId,
      afterSequence: -1,
      limit: 1,
    );

    expect(encodeStudioScenarioLabRunStart(request), request.toJson());
    expect(encodeStudioScenarioLabRunReference(reference), reference.toJson());
    expect(encodeStudioScenarioLabRunObserve(observe), observe.toJson());
    expect(
      decodeStudioScenarioLabRunStart(queued.toJson(), request).digest,
      queued.digest,
    );
    expect(
      decodeStudioScenarioLabRunReferenceResponse(
        queued.toJson(),
        reference,
      ).runId,
      _runId,
    );

    final changedRequest = ScenarioLabRunStartRequest(
      requestId: request.requestId,
      expectedContentSetDigest: request.expectedContentSetDigest,
      expectedScenarioLabManifestDigest:
          request.expectedScenarioLabManifestDigest,
      scenarioId: request.scenarioId,
      scriptId: request.scriptId,
      requestedAt: time(1),
    );
    expect(
      () => decodeStudioScenarioLabRunStart(queued.toJson(), changedRequest),
      throwsA(isA<StudioScenarioLabRunFencingMismatch>()),
    );
    expect(
      () => decodeStudioScenarioLabRunReferenceResponse(
        queued.toJson(),
        ScenarioLabRunReference(runId: ScenarioLabRunId('run-00000002')),
      ),
      throwsFormatException,
    );
  });

  test('Web observation codec enforces the caller page limit', () {
    final first = _snapshot(fixture, identity, request, sequence: 0);
    final current = _snapshot(fixture, identity, request, sequence: 1);
    final response = ScenarioLabRunObservation(
      runId: _runId,
      disposition: ScenarioLabRunDisposition.active,
      afterSequence: -1,
      current: current,
      observations: <ScenarioLabRunSnapshot>[first, current],
      hasMore: false,
    );
    final requestLimitOne = ScenarioLabRunObserveRequest(
      runId: _runId,
      afterSequence: -1,
      limit: 1,
    );

    expect(
      () => decodeStudioScenarioLabRunObservation(
        response.toJson(),
        requestLimitOne,
      ),
      throwsFormatException,
    );

    final exactRequest = ScenarioLabRunObserveRequest(
      runId: _runId,
      afterSequence: -1,
      limit: 2,
    );
    expect(
      decodeStudioScenarioLabRunObservation(
        response.toJson(),
        exactRequest,
      ).digest,
      response.digest,
    );
  });
}

final ScenarioLabRunId _runId = ScenarioLabRunId('run-00000001');

ExperienceContentSetIdentity _identity(ScenarioLabTestFixture fixture) =>
    ExperienceContentSetIdentity(
      revision: 1,
      catalogDigest: fixture.catalog.digest,
      workspaceSnapshotDigest: digest('workspace-snapshot'),
      workspaceContentDigest: digest('workspace-content'),
      scenarioLabManifestDigest: fixture.manifest.digest,
    );

ScenarioLabRunStartRequest _request(
  ScenarioLabTestFixture fixture,
  ExperienceContentSetIdentity identity,
) => ScenarioLabRunStartRequest(
  requestId: ScenarioLabRunRequestId('request-00000001'),
  expectedContentSetDigest: identity.contentSetDigest,
  expectedScenarioLabManifestDigest: fixture.manifest.digest,
  scenarioId: fixture.scenarioId,
  scriptId: fixture.scriptId,
  requestedAt: time(0),
);

ScenarioLabRunSnapshot _snapshot(
  ScenarioLabTestFixture fixture,
  ExperienceContentSetIdentity identity,
  ScenarioLabRunStartRequest request, {
  required int sequence,
  ScenarioLabRunState? state,
  int? observedMinute,
  Digest? catalogDigest,
}) {
  final resolvedState =
      state ??
      (sequence == 0
          ? ScenarioLabRunState.queued
          : ScenarioLabRunState.running);
  final terminal = resolvedState.isTerminal;
  final cancelled = resolvedState == ScenarioLabRunState.cancelled;
  return ScenarioLabRunSnapshot(
    runId: _runId,
    startRequestDigest: request.digest,
    contentSetDigest: identity.contentSetDigest,
    catalogDigest: catalogDigest ?? fixture.catalog.digest,
    scenarioLabManifestDigest: fixture.manifest.digest,
    scenarioId: fixture.scenarioId,
    scriptId: fixture.scriptId,
    sequence: sequence,
    observedAt: time(observedMinute ?? sequence),
    state: resolvedState,
    runtimeInputs: resolvedState == ScenarioLabRunState.queued
        ? null
        : fixture.runtimeInputs,
    steps: <ScenarioLabStepSnapshot>[
      if (!terminal && resolvedState == ScenarioLabRunState.queued)
        pendingStep('bind')
      else if (!terminal)
        ScenarioLabStepSnapshot(
          stepId: 'bind',
          state: ScenarioLabStepState.running,
          startedAt: time(0),
        )
      else if (cancelled)
        ScenarioLabStepSnapshot(
          stepId: 'bind',
          state: ScenarioLabStepState.cancelled,
          completedAt: time(sequence),
          terminalCause: ScenarioLabStepTerminalCause.cancelled,
        )
      else
        completedStep('bind', 0, sequence),
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

ScenarioLabRunResult _result(ScenarioLabRunSnapshot snapshot) =>
    ScenarioLabRunResult(
      finalSnapshot: snapshot,
      startedAt: time(0),
      completedAt: time(snapshot.sequence),
      verificationState: VerificationState.notRun,
    );

ScenarioLabRunController _controller({
  required ScenarioLabTestFixture fixture,
  required ExperienceContentSetIdentity identity,
  required StudioHostScenarioLabRunClient? host,
  ScenarioLabRunStateListener? listener,
  int pageSize = 10,
  int maxPages = 20,
  int maxRetained = 200,
}) => ScenarioLabRunController(
  host: host,
  contentIdentity: identity,
  manifest: fixture.manifest,
  reattachPageSize: pageSize,
  maxReattachPages: maxPages,
  maxRetainedObservations: maxRetained,
  onStateChanged: listener,
);

final class _RunHost implements StudioHostScenarioLabRunClient {
  _RunHost({
    Iterable<ScenarioLabRunSnapshot> startResponses =
        const <ScenarioLabRunSnapshot>[],
    Iterable<ScenarioLabRunSnapshot> getResponses =
        const <ScenarioLabRunSnapshot>[],
    Iterable<ScenarioLabRunSnapshot> cancelResponses =
        const <ScenarioLabRunSnapshot>[],
    Iterable<ScenarioLabRunObservation> reattachResponses =
        const <ScenarioLabRunObservation>[],
    this.pendingStart,
    this.pendingGet,
    this.pendingReattach,
    this.startError,
  }) : startResponses = List<ScenarioLabRunSnapshot>.of(startResponses),
       getResponses = List<ScenarioLabRunSnapshot>.of(getResponses),
       cancelResponses = List<ScenarioLabRunSnapshot>.of(cancelResponses),
       reattachResponses = List<ScenarioLabRunObservation>.of(
         reattachResponses,
       );

  final List<ScenarioLabRunSnapshot> startResponses;
  final List<ScenarioLabRunSnapshot> getResponses;
  final List<ScenarioLabRunSnapshot> cancelResponses;
  final List<ScenarioLabRunObservation> reattachResponses;
  final Completer<ScenarioLabRunSnapshot>? pendingStart;
  final Completer<ScenarioLabRunSnapshot>? pendingGet;
  final Completer<ScenarioLabRunObservation>? pendingReattach;
  final Object? startError;

  final List<ScenarioLabRunStartRequest> startRequests =
      <ScenarioLabRunStartRequest>[];
  final List<ScenarioLabRunReference> getReferences =
      <ScenarioLabRunReference>[];
  final List<ScenarioLabRunReference> cancelReferences =
      <ScenarioLabRunReference>[];
  final List<ScenarioLabRunObserveRequest> observeRequests =
      <ScenarioLabRunObserveRequest>[];

  @override
  Future<ScenarioLabRunSnapshot> startScenarioLabRun(
    ScenarioLabRunStartRequest request,
  ) async {
    startRequests.add(request);
    final error = startError;
    if (error case final Exception exception) throw exception;
    if (error case final Error error) throw error;
    final pending = pendingStart;
    if (pending != null) return pending.future;
    return startResponses.removeAt(0);
  }

  @override
  Future<ScenarioLabRunSnapshot> getScenarioLabRun(
    ScenarioLabRunReference reference,
  ) async {
    getReferences.add(reference);
    final pending = pendingGet;
    if (pending != null) return pending.future;
    return getResponses.removeAt(0);
  }

  @override
  Future<ScenarioLabRunSnapshot> cancelScenarioLabRun(
    ScenarioLabRunReference reference,
  ) async {
    cancelReferences.add(reference);
    return cancelResponses.removeAt(0);
  }

  @override
  Future<ScenarioLabRunObservation> reattachScenarioLabRun(
    ScenarioLabRunObserveRequest request,
  ) async {
    observeRequests.add(request);
    final pending = pendingReattach;
    if (pending != null) return pending.future;
    return reattachResponses.removeAt(0);
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);
