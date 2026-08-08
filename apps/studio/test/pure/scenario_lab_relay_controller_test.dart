import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/lab/scenario_lab_relay_controller.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  test('explicitly reports an absent optional Host relay port', () async {
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: null,
      target: _CommandTarget(),
    );

    await controller.open();

    expect(controller.status, ScenarioLabRelayControllerStatus.unavailable);
    expect(controller.descriptor, isNull);
    expect(controller.snapshot.isTerminal, isTrue);
  });

  test(
    'maps a Host without relay lifecycle to the explicit fallback',
    () async {
      final controller = ScenarioLabRelayController(
        binding: _binding,
        host: _UnavailableRelayHost(),
        target: _CommandTarget(),
      );

      await controller.open();

      expect(controller.status, ScenarioLabRelayControllerStatus.unavailable);
      expect(controller.snapshot.failure, isNull);
    },
  );

  test(
    'forwards one authorized hello, command and result without broadcasting',
    () async {
      final command = _readCommand();
      final host = _RelayHost(
        descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
        polls: <ScenarioLabRelayPollResponse>[
          _commandPoll(command),
          _closedPoll(afterSequence: 1),
        ],
      );
      final target = _CommandTarget();
      final observed = <ScenarioLabRelayControllerSnapshot>[];
      final controller = ScenarioLabRelayController(
        binding: _binding,
        host: host,
        target: target,
        onStateChanged: observed.add,
      );

      await controller.open();
      expect(controller.status, ScenarioLabRelayControllerStatus.awaitingHello);
      controller.acceptFrameEnvelope(_envelope(_hello().toJson(), sequence: 1));
      await _waitFor(
        () =>
            controller.status ==
            ScenarioLabRelayControllerStatus.awaitingResult,
      );

      expect(host.helloSubmissions.single.hello.digest, _hello().digest);
      expect(target.commands.single.commandDigest, command.commandDigest);
      expect(
        observed.every(
          (snapshot) =>
              snapshot.descriptorDigest == null ||
              snapshot.descriptorDigest == _descriptor.digest,
        ),
        isTrue,
      );

      final result = _readResult(command);
      controller.acceptFrameEnvelope(_envelope(result.toJson(), sequence: 2));
      await _waitFor(
        () => controller.status == ScenarioLabRelayControllerStatus.closed,
      );

      expect(
        host.resultSubmissions.single.result.resultDigest,
        result.resultDigest,
      );
      expect(host.pollRequests.map((item) => item.afterSequence), <int>[0, 1]);
      expect(controller.snapshot.lastAcceptedSequence, 1);
      expect(controller.descriptor, isNull);
    },
  );

  test('rejects a second hello as a target reconnect', () async {
    final host = _RelayHost(
      descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
      pendingPoll: Completer<ScenarioLabRelayPollResponse>(),
    );
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: host,
      target: _CommandTarget(),
    );
    await controller.open();
    controller.acceptFrameEnvelope(_envelope(_hello().toJson(), sequence: 1));
    await _waitFor(
      () => controller.status == ScenarioLabRelayControllerStatus.polling,
    );

    controller.acceptFrameEnvelope(_envelope(_hello().toJson(), sequence: 2));

    expect(controller.status, ScenarioLabRelayControllerStatus.failed);
    expect(
      controller.snapshot.failure,
      ScenarioLabRelayControllerFailure.reconnectRejected,
    );
    expect(controller.descriptor, isNull);
  });

  test(
    'revalidates the authorized frame envelope identity and sequence',
    () async {
      for (final envelope in <PostMessageEnvelope>[
        PostMessageEnvelope(
          protocolVersion: 2,
          sessionId: _runId.value,
          nonce: _nonce.value,
          sequence: 1,
          payload: _hello().toJson(),
        ),
        PostMessageEnvelope(
          protocolVersion: 1,
          sessionId: 'run-00000002',
          nonce: _nonce.value,
          sequence: 1,
          payload: _hello().toJson(),
        ),
        PostMessageEnvelope(
          protocolVersion: 1,
          sessionId: _runId.value,
          nonce: 'wrong-relay-nonce-000001',
          sequence: 1,
          payload: _hello().toJson(),
        ),
      ]) {
        final controller = ScenarioLabRelayController(
          binding: _binding,
          host: _RelayHost(
            descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
          ),
          target: _CommandTarget(),
        );
        await controller.open();

        controller.acceptFrameEnvelope(envelope);

        expect(controller.status, ScenarioLabRelayControllerStatus.failed);
        expect(
          controller.snapshot.failure,
          ScenarioLabRelayControllerFailure.protocolViolation,
        );
      }

      final poll = Completer<ScenarioLabRelayPollResponse>();
      final replayController = ScenarioLabRelayController(
        binding: _binding,
        host: _RelayHost(
          descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
          pendingPoll: poll,
        ),
        target: _CommandTarget(),
      );
      await replayController.open();
      replayController.acceptFrameEnvelope(
        _envelope(_hello().toJson(), sequence: 1),
      );
      await _waitFor(
        () =>
            replayController.status == ScenarioLabRelayControllerStatus.polling,
      );

      replayController.acceptFrameEnvelope(
        _envelope(_hello().toJson(), sequence: 1),
      );

      expect(replayController.status, ScenarioLabRelayControllerStatus.failed);
      expect(
        replayController.snapshot.failure,
        ScenarioLabRelayControllerFailure.protocolViolation,
      );
    },
  );

  test('rejects tampered frame result digest before Host submission', () async {
    final command = _readCommand();
    final host = _RelayHost(
      descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
      polls: <ScenarioLabRelayPollResponse>[_commandPoll(command)],
    );
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: host,
      target: _CommandTarget(),
    );
    await controller.open();
    controller.acceptFrameEnvelope(_envelope(_hello().toJson(), sequence: 1));
    await _waitFor(
      () =>
          controller.status == ScenarioLabRelayControllerStatus.awaitingResult,
    );
    final tampered = _readResult(command).toJson()
      ..['resultDigest'] = Digest.semantic(const <String, Object?>{
        'tampered': true,
      }).value;

    controller.acceptFrameEnvelope(_envelope(tampered, sequence: 2));

    expect(controller.status, ScenarioLabRelayControllerStatus.failed);
    expect(
      controller.snapshot.failure,
      ScenarioLabRelayControllerFailure.protocolViolation,
    );
    expect(host.resultSubmissions, isEmpty);
  });

  test(
    'validates descriptor, nonce, sequence and acknowledgement digests',
    () async {
      final wrongNonceCommand = ReadAppAdapterRelayCommand(
        runId: _runId,
        commandId: ScenarioLabCommandId('command-00000001'),
        sequence: 1,
        nonce: AppAdapterRelayNonce('wrong-relay-nonce-000001'),
        controlId: _controlId,
        capability: _capability,
        operationId: CapabilityOperationId('read'),
      );
      final host = _RelayHost(
        descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
        polls: <ScenarioLabRelayPollResponse>[_commandPoll(wrongNonceCommand)],
      );
      final target = _CommandTarget();
      final controller = ScenarioLabRelayController(
        binding: _binding,
        host: host,
        target: target,
      );
      await controller.open();
      controller.acceptFrameEnvelope(_envelope(_hello().toJson(), sequence: 1));
      await _waitFor(
        () => controller.status == ScenarioLabRelayControllerStatus.failed,
      );

      expect(
        controller.snapshot.failure,
        ScenarioLabRelayControllerFailure.protocolViolation,
      );
      expect(target.commands, isEmpty);

      final badAckHost = _RelayHost(
        descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
        acceptedHelloDigest: Digest.semantic(const <String, Object?>{
          'other': 'hello',
        }),
      );
      final badAckController = ScenarioLabRelayController(
        binding: _binding,
        host: badAckHost,
        target: _CommandTarget(),
      );
      await badAckController.open();
      badAckController.acceptFrameEnvelope(
        _envelope(_hello().toJson(), sequence: 1),
      );
      await _waitFor(
        () =>
            badAckController.status == ScenarioLabRelayControllerStatus.failed,
      );
      expect(
        badAckController.snapshot.failure,
        ScenarioLabRelayControllerFailure.protocolViolation,
      );
    },
  );

  test('cancellation invalidates a late long-poll command', () async {
    final poll = Completer<ScenarioLabRelayPollResponse>();
    final target = _CommandTarget();
    final host = _RelayHost(
      descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
      pendingPoll: poll,
    );
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: host,
      target: target,
    );
    await controller.open();
    controller.acceptFrameEnvelope(_envelope(_hello().toJson(), sequence: 1));
    await _waitFor(() => host.pollRequests.isNotEmpty);

    controller.cancel();
    poll.complete(_commandPoll(_readCommand()));
    await _flush();

    expect(controller.status, ScenarioLabRelayControllerStatus.cancelled);
    expect(controller.descriptor, isNull);
    expect(target.commands, isEmpty);
  });

  test('close invalidates a pending descriptor retry', () async {
    final retry = Completer<void>();
    final host = _RelayHost(
      descriptions: <ScenarioLabRelayDescription>[
        ScenarioLabRelayDescription(
          runId: _runId,
          status: ScenarioLabRelayDescriptionStatus.pending,
        ),
        _readyDescription(),
      ],
    );
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: host,
      target: _CommandTarget(),
      delay: (_) => retry.future,
    );
    final opening = controller.open();
    await _waitFor(
      () => controller.status == ScenarioLabRelayControllerStatus.pendingTarget,
    );

    controller.close();
    retry.complete();
    await opening;

    expect(controller.status, ScenarioLabRelayControllerStatus.closed);
    expect(controller.descriptor, isNull);
    expect(host.descriptionCalls, 1);
  });

  test('fails closed when the single target frame is detached', () async {
    final command = _readCommand();
    final host = _RelayHost(
      descriptions: <ScenarioLabRelayDescription>[_readyDescription()],
      polls: <ScenarioLabRelayPollResponse>[_commandPoll(command)],
    );
    final target = _CommandTarget(attached: false);
    final controller = ScenarioLabRelayController(
      binding: _binding,
      host: host,
      target: target,
    );
    await controller.open();
    controller.acceptFrameEnvelope(_envelope(_hello().toJson(), sequence: 1));
    await _waitFor(
      () => controller.status == ScenarioLabRelayControllerStatus.failed,
    );

    expect(
      controller.snapshot.failure,
      ScenarioLabRelayControllerFailure.targetDisconnected,
    );
    expect(target.commands, isEmpty);
  });
}

final _runId = ScenarioLabRunId('run-00000001');
final _fixture = ScenarioLabTestFixture();
final _binding = StudioLabRelayRunBinding.fromSnapshot(
  snapshot: _fixture.runningSnapshot(runId: _runId),
  catalog: _fixture.catalog,
  manifest: _fixture.manifest,
);
final _nonce = AppAdapterRelayNonce('relay-nonce-000000000001');
final _controlId = ScenarioControlId('ready-control');
final _capability = AppAdapterCapabilityReference(
  id: AppAdapterCapabilityId('sample.ready-control'),
  version: 1,
);

ScenarioLabRelayTargetDescriptor get _descriptor =>
    ScenarioLabRelayTargetDescriptor(
      runId: _runId,
      targetId: 'browser',
      launchProfileId: 'lab-web',
      launchAttemptId: TargetLaunchAttemptId('launch-attempt-0001'),
      origin: Uri.parse('http://127.0.0.1:8181'),
      nonce: _nonce,
    );

ScenarioLabRelayDescription _readyDescription() => ScenarioLabRelayDescription(
  runId: _runId,
  status: ScenarioLabRelayDescriptionStatus.ready,
  descriptor: _descriptor,
);

AppAdapterRelayHello _hello() => AppAdapterRelayHello(
  runId: _runId,
  adapterInstanceId: 'adapter-instance-0001',
  sequence: 0,
  nonce: _nonce,
  capabilities: <AppAdapterCapabilityReference>[_capability],
);

ReadAppAdapterRelayCommand _readCommand() => ReadAppAdapterRelayCommand(
  runId: _runId,
  commandId: ScenarioLabCommandId('command-00000001'),
  sequence: 1,
  nonce: _nonce,
  controlId: _controlId,
  capability: _capability,
  operationId: CapabilityOperationId('read'),
);

ReadAppAdapterRelayResult _readResult(ReadAppAdapterRelayCommand command) =>
    ReadAppAdapterRelayResult(
      runId: command.runId,
      commandId: command.commandId,
      sequence: command.sequence,
      nonce: command.nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(true),
    );

ScenarioLabRelayPollResponse _commandPoll(AppAdapterRelayCommand command) =>
    ScenarioLabRelayPollResponse(
      runId: _runId,
      descriptorDigest: _descriptor.digest,
      afterSequence: 0,
      state: ScenarioLabRelayPollState.command,
      command: command,
    );

ScenarioLabRelayPollResponse _closedPoll({required int afterSequence}) =>
    ScenarioLabRelayPollResponse(
      runId: _runId,
      descriptorDigest: _descriptor.digest,
      afterSequence: afterSequence,
      state: ScenarioLabRelayPollState.closed,
    );

PostMessageEnvelope _envelope(
  Map<String, Object?> payload, {
  required int sequence,
}) => PostMessageEnvelope(
  protocolVersion: 1,
  sessionId: _runId.value,
  nonce: _nonce.value,
  sequence: sequence,
  payload: payload,
);

final class _CommandTarget implements ScenarioLabRelayCommandTarget {
  _CommandTarget({this.attached = true});

  final bool attached;
  final List<AppAdapterRelayCommand> commands = <AppAdapterRelayCommand>[];

  @override
  bool get isAttached => attached;

  @override
  void sendCommand(AppAdapterRelayCommand command) {
    commands.add(command);
  }
}

final class _RelayHost implements StudioHostLabRelayClient {
  _RelayHost({
    required this.descriptions,
    this.polls = const <ScenarioLabRelayPollResponse>[],
    this.pendingPoll,
    this.acceptedHelloDigest,
  });

  final List<ScenarioLabRelayDescription> descriptions;
  final List<ScenarioLabRelayPollResponse> polls;
  final Completer<ScenarioLabRelayPollResponse>? pendingPoll;
  final Digest? acceptedHelloDigest;
  final List<ScenarioLabRelayHelloSubmission> helloSubmissions =
      <ScenarioLabRelayHelloSubmission>[];
  final List<ScenarioLabRelayPollRequest> pollRequests =
      <ScenarioLabRelayPollRequest>[];
  final List<ScenarioLabRelayResultSubmission> resultSubmissions =
      <ScenarioLabRelayResultSubmission>[];
  var _descriptionIndex = 0;
  var _pollIndex = 0;
  var descriptionCalls = 0;

  @override
  Future<StudioLabRelayDescription> describeLabRelay(
    StudioLabRelayRunBinding binding,
  ) async {
    descriptionCalls += 1;
    final description =
        descriptions[_descriptionIndex < descriptions.length - 1
            ? _descriptionIndex++
            : _descriptionIndex];
    return _decodeV1(description, binding);
  }

  @override
  Future<ScenarioLabRelayHelloAcknowledgement> submitLabRelayHello(
    ScenarioLabRelayHelloSubmission submission,
  ) async {
    helloSubmissions.add(submission);
    return ScenarioLabRelayHelloAcknowledgement(
      runId: _runId,
      descriptorDigest: _descriptor.digest,
      acceptedHelloDigest: acceptedHelloDigest ?? submission.hello.digest,
    );
  }

  @override
  Future<ScenarioLabRelayPollResponse> nextLabRelayCommand(
    ScenarioLabRelayPollRequest request,
  ) {
    pollRequests.add(request);
    final pending = pendingPoll;
    if (pending != null) return pending.future;
    return Future<ScenarioLabRelayPollResponse>.value(polls[_pollIndex++]);
  }

  @override
  Future<ScenarioLabRelayResultAcknowledgement> submitLabRelayResult(
    ScenarioLabRelayResultSubmission submission,
  ) async {
    resultSubmissions.add(submission);
    return ScenarioLabRelayResultAcknowledgement(
      runId: _runId,
      descriptorDigest: _descriptor.digest,
      acceptedResultDigest: submission.result.resultDigest,
    );
  }
}

final class _UnavailableRelayHost implements StudioHostLabRelayClient {
  @override
  Future<StudioLabRelayDescription> describeLabRelay(
    StudioLabRelayRunBinding binding,
  ) => throw const StudioLabRelayUnavailable();

  @override
  Future<ScenarioLabRelayPollResponse> nextLabRelayCommand(
    ScenarioLabRelayPollRequest request,
  ) => throw const StudioLabRelayUnavailable();

  @override
  Future<ScenarioLabRelayHelloAcknowledgement> submitLabRelayHello(
    ScenarioLabRelayHelloSubmission submission,
  ) => throw const StudioLabRelayUnavailable();

  @override
  Future<ScenarioLabRelayResultAcknowledgement> submitLabRelayResult(
    ScenarioLabRelayResultSubmission submission,
  ) => throw const StudioLabRelayUnavailable();
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var index = 0; index < 50; index += 1) {
    if (predicate()) return;
    await _flush();
  }
  fail('Timed out waiting for relay state');
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

StudioLabRelayDescription _decodeV1(
  ScenarioLabRelayDescription description,
  StudioLabRelayRunBinding binding,
) {
  final call = prepareStudioLabRelayDescribeCall(
    capabilities: studioLabRelayRpcMethods,
    binding: binding,
  );
  return decodeStudioLabRelayDescription(
    value: description.toJson(),
    call: call,
    binding: binding,
  );
}
