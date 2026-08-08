import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: studio_scale_browser_probe <studio-origin> <webdriver-origin> '
      '<chromium-executable> <screenshot>',
    );
    exitCode = 64;
    return;
  }
  final driver = _WebDriver(Uri.parse(arguments[1]));
  String? sessionId;
  var stage = 'session';
  try {
    sessionId = await driver.createSession(chromiumExecutable: arguments[2]);
    stage = 'load';
    final route = Uri.parse(
      arguments[0],
    ).resolve('/journeys/scale-journey/nodes/node-01000');
    await driver.navigate(sessionId, route);
    await driver.waitForSelector(
      sessionId,
      '.journey-map-stage[data-window-rendered]',
      description: 'scale Journey window',
      timeout: const Duration(seconds: 90),
    );
    await driver.waitForSelector(
      sessionId,
      '.scenario-outline-list[data-outline-total="2000"]',
      description: 'scale Outline window',
      timeout: const Duration(seconds: 90),
    );

    stage = 'desktop-audit';
    final desktop = await driver.audit(sessionId);
    _validateDesktop(desktop);
    await driver.proveKeyboardFocus(sessionId);
    final focus = await driver.focusAudit(sessionId);
    if (!focus.focused || !focus.visible) {
      throw StateError('Keyboard focus was not visible on the Journey map');
    }
    final contrast = await driver.contrastAudit(sessionId);
    if (contrast.controlCount < 4 || contrast.minimumRatio < 4.5) {
      throw StateError('Essential Journey controls failed contrast audit');
    }
    final reducedMotion = await driver.reducedMotionAudit(sessionId);
    if (!reducedMotion.queryMatches || !reducedMotion.durationsBounded) {
      throw StateError('Scale Journey failed the reduced-motion audit');
    }

    stage = 'screenshot';
    final screenshot = await driver.screenshot(sessionId);
    final inspection = const PngCaptureInspector().inspect(screenshot);
    if (inspection.width < 1200 || inspection.height < 800) {
      throw StateError('Scale screenshot has an unexpected viewport');
    }
    final screenshotFile = File(arguments[3]);
    screenshotFile.parent.createSync(recursive: true);
    screenshotFile.writeAsBytesSync(screenshot, flush: true);

    stage = 'text-scale-audit';
    await driver.setWindowRect(sessionId, width: 360, height: 900);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final textScale = await driver.textScaleAudit(sessionId);
    if (textScale.horizontalDocumentOverflow ||
        !textScale.mainVisible ||
        !textScale.outlineWindowAvailable) {
      throw StateError('Scale Journey failed the 200% text reflow audit');
    }

    stage = 'responsive-audit';
    final responsive = await driver.responsiveAudit(sessionId);
    if (responsive.horizontalDocumentOverflow ||
        !responsive.mainVisible ||
        !responsive.outlineWindowAvailable) {
      throw StateError('Scale Journey failed the 360px reflow audit');
    }

    stage = 'browser-logs';
    final logs = await driver.severeBrowserLogs(sessionId);
    if (logs.isNotEmpty) throw StateError('Browser emitted severe log entries');

    stdout.writeln(
      jsonEncode(<String, Object?>{
        'outlineTotal': desktop.outlineTotal,
        'outlineRendered': desktop.outlineRendered,
        'mapRenderedItems': desktop.mapRenderedItems,
        'mapRenderedEdges': desktop.mapRenderedEdges,
        'mapBoundaryRetained': desktop.mapBoundaryRetained,
        'mapBoundaryTotal': desktop.mapBoundaryTotal,
        'domElementCount': desktop.domElementCount,
        'landmarksNamed': desktop.landmarksNamed,
        'nonDragNavigation': desktop.nonDragNavigation,
        'keyboardFocusVisible': true,
        'essentialControlCount': contrast.controlCount,
        'minimumTextContrast': contrast.minimumRatio,
        'reducedMotion': true,
        'textScale200Overflow': textScale.horizontalDocumentOverflow,
        'horizontalOverflow360': responsive.horizontalDocumentOverflow,
        'transientMarkerCount': desktop.transientMarkerCount,
        'severeBrowserLogs': logs.length,
        'screenshotDigest': Digest.bytes(screenshot).value,
        'screenshotWidth': inspection.width,
        'screenshotHeight': inspection.height,
      }),
    );
  } on Object catch (error) {
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'stage': stage,
        'failure': switch (error) {
          TimeoutException() => 'timeout',
          FormatException() => 'protocol',
          StateError() => 'state',
          FileSystemException() => 'filesystem',
          _ => 'unexpected',
        },
      }),
    );
    exitCode = 1;
  } finally {
    if (sessionId != null) await driver.deleteSession(sessionId);
    driver.close();
  }
}

void _validateDesktop(_DesktopAudit audit) {
  if (audit.outlineTotal != 2000 ||
      audit.outlineRendered < 1 ||
      audit.outlineRendered > 48 ||
      audit.outlineDomItems != audit.outlineRendered ||
      !audit.selectedOutlineItemPresent ||
      audit.mapRenderedItems < 1 ||
      audit.mapRenderedItems > 64 ||
      audit.mapRenderedEdges < 0 ||
      audit.mapRenderedEdges > 256 ||
      audit.mapBoundaryRetained < 0 ||
      audit.mapBoundaryRetained > 256 ||
      audit.mapBoundaryTotal < audit.mapBoundaryRetained ||
      audit.domElementCount > 5000 ||
      !audit.landmarksNamed ||
      !audit.nonDragNavigation ||
      audit.transientMarkerCount != 0) {
    throw StateError('Scale browser surface violated its bounded contract');
  }
}

final class _DesktopAudit {
  const _DesktopAudit({
    required this.outlineTotal,
    required this.outlineRendered,
    required this.outlineDomItems,
    required this.selectedOutlineItemPresent,
    required this.mapRenderedItems,
    required this.mapRenderedEdges,
    required this.mapBoundaryRetained,
    required this.mapBoundaryTotal,
    required this.domElementCount,
    required this.landmarksNamed,
    required this.nonDragNavigation,
    required this.transientMarkerCount,
  });

  final int outlineTotal;
  final int outlineRendered;
  final int outlineDomItems;
  final bool selectedOutlineItemPresent;
  final int mapRenderedItems;
  final int mapRenderedEdges;
  final int mapBoundaryRetained;
  final int mapBoundaryTotal;
  final int domElementCount;
  final bool landmarksNamed;
  final bool nonDragNavigation;
  final int transientMarkerCount;
}

final class _FocusAudit {
  const _FocusAudit({required this.focused, required this.visible});

  final bool focused;
  final bool visible;
}

final class _ResponsiveAudit {
  const _ResponsiveAudit({
    required this.horizontalDocumentOverflow,
    required this.mainVisible,
    required this.outlineWindowAvailable,
  });

  final bool horizontalDocumentOverflow;
  final bool mainVisible;
  final bool outlineWindowAvailable;
}

final class _ContrastAudit {
  const _ContrastAudit({
    required this.controlCount,
    required this.minimumRatio,
  });

  final int controlCount;
  final double minimumRatio;
}

final class _ReducedMotionAudit {
  const _ReducedMotionAudit({
    required this.queryMatches,
    required this.durationsBounded,
  });

  final bool queryMatches;
  final bool durationsBounded;
}

final class _WebDriver {
  _WebDriver(this.origin);

  final Uri origin;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  Future<String> createSession({required String chromiumExecutable}) async {
    final value = await _request('POST', '/session', <String, Object?>{
      'capabilities': <String, Object?>{
        'alwaysMatch': <String, Object?>{
          'browserName': 'chrome',
          'goog:chromeOptions': <String, Object?>{
            'binary': chromiumExecutable,
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
      timeout: const Duration(seconds: 90),
    );
  }

  Future<void> waitForSelector(
    String sessionId,
    String selector, {
    required String description,
    required Duration timeout,
  }) => _waitUntil(
    () async =>
        await _execute(
          sessionId,
          'return Boolean(document.querySelector(arguments[0]));',
          <Object?>[selector],
        ) ==
        true,
    description: description,
    timeout: timeout,
  );

  Future<_DesktopAudit> audit(String sessionId) async {
    final value = await _execute(sessionId, r'''
const outline = document.querySelector('.scenario-outline-list');
const stage = document.querySelector('.journey-map-stage');
const html = document.documentElement?.outerHTML ?? '';
const integer = (element, name) => Number.parseInt(element?.getAttribute(name) ?? '-1', 10);
const markers = [
  'authorityId', 'policyId', 'principalId', 'grantId', 'grantDigest',
  'capabilityDigest', 'contentRoot', '/home/', 'Bearer ', 'PRIVATE KEY',
  'postgres://', 'postgresql://', 'mysql://', 'aws_access_key_id'
];
return {
  outlineTotal: integer(outline, 'data-outline-total'),
  outlineRendered: integer(outline, 'data-outline-rendered'),
  outlineDomItems: outline?.querySelectorAll(':scope > li').length ?? -1,
  selectedOutlineItemPresent: Boolean(outline?.querySelector('[aria-current="step"]')),
  mapRenderedItems: integer(stage, 'data-window-rendered'),
  mapRenderedEdges: integer(stage, 'data-renderable-edge-rendered'),
  mapBoundaryRetained: integer(stage, 'data-boundary-edge-retained'),
  mapBoundaryTotal: integer(stage, 'data-boundary-edge-total'),
  domElementCount: document.querySelectorAll('*').length,
  landmarksNamed: Boolean(
    document.querySelector('main#main-content') &&
    document.querySelector('nav[aria-label="Navegação principal"]') &&
    document.querySelector('aside[aria-label="Outline da Journey"]') &&
    document.querySelector('aside[aria-label="Inspector da Journey"]') &&
    document.querySelector('[role="region"][aria-label="Viewport do Journey Map"]')
  ),
  nonDragNavigation: Boolean(
    document.querySelector('nav[aria-label="Navegação da janela do Outline"] a') &&
    document.querySelector('.scenario-outline-item') &&
    document.querySelector('[role="region"][tabindex="0"]')
  ),
  transientMarkerCount: markers.filter((marker) => html.includes(marker)).length,
};
''');
    final json = _object(value, 'DesktopAudit');
    return _DesktopAudit(
      outlineTotal: _integer(json, 'outlineTotal'),
      outlineRendered: _integer(json, 'outlineRendered'),
      outlineDomItems: _integer(json, 'outlineDomItems'),
      selectedOutlineItemPresent: _boolean(json, 'selectedOutlineItemPresent'),
      mapRenderedItems: _integer(json, 'mapRenderedItems'),
      mapRenderedEdges: _integer(json, 'mapRenderedEdges'),
      mapBoundaryRetained: _integer(json, 'mapBoundaryRetained'),
      mapBoundaryTotal: _integer(json, 'mapBoundaryTotal'),
      domElementCount: _integer(json, 'domElementCount'),
      landmarksNamed: _boolean(json, 'landmarksNamed'),
      nonDragNavigation: _boolean(json, 'nonDragNavigation'),
      transientMarkerCount: _integer(json, 'transientMarkerCount'),
    );
  }

  Future<void> proveKeyboardFocus(String sessionId) async {
    final focused = await _execute(sessionId, r'''
const element = document.querySelector('[role="region"][aria-label="Viewport do Journey Map"]');
if (!(element instanceof HTMLElement)) return false;
element.focus();
return document.activeElement === element;
''');
    if (focused != true) {
      throw StateError('Journey map could not receive focus');
    }
    await _request('POST', '/session/$sessionId/actions', <String, Object?>{
      'actions': <Object?>[
        <String, Object?>{
          'type': 'key',
          'id': 'scale-keyboard',
          'actions': <Object?>[
            const <String, Object?>{'type': 'keyDown', 'value': '\uE008'},
            const <String, Object?>{'type': 'keyDown', 'value': '\uE004'},
            const <String, Object?>{'type': 'keyUp', 'value': '\uE004'},
            const <String, Object?>{'type': 'keyUp', 'value': '\uE008'},
            const <String, Object?>{'type': 'keyDown', 'value': '\uE004'},
            const <String, Object?>{'type': 'keyUp', 'value': '\uE004'},
          ],
        },
      ],
    });
    await _request('DELETE', '/session/$sessionId/actions');
  }

  Future<_FocusAudit> focusAudit(String sessionId) async {
    final value = await _execute(sessionId, r'''
const element = document.querySelector('[role="region"][aria-label="Viewport do Journey Map"]');
const style = element instanceof HTMLElement ? getComputedStyle(element) : null;
return {
  focused: document.activeElement === element,
  visible: Boolean(element?.matches(':focus-visible')) &&
    style?.outlineStyle !== 'none' && Number.parseFloat(style?.outlineWidth ?? '0') > 0,
};
''');
    final json = _object(value, 'FocusAudit');
    return _FocusAudit(
      focused: _boolean(json, 'focused'),
      visible: _boolean(json, 'visible'),
    );
  }

  Future<_ContrastAudit> contrastAudit(String sessionId) async {
    final value = await _execute(sessionId, r'''
const parse = (value) => {
  const match = value.match(/rgba?\((\d+(?:\.\d+)?)\D+(\d+(?:\.\d+)?)\D+(\d+(?:\.\d+)?)(?:\D+(\d+(?:\.\d+)?))?\)/);
  return match ? [Number(match[1]), Number(match[2]), Number(match[3]), match[4] === undefined ? 1 : Number(match[4])] : null;
};
const composite = (front, back) => {
  const alpha = front[3] + back[3] * (1 - front[3]);
  if (alpha <= 0) return [0, 0, 0, 0];
  return [
    (front[0] * front[3] + back[0] * back[3] * (1 - front[3])) / alpha,
    (front[1] * front[3] + back[1] * back[3] * (1 - front[3])) / alpha,
    (front[2] * front[3] + back[2] * back[3] * (1 - front[3])) / alpha,
    alpha,
  ];
};
const background = (element) => {
  let result = [0, 0, 0, 0];
  const layers = [];
  for (let current = element; current; current = current.parentElement) {
    const color = parse(getComputedStyle(current).backgroundColor);
    if (color && color[3] > 0) layers.push(color);
  }
  layers.push(parse(getComputedStyle(document.documentElement).backgroundColor) ?? [255, 255, 255, 1]);
  for (const layer of layers.reverse()) result = composite(layer, result);
  return result;
};
const luminance = (color) => {
  const channels = color.slice(0, 3).map((value) => {
    const normalized = value / 255;
    return normalized <= 0.04045
      ? normalized / 12.92
      : Math.pow((normalized + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
};
const ratio = (left, right) => {
  const a = luminance(left);
  const b = luminance(right);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
};
const controls = Array.from(document.querySelectorAll(
  '.studio-nav__item, .scenario-outline-item a, nav[aria-label="Navegação da janela do Outline"] a'
)).filter((element) => {
  const rect = element.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0 && getComputedStyle(element).visibility !== 'hidden';
});
const ratios = controls.map((element) => {
  const foreground = parse(getComputedStyle(element).color);
  return foreground ? ratio(foreground, background(element)) : 0;
});
return {
  controlCount: ratios.length,
  minimumRatio: ratios.length ? Math.min(...ratios) : 0,
};
''');
    final json = _object(value, 'ContrastAudit');
    return _ContrastAudit(
      controlCount: _integer(json, 'controlCount'),
      minimumRatio: _number(json, 'minimumRatio'),
    );
  }

  Future<_ReducedMotionAudit> reducedMotionAudit(String sessionId) async {
    await _request(
      'POST',
      '/session/$sessionId/goog/cdp/execute',
      <String, Object?>{
        'cmd': 'Emulation.setEmulatedMedia',
        'params': <String, Object?>{
          'features': <Object?>[
            <String, Object?>{
              'name': 'prefers-reduced-motion',
              'value': 'reduce',
            },
          ],
        },
      },
    );
    try {
      final value = await _execute(sessionId, r'''
const elements = Array.from(document.querySelectorAll('a, button, [role="region"]')).slice(0, 64);
const seconds = (value) => value.split(',').map((part) => {
  const text = part.trim();
  const number = Number.parseFloat(text);
  return Number.isFinite(number) ? number * (text.endsWith('ms') ? 0.001 : 1) : 1;
});
const durations = elements.flatMap((element) => {
  const style = getComputedStyle(element);
  return [...seconds(style.transitionDuration), ...seconds(style.animationDuration)];
});
return {
  queryMatches: matchMedia('(prefers-reduced-motion: reduce)').matches,
  durationsBounded: durations.length > 0 && durations.every((duration) => duration <= 0.001),
};
''');
      final json = _object(value, 'ReducedMotionAudit');
      return _ReducedMotionAudit(
        queryMatches: _boolean(json, 'queryMatches'),
        durationsBounded: _boolean(json, 'durationsBounded'),
      );
    } finally {
      await _request(
        'POST',
        '/session/$sessionId/goog/cdp/execute',
        const <String, Object?>{
          'cmd': 'Emulation.setEmulatedMedia',
          'params': <String, Object?>{},
        },
      );
    }
  }

  Future<void> setWindowRect(
    String sessionId, {
    required int width,
    required int height,
  }) => _request('POST', '/session/$sessionId/window/rect', <String, Object?>{
    'width': width,
    'height': height,
  }).then((_) {});

  Future<_ResponsiveAudit> responsiveAudit(String sessionId) async {
    final value = await _execute(sessionId, r'''
const root = document.documentElement;
const body = document.body;
const main = document.querySelector('main#main-content');
return {
  horizontalDocumentOverflow: Math.max(root?.scrollWidth ?? 0, body?.scrollWidth ?? 0) > window.innerWidth + 1,
  mainVisible: main instanceof HTMLElement && main.getBoundingClientRect().width > 0,
  outlineWindowAvailable: Boolean(document.querySelector('nav[aria-label="Navegação da janela do Outline"]')),
};
''');
    final json = _object(value, 'ResponsiveAudit');
    return _ResponsiveAudit(
      horizontalDocumentOverflow: _boolean(json, 'horizontalDocumentOverflow'),
      mainVisible: _boolean(json, 'mainVisible'),
      outlineWindowAvailable: _boolean(json, 'outlineWindowAvailable'),
    );
  }

  Future<_ResponsiveAudit> textScaleAudit(String sessionId) async {
    await _execute(
      sessionId,
      "document.documentElement.style.fontSize = '200%'; return true;",
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    try {
      return await responsiveAudit(sessionId);
    } finally {
      await _execute(
        sessionId,
        "document.documentElement.style.removeProperty('font-size'); return true;",
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
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
      // Best-effort after a failed assertion.
    }
  }

  Future<Object?> _execute(
    String sessionId,
    String script, [
    List<Object?> arguments = const <Object?>[],
  ]) async {
    final response = await _request(
      'POST',
      '/session/$sessionId/execute/sync',
      <String, Object?>{'script': script, 'args': arguments},
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
      throw StateError('WebDriver command failed with HTTP status');
    }
    final value = decoded['value'];
    if (value is Map<String, Object?> && value['error'] is String) {
      throw StateError('WebDriver command failed');
    }
    return decoded;
  }

  Future<void> _waitUntil(
    Future<bool> Function() condition, {
    required String description,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await condition()) return;
      } on Object {
        // The Studio rerenders while the Host content resource is opening.
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException('Timed out waiting for $description');
  }

  Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }

  int _integer(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int) throw FormatException('$key must be an integer');
    return value;
  }

  bool _boolean(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! bool) throw FormatException('$key must be a boolean');
    return value;
  }

  double _number(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('$key must be a finite number');
    }
    return value.toDouble();
  }

  void close() => _client.close(force: true);
}
