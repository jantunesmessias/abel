import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  final configuration = KubernetesRemoteJobConfiguration(
    webWorkerImage:
        'registry.example.test/workspace/worker-web@sha256:${'a' * 64}',
    androidWorkerImage:
        'registry.example.test/workspace/worker-android@sha256:${'b' * 64}',
    controlPlaneOrigin: Uri.parse('https://control.example.test'),
    artifactOrigin: Uri.parse('https://objects.example.test'),
    gatewayOrigin: Uri.parse('https://gateway.example.test'),
    trustedJwksJson: '{"keys":[{"kty":"EC","crv":"P-256","x":"x","y":"y"}]}',
    androidImageDigest: Digest.semantic('android-image'),
    androidScrcpyServerDigest: Digest.semantic('scrcpy-server'),
    allowedStudioOrigins: const <String>['https://studio.example.test'],
    allowedEgressCidrs: const <String>['10.20.0.0/16'],
  );

  test(
    'web Job is immutable, restricted, tenant-opaque, and deny-by-default',
    () {
      final assignment = _assignment(RemoteTargetKind.web);
      final bundle = KubernetesRemoteJobBuilder(
        configuration,
      ).build(assignment);
      expect(
        bundle.namespace,
        matches(RegExp(r'^workspace-run-[0-9a-f]{16}$')),
      );
      final publicJson = jsonEncode(bundle.publicManifests);
      expect(publicJson, isNot(contains('capability-secret')));
      expect(publicJson, isNot(contains('tenant-a')));
      expect(publicJson, isNot(contains('DATABASE_URL')));
      expect(publicJson, isNot(contains('hostPath')));
      expect(publicJson, isNot(contains('privileged')));
      expect(publicJson, contains(configuration.webWorkerImage));
      expect(publicJson, isNot(contains(configuration.androidWorkerImage)));

      final namespace = bundle.publicManifests.first;
      final labels =
          (namespace['metadata']! as Map<String, Object?>)['labels']!
              as Map<String, Object?>;
      expect(labels['pod-security.kubernetes.io/enforce'], 'restricted');
      final policy = bundle.publicManifests.singleWhere(
        (manifest) => manifest['kind'] == 'NetworkPolicy',
      );
      final policySpec = policy['spec']! as Map<String, Object?>;
      expect(policySpec['policyTypes'], <String>['Ingress', 'Egress']);
      expect(policySpec['ingress'], isEmpty);

      final job = bundle.publicManifests.singleWhere(
        (manifest) => manifest['kind'] == 'Job',
      );
      final jobSpec = job['spec']! as Map<String, Object?>;
      expect(jobSpec['backoffLimit'], 0);
      expect(jobSpec['ttlSecondsAfterFinished'], 300);
      final podSpec =
          ((jobSpec['template']! as Map<String, Object?>)['spec']!)
              as Map<String, Object?>;
      expect(podSpec['automountServiceAccountToken'], isFalse);
      expect(podSpec['runtimeClassName'], isNull);

      final manifests = bundle.launchManifests.toList(growable: false);
      final secret = manifests.singleWhere(
        (manifest) => manifest['kind'] == 'Secret',
      );
      expect(secret['immutable'], isTrue);
      final data = secret['data']! as Map<String, Object?>;
      expect(
        utf8.decode(base64Decode(data['capability.jwt']! as String)),
        'capability-secret',
      );
    },
  );

  test('Android Job requires dedicated KVM resource without host mounts', () {
    final bundle = KubernetesRemoteJobBuilder(
      configuration,
    ).build(_assignment(RemoteTargetKind.androidEmulator));
    final job = bundle.publicManifests.singleWhere(
      (manifest) => manifest['kind'] == 'Job',
    );
    final podSpec =
        ((((job['spec']! as Map<String, Object?>)['template']!)
                as Map<String, Object?>)['spec']!)
            as Map<String, Object?>;
    expect(podSpec['runtimeClassName'], 'workspace-android-kvm');
    expect(podSpec['nodeSelector'], const <String, String>{
      'io.github.jantunesmessias/android-kvm': 'true',
      'io.github.jantunesmessias/android-image':
          'b02eb4d90e167b7c0f30b6312119dfd4b074c9716ab16e80677daa99b5c99c8f',
    });
    final container =
        (podSpec['containers']! as List<Object?>).single
            as Map<String, Object?>;
    expect(container['image'], configuration.androidWorkerImage);
    final environment = jsonEncode(container['env']);
    expect(environment, contains('ANDROID_IMAGE_DIGEST'));
    expect(environment, contains('ANDROID_SDK_ROOT'));
    expect(environment, contains('ANDROID_AVD'));
    final resources = container['resources']! as Map<String, Object?>;
    final limits = resources['limits']! as Map<String, Object?>;
    expect(limits['devices.kubevirt.io/kvm'], '1');
    expect(jsonEncode(podSpec), isNot(contains('/dev/kvm')));
  });

  test('interactive Job has an authenticated per-run Gateway API route', () {
    final bundle = KubernetesRemoteJobBuilder(
      configuration,
    ).build(_assignment(RemoteTargetKind.web, mode: RemoteRunMode.interactive));
    expect(
      bundle.publicManifests.map((manifest) => manifest['kind']),
      containsAll(<String>['Service', 'HTTPRoute']),
    );
    final route = bundle.publicManifests.singleWhere(
      (manifest) => manifest['kind'] == 'HTTPRoute',
    );
    expect(jsonEncode(route), contains('/v1/sessions/run-001'));
    final job = bundle.publicManifests.singleWhere(
      (manifest) => manifest['kind'] == 'Job',
    );
    final podSpec =
        ((((job['spec']! as Map<String, Object?>)['template']!)
                as Map<String, Object?>)['spec']!)
            as Map<String, Object?>;
    final containers = podSpec['containers']! as List<Object?>;
    expect(containers, hasLength(2));
    final gateway = containers.cast<Map<String, Object?>>().singleWhere(
      (container) => container['name'] == 'session-gateway',
    );
    expect(gateway['command'], const <String>[
      '/app/workspace-remote-session-gateway',
    ]);
    expect(jsonEncode(gateway), isNot(contains('capability.jwt')));
  });

  test(
    'projected Kubernetes token rotates only inside its trusted root',
    () async {
      final root = Directory.systemTemp.createTempSync('workspace-kube-token-');
      final outside = File('${root.parent.path}/outside-${root.path.hashCode}')
        ..writeAsStringSync('z' * 64);
      try {
        final data = Directory('${root.path}/..data')..createSync();
        final token = File('${data.path}/token')..writeAsStringSync('a' * 64);
        final projected = Link('${root.path}/token')..createSync(token.path);
        final source = RotatingKubernetesBearerTokenFile(
          file: File(projected.path),
          trustedRoot: root,
        );
        expect(await source.read(), 'a' * 64);
        token.writeAsStringSync('b' * 64);
        expect(await source.read(), 'b' * 64);

        final escaped = Link('${root.path}/escaped')..createSync(outside.path);
        final rejected = RotatingKubernetesBearerTokenFile(
          file: File(escaped.path),
          trustedRoot: root,
        );
        await expectLater(rejected.read(), throwsStateError);
      } finally {
        root.deleteSync(recursive: true);
        if (outside.existsSync()) outside.deleteSync();
      }
    },
  );
}

RemoteAssignment _assignment(
  RemoteTargetKind target, {
  RemoteRunMode mode = RemoteRunMode.batch,
}) {
  final now = DateTime.utc(2026, 8, 9, 12);
  final request = RemoteExecutionRequest(
    tenantId: 'tenant-a',
    id: 'request-001',
    workspaceId: 'workspace-a',
    requestedBy: 'principal-a',
    target: target,
    mode: mode,
    interactiveTransport: mode == RemoteRunMode.batch
        ? RemoteInteractiveTransport.none
        : target == RemoteTargetKind.web
        ? RemoteInteractiveTransport.webDirect
        : RemoteInteractiveTransport.scrcpyH264Control,
    priority: 50,
    maximumDurationSeconds: 300,
    artifacts: <RemoteArtifactInput>[
      RemoteArtifactInput(
        role: target == RemoteTargetKind.web ? 'webBuild' : 'androidApk',
        digest: Digest.semantic('executable'),
        size: 1024,
        mediaType: target == RemoteTargetKind.web
            ? 'application/zip'
            : 'application/vnd.android.package-archive',
      ),
    ],
    requestedAt: now,
  );
  final plan = RemoteExecutionPlan(
    tenantId: 'tenant-a',
    runId: 'run-001',
    requestDigest: request.digest,
    target: target,
    mode: request.mode,
    interactiveTransport: request.interactiveTransport,
    artifacts: request.artifacts,
    executionFingerprintDigest: Digest.semantic('fingerprint'),
    containmentPolicyDigest: Digest.semantic('containment'),
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 5)),
    nonce: 'nonce-001',
    deviceImage: target == RemoteTargetKind.androidEmulator
        ? DeviceImageDescriptor(
            id: 'android-api-35',
            imageDigest: Digest.semantic('android-image'),
            apiLevel: 35,
            abi: 'x86_64',
            renderer: 'swiftshader_indirect',
            kvmRequired: true,
          )
        : null,
  );
  final run = RemoteRun(
    tenantId: 'tenant-a',
    id: plan.runId,
    requestDigest: request.digest,
    planDigest: plan.digest,
    target: target,
    mode: request.mode,
    state: RemoteRunState.scheduled,
    attempt: 1,
    createdAt: now,
    updatedAt: now,
    workerId: 'worker-001',
  );
  final lease = RemoteLease(
    tenantId: 'tenant-a',
    runId: plan.runId,
    workerId: 'worker-001',
    tokenId: 'token-001',
    generation: 1,
    acquiredAt: now,
    heartbeatAt: now,
    expiresAt: now.add(const Duration(minutes: 1)),
  );
  return RemoteAssignment(
    run: run,
    lease: lease,
    signedPlan: SignedRemoteExecutionPlan(
      plan: plan,
      compactSignature: 'signed-plan',
      signerKeyId: 'key-001',
    ),
    capabilityToken: 'capability-secret',
  );
}
