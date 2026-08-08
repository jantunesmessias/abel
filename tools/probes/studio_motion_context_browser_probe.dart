import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart run tools/probes/studio_motion_context_browser_probe.dart '
      '<studio-origin> <webdriver-origin> <chromium-executable> <screenshot>',
    );
    exitCode = 64;
    return;
  }
  final studioOrigin = Uri.parse(arguments[0]);
  final driver = _WebDriver(Uri.parse(arguments[1]));
  final screenshotFile = File(arguments[3]);
  String? sessionId;
  var stage = 'session';
  try {
    sessionId = await driver.createSession(chromiumExecutable: arguments[2]);
    final motionRoute = studioOrigin.resolve(
      '/motion/delivery-journey?scenarioId=dashboard-ready',
    );
    final contextRoute = studioOrigin.resolve(
      '/context/delivery-journey?scenarioId=dashboard-ready',
    );

    stage = 'motion-full';
    await driver.navigate(sessionId, motionRoute);
    await driver.waitForSelector(
      sessionId,
      '[data-motion-mode="full"]',
      description: 'full Motion generation',
    );
    final fullAudit = await driver.auditMotion(sessionId);

    stage = 'motion-reduced';
    await driver.click(sessionId, '[data-motion-action="mode-reduced"]');
    await driver.click(sessionId, '[data-motion-action="play"]');
    await driver.waitForText(
      sessionId,
      'Execução observada: 2 etapas · 580 ms',
      description: 'reduced Motion duration',
    );

    stage = 'motion-none';
    await driver.click(sessionId, '[data-motion-action="mode-none"]');
    await driver.click(sessionId, '[data-motion-action="play"]');
    await driver.waitForText(
      sessionId,
      'Execução observada: 2 etapas · 0 ms',
      description: 'none Motion duration',
    );
    final noneAudit = await driver.auditMotion(sessionId);

    stage = 'context-first';
    await driver.navigate(sessionId, contextRoute);
    await driver.waitForSelector(
      sessionId,
      '[data-context-state="idle"]',
      description: 'Context Builder description',
    );
    await driver.click(sessionId, '[data-context-action="export"]');
    await driver.waitForSelector(
      sessionId,
      '[data-context-state="ready"]',
      description: 'first deterministic Context export',
    );
    final firstContext = await driver.auditContext(sessionId);

    stage = 'context-reload';
    await driver.navigate(sessionId, contextRoute);
    await driver.waitForSelector(
      sessionId,
      '[data-context-state="idle"]',
      description: 'Context Builder after reload',
    );
    await driver.click(sessionId, '[data-context-action="export"]');
    await driver.waitForSelector(
      sessionId,
      '[data-context-state="ready"]',
      description: 'second deterministic Context export',
    );
    final secondContext = await driver.auditContext(sessionId);
    if (firstContext.digest != secondContext.digest) {
      throw StateError('Equivalent Context exports were not deterministic');
    }

    stage = 'context-omission';
    await driver.click(sessionId, '[data-context-category="evidence"]');
    await driver.click(sessionId, '[data-context-action="export"]');
    await driver.waitForContextDigestChange(
      sessionId,
      secondContext.digest,
      description: 'Context export with evidence omitted',
    );
    final omittedContext = await driver.auditContext(sessionId);
    if (!omittedContext.evidenceOmitted ||
        omittedContext.digest == secondContext.digest) {
      throw StateError('Context omission was not explicit and deterministic');
    }

    stage = 'surface-audit';
    final transientMarkers = await driver.transientMarkerCount(sessionId);
    if (transientMarkers != 0) {
      throw StateError('Context surface retained transient authority material');
    }
    final severeLogs = await driver.severeBrowserLogs(sessionId);
    if (severeLogs.isNotEmpty) {
      throw StateError('Browser reported severe log entries');
    }

    stage = 'screenshot';
    final screenshot = await driver.screenshot(sessionId);
    final inspection = const PngCaptureInspector().inspect(screenshot);
    if (inspection.width < 1200 || inspection.height < 800) {
      throw StateError('Motion/Context screenshot has an unexpected viewport');
    }
    screenshotFile.parent.createSync(recursive: true);
    screenshotFile.writeAsBytesSync(screenshot, flush: true);

    stdout.writeln(
      jsonEncode(<String, Object?>{
        'motionModesProved': true,
        'motionStepCount': fullAudit.stepCount,
        'motionObservationCount': fullAudit.observationCount,
        'staticEquivalentPreserved':
            fullAudit.staticEquivalent && noneAudit.staticEquivalent,
        'contextCategoryCount': firstContext.categoryCount,
        'contextItemCount': firstContext.itemCount,
        'contextOmissionCount': omittedContext.omissionCount,
        'contextDeterministic': true,
        'evidenceOmissionProved': true,
        'transientAuthorityMarkers': transientMarkers,
        'severeBrowserLogs': severeLogs.length,
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

final class _MotionAudit {
  const _MotionAudit({
    required this.stepCount,
    required this.observationCount,
    required this.staticEquivalent,
  });

  final int stepCount;
  final int observationCount;
  final bool staticEquivalent;
}

final class _ContextAudit {
  const _ContextAudit({
    required this.digest,
    required this.categoryCount,
    required this.itemCount,
    required this.omissionCount,
    required this.evidenceOmitted,
  });

  final String digest;
  final int categoryCount;
  final int itemCount;
  final int omissionCount;
  final bool evidenceOmitted;
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
    );
  }

  Future<void> click(String sessionId, String selector) async {
    final clicked = await _execute(
      sessionId,
      r'''
const element = document.querySelector(arguments[0]);
if (!(element instanceof HTMLElement) || element.matches(':disabled')) return false;
element.click();
return true;
''',
      <Object?>[selector],
    );
    if (clicked != true) throw StateError('Control is unavailable');
  }

  Future<void> waitForSelector(
    String sessionId,
    String selector, {
    required String description,
    Duration timeout = const Duration(seconds: 30),
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

  Future<void> waitForText(
    String sessionId,
    String expected, {
    required String description,
    Duration timeout = const Duration(seconds: 30),
  }) => _waitUntil(
    () async {
      final value = await _execute(
        sessionId,
        "return document.body?.innerText ?? '';",
      );
      return value is String && value.contains(expected);
    },
    description: description,
    timeout: timeout,
  );

  Future<void> waitForContextDigestChange(
    String sessionId,
    String previous, {
    required String description,
  }) => _waitUntil(() async {
    final value = await _execute(sessionId, r'''
const root = document.querySelector('[data-context-state="ready"]');
return root?.getAttribute('data-context-digest') ?? '';
''');
    return value is String && value.isNotEmpty && value != previous;
  }, description: description);

  Future<_MotionAudit> auditMotion(String sessionId) async {
    final value = await _execute(sessionId, r'''
const body = document.body?.innerText ?? '';
return {
  stepCount: document.querySelectorAll('.motion-step').length,
  observationCount: document.querySelectorAll('.motion-observations li').length,
  staticEquivalent: body.includes('Loading resolves to ready') &&
    body.includes('Compreensão preservada') &&
    body.includes('movimento não contém informação exclusiva'),
};
''');
    final result = _object(value, 'MotionAudit');
    if (result['stepCount'] != 2 ||
        result['observationCount'] != 2 ||
        result['staticEquivalent'] != true) {
      throw StateError('Motion surface audit failed');
    }
    return _MotionAudit(
      stepCount: result['stepCount']! as int,
      observationCount: result['observationCount']! as int,
      staticEquivalent: result['staticEquivalent']! as bool,
    );
  }

  Future<_ContextAudit> auditContext(String sessionId) async {
    final value = await _execute(sessionId, r'''
const root = document.querySelector('[data-context-state="ready"]');
const omissions = Array.from(document.querySelectorAll('.context-omissions li'))
  .map((element) => element.textContent ?? '');
return {
  digest: root?.getAttribute('data-context-digest') ?? '',
  categoryCount: document.querySelectorAll('.context-budget').length,
  itemCount: document.querySelectorAll('.context-items li').length,
  omissionCount: omissions.length,
  evidenceOmitted: omissions.includes('evidence · evidence · omittedByRequest'),
};
''');
    final result = _object(value, 'ContextAudit');
    final digest = result['digest'];
    if (digest is! String ||
        !digest.startsWith('sha256:') ||
        result['categoryCount'] != 5 ||
        result['itemCount'] is! int ||
        result['omissionCount'] is! int ||
        result['evidenceOmitted'] is! bool) {
      throw StateError('Context surface audit failed');
    }
    return _ContextAudit(
      digest: digest,
      categoryCount: result['categoryCount']! as int,
      itemCount: result['itemCount']! as int,
      omissionCount: result['omissionCount']! as int,
      evidenceOmitted: result['evidenceOmitted']! as bool,
    );
  }

  Future<int> transientMarkerCount(String sessionId) async {
    final value = await _execute(sessionId, r'''
const body = document.documentElement?.outerHTML ?? '';
const markers = [
  'authorityId', 'policyId', 'principalId', 'grantId', 'grantDigest',
  'capabilityDigest', 'contentRoot', '/home/', 'Bearer ',
  'PRIVATE KEY', 'postgres://', 'postgresql://', 'mysql://'
];
return markers.filter((marker) => body.includes(marker)).length;
''');
    if (value is! int) throw const FormatException('Marker count is invalid');
    return value;
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
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await condition()) return;
      } on Object {
        // Transient rerenders and navigation are expected while polling.
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

  void close() => _client.close(force: true);
}
