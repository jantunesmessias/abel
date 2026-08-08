import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:workspace_cli/workspace_cli.dart';

const List<String> _packagedModuleIds = <String>[
  'artifact-store.local',
  'authoring.local',
  'automation.mcp',
  'capture.app-adapter',
  'catalog',
  'context.builder.local',
  'evidence.android',
  'evidence.auto-preview',
  'evidence.tests',
  'gateway.interceptor',
  'hosted.collaboration',
  'motion.local',
  'plugins.external',
  'quality.decisions.local',
  'release.local',
  'remote.execution',
  'scenario.lab.local',
  'sessions.local',
  'source.impact',
  'studio.authoring',
  'studio.context',
  'studio.inventory',
  'studio.journey-map',
  'studio.lab',
  'studio.motion',
  'studio.quality',
  'studio.shell',
  'target.android',
];

void main() {
  test('version has human and stable machine representations', () async {
    final human = await WorkspaceCli().run(<String>['version']);
    final machine = await WorkspaceCli().run(<String>['--json', 'version']);

    expect(human.exitCode, 0);
    expect(human.stdout, 'workspace 0.1.0-dev\n');
    expect(machine.exitCode, 0);
    final payload = jsonDecode(machine.stdout) as Map<String, Object?>;
    expect(payload['schemaVersion'], 1);
    expect(payload['command'], 'version');
    expect(payload['ok'], isTrue);
  });

  test('unknown invocation uses the stable usage exit code', () async {
    final result = await WorkspaceCli().run(<String>['unknown']);

    expect(result.exitCode, 2);
    expect(result.stderr, contains('Usage:'));
  });

  test('module bootstrap commands work without a workspace', () async {
    final empty = Directory.systemTemp.createTempSync(
      'workspace-modules-empty-',
    );
    addTearDown(() => empty.deleteSync(recursive: true));
    final cli = WorkspaceCli(workspaceDirectory: empty.path);

    final result = await cli.run(<String>[
      '--json',
      'modules',
      'list',
      '--profile',
      'journey-preview',
    ]);

    expect(result.exitCode, 0, reason: result.stderr);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    final value = payload['result']! as Map<String, Object?>;
    expect(value['profileId'], 'journey-preview');
    expect(value['workspaceConfigured'], isFalse);
    expect(value['planDigest'], startsWith('sha256:'));
    final modules = value['modules']! as List<Object?>;
    expect(
      modules
          .whereType<Map<String, Object?>>()
          .map((module) => module['id'])
          .toList(growable: false),
      _packagedModuleIds,
    );
    final enabled = modules
        .whereType<Map<String, Object?>>()
        .where((module) => module['enabled'] == true)
        .map((module) => module['id'])
        .toSet();
    expect(enabled, <Object?>{
      'artifact-store.local',
      'catalog',
      'evidence.auto-preview',
      'studio.inventory',
      'studio.journey-map',
      'studio.lab',
      'studio.quality',
      'studio.shell',
    });
  });

  test('module doctor reports the bounded AutoPreview claims', () async {
    final empty = Directory.systemTemp.createTempSync(
      'workspace-doctor-preview-',
    );
    addTearDown(() => empty.deleteSync(recursive: true));

    final result = await WorkspaceCli(workspaceDirectory: empty.path).run(
      <String>['--json', 'modules', 'doctor', '--profile', 'journey-preview'],
    );

    expect(result.exitCode, 0, reason: result.stderr);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    final value = payload['result']! as Map<String, Object?>;
    final limitations = value['runtimeLimitations']! as List<Object?>;
    expect(limitations, hasLength(5));
    expect(
      limitations.cast<Map<String, Object?>>().map((item) => item['code']),
      containsAll(<String>[
        'preview.fidelity.structural',
        'preview.detector.workspace-regression',
        'preview.export.runner-owned',
        'preview.sandbox.host-dependent',
        'preview.native.not-proved',
      ]),
    );
  });

  test('module explain reflects v2 profile without implying Android', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-modules-v2-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    Directory(p.join(workspace.path, '.experience')).createSync();
    File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications: {}
kit:
  profile: journey-preview
  modules: {}
''');
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);

    final result = await cli.run(<String>[
      '--json',
      'modules',
      'explain',
      '--module',
      'target.android',
    ]);

    expect(result.exitCode, 0, reason: result.stderr);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    final value = payload['result']! as Map<String, Object?>;
    final module = value['module']! as Map<String, Object?>;
    expect(value['profileId'], 'journey-preview');
    expect(value['workspaceConfigured'], isTrue);
    expect(module['packaged'], isTrue);
    expect(module['enabled'], isFalse);
    expect(module['ready'], isFalse);
    expect(module['authorized'], isFalse);
  });

  test('resolved profile removes disabled commands before dispatch', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-command-surface-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    Directory(p.join(workspace.path, '.experience')).createSync();
    File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications: {}
kit:
  profile: journey-preview
  modules: {}
''');
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);

    final android = await cli.run(<String>[
      '--json',
      'target',
      'android',
      'discover',
    ]);
    final gateway = await cli.run(<String>['--json', 'gateway', 'doctor']);
    final tests = await cli.run(<String>[
      '--json',
      'evidence',
      'collect-tests',
    ]);
    final previews = await cli.run(<String>[
      '--json',
      'evidence',
      'collect-previews',
    ]);
    final disabledCommands = <List<String>>[
      <String>['capture'],
      <String>['session', 'start'],
      <String>['source', 'inspect'],
      <String>['plugin', 'list'],
      <String>['mcp', 'serve'],
      <String>['auth', 'status'],
      <String>['workspace', 'pull'],
      <String>['publish'],
      <String>['release', 'bundle'],
    ];

    expect(android.exitCode, 2);
    expect(gateway.exitCode, 2);
    expect(tests.exitCode, 2);
    expect(previews.exitCode, 2);
    expect(previews.stderr, contains('Option application is mandatory'));
    for (final invocation in disabledCommands) {
      final disabled = await cli.run(<String>['--json', ...invocation]);
      expect(disabled.exitCode, 2, reason: invocation.join(' '));
      expect(disabled.stderr, contains('Usage:'), reason: invocation.join(' '));
    }
  });

  test(
    'validate and explain are side-effect free while compile is atomic',
    () async {
      final workspace = Directory.systemTemp.createTempSync('workspace-cli-');
      addTearDown(() => workspace.deleteSync(recursive: true));
      Directory(p.join(workspace.path, '.experience')).createSync();
      File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample, displayName: Sample}
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
spec: {applicationId: app, title: First}
''');
      File(
        p.join(workspace.path, '.experience', 'journey.yaml'),
      ).writeAsStringSync('''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Flow, scenarioIds: [first]}
''');
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);

      final validate = await cli.run(<String>['--json', 'validate']);
      final explain = await cli.run(<String>['--json', 'explain']);
      expect(validate.exitCode, 0);
      expect(explain.exitCode, 0);
      expect(
        Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
        isFalse,
      );

      final compile = await cli.run(<String>['--json', 'compile']);
      expect(compile.exitCode, 0, reason: compile.stderr);
      final payload = jsonDecode(compile.stdout) as Map<String, Object?>;
      expect(payload['ok'], isTrue);
      expect(
        File(
          p.join(
            workspace.path,
            '.dart_tool',
            'workspace',
            'full-local',
            'catalog',
            'manifest.json',
          ),
        ).existsSync(),
        isTrue,
      );
      final dev = await cli.run(<String>['--json', 'dev', '--plan-only']);
      expect(dev.exitCode, 0);
      final devPayload = jsonDecode(dev.stdout) as Map<String, Object?>;
      final devResult = devPayload['result']! as Map<String, Object?>;
      final host = devResult['host']! as Map<String, Object?>;
      final environment = host['environment']! as Map<String, Object?>;
      final planPath = environment['RESOLVED_COMPOSITION_PLAN']! as String;
      final plan = ResolvedKitPlan.fromJson(
        jsonDecode(File(planPath).readAsStringSync()),
      );
      expect(
        environment['RESOLVED_COMPOSITION_PLAN_DIGEST'],
        plan.digest.value,
      );
      expect(
        (jsonDecode(dev.stdout) as Map<String, Object?>)['command'],
        'dev',
      );
    },
  );

  test(
    'dev supervises a real Host and packaged Studio until cleanup',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-cli-dev-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      _writeCatalog(workspace);
      final assets = Directory(p.join(workspace.path, 'studio-assets'))
        ..createSync();
      File(
        p.join(assets.path, 'index.html'),
      ).writeAsStringSync('<!doctype html><title>Abel Studio</title>');
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);
      addTearDown(cli.closeDevelopmentRuns);

      final result = await cli.run(<String>[
        '--json',
        'dev',
        '--profile',
        'journey-preview',
        '--no-open',
        '--studio-assets',
        assets.path,
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, isNot(contains('sessionToken')));
      final payload = jsonDecode(result.stdout) as Map<String, Object?>;
      final value = payload['result']! as Map<String, Object?>;
      expect(value['status'], 'ready');
      expect(value['profileId'], 'journey-preview');
      final hostOrigin = Uri.parse(value['hostOrigin']! as String);
      final studioOrigin = Uri.parse(value['studioOrigin']! as String);
      expect(await _httpStatus(hostOrigin.replace(path: '/health')), 200);
      expect(await _httpStatus(studioOrigin.replace(path: '/health')), 200);
      expect(
        Directory(
          p.join(workspace.path, '.dart_tool', 'workspace', 'run'),
        ).existsSync(),
        isFalse,
      );

      await cli.closeDevelopmentRuns();

      await expectLater(
        _httpStatus(hostOrigin),
        throwsA(isA<SocketException>()),
      );
      await expectLater(
        _httpStatus(studioOrigin),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test(
    'dev attaches Host bootstrap to an external hot-reload Studio',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-cli-hot-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      _writeCatalog(workspace);
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);
      addTearDown(cli.closeDevelopmentRuns);
      const studioOrigin = 'http://127.0.0.1:36409';

      final result = await cli.run(<String>[
        '--json',
        'dev',
        '--profile',
        'journey-preview',
        '--no-open',
        '--studio-dev-origin',
        studioOrigin,
      ]);

      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, isNot(contains('sessionToken')));
      final payload = jsonDecode(result.stdout) as Map<String, Object?>;
      final value = payload['result']! as Map<String, Object?>;
      expect(value['studioOrigin'], studioOrigin);
      final hostOrigin = Uri.parse(value['hostOrigin']! as String);
      expect(
        value['studioBootstrapUri'],
        hostOrigin.replace(path: '/studio/bootstrap.json').toString(),
      );
      expect(await _httpStatus(hostOrigin.replace(path: '/health')), 200);

      await cli.closeDevelopmentRuns();
      await expectLater(
        _httpStatus(hostOrigin),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test('doctor probes the real local toolchain', () async {
    final result = await WorkspaceCli().run(<String>['--json', 'doctor']);

    expect(result.exitCode, 0, reason: result.stderr);
    expect((jsonDecode(result.stdout) as Map<String, Object?>)['ok'], isTrue);
  });

  test('capture and release build produce a verified local bundle', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-release-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    _writeCatalog(workspace);
    final captureFile = File(p.join(workspace.path, 'capture.png'))
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
        ),
      );
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);

    final premature = await cli.run(<String>['--json', 'release', 'build']);
    expect(premature.exitCode, 3);
    expect(
      (jsonDecode(premature.stderr)
          as Map<String, Object?>)['effectiveContext'],
      containsPair('freshness', 'missing'),
    );

    final capture = await cli.run(<String>[
      '--json',
      'capture',
      '--input',
      captureFile.path,
      '--launch-profile',
      'sample-web',
      '--target',
      'local-chrome',
      '--renderer',
      'canvaskit',
    ]);
    expect(capture.exitCode, 0, reason: capture.stderr);
    final captureOutput = jsonDecode(capture.stdout) as Map<String, Object?>;
    final captureResult = captureOutput['result']! as Map<String, Object?>;
    expect(captureResult['freshness'], 'fresh');
    expect(captureResult['reproductionClaimComplete'], isFalse);

    final release = await cli.run(<String>['--json', 'release', 'build']);
    expect(release.exitCode, 0, reason: release.stderr);
    final releaseOutput = jsonDecode(release.stdout) as Map<String, Object?>;
    final releaseResult = releaseOutput['result']! as Map<String, Object?>;
    final directory = releaseResult['directory']! as String;
    final verified = LocalEvidenceRepository(
      store: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
    ).verifyBundle(directory);
    expect(verified.digest.value, releaseResult['bundleDigest']);
    expect(verified.release.digest.value, releaseResult['releaseDigest']);
  });

  test('session start negotiates and invokes a running Host', () async {
    const token = '0123456789abcdef0123456789abcdef';
    final temporary = Directory.systemTemp.createTempSync(
      'workspace-cli-session-',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    _writeCatalog(temporary);
    final processScript = File(p.join(temporary.path, 'target.dart'))
      ..writeAsStringSync('''
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9000);
  await for (final request in server) {
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  }
}
''');
    final application = WorkspaceHost(
      studioOrigin: Uri.parse('http://127.0.0.1:8765'),
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
    );
    await application.start();
    addTearDown(application.close);

    final result = await WorkspaceCli().run(<String>[
      '--json',
      'session',
      'start',
      '--host',
      application.rpc.httpUri.toString(),
      '--token',
      token,
      '--studio-origin',
      'http://127.0.0.1:8765',
      '--launch-profile',
      'web',
      '--target-origin',
      'http://127.0.0.1:9000',
    ]);

    expect(result.exitCode, 0, reason: result.stderr);
    final output = jsonDecode(result.stdout) as Map<String, Object?>;
    expect((output['result']! as Map<String, Object?>)['state'], 'ready');
  });

  test('Gateway CLI drives the isolated Host sidecar lifecycle', () async {
    const token = 'abcdef0123456789abcdef0123456789';
    const studioOrigin = 'http://127.0.0.1:8766';
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-gateway-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    _writeCatalog(workspace);
    final processScript = File(p.join(workspace.path, 'target.dart'))
      ..writeAsStringSync('''
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 9001);
  await for (final request in server) {
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  }
}
''');
    final fixtureBytes = utf8.encode('{"gateway":"cli"}');
    _writeGatewayAuthoring(workspace, fixtureBytes);
    final application = WorkspaceHost(
      studioOrigin: Uri.parse(studioOrigin),
      sessionToken: token,
      workspaceRoot: workspace.path,
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
        'apps/gateway_sidecar/bin/gateway_sidecar.dart',
      ],
      gatewaySidecarWorkingDirectory: _repositoryRoot(),
    );
    await application.start();
    addTearDown(application.close);
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);
    final connection = <String>[
      '--host',
      application.rpc.httpUri.toString(),
      '--token',
      token,
      '--studio-origin',
      studioOrigin,
    ];

    final session = await cli.run(<String>[
      '--json',
      'session',
      'start',
      ...connection,
      '--launch-profile',
      'web',
      '--target-origin',
      'http://127.0.0.1:9001',
    ]);
    expect(session.exitCode, 0, reason: session.stderr);
    final ownerSessionId =
        ((jsonDecode(session.stdout) as Map<String, Object?>)['result']!
                as Map<String, Object?>)['id']!
            as String;
    final run = await cli.run(<String>[
      '--json',
      'gateway',
      'run',
      ...connection,
      '--owner-session',
      ownerSessionId,
      'default',
    ]);
    expect(run.exitCode, 0, reason: run.stderr);
    final runResult =
        (jsonDecode(run.stdout) as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    final gatewaySessionId = runResult['id']! as String;
    final gateway = <String>[
      ...connection,
      '--gateway-session',
      gatewaySessionId,
    ];

    final status = await cli.run(<String>[
      '--json',
      'gateway',
      'status',
      ...gateway,
    ]);
    expect(status.exitCode, 0, reason: status.stderr);
    expect(
      ((jsonDecode(status.stdout) as Map<String, Object?>)['result']!
          as Map<String, Object?>)['state'],
      'running',
    );
    final verify = await cli.run(<String>[
      '--json',
      'gateway',
      'verify',
      ...gateway,
      '--path',
      '/value',
    ]);
    expect(verify.exitCode, 0, reason: verify.stderr);
    final verifyResult =
        (jsonDecode(verify.stdout) as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    final verifiedArtifact = Digest(
      verifyResult['responseBodyArtifactDigest']! as String,
    );
    expect(
      FileSystemWorkspaceStore(
        workspaceRoot: workspace.path,
      ).readBlob(verifiedArtifact),
      fixtureBytes,
    );
    expect(verifyResult, isNot(contains('responseBodyBase64')));
    final traffic = await cli.run(<String>[
      '--json',
      'gateway',
      'traffic',
      ...gateway,
    ]);
    expect(traffic.exitCode, 0, reason: traffic.stderr);
    expect(
      (jsonDecode(traffic.stdout) as Map<String, Object?>)['result'],
      hasLength(1),
    );
    final reset = await cli.run(<String>[
      '--json',
      'gateway',
      'reset',
      ...gateway,
    ]);
    expect(reset.exitCode, 0, reason: reset.stderr);
    final apply = await cli.run(<String>[
      '--json',
      'gateway',
      'apply-preset',
      ...gateway,
      'default',
    ]);
    expect(apply.exitCode, 0, reason: apply.stderr);
    final stop = await cli.run(<String>[
      '--json',
      'gateway',
      'stop',
      ...gateway,
    ]);
    expect(stop.exitCode, 0, reason: stop.stderr);
    expect(application.gateways!.activeCount, 0);
  });

  test('Gateway doctor and sync use redacted local provider config', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-sync-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    _writeCatalog(workspace);
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    upstream.listen((request) async {
      expect(request.uri.path, '/remote/config');
      expect(request.uri.queryParameters['channel'], 'test');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"schemaVersion":1,"items":[{"id":"feature-a","enabled":true}]}',
      );
      await request.response.close();
    });
    File(p.join(workspace.path, 'workspace.local.yaml')).writeAsStringSync('''
schemaVersion: 1
gateway:
  upstreams:
    integration:
      baseUrl: http://127.0.0.1:${upstream.port}/remote
      allowedHost: 127.0.0.1
      environment: development
      allowPrivateAddresses: true
  providers:
    features:
      upstreamProfileId: integration
      requestPath: /config
      query: {channel: test}
''');
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);

    final doctor = await cli.run(<String>[
      '--json',
      'gateway',
      'doctor',
      '--provider',
      'features',
    ]);
    expect(doctor.exitCode, 0, reason: doctor.stderr);
    expect(doctor.stdout, isNot(contains(upstream.port.toString())));
    expect(doctor.stdout, isNot(contains('baseUrl')));
    final doctorResult =
        (jsonDecode(doctor.stdout) as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    expect(doctorResult['ready'], isTrue);

    final sync = await cli.run(<String>[
      '--json',
      'gateway',
      'sync',
      '--provider',
      'features',
    ]);
    expect(sync.exitCode, 0, reason: sync.stderr);
    expect(sync.stdout, isNot(contains('feature-a')));
    final syncResult =
        (jsonDecode(sync.stdout) as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    expect((syncResult['observed']! as Map<String, Object?>)['state'], 'ready');
    expect(syncResult['activeDocumentDigest'], isNotNull);
    expect(
      File(
        p.join(
          workspace.path,
          '.dart_tool',
          'workspace',
          'full-local',
          'gateway',
          'providers',
          'features',
          'state.json',
        ),
      ).existsSync(),
      isTrue,
    );
  });

  test('init and detach are preview-first and ownership-aware', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-cli-adoption-',
    );
    addTearDown(() => workspace.deleteSync(recursive: true));
    final pubspec = File(p.join(workspace.path, 'pubspec.yaml'))
      ..writeAsStringSync('name: friction_consumer\n');
    final lock = File(p.join(workspace.path, 'pubspec.lock'))
      ..writeAsStringSync('packages: {}\n');
    final pubspecDigest = Digest.bytes(pubspec.readAsBytesSync());
    final lockDigest = Digest.bytes(lock.readAsBytesSync());
    final cli = WorkspaceCli(workspaceDirectory: workspace.path);

    final preview = await cli.run(<String>[
      '--json',
      'init',
      '--workspace-id',
      'friction',
      '--display-name',
      'Friction',
    ]);
    expect(preview.exitCode, 0, reason: preview.stderr);
    expect(
      File(p.join(workspace.path, 'workspace.yaml')).existsSync(),
      isFalse,
    );
    expect(
      Directory(p.join(workspace.path, '.dart_tool')).existsSync(),
      isFalse,
    );

    final applied = await cli.run(<String>[
      '--json',
      'init',
      '--apply',
      '--workspace-id',
      'friction',
      '--display-name',
      'Friction',
    ]);
    expect(applied.exitCode, 0, reason: applied.stderr);
    expect(File(p.join(workspace.path, 'workspace.yaml')).existsSync(), isTrue);
    expect(Digest.bytes(pubspec.readAsBytesSync()), pubspecDigest);
    expect(Digest.bytes(lock.readAsBytesSync()), lockDigest);

    final readme = File(p.join(workspace.path, '.experience', 'README.md'))
      ..writeAsStringSync('\nconsumer note\n', mode: FileMode.append);
    final detachPreview = await cli.run(<String>[
      '--json',
      'detach',
      '--dry-run',
    ]);
    expect(detachPreview.exitCode, 0, reason: detachPreview.stderr);
    expect(readme.existsSync(), isTrue);

    final partial = await cli.run(<String>['--json', 'detach', '--apply']);
    expect(partial.exitCode, 0, reason: partial.stderr);
    final partialReport =
        ((jsonDecode(partial.stdout) as Map<String, Object?>)['result']!
                as Map<String, Object?>)['report']!
            as Map<String, Object?>;
    expect(partialReport['adopted'], isTrue);
    expect(readme.existsSync(), isTrue);
    expect(
      File(p.join(workspace.path, 'workspace.yaml')).existsSync(),
      isFalse,
    );

    readme.deleteSync();
    final detached = await cli.run(<String>['--json', 'detach', '--apply']);
    expect(detached.exitCode, 0, reason: detached.stderr);
    expect(
      (((jsonDecode(detached.stdout) as Map<String, Object?>)['result']!
              as Map<String, Object?>)['report']!
          as Map<String, Object?>)['adopted'],
      isFalse,
    );
    expect(Digest.bytes(pubspec.readAsBytesSync()), pubspecDigest);
    expect(Digest.bytes(lock.readAsBytesSync()), lockDigest);
  });

  test(
    'evidence collect-tests ingests the real Dart machine reporter',
    () async {
      final result = await WorkspaceCli(workspaceDirectory: _repositoryRoot())
          .run(<String>[
            '--json',
            'evidence',
            'collect-tests',
            '--target',
            'libs/testing_support/test/testkit_test.dart',
            '--timeout-seconds',
            '30',
          ]);

      expect(result.exitCode, 0, reason: result.stderr);
      final summary =
          (jsonDecode(result.stdout) as Map<String, Object?>)['result']!
              as Map<String, Object?>;
      expect(summary['providerId'], 'dart-test-json-v1');
      expect(summary['success'], isTrue);
      expect(summary['total'], 1);
    },
  );

  test(
    'evidence comparisons apply explicit visual and semantic policies',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-cli-comparison-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      final png = File(p.join(workspace.path, 'capture.png'))
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
          ),
        );
      File(p.join(workspace.path, 'visual-policy.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'kind': 'VisualComparisonPolicy',
          'id': 'visual-exact-v1',
          'maxChannelDelta': 0,
          'maxChangedPixelRatio': 0,
        }),
      );
      List<int> semantics(String digest) => utf8.encode(
        '${const JcsCanonicalizer().canonicalize(<String, Object?>{
          'schemaVersion': 1,
          'kind': 'AndroidSemanticsSnapshot',
          'privacy': 'hashedTextV1',
          'nodes': <Object?>[
            <String, Object?>{'sequence': 0, 'textDigest': digest},
          ],
        })}\n',
      );
      File(
        p.join(workspace.path, 'expected.json'),
      ).writeAsBytesSync(semantics(Digest.semantic('expected').value));
      File(
        p.join(workspace.path, 'actual.json'),
      ).writeAsBytesSync(semantics(Digest.semantic('actual').value));
      File(p.join(workspace.path, 'semantic-policy.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'kind': 'SemanticComparisonPolicy',
          'id': 'semantic-exact-v1',
          'maxChangedNodes': 0,
          'ignoreBounds': true,
        }),
      );
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);

      final stored = FileSystemWorkspaceStore(workspaceRoot: workspace.path)
          .withExclusiveLock(
            () => FileSystemWorkspaceStore(
              workspaceRoot: workspace.path,
            ).putBlob(png.readAsBytesSync()),
          );
      final exported = await cli.run(<String>[
        '--json',
        'evidence',
        'export-artifact',
        '--digest',
        stored.value,
        '--output',
        'exported.png',
      ]);
      expect(exported.exitCode, 0, reason: exported.stderr);
      expect(
        File(p.join(workspace.path, 'exported.png')).readAsBytesSync(),
        png.readAsBytesSync(),
      );

      final visual = await cli.run(<String>[
        '--json',
        'evidence',
        'compare-visual',
        '--expected',
        png.path,
        '--actual',
        png.path,
        '--policy',
        'visual-policy.json',
        '--output',
        'visual-report.json',
      ]);
      expect(visual.exitCode, 0, reason: visual.stderr);
      expect(
        EvidenceComparisonReport.fromJson(
          jsonDecode(
            File(
              p.join(workspace.path, 'visual-report.json'),
            ).readAsStringSync(),
          ),
        ).passed,
        isTrue,
      );

      final semantic = await cli.run(<String>[
        '--json',
        'evidence',
        'compare-semantics',
        '--expected',
        'expected.json',
        '--actual',
        'actual.json',
        '--policy',
        'semantic-policy.json',
      ]);
      expect(semantic.exitCode, 4);
      final denied = jsonDecode(semantic.stderr) as Map<String, Object?>;
      final result = denied['result']! as Map<String, Object?>;
      final report = EvidenceComparisonReport.fromJson(result['report']);
      expect(report.passed, isFalse);
      expect(report.changedUnits, 1);
    },
  );

  test(
    'CLI composes source impact, context, bundle verification, and seal',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-cli-v2-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      _writeCatalog(workspace);
      final source = File(p.join(workspace.path, 'source.txt'))
        ..writeAsStringSync('before');
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);

      final base = await cli.run(<String>[
        '--json',
        'source',
        'inspect',
        '--output',
        'base.json',
      ]);
      expect(base.exitCode, 0, reason: base.stderr);
      source.writeAsStringSync('after');
      final current = await cli.run(<String>[
        '--json',
        'source',
        'inspect',
        '--output',
        'current.json',
      ]);
      expect(current.exitCode, 0, reason: current.stderr);
      final diff = await cli.run(<String>[
        '--json',
        'source',
        'diff',
        '--base',
        'base.json',
        '--current',
        'current.json',
        '--output',
        'changes.json',
      ]);
      expect(diff.exitCode, 0, reason: diff.stderr);
      File(p.join(workspace.path, 'bindings.json')).writeAsStringSync(
        jsonEncode(<String, Object?>{
          'bindings': <Object?>[
            <String, Object?>{
              'id': 'source',
              'subject': 'scenario-source',
              'repositoryId': 'workspace',
              'pathGlobs': <String>['source.txt'],
              'dependsOn': <String>[],
            },
            <String, Object?>{
              'id': 'docs',
              'subject': 'scenario-docs',
              'repositoryId': 'workspace',
              'pathGlobs': <String>['docs/**'],
              'dependsOn': <String>[],
            },
          ],
        }),
      );
      final plan = await cli.run(<String>[
        '--json',
        'plan',
        '--change-set',
        'changes.json',
        '--bindings',
        'bindings.json',
        '--output',
        'impact.json',
      ]);
      expect(plan.exitCode, 0, reason: plan.stderr);
      expect(
        (jsonDecode(plan.stdout) as Map<String, Object?>)['result'],
        isA<Map<String, Object?>>(),
      );
      final allowed = await cli.run(<String>[
        '--json',
        'gate',
        '--impact-plan',
        'impact.json',
        '--subject',
        'scenario-docs',
      ]);
      expect(allowed.exitCode, 0, reason: allowed.stderr);
      final denied = await cli.run(<String>[
        '--json',
        'gate',
        '--impact-plan',
        'impact.json',
        '--subject',
        'scenario-source',
      ]);
      expect(denied.exitCode, 4);

      final context = await cli.run(<String>[
        '--json',
        'context',
        'export',
        '--snapshot',
        'current.json',
        '--path',
        'source.txt',
        '--output',
        'context.json',
      ]);
      expect(context.exitCode, 0, reason: context.stderr);
      expect(
        ContextBundle.fromJson(
          jsonDecode(
            File(p.join(workspace.path, 'context.json')).readAsStringSync(),
          ),
        ).files.single.content,
        'after',
      );

      final captureFile = File(p.join(workspace.path, 'capture.png'))
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
          ),
        );
      final capture = await cli.run(<String>[
        '--json',
        'capture',
        '--input',
        captureFile.path,
        '--source-snapshot',
        'current.json',
      ]);
      expect(capture.exitCode, 0, reason: capture.stderr);
      final release = await cli.run(<String>['--json', 'release', 'build']);
      expect(release.exitCode, 0, reason: release.stderr);
      final releaseResult =
          (jsonDecode(release.stdout) as Map<String, Object?>)['result']!
              as Map<String, Object?>;
      final archive = await cli.run(<String>[
        '--json',
        'release',
        'bundle',
        '--directory',
        releaseResult['directory']! as String,
        '--output',
        'release.evidence.zip',
      ]);
      expect(archive.exitCode, 0, reason: archive.stderr);
      final verify = await cli.run(<String>[
        '--json',
        'release',
        'verify-bundle',
        '--bundle',
        'release.evidence.zip',
      ]);
      expect(verify.exitCode, 0, reason: verify.stderr);
      final seal = await cli.run(<String>[
        '--json',
        'release',
        'seal',
        '--bundle',
        'release.evidence.zip',
        '--impact-plan',
        'impact.json',
        '--snapshot',
        'current.json',
        '--output',
        'seal.json',
      ]);
      expect(seal.exitCode, 0, reason: seal.stderr);
      expect(
        ReleaseSeal.fromJson(
          jsonDecode(
            File(p.join(workspace.path, 'seal.json')).readAsStringSync(),
          ),
        ).bundleArchiveDigest.value,
        contains('sha256:'),
      );
    },
  );

  test(
    'hosted auth status and workspace link never persist bearer tokens',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'control-plane-cli-',
      );
      addTearDown(() => workspace.deleteSync(recursive: true));
      final credential = File(p.join(workspace.path, 'hosted-auth.json'));
      final cli = WorkspaceCli(workspaceDirectory: workspace.path);

      final missing = await cli.run(<String>[
        '--json',
        'auth',
        'status',
        '--credential-file',
        credential.path,
      ]);
      expect(missing.exitCode, 3);

      credential.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schemaVersion': 1,
          'hostedUrl': 'http://127.0.0.1:43123',
          'tenantId': 'tenant-a',
          'issuer': 'https://issuer.example.test',
          'subject': 'subject-a',
          'accessToken': 'secret-bearer-token',
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
        }),
      );
      if (!Platform.isWindows) {
        expect(
          Process.runSync('chmod', <String>['600', credential.path]).exitCode,
          0,
        );
      }
      final status = await cli.run(<String>[
        '--json',
        'auth',
        'status',
        '--credential-file',
        credential.path,
      ]);
      expect(status.exitCode, 0, reason: status.stderr);
      expect(status.stdout, isNot(contains('secret-bearer-token')));

      final link = await cli.run(<String>[
        '--json',
        'workspace',
        'link',
        '--hosted-url',
        'http://127.0.0.1:43123',
        '--tenant',
        'tenant-a',
        '--workspace-id',
        'workspace-a',
      ]);
      expect(link.exitCode, 0, reason: link.stderr);
      final linkText = File(
        p.join(workspace.path, '.experience', 'hosted-link.json'),
      ).readAsStringSync();
      expect(linkText, contains('workspace-a'));
      expect(linkText, isNot(contains('secret-bearer-token')));

      final logout = await cli.run(<String>[
        '--json',
        'auth',
        'logout',
        '--credential-file',
        credential.path,
      ]);
      expect(logout.exitCode, 0);
      expect(credential.existsSync(), isFalse);
    },
  );
}

void _writeCatalog(Directory workspace) {
  Directory(p.join(workspace.path, '.experience')).createSync();
  File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample, displayName: Sample}
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
spec: {applicationId: app, title: First}
''');
  File(p.join(workspace.path, '.experience', 'journey.yaml')).writeAsStringSync(
    '''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Flow, scenarioIds: [first]}
''',
  );
}

Future<int> _httpStatus(Uri uri) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 500);
  try {
    final response = await (await client.getUrl(uri)).close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void _writeGatewayAuthoring(Directory workspace, List<int> fixtureBytes) {
  final root = Directory(p.join(workspace.path, '.experience', 'gateway'))
    ..createSync();
  final fixtures = Directory(p.join(root.path, 'fixtures'))..createSync();
  File(p.join(root.path, 'scope.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayScope
metadata: {id: sample}
spec: {displayName: Sample, routeIds: [value]}
''');
  File(p.join(root.path, 'preset.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayPreset
metadata: {id: default}
spec:
  scopeId: sample
  description: Default
  routeIds: [value]
''');
  File(p.join(root.path, 'route.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayRoute
metadata: {id: value}
spec:
  scopeId: sample
  method: GET
  pathTemplate: /value
  appliesTo: [default]
  policy: localOnly
  fixtureId: value-fixture
''');
  File(p.join(root.path, 'fixture.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: GatewayFixture
metadata: {id: value-fixture}
spec:
  status: 200
  headers: {content-type: application/json}
  bodyFile: fixtures/value.body
  mediaType: application/json
''');
  File(p.join(fixtures.path, 'value.body')).writeAsBytesSync(fixtureBytes);
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
