import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

import 'support/temporary_preview_consumer.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef';
  final studioOrigin = Uri.parse('http://127.0.0.1:43991');

  test(
    'workspace.refresh reinspects AutoPreview when manifests are unchanged',
    () async {
      final consumer = TemporaryPreviewConsumer.create();
      addTearDown(consumer.dispose);
      final application = WorkspaceHost.fromResolvedPlan(
        studioOrigin: studioOrigin,
        sessionToken: token,
        workspaceRoot: consumer.root.path,
        launchProfiles: const <LaunchProfile>[],
        catalog: _moduleCatalog(),
        plan: _previewPlan(),
        workspaceCatalog: consumer.catalog(),
      );
      addTearDown(application.close);
      await application.start();
      final rpc = await _RpcClient.connect(application.rpc, studioOrigin);
      addTearDown(rpc.close);
      expect((await rpc.initialize()).isSuccess, isTrue);

      final before = application.workspace!.snapshot;
      expect(
        before.variantManifest.variants.map((variant) => variant.id.value),
        isNot(contains('tablet.light.en-us')),
      );
      consumer.writeLibrary('refresh_probe.dart', _additionalPreviewSource);
      final cursor = application.rpc.journal.latestSequence;

      final response = await rpc.call(
        'workspace.refresh',
        const <String, Object?>{},
      );

      expect(response.isSuccess, isTrue);
      final payload = response.result! as Map<String, Object?>;
      final after = application.workspace!.snapshot;
      expect(after.catalog.digest, before.catalog.digest);
      expect(
        after.variantManifest.variants.map((variant) => variant.id.value),
        contains('tablet.light.en-us'),
        reason:
            'workspace.refresh must re-run AutoPreview inspection even when '
            'Catalog, Topology and Facets are byte-identical',
      );
      expect(after.revision, before.revision + 1);
      expect(payload['changed'], isTrue);
      expect(
        _contentEventsAfter(application, cursor).map((event) => event.method),
        <String>['workspace.changed', 'experience.content.changed'],
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'Lab-only refresh advances content while preserving workspace payload',
    () async {
      final workspace = Directory.systemTemp.createTempSync(
        'workspace-lab-content-refresh-',
      );
      addTearDown(() {
        if (workspace.existsSync()) workspace.deleteSync(recursive: true);
      });
      _writeCatalogWorkspace(workspace);
      _writeLabAuthoring(workspace, displayName: 'Inspect ready state');
      final application = WorkspaceHost.fromResolvedPlan(
        studioOrigin: studioOrigin,
        sessionToken: token,
        workspaceRoot: workspace.path,
        launchProfiles: const <LaunchProfile>[],
        catalog: _moduleCatalog(),
        plan: _catalogOnlyPlan(),
      );
      addTearDown(application.close);
      await application.start();
      final rpc = await _RpcClient.connect(application.rpc, studioOrigin);
      addTearDown(rpc.close);
      expect((await rpc.initialize()).isSuccess, isTrue);

      final beforeWorkspace =
          (await rpc.call(
                'workspace.describe',
                const <String, Object?>{},
              )).result!
              as Map<String, Object?>;
      final beforeContent = ExperienceContentSetDescription.fromJson(
        (await rpc.call(
          'experience.content.describe',
          const <String, Object?>{},
        )).result,
      );
      final beforeLab = application.workspace!.scenarioLabManifest!.digest;
      final cursor = application.rpc.journal.latestSequence;
      _writeLabAuthoring(
        workspace,
        displayName: 'Inspect the current ready state',
      );

      final response = await rpc.call(
        'workspace.refresh',
        const <String, Object?>{},
      );

      expect(response.isSuccess, isTrue);
      expect(response.result, <String, Object?>{
        ...beforeWorkspace,
        'changed': false,
      }, reason: 'Lab content does not change the WorkspaceSnapshot response');
      expect(
        application.workspace!.scenarioLabManifest!.digest,
        isNot(beforeLab),
      );
      final afterContent = ExperienceContentSetDescription.fromJson(
        (await rpc.call(
          'experience.content.describe',
          const <String, Object?>{},
        )).result,
      );
      expect(
        afterContent.identity.revision,
        beforeContent.identity.revision + 1,
      );
      expect(
        afterContent.identity.workspaceSnapshotDigest,
        beforeContent.identity.workspaceSnapshotDigest,
      );
      expect(
        afterContent.identity.contentSetDigest,
        isNot(beforeContent.identity.contentSetDigest),
      );
      final events = _contentEventsAfter(application, cursor);
      expect(events.map((event) => event.method), <String>[
        'experience.content.changed',
      ]);
      expect(
        ExperienceContentSetDescription.fromJson(events.single.params).toJson(),
        afterContent.toJson(),
      );
    },
  );

  test('no-op and failed refresh publish no content change event', () async {
    final workspace = Directory.systemTemp.createTempSync(
      'workspace-noop-content-refresh-',
    );
    addTearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });
    _writeCatalogWorkspace(workspace);
    _writeLabAuthoring(workspace, displayName: 'Inspect ready state');
    final application = WorkspaceHost.fromResolvedPlan(
      studioOrigin: studioOrigin,
      sessionToken: token,
      workspaceRoot: workspace.path,
      launchProfiles: const <LaunchProfile>[],
      catalog: _moduleCatalog(),
      plan: _catalogOnlyPlan(),
    );
    addTearDown(application.close);
    await application.start();
    final rpc = await _RpcClient.connect(application.rpc, studioOrigin);
    addTearDown(rpc.close);
    expect((await rpc.initialize()).isSuccess, isTrue);

    final beforeWorkspace = application.workspace!.describe();
    final beforeContent = application.workspace!.describeContentSet().toJson();
    final beforeContentRevision = application.workspace!.contentRevision;
    final beforeLab = application.workspace!.scenarioLabManifest!.digest;
    final cursor = application.rpc.journal.latestSequence;

    final noOp = await rpc.call('workspace.refresh', const <String, Object?>{});
    expect(noOp.isSuccess, isTrue);
    expect(application.rpc.journal.after(cursor), isEmpty);

    _writeLabAuthoring(
      workspace,
      displayName: 'Invalid ready state',
      timeoutMs: 0,
    );
    final failed = await rpc.call(
      'workspace.refresh',
      const <String, Object?>{},
    );
    expect(failed.isSuccess, isFalse);
    expect(application.rpc.journal.after(cursor), isEmpty);
    expect(application.workspace!.describe(), beforeWorkspace);
    expect(application.workspace!.describeContentSet().toJson(), beforeContent);
    expect(application.workspace!.contentRevision, beforeContentRevision);
    expect(application.workspace!.scenarioLabManifest!.digest, beforeLab);
  });
}

const Set<String> _contentChangeMethods = <String>{
  'workspace.changed',
  'experience.changed',
  'experience.content.changed',
};

List<HostEvent> _contentEventsAfter(WorkspaceHost application, int cursor) =>
    application.rpc.journal
        .after(cursor)
        .where((event) => _contentChangeMethods.contains(event.method))
        .toList(growable: false);

ModuleCatalog _moduleCatalog() =>
    const BuiltinModuleCatalog().create(platform: 'linux-x64');

ResolvedKitPlan _previewPlan() {
  const builtins = BuiltinModuleCatalog();
  final catalog = builtins.create(platform: 'linux-x64');
  return const KitPlanResolver().resolve(
    catalog: catalog,
    profileId: 'journey-preview',
    configurationSchemas: builtins.configurationSchemas,
  );
}

ResolvedKitPlan _catalogOnlyPlan() {
  const builtins = BuiltinModuleCatalog();
  final catalog = builtins.create(platform: 'linux-x64');
  return const KitPlanResolver().resolve(
    catalog: catalog,
    profileId: 'gateway-lab-headless',
    overlays: <KitSelection>[
      KitSelection(
        modules: <KitModuleSelection>[
          KitModuleSelection(
            moduleId: ModuleId('gateway.interceptor'),
            enabled: false,
          ),
          KitModuleSelection(
            moduleId: ModuleId('sessions.local'),
            enabled: false,
          ),
        ],
      ),
    ],
    configurationSchemas: builtins.configurationSchemas,
  );
}

void _writeCatalogWorkspace(Directory workspace) {
  final content = Directory(p.join(workspace.path, '.experience'))
    ..createSync();
  File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample, displayName: Sample workspace}
applications:
  app: {root: ., target: web}
kit: {profile: full-local, modules: {}}
''');
  File(p.join(content.path, 'scenario.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: Scenario
metadata: {id: ready}
spec: {applicationId: app, title: Ready state}
''');
  File(p.join(content.path, 'binding.yaml')).writeAsStringSync('''
schemaVersion: 1
kind: ScenarioExecutionBinding
metadata: {id: ready-web}
spec:
  scenarioId: ready
  targetId: chrome
  launchProfileId: app-web
''');
}

void _writeLabAuthoring(
  Directory workspace, {
  required String displayName,
  int timeoutMs = 30000,
}) {
  final lab = Directory(p.join(workspace.path, '.experience', 'lab'))
    ..createSync();
  File(p.join(lab.path, 'script.json')).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'kind': 'ScenarioScript',
      'metadata': <String, Object?>{'id': 'inspect-ready'},
      'spec': <String, Object?>{
        'scenarioId': 'ready',
        'displayName': displayName,
        'timeoutMs': timeoutMs,
        'timeoutOutcome': 'fail',
        'cancellationPolicy': 'immediate',
        'steps': <Object?>[
          <String, Object?>{
            'id': 'launch-ready',
            'kind': 'executionBinding',
            'bindingId': 'ready-web',
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
      'metadata': <String, Object?>{'id': 'ready'},
      'spec': <String, Object?>{
        'scenarioId': 'ready',
        'executionBindingIds': <String>['ready-web'],
        'controlIds': <String>[],
        'operationIds': <String>[],
        'scriptIds': <String>['inspect-ready'],
        'automatedAcceptanceCriterionIds': <String>[],
        'requiredEvidenceIds': <String>[],
        'comparisonBindingIds': <String>[],
        'humanApprovalRequirementIds': <String>[],
        'supplementalArtifactIds': <String>[],
      },
    }),
  );
}

final class _RpcClient {
  _RpcClient(this.channel, this.iterator, this.sessionToken);

  final IOWebSocketChannel channel;
  final StreamIterator<Object?> iterator;
  final String sessionToken;
  var _nextId = 1;

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
    final id = 'request-${_nextId++}';
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

const String _additionalPreviewSource = r'''
import 'package:flutter_preview/flutter_preview.dart';
import 'package:flutter/material.dart';

@AutoPreview(
  id: 'fixture.dashboard.ready.refresh-probe',
  scenarioId: 'dashboard-ready',
  variantId: 'tablet.light.en-us',
  size: Size(820, 1180),
  devicePixelRatio: 2,
  localeTag: 'en-US',
  brightness: Brightness.light,
)
Widget refreshedDashboardPreview() => const SizedBox();
''';
