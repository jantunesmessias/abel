import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import 'filesystem_workspace_store.dart';

final class LocalRetentionPolicy {
  const LocalRetentionPolicy({
    this.quotaBytes = 10 * 1024 * 1024 * 1024,
    this.temporaryTtl = const Duration(days: 7),
    this.unreachableGrace = const Duration(hours: 24),
  });

  final int quotaBytes;
  final Duration temporaryTtl;
  final Duration unreachableGrace;

  void validate() {
    if (quotaBytes < 1024 * 1024 || quotaBytes > 1024 * 1024 * 1024 * 1024) {
      throw ArgumentError.value(quotaBytes, 'quotaBytes');
    }
    if (temporaryTtl < const Duration(hours: 1) ||
        temporaryTtl > const Duration(days: 365)) {
      throw ArgumentError.value(temporaryTtl, 'temporaryTtl');
    }
    if (unreachableGrace < const Duration(hours: 1) ||
        unreachableGrace > const Duration(days: 30)) {
      throw ArgumentError.value(unreachableGrace, 'unreachableGrace');
    }
  }
}

final class LocalRetentionReport {
  const LocalRetentionReport({
    required this.mode,
    required this.totalBytesBefore,
    required this.totalBytesAfter,
    required this.quotaBytes,
    required this.reachableBlobs,
    required this.unreachableBlobs,
    required this.graceBlobs,
    required this.deletedBlobs,
    required this.deletedTemporaryFiles,
    required this.pinnedReleases,
    required this.recoveredTransaction,
  });

  final String mode;
  final int totalBytesBefore;
  final int totalBytesAfter;
  final int quotaBytes;
  final int reachableBlobs;
  final int unreachableBlobs;
  final int graceBlobs;
  final int deletedBlobs;
  final int deletedTemporaryFiles;
  final int pinnedReleases;
  final bool recoveredTransaction;

  bool get quotaSatisfied => totalBytesAfter <= quotaBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'mode': mode,
    'totalBytesBefore': totalBytesBefore,
    'totalBytesAfter': totalBytesAfter,
    'quotaBytes': quotaBytes,
    'quotaSatisfied': quotaSatisfied,
    'reachableBlobs': reachableBlobs,
    'unreachableBlobs': unreachableBlobs,
    'graceBlobs': graceBlobs,
    'deletedBlobs': deletedBlobs,
    'deletedTemporaryFiles': deletedTemporaryFiles,
    'pinnedReleases': pinnedReleases,
    'recoveredTransaction': recoveredTransaction,
  };
}

final class LocalRetentionService {
  LocalRetentionService({
    required String workspaceRoot,
    this.policy = const LocalRetentionPolicy(),
    DateTime Function()? nowUtc,
  }) : store = FileSystemWorkspaceStore(workspaceRoot: workspaceRoot),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()) {
    policy.validate();
  }

  static const String _sweepPath = 'retention/sweep-v1.json';
  static const String _journalPath = 'retention/transaction-v1.json';

  final FileSystemWorkspaceStore store;
  final LocalRetentionPolicy policy;
  final DateTime Function() _nowUtc;

  LocalRetentionReport run({required bool apply}) {
    var recovered = false;
    if (apply) {
      store.withExclusiveLock(() {
        recovered = _recoverIfNecessary();
      });
    } else if (store.readStateBytes(_journalPath) != null) {
      throw StateError('Retention recovery is pending; run with --apply');
    }
    if (!Directory(store.stateRoot).existsSync()) {
      return LocalRetentionReport(
        mode: apply ? 'apply' : 'dryRun',
        totalBytesBefore: 0,
        totalBytesAfter: 0,
        quotaBytes: policy.quotaBytes,
        reachableBlobs: 0,
        unreachableBlobs: 0,
        graceBlobs: 0,
        deletedBlobs: 0,
        deletedTemporaryFiles: 0,
        pinnedReleases: 0,
        recoveredTransaction: recovered,
      );
    }
    final now = _nowUtc();
    final expiredTemporary = _expiredTemporaryFiles(now);
    final reachable = _reachableDigests(
      expiredTemporary.map((file) => file.path).toSet(),
    );
    final cas = _casFiles();
    final previous = _readSweep();
    final next = <Digest, DateTime>{};
    final eligible = <_CasEntry>[];
    var grace = 0;
    for (final entry in cas) {
      if (reachable.contains(entry.digest)) continue;
      final since = previous[entry.digest] ?? now;
      next[entry.digest] = since;
      if (!since.add(policy.unreachableGrace).isAfter(now)) {
        eligible.add(entry);
      } else {
        grace += 1;
      }
    }
    eligible.sort((left, right) {
      final byTime = next[left.digest]!.compareTo(next[right.digest]!);
      return byTime != 0
          ? byTime
          : left.digest.value.compareTo(right.digest.value);
    });
    for (final entry in eligible) {
      next.remove(entry.digest);
    }
    final totalBefore = _totalStateBytes();
    final deletedBytes =
        eligible.fold<int>(0, (total, entry) => total + entry.size) +
        expiredTemporary.fold<int>(
          0,
          (total, file) => total + file.lengthSync(),
        );
    final totalAfter = totalBefore - deletedBytes;
    if (apply) {
      store.withExclusiveLock(() {
        _applyTransaction(
          now: now,
          blobs: eligible,
          temporaryFiles: expiredTemporary,
          nextSweep: next,
        );
      });
    }
    return LocalRetentionReport(
      mode: apply ? 'apply' : 'dryRun',
      totalBytesBefore: totalBefore,
      totalBytesAfter: apply ? _totalStateBytes() : totalAfter,
      quotaBytes: policy.quotaBytes,
      reachableBlobs: cas
          .where((entry) => reachable.contains(entry.digest))
          .length,
      unreachableBlobs:
          cas.length -
          cas.where((entry) => reachable.contains(entry.digest)).length,
      graceBlobs: grace,
      deletedBlobs: eligible.length,
      deletedTemporaryFiles: expiredTemporary.length,
      pinnedReleases: _pinnedReleaseCount(),
      recoveredTransaction: recovered,
    );
  }

  Set<Digest> _reachableDigests(Set<String> excludedPaths) {
    final root = Directory(store.stateRoot);
    final output = <Digest>{};
    var totalBytes = 0;
    final files =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) {
              final relative = p.relative(file.path, from: root.path);
              return file.path.endsWith('.json') &&
                  relative != p.join('cas', 'index.json') &&
                  !relative.startsWith('retention${p.separator}') &&
                  !relative.startsWith('.trash${p.separator}') &&
                  !excludedPaths.contains(file.path);
            })
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      if (Link(file.path).existsSync()) {
        throw FileSystemException(
          'Retention root cannot be a symlink',
          file.path,
        );
      }
      final length = file.lengthSync();
      totalBytes += length;
      if (length > 16 * 1024 * 1024 || totalBytes > 256 * 1024 * 1024) {
        throw StateError('Retention root documents exceed the scan budget');
      }
      final Object? json;
      try {
        json = jsonDecode(file.readAsStringSync());
      } on Object {
        throw FormatException('Retention root is invalid JSON: ${file.path}');
      }
      _collectDigests(json, output);
    }
    return output;
  }

  void _collectDigests(Object? value, Set<Digest> output) {
    if (value is String && RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value)) {
      output.add(Digest(value));
      return;
    }
    if (value is List<Object?>) {
      for (final item in value) {
        _collectDigests(item, output);
      }
    } else if (value is Map<String, Object?>) {
      for (final item in value.values) {
        _collectDigests(item, output);
      }
    }
  }

  List<_CasEntry> _casFiles() {
    final root = Directory(p.join(store.stateRoot, 'cas', 'sha256'));
    if (!root.existsSync()) return const <_CasEntry>[];
    final output = <_CasEntry>[];
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! File || Link(entity.path).existsSync()) {
        throw FileSystemException(
          'CAS contains a non-regular entry',
          entity.path,
        );
      }
      final name = p.basename(entity.path);
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(name)) {
        throw FormatException('CAS contains an invalid filename');
      }
      final digest = Digest('sha256:$name');
      final bytes = entity.readAsBytesSync();
      if (Digest.bytes(bytes) != digest) {
        throw StateError('CAS corruption at ${entity.path}');
      }
      output.add(_CasEntry(file: entity, digest: digest, size: bytes.length));
    }
    output.sort(
      (left, right) => left.digest.value.compareTo(right.digest.value),
    );
    return output;
  }

  List<File> _expiredTemporaryFiles(DateTime now) {
    final roots = <Directory>[
      Directory(p.join(store.stateRoot, '.staging')),
      Directory(p.join(store.stateRoot, 'probe', 'temporary')),
    ];
    final output = <File>[];
    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true, followLinks: false)) {
        if (entity is Link) {
          throw FileSystemException(
            'Temporary root contains a symlink',
            entity.path,
          );
        }
        if (entity is File &&
            !entity
                .lastModifiedSync()
                .toUtc()
                .add(policy.temporaryTtl)
                .isAfter(now)) {
          output.add(entity);
        }
      }
    }
    output.sort((left, right) => left.path.compareTo(right.path));
    return output;
  }

  Map<Digest, DateTime> _readSweep() {
    final bytes = store.readStateBytes(_sweepPath);
    if (bytes == null) return <Digest, DateTime>{};
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != 1 ||
        value['unreachableSince'] is! Map<String, Object?>) {
      throw const FormatException('Invalid retention sweep state');
    }
    if (value.keys.toSet().difference(const <String>{
      'schemaVersion',
      'unreachableSince',
    }).isNotEmpty) {
      throw const FormatException('Unknown retention sweep state field');
    }
    final entries = value['unreachableSince']! as Map<String, Object?>;
    final output = <Digest, DateTime>{};
    for (final entry in entries.entries) {
      final time = entry.value is String
          ? DateTime.tryParse(entry.value! as String)
          : null;
      if (time == null || !time.isUtc) {
        throw const FormatException('Invalid retention unreachable timestamp');
      }
      output[Digest(entry.key)] = time;
    }
    return output;
  }

  void _writeSweep(Map<Digest, DateTime> state) {
    final value = <String, Object?>{
      'schemaVersion': 1,
      'unreachableSince': <String, String>{
        for (final digest
            in state.keys.toList()
              ..sort((left, right) => left.value.compareTo(right.value)))
          digest.value: state[digest]!.toUtc().toIso8601String(),
      },
    };
    store.atomicWrite(
      _sweepPath,
      utf8.encode('${const JcsCanonicalizer().canonicalize(value)}\n'),
    );
  }

  void _applyTransaction({
    required DateTime now,
    required List<_CasEntry> blobs,
    required List<File> temporaryFiles,
    required Map<Digest, DateTime> nextSweep,
  }) {
    final runId = now.microsecondsSinceEpoch.toString();
    final trashRoot = p.join('.trash', 'retention-$runId');
    final moves = <_RetentionMove>[
      for (final entry in blobs)
        _RetentionMove(
          origin: p.relative(entry.file.path, from: store.stateRoot),
          trash: p.join(trashRoot, 'cas', p.basename(entry.file.path)),
        ),
      for (var index = 0; index < temporaryFiles.length; index++)
        _RetentionMove(
          origin: p.relative(temporaryFiles[index].path, from: store.stateRoot),
          trash: p.join(trashRoot, 'temporary', '$index.bin'),
        ),
    ];
    var journal = _RetentionJournal(
      phase: 'planned',
      moves: moves,
      nextSweep: nextSweep,
    );
    _writeJournal(journal);
    for (final move in moves) {
      final origin = _stateFile(move.origin);
      final trash = _stateFile(move.trash);
      trash.parent.createSync(recursive: true);
      if (origin.existsSync()) origin.renameSync(trash.path);
    }
    journal = journal.withPhase('moved');
    _writeJournal(journal);
    journal = journal.withPhase('commitRequested');
    _writeJournal(journal);
    _writeSweep(nextSweep);
    store.rebuildCasIndex();
    final trash = Directory(p.join(store.stateRoot, trashRoot));
    if (trash.existsSync()) trash.deleteSync(recursive: true);
    _deleteJournal();
    _deleteEmptyTemporaryDirectories();
  }

  bool _recoverIfNecessary() {
    final bytes = store.readStateBytes(_journalPath);
    if (bytes == null) return false;
    final journal = _RetentionJournal.fromJson(jsonDecode(utf8.decode(bytes)));
    if (journal.phase == 'commitRequested') {
      for (final move in journal.moves) {
        final trash = _stateFile(move.trash);
        if (trash.existsSync()) trash.deleteSync();
      }
      _writeSweep(journal.nextSweep);
      store.rebuildCasIndex();
    } else {
      for (final move in journal.moves.reversed) {
        final origin = _stateFile(move.origin);
        final trash = _stateFile(move.trash);
        if (trash.existsSync()) {
          if (origin.existsSync()) {
            throw StateError(
              'Retention recovery found duplicate move endpoints',
            );
          }
          origin.parent.createSync(recursive: true);
          trash.renameSync(origin.path);
        }
      }
      store.rebuildCasIndex();
    }
    _cleanupTransactionTrash(journal.moves);
    _deleteJournal();
    return true;
  }

  void _cleanupTransactionTrash(List<_RetentionMove> moves) {
    final roots = <String>{};
    for (final move in moves) {
      final segments = p.split(move.trash);
      if (segments.length < 2 || segments.first != '.trash') {
        throw const FormatException('Invalid retention trash path');
      }
      roots.add(p.join(segments[0], segments[1]));
    }
    for (final relative in roots) {
      final directory = Directory(p.join(store.stateRoot, relative));
      if (!directory.existsSync()) continue;
      if (directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .isNotEmpty) {
        throw StateError('Retention recovery left unaccounted trash files');
      }
      directory.deleteSync(recursive: true);
    }
    final parent = Directory(p.join(store.stateRoot, '.trash'));
    if (parent.existsSync() && parent.listSync().isEmpty) parent.deleteSync();
  }

  void _writeJournal(_RetentionJournal journal) {
    store.atomicWrite(
      _journalPath,
      utf8.encode(
        '${const JcsCanonicalizer().canonicalize(journal.toJson())}\n',
      ),
    );
  }

  void _deleteJournal() {
    final file = _stateFile(_journalPath);
    if (file.existsSync()) file.deleteSync();
  }

  File _stateFile(String relative) {
    if (p.isAbsolute(relative) ||
        p.split(p.normalize(relative)).contains('..')) {
      throw const FormatException('Invalid retention transaction path');
    }
    final path = p.normalize(p.join(store.stateRoot, relative));
    if (!p.isWithin(store.stateRoot, path)) {
      throw const FormatException('Retention transaction escapes state root');
    }
    return File(path);
  }

  int _totalStateBytes() {
    final root = Directory(store.stateRoot);
    if (!root.existsSync()) return 0;
    var total = 0;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FileSystemException(
          'Retention state contains a symlink',
          entity.path,
        );
      }
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }

  int _pinnedReleaseCount() {
    final root = Directory(p.join(store.stateRoot, 'releases', 'sha256'));
    if (!root.existsSync()) return 0;
    return root.listSync(followLinks: false).whereType<Directory>().length;
  }

  void _deleteEmptyTemporaryDirectories() {
    for (final root in <Directory>[
      Directory(p.join(store.stateRoot, '.staging')),
      Directory(p.join(store.stateRoot, 'probe', 'temporary')),
    ]) {
      if (!root.existsSync()) continue;
      final directories =
          root
              .listSync(recursive: true, followLinks: false)
              .whereType<Directory>()
              .toList()
            ..sort(
              (left, right) => right.path.length.compareTo(left.path.length),
            );
      for (final directory in directories) {
        if (directory.listSync().isEmpty) directory.deleteSync();
      }
      if (root.existsSync() && root.listSync().isEmpty) root.deleteSync();
    }
  }
}

final class _CasEntry {
  const _CasEntry({
    required this.file,
    required this.digest,
    required this.size,
  });

  final File file;
  final Digest digest;
  final int size;
}

final class _RetentionMove {
  const _RetentionMove({required this.origin, required this.trash});

  final String origin;
  final String trash;

  Map<String, Object?> toJson() => <String, Object?>{
    'origin': origin,
    'trash': trash,
  };
}

final class _RetentionJournal {
  const _RetentionJournal({
    required this.phase,
    required this.moves,
    required this.nextSweep,
  });

  final String phase;
  final List<_RetentionMove> moves;
  final Map<Digest, DateTime> nextSweep;

  _RetentionJournal withPhase(String value) =>
      _RetentionJournal(phase: value, moves: moves, nextSweep: nextSweep);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'phase': phase,
    'moves': <Object?>[for (final move in moves) move.toJson()],
    'nextSweep': <String, String>{
      for (final digest
          in nextSweep.keys.toList()
            ..sort((left, right) => left.value.compareTo(right.value)))
        digest.value: nextSweep[digest]!.toUtc().toIso8601String(),
    },
  };

  factory _RetentionJournal.fromJson(Object? value) {
    if (value is! Map<String, Object?> ||
        value['schemaVersion'] != 1 ||
        !const <String>{
          'planned',
          'moved',
          'commitRequested',
        }.contains(value['phase']) ||
        value['moves'] is! List<Object?> ||
        value['nextSweep'] is! Map<String, Object?> ||
        value.length != 4) {
      throw const FormatException('Invalid retention transaction journal');
    }
    final moves = <_RetentionMove>[];
    for (final item in value['moves']! as List<Object?>) {
      if (item is! Map<String, Object?> ||
          item.length != 2 ||
          item['origin'] is! String ||
          item['trash'] is! String) {
        throw const FormatException('Invalid retention transaction move');
      }
      moves.add(
        _RetentionMove(
          origin: item['origin']! as String,
          trash: item['trash']! as String,
        ),
      );
    }
    final nextJson = value['nextSweep']! as Map<String, Object?>;
    final next = <Digest, DateTime>{};
    for (final entry in nextJson.entries) {
      final parsed = entry.value is String
          ? DateTime.tryParse(entry.value! as String)
          : null;
      if (parsed == null || !parsed.isUtc) {
        throw const FormatException('Invalid retention transaction timestamp');
      }
      next[Digest(entry.key)] = parsed;
    }
    return _RetentionJournal(
      phase: value['phase']! as String,
      moves: moves,
      nextSweep: next,
    );
  }
}
