import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Scenario Lab relay RPC contracts', () {
    test('round-trips descriptor, descriptions and request/response flow', () {
      final descriptor = _descriptor();
      expect(
        ScenarioLabRelayTargetDescriptor.fromJson(descriptor.toJson()).toJson(),
        descriptor.toJson(),
      );

      for (final description in <ScenarioLabRelayDescription>[
        ScenarioLabRelayDescription(
          runId: _runId,
          status: ScenarioLabRelayDescriptionStatus.pending,
        ),
        ScenarioLabRelayDescription(
          runId: _runId,
          status: ScenarioLabRelayDescriptionStatus.ready,
          descriptor: descriptor,
        ),
        ScenarioLabRelayDescription(
          runId: _runId,
          status: ScenarioLabRelayDescriptionStatus.closed,
        ),
      ]) {
        expect(
          ScenarioLabRelayDescription.fromJson(description.toJson()).toJson(),
          description.toJson(),
        );
      }

      final hello = _hello();
      final helloSubmission = ScenarioLabRelayHelloSubmission(
        descriptorDigest: descriptor.digest,
        hello: hello,
      );
      helloSubmission.validateAgainst(descriptor);
      expect(
        ScenarioLabRelayHelloSubmission.fromJson(
          helloSubmission.toJson(),
        ).toJson(),
        helloSubmission.toJson(),
      );
      final helloAck = ScenarioLabRelayHelloAcknowledgement(
        runId: _runId,
        descriptorDigest: descriptor.digest,
        acceptedHelloDigest: hello.digest,
      );
      expect(
        ScenarioLabRelayHelloAcknowledgement.fromJson(
          helloAck.toJson(),
        ).toJson(),
        helloAck.toJson(),
      );

      final request = ScenarioLabRelayPollRequest(
        runId: _runId,
        descriptorDigest: descriptor.digest,
        afterSequence: 0,
        waitMs: 25000,
      );
      expect(
        ScenarioLabRelayPollRequest.fromJson(request.toJson()).toJson(),
        request.toJson(),
      );
      final command = _command();
      for (final response in <ScenarioLabRelayPollResponse>[
        ScenarioLabRelayPollResponse(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          state: ScenarioLabRelayPollState.command,
          command: command,
        ),
        ScenarioLabRelayPollResponse(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 1,
          state: ScenarioLabRelayPollState.idle,
        ),
        ScenarioLabRelayPollResponse(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 1,
          state: ScenarioLabRelayPollState.closed,
        ),
      ]) {
        expect(
          ScenarioLabRelayPollResponse.fromJson(response.toJson()).toJson(),
          response.toJson(),
        );
      }

      final result = _result(command);
      final resultSubmission = ScenarioLabRelayResultSubmission(
        descriptorDigest: descriptor.digest,
        result: result,
      );
      expect(
        ScenarioLabRelayResultSubmission.fromJson(
          resultSubmission.toJson(),
        ).toJson(),
        resultSubmission.toJson(),
      );
      final resultAck = ScenarioLabRelayResultAcknowledgement(
        runId: _runId,
        descriptorDigest: descriptor.digest,
        acceptedResultDigest: result.resultDigest,
      );
      expect(
        ScenarioLabRelayResultAcknowledgement.fromJson(
          resultAck.toJson(),
        ).toJson(),
        resultAck.toJson(),
      );
    });

    test('fails closed for target, fencing, optional and sequence errors', () {
      final descriptor = _descriptor();
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
      expect(
        () => ScenarioLabRelayDescription(
          runId: _runId,
          status: ScenarioLabRelayDescriptionStatus.pending,
          descriptor: descriptor,
        ),
        throwsArgumentError,
      );
      expect(
        () => ScenarioLabRelayPollResponse(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 1,
          state: ScenarioLabRelayPollState.command,
          command: _command(),
        ),
        throwsArgumentError,
      );

      final wrongDescriptor = ScenarioLabRelayTargetDescriptor(
        runId: _runId,
        targetId: 'another-target',
        launchProfileId: 'sample-web',
        launchAttemptId: TargetLaunchAttemptId('launch-attempt-2'),
        origin: Uri.parse('http://127.0.0.1:8182'),
        nonce: _nonce,
      );
      final submission = ScenarioLabRelayHelloSubmission(
        descriptorDigest: descriptor.digest,
        hello: _hello(),
      );
      expect(
        () => submission.validateAgainst(wrongDescriptor),
        throwsArgumentError,
      );

      final unknown = <String, Object?>{
        ...ScenarioLabRelayDescription(
          runId: _runId,
          status: ScenarioLabRelayDescriptionStatus.pending,
        ).toJson(),
        'extra': true,
      };
      expect(
        () => ScenarioLabRelayDescription.fromJson(unknown),
        throwsFormatException,
      );
      final tampered = ScenarioLabRelayPollRequest(
        runId: _runId,
        descriptorDigest: descriptor.digest,
        afterSequence: 0,
        waitMs: 0,
      ).toJson()..['waitMs'] = 1;
      expect(
        () => ScenarioLabRelayPollRequest.fromJson(tampered),
        throwsFormatException,
      );
    });

    test('all RPC documents conform to the closed public schema', () {
      final descriptor = _descriptor();
      final hello = _hello();
      final command = _command();
      final result = _result(command);
      final documents = <Map<String, Object?>>[
        descriptor.toJson(),
        ScenarioLabRelayDescription(
          runId: _runId,
          status: ScenarioLabRelayDescriptionStatus.ready,
          descriptor: descriptor,
        ).toJson(),
        ScenarioLabRelayHelloSubmission(
          descriptorDigest: descriptor.digest,
          hello: hello,
        ).toJson(),
        ScenarioLabRelayHelloAcknowledgement(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          acceptedHelloDigest: hello.digest,
        ).toJson(),
        ScenarioLabRelayPollRequest(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          waitMs: 25000,
        ).toJson(),
        ScenarioLabRelayPollResponse(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          afterSequence: 0,
          state: ScenarioLabRelayPollState.command,
          command: command,
        ).toJson(),
        ScenarioLabRelayResultSubmission(
          descriptorDigest: descriptor.digest,
          result: result,
        ).toJson(),
        ScenarioLabRelayResultAcknowledgement(
          runId: _runId,
          descriptorDigest: descriptor.digest,
          acceptedResultDigest: result.resultDigest,
        ).toJson(),
      ];
      final validator = Draft202012Validator(
        jsonDecode(
              File(
                p.join(
                  _repositoryRoot(),
                  'schemas',
                  'runtime',
                  'scenario-lab-relay.schema.json',
                ),
              ).readAsStringSync(),
            )
            as Object,
      );
      for (final document in documents) {
        final validation = validator.validate(document);
        expect(
          validation.isValid,
          isTrue,
          reason: '${document['kind']}: ${validation.issues.join('\n')}',
        );
      }
    });
  });
}

final _runId = ScenarioLabRunId('run-00000001');
final _nonce = AppAdapterRelayNonce('relay-nonce-000000000001');
final _capability = AppAdapterCapabilityReference(
  id: AppAdapterCapabilityId('sample.ready-control'),
  version: 1,
);

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

ReadAppAdapterRelayCommand _command() => ReadAppAdapterRelayCommand(
  runId: _runId,
  commandId: ScenarioLabCommandId('command-00000001'),
  sequence: 1,
  nonce: _nonce,
  controlId: ScenarioControlId('ready-control'),
  capability: _capability,
  operationId: CapabilityOperationId('read'),
);

ReadAppAdapterRelayResult _result(ReadAppAdapterRelayCommand command) =>
    ReadAppAdapterRelayResult(
      runId: command.runId,
      commandId: command.commandId,
      sequence: command.sequence,
      nonce: command.nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(true),
    );

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
