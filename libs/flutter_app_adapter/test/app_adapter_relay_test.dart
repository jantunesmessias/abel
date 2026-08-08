import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:flutter_app_adapter/flutter_app_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AppAdapterRelay', () {
    test('announces and executes allowlisted read, write and reset', () async {
      var value = false;
      final control = _booleanControl(
        read: () => value,
        write: (next) => value = next,
        reset: () => value = false,
      );
      final relay = _relay(control: control);
      final capability = _capability(control);

      try {
        expect(relay.hello.adapterInstanceId, 'adapter-instance-1');
        expect(relay.hello.capabilities, hasLength(1));
        expect(relay.hello.capabilities.single.key, capability.key);

        final read = ReadAppAdapterRelayCommand(
          runId: relay.hello.runId,
          commandId: ScenarioLabCommandId('read-1'),
          sequence: 1,
          nonce: relay.hello.nonce,
          controlId: ScenarioControlId('ready-control'),
          capability: capability,
          operationId: CapabilityOperationId('read-enabled'),
        );
        final readResult = await relay.handle(
          jsonDecode(jsonEncode(read.toJson())),
        );
        expect(readResult, isA<ReadAppAdapterRelayResult>());
        expect((readResult as ReadAppAdapterRelayResult).value?.value, isFalse);

        final write = WriteAppAdapterRelayCommand(
          runId: relay.hello.runId,
          commandId: ScenarioLabCommandId('write-1'),
          sequence: 2,
          nonce: relay.hello.nonce,
          controlId: ScenarioControlId('ready-control'),
          capability: capability,
          operationId: CapabilityOperationId('write-enabled'),
          value: const BooleanScenarioControlValue(true),
        );
        final writeResult = await relay.execute(write);
        expect(writeResult.state, AppAdapterRelayResultState.succeeded);
        expect(value, isTrue);

        final reset = ResetAppAdapterRelayCommand(
          runId: relay.hello.runId,
          commandId: ScenarioLabCommandId('reset-1'),
          sequence: 3,
          nonce: relay.hello.nonce,
          controlId: ScenarioControlId('ready-control'),
          capability: capability,
          operationId: CapabilityOperationId('reset-enabled'),
        );
        final resetResult = await relay.execute(reset);
        expect(resetResult.state, AppAdapterRelayResultState.succeeded);
        expect(value, isFalse);
        expect(() => resetResult.validateAgainst(reset), returnsNormally);
      } finally {
        relay.dispose();
      }
    });

    test('rejects digest, nonce, sequence and capability violations', () async {
      var reads = 0;
      final control = _booleanControl(
        read: () {
          reads += 1;
          return false;
        },
        write: (_) {},
        reset: () {},
      );
      final relay = _relay(control: control);
      final capability = _capability(control);
      final valid = ReadAppAdapterRelayCommand(
        runId: relay.hello.runId,
        commandId: ScenarioLabCommandId('read-1'),
        sequence: 1,
        nonce: relay.hello.nonce,
        controlId: ScenarioControlId('ready-control'),
        capability: capability,
        operationId: CapabilityOperationId('read-enabled'),
      );

      try {
        final tampered = Map<String, Object?>.of(valid.toJson())
          ..['commandDigest'] = _digest('tampered').value;
        await expectLater(relay.handle(tampered), throwsFormatException);

        final wrongNonce = ReadAppAdapterRelayCommand(
          runId: valid.runId,
          commandId: valid.commandId,
          sequence: valid.sequence,
          nonce: AppAdapterRelayNonce('different_nonce_value_1234'),
          controlId: valid.controlId,
          capability: capability,
          operationId: valid.operationId,
        );
        expect(
          (await relay.execute(wrongNonce)).failure?.cause,
          AppAdapterRelayFailureCause.rejected,
        );

        final skipped = ReadAppAdapterRelayCommand(
          runId: valid.runId,
          commandId: ScenarioLabCommandId('read-skipped'),
          sequence: 2,
          nonce: valid.nonce,
          controlId: valid.controlId,
          capability: capability,
          operationId: valid.operationId,
        );
        expect(
          (await relay.execute(skipped)).failure?.cause,
          AppAdapterRelayFailureCause.rejected,
        );

        final misrouted = ReadAppAdapterRelayCommand(
          runId: valid.runId,
          commandId: ScenarioLabCommandId('read-misrouted'),
          sequence: 1,
          nonce: valid.nonce,
          controlId: valid.controlId,
          capability: capability,
          operationId: CapabilityOperationId('write-enabled'),
        );
        expect(
          (await relay.execute(misrouted)).failure?.cause,
          AppAdapterRelayFailureCause.unsupported,
        );

        final unavailable = ReadAppAdapterRelayCommand(
          runId: valid.runId,
          commandId: ScenarioLabCommandId('read-unavailable'),
          sequence: 2,
          nonce: valid.nonce,
          controlId: valid.controlId,
          capability: AppAdapterCapabilityReference(
            id: AppAdapterCapabilityId('unavailable-control'),
            version: 1,
          ),
          operationId: valid.operationId,
        );
        expect(
          (await relay.execute(unavailable)).failure?.cause,
          AppAdapterRelayFailureCause.unsupported,
        );
        expect(reads, 0);
      } finally {
        relay.dispose();
      }
    });

    test(
      'deduplicates identical control commands and rejects conflicts',
      () async {
        var value = false;
        var writes = 0;
        final control = _booleanControl(
          read: () => value,
          write: (next) {
            writes += 1;
            value = next;
          },
          reset: () => value = false,
        );
        final relay = _relay(control: control);
        final command = WriteAppAdapterRelayCommand(
          runId: relay.hello.runId,
          commandId: ScenarioLabCommandId('write-1'),
          sequence: 1,
          nonce: relay.hello.nonce,
          controlId: ScenarioControlId('ready-control'),
          capability: _capability(control),
          operationId: CapabilityOperationId('write-enabled'),
          value: const BooleanScenarioControlValue(true),
        );

        try {
          final first = await relay.execute(command);
          final retry = await relay.handle(
            jsonDecode(jsonEncode(command.toJson())),
          );
          expect(retry.resultDigest, first.resultDigest);
          expect(writes, 1);

          final conflict = WriteAppAdapterRelayCommand(
            runId: command.runId,
            commandId: command.commandId,
            sequence: command.sequence,
            nonce: command.nonce,
            controlId: command.controlId,
            capability: command.capability,
            operationId: command.operationId,
            value: const BooleanScenarioControlValue(false),
          );
          final rejected = await relay.execute(conflict);
          expect(rejected.failure?.cause, AppAdapterRelayFailureCause.rejected);
          expect(writes, 1);
          expect(value, isTrue);
        } finally {
          relay.dispose();
        }
      },
    );

    test('reuploads cached PNG bytes through a renewed grant', () async {
      final bodies = <List<int>>[];
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        bodies.add(List<int>.of(request.bodyBytes));
        expect(request.method, 'PUT');
        expect(request.headers['content-type'], 'image/png');
        return http.Response('', 201);
      });
      var captures = 0;
      final adapter = AppAdapter(
        capabilities: const <AppCapability>[],
        captureHandler: (_) {
          captures += 1;
          return <int>[137, 80, 78, 71, captures];
        },
      );
      final now = DateTime.utc(2026, 8, 14, 12);
      final uploader = AppAdapterCaptureUploader(
        client: client,
        nowUtc: () => now,
      );
      final relay = _relay(adapter: adapter, captureUploader: uploader);
      final first = _captureCommand(
        relay,
        requestId: 'capture01',
        token: 'upload_token_1234',
        expiresAt: now.add(const Duration(minutes: 1)),
      );

      try {
        final firstResult =
            await relay.execute(first) as CaptureAppAdapterRelayResult;
        expect(firstResult.state, AppAdapterRelayResultState.succeeded);
        expect(firstResult.uploadRequestId, 'capture01');
        expect(firstResult.toJson(), isNot(contains('evidenceDigest')));

        final exactRetry =
            await relay.execute(first) as CaptureAppAdapterRelayResult;
        expect(exactRetry.resultDigest, firstResult.resultDigest);
        expect(captures, 1);
        expect(requests, hasLength(1));

        final renewed = _captureCommand(
          relay,
          requestId: 'capture02',
          token: 'renewed_token_1234',
          expiresAt: now.add(const Duration(minutes: 2)),
        );
        expect(renewed.commandDigest, first.commandDigest);
        final renewedResult =
            await relay.execute(renewed) as CaptureAppAdapterRelayResult;
        expect(renewedResult.state, AppAdapterRelayResultState.succeeded);
        expect(renewedResult.uploadRequestId, 'capture02');
        expect(captures, 1);
        expect(requests, hasLength(2));
        expect(bodies[1], bodies[0]);
      } finally {
        relay.dispose();
        client.close();
      }
    });
  });
}

BooleanControlCapability _booleanControl({
  required bool Function() read,
  required void Function(bool) write,
  required void Function() reset,
}) => BooleanControlCapability(
  id: 'sample.ready-control',
  readOperation: 'read-enabled',
  writeOperation: 'write-enabled',
  resetOperation: 'reset-enabled',
  read: read,
  write: write,
  reset: reset,
);

AppAdapterCapabilityReference _capability(BooleanControlCapability control) =>
    AppAdapterCapabilityReference(
      id: AppAdapterCapabilityId(control.descriptor.id),
      version: control.descriptor.version,
    );

AppAdapterRelay _relay({
  BooleanControlCapability? control,
  AppAdapter? adapter,
  AppAdapterCaptureUploader? captureUploader,
}) {
  final actualAdapter =
      adapter ??
      AppAdapter(
        capabilities: <AppCapability>[?control],
        captureHandler: (_) => const <int>[],
      );
  return AppAdapterRelay(
    adapter: actualAdapter,
    sessionId: 'session01',
    configuration: AppAdapterRelayConfiguration(
      runId: ScenarioLabRunId('run-1'),
      adapterInstanceId: 'adapter-instance-1',
      nonce: AppAdapterRelayNonce('relay_nonce_value_123456'),
      evidenceProviderIds: <ModuleId>[ModuleId('capture.web')],
    ),
    captureUploader: captureUploader,
  );
}

CaptureAppAdapterRelayCommand _captureCommand(
  AppAdapterRelay relay, {
  required String requestId,
  required String token,
  required DateTime expiresAt,
}) => CaptureAppAdapterRelayCommand(
  runId: relay.hello.runId,
  commandId: ScenarioLabCommandId('capture-1'),
  sequence: 1,
  nonce: relay.hello.nonce,
  requiredEvidenceId: RequiredEvidenceId('ready-visual'),
  providerId: ModuleId('capture.web'),
  uploadGrant: AppAdapterRelayCaptureUploadGrant(
    requestId: requestId,
    sessionId: relay.sessionId,
    uploadUri: Uri.parse(
      'http://127.0.0.1:7367/capture-uploads/$requestId?token=$token',
    ),
    expiresAt: expiresAt,
    maxBytes: 8 * 1024 * 1024,
  ),
);

Digest _digest(String seed) => Digest.bytes(utf8.encode(seed));
