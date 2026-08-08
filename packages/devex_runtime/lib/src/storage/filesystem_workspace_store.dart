import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;

final class FileSystemWorkspaceStore {
  factory FileSystemWorkspaceStore({
    required String workspaceRoot,
    String distributionId = 'devex-kit',
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
  }) : stateRoot = p.join(workspaceRoot, '.dart_tool', 'devex', distributionId);

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

  List<int>? readStateBytes(String relativePath) {
    final file = _safeStatePath(relativePath);
    if (!file.existsSync()) return null;
    return file.readAsBytesSync();
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
