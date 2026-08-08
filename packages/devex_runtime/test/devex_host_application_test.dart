import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/png_fixture.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  late Directory temporary;
  late StaticWebOriginServer studioOrigin;
  late StaticWebOriginServer targetOrigin;
  late DevExHostApplication application;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('devex-host-app-');
    final studioRoot = Directory(p.join(temporary.path, 'studio'))
      ..createSync();
    final targetRoot = Directory(p.join(temporary.path, 'target'))
      ..createSync();
    File(
      p.join(studioRoot.path, 'index.html'),
    ).writeAsStringSync('<p>studio</p>');
    File(
      p.join(targetRoot.path, 'index.html'),
    ).writeAsStringSync('<p>target</p>');
    _writeCatalog(temporary);
    final processScript = File(p.join(temporary.path, 'target_process.dart'));
    processScript.writeAsStringSync('''
import 'dart:async';
void main() => Timer.periodic(const Duration(seconds: 30), (_) {});
''');
    studioOrigin = StaticWebOriginServer(rootDirectory: studioRoot.path);
    targetOrigin = StaticWebOriginServer(rootDirectory: targetRoot.path);
    await studioOrigin.start();
    await targetOrigin.start();
    application = DevExHostApplication(
      studioOrigin: studioOrigin.origin,
      sessionToken: token,
      workspaceRoot: temporary.path,
      launchProfiles: <LaunchProfile>[
        LaunchProfile(
          id: 'web',
          applicationId: ApplicationId('app'),
          platform: TargetPlatform.web,
          command: Platform.resolvedExecutable,
          arguments: <String>[processScript.path],
          workingDirectory: '.',
          overlay: RuntimeConfigurationOverlay(const <String, String>{}),
          bootstrapPolicy: ApplicationBootstrapPolicy(
            const <String, BootstrapDependencyPolicy>{},
          ),
        ),
      ],
      gatewaySidecarCommand: Platform.resolvedExecutable,
      gatewaySidecarArguments: const <String>[
        'run',
        'apps/backend_gateway/bin/backend_gateway.dart',
      ],
      gatewaySidecarWorkingDirectory: _repositoryRoot(),
    );
    await application.start();
  });

  tearDown(() async {
    await application.close();
    await targetOrigin.close();
    await studioOrigin.close();
    temporary.deleteSync(recursive: true);
  });

  test(
    'uses separate origins and rejects domain methods before initialize',
    () async {
      expect(studioOrigin.origin.origin, isNot(targetOrigin.origin.origin));
      final rpc = await _RpcClient.connect(
        application.rpc,
        studioOrigin.origin,
      );
      final response = await rpc.call('devex.session.get', <String, Object?>{
        'sessionId': 'missing',
      });

      expect(response.error?.code, -32001);
      await rpc.close();
    },
  );

  test('survives 20 start reset capture stop cycles without residue', () async {
    final rpc = await _RpcClient.connect(application.rpc, studioOrigin.origin);
    expect((await rpc.initialize()).isSuccess, isTrue);

    for (var cycle = 0; cycle < 20; cycle += 1) {
      final start = await rpc.call('devex.session.start', <String, Object?>{
        'launchProfileId': 'web',
        'targetOrigin': targetOrigin.origin.toString(),
      });
      final startResult = start.result! as Map<String, Object?>;
      final sessionId = startResult['id']! as String;
      expect(startResult['state'], 'ready');

      final reset = await rpc.call('devex.session.reset', <String, Object?>{
        'sessionId': sessionId,
      });
      expect((reset.result! as Map<String, Object?>)['state'], 'ready');
      if (cycle == 0) {
        final capture = await rpc.call(
          'devex.capture.request',
          <String, Object?>{'sessionId': sessionId, 'format': 'png'},
        );
        final command = AppAdapterCaptureCommand.fromJson(capture.result);
        expect(command.format, 'png');
        final captureBytes = rgbaPng(
          width: 1,
          height: 1,
          pixels: const <int>[10, 20, 30, 255],
        );
        expect(
          await _putCapture(
            command.uploadUri,
            origin: targetOrigin.origin.origin,
            bytes: captureBytes,
          ),
          HttpStatus.created,
        );
        final status = await rpc.call('devex.capture.status', <String, Object?>{
          'sessionId': sessionId,
          'requestId': command.requestId,
        });
        final captureStatus = status.result! as Map<String, Object?>;
        expect(captureStatus['state'], 'completed');
        final receipt = captureStatus['receipt']! as Map<String, Object?>;
        final artifact = Digest(receipt['artifactDigest']! as String);
        expect(application.store.readBlob(artifact), captureBytes);
      }
      final stop = await rpc.call('devex.session.stop', <String, Object?>{
        'sessionId': sessionId,
      });
      expect((stop.result! as Map<String, Object?>)['state'], 'stopped');
    }

    expect(application.processes.activeCount, 0);
    expect(application.coordinator.activeSessions, isEmpty);
    expect(application.captureBridge.pendingCount, 0);
    await rpc.close();
  });

  test(
    'owns an isolated Gateway sidecar for the complete Session lifecycle',
    () async {
      final fixtureBytes = utf8.encode('{"source":"host-sidecar"}');
      final fixtureDigest = application.store.withExclusiveLock(
        () => application.store.putBlob(fixtureBytes),
      );
      final plan = _gatewayPlan(fixtureDigest, fixtureBytes.length);
      final planBytes = utf8.encode(
        const JcsCanonicalizer().canonicalize(plan.toJson()),
      );
      final planArtifactDigest = application.store.withExclusiveLock(
        () => application.store.putBlob(planBytes),
      );
      final rpc = await _RpcClient.connect(
        application.rpc,
        studioOrigin.origin,
      );
      final initialized = await rpc.initialize();
      final capabilities =
          (initialized.result! as Map<String, Object?>)['capabilities']!
              as List<Object?>;
      expect(capabilities, contains('devex.gateway.start'));
      expect(capabilities, contains('devex.gateway.presets'));

      final presets = await rpc.call(
        'devex.gateway.presets',
        const <String, Object?>{},
      );
      expect(presets.isSuccess, isTrue);
      final presetList = presets.result! as List<Object?>;
      expect(presetList, hasLength(1));
      final preset = presetList.single! as Map<String, Object?>;
      expect(preset['presetId'], 'test-preset');
      expect(preset['backendMode'], 'isolated');
      expect(preset['routeCount'], 1);
      expect(
        application.store.readBlob(Digest(preset['artifactDigest']! as String)),
        isNotNull,
      );

      final startedSession = await rpc.call(
        'devex.session.start',
        <String, Object?>{
          'launchProfileId': 'web',
          'targetOrigin': targetOrigin.origin.toString(),
        },
      );
      final ownerSessionId =
          (startedSession.result! as Map<String, Object?>)['id']! as String;
      final startedGateway = await rpc
          .call('devex.gateway.start', <String, Object?>{
            'ownerSessionId': ownerSessionId,
            'planArtifactDigest': planArtifactDigest.value,
          });
      expect(startedGateway.isSuccess, isTrue);
      final gateway = startedGateway.result! as Map<String, Object?>;
      final gatewaySessionId = gateway['id']! as String;
      final dataOrigin = Uri.parse(gateway['dataOrigin']! as String);
      expect(gateway['planDigest'], plan.digest.value);
      expect(application.gateways!.activeCount, 1);
      expect(await _get(dataOrigin.replace(path: '/value')), fixtureBytes);

      final verification = await rpc.call(
        'devex.gateway.verify',
        <String, Object?>{
          'gatewaySessionId': gatewaySessionId,
          'method': 'GET',
          'path': '/value',
        },
      );
      final verificationResult = verification.result! as Map<String, Object?>;
      final verifiedArtifact = Digest(
        verificationResult['responseBodyArtifactDigest']! as String,
      );
      expect(application.store.readBlob(verifiedArtifact), fixtureBytes);
      expect(verificationResult, isNot(contains('responseBodyBase64')));
      final traffic = await rpc.call('devex.gateway.traffic', <String, Object?>{
        'gatewaySessionId': gatewaySessionId,
      });
      expect(traffic.result, hasLength(2));
      expect(
        (await rpc.call('devex.gateway.reset', <String, Object?>{
          'gatewaySessionId': gatewaySessionId,
        })).isSuccess,
        isTrue,
      );

      final stoppedSession = await rpc.call(
        'devex.session.stop',
        <String, Object?>{'sessionId': ownerSessionId},
      );
      expect(
        (stoppedSession.result! as Map<String, Object?>)['state'],
        'stopped',
      );
      expect(application.gateways!.activeCount, 0);
      await expectLater(
        _get(dataOrigin.replace(path: '/value')),
        throwsA(isA<SocketException>()),
      );
      await rpc.close();
    },
  );

  test(
    'journey-preview Host exposes only kernel RPCs and no extra listener',
    () async {
      const builtins = BuiltinModuleCatalog();
      final catalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: catalog,
        profileId: 'journey-preview',
        configurationSchemas: builtins.configurationSchemas,
      );
      final minimal = DevExHostApplication.fromResolvedPlan(
        studioOrigin: studioOrigin.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: const <LaunchProfile>[],
        catalog: catalog,
        plan: plan,
      );
      await minimal.start();
      addTearDown(minimal.close);

      final rpc = await _RpcClient.connect(minimal.rpc, studioOrigin.origin);
      final initialized = await rpc.initialize();
      final capabilities =
          (initialized.result! as Map<String, Object?>)['capabilities']!
              as List<Object?>;
      expect(
        capabilities,
        containsAll(<String>[
          'devex.kit.describe',
          'devex.kit.health',
          'devex.workspace.describe',
          'devex.workspace.open',
          'devex.workspace.refresh',
          'devex.preview.collect',
          'devex.preview.status',
          'devex.preview.cancel',
        ]),
      );
      expect(capabilities, isNot(contains('devex.session.start')));
      expect(capabilities, isNot(contains('devex.capture.request')));
      expect(capabilities, isNot(contains('devex.gateway.start')));
      final described = await rpc.call(
        'devex.kit.describe',
        const <String, Object?>{},
      );
      final manifest = EffectiveKitManifest.fromJson(described.result);
      expect(manifest.resolvedPlanDigest, plan.digest);
      expect(
        EffectiveKitManifest.fromJson(
          jsonDecode(File(minimal.effectiveKitManifestPath).readAsStringSync()),
        ).digest,
        manifest.digest,
      );
      expect(
        manifest.modules
            .where((module) => module.state == ModuleRuntimeState.ready)
            .map((module) => module.moduleId.value),
        containsAll(<String>[
          'catalog',
          'artifact-store.local',
          'studio.shell',
          'studio.journey-map',
          'evidence.auto-preview',
        ]),
      );
      expect(minimal.captureBridge.isRunning, isFalse);
      expect(minimal.processes.activeCount, 0);
      expect(minimal.gateways, isNull);

      final workspaceDescription = await rpc.call(
        'devex.workspace.describe',
        const <String, Object?>{},
      );
      final description = workspaceDescription.result! as Map<String, Object?>;
      expect(description['workspaceId'], 'sample');
      expect(description['revision'], isA<int>());
      expect(description['catalogDigest'], isNotEmpty);
      final firstRevision = description['revision']! as int;

      final opened = await rpc.call('devex.workspace.open', <String, Object?>{
        'expectedRevision': firstRevision,
      });
      final openedResult = opened.result! as Map<String, Object?>;
      final handle = ResourceHandle.fromJson(openedResult['resource']);
      final snapshot = WorkspaceSnapshot.fromJson(
        jsonDecode(
          utf8.decode(
            await _get(handle.uri, origin: studioOrigin.origin.origin),
          ),
        ),
      );
      expect(snapshot.catalog.digest.value, description['catalogDigest']);
      expect(snapshot.catalog.journeys.single.id, JourneyId('flow'));
      expect(snapshot.catalog.scenarios.single.id, ScenarioId('first'));
      expect(
        snapshot.providers.single.providerId,
        ModuleId('evidence.auto-preview'),
      );
      expect(
        snapshot.providers.single.supportedFidelities,
        const <RuntimeFidelity>{RuntimeFidelity.structural},
      );

      File(p.join(temporary.path, '.devex', 'second.yaml')).writeAsStringSync(
        '''
schemaVersion: 1
kind: Scenario
metadata: {id: second}
spec: {applicationId: app, title: Second scenario}
''',
      );
      File(p.join(temporary.path, '.devex', 'journey.yaml')).writeAsStringSync(
        '''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Main flow, scenarioIds: [first, second]}
''',
      );
      final refreshed = await rpc.call(
        'devex.workspace.refresh',
        const <String, Object?>{},
      );
      final refreshedResult = refreshed.result! as Map<String, Object?>;
      expect(refreshedResult['changed'], isTrue);
      final secondRevision = refreshedResult['revision']! as int;
      expect(secondRevision, greaterThan(firstRevision));
      expect(
        minimal.rpc.journal.after(0).map((event) => event.method),
        contains('devex.workspace.changed'),
      );
      final staleOpen = await rpc.call(
        'devex.workspace.open',
        <String, Object?>{'expectedRevision': firstRevision},
      );
      expect(staleOpen.error?.code, -32003);
      final secondOpen = await rpc.call(
        'devex.workspace.open',
        <String, Object?>{'expectedRevision': secondRevision},
      );
      final secondHandle = ResourceHandle.fromJson(
        (secondOpen.result! as Map<String, Object?>)['resource'],
      );
      final secondSnapshot = WorkspaceSnapshot.fromJson(
        jsonDecode(
          utf8.decode(
            await _get(secondHandle.uri, origin: studioOrigin.origin.origin),
          ),
        ),
      );
      expect(secondSnapshot.catalog.scenarios, hasLength(2));
      await rpc.close();
    },
  );

  test(
    'journey-android remains independent from Preview and Adapter',
    () async {
      const builtins = BuiltinModuleCatalog();
      final catalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: catalog,
        profileId: 'journey-android',
        configurationSchemas: builtins.configurationSchemas,
      );
      final application = DevExHostApplication.fromResolvedPlan(
        studioOrigin: studioOrigin.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: const <LaunchProfile>[],
        catalog: catalog,
        plan: plan,
      );
      await application.start();
      addTearDown(application.close);
      final rpc = await _RpcClient.connect(
        application.rpc,
        studioOrigin.origin,
      );
      final initialized = await rpc.initialize();
      final capabilities =
          (initialized.result! as Map<String, Object?>)['capabilities']!
              as List<Object?>;

      expect(capabilities, contains('devex.session.start'));
      expect(capabilities, isNot(contains('devex.preview.collect')));
      expect(capabilities, isNot(contains('devex.capture.request')));
      expect(capabilities, isNot(contains('devex.gateway.start')));
      expect(application.processes.activeCount, 0);
      expect(application.captureBridge.isRunning, isFalse);

      final description =
          (await rpc.call(
                'devex.workspace.describe',
                const <String, Object?>{},
              )).result!
              as Map<String, Object?>;
      final opened = await rpc.call('devex.workspace.open', <String, Object?>{
        'expectedRevision': description['revision'],
      });
      final handle = ResourceHandle.fromJson(
        (opened.result! as Map<String, Object?>)['resource'],
      );
      final snapshot = WorkspaceSnapshot.fromJson(
        jsonDecode(
          utf8.decode(
            await _get(handle.uri, origin: studioOrigin.origin.origin),
          ),
        ),
      );
      expect(snapshot.providers, hasLength(1));
      expect(snapshot.providers.single.providerId.value, 'evidence.android');
      expect(snapshot.providers.single.supportsCollection, isFalse);
      expect(snapshot.visualProjections, isEmpty);
      await rpc.close();
    },
  );

  test('disabled catalog adds no workspace RPC and reads no config', () async {
    const builtins = BuiltinModuleCatalog();
    final catalog = builtins.create(platform: 'linux-x64');
    final plan = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'gateway-lab-headless',
      overlays: <KitSelection>[
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(moduleId: ModuleId('catalog'), enabled: false),
            KitModuleSelection(
              moduleId: ModuleId('artifact-store.local'),
              enabled: false,
            ),
            KitModuleSelection(
              moduleId: ModuleId('gateway.interceptor'),
              enabled: false,
            ),
          ],
        ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );
    final noConfig = Directory(p.join(temporary.path, 'no-config'))
      ..createSync();
    final minimal = DevExHostApplication.fromResolvedPlan(
      studioOrigin: studioOrigin.origin,
      sessionToken: token,
      workspaceRoot: noConfig.path,
      launchProfiles: const <LaunchProfile>[],
      catalog: catalog,
      plan: plan,
    );
    await minimal.start();
    addTearDown(minimal.close);

    final rpc = await _RpcClient.connect(minimal.rpc, studioOrigin.origin);
    final initialized = await rpc.initialize();
    final capabilities =
        (initialized.result! as Map<String, Object?>)['capabilities']!
            as List<Object?>;
    expect(capabilities, contains('devex.kit.describe'));
    expect(capabilities, isNot(contains('devex.workspace.describe')));
    expect(capabilities, isNot(contains('devex.workspace.open')));
    expect(capabilities, isNot(contains('devex.workspace.refresh')));
    expect(minimal.workspace, isNull);
    expect(File(p.join(noConfig.path, 'devex.yaml')).existsSync(), isFalse);
    expect(Directory(p.join(noConfig.path, '.devex')).existsSync(), isFalse);
    await rpc.close();
  });
}

CompiledGatewayPlan _gatewayPlan(Digest fixtureDigest, int fixtureSize) {
  final scopeId = GatewayScopeId('sample');
  final presetId = GatewayPresetId('default');
  final route = GatewayRoute(
    id: GatewayRouteId('value'),
    scopeId: scopeId,
    method: 'GET',
    pathTemplate: '/value',
    requiredQuery: const <String, String>{},
    appliesTo: <GatewayPresetId>{presetId},
    policy: GatewayRoutePolicy.localOnly,
    fixtureId: GatewayFixtureId('value-fixture'),
  );
  return const GatewayPlanCompiler()
      .compile(
        scope: GatewayScope(
          id: scopeId,
          displayName: 'Sample',
          routeIds: <GatewayRouteId>[route.id],
        ),
        preset: GatewayPreset(
          id: presetId,
          scopeId: scopeId,
          description: 'Default',
          routeIds: <GatewayRouteId>[route.id],
        ),
        routes: <GatewayRoute>[route],
        fixtures: <GatewayFixture>[
          GatewayFixture(
            id: GatewayFixtureId('value-fixture'),
            status: 200,
            headers: const <String, String>{'content-type': 'application/json'},
            bodyDigest: fixtureDigest,
            bodySize: fixtureSize,
            mediaType: 'application/json',
          ),
        ],
      )
      .plan;
}

Future<List<int>> _get(Uri uri, {String? origin}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final request = await client.getUrl(uri);
    if (origin != null) request.headers.set('origin', origin);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GET failed with ${response.statusCode}', uri: uri);
    }
    return await response.fold<List<int>>(
      <int>[],
      (output, chunk) => output..addAll(chunk),
    );
  } finally {
    client.close(force: true);
  }
}

void _writeCatalog(Directory workspace) {
  Directory(p.join(workspace.path, '.devex')).createSync();
  File(p.join(workspace.path, 'devex.yaml')).writeAsStringSync('''
schemaVersion: 1
content: {root: .devex}
workspace: {id: sample, displayName: Sample workspace}
applications:
  app: {root: ., target: local}
''');
  File(p.join(workspace.path, '.devex', 'scenario.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata: {id: first}
spec: {applicationId: app, title: First scenario}
''');
  File(p.join(workspace.path, '.devex', 'journey.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Main flow, scenarioIds: [first]}
''');
  final gateway = Directory(p.join(workspace.path, '.devex', 'gateway'))
    ..createSync();
  final fixtures = Directory(p.join(gateway.path, 'fixtures'))..createSync();
  File(p.join(fixtures.path, 'value.body')).writeAsStringSync('{"ok":true}');
  File(p.join(gateway.path, 'scope.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayScope
metadata: {id: test-scope}
spec: {displayName: Test API, routeIds: [test-route]}
''');
  File(p.join(gateway.path, 'preset.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayPreset
metadata: {id: test-preset}
spec:
  scopeId: test-scope
  description: Deterministic test preset
  backendMode: isolated
  routeIds: [test-route]
''');
  File(p.join(gateway.path, 'route.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayRoute
metadata: {id: test-route}
spec:
  scopeId: test-scope
  method: GET
  pathTemplate: /value
  appliesTo: [test-preset]
  policy: localOnly
  fixtureId: test-fixture
''');
  File(p.join(gateway.path, 'fixture.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayFixture
metadata: {id: test-fixture}
spec:
  status: 200
  headers: {content-type: application/json}
  bodyFile: fixtures/value.body
  mediaType: application/json
''');
}

Future<int> _putCapture(
  Uri uri, {
  required String origin,
  required List<int> bytes,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.putUrl(uri);
    request.headers
      ..set('origin', origin)
      ..contentType = ContentType('image', 'png');
    request.add(bytes);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

final class _RpcClient {
  _RpcClient(this.channel, this.iterator, this.sessionToken);

  final IOWebSocketChannel channel;
  final StreamIterator<Object?> iterator;
  final String sessionToken;
  var nextId = 1;

  static Future<_RpcClient> connect(
    HostRpcServer server,
    Uri studioOrigin,
  ) async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      headers: <String, String>{'Origin': studioOrigin.origin},
    );
    await channel.ready;
    return _RpcClient(
      channel,
      StreamIterator<Object?>(channel.stream),
      server.sessionToken,
    );
  }

  Future<JsonRpcResponse> initialize() => call(
    'devex.initialize',
    <String, Object?>{'protocolVersion': 1, 'sessionToken': sessionToken},
  );

  Future<JsonRpcResponse> call(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = 'request-${nextId++}';
    channel.sink.add(
      JsonRpcRequest(method: method, id: id, params: params).encode(),
    );
    while (await iterator.moveNext()) {
      final message = const JsonRpcCodec().decode(iterator.current! as String);
      if (message is JsonRpcResponse && message.id == id) return message;
    }
    throw StateError('RPC connection closed before response $id');
  }

  Future<void> close() async {
    await iterator.cancel();
    await channel.sink.close();
  }
}

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final workspace = File(p.join(current.path, 'pubspec.yaml'));
    if (workspace.existsSync() &&
        workspace.readAsStringSync().contains('name: devex_workspace')) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
