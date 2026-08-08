import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('breadcrumb links preserve a 48px interactive target', () {
    final css = _componentsCss().readAsStringSync();
    final breadcrumbRule = RegExp(
      r'\.studio-ui-breadcrumbs a\s*\{(?<body>[^}]*)\}',
      multiLine: true,
    ).firstMatch(css)?.namedGroup('body');

    expect(breadcrumbRule, isNotNull);
    expect(breadcrumbRule, contains('min-width: 3rem;'));
    expect(breadcrumbRule, contains('min-height: 3rem;'));
  });

  test('desktop shell constrains scrolling to the main content region', () {
    final css = _layoutCss().readAsStringSync();
    final shellRule = RegExp(
      r'\.studio-shell\s*\{(?<body>[^}]*)\}',
      multiLine: true,
    ).firstMatch(css)?.namedGroup('body');
    final mainRule = RegExp(
      r'\.studio-main\s*\{(?<body>[^}]*)\}',
      multiLine: true,
    ).firstMatch(css)?.namedGroup('body');
    final mobileRule = RegExp(
      r'@media \(max-width: 52rem\)\s*\{(?<body>[\s\S]*)\n\}',
      multiLine: true,
    ).firstMatch(css)?.namedGroup('body');

    expect(shellRule, contains('height: 100dvh;'));
    expect(shellRule, contains('overflow: hidden;'));
    expect(mainRule, contains('overflow: auto;'));
    expect(mobileRule, contains('height: auto;'));
    expect(mobileRule, contains('overflow: visible;'));
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
