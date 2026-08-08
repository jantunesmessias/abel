import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory bundle;
  const repository = LocalDistributionBundleRepository();

  setUp(() {
    bundle = Directory.systemTemp.createTempSync('devex-distribution-');
    Directory(p.join(bundle.path, 'bin')).createSync();
    Directory(p.join(bundle.path, 'studio')).createSync();
    for (final path in <String>[
      'bin/devex',
      'bin/devex_host',
      'bin/backend_gateway',
    ]) {
      final file = File(p.join(bundle.path, path))..writeAsStringSync(path);
      final chmod = Process.runSync('chmod', <String>['755', file.path]);
      if (chmod.exitCode != 0) throw StateError('chmod failed');
    }
    File(
      p.join(bundle.path, 'studio', 'index.html'),
    ).writeAsStringSync('<!doctype html>');
  });

  tearDown(() => bundle.deleteSync(recursive: true));

  test('creates and verifies a closed byte inventory', () async {
    final manifest = await repository.createManifest(
      directory: bundle.path,
      distribution: _descriptor(),
      releaseVersion: '0.1.0-preview.1',
      coreVersion: '0.1.0-dev',
      platform: 'linux-x64',
    );
    repository.writeDescriptor(bundle.path, manifest);

    final verified = await repository.verify(bundle.path);

    expect(verified.digest, manifest.digest);
    expect(verified.files, hasLength(4));
  });

  test('rejects tampering, extras, and links', () async {
    final manifest = await repository.createManifest(
      directory: bundle.path,
      distribution: _descriptor(),
      releaseVersion: '0.1.0-preview.1',
      coreVersion: '0.1.0-dev',
      platform: 'linux-x64',
    );
    repository.writeDescriptor(bundle.path, manifest);
    File(p.join(bundle.path, 'studio', 'index.html')).writeAsStringSync('bad');
    await expectLater(repository.verify(bundle.path), throwsFormatException);

    File(
      p.join(bundle.path, 'studio', 'index.html'),
    ).writeAsStringSync('<!doctype html>');
    File(p.join(bundle.path, 'extra')).writeAsStringSync('extra');
    await expectLater(repository.verify(bundle.path), throwsFormatException);
    File(p.join(bundle.path, 'extra')).deleteSync();
    Link(p.join(bundle.path, 'linked')).createSync('/tmp');
    await expectLater(
      repository.verify(bundle.path),
      throwsA(isA<FileSystemException>()),
    );
  });
}

DistributionDescriptor _descriptor() => DistributionDescriptor(
  id: 'devex-kit',
  displayName: 'DevExKit',
  coreCompatibility: '^0.1.0',
  defaultLayout: ConsumerLayout.devexDefault,
  commandAliases: const <String>['devex', 'devex-kit'],
);
