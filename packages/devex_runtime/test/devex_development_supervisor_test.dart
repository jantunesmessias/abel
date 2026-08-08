import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('devex-supervisor-');
  });

  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test(
    'supervises Host and Studio with same-origin bootstrap and cleanup',
    () async {
      _writeCatalog(temporary);
      final studioAssets = Directory(p.join(temporary.path, 'studio'))
        ..createSync();
      File(
        p.join(studioAssets.path, 'index.html'),
      ).writeAsStringSync('<!doctype html><title>DevEx Studio</title>');
      const builtins = BuiltinModuleCatalog();
      final moduleCatalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: moduleCatalog,
        profileId: 'journey-preview',
        configurationSchemas: builtins.configurationSchemas,
      );
      final supervisor = DevExDevelopmentSupervisor(
        workspaceRoot: temporary.path,
        catalog: moduleCatalog,
        plan: plan,
        studioAssetRoot: studioAssets.path,
      );
      addTearDown(supervisor.close);

      final runtime = await supervisor.start();

      expect(runtime.profileId, 'journey-preview');
      expect(runtime.planDigest, plan.digest);
      expect(runtime.toJson(), isNot(contains('sessionToken')));
      expect(await _status(runtime.hostOrigin.replace(path: '/health')), 200);
      expect(
        await _status(
          runtime.hostOrigin.replace(path: '/devex/bootstrap.json'),
        ),
        HttpStatus.notFound,
      );
      expect(
        await _status(runtime.studioOrigin!.replace(path: '/health')),
        200,
      );
      expect(
        await _status(runtime.studioOrigin!.replace(path: '/index.html')),
        200,
      );
      final deepLink = await _get(
        runtime.studioOrigin!.replace(path: '/journeys/sample'),
      );
      expect(deepLink.statusCode, HttpStatus.ok);
      expect(utf8.decode(deepLink.bytes), contains('DevEx Studio'));
      final contentSecurityPolicy = deepLink.headers.value(
        'content-security-policy',
      );
      expect(contentSecurityPolicy, contains("script-src 'self'"));
      expect(contentSecurityPolicy, isNot(contains("'unsafe-inline'")));
      expect(contentSecurityPolicy, isNot(contains("'wasm-unsafe-eval'")));
      expect(contentSecurityPolicy, isNot(contains('https:')));
      expect(contentSecurityPolicy, contains(runtime.hostOrigin.origin));
      expect(
        contentSecurityPolicy,
        contains('ws://${runtime.hostOrigin.authority}'),
      );
      expect(
        await _status(runtime.studioOrigin!.replace(path: '/missing-asset.js')),
        HttpStatus.notFound,
      );

      final deniedBootstrap = await _get(
        runtime.studioOrigin!.replace(path: '/devex/bootstrap.json'),
      );
      expect(deniedBootstrap.statusCode, HttpStatus.forbidden);
      final bootstrapResponse = await _get(
        runtime.studioOrigin!.replace(path: '/devex/bootstrap.json'),
        headers: const <String, String>{'sec-fetch-site': 'same-origin'},
      );
      expect(bootstrapResponse.statusCode, HttpStatus.ok);
      expect(bootstrapResponse.headers.value('cache-control'), 'no-store');
      final bootstrap =
          jsonDecode(utf8.decode(bootstrapResponse.bytes))
              as Map<String, Object?>;
      expect(bootstrap['hostOrigin'], runtime.hostOrigin.toString());
      expect(
        (bootstrap['sessionToken']! as String).length,
        greaterThanOrEqualTo(32),
      );
      expect(
        EffectiveKitManifest.fromJson(bootstrap['effectiveKitManifest']).digest,
        runtime.effectiveKitManifest.digest,
      );

      final rpcUri = runtime.hostOrigin.replace(scheme: 'ws', path: '/rpc');
      final channel = IOWebSocketChannel.connect(
        rpcUri,
        headers: <String, String>{'Origin': runtime.studioOrigin!.origin},
      );
      await channel.ready;
      channel.sink.add(
        JsonRpcRequest(
          method: 'devex.initialize',
          id: 'initialize',
          params: <String, Object?>{
            'protocolVersion': 1,
            'sessionToken': bootstrap['sessionToken'],
          },
        ).encode(),
      );
      final initialized =
          const JsonRpcCodec().decode(await channel.stream.first as String)
              as JsonRpcResponse;
      expect(initialized.isSuccess, isTrue);
      expect(
        (initialized.result! as Map<String, Object?>)['capabilities'],
        contains('devex.workspace.open'),
      );
      await channel.sink.close();

      final hostOrigin = runtime.hostOrigin;
      final studioOrigin = runtime.studioOrigin!;
      await supervisor.close();
      expect(supervisor.isRunning, isFalse);
      await expectLater(_status(hostOrigin), throwsA(isA<SocketException>()));
      await expectLater(_status(studioOrigin), throwsA(isA<SocketException>()));
    },
  );

  test(
    'serves an origin-bound bootstrap for an external hot-reload Studio',
    () async {
      _writeCatalog(temporary);
      const builtins = BuiltinModuleCatalog();
      final moduleCatalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: moduleCatalog,
        profileId: 'journey-preview',
        configurationSchemas: builtins.configurationSchemas,
      );
      final externalStudioOrigin = Uri.parse('http://127.0.0.1:36409');
      final supervisor = DevExDevelopmentSupervisor(
        workspaceRoot: temporary.path,
        catalog: moduleCatalog,
        plan: plan,
        studioDevelopmentOrigin: externalStudioOrigin,
      );
      addTearDown(supervisor.close);

      final runtime = await supervisor.start();

      expect(runtime.studioOrigin, externalStudioOrigin);
      expect(
        runtime.studioBootstrapUri,
        runtime.hostOrigin.replace(path: '/devex/bootstrap.json'),
      );
      expect(runtime.toJson(), isNot(contains('sessionToken')));
      final denied = await _get(runtime.studioBootstrapUri!);
      expect(denied.statusCode, HttpStatus.forbidden);
      final attacker = await _get(
        runtime.studioBootstrapUri!,
        headers: const <String, String>{'Origin': 'http://127.0.0.1:9999'},
      );
      expect(attacker.statusCode, HttpStatus.forbidden);
      final queried = await _get(
        runtime.studioBootstrapUri!.replace(query: 'token=forbidden'),
        headers: <String, String>{'Origin': externalStudioOrigin.origin},
      );
      expect(queried.statusCode, HttpStatus.forbidden);

      final accepted = await _get(
        runtime.studioBootstrapUri!,
        headers: <String, String>{'Origin': externalStudioOrigin.origin},
      );
      expect(accepted.statusCode, HttpStatus.ok);
      expect(
        accepted.headers.value('access-control-allow-origin'),
        externalStudioOrigin.origin,
      );
      expect(accepted.headers.value('cache-control'), 'no-store');
      final bootstrap =
          jsonDecode(utf8.decode(accepted.bytes)) as Map<String, Object?>;
      expect(bootstrap['hostOrigin'], runtime.hostOrigin.toString());
      expect(
        (bootstrap['sessionToken']! as String).length,
        greaterThanOrEqualTo(32),
      );
      expect(
        EffectiveKitManifest.fromJson(bootstrap['effectiveKitManifest']).digest,
        runtime.effectiveKitManifest.digest,
      );

      final hostOrigin = runtime.hostOrigin;
      await supervisor.close();
      await expectLater(_status(hostOrigin), throwsA(isA<SocketException>()));
    },
  );

  test('does not touch Studio assets when studio.shell is disabled', () async {
    const builtins = BuiltinModuleCatalog();
    final moduleCatalog = builtins.create(platform: 'linux-x64');
    final plan = const KitPlanResolver().resolve(
      catalog: moduleCatalog,
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
    final supervisor = DevExDevelopmentSupervisor(
      workspaceRoot: temporary.path,
      catalog: moduleCatalog,
      plan: plan,
      headlessStudioOrigin: Uri.parse('http://127.0.0.1:9999'),
    );

    final runtime = await supervisor.start();

    expect(runtime.studioOrigin, isNull);
    expect(runtime.effectiveKitManifest.studioContributions, isEmpty);
    expect(Directory(p.join(temporary.path, 'studio')).existsSync(), isFalse);
    await supervisor.close();
  });

  test(
    'starts and stops Host plus Studio for twenty cycles without listeners',
    () async {
      _writeCatalog(temporary);
      final studioAssets = Directory(p.join(temporary.path, 'studio'))
        ..createSync();
      File(
        p.join(studioAssets.path, 'index.html'),
      ).writeAsStringSync('<!doctype html><title>DevEx Studio</title>');
      const builtins = BuiltinModuleCatalog();
      final moduleCatalog = builtins.create(platform: 'linux-x64');
      final plan = const KitPlanResolver().resolve(
        catalog: moduleCatalog,
        profileId: 'journey-preview',
        configurationSchemas: builtins.configurationSchemas,
      );

      for (var cycle = 0; cycle < 20; cycle += 1) {
        final supervisor = DevExDevelopmentSupervisor(
          workspaceRoot: temporary.path,
          catalog: moduleCatalog,
          plan: plan,
          studioAssetRoot: studioAssets.path,
        );
        final runtime = await supervisor.start();
        final hostOrigin = runtime.hostOrigin;
        final studioOrigin = runtime.studioOrigin!;
        expect(await _status(hostOrigin.replace(path: '/health')), 200);
        expect(await _status(studioOrigin.replace(path: '/health')), 200);

        await supervisor.close();

        expect(supervisor.isRunning, isFalse, reason: 'cycle $cycle');
        await expectLater(
          _status(hostOrigin),
          throwsA(isA<SocketException>()),
          reason: 'Host listener survived cycle $cycle',
        );
        await expectLater(
          _status(studioOrigin),
          throwsA(isA<SocketException>()),
          reason: 'Studio listener survived cycle $cycle',
        );
      }
    },
  );
}

Future<int> _status(Uri uri) async => (await _get(uri)).statusCode;

Future<_HttpResult> _get(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 500);
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (result, chunk) => result..addAll(chunk),
    );
    return _HttpResult(response.statusCode, response.headers, bytes);
  } finally {
    client.close(force: true);
  }
}

final class _HttpResult {
  const _HttpResult(this.statusCode, this.headers, this.bytes);

  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;
}

void _writeCatalog(Directory workspace) {
  Directory(p.join(workspace.path, '.devex')).createSync();
  File(p.join(workspace.path, 'devex.yaml')).writeAsStringSync('''
schemaVersion: 1
content: {root: .devex}
workspace: {id: sample, displayName: Sample}
applications:
  app: {root: ., target: local}
''');
  File(p.join(workspace.path, '.devex', 'scenario.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata: {id: first}
spec: {applicationId: app, title: First}
''');
  File(p.join(workspace.path, '.devex', 'journey.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Journey
metadata: {id: flow}
spec: {applicationId: app, title: Flow, scenarioIds: [first]}
''');
}
