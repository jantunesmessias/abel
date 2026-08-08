import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  SourceSnapshot snapshot(
    String revision,
    Map<String, String> files, {
    SnapshotCompleteness completeness = SnapshotCompleteness.complete,
  }) {
    return SourceSnapshot(
      repository: SourceRepository(
        id: 'repo',
        kind: SourceRepositoryKind.filesystem,
        root: '.',
      ),
      revision: revision,
      completeness: completeness,
      files: <SourceFileEntry>[
        for (final entry in files.entries)
          SourceFileEntry(
            path: entry.key,
            digest: Digest.bytes(entry.value.codeUnits),
            size: entry.value.length,
          ),
      ],
    );
  }

  const engine = SourceImpactEngine();

  test('diff and plan direct plus transitive impact deterministically', () {
    final changes = engine.diff(
      snapshot('base', <String, String>{
        'lib/domain/model.dart': 'old',
        'lib/ui/view.dart': 'same',
      }),
      snapshot('head', <String, String>{
        'lib/domain/model.dart': 'new',
        'lib/ui/view.dart': 'same',
        'tests/new_test.dart': 'added',
      }),
    );
    final plan = engine.plan(changes, <SourceBinding>[
      SourceBinding(
        id: 'domain',
        subject: 'scenario-domain',
        repositoryId: 'repo',
        pathGlobs: const <String>['lib/domain/**'],
      ),
      SourceBinding(
        id: 'ui',
        subject: 'scenario-ui',
        repositoryId: 'repo',
        pathGlobs: const <String>['lib/ui/**'],
        dependsOn: const <String>['domain'],
      ),
      SourceBinding(
        id: 'docs',
        subject: 'scenario-docs',
        repositoryId: 'repo',
        pathGlobs: const <String>['docs/**'],
      ),
    ]);

    expect(changes.changes.map((item) => item.path), <String>[
      'lib/domain/model.dart',
      'tests/new_test.dart',
    ]);
    expect(plan.complete, isTrue);
    expect(plan.impacted.map((item) => item.bindingId), <String>[
      'domain',
      'ui',
    ]);
    expect(plan.impacted.first.reasons, contains(ImpactReason.direct));
    expect(plan.impacted.last.reasons, contains(ImpactReason.transitive));
    expect(plan.reusableSubjects, <String>['scenario-docs']);
    expect(ImpactPlan.fromJson(plan.toJson()).digest, plan.digest);
  });

  test('incomplete snapshot fails closed and permits no evidence reuse', () {
    final changes = engine.diff(
      snapshot('base', const <String, String>{'lib/a.dart': 'a'}),
      snapshot('head', const <String, String>{
        'lib/a.dart': 'a',
      }, completeness: SnapshotCompleteness.partial),
    );
    final plan = engine.plan(changes, <SourceBinding>[
      SourceBinding(
        id: 'a',
        subject: 'scenario-a',
        repositoryId: 'repo',
        pathGlobs: const <String>['lib/**'],
      ),
    ]);
    expect(plan.complete, isFalse);
    expect(plan.allowsEvidenceReuse, isFalse);
    expect(plan.reusableSubjects, isEmpty);
    expect(
      plan.impacted.single.reasons,
      contains(ImpactReason.incompleteSnapshot),
    );
  });

  test('unknown dependency invalidates plan conservatively', () {
    final changes = engine.diff(
      snapshot('base', const <String, String>{'lib/a.dart': 'a'}),
      snapshot('head', const <String, String>{'lib/a.dart': 'a'}),
    );
    final plan = engine.plan(changes, <SourceBinding>[
      SourceBinding(
        id: 'a',
        subject: 'scenario-a',
        repositoryId: 'repo',
        pathGlobs: const <String>['lib/**'],
        dependsOn: const <String>['missing'],
      ),
    ]);
    expect(plan.complete, isFalse);
    expect(plan.impacted.single.reasons, contains(ImpactReason.unknownBinding));
  });
}
