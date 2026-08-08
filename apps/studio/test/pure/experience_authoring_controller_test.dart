@TestOn('vm')
library;

import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/authoring/experience_authoring_controller.dart';
import 'package:studio/src/host/studio_host_client.dart';
import 'package:studio/src/jaspr/experience_authoring_page.dart';
import 'package:studio_ui/studio_ui.dart';

void main() {
  test(
    'Viewer loads the published layout without probing for a grant',
    () async {
      final fixture = _AuthoringFixture();
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.policyDenied,
      );
      final controller = fixture.controller(host);

      await controller.load();

      expect(controller.snapshot.isViewer, isTrue);
      expect(controller.snapshot.draft, isNull);
      expect(controller.snapshot.baseNodes.single.x, 360);
      expect(host.grantIntents, isEmpty);
      expect(host.effectRequests, isEmpty);
      controller.close();
    },
  );

  test(
    'Author obtains a distinct request grant before each effect and materializes the move',
    () async {
      final fixture = _AuthoringFixture();
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.available,
      );
      final controller = fixture.controller(host);

      await controller.load();
      await controller.openDraft();
      await controller.moveNodeBy(fixture.nodeId, dx: 40, dy: -20);

      expect(host.events, <String>[
        'grant:openDraft',
        'effect:openDraft',
        'grant:moveNode',
        'effect:moveNode',
      ]);
      expect(host.grantIntents, hasLength(2));
      expect(host.effectRequests, hasLength(2));
      for (var index = 0; index < host.grantIntents.length; index += 1) {
        final grant = host.grantIntents[index];
        final effect = host.effectRequests[index];
        expect(effect.requestId, isNot(grant.requestId));
        expect(effect.payloadDigest, grant.payloadDigest);
      }
      final draft = controller.snapshot.draft!;
      expect(draft.revision, 1);
      expect(draft.nodes.single.x, 400);
      expect(draft.nodes.single.y, 200);
      expect(draft.nodes.single.changed, isTrue);
      controller.close();
    },
  );

  test(
    'Promotion history loads a bounded final window beyond the page size',
    () async {
      final fixture = _AuthoringFixture();
      final history = fixture.promotionHistory(17);
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.policyDenied,
        operations: const <AuthoringOperation>{
          AuthoringOperation.describe,
          AuthoringOperation.getSubjectHead,
          AuthoringOperation.getPromotionHistory,
        },
        promotionHistory: history,
      );
      final controller = fixture.controller(host);

      await controller.load();

      expect(
        controller.snapshot.phase,
        ExperienceAuthoringControllerPhase.ready,
      );
      expect(controller.snapshot.promotions, hasLength(16));
      expect(controller.snapshot.promotions.first.sequence, 2);
      expect(controller.snapshot.latestPromotion?.sequence, 17);
      expect(host.historyOffsets, <int>[0, 1]);
      expect(host.historyLimits, <int>[1, 16]);
      expect(controller.snapshot.promotionTotalCount, 17);
      expect(controller.snapshot.promotionHistoryTruncated, isTrue);
      controller.close();
    },
  );

  test(
    'Promotion history retains one final window with at most two calls',
    () async {
      final fixture = _AuthoringFixture();
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.policyDenied,
        operations: const <AuthoringOperation>{
          AuthoringOperation.describe,
          AuthoringOperation.getSubjectHead,
          AuthoringOperation.getPromotionHistory,
        },
        promotionHistoryTotalCount: 1000000,
      );
      final controller = fixture.controller(host);

      await controller.load();

      expect(
        controller.snapshot.phase,
        ExperienceAuthoringControllerPhase.ready,
      );
      expect(host.historyQueries, 2);
      expect(host.historyOffsets, <int>[0, 999984]);
      expect(host.historyLimits, <int>[1, 16]);
      expect(controller.snapshot.promotions, hasLength(16));
      expect(controller.snapshot.promotions.first.sequence, 999985);
      expect(controller.snapshot.promotions.last.sequence, 1000000);
      expect(controller.snapshot.latestPromotion?.sequence, 1000000);
      expect(controller.snapshot.promotionTotalCount, 1000000);
      expect(controller.snapshot.promotionHistoryTruncated, isTrue);
      controller.close();
    },
  );

  test('Promotion history total drift is a protocol violation', () async {
    final fixture = _AuthoringFixture();
    final host = _FakeAuthoringHost(
      fixture,
      availability: ExperienceAuthoringAvailability.policyDenied,
      operations: const <AuthoringOperation>{
        AuthoringOperation.describe,
        AuthoringOperation.getSubjectHead,
        AuthoringOperation.getPromotionHistory,
      },
      promotionHistoryTotalCount: 1000000,
      historyTotalCounts: const <int>[1000000, 999999],
    );
    final controller = fixture.controller(host);

    await controller.load();

    expect(host.historyQueries, 2);
    expect(
      controller.snapshot.phase,
      ExperienceAuthoringControllerPhase.protocolViolation,
    );
    expect(controller.snapshot.promotions, isEmpty);
    controller.close();
  });

  test(
    'Load gates every optional query by the described operation set',
    () async {
      final fixture = _AuthoringFixture();
      final draft = fixture.movedDraft();
      final changeSet = fixture.changeSet(draft);
      final review = fixture.reviewPacket(changeSet);
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.policyDenied,
        operations: const <AuthoringOperation>{
          AuthoringOperation.describe,
          AuthoringOperation.getSubjectHead,
        },
        draft: draft,
        changeSet: changeSet,
        reviewPacket: review,
        promotionHistory: fixture.promotionHistory(1),
      );
      final controller = fixture.controller(host);

      await controller.load();

      expect(
        controller.snapshot.phase,
        ExperienceAuthoringControllerPhase.ready,
      );
      expect(host.headQueries, 1);
      expect(host.draftQueries, 0);
      expect(host.changeSetQueries, 0);
      expect(host.reviewQueries, 0);
      expect(host.promotionQueries, 0);
      expect(host.historyQueries, 0);
      controller.close();

      final describeOnly = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.policyDenied,
        operations: const <AuthoringOperation>{AuthoringOperation.describe},
      );
      final describeOnlyController = fixture.controller(describeOnly);
      await describeOnlyController.load();
      expect(
        describeOnlyController.snapshot.phase,
        ExperienceAuthoringControllerPhase.ready,
      );
      expect(describeOnly.headQueries, 0);
      describeOnlyController.close();
    },
  );

  test(
    'Invalid UTF-8 text and out-of-profile coordinates never request grants',
    () async {
      final fixture = _AuthoringFixture();
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.available,
      );
      final controller = fixture.controller(host);
      await controller.load();
      await controller.openDraft();
      final grantCount = host.grantIntents.length;
      final effectCount = host.effectRequests.length;

      await controller.moveNode(fixture.nodeId, toX: 1000000.1, toY: 0);
      await controller.moveNode(fixture.nodeId, toX: -0.0, toY: 0);
      await controller.proposeConcept(
        title: List<String>.filled(129, 'é').join(),
        rationale: 'Explicit synthetic concept',
      );

      expect(
        controller.snapshot.failureCode,
        ExperienceAuthoringErrorCode.invalidRequest,
      );
      expect(host.grantIntents, hasLength(grantCount));
      expect(host.effectRequests, hasLength(effectCount));
      controller.close();
    },
  );

  test('Automated acceptance is one-shot at the controller boundary', () async {
    final fixture = _AuthoringFixture();
    final draft = fixture.movedDraft();
    final changeSet = fixture.changeSet(draft);
    final review = fixture.reviewPacket(
      changeSet,
      acceptance: AutomatedAcceptanceOutcome.failed,
    );
    final host = _FakeAuthoringHost(
      fixture,
      availability: ExperienceAuthoringAvailability.available,
      operations: const <AuthoringOperation>{
        AuthoringOperation.describe,
        AuthoringOperation.getSubjectHead,
        AuthoringOperation.getDraft,
        AuthoringOperation.getChangeSet,
        AuthoringOperation.getReview,
        AuthoringOperation.evaluateAutomatedAcceptance,
      },
      draft: draft,
      changeSet: changeSet,
      reviewPacket: review,
    );
    final controller = fixture.controller(host);
    await controller.load();

    await controller.evaluateAutomatedAcceptance();

    expect(host.grantIntents, isEmpty);
    expect(host.effectRequests, isEmpty);
    controller.close();
  });

  test(
    'Review rejects a globally cataloged artifact from another Scenario plan',
    () async {
      final fixture = _AuthoringFixture();
      final scenarioLab = fixture.crossScenarioLab();
      final draft = fixture.movedDraft();
      final changeSet = fixture.changeSet(draft);
      const compiler = ExperienceReviewPacketCompiler();
      final crossScenarioPacket = compiler.appendFinding(
        packet: fixture.reviewPacket(changeSet),
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: <Digest>{fixture.crossScenarioArtifactDigest},
        id: ExperienceFindingId('cross-scenario-artifact'),
        input: AppendExperienceFindingInput(
          subject: ExperienceReviewSubject.artifact(
            fixture.crossScenarioArtifactDigest,
          ),
          severity: ExperienceFindingSeverity.warning,
          summary: 'Artifact belongs to a different Scenario plan',
          detail:
              'The review packet must not inherit a global artifact allowlist.',
        ),
        principalId: AuthoringPrincipalId('principal-secret'),
        authorityId: AuthoringAuthorityId('authority-secret'),
        grantDigest: Digest.semantic('cross-scenario-grant'),
        recordedAt: DateTime.utc(2026, 8, 17, 12, 3),
      );
      expect(
        () => compiler.validatePacket(
          packet: crossScenarioPacket,
          changeSet: changeSet,
          catalog: fixture.catalog,
          topology: fixture.topology,
          allowedArtifactDigests: <Digest>{fixture.crossScenarioArtifactDigest},
        ),
        returnsNormally,
      );
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.policyDenied,
        operations: const <AuthoringOperation>{
          AuthoringOperation.describe,
          AuthoringOperation.getSubjectHead,
          AuthoringOperation.getDraft,
          AuthoringOperation.getChangeSet,
          AuthoringOperation.getReview,
        },
        draft: draft,
        changeSet: changeSet,
        reviewPacket: crossScenarioPacket,
      );
      final controller = fixture.controller(host, scenarioLab: scenarioLab);

      await controller.load();

      expect(
        controller.snapshot.phase,
        ExperienceAuthoringControllerPhase.protocolViolation,
      );
      expect(controller.snapshot.review, isNull);
      controller.close();
    },
  );

  test(
    'Promotion rechecks the operation epoch before requesting authority',
    () async {
      final fixture = _AuthoringFixture();
      final draft = fixture.movedDraft();
      final changeSet = fixture.changeSet(draft);
      final review = fixture.reviewPacket(
        changeSet,
        acceptance: AutomatedAcceptanceOutcome.passed,
        rejectThenApprove: true,
      );
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.available,
        operations: const <AuthoringOperation>{
          AuthoringOperation.describe,
          AuthoringOperation.getSubjectHead,
          AuthoringOperation.getDraft,
          AuthoringOperation.getChangeSet,
          AuthoringOperation.getReview,
          AuthoringOperation.promote,
        },
        draft: draft,
        changeSet: changeSet,
        reviewPacket: review,
      );
      final controller = fixture.controller(host);
      await controller.load();
      expect(controller.snapshot.review?.promotable, isTrue);
      host.blockReviewCall = 2;
      host.reviewBlocked = Completer<void>();
      host.releaseReview = Completer<void>();

      final pendingPromotion = controller.promote();
      await host.reviewBlocked!.future.timeout(const Duration(seconds: 2));
      controller.close();
      host.releaseReview!.complete();
      await pendingPromotion;

      expect(host.promotionGrantQueries, 0);
    },
  );

  testComponents(
    'Author page exposes non-drag controls without leaking transient attribution',
    (tester) async {
      final fixture = _AuthoringFixture();
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.available,
      );
      tester.pumpComponent(
        ExperienceAuthoringPage(
          enabled: true,
          rpcMethods: ExperienceAuthoringRpcMethod.values.toSet(),
          catalog: fixture.catalog,
          projectionId: fixture.projectionId.value,
          bundle: fixture.bundle,
          contentSetDigest: fixture.contentSetDigest,
          resolvedPlanDigest: fixture.planDigest,
          authoringClient: host,
        ),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-authoring-role': 'author',
        }),
        findsOneComponent,
      );
      await tester.click(find.componentWithText(StudioButton, 'Iniciar draft'));
      await tester.pump();
      expect(find.text('Esquerda'), findsOneComponent);
      expect(find.text('Direita'), findsOneComponent);
      expect(find.text('Coordenada X'), findsOneComponent);
      expect(find.text('Coordenada Y'), findsOneComponent);

      await tester.click(find.componentWithText(StudioButton, 'Direita'));
      await tester.pump();
      expect(
        _domWithAttributes(const <String, String>{
          'data-authoring-node': 'journey-dashboard-ready',
          'data-authoring-node-changed': 'true',
        }),
        findsOneComponent,
      );
      expect(_domWithAttributeValue('draggable', 'true'), findsNothing);
      for (final secret in const <String>[
        'authority-secret',
        'policy-secret',
        'principal-secret',
      ]) {
        expect(find.textContaining(secret), findsNothing);
        expect(_domContainingAttributeValue(secret), findsNothing);
      }
    },
  );

  testComponents(
    'Viewer loads latest promotion independently from a current draft head',
    (tester) async {
      final fixture = _AuthoringFixture();
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.policyDenied,
        operations: const <AuthoringOperation>{
          AuthoringOperation.describe,
          AuthoringOperation.getSubjectHead,
          AuthoringOperation.getPromotion,
        },
        draft: fixture.movedDraft(),
        promotionHistory: fixture.promotionHistory(1),
      );
      tester.pumpComponent(
        ExperienceAuthoringPage(
          enabled: true,
          rpcMethods: ExperienceAuthoringRpcMethod.values.toSet(),
          catalog: fixture.catalog,
          projectionId: fixture.projectionId.value,
          bundle: fixture.bundle,
          contentSetDigest: fixture.contentSetDigest,
          resolvedPlanDigest: fixture.planDigest,
          authoringClient: host,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(host.promotionQueries, 1);
      expect(find.text('Promoção 1'), findsOneComponent);
      expect(find.text('Nenhuma promoção publicada.'), findsNothing);
    },
  );

  testComponents(
    'Failed one-shot acceptance still enables a reasoned rejection',
    (tester) async {
      final fixture = _AuthoringFixture();
      final draft = fixture.movedDraft();
      final changeSet = fixture.changeSet(draft);
      final review = fixture.reviewPacket(
        changeSet,
        acceptance: AutomatedAcceptanceOutcome.failed,
        rejectThenApprove: true,
      );
      final host = _FakeAuthoringHost(
        fixture,
        availability: ExperienceAuthoringAvailability.available,
        operations: const <AuthoringOperation>{
          AuthoringOperation.describe,
          AuthoringOperation.getSubjectHead,
          AuthoringOperation.getDraft,
          AuthoringOperation.getChangeSet,
          AuthoringOperation.getReview,
          AuthoringOperation.evaluateAutomatedAcceptance,
          AuthoringOperation.decideReview,
        },
        draft: draft,
        changeSet: changeSet,
        reviewPacket: review,
      );
      tester.pumpComponent(
        ExperienceAuthoringPage(
          enabled: true,
          rpcMethods: ExperienceAuthoringRpcMethod.values.toSet(),
          catalog: fixture.catalog,
          projectionId: fixture.projectionId.value,
          bundle: fixture.bundle,
          contentSetDigest: fixture.contentSetDigest,
          resolvedPlanDigest: fixture.planDigest,
          authoringClient: host,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Reavaliar'), findsNothing);
      expect(
        _componentWithAuthoringAction('evaluate-acceptance'),
        findsNothing,
      );
      final rationale =
          find
                  .byComponentPredicate(
                    (component) =>
                        component is StudioTextInput &&
                        component.id == 'authoring-decision-rationale',
                    description: 'Authoring decision rationale input',
                  )
                  .evaluate()
                  .single
                  .component
              as StudioTextInput;
      rationale.onInput('Reject the failed automated result');
      await tester.pump();

      final reject =
          _componentWithAuthoringAction('reject').evaluate().single.component
              as StudioButton;
      expect(reject.disabled, isFalse);
      for (final secret in const <String>[
        'authority-secret',
        'principal-secret',
      ]) {
        expect(find.textContaining(secret), findsNothing);
        expect(_domContainingAttributeValue(secret), findsNothing);
      }
    },
  );
}

final class _AuthoringFixture {
  _AuthoringFixture() {
    catalog = CatalogManifest(
      distribution: DistributionDescriptor(
        id: 'full-local',
        displayName: 'Abel',
        coreCompatibility: '^0.1.0',
        defaultLayout: ConsumerLayout.standard,
      ),
      layout: ConsumerLayout.standard,
      workspace: Workspace(id: workspaceId, displayName: 'Delivery workspace'),
      applications: <Application>[
        Application(
          id: applicationId,
          workspaceId: workspaceId,
          displayName: 'Delivery app',
          root: '.',
          target: 'web',
        ),
      ],
      journeys: <Journey>[
        Journey(
          id: JourneyId('operate-delivery-workspace'),
          applicationId: applicationId,
          title: 'Operate delivery workspace',
          scenarioIds: <ScenarioId>[scenarioId],
        ),
      ],
      scenarios: <Scenario>[
        Scenario(
          id: scenarioId,
          applicationId: applicationId,
          title: 'Dashboard ready',
          description: 'Dashboard is ready for review',
          sourceReferences: <SourceReference>[
            SourceReference(
              repository: 'workspace',
              path: 'lib/dashboard.dart',
            ),
          ],
        ),
        Scenario(
          id: otherScenarioId,
          applicationId: applicationId,
          title: 'Other scenario',
        ),
      ],
      transitions: const <Transition>[],
      executionBindings: <ScenarioExecutionBinding>[
        ScenarioExecutionBinding(
          id: bindingId,
          scenarioId: scenarioId,
          targetId: 'browser',
          launchProfileId: 'delivery-lab-web',
        ),
        ScenarioExecutionBinding(
          id: otherBindingId,
          scenarioId: otherScenarioId,
          targetId: 'browser',
          launchProfileId: 'other-lab-web',
        ),
      ],
      reviewGuides: <ReviewGuide>[
        ReviewGuide(
          id: reviewGuideId,
          applicationId: applicationId,
          title: 'Delivery workspace review',
          steps: <ReviewGuideStep>[
            ReviewGuideStep(
              id: reviewGuideStepId,
              instruction: 'Open the ready state and inspect the layout.',
              observationCriteria:
                  'The ready state remains legible after the move.',
              scenarioId: scenarioId,
              bindingId: bindingId,
            ),
          ],
        ),
      ],
    );
    topology = ExperienceTopologyManifest(
      catalog: catalog,
      boards: <Board>[
        Board(
          id: boardId,
          applicationId: applicationId,
          title: 'Delivery board',
          projectionIds: <ExperienceProjectionId>[projectionId],
        ),
      ],
      projections: <ExperienceProjection>[
        ExperienceProjection(
          id: projectionId,
          boardId: boardId,
          applicationId: applicationId,
          title: 'Delivery journey',
          kind: ProjectionKind.journey,
          journeyId: JourneyId('operate-delivery-workspace'),
          nodeInstanceIds: <NodeInstanceId>[nodeId],
          edgeInstanceIds: const <EdgeInstanceId>[],
        ),
      ],
      nodes: <NodeInstance>[
        NodeInstance(
          id: nodeId,
          projectionId: projectionId,
          scenarioId: scenarioId,
        ),
      ],
      edges: const <EdgeInstance>[],
    );
    baseLayout = ProjectionLayoutManifest(
      topologyDigest: topology.digest,
      projectionId: projectionId,
      nodeFrames: <ProjectionNodeFrame>[
        ProjectionNodeFrame(
          nodeInstanceId: nodeId,
          x: 360,
          y: 220,
          width: 320,
          height: 180,
        ),
      ],
      groups: const <ProjectionGroup>[],
      lanes: const <ProjectionLane>[],
      annotations: const <ProjectionAnnotation>[],
      camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
    );
    bundle = ExperienceTopologyBundle(
      catalog: catalog,
      topology: topology,
      layouts: <ProjectionLayoutManifest>[baseLayout],
    );
  }

  final WorkspaceId workspaceId = WorkspaceId('delivery-workspace');
  final ApplicationId applicationId = ApplicationId('delivery-app');
  final BoardId boardId = BoardId('delivery-board');
  final ExperienceProjectionId projectionId = ExperienceProjectionId(
    'delivery-journey',
  );
  final NodeInstanceId nodeId = NodeInstanceId('journey-dashboard-ready');
  final ScenarioId scenarioId = ScenarioId('dashboard-ready');
  final ScenarioId otherScenarioId = ScenarioId('other-scenario');
  final ScenarioExecutionBindingId bindingId = ScenarioExecutionBindingId(
    'dashboard-ready-lab-web',
  );
  final ScenarioExecutionBindingId otherBindingId = ScenarioExecutionBindingId(
    'other-scenario-lab-web',
  );
  final ReviewGuideId reviewGuideId = ReviewGuideId(
    'delivery-workspace-review',
  );
  final String reviewGuideStepId = 'review-ready-lab';
  final Digest contentSetDigest = Digest.semantic('content-set');
  final Digest sourceDigest = Digest.semantic('source');
  final Digest planDigest = Digest.semantic('plan');
  final Digest crossScenarioArtifactDigest = Digest.semantic(
    'other-scenario-baseline',
  );
  late final CatalogManifest catalog;
  late final ExperienceTopologyManifest topology;
  late final ExperienceTopologyBundle bundle;
  late final ProjectionLayoutManifest baseLayout;

  AuthoringSubjectRef get subject => AuthoringSubjectRef(
    workspaceId: workspaceId,
    applicationId: applicationId,
    projectionId: projectionId,
  );

  LayoutDraft movedDraft() {
    const engine = LayoutDraftEngine();
    final opened = engine.openDraft(
      id: LayoutDraftId('delivery-draft'),
      subject: subject,
      baseLayout: baseLayout,
      baseSourceDigest: sourceDigest,
      contentSetDigest: contentSetDigest,
    );
    return engine.applyMove(
      draft: opened,
      baseLayout: baseLayout,
      input: LayoutMoveNodeInput(nodeInstanceId: nodeId, toX: 400, toY: 200),
    );
  }

  ExperienceChangeSet changeSet(LayoutDraft draft) =>
      const LayoutDraftEngine().createChangeSet(
        id: ExperienceChangeSetId('delivery-change-set'),
        draft: draft,
        baseLayout: baseLayout,
        currentContentSetDigest: contentSetDigest,
        currentSourceDigest: sourceDigest,
      );

  ExecutableReviewGuideBinding get reviewGuideBinding =>
      ExecutableReviewGuideBinding(
        catalogDigest: catalog.digest,
        applicationId: applicationId,
        reviewGuideId: reviewGuideId,
        stepId: reviewGuideStepId,
        scenarioId: scenarioId,
        bindingId: bindingId,
      );

  ExperienceReviewPacket reviewPacket(
    ExperienceChangeSet changeSet, {
    AutomatedAcceptanceOutcome? acceptance,
    bool rejectThenApprove = false,
  }) {
    const compiler = ExperienceReviewPacketCompiler();
    var packet = compiler.compile(
      id: ExperienceReviewPacketId('delivery-review-packet'),
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: const <Digest>{},
      reviewGuideBinding: reviewGuideBinding,
      findings: const <ExperienceFindingRecord>[],
      concepts: const <ExperienceConceptProposalRecord>[],
      comments: const <ExperienceReviewCommentRecord>[],
      automatedAcceptance: null,
      humanDecisions: const <ExperienceHumanDecisionRecord>[],
    );
    if (acceptance == null) return packet;
    packet = compiler.recordAcceptance(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: const <Digest>{},
      outcome: acceptance,
      recordedAt: DateTime.utc(2026, 8, 17, 12),
    );
    if (!rejectThenApprove) return packet;
    packet = compiler.appendDecision(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: const <Digest>{},
      id: ExperienceHumanDecisionId('reject-one'),
      input: AppendExperienceHumanDecisionInput(
        decision: ExperienceHumanDecision.reject,
        rationale: 'Reject before the superseding approval',
      ),
      principalId: AuthoringPrincipalId('principal-secret'),
      authorityId: AuthoringAuthorityId('authority-secret'),
      grantDigest: Digest.semantic('reject-grant'),
      recordedAt: DateTime.utc(2026, 8, 17, 12, 1),
    );
    return compiler.appendDecision(
      packet: packet,
      changeSet: changeSet,
      catalog: catalog,
      topology: topology,
      allowedArtifactDigests: const <Digest>{},
      id: ExperienceHumanDecisionId('approve-two'),
      input: AppendExperienceHumanDecisionInput(
        decision: ExperienceHumanDecision.approve,
        rationale: 'Approve the current review head',
      ),
      principalId: AuthoringPrincipalId('principal-secret'),
      authorityId: AuthoringAuthorityId('authority-secret'),
      grantDigest: Digest.semantic('approve-grant'),
      recordedAt: DateTime.utc(2026, 8, 17, 12, 2),
    );
  }

  List<ExperiencePromotionReceipt> promotionHistory(int count) =>
      promotionHistoryPage(offset: 0, length: count);

  List<ExperiencePromotionReceipt> promotionHistoryPage({
    required int offset,
    required int length,
  }) {
    final receipts = <ExperiencePromotionReceipt>[];
    Digest? previousReceiptDigest;
    if (offset > 0) {
      previousReceiptDigest = offset == 1
          ? promotionHistoryPage(offset: 0, length: 1).single.digest
          : Digest.semantic('promotion-before-$offset');
    }
    for (var index = 0; index < length; index += 1) {
      final sequence = offset + index + 1;
      receipts.add(
        ExperiencePromotionReceipt(
          id: ExperiencePromotionReceiptId('promotion-$sequence'),
          sequence: sequence,
          previousReceiptDigest:
              receipts.lastOrNull?.digest ?? previousReceiptDigest,
          subject: subject,
          draftId: LayoutDraftId('draft-$sequence'),
          draftDigest: Digest.semantic('draft-$sequence'),
          draftRevision: sequence,
          sourceDigest: Digest.semantic('source-$sequence'),
          resultSourceDigest: Digest.semantic('result-source-$sequence'),
          previousContentSetDigest: Digest.semantic('content-$sequence'),
          resultContentSetDigest: Digest.semantic('result-content-$sequence'),
          layoutDigest: Digest.semantic('layout-$sequence'),
          changeSetId: ExperienceChangeSetId('change-$sequence'),
          changeSetDigest: Digest.semantic('change-$sequence'),
          reviewPacketId: ExperienceReviewPacketId('review-$sequence'),
          reviewPacketDigest: Digest.semantic('review-$sequence'),
          promotedAt: DateTime.utc(
            2026,
            8,
            17,
          ).add(Duration(seconds: sequence)),
        ),
      );
    }
    return receipts;
  }

  ScenarioLabManifest crossScenarioLab() {
    final evidenceId = RequiredEvidenceId('other-required-visual');
    final artifactId = SupplementalArtifactId('other-baseline-artifact');
    final comparisonId = ScenarioComparisonBindingId('other-comparison');
    final collectId = ScenarioLabOperationId('collect-other-visual');
    final acceptanceId = AutomatedAcceptanceCriterionId(
      'other-evidence-accepted',
    );
    final targetScriptId = ScenarioScriptId('exercise-dashboard-ready-lab');
    final otherScriptId = ScenarioScriptId('exercise-other-scenario');
    return ScenarioLabManifest(
      catalog: catalog,
      appAdapterCapabilities: const <CapabilityDescriptor>[],
      controls: const <ScenarioControlDefinition>[],
      operations: <ScenarioLabOperationDefinition>[
        CollectEvidenceOperationDefinition(
          id: collectId,
          scenarioId: otherScenarioId,
          evidenceRequirementId: evidenceId,
        ),
      ],
      scripts: <ScenarioScriptDefinition>[
        ScenarioScriptDefinition(
          id: targetScriptId,
          scenarioId: scenarioId,
          displayName: 'Exercise dashboard ready',
          timeoutMs: 30000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
          steps: <ScenarioScriptStep>[
            ExecutionBindingScenarioScriptStep(
              id: 'bind-dashboard-ready',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
              bindingId: bindingId,
            ),
          ],
        ),
        ScenarioScriptDefinition(
          id: otherScriptId,
          scenarioId: otherScenarioId,
          displayName: 'Exercise other scenario',
          timeoutMs: 30000,
          timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
          cancellationPolicy: ScenarioScriptCancellationPolicy.afterCurrentStep,
          steps: <ScenarioScriptStep>[
            ExecutionBindingScenarioScriptStep(
              id: 'bind-other-scenario',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.cancel,
              bindingId: otherBindingId,
            ),
            OperationScenarioScriptStep(
              id: 'collect-other-scenario',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
              operationId: collectId,
            ),
          ],
        ),
      ],
      automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
        EvidenceAcceptedAcceptanceCriterion(
          id: acceptanceId,
          scenarioId: otherScenarioId,
          displayName: 'Other evidence accepted',
          evidenceRequirementId: evidenceId,
        ),
      ],
      requiredEvidence: <RequiredEvidenceDefinition>[
        RequiredEvidenceDefinition(
          id: evidenceId,
          scenarioId: otherScenarioId,
          providerId: ModuleId('capture.typed'),
          fidelity: RuntimeFidelity.simulated,
          variantId: VariantId('default'),
          freshness: EvidenceFreshness.fresh,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.internal,
          },
          evidencePolicyId: EvidencePolicyId('other-evidence-policy'),
          comparisonPolicy: VisualComparisonPolicyReference(
            VisualComparisonPolicyId('other-visual-policy'),
          ),
        ),
      ],
      comparisonBindings: <ScenarioComparisonBinding>[
        ScenarioComparisonBinding(
          id: comparisonId,
          scenarioId: otherScenarioId,
          requiredEvidenceId: evidenceId,
          baseline: ArtifactComparisonInputReference(artifactId: artifactId),
          candidate: RequiredEvidenceComparisonInputReference(
            requiredEvidenceId: evidenceId,
          ),
        ),
      ],
      visualComparisonPolicies: <VisualComparisonPolicy>[
        VisualComparisonPolicy(
          id: 'other-visual-policy',
          maxChannelDelta: 8,
          maxChangedPixelRatio: 0.01,
        ),
      ],
      semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
      humanApprovalRequirements: const <HumanApprovalRequirement>[],
      supplementalArtifacts: <SupplementalArtifactReference>[
        SupplementalArtifactReference(
          id: artifactId,
          scenarioId: otherScenarioId,
          requiredEvidenceId: evidenceId,
          role: SupplementalArtifactRole.comparisonBaseline,
          artifactDigest: crossScenarioArtifactDigest,
          provenanceDigest: Digest.semantic('other-baseline-provenance'),
          classification: ArtifactClassification.internal,
        ),
      ],
      plans: <ScenarioLabPlan>[
        ScenarioLabPlan(
          scenarioId: scenarioId,
          executionBindingIds: <ScenarioExecutionBindingId>[bindingId],
          controlIds: const <ScenarioControlId>[],
          operationIds: const <ScenarioLabOperationId>[],
          scriptIds: <ScenarioScriptId>[targetScriptId],
          automatedAcceptanceCriterionIds:
              const <AutomatedAcceptanceCriterionId>[],
          requiredEvidenceIds: const <RequiredEvidenceId>[],
          comparisonBindingIds: const <ScenarioComparisonBindingId>[],
          humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
          supplementalArtifactIds: const <SupplementalArtifactId>[],
        ),
        ScenarioLabPlan(
          scenarioId: otherScenarioId,
          executionBindingIds: <ScenarioExecutionBindingId>[otherBindingId],
          controlIds: const <ScenarioControlId>[],
          operationIds: <ScenarioLabOperationId>[collectId],
          scriptIds: <ScenarioScriptId>[otherScriptId],
          automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
            acceptanceId,
          ],
          requiredEvidenceIds: <RequiredEvidenceId>[evidenceId],
          comparisonBindingIds: <ScenarioComparisonBindingId>[comparisonId],
          humanApprovalRequirementIds: const <HumanApprovalRequirementId>[],
          supplementalArtifactIds: <SupplementalArtifactId>[artifactId],
        ),
      ],
    );
  }

  ExperienceAuthoringController controller(
    _FakeAuthoringHost host, {
    ScenarioLabManifest? scenarioLab,
  }) => ExperienceAuthoringController(
    host: host,
    catalog: catalog,
    bundle: bundle,
    contentSetDigest: contentSetDigest,
    resolvedPlanDigest: planDigest,
    projectionId: projectionId,
    scenarioLab: scenarioLab,
    requestIdFactory: (purpose, sequence) =>
        AuthoringRequestId('$purpose-$sequence'),
  );
}

final class _FakeAuthoringHost implements StudioHostExperienceAuthoringClient {
  _FakeAuthoringHost(
    this.fixture, {
    required this.availability,
    Set<AuthoringOperation>? operations,
    this.changeSet,
    this.reviewPacket,
    List<ExperiencePromotionReceipt> promotionHistory =
        const <ExperiencePromotionReceipt>[],
    this.promotionHistoryTotalCount,
    List<int> historyTotalCounts = const <int>[],
    this.draft,
  }) : _operations =
           operations ??
           (availability == ExperienceAuthoringAvailability.available
               ? const <AuthoringOperation>{
                   AuthoringOperation.describe,
                   AuthoringOperation.getSubjectHead,
                   AuthoringOperation.openDraft,
                   AuthoringOperation.moveNode,
                 }
               : const <AuthoringOperation>{
                   AuthoringOperation.describe,
                   AuthoringOperation.getSubjectHead,
                 }),
       promotionHistory = List<ExperiencePromotionReceipt>.unmodifiable(
         promotionHistory,
       ),
       historyTotalCounts = List<int>.unmodifiable(historyTotalCounts);

  final _AuthoringFixture fixture;
  final ExperienceAuthoringAvailability availability;
  final Set<AuthoringOperation> _operations;
  final ExperienceChangeSet? changeSet;
  ExperienceReviewPacket? reviewPacket;
  final List<ExperiencePromotionReceipt> promotionHistory;
  final int? promotionHistoryTotalCount;
  final List<int> historyTotalCounts;
  final List<AuthoringGrantIntent> grantIntents = <AuthoringGrantIntent>[];
  final List<_EffectRequest> effectRequests = <_EffectRequest>[];
  final List<String> events = <String>[];
  final List<int> historyOffsets = <int>[];
  final List<int> historyLimits = <int>[];
  LayoutDraft? draft;
  var headQueries = 0;
  var draftQueries = 0;
  var changeSetQueries = 0;
  var reviewQueries = 0;
  var promotionQueries = 0;
  var historyQueries = 0;
  var promotionGrantQueries = 0;
  int? blockReviewCall;
  Completer<void>? reviewBlocked;
  Completer<void>? releaseReview;

  AuthoringCapability get _capability => AuthoringCapability(
    capability: ModuleCapabilityRef(id: 'experience.authoring', version: 1),
    moduleId: ModuleId('authoring.local'),
    resolvedPlanDigest: fixture.planDigest,
    subject: fixture.subject,
    effects: AuthoringActionEffect.values.toSet(),
    operations: AuthoringOperation.values.toSet(),
  );

  @override
  Future<ExperienceAuthoringDescription> describeExperienceAuthoring(
    ExperienceAuthoringDescribeRequest request,
  ) async => ExperienceAuthoringDescription(
    requestId: request.requestId,
    subject: request.subject,
    availability: availability,
    capability: _capability,
    allowedEffects: _operations.map(authoringEffectFor).toSet(),
    allowedOperations: _operations,
    currentContentSetDigest: fixture.contentSetDigest,
    currentSourceDigest: fixture.sourceDigest,
    currentTopologyDigest: fixture.bundle.topology.digest,
    currentLayoutDigest: fixture.baseLayout.digest,
  );

  @override
  Future<ExperienceAuthoringSubjectHeadResult> getExperienceAuthoringHead(
    ExperienceAuthoringSubjectHeadRequest request,
  ) async {
    headQueries += 1;
    return ExperienceAuthoringSubjectHeadResult(
      requestId: request.requestId,
      head: _head(request.subject),
    );
  }

  ExperiencePromotionReceipt? get _latestPromotionReceipt {
    if (promotionHistory.lastOrNull case final receipt?) return receipt;
    final totalCount =
        promotionHistoryTotalCount ?? historyTotalCounts.firstOrNull ?? 0;
    if (totalCount == 0) return null;
    final offset = totalCount > experienceAuthoringMaxPromotionReceipts
        ? totalCount - experienceAuthoringMaxPromotionReceipts
        : 0;
    return fixture
        .promotionHistoryPage(offset: offset, length: totalCount - offset)
        .last;
  }

  ExperienceAuthoringSubjectHead _head(AuthoringSubjectRef subject) =>
      ExperienceAuthoringSubjectHead(
        subject: subject,
        draft: draft == null ? null : LayoutDraftHeadRef.fromDraft(draft!),
        changeSet: changeSet == null
            ? null
            : ExperienceChangeSetHeadRef.fromChangeSet(changeSet!),
        review: reviewPacket == null
            ? null
            : ExperienceReviewHeadRef.fromPacket(reviewPacket!),
        latestPromotion: _latestPromotionReceipt == null
            ? null
            : ExperiencePromotionHeadRef.fromReceipt(_latestPromotionReceipt!),
      );

  @override
  Future<LayoutDraftGetResult> getExperienceLayoutDraft(
    LayoutDraftGetRequest request,
  ) async {
    draftQueries += 1;
    return LayoutDraftGetResult(
      requestId: request.requestId,
      draft: draft!,
      head: _head(request.subject),
    );
  }

  @override
  Future<ExperienceChangeSetGetResult> getExperienceChangeSet(
    ExperienceChangeSetGetRequest request,
  ) async {
    changeSetQueries += 1;
    return ExperienceChangeSetGetResult(
      requestId: request.requestId,
      changeSet: changeSet!,
    );
  }

  @override
  Future<ExperienceReviewGetResult> getExperienceReview(
    ExperienceReviewGetRequest request,
  ) async {
    reviewQueries += 1;
    if (reviewQueries == blockReviewCall) {
      reviewBlocked?.complete();
      await releaseReview?.future;
    }
    return ExperienceReviewGetResult(
      requestId: request.requestId,
      reviewPacket: reviewPacket!,
    );
  }

  @override
  Future<ExperiencePromotionGetResult> getExperiencePromotion(
    ExperiencePromotionGetRequest request,
  ) async {
    promotionQueries += 1;
    final latest = _latestPromotionReceipt;
    return ExperiencePromotionGetResult(
      requestId: request.requestId,
      receipt:
          promotionHistory
              .where((receipt) => receipt.id == request.receiptId)
              .firstOrNull ??
          latest!,
    );
  }

  @override
  Future<ExperiencePromotionHistoryResult> getExperiencePromotionHistory(
    ExperiencePromotionHistoryRequest request,
  ) async {
    historyQueries += 1;
    historyOffsets.add(request.offset);
    historyLimits.add(request.limit);
    final totalCount = historyTotalCounts.isEmpty
        ? promotionHistoryTotalCount ?? promotionHistory.length
        : historyTotalCounts[historyQueries - 1 < historyTotalCounts.length
              ? historyQueries - 1
              : historyTotalCounts.length - 1];
    final synthetic =
        promotionHistoryTotalCount != null || historyTotalCounts.isNotEmpty;
    final expectedLength = totalCount == 0
        ? 0
        : (totalCount - request.offset < request.limit
              ? totalCount - request.offset
              : request.limit);
    final receipts = synthetic
        ? fixture.promotionHistoryPage(
            offset: request.offset,
            length: expectedLength,
          )
        : promotionHistory.sublist(
            request.offset,
            request.offset + expectedLength,
          );
    return ExperiencePromotionHistoryResult(
      requestId: request.requestId,
      subject: request.subject,
      offset: request.offset,
      limit: request.limit,
      totalCount: totalCount,
      previousPageReceiptDigest: receipts.firstOrNull?.previousReceiptDigest,
      receipts: receipts,
    );
  }

  @override
  Future<AuthoringGrantResult> requestExperiencePromotionGrant(
    ExperiencePromotionGrantRequest request,
  ) async {
    promotionGrantQueries += 1;
    throw StateError('Promotion grant was not expected in this repro');
  }

  @override
  Future<AuthoringGrantResult> requestExperienceAuthoringGrant(
    AuthoringGrantRequest request,
  ) async {
    grantIntents.add(request);
    events.add('grant:${request.operation.name}');
    final grant = AuthoringActionGrant(
      id: AuthoringActionGrantId('grant-${grantIntents.length}'),
      requestId: request.requestId,
      requestDigest: request.digest,
      payloadDigest: request.payloadDigest,
      authorityId: AuthoringAuthorityId('authority-secret'),
      policyId: AuthoringPolicyId('policy-secret'),
      principalId: AuthoringPrincipalId('principal-secret'),
      capabilityDigest: request.capabilityDigest,
      subject: request.subject,
      effect: request.effect,
      operation: request.operation,
      expectedDigest: request.expectedDigest,
      expectedSourceDigest: request.expectedSourceDigest,
      issuedAt: DateTime.utc(2026, 8, 17, 12),
      expiresAt: DateTime.utc(2026, 8, 17, 12, 2),
      singleUse: true,
    );
    return AuthoringGrantResult(requestId: request.requestId, grant: grant);
  }

  @override
  Future<LayoutDraftOpenResult> openExperienceLayoutDraft(
    LayoutDraftOpenRequest request,
  ) async {
    events.add('effect:openDraft');
    effectRequests.add(
      _EffectRequest(request.requestId, request.payloadDigest),
    );
    draft = const LayoutDraftEngine().openDraft(
      id: LayoutDraftId('delivery-draft'),
      subject: request.subject,
      baseLayout: fixture.baseLayout,
      baseSourceDigest: request.expectedSourceDigest,
      contentSetDigest: request.expectedContentSetDigest,
    );
    return LayoutDraftOpenResult(
      requestId: request.requestId,
      draft: draft!,
      resumed: false,
      head: ExperienceAuthoringSubjectHead(
        subject: request.subject,
        draft: LayoutDraftHeadRef.fromDraft(draft!),
      ),
    );
  }

  @override
  Future<LayoutDraftMutationResult> mutateExperienceLayoutDraft(
    LayoutDraftMutationRequest request, {
    required AuthoringSubjectRef subject,
  }) async {
    expect(subject, fixture.subject);
    events.add('effect:moveNode');
    effectRequests.add(
      _EffectRequest(request.requestId, request.payloadDigest),
    );
    final previous = draft!;
    draft = const LayoutDraftEngine().applyMove(
      draft: previous,
      baseLayout: fixture.baseLayout,
      input: request.move!,
    );
    return LayoutDraftMutationResult(
      requestId: request.requestId,
      draft: draft!,
      head: ExperienceAuthoringSubjectHead(
        subject: fixture.subject,
        draft: LayoutDraftHeadRef.fromDraft(draft!),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EffectRequest {
  const _EffectRequest(this.requestId, this.payloadDigest);

  final AuthoringRequestId requestId;
  final Digest payloadDigest;
}

Finder _domWithAttributes(Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM component with attributes $attributes',
    );

Finder _domWithAttributeValue(String name, String value) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent && component.attributes?[name] == value,
      description: 'DOM component with $name=$value',
    );

Finder _domContainingAttributeValue(String value) => find.byComponentPredicate(
  (component) =>
      component is DomComponent &&
      (component.attributes?.values.any((item) => item.contains(value)) ??
          false),
  description: 'DOM component containing sensitive attribute value',
);

Finder _componentWithAuthoringAction(String action) =>
    find.byComponentPredicate(
      (component) =>
          component is StudioButton &&
          component.attributes['data-authoring-action'] == action,
      description: 'Authoring action component $action',
    );
