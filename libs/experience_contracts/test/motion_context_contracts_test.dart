import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('Motion modes are bounded and none always has zero duration', () {
    final step = MotionTransitionStep(
      id: 'show-ready',
      transitionId: TransitionId('next'),
      fromNodeId: NodeInstanceId('first-node'),
      toNodeId: NodeInstanceId('second-node'),
      startMs: 20,
      fullDurationMs: 400,
      reducedDurationMs: 80,
      easing: MotionEasing.easeInOut,
      observations: <MotionObservation>[
        MotionObservation(
          id: 'ready-visible',
          label: 'Ready content is visible',
          atFraction: 1,
          kind: MotionObservationKind.stateVisible,
        ),
      ],
    );

    expect(step.durationFor(MotionMode.full), 400);
    expect(step.durationFor(MotionMode.reduced), 80);
    expect(step.durationFor(MotionMode.none), 0);
    final sequence = MotionSequenceManifest(
      id: 'flow',
      projectionId: ExperienceProjectionId('projection'),
      title: 'Flow',
      steps: <MotionTransitionStep>[
        step,
        MotionTransitionStep(
          id: 'late-step',
          transitionId: TransitionId('later'),
          fromNodeId: NodeInstanceId('second-node'),
          toNodeId: NodeInstanceId('third-node'),
          startMs: 900,
          fullDurationMs: 300,
          reducedDurationMs: 60,
          easing: MotionEasing.linear,
          observations: <MotionObservation>[
            MotionObservation(
              id: 'third-visible',
              label: 'Third content is visible',
              atFraction: 1,
              kind: MotionObservationKind.stateVisible,
            ),
          ],
        ),
      ],
      staticSummary: 'First, then second, then third.',
    );
    expect(sequence.totalDurationFor(MotionMode.full), 1200);
    expect(sequence.totalDurationFor(MotionMode.reduced), 960);
    expect(sequence.totalDurationFor(MotionMode.none), 0);
    expect(
      () => MotionSequenceManifest.fromJson(<String, Object?>{
        'id': 'flow',
        'projectionId': 'projection',
        'title': 'Flow',
        'steps': <Object?>[step.toJson()],
        'staticSummary': 'First, then second.',
        'motionRequiredForComprehension': true,
      }),
      throwsFormatException,
    );
  });

  test('Context bundle is closed, measured and byte deterministic', () {
    final budgets = _budgets(4096);
    final item = ContextItem(
      category: ContextCategory.sources,
      id: 'scenario.ready',
      mediaType: 'application/json',
      content: '{"ready":true}',
    );
    final bundle = ExperienceContextBundle(
      contentSetDigest: Digest.semantic('content'),
      selection: ContextSelection(
        boardId: BoardId('board'),
        projectionId: ExperienceProjectionId('projection'),
        journeyId: JourneyId('journey'),
        scenarioId: ScenarioId('ready'),
      ),
      inclusion: const ContextInclusion(
        sources: true,
        images: false,
        evidence: false,
        history: false,
        changes: false,
      ),
      requestedBudgets: budgets,
      effectiveBudgets: budgets,
      items: <ContextItem>[item],
      usage: <ContextCategory, ContextUsage>{
        for (final category in ContextCategory.values)
          category: ContextUsage(
            items: category == ContextCategory.sources ? 1 : 0,
            bytes: category == ContextCategory.sources
                ? utf8.encode(item.content).length
                : 0,
          ),
      },
      omissions: <ContextOmission>[
        for (final category in ContextCategory.values.skip(1))
          ContextOmission(
            category: category,
            subject: category.name,
            reason: ContextOmissionReason.omittedByRequest,
          ),
      ],
    );
    final decoded = ExperienceContextBundle.fromJson(bundle.toJson());

    expect(decoded.digest, bundle.digest);
    expect(jsonEncode(decoded.toJson()), jsonEncode(bundle.toJson()));
    final poisoned = Map<String, Object?>.of(bundle.toJson())
      ..['path'] = '/tmp';
    expect(
      () => ExperienceContextBundle.fromJson(poisoned),
      throwsFormatException,
    );
  });
}

ContextBudgets _budgets(int bytes) => ContextBudgets(
  categories: <ContextCategory, ContextCategoryBudget>{
    for (final category in ContextCategory.values)
      category: ContextCategoryBudget(maxItems: 8, maxBytes: bytes),
  },
);
