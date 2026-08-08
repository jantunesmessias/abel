import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';

final class ScenarioLabRelayClosed implements Exception {
  const ScenarioLabRelayClosed(this.runId);

  final ScenarioLabRunId runId;

  @override
  String toString() => 'ScenarioLabRelayClosed: ${runId.value}';
}

/// In-memory command broker between one Host-owned run and one Studio iframe.
///
/// Commands are leased through request/response calls and never broadcast as
/// events. At most one command is in flight for a run, matching the serial
/// semantics of [ScenarioLabExecutionService].
final class ScenarioLabRelayBroker {
  final Map<String, _RelayChannel> _channels = <String, _RelayChannel>{};

  int get activeCount => _channels.length;

  void open(ScenarioLabRelayTargetDescriptor descriptor) {
    final existing = _channels[descriptor.runId.value];
    if (existing != null) {
      if (existing.descriptor.digest != descriptor.digest) {
        throw StateError('Scenario Lab relay target is already open');
      }
      return;
    }
    _channels[descriptor.runId.value] = _RelayChannel(descriptor);
  }

  ScenarioLabRelayTargetDescriptor? describe(ScenarioLabRunId runId) =>
      _channels[runId.value]?.descriptor;

  AppAdapterRelayHello acceptHello(AppAdapterRelayHello hello) {
    final channel = _require(hello.runId);
    if (hello.nonce != channel.descriptor.nonce) {
      throw ArgumentError('App Adapter hello does not bind the relay target');
    }
    final previous = channel.hello;
    if (previous != null) {
      if (previous.digest != hello.digest) {
        throw StateError('Conflicting App Adapter hello');
      }
      return previous;
    }
    channel.hello = hello;
    if (!channel.helloReady.isCompleted) {
      channel.helloReady.complete(hello);
    }
    return hello;
  }

  Future<AppAdapterRelayHello> waitForHello(ScenarioLabRunId runId) {
    final channel = _require(runId);
    final hello = channel.hello;
    return hello == null
        ? channel.helloReady.future
        : Future<AppAdapterRelayHello>.value(hello);
  }

  /// Returns the current in-flight command or waits for the next one.
  ///
  /// A timeout is an empty poll, not a run failure. Multiple concurrent polls
  /// observe the same immutable command.
  Future<AppAdapterRelayCommand?> nextCommand(
    ScenarioLabRunId runId, {
    required int afterSequence,
    Duration wait = const Duration(seconds: 25),
  }) async {
    if (afterSequence < 0 || afterSequence > 9007199254740991) {
      throw ArgumentError.value(afterSequence, 'afterSequence');
    }
    if (wait < Duration.zero || wait > const Duration(seconds: 30)) {
      throw ArgumentError.value(wait, 'wait');
    }
    final channel = _require(runId);
    if (afterSequence != channel.lastCompletedSequence) {
      throw StateError('Scenario Lab relay poll sequence is stale');
    }
    final pending = channel.pending;
    if (pending != null) {
      if (pending.command.sequence != afterSequence + 1) {
        throw StateError('Scenario Lab relay command sequence is invalid');
      }
      return pending.command;
    }
    if (wait == Duration.zero) return null;
    final waiter = Completer<AppAdapterRelayCommand?>();
    channel.polls.add(waiter);
    try {
      return await waiter.future.timeout(wait, onTimeout: () => null);
    } finally {
      channel.polls.remove(waiter);
    }
  }

  Future<AppAdapterRelayResult> dispatch(AppAdapterRelayCommand command) {
    final channel = _require(command.runId);
    final hello = channel.hello;
    if (hello == null) {
      throw StateError('App Adapter hello has not been accepted');
    }
    command.validateHello(hello);
    final completed = channel.completed[command.commandId.value];
    if (completed != null) {
      final previousCommand =
          channel.completedCommands[command.commandId.value]!;
      if (previousCommand.commandDigest != command.commandDigest) {
        throw StateError('Scenario Lab command ID was reused');
      }
      return Future<AppAdapterRelayResult>.value(completed);
    }
    if (command.sequence != channel.lastCompletedSequence + 1) {
      throw StateError('Scenario Lab relay command sequence is invalid');
    }
    final current = channel.pending;
    if (current != null) {
      if (current.command.commandId != command.commandId ||
          current.command.commandDigest != command.commandDigest) {
        throw StateError('Another Scenario Lab relay command is in flight');
      }
      return current.result.future;
    }
    final pending = _PendingRelayCommand(command);
    channel.pending = pending;
    for (final poll in channel.polls.toList(growable: false)) {
      if (!poll.isCompleted) poll.complete(command);
    }
    channel.polls.clear();
    return pending.result.future;
  }

  AppAdapterRelayResult acceptResult(AppAdapterRelayResult result) {
    final channel = _require(result.runId);
    final completed = channel.completed[result.commandId.value];
    if (completed != null) {
      if (completed.resultDigest != result.resultDigest) {
        throw StateError('Conflicting App Adapter relay result');
      }
      return completed;
    }
    final pending = channel.pending;
    if (pending == null || pending.command.commandId != result.commandId) {
      throw StateError('No matching Scenario Lab relay command is in flight');
    }
    result.validateAgainst(pending.command);
    channel.pending = null;
    channel.completed[result.commandId.value] = result;
    channel.completedCommands[result.commandId.value] = pending.command;
    channel.lastCompletedSequence = result.sequence;
    if (!pending.result.isCompleted) pending.result.complete(result);
    return result;
  }

  void close(ScenarioLabRunId runId) {
    final channel = _channels.remove(runId.value);
    if (channel == null) return;
    final error = ScenarioLabRelayClosed(runId);
    if (!channel.helloReady.isCompleted) {
      channel.helloReady.completeError(error);
    }
    final pending = channel.pending;
    if (pending != null && !pending.result.isCompleted) {
      pending.result.completeError(error);
    }
    for (final poll in channel.polls) {
      if (!poll.isCompleted) {
        poll.complete(null);
      }
    }
    channel.polls.clear();
  }

  void closeAll() {
    for (final runId in _channels.keys.toList(growable: false)) {
      close(ScenarioLabRunId(runId));
    }
  }

  _RelayChannel _require(ScenarioLabRunId runId) {
    final channel = _channels[runId.value];
    if (channel == null) throw ScenarioLabRelayClosed(runId);
    return channel;
  }
}

final class _RelayChannel {
  _RelayChannel(this.descriptor);

  final ScenarioLabRelayTargetDescriptor descriptor;
  final Completer<AppAdapterRelayHello> helloReady =
      Completer<AppAdapterRelayHello>();
  final List<Completer<AppAdapterRelayCommand?>> polls =
      <Completer<AppAdapterRelayCommand?>>[];
  final Map<String, AppAdapterRelayCommand> completedCommands =
      <String, AppAdapterRelayCommand>{};
  final Map<String, AppAdapterRelayResult> completed =
      <String, AppAdapterRelayResult>{};
  AppAdapterRelayHello? hello;
  _PendingRelayCommand? pending;
  int lastCompletedSequence = 0;
}

final class _PendingRelayCommand {
  _PendingRelayCommand(this.command);

  final AppAdapterRelayCommand command;
  final Completer<AppAdapterRelayResult> result =
      Completer<AppAdapterRelayResult>();
}
