@TestOn('vm')
library;

import 'package:experience_contracts/experience_contracts.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio/src/lab/scenario_lab_panel.dart';
import 'package:studio/src/quality/scenario_quality_panel.dart';
import 'package:studio/src/quality/scenario_quality_projection.dart';

import '../support/scenario_lab_fixture.dart';

void main() {
  testComponents('Lab renders declared script, controls and Evidence', (
    tester,
  ) async {
    final fixture = ScenarioLabTestFixture();
    final result = fixture.result();
    tester.pumpComponent(
      ScenarioLabPanel(
        catalog: fixture.catalog,
        manifest: fixture.manifest,
        scenarioId: fixture.scenarioId,
        scriptId: fixture.scriptId,
        runResult: result,
        qualitySnapshot: fixture.quality(result),
      ),
    );
    await tester.pump();

    expect(
      _domWithAttributes(<String, String>{
        'aria-label': 'Scenario Lab: Ready state',
        'data-lab-scenario-id': 'scenario-ready',
        'data-lab-script-id': 'exercise-ready',
        'data-lab-run-state': 'succeeded',
        'data-lab-run-id': 'run-terminal',
      }),
      findsOneComponent,
    );
    for (final step in <(String, String)>[
      ('bind', 'executionBinding'),
      ('enable', 'operation'),
      ('capture', 'operation'),
      ('reset', 'operation'),
    ]) {
      expect(
        _domWithAttributes(<String, String>{
          'data-lab-step-id': step.$1,
          'data-lab-step-kind': step.$2,
          'data-lab-step-state': 'succeeded',
        }),
        findsOneComponent,
      );
    }
    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-control-id': 'highlight',
        'data-lab-control-kind': 'boolean',
        'data-lab-control-result': 'reset',
      }),
      findsOneComponent,
    );
    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-evidence-id': 'required-visual',
        'data-lab-evidence-provider': 'capture.typed',
        'data-lab-evidence-fidelity': 'simulated',
        'data-lab-evidence-state': 'collected',
        'data-lab-evidence-freshness': 'fresh',
        'data-lab-evidence-verification': 'passed',
      }),
      findsOneComponent,
    );
    expect(find.text('Required Evidence'), findsOneComponent);
    expect(find.text('Critérios automatizados'), findsOneComponent);
    expect(_domTag('button'), findsNothing);
  });

  testComponents('Lab exposes the not-started and not-reported states', (
    tester,
  ) async {
    final fixture = ScenarioLabTestFixture();
    tester.pumpComponent(
      ScenarioLabPanel(
        catalog: fixture.catalog,
        manifest: fixture.manifest,
        scenarioId: fixture.scenarioId,
        scriptId: fixture.scriptId,
      ),
    );
    await tester.pump();

    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-run-state': 'notStarted',
      }),
      findsOneComponent,
    );
    expect(find.textContaining('Nenhuma execução'), findsOneComponent);
    expect(
      _domWithAttributes(const <String, String>{
        'data-lab-evidence-id': 'required-visual',
        'data-lab-evidence-state': 'notReported',
      }),
      findsOneComponent,
    );
  });

  final qualityCases =
      <
        (
          String,
          ScenarioQualityState,
          _QualityInputs Function(ScenarioLabTestFixture),
        )
      >[
        (
          'passing',
          ScenarioQualityState.passing,
          (fixture) {
            final result = fixture.result();
            return (result: result, quality: fixture.quality(result));
          },
        ),
        (
          'changed',
          ScenarioQualityState.changed,
          (fixture) {
            final result = fixture.result(changedPixels: 4);
            return (result: result, quality: fixture.quality(result));
          },
        ),
        (
          'failing',
          ScenarioQualityState.failing,
          (fixture) {
            final result = fixture.result(
              acceptanceState: VerificationState.failed,
              comparisonState: VerificationState.failed,
              changedPixels: 4,
            );
            return (result: result, quality: fixture.quality(result));
          },
        ),
        (
          'stale',
          ScenarioQualityState.stale,
          (fixture) {
            final result = fixture.result(
              evidenceState: RequiredEvidenceResultState.pending,
              freshness: EvidenceFreshness.stale,
            );
            return (
              result: result,
              quality: fixture.quality(
                result,
                evidenceVerification: VerificationState.notRun,
              ),
            );
          },
        ),
        (
          'unverified',
          ScenarioQualityState.unverified,
          (fixture) => (result: null, quality: null),
        ),
        (
          'missing',
          ScenarioQualityState.missing,
          (fixture) => _evidenceStateInputs(
            fixture,
            RequiredEvidenceResultState.missing,
          ),
        ),
        (
          'unsupported',
          ScenarioQualityState.unsupported,
          (fixture) => _evidenceStateInputs(
            fixture,
            RequiredEvidenceResultState.unsupported,
          ),
        ),
        (
          'policyDenied',
          ScenarioQualityState.policyDenied,
          (fixture) => _evidenceStateInputs(
            fixture,
            RequiredEvidenceResultState.policyDenied,
          ),
        ),
      ];
  for (final qualityCase in qualityCases) {
    testComponents('Quality exposes ${qualityCase.$1} semantics', (
      tester,
    ) async {
      final fixture = ScenarioLabTestFixture();
      final inputs = qualityCase.$3(fixture);
      tester.pumpComponent(
        ScenarioQualityPanel(
          catalog: fixture.catalog,
          manifest: fixture.manifest,
          scenarioId: fixture.scenarioId,
          scriptId: fixture.scriptId,
          runResult: inputs.result,
          qualitySnapshot: inputs.quality,
        ),
      );
      await tester.pump();

      expect(
        _domWithAttributes(<String, String>{
          'data-quality-state': qualityCase.$2.name,
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'aria-label': 'Estados Quality observados',
        }),
        findsOneComponent,
      );
    });
  }

  testComponents(
    'Quality marks a terminal run stale against the current content generation',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result();
      tester.pumpComponent(
        ScenarioQualityPanel(
          catalog: fixture.catalog,
          manifest: fixture.manifest,
          scenarioId: fixture.scenarioId,
          scriptId: fixture.scriptId,
          runSnapshot: result.finalSnapshot,
          runResult: result,
          qualitySnapshot: fixture.quality(result),
          currentContentSetDigest: digest('new-content-generation'),
        ),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-content-currentness': 'stale',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-state': 'stale',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-state': 'passing',
        }),
        findsNothing,
      );
    },
  );

  testComponents(
    'Quality keeps rejected human review separate from passing and changed',
    (tester) async {
      final fixture = ScenarioLabTestFixture();
      final result = fixture.result(changedPixels: 3);
      tester.pumpComponent(
        ScenarioQualityPanel(
          catalog: fixture.catalog,
          manifest: fixture.manifest,
          scenarioId: fixture.scenarioId,
          scriptId: fixture.scriptId,
          runResult: result,
          qualitySnapshot: fixture.quality(
            result,
            humanDecision: HumanDecisionState.rejected,
          ),
        ),
      );
      await tester.pump();

      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-human-decision': 'rejected',
          'aria-label': 'Decisão humana',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-state': 'passing',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-state': 'changed',
        }),
        findsOneComponent,
      );
      expect(
        _domWithAttributes(const <String, String>{
          'data-quality-comparison-id': 'visual-comparison',
          'data-quality-changed-units': '3',
        }),
        findsOneComponent,
      );
      expect(
        find.textContaining('independente da verificação automatizada'),
        findsOneComponent,
      );
    },
  );
}

typedef _QualityInputs = ({
  ScenarioLabRunResult? result,
  ScenarioQualitySnapshot? quality,
});

_QualityInputs _evidenceStateInputs(
  ScenarioLabTestFixture fixture,
  RequiredEvidenceResultState state,
) {
  final result = fixture.result(
    evidenceState: state,
    freshness: EvidenceFreshness.missing,
  );
  return (
    result: result,
    quality: fixture.quality(
      result,
      evidenceVerification: VerificationState.notRun,
    ),
  );
}

Finder _domWithAttributes(Map<String, String> attributes) =>
    find.byComponentPredicate(
      (component) =>
          component is DomComponent &&
          attributes.entries.every(
            (entry) => component.attributes?[entry.key] == entry.value,
          ),
      description: 'DOM component with attributes $attributes',
    );

Finder _domTag(String tag) => find.byComponentPredicate(
  (component) => component is DomComponent && component.tag == tag,
  description: 'DOM <$tag>',
);
