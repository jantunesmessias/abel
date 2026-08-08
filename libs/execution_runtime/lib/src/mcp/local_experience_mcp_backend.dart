import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;

import '../composition/builtin_module_catalog.dart';
import '../evidence/dart_test_evidence_provider.dart';
import '../evidence/deterministic_evidence_bundle.dart';
import '../evidence/evidence_comparison_service.dart';
import '../evidence/png_capture_inspector.dart';
import '../host/host_context_builder_service.dart';
import '../host/host_experience_authoring_runtime.dart';
import '../host/host_rpc_server.dart';
import '../host/host_workspace_service.dart';
import '../secure_id_generator.dart';
import '../source/local_source_adapters.dart';
import '../storage/filesystem_workspace_store.dart';
import '../system_clock.dart';
import '../workspace/workspace_catalog_loader.dart';
import '../workspace/workspace_configuration_loader.dart';
import 'experience_mcp_backend.dart';

final class LocalExperienceMcpBackend implements ExperienceMcpBackend {
  factory LocalExperienceMcpBackend.create({
    required LoadedWorkspaceConfiguration configuration,
    required ResolvedKitPlan plan,
  }) {
    HostWorkspaceContent loadContent() => _compileContent(
      configuration,
      motionEnabled: _enabled(plan, 'motion.local'),
    );

    final initial = loadContent();
    final clock = SystemClock();
    final manifest = _effectiveManifest(plan);
    final workspaceStore = FileSystemWorkspaceStore(
      workspaceRoot: configuration.workspaceRoot,
    );
    final workspace = HostWorkspaceService(
      initialCatalog: initial.catalog,
      initialExperienceBundle: initial.experienceBundle,
      initialScenarioFacetManifest: initial.scenarioFacetManifest,
      initialScenarioLabManifest: initial.scenarioLabManifest,
      initialMotionManifest: initial.motionManifest,
      clock: clock,
      providerBindings: plan.providerBindings,
      reloadContent: loadContent,
    );
    workspace.initialize(manifest);
    final authoring = _enabled(plan, 'authoring.local')
        ? HostExperienceAuthoringRuntime.create(
            workspaceRoot: configuration.workspaceRoot,
            workspaceStore: workspaceStore,
            workspace: workspace,
            plan: plan,
            sourceBacked: true,
            publishEvent: (_, _) async {},
            clock: clock.nowUtc,
          )
        : null;
    authoring?.start();
    return LocalExperienceMcpBackend._(
      configuration: configuration,
      plan: plan,
      manifest: manifest,
      workspace: workspace,
      workspaceStore: workspaceStore,
      authoring: authoring,
      contextBuilder: _enabled(plan, 'context.builder.local')
          ? HostContextBuilderService(
              workspace: workspace,
              workspaceRoot: configuration.workspaceRoot,
              sourceBacked: true,
            )
          : null,
    );
  }

  LocalExperienceMcpBackend._({
    required this.configuration,
    required this.plan,
    required this.manifest,
    required this.workspace,
    required this.workspaceStore,
    required this.authoring,
    required this.contextBuilder,
  }) {
    _loadAudit();
  }

  static const int _maxAuditRecords = 10000;
  static const int _maxCaptureBytes = 64 * 1024 * 1024;
  static const String _auditPath = 'mcp/automation-audit.json';
  final LoadedWorkspaceConfiguration configuration;
  final ResolvedKitPlan plan;
  final EffectiveKitManifest manifest;
  final HostWorkspaceService workspace;
  final FileSystemWorkspaceStore workspaceStore;
  final HostExperienceAuthoringRuntime? authoring;
  final HostContextBuilderService? contextBuilder;
  final SecureIdGenerator _ids = SecureIdGenerator();
  final Map<String, _AutomationCapability> _capabilities =
      <String, _AutomationCapability>{};
  final List<Map<String, Object?>> _audit = <Map<String, Object?>>[];

  @override
  List<Map<String, Object?>> get tools => _experienceTools
      .where((tool) => _availableToolNames.contains(tool['name']))
      .toList(growable: false);

  Set<String> get _genericEffectTools => <String>{
    if (_enabled(plan, 'evidence.tests')) 'quality.tests.run',
    if (_enabled(plan, 'artifact-store.local')) 'quality.capture',
  };

  Set<String> get _availableToolNames => <String>{
    'catalog.list',
    'catalog.search',
    'catalog.get',
    if (workspace.experienceBundle != null) ...<String>{
      'catalog.neighborhood',
      'catalog.graph',
    },
    if (contextBuilder != null) 'context.export',
    if (_enabled(plan, 'source.impact')) 'source.excerpt',
    'evidence.index',
    'capture.index',
    'quality.validate',
    'quality.bundle.verify',
    if (_enabled(plan, 'artifact-store.local')) ...<String>{
      'quality.capture.diff',
      'quality.evidence.verify',
    },
    ..._genericEffectTools,
    if (_genericEffectTools.isNotEmpty) ...<String>{
      'capability.issue',
      'capability.revoke',
    },
    if (authoring != null) ...<String>{
      'authoring.describe',
      'authoring.getHead',
      'authoring.getDraft',
      'authoring.getChangeSet',
      'authoring.getReview',
      'authoring.grant',
      'authoring.openDraft',
      'authoring.layout.edit',
      'authoring.layout.batchMutate',
      'authoring.review.prepare',
      'authoring.finding.record',
      'authoring.concept.propose',
      'quality.acceptance.record',
      'authoring.layout.promote',
    },
  };

  @override
  List<Map<String, Object?>> get resources {
    final result = <Map<String, Object?>>[
      _resource('experience://content-set', 'Experience content set'),
      _resource('experience://catalog', 'Catalog manifest'),
    ];
    if (workspace.experienceBundle != null) {
      result.add(_resource('experience://topology', 'Experience graph'));
    }
    if (workspace.scenarioFacetManifest != null) {
      result.add(_resource('experience://facets', 'Scenario facets'));
    }
    if (workspace.scenarioLabManifest != null) {
      result.add(_resource('experience://scenario-lab', 'Scenario Lab'));
    }
    if (workspace.motionManifest != null) {
      result.add(_resource('experience://motion', 'Motion manifest'));
    }
    return result;
  }

  @override
  Future<Object?> readResource({
    required String uri,
    required String principalId,
  }) async => switch (uri) {
    'experience://content-set' => workspace.contentSetIdentity.toJson(),
    'experience://catalog' => workspace.snapshot.catalog.toJson(),
    'experience://topology' =>
      workspace.experienceBundle?.toJson() ??
          (throw const ExperienceMcpToolException('resourceUnavailable')),
    'experience://facets' =>
      workspace.scenarioFacetManifest?.toJson() ??
          (throw const ExperienceMcpToolException('resourceUnavailable')),
    'experience://scenario-lab' =>
      workspace.scenarioLabManifest?.toJson() ??
          (throw const ExperienceMcpToolException('resourceUnavailable')),
    'experience://motion' =>
      workspace.motionManifest?.toJson() ??
          (throw const ExperienceMcpToolException('resourceUnavailable')),
    _ => throw const ExperienceMcpToolException('resourceNotFound'),
  };

  @override
  Future<Object?> call({
    required String name,
    required Map<String, Object?> arguments,
    required String principalId,
    required String connectionEpoch,
  }) async {
    if (!_availableToolNames.contains(name)) {
      throw const ExperienceMcpToolException('unknownTool');
    }
    if (name == 'capability.issue') {
      return _issueCapability(arguments, principalId);
    }
    if (name == 'capability.revoke') {
      return _revokeCapability(arguments, principalId);
    }
    if (_genericEffectTools.contains(name)) {
      return _runGenericEffect(
        name: name,
        arguments: arguments,
        principalId: principalId,
      );
    }
    return switch (name) {
      'catalog.list' => _list(arguments),
      'catalog.search' => _search(arguments),
      'catalog.get' => _get(arguments),
      'catalog.neighborhood' => _neighborhood(arguments),
      'catalog.graph' => _graph(arguments),
      'context.export' => _context(arguments),
      'source.excerpt' => _sourceExcerpt(arguments),
      'evidence.index' => _evidenceIndex(arguments),
      'capture.index' => _captureIndex(arguments),
      'quality.validate' => _validate(arguments),
      'quality.capture.diff' => _diffCapture(arguments),
      'quality.bundle.verify' => _verifyBundle(arguments),
      'quality.evidence.verify' => _verifyEvidence(arguments),
      'authoring.describe' => _authoringCall(
        ExperienceAuthoringRpcMethod.describe,
        _request(arguments),
        connectionEpoch,
      ),
      'authoring.getHead' => _authoringCall(
        ExperienceAuthoringRpcMethod.getSubjectHead,
        _request(arguments),
        connectionEpoch,
      ),
      'authoring.getDraft' => _authoringCall(
        ExperienceAuthoringRpcMethod.getDraft,
        _request(arguments),
        connectionEpoch,
      ),
      'authoring.getChangeSet' => _authoringCall(
        ExperienceAuthoringRpcMethod.getChangeSet,
        _request(arguments),
        connectionEpoch,
      ),
      'authoring.getReview' => _authoringCall(
        ExperienceAuthoringRpcMethod.getReview,
        _request(arguments),
        connectionEpoch,
      ),
      'authoring.grant' => _authoringGrant(arguments, connectionEpoch),
      'authoring.openDraft' => _authoringCall(
        ExperienceAuthoringRpcMethod.openDraft,
        _request(arguments),
        connectionEpoch,
      ),
      'authoring.layout.edit' => _authoringMutation(arguments, connectionEpoch),
      'authoring.layout.batchMutate' => _authoringBatch(
        arguments,
        connectionEpoch,
      ),
      'authoring.review.prepare' => _authoringCall(
        ExperienceAuthoringRpcMethod.prepareReview,
        _request(arguments),
        connectionEpoch,
      ),
      'authoring.finding.record' => _reviewAction(
        arguments,
        connectionEpoch,
        AuthoringOperation.appendFinding,
      ),
      'authoring.concept.propose' => _reviewAction(
        arguments,
        connectionEpoch,
        AuthoringOperation.proposeConcept,
      ),
      'quality.acceptance.record' => _reviewAction(
        arguments,
        connectionEpoch,
        AuthoringOperation.evaluateAutomatedAcceptance,
      ),
      'authoring.layout.promote' => _authoringCall(
        ExperienceAuthoringRpcMethod.applyPromotion,
        _request(arguments),
        connectionEpoch,
      ),
      _ => throw const ExperienceMcpToolException('unknownTool'),
    };
  }

  Map<String, Object?> _list(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'kind', 'offset', 'limit'});
    final kind = _string(arguments, 'kind');
    final offset = _optionalInt(arguments, 'offset', defaultValue: 0);
    final limit = _optionalInt(arguments, 'limit', defaultValue: 100);
    if (offset < 0 || limit < 1 || limit > 500) {
      throw const FormatException('Invalid page');
    }
    final entities = _entities(kind);
    final page = offset >= entities.length
        ? const <Map<String, Object?>>[]
        : entities.sublist(
            offset,
            offset + limit > entities.length ? entities.length : offset + limit,
          );
    return <String, Object?>{
      'kind': kind,
      'offset': offset,
      'limit': limit,
      'totalCount': entities.length,
      'items': page,
      'contentSetDigest': workspace.contentSetIdentity.contentSetDigest.value,
    };
  }

  Map<String, Object?> _search(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'query', 'kinds', 'limit'});
    final query = _string(arguments, 'query').toLowerCase();
    if (utf8.encode(query).length > 256) {
      throw const FormatException('Query is too large');
    }
    final kinds = arguments['kinds'] == null
        ? _entityKinds
        : _stringList(
            arguments['kinds'],
            maxItems: _entityKinds.length,
          ).toSet();
    if (!kinds.every(_entityKinds.contains)) {
      throw const FormatException('Unknown entity kind');
    }
    final limit = _optionalInt(arguments, 'limit', defaultValue: 50);
    if (limit < 1 || limit > 100) throw const FormatException('Invalid limit');
    final matches = <Map<String, Object?>>[];
    for (final kind in kinds.toList()..sort()) {
      for (final item in _entities(kind)) {
        final searchable = const JcsCanonicalizer()
            .canonicalize(item)
            .toLowerCase();
        if (searchable.contains(query)) {
          matches.add(<String, Object?>{'kind': kind, 'entity': item});
          if (matches.length == limit) break;
        }
      }
      if (matches.length == limit) break;
    }
    return <String, Object?>{
      'query': query,
      'items': matches,
      'truncated': matches.length == limit,
      'contentSetDigest': workspace.contentSetIdentity.contentSetDigest.value,
    };
  }

  Map<String, Object?> _get(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'kind', 'id'});
    final kind = _string(arguments, 'kind');
    final id = _string(arguments, 'id');
    final matches = _entities(
      kind,
    ).where((entity) => entity['id'] == id).toList(growable: false);
    if (matches.length != 1) {
      throw const ExperienceMcpToolException('entityNotFound');
    }
    return <String, Object?>{
      'kind': kind,
      'entity': matches.single,
      'contentSetDigest': workspace.contentSetIdentity.contentSetDigest.value,
    };
  }

  Map<String, Object?> _neighborhood(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'projectionId', 'nodeId', 'depth'});
    final bundle = _bundle();
    final projectionId = ExperienceProjectionId(
      _string(arguments, 'projectionId'),
    );
    final start = NodeInstanceId(_string(arguments, 'nodeId'));
    final depth = _optionalInt(arguments, 'depth', defaultValue: 1);
    if (depth < 0 || depth > 3) throw const FormatException('Invalid depth');
    final projection = bundle.topology.projections
        .where((item) => item.id == projectionId)
        .firstOrNull;
    if (projection == null || !projection.nodeInstanceIds.contains(start)) {
      throw const ExperienceMcpToolException('entityNotFound');
    }
    var frontier = <NodeInstanceId>{start};
    final visited = <NodeInstanceId>{start};
    final edges = <EdgeInstance>{};
    for (var level = 0; level < depth; level += 1) {
      final next = <NodeInstanceId>{};
      for (final edge in bundle.topology.edges.where(
        (edge) => edge.projectionId == projectionId,
      )) {
        if (frontier.contains(edge.fromNodeId) ||
            frontier.contains(edge.toNodeId)) {
          edges.add(edge);
          next
            ..add(edge.fromNodeId)
            ..add(edge.toNodeId);
        }
      }
      next.removeAll(visited);
      visited.addAll(next);
      frontier = next;
    }
    return <String, Object?>{
      'projectionId': projectionId.value,
      'rootNodeId': start.value,
      'depth': depth,
      'nodes': bundle.topology.nodes
          .where((node) => visited.contains(node.id))
          .map((node) => node.toJson())
          .toList(),
      'edges':
          (edges.toList()..sort(
                (left, right) => left.id.value.compareTo(right.id.value),
              ))
              .map((edge) => edge.toJson())
              .toList(),
    };
  }

  Map<String, Object?> _graph(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'projectionId'});
    final bundle = _bundle();
    final id = ExperienceProjectionId(_string(arguments, 'projectionId'));
    final projection = bundle.topology.projections
        .where((item) => item.id == id)
        .firstOrNull;
    final layout = bundle.layouts
        .where((item) => item.projectionId == id)
        .firstOrNull;
    if (projection == null || layout == null) {
      throw const ExperienceMcpToolException('entityNotFound');
    }
    return <String, Object?>{
      'projection': projection.toJson(),
      'nodes': bundle.topology.nodes
          .where((node) => node.projectionId == id)
          .map((node) => node.toJson())
          .toList(),
      'edges': bundle.topology.edges
          .where((edge) => edge.projectionId == id)
          .map((edge) => edge.toJson())
          .toList(),
      'layout': layout.toJson(),
      'contentSetDigest': workspace.contentSetIdentity.contentSetDigest.value,
    };
  }

  Map<String, Object?> _context(Map<String, Object?> arguments) {
    final service = contextBuilder;
    if (service == null) {
      throw const ExperienceMcpToolException('capabilityUnavailable');
    }
    return service.build(ContextBuildRequest.fromJson(arguments)).toJson();
  }

  Map<String, Object?> _sourceExcerpt(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'scenarioId', 'maxBytes'});
    final scenarioId = ScenarioId(_string(arguments, 'scenarioId'));
    final scenario = workspace.snapshot.catalog.scenarios
        .where((item) => item.id == scenarioId)
        .firstOrNull;
    if (scenario == null || scenario.sourceReferences.isEmpty) {
      throw const ExperienceMcpToolException('sourceUnavailable');
    }
    final maxBytes = _optionalInt(arguments, 'maxBytes', defaultValue: 32768);
    if (maxBytes < 1 || maxBytes > 65536) {
      throw const FormatException('Invalid source budget');
    }
    final path = scenario.sourceReferences.first.path;
    final snapshot = const FilesystemSourceAdapter().inspect(
      root: configuration.workspaceRoot,
    );
    final bundle =
        LocalContextBundleExporter(
          maxFileBytes: maxBytes,
          maxTotalBytes: maxBytes,
        ).export(
          snapshot: snapshot,
          root: configuration.workspaceRoot,
          paths: <String>[path],
        );
    return <String, Object?>{
      'scenarioId': scenarioId.value,
      'snapshotDigest': bundle.snapshotDigest.value,
      'files': bundle.files.map((file) => file.toJson()).toList(),
      'redactions': bundle.redactions,
    };
  }

  Map<String, Object?> _evidenceIndex(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'scenarioId'});
    final scenario = arguments['scenarioId'];
    if (scenario != null && scenario is! String) {
      throw const FormatException('scenarioId must be a string');
    }
    final projections = workspace.snapshot.visualProjections
        .where((item) => scenario == null || item.scenarioId?.value == scenario)
        .map(
          (item) => <String, Object?>{
            if (item.scenarioId != null) 'scenarioId': item.scenarioId!.value,
            if (item.variantId != null) 'variantId': item.variantId!.value,
            'providerId': item.providerId.value,
            'status': item.status.name,
            'freshness': item.freshness.name,
            if (item.fidelity != null) 'fidelity': item.fidelity!.name,
            if (item.artifactDigest != null)
              'artifactDigest': item.artifactDigest!.value,
            if (item.captureKey != null) 'captureKey': item.captureKey!.value,
          },
        )
        .toList();
    return <String, Object?>{
      'items': projections,
      'workspaceContentDigest': workspace.snapshot.workspaceContentDigest.value,
    };
  }

  Map<String, Object?> _captureIndex(Map<String, Object?> arguments) {
    final result = _evidenceIndex(arguments);
    result['items'] = (result['items']! as List<Object?>)
        .whereType<Map<String, Object?>>()
        .where((item) => item.containsKey('artifactDigest'))
        .toList();
    return result;
  }

  Map<String, Object?> _validate(Map<String, Object?> arguments) {
    _only(arguments, const <String>{});
    final refresh = workspace.refreshContent(manifest);
    return <String, Object?>{
      'valid': true,
      'catalogDigest': workspace.snapshot.catalog.digest.value,
      'contentSetDigest': workspace.contentSetIdentity.contentSetDigest.value,
      'catalogChanged': refresh.catalogChanged,
      'experienceChanged': refresh.experienceChanged,
      'facetsChanged': refresh.facetsChanged,
      'scenarioLabChanged': refresh.scenarioLabChanged,
      'motionChanged': refresh.motionChanged,
    };
  }

  Map<String, Object?> _diffCapture(Map<String, Object?> arguments) {
    _only(arguments, const <String>{
      'expectedDigest',
      'actualDigest',
      'policy',
    });
    final expected = workspaceStore.readBlobBounded(
      Digest(_string(arguments, 'expectedDigest')),
      maxBytes: _maxCaptureBytes,
    );
    final actual = workspaceStore.readBlobBounded(
      Digest(_string(arguments, 'actualDigest')),
      maxBytes: _maxCaptureBytes,
    );
    if (expected == null || actual == null) {
      throw const ExperienceMcpToolException('artifactUnavailable');
    }
    return const EvidenceComparisonService()
        .compareVisual(
          expected: expected,
          actual: actual,
          policy: VisualComparisonPolicy.fromJson(arguments['policy']),
        )
        .toJson();
  }

  Map<String, Object?> _verifyBundle(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'path'});
    final file = _workspaceFile(_string(arguments, 'path'));
    final verified = const DeterministicEvidenceBundleRepository().verify(
      file.path,
    );
    return <String, Object?>{
      'archiveDigest': verified.archiveDigest.value,
      'size': verified.size,
      'manifest': verified.manifest.toJson(),
    };
  }

  Map<String, Object?> _verifyEvidence(Map<String, Object?> arguments) {
    _only(arguments, const <String>{'evidence'});
    final evidence = Evidence.fromJson(arguments['evidence']);
    for (final artifact in evidence.artifacts) {
      final bytes = workspaceStore.readBlobBounded(
        artifact.digest,
        maxBytes: _maxCaptureBytes,
        expectedSize: artifact.size,
      );
      if (bytes == null) {
        throw const ExperienceMcpToolException('artifactUnavailable');
      }
    }
    return <String, Object?>{
      'verified': true,
      'evidenceDigest': evidence.digest.value,
      'artifactCount': evidence.artifacts.length,
    };
  }

  Future<Object?> _authoringCall(
    String method,
    Map<String, Object?> request,
    String connectionEpoch,
  ) async {
    final runtime = authoring;
    if (runtime == null) {
      throw const ExperienceMcpToolException('capabilityUnavailable');
    }
    try {
      return await runtime.call(
        method,
        request,
        connectionEpoch: connectionEpoch,
      );
    } on HostRpcApplicationException catch (error) {
      try {
        final typed = ExperienceAuthoringError.fromJson(error.data);
        throw ExperienceMcpToolException(
          'authoring.${typed.code.name}',
          details: typed.toJson(),
        );
      } on ExperienceMcpToolException {
        rethrow;
      } on Object {
        throw const ExperienceMcpToolException('authoringRejected');
      }
    } on Object {
      throw const ExperienceMcpToolException('authoringRejected');
    }
  }

  Future<Object?> _authoringGrant(
    Map<String, Object?> arguments,
    String connectionEpoch,
  ) {
    _only(arguments, const <String>{'request'});
    final request = _request(arguments);
    final kind = request['kind'];
    final method = switch (kind) {
      'AuthoringGrantRequest' => ExperienceAuthoringRpcMethod.requestGrant,
      'ExperienceReviewDecisionGrantRequest' =>
        ExperienceAuthoringRpcMethod.requestDecisionGrant,
      'ExperiencePromotionGrantRequest' =>
        ExperienceAuthoringRpcMethod.requestPromotionGrant,
      _ => throw const FormatException('Unknown grant request'),
    };
    return _authoringCall(method, request, connectionEpoch);
  }

  Future<Object?> _authoringMutation(
    Map<String, Object?> arguments,
    String connectionEpoch,
  ) {
    final request = _request(arguments);
    LayoutDraftMutationRequest.fromJson(request);
    return _authoringCall(
      ExperienceAuthoringRpcMethod.mutateDraft,
      request,
      connectionEpoch,
    );
  }

  Future<Object?> _authoringBatch(
    Map<String, Object?> arguments,
    String connectionEpoch,
  ) async {
    _only(arguments, const <String>{'requests'});
    final values = arguments['requests'];
    if (values is! List<Object?> || values.isEmpty || values.length > 16) {
      throw const FormatException('Batch is invalid');
    }
    final requests = values
        .map(LayoutDraftMutationRequest.fromJson)
        .toList(growable: false);
    for (var index = 1; index < requests.length; index += 1) {
      if (requests[index].draftId != requests.first.draftId ||
          requests[index].expectedDraftRevision !=
              requests[index - 1].expectedDraftRevision + 1) {
        throw const FormatException('Batch draft chain is invalid');
      }
    }
    final results = <Object?>[];
    for (final request in requests) {
      results.add(
        await _authoringCall(
          ExperienceAuthoringRpcMethod.mutateDraft,
          request.toJson(),
          connectionEpoch,
        ),
      );
    }
    return <String, Object?>{
      'resultType': 'complete',
      'atomic': false,
      'attemptCount': results.length,
      'results': results,
    };
  }

  Future<Object?> _reviewAction(
    Map<String, Object?> arguments,
    String connectionEpoch,
    AuthoringOperation expected,
  ) {
    final request = ExperienceReviewActionRequest.fromJson(_request(arguments));
    if (request.operation != expected) {
      throw const FormatException('Review operation mismatch');
    }
    return _authoringCall(
      ExperienceAuthoringRpcMethod.reviewAction,
      request.toJson(),
      connectionEpoch,
    );
  }

  Map<String, Object?> _issueCapability(
    Map<String, Object?> arguments,
    String principalId,
  ) {
    _only(arguments, const <String>{
      'requestId',
      'tool',
      'expectedDigest',
      'input',
    });
    final tool = _string(arguments, 'tool');
    if (!_genericEffectTools.contains(tool)) {
      throw const ExperienceMcpToolException('capabilityUnavailable');
    }
    final expected = Digest(_string(arguments, 'expectedDigest'));
    if (expected != workspace.contentSetIdentity.contentSetDigest) {
      throw const ExperienceMcpToolException('stale');
    }
    _requireAuditCapacity(1);
    final input = _map(arguments['input'], 'input');
    final now = DateTime.now().toUtc();
    final capability = _AutomationCapability(
      id: _ids.nextId(),
      principalId: principalId,
      tool: tool,
      expectedDigest: expected,
      payloadDigest: Digest.semantic(input),
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 2)),
      state: 'active',
    );
    _capabilities[capability.id] = capability;
    _appendAudit(
      requestId: _string(arguments, 'requestId'),
      principalId: principalId,
      operation: 'capability.issue',
      outcome: 'issued',
      subjectDigest: capability.digest,
    );
    return capability.toJson();
  }

  Map<String, Object?> _revokeCapability(
    Map<String, Object?> arguments,
    String principalId,
  ) {
    _only(arguments, const <String>{
      'requestId',
      'capabilityId',
      'capabilityDigest',
    });
    final capability = _capability(arguments, principalId);
    if (capability.state != 'active') {
      throw const ExperienceMcpToolException('capabilityConsumed');
    }
    _requireAuditCapacity(1);
    capability.state = 'revoked';
    _appendAudit(
      requestId: _string(arguments, 'requestId'),
      principalId: principalId,
      operation: 'capability.revoke',
      outcome: 'revoked',
      subjectDigest: capability.digest,
    );
    return <String, Object?>{'revoked': true, 'capabilityId': capability.id};
  }

  Future<Object?> _runGenericEffect({
    required String name,
    required Map<String, Object?> arguments,
    required String principalId,
  }) async {
    _only(arguments, const <String>{
      'requestId',
      'capabilityId',
      'capabilityDigest',
      'expectedDigest',
      'input',
    });
    final capability = _capability(arguments, principalId);
    final expected = Digest(_string(arguments, 'expectedDigest'));
    final input = _map(arguments['input'], 'input');
    if (capability.state != 'active' ||
        !DateTime.now().toUtc().isBefore(capability.expiresAt) ||
        capability.tool != name ||
        capability.expectedDigest != expected ||
        expected != workspace.contentSetIdentity.contentSetDigest ||
        capability.payloadDigest != Digest.semantic(input)) {
      _requireAuditCapacity(1);
      capability.state = 'consumed';
      _appendAudit(
        requestId: _string(arguments, 'requestId'),
        principalId: principalId,
        operation: name,
        outcome: 'rejected',
        subjectDigest: capability.digest,
      );
      throw const ExperienceMcpToolException('capabilityMismatch');
    }
    _requireAuditCapacity(2);
    capability.state = 'inFlight';
    _appendAudit(
      requestId: _string(arguments, 'requestId'),
      principalId: principalId,
      operation: name,
      outcome: 'started',
      subjectDigest: capability.digest,
    );
    late final Object? result;
    try {
      result = await switch (name) {
        'quality.tests.run' => _runTests(input),
        'quality.capture' => Future<Object?>.value(_capture(input)),
        _ => throw const ExperienceMcpToolException('unknownTool'),
      };
    } on Object catch (error, stackTrace) {
      capability.state = 'consumed';
      _appendAudit(
        requestId: _string(arguments, 'requestId'),
        principalId: principalId,
        operation: name,
        outcome: 'failed',
        subjectDigest: capability.digest,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    capability.state = 'consumed';
    _appendAudit(
      requestId: _string(arguments, 'requestId'),
      principalId: principalId,
      operation: name,
      outcome: 'succeeded',
      subjectDigest: capability.digest,
    );
    return result;
  }

  Future<Object?> _runTests(Map<String, Object?> input) async {
    _only(input, const <String>{'runner', 'targets'});
    final runner = switch (_string(input, 'runner')) {
      'dart' => DartTestRunner.dart,
      'flutter' => DartTestRunner.flutter,
      _ => throw const FormatException('Unknown test runner'),
    };
    final targets = _stringList(input['targets'], maxItems: 32);
    final result = await DartTestEvidenceProvider(
      workspaceRoot: configuration.workspaceRoot,
    ).collect(runner: runner, targets: targets);
    return result.toJson();
  }

  Map<String, Object?> _capture(Map<String, Object?> input) {
    _only(input, const <String>{'path', 'classification'});
    final file = _workspaceFile(_string(input, 'path'));
    final size = file.lengthSync();
    if (size <= 0 || size > _maxCaptureBytes) {
      throw const ExperienceMcpToolException('captureQuotaExceeded');
    }
    final bytes = file.readAsBytesSync();
    final inspection = const PngCaptureInspector().inspect(bytes);
    final digest = workspaceStore.withExclusiveLock(
      () => workspaceStore.putBlob(bytes),
    );
    return <String, Object?>{
      'artifactDigest': digest.value,
      'size': bytes.length,
      'mediaType': 'image/png',
      'classification': _string(input, 'classification'),
      'width': inspection.width,
      'height': inspection.height,
    };
  }

  _AutomationCapability _capability(
    Map<String, Object?> arguments,
    String principalId,
  ) {
    final id = _string(arguments, 'capabilityId');
    final capability = _capabilities[id];
    if (capability == null ||
        capability.principalId != principalId ||
        capability.digest != Digest(_string(arguments, 'capabilityDigest'))) {
      throw const ExperienceMcpToolException('capabilityMismatch');
    }
    return capability;
  }

  void _appendAudit({
    required String requestId,
    required String principalId,
    required String operation,
    required String outcome,
    required Digest subjectDigest,
  }) {
    if (_audit.length >= _maxAuditRecords) {
      throw const ExperienceMcpToolException('auditQuotaExceeded');
    }
    final previous = _audit.isEmpty ? null : _audit.last['digest']! as String;
    final record = <String, Object?>{
      'sequence': _audit.length + 1,
      'requestDigest': Digest.semantic(requestId).value,
      'principalDigest': Digest.semantic(principalId).value,
      'operation': operation,
      'outcome': outcome,
      'subjectDigest': subjectDigest.value,
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      'previousDigest': ?previous,
    };
    record['digest'] = Digest.semantic(record).value;
    _audit.add(Map<String, Object?>.unmodifiable(record));
    workspaceStore.withExclusiveLock(() {
      workspaceStore.atomicWrite(
        _auditPath,
        utf8.encode(
          '${const JcsCanonicalizer().canonicalize(<String, Object?>{'schemaVersion': 1, 'kind': 'McpAutomationAudit', 'records': _audit})}\n',
        ),
      );
    });
  }

  void _requireAuditCapacity(int additionalRecords) {
    if (additionalRecords < 1 ||
        _audit.length > _maxAuditRecords - additionalRecords) {
      throw const ExperienceMcpToolException('auditQuotaExceeded');
    }
  }

  void _loadAudit() {
    final bytes = workspaceStore.readStateBytesBounded(
      _auditPath,
      maxBytes: 8 * 1024 * 1024,
    );
    if (bytes == null) return;
    final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    final document = _map(value, 'McpAutomationAudit');
    _only(document, const <String>{'schemaVersion', 'kind', 'records'});
    if (document['schemaVersion'] != 1 ||
        document['kind'] != 'McpAutomationAudit' ||
        document['records'] is! List<Object?>) {
      throw const FormatException('MCP audit is invalid');
    }
    final records = document['records']! as List<Object?>;
    if (records.length > _maxAuditRecords) {
      throw const FormatException('MCP audit exceeds quota');
    }
    String? previous;
    for (var index = 0; index < records.length; index += 1) {
      final record = _map(records[index], 'McpAutomationAudit.record');
      _only(record, const <String>{
        'sequence',
        'requestDigest',
        'principalDigest',
        'operation',
        'outcome',
        'subjectDigest',
        'recordedAt',
        'previousDigest',
        'digest',
      });
      if (!record.keys.toSet().containsAll(const <String>{
            'sequence',
            'requestDigest',
            'principalDigest',
            'operation',
            'outcome',
            'subjectDigest',
            'recordedAt',
            'digest',
          }) ||
          record['sequence'] is! int ||
          record['previousDigest'] != null &&
              record['previousDigest'] is! String) {
        throw const FormatException('MCP audit record is invalid');
      }
      Digest(_string(record, 'requestDigest'));
      Digest(_string(record, 'principalDigest'));
      Digest(_string(record, 'subjectDigest'));
      if (record['previousDigest'] case final String digest) Digest(digest);
      final outcome = _string(record, 'outcome');
      if (!const <String>{
        'issued',
        'revoked',
        'rejected',
        'started',
        'succeeded',
        'failed',
      }.contains(outcome)) {
        throw const FormatException('MCP audit outcome is invalid');
      }
      _string(record, 'operation');
      final recordedAt = DateTime.tryParse(_string(record, 'recordedAt'));
      if (recordedAt == null || !recordedAt.isUtc) {
        throw const FormatException('MCP audit timestamp is invalid');
      }
      final declared = record['digest'];
      final content = Map<String, Object?>.of(record)..remove('digest');
      if (record['sequence'] != index + 1 ||
          record['previousDigest'] != previous ||
          declared is! String ||
          Digest(declared).value != declared ||
          declared != Digest.semantic(content).value) {
        throw const FormatException('MCP audit chain is invalid');
      }
      previous = declared;
      _audit.add(Map<String, Object?>.unmodifiable(record));
    }
  }

  @override
  Future<void> close({required String connectionEpoch}) async {
    for (final capability in _capabilities.values) {
      if (capability.state == 'active' || capability.state == 'inFlight') {
        capability.state = 'revoked';
      }
    }
    authoring?.connectionClosed(connectionEpoch);
    authoring?.close();
  }

  ExperienceTopologyBundle _bundle() =>
      workspace.experienceBundle ??
      (throw const ExperienceMcpToolException('topologyUnavailable'));

  List<Map<String, Object?>> _entities(String kind) => switch (kind) {
    'application' =>
      workspace.snapshot.catalog.applications
          .map((item) => item.toJson())
          .toList(),
    'journey' =>
      workspace.snapshot.catalog.journeys.map((item) => item.toJson()).toList(),
    'scenario' =>
      workspace.snapshot.catalog.scenarios
          .map((item) => item.toJson())
          .toList(),
    'transition' =>
      workspace.snapshot.catalog.transitions
          .map((item) => item.toJson())
          .toList(),
    'board' => _bundle().topology.boards.map((item) => item.toJson()).toList(),
    'projection' =>
      _bundle().topology.projections.map((item) => item.toJson()).toList(),
    'node' => _bundle().topology.nodes.map((item) => item.toJson()).toList(),
    'edge' => _bundle().topology.edges.map((item) => item.toJson()).toList(),
    _ => throw const FormatException('Unknown entity kind'),
  };

  File _workspaceFile(String relative) {
    if (p.isAbsolute(relative) || relative.contains('\u0000')) {
      throw const FormatException('Path must be workspace-relative');
    }
    final normalized = p.normalize(
      p.join(configuration.workspaceRoot, relative),
    );
    if (!p.isWithin(configuration.workspaceRoot, normalized)) {
      throw const FormatException('Path escapes workspace');
    }
    final file = File(normalized);
    if (!file.existsSync()) {
      throw const ExperienceMcpToolException('fileUnavailable');
    }
    _rejectLinkedPath(configuration.workspaceRoot, normalized);
    final resolved = file.resolveSymbolicLinksSync();
    if (!p.isWithin(configuration.workspaceRoot, resolved) ||
        File(resolved).statSync().type != FileSystemEntityType.file) {
      throw const FormatException('Path escapes workspace');
    }
    return File(resolved);
  }
}

void _rejectLinkedPath(String root, String path) {
  var current = root;
  final relative = p.relative(path, from: root);
  for (final segment in p.split(relative)) {
    current = p.join(current, segment);
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException('Path crosses a link');
    }
  }
}

HostWorkspaceContent _compileContent(
  LoadedWorkspaceConfiguration configuration, {
  required bool motionEnabled,
}) {
  final loaded = const WorkspaceCatalogLoader().loadFromConfiguration(
    configuration,
  );
  final catalog = const CatalogCompiler().compile(
    loaded.documents,
    layout: loaded.layout,
  );
  const topologyCompiler = ExperienceTopologyCompiler();
  final ExperienceTopologyBundle? bundle;
  if (topologyCompiler.hasAuthoring(loaded.documents)) {
    final compiled = topologyCompiler.compile(
      loaded.documents,
      catalog: catalog,
    );
    bundle = ExperienceTopologyBundle(
      catalog: catalog,
      topology: compiled.topology,
      layouts: compiled.layouts,
    );
  } else {
    bundle = null;
  }
  const facetCompiler = ScenarioFacetCompiler();
  final facets = facetCompiler.hasAuthoring(loaded.documents)
      ? facetCompiler.compile(loaded.documents, catalog: catalog)
      : null;
  const labCompiler = ScenarioLabCompiler();
  final lab = labCompiler.hasAuthoring(loaded.documents)
      ? labCompiler.compile(loaded.documents, catalog: catalog)
      : null;
  const motionCompiler = MotionManifestCompiler();
  final motion =
      motionEnabled &&
          bundle != null &&
          motionCompiler.hasAuthoring(loaded.documents)
      ? motionCompiler.compile(
          loaded.documents,
          catalog: catalog,
          topology: bundle.topology,
        )
      : null;
  return HostWorkspaceContent(
    catalog: catalog,
    experienceBundle: bundle,
    scenarioFacetManifest: facets,
    scenarioLabManifest: lab,
    motionManifest: motion,
  );
}

bool _enabled(ResolvedKitPlan plan, String moduleId) =>
    plan.enabledModules.any((module) => module.moduleId.value == moduleId);

EffectiveKitManifest _effectiveManifest(ResolvedKitPlan plan) {
  final catalog = const BuiltinModuleCatalog().create(
    platform: switch (Platform.operatingSystem) {
      'linux' => 'linux-x64',
      'macos' => 'macos-arm64',
      'windows' => 'windows-x64',
      final value => '$value-native',
    },
  );
  final descriptors = <ModuleId, ModuleDescriptor>{
    for (final descriptor in catalog.modules) descriptor.id: descriptor,
  };
  return EffectiveKitManifest(
    resolvedPlanDigest: plan.digest,
    modules: <EffectiveModuleState>[
      for (final module in plan.enabledModules)
        EffectiveModuleState(
          moduleId: module.moduleId,
          state: ModuleRuntimeState.ready,
          health: ModuleHealth.healthy,
          effectiveCapabilities:
              descriptors[module.moduleId]?.provides ??
              (throw StateError('Resolved module is not built in')),
        ),
    ],
    commands: const <String>[],
    rpcMethods: const <String>[],
    studioContributions: const <String>[],
    generatedAt: DateTime.utc(1970),
  );
}

const Set<String> _entityKinds = <String>{
  'application',
  'journey',
  'scenario',
  'transition',
  'board',
  'projection',
  'node',
  'edge',
};

Map<String, Object?> _resource(String uri, String name) => <String, Object?>{
  'uri': uri,
  'name': name,
  'mimeType': 'application/json',
};

Map<String, Object?> _request(Map<String, Object?> arguments) {
  _only(arguments, const <String>{'request'});
  return _map(arguments['request'], 'request');
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

String _string(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String ||
      result.isEmpty ||
      utf8.encode(result).length > 4096) {
    throw FormatException('$key must be a bounded string');
  }
  return result;
}

int _optionalInt(
  Map<String, Object?> value,
  String key, {
  required int defaultValue,
}) {
  final result = value[key];
  if (result == null) return defaultValue;
  if (result is! int) throw FormatException('$key must be an integer');
  return result;
}

List<String> _stringList(Object? value, {required int maxItems}) {
  if (value is! List<Object?> || value.isEmpty || value.length > maxItems) {
    throw const FormatException('Expected a bounded string list');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String || item.isEmpty || utf8.encode(item).length > 4096) {
      throw const FormatException('Expected a bounded string list');
    }
    result.add(item);
  }
  return result;
}

void _only(Map<String, Object?> value, Set<String> allowed) {
  if (value.keys.toSet().difference(allowed).isNotEmpty) {
    throw const FormatException('Unknown fields');
  }
}

final class _AutomationCapability {
  _AutomationCapability({
    required this.id,
    required this.principalId,
    required this.tool,
    required this.expectedDigest,
    required this.payloadDigest,
    required this.issuedAt,
    required this.expiresAt,
    required this.state,
  });

  final String id;
  final String principalId;
  final String tool;
  final Digest expectedDigest;
  final Digest payloadDigest;
  final DateTime issuedAt;
  final DateTime expiresAt;
  String state;

  late final Digest digest = Digest.semantic(<String, Object?>{
    'id': id,
    'principalId': principalId,
    'tool': tool,
    'expectedDigest': expectedDigest.value,
    'payloadDigest': payloadDigest.value,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'singleUse': true,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'kind': 'McpAutomationCapability',
    'id': id,
    'principalId': principalId,
    'tool': tool,
    'expectedDigest': expectedDigest.value,
    'payloadDigest': payloadDigest.value,
    'issuedAt': issuedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'singleUse': true,
    'digest': digest.value,
  };
}

Map<String, Object?> _tool(
  String name,
  String title, {
  required bool readOnly,
  required Map<String, Object?> properties,
  required List<String> required,
}) => <String, Object?>{
  'name': name,
  'title': title,
  'description': title,
  'inputSchema': <String, Object?>{
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  },
  'annotations': <String, Object?>{
    'readOnlyHint': readOnly,
    'destructiveHint': false,
    'idempotentHint': readOnly,
  },
};

const Map<String, Object?> _stringSchema = <String, Object?>{
  'type': 'string',
  'minLength': 1,
  'maxLength': 4096,
};
const Map<String, Object?> _objectSchema = <String, Object?>{'type': 'object'};

final List<Map<String, Object?>> _experienceTools = <Map<String, Object?>>[
  _tool(
    'catalog.list',
    'List typed catalog entities',
    readOnly: true,
    properties: <String, Object?>{
      'kind': _stringSchema,
      'offset': <String, Object?>{'type': 'integer'},
      'limit': <String, Object?>{'type': 'integer'},
    },
    required: <String>['kind'],
  ),
  _tool(
    'catalog.search',
    'Search typed catalog entities',
    readOnly: true,
    properties: <String, Object?>{
      'query': _stringSchema,
      'kinds': <String, Object?>{'type': 'array', 'items': _stringSchema},
      'limit': <String, Object?>{'type': 'integer'},
    },
    required: <String>['query'],
  ),
  _tool(
    'catalog.get',
    'Get one typed catalog entity',
    readOnly: true,
    properties: <String, Object?>{'kind': _stringSchema, 'id': _stringSchema},
    required: <String>['kind', 'id'],
  ),
  _tool(
    'catalog.neighborhood',
    'Read a bounded graph neighborhood',
    readOnly: true,
    properties: <String, Object?>{
      'projectionId': _stringSchema,
      'nodeId': _stringSchema,
      'depth': <String, Object?>{'type': 'integer'},
    },
    required: <String>['projectionId', 'nodeId'],
  ),
  _tool(
    'catalog.graph',
    'Read one projection graph',
    readOnly: true,
    properties: <String, Object?>{'projectionId': _stringSchema},
    required: <String>['projectionId'],
  ),
  _tool(
    'context.export',
    'Export deterministic semantic context',
    readOnly: true,
    properties: <String, Object?>{
      'expectedContentSetDigest': _stringSchema,
      'selection': _objectSchema,
      'inclusion': _objectSchema,
      'budgets': _objectSchema,
    },
    required: <String>[
      'expectedContentSetDigest',
      'selection',
      'inclusion',
      'budgets',
    ],
  ),
  _tool(
    'source.excerpt',
    'Read one sanitized source excerpt',
    readOnly: true,
    properties: <String, Object?>{
      'scenarioId': _stringSchema,
      'maxBytes': <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 65536,
      },
    },
    required: <String>['scenarioId'],
  ),
  _tool(
    'evidence.index',
    'Index visual Evidence',
    readOnly: true,
    properties: <String, Object?>{'scenarioId': _stringSchema},
    required: const <String>[],
  ),
  _tool(
    'capture.index',
    'Index available captures',
    readOnly: true,
    properties: <String, Object?>{'scenarioId': _stringSchema},
    required: const <String>[],
  ),
  _tool(
    'quality.validate',
    'Validate the current authored generation',
    readOnly: true,
    properties: const <String, Object?>{},
    required: const <String>[],
  ),
  _tool(
    'quality.capture.diff',
    'Compare two CAS PNG captures',
    readOnly: true,
    properties: <String, Object?>{
      'expectedDigest': _stringSchema,
      'actualDigest': _stringSchema,
      'policy': _objectSchema,
    },
    required: <String>['expectedDigest', 'actualDigest', 'policy'],
  ),
  _tool(
    'quality.bundle.verify',
    'Verify a workspace-local bundle',
    readOnly: true,
    properties: <String, Object?>{'path': _stringSchema},
    required: <String>['path'],
  ),
  _tool(
    'quality.evidence.verify',
    'Verify Evidence and its CAS artifacts',
    readOnly: true,
    properties: <String, Object?>{'evidence': _objectSchema},
    required: <String>['evidence'],
  ),
  _tool(
    'capability.issue',
    'Issue one short scoped automation capability',
    readOnly: false,
    properties: <String, Object?>{
      'requestId': _stringSchema,
      'tool': _stringSchema,
      'expectedDigest': _stringSchema,
      'input': _objectSchema,
    },
    required: <String>['requestId', 'tool', 'expectedDigest', 'input'],
  ),
  _tool(
    'capability.revoke',
    'Revoke one unused automation capability',
    readOnly: false,
    properties: <String, Object?>{
      'requestId': _stringSchema,
      'capabilityId': _stringSchema,
      'capabilityDigest': _stringSchema,
    },
    required: <String>['requestId', 'capabilityId', 'capabilityDigest'],
  ),
  _tool(
    'quality.tests.run',
    'Run bounded declared test targets',
    readOnly: false,
    properties: <String, Object?>{
      'requestId': _stringSchema,
      'capabilityId': _stringSchema,
      'capabilityDigest': _stringSchema,
      'expectedDigest': _stringSchema,
      'input': _objectSchema,
    },
    required: <String>[
      'requestId',
      'capabilityId',
      'capabilityDigest',
      'expectedDigest',
      'input',
    ],
  ),
  _tool(
    'quality.capture',
    'Ingest one workspace-local PNG capture',
    readOnly: false,
    properties: <String, Object?>{
      'requestId': _stringSchema,
      'capabilityId': _stringSchema,
      'capabilityDigest': _stringSchema,
      'expectedDigest': _stringSchema,
      'input': _objectSchema,
    },
    required: <String>[
      'requestId',
      'capabilityId',
      'capabilityDigest',
      'expectedDigest',
      'input',
    ],
  ),
  for (final entry in <(String, String, bool)>[
    ('authoring.describe', 'Describe authoring availability', true),
    ('authoring.getHead', 'Get the current authoring head', true),
    ('authoring.getDraft', 'Get an exact draft', true),
    ('authoring.getChangeSet', 'Get an exact changeset', true),
    ('authoring.getReview', 'Get an exact review packet', true),
    ('authoring.grant', 'Issue a scoped authoring grant', false),
    ('authoring.openDraft', 'Open or resume a layout draft', false),
    ('authoring.layout.edit', 'Apply one fenced layout edit', false),
    (
      'authoring.layout.batchMutate',
      'Apply a bounded chain of fenced edits',
      false,
    ),
    ('authoring.review.prepare', 'Prepare a review packet', false),
    ('authoring.finding.record', 'Record a typed finding', false),
    ('authoring.concept.propose', 'Propose a non-current concept', false),
    (
      'quality.acceptance.record',
      'Record Host-evaluated automated acceptance',
      false,
    ),
    ('authoring.layout.promote', 'Promote one approved layout', false),
  ])
    _tool(
      entry.$1,
      entry.$2,
      readOnly: entry.$3,
      properties: entry.$1 == 'authoring.layout.batchMutate'
          ? <String, Object?>{
              'requests': <String, Object?>{
                'type': 'array',
                'items': _objectSchema,
                'maxItems': 16,
              },
            }
          : <String, Object?>{'request': _objectSchema},
      required: <String>[
        entry.$1 == 'authoring.layout.batchMutate' ? 'requests' : 'request',
      ],
    ),
];
