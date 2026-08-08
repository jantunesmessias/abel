import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('test evidence summary round-trips and conforms to its schema', () {
    final report = Artifact(
      digest: Digest.semantic('report'),
      size: 20,
      mediaType: 'application/json',
      classification: ArtifactClassification.internal,
      role: 'dart-test-report',
    );
    final summary = TestEvidenceSummary(
      providerId: 'dart-test-json-v1',
      runnerProtocolVersion: '0.1.1',
      runnerVersion: '1.31.0',
      success: true,
      total: 2,
      passed: 1,
      failed: 0,
      skipped: 1,
      durationMilliseconds: 12,
      platforms: const <String>{'vm'},
      reportArtifact: report,
      referencedArtifacts: const <Artifact>[],
    );
    expect(
      TestEvidenceSummary.fromJson(summary.toJson()).digest,
      summary.digest,
    );
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'evidence',
                'test-evidence-summary.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );
    final result = validator.validate(summary.toJson());
    expect(result.isValid, isTrue, reason: '${result.issues}');
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
