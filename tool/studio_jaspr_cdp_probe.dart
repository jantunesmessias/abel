import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_runtime/devex_runtime.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/studio_jaspr_cdp_probe.dart '
      '<chrome-debug-origin> <studio-url> '
      '[--confirm-synthetic-data|--no-preview|--capture-only|--watch-reconnect|--showcase-flow=<dir>] '
      '[--wait-for=<text>] [--viewport=<width>x<height>] '
      '[--screenshot=<png-path>] [--dialog-screenshot=<png-path>]',
    );
    exitCode = 64;
    return;
  }
  final debugOrigin = Uri.parse(arguments[0]);
  final studioUri = Uri.parse(arguments[1]);
  final confirmSyntheticData = arguments.contains('--confirm-synthetic-data');
  final noPreview = arguments.contains('--no-preview');
  final captureOnly = arguments.contains('--capture-only');
  final watchReconnect = arguments.contains('--watch-reconnect');
  final showcaseFlowDirectory = arguments
      .where((item) => item.startsWith('--showcase-flow='))
      .map((item) => item.substring('--showcase-flow='.length))
      .firstOrNull;
  final showcaseFlow = showcaseFlowDirectory != null;
  if (<bool>[
        confirmSyntheticData,
        noPreview,
        captureOnly,
        watchReconnect,
        showcaseFlow,
      ].where((value) => value).length >
      1) {
    throw ArgumentError('Preview operation modes are mutually exclusive');
  }
  final waitForText =
      arguments
          .where((item) => item.startsWith('--wait-for='))
          .map((item) => item.substring('--wait-for='.length))
          .firstOrNull ??
      'Host conectado';
  if (waitForText.isEmpty || waitForText.length > 512) {
    throw ArgumentError('--wait-for must contain between 1 and 512 chars');
  }
  final viewport = _parseViewport(
    arguments
        .where((item) => item.startsWith('--viewport='))
        .map((item) => item.substring('--viewport='.length))
        .firstOrNull,
  );
  final screenshotPath = arguments
      .where((item) => item.startsWith('--screenshot='))
      .map((item) => item.substring('--screenshot='.length))
      .firstOrNull;
  final dialogScreenshotPath = arguments
      .where((item) => item.startsWith('--dialog-screenshot='))
      .map((item) => item.substring('--dialog-screenshot='.length))
      .firstOrNull;
  _requireLoopbackHttp(debugOrigin, 'Chrome debugging origin');
  _requireLoopbackHttp(studioUri, 'Studio URL');
  if (screenshotPath != null && !File(screenshotPath).isAbsolute) {
    throw ArgumentError('Screenshot path must be absolute');
  }
  if (dialogScreenshotPath != null && !File(dialogScreenshotPath).isAbsolute) {
    throw ArgumentError('Dialog screenshot path must be absolute');
  }
  if (captureOnly && screenshotPath == null) {
    throw ArgumentError('--capture-only requires --screenshot');
  }
  if (showcaseFlow) {
    final directory = Directory(showcaseFlowDirectory);
    if (!directory.isAbsolute) {
      throw ArgumentError('--showcase-flow requires an absolute directory');
    }
    directory.createSync(recursive: true);
  }

  final target = await _createTarget(debugOrigin, studioUri);
  final connection = await _CdpConnection.connect(target.webSocketUri);
  try {
    await Future.wait(<Future<Object?>>[
      connection.send('Page.enable'),
      connection.send('Runtime.enable'),
      connection.send('Network.enable'),
      connection.send('Log.enable'),
      connection.send('Accessibility.enable'),
    ]);
    if (viewport case final size?) {
      await connection
          .send('Emulation.setDeviceMetricsOverride', <String, Object?>{
            'width': size.$1,
            'height': size.$2,
            'deviceScaleFactor': 1,
            'mobile': size.$1 < 600,
          });
    }
    await _waitFor(
      () async =>
          await connection.evaluate<String>('document.readyState') ==
          'complete',
      description: 'document readiness',
    );
    await _waitFor(
      () async => await connection.bodyContains(waitForText),
      description: 'visible text "$waitForText"',
    );
    if (watchReconnect) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'status': 'armed',
          'mode': 'watch-reconnect',
          'hostConnected': true,
        }),
      );
      await _waitFor(
        () async =>
            await connection.bodyContains('Host indisponível') ||
            await connection.bodyContains('Conectando') ||
            await connection.bodyContains('Snapshot desatualizado'),
        description: 'Host disconnect state',
        timeout: const Duration(minutes: 2),
      );
      await _waitFor(
        () async => await connection.bodyContains('Host conectado'),
        description: 'automatic Host reconnection',
        timeout: const Duration(minutes: 3),
      );
      await connection.evaluate<Object?>(r'''
new Promise((resolve) => requestAnimationFrame(
  () => requestAnimationFrame(resolve)
))
''');
      final screenshot = await connection.captureScreenshot();
      if (screenshotPath != null) {
        await File(screenshotPath).writeAsBytes(screenshot, flush: true);
      }
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'status': 'passed',
          'mode': 'watch-reconnect',
          'hostConnected': true,
          'screenshotDigest': Digest.bytes(screenshot).value,
          'severeBrowserLogs': connection.severeLogs.length,
        }),
      );
      return;
    }
    if (showcaseFlow) {
      Future<void> capture(String name) async {
        await connection.evaluate<Object?>(r'''
(() => {
  const active = document.activeElement;
  if (active instanceof HTMLElement) active.blur();
  return true;
})()
''');
        await connection.evaluate<Object?>(r'''
new Promise((resolve) => requestAnimationFrame(
  () => requestAnimationFrame(resolve)
))
''');
        await File(
          '$showcaseFlowDirectory/$name.png',
        ).writeAsBytes(await connection.captureScreenshot(), flush: true);
      }

      await _waitFor(
        () async => await connection.bodyContains('Iniciar target'),
        description: 'Target controls',
      );
      await capture('08-target-idle');
      await connection.clickButton('Iniciar target');
      await _waitFor(
        () async => await connection.bodyContains('Aplicação em execução'),
        description: 'ready Target session',
        timeout: const Duration(minutes: 3),
      );
      await _waitFor(
        () async => connection.requestedUrlStartsWith(
          'http://127.0.0.1:8181/v1/dashboard',
        ),
        description: 'direct Target dashboard request',
        timeout: const Duration(minutes: 1),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await capture('09-target-running');
      await connection.clickLink('Gateway Lab');
      await _waitFor(
        () async => await connection.bodyContains('showcase-hybrid'),
        description: 'Gateway presets',
      );
      await connection.selectValue('gateway-preset', 'showcase-hybrid');
      await capture('10-gateway-ready');
      await connection.clickButton('Iniciar Gateway');
      await _waitFor(
        () async => await connection.bodyContains('Estado operacional'),
        description: 'running Gateway sidecar',
        timeout: const Duration(minutes: 2),
      );
      final gatewayPageText =
          await connection.evaluate<String>('document.body?.innerText ?? ""') ??
          '';
      final gatewayOriginMatch = RegExp(
        r'Origem de dados\s+(http://127\.0\.0\.1:\d+)',
      ).firstMatch(gatewayPageText);
      if (gatewayOriginMatch == null) {
        throw StateError('Gateway origin was not rendered by the Studio');
      }
      final gatewayOrigin = gatewayOriginMatch.group(1)!;
      await capture('11-gateway-running');
      await connection.clickLink('Abrir Target com Gateway');
      await _waitFor(
        () async => await connection.bodyContains('Aplicação em execução'),
        description: 'Target mounted with Gateway overlay',
      );
      await _waitFor(
        () async =>
            connection.requestedUrlStartsWith('$gatewayOrigin/v1/dashboard'),
        description: 'Target dashboard request through Gateway',
        timeout: const Duration(minutes: 3),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await connection.evaluate<Object?>(r'''
(() => {
  const frame = document.querySelector('iframe');
  if (!frame) return false;
  const top = frame.getBoundingClientRect().top + window.scrollY - 260;
  window.scrollTo({top: Math.max(0, top), behavior: 'instant'});
  return true;
})()
''');
      await capture('12-target-with-gateway');
      await connection.clickLink('Gateway Lab');
      await _waitFor(
        () async => await connection.bodyContains('Atualizar tráfego'),
        description: 'Gateway traffic controls',
      );
      await connection.clickButton('Atualizar tráfego');
      await _waitFor(
        () async => await connection.bodyContains('/v1/dashboard'),
        description: 'observed Gateway traffic',
        timeout: const Duration(minutes: 1),
      );
      await connection.evaluate<Object?>(r'''
(() => {
  const row = Array.from(document.querySelectorAll('tr'))
    .find((item) => item.textContent.includes('/v1/dashboard'));
  row?.scrollIntoView({block: 'center', behavior: 'instant'});
  return Boolean(row);
})()
''');
      await capture('13-gateway-traffic');
      await connection.clickLink('Target');
      await _waitFor(
        () async => await connection.bodyContains('Aplicação em execução'),
        description: 'Target cleanup controls',
      );
      await connection.clickButton('Encerrar');
      await _waitFor(
        () async => await connection.bodyContains('Target encerrado'),
        description: 'stopped Target session',
      );
      await connection.clickLink('Gateway Lab');
      await _waitFor(
        () async => await connection.bodyContains('Inicie o Target'),
        description: 'Gateway cascade cleanup',
      );
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'status': 'passed',
          'mode': 'showcase-flow',
          'captures': 6,
          'targetStopped': true,
          'gatewayStopped': true,
          'severeBrowserLogs': connection.severeLogs.length,
          'browserErrors': connection.severeLogs.take(10).toList(),
        }),
      );
      return;
    }
    if (captureOnly) {
      await _waitFor(
        () async =>
            await connection.evaluate<bool>(r'''
(() => {
  const isVisible = (element) => {
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 &&
      rect.bottom >= 0 && rect.right >= 0 &&
      rect.top <= innerHeight && rect.left <= innerWidth;
  };
  const pending = Array.from(document.querySelectorAll(
    '.verified-artifact-placeholder[data-resource-state="validating"]'
  )).filter(isVisible).length;
  const imagesReady = Array.from(document.images).filter(isVisible)
    .every((image) => image.complete && image.naturalWidth > 0);
  return pending === 0 && imagesReady;
})()
''') ??
            false,
        description: 'visual resources',
      );
      await connection.evaluate<Object?>(r'''
new Promise((resolve) => requestAnimationFrame(
  () => requestAnimationFrame(resolve)
))
''');
      final screenshot = await connection.captureScreenshot();
      final inspection = const PngCaptureInspector().inspect(screenshot);
      await File(screenshotPath!).writeAsBytes(screenshot, flush: true);
      final accessibilityNodes = await connection.accessibilityNodeCount();
      if (connection.severeLogs.isNotEmpty) {
        throw StateError(
          'Chrome reported a severe error: ${connection.severeLogs.first}',
        );
      }
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'status': 'passed',
          'mode': 'capture-only',
          'url': await connection.evaluate<String>('location.href'),
          'title': await connection.evaluate<String>('document.title'),
          'waitFor': waitForText,
          'accessibilityNodes': accessibilityNodes,
          'resourceRequests': connection.resourceUrls.length,
          'screenshotDigest': Digest.bytes(screenshot).value,
          'screenshotWidth': inspection.width,
          'screenshotHeight': inspection.height,
          'severeBrowserLogs': connection.severeLogs.length,
        }),
      );
      return;
    }
    final semantics = await connection.auditSemanticHtml();
    final keyboard = await connection.auditKeyboardNavigation();
    final performance = await connection.performanceMetrics();
    final reducedMotion = await connection.auditReducedMotion();
    final reflow = await connection.auditReflowAtTwoHundredPercent();
    final mapInteraction = await connection.auditMapInteractionPerformance();

    String? dialogFocus;
    num dialogCount = 0;
    String? focusAfterDialog;
    if (!noPreview) {
      await _waitFor(
        () async =>
            await connection.bodyContains('Coletar novamente') ||
            await connection.bodyContains('Coletar AutoPreview'),
        description: 'AutoPreview collection action',
      );

      final actionLabel = await connection.bodyContains('Coletar novamente')
          ? 'Coletar novamente'
          : 'Coletar AutoPreview';
      await connection.clickButton(actionLabel);
      await _waitFor(
        () async => await connection.bodyContains('Coletar AutoPreview?'),
        description: 'AutoPreview confirmation dialog',
      );
      dialogFocus = await connection.activeElementText();
      dialogCount =
          await connection.evaluate<num>(
            "document.querySelectorAll('dialog[open]').length",
          ) ??
          0;
      if (dialogCount != 1) {
        throw StateError('Expected one open native dialog, found $dialogCount');
      }
      if (dialogFocus != 'Confirmo dados sintéticos') {
        throw StateError(
          'Synthetic-data confirmation did not receive initial focus',
        );
      }
      if (dialogScreenshotPath != null) {
        await File(
          dialogScreenshotPath,
        ).writeAsBytes(await connection.captureScreenshot(), flush: true);
      }

      if (confirmSyntheticData) {
        await connection.clickButton('Confirmo dados sintéticos');
        await _waitFor(
          () async => !await connection.bodyContains('Coletar AutoPreview?'),
          description: 'dialog dismissal after confirmation',
        );
        await _waitFor(
          () async => await connection.bodyContains('Host conectado'),
          description: 'Host connection after collection',
          timeout: const Duration(minutes: 7),
        );
        await connection.clickButton('Evidence');
        await _waitFor(
          () async =>
              await connection.bodyContains('Coleta AutoPreview') &&
              (await connection.bodyContains('Concluída') ||
                  await connection.bodyContains('Concluída parcialmente') ||
                  await connection.bodyContains('Falhou')),
          description: 'terminal AutoPreview operation',
          timeout: const Duration(minutes: 7),
        );
      } else {
        await connection.pressEscape();
        await _waitFor(
          () async => !await connection.bodyContains('Coletar AutoPreview?'),
          description: 'dialog dismissal after Escape',
        );
        await _waitFor(
          () async => await connection.activeElementText() == actionLabel,
          description: 'dialog opener focus restoration',
        );
      }

      focusAfterDialog = await connection.activeElementText();
    }

    final screenshot = await connection.captureScreenshot();
    final inspection = const PngCaptureInspector().inspect(screenshot);
    if (inspection.width < 1000 || inspection.height < 700) {
      throw StateError('Chrome screenshot has an unexpected viewport');
    }
    if (screenshotPath != null) {
      await File(screenshotPath).writeAsBytes(screenshot, flush: true);
    }
    final accessibilityNodes = await connection.accessibilityNodeCount();
    if (accessibilityNodes < 20) {
      throw StateError('Accessibility tree is unexpectedly small');
    }
    final severeLogs = connection.severeLogs;
    if (severeLogs.isNotEmpty) {
      throw StateError('Chrome reported a severe error: ${severeLogs.first}');
    }

    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': 'passed',
        'mode': noPreview
            ? 'no-preview'
            : confirmSyntheticData
            ? 'confirmed'
            : 'cancelled',
        'dialogCount': dialogCount,
        'dialogInitialFocus': dialogFocus,
        'focusAfterDialog': focusAfterDialog,
        'semanticHtml': semantics,
        'keyboard': keyboard,
        'reflow200Percent': reflow,
        'reducedMotion': reducedMotion,
        'performance': performance,
        'mapInteraction': mapInteraction,
        'hostConnected': await connection.bodyContains('Host conectado'),
        'resourceRequests': connection.resourceUrls
            .where((value) => value.contains('/resources/'))
            .length,
        'accessibilityNodes': accessibilityNodes,
        'screenshotDigest': Digest.bytes(screenshot).value,
        'screenshotWidth': inspection.width,
        'screenshotHeight': inspection.height,
        'severeBrowserLogs': severeLogs.length,
      }),
    );
  } on Object catch (error) {
    final body = await connection.evaluate<String>(
      'document.body?.innerText?.slice(0, 2000) ?? ""',
    );
    final documentState = await connection.evaluate<Object?>('''
(() => ({
  readyState: document.readyState,
  location: location.href,
  scripts: Array.from(document.scripts).map((item) => ({
    src: item.src,
    inlineLength: item.textContent?.length ?? 0,
  })),
  resources: performance.getEntriesByType('resource')
    .map((item) => item.name)
    .slice(-80),
}))()
''');
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'status': 'failed',
        'error': '$error',
        'body': body,
        'document': documentState,
        'severeBrowserLogs': connection.severeLogs,
        'requestedUrls': connection.resourceUrls.toList(growable: false),
        'resourceRequests': connection.resourceUrls
            .where((value) => value.contains('/resources/'))
            .length,
      }),
    );
    if (screenshotPath != null) {
      await File(
        screenshotPath,
      ).writeAsBytes(await connection.captureScreenshot(), flush: true);
    }
    rethrow;
  } finally {
    await connection.close();
    await _closeTarget(debugOrigin, target.id);
  }
}

(int, int)? _parseViewport(String? source) {
  if (source == null) return null;
  final match = RegExp(r'^(\d{3,4})x(\d{3,4})$').firstMatch(source);
  if (match == null) {
    throw ArgumentError('--viewport must use <width>x<height>');
  }
  final width = int.parse(match.group(1)!);
  final height = int.parse(match.group(2)!);
  if (width < 320 || width > 3840 || height < 480 || height > 2160) {
    throw ArgumentError('--viewport must stay within 320x480 and 3840x2160');
  }
  return (width, height);
}

void _requireLoopbackHttp(Uri uri, String label) {
  if (uri.scheme != 'http' ||
      uri.host.isEmpty ||
      !const <String>{'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
    throw ArgumentError('$label must be loopback HTTP');
  }
}

Future<_ChromeTarget> _createTarget(Uri origin, Uri targetUri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final endpoint = origin.replace(
      path: '/json/new',
      query: targetUri.toString(),
    );
    final request = await client.openUrl('PUT', endpoint);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Chrome target creation failed: $body');
    }
    final value = jsonDecode(body);
    if (value is! Map<String, Object?> ||
        value['id'] is! String ||
        value['webSocketDebuggerUrl'] is! String) {
      throw const FormatException('Chrome target response is invalid');
    }
    return _ChromeTarget(
      id: value['id']! as String,
      webSocketUri: Uri.parse(value['webSocketDebuggerUrl']! as String),
    );
  } finally {
    client.close(force: true);
  }
}

Future<void> _closeTarget(Uri origin, String id) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(
      origin.replace(path: '/json/close/$id'),
    );
    await request.close();
  } on Object {
    // Browser process cleanup is the outer runner's responsibility.
  } finally {
    client.close(force: true);
  }
}

Future<void> _waitFor(
  Future<bool> Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await condition()) return;
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw TimeoutException(
    'Timed out waiting for $description'
    '${lastError == null ? '' : ': $lastError'}',
  );
}

final class _ChromeTarget {
  const _ChromeTarget({required this.id, required this.webSocketUri});

  final String id;
  final Uri webSocketUri;
}

final class _CdpConnection {
  _CdpConnection._(this._socket) {
    _subscription = _socket.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) {
        _failPending(error, stackTrace);
      },
      onDone: () {
        _failPending(
          StateError('Chrome DevTools connection closed'),
          StackTrace.current,
        );
      },
      cancelOnError: true,
    );
  }

  static Future<_CdpConnection> connect(Uri uri) async =>
      _CdpConnection._(await WebSocket.connect(uri.toString()));

  final WebSocket _socket;
  late final StreamSubscription<Object?> _subscription;
  final Map<int, Completer<Map<String, Object?>>> _pending =
      <int, Completer<Map<String, Object?>>>{};
  final List<String> severeLogs = <String>[];
  final Set<String> resourceUrls = <String>{};
  int _nextId = 1;

  Future<Map<String, Object?>> send(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode(<String, Object?>{
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      _pending.remove(id);
    }
  }

  Future<T?> evaluate<T>(String expression) async {
    final result = await send('Runtime.evaluate', <String, Object?>{
      'expression': expression,
      'returnByValue': true,
      'awaitPromise': true,
    });
    final exception = result['exceptionDetails'];
    if (exception != null) {
      throw StateError('Chrome evaluation failed: $exception');
    }
    final remote = _object(result['result'], 'Runtime.evaluate.result');
    final value = remote['value'];
    if (value == null) return null;
    return value as T;
  }

  Future<bool> bodyContains(String text) async =>
      await evaluate<bool>(
        'document.body?.innerText.includes(${jsonEncode(text)}) ?? false',
      ) ??
      false;

  bool requestedUrlContains(String value) =>
      resourceUrls.any((url) => url.contains(value));

  bool requestedUrlStartsWith(String value) =>
      resourceUrls.any((url) => url.startsWith(value));

  Future<void> clickButton(String label) async {
    final clicked = await evaluate<bool>('''
(() => {
  const label = ${jsonEncode(label)};
  const button = Array.from(document.querySelectorAll('button'))
    .find((item) => item.textContent.trim() === label);
  if (!button || button.disabled) return false;
  button.focus();
  button.click();
  return true;
})()
''');
    if (clicked != true) throw StateError('Button not available: $label');
  }

  Future<void> clickLink(String label) async {
    final clicked = await evaluate<bool>('''
(() => {
  const label = ${jsonEncode(label)};
  const link = Array.from(document.querySelectorAll('a[href]'))
    .find((item) => item.textContent.trim() === label);
  if (!link) return false;
  link.focus();
  link.click();
  return true;
})()
''');
    if (clicked != true) throw StateError('Link not available: $label');
  }

  Future<void> selectValue(String id, String value) async {
    final selected = await evaluate<bool>('''
(() => {
  const select = document.getElementById(${jsonEncode(id)});
  const value = ${jsonEncode(value)};
  if (!(select instanceof HTMLSelectElement) ||
      !Array.from(select.options).some((option) => option.value === value)) {
    return false;
  }
  select.value = value;
  select.dispatchEvent(new Event('change', {bubbles: true}));
  return true;
})()
''');
    if (selected != true) {
      throw StateError('Select value not available: $id=$value');
    }
  }

  Future<String?> activeElementText() async =>
      evaluate<String?>('document.activeElement?.textContent?.trim() ?? null');

  Future<void> pressEscape() async {
    await send('Input.dispatchKeyEvent', const <String, Object?>{
      'type': 'keyDown',
      'key': 'Escape',
      'code': 'Escape',
      'windowsVirtualKeyCode': 27,
      'nativeVirtualKeyCode': 27,
    });
    await send('Input.dispatchKeyEvent', const <String, Object?>{
      'type': 'keyUp',
      'key': 'Escape',
      'code': 'Escape',
      'windowsVirtualKeyCode': 27,
      'nativeVirtualKeyCode': 27,
    });
  }

  Future<Map<String, Object?>> auditSemanticHtml() async {
    final value = await evaluate<Object?>(r'''
(() => {
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
  const undersizedTargets = focusables.map((element) => {
    const rect = element.getBoundingClientRect();
    return {
      name: accessibleName(element),
      tag: element.tagName,
      width: rect.width,
      height: rect.height,
    };
  }).filter((item) => item.width > 0 && item.height > 0 && Math.min(item.width, item.height) < 47.5);
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
    undersizedTargets,
  };
})()
''');
    final result = _object(value, 'SemanticHtmlAudit');
    if (result['hasMain'] != true ||
        result['hasPrimaryNavigation'] != true ||
        result['hasPageHeading'] != true ||
        result['hasLiveRegion'] != true ||
        result['flutterElementCount'] != 0 ||
        (result['focusableCount'] as num? ?? 0) < 8 ||
        result['unnamedFocusableCount'] != 0 ||
        (result['minimumInteractiveSize'] as num? ?? 0) < 47.5) {
      throw StateError('Studio semantic HTML audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditKeyboardNavigation() async {
    await evaluate<Object?>(
      'document.activeElement?.blur(); document.body.scrollTop = 0; true',
    );
    final visited = <String>[];
    for (var index = 0; index < 8; index += 1) {
      await send('Input.dispatchKeyEvent', const <String, Object?>{
        'type': 'keyDown',
        'key': 'Tab',
        'code': 'Tab',
        'windowsVirtualKeyCode': 9,
        'nativeVirtualKeyCode': 9,
      });
      await send('Input.dispatchKeyEvent', const <String, Object?>{
        'type': 'keyUp',
        'key': 'Tab',
        'code': 'Tab',
        'windowsVirtualKeyCode': 9,
        'nativeVirtualKeyCode': 9,
      });
      final current = await evaluate<String>(r'''
(() => {
  const element = document.activeElement;
  return element
    ? `${element.tagName}:${element.getAttribute('aria-label') || element.textContent || element.id}`.trim()
    : '';
})()
''');
      if (current != null && current.isNotEmpty) visited.add(current);
    }
    if (visited.toSet().length < 5) {
      throw StateError('Keyboard traversal did not reach enough controls');
    }
    return <String, Object?>{
      'tabStopsVisited': visited.length,
      'uniqueTabStops': visited.toSet().length,
    };
  }

  Future<Map<String, Object?>> auditReflowAtTwoHundredPercent() async {
    await send('Emulation.setDeviceMetricsOverride', const <String, Object?>{
      'width': 360,
      'height': 800,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    final value = await evaluate<Object?>(r'''
(() => {
  document.documentElement.style.fontSize = '200%';
  const root = document.documentElement;
  const body = document.body;
  const overflowingElements = Array.from(document.querySelectorAll('body *'))
    .map((element) => {
      const rect = element.getBoundingClientRect();
      return {
        tag: element.tagName,
        classes: element.className,
        width: rect.width,
        right: rect.right,
        scrollWidth: element.scrollWidth,
        clientWidth: element.clientWidth,
      };
    })
    .filter((item) => item.right > window.innerWidth + 1 || item.width > window.innerWidth + 1)
    .sort((left, right) => right.right - left.right)
    .slice(0, 12);
  const layoutOverflowSources = Array.from(document.querySelectorAll('body *'))
    .filter((element) => !element.closest('.journey-map-viewport, .scenario-outline-list'))
    .map((element) => {
      const rect = element.getBoundingClientRect();
      return {
        tag: element.tagName,
        classes: element.className,
        text: element.textContent?.trim().slice(0, 80) ?? '',
        width: rect.width,
        right: rect.right,
        overflowX: getComputedStyle(element).overflowX,
      };
    })
    .filter((item) => item.right > window.innerWidth + 1 || item.width > window.innerWidth + 1)
    .sort((left, right) => right.right - left.right)
    .slice(0, 12);
  return {
    viewportWidth: window.innerWidth,
    rootScrollWidth: root.scrollWidth,
    bodyScrollWidth: body.scrollWidth,
    horizontalDocumentOverflow: Math.max(root.scrollWidth, body.scrollWidth) > window.innerWidth + 1,
    mainVisible: document.querySelector('main')?.getBoundingClientRect().width > 0,
    headingVisible: document.querySelector('main h1')?.getBoundingClientRect().height > 0,
    overflowingElements,
    layoutOverflowSources,
  };
})()
''');
    final result = _object(value, 'ReflowAudit');
    await evaluate<Object?>(
      "document.documentElement.style.removeProperty('font-size'); true",
    );
    await send('Emulation.setDeviceMetricsOverride', const <String, Object?>{
      'width': 1440,
      'height': 1000,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    if (result['horizontalDocumentOverflow'] != false ||
        result['mainVisible'] != true ||
        result['headingVisible'] != true) {
      throw StateError('Studio 200% text reflow audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditReducedMotion() async {
    await send('Emulation.setEmulatedMedia', const <String, Object?>{
      'features': <Object?>[
        <String, Object?>{'name': 'prefers-reduced-motion', 'value': 'reduce'},
      ],
    });
    final value = await evaluate<Object?>(r'''
(() => {
  const control = document.querySelector('button');
  const style = control ? getComputedStyle(control) : null;
  return {
    queryMatches: matchMedia('(prefers-reduced-motion: reduce)').matches,
    transitionDuration: style?.transitionDuration ?? '',
    animationDuration: style?.animationDuration ?? '',
    transitionSeconds: Number.parseFloat(style?.transitionDuration ?? '1'),
  };
})()
''');
    await send('Emulation.setEmulatedMedia');
    final result = _object(value, 'ReducedMotionAudit');
    if (result['queryMatches'] != true ||
        (result['transitionSeconds'] as num? ?? 1) > 0.001) {
      throw StateError('Studio reduced-motion audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> performanceMetrics() async {
    final value = await evaluate<Object?>(r'''
(() => {
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
})()
''');
    final result = _object(value, 'PerformanceMetrics');
    final load = result['loadEventMs'] as num? ?? double.infinity;
    if (load <= 0 || load > 5000) {
      throw StateError('Studio load exceeded the local 5 s budget: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditMapInteractionPerformance() async {
    final value = await evaluate<Object?>(r'''
(async () => {
  const labels = ['Ampliar', 'Reduzir'];
  const controls = labels.map((label) => Array.from(
    document.querySelectorAll('button')
  ).find((item) => item.textContent.trim() === label));
  if (controls.some((button) => !button)) {
    return {available: false, samples: 0};
  }
  const samples = [];
  for (let index = 0; index < 20; index += 1) {
    const label = labels[index % labels.length];
    const button = Array.from(document.querySelectorAll('button'))
      .find((item) => item.textContent.trim() === label);
    if (!button || button.disabled) {
      throw new Error(`Map interaction unavailable: ${label}`);
    }
    const started = performance.now();
    button.click();
    await new Promise((resolve) => requestAnimationFrame(resolve));
    await new Promise((resolve) => requestAnimationFrame(resolve));
    samples.push(performance.now() - started);
  }
  const ordered = [...samples].sort((left, right) => left - right);
  const percentile = (value) => ordered[Math.min(
    ordered.length - 1,
    Math.ceil(value * ordered.length) - 1,
  )];
  return {
    available: true,
    samples: samples.length,
    medianMs: percentile(0.5),
    p95Ms: percentile(0.95),
    maxMs: ordered[ordered.length - 1],
  };
})()
''');
    final result = _object(value, 'MapInteractionPerformance');
    if (result['available'] == false) return result;
    final p95 = result['p95Ms'] as num? ?? double.infinity;
    if (p95 <= 0 || p95 > 100) {
      throw StateError(
        'Journey Map interaction exceeded the local 100 ms p95 budget: '
        '$result',
      );
    }
    return result;
  }

  Future<List<int>> captureScreenshot() async {
    final result = await send('Page.captureScreenshot', const <String, Object?>{
      'format': 'png',
      'fromSurface': true,
      'captureBeyondViewport': false,
    });
    final data = result['data'];
    if (data is! String || data.length > 32 * 1024 * 1024) {
      throw const FormatException('Chrome screenshot response is invalid');
    }
    return base64Decode(data);
  }

  Future<int> accessibilityNodeCount() async {
    final result = await send('Accessibility.getFullAXTree');
    final nodes = result['nodes'];
    if (nodes is! List<Object?>) {
      throw const FormatException('Chrome accessibility tree is invalid');
    }
    return nodes.length;
  }

  void _onMessage(Object? raw) {
    if (raw is! String || raw.length > 16 * 1024 * 1024) {
      _failPending(
        const FormatException('Chrome returned an invalid CDP frame'),
        StackTrace.current,
      );
      return;
    }
    final value = jsonDecode(raw);
    if (value is! Map<String, Object?>) return;
    final id = value['id'];
    if (id is int) {
      final completer = _pending[id];
      if (completer == null || completer.isCompleted) return;
      if (value['error'] != null) {
        completer.completeError(
          StateError('CDP command failed: ${value['error']}'),
        );
      } else {
        completer.complete(_object(value['result'], 'CDP result'));
      }
      return;
    }
    final method = value['method'];
    final params = value['params'];
    if (method == 'Network.requestWillBeSent' &&
        params is Map<String, Object?> &&
        params['request'] is Map<String, Object?>) {
      final url = (params['request']! as Map<String, Object?>)['url'];
      if (url is String) resourceUrls.add(url);
    }
    if (method == 'Log.entryAdded' && params is Map<String, Object?>) {
      final entry = params['entry'];
      if (entry is Map<String, Object?> && entry['level'] == 'error') {
        severeLogs.add('${entry['text']}');
      }
    }
    if (method == 'Runtime.exceptionThrown' && params is Map<String, Object?>) {
      severeLogs.add('${params['exceptionDetails']}');
    }
  }

  void _failPending(Object error, StackTrace stackTrace) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    _pending.clear();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close(WebSocketStatus.normalClosure, 'Probe complete');
  }

  static Map<String, Object?> _object(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    return value;
  }
}
