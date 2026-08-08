import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
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
    this.maxFiles = 20000,
  });

  final SafeAuthoringParser parser;
  final WorkspaceConfigurationLoader configurationLoader;
  final int maxFiles;

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
    for (final file in authoringFiles) {
      documents.add(
        parser.parse(file.readAsStringSync(), sourceName: file.path),
      );
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
}
