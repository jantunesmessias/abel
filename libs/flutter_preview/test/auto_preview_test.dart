import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_preview/flutter_preview.dart';
import 'package:flutter_test/flutter_test.dart';

@AutoPreview(
  id: 'sample.single',
  scenarioId: 'launch-sample',
  variantId: 'phone.light',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
  devicePixelRatio: 3,
)
Widget singlePreview() => const Text('single');

@AutoMultiPreview(
  id: 'sample.multi',
  scenarioId: 'launch-sample',
  variants: <AutoPreviewVariant>[
    AutoPreviewVariant(
      variantId: 'phone.light',
      size: Size(390, 844),
      localeTag: 'pt-BR',
      brightness: Brightness.light,
      devicePixelRatio: 3,
    ),
    AutoPreviewVariant(
      variantId: 'phone.dark',
      size: Size(390, 844),
      localeTag: 'pt-BR',
      brightness: Brightness.dark,
      devicePixelRatio: 3,
    ),
  ],
)
Widget multiPreview() => const Text('multi');

void main() {
  test(
    'AutoPreview is official Preview metadata plus stable platform identity',
    () {
      const preview = AutoPreview(
        id: 'sample.single',
        scenarioId: 'launch-sample',
        variantId: 'phone.light',
        size: Size(390, 844),
        localeTag: 'pt-BR',
        brightness: Brightness.light,
        devicePixelRatio: 3,
      );

      expect(preview, isA<Preview>());
      expect(preview.group, 'Abel');
      expect(preview.size, const Size(390, 844));
      expect(preview.textScaleFactor, 1);
      expect(preview.devicePixelRatio, 3);
      expect(PreviewCompatibility.flutter, '3.47.x');
      expect(PreviewCompatibility.widgetPreviewApi, 'experimental-v2');
    },
  );

  test('AutoMultiPreview expands official previews of one Scenario', () {
    const preview = AutoMultiPreview(
      id: 'sample.multi',
      scenarioId: 'launch-sample',
      variants: <AutoPreviewVariant>[
        AutoPreviewVariant(
          variantId: 'phone.light',
          size: Size(390, 844),
          localeTag: 'pt-BR',
          brightness: Brightness.light,
        ),
        AutoPreviewVariant(
          variantId: 'phone.dark',
          size: Size(390, 844),
          localeTag: 'pt-BR',
          brightness: Brightness.dark,
        ),
      ],
    );

    expect(preview, isA<MultiPreview>());
    expect(preview.previews, hasLength(2));
    expect(preview.variants.map((variant) => variant.variantId), <String>[
      'phone.light',
      'phone.dark',
    ]);
  });
}
