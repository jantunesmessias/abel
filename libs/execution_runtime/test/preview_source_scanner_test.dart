import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/temporary_preview_consumer.dart';

void main() {
  late TemporaryPreviewConsumer consumer;
  late PreviewSourceScanResult fixtureScan;
  late PreviewManifest fixtureManifest;

  setUpAll(() async {
    consumer = TemporaryPreviewConsumer.create();
    fixtureScan = await const PreviewSourceScanner().scan(
      applicationRoot: consumer.root.path,
    );
    fixtureManifest = const PreviewManifestCompiler().compile(
      candidates: fixtureScan.candidates,
      catalog: consumer.catalog(),
      flutterCompatibility: PreviewSourceScanner.flutterCompatibility,
    );
  });

  tearDownAll(() => consumer.dispose());

  test('discovers public previews and compiles seven fixture captures', () {
    expect(fixtureScan.declarations, hasLength(5));
    expect(
      fixtureScan.declarations.map((value) => value.returnKind).toSet(),
      <PreviewFactoryReturnKind>{PreviewFactoryReturnKind.widget},
    );
    expect(fixtureManifest.descriptors, hasLength(7));
    expect(
      fixtureManifest.descriptors.map((value) => value.variant.id.value),
      <String>[
        'phone.light.en-us',
        'desktop.light.en-us',
        'phone.light.en-us',
        'desktop.light.en-us',
        'phone.dark.en-us',
        'phone.light.en-us',
        'phone.light.en-us',
      ],
    );
    expect(
      fixtureManifest.descriptors.map((value) => value.sourceUri).toSet(),
      <String>{'package:preview_test_consumer/previews.dart'},
    );
  });

  test(
    'rejects private, invalid-return, non-const, and empty declarations',
    () async {
      final invalidConsumer = TemporaryPreviewConsumer.create();
      addTearDown(invalidConsumer.dispose);
      invalidConsumer.previewSource.deleteSync();
      invalidConsumer.writeLibrary('invalid.dart', invalidPreviewSource);

      expect(
        () => const PreviewSourceScanner().scan(
          applicationRoot: invalidConsumer.root.path,
        ),
        throwsA(
          isA<PreviewSourceScanException>().having(
            (error) => error.issues.join('\n'),
            'issues',
            allOf(
              contains('preview factory must be public'),
              contains('must return Widget or WidgetBuilder'),
              contains('must resolve to a compile-time constant'),
              contains('variants must not be empty'),
            ),
          ),
        ),
      );
    },
  );

  test('writes registry and manifest only below .dart_tool', () async {
    final registry = await const EphemeralPreviewRegistryWriter().write(
      applicationRoot: consumer.root.path,
      planDigest: Digest.semantic(const <String, Object?>{
        'test': 'scanner-registry',
      }),
      manifest: fixtureManifest,
      scan: fixtureScan,
    );
    addTearDown(() async {
      final directory = Directory(registry.directory);
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    expect(
      p.isWithin(
        p.join(consumer.root.path, '.dart_tool'),
        registry.registryPath,
      ),
      isTrue,
    );
    final source = File(registry.registryPath).readAsStringSync();
    expect(
      source,
      contains("import 'package:preview_test_consumer/previews.dart'"),
    );
    expect(source, contains('fixture.dashboard.ready:phone.dark.en-us'));
    expect(
      source,
      contains('fixture.dashboard.gateway-traffic:desktop.light.en-us'),
    );
    expect(source, isNot(contains('dashboardReadyPreviews()(context)')));
    expect(
      File(registry.manifestPath).readAsStringSync(),
      contains(fixtureManifest.digest.value),
    );
    expect(
      File(
        p.join(consumer.root.path, 'lib', 'preview_registry.g.dart'),
      ).existsSync(),
      isFalse,
    );
  });
}
