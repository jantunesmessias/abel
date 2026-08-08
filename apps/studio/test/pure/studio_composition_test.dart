import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/studio_composition.dart';
import 'package:test/test.dart';

void main() {
  test('gates Inventory independently from Journey Map', () {
    final inventoryOnly = StudioComposition(
      planDigest: Digest.semantic(const <String, Object?>{'plan': 1}),
      contributions: const <String>['studio.shell', 'studio.inventory'],
    );

    expect(inventoryOnly.shellEnabled, isTrue);
    expect(inventoryOnly.inventoryEnabled, isTrue);
    expect(inventoryOnly.journeyMapEnabled, isFalse);

    final journeyOnly = StudioComposition(
      planDigest: Digest.semantic(const <String, Object?>{'plan': 2}),
      contributions: const <String>['studio.shell', 'studio.journey-map'],
    );
    expect(journeyOnly.inventoryEnabled, isFalse);
    expect(journeyOnly.journeyMapEnabled, isTrue);
  });

  test('gates Lab and Quality as independent contributions', () {
    final labOnly = StudioComposition(
      planDigest: Digest.semantic(const <String, Object?>{'plan': 'lab'}),
      contributions: const <String>['studio.shell', 'studio.lab'],
    );
    expect(labOnly.labEnabled, isTrue);
    expect(labOnly.qualityEnabled, isFalse);

    final qualityOnly = StudioComposition(
      planDigest: Digest.semantic(const <String, Object?>{'plan': 'quality'}),
      contributions: const <String>['studio.shell', 'studio.quality'],
    );
    expect(qualityOnly.labEnabled, isFalse);
    expect(qualityOnly.qualityEnabled, isTrue);
  });

  test('gates Authoring independently', () {
    final authoringOnly = StudioComposition(
      planDigest: Digest.semantic(const <String, Object?>{'plan': 'authoring'}),
      contributions: const <String>['studio.shell', 'studio.authoring'],
    );

    expect(authoringOnly.authoringEnabled, isTrue);
    expect(authoringOnly.inventoryEnabled, isFalse);
  });
}
