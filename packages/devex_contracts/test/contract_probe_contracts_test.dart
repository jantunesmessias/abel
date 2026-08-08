import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('ContractProbePlan is closed, canonical and schema conformant', () {
    final plan = _plan();

    expect(ContractProbePlan.fromJson(plan.toJson()).digest, plan.digest);
    expect(plan.orderedSteps.map((step) => step.routeId.value), <String>[
      'session',
      'details',
    ]);
    final schema = jsonDecode(
      File(
        p.join(
          _repositoryRoot(),
          'schemas',
          'v1',
          'contract-probe-plan.schema.json',
        ),
      ).readAsStringSync(),
    );
    final result = Draft202012Validator(
      schema as Object,
    ).validate(plan.toJson());
    expect(result.isValid, isTrue, reason: '${result.issues}');
  });

  test('cycle, free extraction and public CAS responses fail closed', () {
    final session = GatewayRouteId('session');
    final details = GatewayRouteId('details');
    expect(
      () => ContractProbePlan(
        id: 'cycle',
        presetId: GatewayPresetId('default'),
        steps: <ContractProbeStep>[
          ContractProbeStep(
            routeId: session,
            order: 0,
            after: <GatewayRouteId>{details},
            extract: const <String, ProbeExtraction>{},
          ),
          ContractProbeStep(
            routeId: details,
            order: 1,
            after: <GatewayRouteId>{session},
            extract: const <String, ProbeExtraction>{},
          ),
        ],
        parameterDefaults: const <String, String>{},
      ),
      throwsArgumentError,
    );
    expect(
      () => ContractProbeStep(
        routeId: details,
        order: 1,
        after: const <GatewayRouteId>{},
        extract: <String, ProbeExtraction>{
          'id': ProbeExtraction(fromRouteId: session, paths: <String>['/id']),
        },
      ),
      throwsArgumentError,
    );
    expect(
      () => ContractProbePlan(
        id: 'public-cas',
        presetId: GatewayPresetId('default'),
        steps: <ContractProbeStep>[
          ContractProbeStep(
            routeId: session,
            order: 0,
            after: const <GatewayRouteId>{},
            extract: const <String, ProbeExtraction>{},
          ),
        ],
        parameterDefaults: const <String, String>{},
        artifactRetention: ProbeArtifactRetention.cas,
        artifactClassification: ArtifactClassification.public,
      ),
      throwsArgumentError,
    );
  });
}

ContractProbePlan _plan() {
  final session = GatewayRouteId('session');
  final details = GatewayRouteId('details');
  return ContractProbePlan(
    id: 'account-chain',
    presetId: GatewayPresetId('default'),
    steps: <ContractProbeStep>[
      ContractProbeStep(
        routeId: details,
        order: 0,
        after: <GatewayRouteId>{session},
        extract: <String, ProbeExtraction>{
          'account_id': ProbeExtraction(
            fromRouteId: session,
            paths: <String>['/data/id', '/id'],
          ),
        },
      ),
      ContractProbeStep(
        routeId: session,
        order: 10,
        after: const <GatewayRouteId>{},
        extract: const <String, ProbeExtraction>{},
      ),
    ],
    parameterDefaults: const <String, String>{},
    artifactRetention: ProbeArtifactRetention.cas,
    artifactClassification: ArtifactClassification.sensitive,
  );
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return current.path;
    }
    current = current.parent;
  }
  throw StateError('Repository root not found');
}
