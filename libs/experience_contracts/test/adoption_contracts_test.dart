import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final manifest = AdoptionManifest(
    distributionId: 'full-local',
    files: <AdoptionFileRecord>[
      AdoptionFileRecord(
        path: 'workspace.yaml',
        role: 'consumer-config',
        contentDigest: Digest.bytes(utf8.encode('config')),
      ),
    ],
  );
  final report = AdoptionReport(
    distributionId: 'full-local',
    adopted: true,
    canApply: false,
    canDetach: true,
    manifestDigest: manifest.digest,
    files: <AdoptionFileObservation>[
      AdoptionFileObservation(
        path: 'workspace.yaml',
        role: 'consumer-config',
        state: AdoptionFileState.ownedUnmodified,
        expectedDigest: manifest.files.single.contentDigest,
        observedDigest: manifest.files.single.contentDigest,
      ),
    ],
  );

  test('manifest round-trips and emitted documents conform to schema', () {
    expect(
      AdoptionManifest.fromJson(manifest.toJson()).digest,
      manifest.digest,
    );
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'distribution',
                'adoption.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );
    expect(validator.validate(manifest.toJson()).isValid, isTrue);
    expect(validator.validate(report.toJson()).isValid, isTrue);
  });

  test('paths and manifest digests fail closed', () {
    expect(
      () => AdoptionFileRecord(
        path: '../pubspec.yaml',
        role: 'unsafe',
        contentDigest: Digest.semantic('x'),
      ),
      throwsFormatException,
    );
    final tampered = manifest.toJson()..['distributionId'] = 'other';
    expect(() => AdoptionManifest.fromJson(tampered), throwsFormatException);
  });
}

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
