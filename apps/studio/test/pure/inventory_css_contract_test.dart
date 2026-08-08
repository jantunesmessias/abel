import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Inventory CSS owns responsive layout and CSP-safe spatial geometry', () {
    final css = _layoutCss().readAsStringSync();

    for (final selector in const <String>[
      '.inventory-page',
      '.inventory-toolbar__filters',
      '.inventory-layout',
      '.inventory-scenario-grid',
      '.inventory-outline',
      '.inventory-canvas',
      '.inventory-inspector',
      '.inventory-map-viewport',
    ]) {
      expect(css, contains(selector), reason: 'missing $selector');
    }
    expect(
      css,
      contains(
        '@supports (width: calc(attr(data-canvas-width type(<number>)) * 1px))',
      ),
    );
    expect(css, contains('attr(data-x type(<number>))'));
    expect(css, contains('@media (max-width: 52rem)'));
    expect(css, contains('@media (max-width: 36rem)'));
  });
}

File _layoutCss() {
  for (final path in const <String>[
    'apps/studio/web/styles/layout.css',
    'web/styles/layout.css',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  throw StateError('Could not locate Studio layout.css');
}
