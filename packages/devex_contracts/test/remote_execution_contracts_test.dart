import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 9, 12);
  final input = RemoteArtifactInput(
    role: 'androidApk',
    digest: Digest.semantic('apk'),
    size: 1024,
    mediaType: 'application/vnd.android.package-archive',
  );
  final request = RemoteExecutionRequest(
    tenantId: 'tenant-a',
    id: 'request-001',
    workspaceId: 'workspace-a',
    requestedBy: 'principal-a',
    target: RemoteTargetKind.androidEmulator,
    mode: RemoteRunMode.interactive,
    interactiveTransport: RemoteInteractiveTransport.scrcpyH264Control,
    priority: 50,
    maximumDurationSeconds: 300,
    artifacts: <RemoteArtifactInput>[input],
    requestedAt: now,
  );
  final plan = RemoteExecutionPlan(
    tenantId: request.tenantId,
    runId: 'run-001',
    requestDigest: request.digest,
    target: request.target,
    mode: request.mode,
    interactiveTransport: request.interactiveTransport,
    artifacts: request.artifacts,
    executionFingerprintDigest: Digest.semantic('fingerprint'),
    containmentPolicyDigest: Digest.semantic('containment'),
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
    nonce: 'nonce-001',
    deviceImage: DeviceImageDescriptor(
      id: 'android-api-35',
      imageDigest: Digest.semantic('image'),
      apiLevel: 35,
      abi: 'x86_64',
      renderer: 'swiftshader_indirect',
      kvmRequired: true,
    ),
  );

  test('remote documents are strict, round-trip, and schema conformant', () {
    final run = RemoteRun(
      tenantId: request.tenantId,
      id: plan.runId,
      requestDigest: request.digest,
      planDigest: plan.digest,
      target: request.target,
      mode: request.mode,
      state: RemoteRunState.running,
      attempt: 1,
      createdAt: now,
      updatedAt: now,
      workerId: 'worker-001',
    );
    final lease = RemoteLease(
      tenantId: request.tenantId,
      runId: plan.runId,
      workerId: 'worker-001',
      tokenId: 'token-001',
      generation: 1,
      acquiredAt: now,
      heartbeatAt: now,
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final blobDigest = Digest.semantic('screenshot');
    final manifest = RemoteArtifactManifest(
      tenantId: request.tenantId,
      runId: plan.runId,
      executionFingerprintDigest: plan.executionFingerprintDigest,
      interactiveTransport: RemoteInteractiveTransport.scrcpyH264Control,
      artifacts: <HostedBlobDescriptor>[
        HostedBlobDescriptor(
          tenantId: request.tenantId,
          digest: blobDigest,
          size: 10,
          mediaType: 'image/png',
          classification: 'internal',
          objectKey:
              'tenants/tenant-a/blobs/sha256/${blobDigest.value.substring(7)}',
        ),
      ],
      createdAt: now,
    );
    final containment = RemoteContainmentReport(
      tenantId: request.tenantId,
      runId: plan.runId,
      namespace: 'devex-run-001',
      serviceAccount: 'worker-001',
      podSecurityProfile: 'android-kvm-minimal',
      defaultDenyEgress: true,
      allowedEndpointClasses: const <String>{
        'gateway',
        'artifact',
        'control',
        'dns',
      },
      ephemeralStorageWiped: true,
      leaseRevoked: true,
      observedAt: now,
    );
    final sessionTicket = RemoteSessionTicket(
      tenantId: request.tenantId,
      runId: plan.runId,
      principalId: 'principal-a',
      role: RemoteSessionRole.viewer,
      allowedTransports: const <RemoteInteractiveTransport>{
        RemoteInteractiveTransport.scrcpyH264Control,
        RemoteInteractiveTransport.periodicScreenshotReadOnly,
      },
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 1)),
      nonce: 'session-nonce-001',
    );
    final validator = Draft202012Validator(
      jsonDecode(
            File(
              p.join(_root(), 'schemas/v1/remote-execution.schema.json'),
            ).readAsStringSync(),
          )
          as Object,
    );
    for (final document in <Map<String, Object?>>[
      request.toJson(),
      plan.toJson(),
      run.toJson(),
      lease.toJson(),
      manifest.toJson(),
      containment.toJson(),
      sessionTicket.toJson(),
    ]) {
      expect(validator.validate(document).isValid, isTrue, reason: '$document');
    }
    expect(
      RemoteExecutionRequest.fromJson(request.toJson()).digest,
      request.digest,
    );
    expect(RemoteExecutionPlan.fromJson(plan.toJson()).digest, plan.digest);
    expect(RemoteRun.fromJson(run.toJson()).state, RemoteRunState.running);
    expect(RemoteLease.fromJson(lease.toJson()).tokenId, lease.tokenId);
    expect(
      RemoteSessionTicket.fromJson(sessionTicket.toJson()).allowedTransports,
      sessionTicket.allowedTransports,
    );
    final grant = RemoteSessionGrant(
      runId: plan.runId,
      endpoint: Uri.parse(
        'wss://gateway.example.test/v1/sessions/${plan.runId}/viewer',
      ),
      compactTicket: 'signed-viewer-ticket',
      allowedTransports: sessionTicket.allowedTransports,
      expiresAt: sessionTicket.expiresAt,
    );
    expect(
      RemoteSessionGrant.fromEphemeralJson(
        grant.toEphemeralJson(),
      ).allowedTransports,
      grant.allowedTransports,
    );
  });

  test('remote binary stream frames are bounded and deterministic', () {
    final frame = RemoteStreamFrame(
      channel: RemoteStreamChannel.videoH264,
      sequence: 42,
      payload: const <int>[0, 0, 0, 1, 0x67],
    );
    final encoded = RemoteStreamFrameCodec.encode(frame);
    final decoded = RemoteStreamFrameCodec.decode(encoded);
    expect(decoded.channel, frame.channel);
    expect(decoded.sequence, 42);
    expect(decoded.payload, frame.payload);

    final portableMaximum = RemoteStreamFrameCodec.decode(
      RemoteStreamFrameCodec.encode(
        RemoteStreamFrame(
          channel: RemoteStreamChannel.metadataJson,
          sequence: 0x1FFFFFFFFFFFFF,
          payload: const <int>[1],
        ),
      ),
    );
    expect(portableMaximum.sequence, 0x1FFFFFFFFFFFFF);
    expect(
      () => RemoteStreamFrame(
        channel: RemoteStreamChannel.metadataJson,
        sequence: 0x20000000000000,
        payload: const <int>[1],
      ),
      throwsFormatException,
    );

    final oversized = List<int>.filled(64 * 1024 + 1, 1);
    expect(
      () => RemoteStreamFrame(
        channel: RemoteStreamChannel.control,
        sequence: 1,
        payload: oversized,
      ),
      throwsFormatException,
    );
    expect(
      () =>
          RemoteStreamFrameCodec.decode(encoded.sublist(0, encoded.length - 1)),
      throwsA(isA<RemoteStreamProtocolException>()),
    );
  });

  test('remote H.264 access units retain WebCodecs timing and frame flags', () {
    final packet = RemoteH264Packet(
      configuration: false,
      keyFrame: true,
      timestampMicros: 123456,
      data: const <int>[0, 0, 0, 1, 0x65, 1, 2, 3],
    );
    final encoded = RemoteH264PacketCodec.encode(packet);
    final decoded = RemoteH264PacketCodec.decode(encoded);
    expect(decoded.configuration, isFalse);
    expect(decoded.keyFrame, isTrue);
    expect(decoded.timestampMicros, 123456);
    expect(decoded.data, packet.data);

    final maximumTimestamp = RemoteH264PacketCodec.decode(
      RemoteH264PacketCodec.encode(
        RemoteH264Packet(
          configuration: false,
          keyFrame: false,
          timestampMicros: 0x1FFFFFFFFFFFFF,
          data: const <int>[1],
        ),
      ),
    );
    expect(maximumTimestamp.timestampMicros, 0x1FFFFFFFFFFFFF);

    final configuration = RemoteH264PacketCodec.decode(
      RemoteH264PacketCodec.encode(
        RemoteH264Packet(
          configuration: true,
          keyFrame: false,
          timestampMicros: null,
          data: const <int>[0, 0, 0, 1, 0x67],
        ),
      ),
    );
    expect(configuration.configuration, isTrue);
    expect(configuration.timestampMicros, isNull);
    expect(
      () =>
          RemoteH264PacketCodec.decode(encoded.sublist(0, encoded.length - 1)),
      throwsA(isA<RemoteStreamProtocolException>()),
    );
  });

  test(
    'source/build artifacts and Android without a pinned image fail closed',
    () {
      expect(
        () => RemoteArtifactInput(
          role: 'sourceTree',
          digest: Digest.semantic('source'),
          size: 1,
          mediaType: 'application/zip',
        ),
        throwsFormatException,
      );
      expect(
        () => RemoteExecutionPlan(
          tenantId: request.tenantId,
          runId: 'run-002',
          requestDigest: request.digest,
          target: RemoteTargetKind.androidEmulator,
          mode: RemoteRunMode.batch,
          interactiveTransport: RemoteInteractiveTransport.none,
          artifacts: request.artifacts,
          executionFingerprintDigest: Digest.semantic('fingerprint'),
          containmentPolicyDigest: Digest.semantic('containment'),
          issuedAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
          nonce: 'nonce-002',
        ),
        throwsFormatException,
      );
    },
  );
}

String _root() {
  var directory = Directory.current.absolute;
  while (!File(
    p.join(directory.path, 'pubspec.yaml'),
  ).readAsStringSync().contains('name: devex_workspace')) {
    directory = directory.parent;
  }
  return directory.path;
}
