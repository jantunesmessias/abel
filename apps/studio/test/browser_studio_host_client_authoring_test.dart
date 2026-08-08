@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/authoring/studio_experience_authoring_transport.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/host/studio_host_client_web.dart';
import 'package:test/test.dart';

void main() {
  late BrowserStudioHostClient client;
  late AuthoringSubjectRef subject;
  late ExperienceAuthoringDescription description;
  var harnessInstalled = false;

  setUp(() {
    subject = AuthoringSubjectRef(
      workspaceId: WorkspaceId('workspace'),
      applicationId: ApplicationId('app'),
      projectionId: ExperienceProjectionId('projection'),
    );
    final capability = AuthoringCapability(
      capability: ModuleCapabilityRef(id: 'experience.authoring', version: 1),
      moduleId: ModuleId('authoring.local'),
      resolvedPlanDigest: Digest.semantic('resolved-plan'),
      subject: subject,
      effects: AuthoringActionEffect.values.toSet(),
      operations: AuthoringOperation.values.toSet(),
    );
    description = ExperienceAuthoringDescription(
      requestId: AuthoringRequestId('describe-browser'),
      subject: subject,
      availability: ExperienceAuthoringAvailability.policyDenied,
      capability: capability,
      allowedEffects: const <AuthoringActionEffect>{
        AuthoringActionEffect.query,
      },
      allowedOperations: AuthoringOperation.values
          .where(
            (operation) =>
                authoringEffectFor(operation) == AuthoringActionEffect.query,
          )
          .toSet(),
      currentContentSetDigest: Digest.semantic('content-set'),
      currentSourceDigest: Digest.semantic('source'),
      currentTopologyDigest: Digest.semantic('topology'),
      currentLayoutDigest: Digest.semantic('layout'),
    );
    final grantError = ExperienceAuthoringError(
      code: ExperienceAuthoringErrorCode.policyDenied,
      requestId: AuthoringRequestId('grant-browser'),
      subject: subject,
      operation: AuthoringOperation.openDraft,
    );
    final capabilities = <String>{
      'workspace.describe',
      'workspace.open',
      ...ExperienceAuthoringRpcMethod.values,
    };
    final manifest = EffectiveKitManifest(
      resolvedPlanDigest: Digest.semantic('resolved-plan'),
      modules: const <EffectiveModuleState>[],
      commands: const <String>[],
      rpcMethods: capabilities.toList(),
      studioContributions: const <String>['studio.authoring'],
      generatedAt: DateTime.utc(2026, 8, 17),
    );
    _installHarness(<String, Object?>{
      'bootstrap': <String, Object?>{
        'schemaVersion': 1,
        'protocolVersion': 1,
        'hostOrigin': 'http://127.0.0.1:7368',
        'rpcPath': '/rpc',
        'sessionToken': 'session-token-00000000000000000002',
        'effectiveKitManifest': manifest.toJson(),
      },
      'initialize': <String, Object?>{
        'protocolVersion': 1,
        'capabilities': capabilities.toList()..sort(),
      },
      'description': description.toJson(),
      'grantError': grantError.toJson(),
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

  test(
    'production client implements and decodes the exact authoring facade',
    () async {
      expect(client, isA<StudioHostExperienceAuthoringClient>());
      final request = ExperienceAuthoringDescribeRequest(
        requestId: description.requestId,
        subject: subject,
      );
      final result = await client.describeExperienceAuthoring(request);
      expect(result.digest, description.digest);
      expect(
        _requestMethods(),
        containsAllInOrder(<String>[
          'workspace.initialize',
          ExperienceAuthoringRpcMethod.describe,
        ]),
      );
    },
  );

  test('typed authoring errors remain bound to the exact request', () async {
    final intent = AuthoringGrantRequest(
      requestId: AuthoringRequestId('grant-browser'),
      capabilityDigest: description.capability!.digest,
      subject: subject,
      effect: AuthoringActionEffect.authoring,
      operation: AuthoringOperation.openDraft,
      expectedDigest: description.currentContentSetDigest,
      expectedSourceDigest: description.currentSourceDigest!,
      payloadDigest: Digest.semantic('open-payload'),
    );
    await expectLater(
      client.requestExperienceAuthoringGrant(intent),
      throwsA(
        isA<StudioExperienceAuthoringFailure>().having(
          (failure) => failure.error.code,
          'code',
          ExperienceAuthoringErrorCode.policyDenied,
        ),
      ),
    );
  });
}

List<String> _requestMethods() =>
    (jsonDecode(_harnessRequestMethods().toDart) as List<Object?>)
        .cast<String>();

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
        case '${ExperienceAuthoringRpcMethod.describe}':
          respond(this, request, config.description);
          break;
        case '${ExperienceAuthoringRpcMethod.requestGrant}':
          queueMicrotask(() => this.serverMessage({
            jsonrpc: '2.0',
            id: request.id,
            error: {
              code: ${ExperienceAuthoringError.jsonRpcCode},
              message: 'Experience Authoring request rejected',
              data: config.grantError,
            },
          }));
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
  globalThis.__authoringHarnessRequestMethods = () =>
    JSON.stringify(state.requests.map((request) => request.method));
  globalThis.__authoringHarnessUninstall = () => {
    globalThis.fetch = originalFetch;
    globalThis.WebSocket = OriginalWebSocket;
    delete globalThis.__authoringHarnessRequestMethods;
    delete globalThis.__authoringHarnessUninstall;
  };
})();
''';
  globalContext.callMethod('eval'.toJS, source.toJS);
}

@JS('__authoringHarnessRequestMethods')
external JSString _harnessRequestMethods();

@JS('__authoringHarnessUninstall')
external void _uninstallHarness();
