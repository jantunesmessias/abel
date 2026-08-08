import 'package:execution_runtime/src/lab/scenario_lab_relay_broker.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'brokers one hello and one command without broadcasting payloads',
    () async {
      final broker = ScenarioLabRelayBroker();
      final descriptor = _descriptor();
      broker.open(descriptor);

      final helloFuture = broker.waitForHello(descriptor.runId);
      final hello = _hello();
      expect(broker.acceptHello(hello).digest, hello.digest);
      expect((await helloFuture).digest, hello.digest);

      final poll = broker.nextCommand(descriptor.runId, afterSequence: 0);
      final command = _read(sequence: 1);
      final resultFuture = broker.dispatch(command);
      expect((await poll)!.commandDigest, command.commandDigest);
      expect(
        (await broker.nextCommand(
          descriptor.runId,
          afterSequence: 0,
          wait: Duration.zero,
        ))!.commandDigest,
        command.commandDigest,
      );

      final result = _readResult(
        command,
        const BooleanScenarioControlValue(true),
      );
      expect(broker.acceptResult(result).resultDigest, result.resultDigest);
      expect((await resultFuture).resultDigest, result.resultDigest);
      expect(broker.acceptResult(result).resultDigest, result.resultDigest);
      expect(
        await broker.nextCommand(
          descriptor.runId,
          afterSequence: 1,
          wait: Duration.zero,
        ),
        isNull,
      );
    },
  );

  test(
    'fails closed for wrong hello, command reuse and mismatched result',
    () async {
      final broker = ScenarioLabRelayBroker()..open(_descriptor());
      expect(
        () => broker.acceptHello(
          AppAdapterRelayHello(
            runId: _runId,
            adapterInstanceId: 'adapter-instance-1',
            sequence: 0,
            nonce: AppAdapterRelayNonce('wrong-nonce-000000000001'),
            capabilities: <AppAdapterCapabilityReference>[_capability],
          ),
        ),
        throwsArgumentError,
      );
      broker.acceptHello(_hello());
      expect(broker.acceptHello(_hello()).digest, _hello().digest);
      expect(
        () => broker.acceptHello(
          AppAdapterRelayHello(
            runId: _runId,
            adapterInstanceId: 'adapter-instance-2',
            sequence: 0,
            nonce: _nonce,
            capabilities: <AppAdapterCapabilityReference>[_capability],
          ),
        ),
        throwsStateError,
      );

      final first = _read(sequence: 1);
      final firstFuture = broker.dispatch(first);
      final wrong = _readResult(
        _read(sequence: 2),
        const BooleanScenarioControlValue(true),
      );
      expect(() => broker.acceptResult(wrong), throwsStateError);
      final firstResult = _readResult(
        first,
        const BooleanScenarioControlValue(false),
      );
      broker.acceptResult(firstResult);
      expect((await firstFuture).resultDigest, firstResult.resultDigest);
      expect(
        () => broker.nextCommand(_runId, afterSequence: 0, wait: Duration.zero),
        throwsStateError,
      );

      final reused = ReadAppAdapterRelayCommand(
        runId: _runId,
        commandId: first.commandId,
        sequence: 2,
        nonce: _nonce,
        controlId: _controlId,
        capability: _capability,
        operationId: CapabilityOperationId('read'),
      );
      expect(() => broker.dispatch(reused), throwsStateError);
    },
  );

  test('closing releases hello, command and long-poll waiters', () async {
    final broker = ScenarioLabRelayBroker();
    broker.open(_descriptor());
    final hello = broker.waitForHello(_runId);
    final poll = broker.nextCommand(_runId, afterSequence: 0);
    broker.close(_runId);

    await expectLater(hello, throwsA(isA<ScenarioLabRelayClosed>()));
    expect(await poll, isNull);
    expect(broker.activeCount, 0);
    expect(() => broker.describe(_runId), returnsNormally);
    expect(broker.describe(_runId), isNull);
  });

  test('descriptor accepts only canonical loopback origins', () {
    expect(
      _descriptor().toJson(),
      containsPair('digest', startsWith('sha256:')),
    );
    expect(
      () => ScenarioLabRelayTargetDescriptor(
        runId: _runId,
        targetId: 'sample-target',
        launchProfileId: 'sample-web',
        launchAttemptId: TargetLaunchAttemptId('launch-attempt-1'),
        origin: Uri.parse('https://example.com:443'),
        nonce: _nonce,
      ),
      throwsFormatException,
    );
  });
}

final _runId = ScenarioLabRunId('run-00000001');
final _controlId = ScenarioControlId('ready-control');
final _capability = AppAdapterCapabilityReference(
  id: AppAdapterCapabilityId('sample.ready-control'),
  version: 1,
);
final _nonce = AppAdapterRelayNonce('relay-nonce-000000000001');

ScenarioLabRelayTargetDescriptor _descriptor() =>
    ScenarioLabRelayTargetDescriptor(
      runId: _runId,
      targetId: 'sample-target',
      launchProfileId: 'sample-web',
      launchAttemptId: TargetLaunchAttemptId('launch-attempt-1'),
      origin: Uri.parse('http://127.0.0.1:8181'),
      nonce: _nonce,
    );

AppAdapterRelayHello _hello() => AppAdapterRelayHello(
  runId: _runId,
  adapterInstanceId: 'adapter-instance-1',
  sequence: 0,
  nonce: _nonce,
  capabilities: <AppAdapterCapabilityReference>[_capability],
);

ReadAppAdapterRelayCommand _read({required int sequence}) =>
    ReadAppAdapterRelayCommand(
      runId: _runId,
      commandId: ScenarioLabCommandId('command-0000000$sequence'),
      sequence: sequence,
      nonce: _nonce,
      controlId: _controlId,
      capability: _capability,
      operationId: CapabilityOperationId('read'),
    );

ReadAppAdapterRelayResult _readResult(
  ReadAppAdapterRelayCommand command,
  ScenarioControlValue value,
) => ReadAppAdapterRelayResult(
  runId: command.runId,
  commandId: command.commandId,
  sequence: command.sequence,
  nonce: command.nonce,
  state: AppAdapterRelayResultState.succeeded,
  value: value,
);
