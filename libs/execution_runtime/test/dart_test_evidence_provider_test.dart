import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('ingests normalized results and explicitly referenced artifacts', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-test-provider-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final artifactBytes = utf8.encode('{"observed":true}');
    Directory(p.join(workspace.path, 'artifacts')).createSync();
    File(
      p.join(workspace.path, 'artifacts', 'result.json'),
    ).writeAsBytesSync(artifactBytes);
    final lines = <String>[
      '{"protocolVersion":"0.1.1","runnerVersion":"1.31.0","pid":1,"type":"start","time":0}',
      '{"suite":{"id":0,"platform":"vm","path":"tests/sample_test.dart"},"type":"suite","time":0}',
      '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":4}',
      jsonEncode(<String, Object?>{
        'testID': 1,
        'message':
            'TEST_ARTIFACT_JSON:{"path":"artifacts/result.json","mediaType":"application/json","classification":"internal","role":"test-output"}',
        'type': 'print',
        'time': 5,
      }),
      '{"success":true,"type":"done","time":6}',
    ];
    final provider = DartTestEvidenceProvider(workspaceRoot: workspace.path);

    final summary = await provider.ingest(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode('${lines.join('\n')}\n'),
      ]),
      exitCode: 0,
    );

    expect(summary.success, isTrue);
    expect(summary.total, 1);
    expect(summary.referencedArtifacts, hasLength(1));
    final store = FileSystemWorkspaceStore(workspaceRoot: workspace.path);
    expect(
      store.readBlob(summary.referencedArtifacts.single.digest),
      artifactBytes,
    );
    final normalized = utf8.decode(
      store.readBlob(summary.reportArtifact.digest)!,
    );
    expect(normalized, isNot(contains('result.json')));
    expect(normalized, isNot(contains(workspace.path)));
  });

  test('rejects traversal markers and incomplete reporter streams', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-test-provider-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final provider = DartTestEvidenceProvider(workspaceRoot: workspace.path);
    final prefix = <String>[
      '{"protocolVersion":"0.1.1","runnerVersion":"1.31.0","type":"start","time":0}',
      '{"suite":{"id":0,"platform":"vm","path":"test.dart"},"type":"suite","time":0}',
    ];
    final traversal = <String>[
      ...prefix,
      jsonEncode(<String, Object?>{
        'message':
            'TEST_ARTIFACT_JSON:{"path":"../secret","mediaType":"text/plain","classification":"sensitive","role":"unsafe"}',
        'type': 'print',
      }),
      '{"success":true,"type":"done","time":1}',
    ];

    await expectLater(
      provider.ingest(
        Stream<List<int>>.value(utf8.encode('${traversal.join('\n')}\n')),
        exitCode: 0,
      ),
      throwsFormatException,
    );
    await expectLater(
      provider.ingest(
        Stream<List<int>>.value(utf8.encode('${prefix.join('\n')}\n')),
        exitCode: 0,
      ),
      throwsFormatException,
    );
  });

  test('collects the real Dart test machine reporter', () async {
    final repository = _repositoryRoot();
    final provider = DartTestEvidenceProvider(workspaceRoot: repository);

    final summary = await provider.collect(
      runner: DartTestRunner.dart,
      targets: const <String>['libs/testing_support/test/testkit_test.dart'],
      timeout: const Duration(seconds: 30),
    );

    expect(summary.success, isTrue);
    expect(summary.total, 1);
    expect(summary.platforms, contains('vm'));
  });

  test(
    'rejects a workspace file that could be parsed as a runner flag',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-test-provider-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      File(p.join(workspace.path, '--help')).writeAsStringSync('not a target');
      final provider = DartTestEvidenceProvider(workspaceRoot: workspace.path);

      await expectLater(
        provider.collect(
          runner: DartTestRunner.dart,
          targets: const <String>['--help'],
        ),
        throwsFormatException,
      );
    },
  );
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
