import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../secure_id_generator.dart';
import '../storage/filesystem_workspace_store.dart';
import '../system_clock.dart';
import 'png_capture_inspector.dart';

final class EvidencePreconditionException implements Exception {
  const EvidencePreconditionException(this.message, {this.freshness});

  final String message;
  final EvidenceFreshness? freshness;

  @override
  String toString() => message;
}

final class LocalReleaseResult {
  const LocalReleaseResult({
    required this.release,
    required this.bundle,
    required this.publication,
    required this.directory,
  });

  final Release release;
  final ReleaseBundle bundle;
  final PublicationView publication;
  final String directory;
}

/// One exact Evidence document together with its encoded storage cost.
final class EvidenceDocumentRead {
  const EvidenceDocumentRead({
    required this.evidence,
    required this.encodedByteCount,
  });

  final Evidence evidence;
  final int encodedByteCount;
}

/// Filesystem adapter for the local Evidence & Release bounded context.
///
/// Documents are JCS encoded, blobs live in the workspace CAS, and a release
/// directory is exposed only after its self-contained bundle verifies.
final class LocalEvidenceRepository {
  static const int maxDocumentBytes = 16 * 1024 * 1024;

  LocalEvidenceRepository({
    required this.store,
    this.inspector = const PngCaptureInspector(),
    Clock? clock,
    IdGenerator? ids,
  }) : clock = clock ?? SystemClock(),
       ids = ids ?? SecureIdGenerator();

  final FileSystemWorkspaceStore store;
  final PngCaptureInspector inspector;
  final Clock clock;
  final IdGenerator ids;

  Evidence capturePng({
    required List<int> bytes,
    required ExecutionFingerprint fingerprint,
    ArtifactClassification classification = ArtifactClassification.internal,
    String role = 'capture.screen',
    String policyId = 'local-v1',
  }) {
    final inspection = inspector.inspect(bytes);
    final subjectDigest = fingerprint.catalogDigest;
    return store.withExclusiveLock(() {
      final blobDigest = store.putBlob(bytes);
      final artifact = Artifact(
        digest: blobDigest,
        size: bytes.length,
        mediaType: 'image/png',
        classification: classification,
        role: role,
        pixelDigest: inspection.pixelDigest,
        width: inspection.width,
        height: inspection.height,
      );
      final evidence = Evidence(
        id: 'evidence-${ids.nextId()}',
        subjectDigest: subjectDigest,
        fingerprint: fingerprint,
        observedAt: clock.nowUtc(),
        policyId: policyId,
        artifacts: <Artifact>[artifact],
      );
      return _persistEvidence(evidence);
    });
  }

  /// Persists evidence produced by any provider after verifying every CAS
  /// artifact. This keeps PNG and multimodal evidence under one repository and
  /// one freshness/release model.
  Evidence persistEvidence(Evidence evidence) => store.withExclusiveLock(() {
    return _persistEvidence(evidence);
  });

  Evidence _persistEvidence(Evidence evidence) {
    if (!_artifactsAreValid(evidence.artifacts)) {
      throw StateError('Evidence contains a missing or invalid CAS artifact');
    }
    _writeDocument(_evidencePath(evidence.digest), evidence.toJson());
    _writeDocument('evidence/latest.json', <String, Object?>{
      'schemaVersion': 1,
      'kind': 'EvidencePointer',
      'evidenceDigest': evidence.digest.value,
    });
    store.rebuildCasIndex();
    return evidence;
  }

  Evidence? readLatestEvidence() {
    final pointerBytes = store.readStateBytesBounded(
      'evidence/latest.json',
      maxBytes: maxDocumentBytes,
    );
    if (pointerBytes == null) return null;
    final pointer = _decodeObject(pointerBytes, 'evidence/latest.json');
    _expectExactKeys(pointer, const <String>{
      'schemaVersion',
      'kind',
      'evidenceDigest',
    }, 'EvidencePointer');
    if (pointer['schemaVersion'] != 1 || pointer['kind'] != 'EvidencePointer') {
      throw const FormatException('Invalid EvidencePointer version or kind');
    }
    final rawDigest = pointer['evidenceDigest'];
    if (rawDigest is! String) {
      throw const FormatException('EvidencePointer.evidenceDigest is required');
    }
    final digest = Digest(rawDigest);
    final evidence = readEvidence(digest);
    if (evidence == null) {
      throw StateError('EvidencePointer references a missing document');
    }
    return evidence;
  }

  /// Reads one exact immutable Evidence document by semantic digest.
  ///
  /// This never falls back to the latest pointer. Artifact bytes remain a
  /// separate CAS concern and must be verified by the operation consuming the
  /// document.
  Evidence? readEvidence(Digest digest) =>
      readEvidenceDocument(digest)?.evidence;

  /// Reads and decodes one Evidence document with a pre-allocation budget hook.
  ///
  /// [reserveEncodedBytes] runs after the single file-size observation but
  /// before opening, allocating, UTF-8 decoding or parsing the document. A
  /// callback rejection therefore cannot be masked by later document/CAS work.
  EvidenceDocumentRead? readEvidenceDocument(
    Digest digest, {
    void Function(int byteCount)? reserveEncodedBytes,
  }) {
    final path = _evidencePath(digest);
    final evidenceBytes = store.readStateBytesBounded(
      path,
      maxBytes: maxDocumentBytes,
      beforeRead: reserveEncodedBytes,
    );
    if (evidenceBytes == null) return null;
    final evidence = Evidence.fromJson(_decodeObject(evidenceBytes, path));
    if (evidence.digest != digest) {
      throw const FormatException('Evidence document digest mismatch');
    }
    return EvidenceDocumentRead(
      evidence: evidence,
      encodedByteCount: evidenceBytes.length,
    );
  }

  /// Reads the bounded, digest-addressed Evidence history in canonical order.
  /// Invalid entries fail closed instead of being silently skipped.
  List<Evidence> readAllEvidence({int maxItems = 100000}) {
    if (maxItems < 1 || maxItems > 100000) {
      throw ArgumentError.value(maxItems, 'maxItems');
    }
    final directory = Directory(p.join(store.stateRoot, 'evidence', 'sha256'));
    if (!directory.existsSync()) return const <Evidence>[];
    if (Link(directory.path).existsSync()) {
      throw FileSystemException(
        'Evidence directory cannot be a symlink',
        directory.path,
      );
    }
    final entities = directory.listSync(followLinks: false)
      ..sort((left, right) => left.path.compareTo(right.path));
    if (entities.length > maxItems) {
      throw StateError('Evidence history exceeds the read limit');
    }
    final result = <Evidence>[];
    for (final entity in entities) {
      if (entity is! File || Link(entity.path).existsSync()) {
        throw FileSystemException(
          'Evidence history contains a non-file entry',
          entity.path,
        );
      }
      final name = p.basenameWithoutExtension(entity.path);
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(name)) {
        throw FormatException('Invalid Evidence history filename: $name');
      }
      final digest = Digest('sha256:$name');
      final bytes = entity.readAsBytesSync();
      final evidence = Evidence.fromJson(
        _decodeObject(bytes, p.relative(entity.path, from: store.stateRoot)),
      );
      if (evidence.digest != digest) {
        throw const FormatException('Evidence history digest mismatch');
      }
      result.add(evidence);
    }
    result.sort((left, right) {
      final byTime = left.observedAt.compareTo(right.observedAt);
      return byTime != 0
          ? byTime
          : left.digest.value.compareTo(right.digest.value);
    });
    return List<Evidence>.unmodifiable(result);
  }

  EvidenceFreshness freshnessFor(Digest currentSubject) {
    final evidence = readLatestEvidence();
    if (evidence == null) return EvidenceFreshness.missing;
    return evidence.freshnessFor(
      currentSubject,
      artifactsValid: _artifactsAreValid(evidence.artifacts),
    );
  }

  LocalReleaseResult buildRelease({
    required Digest currentSubject,
    required Digest distributionDigest,
    required String coreVersion,
    Map<String, String> policies = const <String, String>{
      'release': 'local-v1',
    },
  }) => store.withExclusiveLock(() {
    final evidence = readLatestEvidence();
    if (evidence == null) {
      throw const EvidencePreconditionException(
        'Release requires captured Evidence',
        freshness: EvidenceFreshness.missing,
      );
    }
    final freshness = evidence.freshnessFor(
      currentSubject,
      artifactsValid: _artifactsAreValid(evidence.artifacts),
    );
    if (freshness != EvidenceFreshness.fresh) {
      throw EvidencePreconditionException(
        'Release requires fresh, valid Evidence; got ${freshness.name}',
        freshness: freshness,
      );
    }
    final release = Release(
      id: 'release-${ids.nextId()}',
      subjectDigest: currentSubject,
      distributionDigest: distributionDigest,
      coreVersion: coreVersion,
      createdAt: clock.nowUtc(),
      policies: policies,
      evidence: <Evidence>[evidence],
    );
    final bundle = ReleaseBundle(
      release: release,
      artifacts: release.artifacts,
    );
    final publication = PublicationView(
      release: release,
      includeSensitive: false,
    );
    final releaseBytes = _canonicalBytes(
      release.toJson(),
      trailingNewline: false,
    );
    final bundleBytes = _canonicalBytes(bundle.toJson());
    final storedReleaseDigest = store.putBlob(releaseBytes);
    if (storedReleaseDigest != release.digest) {
      throw StateError(
        'Release manifest bytes do not match its semantic digest',
      );
    }
    store.putBlob(bundleBytes);
    final directory = _publishRelease(
      release: release,
      bundle: bundle,
      publication: publication,
      releaseBytes: releaseBytes,
      bundleBytes: bundleBytes,
    );
    final verified = verifyBundle(directory);
    if (verified.digest != bundle.digest) {
      throw StateError('Published bundle digest changed during verification');
    }
    _writeDocument('releases/latest.json', <String, Object?>{
      'schemaVersion': 1,
      'kind': 'ReleasePointer',
      'releaseDigest': release.digest.value,
      'bundleDigest': bundle.digest.value,
      'path': p.relative(directory, from: store.stateRoot),
    });
    store.rebuildCasIndex();
    return LocalReleaseResult(
      release: release,
      bundle: bundle,
      publication: publication,
      directory: directory,
    );
  });

  ReleaseBundle verifyBundle(String directoryPath) {
    final directory = Directory(directoryPath).absolute;
    if (!directory.existsSync()) {
      throw FileSystemException(
        'Release bundle directory is missing',
        directory.path,
      );
    }
    final bundleFile = _regularFile(directory, 'bundle.json');
    final bundle = ReleaseBundle.fromJson(
      _decodeObject(bundleFile.readAsBytesSync(), bundleFile.path),
    );
    _expectCanonical(bundleFile, bundle.toJson());
    final releaseFile = _regularFile(directory, 'release.json');
    final release = Release.fromJson(
      _decodeObject(releaseFile.readAsBytesSync(), releaseFile.path),
      expectedDigest: bundle.release.digest,
    );
    if (release.digest != bundle.release.digest) {
      throw const FormatException('bundle.json and release.json disagree');
    }
    _expectCanonical(releaseFile, release.toJson(), trailingNewline: false);
    final publicationFile = _regularFile(directory, 'publication.json');
    _expectCanonical(
      publicationFile,
      PublicationView(release: release, includeSensitive: false).toJson(),
    );

    final expectedRelativeFiles = <String>{
      'bundle.json',
      'release.json',
      'publication.json',
    };
    for (final artifact in bundle.artifacts) {
      final relative = p.join(
        'blobs',
        'sha256',
        artifact.digest.value.substring('sha256:'.length),
      );
      expectedRelativeFiles.add(relative);
      final file = _regularFile(directory, relative);
      final bytes = file.readAsBytesSync();
      if (bytes.length != artifact.size ||
          Digest.bytes(bytes) != artifact.digest) {
        throw FormatException(
          'Artifact ${artifact.digest.value} failed verification',
        );
      }
      if (artifact.mediaType == 'image/png') {
        final png = inspector.inspect(bytes);
        if (png.width != artifact.width ||
            png.height != artifact.height ||
            png.pixelDigest != artifact.pixelDigest) {
          throw FormatException(
            'PNG identity ${artifact.digest.value} failed verification',
          );
        }
      }
    }
    final actualRelativeFiles = <String>{};
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) {
        throw FileSystemException(
          'Symlinks are forbidden in ReleaseBundle',
          entity.path,
        );
      }
      if (entity is File) {
        actualRelativeFiles.add(p.relative(entity.path, from: directory.path));
      }
    }
    if (actualRelativeFiles.length != expectedRelativeFiles.length ||
        !actualRelativeFiles.containsAll(expectedRelativeFiles)) {
      throw const FormatException(
        'ReleaseBundle contains missing or unexpected files',
      );
    }
    return bundle;
  }

  String _publishRelease({
    required Release release,
    required ReleaseBundle bundle,
    required PublicationView publication,
    required List<int> releaseBytes,
    required List<int> bundleBytes,
  }) {
    final releaseHex = release.digest.value.substring('sha256:'.length);
    final releasesRoot = Directory(
      p.join(store.stateRoot, 'releases', 'sha256'),
    )..createSync(recursive: true);
    final destination = Directory(p.join(releasesRoot.path, releaseHex));
    if (destination.existsSync()) {
      final existing = verifyBundle(destination.path);
      if (existing.digest != bundle.digest) {
        throw StateError('Release digest collision at ${destination.path}');
      }
      return destination.path;
    }
    final stagingRoot = Directory(p.join(store.stateRoot, '.staging'))
      ..createSync(recursive: true);
    final staging = Directory(
      p.join(stagingRoot.path, 'release-$releaseHex-${ids.nextId()}'),
    )..createSync();
    try {
      _writeFile(staging, 'release.json', releaseBytes);
      _writeFile(staging, 'bundle.json', bundleBytes);
      _writeFile(
        staging,
        'publication.json',
        _canonicalBytes(publication.toJson()),
      );
      for (final artifact in bundle.artifacts) {
        final bytes = store.readBlob(artifact.digest);
        if (bytes == null) {
          throw StateError('CAS is missing ${artifact.digest.value}');
        }
        _writeFile(
          staging,
          p.join(
            'blobs',
            'sha256',
            artifact.digest.value.substring('sha256:'.length),
          ),
          bytes,
        );
      }
      verifyBundle(staging.path);
      staging.renameSync(destination.path);
      return destination.path;
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  bool _artifactsAreValid(List<Artifact> artifacts) {
    try {
      for (final artifact in artifacts) {
        final bytes = store.readBlob(artifact.digest);
        if (bytes == null || bytes.length != artifact.size) return false;
        if (artifact.mediaType == 'image/png') {
          final png = inspector.inspect(bytes);
          if (png.width != artifact.width ||
              png.height != artifact.height ||
              png.pixelDigest != artifact.pixelDigest) {
            return false;
          }
        }
      }
      return true;
    } on Object {
      return false;
    }
  }

  String _evidencePath(Digest digest) => p.join(
    'evidence',
    'sha256',
    '${digest.value.substring('sha256:'.length)}.json',
  );

  void _writeDocument(String path, Map<String, Object?> document) {
    final bytes = _canonicalBytes(document);
    if (bytes.length > maxDocumentBytes) {
      throw StateError('Evidence document exceeds the write size budget');
    }
    store.atomicWrite(path, bytes);
  }

  List<int> _canonicalBytes(
    Map<String, Object?> document, {
    bool trailingNewline = true,
  }) {
    final canonical = const JcsCanonicalizer().canonicalize(document);
    return utf8.encode(trailingNewline ? '$canonical\n' : canonical);
  }

  Map<String, Object?> _decodeObject(List<int> bytes, String source) {
    if (bytes.length > maxDocumentBytes) {
      throw FormatException('$source exceeds the document size budget');
    }
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, Object?>) {
        throw FormatException('$source must contain a JSON object');
      }
      return value;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('$source is invalid JSON: $error');
    }
  }

  void _expectExactKeys(
    Map<String, Object?> value,
    Set<String> expected,
    String path,
  ) {
    if (value.keys.length != expected.length ||
        !value.keys.toSet().containsAll(expected)) {
      throw FormatException('$path fields do not match the v1 contract');
    }
  }

  File _regularFile(Directory root, String relative) {
    final normalized = p.normalize(p.join(root.path, relative));
    if (!p.isWithin(root.path, normalized) || Link(normalized).existsSync()) {
      throw FileSystemException('Unsafe ReleaseBundle path', normalized);
    }
    final file = File(normalized);
    if (!file.existsSync()) {
      throw FileSystemException('ReleaseBundle file is missing', normalized);
    }
    return file;
  }

  void _expectCanonical(
    File file,
    Map<String, Object?> document, {
    bool trailingNewline = true,
  }) {
    final expected = _canonicalBytes(
      document,
      trailingNewline: trailingNewline,
    );
    final actual = file.readAsBytesSync();
    if (!_bytesEqual(actual, expected)) {
      throw FormatException('${file.path} is not canonical JCS');
    }
  }

  void _writeFile(Directory root, String relative, List<int> bytes) {
    final normalized = p.normalize(p.join(root.path, relative));
    if (!p.isWithin(root.path, normalized)) {
      throw FileSystemException('Unsafe staging path', normalized);
    }
    final file = File(normalized);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
  }

  bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
