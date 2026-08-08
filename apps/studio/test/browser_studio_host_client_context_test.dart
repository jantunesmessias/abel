@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/host/studio_host_client_web.dart';
import 'package:test/test.dart';

void main() {
  late BrowserStudioHostClient client;
  late ContextBuilderDescription description;
  late ContextBuildRequest request;
  late ContextBuildResult result;
  var harnessInstalled = false;

  setUp(() {
    final digest = Digest.semantic('context-content');
    final budgets = ContextBudgets(
      categories: <ContextCategory, ContextCategoryBudget>{
        for (final category in ContextCategory.values)
          category: ContextCategoryBudget(maxItems: 8, maxBytes: 4096),
      },
    );
    final selection = ContextSelection(
      boardId: BoardId('board'),
      projectionId: ExperienceProjectionId('projection'),
      journeyId: JourneyId('journey'),
      scenarioId: ScenarioId('ready'),
    );
    const inclusion = ContextInclusion(
      sources: true,
      images: true,
      evidence: true,
      history: true,
      changes: false,
    );
    description = ContextBuilderDescription(
      contentSetDigest: digest,
      supportedCategories: ContextCategory.values.toSet(),
      maximumBudgets: budgets,
    );
    request = ContextBuildRequest(
      expectedContentSetDigest: digest,
      selection: selection,
      inclusion: inclusion,
      budgets: budgets,
    );
    result = ContextBuildResult(
      bundle: ExperienceContextBundle(
        contentSetDigest: digest,
        selection: selection,
        inclusion: inclusion,
        requestedBudgets: budgets,
        effectiveBudgets: budgets,
        items: const <ContextItem>[],
        usage: <ContextCategory, ContextUsage>{
          for (final category in ContextCategory.values)
            category: ContextUsage(items: 0, bytes: 0),
        },
        omissions: <ContextOmission>[
          for (final category in ContextCategory.values)
            ContextOmission(
              category: category,
              subject: category.name,
              reason: ContextOmissionReason.unavailable,
            ),
        ],
      ),
    );
    const capabilities = <String>{
      'workspace.describe',
      'workspace.open',
      'context.describe',
      'context.build',
    };
    final manifest = EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic('resolved-plan'),
      modules: const <EffectiveModuleState>[],
      commands: const <String>[],
      rpcMethods: capabilities.toList(),
      studioContributions: const <String>['studio.context'],
      generatedAt: DateTime.utc(2026, 8, 17),
    );
    _installHarness(<String, Object?>{
      'bootstrap': <String, Object?>{
        'schemaVersion': 1,
        'protocolVersion': 1,
        'hostOrigin': 'http://127.0.0.1:7367',
        'rpcPath': '/rpc',
        'sessionToken': 'session-token-00000000000000000006',
        'effectiveKitManifest': manifest.toJson(),
      },
      'initialize': <String, Object?>{
        'protocolVersion': 1,
        'capabilities': capabilities.toList()..sort(),
      },
      'description': description.toJson(),
      'result': result.toJson(),
    });
    harnessInstalled = true;
    client = BrowserStudioHostClient();
  });

  tearDown(() async {
    if (!harnessInstalled) return;
    try {
      await client.close();
    } finally {
      _uninstallHarness();
      harnessInstalled = false;
    }
  });

  test('production client exposes the closed Context Builder facade', () async {
    expect(client, isA<StudioHostContextBuilderClient>());
    final decodedDescription = await client.describeContextBuilder();
    final decodedResult = await client.buildContext(request);

    expect(decodedDescription.toJson(), description.toJson());
    expect(decodedResult.bundle.digest, result.bundle.digest);
    final requests = _requests();
    expect(
      requests.map((entry) => entry['method']),
      containsAllInOrder(<String>[
        'workspace.initialize',
        'context.describe',
        'context.build',
      ]),
    );
    final wire = jsonEncode(requests);
    expect(wire, isNot(contains('contentRoot')));
    expect(wire, isNot(contains('authorityId')));
    expect(wire, isNot(contains('/home/')));
  });
}

List<Map<String, Object?>> _requests() =>
    (jsonDecode(_harnessRequests().toDart) as List<Object?>)
        .cast<Map<String, Object?>>();

void _installHarness(Map<String, Object?> config) {
  final source =
      '''
(() => {
  const config = ${jsonEncode(config)};
  const originalFetch = globalThis.fetch;
  const OriginalWebSocket = globalThis.WebSocket;
  const state = {requests: []};

  const respond = (socket, request, result) => {
    queueMicrotask(() => socket.serverMessage({
      jsonrpc: '2.0',
      id: request.id,
      result,
    }));
  };

  class FakeWebSocket extends EventTarget {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;

    constructor(url) {
      super();
      this.url = String(url);
      this.readyState = FakeWebSocket.CONNECTING;
      this.protocol = '';
      this.extensions = '';
      this.binaryType = 'blob';
      this.bufferedAmount = 0;
      queueMicrotask(() => {
        if (this.readyState !== FakeWebSocket.CONNECTING) return;
        this.readyState = FakeWebSocket.OPEN;
        this.dispatchEvent(new Event('open'));
      });
    }

    send(data) {
      const request = JSON.parse(String(data));
      state.requests.push(request);
      switch (request.method) {
        case 'workspace.initialize':
          respond(this, request, config.initialize);
          break;
        case 'context.describe':
          respond(this, request, config.description);
          break;
        case 'context.build':
          respond(this, request, config.result);
          break;
        default:
          queueMicrotask(() => this.serverMessage({
            jsonrpc: '2.0',
            id: request.id,
            error: {code: -32601, message: 'unsupported test method'},
          }));
      }
    }

    close(code = 1000, reason = '') {
      if (this.readyState === FakeWebSocket.CLOSED) return;
      this.readyState = FakeWebSocket.CLOSED;
      this.dispatchEvent(new CloseEvent('close', {
        code,
        reason,
        wasClean: true,
      }));
    }

    serverMessage(message) {
      this.dispatchEvent(new MessageEvent('message', {
        data: JSON.stringify(message),
      }));
    }
  }

  globalThis.fetch = async () => new Response(
    JSON.stringify(config.bootstrap),
    {status: 200, headers: {'content-type': 'application/json'}},
  );
  globalThis.WebSocket = FakeWebSocket;
  globalThis.__contextHarnessRequests = () => JSON.stringify(state.requests);
  globalThis.__contextHarnessUninstall = () => {
    globalThis.fetch = originalFetch;
    globalThis.WebSocket = OriginalWebSocket;
    delete globalThis.__contextHarnessRequests;
    delete globalThis.__contextHarnessUninstall;
  };
})();
''';
  globalContext.callMethod('eval'.toJS, source.toJS);
}

@JS('__contextHarnessRequests')
external JSString _harnessRequests();

@JS('__contextHarnessUninstall')
external void _uninstallHarness();
