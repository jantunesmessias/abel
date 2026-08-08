import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';

import 'workspace_configuration_loader.dart';

final class ConsumerConfigurationMigrationReport {
  ConsumerConfigurationMigrationReport({
    required this.configPath,
    required this.fromVersion,
    required this.toVersion,
    required this.applied,
    required this.changed,
    required this.beforeDigest,
    required this.afterDigest,
    required Map<String, Object?> document,
    this.backupPath,
  }) : document = Map<String, Object?>.unmodifiable(document);

  final String configPath;
  final int fromVersion;
  final int toVersion;
  final bool applied;
  final bool changed;
  final Digest beforeDigest;
  final Digest afterDigest;
  final Map<String, Object?> document;
  final String? backupPath;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'ConsumerConfigurationMigrationReport',
    'configPath': configPath,
    'fromVersion': fromVersion,
    'toVersion': toVersion,
    'applied': applied,
    'changed': changed,
    'beforeDigest': beforeDigest.value,
    'afterDigest': afterDigest.value,
    if (backupPath != null) 'backupPath': backupPath,
    'document': document,
  };
}

/// Converts consumer configuration v1 to its explicit v2 compatibility
/// profile. Preview mode is pure; apply mode keeps the original beside the
/// config before atomically publishing the migrated document.
final class ConsumerConfigurationMigrator {
  const ConsumerConfigurationMigrator();

  ConsumerConfigurationMigrationReport migrate({
    required LoadedWorkspaceConfiguration configuration,
    required bool apply,
  }) {
    final before = configuration.document;
    final fromVersion = configuration.schemaVersion;
    final migrated = fromVersion == 2 ? before : _v2Document(before);
    final beforeDigest = Digest.semantic(before);
    final afterDigest = Digest.semantic(migrated);
    final changed = beforeDigest != afterDigest;
    String? backupPath;
    if (apply && changed) {
      backupPath = _apply(
        configPath: configuration.configPath,
        migrated: migrated,
      );
    }
    return ConsumerConfigurationMigrationReport(
      configPath: configuration.configPath,
      fromVersion: fromVersion,
      toVersion: 2,
      applied: apply && changed,
      changed: changed,
      beforeDigest: beforeDigest,
      afterDigest: afterDigest,
      document: migrated,
      backupPath: backupPath,
    );
  }

  Map<String, Object?> _v2Document(
    Map<String, Object?> source,
  ) => <String, Object?>{
    'schemaVersion': 2,
    if (source['distribution'] != null) 'distribution': source['distribution'],
    'content': source['content'],
    'workspace': source['workspace'],
    'applications': source['applications'],
    'kit': <String, Object?>{
      'profile': const LegacyV1ConfigurationTranslator().profileId,
      'modules': <String, Object?>{},
      'startupPolicy': 'fail-required-v1',
    },
  };

  String _apply({
    required String configPath,
    required Map<String, Object?> migrated,
  }) {
    final config = File(configPath);
    final backup = File('$configPath.v1.bak');
    if (backup.existsSync() || Link(backup.path).existsSync()) {
      throw FileSystemException(
        'Configuration migration backup already exists',
        backup.path,
      );
    }
    final staging = File(
      '$configPath.devex-migrate-$pid-${DateTime.now().microsecondsSinceEpoch}',
    );
    final rendered =
        '${const JsonEncoder.withIndent('  ').convert(migrated)}\n';
    try {
      staging.writeAsStringSync(rendered, flush: true);
      config.renameSync(backup.path);
      try {
        staging.renameSync(config.path);
      } on Object {
        if (!config.existsSync() && backup.existsSync()) {
          backup.renameSync(config.path);
        }
        rethrow;
      }
    } finally {
      if (staging.existsSync()) staging.deleteSync();
    }
    return backup.path;
  }
}
