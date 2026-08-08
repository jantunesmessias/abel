import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('devex-bundle-test.'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('builds byte-identical ZIPs and verifies the release offline', () {
    final releaseDirectory = _releaseDirectory(temp);
    const repository = DeterministicDevExBundleRepository();
    final first = repository.build(
      releaseDirectory: releaseDirectory.path,
      outputPath: p.join(temp.path, 'one.devexbundle'),
    );
    final second = repository.build(
      releaseDirectory: releaseDirectory.path,
      outputPath: p.join(temp.path, 'two.devexbundle'),
    );
    expect(
      File(first.path).readAsBytesSync(),
      File(second.path).readAsBytesSync(),
    );
    expect(first.archiveDigest, second.archiveDigest);
    expect(first.manifest.attested, isFalse);
    expect(
      repository.verify(first.path).manifest.digest,
      first.manifest.digest,
    );
  });

  test('rejects trailing data and path traversal before extraction', () {
    final releaseDirectory = _releaseDirectory(temp);
    const repository = DeterministicDevExBundleRepository();
    final built = repository.build(
      releaseDirectory: releaseDirectory.path,
      outputPath: p.join(temp.path, 'valid.devexbundle'),
    );
    final trailing = File(p.join(temp.path, 'trailing.devexbundle'))
      ..writeAsBytesSync(<int>[...File(built.path).readAsBytesSync(), 0]);
    expect(() => repository.verify(trailing.path), throwsFormatException);

    final source = File(built.path).readAsBytesSync();
    final original = utf8.encode('release.json');
    final replacement = utf8.encode('../ease.json');
    var replacements = 0;
    for (var index = 0; index <= source.length - original.length; index += 1) {
      if (_matches(source, index, original)) {
        source.setRange(index, index + original.length, replacement);
        replacements += 1;
      }
    }
    // local header, central directory, and manifest inventory.
    expect(replacements, 3);
    final traversal = File(p.join(temp.path, 'traversal.devexbundle'))
      ..writeAsBytesSync(source);
    expect(() => repository.verify(traversal.path), throwsFormatException);
  });
}

Directory _releaseDirectory(Directory temp) {
  final root = Directory(p.join(temp.path, 'release'))..createSync();
  final artifactBytes = utf8.encode('artifact');
  final artifact = Artifact(
    digest: Digest.bytes(artifactBytes),
    size: artifactBytes.length,
    mediaType: 'application/octet-stream',
    classification: ArtifactClassification.internal,
    role: 'test.output',
  );
  final subject = Digest.semantic(<String, Object?>{'catalog': 1});
  final fingerprint = ExecutionFingerprint(
    catalogDigest: subject,
    launchProfileId: 'web',
    targetId: 'chrome',
    platform: 'web',
    renderer: 'canvaskit',
    runtimeFidelity: RuntimeFidelity.simulated,
    backendMode: BackendMode.none,
    networkContainment: NetworkContainment.unconstrained,
    bootstrapAssessment: BootstrapAssessment.declared,
    toolchain: const <String, String>{'dart': '3.12.2'},
    capabilities: const <String>{'test'},
  );
  final evidence = Evidence(
    id: 'evidence-1',
    subjectDigest: subject,
    fingerprint: fingerprint,
    observedAt: DateTime.utc(2026, 8, 9),
    policyId: 'test',
    artifacts: <Artifact>[artifact],
  );
  final release = Release(
    id: 'release-1',
    subjectDigest: subject,
    distributionDigest: Digest.semantic(<String, Object?>{'distribution': 1}),
    coreVersion: '0.1.0-dev',
    createdAt: DateTime.utc(2026, 8, 9),
    policies: const <String, String>{'release': 'test'},
    evidence: <Evidence>[evidence],
  );
  final bundle = ReleaseBundle(
    release: release,
    artifacts: <Artifact>[artifact],
  );
  _write(root, 'release.json', release.toJson(), newline: false);
  _write(root, 'bundle.json', bundle.toJson());
  _write(
    root,
    'publication.json',
    PublicationView(release: release, includeSensitive: false).toJson(),
  );
  final blob = File(
    p.join(root.path, 'blobs/sha256/${artifact.digest.value.substring(7)}'),
  );
  blob.parent.createSync(recursive: true);
  blob.writeAsBytesSync(artifactBytes);
  return root;
}

void _write(
  Directory root,
  String path,
  Map<String, Object?> value, {
  bool newline = true,
}) {
  final text = const JcsCanonicalizer().canonicalize(value);
  File(p.join(root.path, path)).writeAsStringSync(newline ? '$text\n' : text);
}

bool _matches(List<int> source, int offset, List<int> expected) {
  for (var index = 0; index < expected.length; index += 1) {
    if (source[offset + index] != expected[index]) return false;
  }
  return true;
}
