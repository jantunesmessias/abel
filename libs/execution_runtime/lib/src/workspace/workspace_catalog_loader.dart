import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import 'workspace_configuration_loader.dart';

final class LoadedWorkspaceCatalog {
  LoadedWorkspaceCatalog({
    required this.configuration,
    required this.workspaceRoot,
    required this.configPath,
    required this.contentRoot,
    required this.layout,
    required List<AuthoringDocument> documents,
  }) : documents = List<AuthoringDocument>.unmodifiable(documents);

  final LoadedWorkspaceConfiguration configuration;
  final String workspaceRoot;
  final String configPath;
  final String contentRoot;
  final ConsumerLayout layout;
  final List<AuthoringDocument> documents;
}

final class WorkspaceCatalogLoader {
  const WorkspaceCatalogLoader({
    this.parser = const SafeAuthoringParser(),
    this.configurationLoader = const WorkspaceConfigurationLoader(),
    this.maxFiles = 50000,
    this.maxFileBytes = 1024 * 1024,
    this.maxTotalBytes = 128 * 1024 * 1024,
  });

  final SafeAuthoringParser parser;
  final WorkspaceConfigurationLoader configurationLoader;
  final int maxFiles;
  final int maxFileBytes;
  final int maxTotalBytes;

  LoadedWorkspaceCatalog load({
    required String startPath,
    String? explicitConfigPath,
    Map<String, String>? environment,
  }) => loadFromConfiguration(
    configurationLoader.load(
      startPath: startPath,
      explicitConfigPath: explicitConfigPath,
      environment: environment,
    ),
  );

  LoadedWorkspaceCatalog loadFromConfiguration(
    LoadedWorkspaceConfiguration configuration,
  ) {
    if (maxFiles <= 0 || maxFileBytes <= 0 || maxTotalBytes <= 0) {
      throw ArgumentError(
        'Workspace catalog budgets must all be positive integers',
      );
    }
    final documents = <AuthoringDocument>[
      AuthoringDocument(
        schemaVersion: 1,
        kind: AuthoringKind.workspace,
        id: configuration.workspaceId,
        spec: <String, Object?>{
          'displayName': configuration.workspaceDisplayName,
        },
        sourceName: '${configuration.configPath}#workspace',
      ),
    ];
    for (final application in configuration.applications.values) {
      documents.add(
        AuthoringDocument(
          schemaVersion: 1,
          kind: AuthoringKind.application,
          id: application.id,
          spec: <String, Object?>{
            'workspaceId': configuration.workspaceId,
            'displayName': application.displayName,
            'root': application.root,
            'target': application.target,
          },
          sourceName:
              '${configuration.configPath}#applications.${application.id}',
        ),
      );
    }
    final authoringFiles = _authoringFiles(
      Directory(configuration.contentRoot),
    );
    if (authoringFiles.length > maxFiles) {
      throw FileSystemException(
        'Content root exceeds $maxFiles authoring files',
        configuration.contentRoot,
      );
    }
    var totalBytes = 0;
    for (final file in authoringFiles) {
      final source = _readAuthoringFile(file);
      totalBytes += utf8.encode(source).length;
      if (totalBytes > maxTotalBytes) {
        throw FileSystemException(
          'Content root exceeds $maxTotalBytes authoring bytes',
          configuration.contentRoot,
        );
      }
      documents.add(parser.parse(source, sourceName: file.path));
    }

    return LoadedWorkspaceCatalog(
      configuration: configuration,
      workspaceRoot: configuration.workspaceRoot,
      configPath: configuration.configPath,
      contentRoot: configuration.contentRoot,
      layout: configuration.layout,
      documents: documents,
    );
  }

  List<File> _authoringFiles(Directory root) {
    final files = <File>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FileSystemException(
          'Links are forbidden in content root',
          entity.path,
        );
      }
      if (entity is File &&
          const <String>{
            '.yaml',
            '.yml',
            '.json',
          }.contains(p.extension(entity.path).toLowerCase())) {
        files.add(entity);
      }
    }
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  String _readAuthoringFile(File file) {
    final before = file.statSync();
    if (before.type != FileSystemEntityType.file ||
        before.size <= 0 ||
        before.size > maxFileBytes) {
      throw FileSystemException(
        'Authoring file is outside the $maxFileBytes byte budget',
        file.path,
      );
    }
    final reader = file.openSync();
    final bytes = <int>[];
    try {
      while (bytes.length <= maxFileBytes) {
        final remaining = maxFileBytes + 1 - bytes.length;
        final chunk = reader.readSync(
          remaining < 64 * 1024 ? remaining : 64 * 1024,
        );
        if (chunk.isEmpty) break;
        bytes.addAll(chunk);
      }
    } finally {
      reader.closeSync();
    }
    final after = file.statSync();
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        bytes.length != before.size ||
        bytes.length > maxFileBytes ||
        after.size != before.size ||
        after.modified != before.modified ||
        after.changed != before.changed) {
      throw FileSystemException(
        'Authoring file changed while it was read',
        file.path,
      );
    }
    return utf8.decode(bytes, allowMalformed: false);
  }
}
