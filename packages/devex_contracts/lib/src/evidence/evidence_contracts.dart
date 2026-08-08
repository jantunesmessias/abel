import '../canonical_json.dart';
import '../digest.dart';

enum ArtifactClassification { public, internal, sensitive }

enum RuntimeFidelity { structural, simulated, hostNative, deviceAttested }

enum BackendMode { none, isolated, hybrid }

enum NetworkContainment { unconstrained, gatewayOnly, targetEnforced }

enum BootstrapAssessment { unassessed, declared, controlled, failed }

enum EvidenceFreshness { missing, fresh, stale, invalid }

final class Artifact {
  Artifact({
    required this.digest,
    required this.size,
    required this.mediaType,
    required this.classification,
    required this.role,
    this.pixelDigest,
    this.width,
    this.height,
  }) {
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'must be non-negative');
    }
    _nonEmpty(mediaType, 'mediaType');
    _nonEmpty(role, 'role');
    final visualFields = <Object?>[pixelDigest, width, height];
    if (visualFields.any((value) => value != null) &&
        visualFields.any((value) => value == null)) {
      throw ArgumentError(
        'pixelDigest, width, and height must either all be present or all absent',
      );
    }
    if (pixelDigest != null) {
      if (mediaType != 'image/png') {
        throw ArgumentError('Pixel identity is only valid for image/png');
      }
      if (width! <= 0 || height! <= 0) {
        throw ArgumentError('PNG dimensions must be positive');
      }
    }
  }

  final Digest digest;
  final int size;
  final String mediaType;
  final ArtifactClassification classification;
  final String role;
  final Digest? pixelDigest;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => <String, Object?>{
    'digest': digest.value,
    'size': size,
    'mediaType': mediaType,
    'classification': classification.name,
    'role': role,
    if (pixelDigest != null) 'pixelDigest': pixelDigest!.value,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  };

  factory Artifact.fromJson(Object? value) {
    final json = _object(value, 'Artifact');
    _onlyKeys(json, const <String>{
      'digest',
      'size',
      'mediaType',
      'classification',
      'role',
      'pixelDigest',
      'width',
      'height',
    }, 'Artifact');
    return Artifact(
      digest: Digest(_string(json, 'digest', 'Artifact')),
      size: _integer(json, 'size', 'Artifact'),
      mediaType: _string(json, 'mediaType', 'Artifact'),
      classification: _enumValue(
        ArtifactClassification.values,
        _string(json, 'classification', 'Artifact'),
        'Artifact.classification',
      ),
      role: _string(json, 'role', 'Artifact'),
      pixelDigest: _optionalDigest(json, 'pixelDigest', 'Artifact'),
      width: _optionalInteger(json, 'width', 'Artifact'),
      height: _optionalInteger(json, 'height', 'Artifact'),
    );
  }
}

final class ExecutionFingerprint {
  ExecutionFingerprint({
    required this.catalogDigest,
    required this.launchProfileId,
    required this.targetId,
    required this.platform,
    required this.renderer,
    required this.runtimeFidelity,
    required this.backendMode,
    required this.networkContainment,
    required this.bootstrapAssessment,
    required Map<String, String> toolchain,
    required Set<String> capabilities,
    Map<String, Digest> inputDigests = const <String, Digest>{},
    Map<String, String> policies = const <String, String>{},
    this.sourceRevision,
  }) : toolchain = _immutableNonEmptyMap(toolchain, 'toolchain'),
       capabilities = _immutableStringSet(capabilities, 'capabilities'),
       inputDigests = Map<String, Digest>.unmodifiable(inputDigests),
       policies = _immutableStringMap(policies, 'policies') {
    _nonEmpty(launchProfileId, 'launchProfileId');
    _nonEmpty(targetId, 'targetId');
    _nonEmpty(platform, 'platform');
    _nonEmpty(renderer, 'renderer');
    if (sourceRevision != null) _nonEmpty(sourceRevision!, 'sourceRevision');
    for (final key in inputDigests.keys) {
      _nonEmpty(key, 'inputDigests key');
    }
  }

  static const int schemaVersion = 1;

  final Digest catalogDigest;
  final String launchProfileId;
  final String targetId;
  final String platform;
  final String renderer;
  final RuntimeFidelity runtimeFidelity;
  final BackendMode backendMode;
  final NetworkContainment networkContainment;
  final BootstrapAssessment bootstrapAssessment;
  final Map<String, String> toolchain;
  final Set<String> capabilities;
  final Map<String, Digest> inputDigests;
  final Map<String, String> policies;
  final String? sourceRevision;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  bool get hasReproductionClaim =>
      sourceRevision != null && inputDigests.isNotEmpty && policies.isNotEmpty;

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExecutionFingerprint',
    'catalogDigest': catalogDigest.value,
    'launchProfileId': launchProfileId,
    'targetId': targetId,
    'platform': platform,
    'renderer': renderer,
    'runtimeFidelity': runtimeFidelity.name,
    'backendMode': backendMode.name,
    'networkContainment': networkContainment.name,
    'bootstrapAssessment': bootstrapAssessment.name,
    'toolchain': _sortedStrings(toolchain),
    'capabilities': capabilities.toList()..sort(),
    'inputDigests': _sortedDigests(inputDigests),
    'policies': _sortedStrings(policies),
    if (sourceRevision != null) 'sourceRevision': sourceRevision,
    if (includeDigest) 'digest': digest.value,
  };

  factory ExecutionFingerprint.fromJson(Object? value) {
    final json = _object(value, 'ExecutionFingerprint');
    _onlyKeys(json, const <String>{
      'schemaVersion',
      'kind',
      'catalogDigest',
      'launchProfileId',
      'targetId',
      'platform',
      'renderer',
      'runtimeFidelity',
      'backendMode',
      'networkContainment',
      'bootstrapAssessment',
      'toolchain',
      'capabilities',
      'inputDigests',
      'policies',
      'sourceRevision',
      'digest',
    }, 'ExecutionFingerprint');
    _versionAndKind(json, 'ExecutionFingerprint');
    final fingerprint = ExecutionFingerprint(
      catalogDigest: Digest(
        _string(json, 'catalogDigest', 'ExecutionFingerprint'),
      ),
      launchProfileId: _string(json, 'launchProfileId', 'ExecutionFingerprint'),
      targetId: _string(json, 'targetId', 'ExecutionFingerprint'),
      platform: _string(json, 'platform', 'ExecutionFingerprint'),
      renderer: _string(json, 'renderer', 'ExecutionFingerprint'),
      runtimeFidelity: _enumValue(
        RuntimeFidelity.values,
        _string(json, 'runtimeFidelity', 'ExecutionFingerprint'),
        'ExecutionFingerprint.runtimeFidelity',
      ),
      backendMode: _enumValue(
        BackendMode.values,
        _string(json, 'backendMode', 'ExecutionFingerprint'),
        'ExecutionFingerprint.backendMode',
      ),
      networkContainment: _enumValue(
        NetworkContainment.values,
        _string(json, 'networkContainment', 'ExecutionFingerprint'),
        'ExecutionFingerprint.networkContainment',
      ),
      bootstrapAssessment: _enumValue(
        BootstrapAssessment.values,
        _string(json, 'bootstrapAssessment', 'ExecutionFingerprint'),
        'ExecutionFingerprint.bootstrapAssessment',
      ),
      toolchain: _stringMap(
        json['toolchain'],
        'ExecutionFingerprint.toolchain',
      ),
      capabilities: _stringList(
        json['capabilities'],
        'ExecutionFingerprint.capabilities',
      ).toSet(),
      inputDigests: _digestMap(
        json['inputDigests'],
        'ExecutionFingerprint.inputDigests',
      ),
      policies: _stringMap(json['policies'], 'ExecutionFingerprint.policies'),
      sourceRevision: _optionalString(
        json,
        'sourceRevision',
        'ExecutionFingerprint',
      ),
    );
    _verifyDigest(json, fingerprint.digest, 'ExecutionFingerprint');
    return fingerprint;
  }
}

final class Evidence {
  Evidence({
    required this.id,
    required this.subjectDigest,
    required this.fingerprint,
    required this.observedAt,
    required this.policyId,
    required List<Artifact> artifacts,
  }) : artifacts = List<Artifact>.unmodifiable(
         List<Artifact>.of(artifacts)..sort(
           (left, right) => left.digest.value.compareTo(right.digest.value),
         ),
       ) {
    _nonEmpty(id, 'id');
    _nonEmpty(policyId, 'policyId');
    if (artifacts.isEmpty) throw ArgumentError('Evidence requires an artifact');
    if (artifacts.map((artifact) => artifact.digest).toSet().length !=
        artifacts.length) {
      throw ArgumentError('Evidence artifact digests must be unique');
    }
  }

  static const int schemaVersion = 1;

  final String id;
  final Digest subjectDigest;
  final ExecutionFingerprint fingerprint;
  final DateTime observedAt;
  final String policyId;
  final List<Artifact> artifacts;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  EvidenceFreshness freshnessFor(
    Digest currentSubject, {
    required bool artifactsValid,
  }) {
    if (!artifactsValid) return EvidenceFreshness.invalid;
    return isFreshFor(currentSubject)
        ? EvidenceFreshness.fresh
        : EvidenceFreshness.stale;
  }

  bool isFreshFor(Digest currentSubject) =>
      subjectDigest == currentSubject &&
      fingerprint.catalogDigest == currentSubject;

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'Evidence',
    'id': id,
    'subjectDigest': subjectDigest.value,
    'fingerprint': fingerprint.toJson(),
    'observedAt': observedAt.toUtc().toIso8601String(),
    'policyId': policyId,
    'artifacts': <Object?>[for (final artifact in artifacts) artifact.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory Evidence.fromJson(Object? value) {
    final json = _object(value, 'Evidence');
    _onlyKeys(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'subjectDigest',
      'fingerprint',
      'observedAt',
      'policyId',
      'artifacts',
      'digest',
    }, 'Evidence');
    _versionAndKind(json, 'Evidence');
    final evidence = Evidence(
      id: _string(json, 'id', 'Evidence'),
      subjectDigest: Digest(_string(json, 'subjectDigest', 'Evidence')),
      fingerprint: ExecutionFingerprint.fromJson(json['fingerprint']),
      observedAt: _dateTime(json, 'observedAt', 'Evidence'),
      policyId: _string(json, 'policyId', 'Evidence'),
      artifacts: _list(
        json['artifacts'],
        'Evidence.artifacts',
      ).map(Artifact.fromJson).toList(growable: false),
    );
    _verifyDigest(json, evidence.digest, 'Evidence');
    return evidence;
  }
}

final class Approval {
  Approval({
    required this.id,
    required this.subjectDigest,
    required this.principalId,
    required this.decidedAt,
    required this.approved,
  }) {
    _nonEmpty(id, 'id');
    _nonEmpty(principalId, 'principalId');
  }

  final String id;
  final Digest subjectDigest;
  final String principalId;
  final DateTime decidedAt;
  final bool approved;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'subjectDigest': subjectDigest.value,
    'principalId': principalId,
    'decidedAt': decidedAt.toUtc().toIso8601String(),
    'approved': approved,
  };
}

final class Finding {
  Finding({
    required this.id,
    required this.subjectDigest,
    required this.severity,
    required this.message,
  }) {
    _nonEmpty(id, 'id');
    _nonEmpty(severity, 'severity');
    _nonEmpty(message, 'message');
  }

  final String id;
  final Digest subjectDigest;
  final String severity;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'subjectDigest': subjectDigest.value,
    'severity': severity,
    'message': message,
  };
}

final class Release {
  Release({
    required this.id,
    required this.subjectDigest,
    required this.distributionDigest,
    required this.coreVersion,
    required this.createdAt,
    required Map<String, String> policies,
    required List<Evidence> evidence,
  }) : policies = _immutableNonEmptyMap(policies, 'policies'),
       evidence = List<Evidence>.unmodifiable(
         List<Evidence>.of(evidence)..sort(
           (left, right) => left.digest.value.compareTo(right.digest.value),
         ),
       ) {
    _nonEmpty(id, 'id');
    _nonEmpty(coreVersion, 'coreVersion');
    if (evidence.isEmpty) throw ArgumentError('Release requires Evidence');
    if (evidence.map((item) => item.digest).toSet().length != evidence.length) {
      throw ArgumentError('Release Evidence digests must be unique');
    }
    for (final item in evidence) {
      if (!item.isFreshFor(subjectDigest)) {
        throw ArgumentError('Release contains stale Evidence ${item.id}');
      }
    }
  }

  static const int schemaVersion = 1;

  final String id;
  final Digest subjectDigest;
  final Digest distributionDigest;
  final String coreVersion;
  final DateTime createdAt;
  final Map<String, String> policies;
  final List<Evidence> evidence;

  late final Digest digest = Digest.semantic(toJson());

  List<Artifact> get artifacts {
    final byDigest = <Digest, Artifact>{};
    for (final item in evidence) {
      for (final artifact in item.artifacts) {
        final previous = byDigest[artifact.digest];
        if (previous != null &&
            const JcsCanonicalizer().canonicalize(previous.toJson()) !=
                const JcsCanonicalizer().canonicalize(artifact.toJson())) {
          throw StateError(
            'Conflicting metadata for artifact ${artifact.digest.value}',
          );
        }
        byDigest[artifact.digest] = artifact;
      }
    }
    return byDigest.values.toList(growable: false)
      ..sort((left, right) => left.digest.value.compareTo(right.digest.value));
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'Release',
    'id': id,
    'subjectDigest': subjectDigest.value,
    'distributionDigest': distributionDigest.value,
    'coreVersion': coreVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'policies': _sortedStrings(policies),
    'evidence': <Object?>[for (final item in evidence) item.toJson()],
  };

  factory Release.fromJson(Object? value, {required Digest expectedDigest}) {
    final json = _object(value, 'Release');
    _onlyKeys(json, const <String>{
      'schemaVersion',
      'kind',
      'id',
      'subjectDigest',
      'distributionDigest',
      'coreVersion',
      'createdAt',
      'policies',
      'evidence',
    }, 'Release');
    _versionAndKind(json, 'Release');
    final release = Release(
      id: _string(json, 'id', 'Release'),
      subjectDigest: Digest(_string(json, 'subjectDigest', 'Release')),
      distributionDigest: Digest(
        _string(json, 'distributionDigest', 'Release'),
      ),
      coreVersion: _string(json, 'coreVersion', 'Release'),
      createdAt: _dateTime(json, 'createdAt', 'Release'),
      policies: _stringMap(json['policies'], 'Release.policies'),
      evidence: _list(
        json['evidence'],
        'Release.evidence',
      ).map(Evidence.fromJson).toList(growable: false),
    );
    if (release.digest != expectedDigest) {
      throw const FormatException('Release digest mismatch');
    }
    return release;
  }
}

final class PublicationView {
  PublicationView({
    required this.release,
    required this.includeSensitive,
    List<Approval> approvals = const <Approval>[],
    List<Finding> findings = const <Finding>[],
  }) : approvals = List<Approval>.unmodifiable(approvals),
       findings = List<Finding>.unmodifiable(findings) {
    for (final approval in approvals) {
      if (approval.subjectDigest != release.digest) {
        throw ArgumentError(
          'Approval ${approval.id} does not target the Release',
        );
      }
    }
    for (final finding in findings) {
      if (finding.subjectDigest != release.digest) {
        throw ArgumentError(
          'Finding ${finding.id} does not target the Release',
        );
      }
    }
  }

  final Release release;
  final bool includeSensitive;
  final List<Approval> approvals;
  final List<Finding> findings;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'PublicationView',
    'releaseId': release.id,
    'releaseDigest': release.digest.value,
    'subjectDigest': release.subjectDigest.value,
    'evidence': <Object?>[
      for (final item in release.evidence)
        <String, Object?>{
          'id': item.id,
          'digest': item.digest.value,
          'freshness': EvidenceFreshness.fresh.name,
          'artifacts': <Object?>[
            for (final artifact in item.artifacts)
              if (includeSensitive ||
                  artifact.classification != ArtifactClassification.sensitive)
                artifact.toJson(),
          ],
        },
    ],
    'approvals': <Object?>[for (final approval in approvals) approval.toJson()],
    'findings': <Object?>[for (final finding in findings) finding.toJson()],
  };
}

final class ReleaseBundle {
  ReleaseBundle({required this.release, required List<Artifact> artifacts})
    : artifacts = List<Artifact>.unmodifiable(
        List<Artifact>.of(artifacts)..sort(
          (left, right) => left.digest.value.compareTo(right.digest.value),
        ),
      ) {
    final expected = release.artifacts
        .map((artifact) => artifact.digest)
        .toSet();
    final actual = artifacts.map((artifact) => artifact.digest).toSet();
    if (actual.length != artifacts.length) {
      throw ArgumentError('ReleaseBundle artifact digests must be unique');
    }
    if (expected.length != actual.length || !expected.containsAll(actual)) {
      throw ArgumentError('ReleaseBundle must contain every Release artifact');
    }
  }

  static const int schemaVersion = 1;

  final Release release;
  final List<Artifact> artifacts;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ReleaseBundle',
    'releaseDigest': release.digest.value,
    'release': release.toJson(),
    'artifacts': <Object?>[for (final artifact in artifacts) artifact.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory ReleaseBundle.fromJson(Object? value) {
    final json = _object(value, 'ReleaseBundle');
    _onlyKeys(json, const <String>{
      'schemaVersion',
      'kind',
      'releaseDigest',
      'release',
      'artifacts',
      'digest',
    }, 'ReleaseBundle');
    _versionAndKind(json, 'ReleaseBundle');
    final bundle = ReleaseBundle(
      release: Release.fromJson(
        json['release'],
        expectedDigest: Digest(_string(json, 'releaseDigest', 'ReleaseBundle')),
      ),
      artifacts: _list(
        json['artifacts'],
        'ReleaseBundle.artifacts',
      ).map(Artifact.fromJson).toList(growable: false),
    );
    _verifyDigest(json, bundle.digest, 'ReleaseBundle');
    return bundle;
  }
}

Map<String, String> _immutableNonEmptyMap(
  Map<String, String> values,
  String name,
) {
  if (values.isEmpty) throw ArgumentError('$name must not be empty');
  return _immutableStringMap(values, name);
}

Map<String, String> _immutableStringMap(
  Map<String, String> values,
  String name,
) {
  for (final entry in values.entries) {
    _nonEmpty(entry.key, '$name key');
    _nonEmpty(entry.value, '$name.${entry.key}');
  }
  return Map<String, String>.unmodifiable(values);
}

Set<String> _immutableStringSet(Set<String> values, String name) {
  for (final value in values) {
    _nonEmpty(value, name);
  }
  return Set<String>.unmodifiable(values);
}

void _nonEmpty(String value, String name) {
  if (value.trim().isEmpty) throw ArgumentError.value(value, name, 'is empty');
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path must be an array');
  return value;
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

int? _optionalInteger(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

Digest? _optionalDigest(Map<String, Object?> json, String key, String path) {
  final value = _optionalString(json, key, path);
  return value == null ? null : Digest(value);
}

DateTime _dateTime(Map<String, Object?> json, String key, String path) {
  final raw = _string(json, key, path);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc || !raw.endsWith('Z')) {
    throw FormatException('$path.$key must be an RFC 3339 UTC timestamp');
  }
  return parsed;
}

List<String> _stringList(Object? value, String path) {
  final list = _list(value, path);
  if (list.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$path must contain only non-empty strings');
  }
  final strings = list.cast<String>();
  if (strings.toSet().length != strings.length) {
    throw FormatException('$path must contain unique values');
  }
  return strings;
}

Map<String, String> _stringMap(Object? value, String path) {
  final map = _object(value, path);
  final output = <String, String>{};
  for (final entry in map.entries) {
    if (entry.key.isEmpty ||
        entry.value is! String ||
        (entry.value! as String).isEmpty) {
      throw FormatException('$path must contain non-empty string entries');
    }
    output[entry.key] = entry.value! as String;
  }
  return output;
}

Map<String, Digest> _digestMap(Object? value, String path) {
  final map = _object(value, path);
  return <String, Digest>{
    for (final entry in map.entries)
      entry.key: entry.value is String
          ? Digest(entry.value! as String)
          : throw FormatException('$path.${entry.key} must be a digest'),
  };
}

T _enumValue<T extends Enum>(List<T> values, String value, String path) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$path has unsupported value $value');
}

void _versionAndKind(Map<String, Object?> json, String kind) {
  if (json['schemaVersion'] != 1) {
    throw FormatException('$kind.schemaVersion must equal 1');
  }
  if (json['kind'] != kind) {
    throw FormatException('$kind.kind must equal $kind');
  }
}

void _verifyDigest(Map<String, Object?> json, Digest actual, String path) {
  final declared = Digest(_string(json, 'digest', path));
  if (declared != actual) throw FormatException('$path digest mismatch');
}

void _onlyKeys(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path has unknown field $key');
    }
  }
}

Map<String, String> _sortedStrings(Map<String, String> values) =>
    Map<String, String>.fromEntries(
      values.entries.toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    );

Map<String, String> _sortedDigests(Map<String, Digest> values) =>
    Map<String, String>.fromEntries(
      values.entries
          .map((entry) => MapEntry(entry.key, entry.value.value))
          .toList()
        ..sort((left, right) => left.key.compareTo(right.key)),
    );
