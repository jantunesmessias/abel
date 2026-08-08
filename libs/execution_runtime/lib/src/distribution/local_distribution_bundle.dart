import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

final class LocalDistributionBundleRepository {
  const LocalDistributionBundleRepository();

  static const int maxDescriptorBytes = 1024 * 1024;
  static const int maxFiles = 10000;
  static const int maxFileBytes = 512 * 1024 * 1024;
  static const int maxTotalBytes = 2 * 1024 * 1024 * 1024;
  static const String descriptorName = 'distribution.json';

  Future<DistributionReleaseManifest> createManifest({
    required String directory,
    required DistributionDescriptor distribution,
    required String releaseVersion,
    required String coreVersion,
    required String platform,
    required ModuleCatalog moduleCatalog,
    required List<String> profileIds,
    required List<DistributionComponent> components,
    required Map<String, String> entrypoints,
    required Map<String, List<String>> fileModuleIds,
    String moduleCatalogPath = 'modules/module-catalog.json',
  }) async {
    final root = _safeRoot(directory);
    final descriptor = File(p.join(root.path, descriptorName));
    if (descriptor.existsSync() || Link(descriptor.path).existsSync()) {
      throw FileSystemException('Distribution descriptor already exists');
    }
    final availableProfiles = moduleCatalog.profiles
        .map((item) => item.id)
        .toSet();
    if (profileIds.isEmpty || !availableProfiles.containsAll(profileIds)) {
      throw ArgumentError('Distribution profiles are not packaged in catalog');
    }
    final rawFiles = await _scan(root);
    final files = <DistributionFile>[
      for (final file in rawFiles)
        DistributionFile(
          path: file.path,
          digest: file.digest,
          size: file.size,
          executable: file.executable,
          role: file.role,
          moduleIds: fileModuleIds[file.path] ?? const <String>[],
        ),
    ];
    final catalogFiles = files.where((file) => file.path == moduleCatalogPath);
    if (catalogFiles.length != 1) {
      throw ArgumentError('Canonical module catalog file is missing');
    }
    final catalogBytes = File(
      p.join(root.path, moduleCatalogPath),
    ).readAsBytesSync();
    final packagedCatalog = ModuleCatalog.fromJson(
      jsonDecode(utf8.decode(catalogBytes)),
    );
    final canonicalCatalog = utf8.encode(
      const JcsCanonicalizer().canonicalize(packagedCatalog.toJson()),
    );
    if (packagedCatalog.digest != moduleCatalog.digest ||
        !_sameBytes(catalogBytes, canonicalCatalog)) {
      throw ArgumentError(
        'Packaged module catalog is not canonical or differs',
      );
    }
    final catalogReference = DistributionDocumentReference(
      path: moduleCatalogPath,
      digest: moduleCatalog.digest,
    );
    final releaseDescriptor = DistributionReleaseDescriptor(
      id: distribution.id,
      displayName: distribution.displayName,
      coreCompatibility: distribution.coreCompatibility,
      defaultLayout: distribution.defaultLayout,
      commandAliases: distribution.commandAliases,
      moduleCatalog: catalogReference,
      defaultProfileId: profileIds.contains(moduleCatalog.defaultProfileId)
          ? moduleCatalog.defaultProfileId
          : profileIds.first,
    );
    return DistributionReleaseManifest(
      distribution: releaseDescriptor,
      releaseVersion: releaseVersion,
      coreVersion: coreVersion,
      platform: platform,
      moduleCatalog: catalogReference,
      modules: moduleCatalog.modules
          .map((module) => module.id.value)
          .toList(growable: false),
      profiles: profileIds,
      components: components,
      entrypoints: entrypoints,
      commandAliases: <String, String>{
        for (final alias in distribution.commandAliases)
          alias: entrypoints['cli']!,
      },
      files: files,
    );
  }

  void writeDescriptor(String directory, DistributionReleaseManifest manifest) {
    final root = _safeRoot(directory);
    final descriptor = File(p.join(root.path, descriptorName));
    if (descriptor.existsSync() || Link(descriptor.path).existsSync()) {
      throw FileSystemException(
        'Distribution descriptor already exists',
        descriptor.path,
      );
    }
    final bytes = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(manifest.toJson())}\n',
    );
    final temporary = File('${descriptor.path}.new-$pid');
    if (temporary.existsSync() || Link(temporary.path).existsSync()) {
      throw FileSystemException('Descriptor staging file exists');
    }
    try {
      temporary.writeAsBytesSync(bytes, flush: true);
      temporary.renameSync(descriptor.path);
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
    }
  }

  Future<DistributionReleaseManifest> verify(String directory) async {
    final root = _safeRoot(directory);
    final descriptor = File(p.join(root.path, descriptorName));
    if (Link(descriptor.path).existsSync() || !descriptor.existsSync()) {
      throw FileSystemException(
        'Distribution descriptor is missing or linked',
        descriptor.path,
      );
    }
    final descriptorSize = descriptor.lengthSync();
    if (descriptorSize <= 0 || descriptorSize > maxDescriptorBytes) {
      throw const FormatException('Distribution descriptor size is invalid');
    }
    final bytes = descriptor.readAsBytesSync();
    final manifest = const DistributionReleaseCodec().fromJson(
      jsonDecode(utf8.decode(bytes)),
    );
    final canonical = utf8.encode(
      '${const JcsCanonicalizer().canonicalize(manifest.toJson())}\n',
    );
    if (!_sameBytes(bytes, canonical)) {
      throw const FormatException('Distribution descriptor is not canonical');
    }
    final observed = await _scan(root);
    if (observed.length != manifest.files.length) {
      throw const FormatException('Distribution file inventory differs');
    }
    for (var index = 0; index < observed.length; index += 1) {
      final actual = observed[index];
      final expected = manifest.files[index];
      if (actual.path != expected.path ||
          actual.digest != expected.digest ||
          actual.size != expected.size ||
          actual.executable != expected.executable ||
          actual.role != expected.role) {
        throw FormatException('Distribution file mismatch: ${expected.path}');
      }
    }
    return manifest;
  }

  Directory _safeRoot(String value) {
    final source = Directory(value).absolute;
    if (Link(source.path).existsSync() || !source.existsSync()) {
      throw FileSystemException(
        'Distribution directory is missing or linked',
        source.path,
      );
    }
    return Directory(source.resolveSymbolicLinksSync());
  }

  Future<List<DistributionFile>> _scan(Directory root) async {
    final entities = root.listSync(recursive: true, followLinks: false);
    if (entities.any((entity) => entity is Link)) {
      throw const FileSystemException('Distribution contains a symlink');
    }
    final files = entities.whereType<File>().where((file) {
      return p.relative(file.path, from: root.path) != descriptorName;
    }).toList();
    if (files.isEmpty || files.length > maxFiles) {
      throw const FormatException('Distribution file count is invalid');
    }
    final output = <DistributionFile>[];
    var totalBytes = 0;
    for (final file in files) {
      final relative = p
          .relative(file.path, from: root.path)
          .replaceAll(p.separator, '/');
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.file ||
          stat.size < 0 ||
          stat.size > maxFileBytes) {
        throw FormatException('Distribution file size is invalid: $relative');
      }
      totalBytes += stat.size;
      if (totalBytes > maxTotalBytes) {
        throw const FormatException('Distribution exceeds 2 GiB');
      }
      output.add(
        DistributionFile(
          path: relative,
          digest: await _fileDigest(file),
          size: stat.size,
          executable: stat.mode & 0x49 != 0,
          role: switch (relative) {
            'bin/workspace' => 'cli',
            'bin/workspace_host' => 'host',
            'bin/gateway_sidecar' => 'gateway',
            _ when relative.startsWith('studio/') => 'studio-asset',
            _ => 'distribution-asset',
          },
        ),
      );
    }
    output.sort((left, right) => left.path.compareTo(right.path));
    return output;
  }

  Future<Digest> _fileDigest(File file) async {
    final value = await crypto.sha256.bind(file.openRead()).single;
    return Digest('sha256:$value');
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
