import 'dart:convert';

import '../digest.dart';

enum SourceRepositoryKind { filesystem, git }

enum SnapshotCompleteness { complete, partial, unknown }

enum SourceChangeKind { added, modified, deleted }

enum ImpactReason { direct, transitive, incompleteSnapshot, unknownBinding }

/// Effects an external agent may perform without an independent apply grant.
/// Mutation is intentionally absent from this enum.
enum AgentTaskEffect { inspect, propose }

final class SourceRepository {
  SourceRepository({
    required this.id,
    required this.kind,
    required this.root,
    this.revision,
  }) {
    _id(id, 'SourceRepository.id');
    _relativePath(root, 'SourceRepository.root', allowDot: true);
    if (revision != null) _nonEmpty(revision!, 'SourceRepository.revision');
  }

  final String id;
  final SourceRepositoryKind kind;
  final String root;
  final String? revision;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.name,
    'root': root,
    if (revision != null) 'revision': revision,
  };

  factory SourceRepository.fromJson(Object? value) {
    final json = _object(value, 'SourceRepository');
    _only(json, const <String>{
      'id',
      'kind',
      'root',
      'revision',
    }, 'SourceRepository');
    return SourceRepository(
      id: _string(json, 'id', 'SourceRepository'),
      kind: _enum(
        SourceRepositoryKind.values,
        _string(json, 'kind', 'SourceRepository'),
        'SourceRepository.kind',
      ),
      root: _string(json, 'root', 'SourceRepository'),
      revision: _optionalString(json, 'revision', 'SourceRepository'),
    );
  }
}

final class SourceFileEntry {
  SourceFileEntry({
    required this.path,
    required this.digest,
    required this.size,
  }) {
    _relativePath(path, 'SourceFileEntry.path');
    if (size < 0) {
      throw ArgumentError.value(size, 'size', 'must be non-negative');
    }
  }

  final String path;
  final Digest digest;
  final int size;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'digest': digest.value,
    'size': size,
  };

  factory SourceFileEntry.fromJson(Object? value) {
    final json = _object(value, 'SourceFileEntry');
    _only(json, const <String>{'path', 'digest', 'size'}, 'SourceFileEntry');
    return SourceFileEntry(
      path: _string(json, 'path', 'SourceFileEntry'),
      digest: Digest(_string(json, 'digest', 'SourceFileEntry')),
      size: _integer(json, 'size', 'SourceFileEntry'),
    );
  }
}

final class SourceSnapshot {
  SourceSnapshot({
    required this.repository,
    required this.revision,
    required this.completeness,
    required List<SourceFileEntry> files,
    List<String> omissions = const <String>[],
  }) : files = List<SourceFileEntry>.unmodifiable(
         List<SourceFileEntry>.of(files)
           ..sort((a, b) => a.path.compareTo(b.path)),
       ),
       omissions = List<String>.unmodifiable(
         List<String>.of(omissions)..sort(),
       ) {
    _nonEmpty(revision, 'SourceSnapshot.revision');
    if (this.files.map((file) => file.path).toSet().length !=
        this.files.length) {
      throw ArgumentError('SourceSnapshot paths must be unique');
    }
    if (completeness == SnapshotCompleteness.complete &&
        this.omissions.isNotEmpty) {
      throw ArgumentError('A complete SourceSnapshot cannot have omissions');
    }
    for (final omission in this.omissions) {
      _nonEmpty(omission, 'SourceSnapshot.omission');
    }
  }

  static const int schemaVersion = 1;
  final SourceRepository repository;
  final String revision;
  final SnapshotCompleteness completeness;
  final List<SourceFileEntry> files;
  final List<String> omissions;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'SourceSnapshot',
    'repository': repository.toJson(),
    'revision': revision,
    'completeness': completeness.name,
    'files': <Object?>[for (final file in files) file.toJson()],
    'omissions': omissions,
    if (includeDigest) 'digest': digest.value,
  };

  factory SourceSnapshot.fromJson(Object? value) {
    final json = _object(value, 'SourceSnapshot');
    _document(json, 'SourceSnapshot', const <String>{
      'repository',
      'revision',
      'completeness',
      'files',
      'omissions',
    });
    final snapshot = SourceSnapshot(
      repository: SourceRepository.fromJson(json['repository']),
      revision: _string(json, 'revision', 'SourceSnapshot'),
      completeness: _enum(
        SnapshotCompleteness.values,
        _string(json, 'completeness', 'SourceSnapshot'),
        'SourceSnapshot.completeness',
      ),
      files: _list(
        json,
        'files',
        'SourceSnapshot',
      ).map(SourceFileEntry.fromJson).toList(growable: false),
      omissions: _stringList(json, 'omissions', 'SourceSnapshot'),
    );
    _digest(json, snapshot.digest, 'SourceSnapshot');
    return snapshot;
  }
}

final class SourceChange {
  SourceChange({
    required this.path,
    required this.kind,
    this.beforeDigest,
    this.afterDigest,
  }) {
    _relativePath(path, 'SourceChange.path');
    switch (kind) {
      case SourceChangeKind.added:
        if (beforeDigest != null || afterDigest == null) {
          throw ArgumentError('Added source requires only afterDigest');
        }
      case SourceChangeKind.modified:
        if (beforeDigest == null ||
            afterDigest == null ||
            beforeDigest == afterDigest) {
          throw ArgumentError(
            'Modified source requires distinct before/after digests',
          );
        }
      case SourceChangeKind.deleted:
        if (beforeDigest == null || afterDigest != null) {
          throw ArgumentError('Deleted source requires only beforeDigest');
        }
    }
  }

  final String path;
  final SourceChangeKind kind;
  final Digest? beforeDigest;
  final Digest? afterDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'kind': kind.name,
    if (beforeDigest != null) 'beforeDigest': beforeDigest!.value,
    if (afterDigest != null) 'afterDigest': afterDigest!.value,
  };

  factory SourceChange.fromJson(Object? value) {
    final json = _object(value, 'SourceChange');
    _only(json, const <String>{
      'path',
      'kind',
      'beforeDigest',
      'afterDigest',
    }, 'SourceChange');
    return SourceChange(
      path: _string(json, 'path', 'SourceChange'),
      kind: _enum(
        SourceChangeKind.values,
        _string(json, 'kind', 'SourceChange'),
        'SourceChange.kind',
      ),
      beforeDigest: _optionalDigest(json, 'beforeDigest', 'SourceChange'),
      afterDigest: _optionalDigest(json, 'afterDigest', 'SourceChange'),
    );
  }
}

final class ChangeSet {
  ChangeSet({
    required this.repositoryId,
    required this.baseSnapshotDigest,
    required this.currentSnapshotDigest,
    required this.complete,
    required List<SourceChange> changes,
  }) : changes = List<SourceChange>.unmodifiable(
         List<SourceChange>.of(changes)
           ..sort((a, b) => a.path.compareTo(b.path)),
       ) {
    _id(repositoryId, 'ChangeSet.repositoryId');
    if (this.changes.map((change) => change.path).toSet().length !=
        this.changes.length) {
      throw ArgumentError('ChangeSet paths must be unique');
    }
  }

  static const int schemaVersion = 1;
  final String repositoryId;
  final Digest baseSnapshotDigest;
  final Digest currentSnapshotDigest;
  final bool complete;
  final List<SourceChange> changes;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ChangeSet',
    'repositoryId': repositoryId,
    'baseSnapshotDigest': baseSnapshotDigest.value,
    'currentSnapshotDigest': currentSnapshotDigest.value,
    'complete': complete,
    'changes': <Object?>[for (final change in changes) change.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory ChangeSet.fromJson(Object? value) {
    final json = _object(value, 'ChangeSet');
    _document(json, 'ChangeSet', const <String>{
      'repositoryId',
      'baseSnapshotDigest',
      'currentSnapshotDigest',
      'complete',
      'changes',
    });
    final set = ChangeSet(
      repositoryId: _string(json, 'repositoryId', 'ChangeSet'),
      baseSnapshotDigest: Digest(
        _string(json, 'baseSnapshotDigest', 'ChangeSet'),
      ),
      currentSnapshotDigest: Digest(
        _string(json, 'currentSnapshotDigest', 'ChangeSet'),
      ),
      complete: _boolean(json, 'complete', 'ChangeSet'),
      changes: _list(
        json,
        'changes',
        'ChangeSet',
      ).map(SourceChange.fromJson).toList(growable: false),
    );
    _digest(json, set.digest, 'ChangeSet');
    return set;
  }
}

final class SourceBinding {
  SourceBinding({
    required this.id,
    required this.subject,
    required this.repositoryId,
    required List<String> pathGlobs,
    this.symbol,
    List<String> dependsOn = const <String>[],
  }) : pathGlobs = List<String>.unmodifiable(
         List<String>.of(pathGlobs)..sort(),
       ),
       dependsOn = List<String>.unmodifiable(
         List<String>.of(dependsOn)..sort(),
       ) {
    _id(id, 'SourceBinding.id');
    _nonEmpty(subject, 'SourceBinding.subject');
    _id(repositoryId, 'SourceBinding.repositoryId');
    if (this.pathGlobs.isEmpty ||
        this.pathGlobs.toSet().length != this.pathGlobs.length) {
      throw ArgumentError('SourceBinding requires unique path globs');
    }
    for (final glob in this.pathGlobs) {
      _relativeGlob(glob);
    }
    if (symbol != null) _nonEmpty(symbol!, 'SourceBinding.symbol');
    if (this.dependsOn.toSet().length != this.dependsOn.length ||
        this.dependsOn.contains(id)) {
      throw ArgumentError('SourceBinding dependencies are invalid');
    }
    for (final dependency in this.dependsOn) {
      _id(dependency, 'SourceBinding.dependsOn');
    }
  }

  final String id;
  final String subject;
  final String repositoryId;
  final List<String> pathGlobs;
  final String? symbol;
  final List<String> dependsOn;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'subject': subject,
    'repositoryId': repositoryId,
    'pathGlobs': pathGlobs,
    if (symbol != null) 'symbol': symbol,
    'dependsOn': dependsOn,
  };

  factory SourceBinding.fromJson(Object? value) {
    final json = _object(value, 'SourceBinding');
    _only(json, const <String>{
      'id',
      'subject',
      'repositoryId',
      'pathGlobs',
      'symbol',
      'dependsOn',
    }, 'SourceBinding');
    return SourceBinding(
      id: _string(json, 'id', 'SourceBinding'),
      subject: _string(json, 'subject', 'SourceBinding'),
      repositoryId: _string(json, 'repositoryId', 'SourceBinding'),
      pathGlobs: _stringList(json, 'pathGlobs', 'SourceBinding'),
      symbol: _optionalString(json, 'symbol', 'SourceBinding'),
      dependsOn: _stringList(json, 'dependsOn', 'SourceBinding'),
    );
  }
}

final class ImpactItem {
  ImpactItem({
    required this.bindingId,
    required this.subject,
    required Set<ImpactReason> reasons,
  }) : reasons = Set<ImpactReason>.unmodifiable(reasons) {
    _id(bindingId, 'ImpactItem.bindingId');
    _nonEmpty(subject, 'ImpactItem.subject');
    if (this.reasons.isEmpty) {
      throw ArgumentError('ImpactItem requires a reason');
    }
  }

  final String bindingId;
  final String subject;
  final Set<ImpactReason> reasons;

  Map<String, Object?> toJson() => <String, Object?>{
    'bindingId': bindingId,
    'subject': subject,
    'reasons': reasons.map((reason) => reason.name).toList()..sort(),
  };

  factory ImpactItem.fromJson(Object? value) {
    final json = _object(value, 'ImpactItem');
    _only(json, const <String>{
      'bindingId',
      'subject',
      'reasons',
    }, 'ImpactItem');
    return ImpactItem(
      bindingId: _string(json, 'bindingId', 'ImpactItem'),
      subject: _string(json, 'subject', 'ImpactItem'),
      reasons: _stringList(json, 'reasons', 'ImpactItem')
          .map(
            (value) => _enum(ImpactReason.values, value, 'ImpactItem.reasons'),
          )
          .toSet(),
    );
  }
}

final class ImpactPlan {
  ImpactPlan({
    required this.changeSetDigest,
    required this.currentSnapshotDigest,
    required this.complete,
    required List<ImpactItem> impacted,
    required List<String> reusableSubjects,
  }) : impacted = List<ImpactItem>.unmodifiable(
         List<ImpactItem>.of(impacted)
           ..sort((a, b) => a.bindingId.compareTo(b.bindingId)),
       ),
       reusableSubjects = List<String>.unmodifiable(
         List<String>.of(reusableSubjects)..sort(),
       ) {
    if (this.impacted.map((item) => item.bindingId).toSet().length !=
        this.impacted.length) {
      throw ArgumentError('ImpactPlan binding IDs must be unique');
    }
    if (this.reusableSubjects.toSet().length != this.reusableSubjects.length) {
      throw ArgumentError('ImpactPlan reusable subjects must be unique');
    }
    if (!complete && this.reusableSubjects.isNotEmpty) {
      throw ArgumentError('Incomplete impact cannot assert reusable subjects');
    }
  }

  static const int schemaVersion = 1;
  final Digest changeSetDigest;
  final Digest currentSnapshotDigest;
  final bool complete;
  final List<ImpactItem> impacted;
  final List<String> reusableSubjects;
  bool get allowsEvidenceReuse => complete;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ImpactPlan',
    'changeSetDigest': changeSetDigest.value,
    'currentSnapshotDigest': currentSnapshotDigest.value,
    'complete': complete,
    'allowsEvidenceReuse': allowsEvidenceReuse,
    'impacted': <Object?>[for (final item in impacted) item.toJson()],
    'reusableSubjects': reusableSubjects,
    if (includeDigest) 'digest': digest.value,
  };

  factory ImpactPlan.fromJson(Object? value) {
    final json = _object(value, 'ImpactPlan');
    _document(json, 'ImpactPlan', const <String>{
      'changeSetDigest',
      'currentSnapshotDigest',
      'complete',
      'allowsEvidenceReuse',
      'impacted',
      'reusableSubjects',
    });
    final plan = ImpactPlan(
      changeSetDigest: Digest(_string(json, 'changeSetDigest', 'ImpactPlan')),
      currentSnapshotDigest: Digest(
        _string(json, 'currentSnapshotDigest', 'ImpactPlan'),
      ),
      complete: _boolean(json, 'complete', 'ImpactPlan'),
      impacted: _list(
        json,
        'impacted',
        'ImpactPlan',
      ).map(ImpactItem.fromJson).toList(growable: false),
      reusableSubjects: _stringList(json, 'reusableSubjects', 'ImpactPlan'),
    );
    if (json['allowsEvidenceReuse'] != plan.allowsEvidenceReuse) {
      throw const FormatException(
        'ImpactPlan.allowsEvidenceReuse is inconsistent',
      );
    }
    _digest(json, plan.digest, 'ImpactPlan');
    return plan;
  }
}

final class ContextFile {
  ContextFile({
    required this.path,
    required this.digest,
    required this.content,
  }) {
    _relativePath(path, 'ContextFile.path');
    if (content.contains('\u0000')) {
      throw ArgumentError('ContextFile content cannot contain NUL');
    }
    if (digest != Digest.bytes(utf8.encode(content))) {
      throw ArgumentError('ContextFile digest must identify its UTF-8 content');
    }
  }

  final String path;
  final Digest digest;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'digest': digest.value,
    'content': content,
  };

  factory ContextFile.fromJson(Object? value) {
    final json = _object(value, 'ContextFile');
    _only(json, const <String>{'path', 'digest', 'content'}, 'ContextFile');
    final file = ContextFile(
      path: _string(json, 'path', 'ContextFile'),
      digest: Digest(_string(json, 'digest', 'ContextFile')),
      content: _stringAllowEmpty(json, 'content', 'ContextFile'),
    );
    return file;
  }
}

final class ContextBundle {
  ContextBundle({
    required this.snapshotDigest,
    required List<ContextFile> files,
    required List<String> redactions,
  }) : files = List<ContextFile>.unmodifiable(
         List<ContextFile>.of(files)..sort((a, b) => a.path.compareTo(b.path)),
       ),
       redactions = List<String>.unmodifiable(
         List<String>.of(redactions)..sort(),
       ) {
    if (this.files.map((file) => file.path).toSet().length !=
        this.files.length) {
      throw ArgumentError('ContextBundle paths must be unique');
    }
    for (final redaction in this.redactions) {
      _nonEmpty(redaction, 'ContextBundle.redaction');
    }
  }

  static const int schemaVersion = 1;
  final Digest snapshotDigest;
  final List<ContextFile> files;
  final List<String> redactions;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ContextBundle',
    'snapshotDigest': snapshotDigest.value,
    'files': <Object?>[for (final file in files) file.toJson()],
    'redactions': redactions,
    if (includeDigest) 'digest': digest.value,
  };

  factory ContextBundle.fromJson(Object? value) {
    final json = _object(value, 'ContextBundle');
    _document(json, 'ContextBundle', const <String>{
      'snapshotDigest',
      'files',
      'redactions',
    });
    final bundle = ContextBundle(
      snapshotDigest: Digest(_string(json, 'snapshotDigest', 'ContextBundle')),
      files: _list(
        json,
        'files',
        'ContextBundle',
      ).map(ContextFile.fromJson).toList(growable: false),
      redactions: _stringList(json, 'redactions', 'ContextBundle'),
    );
    _digest(json, bundle.digest, 'ContextBundle');
    return bundle;
  }
}

/// A bounded, expiring authorization envelope for external analysis.
///
/// Repository content and the objective remain untrusted data. The task binds
/// the agent to one sanitized context and one expected source snapshot, and it
/// cannot grant an apply, approval, seal, or publication effect.
final class AgentTask {
  AgentTask({
    required this.id,
    required this.principalId,
    required this.contextBundleDigest,
    required this.baseSnapshotDigest,
    required this.objective,
    required Set<AgentTaskEffect> allowedEffects,
    required this.createdAt,
    required this.expiresAt,
  }) : allowedEffects = Set<AgentTaskEffect>.unmodifiable(allowedEffects) {
    _id(id, 'AgentTask.id');
    _id(principalId, 'AgentTask.principalId');
    _boundedText(objective, 'AgentTask.objective');
    if (this.allowedEffects.isEmpty) {
      throw ArgumentError('AgentTask requires at least one allowed effect');
    }
    final lifetime = expiresAt.toUtc().difference(createdAt.toUtc());
    if (lifetime <= Duration.zero || lifetime > const Duration(hours: 24)) {
      throw ArgumentError(
        'AgentTask lifetime must be positive and no longer than 24 hours',
      );
    }
  }

  static const int schemaVersion = 1;

  final String id;
  final String principalId;
  final Digest contextBundleDigest;
  final Digest baseSnapshotDigest;
  final String objective;
  final Set<AgentTaskEffect> allowedEffects;
  final DateTime createdAt;
  final DateTime expiresAt;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AgentTask',
    'id': id,
    'principalId': principalId,
    'contextBundleDigest': contextBundleDigest.value,
    'baseSnapshotDigest': baseSnapshotDigest.value,
    'objective': objective,
    'allowedEffects': allowedEffects.map((effect) => effect.name).toList()
      ..sort(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (includeDigest) 'digest': digest.value,
  };

  factory AgentTask.fromJson(Object? value) {
    final json = _object(value, 'AgentTask');
    _document(json, 'AgentTask', const <String>{
      'id',
      'principalId',
      'contextBundleDigest',
      'baseSnapshotDigest',
      'objective',
      'allowedEffects',
      'createdAt',
      'expiresAt',
    });
    final effectNames = _stringList(json, 'allowedEffects', 'AgentTask');
    if (effectNames.toSet().length != effectNames.length) {
      throw const FormatException('AgentTask.allowedEffects must be unique');
    }
    final task = AgentTask(
      id: _string(json, 'id', 'AgentTask'),
      principalId: _string(json, 'principalId', 'AgentTask'),
      contextBundleDigest: Digest(
        _string(json, 'contextBundleDigest', 'AgentTask'),
      ),
      baseSnapshotDigest: Digest(
        _string(json, 'baseSnapshotDigest', 'AgentTask'),
      ),
      objective: _string(json, 'objective', 'AgentTask'),
      allowedEffects: effectNames
          .map(
            (effect) => _enum(
              AgentTaskEffect.values,
              effect,
              'AgentTask.allowedEffects',
            ),
          )
          .toSet(),
      createdAt: _dateTime(json, 'createdAt', 'AgentTask'),
      expiresAt: _dateTime(json, 'expiresAt', 'AgentTask'),
    );
    _digest(json, task.digest, 'AgentTask');
    return task;
  }
}

/// An immutable draft linked to the exact task, base snapshot, and ChangeSet.
/// Applying it is always a separate operation with its own expected digest and
/// human or CI grant.
final class AgentProposal {
  AgentProposal({
    required this.id,
    required this.taskId,
    required this.taskDigest,
    required this.baseSnapshotDigest,
    required this.changeSetDigest,
    required this.summary,
    required this.createdAt,
  }) {
    _id(id, 'AgentProposal.id');
    _id(taskId, 'AgentProposal.taskId');
    _boundedText(summary, 'AgentProposal.summary');
  }

  static const int schemaVersion = 1;

  final String id;
  final String taskId;
  final Digest taskDigest;
  final Digest baseSnapshotDigest;
  final Digest changeSetDigest;
  final String summary;
  final DateTime createdAt;

  bool get requiresExplicitApply => true;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'AgentProposal',
    'id': id,
    'taskId': taskId,
    'taskDigest': taskDigest.value,
    'baseSnapshotDigest': baseSnapshotDigest.value,
    'changeSetDigest': changeSetDigest.value,
    'summary': summary,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'requiresExplicitApply': requiresExplicitApply,
    if (includeDigest) 'digest': digest.value,
  };

  factory AgentProposal.fromJson(Object? value) {
    final json = _object(value, 'AgentProposal');
    _document(json, 'AgentProposal', const <String>{
      'id',
      'taskId',
      'taskDigest',
      'baseSnapshotDigest',
      'changeSetDigest',
      'summary',
      'createdAt',
      'requiresExplicitApply',
    });
    if (json['requiresExplicitApply'] != true) {
      throw const FormatException(
        'AgentProposal requires an independent explicit apply',
      );
    }
    final proposal = AgentProposal(
      id: _string(json, 'id', 'AgentProposal'),
      taskId: _string(json, 'taskId', 'AgentProposal'),
      taskDigest: Digest(_string(json, 'taskDigest', 'AgentProposal')),
      baseSnapshotDigest: Digest(
        _string(json, 'baseSnapshotDigest', 'AgentProposal'),
      ),
      changeSetDigest: Digest(
        _string(json, 'changeSetDigest', 'AgentProposal'),
      ),
      summary: _string(json, 'summary', 'AgentProposal'),
      createdAt: _dateTime(json, 'createdAt', 'AgentProposal'),
    );
    _digest(json, proposal.digest, 'AgentProposal');
    return proposal;
  }
}

void _document(Map<String, Object?> json, String kind, Set<String> fields) {
  _only(json, <String>{'schemaVersion', 'kind', ...fields, 'digest'}, kind);
  if (json['schemaVersion'] != 1 || json['kind'] != kind) {
    throw FormatException('$kind version or kind is invalid');
  }
}

void _digest(Map<String, Object?> json, Digest expected, String path) {
  if (Digest(_string(json, 'digest', path)) != expected) {
    throw FormatException('$path.digest does not match canonical content');
  }
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

String _stringAllowEmpty(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String) throw FormatException('$path.$key must be a string');
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

DateTime _dateTime(Map<String, Object?> json, String key, String path) {
  final source = _string(json, key, path);
  final value = DateTime.tryParse(source);
  if (value == null || !value.isUtc || value.toIso8601String() != source) {
    throw FormatException('$path.$key must be a canonical UTC date-time');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw FormatException('$path.$key must be an array');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> json, String key, String path) {
  final list = _list(json, key, path);
  if (list.any((value) => value is! String || value.isEmpty)) {
    throw FormatException('$path.$key must contain non-empty strings');
  }
  return list.cast<String>();
}

Digest? _optionalDigest(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$path.$key must be a digest');
  return Digest(value);
}

T _enum<T extends Enum>(List<T> values, String source, String path) {
  for (final value in values) {
    if (value.name == source) return value;
  }
  throw FormatException('$path is invalid: $source');
}

void _nonEmpty(String value, String path) {
  if (value.trim().isEmpty) throw ArgumentError('$path must be non-empty');
}

void _boundedText(String value, String path) {
  if (value.trim().isEmpty || value.runes.length > 4096) {
    throw ArgumentError('$path must contain 1 to 4096 characters');
  }
}

void _id(String value, String path) {
  if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(value)) {
    throw FormatException('$path is not an opaque ID: $value');
  }
}

void _relativePath(String value, String path, {bool allowDot = false}) {
  final normalized = value.replaceAll('\\', '/');
  final segments = normalized.split('/');
  if (normalized.isEmpty ||
      (!allowDot && normalized == '.') ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      segments.contains('..') ||
      segments.contains('') ||
      normalized.endsWith('/')) {
    throw FormatException('$path must be a normalized relative path');
  }
}

void _relativeGlob(String value) {
  if (value.contains('\\') ||
      value.startsWith('/') ||
      value.split('/').contains('..') ||
      value.isEmpty) {
    throw FormatException(
      'SourceBinding glob must be workspace-relative: $value',
    );
  }
}
