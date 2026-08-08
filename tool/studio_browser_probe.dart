import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 || arguments.length > 3) {
    stderr.writeln(
      'Usage: dart run tool/studio_browser_probe.dart '
      '<studio-origin> <webdriver-origin> [chromium-executable]',
    );
    exitCode = 64;
    return;
  }
  final studioOrigin = Uri.parse(arguments[0]);
  final driverOrigin = Uri.parse(arguments[1]);
  final chromium = arguments.length == 3 ? arguments[2] : null;
  final driver = _WebDriver(driverOrigin);
  String? sessionId;
  try {
    sessionId = await driver.createSession(chromiumExecutable: chromium);
    await driver.navigate(sessionId, studioOrigin);
    final explore = await driver.waitForText(sessionId, const <String>[
      'Sample Flutter consumer',
      'Understand the runtime',
    ]);

    final journeyUri = studioOrigin.resolve(
      '/journeys/understand-runtime-configuration',
    );
    await driver.navigate(sessionId, journeyUri);
    final journey = await driver.waitForText(sessionId, const <String>[
      'Understand the runtime configuration',
      'Launch the sample application',
    ]);
    final semantics = await driver.auditSemanticHtml(sessionId);
    final keyboard = await driver.auditKeyboardNavigation(sessionId);
    final performance = await driver.performanceMetrics(sessionId);
    final reflow = await driver.auditReflowAtTwoHundredPercent(sessionId);
    final resources = await driver.resourceRequests(sessionId);
    if (!resources.any((value) => value.contains('/resources/'))) {
      throw StateError('Chromium did not request any Host resource handle');
    }
    final screenshot = await driver.screenshot(sessionId);
    final inspection = const PngCaptureInspector().inspect(screenshot);
    if (inspection.width < 1000 || inspection.height < 700) {
      throw StateError('Chromium screenshot has an unexpected viewport');
    }
    final severeLogs = await driver.severeBrowserLogs(sessionId);
    if (severeLogs.isNotEmpty) {
      throw StateError('Chromium reported severe errors: ${severeLogs.first}');
    }

    stdout.writeln(
      jsonEncode(<String, Object?>{
        'exploreMatchedLabels': explore,
        'journeyMatchedLabels': journey,
        'semanticHtml': semantics,
        'keyboard': keyboard,
        'reflow200Percent': reflow,
        'performance': performance,
        'resourceRequests': resources
            .where((value) => value.contains('/resources/'))
            .length,
        'screenshotDigest': Digest.bytes(screenshot).value,
        'screenshotWidth': inspection.width,
        'screenshotHeight': inspection.height,
        'severeBrowserLogs': severeLogs.length,
      }),
    );
  } on Object catch (error, stackTrace) {
    if (sessionId != null) {
      try {
        final browserLogs = await driver.severeBrowserLogs(sessionId);
        for (final message in browserLogs) {
          stderr.writeln('[browser-severe] $message');
        }
      } on Object {
        // Preserve the original probe failure if browser log retrieval fails.
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  } finally {
    if (sessionId != null) await driver.deleteSession(sessionId);
    driver.close();
  }
}

final class _WebDriver {
  _WebDriver(this.origin);

  final Uri origin;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  Future<String> createSession({String? chromiumExecutable}) async {
    final value = await _request('POST', '/session', <String, Object?>{
      'capabilities': <String, Object?>{
        'alwaysMatch': <String, Object?>{
          'browserName': 'chrome',
          'goog:chromeOptions': <String, Object?>{
            'binary': ?chromiumExecutable,
            'args': <String>[
              '--headless=new',
              '--no-sandbox',
              '--disable-dev-shm-usage',
              '--disable-gpu',
              '--window-size=1440,1000',
            ],
          },
          'goog:loggingPrefs': const <String, String>{'browser': 'ALL'},
        },
      },
    });
    final result = _object(value['value'], 'NewSession.value');
    final id = result['sessionId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('WebDriver did not return a session ID');
    }
    return id;
  }

  Future<void> navigate(String sessionId, Uri uri) async {
    await _request('POST', '/session/$sessionId/url', <String, Object?>{
      'url': uri.toString(),
    });
    await _waitUntil(
      () async =>
          await _execute(sessionId, 'return document.readyState') == 'complete',
      description: 'document readiness',
    );
  }

  Future<List<String>> waitForText(
    String sessionId,
    List<String> expected,
  ) async {
    await _waitUntil(() async {
      final value = await _execute(sessionId, '''
return document.body?.innerText ?? '';
''');
      final body = value is String ? value.toLowerCase() : '';
      return expected.every((item) => body.contains(item.toLowerCase()));
    }, description: 'Studio semantic content: ${expected.join(', ')}');
    return expected;
  }

  Future<Map<String, Object?>> auditSemanticHtml(String sessionId) async {
    final value = await _execute(sessionId, r'''
const focusables = Array.from(document.querySelectorAll(
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
));
const accessibleName = (element) => {
  const aria = element.getAttribute('aria-label')?.trim();
  if (aria) return aria;
  const labelledBy = element.getAttribute('aria-labelledby');
  if (labelledBy) {
    const value = labelledBy.split(/\s+/)
      .map((id) => document.getElementById(id)?.textContent?.trim() ?? '')
      .filter(Boolean)
      .join(' ');
    if (value) return value;
  }
  if (element.id) {
    const label = document.querySelector(`label[for="${CSS.escape(element.id)}"]`)
      ?.textContent?.trim();
    if (label) return label;
  }
  return element.textContent?.trim() || element.getAttribute('title') || '';
};
const unnamed = focusables.filter((element) => !accessibleName(element));
const targetSizes = focusables.map((element) => {
  const rect = element.getBoundingClientRect();
  return Math.min(rect.width, rect.height);
}).filter((size) => size > 0);
return {
  hasMain: Boolean(document.querySelector('main#main-content')),
  hasPrimaryNavigation: Boolean(document.querySelector('nav[aria-label]')),
  hasPageHeading: Boolean(document.querySelector('main h1')),
  hasLiveRegion: Boolean(document.querySelector('[aria-live], [role="status"], [role="alert"]')),
  nativeDialogCount: document.querySelectorAll('dialog').length,
  flutterElementCount: document.querySelectorAll('[class^="flt-"], flt-glass-pane, flt-semantics').length,
  focusableCount: focusables.length,
  unnamedFocusableCount: unnamed.length,
  minimumInteractiveSize: targetSizes.length ? Math.min(...targetSizes) : 0,
};
''');
    final result = _object(value, 'SemanticHtmlAudit');
    if (result['hasMain'] != true ||
        result['hasPrimaryNavigation'] != true ||
        result['hasPageHeading'] != true ||
        result['hasLiveRegion'] != true ||
        result['flutterElementCount'] != 0 ||
        (result['focusableCount'] as num? ?? 0) < 8 ||
        result['unnamedFocusableCount'] != 0 ||
        (result['minimumInteractiveSize'] as num? ?? 0) < 24) {
      throw StateError('Studio semantic HTML audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditKeyboardNavigation(String sessionId) async {
    await _execute(sessionId, 'document.body.focus(); return true;');
    final visited = <String>[];
    for (var index = 0; index < 8; index += 1) {
      await _request(
        'POST',
        '/session/$sessionId/actions',
        const <String, Object?>{
          'actions': <Object?>[
            <String, Object?>{
              'type': 'key',
              'id': 'keyboard',
              'actions': <Object?>[
                <String, Object?>{'type': 'keyDown', 'value': '\uE004'},
                <String, Object?>{'type': 'keyUp', 'value': '\uE004'},
              ],
            },
          ],
        },
      );
      final current = await _execute(sessionId, r'''
const element = document.activeElement;
return element ? `${element.tagName}:${element.getAttribute('aria-label') || element.textContent || element.id}`.trim() : '';
''');
      if (current is String && current.isNotEmpty) visited.add(current);
    }
    await _request('DELETE', '/session/$sessionId/actions');
    if (visited.toSet().length < 5) {
      throw StateError('Keyboard traversal did not reach enough controls');
    }
    return <String, Object?>{
      'tabStopsVisited': visited.length,
      'uniqueTabStops': visited.toSet().length,
    };
  }

  Future<Map<String, Object?>> auditReflowAtTwoHundredPercent(
    String sessionId,
  ) async {
    await _request(
      'POST',
      '/session/$sessionId/window/rect',
      const <String, Object?>{'width': 360, 'height': 800},
    );
    final value = await _execute(sessionId, r'''
document.documentElement.style.fontSize = '200%';
const root = document.documentElement;
const body = document.body;
return {
  viewportWidth: window.innerWidth,
  rootScrollWidth: root.scrollWidth,
  bodyScrollWidth: body.scrollWidth,
  horizontalDocumentOverflow: Math.max(root.scrollWidth, body.scrollWidth) > window.innerWidth + 1,
  mainVisible: document.querySelector('main')?.getBoundingClientRect().width > 0,
  headingVisible: document.querySelector('main h1')?.getBoundingClientRect().height > 0,
};
''');
    final result = _object(value, 'ReflowAudit');
    await _execute(
      sessionId,
      "document.documentElement.style.removeProperty('font-size'); return true;",
    );
    await _request(
      'POST',
      '/session/$sessionId/window/rect',
      const <String, Object?>{'width': 1440, 'height': 1000},
    );
    if (result['horizontalDocumentOverflow'] != false ||
        result['mainVisible'] != true ||
        result['headingVisible'] != true) {
      throw StateError('Studio 200% text reflow audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> performanceMetrics(String sessionId) async {
    final value = await _execute(sessionId, r'''
const navigation = performance.getEntriesByType('navigation')[0];
const paints = Object.fromEntries(
  performance.getEntriesByType('paint').map((entry) => [entry.name, entry.startTime])
);
return {
  domContentLoadedMs: navigation?.domContentLoadedEventEnd ?? 0,
  loadEventMs: navigation?.loadEventEnd ?? 0,
  firstContentfulPaintMs: paints['first-contentful-paint'] ?? 0,
  transferredBytes: performance.getEntriesByType('resource')
    .reduce((total, entry) => total + (entry.transferSize || 0), 0),
};
''');
    final result = _object(value, 'PerformanceMetrics');
    final load = result['loadEventMs'] as num? ?? double.infinity;
    if (load <= 0 || load > 5000) {
      throw StateError('Studio load exceeded the local 5 s budget: $result');
    }
    return result;
  }

  Future<List<String>> resourceRequests(String sessionId) async {
    final value = await _execute(sessionId, '''
return performance.getEntriesByType('resource').map((entry) => entry.name);
''');
    return value is List<Object?>
        ? value.whereType<String>().toList(growable: false)
        : const <String>[];
  }

  Future<List<int>> screenshot(String sessionId) async {
    final response = await _request('GET', '/session/$sessionId/screenshot');
    final value = response['value'];
    if (value is! String || value.length > 32 * 1024 * 1024) {
      throw const FormatException('WebDriver screenshot is invalid');
    }
    return base64Decode(value);
  }

  Future<List<String>> severeBrowserLogs(String sessionId) async {
    final response = await _request(
      'POST',
      '/session/$sessionId/se/log',
      const <String, Object?>{'type': 'browser'},
    );
    final value = response['value'];
    if (value is! List<Object?>) return const <String>[];
    return <String>[
      for (final item in value)
        if (item is Map<String, Object?> && item['level'] == 'SEVERE')
          '${item['message']}',
    ];
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _request('DELETE', '/session/$sessionId');
    } on Object {
      // ChromeDriver cleanup remains best-effort after a failed assertion.
    }
  }

  Future<Object?> _execute(String sessionId, String script) async {
    final response = await _request(
      'POST',
      '/session/$sessionId/execute/sync',
      <String, Object?>{'script': script, 'args': const <Object?>[]},
    );
    return response['value'];
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final request = await _client.openUrl(method, origin.resolve(path));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      if (buffer.length + chunk.length > 32 * 1024 * 1024) {
        throw const FormatException('WebDriver response exceeded its limit');
      }
      return buffer..addAll(chunk);
    });
    final decoded = bytes.isEmpty
        ? <String, Object?>{}
        : jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('WebDriver response must be an object');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('WebDriver $method $path failed: $decoded');
    }
    final value = decoded['value'];
    if (value is Map<String, Object?> && value['error'] is String) {
      throw StateError('WebDriver command failed: ${value['message']}');
    }
    return decoded;
  }

  Future<void> _waitUntil(
    Future<bool> Function() condition, {
    required String description,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await condition()) return;
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException(
      'Timed out waiting for $description${lastError == null ? '' : ': $lastError'}',
    );
  }

  Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }

  void close() => _client.close(force: true);
}
