import 'dart:convert';

import '../catalog/catalog_contracts.dart';
import '../catalog/experience_topology_contracts.dart';
import '../digest.dart';

enum MotionMode { full, reduced, none }

enum MotionEasing { linear, easeInOut }

enum MotionObservationKind { stateVisible, transitionCompleted, contentStable }

final class MotionObservation {
  MotionObservation({
    required this.id,
    required this.label,
    required this.atFraction,
    required this.kind,
  }) {
    _id(id, 'MotionObservation.id');
    _text(label, 'MotionObservation.label', maxBytes: 512);
    if (!atFraction.isFinite || atFraction < 0 || atFraction > 1) {
      throw ArgumentError.value(
        atFraction,
        'atFraction',
        'must be finite and between zero and one',
      );
    }
  }

  final String id;
  final String label;
  final double atFraction;
  final MotionObservationKind kind;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'atFraction': atFraction,
    'kind': kind.name,
  };

  factory MotionObservation.fromJson(Object? value) {
    final json = _object(value, 'MotionObservation');
    _only(json, const <String>{
      'id',
      'label',
      'atFraction',
      'kind',
    }, 'MotionObservation');
    return MotionObservation(
      id: _string(json, 'id', 'MotionObservation'),
      label: _string(json, 'label', 'MotionObservation'),
      atFraction: _number(json, 'atFraction', 'MotionObservation'),
      kind: _enumValue(
        MotionObservationKind.values,
        _string(json, 'kind', 'MotionObservation'),
        'MotionObservation.kind',
      ),
    );
  }
}

final class MotionTransitionStep {
  MotionTransitionStep({
    required this.id,
    required this.transitionId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.startMs,
    required this.fullDurationMs,
    required this.reducedDurationMs,
    required this.easing,
    required Iterable<MotionObservation> observations,
  }) : observations = List<MotionObservation>.unmodifiable(observations) {
    _id(id, 'MotionTransitionStep.id');
    _safeInteger(startMs, 'MotionTransitionStep.startMs', min: 0, max: 600000);
    _safeInteger(
      fullDurationMs,
      'MotionTransitionStep.fullDurationMs',
      min: 1,
      max: 60000,
    );
    _safeInteger(
      reducedDurationMs,
      'MotionTransitionStep.reducedDurationMs',
      min: 0,
      max: fullDurationMs,
    );
    if (this.observations.isEmpty || this.observations.length > 64) {
      throw ArgumentError('MotionTransitionStep requires 1..64 observations');
    }
    if (this.observations.map((item) => item.id).toSet().length !=
        this.observations.length) {
      throw ArgumentError(
        'MotionTransitionStep observation IDs must be unique',
      );
    }
  }

  final String id;
  final TransitionId transitionId;
  final NodeInstanceId fromNodeId;
  final NodeInstanceId toNodeId;
  final int startMs;
  final int fullDurationMs;
  final int reducedDurationMs;
  final MotionEasing easing;
  final List<MotionObservation> observations;

  int durationFor(MotionMode mode) => switch (mode) {
    MotionMode.full => fullDurationMs,
    MotionMode.reduced => reducedDurationMs,
    MotionMode.none => 0,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'transitionId': transitionId.value,
    'fromNodeId': fromNodeId.value,
    'toNodeId': toNodeId.value,
    'startMs': startMs,
    'fullDurationMs': fullDurationMs,
    'reducedDurationMs': reducedDurationMs,
    'easing': easing.name,
    'observations': <Object?>[
      for (final observation in observations) observation.toJson(),
    ],
  };

  factory MotionTransitionStep.fromJson(Object? value) {
    final json = _object(value, 'MotionTransitionStep');
    _only(json, const <String>{
      'id',
      'transitionId',
      'fromNodeId',
      'toNodeId',
      'startMs',
      'fullDurationMs',
      'reducedDurationMs',
      'easing',
      'observations',
    }, 'MotionTransitionStep');
    return MotionTransitionStep(
      id: _string(json, 'id', 'MotionTransitionStep'),
      transitionId: TransitionId(
        _string(json, 'transitionId', 'MotionTransitionStep'),
      ),
      fromNodeId: NodeInstanceId(
        _string(json, 'fromNodeId', 'MotionTransitionStep'),
      ),
      toNodeId: NodeInstanceId(
        _string(json, 'toNodeId', 'MotionTransitionStep'),
      ),
      startMs: _integer(json, 'startMs', 'MotionTransitionStep'),
      fullDurationMs: _integer(json, 'fullDurationMs', 'MotionTransitionStep'),
      reducedDurationMs: _integer(
        json,
        'reducedDurationMs',
        'MotionTransitionStep',
      ),
      easing: _enumValue(
        MotionEasing.values,
        _string(json, 'easing', 'MotionTransitionStep'),
        'MotionTransitionStep.easing',
      ),
      observations: _list(
        json,
        'observations',
        'MotionTransitionStep',
        max: 64,
      ).map(MotionObservation.fromJson),
    );
  }
}

final class MotionSequenceManifest {
  MotionSequenceManifest({
    required this.id,
    required this.projectionId,
    required this.title,
    required Iterable<MotionTransitionStep> steps,
    required this.staticSummary,
  }) : steps = List<MotionTransitionStep>.unmodifiable(steps) {
    _id(id, 'MotionSequenceManifest.id');
    _text(title, 'MotionSequenceManifest.title', maxBytes: 512);
    _text(
      staticSummary,
      'MotionSequenceManifest.staticSummary',
      maxBytes: 2048,
    );
    if (this.steps.isEmpty || this.steps.length > 256) {
      throw ArgumentError('MotionSequenceManifest requires 1..256 steps');
    }
    if (this.steps.map((step) => step.id).toSet().length != this.steps.length) {
      throw ArgumentError('MotionSequenceManifest step IDs must be unique');
    }
    var previousStart = -1;
    for (final step in this.steps) {
      if (step.startMs < previousStart) {
        throw ArgumentError(
          'MotionSequenceManifest steps must be time ordered',
        );
      }
      previousStart = step.startMs;
    }
  }

  final String id;
  final ExperienceProjectionId projectionId;
  final String title;
  final List<MotionTransitionStep> steps;

  /// Textual, fully sufficient representation used when motion is disabled.
  final String staticSummary;

  int totalDurationFor(MotionMode mode) => mode == MotionMode.none
      ? 0
      : steps.fold<int>(
          0,
          (maximum, step) =>
              _max(maximum, step.startMs + step.durationFor(mode)),
        );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'projectionId': projectionId.value,
    'title': title,
    'steps': <Object?>[for (final step in steps) step.toJson()],
    'staticSummary': staticSummary,
    'motionRequiredForComprehension': false,
  };

  factory MotionSequenceManifest.fromJson(Object? value) {
    final json = _object(value, 'MotionSequenceManifest');
    _only(json, const <String>{
      'id',
      'projectionId',
      'title',
      'steps',
      'staticSummary',
      'motionRequiredForComprehension',
    }, 'MotionSequenceManifest');
    if (json['motionRequiredForComprehension'] != false) {
      throw const FormatException(
        'MotionSequenceManifest requires a complete non-motion equivalent',
      );
    }
    return MotionSequenceManifest(
      id: _string(json, 'id', 'MotionSequenceManifest'),
      projectionId: ExperienceProjectionId(
        _string(json, 'projectionId', 'MotionSequenceManifest'),
      ),
      title: _string(json, 'title', 'MotionSequenceManifest'),
      steps: _list(
        json,
        'steps',
        'MotionSequenceManifest',
        max: 256,
      ).map(MotionTransitionStep.fromJson),
      staticSummary: _string(json, 'staticSummary', 'MotionSequenceManifest'),
    );
  }
}

final class MotionManifest {
  MotionManifest({
    required this.catalogDigest,
    required this.topologyDigest,
    required Iterable<MotionSequenceManifest> sequences,
  }) : sequences = List<MotionSequenceManifest>.unmodifiable(
         List<MotionSequenceManifest>.of(sequences)
           ..sort((left, right) => left.id.compareTo(right.id)),
       ) {
    if (this.sequences.length > 10000) {
      throw ArgumentError('MotionManifest exceeds sequence limit');
    }
    if (this.sequences.map((item) => item.id).toSet().length !=
        this.sequences.length) {
      throw ArgumentError('MotionManifest sequence IDs must be unique');
    }
  }

  static const int schemaVersion = 1;
  final Digest catalogDigest;
  final Digest topologyDigest;
  final List<MotionSequenceManifest> sequences;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  void validateAgainst({
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
  }) {
    if (catalog.digest != catalogDigest || topology.digest != topologyDigest) {
      throw ArgumentError('MotionManifest belongs to another content set');
    }
    final projections = <ExperienceProjectionId, ExperienceProjection>{
      for (final projection in topology.projections) projection.id: projection,
    };
    final nodes = <NodeInstanceId, NodeInstance>{
      for (final node in topology.nodes) node.id: node,
    };
    final edges = <TransitionId, EdgeInstance>{
      for (final edge in topology.edges) edge.transitionId: edge,
    };
    for (final sequence in sequences) {
      if (!projections.containsKey(sequence.projectionId)) {
        throw ArgumentError('Motion sequence references an unknown Projection');
      }
      for (final step in sequence.steps) {
        final from = nodes[step.fromNodeId];
        final to = nodes[step.toNodeId];
        final edge = edges[step.transitionId];
        if (from == null ||
            to == null ||
            edge == null ||
            from.projectionId != sequence.projectionId ||
            to.projectionId != sequence.projectionId ||
            edge.projectionId != sequence.projectionId ||
            edge.fromNodeId != step.fromNodeId ||
            edge.toNodeId != step.toNodeId) {
          throw ArgumentError(
            'Motion step is not an exact topology transition',
          );
        }
      }
    }
  }

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'MotionManifest',
    'catalogDigest': catalogDigest.value,
    'topologyDigest': topologyDigest.value,
    'sequences': <Object?>[for (final sequence in sequences) sequence.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory MotionManifest.fromJson(
    Object? value, {
    required CatalogManifest catalog,
    required ExperienceTopologyManifest topology,
  }) {
    final json = _object(value, 'MotionManifest');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'catalogDigest',
      'topologyDigest',
      'sequences',
      'digest',
    }, 'MotionManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'MotionManifest') {
      throw const FormatException('MotionManifest has invalid header');
    }
    final manifest = MotionManifest(
      catalogDigest: Digest(_string(json, 'catalogDigest', 'MotionManifest')),
      topologyDigest: Digest(_string(json, 'topologyDigest', 'MotionManifest')),
      sequences: _list(
        json,
        'sequences',
        'MotionManifest',
        max: 10000,
      ).map(MotionSequenceManifest.fromJson),
    );
    if (Digest(_string(json, 'digest', 'MotionManifest')) != manifest.digest) {
      throw const FormatException('MotionManifest.digest mismatch');
    }
    manifest.validateAgainst(catalog: catalog, topology: topology);
    return manifest;
  }
}

enum ContextCategory { sources, images, evidence, history, changes }

enum ContextOmissionReason {
  omittedByRequest,
  budgetExceeded,
  unavailable,
  unsupported,
  redacted,
  stale,
  unsafe,
}

final class ContextSelection {
  ContextSelection({
    required this.boardId,
    required this.projectionId,
    this.journeyId,
    this.scenarioId,
    this.changeSetDigest,
  });

  final BoardId boardId;
  final ExperienceProjectionId projectionId;
  final JourneyId? journeyId;
  final ScenarioId? scenarioId;
  final Digest? changeSetDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'boardId': boardId.value,
    'projectionId': projectionId.value,
    if (journeyId != null) 'journeyId': journeyId!.value,
    if (scenarioId != null) 'scenarioId': scenarioId!.value,
    if (changeSetDigest != null) 'changeSetDigest': changeSetDigest!.value,
  };

  factory ContextSelection.fromJson(Object? value) {
    final json = _object(value, 'ContextSelection');
    _only(json, const <String>{
      'boardId',
      'projectionId',
      'journeyId',
      'scenarioId',
      'changeSetDigest',
    }, 'ContextSelection');
    final journeyId = _optionalString(json, 'journeyId', 'ContextSelection');
    final scenarioId = _optionalString(json, 'scenarioId', 'ContextSelection');
    final changeSetDigest = _optionalString(
      json,
      'changeSetDigest',
      'ContextSelection',
    );
    return ContextSelection(
      boardId: BoardId(_string(json, 'boardId', 'ContextSelection')),
      projectionId: ExperienceProjectionId(
        _string(json, 'projectionId', 'ContextSelection'),
      ),
      journeyId: journeyId == null ? null : JourneyId(journeyId),
      scenarioId: scenarioId == null ? null : ScenarioId(scenarioId),
      changeSetDigest: changeSetDigest == null ? null : Digest(changeSetDigest),
    );
  }
}

final class ContextInclusion {
  const ContextInclusion({
    required this.sources,
    required this.images,
    required this.evidence,
    required this.history,
    required this.changes,
  });

  final bool sources;
  final bool images;
  final bool evidence;
  final bool history;
  final bool changes;

  bool includes(ContextCategory category) => switch (category) {
    ContextCategory.sources => sources,
    ContextCategory.images => images,
    ContextCategory.evidence => evidence,
    ContextCategory.history => history,
    ContextCategory.changes => changes,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'sources': sources,
    'images': images,
    'evidence': evidence,
    'history': history,
    'changes': changes,
  };

  factory ContextInclusion.fromJson(Object? value) {
    final json = _object(value, 'ContextInclusion');
    _only(json, const <String>{
      'sources',
      'images',
      'evidence',
      'history',
      'changes',
    }, 'ContextInclusion');
    return ContextInclusion(
      sources: _boolean(json, 'sources', 'ContextInclusion'),
      images: _boolean(json, 'images', 'ContextInclusion'),
      evidence: _boolean(json, 'evidence', 'ContextInclusion'),
      history: _boolean(json, 'history', 'ContextInclusion'),
      changes: _boolean(json, 'changes', 'ContextInclusion'),
    );
  }
}

final class ContextCategoryBudget {
  ContextCategoryBudget({required this.maxItems, required this.maxBytes}) {
    _safeInteger(maxItems, 'ContextCategoryBudget.maxItems', min: 0, max: 1000);
    _safeInteger(
      maxBytes,
      'ContextCategoryBudget.maxBytes',
      min: 0,
      max: 4 * 1024 * 1024,
    );
  }

  final int maxItems;
  final int maxBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'maxItems': maxItems,
    'maxBytes': maxBytes,
  };

  factory ContextCategoryBudget.fromJson(Object? value) {
    final json = _object(value, 'ContextCategoryBudget');
    _only(json, const <String>{
      'maxItems',
      'maxBytes',
    }, 'ContextCategoryBudget');
    return ContextCategoryBudget(
      maxItems: _integer(json, 'maxItems', 'ContextCategoryBudget'),
      maxBytes: _integer(json, 'maxBytes', 'ContextCategoryBudget'),
    );
  }
}

final class ContextBudgets {
  ContextBudgets({
    required Map<ContextCategory, ContextCategoryBudget> categories,
  }) : categories = Map<ContextCategory, ContextCategoryBudget>.unmodifiable(
         categories,
       ) {
    if (this.categories.length != ContextCategory.values.length ||
        !this.categories.keys.toSet().containsAll(ContextCategory.values)) {
      throw ArgumentError(
        'ContextBudgets requires every category exactly once',
      );
    }
  }

  final Map<ContextCategory, ContextCategoryBudget> categories;

  ContextCategoryBudget operator [](ContextCategory category) =>
      categories[category]!;

  Map<String, Object?> toJson() => <String, Object?>{
    for (final category in ContextCategory.values)
      category.name: categories[category]!.toJson(),
  };

  factory ContextBudgets.fromJson(Object? value) {
    final json = _object(value, 'ContextBudgets');
    _only(
      json,
      ContextCategory.values.map((item) => item.name).toSet(),
      'ContextBudgets',
    );
    return ContextBudgets(
      categories: <ContextCategory, ContextCategoryBudget>{
        for (final category in ContextCategory.values)
          category: ContextCategoryBudget.fromJson(json[category.name]),
      },
    );
  }
}

final class ContextUsage {
  ContextUsage({required this.items, required this.bytes}) {
    _safeInteger(items, 'ContextUsage.items', min: 0, max: 1000);
    _safeInteger(bytes, 'ContextUsage.bytes', min: 0, max: 4 * 1024 * 1024);
  }

  final int items;
  final int bytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'items': items,
    'bytes': bytes,
  };

  factory ContextUsage.fromJson(Object? value) {
    final json = _object(value, 'ContextUsage');
    _only(json, const <String>{'items', 'bytes'}, 'ContextUsage');
    return ContextUsage(
      items: _integer(json, 'items', 'ContextUsage'),
      bytes: _integer(json, 'bytes', 'ContextUsage'),
    );
  }
}

final class ContextItem {
  ContextItem({
    required this.category,
    required this.id,
    required this.mediaType,
    required this.content,
  }) : digest = Digest.bytes(utf8.encode(content)) {
    _id(id, 'ContextItem.id');
    _text(mediaType, 'ContextItem.mediaType', maxBytes: 128);
    if (content.contains('\u0000') ||
        utf8.encode(content).length > 256 * 1024) {
      throw ArgumentError('ContextItem.content must be bounded UTF-8 text');
    }
  }

  ContextItem._decoded({
    required this.category,
    required this.id,
    required this.mediaType,
    required this.content,
    required this.digest,
  }) {
    _id(id, 'ContextItem.id');
    _text(mediaType, 'ContextItem.mediaType', maxBytes: 128);
    if (Digest.bytes(utf8.encode(content)) != digest) {
      throw const FormatException('ContextItem.digest mismatch');
    }
  }

  final ContextCategory category;
  final String id;
  final String mediaType;
  final String content;
  final Digest digest;

  int get byteLength => utf8.encode(content).length;

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.name,
    'id': id,
    'mediaType': mediaType,
    'content': content,
    'digest': digest.value,
  };

  factory ContextItem.fromJson(Object? value) {
    final json = _object(value, 'ContextItem');
    _only(json, const <String>{
      'category',
      'id',
      'mediaType',
      'content',
      'digest',
    }, 'ContextItem');
    return ContextItem._decoded(
      category: _enumValue(
        ContextCategory.values,
        _string(json, 'category', 'ContextItem'),
        'ContextItem.category',
      ),
      id: _string(json, 'id', 'ContextItem'),
      mediaType: _string(json, 'mediaType', 'ContextItem'),
      content: _stringAllowEmpty(json, 'content', 'ContextItem'),
      digest: Digest(_string(json, 'digest', 'ContextItem')),
    );
  }
}

final class ContextOmission {
  ContextOmission({
    required this.category,
    required this.subject,
    required this.reason,
  }) {
    _text(subject, 'ContextOmission.subject', maxBytes: 512);
  }

  final ContextCategory category;
  final String subject;
  final ContextOmissionReason reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.name,
    'subject': subject,
    'reason': reason.name,
  };

  factory ContextOmission.fromJson(Object? value) {
    final json = _object(value, 'ContextOmission');
    _only(json, const <String>{
      'category',
      'subject',
      'reason',
    }, 'ContextOmission');
    return ContextOmission(
      category: _enumValue(
        ContextCategory.values,
        _string(json, 'category', 'ContextOmission'),
        'ContextOmission.category',
      ),
      subject: _string(json, 'subject', 'ContextOmission'),
      reason: _enumValue(
        ContextOmissionReason.values,
        _string(json, 'reason', 'ContextOmission'),
        'ContextOmission.reason',
      ),
    );
  }
}

final class ExperienceContextBundle {
  ExperienceContextBundle({
    required this.contentSetDigest,
    required this.selection,
    required this.inclusion,
    required this.requestedBudgets,
    required this.effectiveBudgets,
    required Iterable<ContextItem> items,
    required Map<ContextCategory, ContextUsage> usage,
    required Iterable<ContextOmission> omissions,
  }) : items = List<ContextItem>.unmodifiable(
         List<ContextItem>.of(items)..sort((left, right) {
           final category = left.category.index.compareTo(right.category.index);
           return category != 0 ? category : left.id.compareTo(right.id);
         }),
       ),
       usage = Map<ContextCategory, ContextUsage>.unmodifiable(usage),
       omissions = List<ContextOmission>.unmodifiable(
         List<ContextOmission>.of(omissions)..sort((left, right) {
           final category = left.category.index.compareTo(right.category.index);
           final subject = left.subject.compareTo(right.subject);
           return category != 0
               ? category
               : subject != 0
               ? subject
               : left.reason.index.compareTo(right.reason.index);
         }),
       ) {
    if (this.items.length > 5000 || this.omissions.length > 5000) {
      throw ArgumentError('ExperienceContextBundle exceeds item limit');
    }
    if (this.items
            .map((item) => '${item.category.name}:${item.id}')
            .toSet()
            .length !=
        this.items.length) {
      throw ArgumentError('ExperienceContextBundle item keys must be unique');
    }
    if (this.usage.length != ContextCategory.values.length ||
        !this.usage.keys.toSet().containsAll(ContextCategory.values)) {
      throw ArgumentError(
        'ExperienceContextBundle requires usage per category',
      );
    }
    for (final category in ContextCategory.values) {
      final categoryItems = this.items.where(
        (item) => item.category == category,
      );
      final measured = ContextUsage(
        items: categoryItems.length,
        bytes: categoryItems.fold<int>(0, (sum, item) => sum + item.byteLength),
      );
      final declared = this.usage[category]!;
      final budget = effectiveBudgets[category];
      if (declared.items != measured.items ||
          declared.bytes != measured.bytes ||
          declared.items > budget.maxItems ||
          declared.bytes > budget.maxBytes) {
        throw ArgumentError('ExperienceContextBundle usage is invalid');
      }
    }
  }

  static const int schemaVersion = 1;
  final Digest contentSetDigest;
  final ContextSelection selection;
  final ContextInclusion inclusion;
  final ContextBudgets requestedBudgets;
  final ContextBudgets effectiveBudgets;
  final List<ContextItem> items;
  final Map<ContextCategory, ContextUsage> usage;
  final List<ContextOmission> omissions;
  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceContextBundle',
    'contentSetDigest': contentSetDigest.value,
    'selection': selection.toJson(),
    'inclusion': inclusion.toJson(),
    'requestedBudgets': requestedBudgets.toJson(),
    'effectiveBudgets': effectiveBudgets.toJson(),
    'items': <Object?>[for (final item in items) item.toJson()],
    'usage': <String, Object?>{
      for (final category in ContextCategory.values)
        category.name: usage[category]!.toJson(),
    },
    'omissions': <Object?>[for (final omission in omissions) omission.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  factory ExperienceContextBundle.fromJson(Object? value) {
    final json = _object(value, 'ExperienceContextBundle');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'contentSetDigest',
      'selection',
      'inclusion',
      'requestedBudgets',
      'effectiveBudgets',
      'items',
      'usage',
      'omissions',
      'digest',
    }, 'ExperienceContextBundle');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ExperienceContextBundle') {
      throw const FormatException('ExperienceContextBundle has invalid header');
    }
    final usageJson = _object(json['usage'], 'ExperienceContextBundle.usage');
    _only(
      usageJson,
      ContextCategory.values.map((item) => item.name).toSet(),
      'ExperienceContextBundle.usage',
    );
    final bundle = ExperienceContextBundle(
      contentSetDigest: Digest(
        _string(json, 'contentSetDigest', 'ExperienceContextBundle'),
      ),
      selection: ContextSelection.fromJson(json['selection']),
      inclusion: ContextInclusion.fromJson(json['inclusion']),
      requestedBudgets: ContextBudgets.fromJson(json['requestedBudgets']),
      effectiveBudgets: ContextBudgets.fromJson(json['effectiveBudgets']),
      items: _list(
        json,
        'items',
        'ExperienceContextBundle',
        max: 5000,
      ).map(ContextItem.fromJson),
      usage: <ContextCategory, ContextUsage>{
        for (final category in ContextCategory.values)
          category: ContextUsage.fromJson(usageJson[category.name]),
      },
      omissions: _list(
        json,
        'omissions',
        'ExperienceContextBundle',
        max: 5000,
      ).map(ContextOmission.fromJson),
    );
    if (Digest(_string(json, 'digest', 'ExperienceContextBundle')) !=
        bundle.digest) {
      throw const FormatException('ExperienceContextBundle.digest mismatch');
    }
    return bundle;
  }
}

final class ContextBuilderDescription {
  ContextBuilderDescription({
    required this.contentSetDigest,
    required Set<ContextCategory> supportedCategories,
    required this.maximumBudgets,
  }) : supportedCategories = Set<ContextCategory>.unmodifiable(
         supportedCategories,
       ) {
    if (this.supportedCategories.isEmpty) {
      throw ArgumentError('ContextBuilderDescription requires support');
    }
  }

  static const int schemaVersion = 1;
  final Digest contentSetDigest;
  final Set<ContextCategory> supportedCategories;
  final ContextBudgets maximumBudgets;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ContextBuilderDescription',
    'status': 'ready',
    'contentSetDigest': contentSetDigest.value,
    'supportedCategories': supportedCategories.map((item) => item.name).toList()
      ..sort(),
    'maximumBudgets': maximumBudgets.toJson(),
  };

  factory ContextBuilderDescription.fromJson(Object? value) {
    final json = _object(value, 'ContextBuilderDescription');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'status',
      'contentSetDigest',
      'supportedCategories',
      'maximumBudgets',
    }, 'ContextBuilderDescription');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ContextBuilderDescription' ||
        json['status'] != 'ready') {
      throw const FormatException(
        'ContextBuilderDescription has invalid header',
      );
    }
    final names = _list(
      json,
      'supportedCategories',
      'ContextBuilderDescription',
      max: ContextCategory.values.length,
    );
    return ContextBuilderDescription(
      contentSetDigest: Digest(
        _string(json, 'contentSetDigest', 'ContextBuilderDescription'),
      ),
      supportedCategories: names.map((name) {
        if (name is! String) {
          throw const FormatException(
            'ContextBuilderDescription categories must be strings',
          );
        }
        return _enumValue(
          ContextCategory.values,
          name,
          'ContextBuilderDescription.supportedCategories',
        );
      }).toSet(),
      maximumBudgets: ContextBudgets.fromJson(json['maximumBudgets']),
    );
  }
}

final class ContextBuildRequest {
  ContextBuildRequest({
    required this.expectedContentSetDigest,
    required this.selection,
    required this.inclusion,
    required this.budgets,
  });

  final Digest expectedContentSetDigest;
  final ContextSelection selection;
  final ContextInclusion inclusion;
  final ContextBudgets budgets;

  Map<String, Object?> toJson() => <String, Object?>{
    'expectedContentSetDigest': expectedContentSetDigest.value,
    'selection': selection.toJson(),
    'inclusion': inclusion.toJson(),
    'budgets': budgets.toJson(),
  };

  factory ContextBuildRequest.fromJson(Object? value) {
    final json = _object(value, 'ContextBuildRequest');
    _only(json, const <String>{
      'expectedContentSetDigest',
      'selection',
      'inclusion',
      'budgets',
    }, 'ContextBuildRequest');
    return ContextBuildRequest(
      expectedContentSetDigest: Digest(
        _string(json, 'expectedContentSetDigest', 'ContextBuildRequest'),
      ),
      selection: ContextSelection.fromJson(json['selection']),
      inclusion: ContextInclusion.fromJson(json['inclusion']),
      budgets: ContextBudgets.fromJson(json['budgets']),
    );
  }
}

final class ContextBuildResult {
  const ContextBuildResult({required this.bundle});

  static const int schemaVersion = 1;
  final ExperienceContextBundle bundle;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ContextBuildResult',
    'bundle': bundle.toJson(),
  };

  factory ContextBuildResult.fromJson(Object? value) {
    final json = _object(value, 'ContextBuildResult');
    _only(json, const <String>{
      'schemaVersion',
      'kind',
      'bundle',
    }, 'ContextBuildResult');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ContextBuildResult') {
      throw const FormatException('ContextBuildResult has invalid header');
    }
    return ContextBuildResult(
      bundle: ExperienceContextBundle.fromJson(json['bundle']),
    );
  }
}

int _max(int left, int right) => left > right ? left : right;

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$path must be an object');
  }
  final output = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$path keys must be strings');
    }
    output[entry.key! as String] = entry.value;
  }
  return output;
}

void _only(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

String _string(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty || utf8.encode(value).length > 4096) {
    throw FormatException('$path.$key must be bounded UTF-8 text');
  }
  return value;
}

String _stringAllowEmpty(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || utf8.encode(value).length > 256 * 1024) {
    throw FormatException('$path.$key must be bounded UTF-8 text');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) return null;
  return _string(json, key, path);
}

int _integer(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! int) throw FormatException('$path.$key must be an integer');
  return value;
}

double _number(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('$path.$key must be a finite number');
  }
  return value.toDouble();
}

bool _boolean(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! bool) throw FormatException('$path.$key must be a boolean');
  return value;
}

List<Object?> _list(
  Map<String, Object?> json,
  String key,
  String path, {
  required int max,
}) {
  final value = json[key];
  if (value is! List<Object?> || value.length > max) {
    throw FormatException('$path.$key must be a bounded array');
  }
  return value;
}

T _enumValue<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has an unknown value');
}

void _id(String value, String path) {
  if (!RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(value) ||
      utf8.encode(value).length > 256) {
    throw ArgumentError.value(value, path, 'must be a bounded canonical ID');
  }
}

void _text(String value, String path, {required int maxBytes}) {
  final bytes = utf8.encode(value);
  if (value.trim().isEmpty ||
      value.contains('\u0000') ||
      bytes.length > maxBytes) {
    throw ArgumentError.value(value, path, 'must be bounded non-empty UTF-8');
  }
}

void _safeInteger(
  int value,
  String path, {
  required int min,
  required int max,
}) {
  if (value < min || value > max || value > 9007199254740991) {
    throw ArgumentError.value(value, path, 'must be a bounded safe integer');
  }
}
