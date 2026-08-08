import 'package:devex_contracts/devex_contracts.dart';

final class SourceImpactEngine {
  const SourceImpactEngine();

  ChangeSet diff(SourceSnapshot base, SourceSnapshot current) {
    if (base.repository.id != current.repository.id) {
      throw ArgumentError(
        'Source snapshots must belong to the same repository',
      );
    }
    final before = <String, SourceFileEntry>{
      for (final file in base.files) file.path: file,
    };
    final after = <String, SourceFileEntry>{
      for (final file in current.files) file.path: file,
    };
    final paths = <String>{...before.keys, ...after.keys}.toList()..sort();
    final changes = <SourceChange>[];
    for (final path in paths) {
      final left = before[path];
      final right = after[path];
      if (left == null) {
        changes.add(
          SourceChange(
            path: path,
            kind: SourceChangeKind.added,
            afterDigest: right!.digest,
          ),
        );
      } else if (right == null) {
        changes.add(
          SourceChange(
            path: path,
            kind: SourceChangeKind.deleted,
            beforeDigest: left.digest,
          ),
        );
      } else if (left.digest != right.digest || left.size != right.size) {
        changes.add(
          SourceChange(
            path: path,
            kind: SourceChangeKind.modified,
            beforeDigest: left.digest,
            afterDigest: right.digest,
          ),
        );
      }
    }
    return ChangeSet(
      repositoryId: base.repository.id,
      baseSnapshotDigest: base.digest,
      currentSnapshotDigest: current.digest,
      complete:
          base.completeness == SnapshotCompleteness.complete &&
          current.completeness == SnapshotCompleteness.complete,
      changes: changes,
    );
  }

  ImpactPlan plan(ChangeSet changes, List<SourceBinding> bindings) {
    final byId = <String, SourceBinding>{};
    var complete = changes.complete;
    for (final binding in bindings) {
      if (byId.containsKey(binding.id)) {
        throw ArgumentError('Duplicate SourceBinding ID: ${binding.id}');
      }
      byId[binding.id] = binding;
      if (binding.repositoryId != changes.repositoryId) complete = false;
    }

    final reasons = <String, Set<ImpactReason>>{};
    void impact(String id, ImpactReason reason) =>
        (reasons[id] ??= <ImpactReason>{}).add(reason);

    if (!changes.complete) {
      for (final binding in bindings) {
        impact(binding.id, ImpactReason.incompleteSnapshot);
      }
    }
    for (final binding in bindings) {
      if (binding.repositoryId != changes.repositoryId) {
        impact(binding.id, ImpactReason.unknownBinding);
        continue;
      }
      if (changes.changes.any(
        (change) =>
            binding.pathGlobs.any((glob) => _matches(glob, change.path)),
      )) {
        impact(binding.id, ImpactReason.direct);
      }
      for (final dependency in binding.dependsOn) {
        if (!byId.containsKey(dependency)) {
          complete = false;
          impact(binding.id, ImpactReason.unknownBinding);
        }
      }
    }

    var changed = true;
    while (changed) {
      changed = false;
      for (final binding in bindings) {
        if (reasons.containsKey(binding.id)) continue;
        if (binding.dependsOn.any(reasons.containsKey)) {
          impact(binding.id, ImpactReason.transitive);
          changed = true;
        }
      }
    }

    if (!complete) {
      // Unproven completeness invalidates every reuse decision, even when a
      // binding looked unrelated in the available tree.
      for (final binding in bindings) {
        impact(binding.id, ImpactReason.unknownBinding);
      }
    }

    final impacted = <ImpactItem>[
      for (final binding in bindings)
        if (reasons[binding.id] case final itemReasons?)
          ImpactItem(
            bindingId: binding.id,
            subject: binding.subject,
            reasons: itemReasons,
          ),
    ];
    final impactedSubjects = impacted.map((item) => item.subject).toSet();
    final reusable = complete
        ? bindings
              .map((binding) => binding.subject)
              .where((subject) => !impactedSubjects.contains(subject))
              .toSet()
              .toList()
        : const <String>[];
    return ImpactPlan(
      changeSetDigest: changes.digest,
      currentSnapshotDigest: changes.currentSnapshotDigest,
      complete: complete,
      impacted: impacted,
      reusableSubjects: reusable,
    );
  }

  bool _matches(String glob, String path) {
    final expression = StringBuffer('^');
    for (var index = 0; index < glob.length; index += 1) {
      final char = glob[index];
      if (char == '*') {
        final doubleStar = index + 1 < glob.length && glob[index + 1] == '*';
        if (doubleStar) {
          index += 1;
          if (index + 1 < glob.length && glob[index + 1] == '/') {
            index += 1;
            expression.write('(?:.*/)?');
          } else {
            expression.write('.*');
          }
        } else {
          expression.write('[^/]*');
        }
      } else if (char == '?') {
        expression.write('[^/]');
      } else {
        expression.write(RegExp.escape(char));
      }
    }
    expression.write(r'$');
    return RegExp(expression.toString()).hasMatch(path);
  }
}
