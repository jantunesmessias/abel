import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('HostExperienceAuthoringRuntime', () {
    test(
      'registers the exact v1 surface and denies effects without authority',
      () async {
        final fixture = _RuntimeFixture(
          authoringSettings: const <String, Object?>{},
        );
        addTearDown(fixture.close);

        expect(
          HostExperienceAuthoringRuntime.rpcMethods,
          ExperienceAuthoringRpcMethod.values,
        );
        expect(
          fixture.runtime.connectionAwareMethods.keys.toSet(),
          ExperienceAuthoringRpcMethod.values,
        );

        final request = ExperienceAuthoringDescribeRequest(
          requestId: AuthoringRequestId('describe-policy'),
          subject: fixture.subject,
        );
        final description = ExperienceAuthoringDescription.fromJson(
          await fixture.runtime.call(
            ExperienceAuthoringRpcMethod.describe,
            request.toJson(),
            connectionEpoch: 'connection-policy',
          ),
        );
        description.validateAgainst(request);
        expect(
          description.availability,
          ExperienceAuthoringAvailability.policyDenied,
        );
        expect(description.allowedEffects, <AuthoringActionEffect>{
          AuthoringActionEffect.query,
        });
        expect(
          description.allowedOperations.every(
            (operation) =>
                authoringEffectFor(operation) == AuthoringActionEffect.query,
          ),
          isTrue,
        );

        final intent = AuthoringGrantRequest(
          requestId: AuthoringRequestId('grant-policy'),
          capabilityDigest: description.capability!.digest,
          subject: fixture.subject,
          effect: AuthoringActionEffect.authoring,
          operation: AuthoringOperation.openDraft,
          expectedDigest: description.currentContentSetDigest,
          expectedSourceDigest: description.currentSourceDigest!,
          payloadDigest: Digest.semantic('denied-open-payload'),
        );
        final error = await fixture.typedFailure(
          ExperienceAuthoringRpcMethod.requestGrant,
          intent.toJson(),
          connectionEpoch: 'connection-policy',
        );
        expect(error.code, ExperienceAuthoringErrorCode.policyDenied);
        expect(error.requestId, intent.requestId);
        expect(error.subject, fixture.subject);
        expect(fixture.stateFile.existsSync(), isFalse);
      },
    );

    test(
      'connection revocation is fail-closed and terminal replay is exact',
      () async {
        final fixture = _RuntimeFixture(authoringSettings: _authorSettings);
        addTearDown(fixture.close);

        final describeRequest = ExperienceAuthoringDescribeRequest(
          requestId: AuthoringRequestId('describe-author'),
          subject: fixture.subject,
        );
        final description = ExperienceAuthoringDescription.fromJson(
          await fixture.runtime.call(
            ExperienceAuthoringRpcMethod.describe,
            describeRequest.toJson(),
            connectionEpoch: 'connection-a',
          ),
        );
        expect(
          description.availability,
          ExperienceAuthoringAvailability.available,
        );

        LayoutDraftOpenRequest provisional(String requestId) =>
            LayoutDraftOpenRequest(
              requestId: AuthoringRequestId(requestId),
              subject: fixture.subject,
              expectedContentSetDigest: description.currentContentSetDigest,
              expectedSourceDigest: description.currentSourceDigest!,
              grantId: AuthoringActionGrantId('transient-grant'),
              grantDigest: Digest.semantic('transient-grant'),
            );

        Future<AuthoringActionGrant> issueGrant({
          required String requestId,
          required String effectRequestId,
          required String connectionEpoch,
        }) async {
          final effect = provisional(effectRequestId);
          final intent = AuthoringGrantRequest(
            requestId: AuthoringRequestId(requestId),
            capabilityDigest: description.capability!.digest,
            subject: fixture.subject,
            effect: AuthoringActionEffect.authoring,
            operation: AuthoringOperation.openDraft,
            expectedDigest: description.currentContentSetDigest,
            expectedSourceDigest: description.currentSourceDigest!,
            payloadDigest: effect.payloadDigest,
          );
          final result = AuthoringGrantResult.fromJson(
            await fixture.runtime.call(
              ExperienceAuthoringRpcMethod.requestGrant,
              intent.toJson(),
              connectionEpoch: connectionEpoch,
            ),
          );
          result.validateAgainst(intent);
          return result.grant;
        }

        final revokedGrant = await issueGrant(
          requestId: 'grant-revoked',
          effectRequestId: 'open-revoked',
          connectionEpoch: 'connection-a',
        );
        expect(fixture.runtime.connectionClosed('connection-a'), 1);
        final revokedRequest = LayoutDraftOpenRequest(
          requestId: AuthoringRequestId('open-revoked'),
          subject: fixture.subject,
          expectedContentSetDigest: description.currentContentSetDigest,
          expectedSourceDigest: description.currentSourceDigest!,
          grantId: revokedGrant.id,
          grantDigest: revokedGrant.digest,
        );
        final revoked = await fixture.typedFailure(
          ExperienceAuthoringRpcMethod.openDraft,
          revokedRequest.toJson(),
          connectionEpoch: 'connection-b',
        );
        expect(revoked.code, ExperienceAuthoringErrorCode.grantRevoked);

        final liveGrant = await issueGrant(
          requestId: 'grant-live',
          effectRequestId: 'open-live',
          connectionEpoch: 'connection-b',
        );
        final openRequest = LayoutDraftOpenRequest(
          requestId: AuthoringRequestId('open-live'),
          subject: fixture.subject,
          expectedContentSetDigest: description.currentContentSetDigest,
          expectedSourceDigest: description.currentSourceDigest!,
          grantId: liveGrant.id,
          grantDigest: liveGrant.digest,
        );
        final firstJson = await fixture.runtime.call(
          ExperienceAuthoringRpcMethod.openDraft,
          openRequest.toJson(),
          connectionEpoch: 'connection-b',
        );
        final first = LayoutDraftOpenResult.fromJson(firstJson);
        first.validateAgainst(openRequest);
        expect(fixture.runtime.connectionClosed('connection-b'), 0);

        final replayJson = await fixture.runtime.call(
          ExperienceAuthoringRpcMethod.openDraft,
          openRequest.toJson(),
          connectionEpoch: 'connection-c',
        );
        final replay = LayoutDraftOpenResult.fromJson(replayJson);
        expect(replay.digest, first.digest);
        expect(replay.draft.digest, first.draft.digest);
        expect(fixture.stateFile.existsSync(), isTrue);
      },
    );

    test(
      'injected content is queryable but never gains source authority',
      () async {
        final fixture = _RuntimeFixture(
          authoringSettings: _authorSettings,
          sourceBacked: false,
        );
        addTearDown(fixture.close);

        final request = ExperienceAuthoringDescribeRequest(
          requestId: AuthoringRequestId('describe-injected'),
          subject: fixture.subject,
        );
        final description = ExperienceAuthoringDescription.fromJson(
          await fixture.runtime.call(
            ExperienceAuthoringRpcMethod.describe,
            request.toJson(),
            connectionEpoch: 'connection-injected',
          ),
        );
        description.validateAgainst(request);
        expect(
          description.availability,
          ExperienceAuthoringAvailability.unsupported,
        );
        expect(description.capability, isNull);
        expect(description.currentSourceDigest, isNull);
        expect(description.allowedOperations, isEmpty);
        expect(fixture.stateFile.existsSync(), isFalse);
      },
    );

    test(
      'publishes content only for a fresh durable promotion commit',
      () async {
        final fixture = _RuntimeFixture(authoringSettings: _authorSettings);
        addTearDown(fixture.close);
        const connection = 'connection-promotion';
        final service = fixture.runtime.service;
        final description = service.describe(
          ExperienceAuthoringDescribeRequest(
            requestId: AuthoringRequestId('promotion-describe'),
            subject: fixture.subject,
          ),
        );
        final capability = description.capability!;

        AuthoringActionGrant genericGrant({
          required String requestId,
          required AuthoringOperation operation,
          required Digest expectedDigest,
          required Digest expectedSourceDigest,
          required Digest payloadDigest,
        }) => service
            .requestGrant(
              AuthoringGrantRequest(
                requestId: AuthoringRequestId(requestId),
                capabilityDigest: capability.digest,
                subject: fixture.subject,
                effect: authoringEffectFor(operation),
                operation: operation,
                expectedDigest: expectedDigest,
                expectedSourceDigest: expectedSourceDigest,
                payloadDigest: payloadDigest,
              ),
              connectionEpoch: connection,
            )
            .grant;

        final openTemplate = LayoutDraftOpenRequest(
          requestId: AuthoringRequestId('promotion-open-effect'),
          subject: fixture.subject,
          expectedContentSetDigest: description.currentContentSetDigest,
          expectedSourceDigest: description.currentSourceDigest!,
          grantId: AuthoringActionGrantId('promotion-open-template'),
          grantDigest: Digest.semantic('promotion-open-template'),
        );
        final openGrant = genericGrant(
          requestId: 'promotion-open-grant',
          operation: AuthoringOperation.openDraft,
          expectedDigest: description.currentContentSetDigest,
          expectedSourceDigest: description.currentSourceDigest!,
          payloadDigest: openTemplate.payloadDigest,
        );
        final opened = service.openDraft(
          LayoutDraftOpenRequest(
            requestId: openTemplate.requestId,
            subject: fixture.subject,
            expectedContentSetDigest: openTemplate.expectedContentSetDigest,
            expectedSourceDigest: openTemplate.expectedSourceDigest,
            grantId: openGrant.id,
            grantDigest: openGrant.digest,
          ),
          connectionEpoch: connection,
        );

        final moveTemplate = LayoutDraftMutationRequest(
          requestId: AuthoringRequestId('promotion-move-effect'),
          draftId: opened.draft.id,
          expectedDraftDigest: opened.draft.digest,
          expectedDraftRevision: opened.draft.revision,
          grantId: AuthoringActionGrantId('promotion-move-template'),
          grantDigest: Digest.semantic('promotion-move-template'),
          mutation: LayoutDraftMutation.applyMove,
          move: LayoutMoveNodeInput(
            nodeInstanceId: NodeInstanceId('node'),
            toX: 125,
            toY: 245,
          ),
        );
        final moveGrant = genericGrant(
          requestId: 'promotion-move-grant',
          operation: AuthoringOperation.moveNode,
          expectedDigest: opened.draft.digest,
          expectedSourceDigest: opened.draft.baseSourceDigest,
          payloadDigest: moveTemplate.payloadDigest,
        );
        final moved = service.mutateDraft(
          LayoutDraftMutationRequest(
            requestId: moveTemplate.requestId,
            draftId: moveTemplate.draftId,
            expectedDraftDigest: moveTemplate.expectedDraftDigest,
            expectedDraftRevision: moveTemplate.expectedDraftRevision,
            grantId: moveGrant.id,
            grantDigest: moveGrant.digest,
            mutation: moveTemplate.mutation,
            move: moveTemplate.move,
          ),
          connectionEpoch: connection,
        );

        final prepareTemplate = ExperienceReviewPrepareRequest(
          requestId: AuthoringRequestId('promotion-review-effect'),
          subject: fixture.subject,
          draftId: moved.draft.id,
          expectedDraftDigest: moved.draft.digest,
          expectedDraftRevision: moved.draft.revision,
          expectedContentSetDigest: moved.draft.contentSetDigest,
          expectedSourceDigest: moved.draft.baseSourceDigest,
          reviewGuideId: ReviewGuideId('layout-review'),
          reviewGuideStepId: 'inspect-layout',
          grantId: AuthoringActionGrantId('promotion-review-template'),
          grantDigest: Digest.semantic('promotion-review-template'),
        );
        final prepareGrant = genericGrant(
          requestId: 'promotion-review-grant',
          operation: AuthoringOperation.prepareReview,
          expectedDigest: moved.draft.digest,
          expectedSourceDigest: moved.draft.baseSourceDigest,
          payloadDigest: prepareTemplate.payloadDigest,
        );
        final prepared = service.prepareReview(
          ExperienceReviewPrepareRequest(
            requestId: prepareTemplate.requestId,
            subject: fixture.subject,
            draftId: prepareTemplate.draftId,
            expectedDraftDigest: prepareTemplate.expectedDraftDigest,
            expectedDraftRevision: prepareTemplate.expectedDraftRevision,
            expectedContentSetDigest: prepareTemplate.expectedContentSetDigest,
            expectedSourceDigest: prepareTemplate.expectedSourceDigest,
            reviewGuideId: prepareTemplate.reviewGuideId,
            reviewGuideStepId: prepareTemplate.reviewGuideStepId,
            grantId: prepareGrant.id,
            grantDigest: prepareGrant.digest,
          ),
          connectionEpoch: connection,
        );

        ExperienceReviewMutationFence fence(ExperienceReviewPacket packet) =>
            ExperienceReviewMutationFence(
              subject: fixture.subject,
              changeSetId: prepared.changeSet.id,
              changeSetDigest: prepared.changeSet.digest,
              reviewPacketId: packet.id,
              reviewPacketDigest: packet.digest,
              reviewPacketRevision: packet.revision,
              expectedSourceDigest: prepared.changeSet.baseSourceDigest,
              expectedContentSetDigest:
                  prepared.changeSet.expectedContentSetDigest,
            );

        final acceptanceTemplate = ExperienceReviewActionRequest(
          requestId: AuthoringRequestId('promotion-accept-effect'),
          fence: fence(prepared.reviewPacket),
          operation: AuthoringOperation.evaluateAutomatedAcceptance,
          grantId: AuthoringActionGrantId('promotion-accept-template'),
          grantDigest: Digest.semantic('promotion-accept-template'),
        );
        final acceptanceGrant = genericGrant(
          requestId: 'promotion-accept-grant',
          operation: acceptanceTemplate.operation,
          expectedDigest: prepared.reviewPacket.digest,
          expectedSourceDigest: prepared.changeSet.baseSourceDigest,
          payloadDigest: acceptanceTemplate.payloadDigest,
        );
        final accepted = service.reviewAction(
          ExperienceReviewActionRequest(
            requestId: acceptanceTemplate.requestId,
            fence: acceptanceTemplate.fence,
            operation: acceptanceTemplate.operation,
            grantId: acceptanceGrant.id,
            grantDigest: acceptanceGrant.digest,
          ),
          connectionEpoch: connection,
        );
        expect(
          accepted.reviewPacket.automatedAcceptance?.outcome,
          AutomatedAcceptanceOutcome.passed,
        );

        final decision = AppendExperienceHumanDecisionInput(
          decision: ExperienceHumanDecision.approve,
          rationale: 'The moved frame remains safe and ready to publish.',
        );
        final decisionFence = fence(accepted.reviewPacket);
        final decisionGrant = service.requestDecisionGrant(
          ExperienceReviewDecisionGrantRequest(
            requestId: AuthoringRequestId('promotion-decision-grant'),
            capabilityDigest: capability.digest,
            fence: decisionFence,
            decision: decision,
            automatedAcceptanceDigest:
                accepted.reviewPacket.automatedAcceptance!.digest,
          ),
          connectionEpoch: connection,
        );
        final approved = service.reviewAction(
          ExperienceReviewActionRequest(
            requestId: AuthoringRequestId('promotion-decision-effect'),
            fence: decisionFence,
            operation: AuthoringOperation.decideReview,
            decision: decision,
            expectedAutomatedAcceptanceDigest:
                accepted.reviewPacket.automatedAcceptance!.digest,
            grantId: decisionGrant.grant.id,
            grantDigest: decisionGrant.grant.digest,
          ),
          connectionEpoch: connection,
        );
        expect(approved.reviewPacket.isPromotable, isTrue);

        final promotionIntent = ExperiencePromotionGrantRequest(
          requestId: AuthoringRequestId('promotion-final-grant'),
          capabilityDigest: capability.digest,
          subject: fixture.subject,
          draftId: moved.draft.id,
          draftDigest: moved.draft.digest,
          draftRevision: moved.draft.revision,
          changeSetId: prepared.changeSet.id,
          changeSetDigest: prepared.changeSet.digest,
          reviewPacketId: approved.reviewPacket.id,
          reviewPacketDigest: approved.reviewPacket.digest,
          expectedSourceDigest: prepared.changeSet.baseSourceDigest,
          expectedContentSetDigest: prepared.changeSet.expectedContentSetDigest,
          candidateLayoutDigest: moved.draft.candidateLayoutDigest,
        );
        final promotionGrant = service.requestPromotionGrant(
          promotionIntent,
          connectionEpoch: connection,
        );
        final promotionRequest = ExperiencePromotionApplyRequest(
          requestId: AuthoringRequestId('promotion-final-effect'),
          subject: promotionIntent.subject,
          draftId: promotionIntent.draftId,
          draftDigest: promotionIntent.draftDigest,
          draftRevision: promotionIntent.draftRevision,
          changeSetId: promotionIntent.changeSetId,
          changeSetDigest: promotionIntent.changeSetDigest,
          reviewPacketId: promotionIntent.reviewPacketId,
          reviewPacketDigest: promotionIntent.reviewPacketDigest,
          expectedSourceDigest: promotionIntent.expectedSourceDigest,
          expectedContentSetDigest: promotionIntent.expectedContentSetDigest,
          candidateLayoutDigest: promotionIntent.candidateLayoutDigest,
          grantId: promotionGrant.grant.id,
          grantDigest: promotionGrant.grant.digest,
        );
        final first = ExperiencePromotionApplyResult.fromJson(
          await fixture.runtime.call(
            ExperienceAuthoringRpcMethod.applyPromotion,
            promotionRequest.toJson(),
            connectionEpoch: connection,
          ),
        );
        first.validateAgainst(promotionRequest);
        expect(fixture.events, hasLength(1));
        expect(fixture.events.single.method, 'experience.content.changed');
        expect(
          ExperienceContentSetDescription.fromJson(
            fixture.events.single.params,
          ).identity.contentSetDigest,
          first.receipt.resultContentSetDigest,
        );

        final replay = ExperiencePromotionApplyResult.fromJson(
          await fixture.runtime.call(
            ExperienceAuthoringRpcMethod.applyPromotion,
            promotionRequest.toJson(),
            connectionEpoch: 'connection-promotion-replay',
          ),
        );
        expect(replay.toJson(), first.toJson());
        expect(fixture.events, hasLength(1));
      },
    );

    test(
      'Host composition advertises the exact connection-aware surface',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'workspace-host-authoring-composition-',
        );
        _writeWorkspace(root);
        final catalog = const BuiltinModuleCatalog().create(
          platform: 'linux-x64',
        );
        final plan = _plan(_authorSettings);
        final application = WorkspaceHost.fromResolvedPlan(
          studioOrigin: Uri.parse('http://127.0.0.1:7357'),
          sessionToken: 'authoring-session-token-0000000000001',
          workspaceRoot: root.path,
          launchProfiles: const <LaunchProfile>[],
          catalog: catalog,
          plan: plan,
        );
        addTearDown(() async {
          await application.close();
          if (root.existsSync()) root.deleteSync(recursive: true);
        });

        expect(
          application.rpc.connectionAwareMethods.keys.toSet(),
          ExperienceAuthoringRpcMethod.values,
        );
        expect(
          application.rpc.applicationMethods.keys.toSet().intersection(
            ExperienceAuthoringRpcMethod.values,
          ),
          isEmpty,
        );
        await application.start();
        expect(
          application.effectiveKitManifest.rpcMethods.toSet(),
          containsAll(ExperienceAuthoringRpcMethod.values),
        );
        await application.close();
      },
    );
  });
}

const Map<String, Object?> _authorSettings = <String, Object?>{
  'authorityId': 'local-authority',
  'accessPolicyId': 'local-policy',
  'principalId': 'local-author',
  'allowedOperations': <Object?>[
    'openDraft',
    'abandonDraft',
    'moveNode',
    'undo',
    'redo',
    'reset',
    'appendFinding',
    'proposeConcept',
    'appendComment',
    'prepareReview',
    'evaluateAutomatedAcceptance',
    'decideReview',
    'promote',
  ],
  'grantTtlSeconds': 120,
};

final class _RuntimeFixture {
  _RuntimeFixture({
    required Map<String, Object?> authoringSettings,
    this.sourceBacked = true,
  }) : root = Directory.systemTemp.createTempSync(
         'workspace-host-authoring-runtime-',
       ) {
    _writeWorkspace(root);
    final corpus = const BoundedWorkspaceAuthoringLoader().load(
      startPath: root.path,
    );
    final content = const ProjectionLayoutPromotionCompiler().compileCurrent(
      corpus,
    );
    final clock = _FixedClock();
    plan = _plan(authoringSettings);
    workspace =
        HostWorkspaceService(
          initialCatalog: content.catalog,
          initialExperienceBundle: content.experienceBundle,
          initialScenarioFacetManifest: content.scenarioFacetManifest,
          initialScenarioLabManifest: content.scenarioLabManifest,
          clock: clock,
        )..initialize(
          EffectiveKitManifest(
            resolvedPlanDigest: plan.digest,
            modules: const <EffectiveModuleState>[],
            commands: const <String>[],
            rpcMethods: const <String>[],
            studioContributions: const <String>[],
            generatedAt: clock.nowUtc(),
          ),
        );
    runtime = HostExperienceAuthoringRuntime.create(
      workspaceRoot: root.path,
      workspaceStore: FileSystemWorkspaceStore(workspaceRoot: root.path),
      workspace: workspace,
      plan: plan,
      sourceBacked: sourceBacked,
      publishEvent: (method, params) async {
        events.add((method: method, params: params));
      },
      clock: clock.nowUtc,
    );
    runtime.start();
  }

  final Directory root;
  final bool sourceBacked;
  final List<({String method, Map<String, Object?> params})> events = [];
  final AuthoringSubjectRef subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace'),
    applicationId: ApplicationId('app'),
    projectionId: ExperienceProjectionId('projection'),
  );
  late final ResolvedKitPlan plan;
  late final HostWorkspaceService workspace;
  late final HostExperienceAuthoringRuntime runtime;

  File get stateFile => File(
    p.join(
      root.path,
      '.dart_tool',
      'workspace',
      'full-local',
      FilesystemExperienceAuthoringStore.statePath,
    ),
  );

  Future<ExperienceAuthoringError> typedFailure(
    String method,
    Map<String, Object?> params, {
    required String connectionEpoch,
  }) async {
    try {
      await runtime.call(method, params, connectionEpoch: connectionEpoch);
      fail('$method unexpectedly succeeded');
    } on HostRpcApplicationException catch (failure) {
      expect(failure.code, ExperienceAuthoringError.jsonRpcCode);
      return ExperienceAuthoringError.fromJson(failure.data);
    }
  }

  void close() {
    runtime.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

ResolvedKitPlan _plan(Map<String, Object?> authoringSettings) {
  const builtins = BuiltinModuleCatalog();
  final catalog = builtins.create(platform: 'linux-x64');
  return const KitPlanResolver().resolve(
    catalog: catalog,
    profileId: 'gateway-lab-headless',
    overlays: <KitSelection>[
      KitSelection(
        modules: <KitModuleSelection>[
          KitModuleSelection(
            moduleId: ModuleId('artifact-store.local'),
            enabled: false,
          ),
          KitModuleSelection(
            moduleId: ModuleId('gateway.interceptor'),
            enabled: false,
          ),
          KitModuleSelection(
            moduleId: ModuleId('sessions.local'),
            enabled: false,
          ),
          KitModuleSelection(
            moduleId: ModuleId('authoring.local'),
            enabled: true,
            settings: authoringSettings,
          ),
        ],
      ),
    ],
    configurationSchemas: builtins.configurationSchemas,
  );
}

final class _FixedClock implements Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 17, 12);

  @override
  int monotonicMicroseconds() => 0;
}

void _writeWorkspace(Directory workspace) {
  final content = Directory(p.join(workspace.path, '.experience'))
    ..createSync();
  File(p.join(workspace.path, 'workspace.yaml')).writeAsStringSync('''
schemaVersion: 2
content: {root: .experience}
workspace: {id: workspace, displayName: Workspace}
applications:
  app: {root: ., target: web, displayName: App}
kit: {profile: full-local, modules: {}}
''');
  _writeJson(File(p.join(content.path, 'scenario.json')), <String, Object?>{
    'schemaVersion': 1,
    'kind': 'Scenario',
    'metadata': <String, Object?>{'id': 'scenario'},
    'spec': <String, Object?>{'applicationId': 'app', 'title': 'Scenario'},
  });
  _writeJson(File(p.join(content.path, 'binding.json')), <String, Object?>{
    'schemaVersion': 1,
    'kind': 'ScenarioExecutionBinding',
    'metadata': <String, Object?>{'id': 'scenario-binding'},
    'spec': <String, Object?>{
      'scenarioId': 'scenario',
      'targetId': 'browser',
      'launchProfileId': 'app-web',
    },
  });
  _writeJson(File(p.join(content.path, 'review.json')), <String, Object?>{
    'schemaVersion': 1,
    'kind': 'ReviewGuide',
    'metadata': <String, Object?>{'id': 'layout-review'},
    'spec': <String, Object?>{
      'applicationId': 'app',
      'title': 'Layout review',
      'steps': <Object?>[
        <String, Object?>{
          'id': 'inspect-layout',
          'instruction': 'Inspect the moved frame.',
          'observationCriteria': 'The frame remains legible.',
          'scenarioId': 'scenario',
          'bindingId': 'scenario-binding',
        },
      ],
    },
  });
  _writeJson(File(p.join(content.path, 'board.json')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'Board',
    'metadata': <String, Object?>{'id': 'board'},
    'spec': <String, Object?>{
      'applicationId': 'app',
      'title': 'Board',
      'projectionIds': <String>['projection'],
    },
  });
  _writeJson(File(p.join(content.path, 'projection.json')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'ExperienceProjection',
    'metadata': <String, Object?>{'id': 'projection'},
    'spec': <String, Object?>{
      'boardId': 'board',
      'applicationId': 'app',
      'title': 'Projection',
      'projectionKind': 'inventory',
      'nodeInstanceIds': <String>['node'],
      'edgeInstanceIds': <String>[],
    },
  });
  _writeJson(File(p.join(content.path, 'node.json')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'NodeInstance',
    'metadata': <String, Object?>{'id': 'node'},
    'spec': <String, Object?>{
      'projectionId': 'projection',
      'scenarioId': 'scenario',
    },
  });
  _writeJson(File(p.join(content.path, 'layout.yaml')), <String, Object?>{
    'schemaVersion': 2,
    'kind': 'ProjectionLayout',
    'metadata': <String, Object?>{'id': 'projection'},
    'spec': <String, Object?>{
      'projectionId': 'projection',
      'nodeFrames': <Object?>[
        <String, Object?>{
          'nodeInstanceId': 'node',
          'x': 10,
          'y': 20,
          'width': 300,
          'height': 180,
        },
      ],
      'groups': <Object?>[],
      'lanes': <Object?>[],
      'annotations': <Object?>[],
      'camera': <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
    },
  });
}

void _writeJson(File file, Map<String, Object?> value) {
  file.writeAsStringSync('${jsonEncode(value)}\n');
}
