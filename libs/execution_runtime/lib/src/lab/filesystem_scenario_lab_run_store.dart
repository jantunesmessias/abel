import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import 'scenario_lab_run_store.dart';

/// Injectable atomic replacement boundary used by the durable store.
abstract interface class ScenarioLabAtomicFileWriter {
  void write({required File destination, required List<int> bytes});
}

/// Flushes a unique staging file before atomically replacing the destination.
final class DefaultScenarioLabAtomicFileWriter
    implements ScenarioLabAtomicFileWriter {
  const DefaultScenarioLabAtomicFileWriter();

  @override
  void write({required File destination, required List<int> bytes}) {
    if (Link(destination.path).existsSync()) {
      throw FileSystemException(
        'Scenario Lab store state cannot be a symlink',
        destination.path,
      );
    }
    destination.parent.createSync(recursive: true);
    final staging = File(
      '${destination.path}.tmp-$pid-'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    if (FileSystemEntity.typeSync(staging.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Scenario Lab store staging path already exists',
        staging.path,
      );
    }
    try {
      staging.writeAsBytesSync(bytes, flush: true);
      staging.renameSync(destination.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
  }
}

/// JCS journal-backed Scenario Lab run store under one explicit root.
///
/// Opening a new instance is an ownership boundary. Any generation without a
/// committed result is closed by an `interrupted` store tombstone. The v1 run
/// snapshot remains unchanged because that wire has no interrupted terminal
/// cause and a queued snapshot cannot legally invent runtime inputs. A terminal
/// snapshot is a provisional journal tail until its exact result is present.
/// Recovery atomically rolls an uncommitted terminal tail back to the preceding
/// non-terminal observation before writing the interruption tombstone.
final class FilesystemScenarioLabRunStore implements ScenarioLabRunStore {
  factory FilesystemScenarioLabRunStore({
    required String rootPath,
    ScenarioLabAtomicFileWriter writer =
        const DefaultScenarioLabAtomicFileWriter(),
  }) {
    if (rootPath.trim().isEmpty) {
      throw ArgumentError.value(rootPath, 'rootPath', 'must not be empty');
    }
    final requested = Directory(rootPath).absolute;
    if (Link(requested.path).existsSync()) {
      throw FileSystemException(
        'Scenario Lab store root cannot be a symlink',
        requested.path,
      );
    }
    final type = FileSystemEntity.typeSync(requested.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Scenario Lab store root must be a directory',
        requested.path,
      );
    }
    requested.createSync(recursive: true);
    final root = Directory(requested.resolveSymbolicLinksSync());
    final store = FilesystemScenarioLabRunStore._(
      rootPath: root.path,
      writer: writer,
    );
    store._recoverOwnerlessRuns();
    return store;
  }

  FilesystemScenarioLabRunStore._({
    required this.rootPath,
    required this._writer,
  });

  static const int _maxStateBytes = 64 * 1024 * 1024;
  static const int _maxEntries = 1000000;
  static const String _stateName = 'scenario-lab-runs.journal.json';
  static const String _lockName = 'scenario-lab-runs.lock';
  static const String _guardName = 'scenario-lab-runs.lock.guard';
  static const Duration _guardTimeout = Duration(seconds: 30);

  final String rootPath;
  final ScenarioLabAtomicFileWriter _writer;

  String get stateFilePath => p.join(rootPath, _stateName);

  String get lockFilePath => p.join(rootPath, _lockName);

  String get _guardFilePath => p.join(rootPath, _guardName);

  @override
  int get length => _withExclusiveLock(() => _load().memory.length);

  @override
  ScenarioLabRunRegistration register({
    required ScenarioLabRunStartRequest request,
    required ScenarioLabRunSnapshot initialSnapshot,
  }) => _withExclusiveLock(() {
    final state = _load();
    final registration = state.memory.register(
      request: request,
      initialSnapshot: initialSnapshot,
    );
    if (!registration.created) return registration;
    final next = state.add(
      type: _JournalEventType.register,
      runId: initialSnapshot.runId,
      payload: <String, Object?>{
        'request': request.toJson(),
        'initialSnapshot': initialSnapshot.toJson(),
      },
    );
    _persist(next);
    return ScenarioLabRunRegistration(
      created: true,
      run: next.memory.requireRun(initialSnapshot.runId),
    );
  });

  @override
  ScenarioLabStoredRun? findByRequestId(ScenarioLabRunRequestId requestId) =>
      _withExclusiveLock(() => _load().memory.findByRequestId(requestId));

  @override
  ScenarioLabStoredRun? findByRunId(ScenarioLabRunId runId) =>
      _withExclusiveLock(() => _load().memory.findByRunId(runId));

  @override
  ScenarioLabStoredRun requireRun(ScenarioLabRunId runId) =>
      _withExclusiveLock(() => _load().memory.requireRun(runId));

  @override
  List<ScenarioLabStoredRun> get runs =>
      _withExclusiveLock(() => _load().memory.runs);

  @override
  void append(ScenarioLabRunSnapshot snapshot) => _withExclusiveLock(() {
    final state = _load();
    state.memory.append(snapshot);
    _persist(
      state.add(
        type: _JournalEventType.snapshot,
        runId: snapshot.runId,
        payload: <String, Object?>{'snapshot': snapshot.toJson()},
      ),
    );
  });

  @override
  void complete(ScenarioLabRunResult result) => _withExclusiveLock(() {
    final state = _load();
    final existing = state.memory.requireRun(result.finalSnapshot.runId).result;
    state.memory.complete(result);
    if (existing != null) return;

    _persist(
      state.add(
        type: _JournalEventType.result,
        runId: result.finalSnapshot.runId,
        payload: <String, Object?>{'result': result.toJson()},
      ),
    );
  });

  @override
  bool interrupt(ScenarioLabRunId runId) => _withExclusiveLock(() {
    final state = _load(recoverDanglingTerminalCommits: true);
    final latest = state.memory.requireRun(runId).latest;
    if (!state.memory.interrupt(runId)) {
      if (state.requiresRecoveryWrite) _persist(state);
      return false;
    }
    _persist(
      state.add(
        type: _JournalEventType.interrupted,
        runId: runId,
        payload: <String, Object?>{'latestSnapshotDigest': latest.digest.value},
      ),
    );
    return true;
  });

  @override
  List<ScenarioLabRunSnapshot> observationsAfter(
    ScenarioLabRunId runId,
    int sequence,
  ) => _withExclusiveLock(
    () => _load().memory.observationsAfter(runId, sequence),
  );

  void _recoverOwnerlessRuns() => _withExclusiveLock(() {
    var state = _load(recoverDanglingTerminalCommits: true);
    final openRuns =
        state.memory.runs
            .where((run) => run.result == null && !run.interrupted)
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.latest.runId.value.compareTo(right.latest.runId.value),
          );
    if (openRuns.isEmpty) {
      if (state.requiresRecoveryWrite) _persist(state);
      return;
    }
    for (final run in openRuns) {
      final runId = run.latest.runId;
      final latestDigest = state.memory.requireRun(runId).latest.digest;
      if (!state.memory.interrupt(runId)) continue;
      state = state.add(
        type: _JournalEventType.interrupted,
        runId: runId,
        payload: <String, Object?>{'latestSnapshotDigest': latestDigest.value},
      );
    }
    _persist(state);
  });

  _LoadedJournal _load({bool recoverDanglingTerminalCommits = false}) {
    final file = File(stateFilePath);
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return _LoadedJournal.empty();
    }
    if (type != FileSystemEntityType.file || Link(file.path).existsSync()) {
      throw FileSystemException(
        'Scenario Lab store state must be a regular file',
        file.path,
      );
    }
    final length = file.lengthSync();
    if (length < 1 || length > _maxStateBytes) {
      throw const FormatException(
        'Scenario Lab store state has an invalid size',
      );
    }
    final bytes = file.readAsBytesSync();
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on Object catch (error) {
      throw FormatException('Scenario Lab store state is not JSON: $error');
    }
    List<int> canonical;
    try {
      canonical = utf8.encode(
        '${const JcsCanonicalizer().canonicalize(decoded)}\n',
      );
    } on CanonicalJsonException catch (error) {
      throw FormatException(
        'Scenario Lab store state is outside the JCS profile: $error',
      );
    }
    if (!_sameBytes(bytes, canonical)) {
      throw const FormatException(
        'Scenario Lab store state is not canonical JCS',
      );
    }
    final document = _JournalDocument.fromJson(decoded);
    if (!recoverDanglingTerminalCommits) {
      return _LoadedJournal.replay(document.entries);
    }
    final recovery = _recoverDanglingTerminalEntries(document.entries);
    final validated = _LoadedJournal.replay(document.entries);
    if (!recovery.changed) return validated;
    return _LoadedJournal.replay(
      recovery.entries,
      requiresRecoveryWrite: recovery.changed,
    );
  }

  void _persist(_LoadedJournal state) {
    final document = _JournalDocument(entries: state.entries);
    final json = document.toJson();
    _rejectTransportSecrets(json);
    final bytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(json)}\n',
    );
    if (bytes.length > _maxStateBytes) {
      throw StateError('Scenario Lab store exceeds the 64 MiB limit');
    }
    _writer.write(destination: File(stateFilePath), bytes: bytes);
  }

  T _withExclusiveLock<T>(T Function() action) {
    final file = File(lockFilePath);
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException(
        'Scenario Lab store lock must be a regular file',
        file.path,
      );
    }
    if (Link(file.path).existsSync()) {
      throw FileSystemException(
        'Scenario Lab store lock cannot be a symlink',
        file.path,
      );
    }
    final lock = file.openSync(mode: FileMode.append);
    _LockClaim? claim;
    try {
      lock.lockSync(FileLock.exclusive);
      claim = _acquireInProcessClaim();
      return action();
    } finally {
      claim?.release();
      lock.unlockSync();
      lock.closeSync();
    }
  }

  _LockClaim _acquireInProcessClaim() {
    final guard = File(_guardFilePath);
    final waiting = Stopwatch()..start();
    final claimId =
        '$pid-${DateTime.now().microsecondsSinceEpoch}-'
        '${identityHashCode(Object())}';
    while (true) {
      final type = FileSystemEntity.typeSync(guard.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        try {
          guard.createSync(exclusive: true);
          guard.writeAsStringSync('$claimId\n', flush: true);
          return _LockClaim(file: guard, claimId: claimId);
        } on FileSystemException {
          continue;
        }
      }
      if (type != FileSystemEntityType.file || Link(guard.path).existsSync()) {
        throw FileSystemException(
          'Scenario Lab store guard must be a regular file',
          guard.path,
        );
      }
      String current = '';
      DateTime modified;
      try {
        current = guard.readAsStringSync().trim();
        modified = guard.statSync().modified.toUtc();
      } on FileSystemException {
        continue;
      }
      final claimParts = current.split('-');
      final parsedPid = claimParts.length == 3
          ? int.tryParse(claimParts.first)
          : null;
      final ownerPid = parsedPid != null && parsedPid > 0 ? parsedPid : null;
      final now = DateTime.now().toUtc();
      final stale = now.difference(modified) > _guardTimeout;
      final proc = Directory('/proc');
      final canInspectProcesses = proc.existsSync();
      final ownerIsGone =
          ownerPid != null &&
          canInspectProcesses &&
          !Directory('/proc/$ownerPid').existsSync();
      final abandonedIncompleteClaim =
          ownerPid == null && canInspectProcesses && stale;
      if (ownerIsGone || abandonedIncompleteClaim) {
        try {
          guard.deleteSync();
        } on FileSystemException {
          // Another contender already recovered the orphaned claim.
        }
        continue;
      }
      if (waiting.elapsed >= _guardTimeout) {
        throw FileSystemException(
          'Timed out waiting for Scenario Lab store guard',
          guard.path,
        );
      }
      sleep(const Duration(milliseconds: 1));
    }
  }
}

final class _LockClaim {
  const _LockClaim({required this.file, required this.claimId});

  final File file;
  final String claimId;

  void release() {
    if (!file.existsSync()) return;
    try {
      if (file.readAsStringSync().trim() == claimId) file.deleteSync();
    } on FileSystemException {
      // The OS lock still fences other processes; a stale guard is recovered
      // by the next owner after that lock is released.
    }
  }
}

enum _JournalEventType { register, snapshot, result, interrupted }

final class _JournalEvent {
  _JournalEvent._({
    required this.index,
    required this.previousDigest,
    required this.type,
    required this.runId,
    required this.payload,
  });

  factory _JournalEvent.create({
    required int index,
    required Digest? previousDigest,
    required _JournalEventType type,
    required ScenarioLabRunId runId,
    required Map<String, Object?> payload,
  }) {
    _rejectTransportSecrets(payload);
    return _JournalEvent._(
      index: index,
      previousDigest: previousDigest,
      type: type,
      runId: runId,
      payload: Map<String, Object?>.unmodifiable(payload),
    );
  }

  final int index;
  final Digest? previousDigest;
  final _JournalEventType type;
  final ScenarioLabRunId runId;
  final Map<String, Object?> payload;

  late final Digest digest = Digest.semantic(_digestJson());

  Map<String, Object?> _digestJson() => <String, Object?>{
    'index': index,
    'previousDigest': previousDigest?.value,
    'type': type.name,
    'runId': runId.value,
    'payload': payload,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ..._digestJson(),
    'digest': digest.value,
  };

  factory _JournalEvent.fromJson(
    Object? value, {
    required int expectedIndex,
    required Digest? expectedPreviousDigest,
  }) {
    final json = _object(value, 'Scenario Lab journal event');
    _only(json, const <String>{
      'index',
      'previousDigest',
      'type',
      'runId',
      'payload',
      'digest',
    }, 'Scenario Lab journal event');
    final index = _integer(json, 'index', 'Scenario Lab journal event');
    final rawPrevious = json['previousDigest'];
    if (rawPrevious != null && rawPrevious is! String) {
      throw const FormatException(
        'Scenario Lab journal previousDigest is invalid',
      );
    }
    final previous = rawPrevious == null ? null : Digest(rawPrevious as String);
    final rawType = _string(json, 'type', 'Scenario Lab journal event');
    final type = _JournalEventType.values
        .where((candidate) => candidate.name == rawType)
        .firstOrNull;
    if (type == null ||
        index != expectedIndex ||
        previous != expectedPreviousDigest) {
      throw const FormatException(
        'Scenario Lab journal chain is invalid or truncated',
      );
    }
    final event = _JournalEvent.create(
      index: index,
      previousDigest: previous,
      type: type,
      runId: ScenarioLabRunId(
        _string(json, 'runId', 'Scenario Lab journal event'),
      ),
      payload: _object(json['payload'], 'Scenario Lab journal payload'),
    );
    if (event.digest !=
        Digest(_string(json, 'digest', 'Scenario Lab journal event'))) {
      throw const FormatException('Scenario Lab journal event digest mismatch');
    }
    return event;
  }
}

final class _JournalDocument {
  _JournalDocument({required Iterable<_JournalEvent> entries})
    : entries = List<_JournalEvent>.unmodifiable(entries) {
    if (this.entries.length > FilesystemScenarioLabRunStore._maxEntries) {
      throw StateError('Scenario Lab journal entry limit exceeded');
    }
  }

  final List<_JournalEvent> entries;

  Digest? get headDigest => entries.lastOrNull?.digest;

  late final Digest digest = Digest.semantic(_digestJson());

  Map<String, Object?> _digestJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'ScenarioLabRunStoreJournal',
    'entryCount': entries.length,
    'headDigest': headDigest?.value,
    'entries': entries.map((event) => event.toJson()).toList(),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ..._digestJson(),
    'digest': digest.value,
  };

  factory _JournalDocument.fromJson(Object? value) {
    final json = _object(value, 'Scenario Lab journal');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'entryCount',
      'headDigest',
      'entries',
      'digest',
    }, 'Scenario Lab journal');
    if (json['schemaVersion'] != 1 ||
        json['kind'] != 'ScenarioLabRunStoreJournal') {
      throw const FormatException('Scenario Lab journal header is invalid');
    }
    final entryCount = _integer(json, 'entryCount', 'Scenario Lab journal');
    final values = _list(json, 'entries', 'Scenario Lab journal');
    if (entryCount != values.length ||
        values.length > FilesystemScenarioLabRunStore._maxEntries) {
      throw const FormatException(
        'Scenario Lab journal entry count is invalid',
      );
    }
    final entries = <_JournalEvent>[];
    Digest? previous;
    for (var index = 0; index < values.length; index += 1) {
      final event = _JournalEvent.fromJson(
        values[index],
        expectedIndex: index,
        expectedPreviousDigest: previous,
      );
      entries.add(event);
      previous = event.digest;
    }
    final rawHead = json['headDigest'];
    if (rawHead != null && rawHead is! String) {
      throw const FormatException('Scenario Lab journal head is invalid');
    }
    final advertisedHead = rawHead == null ? null : Digest(rawHead as String);
    final document = _JournalDocument(entries: entries);
    if (advertisedHead != document.headDigest ||
        Digest(_string(json, 'digest', 'Scenario Lab journal')) !=
            document.digest) {
      throw const FormatException(
        'Scenario Lab journal head or document digest mismatch',
      );
    }
    return document;
  }
}

final class _LoadedJournal {
  _LoadedJournal._({
    required this.entries,
    required this.memory,
    required this.requiresRecoveryWrite,
  });

  factory _LoadedJournal.empty() => _LoadedJournal._(
    entries: const <_JournalEvent>[],
    memory: InMemoryScenarioLabRunStore(),
    requiresRecoveryWrite: false,
  );

  factory _LoadedJournal.replay(
    List<_JournalEvent> entries, {
    bool requiresRecoveryWrite = false,
  }) {
    final memory = InMemoryScenarioLabRunStore();
    for (final event in entries) {
      try {
        switch (event.type) {
          case _JournalEventType.register:
            _only(event.payload, const <String>{
              'request',
              'initialSnapshot',
            }, 'Scenario Lab register event');
            final request = ScenarioLabRunStartRequest.fromJson(
              event.payload['request'],
            );
            final snapshot = ScenarioLabRunSnapshot.fromJson(
              event.payload['initialSnapshot'],
            );
            if (snapshot.runId != event.runId ||
                !memory
                    .register(request: request, initialSnapshot: snapshot)
                    .created) {
              throw const FormatException(
                'Scenario Lab register event is not unique',
              );
            }
          case _JournalEventType.snapshot:
            _only(event.payload, const <String>{
              'snapshot',
            }, 'Scenario Lab snapshot event');
            final snapshot = ScenarioLabRunSnapshot.fromJson(
              event.payload['snapshot'],
            );
            if (snapshot.runId != event.runId) {
              throw const FormatException(
                'Scenario Lab snapshot event run mismatch',
              );
            }
            memory.append(snapshot);
          case _JournalEventType.result:
            _only(event.payload, const <String>{
              'result',
            }, 'Scenario Lab result event');
            final result = ScenarioLabRunResult.fromJson(
              event.payload['result'],
            );
            if (result.finalSnapshot.runId != event.runId) {
              throw const FormatException(
                'Scenario Lab result event run mismatch',
              );
            }
            memory.complete(result);
          case _JournalEventType.interrupted:
            _only(event.payload, const <String>{
              'latestSnapshotDigest',
            }, 'Scenario Lab interrupted event');
            final latest = memory.requireRun(event.runId).latest;
            final advertisedDigest = Digest(
              _string(
                event.payload,
                'latestSnapshotDigest',
                'Scenario Lab interrupted event',
              ),
            );
            if (latest.digest != advertisedDigest) {
              throw const FormatException(
                'Scenario Lab interruption tombstone is invalid',
              );
            }
            if (!memory.interrupt(event.runId)) {
              throw const FormatException(
                'Scenario Lab interruption tombstone is invalid',
              );
            }
        }
      } on FormatException {
        rethrow;
      } on Object catch (error) {
        throw FormatException(
          'Scenario Lab journal event ${event.index} is invalid: $error',
        );
      }
    }
    return _LoadedJournal._(
      entries: List<_JournalEvent>.unmodifiable(entries),
      memory: memory,
      requiresRecoveryWrite: requiresRecoveryWrite,
    );
  }

  final List<_JournalEvent> entries;
  final InMemoryScenarioLabRunStore memory;
  final bool requiresRecoveryWrite;

  _LoadedJournal add({
    required _JournalEventType type,
    required ScenarioLabRunId runId,
    required Map<String, Object?> payload,
  }) {
    final event = _JournalEvent.create(
      index: entries.length,
      previousDigest: entries.lastOrNull?.digest,
      type: type,
      runId: runId,
      payload: payload,
    );
    return _LoadedJournal._(
      entries: List<_JournalEvent>.unmodifiable(<_JournalEvent>[
        ...entries,
        event,
      ]),
      memory: memory,
      requiresRecoveryWrite: requiresRecoveryWrite,
    );
  }
}

final class _JournalRecovery {
  const _JournalRecovery({required this.entries, required this.changed});

  final List<_JournalEvent> entries;
  final bool changed;
}

_JournalRecovery _recoverDanglingTerminalEntries(List<_JournalEvent> entries) {
  final latestSnapshotIndexes = <String, int>{};
  final latestSnapshots = <String, ScenarioLabRunSnapshot>{};
  final resultRunIds = <String>{};
  for (var index = 0; index < entries.length; index += 1) {
    final event = entries[index];
    switch (event.type) {
      case _JournalEventType.register:
        break;
      case _JournalEventType.snapshot:
        final snapshot = ScenarioLabRunSnapshot.fromJson(
          event.payload['snapshot'],
        );
        latestSnapshotIndexes[event.runId.value] = index;
        latestSnapshots[event.runId.value] = snapshot;
      case _JournalEventType.result:
        resultRunIds.add(event.runId.value);
      case _JournalEventType.interrupted:
        break;
    }
  }
  final removedIndexes = <int>{};
  for (final entry in latestSnapshots.entries) {
    if (!entry.value.state.isTerminal || resultRunIds.contains(entry.key)) {
      continue;
    }
    final snapshotIndex = latestSnapshotIndexes[entry.key];
    if (snapshotIndex == null) {
      throw const FormatException(
        'Scenario Lab terminal preparation is missing its journal event',
      );
    }
    removedIndexes.add(snapshotIndex);
  }
  if (removedIndexes.isEmpty) {
    return _JournalRecovery(entries: entries, changed: false);
  }
  final rebuilt = <_JournalEvent>[];
  Digest? previous;
  for (var index = 0; index < entries.length; index += 1) {
    if (removedIndexes.contains(index)) continue;
    final original = entries[index];
    final event = _JournalEvent.create(
      index: rebuilt.length,
      previousDigest: previous,
      type: original.type,
      runId: original.runId,
      payload: original.payload,
    );
    rebuilt.add(event);
    previous = event.digest;
  }
  return _JournalRecovery(
    entries: List<_JournalEvent>.unmodifiable(rebuilt),
    changed: true,
  );
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must be an object');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> json, String key, String label) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$label.$key must be a list');
  }
  return value;
}

String _string(Map<String, Object?> json, String key, String label) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$label.$key must be a string');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key, String label) {
  final value = json[key];
  if (value is! int || value < 0 || value > JcsCanonicalizer.maxSafeInteger) {
    throw FormatException('$label.$key must be a JSON-safe integer');
  }
  return value;
}

void _only(Map<String, Object?> json, Set<String> allowed, String label) {
  if (json.keys.length != allowed.length ||
      json.keys.any((key) => !allowed.contains(key))) {
    throw FormatException('$label has unknown or missing fields');
  }
}

void _rejectTransportSecrets(Object? value, [String path = r'$']) {
  switch (value) {
    case Map<String, Object?>():
      for (final entry in value.entries) {
        final normalized = entry.key.toLowerCase();
        if (const <String>{
          'token',
          'secret',
          'password',
          'authorization',
          'credential',
          'cookie',
          'uri',
          'url',
        }.any(normalized.contains)) {
          throw FormatException(
            'Scenario Lab durable state forbids transport field '
            '$path.${entry.key}',
          );
        }
        _rejectTransportSecrets(entry.value, '$path.${entry.key}');
      }
    case List<Object?>():
      for (var index = 0; index < value.length; index += 1) {
        _rejectTransportSecrets(value[index], '$path[$index]');
      }
    case String():
      final normalized = value.toLowerCase();
      if (normalized.contains('://') ||
          normalized.startsWith('bearer ') ||
          normalized.contains('access_token=') ||
          normalized.contains('token=')) {
        throw FormatException(
          'Scenario Lab durable state forbids transport value at $path',
        );
      }
    case null || bool() || int() || double():
      return;
    default:
      throw FormatException(
        'Scenario Lab durable state contains non-JSON value at $path',
      );
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
