import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:path/path.dart' as p;

import '../storage/filesystem_workspace_store.dart';

enum LegacyMigrationMode { inspect, dryRun, apply, rollback }

final class LegacyMigrationReport {
  LegacyMigrationReport({
    required this.migrationId,
    required this.mode,
    required this.changed,
    required this.verified,
    required this.sourceDigest,
    required this.mappingDigest,
    required this.outputRoot,
    required Map<String, Digest> documents,
    required List<String> actions,
    this.quarantinePath,
  }) : documents = Map<String, Digest>.unmodifiable(documents),
       actions = List<String>.unmodifiable(actions);

  final String migrationId;
  final LegacyMigrationMode mode;
  final bool changed;
  final bool verified;
  final Digest sourceDigest;
  final Digest mappingDigest;
  final String outputRoot;
  final Map<String, Digest> documents;
  final List<String> actions;
  final String? quarantinePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'migrationId': migrationId,
    'mode': mode.name,
    'changed': changed,
    'verified': verified,
    'sourceDigest': sourceDigest.value,
    'mappingDigest': mappingDigest.value,
    'outputRoot': outputRoot,
    'documents': <String, String>{
      for (final key in documents.keys.toList()..sort())
        key: documents[key]!.value,
    },
    'actions': actions,
    if (quarantinePath != null) 'quarantinePath': quarantinePath,
  };
}

final class LegacyConfigurationMigrator {
  LegacyConfigurationMigrator({
    required String workspaceRoot,
    SafeAuthoringParser parser = const SafeAuthoringParser(),
  }) : this._(
         workspaceRoot: Directory(
           workspaceRoot,
         ).absolute.resolveSymbolicLinksSync(),
         store: FileSystemWorkspaceStore(workspaceRoot: workspaceRoot),
         parser: parser,
       );

  LegacyConfigurationMigrator._({
    required this.workspaceRoot,
    required this.store,
    required this._parser,
  });

  static const String markerName = '.devex-migration-v1.json';

  final String workspaceRoot;
  final FileSystemWorkspaceStore store;
  final SafeAuthoringParser _parser;

  LegacyMigrationReport migrate({
    required String sourcePath,
    required String mappingPath,
    required String outputRoot,
    required bool apply,
  }) {
    final source = _readBounded(sourcePath, 'legacy source');
    final mappingBytes = _readBounded(mappingPath, 'legacy mapping');
    final sourceDigest = Digest.bytes(source);
    final mappingDigest = Digest.bytes(mappingBytes);
    final sourceObject = _parser.parseObject(
      utf8.decode(source),
      sourceName: sourcePath,
    );
    final mapping = _LegacyMapping.parse(
      _parser.parseObject(utf8.decode(mappingBytes), sourceName: mappingPath),
    );
    final outputDirectory = _workspaceDirectory(outputRoot);
    final rendered = _render(mapping, sourceObject);
    final documentDigests = <String, Digest>{
      for (final entry in rendered.entries)
        entry.key: Digest.bytes(entry.value),
    };
    final existing = _readMarker(outputDirectory);
    if (existing != null) {
      final same =
          existing.migrationId == mapping.id &&
          existing.sourceDigest == sourceDigest &&
          existing.mappingDigest == mappingDigest &&
          _verifyFiles(outputDirectory, existing.documents);
      if (!same) {
        throw StateError('Migration output is already owned by another input');
      }
      if (apply) {
        store.withExclusiveLock(() => _writeActivePin(existing));
      }
      return LegacyMigrationReport(
        migrationId: mapping.id,
        mode: apply ? LegacyMigrationMode.apply : LegacyMigrationMode.dryRun,
        changed: false,
        verified: true,
        sourceDigest: sourceDigest,
        mappingDigest: mappingDigest,
        outputRoot: p.relative(outputDirectory.path, from: workspaceRoot),
        documents: existing.documents,
        actions: const <String>['reuse verified migration output'],
      );
    }
    if (outputDirectory.existsSync()) {
      throw FileSystemException(
        'Migration output directory already exists without ownership marker',
        outputDirectory.path,
      );
    }
    const actions = <String>[
      'parse bounded legacy input without eval',
      'render canonical v1 authoring documents',
      'back up source and mapping by digest',
      'publish the owned output directory atomically',
    ];
    if (!apply) {
      return LegacyMigrationReport(
        migrationId: mapping.id,
        mode: LegacyMigrationMode.dryRun,
        changed: true,
        verified: false,
        sourceDigest: sourceDigest,
        mappingDigest: mappingDigest,
        outputRoot: p.relative(outputDirectory.path, from: workspaceRoot),
        documents: documentDigests,
        actions: actions,
      );
    }

    late final Digest sourceBackup;
    late final Digest mappingBackup;
    store.withExclusiveLock(() {
      sourceBackup = store.putBlob(source);
      mappingBackup = store.putBlob(mappingBytes);
    });
    final stage = Directory(
      '${outputDirectory.path}.stage-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (stage.existsSync() || Link(stage.path).existsSync()) {
      throw FileSystemException(
        'Migration stage path is not clean',
        stage.path,
      );
    }
    final marker = _MigrationMarker(
      migrationId: mapping.id,
      sourceDigest: sourceDigest,
      mappingDigest: mappingDigest,
      sourceBackupDigest: sourceBackup,
      mappingBackupDigest: mappingBackup,
      documents: documentDigests,
    );
    stage.createSync(recursive: true);
    try {
      for (final entry in rendered.entries) {
        final file = File(p.join(stage.path, entry.key));
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(entry.value, flush: true);
      }
      File(p.join(stage.path, markerName)).writeAsStringSync(
        '${const JcsCanonicalizer().canonicalize(marker.toJson())}\n',
        flush: true,
      );
      outputDirectory.parent.createSync(recursive: true);
      stage.renameSync(outputDirectory.path);
      store.withExclusiveLock(() => _writeActivePin(marker));
    } finally {
      if (stage.existsSync()) stage.deleteSync(recursive: true);
    }
    final verified = _verifyFiles(outputDirectory, documentDigests);
    if (!verified) {
      throw StateError('Legacy migration failed post-apply verification');
    }
    return LegacyMigrationReport(
      migrationId: mapping.id,
      mode: LegacyMigrationMode.apply,
      changed: true,
      verified: true,
      sourceDigest: sourceDigest,
      mappingDigest: mappingDigest,
      outputRoot: p.relative(outputDirectory.path, from: workspaceRoot),
      documents: documentDigests,
      actions: actions,
    );
  }

  LegacyMigrationReport verify({required String outputRoot}) {
    final outputDirectory = _workspaceDirectory(outputRoot);
    final marker = _readMarker(outputDirectory);
    if (marker == null) throw StateError('No owned legacy migration output');
    return LegacyMigrationReport(
      migrationId: marker.migrationId,
      mode: LegacyMigrationMode.inspect,
      changed: false,
      verified: _verifyFiles(outputDirectory, marker.documents),
      sourceDigest: marker.sourceDigest,
      mappingDigest: marker.mappingDigest,
      outputRoot: p.relative(outputDirectory.path, from: workspaceRoot),
      documents: marker.documents,
      actions: const <String>[
        'verify every owned document digest',
        'verify source and mapping backups remain readable',
      ],
    );
  }

  LegacyMigrationReport rollback({
    required String outputRoot,
    required bool apply,
  }) {
    final outputDirectory = _workspaceDirectory(outputRoot);
    final marker = _readMarker(outputDirectory);
    if (marker == null) throw StateError('No owned legacy migration output');
    if (!_verifyFiles(outputDirectory, marker.documents)) {
      throw StateError(
        'Refusing rollback because an owned output was modified',
      );
    }
    const actions = <String>[
      'verify every owned output is unmodified',
      'move the owned directory to recoverable quarantine',
    ];
    if (!apply) {
      return LegacyMigrationReport(
        migrationId: marker.migrationId,
        mode: LegacyMigrationMode.dryRun,
        changed: true,
        verified: false,
        sourceDigest: marker.sourceDigest,
        mappingDigest: marker.mappingDigest,
        outputRoot: p.relative(outputDirectory.path, from: workspaceRoot),
        documents: marker.documents,
        actions: actions,
      );
    }
    final quarantineRelative = p.join(
      'migrations',
      'quarantine',
      '${marker.migrationId}-${DateTime.now().toUtc().microsecondsSinceEpoch}',
    );
    final quarantine = Directory(p.join(store.stateRoot, quarantineRelative));
    quarantine.parent.createSync(recursive: true);
    outputDirectory.renameSync(quarantine.path);
    store.withExclusiveLock(() => _deleteActivePin(marker.migrationId));
    return LegacyMigrationReport(
      migrationId: marker.migrationId,
      mode: LegacyMigrationMode.rollback,
      changed: true,
      verified:
          !outputDirectory.existsSync() &&
          _verifyFiles(quarantine, marker.documents),
      sourceDigest: marker.sourceDigest,
      mappingDigest: marker.mappingDigest,
      outputRoot: p.relative(outputDirectory.path, from: workspaceRoot),
      documents: marker.documents,
      actions: actions,
      quarantinePath: p.relative(quarantine.path, from: workspaceRoot),
    );
  }

  Map<String, List<int>> _render(
    _LegacyMapping mapping,
    Map<String, Object?> source,
  ) {
    final output = <String, List<int>>{};
    for (final document in mapping.documents) {
      final idValue = document.id.resolve(source);
      if (idValue is! String) {
        throw FormatException('Mapped authoring ID must resolve to a string');
      }
      final spec = <String, Object?>{
        for (final entry in document.spec.entries)
          entry.key: entry.value.resolve(source),
      };
      final value = <String, Object?>{
        'schemaVersion': 1,
        'kind': _authoringKindName(document.kind),
        'metadata': <String, Object?>{'id': idValue},
        'spec': spec,
      };
      final canonical = const JcsCanonicalizer().canonicalize(value);
      _parser.parse(canonical, sourceName: document.output);
      output[document.output] = utf8.encode('$canonical\n');
    }
    return output;
  }

  bool _verifyFiles(Directory root, Map<String, Digest> documents) {
    if (!root.existsSync() || Link(root.path).existsSync()) return false;
    for (final entry in documents.entries) {
      final file = File(p.join(root.path, entry.key));
      if (!file.existsSync() ||
          Link(file.path).existsSync() ||
          Digest.bytes(file.readAsBytesSync()) != entry.value) {
        return false;
      }
    }
    final allowed = <String>{...documents.keys, markerName};
    final files = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) => p.relative(file.path, from: root.path))
        .toSet();
    return files.length == allowed.length && files.containsAll(allowed);
  }

  _MigrationMarker? _readMarker(Directory output) {
    final file = File(p.join(output.path, markerName));
    if (!file.existsSync() || Link(file.path).existsSync()) return null;
    final marker = _MigrationMarker.fromJson(
      jsonDecode(utf8.decode(_readBounded(file.path, 'migration marker'))),
    );
    if (store.readBlob(marker.sourceBackupDigest) == null ||
        store.readBlob(marker.mappingBackupDigest) == null) {
      throw StateError('Legacy migration backup is missing or corrupt');
    }
    return marker;
  }

  Directory _workspaceDirectory(String relative) {
    if (p.isAbsolute(relative) ||
        relative.isEmpty ||
        p.split(p.normalize(relative)).contains('..')) {
      throw FormatException('Migration output must be workspace-relative');
    }
    final path = p.normalize(p.join(workspaceRoot, relative));
    if (!p.isWithin(workspaceRoot, path)) {
      throw FormatException('Migration output escapes the workspace');
    }
    var current = Directory(workspaceRoot);
    for (final segment in p.split(p.relative(path, from: workspaceRoot))) {
      current = Directory(p.join(current.path, segment));
      if (Link(current.path).existsSync()) {
        throw FileSystemException('Migration path cannot contain symlinks');
      }
    }
    return Directory(path);
  }

  void _writeActivePin(_MigrationMarker marker) {
    store.atomicWrite(
      p.join('migrations', 'active', '${marker.migrationId}.json'),
      utf8.encode(
        '${const JcsCanonicalizer().canonicalize(marker.toJson())}\n',
      ),
    );
  }

  void _deleteActivePin(String migrationId) {
    OpaqueId.validate(migrationId, 'LegacyMigration');
    final file = File(
      p.join(store.stateRoot, 'migrations', 'active', '$migrationId.json'),
    );
    if (file.existsSync()) file.deleteSync();
  }
}

final class _LegacyMapping {
  const _LegacyMapping({required this.id, required this.documents});

  final String id;
  final List<_LegacyDocumentMapping> documents;

  factory _LegacyMapping.parse(Map<String, Object?> json) {
    _only(json, const <String>{
      'schemaVersion',
      'migrationId',
      'documents',
    }, 'LegacyMapping');
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported legacy mapping version');
    }
    final id = _string(json, 'migrationId', 'LegacyMapping');
    OpaqueId.validate(id, 'LegacyMigration');
    final documentsValue = json['documents'];
    if (documentsValue is! List<Object?> ||
        documentsValue.isEmpty ||
        documentsValue.length > 256) {
      throw const FormatException('Legacy mapping documents are invalid');
    }
    final documents = documentsValue.map(_LegacyDocumentMapping.parse).toList();
    if (documents.map((value) => value.output).toSet().length !=
        documents.length) {
      throw const FormatException('Legacy mapping outputs must be unique');
    }
    return _LegacyMapping(id: id, documents: documents);
  }
}

final class _LegacyDocumentMapping {
  const _LegacyDocumentMapping({
    required this.output,
    required this.kind,
    required this.id,
    required this.spec,
  });

  final String output;
  final AuthoringKind kind;
  final _MappingValue id;
  final Map<String, _MappingValue> spec;

  factory _LegacyDocumentMapping.parse(Object? value) {
    final json = _object(value, 'LegacyDocumentMapping');
    _only(json, const <String>{
      'output',
      'kind',
      'id',
      'spec',
    }, 'LegacyDocumentMapping');
    final output = _string(json, 'output', 'LegacyDocumentMapping');
    if (p.isAbsolute(output) ||
        !output.endsWith('.json') ||
        p.split(p.normalize(output)).contains('..')) {
      throw const FormatException('Legacy mapping output must be safe JSON');
    }
    final kindName = _string(json, 'kind', 'LegacyDocumentMapping');
    final kind = AuthoringKind.values.where(
      (candidate) => candidate.name.toLowerCase() == kindName.toLowerCase(),
    );
    if (kind.length != 1) throw FormatException('Unsupported kind $kindName');
    final specJson = _object(json['spec'], 'LegacyDocumentMapping.spec');
    return _LegacyDocumentMapping(
      output: output,
      kind: kind.single,
      id: _MappingValue.parse(json['id']),
      spec: <String, _MappingValue>{
        for (final entry in specJson.entries)
          entry.key: _MappingValue.parse(entry.value),
      },
    );
  }
}

final class _MappingValue {
  const _MappingValue.pointer(this.value) : literal = false;
  const _MappingValue.literal(this.value) : literal = true;

  final Object? value;
  final bool literal;

  factory _MappingValue.parse(Object? value) {
    final json = _object(value, 'MappingValue');
    if (json.length != 1) {
      throw const FormatException('Mapping value needs one pointer or literal');
    }
    if (json.containsKey('pointer')) {
      final pointer = json['pointer'];
      if (pointer is! String || !_pointer.hasMatch(pointer)) {
        throw const FormatException('Mapping pointer must be a JSON Pointer');
      }
      return _MappingValue.pointer(pointer);
    }
    if (json.containsKey('literal')) {
      return _MappingValue.literal(json['literal']);
    }
    throw const FormatException('Unknown mapping value operation');
  }

  Object? resolve(Map<String, Object?> source) =>
      literal ? value : _resolvePointer(source, value! as String);
}

final class _MigrationMarker {
  const _MigrationMarker({
    required this.migrationId,
    required this.sourceDigest,
    required this.mappingDigest,
    required this.sourceBackupDigest,
    required this.mappingBackupDigest,
    required this.documents,
  });

  final String migrationId;
  final Digest sourceDigest;
  final Digest mappingDigest;
  final Digest sourceBackupDigest;
  final Digest mappingBackupDigest;
  final Map<String, Digest> documents;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'migrationId': migrationId,
    'sourceDigest': sourceDigest.value,
    'mappingDigest': mappingDigest.value,
    'sourceBackupDigest': sourceBackupDigest.value,
    'mappingBackupDigest': mappingBackupDigest.value,
    'documents': <String, String>{
      for (final key in documents.keys.toList()..sort())
        key: documents[key]!.value,
    },
  };

  factory _MigrationMarker.fromJson(Object? value) {
    final json = _object(value, 'MigrationMarker');
    _only(json, const <String>{
      'schemaVersion',
      'migrationId',
      'sourceDigest',
      'mappingDigest',
      'sourceBackupDigest',
      'mappingBackupDigest',
      'documents',
    }, 'MigrationMarker');
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Invalid migration marker version');
    }
    final documentsJson = _object(
      json['documents'],
      'MigrationMarker.documents',
    );
    return _MigrationMarker(
      migrationId: _string(json, 'migrationId', 'MigrationMarker'),
      sourceDigest: Digest(_string(json, 'sourceDigest', 'MigrationMarker')),
      mappingDigest: Digest(_string(json, 'mappingDigest', 'MigrationMarker')),
      sourceBackupDigest: Digest(
        _string(json, 'sourceBackupDigest', 'MigrationMarker'),
      ),
      mappingBackupDigest: Digest(
        _string(json, 'mappingBackupDigest', 'MigrationMarker'),
      ),
      documents: <String, Digest>{
        for (final entry in documentsJson.entries)
          entry.key: entry.value is String
              ? Digest(entry.value! as String)
              : throw const FormatException(
                  'Invalid migration document digest',
                ),
      },
    );
  }
}

List<int> _readBounded(String path, String label) {
  final file = File(path).absolute;
  if (!file.existsSync() || Link(file.path).existsSync()) {
    throw FileSystemException('$label is absent or a symlink', file.path);
  }
  final length = file.lengthSync();
  if (length < 1 || length > 8 * 1024 * 1024) {
    throw FormatException('$label exceeds the 8 MiB limit');
  }
  return file.readAsBytesSync();
}

Object? _resolvePointer(Object? source, String pointer) {
  if (pointer.isEmpty) return source;
  var current = source;
  for (final raw in pointer.substring(1).split('/')) {
    final token = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is Map<String, Object?> && current.containsKey(token)) {
      current = current[token];
    } else if (current is List<Object?>) {
      final index = int.tryParse(token);
      if (index == null || index < 0 || index >= current.length) {
        throw StateError('Legacy mapping pointer is unresolved');
      }
      current = current[index];
    } else {
      throw StateError('Legacy mapping pointer is unresolved');
    }
  }
  return current;
}

String _authoringKindName(AuthoringKind kind) =>
    '${kind.name[0].toUpperCase()}${kind.name.substring(1)}';

Map<String, Object?> _object(Object? value, String context) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$context must be an object');
  }
  final output = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('$context key is invalid');
    output[entry.key! as String] = entry.value;
  }
  return output;
}

void _only(Map<String, Object?> value, Set<String> fields, String context) {
  if (value.keys.any((key) => !fields.contains(key))) {
    throw FormatException('$context contains an unknown field');
  }
}

String _string(Map<String, Object?> value, String key, String context) {
  final item = value[key];
  if (item is! String || item.isEmpty) {
    throw FormatException('$context.$key must be a non-empty string');
  }
  return item;
}

final RegExp _pointer = RegExp(r'^(?:/(?:[^~/]|~[01])*)*$');
