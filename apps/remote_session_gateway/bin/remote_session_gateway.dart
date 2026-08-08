import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_remote_session_gateway/remote_session_gateway.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:jose/jose.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final environment = Platform.environment;
  String requiredValue(String name) {
    final value = environment[name];
    if (value == null || value.isEmpty) throw StateError('$name is required');
    return value;
  }

  String? optionalValue(String name) {
    final value = environment[name];
    return value == null || value.isEmpty ? null : value;
  }

  final trustFile = File(requiredValue('DEVEX_REMOTE_JWKS_FILE'));
  if (!trustFile.existsSync() ||
      Link(trustFile.path).existsSync() ||
      trustFile.lengthSync() > 1024 * 1024) {
    throw StateError('remote gateway trust file is invalid');
  }
  final trust = jsonDecode(trustFile.readAsStringSync());
  if (trust is! Map<String, Object?>) {
    throw StateError('remote gateway trust file is not a JWK set');
  }
  final clock = SystemClock();
  final targetOrigin = optionalValue('DEVEX_WEB_TARGET_ORIGIN');
  final application = RemoteSessionGatewayApplication(
    verifier: RemoteWorkerTokenVerifier(
      trustedKeys: JsonWebKeySet.fromJson(trust),
      allowedAlgorithms: (environment['DEVEX_REMOTE_ALGORITHMS'] ?? 'ES256')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet(),
      clock: clock,
    ),
    expectedRunId: requiredValue('DEVEX_RUN_ID'),
    allowedViewerOrigins: requiredValue('DEVEX_ALLOWED_STUDIO_ORIGINS')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet(),
    sessionDeadline: DateTime.parse(
      requiredValue('DEVEX_SESSION_DEADLINE'),
    ).toUtc(),
    clock: clock,
    webTargetOrigin: targetOrigin == null ? null : Uri.parse(targetOrigin),
  );
  final port = int.parse(environment['PORT'] ?? '27183');
  if (port < 1 || port > 65535) throw StateError('PORT is invalid');
  final server = await shelf_io.serve(
    application.handler,
    InternetAddress.anyIPv4,
    port,
    poweredByHeader: null,
  );
  stdout.writeln('devex remote session gateway listening on ${server.port}');

  final stopping = Completer<void>();
  late final StreamSubscription<ProcessSignal> term;
  late final StreamSubscription<ProcessSignal> interrupt;
  Future<void> stop(ProcessSignal _) async {
    if (stopping.isCompleted) return;
    await server.close(force: false);
    await application.close();
    stopping.complete();
  }

  term = ProcessSignal.sigterm.watch().listen(stop);
  interrupt = ProcessSignal.sigint.watch().listen(stop);
  await stopping.future;
  await term.cancel();
  await interrupt.cancel();
}
