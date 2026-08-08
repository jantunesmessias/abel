import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';

const _presetIds = <String>[
  'showcase-hybrid',
  'showcase-offline',
  'showcase-unavailable',
  'showcase-failure',
];

Future<void> main(List<String> arguments) async {
  final options = _SmokeOptions.parse(arguments);
  final root = _repositoryRoot();
  final sampleRoot = '${root.path}/examples/sample_flutter';
  final loaded = const WorkspaceCatalogLoader().load(startPath: sampleRoot);
  final compiledPresets = <String, WorkspaceGatewayPlanResult>{
    for (final presetId in _presetIds)
      presetId: const WorkspaceGatewayPlanCompiler().compilePreset(
        loaded,
        presetId: presetId,
        persist: true,
      ),
  };

  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  WebSocket? socket;
  StreamIterator<Object?>? messages;
  String? sessionId;
  String? gatewaySessionId;
  late Future<Object?> Function(String, Map<String, Object?>) call;
  try {
    final apiMatrix = await _verifyApiMatrix(client, options.apiOrigin);
    final bootstrap = await _jsonRequest(
      client,
      options.studioOrigin.resolve('/studio/bootstrap.json'),
      expectedStatus: 200,
      headers: const <String, String>{'sec-fetch-site': 'same-origin'},
    );
    final hostOrigin = _loopbackOrigin(
      bootstrap.body['hostOrigin'],
      'bootstrap.hostOrigin',
    );
    final token = _requiredString(
      bootstrap.body,
      'sessionToken',
      'Studio bootstrap',
    );
    socket = await WebSocket.connect(
      hostOrigin.replace(scheme: 'ws', path: '/rpc').toString(),
      headers: <String, String>{'Origin': options.studioOrigin.origin},
    );
    final connectedSocket = socket;
    final connectedMessages = StreamIterator<Object?>(connectedSocket);
    messages = connectedMessages;
    var requestSequence = 0;
    call = (method, params) async {
      final requestId = 'reference-consumer-${requestSequence++}';
      connectedSocket.add(
        JsonRpcRequest(method: method, id: requestId, params: params).encode(),
      );
      while (await connectedMessages.moveNext()) {
        final raw = connectedMessages.current;
        if (raw is! String) continue;
        final decoded = const JsonRpcCodec().decode(raw);
        if (decoded is! JsonRpcResponse || decoded.id != requestId) continue;
        if (!decoded.isSuccess) {
          throw StateError(
            '$method failed (${decoded.error!.code}): '
            '${decoded.error!.message}',
          );
        }
        return decoded.result;
      }
      throw StateError('Host closed the RPC connection during $method');
    };

    final initialized = _object(
      await call('workspace.initialize', <String, Object?>{
        'protocolVersion': 1,
        'sessionToken': token,
      }),
      'InitializeResult',
    );
    final capabilities = _stringList(
      initialized['capabilities'],
      'InitializeResult.capabilities',
    ).toSet();
    for (final required in const <String>{
      'session.start',
      'session.stop',
      'gateway.start',
      'gateway.status',
      'gateway.traffic',
      'gateway.stop',
      'preview.collect',
      'preview.status',
      'workspace.describe',
      'workspace.open',
      'experience.describe',
      'experience.open',
    }) {
      if (!capabilities.contains(required)) {
        throw StateError('Missing Host capability $required');
      }
    }

    final evidence = await _collectAndVerifyEvidence(
      call: call,
      client: client,
      hostOrigin: hostOrigin,
      studioOrigin: options.studioOrigin,
    );

    final session = _object(
      await call('session.start', <String, Object?>{
        'launchProfileId': 'sample-web',
        'targetOrigin': options.targetOrigin.origin,
      }),
      'Session',
    );
    sessionId = _requiredString(session, 'id', 'Session');
    await _waitForHttp(
      client,
      options.targetOrigin.resolve('/health'),
      expectedStatus: 200,
    );
    final targetDocument = await _textRequest(
      client,
      options.targetOrigin,
      expectedStatus: 200,
    );
    if (!targetDocument.contains('flutter_bootstrap.js')) {
      throw StateError('Managed Target did not serve the Flutter entrypoint');
    }

    Future<Map<String, Object?>> runPreset(
      String presetId,
      Future<Map<String, Object?>> Function(Uri gatewayOrigin) verify,
    ) async {
      final artifactDigest = compiledPresets[presetId]!.planArtifactDigest!;
      final gateway = _object(
        await call('gateway.start', <String, Object?>{
          'ownerSessionId': sessionId,
          'planArtifactDigest': artifactDigest.value,
        }),
        'GatewaySession',
      );
      gatewaySessionId = _requiredString(gateway, 'id', 'GatewaySession');
      final gatewayOrigin = _loopbackOrigin(
        gateway['dataOrigin'],
        'GatewaySession.dataOrigin',
      );
      try {
        final result = await verify(gatewayOrigin);
        final status = _object(
          await call('gateway.status', <String, Object?>{
            'gatewaySessionId': gatewaySessionId,
          }),
          'GatewayStatus',
        );
        if (status['state'] != 'running') {
          throw StateError('$presetId Gateway was not running: $status');
        }
        final traffic = _list(
          await call('gateway.traffic', <String, Object?>{
            'gatewaySessionId': gatewaySessionId,
            'afterSequence': 0,
            'limit': 100,
          }),
          'GatewayTraffic',
        );
        if (traffic.isEmpty) {
          throw StateError('$presetId did not record Gateway traffic');
        }
        return <String, Object?>{
          'presetId': presetId,
          'planDigest':
              compiledPresets[presetId]!.compilation.plan.digest.value,
          'artifactDigest': artifactDigest.value,
          'trafficEvents': traffic.length,
          ...result,
        };
      } finally {
        final activeGateway = gatewaySessionId;
        gatewaySessionId = null;
        if (activeGateway != null) {
          await call('gateway.stop', <String, Object?>{
            'gatewaySessionId': activeGateway,
          });
        }
      }
    }

    final hybrid = await runPreset('showcase-hybrid', (gatewayOrigin) async {
      await _jsonRequest(
        client,
        options.apiOrigin.resolve('/v1/reset'),
        method: 'POST',
        expectedStatus: 200,
      );
      final dashboard = await _jsonRequest(
        client,
        gatewayOrigin.resolve('/v1/dashboard'),
        expectedStatus: 200,
      );
      _expectState(dashboard, 'ready');
      final dashboardData = _object(
        dashboard.body['dashboard'],
        'Hybrid dashboard',
      );
      final fixture = await _jsonRequest(
        client,
        gatewayOrigin.resolve('/v1/runtime/configuration?view=tooling'),
        expectedStatus: 200,
      );
      if (fixture.body['mode'] != 'fixture' ||
          fixture.body['synthetic'] != true) {
        throw StateError(
          'Hybrid fixture route was not isolated: ${fixture.body}',
        );
      }
      final mutation = await _jsonRequest(
        client,
        gatewayOrigin.resolve(
          '/v1/projects/mobile-foundation/tasks/offline-state/toggle',
        ),
        method: 'POST',
        expectedStatus: 200,
      );
      final changedProject = _object(
        mutation.body['project'],
        'Hybrid mutation project',
      );
      if (!_taskCompleted(changedProject, 'offline-state')) {
        throw StateError('Hybrid mutation did not reach the real sample API');
      }
      final observed = await _jsonRequest(
        client,
        options.apiOrigin.resolve('/v1/dashboard'),
        expectedStatus: 200,
      );
      final observedDashboard = _object(
        observed.body['dashboard'],
        'Observed dashboard',
      );
      if (!_dashboardTaskCompleted(
        observedDashboard,
        'mobile-foundation',
        'offline-state',
      )) {
        throw StateError('Upstream mutation was not observable after Gateway');
      }
      await _jsonRequest(
        client,
        options.apiOrigin.resolve('/v1/reset'),
        method: 'POST',
        expectedStatus: 200,
      );
      return <String, Object?>{
        'state': dashboard.body['state'],
        'projects': _list(
          dashboardData['projects'],
          'Hybrid dashboard.projects',
        ).length,
        'fixtureMode': fixture.body['mode'],
        'mutationObserved': true,
      };
    });

    final offline = await runPreset('showcase-offline', (gatewayOrigin) async {
      final dashboard = await _jsonRequest(
        client,
        gatewayOrigin.resolve('/v1/dashboard'),
        expectedStatus: 200,
      );
      _expectState(dashboard, 'ready');
      final mutation = await _jsonRequest(
        client,
        gatewayOrigin.resolve(
          '/v1/projects/mobile-foundation/tasks/offline-state/toggle',
        ),
        method: 'POST',
        expectedStatus: 200,
      );
      final changedProject = _object(
        mutation.body['project'],
        'Offline mutation project',
      );
      if (!_taskCompleted(changedProject, 'offline-state')) {
        throw StateError('Offline mutation fixture is incoherent');
      }
      final upstream = await _jsonRequest(
        client,
        options.apiOrigin.resolve('/v1/dashboard'),
        expectedStatus: 200,
      );
      final upstreamDashboard = _object(
        upstream.body['dashboard'],
        'Upstream dashboard',
      );
      if (_dashboardTaskCompleted(
        upstreamDashboard,
        'mobile-foundation',
        'offline-state',
      )) {
        throw StateError(
          'Offline fixture unexpectedly mutated the upstream API',
        );
      }
      return <String, Object?>{
        'state': dashboard.body['state'],
        'isolatedMutation': true,
      };
    });

    final unavailable = await runPreset('showcase-unavailable', (
      gatewayOrigin,
    ) async {
      final response = await _jsonRequest(
        client,
        gatewayOrigin.resolve('/v1/dashboard'),
        expectedStatus: 503,
      );
      _expectState(response, 'unavailable');
      if (response.body['recoverable'] != true ||
          response.body['error'] != 'SAMPLE_DEPENDENCY_UNAVAILABLE') {
        throw StateError('Unavailable preset lost recoverability semantics');
      }
      return <String, Object?>{
        'state': response.body['state'],
        'recoverable': response.body['recoverable'],
      };
    });

    final failure = await runPreset('showcase-failure', (gatewayOrigin) async {
      final response = await _jsonRequest(
        client,
        gatewayOrigin.resolve('/v1/dashboard'),
        expectedStatus: 500,
      );
      _expectState(response, 'failure');
      if (response.body['recoverable'] != false ||
          response.body['error'] != 'SAMPLE_API_FAILURE') {
        throw StateError('Failure preset lost non-recoverable semantics');
      }
      return <String, Object?>{
        'state': response.body['state'],
        'recoverable': response.body['recoverable'],
      };
    });

    stdout.writeln(
      jsonEncode(<String, Object?>{
        'status': 'passed',
        'consumer': 'delivery-lab',
        'profile': 'full-local',
        'launchProfile': 'sample-web',
        'apiMatrix': apiMatrix,
        'evidence': evidence,
        'target': <String, Object?>{
          'origin': options.targetOrigin.origin,
          'flutterEntrypoint': true,
        },
        'gatewayPresets': <Object?>[hybrid, offline, unavailable, failure],
      }),
    );
  } finally {
    if (gatewaySessionId != null) {
      try {
        await call('gateway.stop', <String, Object?>{
          'gatewaySessionId': gatewaySessionId,
        });
      } on Object {
        // Session shutdown below remains the owning cleanup boundary.
      }
    }
    if (sessionId != null) {
      try {
        await call('session.stop', <String, Object?>{'sessionId': sessionId});
      } on Object {
        // Host shutdown owns any remaining managed process.
      }
    }
    await messages?.cancel();
    await socket?.close();
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _verifyApiMatrix(
  HttpClient client,
  Uri apiOrigin,
) async {
  const expected = <String, int>{
    'ready': 200,
    'loading': 202,
    'empty': 200,
    'stale': 200,
    'unavailable': 503,
    'failure': 500,
  };
  final states = <Object?>[];
  for (final entry in expected.entries) {
    final response = await _jsonRequest(
      client,
      apiOrigin.resolve('/v1/dashboard?state=${entry.key}'),
      expectedStatus: entry.value,
    );
    _expectState(response, entry.key);
    final hasData = response.body['dashboard'] is Map<String, Object?>;
    if (hasData != const <String>{'ready', 'stale'}.contains(entry.key)) {
      throw StateError('${entry.key} has an invalid dashboard payload shape');
    }
    if (entry.key == 'stale' &&
        response.body['staleSince'] != '2026-08-13T12:00:00.000Z') {
      throw StateError('Stale state lost its deterministic timestamp');
    }
    states.add(<String, Object?>{
      'state': entry.key,
      'status': response.status,
      'hasData': hasData,
      if (response.body['recoverable'] case final bool recoverable)
        'recoverable': recoverable,
    });
  }
  final invalid = await _jsonRequest(
    client,
    apiOrigin.resolve('/v1/dashboard?state=unknown'),
    expectedStatus: 400,
  );
  if (invalid.body['error'] != 'DASHBOARD_STATE_INVALID') {
    throw StateError('Sample API did not fail closed for an unknown state');
  }
  return <String, Object?>{'states': states, 'unknownStateRejected': true};
}

Future<Map<String, Object?>> _collectAndVerifyEvidence({
  required Future<Object?> Function(String, Map<String, Object?>) call,
  required HttpClient client,
  required Uri hostOrigin,
  required Uri studioOrigin,
}) async {
  var collection = _object(
    await call('preview.collect', const <String, Object?>{
      'applicationId': 'sample',
      'syntheticDataConfirmed': true,
    }),
    'PreviewCollection',
  );
  const terminal = <String>{'cancelled', 'completed', 'failed', 'timedOut'};
  for (var poll = 0; !terminal.contains(collection['state']); poll += 1) {
    if (poll >= 2400) {
      throw TimeoutException(
        'AutoPreview collection did not finish',
        const Duration(minutes: 10),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    collection = _object(
      await call('preview.status', <String, Object?>{
        'operationId': collection['operationId'],
      }),
      'PreviewCollection',
    );
  }
  if (collection['state'] != 'completed') {
    throw StateError('AutoPreview collection failed: $collection');
  }

  final description = _object(
    await call('workspace.describe', const <String, Object?>{}),
    'WorkspaceDescription',
  );
  final opened = _object(
    await call('workspace.open', <String, Object?>{
      'expectedRevision': description['revision'],
    }),
    'WorkspaceOpen',
  );
  final handle = ResourceHandle.fromJson(opened['resource']);
  final bytes = await _readResource(
    client: client,
    handle: handle,
    hostOrigin: hostOrigin,
    studioOrigin: studioOrigin,
    expectedMediaType: 'application/json',
    expectedPurpose: 'workspace-snapshot',
  );
  final snapshot = WorkspaceSnapshot.fromJson(jsonDecode(utf8.decode(bytes)));
  final currentProjections = snapshot.visualProjections
      .where((projection) => projection.status != VisualEvidenceStatus.unbound)
      .toList(growable: false);
  final historicalUnbound = snapshot.visualProjections
      .where((projection) => projection.status == VisualEvidenceStatus.unbound)
      .toList(growable: false);
  if (snapshot.catalog.applications.length != 1 ||
      snapshot.catalog.scenarios.length != 8 ||
      snapshot.variantManifest.variants.length != 3 ||
      currentProjections.length != 10) {
    throw StateError(
      'Reference snapshot cardinalities changed: '
      '${snapshot.catalog.applications.length} application(s), '
      '${snapshot.catalog.scenarios.length} scenario(s), '
      '${snapshot.variantManifest.variants.length} variant(s), '
      '${currentProjections.length} current projection(s), '
      '${historicalUnbound.length} historical unbound projection(s)',
    );
  }
  const requiredScenarios = <String>{
    'dashboard-loading',
    'dashboard-ready',
    'dashboard-empty',
    'dashboard-stale',
    'dashboard-unavailable',
    'dashboard-failed',
    'toggle-delivery-task',
    'inspect-gateway-traffic',
  };
  final projectedScenarios = currentProjections
      .map((projection) => projection.scenarioId?.value)
      .whereType<String>()
      .toSet();
  if (!projectedScenarios.containsAll(requiredScenarios)) {
    throw StateError(
      'AutoPreview coverage is incomplete: '
      '${requiredScenarios.difference(projectedScenarios)}',
    );
  }
  var pngs = 0;
  for (final projection in currentProjections) {
    if (projection.providerId.value != 'evidence.auto-preview' ||
        projection.status != VisualEvidenceStatus.collected ||
        projection.freshness != EvidenceFreshness.fresh ||
        projection.fidelity != RuntimeFidelity.structural ||
        projection.capturePolicyId != 'static-v1' ||
        projection.executionFingerprintDigest == null ||
        projection.captureKey == null ||
        projection.artifactDigest == null ||
        projection.artifactHandle == null) {
      throw StateError(
        'Invalid AutoPreview projection: ${projection.toJson()}',
      );
    }
    final artifact = await _readResource(
      client: client,
      handle: projection.artifactHandle!,
      hostOrigin: hostOrigin,
      studioOrigin: studioOrigin,
      expectedMediaType: 'image/png',
      expectedPurpose: 'visual-artifact',
    );
    if (artifact.length < 8 ||
        artifact[0] != 0x89 ||
        artifact[1] != 0x50 ||
        artifact[2] != 0x4e ||
        artifact[3] != 0x47) {
      throw StateError('AutoPreview artifact is not a PNG');
    }
    pngs += 1;
  }
  return <String, Object?>{
    'operationId': collection['operationId'],
    'state': collection['state'],
    'snapshotDigest': snapshot.digest.value,
    'scenarios': snapshot.catalog.scenarios.length,
    'variants': snapshot.variantManifest.variants.length,
    'captures': currentProjections.length,
    'historicalUnboundEvidence': historicalUnbound.length,
    'validatedPngs': pngs,
    'fidelity': 'structural',
    'freshness': 'fresh',
    'requiredStates': const <String>[
      'ready',
      'loading',
      'empty',
      'stale',
      'unavailable',
      'failure',
    ],
  };
}

Future<List<int>> _readResource({
  required HttpClient client,
  required ResourceHandle handle,
  required Uri hostOrigin,
  required Uri studioOrigin,
  required String expectedMediaType,
  required String expectedPurpose,
}) async {
  if (handle.uri.origin != hostOrigin.origin ||
      handle.mediaType != expectedMediaType ||
      handle.purpose != expectedPurpose ||
      handle.isExpiredAt(DateTime.now().toUtc())) {
    throw StateError('Invalid resource handle: ${handle.toJson()}');
  }
  final request = await client.getUrl(handle.uri);
  request.headers.set('Origin', studioOrigin.origin);
  final response = await request.close();
  final bytes = await response.fold<List<int>>(<int>[], (output, chunk) {
    if (output.length + chunk.length > 64 * 1024 * 1024) {
      throw const FormatException('Resource exceeds 64 MiB');
    }
    return output..addAll(chunk);
  });
  if (response.statusCode != 200 ||
      response.headers.contentType?.mimeType != expectedMediaType ||
      bytes.length != handle.size ||
      Digest.bytes(bytes) != handle.digest) {
    throw StateError('Resource response does not match its handle');
  }
  return bytes;
}

void _expectState(_JsonResponse response, String expected) {
  if (response.body['state'] != expected) {
    throw StateError(
      'Expected state $expected from ${response.uri}, got ${response.body}',
    );
  }
}

bool _dashboardTaskCompleted(
  Map<String, Object?> dashboard,
  String projectId,
  String taskId,
) {
  for (final project in _objectList(
    dashboard['projects'],
    'Dashboard.projects',
  )) {
    if (project['id'] == projectId) return _taskCompleted(project, taskId);
  }
  throw StateError('Dashboard omitted project $projectId');
}

bool _taskCompleted(Map<String, Object?> project, String taskId) {
  for (final task in _objectList(project['tasks'], 'Project.tasks')) {
    if (task['id'] == taskId) return task['completed'] == true;
  }
  throw StateError('Project omitted task $taskId');
}

Future<void> _waitForHttp(
  HttpClient client,
  Uri uri, {
  required int expectedStatus,
}) async {
  for (var attempt = 0; attempt < 240; attempt += 1) {
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode == expectedStatus) return;
    } on SocketException {
      // Managed Target is still starting.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('HTTP endpoint did not become ready at $uri');
}

Future<_JsonResponse> _jsonRequest(
  HttpClient client,
  Uri uri, {
  String method = 'GET',
  required int expectedStatus,
  Map<String, String> headers = const <String, String>{},
}) async {
  final request = switch (method) {
    'GET' => await client.getUrl(uri),
    'POST' => await client.postUrl(uri),
    _ => throw ArgumentError.value(method, 'method'),
  };
  headers.forEach(request.headers.set);
  final response = await request.close();
  final bytes = await response.fold<List<int>>(<int>[], (output, chunk) {
    if (output.length + chunk.length > 1024 * 1024) {
      throw const FormatException('JSON response exceeds 1 MiB');
    }
    return output..addAll(chunk);
  });
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw FormatException('Invalid JSON from $uri: ${error.message}');
  }
  if (response.statusCode != expectedStatus ||
      decoded is! Map<String, Object?>) {
    throw StateError(
      'Unexpected response ${response.statusCode} from $uri: $decoded',
    );
  }
  return _JsonResponse(uri: uri, status: response.statusCode, body: decoded);
}

Future<String> _textRequest(
  HttpClient client,
  Uri uri, {
  required int expectedStatus,
}) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  final bytes = await response.fold<List<int>>(<int>[], (output, chunk) {
    if (output.length + chunk.length > 2 * 1024 * 1024) {
      throw const FormatException('Text response exceeds 2 MiB');
    }
    return output..addAll(chunk);
  });
  if (response.statusCode != expectedStatus) {
    throw StateError('Unexpected response ${response.statusCode} from $uri');
  }
  return utf8.decode(bytes);
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _list(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path must be a list');
  return value;
}

List<Map<String, Object?>> _objectList(Object? value, String path) => _list(
  value,
  path,
).map((item) => _object(item, '$path[]')).toList(growable: false);

List<String> _stringList(Object? value, String path) => _list(value, path)
    .map((item) {
      if (item is! String) throw FormatException('$path[] must be a string');
      return item;
    })
    .toList(growable: false);

String _requiredString(Map<String, Object?> value, String field, String path) {
  final result = value[field];
  if (result is! String || result.isEmpty) {
    throw FormatException('$path.$field must be a non-empty string');
  }
  return result;
}

Uri _loopbackOrigin(Object? value, String path) {
  if (value is! String) throw FormatException('$path must be a string');
  return _validateLoopbackOrigin(Uri.parse(value), path);
}

Uri _validateLoopbackOrigin(Uri uri, String path) {
  final address = InternetAddress.tryParse(uri.host);
  if (uri.scheme != 'http' ||
      uri.userInfo.isNotEmpty ||
      (uri.host != 'localhost' && address?.isLoopback != true) ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.hasPort) {
    throw FormatException('$path must be a loopback HTTP origin with a port');
  }
  return Uri.parse(uri.origin);
}

Directory _repositoryRoot() {
  var current = File.fromUri(Platform.script).parent;
  while (current.parent.path != current.path) {
    final pubspec = File('${current.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('Abel repository root not found');
}

final class _JsonResponse {
  const _JsonResponse({
    required this.uri,
    required this.status,
    required this.body,
  });

  final Uri uri;
  final int status;
  final Map<String, Object?> body;
}

final class _SmokeOptions {
  const _SmokeOptions({
    required this.studioOrigin,
    required this.apiOrigin,
    required this.targetOrigin,
  });

  final Uri studioOrigin;
  final Uri apiOrigin;
  final Uri targetOrigin;

  factory _SmokeOptions.parse(List<String> arguments) {
    var studioOrigin = Uri.parse('http://127.0.0.1:7368');
    var apiOrigin = Uri.parse('http://127.0.0.1:8181');
    var targetOrigin = Uri.parse('http://127.0.0.1:8080');
    for (final argument in arguments) {
      if (argument.startsWith('--studio-origin=')) {
        studioOrigin = Uri.parse(argument.substring('--studio-origin='.length));
      } else if (argument.startsWith('--api-origin=')) {
        apiOrigin = Uri.parse(argument.substring('--api-origin='.length));
      } else if (argument.startsWith('--target-origin=')) {
        targetOrigin = Uri.parse(argument.substring('--target-origin='.length));
      } else {
        throw FormatException('Unknown showcase_smoke option $argument');
      }
    }
    return _SmokeOptions(
      studioOrigin: _validateLoopbackOrigin(studioOrigin, '--studio-origin'),
      apiOrigin: _validateLoopbackOrigin(apiOrigin, '--api-origin'),
      targetOrigin: _validateLoopbackOrigin(targetOrigin, '--target-origin'),
    );
  }
}
