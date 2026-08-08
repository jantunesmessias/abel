import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

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
    final catalog = ModuleCatalog.fromJson(
      jsonDecode(
        File(
          p.join(staging.path, original.moduleCatalog.path),
        ).readAsStringSync(),
      ),
    );
    final relabeled = await bundles.createManifest(
      directory: staging.path,
      distribution: DistributionDescriptor(
        id: original.distribution.id,
        displayName: original.distribution.displayName,
        coreCompatibility: original.distribution.coreCompatibility,
        defaultLayout: original.distribution.defaultLayout,
        commandAliases: original.distribution.commandAliases,
      ),
      releaseVersion: version,
      coreVersion: original.coreVersion,
      platform: original.platform,
      moduleCatalog: catalog,
      profileIds: original.profiles,
      components: original.components,
      entrypoints: original.entrypoints,
      fileModuleIds: <String, List<String>>{
        for (final file in original.files) file.path: file.moduleIds,
      },
      moduleCatalogPath: original.moduleCatalog.path,
    );
    bundles.writeDescriptor(staging.path, relabeled);
    await bundles.verify(staging.path);
    staging.renameSync(output.path);
    stdout.writeln(relabeled.digest.value);
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}
