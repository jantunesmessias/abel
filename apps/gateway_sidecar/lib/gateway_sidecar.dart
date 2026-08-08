import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

final class BackendGatewayBuildInfo {
  const BackendGatewayBuildInfo();

  static const String version = '0.1.0-dev';

  Map<String, Object?> toJson() => const <String, Object?>{
    'name': 'gateway_sidecar',
    'version': version,
    'implementedCapabilities': <String>[
      'gateway.isolated',
      'gateway.mock',
      'gateway.hybrid',
      'gateway.upstream.allowlist',
      'gateway.upstream.dnsPinned',
      'gateway.verify',
      'gateway.traffic',
      'gateway.reset',
    ],
  };
}

final class BackendGatewayApplication {
  BackendGatewayApplication({
    required this.gatewaySessionId,
    required this.workspaceRoot,
    required CompiledGatewayPlan plan,
    this.allowedOrigins = const <Uri>{},
  }) : _runtime = GatewayRuntime(
         gatewaySessionId: gatewaySessionId,
         compilation: _compilation(plan),
         mockHandler: CasGatewayMockHandler(
           FileSystemWorkspaceStore(workspaceRoot: workspaceRoot),
         ),
         clock: SystemClock(),
         delay: const SystemDelay(),
         upstreamHandler: _upstreamHandler(plan, workspaceRoot),
       ) {
    if (gatewaySessionId.isEmpty) {
      throw ArgumentError.value(gatewaySessionId, 'gatewaySessionId');
    }
  }

  final String gatewaySessionId;
  final String workspaceRoot;
  final Set<Uri> allowedOrigins;
  final GatewayRuntime _runtime;
  late final GatewayHttpServer _server = GatewayHttpServer(
    runtime: _runtime,
    allowedOrigins: allowedOrigins,
  );
  var _started = false;

  GatewayRuntime get runtime => _runtime;
  Uri get dataOrigin => _server.origin;

  Future<void> start() async {
    if (_started) throw StateError('Gateway application already started');
    await _server.start();
    _started = true;
  }

  Future<void> close() async {
    if (!_started) return;
    _started = false;
    await _server.close();
  }

  Map<String, Object?> status() => <String, Object?>{
    'gatewaySessionId': gatewaySessionId,
    'state': _started ? 'running' : 'stopped',
    if (_started) 'dataOrigin': dataOrigin.toString(),
    'backendMode': _runtime.plan.backendMode.name,
    'networkContainment': _runtime.plan.networkContainment.name,
    'planDigest': _runtime.plan.digest.value,
    'routingTableDigest': _runtime.routingTable.digest.value,
    'runtimeStateDigest': _runtime.runtimeStateDigest.value,
    'trafficEvents': _runtime.traffic(limit: 10000).length,
    'evictedTrafficEvents': _runtime.evictedEvents,
    'trafficBytes': _runtime.trafficBytes,
  };

  Map<String, Object?> applyPlan(CompiledGatewayPlan plan) {
    _runtime.apply(_compilation(plan));
    return status();
  }

  void reset() => _runtime.reset();

  Future<Map<String, Object?>> verify(Map<String, Object?> params) async {
    final request = _request(params);
    final report = await _runtime.verify(request);
    return <String, Object?>{
      ...report.toJson(),
      'responseBodyBase64': base64Encode(report.response.body),
    };
  }

  List<Object?> traffic(Map<String, Object?> params) => <Object?>[
    for (final event in _runtime.traffic(
      afterSequence: _optionalInt(params, 'afterSequence') ?? 0,
      limit: _optionalInt(params, 'limit') ?? 1000,
    ))
      event.toJson(),
  ];

  GatewayRequest _request(Map<String, Object?> params) {
    final method = _requiredString(params, 'method');
    final path = _requiredString(params, 'path');
    final queryValue = params['query'] ?? const <String, Object?>{};
    if (queryValue is! Map<String, Object?>) {
      throw const FormatException('query must be an object');
    }
    final query = <String, List<String>>{};
    for (final entry in queryValue.entries) {
      final value = entry.value;
      if (value is String) {
        query[entry.key] = <String>[value];
      } else if (value is List<Object?> &&
          value.every((item) => item is String)) {
        query[entry.key] = value.cast<String>();
      } else {
        throw FormatException(
          'query.${entry.key} must be string or string array',
        );
      }
    }
    final encodedBody = params['bodyBase64'];
    final List<int> body;
    if (encodedBody == null) {
      body = const <int>[];
    } else if (encodedBody is String) {
      try {
        body = base64Decode(encodedBody);
      } on FormatException {
        throw const FormatException('bodyBase64 is invalid');
      }
    } else {
      throw const FormatException('bodyBase64 must be a string');
    }
    return GatewayRequest(method: method, path: path, query: query, body: body);
  }

  static GatewayCompilation _compilation(CompiledGatewayPlan plan) =>
      GatewayCompilation(
        plan: plan,
        routingTable: RoutingTable(
          scopeId: plan.scope.id,
          presetId: plan.preset.id,
          entries: <GatewayRouteId, GatewayRoutingDecision>{
            for (final route in plan.routes)
              route.id:
                  plan.backendMode == BackendMode.hybrid &&
                      route.policy == GatewayRoutePolicy.upstreamOnly
                  ? GatewayRoutingDecision.passthrough
                  : GatewayRoutingDecision.mock,
          },
        ),
      );

  static UpstreamHandlerPort? _upstreamHandler(
    CompiledGatewayPlan plan,
    String workspaceRoot,
  ) {
    if (plan.backendMode != BackendMode.hybrid) return null;
    final localConfiguration = const WorkspaceConfigurationLoader()
        .loadLocalConfiguration(workspaceRoot: workspaceRoot);
    final endpoints = const LocalGatewayConfigurationLoader().parseDocument(
      localConfiguration,
    );
    final requiredProfiles = plan.routes
        .map((route) => route.upstreamProfileId)
        .whereType<UpstreamProfileId>()
        .toSet();
    if (!endpoints.keys.toSet().containsAll(requiredProfiles)) {
      throw StateError('Hybrid plan has an unconfigured UpstreamProfile');
    }
    return SafeHttpGatewayUpstreamHandler(
      endpoints: endpoints,
      credentials: EnvironmentCredentialResolver(),
    );
  }

  String _requiredString(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  int? _optionalInt(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value == null) return null;
    if (value is! int) throw FormatException('$key must be an integer');
    return value;
  }
}

final class GatewayStdioControlPlane {
  const GatewayStdioControlPlane({this.maxMessageBytes = 1024 * 1024});

  static const int protocolVersion = 1;

  final int maxMessageBytes;

  Future<void> run(Stream<List<int>> input, IOSink output) async {
    BackendGatewayApplication? application;
    var stop = false;
    final lines = input.transform(
      BoundedUtf8LineDecoder(maxLineBytes: maxMessageBytes),
    );
    await for (final line in lines) {
      if (utf8.encode(line).length > maxMessageBytes) {
        output.writeln(
          JsonRpcResponse.error(
            id: null,
            error: const JsonRpcError(
              code: JsonRpcError.invalidRequest,
              message: 'Control message too large',
            ),
          ).encode(),
        );
        await output.flush();
        continue;
      }
      final JsonRpcRequest request;
      try {
        final decoded = const JsonRpcCodec().decode(line);
        if (decoded is! JsonRpcRequest) continue;
        request = decoded;
      } on JsonRpcFormatException catch (error) {
        output.writeln(
          JsonRpcResponse.error(
            id: null,
            error: JsonRpcError(
              code: JsonRpcError.parseError,
              message: error.message,
            ),
          ).encode(),
        );
        await output.flush();
        continue;
      }
      JsonRpcResponse response;
      try {
        final params = request.params;
        if (params != null && params is! Map<String, Object?>) {
          throw const FormatException('params must be an object');
        }
        final objectParams =
            params as Map<String, Object?>? ?? const <String, Object?>{};
        if (request.method == 'gateway.initialize') {
          if (application != null) {
            throw StateError('Gateway is already initialized');
          }
          if (objectParams['protocolVersion'] != protocolVersion) {
            throw const FormatException('Unsupported protocolVersion');
          }
          final workspaceRoot = _requiredString(objectParams, 'workspaceRoot');
          final gatewaySessionId = _requiredString(
            objectParams,
            'gatewaySessionId',
          );
          final plan = CompiledGatewayPlan.fromJson(objectParams['plan']);
          application = BackendGatewayApplication(
            gatewaySessionId: gatewaySessionId,
            workspaceRoot: workspaceRoot,
            plan: plan,
            allowedOrigins: _allowedOrigins(objectParams),
          );
          await application.start();
          response = JsonRpcResponse.success(
            id: request.id,
            result: <String, Object?>{
              'protocolVersion': protocolVersion,
              'maxMessageBytes': maxMessageBytes,
              'capabilities': const BackendGatewayBuildInfo()
                  .toJson()['implementedCapabilities'],
              ...application.status(),
            },
          );
        } else {
          final current = application;
          if (current == null) {
            throw StateError('gateway.initialize is required first');
          }
          final result = switch (request.method) {
            'gateway.status' => current.status(),
            'gateway.apply' => current.applyPlan(
              CompiledGatewayPlan.fromJson(objectParams['plan']),
            ),
            'gateway.verify' => await current.verify(objectParams),
            'gateway.traffic' => current.traffic(objectParams),
            'gateway.reset' => _reset(current),
            'gateway.stop' => await _stop(current),
            _ => throw const _MethodNotFound(),
          };
          stop = request.method == 'gateway.stop';
          response = JsonRpcResponse.success(id: request.id, result: result);
        }
      } on _MethodNotFound {
        response = JsonRpcResponse.error(
          id: request.id,
          error: const JsonRpcError(
            code: JsonRpcError.methodNotFound,
            message: 'Method not found',
          ),
        );
      } on FormatException catch (error) {
        response = JsonRpcResponse.error(
          id: request.id,
          error: JsonRpcError(
            code: JsonRpcError.invalidParams,
            message: error.message,
          ),
        );
      } on StateError catch (error) {
        response = JsonRpcResponse.error(
          id: request.id,
          error: JsonRpcError(code: -32003, message: error.message),
        );
      } on Object {
        response = JsonRpcResponse.error(
          id: request.id,
          error: const JsonRpcError(
            code: JsonRpcError.internalError,
            message: 'Gateway operation failed',
          ),
        );
      }
      output.writeln(response.encode());
      await output.flush();
      if (stop) break;
    }
    await application?.close();
  }

  static Map<String, Object?> _reset(BackendGatewayApplication application) {
    application.reset();
    return application.status();
  }

  static Future<Map<String, Object?>> _stop(
    BackendGatewayApplication application,
  ) async {
    await application.close();
    return application.status();
  }

  static Set<Uri> _allowedOrigins(Map<String, Object?> params) {
    final value = params['allowedOrigins'];
    if (value == null) return const <Uri>{};
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      throw const FormatException('allowedOrigins must be a string array');
    }
    if (value.length > 16) {
      throw const FormatException('allowedOrigins exceeds 16 origins');
    }
    return <Uri>{for (final item in value.cast<String>()) Uri.parse(item)};
  }

  static String _requiredString(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }
}

final class _MethodNotFound implements Exception {
  const _MethodNotFound();
}
