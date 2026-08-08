import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;

final class FilesystemSourceAdapter {
  const FilesystemSourceAdapter({
    this.maxFiles = 100000,
    this.maxFileBytes = 64 * 1024 * 1024,
    this.maxTotalBytes = 2 * 1024 * 1024 * 1024,
    this.excludedSegments = const <String>{
      '.git',
      '.dart_tool',
      '.devex',
      'build',
    },
  });

  final int maxFiles;
  final int maxFileBytes;
  final int maxTotalBytes;
  final Set<String> excludedSegments;

  SourceSnapshot inspect({
    required String root,
    String repositoryId = 'workspace',
  }) {
    final directory = _safeDirectory(root);
    final entries = <SourceFileEntry>[];
    final omissions = <String>[];
    var totalBytes = 0;
    final entities = directory.listSync(recursive: true, followLinks: false)
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final entity in entities) {
      final relative = _relative(directory, entity.path);
      final segments = relative.split('/');
      if (segments.any(excludedSegments.contains)) continue;
      if (entity is Link) {
        omissions.add('$relative:symlink');
        continue;
      }
      if (entity is! File) continue;
      if (entries.length >= maxFiles) {
        omissions.add('$relative:file-count-limit');
        continue;
      }
      try {
        final stat = entity.statSync();
        if (stat.type != FileSystemEntityType.file ||
            stat.size > maxFileBytes) {
          omissions.add('$relative:file-size-limit');
          continue;
        }
        if (totalBytes + stat.size > maxTotalBytes) {
          omissions.add('$relative:total-size-limit');
          continue;
        }
        final bytes = entity.readAsBytesSync();
        totalBytes += bytes.length;
        entries.add(
          SourceFileEntry(
            path: relative,
            digest: Digest.bytes(bytes),
            size: bytes.length,
          ),
        );
      } on FileSystemException {
        omissions.add('$relative:unreadable');
      }
    }
    final treeDigest = Digest.semantic(<Object?>[
      for (final entry in entries) entry.toJson(),
    ]);
    return SourceSnapshot(
      repository: SourceRepository(
        id: repositoryId,
        kind: SourceRepositoryKind.filesystem,
        root: '.',
      ),
      revision: 'filesystem:${treeDigest.value.substring('sha256:'.length)}',
      completeness: omissions.isEmpty
          ? SnapshotCompleteness.complete
          : SnapshotCompleteness.partial,
      files: entries,
      omissions: omissions,
    );
  }
}

final class GitSourceAdapter {
  const GitSourceAdapter({
    this.maxFiles = 100000,
    this.maxFileBytes = 64 * 1024 * 1024,
  });

  final int maxFiles;
  final int maxFileBytes;

  Future<SourceSnapshot> inspect({
    required String root,
    String repositoryId = 'workspace',
    String? revision,
  }) async {
    final directory = _safeDirectory(root);
    final topLevel = await _gitText(directory, const <String>[
      'rev-parse',
      '--show-toplevel',
    ]);
    final canonicalRoot = Directory(topLevel.trim()).resolveSymbolicLinksSync();
    if (p.normalize(canonicalRoot) != p.normalize(directory.path)) {
      throw const FormatException(
        'Git source root must be the repository top-level',
      );
    }
    if (revision == null) {
      final filesystem = const FilesystemSourceAdapter().inspect(
        root: directory.path,
        repositoryId: repositoryId,
      );
      final head = (await _gitText(directory, const <String>[
        'rev-parse',
        'HEAD',
      ])).trim();
      return SourceSnapshot(
        repository: SourceRepository(
          id: repositoryId,
          kind: SourceRepositoryKind.git,
          root: '.',
          revision: 'worktree',
        ),
        revision:
            'worktree:$head:${filesystem.digest.value.substring('sha256:'.length)}',
        completeness: filesystem.completeness,
        files: filesystem.files,
        omissions: filesystem.omissions,
      );
    }
    if (revision.startsWith('-') ||
        revision.contains('\u0000') ||
        revision.length > 256) {
      throw const FormatException('Git revision is invalid');
    }
    final commit = (await _gitText(directory, <String>[
      'rev-parse',
      '--verify',
      '$revision^{commit}',
    ])).trim();
    if (!RegExp(r'^[0-9a-f]{40,64}$').hasMatch(commit)) {
      throw const FormatException('Git did not resolve a canonical commit ID');
    }
    final listing = await _gitBytes(directory, <String>[
      'ls-tree',
      '-r',
      '-z',
      '--name-only',
      commit,
    ]);
    final names = utf8.decode(listing).split('\u0000')
      ..removeWhere((name) => name.isEmpty);
    if (names.length > maxFiles) {
      throw const FormatException('Git snapshot exceeds file-count limit');
    }
    final files = <SourceFileEntry>[];
    final omissions = <String>[];
    for (final name in names..sort()) {
      _validateGitPath(name);
      final bytes = await _gitBytes(directory, <String>[
        'show',
        '--no-textconv',
        '$commit:$name',
      ]);
      if (bytes.length > maxFileBytes) {
        omissions.add('$name:file-size-limit');
        continue;
      }
      files.add(
        SourceFileEntry(
          path: name,
          digest: Digest.bytes(bytes),
          size: bytes.length,
        ),
      );
    }
    return SourceSnapshot(
      repository: SourceRepository(
        id: repositoryId,
        kind: SourceRepositoryKind.git,
        root: '.',
        revision: commit,
      ),
      revision: commit,
      completeness: omissions.isEmpty
          ? SnapshotCompleteness.complete
          : SnapshotCompleteness.partial,
      files: files,
      omissions: omissions,
    );
  }

  Future<String> _gitText(Directory root, List<String> arguments) async =>
      utf8.decode(await _gitBytes(root, arguments));

  Future<List<int>> _gitBytes(Directory root, List<String> arguments) async {
    final result = await Process.run(
      'git',
      <String>['-C', root.path, ...arguments],
      stdoutEncoding: null,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      final message = (result.stderr as String).trim();
      throw FormatException(
        'Git command failed (${result.exitCode}): $message',
      );
    }
    return (result.stdout as List<int>);
  }
}

final class LocalContextBundleExporter {
  const LocalContextBundleExporter({
    this.maxFileBytes = 1024 * 1024,
    this.maxTotalBytes = 4 * 1024 * 1024,
  });

  final int maxFileBytes;
  final int maxTotalBytes;

  ContextBundle export({
    required SourceSnapshot snapshot,
    required String root,
    required List<String> paths,
  }) {
    if (paths.isEmpty) {
      throw ArgumentError('Context export requires explicit paths');
    }
    final directory = _safeDirectory(root);
    final inventory = <String, SourceFileEntry>{
      for (final file in snapshot.files) file.path: file,
    };
    final unique = paths.toSet().toList()..sort();
    final files = <ContextFile>[];
    final redactions = <String>[];
    var total = 0;
    for (final relative in unique) {
      _validateGitPath(relative);
      final expected = inventory[relative];
      if (expected == null) {
        redactions.add('$relative:not-in-snapshot');
        continue;
      }
      if (_secretLikePath(relative)) {
        redactions.add('$relative:secret-like-path');
        continue;
      }
      final file = File(p.join(directory.path, relative));
      if (!p.isWithin(directory.path, p.normalize(file.path)) ||
          Link(file.path).existsSync() ||
          !file.existsSync()) {
        redactions.add('$relative:unsafe-or-missing');
        continue;
      }
      final bytes = file.readAsBytesSync();
      if (bytes.length > maxFileBytes || total + bytes.length > maxTotalBytes) {
        redactions.add('$relative:size-limit');
        continue;
      }
      if (Digest.bytes(bytes) != expected.digest) {
        redactions.add('$relative:changed-after-snapshot');
        continue;
      }
      try {
        var text = utf8.decode(bytes, allowMalformed: false);
        final result = _redact(text);
        text = result.$1;
        if (result.$2) redactions.add('$relative:secret-pattern');
        final sanitized = utf8.encode(text);
        total += sanitized.length;
        files.add(
          ContextFile(
            path: relative,
            digest: Digest.bytes(sanitized),
            content: text,
          ),
        );
      } on FormatException {
        redactions.add('$relative:binary-or-invalid-utf8');
      }
    }
    return ContextBundle(
      snapshotDigest: snapshot.digest,
      files: files,
      redactions: redactions,
    );
  }

  (String, bool) _redact(String source) {
    var changed = false;
    var output = source;
    final patterns = <RegExp>[
      RegExp(
        r'^\s*(authorization|cookie|set-cookie)\s*[:=].*$',
        caseSensitive: false,
        multiLine: true,
      ),
      RegExp(
        r'^\s*[A-Z0-9_]*(TOKEN|SECRET|PASSWORD|API_KEY)[A-Z0-9_]*\s*=.*$',
        caseSensitive: false,
        multiLine: true,
      ),
      RegExp(
        r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
      ),
    ];
    for (final pattern in patterns) {
      output = output.replaceAllMapped(pattern, (_) {
        changed = true;
        return '[REDACTED]';
      });
    }
    return (output, changed);
  }

  bool _secretLikePath(String value) {
    final base = p.posix.basename(value).toLowerCase();
    return base == '.env' ||
        base.startsWith('.env.') ||
        base.endsWith('.pem') ||
        base.endsWith('.key') ||
        base.contains('credential') ||
        base.contains('secret');
  }
}

Directory _safeDirectory(String value) {
  final directory = Directory(value).absolute;
  if (Link(directory.path).existsSync() || !directory.existsSync()) {
    throw FileSystemException(
      'Source root is missing or linked',
      directory.path,
    );
  }
  return Directory(directory.resolveSymbolicLinksSync());
}

String _relative(Directory root, String value) =>
    p.relative(value, from: root.path).replaceAll(p.separator, '/');

void _validateGitPath(String value) {
  final segments = value.split('/');
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      segments.contains('..') ||
      segments.contains('') ||
      value.contains('\u0000')) {
    throw FormatException('Unsafe source path: $value');
  }
}
