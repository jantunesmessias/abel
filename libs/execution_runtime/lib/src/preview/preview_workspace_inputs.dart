import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;

final class PreviewWorkspaceInputs {
  const PreviewWorkspaceInputs();

  Map<String, Digest> inspect(String applicationRoot) {
    final root = Directory(applicationRoot).resolveSymbolicLinksSync();
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!pubspec.existsSync() || Link(pubspec.path).existsSync()) {
      throw FileSystemException(
        'Flutter Application pubspec is unavailable',
        pubspec.path,
      );
    }
    final files = <String, String>{};
    final lib = Directory(p.join(root, 'lib'));
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw FileSystemException(
          'Links are forbidden in preview source',
          entity.path,
        );
      }
      if (entity is File && p.extension(entity.path) == '.dart') {
        files[p.relative(entity.path, from: root)] = Digest.bytes(
          entity.readAsBytesSync(),
        ).value;
      }
    }
    final result = <String, Digest>{
      'application.pubspec': Digest.bytes(pubspec.readAsBytesSync()),
      'application.lib': Digest.semantic(<String, Object?>{'files': files}),
    };
    final workspaceReference = File(
      p.join(root, '.dart_tool', 'pub', 'workspace_ref.json'),
    );
    File? lock;
    if (workspaceReference.existsSync() &&
        !Link(workspaceReference.path).existsSync()) {
      final reference = jsonDecode(workspaceReference.readAsStringSync());
      if (reference is Map<String, Object?> &&
          reference['workspaceRoot'] is String) {
        final candidate = Directory(
          p.normalize(
            p.join(
              workspaceReference.parent.path,
              reference['workspaceRoot']! as String,
            ),
          ),
        );
        if (candidate.existsSync()) {
          final resolved = candidate.resolveSymbolicLinksSync();
          if (resolved == root || p.isWithin(resolved, root)) {
            lock = File(p.join(resolved, 'pubspec.lock'));
          }
        }
      }
    }
    lock ??= File(p.join(root, 'pubspec.lock'));
    if (lock.existsSync() && !Link(lock.path).existsSync()) {
      result['pubspec.lock'] = Digest.bytes(lock.readAsBytesSync());
    }
    return result;
  }

  Future<Map<String, String>> toolchain(String workingDirectory) async {
    final result = await Process.run('flutter', const <String>[
      '--version',
      '--machine',
    ], workingDirectory: workingDirectory).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw const FormatException('Flutter toolchain inspection failed');
    }
    final value = jsonDecode(result.stdout as String);
    if (value is! Map<String, Object?>) {
      throw const FormatException('Flutter toolchain response is invalid');
    }
    String field(String name) {
      final item = value[name];
      if (item is! String || item.isEmpty) {
        throw FormatException('Flutter toolchain is missing $name');
      }
      return item;
    }

    return <String, String>{
      'flutter': field('frameworkVersion'),
      'dart': field('dartSdkVersion'),
      'engine': field('engineRevision'),
    };
  }
}
