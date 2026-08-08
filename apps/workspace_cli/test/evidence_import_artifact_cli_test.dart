import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:workspace_cli/workspace_cli.dart';

void main() {
  test('imports exact artifact and provenance bytes idempotently', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-artifact-import-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final input = File(p.join(workspace.path, 'baselines', 'dashboard.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(_pngBytes);
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);
    final arguments = <String>[
      '--json',
      'evidence',
      'import-artifact',
      '--input',
      p.relative(input.path, from: workspace.path),
      '--media-type',
      ScenarioLabSupplementalArtifactMediaType.png.value,
      '--classification',
      ArtifactClassification.internal.name,
      '--source-id',
      'delivery-lab.dashboard-ready',
      '--import-policy',
      'delivery-lab.baseline-v1',
    ];

    final first = await cli.run(arguments);
    final second = await cli.run(arguments);

    expect(first.exitCode, 0, reason: first.stderr);
    expect(second.exitCode, 0, reason: second.stderr);
    expect(second.stdout, first.stdout, reason: 'the import is deterministic');
    final result = _result(first);
    expect(result, hasLength(7));
    expect(result['artifactDigest'], Digest.bytes(_pngBytes).value);
    expect(result['provenanceDigest'], startsWith('sha256:'));
    expect(result['size'], _pngBytes.length);
    expect(result['mediaType'], 'image/png');
    expect(result['classification'], 'internal');
    expect(result['sourceId'], 'delivery-lab.dashboard-ready');
    expect(result['importPolicyId'], 'delivery-lab.baseline-v1');
    expect(result, isNot(contains('input')));
    expect(result, isNot(contains('path')));
    expect(jsonEncode(result), isNot(contains(workspace.path)));

    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    final artifactDigest = Digest(result['artifactDigest']! as String);
    final provenanceDigest = Digest(result['provenanceDigest']! as String);
    expect(store.readBlob(artifactDigest), _pngBytes);
    final provenanceBytes = store.readBlob(provenanceDigest)!;
    expect(utf8.decode(provenanceBytes), isNot(endsWith('\n')));
    final provenance = ScenarioLabSupplementalArtifactProvenance.fromJson(
      jsonDecode(utf8.decode(provenanceBytes)),
      expectedDigest: provenanceDigest,
    );
    expect(provenance.artifactDigest, artifactDigest);
    expect(provenance.size, _pngBytes.length);
    expect(provenance.sourceId.value, 'delivery-lab.dashboard-ready');
    expect(provenance.importPolicyId.value, 'delivery-lab.baseline-v1');

    final importRoot = _importRootFile(store, provenanceDigest);
    expect(importRoot.existsSync(), isTrue);
    final importRootText = importRoot.readAsStringSync();
    final importRootJson = jsonDecode(importRootText) as Map<String, Object?>;
    expect(importRootJson, hasLength(4));
    expect(importRootJson['schemaVersion'], 1);
    expect(importRootJson['kind'], 'SupplementalArtifactImportRoot');
    expect(importRootJson['artifactDigest'], artifactDigest.value);
    expect(importRootJson['provenanceDigest'], provenanceDigest.value);
    expect(
      importRootText,
      '${const JcsCanonicalizer().canonicalize(importRootJson)}\n',
    );
    expect(importRootText, isNot(contains(workspace.path)));
    expect(
      importRoot.parent.listSync(followLinks: false).whereType<File>(),
      hasLength(1),
      reason: 'an identical retry must reuse its owned retention root',
    );

    final index =
        jsonDecode(utf8.decode(store.readStateBytes('cas/index.json')!))
            as Map<String, Object?>;
    final blobs = (index['blobs']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(blobs, hasLength(2));
    expect(blobs.map((blob) => blob['digest']).toSet(), <Object?>{
      artifactDigest.value,
      provenanceDigest.value,
    });
  });

  test('uses the configured workspace root when invoked in a child', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-artifact-configured-root-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    Directory(p.join(workspace.path, '.experience')).createSync();
    File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications: {}
kit:
  profile: journey-preview
  modules: {}
''');
    final child = Directory(p.join(workspace.path, 'tools', 'baselines'))
      ..createSync(recursive: true);
    File(p.join(child.path, 'dashboard.png')).writeAsBytesSync(_pngBytes);
    final cli = WorkspaceCli(workspaceDirectory: child.path);

    final imported = await cli.run(_arguments('dashboard.png'));

    expect(imported.exitCode, 0, reason: imported.stderr);
    final result = _result(imported);
    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    expect(
      store.readBlob(Digest(result['artifactDigest']! as String)),
      _pngBytes,
    );
    expect(
      store.readBlob(Digest(result['provenanceDigest']! as String)),
      isNotNull,
    );
    expect(
      Directory(p.join(child.path, '.dart_tool')).existsSync(),
      isFalse,
      reason: 'the invocation directory must not become a second CAS root',
    );
  });

  test('fails closed when an existing CAS blob is tampered', () async {
    for (final digestField in <String>['artifactDigest', 'provenanceDigest']) {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-cli-artifact-tamper-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      File(p.join(workspace.path, 'baseline.png')).writeAsBytesSync(_pngBytes);
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);
      final arguments = _arguments('baseline.png');
      final imported = await cli.run(arguments);
      expect(imported.exitCode, 0, reason: imported.stderr);
      final tamperedDigest = Digest(_result(imported)[digestField]! as String);
      final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
      final tamperedFile = File(
        p.join(
          store.stateRoot,
          'cas',
          'sha256',
          tamperedDigest.value.substring('sha256:'.length),
        ),
      )..writeAsBytesSync(const <int>[0], flush: true);

      final repeated = await cli.run(arguments);

      expect(repeated.exitCode, 3);
      expect(repeated.stdout, isEmpty);
      final failure = jsonDecode(repeated.stderr) as Map<String, Object?>;
      final failures = failure['failures']! as List<Object?>;
      expect(
        (failures.single! as Map<String, Object?>)['code'],
        'EVIDENCE_PRECONDITION',
      );
      expect(tamperedFile.readAsBytesSync(), const <int>[0]);
    }
  });

  test('does not overwrite a conflicting owned import root', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-artifact-root-conflict-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    File(p.join(workspace.path, 'baseline.png')).writeAsBytesSync(_pngBytes);
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);
    final arguments = _arguments('baseline.png');
    final imported = await cli.run(arguments);
    expect(imported.exitCode, 0, reason: imported.stderr);
    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    final root = _importRootFile(
      store,
      Digest(_result(imported)['provenanceDigest']! as String),
    )..writeAsStringSync('{}\n', flush: true);

    final repeated = await cli.run(arguments);

    expect(repeated.exitCode, 3);
    expect(repeated.stdout, isEmpty);
    final failure = jsonDecode(repeated.stderr) as Map<String, Object?>;
    expect(
      ((failure['failures']! as List<Object?>).single!
          as Map<String, Object?>)['code'],
      'EVIDENCE_PRECONDITION',
    );
    expect(root.readAsStringSync(), '{}\n');
  });

  test('retention preserves imported roots at t0 and t0 plus 25h', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-artifact-retention-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    File(p.join(workspace.path, 'baseline.png')).writeAsBytesSync(_pngBytes);
    final imported = await WorkspaceCli(
      workspaceDirectory: workspace.path,
    ).run(_arguments('baseline.png'));
    expect(imported.exitCode, 0, reason: imported.stderr);
    final result = _result(imported);
    final artifactDigest = Digest(result['artifactDigest']! as String);
    final provenanceDigest = Digest(result['provenanceDigest']! as String);
    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    late final Digest unreachable;
    store.withExclusiveLock(() {
      unreachable = store.putBlob(utf8.encode('unreachable-control'));
      store.rebuildCasIndex();
    });
    var now = DateTime.utc(2026, 8, 14, 12);
    final retention = LocalRetentionService(
      workspaceRoot: workspace.path,
      nowUtc: () => now,
    );

    final atT0 = retention.run(apply: true);

    expect(atT0.reachableBlobs, 2);
    expect(atT0.graceBlobs, 1);
    expect(atT0.deletedBlobs, 0);
    expect(store.readBlob(artifactDigest), _pngBytes);
    expect(store.readBlob(provenanceDigest), isNotNull);
    expect(store.readBlob(unreachable), isNotNull);

    now = now.add(const Duration(hours: 25));
    final afterGrace = retention.run(apply: true);

    expect(afterGrace.reachableBlobs, 2);
    expect(afterGrace.deletedBlobs, 1);
    expect(store.readBlob(artifactDigest), _pngBytes);
    expect(store.readBlob(provenanceDigest), isNotNull);
    expect(store.readBlob(unreachable), isNull);
    expect(_importRootFile(store, provenanceDigest).existsSync(), isTrue);
  });

  test('rejects outside, linked, non-file and out-of-budget inputs', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-artifact-path-',
    );
    final outside = Directory.systemTemp.createTempSync(
      'workspace-cli-artifact-outside-',
    );
    addTearDown(() {
      workspace.deleteSync(recursive: true);
      outside.deleteSync(recursive: true);
    });
    final valid = File(p.join(workspace.path, 'valid.png'))
      ..writeAsBytesSync(_pngBytes);
    final outsideFile = File(p.join(outside.path, 'outside.png'))
      ..writeAsBytesSync(_pngBytes);
    final empty = File(p.join(workspace.path, 'empty.png'))..createSync();
    final oversized = File(p.join(workspace.path, 'oversized.png'));
    final handle = oversized.openSync(mode: FileMode.write);
    handle.truncateSync(
      ScenarioLabSupplementalArtifactProvenance.maxArtifactBytes + 1,
    );
    handle.closeSync();
    final directory = Directory(p.join(workspace.path, 'not-a-file'))
      ..createSync();
    final invalidInputs = <String>[
      outsideFile.path,
      p.join('..', p.basename(outside.path), p.basename(outsideFile.path)),
      p.relative(empty.path, from: workspace.path),
      p.relative(oversized.path, from: workspace.path),
      p.relative(directory.path, from: workspace.path),
    ];
    if (!Platform.isWindows) {
      final directLink = Link(p.join(workspace.path, 'linked.png'))
        ..createSync(valid.path);
      final directoryLink = Link(p.join(workspace.path, 'linked-directory'))
        ..createSync(outside.path);
      invalidInputs
        ..add(p.relative(directLink.path, from: workspace.path))
        ..add(
          p.join(
            p.relative(directoryLink.path, from: workspace.path),
            p.basename(outsideFile.path),
          ),
        );
    }
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);

    for (final input in invalidInputs) {
      final result = await cli.run(_arguments(input));
      expect(result.exitCode, 2, reason: '$input: ${result.stderr}');
      expect(result.stdout, isEmpty, reason: input);
    }
    expect(
      Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
      isFalse,
      reason: 'rejected inputs must not allocate CAS state',
    );
  });

  test(
    'validates the closed media profile before allocating CAS state',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-cli-artifact-media-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      File(p.join(workspace.path, 'baseline.png')).writeAsBytesSync(_pngBytes);
      final semantics = File(p.join(workspace.path, 'semantics.json'))
        ..writeAsBytesSync(_semanticsBytes);
      final adjacentSemantics =
          File(p.join(workspace.path, 'adjacent-semantics.json'))
            ..writeAsStringSync(
              jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'kind': 'AndroidSemanticsSnapshot',
                'privacy': 'hashedTextV1',
                'nodes': <Object?>[
                  <String, Object?>{'sequence': 0},
                ],
              }),
            );
      final nonInteroperableSemantics =
          File(
            p.join(workspace.path, 'non-interoperable-semantics.json'),
          )..writeAsStringSync(
            '{"kind":"AndroidSemanticsSnapshot","nodes":[{"sequence":9007199254740992}],"privacy":"hashedTextV1","schemaVersion":1}\n',
          );
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);
      final invalid = <List<String>>[
        _arguments(
          'baseline.png',
          mediaType:
              ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1,
        ),
        _arguments(
          p.relative(semantics.path, from: workspace.path),
          mediaType: ScenarioLabSupplementalArtifactMediaType.png,
        ),
        _arguments(
          p.relative(adjacentSemantics.path, from: workspace.path),
          mediaType:
              ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1,
        ),
        _arguments(
          p.relative(nonInteroperableSemantics.path, from: workspace.path),
          mediaType:
              ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1,
        ),
      ];

      for (final arguments in invalid) {
        final result = await cli.run(arguments);
        expect(result.exitCode, 2, reason: result.stderr);
      }
      expect(
        Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
        isFalse,
      );

      final valid = await cli.run(
        _arguments(
          p.relative(semantics.path, from: workspace.path),
          mediaType:
              ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1,
        ),
      );
      expect(valid.exitCode, 0, reason: valid.stderr);
      expect(
        _result(valid)['mediaType'],
        ScenarioLabSupplementalArtifactMediaType.androidSemanticsV1.value,
      );
    },
  );

  test(
    'requires the closed media, classification and opaque ID flags',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-cli-artifact-flags-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      File(p.join(workspace.path, 'baseline.png')).writeAsBytesSync(_pngBytes);
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);
      final missingInput = <String>[..._arguments('baseline.png')]
        ..removeRange(3, 5);
      final invalidMedia = <String>[..._arguments('baseline.png')]
        ..[6] = 'application/octet-stream';
      final invalidClassification = <String>[..._arguments('baseline.png')]
        ..[8] = 'secret';
      final cases = <List<String>>[
        missingInput,
        invalidMedia,
        invalidClassification,
        _arguments('baseline.png', sourceId: '/tmp/baseline.png'),
        _arguments('baseline.png', importPolicy: 'HTTPS://policy.test'),
      ];

      for (final arguments in cases) {
        final result = await cli.run(arguments);
        expect(
          result.exitCode,
          2,
          reason: '${arguments.join(' ')}\n${result.stderr}',
        );
        expect(result.stdout, isEmpty);
        if (identical(arguments, invalidMedia) ||
            identical(arguments, invalidClassification)) {
          final failure = jsonDecode(result.stderr) as Map<String, Object?>;
          expect(failure['command'], 'evidence import-artifact');
          expect(failure['ok'], isFalse);
          expect(
            ((failure['failures']! as List<Object?>).single!
                as Map<String, Object?>)['code'],
            'AUTHORING_INVALID',
          );
        }
      }
      expect(
        Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
        isFalse,
        reason: 'invalid flags must not allocate CAS state',
      );
    },
  );
}

List<String> _arguments(
  String input, {
  String sourceId = 'delivery-lab.dashboard-ready',
  String importPolicy = 'delivery-lab.baseline-v1',
  ScenarioLabSupplementalArtifactMediaType mediaType =
      ScenarioLabSupplementalArtifactMediaType.png,
}) => <String>[
  '--json',
  'evidence',
  'import-artifact',
  '--input',
  input,
  '--media-type',
  mediaType.value,
  '--classification',
  ArtifactClassification.internal.name,
  '--source-id',
  sourceId,
  '--import-policy',
  importPolicy,
];

Map<String, Object?> _result(CliResult value) =>
    (jsonDecode(value.stdout) as Map<String, Object?>)['result']!
        as Map<String, Object?>;

File _importRootFile(FileSystemWorkspaceStore store, Digest provenanceDigest) =>
    File(
      p.join(
        store.stateRoot,
        'evidence',
        'import-artifact',
        'roots-v1',
        'sha256',
        '${provenanceDigest.value.substring('sha256:'.length)}.json',
      ),
    );

final List<int> _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
);

final List<int> _semanticsBytes = utf8.encode(
  '${const JcsCanonicalizer().canonicalize(<String, Object?>{
    'schemaVersion': 1,
    'kind': 'AndroidSemanticsSnapshot',
    'privacy': 'hashedTextV1',
    'nodes': <Object?>[
      <String, Object?>{'sequence': 0, 'textDigest': 'sha256:0000000000000000000000000000000000000000000000000000000000000000'},
    ],
  })}\n',
);
