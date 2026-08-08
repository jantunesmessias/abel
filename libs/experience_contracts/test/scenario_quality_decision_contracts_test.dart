import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Scenario Quality decision wire', () {
    test('all public documents round-trip through the structural schema', () {
      final fixture = _fixture();
      final documents = <Map<String, Object?>>[
        fixture.quality.toJson(),
        fixture.receipt.toJson(),
        fixture.grant.toJson(),
        fixture.describeRequest.toJson(),
        fixture.description.toJson(),
        fixture.descriptor.toJson(),
        fixture.describeResult.toJson(),
        fixture.openRequest.toJson(),
        fixture.openResult.toJson(),
        fixture.grantRequest.toJson(),
        fixture.appendRequest.toJson(),
        fixture.appendResult.toJson(),
        fixture.getRequest.toJson(),
        fixture.view.toJson(),
        fixture.error.toJson(),
      ];
      for (final document in documents) {
        expect(
          _qualitySchema.validate(document).isValid,
          isTrue,
          reason: '${document['kind'] ?? 'AppAdapterCaptureReceipt'}',
        );
      }

      expect(
        ScenarioQualityDecisionGrant.fromJson(
          _wire(fixture.grant.toJson()),
        ).toJson(),
        fixture.grant.toJson(),
      );
      expect(
        ScenarioQualityDescribeResult.fromJson(
          _wire(fixture.describeResult.toJson()),
        ).toJson(),
        fixture.describeResult.toJson(),
      );
      expect(
        ScenarioQualityReviewOpenResult.fromJson(
          _wire(fixture.openResult.toJson()),
        ).toJson(),
        fixture.openResult.toJson(),
      );
      expect(
        ScenarioQualityDecisionAppendResult.fromJson(
          _wire(fixture.appendResult.toJson()),
        ).toJson(),
        fixture.appendResult.toJson(),
      );
      expect(
        ScenarioQualityDecisionView.fromJson(
          _wire(fixture.view.toJson()),
        ).toJson(),
        fixture.view.toJson(),
      );
      expect(
        ScenarioQualityDecisionError.fromJson(
          _wire(fixture.error.toJson()),
        ).toJson(),
        fixture.error.toJson(),
      );
      expect(ScenarioQualityDecisionError.jsonRpcCode, -32120);
    });

    test('schema is structural while codecs enforce exact semantic fences', () {
      final fixture = _fixture();

      final subsetDescriptor = ScenarioQualityReviewDescriptor(
        runId: fixture.runId,
        runResultDigest: fixture.runResultDigest,
        qualityDigest: fixture.quality.digest,
        requirementId: fixture.requirementId,
        requirementScope: HumanApprovalScope.evidenceSet,
        reviewGuideId: ReviewGuideId('review-guide'),
        reviewGuideStepId: 'inspect-all',
        requiredEvidenceResultDigests: <Digest>[fixture.evidenceResultDigest],
        comparisonResultDigests: const <Digest>[],
        artifacts: <ScenarioQualityReviewArtifactDescriptor>[
          fixture.descriptor.artifacts.first,
        ],
      );
      final subset = _redigest(<String, Object?>{
        ...fixture.describeResult.toJson(),
        'reviewDescriptor': subsetDescriptor.toJson(),
      });
      expect(_qualitySchema.validate(subset).isValid, isTrue);
      expect(
        () => ScenarioQualityDescribeResult.fromJson(subset),
        throwsArgumentError,
      );

      final crossRunDescriptor = _descriptor(
        runId: ScenarioLabRunId('other-run'),
        runResultDigest: fixture.runResultDigest,
        qualityDigest: fixture.quality.digest,
        requirementId: fixture.requirementId,
        evidenceResultDigest: fixture.evidenceResultDigest,
        comparisonResultDigest: fixture.comparisonResultDigest,
      );
      final crossRun = _redigest(<String, Object?>{
        ...fixture.describeResult.toJson(),
        'reviewDescriptor': crossRunDescriptor.toJson(),
      });
      expect(_qualitySchema.validate(crossRun).isValid, isTrue);
      expect(
        () => ScenarioQualityDescribeResult.fromJson(crossRun),
        throwsArgumentError,
      );

      final wrongEvidenceId = _wire(fixture.describeResult.toJson());
      final wrongEvidenceDescriptor =
          wrongEvidenceId['reviewDescriptor']! as Map<String, Object?>;
      final wrongEvidenceArtifacts =
          wrongEvidenceDescriptor['artifacts']! as List<Object?>;
      final wrongRequiredArtifact =
          wrongEvidenceArtifacts.firstWhere(
                (value) =>
                    (value! as Map<String, Object?>)['role'] ==
                    'requiredEvidence',
              )!
              as Map<String, Object?>;
      wrongRequiredArtifact['requiredEvidenceId'] = 'other-evidence';
      _redigestInPlace(wrongRequiredArtifact);
      _redigestInPlace(wrongEvidenceDescriptor);
      _redigestInPlace(wrongEvidenceId);
      expect(_qualitySchema.validate(wrongEvidenceId).isValid, isTrue);
      expect(
        () => ScenarioQualityDescribeResult.fromJson(wrongEvidenceId),
        throwsArgumentError,
      );

      for (final duplicateRole in <String>[
        'requiredEvidence',
        'comparisonBaseline',
      ]) {
        final duplicated = _wire(fixture.describeResult.toJson());
        final descriptor =
            duplicated['reviewDescriptor']! as Map<String, Object?>;
        final artifacts = descriptor['artifacts']! as List<Object?>;
        final source =
            artifacts.firstWhere(
                  (value) =>
                      (value! as Map<String, Object?>)['role'] == duplicateRole,
                )!
                as Map<String, Object?>;
        final duplicate = _wire(source)
          ..['artifactDigest'] = _digest('duplicate-$duplicateRole').value;
        _redigestInPlace(duplicate);
        artifacts.add(duplicate);
        _redigestInPlace(descriptor);
        _redigestInPlace(duplicated);
        expect(
          _qualitySchema.validate(duplicated).isValid,
          isTrue,
          reason: 'schema cannot express keyed role cardinality',
        );
        expect(
          () => ScenarioQualityDescribeResult.fromJson(duplicated),
          throwsArgumentError,
        );
      }

      final wrongHandle = _wire(fixture.openResult.toJson());
      final resources = wrongHandle['resources']! as List<Object?>;
      final first = resources.first! as Map<String, Object?>;
      final artifact = first['artifact']! as Map<String, Object?>;
      artifact['digest'] = _digest('wrong-handle').value;
      expect(_qualitySchema.validate(wrongHandle).isValid, isTrue);
      expect(
        () => ScenarioQualityReviewOpenResult.fromJson(wrongHandle),
        throwsArgumentError,
      );

      final forgedAttribution = ScenarioQualityDecisionAttribution(
        runId: fixture.runId,
        runResultDigest: fixture.runResultDigest,
        reviewDescriptorDigest: fixture.descriptor.digest,
        requirementId: fixture.requirementId,
        requirementScope: HumanApprovalScope.evidenceSet,
        reviewGuideId: ReviewGuideId('review-guide'),
        reviewGuideStepId: 'inspect-all',
        authorityId: ScenarioQualityAuthorityId('local-authority'),
        accessPolicyId: ScenarioQualityAccessPolicyId('local-policy'),
        principalId: ScenarioQualityPrincipalId('forged-reviewer'),
        role: ScenarioQualityDecisionRole.reviewer,
        grantDigest: fixture.grant.digest,
        grantRequestDigest: fixture.grantRequest.digest,
        decisionRequestDigest: fixture.appendRequest.digest,
      );
      final forgedView = _redigest(<String, Object?>{
        ...fixture.view.toJson(),
        'attribution': forgedAttribution.toJson(),
      });
      expect(_qualitySchema.validate(forgedView).isValid, isTrue);
      expect(
        () => ScenarioQualityDecisionView.fromJson(forgedView),
        throwsArgumentError,
      );

      final jcsTamper = _wire(fixture.description.toJson())
        ..['availability'] = 'unavailable';
      expect(_qualitySchema.validate(jcsTamper).isValid, isTrue);
      expect(
        () => ScenarioQualityDescription.fromJson(jcsTamper),
        throwsFormatException,
      );
    });

    test(
      'closed codecs enforce reviewer role, IDs and bounded RPC Quality',
      () {
        final fixture = _fixture();
        final observerGrant = _wire(fixture.grant.toJson())
          ..['role'] = 'observer';
        observerGrant['digest'] = Digest.semantic(
          Map<String, Object?>.of(observerGrant)..remove('digest'),
        ).value;
        expect(
          () => ScenarioQualityDecisionGrant.fromJson(observerGrant),
          throwsArgumentError,
        );

        final scenarioRunGrant = _wire(fixture.grant.toJson())
          ..['requirementScope'] = 'scenarioRun';
        _redigestInPlace(scenarioRunGrant);
        expect(_qualitySchema.validate(scenarioRunGrant).isValid, isFalse);
        expect(
          () => ScenarioQualityDecisionGrant.fromJson(scenarioRunGrant),
          throwsArgumentError,
        );

        final scenarioRunAttribution = _wire(
          fixture.appendResult.attribution.toJson(),
        )..['requirementScope'] = 'scenarioRun';
        _redigestInPlace(scenarioRunAttribution);
        expect(
          _qualitySchema.validate(scenarioRunAttribution).isValid,
          isFalse,
        );
        expect(
          () => ScenarioQualityDecisionAttribution.fromJson(
            scenarioRunAttribution,
          ),
          throwsArgumentError,
        );

        final scenarioRunDescriptor = _wire(fixture.descriptor.toJson())
          ..['requirementScope'] = 'scenarioRun';
        _redigestInPlace(scenarioRunDescriptor);
        expect(_qualitySchema.validate(scenarioRunDescriptor).isValid, isFalse);
        expect(
          () => ScenarioQualityReviewDescriptor.fromJson(scenarioRunDescriptor),
          throwsArgumentError,
        );

        expect(
          () => ScenarioQualityReviewDescriptor(
            runId: fixture.runId,
            runResultDigest: fixture.runResultDigest,
            qualityDigest: fixture.quality.digest,
            requirementId: fixture.requirementId,
            requirementScope: HumanApprovalScope.evidenceSet,
            reviewGuideId: ReviewGuideId('review-guide'),
            reviewGuideStepId: 'a${'b' * 256}',
            requiredEvidenceResultDigests: <Digest>[
              fixture.evidenceResultDigest,
            ],
            comparisonResultDigests: <Digest>[fixture.comparisonResultDigest],
            artifacts: fixture.descriptor.artifacts,
          ),
          throwsArgumentError,
        );

        final oversizedQuality = ScenarioQualitySnapshot(
          subjectDigest: fixture.runResultDigest,
          runId: fixture.runId,
          scenarioId: ScenarioId('scenario'),
          verificationState: VerificationState.passed,
          humanDecision: HumanDecisionProjection(
            state: HumanDecisionState.unreviewed,
          ),
          requiredEvidence: List<RequiredEvidenceVerification>.generate(
            33,
            (index) => RequiredEvidenceVerification(
              requiredEvidenceId: RequiredEvidenceId('evidence-$index'),
              resultDigest: _digest('result-$index'),
              verificationState: VerificationState.passed,
            ),
          ),
        );
        expect(
          () => ScenarioQualityDescription(
            runId: fixture.runId,
            runResultDigest: fixture.runResultDigest,
            quality: oversizedQuality,
            availability: ScenarioQualityReviewAvailability.unavailable,
            decisionCount: 0,
          ),
          throwsArgumentError,
        );
        expect(
          () => ScenarioQualitySnapshot(
            subjectDigest: fixture.runResultDigest,
            runId: fixture.runId,
            scenarioId: ScenarioId('s${'x' * 256}'),
            verificationState: VerificationState.passed,
            humanDecision: HumanDecisionProjection(
              state: HumanDecisionState.unreviewed,
            ),
          ),
          throwsFormatException,
        );
      },
    );

    test('time, URI and integer profiles converge at the codec boundary', () {
      final fixture = _fixture();
      final impossible = _wire(fixture.grant.toJson())
        ..['issuedAt'] = '2020-02-31T00:00:00.000Z';
      impossible['digest'] = Digest.semantic(
        Map<String, Object?>.of(impossible)..remove('digest'),
      ).value;
      expect(
        _qualitySchema.validate(impossible).isValid,
        isTrue,
        reason: 'calendar validity is a normative codec invariant',
      );
      expect(
        () => ScenarioQualityDecisionGrant.fromJson(impossible),
        throwsFormatException,
      );

      for (final invalid in <String>['garbageZ', '2026-42-42T00:00:00.000Z']) {
        final json = _wire(fixture.grant.toJson())..['issuedAt'] = invalid;
        expect(_qualitySchema.validate(json).isValid, isFalse);
      }

      final handle = fixture.openResult.resources.first.artifact;
      final normalizedTime = _wire(handle.toJson())
        ..['expiresAt'] = '2026-08-14T12:05:00.000000Z';
      expect(
        () => ResourceHandle.fromJson(normalizedTime),
        throwsFormatException,
      );
      expect(
        () => ResourceHandle(
          uri: Uri.parse('https://example.test/resources/${'x' * 4090}'),
          digest: _digest('long-uri'),
          mediaType: 'image/png',
          size: 1,
          purpose: 'scenario-quality-review-artifact',
          expiresAt: DateTime.utc(2026, 8, 14, 12, 5),
        ),
        throwsArgumentError,
      );

      final numericArtifact = _wire(fixture.descriptor.artifacts.first.toJson())
        ..['size'] = fixture.descriptor.artifacts.first.size.toDouble();
      numericArtifact['digest'] = Digest.semantic(
        Map<String, Object?>.of(numericArtifact)..remove('digest'),
      ).value;
      expect(
        ScenarioQualityReviewArtifactDescriptor.fromJson(numericArtifact).size,
        fixture.descriptor.artifacts.first.size,
      );
    });
  });

  group('public AppAdapterCaptureReceipt', () {
    test('standalone schema and codec preserve exact canonical bytes', () {
      final receipt = _fixture().receipt;
      final bytes = utf8.encode(
        const JcsCanonicalizer().canonicalize(receipt.toJson()),
      );
      expect(receipt.canonicalBytes.toList(), bytes);
      expect(receipt.digest, Digest.bytes(bytes));
      expect(_receiptSchema.validate(receipt.toJson()).isValid, isTrue);
      expect(
        AppAdapterCaptureReceipt.fromJson(
          _wire(receipt.toJson()),
          expectedDigest: receipt.digest,
        ).canonicalBytes,
        receipt.canonicalBytes,
      );

      final numeric = _wire(receipt.toJson())..['width'] = 8.0;
      final numericDigest = Digest.bytes(
        utf8.encode(const JcsCanonicalizer().canonicalize(numeric)),
      );
      expect(_receiptSchema.validate(numeric).isValid, isTrue);
      expect(
        AppAdapterCaptureReceipt.fromJson(
          numeric,
          expectedDigest: numericDigest,
        ).width,
        8,
      );
    });

    test('rejects unknown, tamper, Unicode IDs and invalid calendar', () {
      final receipt = _fixture().receipt;
      final unknown = _wire(receipt.toJson())..['unknown'] = true;
      expect(_receiptSchema.validate(unknown).isValid, isFalse);
      expect(
        () => AppAdapterCaptureReceipt.fromJson(
          unknown,
          expectedDigest: receipt.digest,
        ),
        throwsFormatException,
      );
      expect(
        () => AppAdapterCaptureReceipt.fromJson(
          _wire(receipt.toJson())..['size'] = 129,
          expectedDigest: receipt.digest,
        ),
        throwsFormatException,
      );

      final unicode = _wire(receipt.toJson())..['requestId'] = 'é';
      expect(_receiptSchema.validate(unicode).isValid, isFalse);
      expect(
        () => AppAdapterCaptureReceipt.fromJson(
          unicode,
          expectedDigest: Digest.bytes(
            utf8.encode(const JcsCanonicalizer().canonicalize(unicode)),
          ),
        ),
        throwsArgumentError,
      );

      final invalidCalendar = _wire(receipt.toJson())
        ..['completedAt'] = '2020-02-31T00:00:00.000Z';
      expect(_receiptSchema.validate(invalidCalendar).isValid, isTrue);
      expect(
        () => AppAdapterCaptureReceipt.fromJson(
          invalidCalendar,
          expectedDigest: Digest.bytes(
            utf8.encode(const JcsCanonicalizer().canonicalize(invalidCalendar)),
          ),
        ),
        throwsFormatException,
      );
    });
  });
}

final class _Fixture {
  const _Fixture({
    required this.runId,
    required this.runResultDigest,
    required this.requirementId,
    required this.evidenceResultDigest,
    required this.comparisonResultDigest,
    required this.quality,
    required this.receipt,
    required this.descriptor,
    required this.description,
    required this.describeRequest,
    required this.describeResult,
    required this.openRequest,
    required this.openResult,
    required this.grantRequest,
    required this.grant,
    required this.appendRequest,
    required this.appendResult,
    required this.getRequest,
    required this.view,
    required this.error,
  });

  final ScenarioLabRunId runId;
  final Digest runResultDigest;
  final HumanApprovalRequirementId requirementId;
  final Digest evidenceResultDigest;
  final Digest comparisonResultDigest;
  final ScenarioQualitySnapshot quality;
  final AppAdapterCaptureReceipt receipt;
  final ScenarioQualityReviewDescriptor descriptor;
  final ScenarioQualityDescription description;
  final ScenarioQualityDescribeRequest describeRequest;
  final ScenarioQualityDescribeResult describeResult;
  final ScenarioQualityReviewOpenRequest openRequest;
  final ScenarioQualityReviewOpenResult openResult;
  final ScenarioQualityDecisionGrantRequest grantRequest;
  final ScenarioQualityDecisionGrant grant;
  final ScenarioQualityDecisionAppendRequest appendRequest;
  final ScenarioQualityDecisionAppendResult appendResult;
  final ScenarioQualityDecisionGetRequest getRequest;
  final ScenarioQualityDecisionView view;
  final ScenarioQualityDecisionError error;
}

_Fixture _fixture() {
  final runId = ScenarioLabRunId('run-1');
  final runResultDigest = _digest('run-result');
  final requirementId = HumanApprovalRequirementId('approval');
  final evidenceResultDigest = _digest('evidence-result');
  final comparisonResultDigest = _digest('comparison-result');
  final quality = ScenarioQualitySnapshot(
    subjectDigest: runResultDigest,
    runId: runId,
    scenarioId: ScenarioId('scenario'),
    verificationState: VerificationState.passed,
    humanDecision: HumanDecisionProjection(
      state: HumanDecisionState.unreviewed,
    ),
    requiredEvidence: <RequiredEvidenceVerification>[
      RequiredEvidenceVerification(
        requiredEvidenceId: RequiredEvidenceId('visual'),
        resultDigest: evidenceResultDigest,
        verificationState: VerificationState.passed,
      ),
    ],
    comparisonResultDigests: <Digest>[comparisonResultDigest],
  );
  final descriptor = _descriptor(
    runId: runId,
    runResultDigest: runResultDigest,
    qualityDigest: quality.digest,
    requirementId: requirementId,
    evidenceResultDigest: evidenceResultDigest,
    comparisonResultDigest: comparisonResultDigest,
  );
  final description = ScenarioQualityDescription(
    runId: runId,
    runResultDigest: runResultDigest,
    quality: quality,
    availability: ScenarioQualityReviewAvailability.available,
    requirementId: requirementId,
    decisionCount: 0,
  );
  final describeRequest = ScenarioQualityDescribeRequest(
    runId: runId,
    expectedRunResultDigest: runResultDigest,
  );
  final describeResult = ScenarioQualityDescribeResult(
    description: description,
    reviewDescriptor: descriptor,
  );
  final openRequest = ScenarioQualityReviewOpenRequest(
    runId: runId,
    expectedRunResultDigest: runResultDigest,
    expectedQualityDigest: quality.digest,
    expectedReviewDescriptorDigest: descriptor.digest,
  );
  final openResult = ScenarioQualityReviewOpenResult(
    reviewDescriptor: descriptor,
    resources: <ScenarioQualityReviewResourceBinding>[
      for (var index = 0; index < descriptor.artifacts.length; index++)
        _resourceBinding(descriptor.artifacts[index], index),
    ],
  );
  final grantRequest = ScenarioQualityDecisionGrantRequest(
    requestId: ScenarioQualityDecisionRequestId('grant-request'),
    runId: runId,
    expectedRunResultDigest: runResultDigest,
    expectedQualityDigest: quality.digest,
    expectedReviewDescriptorDigest: descriptor.digest,
    decision: HumanDecision.approved,
  );
  final grant = ScenarioQualityDecisionGrant(
    id: ScenarioQualityDecisionGrantId('grant-1'),
    requestId: grantRequest.requestId,
    requestDigest: grantRequest.digest,
    authorityId: ScenarioQualityAuthorityId('local-authority'),
    accessPolicyId: ScenarioQualityAccessPolicyId('local-policy'),
    principalId: ScenarioQualityPrincipalId('reviewer-1'),
    role: ScenarioQualityDecisionRole.reviewer,
    runId: runId,
    runResultDigest: runResultDigest,
    qualityDigest: quality.digest,
    reviewDescriptorDigest: descriptor.digest,
    requirementId: requirementId,
    requirementScope: HumanApprovalScope.evidenceSet,
    reviewGuideId: ReviewGuideId('review-guide'),
    reviewGuideStepId: 'inspect-all',
    expectedPreviousDecisionDigest: null,
    decision: HumanDecision.approved,
    issuedAt: DateTime.utc(2026, 8, 14, 12),
    expiresAt: DateTime.utc(2026, 8, 14, 12, 2),
  );
  final appendRequest = ScenarioQualityDecisionAppendRequest(
    requestId: ScenarioQualityDecisionRequestId('append-request'),
    runId: runId,
    expectedRunResultDigest: runResultDigest,
    expectedQualityDigest: quality.digest,
    expectedReviewDescriptorDigest: descriptor.digest,
    grantId: grant.id,
    grantDigest: grant.digest,
    decision: HumanDecision.approved,
  );
  final record = HumanDecisionRecord(
    id: HumanDecisionRecordId('decision-1'),
    subjectDigest: runResultDigest,
    principalId: grant.principalId,
    decision: HumanDecision.approved,
    decidedAt: DateTime.utc(2026, 8, 14, 12, 1),
  );
  final attribution = ScenarioQualityDecisionAttribution(
    runId: runId,
    runResultDigest: runResultDigest,
    reviewDescriptorDigest: descriptor.digest,
    requirementId: requirementId,
    requirementScope: HumanApprovalScope.evidenceSet,
    reviewGuideId: ReviewGuideId('review-guide'),
    reviewGuideStepId: 'inspect-all',
    authorityId: grant.authorityId,
    accessPolicyId: grant.accessPolicyId,
    principalId: grant.principalId,
    role: grant.role,
    grantDigest: grant.digest,
    grantRequestDigest: grantRequest.digest,
    decisionRequestDigest: appendRequest.digest,
  );
  final reviewedQuality = ScenarioQualitySnapshot(
    subjectDigest: runResultDigest,
    runId: runId,
    scenarioId: quality.scenarioId,
    verificationState: quality.verificationState,
    humanDecision: HumanDecisionProjection(
      state: HumanDecisionState.approved,
      decisionDigest: record.digest,
    ),
    requiredEvidence: quality.requiredEvidence,
    comparisonResultDigests: quality.comparisonResultDigests,
  );
  final appendResult = ScenarioQualityDecisionAppendResult(
    requestId: appendRequest.requestId,
    requestDigest: appendRequest.digest,
    attribution: attribution,
    record: record,
    quality: reviewedQuality,
  );
  final view = ScenarioQualityDecisionView(
    record: record,
    projection: HumanDecisionProjection(
      state: HumanDecisionState.approved,
      decisionDigest: record.digest,
    ),
    attribution: attribution,
    reviewDescriptor: descriptor,
  );
  final getRequest = ScenarioQualityDecisionGetRequest(
    runId: runId,
    expectedRunResultDigest: runResultDigest,
    decisionDigest: record.digest,
  );
  final error = ScenarioQualityDecisionError(
    operation: ScenarioQualityDecisionOperation.append,
    code: ScenarioQualityDecisionErrorCode.staleQuality,
    runId: runId,
    expectedRunResultDigest: runResultDigest,
    requestId: appendRequest.requestId,
    currentQualityDigest: reviewedQuality.digest,
    currentDecisionDigest: record.digest,
  );
  final receipt = AppAdapterCaptureReceipt(
    requestId: 'capture_request',
    sessionId: 'run-1',
    artifactDigest: _digest('capture-artifact'),
    pixelDigest: _digest('capture-pixels'),
    size: 128,
    width: 8,
    height: 4,
    completedAt: DateTime.utc(2026, 8, 14, 12),
  );
  return _Fixture(
    runId: runId,
    runResultDigest: runResultDigest,
    requirementId: requirementId,
    evidenceResultDigest: evidenceResultDigest,
    comparisonResultDigest: comparisonResultDigest,
    quality: quality,
    receipt: receipt,
    descriptor: descriptor,
    description: description,
    describeRequest: describeRequest,
    describeResult: describeResult,
    openRequest: openRequest,
    openResult: openResult,
    grantRequest: grantRequest,
    grant: grant,
    appendRequest: appendRequest,
    appendResult: appendResult,
    getRequest: getRequest,
    view: view,
    error: error,
  );
}

ScenarioQualityReviewDescriptor _descriptor({
  required ScenarioLabRunId runId,
  required Digest runResultDigest,
  required Digest qualityDigest,
  required HumanApprovalRequirementId requirementId,
  required Digest evidenceResultDigest,
  required Digest comparisonResultDigest,
}) => ScenarioQualityReviewDescriptor(
  runId: runId,
  runResultDigest: runResultDigest,
  qualityDigest: qualityDigest,
  requirementId: requirementId,
  requirementScope: HumanApprovalScope.evidenceSet,
  reviewGuideId: ReviewGuideId('review-guide'),
  reviewGuideStepId: 'inspect-all',
  requiredEvidenceResultDigests: <Digest>[evidenceResultDigest],
  comparisonResultDigests: <Digest>[comparisonResultDigest],
  artifacts: <ScenarioQualityReviewArtifactDescriptor>[
    ScenarioQualityReviewArtifactDescriptor(
      requiredEvidenceId: RequiredEvidenceId('visual'),
      requiredEvidenceResultDigest: evidenceResultDigest,
      role: ScenarioQualityReviewArtifactRole.requiredEvidence,
      artifactDigest: _digest('candidate-artifact'),
      provenanceDigest: _digest('candidate-provenance'),
      provenanceKind:
          ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
      classification: ArtifactClassification.internal,
      mediaType: 'image/png',
      size: 128,
    ),
    ScenarioQualityReviewArtifactDescriptor(
      requiredEvidenceId: RequiredEvidenceId('visual'),
      requiredEvidenceResultDigest: evidenceResultDigest,
      role: ScenarioQualityReviewArtifactRole.comparisonBaseline,
      artifactDigest: _digest('baseline-artifact'),
      provenanceDigest: _digest('baseline-provenance'),
      provenanceKind:
          ScenarioQualityReviewProvenanceKind.supplementalArtifactImport,
      classification: ArtifactClassification.internal,
      mediaType: 'image/png',
      size: 64,
      comparisonResultDigest: comparisonResultDigest,
    ),
    ScenarioQualityReviewArtifactDescriptor(
      requiredEvidenceId: RequiredEvidenceId('visual'),
      requiredEvidenceResultDigest: evidenceResultDigest,
      role: ScenarioQualityReviewArtifactRole.comparisonCandidate,
      artifactDigest: _digest('candidate-artifact'),
      provenanceDigest: _digest('candidate-provenance'),
      provenanceKind:
          ScenarioQualityReviewProvenanceKind.appAdapterCaptureReceipt,
      classification: ArtifactClassification.internal,
      mediaType: 'image/png',
      size: 128,
      comparisonResultDigest: comparisonResultDigest,
    ),
  ],
);

ScenarioQualityReviewResourceBinding _resourceBinding(
  ScenarioQualityReviewArtifactDescriptor descriptor,
  int index,
) => ScenarioQualityReviewResourceBinding(
  artifactDescriptorDigest: descriptor.digest,
  artifact: ResourceHandle(
    uri: Uri.parse('http://127.0.0.1:7367/resources/${'a' * 31}${index + 1}'),
    digest: descriptor.artifactDigest,
    mediaType: descriptor.mediaType,
    size: descriptor.size,
    purpose: 'scenario-quality-review-artifact',
    expiresAt: DateTime.utc(2026, 8, 14, 12, 5),
  ),
  provenance: ResourceHandle(
    uri: Uri.parse('http://127.0.0.1:7367/resources/${'b' * 31}${index + 1}'),
    digest: descriptor.provenanceDigest,
    mediaType: 'application/json',
    size: 32,
    purpose: 'scenario-quality-review-provenance',
    expiresAt: DateTime.utc(2026, 8, 14, 12, 5),
  ),
);

Map<String, Object?> _redigest(Map<String, Object?> value) {
  final copy = _wire(value)..remove('digest');
  return <String, Object?>{...copy, 'digest': Digest.semantic(copy).value};
}

void _redigestInPlace(Map<String, Object?> value) {
  value.remove('digest');
  value['digest'] = Digest.semantic(value).value;
}

Map<String, Object?> _wire(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

Digest _digest(String seed) => Digest.semantic(seed);

final Draft202012Validator _qualitySchema = _schema(
  'scenario-quality.schema.json',
);
final Draft202012Validator _receiptSchema = _schema(
  'app-adapter-capture-receipt.schema.json',
);

Draft202012Validator _schema(String filename) => Draft202012Validator(
  jsonDecode(
        File(
          p.join(_root(), 'schemas', 'evidence', filename),
        ).readAsStringSync(),
      )
      as Object,
);

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
