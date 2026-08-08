import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Motion and Context CSS is responsive and honors user preferences', () {
    final css = _css().readAsStringSync();

    for (final selector in const <String>[
      '.motion-mode-group',
      '.motion-static-equivalent',
      '.motion-comprehension-proof',
      '.context-inclusions',
      '.context-budget-grid',
      '.context-toggle',
      '.context-result',
    ]) {
      expect(css, contains(selector), reason: 'missing $selector');
    }
    expect(css, contains('@media (max-width: 360px)'));
    expect(css, contains('@media (forced-colors: active)'));
    expect(css, contains('@media (prefers-reduced-motion: reduce)'));
    expect(css, contains('minmax(min(100%, 12rem), 1fr)'));
    expect(css, contains('min-height: 48px'));
    expect(css, isNot(contains('style=')));
  });

  test('the stylesheet is loaded by the CSP-safe document', () {
    final html = _index().readAsStringSync();
    expect(html, contains('href="/styles/motion_context.css"'));
    expect(html, contains("style-src 'self'"));
  });
}

File _css() => _find(const <String>[
  'apps/studio/web/styles/motion_context.css',
  'web/styles/motion_context.css',
]);

File _index() =>
    _find(const <String>['apps/studio/web/index.html', 'web/index.html']);

File _find(List<String> paths) {
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  throw StateError('Could not locate ${paths.first.split('/').last}');
}
