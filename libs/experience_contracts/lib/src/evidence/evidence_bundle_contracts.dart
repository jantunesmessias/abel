import '../digest.dart';

final class EvidenceBundleEntry {
  EvidenceBundleEntry({
    required this.path,
    required this.digest,
    required this.size,
    required this.mediaType,
  }) {
    _bundlePath(path);
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'must be non-negative');
    }
    if (mediaType.isEmpty) throw ArgumentError('mediaType must be non-empty');
  }

  final String path;
  final Digest digest;
  final int size;
  final String mediaType;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'digest': digest.value,
    'size': size,
    'mediaType': mediaType,
  };

  factory EvidenceBundleEntry.fromJson(Object? value) {
    final json = _bundleObject(value, 'EvidenceBundleEntry');
    _bundleOnly(json, const <String>{
      'path',
      'digest',
      'size',
      'mediaType',
    }, 'EvidenceBundleEntry');
    return EvidenceBundleEntry(
      path: _bundleString(json, 'path', 'EvidenceBundleEntry'),
      digest: Digest(_bundleString(json, 'digest', 'EvidenceBundleEntry')),
      size: _bundleInt(json, 'size', 'EvidenceBundleEntry'),
      mediaType: _bundleString(json, 'mediaType', 'EvidenceBundleEntry'),
    );
  }
}

final class EvidenceBundleManifest {
  EvidenceBundleManifest({
    required this.releaseDigest,
    required this.releaseBundleDigest,
    required List<EvidenceBundleEntry> entries,
    this.attestationDigest,
  }) : entries = List<EvidenceBundleEntry>.unmodifiable(
         List<EvidenceBundleEntry>.of(entries)
           ..sort((a, b) => a.path.compareTo(b.path)),
       ) {
    if (this.entries.isEmpty ||
        this.entries.map((entry) => entry.path).toSet().length !=
            this.entries.length) {
      throw ArgumentError(
        'EvidenceBundleManifest entries must be non-empty and unique',
      );
    }
  }

  static const int schemaVersion = 1;
  final Digest releaseDigest;
  final Digest releaseBundleDigest;
  final List<EvidenceBundleEntry> entries;
  final Digest? attestationDigest;
  bool get attested => attestationDigest != null;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'EvidenceBundleManifest',
    'releaseDigest': releaseDigest.value,
    'releaseBundleDigest': releaseBundleDigest.value,
    'entries': <Object?>[for (final entry in entries) entry.toJson()],
    'attestation': attestationDigest == null
        ? const <String, Object?>{'status': 'absent'}
        : <String, Object?>{
            'status': 'present',
            'digest': attestationDigest!.value,
          },
    if (includeDigest) 'digest': digest.value,
  };

  factory EvidenceBundleManifest.fromJson(Object? value) {
    final json = _bundleObject(value, 'EvidenceBundleManifest');
    _bundleOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'releaseDigest',
      'releaseBundleDigest',
      'entries',
      'attestation',
      'digest',
    }, 'EvidenceBundleManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'EvidenceBundleManifest') {
      throw const FormatException(
        'Invalid EvidenceBundleManifest version or kind',
      );
    }
    final attestation = _bundleObject(
      json['attestation'],
      'EvidenceBundleManifest.attestation',
    );
    _bundleOnly(attestation, const <String>{
      'status',
      'digest',
    }, 'EvidenceBundleManifest.attestation');
    final status = _bundleString(
      attestation,
      'status',
      'EvidenceBundleManifest.attestation',
    );
    if (status != 'absent' && status != 'present') {
      throw const FormatException('Invalid attestation status');
    }
    if ((status == 'present') != attestation.containsKey('digest')) {
      throw const FormatException('Attestation status and digest disagree');
    }
    final entriesValue = json['entries'];
    if (entriesValue is! List<Object?>) {
      throw const FormatException(
        'EvidenceBundleManifest.entries must be an array',
      );
    }
    final manifest = EvidenceBundleManifest(
      releaseDigest: Digest(
        _bundleString(json, 'releaseDigest', 'EvidenceBundleManifest'),
      ),
      releaseBundleDigest: Digest(
        _bundleString(json, 'releaseBundleDigest', 'EvidenceBundleManifest'),
      ),
      entries: entriesValue
          .map(EvidenceBundleEntry.fromJson)
          .toList(growable: false),
      attestationDigest: status == 'present'
          ? Digest(
              _bundleString(
                attestation,
                'digest',
                'EvidenceBundleManifest.attestation',
              ),
            )
          : null,
    );
    if (Digest(_bundleString(json, 'digest', 'EvidenceBundleManifest')) !=
        manifest.digest) {
      throw const FormatException(
        'EvidenceBundleManifest.digest does not match canonical content',
      );
    }
    return manifest;
  }
}

final class ReleaseSeal {
  ReleaseSeal({
    required this.releaseDigest,
    required this.bundleArchiveDigest,
    required this.impactPlanDigest,
    required List<Digest> sourceSnapshotDigests,
    required this.policyId,
  }) : sourceSnapshotDigests = List<Digest>.unmodifiable(
         List<Digest>.of(sourceSnapshotDigests)
           ..sort((a, b) => a.value.compareTo(b.value)),
       ) {
    if (this.sourceSnapshotDigests.isEmpty ||
        this.sourceSnapshotDigests.toSet().length !=
            this.sourceSnapshotDigests.length) {
      throw ArgumentError(
        'ReleaseSeal source snapshots must be non-empty and unique',
      );
    }
    if (policyId.isEmpty) {
      throw ArgumentError('ReleaseSeal.policyId must be non-empty');
    }
  }

  static const int schemaVersion = 1;
  final Digest releaseDigest;
  final Digest bundleArchiveDigest;
  final Digest impactPlanDigest;
  final List<Digest> sourceSnapshotDigests;
  final String policyId;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ReleaseSeal',
    'releaseDigest': releaseDigest.value,
    'bundleArchiveDigest': bundleArchiveDigest.value,
    'impactPlanDigest': impactPlanDigest.value,
    'sourceSnapshotDigests': sourceSnapshotDigests
        .map((item) => item.value)
        .toList(),
    'policyId': policyId,
    if (includeDigest) 'digest': digest.value,
  };

  factory ReleaseSeal.fromJson(Object? value) {
    final json = _bundleObject(value, 'ReleaseSeal');
    _bundleOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'releaseDigest',
      'bundleArchiveDigest',
      'impactPlanDigest',
      'sourceSnapshotDigests',
      'policyId',
      'digest',
    }, 'ReleaseSeal');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ReleaseSeal') {
      throw const FormatException('Invalid ReleaseSeal version or kind');
    }
    final snapshots = json['sourceSnapshotDigests'];
    if (snapshots is! List<Object?> ||
        snapshots.any((item) => item is! String)) {
      throw const FormatException(
        'ReleaseSeal.sourceSnapshotDigests must be an array of digests',
      );
    }
    final seal = ReleaseSeal(
      releaseDigest: Digest(
        _bundleString(json, 'releaseDigest', 'ReleaseSeal'),
      ),
      bundleArchiveDigest: Digest(
        _bundleString(json, 'bundleArchiveDigest', 'ReleaseSeal'),
      ),
      impactPlanDigest: Digest(
        _bundleString(json, 'impactPlanDigest', 'ReleaseSeal'),
      ),
      sourceSnapshotDigests: snapshots
          .cast<String>()
          .map(Digest.new)
          .toList(growable: false),
      policyId: _bundleString(json, 'policyId', 'ReleaseSeal'),
    );
    if (Digest(_bundleString(json, 'digest', 'ReleaseSeal')) != seal.digest) {
      throw const FormatException(
        'ReleaseSeal.digest does not match canonical content',
      );
    }
    return seal;
  }
}

Map<String, Object?> _bundleObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _bundleOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _bundleString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

int _bundleInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('$path.$key must be a non-negative integer');
  }
  return value;
}

void _bundlePath(String value) {
  final segments = value.split('/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      segments.contains('..') ||
      segments.contains('') ||
      value.endsWith('/')) {
    throw FormatException('Unsafe EvidenceBundle path: $value');
  }
}
