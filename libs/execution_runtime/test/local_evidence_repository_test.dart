import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory temporary;
  late FileSystemWorkspaceStore store;
  late LocalEvidenceRepository repository;
  late Digest catalogDigest;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('workspace-evidence-');
    store = FileSystemWorkspaceStore(workspaceRoot: temporary.path);
    repository = LocalEvidenceRepository(
      store: store,
      clock: _FixedClock(),
      ids: _SequenceIds(),
    );
    catalogDigest = Digest.semantic(<String, Object?>{'catalog': 'current'});
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('reports missing without creating workspace state', () {
    expect(repository.freshnessFor(catalogDigest), EvidenceFreshness.missing);
    expect(
      Directory(p.join(temporary.path, '.dart_tool')).existsSync(),
      isFalse,
    );
  });

  test('captures in CAS and publishes a verified offline bundle', () {
    final evidence = repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
      classification: ArtifactClassification.sensitive,
    );

    expect(repository.readLatestEvidence()!.digest, evidence.digest);
    expect(repository.freshnessFor(catalogDigest), EvidenceFreshness.fresh);
    final result = repository.buildRelease(
      currentSubject: catalogDigest,
      distributionDigest: Digest.semantic(<String, Object?>{
        'distribution': 'full-local',
      }),
      coreVersion: '0.1.0-dev',
    );

    expect(
      repository.verifyBundle(result.directory).digest,
      result.bundle.digest,
    );
    expect(
      Digest.bytes(
        File(p.join(result.directory, 'release.json')).readAsBytesSync(),
      ),
      result.release.digest,
    );
    final publication =
        jsonDecode(
              File(
                p.join(result.directory, 'publication.json'),
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final publishedEvidence =
        (publication['evidence']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(publishedEvidence['artifacts'], isEmpty);
    expect(Directory(p.join(store.stateRoot, '.staging')).listSync(), isEmpty);
    expect(store.readStateBytes('releases/latest.json'), isNotNull);
  });

  test('refuses stale evidence without publishing a ReleasePointer', () {
    repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
    );
    final changed = Digest.semantic(<String, Object?>{'catalog': 'changed'});

    expect(
      () => repository.buildRelease(
        currentSubject: changed,
        distributionDigest: Digest.semantic('distribution'),
        coreVersion: '0.1.0-dev',
      ),
      throwsA(isA<EvidencePreconditionException>()),
    );
    expect(store.readStateBytes('releases/latest.json'), isNull);
  });

  test('bounds tampered reads and programmatic Evidence writes at 16 MiB', () {
    final digest = Digest.semantic('oversized-evidence-state');
    store.atomicWrite(
      p.join(
        'evidence',
        'sha256',
        '${digest.value.substring('sha256:'.length)}.json',
      ),
      List<int>.filled(LocalEvidenceRepository.maxDocumentBytes + 1, 0x20),
    );
    expect(() => repository.readEvidence(digest), throwsStateError);

    final bytes = _captureBytes();
    final inspection = const PngCaptureInspector().inspect(bytes);
    final artifactDigest = store.putBlob(bytes);
    final evidence = Evidence(
      id: 'e${'x' * LocalEvidenceRepository.maxDocumentBytes}',
      subjectDigest: catalogDigest,
      fingerprint: _fingerprint(catalogDigest),
      observedAt: DateTime.utc(2026, 8, 13, 12),
      policyId: 'local-v1',
      artifacts: <Artifact>[
        Artifact(
          digest: artifactDigest,
          size: bytes.length,
          mediaType: 'image/png',
          classification: ArtifactClassification.internal,
          role: 'capture.screen',
          pixelDigest: inspection.pixelDigest,
          width: inspection.width,
          height: inspection.height,
        ),
      ],
    );
    expect(() => repository.persistEvidence(evidence), throwsStateError);
    expect(
      store.readStateBytes(
        p.join(
          'evidence',
          'sha256',
          '${evidence.digest.value.substring('sha256:'.length)}.json',
        ),
      ),
      isNull,
    );
  });

  test('detects invalid CAS and an altered exported blob', () {
    final evidence = repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
    );
    final artifact = evidence.artifacts.single;
    final casFile = File(
      p.join(
        store.stateRoot,
        'cas',
        'sha256',
        artifact.digest.value.substring('sha256:'.length),
      ),
    );
    final original = casFile.readAsBytesSync();
    casFile.writeAsBytesSync(const <int>[0], flush: true);
    expect(repository.freshnessFor(catalogDigest), EvidenceFreshness.invalid);
    casFile.writeAsBytesSync(original, flush: true);

    final release = repository.buildRelease(
      currentSubject: catalogDigest,
      distributionDigest: Digest.semantic('distribution'),
      coreVersion: '0.1.0-dev',
    );
    final exported = File(
      p.join(
        release.directory,
        'blobs',
        'sha256',
        artifact.digest.value.substring('sha256:'.length),
      ),
    );
    exported.writeAsBytesSync(const <int>[0], flush: true);

    expect(
      () => repository.verifyBundle(release.directory),
      throwsFormatException,
    );
  });

  test('reads verified Evidence history in canonical observation order', () {
    final first = repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
    );
    final second = repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
    );

    final history = repository.readAllEvidence();

    expect(history.map((item) => item.digest), <Digest>[
      first.digest,
      second.digest,
    ]);
    expect(() => history.add(first), throwsUnsupportedError);
    expect(() => repository.readAllEvidence(maxItems: 1), throwsStateError);
  });

  test('reads only the exact Evidence digest and never falls back', () {
    final evidence = repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
    );

    expect(
      repository.readEvidence(evidence.digest)?.toJson(),
      evidence.toJson(),
    );
    expect(repository.readEvidence(Digest.semantic('absent')), isNull);

    final document = File(
      p.join(
        store.stateRoot,
        'evidence',
        'sha256',
        '${evidence.digest.value.substring('sha256:'.length)}.json',
      ),
    );
    document.writeAsStringSync(
      '${const JcsCanonicalizer().canonicalize(<String, Object?>{...evidence.toJson(), 'policyId': 'tampered'})}\n',
      flush: true,
    );
    expect(
      () => repository.readEvidence(evidence.digest),
      throwsFormatException,
    );
  });

  test('reserves aggregate document bytes before allocation and decode', () {
    final first = repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
    );
    final second = repository.capturePng(
      bytes: _captureBytes(),
      fingerprint: _fingerprint(catalogDigest),
    );
    final firstFile = _evidenceFile(store, first.digest);
    final secondFile = _evidenceFile(store, second.digest);
    final firstSize = firstFile.lengthSync();
    final secondSize = secondFile.lengthSync();
    expect(repository.readEvidence(first.digest), isNotNull);
    expect(repository.readEvidence(second.digest), isNotNull);

    var remaining = firstSize + secondSize - 1;
    void reserve(int bytes) {
      if (bytes > remaining) throw const _DocumentBudgetExceeded();
      remaining -= bytes;
    }

    final firstRead = repository.readEvidenceDocument(
      first.digest,
      reserveEncodedBytes: reserve,
    );
    expect(firstRead?.encodedByteCount, firstSize);
    secondFile.writeAsBytesSync(
      List<int>.filled(secondSize, 0x20),
      flush: true,
    );
    expect(
      () => repository.readEvidenceDocument(
        second.digest,
        reserveEncodedBytes: reserve,
      ),
      throwsA(isA<_DocumentBudgetExceeded>()),
      reason: 'budget rejection precedes allocation, UTF-8 and JSON decode',
    );
    expect(() => repository.readEvidence(second.digest), throwsFormatException);
  });
}

final class _DocumentBudgetExceeded implements Exception {
  const _DocumentBudgetExceeded();
}

File _evidenceFile(FileSystemWorkspaceStore store, Digest digest) => File(
  p.join(
    store.stateRoot,
    'evidence',
    'sha256',
    '${digest.value.substring('sha256:'.length)}.json',
  ),
);

List<int> _captureBytes() => rgbaPng(
  width: 2,
  height: 1,
  pixels: const <int>[255, 0, 0, 255, 0, 0, 255, 255],
);

ExecutionFingerprint _fingerprint(Digest catalogDigest) => ExecutionFingerprint(
  catalogDigest: catalogDigest,
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
  inputDigests: <String, Digest>{'catalog': catalogDigest},
  policies: const <String, String>{'evidence': 'local-v1'},
  sourceRevision: 'working-tree:test',
);

final class _FixedClock implements Clock {
  var calls = 0;

  @override
  int monotonicMicroseconds() => calls * 1000;

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 9, 12, calls++);
}

final class _SequenceIds implements IdGenerator {
  var next = 0;

  @override
  String nextId() => 'id-${next++}';
}
