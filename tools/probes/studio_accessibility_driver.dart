import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final debuggerUri = Uri.parse('http://${options.host}:${options.port}');
  final target = await _findTarget(debuggerUri, options.targetUrlPrefix);
  stdout.writeln('TARGET ${target.url}');

  // ignore: close_sinks
  final socket = await WebSocket.connect(target.webSocketDebuggerUrl);
  final cdp = _CdpClient(socket);
  try {
    await cdp.command('Accessibility.enable');
    final colorScheme = options.colorScheme;
    if (colorScheme != null) {
      await cdp.command('Emulation.setEmulatedMedia', <String, Object?>{
        'features': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'prefers-color-scheme',
            'value': colorScheme,
          },
        ],
      });
      await Future<void>.delayed(options.settleDelay);
    }
    if (options.enableFlutterSemantics) {
      await _enableFlutterSemantics(cdp);
      await Future<void>.delayed(options.settleDelay);
    }
    await _printSnapshot(cdp, 'initial');
    for (final key in options.keys) {
      await _dispatchKey(cdp, key);
      await Future<void>.delayed(options.settleDelay);
      await _printSnapshot(cdp, 'after ${key.label}');
    }
    if (options.reload) {
      await cdp.command('Page.reload');
      await Future<void>.delayed(options.reloadDelay);
      if (options.enableFlutterSemantics) {
        await _enableFlutterSemantics(cdp);
        await Future<void>.delayed(options.settleDelay);
      }
      await _printSnapshot(cdp, 'after reload');
    }
    final screenshotPath = options.screenshotPath;
    if (screenshotPath != null) {
      final response = await cdp.command(
        'Page.captureScreenshot',
        const <String, Object?>{'format': 'png', 'fromSurface': true},
      );
      final result = response['result'];
      final data = result is Map<String, Object?> ? result['data'] : null;
      if (data is! String) {
        throw const FormatException('Page.captureScreenshot omitted data');
      }
      File(screenshotPath).writeAsBytesSync(base64Decode(data), flush: true);
      stdout.writeln('SCREENSHOT $screenshotPath');
    }
  } finally {
    await cdp.close();
  }
}

Future<void> _enableFlutterSemantics(_CdpClient cdp) =>
    cdp.command('Runtime.evaluate', <String, Object?>{
      'expression': '''
      (() => {
        const placeholder = document.querySelector(
          'flt-semantics-placeholder'
        );
        if (!placeholder) return 'already-enabled-or-unavailable';
        placeholder.click();
        return 'enabled';
      })()
    ''',
      'returnByValue': true,
    });

Future<_Target> _findTarget(Uri debuggerUri, String urlPrefix) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.getUrl(debuggerUri.resolve('/json/list'));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'DevTools target list returned ${response.statusCode}',
      );
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (output, chunk) => output..addAll(chunk),
    );
    final targets = jsonDecode(utf8.decode(bytes));
    if (targets is! List<Object?>) {
      throw const FormatException('DevTools target list is not an array');
    }
    for (final value in targets) {
      if (value is! Map<String, Object?>) continue;
      final url = value['url'];
      final websocket = value['webSocketDebuggerUrl'];
      if (url is String && websocket is String && url.startsWith(urlPrefix)) {
        return _Target(url: url, webSocketDebuggerUrl: websocket);
      }
    }
    throw StateError('No page target starts with $urlPrefix');
  } finally {
    client.close(force: true);
  }
}

Future<void> _dispatchKey(_CdpClient cdp, _KeyStroke stroke) async {
  if (stroke.modifiers == 8) {
    await cdp.command('Input.dispatchKeyEvent', const <String, Object?>{
      'type': 'rawKeyDown',
      'key': 'Shift',
      'code': 'ShiftLeft',
      'windowsVirtualKeyCode': 16,
      'nativeVirtualKeyCode': 16,
      'modifiers': 8,
    });
  }
  final common = <String, Object?>{
    'key': stroke.key,
    'code': stroke.code,
    'windowsVirtualKeyCode': stroke.virtualKey,
    'nativeVirtualKeyCode': stroke.virtualKey,
    if (stroke.modifiers != 0) 'modifiers': stroke.modifiers,
  };
  await cdp.command('Input.dispatchKeyEvent', <String, Object?>{
    ...common,
    'type': 'rawKeyDown',
  });
  await cdp.command('Input.dispatchKeyEvent', <String, Object?>{
    ...common,
    'type': 'keyUp',
  });
  if (stroke.modifiers == 8) {
    await cdp.command('Input.dispatchKeyEvent', const <String, Object?>{
      'type': 'keyUp',
      'key': 'Shift',
      'code': 'ShiftLeft',
      'windowsVirtualKeyCode': 16,
      'nativeVirtualKeyCode': 16,
    });
  }
}

Future<void> _printSnapshot(_CdpClient cdp, String label) async {
  final metricsResponse = await cdp
      .command('Runtime.evaluate', <String, Object?>{
        'expression': '''JSON.stringify({
        width: window.innerWidth,
        height: window.innerHeight,
        devicePixelRatio: window.devicePixelRatio,
        visualScale: window.visualViewport?.scale ?? 1,
        scrollWidth: document.documentElement.scrollWidth,
        scrollHeight: document.documentElement.scrollHeight
      })''',
        'returnByValue': true,
      });
  final response = await cdp.command('Accessibility.getFullAXTree');
  final result = response['result'];
  final nodes = result is Map<String, Object?> ? result['nodes'] : null;
  if (nodes is! List<Object?>) {
    throw const FormatException('Accessibility.getFullAXTree omitted nodes');
  }
  final metrics = metricsResponse['result'];
  final metricsResult = metrics is Map<String, Object?>
      ? metrics['result']
      : null;
  final metricsValue = metricsResult is Map<String, Object?>
      ? metricsResult['value']
      : null;
  stdout.writeln('--- $label metrics=$metricsValue ---');
  for (final value in nodes) {
    if (value is! Map<String, Object?> || value['ignored'] == true) continue;
    final role = _axValue(value['role']);
    final name = _axValue(value['name']);
    final focused = _axBooleanProperty(value['properties'], 'focused');
    final focusable = _axBooleanProperty(value['properties'], 'focusable');
    if (focused || (name.isNotEmpty && _meaningfulRoles.contains(role))) {
      stdout.writeln(
        '${focused ? 'FOCUS' : 'NODE '} role=$role '
        'name=${jsonEncode(name)} focusable=$focusable',
      );
    }
  }
}

String _axValue(Object? value) {
  if (value is! Map<String, Object?>) return '';
  final actual = value['value'];
  return actual is String ? actual : '';
}

bool _axBooleanProperty(Object? properties, String name) {
  if (properties is! List<Object?>) return false;
  for (final value in properties) {
    if (value is! Map<String, Object?> || value['name'] != name) continue;
    final wrapped = value['value'];
    return wrapped is Map<String, Object?> && wrapped['value'] == true;
  }
  return false;
}

const Set<String> _meaningfulRoles = <String>{
  'button',
  'checkbox',
  'dialog',
  'heading',
  'link',
  'list',
  'listitem',
  'main',
  'navigation',
  'radio',
  'tab',
};

final class _CdpClient {
  _CdpClient(this._socket) : _messages = StreamIterator<Object?>(_socket);

  final WebSocket _socket;
  final StreamIterator<Object?> _messages;
  var _nextId = 0;

  Future<Map<String, Object?>> command(
    String method, [
    Map<String, Object?> parameters = const <String, Object?>{},
  ]) async {
    final id = ++_nextId;
    _socket.add(
      jsonEncode(<String, Object?>{
        'id': id,
        'method': method,
        if (parameters.isNotEmpty) 'params': parameters,
      }),
    );
    while (await _messages.moveNext()) {
      final decoded = jsonDecode(_messages.current! as String);
      if (decoded is! Map<String, Object?> || decoded['id'] != id) continue;
      final error = decoded['error'];
      if (error != null) throw StateError('$method failed: $error');
      return decoded;
    }
    throw StateError('DevTools connection closed during $method');
  }

  Future<void> close() async {
    await _messages.cancel();
    await _socket.close();
  }
}

final class _Target {
  const _Target({required this.url, required this.webSocketDebuggerUrl});

  final String url;
  final String webSocketDebuggerUrl;
}

final class _Options {
  const _Options({
    required this.host,
    required this.port,
    required this.targetUrlPrefix,
    required this.keys,
    required this.enableFlutterSemantics,
    required this.reload,
    required this.screenshotPath,
    required this.colorScheme,
    required this.settleDelay,
    required this.reloadDelay,
  });

  final String host;
  final int port;
  final String targetUrlPrefix;
  final List<_KeyStroke> keys;
  final bool enableFlutterSemantics;
  final bool reload;
  final String? screenshotPath;
  final String? colorScheme;
  final Duration settleDelay;
  final Duration reloadDelay;

  static _Options parse(List<String> arguments) {
    var host = '127.0.0.1';
    var port = 9222;
    var targetUrlPrefix = 'http://127.0.0.1';
    var enableFlutterSemantics = false;
    var reload = false;
    String? screenshotPath;
    String? colorScheme;
    var settleMilliseconds = 500;
    var reloadMilliseconds = 1500;
    var keys = <_KeyStroke>[];
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      String next() {
        if (++index >= arguments.length) {
          throw FormatException('Missing value after $argument');
        }
        return arguments[index];
      }

      switch (argument) {
        case '--host':
          host = next();
        case '--port':
          port = int.parse(next());
        case '--target-url-prefix':
          targetUrlPrefix = next();
        case '--keys':
          keys = next()
              .split(',')
              .where((value) => value.isNotEmpty)
              .map(_KeyStroke.parse)
              .toList(growable: false);
        case '--reload':
          reload = true;
        case '--enable-flutter-semantics':
          enableFlutterSemantics = true;
        case '--settle-ms':
          settleMilliseconds = int.parse(next());
        case '--reload-ms':
          reloadMilliseconds = int.parse(next());
        case '--screenshot':
          screenshotPath = next();
        case '--color-scheme':
          colorScheme = next();
        default:
          throw FormatException('Unknown argument: $argument');
      }
    }
    if (port < 1 ||
        port > 65535 ||
        settleMilliseconds < 0 ||
        (screenshotPath != null &&
            (!p.isAbsolute(screenshotPath) ||
                !screenshotPath.endsWith('.png'))) ||
        (colorScheme != null &&
            !const <String>{'light', 'dark'}.contains(colorScheme))) {
      throw const FormatException('Invalid browser driver bounds');
    }
    return _Options(
      host: host,
      port: port,
      targetUrlPrefix: targetUrlPrefix,
      keys: List<_KeyStroke>.unmodifiable(keys),
      enableFlutterSemantics: enableFlutterSemantics,
      reload: reload,
      screenshotPath: screenshotPath,
      colorScheme: colorScheme,
      settleDelay: Duration(milliseconds: settleMilliseconds),
      reloadDelay: Duration(milliseconds: reloadMilliseconds),
    );
  }
}

final class _KeyStroke {
  const _KeyStroke({
    required this.label,
    required this.key,
    required this.code,
    required this.virtualKey,
    this.modifiers = 0,
  });

  final String label;
  final String key;
  final String code;
  final int virtualKey;
  final int modifiers;

  static _KeyStroke parse(String value) => switch (value) {
    'Tab' => const _KeyStroke(
      label: 'Tab',
      key: 'Tab',
      code: 'Tab',
      virtualKey: 9,
    ),
    'Shift+Tab' => const _KeyStroke(
      label: 'Shift+Tab',
      key: 'Tab',
      code: 'Tab',
      virtualKey: 9,
      modifiers: 8,
    ),
    'Enter' => const _KeyStroke(
      label: 'Enter',
      key: 'Enter',
      code: 'Enter',
      virtualKey: 13,
    ),
    'Space' => const _KeyStroke(
      label: 'Space',
      key: ' ',
      code: 'Space',
      virtualKey: 32,
    ),
    'Ctrl++' => const _KeyStroke(
      label: 'Ctrl++',
      key: '+',
      code: 'Equal',
      virtualKey: 187,
      modifiers: 2,
    ),
    _ => throw FormatException('Unsupported key stroke: $value'),
  };
}
