import 'dart:async';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:devex_engine/devex_engine.dart';
import 'package:devex_runtime/devex_runtime.dart';
import 'package:jose/jose.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late _FixedClock clock;
  late RemoteExecutionPlan plan;
  late SignedRemoteExecutionPlan signed;
  late String capabilityToken;
  late RemoteWorkerTokenVerifier verifier;
  late JoseRemoteExecutionSecurity security;
  late RemoteLease lease;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('devex-remote-worker-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    clock = _FixedClock(DateTime.utc(2026, 8, 9, 12));
    final bytes = <int>[1, 2, 3, 4];
    final input = RemoteArtifactInput(
      role: 'webBuild',
      digest: Digest.bytes(bytes),
      size: bytes.length,
      mediaType: 'application/zip',
    );
    plan = RemoteExecutionPlan(
      tenantId: 'tenant-a',
      runId: 'run-001',
      requestDigest: Digest.semantic('request'),
      target: RemoteTargetKind.web,
      mode: RemoteRunMode.batch,
      interactiveTransport: RemoteInteractiveTransport.none,
      artifacts: <RemoteArtifactInput>[input],
      executionFingerprintDigest: Digest.semantic('fingerprint'),
      containmentPolicyDigest: Digest.semantic('containment'),
      issuedAt: clock.nowUtc(),
      expiresAt: clock.nowUtc().add(const Duration(minutes: 5)),
      nonce: 'nonce-001',
    );
    lease = RemoteLease(
      tenantId: plan.tenantId,
      runId: plan.runId,
      workerId: 'worker-001',
      tokenId: 'token-001',
      generation: 1,
      acquiredAt: clock.nowUtc(),
      heartbeatAt: clock.nowUtc(),
      expiresAt: clock.nowUtc().add(const Duration(minutes: 1)),
    );
    final generated = JsonWebKey.generate('RS256');
    security = JoseRemoteExecutionSecurity(
      signingKey: generated,
      keyId: 'remote-key-001',
      algorithm: 'RS256',
    );
    signed = await security.sign(plan);
    capabilityToken = await security.issue(
      plan: plan,
      lease: lease,
      scopes: const <String>{
        'artifact:read',
        'artifact:write',
        'run:heartbeat',
        'run:complete',
      },
    );
    final public = JsonWebKey.fromJson(<String, dynamic>{
      ...JsonWebKey.fromCryptoKeys(
        publicKey: generated.cryptoKeyPair.publicKey,
      ).toJson(),
      'kid': 'remote-key-001',
    });
    verifier = RemoteWorkerTokenVerifier(
      trustedKeys: JsonWebKeySet.fromJson(<String, Object?>{
        'keys': <Object?>[public.toJson()],
      }),
      allowedAlgorithms: const <String>{'RS256'},
      clock: clock,
    );
    await verifier.verifyCapability(
      capabilityToken,
      plan: plan,
      workerId: 'worker-001',
      requiredScopes: const <String>{'artifact:read'},
    );
  });

  test(
    'worker verifies inputs, uploads outputs, and wipes ephemeral state',
    () async {
      final artifacts = _Artifacts(plan.artifacts.single, tamper: false);
      final control = _Control();
      final backend = _Backend();
      final service = RemoteWorkerService(
        verifier: verifier,
        artifacts: artifacts,
        control: control,
        backend: backend,
        clock: clock,
        workspaceRoot: root,
        namespace: 'devex-run-0123456789abcdef',
        serviceAccount: 'worker',
      );
      final outcome = await service.run(
        signedPlan: signed.compactSignature,
        capabilityToken: capabilityToken,
        workerId: 'worker-001',
      );
      expect(control.states, <RemoteRunState>[
        RemoteRunState.provisioning,
        RemoteRunState.running,
        RemoteRunState.uploading,
      ]);
      expect(control.completed, isTrue);
      expect(backend.stopped, isTrue);
      expect(Directory(p.join(root.path, plan.runId)).existsSync(), isFalse);
      expect(
        outcome.artifacts.executionFingerprintDigest,
        plan.executionFingerprintDigest,
      );
      expect(outcome.containment.defaultDenyEgress, isTrue);
      expect(outcome.containment.ephemeralStorageWiped, isTrue);
      expect(outcome.containment.leaseRevoked, isFalse);
    },
  );

  test(
    'digest mismatch fails, reports no success, and still cleans up',
    () async {
      final control = _Control();
      final backend = _Backend();
      final service = RemoteWorkerService(
        verifier: verifier,
        artifacts: _Artifacts(plan.artifacts.single, tamper: true),
        control: control,
        backend: backend,
        clock: clock,
        workspaceRoot: root,
        namespace: 'devex-run-0123456789abcdef',
        serviceAccount: 'worker',
      );
      await expectLater(
        service.run(
          signedPlan: signed.compactSignature,
          capabilityToken: capabilityToken,
          workerId: 'worker-001',
        ),
        throwsStateError,
      );
      expect(control.completed, isFalse);
      expect(control.states.last, RemoteRunState.failed);
      expect(backend.stopped, isTrue);
      expect(Directory(p.join(root.path, plan.runId)).existsSync(), isFalse);
    },
  );

  test(
    'interactive worker fences stream, reauthenticates, and closes the target',
    () async {
      final interactivePlan = RemoteExecutionPlan(
        tenantId: plan.tenantId,
        runId: plan.runId,
        requestDigest: plan.requestDigest,
        target: plan.target,
        mode: RemoteRunMode.interactive,
        interactiveTransport: RemoteInteractiveTransport.webDirect,
        artifacts: plan.artifacts,
        executionFingerprintDigest: plan.executionFingerprintDigest,
        containmentPolicyDigest: plan.containmentPolicyDigest,
        issuedAt: plan.issuedAt,
        expiresAt: plan.expiresAt,
        nonce: plan.nonce,
      );
      final interactiveSigned = await security.sign(interactivePlan);
      final interactiveCapability = await security.issue(
        plan: interactivePlan,
        lease: lease,
        scopes: const <String>{
          'artifact:read',
          'artifact:write',
          'run:heartbeat',
          'run:complete',
          'stream:write',
        },
      );
      final artifacts = _Artifacts(
        interactivePlan.artifacts.single,
        tamper: false,
      );
      final control = _Control();
      final session = _InteractiveSession();
      final backend = _InteractiveBackend(session);
      final stream = _Stream();
      final service = RemoteWorkerService(
        verifier: verifier,
        artifacts: artifacts,
        control: control,
        backend: backend,
        clock: clock,
        workspaceRoot: root,
        namespace: 'devex-run-0123456789abcdef',
        serviceAccount: 'worker',
        stream: stream,
        heartbeatInterval: const Duration(milliseconds: 1),
      );

      final outcome = await service.run(
        signedPlan: interactiveSigned.compactSignature,
        capabilityToken: interactiveCapability,
        workerId: 'worker-001',
      );

      expect(session.ran, isTrue);
      expect(session.stopped, isTrue);
      expect(stream.connectedTokens, <String>['renewed-capability-1']);
      expect(stream.reauthenticatedTokens, isNotEmpty);
      expect(stream.publishedChannels, <RemoteStreamChannel>[
        RemoteStreamChannel.metadataJson,
      ]);
      expect(stream.closed, isTrue);
      expect(control.heartbeatCount, greaterThan(1));
      expect(control.completed, isTrue);
      expect(
        outcome.interactiveTransport,
        RemoteInteractiveTransport.webDirect,
      );
    },
  );

  test(
    'heartbeat failure stops execution and can never report success',
    () async {
      final control = _Control(failHeartbeatAt: 2);
      final backend = _BlockingBackend();
      final service = RemoteWorkerService(
        verifier: verifier,
        artifacts: _Artifacts(plan.artifacts.single, tamper: false),
        control: control,
        backend: backend,
        clock: clock,
        workspaceRoot: root,
        namespace: 'devex-run-0123456789abcdef',
        serviceAccount: 'worker',
        heartbeatInterval: const Duration(milliseconds: 1),
        backendStopTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(
        service.run(
          signedPlan: signed.compactSignature,
          capabilityToken: capabilityToken,
          workerId: 'worker-001',
        ),
        throwsA(isA<RemoteStateException>()),
      );
      expect(control.heartbeatCount, greaterThanOrEqualTo(2));
      expect(control.completed, isFalse);
      expect(control.states.last, RemoteRunState.failed);
      expect(backend.stopped, isTrue);
      expect(Directory(p.join(root.path, plan.runId)).existsSync(), isFalse);
    },
  );
}

final class _Artifacts implements RemoteWorkerArtifactClient {
  _Artifacts(this.input, {required this.tamper});

  final RemoteArtifactInput input;
  final bool tamper;

  @override
  Future<File> download({
    required VerifiedRemoteCapability capability,
    required RemoteArtifactInput artifact,
    required Directory destination,
  }) async =>
      File(p.join(destination.path, 'input.bin'))
        ..writeAsBytesSync(tamper ? <int>[9, 9, 9, 9] : <int>[1, 2, 3, 4]);

  @override
  Future<HostedBlobDescriptor> upload({
    required VerifiedRemoteCapability capability,
    required RemoteGeneratedArtifact artifact,
  }) async {
    final bytes = artifact.file.readAsBytesSync();
    final digest = Digest.bytes(bytes);
    return HostedBlobDescriptor(
      tenantId: capability.tenantId,
      digest: digest,
      size: bytes.length,
      mediaType: artifact.mediaType,
      classification: artifact.classification,
      objectKey:
          'tenants/${capability.tenantId}/blobs/sha256/${digest.value.substring(7)}',
    );
  }
}

final class _Backend implements RemoteWorkerBackend {
  bool stopped = false;

  @override
  Future<RemoteBackendResult> execute({
    required RemoteExecutionPlan plan,
    required Map<String, File> inputsByRole,
    required Directory workspace,
  }) async {
    expect(inputsByRole.keys, <String>['webBuild']);
    final screenshot = File(p.join(workspace.path, 'screenshot.png'))
      ..writeAsBytesSync(<int>[137, 80, 78, 71]);
    return RemoteBackendResult(
      artifacts: <RemoteGeneratedArtifact>[
        RemoteGeneratedArtifact(
          role: 'screenshot',
          file: screenshot,
          mediaType: 'image/png',
          classification: 'internal',
        ),
      ],
      interactiveTransport: RemoteInteractiveTransport.none,
    );
  }

  @override
  Future<void> stop() async => stopped = true;
}

final class _BlockingBackend implements RemoteWorkerBackend {
  final Completer<RemoteBackendResult> _completion =
      Completer<RemoteBackendResult>();
  bool stopped = false;

  @override
  Future<RemoteBackendResult> execute({
    required RemoteExecutionPlan plan,
    required Map<String, File> inputsByRole,
    required Directory workspace,
  }) => _completion.future;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_completion.isCompleted) {
      _completion.completeError(StateError('backend stopped'));
    }
  }
}

final class _InteractiveBackend implements RemoteWorkerBackend {
  _InteractiveBackend(this.session);

  final _InteractiveSession session;
  bool stopped = false;

  @override
  Future<RemoteBackendResult> execute({
    required RemoteExecutionPlan plan,
    required Map<String, File> inputsByRole,
    required Directory workspace,
  }) async {
    final screenshot = File(p.join(workspace.path, 'screenshot.png'))
      ..writeAsBytesSync(<int>[137, 80, 78, 71]);
    return RemoteBackendResult(
      artifacts: <RemoteGeneratedArtifact>[
        RemoteGeneratedArtifact(
          role: 'screenshot',
          file: screenshot,
          mediaType: 'image/png',
          classification: 'internal',
        ),
      ],
      interactiveTransport: session.transport,
      interactiveSession: session,
    );
  }

  @override
  Future<void> stop() async {
    stopped = true;
    await session.stop();
  }
}

final class _InteractiveSession implements RemoteWorkerInteractiveSession {
  bool ran = false;
  bool stopped = false;

  @override
  RemoteInteractiveTransport get transport =>
      RemoteInteractiveTransport.webDirect;

  @override
  Future<void> run({
    required RemoteWorkerStreamClient stream,
    required DateTime deadline,
  }) async {
    ran = true;
    await stream.publish(RemoteStreamChannel.metadataJson, const <int>[1]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  @override
  Future<void> stop() async => stopped = true;
}

final class _Stream implements RemoteWorkerStreamClient {
  final StreamController<RemoteStreamFrame> _controls =
      StreamController<RemoteStreamFrame>.broadcast();
  final Completer<void> _done = Completer<void>();
  final List<String> connectedTokens = <String>[];
  final List<String> reauthenticatedTokens = <String>[];
  final List<RemoteStreamChannel> publishedChannels = <RemoteStreamChannel>[];
  bool closed = false;

  @override
  Stream<RemoteStreamFrame> get controlFrames => _controls.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> connect(String capabilityToken) async {
    connectedTokens.add(capabilityToken);
  }

  @override
  Future<void> reauthenticate(String capabilityToken) async {
    reauthenticatedTokens.add(capabilityToken);
  }

  @override
  Future<void> publish(RemoteStreamChannel channel, List<int> payload) async {
    publishedChannels.add(channel);
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_done.isCompleted) _done.complete();
    await _controls.close();
  }
}

final class _Control implements RemoteWorkerControlClient {
  _Control({this.failHeartbeatAt});

  final int? failHeartbeatAt;
  final List<RemoteRunState> states = <RemoteRunState>[];
  bool completed = false;
  int heartbeatCount = 0;

  @override
  Future<void> complete({
    required VerifiedRemoteCapability capability,
    required RemoteArtifactManifest artifacts,
    required RemoteContainmentReport containment,
    required RemoteInteractiveTransport interactiveTransport,
  }) async => completed = true;

  @override
  Future<RemoteWorkerHeartbeat> heartbeat(
    VerifiedRemoteCapability capability,
  ) async {
    heartbeatCount += 1;
    if (heartbeatCount == failHeartbeatAt) {
      throw StateError('synthetic heartbeat failure');
    }
    return RemoteWorkerHeartbeat(
      renewedCapabilityToken: 'renewed-capability-$heartbeatCount',
    );
  }

  @override
  Future<void> state({
    required VerifiedRemoteCapability capability,
    required RemoteRunState state,
    String? failureCode,
  }) async => states.add(state);
}

final class _FixedClock implements Clock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  int monotonicMicroseconds() => value.microsecondsSinceEpoch;

  @override
  DateTime nowUtc() => value;
}
