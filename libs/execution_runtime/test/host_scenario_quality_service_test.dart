import 'dart:io';

import 'package:execution_runtime/execution_runtime.dart'
    hide AppAdapterCaptureReceipt;
import 'package:execution_runtime/src/lab/host_scenario_lab_service.dart';
import 'package:execution_runtime/src/lab/scenario_lab_run_store.dart';
import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/png_fixture.dart';

void main() {
  group('HostScenarioQualityService', () {
    test(
      'executes the exact five-call CAS review and survives restart',
      () async {
        final root = Directory.systemTemp.createTempSync('quality-five-rpc-');
        addTearDown(() => root.deleteSync(recursive: true));
        final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
        final fixture = _fixture(
          classification: ArtifactClassification.internal,
          workspace: workspace,
        );
        final serviceIds = _Ids();
        final resources = HostResourceRegistry(
          clock: const _Clock(),
          ids: _Ids(),
        );
        var service = _service(
          workspace: workspace,
          fixture: fixture,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.internal,
          },
          ids: serviceIds,
        );
        addTearDown(() {
          service.close();
          resources.clear();
        });
        final runId = fixture.result.finalSnapshot.runId;

        final described = service.describeRequest(
          ScenarioQualityDescribeRequest(
            runId: runId,
            expectedRunResultDigest: fixture.result.digest,
          ),
        );
        expect(
          described.description.availability,
          ScenarioQualityReviewAvailability.available,
        );
        expect(described.reviewDescriptor?.artifacts, hasLength(3));

        final grantWithoutOpen = ScenarioQualityDecisionGrantRequest(
          requestId: ScenarioQualityDecisionRequestId('grant-before-open'),
          runId: runId,
          expectedRunResultDigest: fixture.result.digest,
          expectedQualityDigest: described.description.quality.digest,
          expectedReviewDescriptorDigest: described.reviewDescriptor!.digest,
          decision: HumanDecision.approved,
        );
        expect(
          () => service.grantRequest(grantWithoutOpen),
          _rejection(ScenarioQualityDecisionErrorCode.unavailable),
        );
        expect(
          () => service.openRequest(
            request: ScenarioQualityReviewOpenRequest(
              runId: runId,
              expectedRunResultDigest: fixture.result.digest,
              expectedQualityDigest: described.description.quality.digest,
              expectedReviewDescriptorDigest: _digest('stale-descriptor'),
            ),
            resources: resources,
            hostOrigin: Uri.parse('http://127.0.0.1:7367'),
            audienceOrigin: Uri.parse('http://127.0.0.1:7368'),
          ),
          _rejection(ScenarioQualityDecisionErrorCode.staleQuality),
        );
        expect(resources.activeCount, 0);

        final opened = service.openRequest(
          request: ScenarioQualityReviewOpenRequest(
            runId: runId,
            expectedRunResultDigest: fixture.result.digest,
            expectedQualityDigest: described.description.quality.digest,
            expectedReviewDescriptorDigest: described.reviewDescriptor!.digest,
          ),
          resources: resources,
          hostOrigin: Uri.parse('http://127.0.0.1:7367'),
          audienceOrigin: Uri.parse('http://127.0.0.1:7368'),
        );
        expect(resources.activeCount, 6);
        for (final binding in opened.resources) {
          for (final handle in <ResourceHandle>[
            binding.artifact,
            binding.provenance,
          ]) {
            final response = resources.serve(
              Request(
                'GET',
                handle.uri,
                headers: const <String, String>{
                  'origin': 'http://127.0.0.1:7368',
                },
              ),
            );
            final bytes = await response
                .read()
                .expand((chunk) => chunk)
                .toList();
            expect(response.statusCode, 200);
            expect(Digest.bytes(bytes), handle.digest);
            expect(bytes, workspace.readBlob(handle.digest));
          }
        }

        final grantRequest = ScenarioQualityDecisionGrantRequest(
          requestId: ScenarioQualityDecisionRequestId('grant-approve'),
          runId: runId,
          expectedRunResultDigest: fixture.result.digest,
          expectedQualityDigest: described.description.quality.digest,
          expectedReviewDescriptorDigest: described.reviewDescriptor!.digest,
          decision: HumanDecision.approved,
        );
        final grant = service.grantRequest(grantRequest);
        expect(service.grantRequest(grantRequest).toJson(), grant.toJson());
        final appendRequest = ScenarioQualityDecisionAppendRequest(
          requestId: ScenarioQualityDecisionRequestId('append-approve'),
          runId: runId,
          expectedRunResultDigest: fixture.result.digest,
          expectedQualityDigest: grant.qualityDigest,
          expectedReviewDescriptorDigest: grant.reviewDescriptorDigest,
          grantId: grant.id,
          grantDigest: grant.digest,
          decision: grant.decision,
        );
        final appended = service.appendRequest(appendRequest);
        expect(
          service.appendRequest(appendRequest).toJson(),
          appended.toJson(),
        );
        final current = service.getRequest(
          ScenarioQualityDecisionGetRequest(
            runId: runId,
            expectedRunResultDigest: fixture.result.digest,
            decisionDigest: appended.record.digest,
          ),
        );
        expect(current.record.decision, HumanDecision.approved);
        expect(current.reviewDescriptor.digest, grant.reviewDescriptorDigest);

        service.close();
        expect(resources.activeCount, 0);
        service = _service(
          workspace: FileSystemWorkspaceStore(workspaceRoot: root.path),
          fixture: fixture,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.internal,
          },
          ids: serviceIds,
        );
        final afterRestart = service.describeRequest(
          ScenarioQualityDescribeRequest(
            runId: runId,
            expectedRunResultDigest: fixture.result.digest,
          ),
        );
        expect(afterRestart.description.decisionCount, 1);
        expect(
          afterRestart.description.quality.humanDecision.state,
          HumanDecisionState.approved,
        );
        service.openRequest(
          request: ScenarioQualityReviewOpenRequest(
            runId: runId,
            expectedRunResultDigest: fixture.result.digest,
            expectedQualityDigest: afterRestart.description.quality.digest,
            expectedReviewDescriptorDigest:
                afterRestart.reviewDescriptor!.digest,
          ),
          resources: resources,
          hostOrigin: Uri.parse('http://127.0.0.1:7367'),
          audienceOrigin: Uri.parse('http://127.0.0.1:7368'),
        );
        final rejectGrant = service.grantRequest(
          ScenarioQualityDecisionGrantRequest(
            requestId: ScenarioQualityDecisionRequestId('grant-reject'),
            runId: runId,
            expectedRunResultDigest: fixture.result.digest,
            expectedQualityDigest: afterRestart.description.quality.digest,
            expectedReviewDescriptorDigest:
                afterRestart.reviewDescriptor!.digest,
            expectedPreviousDecisionDigest: appended.record.digest,
            decision: HumanDecision.rejected,
          ),
        );
        final rejected = service.appendRequest(
          ScenarioQualityDecisionAppendRequest(
            requestId: ScenarioQualityDecisionRequestId('append-reject'),
            runId: runId,
            expectedRunResultDigest: fixture.result.digest,
            expectedQualityDigest: rejectGrant.qualityDigest,
            expectedReviewDescriptorDigest: rejectGrant.reviewDescriptorDigest,
            grantId: rejectGrant.id,
            grantDigest: rejectGrant.digest,
            expectedPreviousDecisionDigest: appended.record.digest,
            decision: HumanDecision.rejected,
          ),
        );
        expect(
          rejected.record.decidedAt.isAfter(appended.record.decidedAt),
          isTrue,
        );
        expect(
          service
              .getRequest(
                ScenarioQualityDecisionGetRequest(
                  runId: runId,
                  expectedRunResultDigest: fixture.result.digest,
                  decisionDigest: appended.record.digest,
                ),
              )
              .projection
              .state,
          HumanDecisionState.superseded,
        );
        expect(
          service
              .getRequest(
                ScenarioQualityDecisionGetRequest(
                  runId: runId,
                  expectedRunResultDigest: fixture.result.digest,
                  decisionDigest: rejected.record.digest,
                ),
              )
              .projection
              .state,
          HumanDecisionState.rejected,
        );
      },
    );

    test(
      'content generation drift preserves exact Quality but disables review',
      () {
        final root = Directory.systemTemp.createTempSync('quality-stale-');
        addTearDown(() => root.deleteSync(recursive: true));
        final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
        final fixture = _fixture(
          classification: ArtifactClassification.internal,
          workspace: workspace,
        );
        final previous = fixture.content.identity;
        final currentContent = HostScenarioLabContent(
          identity: ExperienceContentSetIdentity(
            revision: previous.revision + 1,
            catalogDigest: previous.catalogDigest,
            workspaceSnapshotDigest: _digest('new-workspace-snapshot'),
            workspaceContentDigest: _digest('new-workspace-content'),
            experienceTopologyBundleDigest:
                previous.experienceTopologyBundleDigest,
            scenarioFacetManifestDigest: previous.scenarioFacetManifestDigest,
            scenarioLabManifestDigest: previous.scenarioLabManifestDigest,
          ),
          catalog: fixture.content.catalog,
          manifest: fixture.content.manifest,
        );
        final service = _service(
          workspace: workspace,
          fixture: fixture,
          currentContent: currentContent,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.internal,
          },
        );
        addTearDown(service.close);
        final described = service.describeRequest(
          ScenarioQualityDescribeRequest(
            runId: fixture.result.finalSnapshot.runId,
            expectedRunResultDigest: fixture.result.digest,
          ),
        );

        expect(
          described.description.availability,
          ScenarioQualityReviewAvailability.unavailable,
        );
        expect(described.reviewDescriptor, isNull);
        expect(
          described.description.quality.subjectDigest,
          fixture.result.digest,
        );
        expect(
          described.description.quality.verificationState,
          fixture.result.verificationState,
        );
      },
    );

    test(
      'classification policy is evaluated before any Evidence state read',
      () {
        final root = Directory.systemTemp.createTempSync('quality-policy-');
        addTearDown(() => root.deleteSync(recursive: true));
        final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
        final fixture = _fixture(classification: ArtifactClassification.public);
        final evidencePath = p.join(
          'evidence',
          'sha256',
          '${fixture.evidenceDigest.value.substring('sha256:'.length)}.json',
        );
        workspace.atomicWrite(
          evidencePath,
          List<int>.filled(LocalEvidenceRepository.maxDocumentBytes + 1, 0x20),
        );
        final resources = HostResourceRegistry(
          clock: const _Clock(),
          ids: _Ids(),
        );
        final service = _service(
          workspace: workspace,
          fixture: fixture,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.internal,
          },
        );

        final described = service.describeRequest(
          ScenarioQualityDescribeRequest(
            runId: fixture.result.finalSnapshot.runId,
            expectedRunResultDigest: fixture.result.digest,
          ),
        );
        expect(
          described.description.availability,
          ScenarioQualityReviewAvailability.policyDenied,
        );
        expect(described.reviewDescriptor, isNull);
        expect(
          () => service.openRequest(
            request: ScenarioQualityReviewOpenRequest(
              runId: fixture.result.finalSnapshot.runId,
              expectedRunResultDigest: fixture.result.digest,
              expectedQualityDigest: described.description.quality.digest,
              expectedReviewDescriptorDigest: _digest('not-issued'),
            ),
            resources: resources,
            hostOrigin: Uri.parse('http://127.0.0.1:7367'),
            audienceOrigin: Uri.parse('http://127.0.0.1:7368'),
          ),
          _rejection(ScenarioQualityDecisionErrorCode.policyDenied),
        );
        expect(resources.activeCount, 0);

        final allowed = _service(
          workspace: workspace,
          fixture: fixture,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.public,
            ArtifactClassification.internal,
          },
        );
        expect(
          allowed
              .describeRequest(
                ScenarioQualityDescribeRequest(
                  runId: fixture.result.finalSnapshot.runId,
                  expectedRunResultDigest: fixture.result.digest,
                ),
              )
              .description
              .availability,
          ScenarioQualityReviewAvailability.unavailable,
          reason: 'only an authorized classification reaches the corrupt state',
        );
      },
    );

    test('valid but unsupported providers stay distinct from unavailable', () {
      final root = Directory.systemTemp.createTempSync('quality-unsupported-');
      addTearDown(() => root.deleteSync(recursive: true));
      final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
      final fixture = _fixture(
        classification: ArtifactClassification.internal,
        providerId: ModuleId('capture.web'),
      );
      final service = _service(
        workspace: workspace,
        fixture: fixture,
        allowedClassifications: const <ArtifactClassification>{
          ArtifactClassification.internal,
        },
      );

      final result = service.describeRequest(
        ScenarioQualityDescribeRequest(
          runId: fixture.result.finalSnapshot.runId,
          expectedRunResultDigest: fixture.result.digest,
        ),
      );
      expect(
        result.description.availability,
        ScenarioQualityReviewAvailability.unsupported,
      );
      expect(result.reviewDescriptor, isNull);
    });

    test(
      'Evidence documents share the review byte budget before later CAS work',
      () {
        final root = Directory.systemTemp.createTempSync(
          'quality-evidence-budget-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
        final fixture = _fixture(
          classification: ArtifactClassification.internal,
          workspace: workspace,
          evidenceCount: 2,
        );
        final results = fixture.result.finalSnapshot.requiredEvidence;
        final first = results.first;
        final second = results.last;
        final firstDocumentBytes = _evidenceDocumentFile(
          workspace,
          first.evidenceDigest!,
        ).lengthSync();
        final secondDocumentBytes = _evidenceDocumentFile(
          workspace,
          second.evidenceDigest!,
        ).lengthSync();
        final firstArtifactBytes = workspace.blobSize(
          first.artifacts.single.artifactDigest,
        )!;
        final firstProvenanceBytes = workspace.blobSize(
          first.artifacts.single.provenanceDigest,
        )!;
        final budgetBeforeSecondDecode =
            firstDocumentBytes +
            firstArtifactBytes +
            firstProvenanceBytes +
            secondDocumentBytes -
            1;

        expect(
          LocalEvidenceRepository(
            store: workspace,
            clock: const _Clock(),
            ids: _Ids(),
          ).readEvidence(second.evidenceDigest!),
          isNotNull,
          reason: 'both small Evidence documents start valid',
        );
        _blobFile(
          workspace,
          second.artifacts.single.artifactDigest,
        ).deleteSync();
        _blobFile(
          workspace,
          second.artifacts.single.provenanceDigest,
        ).deleteSync();

        final service = _service(
          workspace: workspace,
          fixture: fixture,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.internal,
          },
          maxReviewAggregateBytes: budgetBeforeSecondDecode,
        );
        addTearDown(service.close);
        expect(
          () => service.describeRequest(
            ScenarioQualityDescribeRequest(
              runId: fixture.result.finalSnapshot.runId,
              expectedRunResultDigest: fixture.result.digest,
            ),
          ),
          _rejection(ScenarioQualityDecisionErrorCode.quotaExceeded),
          reason:
              'the second document exhausts quota before its missing CAS is read',
        );
      },
    );

    test('describe preflights the complete JSON-RPC response envelope', () {
      final root = Directory.systemTemp.createTempSync('quality-frame-');
      addTearDown(() => root.deleteSync(recursive: true));
      final workspace = FileSystemWorkspaceStore(workspaceRoot: root.path);
      final fixture = _fixture(
        classification: ArtifactClassification.internal,
        providerId: ModuleId('capture.web'),
      );
      final service = _service(
        workspace: workspace,
        fixture: fixture,
        allowedClassifications: const <ArtifactClassification>{
          ArtifactClassification.internal,
        },
        maxRpcMessageBytes: 1024,
      );
      expect(
        () => service.describeRequest(
          ScenarioQualityDescribeRequest(
            runId: fixture.result.finalSnapshot.runId,
            expectedRunResultDigest: fixture.result.digest,
          ),
        ),
        _rejection(ScenarioQualityDecisionErrorCode.quotaExceeded),
      );
    });
  });
}

Matcher _rejection(ScenarioQualityDecisionErrorCode code) => throwsA(
  isA<HostScenarioQualityDecisionRejected>().having(
    (rejection) => rejection.error.code,
    'code',
    code,
  ),
);

HostScenarioQualityService _service({
  required FileSystemWorkspaceStore workspace,
  required _Fixture fixture,
  required Set<ArtifactClassification> allowedClassifications,
  int maxRpcMessageBytes = 64 * 1024,
  int maxReviewAggregateBytes = 64 * 1024 * 1024,
  IdGenerator? ids,
  HostScenarioLabContent? currentContent,
}) {
  final resolvedIds = ids ?? _Ids();
  return HostScenarioQualityService(
    workspaceStore: workspace,
    runStore: _RunStore(fixture.storedRun),
    decisionStore: FilesystemScenarioQualityDecisionStore(
      workspaceStore: workspace,
    ),
    evidenceRepository: LocalEvidenceRepository(
      store: workspace,
      clock: const _Clock(),
      ids: resolvedIds,
    ),
    readContent: () => currentContent ?? fixture.content,
    clock: const _Clock(),
    ids: resolvedIds,
    authority: HostScenarioQualityDecisionAuthority(
      authorityId: ScenarioQualityAuthorityId('local-authority'),
      accessPolicyId: ScenarioQualityAccessPolicyId('local-policy'),
      principalId: ScenarioQualityPrincipalId('reviewer-1'),
      role: ScenarioQualityDecisionRole.reviewer,
      allowedRequirementIds: <HumanApprovalRequirementId>[
        HumanApprovalRequirementId('approval'),
      ],
      allowedDecisions: const <HumanDecision>{
        HumanDecision.approved,
        HumanDecision.rejected,
      },
      artifactClassifications: allowedClassifications,
    ),
    maxRpcMessageBytes: maxRpcMessageBytes,
    maxReviewAggregateBytes: maxReviewAggregateBytes,
  );
}

final class _Fixture {
  const _Fixture({
    required this.content,
    required this.result,
    required this.storedRun,
    required this.evidenceDigest,
  });

  final HostScenarioLabContent content;
  final ScenarioLabRunResult result;
  final ScenarioLabStoredRun storedRun;
  final Digest evidenceDigest;
}

_Fixture _fixture({
  required ArtifactClassification classification,
  ModuleId? providerId,
  FileSystemWorkspaceStore? workspace,
  int evidenceCount = 1,
}) {
  if (evidenceCount < 1 || evidenceCount > 8) {
    throw ArgumentError.value(evidenceCount, 'evidenceCount');
  }
  final catalog = _catalog();
  final effectiveProviderId = providerId ?? ModuleId('capture.app-adapter');
  final evidenceIds = List<RequiredEvidenceId>.generate(
    evidenceCount,
    _fixtureEvidenceId,
  );
  final artifactDigests = List<Digest>.generate(
    evidenceCount,
    (index) => _digest('artifact-$index'),
  );
  final artifactProvenanceDigests = List<Digest>.generate(
    evidenceCount,
    (index) => _digest('provenance-$index'),
  );
  final evidenceDigests = List<Digest>.generate(
    evidenceCount,
    (index) => _digest('evidence-$index'),
  );
  var baselineArtifactDigest = _digest('baseline-artifact');
  var baselineProvenanceDigest = _digest('baseline-provenance');
  ExecutionFingerprint? exactFingerprint;
  if (workspace != null) {
    if (effectiveProviderId.value != 'capture.app-adapter') {
      throw ArgumentError('Only app-adapter fixtures can materialize CAS');
    }
    exactFingerprint = _reviewFingerprint(catalog.digest);
    final evidenceRepository = LocalEvidenceRepository(
      store: workspace,
      clock: const _Clock(),
      ids: _Ids(),
    );
    final candidateBytes = <List<int>>[];
    for (var index = 0; index < evidenceCount; index += 1) {
      final bytes = rgbaPng(
        width: 2,
        height: 1,
        pixels: <int>[index + 1, 2, 3, 255, 4, 5, index + 6, 255],
      );
      candidateBytes.add(bytes);
      final inspection = const PngCaptureInspector().inspect(bytes);
      artifactDigests[index] = workspace.putBlob(bytes);
      final receipt = AppAdapterCaptureReceipt(
        requestId: 'capture-request-${index + 1}',
        sessionId: 'run-1',
        artifactDigest: artifactDigests[index],
        pixelDigest: inspection.pixelDigest,
        size: bytes.length,
        width: inspection.width,
        height: inspection.height,
        completedAt: DateTime.utc(2026, 8, 14, 12),
      );
      artifactProvenanceDigests[index] = workspace.putBlob(
        receipt.canonicalBytes,
      );
      final evidence = evidenceRepository.persistEvidence(
        Evidence(
          id: 'evidence-quality-review-${index + 1}',
          subjectDigest: catalog.digest,
          fingerprint: exactFingerprint,
          observedAt: DateTime.utc(2026, 8, 14, 12),
          policyId: 'visual-policy',
          artifacts: <Artifact>[
            Artifact(
              digest: artifactDigests[index],
              size: bytes.length,
              mediaType: 'image/png',
              classification: classification,
              role: 'scenario-lab.capture.app-adapter',
              pixelDigest: inspection.pixelDigest,
              width: inspection.width,
              height: inspection.height,
            ),
          ],
        ),
      );
      evidenceDigests[index] = evidence.digest;
    }

    final baselineBytes = candidateBytes.first;
    baselineArtifactDigest = workspace.putBlob(baselineBytes);
    final baselineProvenance = ScenarioLabSupplementalArtifactProvenance(
      artifactDigest: baselineArtifactDigest,
      size: baselineBytes.length,
      mediaType: ScenarioLabSupplementalArtifactMediaType.png,
      classification: ArtifactClassification.internal,
      sourceId: ScenarioLabSupplementalArtifactSourceId('golden-dashboard'),
      importPolicyId: ScenarioLabSupplementalArtifactImportPolicyId(
        'workspace-import-v1',
      ),
    );
    baselineProvenanceDigest = workspace.putBlob(
      baselineProvenance.canonicalBytes,
    );
  }
  final manifest = _manifest(
    catalog,
    effectiveProviderId,
    evidenceCount: evidenceCount,
    baselineArtifactDigest: baselineArtifactDigest,
    baselineProvenanceDigest: baselineProvenanceDigest,
  );
  final identity = ExperienceContentSetIdentity(
    revision: 1,
    catalogDigest: catalog.digest,
    workspaceSnapshotDigest: _digest('workspace'),
    workspaceContentDigest: _digest('workspace-content'),
    experienceTopologyBundleDigest: _digest('topology'),
    scenarioFacetManifestDigest: _digest('facets'),
    scenarioLabManifestDigest: manifest.digest,
  );
  final content = HostScenarioLabContent(
    identity: identity,
    catalog: catalog,
    manifest: manifest,
  );
  final request = ScenarioLabRunStartRequest(
    requestId: ScenarioLabRunRequestId('request-1'),
    expectedContentSetDigest: identity.contentSetDigest,
    expectedScenarioLabManifestDigest: manifest.digest,
    scenarioId: ScenarioId('scenario'),
    scriptId: ScenarioScriptId('script'),
    requestedAt: DateTime.utc(2026, 8, 14, 11, 59),
  );
  final evidence = <RequiredEvidenceRunResult>[
    for (var index = 0; index < evidenceCount; index += 1)
      RequiredEvidenceRunResult(
        requiredEvidenceId: evidenceIds[index],
        providerId: effectiveProviderId,
        fidelity: RuntimeFidelity.hostNative,
        variantId: VariantId('phone'),
        freshness: EvidenceFreshness.fresh,
        state: RequiredEvidenceResultState.collected,
        evidenceDigest: evidenceDigests[index],
        artifacts: <ScenarioEvidenceArtifactResult>[
          ScenarioEvidenceArtifactResult(
            artifactDigest: artifactDigests[index],
            provenanceDigest: artifactProvenanceDigests[index],
            classification: classification,
          ),
        ],
      ),
  ];
  final comparisons = <ScenarioComparisonResult>[
    for (var index = 0; index < evidenceCount; index += 1)
      VisualScenarioComparisonResult(
        bindingId: _fixtureComparisonId(index),
        requiredEvidenceId: evidenceIds[index],
        baselineDigest: baselineArtifactDigest,
        candidateDigest: artifactDigests[index],
        policyDigest: manifest.visualComparisonPolicies.single.digest,
        verificationState: VerificationState.passed,
        comparedPixels: 1,
        changedPixels: 0,
        maxChannelDeltaObserved: 0,
      ),
  ];
  final snapshot = ScenarioLabRunSnapshot(
    runId: ScenarioLabRunId('run-1'),
    startRequestDigest: request.digest,
    contentSetDigest: identity.contentSetDigest,
    catalogDigest: catalog.digest,
    scenarioLabManifestDigest: manifest.digest,
    scenarioId: request.scenarioId,
    scriptId: request.scriptId,
    sequence: 1,
    observedAt: DateTime.utc(2026, 8, 14, 12),
    state: ScenarioLabRunState.succeeded,
    runtimeInputs: ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest:
          exactFingerprint?.digest ?? _digest('fingerprint'),
      executionTargetId: 'browser',
    ),
    steps: <ScenarioLabStepSnapshot>[
      ScenarioLabStepSnapshot(
        stepId: 'collect',
        state: ScenarioLabStepState.succeeded,
        startedAt: DateTime.utc(2026, 8, 14, 11, 59),
        completedAt: DateTime.utc(2026, 8, 14, 12),
        terminalCause: ScenarioLabStepTerminalCause.completed,
      ),
    ],
    requiredEvidence: evidence,
    automatedAcceptance: <AutomatedAcceptanceResult>[
      AutomatedAcceptanceResult(
        criterionId: AutomatedAcceptanceCriterionId('accepted'),
        verificationState: VerificationState.passed,
      ),
      for (var index = 0; index < evidenceCount; index += 1)
        AutomatedAcceptanceResult(
          criterionId: _fixtureEvidenceAcceptanceId(index),
          verificationState: VerificationState.passed,
        ),
    ],
    comparisons: comparisons,
    cleanup: ScenarioLabCleanupResult(state: ScenarioLabCleanupState.succeeded),
    terminalCause: ScenarioLabTerminalCause.completed,
  );
  final result = ScenarioLabRunResult(
    finalSnapshot: snapshot,
    startedAt: DateTime.utc(2026, 8, 14, 11, 59),
    completedAt: DateTime.utc(2026, 8, 14, 12),
    verificationState: VerificationState.passed,
  );
  return _Fixture(
    content: content,
    result: result,
    storedRun: ScenarioLabStoredRun(
      request: request,
      snapshots: <ScenarioLabRunSnapshot>[snapshot],
      result: result,
      interrupted: false,
    ),
    evidenceDigest: evidenceDigests.first,
  );
}

CatalogManifest _catalog() {
  final layout = ConsumerLayout.standard;
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('application');
  final scenarioId = ScenarioId('scenario');
  final bindingId = ScenarioExecutionBindingId('scenario-web');
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Application',
        root: '.',
        target: 'web',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(id: scenarioId, applicationId: applicationId, title: 'Scenario'),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: bindingId,
        scenarioId: scenarioId,
        targetId: 'browser',
        launchProfileId: 'web',
      ),
    ],
    reviewGuides: <ReviewGuide>[
      ReviewGuide(
        id: ReviewGuideId('review-guide'),
        applicationId: applicationId,
        title: 'Review',
        steps: <ReviewGuideStep>[
          ReviewGuideStep(
            id: 'inspect-all',
            instruction: 'Inspect all evidence.',
            observationCriteria: 'Every required artifact is legible.',
            scenarioId: scenarioId,
            bindingId: bindingId,
          ),
        ],
      ),
    ],
  );
}

ScenarioLabManifest _manifest(
  CatalogManifest catalog,
  ModuleId providerId, {
  int evidenceCount = 1,
  Digest? baselineArtifactDigest,
  Digest? baselineProvenanceDigest,
}) {
  final scenarioId = ScenarioId('scenario');
  final evidenceIds = List<RequiredEvidenceId>.generate(
    evidenceCount,
    _fixtureEvidenceId,
  );
  final scriptId = ScenarioScriptId('script');
  final operationIds = List<ScenarioLabOperationId>.generate(
    evidenceCount,
    (index) =>
        ScenarioLabOperationId(index == 0 ? 'collect' : 'collect-$index'),
  );
  final acceptanceId = AutomatedAcceptanceCriterionId('accepted');
  final evidenceAcceptanceIds = List<AutomatedAcceptanceCriterionId>.generate(
    evidenceCount,
    _fixtureEvidenceAcceptanceId,
  );
  final comparisonIds = List<ScenarioComparisonBindingId>.generate(
    evidenceCount,
    _fixtureComparisonId,
  );
  final supplementalIds = List<SupplementalArtifactId>.generate(
    evidenceCount,
    (index) =>
        SupplementalArtifactId(index == 0 ? 'baseline' : 'baseline-$index'),
  );
  return ScenarioLabManifest(
    catalog: catalog,
    appAdapterCapabilities: const <CapabilityDescriptor>[],
    controls: const <ScenarioControlDefinition>[],
    operations: <ScenarioLabOperationDefinition>[
      for (var index = 0; index < evidenceCount; index += 1)
        CollectEvidenceOperationDefinition(
          id: operationIds[index],
          scenarioId: scenarioId,
          evidenceRequirementId: evidenceIds[index],
        ),
    ],
    scripts: <ScenarioScriptDefinition>[
      ScenarioScriptDefinition(
        id: scriptId,
        scenarioId: scenarioId,
        displayName: 'Collect evidence',
        timeoutMs: 30000,
        timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
        cancellationPolicy: ScenarioScriptCancellationPolicy.immediate,
        steps: <ScenarioScriptStep>[
          ExecutionBindingScenarioScriptStep(
            id: 'attach',
            timeoutMs: 10000,
            timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
            bindingId: ScenarioExecutionBindingId('scenario-web'),
          ),
          for (var index = 0; index < evidenceCount; index += 1)
            OperationScenarioScriptStep(
              id: index == 0 ? 'collect' : 'collect-$index',
              timeoutMs: 10000,
              timeoutOutcome: ScenarioScriptTimeoutOutcome.fail,
              operationId: operationIds[index],
            ),
        ],
      ),
    ],
    automatedAcceptanceCriteria: <AutomatedAcceptanceCriterion>[
      ScriptSucceededAcceptanceCriterion(
        id: acceptanceId,
        scenarioId: scenarioId,
        displayName: 'Script succeeds',
        scriptId: scriptId,
      ),
      for (var index = 0; index < evidenceCount; index += 1)
        EvidenceAcceptedAcceptanceCriterion(
          id: evidenceAcceptanceIds[index],
          scenarioId: scenarioId,
          displayName: 'Evidence accepted ${index + 1}',
          evidenceRequirementId: evidenceIds[index],
        ),
    ],
    requiredEvidence: <RequiredEvidenceDefinition>[
      for (var index = 0; index < evidenceCount; index += 1)
        RequiredEvidenceDefinition(
          id: evidenceIds[index],
          scenarioId: scenarioId,
          providerId: providerId,
          fidelity: RuntimeFidelity.hostNative,
          variantId: VariantId('phone'),
          freshness: EvidenceFreshness.fresh,
          allowedClassifications: const <ArtifactClassification>{
            ArtifactClassification.public,
            ArtifactClassification.internal,
          },
          evidencePolicyId: EvidencePolicyId('visual-policy'),
          comparisonPolicy: VisualComparisonPolicyReference(
            VisualComparisonPolicyId('pixel-policy'),
          ),
        ),
    ],
    comparisonBindings: <ScenarioComparisonBinding>[
      for (var index = 0; index < evidenceCount; index += 1)
        ScenarioComparisonBinding(
          id: comparisonIds[index],
          scenarioId: scenarioId,
          requiredEvidenceId: evidenceIds[index],
          baseline: ArtifactComparisonInputReference(
            artifactId: supplementalIds[index],
          ),
          candidate: RequiredEvidenceComparisonInputReference(
            requiredEvidenceId: evidenceIds[index],
          ),
        ),
    ],
    visualComparisonPolicies: <VisualComparisonPolicy>[
      VisualComparisonPolicy(
        id: 'pixel-policy',
        maxChannelDelta: 0,
        maxChangedPixelRatio: 0,
      ),
    ],
    semanticComparisonPolicies: const <SemanticComparisonPolicy>[],
    humanApprovalRequirements: <HumanApprovalRequirement>[
      HumanApprovalRequirement(
        id: HumanApprovalRequirementId('approval'),
        scenarioId: scenarioId,
        reviewGuideId: ReviewGuideId('review-guide'),
        reviewGuideStepId: 'inspect-all',
        scope: HumanApprovalScope.evidenceSet,
      ),
    ],
    supplementalArtifacts: <SupplementalArtifactReference>[
      for (var index = 0; index < evidenceCount; index += 1)
        SupplementalArtifactReference(
          id: supplementalIds[index],
          scenarioId: scenarioId,
          requiredEvidenceId: evidenceIds[index],
          role: SupplementalArtifactRole.comparisonBaseline,
          artifactDigest:
              baselineArtifactDigest ?? _digest('baseline-artifact'),
          provenanceDigest:
              baselineProvenanceDigest ?? _digest('baseline-provenance'),
          classification: ArtifactClassification.internal,
        ),
    ],
    plans: <ScenarioLabPlan>[
      ScenarioLabPlan(
        scenarioId: scenarioId,
        executionBindingIds: <ScenarioExecutionBindingId>[
          ScenarioExecutionBindingId('scenario-web'),
        ],
        controlIds: const <ScenarioControlId>[],
        operationIds: operationIds,
        scriptIds: <ScenarioScriptId>[scriptId],
        automatedAcceptanceCriterionIds: <AutomatedAcceptanceCriterionId>[
          acceptanceId,
          ...evidenceAcceptanceIds,
        ],
        requiredEvidenceIds: evidenceIds,
        comparisonBindingIds: comparisonIds,
        humanApprovalRequirementIds: <HumanApprovalRequirementId>[
          HumanApprovalRequirementId('approval'),
        ],
        supplementalArtifactIds: supplementalIds,
      ),
    ],
  );
}

RequiredEvidenceId _fixtureEvidenceId(int index) =>
    RequiredEvidenceId(index == 0 ? 'visual' : 'visual-$index');

ScenarioComparisonBindingId _fixtureComparisonId(int index) =>
    ScenarioComparisonBindingId(
      index == 0 ? 'visual-comparison' : 'visual-comparison-$index',
    );

AutomatedAcceptanceCriterionId _fixtureEvidenceAcceptanceId(int index) =>
    AutomatedAcceptanceCriterionId(
      index == 0 ? 'evidence-accepted' : 'evidence-accepted-$index',
    );

final class _RunStore implements ScenarioLabRunStore {
  const _RunStore(this.run);

  final ScenarioLabStoredRun run;

  @override
  int get length => 1;

  @override
  List<ScenarioLabStoredRun> get runs => <ScenarioLabStoredRun>[run];

  @override
  ScenarioLabStoredRun? findByRequestId(ScenarioLabRunRequestId requestId) =>
      requestId == run.request.requestId ? run : null;

  @override
  ScenarioLabStoredRun? findByRunId(ScenarioLabRunId runId) =>
      runId == run.latest.runId ? run : null;

  @override
  ScenarioLabStoredRun requireRun(ScenarioLabRunId runId) =>
      findByRunId(runId) ?? (throw ScenarioLabRunNotFound(runId));

  @override
  ScenarioLabRunRegistration register({
    required ScenarioLabRunStartRequest request,
    required ScenarioLabRunSnapshot initialSnapshot,
  }) => throw UnsupportedError('read-only fixture');

  @override
  void append(ScenarioLabRunSnapshot snapshot) =>
      throw UnsupportedError('read-only fixture');

  @override
  void complete(ScenarioLabRunResult result) =>
      throw UnsupportedError('read-only fixture');

  @override
  bool interrupt(ScenarioLabRunId runId) =>
      throw UnsupportedError('read-only fixture');

  @override
  List<ScenarioLabRunSnapshot> observationsAfter(
    ScenarioLabRunId runId,
    int sequence,
  ) => throw UnsupportedError('read-only fixture');
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime nowUtc() => DateTime.utc(2026, 8, 14, 12);

  @override
  int monotonicMicroseconds() => 0;
}

final class _Ids implements IdGenerator {
  var next = 0;

  @override
  String nextId() => 'id-${next++}';
}

ExecutionFingerprint _reviewFingerprint(Digest catalogDigest) =>
    ExecutionFingerprint(
      catalogDigest: catalogDigest,
      launchProfileId: 'web',
      targetId: 'browser',
      platform: 'web',
      renderer: 'flutter-web',
      runtimeFidelity: RuntimeFidelity.hostNative,
      backendMode: BackendMode.none,
      networkContainment: NetworkContainment.unconstrained,
      bootstrapAssessment: BootstrapAssessment.controlled,
      toolchain: const <String, String>{'dart': 'test'},
      capabilities: const <String>{'capture.app-adapter'},
    );

File _evidenceDocumentFile(FileSystemWorkspaceStore workspace, Digest digest) =>
    File(
      p.join(
        workspace.stateRoot,
        'evidence',
        'sha256',
        '${digest.value.substring('sha256:'.length)}.json',
      ),
    );

File _blobFile(FileSystemWorkspaceStore workspace, Digest digest) => File(
  p.join(
    workspace.stateRoot,
    'cas',
    'sha256',
    digest.value.substring('sha256:'.length),
  ),
);

Digest _digest(String seed) => Digest.semantic(seed);
