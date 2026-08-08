import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('ExperienceAuthoringService authority lifecycle', () {
    late Directory workspace;
    late _Fixture fixture;
    late _MutableResolver resolver;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync(
        'workspace-authoring-service-',
      );
      fixture = _Fixture();
      resolver = _MutableResolver(fixture.snapshot);
    });

    tearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });

    test('empty settings retain query-only policyDenied description', () {
      final store = fixture.store(workspace);
      final service = fixture.service(
        store: store,
        resolver: resolver,
        settings: ExperienceAuthoringAuthoritySettings.fromJson(
          const <String, Object?>{},
        ),
      );
      final request = ExperienceAuthoringDescribeRequest(
        requestId: AuthoringRequestId('describe-viewer'),
        subject: fixture.subject,
      );

      final result = service.describe(request);

      expect(result.availability, ExperienceAuthoringAvailability.policyDenied);
      expect(result.capability, isNotNull);
      expect(result.allowedEffects, <AuthoringActionEffect>{
        AuthoringActionEffect.query,
      });
      expect(
        result.allowedOperations.every(
          (operation) =>
              authoringEffectFor(operation) == AuthoringActionEffect.query,
        ),
        isTrue,
      );
      expect(
        result.allowedOperations,
        contains(AuthoringOperation.getSubjectHead),
      );
      expect(
        result.allowedOperations,
        isNot(contains(AuthoringOperation.getDraft)),
      );
      expect(
        () => service.requestGrant(
          fixture.openIntent(
            requestId: 'viewer-open-grant',
            payloadDigest: fixture.openPayload,
          ),
          connectionEpoch: 'viewer-connection',
        ),
        throwsA(_serviceError(ExperienceAuthoringErrorCode.policyDenied)),
      );
      expect(
        store.findAttempt(AuthoringRequestId('viewer-open-grant')),
        isNull,
      );
    });

    test('unproven state writer makes the authority strictly unsupported', () {
      final store = fixture.store(
        workspace,
        writer: const _UnsupportedStateWriter(),
      );
      final service = fixture.service(store: store, resolver: resolver);
      final description = service.describe(
        ExperienceAuthoringDescribeRequest(
          requestId: AuthoringRequestId('unsupported-durability-describe'),
          subject: fixture.subject,
        ),
      );

      expect(
        description.availability,
        ExperienceAuthoringAvailability.unsupported,
      );
      expect(description.capability, isNull);
      expect(description.allowedEffects, isEmpty);
      expect(description.allowedOperations, isEmpty);
      expect(
        () => service.getSubjectHead(
          ExperienceAuthoringSubjectHeadRequest(
            requestId: AuthoringRequestId('unsupported-durability-head'),
            subject: fixture.subject,
          ),
        ),
        throwsA(
          _serviceError(ExperienceAuthoringErrorCode.capabilityUnavailable),
        ),
      );
      expect(
        () => service.requestGrant(
          fixture.openIntent(
            requestId: 'unsupported-durability-grant',
            payloadDigest: fixture.openPayload,
          ),
          connectionEpoch: 'unsupported-durability-connection',
        ),
        throwsA(
          _serviceError(ExperienceAuthoringErrorCode.capabilityUnavailable),
        ),
      );
      expect(File(store.stateFilePath).existsSync(), isFalse);
    });

    test('journal fsync uncertainty returns one bounded typed error', () {
      final fault = _DestinationFsyncFault();
      final store = fixture.store(
        workspace,
        writer: DefaultExperienceAuthoringStateWriter(beforeFsync: fault.call),
      );
      final service = fixture.service(store: store, resolver: resolver);
      final intent = fixture.openIntent(
        requestId: 'durability-failure-grant',
        payloadDigest: fixture.openPayload,
      );

      for (var attempt = 0; attempt < 2; attempt += 1) {
        try {
          service.requestGrant(
            intent,
            connectionEpoch: 'durability-failure-connection',
          );
          fail('durability-uncertain grant unexpectedly succeeded');
        } on ExperienceAuthoringServiceException catch (failure) {
          expect(failure.error.code, ExperienceAuthoringErrorCode.unavailable);
          expect(
            jsonEncode(failure.error.toJson()).length,
            lessThan(experienceAuthoringMaxFrameBytes),
          );
        }
      }
      expect(store.hasDurabilityUncertainty, isTrue);
      expect(
        service
            .describe(
              ExperienceAuthoringDescribeRequest(
                requestId: AuthoringRequestId('durability-failure-describe'),
                subject: fixture.subject,
              ),
            )
            .availability,
        ExperienceAuthoringAvailability.unsupported,
      );
    });

    test(
      'open is durable, effect replay precedes restart epoch revocation',
      () {
        final store = fixture.store(workspace);
        final service = fixture.service(store: store, resolver: resolver);
        final grant = service.requestGrant(
          fixture.openIntent(
            requestId: 'open-grant-request',
            payloadDigest: fixture.openPayload,
          ),
          connectionEpoch: 'connection-one',
        );
        final effect = fixture.openEffect(
          requestId: 'open-effect-request',
          grant: grant.grant,
        );

        final opened = service.openDraft(
          effect,
          connectionEpoch: 'connection-one',
        );
        expect(opened.resumed, isFalse);
        expect(
          store.findGrant(grant.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );

        final restartedStore = fixture.store(workspace);
        final restarted = fixture.service(
          store: restartedStore,
          resolver: resolver,
        );
        final replay = restarted.openDraft(
          effect,
          connectionEpoch: 'different-connection-after-restart',
        );

        expect(replay.toJson(), opened.toJson());
        expect(
          restartedStore.requireDraft(fixture.subject).draft.digest,
          opened.draft.digest,
        );
      },
    );

    test(
      'stale source consumes a structurally bound grant and replays error',
      () {
        final store = fixture.store(workspace);
        final service = fixture.service(store: store, resolver: resolver);
        final grant = service.requestGrant(
          fixture.openIntent(
            requestId: 'stale-open-grant',
            payloadDigest: fixture.openPayload,
          ),
          connectionEpoch: 'connection-stale',
        );
        final effect = fixture.openEffect(
          requestId: 'stale-open-effect',
          grant: grant.grant,
        );
        resolver.snapshot = fixture.snapshotWith(
          sourceDigest: _d('externally-edited-source'),
        );

        ExperienceAuthoringError firstError() {
          try {
            service.openDraft(effect, connectionEpoch: 'connection-stale');
            fail('stale open unexpectedly succeeded');
          } on ExperienceAuthoringServiceException catch (error) {
            return error.error;
          }
        }

        final first = firstError();
        final replay = firstError();
        expect(first.code, ExperienceAuthoringErrorCode.stale);
        expect(replay.toJson(), first.toJson());
        expect(
          store.findGrant(grant.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );
        expect(
          store.findAttempt(effect.requestId)!.terminalJson,
          first.toJson(),
        );
        expect(store.findDraft(fixture.subject), isNull);
      },
    );

    test('same-principal loser is stale and consumes a head-revoked grant', () {
      final store = fixture.store(workspace);
      final service = fixture.service(store: store, resolver: resolver);
      final draft = fixture.openThrough(service, connection: 'connection-cas');
      final moveA = fixture.moveEffectTemplate(
        requestId: 'move-effect-a',
        draft: draft,
        toX: 450,
      );
      final moveB = fixture.moveEffectTemplate(
        requestId: 'move-effect-b',
        draft: draft,
        toX: 450,
      );
      final grantA = service.requestGrant(
        fixture.mutationIntent(
          requestId: 'move-grant-a',
          draft: draft,
          payloadDigest: moveA.payloadDigest,
        ),
        connectionEpoch: 'connection-cas',
      );
      final grantB = service.requestGrant(
        fixture.mutationIntent(
          requestId: 'move-grant-b',
          draft: draft,
          payloadDigest: moveB.payloadDigest,
        ),
        connectionEpoch: 'connection-cas',
      );
      final effectA = fixture.withMutationGrant(moveA, grantA.grant);
      final effectB = fixture.withMutationGrant(moveB, grantB.grant);

      final winner = service.mutateDraft(
        effectA,
        connectionEpoch: 'connection-cas',
      );
      expect(winner.draft.revision, 1);
      expect(
        store.findGrant(grantB.grant.id)!.state,
        StoredAuthoringGrantState.revoked,
      );
      expect(
        store.findGrant(grantB.grant.id)!.revocationReason,
        'subject-head-changed',
      );
      final forgedError = ExperienceAuthoringError(
        code: ExperienceAuthoringErrorCode.grantExpired,
        requestId: AuthoringRequestId('forged-non-stale-terminal'),
        subject: fixture.subject,
        operation: AuthoringOperation.moveNode,
        mutation: LayoutDraftMutation.applyMove,
        draftId: draft.id,
      );
      expect(
        () => store.commitAtomic(
          ExperienceAuthoringAtomicCommit(
            attempt: StoredAuthoringAttempt(
              family: StoredAuthoringAttemptFamily.draftMutation,
              requestId: forgedError.requestId,
              requestDigest: _d('forged-non-stale-request'),
              payloadDigest: grantB.grant.payloadDigest,
              subject: fixture.subject,
              effect: AuthoringActionEffect.authoring,
              operation: AuthoringOperation.moveNode,
              grantId: grantB.grant.id,
              grantDigest: grantB.grant.digest,
              isError: true,
              terminalJson: forgedError.toJson(),
              completedAt: fixture.now,
            ),
            consumedGrantId: grantB.grant.id,
          ),
        ),
        throwsFormatException,
      );
      expect(
        store.findGrant(grantB.grant.id)!.state,
        StoredAuthoringGrantState.revoked,
      );

      ExperienceAuthoringError lose() {
        try {
          service.mutateDraft(effectB, connectionEpoch: 'connection-cas');
          fail('stale writer unexpectedly won');
        } on ExperienceAuthoringServiceException catch (error) {
          return error.error;
        }
      }

      final first = lose();
      final replay = lose();
      expect(first.code, ExperienceAuthoringErrorCode.stale);
      expect(replay.toJson(), first.toJson());
      expect(
        store.findGrant(grantB.grant.id)!.state,
        StoredAuthoringGrantState.consumed,
      );
      expect(
        store.requireDraft(fixture.subject).draft.digest,
        winner.draft.digest,
      );
    });

    test(
      'atomic mutation quota is terminal across checkpoint and reserves abandon',
      () {
        final store = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
          maxJournalEntries: 2,
          maxDraftMutations: 1,
        );
        var service = fixture.service(store: store, resolver: resolver);
        final opened = fixture.openThrough(
          service,
          connection: 'quota-connection',
        );
        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: 'quota-move',
          connection: 'quota-connection',
          toX: 250,
        );
        final template = LayoutDraftMutationRequest(
          requestId: AuthoringRequestId('quota-undo-effect'),
          draftId: moved.id,
          expectedDraftDigest: moved.digest,
          expectedDraftRevision: moved.revision,
          grantId: AuthoringActionGrantId('quota-undo-template'),
          grantDigest: _d('quota-undo-template'),
          mutation: LayoutDraftMutation.undo,
        );
        final grant = service.requestGrant(
          AuthoringGrantRequest(
            requestId: AuthoringRequestId('quota-undo-grant'),
            capabilityDigest: fixture.capability.digest,
            subject: fixture.subject,
            effect: AuthoringActionEffect.authoring,
            operation: AuthoringOperation.undo,
            expectedDigest: moved.digest,
            expectedSourceDigest: moved.baseSourceDigest,
            payloadDigest: template.payloadDigest,
          ),
          connectionEpoch: 'quota-connection',
        );
        final request = LayoutDraftMutationRequest(
          requestId: template.requestId,
          draftId: template.draftId,
          expectedDraftDigest: template.expectedDraftDigest,
          expectedDraftRevision: template.expectedDraftRevision,
          grantId: grant.grant.id,
          grantDigest: grant.grant.digest,
          mutation: template.mutation,
        );

        ExperienceAuthoringError attempt(ExperienceAuthoringService target) {
          try {
            target.mutateDraft(request, connectionEpoch: 'quota-connection');
            fail('quota-limited mutation unexpectedly succeeded');
          } on ExperienceAuthoringServiceException catch (error) {
            return error.error;
          }
        }

        final first = attempt(service);
        expect(first.code, ExperienceAuthoringErrorCode.quotaExceeded);
        expect(store.requireDraft(fixture.subject).draft.digest, moved.digest);
        expect(
          store.findGrant(grant.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );
        expect(
          store.findAttempt(request.requestId)!.terminalJson,
          first.toJson(),
        );

        final restartedStore = FilesystemExperienceAuthoringStore(
          workspaceStore: FileSystemWorkspaceStore(
            workspaceRoot: workspace.path,
          ),
          maxJournalEntries: 2,
          maxDraftMutations: 1,
        );
        service = fixture.service(store: restartedStore, resolver: resolver);
        expect(attempt(service).toJson(), first.toJson());

        final abandonTemplate = LayoutDraftAbandonRequest(
          requestId: AuthoringRequestId('quota-abandon-effect'),
          subject: fixture.subject,
          draftId: moved.id,
          expectedDraftDigest: moved.digest,
          expectedDraftRevision: moved.revision,
          expectedSourceDigest: moved.baseSourceDigest,
          grantId: AuthoringActionGrantId('quota-abandon-template'),
          grantDigest: _d('quota-abandon-template'),
        );
        final abandonGrant = service.requestGrant(
          AuthoringGrantRequest(
            requestId: AuthoringRequestId('quota-abandon-grant'),
            capabilityDigest: fixture.capability.digest,
            subject: fixture.subject,
            effect: AuthoringActionEffect.authoring,
            operation: AuthoringOperation.abandonDraft,
            expectedDigest: moved.digest,
            expectedSourceDigest: moved.baseSourceDigest,
            payloadDigest: abandonTemplate.payloadDigest,
          ),
          connectionEpoch: 'quota-connection',
        );
        final abandoned = service.abandonDraft(
          LayoutDraftAbandonRequest(
            requestId: abandonTemplate.requestId,
            subject: abandonTemplate.subject,
            draftId: abandonTemplate.draftId,
            expectedDraftDigest: abandonTemplate.expectedDraftDigest,
            expectedDraftRevision: abandonTemplate.expectedDraftRevision,
            expectedSourceDigest: abandonTemplate.expectedSourceDigest,
            grantId: abandonGrant.grant.id,
            grantDigest: abandonGrant.grant.digest,
          ),
          connectionEpoch: 'quota-connection',
        );
        expect(abandoned.receipt.finalDraftDigest, moved.digest);
        expect(restartedStore.findDraft(fixture.subject), isNull);
      },
    );

    test(
      'disconnect revocation never uses the stale-head consume exception',
      () {
        final store = fixture.store(workspace);
        final service = fixture.service(store: store, resolver: resolver);
        final draft = fixture.openThrough(
          service,
          connection: 'connection-disconnect',
        );
        final template = fixture.moveEffectTemplate(
          requestId: 'move-after-disconnect',
          draft: draft,
          toX: 480,
        );
        final grant = service.requestGrant(
          fixture.mutationIntent(
            requestId: 'move-disconnect-grant',
            draft: draft,
            payloadDigest: template.payloadDigest,
          ),
          connectionEpoch: 'connection-disconnect',
        );
        final effect = fixture.withMutationGrant(template, grant.grant);
        expect(service.revokeConnection('connection-disconnect'), 1);

        expect(
          () => service.mutateDraft(
            effect,
            connectionEpoch: 'connection-disconnect',
          ),
          throwsA(_serviceError(ExperienceAuthoringErrorCode.grantRevoked)),
        );
        expect(
          store.findGrant(grant.grant.id)!.state,
          StoredAuthoringGrantState.revoked,
        );
        expect(store.findAttempt(effect.requestId), isNull);
      },
    );

    test(
      'review acceptance and head approval survive restart and later input invalidates promotion',
      () {
        final store = fixture.store(workspace);
        var service = fixture.service(store: store, resolver: resolver);
        final opened = fixture.openThrough(
          service,
          connection: 'connection-review',
        );
        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: 'review-move',
          connection: 'connection-review',
          toX: 250,
        );
        final prepared = fixture.prepareThrough(
          service,
          draft: moved,
          requestStem: 'review-prepare',
          connection: 'connection-review',
        );
        final accepted = fixture.acceptThrough(
          service,
          prepared: prepared,
          requestStem: 'review-accept',
          connection: 'connection-review',
        );
        expect(
          accepted.automatedAcceptance!.outcome,
          AutomatedAcceptanceOutcome.passed,
        );
        final approved = fixture.decideThrough(
          service,
          changeSet: prepared.changeSet,
          packet: accepted.reviewPacket,
          requestStem: 'review-approve',
          connection: 'connection-review',
          decision: ExperienceHumanDecision.approve,
        );
        expect(approved.reviewPacket.isPromotable, isTrue);

        service = fixture.service(
          store: fixture.store(workspace),
          resolver: resolver,
        );
        final historicalChange = service.getChangeSet(
          ExperienceChangeSetGetRequest(
            requestId: AuthoringRequestId('historical-change-after-restart'),
            subject: fixture.subject,
            changeSetId: prepared.changeSet.id,
            expectedChangeSetDigest: prepared.changeSet.digest,
          ),
        );
        final historicalReview = service.getReview(
          ExperienceReviewGetRequest(
            requestId: AuthoringRequestId('historical-review-after-restart'),
            subject: fixture.subject,
            reviewPacketId: approved.reviewPacket.id,
            expectedReviewPacketDigest: approved.reviewPacket.digest,
          ),
        );
        historicalReview.validateWithChangeSet(historicalChange);
        expect(
          service
              .getSubjectHead(
                ExperienceAuthoringSubjectHeadRequest(
                  requestId: AuthoringRequestId('head-after-review-restart'),
                  subject: fixture.subject,
                ),
              )
              .head
              .review!
              .digest,
          approved.reviewPacket.digest,
        );

        final commented = fixture.commentThrough(
          service,
          changeSet: prepared.changeSet,
          packet: approved.reviewPacket,
          requestStem: 'review-comment',
          connection: 'connection-review-new',
        );
        expect(commented.reviewPacket.isPromotable, isFalse);
        expect(
          () => service.requestPromotionGrant(
            fixture.promotionIntent(
              draft: moved,
              changeSet: prepared.changeSet,
              packet: commented.reviewPacket,
              requestId: 'blocked-promotion-grant',
            ),
            connectionEpoch: 'connection-review-new',
          ),
          throwsA(_serviceError(ExperienceAuthoringErrorCode.stale)),
        );

        final reapproved = fixture.decideThrough(
          service,
          changeSet: prepared.changeSet,
          packet: commented.reviewPacket,
          requestStem: 'review-reapprove',
          connection: 'connection-review-new',
          decision: ExperienceHumanDecision.approve,
        );
        expect(reapproved.reviewPacket.isPromotable, isTrue);
        final promotionGrant = service.requestPromotionGrant(
          fixture.promotionIntent(
            draft: moved,
            changeSet: prepared.changeSet,
            packet: reapproved.reviewPacket,
            requestId: 'allowed-promotion-grant',
          ),
          connectionEpoch: 'connection-review-new',
        );
        expect(promotionGrant.grant.operation, AuthoringOperation.promote);
      },
    );

    test('new open after review resumes the complete durable head', () {
      final store = fixture.store(workspace);
      var service = fixture.service(store: store, resolver: resolver);
      final opened = fixture.openThrough(
        service,
        connection: 'resume-head-initial',
      );
      final moved = fixture.moveThrough(
        service,
        draft: opened,
        requestStem: 'resume-head-move',
        connection: 'resume-head-initial',
        toX: 250,
      );
      final prepared = fixture.prepareThrough(
        service,
        draft: moved,
        requestStem: 'resume-head-review',
        connection: 'resume-head-initial',
      );
      final expectedHead = store.subjectHead(fixture.subject);
      expect(expectedHead.changeSet?.digest, prepared.changeSet.digest);
      expect(expectedHead.review?.digest, prepared.reviewPacket.digest);

      final restartedStore = fixture.store(workspace);
      service = fixture.service(store: restartedStore, resolver: resolver);
      final grant = service.requestGrant(
        fixture.openIntent(
          requestId: 'resume-head-new-grant',
          payloadDigest: fixture.openPayload,
        ),
        connectionEpoch: 'resume-head-after-restart',
      );
      final resumed = service.openDraft(
        fixture.openEffect(
          requestId: 'resume-head-new-effect',
          grant: grant.grant,
        ),
        connectionEpoch: 'resume-head-after-restart',
      );

      expect(resumed.resumed, isTrue);
      expect(resumed.draft.digest, moved.digest);
      expect(resumed.head.toJson(), expectedHead.toJson());
      expect(
        restartedStore.subjectHead(fixture.subject).toJson(),
        expectedHead.toJson(),
      );
    });

    test('structural acceptance fails overlap but permits touching edges', () {
      AutomatedAcceptanceOutcome evaluateAt(double x, double y, String stem) {
        final isolatedWorkspace = Directory.systemTemp.createTempSync(
          'workspace-authoring-safety-',
        );
        addTearDown(() {
          if (isolatedWorkspace.existsSync()) {
            isolatedWorkspace.deleteSync(recursive: true);
          }
        });
        final localStore = fixture.store(isolatedWorkspace);
        final localResolver = _MutableResolver(fixture.snapshot);
        final service = fixture.service(
          store: localStore,
          resolver: localResolver,
        );
        final opened = fixture.openThrough(
          service,
          connection: '$stem-connection',
        );
        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: '$stem-move',
          connection: '$stem-connection',
          toX: x,
          toY: y,
        );
        final prepared = fixture.prepareThrough(
          service,
          draft: moved,
          requestStem: '$stem-prepare',
          connection: '$stem-connection',
        );
        return fixture
            .acceptThrough(
              service,
              prepared: prepared,
              requestStem: '$stem-accept',
              connection: '$stem-connection',
            )
            .automatedAcceptance!
            .outcome;
      }

      expect(evaluateAt(150, 50, 'overlap'), AutomatedAcceptanceOutcome.failed);
      expect(evaluateAt(200, 0, 'touch'), AutomatedAcceptanceOutcome.passed);
    });

    test(
      'oversized review result consumes the grant without advancing the packet',
      () {
        final store = fixture.store(workspace);
        final service = fixture.service(store: store, resolver: resolver);
        final opened = fixture.openThrough(service, connection: 'frame-budget');
        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: 'frame-budget-move',
          connection: 'frame-budget',
          toX: 250,
        );
        final prepared = fixture.prepareThrough(
          service,
          draft: moved,
          requestStem: 'frame-budget-review',
          connection: 'frame-budget',
        );
        var packet = prepared.reviewPacket;
        final escapedComment = List<String>.filled(1024, '\u0001').join();
        for (var index = 0; index < 5; index += 1) {
          packet = fixture
              .commentThrough(
                service,
                changeSet: prepared.changeSet,
                packet: packet,
                requestStem: 'frame-budget-comment-$index',
                connection: 'frame-budget',
                body: index == 4
                    ? List<String>.filled(600, '\u0001').join()
                    : escapedComment,
              )
              .reviewPacket;
        }
        final before = packet;
        final fence = fixture.reviewFence(prepared.changeSet, before);
        final input = AppendExperienceFindingInput(
          subject: ExperienceReviewSubject.scenario(
            before.reviewGuideBinding.scenarioId,
          ),
          severity: ExperienceFindingSeverity.warning,
          summary: List<String>.filled(512, '\u0002').join(),
          detail: List<String>.filled(2048, '\u0003').join(),
        );
        final template = ExperienceReviewActionRequest(
          requestId: AuthoringRequestId('frame-budget-finding-effect'),
          fence: fence,
          operation: AuthoringOperation.appendFinding,
          finding: input,
          grantId: AuthoringActionGrantId('frame-budget-template'),
          grantDigest: _d('frame-budget-template'),
        );
        final grant = service.requestGrant(
          fixture._reviewGrantIntent(
            requestId: 'frame-budget-finding-grant',
            fence: fence,
            operation: template.operation,
            payloadDigest: template.payloadDigest,
          ),
          connectionEpoch: 'frame-budget',
        );
        final request = ExperienceReviewActionRequest(
          requestId: template.requestId,
          fence: fence,
          operation: template.operation,
          finding: input,
          grantId: grant.grant.id,
          grantDigest: grant.grant.digest,
        );

        expect(
          () => service.reviewAction(request, connectionEpoch: 'frame-budget'),
          throwsA(_serviceError(ExperienceAuthoringErrorCode.quotaExceeded)),
        );
        expect(
          store.findGrant(grant.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );
        expect(store.findAttempt(request.requestId)!.isError, isTrue);
        expect(
          store.subjectHead(fixture.subject).review!.digest,
          before.digest,
        );
        expect(
          store.findReviewPacket(
            subject: fixture.subject,
            id: before.id,
            expectedDigest: before.digest,
          ),
          isNotNull,
        );
      },
    );

    test('writer persisted-then-error returns exact terminal open success', () {
      final writer = _PersistThenErrorWriter();
      final store = fixture.store(workspace, writer: writer);
      final service = fixture.service(store: store, resolver: resolver);
      final grant = service.requestGrant(
        fixture.openIntent(
          requestId: 'ambiguous-open-grant',
          payloadDigest: fixture.openPayload,
        ),
        connectionEpoch: 'connection-ambiguous',
      );
      final effect = fixture.openEffect(
        requestId: 'ambiguous-open-effect',
        grant: grant.grant,
      );
      writer.throwAfterNextPersist = true;

      final result = service.openDraft(
        effect,
        connectionEpoch: 'connection-ambiguous',
      );

      expect(
        result.draft.digest,
        store.requireDraft(fixture.subject).draft.digest,
      );
      expect(store.findAttempt(effect.requestId)!.isError, isFalse);
    });

    test(
      'persisted-then-error recovers mutation review and abandon families',
      () {
        final writer = _PersistThenErrorWriter();
        final store = fixture.store(workspace, writer: writer);
        final service = fixture.service(store: store, resolver: resolver);
        final opened = fixture.openThrough(
          service,
          connection: 'ambiguous-families',
        );

        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: 'ambiguous-mutation',
          connection: 'ambiguous-families',
          toX: 250,
          beforeEffect: () => writer.throwAfterNextPersist = true,
        );
        expect(moved.revision, 1);
        expect(
          store
              .findAttempt(AuthoringRequestId('ambiguous-mutation-effect'))!
              .isError,
          isFalse,
        );

        final prepared = fixture.prepareThrough(
          service,
          draft: moved,
          requestStem: 'ambiguous-prepare',
          connection: 'ambiguous-families',
          beforeEffect: () => writer.throwAfterNextPersist = true,
        );
        expect(
          store
              .findAttempt(AuthoringRequestId('ambiguous-prepare-effect'))!
              .isError,
          isFalse,
        );

        final accepted = fixture.acceptThrough(
          service,
          prepared: prepared,
          requestStem: 'ambiguous-review-action',
          connection: 'ambiguous-families',
          beforeEffect: () => writer.throwAfterNextPersist = true,
        );
        expect(accepted.automatedAcceptance, isNotNull);
        expect(
          store
              .findAttempt(
                AuthoringRequestId('ambiguous-review-action-effect'),
              )!
              .isError,
          isFalse,
        );

        final abandonTemplate = LayoutDraftAbandonRequest(
          requestId: AuthoringRequestId('ambiguous-abandon-effect'),
          subject: fixture.subject,
          draftId: moved.id,
          expectedDraftDigest: moved.digest,
          expectedDraftRevision: moved.revision,
          expectedSourceDigest: moved.baseSourceDigest,
          grantId: AuthoringActionGrantId('ambiguous-abandon-template'),
          grantDigest: _d('ambiguous-abandon-template'),
        );
        final abandonGrant = service.requestGrant(
          AuthoringGrantRequest(
            requestId: AuthoringRequestId('ambiguous-abandon-grant'),
            capabilityDigest: fixture.capability.digest,
            subject: fixture.subject,
            effect: AuthoringActionEffect.authoring,
            operation: AuthoringOperation.abandonDraft,
            expectedDigest: moved.digest,
            expectedSourceDigest: moved.baseSourceDigest,
            payloadDigest: abandonTemplate.payloadDigest,
          ),
          connectionEpoch: 'ambiguous-families',
        );
        final abandonRequest = LayoutDraftAbandonRequest(
          requestId: abandonTemplate.requestId,
          subject: abandonTemplate.subject,
          draftId: abandonTemplate.draftId,
          expectedDraftDigest: abandonTemplate.expectedDraftDigest,
          expectedDraftRevision: abandonTemplate.expectedDraftRevision,
          expectedSourceDigest: abandonTemplate.expectedSourceDigest,
          grantId: abandonGrant.grant.id,
          grantDigest: abandonGrant.grant.digest,
        );
        writer.throwAfterNextPersist = true;
        final abandoned = service.abandonDraft(
          abandonRequest,
          connectionEpoch: 'ambiguous-families',
        );

        expect(abandoned.receipt.finalDraftDigest, moved.digest);
        expect(store.findAttempt(abandonRequest.requestId)!.isError, isFalse);
        expect(store.findDraft(fixture.subject), isNull);
      },
    );

    test('querying a live draft is restricted to its configured owner', () {
      final ownerStore = fixture.store(workspace);
      final owner = fixture.service(store: ownerStore, resolver: resolver);
      final draft = fixture.openThrough(owner, connection: 'owner-connection');
      final viewer = fixture.service(
        store: fixture.store(workspace),
        resolver: resolver,
        settings: ExperienceAuthoringAuthoritySettings.fromJson(
          const <String, Object?>{},
        ),
      );

      expect(
        () => viewer.getDraft(
          LayoutDraftGetRequest(
            requestId: AuthoringRequestId('viewer-get-draft'),
            subject: fixture.subject,
            draftId: draft.id,
          ),
        ),
        throwsA(_serviceError(ExperienceAuthoringErrorCode.policyDenied)),
      );
    });

    test(
      'unsupported source gates every journal query before historical disclosure',
      () {
        final store = fixture.store(workspace);
        final service = fixture.service(store: store, resolver: resolver);
        final opened = fixture.openThrough(
          service,
          connection: 'unsupported-query',
        );
        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: 'unsupported-query-move',
          connection: 'unsupported-query',
          toX: 250,
        );
        final prepared = fixture.prepareThrough(
          service,
          draft: moved,
          requestStem: 'unsupported-query-review',
          connection: 'unsupported-query',
        );
        final before = File(store.stateFilePath).readAsBytesSync();
        resolver.snapshot = fixture.snapshotWith(sourceDigest: null);

        final probes = <void Function()>[
          () => service.getSubjectHead(
            ExperienceAuthoringSubjectHeadRequest(
              requestId: AuthoringRequestId('unsupported-head'),
              subject: fixture.subject,
            ),
          ),
          () => service.getDraft(
            LayoutDraftGetRequest(
              requestId: AuthoringRequestId('unsupported-draft'),
              subject: fixture.subject,
              draftId: moved.id,
            ),
          ),
          () => service.getChangeSet(
            ExperienceChangeSetGetRequest(
              requestId: AuthoringRequestId('unsupported-changeset'),
              subject: fixture.subject,
              changeSetId: prepared.changeSet.id,
              expectedChangeSetDigest: prepared.changeSet.digest,
            ),
          ),
          () => service.getReview(
            ExperienceReviewGetRequest(
              requestId: AuthoringRequestId('unsupported-review'),
              subject: fixture.subject,
              reviewPacketId: prepared.reviewPacket.id,
              expectedReviewPacketDigest: prepared.reviewPacket.digest,
            ),
          ),
          () => service.getPromotion(
            ExperiencePromotionGetRequest(
              requestId: AuthoringRequestId('unsupported-promotion'),
              subject: fixture.subject,
              receiptId: ExperiencePromotionReceiptId('unknown-receipt'),
            ),
          ),
          () => service.getPromotionHistory(
            ExperiencePromotionHistoryRequest(
              requestId: AuthoringRequestId('unsupported-history'),
              subject: fixture.subject,
              offset: 0,
              limit: 16,
            ),
          ),
        ];
        for (final probe in probes) {
          expect(
            probe,
            throwsA(
              _serviceError(ExperienceAuthoringErrorCode.capabilityUnavailable),
            ),
          );
        }
        expect(File(store.stateFilePath).readAsBytesSync(), before);
      },
    );

    test(
      'promotion atomically closes head and records effect time with exact replay',
      () {
        final store = fixture.store(workspace);
        var effectTime = fixture.now;
        final executor = _AtomicTestPromotionExecutor(
          store: store,
          originalSourceBytes: fixture.sourceBytes,
        );
        var service = fixture.service(
          store: store,
          resolver: resolver,
          promotionExecutor: executor,
          clock: () => effectTime,
        );
        final opened = fixture.openThrough(
          service,
          connection: 'promotion-connection',
        );
        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: 'promotion-move',
          connection: 'promotion-connection',
          toX: 250,
        );
        final prepared = fixture.prepareThrough(
          service,
          draft: moved,
          requestStem: 'promotion-review',
          connection: 'promotion-connection',
        );
        final accepted = fixture.acceptThrough(
          service,
          prepared: prepared,
          requestStem: 'promotion-accept',
          connection: 'promotion-connection',
        );
        final approved = fixture.decideThrough(
          service,
          changeSet: prepared.changeSet,
          packet: accepted.reviewPacket,
          requestStem: 'promotion-approve',
          connection: 'promotion-connection',
          decision: ExperienceHumanDecision.approve,
        );
        final intent = fixture.promotionIntent(
          draft: moved,
          changeSet: prepared.changeSet,
          packet: approved.reviewPacket,
          requestId: 'promotion-grant-effect-time',
        );
        final grant = service.requestPromotionGrant(
          intent,
          connectionEpoch: 'promotion-connection',
        );
        effectTime = fixture.now.add(const Duration(seconds: 30));
        final request = ExperiencePromotionApplyRequest(
          requestId: AuthoringRequestId('promotion-apply-effect-time'),
          subject: fixture.subject,
          draftId: intent.draftId,
          draftDigest: intent.draftDigest,
          draftRevision: intent.draftRevision,
          changeSetId: intent.changeSetId,
          changeSetDigest: intent.changeSetDigest,
          reviewPacketId: intent.reviewPacketId,
          reviewPacketDigest: intent.reviewPacketDigest,
          expectedSourceDigest: intent.expectedSourceDigest,
          expectedContentSetDigest: intent.expectedContentSetDigest,
          candidateLayoutDigest: intent.candidateLayoutDigest,
          grantId: grant.grant.id,
          grantDigest: grant.grant.digest,
        );

        final applied = service.applyPromotionWithCommitState(
          request,
          connectionEpoch: 'promotion-connection',
        );
        final result = applied.result;

        expect(applied.durableCommitCreated, isTrue);
        expect(result.receipt.promotedAt, effectTime);
        expect(store.findAttempt(request.requestId)!.completedAt, effectTime);
        expect(store.findDraft(fixture.subject), isNull);
        expect(
          store.findGrant(grant.grant.id)!.state,
          StoredAuthoringGrantState.consumed,
        );
        expect(
          store.subjectHead(fixture.subject).latestPromotion!.digest,
          result.receipt.digest,
        );

        service = fixture.service(
          store: fixture.store(workspace),
          resolver: resolver,
          promotionExecutor: executor,
          clock: () => effectTime.add(const Duration(minutes: 1)),
        );
        final replay = service.applyPromotionWithCommitState(
          request,
          connectionEpoch: 'different-replay-connection',
        );
        expect(replay.durableCommitCreated, isFalse);
        expect(replay.result.toJson(), result.toJson());
      },
    );

    test(
      'specialized grant retries replay before changed heads and reconnect checks',
      () {
        final writer = _PersistThenErrorWriter();
        final store = fixture.store(workspace, writer: writer);
        final service = fixture.service(store: store, resolver: resolver);
        final opened = fixture.openThrough(
          service,
          connection: 'specialized-replay',
        );
        final moved = fixture.moveThrough(
          service,
          draft: opened,
          requestStem: 'specialized-move',
          connection: 'specialized-replay',
          toX: 250,
        );
        final prepared = fixture.prepareThrough(
          service,
          draft: moved,
          requestStem: 'specialized-review',
          connection: 'specialized-replay',
        );
        final accepted = fixture.acceptThrough(
          service,
          prepared: prepared,
          requestStem: 'specialized-accept',
          connection: 'specialized-replay',
        );
        final decisionInput = AppendExperienceHumanDecisionInput(
          decision: ExperienceHumanDecision.approve,
          rationale: 'Exact specialized grant replay.',
        );
        final decisionIntent = ExperienceReviewDecisionGrantRequest(
          requestId: AuthoringRequestId('specialized-decision-grant'),
          capabilityDigest: fixture.capability.digest,
          fence: fixture.reviewFence(prepared.changeSet, accepted.reviewPacket),
          decision: decisionInput,
          automatedAcceptanceDigest:
              accepted.reviewPacket.automatedAcceptance!.digest,
        );
        writer.throwAfterNextPersist = true;
        final decisionGrant = service.requestDecisionGrant(
          decisionIntent,
          connectionEpoch: 'specialized-replay',
        );
        final commented = fixture.commentThrough(
          service,
          changeSet: prepared.changeSet,
          packet: accepted.reviewPacket,
          requestStem: 'specialized-comment',
          connection: 'specialized-replay',
        );
        final decisionReplay = service.requestDecisionGrant(
          decisionIntent,
          connectionEpoch: 'different-specialized-connection',
        );
        expect(decisionReplay.toJson(), decisionGrant.toJson());
        expect(
          store.findGrant(decisionGrant.grant.id)!.state,
          StoredAuthoringGrantState.revoked,
        );

        final approved = fixture.decideThrough(
          service,
          changeSet: prepared.changeSet,
          packet: commented.reviewPacket,
          requestStem: 'specialized-approve',
          connection: 'specialized-replay',
          decision: ExperienceHumanDecision.approve,
        );
        final promotionIntent = fixture.promotionIntent(
          draft: moved,
          changeSet: prepared.changeSet,
          packet: approved.reviewPacket,
          requestId: 'specialized-promotion-grant',
        );
        writer.throwAfterNextPersist = true;
        final promotionGrant = service.requestPromotionGrant(
          promotionIntent,
          connectionEpoch: 'specialized-replay',
        );
        fixture.commentThrough(
          service,
          changeSet: prepared.changeSet,
          packet: approved.reviewPacket,
          requestStem: 'specialized-comment-after-promotion',
          connection: 'specialized-replay',
        );
        final promotionReplay = service.requestPromotionGrant(
          promotionIntent,
          connectionEpoch: 'another-specialized-connection',
        );
        expect(promotionReplay.toJson(), promotionGrant.toJson());
        expect(
          store.findGrant(promotionGrant.grant.id)!.state,
          StoredAuthoringGrantState.revoked,
        );
      },
    );

    test('all durable grant intent codecs round-trip across restart', () {
      final store = fixture.store(workspace);
      final service = fixture.service(store: store, resolver: resolver);
      final genericIntent = fixture.openIntent(
        requestId: 'codec-generic-grant',
        payloadDigest: fixture.openPayload,
      );
      final genericGrant = service.requestGrant(
        genericIntent,
        connectionEpoch: 'codec-connection',
      );
      final opened = service
          .openDraft(
            fixture.openEffect(
              requestId: 'codec-open-effect',
              grant: genericGrant.grant,
            ),
            connectionEpoch: 'codec-connection',
          )
          .draft;
      final moved = fixture.moveThrough(
        service,
        draft: opened,
        requestStem: 'codec-move',
        connection: 'codec-connection',
        toX: 250,
      );
      final prepared = fixture.prepareThrough(
        service,
        draft: moved,
        requestStem: 'codec-review',
        connection: 'codec-connection',
      );
      final accepted = fixture.acceptThrough(
        service,
        prepared: prepared,
        requestStem: 'codec-accept',
        connection: 'codec-connection',
      );
      final decisionIntent = ExperienceReviewDecisionGrantRequest(
        requestId: AuthoringRequestId('codec-decision-grant'),
        capabilityDigest: fixture.capability.digest,
        fence: fixture.reviewFence(prepared.changeSet, accepted.reviewPacket),
        decision: AppendExperienceHumanDecisionInput(
          decision: ExperienceHumanDecision.approve,
          rationale: 'Exercise the stable decision grant codec.',
        ),
        automatedAcceptanceDigest:
            accepted.reviewPacket.automatedAcceptance!.digest,
      );
      final decisionGrant = service.requestDecisionGrant(
        decisionIntent,
        connectionEpoch: 'codec-connection',
      );
      final approved = fixture.decideThrough(
        service,
        changeSet: prepared.changeSet,
        packet: accepted.reviewPacket,
        requestStem: 'codec-approve',
        connection: 'codec-connection',
        decision: ExperienceHumanDecision.approve,
      );
      final promotionIntent = fixture.promotionIntent(
        draft: moved,
        changeSet: prepared.changeSet,
        packet: approved.reviewPacket,
        requestId: 'codec-promotion-grant',
      );
      final promotionGrant = service.requestPromotionGrant(
        promotionIntent,
        connectionEpoch: 'codec-connection',
      );

      final restarted = fixture.store(workspace);
      final decodedGeneric = restarted.grantIntent(
        restarted.findGrant(genericGrant.grant.id)!,
      );
      final decodedDecision = restarted.grantIntent(
        restarted.findGrant(decisionGrant.grant.id)!,
      );
      final decodedPromotion = restarted.grantIntent(
        restarted.findGrant(promotionGrant.grant.id)!,
      );

      expect(decodedGeneric, isA<AuthoringGrantRequest>());
      expect(decodedGeneric.digest, genericIntent.digest);
      expect(decodedDecision, isA<ExperienceReviewDecisionGrantRequest>());
      expect(decodedDecision.digest, decisionIntent.digest);
      expect(decodedPromotion, isA<ExperiencePromotionGrantRequest>());
      expect(decodedPromotion.digest, promotionIntent.digest);
      expect(
        () => decodeStoredAuthoringGrantIntent(
          'RefactorDependentRuntimeType',
          storedAuthoringGrantIntentJson(genericIntent),
        ),
        throwsFormatException,
      );
    });

    test(
      'artifact authority binds the exact ReviewGuide execution binding',
      () {
        final binding = fixture.snapshot.reviewBinding(
          guideId: ReviewGuideId('delivery-review'),
          stepId: 'ready-step',
        );
        final exactDigest = _d('exact-binding-artifact');
        final exact = ExperienceAuthoringWorkspaceSnapshot(
          subject: fixture.subject,
          catalog: fixture.catalog,
          topology: fixture.topology,
          layout: fixture.layout,
          contentSetDigest: fixture.contentSetDigest,
          sourceDigest: fixture.sourceDigest,
          scenarioLabManifest: _artifactManifest(
            fixture.catalog,
            bindingId: binding.bindingId,
            artifactDigest: exactDigest,
          ),
        );
        expect(exact.allowedArtifactDigests(binding), <Digest>{exactDigest});

        final decoy = ExperienceAuthoringWorkspaceSnapshot(
          subject: fixture.subject,
          catalog: fixture.catalog,
          topology: fixture.topology,
          layout: fixture.layout,
          contentSetDigest: fixture.contentSetDigest,
          sourceDigest: fixture.sourceDigest,
          scenarioLabManifest: _artifactManifest(
            fixture.catalog,
            bindingId: ScenarioExecutionBindingId('ready-decoy'),
            artifactDigest: _d('decoy-binding-artifact'),
          ),
        );
        expect(() => decoy.allowedArtifactDigests(binding), throwsStateError);
      },
    );

    test('unknown resolver failures are typed without path disclosure', () {
      final store = fixture.store(workspace);
      Object? diagnostic;
      final service = fixture.service(
        store: store,
        resolver: const _ThrowingResolver(),
        diagnosticSink: (error, _) => diagnostic = error,
      );
      final unknown = AuthoringSubjectRef(
        workspaceId: WorkspaceId('unknown-workspace'),
        applicationId: ApplicationId('unknown-app'),
        projectionId: ExperienceProjectionId('unknown-projection'),
      );

      for (final invoke in <void Function()>[
        () => service.describe(
          ExperienceAuthoringDescribeRequest(
            requestId: AuthoringRequestId('unknown-describe'),
            subject: unknown,
          ),
        ),
        () => service.getSubjectHead(
          ExperienceAuthoringSubjectHeadRequest(
            requestId: AuthoringRequestId('unknown-head'),
            subject: unknown,
          ),
        ),
        () => service.requestGrant(
          AuthoringGrantRequest(
            requestId: AuthoringRequestId('unknown-grant'),
            capabilityDigest: fixture.capability.digest,
            subject: unknown,
            effect: AuthoringActionEffect.authoring,
            operation: AuthoringOperation.openDraft,
            expectedDigest: fixture.contentSetDigest,
            expectedSourceDigest: fixture.sourceDigest,
            payloadDigest: fixture.openPayload,
          ),
          connectionEpoch: 'unknown-connection',
        ),
      ]) {
        try {
          invoke();
          fail('unknown resolver call unexpectedly succeeded');
        } on ExperienceAuthoringServiceException catch (failure) {
          expect(
            failure.error.code,
            ExperienceAuthoringErrorCode.capabilityUnavailable,
          );
          final wire = jsonEncode(failure.error.toJson());
          expect(wire, isNot(contains('resolver-canary')));
          expect(wire, isNot(contains('/private/authoring')));
          expect(wire.length, lessThan(experienceAuthoringMaxFrameBytes));
        }
      }
      expect(diagnostic.toString(), contains('resolver-canary'));
      expect(File(store.stateFilePath).existsSync(), isFalse);
    });
  });
}

Matcher _serviceError(ExperienceAuthoringErrorCode code) =>
    isA<ExperienceAuthoringServiceException>().having(
      (error) => error.error.code,
      'code',
      code,
    );

final class _MutableResolver implements ExperienceAuthoringWorkspaceResolver {
  _MutableResolver(this.snapshot);

  ExperienceAuthoringWorkspaceSnapshot snapshot;

  @override
  ExperienceAuthoringWorkspaceSnapshot resolve(AuthoringSubjectRef subject) {
    if (subject != snapshot.subject) throw StateError('unknown subject');
    return snapshot;
  }
}

final class _ThrowingResolver implements ExperienceAuthoringWorkspaceResolver {
  const _ThrowingResolver();

  @override
  ExperienceAuthoringWorkspaceSnapshot resolve(AuthoringSubjectRef subject) {
    throw const FileSystemException(
      'resolver-canary',
      '/private/authoring/source.yaml',
    );
  }
}

final class _UnsupportedStateWriter implements ExperienceAuthoringStateWriter {
  const _UnsupportedStateWriter();

  @override
  bool get isDurabilitySupported => false;

  @override
  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  }) => throw const ExperienceAuthoringStateDurabilityFailure.unsupported();

  @override
  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
  }) => throw const ExperienceAuthoringStateDurabilityFailure.unsupported();
}

final class _DestinationFsyncFault {
  bool didFail = false;

  void call(ExperienceAuthoringStateFsyncTarget target) {
    if (!didFail &&
        target == ExperienceAuthoringStateFsyncTarget.destinationParent) {
      didFail = true;
      throw StateError('injected authoring directory fsync failure');
    }
  }
}

final class _PersistThenErrorWriter implements ExperienceAuthoringStateWriter {
  bool throwAfterNextPersist = false;

  @override
  bool get isDurabilitySupported =>
      const DefaultExperienceAuthoringStateWriter().isDurabilitySupported;

  @override
  ExperienceAuthoringDurableWriteReceipt write({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
    List<int>? expectedCurrentBytes,
  }) {
    final receipt = const DefaultExperienceAuthoringStateWriter().write(
      workspaceStore: workspaceStore,
      relativePath: relativePath,
      bytes: bytes,
      expectedCurrentBytes: expectedCurrentBytes,
    );
    if (throwAfterNextPersist &&
        relativePath == FilesystemExperienceAuthoringStore.statePath) {
      throwAfterNextPersist = false;
      throw StateError('persisted authoring state before injected error');
    }
    return receipt;
  }

  @override
  ExperienceAuthoringDurableWriteReceipt reproveExisting({
    required FileSystemWorkspaceStore workspaceStore,
    required String relativePath,
    required List<int> bytes,
  }) => const DefaultExperienceAuthoringStateWriter().reproveExisting(
    workspaceStore: workspaceStore,
    relativePath: relativePath,
    bytes: bytes,
  );
}

final class _AtomicTestPromotionExecutor
    implements ExperienceAuthoringPromotionExecutor {
  const _AtomicTestPromotionExecutor({
    required this.store,
    required this.originalSourceBytes,
  });

  final FilesystemExperienceAuthoringStore store;
  final List<int> originalSourceBytes;

  @override
  ExperiencePromotionReceipt promote({
    required ExperiencePromotionApplyRequest request,
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket reviewPacket,
    required Set<Digest> allowedArtifactDigests,
    required DateTime promotedAt,
    required StoredAuthoringAttempt Function(ExperiencePromotionReceipt receipt)
    successAttemptFactory,
    required StoredAuthoringAttempt rollbackAttempt,
  }) {
    final candidateBytes = utf8.encode('fixture-promoted-source-v2\n');
    final previous = store.promotionHistory(request.subject).lastOrNull;
    final receipt = ExperiencePromotionReceipt(
      id: ExperiencePromotionReceiptId('receipt-${request.requestId.value}'),
      sequence: (previous?.sequence ?? 0) + 1,
      previousReceiptDigest: previous?.digest,
      subject: request.subject,
      draftId: request.draftId,
      draftDigest: request.draftDigest,
      draftRevision: request.draftRevision,
      sourceDigest: Digest.bytes(originalSourceBytes),
      resultSourceDigest: Digest.bytes(candidateBytes),
      previousContentSetDigest: request.expectedContentSetDigest,
      resultContentSetDigest: Digest.semantic(<String, Object?>{
        'promotedFrom': request.expectedContentSetDigest.value,
      }),
      layoutDigest: request.candidateLayoutDigest,
      changeSetId: changeSet.id,
      changeSetDigest: changeSet.digest,
      reviewPacketId: reviewPacket.id,
      reviewPacketDigest: reviewPacket.digest,
      promotedAt: promotedAt,
    );
    final success = successAttemptFactory(receipt);
    final pending = StoredProjectionLayoutPromotion(
      intentId: 'intent-${request.requestId.value}',
      subject: request.subject,
      relativeSourcePath: 'layout.json',
      replaceProtocol: projectionLayoutPreservingSwapProtocol,
      replaceProviderKind: projectionLayoutLinuxX64SwapProvider,
      recoverySlot: const FilesystemProjectionLayoutAtomicFileWriter()
          .recoverySlot(
            subject: request.subject,
            relativeSourcePath: 'layout.json',
          ),
      configurationAuthorityDigest: Digest.semantic(
        'fixture-promotion-configuration-authority',
      ),
      sourceMetadataDigest: Digest.semantic(
        'fixture-promotion-source-metadata',
      ),
      originalSourceBlobDigest: receipt.sourceDigest,
      candidateSourceBlobDigest: receipt.resultSourceDigest,
      originalCompiledCorpusDigest: Digest.semantic('fixture-compiled-base'),
      candidateCompiledCorpusDigest: Digest.semantic(
        'fixture-compiled-candidate',
      ),
      receipt: receipt,
      grantDigest: request.grantDigest,
      successAttempt: success,
      rollbackAttempt: rollbackAttempt,
      preparedAt: promotedAt,
    );
    store.preparePromotion(
      promotion: pending,
      originalSourceBytes: originalSourceBytes,
      candidateSourceBytes: candidateBytes,
    );
    store.finalizePromotionEffect(
      intentId: pending.intentId,
      outcome: StoredPromotionFinalization.committed,
    );
    return receipt;
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
          nodeInstanceId: NodeInstanceId('ready-node'),
          x: 300,
          y: 200,
          width: 200,
          height: 120,
        ),
      ],
      groups: const <ProjectionGroup>[],
      lanes: const <ProjectionLane>[],
      annotations: const <ProjectionAnnotation>[],
      camera: ProjectionCamera(x: 0, y: 0, zoom: 1),
    );
    snapshot = ExperienceAuthoringWorkspaceSnapshot(
      subject: subject,
      catalog: catalog,
      topology: topology,
      layout: layout,
      contentSetDigest: contentSetDigest,
      sourceDigest: sourceDigest,
    );
  }

  final DateTime now = DateTime.utc(2026, 8, 17, 12);
  final Digest planDigest = _d('resolved-plan');
  final List<int> sourceBytes = utf8.encode('fixture-projection-source-v2\n');
  late final Digest sourceDigest = Digest.bytes(sourceBytes);
  final Digest contentSetDigest = _d('content-set');
  final AuthoringSubjectRef subject = AuthoringSubjectRef(
    workspaceId: WorkspaceId('workspace'),
    applicationId: ApplicationId('app'),
    projectionId: ExperienceProjectionId('journey'),
  );
  late final CatalogManifest catalog;
  late final ExperienceTopologyManifest topology;
  late final ProjectionLayoutManifest layout;
  late final ExperienceAuthoringWorkspaceSnapshot snapshot;

  Digest get openPayload => Digest.semantic(<String, Object?>{
    'subject': subject.toJson(),
    'expectedContentSetDigest': contentSetDigest.value,
    'expectedSourceDigest': sourceDigest.value,
  });

  ExperienceAuthoringWorkspaceSnapshot snapshotWith({
    required Digest? sourceDigest,
  }) => ExperienceAuthoringWorkspaceSnapshot(
    subject: subject,
    catalog: catalog,
    topology: topology,
    layout: layout,
    contentSetDigest: contentSetDigest,
    sourceDigest: sourceDigest,
  );

  FilesystemExperienceAuthoringStore store(
    Directory workspace, {
    ExperienceAuthoringStateWriter writer =
        const DefaultExperienceAuthoringStateWriter(),
  }) => FilesystemExperienceAuthoringStore(
    workspaceStore: FileSystemWorkspaceStore(workspaceRoot: workspace.path),
    writer: writer,
  );

  ExperienceAuthoringService service({
    required FilesystemExperienceAuthoringStore store,
    required ExperienceAuthoringWorkspaceResolver resolver,
    ExperienceAuthoringAuthoritySettings? settings,
    ExperienceAuthoringPromotionExecutor? promotionExecutor,
    ExperienceAuthoringClock? clock,
    ExperienceAuthoringDiagnosticSink? diagnosticSink,
  }) => ExperienceAuthoringService(
    store: store,
    workspaceResolver: resolver,
    moduleSupport: ExperienceAuthoringModuleSupport(
      resolvedPlanDigest: planDigest,
      active: true,
      healthy: true,
    ),
    settings: settings ?? authorSettings,
    clock: clock ?? () => now,
    promotionExecutor: promotionExecutor,
    diagnosticSink: diagnosticSink,
  );

  ExperienceAuthoringAuthoritySettings get authorSettings =>
      ExperienceAuthoringAuthoritySettings.fromJson(<String, Object?>{
        'authorityId': 'local-authority',
        'accessPolicyId': 'local-policy',
        'principalId': 'local-author',
        'allowedOperations': <Object?>[
          for (final operation in AuthoringOperation.values)
            if (authoringEffectFor(operation) != AuthoringActionEffect.query)
              operation.name,
        ],
        'grantTtlSeconds': 120,
      });

  AuthoringCapability get capability => ExperienceAuthoringModuleSupport(
    resolvedPlanDigest: planDigest,
    active: true,
    healthy: true,
  ).capabilityFor(subject)!;

  AuthoringGrantRequest openIntent({
    required String requestId,
    required Digest payloadDigest,
  }) => AuthoringGrantRequest(
    requestId: AuthoringRequestId(requestId),
    capabilityDigest: capability.digest,
    subject: subject,
    effect: AuthoringActionEffect.authoring,
    operation: AuthoringOperation.openDraft,
    expectedDigest: contentSetDigest,
    expectedSourceDigest: sourceDigest,
    payloadDigest: payloadDigest,
  );

  LayoutDraftOpenRequest openEffect({
    required String requestId,
    required AuthoringActionGrant grant,
  }) => LayoutDraftOpenRequest(
    requestId: AuthoringRequestId(requestId),
    subject: subject,
    expectedContentSetDigest: contentSetDigest,
    expectedSourceDigest: sourceDigest,
    grantId: grant.id,
    grantDigest: grant.digest,
  );

  LayoutDraft openThrough(
    ExperienceAuthoringService service, {
    required String connection,
  }) {
    final template = LayoutDraftOpenRequest(
      requestId: AuthoringRequestId('template-${connection.hashCode.abs()}'),
      subject: subject,
      expectedContentSetDigest: contentSetDigest,
      expectedSourceDigest: sourceDigest,
      grantId: AuthoringActionGrantId('template-grant'),
      grantDigest: _d('template-grant'),
    );
    final grant = service.requestGrant(
      openIntent(
        requestId: 'grant-${connection.hashCode.abs()}',
        payloadDigest: template.payloadDigest,
      ),
      connectionEpoch: connection,
    );
    return service
        .openDraft(
          openEffect(
            requestId: 'effect-${connection.hashCode.abs()}',
            grant: grant.grant,
          ),
          connectionEpoch: connection,
        )
        .draft;
  }

  LayoutDraftMutationRequest moveEffectTemplate({
    required String requestId,
    required LayoutDraft draft,
    required double toX,
    double toY = 200,
  }) => LayoutDraftMutationRequest(
    requestId: AuthoringRequestId(requestId),
    draftId: draft.id,
    expectedDraftDigest: draft.digest,
    expectedDraftRevision: draft.revision,
    grantId: AuthoringActionGrantId('template-$requestId'),
    grantDigest: _d('template-$requestId'),
    mutation: LayoutDraftMutation.applyMove,
    move: LayoutMoveNodeInput(
      nodeInstanceId: NodeInstanceId('ready-node'),
      toX: toX,
      toY: toY,
    ),
  );

  AuthoringGrantRequest mutationIntent({
    required String requestId,
    required LayoutDraft draft,
    required Digest payloadDigest,
  }) => AuthoringGrantRequest(
    requestId: AuthoringRequestId(requestId),
    capabilityDigest: capability.digest,
    subject: subject,
    effect: AuthoringActionEffect.authoring,
    operation: AuthoringOperation.moveNode,
    expectedDigest: draft.digest,
    expectedSourceDigest: draft.baseSourceDigest,
    payloadDigest: payloadDigest,
  );

  LayoutDraftMutationRequest withMutationGrant(
    LayoutDraftMutationRequest template,
    AuthoringActionGrant grant,
  ) => LayoutDraftMutationRequest(
    requestId: template.requestId,
    draftId: template.draftId,
    expectedDraftDigest: template.expectedDraftDigest,
    expectedDraftRevision: template.expectedDraftRevision,
    grantId: grant.id,
    grantDigest: grant.digest,
    mutation: template.mutation,
    move: template.move,
  );

  LayoutDraft moveThrough(
    ExperienceAuthoringService service, {
    required LayoutDraft draft,
    required String requestStem,
    required String connection,
    required double toX,
    double toY = 200,
    void Function()? beforeEffect,
  }) {
    final template = moveEffectTemplate(
      requestId: '$requestStem-effect',
      draft: draft,
      toX: toX,
      toY: toY,
    );
    final grant = service.requestGrant(
      mutationIntent(
        requestId: '$requestStem-grant',
        draft: draft,
        payloadDigest: template.payloadDigest,
      ),
      connectionEpoch: connection,
    );
    beforeEffect?.call();
    return service
        .mutateDraft(
          withMutationGrant(template, grant.grant),
          connectionEpoch: connection,
        )
        .draft;
  }

  ExperienceReviewPrepareResult prepareThrough(
    ExperienceAuthoringService service, {
    required LayoutDraft draft,
    required String requestStem,
    required String connection,
    void Function()? beforeEffect,
  }) {
    final template = ExperienceReviewPrepareRequest(
      requestId: AuthoringRequestId('$requestStem-effect'),
      subject: subject,
      draftId: draft.id,
      expectedDraftDigest: draft.digest,
      expectedDraftRevision: draft.revision,
      expectedContentSetDigest: draft.contentSetDigest,
      expectedSourceDigest: draft.baseSourceDigest,
      reviewGuideId: ReviewGuideId('delivery-review'),
      reviewGuideStepId: 'ready-step',
      grantId: AuthoringActionGrantId('$requestStem-template'),
      grantDigest: _d('$requestStem-template'),
    );
    final grant = service.requestGrant(
      AuthoringGrantRequest(
        requestId: AuthoringRequestId('$requestStem-grant'),
        capabilityDigest: capability.digest,
        subject: subject,
        effect: AuthoringActionEffect.authoring,
        operation: AuthoringOperation.prepareReview,
        expectedDigest: draft.digest,
        expectedSourceDigest: draft.baseSourceDigest,
        payloadDigest: template.payloadDigest,
      ),
      connectionEpoch: connection,
    );
    beforeEffect?.call();
    return service.prepareReview(
      ExperienceReviewPrepareRequest(
        requestId: template.requestId,
        subject: template.subject,
        draftId: template.draftId,
        expectedDraftDigest: template.expectedDraftDigest,
        expectedDraftRevision: template.expectedDraftRevision,
        expectedContentSetDigest: template.expectedContentSetDigest,
        expectedSourceDigest: template.expectedSourceDigest,
        reviewGuideId: template.reviewGuideId,
        reviewGuideStepId: template.reviewGuideStepId,
        grantId: grant.grant.id,
        grantDigest: grant.grant.digest,
      ),
      connectionEpoch: connection,
    );
  }

  ExperienceReviewActionResult acceptThrough(
    ExperienceAuthoringService service, {
    required ExperienceReviewPrepareResult prepared,
    required String requestStem,
    required String connection,
    void Function()? beforeEffect,
  }) {
    final fence = _fence(prepared.changeSet, prepared.reviewPacket);
    final template = ExperienceReviewActionRequest(
      requestId: AuthoringRequestId('$requestStem-effect'),
      fence: fence,
      operation: AuthoringOperation.evaluateAutomatedAcceptance,
      grantId: AuthoringActionGrantId('$requestStem-template'),
      grantDigest: _d('$requestStem-template'),
    );
    final grant = service.requestGrant(
      _reviewGrantIntent(
        requestId: '$requestStem-grant',
        fence: fence,
        operation: template.operation,
        payloadDigest: template.payloadDigest,
      ),
      connectionEpoch: connection,
    );
    beforeEffect?.call();
    return service.reviewAction(
      ExperienceReviewActionRequest(
        requestId: template.requestId,
        fence: fence,
        operation: template.operation,
        grantId: grant.grant.id,
        grantDigest: grant.grant.digest,
      ),
      connectionEpoch: connection,
    );
  }

  ExperienceReviewActionResult commentThrough(
    ExperienceAuthoringService service, {
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket packet,
    required String requestStem,
    required String connection,
    String body = 'The current review head needs one more explicit note.',
  }) {
    final fence = _fence(changeSet, packet);
    final input = AppendExperienceReviewCommentInput(
      subject: ExperienceReviewSubject.scenario(
        packet.reviewGuideBinding.scenarioId,
      ),
      body: body,
    );
    final template = ExperienceReviewActionRequest(
      requestId: AuthoringRequestId('$requestStem-effect'),
      fence: fence,
      operation: AuthoringOperation.appendComment,
      comment: input,
      grantId: AuthoringActionGrantId('$requestStem-template'),
      grantDigest: _d('$requestStem-template'),
    );
    final grant = service.requestGrant(
      _reviewGrantIntent(
        requestId: '$requestStem-grant',
        fence: fence,
        operation: template.operation,
        payloadDigest: template.payloadDigest,
      ),
      connectionEpoch: connection,
    );
    return service.reviewAction(
      ExperienceReviewActionRequest(
        requestId: template.requestId,
        fence: fence,
        operation: template.operation,
        comment: input,
        grantId: grant.grant.id,
        grantDigest: grant.grant.digest,
      ),
      connectionEpoch: connection,
    );
  }

  ExperienceReviewActionResult decideThrough(
    ExperienceAuthoringService service, {
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket packet,
    required String requestStem,
    required String connection,
    required ExperienceHumanDecision decision,
  }) {
    final acceptance = packet.automatedAcceptance!;
    final fence = _fence(changeSet, packet);
    final input = AppendExperienceHumanDecisionInput(
      decision: decision,
      rationale: 'Decision bound to the exact current review packet.',
    );
    final grant = service.requestDecisionGrant(
      ExperienceReviewDecisionGrantRequest(
        requestId: AuthoringRequestId('$requestStem-grant'),
        capabilityDigest: capability.digest,
        fence: fence,
        decision: input,
        automatedAcceptanceDigest: acceptance.digest,
      ),
      connectionEpoch: connection,
    );
    return service.reviewAction(
      ExperienceReviewActionRequest(
        requestId: AuthoringRequestId('$requestStem-effect'),
        fence: fence,
        operation: AuthoringOperation.decideReview,
        decision: input,
        expectedAutomatedAcceptanceDigest: acceptance.digest,
        grantId: grant.grant.id,
        grantDigest: grant.grant.digest,
      ),
      connectionEpoch: connection,
    );
  }

  AuthoringGrantRequest _reviewGrantIntent({
    required String requestId,
    required ExperienceReviewMutationFence fence,
    required AuthoringOperation operation,
    required Digest payloadDigest,
  }) => AuthoringGrantRequest(
    requestId: AuthoringRequestId(requestId),
    capabilityDigest: capability.digest,
    subject: subject,
    effect: authoringEffectFor(operation),
    operation: operation,
    expectedDigest: fence.reviewPacketDigest,
    expectedSourceDigest: fence.expectedSourceDigest,
    payloadDigest: payloadDigest,
  );

  ExperienceReviewMutationFence _fence(
    ExperienceChangeSet changeSet,
    ExperienceReviewPacket packet,
  ) => ExperienceReviewMutationFence(
    subject: subject,
    changeSetId: changeSet.id,
    changeSetDigest: changeSet.digest,
    reviewPacketId: packet.id,
    reviewPacketDigest: packet.digest,
    reviewPacketRevision: packet.revision,
    expectedSourceDigest: sourceDigest,
    expectedContentSetDigest: contentSetDigest,
  );

  ExperienceReviewMutationFence reviewFence(
    ExperienceChangeSet changeSet,
    ExperienceReviewPacket packet,
  ) => _fence(changeSet, packet);

  ExperiencePromotionGrantRequest promotionIntent({
    required LayoutDraft draft,
    required ExperienceChangeSet changeSet,
    required ExperienceReviewPacket packet,
    required String requestId,
  }) => ExperiencePromotionGrantRequest(
    requestId: AuthoringRequestId(requestId),
    capabilityDigest: capability.digest,
    subject: subject,
    draftId: draft.id,
    draftDigest: draft.digest,
    draftRevision: draft.revision,
    changeSetId: changeSet.id,
    changeSetDigest: changeSet.digest,
    reviewPacketId: packet.id,
    reviewPacketDigest: packet.digest,
    expectedSourceDigest: sourceDigest,
    expectedContentSetDigest: contentSetDigest,
    candidateLayoutDigest: draft.candidateLayoutDigest,
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
        id: ScenarioExecutionBindingId('ready-web'),
        scenarioId: ScenarioId('ready'),
        targetId: 'browser',
        launchProfileId: 'web',
      ),
      ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('ready-decoy'),
        scenarioId: ScenarioId('ready'),
        targetId: 'browser-decoy',
        launchProfileId: 'web-decoy',
      ),
    ],
    reviewGuides: <ReviewGuide>[
      ReviewGuide(
        id: ReviewGuideId('delivery-review'),
        applicationId: appId,
        title: 'Delivery review',
        steps: <ReviewGuideStep>[
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

ScenarioLabManifest _artifactManifest(
  CatalogManifest catalog, {
  required ScenarioExecutionBindingId bindingId,
  required Digest artifactDigest,
}) {
  final scenarioId = ScenarioId('ready');
  final evidenceId = RequiredEvidenceId('layout-baseline-evidence');
  final operationId = ScenarioLabOperationId('collect-layout-baseline');
  final scriptId = ScenarioScriptId('inspect-layout-baseline');
  final acceptanceId = AutomatedAcceptanceCriterionId('accept-layout-baseline');
  final comparisonId = ScenarioComparisonBindingId('compare-layout-baseline');
  final artifactId = SupplementalArtifactId('layout-baseline');
  return ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: const <CapabilityDescriptor>[],
    controls: const <ScenarioControlDefinition>[],
    operations: <ScenarioLabOperationDefinition>[
      CollectEvidenceOperationDefinition(
        id: operationId,
        scenarioId: scenarioId,
        evidenceRequirementId: evidenceId,
      ),
    ],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: scriptId,
        scenarioId: scenarioId,
        displayName: 'Inspect layout baseline',
        timeoutMs: 10000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'attach',
            timeoutMs: 5000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            bindingId: bindingId,
          ),
          OperationScenarioScriptStep(
            id: 'collect',
            timeoutMs: 5000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            operationId: operationId,
          ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
      EvidenceAcceptedAcceptanceCriterion(
        id: acceptanceId,
        scenarioId: scenarioId,
        displayName: 'Layout baseline accepted',
        evidenceRequirementId: evidenceId,
      ),
    ],
    requiredEvidence: <RequiredEvidenceDefinition>[
      RequiredEvidenceDefinition(
        id: evidenceId,
        scenarioId: scenarioId,
        providerId: ModuleId('fixture-provider'),
        fidelity: RuntimeFidelity.hostNative,
        variantId: VariantId('desktop'),
        freshness: EvidenceFreshness.fresh,
        allowedClassifications: const <ArtifactClassification>{
          ArtifactClassification.internal,
        },
        evidencePolicyId: EvidencePolicyId('fixture-evidence-policy'),
        comparisonPolicy: VisualComparisonPolicyReference(
          VisualComparisonPolicyId('fixture-visual-policy'),
        ),
      ),
    ],
    comparisonBindings: <ScenarioComparisonBinding>[
      ScenarioComparisonBinding(
        id: comparisonId,
        scenarioId: scenarioId,
        requiredEvidenceId: evidenceId,
        baseline: ArtifactComparisonInputReference(artifactId: artifactId),
        candidate: RequiredEvidenceComparisonInputReference(
          requiredEvidenceId: evidenceId,
        ),
      ),
    ],
    visualComparisonPolicies: <VisualComparisonPolicy>[
      VisualComparisonPolicy(
        id: 'fixture-visual-policy',
        maxChannelDelta: 0,
        maxChangedPixelRatio: 0,
      ),
    ],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: const <HumanApprovalRequirement>[],
    supplementalArtifacts: <SupplementalArtifactReference>[
      SupplementalArtifactReference(
        id: artifactId,
        scenarioId: scenarioId,
        requiredEvidenceId: evidenceId,
        role: SupplementalArtifactRole.comparisonBaseline,
        artifactDigest: artifactDigest,
        provenanceDigest: _d('fixture-artifact-provenance'),
        classification: ArtifactClassification.internal,
      ),
    ],
    plans: <ScenarioLabPlan>[
      ScenarioLabPlan(
        scenarioId: scenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[bindingId],
        controlIds: const <ScenarioControlId>[],
        operationIds: <ScenarioLabOperationId>[operationId],
        scriptIds: <ScenarioScriptId>[scriptId],
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

Digest _d(String value) => Digest.semantic(value);
