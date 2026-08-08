import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Experience Content Set', () {
    test('atomically binds optional Lab digest and resource', () {
      final identity = _contentIdentity();
      final description = ExperienceContentSetDescription(identity: identity);
      final opened = ExperienceContentSetOpenResult(
        identity: identity,
        workspaceSnapshot: _resource('workspace-snapshot', 1),
        experienceTopologyBundle: _resource('experience-topology-bundle', 2),
        scenarioFacetManifest: _resource('scenario-facet-manifest', 3),
        scenarioLabManifest: _resource('scenario-lab-manifest', 4),
      );

      expect(
        _schema(
          'runtime/experience-content-set',
        ).validate(description.toJson()).isValid,
        isTrue,
      );
      expect(
        _schema(
          'runtime/experience-content-set',
        ).validate(opened.toJson()).isValid,
        isTrue,
      );
      expect(
        ExperienceContentSetDescription.fromJson(
          _wire(description.toJson()),
        ).toJson(),
        description.toJson(),
      );
      expect(
        ExperienceContentSetOpenResult.fromJson(
          _wire(opened.toJson()),
        ).toJson(),
        opened.toJson(),
      );
      expect(
        opened.scenarioLabManifest!.digest,
        isNot(identity.scenarioLabManifestDigest),
        reason: 'resource byte digest and model semantic digest are distinct',
      );
    });

    test('digest excludes revision, snapshot bytes and resource grants', () {
      final identity = _contentIdentity();
      final nextRevision = ExperienceContentSetIdentity(
        revision: identity.revision + 1,
        catalogDigest: identity.catalogDigest,
        workspaceSnapshotDigest: _digest('re-encoded-snapshot'),
        workspaceContentDigest: identity.workspaceContentDigest,
        experienceTopologyBundleDigest: identity.experienceTopologyBundleDigest,
        scenarioFacetManifestDigest: identity.scenarioFacetManifestDigest,
        scenarioLabManifestDigest: identity.scenarioLabManifestDigest,
      );
      final changedLab = ExperienceContentSetIdentity(
        revision: identity.revision,
        catalogDigest: identity.catalogDigest,
        workspaceSnapshotDigest: identity.workspaceSnapshotDigest,
        workspaceContentDigest: identity.workspaceContentDigest,
        experienceTopologyBundleDigest: identity.experienceTopologyBundleDigest,
        scenarioFacetManifestDigest: identity.scenarioFacetManifestDigest,
        scenarioLabManifestDigest: _digest('other-lab'),
      );
      final changedWorkspace = ExperienceContentSetIdentity(
        revision: identity.revision,
        catalogDigest: identity.catalogDigest,
        workspaceSnapshotDigest: identity.workspaceSnapshotDigest,
        workspaceContentDigest: _digest('other-workspace-content'),
        experienceTopologyBundleDigest: identity.experienceTopologyBundleDigest,
        scenarioFacetManifestDigest: identity.scenarioFacetManifestDigest,
        scenarioLabManifestDigest: identity.scenarioLabManifestDigest,
      );

      expect(
        nextRevision.workspaceSnapshotDigest,
        isNot(identity.workspaceSnapshotDigest),
      );
      expect(nextRevision.contentSetDigest, identity.contentSetDigest);
      expect(changedLab.contentSetDigest, isNot(identity.contentSetDigest));
      expect(
        changedWorkspace.contentSetDigest,
        isNot(identity.contentSetDigest),
      );
    });

    test('strict codec rejects v1, unknown, tamper and split Lab pair', () {
      final description = ExperienceContentSetDescription(
        identity: _contentIdentity(),
      ).toJson();
      expect(
        () => ExperienceContentSetDescription.fromJson(
          _copy(description)..['schemaVersion'] = 1,
        ),
        throwsFormatException,
      );
      expect(
        () => ExperienceContentSetDescription.fromJson(
          _copy(description)..['unknown'] = true,
        ),
        throwsFormatException,
      );
      final missingWorkspaceContent = _copy(description)
        ..remove('workspaceContentDigest');
      expect(
        _schema(
          'runtime/experience-content-set',
        ).validate(missingWorkspaceContent).isValid,
        isFalse,
      );
      expect(
        () => ExperienceContentSetDescription.fromJson(missingWorkspaceContent),
        throwsFormatException,
      );
      expect(
        () => ExperienceContentSetDescription.fromJson(
          _copy(description)
            ..['scenarioLabManifestDigest'] = _digest('tamper').value,
        ),
        throwsFormatException,
      );

      final opened = ExperienceContentSetOpenResult(
        identity: _contentIdentity(),
        workspaceSnapshot: _resource('workspace-snapshot', 1),
        experienceTopologyBundle: _resource('experience-topology-bundle', 2),
        scenarioFacetManifest: _resource('scenario-facet-manifest', 3),
        scenarioLabManifest: _resource('scenario-lab-manifest', 4),
      ).toJson();
      final resources = _copy(opened['resources']! as Map<String, Object?>)
        ..remove('scenarioLabManifest');
      final split = _copy(opened)..['resources'] = resources;
      expect(
        _schema('runtime/experience-content-set').validate(split).isValid,
        isFalse,
      );
      expect(
        () => ExperienceContentSetOpenResult.fromJson(split),
        throwsArgumentError,
      );
    });
  });

  group('Scenario Lab execution and Quality', () {
    test(
      'round-trips immutable partial/final typed results through schemas',
      () {
        final fixture = _runFixture();
        final executionSchema = _schema('runtime/scenario-lab-execution');
        final qualitySchema = _schema('evidence/scenario-quality');

        expect(
          executionSchema.validate(fixture.start.toJson()).isValid,
          isTrue,
        );
        expect(
          executionSchema.validate(fixture.snapshot.toJson()).isValid,
          isTrue,
        );
        expect(
          executionSchema.validate(fixture.result.toJson()).isValid,
          isTrue,
        );
        expect(
          qualitySchema.validate(fixture.quality.toJson()).isValid,
          isTrue,
        );
        expect(
          ScenarioLabRunStartRequest.fromJson(
            _wire(fixture.start.toJson()),
          ).toJson(),
          fixture.start.toJson(),
        );
        expect(
          ScenarioLabRunSnapshot.fromJson(
            _wire(fixture.snapshot.toJson()),
          ).toJson(),
          fixture.snapshot.toJson(),
        );
        expect(
          ScenarioLabRunResult.fromJson(
            _wire(fixture.result.toJson()),
          ).toJson(),
          fixture.result.toJson(),
        );
        expect(
          ScenarioQualitySnapshot.fromJson(
            _wire(fixture.quality.toJson()),
          ).toJson(),
          fixture.quality.toJson(),
        );
        expect(
          () => fixture.snapshot.validateAgainstStart(fixture.start),
          returnsNormally,
        );
        expect(
          () => fixture.quality.validateAgainstResult(fixture.result),
          returnsNormally,
        );
      },
    );

    test('runtime inputs fence Gateway separately from the Content Set', () {
      final runtimeInputs = _runtimeInputs();
      final catalogBinding = ScenarioExecutionBinding(
        id: ScenarioExecutionBindingId('ready-web'),
        scenarioId: ScenarioId('ready'),
        targetId: 'browser',
        launchProfileId: 'sample-web',
        gatewayPresetId: 'delivery-ready',
      );
      expect(
        () => runtimeInputs.validateAgainst(catalogBinding),
        returnsNormally,
      );
      expect(
        () => ScenarioLabRuntimeInputBinding(
          executionFingerprintDigest: _digest('fingerprint'),
          executionTargetId: 'browser',
          gatewayPresetId: GatewayPresetId('delivery-ready'),
          compiledGatewayPlanDigest: _digest('gateway-plan'),
        ),
        throwsArgumentError,
      );
      expect(
        () => runtimeInputs.validateAgainst(
          ScenarioExecutionBinding(
            id: ScenarioExecutionBindingId('ready-web'),
            scenarioId: ScenarioId('ready'),
            targetId: 'other-target',
            launchProfileId: 'sample-web',
            gatewayPresetId: 'delivery-ready',
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'running snapshots carry explicit partial states without fake output',
      () {
        final fixture = _runFixture();
        final pendingEvidence = RequiredEvidenceRunResult(
          requiredEvidenceId: RequiredEvidenceId('ready-semantics'),
          providerId: ModuleId('capture.semantics'),
          fidelity: RuntimeFidelity.hostNative,
          variantId: VariantId('phone'),
          freshness: EvidenceFreshness.missing,
          state: RequiredEvidenceResultState.pending,
        );
        final pendingComparison = SemanticScenarioComparisonResult(
          bindingId: ScenarioComparisonBindingId('ready-semantic-comparison'),
          requiredEvidenceId: pendingEvidence.requiredEvidenceId,
          baselineDigest: _digest('semantic-baseline'),
          candidateDigest: _digest('semantic-candidate'),
          policyDigest: _digest('semantic-policy'),
          verificationState: VerificationState.notRun,
        );
        final partial = ScenarioLabRunSnapshot(
          runId: fixture.snapshot.runId,
          startRequestDigest: fixture.start.digest,
          contentSetDigest: fixture.snapshot.contentSetDigest,
          catalogDigest: fixture.snapshot.catalogDigest,
          scenarioLabManifestDigest: fixture.snapshot.scenarioLabManifestDigest,
          scenarioId: fixture.snapshot.scenarioId,
          scriptId: fixture.snapshot.scriptId,
          sequence: 2,
          observedAt: _time(2),
          state: ScenarioLabRunState.running,
          runtimeInputs: _runtimeInputs(),
          steps: <ScenarioLabStepSnapshot>[
            ScenarioLabStepSnapshot(
              stepId: 'prepare',
              state: ScenarioLabStepState.running,
              startedAt: _time(1),
            ),
          ],
          requiredEvidence: <RequiredEvidenceRunResult>[pendingEvidence],
          automatedAcceptance: <AutomatedAcceptanceResult>[
            AutomatedAcceptanceResult(
              criterionId: AutomatedAcceptanceCriterionId('ready-accepted'),
              verificationState: VerificationState.notRun,
            ),
          ],
          comparisons: <ScenarioComparisonResult>[pendingComparison],
          cleanup: ScenarioLabCleanupResult(
            state: ScenarioLabCleanupState.pending,
          ),
        );

        expect(
          _schema(
            'runtime/scenario-lab-execution',
          ).validate(partial.toJson()).isValid,
          isTrue,
        );
        expect(
          ScenarioLabRunSnapshot.fromJson(_wire(partial.toJson())).toJson(),
          partial.toJson(),
        );
        expect(pendingEvidence.artifacts, isEmpty);
        expect(pendingComparison.comparedNodes, isNull);
      },
    );

    test('RequiredEvidence preserves typed absence and collection claims', () {
      final missing = RequiredEvidenceRunResult(
        requiredEvidenceId: RequiredEvidenceId('ready-visual'),
        providerId: ModuleId('capture.web'),
        fidelity: RuntimeFidelity.hostNative,
        variantId: VariantId('phone'),
        freshness: EvidenceFreshness.missing,
        state: RequiredEvidenceResultState.unsupported,
      );
      expect(
        RequiredEvidenceRunResult.fromJson(_wire(missing.toJson())).toJson(),
        missing.toJson(),
      );
      expect(
        () => RequiredEvidenceRunResult(
          requiredEvidenceId: RequiredEvidenceId('ready-visual'),
          providerId: ModuleId('capture.web'),
          fidelity: RuntimeFidelity.hostNative,
          variantId: VariantId('phone'),
          freshness: EvidenceFreshness.fresh,
          state: RequiredEvidenceResultState.missing,
        ),
        throwsArgumentError,
      );
    });

    test('comparisons are sealed, bounded and have no free metrics map', () {
      final fixture = _runFixture();
      final visual = fixture.snapshot.comparisons.single;
      final tampered = _copy(visual.toJson())
        ..['metrics'] = <String, Object?>{};
      expect(
        () => ScenarioComparisonResult.fromJson(tampered),
        throwsFormatException,
      );
      expect(
        () => VisualScenarioComparisonResult(
          bindingId: ScenarioComparisonBindingId('ready-comparison'),
          requiredEvidenceId: RequiredEvidenceId('ready-visual'),
          baselineDigest: _digest('baseline'),
          candidateDigest: _digest('candidate'),
          policyDigest: _digest('policy'),
          verificationState: VerificationState.passed,
          comparedPixels: 10,
          changedPixels: 11,
          maxChannelDeltaObserved: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => ScenarioComparisonResult.fromJson(
          _copy(visual.toJson())..['resultKind'] = 'futureComparison',
        ),
        throwsFormatException,
      );
    });

    test(
      'human decisions are append-only records and four-state projections',
      () {
        final first = HumanDecisionRecord(
          id: HumanDecisionRecordId('decision-1'),
          subjectDigest: _digest('run-result'),
          principalId: ScenarioQualityPrincipalId('reviewer-1'),
          decision: HumanDecision.approved,
          decidedAt: _time(10),
        );
        final second = HumanDecisionRecord(
          id: HumanDecisionRecordId('decision-2'),
          subjectDigest: first.subjectDigest,
          principalId: ScenarioQualityPrincipalId('reviewer-2'),
          decision: HumanDecision.rejected,
          decidedAt: _time(11),
          supersedesDecisionDigest: first.digest,
        );

        expect(() => second.validateSupersedes(first), returnsNormally);
        expect(
          _schema('evidence/scenario-quality').validate(first.toJson()).isValid,
          isTrue,
        );
        expect(
          _schema(
            'evidence/scenario-quality',
          ).validate(second.toJson()).isValid,
          isTrue,
        );
        expect(
          HumanDecisionRecord.fromJson(_wire(second.toJson())).toJson(),
          second.toJson(),
        );
        expect(
          HumanDecisionProjection(state: HumanDecisionState.unreviewed).state,
          HumanDecisionState.unreviewed,
        );
        expect(
          HumanDecisionProjection(
            state: HumanDecisionState.approved,
            decisionDigest: first.digest,
          ).state,
          HumanDecisionState.approved,
        );
        expect(
          HumanDecisionProjection(
            state: HumanDecisionState.rejected,
            decisionDigest: second.digest,
          ).state,
          HumanDecisionState.rejected,
        );
        expect(
          HumanDecisionProjection(
            state: HumanDecisionState.superseded,
            decisionDigest: first.digest,
            supersededByDecisionDigest: second.digest,
          ).state,
          HumanDecisionState.superseded,
        );
        expect(
          () => HumanDecisionRecord.fromJson(
            _copy(first.toJson())..['decision'] = 'superseded',
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'strict execution codecs reject unknown, adjacent and tampered wires',
      () {
        final fixture = _runFixture();
        expect(
          () => ScenarioLabRunStartRequest.fromJson(
            _copy(fixture.start.toJson())..['unknown'] = true,
          ),
          throwsFormatException,
        );
        expect(
          () => ScenarioLabRunStartRequest.fromJson(
            _copy(fixture.start.toJson())..['schemaVersion'] = 2,
          ),
          throwsFormatException,
        );
        expect(
          () => ScenarioLabRunResult.fromJson(
            _copy(fixture.result.toJson())
              ..['completedAt'] = _time(12).toIso8601String(),
          ),
          throwsFormatException,
        );
        expect(
          () => ScenarioQualitySnapshot.fromJson(
            _copy(fixture.quality.toJson())
              ..['subjectDigest'] = _digest('other').value,
          ),
          throwsFormatException,
        );
        expect(
          () => RequiredEvidenceRunResult(
            requiredEvidenceId: RequiredEvidenceId('ready-visual'),
            providerId: ModuleId('capture.web'),
            fidelity: RuntimeFidelity.hostNative,
            variantId: VariantId('phone'),
            freshness: EvidenceFreshness.fresh,
            state: RequiredEvidenceResultState.collected,
            evidenceDigest: _digest('too-many-artifacts'),
            artifacts: List<ScenarioEvidenceArtifactResult>.generate(
              65,
              (index) => ScenarioEvidenceArtifactResult(
                artifactDigest: _digest('artifact-$index'),
                provenanceDigest: _digest('provenance-$index'),
                classification: ArtifactClassification.internal,
              ),
            ),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('typed App Adapter relay', () {
    test('round-trips hello and all sealed command/result variants', () {
      final relay = _relayFixture();
      final validator = _schema('runtime/app-adapter-relay');
      final documents = <Object>[
        relay.hello,
        ...relay.commands,
        ...relay.results,
      ];
      for (final document in documents) {
        final json = switch (document) {
          final AppAdapterRelayHello value => value.toJson(),
          final AppAdapterRelayCommand value => value.toJson(),
          final AppAdapterRelayResult value => value.toJson(),
          _ => throw StateError('unexpected fixture'),
        };
        expect(validator.validate(json).isValid, isTrue, reason: '$document');
      }

      expect(
        AppAdapterRelayHello.fromJson(_wire(relay.hello.toJson())).toJson(),
        relay.hello.toJson(),
      );
      for (var index = 0; index < relay.commands.length; index++) {
        final command = relay.commands[index];
        final result = relay.results[index];
        expect(
          AppAdapterRelayCommand.fromJson(_wire(command.toJson())).toJson(),
          command.toJson(),
        );
        expect(
          AppAdapterRelayResult.fromJson(_wire(result.toJson())).toJson(),
          result.toJson(),
        );
        expect(() => command.validateHello(relay.hello), returnsNormally);
        expect(() => result.validateAgainst(command), returnsNormally);
      }
    });

    test(
      'capture grant matches real loopback PUT path and is outside digest',
      () {
        final relay = _relayFixture();
        final first = relay.commands.last as CaptureAppAdapterRelayCommand;
        final changedGrant = AppAdapterRelayCaptureUploadGrant(
          requestId: 'capture01',
          sessionId: 'session01',
          uploadUri: Uri.parse(
            'http://127.0.0.1:7367/capture-uploads/capture01?token=changed_token_1234',
          ),
          expiresAt: _time(20),
          maxBytes: 8 * 1024 * 1024,
        );
        final second = CaptureAppAdapterRelayCommand(
          runId: first.runId,
          commandId: first.commandId,
          sequence: first.sequence,
          nonce: first.nonce,
          requiredEvidenceId: first.requiredEvidenceId,
          providerId: first.providerId,
          uploadGrant: changedGrant,
        );

        expect(first.commandDigest, second.commandDigest);
        expect(
          first.toJson()['uploadGrant'],
          isNot(second.toJson()['uploadGrant']),
        );
        expect(
          () => AppAdapterRelayCaptureUploadGrant(
            requestId: 'capture01',
            sessionId: 'session01',
            uploadUri: Uri.parse(
              'https://example.com/resources/capture01?token=credential1',
            ),
            expiresAt: _time(20),
            maxBytes: 1024,
          ),
          throwsFormatException,
        );
      },
    );

    test('capture result acknowledges only its exact PUT request', () {
      final relay = _relayFixture();
      final command = relay.commands.last as CaptureAppAdapterRelayCommand;
      final result = relay.results.last as CaptureAppAdapterRelayResult;

      expect(result.uploadRequestId, command.uploadGrant.requestId);
      expect(() => result.validateAgainst(command), returnsNormally);
      expect(
        () => CaptureAppAdapterRelayResult(
          runId: command.runId,
          commandId: command.commandId,
          sequence: command.sequence,
          nonce: command.nonce,
          state: AppAdapterRelayResultState.succeeded,
          uploadRequestId: 'different_capture',
        ).validateAgainst(command),
        throwsArgumentError,
      );
      expect(
        () => CaptureAppAdapterRelayResult(
          runId: command.runId,
          commandId: command.commandId,
          sequence: command.sequence,
          nonce: command.nonce,
          state: AppAdapterRelayResultState.succeeded,
        ),
        throwsArgumentError,
      );
    });

    test('capture relay carries no Host-owned Evidence authority', () {
      final relay = _relayFixture();
      final result = relay.results.last as CaptureAppAdapterRelayResult;
      final validator = _schema('runtime/app-adapter-relay');
      const forbidden = <String>{
        'evidenceDigest',
        'fidelity',
        'freshness',
        'artifacts',
        'provenanceDigest',
        'classification',
      };

      expect(result.toJson().keys.toSet().intersection(forbidden), isEmpty);
      for (final field in forbidden) {
        final tampered = _copy(result.toJson())
          ..[field] = field == 'artifacts' ? <Object?>[] : 'forbidden';
        expect(validator.validate(tampered).isValid, isFalse, reason: field);
        expect(
          () => AppAdapterRelayResult.fromJson(tampered),
          throwsFormatException,
          reason: field,
        );
      }

      final command = relay.commands.last as CaptureAppAdapterRelayCommand;
      expect(
        () => CaptureAppAdapterRelayResult(
          runId: command.runId,
          commandId: command.commandId,
          sequence: command.sequence,
          nonce: command.nonce,
          state: AppAdapterRelayResultState.failed,
          failure: const AppAdapterRelayFailure(
            cause: AppAdapterRelayFailureCause.rejected,
          ),
          uploadRequestId: command.uploadGrant.requestId,
        ),
        throwsArgumentError,
      );
    });

    test(
      'strict relay rejects unknown variants, tamper and envelope mismatch',
      () {
        final relay = _relayFixture();
        final command = relay.commands.first;
        expect(
          () => AppAdapterRelayCommand.fromJson(
            _copy(command.toJson())..['operation'] = 'invoke',
          ),
          throwsFormatException,
        );
        expect(
          () => AppAdapterRelayCommand.fromJson(
            _copy(command.toJson())..['kind'] = 'AppAdapterRelayResult',
          ),
          throwsFormatException,
        );
        expect(
          () => AppAdapterRelayCommand.fromJson(
            _copy(command.toJson())..['metadata'] = <String, Object?>{},
          ),
          throwsFormatException,
        );
        expect(
          () => AppAdapterRelayCommand.fromJson(
            _copy(command.toJson())..['controlId'] = 'other-control',
          ),
          throwsFormatException,
        );
        final mismatched = ReadAppAdapterRelayResult(
          runId: ScenarioLabRunId('other-run'),
          commandId: command.commandId,
          sequence: command.sequence,
          nonce: command.nonce,
          state: AppAdapterRelayResultState.succeeded,
          value: const BooleanScenarioControlValue(true),
        );
        expect(() => mismatched.validateAgainst(command), throwsArgumentError);
      },
    );
  });

  test('selected schemas and RPC/capture/content sources remain byte exact', () {
    const expected = <String, String>{
      'schemas/catalog/catalog-manifest.schema.json':
          'b315d5f7574e7cfd7b1eb5256293908483642c4e97d8d77e9a8d4b639ed2551a',
      'schemas/catalog/experience-topology-bundle.schema.json':
          'd43361e6b33b717513072dbd9e7240fca822d3ac640d8bca8ba3227434879f0e',
      'schemas/catalog/scenario-facet-manifest.schema.json':
          '6e0ff67ad866bbfcaef6772382e21f543adb29e7347ea54767d5d33fba4e26d0',
      'schemas/catalog/scenario-lab-manifest.schema.json':
          '1eaab6addc35d878ea6729ca45293f1d0e4c80e16e39b01c65ce32af121fbcf3',
      'schemas/runtime/experience-content-set.schema.json':
          'e1d1cd7dafcaa617515ef6208d802e7ab00fd734cac42ebdb7e1c5fd0af4dcb7',
      'schemas/evidence/app-adapter-capture-command.schema.json':
          'd051154c6a4f8796374d2ba30bb1491e764380a9599530b915780205496b3bcf',
      'schemas/runtime/session-runtime.schema.json':
          'fb6004f53be68d7ec1d8f569d65f1bef2bb50f912525bac22705c184e3235b68',
      'libs/experience_contracts/lib/src/protocol/json_rpc.dart':
          'c21a273cf8f7ed6c6cb1ad8bd1baf26d0bcb7c0364053a8fa45fe7ddbe15004e',
      'libs/experience_contracts/lib/src/sessions/app_adapter_capture_contracts.dart':
          '01d2f4115aa98f1270191b0aba6e9d4a04249ed48353f870656e92006fa84783',
      'libs/experience_contracts/lib/src/studio/experience_content_contracts.dart':
          '2005a1c8198aba14e89066e76ea113319ae7c7f0675ca3af52f27fa2b1c210ee',
    };

    for (final entry in expected.entries) {
      final bytes = File(p.join(_root(), entry.key)).readAsBytesSync();
      expect(
        Digest.bytes(bytes).value,
        'sha256:${entry.value}',
        reason: entry.key,
      );
    }
    expect(
      const JsonRpcRequest(method: 'unchanged.v1', id: 7).encode(),
      '{"jsonrpc":"2.0","method":"unchanged.v1","id":7}',
    );
  });
}

final class _RunFixture {
  const _RunFixture({
    required this.start,
    required this.snapshot,
    required this.result,
    required this.quality,
  });

  final ScenarioLabRunStartRequest start;
  final ScenarioLabRunSnapshot snapshot;
  final ScenarioLabRunResult result;
  final ScenarioQualitySnapshot quality;
}

_RunFixture _runFixture() {
  final content = _contentIdentity();
  final start = ScenarioLabRunStartRequest(
    requestId: ScenarioLabRunRequestId('request-1'),
    expectedContentSetDigest: content.contentSetDigest,
    expectedScenarioLabManifestDigest: content.scenarioLabManifestDigest!,
    scenarioId: ScenarioId('ready'),
    scriptId: ScenarioScriptId('exercise-ready'),
    requestedAt: _time(0),
  );
  final evidence = RequiredEvidenceRunResult(
    requiredEvidenceId: RequiredEvidenceId('ready-visual'),
    providerId: ModuleId('capture.web'),
    fidelity: RuntimeFidelity.hostNative,
    variantId: VariantId('phone'),
    freshness: EvidenceFreshness.fresh,
    state: RequiredEvidenceResultState.collected,
    evidenceDigest: _digest('evidence'),
    artifacts: <ScenarioEvidenceArtifactResult>[
      ScenarioEvidenceArtifactResult(
        artifactDigest: _digest('artifact'),
        provenanceDigest: _digest('provenance'),
        classification: ArtifactClassification.internal,
      ),
    ],
  );
  final comparison = VisualScenarioComparisonResult(
    bindingId: ScenarioComparisonBindingId('ready-comparison'),
    requiredEvidenceId: RequiredEvidenceId('ready-visual'),
    baselineDigest: _digest('baseline'),
    candidateDigest: _digest('candidate'),
    policyDigest: _digest('visual-policy'),
    verificationState: VerificationState.passed,
    comparedPixels: 100,
    changedPixels: 0,
    maxChannelDeltaObserved: 0,
  );
  final snapshot = ScenarioLabRunSnapshot(
    runId: ScenarioLabRunId('run-1'),
    startRequestDigest: start.digest,
    contentSetDigest: content.contentSetDigest,
    catalogDigest: content.catalogDigest,
    scenarioLabManifestDigest: content.scenarioLabManifestDigest!,
    scenarioId: start.scenarioId,
    scriptId: start.scriptId,
    sequence: 4,
    observedAt: _time(4),
    state: ScenarioLabRunState.succeeded,
    runtimeInputs: _runtimeInputs(),
    steps: <ScenarioLabStepSnapshot>[
      ScenarioLabStepSnapshot(
        stepId: 'prepare',
        state: ScenarioLabStepState.succeeded,
        startedAt: _time(1),
        completedAt: _time(2),
        terminalCause: ScenarioLabStepTerminalCause.completed,
      ),
    ],
    controls: <ScenarioControlResult>[
      ScenarioControlResult(
        controlId: ScenarioControlId('feature-ready'),
        source: ScenarioControlResultSource.write,
        value: const BooleanScenarioControlValue(true),
      ),
    ],
    requiredEvidence: <RequiredEvidenceRunResult>[evidence],
    automatedAcceptance: <AutomatedAcceptanceResult>[
      AutomatedAcceptanceResult(
        criterionId: AutomatedAcceptanceCriterionId('ready-accepted'),
        verificationState: VerificationState.passed,
      ),
    ],
    comparisons: <ScenarioComparisonResult>[comparison],
    cleanup: ScenarioLabCleanupResult(
      state: ScenarioLabCleanupState.succeeded,
      resetControlIds: <ScenarioControlId>[ScenarioControlId('feature-ready')],
    ),
    terminalCause: ScenarioLabTerminalCause.completed,
  );
  final result = ScenarioLabRunResult(
    finalSnapshot: snapshot,
    startedAt: _time(1),
    completedAt: _time(4),
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
    comparisonResultDigests: <Digest>[comparison.digest],
  );
  return _RunFixture(
    start: start,
    snapshot: snapshot,
    result: result,
    quality: quality,
  );
}

ScenarioLabRuntimeInputBinding _runtimeInputs() =>
    ScenarioLabRuntimeInputBinding(
      executionFingerprintDigest: _digest('fingerprint'),
      executionTargetId: 'browser',
      gatewayPresetId: GatewayPresetId('delivery-ready'),
      compiledGatewayPlanDigest: _digest('gateway-plan'),
      routingTableDigest: _digest('routing-table'),
    );

final class _RelayFixture {
  const _RelayFixture({
    required this.hello,
    required this.commands,
    required this.results,
  });

  final AppAdapterRelayHello hello;
  final List<AppAdapterRelayCommand> commands;
  final List<AppAdapterRelayResult> results;
}

_RelayFixture _relayFixture() {
  final runId = ScenarioLabRunId('run-1');
  final nonce = AppAdapterRelayNonce('abcdefghijklmnopqrstuvwx');
  final capability = AppAdapterCapabilityReference(
    id: AppAdapterCapabilityId('sample.controls'),
    version: 1,
  );
  final hello = AppAdapterRelayHello(
    runId: runId,
    adapterInstanceId: 'adapter-1',
    sequence: 0,
    nonce: nonce,
    capabilities: <AppAdapterCapabilityReference>[capability],
    evidenceProviderIds: <ModuleId>[ModuleId('capture.web')],
  );
  final commands = <AppAdapterRelayCommand>[
    ReadAppAdapterRelayCommand(
      runId: runId,
      commandId: ScenarioLabCommandId('command-1'),
      sequence: 1,
      nonce: nonce,
      controlId: ScenarioControlId('feature-ready'),
      capability: capability,
      operationId: CapabilityOperationId('read'),
    ),
    WriteAppAdapterRelayCommand(
      runId: runId,
      commandId: ScenarioLabCommandId('command-2'),
      sequence: 2,
      nonce: nonce,
      controlId: ScenarioControlId('feature-ready'),
      capability: capability,
      operationId: CapabilityOperationId('write'),
      value: const BooleanScenarioControlValue(true),
    ),
    ResetAppAdapterRelayCommand(
      runId: runId,
      commandId: ScenarioLabCommandId('command-3'),
      sequence: 3,
      nonce: nonce,
      controlId: ScenarioControlId('feature-ready'),
      capability: capability,
      operationId: CapabilityOperationId('reset'),
    ),
    CaptureAppAdapterRelayCommand(
      runId: runId,
      commandId: ScenarioLabCommandId('command-4'),
      sequence: 4,
      nonce: nonce,
      requiredEvidenceId: RequiredEvidenceId('ready-visual'),
      providerId: ModuleId('capture.web'),
      uploadGrant: AppAdapterRelayCaptureUploadGrant(
        requestId: 'capture01',
        sessionId: 'session01',
        uploadUri: Uri.parse(
          'http://127.0.0.1:7367/capture-uploads/capture01?token=upload_token_1234',
        ),
        expiresAt: _time(15),
        maxBytes: 8 * 1024 * 1024,
      ),
    ),
  ];
  final results = <AppAdapterRelayResult>[
    ReadAppAdapterRelayResult(
      runId: runId,
      commandId: commands[0].commandId,
      sequence: 1,
      nonce: nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(false),
    ),
    WriteAppAdapterRelayResult(
      runId: runId,
      commandId: commands[1].commandId,
      sequence: 2,
      nonce: nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(true),
    ),
    ResetAppAdapterRelayResult(
      runId: runId,
      commandId: commands[2].commandId,
      sequence: 3,
      nonce: nonce,
      state: AppAdapterRelayResultState.succeeded,
      value: const BooleanScenarioControlValue(false),
    ),
    CaptureAppAdapterRelayResult(
      runId: runId,
      commandId: commands[3].commandId,
      sequence: 4,
      nonce: nonce,
      state: AppAdapterRelayResultState.succeeded,
      uploadRequestId: 'capture01',
    ),
  ];
  return _RelayFixture(hello: hello, commands: commands, results: results);
}

ExperienceContentSetIdentity _contentIdentity() => ExperienceContentSetIdentity(
  revision: 7,
  catalogDigest: _digest('catalog'),
  workspaceSnapshotDigest: _digest('snapshot'),
  workspaceContentDigest: _digest('workspace-content'),
  experienceTopologyBundleDigest: _digest('topology'),
  scenarioFacetManifestDigest: _digest('facets'),
  scenarioLabManifestDigest: _digest('lab'),
);

ResourceHandle _resource(String purpose, int seed) => ResourceHandle(
  uri: Uri.parse(
    'http://127.0.0.1:7367/resources/'
    '${seed.toRadixString(16).padLeft(32, '0')}',
  ),
  digest: _digest('resource-$seed'),
  mediaType: 'application/json',
  size: seed,
  purpose: purpose,
  expiresAt: _time(30),
);

DateTime _time(int minute) => DateTime.utc(2026, 8, 14, 12, minute);

Digest _digest(String value) => Digest.semantic(value);

Map<String, Object?> _wire(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

Map<String, Object?> _copy(Map<String, Object?> value) => _wire(value);

Draft202012Validator _schema(String name) => Draft202012Validator(
  jsonDecode(
        File(
          p.join(_root(), 'schemas', '$name.schema.json'),
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
