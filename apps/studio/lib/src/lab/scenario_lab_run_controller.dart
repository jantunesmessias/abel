import 'package:experience_contracts/experience_contracts.dart';

import '../host/studio_host_client.dart';
import 'studio_scenario_lab_run_transport.dart';

enum ScenarioLabRunControllerStatus {
  idle,
  unavailable,
  starting,
  nonTerminal,
  active,
  polling,
  cancelling,
  reattaching,
  terminal,
  interrupted,
  failed,
  closed,
}

enum ScenarioLabRunControllerFailure {
  transport,
  protocolViolation,
  fencingMismatch,
  paginationLimit,
}

final class ScenarioLabRunControllerSnapshot {
  const ScenarioLabRunControllerSnapshot({
    required this.status,
    required this.retainedObservationCount,
    required this.historyTruncated,
    this.runId,
    this.runState,
    this.disposition,
    this.sequence,
    this.snapshotDigest,
    this.resultDigest,
    this.failure,
  });

  final ScenarioLabRunControllerStatus status;
  final ScenarioLabRunId? runId;
  final ScenarioLabRunState? runState;
  final ScenarioLabRunDisposition? disposition;
  final int? sequence;
  final Digest? snapshotDigest;
  final Digest? resultDigest;
  final ScenarioLabRunControllerFailure? failure;
  final int retainedObservationCount;
  final bool historyTruncated;

  bool get isTerminal => switch (status) {
    ScenarioLabRunControllerStatus.unavailable ||
    ScenarioLabRunControllerStatus.terminal ||
    ScenarioLabRunControllerStatus.interrupted ||
    ScenarioLabRunControllerStatus.failed ||
    ScenarioLabRunControllerStatus.closed => true,
    _ => false,
  };
}

typedef ScenarioLabRunStateListener =
    void Function(ScenarioLabRunControllerSnapshot snapshot);

final class ScenarioLabRunController {
  ScenarioLabRunController({
    required this.host,
    required this.contentIdentity,
    required this.manifest,
    this.reattachPageSize = 10,
    this.maxReattachPages = 20,
    this.maxRetainedObservations = 200,
    this.onStateChanged,
  }) {
    if (contentIdentity.catalogDigest != manifest.catalogDigest ||
        contentIdentity.scenarioLabManifestDigest != manifest.digest) {
      throw ArgumentError(
        'Scenario Lab controller requires one atomic content generation',
      );
    }
    if (reattachPageSize < 1 || reattachPageSize > 100) {
      throw ArgumentError.value(reattachPageSize, 'reattachPageSize');
    }
    if (maxReattachPages < 1 || maxReattachPages > 1000) {
      throw ArgumentError.value(maxReattachPages, 'maxReattachPages');
    }
    if (maxRetainedObservations < 1 || maxRetainedObservations > 10000) {
      throw ArgumentError.value(
        maxRetainedObservations,
        'maxRetainedObservations',
      );
    }
  }

  final StudioHostScenarioLabRunClient? host;
  final ExperienceContentSetIdentity contentIdentity;
  final ScenarioLabManifest manifest;
  final int reattachPageSize;
  final int maxReattachPages;
  final int maxRetainedObservations;
  ScenarioLabRunStateListener? onStateChanged;

  ScenarioLabRunControllerStatus _status = ScenarioLabRunControllerStatus.idle;
  ScenarioLabRunControllerFailure? _failure;
  ScenarioLabRunStartRequest? _startRequest;
  ScenarioId? _expectedScenarioId;
  ScenarioScriptId? _expectedScriptId;
  Digest? _expectedStartRequestDigest;
  Digest? _expectedObservedContentSetDigest;
  var _allowHistoricalTerminalContent = false;
  ScenarioLabRunId? _ownedRunId;
  ScenarioLabRunSnapshot? _current;
  ScenarioLabRunResult? _result;
  ScenarioLabRunDisposition? _disposition;
  final List<ScenarioLabRunSnapshot> _observations = <ScenarioLabRunSnapshot>[];
  var _historyTruncated = false;
  var _epoch = 0;

  ScenarioLabRunControllerStatus get status => _status;

  ScenarioLabRunSnapshot? get current => _current;

  ScenarioLabRunResult? get result => _result;

  List<ScenarioLabRunSnapshot> get retainedObservations =>
      List<ScenarioLabRunSnapshot>.unmodifiable(_observations);

  ScenarioLabRunControllerSnapshot get snapshot =>
      ScenarioLabRunControllerSnapshot(
        status: _status,
        runId: _ownedRunId,
        runState: _current?.state,
        disposition: _disposition,
        sequence: _current?.sequence,
        snapshotDigest: _current?.digest,
        resultDigest: _result?.digest,
        failure: _failure,
        retainedObservationCount: _observations.length,
        historyTruncated: _historyTruncated,
      );

  void setStateListener(ScenarioLabRunStateListener? listener) {
    onStateChanged = listener;
  }

  Future<void> start(ScenarioLabRunStartRequest request) async {
    if (_status == ScenarioLabRunControllerStatus.closed) return;
    if (_operationInFlight || _hasNonTerminalRun) {
      throw StateError('Scenario Lab controller already owns an active run');
    }
    if (!_validateStartRequest(request)) return;
    final activeHost = host;
    if (activeHost == null) {
      _transition(ScenarioLabRunControllerStatus.unavailable);
      return;
    }

    _resetRun(request);
    final operationEpoch = ++_epoch;
    _transition(ScenarioLabRunControllerStatus.starting);
    try {
      final response = await activeHost.startScenarioLabRun(request);
      if (!_isCurrent(operationEpoch)) return;
      _validateAndAcceptCurrent(response, request: request);
      _finishFromCurrent();
    } on StudioScenarioLabRunUnavailable {
      _unavailableIfCurrent(operationEpoch);
    } on StudioScenarioLabRunFencingMismatch {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on _ScenarioLabFenceViolation {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on FormatException {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on ArgumentError {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on Object {
      _failIfCurrent(operationEpoch, ScenarioLabRunControllerFailure.transport);
    }
  }

  Future<void> poll() async {
    final binding = _activeBinding();
    if (binding == null) return;
    final activeHost = host;
    if (activeHost == null) {
      _transition(ScenarioLabRunControllerStatus.unavailable);
      return;
    }

    final operationEpoch = ++_epoch;
    _transition(ScenarioLabRunControllerStatus.polling);
    try {
      final response = await activeHost.getScenarioLabRun(
        ScenarioLabRunReference(runId: binding.current.runId),
      );
      if (!_isCurrent(operationEpoch)) return;
      _validateAndAcceptCurrent(response, request: _startRequest);
      _finishFromCurrent();
    } on StudioScenarioLabRunUnavailable {
      _unavailableIfCurrent(operationEpoch);
    } on StudioScenarioLabRunFencingMismatch {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on _ScenarioLabFenceViolation {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on FormatException {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on ArgumentError {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on Object {
      _failIfCurrent(operationEpoch, ScenarioLabRunControllerFailure.transport);
    }
  }

  Future<void> cancel() async {
    final binding = _cancellableBinding();
    if (binding == null) return;
    final activeHost = host;
    if (activeHost == null) {
      _transition(ScenarioLabRunControllerStatus.unavailable);
      return;
    }

    final operationEpoch = ++_epoch;
    _transition(ScenarioLabRunControllerStatus.cancelling);
    try {
      final response = await activeHost.cancelScenarioLabRun(
        ScenarioLabRunReference(runId: binding.runId),
      );
      if (!_isCurrent(operationEpoch)) return;
      _validateAndAcceptCurrent(response, request: _startRequest);
      _finishFromCurrent();
    } on StudioScenarioLabRunUnavailable {
      _unavailableIfCurrent(operationEpoch);
    } on StudioScenarioLabRunFencingMismatch {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on _ScenarioLabFenceViolation {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on FormatException {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on ArgumentError {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on Object {
      _failIfCurrent(operationEpoch, ScenarioLabRunControllerFailure.transport);
    }
  }

  Future<void> reattach({
    required ScenarioLabRunId runId,
    required ScenarioLabRunStartRequest request,
  }) async {
    if (_status == ScenarioLabRunControllerStatus.closed) return;
    if (!_validateStartRequest(request)) return;
    await _reattachBound(
      runId: runId,
      scenarioId: request.scenarioId,
      scriptId: request.scriptId,
      request: request,
    );
  }

  Future<void> reattachKnownRun({
    required ScenarioLabRunId runId,
    required ScenarioId scenarioId,
    required ScenarioScriptId scriptId,
    bool allowHistoricalTerminalContent = false,
  }) async {
    if (_status == ScenarioLabRunControllerStatus.closed) return;
    if (!_selectionDeclared(scenarioId, scriptId)) {
      _fail(ScenarioLabRunControllerFailure.fencingMismatch);
      return;
    }
    await _reattachBound(
      runId: runId,
      scenarioId: scenarioId,
      scriptId: scriptId,
      allowHistoricalTerminalContent: allowHistoricalTerminalContent,
    );
  }

  Future<void> _reattachBound({
    required ScenarioLabRunId runId,
    required ScenarioId scenarioId,
    required ScenarioScriptId scriptId,
    ScenarioLabRunStartRequest? request,
    bool allowHistoricalTerminalContent = false,
  }) async {
    if (_status == ScenarioLabRunControllerStatus.closed) return;
    if (_operationInFlight) {
      throw StateError('Scenario Lab controller operation is already active');
    }
    final activeHost = host;
    if (activeHost == null) {
      _transition(ScenarioLabRunControllerStatus.unavailable);
      return;
    }
    final existingRunId = _ownedRunId;
    final existing = _current;
    if (existingRunId != null &&
        existingRunId != runId &&
        (existing == null || !existing.state.isTerminal)) {
      throw StateError('Scenario Lab controller already owns another run');
    }
    if (existingRunId != runId) {
      _resetKnownRun(
        runId: runId,
        scenarioId: scenarioId,
        scriptId: scriptId,
        request: request,
        allowHistoricalTerminalContent: allowHistoricalTerminalContent,
      );
    } else {
      if (_expectedScenarioId != scenarioId ||
          _expectedScriptId != scriptId ||
          (request != null &&
              _expectedStartRequestDigest != null &&
              _expectedStartRequestDigest != request.digest)) {
        _fail(ScenarioLabRunControllerFailure.fencingMismatch);
        return;
      }
      _startRequest ??= request;
      _expectedStartRequestDigest ??= request?.digest;
      if (_allowHistoricalTerminalContent && !allowHistoricalTerminalContent) {
        _fail(ScenarioLabRunControllerFailure.fencingMismatch);
        return;
      }
      _allowHistoricalTerminalContent = allowHistoricalTerminalContent;
      _result = null;
      _disposition = null;
      _failure = null;
    }

    final operationEpoch = ++_epoch;
    var cursor = _current?.sequence ?? -1;
    _transition(ScenarioLabRunControllerStatus.reattaching);
    try {
      for (var page = 0; page < maxReattachPages; page += 1) {
        final pageRequest = ScenarioLabRunObserveRequest(
          runId: runId,
          afterSequence: cursor,
          limit: reattachPageSize,
        );
        final response = await activeHost.reattachScenarioLabRun(pageRequest);
        if (!_isCurrent(operationEpoch)) return;
        _validateObservation(response, pageRequest, request);
        if (!response.hasMore) {
          if (_allowHistoricalTerminalContent &&
              _expectedObservedContentSetDigest !=
                  contentIdentity.contentSetDigest &&
              (response.disposition != ScenarioLabRunDisposition.terminal ||
                  response.result == null)) {
            throw const _ScenarioLabFenceViolation();
          }
        }
        _acceptObservationPage(response, request);

        if (!response.hasMore) {
          _disposition = response.disposition;
          final result = response.result;
          if (result != null) {
            _validateResult(result, request, expectedCurrent: response.current);
          }
          _result = result;
          _finishFromDisposition();
          return;
        }
        if (response.observations.isEmpty) {
          throw const FormatException(
            'Scenario Lab page cannot advance its advertised cursor',
          );
        }
        cursor = response.observations.last.sequence;
      }
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.paginationLimit,
      );
    } on StudioScenarioLabRunUnavailable {
      _unavailableIfCurrent(operationEpoch);
    } on StudioScenarioLabRunFencingMismatch {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on _ScenarioLabFenceViolation {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.fencingMismatch,
      );
    } on FormatException {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on ArgumentError {
      _failIfCurrent(
        operationEpoch,
        ScenarioLabRunControllerFailure.protocolViolation,
      );
    } on Object {
      _failIfCurrent(operationEpoch, ScenarioLabRunControllerFailure.transport);
    }
  }

  void close() {
    if (_status == ScenarioLabRunControllerStatus.closed) return;
    _epoch += 1;
    _startRequest = null;
    _expectedScenarioId = null;
    _expectedScriptId = null;
    _expectedStartRequestDigest = null;
    _expectedObservedContentSetDigest = null;
    _allowHistoricalTerminalContent = false;
    _ownedRunId = null;
    _current = null;
    _result = null;
    _disposition = null;
    _observations.clear();
    _historyTruncated = false;
    _transition(ScenarioLabRunControllerStatus.closed);
  }

  bool get _operationInFlight => switch (_status) {
    ScenarioLabRunControllerStatus.starting ||
    ScenarioLabRunControllerStatus.polling ||
    ScenarioLabRunControllerStatus.cancelling ||
    ScenarioLabRunControllerStatus.reattaching => true,
    _ => false,
  };

  bool get _hasNonTerminalRun =>
      _current != null && !_current!.state.isTerminal;

  _ScenarioLabRunBinding? _activeBinding() {
    if (_status == ScenarioLabRunControllerStatus.closed ||
        _operationInFlight) {
      return null;
    }
    final current = _current;
    if (current == null || current.state.isTerminal) {
      return null;
    }
    return _ScenarioLabRunBinding(current: current);
  }

  _ScenarioLabCancellationBinding? _cancellableBinding() {
    if (_status == ScenarioLabRunControllerStatus.closed ||
        _status == ScenarioLabRunControllerStatus.starting ||
        _status == ScenarioLabRunControllerStatus.cancelling) {
      return null;
    }
    final runId = _ownedRunId;
    final current = _current;
    if (runId == null ||
        current == null ||
        current.state.isTerminal ||
        current.contentSetDigest != contentIdentity.contentSetDigest) {
      return null;
    }
    return _ScenarioLabCancellationBinding(runId: runId);
  }

  bool _validateStartRequest(ScenarioLabRunStartRequest request) {
    try {
      request.validateAgainst(
        contentSet: contentIdentity,
        scenarioLabManifest: manifest,
      );
      return true;
    } on ArgumentError {
      _fail(ScenarioLabRunControllerFailure.fencingMismatch);
      return false;
    }
  }

  bool _selectionDeclared(ScenarioId scenarioId, ScenarioScriptId scriptId) {
    final plans = manifest.plans.where((plan) => plan.scenarioId == scenarioId);
    final scripts = manifest.scripts.where(
      (script) => script.id == scriptId && script.scenarioId == scenarioId,
    );
    return plans.length == 1 &&
        scripts.length == 1 &&
        plans.single.scriptIds.contains(scriptId);
  }

  void _validateSnapshot(
    ScenarioLabRunSnapshot candidate, {
    ScenarioLabRunStartRequest? request,
    ScenarioLabRunId? expectedRunId,
  }) {
    try {
      if (request != null) candidate.validateAgainstStart(request);
    } on ArgumentError {
      throw const _ScenarioLabFenceViolation();
    }
    if (candidate.catalogDigest != contentIdentity.catalogDigest ||
        candidate.scenarioLabManifestDigest != manifest.digest ||
        candidate.scenarioId != _expectedScenarioId ||
        candidate.scriptId != _expectedScriptId ||
        (_expectedStartRequestDigest != null &&
            candidate.startRequestDigest != _expectedStartRequestDigest)) {
      throw const _ScenarioLabFenceViolation();
    }
    final observedContentSetDigest = _expectedObservedContentSetDigest;
    if (observedContentSetDigest == null) {
      if (!_allowHistoricalTerminalContent &&
          candidate.contentSetDigest != contentIdentity.contentSetDigest) {
        throw const _ScenarioLabFenceViolation();
      }
      _expectedObservedContentSetDigest = candidate.contentSetDigest;
    } else if (candidate.contentSetDigest != observedContentSetDigest) {
      throw const _ScenarioLabFenceViolation();
    }
    if (expectedRunId != null && candidate.runId != expectedRunId) {
      throw const FormatException(
        'Scenario Lab observation belongs to another run',
      );
    }
  }

  void _validateAndAcceptCurrent(
    ScenarioLabRunSnapshot candidate, {
    ScenarioLabRunStartRequest? request,
  }) {
    final expectedRunId = _ownedRunId;
    _validateSnapshot(
      candidate,
      request: request,
      expectedRunId: expectedRunId,
    );
    final current = _current;
    if (current != null) {
      if (candidate.sequence < current.sequence ||
          (candidate.sequence == current.sequence &&
              candidate.digest != current.digest) ||
          (current.state.isTerminal && candidate.digest != current.digest)) {
        throw const FormatException(
          'Scenario Lab latest snapshot is not monotonic',
        );
      }
      if (candidate.sequence == current.sequence) return;
    }
    _expectedStartRequestDigest ??= candidate.startRequestDigest;
    _ownedRunId ??= candidate.runId;
    _current = candidate;
    _retain(candidate);
  }

  void _validateObservation(
    ScenarioLabRunObservation response,
    ScenarioLabRunObserveRequest pageRequest,
    ScenarioLabRunStartRequest? request,
  ) {
    if (response.runId != pageRequest.runId ||
        response.afterSequence != pageRequest.afterSequence ||
        response.observations.length > pageRequest.limit) {
      throw const FormatException(
        'Scenario Lab observation does not bind its page request',
      );
    }
    _validateSnapshot(
      response.current,
      request: request,
      expectedRunId: pageRequest.runId,
    );
    for (final observation in response.observations) {
      _validateSnapshot(
        observation,
        request: request,
        expectedRunId: pageRequest.runId,
      );
      _validateRetained(observation);
    }
    if (response.observations.any(
      (item) => item.startRequestDigest != response.current.startRequestDigest,
    )) {
      throw const _ScenarioLabFenceViolation();
    }
    final current = _current;
    if (current != null &&
        (response.current.sequence < current.sequence ||
            (response.current.sequence == current.sequence &&
                response.current.digest != current.digest) ||
            (current.state.isTerminal &&
                response.current.digest != current.digest))) {
      throw const FormatException(
        'Scenario Lab observation current snapshot regressed',
      );
    }
    _validateRetained(response.current);
    final result = response.result;
    if (result != null) {
      _validateResult(result, request, expectedCurrent: response.current);
    }
    _expectedStartRequestDigest ??= response.current.startRequestDigest;
  }

  void _validateResult(
    ScenarioLabRunResult candidate,
    ScenarioLabRunStartRequest? request, {
    required ScenarioLabRunSnapshot expectedCurrent,
  }) {
    _validateSnapshot(
      candidate.finalSnapshot,
      request: request,
      expectedRunId: expectedCurrent.runId,
    );
    if (candidate.finalSnapshot.digest != expectedCurrent.digest) {
      throw const FormatException(
        'Scenario Lab result does not bind the current snapshot',
      );
    }
  }

  void _acceptObservationPage(
    ScenarioLabRunObservation response,
    ScenarioLabRunStartRequest? request,
  ) {
    for (final observation in response.observations) {
      _retain(observation);
    }
    _validateAndAcceptCurrent(response.current, request: request);
  }

  void _retain(ScenarioLabRunSnapshot observation) {
    final existingIndex = _observations.indexWhere(
      (item) => item.sequence == observation.sequence,
    );
    if (existingIndex >= 0) {
      if (_observations[existingIndex].digest != observation.digest) {
        throw const FormatException(
          'Scenario Lab sequence changed immutable content',
        );
      }
      return;
    }
    _observations.add(observation);
    _observations.sort(
      (left, right) => left.sequence.compareTo(right.sequence),
    );
    while (_observations.length > maxRetainedObservations) {
      _observations.removeAt(0);
      _historyTruncated = true;
    }
  }

  void _validateRetained(ScenarioLabRunSnapshot observation) {
    final existing = _observations.where(
      (item) => item.sequence == observation.sequence,
    );
    if (existing.isNotEmpty && existing.single.digest != observation.digest) {
      throw const FormatException(
        'Scenario Lab sequence changed immutable content',
      );
    }
  }

  void _resetRun(
    ScenarioLabRunStartRequest request, {
    ScenarioLabRunId? runId,
  }) {
    _startRequest = request;
    _expectedScenarioId = request.scenarioId;
    _expectedScriptId = request.scriptId;
    _expectedStartRequestDigest = request.digest;
    _expectedObservedContentSetDigest = contentIdentity.contentSetDigest;
    _allowHistoricalTerminalContent = false;
    _ownedRunId = runId;
    _current = null;
    _result = null;
    _disposition = null;
    _failure = null;
    _observations.clear();
    _historyTruncated = false;
  }

  void _resetKnownRun({
    required ScenarioLabRunId runId,
    required ScenarioId scenarioId,
    required ScenarioScriptId scriptId,
    ScenarioLabRunStartRequest? request,
    bool allowHistoricalTerminalContent = false,
  }) {
    _startRequest = request;
    _expectedScenarioId = scenarioId;
    _expectedScriptId = scriptId;
    _expectedStartRequestDigest = request?.digest;
    _expectedObservedContentSetDigest = request?.expectedContentSetDigest;
    _allowHistoricalTerminalContent = allowHistoricalTerminalContent;
    _ownedRunId = runId;
    _current = null;
    _result = null;
    _disposition = null;
    _failure = null;
    _observations.clear();
    _historyTruncated = false;
  }

  void _finishFromCurrent() {
    _disposition = null;
    _result = null;
    _transition(
      _current!.state.isTerminal
          ? ScenarioLabRunControllerStatus.terminal
          : ScenarioLabRunControllerStatus.nonTerminal,
    );
  }

  void _finishFromDisposition() {
    switch (_disposition!) {
      case ScenarioLabRunDisposition.active:
        _transition(ScenarioLabRunControllerStatus.active);
      case ScenarioLabRunDisposition.terminal:
        _transition(ScenarioLabRunControllerStatus.terminal);
      case ScenarioLabRunDisposition.interrupted:
        _transition(ScenarioLabRunControllerStatus.interrupted);
    }
  }

  bool _isCurrent(int operationEpoch) =>
      _status != ScenarioLabRunControllerStatus.closed &&
      _epoch == operationEpoch;

  void _unavailableIfCurrent(int operationEpoch) {
    if (_isCurrent(operationEpoch)) {
      _transition(ScenarioLabRunControllerStatus.unavailable);
    }
  }

  void _failIfCurrent(
    int operationEpoch,
    ScenarioLabRunControllerFailure failure,
  ) {
    if (_isCurrent(operationEpoch)) _fail(failure);
  }

  void _fail(ScenarioLabRunControllerFailure failure) {
    _epoch += 1;
    if (_allowHistoricalTerminalContent &&
        _expectedObservedContentSetDigest != null &&
        _expectedObservedContentSetDigest != contentIdentity.contentSetDigest) {
      _ownedRunId = null;
      _current = null;
      _result = null;
      _disposition = null;
      _observations.clear();
      _historyTruncated = false;
    }
    _failure = failure;
    _transition(ScenarioLabRunControllerStatus.failed);
  }

  void _transition(ScenarioLabRunControllerStatus status) {
    _status = status;
    onStateChanged?.call(snapshot);
  }
}

final class _ScenarioLabRunBinding {
  const _ScenarioLabRunBinding({required this.current});

  final ScenarioLabRunSnapshot current;
}

final class _ScenarioLabCancellationBinding {
  const _ScenarioLabCancellationBinding({required this.runId});

  final ScenarioLabRunId runId;
}

final class _ScenarioLabFenceViolation implements Exception {
  const _ScenarioLabFenceViolation();
}
