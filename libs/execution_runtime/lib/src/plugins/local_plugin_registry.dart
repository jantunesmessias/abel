import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

final class DiscoveredPlugin {
  const DiscoveredPlugin({
    required this.manifest,
    required this.directory,
    required this.manifestDigest,
  });

  final PluginManifest manifest;
  final String directory;
  final Digest manifestDigest;
}

final class LocalPluginRegistry {
  const LocalPluginRegistry({
    this.maxPlugins = 128,
    this.maxManifestBytes = 1024 * 1024,
  });

  final int maxPlugins;
  final int maxManifestBytes;

  List<DiscoveredPlugin> discover(String rootPath) {
    final root = Directory(rootPath).absolute;
    if (Link(root.path).existsSync() || !root.existsSync()) {
      throw FileSystemException(
        'Plugin registry root is missing or linked',
        root.path,
      );
    }
    final canonicalRoot = Directory(root.resolveSymbolicLinksSync());
    final directories = canonicalRoot.listSync(followLinks: false);
    if (directories.any((entry) => entry is Link)) {
      throw const FileSystemException('Plugin registry contains a symlink');
    }
    final candidates = directories.whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (candidates.length > maxPlugins) {
      throw const FormatException('Plugin registry exceeds plugin-count limit');
    }
    final output = <DiscoveredPlugin>[];
    final ids = <String>{};
    for (final directory in candidates) {
      final manifestFile = File(p.join(directory.path, 'plugin.json'));
      if (Link(manifestFile.path).existsSync() || !manifestFile.existsSync()) {
        continue;
      }
      final length = manifestFile.lengthSync();
      if (length <= 0 || length > maxManifestBytes) {
        throw FormatException(
          'Plugin manifest size is invalid: ${manifestFile.path}',
        );
      }
      final bytes = manifestFile.readAsBytesSync();
      final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      final manifest = PluginManifest.fromJson(value);
      final canonical = utf8.encode(
        '${const JcsCanonicalizer().canonicalize(manifest.toJson())}\n',
      );
      if (!_registrySameBytes(bytes, canonical)) {
        throw FormatException(
          'Plugin manifest is not canonical JCS: ${manifestFile.path}',
        );
      }
      if (!ids.add(manifest.id)) {
        throw FormatException('Duplicate plugin ID: ${manifest.id}');
      }
      output.add(
        DiscoveredPlugin(
          manifest: manifest,
          directory: directory.resolveSymbolicLinksSync(),
          manifestDigest: Digest.bytes(bytes),
        ),
      );
    }
    output.sort((a, b) => a.manifest.id.compareTo(b.manifest.id));
    return List<DiscoveredPlugin>.unmodifiable(output);
  }
}

bool _registrySameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
