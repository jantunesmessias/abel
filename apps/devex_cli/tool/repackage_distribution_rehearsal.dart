import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;

/// Re-labels already verified bytes solely for the update/rollback rehearsal.
/// Production release promotion must rebuild from its pinned source inputs.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    throw const FormatException(
      'Usage: repackage_distribution_rehearsal <source> <output> <version>',
    );
  }
  const bundles = LocalDistributionBundleRepository();
  final source = Directory(arguments[0]).absolute;
  final output = Directory(arguments[1]).absolute;
  final version = arguments[2];
  final original = await bundles.verify(source.path);
  if (output.existsSync() || Link(output.path).existsSync()) {
    throw FileSystemException('Rehearsal output exists', output.path);
  }
  final staging = Directory('${output.path}.staging-$pid')..createSync();
  try {
    for (final file in original.files) {
      final destination = File(p.join(staging.path, file.path));
      destination.parent.createSync(recursive: true);
      File(p.join(source.path, file.path)).copySync(destination.path);
      final chmod = Process.runSync('chmod', <String>[
        file.executable ? '755' : '644',
        destination.path,
      ]);
      if (chmod.exitCode != 0) throw StateError('chmod failed');
    }
    final DistributionRelease relabeled;
    if (original case final DistributionReleaseManifest v1) {
      relabeled = await bundles.createManifest(
        directory: staging.path,
        distribution: v1.distribution,
        releaseVersion: version,
        coreVersion: original.coreVersion,
        platform: original.platform,
      );
    } else if (original case final DistributionReleaseManifestV2 v2) {
      final catalog = ModuleCatalog.fromJson(
        jsonDecode(
          File(p.join(staging.path, v2.moduleCatalog.path)).readAsStringSync(),
        ),
      );
      relabeled = await bundles.createManifestV2(
        directory: staging.path,
        distribution: DistributionDescriptor(
          id: v2.distribution.id,
          displayName: v2.distribution.displayName,
          coreCompatibility: v2.distribution.coreCompatibility,
          defaultLayout: v2.distribution.defaultLayout,
          commandAliases: v2.distribution.commandAliases,
        ),
        releaseVersion: version,
        coreVersion: original.coreVersion,
        platform: original.platform,
        moduleCatalog: catalog,
        profileIds: v2.profiles,
        components: v2.components,
        entrypoints: v2.entrypoints,
        fileModuleIds: <String, List<String>>{
          for (final file in v2.files) file.path: file.moduleIds,
        },
        moduleCatalogPath: v2.moduleCatalog.path,
      );
    } else {
      throw StateError('Unsupported distribution release version');
    }
    bundles.writeDescriptor(staging.path, relabeled);
    await bundles.verify(staging.path);
    staging.renameSync(output.path);
    stdout.writeln(relabeled.digest.value);
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}
