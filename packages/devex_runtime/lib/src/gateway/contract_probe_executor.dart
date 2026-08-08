import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';

import '../storage/filesystem_workspace_store.dart';

final class ContractProbeTransportResponse {
  ContractProbeTransportResponse({
    required this.status,
    required Map<String, String> headers,
    required List<int> body,
  }) : headers = Map<String, String>.unmodifiable(headers),
       body = List<int>.unmodifiable(body) {
    if (status < 100 || status > 599) {
      throw ArgumentError.value(status, 'status');
    }
  }

  final int status;
  final Map<String, String> headers;
  final List<int> body;
}

abstract interface class ContractProbeTransport {
  Future<ContractProbeTransportResponse> send(GatewayRequest request);
}

final class GatewayRuntimeProbeTransport implements ContractProbeTransport {
  const GatewayRuntimeProbeTransport(this.runtime);

  final GatewayRuntime runtime;

  @override
  Future<ContractProbeTransportResponse> send(GatewayRequest request) async {
    final response = await runtime.handle(request);
    return ContractProbeTransportResponse(
      status: response.status,
      headers: response.headers,
      body: response.body,
    );
  }
}

final class HttpContractProbeTransport implements ContractProbeTransport {
  HttpContractProbeTransport({
    required Uri origin,
    this.maxResponseBytes = 4 * 1024 * 1024,
    HttpClient? client,
  }) : origin = _localOrigin(origin),
       _client = client ?? HttpClient() {
    if (maxResponseBytes < 1 || maxResponseBytes > 16 * 1024 * 1024) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
    _client
      ..connectionTimeout = const Duration(seconds: 10)
      ..autoUncompress = false
      ..findProxy = ((_) => 'DIRECT');
  }

  final Uri origin;
  final int maxResponseBytes;
  final HttpClient _client;

  @override
  Future<ContractProbeTransportResponse> send(GatewayRequest request) async {
    final uri = origin.replace(
      path: request.path,
      queryParameters: request.query.isEmpty ? null : request.query,
    );
    final clientRequest = await _client
        .openUrl(request.method, uri)
        .timeout(const Duration(seconds: 10));
    clientRequest
      ..followRedirects = false
      ..maxRedirects = 0;
    if (request.body.isNotEmpty) {
      clientRequest.headers.contentType = ContentType.json;
      clientRequest.contentLength = request.body.length;
      clientRequest.add(request.body);
    }
    final response = await clientRequest.close().timeout(
      const Duration(seconds: 30),
    );
    final body = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (body.length + chunk.length > maxResponseBytes) {
        throw StateError(
          'Contract probe response exceeds the configured limit',
        );
      }
      body.addAll(chunk);
    }
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      if (const <String>{
        'content-type',
        'etag',
        'last-modified',
      }.contains(name.toLowerCase())) {
        headers[name.toLowerCase()] = values.join(', ');
      }
    });
    return ContractProbeTransportResponse(
      status: response.statusCode,
      headers: headers,
      body: body,
    );
  }

  void close() => _client.close(force: true);
}

final class ContractProbeExecutor {
  ContractProbeExecutor({this.store, DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final FileSystemWorkspaceStore? store;
  final DateTime Function() _nowUtc;

  Future<ContractProbeReport> execute({
    required ContractProbePlan plan,
    required CompiledGatewayPlan gatewayPlan,
    required ContractProbeTransport transport,
    Map<String, String> manualParameters = const <String, String>{},
    Map<String, String> capturedParameters = const <String, String>{},
    Map<String, String> stableParameters = const <String, String>{},
  }) async {
    if (gatewayPlan.preset.id != plan.presetId) {
      throw StateError('Contract probe preset does not match the active plan');
    }
    if (gatewayPlan.backendMode == BackendMode.hybrid &&
        plan.artifactRetention == ProbeArtifactRetention.cas &&
        plan.artifactClassification != ArtifactClassification.sensitive) {
      throw StateError(
        'Hybrid probe responses stored in CAS must be sensitive',
      );
    }
    if (plan.artifactRetention == ProbeArtifactRetention.cas && store == null) {
      throw StateError('CAS probe retention requires a workspace store');
    }
    final routeById = <GatewayRouteId, GatewayRoute>{
      for (final route in gatewayPlan.routes) route.id: route,
    };
    for (final step in plan.steps) {
      final route = routeById[step.routeId];
      if (route == null || !route.appliesTo.contains(plan.presetId)) {
        throw StateError(
          'Contract probe route is outside the active preset: ${step.routeId}',
        );
      }
    }
    _validateParameters(manualParameters, 'manual');
    _validateParameters(capturedParameters, 'captured');
    _validateParameters(stableParameters, 'stable');

    final responseBodies = <GatewayRouteId, List<int>>{};
    final executions = <ContractProbeExecution>[];
    var success = true;
    for (final step in plan.orderedSteps) {
      final extracted = <String, String>{};
      for (final entry in step.extract.entries) {
        final source = responseBodies[entry.value.fromRouteId];
        if (source == null) {
          throw StateError('Contract probe extraction source is unavailable');
        }
        extracted[entry.key] = _extract(source, entry.value.paths);
      }
      final parameters = <String, String>{
        ...plan.parameterDefaults,
        ...stableParameters,
        ...capturedParameters,
        ...extracted,
        ...manualParameters,
      };
      final route = routeById[step.routeId]!;
      final request = GatewayRequest(
        method: route.method,
        path: _renderPath(route.pathTemplate, parameters),
        query: <String, List<String>>{
          for (final entry in route.requiredQuery.entries)
            entry.key: <String>[_renderString(entry.value, parameters)],
        },
        body: step.requestBodyTemplate == null
            ? const <int>[]
            : utf8.encode(
                const JcsCanonicalizer().canonicalize(
                  _renderJson(step.requestBodyTemplate, parameters),
                ),
              ),
      );
      final response = await transport.send(request);
      responseBodies[step.routeId] = response.body;
      final digest = Digest.bytes(response.body);
      Artifact? artifact;
      if (plan.artifactRetention == ProbeArtifactRetention.cas) {
        late final Digest stored;
        store!.withExclusiveLock(() {
          stored = store!.putBlob(response.body);
        });
        if (stored != digest) {
          throw StateError('Contract probe CAS digest mismatch');
        }
        artifact = Artifact(
          digest: stored,
          size: response.body.length,
          mediaType:
              response.headers['content-type'] ?? 'application/octet-stream',
          classification: plan.artifactClassification,
          role: 'contract-probe-response.${step.routeId.value}',
        );
      }
      executions.add(
        ContractProbeExecution(
          routeId: step.routeId,
          status: response.status,
          bodyDigest: digest,
          bodySize: response.body.length,
          extractedParameters: extracted.keys.toSet(),
          artifact: artifact,
        ),
      );
      if (response.status < 200 || response.status >= 400) {
        success = false;
        break;
      }
    }
    if (plan.artifactRetention == ProbeArtifactRetention.cas) {
      store!.withExclusiveLock(store!.rebuildCasIndex);
    }
    final report = ContractProbeReport(
      planDigest: plan.digest,
      gatewayPlanDigest: gatewayPlan.digest,
      presetId: plan.presetId,
      success: success && executions.length == plan.steps.length,
      executions: executions,
    );
    if (plan.artifactRetention == ProbeArtifactRetention.cas) {
      final observedAt = _nowUtc();
      store!.withExclusiveLock(() {
        store!.atomicWrite(
          'probe/temporary/${observedAt.microsecondsSinceEpoch}-${report.digest.value.substring(7)}.json',
          utf8.encode(
            '${const JcsCanonicalizer().canonicalize(<String, Object?>{'schemaVersion': 1, 'kind': 'TemporaryContractProbeReport', 'observedAt': observedAt.toUtc().toIso8601String(), 'expiresAt': observedAt.add(const Duration(days: 7)).toUtc().toIso8601String(), 'report': report.toJson()})}\n',
          ),
        );
      });
    }
    return report;
  }
}

Uri _localOrigin(Uri origin) {
  if (!origin.hasScheme ||
      !const <String>{'http', 'https'}.contains(origin.scheme) ||
      !const <String>{'127.0.0.1', '::1', 'localhost'}.contains(origin.host) ||
      origin.port == 0 ||
      origin.path.isNotEmpty && origin.path != '/' ||
      origin.hasQuery ||
      origin.hasFragment ||
      origin.userInfo.isNotEmpty) {
    throw FormatException(
      'Contract probe transport requires a loopback origin',
    );
  }
  return origin.replace(path: '', query: null, fragment: null);
}

void _validateParameters(Map<String, String> values, String source) {
  for (final entry in values.entries) {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(entry.key) ||
        entry.value.isEmpty ||
        entry.value.length > 4096) {
      throw FormatException('Invalid $source contract probe parameter');
    }
  }
}

String _renderPath(String template, Map<String, String> parameters) {
  final segments = template.split('/');
  final rendered = <String>[];
  for (final segment in segments.skip(1)) {
    final match = RegExp(r'^\{([a-z][a-z0-9_]*)\}$').firstMatch(segment);
    if (match == null) {
      rendered.add(segment);
      continue;
    }
    final value = parameters[match.group(1)!];
    if (value == null) {
      throw StateError(
        'Missing contract probe path parameter ${match.group(1)}',
      );
    }
    rendered.add(Uri.encodeComponent(value));
  }
  return '/${rendered.join('/')}';
}

String _renderString(String template, Map<String, String> parameters) {
  return template.replaceAllMapped(RegExp(r'\{\{([a-z][a-z0-9_]*)\}\}'), (
    match,
  ) {
    final value = parameters[match.group(1)!];
    if (value == null) {
      throw StateError('Missing contract probe template parameter');
    }
    return value;
  });
}

Object? _renderJson(Object? value, Map<String, String> parameters) =>
    switch (value) {
      String() => _renderString(value, parameters),
      List<Object?>() => <Object?>[
        for (final item in value) _renderJson(item, parameters),
      ],
      Map<String, Object?>() => <String, Object?>{
        for (final entry in value.entries)
          entry.key: _renderJson(entry.value, parameters),
      },
      _ => value,
    };

String _extract(List<int> body, List<String> candidates) {
  if (body.length > 4 * 1024 * 1024) {
    throw StateError('Contract probe extraction body exceeds 4 MiB');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(body));
  } on Object {
    throw const FormatException('Contract probe extraction requires JSON');
  }
  for (final pointer in candidates) {
    final value = _resolveJsonPointer(decoded, pointer);
    if (value is String && value.isNotEmpty) return value;
    if (value is num || value is bool) return '$value';
  }
  throw StateError(
    'No contract probe extraction candidate resolved to a scalar',
  );
}

Object? _resolveJsonPointer(Object? value, String pointer) {
  if (pointer.isEmpty) return value;
  var current = value;
  for (final raw in pointer.substring(1).split('/')) {
    final token = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    if (current is Map<String, Object?>) {
      if (!current.containsKey(token)) return null;
      current = current[token];
    } else if (current is List<Object?>) {
      final index = int.tryParse(token);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}
