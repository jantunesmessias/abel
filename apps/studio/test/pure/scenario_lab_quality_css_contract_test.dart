import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Lab and Quality CSS remains responsive and CSP-safe', () {
    final css = _componentsCss().readAsStringSync();

    for (final selector in const <String>[
      '.scenario-surface-list',
      '.scenario-surface-list__link',
      '.scenario-surface-list__cross-link',
      '.scenario-lab-panel',
      '.scenario-lab-panel__metadata',
      '.scenario-quality-panel',
      '.scenario-quality-panel__states',
    ]) {
      expect(css, contains(selector), reason: 'missing $selector');
    }
    expect(css, contains('min-height: 3rem;'));
    expect(css, contains('@media (max-width: 48rem)'));
    expect(css, isNot(contains('style=')));
  });
}

File _componentsCss() {
  for (final path in const <String>[
    'apps/studio/web/styles/components.css',
    'web/styles/components.css',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  throw StateError('Could not locate Studio components.css');
}
