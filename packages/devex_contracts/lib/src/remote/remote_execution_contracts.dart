import '../digest.dart';
import '../hosted/hosted_contracts.dart';

enum RemoteTargetKind { web, androidEmulator }

enum RemoteRunMode { batch, interactive }

enum RemoteInteractiveTransport {
  webDirect,
  scrcpyH264Control,
  periodicScreenshotReadOnly,
  none,
}

enum RemoteRunState {
  queued,
  scheduled,
  provisioning,
  running,
  uploading,
  succeeded,
  failed,
  cancelled,
  unknown,
}

final class RemoteArtifactInput {
  RemoteArtifactInput({
    required this.role,
    required this.digest,
    required this.size,
    required this.mediaType,
  }) {
    if (!const <String>{
      'webBuild',
      'androidApk',
      'interactionScript',
      'gatewayPlan',
    }.contains(role)) {
      throw const FormatException('RemoteArtifactInput.role is invalid');
    }
    if (size < 1 || size > 2 * 1024 * 1024 * 1024) {
      throw const FormatException('RemoteArtifactInput.size is invalid');
    }
    _remoteText(mediaType, 'RemoteArtifactInput.mediaType', 255);
  }

  final String role;
  final Digest digest;
  final int size;
  final String mediaType;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'digest': digest.value,
    'size': size,
    'mediaType': mediaType,
  };

  factory RemoteArtifactInput.fromJson(Object? value) {
    final json = _remoteObject(value, 'RemoteArtifactInput');
    _remoteOnly(json, const <String>{
      'role',
      'digest',
      'size',
      'mediaType',
    }, 'RemoteArtifactInput');
    return RemoteArtifactInput(
      role: _remoteString(json, 'role', 'RemoteArtifactInput'),
      digest: Digest(_remoteString(json, 'digest', 'RemoteArtifactInput')),
      size: _remoteInt(json, 'size', 'RemoteArtifactInput'),
      mediaType: _remoteString(json, 'mediaType', 'RemoteArtifactInput'),
    );
  }
}

final class DeviceImageDescriptor {
  DeviceImageDescriptor({
    required this.id,
    required this.imageDigest,
    required this.apiLevel,
    required this.abi,
    required this.renderer,
    required this.kvmRequired,
  }) {
    _remoteId(id, 'DeviceImageDescriptor.id');
    if (apiLevel < 21 || apiLevel > 100) {
      throw const FormatException('DeviceImageDescriptor.apiLevel is invalid');
    }
    _remoteText(abi, 'DeviceImageDescriptor.abi', 64);
    _remoteText(renderer, 'DeviceImageDescriptor.renderer', 64);
  }

  final String id;
  final Digest imageDigest;
  final int apiLevel;
  final String abi;
  final String renderer;
  final bool kvmRequired;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'imageDigest': imageDigest.value,
    'apiLevel': apiLevel,
    'abi': abi,
    'renderer': renderer,
    'kvmRequired': kvmRequired,
  };

  factory DeviceImageDescriptor.fromJson(Object? value) {
    final json = _remoteObject(value, 'DeviceImageDescriptor');
    _remoteOnly(json, const <String>{
      'id',
      'imageDigest',
      'apiLevel',
      'abi',
      'renderer',
      'kvmRequired',
    }, 'DeviceImageDescriptor');
    return DeviceImageDescriptor(
      id: _remoteString(json, 'id', 'DeviceImageDescriptor'),
      imageDigest: Digest(
        _remoteString(json, 'imageDigest', 'DeviceImageDescriptor'),
      ),
      apiLevel: _remoteInt(json, 'apiLevel', 'DeviceImageDescriptor'),
      abi: _remoteString(json, 'abi', 'DeviceImageDescriptor'),
      renderer: _remoteString(json, 'renderer', 'DeviceImageDescriptor'),
      kvmRequired: _remoteBool(json, 'kvmRequired', 'DeviceImageDescriptor'),
    );
  }
}

final class RemoteExecutionRequest {
  RemoteExecutionRequest({
    required this.tenantId,
    required this.id,
    required this.workspaceId,
    required this.requestedBy,
    required this.target,
    required this.mode,
    required this.interactiveTransport,
    required this.priority,
    required this.maximumDurationSeconds,
    required List<RemoteArtifactInput> artifacts,
    required this.requestedAt,
  }) : artifacts = List<RemoteArtifactInput>.unmodifiable(artifacts) {
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('tenantId', tenantId),
      MapEntry<String, String>('id', id),
      MapEntry<String, String>('workspaceId', workspaceId),
      MapEntry<String, String>('requestedBy', requestedBy),
    ]) {
      _remoteId(entry.value, 'RemoteExecutionRequest.${entry.key}');
    }
    if (priority < 0 ||
        priority > 100 ||
        maximumDurationSeconds < 30 ||
        maximumDurationSeconds > 3600) {
      throw const FormatException('RemoteExecutionRequest limits are invalid');
    }
    _remoteTransport(
      target: target,
      mode: mode,
      transport: interactiveTransport,
      path: 'RemoteExecutionRequest.interactiveTransport',
    );
    if (this.artifacts.isEmpty ||
        this.artifacts.map((item) => item.role).toSet().length !=
            this.artifacts.length ||
        this.artifacts.map((item) => item.digest).toSet().length !=
            this.artifacts.length) {
      throw const FormatException(
        'RemoteExecutionRequest artifacts are invalid',
      );
    }
    final executableRole = target == RemoteTargetKind.web
        ? 'webBuild'
        : 'androidApk';
    if (!this.artifacts.any((item) => item.role == executableRole) ||
        this.artifacts.any(
          (item) => item.role == 'webBuild' || item.role == 'androidApk'
              ? item.role != executableRole
              : false,
        )) {
      throw const FormatException(
        'RemoteExecutionRequest must contain one prebuilt target artifact',
      );
    }
    _remoteUtc(requestedAt, 'RemoteExecutionRequest.requestedAt');
  }

  final String tenantId;
  final String id;
  final String workspaceId;
  final String requestedBy;
  final RemoteTargetKind target;
  final RemoteRunMode mode;
  final RemoteInteractiveTransport interactiveTransport;
  final int priority;
  final int maximumDurationSeconds;
  final List<RemoteArtifactInput> artifacts;
  final DateTime requestedAt;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'RemoteExecutionRequest',
    'tenantId': tenantId,
    'id': id,
    'workspaceId': workspaceId,
    'requestedBy': requestedBy,
    'target': target.name,
    'mode': mode.name,
    'interactiveTransport': interactiveTransport.name,
    'priority': priority,
    'maximumDurationSeconds': maximumDurationSeconds,
    'artifacts': <Object?>[for (final item in artifacts) item.toJson()],
    'requestedAt': requestedAt.toIso8601String(),
  };

  factory RemoteExecutionRequest.fromJson(Object? value) {
    final json = _remoteObject(value, 'RemoteExecutionRequest');
    _remoteOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'tenantId',
      'id',
      'workspaceId',
      'requestedBy',
      'target',
      'mode',
      'interactiveTransport',
      'priority',
      'maximumDurationSeconds',
      'artifacts',
      'requestedAt',
    }, 'RemoteExecutionRequest');
    _remoteHeader(json, 'RemoteExecutionRequest');
    return RemoteExecutionRequest(
      tenantId: _remoteString(json, 'tenantId', 'RemoteExecutionRequest'),
      id: _remoteString(json, 'id', 'RemoteExecutionRequest'),
      workspaceId: _remoteString(json, 'workspaceId', 'RemoteExecutionRequest'),
      requestedBy: _remoteString(json, 'requestedBy', 'RemoteExecutionRequest'),
      target: _remoteEnum(
        RemoteTargetKind.values,
        _remoteString(json, 'target', 'RemoteExecutionRequest'),
        'RemoteExecutionRequest.target',
      ),
      mode: _remoteEnum(
        RemoteRunMode.values,
        _remoteString(json, 'mode', 'RemoteExecutionRequest'),
        'RemoteExecutionRequest.mode',
      ),
      interactiveTransport: _remoteEnum(
        RemoteInteractiveTransport.values,
        _remoteString(json, 'interactiveTransport', 'RemoteExecutionRequest'),
        'RemoteExecutionRequest.interactiveTransport',
      ),
      priority: _remoteInt(json, 'priority', 'RemoteExecutionRequest'),
      maximumDurationSeconds: _remoteInt(
        json,
        'maximumDurationSeconds',
        'RemoteExecutionRequest',
      ),
      artifacts: _remoteList(
        json['artifacts'],
        'RemoteExecutionRequest.artifacts',
      ).map(RemoteArtifactInput.fromJson).toList(growable: false),
      requestedAt: _remoteDate(json, 'requestedAt', 'RemoteExecutionRequest'),
    );
  }
}

final class RemoteExecutionPlan {
  RemoteExecutionPlan({
    required this.tenantId,
    required this.runId,
    required this.requestDigest,
    required this.target,
    required this.mode,
    required this.interactiveTransport,
    required List<RemoteArtifactInput> artifacts,
    required this.executionFingerprintDigest,
    required this.containmentPolicyDigest,
    required this.issuedAt,
    required this.expiresAt,
    required this.nonce,
    this.deviceImage,
  }) : artifacts = List<RemoteArtifactInput>.unmodifiable(artifacts) {
    _remoteId(tenantId, 'RemoteExecutionPlan.tenantId');
    _remoteId(runId, 'RemoteExecutionPlan.runId');
    _remoteId(nonce, 'RemoteExecutionPlan.nonce');
    if (this.artifacts.isEmpty ||
        this.artifacts.map((item) => item.digest).toSet().length !=
            this.artifacts.length ||
        this.artifacts.map((item) => item.role).toSet().length !=
            this.artifacts.length) {
      throw const FormatException('RemoteExecutionPlan artifacts are invalid');
    }
    if ((target == RemoteTargetKind.androidEmulator) != (deviceImage != null)) {
      throw const FormatException(
        'RemoteExecutionPlan device image is invalid',
      );
    }
    _remoteTransport(
      target: target,
      mode: mode,
      transport: interactiveTransport,
      path: 'RemoteExecutionPlan.interactiveTransport',
    );
    _remoteUtc(issuedAt, 'RemoteExecutionPlan.issuedAt');
    _remoteUtc(expiresAt, 'RemoteExecutionPlan.expiresAt');
    if (!expiresAt.isAfter(issuedAt) ||
        expiresAt.difference(issuedAt) > const Duration(hours: 1)) {
      throw const FormatException('RemoteExecutionPlan expiry is invalid');
    }
  }

  final String tenantId;
  final String runId;
  final Digest requestDigest;
  final RemoteTargetKind target;
  final RemoteRunMode mode;
  final RemoteInteractiveTransport interactiveTransport;
  final List<RemoteArtifactInput> artifacts;
  List<Digest> get artifactDigests =>
      List<Digest>.unmodifiable(artifacts.map((item) => item.digest));
  final Digest executionFingerprintDigest;
  final Digest containmentPolicyDigest;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String nonce;
  final DeviceImageDescriptor? deviceImage;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'RemoteExecutionPlan',
    'tenantId': tenantId,
    'runId': runId,
    'requestDigest': requestDigest.value,
    'target': target.name,
    'mode': mode.name,
    'interactiveTransport': interactiveTransport.name,
    'artifacts': <Object?>[for (final artifact in artifacts) artifact.toJson()],
    'executionFingerprintDigest': executionFingerprintDigest.value,
    'containmentPolicyDigest': containmentPolicyDigest.value,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'nonce': nonce,
    if (deviceImage != null) 'deviceImage': deviceImage!.toJson(),
  };

  factory RemoteExecutionPlan.fromJson(Object? value) {
    final json = _remoteObject(value, 'RemoteExecutionPlan');
    _remoteOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'tenantId',
      'runId',
      'requestDigest',
      'target',
      'mode',
      'interactiveTransport',
      'artifacts',
      'executionFingerprintDigest',
      'containmentPolicyDigest',
      'issuedAt',
      'expiresAt',
      'nonce',
      'deviceImage',
    }, 'RemoteExecutionPlan');
    _remoteHeader(json, 'RemoteExecutionPlan');
    return RemoteExecutionPlan(
      tenantId: _remoteString(json, 'tenantId', 'RemoteExecutionPlan'),
      runId: _remoteString(json, 'runId', 'RemoteExecutionPlan'),
      requestDigest: Digest(
        _remoteString(json, 'requestDigest', 'RemoteExecutionPlan'),
      ),
      target: _remoteEnum(
        RemoteTargetKind.values,
        _remoteString(json, 'target', 'RemoteExecutionPlan'),
        'RemoteExecutionPlan.target',
      ),
      mode: _remoteEnum(
        RemoteRunMode.values,
        _remoteString(json, 'mode', 'RemoteExecutionPlan'),
        'RemoteExecutionPlan.mode',
      ),
      interactiveTransport: _remoteEnum(
        RemoteInteractiveTransport.values,
        _remoteString(json, 'interactiveTransport', 'RemoteExecutionPlan'),
        'RemoteExecutionPlan.interactiveTransport',
      ),
      artifacts: _remoteList(
        json['artifacts'],
        'RemoteExecutionPlan.artifacts',
      ).map(RemoteArtifactInput.fromJson).toList(growable: false),
      executionFingerprintDigest: Digest(
        _remoteString(
          json,
          'executionFingerprintDigest',
          'RemoteExecutionPlan',
        ),
      ),
      containmentPolicyDigest: Digest(
        _remoteString(json, 'containmentPolicyDigest', 'RemoteExecutionPlan'),
      ),
      issuedAt: _remoteDate(json, 'issuedAt', 'RemoteExecutionPlan'),
      expiresAt: _remoteDate(json, 'expiresAt', 'RemoteExecutionPlan'),
      nonce: _remoteString(json, 'nonce', 'RemoteExecutionPlan'),
      deviceImage: json['deviceImage'] == null
          ? null
          : DeviceImageDescriptor.fromJson(json['deviceImage']),
    );
  }
}

final class RemoteWorkerDescriptor {
  RemoteWorkerDescriptor({
    required this.id,
    required this.pool,
    required Set<RemoteTargetKind> targets,
    required this.maximumLeases,
    required this.lastHeartbeatAt,
  }) : targets = Set<RemoteTargetKind>.unmodifiable(targets) {
    _remoteId(id, 'RemoteWorkerDescriptor.id');
    _remoteId(pool, 'RemoteWorkerDescriptor.pool');
    if (this.targets.isEmpty || maximumLeases < 1 || maximumLeases > 32) {
      throw const FormatException('RemoteWorkerDescriptor capacity is invalid');
    }
    _remoteUtc(lastHeartbeatAt, 'RemoteWorkerDescriptor.lastHeartbeatAt');
  }

  final String id;
  final String pool;
  final Set<RemoteTargetKind> targets;
  final int maximumLeases;
  final DateTime lastHeartbeatAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'pool': pool,
    'targets': targets.map((value) => value.name).toList()..sort(),
    'maximumLeases': maximumLeases,
    'lastHeartbeatAt': lastHeartbeatAt.toIso8601String(),
  };
}

final class RemoteLease {
  RemoteLease({
    required this.tenantId,
    required this.runId,
    required this.workerId,
    required this.tokenId,
    required this.generation,
    required this.acquiredAt,
    required this.heartbeatAt,
    required this.expiresAt,
  }) {
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('tenantId', tenantId),
      MapEntry<String, String>('runId', runId),
      MapEntry<String, String>('workerId', workerId),
      MapEntry<String, String>('tokenId', tokenId),
    ]) {
      _remoteId(entry.value, 'RemoteLease.${entry.key}');
    }
    if (generation < 1) {
      throw const FormatException('RemoteLease.generation is invalid');
    }
    for (final entry in <MapEntry<String, DateTime>>[
      MapEntry<String, DateTime>('acquiredAt', acquiredAt),
      MapEntry<String, DateTime>('heartbeatAt', heartbeatAt),
      MapEntry<String, DateTime>('expiresAt', expiresAt),
    ]) {
      _remoteUtc(entry.value, 'RemoteLease.${entry.key}');
    }
    if (heartbeatAt.isBefore(acquiredAt) || !expiresAt.isAfter(heartbeatAt)) {
      throw const FormatException('RemoteLease timestamps are invalid');
    }
  }

  final String tenantId;
  final String runId;
  final String workerId;
  final String tokenId;
  final int generation;
  final DateTime acquiredAt;
  final DateTime heartbeatAt;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenantId': tenantId,
    'runId': runId,
    'workerId': workerId,
    'tokenId': tokenId,
    'generation': generation,
    'acquiredAt': acquiredAt.toIso8601String(),
    'heartbeatAt': heartbeatAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory RemoteLease.fromJson(Object? value) {
    final json = _remoteObject(value, 'RemoteLease');
    _remoteOnly(json, const <String>{
      'tenantId',
      'runId',
      'workerId',
      'tokenId',
      'generation',
      'acquiredAt',
      'heartbeatAt',
      'expiresAt',
    }, 'RemoteLease');
    return RemoteLease(
      tenantId: _remoteString(json, 'tenantId', 'RemoteLease'),
      runId: _remoteString(json, 'runId', 'RemoteLease'),
      workerId: _remoteString(json, 'workerId', 'RemoteLease'),
      tokenId: _remoteString(json, 'tokenId', 'RemoteLease'),
      generation: _remoteInt(json, 'generation', 'RemoteLease'),
      acquiredAt: _remoteDate(json, 'acquiredAt', 'RemoteLease'),
      heartbeatAt: _remoteDate(json, 'heartbeatAt', 'RemoteLease'),
      expiresAt: _remoteDate(json, 'expiresAt', 'RemoteLease'),
    );
  }
}

final class RemoteRun {
  RemoteRun({
    required this.tenantId,
    required this.id,
    required this.requestDigest,
    required this.planDigest,
    required this.target,
    required this.mode,
    required this.state,
    required this.attempt,
    required this.createdAt,
    required this.updatedAt,
    this.workerId,
    this.failureCode,
  }) {
    _remoteId(tenantId, 'RemoteRun.tenantId');
    _remoteId(id, 'RemoteRun.id');
    if (attempt < 0 || attempt > 10 || updatedAt.isBefore(createdAt)) {
      throw const FormatException('RemoteRun counters are invalid');
    }
    _remoteUtc(createdAt, 'RemoteRun.createdAt');
    _remoteUtc(updatedAt, 'RemoteRun.updatedAt');
    final terminal = const <RemoteRunState>{
      RemoteRunState.failed,
      RemoteRunState.cancelled,
      RemoteRunState.unknown,
    }.contains(state);
    if ((failureCode != null) != terminal) {
      throw const FormatException('RemoteRun failure code is invalid');
    }
  }

  final String tenantId;
  final String id;
  final Digest requestDigest;
  final Digest planDigest;
  final RemoteTargetKind target;
  final RemoteRunMode mode;
  final RemoteRunState state;
  final int attempt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? workerId;
  final String? failureCode;

  bool get terminal => const <RemoteRunState>{
    RemoteRunState.succeeded,
    RemoteRunState.failed,
    RemoteRunState.cancelled,
    RemoteRunState.unknown,
  }.contains(state);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'RemoteRun',
    'tenantId': tenantId,
    'id': id,
    'requestDigest': requestDigest.value,
    'planDigest': planDigest.value,
    'target': target.name,
    'mode': mode.name,
    'state': state.name,
    'attempt': attempt,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (workerId != null) 'workerId': workerId,
    if (failureCode != null) 'failureCode': failureCode,
  };

  factory RemoteRun.fromJson(Object? value) {
    final json = _remoteObject(value, 'RemoteRun');
    _remoteOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'tenantId',
      'id',
      'requestDigest',
      'planDigest',
      'target',
      'mode',
      'state',
      'attempt',
      'createdAt',
      'updatedAt',
      'workerId',
      'failureCode',
    }, 'RemoteRun');
    _remoteHeader(json, 'RemoteRun');
    return RemoteRun(
      tenantId: _remoteString(json, 'tenantId', 'RemoteRun'),
      id: _remoteString(json, 'id', 'RemoteRun'),
      requestDigest: Digest(_remoteString(json, 'requestDigest', 'RemoteRun')),
      planDigest: Digest(_remoteString(json, 'planDigest', 'RemoteRun')),
      target: _remoteEnum(
        RemoteTargetKind.values,
        _remoteString(json, 'target', 'RemoteRun'),
        'RemoteRun.target',
      ),
      mode: _remoteEnum(
        RemoteRunMode.values,
        _remoteString(json, 'mode', 'RemoteRun'),
        'RemoteRun.mode',
      ),
      state: _remoteEnum(
        RemoteRunState.values,
        _remoteString(json, 'state', 'RemoteRun'),
        'RemoteRun.state',
      ),
      attempt: _remoteInt(json, 'attempt', 'RemoteRun'),
      createdAt: _remoteDate(json, 'createdAt', 'RemoteRun'),
      updatedAt: _remoteDate(json, 'updatedAt', 'RemoteRun'),
      workerId: _remoteOptionalString(json, 'workerId', 'RemoteRun'),
      failureCode: _remoteOptionalString(json, 'failureCode', 'RemoteRun'),
    );
  }
}

final class RemoteArtifactManifest {
  RemoteArtifactManifest({
    required this.tenantId,
    required this.runId,
    required this.executionFingerprintDigest,
    required this.interactiveTransport,
    required List<HostedBlobDescriptor> artifacts,
    required this.createdAt,
  }) : artifacts = List<HostedBlobDescriptor>.unmodifiable(artifacts) {
    _remoteId(tenantId, 'RemoteArtifactManifest.tenantId');
    _remoteId(runId, 'RemoteArtifactManifest.runId');
    if (this.artifacts.isEmpty ||
        this.artifacts.any((artifact) => artifact.tenantId != tenantId) ||
        this.artifacts.map((artifact) => artifact.digest).toSet().length !=
            this.artifacts.length) {
      throw const FormatException(
        'RemoteArtifactManifest artifacts are invalid',
      );
    }
    _remoteUtc(createdAt, 'RemoteArtifactManifest.createdAt');
  }

  final String tenantId;
  final String runId;
  final Digest executionFingerprintDigest;
  final RemoteInteractiveTransport interactiveTransport;
  final List<HostedBlobDescriptor> artifacts;
  final DateTime createdAt;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'RemoteArtifactManifest',
    'tenantId': tenantId,
    'runId': runId,
    'executionFingerprintDigest': executionFingerprintDigest.value,
    'interactiveTransport': interactiveTransport.name,
    'artifacts': <Object?>[for (final item in artifacts) item.toJson()],
    'createdAt': createdAt.toIso8601String(),
  };

  factory RemoteArtifactManifest.fromJson(Object? value) {
    final json = _remoteObject(value, 'RemoteArtifactManifest');
    _remoteOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'tenantId',
      'runId',
      'executionFingerprintDigest',
      'interactiveTransport',
      'artifacts',
      'createdAt',
    }, 'RemoteArtifactManifest');
    _remoteHeader(json, 'RemoteArtifactManifest');
    return RemoteArtifactManifest(
      tenantId: _remoteString(json, 'tenantId', 'RemoteArtifactManifest'),
      runId: _remoteString(json, 'runId', 'RemoteArtifactManifest'),
      executionFingerprintDigest: Digest(
        _remoteString(
          json,
          'executionFingerprintDigest',
          'RemoteArtifactManifest',
        ),
      ),
      interactiveTransport: _remoteEnum(
        RemoteInteractiveTransport.values,
        _remoteString(json, 'interactiveTransport', 'RemoteArtifactManifest'),
        'RemoteArtifactManifest.interactiveTransport',
      ),
      artifacts: _remoteList(
        json['artifacts'],
        'RemoteArtifactManifest.artifacts',
      ).map(HostedBlobDescriptor.fromJson).toList(growable: false),
      createdAt: _remoteDate(json, 'createdAt', 'RemoteArtifactManifest'),
    );
  }
}

final class RemoteContainmentReport {
  RemoteContainmentReport({
    required this.tenantId,
    required this.runId,
    required this.namespace,
    required this.serviceAccount,
    required this.podSecurityProfile,
    required this.defaultDenyEgress,
    required Set<String> allowedEndpointClasses,
    required this.ephemeralStorageWiped,
    required this.leaseRevoked,
    required this.observedAt,
  }) : allowedEndpointClasses = Set<String>.unmodifiable(
         allowedEndpointClasses,
       ) {
    _remoteId(tenantId, 'RemoteContainmentReport.tenantId');
    _remoteId(runId, 'RemoteContainmentReport.runId');
    _remoteId(namespace, 'RemoteContainmentReport.namespace');
    _remoteId(serviceAccount, 'RemoteContainmentReport.serviceAccount');
    if (!const <String>{
          'restricted',
          'android-kvm-minimal',
        }.contains(podSecurityProfile) ||
        this.allowedEndpointClasses.any(
          (value) => !const <String>{
            'gateway',
            'artifact',
            'control',
            'dns',
          }.contains(value),
        )) {
      throw const FormatException('RemoteContainmentReport policy is invalid');
    }
    _remoteUtc(observedAt, 'RemoteContainmentReport.observedAt');
  }

  final String tenantId;
  final String runId;
  final String namespace;
  final String serviceAccount;
  final String podSecurityProfile;
  final bool defaultDenyEgress;
  final Set<String> allowedEndpointClasses;
  final bool ephemeralStorageWiped;
  final bool leaseRevoked;
  final DateTime observedAt;
  late final Digest digest = Digest.semantic(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'RemoteContainmentReport',
    'tenantId': tenantId,
    'runId': runId,
    'namespace': namespace,
    'serviceAccount': serviceAccount,
    'podSecurityProfile': podSecurityProfile,
    'defaultDenyEgress': defaultDenyEgress,
    'allowedEndpointClasses': allowedEndpointClasses.toList()..sort(),
    'ephemeralStorageWiped': ephemeralStorageWiped,
    'leaseRevoked': leaseRevoked,
    'observedAt': observedAt.toIso8601String(),
  };

  factory RemoteContainmentReport.fromJson(Object? value) {
    final json = _remoteObject(value, 'RemoteContainmentReport');
    _remoteOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'tenantId',
      'runId',
      'namespace',
      'serviceAccount',
      'podSecurityProfile',
      'defaultDenyEgress',
      'allowedEndpointClasses',
      'ephemeralStorageWiped',
      'leaseRevoked',
      'observedAt',
    }, 'RemoteContainmentReport');
    _remoteHeader(json, 'RemoteContainmentReport');
    return RemoteContainmentReport(
      tenantId: _remoteString(json, 'tenantId', 'RemoteContainmentReport'),
      runId: _remoteString(json, 'runId', 'RemoteContainmentReport'),
      namespace: _remoteString(json, 'namespace', 'RemoteContainmentReport'),
      serviceAccount: _remoteString(
        json,
        'serviceAccount',
        'RemoteContainmentReport',
      ),
      podSecurityProfile: _remoteString(
        json,
        'podSecurityProfile',
        'RemoteContainmentReport',
      ),
      defaultDenyEgress: _remoteBool(
        json,
        'defaultDenyEgress',
        'RemoteContainmentReport',
      ),
      allowedEndpointClasses:
          _remoteList(
            json['allowedEndpointClasses'],
            'RemoteContainmentReport.allowedEndpointClasses',
          ).map((value) {
            if (value is! String || value.isEmpty) {
              throw const FormatException(
                'RemoteContainmentReport.allowedEndpointClasses is invalid',
              );
            }
            return value;
          }).toSet(),
      ephemeralStorageWiped: _remoteBool(
        json,
        'ephemeralStorageWiped',
        'RemoteContainmentReport',
      ),
      leaseRevoked: _remoteBool(
        json,
        'leaseRevoked',
        'RemoteContainmentReport',
      ),
      observedAt: _remoteDate(json, 'observedAt', 'RemoteContainmentReport'),
    );
  }
}

Map<String, Object?> _remoteObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

List<Object?> _remoteList(Object? value, String path) {
  if (value is! List<Object?>) throw FormatException('$path must be an array');
  return value;
}

void _remoteOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) throw FormatException('$path has unknown fields');
}

String _remoteString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key is invalid');
  }
  return value;
}

String? _remoteOptionalString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key is invalid');
  }
  return value;
}

int _remoteInt(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key is invalid');
  return value;
}

bool _remoteBool(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key is invalid');
  return value;
}

DateTime _remoteDate(Map<String, Object?> json, String key, String path) {
  final value = DateTime.tryParse(_remoteString(json, key, path));
  if (value == null || !value.isUtc) {
    throw FormatException('$path.$key is invalid');
  }
  return value;
}

T _remoteEnum<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path is invalid');
}

void _remoteTransport({
  required RemoteTargetKind target,
  required RemoteRunMode mode,
  required RemoteInteractiveTransport transport,
  required String path,
}) {
  final valid = switch ((mode, target)) {
    (RemoteRunMode.batch, _) => transport == RemoteInteractiveTransport.none,
    (RemoteRunMode.interactive, RemoteTargetKind.web) =>
      transport == RemoteInteractiveTransport.webDirect,
    (RemoteRunMode.interactive, RemoteTargetKind.androidEmulator) =>
      transport == RemoteInteractiveTransport.scrcpyH264Control ||
          transport == RemoteInteractiveTransport.periodicScreenshotReadOnly,
  };
  if (!valid) throw FormatException('$path is invalid for target and mode');
}

void _remoteHeader(Map<String, Object?> json, String kind) {
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind header is invalid');
  }
}

void _remoteId(String value, String path) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$').hasMatch(value)) {
    throw FormatException('$path is invalid');
  }
}

void _remoteText(String value, String path, int maximum) {
  if (value.isEmpty || value.length > maximum || value.contains('\u0000')) {
    throw FormatException('$path is invalid');
  }
}

void _remoteUtc(DateTime value, String path) {
  if (!value.isUtc) throw ArgumentError('$path must be UTC');
}
