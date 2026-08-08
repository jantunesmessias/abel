import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/png_fixture.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  late Directory temporary;
  late StaticWebOriginServer studioOrigin;
  late StaticWebOriginServer targetOrigin;
  late WorkspaceHost application;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('workspace-host-app-');
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
    application = WorkspaceHost(
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
      gatewaySidecarArguments: <String>[
        p.join(
          _repositoryRoot(),
          'apps',
          'gateway_sidecar',
          'bin',
          'gateway_sidecar.dart',
        ),
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
      final response = await rpc.call('session.get', <String, Object?>{
        'sessionId': 'missing',
      });

      expect(response.error?.code, -32001);
      await rpc.close();
    },
  );

  test(
    'announces exactly five Quality RPCs and preserves typed errors',
    () async {
      final rpc = await _RpcClient.connect(
        application.rpc,
        studioOrigin.origin,
      );
      final initialized = await rpc.initialize();
      final capabilities =
          (initialized.result! as Map<String, Object?>)['capabilities']!
              as List<Object?>;
      expect(
        capabilities.whereType<String>().where(
          (method) => method.startsWith('quality'),
        ),
        <String>[
          'quality.decision.append',
          'quality.decision.get',
          'quality.decision.grant',
          'quality.describe',
          'quality.open',
        ],
      );

      final request = ScenarioQualityDescribeRequest(
        runId: ScenarioLabRunId('missing-run'),
        expectedRunResultDigest: Digest.semantic('missing-result'),
      );
      final response = await rpc.call('quality.describe', request.toJson());
      expect(response.error?.code, ScenarioQualityDecisionError.jsonRpcCode);
      final error = ScenarioQualityDecisionError.fromJson(response.error?.data);
      expect(error.operation, ScenarioQualityDecisionOperation.describe);
      expect(error.code, ScenarioQualityDecisionErrorCode.notFound);
      expect(error.runId, request.runId);
      expect(error.expectedRunResultDigest, request.expectedRunResultDigest);
      await rpc.close();
    },
  );

  test('survives 20 start reset capture stop cycles without residue', () async {
    final rpc = await _RpcClient.connect(application.rpc, studioOrigin.origin);
    expect((await rpc.initialize()).isSuccess, isTrue);

    for (var cycle = 0; cycle < 20; cycle += 1) {
      final start = await rpc.call('session.start', <String, Object?>{
        'launchProfileId': 'web',
        'targetOrigin': targetOrigin.origin.toString(),
      });
      final startResult = start.result! as Map<String, Object?>;
      final sessionId = startResult['id']! as String;
      expect(startResult['state'], 'ready');

      final reset = await rpc.call('session.reset', <String, Object?>{
        'sessionId': sessionId,
      });
      expect((reset.result! as Map<String, Object?>)['state'], 'ready');
      if (cycle == 0) {
        final capture = await rpc.call('capture.request', <String, Object?>{
          'sessionId': sessionId,
          'format': 'png',
        });
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
        final status = await rpc.call('capture.status', <String, Object?>{
          'sessionId': sessionId,
          'requestId': command.requestId,
        });
        final captureStatus = status.result! as Map<String, Object?>;
        expect(captureStatus['state'], 'completed');
        final receipt = captureStatus['receipt']! as Map<String, Object?>;
        final artifact = Digest(receipt['artifactDigest']! as String);
        expect(application.store.readBlob(artifact), captureBytes);
      }
      final stop = await rpc.call('session.stop', <String, Object?>{
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
      expect(capabilities, contains('gateway.start'));
      expect(capabilities, contains('gateway.presets'));

      final presets = await rpc.call(
        'gateway.presets',
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

      final startedSession = await rpc.call('session.start', <String, Object?>{
        'launchProfileId': 'web',
        'targetOrigin': targetOrigin.origin.toString(),
      });
      final ownerSessionId =
          (startedSession.result! as Map<String, Object?>)['id']! as String;
      final startedGateway = await rpc.call('gateway.start', <String, Object?>{
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

      final verification = await rpc.call('gateway.verify', <String, Object?>{
        'gatewaySessionId': gatewaySessionId,
        'method': 'GET',
        'path': '/value',
      });
      final verificationResult = verification.result! as Map<String, Object?>;
      final verifiedArtifact = Digest(
        verificationResult['responseBodyArtifactDigest']! as String,
      );
      expect(application.store.readBlob(verifiedArtifact), fixtureBytes);
      expect(verificationResult, isNot(contains('responseBodyBase64')));
      final traffic = await rpc.call('gateway.traffic', <String, Object?>{
        'gatewaySessionId': gatewaySessionId,
      });
      expect(traffic.result, hasLength(2));
      expect(
        (await rpc.call('gateway.reset', <String, Object?>{
          'gatewaySessionId': gatewaySessionId,
        })).isSuccess,
        isTrue,
      );

      final stoppedSession = await rpc.call('session.stop', <String, Object?>{
        'sessionId': ownerSessionId,
      });
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

    timeout: const Timeout(Duration(minutes: 2)),
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
      final minimal = WorkspaceHost.fromResolvedPlan(
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
          'composition.describe',
          'composition.health',
          'workspace.describe',
          'workspace.open',
          'workspace.refresh',
          'experience.content.describe',
          'experience.content.open',
          'preview.collect',
          'preview.status',
          'preview.cancel',
        ]),
      );
      expect(capabilities, isNot(contains('session.start')));
      expect(capabilities, isNot(contains('capture.request')));
      expect(capabilities, isNot(contains('gateway.start')));
      final described = await rpc.call(
        'composition.describe',
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
      expect(manifest.studioContributions, <String>[
        'studio.inventory',
        'studio.journey-map',
        'studio.lab',
        'studio.quality',
        'studio.shell',
      ]);
      expect(minimal.captureBridge.isRunning, isFalse);
      expect(minimal.processes.activeCount, 0);
      expect(minimal.gateways, isNull);

      final workspaceDescription = await rpc.call(
        'workspace.describe',
        const <String, Object?>{},
      );
      final description = workspaceDescription.result! as Map<String, Object?>;
      expect(description['workspaceId'], 'sample');
      expect(description['revision'], isA<int>());
      expect(description['catalogDigest'], isNotEmpty);
      final firstRevision = description['revision']! as int;

      final opened = await rpc.call('workspace.open', <String, Object?>{
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

      File(
        p.join(temporary.path, '.experience', 'second.yaml'),
      ).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata: {id: second}
spec: {applicationId: app, title: Second scenario}
''');
      File(
        p.join(temporary.path, '.experience', 'journey.yaml'),
      ).writeAsStringSync('''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Main flow, scenarioIds: [first, second]}
''');
      final refreshed = await rpc.call(
        'workspace.refresh',
        const <String, Object?>{},
      );
      final refreshedResult = refreshed.result! as Map<String, Object?>;
      expect(refreshedResult['changed'], isTrue);
      expect(refreshedResult, isNot(contains('facetsChanged')));
      final secondRevision = refreshedResult['revision']! as int;
      expect(secondRevision, greaterThan(firstRevision));
      expect(
        minimal.rpc.journal.after(0).map((event) => event.method),
        contains('workspace.changed'),
      );
      final staleOpen = await rpc.call('workspace.open', <String, Object?>{
        'expectedRevision': firstRevision,
      });
      expect(staleOpen.error?.code, -32003);
      final secondOpen = await rpc.call('workspace.open', <String, Object?>{
        'expectedRevision': secondRevision,
      });
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
      final application = WorkspaceHost.fromResolvedPlan(
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

      expect(capabilities, contains('session.start'));
      expect(capabilities, isNot(contains('preview.collect')));
      expect(capabilities, isNot(contains('capture.request')));
      expect(capabilities, isNot(contains('gateway.start')));
      expect(application.processes.activeCount, 0);
      expect(application.captureBridge.isRunning, isFalse);

      final description =
          (await rpc.call(
                'workspace.describe',
                const <String, Object?>{},
              )).result!
              as Map<String, Object?>;
      final opened = await rpc.call('workspace.open', <String, Object?>{
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

  test(
    'catalog module serves an injected Experience bundle by scoped resource',
    () async {
      const builtins = BuiltinModuleCatalog();
      final moduleCatalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: moduleCatalog,
        profileId: 'journey-android',
        configurationSchemas: builtins.configurationSchemas,
      );
      final catalog = _experienceCatalog();
      final bundle = _experienceBundle(catalog);
      final facets = _experienceFacets(catalog);
      final lab = _experienceLab(catalog);
      final experienceApplication = WorkspaceHost.fromResolvedPlan(
        studioOrigin: studioOrigin.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: const <LaunchProfile>[],
        catalog: moduleCatalog,
        plan: plan,
        workspaceCatalog: catalog,
        workspaceExperienceBundle: bundle,
        workspaceScenarioFacetManifest: facets,
        workspaceScenarioLabManifest: lab,
      );
      await experienceApplication.start();
      final rpc = await _RpcClient.connect(
        experienceApplication.rpc,
        studioOrigin.origin,
      );
      try {
        final initialized = await rpc.initialize();
        final capabilities =
            (initialized.result! as Map<String, Object?>)['capabilities']!
                as List<Object?>;
        expect(
          capabilities,
          containsAll(<String>[
            'experience.describe',
            'experience.open',
            'experience.content.describe',
            'experience.content.open',
          ]),
        );

        final description =
            (await rpc.call(
                  'experience.describe',
                  const <String, Object?>{},
                )).result!
                as Map<String, Object?>;
        expect(description['status'], 'ready');
        expect(description['catalogDigest'], catalog.digest.value);
        expect(description['topologyDigest'], bundle.topology.digest.value);
        expect(description['bundleDigest'], bundle.digest.value);
        expect(description['layoutDigests'], hasLength(1));

        final opened = await rpc.call('experience.open', <String, Object?>{
          'expectedRevision': description['revision'],
          'expectedBundleDigest': bundle.digest.value,
        });
        final openedResult = opened.result! as Map<String, Object?>;
        final handle = ResourceHandle.fromJson(openedResult['resource']);
        expect(handle.mediaType, 'application/json');
        expect(handle.purpose, 'experience-topology-bundle');
        final bytes = await _get(
          handle.uri,
          origin: studioOrigin.origin.origin,
        );
        expect(handle.digest, Digest.bytes(bytes));
        final decoded = ExperienceTopologyBundle.fromJson(
          jsonDecode(utf8.decode(bytes)),
          catalog: catalog,
        );
        expect(decoded.digest, bundle.digest);
        expect(experienceApplication.rpc.resources.activeCount, 1);

        final stale = await rpc.call('experience.open', <String, Object?>{
          'expectedRevision': (description['revision']! as int) + 1,
        });
        expect(stale.error?.code, -32003);

        final contentDescription = ExperienceContentSetDescription.fromJson(
          (await rpc.call(
            'experience.content.describe',
            const <String, Object?>{},
          )).result,
        );
        final identity = contentDescription.identity;
        expect(identity.catalogDigest, catalog.digest);
        expect(identity.workspaceSnapshotDigest, isNotNull);
        expect(identity.experienceTopologyBundleDigest, bundle.digest);
        expect(identity.scenarioFacetManifestDigest, facets.digest);
        expect(identity.scenarioLabManifestDigest, lab.digest);

        final missingFence = await rpc.call(
          'experience.content.open',
          <String, Object?>{'expectedRevision': identity.revision},
        );
        expect(missingFence.error?.code, JsonRpcError.invalidParams);
        final wrongType = await rpc
            .call('experience.content.open', <String, Object?>{
              'expectedRevision': '${identity.revision}',
              'catalogDigest': identity.catalogDigest.value,
              'contentSetDigest': identity.contentSetDigest.value,
            });
        expect(wrongType.error?.code, JsonRpcError.invalidParams);
        final unsafeRevision = await rpc
            .call('experience.content.open', <String, Object?>{
              'expectedRevision': JcsCanonicalizer.maxSafeInteger + 1,
              'catalogDigest': identity.catalogDigest.value,
              'contentSetDigest': identity.contentSetDigest.value,
            });
        expect(unsafeRevision.error?.code, JsonRpcError.invalidParams);
        final staleContent = await rpc
            .call('experience.content.open', <String, Object?>{
              'expectedRevision': identity.revision + 1,
              'catalogDigest': identity.catalogDigest.value,
              'contentSetDigest': identity.contentSetDigest.value,
            });
        expect(staleContent.error?.code, -32003);
        final wrongCatalog = await rpc
            .call('experience.content.open', <String, Object?>{
              'expectedRevision': identity.revision,
              'catalogDigest': Digest.semantic('another-catalog').value,
              'contentSetDigest': identity.contentSetDigest.value,
            });
        expect(wrongCatalog.error?.code, -32003);
        final wrongContent = await rpc
            .call('experience.content.open', <String, Object?>{
              'expectedRevision': identity.revision,
              'catalogDigest': identity.catalogDigest.value,
              'contentSetDigest': Digest.semantic('another-content-set').value,
            });
        expect(wrongContent.error?.code, -32003);
        expect(experienceApplication.rpc.resources.activeCount, 1);

        final contentOpenResponse = await rpc
            .call('experience.content.open', <String, Object?>{
              'expectedRevision': identity.revision,
              'catalogDigest': identity.catalogDigest.value,
              'contentSetDigest': identity.contentSetDigest.value,
            });
        final contentOpen = ExperienceContentSetOpenResult.fromJson(
          contentOpenResponse.result,
        );
        expect(contentOpen.identity.toJson(), identity.toJson());
        final contentSnapshot = WorkspaceSnapshot.fromJson(
          jsonDecode(
            utf8.decode(
              await _get(
                contentOpen.workspaceSnapshot.uri,
                origin: studioOrigin.origin.origin,
              ),
            ),
          ),
        );
        final contentBundle = ExperienceTopologyBundle.fromJson(
          jsonDecode(
            utf8.decode(
              await _get(
                contentOpen.experienceTopologyBundle!.uri,
                origin: studioOrigin.origin.origin,
              ),
            ),
          ),
          catalog: contentSnapshot.catalog,
        );
        final contentFacets = ScenarioFacetManifest.fromJson(
          jsonDecode(
            utf8.decode(
              await _get(
                contentOpen.scenarioFacetManifest!.uri,
                origin: studioOrigin.origin.origin,
              ),
            ),
          ),
          catalog: contentSnapshot.catalog,
        );
        final contentLab = ScenarioLabManifest.fromJson(
          jsonDecode(
            utf8.decode(
              await _get(
                contentOpen.scenarioLabManifest!.uri,
                origin: studioOrigin.origin.origin,
              ),
            ),
          ),
          catalog: contentSnapshot.catalog,
        );
        expect(contentSnapshot.digest, identity.workspaceSnapshotDigest);
        expect(contentBundle.digest, bundle.digest);
        expect(contentFacets.digest, facets.digest);
        expect(contentLab.digest, lab.digest);
        expect(experienceApplication.rpc.resources.activeCount, 5);
      } finally {
        await rpc.close();
        await experienceApplication.close();
      }
      expect(experienceApplication.rpc.resources.activeCount, 0);
    },
  );

  test('Experience describe is explicit when topology is absent', () async {
    const builtins = BuiltinModuleCatalog();
    final moduleCatalog = builtins.create(platform: 'linux-x64');
    final plan = const KitPlanResolver().resolve(
      catalog: moduleCatalog,
      profileId: 'journey-android',
      configurationSchemas: builtins.configurationSchemas,
    );
    final catalog = _experienceCatalog();
    final experienceApplication = WorkspaceHost.fromResolvedPlan(
      studioOrigin: studioOrigin.origin,
      sessionToken: token,
      workspaceRoot: temporary.path,
      launchProfiles: const <LaunchProfile>[],
      catalog: moduleCatalog,
      plan: plan,
      workspaceCatalog: catalog,
    );
    await experienceApplication.start();
    final rpc = await _RpcClient.connect(
      experienceApplication.rpc,
      studioOrigin.origin,
    );
    try {
      await rpc.initialize();
      final description =
          (await rpc.call(
                'experience.describe',
                const <String, Object?>{},
              )).result!
              as Map<String, Object?>;
      expect(description['status'], 'absent');
      expect(description['catalogDigest'], catalog.digest.value);
      expect(description, isNot(contains('bundleDigest')));

      final opened = await rpc.call('experience.open', <String, Object?>{
        'expectedRevision': description['revision'],
      });
      expect(opened.error?.code, -32003);
      expect(experienceApplication.rpc.resources.activeCount, 0);
    } finally {
      await rpc.close();
      await experienceApplication.close();
    }
  });

  test(
    'Motion and Context Builder are exposed through the resolved Host RPC',
    () async {
      const builtins = BuiltinModuleCatalog();
      final moduleCatalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: moduleCatalog,
        profileId: 'journey-preview',
        overlays: <KitSelection>[
          KitSelection(
            modules: <KitModuleSelection>[
              KitModuleSelection(
                moduleId: ModuleId('studio.motion'),
                enabled: true,
              ),
              KitModuleSelection(
                moduleId: ModuleId('motion.local'),
                enabled: true,
              ),
              KitModuleSelection(
                moduleId: ModuleId('studio.context'),
                enabled: true,
              ),
              KitModuleSelection(
                moduleId: ModuleId('context.builder.local'),
                enabled: true,
              ),
            ],
          ),
        ],
        configurationSchemas: builtins.configurationSchemas,
      );
      final catalog = _experienceCatalog();
      final bundle = _experienceBundle(catalog);
      final motion = _experienceMotion(catalog, bundle);
      final motionApplication = WorkspaceHost.fromResolvedPlan(
        studioOrigin: studioOrigin.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: const <LaunchProfile>[],
        catalog: moduleCatalog,
        plan: plan,
        workspaceCatalog: catalog,
        workspaceExperienceBundle: bundle,
        workspaceMotionManifest: motion,
      );
      await motionApplication.start();
      final rpc = await _RpcClient.connect(
        motionApplication.rpc,
        studioOrigin.origin,
      );
      try {
        final initialized = await rpc.initialize();
        final capabilities =
            (initialized.result! as Map<String, Object?>)['capabilities']!
                as List<Object?>;
        expect(
          capabilities,
          containsAll(<String>['context.describe', 'context.build']),
        );
        expect(
          motionApplication.effectiveKitManifest.studioContributions,
          containsAll(<String>['studio.motion', 'studio.context']),
        );

        final description = ContextBuilderDescription.fromJson(
          (await rpc.call(
            'context.describe',
            const <String, Object?>{},
          )).result,
        );
        expect(
          description.contentSetDigest,
          motionApplication.workspace!.contentSetIdentity.contentSetDigest,
        );
        expect(
          description.supportedCategories,
          isNot(contains(ContextCategory.sources)),
        );
        final request = ContextBuildRequest(
          expectedContentSetDigest: description.contentSetDigest,
          selection: ContextSelection(
            boardId: BoardId('flow-board'),
            projectionId: ExperienceProjectionId('flow-projection'),
            journeyId: JourneyId('flow'),
            scenarioId: ScenarioId('ready'),
          ),
          inclusion: const ContextInclusion(
            sources: true,
            images: true,
            evidence: true,
            history: true,
            changes: true,
          ),
          budgets: description.maximumBudgets,
        );
        final first = ContextBuildResult.fromJson(
          (await rpc.call('context.build', request.toJson())).result,
        );
        final second = ContextBuildResult.fromJson(
          (await rpc.call('context.build', request.toJson())).result,
        );
        expect(first.bundle.digest, second.bundle.digest);
        expect(first.bundle.contentSetDigest, description.contentSetDigest);
        expect(first.bundle.items, isNotEmpty);
        expect(first.bundle.toJson().toString(), isNot(contains('/home/')));

        final stale = await rpc.call(
          'context.build',
          ContextBuildRequest(
            expectedContentSetDigest: Digest.semantic('stale'),
            selection: request.selection,
            inclusion: request.inclusion,
            budgets: request.budgets,
          ).toJson(),
        );
        expect(stale.error?.code, -32003);

        final content = ExperienceContentSetDescription.fromJson(
          (await rpc.call(
            'experience.content.describe',
            const <String, Object?>{},
          )).result,
        );
        expect(content.identity.motionManifestDigest, motion.digest);
      } finally {
        await rpc.close();
        await motionApplication.close();
      }
    },
  );

  test(
    'create compiles Catalog and Experience from one loaded document set',
    () async {
      _writeExperienceAuthoring(temporary);
      _writeFacetAuthoring(temporary, const <String>['first', 'second']);
      _writeLabAuthoring(temporary, displayName: 'Inspect first scenario');
      final compiledApplication = WorkspaceHost.create(
        studioOrigin: studioOrigin.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: const <LaunchProfile>[],
      );
      final bundle = compiledApplication.workspace!.experienceBundle;
      final facets = compiledApplication.workspace!.scenarioFacetManifest;
      final lab = compiledApplication.workspace!.scenarioLabManifest;
      expect(bundle, isNotNull);
      expect(facets, isNotNull);
      expect(lab, isNotNull);
      final requiredBundle = bundle!;
      final requiredFacets = facets!;
      final requiredLab = lab!;
      await compiledApplication.start();
      try {
        expect(
          requiredBundle.catalogDigest,
          compiledApplication.workspace!.snapshot.catalog.digest,
        );
        expect(
          requiredBundle.topology.projections.single.journeyId,
          JourneyId('flow'),
        );
        expect(
          requiredBundle.layouts.single.projectionId.value,
          'flow-projection',
        );
        expect(
          requiredFacets.catalogDigest,
          compiledApplication.workspace!.snapshot.catalog.digest,
        );
        expect(
          requiredFacets.scenarioFacets.map((facet) => facet.scenarioId.value),
          <String>['first', 'second'],
        );
        expect(requiredLab.plans.single.scenarioId, ScenarioId('first'));
        expect(
          requiredLab.scripts.single.id,
          ScenarioScriptId('inspect-first'),
        );
      } finally {
        await compiledApplication.close();
      }
    },
  );

  test(
    'facet-only refresh advances and publishes one atomic content generation',
    () async {
      final rpc = await _RpcClient.connect(
        application.rpc,
        studioOrigin.origin,
      );
      try {
        await rpc.initialize();
        final before = ExperienceContentSetDescription.fromJson(
          (await rpc.call(
            'experience.content.describe',
            const <String, Object?>{},
          )).result,
        ).identity;
        expect(before.scenarioFacetManifestDigest, isNull);
        final cursor = application.rpc.journal.latestSequence;

        _writeFacetAuthoring(temporary, const <String>['first']);
        final refresh =
            (await rpc.call(
                  'workspace.refresh',
                  const <String, Object?>{},
                )).result!
                as Map<String, Object?>;

        expect(refresh['changed'], isFalse);
        expect(refresh, isNot(contains('catalogChanged')));
        expect(refresh, isNot(contains('experienceChanged')));
        expect(refresh, isNot(contains('facetsChanged')));
        expect(refresh, isNot(contains('workspaceSnapshotChanged')));
        final after = ExperienceContentSetDescription.fromJson(
          (await rpc.call(
            'experience.content.describe',
            const <String, Object?>{},
          )).result,
        ).identity;
        expect(after.revision, before.revision + 1);
        expect(after.workspaceSnapshotDigest, before.workspaceSnapshotDigest);
        expect(after.experienceTopologyBundleDigest, isNull);
        expect(after.scenarioFacetManifestDigest, isNotNull);
        expect(after.contentSetDigest, isNot(before.contentSetDigest));

        final contentEvents = application.rpc.journal
            .after(cursor)
            .where((event) => event.method == 'experience.content.changed')
            .toList(growable: false);
        expect(contentEvents, isNotEmpty);
        expect(
          ExperienceContentSetDescription.fromJson(
            contentEvents.first.params,
          ).identity.toJson(),
          after.toJson(),
        );

        final stale = await rpc
            .call('experience.content.open', <String, Object?>{
              'expectedRevision': before.revision,
              'catalogDigest': before.catalogDigest.value,
              'contentSetDigest': before.contentSetDigest.value,
            });
        expect(stale.error?.code, -32003);
        final opened = ExperienceContentSetOpenResult.fromJson(
          (await rpc.call('experience.content.open', <String, Object?>{
            'expectedRevision': after.revision,
            'catalogDigest': after.catalogDigest.value,
            'contentSetDigest': after.contentSetDigest.value,
          })).result,
        );
        expect(opened.experienceTopologyBundle, isNull);
        expect(opened.scenarioFacetManifest, isNotNull);
      } finally {
        await rpc.close();
      }
    },
  );

  test('Lab-only refresh advances the canonical content generation', () async {
    final rpc = await _RpcClient.connect(application.rpc, studioOrigin.origin);
    try {
      await rpc.initialize();
      final before = ExperienceContentSetDescription.fromJson(
        (await rpc.call(
          'experience.content.describe',
          const <String, Object?>{},
        )).result,
      ).identity;
      expect(before.scenarioLabManifestDigest, isNull);
      final cursor = application.rpc.journal.latestSequence;

      _writeLabAuthoring(temporary, displayName: 'Inspect first scenario');
      final refresh =
          (await rpc.call(
                'workspace.refresh',
                const <String, Object?>{},
              )).result!
              as Map<String, Object?>;

      expect(refresh['changed'], isFalse);
      final after = ExperienceContentSetDescription.fromJson(
        (await rpc.call(
          'experience.content.describe',
          const <String, Object?>{},
        )).result,
      ).identity;
      expect(after.revision, before.revision + 1);
      expect(after.workspaceSnapshotDigest, before.workspaceSnapshotDigest);
      expect(after.scenarioLabManifestDigest, isNotNull);
      expect(after.contentSetDigest, isNot(before.contentSetDigest));

      final events = application.rpc.journal.after(cursor).toList();
      expect(
        events.where((event) => event.method == 'experience.changed'),
        isEmpty,
      );
      final contentEvents = events
          .where((event) => event.method == 'experience.content.changed')
          .toList(growable: false);
      expect(contentEvents, hasLength(1));
      expect(
        ExperienceContentSetDescription.fromJson(
          contentEvents.single.params,
        ).identity.toJson(),
        after.toJson(),
      );

      final opened = ExperienceContentSetOpenResult.fromJson(
        (await rpc.call('experience.content.open', <String, Object?>{
          'expectedRevision': after.revision,
          'catalogDigest': after.catalogDigest.value,
          'contentSetDigest': after.contentSetDigest.value,
        })).result,
      );
      final lab = ScenarioLabManifest.fromJson(
        jsonDecode(
          utf8.decode(
            await _get(
              opened.scenarioLabManifest!.uri,
              origin: studioOrigin.origin.origin,
            ),
          ),
        ),
        catalog: application.workspace!.snapshot.catalog,
      );
      expect(lab.digest, after.scenarioLabManifestDigest);
    } finally {
      await rpc.close();
    }
  });

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
    final minimal = WorkspaceHost.fromResolvedPlan(
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
    expect(capabilities, contains('composition.describe'));
    expect(capabilities, isNot(contains('workspace.describe')));
    expect(capabilities, isNot(contains('workspace.open')));
    expect(capabilities, isNot(contains('workspace.refresh')));
    expect(capabilities, isNot(contains('experience.describe')));
    expect(capabilities, isNot(contains('experience.open')));
    expect(capabilities, isNot(contains('experience.content.describe')));
    expect(capabilities, isNot(contains('experience.content.open')));
    expect(capabilities, isNot(contains('experience.content.describe')));
    expect(capabilities, isNot(contains('experience.content.open')));
    expect(
      capabilities.whereType<String>().where(
        (method) => method.startsWith('quality'),
      ),
      isEmpty,
    );
    expect(minimal.workspace, isNull);
    expect(File(p.join(noConfig.path, 'workspace.yaml')).existsSync(), isFalse);
    expect(
      Directory(p.join(noConfig.path, '.experience')).existsSync(),
      isFalse,
    );
    await rpc.close();
  });

  test('rejects Scenario Lab Evidence policy without the capture provider', () {
    const builtins = BuiltinModuleCatalog();
    final catalog = builtins.create(platform: 'linux-x64');
    final plan = const KitPlanResolver().resolve(
      catalog: catalog,
      profileId: 'gateway-lab',
      overlays: <KitSelection>[
        KitSelection(
          modules: <KitModuleSelection>[
            KitModuleSelection(
              moduleId: ModuleId('gateway.interceptor'),
              enabled: false,
            ),
            KitModuleSelection(
              moduleId: ModuleId('scenario.lab.local'),
              enabled: true,
              settings: <String, Object?>{'evidenceClassification': 'internal'},
            ),
          ],
        ),
      ],
      configurationSchemas: builtins.configurationSchemas,
    );

    expect(
      () => WorkspaceHost.fromResolvedPlan(
        studioOrigin: studioOrigin.origin,
        sessionToken: token,
        workspaceRoot: temporary.path,
        launchProfiles: const <LaunchProfile>[],
        catalog: catalog,
        plan: plan,
      ),
      throwsArgumentError,
    );
  });
}

CatalogManifest _experienceCatalog() {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('experience-workspace');
  final applicationId = ApplicationId('experience-app');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Experience workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Experience app',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('flow'),
        applicationId: applicationId,
        title: 'Flow',
        scenarioIds: <ScenarioId>[ScenarioId('start'), ScenarioId('ready')],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(
        id: ScenarioId('start'),
        applicationId: applicationId,
        title: 'Start',
      ),
      Scenario(
        id: ScenarioId('ready'),
        applicationId: applicationId,
        title: 'Ready',
      ),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('start-ready'),
        journeyId: JourneyId('flow'),
        from: ScenarioId('start'),
        to: ScenarioId('ready'),
      ),
    ],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('ready-web'),
        scenarioId: ScenarioId('ready'),
        targetId: 'chrome',
        launchProfileId: 'ready-web',
      ),
    ],
  );
}

ScenarioLabManifest _experienceLab(CatalogManifest catalog) =>
    ScenarioLabManifest(
      catalog: catalog,
      appAdapterCapabilities: const <CapabilityDescriptor>[],
      controls: const <ScenarioControlDefinition>[],
      operations: const <ScenarioLabOperationDefinition>[],
      scripts: <ScenarioScriptDefinition>[
        ScenarioScriptDefinition(
          id: ScenarioScriptId('inspect-ready'),
          scenarioId: ScenarioId('ready'),
          displayName: 'Inspect ready',
          timeoutMs: 30000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
          steps: <ScenarioScriptStep>[
            ExecutionBindingScenarioScriptStep(
              id: 'launch-ready',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
              bindingId: ScenarioExecutionBindingId('ready-web'),
            ),
          ],
        ),
      ],
      automatedAcceptanceCriteria: const <AutomatedAcceptanceCriterion>[],
      requiredEvidence: const <RequiredEvidenceDefinition>[],
      comparisonBindings: const <ScenarioComparisonBinding>[],
      visualComparisonPolicies: const <VisualComparisonPolicy>[],
      semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
      humanApprovalRequirements: const <HumanApprovalRequirement>[],
      supplementalArtifacts: const <SupplementalArtifactReference>[],
      plans: <ScenarioLabPlan>[
        ScenarioLabPlan(
          scenarioId: ScenarioId('ready'),
          executionBindingIds: <ScenarioExecutionBindingId>[
            ScenarioExecutionBindingId('ready-web'),
          ],
          controlIds: const <ScenarioControlId>[],
          operationIds: const <ScenarioLabOperationId>[],
          scriptIds: <ScenarioScriptId>[ScenarioScriptId('inspect-ready')],
          automatedAcceptanceCriterionIds:
              const <AutomatedAcceptanceCriterionId>[],
          requiredEvidenceIds: const <RequiredEvidenceId>[],
          comparisonBindingIds: const <ScenarioComparisonBindingId>[],
          humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
          supplementalArtifactIds: const <SupplementalArtifactId>[],
        ),
      ],
    );

ExperienceTopologyBundle _experienceBundle(CatalogManifest catalog) {
  final projectionId = ExperienceProjectionId('flow-projection');
  final topology = ExperienceTopologyManifest(
    catalog: catalog,
    boards: <Board>[
      Board(
        id: BoardId('flow-board'),
        applicationId: ApplicationId('experience-app'),
        title: 'Flow',
        projectionIds: <ExperienceProjectionId>[projectionId],
      ),
    ],
    projections: <ExperienceProjection>[
      ExperienceProjection(
        id: projectionId,
        boardId: BoardId('flow-board'),
        applicationId: ApplicationId('experience-app'),
        title: 'Flow',
        kind: ProjectionKind.journey,
        journeyId: JourneyId('flow'),
        nodeInstanceIds: <NodeInstanceId>[
          NodeInstanceId('start-node'),
          NodeInstanceId('ready-node'),
        ],
        edgeInstanceIds: <EdgeInstanceId>[EdgeInstanceId('start-ready-edge')],
      ),
    ],
    nodes: <NodeInstance>[
      NodeInstance(
        id: NodeInstanceId('start-node'),
        projectionId: projectionId,
        scenarioId: ScenarioId('start'),
      ),
      NodeInstance(
        id: NodeInstanceId('ready-node'),
        projectionId: projectionId,
        scenarioId: ScenarioId('ready'),
      ),
    ],
    edges: <EdgeInstance>[
      EdgeInstance(
        id: EdgeInstanceId('start-ready-edge'),
        projectionId: projectionId,
        transitionId: TransitionId('start-ready'),
        fromNodeId: NodeInstanceId('start-node'),
        toNodeId: NodeInstanceId('ready-node'),
      ),
    ],
  );
  return ExperienceTopologyBundle(
    catalog: catalog,
    topology: topology,
    layouts: <ProjectionLayoutManifest>[
      ProjectionLayoutManifest(
        topologyDigest: topology.digest,
        projectionId: projectionId,
        nodeFrames: <ProjectionNodeFrame>[
          ProjectionNodeFrame(
            nodeInstanceId: NodeInstanceId('start-node'),
            x: 0,
            y: 0,
            width: 320,
            height: 640,
          ),
          ProjectionNodeFrame(
            nodeInstanceId: NodeInstanceId('ready-node'),
            x: 480,
            y: 0,
            width: 320,
            height: 640,
          ),
        ],
        groups: const <ProjectionGroup>[],
        lanes: const <ProjectionLane>[],
        annotations: const <ProjectionAnnotation>[],
        camera: ProjectionCamera(x: 400, y: 320, zoom: 0.8),
      ),
    ],
  );
}

MotionManifest _experienceMotion(
  CatalogManifest catalog,
  ExperienceTopologyBundle bundle,
) => MotionManifest(
  catalogDigest: catalog.digest,
  topologyDigest: bundle.topology.digest,
  sequences: <MotionSequenceManifest>[
    MotionSequenceManifest(
      id: 'flow-motion',
      projectionId: ExperienceProjectionId('flow-projection'),
      title: 'Flow motion',
      staticSummary: 'Start is followed by ready.',
      steps: <MotionTransitionStep>[
        MotionTransitionStep(
          id: 'start-to-ready',
          transitionId: TransitionId('start-ready'),
          fromNodeId: NodeInstanceId('start-node'),
          toNodeId: NodeInstanceId('ready-node'),
          startMs: 0,
          fullDurationMs: 420,
          reducedDurationMs: 80,
          easing: MotionEasing.easeInOut,
          observations: <MotionObservation>[
            MotionObservation(
              id: 'ready-visible',
              label: 'Ready is visible',
              atFraction: 1,
              kind: MotionObservationKind.stateVisible,
            ),
          ],
        ),
      ],
    ),
  ],
)..validateAgainst(catalog: catalog, topology: bundle.topology);

ScenarioFacetManifest _experienceFacets(
  CatalogManifest catalog,
) => ScenarioFacetManifest(
  catalog: catalog,
  scenarioKinds: <ScenarioKindDefinition>[
    ScenarioKindDefinition(id: ScenarioKindId('state'), displayName: 'State'),
  ],
  surfaces: <ExperienceSurfaceDefinition>[
    ExperienceSurfaceDefinition(
      id: ExperienceSurfaceId('surface'),
      applicationId: ApplicationId('experience-app'),
      displayName: 'Surface',
    ),
  ],
  states: <ScenarioStateDefinition>[
    ScenarioStateDefinition(
      id: ScenarioStateId('ready'),
      surfaceId: ExperienceSurfaceId('surface'),
      displayName: 'Ready',
    ),
  ],
  ownershipAreas: <OwnershipAreaDefinition>[
    OwnershipAreaDefinition(
      id: OwnershipAreaId('experience'),
      displayName: 'Experience',
    ),
  ],
  tags: <ScenarioTagDefinition>[
    ScenarioTagDefinition(id: ScenarioTagId('flow'), displayName: 'Flow'),
  ],
  components: <ExperienceComponentDefinition>[
    ExperienceComponentDefinition(
      id: ExperienceComponentId('screen'),
      applicationId: ApplicationId('experience-app'),
      displayName: 'Screen',
    ),
  ],
  fixtures: <ScenarioFixtureDefinition>[
    for (final id in const <String>['start', 'ready'])
      ScenarioFixtureDefinition(
        id: ScenarioFixtureId('$id-fixture'),
        applicationId: ApplicationId('experience-app'),
        displayName: '$id fixture',
      ),
  ],
  formFactors: <FormFactorDefinition>[
    FormFactorDefinition(id: FormFactorId('phone'), displayName: 'Phone'),
  ],
  presentationFrames: <PresentationFrameDefinition>[
    PresentationFrameDefinition(
      id: PresentationFrameId('phone-frame'),
      displayName: 'Phone frame',
      kind: PresentationFrameKind.device,
      formFactorId: FormFactorId('phone'),
    ),
  ],
  scenarioFacets: <ScenarioFacet>[
    for (final id in const <String>['start', 'ready'])
      ScenarioFacet(
        scenarioId: ScenarioId(id),
        lifecycle: ScenarioLifecycle.current,
        scenarioKindId: ScenarioKindId('state'),
        surfaceId: ExperienceSurfaceId('surface'),
        stateId: ScenarioStateId('ready'),
        ownershipAreaId: OwnershipAreaId('experience'),
        tagIds: <ScenarioTagId>[ScenarioTagId('flow')],
        componentIds: <ExperienceComponentId>[ExperienceComponentId('screen')],
        fixtureId: ScenarioFixtureId('$id-fixture'),
        renderSource: PreviewDescriptorRenderSource(
          previewId: AutoPreviewId('$id-preview'),
        ),
        presentationFrameIds: <PresentationFrameId>[
          PresentationFrameId('phone-frame'),
        ],
        preferredPresentationFrameId: PresentationFrameId('phone-frame'),
      ),
  ],
);

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
  Directory(p.join(workspace.path, '.experience')).createSync();
  File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample, displayName: Sample workspace}
applications:
  app: {root: ., target: local}
kit: {profile: full-local, modules: {}}
''');
  File(
    p.join(workspace.path, '.experience', 'scenario.yaml'),
  ).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata: {id: first}
spec: {applicationId: app, title: First scenario}
''');
  File(p.join(workspace.path, '.experience', 'journey.yaml')).writeAsStringSync(
    '''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Main flow, scenarioIds: [first]}
''',
  );
  final bindings = Directory(p.join(workspace.path, '.experience', 'bindings'))
    ..createSync();
  File(p.join(bindings.path, 'first-web.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: ScenarioExecutionBinding
metadata: {id: first-web}
spec:
  scenarioId: first
  targetId: sample-web
  launchProfileId: web
''');
  final gateway = Directory(p.join(workspace.path, '.experience', 'gateway'))
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

void _writeExperienceAuthoring(Directory workspace) {
  final content = Directory(p.join(workspace.path, '.experience'));
  File(p.join(content.path, 'second.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata: {id: second}
spec: {applicationId: app, title: Second scenario}
''');
  File(p.join(content.path, 'journey.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Main flow, scenarioIds: [first, second]}
''');
  File(p.join(content.path, 'transition.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Transition
metadata: {id: first-second}
spec: {journeyId: flow, from: first, to: second}
''');
  final topology = Directory(p.join(content.path, 'topology'))..createSync();
  void write(String name, String kind, String id, Map<String, Object?> spec) {
    File(p.join(topology.path, '$name.json')).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'kind': kind,
        'metadata': <String, Object?>{'id': id},
        'spec': spec,
      }),
    );
  }

  write('board', 'Board', 'flow-board', <String, Object?>{
    'applicationId': 'app',
    'title': 'Flow board',
    'projectionIds': <String>['flow-projection'],
  });
  write(
    'projection',
    'ExperienceProjection',
    'flow-projection',
    <String, Object?>{
      'boardId': 'flow-board',
      'applicationId': 'app',
      'title': 'Flow',
      'projectionKind': 'journey',
      'journeyId': 'flow',
      'nodeInstanceIds': <String>['first-node', 'second-node'],
      'edgeInstanceIds': <String>['first-second-edge'],
    },
  );
  write('first-node', 'NodeInstance', 'first-node', <String, Object?>{
    'projectionId': 'flow-projection',
    'scenarioId': 'first',
  });
  write('second-node', 'NodeInstance', 'second-node', <String, Object?>{
    'projectionId': 'flow-projection',
    'scenarioId': 'second',
  });
  write('edge', 'EdgeInstance', 'first-second-edge', <String, Object?>{
    'projectionId': 'flow-projection',
    'transitionId': 'first-second',
    'fromNodeId': 'first-node',
    'toNodeId': 'second-node',
  });
  write('layout', 'ProjectionLayout', 'flow-projection', <String, Object?>{
    'projectionId': 'flow-projection',
    'nodeFrames': <Object?>[
      <String, Object?>{
        'nodeInstanceId': 'first-node',
        'x': 0,
        'y': 0,
        'width': 320,
        'height': 180,
      },
      <String, Object?>{
        'nodeInstanceId': 'second-node',
        'x': 480,
        'y': 0,
        'width': 320,
        'height': 180,
      },
    ],
    'groups': <Object?>[],
    'lanes': <Object?>[],
    'annotations': <Object?>[],
    'camera': <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
  });
}

void _writeFacetAuthoring(Directory workspace, List<String> scenarioIds) {
  final taxonomy = Directory(p.join(workspace.path, '.experience', 'taxonomy'))
    ..createSync();
  void write(String name, String kind, String id, Map<String, Object?> spec) {
    File(p.join(taxonomy.path, '$name.json')).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'schemaVersion': 2,
        'kind': kind,
        'metadata': <String, Object?>{'id': id},
        'spec': spec,
      }),
    );
  }

  write('kind', 'ScenarioKindDefinition', 'state', <String, Object?>{
    'displayName': 'State',
  });
  write('surface', 'ExperienceSurface', 'surface', <String, Object?>{
    'applicationId': 'app',
    'displayName': 'Surface',
  });
  write('state', 'ScenarioState', 'ready', <String, Object?>{
    'surfaceId': 'surface',
    'displayName': 'Ready',
  });
  write('owner', 'OwnershipArea', 'experience', <String, Object?>{
    'displayName': 'Experience',
  });
  write('tag', 'ScenarioTag', 'flow', <String, Object?>{'displayName': 'Flow'});
  write('component', 'ExperienceComponent', 'screen', <String, Object?>{
    'applicationId': 'app',
    'displayName': 'Screen',
  });
  write('form-factor', 'FormFactor', 'phone', <String, Object?>{
    'displayName': 'Phone',
  });
  write(
    'presentation-frame',
    'PresentationFrame',
    'phone-frame',
    <String, Object?>{
      'displayName': 'Phone frame',
      'frameKind': 'device',
      'formFactorId': 'phone',
    },
  );
  for (final scenarioId in scenarioIds) {
    write(
      'fixture-$scenarioId',
      'ScenarioFixture',
      '$scenarioId-fixture',
      <String, Object?>{
        'applicationId': 'app',
        'displayName': '$scenarioId fixture',
      },
    );
    write('facet-$scenarioId', 'ScenarioFacet', scenarioId, <String, Object?>{
      'scenarioId': scenarioId,
      'lifecycle': 'current',
      'scenarioKindId': 'state',
      'surfaceId': 'surface',
      'stateId': 'ready',
      'ownershipAreaId': 'experience',
      'tagIds': <String>['flow'],
      'componentIds': <String>['screen'],
      'fixtureId': '$scenarioId-fixture',
      'renderSource': <String, Object?>{
        'kind': 'previewDescriptor',
        'previewId': '$scenarioId-preview',
      },
      'presentationFrameIds': <String>['phone-frame'],
      'preferredPresentationFrameId': 'phone-frame',
    });
  }
}

void _writeLabAuthoring(Directory workspace, {required String displayName}) {
  final lab = Directory(p.join(workspace.path, '.experience', 'lab'))
    ..createSync();
  File(p.join(lab.path, 'script.json')).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'kind': 'ScenarioScript',
      'metadata': <String, Object?>{'id': 'inspect-first'},
      'spec': <String, Object?>{
        'scenarioId': 'first',
        'displayName': displayName,
        'timeoutMs': 30000,
        'timeoutOutcome': 'fail',
        'cancellationPolicy': 'immediate',
        'steps': <Object?>[
          <String, Object?>{
            'id': 'launch-first',
            'kind': 'executionBinding',
            'bindingId': 'first-web',
            'timeoutMs': 10000,
            'timeoutOutcome': 'fail',
          },
        ],
      },
    }),
  );
  File(p.join(lab.path, 'plan.json')).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'kind': 'ScenarioLabPlan',
      'metadata': <String, Object?>{'id': 'first'},
      'spec': <String, Object?>{
        'scenarioId': 'first',
        'executionBindingIds': <String>['first-web'],
        'controlIds': <String>[],
        'operationIds': <String>[],
        'scriptIds': <String>['inspect-first'],
        'automatedAcceptanceCriterionIds': <String>[],
        'requiredEvidenceIds': <String>[],
        'comparisonBindingIds': <String>[],
        'humanApprovalRequirementIds': <String>[],
        'supplementalArtifactIds': <String>[],
      },
    }),
  );
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
    'workspace.initialize',
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
        workspace.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}
