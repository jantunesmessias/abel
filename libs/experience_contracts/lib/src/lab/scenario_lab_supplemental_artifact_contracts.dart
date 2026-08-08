import 'dart:convert';

import '../canonical_json.dart';
import '../catalog/catalog_contracts.dart';
import '../digest.dart';
import '../evidence/evidence_contracts.dart';
import '../immutable_bytes.dart';

/// Consumer-owned identity of the immutable source used to ingest an artifact.
///
/// This is deliberately an opaque identifier, not a filesystem path or URI.
final class ScenarioLabSupplementalArtifactSourceId extends OpaqueId {
  factory ScenarioLabSupplementalArtifactSourceId(String value) {
    _supplementalArtifactId(value, 'source');
    return ScenarioLabSupplementalArtifactSourceId._(value);
  }

  const ScenarioLabSupplementalArtifactSourceId._(super.value);
}

/// Consumer-owned policy identity applied while ingesting an artifact.
final class ScenarioLabSupplementalArtifactImportPolicyId extends OpaqueId {
  factory ScenarioLabSupplementalArtifactImportPolicyId(String value) {
    _supplementalArtifactId(value, 'import policy');
    return ScenarioLabSupplementalArtifactImportPolicyId._(value);
  }

  const ScenarioLabSupplementalArtifactImportPolicyId._(super.value);
}

/// Closed media profiles accepted as Scenario Lab comparison inputs.
enum ScenarioLabSupplementalArtifactMediaType {
  png('image/png'),
  androidSemanticsV1('application/json');

  const ScenarioLabSupplementalArtifactMediaType(this.value);

  final String value;

  static ScenarioLabSupplementalArtifactMediaType fromValue(String value) {
    for (final mediaType in values) {
      if (mediaType.value == value) return mediaType;
    }
    throw FormatException(
      'Unsupported Scenario Lab supplemental artifact media type: $value',
    );
  }
}

/// Deterministic provenance for a consumer-owned supplemental artifact.
///
/// [canonicalBytes] is the complete wire document and [digest] is its CAS byte
/// digest. The document intentionally contains no self-referential digest,
/// absolute path, URI, timestamp or open metadata. A manifest's
/// `provenanceDigest` therefore addresses these exact bytes directly.
final class ScenarioLabSupplementalArtifactProvenance {
  ScenarioLabSupplementalArtifactProvenance({
    required this.artifactDigest,
    required this.size,
    required this.mediaType,
    required this.classification,
    required this.sourceId,
    required this.importPolicyId,
  }) {
    if (size < 1 || size > maxArtifactBytes) {
      throw ArgumentError.value(
        size,
        'size',
        'must be between 1 and $maxArtifactBytes bytes',
      );
    }
  }

  static const int schemaVersion = 1;
  static const String kind = 'ScenarioLabSupplementalArtifactProvenance';
  static const int maxArtifactBytes = 32 * 1024 * 1024;
  static const int maxDocumentBytes = 4096;

  final Digest artifactDigest;
  final int size;
  final ScenarioLabSupplementalArtifactMediaType mediaType;
  final ArtifactClassification classification;
  final ScenarioLabSupplementalArtifactSourceId sourceId;
  final ScenarioLabSupplementalArtifactImportPolicyId importPolicyId;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind,
    'artifactDigest': artifactDigest.value,
    'size': size,
    'mediaType': mediaType.value,
    'classification': classification.name,
    'sourceId': sourceId.value,
    'importPolicyId': importPolicyId.value,
  };

  late final ImmutableBytes canonicalBytes = ImmutableBytes.copyOf(
    utf8.encode(const JcsCanonicalizer().canonicalize(toJson())),
  );

  /// CAS identity of [canonicalBytes], not a second semantic digest domain.
  late final Digest digest = Digest.bytes(canonicalBytes);

  factory ScenarioLabSupplementalArtifactProvenance.fromJson(
    Object? value, {
    required Digest expectedDigest,
  }) {
    final json = _supplementalArtifactObject(value);
    const fields = <String>{
      'schemaVersion',
      'kind',
      'artifactDigest',
      'size',
      'mediaType',
      'classification',
      'sourceId',
      'importPolicyId',
    };
    if (json.length != fields.length ||
        json.keys.any((key) => !fields.contains(key)) ||
        json['schemaVersion'] != schemaVersion ||
        json['kind'] != kind) {
      throw const FormatException(
        'Invalid ScenarioLabSupplementalArtifactProvenance document',
      );
    }
    final size = json['size'];
    if (size is! int || size < 1 || size > maxArtifactBytes) {
      throw const FormatException(
        'Scenario Lab supplemental artifact size is invalid',
      );
    }
    final classificationValue = _supplementalArtifactString(
      json,
      'classification',
    );
    ArtifactClassification? classification;
    for (final candidate in ArtifactClassification.values) {
      if (candidate.name == classificationValue) classification = candidate;
    }
    if (classification == null) {
      throw const FormatException(
        'Scenario Lab supplemental artifact classification is invalid',
      );
    }
    final provenance = ScenarioLabSupplementalArtifactProvenance(
      artifactDigest: Digest(
        _supplementalArtifactString(json, 'artifactDigest'),
      ),
      size: size,
      mediaType: ScenarioLabSupplementalArtifactMediaType.fromValue(
        _supplementalArtifactString(json, 'mediaType'),
      ),
      classification: classification,
      sourceId: ScenarioLabSupplementalArtifactSourceId(
        _supplementalArtifactString(json, 'sourceId'),
      ),
      importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
        _supplementalArtifactString(json, 'importPolicyId'),
      ),
    );
    if (provenance.digest != expectedDigest) {
      throw const FormatException(
        'Scenario Lab supplemental artifact provenance digest mismatch',
      );
    }
    return provenance;
  }
}

void _supplementalArtifactId(String value, String kind) {
  if (value.length > 256) {
    throw FormatException(
      'Scenario Lab supplemental artifact $kind ID is too long',
    );
  }
  OpaqueId.validate(value, 'Scenario Lab supplemental artifact $kind');
}

Map<String, Object?> _supplementalArtifactObject(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'ScenarioLabSupplementalArtifactProvenance must be an object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException(
        'ScenarioLabSupplementalArtifactProvenance keys must be strings',
      );
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

String _supplementalArtifactString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 512) {
    throw FormatException(
      'Scenario Lab supplemental artifact $key must be a bounded string',
    );
  }
  return value;
}
