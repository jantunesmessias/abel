import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';

import '../authoring/experience_authoring_service.dart';
import '../authoring/filesystem_experience_authoring_store.dart';
import '../authoring/projection_layout_promotion.dart';
import '../storage/filesystem_workspace_store.dart';
import '../workspace/workspace_configuration_loader.dart';
import 'host_rpc_server.dart';
import 'host_workspace_service.dart';

typedef HostExperienceAuthoringEventPublisher =
    Future<void> Function(String method, Map<String, Object?> params);
typedef HostExperienceAuthoringDiagnosticSink =
    void Function(Object error, StackTrace stackTrace);

/// Silent live-content authority. Filesystem installation and live revision
/// validation happen before the durable authoring commit, while the public
/// content-set event is owned by [HostExperienceAuthoringRuntime] afterwards.
final class HostProjectionLayoutContentAuthority
    implements ProjectionLayoutContentAuthority {
  const HostProjectionLayoutContentAuthority(this.workspace);

  final HostWorkspaceService workspace;

  @override
  Digest previewContentSetDigest(HostWorkspaceContent content) =>
      workspace.previewPrecompiledContentSetDigest(content);

  @override
  Digest publish(HostWorkspaceContent content) =>
      workspace.installPrecompiledContentSilently(content);
}

/// Resolves an opaque subject only through the Host-configured content root.
/// No RPC parameter can select a path, configuration, parser, or source file.
final class HostExperienceAuthoringWorkspaceResolver
    implements ExperienceAuthoringWorkspaceResolver {
  const HostExperienceAuthoringWorkspaceResolver({
    required this.workspace,
    required this.contentAuthority,
    required this.configuration,
    this.loader = const BoundedWorkspaceAuthoringLoader(),
    this.compiler = const ProjectionLayoutPromotionCompiler(),
  });

  final HostWorkspaceService workspace;
  final HostProjectionLayoutContentAuthority contentAuthority;
  final LoadedWorkspaceConfiguration? configuration;
  final BoundedWorkspaceAuthoringLoader loader;
  final ProjectionLayoutPromotionCompiler compiler;

  @override
  ExperienceAuthoringWorkspaceSnapshot resolve(AuthoringSubjectRef subject) {
    final configuration = this.configuration;
    if (configuration == null) return _resolveInjected(subject);

    final corpus = loader.loadFromConfiguration(configuration);
    final content = compiler.compileCurrent(corpus);
    final bundle = content.experienceBundle;
    if (bundle == null) {
      throw StateError('Experience topology is unavailable');
    }
    final layouts = bundle.layouts
        .where((layout) => layout.projectionId == subject.projectionId)
        .toList(growable: false);
    if (layouts.length != 1) {
      throw StateError('Authoring projection layout is unavailable');
    }
    final documents = corpus.documents
        .where(
          (document) =>
              document.kind == AuthoringKind.projectionLayout &&
              document.id == subject.projectionId.value,
        )
        .toList(growable: false);
    Digest? sourceDigest;
    if (documents.length == 1 && documents.single.schemaVersion == 2) {
      sourceDigest = corpus.sources[documents.single.sourceName]?.digest;
    }
    return ExperienceAuthoringWorkspaceSnapshot(
      subject: subject,
      catalog: content.catalog,
      topology: bundle.topology,
      layout: layouts.single,
      contentSetDigest: contentAuthority.previewContentSetDigest(content),
      sourceDigest: sourceDigest,
      scenarioLabManifest: content.scenarioLabManifest,
    );
  }

  ExperienceAuthoringWorkspaceSnapshot _resolveInjected(
    AuthoringSubjectRef subject,
  ) {
    final catalog = workspace.snapshot.catalog;
    final bundle = workspace.experienceBundle;
    if (bundle == null) {
      throw StateError('Experience topology is unavailable');
    }
    final layouts = bundle.layouts
        .where((layout) => layout.projectionId == subject.projectionId)
        .toList(growable: false);
    if (layouts.length != 1) {
      throw StateError('Authoring projection layout is unavailable');
    }
    return ExperienceAuthoringWorkspaceSnapshot(
      subject: subject,
      catalog: catalog,
      topology: bundle.topology,
      layout: layouts.single,
      contentSetDigest: workspace.contentSetIdentity.contentSetDigest,
      sourceDigest: null,
      scenarioLabManifest: workspace.scenarioLabManifest,
    );
  }
}

/// Closed Host adapter for the sixteen Experience Authoring v1 methods.
final class HostExperienceAuthoringRuntime {
  HostExperienceAuthoringRuntime._({
    required this.service,
    required this.workspace,
    required this.promotionExecutor,
    required this.publishEvent,
    required this.clock,
    this.diagnosticSink,
  });

  factory HostExperienceAuthoringRuntime.create({
    required String workspaceRoot,
    required FileSystemWorkspaceStore workspaceStore,
    required HostWorkspaceService workspace,
    required ResolvedKitPlan plan,
    required bool sourceBacked,
    required HostExperienceAuthoringEventPublisher publishEvent,
    required DateTime Function() clock,
    HostExperienceAuthoringDiagnosticSink? diagnosticSink,
  }) {
    final modules = plan.enabledModules
        .where((module) => module.moduleId.value == 'authoring.local')
        .toList(growable: false);
    if (modules.length != 1) {
      throw ArgumentError('authoring.local must be enabled exactly once');
    }
    final configuration = sourceBacked
        ? const WorkspaceConfigurationLoader().load(startPath: workspaceRoot)
        : null;
    final store = FilesystemExperienceAuthoringStore(
      workspaceStore: workspaceStore,
    );
    final contentAuthority = HostProjectionLayoutContentAuthority(workspace);
    final executor = configuration == null
        ? null
        : ConfiguredProjectionLayoutPromotionExecutor(
            configuration: configuration,
            coordinator: ProjectionLayoutPromotionCoordinator(store: store),
            contentAuthority: contentAuthority,
          );
    final resolver = HostExperienceAuthoringWorkspaceResolver(
      workspace: workspace,
      contentAuthority: contentAuthority,
      configuration: configuration,
    );
    final service = ExperienceAuthoringService(
      store: store,
      workspaceResolver: resolver,
      moduleSupport: ExperienceAuthoringModuleSupport(
        resolvedPlanDigest: plan.digest,
        active: true,
        healthy: true,
      ),
      settings: ExperienceAuthoringAuthoritySettings.fromJson(
        modules.single.settings,
      ),
      clock: clock,
      promotionExecutor: executor,
      diagnosticSink: diagnosticSink,
    );
    return HostExperienceAuthoringRuntime._(
      service: service,
      workspace: workspace,
      promotionExecutor: executor,
      publishEvent: publishEvent,
      clock: clock,
      diagnosticSink: diagnosticSink,
    );
  }

  static const Set<String> rpcMethods = ExperienceAuthoringRpcMethod.values;

  final ExperienceAuthoringService service;
  final HostWorkspaceService workspace;
  final ConfiguredProjectionLayoutPromotionExecutor? promotionExecutor;
  final HostExperienceAuthoringEventPublisher publishEvent;
  final DateTime Function() clock;
  final HostExperienceAuthoringDiagnosticSink? diagnosticSink;

  /// Reconciles any prepared WAL before the RPC listener becomes observable.
  List<ExperiencePromotionReceipt> start() =>
      promotionExecutor?.recoverPending() ??
      const <ExperiencePromotionReceipt>[];

  int connectionClosed(String connectionEpoch) =>
      service.revokeConnection(connectionEpoch);

  Map<String, HostRpcConnectionMethodHandler> get connectionAwareMethods =>
      Map<String, HostRpcConnectionMethodHandler>.unmodifiable(
        <String, HostRpcConnectionMethodHandler>{
          for (final method in rpcMethods)
            method: (params, context) =>
                call(method, params, connectionEpoch: context.connectionEpoch),
        },
      );

  void onConnectionClosed(HostRpcConnectionContext context) {
    connectionClosed(context.connectionEpoch);
  }

  int contentAuthorityChanged() => service.store.revokeAllActive(
    reason: 'content-authority-changed',
    at: clock().toUtc(),
  );

  int close() => service.close();

  Future<Object?> call(
    String method,
    Map<String, Object?> params, {
    required String connectionEpoch,
  }) async {
    try {
      return switch (method) {
        ExperienceAuthoringRpcMethod.describe =>
          service
              .describe(ExperienceAuthoringDescribeRequest.fromJson(params))
              .toJson(),
        ExperienceAuthoringRpcMethod.getSubjectHead =>
          service
              .getSubjectHead(
                ExperienceAuthoringSubjectHeadRequest.fromJson(params),
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.openDraft =>
          service
              .openDraft(
                LayoutDraftOpenRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.getDraft =>
          service.getDraft(LayoutDraftGetRequest.fromJson(params)).toJson(),
        ExperienceAuthoringRpcMethod.requestGrant =>
          service
              .requestGrant(
                AuthoringGrantRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.mutateDraft =>
          service
              .mutateDraft(
                LayoutDraftMutationRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.prepareReview =>
          service
              .prepareReview(
                ExperienceReviewPrepareRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.getChangeSet =>
          service
              .getChangeSet(ExperienceChangeSetGetRequest.fromJson(params))
              .toJson(),
        ExperienceAuthoringRpcMethod.getReview =>
          service
              .getReview(ExperienceReviewGetRequest.fromJson(params))
              .toJson(),
        ExperienceAuthoringRpcMethod.reviewAction =>
          service
              .reviewAction(
                ExperienceReviewActionRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.requestDecisionGrant =>
          service
              .requestDecisionGrant(
                ExperienceReviewDecisionGrantRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.abandonDraft =>
          service
              .abandonDraft(
                LayoutDraftAbandonRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.requestPromotionGrant =>
          service
              .requestPromotionGrant(
                ExperiencePromotionGrantRequest.fromJson(params),
                connectionEpoch: connectionEpoch,
              )
              .toJson(),
        ExperienceAuthoringRpcMethod.applyPromotion => await _applyPromotion(
          params,
          connectionEpoch,
        ),
        ExperienceAuthoringRpcMethod.getPromotion =>
          service
              .getPromotion(ExperiencePromotionGetRequest.fromJson(params))
              .toJson(),
        ExperienceAuthoringRpcMethod.getPromotionHistory =>
          service
              .getPromotionHistory(
                ExperiencePromotionHistoryRequest.fromJson(params),
              )
              .toJson(),
        _ => throw ArgumentError.value(method, 'method'),
      };
    } on ExperienceAuthoringServiceException catch (rejection) {
      throw HostRpcApplicationException(
        code: ExperienceAuthoringError.jsonRpcCode,
        message: 'Experience Authoring request rejected',
        data: rejection.error.toJson(),
      );
    } on Object catch (error) {
      if (error is FormatException || error is ArgumentError) {
        throw const HostRpcApplicationException(
          code: -32602,
          message: 'Invalid Experience Authoring params',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, Object?>> _applyPromotion(
    Map<String, Object?> params,
    String connectionEpoch,
  ) async {
    final request = ExperiencePromotionApplyRequest.fromJson(params);
    final outcome = service.applyPromotionWithCommitState(
      request,
      connectionEpoch: connectionEpoch,
    );
    if (outcome.durableCommitCreated) {
      try {
        final description = workspace.describeContentSet();
        if (description.identity.contentSetDigest !=
            outcome.result.receipt.resultContentSetDigest) {
          throw StateError(
            'Committed promotion differs from the live content-set identity',
          );
        }
        await publishEvent('experience.content.changed', description.toJson());
      } on Object catch (error, stackTrace) {
        diagnosticSink?.call(error, stackTrace);
      }
    }
    return outcome.result.toJson();
  }
}
