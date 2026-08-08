import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/src/lab/scenario_lab_execution_ports.dart';
import 'package:execution_runtime/src/lab/scenario_lab_supplemental_artifact_cas_resolver.dart';
import 'package:execution_runtime/src/storage/filesystem_workspace_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  late Directory workspace;
  late FileSystemWorkspaceStore store;
  late ScenarioLabSupplementalArtifactCasResolver resolver;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('workspace-lab-cas-input-');
    store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    resolver = ScenarioLabSupplementalArtifactCasResolver(store: store);
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test('resolves exact canonical PNG bytes and typed provenance', () async {
    final bytes = rgbaPng(
      width: 2,
      height: 1,
      pixels: const <int>[255, 0, 0, 255, 0, 255, 0, 255],
    );
    final persisted = _persist(
      store,
      bytes,
      mediaType: ScenarioLabSupplementalArtifactMediaType.png,
    );

    final resolved = await resolver.resolve(
      runId: _runId,
      descriptor: persisted.descriptor,
      cancellation: _Cancellation(),
    );

    expect(resolved, isNotNull);
    expect(resolved!.descriptor, same(persisted.descriptor));
    expect(resolved.bytes, bytes);
    expect(
      store.readBlob(persisted.provenance.digest),
      persisted.provenance.canonicalBytes,
    );
  });

  test('resolves the closed canonical Android semantics profile', () async {
    final bytes = _semantics(<Map<String, Object?>>[
      <String, Object?>{
        'class': 'android.widget.TextView',
        'textDigest': Digest.semantic('Delivery Lab').value,
      },
    ]);
    final persisted = _persist(
      store,
      bytes,
      mediaType: ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1,
    );

    final resolved = await resolver.resolve(
      runId: _runId,
      descriptor: persisted.descriptor,
      cancellation: _Cancellation(),
    );

    expect(resolved?.bytes, bytes);
  });

  test('exact absence returns null and never selects a decoy', () async {
    final bytes = rgbaPng(
      width: 1,
      height: 1,
      pixels: const <int>[1, 2, 3, 255],
    );
    final decoy = _persist(
      store,
      bytes,
      mediaType: ScenarioLabSupplementalArtifactMediaType.png,
    );
    final missingArtifact = ScenarioLabComparisonArtifactDescriptor(
      artifactDigest: Digest.semantic('missing-artifact'),
      provenanceDigest: decoy.provenance.digest,
      classification: ArtifactClassification.internal,
    );
    final missingProvenance = ScenarioLabComparisonArtifactDescriptor(
      artifactDigest: decoy.descriptor.artifactDigest,
      provenanceDigest: Digest.semantic('missing-provenance'),
      classification: ArtifactClassification.internal,
    );

    expect(
      await resolver.resolve(
        runId: _runId,
        descriptor: missingArtifact,
        cancellation: _Cancellation(),
      ),
      isNull,
    );
    expect(
      await resolver.resolve(
        runId: _runId,
        descriptor: missingProvenance,
        cancellation: _Cancellation(),
      ),
      isNull,
    );
  });

  test(
    'fails closed for artifact, size and classification mismatches',
    () async {
      final first = rgbaPng(
        width: 1,
        height: 1,
        pixels: const <int>[1, 2, 3, 255],
      );
      final second = rgbaPng(
        width: 1,
        height: 1,
        pixels: const <int>[3, 2, 1, 255],
      );
      final firstDigest = store.putBlob(first);
      final secondDigest = store.putBlob(second);
      final wrongArtifact = _storeProvenance(
        store,
        artifactDigest: secondDigest,
        size: first.length,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      );
      final wrongSize = _storeProvenance(
        store,
        artifactDigest: firstDigest,
        size: first.length + 1,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      );
      final valid = _storeProvenance(
        store,
        artifactDigest: firstDigest,
        size: first.length,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      );

      for (final descriptor in <ScenarioLabComparisonArtifactDescriptor>[
        ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: firstDigest,
          provenanceDigest: wrongArtifact.digest,
          classification: ArtifactClassification.internal,
        ),
        ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: firstDigest,
          provenanceDigest: wrongSize.digest,
          classification: ArtifactClassification.internal,
        ),
        ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: firstDigest,
          provenanceDigest: valid.digest,
          classification: ArtifactClassification.public,
        ),
      ]) {
        await expectLater(
          resolver.resolve(
            runId: _runId,
            descriptor: descriptor,
            cancellation: _Cancellation(),
          ),
          throwsA(isA<ScenarioLabComparisonInputInvalid>()),
        );
      }
    },
  );

  test(
    'fails closed for malformed, noncanonical and wrong-media provenance',
    () async {
      final bytes = rgbaPng(
        width: 1,
        height: 1,
        pixels: const <int>[1, 2, 3, 255],
      );
      final artifactDigest = store.putBlob(bytes);
      final malformedDigest = store.putBlob(utf8.encode('{not-json'));
      final provenance = _provenance(
        artifactDigest: artifactDigest,
        size: bytes.length,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      );
      final noncanonicalDigest = store.putBlob(
        utf8.encode('${jsonEncode(provenance.toJson())}\n'),
      );
      final nonPng = const <int>[1, 2, 3, 4];
      final nonPngDigest = store.putBlob(nonPng);
      final wrongMedia = _storeProvenance(
        store,
        artifactDigest: nonPngDigest,
        size: nonPng.length,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      );

      for (final descriptor in <ScenarioLabComparisonArtifactDescriptor>[
        ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: artifactDigest,
          provenanceDigest: malformedDigest,
          classification: ArtifactClassification.internal,
        ),
        ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: artifactDigest,
          provenanceDigest: noncanonicalDigest,
          classification: ArtifactClassification.internal,
        ),
        ScenarioLabComparisonArtifactDescriptor(
          artifactDigest: nonPngDigest,
          provenanceDigest: wrongMedia.digest,
          classification: ArtifactClassification.internal,
        ),
      ]) {
        await expectLater(
          resolver.resolve(
            runId: _runId,
            descriptor: descriptor,
            cancellation: _Cancellation(),
          ),
          throwsA(isA<ScenarioLabComparisonInputInvalid>()),
        );
      }
    },
  );

  test(
    'CAS tamper and cancellation fail with explicit typed outcomes',
    () async {
      final bytes = rgbaPng(
        width: 1,
        height: 1,
        pixels: const <int>[1, 2, 3, 255],
      );
      final persisted = _persist(
        store,
        bytes,
        mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      );
      _casFile(
        store,
        persisted.descriptor.artifactDigest,
      ).writeAsBytesSync(const <int>[0], flush: true);

      await expectLater(
        resolver.resolve(
          runId: _runId,
          descriptor: persisted.descriptor,
          cancellation: _Cancellation(),
        ),
        throwsA(isA<ScenarioLabComparisonInputInvalid>()),
      );
      await expectLater(
        resolver.resolve(
          runId: _runId,
          descriptor: ScenarioLabComparisonArtifactDescriptor(
            artifactDigest: Digest.semantic('absent'),
            provenanceDigest: Digest.semantic('also-absent'),
            classification: ArtifactClassification.internal,
          ),
          cancellation: _Cancellation(cancelled: true),
        ),
        throwsA(isA<ScenarioLabComparisonCancelled>()),
      );
    },
  );
}

({
  ScenarioLabComparisonArtifactDescriptor descriptor,
  ScenarioLabSupplementalArtifactProvenance provenance,
})
_persist(
  FileSystemWorkspaceStore store,
  List<int> bytes, {
  required ScenarioLabSupplementalArtifactMediaType mediaType,
}) {
  final artifactDigest = store.putBlob(bytes);
  final provenance = _storeProvenance(
    store,
    artifactDigest: artifactDigest,
    size: bytes.length,
    mediaType: mediaType,
  );
  return (
    descriptor: ScenarioLabComparisonArtifactDescriptor(
      artifactDigest: artifactDigest,
      provenanceDigest: provenance.digest,
      classification: ArtifactClassification.internal,
    ),
    provenance: provenance,
  );
}

ScenarioLabSupplementalArtifactProvenance _storeProvenance(
  FileSystemWorkspaceStore store, {
  required Digest artifactDigest,
  required int size,
  required ScenarioLabSupplementalArtifactMediaType mediaType,
}) {
  final provenance = _provenance(
    artifactDigest: artifactDigest,
    size: size,
    mediaType: mediaType,
  );
  expect(store.putBlob(provenance.canonicalBytes), provenance.digest);
  return provenance;
}

ScenarioLabSupplementalArtifactProvenance _provenance({
  required Digest artifactDigest,
  required int size,
  required ScenarioLabSupplementalArtifactMediaType mediaType,
}) => ScenarioLabSupplementalArtifactProvenance(
  artifactDigest: artifactDigest,
  size: size,
  mediaType: mediaType,
  classification: ArtifactClassification.internal,
  sourceId: ScenarioLabSupplementalArtifactSourceId(
    'delivery-lab.dashboard-ready-baseline',
  ),
  importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
    'delivery-lab.baseline-v1',
  ),
);

List<int> _semantics(List<Map<String, Object?>> nodes) => utf8.encode(
  '${const JcsCanonicalizer().canonicalize(<String, Object?>{'schemaVersion': 1, 'kind': 'AndroidSemanticsSnapshot', 'privacy': 'hashedTextV1', 'nodes': nodes})}\n',
);

File _casFile(FileSystemWorkspaceStore store, Digest digest) => File(
  p.join(
    store.stateRoot,
    'cas',
    'sha256',
    digest.value.substring('sha256:'.length),
  ),
);

final _runId = ScenarioLabRunId('run-supplemental-1');

final class _Cancellation implements ScenarioLabCancellationSignal {
  _Cancellation({this.cancelled = false});

  final bool cancelled;
  final Completer<void> _completer = Completer<void>();

  @override
  bool get isCancelled => cancelled;

  @override
  Future<void> get whenCancelled =>
      cancelled ? Future<void>.value() : _completer.future;
}
