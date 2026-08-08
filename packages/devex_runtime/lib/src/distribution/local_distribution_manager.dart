import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;

import 'local_distribution_bundle.dart';

final class DistributionInstallStatus {
  const DistributionInstallStatus({
    required this.installed,
    required this.healthy,
    this.distributionId,
    this.currentVersion,
    this.currentDigest,
    this.previousVersion,
    this.migrationRequired = false,
  });

  final bool installed;
  final bool healthy;
  final String? distributionId;
  final String? currentVersion;
  final Digest? currentDigest;
  final String? previousVersion;
  final bool migrationRequired;

  Map<String, Object?> toJson() => <String, Object?>{
    'installed': installed,
    'healthy': healthy,
    'migrationRequired': migrationRequired,
    if (distributionId != null) 'distributionId': distributionId,
    if (currentVersion != null) 'currentVersion': currentVersion,
    if (currentDigest != null) 'currentDigest': currentDigest!.value,
    if (previousVersion != null) 'previousVersion': previousVersion,
  };
}

final class DistributionMigrationPlan {
  const DistributionMigrationPlan({
    required this.required,
    required this.fromSchemaVersion,
    required this.toSchemaVersion,
    required this.backupPresent,
  });

  final bool required;
  final int fromSchemaVersion;
  final int toSchemaVersion;
  final bool backupPresent;

  Map<String, Object?> toJson() => <String, Object?>{
    'required': required,
    'fromSchemaVersion': fromSchemaVersion,
    'toSchemaVersion': toSchemaVersion,
    'backupPresent': backupPresent,
  };
}

final class LocalDistributionManager {
  LocalDistributionManager({required String installRoot})
    : installRoot = Directory(installRoot).absolute.path {
    final parsed = p.normalize(this.installRoot);
    final filesystemRoot = p.rootPrefix(parsed);
    final home = Platform.environment['HOME'];
    if (parsed == filesystemRoot ||
        (home != null && parsed == p.normalize(home))) {
      throw ArgumentError('installRoot is too broad');
    }
    _rejectLinkedAncestors(parsed);
  }

  static const String _stateName = 'install-state.json';
  static const String _backupName = 'install-state.v0.backup.json';
  static const String _lockName = 'install.lock';

  final String installRoot;
  static const LocalDistributionBundleRepository _bundles =
      LocalDistributionBundleRepository();

  Future<DistributionInstallStatus> install(String bundleDirectory) async {
    final source = await _bundles.verify(bundleDirectory);
    final root = Directory(installRoot)..createSync(recursive: true);
    _rejectLinkedAncestors(root.path);
    final staging = Directory(
      p.join(root.path, '.staging-${source.releaseVersion}-$pid'),
    );
    if (staging.existsSync() || Link(staging.path).existsSync()) {
      throw FileSystemException(
        'Distribution staging path exists',
        staging.path,
      );
    }
    try {
      _copyVerifiedBundle(
        sourceRoot: Directory(bundleDirectory).absolute.path,
        targetRoot: staging.path,
        manifest: source,
      );
      final staged = await _bundles.verify(staging.path);
      if (staged.digest != source.digest) {
        throw StateError('Staged distribution digest differs');
      }
      return await _withLock(() async {
        final state = _readState();
        if (state != null && state.schemaVersion != 1) {
          throw StateError('Distribution state migration is required');
        }
        if (state != null && state.distributionId != source.distributionId) {
          throw StateError('Installed distribution ID differs');
        }
        final previousManifest = state == null
            ? null
            : await _bundles.verify(
                p.join(root.path, 'releases', state.currentVersion),
              );
        final release = Directory(
          p.join(root.path, 'releases', source.releaseVersion),
        );
        if (release.existsSync() || Link(release.path).existsSync()) {
          if (Link(release.path).existsSync()) {
            throw StateError('Installed release path is a symlink');
          }
          final existing = await _bundles.verify(release.path);
          if (existing.digest != source.digest) {
            throw StateError('Release version already exists with other bytes');
          }
          staging.deleteSync(recursive: true);
        } else {
          release.parent.createSync(recursive: true);
          staging.renameSync(release.path);
        }
        final next = _InstallState(
          distributionId: source.distributionId,
          currentVersion: source.releaseVersion,
          currentDigest: source.digest,
          previousVersion: state?.currentVersion == source.releaseVersion
              ? state?.previousVersion
              : state?.currentVersion,
          previousDigest: state?.currentVersion == source.releaseVersion
              ? state?.previousDigest
              : state?.currentDigest,
        );
        _ensureLaunchers(source, previous: previousManifest);
        _switchCurrent(next.currentVersion);
        _writeState(next);
        return _statusFor(next);
      });
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  Future<DistributionInstallStatus> rollback() async {
    return _withLock(() async {
      final state = _readState();
      if (state == null || state.schemaVersion != 1) {
        throw StateError('No current distribution is installed');
      }
      final previousVersion = state.previousVersion;
      final previousDigest = state.previousDigest;
      if (previousVersion == null || previousDigest == null) {
        throw StateError('No previous distribution is available');
      }
      final previous = await _bundles.verify(
        p.join(installRoot, 'releases', previousVersion),
      );
      if (previous.digest != previousDigest) {
        throw StateError('Previous distribution digest is invalid');
      }
      final current = await _bundles.verify(
        p.join(installRoot, 'releases', state.currentVersion),
      );
      _ensureLaunchers(previous, previous: current);
      _switchCurrent(previousVersion);
      final rolledBack = _InstallState(
        distributionId: state.distributionId,
        currentVersion: previousVersion,
        currentDigest: previousDigest,
        previousVersion: state.currentVersion,
        previousDigest: state.currentDigest,
      );
      _writeState(rolledBack);
      return _statusFor(rolledBack);
    });
  }

  Future<DistributionInstallStatus> status() async {
    if (!Directory(installRoot).existsSync()) {
      return const DistributionInstallStatus(installed: false, healthy: true);
    }
    final state = _readState();
    if (state == null) {
      return const DistributionInstallStatus(installed: false, healthy: false);
    }
    if (state.schemaVersion == 0) {
      return DistributionInstallStatus(
        installed: true,
        healthy: false,
        distributionId: state.distributionId,
        currentVersion: state.currentVersion,
        currentDigest: state.currentDigest,
        migrationRequired: true,
      );
    }
    return _statusFor(state);
  }

  DistributionMigrationPlan inspectMigration() {
    final state = _readState();
    final version = state?.schemaVersion ?? 1;
    return DistributionMigrationPlan(
      required: version == 0,
      fromSchemaVersion: version,
      toSchemaVersion: 1,
      backupPresent: File(p.join(installRoot, _backupName)).existsSync(),
    );
  }

  Future<DistributionMigrationPlan> migrateState({required bool apply}) async {
    final plan = inspectMigration();
    if (!plan.required || !apply) return plan;
    return _withLock(() async {
      final stateFile = File(p.join(installRoot, _stateName));
      final sourceBytes = stateFile.readAsBytesSync();
      final state = _readState();
      if (state == null || state.schemaVersion != 0) {
        throw StateError('Distribution state no longer requires migration');
      }
      final release = await _bundles.verify(
        p.join(installRoot, 'releases', state.currentVersion),
      );
      if (release.digest != state.currentDigest ||
          release.distributionId != state.distributionId) {
        throw StateError('Legacy distribution state cannot be verified');
      }
      final backup = File(p.join(installRoot, _backupName));
      if (backup.existsSync() || Link(backup.path).existsSync()) {
        throw StateError('Migration backup already exists');
      }
      _atomicWrite(backup, sourceBytes);
      _writeState(
        _InstallState(
          distributionId: state.distributionId,
          currentVersion: state.currentVersion,
          currentDigest: state.currentDigest,
          previousVersion: null,
          previousDigest: null,
        ),
      );
      _switchCurrent(state.currentVersion);
      final verified = _readState();
      if (verified?.schemaVersion != 1) {
        throw StateError('Distribution migration verification failed');
      }
      return inspectMigration();
    });
  }

  Future<DistributionMigrationPlan> rollbackMigration() async {
    return _withLock(() async {
      final backup = File(p.join(installRoot, _backupName));
      if (!backup.existsSync() || Link(backup.path).existsSync()) {
        throw StateError('No migration backup is available');
      }
      final decoded = jsonDecode(backup.readAsStringSync());
      final legacy = _InstallState.fromJson(decoded);
      if (legacy.schemaVersion != 0) {
        throw StateError('Migration backup is not a legacy state');
      }
      _atomicWrite(
        File(p.join(installRoot, _stateName)),
        backup.readAsBytesSync(),
      );
      backup.deleteSync();
      return inspectMigration();
    });
  }

  Future<DistributionInstallStatus> _statusFor(_InstallState state) async {
    try {
      final release = await _bundles.verify(
        p.join(installRoot, 'releases', state.currentVersion),
      );
      final current = Link(p.join(installRoot, 'current'));
      final expectedCurrent = p.join('releases', state.currentVersion);
      final launchersHealthy = _launchersMatch(release);
      final healthy =
          release.digest == state.currentDigest &&
          current.existsSync() &&
          current.targetSync() == expectedCurrent &&
          launchersHealthy;
      return DistributionInstallStatus(
        installed: true,
        healthy: healthy,
        distributionId: state.distributionId,
        currentVersion: state.currentVersion,
        currentDigest: state.currentDigest,
        previousVersion: state.previousVersion,
      );
    } on Object {
      return DistributionInstallStatus(
        installed: true,
        healthy: false,
        distributionId: state.distributionId,
        currentVersion: state.currentVersion,
        currentDigest: state.currentDigest,
        previousVersion: state.previousVersion,
      );
    }
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    Directory(installRoot).createSync(recursive: true);
    final file = File(
      p.join(installRoot, _lockName),
    ).openSync(mode: FileMode.append);
    try {
      file.lockSync(FileLock.exclusive);
      return await action();
    } finally {
      file.unlockSync();
      file.closeSync();
    }
  }

  _InstallState? _readState() {
    final file = File(p.join(installRoot, _stateName));
    if (!file.existsSync()) return null;
    if (Link(file.path).existsSync() || file.lengthSync() > 1024 * 1024) {
      throw const FormatException('Distribution install state is unsafe');
    }
    return _InstallState.fromJson(jsonDecode(file.readAsStringSync()));
  }

  void _writeState(_InstallState state) {
    _atomicWrite(
      File(p.join(installRoot, _stateName)),
      utf8.encode('${const JcsCanonicalizer().canonicalize(state.toJson())}\n'),
    );
  }

  void _copyVerifiedBundle({
    required String sourceRoot,
    required String targetRoot,
    required DistributionRelease manifest,
  }) {
    final target = Directory(targetRoot)..createSync();
    for (final file in <DistributionFile>[
      ...manifest.files,
      DistributionFile(
        path: LocalDistributionBundleRepository.descriptorName,
        digest: Digest.semantic(manifest.toJson()),
        size: 0,
        executable: false,
        role: 'descriptor',
      ),
    ]) {
      final relative = file.path;
      final source = File(p.join(sourceRoot, relative));
      final destination = File(p.join(target.path, relative));
      destination.parent.createSync(recursive: true);
      source.copySync(destination.path);
      final chmod = Process.runSync('chmod', <String>[
        file.executable ? '755' : '644',
        destination.path,
      ]);
      if (chmod.exitCode != 0) throw StateError('chmod failed during install');
    }
  }

  void _ensureLaunchers(
    DistributionRelease manifest, {
    DistributionRelease? previous,
  }) {
    final bin = Directory(p.join(installRoot, 'bin'));
    if (Link(bin.path).existsSync()) throw StateError('bin is a symlink');
    bin.createSync(recursive: true);
    final launchers = _launcherTargets(manifest);
    final previousLaunchers = previous == null
        ? const <String, String>{}
        : _launcherTargets(previous);
    final removedLaunchers = previousLaunchers.keys.toSet().difference(
      launchers.keys.toSet(),
    );
    for (final name in removedLaunchers) {
      final link = Link(p.join(bin.path, name));
      final expected = previousLaunchers[name]!;
      if (!link.existsSync() || link.targetSync() != expected) {
        throw StateError('Removed launcher is not manager-owned: $name');
      }
      link.deleteSync();
    }
    for (final entry in launchers.entries) {
      final link = Link(p.join(bin.path, entry.key));
      if (link.existsSync()) {
        if (link.targetSync() != entry.value) {
          throw StateError('Launcher target differs: ${entry.key}');
        }
      } else if (File(link.path).existsSync() ||
          Directory(link.path).existsSync()) {
        throw StateError('Launcher path is occupied: ${entry.key}');
      } else {
        link.createSync(entry.value);
      }
    }
  }

  bool _launchersMatch(DistributionRelease manifest) {
    final expected = _launcherTargets(manifest);
    final bin = Directory(p.join(installRoot, 'bin'));
    if (!bin.existsSync() || Link(bin.path).existsSync()) return false;
    final names = bin
        .listSync(followLinks: false)
        .map((entity) => p.basename(entity.path))
        .toSet();
    if (names.length != expected.length || !names.containsAll(expected.keys)) {
      return false;
    }
    return expected.entries.every((entry) {
      final link = Link(p.join(installRoot, 'bin', entry.key));
      return link.existsSync() && link.targetSync() == entry.value;
    });
  }

  Map<String, String> _launcherTargets(DistributionRelease manifest) =>
      <String, String>{
        for (final alias in manifest.commandAliases.keys)
          alias: p.join('..', 'current', manifest.entrypoints['cli']!),
        if (manifest.entrypoints['host'] case final host?)
          'devex_host': p.join('..', 'current', host),
        if (manifest.entrypoints['gateway'] case final gateway?)
          'backend_gateway': p.join('..', 'current', gateway),
      };

  void _switchCurrent(String version) {
    final current = Link(p.join(installRoot, 'current'));
    if (!current.existsSync() &&
        (File(current.path).existsSync() ||
            Directory(current.path).existsSync())) {
      throw StateError('current path is not a managed symlink');
    }
    final temporary = Link('${current.path}.new-$pid');
    if (temporary.existsSync()) temporary.deleteSync();
    temporary.createSync(p.join('releases', version));
    try {
      temporary.renameSync(current.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  void _atomicWrite(File target, List<int> bytes) {
    final temporary = File('${target.path}.new-$pid');
    if (temporary.existsSync() || Link(temporary.path).existsSync()) {
      throw FileSystemException('Atomic staging path exists', temporary.path);
    }
    try {
      temporary.writeAsBytesSync(bytes, flush: true);
      temporary.renameSync(target.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  static void _rejectLinkedAncestors(String path) {
    var current = Directory(p.normalize(path));
    while (current.path != current.parent.path) {
      if (Link(current.path).existsSync()) {
        throw ArgumentError('installRoot crosses a symlink');
      }
      current = current.parent;
    }
  }
}

final class _InstallState {
  _InstallState({
    this.schemaVersion = 1,
    required this.distributionId,
    required this.currentVersion,
    required this.currentDigest,
    required this.previousVersion,
    required this.previousDigest,
  }) {
    if (schemaVersion != 0 && schemaVersion != 1) {
      throw ArgumentError.value(schemaVersion, 'schemaVersion');
    }
    OpaqueId.validate(distributionId, 'Distribution');
    _stateVersion(currentVersion);
    if ((previousVersion == null) != (previousDigest == null)) {
      throw ArgumentError('Previous version and digest must be paired');
    }
    if (previousVersion != null) _stateVersion(previousVersion!);
  }

  final int schemaVersion;
  final String distributionId;
  final String currentVersion;
  final Digest currentDigest;
  final String? previousVersion;
  final Digest? previousDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'distributionId': distributionId,
    if (schemaVersion == 0) ...<String, Object?>{
      'version': currentVersion,
      'digest': currentDigest.value,
    } else ...<String, Object?>{
      'currentVersion': currentVersion,
      'currentDigest': currentDigest.value,
      if (previousVersion != null) 'previousVersion': previousVersion,
      if (previousDigest != null) 'previousDigest': previousDigest!.value,
    },
  };

  factory _InstallState.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Install state must be an object');
    }
    final schema = value['schemaVersion'];
    if (schema == 0) {
      _onlyKeys(value, const <String>{
        'schemaVersion',
        'distributionId',
        'version',
        'digest',
      });
      return _InstallState(
        schemaVersion: 0,
        distributionId: _stateString(value, 'distributionId'),
        currentVersion: _stateString(value, 'version'),
        currentDigest: Digest(_stateString(value, 'digest')),
        previousVersion: null,
        previousDigest: null,
      );
    }
    if (schema != 1) {
      throw const FormatException('Unknown install state version');
    }
    _onlyKeys(value, const <String>{
      'schemaVersion',
      'distributionId',
      'currentVersion',
      'currentDigest',
      'previousVersion',
      'previousDigest',
    });
    final previousVersion = value['previousVersion'];
    final previousDigest = value['previousDigest'];
    if ((previousVersion == null) != (previousDigest == null) ||
        (previousVersion != null && previousVersion is! String) ||
        (previousDigest != null && previousDigest is! String)) {
      throw const FormatException('Previous install state is malformed');
    }
    return _InstallState(
      distributionId: _stateString(value, 'distributionId'),
      currentVersion: _stateString(value, 'currentVersion'),
      currentDigest: Digest(_stateString(value, 'currentDigest')),
      previousVersion: previousVersion as String?,
      previousDigest: previousDigest == null
          ? null
          : Digest(previousDigest as String),
    );
  }
}

String _stateString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

void _onlyKeys(Map<String, Object?> json, Set<String> allowed) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Install state has unknown fields');
  }
}

void _stateVersion(String value) {
  if (!RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
  ).hasMatch(value)) {
    throw FormatException('Invalid installed release version: $value');
  }
}
