import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('canonical bytes are the sole provenance CAS identity', () {
    final provenance = _provenance();
    final canonical = utf8.decode(provenance.canonicalBytes);
    final expected =
        '{"artifactDigest":"${provenance.artifactDigest.value}",'
        '"classification":"internal",'
        '"importPolicyId":"delivery-lab.baseline-v1",'
        '"kind":"ScenarioLabSupplementalArtifactProvenance",'
        '"mediaType":"image/png",'
        '"schemaVersion":1,'
        '"size":3,'
        '"sourceId":"dashboard-ready.baseline"'
        '}';

    expect(canonical, expected);
    expect(provenance.digest, Digest.bytes(provenance.canonicalBytes));
    expect(provenance.digest, Digest.semantic(provenance.toJson()));
    expect(_validator().validate(provenance.toJson()).isValid, isTrue);

    final decoded = jsonDecode(canonical);
    final roundTrip = ScenarioLabSupplementalArtifactProvenance.fromJson(
      decoded,
      expectedDigest: provenance.digest,
    );
    expect(roundTrip.toJson(), provenance.toJson());
    expect(roundTrip.canonicalBytes, provenance.canonicalBytes);
    expect(roundTrip.digest, provenance.digest);
  });

  test('JCS identity is independent of input object field order', () {
    final provenance = _provenance();
    final reordered =
        ScenarioLabSupplementalArtifactProvenance.fromJson(<String, Object?>{
          'importPolicyId': provenance.importPolicyId.value,
          'sourceId': provenance.sourceId.value,
          'classification': provenance.classification.name,
          'mediaType': provenance.mediaType.value,
          'size': provenance.size,
          'artifactDigest': provenance.artifactDigest.value,
          'kind': ScenarioLabSupplementalArtifactProvenance.kind,
          'schemaVersion': 1,
        }, expectedDigest: provenance.digest);

    expect(reordered.canonicalBytes, provenance.canonicalBytes);
    expect(reordered.digest, provenance.digest);
    final changed = _provenance(sourceId: 'dashboard-failed.baseline');
    expect(changed.digest, isNot(provenance.digest));
  });

  test('media type is a closed wire enum', () {
    expect(
      ScenarioLabSupplementalArtifactMediaType.values.map(
        (value) => value.value,
      ),
      <String>['image/png', 'application/json'],
    );
    for (final mediaType in ScenarioLabSupplementalArtifactMediaType.values) {
      final provenance = _provenance(mediaType: mediaType);
      expect(_validator().validate(provenance.toJson()).isValid, isTrue);
      expect(
        ScenarioLabSupplementalArtifactProvenance.fromJson(
          provenance.toJson(),
          expectedDigest: provenance.digest,
        ).mediaType,
        mediaType,
      );
    }
  });

  test('strict codec and schema reject adjacent and open documents', () {
    final valid = _provenance().toJson();
    final invalid = <Map<String, Object?>>[
      <String, Object?>{...valid, 'schemaVersion': 2},
      <String, Object?>{...valid, 'kind': 'SupplementalArtifactProvenance'},
      <String, Object?>{...valid}..remove('importPolicyId'),
      <String, Object?>{...valid, 'metadata': <String, Object?>{}},
      <String, Object?>{...valid, 'capturedAt': '2026-08-14T00:00:00Z'},
      <String, Object?>{...valid, 'artifactDigest': 'sha256:not-a-digest'},
      <String, Object?>{...valid, 'size': 0},
      <String, Object?>{...valid, 'size': 33554433},
      <String, Object?>{...valid, 'size': 3.5},
      <String, Object?>{...valid, 'mediaType': 'application/octet-stream'},
      <String, Object?>{...valid, 'classification': 'secret'},
      <String, Object?>{...valid, 'sourceId': '/tmp/baseline.png'},
      <String, Object?>{...valid, 'sourceId': 'file:///workspace/baseline.png'},
      <String, Object?>{...valid, 'importPolicyId': 'DeliveryLab'},
      <String, Object?>{...valid, 'importPolicyId': 'p${'x' * 256}'},
    ];

    for (final document in invalid) {
      expect(
        _validator().validate(document).isValid,
        isFalse,
        reason: document.toString(),
      );
      expect(
        () => ScenarioLabSupplementalArtifactProvenance.fromJson(
          document,
          expectedDigest: _provenance().digest,
        ),
        throwsFormatException,
        reason: document.toString(),
      );
    }
    expect(
      () => ScenarioLabSupplementalArtifactProvenance.fromJson(
        <Object?, Object?>{1: true},
        expectedDigest: _provenance().digest,
      ),
      throwsFormatException,
    );
    final integralDouble = <String, Object?>{...valid, 'size': 3.0};
    expect(
      _validator().validate(integralDouble).isValid,
      isTrue,
      reason: 'JSON Schema integer includes mathematically integral numbers',
    );
    expect(
      () => ScenarioLabSupplementalArtifactProvenance.fromJson(
        integralDouble,
        expectedDigest: _provenance().digest,
      ),
      throwsFormatException,
      reason: 'the Dart codec additionally rejects an adjacent double value',
    );
    final validTamper = <String, Object?>{
      ...valid,
      'sourceId': 'dashboard-failed.baseline',
    };
    expect(_validator().validate(validTamper).isValid, isTrue);
    expect(
      () => ScenarioLabSupplementalArtifactProvenance.fromJson(
        validTamper,
        expectedDigest: _provenance().digest,
      ),
      throwsFormatException,
      reason: 'valid adjacent content must not retain the old CAS identity',
    );
  });

  test('direct constructors enforce bounded consumer-owned IDs and size', () {
    expect(
      () => ScenarioLabSupplementalArtifactSourceId('../baseline'),
      throwsFormatException,
    );
    expect(
      () =>
          ScenarioLabSupplementalArtifactImportPolicyId('https://policy.test'),
      throwsFormatException,
    );
    expect(() => _provenance(size: 0), throwsArgumentError);
    expect(
      () => _provenance(
        size: ScenarioLabSupplementalArtifactProvenance.maxArtifactBytes + 1,
      ),
      throwsArgumentError,
    );
  });
}

ScenarioLabSupplementalArtifactProvenance _provenance({
  int size = 3,
  String sourceId = 'dashboard-ready.baseline',
  ScenarioLabSupplementalArtifactMediaType mediaType =
      ScenarioLabSupplementalArtifactMediaType.png,
}) => ScenarioLabSupplementalArtifactProvenance(
  artifactDigest: Digest.bytes(const <int>[1, 2, 3]),
  size: size,
  mediaType: mediaType,
  classification: ArtifactClassification.internal,
  sourceId: ScenarioLabSupplementalArtifactSourceId(sourceId),
  importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
    'delivery-lab.baseline-v1',
  ),
);

Draft202012Validator _validator() => Draft202012Validator(
  jsonDecode(
        File(
          p.join(
            _repositoryRoot(),
            'schemas',
            'evidence',
            'scenario-lab-supplemental-artifact-provenance.schema.json',
          ),
        ).readAsStringSync(),
      )
      as Object,
);

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    if (File(p.join(current.path, 'ARCHITECTURE.md')).existsSync()) {
      return current.path;
    }
    current = current.parent;
  }
  throw StateError('Repository root not found');
}
