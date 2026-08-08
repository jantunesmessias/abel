import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final validator = Draft202012Validator(
    jsonDecode(
          File(
            p.join(_root(), 'schemas', 'catalog', 'motion-context.schema.json'),
          ).readAsStringSync(),
        )
        as Object,
  );
  final contentSetDigest = Digest.semantic('content');
  final budgets = ContextBudgets(
    categories: <ContextCategory, ContextCategoryBudget>{
      for (final category in ContextCategory.values)
        category: ContextCategoryBudget(maxItems: 8, maxBytes: 4096),
    },
  );
  final selection = ContextSelection(
    boardId: BoardId('board'),
    projectionId: ExperienceProjectionId('projection'),
    journeyId: JourneyId('journey'),
    scenarioId: ScenarioId('ready'),
  );
  const inclusion = ContextInclusion(
    sources: true,
    images: true,
    evidence: true,
    history: true,
    changes: false,
  );
  final bundle = ExperienceContextBundle(
    contentSetDigest: contentSetDigest,
    selection: selection,
    inclusion: inclusion,
    requestedBudgets: budgets,
    effectiveBudgets: budgets,
    items: const <ContextItem>[],
    usage: <ContextCategory, ContextUsage>{
      for (final category in ContextCategory.values)
        category: ContextUsage(items: 0, bytes: 0),
    },
    omissions: <ContextOmission>[
      for (final category in ContextCategory.values)
        ContextOmission(
          category: category,
          subject: category.name,
          reason: ContextOmissionReason.unavailable,
        ),
    ],
  );

  test('schema accepts every closed Motion and Context wire envelope', () {
    final motion = MotionManifest(
      catalogDigest: Digest.semantic('catalog'),
      topologyDigest: Digest.semantic('topology'),
      sequences: <MotionSequenceManifest>[
        MotionSequenceManifest(
          id: 'ready-motion',
          projectionId: ExperienceProjectionId('projection'),
          title: 'Ready motion',
          staticSummary: 'Loading is followed by ready.',
          steps: <MotionTransitionStep>[
            MotionTransitionStep(
              id: 'show-ready',
              transitionId: TransitionId('next'),
              fromNodeId: NodeInstanceId('loading-node'),
              toNodeId: NodeInstanceId('ready-node'),
              startMs: 0,
              fullDurationMs: 420,
              reducedDurationMs: 80,
              easing: MotionEasing.easeInOut,
              observations: <MotionObservation>[
                MotionObservation(
                  id: 'ready-visible',
                  label: 'Ready is visible',
                  atFraction: 1,
                  kind: MotionObservationKind.stateVisible,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final description = ContextBuilderDescription(
      contentSetDigest: contentSetDigest,
      supportedCategories: ContextCategory.values.toSet(),
      maximumBudgets: budgets,
    );
    final request = ContextBuildRequest(
      expectedContentSetDigest: contentSetDigest,
      selection: selection,
      inclusion: inclusion,
      budgets: budgets,
    );

    for (final value in <Map<String, Object?>>[
      motion.toJson(),
      description.toJson(),
      request.toJson(),
      ContextBuildResult(bundle: bundle).toJson(),
    ]) {
      expect(validator.validate(value).isValid, isTrue, reason: '$value');
    }
  });

  test('schema rejects cross-envelope fields and comprehension by motion', () {
    expect(
      validator.validate(<String, Object?>{
        ...ContextBuildResult(bundle: bundle).toJson(),
        'contentRoot': '/tmp/forbidden',
      }).isValid,
      isFalse,
    );
    final poisoned = <String, Object?>{
      'schemaVersion': 1,
      'kind': 'MotionManifest',
      'catalogDigest': Digest.semantic('catalog').value,
      'topologyDigest': Digest.semantic('topology').value,
      'sequences': <Object?>[
        <String, Object?>{
          'id': 'motion',
          'projectionId': 'projection',
          'title': 'Motion',
          'steps': const <Object?>[],
          'staticSummary': 'Static summary',
          'motionRequiredForComprehension': true,
        },
      ],
      'digest': Digest.semantic('motion').value,
    };
    expect(validator.validate(poisoned).isValid, isFalse);
  });
}

String _root() {
  var current = Directory.current.absolute;
  while (true) {
    if (File(p.join(current.path, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(current.path, 'libs')).existsSync() &&
        Directory(p.join(current.path, 'schemas')).existsSync()) {
      return current.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Repository root not found');
    }
    current = parent;
  }
}
