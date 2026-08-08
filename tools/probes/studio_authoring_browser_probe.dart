import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    stderr.writeln(
      'Usage: dart run tools/probes/studio_authoring_browser_probe.dart '
      '<studio-origin> <webdriver-origin> <chromium-executable> <screenshot>',
    );
    exitCode = 64;
    return;
  }
  final studioOrigin = Uri.parse(arguments[0]);
  final driver = _WebDriver(Uri.parse(arguments[1]));
  final chromium = arguments[2];
  final screenshotFile = File(arguments[3]);
  String? authorSession;
  String? staleSession;
  var stage = 'primary-session';
  try {
    authorSession = await driver.createSession(chromiumExecutable: chromium);
    stage = 'secondary-session';
    staleSession = await driver.createSession(chromiumExecutable: chromium);
    stage = 'navigation';
    final route = studioOrigin.resolve('/authoring/delivery-journey');
    stage = 'author-ready';
    await Future.wait(<Future<void>>[
      driver.navigate(authorSession, route),
      driver.navigate(staleSession, route),
    ]);
    await Future.wait(<Future<void>>[
      driver.waitForSelector(
        authorSession,
        '[data-authoring-role="author"][data-authoring-state="ready"]',
        description: 'Author mode on the primary connection',
      ),
      driver.waitForSelector(
        staleSession,
        '[data-authoring-role="author"][data-authoring-state="ready"]',
        description: 'Author mode on the stale-writer connection',
      ),
    ]);

    stage = 'draft-open';
    await driver.click(authorSession, '[data-authoring-action="open-draft"]');
    await driver.waitForSelector(
      authorSession,
      '[data-authoring-action="prepare-review"]',
      description: 'opened authoring draft',
    );
    await driver.click(staleSession, '[data-authoring-action="refresh"]');
    await driver.waitForSelector(
      staleSession,
      '[data-authoring-action="move-node-direita"]',
      description: 'shared draft observed by second connection',
    );

    stage = 'stale-writer';
    const nodeId = 'journey-dashboard-ready';
    final nodeSelector = '[data-authoring-node="${_cssString(nodeId)}"]';
    final moveSelector =
        '$nodeSelector [data-authoring-action="move-node-direita"]';

    await driver.click(authorSession, moveSelector);
    await driver.waitForSelector(
      authorSession,
      '$nodeSelector[data-authoring-node-changed="true"]',
      description: 'primary writer move',
    );
    await driver.click(staleSession, moveSelector);
    await driver.waitForText(
      staleSession,
      'Writer desatualizado',
      description: 'typed stale-writer rejection',
    );

    stage = 'draft-history';
    await driver.click(authorSession, '[data-authoring-action="undo"]');
    await driver.waitForSelector(
      authorSession,
      '$nodeSelector[data-authoring-node-changed="false"]',
      description: 'undo materialization',
    );
    await driver.click(authorSession, '[data-authoring-action="redo"]');
    await driver.waitForSelector(
      authorSession,
      '$nodeSelector[data-authoring-node-changed="true"]',
      description: 'redo materialization',
    );
    await driver.click(authorSession, '[data-authoring-action="reset"]');
    await driver.waitForSelector(
      authorSession,
      '$nodeSelector[data-authoring-node-changed="false"]',
      description: 'reset materialization',
    );
    await driver.click(authorSession, moveSelector);
    await driver.waitForSelector(
      authorSession,
      '$nodeSelector[data-authoring-node-changed="true"]',
      description: 'final reviewable move',
    );
    stage = 'review-prepare';
    await driver.click(
      authorSession,
      '[data-authoring-action="prepare-review"]',
    );
    await driver.waitForSelector(
      authorSession,
      '[data-authoring-review-instruction="true"]',
      description: 'materialized ReviewGuide',
    );

    stage = 'finding';
    await driver.setValue(
      authorSession,
      '#authoring-finding-summary',
      'Layout move inspected',
    );
    stage = 'concept';
    await driver.setValue(
      authorSession,
      '#authoring-finding-detail',
      'The moved frame remains legible and keeps its scenario binding.',
    );
    await driver.click(
      authorSession,
      '[data-authoring-action="append-finding"]',
    );
    await driver.waitForText(
      authorSession,
      'Layout move inspected',
      description: 'scenario-bound finding',
    );

    stage = 'comment';
    await driver.setValue(
      authorSession,
      '#authoring-concept-title',
      'Delivery follow-up concept',
    );
    await driver.setValue(
      authorSession,
      '#authoring-concept-rationale',
      'Keep the proposal explicitly non-current until it is authored.',
    );
    stage = 'acceptance';
    await driver.click(
      authorSession,
      '[data-authoring-action="propose-concept"]',
    );
    await driver.waitForText(
      authorSession,
      'Delivery follow-up concept',
      description: 'non-current concept proposal',
    );

    stage = 'rejection';
    await driver.setValue(
      authorSession,
      '#authoring-comment-body',
      'Review comment retained append-only.',
    );
    await driver.click(
      authorSession,
      '[data-authoring-action="append-comment"]',
    );
    await driver.waitForText(
      authorSession,
      'Review comment retained append-only.',
      description: 'append-only review comment',
    );

    await driver.click(
      authorSession,
      '[data-authoring-action="evaluate-acceptance"]',
    );
    await driver.waitForText(
      authorSession,
      'Automated acceptance passou',
      description: 'Host-run structural acceptance',
    );

    stage = 'approval';
    await driver.setValue(
      authorSession,
      '#authoring-decision-rationale',
      'Reject once to prove append-only supersession.',
    );
    await driver.click(authorSession, '[data-authoring-action="reject"]');
    await driver.click(authorSession, '[data-authoring-confirmation="reject"]');
    await driver.waitForSelector(
      authorSession,
      '[data-authoring-decision="reject"][data-authoring-decision-state="head"]',
      description: 'rejection decision head',
    );

    await driver.setValue(
      authorSession,
      '#authoring-decision-rationale',
      'Approve the exact reviewed head after the explicit rejection.',
    );
    await driver.click(authorSession, '[data-authoring-action="approve"]');
    await driver.click(
      authorSession,
      '[data-authoring-confirmation="approve"]',
    );
    await driver.waitForSelector(
      authorSession,
      '[data-authoring-decision="reject"][data-authoring-decision-state="superseded"]',
      description: 'superseded rejection',
    );
    await driver.waitForSelector(
      authorSession,
      '[data-authoring-decision="approve"][data-authoring-decision-state="head"]',
      description: 'approval decision head',
    );

    stage = 'review-audit';
    final reviewAudit = await driver.auditReview(authorSession);

    stage = 'promotion';
    await driver.click(authorSession, '[data-authoring-action="promote"]');
    await driver.click(
      authorSession,
      '[data-authoring-confirmation="promote"]',
    );
    await driver.waitForText(
      authorSession,
      'Promoção 1',
      description: 'durable promotion receipt',
      timeout: const Duration(seconds: 60),
    );
    await driver.waitForSelector(
      authorSession,
      '[data-authoring-action="open-draft"]',
      description: 'promoted layout generation reopened',
      timeout: const Duration(seconds: 60),
    );

    stage = 'final-audit';
    final finalAudit = await driver.auditFinal(authorSession);
    final severe = <String>[
      ...await driver.severeBrowserLogs(authorSession),
      ...await driver.severeBrowserLogs(staleSession),
    ];
    if (severe.isNotEmpty) {
      throw StateError('Browser reported ${severe.length} severe log entries');
    }
    stage = 'screenshot';
    final screenshot = await driver.screenshot(authorSession);
    final inspection = const PngCaptureInspector().inspect(screenshot);
    if (inspection.width < 1200 || inspection.height < 800) {
      throw StateError('Authoring screenshot has an unexpected viewport');
    }
    screenshotFile.parent.createSync(recursive: true);
    screenshotFile.writeAsBytesSync(screenshot, flush: true);

    stdout.writeln(
      jsonEncode(<String, Object?>{
        'authorMode': true,
        'staleWriterRejected': true,
        'undoRedoResetExercised': true,
        'reviewGuideMaterialized': true,
        'findingCount': reviewAudit['findingCount'],
        'conceptCount': reviewAudit['conceptCount'],
        'commentCount': reviewAudit['commentCount'],
        'decisionCount': reviewAudit['decisionCount'],
        'supersededDecisionCount': reviewAudit['supersededDecisionCount'],
        'promotionCount': finalAudit['promotionCount'],
        'transientAuthorityMarkers': finalAudit['transientAuthorityMarkers'],
        'severeBrowserLogs': severe.length,
        'screenshotDigest': Digest.bytes(screenshot).value,
        'screenshotWidth': inspection.width,
        'screenshotHeight': inspection.height,
      }),
    );
  } on Object catch (error) {
    var publicState = 'unavailable';
    var publicFailureCode = 'none';
    if (authorSession != null) {
      try {
        publicState = await driver.authoringStatus(authorSession);
        publicFailureCode = await driver.authoringFailureCode(authorSession);
      } on Object {
        publicState = 'unavailable';
        publicFailureCode = 'none';
      }
    }
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
        'publicState': publicState,
        'publicFailureCode': publicFailureCode,
      }),
    );
    exitCode = 1;
  } finally {
    if (authorSession != null) await driver.deleteSession(authorSession);
    if (staleSession != null) await driver.deleteSession(staleSession);
    driver.close();
  }
}

String _cssString(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

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
    if (clicked != true) throw StateError('Control is unavailable: $selector');
  }

  Future<void> setValue(String sessionId, String selector, String value) async {
    final changed = await _execute(
      sessionId,
      r'''
const element = document.querySelector(arguments[0]);
if (!(element instanceof HTMLInputElement) && !(element instanceof HTMLTextAreaElement)) return false;
element.value = arguments[1];
element.dispatchEvent(new InputEvent('input', {
  bubbles: true,
  inputType: 'insertText',
  data: arguments[1],
}));
return true;
''',
      <Object?>[selector, value],
    );
    if (changed != true) throw StateError('Input is unavailable: $selector');
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

  Future<Map<String, Object?>> auditReview(String sessionId) async {
    final value = await _execute(sessionId, r'''
return {
  findingCount: document.querySelectorAll('.authoring-review-record [data-finding]').length ||
    Array.from(document.querySelectorAll('.authoring-review-record li strong'))
      .filter((element) => element.textContent === 'Layout move inspected').length,
  conceptCount: Array.from(document.querySelectorAll('.authoring-review-record li strong'))
    .filter((element) => element.textContent === 'Delivery follow-up concept').length,
  commentCount: Array.from(document.querySelectorAll('.authoring-review-record li p'))
    .filter((element) => element.textContent === 'Review comment retained append-only.').length,
  decisionCount: document.querySelectorAll('[data-authoring-decision]').length,
  supersededDecisionCount: document.querySelectorAll(
    '[data-authoring-decision-state="superseded"]'
  ).length,
};
''');
    final result = _object(value, 'AuthoringReviewAudit');
    if (result['findingCount'] != 1 ||
        result['conceptCount'] != 1 ||
        result['commentCount'] != 1 ||
        result['decisionCount'] != 2 ||
        result['supersededDecisionCount'] != 1) {
      throw StateError('Authoring review-surface audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditFinal(String sessionId) async {
    final value = await _execute(sessionId, r'''
const body = document.body?.innerText ?? '';
const markers = [
  'authorityId', 'policyId', 'principalId', 'grantId', 'grantDigest',
  'capabilityDigest', 'contentRoot', '/home/'
];
return {
  promotionCount: Array.from(document.querySelectorAll('.authoring-promotion-history li strong'))
    .filter((element) => element.textContent?.startsWith('Promoção ')).length,
  transientAuthorityMarkers: markers.filter((marker) => body.includes(marker)).length,
};
''');
    final result = _object(value, 'AuthoringFinalAudit');
    if (result['promotionCount'] != 1 ||
        result['transientAuthorityMarkers'] != 0) {
      throw StateError('Authoring final-surface audit failed: $result');
    }
    return result;
  }

  Future<List<int>> screenshot(String sessionId) async {
    final response = await _request('GET', '/session/$sessionId/screenshot');
    final value = response['value'];
    if (value is! String || value.length > 32 * 1024 * 1024) {
      throw const FormatException('WebDriver screenshot is invalid');
    }
    return base64Decode(value);
  }

  Future<String> authoringStatus(String sessionId) async {
    final value = await _execute(
      sessionId,
      "return document.body?.innerText ?? '';",
    );
    if (value is! String) return 'unavailable';
    const states = <String, String>{
      'Writer desatualizado': 'conflict',
      'Resposta incompatível': 'protocolViolation',
      'Host indisponível': 'transportFailure',
      'Modo Author': 'author',
      'Modo Viewer': 'viewer',
      'Authoring não suportado': 'unsupported',
      'Aplicando operação': 'submitting',
      'Carregando estado autoritativo': 'loading',
    };
    for (final entry in states.entries) {
      if (value.contains(entry.key)) return entry.value;
    }
    return 'unknown';
  }

  Future<String> authoringFailureCode(String sessionId) async {
    final value = await _execute(
      sessionId,
      "return document.body?.innerText ?? '';",
    );
    if (value is! String) return 'none';
    for (final code in ExperienceAuthoringErrorCode.values) {
      if (value.contains('Código tipado: ${code.name}.')) return code.name;
    }
    return 'none';
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
      throw StateError('WebDriver command failed: ${value['error']}');
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
