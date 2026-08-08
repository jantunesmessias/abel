import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage: dart run tools/probes/studio_jaspr_cdp_probe.dart '
      '<chrome-debug-origin> <studio-url> '
      '[--confirm-synthetic-data|--no-preview|--capture-only|--watch-reconnect|--inventory-audit|--scenario-lab-audit|--scenario-quality-reload-audit=<json>|--scenario-currentness-audit=<json>|--showcase-flow=<dir>] '
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
  final inventoryAudit = arguments.contains('--inventory-audit');
  final scenarioLabAudit = arguments.contains('--scenario-lab-audit');
  final scenarioQualityReloadSources = arguments
      .where((item) => item.startsWith('--scenario-quality-reload-audit='))
      .map((item) => item.substring('--scenario-quality-reload-audit='.length))
      .toList(growable: false);
  if (scenarioQualityReloadSources.length > 1) {
    throw ArgumentError('--scenario-quality-reload-audit may be provided once');
  }
  final scenarioQualityReloadExpectation =
      scenarioQualityReloadSources.firstOrNull == null
      ? null
      : _ScenarioQualityReloadExpectation.decode(
          scenarioQualityReloadSources.single,
        );
  final scenarioQualityReloadAudit = scenarioQualityReloadExpectation != null;
  final scenarioCurrentnessSources = arguments
      .where((item) => item.startsWith('--scenario-currentness-audit='))
      .map((item) => item.substring('--scenario-currentness-audit='.length))
      .toList(growable: false);
  if (scenarioCurrentnessSources.length > 1) {
    throw ArgumentError('--scenario-currentness-audit may be provided once');
  }
  final scenarioCurrentnessExpectation =
      scenarioCurrentnessSources.firstOrNull == null
      ? null
      : _ScenarioCurrentnessExpectation.decode(
          scenarioCurrentnessSources.single,
        );
  final scenarioCurrentnessAudit = scenarioCurrentnessExpectation != null;
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
        inventoryAudit,
        scenarioLabAudit,
        scenarioQualityReloadAudit,
        scenarioCurrentnessAudit,
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
    if (scenarioQualityReloadExpectation case final expectation?) {
      final result = await _auditScenarioQualityReload(connection, expectation);
      stdout.writeln(jsonEncode(result));
      return;
    }
    if (scenarioCurrentnessExpectation case final expectation?) {
      final result = await _auditScenarioCurrentness(connection, expectation);
      stdout.writeln(jsonEncode(result));
      return;
    }
    if (scenarioLabAudit) {
      final result = await _auditScenarioLab(
        connection,
        qualityScreenshotPath: screenshotPath,
        dialogScreenshotPath: dialogScreenshotPath,
      );
      stdout.writeln(jsonEncode(result));
      return;
    }
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
    if (inventoryAudit) {
      await _waitFor(
        () async =>
            await connection.evaluate<bool>(r'''
(() => location.pathname === '/inventory' && location.search === '')()
''') ??
            false,
        description: 'canonical Inventory index route',
      );
      await _waitFor(
        () async =>
            await connection.evaluate<bool>(r'''
(() => {
  const boundary = document.querySelector(
    '.inventory-facet-boundary[data-inventory-facets="ready"]'
  );
  return Boolean(boundary?.dataset.inventoryFacetDigest) &&
    document.querySelectorAll('.inventory-scenario-card').length === 8;
})()
''') ??
            false,
        description: 'canonical Scenario Inventory and facet manifest',
      );
      final inventoryIndex = await connection.auditInventoryIndex();

      await connection.selectValue(
        'inventory-index-state',
        'dashboard.unavailable',
      );
      await _waitFor(
        () async =>
            await connection.evaluate<bool>(r'''
(() => {
  const query = new URLSearchParams(location.search);
  const cards = document.querySelectorAll('.inventory-scenario-card');
  return location.pathname === '/inventory' &&
    query.size === 1 &&
    query.get('state') === 'dashboard.unavailable' &&
    cards.length === 1 &&
    cards[0]?.dataset.inventoryScenarioId === 'dashboard-unavailable';
})()
''') ??
            false,
        description: 'canonical dashboard.unavailable URL filter',
      );
      final inventoryFilter = await connection.auditInventoryStateFilter();

      await connection.clickButton('Limpar filtros');
      await _waitFor(
        () async =>
            await connection.evaluate<bool>(r'''
(() => location.pathname === '/inventory' && location.search === '' &&
  document.querySelectorAll('.inventory-scenario-card').length === 8)()
''') ??
            false,
        description: 'Inventory filter reset',
      );
      final inventoryReset = await connection.auditInventoryIndex();

      await connection.clickLinkPath('/inventory/delivery-inventory');
      await _waitFor(
        () async =>
            await connection.evaluate<bool>(r'''
Boolean(document.querySelector(
  '.inventory-map-stage.is-spatial[data-projection-id="delivery-inventory"]'
))
''') ??
            false,
        description: 'authored delivery-inventory spatial projection',
      );
      await connection.clickLinkPath(
        '/inventory/delivery-inventory/nodes/inventory-dashboard-ready',
      );
      await _waitFor(
        () async =>
            await connection.evaluate<bool>(r'''
(() => location.pathname ===
  '/inventory/delivery-inventory/nodes/inventory-dashboard-ready' &&
  document.querySelector(
    '.inventory-map-node[data-node-instance-id="inventory-dashboard-ready"] '
      + '.inventory-card.is-selected a[aria-current="page"]'
  ) !== null)()
''') ??
            false,
        description: 'Inventory NodeInstance deep link and selection',
      );
      final spatialInventory = await connection.auditSpatialInventoryMap();
      final semantics = await connection.auditSemanticHtml();
      final keyboard = await connection.auditKeyboardNavigation();
      final performance = await connection.performanceMetrics();
      final reducedMotion = await connection.auditReducedMotion();
      final reflow = await connection.auditReflowAtTwoHundredPercent();

      await connection.evaluate<Object?>(r'''
(() => {
  document.querySelector(
    '.inventory-map-node[data-node-instance-id="inventory-dashboard-ready"]'
  )?.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
  return true;
})()
''');
      await connection.evaluate<Object?>(r'''
new Promise((resolve) => requestAnimationFrame(
  () => requestAnimationFrame(resolve)
))
''');
      final screenshotSubjectVisible =
          await connection.evaluate<bool>(r'''
(() => {
  const node = document.querySelector(
    '.inventory-map-node[data-node-instance-id="inventory-dashboard-ready"]'
  );
  if (!node) return false;
  const rect = node.getBoundingClientRect();
  return rect.width > 0 && rect.height > 0 && rect.bottom > 0 &&
    rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
})()
''') ??
          false;
      if (!screenshotSubjectVisible) {
        throw StateError(
          'Inventory screenshot subject is outside the viewport',
        );
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
      if (connection.severeLogs.isNotEmpty) {
        throw StateError(
          'Chrome reported a severe error: ${connection.severeLogs.first}',
        );
      }
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'status': 'passed',
          'mode': 'inventory-audit',
          'inventoryIndex': inventoryIndex,
          'inventoryFilter': inventoryFilter,
          'inventoryReset': inventoryReset,
          'spatialInventory': spatialInventory,
          'semanticHtml': semantics,
          'keyboard': keyboard,
          'reflow200Percent': reflow,
          'reducedMotion': reducedMotion,
          'performance': performance,
          'hostConnected': await connection.bodyContains('Host conectado'),
          'resourceRequests': connection.resourceUrls
              .where((value) => value.contains('/resources/'))
              .length,
          'accessibilityNodes': accessibilityNodes,
          'screenshotDigest': Digest.bytes(screenshot).value,
          'screenshotWidth': inspection.width,
          'screenshotHeight': inspection.height,
          'screenshotSubjectVisible': screenshotSubjectVisible,
          'severeBrowserLogs': connection.severeLogs.length,
        }),
      );
      return;
    }
    await _waitFor(
      () async =>
          await connection.evaluate<bool>(r'''
Boolean(document.querySelector(
  '.journey-map-stage.is-spatial[data-projection-id="delivery-journey"]'
))
''') ??
          false,
      description: 'authored delivery-journey spatial projection',
    );
    final spatialMap = await connection.auditSpatialJourneyMap();
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
        'spatialMap': spatialMap,
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
    if (scenarioLabAudit ||
        scenarioQualityReloadAudit ||
        scenarioCurrentnessAudit) {
      final blocked = switch (error) {
        final _ScenarioLabAuditBlocked value => <String, Object?>{
          'phase': value.phase,
          'details': value.details,
        },
        final _ProbeTimeout value => <String, Object?>{
          'phase': 'timeout',
          'details': <String, Object?>{'description': value.description},
        },
        _ => <String, Object?>{
          'phase': 'probe',
          'errorType': error.runtimeType.toString(),
        },
      };
      stderr.writeln(
        jsonEncode(<String, Object?>{
          'status': 'blocked',
          'mode': scenarioLabAudit
              ? 'scenario-lab-audit'
              : scenarioCurrentnessAudit
              ? 'scenario-currentness-audit'
              : 'scenario-quality-reload-audit',
          ...blocked,
          'relayPorts': connection.scenarioLabKnownPorts(),
          'severeBrowserLogs': connection.severeLogs.length,
          'resourceRequests': connection.resourceUrls
              .where((value) => value.contains('/resources/'))
              .length,
        }),
      );
      exitCode = 1;
      return;
    }
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

const _scenarioLabPath =
    '/lab/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab';
const _scenarioQualityPath =
    '/quality/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab';
const _scenarioLabGatewayPresetId = 'showcase-offline';
const _scenarioLabExecutionTargetId = 'sample-lab-web';
const _scenarioLabLaunchProfileId = 'sample-lab-web';
const _scenarioQualityRpcMethods = <String>[
  'quality.describe',
  'quality.open',
  'quality.decision.grant',
  'quality.decision.append',
  'quality.decision.get',
];

Future<Map<String, Object?>?> _captureScenarioVisual(
  _CdpConnection connection,
  String? outputPath, {
  required String phase,
}) async {
  if (outputPath == null) return null;
  await connection.waitForDoubleAnimationFrame();
  final bytes = await connection.captureScreenshot();
  final inspection = const PngCaptureInspector().inspect(bytes);
  if (inspection.width < 1000 || inspection.height < 700) {
    throw _ScenarioLabAuditBlocked(phase, <String, Object?>{
      'width': inspection.width,
      'height': inspection.height,
    });
  }

  final output = File(outputPath);
  var created = false;
  var complete = false;
  try {
    await output.create(exclusive: true);
    created = true;
    await output.writeAsBytes(bytes, flush: true);
    complete = true;
  } finally {
    if (created && !complete && await output.exists()) {
      await output.delete();
    }
  }
  return <String, Object?>{
    'digest': Digest.bytes(bytes).value,
    'width': inspection.width,
    'height': inspection.height,
  };
}

Future<Map<String, Object?>> _auditScenarioLab(
  _CdpConnection connection, {
  required String? qualityScreenshotPath,
  required String? dialogScreenshotPath,
}) async {
  await connection.installScenarioLabControlObserver();
  final preflight = await connection.scenarioLabSurface();
  if (preflight['path'] != _scenarioLabPath ||
      preflight['search'] != '' ||
      preflight['routeState'] != 'ready' ||
      preflight['runCapability'] != 'available' ||
      preflight['relayCapability'] != 'available' ||
      preflight['actionsState'] != 'ready' ||
      preflight['startButtonCount'] != 1 ||
      preflight['startEnabled'] != true ||
      preflight['iframeCount'] != 0 ||
      preflight['relayCount'] != 0) {
    throw _ScenarioLabAuditBlocked('preflight', preflight);
  }

  final semanticHtml = await connection.auditSemanticHtml();
  final keyboard = await connection.auditKeyboardNavigation();
  connection.beginScenarioLabRunTransportAudit();
  await connection.clickScenarioLabRunAction('start');
  await _waitFor(
    () async {
      final surface = await connection.scenarioLabSurface();
      final selectedRunId = surface['selectedRunId'];
      return (selectedRunId is String &&
              surface['queryRunId'] == selectedRunId) ||
          const <String>{
            'failed',
            'unavailable',
            'closed',
          }.contains(surface['lifecycle']);
    },
    description: 'Scenario Lab Start outcome',
    timeout: const Duration(seconds: 45),
  );
  final started = await connection.scenarioLabSurface();
  final encodedRunId = started['selectedRunId'];
  if (encodedRunId is! String) {
    throw _ScenarioLabAuditBlocked('start', <String, Object?>{
      'surface': started,
      'rpc': connection.scenarioLabRpcSummary(),
    });
  }
  final runId = ScenarioLabRunId(encodedRunId);
  if (started['path'] != _scenarioLabPath ||
      started['queryRunId'] != runId.value ||
      started['runPanelId'] != runId.value ||
      started['runPanelState'] == 'notStarted') {
    throw _ScenarioLabAuditBlocked('run-url', started);
  }

  Map<String, Object?>? mountedRelay;
  var lastRelaySurface = started;
  var lastRelay = await connection.scenarioLabRelay(runId);
  var lastMountProof = connection.scenarioLabRelayMountProof(
    runId: runId,
    relay: lastRelay,
  );
  try {
    await _waitFor(
      () async {
        final surface = await connection.scenarioLabSurface();
        final candidate = await connection.scenarioLabRelay(runId);
        final mountProof = connection.scenarioLabRelayMountProof(
          runId: runId,
          relay: candidate,
        );
        lastRelaySurface = surface;
        lastRelay = candidate;
        lastMountProof = mountProof;
        if (surface['iframeCount'] == 1 &&
            mountProof['mountAuthorized'] == true) {
          mountedRelay = candidate;
          return true;
        }
        return surface['lifecycle'] == 'terminal' ||
            surface['relayState'] == 'failed';
      },
      description: 'single Scenario Lab relay iframe',
      timeout: const Duration(minutes: 2),
    );
  } on _ProbeTimeout {
    throw _ScenarioLabAuditBlocked('single-relay-timeout', <String, Object?>{
      'surface': _scenarioLabSurfaceSummary(lastRelaySurface),
      'relay': _scenarioLabRelaySummary(lastRelay),
      'mount': lastMountProof,
      'frameNavigation': connection.scenarioLabFrameNavigationDiagnostics(
        runId,
      ),
      'relayV2': connection.scenarioLabRelayV2Diagnostics(runId),
      'rpc': connection.scenarioLabRpcSummary(),
    });
  }
  final relay = mountedRelay ?? await connection.scenarioLabRelay(runId);
  final mountProof = connection.scenarioLabRelayMountProof(
    runId: runId,
    relay: relay,
  );
  if (relay['relayCount'] != 1 ||
      relay['iframeCount'] != 1 ||
      relay['runId'] != runId.value ||
      relay['aboutBlank'] != true ||
      relay['gatewayBindingDeclared'] != true ||
      relay['gatewayBound'] != true ||
      mountProof['mountAuthorized'] != true) {
    throw _ScenarioLabAuditBlocked('relay', <String, Object?>{
      'relay': _scenarioLabRelaySummary(relay),
      'mount': mountProof,
    });
  }
  final relayAtMount = <String, Object?>{
    ..._scenarioLabRelaySummary(relay),
    ...mountProof,
  };

  final terminal = await _driveScenarioLabToTerminal(connection, runId);
  final observationJson = connection.latestTerminalRunObservation(runId);
  if (observationJson == null) {
    throw _ScenarioLabAuditBlocked('terminal-rpc', <String, Object?>{
      'surface': terminal,
      'rpc': connection.scenarioLabRpcSummary(),
    });
  }
  final observation = ScenarioLabRunObservation.fromJson(observationJson);
  final result = observation.result;
  if (terminal['runPanelState'] != 'succeeded' ||
      terminal['iframeCount'] != 0 ||
      terminal['relayCount'] != 0) {
    throw _ScenarioLabAuditBlocked('terminal-ui', <String, Object?>{
      'surface': terminal,
      'observation': _scenarioLabObservationSummary(observation),
      'targetControl': await connection.scenarioLabControlProof(),
      'relayAtMount': relayAtMount,
      'rpc': connection.scenarioLabRpcSummary(),
    });
  }
  if (observation.runId != runId ||
      observation.disposition != ScenarioLabRunDisposition.terminal ||
      result == null ||
      result.finalSnapshot.state != ScenarioLabRunState.succeeded ||
      result.finalSnapshot.cleanup.state != ScenarioLabCleanupState.succeeded ||
      result.finalSnapshot.steps.any(
        (step) => step.state != ScenarioLabStepState.succeeded,
      )) {
    throw _ScenarioLabAuditBlocked(
      'terminal-contract',
      _scenarioLabObservationSummary(observation),
    );
  }
  final finalSnapshot = result.finalSnapshot;
  final gatewayProof = connection.scenarioLabGatewayProof(
    runId: runId,
    snapshot: finalSnapshot,
    relay: relay,
  );
  if (!_scenarioLabGatewayProofIsValid(gatewayProof)) {
    throw _ScenarioLabAuditBlocked('gateway-binding', gatewayProof);
  }
  final relaySummary = <String, Object?>{...relayAtMount, ...gatewayProof};
  final evidence = finalSnapshot.requiredEvidence.singleWhere(
    (item) => item.requiredEvidenceId.value == 'dashboard-ready-visual',
  );
  final control = finalSnapshot.controls.singleWhere(
    (item) => item.controlId.value == 'dashboard-ready-highlight-enabled',
  );
  final comparison = finalSnapshot.comparisons.singleWhere(
    (item) => item.bindingId.value == 'dashboard-ready-baseline-candidate',
  );
  if (evidence.providerId.value != 'capture.app-adapter' ||
      evidence.fidelity != RuntimeFidelity.simulated ||
      evidence.state != RequiredEvidenceResultState.collected ||
      evidence.freshness != EvidenceFreshness.fresh ||
      evidence.evidenceDigest == null ||
      evidence.artifacts.length != 1 ||
      control.source != ScenarioControlResultSource.read ||
      control.value is! BooleanScenarioControlValue ||
      (control.value as BooleanScenarioControlValue).value ||
      comparison.resultKind != ScenarioComparisonResultKind.visual ||
      comparison.verificationState != VerificationState.passed ||
      result.verificationState != VerificationState.passed) {
    throw _ScenarioLabAuditBlocked(
      'evidence-comparison',
      _scenarioLabObservationSummary(observation),
    );
  }

  final targetControl = await connection.scenarioLabControlProof();
  if (targetControl['semanticStates'] is! List<Object?> ||
      !(targetControl['semanticStates']! as List<Object?>).contains(
        'disabled',
      ) ||
      !(targetControl['semanticStates']! as List<Object?>).contains(
        'enabled',
      ) ||
      targetControl['disabledScreenshotDigest'] == null ||
      targetControl['enabledScreenshotDigest'] == null ||
      targetControl['disabledScreenshotDigest'] ==
          targetControl['enabledScreenshotDigest'] ||
      (targetControl['captureErrors'] as List<Object?>? ?? const <Object?>[])
          .isNotEmpty) {
    throw _ScenarioLabAuditBlocked('target-control', targetControl);
  }

  await connection.clickSelector(
    'a[data-scenario-cross-surface="lab-to-quality"]',
  );
  await _waitFor(
    () async => _scenarioQualityReviewReady(
      await connection.scenarioQualitySurface(),
      runId: runId,
      decisionCount: 0,
      humanDecision: HumanDecisionState.unreviewed,
      enabledAction: 'approve',
    ),
    description: 'exact Quality review resources and provenance',
    timeout: const Duration(minutes: 2),
  );
  final initialQuality = await connection.scenarioQualitySurface();
  _requireScenarioQualityAutomatedSurface(
    initialQuality,
    runId: runId,
    result: result,
    phase: 'quality-initial',
  );
  _requireScenarioQualityRpcCounts(
    connection,
    phase: 'quality-initial-rpc',
    describe: 1,
    open: 1,
    grant: 0,
    append: 0,
    get: 0,
  );

  final initialDescriptions = connection.scenarioQualityDescribeResults;
  final initialReviewSets = connection.scenarioQualityReviewSets;
  if (initialDescriptions.length != 1 || initialReviewSets.length != 1) {
    throw _ScenarioLabAuditBlocked(
      'quality-initial-contract',
      <String, Object?>{
        'descriptionCount': initialDescriptions.length,
        'reviewSetCount': initialReviewSets.length,
        'rpc': connection.scenarioQualityRpcSummary(),
      },
    );
  }
  final initialDescription = initialDescriptions.single.description;
  initialDescription.quality.validateAgainstResult(result);
  final initialAutomated = _scenarioQualityAutomatedSummary(
    initialDescription.quality,
  );
  if (initialDescription.runId != runId ||
      initialDescription.runResultDigest != result.digest ||
      initialDescription.availability !=
          ScenarioQualityReviewAvailability.available ||
      initialDescription.decisionCount != 0 ||
      initialDescription.headDecisionDigest != null ||
      initialDescription.quality.humanDecision.state !=
          HumanDecisionState.unreviewed ||
      initialDescription.quality.requiredEvidence.length != 1 ||
      initialDescription.quality.requiredEvidence.single.resultDigest !=
          evidence.digest ||
      initialDescription.quality.requiredEvidence.single.verificationState !=
          VerificationState.passed ||
      initialDescription.quality.comparisonResultDigests.length != 1 ||
      initialDescription.quality.comparisonResultDigests.single !=
          comparison.digest ||
      !_scenarioQualityResourceSurfaceMatchesReviewSet(
        initialQuality,
        initialReviewSets.single,
      )) {
    throw _ScenarioLabAuditBlocked(
      'quality-initial-binding',
      _scenarioQualityDescriptionSummary(initialDescription),
    );
  }

  final approveCountsBeforeConfirmation = connection
      .scenarioQualityRequestCounts();
  await connection.clickScenarioQualityAction('approve');
  await _waitFor(
    () async => _scenarioQualityConfirmationReady(
      await connection.scenarioQualitySurface(),
      runId,
    ),
    description: 'approve confirmation before Host authority',
  );
  final approveConfirmation = await connection.scenarioQualitySurface();
  final approveCountsAfterConfirmation = connection
      .scenarioQualityRequestCounts();
  if (!_sameJson(
    approveCountsBeforeConfirmation,
    approveCountsAfterConfirmation,
  )) {
    throw _ScenarioLabAuditBlocked(
      'approve-confirmation-fence',
      <String, Object?>{
        'before': approveCountsBeforeConfirmation,
        'after': approveCountsAfterConfirmation,
        'surface': approveConfirmation,
      },
    );
  }
  await connection.pressEscape();
  await _waitFor(() async {
    final surface = await connection.scenarioQualitySurface();
    return _scenarioQualityReviewReady(
          surface,
          runId: runId,
          decisionCount: 0,
          humanDecision: HumanDecisionState.unreviewed,
          enabledAction: 'approve',
        ) &&
        surface['focusedAction'] == 'approve';
  }, description: 'Escape dismissal and approve opener focus restoration');
  final approveCountsAfterEscape = connection.scenarioQualityRequestCounts();
  if (!_sameJson(approveCountsBeforeConfirmation, approveCountsAfterEscape)) {
    throw _ScenarioLabAuditBlocked('approve-escape-fence', <String, Object?>{
      'before': approveCountsBeforeConfirmation,
      'after': approveCountsAfterEscape,
    });
  }
  await connection.clickScenarioQualityAction('approve');
  await _waitFor(
    () async => _scenarioQualityConfirmationReady(
      await connection.scenarioQualitySurface(),
      runId,
    ),
    description: 'reopened approve confirmation',
  );
  final approveReopenedConfirmation = await connection.scenarioQualitySurface();
  if (approveReopenedConfirmation['focusedAction'] !=
          approveConfirmation['focusedAction'] ||
      !_sameJson(
        approveCountsBeforeConfirmation,
        connection.scenarioQualityRequestCounts(),
      )) {
    throw _ScenarioLabAuditBlocked(
      'approve-reopen-fence',
      approveReopenedConfirmation,
    );
  }
  final dialogCapture = await _captureScenarioVisual(
    connection,
    dialogScreenshotPath,
    phase: 'quality-decision-dialog-capture',
  );
  await connection.clickScenarioQualityAction('confirm');
  await _waitFor(
    () async => _scenarioQualityReviewReady(
      await connection.scenarioQualitySurface(),
      runId: runId,
      decisionCount: 1,
      humanDecision: HumanDecisionState.approved,
      enabledAction: 'supersede-rejected',
    ),
    description: 'approved Quality decision and exact history',
    timeout: const Duration(minutes: 2),
  );
  final approvedQuality = await connection.scenarioQualitySurface();
  _requireScenarioQualityAutomatedSurface(
    approvedQuality,
    runId: runId,
    result: result,
    phase: 'quality-approved',
  );
  _requireScenarioQualityRpcCounts(
    connection,
    phase: 'quality-approved-rpc',
    describe: 2,
    open: 2,
    grant: 1,
    append: 1,
    get: 1,
  );
  if (!_sameJson(
    _scenarioQualityAutomatedSurface(initialQuality),
    _scenarioQualityAutomatedSurface(approvedQuality),
  )) {
    throw _ScenarioLabAuditBlocked(
      'quality-approved-automated-drift',
      <String, Object?>{
        'initial': _scenarioQualityAutomatedSurface(initialQuality),
        'approved': _scenarioQualityAutomatedSurface(approvedQuality),
      },
    );
  }
  final approvedAppends = connection.scenarioQualityAppendResults;
  if (approvedAppends.length != 1 ||
      approvedAppends.single['decision'] != HumanDecision.approved.name ||
      approvedAppends.single['state'] != HumanDecisionState.approved.name ||
      approvedAppends.single['supersedesDecisionDigest'] != null) {
    throw _ScenarioLabAuditBlocked('quality-approved-record', approvedAppends);
  }
  final approvedDecision = approvedAppends.single;

  final rejectCountsBeforeConfirmation = connection
      .scenarioQualityRequestCounts();
  await connection.clickScenarioQualityAction('supersede-rejected');
  await _waitFor(
    () async => _scenarioQualityConfirmationReady(
      await connection.scenarioQualitySurface(),
      runId,
    ),
    description: 'superseding rejection confirmation before Host authority',
  );
  final rejectConfirmation = await connection.scenarioQualitySurface();
  final rejectCountsAfterConfirmation = connection
      .scenarioQualityRequestCounts();
  if (!_sameJson(
    rejectCountsBeforeConfirmation,
    rejectCountsAfterConfirmation,
  )) {
    throw _ScenarioLabAuditBlocked(
      'reject-confirmation-fence',
      <String, Object?>{
        'before': rejectCountsBeforeConfirmation,
        'after': rejectCountsAfterConfirmation,
        'surface': rejectConfirmation,
      },
    );
  }
  await connection.pressEscape();
  await _waitFor(() async {
    final surface = await connection.scenarioQualitySurface();
    return _scenarioQualityReviewReady(
          surface,
          runId: runId,
          decisionCount: 1,
          humanDecision: HumanDecisionState.approved,
          enabledAction: 'supersede-rejected',
        ) &&
        surface['focusedAction'] == 'supersede-rejected';
  }, description: 'Escape dismissal and supersede opener focus restoration');
  final rejectCountsAfterEscape = connection.scenarioQualityRequestCounts();
  if (!_sameJson(rejectCountsBeforeConfirmation, rejectCountsAfterEscape)) {
    throw _ScenarioLabAuditBlocked('reject-escape-fence', <String, Object?>{
      'before': rejectCountsBeforeConfirmation,
      'after': rejectCountsAfterEscape,
    });
  }
  await connection.clickScenarioQualityAction('supersede-rejected');
  await _waitFor(
    () async => _scenarioQualityConfirmationReady(
      await connection.scenarioQualitySurface(),
      runId,
    ),
    description: 'reopened superseding rejection confirmation',
  );
  final rejectReopenedConfirmation = await connection.scenarioQualitySurface();
  if (rejectReopenedConfirmation['focusedAction'] !=
          rejectConfirmation['focusedAction'] ||
      !_sameJson(
        rejectCountsBeforeConfirmation,
        connection.scenarioQualityRequestCounts(),
      )) {
    throw _ScenarioLabAuditBlocked(
      'reject-reopen-fence',
      rejectReopenedConfirmation,
    );
  }
  await connection.clickScenarioQualityAction('confirm');
  await _waitFor(
    () async => _scenarioQualityReviewReady(
      await connection.scenarioQualitySurface(),
      runId: runId,
      decisionCount: 2,
      humanDecision: HumanDecisionState.rejected,
      enabledAction: 'supersede-approved',
    ),
    description: 'rejected superseding Quality head and exact history',
    timeout: const Duration(minutes: 2),
  );
  final quality = await connection.scenarioQualitySurface();
  _requireScenarioQualityAutomatedSurface(
    quality,
    runId: runId,
    result: result,
    phase: 'quality-rejected',
  );
  _requireScenarioQualityRpcCounts(
    connection,
    phase: 'quality-final-rpc',
    describe: 3,
    open: 3,
    grant: 2,
    append: 2,
    get: 3,
  );

  final descriptions = connection.scenarioQualityDescribeResults;
  final reviewSets = connection.scenarioQualityReviewSets;
  final appends = connection.scenarioQualityAppendResults;
  final decisionViews = connection.scenarioQualityDecisionViews;
  if (descriptions.length != 3 ||
      reviewSets.length != 3 ||
      appends.length != 2 ||
      decisionViews.length != 3) {
    throw _ScenarioLabAuditBlocked('quality-final-contract', <String, Object?>{
      'descriptionCount': descriptions.length,
      'reviewSetCount': reviewSets.length,
      'appendCount': appends.length,
      'decisionViewCount': decisionViews.length,
      'rpc': connection.scenarioQualityRpcSummary(),
    });
  }
  final automatedSummaries = <Map<String, Object?>>[
    for (final described in descriptions)
      _scenarioQualityAutomatedSummary(described.description.quality),
  ];
  final automatedDigests = <String>{
    for (final summary in automatedSummaries) Digest.semantic(summary).value,
  };
  final reviewSetDigests = <String>{
    for (final reviewSet in reviewSets) Digest.semantic(reviewSet).value,
  };
  final humanTransitions = <String>[
    for (final described in descriptions)
      described.description.quality.humanDecision.state.name,
  ];
  final resourceSurfacesMatch =
      <Map<String, Object?>>[
        initialQuality,
        approvedQuality,
        quality,
      ].indexed.every(
        (entry) => _scenarioQualityResourceSurfaceMatchesReviewSet(
          entry.$2,
          reviewSets[entry.$1],
        ),
      );
  if (automatedDigests.length != 1 ||
      reviewSetDigests.length != 1 ||
      !resourceSurfacesMatch ||
      !_sameJson(initialAutomated, automatedSummaries.first) ||
      !_sameJson(humanTransitions, const <String>[
        'unreviewed',
        'approved',
        'rejected',
      ]) ||
      !_sameJson(
        _scenarioQualityAutomatedSurface(initialQuality),
        _scenarioQualityAutomatedSurface(quality),
      )) {
    throw _ScenarioLabAuditBlocked(
      'quality-automated-invariants',
      <String, Object?>{
        'automatedDigests': automatedDigests.toList(),
        'reviewSetDigests': reviewSetDigests.toList(),
        'humanTransitions': humanTransitions,
        'initialSurface': _scenarioQualityAutomatedSurface(initialQuality),
        'finalSurface': _scenarioQualityAutomatedSurface(quality),
      },
    );
  }

  final rejectedDecision = appends.last;
  final approvedDecisionDigest = approvedDecision['decisionDigest'];
  final rejectedDecisionDigest = rejectedDecision['decisionDigest'];
  if (approvedDecisionDigest is! String ||
      rejectedDecisionDigest is! String ||
      rejectedDecision['decision'] != HumanDecision.rejected.name ||
      rejectedDecision['state'] != HumanDecisionState.rejected.name ||
      rejectedDecision['supersedesDecisionDigest'] != approvedDecisionDigest ||
      quality['headDecisionDigest'] != rejectedDecisionDigest ||
      approvedQuality['headDecisionDigest'] != approvedDecisionDigest) {
    throw _ScenarioLabAuditBlocked(
      'quality-superseding-record',
      <String, Object?>{
        'approved': approvedDecision,
        'rejected': rejectedDecision,
        'approvedSurface': approvedQuality,
        'rejectedSurface': quality,
      },
    );
  }
  final oldDecisionView = _singleScenarioQualityDecisionView(
    decisionViews,
    decisionDigest: approvedDecisionDigest,
    state: HumanDecisionState.superseded,
  );
  final headDecisionView = _singleScenarioQualityDecisionView(
    decisionViews,
    decisionDigest: rejectedDecisionDigest,
    state: HumanDecisionState.rejected,
  );
  if (oldDecisionView['supersededByDecisionDigest'] != rejectedDecisionDigest ||
      headDecisionView['supersededByDecisionDigest'] != null ||
      !_scenarioQualityAttributionMatches(
        approvedDecision,
        runId: runId,
        resultDigest: result.digest,
      ) ||
      !_scenarioQualityAttributionMatches(
        rejectedDecision,
        runId: runId,
        resultDigest: result.digest,
      ) ||
      !_scenarioQualityAttributionMatches(
        oldDecisionView,
        runId: runId,
        resultDigest: result.digest,
      ) ||
      !_scenarioQualityAttributionMatches(
        headDecisionView,
        runId: runId,
        resultDigest: result.digest,
      )) {
    throw _ScenarioLabAuditBlocked(
      'quality-history-attribution',
      <String, Object?>{
        'approved': approvedDecision,
        'rejected': rejectedDecision,
        'oldDecision': oldDecisionView,
        'headDecision': headDecisionView,
      },
    );
  }
  final approvedAttribution = approvedDecision['attribution'];
  final rejectedAttribution = rejectedDecision['attribution'];
  if (approvedAttribution is! Map<String, Object?> ||
      rejectedAttribution is! Map<String, Object?> ||
      approvedAttribution['principalId'] !=
          rejectedAttribution['principalId'] ||
      approvedAttribution['authorityId'] !=
          rejectedAttribution['authorityId'] ||
      approvedAttribution['accessPolicyId'] !=
          rejectedAttribution['accessPolicyId'] ||
      quality['decisionPolicy'] != rejectedAttribution['accessPolicyId'] ||
      quality['decisionRequirement'] != rejectedAttribution['requirementId'] ||
      !_scenarioQualityHistorySurfaceMatches(
        quality,
        approvedDecision: approvedDecision,
        rejectedDecision: rejectedDecision,
      )) {
    throw _ScenarioLabAuditBlocked('quality-history-surface', <String, Object?>{
      'surface': quality,
      'approved': approvedDecision,
      'rejected': rejectedDecision,
    });
  }

  final decisionHistory = <Map<String, Object?>>[
    headDecisionView,
    oldDecisionView,
  ];
  final automatedDigest = automatedDigests.single;
  final reviewSet = reviewSets.last;
  final reviewSetDigest = reviewSetDigests.single;
  final qualitySurfaceDigest = Digest.semantic(
    _scenarioQualityAutomatedSurface(quality),
  ).value;
  final historyDigest = Digest.semantic(decisionHistory).value;

  Map<String, Object?>? qualityCapture;
  if (qualityScreenshotPath != null) {
    final subjectVisible = await connection
        .revealScenarioQualityReviewForCapture();
    if (!subjectVisible) {
      throw _ScenarioLabAuditBlocked(
        'quality-final-capture-subject',
        const <String, Object?>{'visible': false},
      );
    }
    qualityCapture = await _captureScenarioVisual(
      connection,
      qualityScreenshotPath,
      phase: 'quality-final-capture',
    );
  }

  final reflow = await connection.auditReflowAtTwoHundredPercent();
  final reducedMotion = await connection.auditReducedMotion();
  final performance = await connection.performanceMetrics();
  final accessibilityNodes = await connection.accessibilityNodeCount();
  if (accessibilityNodes < 20 || connection.severeLogs.isNotEmpty) {
    throw _ScenarioLabAuditBlocked('browser-health', <String, Object?>{
      'accessibilityNodes': accessibilityNodes,
      'severeBrowserLogs': connection.severeLogs.length,
    });
  }

  await connection.navigateToPath(_scenarioLabPath);
  await _waitFor(() async {
    final surface = await connection.scenarioLabSurface();
    return surface['path'] == _scenarioLabPath &&
        surface['search'] == '' &&
        surface['startEnabled'] == true;
  }, description: 'fresh Scenario Lab route for cancellation');
  await connection.clickScenarioLabRunAction('start');
  await _waitFor(
    () async {
      final surface = await connection.scenarioLabSurface();
      final selectedRunId = surface['selectedRunId'];
      return (selectedRunId is String &&
              surface['queryRunId'] == selectedRunId &&
              surface['cancelEnabled'] == true) ||
          surface['lifecycle'] == 'failed';
    },
    description: 'second Scenario Lab Start outcome',
    timeout: const Duration(seconds: 45),
  );
  final secondStarted = await connection.scenarioLabSurface();
  final secondRunValue = secondStarted['selectedRunId'];
  if (secondRunValue is! String || secondRunValue == runId.value) {
    throw _ScenarioLabAuditBlocked('cancel-start', <String, Object?>{
      'surface': secondStarted,
      'rpc': connection.scenarioLabRpcSummary(),
    });
  }
  final secondRunId = ScenarioLabRunId(secondRunValue);
  await connection.clickScenarioLabRunAction('cancel');
  final cancelledSurface = await _driveScenarioLabToTerminal(
    connection,
    secondRunId,
  );
  final cancelledJson = connection.latestTerminalRunObservation(secondRunId);
  if (cancelledJson == null) {
    throw _ScenarioLabAuditBlocked('cancel-observation', cancelledSurface);
  }
  final cancelled = ScenarioLabRunObservation.fromJson(cancelledJson);
  final cancelledCleanup = cancelled.result?.finalSnapshot.cleanup.state;
  if (cancelled.result?.finalSnapshot.state != ScenarioLabRunState.cancelled ||
      !const <ScenarioLabCleanupState>{
        ScenarioLabCleanupState.notRequired,
        ScenarioLabCleanupState.succeeded,
      }.contains(cancelledCleanup) ||
      cancelledSurface['iframeCount'] != 0 ||
      cancelledSurface['relayCount'] != 0) {
    throw _ScenarioLabAuditBlocked('cancel-terminal', <String, Object?>{
      'surface': cancelledSurface,
      'observation': _scenarioLabObservationSummary(cancelled),
    });
  }

  final artifact = evidence.artifacts.single;
  return <String, Object?>{
    'status': 'passed',
    'mode': 'scenario-lab-audit',
    'route': _scenarioLabPath,
    'runId': runId.value,
    'secondRunId': secondRunId.value,
    'relay': relaySummary,
    'targetControl': targetControl,
    'terminal': <String, Object?>{
      'state': finalSnapshot.state.name,
      'cleanup': finalSnapshot.cleanup.state.name,
      'resultDigest': result.digest.value,
      'snapshotDigest': finalSnapshot.digest.value,
      'contentSetDigest': finalSnapshot.contentSetDigest.value,
      'catalogDigest': finalSnapshot.catalogDigest.value,
      'scenarioLabManifestDigest':
          finalSnapshot.scenarioLabManifestDigest.value,
      'verification': result.verificationState.name,
    },
    'evidence': <String, Object?>{
      'state': evidence.state.name,
      'freshness': evidence.freshness.name,
      'evidenceDigest': evidence.evidenceDigest!.value,
      'resultDigest': evidence.digest.value,
      'artifactDigest': artifact.artifactDigest.value,
      'provenanceDigest': artifact.provenanceDigest.value,
      'classification': artifact.classification.name,
    },
    'comparison': <String, Object?>{
      'kind': comparison.resultKind.name,
      'verification': comparison.verificationState.name,
      'resultDigest': comparison.digest.value,
      if (comparison is VisualScenarioComparisonResult) ...<String, Object?>{
        'comparedPixels': comparison.comparedPixels,
        'changedPixels': comparison.changedPixels,
        'maxChannelDeltaObserved': comparison.maxChannelDeltaObserved,
      },
    },
    'captures': <String, Object?>{
      'decisionDialog': ?dialogCapture,
      'qualityFinal': ?qualityCapture,
    },
    'quality': quality,
    'qualityReview': <String, Object?>{
      'initial': initialQuality,
      'approved': approvedQuality,
      'head': quality,
      'confirmBeforeAuthority': <String, Object?>{
        'approve': true,
        'supersedingReject': true,
      },
      'dialogAccessibility': <String, Object?>{
        'nativeModal': true,
        'approveInitialFocus': approveConfirmation['focusedAction'],
        'approveEscapeClosedWithoutRpc': true,
        'approveFocusReturnedToOpener': true,
        'supersedeInitialFocus': rejectConfirmation['focusedAction'],
        'supersedeEscapeClosedWithoutRpc': true,
        'supersedeFocusReturnedToOpener': true,
      },
      'automatedDigest': automatedDigest,
      'automatedUnchanged': true,
      'qualitySurfaceDigest': qualitySurfaceDigest,
      'reviewSet': reviewSet,
      'reviewSetDigest': reviewSetDigest,
      'humanTransitions': humanTransitions,
    },
    'decisions': <String, Object?>{
      'approved': approvedDecision,
      'head': rejectedDecision,
      'oldAfterSupersession': oldDecisionView,
      'headView': headDecisionView,
      'historyDigest': historyDigest,
    },
    'cancel': <String, Object?>{
      'state': cancelled.result!.finalSnapshot.state.name,
      'cleanup': cancelled.result!.finalSnapshot.cleanup.state.name,
    },
    'semanticHtml': semanticHtml,
    'keyboard': keyboard,
    'reflow200Percent': reflow,
    'reducedMotion': reducedMotion,
    'performance': performance,
    'accessibilityNodes': accessibilityNodes,
    'severeBrowserLogs': connection.severeLogs.length,
    'labRpc': connection.scenarioLabRpcSummary(),
    'qualityRpc': connection.scenarioQualityRpcSummary(),
  };
}

Future<Map<String, Object?>> _auditScenarioQualityReload(
  _CdpConnection connection,
  _ScenarioQualityReloadExpectation expected,
) async {
  await _waitFor(
    () async => _scenarioQualityReattachActionReady(
      await connection.scenarioQualityReattachSurface(),
      expected.runId,
    ),
    description: 'new-probe explicit Quality reattach action',
  );
  final initialBoundary = await connection.scenarioQualityReattachSurface();
  _requireScenarioQualityAwaitingExplicitReattach(
    connection,
    initialBoundary,
    expected.runId,
    phase: 'new-probe-reattach-boundary',
  );
  await connection.clickScenarioLabRunAction('reattach');
  try {
    await _waitFor(
      () async {
        final quality = await connection.scenarioQualitySurface();
        if (_scenarioQualityReviewReady(
          quality,
          runId: expected.runId,
          decisionCount: 2,
          humanDecision: HumanDecisionState.rejected,
          enabledAction: 'supersede-approved',
        )) {
          return true;
        }
        final boundary = await connection.scenarioQualityReattachSurface();
        return const <String>{
          'failed',
          'unavailable',
          'closed',
        }.contains(boundary['lifecycle']);
      },
      description: 'new-probe reattached Quality history and head',
      timeout: const Duration(minutes: 2),
    );
  } on _ProbeTimeout {
    throw _ScenarioLabAuditBlocked(
      'new-probe-reattach-timeout',
      <String, Object?>{
        'reattachSurface': await connection.scenarioQualityReattachSurface(),
        'qualitySurface': await connection.scenarioQualitySurface(),
        'labRpc': connection.scenarioLabRpcSummary(),
        'qualityRpc': connection.scenarioQualityRpcSummary(),
      },
    );
  }
  final newProbeQuality = await connection.scenarioQualitySurface();
  if (!_scenarioQualityReviewReady(
    newProbeQuality,
    runId: expected.runId,
    decisionCount: 2,
    humanDecision: HumanDecisionState.rejected,
    enabledAction: 'supersede-approved',
  )) {
    throw _ScenarioLabAuditBlocked(
      'new-probe-reattach-failed',
      <String, Object?>{
        'reattachSurface': await connection.scenarioQualityReattachSurface(),
        'qualitySurface': newProbeQuality,
        'labRpc': connection.scenarioLabRpcSummary(),
        'qualityRpc': connection.scenarioQualityRpcSummary(),
      },
    );
  }
  final initialQuality = await connection.scenarioQualitySurface();
  final initialProof = _requireScenarioQualityRecoveryProof(
    connection,
    expected,
    initialQuality,
    phase: 'new-probe',
  );
  final initialLabRpc = _jsonMapSnapshot(connection.scenarioLabRpcSummary());
  final initialQualityRpc = _jsonMapSnapshot(
    connection.scenarioQualityRpcSummary(),
  );

  connection.resetScenarioAuditForReload();
  await connection.reloadCurrentPage();
  await _waitFor(
    () async => _scenarioQualityReattachActionReady(
      await connection.scenarioQualityReattachSurface(),
      expected.runId,
    ),
    description: 'post-reload explicit Quality reattach action',
  );
  final reloadedBoundary = await connection.scenarioQualityReattachSurface();
  _requireScenarioQualityAwaitingExplicitReattach(
    connection,
    reloadedBoundary,
    expected.runId,
    phase: 'post-reload-reattach-boundary',
  );
  await connection.clickScenarioLabRunAction('reattach');
  try {
    await _waitFor(
      () async {
        final quality = await connection.scenarioQualitySurface();
        if (_scenarioQualityReviewReady(
          quality,
          runId: expected.runId,
          decisionCount: 2,
          humanDecision: HumanDecisionState.rejected,
          enabledAction: 'supersede-approved',
        )) {
          return true;
        }
        final boundary = await connection.scenarioQualityReattachSurface();
        return const <String>{
          'failed',
          'unavailable',
          'closed',
        }.contains(boundary['lifecycle']);
      },
      description: 'post-reload reattached Quality history and head',
      timeout: const Duration(minutes: 2),
    );
  } on _ProbeTimeout {
    throw _ScenarioLabAuditBlocked(
      'post-reload-reattach-timeout',
      <String, Object?>{
        'reattachSurface': await connection.scenarioQualityReattachSurface(),
        'qualitySurface': await connection.scenarioQualitySurface(),
        'labRpc': connection.scenarioLabRpcSummary(),
        'qualityRpc': connection.scenarioQualityRpcSummary(),
      },
    );
  }
  final postReloadQuality = await connection.scenarioQualitySurface();
  if (!_scenarioQualityReviewReady(
    postReloadQuality,
    runId: expected.runId,
    decisionCount: 2,
    humanDecision: HumanDecisionState.rejected,
    enabledAction: 'supersede-approved',
  )) {
    throw _ScenarioLabAuditBlocked(
      'post-reload-reattach-failed',
      <String, Object?>{
        'reattachSurface': await connection.scenarioQualityReattachSurface(),
        'qualitySurface': postReloadQuality,
        'labRpc': connection.scenarioLabRpcSummary(),
        'qualityRpc': connection.scenarioQualityRpcSummary(),
      },
    );
  }
  final quality = await connection.scenarioQualitySurface();
  final proof = _requireScenarioQualityRecoveryProof(
    connection,
    expected,
    quality,
    phase: 'post-reload',
  );
  final postReloadLabRpc = connection.scenarioLabRpcSummary();
  if (!_sameJson(initialProof.quality, proof.quality) ||
      !_sameJson(initialProof.automated, proof.automated) ||
      !_sameJson(initialProof.reviewSet, proof.reviewSet) ||
      !_sameJson(initialProof.oldDecisionView, proof.oldDecisionView) ||
      !_sameJson(initialProof.headDecisionView, proof.headDecisionView) ||
      !_sameJson(
        initialLabRpc['requestsByMethod'],
        postReloadLabRpc['requestsByMethod'],
      ) ||
      initialProof.result.digest != proof.result.digest ||
      initialProof.result.finalSnapshot.digest !=
          proof.result.finalSnapshot.digest) {
    throw _ScenarioLabAuditBlocked('reload-recovery-drift', <String, Object?>{
      'newProbeSurfaceDigest': Digest.semantic(initialProof.quality).value,
      'postReloadSurfaceDigest': Digest.semantic(proof.quality).value,
      'newProbeReviewSetDigest': Digest.semantic(initialProof.reviewSet).value,
      'postReloadReviewSetDigest': Digest.semantic(proof.reviewSet).value,
    });
  }

  final semanticHtml = await connection.auditSemanticHtml();
  final keyboard = await connection.auditKeyboardNavigation();
  final reflow = await connection.auditReflowAtTwoHundredPercent();
  final reducedMotion = await connection.auditReducedMotion();
  final performance = await connection.performanceMetrics();
  final accessibilityNodes = await connection.accessibilityNodeCount();
  if (accessibilityNodes < 20 || connection.severeLogs.isNotEmpty) {
    throw _ScenarioLabAuditBlocked('reload-browser-health', <String, Object?>{
      'accessibilityNodes': accessibilityNodes,
      'severeBrowserLogs': connection.severeLogs.length,
    });
  }
  return <String, Object?>{
    'status': 'passed',
    'mode': 'scenario-quality-reload-audit',
    'route': _scenarioQualityPath,
    'runId': expected.runId.value,
    'terminal': <String, Object?>{
      'state': proof.result.finalSnapshot.state.name,
      'resultDigest': proof.result.digest.value,
      'snapshotDigest': proof.result.finalSnapshot.digest.value,
    },
    'quality': quality,
    'qualityReview': <String, Object?>{
      'automatedDigest': Digest.semantic(proof.automated).value,
      'qualitySurfaceDigest': Digest.semantic(
        _scenarioQualityAutomatedSurface(quality),
      ).value,
      'reviewSet': proof.reviewSet,
      'reviewSetDigest': Digest.semantic(proof.reviewSet).value,
    },
    'decisions': <String, Object?>{
      'headView': proof.headDecisionView,
      'oldAfterSupersession': proof.oldDecisionView,
      'historyDigest': Digest.semantic(<Map<String, Object?>>[
        proof.headDecisionView,
        proof.oldDecisionView,
      ]).value,
    },
    'reattach': <String, Object?>{
      'newProbeExplicit': true,
      'postReloadExplicit': true,
      'newProbeSurfaceDigest': Digest.semantic(initialProof.quality).value,
      'postReloadSurfaceDigest': Digest.semantic(proof.quality).value,
      'newProbeLabRpc': initialLabRpc,
      'newProbeQualityRpc': initialQualityRpc,
    },
    'semanticHtml': semanticHtml,
    'keyboard': keyboard,
    'reflow200Percent': reflow,
    'reducedMotion': reducedMotion,
    'performance': performance,
    'accessibilityNodes': accessibilityNodes,
    'severeBrowserLogs': connection.severeLogs.length,
    'labRpc': connection.scenarioLabRpcSummary(),
    'qualityRpc': connection.scenarioQualityRpcSummary(),
  };
}

Future<Map<String, Object?>> _auditScenarioCurrentness(
  _CdpConnection connection,
  _ScenarioCurrentnessExpectation expected,
) async {
  await connection.installScenarioLabControlObserver();
  await _waitFor(
    () async => _scenarioQualityReattachActionReady(
      await connection.scenarioQualityReattachSurface(),
      expected.oldRunId,
    ),
    description: 'historical Quality explicit reattach action',
  );
  final initialBoundary = await connection.scenarioQualityReattachSurface();
  _requireScenarioQualityAwaitingExplicitReattach(
    connection,
    initialBoundary,
    expected.oldRunId,
    phase: 'historical-reattach-boundary',
  );
  await connection.clickScenarioLabRunAction('reattach');
  await _waitFor(
    () async {
      final surface = await connection.scenarioQualitySurface();
      final history = surface['history'];
      return surface['runId'] == expected.oldRunId.value &&
          surface['contentCurrentness'] == 'stale' &&
          surface['reviewAvailability'] ==
              ScenarioQualityReviewAvailability.unavailable.name &&
          surface['decisionOperation'] == 'ready' &&
          history is List<Object?> &&
          history.length == 2 &&
          connection.scenarioQualityDescribeResults.length == 1 &&
          connection.scenarioQualityDecisionViews.length == 2;
    },
    description: 'historical stale Quality and unavailable review',
    timeout: const Duration(minutes: 2),
  );

  final historicalQuality = await connection.scenarioQualitySurface();
  final historicalStates = historicalQuality['states'];
  final recollectLinks = historicalQuality['recollectLinks'];
  final historicalResources = historicalQuality['resources'];
  if (historicalQuality['path'] != _scenarioQualityPath ||
      historicalQuality['queryRunId'] != expected.oldRunId.value ||
      historicalQuality['runId'] != expected.oldRunId.value ||
      historicalQuality['resultDigest'] != expected.oldRunResultDigest.value ||
      historicalQuality['contentCurrentness'] != 'stale' ||
      historicalQuality['currentnessNoticeCount'] != 1 ||
      historicalQuality['verification'] != VerificationState.passed.name ||
      historicalQuality['evidenceState'] !=
          RequiredEvidenceResultState.collected.name ||
      historicalQuality['evidenceFreshness'] != EvidenceFreshness.fresh.name ||
      historicalQuality['evidenceVerification'] !=
          VerificationState.passed.name ||
      historicalQuality['comparisonState'] != VerificationState.passed.name ||
      historicalQuality['comparisonKind'] !=
          ScenarioComparisonResultKind.visual.name ||
      historicalQuality['comparisonChangedUnits'] !=
          '${expected.oldChangedPixels}' ||
      historicalQuality['reviewAvailability'] !=
          ScenarioQualityReviewAvailability.unavailable.name ||
      historicalQuality['decisionOperation'] != 'ready' ||
      historicalStates is! List<Object?> ||
      !historicalStates.contains('stale') ||
      historicalStates.contains('passing') ||
      historicalStates.contains('failing') ||
      recollectLinks is! List<Object?> ||
      !_sameJson(recollectLinks, const <Object?>[
        <String, Object?>{'path': _scenarioLabPath, 'search': ''},
      ]) ||
      historicalResources is! List<Object?> ||
      historicalResources.isNotEmpty) {
    throw _ScenarioLabAuditBlocked(
      'historical-quality-currentness',
      historicalQuality,
    );
  }

  final historicalObservationJson = connection.latestTerminalRunObservation(
    expected.oldRunId,
  );
  if (historicalObservationJson == null) {
    throw _ScenarioLabAuditBlocked(
      'historical-reattach-observation',
      connection.scenarioLabRpcSummary(),
    );
  }
  final historicalObservation = ScenarioLabRunObservation.fromJson(
    historicalObservationJson,
  );
  final historicalResult = historicalObservation.result;
  if (historicalObservation.disposition != ScenarioLabRunDisposition.terminal ||
      historicalResult == null ||
      historicalResult.digest != expected.oldRunResultDigest ||
      historicalResult.finalSnapshot.digest != expected.oldSnapshotDigest ||
      historicalResult.finalSnapshot.contentSetDigest !=
          expected.oldContentSetDigest ||
      historicalResult.finalSnapshot.catalogDigest !=
          expected.oldCatalogDigest ||
      historicalResult.finalSnapshot.scenarioLabManifestDigest !=
          expected.oldScenarioLabManifestDigest ||
      historicalResult.finalSnapshot.state != ScenarioLabRunState.succeeded ||
      historicalResult.finalSnapshot.cleanup.state !=
          ScenarioLabCleanupState.succeeded ||
      historicalResult.verificationState != VerificationState.passed) {
    throw _ScenarioLabAuditBlocked(
      'historical-terminal-identity',
      _scenarioLabObservationSummary(historicalObservation),
    );
  }
  final historicalEvidence = historicalResult.finalSnapshot.requiredEvidence
      .singleWhere(
        (item) => item.requiredEvidenceId.value == 'dashboard-ready-visual',
      );
  final historicalComparison = historicalResult.finalSnapshot.comparisons
      .singleWhere(
        (item) => item.bindingId.value == 'dashboard-ready-baseline-candidate',
      );
  final historicalArtifact = historicalEvidence.artifacts.single;
  if (historicalComparison is! VisualScenarioComparisonResult ||
      historicalEvidence.state != RequiredEvidenceResultState.collected ||
      historicalEvidence.freshness != EvidenceFreshness.fresh ||
      historicalEvidence.digest != expected.oldEvidenceResultDigest ||
      historicalEvidence.evidenceDigest != expected.oldEvidenceDigest ||
      historicalArtifact.artifactDigest != expected.oldArtifactDigest ||
      historicalArtifact.provenanceDigest != expected.oldProvenanceDigest ||
      historicalComparison.digest != expected.oldComparisonResultDigest ||
      historicalComparison.verificationState != VerificationState.passed ||
      historicalComparison.comparedPixels != expected.oldComparedPixels ||
      historicalComparison.changedPixels != expected.oldChangedPixels ||
      historicalComparison.maxChannelDeltaObserved !=
          expected.oldMaxChannelDeltaObserved) {
    throw _ScenarioLabAuditBlocked(
      'historical-evidence-immutability',
      _scenarioLabObservationSummary(historicalObservation),
    );
  }

  final historicalDescriptions = connection.scenarioQualityDescribeResults;
  final historicalDescription = historicalDescriptions.single.description;
  historicalDescription.quality.validateAgainstResult(historicalResult);
  _requireScenarioQualityRpcCounts(
    connection,
    phase: 'historical-quality-rpc',
    describe: 1,
    open: 0,
    grant: 0,
    append: 0,
    get: 2,
  );
  if (historicalDescription.runId != expected.oldRunId ||
      historicalDescription.runResultDigest != expected.oldRunResultDigest ||
      historicalDescription.availability !=
          ScenarioQualityReviewAvailability.unavailable ||
      connection.scenarioQualityReviewSets.isNotEmpty ||
      historicalDescription.quality.requiredEvidence.single.resultDigest !=
          expected.oldEvidenceResultDigest ||
      historicalDescription.quality.comparisonResultDigests.single !=
          expected.oldComparisonResultDigest) {
    throw _ScenarioLabAuditBlocked(
      'historical-quality-contract',
      _scenarioQualityDescriptionSummary(historicalDescription),
    );
  }
  final historicalLabRpc = _jsonMapSnapshot(connection.scenarioLabRpcSummary());
  final historicalQualityRpc = _jsonMapSnapshot(
    connection.scenarioQualityRpcSummary(),
  );

  await connection.clickSelector('a[data-quality-action="recollect"]');
  await _waitFor(() async {
    final surface = await connection.scenarioLabSurface();
    return surface['path'] == _scenarioLabPath &&
        surface['search'] == '' &&
        surface['queryRunId'] == null &&
        surface['routeState'] == 'ready' &&
        surface['startButtonCount'] == 1 &&
        surface['startEnabled'] == true;
  }, description: 'current Lab recollection route without runId');
  final recollectDestination = await connection.scenarioLabSurface();

  connection.resetScenarioAuditForReload();
  connection.beginScenarioLabRunTransportAudit();
  await connection.clickScenarioLabRunAction('start');
  await _waitFor(
    () async {
      final surface = await connection.scenarioLabSurface();
      final selectedRunId = surface['selectedRunId'];
      return selectedRunId is String &&
          selectedRunId != expected.oldRunId.value &&
          surface['queryRunId'] == selectedRunId;
    },
    description: 'current recollection run identity',
    timeout: const Duration(seconds: 45),
  );
  final started = await connection.scenarioLabSurface();
  final currentRunValue = started['selectedRunId'];
  if (currentRunValue is! String) {
    throw _ScenarioLabAuditBlocked('current-run-start', started);
  }
  final currentRunId = ScenarioLabRunId(currentRunValue);

  Map<String, Object?>? currentMountedRelay;
  var lastCurrentRelaySurface = started;
  var lastCurrentRelay = await connection.scenarioLabRelay(currentRunId);
  var lastCurrentMountProof = connection.scenarioLabRelayMountProof(
    runId: currentRunId,
    relay: lastCurrentRelay,
  );
  try {
    await _waitFor(
      () async {
        final surface = await connection.scenarioLabSurface();
        final relay = await connection.scenarioLabRelay(currentRunId);
        final mountProof = connection.scenarioLabRelayMountProof(
          runId: currentRunId,
          relay: relay,
        );
        lastCurrentRelaySurface = surface;
        lastCurrentRelay = relay;
        lastCurrentMountProof = mountProof;
        if (surface['iframeCount'] == 1 &&
            mountProof['mountAuthorized'] == true) {
          currentMountedRelay = relay;
          return true;
        }
        return surface['lifecycle'] == 'terminal' ||
            surface['relayState'] == 'failed';
      },
      description: 'current recollection relay iframe',
      timeout: const Duration(minutes: 2),
    );
  } on _ProbeTimeout {
    throw _ScenarioLabAuditBlocked(
      'current-single-relay-timeout',
      <String, Object?>{
        'surface': _scenarioLabSurfaceSummary(lastCurrentRelaySurface),
        'relay': _scenarioLabRelaySummary(lastCurrentRelay),
        'mount': lastCurrentMountProof,
        'frameNavigation': connection.scenarioLabFrameNavigationDiagnostics(
          currentRunId,
        ),
        'relayV2': connection.scenarioLabRelayV2Diagnostics(currentRunId),
        'rpc': connection.scenarioLabRpcSummary(),
      },
    );
  }
  final currentRelay =
      currentMountedRelay ?? await connection.scenarioLabRelay(currentRunId);
  final currentMountProof = connection.scenarioLabRelayMountProof(
    runId: currentRunId,
    relay: currentRelay,
  );
  if (currentRelay['relayCount'] != 1 ||
      currentRelay['iframeCount'] != 1 ||
      currentRelay['runId'] != currentRunId.value ||
      currentRelay['aboutBlank'] != true ||
      currentRelay['gatewayBindingDeclared'] != true ||
      currentRelay['gatewayBound'] != true ||
      currentMountProof['mountAuthorized'] != true) {
    throw _ScenarioLabAuditBlocked('current-relay', <String, Object?>{
      'relay': _scenarioLabRelaySummary(currentRelay),
      'mount': currentMountProof,
    });
  }
  final currentRelayAtMount = <String, Object?>{
    ..._scenarioLabRelaySummary(currentRelay),
    ...currentMountProof,
  };

  final terminalSurface = await _driveScenarioLabToTerminal(
    connection,
    currentRunId,
  );
  final currentObservationJson = connection.latestTerminalRunObservation(
    currentRunId,
  );
  if (currentObservationJson == null) {
    throw _ScenarioLabAuditBlocked(
      'current-terminal-observation',
      connection.scenarioLabRpcSummary(),
    );
  }
  final currentObservation = ScenarioLabRunObservation.fromJson(
    currentObservationJson,
  );
  final currentResult = currentObservation.result;
  if (currentObservation.disposition != ScenarioLabRunDisposition.terminal ||
      currentResult == null ||
      terminalSurface['runPanelState'] != 'failed' ||
      terminalSurface['iframeCount'] != 0 ||
      terminalSurface['relayCount'] != 0 ||
      currentResult.finalSnapshot.state != ScenarioLabRunState.failed ||
      currentResult.finalSnapshot.terminalCause !=
          ScenarioLabTerminalCause.acceptanceFailed ||
      currentResult.finalSnapshot.cleanup.state !=
          ScenarioLabCleanupState.succeeded ||
      currentResult.verificationState != VerificationState.passed ||
      currentResult.finalSnapshot.contentSetDigest !=
          expected.currentContentSetDigest ||
      currentResult.finalSnapshot.catalogDigest !=
          expected.currentCatalogDigest ||
      currentResult.finalSnapshot.scenarioLabManifestDigest !=
          expected.currentScenarioLabManifestDigest) {
    throw _ScenarioLabAuditBlocked(
      'current-terminal-contract',
      _scenarioLabObservationSummary(currentObservation),
    );
  }
  final currentGatewayProof = connection.scenarioLabGatewayProof(
    runId: currentRunId,
    snapshot: currentResult.finalSnapshot,
    relay: currentRelay,
  );
  if (!_scenarioLabGatewayProofIsValid(currentGatewayProof)) {
    throw _ScenarioLabAuditBlocked(
      'current-gateway-binding',
      currentGatewayProof,
    );
  }
  final currentRelaySummary = <String, Object?>{
    ...currentRelayAtMount,
    ...currentGatewayProof,
  };

  final currentEvidence = currentResult.finalSnapshot.requiredEvidence
      .singleWhere(
        (item) => item.requiredEvidenceId.value == 'dashboard-ready-visual',
      );
  final currentComparison = currentResult.finalSnapshot.comparisons.singleWhere(
    (item) => item.bindingId.value == 'dashboard-ready-baseline-candidate',
  );
  final currentArtifact = currentEvidence.artifacts.single;
  if (currentComparison is! VisualScenarioComparisonResult ||
      currentEvidence.state != RequiredEvidenceResultState.collected ||
      currentEvidence.freshness != EvidenceFreshness.fresh ||
      currentEvidence.evidenceDigest == null ||
      currentEvidence.artifacts.length != 1 ||
      currentArtifact.artifactDigest == expected.oldArtifactDigest ||
      currentComparison.resultKind != ScenarioComparisonResultKind.visual ||
      currentComparison.verificationState != VerificationState.failed ||
      currentComparison.comparedPixels == null ||
      currentComparison.changedPixels == null ||
      currentComparison.maxChannelDeltaObserved == null ||
      currentComparison.changedPixels! <= 0 ||
      currentComparison.changedPixels! / currentComparison.comparedPixels! <=
          0.005 ||
      currentComparison.maxChannelDeltaObserved! <= 8) {
    throw _ScenarioLabAuditBlocked(
      'current-evidence-comparison',
      _scenarioLabObservationSummary(currentObservation),
    );
  }
  final changedPixelRatio =
      currentComparison.changedPixels! / currentComparison.comparedPixels!;
  final targetControl = await connection.scenarioLabControlProof();
  if (targetControl['semanticStates'] is! List<Object?> ||
      !(targetControl['semanticStates']! as List<Object?>).contains(
        'disabled',
      ) ||
      !(targetControl['semanticStates']! as List<Object?>).contains(
        'enabled',
      ) ||
      (targetControl['captureErrors'] as List<Object?>? ?? const <Object?>[])
          .isNotEmpty) {
    throw _ScenarioLabAuditBlocked('current-target-control', targetControl);
  }

  await connection.clickSelector(
    'a[data-scenario-cross-surface="lab-to-quality"]',
  );
  await _waitFor(
    () async {
      final quality = await connection.scenarioQualitySurface();
      final states = quality['states'];
      return quality['path'] == _scenarioQualityPath &&
          quality['queryRunId'] == currentRunId.value &&
          quality['runId'] == currentRunId.value &&
          quality['contentCurrentness'] == 'current' &&
          quality['evidenceFreshness'] == EvidenceFreshness.fresh.name &&
          quality['comparisonState'] == VerificationState.failed.name &&
          states is List<Object?> &&
          states.contains('changed') &&
          states.contains('failing') &&
          connection.scenarioQualityDescribeResults.length == 1;
    },
    description: 'current changed and failing Quality',
    timeout: const Duration(minutes: 2),
  );
  final currentQuality = await connection.scenarioQualitySurface();
  final currentStates = currentQuality['states'];
  if (currentQuality['resultDigest'] != currentResult.digest.value ||
      currentQuality['verification'] != VerificationState.passed.name ||
      currentQuality['evidenceState'] !=
          RequiredEvidenceResultState.collected.name ||
      currentQuality['evidenceFreshness'] != EvidenceFreshness.fresh.name ||
      currentQuality['evidenceVerification'] != VerificationState.passed.name ||
      currentQuality['comparisonState'] != VerificationState.failed.name ||
      currentQuality['comparisonKind'] !=
          ScenarioComparisonResultKind.visual.name ||
      currentQuality['comparisonChangedUnits'] !=
          '${currentComparison.changedPixels}' ||
      currentQuality['contentCurrentness'] != 'current' ||
      currentQuality['currentnessNoticeCount'] != 0 ||
      currentStates is! List<Object?> ||
      !currentStates.contains('changed') ||
      !currentStates.contains('failing') ||
      currentStates.contains('stale') ||
      currentStates.contains('passing') ||
      currentStates.contains('unverified') ||
      currentStates.contains('missing') ||
      currentStates.contains('unsupported') ||
      currentStates.contains('policyDenied')) {
    throw _ScenarioLabAuditBlocked('current-quality-states', currentQuality);
  }
  final currentDescriptions = connection.scenarioQualityDescribeResults;
  final currentDescription = currentDescriptions.single.description;
  currentDescription.quality.validateAgainstResult(currentResult);
  if (currentDescription.runId != currentRunId ||
      currentDescription.runResultDigest != currentResult.digest ||
      currentDescription.quality.verificationState !=
          VerificationState.passed ||
      currentDescription.quality.requiredEvidence.single.resultDigest !=
          currentEvidence.digest ||
      currentDescription.quality.comparisonResultDigests.single !=
          currentComparison.digest) {
    throw _ScenarioLabAuditBlocked(
      'current-quality-contract',
      _scenarioQualityDescriptionSummary(currentDescription),
    );
  }
  if (connection.severeLogs.isNotEmpty) {
    throw _ScenarioLabAuditBlocked(
      'currentness-browser-health',
      <String, Object?>{'severeBrowserLogs': connection.severeLogs.length},
    );
  }

  return <String, Object?>{
    'status': 'passed',
    'mode': 'scenario-currentness-audit',
    'historical': <String, Object?>{
      'runId': expected.oldRunId.value,
      'terminal': <String, Object?>{
        'state': historicalResult.finalSnapshot.state.name,
        'cleanup': historicalResult.finalSnapshot.cleanup.state.name,
        'resultDigest': historicalResult.digest.value,
        'snapshotDigest': historicalResult.finalSnapshot.digest.value,
        'contentSetDigest':
            historicalResult.finalSnapshot.contentSetDigest.value,
        'catalogDigest': historicalResult.finalSnapshot.catalogDigest.value,
        'scenarioLabManifestDigest':
            historicalResult.finalSnapshot.scenarioLabManifestDigest.value,
        'verification': historicalResult.verificationState.name,
      },
      'evidence': <String, Object?>{
        'state': historicalEvidence.state.name,
        'freshness': historicalEvidence.freshness.name,
        'resultDigest': historicalEvidence.digest.value,
        'evidenceDigest': historicalEvidence.evidenceDigest!.value,
        'artifactDigest': historicalArtifact.artifactDigest.value,
        'provenanceDigest': historicalArtifact.provenanceDigest.value,
        'immutable': true,
      },
      'comparison': <String, Object?>{
        'kind': historicalComparison.resultKind.name,
        'verification': historicalComparison.verificationState.name,
        'resultDigest': historicalComparison.digest.value,
        'comparedPixels': historicalComparison.comparedPixels,
        'changedPixels': historicalComparison.changedPixels,
        'maxChannelDeltaObserved': historicalComparison.maxChannelDeltaObserved,
      },
      'quality': historicalQuality,
      'reviewUnavailable': true,
      'recollect': <String, Object?>{
        'linkCount': 1,
        'path': _scenarioLabPath,
        'hasRunId': false,
        'destinationSearch': recollectDestination['search'],
      },
      'labRpc': historicalLabRpc,
      'qualityRpc': historicalQualityRpc,
    },
    'current': <String, Object?>{
      'runId': currentRunId.value,
      'relay': currentRelaySummary,
      'targetControl': targetControl,
      'terminal': <String, Object?>{
        'state': currentResult.finalSnapshot.state.name,
        'terminalCause': currentResult.finalSnapshot.terminalCause!.name,
        'cleanup': currentResult.finalSnapshot.cleanup.state.name,
        'resultDigest': currentResult.digest.value,
        'snapshotDigest': currentResult.finalSnapshot.digest.value,
        'contentSetDigest': currentResult.finalSnapshot.contentSetDigest.value,
        'catalogDigest': currentResult.finalSnapshot.catalogDigest.value,
        'scenarioLabManifestDigest':
            currentResult.finalSnapshot.scenarioLabManifestDigest.value,
        'identityMatchesPostRefresh': true,
        'verification': currentResult.verificationState.name,
      },
      'evidence': <String, Object?>{
        'state': currentEvidence.state.name,
        'freshness': currentEvidence.freshness.name,
        'resultDigest': currentEvidence.digest.value,
        'evidenceDigest': currentEvidence.evidenceDigest!.value,
        'artifactDigest': currentArtifact.artifactDigest.value,
        'provenanceDigest': currentArtifact.provenanceDigest.value,
      },
      'comparison': <String, Object?>{
        'kind': currentComparison.resultKind.name,
        'verification': currentComparison.verificationState.name,
        'resultDigest': currentComparison.digest.value,
        'comparedPixels': currentComparison.comparedPixels,
        'changedPixels': currentComparison.changedPixels,
        'changedPixelRatio': changedPixelRatio,
        'maxChannelDeltaObserved': currentComparison.maxChannelDeltaObserved,
      },
      'quality': currentQuality,
      'labRpc': connection.scenarioLabRpcSummary(),
      'qualityRpc': connection.scenarioQualityRpcSummary(),
    },
    'severeBrowserLogs': connection.severeLogs.length,
  };
}

final class _ScenarioQualityRecoveryProof {
  const _ScenarioQualityRecoveryProof({
    required this.quality,
    required this.automated,
    required this.reviewSet,
    required this.oldDecisionView,
    required this.headDecisionView,
    required this.result,
  });

  final Map<String, Object?> quality;
  final Map<String, Object?> automated;
  final Map<String, Object?> reviewSet;
  final Map<String, Object?> oldDecisionView;
  final Map<String, Object?> headDecisionView;
  final ScenarioLabRunResult result;
}

_ScenarioQualityRecoveryProof _requireScenarioQualityRecoveryProof(
  _CdpConnection connection,
  _ScenarioQualityReloadExpectation expected,
  Map<String, Object?> quality, {
  required String phase,
}) {
  if (quality['path'] != _scenarioQualityPath ||
      quality['queryRunId'] != expected.runId.value ||
      quality['runId'] != expected.runId.value ||
      quality['resultDigest'] != expected.runResultDigest.value ||
      quality['decisionCount'] != 2 ||
      quality['headDecisionDigest'] != expected.headDecisionDigest.value ||
      quality['decisionRequirement'] != expected.requirementId.value ||
      quality['decisionPolicy'] != expected.policyId.value ||
      Digest.semantic(_scenarioQualityAutomatedSurface(quality)).value !=
          expected.qualitySurfaceDigest.value) {
    throw _ScenarioLabAuditBlocked('$phase-quality-surface', quality);
  }
  _requireScenarioQualityRpcCounts(
    connection,
    phase: '$phase-quality-rpc',
    describe: 1,
    open: 1,
    grant: 0,
    append: 0,
    get: 2,
  );
  final descriptions = connection.scenarioQualityDescribeResults;
  final reviewSets = connection.scenarioQualityReviewSets;
  final decisionViews = connection.scenarioQualityDecisionViews;
  if (descriptions.length != 1 ||
      reviewSets.length != 1 ||
      decisionViews.length != 2) {
    throw _ScenarioLabAuditBlocked('$phase-quality-contract', <String, Object?>{
      'descriptionCount': descriptions.length,
      'reviewSetCount': reviewSets.length,
      'decisionViewCount': decisionViews.length,
      'rpc': connection.scenarioQualityRpcSummary(),
    });
  }

  final observationJson = connection.latestTerminalRunObservation(
    expected.runId,
  );
  if (observationJson == null) {
    throw _ScenarioLabAuditBlocked('$phase-reattach-rpc', <String, Object?>{
      'labRpc': connection.scenarioLabRpcSummary(),
    });
  }
  final observation = ScenarioLabRunObservation.fromJson(observationJson);
  final result = observation.result;
  if (observation.disposition != ScenarioLabRunDisposition.terminal ||
      result == null ||
      result.digest != expected.runResultDigest ||
      result.finalSnapshot.digest != expected.snapshotDigest ||
      result.finalSnapshot.state != ScenarioLabRunState.succeeded) {
    throw _ScenarioLabAuditBlocked(
      '$phase-reattach-terminal',
      _scenarioLabObservationSummary(observation),
    );
  }

  final description = descriptions.single.description;
  description.quality.validateAgainstResult(result);
  final automated = _scenarioQualityAutomatedSummary(description.quality);
  final reviewSet = reviewSets.single;
  if (description.runId != expected.runId ||
      description.runResultDigest != expected.runResultDigest ||
      description.availability != ScenarioQualityReviewAvailability.available ||
      description.requirementId != expected.requirementId ||
      description.decisionCount != 2 ||
      description.headDecisionDigest != expected.headDecisionDigest ||
      description.quality.humanDecision.state != HumanDecisionState.rejected ||
      Digest.semantic(automated).value != expected.automatedDigest.value ||
      Digest.semantic(reviewSet).value != expected.reviewSetDigest.value ||
      !_scenarioQualityResourceSurfaceMatchesReviewSet(quality, reviewSet)) {
    throw _ScenarioLabAuditBlocked('$phase-quality-binding', <String, Object?>{
      'description': _scenarioQualityDescriptionSummary(description),
      'automatedDigest': Digest.semantic(automated).value,
      'reviewSetDigest': Digest.semantic(reviewSet).value,
    });
  }

  final oldDecisionView = _singleScenarioQualityDecisionView(
    decisionViews,
    decisionDigest: expected.approvedDecisionDigest.value,
    state: HumanDecisionState.superseded,
  );
  final headDecisionView = _singleScenarioQualityDecisionView(
    decisionViews,
    decisionDigest: expected.headDecisionDigest.value,
    state: HumanDecisionState.rejected,
  );
  if (oldDecisionView['recordId'] != expected.approvedRecordId.value ||
      oldDecisionView['supersededByDecisionDigest'] !=
          expected.headDecisionDigest.value ||
      headDecisionView['recordId'] != expected.headRecordId.value ||
      headDecisionView['supersededByDecisionDigest'] != null ||
      !_scenarioQualityAttributionMatches(
        oldDecisionView,
        runId: expected.runId,
        resultDigest: expected.runResultDigest,
        requirementId: expected.requirementId.value,
        policyId: expected.policyId.value,
      ) ||
      !_scenarioQualityAttributionMatches(
        headDecisionView,
        runId: expected.runId,
        resultDigest: expected.runResultDigest,
        requirementId: expected.requirementId.value,
        policyId: expected.policyId.value,
      ) ||
      !_scenarioQualityHistorySurfaceMatches(
        quality,
        approvedDecision: oldDecisionView,
        rejectedDecision: headDecisionView,
      ) ||
      Digest.semantic(<Map<String, Object?>>[
            headDecisionView,
            oldDecisionView,
          ]).value !=
          expected.historyDigest.value) {
    throw _ScenarioLabAuditBlocked('$phase-quality-history', <String, Object?>{
      'head': headDecisionView,
      'old': oldDecisionView,
    });
  }

  final evidence = result.finalSnapshot.requiredEvidence.singleWhere(
    (item) => item.requiredEvidenceId.value == 'dashboard-ready-visual',
  );
  final comparison = result.finalSnapshot.comparisons.singleWhere(
    (item) => item.bindingId.value == 'dashboard-ready-baseline-candidate',
  );
  final artifact = evidence.artifacts.single;
  final labRequests = connection.scenarioLabRequestCounts();
  final labRpc = connection.scenarioLabRpcSummary();
  final reattachRequests = labRequests['lab.reattach'];
  if (evidence.digest != expected.evidenceResultDigest ||
      evidence.evidenceDigest != expected.evidenceDigest ||
      artifact.artifactDigest != expected.artifactDigest ||
      artifact.provenanceDigest != expected.provenanceDigest ||
      comparison.digest != expected.comparisonResultDigest ||
      labRequests.length != 1 ||
      reattachRequests is! int ||
      reattachRequests < 1 ||
      reattachRequests > 20 ||
      !_sameJson(labRpc['requestsByMethod'], labRpc['resultsByMethod']) ||
      (labRpc['failures'] as List<Object?>).isNotEmpty) {
    throw _ScenarioLabAuditBlocked('$phase-reattach-binding', <String, Object?>{
      'observation': _scenarioLabObservationSummary(observation),
      'labRpc': labRpc,
    });
  }

  return _ScenarioQualityRecoveryProof(
    quality: quality,
    automated: automated,
    reviewSet: reviewSet,
    oldDecisionView: oldDecisionView,
    headDecisionView: headDecisionView,
    result: result,
  );
}

bool _scenarioQualityReattachActionReady(
  Map<String, Object?> surface,
  ScenarioLabRunId runId,
) =>
    surface['path'] == _scenarioQualityPath &&
    surface['queryRunId'] == runId.value &&
    surface['routeState'] == 'ready' &&
    surface['qualitySelectedRunId'] == runId.value &&
    surface['controlSelectedRunId'] == runId.value &&
    surface['actionsState'] == 'ready' &&
    _sameJson(surface['actions'], const <Object?>['reattach']) &&
    surface['reattachCount'] == 1 &&
    surface['reattachEnabled'] == true;

void _requireScenarioQualityAwaitingExplicitReattach(
  _CdpConnection connection,
  Map<String, Object?> surface,
  ScenarioLabRunId runId, {
  required String phase,
}) {
  _requireScenarioQualityRpcCounts(
    connection,
    phase: '$phase-quality-rpc',
    describe: 0,
    open: 0,
    grant: 0,
    append: 0,
    get: 0,
  );
  final labRequests = connection.scenarioLabRequestCounts();
  final labRpc = connection.scenarioLabRpcSummary();
  if (!_scenarioQualityReattachActionReady(surface, runId) ||
      surface['lifecycle'] != 'detached' ||
      surface['qualityRunId'] != null ||
      surface['qualityResultDigest'] != null ||
      surface['decisionOperation'] != 'detached' ||
      labRequests.isNotEmpty ||
      (labRpc['failures'] as List<Object?>).isNotEmpty) {
    throw _ScenarioLabAuditBlocked(phase, <String, Object?>{
      'surface': surface,
      'labRpc': labRpc,
    });
  }
}

Map<String, Object?> _jsonMapSnapshot(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value)) as Map<Object?, Object?>).cast();

Map<String, Object?> _scenarioLabRelaySummary(Map<String, Object?> relay) =>
    <String, Object?>{
      'relayCount': relay['relayCount'],
      'boundRelayCount': relay['boundRelayCount'],
      'iframeCount': relay['iframeCount'],
      'scopedIframeCount': relay['scopedIframeCount'],
      'runId': relay['runId'],
      'relayState': relay['relayState'],
      'targetId': relay['targetId'],
      'launchProfileId': relay['launchProfileId'],
      'launchAttemptId': relay['launchAttemptId'],
      'aboutBlank': relay['aboutBlank'],
      'gatewayBindingDeclared': relay['gatewayBindingDeclared'],
      'gatewayBound': relay['gatewayBound'],
    };

Map<String, Object?> _scenarioLabSurfaceSummary(Map<String, Object?> surface) =>
    <String, Object?>{
      'path': surface['path'],
      'routeState': surface['routeState'],
      'runCapability': surface['runCapability'],
      'relayCapability': surface['relayCapability'],
      'actionsState': surface['actionsState'],
      'lifecycle': surface['lifecycle'],
      'failure': surface['failure'],
      'selectedRunId': surface['selectedRunId'],
      'queryRunId': surface['queryRunId'],
      'runPanelId': surface['runPanelId'],
      'runPanelState': surface['runPanelState'],
      'resultDigest': surface['resultDigest'],
      'startButtonCount': surface['startButtonCount'],
      'startEnabled': surface['startEnabled'],
      'cancelButtonCount': surface['cancelButtonCount'],
      'cancelEnabled': surface['cancelEnabled'],
      'relayRecoveryButtonCount': surface['relayRecoveryButtonCount'],
      'relayRecoveryEnabled': surface['relayRecoveryEnabled'],
      'relayCount': surface['relayCount'],
      'relayState': surface['relayState'],
      'relayFailure': surface['relayFailure'],
      'iframeCount': surface['iframeCount'],
    };

bool _scenarioLabGatewayProofIsValid(Map<String, Object?> proof) =>
    proof['childNavigationScrubbed'] == true &&
    proof['targetFrameBound'] == true &&
    proof['relayV2Ready'] == true &&
    proof['relayV2Fenced'] == true &&
    proof['mountAuthorized'] == true &&
    proof['helloAccepted'] == true &&
    proof['relayResultsAccepted'] == true &&
    (proof['relayResultCount'] as int? ?? 0) > 0 &&
    proof['networkTraceComplete'] == true &&
    proof['gatewayRequestBound'] == true &&
    proof['gatewayRequestCount'] == 1 &&
    proof['gatewaySuccessfulResponseCount'] == 1 &&
    proof['directApiRequestCount'] == 0 &&
    proof['gatewayTrafficObserved'] == true &&
    proof['gatewayTrafficSucceeded'] == true &&
    proof['gatewayBound'] == true &&
    proof['gatewayRouted'] == true &&
    proof['controllerBound'] == true &&
    (proof['targetPort'] as int? ?? 0) >= 1 &&
    (proof['targetPort'] as int? ?? 0) <= 65535 &&
    (proof['gatewayPort'] as int? ?? 0) >= 1 &&
    (proof['gatewayPort'] as int? ?? 0) <= 65535;

Map<String, Object?> _scenarioLabObservationSummary(
  ScenarioLabRunObservation observation,
) {
  final snapshot = observation.current;
  final result = observation.result;
  return <String, Object?>{
    'runId': observation.runId.value,
    'disposition': observation.disposition.name,
    'sequence': snapshot.sequence,
    'state': snapshot.state.name,
    'terminalCause': snapshot.terminalCause?.name,
    'snapshotDigest': snapshot.digest.value,
    'cleanup': snapshot.cleanup.state.name,
    'steps': <Object?>[
      for (final step in snapshot.steps)
        <String, Object?>{
          'stepId': step.stepId,
          'state': step.state.name,
          'terminalCause': step.terminalCause?.name,
          if (step.startedAt != null)
            'startedAt': step.startedAt!.toIso8601String(),
          if (step.completedAt != null)
            'completedAt': step.completedAt!.toIso8601String(),
        },
    ],
    'requiredEvidence': <Object?>[
      for (final item in snapshot.requiredEvidence)
        <String, Object?>{
          'requiredEvidenceId': item.requiredEvidenceId.value,
          'providerId': item.providerId.value,
          'state': item.state.name,
          'freshness': item.freshness.name,
          'artifactCount': item.artifacts.length,
          'artifacts': <Object?>[
            for (final artifact in item.artifacts)
              <String, Object?>{
                'artifactDigest': artifact.artifactDigest.value,
                'provenanceDigest': artifact.provenanceDigest.value,
                'classification': artifact.classification.name,
              },
          ],
        },
    ],
    'comparisonCount': snapshot.comparisons.length,
    'controlCount': snapshot.controls.length,
    'verification': result?.verificationState.name,
    'resultDigest': result?.digest.value,
  };
}

bool _scenarioQualityReviewReady(
  Map<String, Object?> surface, {
  required ScenarioLabRunId runId,
  required int decisionCount,
  required HumanDecisionState humanDecision,
  required String enabledAction,
}) {
  final resources = surface['resources'];
  final history = surface['history'];
  if (surface['path'] != _scenarioQualityPath ||
      surface['queryRunId'] != runId.value ||
      surface['runId'] != runId.value ||
      surface['routeState'] != 'ready' ||
      surface['reviewAvailability'] !=
          ScenarioQualityReviewAvailability.available.name ||
      surface['decisionOperation'] != 'ready' ||
      surface['decisionCount'] != decisionCount ||
      surface['humanDecision'] != humanDecision.name ||
      surface['decisionRequirement'] is! String ||
      surface['reviewGuide'] != 'pinned' ||
      surface['reviewInstruction'] != true ||
      surface['reviewCriteria'] != true ||
      surface['confirmationCount'] != 0 ||
      resources is! List<Object?> ||
      resources.length != 3 ||
      history is! List<Object?> ||
      history.length != decisionCount ||
      !_scenarioQualityActionEnabled(surface, enabledAction)) {
    return false;
  }
  if (decisionCount == 0) {
    if (surface['headDecisionDigest'] != null) return false;
  } else if (surface['headDecisionDigest'] is! String ||
      surface['decisionPolicy'] is! String) {
    return false;
  }
  final roles = <String>{};
  for (final value in resources) {
    if (value is! Map<String, Object?> ||
        value['state'] != 'rendered' ||
        value['role'] is! String ||
        value['artifactDigest'] is! String ||
        value['provenanceKind'] is! String) {
      return false;
    }
    roles.add(value['role']! as String);
  }
  return roles.length == 3 &&
      roles.containsAll(const <String>{
        'requiredEvidence',
        'comparisonBaseline',
        'comparisonCandidate',
      });
}

bool _scenarioQualityConfirmationReady(
  Map<String, Object?> surface,
  ScenarioLabRunId runId,
) =>
    surface['path'] == _scenarioQualityPath &&
    surface['queryRunId'] == runId.value &&
    surface['runId'] == runId.value &&
    surface['decisionOperation'] == 'ready' &&
    surface['confirmationCount'] == 1 &&
    surface['confirmationNative'] == true &&
    surface['confirmationModal'] == 'true' &&
    surface['confirmationLabelledBy'] ==
        'scenario-quality-decision-confirmation-title' &&
    surface['confirmationDescribedBy'] ==
        'scenario-quality-decision-confirmation-description' &&
    surface['confirmationTitle'] == 'Confirmar decisão humana?' &&
    surface['confirmationDescription'] is String &&
    surface['focusedAction'] == 'confirm' &&
    _scenarioQualityActionEnabled(surface, 'confirm') &&
    _scenarioQualityActionEnabled(surface, 'cancel');

bool _scenarioQualityActionEnabled(
  Map<String, Object?> surface,
  String action,
) {
  final actions = surface['actions'];
  if (actions is! List<Object?>) return false;
  return actions.whereType<Map<String, Object?>>().any(
    (item) => item['action'] == action && item['enabled'] == true,
  );
}

void _requireScenarioQualityAutomatedSurface(
  Map<String, Object?> quality, {
  required ScenarioLabRunId runId,
  required ScenarioLabRunResult result,
  required String phase,
}) {
  final qualityStates = quality['states'];
  if (quality['path'] != _scenarioQualityPath ||
      quality['queryRunId'] != runId.value ||
      quality['runId'] != runId.value ||
      quality['resultDigest'] != result.digest.value ||
      quality['verification'] != VerificationState.passed.name ||
      quality['evidenceState'] != RequiredEvidenceResultState.collected.name ||
      quality['evidenceFreshness'] != EvidenceFreshness.fresh.name ||
      quality['evidenceVerification'] != VerificationState.passed.name ||
      quality['comparisonState'] != VerificationState.passed.name ||
      quality['comparisonKind'] != ScenarioComparisonResultKind.visual.name ||
      qualityStates is! List<Object?> ||
      !qualityStates.contains('passing') ||
      qualityStates.contains('unverified') ||
      qualityStates.contains('missing') ||
      qualityStates.contains('unsupported') ||
      qualityStates.contains('policyDenied')) {
    throw _ScenarioLabAuditBlocked(phase, quality);
  }
}

Map<String, Object?> _scenarioQualityAutomatedSurface(
  Map<String, Object?> quality,
) => <String, Object?>{
  'path': quality['path'],
  'queryRunId': quality['queryRunId'],
  'runId': quality['runId'],
  'resultDigest': quality['resultDigest'],
  'verification': quality['verification'],
  'states': quality['states'],
  'evidenceState': quality['evidenceState'],
  'evidenceFreshness': quality['evidenceFreshness'],
  'evidenceVerification': quality['evidenceVerification'],
  'comparisonState': quality['comparisonState'],
  'comparisonKind': quality['comparisonKind'],
  'comparisonChangedUnits': quality['comparisonChangedUnits'],
};

Map<String, Object?> _scenarioQualityAutomatedSummary(
  ScenarioQualitySnapshot quality,
) => <String, Object?>{
  'runId': quality.runId.value,
  'subjectDigest': quality.subjectDigest.value,
  'scenarioId': quality.scenarioId.value,
  'verification': quality.verificationState.name,
  'requiredEvidence': <Object?>[
    for (final item in quality.requiredEvidence)
      <String, Object?>{
        'requiredEvidenceId': item.requiredEvidenceId.value,
        'resultDigest': item.resultDigest.value,
        'verification': item.verificationState.name,
      },
  ],
  'comparisonResultDigests': <String>[
    for (final digest in quality.comparisonResultDigests) digest.value,
  ],
};

Map<String, Object?> _scenarioQualityDescriptionSummary(
  ScenarioQualityDescription description,
) => <String, Object?>{
  'runId': description.runId.value,
  'runResultDigest': description.runResultDigest.value,
  'availability': description.availability.name,
  'requirementId': description.requirementId?.value,
  'headDecisionDigest': description.headDecisionDigest?.value,
  'decisionCount': description.decisionCount,
  'humanDecision': description.quality.humanDecision.state.name,
  'automatedDigest': Digest.semantic(
    _scenarioQualityAutomatedSummary(description.quality),
  ).value,
};

void _requireScenarioQualityRpcCounts(
  _CdpConnection connection, {
  required String phase,
  required int describe,
  required int open,
  required int grant,
  required int append,
  required int get,
}) {
  final expected = <String, Object?>{
    'quality.describe': describe,
    'quality.open': open,
    'quality.decision.grant': grant,
    'quality.decision.append': append,
    'quality.decision.get': get,
  };
  final summary = connection.scenarioQualityRpcSummary();
  if (!_sameJson(summary['requestsByMethod'], expected) ||
      !_sameJson(summary['resultsByMethod'], expected) ||
      (summary['failures'] as List<Object?>).isNotEmpty) {
    throw _ScenarioLabAuditBlocked(phase, summary);
  }
}

Map<String, Object?> _singleScenarioQualityDecisionView(
  List<Map<String, Object?>> views, {
  required String decisionDigest,
  required HumanDecisionState state,
}) {
  final matches = views
      .where(
        (item) =>
            item['decisionDigest'] == decisionDigest &&
            item['state'] == state.name,
      )
      .toList(growable: false);
  if (matches.length != 1) {
    throw _ScenarioLabAuditBlocked('quality-decision-view', <String, Object?>{
      'decisionDigest': decisionDigest,
      'state': state.name,
      'matchingCount': matches.length,
    });
  }
  return matches.single;
}

bool _scenarioQualityAttributionMatches(
  Map<String, Object?> decision, {
  required ScenarioLabRunId runId,
  required Digest resultDigest,
  String? requirementId,
  String? policyId,
}) {
  final attribution = decision['attribution'];
  if (attribution is! Map<String, Object?>) return false;
  return attribution['runId'] == runId.value &&
      attribution['runResultDigest'] == resultDigest.value &&
      attribution['requirementScope'] == HumanApprovalScope.evidenceSet.name &&
      attribution['role'] == ScenarioQualityDecisionRole.reviewer.name &&
      attribution['requirementId'] is String &&
      attribution['accessPolicyId'] is String &&
      attribution['authorityId'] is String &&
      attribution['principalId'] is String &&
      attribution['reviewGuideId'] is String &&
      attribution['reviewGuideStepId'] is String &&
      (requirementId == null ||
          attribution['requirementId'] == requirementId) &&
      (policyId == null || attribution['accessPolicyId'] == policyId);
}

bool _scenarioQualityHistorySurfaceMatches(
  Map<String, Object?> surface, {
  required Map<String, Object?> approvedDecision,
  required Map<String, Object?> rejectedDecision,
}) {
  final history = surface['history'];
  final approvedAttribution = approvedDecision['attribution'];
  final rejectedAttribution = rejectedDecision['attribution'];
  if (history is! List<Object?> ||
      approvedAttribution is! Map<String, Object?> ||
      rejectedAttribution is! Map<String, Object?>) {
    return false;
  }
  final entries = history.whereType<Map<String, Object?>>().toList();
  if (entries.length != 2) return false;
  final approved = entries.where(
    (item) => item['recordId'] == approvedDecision['recordId'],
  );
  final rejected = entries.where(
    (item) => item['recordId'] == rejectedDecision['recordId'],
  );
  if (approved.length != 1 || rejected.length != 1) return false;
  return approved.single['humanDecision'] ==
          HumanDecisionState.superseded.name &&
      approved.single['supersededByDecisionDigest'] ==
          rejectedDecision['decisionDigest'] &&
      approved.single['decisionPolicy'] ==
          approvedAttribution['accessPolicyId'] &&
      approved.single['decisionRequirement'] ==
          approvedAttribution['requirementId'] &&
      rejected.single['humanDecision'] == HumanDecisionState.rejected.name &&
      rejected.single['supersededByDecisionDigest'] == null &&
      rejected.single['decisionPolicy'] ==
          rejectedAttribution['accessPolicyId'] &&
      rejected.single['decisionRequirement'] ==
          rejectedAttribution['requirementId'];
}

bool _scenarioQualityResourceSurfaceMatchesReviewSet(
  Map<String, Object?> surface,
  Map<String, Object?> reviewSet,
) {
  final resources = surface['resources'];
  final artifacts = reviewSet['artifacts'];
  if (resources is! List<Object?> || artifacts is! List<Object?>) return false;

  List<Map<String, Object?>> normalized(
    List<Object?> values, {
    required bool includeState,
  }) {
    final result = <Map<String, Object?>>[];
    for (final value in values) {
      if (value is! Map<String, Object?>) return const [];
      final role = value['role'];
      final artifactDigest = value['artifactDigest'];
      final provenanceKind = value['provenanceKind'];
      if (role is! String ||
          artifactDigest is! String ||
          provenanceKind is! String ||
          (includeState && value['state'] != 'rendered')) {
        return const [];
      }
      result.add(<String, Object?>{
        'role': role,
        'artifactDigest': artifactDigest,
        'provenanceKind': provenanceKind,
      });
    }
    result.sort((left, right) => jsonEncode(left).compareTo(jsonEncode(right)));
    return result;
  }

  final rendered = normalized(resources, includeState: true);
  final described = normalized(artifacts, includeState: false);
  return rendered.length == 3 && _sameJson(rendered, described);
}

bool _sameJson(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);

final class _ScenarioQualityReloadExpectation {
  const _ScenarioQualityReloadExpectation({
    required this.runId,
    required this.runResultDigest,
    required this.snapshotDigest,
    required this.evidenceResultDigest,
    required this.evidenceDigest,
    required this.artifactDigest,
    required this.provenanceDigest,
    required this.comparisonResultDigest,
    required this.automatedDigest,
    required this.qualitySurfaceDigest,
    required this.reviewSetDigest,
    required this.approvedDecisionDigest,
    required this.approvedRecordId,
    required this.headDecisionDigest,
    required this.headRecordId,
    required this.historyDigest,
    required this.requirementId,
    required this.policyId,
  });

  factory _ScenarioQualityReloadExpectation.decode(String source) {
    if (source.isEmpty || source.length > 32 * 1024) {
      throw ArgumentError(
        '--scenario-quality-reload-audit has an invalid size',
      );
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Scenario Quality reload expectation must be an object',
      );
    }
    const keys = <String>{
      'runId',
      'runResultDigest',
      'snapshotDigest',
      'evidenceResultDigest',
      'evidenceDigest',
      'artifactDigest',
      'provenanceDigest',
      'comparisonResultDigest',
      'automatedDigest',
      'qualitySurfaceDigest',
      'reviewSetDigest',
      'approvedDecisionDigest',
      'approvedRecordId',
      'headDecisionDigest',
      'headRecordId',
      'historyDigest',
      'requirementId',
      'policyId',
    };
    if (decoded.length != keys.length ||
        !decoded.keys.toSet().containsAll(keys)) {
      throw const FormatException(
        'Scenario Quality reload expectation is not closed',
      );
    }
    String field(String name) {
      final value = decoded[name];
      if (value is! String) {
        throw FormatException('Scenario Quality reload $name is invalid');
      }
      return value;
    }

    return _ScenarioQualityReloadExpectation(
      runId: ScenarioLabRunId(field('runId')),
      runResultDigest: Digest(field('runResultDigest')),
      snapshotDigest: Digest(field('snapshotDigest')),
      evidenceResultDigest: Digest(field('evidenceResultDigest')),
      evidenceDigest: Digest(field('evidenceDigest')),
      artifactDigest: Digest(field('artifactDigest')),
      provenanceDigest: Digest(field('provenanceDigest')),
      comparisonResultDigest: Digest(field('comparisonResultDigest')),
      automatedDigest: Digest(field('automatedDigest')),
      qualitySurfaceDigest: Digest(field('qualitySurfaceDigest')),
      reviewSetDigest: Digest(field('reviewSetDigest')),
      approvedDecisionDigest: Digest(field('approvedDecisionDigest')),
      approvedRecordId: HumanDecisionRecordId(field('approvedRecordId')),
      headDecisionDigest: Digest(field('headDecisionDigest')),
      headRecordId: HumanDecisionRecordId(field('headRecordId')),
      historyDigest: Digest(field('historyDigest')),
      requirementId: HumanApprovalRequirementId(field('requirementId')),
      policyId: ScenarioQualityAccessPolicyId(field('policyId')),
    );
  }

  final ScenarioLabRunId runId;
  final Digest runResultDigest;
  final Digest snapshotDigest;
  final Digest evidenceResultDigest;
  final Digest evidenceDigest;
  final Digest artifactDigest;
  final Digest provenanceDigest;
  final Digest comparisonResultDigest;
  final Digest automatedDigest;
  final Digest qualitySurfaceDigest;
  final Digest reviewSetDigest;
  final Digest approvedDecisionDigest;
  final HumanDecisionRecordId approvedRecordId;
  final Digest headDecisionDigest;
  final HumanDecisionRecordId headRecordId;
  final Digest historyDigest;
  final HumanApprovalRequirementId requirementId;
  final ScenarioQualityAccessPolicyId policyId;
}

final class _ScenarioCurrentnessExpectation {
  const _ScenarioCurrentnessExpectation({
    required this.oldRunId,
    required this.oldRunResultDigest,
    required this.oldSnapshotDigest,
    required this.oldContentSetDigest,
    required this.oldCatalogDigest,
    required this.oldScenarioLabManifestDigest,
    required this.oldEvidenceResultDigest,
    required this.oldEvidenceDigest,
    required this.oldArtifactDigest,
    required this.oldProvenanceDigest,
    required this.oldComparisonResultDigest,
    required this.oldComparedPixels,
    required this.oldChangedPixels,
    required this.oldMaxChannelDeltaObserved,
    required this.currentContentSetDigest,
    required this.currentCatalogDigest,
    required this.currentScenarioLabManifestDigest,
  });

  factory _ScenarioCurrentnessExpectation.decode(String source) {
    if (source.isEmpty || source.length > 16 * 1024) {
      throw ArgumentError('--scenario-currentness-audit has an invalid size');
    }
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Scenario currentness expectation must be an object',
      );
    }
    const keys = <String>{
      'oldRunId',
      'oldRunResultDigest',
      'oldSnapshotDigest',
      'oldContentSetDigest',
      'oldCatalogDigest',
      'oldScenarioLabManifestDigest',
      'oldEvidenceResultDigest',
      'oldEvidenceDigest',
      'oldArtifactDigest',
      'oldProvenanceDigest',
      'oldComparisonResultDigest',
      'oldComparedPixels',
      'oldChangedPixels',
      'oldMaxChannelDeltaObserved',
      'currentContentSetDigest',
      'currentCatalogDigest',
      'currentScenarioLabManifestDigest',
    };
    if (decoded.length != keys.length ||
        !decoded.keys.toSet().containsAll(keys)) {
      throw const FormatException(
        'Scenario currentness expectation is not closed',
      );
    }
    String field(String name) {
      final value = decoded[name];
      if (value is! String) {
        throw FormatException('Scenario currentness $name is invalid');
      }
      return value;
    }

    int integer(String name) {
      final value = decoded[name];
      if (value is! int || value < 0 || value > 1000000000) {
        throw FormatException('Scenario currentness $name is invalid');
      }
      return value;
    }

    final oldComparedPixels = integer('oldComparedPixels');
    final oldChangedPixels = integer('oldChangedPixels');
    final oldMaxChannelDeltaObserved = integer('oldMaxChannelDeltaObserved');
    if (oldComparedPixels < 1 ||
        oldChangedPixels > oldComparedPixels ||
        oldMaxChannelDeltaObserved > 255) {
      throw const FormatException(
        'Scenario currentness historical visual metrics are invalid',
      );
    }

    return _ScenarioCurrentnessExpectation(
      oldRunId: ScenarioLabRunId(field('oldRunId')),
      oldRunResultDigest: Digest(field('oldRunResultDigest')),
      oldSnapshotDigest: Digest(field('oldSnapshotDigest')),
      oldContentSetDigest: Digest(field('oldContentSetDigest')),
      oldCatalogDigest: Digest(field('oldCatalogDigest')),
      oldScenarioLabManifestDigest: Digest(
        field('oldScenarioLabManifestDigest'),
      ),
      oldEvidenceResultDigest: Digest(field('oldEvidenceResultDigest')),
      oldEvidenceDigest: Digest(field('oldEvidenceDigest')),
      oldArtifactDigest: Digest(field('oldArtifactDigest')),
      oldProvenanceDigest: Digest(field('oldProvenanceDigest')),
      oldComparisonResultDigest: Digest(field('oldComparisonResultDigest')),
      oldComparedPixels: oldComparedPixels,
      oldChangedPixels: oldChangedPixels,
      oldMaxChannelDeltaObserved: oldMaxChannelDeltaObserved,
      currentContentSetDigest: Digest(field('currentContentSetDigest')),
      currentCatalogDigest: Digest(field('currentCatalogDigest')),
      currentScenarioLabManifestDigest: Digest(
        field('currentScenarioLabManifestDigest'),
      ),
    );
  }

  final ScenarioLabRunId oldRunId;
  final Digest oldRunResultDigest;
  final Digest oldSnapshotDigest;
  final Digest oldContentSetDigest;
  final Digest oldCatalogDigest;
  final Digest oldScenarioLabManifestDigest;
  final Digest oldEvidenceResultDigest;
  final Digest oldEvidenceDigest;
  final Digest oldArtifactDigest;
  final Digest oldProvenanceDigest;
  final Digest oldComparisonResultDigest;
  final int oldComparedPixels;
  final int oldChangedPixels;
  final int oldMaxChannelDeltaObserved;
  final Digest currentContentSetDigest;
  final Digest currentCatalogDigest;
  final Digest currentScenarioLabManifestDigest;
}

Future<Map<String, Object?>> _driveScenarioLabToTerminal(
  _CdpConnection connection,
  ScenarioLabRunId runId,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final surface = await connection.scenarioLabSurface();
    if (surface['selectedRunId'] != runId.value ||
        surface['queryRunId'] != runId.value) {
      throw _ScenarioLabAuditBlocked('run-fence', surface);
    }
    if (surface['lifecycle'] == 'terminal') {
      if (connection.scenarioLabRpcHasFailures) {
        throw _ScenarioLabAuditBlocked(
          'terminal-rpc-failure',
          connection.scenarioLabRpcSummary(),
        );
      }
      if (connection.scenarioLabRpcSettled) return surface;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      continue;
    }
    if (const <String>{
      'failed',
      'unavailable',
      'closed',
    }.contains(surface['lifecycle'])) {
      throw _ScenarioLabAuditBlocked('run-lifecycle', <String, Object?>{
        'surface': surface,
        'rpc': connection.scenarioLabRpcSummary(),
      });
    }
    await connection.clickScenarioLabRunActionIfEnabled('reattach');
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
  throw _ScenarioLabAuditBlocked('terminal-timeout', <String, Object?>{
    'surface': await connection.scenarioLabSurface(),
    'rpc': connection.scenarioLabRpcSummary(),
  });
}

final class _ScenarioLabAuditBlocked implements Exception {
  const _ScenarioLabAuditBlocked(this.phase, this.details);

  final String phase;
  final Object? details;

  @override
  String toString() =>
      'ScenarioLabAuditBlocked[$phase]: ${jsonEncode(details)}';
}

final class _ProbeTimeout implements Exception {
  const _ProbeTimeout(this.description);

  final String description;
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
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await condition()) return;
    } on Object {
      // A transient DOM/RPC observation is retried until the bounded deadline.
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw _ProbeTimeout(description);
}

final class _ChromeTarget {
  const _ChromeTarget({required this.id, required this.webSocketUri});

  final String id;
  final Uri webSocketUri;
}

final class _ScenarioLabChildFrameNavigation {
  const _ScenarioLabChildFrameNavigation({
    required this.frameId,
    required this.scheme,
    required this.host,
    required this.port,
    required this.path,
    required this.queryAbsent,
    required this.fragmentAbsent,
    required this.userInfoAbsent,
  });

  static _ScenarioLabChildFrameNavigation? tryParse({
    required String frameId,
    required String rawUrl,
  }) {
    final value = Uri.tryParse(rawUrl);
    if (frameId.isEmpty || frameId.length > 512 || value == null) return null;
    return _ScenarioLabChildFrameNavigation(
      frameId: frameId,
      scheme: value.scheme,
      host: value.host,
      port: value.hasPort ? value.port : null,
      path: value.path,
      queryAbsent: !value.hasQuery,
      fragmentAbsent: !value.hasFragment,
      userInfoAbsent: value.userInfo.isEmpty,
    );
  }

  final String frameId;
  final String scheme;
  final String host;
  final int? port;
  final String path;
  final bool queryAbsent;
  final bool fragmentAbsent;
  final bool userInfoAbsent;

  bool get isHttp => const <String>{'http', 'https'}.contains(scheme);

  bool isScrubbedNavigationTo(ScenarioLabRelayTargetDescriptor descriptor) {
    final target = descriptor.origin;
    return scheme == target.scheme &&
        host == target.host &&
        port == target.port &&
        (path.isEmpty || path == '/') &&
        queryAbsent &&
        fragmentAbsent &&
        userInfoAbsent;
  }
}

final class _ScenarioLabNetworkLocation {
  const _ScenarioLabNetworkLocation({
    required this.scheme,
    required this.host,
    required this.port,
    required this.path,
    required this.userInfoAbsent,
    required this.fragmentAbsent,
    required this.exactReadyStateQuery,
  });

  static _ScenarioLabNetworkLocation? tryParse(String rawUrl) {
    final value = Uri.tryParse(rawUrl);
    if (value == null) return null;
    final query = value.queryParametersAll;
    final stateValues = query['state'];
    return _ScenarioLabNetworkLocation(
      scheme: value.scheme,
      host: value.host,
      port: value.hasPort ? value.port : null,
      path: value.path,
      userInfoAbsent: value.userInfo.isEmpty,
      fragmentAbsent: !value.hasFragment,
      exactReadyStateQuery:
          query.length == 1 &&
          stateValues != null &&
          stateValues.length == 1 &&
          stateValues.single == 'ready',
    );
  }

  final String scheme;
  final String host;
  final int? port;
  final String path;
  final bool userInfoAbsent;
  final bool fragmentAbsent;
  final bool exactReadyStateQuery;

  bool isGatewayDashboard(Uri gateway) =>
      scheme == gateway.scheme &&
      host == gateway.host &&
      port == gateway.port &&
      userInfoAbsent &&
      path == '/v1/dashboard' &&
      fragmentAbsent &&
      exactReadyStateQuery;

  bool get isDirectApiDashboard =>
      scheme == 'http' &&
      const <String>{'127.0.0.1', '::1', 'localhost'}.contains(host) &&
      port == 8181 &&
      path == '/v1/dashboard';

  bool sameResourceAs(_ScenarioLabNetworkLocation other) =>
      scheme == other.scheme &&
      host == other.host &&
      port == other.port &&
      path == other.path &&
      userInfoAbsent == other.userInfoAbsent &&
      fragmentAbsent == other.fragmentAbsent &&
      exactReadyStateQuery == other.exactReadyStateQuery;
}

final class _ScenarioLabNetworkRequest {
  const _ScenarioLabNetworkRequest({
    required this.location,
    required this.method,
    required this.frameId,
    required this.initiatorType,
  });

  final _ScenarioLabNetworkLocation location;
  final String method;
  final String? frameId;
  final String? initiatorType;
}

final class _ScenarioLabNetworkResponse {
  const _ScenarioLabNetworkResponse({
    required this.location,
    required this.status,
  });

  final _ScenarioLabNetworkLocation location;
  final num status;

  bool get succeeded => status >= 200 && status < 300;
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
  final Map<String, _ScenarioLabNetworkRequest> _scenarioLabNetworkRequests =
      <String, _ScenarioLabNetworkRequest>{};
  final Map<String, _ScenarioLabNetworkResponse> _scenarioLabNetworkResponses =
      <String, _ScenarioLabNetworkResponse>{};
  final Set<String> _scenarioLabAmbiguousNetworkRequestIds = <String>{};
  bool _scenarioLabNetworkTraceOverflowed = false;
  final Map<String, String> _scenarioLabPendingRpc = <String, String>{};
  final Map<String, ScenarioLabRelayDescribeRequestV2>
  _scenarioLabRelayV2PendingRequests =
      <String, ScenarioLabRelayDescribeRequestV2>{};
  final List<(ScenarioLabRelayDescribeRequestV2, ScenarioLabRelayDescriptionV2)>
  _scenarioLabRelayV2Exchanges =
      <(ScenarioLabRelayDescribeRequestV2, ScenarioLabRelayDescriptionV2)>[];
  final Map<String, ScenarioLabRelayHelloSubmission>
  _scenarioLabRelayHelloPendingRequests =
      <String, ScenarioLabRelayHelloSubmission>{};
  final List<
    (ScenarioLabRelayHelloSubmission, ScenarioLabRelayHelloAcknowledgement)
  >
  _scenarioLabRelayHelloExchanges =
      <
        (ScenarioLabRelayHelloSubmission, ScenarioLabRelayHelloAcknowledgement)
      >[];
  final Map<String, ScenarioLabRelayResultSubmission>
  _scenarioLabRelayResultPendingRequests =
      <String, ScenarioLabRelayResultSubmission>{};
  final List<
    (ScenarioLabRelayResultSubmission, ScenarioLabRelayResultAcknowledgement)
  >
  _scenarioLabRelayResultExchanges =
      <
        (
          ScenarioLabRelayResultSubmission,
          ScenarioLabRelayResultAcknowledgement,
        )
      >[];
  final Set<String> _scenarioLabChildFrameIds = <String>{};
  final List<_ScenarioLabChildFrameNavigation>
  _scenarioLabChildFrameNavigations = <_ScenarioLabChildFrameNavigation>[];
  final Map<String, String> _scenarioLabRelayFrameIds = <String, String>{};
  final Set<String> _scenarioLabAmbiguousRelayFrameRuns = <String>{};
  final Map<String, int> _scenarioLabRpcCounts = <String, int>{};
  final Map<String, int> _scenarioLabRpcResultCounts = <String, int>{};
  final List<Map<String, Object?>> _scenarioLabRpcFailures =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> _scenarioLabRelayResults =
      <Map<String, Object?>>[];
  final List<(String, Map<String, Object?>)> _scenarioLabRunResults =
      <(String, Map<String, Object?>)>[];
  final List<Map<String, Object?>> _scenarioLabSurfaceHistory =
      <Map<String, Object?>>[];
  final Map<String, String> _scenarioQualityPendingRpc = <String, String>{};
  final Map<String, int> _scenarioQualityRpcCounts = <String, int>{};
  final Map<String, int> _scenarioQualityRpcResultCounts = <String, int>{};
  final List<Map<String, Object?>> _scenarioQualityRpcFailures =
      <Map<String, Object?>>[];
  final List<ScenarioQualityDescribeResult> _scenarioQualityDescriptions =
      <ScenarioQualityDescribeResult>[];
  final List<Map<String, Object?>> _scenarioQualityReviewSetResults =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> _scenarioQualityAppendResultSummaries =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> _scenarioQualityDecisionViewSummaries =
      <Map<String, Object?>>[];
  final Set<String> _scenarioLabControlStates = <String>{};
  final Map<String, Digest> _scenarioLabControlScreenshots = <String, Digest>{};
  final List<String> _scenarioLabControlCaptureErrors = <String>[];
  final List<Future<void>> _scenarioLabControlCaptures = <Future<void>>[];
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

  Future<void> clickScenarioLabRunAction(String action) async {
    if (!const <String>{
      'start',
      'reattach',
      'cancel',
      'relay',
    }.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    final clicked = await evaluate<bool>('''
(() => {
  const action = ${jsonEncode(action)};
  const controls = Array.from(document.querySelectorAll(
    '[data-lab-run-action]'
  )).filter((item) => item.dataset.labRunAction === action);
  if (controls.length !== 1) return false;
  const control = controls[0];
  if (!(control instanceof HTMLButtonElement) || control.disabled) return false;
  control.focus();
  control.click();
  return true;
})()
''');
    if (clicked != true) {
      throw StateError('Scenario Lab action is not available: $action');
    }
  }

  Future<bool> clickScenarioLabRunActionIfEnabled(String action) async {
    if (!const <String>{
      'start',
      'reattach',
      'cancel',
      'relay',
    }.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    return await evaluate<bool>('''
(() => {
  const action = ${jsonEncode(action)};
  const controls = Array.from(document.querySelectorAll(
    '[data-lab-run-action]'
  )).filter((item) => item.dataset.labRunAction === action);
  if (controls.length !== 1) return false;
  const control = controls[0];
  if (!(control instanceof HTMLButtonElement) || control.disabled) return false;
  control.focus();
  control.click();
  return true;
})()
''') ??
        false;
  }

  Future<void> clickSelector(String selector) async {
    final clicked = await evaluate<bool>('''
(() => {
  const element = document.querySelector(${jsonEncode(selector)});
  if (!(element instanceof HTMLElement)) return false;
  element.focus();
  element.click();
  return true;
})()
''');
    if (clicked != true) {
      throw StateError('Element not available: $selector');
    }
  }

  Future<void> navigateToPath(String path) async {
    if (!path.startsWith('/') || path.contains('..')) {
      throw ArgumentError.value(path, 'path');
    }
    final origin = await evaluate<String>('location.origin');
    if (origin == null) throw StateError('Studio origin is unavailable');
    await send('Page.navigate', <String, Object?>{'url': '$origin$path'});
    await _waitFor(
      () async =>
          await evaluate<String>('document.readyState') == 'complete' &&
          await bodyContains('Host conectado'),
      description: 'Studio navigation to $path',
    );
  }

  Future<void> installScenarioLabControlObserver() async {
    await send('Page.addScriptToEvaluateOnNewDocument', <String, Object?>{
      'source': r'''
(() => {
  const marker = 'SCENARIO_LAB_CONTROL:';
  const identifier = 'showcase.control.dashboard-ready-highlight';
  const seen = new Set();
  let scheduled = false;
  const publish = (state) => {
    if (seen.has(state)) return;
    seen.add(state);
    requestAnimationFrame(() => requestAnimationFrame(() => {
      console.debug(`${marker}${state}`);
    }));
  };
  const scan = () => {
    scheduled = false;
    const placeholder = document.querySelector('flt-semantics-placeholder');
    if (placeholder instanceof HTMLElement) placeholder.click();
    const exact = document.querySelector(
      `[flt-semantics-identifier="${identifier}"]`
    );
    const fallback = Array.from(document.querySelectorAll(
      '[aria-label], [aria-valuetext], [role]'
    )).find((element) => {
      const text = [
        element.getAttribute('aria-label'),
        element.getAttribute('aria-valuetext'),
        element.textContent,
      ].filter(Boolean).join(' ');
      return text.includes('Delivery readiness highlight');
    });
    const element = exact ?? fallback;
    if (!element) return;
    const value = [
      element.getAttribute('aria-valuetext'),
      element.getAttribute('aria-label'),
      element.textContent,
    ].filter(Boolean).join(' ').toLowerCase();
    if (/\benabled\b/.test(value)) publish('enabled');
    if (/\bdisabled\b/.test(value)) publish('disabled');
  };
  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(scan);
  };
  new MutationObserver(schedule).observe(document, {
    subtree: true,
    childList: true,
    attributes: true,
    characterData: true,
  });
  addEventListener('DOMContentLoaded', schedule, {once: true});
  schedule();
})();
''',
    });
  }

  Future<Map<String, Object?>> scenarioLabSurface() async {
    final result = _object(
      await evaluate<Object?>(r'''
(() => {
  const controls = document.querySelector('.scenario-lab-run-controls');
  const panel = document.querySelector('.scenario-lab-panel');
  const relay = document.querySelector('.scenario-lab-relay-target');
  const starts = Array.from(document.querySelectorAll(
    '[data-lab-run-action="start"]'
  ));
  const cancels = Array.from(document.querySelectorAll(
    '[data-lab-run-action="cancel"]'
  ));
  const relayRecoveries = Array.from(document.querySelectorAll(
    '[data-lab-run-action="relay"]'
  ));
  const query = new URLSearchParams(location.search);
  return {
    path: location.pathname,
    search: location.search,
    routeState: document.querySelector('[data-lab-route-state]')
      ?.dataset.labRouteState ?? null,
    runCapability: controls?.dataset.labRunCapability ?? null,
    relayCapability: controls?.dataset.labRelayCapability ?? null,
    actionsState: controls?.dataset.labRunActionsState ?? null,
    lifecycle: controls?.dataset.labRunLifecycle ?? null,
    failure: controls?.dataset.labRunFailure ?? null,
    selectedRunId: controls?.dataset.labSelectedRunId ?? null,
    queryRunId: query.get('runId'),
    runPanelId: panel?.dataset.labRunId ?? null,
    runPanelState: panel?.dataset.labRunState ?? null,
    resultDigest: panel?.dataset.labResultDigest ?? null,
    startButtonCount: starts.length,
    startEnabled: starts.length === 1 && !starts[0].disabled,
    cancelButtonCount: cancels.length,
    cancelEnabled: cancels.length === 1 && !cancels[0].disabled,
    relayRecoveryButtonCount: relayRecoveries.length,
    relayRecoveryEnabled: relayRecoveries.length === 1 &&
      relayRecoveries[0] instanceof HTMLButtonElement &&
      !relayRecoveries[0].disabled,
    relayCount: document.querySelectorAll(
      '.scenario-lab-relay-target[data-lab-relay-run-id]'
    ).length,
    relayState: relay?.dataset.labRelayState ?? null,
    relayFailure: relay?.dataset.labRelayFailure ?? null,
    iframeCount: document.querySelectorAll(
      '.scenario-lab-relay-target iframe'
    ).length,
  };
})()
'''),
      'ScenarioLabSurface',
    );
    final sample = <String, Object?>{
      'lifecycle': result['lifecycle'],
      'runPanelState': result['runPanelState'],
      'relayState': result['relayState'],
      'relayFailure': result['relayFailure'],
      'iframeCount': result['iframeCount'],
      'relayRecoveryButtonCount': result['relayRecoveryButtonCount'],
      'relayRecoveryEnabled': result['relayRecoveryEnabled'],
    };
    if (_scenarioLabSurfaceHistory.isEmpty ||
        jsonEncode(_scenarioLabSurfaceHistory.last) != jsonEncode(sample)) {
      if (_scenarioLabSurfaceHistory.length == 128) {
        _scenarioLabSurfaceHistory.removeAt(0);
      }
      _scenarioLabSurfaceHistory.add(sample);
    }
    return result;
  }

  Future<Map<String, Object?>> scenarioLabRelay(ScenarioLabRunId runId) async {
    final relay = _object(
      await evaluate<Object?>('''
(() => {
  const expectedRunId = ${jsonEncode(runId.value)};
  const relays = Array.from(document.querySelectorAll(
    'section.scenario-lab-relay-target'
  ));
  const boundRelays = relays.filter((item) =>
    item.getAttribute('aria-label') === 'Target do Scenario Lab' &&
    item.dataset.labRelayRunId === expectedRunId &&
    item.getAttribute('data-lab-relay-gateway-bound') === 'true'
  );
  const relay = relays.length === 1 && boundRelays.length === 1 &&
    relays[0] === boundRelays[0] ? boundRelays[0] : null;
  const frames = Array.from(document.querySelectorAll(
    '.scenario-lab-relay-target iframe'
  ));
  const scopedFrames = relay === null
    ? []
    : Array.from(relay.querySelectorAll('iframe'));
  const frame = scopedFrames.length === 1 ? scopedFrames[0] : null;
  return {
    relayCount: relays.length,
    boundRelayCount: boundRelays.length,
    iframeCount: frames.length,
    scopedIframeCount: scopedFrames.length,
    runId: relay?.dataset.labRelayRunId ?? null,
    relayState: relay?.dataset.labRelayState ?? null,
    gatewayBindingDeclared: ['true', 'false'].includes(
      relay?.getAttribute('data-lab-relay-gateway-bound')
    ),
    gatewayBound:
      relay?.getAttribute('data-lab-relay-gateway-bound') === 'true',
    targetId: relay?.querySelector('[data-lab-relay-target-id]')
      ?.dataset.labRelayTargetId ?? null,
    launchProfileId: relay?.querySelector('[data-lab-relay-launch-profile-id]')
      ?.dataset.labRelayLaunchProfileId ?? null,
    launchAttemptId: relay?.querySelector('[data-lab-relay-launch-attempt-id]')
      ?.dataset.labRelayLaunchAttemptId ?? null,
    aboutBlank: frame !== null &&
      frame.getAttribute('src') === 'about:blank',
  };
})()
'''),
      'ScenarioLabRelay',
    );
    final relayFrameId = await _scenarioLabExactRelayFrameId(runId);
    if (relayFrameId != null) {
      final previous = _scenarioLabRelayFrameIds[runId.value];
      if (previous == null) {
        _scenarioLabRelayFrameIds[runId.value] = relayFrameId;
      } else if (previous != relayFrameId) {
        _scenarioLabAmbiguousRelayFrameRuns.add(runId.value);
      }
    }
    return relay;
  }

  Future<String?> _scenarioLabExactRelayFrameId(ScenarioLabRunId runId) async {
    final document = await send('DOM.getDocument', const <String, Object?>{
      'depth': 1,
      'pierce': false,
    });
    final root = _object(document['root'], 'DOM.getDocument.root');
    final rootNodeId = root['nodeId'];
    if (rootNodeId is! int) return null;

    final sectionQuery = await send('DOM.querySelectorAll', <String, Object?>{
      'nodeId': rootNodeId,
      'selector': 'section.scenario-lab-relay-target',
    });
    final sectionNodeIds = sectionQuery['nodeIds'];
    if (sectionNodeIds is! List<Object?> ||
        sectionNodeIds.length != 1 ||
        sectionNodeIds.single is! int) {
      return null;
    }
    final sectionNodeId = sectionNodeIds.single! as int;
    final attributeResult = await send('DOM.getAttributes', <String, Object?>{
      'nodeId': sectionNodeId,
    });
    final attributeValues = attributeResult['attributes'];
    if (attributeValues is! List<Object?> || attributeValues.length.isOdd) {
      return null;
    }
    final attributes = <String, String>{};
    for (var index = 0; index < attributeValues.length; index += 2) {
      final name = attributeValues[index];
      final value = attributeValues[index + 1];
      if (name is! String || value is! String) return null;
      attributes[name] = value;
    }
    if (attributes['aria-label'] != 'Target do Scenario Lab' ||
        attributes['data-lab-relay-run-id'] != runId.value ||
        attributes['data-lab-relay-gateway-bound'] != 'true') {
      return null;
    }

    final frameQuery = await send('DOM.querySelectorAll', <String, Object?>{
      'nodeId': sectionNodeId,
      'selector': 'iframe',
    });
    final frameNodeIds = frameQuery['nodeIds'];
    if (frameNodeIds is! List<Object?> ||
        frameNodeIds.length != 1 ||
        frameNodeIds.single is! int) {
      return null;
    }
    final frameDescription = await send('DOM.describeNode', <String, Object?>{
      'nodeId': frameNodeIds.single! as int,
      'depth': 0,
    });
    final frameNode = _object(
      frameDescription['node'],
      'DOM.describeNode.node',
    );
    final frameId = frameNode['frameId'];
    if (frameNode['nodeName'] != 'IFRAME' ||
        frameId is! String ||
        frameId.isEmpty ||
        frameId.length > 512) {
      return null;
    }
    return frameId;
  }

  Future<Map<String, Object?>> scenarioQualityReattachSurface() async =>
      _object(
        await evaluate<Object?>(r'''
(() => {
  const boundary = document.querySelector('[data-quality-route-state]');
  const controls = document.querySelector('.scenario-lab-run-controls');
  const panel = document.querySelector('.scenario-quality-panel');
  const review = document.querySelector('.scenario-quality-review');
  const actions = Array.from(document.querySelectorAll(
    '[data-lab-run-action]'
  ));
  const reattach = actions.filter(
    (item) => item.dataset.labRunAction === 'reattach'
  );
  const query = new URLSearchParams(location.search);
  return {
    path: location.pathname,
    search: location.search,
    queryRunId: query.get('runId'),
    routeState: boundary?.dataset.qualityRouteState ?? null,
    qualitySelectedRunId:
      boundary?.dataset.qualitySelectedRunId ?? null,
    controlSelectedRunId: controls?.dataset.labSelectedRunId ?? null,
    actionsState: controls?.dataset.labRunActionsState ?? null,
    lifecycle: controls?.dataset.labRunLifecycle ?? null,
    actions: actions.map(
      (item) => item.dataset.labRunAction ?? null
    ).sort(),
    reattachCount: reattach.length,
    reattachEnabled: reattach.length === 1 &&
      reattach[0] instanceof HTMLButtonElement && !reattach[0].disabled,
    qualityRunId: panel?.dataset.qualityRunId ?? null,
    qualityResultDigest: panel?.dataset.qualityResultDigest ?? null,
    decisionOperation: review?.dataset.qualityDecisionOperation ?? null,
  };
})()
'''),
        'ScenarioQualityReattachSurface',
      );

  Future<Map<String, Object?>> scenarioQualitySurface() async => _object(
    await evaluate<Object?>(r'''
(() => {
  const panel = document.querySelector('.scenario-quality-panel');
  const review = document.querySelector('.scenario-quality-review');
  const evidence = document.querySelector(
    '[data-quality-evidence-id="dashboard-ready-visual"]'
  );
  const comparison = document.querySelector(
    '[data-quality-comparison-id="dashboard-ready-baseline-candidate"]'
  );
  const query = new URLSearchParams(location.search);
  const states = (panel?.dataset.qualityStates ?? '')
    .split(',').filter(Boolean);
  const currentnessNotices = document.querySelectorAll(
    '[data-quality-currentness-notice="stale"]'
  );
  const recollectLinks = Array.from(document.querySelectorAll(
    'a[data-quality-action="recollect"][href]'
  )).map((item) => {
    const target = new URL(item.href, location.href);
    return {path: target.pathname, search: target.search};
  });
  const countSource = review?.dataset.qualityDecisionCount ?? null;
  const decisionCount = countSource !== null && /^\d+$/.test(countSource)
    ? Number(countSource)
    : null;
  const resources = Array.from(document.querySelectorAll(
    '[data-quality-resource-state][data-quality-resource-role]'
  )).map((item) => ({
    state: item.dataset.qualityResourceState ?? null,
    role: item.dataset.qualityResourceRole ?? null,
    artifactDigest: item.dataset.qualityArtifactDigest ?? null,
    provenanceKind: item.dataset.qualityProvenanceKind ?? null,
  })).sort((left, right) =>
    `${left.role}:${left.artifactDigest}`.localeCompare(
      `${right.role}:${right.artifactDigest}`
    )
  );
  const history = Array.from(document.querySelectorAll(
    '[data-quality-decision-record]'
  )).map((item) => ({
    recordId: item.dataset.qualityDecisionRecord ?? null,
    humanDecision: item.dataset.qualityHumanDecision ?? null,
    decisionPolicy: item.dataset.qualityDecisionPolicy ?? null,
    decisionRequirement: item.dataset.qualityDecisionRequirement ?? null,
    supersededByDecisionDigest:
      item.dataset.qualityDecisionSupersededBy ?? null,
  }));
  const actions = Array.from(document.querySelectorAll(
    '[data-quality-decision-action]'
  )).map((item) => ({
    action: item.dataset.qualityDecisionAction ?? null,
    enabled: !(item instanceof HTMLButtonElement) || !item.disabled,
  })).sort((left, right) =>
    `${left.action}`.localeCompare(`${right.action}`)
  );
  const dialogs = Array.from(document.querySelectorAll(
    'dialog#scenario-quality-decision-confirmation[open]'
  ));
  const dialog = dialogs[0] ?? null;
  const labelledBy = dialog?.getAttribute('aria-labelledby') ?? null;
  const describedBy = dialog?.getAttribute('aria-describedby') ?? null;
  const focused = document.activeElement;
  return {
    path: location.pathname,
    search: location.search,
    queryRunId: query.get('runId'),
    routeState: document.querySelector('[data-quality-route-state]')
      ?.dataset.qualityRouteState ?? null,
    runId: panel?.dataset.qualityRunId ?? null,
    resultDigest: panel?.dataset.qualityResultDigest ?? null,
    verification: panel?.dataset.qualityVerification ?? null,
    humanDecision: panel?.dataset.qualityHumanDecision ?? null,
    contentCurrentness:
      panel?.dataset.qualityContentCurrentness ?? null,
    currentnessNoticeCount: currentnessNotices.length,
    recollectLinks,
    states,
    evidenceState: evidence?.dataset.qualityEvidenceState ?? null,
    evidenceFreshness: evidence?.dataset.qualityEvidenceFreshness ?? null,
    evidenceVerification: evidence?.dataset.qualityEvidenceVerification ?? null,
    comparisonState: comparison?.dataset.qualityComparisonState ?? null,
    comparisonKind: comparison?.dataset.qualityComparisonKind ?? null,
    comparisonChangedUnits:
      comparison?.dataset.qualityChangedUnits ?? null,
    reviewAvailability: review?.dataset.qualityReviewAvailability ?? null,
    decisionOperation: review?.dataset.qualityDecisionOperation ?? null,
    decisionCount,
    decisionRequirement:
      review?.dataset.qualityDecisionRequirement ?? null,
    headDecisionDigest: review?.dataset.qualityDecisionHead ?? null,
    decisionPolicy: review?.dataset.qualityDecisionPolicy ?? null,
    reviewGuide: review?.querySelector('[data-quality-review-guide]')
      ?.dataset.qualityReviewGuide ?? null,
    reviewInstruction: review?.querySelector(
      '[data-quality-review-instruction="true"]'
    ) !== null,
    reviewCriteria: review?.querySelector(
      '[data-quality-review-criteria="true"]'
    ) !== null,
    resources,
    history,
    actions,
    confirmationCount: dialogs.length,
    confirmationNative: dialog instanceof HTMLDialogElement,
    confirmationModal: dialog?.getAttribute('aria-modal') ?? null,
    confirmationLabelledBy: labelledBy,
    confirmationDescribedBy: describedBy,
    confirmationTitle: labelledBy
      ? document.getElementById(labelledBy)?.textContent.trim() ?? null
      : null,
    confirmationDescription: describedBy
      ? document.getElementById(describedBy)?.textContent.trim() ?? null
      : null,
    focusedAction: focused instanceof HTMLElement
      ? focused.dataset.qualityDecisionAction ?? null
      : null,
  };
})()
'''),
    'ScenarioQualitySurface',
  );

  Future<void> clickScenarioQualityAction(String action) async {
    final clicked = await evaluate<bool>('''
(() => {
  const action = ${jsonEncode(action)};
  const controls = Array.from(document.querySelectorAll(
    '[data-quality-decision-action]'
  )).filter((item) => item.dataset.qualityDecisionAction === action);
  if (controls.length !== 1) return false;
  const control = controls[0];
  if (!(control instanceof HTMLElement) ||
      (control instanceof HTMLButtonElement && control.disabled)) {
    return false;
  }
  control.focus();
  control.click();
  return true;
})()
''');
    if (clicked != true) {
      throw StateError('Quality action is not available: $action');
    }
  }

  Future<void> reloadCurrentPage() async {
    await send('Page.reload', const <String, Object?>{'ignoreCache': true});
    await _waitFor(
      () async =>
          await evaluate<String>('document.readyState') == 'complete' &&
          await bodyContains('Host conectado'),
      description: 'Studio reload and Host reconnection',
      timeout: const Duration(minutes: 2),
    );
  }

  Future<Map<String, Object?>> scenarioLabControlProof() async {
    await Future.wait(_scenarioLabControlCaptures);
    return <String, Object?>{
      'semanticStates': _scenarioLabControlStates.toList()..sort(),
      'disabledScreenshotDigest':
          _scenarioLabControlScreenshots['disabled']?.value,
      'enabledScreenshotDigest':
          _scenarioLabControlScreenshots['enabled']?.value,
      'captureErrors': List<String>.unmodifiable(
        _scenarioLabControlCaptureErrors,
      ),
    };
  }

  Map<String, Object?> scenarioLabKnownPorts() {
    final targetPorts = <int>{};
    final gatewayPorts = <int>{};
    for (final exchange in _scenarioLabRelayV2Exchanges) {
      final description = exchange.$2;
      final descriptor = description.descriptor;
      if (description.status != ScenarioLabRelayDescriptionStatus.ready ||
          descriptor == null) {
        continue;
      }
      final target = descriptor.origin;
      if (target.scheme == 'http' &&
          const <String>{
            '127.0.0.1',
            '::1',
            'localhost',
          }.contains(target.host) &&
          target.hasPort) {
        targetPorts.add(target.port);
      }
      try {
        final gateway = description.gatewayDataOrigin;
        if (gateway != null) {
          gatewayPorts.add(canonicalScenarioLabGatewayDataOrigin(gateway).port);
        }
      } on Object {
        // Invalid transport values never enter the allowlisted port summary.
      }
    }
    final sortedTargetPorts = targetPorts.toList()..sort();
    final sortedGatewayPorts = gatewayPorts.toList()..sort();
    return <String, Object?>{
      'targetPorts': sortedTargetPorts,
      'gatewayPorts': sortedGatewayPorts,
    };
  }

  Map<String, Object?> scenarioLabRelayV2Diagnostics(ScenarioLabRunId runId) {
    final readyForRun = _scenarioLabRelayV2Exchanges.where(
      (exchange) =>
          exchange.$2.runId == runId &&
          exchange.$2.status == ScenarioLabRelayDescriptionStatus.ready,
    );
    return <String, Object?>{
      'describeRequests': _scenarioLabRpcCounts['lab.relay.v2.describe'] ?? 0,
      'describeResults':
          _scenarioLabRpcResultCounts['lab.relay.v2.describe'] ?? 0,
      'readyForRun': readyForRun.length,
      'v1DescribeRequests': _scenarioLabRpcCounts['lab.relay.describe'] ?? 0,
    };
  }

  Map<String, Object?> scenarioLabFrameNavigationDiagnostics(
    ScenarioLabRunId runId,
  ) {
    final ready = _scenarioLabRelayV2Exchanges.where(
      (exchange) =>
          exchange.$2.runId == runId &&
          exchange.$2.status == ScenarioLabRelayDescriptionStatus.ready,
    );
    final descriptor = ready.length == 1 ? ready.single.$2.descriptor : null;
    final httpNavigations = _scenarioLabChildFrameNavigations
        .where((navigation) => navigation.isHttp)
        .length;
    final scrubbedHttpNavigations = descriptor == null
        ? 0
        : _scenarioLabChildFrameNavigations
              .where(
                (navigation) => navigation.isScrubbedNavigationTo(descriptor),
              )
              .length;
    final scrubbedTargetFrames = descriptor == null
        ? 0
        : _scenarioLabScrubbedTargetFrameIds(descriptor).length;
    return <String, Object?>{
      'childFrameNavigations': _scenarioLabChildFrameNavigations.length,
      'httpNavigations': httpNavigations,
      'scrubbedHttpNavigations': scrubbedHttpNavigations,
      'scrubbedTargetFrames': scrubbedTargetFrames,
    };
  }

  Set<String> _scenarioLabScrubbedTargetFrameIds(
    ScenarioLabRelayTargetDescriptor descriptor,
  ) => <String>{
    for (final navigation in _scenarioLabChildFrameNavigations)
      if (navigation.isScrubbedNavigationTo(descriptor)) navigation.frameId,
  };

  Map<String, Object?> scenarioLabRelayMountProof({
    required ScenarioLabRunId runId,
    required Map<String, Object?> relay,
  }) {
    final ready = _scenarioLabRelayV2Exchanges
        .where(
          (exchange) =>
              exchange.$2.runId == runId &&
              exchange.$2.status == ScenarioLabRelayDescriptionStatus.ready,
        )
        .toList(growable: false);
    final exchange = ready.length == 1 ? ready.single : null;
    final request = exchange?.$1;
    final description = exchange?.$2;
    final runtimeInputs = description?.runtimeInputs;
    final descriptor = description?.descriptor;
    Uri? gateway;
    try {
      final candidate = description?.gatewayDataOrigin;
      if (candidate != null) {
        gateway = canonicalScenarioLabGatewayDataOrigin(candidate);
      }
    } on Object {
      gateway = null;
    }

    final requestCount = _scenarioLabRpcCounts['lab.relay.v2.describe'] ?? 0;
    final resultCount =
        _scenarioLabRpcResultCounts['lab.relay.v2.describe'] ?? 0;
    final v1DescribeCount = _scenarioLabRpcCounts['lab.relay.describe'] ?? 0;
    final relayV2Ready = ready.length == 1;
    final transportBound =
        requestCount > 0 &&
        requestCount == resultCount &&
        v1DescribeCount == 0 &&
        relayV2Ready;
    final requestBound =
        request?.runId == runId &&
        description?.runId == runId &&
        request?.expectedStartRequestDigest == description?.startRequestDigest;
    final runtimeBound =
        runtimeInputs != null &&
        runtimeInputs.executionTargetId == _scenarioLabExecutionTargetId &&
        runtimeInputs.gatewayPresetId?.value == _scenarioLabGatewayPresetId;
    final descriptorBound =
        descriptor?.runId == runId &&
        descriptor?.targetId == _scenarioLabExecutionTargetId &&
        descriptor?.launchProfileId == _scenarioLabLaunchProfileId &&
        descriptor?.targetId == runtimeInputs?.executionTargetId;
    final targetCanonical =
        descriptor != null &&
        descriptor.origin.scheme == 'http' &&
        const <String>{
          '127.0.0.1',
          '::1',
          'localhost',
        }.contains(descriptor.origin.host) &&
        descriptor.origin.hasPort &&
        descriptor.origin.path.isEmpty &&
        !descriptor.origin.hasQuery &&
        !descriptor.origin.hasFragment &&
        descriptor.origin.userInfo.isEmpty;
    final gatewayDeclared =
        description?.requiresGateway == true && gateway != null;
    final relaySurfaceBound =
        relay['relayCount'] == 1 &&
        relay['boundRelayCount'] == 1 &&
        relay['iframeCount'] == 1 &&
        relay['scopedIframeCount'] == 1 &&
        relay['runId'] == runId.value &&
        relay['targetId'] == descriptor?.targetId &&
        relay['launchProfileId'] == descriptor?.launchProfileId &&
        relay['launchAttemptId'] == descriptor?.launchAttemptId.value &&
        relay['aboutBlank'] == true &&
        relay['gatewayBindingDeclared'] == true &&
        relay['gatewayBound'] == true;
    final scrubbedTargetFrameIds = descriptor == null
        ? const <String>{}
        : _scenarioLabScrubbedTargetFrameIds(descriptor);
    final relayFrameId = _scenarioLabRelayFrameIds[runId.value];
    final targetFrameBound =
        !_scenarioLabAmbiguousRelayFrameRuns.contains(runId.value) &&
        relayFrameId != null &&
        scrubbedTargetFrameIds.length == 1 &&
        scrubbedTargetFrameIds.single == relayFrameId;
    final childNavigationScrubbed = targetFrameBound;
    final relayV2Fenced =
        transportBound &&
        requestBound &&
        runtimeBound &&
        descriptorBound &&
        targetCanonical &&
        gatewayDeclared;
    final mountAuthorized =
        relaySurfaceBound &&
        relayV2Ready &&
        relayV2Fenced &&
        childNavigationScrubbed;
    return <String, Object?>{
      'targetPort': targetCanonical ? descriptor.origin.port : null,
      'childNavigationScrubbed': childNavigationScrubbed,
      'targetFrameBound': targetFrameBound,
      'relayV2Ready': relayV2Ready,
      'relayV2Fenced': relayV2Fenced,
      'mountAuthorized': mountAuthorized,
    };
  }

  Map<String, Object?> scenarioLabGatewayProof({
    required ScenarioLabRunId runId,
    required ScenarioLabRunSnapshot snapshot,
    required Map<String, Object?> relay,
  }) {
    final mount = scenarioLabRelayMountProof(runId: runId, relay: relay);
    final ready = _scenarioLabRelayV2Exchanges
        .where(
          (exchange) =>
              exchange.$2.runId == runId &&
              exchange.$2.status == ScenarioLabRelayDescriptionStatus.ready,
        )
        .toList(growable: false);
    final exchange = ready.length == 1 ? ready.single : null;
    final request = exchange?.$1;
    final description = exchange?.$2;
    final runtimeInputs = description?.runtimeInputs;
    final descriptor = description?.descriptor;
    final snapshotInputs = snapshot.runtimeInputs;

    Uri? gateway;
    try {
      final candidate = description?.gatewayDataOrigin;
      if (candidate != null) {
        gateway = canonicalScenarioLabGatewayDataOrigin(candidate);
      }
    } on Object {
      gateway = null;
    }
    final canonicalGateway = gateway;
    final targetFrameIds = descriptor == null
        ? const <String>{}
        : _scenarioLabScrubbedTargetFrameIds(descriptor);
    final targetFrameId = targetFrameIds.length == 1
        ? targetFrameIds.single
        : null;
    final gatewayRequests = canonicalGateway == null || targetFrameId == null
        ? const <MapEntry<String, _ScenarioLabNetworkRequest>>[]
        : _scenarioLabNetworkRequests.entries
              .where(
                (entry) =>
                    !_scenarioLabAmbiguousNetworkRequestIds.contains(
                      entry.key,
                    ) &&
                    entry.value.method == 'GET' &&
                    entry.value.frameId == targetFrameId &&
                    entry.value.initiatorType == 'script' &&
                    entry.value.location.isGatewayDashboard(canonicalGateway),
              )
              .toList(growable: false);
    var gatewaySuccessfulResponseCount = 0;
    for (final entry in gatewayRequests) {
      final response = _scenarioLabNetworkResponses[entry.key];
      if (response != null &&
          response.succeeded &&
          response.location.sameResourceAs(entry.value.location) &&
          response.location.isGatewayDashboard(canonicalGateway!)) {
        gatewaySuccessfulResponseCount += 1;
      }
    }
    final directApiRequestCount = _scenarioLabNetworkRequests.values
        .where((request) => request.location.isDirectApiDashboard)
        .length;
    final gatewayRequestCount = gatewayRequests.length;
    final networkTraceComplete =
        !_scenarioLabNetworkTraceOverflowed &&
        _scenarioLabAmbiguousNetworkRequestIds.isEmpty;
    final gatewayRequestBound =
        networkTraceComplete &&
        targetFrameIds.length == 1 &&
        gatewayRequestCount == 1;

    final requestCount = _scenarioLabRpcCounts['lab.relay.v2.describe'] ?? 0;
    final resultCount =
        _scenarioLabRpcResultCounts['lab.relay.v2.describe'] ?? 0;
    final v1DescribeCount = _scenarioLabRpcCounts['lab.relay.describe'] ?? 0;
    final transportBound =
        requestCount > 0 &&
        requestCount == resultCount &&
        v1DescribeCount == 0 &&
        ready.length == 1;
    final requestBound =
        request?.runId == runId &&
        request?.expectedStartRequestDigest == snapshot.startRequestDigest &&
        description?.startRequestDigest == snapshot.startRequestDigest;
    final runtimeBound =
        runtimeInputs != null &&
        snapshotInputs != null &&
        runtimeInputs.digest == snapshotInputs.digest &&
        runtimeInputs.executionTargetId == _scenarioLabExecutionTargetId &&
        runtimeInputs.gatewayPresetId?.value == _scenarioLabGatewayPresetId;
    final descriptorBound =
        descriptor?.runId == runId &&
        descriptor?.targetId == _scenarioLabExecutionTargetId &&
        descriptor?.launchProfileId == _scenarioLabLaunchProfileId &&
        descriptor?.targetId == runtimeInputs?.executionTargetId;
    final snapshotBound =
        request?.expectedStartRequestDigest == snapshot.startRequestDigest &&
        description?.startRequestDigest == snapshot.startRequestDigest;
    final helloRequestCount = _scenarioLabRpcCounts['lab.relay.hello'] ?? 0;
    final helloResultCount =
        _scenarioLabRpcResultCounts['lab.relay.hello'] ?? 0;
    final helloAccepted =
        descriptor != null &&
        helloRequestCount > 0 &&
        helloRequestCount == helloResultCount &&
        _scenarioLabRelayHelloExchanges.length == helloRequestCount &&
        _scenarioLabRelayHelloExchanges.every((exchange) {
          final submission = exchange.$1;
          final acknowledgement = exchange.$2;
          return submission.descriptorDigest == descriptor.digest &&
              submission.hello.runId == runId &&
              submission.hello.nonce == descriptor.nonce &&
              acknowledgement.runId == runId &&
              acknowledgement.descriptorDigest == descriptor.digest &&
              acknowledgement.acceptedHelloDigest == submission.hello.digest;
        });
    final relayResultRequestCount =
        _scenarioLabRpcCounts['lab.relay.result'] ?? 0;
    final relayResultResponseCount =
        _scenarioLabRpcResultCounts['lab.relay.result'] ?? 0;
    final relayResultsAccepted =
        descriptor != null &&
        relayResultRequestCount > 0 &&
        relayResultRequestCount == relayResultResponseCount &&
        _scenarioLabRelayResultExchanges.length == relayResultRequestCount &&
        _scenarioLabRelayResultExchanges.every((exchange) {
          final submission = exchange.$1;
          final result = submission.result;
          final acknowledgement = exchange.$2;
          return submission.descriptorDigest == descriptor.digest &&
              result.runId == runId &&
              result.nonce == descriptor.nonce &&
              result.state == AppAdapterRelayResultState.succeeded &&
              acknowledgement.runId == runId &&
              acknowledgement.descriptorDigest == descriptor.digest &&
              acknowledgement.acceptedResultDigest == result.resultDigest;
        });
    final gatewayTrafficObserved = gatewayRequestBound;
    final gatewayTrafficSucceeded =
        gatewayRequestBound &&
        gatewayRequestCount == gatewaySuccessfulResponseCount &&
        directApiRequestCount == 0;
    final controllerBound = mount['mountAuthorized'] == true && helloAccepted;
    final gatewayBound =
        mount['mountAuthorized'] == true &&
        description?.requiresGateway == true &&
        gateway != null &&
        transportBound &&
        requestBound &&
        runtimeBound &&
        descriptorBound &&
        snapshotBound &&
        helloAccepted;
    final gatewayRouted =
        gatewayBound &&
        relayResultsAccepted &&
        gatewayTrafficObserved &&
        gatewayTrafficSucceeded;
    return <String, Object?>{
      ...mount,
      'controllerBound': controllerBound,
      'helloAccepted': helloAccepted,
      'relayResultsAccepted': relayResultsAccepted,
      'relayResultCount': _scenarioLabRelayResultExchanges.length,
      'networkTraceComplete': networkTraceComplete,
      'gatewayRequestBound': gatewayRequestBound,
      'gatewayRequestCount': gatewayRequestCount,
      'gatewaySuccessfulResponseCount': gatewaySuccessfulResponseCount,
      'directApiRequestCount': directApiRequestCount,
      'gatewayTrafficObserved': gatewayTrafficObserved,
      'gatewayTrafficSucceeded': gatewayTrafficSucceeded,
      'gatewayBound': gatewayBound,
      'gatewayRouted': gatewayRouted,
      'gatewayPort': gateway?.port,
    };
  }

  Map<String, Object?> scenarioLabRpcSummary() => <String, Object?>{
    'requestsByMethod': <String, Object?>{
      for (final entry
          in (_scenarioLabRpcCounts.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key))))
        entry.key: entry.value,
    },
    'resultsByMethod': <String, Object?>{
      for (final entry
          in (_scenarioLabRpcResultCounts.entries.toList()
            ..sort((left, right) => left.key.compareTo(right.key))))
        entry.key: entry.value,
    },
    'failures': List<Map<String, Object?>>.unmodifiable(
      _scenarioLabRpcFailures,
    ),
    'relayResults': List<Map<String, Object?>>.unmodifiable(
      _scenarioLabRelayResults,
    ),
    'surfaceHistory': List<Map<String, Object?>>.unmodifiable(
      _scenarioLabSurfaceHistory,
    ),
  };

  bool get scenarioLabRpcHasFailures => _scenarioLabRpcFailures.isNotEmpty;

  bool get scenarioLabRpcSettled =>
      _scenarioLabPendingRpc.isEmpty &&
      _scenarioLabRpcCounts.length == _scenarioLabRpcResultCounts.length &&
      _scenarioLabRpcCounts.entries.every(
        (entry) => _scenarioLabRpcResultCounts[entry.key] == entry.value,
      );

  Map<String, Object?> scenarioLabRequestCounts() => <String, Object?>{
    for (final entry
        in (_scenarioLabRpcCounts.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key))))
      entry.key: entry.value,
  };

  Map<String, Object?> scenarioQualityRequestCounts() => <String, Object?>{
    for (final method in _scenarioQualityRpcMethods)
      method: _scenarioQualityRpcCounts[method] ?? 0,
  };

  Map<String, Object?> scenarioQualityRpcSummary() => <String, Object?>{
    'requestsByMethod': scenarioQualityRequestCounts(),
    'resultsByMethod': <String, Object?>{
      for (final method in _scenarioQualityRpcMethods)
        method: _scenarioQualityRpcResultCounts[method] ?? 0,
    },
    'failures': List<Map<String, Object?>>.unmodifiable(
      _scenarioQualityRpcFailures,
    ),
  };

  List<ScenarioQualityDescribeResult> get scenarioQualityDescribeResults =>
      List<ScenarioQualityDescribeResult>.unmodifiable(
        _scenarioQualityDescriptions,
      );

  List<Map<String, Object?>> get scenarioQualityReviewSets =>
      List<Map<String, Object?>>.unmodifiable(_scenarioQualityReviewSetResults);

  List<Map<String, Object?>> get scenarioQualityAppendResults =>
      List<Map<String, Object?>>.unmodifiable(
        _scenarioQualityAppendResultSummaries,
      );

  List<Map<String, Object?>> get scenarioQualityDecisionViews =>
      List<Map<String, Object?>>.unmodifiable(
        _scenarioQualityDecisionViewSummaries,
      );

  void resetScenarioAuditForReload() {
    resourceUrls.clear();
    _resetScenarioLabRunTransportAudit();
    _scenarioLabPendingRpc.clear();
    _scenarioLabRelayV2PendingRequests.clear();
    _scenarioLabRelayV2Exchanges.clear();
    _scenarioLabRelayHelloPendingRequests.clear();
    _scenarioLabRelayHelloExchanges.clear();
    _scenarioLabRelayResultPendingRequests.clear();
    _scenarioLabRelayResultExchanges.clear();
    _scenarioLabRpcCounts.clear();
    _scenarioLabRpcResultCounts.clear();
    _scenarioLabRpcFailures.clear();
    _scenarioLabRelayResults.clear();
    _scenarioLabRunResults.clear();
    _scenarioLabSurfaceHistory.clear();
    _scenarioQualityPendingRpc.clear();
    _scenarioQualityRpcCounts.clear();
    _scenarioQualityRpcResultCounts.clear();
    _scenarioQualityRpcFailures.clear();
    _scenarioQualityDescriptions.clear();
    _scenarioQualityReviewSetResults.clear();
    _scenarioQualityAppendResultSummaries.clear();
    _scenarioQualityDecisionViewSummaries.clear();
  }

  void beginScenarioLabRunTransportAudit() =>
      _resetScenarioLabRunTransportAudit();

  void _resetScenarioLabRunTransportAudit() {
    _scenarioLabNetworkRequests.clear();
    _scenarioLabNetworkResponses.clear();
    _scenarioLabAmbiguousNetworkRequestIds.clear();
    _scenarioLabNetworkTraceOverflowed = false;
    _scenarioLabChildFrameIds.clear();
    _scenarioLabChildFrameNavigations.clear();
    _scenarioLabRelayFrameIds.clear();
    _scenarioLabAmbiguousRelayFrameRuns.clear();
  }

  Map<String, Object?>? latestTerminalRunObservation(ScenarioLabRunId runId) {
    ScenarioLabRunObservation? latest;
    Map<String, Object?>? latestJson;
    for (final entry in _scenarioLabRunResults) {
      if (entry.$1 != 'lab.reattach') continue;
      try {
        final observation = ScenarioLabRunObservation.fromJson(entry.$2);
        if (observation.runId == runId &&
            observation.disposition == ScenarioLabRunDisposition.terminal &&
            (latest == null ||
                observation.current.sequence > latest.current.sequence)) {
          latest = observation;
          latestJson = entry.$2;
        }
      } on Object {
        // The typed Studio decoder owns malformed-response rejection. The
        // browser proof only considers independently valid observations.
      }
    }
    return latestJson;
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

  Future<void> clickLinkPath(String path) async {
    final clicked = await evaluate<bool>('''
(() => {
  const path = ${jsonEncode(path)};
  const link = Array.from(document.querySelectorAll('a[href]'))
    .find((item) => {
      const target = new URL(item.href, location.href);
      return target.pathname === path && target.search === '';
    });
  if (!link) return false;
  link.focus();
  link.click();
  return true;
})()
''');
    if (clicked != true) throw StateError('Link path not available: $path');
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

  Future<Map<String, Object?>> auditInventoryIndex() async {
    final value = await evaluate<Object?>(r'''
(() => {
  const expectedAxes = [
    'data-inventory-lifecycle',
    'data-inventory-kind',
    'data-inventory-surface',
    'data-inventory-state',
    'data-inventory-owner',
    'data-inventory-tags',
    'data-inventory-components',
    'data-inventory-fixture',
    'data-inventory-render',
    'data-inventory-frames',
    'data-inventory-form-factors',
  ];
  const duplicates = (values) => [...new Set(values.filter(
    (value, index) => value && values.indexOf(value) !== index
  ))].sort();
  const cards = Array.from(document.querySelectorAll(
    '.inventory-scenario-card[data-inventory-scenario-id]'
  )).map((card) => {
    const scenarioId = card.dataset.inventoryScenarioId ?? '';
    const link = card.querySelector('a[href]');
    const target = link ? new URL(link.href, location.href) : null;
    const missingAxes = expectedAxes.filter(
      (attribute) => !(card.getAttribute(attribute) ?? '').trim()
    );
    return {
      scenarioId,
      domId: card.id,
      canonicalDomId: card.id === `inventory-scenario-${scenarioId}`,
      semanticArticle: card.tagName === 'ARTICLE',
      missingAxes,
      occurrencePath: target?.pathname ?? null,
      occurrenceQuery: target?.search ?? null,
    };
  });
  const boundary = document.querySelector(
    '.inventory-facet-boundary[data-inventory-facets]'
  );
  const projectionIds = Array.from(document.querySelectorAll(
    '.inventory-projection-card[data-inventory-projection-id]'
  )).map((card) => card.dataset.inventoryProjectionId ?? '').sort();
  const allDomIds = Array.from(document.querySelectorAll('[id]'))
    .map((element) => element.id);
  return {
    routePath: location.pathname,
    routeSearch: location.search,
    filterSource: document.querySelector(
      '.inventory-index__filters'
    )?.dataset.inventoryFilterSource ?? null,
    facetBoundaryCount: document.querySelectorAll(
      '.inventory-facet-boundary'
    ).length,
    facetStatus: boundary?.dataset.inventoryFacets ?? null,
    facetDigest: boundary?.dataset.inventoryFacetDigest ?? null,
    scenarioCount: cards.length,
    scenarioIds: cards.map((item) => item.scenarioId).sort(),
    scenarioCards: cards.sort(
      (left, right) => left.scenarioId.localeCompare(right.scenarioId)
    ),
    axisNames: expectedAxes,
    axisCount: expectedAxes.length,
    allAxesNonEmpty: cards.every((item) => item.missingAxes.length === 0),
    canonicalDomIds: cards.every((item) => item.canonicalDomId),
    semanticArticleCount: cards.filter((item) => item.semanticArticle).length,
    projectionIds,
    duplicateDomIds: duplicates(allDomIds),
    duplicateScenarioIds: duplicates(cards.map((item) => item.scenarioId)),
  };
})()
''');
    final result = _object(value, 'InventoryIndexAudit');
    final facetDigest = result['facetDigest'];
    if (facetDigest is! String) {
      throw StateError('Inventory omitted its facet digest: $result');
    }
    Digest(facetDigest);
    final scenarioIds = result['scenarioIds'];
    final axisNames = result['axisNames'];
    final cards = result['scenarioCards'];
    const expectedScenarios = <String>[
      'dashboard-empty',
      'dashboard-failed',
      'dashboard-loading',
      'dashboard-ready',
      'dashboard-stale',
      'dashboard-unavailable',
      'inspect-gateway-traffic',
      'toggle-delivery-task',
    ];
    const expectedAxes = <String>[
      'data-inventory-lifecycle',
      'data-inventory-kind',
      'data-inventory-surface',
      'data-inventory-state',
      'data-inventory-owner',
      'data-inventory-tags',
      'data-inventory-components',
      'data-inventory-fixture',
      'data-inventory-render',
      'data-inventory-frames',
      'data-inventory-form-factors',
    ];
    const expectedOccurrencePaths = <String, String?>{
      'dashboard-empty': null,
      'dashboard-failed':
          '/inventory/delivery-inventory/nodes/inventory-dashboard-failed',
      'dashboard-loading':
          '/inventory/delivery-inventory/nodes/inventory-dashboard-loading',
      'dashboard-ready':
          '/inventory/delivery-inventory/nodes/inventory-dashboard-ready',
      'dashboard-stale': null,
      'dashboard-unavailable': null,
      'inspect-gateway-traffic':
          '/inventory/delivery-inventory/nodes/inventory-inspect-gateway-traffic',
      'toggle-delivery-task':
          '/inventory/delivery-inventory/nodes/inventory-toggle-delivery-task',
    };
    final occurrencePathsValid =
        cards is List<Object?> &&
        cards.every((value) {
          if (value is! Map<String, Object?>) return false;
          return expectedOccurrencePaths[value['scenarioId']] ==
                  value['occurrencePath'] &&
              (value['occurrencePath'] == null ||
                  value['occurrenceQuery'] == '');
        });
    if (result['routePath'] != '/inventory' ||
        result['routeSearch'] != '' ||
        result['filterSource'] != 'url' ||
        result['facetBoundaryCount'] != 1 ||
        result['facetStatus'] != 'ready' ||
        result['scenarioCount'] != 8 ||
        scenarioIds is! List<Object?> ||
        !_sameStrings(scenarioIds, expectedScenarios) ||
        axisNames is! List<Object?> ||
        !_sameStrings(axisNames, expectedAxes) ||
        result['axisCount'] != 11 ||
        result['allAxesNonEmpty'] != true ||
        result['canonicalDomIds'] != true ||
        result['semanticArticleCount'] != 8 ||
        result['projectionIds'] is! List<Object?> ||
        !_sameStrings(result['projectionIds']! as List<Object?>, const <String>[
          'delivery-inventory',
        ]) ||
        (result['duplicateDomIds'] as List<Object?>? ?? const <Object?>[])
            .isNotEmpty ||
        (result['duplicateScenarioIds'] as List<Object?>? ?? const <Object?>[])
            .isNotEmpty ||
        !occurrencePathsValid) {
      throw StateError('Studio Scenario Inventory audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditInventoryStateFilter() async {
    final value = await evaluate<Object?>(r'''
(() => {
  const query = new URLSearchParams(location.search);
  const cards = Array.from(document.querySelectorAll(
    '.inventory-scenario-card[data-inventory-scenario-id]'
  ));
  const boundary = document.querySelector(
    '.inventory-facet-boundary[data-inventory-facets]'
  );
  const reset = Array.from(document.querySelectorAll('button')).find(
    (item) => item.textContent.trim() === 'Limpar filtros'
  );
  return {
    routePath: location.pathname,
    routeSearch: location.search,
    querySize: query.size,
    state: query.get('state'),
    selectedValue: document.getElementById('inventory-index-state')?.value ??
      null,
    scenarioCount: cards.length,
    scenarioIds: cards.map(
      (card) => card.dataset.inventoryScenarioId ?? ''
    ).sort(),
    facetStatus: boundary?.dataset.inventoryFacets ?? null,
    facetDigest: boundary?.dataset.inventoryFacetDigest ?? null,
    resetEnabled: Boolean(reset && !reset.disabled),
  };
})()
''');
    final result = _object(value, 'InventoryStateFilterAudit');
    final facetDigest = result['facetDigest'];
    if (facetDigest is! String) {
      throw StateError('Filtered Inventory omitted its facet digest: $result');
    }
    Digest(facetDigest);
    final scenarioIds = result['scenarioIds'];
    if (result['routePath'] != '/inventory' ||
        result['routeSearch'] != '?state=dashboard.unavailable' ||
        result['querySize'] != 1 ||
        result['state'] != 'dashboard.unavailable' ||
        result['selectedValue'] != 'dashboard.unavailable' ||
        result['scenarioCount'] != 1 ||
        scenarioIds is! List<Object?> ||
        !_sameStrings(scenarioIds, const <String>['dashboard-unavailable']) ||
        result['facetStatus'] != 'ready' ||
        result['resetEnabled'] != true) {
      throw StateError('Studio Inventory state filter audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditSpatialInventoryMap() async {
    final value = await evaluate<Object?>(r'''
(() => {
  const expectedProjectionId = 'delivery-inventory';
  const expectedNodeScenarios = {
    'inventory-dashboard-failed': 'dashboard-failed',
    'inventory-dashboard-loading': 'dashboard-loading',
    'inventory-dashboard-ready': 'dashboard-ready',
    'inventory-inspect-gateway-traffic': 'inspect-gateway-traffic',
    'inventory-toggle-delivery-task': 'toggle-delivery-task',
  };
  const stage = document.querySelector(
    `.inventory-map-stage.is-spatial[data-projection-id="${expectedProjectionId}"]`
  );
  if (!stage) {
    return {
      available: false,
      projectionId: null,
      routePath: location.pathname,
    };
  }
  const duplicates = (values) => [...new Set(values.filter(
    (value, index) => value && values.indexOf(value) !== index
  ))].sort();
  const allDomIds = Array.from(document.querySelectorAll('[id]'))
    .map((element) => element.id);
  const nodeElements = Array.from(stage.querySelectorAll(
    '.inventory-map-node.is-authored[data-node-instance-id]'
  ));
  const nodes = nodeElements.map((element) => {
    const nodeInstanceId = element.dataset.nodeInstanceId ?? '';
    const scenarioId = element.dataset.scenarioId ?? '';
    const card = element.querySelector('.inventory-card');
    const link = card?.querySelector('a.inventory-card__link[href]');
    const target = link ? new URL(link.href, location.href) : null;
    const expectedHref =
      `/inventory/${expectedProjectionId}/nodes/${nodeInstanceId}`;
    return {
      nodeInstanceId,
      scenarioId,
      href: target?.pathname ?? null,
      query: target?.search ?? null,
      expectedHref,
      deepLinkValid: target?.pathname === expectedHref &&
        target?.search === '',
      identityValid: Boolean(nodeInstanceId && scenarioId) &&
        element.dataset.inventoryNodeId === nodeInstanceId &&
        element.dataset.inventoryScenarioId === scenarioId &&
        expectedNodeScenarios[nodeInstanceId] === scenarioId &&
        card?.id === `inventory-card-${nodeInstanceId}` &&
        card?.dataset.inventoryProjectionId === expectedProjectionId &&
        card?.dataset.inventoryNodeId === nodeInstanceId &&
        card?.dataset.inventoryScenarioId === scenarioId,
      selected: card?.classList.contains('is-selected') === true &&
        link?.getAttribute('aria-current') === 'page',
      cardId: card?.id ?? null,
      x: Number(element.dataset.x),
      y: Number(element.dataset.y),
      width: Number(element.dataset.width),
      height: Number(element.dataset.height),
    };
  });
  const nodeIds = nodes.map((item) => item.nodeInstanceId);
  const groups = Array.from(stage.querySelectorAll(
    '.inventory-map-group[data-group-id]'
  )).map((element) => element.dataset.groupId ?? '');
  const lanes = Array.from(stage.querySelectorAll(
    '.inventory-map-lane[data-lane-id]'
  )).map((element) => element.dataset.laneId ?? '');
  const annotations = Array.from(stage.querySelectorAll(
    '.inventory-map-annotation[data-annotation-id]'
  )).map((element) => element.dataset.annotationId ?? '');
  const edgeElements = Array.from(stage.querySelectorAll(
    '.inventory-map-edge[data-edge-instance-id]'
  ));
  const edgeLabels = Array.from(stage.querySelectorAll(
    '.inventory-map-edge__label[data-edge-label-for]'
  ));
  const edgeSvg = stage.querySelector('svg.inventory-map-edges');
  const positionedElements = Array.from(stage.querySelectorAll(
    '.inventory-map-node.is-authored, .inventory-map-lane, '
      + '.inventory-map-group, .inventory-map-annotation'
  ));
  const stageRect = stage.getBoundingClientRect();
  const geometryMismatches = positionedElements.map((element) => {
    const rect = element.getBoundingClientRect();
    const expected = {
      x: Number(element.dataset.x),
      y: Number(element.dataset.y),
      width: Number(element.dataset.width),
      height: Number(element.dataset.height),
    };
    const actual = {
      x: rect.left - stageRect.left,
      y: rect.top - stageRect.top,
      width: rect.width,
      height: rect.height,
    };
    const valid = Object.values(expected).every(Number.isFinite) &&
      Object.keys(expected).every(
        (key) => Math.abs(expected[key] - actual[key]) <= 0.75
      );
    return valid ? null : {
      kind: element.className,
      id: element.dataset.nodeInstanceId ?? element.dataset.laneId ??
        element.dataset.groupId ?? element.dataset.annotationId ?? null,
      expected,
      actual,
    };
  }).filter(Boolean);
  const selectedOutlineIds = Array.from(document.querySelectorAll(
    '.scenario-outline-item[data-node-instance-id][aria-current="page"]'
  )).map((element) => element.dataset.nodeInstanceId ?? '');
  const crossLens = document.querySelector(
    'a[data-cross-lens="inventory-to-journey"][href]'
  );
  const crossLensTarget = crossLens
    ? new URL(crossLens.href, location.href)
    : null;
  return {
    available: true,
    projectionId: stage.dataset.projectionId ?? null,
    projectionKind: stage.dataset.projectionKind ?? null,
    inventoryProjectionId: stage.dataset.inventoryProjectionId ?? null,
    layoutDigest: stage.dataset.layoutDigest ?? null,
    routePath: location.pathname,
    routeSearch: location.search,
    deepLinkNodeId: location.pathname.split('/').filter(Boolean)[3] ?? null,
    selectedNodeInstanceIds: nodes
      .filter((item) => item.selected)
      .map((item) => item.nodeInstanceId),
    selectedOutlineNodeInstanceIds: selectedOutlineIds,
    nodeInstanceCount: nodes.length,
    declaredEdgeCount: Number(stage.dataset.declaredEdgeCount ?? '-1'),
    edgeInstanceCount: edgeElements.length,
    edgeLabelCount: edgeLabels.length,
    edgeLineCount: edgeSvg?.querySelectorAll('line').length ?? -1,
    edgeSvgSemantic: edgeSvg?.getAttribute('role') === 'group' &&
      Boolean(edgeSvg?.getAttribute('aria-label')?.trim()),
    groupCount: groups.length,
    laneCount: lanes.length,
    annotationCount: annotations.length,
    windowCandidateCount: Number(stage.dataset.windowCandidates ?? '-1'),
    windowRenderedCount: Number(stage.dataset.windowRendered ?? '-1'),
    camera: {
      x: Number(stage.dataset.cameraX),
      y: Number(stage.dataset.cameraY),
      zoom: Number(stage.dataset.cameraZoom),
    },
    canvas: {
      width: Number(stage.dataset.canvasWidth),
      height: Number(stage.dataset.canvasHeight),
    },
    typedAttrGeometrySupported: CSS.supports(
      'width',
      'calc(attr(data-canvas-width type(<number>)) * 1px)'
    ),
    stageRendered: stageRect.width > 0 && stageRect.height > 0,
    stageGeometryValid:
      Math.abs(stageRect.width - Number(stage.dataset.canvasWidth)) <= 0.75 &&
      Math.abs(stageRect.height - Number(stage.dataset.canvasHeight)) <= 0.75,
    inlineStyleCount: stage.querySelectorAll('[style]').length +
      (stage.hasAttribute('style') ? 1 : 0),
    geometryMismatches,
    nodeInstances: nodes.sort(
      (left, right) => left.nodeInstanceId.localeCompare(right.nodeInstanceId)
    ),
    nodeInstanceIds: [...nodeIds].sort(),
    edgeInstanceIds: edgeElements.map(
      (element) => element.dataset.edgeInstanceId ?? ''
    ).sort(),
    groupIds: groups.sort(),
    laneIds: lanes.sort(),
    annotationIds: annotations.sort(),
    duplicateDomIds: duplicates(allDomIds),
    duplicateNodeInstanceIds: duplicates(nodeIds),
    duplicateEdgeInstanceIds: duplicates(edgeElements.map(
      (element) => element.dataset.edgeInstanceId ?? ''
    )),
    duplicateGroupIds: duplicates(groups),
    duplicateLaneIds: duplicates(lanes),
    duplicateAnnotationIds: duplicates(annotations),
    allNodeDeepLinksValid: nodes.every((item) => item.deepLinkValid),
    allNodeIdentitiesValid: nodes.every((item) => item.identityValid),
    crossLensPath: crossLensTarget?.pathname ?? null,
    crossLensSearch: crossLensTarget?.search ?? null,
    crossLensExact: crossLensTarget?.pathname ===
        '/journeys/operate-delivery-workspace/nodes/journey-dashboard-ready' &&
      crossLensTarget?.search === '',
  };
})()
''');
    final result = _object(value, 'SpatialInventoryMapAudit');
    final layoutDigest = result['layoutDigest'];
    if (layoutDigest is! String) {
      throw StateError('Spatial Inventory omitted its layout digest: $result');
    }
    Digest(layoutDigest);
    final nodeIds = result['nodeInstanceIds'];
    final edgeIds = result['edgeInstanceIds'];
    final groupIds = result['groupIds'];
    final laneIds = result['laneIds'];
    final annotationIds = result['annotationIds'];
    final selected = result['selectedNodeInstanceIds'];
    final selectedOutline = result['selectedOutlineNodeInstanceIds'];
    final duplicateFields = <String>[
      'duplicateDomIds',
      'duplicateNodeInstanceIds',
      'duplicateEdgeInstanceIds',
      'duplicateGroupIds',
      'duplicateLaneIds',
      'duplicateAnnotationIds',
    ];
    final hasDuplicates = duplicateFields.any(
      (field) =>
          (result[field] as List<Object?>? ?? const <Object?>[]).isNotEmpty,
    );
    final camera = result['camera'];
    final canvas = result['canvas'];
    if (result['available'] != true ||
        result['projectionId'] != 'delivery-inventory' ||
        result['projectionKind'] != 'inventory' ||
        result['inventoryProjectionId'] != 'delivery-inventory' ||
        result['routePath'] !=
            '/inventory/delivery-inventory/nodes/inventory-dashboard-ready' ||
        result['routeSearch'] != '' ||
        result['deepLinkNodeId'] != 'inventory-dashboard-ready' ||
        result['nodeInstanceCount'] != 5 ||
        result['declaredEdgeCount'] != 0 ||
        result['edgeInstanceCount'] != 0 ||
        result['edgeLabelCount'] != 0 ||
        result['edgeLineCount'] != 0 ||
        result['edgeSvgSemantic'] != true ||
        result['groupCount'] != 2 ||
        result['laneCount'] != 2 ||
        result['annotationCount'] != 1 ||
        result['windowCandidateCount'] != 5 ||
        result['windowRenderedCount'] != 5 ||
        camera is! Map<String, Object?> ||
        camera['x'] != 0 ||
        camera['y'] != 0 ||
        camera['zoom'] != 0.9 ||
        canvas is! Map<String, Object?> ||
        canvas['width'] != 1216 ||
        canvas['height'] != 532 ||
        result['typedAttrGeometrySupported'] != true ||
        result['stageRendered'] != true ||
        result['stageGeometryValid'] != true ||
        result['inlineStyleCount'] != 0 ||
        (result['geometryMismatches'] as List<Object?>? ?? const <Object?>[])
            .isNotEmpty ||
        nodeIds is! List<Object?> ||
        !_sameStrings(nodeIds, const <String>[
          'inventory-dashboard-failed',
          'inventory-dashboard-loading',
          'inventory-dashboard-ready',
          'inventory-inspect-gateway-traffic',
          'inventory-toggle-delivery-task',
        ]) ||
        edgeIds is! List<Object?> ||
        edgeIds.isNotEmpty ||
        groupIds is! List<Object?> ||
        !_sameStrings(groupIds, const <String>[
          'inventory-dashboard-group',
          'inventory-gateway-group',
        ]) ||
        laneIds is! List<Object?> ||
        !_sameStrings(laneIds, const <String>[
          'inventory-operation-lane',
          'inventory-state-lane',
        ]) ||
        annotationIds is! List<Object?> ||
        !_sameStrings(annotationIds, const <String>['inventory-reuse-note']) ||
        selected is! List<Object?> ||
        !_sameStrings(selected, const <String>['inventory-dashboard-ready']) ||
        selectedOutline is! List<Object?> ||
        !_sameStrings(selectedOutline, const <String>[
          'inventory-dashboard-ready',
        ]) ||
        hasDuplicates ||
        result['allNodeDeepLinksValid'] != true ||
        result['allNodeIdentitiesValid'] != true ||
        result['crossLensPath'] !=
            '/journeys/operate-delivery-workspace/nodes/journey-dashboard-ready' ||
        result['crossLensSearch'] != '' ||
        result['crossLensExact'] != true) {
      throw StateError('Studio spatial Inventory audit failed: $result');
    }
    return result;
  }

  Future<Map<String, Object?>> auditSpatialJourneyMap() async {
    final value = await evaluate<Object?>(r'''
(() => {
  const expectedProjectionId = 'delivery-journey';
  const expectedJourneyId = 'operate-delivery-workspace';
  const stage = document.querySelector(
    `.journey-map-stage.is-spatial[data-projection-id="${expectedProjectionId}"]`
  );
  if (!stage) {
    return {
      available: false,
      projectionId: null,
      routePath: location.pathname,
    };
  }
  const duplicates = (values) => [...new Set(values.filter(
    (value, index) => value && values.indexOf(value) !== index
  ))].sort();
  const allDomIds = Array.from(document.querySelectorAll('[id]'))
    .map((element) => element.id);
  const nodeElements = Array.from(
    stage.querySelectorAll('.journey-map-node.is-authored[data-node-instance-id]')
  );
  const nodes = nodeElements.map((element) => {
    const nodeInstanceId = element.dataset.nodeInstanceId ?? '';
    const scenarioId = element.dataset.scenarioId ?? '';
    const link = element.querySelector('a.scenario-card__link[href]');
    const href = link ? new URL(link.href, location.href).pathname : null;
    const expectedHref = `/journeys/${expectedJourneyId}/nodes/${nodeInstanceId}`;
    return {
      nodeInstanceId,
      scenarioId,
      href,
      expectedHref,
      deepLinkValid: href === expectedHref,
      identityValid: Boolean(nodeInstanceId && scenarioId) &&
        element.querySelector('.scenario-card')?.id ===
          `scenario-card-${nodeInstanceId}`,
      selected: element.querySelector('.scenario-card.is-selected') !== null &&
        link?.getAttribute('aria-current') === 'step',
      cardId: element.querySelector('.scenario-card')?.id ?? null,
      x: Number(element.dataset.x),
      y: Number(element.dataset.y),
      width: Number(element.dataset.width),
      height: Number(element.dataset.height),
    };
  });
  const nodeIds = nodes.map((item) => item.nodeInstanceId);
  const sortedNodeIds = [...nodeIds].sort();
  const nodeIdSet = new Set(nodeIds);
  const edgeElements = Array.from(
    stage.querySelectorAll('.journey-map-edge[data-edge-instance-id]')
  );
  const edges = edgeElements.map((element) => {
    const edgeInstanceId = element.dataset.edgeInstanceId ?? '';
    const ariaLabel = element.getAttribute('aria-label') ?? '';
    const match = /^EdgeInstance ([^:]+): (\S+) para ([^,]+), /.exec(ariaLabel);
    const declaredEdgeId = match?.[1] ?? null;
    const fromNodeId = element.dataset.fromNodeId ?? null;
    const toNodeId = element.dataset.toNodeId ?? null;
    const x1 = Number(element.getAttribute('x1'));
    const y1 = Number(element.getAttribute('y1'));
    const x2 = Number(element.getAttribute('x2'));
    const y2 = Number(element.getAttribute('y2'));
    const fromNode = nodes.find((item) => item.nodeInstanceId === fromNodeId);
    const toNode = nodes.find((item) => item.nodeInstanceId === toNodeId);
    const close = (left, right) => Math.abs(left - right) <= 0.01;
    return {
      edgeInstanceId,
      declaredEdgeId,
      fromNodeId,
      toNodeId,
      endpointsValid: declaredEdgeId === edgeInstanceId &&
        match?.[2] === fromNodeId && match?.[3] === toNodeId &&
        nodeIdSet.has(fromNodeId) && nodeIdSet.has(toNodeId),
      geometryValid: [x1, y1, x2, y2].every(Number.isFinite) &&
        Boolean(fromNode && toNode) &&
        close(x1, fromNode.x + fromNode.width / 2) &&
        close(y1, fromNode.y + fromNode.height / 2) &&
        close(x2, toNode.x + toNode.width / 2) &&
        close(y2, toNode.y + toNode.height / 2),
      semanticRoleValid: element.getAttribute('role') === 'img',
      renderedLength: Math.hypot(x2 - x1, y2 - y1),
    };
  });
  const sortedEdgeIds = edges.map((item) => item.edgeInstanceId).sort();
  const outgoing = new Map();
  const incoming = new Map();
  for (const edge of edges) {
    if (!edge.endpointsValid) continue;
    outgoing.set(edge.fromNodeId, (outgoing.get(edge.fromNodeId) ?? 0) + 1);
    incoming.set(edge.toNodeId, (incoming.get(edge.toNodeId) ?? 0) + 1);
  }
  const branchNodeIds = [...outgoing.entries()]
    .filter(([, count]) => count > 1)
    .map(([id]) => id)
    .sort();
  const mergeNodeIds = [...incoming.entries()]
    .filter(([, count]) => count > 1)
    .map(([id]) => id)
    .sort();
  const groups = Array.from(stage.querySelectorAll(
    '.journey-map-group[data-group-id]'
  )).map((element) => element.dataset.groupId ?? '');
  const lanes = Array.from(stage.querySelectorAll(
    '.journey-map-lane[data-lane-id]'
  )).map((element) => element.dataset.laneId ?? '');
  const annotations = Array.from(stage.querySelectorAll(
    '.journey-map-annotation[data-annotation-id]'
  )).map((element) => element.dataset.annotationId ?? '');
  const positionedElements = Array.from(stage.querySelectorAll(
    '.journey-map-node.is-authored, .journey-map-lane, .journey-map-group, .journey-map-annotation'
  ));
  const stageRect = stage.getBoundingClientRect();
  const geometryMismatches = positionedElements.map((element) => {
    const rect = element.getBoundingClientRect();
    const expected = {
      x: Number(element.dataset.x),
      y: Number(element.dataset.y),
      width: Number(element.dataset.width),
      height: Number(element.dataset.height),
    };
    const actual = {
      x: rect.left - stageRect.left,
      y: rect.top - stageRect.top,
      width: rect.width,
      height: rect.height,
    };
    const valid = Object.values(expected).every(Number.isFinite) &&
      Object.keys(expected).every(
        (key) => Math.abs(expected[key] - actual[key]) <= 0.75
      );
    return valid ? null : {
      kind: element.className,
      id: element.dataset.nodeInstanceId ?? element.dataset.laneId ??
        element.dataset.groupId ?? element.dataset.annotationId ?? null,
      expected,
      actual,
    };
  }).filter(Boolean);
  const labelGeometryMismatches = Array.from(stage.querySelectorAll(
    '.journey-map-edge__label[data-edge-label-for]'
  )).map((element) => {
    const rect = element.getBoundingClientRect();
    const expectedX = Number(element.dataset.x);
    const expectedY = Number(element.dataset.y);
    const actualX = rect.left - stageRect.left + rect.width / 2;
    const actualY = rect.top - stageRect.top + rect.height / 2;
    return Number.isFinite(expectedX) && Number.isFinite(expectedY) &&
        Math.abs(expectedX - actualX) <= 0.75 &&
        Math.abs(expectedY - actualY) <= 0.75
      ? null
      : {
          edgeInstanceId: element.dataset.edgeLabelFor ?? null,
          expectedX,
          expectedY,
          actualX,
          actualY,
        };
  }).filter(Boolean);
  const routeParts = location.pathname.split('/').filter(Boolean);
  const deepLinkNodeId = routeParts.length === 4 &&
      routeParts[0] === 'journeys' && routeParts[1] === expectedJourneyId &&
      routeParts[2] === 'nodes'
    ? routeParts[3]
    : null;
  return {
    available: true,
    projectionId: stage.dataset.projectionId ?? null,
    layoutDigest: stage.dataset.layoutDigest ?? null,
    routePath: location.pathname,
    deepLinkNodeId,
    selectedNodeInstanceIds: nodes
      .filter((item) => item.selected)
      .map((item) => item.nodeInstanceId),
    nodeInstanceCount: nodes.length,
    edgeInstanceCount: edges.length,
    groupCount: groups.length,
    laneCount: lanes.length,
    annotationCount: annotations.length,
    windowCandidateCount: Number(stage.dataset.windowCandidates ?? '-1'),
    windowRenderedCount: Number(stage.dataset.windowRendered ?? '-1'),
    typedAttrGeometrySupported: CSS.supports(
      'width',
      'calc(attr(data-canvas-width type(<number>)) * 1px)'
    ),
    stageRendered: stageRect.width > 0 && stageRect.height > 0,
    stageGeometryValid:
      Math.abs(stageRect.width - Number(stage.dataset.canvasWidth)) <= 0.75 &&
      Math.abs(stageRect.height - Number(stage.dataset.canvasHeight)) <= 0.75,
    inlineStyleCount: stage.querySelectorAll('[style]').length +
      (stage.hasAttribute('style') ? 1 : 0),
    geometryMismatches,
    labelGeometryMismatches,
    nodeInstances: nodes,
    edgeInstances: edges,
    nodeInstanceIds: sortedNodeIds,
    edgeInstanceIds: sortedEdgeIds,
    groupIds: groups.sort(),
    laneIds: lanes.sort(),
    annotationIds: annotations.sort(),
    branchNodeIds,
    mergeNodeIds,
    duplicateDomIds: duplicates(allDomIds),
    duplicateNodeInstanceIds: duplicates(nodeIds),
    duplicateEdgeInstanceIds: duplicates(
      edges.map((item) => item.edgeInstanceId)
    ),
    duplicateGroupIds: duplicates(groups),
    duplicateLaneIds: duplicates(lanes),
    duplicateAnnotationIds: duplicates(annotations),
    allNodeDeepLinksValid: nodes.every((item) => item.deepLinkValid),
    allNodeIdentitiesValid: nodes.every((item) => item.identityValid),
    allEdgeEndpointsValid: edges.every((item) => item.endpointsValid),
    allEdgeGeometryValid: edges.every((item) => item.geometryValid),
    allEdgesSemantic: edges.every((item) => item.semanticRoleValid),
    allEdgesRendered: edges.every((item) => item.renderedLength > 0),
  };
})()
''');
    final result = _object(value, 'SpatialJourneyMapAudit');
    final layoutDigest = result['layoutDigest'];
    if (layoutDigest is! String) {
      throw StateError(
        'Spatial Journey Map omitted its layout digest: $result',
      );
    }
    Digest(layoutDigest);
    final selected = result['selectedNodeInstanceIds'];
    final branchNodes = result['branchNodeIds'];
    final mergeNodes = result['mergeNodeIds'];
    final nodeIds = result['nodeInstanceIds'];
    final edgeIds = result['edgeInstanceIds'];
    final groupIds = result['groupIds'];
    final laneIds = result['laneIds'];
    final annotationIds = result['annotationIds'];
    final duplicateFields = <String>[
      'duplicateDomIds',
      'duplicateNodeInstanceIds',
      'duplicateEdgeInstanceIds',
      'duplicateGroupIds',
      'duplicateLaneIds',
      'duplicateAnnotationIds',
    ];
    final hasDuplicates = duplicateFields.any(
      (field) =>
          (result[field] as List<Object?>? ?? const <Object?>[]).isNotEmpty,
    );
    if (result['available'] != true ||
        result['projectionId'] != 'delivery-journey' ||
        result['routePath'] !=
            '/journeys/operate-delivery-workspace/nodes/journey-dashboard-ready' ||
        result['deepLinkNodeId'] != 'journey-dashboard-ready' ||
        result['nodeInstanceCount'] != 5 ||
        result['edgeInstanceCount'] != 5 ||
        result['groupCount'] != 1 ||
        result['laneCount'] != 3 ||
        result['annotationCount'] != 1 ||
        result['windowCandidateCount'] != 5 ||
        result['windowRenderedCount'] != 5 ||
        result['typedAttrGeometrySupported'] != true ||
        result['stageRendered'] != true ||
        result['stageGeometryValid'] != true ||
        result['inlineStyleCount'] != 0 ||
        (result['geometryMismatches'] as List<Object?>? ?? const <Object?>[])
            .isNotEmpty ||
        (result['labelGeometryMismatches'] as List<Object?>? ??
                const <Object?>[])
            .isNotEmpty ||
        nodeIds is! List<Object?> ||
        !_sameStrings(nodeIds, const <String>[
          'journey-dashboard-failed',
          'journey-dashboard-loading',
          'journey-dashboard-ready',
          'journey-inspect-gateway-traffic',
          'journey-toggle-delivery-task',
        ]) ||
        edgeIds is! List<Object?> ||
        !_sameStrings(edgeIds, const <String>[
          'journey-loading-to-ready',
          'journey-ready-to-failed',
          'journey-ready-to-gateway',
          'journey-ready-to-toggle',
          'journey-toggle-to-gateway',
        ]) ||
        groupIds is! List<Object?> ||
        !_sameStrings(groupIds, const <String>['journey-branch-merge-group']) ||
        laneIds is! List<Object?> ||
        !_sameStrings(laneIds, const <String>[
          'journey-direct-lane',
          'journey-recovery-lane',
          'journey-task-lane',
        ]) ||
        annotationIds is! List<Object?> ||
        !_sameStrings(annotationIds, const <String>[
          'journey-branch-merge-note',
        ]) ||
        selected is! List<Object?> ||
        selected.length != 1 ||
        selected.single != 'journey-dashboard-ready' ||
        branchNodes is! List<Object?> ||
        !branchNodes.contains('journey-dashboard-ready') ||
        mergeNodes is! List<Object?> ||
        !mergeNodes.contains('journey-inspect-gateway-traffic') ||
        hasDuplicates ||
        result['allNodeDeepLinksValid'] != true ||
        result['allNodeIdentitiesValid'] != true ||
        result['allEdgeEndpointsValid'] != true ||
        result['allEdgeGeometryValid'] != true ||
        result['allEdgesSemantic'] != true ||
        result['allEdgesRendered'] != true) {
      throw StateError('Studio spatial Journey Map audit failed: $result');
    }
    return result;
  }

  static bool _sameStrings(List<Object?> actual, List<String> expected) =>
      actual.length == expected.length &&
      actual.indexed.every((entry) => entry.$2 == expected[entry.$1]);

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

  Future<void> waitForDoubleAnimationFrame() async {
    await evaluate<Object?>(r'''
new Promise((resolve) => requestAnimationFrame(
  () => requestAnimationFrame(resolve)
))
''');
  }

  Future<bool> revealScenarioQualityReviewForCapture() async =>
      await evaluate<bool>(r'''
(async () => {
  const review = document.querySelector('.scenario-quality-review');
  if (!(review instanceof HTMLElement)) return false;
  review.scrollIntoView({
    block: 'center',
    inline: 'nearest',
    behavior: 'instant',
  });
  await new Promise((resolve) => requestAnimationFrame(resolve));
  await new Promise((resolve) => requestAnimationFrame(resolve));
  const rect = review.getBoundingClientRect();
  const resources = Array.from(review.querySelectorAll(
    '[data-quality-resource-state][data-quality-resource-role]'
  ));
  const images = Array.from(review.querySelectorAll('img'));
  return rect.width > 0 && rect.height > 0 && rect.bottom > 0 &&
    rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth &&
    resources.length === 3 && resources.every((item) =>
      item.dataset.qualityResourceState === 'rendered'
    ) && images.every((image) =>
      image.complete && image.naturalWidth > 0 && image.naturalHeight > 0
    );
})()
''') ??
      false;

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

  void _recordScenarioLabControlState(String state) {
    if (!const <String>{'disabled', 'enabled'}.contains(state) ||
        !_scenarioLabControlStates.add(state)) {
      return;
    }
    final capture = _captureScenarioLabControl(state);
    _scenarioLabControlCaptures.add(capture);
    unawaited(capture);
  }

  Future<void> _captureScenarioLabControl(String state) async {
    try {
      final clipValue = await evaluate<Object?>(r'''
(() => {
  const frame = document.querySelector('.scenario-lab-relay-target iframe');
  if (!frame) return null;
  const rect = frame.getBoundingClientRect();
  if (rect.width <= 0 || rect.height <= 0) return null;
  return {
    x: rect.left + scrollX,
    y: rect.top + scrollY,
    width: rect.width,
    height: rect.height,
    scale: 1,
  };
})()
''');
      if (clipValue is! Map<String, Object?>) {
        throw StateError('Scenario Lab target iframe is not visible');
      }
      final result = await send('Page.captureScreenshot', <String, Object?>{
        'format': 'png',
        'fromSurface': true,
        'captureBeyondViewport': true,
        'clip': clipValue,
      });
      final data = result['data'];
      if (data is! String || data.length > 32 * 1024 * 1024) {
        throw const FormatException(
          'Scenario Lab target screenshot is invalid',
        );
      }
      final bytes = base64Decode(data);
      final inspection = const PngCaptureInspector().inspect(bytes);
      if (inspection.width < 200 || inspection.height < 200) {
        throw StateError(
          'Scenario Lab target screenshot is unexpectedly small',
        );
      }
      _scenarioLabControlScreenshots[state] = Digest.bytes(bytes);
    } on Object catch (error) {
      _scenarioLabControlCaptureErrors.add('$state:${error.runtimeType}');
    }
  }

  void _recordScenarioLabWebSocketFrame({
    required bool sent,
    required String payload,
  }) {
    if (payload.length > 64 * 1024) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) return;
    if (sent) {
      final method = decoded['method'];
      final id = decoded['id'];
      if (method is String && method.startsWith('lab.') && id is String) {
        _scenarioLabPendingRpc[id] = method;
        _scenarioLabRpcCounts.update(
          method,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (method == 'lab.relay.v2.describe') {
          try {
            _scenarioLabRelayV2PendingRequests[id] =
                ScenarioLabRelayDescribeRequestV2.fromJson(decoded['params']);
          } on Object {
            _scenarioLabRpcFailures.add(<String, Object?>{
              'method': method,
              'kind': 'invalidRequest',
            });
          }
        }
        if (method == 'lab.relay.hello') {
          try {
            _scenarioLabRelayHelloPendingRequests[id] =
                ScenarioLabRelayHelloSubmission.fromJson(decoded['params']);
          } on Object {
            _scenarioLabRpcFailures.add(<String, Object?>{
              'method': method,
              'kind': 'invalidRequest',
            });
          }
        }
        if (method == 'lab.relay.result') {
          try {
            final submission = ScenarioLabRelayResultSubmission.fromJson(
              decoded['params'],
            );
            _scenarioLabRelayResultPendingRequests[id] = submission;
            final result = submission.result;
            _scenarioLabRelayResults.add(<String, Object?>{
              'operation': result.operation.name,
              'sequence': result.sequence,
              'state': result.state.name,
              if (result.failure != null) 'failure': result.failure!.cause.name,
              if (result is CaptureAppAdapterRelayResult)
                'uploadAcknowledged': result.uploadRequestId != null,
            });
          } on Object {
            _scenarioLabRpcFailures.add(<String, Object?>{
              'method': method,
              'kind': 'invalidRequest',
            });
            _scenarioLabRelayResults.add(const <String, Object?>{
              'decode': 'invalid',
            });
          }
        }
      } else if (method is String && method.startsWith('quality.')) {
        if (id is! String || !_scenarioQualityRpcMethods.contains(method)) {
          _scenarioQualityRpcFailures.add(<String, Object?>{
            'method': method,
            'kind': 'unexpectedRequest',
          });
          return;
        }
        _scenarioQualityPendingRpc[id] = method;
        _scenarioQualityRpcCounts.update(
          method,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      return;
    }
    final id = decoded['id'];
    if (id is! String) return;
    final labMethod = _scenarioLabPendingRpc.remove(id);
    final relayV2Request = _scenarioLabRelayV2PendingRequests.remove(id);
    final relayHelloRequest = _scenarioLabRelayHelloPendingRequests.remove(id);
    final relayResultRequest = _scenarioLabRelayResultPendingRequests.remove(
      id,
    );
    final qualityMethod = _scenarioQualityPendingRpc.remove(id);
    if (labMethod == null && qualityMethod == null) return;
    final error = decoded['error'];
    if (error is Map<String, Object?>) {
      if (labMethod != null) {
        _scenarioLabRpcFailures.add(<String, Object?>{
          'method': labMethod,
          'code': error['code'],
        });
      }
      if (qualityMethod != null) {
        _recordScenarioQualityError(qualityMethod, error);
      }
      return;
    }
    if (qualityMethod != null) {
      _recordScenarioQualityResult(qualityMethod, decoded['result']);
      return;
    }
    final method = labMethod!;
    if (!decoded.containsKey('result')) {
      _scenarioLabRpcFailures.add(<String, Object?>{
        'method': method,
        'kind': 'missingResult',
      });
      return;
    }
    _scenarioLabRpcResultCounts.update(
      method,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (method == 'lab.relay.v2.describe') {
      if (relayV2Request == null) {
        _scenarioLabRpcFailures.add(const <String, Object?>{
          'method': 'lab.relay.v2.describe',
          'kind': 'missingRequestFence',
        });
        return;
      }
      try {
        final description = ScenarioLabRelayDescriptionV2.fromJson(
          decoded['result'],
        );
        description.validateAgainst(relayV2Request);
        _scenarioLabRelayV2Exchanges.add((relayV2Request, description));
      } on Object {
        _scenarioLabRpcFailures.add(const <String, Object?>{
          'method': 'lab.relay.v2.describe',
          'kind': 'invalidResult',
        });
      }
      return;
    }
    if (method == 'lab.relay.hello') {
      if (relayHelloRequest == null) {
        _scenarioLabRpcFailures.add(const <String, Object?>{
          'method': 'lab.relay.hello',
          'kind': 'missingRequestFence',
        });
        return;
      }
      try {
        final acknowledgement = ScenarioLabRelayHelloAcknowledgement.fromJson(
          decoded['result'],
        );
        if (acknowledgement.runId != relayHelloRequest.hello.runId ||
            acknowledgement.descriptorDigest !=
                relayHelloRequest.descriptorDigest ||
            acknowledgement.acceptedHelloDigest !=
                relayHelloRequest.hello.digest) {
          throw const FormatException(
            'Scenario Lab relay Hello acknowledgement fence mismatch',
          );
        }
        _scenarioLabRelayHelloExchanges.add((
          relayHelloRequest,
          acknowledgement,
        ));
      } on Object {
        _scenarioLabRpcFailures.add(const <String, Object?>{
          'method': 'lab.relay.hello',
          'kind': 'invalidResult',
        });
      }
      return;
    }
    if (method == 'lab.relay.result') {
      if (relayResultRequest == null) {
        _scenarioLabRpcFailures.add(const <String, Object?>{
          'method': 'lab.relay.result',
          'kind': 'missingRequestFence',
        });
        return;
      }
      try {
        final acknowledgement = ScenarioLabRelayResultAcknowledgement.fromJson(
          decoded['result'],
        );
        if (acknowledgement.runId != relayResultRequest.result.runId ||
            acknowledgement.descriptorDigest !=
                relayResultRequest.descriptorDigest ||
            acknowledgement.acceptedResultDigest !=
                relayResultRequest.result.resultDigest) {
          throw const FormatException(
            'Scenario Lab relay result acknowledgement fence mismatch',
          );
        }
        _scenarioLabRelayResultExchanges.add((
          relayResultRequest,
          acknowledgement,
        ));
      } on Object {
        _scenarioLabRpcFailures.add(const <String, Object?>{
          'method': 'lab.relay.result',
          'kind': 'invalidResult',
        });
      }
      return;
    }
    if (!const <String>{
      'lab.start',
      'lab.get',
      'lab.cancel',
      'lab.reattach',
    }.contains(method)) {
      return;
    }
    final result = decoded['result'];
    if (result is Map<String, Object?>) {
      _scenarioLabRunResults.add((method, result));
    }
  }

  void _recordScenarioLabChildFrameNavigation({
    required String frameId,
    required String rawUrl,
  }) {
    if (rawUrl.length > 16384 ||
        _scenarioLabChildFrameNavigations.length >= 256) {
      return;
    }
    final navigation = _ScenarioLabChildFrameNavigation.tryParse(
      frameId: frameId,
      rawUrl: rawUrl,
    );
    if (navigation != null) {
      _scenarioLabChildFrameNavigations.add(navigation);
    }
  }

  void _recordScenarioQualityError(String method, Map<String, Object?> error) {
    if (error['code'] != ScenarioQualityDecisionError.jsonRpcCode) {
      _scenarioQualityRpcFailures.add(<String, Object?>{
        'method': method,
        'kind': 'unexpectedErrorCode',
        'jsonRpcCode': error['code'],
      });
      return;
    }
    try {
      final typed = ScenarioQualityDecisionError.fromJson(error['data']);
      _scenarioQualityRpcFailures.add(<String, Object?>{
        'method': method,
        'kind': 'typedError',
        'operation': typed.operation.name,
        'code': typed.code.name,
      });
    } on Object {
      _scenarioQualityRpcFailures.add(<String, Object?>{
        'method': method,
        'kind': 'invalidErrorData',
        'jsonRpcCode': error['code'],
      });
    }
  }

  void _recordScenarioQualityResult(String method, Object? value) {
    try {
      switch (method) {
        case 'quality.describe':
          _scenarioQualityDescriptions.add(
            ScenarioQualityDescribeResult.fromJson(value),
          );
        case 'quality.open':
          final opened = ScenarioQualityReviewOpenResult.fromJson(value);
          _scenarioQualityReviewSetResults.add(
            _scenarioQualityReviewSetSummary(opened),
          );
        case 'quality.decision.grant':
          ScenarioQualityDecisionGrant.fromJson(value);
        case 'quality.decision.append':
          final appended = ScenarioQualityDecisionAppendResult.fromJson(value);
          _scenarioQualityAppendResultSummaries.add(
            _scenarioQualityAppendSummary(appended),
          );
        case 'quality.decision.get':
          final view = ScenarioQualityDecisionView.fromJson(value);
          _scenarioQualityDecisionViewSummaries.add(
            _scenarioQualityDecisionViewSummary(view),
          );
        default:
          throw const FormatException('Unexpected Scenario Quality result');
      }
      _scenarioQualityRpcResultCounts.update(
        method,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    } on Object {
      _scenarioQualityRpcFailures.add(<String, Object?>{
        'method': method,
        'kind': 'invalidResult',
      });
    }
  }

  static Map<String, Object?> _scenarioQualityReviewSetSummary(
    ScenarioQualityReviewOpenResult opened,
  ) {
    final descriptor = opened.reviewDescriptor;
    return <String, Object?>{
      'runId': descriptor.runId.value,
      'runResultDigest': descriptor.runResultDigest.value,
      'requirementId': descriptor.requirementId.value,
      'requirementScope': descriptor.requirementScope.name,
      'reviewGuideId': descriptor.reviewGuideId.value,
      'reviewGuideStepId': descriptor.reviewGuideStepId,
      'requiredEvidenceResultDigests': <String>[
        for (final digest in descriptor.requiredEvidenceResultDigests)
          digest.value,
      ],
      'comparisonResultDigests': <String>[
        for (final digest in descriptor.comparisonResultDigests) digest.value,
      ],
      'resourceCount': opened.resources.length,
      'artifacts': <Object?>[
        for (final artifact in descriptor.artifacts)
          <String, Object?>{
            'descriptorDigest': artifact.digest.value,
            'requiredEvidenceId': artifact.requiredEvidenceId.value,
            'requiredEvidenceResultDigest':
                artifact.requiredEvidenceResultDigest.value,
            'role': artifact.role.name,
            'artifactDigest': artifact.artifactDigest.value,
            'provenanceDigest': artifact.provenanceDigest.value,
            'provenanceKind': artifact.provenanceKind.name,
            'classification': artifact.classification.name,
            'mediaType': artifact.mediaType,
            'size': artifact.size,
            if (artifact.comparisonResultDigest case final comparison?)
              'comparisonResultDigest': comparison.value,
          },
      ],
    };
  }

  static Map<String, Object?> _scenarioQualityAppendSummary(
    ScenarioQualityDecisionAppendResult appended,
  ) => _scenarioQualityDecisionSummary(
    record: appended.record,
    projection: appended.quality.humanDecision,
    attribution: appended.attribution,
  );

  static Map<String, Object?> _scenarioQualityDecisionViewSummary(
    ScenarioQualityDecisionView view,
  ) => _scenarioQualityDecisionSummary(
    record: view.record,
    projection: view.projection,
    attribution: view.attribution,
  );

  static Map<String, Object?> _scenarioQualityDecisionSummary({
    required HumanDecisionRecord record,
    required HumanDecisionProjection projection,
    required ScenarioQualityDecisionAttribution attribution,
  }) => <String, Object?>{
    'recordId': record.id.value,
    'decisionDigest': record.digest.value,
    'subjectDigest': record.subjectDigest.value,
    'principalId': record.principalId.value,
    'decision': record.decision.name,
    'decidedAt': record.decidedAt.toIso8601String(),
    'supersedesDecisionDigest': record.supersedesDecisionDigest?.value,
    'state': projection.state.name,
    'supersededByDecisionDigest': projection.supersededByDecisionDigest?.value,
    'attribution': <String, Object?>{
      'runId': attribution.runId.value,
      'runResultDigest': attribution.runResultDigest.value,
      'reviewDescriptorDigest': attribution.reviewDescriptorDigest.value,
      'requirementId': attribution.requirementId.value,
      'requirementScope': attribution.requirementScope.name,
      'reviewGuideId': attribution.reviewGuideId.value,
      'reviewGuideStepId': attribution.reviewGuideStepId,
      'authorityId': attribution.authorityId.value,
      'accessPolicyId': attribution.accessPolicyId.value,
      'principalId': attribution.principalId.value,
      'role': attribution.role.name,
    },
  };

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
    if (method == 'Page.frameNavigated' &&
        params is Map<String, Object?> &&
        params['frame'] is Map<String, Object?>) {
      final frame = params['frame']! as Map<String, Object?>;
      final frameId = frame['id'];
      final url = frame['url'];
      if (frame['parentId'] is String && frameId is String) {
        if (_scenarioLabChildFrameIds.length < 256) {
          _scenarioLabChildFrameIds.add(frameId);
        }
        if (url is String) {
          _recordScenarioLabChildFrameNavigation(frameId: frameId, rawUrl: url);
        }
      }
    }
    if (method == 'Page.navigatedWithinDocument' &&
        params is Map<String, Object?>) {
      final frameId = params['frameId'];
      final url = params['url'];
      if (frameId is String &&
          _scenarioLabChildFrameIds.contains(frameId) &&
          url is String) {
        _recordScenarioLabChildFrameNavigation(frameId: frameId, rawUrl: url);
      }
    }
    if (method == 'Network.requestWillBeSent' &&
        params is Map<String, Object?> &&
        params['request'] is Map<String, Object?>) {
      final request = params['request']! as Map<String, Object?>;
      final requestId = params['requestId'];
      final frameId = params['frameId'];
      final initiator = params['initiator'];
      final url = request['url'];
      final requestMethod = request['method'];
      if (url is String) resourceUrls.add(url);
      final location = url is String
          ? _ScenarioLabNetworkLocation.tryParse(url)
          : null;
      final initiatorType = initiator is Map<String, Object?>
          ? initiator['type']
          : null;
      if (requestId is String &&
          requestId.isNotEmpty &&
          requestId.length <= 512 &&
          requestMethod is String &&
          requestMethod.isNotEmpty &&
          requestMethod.length <= 32 &&
          location != null) {
        if (_scenarioLabNetworkRequests.length >= 4096) {
          _scenarioLabNetworkTraceOverflowed = true;
        } else if (_scenarioLabNetworkRequests.containsKey(requestId)) {
          _scenarioLabAmbiguousNetworkRequestIds.add(requestId);
        } else {
          _scenarioLabNetworkRequests[requestId] = _ScenarioLabNetworkRequest(
            location: location,
            method: requestMethod,
            frameId: frameId is String && frameId.length <= 512
                ? frameId
                : null,
            initiatorType: initiatorType is String && initiatorType.length <= 64
                ? initiatorType
                : null,
          );
        }
      }
    }
    if (method == 'Network.responseReceived' &&
        params is Map<String, Object?> &&
        params['response'] is Map<String, Object?>) {
      final response = params['response']! as Map<String, Object?>;
      final requestId = params['requestId'];
      final url = response['url'];
      final status = response['status'];
      final location = url is String
          ? _ScenarioLabNetworkLocation.tryParse(url)
          : null;
      if (requestId is String &&
          requestId.isNotEmpty &&
          requestId.length <= 512 &&
          status is num &&
          location != null) {
        if (_scenarioLabNetworkResponses.length >= 4096) {
          _scenarioLabNetworkTraceOverflowed = true;
        } else if (_scenarioLabNetworkResponses.containsKey(requestId)) {
          _scenarioLabAmbiguousNetworkRequestIds.add(requestId);
        } else {
          _scenarioLabNetworkResponses[requestId] = _ScenarioLabNetworkResponse(
            location: location,
            status: status,
          );
        }
      }
    }
    if ((method == 'Network.webSocketFrameSent' ||
            method == 'Network.webSocketFrameReceived') &&
        params is Map<String, Object?>) {
      final response = params['response'];
      if (response is Map<String, Object?> &&
          response['payloadData'] is String) {
        _recordScenarioLabWebSocketFrame(
          sent: method == 'Network.webSocketFrameSent',
          payload: response['payloadData']! as String,
        );
      }
    }
    if (method == 'Runtime.consoleAPICalled' &&
        params is Map<String, Object?> &&
        params['args'] is List<Object?>) {
      const marker = 'SCENARIO_LAB_CONTROL:';
      for (final argument in params['args']! as List<Object?>) {
        if (argument is! Map<String, Object?> || argument['value'] is! String) {
          continue;
        }
        final value = argument['value']! as String;
        if (value.startsWith(marker)) {
          _recordScenarioLabControlState(value.substring(marker.length));
        }
      }
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
