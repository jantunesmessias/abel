import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../workspace/workspace_catalog_loader.dart';
import '../workspace/workspace_configuration_loader.dart';
import 'local_distribution_bundle.dart';

final class LocalConsumerDistributionResult {
  const LocalConsumerDistributionResult({
    required this.release,
    required this.inventory,
    required this.workspacePath,
    required this.resolvedPlanPath,
  });

  final DistributionReleaseManifest release;
  final ConsumerDistributionInventory inventory;
  final String workspacePath;
  final String resolvedPlanPath;

  Map<String, Object?> toJson() => <String, Object?>{
    'distributionId': release.distributionId,
    'releaseVersion': release.releaseVersion,
    'releaseDigest': release.digest.value,
    'inventoryDigest': inventory.digest.value,
    'profileId': inventory.profileId,
    'studioAssets': inventory.studioAssets.name,
    'workspacePath': workspacePath,
    'resolvedPlanPath': resolvedPlanPath,
  };
}

final class LocalConsumerDistributionComposer {
  const LocalConsumerDistributionComposer({
    this.bundleRepository = const LocalDistributionBundleRepository(),
    this.configurationLoader = const WorkspaceConfigurationLoader(),
    this.catalogLoader = const WorkspaceCatalogLoader(),
    this.maxConsumerFiles = 20000,
    this.maxConsumerFileBytes = 16 * 1024 * 1024,
    this.maxConsumerBytes = 64 * 1024 * 1024,
  });

  static const String consumerRoot = 'consumer';
  static const String workspaceRoot = '$consumerRoot/workspace';
  static const String specificationPath =
      '$consumerRoot/distribution-spec.json';
  static const String inventoryPath = '$consumerRoot/inventory.json';
  static const String compiledCatalogPath = '$consumerRoot/catalog.json';
  static const String resolvedPlanPath = '$consumerRoot/resolved-kit-plan.json';

  final LocalDistributionBundleRepository bundleRepository;
  final WorkspaceConfigurationLoader configurationLoader;
  final WorkspaceCatalogLoader catalogLoader;
  final int maxConsumerFiles;
  final int maxConsumerFileBytes;
  final int maxConsumerBytes;

  Future<LocalConsumerDistributionResult> compose({
    required String baseBundleDirectory,
    required String consumerWorkspaceDirectory,
    required ConsumerDistributionSpec specification,
    required String outputDirectory,
    required Map<String, Object?> configurationSchemas,
  }) async {
    final base = await bundleRepository.verify(baseBundleDirectory);
    if (DistributionReleaseManifest.schemaVersion !=
        specification.compatibility.distributionReleaseSchemaVersion) {
      throw const FormatException(
        'Base release schema is outside consumer compatibility',
      );
    }
    if (!base.entrypoints.containsKey('cli') ||
        !base.entrypoints.containsKey('host')) {
      throw const FormatException(
        'Consumer distributions require CLI and Host entrypoints',
      );
    }
    if (base.files.any((file) => file.path.startsWith('$consumerRoot/'))) {
      throw const FormatException('Base release already owns consumer paths');
    }

    final baseRoot = _existingRoot(baseBundleDirectory, 'base bundle');
    final sourceWorkspace = _existingRoot(
      consumerWorkspaceDirectory,
      'consumer workspace',
    );
    final output = Directory(outputDirectory).absolute;
    _validateOutputBoundary(output, baseRoot, sourceWorkspace);

    final baseCatalog = _loadModuleCatalog(baseRoot, base);
    if (!_allowsCaret(
      specification.compatibility.coreCompatibility,
      baseCatalog.coreVersion,
    )) {
      throw const FormatException(
        'Consumer core compatibility excludes the packaged module catalog',
      );
    }
    final selectedProfiles = baseCatalog.profiles.where(
      (profile) => profile.id == specification.profileId,
    );
    if (selectedProfiles.length != 1) {
      throw const FormatException('Consumer profile is not packaged exactly');
    }
    final consumerCatalog = ModuleCatalog(
      distributionId: specification.distribution.id,
      coreVersion: baseCatalog.coreVersion,
      platform: baseCatalog.platform,
      modules: baseCatalog.modules,
      profiles: <KitProfile>[selectedProfiles.single],
      defaultProfileId: specification.profileId,
    );

    final configuration = configurationLoader.load(
      startPath: sourceWorkspace.path,
      explicitConfigPath: p.join(
        sourceWorkspace.path,
        specification.distribution.defaultLayout.configFile,
      ),
    );
    _validateConfiguration(configuration, specification);
    final loadedCatalog = catalogLoader.loadFromConfiguration(configuration);
    final authoredSchemaVersions = loadedCatalog.documents
        .map((document) => document.schemaVersion)
        .toSet();
    if (!specification.compatibility.authoringDocumentSchemaVersions
        .toSet()
        .containsAll(authoredSchemaVersions)) {
      throw const FormatException(
        'Consumer authoring document schema is outside compatibility',
      );
    }
    final resolvedPlan = configuration.kitPlanRequest.resolve(
      catalog: consumerCatalog,
      configurationSchemas: configurationSchemas,
    );
    if (resolvedPlan.profileId != specification.profileId) {
      throw const FormatException(
        'Consumer configuration resolved a different profile',
      );
    }
    final enabledIds = resolvedPlan.enabledModules
        .map((module) => module.moduleId)
        .toSet();
    final enabledDescriptors = consumerCatalog.modules
        .where((module) => enabledIds.contains(module.id))
        .toList(growable: false);
    final studioEnabled = enabledIds.contains(ModuleId('studio.shell'));
    if ((specification.studioAssets == ConsumerStudioAssets.included) !=
        studioEnabled) {
      throw const FormatException(
        'Studio asset mode differs from the resolved consumer plan',
      );
    }
    if (studioEnabled && !base.entrypoints.containsKey('studio')) {
      throw const FormatException(
        'The base release does not contain required Studio assets',
      );
    }

    final staging = Directory('${output.path}.staging-$pid');
    if (output.existsSync() ||
        Link(output.path).existsSync() ||
        staging.existsSync() ||
        Link(staging.path).existsSync()) {
      throw FileSystemException('Consumer distribution output exists');
    }
    output.parent.createSync(recursive: true);
    staging.createSync();
    try {
      final fileModuleIds = <String, List<String>>{};
      for (final file in base.files) {
        if (file.path == base.moduleCatalog.path ||
            (specification.studioAssets == ConsumerStudioAssets.absent &&
                file.path.startsWith('studio/'))) {
          continue;
        }
        await _copyFile(
          source: File(p.join(baseRoot.path, file.path)),
          destination: File(p.join(staging.path, file.path)),
          expected: file,
        );
        fileModuleIds[file.path] = file.moduleIds;
      }

      final moduleCatalogFile = File(
        p.join(staging.path, base.moduleCatalog.path),
      );
      _writeCanonical(
        moduleCatalogFile,
        consumerCatalog.toJson(),
        newline: false,
      );
      fileModuleIds[base.moduleCatalog.path] = <String>[
        for (final module in consumerCatalog.modules) module.id.value,
      ];

      final consumerFiles = <ConsumerDistributionFileInventory>[];
      void writeConsumerJson(
        String relativePath,
        Map<String, Object?> document,
        String role, {
        bool newline = true,
      }) {
        final bytes = utf8.encode(
          '${const JcsCanonicalizer().canonicalize(document)}${newline ? '\n' : ''}',
        );
        final file = File(p.join(staging.path, relativePath));
        _writeBytes(file, bytes);
        consumerFiles.add(
          ConsumerDistributionFileInventory(
            path: relativePath,
            digest: Digest.bytes(bytes),
            size: bytes.length,
            role: role,
          ),
        );
        fileModuleIds[relativePath] = const <String>['catalog'];
      }

      writeConsumerJson(
        specificationPath,
        specification.toJson(),
        'specification',
      );
      final bundledConfigPath = p.posix.join(
        workspaceRoot,
        specification.distribution.defaultLayout.configFile,
      );
      writeConsumerJson(
        bundledConfigPath,
        configuration.document,
        'configuration',
      );
      final compiledCatalog = const CatalogCompiler().compile(
        loadedCatalog.documents,
        distribution: specification.distribution,
        layout: specification.distribution.defaultLayout,
      );
      writeConsumerJson(
        compiledCatalogPath,
        compiledCatalog.toJson(),
        'catalog',
      );
      writeConsumerJson(
        resolvedPlanPath,
        resolvedPlan.toJson(),
        'resolved-plan',
        newline: false,
      );

      for (final content in _consumerContentFiles(configuration)) {
        final relative = p
            .relative(content.path, from: configuration.contentRoot)
            .replaceAll(p.separator, '/');
        final bundledPath = p.posix.join(
          workspaceRoot,
          specification.distribution.defaultLayout.contentRoot,
          relative,
        );
        final bytes = content.readAsBytesSync();
        _writeBytes(File(p.join(staging.path, bundledPath)), bytes);
        consumerFiles.add(
          ConsumerDistributionFileInventory(
            path: bundledPath,
            digest: Digest.bytes(bytes),
            size: bytes.length,
            role: 'content',
          ),
        );
        fileModuleIds[bundledPath] = const <String>['catalog'];
      }

      final packagedConfiguration = configurationLoader.load(
        startPath: p.join(staging.path, workspaceRoot),
        explicitConfigPath: p.join(staging.path, bundledConfigPath),
      );
      final packagedDocuments = catalogLoader.loadFromConfiguration(
        packagedConfiguration,
      );
      final packagedCatalog = const CatalogCompiler().compile(
        packagedDocuments.documents,
        distribution: specification.distribution,
        layout: specification.distribution.defaultLayout,
      );
      if (packagedConfiguration.documentDigest !=
              configuration.documentDigest ||
          packagedCatalog.digest != compiledCatalog.digest) {
        throw const FormatException(
          'Packaged consumer workspace differs from the compiled catalog',
        );
      }

      final inventory = ConsumerDistributionInventory(
        distributionId: specification.distribution.id,
        releaseVersion: specification.releaseVersion,
        coreVersion: consumerCatalog.coreVersion,
        profileId: specification.profileId,
        studioAssets: specification.studioAssets,
        compatibility: specification.compatibility,
        specDigest: specification.digest,
        baseReleaseDigest: base.digest,
        moduleCatalogDigest: consumerCatalog.digest,
        resolvedPlanDigest: resolvedPlan.digest,
        consumerConfigurationDigest: configuration.documentDigest,
        catalogDigest: compiledCatalog.digest,
        modules: <ConsumerDistributionModuleInventory>[
          for (final descriptor in enabledDescriptors)
            ConsumerDistributionModuleInventory(
              id: descriptor.id.value,
              version: descriptor.version,
              coreCompatibility: descriptor.coreCompatibility,
              descriptorDigest: descriptor.digest,
              surfaces: descriptor.surfaces
                  .map((surface) => surface.name)
                  .toList(growable: false),
            ),
        ],
        files: consumerFiles,
      );
      _writeCanonical(
        File(p.join(staging.path, inventoryPath)),
        inventory.toJson(),
      );
      fileModuleIds[inventoryPath] = const <String>['catalog'];

      final entrypoints = <String, String>{...base.entrypoints};
      final components = <DistributionComponent>[...base.components];
      if (specification.studioAssets == ConsumerStudioAssets.absent) {
        entrypoints.remove('studio');
        components.removeWhere(
          (component) =>
              component.kind == DistributionComponentKind.webAssets ||
              component.path.startsWith('studio/'),
        );
      }
      final manifest = await bundleRepository.createManifest(
        directory: staging.path,
        distribution: specification.distribution,
        releaseVersion: specification.releaseVersion,
        coreVersion: base.coreVersion,
        platform: base.platform,
        moduleCatalog: consumerCatalog,
        profileIds: <String>[specification.profileId],
        components: components,
        entrypoints: entrypoints,
        fileModuleIds: fileModuleIds,
        moduleCatalogPath: base.moduleCatalog.path,
      );
      bundleRepository.writeDescriptor(staging.path, manifest);
      final verified = await bundleRepository.verify(staging.path);
      if (verified.digest != manifest.digest) {
        throw StateError('Composed consumer distribution did not verify');
      }
      staging.renameSync(output.path);
      return LocalConsumerDistributionResult(
        release: manifest,
        inventory: inventory,
        workspacePath: workspaceRoot,
        resolvedPlanPath: resolvedPlanPath,
      );
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  ModuleCatalog _loadModuleCatalog(
    Directory baseRoot,
    DistributionReleaseManifest base,
  ) {
    final file = File(p.join(baseRoot.path, base.moduleCatalog.path));
    final bytes = file.readAsBytesSync();
    final catalog = ModuleCatalog.fromJson(jsonDecode(utf8.decode(bytes)));
    if (catalog.digest != base.moduleCatalog.digest) {
      throw const FormatException('Base module catalog digest mismatch');
    }
    return catalog;
  }

  void _validateConfiguration(
    LoadedWorkspaceConfiguration configuration,
    ConsumerDistributionSpec specification,
  ) {
    if (configuration.schemaVersion !=
        specification.compatibility.consumerConfigurationSchemaVersion) {
      throw const FormatException(
        'Consumer configuration schema is outside compatibility',
      );
    }
    if (configuration.localDocument.isNotEmpty) {
      throw const FormatException(
        'Local consumer configuration cannot enter a distribution',
      );
    }
    final distribution = configuration.document['distribution'];
    if (distribution is! Map<String, Object?> ||
        distribution['id'] != specification.distribution.id ||
        distribution.keys.any((key) => key != 'id')) {
      throw const FormatException(
        'Consumer configuration must bind only the exact distribution ID',
      );
    }
    final expected = specification.distribution.defaultLayout;
    if (configuration.layout.configFile != expected.configFile ||
        configuration.layout.contentRoot != expected.contentRoot ||
        configuration.layout.localConfigFile != expected.localConfigFile ||
        configuration.layout.toolingEntrypoint != expected.toolingEntrypoint) {
      throw const FormatException(
        'Consumer configuration layout differs from distribution layout',
      );
    }
  }

  List<File> _consumerContentFiles(LoadedWorkspaceConfiguration configuration) {
    final root = Directory(configuration.contentRoot);
    final output = <File>[];
    var totalBytes = 0;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FileSystemException(
          'Consumer content contains a symbolic link',
          entity.path,
        );
      }
      if (entity is Directory) continue;
      if (entity is! File) {
        throw FileSystemException(
          'Consumer content contains an unsupported entity',
          entity.path,
        );
      }
      final stat = entity.statSync();
      if (stat.type != FileSystemEntityType.file ||
          stat.size < 0 ||
          stat.size > maxConsumerFileBytes) {
        throw FormatException('Consumer content file is out of budget');
      }
      totalBytes += stat.size;
      if (totalBytes > maxConsumerBytes) {
        throw const FormatException('Consumer content exceeds byte budget');
      }
      output.add(entity);
      if (output.length > maxConsumerFiles) {
        throw const FormatException('Consumer content exceeds file budget');
      }
    }
    output.sort((left, right) => left.path.compareTo(right.path));
    return output;
  }

  Directory _existingRoot(String value, String label) {
    final directory = Directory(value).absolute;
    if (!directory.existsSync() || Link(directory.path).existsSync()) {
      throw FileSystemException('$label is missing or linked', directory.path);
    }
    return Directory(directory.resolveSymbolicLinksSync());
  }

  void _validateOutputBoundary(
    Directory output,
    Directory baseRoot,
    Directory sourceWorkspace,
  ) {
    final parent = output.parent;
    if (!parent.existsSync() || Link(parent.path).existsSync()) {
      throw FileSystemException(
        'Consumer distribution parent is missing or linked',
        parent.path,
      );
    }
    final resolvedParent = parent.resolveSymbolicLinksSync();
    final resolvedOutput = p.normalize(
      p.join(resolvedParent, p.basename(output.path)),
    );
    for (final source in <Directory>[baseRoot, sourceWorkspace]) {
      if (resolvedOutput == source.path ||
          p.isWithin(source.path, resolvedOutput) ||
          p.isWithin(resolvedOutput, source.path)) {
        throw ArgumentError('Consumer distribution output overlaps an input');
      }
    }
  }

  Future<void> _copyFile({
    required File source,
    required File destination,
    required DistributionFile expected,
  }) async {
    if (!source.existsSync() || Link(source.path).existsSync()) {
      throw FileSystemException(
        'Verified base file is unavailable',
        source.path,
      );
    }
    destination.parent.createSync(recursive: true);
    source.copySync(destination.path);
    final chmod = Process.runSync('chmod', <String>[
      expected.executable ? '755' : '644',
      destination.path,
    ]);
    if (chmod.exitCode != 0) {
      throw StateError('chmod failed while composing consumer distribution');
    }
    final stat = destination.statSync();
    final observedDigest = await _fileDigest(destination);
    if (stat.type != FileSystemEntityType.file ||
        stat.size != expected.size ||
        observedDigest != expected.digest ||
        (stat.mode & 0x49 != 0) != expected.executable) {
      throw FormatException('Verified base file changed: ${expected.path}');
    }
  }

  void _writeCanonical(
    File file,
    Map<String, Object?> document, {
    bool newline = true,
  }) {
    _writeBytes(
      file,
      utf8.encode(
        '${const JcsCanonicalizer().canonicalize(document)}${newline ? '\n' : ''}',
      ),
    );
  }

  void _writeBytes(File file, List<int> bytes) {
    if (file.existsSync() || Link(file.path).existsSync()) {
      throw FileSystemException('Consumer distribution path exists', file.path);
    }
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
  }

  Future<Digest> _fileDigest(File file) async {
    final value = await crypto.sha256.bind(file.openRead()).single;
    return Digest('sha256:$value');
  }
}

bool _allowsCaret(String constraint, String version) {
  final lower = _Version.parse(constraint.substring(1));
  final actual = _Version.parse(version);
  final upper = switch ((lower.major, lower.minor)) {
    (> 0, _) => _Version(lower.major + 1, 0, 0),
    (0, > 0) => _Version(0, lower.minor + 1, 0),
    _ => _Version(0, 0, lower.patch + 1),
  };
  return actual.compareTo(lower) >= 0 && actual.compareTo(upper) < 0;
}

final class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch, [this.pre = '']);

  factory _Version.parse(String value) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(value);
    if (match == null) throw FormatException('Invalid version: $value');
    return _Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      match.group(4) ?? '',
    );
  }

  final int major;
  final int minor;
  final int patch;
  final String pre;

  @override
  int compareTo(_Version other) {
    for (final pair in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = pair.$1.compareTo(pair.$2);
      if (result != 0) return result;
    }
    if (pre.isEmpty || other.pre.isEmpty) {
      if (pre.isEmpty && other.pre.isEmpty) return 0;
      return pre.isEmpty ? 1 : -1;
    }
    return pre.compareTo(other.pre);
  }
}
