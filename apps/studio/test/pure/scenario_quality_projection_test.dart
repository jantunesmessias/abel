import 'package:experience_contracts/experience_contracts.dart';
import 'package:studio/src/quality/scenario_quality_projection.dart';
import 'package:test/test.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  group('ScenarioQualityResolver states', () {
    test('passing comes from a complete typed terminal result', () {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result();
      final projection = _resolve(
        fixture,
        result: result,
        quality: fixture.quality(result),
      );

      expect(projection.states, <ScenarioQualityState>[
        ScenarioQualityState.passing,
      ]);
      expect(projection.verificationState, VerificationState.passed);
    });

    test(
      'changed comes only from comparison metrics, not digest inequality',
      () {
        final fixture = ScenarioLabTestFixture();
        final unchanged = fixture.result(changedPixels: 0);
        final changed = fixture.result(changedPixels: 4);

        expect(
          _resolve(
            fixture,
            result: unchanged,
            quality: fixture.quality(unchanged),
          ).hasState(ScenarioQualityState.changed),
          isFalse,
          reason: 'baseline and candidate digests differ in both fixtures',
        );
        final projection = _resolve(
          fixture,
          result: changed,
          quality: fixture.quality(changed),
        );
        expect(projection.hasState(ScenarioQualityState.changed), isTrue);
        expect(projection.hasState(ScenarioQualityState.passing), isTrue);
        expect(
          projection.findings
              .where((item) => item.state == ScenarioQualityState.changed)
              .single
              .detail,
          'measured-changed-units-4',
        );
      },
    );

    test('failing comes from explicit failed verification', () {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result(
        acceptanceState: VerificationState.failed,
        comparisonState: VerificationState.failed,
        changedPixels: 5,
      );
      final projection = _resolve(
        fixture,
        result: result,
        quality: fixture.quality(result),
      );

      expect(projection.hasState(ScenarioQualityState.failing), isTrue);
      expect(projection.hasState(ScenarioQualityState.changed), isTrue);
      expect(projection.hasState(ScenarioQualityState.passing), isFalse);
    });

    test(
      'failed comparison blocks passing when automated acceptance passed',
      () {
        final fixture = ScenarioLabTestFixture();
        final result = fixture.result(
          acceptanceState: VerificationState.passed,
          comparisonState: VerificationState.failed,
          changedPixels: 5,
        );
        final projection = _resolve(
          fixture,
          result: result,
          quality: fixture.quality(result),
        );

        expect(projection.verificationState, VerificationState.passed);
        expect(projection.hasState(ScenarioQualityState.failing), isTrue);
        expect(projection.hasState(ScenarioQualityState.changed), isTrue);
        expect(projection.hasState(ScenarioQualityState.passing), isFalse);
      },
    );

    test('stale preserves the Required Evidence freshness axis', () {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result(
        evidenceState: RequiredEvidenceResultState.pending,
        freshness: EvidenceFreshness.stale,
      );
      final projection = _resolve(
        fixture,
        result: result,
        quality: fixture.quality(
          result,
          evidenceVerification: VerificationState.notRun,
        ),
      );

      expect(projection.hasState(ScenarioQualityState.stale), isTrue);
      expect(projection.hasState(ScenarioQualityState.unverified), isTrue);
    });

    test(
      'a newer content generation makes the run stale without rewriting Evidence',
      () {
        final fixture = ScenarioLabTestFixture();
        final result = fixture.result();
        final projection = _resolve(
          fixture,
          result: result,
          quality: fixture.quality(result),
          currentContentSetDigest: digest('new-content-generation'),
        );

        expect(projection.hasState(ScenarioQualityState.stale), isTrue);
        expect(projection.hasState(ScenarioQualityState.passing), isFalse);
        expect(
          projection.findings.any(
            (item) =>
                item.state == ScenarioQualityState.stale &&
                item.source == ScenarioQualityFindingSource.run &&
                item.detail == 'content-generation-changed',
          ),
          isTrue,
        );
        expect(
          projection.lab.requiredEvidence.single.result?.freshness,
          EvidenceFreshness.fresh,
        );
      },
    );

    test('unverified is explicit before a terminal result exists', () {
      final fixture = ScenarioLabTestFixture();
      final projection = _resolve(fixture);

      expect(projection.states, <ScenarioQualityState>[
        ScenarioQualityState.unverified,
      ]);
      expect(projection.verificationState, isNull);
    });

    test(
      'verification errors remain unverified instead of claiming failure',
      () {
        final fixture = ScenarioLabTestFixture();
        final result = fixture.result(
          acceptanceState: VerificationState.error,
          comparisonState: VerificationState.error,
        );
        final projection = _resolve(
          fixture,
          result: result,
          quality: fixture.quality(result),
        );

        expect(projection.hasState(ScenarioQualityState.unverified), isTrue);
        expect(projection.hasState(ScenarioQualityState.failing), isFalse);
        expect(projection.verificationState, VerificationState.error);
      },
    );

    for (final testCase
        in <(String, RequiredEvidenceResultState, ScenarioQualityState)>[
          (
            'missing',
            RequiredEvidenceResultState.missing,
            ScenarioQualityState.missing,
          ),
          (
            'unsupported',
            RequiredEvidenceResultState.unsupported,
            ScenarioQualityState.unsupported,
          ),
          (
            'policyDenied',
            RequiredEvidenceResultState.policyDenied,
            ScenarioQualityState.policyDenied,
          ),
        ]) {
      test('${testCase.$1} comes from the exact Evidence result state', () {
        final fixture = ScenarioLabTestFixture();
        final result = fixture.result(
          evidenceState: testCase.$2,
          freshness: EvidenceFreshness.missing,
        );
        final projection = _resolve(
          fixture,
          result: result,
          quality: fixture.quality(
            result,
            evidenceVerification: VerificationState.notRun,
          ),
        );

        expect(projection.hasState(testCase.$3), isTrue);
        expect(
          projection.findings.any(
            (item) =>
                item.state == testCase.$3 &&
                item.source == ScenarioQualityFindingSource.requiredEvidence,
          ),
          isTrue,
        );
      });
    }

    test('human approval and rejection never rewrite automated Quality', () {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result(changedPixels: 2);
      final approved = _resolve(
        fixture,
        result: result,
        quality: fixture.quality(
          result,
          humanDecision: HumanDecisionState.approved,
        ),
      );
      final rejected = _resolve(
        fixture,
        result: result,
        quality: fixture.quality(
          result,
          humanDecision: HumanDecisionState.rejected,
        ),
      );

      expect(approved.states, rejected.states);
      expect(approved.humanDecisionState, HumanDecisionState.approved);
      expect(rejected.humanDecisionState, HumanDecisionState.rejected);
    });
  });
}

ScenarioQualityProjection _resolve(
  ScenarioLabTestFixture fixture, {
  ScenarioLabRunSnapshot? snapshot,
  ScenarioLabRunResult? result,
  ScenarioQualitySnapshot? quality,
  Digest? currentContentSetDigest,
}) => const ScenarioQualityResolver().resolve(
  catalog: fixture.catalog,
  manifest: fixture.manifest,
  scenarioId: fixture.scenarioId,
  scriptId: fixture.scriptId,
  runSnapshot: snapshot,
  runResult: result,
  qualitySnapshot: quality,
  currentContentSetDigest: currentContentSetDigest,
);
