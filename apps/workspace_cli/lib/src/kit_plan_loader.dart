import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

final class LoadedCliKitPlan {
  const LoadedCliKitPlan({
    required this.catalog,
    required this.plan,
    required this.configuration,
  });

  final ModuleCatalog catalog;
  final ResolvedKitPlan plan;
  final LoadedWorkspaceConfiguration? configuration;
}

final class CliKitPlanLoader {
  const CliKitPlanLoader({this.builtins = const BuiltinModuleCatalog()});

  final BuiltinModuleCatalog builtins;

  LoadedCliKitPlan load({
    required String workspaceDirectory,
    String? explicitConfigPath,
    String? profileOverride,
    bool allowMissingWorkspace = false,
  }) {
    final catalog = builtins.create(platform: _platformId());
    LoadedWorkspaceConfiguration? configuration;
    try {
      configuration = const WorkspaceConfigurationLoader().load(
        startPath: workspaceDirectory,
        explicitConfigPath: explicitConfigPath,
        profileOverride: profileOverride,
      );
    } on FileSystemException {
      if (!allowMissingWorkspace || explicitConfigPath != null) rethrow;
    }
    final plan = configuration == null
        ? const KitPlanResolver().resolve(
            catalog: catalog,
            profileId: profileOverride,
            configurationSchemas: builtins.configurationSchemas,
          )
        : configuration.kitPlanRequest.resolve(
            catalog: catalog,
            configurationSchemas: builtins.configurationSchemas,
          );
    return LoadedCliKitPlan(
      catalog: catalog,
      plan: plan,
      configuration: configuration,
    );
  }

  String _platformId() => switch (Platform.operatingSystem) {
    'linux' => 'linux-x64',
    'macos' => 'macos-arm64',
    'windows' => 'windows-x64',
    final value => '$value-native',
  };
}
