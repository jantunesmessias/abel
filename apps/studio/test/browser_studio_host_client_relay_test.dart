@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/host/studio_host_client_web.dart';
import 'package:studio/src/lab/studio_lab_relay_transport.dart';
import 'package:studio/src/lab/studio_scenario_lab_run_transport.dart';
import 'package:test/test.dart';

import 'support/scenario_lab_fixture.dart';

void main() {
  late BrowserStudioHostClient client;
  late ScenarioLabRunSnapshot running;
  late ScenarioLabRelayResultSubmission submission;
  late ScenarioLabRelayResultAcknowledgement expectedAcknowledgement;
  var harnessInstalled = false;

  setUp(() async {
    final fixture = ScenarioLabTestFixture();
    running = fixture.runningSnapshot();
    final binding = StudioLabRelayRunBinding.fromSnapshot(
      snapshot: running,
      catalog: fixture.catalog,
      manifest: fixture.manifest,
    );
    final descriptor = ScenarioLabRelayTargetDescriptor(
      runId: binding.runId,
      targetId: binding.targetId,
      launchProfileId: binding.launchProfileId,
      launchAttemptId: TargetLaunchAttemptId('launch-attempt-0001'),
      origin: Uri.parse('http://127.0.0.1:8181'),
      nonce: AppAdapterRelayNonce('relay-nonce-000000000001'),
    );
    final result = ResetAppAdapterRelayResult(
      runId: binding.runId,
      commandId: ScenarioLabCommandId('command-reset-0001'),
      sequence: 1,
      nonce: descriptor.nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(false),
    );
    submission = ScenarioLabRelayResultSubmission(
      descriptorDigest: descriptor.digest,
      result: result,
    );
    expectedAcknowledgement = ScenarioLabRelayResultAcknowledgement(
      runId: binding.runId,
      descriptorDigest: descriptor.digest,
      acceptedResultDigest: result.resultDigest,
    );
    final observation = ScenarioLabRunObservation(
      runId: running.runId,
      disposition: ScenarioLabRunDisposition.active,
      afterSequence: running.sequence,
      current: running,
      observations: const <ScenarioLabRunSnapshot>[],
      hasMore: false,
    );
    final capabilities = <String>{
      'workspace.describe',
      'workspace.open',
      ...studioLabRelayRpcMethods,
      ...studioScenarioLabRunRpcMethods,
    };
    final effectiveKit = fixture
        .workspaceSnapshot(rpcMethods: capabilities)
        .effectiveKitManifest;
    _installHarness(<String, Object?>{
      'bootstrap': <String, Object?>{
        'schemaVersion': 1,
        'protocolVersion': 1,
        'hostOrigin': 'http://127.0.0.1:7367',
        'rpcPath': '/rpc',
        'sessionToken': 'session-token-00000000000000000001',
        'effectiveKitManifest': effectiveKit.toJson(),
      },
      'initialize': <String, Object?>{
        'protocolVersion': 1,
        'capabilities': capabilities.toList()..sort(),
      },
      'describe': ScenarioLabRelayDescription(
        runId: binding.runId,
        status: ScenarioLabRelayDescriptionStatus.ready,
        descriptor: descriptor,
      ).toJson(),
      'reattach': observation.toJson(),
      'get': running.toJson(),
      'resultAcknowledgement': expectedAcknowledgement.toJson(),
    });
    harnessInstalled = true;
    client = BrowserStudioHostClient();
    final description = await client.describeLabRelay(binding);
    expect(description.descriptor?.digest, descriptor.digest);
  });

  tearDown(() async {
    if (harnessInstalled) {
      try {
        await client.close();
      } finally {
        _uninstallHarness();
        harnessInstalled = false;
      }
    }
  });

  test('relay result bypasses a blocked general operation', () async {
    final request = ScenarioLabRunObserveRequest(
      runId: running.runId,
      afterSequence: running.sequence,
    );
    var reattachCompleted = false;
    final reattach = client.reattachScenarioLabRun(request);
    unawaited(
      reattach.then<void>(
        (_) => reattachCompleted = true,
        onError: (Object _, StackTrace _) => reattachCompleted = true,
      ),
    );
    await _waitForRequest('lab.reattach');

    final submitted = client.submitLabRelayResult(submission);
    await _waitForRequest('lab.relay.result');
    final acknowledgement = await submitted;

    expect(reattachCompleted, isFalse);
    expect(acknowledgement.digest, expectedAcknowledgement.digest);
    expect(
      _requestMethods(),
      containsAllInOrder(<String>['lab.reattach', 'lab.relay.result']),
    );

    _releaseReattach();
    final observation = await reattach;
    expect(observation.current.digest, running.digest);
  });

  test('reconnect between result send and ACK fails closed', () async {
    _holdRelayResult();
    final submitted = client.submitLabRelayResult(submission);
    await _waitForRequest('lab.relay.result');
    final failedSubmission = expectLater(submitted, throwsA(isA<StateError>()));

    _disconnectLatestSocket();
    await failedSubmission;
    final reconnected = await client.getScenarioLabRun(
      ScenarioLabRunReference(runId: running.runId),
    );
    expect(reconnected.digest, running.digest);
    expect(_socketCount(), 2);

    _ackHeldRelayResult();
    await Future<void>.delayed(Duration.zero);
    expect(_lateAckAttemptCount(), 1);
    await expectLater(
      client.submitLabRelayResult(submission),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _waitForRequest(String method) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    if (_requestMethods().contains(method)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Browser Host harness did not receive $method');
}

List<String> _requestMethods() =>
    (jsonDecode(_harnessRequestMethods().toDart) as List<Object?>)
        .cast<String>();

int _socketCount() => _harnessSocketCount().toDartInt;

int _lateAckAttemptCount() => _harnessLateAckAttemptCount().toDartInt;

void _installHarness(Map<String, Object?> config) {
  final source =
      '''
(() => {
  const config = ${jsonEncode(config)};
  const originalFetch = globalThis.fetch;
  const OriginalWebSocket = globalThis.WebSocket;
  const state = {
    requests: [],
    sockets: [],
    heldReattach: null,
    heldRelayResult: null,
    holdRelayResult: false,
    lateAckAttemptCount: 0,
  };

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
      state.sockets.push(this);
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
        case 'lab.relay.describe':
          respond(this, request, config.describe);
          break;
        case 'lab.reattach':
          state.heldReattach = {socket: this, request};
          break;
        case 'lab.get':
          respond(this, request, config.get);
          break;
        case 'lab.relay.result':
          state.heldRelayResult = {socket: this, request};
          if (!state.holdRelayResult) {
            respond(this, request, config.resultAcknowledgement);
          }
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
      this.serverClose(code, reason);
    }

    serverMessage(message) {
      this.dispatchEvent(new MessageEvent('message', {
        data: JSON.stringify(message),
      }));
    }

    serverClose(code = 1000, reason = 'test disconnect') {
      if (this.readyState === FakeWebSocket.CLOSED) return;
      this.readyState = FakeWebSocket.CLOSED;
      this.dispatchEvent(new CloseEvent('close', {
        code,
        reason,
        wasClean: true,
      }));
    }
  }

  globalThis.fetch = async () => new Response(
    JSON.stringify(config.bootstrap),
    {status: 200, headers: {'content-type': 'application/json'}},
  );
  globalThis.WebSocket = FakeWebSocket;
  globalThis.__relayHarnessRequestMethods = () =>
    JSON.stringify(state.requests.map((request) => request.method));
  globalThis.__relayHarnessSocketCount = () => state.sockets.length;
  globalThis.__relayHarnessLateAckAttemptCount = () =>
    state.lateAckAttemptCount;
  globalThis.__relayHarnessReleaseReattach = () => {
    const held = state.heldReattach;
    if (held === null) throw new Error('no held reattach request');
    state.heldReattach = null;
    respond(held.socket, held.request, config.reattach);
  };
  globalThis.__relayHarnessHoldRelayResult = () => {
    state.holdRelayResult = true;
  };
  globalThis.__relayHarnessDisconnectLatestSocket = () => {
    const socket = state.sockets[state.sockets.length - 1];
    if (socket === undefined) throw new Error('no socket to disconnect');
    socket.serverClose();
  };
  globalThis.__relayHarnessAckHeldRelayResult = () => {
    const held = state.heldRelayResult;
    if (held === null) throw new Error('no held relay result');
    state.heldRelayResult = null;
    state.lateAckAttemptCount += 1;
    held.socket.serverMessage({
      jsonrpc: '2.0',
      id: held.request.id,
      result: config.resultAcknowledgement,
    });
  };
  globalThis.__relayHarnessUninstall = () => {
    globalThis.fetch = originalFetch;
    globalThis.WebSocket = OriginalWebSocket;
    delete globalThis.__relayHarnessRequestMethods;
    delete globalThis.__relayHarnessSocketCount;
    delete globalThis.__relayHarnessLateAckAttemptCount;
    delete globalThis.__relayHarnessReleaseReattach;
    delete globalThis.__relayHarnessHoldRelayResult;
    delete globalThis.__relayHarnessDisconnectLatestSocket;
    delete globalThis.__relayHarnessAckHeldRelayResult;
    delete globalThis.__relayHarnessUninstall;
  };
})();
''';
  globalContext.callMethod('eval'.toJS, source.toJS);
}

@JS('__relayHarnessRequestMethods')
external JSString _harnessRequestMethods();

@JS('__relayHarnessSocketCount')
external JSNumber _harnessSocketCount();

@JS('__relayHarnessLateAckAttemptCount')
external JSNumber _harnessLateAckAttemptCount();

@JS('__relayHarnessReleaseReattach')
external void _releaseReattach();

@JS('__relayHarnessHoldRelayResult')
external void _holdRelayResult();

@JS('__relayHarnessDisconnectLatestSocket')
external void _disconnectLatestSocket();

@JS('__relayHarnessAckHeldRelayResult')
external void _ackHeldRelayResult();

@JS('__relayHarnessUninstall')
external void _uninstallHarness();
