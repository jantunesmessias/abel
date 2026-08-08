import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:workspace_cli/workspace_cli.dart';

Future<void> main(List<String> arguments) async {
  final options = _options(arguments);
  if (Platform.operatingSystem != 'linux') {
    throw StateError('Standalone packaging currently supports Linux only');
  }
  final repository = _repositoryRoot();
  final output = Directory(
    p.isAbsolute(options.output)
        ? p.normalize(options.output)
        : p.normalize(p.join(repository, options.output)),
  );
  if (output.existsSync() || Link(output.path).existsSync()) {
    throw FileSystemException(
      'Distribution output already exists',
      output.path,
    );
  }
  output.parent.createSync(recursive: true);
  final staging = Directory('${output.path}.staging-$pid');
  if (staging.existsSync() || Link(staging.path).existsSync()) {
    throw FileSystemException('Distribution staging path exists', staging.path);
  }
  staging.createSync();
  try {
    const builtins = BuiltinModuleCatalog();
    final completeCatalog = builtins.create(platform: 'linux-x64');
    final packagedCatalog = _catalogForProfile(
      completeCatalog,
      options.profile,
      builtins.configurationSchemas,
    );
    final packagedModuleIds = packagedCatalog.modules
        .map((module) => module.id.value)
        .toSet();
    List<String> modulesFor(ModuleSurface surface) => packagedCatalog.modules
        .where((module) => module.surfaces.contains(surface))
        .map((module) => module.id.value)
        .toList(growable: false);
    final cliModules = modulesFor(ModuleSurface.cli);
    final hostModules = modulesFor(ModuleSurface.host);
    final gatewayModules = modulesFor(ModuleSurface.gateway);
    final studioModules = packagedModuleIds.contains('studio.shell')
        ? modulesFor(ModuleSurface.studio)
        : const <String>[];
    final bin = Directory(p.join(staging.path, 'bin'))..createSync();
    await _run(Platform.resolvedExecutable, <String>[
      'compile',
      'exe',
      'apps/workspace_cli/bin/workspace.dart',
      '-o',
      p.join(bin.path, 'workspace'),
    ], repository);
    if (hostModules.isNotEmpty) {
      await _run(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        'apps/workspace_host/bin/workspace_host.dart',
        '-o',
        p.join(bin.path, 'workspace_host'),
      ], repository);
    }
    if (gatewayModules.isNotEmpty) {
      await _run(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        'apps/gateway_sidecar/bin/gateway_sidecar.dart',
        '-o',
        p.join(bin.path, 'gateway_sidecar'),
      ], repository);
    }
    if (studioModules.isNotEmpty) {
      await _buildDeterministicStudio(
        repository: repository,
        destination: Directory(p.join(staging.path, 'studio')),
      );
    }
    final modules = Directory(p.join(staging.path, 'modules'))..createSync();
    File(p.join(modules.path, 'module-catalog.json')).writeAsStringSync(
      const JcsCanonicalizer().canonicalize(packagedCatalog.toJson()),
      flush: true,
    );
    final descriptor = DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
      commandAliases: const <String>['workspace'],
    );
    const bundles = LocalDistributionBundleRepository();
    final entrypoints = <String, String>{
      'cli': 'bin/workspace',
      if (hostModules.isNotEmpty) 'host': 'bin/workspace_host',
      if (gatewayModules.isNotEmpty) 'gateway': 'bin/gateway_sidecar',
      if (studioModules.isNotEmpty) 'studio': 'studio/index.html',
    };
    final components = <DistributionComponent>[
      DistributionComponent(
        id: 'cli',
        kind: DistributionComponentKind.executable,
        path: 'bin/workspace',
        moduleIds: cliModules,
      ),
      if (hostModules.isNotEmpty)
        DistributionComponent(
          id: 'host',
          kind: DistributionComponentKind.executable,
          path: 'bin/workspace_host',
          moduleIds: hostModules,
        ),
      if (gatewayModules.isNotEmpty)
        DistributionComponent(
          id: 'gateway',
          kind: DistributionComponentKind.executable,
          path: 'bin/gateway_sidecar',
          moduleIds: gatewayModules,
        ),
      if (studioModules.isNotEmpty)
        DistributionComponent(
          id: 'studio',
          kind: DistributionComponentKind.webAssets,
          path: 'studio/index.html',
          moduleIds: studioModules,
        ),
    ];
    final fileModuleIds = <String, List<String>>{
      'bin/workspace': cliModules,
      if (hostModules.isNotEmpty) 'bin/workspace_host': hostModules,
      if (gatewayModules.isNotEmpty) 'bin/gateway_sidecar': gatewayModules,
      'modules/module-catalog.json': packagedModuleIds.toList()..sort(),
    };
    if (studioModules.isNotEmpty) {
      for (final file in Directory(
        p.join(staging.path, 'studio'),
      ).listSync(recursive: true).whereType<File>()) {
        fileModuleIds[p
                .relative(file.path, from: staging.path)
                .replaceAll('\\', '/')] =
            studioModules;
      }
    }
    final manifest = await bundles.createManifest(
      directory: staging.path,
      distribution: descriptor,
      releaseVersion: options.version,
      coreVersion: WorkspaceCli.version,
      platform: 'linux-x64',
      moduleCatalog: packagedCatalog,
      profileIds: packagedCatalog.profiles
          .map((profile) => profile.id)
          .toList(growable: false),
      components: components,
      entrypoints: entrypoints,
      fileModuleIds: fileModuleIds,
    );
    bundles.writeDescriptor(staging.path, manifest);
    await bundles.verify(staging.path);
    staging.renameSync(output.path);
    stdout.writeln(
      '${manifest.digest.value} ${manifest.files.length} ${output.path}',
    );
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}

ModuleCatalog _catalogForProfile(
  ModuleCatalog catalog,
  String profileId,
  Map<String, Object?> configurationSchemas,
) {
  final plan = const KitPlanResolver().resolve(
    catalog: catalog,
    profileId: profileId,
    configurationSchemas: configurationSchemas,
  );
  if (profileId == 'full-local') {
    return catalog;
  }
  final moduleIds = plan.enabledModules
      .map((module) => module.moduleId)
      .toSet();
  final profile = catalog.profiles.singleWhere((item) => item.id == profileId);
  return ModuleCatalog(
    distributionId: catalog.distributionId,
    coreVersion: catalog.coreVersion,
    platform: catalog.platform,
    modules: catalog.modules
        .where((module) => moduleIds.contains(module.id))
        .toList(growable: false),
    profiles: <KitProfile>[profile],
    defaultProfileId: profileId,
  );
}

Future<void> _buildDeterministicStudio({
  required String repository,
  required Directory destination,
}) async {
  final studioRoot = p.join(repository, 'apps', 'studio');
  final output = Directory(p.join(studioRoot, 'build', 'jaspr'));
  final lockFile = File(
    p.join(
      repository,
      '.dart_tool',
      'workspace',
      'locks',
      'distribution-web.lock',
    ),
  )..parent.createSync(recursive: true);
  final lock = lockFile.openSync(mode: FileMode.append);
  try {
    lock.lockSync(FileLock.exclusive);
    if (output.existsSync()) output.deleteSync(recursive: true);
    await _run(_findExecutable('jaspr'), const <String>['build'], studioRoot);
    _copyDistributionTree(output, destination);
  } finally {
    try {
      lock.unlockSync();
    } on FileSystemException {
      // The process is already terminating; closing still releases the lock.
    }
    lock.closeSync();
  }
}

void _copyDistributionTree(Directory source, Directory destination) {
  if (!source.existsSync() || destination.existsSync()) {
    throw FileSystemException(
      'Distribution copy boundary is invalid',
      source.path,
    );
  }
  destination.createSync(recursive: true);
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    if (entity is Link) {
      throw FileSystemException(
        'Studio build contains a symbolic link',
        entity.path,
      );
    }
    final relative = p.relative(entity.path, from: source.path);
    if (relative == '.last_build_id') continue;
    final target = p.join(destination.path, relative);
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    } else {
      throw FileSystemException(
        'Studio build contains an unsupported entity',
        entity.path,
      );
    }
  }
}

Future<void> _run(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw StateError('$executable failed with exit code $code');
  }
}

String _findExecutable(String name) {
  final path = Platform.environment['PATH'] ?? '';
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    final candidate = File('$directory${Platform.pathSeparator}$name');
    if (candidate.existsSync()) return candidate.path;
  }
  throw StateError('$name executable not found');
}

_Options _options(List<String> arguments) {
  String? output;
  String? version;
  var profile = 'full-local';
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (argument != '--output' &&
        argument != '--version' &&
        argument != '--profile') {
      throw FormatException('Unknown option: $argument');
    }
    if (index + 1 == arguments.length) {
      throw FormatException('$argument requires a value');
    }
    final value = arguments[++index];
    if (argument == '--output') {
      output = value;
    } else if (argument == '--version') {
      version = value;
    } else {
      profile = value;
    }
  }
  if (output == null || version == null) {
    throw const FormatException(
      'Usage: build_distribution --output <directory> --version <semver> '
      '[--profile <profile>]',
    );
  }
  return _Options(output: output, version: version, profile: profile);
}

final class _Options {
  const _Options({
    required this.output,
    required this.version,
    required this.profile,
  });

  final String output;
  final String version;
  final String profile;
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
