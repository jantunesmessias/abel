import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('authoring capability and grants', () {
    test('effect mapping freezes Viewer, Author and decision boundaries', () {
      const query = <AuthoringOperation>{
        AuthoringOperation.describe,
        AuthoringOperation.getSubjectHead,
        AuthoringOperation.getDraft,
        AuthoringOperation.getChangeSet,
        AuthoringOperation.getReview,
        AuthoringOperation.getPromotion,
        AuthoringOperation.getPromotionHistory,
      };
      const authoring = <AuthoringOperation>{
        AuthoringOperation.openDraft,
        AuthoringOperation.abandonDraft,
        AuthoringOperation.moveNode,
        AuthoringOperation.undo,
        AuthoringOperation.redo,
        AuthoringOperation.reset,
        AuthoringOperation.proposeConcept,
        AuthoringOperation.prepareReview,
        AuthoringOperation.promote,
      };
      const decision = <AuthoringOperation>{
        AuthoringOperation.appendFinding,
        AuthoringOperation.appendComment,
        AuthoringOperation.evaluateAutomatedAcceptance,
        AuthoringOperation.decideReview,
      };

      for (final operation in query) {
        expect(authoringEffectFor(operation), AuthoringActionEffect.query);
      }
      for (final operation in authoring) {
        expect(authoringEffectFor(operation), AuthoringActionEffect.authoring);
      }
      for (final operation in decision) {
        expect(authoringEffectFor(operation), AuthoringActionEffect.decision);
      }
      expect(<AuthoringOperation>{
        ...query,
        ...authoring,
        ...decision,
      }, AuthoringOperation.values.toSet());
      expect(ExperienceAuthoringRpcMethod.values.length, 16);
      expect(
        ExperienceAuthoringRpcMethod.values.every(
          (method) => method.startsWith('experience.authoring.'),
        ),
        isTrue,
      );
    });

    test('capability is stable support; grant owns authority and TTL', () {
      final fixture = _Fixture();
      final capability = fixture.capability();
      final decoded = AuthoringCapability.fromJson(_wire(capability.toJson()));
      expect(decoded.toJson(), capability.toJson());
      expect(capability.capability.key, 'experience.authoring@1');
      expect(capability.toJson(), isNot(contains('principalId')));
      expect(capability.toJson(), isNot(contains('expiresAt')));

      final intent = fixture.intent();
      final grant = fixture.grant(intent);
      expect(
        AuthoringActionGrant.fromJson(_wire(grant.toJson())).toJson(),
        grant.toJson(),
      );
      expect(
        grant.expiresAt.difference(grant.issuedAt),
        const Duration(minutes: 2),
      );
      expect(
        () => AuthoringGrantRequest(
          requestId: AuthoringRequestId('query-grant'),
          capabilityDigest: capability.digest,
          subject: fixture.subject,
          effect: AuthoringActionEffect.query,
          operation: AuthoringOperation.getReview,
          expectedDigest: _d('review'),
          expectedSourceDigest: fixture.sourceDigest,
          payloadDigest: _d('payload'),
        ),
        throwsArgumentError,
      );
      for (final operation in const <AuthoringOperation>{
        AuthoringOperation.decideReview,
        AuthoringOperation.promote,
      }) {
        final operationSlug = operation == AuthoringOperation.decideReview
            ? 'decision'
            : 'promotion';
        expect(
          () => AuthoringGrantRequest(
            requestId: AuthoringRequestId('bypass-$operationSlug'),
            capabilityDigest: capability.digest,
            subject: fixture.subject,
            effect: authoringEffectFor(operation),
            operation: operation,
            expectedDigest: _d('bypass-head'),
            expectedSourceDigest: fixture.sourceDigest,
            payloadDigest: _d('bypass-payload'),
          ),
          throwsArgumentError,
        );
        final bypassWire = <String, Object?>{
          ...intent.toJson(),
          'effect': authoringEffectFor(operation).name,
          'operation': operation.name,
        };
        expect(_schema.validate(bypassWire).isValid, isFalse);
        expect(
          () => AuthoringGrantRequest.fromJson(bypassWire),
          throwsArgumentError,
        );
      }
      expect(
        () => fixture.grant(
          intent,
          expiresAt: fixture.now.add(const Duration(minutes: 6)),
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthoringCapability(
          capability: ModuleCapabilityRef(
            id: 'experience.authoring',
            version: 1,
          ),
          moduleId: ModuleId('m${'x' * 128}'),
          resolvedPlanDigest: fixture.planDigest,
          subject: fixture.subject,
          effects: const <AuthoringActionEffect>{
            AuthoringActionEffect.authoring,
          },
          operations: const <AuthoringOperation>{AuthoringOperation.moveNode},
        ),
        throwsArgumentError,
      );
      expect(
        () => AuthoringCapability(
          capability: ModuleCapabilityRef(
            id: 'experience.authoring',
            version: 1,
          ),
          moduleId: ModuleId('authoring.remote'),
          resolvedPlanDigest: fixture.planDigest,
          subject: fixture.subject,
          effects: const <AuthoringActionEffect>{
            AuthoringActionEffect.authoring,
          },
          operations: const <AuthoringOperation>{AuthoringOperation.moveNode},
        ),
        throwsArgumentError,
      );
    });

    test('description exposes Viewer queries without mutating authority', () {
      final fixture = _Fixture();
      final capability = fixture.capability();
      final request = ExperienceAuthoringDescribeRequest(
        requestId: AuthoringRequestId('describe'),
        subject: fixture.subject,
      );
      final viewer = ExperienceAuthoringDescription(
        requestId: request.requestId,
        subject: fixture.subject,
        availability: ExperienceAuthoringAvailability.policyDenied,
        capability: capability,
        allowedEffects: const <AuthoringActionEffect>{
          AuthoringActionEffect.query,
        },
        allowedOperations: const <AuthoringOperation>{
          AuthoringOperation.getSubjectHead,
          AuthoringOperation.getChangeSet,
          AuthoringOperation.getReview,
          AuthoringOperation.getPromotion,
          AuthoringOperation.getPromotionHistory,
        },
        currentContentSetDigest: fixture.contentSetDigest,
        currentSourceDigest: fixture.sourceDigest,
        currentTopologyDigest: fixture.topologyDigest,
        currentLayoutDigest: fixture.baseLayout.digest,
      );
      expect(() => viewer.validateAgainst(request), returnsNormally);
      expect(
        ExperienceAuthoringDescription.fromJson(
          _wire(viewer.toJson()),
        ).toJson(),
        viewer.toJson(),
      );
      expect(_schema.validate(viewer.toJson()).isValid, isTrue);
      expect(
        () => ExperienceAuthoringDescription(
          requestId: request.requestId,
          subject: fixture.subject,
          availability: ExperienceAuthoringAvailability.policyDenied,
          capability: capability,
          allowedEffects: const <AuthoringActionEffect>{
            AuthoringActionEffect.authoring,
          },
          allowedOperations: const <AuthoringOperation>{
            AuthoringOperation.moveNode,
          },
          currentContentSetDigest: fixture.contentSetDigest,
          currentSourceDigest: fixture.sourceDigest,
          currentTopologyDigest: fixture.topologyDigest,
          currentLayoutDigest: fixture.baseLayout.digest,
        ),
        throwsArgumentError,
      );
      final unsupported = ExperienceAuthoringDescription(
        requestId: request.requestId,
        subject: fixture.subject,
        availability: ExperienceAuthoringAvailability.unsupported,
        capability: null,
        allowedEffects: const <AuthoringActionEffect>{},
        allowedOperations: const <AuthoringOperation>{},
        currentContentSetDigest: fixture.contentSetDigest,
        currentSourceDigest: null,
        currentTopologyDigest: fixture.topologyDigest,
        currentLayoutDigest: fixture.baseLayout.digest,
      );
      expect(unsupported.currentSourceDigest, isNull);
      expect(_schema.validate(unsupported.toJson()).isValid, isTrue);
      expect(
        () => ExperienceAuthoringDescription(
          requestId: request.requestId,
          subject: fixture.subject,
          availability: ExperienceAuthoringAvailability.available,
          capability: capability,
          allowedEffects: const <AuthoringActionEffect>{
            AuthoringActionEffect.query,
          },
          allowedOperations: const <AuthoringOperation>{
            AuthoringOperation.getReview,
          },
          currentContentSetDigest: fixture.contentSetDigest,
          currentSourceDigest: fixture.sourceDigest,
          currentTopologyDigest: fixture.topologyDigest,
          currentLayoutDigest: fixture.baseLayout.digest,
        ),
        throwsArgumentError,
      );
    });
  });

  group('draft wire and CAS', () {
    test('open-or-resume allows a persisted revision-zero head', () {
      final fixture = _Fixture();
      final request = fixture.openRequest();
      final fresh = LayoutDraftOpenResult(
        requestId: request.requestId,
        draft: fixture.openDraft,
        resumed: false,
        head: fixture.head(draft: fixture.openDraft),
      );
      final resumed = LayoutDraftOpenResult(
        requestId: request.requestId,
        draft: fixture.openDraft,
        resumed: true,
        head: fixture.head(draft: fixture.openDraft),
      );
      expect(() => fresh.validateAgainst(request), returnsNormally);
      expect(() => resumed.validateAgainst(request), returnsNormally);
      expect(
        LayoutDraftOpenResult.fromJson(_wire(resumed.toJson())).resumed,
        isTrue,
      );

      expect(
        () => LayoutDraftOpenResult(
          requestId: request.requestId,
          draft: fixture.movedDraft,
          resumed: false,
          head: fixture.head(draft: fixture.movedDraft),
        ),
        throwsArgumentError,
      );
    });

    test(
      'mutation result prevents ledger rewriting and invalidates review',
      () {
        final fixture = _Fixture();
        final request = LayoutDraftMutationRequest(
          requestId: AuthoringRequestId('move-effect'),
          draftId: fixture.openDraft.id,
          expectedDraftDigest: fixture.openDraft.digest,
          expectedDraftRevision: 0,
          grantId: AuthoringActionGrantId('move-grant'),
          grantDigest: _d('move-grant'),
          mutation: LayoutDraftMutation.applyMove,
          move: LayoutMoveNodeInput(
            nodeInstanceId: NodeInstanceId('ready-node'),
            toX: 100,
            toY: 200,
          ),
        );
        final result = LayoutDraftMutationResult(
          requestId: request.requestId,
          draft: fixture.movedDraft,
          head: fixture.head(draft: fixture.movedDraft),
        );
        expect(
          () =>
              result.validateAgainst(request, previousDraft: fixture.openDraft),
          returnsNormally,
        );

        final secondRequest = LayoutDraftMutationRequest(
          requestId: AuthoringRequestId('move-two-effect'),
          draftId: fixture.movedDraft.id,
          expectedDraftDigest: fixture.movedDraft.digest,
          expectedDraftRevision: fixture.movedDraft.revision,
          grantId: AuthoringActionGrantId('move-two-grant'),
          grantDigest: _d('move-two-grant'),
          mutation: LayoutDraftMutation.applyMove,
          move: LayoutMoveNodeInput(
            nodeInstanceId: NodeInstanceId('ready-node'),
            toX: 300,
            toY: 400,
          ),
        );
        final forgedFirst = LayoutMoveNodeOperation(
          id: fixture.operation.id,
          nodeInstanceId: fixture.operation.nodeInstanceId,
          fromX: fixture.operation.fromX,
          fromY: fixture.operation.fromY,
          toX: 101,
          toY: 201,
        );
        final second = LayoutMoveNodeOperation(
          id: LayoutOperationId('op-two'),
          nodeInstanceId: NodeInstanceId('ready-node'),
          fromX: 101,
          fromY: 201,
          toX: 300,
          toY: 400,
        );
        final forgedDraft = LayoutDraft(
          id: fixture.movedDraft.id,
          subject: fixture.subject,
          baseLayoutDigest: fixture.movedDraft.baseLayoutDigest,
          candidateLayoutDigest: _d('forged-candidate'),
          baseSourceDigest: fixture.sourceDigest,
          topologyDigest: fixture.topologyDigest,
          contentSetDigest: fixture.contentSetDigest,
          history: <LayoutMoveNodeOperation>[forgedFirst, second],
          cursor: 2,
          revision: 2,
          previousDraftDigest: fixture.movedDraft.digest,
        );
        final forgedResult = LayoutDraftMutationResult(
          requestId: secondRequest.requestId,
          draft: forgedDraft,
          head: fixture.head(draft: forgedDraft),
        );
        expect(
          () => forgedResult.validateAgainst(
            secondRequest,
            previousDraft: fixture.movedDraft,
          ),
          throwsStateError,
        );
        expect(
          () => LayoutDraftMutationRequest(
            requestId: AuthoringRequestId('unsafe-revision'),
            draftId: fixture.openDraft.id,
            expectedDraftDigest: fixture.openDraft.digest,
            expectedDraftRevision: experienceAuthoringMaxSafeInteger + 1,
            grantId: AuthoringActionGrantId('unsafe-grant'),
            grantDigest: _d('unsafe-grant'),
            mutation: LayoutDraftMutation.reset,
          ),
          throwsArgumentError,
        );
      },
    );

    test('subject head is the sanitized restart discovery index', () {
      final fixture = _Fixture();
      final head = fixture.head(
        draft: fixture.movedDraft,
        changeSet: fixture.changeSet,
        packet: fixture.initialPacket,
      );
      final request = ExperienceAuthoringSubjectHeadRequest(
        requestId: AuthoringRequestId('subject-head'),
        subject: fixture.subject,
      );
      final result = ExperienceAuthoringSubjectHeadResult(
        requestId: request.requestId,
        head: head,
      );
      expect(() => result.validateAgainst(request), returnsNormally);
      expect(result.toJson().toString(), isNot(contains('authority')));
      expect(result.toJson().toString(), isNot(contains('path')));
      expect(
        () => ExperienceAuthoringSubjectHead(
          subject: fixture.subject,
          draft: null,
          changeSet: ExperienceChangeSetHeadRef.fromChangeSet(
            fixture.changeSet,
          ),
          review: null,
          latestPromotion: null,
        ),
        throwsArgumentError,
      );
    });
  });

  group('review lifecycle RPC', () {
    test('prepare is explicit and starts before automated acceptance', () {
      final fixture = _Fixture();
      final request = fixture.prepareRequest();
      final result = ExperienceReviewPrepareResult(
        requestId: request.requestId,
        changeSet: fixture.changeSet,
        reviewPacket: fixture.initialPacket,
        head: fixture.head(
          draft: fixture.movedDraft,
          changeSet: fixture.changeSet,
          packet: fixture.initialPacket,
        ),
      );
      expect(result.reviewPacket.automatedAcceptance, isNull);
      expect(
        () => result.validateAgainst(request, draft: fixture.movedDraft),
        returnsNormally,
      );
      expect(
        utf8.encode(jsonEncode(result.toJson())).length,
        lessThan(experienceAuthoringMaxFrameBytes),
      );
      expect(
        () => ExperienceReviewPrepareRequest(
          requestId: AuthoringRequestId('prepare-unchanged'),
          subject: fixture.subject,
          draftId: fixture.openDraft.id,
          expectedDraftDigest: fixture.openDraft.digest,
          expectedDraftRevision: 0,
          expectedContentSetDigest: fixture.contentSetDigest,
          expectedSourceDigest: fixture.sourceDigest,
          reviewGuideId: ReviewGuideId('delivery-review'),
          reviewGuideStepId: 'ready-step',
          grantId: AuthoringActionGrantId('prepare-unchanged-grant'),
          grantDigest: _d('prepare-unchanged-grant'),
        ),
        throwsArgumentError,
      );
    });

    test('only Host result introduces one acceptance before decision', () {
      final fixture = _Fixture();
      final fence = fixture.fence(fixture.initialPacket);
      final request = ExperienceReviewActionRequest(
        requestId: AuthoringRequestId('evaluate-effect'),
        fence: fence,
        operation: AuthoringOperation.evaluateAutomatedAcceptance,
        grantId: AuthoringActionGrantId('evaluate-grant'),
        grantDigest: _d('evaluate-grant'),
      );
      expect(request.toJson(), isNot(contains('outcome')));
      expect(request.toJson(), isNot(contains('summary')));
      final accepted = fixture.acceptedPacket;
      final result = ExperienceReviewActionResult(
        requestId: request.requestId,
        operation: request.operation,
        reviewPacket: accepted,
        head: fixture.head(
          draft: fixture.movedDraft,
          changeSet: fixture.changeSet,
          packet: accepted,
        ),
        automatedAcceptance: accepted.automatedAcceptance,
      );
      expect(
        () => result.validateAgainst(
          request,
          changeSet: fixture.changeSet,
          previousPacket: fixture.initialPacket,
        ),
        returnsNormally,
      );
      expect(
        () => result.validateAgainst(
          ExperienceReviewActionRequest(
            requestId: request.requestId,
            fence: fixture.fence(accepted),
            operation: AuthoringOperation.evaluateAutomatedAcceptance,
            grantId: request.grantId,
            grantDigest: request.grantDigest,
          ),
          changeSet: fixture.changeSet,
          previousPacket: accepted,
        ),
        throwsStateError,
      );
    });

    test(
      'decision binds the reviewed head and later append invalidates it',
      () {
        final fixture = _Fixture();
        final accepted = fixture.acceptedPacket;
        final decisionInput = AppendExperienceHumanDecisionInput(
          decision: ExperienceHumanDecision.approve,
          rationale: 'Approved after automated acceptance',
        );
        final grantIntent = ExperienceReviewDecisionGrantRequest(
          requestId: AuthoringRequestId('decision-grant-request'),
          capabilityDigest: fixture.capability().digest,
          fence: fixture.fence(accepted),
          decision: decisionInput,
          automatedAcceptanceDigest: accepted.automatedAcceptance!.digest,
        );
        expect(
          () => grantIntent.validateAgainst(
            changeSet: fixture.changeSet,
            packet: accepted,
          ),
          returnsNormally,
        );
        final effect = ExperienceReviewActionRequest(
          requestId: AuthoringRequestId('decision-effect-request'),
          fence: fixture.fence(accepted),
          operation: AuthoringOperation.decideReview,
          grantId: AuthoringActionGrantId('decision-grant'),
          grantDigest: _d('decision-grant'),
          decision: decisionInput,
          expectedAutomatedAcceptanceDigest:
              accepted.automatedAcceptance!.digest,
        );
        expect(effect.requestId, isNot(grantIntent.requestId));
        expect(effect.payloadDigest, grantIntent.payloadDigest);
        expect(
          () => effect.validateAgainstGrantIntent(grantIntent),
          returnsNormally,
        );
        final approved = fixture.approvedPacket;
        final approvedResult = ExperienceReviewActionResult(
          requestId: effect.requestId,
          operation: effect.operation,
          reviewPacket: approved,
          head: fixture.head(
            draft: fixture.movedDraft,
            changeSet: fixture.changeSet,
            packet: approved,
          ),
          decision: approved.humanDecisions.last,
        );
        expect(
          () => approvedResult.validateAgainst(
            effect,
            changeSet: fixture.changeSet,
            previousPacket: accepted,
          ),
          returnsNormally,
        );
        expect(approved.isPromotable, isTrue);

        final commentInput = AppendExperienceReviewCommentInput(
          subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
          body: 'A later observation',
        );
        final commentRequest = ExperienceReviewActionRequest(
          requestId: AuthoringRequestId('comment-effect'),
          fence: fixture.fence(approved),
          operation: AuthoringOperation.appendComment,
          grantId: AuthoringActionGrantId('comment-grant'),
          grantDigest: _d('comment-grant'),
          comment: commentInput,
        );
        final commented = fixture.commentedPacket;
        final commentResult = ExperienceReviewActionResult(
          requestId: commentRequest.requestId,
          operation: commentRequest.operation,
          reviewPacket: commented,
          head: fixture.head(
            draft: fixture.movedDraft,
            changeSet: fixture.changeSet,
            packet: commented,
          ),
          comment: commented.comments.last,
        );
        expect(
          () => commentResult.validateAgainst(
            commentRequest,
            changeSet: fixture.changeSet,
            previousPacket: approved,
          ),
          returnsNormally,
        );
        expect(commented.isPromotable, isFalse);
      },
    );

    test(
      'packet rejects decisions without acceptance and duplicate concepts',
      () {
        final fixture = _Fixture();
        expect(
          () => fixture.packet(
            automatedAcceptance: null,
            humanDecisions: <ExperienceHumanDecisionRecord>[
              fixture.decisionRecord(
                reviewedDigest: fixture.initialPacket.digest,
              ),
            ],
            revision: 1,
            previous: fixture.initialPacket.digest,
          ),
          throwsArgumentError,
        );
        expect(
          () => ExperienceReviewPacket(
            id: fixture.initialPacket.id,
            subject: fixture.subject,
            changeSetId: fixture.changeSet.id,
            changeSetDigest: fixture.changeSet.digest,
            comparisonDigest: fixture.comparison.digest,
            baseSourceDigest: fixture.sourceDigest,
            findings: const <ExperienceFindingRecord>[],
            concepts: const <ExperienceConceptProposalRecord>[],
            comments: const <ExperienceReviewCommentRecord>[],
            reviewGuideBinding: ExecutableReviewGuideBinding(
              catalogDigest: _d('catalog'),
              applicationId: ApplicationId('another-app'),
              reviewGuideId: ReviewGuideId('delivery-review'),
              stepId: 'ready-step',
              scenarioId: ScenarioId('ready'),
              bindingId: ScenarioExecutionBindingId('ready-web'),
            ),
            automatedAcceptance: null,
            humanDecisions: const <ExperienceHumanDecisionRecord>[],
            revision: 0,
            previousReviewPacketDigest: null,
          ),
          throwsArgumentError,
        );
        final concept = fixture.conceptRecord('concept-one', 'future-ready');
        expect(
          () => fixture.packet(
            concepts: <ExperienceConceptProposalRecord>[
              concept,
              fixture.conceptRecord('concept-two', 'future-ready'),
            ],
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('promotion, abandonment and durable history', () {
    test(
      'promotion intent binds current packet and effect uses another ID',
      () {
        final fixture = _Fixture();
        final intent = fixture.promotionIntent();
        expect(
          () => intent.validateAgainst(
            draft: fixture.movedDraft,
            changeSet: fixture.changeSet,
            reviewPacket: fixture.approvedPacket,
          ),
          returnsNormally,
        );
        final apply = fixture.promotionApply(intent);
        expect(apply.requestId, isNot(intent.requestId));
        expect(() => apply.validateAgainst(intent), returnsNormally);

        final receipt = fixture.promotionReceipt;
        final closedHead = fixture.head(
          promotion: ExperiencePromotionHeadRef.fromReceipt(receipt),
        );
        final result = ExperiencePromotionApplyResult(
          requestId: apply.requestId,
          receipt: receipt,
          head: closedHead,
        );
        expect(() => result.validateAgainst(apply), returnsNormally);
        expect(receipt.previousContentSetDigest, fixture.contentSetDigest);
        expect(
          receipt.resultContentSetDigest,
          isNot(receipt.previousContentSetDigest),
        );

        final getRequest = ExperiencePromotionGetRequest(
          requestId: AuthoringRequestId('get-promotion'),
          subject: fixture.subject,
          receiptId: receipt.id,
          expectedReceiptDigest: receipt.digest,
        );
        final getResult = ExperiencePromotionGetResult(
          requestId: getRequest.requestId,
          receipt: receipt,
        );
        expect(() => getResult.validateAgainst(getRequest), returnsNormally);
        expect(
          ExperiencePromotionGetResult.fromJson(
            _wire(getResult.toJson()),
          ).toJson(),
          getResult.toJson(),
        );

        final historyRequest = ExperiencePromotionHistoryRequest(
          requestId: AuthoringRequestId('promotion-history'),
          subject: fixture.subject,
          offset: 0,
          limit: 16,
        );
        final history = ExperiencePromotionHistoryResult(
          requestId: historyRequest.requestId,
          subject: fixture.subject,
          offset: 0,
          limit: 16,
          totalCount: 1,
          previousPageReceiptDigest: null,
          receipts: <ExperiencePromotionReceipt>[receipt],
        );
        expect(() => history.validateAgainst(historyRequest), returnsNormally);
        expect(() => history.validateLatestHead(closedHead), returnsNormally);
        expect(
          ExperiencePromotionHistoryResult.fromJson(
            _wire(history.toJson()),
          ).toJson(),
          history.toJson(),
        );
      },
    );

    test('abandon receipt is idempotency-bound and releases current heads', () {
      final fixture = _Fixture();
      final request = LayoutDraftAbandonRequest(
        requestId: AuthoringRequestId('abandon-effect'),
        subject: fixture.subject,
        draftId: fixture.movedDraft.id,
        expectedDraftDigest: fixture.movedDraft.digest,
        expectedDraftRevision: fixture.movedDraft.revision,
        expectedSourceDigest: fixture.sourceDigest,
        grantId: AuthoringActionGrantId('abandon-grant'),
        grantDigest: _d('abandon-grant'),
      );
      final receipt = LayoutDraftAbandonReceipt(
        id: LayoutDraftAbandonReceiptId('abandon-receipt'),
        requestId: request.requestId,
        subject: fixture.subject,
        draftId: fixture.movedDraft.id,
        finalDraftDigest: fixture.movedDraft.digest,
        finalDraftRevision: fixture.movedDraft.revision,
        sourceDigest: fixture.sourceDigest,
        abandonedAt: fixture.now,
      );
      final result = LayoutDraftAbandonResult(
        requestId: request.requestId,
        receipt: receipt,
        head: fixture.head(),
      );
      expect(() => result.validateAgainst(request), returnsNormally);
      expect(
        LayoutDraftAbandonResult.fromJson(_wire(result.toJson())).toJson(),
        result.toJson(),
      );
    });
  });

  group('closed codec and frame profile', () {
    test('rejects routing fields, variant leakage and unsafe IDs', () {
      final fixture = _Fixture();
      final open = fixture.openRequest().toJson();
      expect(
        () => LayoutDraftOpenRequest.fromJson(<String, Object?>{
          ...open,
          'path': '/tmp/layout.yaml',
        }),
        throwsFormatException,
      );
      expect(
        _schema.validate(<String, Object?>{
          ...open,
          'path': '/tmp/layout.yaml',
        }).isValid,
        isFalse,
      );
      expect(
        () => LayoutMoveNodeInput.fromJson(<String, Object?>{
          'nodeInstanceId': 'ready-node',
          'toX': 1,
          'toY': 2,
          'fromX': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => ExperienceReviewSubject.fromJson(<String, Object?>{
          'kind': 'scenario',
          'scenarioId': 'ready',
          'transitionId': 'start-ready',
        }),
        throwsFormatException,
      );
      expect(
        () => LayoutMoveNodeInput(
          nodeInstanceId: NodeInstanceId('n${'x' * 128}'),
          toX: 1,
          toY: 2,
        ),
        throwsArgumentError,
      );
    });

    test('typed errors contain no arbitrary public message', () {
      final fixture = _Fixture();
      final error = ExperienceAuthoringError(
        code: ExperienceAuthoringErrorCode.stale,
        requestId: AuthoringRequestId('stale-effect'),
        subject: fixture.subject,
        operation: AuthoringOperation.moveNode,
        mutation: LayoutDraftMutation.applyMove,
        draftId: fixture.movedDraft.id,
        expectedDigest: fixture.movedDraft.digest,
        currentDraftDigest: _d('current-draft'),
      );
      expect(error.toJson(), isNot(contains('message')));
      expect(
        () => ExperienceAuthoringError.fromJson(<String, Object?>{
          ...error.toJson(),
          'message': '/secret/path',
        }),
        throwsFormatException,
      );
    });

    test('worst-case four-byte Unicode packet remains below 64 KiB', () {
      final fixture = _Fixture();
      final emoji64 = _emoji(64);
      final emoji128 = _emoji(128);
      final emoji256 = _emoji(256);
      final emoji512 = _emoji(512);
      final findings = <ExperienceFindingRecord>[
        for (var index = 0; index < experienceAuthoringMaxFindings; index += 1)
          ExperienceFindingRecord(
            id: ExperienceFindingId('finding-$index'),
            subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
            severity: ExperienceFindingSeverity.warning,
            summary: emoji128,
            detail: emoji512,
            principalId: fixture.principalId,
            authorityId: fixture.authorityId,
            grantDigest: _d('finding-grant-$index'),
            recordedAt: fixture.now,
          ),
      ];
      final concepts = <ExperienceConceptProposalRecord>[
        for (var index = 0; index < experienceAuthoringMaxConcepts; index += 1)
          ExperienceConceptProposalRecord(
            id: ExperienceConceptProposalId('concept-$index'),
            scenarioId: ScenarioId('future-$index'),
            lifecycle: ScenarioLifecycle.concept,
            title: emoji64,
            rationale: emoji256,
            principalId: fixture.principalId,
            authorityId: fixture.authorityId,
            grantDigest: _d('concept-grant-$index'),
            recordedAt: fixture.now,
          ),
      ];
      final comments = <ExperienceReviewCommentRecord>[];
      for (var index = 0; index < experienceAuthoringMaxComments; index += 1) {
        comments.add(
          ExperienceReviewCommentRecord(
            id: ExperienceReviewCommentId('comment-$index'),
            sequence: index + 1,
            subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
            principalId: fixture.principalId,
            authorityId: fixture.authorityId,
            grantDigest: _d('comment-grant-$index'),
            body: emoji256,
            recordedAt: fixture.now,
            previousCommentDigest: index == 0
                ? null
                : comments[index - 1].digest,
          ),
        );
      }
      final decisions = <ExperienceHumanDecisionRecord>[];
      for (var index = 0; index < experienceAuthoringMaxDecisions; index += 1) {
        decisions.add(
          ExperienceHumanDecisionRecord(
            id: ExperienceHumanDecisionId('decision-$index'),
            sequence: index + 1,
            changeSetDigest: fixture.changeSet.digest,
            reviewPacketDigest: _d('reviewed-$index'),
            principalId: fixture.principalId,
            authorityId: fixture.authorityId,
            grantDigest: _d('decision-grant-$index'),
            decision: ExperienceHumanDecision.reject,
            rationale: emoji256,
            recordedAt: fixture.now,
            previousDecisionDigest: index == 0
                ? null
                : decisions[index - 1].digest,
          ),
        );
      }
      final packet = fixture.packet(
        findings: findings,
        concepts: concepts,
        comments: comments,
        automatedAcceptance: AutomatedAcceptanceRecord(
          changeSetDigest: fixture.changeSet.digest,
          evaluatorId: projectionLayoutSafetyEvaluatorId,
          outcome: AutomatedAcceptanceOutcome.passed,
          summary: projectionLayoutSafetyPassedSummary,
          recordedAt: fixture.now,
        ),
        humanDecisions: decisions,
        revision: 99,
        previous: _d('packet-98'),
      );
      final encodedBytes = utf8.encode(jsonEncode(packet.toJson())).length;
      expect(encodedBytes, lessThan(experienceAuthoringMaxReviewPacketBytes));
      expect(_schema.validate(packet.toJson()).isValid, isTrue);
      final actionResult = ExperienceReviewActionResult(
        requestId: AuthoringRequestId('max-frame-result'),
        operation: AuthoringOperation.appendFinding,
        reviewPacket: packet,
        head: fixture.head(
          draft: fixture.movedDraft,
          changeSet: fixture.changeSet,
          packet: packet,
        ),
        finding: findings.last,
      );
      final resultBytes = utf8.encode(jsonEncode(actionResult.toJson())).length;
      expect(resultBytes, lessThan(experienceAuthoringMaxDocumentBytes));
      expect(resultBytes, lessThan(experienceAuthoringMaxFrameBytes));
      expect(
        () => AppendExperienceReviewCommentInput(
          subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
          body: '${emoji256}x',
        ),
        throwsArgumentError,
      );
    });

    test(
      'JSON escaping overflow is rejected before transport and on decode',
      () {
        final fixture = _Fixture();
        expect(() => _escapingMaxPacket(fixture), throwsFormatException);

        final oversized = fixture.openRequest().toJson()
          ..['payloadDigest'] = 'x' * experienceAuthoringMaxFrameBytes;
        expect(
          () => LayoutDraftOpenRequest.fromJson(oversized),
          throwsFormatException,
        );
      },
    );

    test('root schema covers representative core and RPC documents', () {
      final fixture = _Fixture();
      final openRequest = fixture.openRequest();
      final openResult = LayoutDraftOpenResult(
        requestId: openRequest.requestId,
        draft: fixture.openDraft,
        resumed: false,
        head: fixture.head(draft: fixture.openDraft),
      );
      final headRequest = ExperienceAuthoringSubjectHeadRequest(
        requestId: AuthoringRequestId('schema-head'),
        subject: fixture.subject,
      );
      final headResult = ExperienceAuthoringSubjectHeadResult(
        requestId: headRequest.requestId,
        head: fixture.head(
          draft: fixture.movedDraft,
          changeSet: fixture.changeSet,
          packet: fixture.initialPacket,
        ),
      );
      final history = ExperiencePromotionHistoryResult(
        requestId: AuthoringRequestId('schema-history'),
        subject: fixture.subject,
        offset: 0,
        limit: 16,
        totalCount: 1,
        previousPageReceiptDigest: null,
        receipts: <ExperiencePromotionReceipt>[fixture.promotionReceipt],
      );
      final documents = <Map<String, Object?>>[
        fixture.capability().toJson(),
        fixture.grant(fixture.intent()).toJson(),
        fixture.openDraft.toJson(),
        fixture.comparison.toJson(),
        fixture.changeSet.toJson(),
        fixture.initialPacket.toJson(),
        fixture.promotionReceipt.toJson(),
        openRequest.toJson(),
        openResult.toJson(),
        headRequest.toJson(),
        headResult.toJson(),
        fixture.prepareRequest().toJson(),
        fixture.promotionIntent().toJson(),
        fixture.promotionApply(fixture.promotionIntent()).toJson(),
        history.toJson(),
      ];
      for (final document in documents) {
        expect(
          _schema.validate(document).isValid,
          isTrue,
          reason: document['kind'] as String?,
        );
      }
    });

    test('schema variants stay in parity with every public document codec', () {
      final sourceDirectory = Directory(
        p.join(
          _repositoryRoot(),
          'libs/experience_contracts/lib/src/authoring',
        ),
      );
      final codecKinds = <String>{};
      final pattern = RegExp(
        r"_authoringDocument\(\s*value,\s*'([^']+)'",
        multiLine: true,
      );
      for (final file in sourceDirectory.listSync().whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        codecKinds.addAll(
          pattern
              .allMatches(file.readAsStringSync())
              .map((match) => match.group(1)!),
        );
      }
      final schemaKinds = (_schemaJson['oneOf']! as List<Object?>)
          .map((raw) => raw! as Map<String, Object?>)
          .map(
            (variant) =>
                ((variant['properties']! as Map<String, Object?>)['kind']!
                        as Map<String, Object?>)['const']!
                    as String,
          )
          .toSet();
      expect(schemaKinds, codecKinds);
      expect(schemaKinds.length, 39);
    });

    test(
      'every foreign top-level family field is rejected by schema and codec',
      () {
        final fixture = _Fixture();
        final openRequest = fixture.openRequest();
        final mutationRequest = LayoutDraftMutationRequest(
          requestId: AuthoringRequestId('schema-move'),
          draftId: fixture.openDraft.id,
          expectedDraftDigest: fixture.openDraft.digest,
          expectedDraftRevision: fixture.openDraft.revision,
          grantId: AuthoringActionGrantId('schema-move-grant'),
          grantDigest: _d('schema-move-grant'),
          mutation: LayoutDraftMutation.applyMove,
          move: fixture.operationToInput,
        );
        final prepareRequest = fixture.prepareRequest();
        final actionRequest = ExperienceReviewActionRequest(
          requestId: AuthoringRequestId('schema-evaluate'),
          fence: fixture.fence(fixture.initialPacket),
          operation: AuthoringOperation.evaluateAutomatedAcceptance,
          grantId: AuthoringActionGrantId('schema-evaluate-grant'),
          grantDigest: _d('schema-evaluate-grant'),
        );
        final decisionRequest = ExperienceReviewDecisionGrantRequest(
          requestId: AuthoringRequestId('schema-decision-grant'),
          capabilityDigest: fixture.capability().digest,
          fence: fixture.fence(fixture.acceptedPacket),
          decision: AppendExperienceHumanDecisionInput(
            decision: ExperienceHumanDecision.approve,
            rationale: 'Schema decision',
          ),
          automatedAcceptanceDigest:
              fixture.acceptedPacket.automatedAcceptance!.digest,
        );
        final abandonRequest = LayoutDraftAbandonRequest(
          requestId: AuthoringRequestId('schema-abandon'),
          subject: fixture.subject,
          draftId: fixture.movedDraft.id,
          expectedDraftDigest: fixture.movedDraft.digest,
          expectedDraftRevision: fixture.movedDraft.revision,
          expectedSourceDigest: fixture.sourceDigest,
          grantId: AuthoringActionGrantId('schema-abandon-grant'),
          grantDigest: _d('schema-abandon-grant'),
        );
        final promotionIntent = fixture.promotionIntent();
        final promotionApply = fixture.promotionApply(promotionIntent);
        final promotionGet = ExperiencePromotionGetRequest(
          requestId: AuthoringRequestId('schema-promotion-get'),
          subject: fixture.subject,
          receiptId: fixture.promotionReceipt.id,
          expectedReceiptDigest: fixture.promotionReceipt.digest,
        );
        final error = ExperienceAuthoringError(
          code: ExperienceAuthoringErrorCode.stale,
          requestId: AuthoringRequestId('schema-error'),
          subject: fixture.subject,
          expectedDigest: fixture.movedDraft.digest,
          currentDraftDigest: fixture.openDraft.digest,
        );
        final cases = <_SchemaCodecCase>[
          _SchemaCodecCase(
            fixture.capability().toJson(),
            AuthoringCapability.fromJson,
          ),
          _SchemaCodecCase(
            fixture.grant(fixture.intent()).toJson(),
            AuthoringActionGrant.fromJson,
          ),
          _SchemaCodecCase(fixture.openDraft.toJson(), LayoutDraft.fromJson),
          _SchemaCodecCase(
            fixture.comparison.toJson(),
            LayoutComparison.fromJson,
          ),
          _SchemaCodecCase(
            fixture.changeSet.toJson(),
            ExperienceChangeSet.fromJson,
          ),
          _SchemaCodecCase(
            fixture.initialPacket.toJson(),
            ExperienceReviewPacket.fromJson,
          ),
          _SchemaCodecCase(
            fixture.promotionReceipt.toJson(),
            ExperiencePromotionReceipt.fromJson,
          ),
          _SchemaCodecCase(
            openRequest.toJson(),
            LayoutDraftOpenRequest.fromJson,
          ),
          _SchemaCodecCase(
            mutationRequest.toJson(),
            LayoutDraftMutationRequest.fromJson,
          ),
          _SchemaCodecCase(
            prepareRequest.toJson(),
            ExperienceReviewPrepareRequest.fromJson,
          ),
          _SchemaCodecCase(
            actionRequest.toJson(),
            ExperienceReviewActionRequest.fromJson,
          ),
          _SchemaCodecCase(
            decisionRequest.toJson(),
            ExperienceReviewDecisionGrantRequest.fromJson,
          ),
          _SchemaCodecCase(
            abandonRequest.toJson(),
            LayoutDraftAbandonRequest.fromJson,
          ),
          _SchemaCodecCase(
            promotionIntent.toJson(),
            ExperiencePromotionGrantRequest.fromJson,
          ),
          _SchemaCodecCase(
            promotionApply.toJson(),
            ExperiencePromotionApplyRequest.fromJson,
          ),
          _SchemaCodecCase(
            promotionGet.toJson(),
            ExperiencePromotionGetRequest.fromJson,
          ),
          _SchemaCodecCase(
            ExperiencePromotionHistoryRequest(
              requestId: AuthoringRequestId('schema-promotion-history'),
              subject: fixture.subject,
              offset: 0,
              limit: 16,
            ).toJson(),
            ExperiencePromotionHistoryRequest.fromJson,
          ),
          _SchemaCodecCase(error.toJson(), ExperienceAuthoringError.fromJson),
        ];
        final globalKeys = (_schemaJson['properties']! as Map<String, Object?>)
            .keys
            .toSet();
        final variants = <String, Set<String>>{
          for (final raw in _schemaJson['oneOf']! as List<Object?>)
            _schemaVariantKind(raw!): _schemaVariantAllowed(raw),
        };
        for (final codecCase in cases) {
          final kind = codecCase.document['kind']! as String;
          expect(
            _schema.validate(codecCase.document).isValid,
            isTrue,
            reason: kind,
          );
          for (final foreignKey in globalKeys.difference(variants[kind]!)) {
            final injected = <String, Object?>{
              ...codecCase.document,
              foreignKey: null,
            };
            expect(
              _schema.validate(injected).isValid,
              isFalse,
              reason: '$kind accepted foreign $foreignKey in schema',
            );
            expect(
              () => codecCase.decode(injected),
              throwsFormatException,
              reason: '$kind accepted foreign $foreignKey in codec',
            );
          }
        }
      },
    );

    test('polymorphic field values cannot cross document variants', () {
      final fixture = _Fixture();
      final capability = fixture.capability();
      final description = ExperienceAuthoringDescription(
        requestId: AuthoringRequestId('cross-description'),
        subject: fixture.subject,
        availability: ExperienceAuthoringAvailability.available,
        capability: capability,
        allowedEffects: capability.effects,
        allowedOperations: capability.operations,
        currentContentSetDigest: fixture.contentSetDigest,
        currentSourceDigest: fixture.sourceDigest,
        currentTopologyDigest: fixture.topologyDigest,
        currentLayoutDigest: fixture.baseLayout.digest,
      );
      final findingInput = AppendExperienceFindingInput(
        subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
        severity: ExperienceFindingSeverity.warning,
        summary: 'Input summary',
        detail: 'Input detail',
      );
      final findingRecord = ExperienceFindingRecord(
        id: ExperienceFindingId('cross-finding'),
        subject: findingInput.subject,
        severity: findingInput.severity,
        summary: findingInput.summary,
        detail: findingInput.detail,
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('cross-finding-grant'),
        recordedAt: fixture.now,
      );
      final action = ExperienceReviewActionRequest(
        requestId: AuthoringRequestId('cross-finding-action'),
        fence: fixture.fence(fixture.initialPacket),
        operation: AuthoringOperation.appendFinding,
        grantId: AuthoringActionGrantId('cross-finding-grant'),
        grantDigest: _d('cross-finding-grant'),
        finding: findingInput,
      );
      final abandonReceipt = LayoutDraftAbandonReceipt(
        id: LayoutDraftAbandonReceiptId('cross-abandon'),
        requestId: AuthoringRequestId('cross-abandon-request'),
        subject: fixture.subject,
        draftId: fixture.movedDraft.id,
        finalDraftDigest: fixture.movedDraft.digest,
        finalDraftRevision: fixture.movedDraft.revision,
        sourceDigest: fixture.sourceDigest,
        abandonedAt: fixture.now,
      );
      final closedHead = fixture.head(
        promotion: ExperiencePromotionHeadRef.fromReceipt(
          fixture.promotionReceipt,
        ),
      );
      final promotionGetResult = ExperiencePromotionGetResult(
        requestId: AuthoringRequestId('cross-promotion-result'),
        receipt: fixture.promotionReceipt,
      );
      final cases = <_SchemaCodecCase>[
        _SchemaCodecCase(<String, Object?>{
          ...capability.toJson(),
          'capability': capability.toJson(),
        }, AuthoringCapability.fromJson),
        _SchemaCodecCase(<String, Object?>{
          ...description.toJson(),
          'capability': capability.capability.toJson(),
        }, ExperienceAuthoringDescription.fromJson),
        _SchemaCodecCase(<String, Object?>{
          ...fixture.changeSet.toJson(),
          'operations': <String>['moveNode'],
        }, ExperienceChangeSet.fromJson),
        _SchemaCodecCase(<String, Object?>{
          ...action.toJson(),
          'finding': findingRecord.toJson(),
        }, ExperienceReviewActionRequest.fromJson),
        _SchemaCodecCase(<String, Object?>{
          ...promotionGetResult.toJson(),
          'receipt': abandonReceipt.toJson(),
        }, ExperiencePromotionGetResult.fromJson),
        _SchemaCodecCase(<String, Object?>{
          ...ExperiencePromotionApplyResult(
            requestId: AuthoringRequestId('cross-apply-result'),
            receipt: fixture.promotionReceipt,
            head: closedHead,
          ).toJson(),
          'receipt': abandonReceipt.toJson(),
        }, ExperiencePromotionApplyResult.fromJson),
      ];
      for (final codecCase in cases) {
        expect(
          _schema.validate(codecCase.document).isValid,
          isFalse,
          reason: '${codecCase.document['kind']} accepted adjacent value shape',
        );
        expect(
          () => codecCase.decode(codecCase.document),
          throwsFormatException,
        );
      }
    });
  });
}

ExperienceReviewPacket _escapingMaxPacket(_Fixture fixture) {
  final findings = <ExperienceFindingRecord>[
    for (var index = 0; index < experienceAuthoringMaxFindings; index += 1)
      ExperienceFindingRecord(
        id: ExperienceFindingId('escaping-finding-$index'),
        subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
        severity: ExperienceFindingSeverity.warning,
        summary: '"' * 512,
        detail: r'\' * 2048,
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('escaping-finding-grant-$index'),
        recordedAt: fixture.now,
      ),
  ];
  final concepts = <ExperienceConceptProposalRecord>[
    for (var index = 0; index < experienceAuthoringMaxConcepts; index += 1)
      ExperienceConceptProposalRecord(
        id: ExperienceConceptProposalId('escaping-concept-$index'),
        scenarioId: ScenarioId('escaping-future-$index'),
        lifecycle: ScenarioLifecycle.concept,
        title: '"' * 256,
        rationale: r'\' * 1024,
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('escaping-concept-grant-$index'),
        recordedAt: fixture.now,
      ),
  ];
  final comments = <ExperienceReviewCommentRecord>[];
  for (var index = 0; index < experienceAuthoringMaxComments; index += 1) {
    comments.add(
      ExperienceReviewCommentRecord(
        id: ExperienceReviewCommentId('escaping-comment-$index'),
        sequence: index + 1,
        subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('escaping-comment-grant-$index'),
        body: '\u0001' * 1024,
        recordedAt: fixture.now,
        previousCommentDigest: index == 0 ? null : comments[index - 1].digest,
      ),
    );
  }
  final decisions = <ExperienceHumanDecisionRecord>[];
  for (var index = 0; index < experienceAuthoringMaxDecisions; index += 1) {
    decisions.add(
      ExperienceHumanDecisionRecord(
        id: ExperienceHumanDecisionId('escaping-decision-$index'),
        sequence: index + 1,
        changeSetDigest: fixture.changeSet.digest,
        reviewPacketDigest: _d('escaping-reviewed-$index'),
        principalId: fixture.principalId,
        authorityId: fixture.authorityId,
        grantDigest: _d('escaping-decision-grant-$index'),
        decision: ExperienceHumanDecision.reject,
        rationale: '\u0002' * 1024,
        recordedAt: fixture.now,
        previousDecisionDigest: index == 0 ? null : decisions[index - 1].digest,
      ),
    );
  }
  return fixture.packet(
    findings: findings,
    concepts: concepts,
    comments: comments,
    automatedAcceptance: AutomatedAcceptanceRecord(
      changeSetDigest: fixture.changeSet.digest,
      evaluatorId: projectionLayoutSafetyEvaluatorId,
      outcome: AutomatedAcceptanceOutcome.failed,
      summary: projectionLayoutSafetyFailedSummary,
      recordedAt: fixture.now,
    ),
    humanDecisions: decisions,
    revision: 100,
    previous: _d('escaping-previous'),
  );
}

final class _Fixture {
  _Fixture() {
    baseLayout = ProjectionLayoutManifest(
      topologyDigest: topologyDigest,
      projectionId: subject.projectionId,
      nodeFrames: <ProjectionNodeFrame>[
        ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('ready-node'),
          x: 10,
          y: 20,
          width: 300,
          height: 180,
        ),
      ],
      groups: const <ProjectionGroup>[],
      lanes: const <ProjectionLane>[],
      annotations: const <ProjectionAnnotation>[],
      camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
    );
    candidateLayout = ProjectionLayoutManifest(
      topologyDigest: topologyDigest,
      projectionId: subject.projectionId,
      nodeFrames: <ProjectionNodeFrame>[
        ProjectionNodeFrame(
          nodeInstanceId: NodeInstanceId('ready-node'),
          x: 100,
          y: 200,
          width: 300,
          height: 180,
        ),
      ],
      groups: const <ProjectionGroup>[],
      lanes: const <ProjectionLane>[],
      annotations: const <ProjectionAnnotation>[],
      camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
    );
    openDraft = LayoutDraft(
      id: LayoutDraftId('draft'),
      subject: subject,
      baseLayoutDigest: baseLayout.digest,
      candidateLayoutDigest: baseLayout.digest,
      baseSourceDigest: sourceDigest,
      topologyDigest: topologyDigest,
      contentSetDigest: contentSetDigest,
      history: const <LayoutMoveNodeOperation>[],
      cursor: 0,
      revision: 0,
      previousDraftDigest: null,
    );
    operation = LayoutMoveNodeOperation(
      id: LayoutOperationId('op-one'),
      nodeInstanceId: NodeInstanceId('ready-node'),
      fromX: 10,
      fromY: 20,
      toX: 100,
      toY: 200,
    );
    movedDraft = LayoutDraft(
      id: openDraft.id,
      subject: subject,
      baseLayoutDigest: baseLayout.digest,
      candidateLayoutDigest: candidateLayout.digest,
      baseSourceDigest: sourceDigest,
      topologyDigest: topologyDigest,
      contentSetDigest: contentSetDigest,
      history: <LayoutMoveNodeOperation>[operation],
      cursor: 1,
      revision: 1,
      previousDraftDigest: openDraft.digest,
    );
    comparison = LayoutComparison(
      topologyDigest: topologyDigest,
      projectionId: subject.projectionId,
      beforeLayoutDigest: baseLayout.digest,
      afterLayoutDigest: candidateLayout.digest,
      changedFrames: <LayoutFrameChange>[
        LayoutFrameChange(
          nodeInstanceId: NodeInstanceId('ready-node'),
          beforeX: 10,
          beforeY: 20,
          afterX: 100,
          afterY: 200,
        ),
      ],
    );
    changeSet = ExperienceChangeSet(
      id: ExperienceChangeSetId('change-set'),
      subject: subject,
      baseSourceDigest: sourceDigest,
      expectedContentSetDigest: contentSetDigest,
      draftDigest: movedDraft.digest,
      draftRevision: movedDraft.revision,
      comparison: comparison,
      operations: <LayoutMoveNodeOperation>[operation],
    );
    initialPacket = packet();
    acceptedPacket = packet(
      automatedAcceptance: AutomatedAcceptanceRecord(
        changeSetDigest: changeSet.digest,
        evaluatorId: projectionLayoutSafetyEvaluatorId,
        outcome: AutomatedAcceptanceOutcome.passed,
        summary: projectionLayoutSafetyPassedSummary,
        recordedAt: now,
      ),
      revision: 1,
      previous: initialPacket.digest,
    );
    approvedPacket = packet(
      automatedAcceptance: acceptedPacket.automatedAcceptance,
      humanDecisions: <ExperienceHumanDecisionRecord>[
        decisionRecord(reviewedDigest: acceptedPacket.digest),
      ],
      revision: 2,
      previous: acceptedPacket.digest,
    );
    final comment = ExperienceReviewCommentRecord(
      id: ExperienceReviewCommentId('comment-one'),
      sequence: 1,
      subject: ExperienceReviewSubject.scenario(ScenarioId('ready')),
      principalId: principalId,
      authorityId: authorityId,
      grantDigest: _d('comment-grant'),
      body: 'A later observation',
      recordedAt: now,
    );
    commentedPacket = packet(
      comments: <ExperienceReviewCommentRecord>[comment],
      automatedAcceptance: approvedPacket.automatedAcceptance,
      humanDecisions: approvedPacket.humanDecisions,
      revision: 3,
      previous: approvedPacket.digest,
    );
    promotionReceipt = ExperiencePromotionReceipt(
      id: ExperiencePromotionReceiptId('promotion-one'),
      sequence: 1,
      previousReceiptDigest: null,
      subject: subject,
      draftId: movedDraft.id,
      draftDigest: movedDraft.digest,
      draftRevision: movedDraft.revision,
      sourceDigest: sourceDigest,
      resultSourceDigest: _d('result-source'),
      previousContentSetDigest: contentSetDigest,
      resultContentSetDigest: _d('result-content'),
      layoutDigest: candidateLayout.digest,
      changeSetId: changeSet.id,
      changeSetDigest: changeSet.digest,
      reviewPacketId: approvedPacket.id,
      reviewPacketDigest: approvedPacket.digest,
      promotedAt: now,
    );
  }

  final DateTime now = DateTime.utc(2026, 8, 17, 12);
  final Digest topologyDigest = _d('topology');
  final Digest sourceDigest = _d('source');
  final Digest contentSetDigest = _d('content');
  final Digest planDigest = _d('plan');
  final AuthoringPrincipalId principalId = AuthoringPrincipalId('author');
  final AuthoringAuthorityId authorityId = AuthoringAuthorityId('authority');
  final AuthoringPolicyId policyId = AuthoringPolicyId('policy');
  final AuthoringSubjectRef subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace'),
    applicationId: ApplicationId('app'),
    projectionId: ExperienceProjectionId('journey'),
  );
  late final ProjectionLayoutManifest baseLayout;
  late final ProjectionLayoutManifest candidateLayout;
  late final LayoutDraft openDraft;
  late final LayoutMoveNodeOperation operation;
  late final LayoutDraft movedDraft;
  late final LayoutComparison comparison;
  late final ExperienceChangeSet changeSet;
  late final ExperienceReviewPacket initialPacket;
  late final ExperienceReviewPacket acceptedPacket;
  late final ExperienceReviewPacket approvedPacket;
  late final ExperienceReviewPacket commentedPacket;
  late final ExperiencePromotionReceipt promotionReceipt;

  LayoutMoveNodeInput get operationToInput => LayoutMoveNodeInput(
    nodeInstanceId: operation.nodeInstanceId,
    toX: operation.toX,
    toY: operation.toY,
  );

  AuthoringCapability capability() => AuthoringCapability(
    capability: ModuleCapabilityRef(id: 'experience.authoring', version: 1),
    moduleId: ModuleId('authoring.local'),
    resolvedPlanDigest: planDigest,
    subject: subject,
    effects: AuthoringActionEffect.values.toSet(),
    operations: AuthoringOperation.values.toSet(),
  );

  AuthoringGrantRequest intent() => AuthoringGrantRequest(
    requestId: AuthoringRequestId('grant-request'),
    capabilityDigest: capability().digest,
    subject: subject,
    effect: AuthoringActionEffect.authoring,
    operation: AuthoringOperation.moveNode,
    expectedDigest: openDraft.digest,
    expectedSourceDigest: sourceDigest,
    payloadDigest: _d('move-payload'),
  );

  AuthoringActionGrant grant(
    AuthoringGrantIntent intent, {
    DateTime? expiresAt,
  }) => AuthoringActionGrant(
    id: AuthoringActionGrantId('grant'),
    requestId: intent.requestId,
    requestDigest: intent.digest,
    payloadDigest: intent.payloadDigest,
    authorityId: authorityId,
    policyId: policyId,
    principalId: principalId,
    capabilityDigest: intent.capabilityDigest,
    subject: subject,
    effect: intent.effect,
    operation: intent.operation,
    expectedDigest: intent.expectedDigest,
    expectedSourceDigest: intent.expectedSourceDigest,
    issuedAt: now,
    expiresAt: expiresAt ?? now.add(const Duration(minutes: 2)),
    singleUse: true,
  );

  LayoutDraftOpenRequest openRequest() => LayoutDraftOpenRequest(
    requestId: AuthoringRequestId('open-effect'),
    subject: subject,
    expectedContentSetDigest: contentSetDigest,
    expectedSourceDigest: sourceDigest,
    grantId: AuthoringActionGrantId('open-grant'),
    grantDigest: _d('open-grant'),
  );

  ExperienceReviewPrepareRequest prepareRequest() =>
      ExperienceReviewPrepareRequest(
        requestId: AuthoringRequestId('prepare-effect'),
        subject: subject,
        draftId: movedDraft.id,
        expectedDraftDigest: movedDraft.digest,
        expectedDraftRevision: movedDraft.revision,
        expectedContentSetDigest: contentSetDigest,
        expectedSourceDigest: sourceDigest,
        reviewGuideId: ReviewGuideId('delivery-review'),
        reviewGuideStepId: 'ready-step',
        grantId: AuthoringActionGrantId('prepare-grant'),
        grantDigest: _d('prepare-grant'),
      );

  ExperienceReviewMutationFence fence(ExperienceReviewPacket packet) =>
      ExperienceReviewMutationFence(
        subject: subject,
        changeSetId: changeSet.id,
        changeSetDigest: changeSet.digest,
        reviewPacketId: packet.id,
        reviewPacketDigest: packet.digest,
        reviewPacketRevision: packet.revision,
        expectedSourceDigest: sourceDigest,
        expectedContentSetDigest: contentSetDigest,
      );

  ExperienceHumanDecisionRecord decisionRecord({
    required Digest reviewedDigest,
  }) => ExperienceHumanDecisionRecord(
    id: ExperienceHumanDecisionId('decision-one'),
    sequence: 1,
    changeSetDigest: changeSet.digest,
    reviewPacketDigest: reviewedDigest,
    principalId: principalId,
    authorityId: authorityId,
    grantDigest: _d('decision-grant'),
    decision: ExperienceHumanDecision.approve,
    rationale: 'Approved after automated acceptance',
    recordedAt: now,
  );

  ExperienceConceptProposalRecord conceptRecord(String id, String scenario) =>
      ExperienceConceptProposalRecord(
        id: ExperienceConceptProposalId(id),
        scenarioId: ScenarioId(scenario),
        lifecycle: ScenarioLifecycle.concept,
        title: 'Future concept',
        rationale: 'Explicitly non-current',
        principalId: principalId,
        authorityId: authorityId,
        grantDigest: _d('$id-grant'),
        recordedAt: now,
      );

  ExperienceReviewPacket packet({
    List<ExperienceFindingRecord> findings = const <ExperienceFindingRecord>[],
    List<ExperienceConceptProposalRecord> concepts =
        const <ExperienceConceptProposalRecord>[],
    List<ExperienceReviewCommentRecord> comments =
        const <ExperienceReviewCommentRecord>[],
    AutomatedAcceptanceRecord? automatedAcceptance,
    List<ExperienceHumanDecisionRecord> humanDecisions =
        const <ExperienceHumanDecisionRecord>[],
    int revision = 0,
    Digest? previous,
  }) => ExperienceReviewPacket(
    id: ExperienceReviewPacketId('review-packet'),
    subject: subject,
    changeSetId: changeSet.id,
    changeSetDigest: changeSet.digest,
    comparisonDigest: comparison.digest,
    baseSourceDigest: sourceDigest,
    findings: findings,
    concepts: concepts,
    comments: comments,
    reviewGuideBinding: ExecutableReviewGuideBinding(
      catalogDigest: _d('catalog'),
      applicationId: subject.applicationId,
      reviewGuideId: ReviewGuideId('delivery-review'),
      stepId: 'ready-step',
      scenarioId: ScenarioId('ready'),
      bindingId: ScenarioExecutionBindingId('ready-web'),
    ),
    automatedAcceptance: automatedAcceptance,
    humanDecisions: humanDecisions,
    revision: revision,
    previousReviewPacketDigest: previous,
  );

  ExperienceAuthoringSubjectHead head({
    LayoutDraft? draft,
    ExperienceChangeSet? changeSet,
    ExperienceReviewPacket? packet,
    ExperiencePromotionHeadRef? promotion,
  }) => ExperienceAuthoringSubjectHead(
    subject: subject,
    draft: draft == null ? null : LayoutDraftHeadRef.fromDraft(draft),
    changeSet: changeSet == null
        ? null
        : ExperienceChangeSetHeadRef.fromChangeSet(changeSet),
    review: packet == null ? null : ExperienceReviewHeadRef.fromPacket(packet),
    latestPromotion: promotion,
  );

  ExperiencePromotionGrantRequest promotionIntent() =>
      ExperiencePromotionGrantRequest(
        requestId: AuthoringRequestId('promotion-grant-request'),
        capabilityDigest: capability().digest,
        subject: subject,
        draftId: movedDraft.id,
        draftDigest: movedDraft.digest,
        draftRevision: movedDraft.revision,
        changeSetId: changeSet.id,
        changeSetDigest: changeSet.digest,
        reviewPacketId: approvedPacket.id,
        reviewPacketDigest: approvedPacket.digest,
        expectedSourceDigest: sourceDigest,
        expectedContentSetDigest: contentSetDigest,
        candidateLayoutDigest: candidateLayout.digest,
      );

  ExperiencePromotionApplyRequest promotionApply(
    ExperiencePromotionGrantRequest intent,
  ) => ExperiencePromotionApplyRequest(
    requestId: AuthoringRequestId('promotion-effect-request'),
    subject: subject,
    draftId: movedDraft.id,
    draftDigest: movedDraft.digest,
    draftRevision: movedDraft.revision,
    changeSetId: changeSet.id,
    changeSetDigest: changeSet.digest,
    reviewPacketId: approvedPacket.id,
    reviewPacketDigest: approvedPacket.digest,
    expectedSourceDigest: sourceDigest,
    expectedContentSetDigest: contentSetDigest,
    candidateLayoutDigest: candidateLayout.digest,
    grantId: AuthoringActionGrantId('promotion-grant'),
    grantDigest: _d('promotion-grant'),
  );
}

final class _SchemaCodecCase {
  const _SchemaCodecCase(this.document, this.decode);

  final Map<String, Object?> document;
  final Object? Function(Object?) decode;
}

String _schemaVariantKind(Object raw) =>
    (((raw as Map<String, Object?>)['properties']!
                as Map<String, Object?>)['kind']!
            as Map<String, Object?>)['const']!
        as String;

Set<String> _schemaVariantAllowed(Object raw) =>
    ((((raw as Map<String, Object?>)['propertyNames']!
                    as Map<String, Object?>)['enum']!
                as List<Object?>)
            .cast<String>())
        .toSet();

final Map<String, Object?> _schemaJson =
    jsonDecode(
          File(
            p.join(
              _repositoryRoot(),
              'schemas/runtime/experience-authoring.schema.json',
            ),
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

final Draft202012Validator _schema = Draft202012Validator(_schemaJson);

String _repositoryRoot() {
  var current = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return current.path;
    }
    if (current.parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = current.parent;
  }
}

Map<String, Object?> _wire(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

String _emoji(int count) => List<String>.filled(count, '😀').join();

Digest _d(String seed) => Digest.semantic(seed);
