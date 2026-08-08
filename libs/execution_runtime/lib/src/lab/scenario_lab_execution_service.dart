import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import 'scenario_lab_execution_ports.dart';
import 'scenario_lab_run_store.dart';

enum ScenarioLabReattachDisposition { active, terminal, interrupted }

/// Observer catch-up result. `interrupted` is intentionally not resumable.
final class ScenarioLabReattachView {
  ScenarioLabReattachView({
    required this.disposition,
    required this.current,
    required Iterable<ScenarioLabRunSnapshot> observations,
  }) : observations = List<ScenarioLabRunSnapshot>.unmodifiable(observations);

  final ScenarioLabReattachDisposition disposition;
  final ScenarioLabRunSnapshot current;
  final List<ScenarioLabRunSnapshot> observations;

  bool get canResume => disposition == ScenarioLabReattachDisposition.active;
}

final class ScenarioLabStartOutcome {
  const ScenarioLabStartOutcome({
    required this.created,
    required this.snapshot,
    required this.disposition,
  });

  final bool created;
  final ScenarioLabRunSnapshot snapshot;
  final ScenarioLabReattachDisposition disposition;

  bool get canResume => disposition == ScenarioLabReattachDisposition.active;
}

/// Raised when a volatile store contains a non-terminal run without its owner.
final class ScenarioLabInterruptedRun implements Exception {
  const ScenarioLabInterruptedRun(this.runId);

  final ScenarioLabRunId runId;

  @override
  String toString() =>
      'ScenarioLabInterruptedRun: ${runId.value} cannot be resumed safely';
}

/// Raised when active runs did not reach a committed terminal result within
/// the bounded Host shutdown drain.
final class ScenarioLabShutdownTimedOut implements Exception {
  ScenarioLabShutdownTimedOut(Iterable<ScenarioLabRunId> activeRunIds)
    : activeRunIds = List<ScenarioLabRunId>.unmodifiable(
        activeRunIds.toList()
          ..sort((left, right) => left.value.compareTo(right.value)),
      );

  final List<ScenarioLabRunId> activeRunIds;

  @override
  String toString() =>
      'ScenarioLabShutdownTimedOut: ${activeRunIds.map((id) => id.value).join(', ')}';
}

/// Raised before a run is reserved when the pure core cannot prove a plan.
///
/// Unsupported target or Evidence work is rejected before effects are
/// reserved. Comparison availability is reported in the immutable run result
/// after a valid collection, so successfully collected Evidence is preserved
/// even when no compatible comparison adapter exists.
final class ScenarioLabUnsupportedExecutionPlan implements Exception {
  ScenarioLabUnsupportedExecutionPlan(Iterable<String> features)
    : features = List<String>.unmodifiable(features.toSet().toList()..sort()) {
    if (this.features.isEmpty) {
      throw ArgumentError(
        'ScenarioLabUnsupportedExecutionPlan requires features',
      );
    }
  }

  final List<String> features;

  @override
  String toString() =>
      'ScenarioLabUnsupportedExecutionPlan: ${features.join(', ')}';
}

/// Pure Phase 1 Scenario Lab coordinator.
///
/// Target work goes through typed ports; this class owns no relay, process,
/// filesystem or network I/O. App Adapter capture and comparison are accepted
/// only through Host-owned ports; absence remains explicit and fail-closed.
final class ScenarioLabExecutionService {
  ScenarioLabExecutionService({
    required this.store,
    required this.clock,
    required this.identities,
    required this.target,
    required this.deadlines,
    this.evidence,
    this.comparison,
    this.planner = const ScenarioLabExecutionPlanner(),
    this.cleanupTimeout = const Duration(seconds: 30),
    this.shutdownTimeout = const Duration(seconds: 45),
  }) {
    if (cleanupTimeout <= Duration.zero) {
      throw ArgumentError.value(cleanupTimeout, 'cleanupTimeout');
    }
    if (shutdownTimeout <= Duration.zero) {
      throw ArgumentError.value(shutdownTimeout, 'shutdownTimeout');
    }
  }

  final ScenarioLabRunStore store;
  final Clock clock;
  final ScenarioLabExecutionIdentityPort identities;
  final ScenarioLabTargetPort target;
  final ScenarioLabDeadlinePort deadlines;
  final ScenarioLabEvidencePort? evidence;
  final ScenarioLabComparisonPort? comparison;
  final ScenarioLabExecutionPlanner planner;
  final Duration cleanupTimeout;
  final Duration shutdownTimeout;

  final Map<String, _RunExecution> _active = <String, _RunExecution>{};
  final Set<String> _failedClosedRunIds = <String>{};
  Future<void>? _closing;
  var _acceptingStarts = true;
  var _closed = false;

  /// This implementation is intentionally volatile across process restart.
  bool get supportsProcessRestartRecovery => false;

  int get activeRunCount => _active.length;

  /// Whether this live owner lost an execution without a committed result.
  ///
  /// The durable store remains the source of truth. This process-local marker
  /// only closes the public liveness gap when persisting the interruption also
  /// fails; a later store ownership boundary performs durable recovery.
  bool isRunFailedClosed(ScenarioLabRunId runId) =>
      _failedClosedRunIds.contains(runId.value);

  /// Public ownership disposition used by every Host-facing run surface.
  ///
  /// A non-terminal stored run is active only while this exact service owns
  /// its execution. Replacement services must expose it as interrupted.
  ScenarioLabReattachDisposition runDisposition(ScenarioLabRunId runId) =>
      _disposition(store.requireRun(runId));

  bool get isClosed => _closed;

  ScenarioLabStartOutcome start({
    required ScenarioLabRunStartRequest request,
    required ExperienceContentSetIdentity contentSet,
    required CatalogManifest catalog,
    required ScenarioLabManifest manifest,
  }) {
    if (!_acceptingStarts) {
      throw StateError('Scenario Lab execution service is closing');
    }
    final existing = store.findByRequestId(request.requestId);
    if (existing != null) {
      if (existing.request.digest != request.digest) {
        throw ScenarioLabRequestConflict(request.requestId);
      }
      return ScenarioLabStartOutcome(
        created: false,
        snapshot: existing.latestObservable,
        disposition: _disposition(existing),
      );
    }

    if (catalog.digest != contentSet.catalogDigest) {
      throw ArgumentError(
        'Scenario Lab Catalog does not match the Content Set',
      );
    }
    request.validateAgainst(
      contentSet: contentSet,
      scenarioLabManifest: manifest,
    );
    final executionPlan = planner.plan(
      catalog: catalog,
      manifest: manifest,
      scenarioId: request.scenarioId,
      scriptId: request.scriptId,
      expectedCatalogDigest: contentSet.catalogDigest,
      expectedScenarioLabManifestDigest:
          request.expectedScenarioLabManifestDigest,
    );
    _validateSupportedPlan(executionPlan, manifest, evidence);
    final plan = executionPlan.plan;
    final script = executionPlan.script;
    final binding = executionPlan.initialBinding;
    final runId = identities.nextRunId();
    final nonce = identities.nextRelayNonce();
    final runtimeInputs = target.resolveRuntimeInputs(
      runId: runId,
      binding: binding,
    )..validateAgainst(binding);
    final now = clock.nowUtc();
    final initialAcceptance = <AutomatedAcceptanceResult>[
      for (final id in plan.automatedAcceptanceCriterionIds)
        AutomatedAcceptanceResult(
          criterionId: id,
          verificationState: VerificationState.notRun,
        ),
    ];
    final initialEvidence = <RequiredEvidenceRunResult>[
      for (final id in plan.requiredEvidenceIds)
        _pendingEvidence(
          manifest.requiredEvidence.singleWhere((item) => item.id == id),
        ),
    ];
    final initial = ScenarioLabRunSnapshot(
      runId: runId,
      startRequestDigest: request.digest,
      contentSetDigest: contentSet.contentSetDigest,
      catalogDigest: catalog.digest,
      scenarioLabManifestDigest: manifest.digest,
      scenarioId: request.scenarioId,
      scriptId: request.scriptId,
      sequence: 0,
      observedAt: now,
      state: ScenarioLabRunState.queued,
      steps: <ScenarioLabStepSnapshot>[
        for (final step in script.steps)
          ScenarioLabStepSnapshot(
            stepId: step.id,
            state: ScenarioLabStepState.pending,
          ),
      ],
      requiredEvidence: initialEvidence,
      automatedAcceptance: initialAcceptance,
      cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.pending),
    );
    final registration = store.register(
      request: request,
      initialSnapshot: initial,
    );
    if (!registration.created) {
      return ScenarioLabStartOutcome(
        created: false,
        snapshot: registration.run.latestObservable,
        disposition: _disposition(registration.run),
      );
    }
    final execution = _RunExecution(
      request: request,
      manifest: manifest,
      executionPlan: executionPlan,
      runId: runId,
      nonce: nonce,
      runtimeInputs: runtimeInputs,
      evidenceResults: <RequiredEvidenceId, RequiredEvidenceRunResult>{
        for (final result in initialEvidence) result.requiredEvidenceId: result,
      },
      acceptanceResults:
          <AutomatedAcceptanceCriterionId, AutomatedAcceptanceResult>{
            for (final result in initialAcceptance) result.criterionId: result,
          },
    );
    _active[runId.value] = execution;
    unawaited(_execute(execution));
    return ScenarioLabStartOutcome(
      created: true,
      snapshot: initial,
      disposition: ScenarioLabReattachDisposition.active,
    );
  }

  ScenarioLabRunSnapshot snapshot(ScenarioLabRunId runId) =>
      store.requireRun(runId).latestObservable;

  Future<ScenarioLabRunResult> waitForResult(ScenarioLabRunId runId) {
    final stored = store.requireRun(runId);
    final result = stored.result;
    if (result != null) return Future<ScenarioLabRunResult>.value(result);
    if (stored.interrupted) {
      return Future<ScenarioLabRunResult>.error(
        ScenarioLabInterruptedRun(runId),
      );
    }
    final execution = _active[runId.value];
    if (execution == null) {
      return Future<ScenarioLabRunResult>.error(
        ScenarioLabInterruptedRun(runId),
      );
    }
    return execution.completion.future;
  }

  ScenarioLabRunSnapshot cancel(ScenarioLabRunId runId) {
    final stored = store.requireRun(runId);
    if (_disposition(stored) == ScenarioLabReattachDisposition.interrupted) {
      throw ScenarioLabInterruptedRun(runId);
    }
    if (stored.latest.state.isTerminal) return stored.latest;
    final execution = _active[runId.value];
    if (execution == null) throw ScenarioLabInterruptedRun(runId);
    return _requestCancellation(
      execution,
      cause: ScenarioLabTerminalCause.cancelledByUser,
      forceImmediate: false,
    );
  }

  /// Stops accepting starts, force-cancels every active run, and waits for
  /// each terminal result to be committed before returning.
  ///
  /// A timed-out drain deliberately leaves external ports open. The owner may
  /// retry [close], but must not close target, relay, or capture authorities
  /// while an execution can still append to its journal.
  Future<void> close() {
    if (_closed) return Future<void>.value();
    final closing = _closing;
    if (closing != null) return closing;
    _acceptingStarts = false;
    late final Future<void> tracked;
    tracked = _drainForShutdown().whenComplete(() {
      if (identical(_closing, tracked)) _closing = null;
    });
    _closing = tracked;
    return tracked;
  }

  Future<void> _drainForShutdown() async {
    final executions = _active.values.toList(growable: false)
      ..sort((left, right) => left.runId.value.compareTo(right.runId.value));
    Object? firstFailure;
    StackTrace? firstFailureStackTrace;
    void preserveFailure(Object error, StackTrace stackTrace) {
      firstFailure ??= error;
      firstFailureStackTrace ??= stackTrace;
    }

    for (final execution in executions) {
      if (!_active.containsKey(execution.runId.value)) continue;
      try {
        _requestCancellation(
          execution,
          cause: ScenarioLabTerminalCause.hostShutdown,
          forceImmediate: true,
        );
      } on Object catch (error, stackTrace) {
        // Cancellation flags and the in-memory signal are set before the
        // journal append. One failed append must not prevent signalling every
        // other owner or awaiting all settlements.
        preserveFailure(error, stackTrace);
      }
    }
    if (executions.isNotEmpty) {
      try {
        await deadlines.run<void>(
          timeout: shutdownTimeout,
          action: () => Future.wait<void>(<Future<void>>[
            for (final execution in executions)
              execution.completion.future.then<void>(
                (_) {},
                onError: (Object error, StackTrace stackTrace) {
                  preserveFailure(error, stackTrace);
                },
              ),
          ]),
        );
      } on ScenarioLabDeadlineExceeded catch (error, stackTrace) {
        if (_active.isNotEmpty) {
          throw ScenarioLabShutdownTimedOut(
            _active.values.map((execution) => execution.runId),
          );
        }
        preserveFailure(error, stackTrace);
      } on Object catch (error, stackTrace) {
        preserveFailure(error, stackTrace);
      }
    }
    if (_active.isNotEmpty) {
      throw StateError('Scenario Lab shutdown completed with active runs');
    }
    _closed = true;
    if (firstFailure case final failure?) {
      Error.throwWithStackTrace(failure, firstFailureStackTrace!);
    }
  }

  ScenarioLabRunSnapshot _requestCancellation(
    _RunExecution execution, {
    required ScenarioLabTerminalCause cause,
    required bool forceImmediate,
  }) {
    execution
      ..cancelRequested = true
      ..cancellationCause ??= cause
      ..targetAbortRequired = true;
    if (execution.targetEffectsStarted && execution.session == null) {
      unawaited(_startTargetAbort(execution));
    }
    if (forceImmediate ||
        execution.script.cancellationPolicy ==
            ScenarioScriptCancellationPolicy.immediate) {
      execution.cancellation.cancel();
    }
    final current = store.requireRun(execution.runId).latest;
    if (current.runtimeInputs != null &&
        !current.state.isTerminal &&
        current.state != ScenarioLabRunState.cancelling) {
      return _append(execution, state: ScenarioLabRunState.cancelling);
    }
    return current;
  }

  void _requestForcedTargetAbort(_RunExecution execution) {
    execution
      ..targetAbortRequired = true
      ..cancellation.cancel();
    if (execution.targetEffectsStarted && execution.session == null) {
      unawaited(_startTargetAbort(execution));
    }
  }

  Future<_TargetAbortFailure?> _startTargetAbort(_RunExecution execution) =>
      execution.targetAbort ??=
          Future<void>.sync(
            () => target.abort(execution.runId),
          ).then<_TargetAbortFailure?>(
            (_) => null,
            onError: (Object error, StackTrace stackTrace) =>
                const _TargetAbortFailure(),
          );

  ScenarioLabReattachView reattach(
    ScenarioLabRunId runId, {
    int afterSequence = -1,
  }) {
    final stored = store.requireRun(runId);
    final current = stored.latestObservable;
    final observations = store
        .observationsAfter(runId, afterSequence)
        .where((snapshot) => snapshot.sequence <= current.sequence);
    return ScenarioLabReattachView(
      disposition: _disposition(stored),
      current: current,
      observations: observations,
    );
  }

  ScenarioLabReattachDisposition _disposition(ScenarioLabStoredRun run) =>
      run.result != null
      ? ScenarioLabReattachDisposition.terminal
      : run.interrupted ||
            run.hasUncommittedTerminalSnapshot ||
            isRunFailedClosed(run.latest.runId)
      ? ScenarioLabReattachDisposition.interrupted
      : _active.containsKey(run.latest.runId.value)
      ? ScenarioLabReattachDisposition.active
      : ScenarioLabReattachDisposition.interrupted;

  Future<void> _execute(_RunExecution execution) async {
    try {
      await _executeBody(execution);
    } on Object catch (error, stackTrace) {
      await _failClosedExecution(execution, error, stackTrace);
    }
  }

  Future<void> _executeBody(_RunExecution execution) async {
    execution
      ..startedAt = clock.nowUtc()
      ..startedMonotonicMicros = clock.monotonicMicroseconds();
    try {
      if (execution.cancelRequested) {
        _append(
          execution,
          state: ScenarioLabRunState.cancelling,
          steps: _terminalizeSteps(
            _current(execution).steps,
            activeIndex: 0,
            activeState: ScenarioLabStepState.cancelled,
            activeCause: ScenarioLabStepTerminalCause.cancelled,
            completedAt: _now(execution),
          ),
        );
        _terminalizePendingEvidence(
          execution,
          state: RequiredEvidenceResultState.cancelled,
        );
        await _finish(
          execution,
          state: ScenarioLabRunState.cancelled,
          cause: _cancellationCause(execution),
        );
        return;
      }

      _beginStep(execution, 0, runState: ScenarioLabRunState.starting);
      final session = await _withinStep(execution, 0, () {
        execution.targetEffectsStarted = true;
        try {
          return target.attach(
            runId: execution.runId,
            binding: execution.binding,
            nonce: execution.nonce,
            cancellation: execution.cancellation,
          );
        } finally {
          if (execution.targetAbortRequired && execution.session == null) {
            unawaited(_startTargetAbort(execution));
          }
        }
      });
      execution.session = session;
      _validateHello(execution, session.hello);
      _throwIfImmediateCancellation(execution);
      for (final controlId in execution.plan.controlIds) {
        final control = execution.control(controlId);
        final command = ReadAppAdapterRelayCommand(
          runId: execution.runId,
          commandId: _nextCommandId(execution),
          sequence: _nextCommandSequence(execution),
          nonce: execution.nonce,
          controlId: control.id,
          capability: control.capability,
          operationId: control.readOperationId,
        );
        command.validateControl(
          hello: session.hello,
          manifest: execution.manifest,
          scenarioId: execution.request.scenarioId,
        );
        final result = await _send(execution, 0, command);
        final value = _controlValue(result, control);
        execution.controlResults[control.id] = ScenarioControlResult(
          controlId: control.id,
          source: ScenarioControlResultSource.read,
          value: value,
        );
      }
      _succeedStep(execution, 0);
      _throwIfCancellation(execution);

      for (var index = 1; index < execution.script.steps.length; index += 1) {
        _throwIfCancellation(execution);
        final step = execution.executionPlan.steps[index];
        _beginStep(execution, index, runState: ScenarioLabRunState.running);
        await _runOperationStep(execution, index, step);
        if (index == execution.script.steps.length - 1) {
          await _refreshControls(execution, index);
        }
        _succeedStep(execution, index);
        _throwIfCancellation(execution);
      }

      _terminalizePendingEvidence(
        execution,
        state: RequiredEvidenceResultState.missing,
      );
      final comparisonFailed = await _evaluateComparisons(execution);
      _throwIfCancellation(execution);
      _evaluateAcceptance(execution);
      final verificationFailed =
          execution.acceptanceResults.values.any(
            (result) =>
                result.verificationState == VerificationState.failed ||
                result.verificationState == VerificationState.error,
          ) ||
          comparisonFailed;
      await _finish(
        execution,
        state: verificationFailed
            ? ScenarioLabRunState.failed
            : ScenarioLabRunState.succeeded,
        cause: verificationFailed
            ? ScenarioLabTerminalCause.acceptanceFailed
            : ScenarioLabTerminalCause.completed,
      );
    } on _RequestedCancellation {
      _terminalizePendingEvidence(
        execution,
        state: RequiredEvidenceResultState.cancelled,
      );
      _prepareTerminalSteps(
        execution,
        state: ScenarioLabStepState.cancelled,
        cause: ScenarioLabStepTerminalCause.cancelled,
      );
      await _finish(
        execution,
        state: ScenarioLabRunState.cancelled,
        cause: _cancellationCause(execution),
      );
    } on _ExecutionTimedOut catch (error) {
      _requestForcedTargetAbort(execution);
      final cancelled = error.outcome == ScenarioScriptTimeoutOutcome.cancel;
      _terminalizePendingEvidence(
        execution,
        state: cancelled
            ? RequiredEvidenceResultState.cancelled
            : RequiredEvidenceResultState.failed,
        failureCause: cancelled ? null : ScenarioLabFailureCause.timedOut,
      );
      _prepareTerminalSteps(
        execution,
        state: cancelled
            ? ScenarioLabStepState.cancelled
            : ScenarioLabStepState.failed,
        cause: cancelled
            ? ScenarioLabStepTerminalCause.cancelled
            : ScenarioLabStepTerminalCause.timedOut,
      );
      await _finish(
        execution,
        state: cancelled
            ? ScenarioLabRunState.cancelled
            : ScenarioLabRunState.failed,
        cause: ScenarioLabTerminalCause.timedOut,
      );
    } on ScenarioLabTargetCancelled {
      _requestForcedTargetAbort(execution);
      _terminalizePendingEvidence(
        execution,
        state: RequiredEvidenceResultState.cancelled,
      );
      _prepareTerminalSteps(
        execution,
        state: ScenarioLabStepState.cancelled,
        cause: ScenarioLabStepTerminalCause.cancelled,
      );
      await _finish(
        execution,
        state: ScenarioLabRunState.cancelled,
        cause: _cancellationCause(execution),
      );
    } on ScenarioLabComparisonCancelled {
      _requestForcedTargetAbort(execution);
      _terminalizePendingEvidence(
        execution,
        state: RequiredEvidenceResultState.cancelled,
      );
      _prepareTerminalSteps(
        execution,
        state: ScenarioLabStepState.cancelled,
        cause: ScenarioLabStepTerminalCause.cancelled,
      );
      await _finish(
        execution,
        state: ScenarioLabRunState.cancelled,
        cause: _cancellationCause(execution),
      );
    } on ScenarioLabAdapterDisconnected {
      _terminalizePendingEvidence(
        execution,
        state: RequiredEvidenceResultState.failed,
        failureCause: ScenarioLabFailureCause.adapterDisconnected,
      );
      _prepareTerminalSteps(
        execution,
        state: ScenarioLabStepState.failed,
        cause: ScenarioLabStepTerminalCause.operationFailed,
      );
      await _finish(
        execution,
        state: ScenarioLabRunState.failed,
        cause: ScenarioLabTerminalCause.adapterDisconnected,
      );
    } on _StepExecutionFailed {
      _terminalizePendingEvidence(
        execution,
        state: RequiredEvidenceResultState.missing,
      );
      _prepareTerminalSteps(
        execution,
        state: ScenarioLabStepState.failed,
        cause: ScenarioLabStepTerminalCause.operationFailed,
      );
      await _finish(
        execution,
        state: ScenarioLabRunState.failed,
        cause: ScenarioLabTerminalCause.stepFailed,
      );
    } on Object catch (error, stackTrace) {
      try {
        _terminalizePendingEvidence(
          execution,
          state: RequiredEvidenceResultState.failed,
          failureCause: ScenarioLabFailureCause.internalError,
        );
        _prepareTerminalSteps(
          execution,
          state: ScenarioLabStepState.failed,
          cause: ScenarioLabStepTerminalCause.operationFailed,
        );
        await _finish(
          execution,
          state: ScenarioLabRunState.failed,
          cause: ScenarioLabTerminalCause.internalError,
        );
      } on Object catch (terminalError, terminalStackTrace) {
        Error.throwWithStackTrace(terminalError, terminalStackTrace);
      }
      if (!execution.completion.isCompleted) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Future<void> _failClosedExecution(
    _RunExecution execution,
    Object error,
    StackTrace stackTrace,
  ) async {
    _failedClosedRunIds.add(execution.runId.value);
    _active.remove(execution.runId.value);
    execution
      ..targetAbortRequired = true
      ..cancellation.cancel();

    // Preserve the last committed journal truth. The store rolls a provisional
    // terminal preparation back before durably recording interruption.
    try {
      final stored = store.requireRun(execution.runId);
      if (stored.result == null && !stored.interrupted) {
        store.interrupt(execution.runId);
      }
    } on Object {
      // The process-local failed-closed marker keeps public reads closed even
      // when the same storage fault also prevents the interruption tombstone.
    }

    if (execution.targetEffectsStarted) {
      try {
        await deadlines.run<_TargetAbortFailure?>(
          timeout: cleanupTimeout,
          action: () => _startTargetAbort(execution),
        );
      } on Object {
        // Public authority is already revoked above. Shutdown may retry the
        // concrete owner cleanup, but this execution can no longer look active.
      }
    }
    if (!execution.completion.isCompleted) {
      execution.completion.completeError(error, stackTrace);
    }
  }

  Future<void> _runOperationStep(
    _RunExecution execution,
    int stepIndex,
    PlannedScenarioLabStep step,
  ) async {
    if (step is! PlannedScenarioLabOperationStep) {
      throw const _StepExecutionFailed();
    }
    final operation = step.operation;
    switch (operation) {
      case AssignControlOperationDefinition():
        await _assignControl(execution, stepIndex, operation);
      case ResetControlOperationDefinition():
        await _resetControl(execution, stepIndex, operation);
      case CollectEvidenceOperationDefinition():
        await _collectEvidence(execution, stepIndex, operation);
    }
  }

  Future<void> _collectEvidence(
    _RunExecution execution,
    int stepIndex,
    CollectEvidenceOperationDefinition operation,
  ) async {
    final evidencePort = evidence;
    if (evidencePort == null) {
      throw StateError('Unsupported Evidence operation reached execution');
    }
    final requirement = execution.requirement(operation.evidenceRequirementId);
    execution.evidenceCleanupRequired = true;
    AppAdapterRelayCaptureUploadGrant uploadGrant;
    try {
      uploadGrant = await _withinStep(
        execution,
        stepIndex,
        () => evidencePort.issueCaptureUpload(
          runId: execution.runId,
          requirement: requirement,
          runtimeInputs: execution.runtimeInputs,
          cancellation: execution.cancellation,
        ),
      );
    } on _ExecutionTimedOut {
      rethrow;
    } on ScenarioLabTargetCancelled {
      rethrow;
    } on ScenarioLabEvidencePolicyDenied {
      _recordUnavailableEvidence(
        execution,
        requirement,
        state: RequiredEvidenceResultState.policyDenied,
      );
      throw const _StepExecutionFailed();
    } on ScenarioLabEvidenceInvalidInput {
      _recordEvidenceFailure(
        execution,
        requirement,
        cause: ScenarioLabFailureCause.invalidResponse,
      );
      throw const _StepExecutionFailed();
    } on Object {
      _recordEvidenceFailure(
        execution,
        requirement,
        cause: ScenarioLabFailureCause.internalError,
      );
      throw const _StepExecutionFailed();
    }
    if (!uploadGrant.expiresAt.isAfter(clock.nowUtc()) ||
        !execution.captureRequestIds.add(uploadGrant.requestId)) {
      _recordEvidenceFailure(
        execution,
        requirement,
        cause: ScenarioLabFailureCause.invalidResponse,
      );
      throw const _StepExecutionFailed();
    }

    final command = CaptureAppAdapterRelayCommand(
      runId: execution.runId,
      commandId: _nextCommandId(execution),
      sequence: _nextCommandSequence(execution),
      nonce: execution.nonce,
      requiredEvidenceId: requirement.id,
      providerId: requirement.providerId,
      uploadGrant: uploadGrant,
    );
    try {
      command.validateManifest(
        hello: execution.requireSession().hello,
        manifest: execution.manifest,
        scenarioId: execution.request.scenarioId,
      );
      final relayResult = await _send(execution, stepIndex, command);
      if (relayResult is! CaptureAppAdapterRelayResult) {
        throw const _StepExecutionFailed();
      }
      final collection = await _withinStep(
        execution,
        stepIndex,
        () => evidencePort.consumeCaptureUpload(
          runId: execution.runId,
          requirement: requirement,
          uploadGrant: uploadGrant,
          cancellation: execution.cancellation,
        ),
      );
      if (collection == null) {
        _recordUnavailableEvidence(
          execution,
          requirement,
          state: RequiredEvidenceResultState.missing,
        );
        throw const _StepExecutionFailed();
      }
      final rejection = _validateEvidenceCollection(
        execution: execution,
        requirement: requirement,
        uploadGrant: uploadGrant,
        collection: collection,
      );
      if (rejection != null) {
        if (rejection == RequiredEvidenceResultState.policyDenied) {
          _recordUnavailableEvidence(
            execution,
            requirement,
            state: RequiredEvidenceResultState.policyDenied,
          );
        } else {
          _recordEvidenceFailure(
            execution,
            requirement,
            cause: ScenarioLabFailureCause.invalidResponse,
          );
        }
        throw const _StepExecutionFailed();
      }
      final receipt = collection.uploadReceipt;
      final evidenceValue = collection.evidence;
      final artifact = evidenceValue.artifacts.single;
      execution.evidenceResults[requirement.id] = RequiredEvidenceRunResult(
        requiredEvidenceId: requirement.id,
        providerId: requirement.providerId,
        fidelity: evidenceValue.fingerprint.runtimeFidelity,
        variantId: requirement.variantId,
        freshness: EvidenceFreshness.fresh,
        state: RequiredEvidenceResultState.collected,
        evidenceDigest: evidenceValue.digest,
        artifacts: <ScenarioEvidenceArtifactResult>[
          ScenarioEvidenceArtifactResult(
            artifactDigest: artifact.digest,
            provenanceDigest: receipt.digest,
            classification: artifact.classification,
          ),
        ],
      );
      _append(execution, state: _activeObservationState(execution));
    } on _ExecutionTimedOut {
      rethrow;
    } on ScenarioLabTargetCancelled {
      rethrow;
    } on ScenarioLabEvidencePolicyDenied {
      if (_isEvidencePending(execution, requirement.id)) {
        _recordUnavailableEvidence(
          execution,
          requirement,
          state: RequiredEvidenceResultState.policyDenied,
        );
      }
      throw const _StepExecutionFailed();
    } on ScenarioLabEvidenceInvalidInput {
      if (_isEvidencePending(execution, requirement.id)) {
        _recordEvidenceFailure(
          execution,
          requirement,
          cause: ScenarioLabFailureCause.invalidResponse,
        );
      }
      throw const _StepExecutionFailed();
    } on _StepExecutionFailed {
      if (_isEvidencePending(execution, requirement.id)) {
        _recordEvidenceFailure(
          execution,
          requirement,
          cause: ScenarioLabFailureCause.invalidResponse,
        );
      }
      rethrow;
    } on Object {
      if (_isEvidencePending(execution, requirement.id)) {
        _recordEvidenceFailure(
          execution,
          requirement,
          cause: ScenarioLabFailureCause.internalError,
        );
      }
      throw const _StepExecutionFailed();
    }
  }

  Future<void> _assignControl(
    _RunExecution execution,
    int stepIndex,
    AssignControlOperationDefinition operation,
  ) async {
    final session = execution.requireSession();
    final control = execution.control(operation.controlId);
    final command = WriteAppAdapterRelayCommand(
      runId: execution.runId,
      commandId: _nextCommandId(execution),
      sequence: _nextCommandSequence(execution),
      nonce: execution.nonce,
      controlId: control.id,
      capability: control.capability,
      operationId: control.writeOperationId,
      value: operation.value,
    );
    command.validateControl(
      hello: session.hello,
      manifest: execution.manifest,
      scenarioId: execution.request.scenarioId,
      value: operation.value,
    );
    // A write may have reached the target even if its response is lost. Mark
    // it dirty before crossing the port so every failure path retries reset.
    execution.dirtyControls.add(control.id);
    final result = await _send(execution, stepIndex, command);
    final value = _controlValue(result, control);
    if (!_sameControlValue(value, operation.value)) {
      throw const _StepExecutionFailed();
    }
    execution.controlResults[control.id] = ScenarioControlResult(
      controlId: control.id,
      source: ScenarioControlResultSource.write,
      value: value,
    );
  }

  Future<void> _resetControl(
    _RunExecution execution,
    int stepIndex,
    ResetControlOperationDefinition operation,
  ) async {
    final control = execution.control(operation.controlId);
    execution.dirtyControls.add(control.id);
    try {
      await _sendReset(
        execution,
        control,
        (action) =>
            _withinStep<AppAdapterRelayResult>(execution, stepIndex, action),
        execution.cancellation,
      );
    } on _CleanupFailed {
      throw const _StepExecutionFailed();
    }
    final value = await _readControl(execution, stepIndex, control);
    if (!_sameControlValue(value, control.domain.defaultValue)) {
      throw const _StepExecutionFailed();
    }
    execution.controlResults[control.id] = ScenarioControlResult(
      controlId: control.id,
      source: ScenarioControlResultSource.read,
      value: value,
    );
    execution.dirtyControls.remove(control.id);
  }

  Future<void> _refreshControls(_RunExecution execution, int stepIndex) async {
    for (final controlId in execution.plan.controlIds) {
      final control = execution.control(controlId);
      final value = await _readControl(execution, stepIndex, control);
      execution.controlResults[control.id] = ScenarioControlResult(
        controlId: control.id,
        source: ScenarioControlResultSource.read,
        value: value,
      );
    }
  }

  Future<ScenarioControlValue> _readControl(
    _RunExecution execution,
    int stepIndex,
    ScenarioControlDefinition control,
  ) async {
    final command = ReadAppAdapterRelayCommand(
      runId: execution.runId,
      commandId: _nextCommandId(execution),
      sequence: _nextCommandSequence(execution),
      nonce: execution.nonce,
      controlId: control.id,
      capability: control.capability,
      operationId: control.readOperationId,
    );
    command.validateControl(
      hello: execution.requireSession().hello,
      manifest: execution.manifest,
      scenarioId: execution.request.scenarioId,
    );
    return _controlValue(await _send(execution, stepIndex, command), control);
  }

  Future<AppAdapterRelayResult> _send(
    _RunExecution execution,
    int stepIndex,
    AppAdapterRelayCommand command,
  ) async {
    final result = await _withinStep(
      execution,
      stepIndex,
      () => execution.requireSession().execute(
        command,
        cancellation: execution.cancellation,
      ),
    );
    _throwIfImmediateCancellation(execution);
    try {
      result.validateAgainst(command);
    } on ArgumentError {
      throw const _StepExecutionFailed();
    }
    if (result.state == AppAdapterRelayResultState.failed) {
      throw const _StepExecutionFailed();
    }
    if (result.state == AppAdapterRelayResultState.cancelled) {
      _throwIfCancellation(execution);
      throw const _StepExecutionFailed();
    }
    return result;
  }

  ScenarioControlValue _controlValue(
    AppAdapterRelayResult result,
    ScenarioControlDefinition control,
  ) {
    final value = switch (result) {
      ReadAppAdapterRelayResult() => result.value,
      WriteAppAdapterRelayResult() => result.value,
      ResetAppAdapterRelayResult() => result.value,
      _ => null,
    };
    if (value == null || !control.domain.accepts(value)) {
      throw const _StepExecutionFailed();
    }
    return value;
  }

  RequiredEvidenceResultState? _validateEvidenceCollection({
    required _RunExecution execution,
    required RequiredEvidenceDefinition requirement,
    required AppAdapterRelayCaptureUploadGrant uploadGrant,
    required ScenarioLabHostEvidenceCollection collection,
  }) {
    final receipt = collection.uploadReceipt;
    final evidenceValue = collection.evidence;
    if (receipt.requestId != uploadGrant.requestId ||
        receipt.sessionId != uploadGrant.sessionId ||
        receipt.size < 1 ||
        receipt.width < 1 ||
        receipt.height < 1 ||
        receipt.completedAt.isAfter(clock.nowUtc()) ||
        evidenceValue.artifacts.length != 1) {
      return RequiredEvidenceResultState.failed;
    }
    final artifact = evidenceValue.artifacts.single;
    if (artifact.digest != receipt.artifactDigest ||
        artifact.size != receipt.size ||
        artifact.mediaType !=
            AppAdapterRelayCaptureUploadGrant.expectedMediaType ||
        artifact.pixelDigest != receipt.pixelDigest ||
        artifact.width != receipt.width ||
        artifact.height != receipt.height ||
        evidenceValue.observedAt.toUtc() != receipt.completedAt.toUtc() ||
        evidenceValue.subjectDigest != _current(execution).catalogDigest ||
        evidenceValue.fingerprint.catalogDigest !=
            _current(execution).catalogDigest ||
        evidenceValue.fingerprint.digest !=
            execution.runtimeInputs.executionFingerprintDigest ||
        evidenceValue.fingerprint.runtimeFidelity != requirement.fidelity ||
        evidenceValue.policyId != requirement.evidencePolicyId.value ||
        evidenceValue.freshnessFor(
              _current(execution).catalogDigest,
              artifactsValid: true,
            ) !=
            requirement.freshness) {
      return RequiredEvidenceResultState.failed;
    }
    if (!requirement.allowedClassifications.contains(artifact.classification)) {
      return RequiredEvidenceResultState.policyDenied;
    }
    return null;
  }

  bool _isEvidencePending(_RunExecution execution, RequiredEvidenceId id) =>
      execution.evidenceResults[id]?.state ==
      RequiredEvidenceResultState.pending;

  void _recordEvidenceFailure(
    _RunExecution execution,
    RequiredEvidenceDefinition requirement, {
    required ScenarioLabFailureCause cause,
  }) {
    execution.evidenceResults[requirement.id] = RequiredEvidenceRunResult(
      requiredEvidenceId: requirement.id,
      providerId: requirement.providerId,
      fidelity: requirement.fidelity,
      variantId: requirement.variantId,
      freshness: EvidenceFreshness.invalid,
      state: RequiredEvidenceResultState.failed,
      failure: ScenarioLabFailure(cause: cause),
    );
    _append(execution, state: _activeObservationState(execution));
  }

  void _recordUnavailableEvidence(
    _RunExecution execution,
    RequiredEvidenceDefinition requirement, {
    required RequiredEvidenceResultState state,
  }) {
    if (!const <RequiredEvidenceResultState>{
      RequiredEvidenceResultState.missing,
      RequiredEvidenceResultState.policyDenied,
      RequiredEvidenceResultState.cancelled,
    }.contains(state)) {
      throw ArgumentError.value(state, 'state');
    }
    execution.evidenceResults[requirement.id] = RequiredEvidenceRunResult(
      requiredEvidenceId: requirement.id,
      providerId: requirement.providerId,
      fidelity: requirement.fidelity,
      variantId: requirement.variantId,
      freshness: EvidenceFreshness.missing,
      state: state,
    );
    _append(execution, state: _activeObservationState(execution));
  }

  ScenarioLabRunState _activeObservationState(_RunExecution execution) {
    final state = _current(execution).state;
    return state == ScenarioLabRunState.cancelling
        ? ScenarioLabRunState.cancelling
        : ScenarioLabRunState.running;
  }

  Future<ScenarioControlValue> _sendReset(
    _RunExecution execution,
    ScenarioControlDefinition control,
    Future<AppAdapterRelayResult> Function(
      Future<AppAdapterRelayResult> Function() action,
    )
    bounded,
    ScenarioLabCancellationSignal cancellation,
  ) async {
    final resetOperationId = control.resetOperationId;
    if (resetOperationId == null) throw const _CleanupFailed();
    final command = ResetAppAdapterRelayCommand(
      runId: execution.runId,
      commandId: _nextCommandId(execution),
      sequence: _nextCommandSequence(execution),
      nonce: execution.nonce,
      controlId: control.id,
      capability: control.capability,
      operationId: resetOperationId,
    );
    command.validateControl(
      hello: execution.requireSession().hello,
      manifest: execution.manifest,
      scenarioId: execution.request.scenarioId,
    );
    final result = await bounded(
      () => execution.requireSession().execute(
        command,
        cancellation: cancellation,
      ),
    );
    try {
      result.validateAgainst(command);
    } on ArgumentError {
      throw const _CleanupFailed();
    }
    if (result.state != AppAdapterRelayResultState.succeeded) {
      throw const _CleanupFailed();
    }
    final value = _controlValue(result, control);
    if (!_sameControlValue(value, control.domain.defaultValue)) {
      throw const _CleanupFailed();
    }
    return value;
  }

  void _evaluateAcceptance(_RunExecution execution) {
    for (final id in execution.plan.automatedAcceptanceCriterionIds) {
      final criterion = execution.manifest.automatedAcceptanceCriteria
          .singleWhere((item) => item.id == id);
      final passed = switch (criterion) {
        ScriptSucceededAcceptanceCriterion() =>
          criterion.scriptId == execution.script.id &&
              _current(execution).steps.every(
                (step) => step.state == ScenarioLabStepState.succeeded,
              ),
        EvidenceAcceptedAcceptanceCriterion() =>
          execution.evidenceResults[criterion.evidenceRequirementId]?.state ==
              RequiredEvidenceResultState.collected,
        ControlEqualsAcceptanceCriterion() => _sameControlValue(
          execution.controlResults[criterion.controlId]?.value,
          criterion.expectedValue,
        ),
      };
      execution.acceptanceResults[id] = AutomatedAcceptanceResult(
        criterionId: id,
        verificationState: passed
            ? VerificationState.passed
            : VerificationState.failed,
      );
    }
  }

  void _terminalizePendingEvidence(
    _RunExecution execution, {
    required RequiredEvidenceResultState state,
    ScenarioLabFailureCause? failureCause,
  }) {
    if ((state == RequiredEvidenceResultState.failed) !=
        (failureCause != null)) {
      throw ArgumentError(
        'Failed Evidence terminalization requires a failure cause',
      );
    }
    var changed = false;
    for (final entry in execution.evidenceResults.entries.toList()) {
      if (entry.value.state != RequiredEvidenceResultState.pending) continue;
      final requirement = execution.requirement(entry.key);
      execution.evidenceResults[entry.key] = RequiredEvidenceRunResult(
        requiredEvidenceId: requirement.id,
        providerId: requirement.providerId,
        fidelity: requirement.fidelity,
        variantId: requirement.variantId,
        freshness: state == RequiredEvidenceResultState.failed
            ? EvidenceFreshness.invalid
            : EvidenceFreshness.missing,
        state: state,
        failure: failureCause == null
            ? null
            : ScenarioLabFailure(cause: failureCause),
      );
      changed = true;
    }
    if (changed) {
      _append(execution, state: _activeObservationState(execution));
    }
  }

  Future<bool> _evaluateComparisons(_RunExecution execution) async {
    if (execution.plan.comparisonBindingIds.isEmpty) return false;
    var failed = false;
    for (final id in execution.plan.comparisonBindingIds) {
      _throwIfCancellation(execution);
      final binding = execution.manifest.comparisonBindings.singleWhere(
        (item) => item.id == id,
      );
      final requirement = execution.requirement(binding.requiredEvidenceId);
      final baselineDigest = _comparisonInputDigest(
        execution,
        binding.baseline,
      );
      final candidateDigest = _comparisonInputDigest(
        execution,
        binding.candidate,
      );
      if (baselineDigest == null || candidateDigest == null) {
        failed = true;
        continue;
      }
      final baseline = _comparisonInputDescriptor(execution, binding.baseline);
      final candidate = _comparisonInputDescriptor(
        execution,
        binding.candidate,
      );
      late final ScenarioComparisonResult result;
      if (_comparisonInputIsAmbiguous(execution, binding.baseline) ||
          _comparisonInputIsAmbiguous(execution, binding.candidate)) {
        result = _comparisonWithoutMetrics(
          execution: execution,
          binding: binding,
          requirement: requirement,
          baselineDigest: baselineDigest,
          candidateDigest: candidateDigest,
          state: VerificationState.error,
          failureCause: ScenarioLabFailureCause.unsupported,
        );
      } else if (baseline == null || candidate == null) {
        failed = true;
        continue;
      } else if (!requirement.allowedClassifications.contains(
            baseline.classification,
          ) ||
          !requirement.allowedClassifications.contains(
            candidate.classification,
          )) {
        result = _comparisonWithoutMetrics(
          execution: execution,
          binding: binding,
          requirement: requirement,
          baselineDigest: baselineDigest,
          candidateDigest: candidateDigest,
          state: VerificationState.error,
          failureCause: ScenarioLabFailureCause.policyDenied,
        );
      } else if (comparison == null) {
        result = _comparisonWithoutMetrics(
          execution: execution,
          binding: binding,
          requirement: requirement,
          baselineDigest: baselineDigest,
          candidateDigest: candidateDigest,
          state: VerificationState.error,
          failureCause: ScenarioLabFailureCause.unsupported,
        );
      } else {
        try {
          result = await _runComparison(
            execution: execution,
            binding: binding,
            requirement: requirement,
            baseline: baseline,
            candidate: candidate,
          );
          _throwIfCancellation(execution);
        } on _ExecutionTimedOut {
          rethrow;
        } on ScenarioLabComparisonCancelled {
          rethrow;
        } on ScenarioLabComparisonInputMissing {
          result = _comparisonWithoutMetrics(
            execution: execution,
            binding: binding,
            requirement: requirement,
            baselineDigest: baselineDigest,
            candidateDigest: candidateDigest,
            state: VerificationState.notRun,
          );
        } on ScenarioLabComparisonPolicyDenied {
          result = _comparisonWithoutMetrics(
            execution: execution,
            binding: binding,
            requirement: requirement,
            baselineDigest: baselineDigest,
            candidateDigest: candidateDigest,
            state: VerificationState.error,
            failureCause: ScenarioLabFailureCause.policyDenied,
          );
        } on ScenarioLabComparisonUnsupported {
          result = _comparisonWithoutMetrics(
            execution: execution,
            binding: binding,
            requirement: requirement,
            baselineDigest: baselineDigest,
            candidateDigest: candidateDigest,
            state: VerificationState.error,
            failureCause: ScenarioLabFailureCause.unsupported,
          );
        } on ScenarioLabComparisonInputInvalid {
          result = _comparisonWithoutMetrics(
            execution: execution,
            binding: binding,
            requirement: requirement,
            baselineDigest: baselineDigest,
            candidateDigest: candidateDigest,
            state: VerificationState.error,
            failureCause: ScenarioLabFailureCause.invalidResponse,
          );
        } on Object {
          result = _comparisonWithoutMetrics(
            execution: execution,
            binding: binding,
            requirement: requirement,
            baselineDigest: baselineDigest,
            candidateDigest: candidateDigest,
            state: VerificationState.error,
            failureCause: ScenarioLabFailureCause.internalError,
          );
        }
      }
      execution.comparisonResults[id] = result;
      _append(execution, state: _activeObservationState(execution));
      if (result.verificationState != VerificationState.passed) failed = true;
    }
    return failed;
  }

  Future<ScenarioComparisonResult> _runComparison({
    required _RunExecution execution,
    required ScenarioComparisonBinding binding,
    required RequiredEvidenceDefinition requirement,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
  }) async {
    final comparisonPort = comparison!;
    return switch (requirement.comparisonPolicy) {
      VisualComparisonPolicyReference(:final policyId) =>
        _visualComparisonResult(
          binding: binding,
          policy: execution.manifest.visualComparisonPolicies.singleWhere(
            (item) => item.id == policyId,
          ),
          baseline: baseline,
          candidate: candidate,
          metrics: await _withinScript(
            execution,
            () => comparisonPort.compareVisual(
              runId: execution.runId,
              baseline: baseline,
              candidate: candidate,
              policy: execution.manifest.visualComparisonPolicies.singleWhere(
                (item) => item.id == policyId,
              ),
              cancellation: execution.cancellation,
            ),
          ),
        ),
      SemanticComparisonPolicyReference(:final policyId) =>
        _semanticComparisonResult(
          binding: binding,
          policy: execution.manifest.semanticComparisonPolicies.singleWhere(
            (item) => item.id == policyId,
          ),
          baseline: baseline,
          candidate: candidate,
          metrics: await _withinScript(
            execution,
            () => comparisonPort.compareSemantic(
              runId: execution.runId,
              baseline: baseline,
              candidate: candidate,
              policy: execution.manifest.semanticComparisonPolicies.singleWhere(
                (item) => item.id == policyId,
              ),
              cancellation: execution.cancellation,
            ),
          ),
        ),
    };
  }

  ScenarioComparisonResult _comparisonWithoutMetrics({
    required _RunExecution execution,
    required ScenarioComparisonBinding binding,
    required RequiredEvidenceDefinition requirement,
    required Digest baselineDigest,
    required Digest candidateDigest,
    required VerificationState state,
    ScenarioLabFailureCause? failureCause,
  }) {
    final failure = failureCause == null
        ? null
        : ScenarioLabFailure(cause: failureCause);
    return switch (requirement.comparisonPolicy) {
      VisualComparisonPolicyReference(:final policyId) =>
        VisualScenarioComparisonResult(
          bindingId: binding.id,
          requiredEvidenceId: binding.requiredEvidenceId,
          baselineDigest: baselineDigest,
          candidateDigest: candidateDigest,
          policyDigest: execution.manifest.visualComparisonPolicies
              .singleWhere((item) => item.id == policyId)
              .digest,
          verificationState: state,
          failure: failure,
        ),
      SemanticComparisonPolicyReference(:final policyId) =>
        SemanticScenarioComparisonResult(
          bindingId: binding.id,
          requiredEvidenceId: binding.requiredEvidenceId,
          baselineDigest: baselineDigest,
          candidateDigest: candidateDigest,
          policyDigest: execution.manifest.semanticComparisonPolicies
              .singleWhere((item) => item.id == policyId)
              .digest,
          verificationState: state,
          failure: failure,
        ),
    };
  }

  VisualScenarioComparisonResult _visualComparisonResult({
    required ScenarioComparisonBinding binding,
    required VisualComparisonPolicy policy,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
    required ScenarioLabVisualComparisonMetrics metrics,
  }) => VisualScenarioComparisonResult(
    bindingId: binding.id,
    requiredEvidenceId: binding.requiredEvidenceId,
    baselineDigest: baseline.artifactDigest,
    candidateDigest: candidate.artifactDigest,
    policyDigest: policy.digest,
    verificationState: metrics.passed
        ? VerificationState.passed
        : VerificationState.failed,
    comparedPixels: metrics.comparedPixels,
    changedPixels: metrics.changedPixels,
    maxChannelDeltaObserved: metrics.maxChannelDeltaObserved,
  );

  SemanticScenarioComparisonResult _semanticComparisonResult({
    required ScenarioComparisonBinding binding,
    required SemanticComparisonPolicy policy,
    required ScenarioLabComparisonArtifactDescriptor baseline,
    required ScenarioLabComparisonArtifactDescriptor candidate,
    required ScenarioLabSemanticComparisonMetrics metrics,
  }) => SemanticScenarioComparisonResult(
    bindingId: binding.id,
    requiredEvidenceId: binding.requiredEvidenceId,
    baselineDigest: baseline.artifactDigest,
    candidateDigest: candidate.artifactDigest,
    policyDigest: policy.digest,
    verificationState: metrics.passed
        ? VerificationState.passed
        : VerificationState.failed,
    comparedNodes: metrics.comparedNodes,
    changedNodes: metrics.changedNodes,
  );

  Digest? _comparisonInputDigest(
    _RunExecution execution,
    ComparisonInputReference input,
  ) => switch (input) {
    ArtifactComparisonInputReference(:final artifactId) =>
      execution.manifest.supplementalArtifacts
          .where((item) => item.id == artifactId)
          .firstOrNull
          ?.artifactDigest,
    EvidenceComparisonInputReference(:final evidenceDigest) => evidenceDigest,
    RequiredEvidenceComparisonInputReference(:final requiredEvidenceId) =>
      switch (execution.evidenceResults[requiredEvidenceId]) {
        RequiredEvidenceRunResult(
          state: RequiredEvidenceResultState.collected,
          artifacts: [final artifact],
        ) =>
          artifact.artifactDigest,
        RequiredEvidenceRunResult(
          state: RequiredEvidenceResultState.collected,
          evidenceDigest: final evidenceDigest?,
        ) =>
          evidenceDigest,
        _ => null,
      },
  };

  bool _comparisonInputIsAmbiguous(
    _RunExecution execution,
    ComparisonInputReference input,
  ) => switch (input) {
    EvidenceComparisonInputReference() => true,
    ArtifactComparisonInputReference() => false,
    RequiredEvidenceComparisonInputReference(:final requiredEvidenceId) =>
      switch (execution.evidenceResults[requiredEvidenceId]) {
        RequiredEvidenceRunResult(
          state: RequiredEvidenceResultState.collected,
          :final artifacts,
        ) =>
          artifacts.length != 1,
        _ => false,
      },
  };

  ScenarioLabComparisonArtifactDescriptor? _comparisonInputDescriptor(
    _RunExecution execution,
    ComparisonInputReference input,
  ) => switch (input) {
    ArtifactComparisonInputReference(:final artifactId) => switch (execution
        .manifest
        .supplementalArtifacts
        .where((item) => item.id == artifactId)
        .firstOrNull) {
      final SupplementalArtifactReference artifact =>
        ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: artifact.artifactDigest,
          provenanceDigest: artifact.provenanceDigest,
          classification: artifact.classification,
        ),
      null => null,
    },
    EvidenceComparisonInputReference() => null,
    RequiredEvidenceComparisonInputReference(:final requiredEvidenceId) =>
      switch (execution.evidenceResults[requiredEvidenceId]) {
        RequiredEvidenceRunResult(
          state: RequiredEvidenceResultState.collected,
          artifacts: [final artifact],
        ) =>
          ScenarioLabComparisonArtifactDescriptor(
            artifactDigest: artifact.artifactDigest,
            provenanceDigest: artifact.provenanceDigest,
            classification: artifact.classification,
          ),
        _ => null,
      },
  };

  Future<void> _finish(
    _RunExecution execution, {
    required ScenarioLabRunState state,
    required ScenarioLabTerminalCause cause,
  }) async {
    if (_current(execution).state.isTerminal) return;
    final session = execution.session;
    if (session == null && execution.targetEffectsStarted) {
      execution.targetAbortRequired = true;
      unawaited(_startTargetAbort(execution));
    }
    var cleanup = ScenarioLabCleanupResult(
      state: ScenarioLabCleanupState.notRequired,
    );
    final resetIds = <ScenarioControlId>[];
    var cleanupFailed = false;
    var cleanupPerformed = false;
    final cleanupWillRun =
        execution.targetAbortRequired ||
        execution.evidenceCleanupRequired ||
        (session != null && execution.dirtyControls.isNotEmpty);
    if (cleanupWillRun) {
      _append(
        execution,
        state: _current(execution).state == ScenarioLabRunState.cancelling
            ? ScenarioLabRunState.cancelling
            : ScenarioLabRunState.running,
        cleanup: ScenarioLabCleanupResult(
          state: ScenarioLabCleanupState.running,
        ),
      );
    }
    if (session != null && execution.dirtyControls.isNotEmpty) {
      for (final controlId in execution.dirtyControls.toList(growable: false)) {
        cleanupPerformed = true;
        try {
          final control = execution.control(controlId);
          final value = await _sendReset(
            execution,
            control,
            (action) => deadlines.run<AppAdapterRelayResult>(
              timeout: cleanupTimeout,
              action: action,
            ),
            const _NeverCancellationSignal(),
          );
          execution.controlResults[control.id] = ScenarioControlResult(
            controlId: control.id,
            source: ScenarioControlResultSource.reset,
            value: value,
          );
          resetIds.add(control.id);
          execution.dirtyControls.remove(control.id);
        } on Object {
          cleanupFailed = true;
          break;
        }
      }
    }
    if (execution.evidenceCleanupRequired) {
      cleanupPerformed = true;
      try {
        await deadlines.run<void>(
          timeout: cleanupTimeout,
          action: () => evidence!.cleanupRun(execution.runId),
        );
        execution.evidenceCleanupRequired = false;
      } on Object {
        cleanupFailed = true;
      }
    }
    if (session != null) {
      try {
        await deadlines.run<void>(
          timeout: cleanupTimeout,
          action: session.close,
        );
      } on Object {
        cleanupFailed = true;
      }
      execution.session = null;
    }
    if (execution.targetAbortRequired) {
      cleanupPerformed = true;
      try {
        final failure = await deadlines.run<_TargetAbortFailure?>(
          timeout: cleanupTimeout,
          action: () => _startTargetAbort(execution),
        );
        if (failure != null) cleanupFailed = true;
      } on Object {
        cleanupFailed = true;
      }
    }
    if (cleanupFailed) {
      cleanup = ScenarioLabCleanupResult(
        state: ScenarioLabCleanupState.failed,
        resetControlIds: resetIds,
        failure: const ScenarioLabFailure(
          cause: ScenarioLabFailureCause.internalError,
        ),
      );
      state = ScenarioLabRunState.failed;
      cause = ScenarioLabTerminalCause.cleanupFailed;
    } else if (cleanupPerformed) {
      cleanup = ScenarioLabCleanupResult(
        state: ScenarioLabCleanupState.succeeded,
        resetControlIds: resetIds,
      );
    }
    if (!cleanupFailed &&
        execution.cancelRequested &&
        state == ScenarioLabRunState.succeeded) {
      // Cancellation may race an awaited reset, Evidence cleanup, session
      // close, or target abort after cleanup.running was persisted. The
      // journal is already in cancelling at that point, so cancellation wins
      // over an uncommitted local success. A failure determined before cleanup
      // remains authoritative, as does cleanupFailed.
      state = ScenarioLabRunState.cancelled;
      cause = _cancellationCause(execution);
    }
    final finalSnapshot = _append(
      execution,
      state: state,
      cleanup: cleanup,
      terminalCause: cause,
    );
    final result = ScenarioLabRunResult(
      finalSnapshot: finalSnapshot,
      startedAt: execution.startedAt!,
      completedAt: finalSnapshot.observedAt,
      verificationState: deriveVerificationState(
        finalSnapshot.automatedAcceptance.map(
          (acceptance) => acceptance.verificationState,
        ),
      ),
    );
    store.complete(result);
    if (!execution.completion.isCompleted) {
      execution.completion.complete(result);
    }
    _active.remove(execution.runId.value);
  }

  void _beginStep(
    _RunExecution execution,
    int index, {
    required ScenarioLabRunState runState,
  }) {
    final current = _current(execution);
    final steps = List<ScenarioLabStepSnapshot>.of(current.steps);
    final startedAt = _now(execution);
    steps[index] = ScenarioLabStepSnapshot(
      stepId: steps[index].stepId,
      state: ScenarioLabStepState.running,
      startedAt: startedAt,
    );
    execution
      ..activeStepIndex = index
      ..activeStepStartedMonotonicMicros = clock.monotonicMicroseconds();
    _append(execution, state: runState, steps: steps);
  }

  void _succeedStep(_RunExecution execution, int index) {
    final current = _current(execution);
    final steps = List<ScenarioLabStepSnapshot>.of(current.steps);
    final previous = steps[index];
    steps[index] = ScenarioLabStepSnapshot(
      stepId: previous.stepId,
      state: ScenarioLabStepState.succeeded,
      startedAt: previous.startedAt,
      completedAt: _now(execution),
      terminalCause: ScenarioLabStepTerminalCause.completed,
    );
    _append(
      execution,
      state: current.state == ScenarioLabRunState.cancelling
          ? ScenarioLabRunState.cancelling
          : ScenarioLabRunState.running,
      steps: steps,
    );
    execution.activeStepIndex = null;
  }

  void _prepareTerminalSteps(
    _RunExecution execution, {
    required ScenarioLabStepState state,
    required ScenarioLabStepTerminalCause cause,
  }) {
    final current = _current(execution);
    if (current.steps.every((step) => step.state.isTerminal)) return;
    final steps = _terminalizeSteps(
      current.steps,
      activeIndex: execution.activeStepIndex,
      activeState: state,
      activeCause: cause,
      completedAt: _now(execution),
    );
    _append(
      execution,
      state: current.state == ScenarioLabRunState.cancelling
          ? ScenarioLabRunState.cancelling
          : ScenarioLabRunState.running,
      steps: steps,
    );
    execution.activeStepIndex = null;
  }

  ScenarioLabRunSnapshot _append(
    _RunExecution execution, {
    required ScenarioLabRunState state,
    List<ScenarioLabStepSnapshot>? steps,
    ScenarioLabCleanupResult? cleanup,
    ScenarioLabTerminalCause? terminalCause,
  }) {
    final current = _current(execution);
    final next = ScenarioLabRunSnapshot(
      runId: current.runId,
      startRequestDigest: current.startRequestDigest,
      contentSetDigest: current.contentSetDigest,
      catalogDigest: current.catalogDigest,
      scenarioLabManifestDigest: current.scenarioLabManifestDigest,
      scenarioId: current.scenarioId,
      scriptId: current.scriptId,
      sequence: current.sequence + 1,
      observedAt: _now(execution),
      state: state,
      runtimeInputs: execution.runtimeInputs,
      steps: steps ?? current.steps,
      controls: execution.controlResults.values,
      requiredEvidence: execution.evidenceResults.values,
      automatedAcceptance: execution.acceptanceResults.values,
      comparisons: execution.comparisonResults.values,
      cleanup: cleanup ?? current.cleanup,
      terminalCause: terminalCause,
    );
    store.append(next);
    return next;
  }

  Future<T> _withinStep<T>(
    _RunExecution execution,
    int stepIndex,
    Future<T> Function() action,
  ) async {
    final step = execution.script.steps[stepIndex];
    final now = clock.monotonicMicroseconds();
    final scriptRemaining =
        execution.script.timeoutMs * 1000 -
        (now - execution.startedMonotonicMicros);
    final stepRemaining =
        step.timeoutMs * 1000 -
        (now - execution.activeStepStartedMonotonicMicros);
    final scriptWins = scriptRemaining <= stepRemaining;
    final remaining = scriptWins ? scriptRemaining : stepRemaining;
    if (remaining <= 0) {
      throw _ExecutionTimedOut(
        scriptWins ? execution.script.timeoutOutcome : step.timeoutOutcome,
      );
    }
    try {
      return await deadlines.run<T>(
        timeout: Duration(microseconds: remaining),
        action: action,
      );
    } on ScenarioLabDeadlineExceeded {
      throw _ExecutionTimedOut(
        scriptWins ? execution.script.timeoutOutcome : step.timeoutOutcome,
      );
    }
  }

  Future<T> _withinScript<T>(
    _RunExecution execution,
    Future<T> Function() action,
  ) async {
    final remaining =
        execution.script.timeoutMs * 1000 -
        (clock.monotonicMicroseconds() - execution.startedMonotonicMicros);
    if (remaining <= 0) {
      throw _ExecutionTimedOut(execution.script.timeoutOutcome);
    }
    try {
      return await deadlines.run<T>(
        timeout: Duration(microseconds: remaining),
        action: action,
      );
    } on ScenarioLabDeadlineExceeded {
      throw _ExecutionTimedOut(execution.script.timeoutOutcome);
    }
  }

  ScenarioLabCommandId _nextCommandId(_RunExecution execution) {
    final id = identities.nextCommandId();
    if (!execution.commandIds.add(id.value)) {
      throw StateError('Scenario Lab command IDs must be unique per run');
    }
    return id;
  }

  int _nextCommandSequence(_RunExecution execution) {
    if (execution.commandSequence >= 9007199254740991) {
      throw StateError('Scenario Lab command sequence exhausted');
    }
    execution.commandSequence += 1;
    return execution.commandSequence;
  }

  void _validateHello(_RunExecution execution, AppAdapterRelayHello hello) {
    if (hello.runId != execution.runId ||
        hello.nonce != execution.nonce ||
        hello.sequence != 0) {
      throw const _StepExecutionFailed();
    }
  }

  void _throwIfImmediateCancellation(_RunExecution execution) {
    if (execution.cancelRequested &&
        execution.script.cancellationPolicy ==
            ScenarioScriptCancellationPolicy.immediate) {
      throw const _RequestedCancellation();
    }
  }

  void _throwIfCancellation(_RunExecution execution) {
    if (execution.cancelRequested) throw const _RequestedCancellation();
  }

  ScenarioLabTerminalCause _cancellationCause(_RunExecution execution) =>
      execution.cancellationCause ?? ScenarioLabTerminalCause.cancelledByUser;

  ScenarioLabRunSnapshot _current(_RunExecution execution) =>
      store.requireRun(execution.runId).latest;

  DateTime _now(_RunExecution execution) {
    final now = clock.nowUtc();
    final previous = store.requireRun(execution.runId).latest.observedAt;
    return now.isBefore(previous) ? previous : now;
  }
}

void _validateSupportedPlan(
  ScenarioLabExecutionPlan plan,
  ScenarioLabManifest manifest,
  ScenarioLabEvidencePort? evidence,
) {
  final unsupported = <String>[];
  final evidenceRequired =
      plan.plan.requiredEvidenceIds.isNotEmpty ||
      plan.steps.whereType<PlannedScenarioLabOperationStep>().any(
        (step) => step.operation is CollectEvidenceOperationDefinition,
      );
  if (evidenceRequired && evidence == null) {
    unsupported.add('Evidence capture requires Host-owned receipts and CAS');
  }
  final supportedProvider = ModuleId('capture.app-adapter');
  for (final id in plan.plan.requiredEvidenceIds) {
    final requirement = manifest.requiredEvidence.singleWhere(
      (item) => item.id == id,
    );
    if (requirement.providerId != supportedProvider) {
      unsupported.add(
        'Evidence provider ${requirement.providerId} is unsupported',
      );
    }
  }
  if (plan.plan.comparisonBindingIds.isNotEmpty && evidence == null) {
    unsupported.add('comparison requires Host-owned artifact bytes');
  }
  for (final criterionId in plan.plan.automatedAcceptanceCriterionIds) {
    final criterion = manifest.automatedAcceptanceCriteria.singleWhere(
      (item) => item.id == criterionId,
    );
    if (criterion is EvidenceAcceptedAcceptanceCriterion && evidence == null) {
      unsupported.add('Evidence acceptance requires Host-owned receipts');
    }
  }
  for (final step in plan.steps.whereType<PlannedScenarioLabOperationStep>()) {
    final operation = step.operation;
    if (operation is AssignControlOperationDefinition) {
      final control = manifest.controls.singleWhere(
        (item) => item.id == operation.controlId,
      );
      if (control.resetOperationId == null) {
        unsupported.add('write control without a reset operation');
      }
    }
  }
  if (unsupported.isNotEmpty) {
    throw ScenarioLabUnsupportedExecutionPlan(unsupported);
  }
}

RequiredEvidenceRunResult _pendingEvidence(
  RequiredEvidenceDefinition requirement,
) => RequiredEvidenceRunResult(
  requiredEvidenceId: requirement.id,
  providerId: requirement.providerId,
  fidelity: requirement.fidelity,
  variantId: requirement.variantId,
  freshness: EvidenceFreshness.missing,
  state: RequiredEvidenceResultState.pending,
);

final class _RunExecution {
  _RunExecution({
    required this.request,
    required this.manifest,
    required this.executionPlan,
    required this.runId,
    required this.nonce,
    required this.runtimeInputs,
    required this.evidenceResults,
    required this.acceptanceResults,
  }) {
    // The Host normally observes runs through snapshots, not waitForResult.
    // Keep an internal error sink attached before execution starts so a
    // fail-closed persistence error cannot escape as an uncaught Zone error.
    // Future results remain multicast, so explicit waiters still receive the
    // original value or error.
    unawaited(
      completion.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  final ScenarioLabRunStartRequest request;
  final ScenarioLabManifest manifest;
  final ScenarioLabExecutionPlan executionPlan;
  final ScenarioLabRunId runId;
  final AppAdapterRelayNonce nonce;
  final ScenarioLabRuntimeInputBinding runtimeInputs;
  final Map<RequiredEvidenceId, RequiredEvidenceRunResult> evidenceResults;
  final Map<AutomatedAcceptanceCriterionId, AutomatedAcceptanceResult>
  acceptanceResults;
  final Map<ScenarioControlId, ScenarioControlResult> controlResults =
      <ScenarioControlId, ScenarioControlResult>{};
  final Set<ScenarioControlId> dirtyControls = <ScenarioControlId>{};
  final Set<String> commandIds = <String>{};
  final Set<String> captureRequestIds = <String>{};
  final Map<ScenarioComparisonBindingId, ScenarioComparisonResult>
  comparisonResults = <ScenarioComparisonBindingId, ScenarioComparisonResult>{};
  final _CancellationController cancellation = _CancellationController();
  final Completer<ScenarioLabRunResult> completion =
      Completer<ScenarioLabRunResult>();

  ScenarioLabTargetSession? session;
  Future<_TargetAbortFailure?>? targetAbort;
  DateTime? startedAt;
  var startedMonotonicMicros = 0;
  var activeStepStartedMonotonicMicros = 0;
  int? activeStepIndex;
  var commandSequence = 0;
  var cancelRequested = false;
  ScenarioLabTerminalCause? cancellationCause;
  var evidenceCleanupRequired = false;
  var targetEffectsStarted = false;
  var targetAbortRequired = false;

  ScenarioLabPlan get plan => executionPlan.plan;

  ScenarioScriptDefinition get script => executionPlan.script;

  ScenarioExecutionBinding get binding => executionPlan.initialBinding;

  ScenarioControlDefinition control(ScenarioControlId id) =>
      manifest.controls.singleWhere((item) => item.id == id);

  RequiredEvidenceDefinition requirement(RequiredEvidenceId id) =>
      manifest.requiredEvidence.singleWhere((item) => item.id == id);

  ScenarioLabTargetSession requireSession() =>
      session ?? (throw StateError('Scenario Lab target is not attached'));
}

final class _CancellationController implements ScenarioLabCancellationSignal {
  final Completer<void> _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

final class _NeverCancellationSignal implements ScenarioLabCancellationSignal {
  const _NeverCancellationSignal();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;
}

final class _ExecutionTimedOut implements Exception {
  const _ExecutionTimedOut(this.outcome);

  final ScenarioScriptTimeoutOutcome outcome;
}

final class _TargetAbortFailure {
  const _TargetAbortFailure();
}

final class _RequestedCancellation implements Exception {
  const _RequestedCancellation();
}

final class _StepExecutionFailed implements Exception {
  const _StepExecutionFailed();
}

final class _CleanupFailed implements Exception {
  const _CleanupFailed();
}

List<ScenarioLabStepSnapshot> _terminalizeSteps(
  List<ScenarioLabStepSnapshot> source, {
  required int? activeIndex,
  required ScenarioLabStepState activeState,
  required ScenarioLabStepTerminalCause activeCause,
  required DateTime completedAt,
}) => <ScenarioLabStepSnapshot>[
  for (final (index, step) in source.indexed)
    if (step.state.isTerminal)
      step
    else if (index == activeIndex ||
        (activeIndex == null && step.state == ScenarioLabStepState.running))
      ScenarioLabStepSnapshot(
        stepId: step.stepId,
        state: activeState,
        startedAt: step.startedAt,
        completedAt: completedAt,
        terminalCause: activeCause,
      )
    else
      ScenarioLabStepSnapshot(
        stepId: step.stepId,
        state: ScenarioLabStepState.skipped,
        completedAt: completedAt,
        terminalCause: ScenarioLabStepTerminalCause.skippedDependency,
      ),
];

bool _sameControlValue(
  ScenarioControlValue? left,
  ScenarioControlValue? right,
) =>
    left != null &&
    right != null &&
    Digest.semantic(left.toJson()) == Digest.semantic(right.toJson());
