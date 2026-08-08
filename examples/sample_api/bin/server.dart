import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sample_api/sample_api.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> arguments) async {
  final options = _ServerOptions.parse(arguments);
  final server = await shelf_io.serve(
    SampleApiHandler().handler,
    options.host,
    options.port,
    poweredByHeader: null,
  );
  stdout.writeln(
    jsonEncode(<String, Object?>{
      'status': 'ready',
      'service': 'sample-api',
      'origin': 'http://${server.address.address}:${server.port}',
      'pid': pid,
    }),
  );

  final stopping = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigint;
  late final StreamSubscription<ProcessSignal> sigterm;
  void stop(ProcessSignal signal) {
    if (!stopping.isCompleted) stopping.complete();
  }

  sigint = ProcessSignal.sigint.watch().listen(stop);
  sigterm = ProcessSignal.sigterm.watch().listen(stop);
  await stopping.future;
  await server.close(force: true);
  await sigint.cancel();
  await sigterm.cancel();
}

final class _ServerOptions {
  const _ServerOptions({required this.host, required this.port});

  final InternetAddress host;
  final int port;

  factory _ServerOptions.parse(List<String> arguments) {
    var host = InternetAddress.loopbackIPv4;
    var port = 8181;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      String value(String name) {
        if (index + 1 >= arguments.length) {
          throw FormatException('$name requires a value');
        }
        index += 1;
        return arguments[index];
      }

      switch (argument) {
        case '--host':
          final parsed = InternetAddress.tryParse(value('--host'));
          if (parsed == null || !parsed.isLoopback) {
            throw const FormatException('--host must be a loopback address');
          }
          host = parsed;
        case '--port':
          port = int.parse(value('--port'));
          if (port < 0 || port > 65535) {
            throw const FormatException('--port must be between 0 and 65535');
          }
        default:
          throw FormatException('Unknown option $argument');
      }
    }
    return _ServerOptions(host: host, port: port);
  }
}
