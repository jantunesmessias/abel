import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final catalogDigest = Digest.semantic(<String, Object?>{'catalog': 1});
  final distributionDigest = Digest.semantic(<String, Object?>{
    'distribution': 1,
  });
  final pixelDigest = Digest.bytes(const <int>[1, 2, 3, 255]);

  ExecutionFingerprint fingerprint({Digest? subject}) => ExecutionFingerprint(
    catalogDigest: subject ?? catalogDigest,
    launchProfileId: 'sample-web',
    targetId: 'local-chrome',
    platform: 'web',
    renderer: 'canvaskit',
    runtimeFidelity: RuntimeFidelity.simulated,
    backendMode: BackendMode.none,
    networkContainment: NetworkContainment.unconstrained,
    bootstrapAssessment: BootstrapAssessment.declared,
    toolchain: const <String, String>{'dart': '3.12.2', 'flutter': '3.44.8'},
    capabilities: const <String>{'capture.png'},
    inputDigests: <String, Digest>{'catalog': subject ?? catalogDigest},
    policies: const <String, String>{'evidence': 'local-v1'},
    sourceRevision: 'working-tree:clean',
  );

  Artifact artifact({
    ArtifactClassification classification = ArtifactClassification.internal,
  }) => Artifact(
    digest: Digest.bytes(const <int>[137, 80, 78, 71]),
    size: 4,
    mediaType: 'image/png',
    classification: classification,
    role: 'capture.screen',
    pixelDigest: pixelDigest,
    width: 1,
    height: 1,
  );

  Evidence evidence({
    Digest? subject,
    ArtifactClassification classification = ArtifactClassification.internal,
  }) => Evidence(
    id: 'evidence-001',
    subjectDigest: subject ?? catalogDigest,
    fingerprint: fingerprint(subject: subject),
    observedAt: DateTime.utc(2026, 8, 9, 12),
    policyId: 'local-v1',
    artifacts: <Artifact>[artifact(classification: classification)],
  );

  Release release({List<Evidence>? items}) => Release(
    id: 'release-001',
    subjectDigest: catalogDigest,
    distributionDigest: distributionDigest,
    coreVersion: '0.1.0-dev',
    createdAt: DateTime.utc(2026, 8, 9, 13),
    policies: const <String, String>{'release': 'local-v1'},
    evidence: items ?? <Evidence>[evidence()],
  );

  test('round-trips evidence, release, and bundle with verified digests', () {
    final originalRelease = release();
    final bundle = ReleaseBundle(
      release: originalRelease,
      artifacts: originalRelease.artifacts,
    );

    final decoded = ReleaseBundle.fromJson(bundle.toJson());

    expect(decoded.digest, bundle.digest);
    expect(decoded.release.digest, originalRelease.digest);
    expect(decoded.artifacts.single.pixelDigest, pixelDigest);
  });

  test('rejects a tampered nested fingerprint', () {
    final json = evidence().toJson();
    final nested = Map<String, Object?>.of(
      json['fingerprint']! as Map<String, Object?>,
    );
    nested['renderer'] = 'html';
    json['fingerprint'] = nested;

    expect(() => Evidence.fromJson(json), throwsFormatException);
  });

  test('classifies stale and invalid evidence independently', () {
    final observed = evidence();
    final changed = Digest.semantic(<String, Object?>{'catalog': 2});

    expect(
      observed.freshnessFor(catalogDigest, artifactsValid: true),
      EvidenceFreshness.fresh,
    );
    expect(
      observed.freshnessFor(changed, artifactsValid: true),
      EvidenceFreshness.stale,
    );
    expect(
      observed.freshnessFor(catalogDigest, artifactsValid: false),
      EvidenceFreshness.invalid,
    );
    expect(
      () => release(items: <Evidence>[evidence(subject: changed)]),
      throwsArgumentError,
    );
  });

  test(
    'PublicationView filters sensitive metadata without mutating Release',
    () {
      final sensitiveRelease = release(
        items: <Evidence>[
          evidence(classification: ArtifactClassification.sensitive),
        ],
      );

      final publication = PublicationView(
        release: sensitiveRelease,
        includeSensitive: false,
      ).toJson();
      final publishedEvidence =
          (publication['evidence']! as List<Object?>).single!
              as Map<String, Object?>;

      expect(publishedEvidence['artifacts'], isEmpty);
      expect(sensitiveRelease.artifacts, hasLength(1));
    },
  );

  test('bundle rejects missing and duplicate artifacts', () {
    final originalRelease = release();
    expect(
      () => ReleaseBundle(
        release: originalRelease,
        artifacts: const <Artifact>[],
      ),
      throwsArgumentError,
    );
    expect(
      () => ReleaseBundle(
        release: originalRelease,
        artifacts: <Artifact>[
          originalRelease.artifacts.single,
          originalRelease.artifacts.single,
        ],
      ),
      throwsArgumentError,
    );
  });

  test('emitted documents conform to the public Evidence schema', () {
    final originalRelease = release();
    final bundle = ReleaseBundle(
      release: originalRelease,
      artifacts: originalRelease.artifacts,
    );
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(
                _repositoryRoot(),
                'schemas',
                'evidence',
                'evidence-release.schema.json',
              ),
            ).readAsStringSync(),
          )
          as Object,
    );

    for (final document in <Map<String, Object?>>[
      originalRelease.evidence.single.fingerprint.toJson(),
      originalRelease.evidence.single.toJson(),
      originalRelease.toJson(),
      bundle.toJson(),
      PublicationView(
        release: originalRelease,
        includeSensitive: false,
      ).toJson(),
    ]) {
      expect(validator.validate(document).isValid, isTrue, reason: '$document');
    }
    final invalid = bundle.toJson();
    final artifactJson = Map<String, Object?>.of(
      (invalid['artifacts']! as List<Object?>).single! as Map<String, Object?>,
    )..remove('role');
    invalid['artifacts'] = <Object?>[artifactJson];
    expect(validator.validate(invalid).isValid, isFalse);
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
