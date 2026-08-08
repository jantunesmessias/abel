import 'dart:convert';
import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FilesystemScenarioQualityDecisionStore', () {
    test('decision quota cannot exceed the public Quality profile', () {
      final root = Directory.systemTemp.createTempSync('quality-quota-');
      addTearDown(() => root.deleteSync(recursive: true));
      final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
      expect(
        () => FilesystemScenarioQualityDecisionStore(
          workspaceStore: workspace,
          maxDecisionsPerRun: 101,
        ),
        throwsArgumentError,
      );
    });

    test(
      'survives restart with descriptor attribution and monotonic supersession',
      () {
        final root = Directory.systemTemp.createTempSync('quality-store-');
        addTearDown(() => root.deleteSync(recursive: true));
        final fixture = _fixture();
        final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
        var store = FilesystemScenarioQualityDecisionStore(
          workspaceStore: workspace,
        );

        final firstDescriptor = _descriptor(
          fixture,
          qualityDigest: fixture.baseQuality.digest,
          seed: 'first',
        );
        final firstGrantRequest = _grantRequest(
          fixture,
          descriptor: firstDescriptor,
          qualityDigest: fixture.baseQuality.digest,
          requestId: 'grant-first',
          decision: HumanDecision.approved,
        );
        final firstIssuedAt = DateTime.utc(2026, 8, 14, 12);
        final firstGrant = _issue(
          store,
          fixture,
          request: firstGrantRequest,
          descriptor: firstDescriptor,
          now: firstIssuedAt,
          id: 'grant-first',
        );
        expect(
          _issue(
            store,
            fixture,
            request: firstGrantRequest,
            descriptor: firstDescriptor,
            now: firstIssuedAt,
            id: 'unused-replay-id',
          ).toJson(),
          firstGrant.toJson(),
        );

        final firstAppend = _appendRequest(
          fixture,
          requestId: 'append-first',
          grant: firstGrant,
        );
        final sharedDecisionInstant = DateTime.utc(2026, 8, 14, 12, 1);
        final firstResult = _append(
          store,
          fixture,
          request: firstAppend,
          descriptor: firstDescriptor,
          now: sharedDecisionInstant,
          recordId: 'decision-first',
        );
        expect(store.replayAppend(firstAppend)?.toJson(), firstResult.toJson());

        var history = store.history(
          baseQuality: fixture.baseQuality,
          result: fixture.result,
        );
        final secondDescriptor = _descriptor(
          fixture,
          qualityDigest: history.quality.digest,
          seed: 'second',
        );
        final secondGrantRequest = _grantRequest(
          fixture,
          descriptor: secondDescriptor,
          qualityDigest: history.quality.digest,
          previous: history.head!.digest,
          requestId: 'grant-second',
          decision: HumanDecision.rejected,
        );
        final secondGrant = _issue(
          store,
          fixture,
          request: secondGrantRequest,
          descriptor: secondDescriptor,
          now: sharedDecisionInstant,
          id: 'grant-second',
        );
        final secondAppend = _appendRequest(
          fixture,
          requestId: 'append-second',
          grant: secondGrant,
        );
        final secondResult = _append(
          store,
          fixture,
          request: secondAppend,
          descriptor: secondDescriptor,
          now: sharedDecisionInstant,
          recordId: 'decision-second',
        );
        expect(
          secondResult.record.decidedAt,
          firstResult.record.decidedAt.add(const Duration(microseconds: 1)),
        );

        store = FilesystemScenarioQualityDecisionStore(
          workspaceStore: FileSystemWorkspaceStore(workspaceRoot: root.path),
        );
        history = store.history(
          baseQuality: fixture.baseQuality,
          result: fixture.result,
        );
        expect(history.records, hasLength(2));
        expect(history.head?.digest, secondResult.record.digest);
        expect(
          history.view(firstResult.record.digest)?.projection.state,
          HumanDecisionState.superseded,
        );
        expect(
          history.view(firstResult.record.digest)?.reviewDescriptor.toJson(),
          firstDescriptor.toJson(),
        );
        expect(
          history.view(secondResult.record.digest)?.reviewDescriptor.toJson(),
          secondDescriptor.toJson(),
        );
        expect(
          history.view(secondResult.record.digest)?.attribution.runResultDigest,
          fixture.result.digest,
        );
        expect(
          store.replayAppend(firstAppend)?.toJson(),
          firstResult.toJson(),
          reason: 'a response-lost replay does not re-evaluate current state',
        );

        final raw = File(
          p.join(
            workspace.stateRoot,
            FilesystemScenarioQualityDecisionStore.statePath,
          ),
        ).readAsStringSync();
        expect(
          raw,
          '${const JcsCanonicalizer().canonicalize(jsonDecode(raw))}\n',
        );
        expect(raw, contains('"reviewDescriptor"'));
        expect(raw.toLowerCase(), isNot(contains('token')));
      },
    );

    test(
      'a mismatched first attempt consumes the grant durably before expiry',
      () {
        final root = Directory.systemTemp.createTempSync('quality-consume-');
        addTearDown(() => root.deleteSync(recursive: true));
        final fixture = _fixture();
        var workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
        var store = FilesystemScenarioQualityDecisionStore(
          workspaceStore: workspace,
        );
        final descriptor = _descriptor(
          fixture,
          qualityDigest: fixture.baseQuality.digest,
          seed: 'consume',
        );
        final grantRequest = _grantRequest(
          fixture,
          descriptor: descriptor,
          qualityDigest: fixture.baseQuality.digest,
          requestId: 'grant-consume',
          decision: HumanDecision.approved,
        );
        final issuedAt = DateTime.utc(2026, 8, 14, 12);
        final grant = _issue(
          store,
          fixture,
          request: grantRequest,
          descriptor: descriptor,
          now: issuedAt,
          id: 'grant-consume',
        );
        final mismatched = ScenarioQualityDecisionAppendRequest(
          requestId: ScenarioQualityDecisionRequestId('append-mismatch'),
          runId: fixture.result.finalSnapshot.runId,
          expectedRunResultDigest: fixture.result.digest,
          expectedQualityDigest: _digest('wrong-quality'),
          expectedReviewDescriptorDigest: descriptor.digest,
          grantId: grant.id,
          grantDigest: grant.digest,
          decision: grant.decision,
        );

        expect(
          () => store.prepareAppendAttempt(
            request: mismatched,
            now: issuedAt.add(const Duration(minutes: 10)),
          ),
          _storeFailure(ScenarioQualityDecisionErrorCode.grantMismatch),
        );
        expect(
          () => store.replayAppend(mismatched),
          _storeFailure(ScenarioQualityDecisionErrorCode.grantMismatch),
        );

        workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
        store = FilesystemScenarioQualityDecisionStore(
          workspaceStore: workspace,
        );
        expect(
          () => store.replayAppend(mismatched),
          _storeFailure(ScenarioQualityDecisionErrorCode.grantMismatch),
        );
        expect(
          store.revokeGrant(
            grantId: grant.id,
            revokedAt: issuedAt.add(const Duration(minutes: 11)),
          ),
          isFalse,
          reason: 'the consumed grant never becomes reusable after restart',
        );
      },
    );

    test('an oversized append response is rejected before decision commit', () {
      final root = Directory.systemTemp.createTempSync(
        'quality-frame-precommit-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final fixture = _fixture();
      var workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
      var store = FilesystemScenarioQualityDecisionStore(
        workspaceStore: workspace,
      );
      final descriptor = _descriptor(
        fixture,
        qualityDigest: fixture.baseQuality.digest,
        seed: 'frame',
      );
      final issuedAt = DateTime.utc(2026, 8, 14, 12);
      final grant = _issue(
        store,
        fixture,
        request: _grantRequest(
          fixture,
          descriptor: descriptor,
          qualityDigest: fixture.baseQuality.digest,
          requestId: 'grant-frame',
          decision: HumanDecision.approved,
        ),
        descriptor: descriptor,
        now: issuedAt,
        id: 'grant-frame',
      );
      final request = _appendRequest(
        fixture,
        requestId: 'append-frame',
        grant: grant,
      );

      expect(
        () => _append(
          store,
          fixture,
          request: request,
          descriptor: descriptor,
          now: issuedAt.add(const Duration(minutes: 1)),
          recordId: 'decision-must-not-commit',
          canReturnResult: false,
        ),
        _storeFailure(ScenarioQualityDecisionErrorCode.quotaExceeded),
      );
      expect(
        store
            .history(baseQuality: fixture.baseQuality, result: fixture.result)
            .records,
        isEmpty,
      );
      expect(
        () => store.replayAppend(request),
        _storeFailure(ScenarioQualityDecisionErrorCode.quotaExceeded),
      );

      workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
      store = FilesystemScenarioQualityDecisionStore(workspaceStore: workspace);
      expect(
        () => store.replayAppend(request),
        _storeFailure(ScenarioQualityDecisionErrorCode.quotaExceeded),
      );
      expect(
        store
            .history(baseQuality: fixture.baseQuality, result: fixture.result)
            .records,
        isEmpty,
      );
      expect(
        store.revokeGrant(
          grantId: grant.id,
          revokedAt: issuedAt.add(const Duration(minutes: 2)),
        ),
        isFalse,
        reason: 'the rejected append permanently consumes its single attempt',
      );
    });

    test('rehashing a cross-run stored descriptor still fails closed', () {
      final root = Directory.systemTemp.createTempSync('quality-tamper-');
      addTearDown(() => root.deleteSync(recursive: true));
      final fixture = _fixture();
      final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
      final store = FilesystemScenarioQualityDecisionStore(
        workspaceStore: workspace,
      );
      final descriptor = _descriptor(
        fixture,
        qualityDigest: fixture.baseQuality.digest,
        seed: 'tamper',
      );
      _issue(
        store,
        fixture,
        request: _grantRequest(
          fixture,
          descriptor: descriptor,
          qualityDigest: fixture.baseQuality.digest,
          requestId: 'grant-tamper',
          decision: HumanDecision.approved,
        ),
        descriptor: descriptor,
        now: DateTime.utc(2026, 8, 14, 12),
        id: 'grant-tamper',
      );

      final file = File(
        p.join(
          workspace.stateRoot,
          FilesystemScenarioQualityDecisionStore.statePath,
        ),
      );
      final journal =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final entries = journal['entries']! as List<Object?>;
      final entry = entries.single! as Map<String, Object?>;
      final crossRun = _descriptor(
        fixture,
        runId: ScenarioLabRunId('other-run'),
        qualityDigest: fixture.baseQuality.digest,
        seed: 'tamper',
      ).toJson();
      entry['reviewDescriptor'] = crossRun;
      entry['digest'] = Digest.semantic(
        Map<String, Object?>.of(entry)..remove('digest'),
      ).value;
      final canonical = const JcsCanonicalizer().canonicalize(journal);
      file.writeAsStringSync('$canonical\n', flush: true);

      expect(
        () => FilesystemScenarioQualityDecisionStore(
          workspaceStore: FileSystemWorkspaceStore(workspaceRoot: root.path),
        ),
        throwsFormatException,
      );
    });
  });
}

Matcher _storeFailure(ScenarioQualityDecisionErrorCode code) => throwsA(
  isA<ScenarioQualityDecisionStoreFailure>().having(
    (failure) => failure.code,
    'code',
    code,
  ),
);

ScenarioQualityDecisionGrant _issue(
  FilesystemScenarioQualityDecisionStore store,
  _RunFixture fixture, {
  required ScenarioQualityDecisionGrantRequest request,
  required ScenarioQualityReviewDescriptor descriptor,
  required DateTime now,
  required String id,
}) => store.issueGrant(
  request: request,
  baseQuality: fixture.baseQuality,
  result: fixture.result,
  reviewDescriptor: descriptor,
  now: now,
  createGrant: (quality, head) => ScenarioQualityDecisionGrant(
    id: ScenarioQualityDecisionGrantId(id),
    requestId: request.requestId,
    requestDigest: request.digest,
    authorityId: ScenarioQualityAuthorityId('local-authority'),
    accessPolicyId: ScenarioQualityAccessPolicyId('local-policy'),
    principalId: ScenarioQualityPrincipalId('reviewer-1'),
    role: ScenarioQualityDecisionRole.reviewer,
    runId: request.runId,
    runResultDigest: fixture.result.digest,
    qualityDigest: quality.digest,
    reviewDescriptorDigest: descriptor.digest,
    requirementId: descriptor.requirementId,
    requirementScope: descriptor.requirementScope,
    reviewGuideId: descriptor.reviewGuideId,
    reviewGuideStepId: descriptor.reviewGuideStepId,
    expectedPreviousDecisionDigest: head?.digest,
    decision: request.decision,
    issuedAt: now,
    expiresAt: now.add(const Duration(minutes: 2)),
  ),
);

ScenarioQualityDecisionAppendResult _append(
  FilesystemScenarioQualityDecisionStore store,
  _RunFixture fixture, {
  required ScenarioQualityDecisionAppendRequest request,
  required ScenarioQualityReviewDescriptor descriptor,
  required DateTime now,
  required String recordId,
  bool canReturnResult = true,
}) {
  store.prepareAppendAttempt(request: request, now: now);
  return store.append(
    request: request,
    baseQuality: fixture.baseQuality,
    result: fixture.result,
    reviewDescriptor: descriptor,
    preflightRejection: null,
    currentAuthorityId: ScenarioQualityAuthorityId('local-authority'),
    currentAccessPolicyId: ScenarioQualityAccessPolicyId('local-policy'),
    currentPrincipalId: ScenarioQualityPrincipalId('reviewer-1'),
    currentRole: ScenarioQualityDecisionRole.reviewer,
    decisionCurrentlyAllowed: true,
    now: now,
    createRecordId: () => HumanDecisionRecordId(recordId),
    canReturnResult: (_) => canReturnResult,
  );
}

ScenarioQualityDecisionGrantRequest _grantRequest(
  _RunFixture fixture, {
  required ScenarioQualityReviewDescriptor descriptor,
  required Digest qualityDigest,
  required String requestId,
  required HumanDecision decision,
  Digest? previous,
}) => ScenarioQualityDecisionGrantRequest(
  requestId: ScenarioQualityDecisionRequestId(requestId),
  runId: fixture.result.finalSnapshot.runId,
  expectedRunResultDigest: fixture.result.digest,
  expectedQualityDigest: qualityDigest,
  expectedReviewDescriptorDigest: descriptor.digest,
  decision: decision,
  expectedPreviousDecisionDigest: previous,
);

ScenarioQualityDecisionAppendRequest _appendRequest(
  _RunFixture fixture, {
  required String requestId,
  required ScenarioQualityDecisionGrant grant,
}) => ScenarioQualityDecisionAppendRequest(
  requestId: ScenarioQualityDecisionRequestId(requestId),
  runId: fixture.result.finalSnapshot.runId,
  expectedRunResultDigest: fixture.result.digest,
  expectedQualityDigest: grant.qualityDigest,
  expectedReviewDescriptorDigest: grant.reviewDescriptorDigest,
  grantId: grant.id,
  grantDigest: grant.digest,
  decision: grant.decision,
  expectedPreviousDecisionDigest: grant.expectedPreviousDecisionDigest,
);

ScenarioQualityReviewDescriptor _descriptor(
  _RunFixture fixture, {
  ScenarioLabRunId? runId,
  required Digest qualityDigest,
  required String seed,
}) => ScenarioQualityReviewDescriptor(
  runId: runId ?? fixture.result.finalSnapshot.runId,
  runResultDigest: fixture.result.digest,
  qualityDigest: qualityDigest,
  requirementId: HumanApprovalRequirementId('approval'),
  requirementScope: HumanApprovalScope.evidenceSet,
  reviewGuideId: ReviewGuideId('review-guide'),
  reviewGuideStepId: 'inspect-all',
  requiredEvidenceResultDigests: <Digest>[
    fixture.result.finalSnapshot.requiredEvidence.single.digest,
  ],
  comparisonResultDigests: const <Digest>[],
  artifacts: <ScenarioQualityReviewArtifactDescriptor>[
    ScenarioQualityReviewArtifactDescriptor(
      requiredEvidenceId: RequiredEvidenceId('visual'),
      requiredEvidenceResultDigest:
          fixture.result.finalSnapshot.requiredEvidence.single.digest,
      role: ScenarioQualityReviewArtifactRole.requiredEvidence,
      artifactDigest: _digest('$seed-artifact'),
      provenanceDigest: _digest('$seed-provenance'),
      provenanceKind:
          ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
      classification: ArtifactClassification.internal,
      mediaType: 'image/png',
      size: 64,
    ),
  ],
);

final class _RunFixture {
  const _RunFixture({required this.result, required this.baseQuality});

  final ScenarioLabRunResult result;
  final ScenarioQualitySnapshot baseQuality;
}

_RunFixture _fixture() {
  final evidence = RequiredEvidenceRunResult(
    requiredEvidenceId: RequiredEvidenceId('visual'),
    providerId: ModuleId('capture.app-adapter'),
    fidelity: RuntimeFidelity.hostNative,
    variantId: VariantId('phone'),
    freshness: EvidenceFreshness.fresh,
    state: RequiredEvidenceResultState.collected,
    evidenceDigest: _digest('evidence'),
    artifacts: <ScenarioEvidenceArtifactResult>[
      ScenarioEvidenceArtifactResult(
        artifactDigest: _digest('result-artifact'),
        provenanceDigest: _digest('result-provenance'),
        classification: ArtifactClassification.internal,
      ),
    ],
  );
  final snapshot = ScenarioLabRunSnapshot(
    runId: ScenarioLabRunId('run-1'),
    startRequestDigest: _digest('start-request'),
    contentSetDigest: _digest('content-set'),
    catalogDigest: _digest('catalog'),
    scenarioLabManifestDigest: _digest('lab-manifest'),
    scenarioId: ScenarioId('scenario'),
    scriptId: ScenarioScriptId('script'),
    sequence: 2,
    observedAt: DateTime.utc(2026, 8, 14, 12),
    state: ScenarioLabRunState.succeeded,
    runtimeInputs: ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest: _digest('fingerprint'),
      executionTargetId: 'browser',
    ),
    steps: <ScenarioLabStepSnapshot>[
      ScenarioLabStepSnapshot(
        stepId: 'inspect',
        state: ScenarioLabStepState.succeeded,
        startedAt: DateTime.utc(2026, 8, 14, 11, 59),
        completedAt: DateTime.utc(2026, 8, 14, 12),
        terminalCause: ScenarioLabStepTerminalCause.completed,
      ),
    ],
    requiredEvidence: <RequiredEvidenceRunResult>[evidence],
    automatedAcceptance: <AutomatedAcceptanceResult>[
      AutomatedAcceptanceResult(
        criterionId: AutomatedAcceptanceCriterionId('accepted'),
        verificationState: VerificationState.passed,
      ),
    ],
    cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.succeeded),
    terminalCause: ScenarioLabTerminalCause.completed,
  );
  final result = ScenarioLabRunResult(
    finalSnapshot: snapshot,
    startedAt: DateTime.utc(2026, 8, 14, 11, 59),
    completedAt: DateTime.utc(2026, 8, 14, 12),
    verificationState: VerificationState.passed,
  );
  final quality = ScenarioQualitySnapshot(
    subjectDigest: result.digest,
    runId: snapshot.runId,
    scenarioId: snapshot.scenarioId,
    verificationState: result.verificationState,
    humanDecision: HumanDecisionProjection(
      state: HumanDecisionState.unreviewed,
    ),
    requiredEvidence: <RequiredEvidenceVerification>[
      RequiredEvidenceVerification(
        requiredEvidenceId: evidence.requiredEvidenceId,
        resultDigest: evidence.digest,
        verificationState: VerificationState.passed,
      ),
    ],
  );
  quality.validateAgainstResult(result);
  return _RunFixture(result: result, baseQuality: quality);
}

Digest _digest(String seed) => Digest.semantic(seed);
