import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:execution_runtime/src/lab/filesystem_scenario_lab_run_store.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('FilesystemScenarioLabRunStore', () {
    test('persists an idempotent, canonical and digest-bound journal', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final store = FilesystemScenarioLabRunStore(rootPath: root.path);

      final first = store.register(
        request: fixture.request,
        initialSnapshot: fixture.initial,
      );
      final retry = store.register(
        request: fixture.request,
        initialSnapshot: fixture.initial,
      );
      expect(first.created, isTrue);
      expect(retry.created, isFalse);
      expect(retry.run.latest.digest, fixture.initial.digest);

      expect(
        () => store.register(
          request: _request(requestedAtMinute: 1),
          initialSnapshot: fixture.initial,
        ),
        throwsA(isA<ScenarioLabRequestConflict>()),
      );

      store
        ..append(fixture.starting)
        ..append(fixture.running)
        ..append(fixture.terminal)
        ..complete(fixture.result);

      final reopened = FilesystemScenarioLabRunStore(rootPath: root.path);
      final persisted = reopened.requireRun(fixture.initial.runId);
      expect(persisted.interrupted, isFalse);
      expect(persisted.result?.digest, fixture.result.digest);
      expect(persisted.snapshots.map((snapshot) => snapshot.sequence), <int>[
        0,
        1,
        2,
        3,
      ]);

      final raw = File(reopened.stateFilePath).readAsStringSync();
      final decoded = jsonDecode(raw);
      expect(raw, '${const JcsCanonicalizer().canonicalize(decoded)}\n');
      final document = decoded as Map<String, Object?>;
      expect(document['entryCount'], 5);
      expect(document['headDigest'], isA<String>());
      expect(document['digest'], isA<String>());
      expect(raw.toLowerCase(), isNot(contains('nonce')));
      expect(raw.toLowerCase(), isNot(contains('token')));
      expect(raw.toLowerCase(), isNot(contains('uri')));
      expect(raw, isNot(contains('://')));
    });

    test('restart closes an unfinished generation as interrupted', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final original = FilesystemScenarioLabRunStore(rootPath: root.path);
      original.register(
        request: fixture.request,
        initialSnapshot: fixture.initial,
      );

      final restarted = FilesystemScenarioLabRunStore(rootPath: root.path);
      final interrupted = restarted.requireRun(fixture.initial.runId);
      expect(interrupted.interrupted, isTrue);
      expect(interrupted.isClosed, isTrue);
      expect(interrupted.result, isNull);
      expect(interrupted.latest.digest, fixture.initial.digest);
      expect(interrupted.latest.state, ScenarioLabRunState.queued);
      expect(() => restarted.append(fixture.starting), throwsStateError);
      expect(
        restarted
            .register(
              request: fixture.request,
              initialSnapshot: fixture.initial,
            )
            .run
            .interrupted,
        isTrue,
      );

      final once =
          jsonDecode(File(restarted.stateFilePath).readAsStringSync())
              as Map<String, Object?>;
      expect(once['entryCount'], 2);
      final restartedAgain = FilesystemScenarioLabRunStore(rootPath: root.path);
      final twice =
          jsonDecode(File(restartedAgain.stateFilePath).readAsStringSync())
              as Map<String, Object?>;
      expect(twice['entryCount'], 2, reason: 'interruption is idempotent');
    });

    test('interrupt rolls a provisional terminal snapshot back atomically', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final original = FilesystemScenarioLabRunStore(rootPath: root.path);
      original
        ..register(request: fixture.request, initialSnapshot: fixture.initial)
        ..append(fixture.starting)
        ..append(fixture.running)
        ..append(fixture.terminal);

      expect(original.interrupt(fixture.initial.runId), isTrue);

      final reopened = FilesystemScenarioLabRunStore(rootPath: root.path);
      final recovered = reopened.requireRun(fixture.initial.runId);
      expect(recovered.interrupted, isTrue);
      expect(recovered.result, isNull);
      expect(recovered.latest.digest, fixture.running.digest);
      expect(recovered.latest.state.isTerminal, isFalse);
      expect(recovered.snapshots.map((snapshot) => snapshot.sequence), <int>[
        0,
        1,
        2,
      ]);
      expect(
        () => ScenarioLabRunObservation(
          runId: fixture.initial.runId,
          disposition: ScenarioLabRunDisposition.interrupted,
          afterSequence: 1,
          current: recovered.latest,
          observations: <ScenarioLabRunSnapshot>[recovered.latest],
          hasMore: false,
        ),
        returnsNormally,
        reason: 'recovery must remain representable by the unchanged v1 wire',
      );

      final document =
          jsonDecode(File(reopened.stateFilePath).readAsStringSync())
              as Map<String, Object?>;
      expect(document['entryCount'], 4);
      expect(
        File(reopened.stateFilePath).readAsStringSync(),
        isNot(contains(fixture.terminal.digest.value)),
      );
    });

    test('reopen rejects interruption appended after a terminal snapshot', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final original = FilesystemScenarioLabRunStore(rootPath: root.path);
      original
        ..register(request: fixture.request, initialSnapshot: fixture.initial)
        ..append(fixture.starting)
        ..append(fixture.running)
        ..append(fixture.terminal);
      _appendInvalidTerminalInterruption(
        File(original.stateFilePath),
        fixture.terminal,
      );

      expect(
        () => FilesystemScenarioLabRunStore(rootPath: root.path),
        throwsFormatException,
      );
    });

    test('failed result commit reopens at the non-terminal interruption', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final writer = _ControllableAtomicWriter();
      final store = FilesystemScenarioLabRunStore(
        rootPath: root.path,
        writer: writer,
      );
      store
        ..register(request: fixture.request, initialSnapshot: fixture.initial)
        ..append(fixture.starting)
        ..append(fixture.running)
        ..append(fixture.terminal);
      final provisional = File(store.stateFilePath).readAsBytesSync();

      writer.failNext = true;
      expect(
        () => store.complete(fixture.result),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(store.stateFilePath).readAsBytesSync(), provisional);
      final provisionalRun = store.requireRun(fixture.initial.runId);
      expect(provisionalRun.isClosed, isTrue);
      expect(provisionalRun.hasUncommittedTerminalSnapshot, isTrue);

      expect(store.interrupt(fixture.initial.runId), isTrue);
      final live = store.requireRun(fixture.initial.runId);
      expect(live.interrupted, isTrue);
      expect(live.result, isNull);
      expect(live.latest.digest, fixture.running.digest);
      expect(live.latest.state.isTerminal, isFalse);

      final reopened = FilesystemScenarioLabRunStore(rootPath: root.path);
      final recovered = reopened.requireRun(fixture.initial.runId);
      expect(recovered.interrupted, isTrue);
      expect(recovered.result, isNull, reason: 'recovery cannot invent result');
      expect(recovered.latest.digest, fixture.running.digest);
      expect(recovered.latest.state.isTerminal, isFalse);
    });

    test('failed recovery replacement remains retryable and fail-closed', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final original = FilesystemScenarioLabRunStore(rootPath: root.path);
      original
        ..register(request: fixture.request, initialSnapshot: fixture.initial)
        ..append(fixture.starting)
        ..append(fixture.running)
        ..append(fixture.terminal);
      final provisional = File(original.stateFilePath).readAsBytesSync();
      final failingWriter = _ControllableAtomicWriter()..failNext = true;

      expect(
        () => FilesystemScenarioLabRunStore(
          rootPath: root.path,
          writer: failingWriter,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(original.stateFilePath).readAsBytesSync(), provisional);

      final retried = FilesystemScenarioLabRunStore(rootPath: root.path);
      final recovered = retried.requireRun(fixture.initial.runId);
      expect(recovered.interrupted, isTrue);
      expect(recovered.result, isNull);
      expect(recovered.latest.digest, fixture.running.digest);
    });

    test(
      'recovery rejects a digest-consistent invalid terminal preparation',
      () {
        final root = _temporaryRoot();
        addTearDown(() => _delete(root));
        final fixture = _runFixture();
        final store = FilesystemScenarioLabRunStore(rootPath: root.path);
        store
          ..register(request: fixture.request, initialSnapshot: fixture.initial)
          ..append(fixture.starting)
          ..append(fixture.running)
          ..append(fixture.terminal);
        _rewriteTerminalSequence(File(store.stateFilePath), sequence: 99);

        expect(
          () => FilesystemScenarioLabRunStore(rootPath: root.path),
          throwsFormatException,
          reason: 'recovery must validate before discarding a preparation',
        );
      },
    );

    test('two isolates serialize the same idempotent reservation', () async {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final requestJson = fixture.request.toJson();
      final snapshotJson = fixture.initial.toJson();

      final results = await Future.wait(<Future<bool>>[
        Isolate.run(
          () => _registerFromJson(root.path, requestJson, snapshotJson),
        ),
        Isolate.run(
          () => _registerFromJson(root.path, requestJson, snapshotJson),
        ),
      ]);

      expect(results.where((created) => created), hasLength(1));
      final reopened = FilesystemScenarioLabRunStore(rootPath: root.path);
      expect(reopened.length, 1);
      expect(
        reopened.requireRun(fixture.initial.runId).request.digest,
        fixture.request.digest,
      );
    });

    test('an old guard owned by a live isolate is never stolen', () async {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final first = _runFixture(suffix: '-first');
      final second = _runFixture(suffix: '-second');
      final holderEntered = File('${root.path}/holder-entered');
      final holderRelease = File('${root.path}/holder-release');
      final contenderEntered = File('${root.path}/contender-entered');

      final holder = Isolate.run(
        () => _registerWithBlockingWriter(
          root.path,
          first.request.toJson(),
          first.initial.toJson(),
          holderEntered.path,
          holderRelease.path,
        ),
      );
      await _waitForFile(holderEntered);
      final guard = root
          .listSync(followLinks: false)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('.lock.guard'));
      final liveClaim = guard.readAsStringSync();
      expect(liveClaim, startsWith('$pid-'));
      guard.setLastModifiedSync(
        DateTime.now().subtract(const Duration(seconds: 31)),
      );

      final contender = Isolate.run(
        () => _registerWithMarkerWriter(
          root.path,
          second.request.toJson(),
          second.initial.toJson(),
          contenderEntered.path,
        ),
      );
      try {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          contenderEntered.existsSync(),
          isFalse,
          reason: 'a live owner must retain the in-process guard',
        );
        expect(guard.existsSync(), isTrue);
        expect(guard.readAsStringSync(), liveClaim);
      } finally {
        holderRelease.createSync();
      }

      expect(await holder, isTrue);
      expect(await contender, isTrue);
      final reopened = FilesystemScenarioLabRunStore(rootPath: root.path);
      expect(
        reopened.runs.map((run) => run.latest.runId.value).toSet(),
        <String>{first.initial.runId.value, second.initial.runId.value},
      );
    });

    test('recovers an old incomplete guard when proc proves no owner', () {
      if (!Directory('/proc').existsSync()) return;
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final guard = File('${root.path}/scenario-lab-runs.lock.guard')
        ..createSync()
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(seconds: 31)),
        );

      final store = FilesystemScenarioLabRunStore(rootPath: root.path);

      expect(store.length, 0);
      expect(guard.existsSync(), isFalse);
    });

    test('detects canonical tamper without accepting rewritten payload', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final store = FilesystemScenarioLabRunStore(rootPath: root.path);
      store.register(
        request: fixture.request,
        initialSnapshot: fixture.initial,
      );
      final file = File(store.stateFilePath);
      final tampered = file.readAsStringSync().replaceFirst(
        'request-1',
        'request-x',
      );
      expect(tampered, isNot(file.readAsStringSync()));
      file.writeAsStringSync(tampered, flush: true);

      expect(
        () => FilesystemScenarioLabRunStore(rootPath: root.path),
        throwsFormatException,
      );
    });

    test('detects a canonical but logically truncated hash chain', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final store = FilesystemScenarioLabRunStore(rootPath: root.path);
      store
        ..register(request: fixture.request, initialSnapshot: fixture.initial)
        ..append(fixture.starting)
        ..append(fixture.running)
        ..append(fixture.terminal)
        ..complete(fixture.result);
      final file = File(store.stateFilePath);
      final document =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final entries = document['entries']! as List<Object?>;
      entries.removeLast();
      document['entryCount'] = entries.length;
      file.writeAsStringSync(
        '${const JcsCanonicalizer().canonicalize(document)}\n',
        flush: true,
      );

      expect(
        () => FilesystemScenarioLabRunStore(rootPath: root.path),
        throwsFormatException,
      );
    });

    test('detects a truncated journal and never treats it as empty', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final store = FilesystemScenarioLabRunStore(rootPath: root.path);
      store.register(
        request: fixture.request,
        initialSnapshot: fixture.initial,
      );
      final file = File(store.stateFilePath);
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2), flush: true);

      expect(
        () => FilesystemScenarioLabRunStore(rootPath: root.path),
        throwsFormatException,
      );
    });

    test('failed staging write leaves disk and live view unchanged', () {
      final root = _temporaryRoot();
      addTearDown(() => _delete(root));
      final fixture = _runFixture();
      final writer = _ControllableAtomicWriter();
      final store = FilesystemScenarioLabRunStore(
        rootPath: root.path,
        writer: writer,
      );
      store.register(
        request: fixture.request,
        initialSnapshot: fixture.initial,
      );
      final before = File(store.stateFilePath).readAsBytesSync();

      writer.failNext = true;
      expect(
        () => store.append(fixture.starting),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(store.stateFilePath).readAsBytesSync(), before);
      expect(store.requireRun(fixture.initial.runId).latest.sequence, 0);
      expect(
        root
            .listSync(followLinks: false)
            .where((entity) => entity.path.contains('.test-staging')),
        isEmpty,
      );
    });
  });
}

bool _registerFromJson(
  String rootPath,
  Map<String, Object?> requestJson,
  Map<String, Object?> snapshotJson,
) => FilesystemScenarioLabRunStore(rootPath: rootPath)
    .register(
      request: ScenarioLabRunStartRequest.fromJson(requestJson),
      initialSnapshot: ScenarioLabRunSnapshot.fromJson(snapshotJson),
    )
    .created;

bool _registerWithBlockingWriter(
  String rootPath,
  Map<String, Object?> requestJson,
  Map<String, Object?> snapshotJson,
  String enteredPath,
  String releasePath,
) =>
    FilesystemScenarioLabRunStore(
          rootPath: rootPath,
          writer: _BlockingAtomicWriter(
            enteredPath: enteredPath,
            releasePath: releasePath,
          ),
        )
        .register(
          request: ScenarioLabRunStartRequest.fromJson(requestJson),
          initialSnapshot: ScenarioLabRunSnapshot.fromJson(snapshotJson),
        )
        .created;

bool _registerWithMarkerWriter(
  String rootPath,
  Map<String, Object?> requestJson,
  Map<String, Object?> snapshotJson,
  String enteredPath,
) =>
    FilesystemScenarioLabRunStore(
          rootPath: rootPath,
          writer: _MarkerAtomicWriter(enteredPath),
        )
        .register(
          request: ScenarioLabRunStartRequest.fromJson(requestJson),
          initialSnapshot: ScenarioLabRunSnapshot.fromJson(snapshotJson),
        )
        .created;

Future<void> _waitForFile(File file) async {
  final waiting = Stopwatch()..start();
  while (!file.existsSync()) {
    if (waiting.elapsed > const Duration(seconds: 5)) {
      throw StateError('Timed out waiting for ${file.path}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _BlockingAtomicWriter implements ScenarioLabAtomicFileWriter {
  const _BlockingAtomicWriter({
    required this.enteredPath,
    required this.releasePath,
  });

  final String enteredPath;
  final String releasePath;

  @override
  void write({required File destination, required List<int> bytes}) {
    File(enteredPath).createSync();
    final waiting = Stopwatch()..start();
    while (!File(releasePath).existsSync()) {
      if (waiting.elapsed > const Duration(seconds: 5)) {
        throw StateError('Timed out waiting to release blocking writer');
      }
      sleep(const Duration(milliseconds: 1));
    }
    const DefaultScenarioLabAtomicFileWriter().write(
      destination: destination,
      bytes: bytes,
    );
  }
}

final class _MarkerAtomicWriter implements ScenarioLabAtomicFileWriter {
  const _MarkerAtomicWriter(this.enteredPath);

  final String enteredPath;

  @override
  void write({required File destination, required List<int> bytes}) {
    File(enteredPath).createSync();
    const DefaultScenarioLabAtomicFileWriter().write(
      destination: destination,
      bytes: bytes,
    );
  }
}

final class _RunFixture {
  const _RunFixture({
    required this.request,
    required this.initial,
    required this.starting,
    required this.running,
    required this.terminal,
    required this.result,
  });

  final ScenarioLabRunStartRequest request;
  final ScenarioLabRunSnapshot initial;
  final ScenarioLabRunSnapshot starting;
  final ScenarioLabRunSnapshot running;
  final ScenarioLabRunSnapshot terminal;
  final ScenarioLabRunResult result;
}

_RunFixture _runFixture({String suffix = ''}) {
  final request = _request(suffix: suffix);
  final runId = ScenarioLabRunId('run-1$suffix');
  final catalogDigest = Digest.semantic('catalog');
  final initial = ScenarioLabRunSnapshot(
    runId: runId,
    startRequestDigest: request.digest,
    contentSetDigest: request.expectedContentSetDigest,
    catalogDigest: catalogDigest,
    scenarioLabManifestDigest: request.expectedScenarioLabManifestDigest,
    scenarioId: request.scenarioId,
    scriptId: request.scriptId,
    sequence: 0,
    observedAt: _time(0),
    state: ScenarioLabRunState.queued,
    steps: <ScenarioLabStepSnapshot>[
      ScenarioLabStepSnapshot(
        stepId: 'attach',
        state: ScenarioLabStepState.pending,
      ),
    ],
    cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.pending),
  );
  final runtimeInputs = ScenarioLabRuntimeInputBinding(
    executionFingerprintDigest: Digest.semantic('fingerprint'),
    executionTargetId: 'chrome',
  );
  final starting = ScenarioLabRunSnapshot(
    runId: runId,
    startRequestDigest: request.digest,
    contentSetDigest: request.expectedContentSetDigest,
    catalogDigest: catalogDigest,
    scenarioLabManifestDigest: request.expectedScenarioLabManifestDigest,
    scenarioId: request.scenarioId,
    scriptId: request.scriptId,
    sequence: 1,
    observedAt: _time(1),
    state: ScenarioLabRunState.starting,
    runtimeInputs: runtimeInputs,
    steps: <ScenarioLabStepSnapshot>[
      ScenarioLabStepSnapshot(
        stepId: 'attach',
        state: ScenarioLabStepState.running,
        startedAt: _time(1),
      ),
    ],
    cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.pending),
  );
  final succeededStep = ScenarioLabStepSnapshot(
    stepId: 'attach',
    state: ScenarioLabStepState.succeeded,
    startedAt: _time(1),
    completedAt: _time(2),
    terminalCause: ScenarioLabStepTerminalCause.completed,
  );
  final running = ScenarioLabRunSnapshot(
    runId: runId,
    startRequestDigest: request.digest,
    contentSetDigest: request.expectedContentSetDigest,
    catalogDigest: catalogDigest,
    scenarioLabManifestDigest: request.expectedScenarioLabManifestDigest,
    scenarioId: request.scenarioId,
    scriptId: request.scriptId,
    sequence: 2,
    observedAt: _time(2),
    state: ScenarioLabRunState.running,
    runtimeInputs: runtimeInputs,
    steps: <ScenarioLabStepSnapshot>[succeededStep],
    cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.pending),
  );
  final terminal = ScenarioLabRunSnapshot(
    runId: runId,
    startRequestDigest: request.digest,
    contentSetDigest: request.expectedContentSetDigest,
    catalogDigest: catalogDigest,
    scenarioLabManifestDigest: request.expectedScenarioLabManifestDigest,
    scenarioId: request.scenarioId,
    scriptId: request.scriptId,
    sequence: 3,
    observedAt: _time(3),
    state: ScenarioLabRunState.succeeded,
    runtimeInputs: runtimeInputs,
    steps: <ScenarioLabStepSnapshot>[succeededStep],
    cleanup: ScenarioLabCleanupResult(
      state: ScenarioLabCleanupState.notRequired,
    ),
    terminalCause: ScenarioLabTerminalCause.completed,
  );
  return _RunFixture(
    request: request,
    initial: initial,
    starting: starting,
    running: running,
    terminal: terminal,
    result: ScenarioLabRunResult(
      finalSnapshot: terminal,
      startedAt: _time(1),
      completedAt: _time(3),
      verificationState: VerificationState.notRun,
    ),
  );
}

ScenarioLabRunStartRequest _request({
  int requestedAtMinute = 0,
  String suffix = '',
}) => ScenarioLabRunStartRequest(
  requestId: ScenarioLabRunRequestId('request-1$suffix'),
  expectedContentSetDigest: Digest.semantic('content-set'),
  expectedScenarioLabManifestDigest: Digest.semantic('lab'),
  scenarioId: ScenarioId('ready'),
  scriptId: ScenarioScriptId('exercise-ready'),
  requestedAt: _time(requestedAtMinute),
);

DateTime _time(int minute) => DateTime.utc(2026, 8, 14, 12, minute);

Directory _temporaryRoot() =>
    Directory.systemTemp.createTempSync('workspace-scenario-lab-store-');

void _delete(Directory directory) {
  if (directory.existsSync()) directory.deleteSync(recursive: true);
}

void _appendInvalidTerminalInterruption(
  File file,
  ScenarioLabRunSnapshot terminal,
) {
  final document = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final entries = document['entries']! as List<Object?>;
  final eventBody = <String, Object?>{
    'index': entries.length,
    'previousDigest': document['headDigest'],
    'type': 'interrupted',
    'runId': terminal.runId.value,
    'payload': <String, Object?>{'latestSnapshotDigest': terminal.digest.value},
  };
  final event = <String, Object?>{
    ...eventBody,
    'digest': Digest.semantic(eventBody).value,
  };
  entries.add(event);
  document
    ..['entryCount'] = entries.length
    ..['headDigest'] = event['digest'];
  final documentBody = Map<String, Object?>.of(document)..remove('digest');
  document['digest'] = Digest.semantic(documentBody).value;
  file.writeAsStringSync(
    '${const JcsCanonicalizer().canonicalize(document)}\n',
    flush: true,
  );
}

void _rewriteTerminalSequence(File file, {required int sequence}) {
  final document = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final entries = document['entries']! as List<Object?>;
  final terminalEvent = entries.last! as Map<String, Object?>;
  final payload = terminalEvent['payload']! as Map<String, Object?>;
  final snapshot = payload['snapshot']! as Map<String, Object?>;
  snapshot['sequence'] = sequence;
  _replaceSemanticDigest(snapshot);
  _replaceSemanticDigest(terminalEvent);
  document['headDigest'] = terminalEvent['digest'];
  _replaceSemanticDigest(document);
  file.writeAsStringSync(
    '${const JcsCanonicalizer().canonicalize(document)}\n',
    flush: true,
  );
}

void _replaceSemanticDigest(Map<String, Object?> document) {
  final body = Map<String, Object?>.of(document)..remove('digest');
  document['digest'] = Digest.semantic(body).value;
}

final class _ControllableAtomicWriter implements ScenarioLabAtomicFileWriter {
  var failNext = false;
  final ScenarioLabAtomicFileWriter _delegate =
      const DefaultScenarioLabAtomicFileWriter();

  @override
  void write({required File destination, required List<int> bytes}) {
    if (!failNext) {
      _delegate.write(destination: destination, bytes: bytes);
      return;
    }
    failNext = false;
    final staging = File('${destination.path}.test-staging');
    try {
      staging.writeAsBytesSync(bytes, flush: true);
      throw FileSystemException('Injected atomic write failure', staging.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }
}
