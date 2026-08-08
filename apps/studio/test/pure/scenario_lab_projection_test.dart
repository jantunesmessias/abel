import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/lab/scenario_lab_projection.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  group('ScenarioLabResolver', () {
    test('joins declared plan and one fully fenced terminal result', () {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result();
      final quality = fixture.quality(result);

      final projection = const ScenarioLabResolver().resolve(
        catalog: fixture.catalog,
        manifest: fixture.manifest,
        scenarioId: fixture.scenarioId,
        scriptId: fixture.scriptId,
        runResult: result,
        qualitySnapshot: quality,
      );

      expect(projection.scenario.id, fixture.scenarioId);
      expect(projection.script.id, fixture.scriptId);
      expect(
        projection.presentationState,
        ScenarioLabPresentationState.succeeded,
      );
      expect(projection.steps.map((item) => item.definition.id), <String>[
        'bind',
        'enable',
        'capture',
        'reset',
      ]);
      expect(projection.steps.first.executionBinding?.id.value, 'ready-web');
      expect(
        projection.steps[1].operation?.kind,
        ScenarioLabOperationKind.assignControl,
      );
      expect(projection.controls.single.definition.id.value, 'highlight');
      expect(
        projection.controls.single.result?.source,
        ScenarioControlResultSource.reset,
      );
      expect(
        projection.requiredEvidence.single.result?.state,
        RequiredEvidenceResultState.collected,
      );
      expect(
        projection.requiredEvidence.single.verification?.verificationState,
        VerificationState.passed,
      );
      expect(projection.automatedAcceptance, hasLength(2));
      expect(
        projection.automatedAcceptance.every(
          (item) => item.result?.verificationState == VerificationState.passed,
        ),
        isTrue,
      );
      expect(
        projection.comparisons.single.result?.verificationState,
        VerificationState.passed,
      );
      expect(
        () => projection.steps.add(projection.steps.first),
        throwsUnsupportedError,
      );
    });

    test('keeps an absent run explicit instead of synthesizing progress', () {
      final fixture = ScenarioLabTestFixture();
      final projection = const ScenarioLabResolver().resolve(
        catalog: fixture.catalog,
        manifest: fixture.manifest,
        scenarioId: fixture.scenarioId,
        scriptId: fixture.scriptId,
      );

      expect(
        projection.presentationState,
        ScenarioLabPresentationState.notStarted,
      );
      expect(projection.runSnapshot, isNull);
      expect(projection.steps.every((item) => item.execution == null), isTrue);
      expect(projection.controls.single.result, isNull);
      expect(projection.requiredEvidence.single.result, isNull);
    });

    test('fails closed on content fencing and split observations', () {
      final fixture = ScenarioLabTestFixture();
      final original = fixture.runningSnapshot();
      final wrongFence = ScenarioLabRunSnapshot(
        runId: original.runId,
        startRequestDigest: original.startRequestDigest,
        contentSetDigest: original.contentSetDigest,
        catalogDigest: original.catalogDigest,
        scenarioLabManifestDigest: digest('another-manifest'),
        scenarioId: original.scenarioId,
        scriptId: original.scriptId,
        sequence: original.sequence,
        observedAt: original.observedAt,
        state: original.state,
        runtimeInputs: original.runtimeInputs,
        steps: original.steps,
        controls: original.controls,
        requiredEvidence: original.requiredEvidence,
        automatedAcceptance: original.automatedAcceptance,
        comparisons: original.comparisons,
        cleanup: original.cleanup,
      );

      expect(
        () => const ScenarioLabResolver().resolve(
          catalog: fixture.catalog,
          manifest: fixture.manifest,
          scenarioId: fixture.scenarioId,
          scriptId: fixture.scriptId,
          runSnapshot: wrongFence,
        ),
        throwsArgumentError,
      );
      expect(
        () => const ScenarioLabResolver().resolve(
          catalog: fixture.catalog,
          manifest: fixture.manifest,
          scenarioId: fixture.scenarioId,
          scriptId: fixture.scriptId,
          runSnapshot: original,
          runResult: fixture.result(),
        ),
        throwsArgumentError,
      );
    });

    test('requires the bound result before accepting Quality', () {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result();
      expect(
        () => const ScenarioLabResolver().resolve(
          catalog: fixture.catalog,
          manifest: fixture.manifest,
          scenarioId: fixture.scenarioId,
          scriptId: fixture.scriptId,
          runSnapshot: result.finalSnapshot,
          qualitySnapshot: fixture.quality(result),
        ),
        throwsArgumentError,
      );
    });
  });
}
