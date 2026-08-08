import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Scenario Lab relay describe v2', () {
    test('request is the exact closed RPC parameter pair', () {
      final request = _request();
      expect(request.toJson(), <String, Object?>{
        'runId': _runId.value,
        'expectedStartRequestDigest': _startRequestDigest.value,
      });
      expect(
        ScenarioLabRelayDescribeRequestV2.fromJson(request.toJson()).toJson(),
        request.toJson(),
      );
      expect(
        () => ScenarioLabRelayDescribeRequestV2.fromJson(<String, Object?>{
          ...request.toJson(),
          'origin': 'http://127.0.0.1:1',
        }),
        throwsFormatException,
      );
    });

    test('round-trips pending, closed and direct ready descriptions', () {
      for (final description in <ScenarioLabRelayDescriptionV2>[
        _description(ScenarioLabRelayDescriptionStatus.pending),
        _description(ScenarioLabRelayDescriptionStatus.closed),
        _description(
          ScenarioLabRelayDescriptionStatus.ready,
          descriptor: _descriptor(),
          runtimeInputs: _runtimeInputs(),
        ),
      ]) {
        final decoded = ScenarioLabRelayDescriptionV2.fromJson(
          description.toJson(),
        );
        decoded.validateAgainst(_request());
        expect(decoded.toJson(), description.toJson());
        expect(decoded.requiresGateway, isFalse);
      }
    });

    test('binds exact v1 descriptor, runtime inputs and Gateway origin', () {
      final descriptor = _descriptor();
      final runtimeInputs = _runtimeInputs(gateway: true);
      final description = _description(
        ScenarioLabRelayDescriptionStatus.ready,
        descriptor: descriptor,
        runtimeInputs: runtimeInputs,
        gatewayDataOrigin: Uri.parse('http://localhost:9393/'),
      );

      expect(description.descriptor!.toJson(), descriptor.toJson());
      expect(description.runtimeInputs!.toJson(), runtimeInputs.toJson());
      expect(description.gatewayDataOrigin.toString(), 'http://localhost:9393');
      expect(description.requiresGateway, isTrue);
      final decoded = ScenarioLabRelayDescriptionV2.fromJson(
        description.toJson(),
      );
      expect(decoded.toJson(), description.toJson());
      expect(decoded.digest, description.digest);
    });

    test('fails closed for incomplete ready state and downgrade shapes', () {
      final descriptor = _descriptor();
      final direct = _runtimeInputs();
      final gateway = _runtimeInputs(gateway: true);
      expect(
        () => _description(
          ScenarioLabRelayDescriptionStatus.pending,
          descriptor: descriptor,
          runtimeInputs: direct,
        ),
        throwsArgumentError,
      );
      expect(
        () => _description(
          ScenarioLabRelayDescriptionStatus.ready,
          descriptor: descriptor,
        ),
        throwsArgumentError,
      );
      expect(
        () => _description(
          ScenarioLabRelayDescriptionStatus.ready,
          descriptor: descriptor,
          runtimeInputs: gateway,
        ),
        throwsArgumentError,
      );
      expect(
        () => _description(
          ScenarioLabRelayDescriptionStatus.ready,
          descriptor: descriptor,
          runtimeInputs: direct,
          gatewayDataOrigin: Uri.parse('http://127.0.0.1:9393'),
        ),
        throwsArgumentError,
      );
      expect(
        () => _description(
          ScenarioLabRelayDescriptionStatus.ready,
          descriptor: ScenarioLabRelayTargetDescriptor(
            runId: _runId,
            targetId: 'another-target',
            launchProfileId: 'sample-web',
            launchAttemptId: TargetLaunchAttemptId('launch-attempt-00000001'),
            origin: Uri.parse('http://127.0.0.1:8181'),
            nonce: _nonce,
          ),
          runtimeInputs: direct,
        ),
        throwsArgumentError,
      );
    });

    test('rejects unsafe Gateway origins and any semantic tampering', () {
      final invalidOrigins = <String>[
        'https://127.0.0.1:9393',
        'http://example.com:9393',
        'http://user@127.0.0.1:9393',
        'http://127.0.0.1:9393?token=secret',
        'http://127.0.0.1:9393#fragment',
        'http://127.0.0.1:9393/data',
        'http://127.0.0.1',
        'http://127.0.0.1:65536',
      ];
      for (final origin in invalidOrigins) {
        expect(
          () => _description(
            ScenarioLabRelayDescriptionStatus.ready,
            descriptor: _descriptor(),
            runtimeInputs: _runtimeInputs(gateway: true),
            gatewayDataOrigin: Uri.parse(origin),
          ),
          throwsFormatException,
          reason: origin,
        );
      }

      final description = _description(
        ScenarioLabRelayDescriptionStatus.ready,
        descriptor: _descriptor(),
        runtimeInputs: _runtimeInputs(gateway: true),
        gatewayDataOrigin: Uri.parse('http://127.0.0.1:9393'),
      );
      final tampered = description.toJson()
        ..['gatewayDataOrigin'] = 'http://127.0.0.1:9494';
      expect(
        () => ScenarioLabRelayDescriptionV2.fromJson(tampered),
        throwsFormatException,
      );
      expect(
        () => description.validateAgainst(
          ScenarioLabRelayDescribeRequestV2(
            runId: _runId,
            expectedStartRequestDigest: Digest.semantic('another-start'),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('request and every response state conform to the v2 schema', () {
      final validator = _schemaValidator();
      final documents = <Map<String, Object?>>[
        _request().toJson(),
        _description(ScenarioLabRelayDescriptionStatus.pending).toJson(),
        _description(ScenarioLabRelayDescriptionStatus.closed).toJson(),
        _description(
          ScenarioLabRelayDescriptionStatus.ready,
          descriptor: _descriptor(),
          runtimeInputs: _runtimeInputs(),
        ).toJson(),
        _description(
          ScenarioLabRelayDescriptionStatus.ready,
          descriptor: _descriptor(),
          runtimeInputs: _runtimeInputs(gateway: true),
          gatewayDataOrigin: Uri.parse('http://[::1]:9393'),
        ).toJson(),
      ];
      for (final document in documents) {
        final result = validator.validate(document);
        expect(
          result.isValid,
          isTrue,
          reason: '${document['status'] ?? 'request'}: ${result.issues}',
        );
      }
      final downgraded = _description(
        ScenarioLabRelayDescriptionStatus.ready,
        descriptor: _descriptor(),
        runtimeInputs: _runtimeInputs(gateway: true),
        gatewayDataOrigin: Uri.parse('http://127.0.0.1:9393'),
      ).toJson()..remove('gatewayDataOrigin');
      expect(validator.validate(downgraded).isValid, isFalse);
      final invalidPort = _description(
        ScenarioLabRelayDescriptionStatus.ready,
        descriptor: _descriptor(),
        runtimeInputs: _runtimeInputs(gateway: true),
        gatewayDataOrigin: Uri.parse('http://127.0.0.1:9393'),
      ).toJson()..['gatewayDataOrigin'] = 'http://127.0.0.1:65536';
      expect(validator.validate(invalidPort).isValid, isFalse);
    });
  });
}

final ScenarioLabRunId _runId = ScenarioLabRunId('run-00000001');
final Digest _startRequestDigest = Digest.semantic('start-request');
final AppAdapterRelayNonce _nonce = AppAdapterRelayNonce(
  'relay-nonce-000000000001',
);

ScenarioLabRelayDescribeRequestV2 _request() =>
    ScenarioLabRelayDescribeRequestV2(
      runId: _runId,
      expectedStartRequestDigest: _startRequestDigest,
    );

ScenarioLabRelayDescriptionV2 _description(
  ScenarioLabRelayDescriptionStatus status, {
  ScenarioLabRelayTargetDescriptor? descriptor,
  ScenarioLabRuntimeInputBinding? runtimeInputs,
  Uri? gatewayDataOrigin,
}) => ScenarioLabRelayDescriptionV2(
  runId: _runId,
  startRequestDigest: _startRequestDigest,
  status: status,
  descriptor: descriptor,
  runtimeInputs: runtimeInputs,
  gatewayDataOrigin: gatewayDataOrigin,
);

ScenarioLabRelayTargetDescriptor _descriptor() =>
    ScenarioLabRelayTargetDescriptor(
      runId: _runId,
      targetId: 'sample-target',
      launchProfileId: 'sample-web',
      launchAttemptId: TargetLaunchAttemptId('launch-attempt-00000001'),
      origin: Uri.parse('http://127.0.0.1:8181'),
      nonce: _nonce,
    );

ScenarioLabRuntimeInputBinding _runtimeInputs({bool gateway = false}) =>
    ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest: Digest.semantic('fingerprint'),
      executionTargetId: 'sample-target',
      gatewayPresetId: gateway ? GatewayPresetId('delivery-ready') : null,
      compiledGatewayPlanDigest: gateway ? Digest.semantic('plan') : null,
      routingTableDigest: gateway ? Digest.semantic('routes') : null,
    );

Draft202012Validator _schemaValidator() => Draft202012Validator(
  jsonDecode(
        File(
          p.join(
            _repositoryRoot(),
            'schemas',
            'runtime',
            'scenario-lab-relay-description.schema.json',
          ),
        ).readAsStringSync(),
      )
      as Object,
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
