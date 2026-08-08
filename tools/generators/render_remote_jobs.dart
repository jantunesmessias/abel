import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run tools/generators/render_remote_jobs.dart OUTPUT_DIR',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(arguments.single).absolute;
  if (output.existsSync() && output.listSync().isNotEmpty) {
    stderr.writeln('refusing to overwrite a non-empty output directory');
    exitCode = 73;
    return;
  }
  output.createSync(recursive: true);
  final builder = KubernetesRemoteJobBuilder(
    KubernetesRemoteJobConfiguration(
      webWorkerImage:
          'registry.example.test/workspace/worker-web@sha256:'
          '${_hex('a')}',
      androidWorkerImage:
          'registry.example.test/workspace/worker-android@sha256:'
          '${_hex('b')}',
      controlPlaneOrigin: Uri.parse('https://control.example.test'),
      artifactOrigin: Uri.parse('https://artifacts.example.test'),
      gatewayOrigin: Uri.parse('https://gateway.example.test'),
      trustedJwksJson: '{"keys":[{"kty":"EC","crv":"P-256","x":"x","y":"y"}]}',
      androidImageDigest: Digest('sha256:${_hex('d')}'),
      androidScrcpyServerDigest: Digest('sha256:${_hex('e')}'),
      allowedStudioOrigins: const <String>['https://studio.example.test'],
      allowedEgressCidrs: const <String>['10.0.0.0/24'],
    ),
  );
  const variants = <(RemoteTargetKind, RemoteRunMode)>[
    (RemoteTargetKind.web, RemoteRunMode.batch),
    (RemoteTargetKind.web, RemoteRunMode.interactive),
    (RemoteTargetKind.androidEmulator, RemoteRunMode.batch),
    (RemoteTargetKind.androidEmulator, RemoteRunMode.interactive),
  ];
  for (final (target, mode) in variants) {
    final bundle = builder.build(_assignment(target, mode));
    final variant = '${target.name}-${mode.name}';
    final directory = Directory('${output.path}/$variant')..createSync();
    for (final (index, manifest) in bundle.launchManifests.indexed) {
      final kind = manifest['kind']! as String;
      final name = index.toString().padLeft(2, '0');
      File('${directory.path}/$name-$kind.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        flush: true,
      );
    }
  }
  stdout.writeln('rendered ${variants.length} remote Job variants');
}

RemoteAssignment _assignment(RemoteTargetKind target, RemoteRunMode mode) {
  final now = DateTime.utc(2026, 8, 9, 12);
  final runId = 'render-${target.name}-${mode.name}';
  final transport = switch ((target, mode)) {
    (_, RemoteRunMode.batch) => RemoteInteractiveTransport.none,
    (RemoteTargetKind.web, RemoteRunMode.interactive) =>
      RemoteInteractiveTransport.webDirect,
    (RemoteTargetKind.androidEmulator, RemoteRunMode.interactive) =>
      RemoteInteractiveTransport.scrcpyH264Control,
  };
  final artifact = RemoteArtifactInput(
    role: target == RemoteTargetKind.web ? 'webBuild' : 'androidApk',
    digest: Digest.semantic('$runId-executable'),
    size: 1024,
    mediaType: target == RemoteTargetKind.web
        ? 'application/zip'
        : 'application/vnd.android.package-archive',
  );
  final request = RemoteExecutionRequest(
    tenantId: 'render-tenant',
    id: 'request-$runId',
    workspaceId: 'workspace-render',
    requestedBy: 'principal-render',
    target: target,
    mode: mode,
    interactiveTransport: transport,
    priority: 50,
    maximumDurationSeconds: 300,
    artifacts: <RemoteArtifactInput>[artifact],
    requestedAt: now,
  );
  final deviceImage = target == RemoteTargetKind.androidEmulator
      ? DeviceImageDescriptor(
          id: 'android-api-35-x86-64',
          imageDigest: Digest('sha256:${_hex('d')}'),
          apiLevel: 35,
          abi: 'x86_64',
          renderer: 'swiftshader_indirect',
          kvmRequired: true,
        )
      : null;
  final plan = RemoteExecutionPlan(
    tenantId: request.tenantId,
    runId: runId,
    requestDigest: request.digest,
    target: target,
    mode: mode,
    interactiveTransport: transport,
    artifacts: request.artifacts,
    executionFingerprintDigest: Digest.semantic('$runId-fingerprint'),
    containmentPolicyDigest: Digest.semantic('$runId-containment'),
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
    nonce: 'nonce-$runId',
    deviceImage: deviceImage,
  );
  final lease = RemoteLease(
    tenantId: request.tenantId,
    runId: runId,
    workerId: 'worker-render',
    tokenId: 'token-render',
    generation: 1,
    acquiredAt: now,
    heartbeatAt: now,
    expiresAt: now.add(const Duration(minutes: 1)),
  );
  return RemoteAssignment(
    run: RemoteRun(
      tenantId: request.tenantId,
      id: runId,
      requestDigest: request.digest,
      planDigest: plan.digest,
      target: target,
      mode: mode,
      state: RemoteRunState.scheduled,
      attempt: 1,
      createdAt: now,
      updatedAt: now,
      workerId: lease.workerId,
    ),
    lease: lease,
    signedPlan: SignedRemoteExecutionPlan(
      plan: plan,
      compactSignature: 'render-only-signed-plan',
      signerKeyId: 'render-key',
    ),
    capabilityToken: 'render-only-capability-not-a-secret',
  );
}

String _hex(String character) => List<String>.filled(64, character).join();
