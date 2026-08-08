import 'package:experience_contracts/experience_contracts.dart';

/// Raised when one idempotency key is reused for a different start intent.
final class ScenarioLabRequestConflict implements Exception {
  const ScenarioLabRequestConflict(this.requestId);

  final ScenarioLabRunRequestId requestId;

  @override
  String toString() =>
      'ScenarioLabRequestConflict: ${requestId.value} has another digest';
}

/// Raised when a Scenario Lab run is absent from the Host-owned store.
final class ScenarioLabRunNotFound implements Exception {
  const ScenarioLabRunNotFound(this.runId);

  final ScenarioLabRunId runId;

  @override
  String toString() => 'ScenarioLabRunNotFound: ${runId.value}';
}

/// Immutable view of one stored run and all of its monotonic observations.
final class ScenarioLabStoredRun {
  ScenarioLabStoredRun({
    required this.request,
    required Iterable<ScenarioLabRunSnapshot> snapshots,
    required this.result,
    required this.interrupted,
  }) : snapshots = List<ScenarioLabRunSnapshot>.unmodifiable(snapshots) {
    if (this.snapshots.isEmpty ||
        (result != null && interrupted) ||
        (interrupted && this.snapshots.last.state.isTerminal) ||
        (result != null &&
            (!this.snapshots.last.state.isTerminal ||
                result!.finalSnapshot.digest != this.snapshots.last.digest))) {
      throw ArgumentError('Scenario Lab stored run state is invalid');
    }
  }

  final ScenarioLabRunStartRequest request;
  final List<ScenarioLabRunSnapshot> snapshots;
  final ScenarioLabRunResult? result;
  final bool interrupted;

  ScenarioLabRunSnapshot get latest => snapshots.last;

  /// Whether the journal has a terminal snapshot whose exact result did not
  /// commit.
  ///
  /// Such a snapshot is not a successful terminal commit and must never be
  /// exposed as resumable. Durable stores recover it to an interruption on the
  /// next ownership boundary; live readers fail closed in the meantime.
  bool get hasUncommittedTerminalSnapshot =>
      result == null && !interrupted && latest.state.isTerminal;

  /// Latest observation that has not been left as an uncommitted terminal
  /// preparation.
  ///
  /// A terminal snapshot only becomes publicly observable as terminal with
  /// its exact result. Until then readers preserve the preceding journal
  /// truth and fail closed as interrupted.
  ScenarioLabRunSnapshot get latestObservable {
    if (!hasUncommittedTerminalSnapshot) return latest;
    if (snapshots.length < 2) {
      throw StateError(
        'Scenario Lab terminal preparation has no prior observation',
      );
    }
    return snapshots[snapshots.length - 2];
  }

  bool get isClosed =>
      result != null || interrupted || hasUncommittedTerminalSnapshot;
}

/// Result of atomically reserving an idempotent start request.
final class ScenarioLabRunRegistration {
  const ScenarioLabRunRegistration({required this.created, required this.run});

  final bool created;
  final ScenarioLabStoredRun run;
}

/// Storage boundary for immutable Scenario Lab run history.
abstract interface class ScenarioLabRunStore {
  int get length;

  ScenarioLabRunRegistration register({
    required ScenarioLabRunStartRequest request,
    required ScenarioLabRunSnapshot initialSnapshot,
  });

  ScenarioLabStoredRun? findByRequestId(ScenarioLabRunRequestId requestId);

  ScenarioLabStoredRun? findByRunId(ScenarioLabRunId runId);

  ScenarioLabStoredRun requireRun(ScenarioLabRunId runId);

  List<ScenarioLabStoredRun> get runs;

  void append(ScenarioLabRunSnapshot snapshot);

  void complete(ScenarioLabRunResult result);

  /// Closes an ownerless generation without fabricating a v1 terminal cause.
  ///
  /// An uncommitted terminal preparation is rolled back to its preceding
  /// non-terminal observation before interruption. Returns whether a new
  /// interruption tombstone was created.
  bool interrupt(ScenarioLabRunId runId);

  List<ScenarioLabRunSnapshot> observationsAfter(
    ScenarioLabRunId runId,
    int sequence,
  );
}

/// Host-owned volatile store for immutable Scenario Lab run observations.
///
/// This store deliberately makes no durability claim. Reusing the same object
/// across service instances supports observer reattachment in one process, but
/// constructing a new store after a process restart starts with no runs.
final class InMemoryScenarioLabRunStore implements ScenarioLabRunStore {
  final Map<String, _MutableStoredRun> _byRequestId =
      <String, _MutableStoredRun>{};
  final Map<String, _MutableStoredRun> _byRunId = <String, _MutableStoredRun>{};

  @override
  int get length => _byRunId.length;

  @override
  ScenarioLabRunRegistration register({
    required ScenarioLabRunStartRequest request,
    required ScenarioLabRunSnapshot initialSnapshot,
  }) {
    final existing = _byRequestId[request.requestId.value];
    if (existing != null) {
      if (existing.request.digest != request.digest) {
        throw ScenarioLabRequestConflict(request.requestId);
      }
      return ScenarioLabRunRegistration(created: false, run: existing.view());
    }
    if (_byRunId.containsKey(initialSnapshot.runId.value)) {
      throw StateError('Scenario Lab Run ID is already registered');
    }
    initialSnapshot.validateAgainstStart(request);
    if (initialSnapshot.sequence != 0 ||
        initialSnapshot.state != ScenarioLabRunState.queued ||
        initialSnapshot.state.isTerminal) {
      throw ArgumentError(
        'Initial Scenario Lab snapshot must be queued at sequence zero',
      );
    }
    _validateInitialSnapshot(initialSnapshot);
    final stored = _MutableStoredRun(
      request: request,
      snapshots: <ScenarioLabRunSnapshot>[initialSnapshot],
    );
    _byRequestId[request.requestId.value] = stored;
    _byRunId[initialSnapshot.runId.value] = stored;
    return ScenarioLabRunRegistration(created: true, run: stored.view());
  }

  @override
  ScenarioLabStoredRun? findByRequestId(ScenarioLabRunRequestId requestId) =>
      _byRequestId[requestId.value]?.view();

  @override
  ScenarioLabStoredRun? findByRunId(ScenarioLabRunId runId) =>
      _byRunId[runId.value]?.view();

  @override
  ScenarioLabStoredRun requireRun(ScenarioLabRunId runId) {
    final stored = _byRunId[runId.value];
    if (stored == null) throw ScenarioLabRunNotFound(runId);
    return stored.view();
  }

  @override
  List<ScenarioLabStoredRun> get runs =>
      List<ScenarioLabStoredRun>.unmodifiable(
        _byRunId.values.map((stored) => stored.view()),
      );

  @override
  void append(ScenarioLabRunSnapshot snapshot) {
    final stored = _byRunId[snapshot.runId.value];
    if (stored == null) throw ScenarioLabRunNotFound(snapshot.runId);
    final previous = stored.snapshots.last;
    if (stored.interrupted) {
      throw StateError('Interrupted Scenario Lab run is immutable');
    }
    if (previous.state.isTerminal) {
      throw StateError('Terminal Scenario Lab snapshot is immutable');
    }
    snapshot.validateAgainstStart(stored.request);
    if (!_sameRunBinding(previous, snapshot)) {
      throw ArgumentError(
        'Scenario Lab snapshot changed immutable run binding',
      );
    }
    if (snapshot.sequence != previous.sequence + 1) {
      throw ArgumentError(
        'Scenario Lab snapshot sequence must increase by one',
      );
    }
    if (snapshot.observedAt.isBefore(previous.observedAt)) {
      throw ArgumentError('Scenario Lab observation time must be monotonic');
    }
    if (!_runTransitionAllowed(previous.state, snapshot.state)) {
      throw StateError(
        'Invalid Scenario Lab run transition '
        '${previous.state.name} -> ${snapshot.state.name}',
      );
    }
    _validateStepHistory(previous.steps, snapshot.steps);
    _validateControlHistory(previous.controls, snapshot.controls);
    _validateRequiredEvidenceHistory(
      previous.requiredEvidence,
      snapshot.requiredEvidence,
    );
    _validateAutomatedAcceptanceHistory(
      previous.automatedAcceptance,
      snapshot.automatedAcceptance,
    );
    _validateComparisonHistory(previous.comparisons, snapshot.comparisons);
    _validateCleanupHistory(
      previous.cleanup,
      snapshot.cleanup,
      snapshot.controls,
    );
    _validateSnapshotClosure(snapshot);
    stored.snapshots.add(snapshot);
  }

  @override
  void complete(ScenarioLabRunResult result) {
    final stored = _byRunId[result.finalSnapshot.runId.value];
    if (stored == null) {
      throw ScenarioLabRunNotFound(result.finalSnapshot.runId);
    }
    if (stored.interrupted) {
      throw StateError('Interrupted Scenario Lab run cannot complete');
    }
    final current = stored.snapshots.last;
    if (!current.state.isTerminal ||
        current.digest != result.finalSnapshot.digest) {
      throw ArgumentError(
        'Scenario Lab result does not close the latest snapshot',
      );
    }
    _validateSnapshotClosure(current);
    if (result.verificationState !=
        deriveVerificationState(
          current.automatedAcceptance.map(
            (acceptance) => acceptance.verificationState,
          ),
        )) {
      throw ArgumentError(
        'Scenario Lab result verification does not match acceptance',
      );
    }
    final previous = stored.result;
    if (previous != null && previous.digest != result.digest) {
      throw StateError('Terminal Scenario Lab result is immutable');
    }
    stored.result = result;
  }

  @override
  bool interrupt(ScenarioLabRunId runId) {
    final stored = _byRunId[runId.value];
    if (stored == null) throw ScenarioLabRunNotFound(runId);
    if (stored.result != null || stored.interrupted) return false;
    if (stored.snapshots.last.state.isTerminal) {
      if (stored.snapshots.length < 2 ||
          stored.snapshots[stored.snapshots.length - 2].state.isTerminal) {
        throw StateError(
          'Scenario Lab terminal preparation has no recoverable predecessor',
        );
      }
      stored.snapshots.removeLast();
    }
    stored.interrupted = true;
    return true;
  }

  @override
  List<ScenarioLabRunSnapshot> observationsAfter(
    ScenarioLabRunId runId,
    int sequence,
  ) {
    if (sequence < -1 || sequence > 9007199254740991) {
      throw ArgumentError.value(sequence, 'sequence', 'must be JSON-safe');
    }
    final stored = _byRunId[runId.value];
    if (stored == null) throw ScenarioLabRunNotFound(runId);
    return List<ScenarioLabRunSnapshot>.unmodifiable(
      stored.snapshots.where((snapshot) => snapshot.sequence > sequence),
    );
  }
}

final class _MutableStoredRun {
  _MutableStoredRun({required this.request, required this.snapshots});

  final ScenarioLabRunStartRequest request;
  final List<ScenarioLabRunSnapshot> snapshots;
  ScenarioLabRunResult? result;
  var interrupted = false;

  ScenarioLabStoredRun view() => ScenarioLabStoredRun(
    request: request,
    snapshots: snapshots,
    result: result,
    interrupted: interrupted,
  );
}

bool _sameRunBinding(
  ScenarioLabRunSnapshot previous,
  ScenarioLabRunSnapshot next,
) =>
    previous.runId == next.runId &&
    previous.startRequestDigest == next.startRequestDigest &&
    previous.contentSetDigest == next.contentSetDigest &&
    previous.catalogDigest == next.catalogDigest &&
    previous.scenarioLabManifestDigest == next.scenarioLabManifestDigest &&
    previous.scenarioId == next.scenarioId &&
    previous.scriptId == next.scriptId &&
    (previous.runtimeInputs == null ||
        previous.runtimeInputs!.digest == next.runtimeInputs?.digest);

void _validateInitialSnapshot(ScenarioLabRunSnapshot snapshot) {
  if (snapshot.steps.any(
        (step) => step.state != ScenarioLabStepState.pending,
      ) ||
      snapshot.controls.isNotEmpty ||
      snapshot.requiredEvidence.any(
        (evidence) => evidence.state != RequiredEvidenceResultState.pending,
      ) ||
      snapshot.automatedAcceptance.any(
        (acceptance) =>
            acceptance.verificationState != VerificationState.notRun,
      ) ||
      snapshot.comparisons.isNotEmpty ||
      snapshot.cleanup.state != ScenarioLabCleanupState.pending ||
      snapshot.cleanup.resetControlIds.isNotEmpty) {
    throw ArgumentError(
      'Initial Scenario Lab snapshot must contain only neutral pending state',
    );
  }
}

bool _runTransitionAllowed(
  ScenarioLabRunState previous,
  ScenarioLabRunState next,
) => switch (previous) {
  ScenarioLabRunState.queued => const <ScenarioLabRunState>{
    ScenarioLabRunState.starting,
    ScenarioLabRunState.cancelling,
    ScenarioLabRunState.failed,
    ScenarioLabRunState.cancelled,
  }.contains(next),
  ScenarioLabRunState.starting => const <ScenarioLabRunState>{
    ScenarioLabRunState.running,
    ScenarioLabRunState.cancelling,
    ScenarioLabRunState.failed,
    ScenarioLabRunState.cancelled,
  }.contains(next),
  ScenarioLabRunState.running => const <ScenarioLabRunState>{
    ScenarioLabRunState.running,
    ScenarioLabRunState.cancelling,
    ScenarioLabRunState.succeeded,
    ScenarioLabRunState.failed,
    ScenarioLabRunState.cancelled,
  }.contains(next),
  ScenarioLabRunState.cancelling => const <ScenarioLabRunState>{
    ScenarioLabRunState.cancelling,
    ScenarioLabRunState.cancelled,
    ScenarioLabRunState.failed,
  }.contains(next),
  ScenarioLabRunState.succeeded ||
  ScenarioLabRunState.failed ||
  ScenarioLabRunState.cancelled => false,
};

void _validateStepHistory(
  List<ScenarioLabStepSnapshot> previous,
  List<ScenarioLabStepSnapshot> next,
) {
  if (previous.length != next.length) {
    throw ArgumentError('Scenario Lab step set cannot change during a run');
  }
  for (var index = 0; index < previous.length; index += 1) {
    final before = previous[index];
    final after = next[index];
    if (before.stepId != after.stepId ||
        (before.startedAt != null && before.startedAt != after.startedAt) ||
        (before.completedAt != null &&
            before.completedAt != after.completedAt)) {
      throw ArgumentError('Scenario Lab step history cannot be rewritten');
    }
    final allowed = switch (before.state) {
      ScenarioLabStepState.pending => const <ScenarioLabStepState>{
        ScenarioLabStepState.pending,
        ScenarioLabStepState.running,
        ScenarioLabStepState.cancelled,
        ScenarioLabStepState.skipped,
      },
      ScenarioLabStepState.running => const <ScenarioLabStepState>{
        ScenarioLabStepState.running,
        ScenarioLabStepState.succeeded,
        ScenarioLabStepState.failed,
        ScenarioLabStepState.cancelled,
      },
      ScenarioLabStepState.succeeded => const <ScenarioLabStepState>{
        ScenarioLabStepState.succeeded,
      },
      ScenarioLabStepState.failed => const <ScenarioLabStepState>{
        ScenarioLabStepState.failed,
      },
      ScenarioLabStepState.cancelled => const <ScenarioLabStepState>{
        ScenarioLabStepState.cancelled,
      },
      ScenarioLabStepState.skipped => const <ScenarioLabStepState>{
        ScenarioLabStepState.skipped,
      },
    };
    if (!allowed.contains(after.state)) {
      throw StateError(
        'Invalid Scenario Lab step transition '
        '${before.state.name} -> ${after.state.name}',
      );
    }
    if (before.state.isTerminal &&
        Digest.semantic(before.toJson()) != Digest.semantic(after.toJson())) {
      throw StateError('Terminal Scenario Lab step is immutable');
    }
  }
}

void _validateControlHistory(
  List<ScenarioControlResult> previous,
  List<ScenarioControlResult> next,
) {
  final nextById = <ScenarioControlId, ScenarioControlResult>{
    for (final result in next) result.controlId: result,
  };
  for (final before in previous) {
    final after = nextById[before.controlId];
    if (after == null) {
      throw ArgumentError('Published Scenario Lab control cannot be removed');
    }
    if (before.source == ScenarioControlResultSource.reset &&
        Digest.semantic(before.toJson()) != Digest.semantic(after.toJson())) {
      throw StateError('Reset Scenario Lab control is immutable');
    }
  }
}

void _validateRequiredEvidenceHistory(
  List<RequiredEvidenceRunResult> previous,
  List<RequiredEvidenceRunResult> next,
) {
  if (previous.length != next.length) {
    throw ArgumentError(
      'Scenario Lab RequiredEvidence set cannot change during a run',
    );
  }
  for (var index = 0; index < previous.length; index += 1) {
    final before = previous[index];
    final after = next[index];
    if (before.requiredEvidenceId != after.requiredEvidenceId) {
      throw ArgumentError(
        'Scenario Lab RequiredEvidence set cannot change during a run',
      );
    }
    if (before.providerId != after.providerId ||
        before.fidelity != after.fidelity ||
        before.variantId != after.variantId) {
      throw ArgumentError(
        'Scenario Lab RequiredEvidence changed immutable binding',
      );
    }
    if (before.state == RequiredEvidenceResultState.pending) {
      if (after.state == RequiredEvidenceResultState.pending &&
          before.digest != after.digest) {
        throw ArgumentError(
          'Pending Scenario Lab RequiredEvidence cannot be rewritten',
        );
      }
      continue;
    }
    if (before.digest != after.digest) {
      throw StateError(
        'Published Scenario Lab RequiredEvidence result is immutable',
      );
    }
  }
}

void _validateAutomatedAcceptanceHistory(
  List<AutomatedAcceptanceResult> previous,
  List<AutomatedAcceptanceResult> next,
) {
  if (previous.length != next.length) {
    throw ArgumentError(
      'Scenario Lab automated acceptance set cannot change during a run',
    );
  }
  for (var index = 0; index < previous.length; index += 1) {
    final before = previous[index];
    final after = next[index];
    if (before.criterionId != after.criterionId) {
      throw ArgumentError(
        'Scenario Lab automated acceptance set cannot change during a run',
      );
    }
    if (before.verificationState == VerificationState.notRun) {
      if (after.verificationState == VerificationState.notRun &&
          Digest.semantic(before.toJson()) != Digest.semantic(after.toJson())) {
        throw ArgumentError(
          'Pending automated acceptance result cannot be rewritten',
        );
      }
      continue;
    }
    if (Digest.semantic(before.toJson()) != Digest.semantic(after.toJson())) {
      throw StateError('Published automated acceptance result is immutable');
    }
  }
}

void _validateCleanupHistory(
  ScenarioLabCleanupResult previous,
  ScenarioLabCleanupResult next,
  List<ScenarioControlResult> controls,
) {
  final allowed = switch (previous.state) {
    ScenarioLabCleanupState.pending => const <ScenarioLabCleanupState>{
      ScenarioLabCleanupState.pending,
      ScenarioLabCleanupState.running,
      ScenarioLabCleanupState.notRequired,
    },
    ScenarioLabCleanupState.running => const <ScenarioLabCleanupState>{
      ScenarioLabCleanupState.running,
      ScenarioLabCleanupState.succeeded,
      ScenarioLabCleanupState.failed,
    },
    ScenarioLabCleanupState.succeeded ||
    ScenarioLabCleanupState.failed ||
    ScenarioLabCleanupState.notRequired => <ScenarioLabCleanupState>{
      previous.state,
    },
  };
  if (!allowed.contains(next.state)) {
    throw StateError(
      'Invalid Scenario Lab cleanup transition '
      '${previous.state.name} -> ${next.state.name}',
    );
  }
  final previousResetIds = previous.resetControlIds.toSet();
  final nextResetIds = next.resetControlIds.toSet();
  if (!nextResetIds.containsAll(previousResetIds)) {
    throw StateError('Scenario Lab cleanup reset history cannot regress');
  }
  final resetControls = <ScenarioControlId>{
    for (final control in controls)
      if (control.source == ScenarioControlResultSource.reset)
        control.controlId,
  };
  final cleanupIsTerminal = const <ScenarioLabCleanupState>{
    ScenarioLabCleanupState.succeeded,
    ScenarioLabCleanupState.failed,
    ScenarioLabCleanupState.notRequired,
  }.contains(next.state);
  if (!resetControls.containsAll(nextResetIds) ||
      (cleanupIsTerminal && resetControls.length != nextResetIds.length)) {
    throw ArgumentError(
      'Scenario Lab cleanup reset IDs must match reset control results',
    );
  }
  final previousJson = Digest.semantic(previous.toJson());
  final nextJson = Digest.semantic(next.toJson());
  if ((previous.state == ScenarioLabCleanupState.pending &&
          next.state == ScenarioLabCleanupState.pending &&
          previousJson != nextJson) ||
      (const <ScenarioLabCleanupState>{
            ScenarioLabCleanupState.succeeded,
            ScenarioLabCleanupState.failed,
            ScenarioLabCleanupState.notRequired,
          }.contains(previous.state) &&
          previousJson != nextJson)) {
    throw StateError('Published Scenario Lab cleanup result is immutable');
  }
}

void _validateSnapshotClosure(ScenarioLabRunSnapshot snapshot) {
  final cleanupIsTerminal = const <ScenarioLabCleanupState>{
    ScenarioLabCleanupState.succeeded,
    ScenarioLabCleanupState.failed,
    ScenarioLabCleanupState.notRequired,
  }.contains(snapshot.cleanup.state);
  if (snapshot.state.isTerminal != cleanupIsTerminal) {
    throw ArgumentError('Scenario Lab run and cleanup terminality must agree');
  }
  if (!snapshot.state.isTerminal) return;
  if (snapshot.requiredEvidence.any(
    (evidence) => evidence.state == RequiredEvidenceResultState.pending,
  )) {
    throw ArgumentError('Terminal Scenario Lab run has pending Evidence');
  }
  final failedAcceptance = snapshot.automatedAcceptance.any(
    (acceptance) => const <VerificationState>{
      VerificationState.failed,
      VerificationState.error,
    }.contains(acceptance.verificationState),
  );
  final blockingComparison = snapshot.comparisons.any(
    (comparison) => comparison.verificationState != VerificationState.passed,
  );
  if (snapshot.state == ScenarioLabRunState.succeeded &&
      (snapshot.automatedAcceptance.any(
            (acceptance) =>
                acceptance.verificationState != VerificationState.passed,
          ) ||
          snapshot.comparisons.any(
            (comparison) =>
                comparison.verificationState != VerificationState.passed,
          ) ||
          snapshot.requiredEvidence.any(
            (evidence) =>
                evidence.state != RequiredEvidenceResultState.collected,
          ) ||
          snapshot.comparisons.length != snapshot.requiredEvidence.length ||
          snapshot.comparisons
                  .map((comparison) => comparison.requiredEvidenceId)
                  .toSet()
                  .length !=
              snapshot.comparisons.length ||
          !snapshot.comparisons
              .map((comparison) => comparison.requiredEvidenceId)
              .toSet()
              .containsAll(
                snapshot.requiredEvidence.map(
                  (evidence) => evidence.requiredEvidenceId,
                ),
              ))) {
    throw ArgumentError(
      'Succeeded Scenario Lab run requires passing published verification',
    );
  }
  if (snapshot.terminalCause == ScenarioLabTerminalCause.acceptanceFailed &&
      !failedAcceptance &&
      !blockingComparison) {
    throw ArgumentError(
      'Acceptance-failed run requires a failed acceptance or comparison',
    );
  }
  if ((snapshot.cleanup.state == ScenarioLabCleanupState.failed) !=
      (snapshot.terminalCause == ScenarioLabTerminalCause.cleanupFailed)) {
    throw ArgumentError('Cleanup failure must be the run terminal cause');
  }
}

void _validateComparisonHistory(
  List<ScenarioComparisonResult> previous,
  List<ScenarioComparisonResult> next,
) {
  final nextByBindingId =
      <ScenarioComparisonBindingId, ScenarioComparisonResult>{
        for (final result in next) result.bindingId: result,
      };
  for (final before in previous) {
    final after = nextByBindingId[before.bindingId];
    if (after == null) {
      throw ArgumentError(
        'Published Scenario Lab comparison result cannot be removed',
      );
    }
    if (before.digest != after.digest) {
      throw StateError('Published Scenario Lab comparison result is immutable');
    }
  }
}
