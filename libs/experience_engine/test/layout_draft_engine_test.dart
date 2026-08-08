import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  group('LayoutDraftEngine', () {
    test('move, undo, redo and reset use monotonic ABA-safe heads', () {
      final fixture = _Fixture();
      const engine = LayoutDraftEngine();
      final opened = fixture.open(engine);

      final moved = engine.applyMove(
        draft: opened,
        baseLayout: fixture.layout,
        input: fixture.move(100, 200),
      );
      expect(moved.revision, 1);
      expect(moved.previousDraftDigest, opened.digest);
      expect(
        engine
            .materialize(draft: moved, baseLayout: fixture.layout)
            .nodeFrames
            .singleWhere((frame) => frame.nodeInstanceId == fixture.readyNodeId)
            .x,
        100,
      );

      final undone = engine.undo(draft: moved, baseLayout: fixture.layout);
      expect(undone.candidateLayoutDigest, fixture.layout.digest);
      expect(undone.digest, isNot(opened.digest));
      expect(undone.revision, 2);

      final redone = engine.redo(draft: undone, baseLayout: fixture.layout);
      expect(redone.candidateLayoutDigest, moved.candidateLayoutDigest);
      expect(redone.digest, isNot(moved.digest));
      expect(redone.revision, 3);

      final reset = engine.reset(draft: redone, baseLayout: fixture.layout);
      expect(reset.history, isEmpty);
      expect(reset.candidateLayoutDigest, fixture.layout.digest);
      expect(reset.revision, 4);
      expect(
        () => engine.reset(draft: reset, baseLayout: fixture.layout),
        throwsStateError,
      );

      final movedAfterReset = engine.applyMove(
        draft: reset,
        baseLayout: fixture.layout,
        input: fixture.move(300, 400),
      );
      expect(movedAfterReset.history.single.id, isNot(moved.history.single.id));
      expect(
        () => engine.applyMove(
          draft: movedAfterReset,
          baseLayout: fixture.layout,
          input: fixture.move(300, 400),
        ),
        throwsStateError,
      );
    });

    test('new move truncates redo while IDs remain draft-lifetime unique', () {
      final fixture = _Fixture();
      const engine = LayoutDraftEngine();
      var draft = fixture.open(engine);
      draft = engine.applyMove(
        draft: draft,
        baseLayout: fixture.layout,
        input: fixture.move(100, 200),
      );
      draft = engine.applyMove(
        draft: draft,
        baseLayout: fixture.layout,
        input: fixture.move(300, 400),
      );
      final discardedId = draft.history.last.id;
      draft = engine.undo(draft: draft, baseLayout: fixture.layout);
      draft = engine.applyMove(
        draft: draft,
        baseLayout: fixture.layout,
        input: fixture.move(500, 600),
      );

      expect(draft.history, hasLength(2));
      expect(draft.history.last.id, isNot(discardedId));
      expect(
        () => engine.redo(draft: draft, baseLayout: fixture.layout),
        throwsStateError,
      );
    });

    test(
      'validateDraft checks a disconnected redo tail, not only the cursor',
      () {
        final fixture = _Fixture();
        const engine = LayoutDraftEngine();
        final first = engine.applyMove(
          draft: fixture.open(engine),
          baseLayout: fixture.layout,
          input: fixture.move(100, 200),
        );
        final forgedTail = LayoutMoveNodeOperation(
          id: LayoutOperationId('forged-tail'),
          nodeInstanceId: fixture.readyNodeId,
          fromX: 999,
          fromY: 200,
          toX: 300,
          toY: 400,
        );
        final forged = LayoutDraft(
          id: first.id,
          subject: first.subject,
          baseLayoutDigest: first.baseLayoutDigest,
          candidateLayoutDigest: first.candidateLayoutDigest,
          baseSourceDigest: first.baseSourceDigest,
          topologyDigest: first.topologyDigest,
          contentSetDigest: first.contentSetDigest,
          history: <LayoutMoveNodeOperation>[first.history.single, forgedTail],
          cursor: 1,
          revision: first.revision + 1,
          previousDraftDigest: first.digest,
        );

        expect(
          () => engine.validateDraft(draft: forged, baseLayout: fixture.layout),
          throwsStateError,
        );
      },
    );

    test(
      'ChangeSet binds exact source, content, draft prefix and comparison',
      () {
        final fixture = _Fixture();
        const engine = LayoutDraftEngine();
        final moved = engine.applyMove(
          draft: fixture.open(engine),
          baseLayout: fixture.layout,
          input: fixture.move(100, 200),
        );
        final changeSet = fixture.changeSet(engine, moved);

        expect(
          () => engine.validateChangeSet(
            changeSet: changeSet,
            draft: moved,
            baseLayout: fixture.layout,
          ),
          returnsNormally,
        );
        expect(
          () => engine.createChangeSet(
            id: ExperienceChangeSetId('stale-source'),
            draft: moved,
            baseLayout: fixture.layout,
            currentContentSetDigest: fixture.contentSetDigest,
            currentSourceDigest: _d('external-edit'),
          ),
          throwsStateError,
        );
        expect(
          () => engine.createChangeSet(
            id: ExperienceChangeSetId('stale-content'),
            draft: moved,
            baseLayout: fixture.layout,
            currentContentSetDigest: _d('other-content'),
            currentSourceDigest: fixture.sourceDigest,
          ),
          throwsStateError,
        );

        final forged = ExperienceChangeSet(
          id: changeSet.id,
          subject: changeSet.subject,
          baseSourceDigest: changeSet.baseSourceDigest,
          expectedContentSetDigest: changeSet.expectedContentSetDigest,
          draftDigest: changeSet.draftDigest,
          draftRevision: changeSet.draftRevision + 1,
          comparison: changeSet.comparison,
          operations: changeSet.operations,
        );
        expect(
          () => engine.validateChangeSet(
            changeSet: forged,
            draft: moved,
            baseLayout: fixture.layout,
          ),
          throwsStateError,
        );

        final returnedToBase = engine.applyMove(
          draft: moved,
          baseLayout: fixture.layout,
          input: fixture.move(10, 20),
        );
        expect(
          () => fixture.changeSet(engine, returnedToBase),
          throwsStateError,
        );
      },
    );
  });

  group('review packet compiler', () {
    test('canonical transitions enforce acceptance and approval coverage', () {
      final fixture = _Fixture();
      const engine = LayoutDraftEngine();
      const compiler = ExperienceReviewPacketCompiler();
      final draft = engine.applyMove(
        draft: fixture.open(engine),
        baseLayout: fixture.layout,
        input: fixture.move(100, 200),
      );
      final changeSet = fixture.changeSet(engine, draft);
      final initial = fixture.packet(compiler, changeSet);

      expect(initial.automatedAcceptance, isNull);
      expect(
        () => compiler.appendDecision(
          packet: initial,
          changeSet: changeSet,
          catalog: fixture.catalog,
          topology: fixture.topology,
          allowedArtifactDigests: const <Digest>{},
          id: ExperienceHumanDecisionId('premature'),
          input: AppendExperienceHumanDecisionInput(
            decision: ExperienceHumanDecision.approve,
            rationale: 'Looks good',
          ),
          principalId: fixture.principalId,
          authorityId: fixture.authorityId,
          grantDigest: _d('decision-grant'),
          recordedAt: fixture.now,
        ),
        throwsStateError,
      );

      final accepted = compiler.recordAcceptance(
        packet: initial,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        outcome: AutomatedAcceptanceOutcome.passed,
        recordedAt: fixture.now,
      );
      expect(
        () => compiler.recordAcceptance(
          packet: accepted,
          changeSet: changeSet,
          catalog: fixture.catalog,
          topology: fixture.topology,
          allowedArtifactDigests: const <Digest>{},
          outcome: AutomatedAcceptanceOutcome.failed,
          recordedAt: fixture.now,
        ),
        throwsStateError,
      );
      final failedOnce = compiler.recordAcceptance(
        packet: fixture.packet(compiler, changeSet),
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        outcome: AutomatedAcceptanceOutcome.failed,
        recordedAt: fixture.now,
      );
      expect(
        () => compiler.recordAcceptance(
          packet: failedOnce,
          changeSet: changeSet,
          catalog: fixture.catalog,
          topology: fixture.topology,
          allowedArtifactDigests: const <Digest>{},
          outcome: AutomatedAcceptanceOutcome.passed,
          recordedAt: fixture.now,
        ),
        throwsStateError,
      );
      final approved = compiler.appendDecision(
        packet: accepted,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        id: ExperienceHumanDecisionId('approve-one'),
        input: AppendExperienceHumanDecisionInput(
          decision: ExperienceHumanDecision.approve,
          rationale: 'Approved after evaluation',
        ),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('approve-grant'),
        recordedAt: fixture.now,
      );
      expect(approved.isPromotable, isTrue);
      expect(approved.headDecision!.reviewPacketDigest, accepted.digest);

      final commented = compiler.appendComment(
        packet: approved,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        id: ExperienceReviewCommentId('comment-one'),
        input: AppendExperienceReviewCommentInput(
          subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
          body: 'A later observation invalidates approval coverage',
        ),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('comment-grant'),
        recordedAt: fixture.now,
      );
      expect(commented.isPromotable, isFalse);

      final reapproved = compiler.appendDecision(
        packet: commented,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        id: ExperienceHumanDecisionId('approve-two'),
        input: AppendExperienceHumanDecisionInput(
          decision: ExperienceHumanDecision.approve,
          rationale: 'Reapproved with the later observation',
        ),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('approve-two-grant'),
        recordedAt: fixture.now,
      );
      expect(reapproved.isPromotable, isTrue);

      final blocked = compiler.appendFinding(
        packet: reapproved,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        id: ExperienceFindingId('blocking-finding'),
        input: AppendExperienceFindingInput(
          subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
          severity: ExperienceFindingSeverity.blocking,
          summary: 'Blocking issue',
          detail: 'This issue must prevent promotion',
        ),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('finding-grant'),
        recordedAt: fixture.now,
      );
      expect(blocked.isPromotable, isFalse);
      expect(blocked.findings.single.authorityId, fixture.authorityId);
    });

    test(
      'guide must bind the changed scenario and concepts stay non-current',
      () {
        final fixture = _Fixture();
        const engine = LayoutDraftEngine();
        const compiler = ExperienceReviewPacketCompiler();
        final draft = engine.applyMove(
          draft: fixture.open(engine),
          baseLayout: fixture.layout,
          input: fixture.move(100, 200),
        );
        final changeSet = fixture.changeSet(engine, draft);

        expect(
          () => compiler.compile(
            id: ExperienceReviewPacketId('wrong-application-guide'),
            changeSet: changeSet,
            catalog: fixture.catalog,
            topology: fixture.topology,
            allowedArtifactDigests: const <Digest>{},
            reviewGuideBinding: fixture.guideBinding(
              applicationId: ApplicationId('another-app'),
            ),
            findings: const <ExperienceFindingRecord>[],
            concepts: const <ExperienceConceptProposalRecord>[],
            comments: const <ExperienceReviewCommentRecord>[],
            automatedAcceptance: null,
            humanDecisions: const <ExperienceHumanDecisionRecord>[],
          ),
          throwsArgumentError,
        );

        expect(
          () => compiler.compile(
            id: ExperienceReviewPacketId('wrong-guide'),
            changeSet: changeSet,
            catalog: fixture.catalog,
            topology: fixture.topology,
            allowedArtifactDigests: const <Digest>{},
            reviewGuideBinding: fixture.guideBinding(
              stepId: 'start-step',
              scenarioId: ScenarioId('start'),
              bindingId: ScenarioExecutionBindingId('start-web'),
            ),
            findings: const <ExperienceFindingRecord>[],
            concepts: const <ExperienceConceptProposalRecord>[],
            comments: const <ExperienceReviewCommentRecord>[],
            automatedAcceptance: null,
            humanDecisions: const <ExperienceHumanDecisionRecord>[],
          ),
          throwsStateError,
        );

        final packet = fixture.packet(compiler, changeSet);
        expect(
          () => compiler.appendConcept(
            packet: packet,
            changeSet: changeSet,
            catalog: fixture.catalog,
            topology: fixture.topology,
            allowedArtifactDigests: const <Digest>{},
            id: ExperienceConceptProposalId('current-concept'),
            input: ProposeExperienceConceptInput(
              scenarioId: ScenarioId('ready'),
              title: 'Existing scenario',
              rationale: 'Must not collide with current catalog',
            ),
            principalId: fixture.principalId,
            authorityId: fixture.authorityId,
            grantDigest: _d('concept-grant'),
            recordedAt: fixture.now,
          ),
          throwsStateError,
        );

        final first = compiler.appendConcept(
          packet: packet,
          changeSet: changeSet,
          catalog: fixture.catalog,
          topology: fixture.topology,
          allowedArtifactDigests: const <Digest>{},
          id: ExperienceConceptProposalId('concept-one'),
          input: ProposeExperienceConceptInput(
            scenarioId: ScenarioId('future-ready'),
            title: 'Future ready',
            rationale: 'A non-current concept proposal',
          ),
          principalId: fixture.principalId,
          authorityId: fixture.authorityId,
          grantDigest: _d('concept-one-grant'),
          recordedAt: fixture.now,
        );
        expect(
          () => compiler.appendConcept(
            packet: first,
            changeSet: changeSet,
            catalog: fixture.catalog,
            topology: fixture.topology,
            allowedArtifactDigests: const <Digest>{},
            id: ExperienceConceptProposalId('concept-two'),
            input: ProposeExperienceConceptInput(
              scenarioId: ScenarioId('future-ready'),
              title: 'Conflicting future ready',
              rationale: 'Same semantic identity is forbidden',
            ),
            principalId: fixture.principalId,
            authorityId: fixture.authorityId,
            grantDigest: _d('concept-two-grant'),
            recordedAt: fixture.now,
          ),
          throwsArgumentError,
        );
      },
    );

    test('one guide scenario must cover every changed frame', () {
      final fixture = _Fixture();
      const engine = LayoutDraftEngine();
      const compiler = ExperienceReviewPacketCompiler();
      var mixed = engine.applyMove(
        draft: fixture.open(engine),
        baseLayout: fixture.layout,
        input: fixture.move(100, 200),
      );
      mixed = engine.applyMove(
        draft: mixed,
        baseLayout: fixture.layout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('start-node'),
          toX: 50,
          toY: 60,
        ),
      );
      expect(
        () => fixture.packet(compiler, fixture.changeSet(engine, mixed)),
        throwsStateError,
      );

      var covered = engine.applyMove(
        draft: fixture.open(engine),
        baseLayout: fixture.layout,
        input: fixture.move(100, 200),
      );
      covered = engine.applyMove(
        draft: covered,
        baseLayout: fixture.layout,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('ready-node-two'),
          toX: 700,
          toY: 800,
        ),
      );
      expect(
        () => fixture.packet(compiler, fixture.changeSet(engine, covered)),
        returnsNormally,
      );
    });
  });

  group('AuthoringGrantVerifier', () {
    test('checks every authority, request, plan and use-state fence', () {
      final fixture = _Fixture();
      final capability = fixture.capability();
      final intent = AuthoringGrantRequest(
        requestId: AuthoringRequestId('grant-request'),
        capabilityDigest: capability.digest,
        subject: fixture.subject,
        effect: AuthoringActionEffect.authoring,
        operation: AuthoringOperation.moveNode,
        expectedDigest: fixture.layout.digest,
        expectedSourceDigest: fixture.sourceDigest,
        payloadDigest: _d('move-payload'),
      );
      final grant = fixture.grant(capability, intent);
      const verifier = AuthoringGrantVerifier();

      void verify({
        AuthoringActionGrant? candidate,
        Digest? plan,
        AuthoringAuthorityId? authority,
        bool revoked = false,
        bool consumed = false,
      }) => verifier.verify(
        capability: capability,
        grant: candidate ?? grant,
        intent: intent,
        authorityId: authority ?? fixture.authorityId,
        policyId: fixture.policyId,
        principalId: fixture.principalId,
        currentResolvedPlanDigest: plan ?? fixture.planDigest,
        subject: fixture.subject,
        effect: intent.effect,
        operation: intent.operation,
        expectedDigest: intent.expectedDigest,
        expectedSourceDigest: intent.expectedSourceDigest,
        payloadDigest: intent.payloadDigest,
        grantRevoked: revoked,
        grantConsumed: consumed,
        at: fixture.now.add(const Duration(seconds: 30)),
      );

      expect(verify, returnsNormally);
      expect(() => verify(plan: _d('other-plan')), throwsStateError);
      expect(
        () => verify(authority: AuthoringAuthorityId('other-authority')),
        throwsStateError,
      );
      expect(() => verify(revoked: true), throwsStateError);
      expect(() => verify(consumed: true), throwsStateError);

      final wrongRequest = fixture.grant(
        capability,
        intent,
        requestDigest: _d('wrong-request'),
      );
      expect(() => verify(candidate: wrongRequest), throwsStateError);
    });

    test('promotion grant is stale after the exact review head changes', () {
      final fixture = _Fixture();
      const engine = LayoutDraftEngine();
      const compiler = ExperienceReviewPacketCompiler();
      const verifier = AuthoringGrantVerifier();
      final draft = engine.applyMove(
        draft: fixture.open(engine),
        baseLayout: fixture.layout,
        input: fixture.move(100, 200),
      );
      final changeSet = fixture.changeSet(engine, draft);
      final initial = fixture.packet(compiler, changeSet);
      final accepted = compiler.recordAcceptance(
        packet: initial,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        outcome: AutomatedAcceptanceOutcome.passed,
        recordedAt: fixture.now,
      );
      final approved = compiler.appendDecision(
        packet: accepted,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        id: ExperienceHumanDecisionId('promotion-approval'),
        input: AppendExperienceHumanDecisionInput(
          decision: ExperienceHumanDecision.approve,
          rationale: 'Approved for exact promotion head',
        ),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('decision-grant'),
        recordedAt: fixture.now,
      );
      final capability = AuthoringCapability(
        capability: ModuleCapabilityRef(id: 'experience.authoring', version: 1),
        moduleId: ModuleId('authoring.local'),
        resolvedPlanDigest: fixture.planDigest,
        subject: fixture.subject,
        effects: const <AuthoringActionEffect>{AuthoringActionEffect.authoring},
        operations: const <AuthoringOperation>{AuthoringOperation.promote},
      );
      final intent = ExperiencePromotionGrantRequest(
        requestId: AuthoringRequestId('promotion-grant-request'),
        capabilityDigest: capability.digest,
        subject: fixture.subject,
        draftId: draft.id,
        draftDigest: draft.digest,
        draftRevision: draft.revision,
        changeSetId: changeSet.id,
        changeSetDigest: changeSet.digest,
        reviewPacketId: approved.id,
        reviewPacketDigest: approved.digest,
        expectedSourceDigest: draft.baseSourceDigest,
        expectedContentSetDigest: draft.contentSetDigest,
        candidateLayoutDigest: draft.candidateLayoutDigest,
      );
      final grant = fixture.grant(capability, intent);

      void verify(ExperienceReviewPacket packet) => verifier.verifyPromotion(
        capability: capability,
        grant: grant,
        intent: intent,
        authorityId: fixture.authorityId,
        policyId: fixture.policyId,
        principalId: fixture.principalId,
        currentResolvedPlanDigest: fixture.planDigest,
        draft: draft,
        changeSet: changeSet,
        reviewPacket: packet,
        grantRevoked: false,
        grantConsumed: false,
        at: fixture.now.add(const Duration(seconds: 30)),
      );

      expect(() => verify(approved), returnsNormally);
      final commented = compiler.appendComment(
        packet: approved,
        changeSet: changeSet,
        catalog: fixture.catalog,
        topology: fixture.topology,
        allowedArtifactDigests: const <Digest>{},
        id: ExperienceReviewCommentId('post-grant-comment'),
        input: AppendExperienceReviewCommentInput(
          subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
          body: 'This changes the review head after grant issuance',
        ),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('comment-grant'),
        recordedAt: fixture.now,
      );
      expect(() => verify(commented), throwsStateError);
    });
  });

  group('ProjectionLayoutSafetyEvaluator', () {
    test(
      'detects changed-to-unchanged overlap and permits edge/corner touch',
      () {
        final overlap = _SafetyFixture().evaluate(<_SafetyMove>[
          const _SafetyMove(0, 15, 0),
        ]);
        expect(overlap, AutomatedAcceptanceOutcome.failed);

        final edgeTouch = _SafetyFixture().evaluate(<_SafetyMove>[
          const _SafetyMove(0, 10, 0),
        ]);
        expect(edgeTouch, AutomatedAcceptanceOutcome.passed);

        final cornerTouch = _SafetyFixture().evaluate(<_SafetyMove>[
          const _SafetyMove(0, 10, 10),
        ]);
        expect(cornerTouch, AutomatedAcceptanceOutcome.passed);
      },
    );

    test('detects changed pairs, same-x starts and nesting', () {
      expect(
        _SafetyFixture().evaluate(<_SafetyMove>[
          const _SafetyMove(0, 100, 0),
          const _SafetyMove(1, 105, 0),
        ]),
        AutomatedAcceptanceOutcome.failed,
      );
      expect(
        _SafetyFixture().evaluate(<_SafetyMove>[
          const _SafetyMove(0, 100, 0),
          const _SafetyMove(1, 100, 0),
        ]),
        AutomatedAcceptanceOutcome.failed,
      );
      expect(
        _SafetyFixture(widths: const <double>[30, 10, 10]).evaluate(
          <_SafetyMove>[
            const _SafetyMove(0, 100, 0),
            const _SafetyMove(1, 105, 0),
          ],
        ),
        AutomatedAcceptanceOutcome.failed,
      );
    });

    test('handles a large projection without a quadratic scan', () {
      final fixture = _SafetyFixture(count: 5000);
      expect(
        fixture.evaluate(<_SafetyMove>[const _SafetyMove(4999, 99990, 0)]),
        AutomatedAcceptanceOutcome.passed,
      );
    });

    test('non-finite frame geometry is rejected by the domain', () {
      expect(
        () => ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('invalid'),
          x: double.nan,
          y: 0,
          width: 10,
          height: 10,
        ),
        throwsArgumentError,
      );
    });
  });
}

final class _SafetyMove {
  const _SafetyMove(this.index, this.x, this.y);

  final int index;
  final double x;
  final double y;
}

final class _SafetyFixture {
  _SafetyFixture({this.count = 3, List<double>? widths})
    : widths = widths ?? List<double>.filled(count, 10) {
    final frames = <ProjectionNodeFrame>[
      for (var index = 0; index < count; index += 1)
        ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('node-$index'),
          x: index * 20,
          y: 0,
          width: this.widths[index],
          height: 10,
        ),
    ];
    base = ProjectionLayoutManifest(
      topologyDigest: _d('safety-topology'),
      projectionId: subject.projectionId,
      nodeFrames: frames,
      groups: const <ProjectionGroup>[],
      lanes: const <ProjectionLane>[],
      annotations: const <ProjectionAnnotation>[],
      camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
    );
  }

  final int count;
  final List<double> widths;
  final AuthoringSubjectRef subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace'),
    applicationId: ApplicationId('app'),
    projectionId: ExperienceProjectionId('safety'),
  );
  late final ProjectionLayoutManifest base;

  AutomatedAcceptanceOutcome evaluate(List<_SafetyMove> moves) {
    const engine = LayoutDraftEngine();
    var draft = engine.openDraft(
      id: LayoutDraftId('safety-draft'),
      subject: subject,
      baseLayout: base,
      baseSourceDigest: _d('safety-source'),
      contentSetDigest: _d('safety-content'),
    );
    for (final move in moves) {
      draft = engine.applyMove(
        draft: draft,
        baseLayout: base,
        input: LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('node-${move.index}'),
          toX: move.x,
          toY: move.y,
        ),
      );
    }
    final changeSet = engine.createChangeSet(
      id: ExperienceChangeSetId('safety-change'),
      draft: draft,
      baseLayout: base,
      currentContentSetDigest: _d('safety-content'),
      currentSourceDigest: _d('safety-source'),
    );
    final candidate = engine.materialize(draft: draft, baseLayout: base);
    return const ProjectionLayoutSafetyEvaluator().evaluate(
      draft: draft,
      baseLayout: base,
      candidateLayout: candidate,
      changeSet: changeSet,
    );
  }
}

final class _Fixture {
  _Fixture() {
    catalog = _catalog();
    topology = _topology(catalog);
    layout = ProjectionLayoutManifest(
      topologyDigest: topology.digest,
      projectionId: subject.projectionId,
      nodeFrames: <ProjectionNodeFrame>[
        ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('start-node'),
          x: 0,
          y: 0,
          width: 200,
          height: 120,
        ),
        ProjectionNodeFrame(
          nodeInstanceId: readyNodeId,
          x: 10,
          y: 20,
          width: 300,
          height: 180,
        ),
        ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('ready-node-two'),
          x: 400,
          y: 500,
          width: 300,
          height: 180,
        ),
      ],
      groups: const <ProjectionGroup>[],
      lanes: const <ProjectionLane>[],
      annotations: const <ProjectionAnnotation>[],
      camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
    );
  }

  final DateTime now = DateTime.utc(2026, 8, 17, 12);
  final Digest sourceDigest = _d('source');
  final Digest contentSetDigest = _d('content');
  final Digest planDigest = _d('plan');
  final AuthoringPrincipalId principalId = AuthoringPrincipalId('author');
  final AuthoringAuthorityId authorityId = AuthoringAuthorityId('authority');
  final AuthoringPolicyId policyId = AuthoringPolicyId('policy');
  final NodeInstanceId readyNodeId = NodeInstanceId('ready-node');
  final AuthoringSubjectRef subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace'),
    applicationId: ApplicationId('app'),
    projectionId: ExperienceProjectionId('journey'),
  );
  late final CatalogManifest catalog;
  late final ExperienceTopologyManifest topology;
  late final ProjectionLayoutManifest layout;

  LayoutMoveNodeInput move(double x, double y) =>
      LayoutMoveNodeInput(nodeInstanceId: readyNodeId, toX: x, toY: y);

  LayoutDraft open(LayoutDraftEngine engine) => engine.openDraft(
    id: LayoutDraftId('draft'),
    subject: subject,
    baseLayout: layout,
    baseSourceDigest: sourceDigest,
    contentSetDigest: contentSetDigest,
  );

  ExperienceChangeSet changeSet(LayoutDraftEngine engine, LayoutDraft draft) =>
      engine.createChangeSet(
        id: ExperienceChangeSetId('change-set'),
        draft: draft,
        baseLayout: layout,
        currentContentSetDigest: contentSetDigest,
        currentSourceDigest: sourceDigest,
      );

  ExecutableReviewGuideBinding guideBinding({
    ApplicationId? applicationId,
    String stepId = 'ready-step',
    ScenarioId? scenarioId,
    ScenarioExecutionBindingId? bindingId,
  }) => ExecutableReviewGuideBinding(
    catalogDigest: catalog.digest,
    applicationId: applicationId ?? subject.applicationId,
    reviewGuideId: ReviewGuideId('delivery-review'),
    stepId: stepId,
    scenarioId: scenarioId ?? ScenarioId('ready'),
    bindingId: bindingId ?? ScenarioExecutionBindingId('ready-web'),
  );

  ExperienceReviewPacket packet(
    ExperienceReviewPacketCompiler compiler,
    ExperienceChangeSet changeSet,
  ) => compiler.compile(
    id: ExperienceReviewPacketId('review-packet'),
    changeSet: changeSet,
    catalog: catalog,
    topology: topology,
    allowedArtifactDigests: const <Digest>{},
    reviewGuideBinding: guideBinding(),
    findings: const <ExperienceFindingRecord>[],
    concepts: const <ExperienceConceptProposalRecord>[],
    comments: const <ExperienceReviewCommentRecord>[],
    automatedAcceptance: null,
    humanDecisions: const <ExperienceHumanDecisionRecord>[],
  );

  AuthoringCapability capability() => AuthoringCapability(
    capability: ModuleCapabilityRef(id: 'experience.authoring', version: 1),
    moduleId: ModuleId('authoring.local'),
    resolvedPlanDigest: planDigest,
    subject: subject,
    effects: const <AuthoringActionEffect>{AuthoringActionEffect.authoring},
    operations: const <AuthoringOperation>{AuthoringOperation.moveNode},
  );

  AuthoringActionGrant grant(
    AuthoringCapability capability,
    AuthoringGrantIntent intent, {
    Digest? requestDigest,
  }) => AuthoringActionGrant(
    id: AuthoringActionGrantId('grant'),
    requestId: intent.requestId,
    requestDigest: requestDigest ?? intent.digest,
    payloadDigest: intent.payloadDigest,
    authorityId: authorityId,
    policyId: policyId,
    principalId: principalId,
    capabilityDigest: capability.digest,
    subject: subject,
    effect: intent.effect,
    operation: intent.operation,
    expectedDigest: intent.expectedDigest,
    expectedSourceDigest: intent.expectedSourceDigest,
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 2)),
    singleUse: true,
  );
}

CatalogManifest _catalog() {
  final workspaceId = WorkspaceId('workspace');
  final appId = ApplicationId('app');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
    ),
    layout: ConsumerLayout.standard,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
    applications: <Application>[
      Application(
        id: appId,
        workspaceId: workspaceId,
        displayName: 'App',
        root: 'apps/app',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('delivery'),
        applicationId: appId,
        title: 'Delivery',
        scenarioIds: <ScenarioId>[ScenarioId('start'), ScenarioId('ready')],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(id: ScenarioId('start'), applicationId: appId, title: 'Start'),
      Scenario(id: ScenarioId('ready'), applicationId: appId, title: 'Ready'),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('start-ready'),
        journeyId: JourneyId('delivery'),
        from: ScenarioId('start'),
        to: ScenarioId('ready'),
      ),
    ],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('start-web'),
        scenarioId: ScenarioId('start'),
        targetId: 'browser',
        launchProfileId: 'web',
      ),
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('ready-web'),
        scenarioId: ScenarioId('ready'),
        targetId: 'browser',
        launchProfileId: 'web',
      ),
    ],
    reviewGuides: <ReviewGuide>[
      ReviewGuide(
        id: ReviewGuideId('delivery-review'),
        applicationId: appId,
        title: 'Delivery review',
        steps: <ReviewGuideStep>[
          ReviewGuideStep(
            id: 'start-step',
            instruction: 'Open the start state',
            observationCriteria: 'The start state is visible',
            scenarioId: ScenarioId('start'),
            bindingId: ScenarioExecutionBindingId('start-web'),
          ),
          ReviewGuideStep(
            id: 'ready-step',
            instruction: 'Open the ready state',
            observationCriteria: 'The ready state is visible',
            scenarioId: ScenarioId('ready'),
            bindingId: ScenarioExecutionBindingId('ready-web'),
          ),
        ],
      ),
    ],
  );
}

ExperienceTopologyManifest _topology(CatalogManifest catalog) =>
    ExperienceTopologyManifest(
      catalog: catalog,
      boards: <Board>[
        Board(
          id: BoardId('delivery-board'),
          applicationId: ApplicationId('app'),
          title: 'Delivery',
          projectionIds: <ExperienceProjectionId>[
            ExperienceProjectionId('journey'),
          ],
        ),
      ],
      projections: <ExperienceProjection>[
        ExperienceProjection(
          id: ExperienceProjectionId('journey'),
          boardId: BoardId('delivery-board'),
          applicationId: ApplicationId('app'),
          title: 'Journey',
          kind: ProjectionKind.journey,
          journeyId: JourneyId('delivery'),
          nodeInstanceIds: <NodeInstanceId>[
            NodeInstanceId('start-node'),
            NodeInstanceId('ready-node'),
            NodeInstanceId('ready-node-two'),
          ],
          edgeInstanceIds: <EdgeInstanceId>[EdgeInstanceId('start-ready-edge')],
        ),
      ],
      nodes: <NodeInstance>[
        NodeInstance(
          id: NodeInstanceId('start-node'),
          projectionId: ExperienceProjectionId('journey'),
          scenarioId: ScenarioId('start'),
        ),
        NodeInstance(
          id: NodeInstanceId('ready-node'),
          projectionId: ExperienceProjectionId('journey'),
          scenarioId: ScenarioId('ready'),
        ),
        NodeInstance(
          id: NodeInstanceId('ready-node-two'),
          projectionId: ExperienceProjectionId('journey'),
          scenarioId: ScenarioId('ready'),
        ),
      ],
      edges: <EdgeInstance>[
        EdgeInstance(
          id: EdgeInstanceId('start-ready-edge'),
          projectionId: ExperienceProjectionId('journey'),
          transitionId: TransitionId('start-ready'),
          fromNodeId: NodeInstanceId('start-node'),
          toNodeId: NodeInstanceId('ready-node'),
        ),
      ],
    );

Digest _d(String seed) => Digest.semantic(seed);
