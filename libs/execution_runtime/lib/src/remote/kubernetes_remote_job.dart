import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

final class KubernetesRemoteJobConfiguration {
  KubernetesRemoteJobConfiguration({
    required this.webWorkerImage,
    required this.androidWorkerImage,
    required this.controlPlaneOrigin,
    required this.artifactOrigin,
    required this.gatewayOrigin,
    required this.trustedJwksJson,
    required this.androidImageDigest,
    required this.androidScrcpyServerDigest,
    required List<String> allowedStudioOrigins,
    required List<String> allowedEgressCidrs,
    this.androidRuntimeClass = 'workspace-android-kvm',
    this.androidKvmResource = 'devices.kubevirt.io/kvm',
    this.chromiumExecutable = '/usr/bin/chromium',
    this.androidSdkRoot = '/opt/android-sdk',
    this.androidAvdName = 'workspace-api-35',
    this.androidScrcpyServerPath = '/opt/scrcpy/scrcpy-server.jar',
    this.androidScrcpyVersion = '4.0',
    this.androidScrcpyPort = 27185,
    this.gatewayPort = 8443,
    this.sessionGatewayName = 'workspace-public',
    this.sessionGatewayNamespace = 'workspace-system',
  }) : allowedStudioOrigins = List<String>.unmodifiable(allowedStudioOrigins),
       allowedEgressCidrs = List<String>.unmodifiable(allowedEgressCidrs) {
    for (final image in <String>[webWorkerImage, androidWorkerImage]) {
      if (!RegExp(r'^.+@sha256:[0-9a-f]{64}$').hasMatch(image)) {
        throw ArgumentError(
          'remote worker images must be pinned by OCI digest',
        );
      }
    }
    for (final uri in <Uri>[
      controlPlaneOrigin,
      artifactOrigin,
      gatewayOrigin,
    ]) {
      if (uri.scheme != 'https' || uri.origin == 'null') {
        throw ArgumentError('remote endpoints must use HTTPS origins');
      }
    }
    if (this.allowedEgressCidrs.isEmpty ||
        this.allowedEgressCidrs.any((cidr) => !_cidr.hasMatch(cidr))) {
      throw ArgumentError('remote egress requires explicit CIDRs');
    }
    if (this.allowedStudioOrigins.isEmpty ||
        this.allowedStudioOrigins.any((origin) {
          final uri = Uri.tryParse(origin);
          return uri == null || uri.scheme != 'https' || uri.origin != origin;
        })) {
      throw ArgumentError('remote sessions require exact HTTPS Studio origins');
    }
    if (chromiumExecutable.isEmpty ||
        androidSdkRoot.isEmpty ||
        androidAvdName.isEmpty ||
        androidScrcpyServerPath.isEmpty ||
        !RegExp(
          r'^[0-9]+\.[0-9]+(?:\.[0-9]+)?$',
        ).hasMatch(androidScrcpyVersion) ||
        androidScrcpyPort < 1024 ||
        androidScrcpyPort > 65535 ||
        gatewayPort < 1 ||
        gatewayPort > 65535) {
      throw ArgumentError('remote runtime paths or gateway port are invalid');
    }
    if (!_kubernetesName.hasMatch(sessionGatewayName) ||
        !_kubernetesName.hasMatch(sessionGatewayNamespace)) {
      throw ArgumentError('remote Gateway API parent reference is invalid');
    }
    final jwks = jsonDecode(trustedJwksJson);
    if (jwks is! Map<String, Object?> ||
        jwks['keys'] is! List<Object?> ||
        (jwks['keys']! as List<Object?>).isEmpty ||
        trustedJwksJson.contains(RegExp(r'"(?:d|p|q|dp|dq|qi|k)"\s*:'))) {
      throw ArgumentError('worker trust bundle must contain public JWKs only');
    }
  }

  static final RegExp _cidr = RegExp(
    r'^(?:[0-9]{1,3}\.){3}[0-9]{1,3}/(?:[0-9]|[12][0-9]|3[0-2])$',
  );
  static final RegExp _kubernetesName = RegExp(
    r'^[a-z0-9](?:[-a-z0-9]{0,61}[a-z0-9])?$',
  );

  final String webWorkerImage;
  final String androidWorkerImage;
  final Uri controlPlaneOrigin;
  final Uri artifactOrigin;
  final Uri gatewayOrigin;
  final String trustedJwksJson;
  final Digest androidImageDigest;
  final Digest androidScrcpyServerDigest;
  final List<String> allowedStudioOrigins;
  final List<String> allowedEgressCidrs;
  final String androidRuntimeClass;
  final String androidKvmResource;
  final String chromiumExecutable;
  final String androidSdkRoot;
  final String androidAvdName;
  final String androidScrcpyServerPath;
  final String androidScrcpyVersion;
  final int androidScrcpyPort;
  final int gatewayPort;
  final String sessionGatewayName;
  final String sessionGatewayNamespace;
}

final class KubernetesRemoteJobBundle {
  const KubernetesRemoteJobBundle({
    required this.namespace,
    required this.runId,
    required this.publicManifests,
    required this._credentialManifest,
  });

  final String namespace;
  final String runId;
  final List<Map<String, Object?>> publicManifests;
  final Map<String, Object?> _credentialManifest;

  Iterable<Map<String, Object?>> get launchManifests sync* {
    yield publicManifests.first;
    yield _credentialManifest;
    yield* publicManifests.skip(1);
  }
}

abstract interface class RemoteJobLauncher {
  Future<void> launch(KubernetesRemoteJobBundle bundle);

  Future<void> cleanup(String namespace);
}

final class KubernetesRemoteJobBuilder {
  const KubernetesRemoteJobBuilder(this.configuration);

  final KubernetesRemoteJobConfiguration configuration;

  KubernetesRemoteJobBundle build(RemoteAssignment assignment) {
    final plan = assignment.signedPlan.plan;
    if (assignment.run.id != plan.runId ||
        assignment.lease.runId != plan.runId ||
        assignment.run.tenantId != plan.tenantId) {
      throw ArgumentError('remote assignment bindings are inconsistent');
    }
    final namespace = remoteNamespaceFor(plan.tenantId, plan.runId);
    final suffix = namespace.substring('workspace-run-'.length);
    final labels = <String, String>{
      'app.kubernetes.io/name': 'workspace-remote-worker',
      'io.github.jantunesmessias/run': suffix,
      'io.github.jantunesmessias/tenant-hash': sha256
          .convert(utf8.encode(plan.tenantId))
          .toString()
          .substring(0, 16),
    };
    final isAndroid = plan.target == RemoteTargetKind.androidEmulator;
    final namespaceManifest = <String, Object?>{
      'apiVersion': 'v1',
      'kind': 'Namespace',
      'metadata': <String, Object?>{
        'name': namespace,
        'labels': <String, Object?>{
          ...labels,
          'pod-security.kubernetes.io/enforce': 'restricted',
          'pod-security.kubernetes.io/audit': 'restricted',
          'pod-security.kubernetes.io/warn': 'restricted',
        },
      },
    };
    final credential = <String, Object?>{
      'apiVersion': 'v1',
      'kind': 'Secret',
      'metadata': <String, Object?>{
        'name': 'worker-capability',
        'namespace': namespace,
        'labels': labels,
      },
      'type': 'Opaque',
      'immutable': true,
      'data': <String, Object?>{
        'capability.jwt': base64Encode(utf8.encode(assignment.capabilityToken)),
        'plan.jwt': base64Encode(
          utf8.encode(assignment.signedPlan.compactSignature),
        ),
      },
    };
    final serviceAccount = <String, Object?>{
      'apiVersion': 'v1',
      'kind': 'ServiceAccount',
      'metadata': <String, Object?>{
        'name': 'worker',
        'namespace': namespace,
        'labels': labels,
      },
      'automountServiceAccountToken': false,
    };
    final trust = <String, Object?>{
      'apiVersion': 'v1',
      'kind': 'ConfigMap',
      'metadata': <String, Object?>{
        'name': 'worker-trust',
        'namespace': namespace,
        'labels': labels,
      },
      'immutable': true,
      'data': <String, Object?>{'jwks.json': configuration.trustedJwksJson},
    };
    final job = <String, Object?>{
      'apiVersion': 'batch/v1',
      'kind': 'Job',
      'metadata': <String, Object?>{
        'name': 'worker',
        'namespace': namespace,
        'labels': labels,
      },
      'spec': <String, Object?>{
        'backoffLimit': 0,
        'activeDeadlineSeconds': plan.expiresAt
            .difference(plan.issuedAt)
            .inSeconds,
        'ttlSecondsAfterFinished': 300,
        'template': <String, Object?>{
          'metadata': <String, Object?>{'labels': labels},
          'spec': <String, Object?>{
            'serviceAccountName': 'worker',
            'automountServiceAccountToken': false,
            'restartPolicy': 'Never',
            if (isAndroid)
              'runtimeClassName': configuration.androidRuntimeClass,
            if (isAndroid)
              'nodeSelector': <String, String>{
                'io.github.jantunesmessias/android-kvm': 'true',
                'io.github.jantunesmessias/android-image': configuration
                    .androidImageDigest
                    .value
                    .substring(7),
              },
            'securityContext': const <String, Object?>{
              'runAsNonRoot': true,
              'seccompProfile': <String, Object?>{'type': 'RuntimeDefault'},
            },
            'containers': <Object?>[
              <String, Object?>{
                'name': 'worker',
                'image': isAndroid
                    ? configuration.androidWorkerImage
                    : configuration.webWorkerImage,
                'imagePullPolicy': 'IfNotPresent',
                'args': <String>[
                  '--plan-file=/var/run/workspace/plan.jwt',
                  '--capability-file=/var/run/workspace/capability.jwt',
                  '--jwks-file=/etc/workspace-trust/jwks.json',
                ],
                'env': <Object?>[
                  _env('REMOTE_WORKER_ID', assignment.lease.workerId),
                  _env('REMOTE_RUN_ID', plan.runId),
                  if (!isAndroid)
                    _env('CHROMIUM_PATH', configuration.chromiumExecutable),
                  if (isAndroid)
                    _env(
                      'ANDROID_IMAGE_DIGEST',
                      configuration.androidImageDigest.value,
                    ),
                  if (isAndroid)
                    _env('ANDROID_SDK_ROOT', configuration.androidSdkRoot),
                  if (isAndroid)
                    _env('ANDROID_AVD', configuration.androidAvdName),
                  if (isAndroid)
                    _env(
                      'SCRCPY_SERVER_PATH',
                      configuration.androidScrcpyServerPath,
                    ),
                  if (isAndroid)
                    _env(
                      'SCRCPY_SERVER_DIGEST',
                      configuration.androidScrcpyServerDigest.value,
                    ),
                  if (isAndroid)
                    _env('SCRCPY_VERSION', configuration.androidScrcpyVersion),
                  if (isAndroid)
                    _env(
                      'SCRCPY_PORT',
                      configuration.androidScrcpyPort.toString(),
                    ),
                  if (isAndroid)
                    _env('GATEWAY_PORT', configuration.gatewayPort.toString()),
                  <String, Object?>{
                    'name': 'REMOTE_WORKER_NAMESPACE',
                    'valueFrom': const <String, Object?>{
                      'fieldRef': <String, Object?>{
                        'fieldPath': 'metadata.namespace',
                      },
                    },
                  },
                  _env(
                    'CONTROL_PLANE_ORIGIN',
                    configuration.controlPlaneOrigin.origin,
                  ),
                  _env('ARTIFACT_ORIGIN', configuration.artifactOrigin.origin),
                  _env('GATEWAY_ORIGIN', configuration.gatewayOrigin.origin),
                  if (plan.mode == RemoteRunMode.interactive)
                    _env(
                      'SESSION_GATEWAY_URL',
                      'ws://127.0.0.1:27183/v1/sessions/${plan.runId}/worker',
                    ),
                  if (!isAndroid && plan.mode == RemoteRunMode.interactive)
                    _env('REMOTE_WEB_INTERACTIVE_PORT', '27184'),
                ],
                'securityContext': const <String, Object?>{
                  'allowPrivilegeEscalation': false,
                  'capabilities': <String, Object?>{
                    'drop': <String>['ALL'],
                  },
                  'readOnlyRootFilesystem': true,
                },
                'resources': <String, Object?>{
                  'requests': <String, Object?>{
                    'cpu': isAndroid ? '2' : '500m',
                    'memory': isAndroid ? '4Gi' : '512Mi',
                    if (isAndroid) configuration.androidKvmResource: '1',
                  },
                  'limits': <String, Object?>{
                    'cpu': isAndroid ? '4' : '2',
                    'memory': isAndroid ? '8Gi' : '2Gi',
                    if (isAndroid) configuration.androidKvmResource: '1',
                  },
                },
                'volumeMounts': const <Object?>[
                  <String, Object?>{
                    'name': 'capability',
                    'mountPath': '/var/run/workspace',
                    'readOnly': true,
                  },
                  <String, Object?>{'name': 'work', 'mountPath': '/work'},
                  <String, Object?>{'name': 'tmp', 'mountPath': '/tmp'},
                  <String, Object?>{
                    'name': 'trust',
                    'mountPath': '/etc/workspace-trust',
                    'readOnly': true,
                  },
                ],
              },
              if (plan.mode == RemoteRunMode.interactive)
                <String, Object?>{
                  'name': 'session-gateway',
                  'image': isAndroid
                      ? configuration.androidWorkerImage
                      : configuration.webWorkerImage,
                  'imagePullPolicy': 'IfNotPresent',
                  'command': const <String>[
                    '/app/workspace-remote-session-gateway',
                  ],
                  'ports': const <Object?>[
                    <String, Object?>{
                      'name': 'session',
                      'containerPort': 27183,
                      'protocol': 'TCP',
                    },
                  ],
                  'env': <Object?>[
                    _env('PORT', '27183'),
                    _env('REMOTE_RUN_ID', plan.runId),
                    _env('SESSION_DEADLINE', plan.expiresAt.toIso8601String()),
                    _env(
                      'STUDIO_ALLOWED_ORIGINS',
                      configuration.allowedStudioOrigins.join(','),
                    ),
                    _env(
                      'REMOTE_SESSION_JWKS_FILE',
                      '/etc/workspace-trust/jwks.json',
                    ),
                    if (!isAndroid)
                      _env(
                        'REMOTE_WEB_TARGET_ORIGIN',
                        'http://127.0.0.1:27184',
                      ),
                  ],
                  'securityContext': const <String, Object?>{
                    'allowPrivilegeEscalation': false,
                    'capabilities': <String, Object?>{
                      'drop': <String>['ALL'],
                    },
                    'readOnlyRootFilesystem': true,
                    'runAsNonRoot': true,
                    'runAsUser': 65532,
                    'runAsGroup': 65532,
                  },
                  'resources': const <String, Object?>{
                    'requests': <String, Object?>{
                      'cpu': '50m',
                      'memory': '64Mi',
                    },
                    'limits': <String, Object?>{
                      'cpu': '500m',
                      'memory': '256Mi',
                    },
                  },
                  'volumeMounts': const <Object?>[
                    <String, Object?>{
                      'name': 'trust',
                      'mountPath': '/etc/workspace-trust',
                      'readOnly': true,
                    },
                    <String, Object?>{'name': 'tmp', 'mountPath': '/tmp'},
                  ],
                },
            ],
            'volumes': <Object?>[
              const <String, Object?>{
                'name': 'capability',
                'secret': <String, Object?>{
                  'secretName': 'worker-capability',
                  'defaultMode': 256,
                },
              },
              <String, Object?>{
                'name': 'work',
                'emptyDir': <String, Object?>{
                  'sizeLimit': isAndroid ? '16Gi' : '4Gi',
                },
              },
              const <String, Object?>{
                'name': 'tmp',
                'emptyDir': <String, Object?>{'sizeLimit': '1Gi'},
              },
              const <String, Object?>{
                'name': 'trust',
                'configMap': <String, Object?>{
                  'name': 'worker-trust',
                  'defaultMode': 256,
                },
              },
            ],
          },
        },
      },
    };
    final networkPolicy = <String, Object?>{
      'apiVersion': 'networking.k8s.io/v1',
      'kind': 'NetworkPolicy',
      'metadata': <String, Object?>{
        'name': 'worker-default-deny',
        'namespace': namespace,
        'labels': labels,
      },
      'spec': <String, Object?>{
        'podSelector': const <String, Object?>{},
        'policyTypes': const <String>['Ingress', 'Egress'],
        'ingress': plan.mode == RemoteRunMode.interactive
            ? <Object?>[
                <String, Object?>{
                  'from': const <Object?>[
                    <String, Object?>{
                      'namespaceSelector': <String, Object?>{
                        'matchLabels': <String, String>{
                          'io.github.jantunesmessias/session-gateway': 'true',
                        },
                      },
                    },
                  ],
                  'ports': const <Object?>[
                    <String, Object?>{'protocol': 'TCP', 'port': 27183},
                  ],
                },
              ]
            : const <Object?>[],
        'egress': <Object?>[
          for (final cidr in configuration.allowedEgressCidrs)
            <String, Object?>{
              'to': <Object?>[
                <String, Object?>{
                  'ipBlock': <String, String>{'cidr': cidr},
                },
              ],
              'ports': const <Object?>[
                <String, Object?>{'protocol': 'TCP', 'port': 443},
                <String, Object?>{'protocol': 'UDP', 'port': 53},
                <String, Object?>{'protocol': 'TCP', 'port': 53},
              ],
            },
        ],
      },
    };
    final sessionService = <String, Object?>{
      'apiVersion': 'v1',
      'kind': 'Service',
      'metadata': <String, Object?>{
        'name': 'session-gateway',
        'namespace': namespace,
        'labels': labels,
      },
      'spec': <String, Object?>{
        'type': 'ClusterIP',
        'selector': labels,
        'ports': const <Object?>[
          <String, Object?>{
            'name': 'session',
            'port': 27183,
            'targetPort': 'session',
            'protocol': 'TCP',
          },
        ],
      },
    };
    final sessionRoute = <String, Object?>{
      'apiVersion': 'gateway.networking.k8s.io/v1',
      'kind': 'HTTPRoute',
      'metadata': <String, Object?>{
        'name': 'session-gateway',
        'namespace': namespace,
        'labels': labels,
      },
      'spec': <String, Object?>{
        'parentRefs': <Object?>[
          <String, Object?>{
            'name': configuration.sessionGatewayName,
            'namespace': configuration.sessionGatewayNamespace,
          },
        ],
        'hostnames': <String>[configuration.gatewayOrigin.host],
        'rules': <Object?>[
          <String, Object?>{
            'matches': <Object?>[
              <String, Object?>{
                'path': <String, Object?>{
                  'type': 'PathPrefix',
                  'value': '/v1/sessions/${plan.runId}',
                },
              },
            ],
            'backendRefs': const <Object?>[
              <String, Object?>{'name': 'session-gateway', 'port': 27183},
            ],
          },
        ],
      },
    };
    return KubernetesRemoteJobBundle(
      namespace: namespace,
      runId: plan.runId,
      publicManifests: <Map<String, Object?>>[
        namespaceManifest,
        serviceAccount,
        trust,
        networkPolicy,
        if (plan.mode == RemoteRunMode.interactive) sessionService,
        if (plan.mode == RemoteRunMode.interactive) sessionRoute,
        job,
      ],
      credentialManifest: credential,
    );
  }

  Map<String, Object?> _env(String name, String value) => <String, Object?>{
    'name': name,
    'value': value,
  };
}

final class KubernetesApiRemoteJobLauncher implements RemoteJobLauncher {
  KubernetesApiRemoteJobLauncher({
    required this.apiServer,
    required this.bearerTokenProvider,
    HttpClient? client,
  }) : _client = client ?? HttpClient() {
    if (apiServer.scheme != 'https' || apiServer.origin == 'null') {
      throw ArgumentError('Kubernetes API server must use HTTPS');
    }
  }

  final Uri apiServer;
  final Future<String> Function() bearerTokenProvider;
  final HttpClient _client;

  @override
  Future<void> launch(KubernetesRemoteJobBundle bundle) async {
    for (final manifest in bundle.launchManifests) {
      final kind = manifest['kind']! as String;
      final path = switch (kind) {
        'Namespace' => '/api/v1/namespaces',
        'ServiceAccount' =>
          '/api/v1/namespaces/${bundle.namespace}/serviceaccounts',
        'Secret' => '/api/v1/namespaces/${bundle.namespace}/secrets',
        'ConfigMap' => '/api/v1/namespaces/${bundle.namespace}/configmaps',
        'NetworkPolicy' =>
          '/apis/networking.k8s.io/v1/namespaces/${bundle.namespace}/networkpolicies',
        'Service' => '/api/v1/namespaces/${bundle.namespace}/services',
        'HTTPRoute' =>
          '/apis/gateway.networking.k8s.io/v1/namespaces/${bundle.namespace}/httproutes',
        'Job' => '/apis/batch/v1/namespaces/${bundle.namespace}/jobs',
        _ => throw StateError('unsupported Kubernetes manifest kind $kind'),
      };
      await _request('POST', path, body: manifest);
    }
  }

  @override
  Future<void> cleanup(String namespace) async {
    if (!RegExp(r'^workspace-run-[0-9a-f]{16}$').hasMatch(namespace)) {
      throw ArgumentError('refusing to delete an unmanaged namespace');
    }
    final path = '/api/v1/namespaces/$namespace';
    final status = await _request(
      'DELETE',
      path,
      body: const <String, Object?>{
        'apiVersion': 'v1',
        'kind': 'DeleteOptions',
        'propagationPolicy': 'Foreground',
      },
      acceptedStatusCodes: const <int>{200, 202, 404},
    );
    if (status == 404) return;
    final deadline = DateTime.now().toUtc().add(const Duration(seconds: 90));
    while (DateTime.now().toUtc().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final observed = await _request(
        'GET',
        path,
        acceptedStatusCodes: const <int>{200, 404},
      );
      if (observed == 404) return;
    }
    throw TimeoutException('Kubernetes namespace cleanup did not converge');
  }

  Future<int> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Set<int> acceptedStatusCodes = const <int>{200, 201},
  }) async {
    final bearerToken = await bearerTokenProvider();
    if (!RegExp(r'^[A-Za-z0-9._~-]{32,16384}$').hasMatch(bearerToken)) {
      throw StateError('Kubernetes bearer token is invalid');
    }
    final request = await _client.openUrl(method, apiServer.resolve(path));
    request
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    if (body != null) {
      request
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (!acceptedStatusCodes.contains(response.statusCode)) {
      final message = await utf8.decoder.bind(response).join();
      throw HttpException(
        'Kubernetes API returned ${response.statusCode}: '
        '${message.substring(0, message.length.clamp(0, 2048))}',
      );
    }
    await response.drain<void>();
    return response.statusCode;
  }

  void close() => _client.close(force: true);
}

/// Reads every API request from a projected service-account token, allowing
/// kubelet rotation while preventing a configured path from escaping its
/// trusted volume through symlinks.
final class RotatingKubernetesBearerTokenFile {
  RotatingKubernetesBearerTokenFile({
    required this.file,
    required this.trustedRoot,
  }) {
    if (!p.isAbsolute(file.path) || !p.isAbsolute(trustedRoot.path)) {
      throw ArgumentError('Kubernetes token paths must be absolute');
    }
  }

  final File file;
  final Directory trustedRoot;

  Future<String> read() async {
    final before = _resolveTrustedFile();
    final document = await File(before).readAsString();
    final after = _resolveTrustedFile();
    if (before != after) {
      throw StateError('Kubernetes token rotated during a read');
    }
    final token = document.trim();
    if (document.length > 16385 ||
        !RegExp(r'^[A-Za-z0-9._~-]{32,16384}$').hasMatch(token)) {
      throw StateError('Kubernetes token file is invalid');
    }
    return token;
  }

  String _resolveTrustedFile() {
    if (!trustedRoot.existsSync()) {
      throw StateError('Kubernetes token root is missing');
    }
    final root = p.normalize(trustedRoot.resolveSymbolicLinksSync());
    final resolved = p.normalize(file.resolveSymbolicLinksSync());
    final stat = File(resolved).statSync();
    if (!p.isWithin(root, resolved) ||
        stat.type != FileSystemEntityType.file ||
        stat.size < 32 ||
        stat.size > 16385) {
      throw StateError('Kubernetes token escaped its trusted root');
    }
    return resolved;
  }
}

String remoteNamespaceFor(String tenantId, String runId) {
  if (tenantId.isEmpty || runId.isEmpty) {
    throw ArgumentError('remote namespace identity must not be empty');
  }
  final suffix = sha256
      .convert(utf8.encode('$tenantId:$runId'))
      .toString()
      .substring(0, 16);
  return 'workspace-run-$suffix';
}
