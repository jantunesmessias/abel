import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

import '../storage/filesystem_workspace_store.dart';

final class LocalAdoptionService {
  LocalAdoptionService({
    required String workspaceRoot,
    this.distributionId = 'full-local',
  }) : workspaceRoot = Directory(
         workspaceRoot,
       ).absolute.resolveSymbolicLinksSync(),
       store = FileSystemWorkspaceStore(
         workspaceRoot: workspaceRoot,
         distributionId: distributionId,
       ) {
    OpaqueId.validate(distributionId, 'Distribution');
  }

  static const String _manifestPath = 'adoption/manifest.json';

  final String workspaceRoot;
  final String distributionId;
  final FileSystemWorkspaceStore store;

  AdoptionReport planInit({
    String workspaceId = 'workspace',
    String displayName = 'Workspace',
    String applicationId = 'app',
  }) {
    final desired = _desiredManifest(
      workspaceId: workspaceId,
      displayName: displayName,
      applicationId: applicationId,
    );
    final existing = _loadManifest();
    if (existing != null) return _report(existing);
    final observations = <AdoptionFileObservation>[
      for (final record in desired.files) _plannedObservation(record),
    ];
    return AdoptionReport(
      distributionId: distributionId,
      adopted: false,
      canApply: observations.every(
        (observation) => observation.state == AdoptionFileState.planned,
      ),
      canDetach: false,
      files: observations,
    );
  }

  AdoptionReport applyInit({
    String workspaceId = 'workspace',
    String displayName = 'Workspace',
    String applicationId = 'app',
  }) {
    final desired = _desiredManifest(
      workspaceId: workspaceId,
      displayName: displayName,
      applicationId: applicationId,
    );
    return store.withExclusiveLock(() {
      if (_loadManifest() != null) {
        throw StateError('Workspace already has an adoption manifest');
      }
      final plan = planInit(
        workspaceId: workspaceId,
        displayName: displayName,
        applicationId: applicationId,
      );
      if (!plan.canApply) {
        throw StateError('Adoption conflicts with pre-existing files');
      }
      final sources = _desiredSources(
        workspaceId: workspaceId,
        displayName: displayName,
        applicationId: applicationId,
      );
      final written = <File>[];
      try {
        for (final entry in sources.entries) {
          final target = _workspaceFile(entry.key);
          _atomicCreate(target, entry.value);
          written.add(target);
        }
        _writeManifest(desired);
      } on Object {
        for (final file in written.reversed) {
          final bytes = sources[p.relative(file.path, from: workspaceRoot)];
          if (file.existsSync() && bytes != null) {
            if (Digest.bytes(file.readAsBytesSync()) == Digest.bytes(bytes)) {
              file.deleteSync();
            }
          }
        }
        _removeEmptyOwnedDirectories(desired.files);
        rethrow;
      }
      return _report(desired);
    });
  }

  AdoptionReport report() {
    final manifest = _loadManifest();
    return manifest == null
        ? AdoptionReport(
            distributionId: distributionId,
            adopted: false,
            canApply: false,
            canDetach: false,
            files: const <AdoptionFileObservation>[],
          )
        : _report(manifest);
  }

  AdoptionReport detach({required bool apply}) {
    final manifest = _loadManifest();
    if (manifest == null) return report();
    final before = _report(manifest);
    if (!apply) return before;
    final remaining = store.withExclusiveLock(() {
      final current = _loadManifest();
      if (current == null || current.digest != manifest.digest) {
        throw StateError('Adoption manifest changed concurrently');
      }
      final unresolved = <AdoptionFileRecord>[];
      for (final record in current.files) {
        final observation = _observe(record);
        switch (observation.state) {
          case AdoptionFileState.ownedUnmodified:
            _workspaceFile(record.path).deleteSync();
          case AdoptionFileState.missing:
            break;
          case AdoptionFileState.modified:
          case AdoptionFileState.preexisting:
          case AdoptionFileState.planned:
            unresolved.add(record);
        }
      }
      _removeEmptyOwnedDirectories(current.files);
      if (unresolved.isEmpty) {
        _deleteManifest();
        return null;
      }
      final retained = AdoptionManifest(
        distributionId: distributionId,
        files: unresolved,
      );
      _writeManifest(retained);
      return retained;
    });
    if (remaining == null) {
      _cleanupDetachedState();
      return AdoptionReport(
        distributionId: distributionId,
        adopted: false,
        canApply: false,
        canDetach: false,
        files: const <AdoptionFileObservation>[],
      );
    }
    return _report(remaining);
  }

  AdoptionManifest _desiredManifest({
    required String workspaceId,
    required String displayName,
    required String applicationId,
  }) {
    OpaqueId.validate(workspaceId, 'Workspace');
    OpaqueId.validate(applicationId, 'Application');
    if (displayName.isEmpty || displayName.length > 256) {
      throw ArgumentError.value(displayName, 'displayName');
    }
    final sources = _desiredSources(
      workspaceId: workspaceId,
      displayName: displayName,
      applicationId: applicationId,
    );
    const roles = <String, String>{
      'workspace.yaml': 'consumer-config',
      '.experience/README.md': 'living-documentation',
      '.experience/scenario.yaml': 'scenario-authoring',
      '.experience/journey.yaml': 'journey-authoring',
    };
    return AdoptionManifest(
      distributionId: distributionId,
      files: <AdoptionFileRecord>[
        for (final entry in sources.entries)
          AdoptionFileRecord(
            path: entry.key,
            role: roles[entry.key]!,
            contentDigest: Digest.bytes(entry.value),
          ),
      ],
    );
  }

  Map<String, List<int>> _desiredSources({
    required String workspaceId,
    required String displayName,
    required String applicationId,
  }) {
    final safeName = jsonEncode(displayName);
    return <String, List<int>>{
      'workspace.yaml': utf8.encode('''schemaVersion: 1
content: {root: .experience}
workspace: {id: $workspaceId, displayName: $safeName}
applications:
  $applicationId: {root: ., target: local}
'''),
      '.experience/README.md': utf8.encode('''# Product journeys

This directory contains documentation authored for Abel. It does not alter
the production entrypoint, `pubspec.yaml`, or the consumer lockfile.
'''),
      '.experience/scenario.yaml': utf8.encode('''schemaVersion: 1
kind: Scenario
metadata: {id: first-scenario}
spec:
  applicationId: $applicationId
  title: First documented scenario
'''),
      '.experience/journey.yaml': utf8.encode('''schemaVersion: 1
kind: Journey
metadata: {id: first-journey}
spec:
  applicationId: $applicationId
  title: First documented journey
  scenarioIds: [first-scenario]
'''),
    };
  }

  AdoptionFileObservation _plannedObservation(AdoptionFileRecord record) {
    final file = _workspaceFile(record.path);
    if (Link(file.path).existsSync() || file.existsSync()) {
      final digest = file.existsSync() && !Link(file.path).existsSync()
          ? Digest.bytes(file.readAsBytesSync())
          : null;
      return AdoptionFileObservation(
        path: record.path,
        role: record.role,
        state: AdoptionFileState.preexisting,
        expectedDigest: record.contentDigest,
        observedDigest: digest,
      );
    }
    return AdoptionFileObservation(
      path: record.path,
      role: record.role,
      state: AdoptionFileState.planned,
      expectedDigest: record.contentDigest,
    );
  }

  AdoptionReport _report(AdoptionManifest manifest) {
    final observations = manifest.files.map(_observe).toList(growable: false);
    return AdoptionReport(
      distributionId: distributionId,
      adopted: true,
      canApply: false,
      canDetach: true,
      manifestDigest: manifest.digest,
      files: observations,
    );
  }

  AdoptionFileObservation _observe(AdoptionFileRecord record) {
    final file = _workspaceFile(record.path);
    if (Link(file.path).existsSync()) {
      return AdoptionFileObservation(
        path: record.path,
        role: record.role,
        state: AdoptionFileState.modified,
        expectedDigest: record.contentDigest,
      );
    }
    if (!file.existsSync()) {
      return AdoptionFileObservation(
        path: record.path,
        role: record.role,
        state: AdoptionFileState.missing,
        expectedDigest: record.contentDigest,
      );
    }
    final observed = Digest.bytes(file.readAsBytesSync());
    return AdoptionFileObservation(
      path: record.path,
      role: record.role,
      state: observed == record.contentDigest
          ? AdoptionFileState.ownedUnmodified
          : AdoptionFileState.modified,
      expectedDigest: record.contentDigest,
      observedDigest: observed,
    );
  }

  AdoptionManifest? _loadManifest() {
    final bytes = store.readStateBytes(_manifestPath);
    if (bytes == null) return null;
    return AdoptionManifest.fromJson(jsonDecode(utf8.decode(bytes)));
  }

  void _writeManifest(AdoptionManifest manifest) {
    store.atomicWrite(
      _manifestPath,
      utf8.encode(
        '${const JcsCanonicalizer().canonicalize(manifest.toJson())}\n',
      ),
    );
  }

  void _deleteManifest() {
    final file = File(p.join(store.stateRoot, _manifestPath));
    if (file.existsSync()) file.deleteSync();
    final directory = file.parent;
    if (directory.existsSync() && directory.listSync().isEmpty) {
      directory.deleteSync();
    }
  }

  File _workspaceFile(String relativePath) {
    final normalized = p.normalize(p.join(workspaceRoot, relativePath));
    if (!p.isWithin(workspaceRoot, normalized)) {
      throw FileSystemException('Adoption path escapes workspace', normalized);
    }
    var parent = File(normalized).parent;
    while (parent.path != workspaceRoot) {
      if (Link(parent.path).existsSync()) {
        throw FileSystemException(
          'Adoption path crosses a symlink',
          parent.path,
        );
      }
      parent = parent.parent;
    }
    return File(normalized);
  }

  void _atomicCreate(File target, List<int> bytes) {
    if (target.existsSync() || Link(target.path).existsSync()) {
      throw FileSystemException('Adoption target already exists', target.path);
    }
    target.parent.createSync(recursive: true);
    final temporary = File('${target.path}.workspace-new-$pid');
    if (temporary.existsSync() || Link(temporary.path).existsSync()) {
      throw FileSystemException('Adoption staging path exists', temporary.path);
    }
    try {
      temporary.writeAsBytesSync(bytes, flush: true);
      temporary.renameSync(target.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  void _removeEmptyOwnedDirectories(List<AdoptionFileRecord> records) {
    final directories =
        records
            .map((record) => _workspaceFile(record.path).parent)
            .where((directory) => directory.path != workspaceRoot)
            .toSet()
            .toList()
          ..sort(
            (left, right) => right.path.length.compareTo(left.path.length),
          );
    for (final directory in directories) {
      if (directory.existsSync() && directory.listSync().isEmpty) {
        directory.deleteSync();
      }
    }
  }

  void _cleanupDetachedState() {
    final root = Directory(store.stateRoot);
    final lock = File(p.join(root.path, 'workspace.lock'));
    final entries = root.existsSync()
        ? root.listSync(recursive: true).whereType<File>().toList()
        : const <File>[];
    if (entries.every((file) => file.path == lock.path)) {
      if (lock.existsSync()) lock.deleteSync();
      if (root.existsSync()) root.deleteSync(recursive: true);
      final workspace = root.parent;
      if (workspace.existsSync() && workspace.listSync().isEmpty) {
        workspace.deleteSync();
      }
      final dartTool = workspace.parent;
      if (dartTool.existsSync() && dartTool.listSync().isEmpty) {
        dartTool.deleteSync();
      }
    }
  }
}
