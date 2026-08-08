import 'dart:async';
import 'dart:io';

import 'package:execution_runtime/src/lab/filesystem_scenario_lab_run_store.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/lab/scenario_lab_execution_service.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  group('ScenarioLabExecutionService', () {
    test(
      'starts idempotently and keeps snapshots and relay envelopes monotonic',
      () async {
        final fixture = _fixture();
        final store = InMemoryScenarioLabRunStore();
        final identities = _SequentialIdentities();
        final target = _FakeTarget();
        final service = _service(
          store: store,
          identities: identities,
          target: target,
        );

        final first = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        final retry = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );

        expect(first.created, isTrue);
        expect(retry.created, isFalse);
        expect(retry.snapshot.runId, first.snapshot.runId);
        expect(retry.disposition, ScenarioLabReattachDisposition.active);
        expect(retry.canResume, isTrue);
        final result = await service.waitForResult(first.snapshot.runId);
        final session = target.session!;

        expect(result.finalSnapshot.state, ScenarioLabRunState.succeeded);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.completed,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(
          result.finalSnapshot.cleanup.resetControlIds,
          <ScenarioControlId>[_controlId],
        );
        expect(
          result.finalSnapshot.automatedAcceptance.map(
            (item) => item.verificationState,
          ),
          everyElement(VerificationState.passed),
        );
        expect(session.commands.map((command) => command.sequence), <int>[
          1,
          2,
          3,
          4,
        ], reason: 'read, write, confirming read, cleanup reset');
        expect(
          session.commands.map((command) => command.commandId).toSet().length,
          session.commands.length,
        );
        expect(
          session.commands.map((command) => command.nonce).toSet(),
          <AppAdapterRelayNonce>{session.hello.nonce},
        );
        expect(target.attachCalls, 1);
        expect(identities.runCount, 1);
        final terminalRetry = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        expect(
          terminalRetry.disposition,
          ScenarioLabReattachDisposition.terminal,
        );
        expect(terminalRetry.canResume, isFalse);

        final history = store.requireRun(first.snapshot.runId).snapshots;
        expect(
          history.map((snapshot) => snapshot.sequence),
          List<int>.generate(history.length, (index) => index),
        );
        for (var index = 1; index < history.length; index += 1) {
          expect(
            history[index].observedAt.isBefore(history[index - 1].observedAt),
            isFalse,
          );
        }
        expect(
          () => store.append(result.finalSnapshot),
          throwsStateError,
          reason: 'a terminal observation cannot be appended or rewritten',
        );

        final conflicting = _request(
          fixture.contentSet,
          fixture.manifest,
          requestedAt: DateTime.utc(2026, 8, 14, 13),
        );
        expect(
          () => service.start(
            request: conflicting,
            contentSet: fixture.contentSet,
            catalog: fixture.catalog,
            manifest: fixture.manifest,
          ),
          throwsA(isA<ScenarioLabRequestConflict>()),
        );
      },
    );

    test('a lost write response still triggers conservative cleanup', () async {
      final fixture = _fixture();
      final target = _FakeTarget(disconnectAfterWriteAtSequence: 2);
      final service = _service(target: target);
      final start = service.start(
        request: fixture.request,
        contentSet: fixture.contentSet,
        catalog: fixture.catalog,
        manifest: fixture.manifest,
      );

      final result = await service.waitForResult(start.snapshot.runId);

      expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
      expect(
        result.finalSnapshot.terminalCause,
        ScenarioLabTerminalCause.adapterDisconnected,
      );
      expect(
        result.finalSnapshot.cleanup.state,
        ScenarioLabCleanupState.succeeded,
      );
      expect(target.session!.value, isFalse);
      expect(
        target.session!.commands.map((command) => command.operation),
        <AppAdapterRelayOperation>[
          AppAdapterRelayOperation.read,
          AppAdapterRelayOperation.write,
          AppAdapterRelayOperation.reset,
        ],
      );
    });

    test('runs unchanged through the durable store boundary', () async {
      final root = Directory.systemTemp.createTempSync(
        'workspace-lab-service-store-',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final fixture = _fixture();
      final target = _FakeTarget();
      final store = FilesystemScenarioLabRunStore(rootPath: root.path);
      final service = _service(store: store, target: target);
      final start = service.start(
        request: fixture.request,
        contentSet: fixture.contentSet,
        catalog: fixture.catalog,
        manifest: fixture.manifest,
      );

      final result = await service.waitForResult(start.snapshot.runId);
      final reopened = FilesystemScenarioLabRunStore(rootPath: root.path);
      final persisted = reopened.requireRun(start.snapshot.runId);

      expect(result.finalSnapshot.state, ScenarioLabRunState.succeeded);
      expect(persisted.interrupted, isFalse);
      expect(persisted.result?.digest, result.digest);
      expect(persisted.latest.digest, result.finalSnapshot.digest);
    });

    test(
      'append persistence failure fail-closes live ownership and retry',
      () async {
        final fixture = _fixture();
        final store = _FailingRunStore()..failAppendsFrom = 2;
        final target = _FakeTarget();
        final service = _service(store: store, target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        final completion = service.waitForResult(start.snapshot.runId);

        await expectLater(completion, throwsA(isA<FileSystemException>()));

        final stored = store.requireRun(start.snapshot.runId);
        expect(stored.interrupted, isTrue);
        expect(stored.result, isNull);
        expect(stored.latest.state.isTerminal, isFalse);
        expect(service.activeRunCount, 0);
        expect(service.isRunFailedClosed(start.snapshot.runId), isTrue);
        expect(target.abortCalls, 1);
        expect(
          service.reattach(start.snapshot.runId).disposition,
          ScenarioLabReattachDisposition.interrupted,
        );

        final retry = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        expect(retry.created, isFalse);
        expect(retry.disposition, ScenarioLabReattachDisposition.interrupted);
        expect(retry.snapshot.state.isTerminal, isFalse);

        final replacement = _service(store: store, target: _FakeTarget());
        final replacementView = replacement.reattach(start.snapshot.runId);
        expect(
          replacementView.disposition,
          ScenarioLabReattachDisposition.interrupted,
        );
        expect(replacementView.current.state.isTerminal, isFalse);
      },
    );

    test('fail-closed completion has an internal Zone error sink', () async {
      final uncaught = <Object>[];

      await runZonedGuarded<Future<void>>(() async {
        final fixture = _fixture();
        final store = _FailingRunStore()..failAppendsFrom = 1;
        final service = _service(store: store, target: _FakeTarget());
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );

        for (var turn = 0; turn < 20 && service.activeRunCount != 0; turn++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(service.activeRunCount, 0);
        expect(
          service.reattach(start.snapshot.runId).disposition,
          ScenarioLabReattachDisposition.interrupted,
        );
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => uncaught.add(error));

      expect(uncaught, isEmpty);
    });

    test(
      'result and interruption persistence failures stay interrupted live',
      () async {
        final fixture = _fixture();
        final store = _FailingRunStore()
          ..failCompletes = true
          ..failInterrupts = true;
        final target = _FakeTarget();
        final service = _service(store: store, target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        final completion = service.waitForResult(start.snapshot.runId);

        await expectLater(completion, throwsA(isA<FileSystemException>()));

        final stored = store.requireRun(start.snapshot.runId);
        expect(stored.interrupted, isFalse);
        expect(stored.result, isNull);
        expect(stored.hasUncommittedTerminalSnapshot, isTrue);
        expect(stored.isClosed, isTrue);
        expect(stored.latest.state.isTerminal, isTrue);
        expect(service.activeRunCount, 0);
        expect(service.isRunFailedClosed(start.snapshot.runId), isTrue);
        expect(target.abortCalls, 1);
        final liveView = service.reattach(start.snapshot.runId);
        expect(
          liveView.disposition,
          ScenarioLabReattachDisposition.interrupted,
        );
        expect(liveView.current.state.isTerminal, isFalse);
        expect(
          liveView.observations.any((snapshot) => snapshot.state.isTerminal),
          isFalse,
        );

        final retry = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        expect(retry.created, isFalse);
        expect(retry.disposition, ScenarioLabReattachDisposition.interrupted);
        expect(retry.snapshot.state.isTerminal, isFalse);

        final replacement = _service(store: store, target: _FakeTarget());
        final replacementView = replacement.reattach(start.snapshot.runId);
        expect(
          replacementView.disposition,
          ScenarioLabReattachDisposition.interrupted,
          reason: 'a new live owner cannot resume an uncommitted terminal tail',
        );
        expect(replacementView.current.state.isTerminal, isFalse);
      },
    );

    test(
      'rejects a mismatched result and cleans a possibly applied write',
      () async {
        final fixture = _fixture();
        final target = _FakeTarget(mismatchAtSequence: 2);
        final service = _service(target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );

        final result = await service.waitForResult(start.snapshot.runId);

        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.stepFailed,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(target.session!.value, isFalse);
      },
    );

    test(
      'cancel is fenced, cleans dirty controls, and supports catch-up',
      () async {
        final fixture = _fixture(assignCount: 2);
        final store = InMemoryScenarioLabRunStore();
        final identities = _SequentialIdentities();
        final target = _FakeTarget(blockAtSequence: 3);
        final service = _service(
          store: store,
          identities: identities,
          target: target,
        );
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.commandBlocked.future;

        final active = service.reattach(start.snapshot.runId, afterSequence: 0);
        expect(active.disposition, ScenarioLabReattachDisposition.active);
        expect(active.canResume, isTrue);
        expect(active.observations, isNotEmpty);
        expect(active.observations.every((item) => item.sequence > 0), isTrue);

        final replacement = _service(
          store: store,
          identities: _SequentialIdentities(),
          target: _FakeTarget(),
        );
        final interrupted = replacement.reattach(start.snapshot.runId);
        expect(
          interrupted.disposition,
          ScenarioLabReattachDisposition.interrupted,
        );
        expect(interrupted.canResume, isFalse);
        final retryAfterOwnerLoss = replacement.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        expect(retryAfterOwnerLoss.created, isFalse);
        expect(
          retryAfterOwnerLoss.disposition,
          ScenarioLabReattachDisposition.interrupted,
        );
        expect(retryAfterOwnerLoss.canResume, isFalse);
        await expectLater(
          replacement.waitForResult(start.snapshot.runId),
          throwsA(isA<ScenarioLabInterruptedRun>()),
        );

        final cancelling = service.cancel(start.snapshot.runId);
        expect(cancelling.state, ScenarioLabRunState.cancelling);
        final result = await service.waitForResult(start.snapshot.runId);
        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.cancelledByUser,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(target.session!.value, isFalse);
        expect(
          replacement.reattach(start.snapshot.runId).disposition,
          ScenarioLabReattachDisposition.terminal,
        );
        expect(service.supportsProcessRestartRecovery, isFalse);
        expect(
          () => _service(target: _FakeTarget()).reattach(start.snapshot.runId),
          throwsA(isA<ScenarioLabRunNotFound>()),
        );
      },
    );

    test(
      'cancellation while attaching retains the user terminal cause',
      () async {
        final fixture = _fixture();
        final target = _FakeTarget(blockAttachUntilCancellation: true);
        final service = _service(target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.attachBlocked.future;

        service.cancel(start.snapshot.runId);
        final result = await service.waitForResult(start.snapshot.runId);

        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.cancelledByUser,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(target.abortCalls, 1);
        expect(target.attachCompleted, isTrue);
      },
    );

    test(
      'cancel during blocked cleanup reset commits cancelled honestly',
      () async {
        final fixture = _fixture();
        final store = InMemoryScenarioLabRunStore();
        final target = _FakeTarget(blockReset: true);
        final service = _service(store: store, target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.resetBlocked.future;

        expect(
          store.requireRun(start.snapshot.runId).latest.cleanup.state,
          ScenarioLabCleanupState.running,
        );
        final cancelling = service.cancel(start.snapshot.runId);
        expect(cancelling.state, ScenarioLabRunState.cancelling);
        expect(cancelling.cleanup.state, ScenarioLabCleanupState.running);
        target.releaseReset();

        final result = await service.waitForResult(start.snapshot.runId);
        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.cancelledByUser,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(
          result.finalSnapshot.cleanup.resetControlIds,
          <ScenarioControlId>[_controlId],
        );
        expect(store.requireRun(start.snapshot.runId).interrupted, isFalse);
        expect(service.isRunFailedClosed(start.snapshot.runId), isFalse);
        expect(service.activeRunCount, 0);
        expect(target.abortCalls, 1);
      },
    );

    test(
      'cancel during failed cleanup preserves the determined failure',
      () async {
        final fixture = _fixture();
        final target = _FakeTarget(
          disconnectAfterWriteAtSequence: 2,
          blockSessionClose: true,
        );
        final service = _service(target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.sessionCloseBlocked.future;

        service.cancel(start.snapshot.runId);
        target.releaseSessionClose();

        final result = await service.waitForResult(start.snapshot.runId);
        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.adapterDisconnected,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(service.isRunFailedClosed(start.snapshot.runId), isFalse);
      },
    );

    test(
      'graceful cancel before attach registration aborts the later owner',
      () async {
        final fixture = _fixture(
          cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
        );
        final target = _FakeTarget(blockAttachUntilAbort: true);
        final deadlines = _DeferredFirstActionDeadline();
        final service = _service(target: target, deadlines: deadlines);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await deadlines.actionDeferred.future;

        service.cancel(start.snapshot.runId);
        expect(target.attachCalls, 0);
        expect(target.abortCalls, 0);
        deadlines.releaseAction();
        final result = await service.waitForResult(start.snapshot.runId);

        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.cancelledByUser,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(target.attachCalls, 1);
        expect(target.abortCalls, 1);
        expect(target.attachCompleted, isTrue);
      },
    );

    test(
      'attach deadline aborts and drains the target before terminal commit',
      () async {
        final fixture = _fixture();
        final target = _FakeTarget(blockAttachUntilAbort: true);
        final deadlines = _ControlledAttachDeadline();
        final service = _service(target: target, deadlines: deadlines);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.attachBlocked.future;

        deadlines.expireAttach();
        final result = await service.waitForResult(start.snapshot.runId);

        expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.timedOut,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(target.abortCalls, 1);
        expect(target.attachCompleted, isTrue);
      },
    );

    test('attach timeout classifies failed abort as cleanup failure', () async {
      final fixture = _fixture();
      final target = _FakeTarget(blockAttachUntilAbort: true, failAbort: true);
      final deadlines = _ControlledAttachDeadline();
      final service = _service(target: target, deadlines: deadlines);
      final start = service.start(
        request: fixture.request,
        contentSet: fixture.contentSet,
        catalog: fixture.catalog,
        manifest: fixture.manifest,
      );
      await target.attachBlocked.future;

      deadlines.expireAttach();
      final result = await service.waitForResult(start.snapshot.runId);

      expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
      expect(
        result.finalSnapshot.terminalCause,
        ScenarioLabTerminalCause.cleanupFailed,
      );
      expect(
        result.finalSnapshot.cleanup.state,
        ScenarioLabCleanupState.failed,
      );
      expect(
        result.finalSnapshot.cleanup.state,
        isNot(ScenarioLabCleanupState.notRequired),
      );
      expect(target.abortCalls, 1);
    });

    test(
      'close force-cancels active work, commits shutdown, and drains writes',
      () async {
        final fixture = _fixture(
          cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
        );
        final store = InMemoryScenarioLabRunStore();
        final target = _FakeTarget(blockAtSequence: 2);
        final service = _service(store: store, target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.commandBlocked.future;
        expect(service.activeRunCount, 1);

        await service.close();

        final result = await service.waitForResult(start.snapshot.runId);
        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.hostShutdown,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(target.session!.value, isFalse);
        expect(target.session!.closeCalls, 1);
        expect(service.activeRunCount, 0);
        expect(service.isClosed, isTrue);

        final committed = store.requireRun(start.snapshot.runId);
        final snapshotCount = committed.snapshots.length;
        final resultDigest = committed.result!.digest;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final stable = store.requireRun(start.snapshot.runId);
        expect(stable.snapshots, hasLength(snapshotCount));
        expect(stable.result!.digest, resultDigest);
        await service.close();
        expect(
          () => service.start(
            request: fixture.request,
            contentSet: fixture.contentSet,
            catalog: fixture.catalog,
            manifest: fixture.manifest,
          ),
          throwsStateError,
        );
      },
    );

    test(
      'close during blocked session cleanup commits host shutdown',
      () async {
        final fixture = _fixture();
        final store = InMemoryScenarioLabRunStore();
        final target = _FakeTarget(blockSessionClose: true);
        final service = _service(store: store, target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.sessionCloseBlocked.future;

        expect(
          store.requireRun(start.snapshot.runId).latest.cleanup.state,
          ScenarioLabCleanupState.running,
        );
        final closing = service.close();
        expect(
          store.requireRun(start.snapshot.runId).latest.state,
          ScenarioLabRunState.cancelling,
        );
        target.releaseSessionClose();
        await closing;

        final result = await service.waitForResult(start.snapshot.runId);
        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.hostShutdown,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(store.requireRun(start.snapshot.runId).interrupted, isFalse);
        expect(service.isRunFailedClosed(start.snapshot.runId), isFalse);
        expect(service.activeRunCount, 0);
        expect(service.isClosed, isTrue);
        expect(target.abortCalls, 1);
      },
    );

    test(
      'close settles a fail-closed completion before reporting its error',
      () async {
        final fixture = _fixture();
        final store = _FailingRunStore()..failCompletes = true;
        final target = _FakeTarget(blockSessionClose: true);
        final service = _service(store: store, target: target);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        await target.sessionCloseBlocked.future;

        final closing = service.close();
        target.releaseSessionClose();

        await expectLater(closing, throwsA(isA<FileSystemException>()));
        expect(service.activeRunCount, 0);
        expect(service.isClosed, isTrue);
        expect(service.isRunFailedClosed(start.snapshot.runId), isTrue);
        expect(store.requireRun(start.snapshot.runId).interrupted, isTrue);
      },
    );

    test(
      'close signals and settles every run after one append failure',
      () async {
        final fixture = _fixture();
        final store = _SelectiveFailingRunStore();
        final target = _FakeTarget(blockAtSequence: 2);
        final service = _service(store: store, target: target);
        final first = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        final secondRequest = ScenarioLabRunStartRequest(
          requestId: ScenarioLabRunRequestId('request-2'),
          expectedContentSetDigest: fixture.request.expectedContentSetDigest,
          expectedScenarioLabManifestDigest:
              fixture.request.expectedScenarioLabManifestDigest,
          scenarioId: fixture.request.scenarioId,
          scriptId: fixture.request.scriptId,
          requestedAt: fixture.request.requestedAt,
        );
        final second = service.start(
          request: secondRequest,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );
        expect(service.activeRunCount, 2);
        store.failNextAppendFor = first.snapshot.runId;

        final closing = service.close();

        await expectLater(closing, throwsA(isA<FileSystemException>()));
        final firstResult = await service.waitForResult(first.snapshot.runId);
        final secondResult = await service.waitForResult(second.snapshot.runId);
        expect(
          firstResult.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.hostShutdown,
        );
        expect(
          secondResult.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.hostShutdown,
        );
        expect(service.activeRunCount, 0);
        expect(service.isClosed, isTrue);
        expect(target.abortCalls, 2);
      },
    );

    test(
      'a step deadline produces timed-out cancellation and cleanup',
      () async {
        final fixture = _fixture(
          operationTimeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
        );
        final target = _FakeTarget();
        final deadlines = _FakeDeadlines(throwAfterActionOnCall: 3);
        final service = _service(target: target, deadlines: deadlines);
        final start = service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        );

        final result = await service.waitForResult(start.snapshot.runId);

        expect(result.finalSnapshot.state, ScenarioLabRunState.cancelled);
        expect(
          result.finalSnapshot.terminalCause,
          ScenarioLabTerminalCause.timedOut,
        );
        expect(
          result.finalSnapshot.steps[1].terminalCause,
          ScenarioLabStepTerminalCause.cancelled,
        );
        expect(
          result.finalSnapshot.cleanup.state,
          ScenarioLabCleanupState.succeeded,
        );
        expect(target.session!.value, isFalse);
      },
    );

    test('cleanup failure overrides apparent script success', () async {
      final fixture = _fixture();
      final target = _FakeTarget(failReset: true);
      final service = _service(target: target);
      final start = service.start(
        request: fixture.request,
        contentSet: fixture.contentSet,
        catalog: fixture.catalog,
        manifest: fixture.manifest,
      );

      final result = await service.waitForResult(start.snapshot.runId);

      expect(result.finalSnapshot.state, ScenarioLabRunState.failed);
      expect(
        result.finalSnapshot.terminalCause,
        ScenarioLabTerminalCause.cleanupFailed,
      );
      expect(
        result.finalSnapshot.cleanup.state,
        ScenarioLabCleanupState.failed,
      );
    });

    test('planner rejects an unresettable write before any target effect', () {
      final fixture = _fixture(resettable: false);
      final target = _FakeTarget();
      final identities = _SequentialIdentities();
      final service = _service(target: target, identities: identities);

      expect(
        () => service.start(
          request: fixture.request,
          contentSet: fixture.contentSet,
          catalog: fixture.catalog,
          manifest: fixture.manifest,
        ),
        throwsA(isA<ScenarioLabUnsupportedExecutionPlan>()),
      );
      expect(target.resolveCalls, 0);
      expect(target.attachCalls, 0);
      expect(identities.runCount, 0);
    });

    test(
      'Evidence and comparison plans are rejected without fake receipts',
      () {
        final fixture = _evidenceFixture();
        final target = _FakeTarget();
        final identities = _SequentialIdentities();
        final service = _service(target: target, identities: identities);

        expect(
          () => service.start(
            request: fixture.request,
            contentSet: fixture.contentSet,
            catalog: fixture.catalog,
            manifest: fixture.manifest,
          ),
          throwsA(
            isA<ScenarioLabUnsupportedExecutionPlan>()
                .having(
                  (error) => error.features.join(' '),
                  'features',
                  contains('Host-owned receipts'),
                )
                .having(
                  (error) => error.features.join(' '),
                  'features',
                  contains('Host-owned artifact bytes'),
                ),
          ),
        );
        expect(target.resolveCalls, 0);
        expect(target.attachCalls, 0);
        expect(identities.runCount, 0);
      },
    );
  });
}

ScenarioLabExecutionService _service({
  ScenarioLabRunStore? store,
  _SequentialIdentities? identities,
  required _FakeTarget target,
  ScenarioLabDeadlinePort? deadlines,
}) => ScenarioLabExecutionService(
  store: store ?? InMemoryScenarioLabRunStore(),
  clock: _AdvancingClock(),
  identities: identities ?? _SequentialIdentities(),
  target: target,
  deadlines: deadlines ?? _FakeDeadlines(),
);

final class _FailingRunStore implements ScenarioLabRunStore {
  final InMemoryScenarioLabRunStore _delegate = InMemoryScenarioLabRunStore();
  int? failAppendsFrom;
  var failCompletes = false;
  var failInterrupts = false;
  var _appendCalls = 0;

  @override
  int get length => _delegate.length;

  @override
  List<ScenarioLabStoredRun> get runs => _delegate.runs;

  @override
  ScenarioLabRunRegistration register({
    required ScenarioLabRunStartRequest request,
    required ScenarioLabRunSnapshot initialSnapshot,
  }) => _delegate.register(request: request, initialSnapshot: initialSnapshot);

  @override
  ScenarioLabStoredRun? findByRequestId(ScenarioLabRunRequestId requestId) =>
      _delegate.findByRequestId(requestId);

  @override
  ScenarioLabStoredRun? findByRunId(ScenarioLabRunId runId) =>
      _delegate.findByRunId(runId);

  @override
  ScenarioLabStoredRun requireRun(ScenarioLabRunId runId) =>
      _delegate.requireRun(runId);

  @override
  void append(ScenarioLabRunSnapshot snapshot) {
    _appendCalls += 1;
    final threshold = failAppendsFrom;
    if (threshold != null && _appendCalls >= threshold) {
      throw const FileSystemException('Injected Scenario Lab append failure');
    }
    _delegate.append(snapshot);
  }

  @override
  void complete(ScenarioLabRunResult result) {
    if (failCompletes) {
      throw const FileSystemException('Injected Scenario Lab result failure');
    }
    _delegate.complete(result);
  }

  @override
  bool interrupt(ScenarioLabRunId runId) {
    if (failInterrupts) {
      throw const FileSystemException(
        'Injected Scenario Lab interruption failure',
      );
    }
    return _delegate.interrupt(runId);
  }

  @override
  List<ScenarioLabRunSnapshot> observationsAfter(
    ScenarioLabRunId runId,
    int sequence,
  ) => _delegate.observationsAfter(runId, sequence);
}

final class _SelectiveFailingRunStore implements ScenarioLabRunStore {
  final InMemoryScenarioLabRunStore _delegate = InMemoryScenarioLabRunStore();
  ScenarioLabRunId? failNextAppendFor;

  @override
  int get length => _delegate.length;

  @override
  List<ScenarioLabStoredRun> get runs => _delegate.runs;

  @override
  ScenarioLabRunRegistration register({
    required ScenarioLabRunStartRequest request,
    required ScenarioLabRunSnapshot initialSnapshot,
  }) => _delegate.register(request: request, initialSnapshot: initialSnapshot);

  @override
  ScenarioLabStoredRun? findByRequestId(ScenarioLabRunRequestId requestId) =>
      _delegate.findByRequestId(requestId);

  @override
  ScenarioLabStoredRun? findByRunId(ScenarioLabRunId runId) =>
      _delegate.findByRunId(runId);

  @override
  ScenarioLabStoredRun requireRun(ScenarioLabRunId runId) =>
      _delegate.requireRun(runId);

  @override
  void append(ScenarioLabRunSnapshot snapshot) {
    if (failNextAppendFor == snapshot.runId) {
      failNextAppendFor = null;
      throw const FileSystemException(
        'Injected Scenario Lab selective append failure',
      );
    }
    _delegate.append(snapshot);
  }

  @override
  void complete(ScenarioLabRunResult result) => _delegate.complete(result);

  @override
  bool interrupt(ScenarioLabRunId runId) => _delegate.interrupt(runId);

  @override
  List<ScenarioLabRunSnapshot> observationsAfter(
    ScenarioLabRunId runId,
    int sequence,
  ) => _delegate.observationsAfter(runId, sequence);
}

final class _Fixture {
  const _Fixture({
    required this.catalog,
    required this.manifest,
    required this.contentSet,
    required this.request,
  });

  final CatalogManifest catalog;
  final ScenarioLabManifest manifest;
  final ExperienceContentSetIdentity contentSet;
  final ScenarioLabRunStartRequest request;
}

final _scenarioId = ScenarioId('ready');
final _bindingId = ScenarioExecutionBindingId('ready-web');
final _controlId = ScenarioControlId('feature-ready');
final _scriptId = ScenarioScriptId('exercise-ready');
final _capability = AppAdapterCapabilityReference(
  id: AppAdapterCapabilityId('sample.controls'),
  version: 1,
);

_Fixture _fixture({
  int assignCount = 1,
  bool resettable = true,
  ScenarioScriptCancellationPolicy cancellationPolicy =
      ScenarioScriptCancellationPolicy.immediate,
  ScenarioScriptTimeoutOutcome operationTimeoutOutcome =
      ScenarioScriptTimeoutOutcome.fail,
}) {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('app');
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
        displayName: 'App',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(id: _scenarioId, applicationId: applicationId, title: 'Ready'),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: _bindingId,
        scenarioId: _scenarioId,
        targetId: 'chrome',
        launchProfileId: 'app-web',
      ),
    ],
  );
  final operationIds = <ScenarioLabOperationId>[
    for (var index = 1; index <= assignCount; index += 1)
      ScenarioLabOperationId('assign-$index'),
  ];
  final manifest = ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: <CapabilityDescriptor>[
      CapabilityDescriptor(
        id: 'sample.controls',
        version: 1,
        operations: <String>{'read', 'write', 'reset'},
      ),
    ],
    controls: <ScenarioControlDefinition>[
      ScenarioControlDefinition(
        id: _controlId,
        scenarioId: _scenarioId,
        displayName: 'Feature ready',
        capability: _capability,
        readOperationId: CapabilityOperationId('read'),
        writeOperationId: CapabilityOperationId('write'),
        resetOperationId: resettable ? CapabilityOperationId('reset') : null,
        domain: BooleanScenarioControlDomain(defaultValue: false),
      ),
    ],
    operations: <ScenarioLabOperationDefinition>[
      for (final id in operationIds)
        AssignControlOperationDefinition(
          id: id,
          scenarioId: _scenarioId,
          controlId: _controlId,
          value: const BooleanScenarioControlValue(true),
        ),
    ],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: _scriptId,
        scenarioId: _scenarioId,
        displayName: 'Exercise ready',
        timeoutMs: 30000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: cancellationPolicy,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'attach',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            bindingId: _bindingId,
          ),
          for (final id in operationIds)
            OperationScenarioScriptStep(
              id: id.value,
              timeoutMs: 10000,
              timeoutOutcome: operationTimeoutOutcome,
              operationId: id,
            ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
      ScriptSucceededAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('script-succeeded'),
        scenarioId: _scenarioId,
        displayName: 'Script succeeded',
        scriptId: _scriptId,
      ),
      ControlEqualsAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('feature-observed'),
        scenarioId: _scenarioId,
        displayName: 'Feature was observed',
        controlId: _controlId,
        expectedValue: const BooleanScenarioControlValue(true),
      ),
    ],
    requiredEvidence: const <RequiredEvidenceDefinition>[],
    comparisonBindings: const <ScenarioComparisonBinding>[],
    visualComparisonPolicies: const <VisualComparisonPolicy>[],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: const <HumanApprovalRequirement>[],
    supplementalArtifacts: const <SupplementalArtifactReference>[],
    plans: <ScenarioLabPlan>[
      ScenarioLabPlan(
        scenarioId: _scenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[_bindingId],
        controlIds: <ScenarioControlId>[_controlId],
        operationIds: operationIds,
        scriptIds: <ScenarioScriptId>[_scriptId],
        automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
          AutomatedAcceptanceCriterionId('script-succeeded'),
          AutomatedAcceptanceCriterionId('feature-observed'),
        ],
        requiredEvidenceIds: const <RequiredEvidenceId>[],
        comparisonBindingIds: const <ScenarioComparisonBindingId>[],
        humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
        supplementalArtifactIds: const <SupplementalArtifactId>[],
      ),
    ],
  );
  final contentSet = ExperienceContentSetIdentity(
    revision: 1,
    catalogDigest: catalog.digest,
    workspaceSnapshotDigest: Digest.semantic('snapshot'),
    workspaceContentDigest: Digest.semantic('workspace-content'),
    scenarioLabManifestDigest: manifest.digest,
  );
  return _Fixture(
    catalog: catalog,
    manifest: manifest,
    contentSet: contentSet,
    request: _request(contentSet, manifest),
  );
}

_Fixture _evidenceFixture() {
  final catalog = _fixture().catalog;
  final evidenceId = RequiredEvidenceId('ready-visual');
  final operationId = ScenarioLabOperationId('collect-ready');
  final scriptId = ScenarioScriptId('collect-ready');
  final baselineId = SupplementalArtifactId('ready-baseline');
  final comparisonId = ScenarioComparisonBindingId('ready-comparison');
  final manifest = ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: const <CapabilityDescriptor>[],
    controls: const <ScenarioControlDefinition>[],
    operations: <ScenarioLabOperationDefinition>[
      CollectEvidenceOperationDefinition(
        id: operationId,
        scenarioId: _scenarioId,
        evidenceRequirementId: evidenceId,
      ),
    ],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: scriptId,
        scenarioId: _scenarioId,
        displayName: 'Collect ready Evidence',
        timeoutMs: 30000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'attach',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            bindingId: _bindingId,
          ),
          OperationScenarioScriptStep(
            id: 'collect',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: operationId,
          ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
      ScriptSucceededAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('script-succeeded'),
        scenarioId: _scenarioId,
        displayName: 'Script succeeded',
        scriptId: scriptId,
      ),
      EvidenceAcceptedAcceptanceCriterion(
        id: AutomatedAcceptanceCriterionId('evidence-accepted'),
        scenarioId: _scenarioId,
        displayName: 'Evidence accepted',
        evidenceRequirementId: evidenceId,
      ),
    ],
    requiredEvidence: <RequiredEvidenceDefinition>[
      RequiredEvidenceDefinition(
        id: evidenceId,
        scenarioId: _scenarioId,
        providerId: ModuleId('capture.web'),
        fidelity: RuntimeFidelity.hostNative,
        variantId: VariantId('desktop'),
        freshness: EvidenceFreshness.fresh,
        allowedClassifications: <ArtifactClassification>{
          ArtifactClassification.internal,
        },
        evidencePolicyId: EvidencePolicyId('visual-v1'),
        comparisonPolicy: VisualComparisonPolicyReference(
          VisualComparisonPolicyId('pixel-v1'),
        ),
      ),
    ],
    comparisonBindings: <ScenarioComparisonBinding>[
      ScenarioComparisonBinding(
        id: comparisonId,
        scenarioId: _scenarioId,
        requiredEvidenceId: evidenceId,
        baseline: ArtifactComparisonInputReference(artifactId: baselineId),
        candidate: RequiredEvidenceComparisonInputReference(
          requiredEvidenceId: evidenceId,
        ),
      ),
    ],
    visualComparisonPolicies: <VisualComparisonPolicy>[
      VisualComparisonPolicy(
        id: 'pixel-v1',
        maxChannelDelta: 8,
        maxChangedPixelRatio: 0.01,
      ),
    ],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: const <HumanApprovalRequirement>[],
    supplementalArtifacts: <SupplementalArtifactReference>[
      SupplementalArtifactReference(
        id: baselineId,
        scenarioId: _scenarioId,
        requiredEvidenceId: evidenceId,
        role: SupplementalArtifactRole.comparisonBaseline,
        artifactDigest: Digest.semantic('baseline-artifact'),
        provenanceDigest: Digest.semantic('baseline-provenance'),
        classification: ArtifactClassification.internal,
      ),
    ],
    plans: <ScenarioLabPlan>[
      ScenarioLabPlan(
        scenarioId: _scenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[_bindingId],
        controlIds: const <ScenarioControlId>[],
        operationIds: <ScenarioLabOperationId>[operationId],
        scriptIds: <ScenarioScriptId>[scriptId],
        automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
          AutomatedAcceptanceCriterionId('script-succeeded'),
          AutomatedAcceptanceCriterionId('evidence-accepted'),
        ],
        requiredEvidenceIds: <RequiredEvidenceId>[evidenceId],
        comparisonBindingIds: <ScenarioComparisonBindingId>[comparisonId],
        humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
        supplementalArtifactIds: <SupplementalArtifactId>[baselineId],
      ),
    ],
  );
  final contentSet = ExperienceContentSetIdentity(
    revision: 1,
    catalogDigest: catalog.digest,
    workspaceSnapshotDigest: Digest.semantic('snapshot'),
    workspaceContentDigest: Digest.semantic('workspace-content'),
    scenarioLabManifestDigest: manifest.digest,
  );
  return _Fixture(
    catalog: catalog,
    manifest: manifest,
    contentSet: contentSet,
    request: ScenarioLabRunStartRequest(
      requestId: ScenarioLabRunRequestId('evidence-request'),
      expectedContentSetDigest: contentSet.contentSetDigest,
      expectedScenarioLabManifestDigest: manifest.digest,
      scenarioId: _scenarioId,
      scriptId: scriptId,
      requestedAt: DateTime.utc(2026, 8, 14, 12),
    ),
  );
}

ScenarioLabRunStartRequest _request(
  ExperienceContentSetIdentity contentSet,
  ScenarioLabManifest manifest, {
  DateTime? requestedAt,
}) => ScenarioLabRunStartRequest(
  requestId: ScenarioLabRunRequestId('request-1'),
  expectedContentSetDigest: contentSet.contentSetDigest,
  expectedScenarioLabManifestDigest: manifest.digest,
  scenarioId: _scenarioId,
  scriptId: _scriptId,
  requestedAt: requestedAt ?? DateTime.utc(2026, 8, 14, 12),
);

final class _SequentialIdentities implements ScenarioLabExecutionIdentityPort {
  var runCount = 0;
  var commandCount = 0;
  var nonceCount = 0;

  @override
  ScenarioLabRunId nextRunId() => ScenarioLabRunId('run-${++runCount}');

  @override
  ScenarioLabCommandId nextCommandId() =>
      ScenarioLabCommandId('command-${++commandCount}');

  @override
  AppAdapterRelayNonce nextRelayNonce() => AppAdapterRelayNonce(
    'nonce_${(++nonceCount).toString().padLeft(20, '0')}',
  );
}

final class _AdvancingClock implements Clock {
  var ticks = 0;
  var micros = 0;

  @override
  DateTime nowUtc() =>
      DateTime.utc(2026, 8, 14, 12).add(Duration(milliseconds: ticks++));

  @override
  int monotonicMicroseconds() {
    micros += 1000;
    return micros;
  }
}

final class _FakeDeadlines implements ScenarioLabDeadlinePort {
  _FakeDeadlines({this.throwAfterActionOnCall});

  final int? throwAfterActionOnCall;
  var calls = 0;

  @override
  Future<T> run<T>({
    required Duration timeout,
    required Future<T> Function() action,
  }) async {
    expect(timeout, greaterThan(Duration.zero));
    final call = ++calls;
    final value = await action();
    if (call == throwAfterActionOnCall) {
      throw const ScenarioLabDeadlineExceeded();
    }
    return value;
  }
}

final class _ControlledAttachDeadline implements ScenarioLabDeadlinePort {
  final Completer<void> _attachExpired = Completer<void>();
  var calls = 0;

  void expireAttach() {
    if (!_attachExpired.isCompleted) _attachExpired.complete();
  }

  @override
  Future<T> run<T>({
    required Duration timeout,
    required Future<T> Function() action,
  }) {
    expect(timeout, greaterThan(Duration.zero));
    final operation = action();
    if (++calls != 1) return operation;
    return Future.any<T>(<Future<T>>[
      operation,
      _attachExpired.future.then<T>(
        (_) => throw const ScenarioLabDeadlineExceeded(),
      ),
    ]);
  }
}

final class _DeferredFirstActionDeadline implements ScenarioLabDeadlinePort {
  final Completer<void> actionDeferred = Completer<void>();
  final Completer<void> _release = Completer<void>();
  var calls = 0;

  void releaseAction() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<T> run<T>({
    required Duration timeout,
    required Future<T> Function() action,
  }) {
    expect(timeout, greaterThan(Duration.zero));
    if (++calls != 1) return action();
    if (!actionDeferred.isCompleted) actionDeferred.complete();
    return _release.future.then<T>((_) => action());
  }
}

final class _FakeTarget implements ScenarioLabTargetPort {
  _FakeTarget({
    this.blockAtSequence,
    this.mismatchAtSequence,
    this.disconnectAfterWriteAtSequence,
    this.failReset = false,
    this.blockAttachUntilCancellation = false,
    this.blockAttachUntilAbort = false,
    this.failAbort = false,
    this.blockReset = false,
    this.blockSessionClose = false,
  });

  final int? blockAtSequence;
  final int? mismatchAtSequence;
  final int? disconnectAfterWriteAtSequence;
  final bool failReset;
  final bool blockAttachUntilCancellation;
  final bool blockAttachUntilAbort;
  final bool failAbort;
  final bool blockReset;
  final bool blockSessionClose;
  final Completer<void> commandBlocked = Completer<void>();
  final Completer<void> attachBlocked = Completer<void>();
  final Completer<void> resetBlocked = Completer<void>();
  final Completer<void> sessionCloseBlocked = Completer<void>();
  final Completer<void> _attachAborted = Completer<void>();
  final Completer<void> _attachFinished = Completer<void>();
  final Completer<void> _resetReleased = Completer<void>();
  final Completer<void> _sessionCloseReleased = Completer<void>();
  var resolveCalls = 0;
  var attachCalls = 0;
  var abortCalls = 0;
  var attachCompleted = false;
  _FakeSession? session;

  void releaseReset() {
    if (!_resetReleased.isCompleted) _resetReleased.complete();
  }

  void releaseSessionClose() {
    if (!_sessionCloseReleased.isCompleted) {
      _sessionCloseReleased.complete();
    }
  }

  @override
  ScenarioLabRuntimeInputBinding resolveRuntimeInputs({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
  }) {
    resolveCalls += 1;
    return ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest: Digest.semantic('fingerprint'),
      executionTargetId: binding.targetId,
    );
  }

  @override
  Future<ScenarioLabTargetSession> attach({
    required ScenarioLabRunId runId,
    required ScenarioExecutionBinding binding,
    required AppAdapterRelayNonce nonce,
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    attachCalls += 1;
    if (blockAttachUntilAbort) {
      if (!attachBlocked.isCompleted) attachBlocked.complete();
      await _attachAborted.future;
      attachCompleted = true;
      if (!_attachFinished.isCompleted) _attachFinished.complete();
      throw const ScenarioLabTargetCancelled();
    }
    if (blockAttachUntilCancellation) {
      if (!attachBlocked.isCompleted) attachBlocked.complete();
      await cancellation.whenCancelled;
      attachCompleted = true;
      if (!_attachFinished.isCompleted) _attachFinished.complete();
      throw const ScenarioLabTargetCancelled();
    }
    attachCompleted = true;
    if (!_attachFinished.isCompleted) _attachFinished.complete();
    return session = _FakeSession(
      runId: runId,
      nonce: nonce,
      blockAtSequence: blockAtSequence,
      mismatchAtSequence: mismatchAtSequence,
      disconnectAfterWriteAtSequence: disconnectAfterWriteAtSequence,
      failReset: failReset,
      commandBlocked: commandBlocked,
      blockReset: blockReset,
      resetBlocked: resetBlocked,
      resetReleased: _resetReleased.future,
      blockSessionClose: blockSessionClose,
      sessionCloseBlocked: sessionCloseBlocked,
      sessionCloseReleased: _sessionCloseReleased.future,
    );
  }

  @override
  Future<void> abort(ScenarioLabRunId runId) async {
    abortCalls += 1;
    if (!_attachAborted.isCompleted) _attachAborted.complete();
    if (failAbort) throw StateError('Target abort failed');
    await _attachFinished.future;
  }
}

final class _FakeSession implements ScenarioLabTargetSession {
  _FakeSession({
    required ScenarioLabRunId runId,
    required AppAdapterRelayNonce nonce,
    required this.blockAtSequence,
    required this.mismatchAtSequence,
    required this.disconnectAfterWriteAtSequence,
    required this.failReset,
    required this.commandBlocked,
    required this.blockReset,
    required this.resetBlocked,
    required this.resetReleased,
    required this.blockSessionClose,
    required this.sessionCloseBlocked,
    required this.sessionCloseReleased,
  }) : hello = AppAdapterRelayHello(
         runId: runId,
         adapterInstanceId: 'adapter-1',
         sequence: 0,
         nonce: nonce,
         capabilities: <AppAdapterCapabilityReference>[_capability],
       );

  @override
  final AppAdapterRelayHello hello;
  final int? blockAtSequence;
  final int? mismatchAtSequence;
  final int? disconnectAfterWriteAtSequence;
  final bool failReset;
  final Completer<void> commandBlocked;
  final bool blockReset;
  final Completer<void> resetBlocked;
  final Future<void> resetReleased;
  final bool blockSessionClose;
  final Completer<void> sessionCloseBlocked;
  final Future<void> sessionCloseReleased;
  final List<AppAdapterRelayCommand> commands = <AppAdapterRelayCommand>[];
  var value = false;
  var closeCalls = 0;

  @override
  Future<AppAdapterRelayResult> execute(
    AppAdapterRelayCommand command, {
    required ScenarioLabCancellationSignal cancellation,
  }) async {
    commands.add(command);
    if (command case WriteAppAdapterRelayCommand(:final value)) {
      this.value = (value as BooleanScenarioControlValue).value;
      if (command.sequence == disconnectAfterWriteAtSequence) {
        throw const ScenarioLabAdapterDisconnected();
      }
    }
    if (command.sequence == blockAtSequence) {
      if (!commandBlocked.isCompleted) commandBlocked.complete();
      await cancellation.whenCancelled;
      return _result(command, state: AppAdapterRelayResultState.cancelled);
    }
    if (command is ResetAppAdapterRelayCommand) {
      if (blockReset) {
        if (!resetBlocked.isCompleted) resetBlocked.complete();
        await resetReleased;
      }
      if (failReset) {
        return _result(
          command,
          state: AppAdapterRelayResultState.failed,
          failure: const AppAdapterRelayFailure(
            cause: AppAdapterRelayFailureCause.rejected,
          ),
        );
      }
      value = false;
    }
    return _result(command, mismatch: command.sequence == mismatchAtSequence);
  }

  AppAdapterRelayResult _result(
    AppAdapterRelayCommand command, {
    AppAdapterRelayResultState state = AppAdapterRelayResultState.succeeded,
    AppAdapterRelayFailure? failure,
    bool mismatch = false,
  }) {
    final sequence = mismatch ? command.sequence + 1 : command.sequence;
    final commandId = command.commandId;
    final nonce = command.nonce;
    return switch (command) {
      ReadAppAdapterRelayCommand() => ReadAppAdapterRelayResult(
        runId: command.runId,
        commandId: commandId,
        sequence: sequence,
        nonce: nonce,
        state: state,
        failure: failure,
        value: state == AppAdapterRelayResultState.succeeded
            ? BooleanScenarioControlValue(value)
            : null,
      ),
      WriteAppAdapterRelayCommand(:final value) => WriteAppAdapterRelayResult(
        runId: command.runId,
        commandId: commandId,
        sequence: sequence,
        nonce: nonce,
        state: state,
        failure: failure,
        value: state == AppAdapterRelayResultState.succeeded ? value : null,
      ),
      ResetAppAdapterRelayCommand() => ResetAppAdapterRelayResult(
        runId: command.runId,
        commandId: commandId,
        sequence: sequence,
        nonce: nonce,
        state: state,
        failure: failure,
        value: state == AppAdapterRelayResultState.succeeded
            ? const BooleanScenarioControlValue(false)
            : null,
      ),
      CaptureAppAdapterRelayCommand() => throw StateError(
        'The pure control core must never emit capture commands',
      ),
      _ => throw StateError('Unknown App Adapter relay command'),
    };
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    if (blockSessionClose) {
      if (!sessionCloseBlocked.isCompleted) sessionCloseBlocked.complete();
      await sessionCloseReleased;
    }
  }
}
