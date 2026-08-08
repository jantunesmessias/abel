import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repositoryRoot = p.normalize(p.absolute('.'));
  final sampleRoot = p.join(repositoryRoot, 'examples', 'sample_flutter');
  late PreviewSourceScanResult sampleScan;
  late PreviewManifest sampleManifest;

  setUpAll(() async {
    sampleScan = await const PreviewSourceScanner().scan(
      applicationRoot: sampleRoot,
    );
    final loaded = const WorkspaceCatalogLoader().load(startPath: sampleRoot);
    final catalog = const CatalogCompiler().compile(loaded.documents);
    sampleManifest = const PreviewManifestCompiler().compile(
      candidates: sampleScan.candidates,
      catalog: catalog,
      flutterCompatibility: PreviewSourceScanner.flutterCompatibility,
    );
  });

  test('discovers all official previews and compiles seven captures', () {
    expect(sampleScan.declarations, hasLength(5));
    expect(
      sampleScan.declarations.map((value) => value.returnKind).toSet(),
      <PreviewFactoryReturnKind>{PreviewFactoryReturnKind.widget},
    );
    expect(sampleManifest.descriptors, hasLength(7));
    expect(
      sampleManifest.descriptors.map((value) => value.variant.id.value),
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
      sampleManifest.descriptors.map((value) => value.sourceUri).toSet(),
      <String>{'package:sample_flutter/previews/launch_previews.dart'},
    );
  });

  test(
    'rejects private, invalid-return, non-const, and empty declarations',
    () async {
      final fixture = Directory(
        p.join(
          sampleRoot,
          '.devex_scanner_test_${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      addTearDown(() async {
        if (fixture.existsSync()) await fixture.delete(recursive: true);
      });
      final lib = Directory(p.join(fixture.path, 'lib'))
        ..createSync(recursive: true);
      File(p.join(lib.path, 'invalid.dart')).writeAsStringSync(r'''
import 'package:devex_preview/devex_preview.dart';
import 'package:flutter/material.dart';

const dynamic runtimeId = String.fromEnvironment('PREVIEW_ID');

@AutoPreview(
  id: 'private.preview',
  scenarioId: 'launch-sample',
  variantId: 'phone',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
)
Widget _privatePreview() => const SizedBox();

@AutoPreview(
  id: 'invalid.return',
  scenarioId: 'launch-sample',
  variantId: 'phone',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
)
int invalidReturn() => 1;

@AutoPreview(
  id: runtimeId,
  scenarioId: 'launch-sample',
  variantId: 'phone',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
)
Widget nonConstPreview() => const SizedBox();

@AutoMultiPreview(
  id: 'empty.preview',
  scenarioId: 'launch-sample',
  variants: <AutoPreviewVariant>[],
)
Widget emptyPreview() => const SizedBox();
''');

      expect(
        () => const PreviewSourceScanner().scan(applicationRoot: fixture.path),
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
      applicationRoot: sampleRoot,
      planDigest: Digest.semantic(const <String, Object?>{
        'test': 'scanner-registry',
      }),
      manifest: sampleManifest,
      scan: sampleScan,
    );
    addTearDown(() async {
      final directory = Directory(registry.directory);
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    expect(
      p.isWithin(p.join(sampleRoot, '.dart_tool'), registry.registryPath),
      isTrue,
    );
    final source = File(registry.registryPath).readAsStringSync();
    expect(
      source,
      contains("import 'package:sample_flutter/previews/launch_previews.dart'"),
    );
    expect(source, contains('sample.dashboard.ready:phone.dark.en-us'));
    expect(
      source,
      contains('sample.dashboard.gateway-traffic:desktop.light.en-us'),
    );
    expect(source, isNot(contains('dashboardReadyPreviews()(context)')));
    expect(
      File(registry.manifestPath).readAsStringSync(),
      contains(sampleManifest.digest.value),
    );
    expect(
      File(p.join(sampleRoot, 'lib', 'preview_registry.g.dart')).existsSync(),
      isFalse,
    );
  });
}
