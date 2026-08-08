import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await _ip(<String>['link', 'set', 'lo', 'up']);
  final broker = _GatewayBroker();
  final gateway = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    gateway.listen((request) async {
      if (request.uri.path != '/probe') {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        final response = await broker.call('/allowlisted-probe');
        request.response.statusCode = response.status;
        request.response.headers.set('access-control-allow-origin', '*');
        request.response.headers.set(
          'access-control-expose-headers',
          'x-devex-gateway-path',
        );
        request.response.headers.set(
          'x-devex-gateway-path',
          response.allowlisted ? 'passthrough' : 'invalid',
        );
      }
      await request.response.close();
    });
    target.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(_page(gateway.port));
      await request.response.close();
    });
    final result = await Process.run(_chromeExecutable(), <String>[
      '--headless=new',
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--disable-background-networking',
      '--disable-component-update',
      '--disable-default-apps',
      '--disable-sync',
      '--metrics-recording-only',
      '--no-first-run',
      '--run-all-compositor-stages-before-draw',
      '--virtual-time-budget=5000',
      '--dump-dom',
      'http://127.0.0.1:${target.port}/',
    ]).timeout(const Duration(seconds: 20));
    final dom = '${result.stdout}';
    final output = <String, Object?>{
      'type': 'result',
      'gatewayPassed': dom.contains('data-gateway="pass"'),
      'egressPassed': dom.contains('data-egress="pass"'),
      'chromeExitCode': result.exitCode,
    };
    stdout.writeln(jsonEncode(output));
    if (result.exitCode != 0 ||
        output['gatewayPassed'] != true ||
        output['egressPassed'] != true) {
      exitCode = 1;
    }
  } finally {
    await gateway.close(force: true);
    await target.close(force: true);
    await broker.close();
  }
}

final class _GatewayBroker {
  _GatewayBroker() {
    _subscription = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_receive);
  }

  late final StreamSubscription<String> _subscription;
  final _pending = <int, Completer<_GatewayResponse>>{};
  var _nextId = 1;

  Future<_GatewayResponse> call(String path) {
    final id = _nextId++;
    final completer = Completer<_GatewayResponse>();
    _pending[id] = completer;
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'type': 'gateway.request',
        'id': id,
        'path': path,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 5));
  }

  void _receive(String line) {
    final message = jsonDecode(line) as Map<String, Object?>;
    if (message['type'] != 'gateway.response') return;
    final id = message['id']! as int;
    _pending
        .remove(id)
        ?.complete(
          _GatewayResponse(
            status: message['status']! as int,
            allowlisted: message['allowlisted']! as bool,
          ),
        );
  }

  Future<void> close() async {
    await _subscription.cancel();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Gateway broker closed'));
      }
    }
    _pending.clear();
  }
}

final class _GatewayResponse {
  const _GatewayResponse({required this.status, required this.allowlisted});

  final int status;
  final bool allowlisted;
}

Future<void> _ip(List<String> arguments) async {
  final result = await Process.run('ip', arguments);
  if (result.exitCode != 0) {
    throw StateError('ip ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

String _chromeExecutable() {
  final configured = Platform.environment['CHROME_EXECUTABLE'];
  if (configured != null && File(configured).existsSync()) return configured;
  final path = Platform.environment['PATH'] ?? '';
  for (final name in <String>[
    'google-chrome',
    'google-chrome-stable',
    'chromium',
  ]) {
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      final candidate = File('$directory${Platform.pathSeparator}$name');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  throw StateError('Chrome/Chromium executable not found');
}

String _page(int gatewayPort) =>
    '''<!doctype html>
<html><head><meta charset="utf-8"><title>running</title></head>
<body data-gateway="pending" data-egress="pending">
<script>
(async () => {
  try {
    const response = await fetch('http://127.0.0.1:$gatewayPort/probe');
    document.body.dataset.gateway =
      response.status === 204 &&
      response.headers.get('x-devex-gateway-path') === 'passthrough'
        ? 'pass' : 'fail';
  } catch (_) {
    document.body.dataset.gateway = 'fail';
  }
  try {
    await fetch('http://192.0.2.1:9/bypass', {
      mode: 'no-cors',
      signal: AbortSignal.timeout(1500)
    });
    document.body.dataset.egress = 'fail';
  } catch (_) {
    document.body.dataset.egress = 'pass';
  }
  document.title = 'done';
})();
</script></body></html>''';
