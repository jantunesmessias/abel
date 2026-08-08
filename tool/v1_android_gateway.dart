import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';

Future<void> main(List<String> arguments) async {
  final port = arguments.length == 2 && arguments.first == '--port'
      ? int.tryParse(arguments[1])
      : null;
  if (port == null || port < 1 || port > 65535) {
    stderr.writeln(
      'Usage: dart run tool/v1_android_gateway.dart --port <port>',
    );
    exitCode = 64;
    return;
  }
  final body = utf8.encode('android-ok');
  final scopeId = GatewayScopeId('android-check');
  final presetId = GatewayPresetId('ready');
  final route = GatewayRoute(
    id: GatewayRouteId('health'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/health',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('health-body'),
  );
  final compilation = const GatewayPlanCompiler().compile(
    scope: GatewayScope(
      id: scopeId,
      displayName: 'Android check',
      routeIds: <GatewayRouteId>[route.id],
    ),
    preset: GatewayPreset(
      id: presetId,
      scopeId: scopeId,
      description: 'Ready',
      routeIds: <GatewayRouteId>[route.id],
    ),
    routes: <GatewayRoute>[route],
    fixtures: <GatewayFixture>[
      GatewayFixture(
        id: GatewayFixtureId('health-body'),
        status: 200,
        headers: const <String, String>{'content-type': 'text/plain'},
        bodyDigest: Digest.bytes(body),
        bodySize: body.length,
        mediaType: 'text/plain',
      ),
    ],
  );
  final runtime = GatewayRuntime(
    gatewaySessionId: 'android-check',
    compilation: compilation,
    mockHandler: _HealthHandler(body),
    clock: SystemClock(),
    delay: const SystemDelay(),
  );
  final server = GatewayHttpServer(runtime: runtime, port: port);
  await server.start();
  stdout.writeln('DEVEX_GATEWAY_READY:${server.origin.port}');
  final done = Completer<void>();
  void stop(ProcessSignal signal) {
    if (!done.isCompleted) done.complete();
  }

  final interruptSubscription = ProcessSignal.sigint.watch().listen(stop);
  final terminateSubscription = ProcessSignal.sigterm.watch().listen(stop);
  await done.future;
  await server.close();
  await interruptSubscription.cancel();
  await terminateSubscription.cancel();
}

final class _HealthHandler implements MockHandlerPort {
  const _HealthHandler(this.body);

  final List<int> body;

  @override
  Future<GatewayMockResult> handle({
    required GatewayRoute route,
    required GatewayFixture fixture,
    required GatewayRequest request,
    required Map<String, String> pathParameters,
    required Map<String, Object?> runtimeState,
  }) async => GatewayMockResult(
    status: 200,
    headers: const <String, String>{'content-type': 'text/plain'},
    body: body,
  );
}
