import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Authoring CSS stays responsive and honors forced/reduced modes', () {
    final css = _authoringCss().readAsStringSync();

    for (final selector in const <String>[
      '.authoring-page',
      '.authoring-node-grid',
      '.authoring-direction-controls',
      '.authoring-coordinate-form',
      '.authoring-review-inputs',
      '.authoring-table-scroll',
      '.authoring-decision-list',
    ]) {
      expect(css, contains(selector), reason: 'missing $selector');
    }
    expect(css, contains('@media (max-width: 36rem)'));
    expect(css, contains('@media (forced-colors: active)'));
    expect(css, contains('@media (prefers-reduced-motion: reduce)'));
    expect(css, contains('overflow-x: auto'));
    expect(css, isNot(contains('style=')));
  });

  test('the standalone stylesheet is loaded by the CSP-safe document', () {
    final html = _indexHtml().readAsStringSync();
    expect(html, contains('href="/styles/authoring.css"'));
    expect(html, contains("style-src 'self'"));
  });
}

File _authoringCss() => _find(const <String>[
  'apps/studio/web/styles/authoring.css',
  'web/styles/authoring.css',
]);

File _indexHtml() =>
    _find(const <String>['apps/studio/web/index.html', 'web/index.html']);

File _find(List<String> paths) {
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  throw StateError('Could not locate ${paths.first.split('/').last}');
}
