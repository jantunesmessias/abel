import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

final class FileSystemWorkspaceStore {
  factory FileSystemWorkspaceStore({
    required String workspaceRoot,
    String distributionId = 'full-local',
  }) {
    final resolvedRoot = Directory(
      workspaceRoot,
    ).absolute.resolveSymbolicLinksSync();
    return FileSystemWorkspaceStore._(
      workspaceRoot: resolvedRoot,
      distributionId: distributionId,
    );
  }

  FileSystemWorkspaceStore._({
    required this.workspaceRoot,
    required String distributionId,
  }) : stateRoot = p.join(
         workspaceRoot,
         '.dart_tool',
         'workspace',
         distributionId,
       );

  final String workspaceRoot;
  final String stateRoot;

  T withExclusiveLock<T>(T Function() action) {
    final lockFile = _safeStatePath('workspace.lock');
    lockFile.parent.createSync(recursive: true);
    final lock = lockFile.openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.exclusive);
      return action();
    } finally {
      lock.unlockSync();
      lock.closeSync();
    }
  }

  Digest putBlob(List<int> bytes) {
    final digest = Digest.bytes(bytes);
    final file = _casFile(digest);
    if (file.existsSync()) {
      final existingDigest = Digest.bytes(file.readAsBytesSync());
      if (existingDigest != digest) {
        throw StateError('CAS corruption at ${file.path}');
      }
      return digest;
    }
    atomicWrite(p.relative(file.path, from: stateRoot), bytes);
    return digest;
  }

  List<int>? readBlob(Digest digest) {
    final file = _casFile(digest);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    if (Digest.bytes(bytes) != digest) {
      throw StateError('CAS corruption at ${file.path}');
    }
    return bytes;
  }

  /// Returns the current CAS file size without materializing its bytes.
  int? blobSize(Digest digest) {
    final file = _casFile(digest);
    if (!file.existsSync()) return null;
    return file.statSync().size;
  }

  /// Reads and verifies one CAS blob without ever crossing [maxBytes].
  ///
  /// The size is checked before opening and while reading so a concurrent file
  /// replacement cannot turn a bounded review into an unbounded allocation.
  List<int>? readBlobBounded(
    Digest digest, {
    required int maxBytes,
    int? expectedSize,
    void Function(int byteCount)? beforeRead,
  }) {
    if (maxBytes < 0 || expectedSize != null && expectedSize < 0) {
      throw ArgumentError('CAS bounded read limits are invalid');
    }
    final file = _casFile(digest);
    if (!file.existsSync()) return null;
    final initialSize = file.statSync().size;
    if (initialSize > maxBytes ||
        expectedSize != null && initialSize != expectedSize) {
      throw StateError('CAS blob size is outside the bounded read');
    }
    beforeRead?.call(initialSize);
    final readLimit = initialSize;
    final output = BytesBuilder(copy: false);
    final reader = file.openSync();
    var total = 0;
    try {
      while (true) {
        final remaining = readLimit - total;
        final chunk = reader.readSync(
          remaining < 64 * 1024 ? remaining + 1 : 64 * 1024,
        );
        if (chunk.isEmpty) break;
        total += chunk.length;
        if (total > readLimit) {
          throw StateError('CAS blob grew beyond the bounded read');
        }
        output.add(chunk);
      }
    } finally {
      reader.closeSync();
    }
    final bytes = Uint8List.fromList(output.takeBytes());
    if (bytes.length != initialSize ||
        expectedSize != null && bytes.length != expectedSize ||
        Digest.bytes(bytes) != digest) {
      throw StateError('CAS corruption at ${file.path}');
    }
    return bytes;
  }

  List<int>? readStateBytes(String relativePath) {
    final file = _safeStatePath(relativePath);
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
  }

  /// Reads mutable state without allocating beyond a caller-owned budget.
  /// The second size comparison closes a concurrent-growth/truncation race.
  List<int>? readStateBytesBounded(
    String relativePath, {
    required int maxBytes,
    void Function(int byteCount)? beforeRead,
  }) {
    if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final file = _safeStatePath(relativePath);
    if (!file.existsSync()) return null;
    final initialSize = file.lengthSync();
    if (initialSize > maxBytes) {
      throw StateError('State document exceeds the bounded read');
    }
    beforeRead?.call(initialSize);
    final readLimit = initialSize;
    final output = BytesBuilder(copy: false);
    final reader = file.openSync();
    var total = 0;
    try {
      while (true) {
        final remaining = readLimit - total;
        final chunk = reader.readSync(
          remaining < 64 * 1024 ? remaining + 1 : 64 * 1024,
        );
        if (chunk.isEmpty) break;
        total += chunk.length;
        if (total > readLimit) {
          throw StateError('State document grew beyond the bounded read');
        }
        output.add(chunk);
      }
    } finally {
      reader.closeSync();
    }
    final bytes = Uint8List.fromList(output.takeBytes());
    if (bytes.length != initialSize) {
      throw StateError('State document changed during the bounded read');
    }
    return bytes;
  }

  void writeManifest(CatalogManifest manifest) {
    final canonical = const JcsCanonicalizer().canonicalize(manifest.toJson());
    atomicWrite('catalog/manifest.json', utf8.encode('$canonical\n'));
  }

  File atomicWrite(String relativePath, List<int> bytes) {
    final destination = _safeStatePath(relativePath);
    destination.parent.createSync(recursive: true);
    final temporary = File(
      '${destination.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      temporary.writeAsBytesSync(bytes, flush: true);
      temporary.renameSync(destination.path);
      return destination;
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  Map<String, Object?> rebuildCasIndex() {
    final root = Directory(p.join(stateRoot, 'cas', 'sha256'));
    final entries = <Map<String, Object?>>[];
    if (root.existsSync()) {
      final files = root.listSync(followLinks: false).whereType<File>().toList()
        ..sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        final digest = Digest('sha256:${p.basename(file.path)}');
        final bytes = file.readAsBytesSync();
        if (Digest.bytes(bytes) != digest) {
          throw StateError('CAS corruption at ${file.path}');
        }
        entries.add(<String, Object?>{
          'digest': digest.value,
          'size': bytes.length,
        });
      }
    }
    final index = <String, Object?>{'schemaVersion': 1, 'blobs': entries};
    atomicWrite(
      'cas/index.json',
      utf8.encode('${const JcsCanonicalizer().canonicalize(index)}\n'),
    );
    return index;
  }

  File _casFile(Digest digest) => File(
    _safeStatePath(
      p.join('cas', 'sha256', digest.value.substring('sha256:'.length)),
    ).path,
  );

  File _safeStatePath(String relativePath) {
    if (p.isAbsolute(relativePath)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'must be relative',
      );
    }
    final normalized = p.normalize(p.join(stateRoot, relativePath));
    if (!p.isWithin(stateRoot, normalized)) {
      throw ArgumentError.value(
        relativePath,
        'relativePath',
        'escapes state root',
      );
    }
    var current = Directory(workspaceRoot);
    final relativeSegments = p.split(
      p.relative(normalized, from: workspaceRoot),
    );
    for (final segment in relativeSegments.take(relativeSegments.length - 1)) {
      current = Directory(p.join(current.path, segment));
      if (Link(current.path).existsSync()) {
        throw FileSystemException(
          'Symlink forbidden in state path',
          current.path,
        );
      }
    }
    if (Link(normalized).existsSync()) {
      throw FileSystemException('Symlink forbidden for state file', normalized);
    }
    return File(normalized);
  }
}
