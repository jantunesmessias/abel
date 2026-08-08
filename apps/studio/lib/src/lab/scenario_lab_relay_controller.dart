import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';

import '../host/studio_host_client.dart';
import 'studio_lab_relay_transport.dart';

/// The only target-side operation the relay coordinator can perform.
///
/// Keeping this port typed prevents arbitrary maps from reaching the target
/// frame and makes the browser boundary replaceable in pure tests.
abstract interface class ScenarioLabRelayCommandTarget {
  bool get isAttached;

  void sendCommand(AppAdapterRelayCommand command);
}

enum ScenarioLabRelayControllerStatus {
  idle,
  unavailable,
  describing,
  pendingTarget,
  awaitingHello,
  authorizingHello,
  polling,
  awaitingResult,
  submittingResult,
  closed,
  cancelled,
  failed,
}

enum ScenarioLabRelayControllerFailure {
  transport,
  protocolViolation,
  targetDisconnected,
  reconnectRejected,
}

/// Sanitized observable state for UI composition.
///
/// It deliberately contains no nonce, relay payload, command, upload grant or
/// arbitrary transport error. The controller supports one local observer and
/// exposes no broadcast stream.
final class ScenarioLabRelayControllerSnapshot {
  const ScenarioLabRelayControllerSnapshot({
    required this.runId,
    required this.status,
    required this.lastAcceptedSequence,
    required this.gatewayBound,
    this.descriptorDigest,
    this.failure,
  });

  final ScenarioLabRunId runId;
  final ScenarioLabRelayControllerStatus status;
  final int lastAcceptedSequence;
  final bool gatewayBound;
  final Digest? descriptorDigest;
  final ScenarioLabRelayControllerFailure? failure;

  bool get isTerminal => switch (status) {
    ScenarioLabRelayControllerStatus.unavailable ||
    ScenarioLabRelayControllerStatus.closed ||
    ScenarioLabRelayControllerStatus.cancelled ||
    ScenarioLabRelayControllerStatus.failed => true,
    _ => false,
  };
}

typedef ScenarioLabRelayStateListener =
    void Function(ScenarioLabRelayControllerSnapshot snapshot);
typedef ScenarioLabRelayDelay = Future<void> Function(Duration duration);

/// Coordinates one Host-owned run with exactly one authorized target frame.
///
/// Authority remains at the Host. This class only forwards a strictly decoded
/// hello/result from the selected frame, long-polls one command at a time, and
/// sends that command to the same target-frame command port. A reconnect or
/// any mismatched identity, sequence or digest terminates this instance.
final class ScenarioLabRelayController {
  ScenarioLabRelayController({
    required this.binding,
    required this.host,
    required this.target,
    this.descriptionPollInterval = const Duration(milliseconds: 250),
    this.commandPollWait = const Duration(seconds: 20),
    this.delay = _defaultDelay,
    this.onStateChanged,
  }) {
    if (descriptionPollInterval <= Duration.zero) {
      throw ArgumentError.value(
        descriptionPollInterval,
        'descriptionPollInterval',
      );
    }
    if (commandPollWait < Duration.zero ||
        commandPollWait > const Duration(seconds: 30)) {
      throw ArgumentError.value(commandPollWait, 'commandPollWait');
    }
  }

  final StudioLabRelayRunBinding binding;
  final StudioHostLabRelayClient? host;
  final ScenarioLabRelayCommandTarget target;
  final Duration descriptionPollInterval;
  final Duration commandPollWait;
  final ScenarioLabRelayDelay delay;
  ScenarioLabRelayStateListener? onStateChanged;

  ScenarioLabRelayControllerStatus _status =
      ScenarioLabRelayControllerStatus.idle;
  ScenarioLabRelayControllerFailure? _failure;
  ScenarioLabRelayTargetDescriptor? _descriptor;
  Uri? _gatewayDataOrigin;
  AppAdapterRelayHello? _hello;
  AppAdapterRelayCommand? _pendingCommand;
  Future<void>? _openFuture;
  var _lastAcceptedSequence = 0;
  var _lastFrameSequence = 0;
  var _generation = 0;

  ScenarioLabRelayControllerStatus get status => _status;

  ScenarioLabRunId get runId => binding.runId;

  ScenarioLabRelayControllerSnapshot get snapshot =>
      ScenarioLabRelayControllerSnapshot(
        runId: runId,
        status: _status,
        lastAcceptedSequence: _lastAcceptedSequence,
        gatewayBound: _gatewayDataOrigin != null,
        descriptorDigest: _descriptor?.digest,
        failure: _failure,
      );

  /// Available only while this instance owns the exact authorized frame.
  ScenarioLabRelayTargetDescriptor? get descriptor => _descriptor;

  /// Returns the Host-owned v2 launch input only to this controller's exact
  /// target port. It is deliberately absent from observable snapshots.
  Uri? gatewayDataOriginFor(ScenarioLabRelayCommandTarget candidate) {
    if (!identical(candidate, target)) {
      throw ArgumentError('Scenario Lab Gateway origin target mismatch');
    }
    return _gatewayDataOrigin;
  }

  bool get isTerminal => snapshot.isTerminal;

  /// Replaces the sole local observer. No relay payload is ever published.
  void setStateListener(ScenarioLabRelayStateListener? listener) {
    onStateChanged = listener;
  }

  /// Describes until the Host reports `ready` or `closed`.
  ///
  /// Calling this more than once returns the same operation. A terminal
  /// controller cannot be restarted; construct a new instance with a fresh
  /// Host connection for an intentional reconnect.
  Future<void> open() {
    final existing = _openFuture;
    if (existing != null) return existing;
    if (_status != ScenarioLabRelayControllerStatus.idle) {
      return Future<void>.value();
    }
    final activeHost = host;
    if (activeHost == null) {
      _transition(ScenarioLabRelayControllerStatus.unavailable);
      return _openFuture = Future<void>.value();
    }
    final generation = ++_generation;
    _transition(ScenarioLabRelayControllerStatus.describing);
    return _openFuture = _describeUntilReady(activeHost, generation);
  }

  /// Receives one message already authorized by the target-frame boundary.
  ///
  /// The payload is decoded again using the closed public relay codecs. Only
  /// Hello and Result documents are accepted; adjacent frame messages fail
  /// this relay closed and are never forwarded to the Host.
  void acceptFrameEnvelope(PostMessageEnvelope envelope) {
    final descriptor = _descriptor;
    if (descriptor == null || isTerminal) return;
    if (envelope.protocolVersion != 1 ||
        envelope.sequence <= _lastFrameSequence ||
        envelope.sessionId != runId.value ||
        envelope.nonce != descriptor.nonce.value) {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
      return;
    }
    _lastFrameSequence = envelope.sequence;
    final kind = envelope.payload['kind'];
    try {
      if (kind == 'AppAdapterRelayHello') {
        _acceptHello(AppAdapterRelayHello.fromJson(envelope.payload));
        return;
      }
      if (kind == 'AppAdapterRelayResult') {
        _acceptResult(AppAdapterRelayResult.fromJson(envelope.payload));
        return;
      }
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
    } on FormatException {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
    } on ArgumentError {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
    }
  }

  /// Stops this local relay without asserting that the Host run was cancelled.
  void cancel() {
    if (isTerminal) return;
    _terminate(ScenarioLabRelayControllerStatus.cancelled);
  }

  /// Invalidates the descriptor, outstanding command and every late response.
  void close() {
    if (isTerminal) return;
    _terminate(ScenarioLabRelayControllerStatus.closed);
  }

  Future<void> _describeUntilReady(
    StudioHostLabRelayClient host,
    int generation,
  ) async {
    while (_isCurrent(generation)) {
      final StudioLabRelayDescription description;
      try {
        description = await host.describeLabRelay(binding);
      } on StudioLabRelayUnavailable {
        if (_isCurrent(generation)) {
          _terminate(ScenarioLabRelayControllerStatus.unavailable);
        }
        return;
      } on StudioLabRelayGatewayV2Required {
        _failIfCurrent(
          generation,
          ScenarioLabRelayControllerFailure.protocolViolation,
        );
        return;
      } on Object {
        _failIfCurrent(generation, ScenarioLabRelayControllerFailure.transport);
        return;
      }
      if (!_isCurrent(generation)) return;
      switch (description.status) {
        case ScenarioLabRelayDescriptionStatus.pending:
          _transition(ScenarioLabRelayControllerStatus.pendingTarget);
          await delay(descriptionPollInterval);
          if (_isCurrent(generation)) {
            _transition(ScenarioLabRelayControllerStatus.describing);
          }
        case ScenarioLabRelayDescriptionStatus.ready:
          final descriptor = description.descriptor;
          if (descriptor == null || descriptor.runId != runId) {
            _fail(ScenarioLabRelayControllerFailure.protocolViolation);
            return;
          }
          _descriptor = descriptor;
          _gatewayDataOrigin = description.gatewayDataOriginFor(binding);
          _transition(ScenarioLabRelayControllerStatus.awaitingHello);
          return;
        case ScenarioLabRelayDescriptionStatus.closed:
          _terminate(ScenarioLabRelayControllerStatus.closed);
          return;
      }
    }
  }

  void _acceptHello(AppAdapterRelayHello hello) {
    final descriptor = _descriptor;
    if (descriptor == null) return;
    if (_hello != null ||
        _status != ScenarioLabRelayControllerStatus.awaitingHello) {
      _fail(ScenarioLabRelayControllerFailure.reconnectRejected);
      return;
    }
    final submission = ScenarioLabRelayHelloSubmission(
      descriptorDigest: descriptor.digest,
      hello: hello,
    );
    try {
      submission.validateAgainst(descriptor);
    } on ArgumentError {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
      return;
    }
    _hello = hello;
    _transition(ScenarioLabRelayControllerStatus.authorizingHello);
    final generation = _generation;
    unawaited(_authorizeHello(submission, hello, descriptor, generation));
  }

  Future<void> _authorizeHello(
    ScenarioLabRelayHelloSubmission submission,
    AppAdapterRelayHello hello,
    ScenarioLabRelayTargetDescriptor descriptor,
    int generation,
  ) async {
    final ScenarioLabRelayHelloAcknowledgement acknowledgement;
    try {
      acknowledgement = await host!.submitLabRelayHello(submission);
    } on Object {
      _failIfCurrent(generation, ScenarioLabRelayControllerFailure.transport);
      return;
    }
    if (!_isCurrent(generation)) return;
    if (acknowledgement.runId != runId ||
        acknowledgement.descriptorDigest != descriptor.digest ||
        acknowledgement.acceptedHelloDigest != hello.digest) {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
      return;
    }
    _transition(ScenarioLabRelayControllerStatus.polling);
    unawaited(_poll(generation));
  }

  Future<void> _poll(int generation) async {
    final descriptor = _descriptor;
    final hello = _hello;
    if (descriptor == null || hello == null) return;
    while (_isCurrent(generation) &&
        _status == ScenarioLabRelayControllerStatus.polling) {
      final request = ScenarioLabRelayPollRequest(
        runId: runId,
        descriptorDigest: descriptor.digest,
        afterSequence: _lastAcceptedSequence,
        waitMs: commandPollWait.inMilliseconds,
      );
      final ScenarioLabRelayPollResponse response;
      try {
        response = await host!.nextLabRelayCommand(request);
      } on Object {
        _failIfCurrent(generation, ScenarioLabRelayControllerFailure.transport);
        return;
      }
      if (!_isCurrent(generation)) return;
      if (response.runId != runId ||
          response.descriptorDigest != descriptor.digest ||
          response.afterSequence != _lastAcceptedSequence) {
        _fail(ScenarioLabRelayControllerFailure.protocolViolation);
        return;
      }
      switch (response.state) {
        case ScenarioLabRelayPollState.idle:
          // A conforming Host long-polls for `waitMs`. The bounded backoff also
          // prevents a broken peer from turning immediate idle responses into
          // a busy loop.
          await delay(descriptionPollInterval);
          continue;
        case ScenarioLabRelayPollState.closed:
          _terminate(ScenarioLabRelayControllerStatus.closed);
          return;
        case ScenarioLabRelayPollState.command:
          final command = response.command;
          if (command == null ||
              command.runId != runId ||
              command.nonce != descriptor.nonce ||
              command.sequence != _lastAcceptedSequence + 1) {
            _fail(ScenarioLabRelayControllerFailure.protocolViolation);
            return;
          }
          try {
            command.validateHello(hello);
          } on ArgumentError {
            _fail(ScenarioLabRelayControllerFailure.protocolViolation);
            return;
          }
          if (!target.isAttached) {
            _fail(ScenarioLabRelayControllerFailure.targetDisconnected);
            return;
          }
          _pendingCommand = command;
          try {
            target.sendCommand(command);
          } on Object {
            _fail(ScenarioLabRelayControllerFailure.targetDisconnected);
            return;
          }
          _transition(ScenarioLabRelayControllerStatus.awaitingResult);
          return;
      }
    }
  }

  void _acceptResult(AppAdapterRelayResult result) {
    final descriptor = _descriptor;
    final command = _pendingCommand;
    if (descriptor == null ||
        command == null ||
        _status != ScenarioLabRelayControllerStatus.awaitingResult) {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
      return;
    }
    if (result.runId != runId || result.nonce != descriptor.nonce) {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
      return;
    }
    try {
      result.validateAgainst(command);
    } on ArgumentError {
      _fail(ScenarioLabRelayControllerFailure.protocolViolation);
      return;
    }
    final submission = ScenarioLabRelayResultSubmission(
      descriptorDigest: descriptor.digest,
      result: result,
    );
    _transition(ScenarioLabRelayControllerStatus.submittingResult);
    final generation = _generation;
    unawaited(
      _submitResult(submission, result, descriptor, command, generation),
    );
  }

  Future<void> _submitResult(
    ScenarioLabRelayResultSubmission submission,
    AppAdapterRelayResult result,
    ScenarioLabRelayTargetDescriptor descriptor,
    AppAdapterRelayCommand command,
    int generation,
  ) async {
    final ScenarioLabRelayResultAcknowledgement acknowledgement;
    try {
      acknowledgement = await host!.submitLabRelayResult(submission);
    } on Object {
      _failIfCurrent(generation, ScenarioLabRelayControllerFailure.transport);
      return;
    }
    if (!_isCurrent(generation)) return;
    if (identical(_pendingCommand, command) &&
        acknowledgement.runId == runId &&
        acknowledgement.descriptorDigest == descriptor.digest &&
        acknowledgement.acceptedResultDigest == result.resultDigest) {
      _lastAcceptedSequence = command.sequence;
      _pendingCommand = null;
      _transition(ScenarioLabRelayControllerStatus.polling);
      unawaited(_poll(generation));
      return;
    }
    _fail(ScenarioLabRelayControllerFailure.protocolViolation);
  }

  bool _isCurrent(int generation) => generation == _generation && !isTerminal;

  void _failIfCurrent(
    int generation,
    ScenarioLabRelayControllerFailure failure,
  ) {
    if (_isCurrent(generation)) _fail(failure);
  }

  void _fail(ScenarioLabRelayControllerFailure failure) {
    if (isTerminal) return;
    _failure = failure;
    _terminate(ScenarioLabRelayControllerStatus.failed);
  }

  void _terminate(ScenarioLabRelayControllerStatus status) {
    _generation += 1;
    _pendingCommand = null;
    _hello = null;
    _descriptor = null;
    _gatewayDataOrigin = null;
    _lastFrameSequence = 0;
    _transition(status);
  }

  void _transition(ScenarioLabRelayControllerStatus status) {
    _status = status;
    onStateChanged?.call(snapshot);
  }
}

Future<void> _defaultDelay(Duration duration) => Future<void>.delayed(duration);
