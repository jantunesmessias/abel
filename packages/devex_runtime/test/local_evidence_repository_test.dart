import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory temporary;
  late FileSystemWorkspaceStore store;
  late LocalEvidenceRepository repository;
  late Digest catalogDigest;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('devex-evidence-');
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
        'distribution': 'devex-kit',
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
}

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
