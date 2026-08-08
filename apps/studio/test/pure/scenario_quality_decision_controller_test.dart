import 'dart:async';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/quality/scenario_quality_decision_controller.dart';
import 'package:test/test.dart';

import '../support/scenario_quality_decision_fixture.dart';
import '../support/scenario_quality_mixed_origin_fixture.dart';

void main() {
  test(
    'approve then supersede reject is confirmed, CAS-fenced and append-only',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final controller = _controller(fixture, host);

      await controller.load();
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.ready,
      );
      expect(controller.snapshot.resources, hasLength(3));
      expect(controller.snapshot.canDecide, isFalse);
      expect(host.provenanceReadCalls, 3);
      await _renderAll(controller);
      expect(controller.snapshot.canDecide, isTrue);

      controller.requestDecision(HumanDecision.approved);
      expect(
        host.grantRequests,
        isEmpty,
        reason: 'confirmation precedes grant',
      );
      final first = controller.submitConfirmedDecision();
      final duplicate = controller.submitConfirmedDecision();
      await Future.wait(<Future<void>>[first, duplicate]);
      expect(host.grantRequests, hasLength(1));
      expect(host.appendRequests, hasLength(1));
      expect(host.appendRequests.single.expectedPreviousDecisionDigest, isNull);
      final approvedHead = controller.snapshot.headDecisionDigest;
      expect(approvedHead, isNotNull);
      expect(controller.snapshot.decisionCount, 1);
      expect(
        controller.snapshot.history.single.decision,
        HumanDecision.approved,
      );
      expect(
        controller.snapshot.quality!.verificationState,
        fixture.quality.verificationState,
      );
      expect(
        controller.snapshot.quality!.requiredEvidence.map(
          (item) => item.toJson(),
        ),
        fixture.quality.requiredEvidence.map((item) => item.toJson()),
      );

      await _renderAll(controller);
      controller.requestDecision(HumanDecision.rejected);
      await controller.submitConfirmedDecision();
      expect(host.grantRequests, hasLength(2));
      expect(host.appendRequests, hasLength(2));
      expect(
        host.grantRequests.last.expectedPreviousDecisionDigest,
        approvedHead,
      );
      expect(
        host.appendRequests.last.expectedPreviousDecisionDigest,
        approvedHead,
      );
      expect(controller.snapshot.decisionCount, 2);
      expect(controller.snapshot.history, hasLength(2));
      expect(
        controller.snapshot.history.first.decision,
        HumanDecision.rejected,
      );
      expect(
        controller.snapshot.history.last.supersededByDecisionDigest,
        controller.snapshot.headDecisionDigest,
      );
      expect(
        controller.snapshot.history.last.state,
        HumanDecisionState.superseded,
      );
    },
  );

  test(
    'baseline RequiredEvidence and candidate Supplemental origins are accepted',
    () async {
      final fixture = ScenarioQualityMixedOriginFixture();
      final host = MixedOriginQualityHost(fixture);
      final controller = ScenarioQualityDecisionController(
        host: host,
        resourceClient: host,
        catalog: fixture.catalog,
        manifest: fixture.manifest,
        runSnapshot: fixture.result.finalSnapshot,
        runResult: fixture.result,
      );

      await controller.load();
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.ready,
      );
      expect(controller.snapshot.resources, hasLength(6));
      expect(
        controller.snapshot.resources,
        contains(
          isA<ScenarioQualityReviewResourceSnapshot>()
              .having(
                (resource) => resource.role,
                'role',
                ScenarioQualityReviewArtifactRole.comparisonBaseline,
              )
              .having(
                (resource) => resource.provenanceKind,
                'origin',
                ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
              ),
        ),
      );
      expect(
        controller.snapshot.resources,
        contains(
          isA<ScenarioQualityReviewResourceSnapshot>()
              .having(
                (resource) => resource.role,
                'role',
                ScenarioQualityReviewArtifactRole.comparisonCandidate,
              )
              .having(
                (resource) => resource.provenanceKind,
                'origin',
                ScenarioQualityReviewProvenanceKind.supplementalArtifactImport,
              ),
        ),
      );
      await _renderAll(controller);
      expect(controller.snapshot.canDecide, isTrue);
    },
  );

  test(
    'typed policy denial is availability, while stale append is conflict',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final deniedHost = FakeScenarioQualityHost(fixture)
        ..failureFactory = (operation, requestId) =>
            operation == ScenarioQualityDecisionOperation.describe
            ? ScenarioQualityDecisionError(
                operation: operation,
                code: ScenarioQualityDecisionErrorCode.policyDenied,
                runId: fixture.result.finalSnapshot.runId,
                expectedRunResultDigest: fixture.result.digest,
              )
            : null;
      final denied = _controller(fixture, deniedHost);
      await denied.load();
      expect(
        denied.snapshot.availability,
        ScenarioQualityReviewAvailability.policyDenied,
      );
      expect(
        denied.snapshot.operation,
        ScenarioQualityDecisionOperationState.ready,
      );

      final staleHost = FakeScenarioQualityHost(fixture)
        ..failureFactory = (operation, requestId) =>
            operation == ScenarioQualityDecisionOperation.append
            ? ScenarioQualityDecisionError(
                operation: operation,
                code: ScenarioQualityDecisionErrorCode.stalePreviousDecision,
                runId: fixture.result.finalSnapshot.runId,
                expectedRunResultDigest: fixture.result.digest,
                requestId: requestId,
                currentDecisionDigest: fixture.quality.digest,
              )
            : null;
      final stale = _controller(fixture, staleHost);
      await stale.load();
      await _renderAll(stale);
      stale.requestDecision(HumanDecision.approved);
      await stale.submitConfirmedDecision();
      expect(
        stale.snapshot.operation,
        ScenarioQualityDecisionOperationState.conflict,
      );
      expect(staleHost.appendRequests, hasLength(1));
      await Future<void>.delayed(Duration.zero);
      expect(
        staleHost.appendRequests,
        hasLength(1),
        reason: 'no automatic retry',
      );
    },
  );

  test('tampered provenance fails closed before any decision', () async {
    final fixture = ScenarioQualityDecisionTestFixture();
    final host = FakeScenarioQualityHost(fixture)
      ..provenanceOverride = AppAdapterCaptureReceipt(
        requestId: 'tampered_capture',
        sessionId: 'run-terminal',
        artifactDigest: fixture.descriptor.artifacts.first.artifactDigest,
        pixelDigest: fixture.quality.digest,
        size: fixture.descriptor.artifacts.first.size + 1,
        width: 8,
        height: 4,
        completedAt: DateTime.utc(2026, 8, 14),
      );
    final controller = _controller(fixture, host);
    await controller.load();
    expect(
      controller.snapshot.operation,
      ScenarioQualityDecisionOperationState.protocolViolation,
    );
    expect(controller.snapshot.canDecide, isFalse);
    expect(host.grantRequests, isEmpty);
  });

  test(
    'terminal plan coverage rejects omitted and extra acceptance pre-RPC',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final observed = fixture.result.finalSnapshot.automatedAcceptance;
      final variants = <ScenarioLabRunResult>[
        _withAutomatedAcceptance(fixture.result, observed.take(1)),
        _withAutomatedAcceptance(fixture.result, <AutomatedAcceptanceResult>[
          ...observed,
          AutomatedAcceptanceResult(
            criterionId: AutomatedAcceptanceCriterionId('undeclared-extra'),
            verificationState: VerificationState.passed,
          ),
        ]),
      ];

      for (final altered in variants) {
        final host = FakeScenarioQualityHost(fixture);
        final controller = ScenarioQualityDecisionController(
          host: host,
          resourceClient: host,
          catalog: fixture.lab.catalog,
          manifest: fixture.lab.manifest,
          runSnapshot: altered.finalSnapshot,
          runResult: altered,
        );
        await controller.load();
        expect(
          controller.snapshot.operation,
          ScenarioQualityDecisionOperationState.protocolViolation,
        );
        expect(host.describeRequests, isEmpty);
        expect(host.openRequests, isEmpty);
        expect(host.grantRequests, isEmpty);
        expect(host.appendRequests, isEmpty);
      }
    },
  );

  test(
    'stale image callbacks cannot validate a refreshed resource generation',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final controller = _controller(fixture, host);
      await controller.load();
      final staleGeneration = controller.snapshot.resourceGeneration;
      final descriptors = controller.snapshot.resources
          .map((resource) => resource.descriptorDigest)
          .toList(growable: false);

      await controller.refresh();
      final currentGeneration = controller.snapshot.resourceGeneration;
      expect(currentGeneration, isNot(staleGeneration));
      for (final descriptor in descriptors) {
        controller.markReviewImageRendered(
          descriptor,
          expectedResourceGeneration: staleGeneration,
        );
        controller.rejectReviewImage(
          descriptor,
          expectedResourceGeneration: staleGeneration,
        );
      }
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.ready,
      );
      expect(
        controller.snapshot.resources.every(
          (resource) =>
              resource.state != ScenarioQualityReviewResourceState.rendered &&
              resource.state != ScenarioQualityReviewResourceState.rejected,
        ),
        isTrue,
      );
      expect(controller.snapshot.canDecide, isFalse);
      await _renderAll(controller);
      expect(controller.snapshot.canDecide, isTrue);
    },
  );

  for (final role in ScenarioQualityReviewArtifactRole.values) {
    test(
      '${role.name} artifact digest is fenced to the terminal result',
      () async {
        final fixture = ScenarioQualityDecisionTestFixture();
        final host = FakeScenarioQualityHost(fixture)
          ..describeOverride = (_) async => ScenarioQualityDescribeResult(
            description: fixture.describe().description,
            reviewDescriptor: _tamperArtifactDigest(fixture.descriptor, role),
          );
        final controller = _controller(fixture, host);
        await controller.load();
        expect(
          controller.snapshot.operation,
          ScenarioQualityDecisionOperationState.protocolViolation,
        );
        expect(host.openRequests, isEmpty);
        expect(host.grantRequests, isEmpty);
        expect(host.appendRequests, isEmpty);
      },
    );
  }

  test(
    'App Adapter receipt from another run is rejected before grant',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture(
        captureSessionId: 'another-run',
      );
      final host = FakeScenarioQualityHost(fixture);
      final controller = _controller(fixture, host);
      await controller.load();
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      expect(host.grantRequests, isEmpty);
      expect(host.appendRequests, isEmpty);
    },
  );

  test(
    'append attribution from another grant is a protocol violation',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture)
        ..appendResultTransform = (result) {
          final original = result.attribution;
          final forged = ScenarioQualityDecisionAttribution(
            runId: original.runId,
            runResultDigest: original.runResultDigest,
            reviewDescriptorDigest: original.reviewDescriptorDigest,
            requirementId: original.requirementId,
            requirementScope: original.requirementScope,
            reviewGuideId: original.reviewGuideId,
            reviewGuideStepId: original.reviewGuideStepId,
            authorityId: ScenarioQualityAuthorityId('forged-authority'),
            accessPolicyId: ScenarioQualityAccessPolicyId('forged-policy'),
            principalId: original.principalId,
            role: original.role,
            grantDigest: Digest.semantic('forged-grant'),
            grantRequestDigest: Digest.semantic('forged-grant-request'),
            decisionRequestDigest: original.decisionRequestDigest,
          );
          return ScenarioQualityDecisionAppendResult(
            requestId: result.requestId,
            requestDigest: result.requestDigest,
            attribution: forged,
            record: result.record,
            quality: result.quality,
          );
        };
      final controller = _controller(fixture, host);
      await controller.load();
      await _renderAll(controller);
      controller.requestDecision(HumanDecision.approved);
      await controller.submitConfirmedDecision();
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      expect(host.grantRequests, hasLength(1));
      expect(host.appendRequests, hasLength(1));
    },
  );

  test(
    'restart rejects a canonical head whose record contradicts Quality',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final writer = _controller(fixture, host);
      await writer.load();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.approved);
      await writer.submitConfirmedDecision();
      final published = host.currentQuality;
      final head = host.head!;
      final contradictory = ScenarioQualitySnapshot(
        subjectDigest: published.subjectDigest,
        runId: published.runId,
        scenarioId: published.scenarioId,
        verificationState: published.verificationState,
        humanDecision: HumanDecisionProjection(
          state: HumanDecisionState.rejected,
          decisionDigest: head,
        ),
        requiredEvidence: published.requiredEvidence,
        comparisonResultDigests: published.comparisonResultDigests,
      );
      host.describeOverride = (_) async => fixture.describe(
        currentQuality: contradictory,
        head: head,
        decisionCount: 1,
      );

      final restarted = _controller(fixture, host);
      await restarted.load();
      expect(
        restarted.snapshot.operation,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      expect(restarted.snapshot.canDecide, isFalse);
    },
  );

  test(
    'restart revalidates every historical descriptor against pinned Catalog',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final writer = _controller(fixture, host);
      await writer.load();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.approved);
      await writer.submitConfirmedDecision();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.rejected);
      await writer.submitConfirmedDecision();
      host.getViewTransform = (view) {
        if (view.projection.state != HumanDecisionState.superseded) return view;
        final forgedDescriptor = _copyDescriptor(
          view.reviewDescriptor,
          reviewGuideId: ReviewGuideId('forged-guide'),
          reviewGuideStepId: 'forged-step',
        );
        return ScenarioQualityDecisionView(
          record: view.record,
          projection: view.projection,
          attribution: _copyAttribution(
            view.attribution,
            descriptor: forgedDescriptor,
          ),
          reviewDescriptor: forgedDescriptor,
        );
      };

      final restarted = _controller(fixture, host);
      await restarted.load();
      expect(
        restarted.snapshot.operation,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      expect(host.getRequests, hasLength(greaterThanOrEqualTo(4)));
      expect(restarted.snapshot.canDecide, isFalse);
    },
  );

  test(
    'restart revalidates historical artifacts against the run result',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final writer = _controller(fixture, host);
      await writer.load();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.approved);
      await writer.submitConfirmedDecision();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.rejected);
      await writer.submitConfirmedDecision();
      host.getViewTransform = (view) {
        if (view.projection.state != HumanDecisionState.superseded) return view;
        final forgedDescriptor = _tamperArtifactDigest(
          view.reviewDescriptor,
          ScenarioQualityReviewArtifactRole.comparisonBaseline,
        );
        return ScenarioQualityDecisionView(
          record: view.record,
          projection: view.projection,
          attribution: _copyAttribution(
            view.attribution,
            descriptor: forgedDescriptor,
          ),
          reviewDescriptor: forgedDescriptor,
        );
      };

      final restarted = _controller(fixture, host);
      await restarted.load();
      expect(
        restarted.snapshot.operation,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      expect(restarted.snapshot.canDecide, isFalse);
    },
  );

  test(
    'restart rejects a historical descriptor with a forged Quality digest',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final writer = _controller(fixture, host);
      await writer.load();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.approved);
      await writer.submitConfirmedDecision();
      host.getViewTransform = (view) {
        final forgedDescriptor = _copyDescriptor(
          view.reviewDescriptor,
          qualityDigest: Digest.semantic('forged-history-quality'),
        );
        return ScenarioQualityDecisionView(
          record: view.record,
          projection: view.projection,
          attribution: _copyAttribution(
            view.attribution,
            descriptor: forgedDescriptor,
          ),
          reviewDescriptor: forgedDescriptor,
        );
      };

      final restarted = _controller(fixture, host);
      await restarted.load();
      expect(
        restarted.snapshot.operation,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      expect(restarted.snapshot.canDecide, isFalse);
    },
  );

  test(
    'restart rejects historical media and size drift from current review',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final writer = _controller(fixture, host);
      await writer.load();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.approved);
      await writer.submitConfirmedDecision();
      host.getViewTransform = (view) {
        final original = view.reviewDescriptor.artifacts.first;
        final forgedArtifact = ScenarioQualityReviewArtifactDescriptor(
          requiredEvidenceId: original.requiredEvidenceId,
          requiredEvidenceResultDigest: original.requiredEvidenceResultDigest,
          role: original.role,
          artifactDigest: original.artifactDigest,
          provenanceDigest: original.provenanceDigest,
          provenanceKind: original.provenanceKind,
          classification: original.classification,
          mediaType: 'image/jpeg',
          size: original.size + 1,
          comparisonResultDigest: original.comparisonResultDigest,
        );
        final forgedDescriptor = _copyDescriptor(
          view.reviewDescriptor,
          artifacts: <ScenarioQualityReviewArtifactDescriptor>[
            forgedArtifact,
            ...view.reviewDescriptor.artifacts.skip(1),
          ],
        );
        return ScenarioQualityDecisionView(
          record: view.record,
          projection: view.projection,
          attribution: _copyAttribution(
            view.attribution,
            descriptor: forgedDescriptor,
          ),
          reviewDescriptor: forgedDescriptor,
        );
      };

      final restarted = _controller(fixture, host);
      await restarted.load();
      expect(
        restarted.snapshot.operation,
        ScenarioQualityDecisionOperationState.protocolViolation,
      );
      expect(restarted.snapshot.canDecide, isFalse);
    },
  );

  test(
    'durable history remains visible after restart when review is denied',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final host = FakeScenarioQualityHost(fixture);
      final writer = _controller(fixture, host);
      await writer.load();
      await _renderAll(writer);
      writer.requestDecision(HumanDecision.approved);
      await writer.submitConfirmedDecision();
      final openCount = host.openRequests.length;
      host.availability = ScenarioQualityReviewAvailability.policyDenied;

      final restarted = _controller(fixture, host);
      await restarted.load();
      expect(
        restarted.snapshot.operation,
        ScenarioQualityDecisionOperationState.ready,
      );
      expect(
        restarted.snapshot.availability,
        ScenarioQualityReviewAvailability.policyDenied,
      );
      expect(restarted.snapshot.history, hasLength(1));
      expect(
        restarted.snapshot.history.single.decision,
        HumanDecision.approved,
      );
      expect(restarted.snapshot.resources, isEmpty);
      expect(restarted.snapshot.canDecide, isFalse);
      expect(host.openRequests, hasLength(openCount));
    },
  );

  test(
    'close fences a late describe response and clears private review state',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final completer = Completer<ScenarioQualityDescribeResult>();
      final host = FakeScenarioQualityHost(fixture)
        ..describeOverride = (_) => completer.future;
      final controller = _controller(fixture, host);
      final loading = controller.load();
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.loading,
      );
      controller.close();
      completer.complete(fixture.describe());
      await loading;
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.closed,
      );
      expect(controller.snapshot.resources, isEmpty);
      expect(controller.snapshot.quality, isNull);
    },
  );

  test(
    'a missing quality client is explicitly unsupported and makes no call',
    () async {
      final fixture = ScenarioQualityDecisionTestFixture();
      final controller = ScenarioQualityDecisionController(
        host: null,
        resourceClient: null,
        catalog: fixture.lab.catalog,
        manifest: fixture.lab.manifest,
        runSnapshot: fixture.result.finalSnapshot,
        runResult: fixture.result,
      );
      await controller.load();
      expect(
        controller.snapshot.availability,
        ScenarioQualityReviewAvailability.unsupported,
      );
      expect(
        controller.snapshot.operation,
        ScenarioQualityDecisionOperationState.ready,
      );
      expect(controller.snapshot.canDecide, isFalse);
    },
  );
}

ScenarioQualityDecisionController _controller(
  ScenarioQualityDecisionTestFixture fixture,
  FakeScenarioQualityHost host,
) => ScenarioQualityDecisionController(
  host: host,
  resourceClient: host,
  catalog: fixture.lab.catalog,
  manifest: fixture.lab.manifest,
  runSnapshot: fixture.result.finalSnapshot,
  runResult: fixture.result,
  requestIdFactory: (purpose, sequence) =>
      ScenarioQualityDecisionRequestId('test-$purpose-$sequence'),
);

Future<void> _renderAll(ScenarioQualityDecisionController controller) async {
  final generation = controller.snapshot.resourceGeneration;
  for (final resource in controller.snapshot.resources) {
    if (!resource.isImage) continue;
    final lease = await controller.openReviewImage(
      resource.descriptorDigest,
      expectedResourceGeneration: generation,
    );
    controller.markReviewImageRendered(
      resource.descriptorDigest,
      expectedResourceGeneration: generation,
    );
    lease.release();
  }
}

ScenarioQualityReviewDescriptor _tamperArtifactDigest(
  ScenarioQualityReviewDescriptor descriptor,
  ScenarioQualityReviewArtifactRole role,
) => ScenarioQualityReviewDescriptor(
  runId: descriptor.runId,
  runResultDigest: descriptor.runResultDigest,
  qualityDigest: descriptor.qualityDigest,
  requirementId: descriptor.requirementId,
  requirementScope: descriptor.requirementScope,
  reviewGuideId: descriptor.reviewGuideId,
  reviewGuideStepId: descriptor.reviewGuideStepId,
  requiredEvidenceResultDigests: descriptor.requiredEvidenceResultDigests,
  comparisonResultDigests: descriptor.comparisonResultDigests,
  artifacts: <ScenarioQualityReviewArtifactDescriptor>[
    for (final artifact in descriptor.artifacts)
      ScenarioQualityReviewArtifactDescriptor(
        requiredEvidenceId: artifact.requiredEvidenceId,
        requiredEvidenceResultDigest: artifact.requiredEvidenceResultDigest,
        role: artifact.role,
        artifactDigest: artifact.role == role
            ? Digest.semantic('tampered-${role.name}')
            : artifact.artifactDigest,
        provenanceDigest: artifact.provenanceDigest,
        provenanceKind: artifact.provenanceKind,
        classification: artifact.classification,
        mediaType: artifact.mediaType,
        size: artifact.size,
        comparisonResultDigest: artifact.comparisonResultDigest,
      ),
  ],
);

ScenarioLabRunResult _withAutomatedAcceptance(
  ScenarioLabRunResult result,
  Iterable<AutomatedAcceptanceResult> acceptance,
) {
  final snapshot = result.finalSnapshot;
  final altered = ScenarioLabRunSnapshot(
    runId: snapshot.runId,
    startRequestDigest: snapshot.startRequestDigest,
    contentSetDigest: snapshot.contentSetDigest,
    catalogDigest: snapshot.catalogDigest,
    scenarioLabManifestDigest: snapshot.scenarioLabManifestDigest,
    scenarioId: snapshot.scenarioId,
    scriptId: snapshot.scriptId,
    sequence: snapshot.sequence,
    observedAt: snapshot.observedAt,
    state: snapshot.state,
    runtimeInputs: snapshot.runtimeInputs,
    steps: snapshot.steps,
    controls: snapshot.controls,
    requiredEvidence: snapshot.requiredEvidence,
    automatedAcceptance: acceptance,
    comparisons: snapshot.comparisons,
    cleanup: snapshot.cleanup,
    terminalCause: snapshot.terminalCause,
  );
  return ScenarioLabRunResult(
    finalSnapshot: altered,
    startedAt: result.startedAt,
    completedAt: result.completedAt,
    verificationState: result.verificationState,
  );
}

ScenarioQualityReviewDescriptor _copyDescriptor(
  ScenarioQualityReviewDescriptor descriptor, {
  Digest? qualityDigest,
  ReviewGuideId? reviewGuideId,
  String? reviewGuideStepId,
  Iterable<ScenarioQualityReviewArtifactDescriptor>? artifacts,
}) => ScenarioQualityReviewDescriptor(
  runId: descriptor.runId,
  runResultDigest: descriptor.runResultDigest,
  qualityDigest: qualityDigest ?? descriptor.qualityDigest,
  requirementId: descriptor.requirementId,
  requirementScope: descriptor.requirementScope,
  reviewGuideId: reviewGuideId ?? descriptor.reviewGuideId,
  reviewGuideStepId: reviewGuideStepId ?? descriptor.reviewGuideStepId,
  requiredEvidenceResultDigests: descriptor.requiredEvidenceResultDigests,
  comparisonResultDigests: descriptor.comparisonResultDigests,
  artifacts: artifacts ?? descriptor.artifacts,
);

ScenarioQualityDecisionAttribution _copyAttribution(
  ScenarioQualityDecisionAttribution attribution, {
  required ScenarioQualityReviewDescriptor descriptor,
}) => ScenarioQualityDecisionAttribution(
  runId: attribution.runId,
  runResultDigest: attribution.runResultDigest,
  reviewDescriptorDigest: descriptor.digest,
  requirementId: descriptor.requirementId,
  requirementScope: descriptor.requirementScope,
  reviewGuideId: descriptor.reviewGuideId,
  reviewGuideStepId: descriptor.reviewGuideStepId,
  authorityId: attribution.authorityId,
  accessPolicyId: attribution.accessPolicyId,
  principalId: attribution.principalId,
  role: attribution.role,
  grantDigest: attribution.grantDigest,
  grantRequestDigest: attribution.grantRequestDigest,
  decisionRequestDigest: attribution.decisionRequestDigest,
);
