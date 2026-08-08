import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../evidence/local_evidence_repository.dart';
import '../preview/preview_capture_runner.dart';
import '../preview/preview_source_scanner.dart';
import '../preview/preview_workspace_inputs.dart';
import '../secure_id_generator.dart';
import '../storage/filesystem_workspace_store.dart';
import '../system_clock.dart';
import 'host_resource_registry.dart';
import 'host_workspace_service.dart';
import 'preview_evidence_scope.dart';

typedef HostPreviewEventPublisher =
    Future<void> Function(String method, Map<String, Object?> params);

enum HostPreviewOperationState {
  queued,
  running,
  cancelling,
  cancelled,
  completed,
  completedWithFailures,
  failed,
}

final class HostAutoPreviewService {
  HostAutoPreviewService({
    required this.workspace,
    required this.store,
    required this.plan,
    required this.platform,
    required this.resources,
    required this.hostOrigin,
    required this.studioOrigin,
    required this.publishEvent,
    Clock? clock,
    IdGenerator? ids,
    this.scanner = const PreviewSourceScanner(),
    this.inputs = const PreviewWorkspaceInputs(),
  }) : clock = clock ?? SystemClock(),
       ids = ids ?? SecureIdGenerator(),
       repository = LocalEvidenceRepository(store: store);

  final HostWorkspaceService workspace;
  final FileSystemWorkspaceStore store;
  final ResolvedKitPlan plan;
  final String platform;
  final HostResourceRegistry resources;
  final Uri Function() hostOrigin;
  final Uri studioOrigin;
  final HostPreviewEventPublisher publishEvent;
  final Clock clock;
  final IdGenerator ids;
  final PreviewSourceScanner scanner;
  final PreviewWorkspaceInputs inputs;
  final LocalEvidenceRepository repository;

  final Map<String, _HostPreviewOperation> _operations =
      <String, _HostPreviewOperation>{};
  final List<ResourceHandle> _issuedHandles = <ResourceHandle>[];
  Future<void> _projectionSerial = Future<void>.value();

  Future<void> initialize() => refreshProjection();

  /// Reissues expiring presentation capabilities without rescanning sources or
  /// recollecting Evidence. Artifact digests remain canonical; only the
  /// audience-bound HTTP handles and WorkspaceSnapshot identity rotate.
  Future<bool> renewArtifactHandles({
    Duration minimumValidity = const Duration(minutes: 1),
    bool force = false,
  }) {
    if (minimumValidity.isNegative) {
      throw ArgumentError.value(minimumValidity, 'minimumValidity');
    }
    final completer = Completer<bool>();
    _projectionSerial = _projectionSerial.then((_) async {
      try {
        completer.complete(
          await _renewArtifactHandles(
            minimumValidity: minimumValidity,
            force: force,
          ),
        );
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> _renewArtifactHandles({
    required Duration minimumValidity,
    required bool force,
  }) async {
    final current = workspace.snapshot;
    final collected = current.visualProjections
        .where((item) => item.status == VisualEvidenceStatus.collected)
        .toList(growable: false);
    if (collected.isEmpty) return false;
    final now = clock.nowUtc();
    final renewAt = now.add(minimumValidity);
    if (!force &&
        collected.every(
          (item) => renewAt.isBefore(item.artifactHandle!.expiresAt),
        )) {
      return false;
    }

    final collectedBytes = <List<int>>[];
    for (final projection in collected) {
      final bytes = store.readBlob(projection.artifactDigest!);
      if (bytes == null) {
        throw StateError(
          'Collected Preview artifact is missing from CAS during handle renewal',
        );
      }
      collectedBytes.add(bytes);
    }

    final renewedHandles = resources.grantByteSet(
      hostOrigin: hostOrigin(),
      audienceOrigin: studioOrigin,
      inputs: <HostResourceGrantInput>[
        for (final bytes in collectedBytes)
          HostResourceGrantInput(
            bytes: bytes,
            mediaType: 'image/png',
            purpose: 'visual-artifact',
            ttl: const Duration(minutes: 15),
          ),
      ],
    );
    var renewedIndex = 0;
    final projections = <VisualEvidenceProjection>[
      for (final projection in current.visualProjections)
        if (projection.status == VisualEvidenceStatus.collected)
          _withArtifactHandle(projection, renewedHandles[renewedIndex++])
        else
          projection,
    ];
    bool changed;
    try {
      changed = workspace.replaceVisualState(
        variantManifest: current.variantManifest,
        projections: projections,
      );
    } on Object {
      for (final handle in renewedHandles) {
        resources.revoke(handle);
      }
      rethrow;
    }
    if (!changed) {
      for (final handle in renewedHandles) {
        resources.revoke(handle);
      }
      return false;
    }

    for (final projection in collected) {
      resources.revoke(projection.artifactHandle!);
    }
    _issuedHandles
      ..removeWhere((handle) => handle.isExpiredAt(now))
      ..removeWhere(
        (handle) => collected.any(
          (projection) => projection.artifactHandle!.uri == handle.uri,
        ),
      )
      ..addAll(renewedHandles);
    await _publishWorkspaceChanged();
    return true;
  }

  Future<void> refreshProjection() {
    final completer = Completer<void>();
    _projectionSerial = _projectionSerial.then((_) async {
      try {
        final inspection = await _inspectSources();
        for (final handle in _issuedHandles) {
          resources.revoke(handle);
        }
        _issuedHandles.clear();
        final projections = _projectEvidence(inspection);
        final changed = workspace.replaceVisualState(
          variantManifest: inspection.variantManifest,
          projections: projections,
        );
        if (changed) {
          await _publishWorkspaceChanged();
        }
        completer.complete();
      } on Object catch (error, stackTrace) {
        final diagnostic = ModuleDiagnostic(
          moduleId: ModuleId('evidence.auto-preview'),
          code: 'preview.inspect.failed',
          severity: ModuleDiagnosticSeverity.error,
          message: _bounded('$error'),
        );
        final changed = workspace.replaceVisualState(
          variantManifest: VariantManifest(
            catalogDigest: workspace.snapshot.catalog.digest,
            variants: const <Variant>[],
            sources: const <VariantDefinitionSource>[],
          ),
          projections: const <VisualEvidenceProjection>[],
          providerDiagnostics: <ModuleId, List<ModuleDiagnostic>>{
            ModuleId('evidence.auto-preview'): <ModuleDiagnostic>[diagnostic],
          },
        );
        if (changed) {
          await _publishWorkspaceChanged();
        }
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _publishWorkspaceChanged() async {
    await publishEvent('workspace.changed', workspace.describe());
    await publishEvent(
      'experience.content.changed',
      workspace.describeContentSet().toJson(),
    );
  }

  Map<String, Object?> collect(Map<String, Object?> params) {
    _only(params, const <String>{
      'applicationId',
      'scenarioId',
      'variantId',
      'syntheticDataConfirmed',
    });
    final active = _operations.values.where(
      (item) =>
          item.state == HostPreviewOperationState.queued ||
          item.state == HostPreviewOperationState.running ||
          item.state == HostPreviewOperationState.cancelling,
    );
    if (active.isNotEmpty) {
      throw StateError('An AutoPreview collection is already active');
    }
    final applicationId = _optionalString(params, 'applicationId');
    final scenarioId = _optionalString(params, 'scenarioId');
    final variantId = _optionalString(params, 'variantId');
    final synthetic = params['syntheticDataConfirmed'];
    if (synthetic is! bool) {
      throw const FormatException(
        'syntheticDataConfirmed must be an explicit boolean',
      );
    }
    final operation = _HostPreviewOperation(
      id: 'preview-${ids.nextId()}',
      applicationId: applicationId,
      scenarioId: scenarioId,
      variantId: variantId,
      syntheticDataConfirmed: synthetic,
      createdAt: clock.nowUtc(),
    );
    _operations[operation.id] = operation;
    unawaited(_run(operation));
    return operation.toJson();
  }

  Map<String, Object?> status(Map<String, Object?> params) {
    _only(params, const <String>{'operationId'});
    final id = _requiredString(params, 'operationId');
    final operation = _operations[id];
    if (operation == null) {
      throw StateError('Unknown AutoPreview operation');
    }
    return operation.toJson();
  }

  Map<String, Object?> cancel(Map<String, Object?> params) {
    _only(params, const <String>{'operationId'});
    final id = _requiredString(params, 'operationId');
    final operation = _operations[id];
    if (operation == null) {
      throw StateError('Unknown AutoPreview operation');
    }
    if (operation.state == HostPreviewOperationState.queued ||
        operation.state == HostPreviewOperationState.running) {
      operation
        ..state = HostPreviewOperationState.cancelling
        ..cancellation.cancel();
      unawaited(_publishOperation(operation));
    }
    return operation.toJson();
  }

  Future<void> close() async {
    for (final operation in _operations.values) {
      if (operation.state == HostPreviewOperationState.running ||
          operation.state == HostPreviewOperationState.queued ||
          operation.state == HostPreviewOperationState.cancelling) {
        operation.cancellation.cancel();
      }
    }
    final running = _operations.values
        .map((item) => item.completion)
        .whereType<Future<void>>()
        .toList(growable: false);
    await Future.wait(
      running,
    ).timeout(const Duration(minutes: 6), onTimeout: () => const <void>[]);
    for (final handle in _issuedHandles) {
      resources.revoke(handle);
    }
    _issuedHandles.clear();
  }

  Future<void> _run(_HostPreviewOperation operation) async {
    final completion = Completer<void>();
    operation.completion = completion.future;
    try {
      operation
        ..state = HostPreviewOperationState.running
        ..startedAt = clock.nowUtc();
      await _publishOperation(operation);
      final inspection = await _inspectSources();
      final application = _resolveApplication(
        inspection,
        operation.applicationId,
      );
      final descriptors = inspection.descriptorsByApplication[application.id]!
          .where(
            (item) =>
                (operation.scenarioId == null ||
                    item.scenarioId.value == operation.scenarioId) &&
                (operation.variantId == null ||
                    item.variant.id.value == operation.variantId),
          )
          .toList(growable: false);
      if (descriptors.isEmpty) {
        throw const FormatException(
          'No AutoPreview matches the requested collection scope',
        );
      }
      final previewManifest = PreviewManifest(
        catalogDigest: workspace.snapshot.catalog.digest,
        flutterCompatibility: PreviewSourceScanner.flutterCompatibility,
        descriptors: descriptors,
      );
      final applicationRoot = inspection.applicationRoots[application.id]!;
      final registry = await const EphemeralPreviewRegistryWriter().write(
        applicationRoot: applicationRoot,
        planDigest: plan.digest,
        manifest: previewManifest,
        scan: inspection.scans[application.id]!,
      );
      final toolchain = await inputs.toolchain(applicationRoot);
      final toolchainDigest = Digest.semantic(toolchain);
      final inputDigests = inputs.inspect(applicationRoot)
        ..['plan'] = plan.digest
        ..['previewManifest'] = previewManifest.digest;
      final settings = plan.enabledModules
          .singleWhere((item) => item.moduleId.value == 'evidence.auto-preview')
          .settings;
      final renderer = settings['renderer'];
      final capturePolicyId = settings['capturePolicy'];
      if (renderer != 'flutter-test' || capturePolicyId is! String) {
        throw const FormatException(
          'Host AutoPreview requires flutter-test and a capture policy',
        );
      }
      final fingerprint = ExecutionFingerprint(
        catalogDigest: workspace.snapshot.catalog.digest,
        launchProfileId: 'preview-${plan.profileId}',
        targetId: 'preview.flutter-test',
        platform: platform,
        renderer: 'flutter-test',
        runtimeFidelity: RuntimeFidelity.structural,
        backendMode: BackendMode.none,
        networkContainment: NetworkContainment.unconstrained,
        bootstrapAssessment: BootstrapAssessment.controlled,
        toolchain: toolchain,
        capabilities: const <String>{'evidence.visual.preview'},
        inputDigests: inputDigests,
        policies: <String, String>{'capture': capturePolicyId},
      );
      operation.totalItems = descriptors.length;
      final run = await PreviewCaptureRunner(store: store).run(
        applicationRoot: applicationRoot,
        previewManifest: previewManifest,
        registry: registry,
        fingerprint: fingerprint,
        planDigest: plan.digest,
        toolchainDigest: toolchainDigest,
        policies: <String, PreviewStabilizationPolicy>{
          capturePolicyId: PreviewStabilizationPolicy(id: capturePolicyId),
        },
        syntheticDataConfirmed: operation.syntheticDataConfirmed,
        inputDigests: inputDigests,
        cancellationToken: operation.cancellation,
        onProgress: (completed, total) {
          operation
            ..completedItems = completed
            ..totalItems = total;
          unawaited(_publishOperation(operation));
        },
      );
      final evidence = PreviewEvidenceProvider(
        store: store,
        repository: repository,
      ).persist(run: run, fingerprint: fingerprint);
      final terminalState = operation.cancellation.isCancelled
          ? HostPreviewOperationState.cancelled
          : run.report.failedItems == 0
          ? HostPreviewOperationState.completed
          : HostPreviewOperationState.completedWithFailures;
      operation
        ..evidenceDigest = evidence.digest
        ..failedItems = run.report.failedItems
        ..completedItems = run.report.totalItems
        ..completedAt = clock.nowUtc();
      await refreshProjection();
      operation.state = terminalState;
    } on Object catch (error) {
      operation
        ..completedAt = clock.nowUtc()
        ..error = _bounded('$error')
        ..state = operation.cancellation.isCancelled
            ? HostPreviewOperationState.cancelled
            : HostPreviewOperationState.failed;
    } finally {
      await _publishOperation(operation);
      completion.complete();
    }
  }

  Future<_PreviewInspection> _inspectSources() async {
    final catalog = workspace.snapshot.catalog;
    final scans = <ApplicationId, PreviewSourceScanResult>{};
    final roots = <ApplicationId, String>{};
    final candidates = <PreviewDeclarationCandidate>[];
    for (final application in catalog.applications) {
      final root = _applicationRoot(application);
      final scan = await scanner.scan(applicationRoot: root);
      roots[application.id] = root;
      scans[application.id] = scan;
      candidates.addAll(scan.candidates);
    }
    if (candidates.isEmpty) {
      return _PreviewInspection(
        manifest: null,
        variantManifest: VariantManifest(
          catalogDigest: catalog.digest,
          variants: const <Variant>[],
          sources: const <VariantDefinitionSource>[],
        ),
        scans: scans,
        applicationRoots: roots,
        descriptorsByApplication: <ApplicationId, List<PreviewDescriptor>>{
          for (final application in catalog.applications)
            application.id: const <PreviewDescriptor>[],
        },
      );
    }
    final manifest = const PreviewManifestCompiler().compile(
      candidates: candidates,
      catalog: catalog,
      flutterCompatibility: PreviewSourceScanner.flutterCompatibility,
    );
    final variants = <VariantId, Variant>{};
    final sources = <String, VariantDefinitionSource>{};
    for (final descriptor in manifest.descriptors) {
      final existing = variants[descriptor.variant.id];
      if (existing != null && existing.digest != descriptor.variant.digest) {
        throw FormatException(
          'Variant ${descriptor.variant.id.value} has divergent sources',
        );
      }
      variants[descriptor.variant.id] = descriptor.variant;
      final source = VariantDefinitionSource(
        variantId: descriptor.variant.id,
        sourceId: 'auto-preview.${descriptor.id.value}',
        sourceDigest: descriptor.digest,
      );
      sources[source.key] = source;
    }
    return _PreviewInspection(
      manifest: manifest,
      variantManifest: VariantManifest(
        catalogDigest: catalog.digest,
        variants: variants.values.toList(growable: false),
        sources: sources.values.toList(growable: false),
      ),
      scans: scans,
      applicationRoots: roots,
      descriptorsByApplication: <ApplicationId, List<PreviewDescriptor>>{
        for (final application in catalog.applications)
          application.id: manifest.descriptors
              .where((item) => item.variant.applicationId == application.id)
              .toList(growable: false),
      },
    );
  }

  List<VisualEvidenceProjection> _projectEvidence(
    _PreviewInspection inspection,
  ) {
    final descriptors = <String, PreviewDescriptor>{
      for (final descriptor
          in inspection.manifest?.descriptors ?? const <PreviewDescriptor>[])
        _descriptorKey(
          descriptor.id,
          descriptor.scenarioId,
          descriptor.variant.id,
        ): descriptor,
    };
    final projections = <String, VisualEvidenceProjection>{};
    final unbound = <VisualEvidenceProjection>[];
    final currentBaseInputs = <ApplicationId, Map<String, Digest>>{};
    for (final evidence in repository.readAllEvidence()) {
      if (evidence.policyId != 'auto-preview' ||
          evidence.fingerprint.runtimeFidelity != RuntimeFidelity.structural) {
        continue;
      }
      final manifestArtifact = evidence.artifacts
          .where((item) => item.role == 'preview.capture-manifest')
          .firstOrNull;
      if (manifestArtifact == null) {
        unbound.add(_unbound(evidence, 'Preview capture manifest is missing'));
        continue;
      }
      try {
        final manifestBytes = store.readBlob(manifestArtifact.digest);
        if (manifestBytes == null) {
          unbound.add(_unbound(evidence, 'Preview capture manifest is absent'));
          continue;
        }
        final capture = PreviewCaptureManifest.fromJson(
          jsonDecode(utf8.decode(manifestBytes)),
        );
        final scope = PreviewEvidenceScope.bind(
          capture: capture,
          currentDescriptors: descriptors.values,
          catalogDigest: workspace.snapshot.catalog.digest,
          flutterCompatibility: PreviewSourceScanner.flutterCompatibility,
        );
        for (final item in capture.items) {
          final descriptor = scope.descriptorFor(item);
          if (descriptor == null) {
            continue;
          }
          final applicationId = descriptor.variant.applicationId;
          final baseInputs = currentBaseInputs.putIfAbsent(applicationId, () {
            return inputs.inspect(inspection.applicationRoots[applicationId]!)
              ..['plan'] = plan.digest;
          });
          final appInputs = <String, Digest>{
            ...baseInputs,
            'previewManifest':
                scope.manifestsByApplication[applicationId]!.digest,
          };
          final stale =
              item.descriptorDigest != descriptor.digest ||
              evidence.subjectDigest != workspace.snapshot.catalog.digest ||
              appInputs.entries.any(
                (entry) =>
                    evidence.fingerprint.inputDigests[entry.key] != entry.value,
              );
          final projection = _projectionForItem(
            evidence: evidence,
            item: item,
            descriptor: descriptor,
            stale: stale,
          );
          projections[projection.key] = projection;
        }
        if (scope.hasUnboundItems) {
          unbound.add(
            _unbound(
              evidence,
              'Capture contains bindings absent from the current PreviewManifest',
            ),
          );
        }
      } on Object catch (error) {
        unbound.add(_unbound(evidence, _bounded('$error')));
      }
    }
    final providerId = ModuleId('evidence.auto-preview');
    for (final descriptor in descriptors.values) {
      final missing = VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: descriptor.scenarioId,
        variantId: descriptor.variant.id,
        capturePolicyId: descriptor.capturePolicyId,
        status: VisualEvidenceStatus.missing,
        freshness: EvidenceFreshness.missing,
      );
      projections.putIfAbsent(missing.key, () => missing);
    }
    return <VisualEvidenceProjection>[...projections.values, ...unbound];
  }

  VisualEvidenceProjection _projectionForItem({
    required Evidence evidence,
    required PreviewCaptureItem item,
    required PreviewDescriptor descriptor,
    required bool stale,
  }) {
    final providerId = ModuleId('evidence.auto-preview');
    final diagnostics = <ModuleDiagnostic>[
      for (final diagnostic in item.diagnostics)
        ModuleDiagnostic(
          moduleId: providerId,
          code: diagnostic.code,
          severity: switch (diagnostic.severity) {
            PreviewDiagnosticSeverity.info => ModuleDiagnosticSeverity.info,
            PreviewDiagnosticSeverity.warning =>
              ModuleDiagnosticSeverity.warning,
            PreviewDiagnosticSeverity.error => ModuleDiagnosticSeverity.error,
          },
          message: diagnostic.message,
        ),
    ];
    if (item.status != PreviewCaptureStatus.collected) {
      return VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: item.scenarioId,
        variantId: item.variantId,
        evidenceDigest: evidence.digest,
        captureKey: item.captureKey,
        executionFingerprintDigest: evidence.fingerprint.digest,
        capturePolicyId: descriptor.capturePolicyId,
        status: switch (item.status) {
          PreviewCaptureStatus.collected => VisualEvidenceStatus.collected,
          PreviewCaptureStatus.invalid ||
          PreviewCaptureStatus.failed => VisualEvidenceStatus.failed,
          PreviewCaptureStatus.unsupported => VisualEvidenceStatus.unsupported,
          PreviewCaptureStatus.policyDenied =>
            VisualEvidenceStatus.policyDenied,
        },
        freshness: EvidenceFreshness.invalid,
        diagnostics: diagnostics,
      );
    }
    final artifact = evidence.artifacts
        .where((entry) => entry.digest == item.artifactDigest)
        .firstOrNull;
    if (artifact == null || artifact.mediaType != 'image/png') {
      return VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: descriptor.scenarioId,
        variantId: descriptor.variant.id,
        evidenceDigest: evidence.digest,
        captureKey: item.captureKey,
        executionFingerprintDigest: evidence.fingerprint.digest,
        capturePolicyId: descriptor.capturePolicyId,
        status: VisualEvidenceStatus.failed,
        freshness: EvidenceFreshness.invalid,
        diagnostics: <ModuleDiagnostic>[
          ...diagnostics,
          ModuleDiagnostic(
            moduleId: providerId,
            code: 'preview.artifact.invalid',
            severity: ModuleDiagnosticSeverity.error,
            message: 'Collected Preview artifact is absent or is not PNG',
          ),
        ],
      );
    }
    if (artifact.classification == ArtifactClassification.sensitive) {
      return VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: descriptor.scenarioId,
        variantId: descriptor.variant.id,
        evidenceDigest: evidence.digest,
        captureKey: item.captureKey,
        executionFingerprintDigest: evidence.fingerprint.digest,
        capturePolicyId: descriptor.capturePolicyId,
        status: VisualEvidenceStatus.policyDenied,
        freshness: EvidenceFreshness.invalid,
        diagnostics: <ModuleDiagnostic>[
          ...diagnostics,
          ModuleDiagnostic(
            moduleId: providerId,
            code: 'preview.artifact.sensitive',
            severity: ModuleDiagnosticSeverity.error,
            message: 'Sensitive Preview artifacts cannot be sent to Studio',
          ),
        ],
      );
    }
    final bytes = store.readBlob(artifact.digest);
    if (bytes == null) {
      return VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: descriptor.scenarioId,
        variantId: descriptor.variant.id,
        evidenceDigest: evidence.digest,
        captureKey: item.captureKey,
        executionFingerprintDigest: evidence.fingerprint.digest,
        capturePolicyId: descriptor.capturePolicyId,
        status: VisualEvidenceStatus.failed,
        freshness: EvidenceFreshness.invalid,
        diagnostics: <ModuleDiagnostic>[
          ...diagnostics,
          ModuleDiagnostic(
            moduleId: providerId,
            code: 'preview.artifact.missing',
            severity: ModuleDiagnosticSeverity.error,
            message: 'Preview artifact is missing from CAS',
          ),
        ],
      );
    }
    try {
      final handle = resources.grantBytes(
        hostOrigin: hostOrigin(),
        audienceOrigin: studioOrigin,
        bytes: bytes,
        mediaType: 'image/png',
        purpose: 'visual-artifact',
        classification: artifact.classification,
        ttl: const Duration(minutes: 15),
      );
      _issuedHandles.add(handle);
      return VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: descriptor.scenarioId,
        variantId: descriptor.variant.id,
        evidenceDigest: evidence.digest,
        artifactDigest: artifact.digest,
        captureKey: item.captureKey,
        executionFingerprintDigest: evidence.fingerprint.digest,
        capturePolicyId: descriptor.capturePolicyId,
        status: VisualEvidenceStatus.collected,
        freshness: stale ? EvidenceFreshness.stale : EvidenceFreshness.fresh,
        fidelity: RuntimeFidelity.structural,
        observedAt: evidence.observedAt,
        artifactHandle: handle,
        diagnostics: diagnostics,
      );
    } on Object catch (error) {
      return VisualEvidenceProjection(
        providerId: providerId,
        scenarioId: descriptor.scenarioId,
        variantId: descriptor.variant.id,
        evidenceDigest: evidence.digest,
        captureKey: item.captureKey,
        executionFingerprintDigest: evidence.fingerprint.digest,
        capturePolicyId: descriptor.capturePolicyId,
        status: VisualEvidenceStatus.policyDenied,
        freshness: EvidenceFreshness.invalid,
        diagnostics: <ModuleDiagnostic>[
          ...diagnostics,
          ModuleDiagnostic(
            moduleId: providerId,
            code: 'preview.resource.denied',
            severity: ModuleDiagnosticSeverity.error,
            message: _bounded('$error'),
          ),
        ],
      );
    }
  }

  VisualEvidenceProjection _unbound(Evidence evidence, String message) =>
      VisualEvidenceProjection(
        providerId: ModuleId('evidence.auto-preview'),
        evidenceDigest: evidence.digest,
        executionFingerprintDigest: evidence.fingerprint.digest,
        status: VisualEvidenceStatus.unbound,
        freshness: evidence.subjectDigest == workspace.snapshot.catalog.digest
            ? EvidenceFreshness.invalid
            : EvidenceFreshness.stale,
        diagnostics: <ModuleDiagnostic>[
          ModuleDiagnostic(
            moduleId: ModuleId('evidence.auto-preview'),
            code: 'preview.evidence.unbound',
            severity: ModuleDiagnosticSeverity.warning,
            message: message,
          ),
        ],
      );

  VisualEvidenceProjection _withArtifactHandle(
    VisualEvidenceProjection projection,
    ResourceHandle handle,
  ) => VisualEvidenceProjection(
    providerId: projection.providerId,
    scenarioId: projection.scenarioId,
    variantId: projection.variantId,
    evidenceDigest: projection.evidenceDigest,
    artifactDigest: projection.artifactDigest,
    captureKey: projection.captureKey,
    executionFingerprintDigest: projection.executionFingerprintDigest,
    capturePolicyId: projection.capturePolicyId,
    status: projection.status,
    freshness: projection.freshness,
    fidelity: projection.fidelity,
    observedAt: projection.observedAt,
    artifactHandle: handle,
    diagnostics: projection.diagnostics,
  );

  Application _resolveApplication(
    _PreviewInspection inspection,
    String? requestedId,
  ) {
    final applications = workspace.snapshot.catalog.applications.where(
      (item) =>
          inspection.descriptorsByApplication[item.id]?.isNotEmpty ?? false,
    );
    if (requestedId != null) {
      return applications
              .where((item) => item.id.value == requestedId)
              .firstOrNull ??
          (throw FormatException(
            'Application $requestedId has no AutoPreview',
          ));
    }
    final values = applications.toList(growable: false);
    if (values.length != 1) {
      throw const FormatException(
        'applicationId is required when zero or multiple Applications expose AutoPreview',
      );
    }
    return values.single;
  }

  String _applicationRoot(Application application) {
    if (p.isAbsolute(application.root)) {
      throw FormatException(
        'Application ${application.id.value} root must be workspace-relative',
      );
    }
    final candidate = Directory(
      p.normalize(p.join(store.workspaceRoot, application.root)),
    );
    final resolved = candidate.resolveSymbolicLinksSync();
    if (resolved != store.workspaceRoot &&
        !p.isWithin(store.workspaceRoot, resolved)) {
      throw FileSystemException(
        'Application root escapes the workspace',
        resolved,
      );
    }
    return resolved;
  }

  Future<void> _publishOperation(_HostPreviewOperation operation) =>
      publishEvent('preview.changed', operation.toJson());

  String _descriptorKey(
    AutoPreviewId id,
    ScenarioId scenarioId,
    VariantId variantId,
  ) => '${id.value}:${scenarioId.value}:${variantId.value}';

  void _only(Map<String, Object?> params, Set<String> allowed) {
    final unknown = params.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown AutoPreview parameter: ${unknown.first}');
    }
  }

  String _requiredString(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value is! String || value.isEmpty || value.length > 512) {
      throw FormatException('$key must be a bounded non-empty string');
    }
    return value;
  }

  String? _optionalString(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value == null) return null;
    if (value is! String || value.isEmpty || value.length > 512) {
      throw FormatException('$key must be a bounded non-empty string');
    }
    return value;
  }

  String _bounded(String value) =>
      value.length <= 2048 ? value : value.substring(value.length - 2048);
}

final class _PreviewInspection {
  const _PreviewInspection({
    required this.manifest,
    required this.variantManifest,
    required this.scans,
    required this.applicationRoots,
    required this.descriptorsByApplication,
  });

  final PreviewManifest? manifest;
  final VariantManifest variantManifest;
  final Map<ApplicationId, PreviewSourceScanResult> scans;
  final Map<ApplicationId, String> applicationRoots;
  final Map<ApplicationId, List<PreviewDescriptor>> descriptorsByApplication;
}

final class _HostPreviewOperation {
  _HostPreviewOperation({
    required this.id,
    required this.applicationId,
    required this.scenarioId,
    required this.variantId,
    required this.syntheticDataConfirmed,
    required this.createdAt,
  });

  final String id;
  final String? applicationId;
  final String? scenarioId;
  final String? variantId;
  final bool syntheticDataConfirmed;
  final DateTime createdAt;
  final PreviewCancellationToken cancellation = PreviewCancellationToken();
  HostPreviewOperationState state = HostPreviewOperationState.queued;
  DateTime? startedAt;
  DateTime? completedAt;
  int completedItems = 0;
  int totalItems = 0;
  int failedItems = 0;
  Digest? evidenceDigest;
  String? error;
  Future<void>? completion;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'PreviewCollectionOperation',
    'operationId': id,
    'state': state.name,
    if (applicationId != null) 'applicationId': applicationId,
    if (scenarioId != null) 'scenarioId': scenarioId,
    if (variantId != null) 'variantId': variantId,
    'completedItems': completedItems,
    'totalItems': totalItems,
    'failedItems': failedItems,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (completedAt != null)
      'completedAt': completedAt!.toUtc().toIso8601String(),
    if (evidenceDigest != null) 'evidenceDigest': evidenceDigest!.value,
    if (error != null) 'error': error,
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
