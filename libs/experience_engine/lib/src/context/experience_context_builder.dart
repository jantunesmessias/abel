import 'package:experience_contracts/experience_contracts.dart';

import '../catalog/authoring_parser.dart';

final class ExperienceContextBuildInputs {
  ExperienceContextBuildInputs({
    required this.catalog,
    required this.topology,
    required Iterable<ProjectionLayoutManifest> layouts,
    required Iterable<AuthoringDocument> documents,
    this.motion,
    this.scenarioLab,
  }) : layouts = List<ProjectionLayoutManifest>.unmodifiable(layouts),
       documents = List<AuthoringDocument>.unmodifiable(documents);

  final CatalogManifest catalog;
  final ExperienceTopologyManifest topology;
  final List<ProjectionLayoutManifest> layouts;
  final List<AuthoringDocument> documents;
  final MotionManifest? motion;
  final ScenarioLabManifest? scenarioLab;
}

final class ExperienceContextBuilder {
  const ExperienceContextBuilder();

  static ContextBudgets get maximumBudgets => ContextBudgets(
    categories: <ContextCategory, ContextCategoryBudget>{
      ContextCategory.sources: ContextCategoryBudget(
        maxItems: 64,
        maxBytes: 512 * 1024,
      ),
      ContextCategory.images: ContextCategoryBudget(
        maxItems: 16,
        maxBytes: 512 * 1024,
      ),
      ContextCategory.evidence: ContextCategoryBudget(
        maxItems: 64,
        maxBytes: 512 * 1024,
      ),
      ContextCategory.history: ContextCategoryBudget(
        maxItems: 32,
        maxBytes: 256 * 1024,
      ),
      ContextCategory.changes: ContextCategoryBudget(
        maxItems: 32,
        maxBytes: 256 * 1024,
      ),
    },
  );

  ExperienceContextBundle build({
    required ContextBuildRequest request,
    required Digest currentContentSetDigest,
    required ExperienceContextBuildInputs inputs,
  }) {
    if (request.expectedContentSetDigest != currentContentSetDigest) {
      throw StateError('Context content set changed; describe it again');
    }
    _validateSelection(request.selection, inputs);
    final effective = _effectiveBudgets(request.budgets);
    final candidates = <ContextCategory, List<ContextItem>>{
      for (final category in ContextCategory.values) category: <ContextItem>[],
    };
    final omissions = <ContextOmission>[];

    _sourceCandidates(
      request.selection,
      inputs,
      candidates[ContextCategory.sources]!,
    );
    _imageCandidates(
      request.selection,
      inputs,
      candidates[ContextCategory.images]!,
    );
    _evidenceCandidates(
      request.selection,
      inputs,
      candidates[ContextCategory.evidence]!,
    );
    _historyCandidates(
      request.selection,
      currentContentSetDigest,
      inputs,
      candidates[ContextCategory.history]!,
    );
    _changeCandidates(request.selection, candidates[ContextCategory.changes]!);

    final accepted = <ContextItem>[];
    final usage = <ContextCategory, ContextUsage>{};
    for (final category in ContextCategory.values) {
      final items = candidates[category]!..sort((a, b) => a.id.compareTo(b.id));
      if (!request.inclusion.includes(category)) {
        omissions.add(
          ContextOmission(
            category: category,
            subject: category.name,
            reason: ContextOmissionReason.omittedByRequest,
          ),
        );
        usage[category] = ContextUsage(items: 0, bytes: 0);
        continue;
      }
      if (items.isEmpty) {
        omissions.add(
          ContextOmission(
            category: category,
            subject: category.name,
            reason: ContextOmissionReason.unavailable,
          ),
        );
        usage[category] = ContextUsage(items: 0, bytes: 0);
        continue;
      }
      final budget = effective[category];
      var count = 0;
      var bytes = 0;
      for (final item in items) {
        if (count >= budget.maxItems ||
            bytes + item.byteLength > budget.maxBytes) {
          omissions.add(
            ContextOmission(
              category: category,
              subject: item.id,
              reason: ContextOmissionReason.budgetExceeded,
            ),
          );
          continue;
        }
        accepted.add(item);
        count += 1;
        bytes += item.byteLength;
      }
      usage[category] = ContextUsage(items: count, bytes: bytes);
    }

    return ExperienceContextBundle(
      contentSetDigest: currentContentSetDigest,
      selection: request.selection,
      inclusion: request.inclusion,
      requestedBudgets: request.budgets,
      effectiveBudgets: effective,
      items: accepted,
      usage: usage,
      omissions: omissions,
    );
  }

  void _validateSelection(
    ContextSelection selection,
    ExperienceContextBuildInputs inputs,
  ) {
    final board = inputs.topology.boards
        .where((item) => item.id == selection.boardId)
        .firstOrNull;
    final projection = inputs.topology.projections
        .where((item) => item.id == selection.projectionId)
        .firstOrNull;
    if (board == null ||
        projection == null ||
        projection.boardId != board.id ||
        !board.projectionIds.contains(projection.id)) {
      throw ArgumentError(
        'Context selection does not resolve one Board/Projection',
      );
    }
    if (selection.journeyId != null &&
        (projection.journeyId != selection.journeyId ||
            !inputs.catalog.journeys.any(
              (item) => item.id == selection.journeyId,
            ))) {
      throw ArgumentError('Context Journey is not bound to the Projection');
    }
    if (selection.scenarioId != null &&
        (!inputs.catalog.scenarios.any(
              (item) => item.id == selection.scenarioId,
            ) ||
            !inputs.topology.nodes.any(
              (node) =>
                  node.projectionId == projection.id &&
                  node.scenarioId == selection.scenarioId,
            ))) {
      throw ArgumentError('Context Scenario is not bound to the Projection');
    }
  }

  ContextBudgets _effectiveBudgets(ContextBudgets requested) => ContextBudgets(
    categories: <ContextCategory, ContextCategoryBudget>{
      for (final category in ContextCategory.values)
        category: ContextCategoryBudget(
          maxItems: _min(
            requested[category].maxItems,
            maximumBudgets[category].maxItems,
          ),
          maxBytes: _min(
            requested[category].maxBytes,
            maximumBudgets[category].maxBytes,
          ),
        ),
    },
  );

  void _sourceCandidates(
    ContextSelection selection,
    ExperienceContextBuildInputs inputs,
    List<ContextItem> output,
  ) {
    final selected = <String>{
      selection.boardId.value,
      selection.projectionId.value,
      if (selection.journeyId != null) selection.journeyId!.value,
      if (selection.scenarioId != null) selection.scenarioId!.value,
    };
    for (final document in inputs.documents) {
      final referencesSelection =
          selected.contains(document.id) ||
          _containsSelectedValue(document.spec, selected);
      if (!referencesSelection) continue;
      final sanitized = _sanitize(<String, Object?>{
        'schemaVersion': document.schemaVersion,
        'kind': document.kind.name,
        'id': document.id,
        'spec': document.spec,
      });
      output.add(
        ContextItem(
          category: ContextCategory.sources,
          id: '${document.kind.name.toLowerCase()}.${document.id}',
          mediaType: 'application/json',
          content: const JcsCanonicalizer().canonicalize(sanitized),
        ),
      );
    }
  }

  void _imageCandidates(
    ContextSelection selection,
    ExperienceContextBuildInputs inputs,
    List<ContextItem> output,
  ) {
    final layout = inputs.layouts
        .where((item) => item.projectionId == selection.projectionId)
        .firstOrNull;
    if (layout == null) return;
    for (final frame in layout.nodeFrames) {
      final node = inputs.topology.nodes
          .where((item) => item.id == frame.nodeInstanceId)
          .firstOrNull;
      if (selection.scenarioId != null &&
          node?.scenarioId != selection.scenarioId) {
        continue;
      }
      output.add(
        ContextItem(
          category: ContextCategory.images,
          id: 'frame.${frame.nodeInstanceId.value}',
          mediaType: 'application/json',
          content: const JcsCanonicalizer().canonicalize(<String, Object?>{
            'projectionId': selection.projectionId.value,
            'nodeInstanceId': frame.nodeInstanceId.value,
            'frame': frame.toJson(),
            'imageBytesIncluded': false,
          }),
        ),
      );
    }
  }

  void _evidenceCandidates(
    ContextSelection selection,
    ExperienceContextBuildInputs inputs,
    List<ContextItem> output,
  ) {
    final scenarioId = selection.scenarioId;
    final lab = inputs.scenarioLab;
    if (scenarioId == null || lab == null) return;
    for (final artifact in lab.supplementalArtifacts) {
      if (artifact.scenarioId != scenarioId) continue;
      output.add(
        ContextItem(
          category: ContextCategory.evidence,
          id: 'artifact.${artifact.id.value}',
          mediaType: 'application/json',
          content: const JcsCanonicalizer().canonicalize(<String, Object?>{
            'scenarioId': scenarioId.value,
            'artifactId': artifact.id.value,
            'artifactDigest': artifact.artifactDigest.value,
            'requiredEvidenceId': artifact.requiredEvidenceId.value,
            'classification': artifact.classification.name,
            'bytesIncluded': false,
          }),
        ),
      );
    }
  }

  void _historyCandidates(
    ContextSelection selection,
    Digest contentSetDigest,
    ExperienceContextBuildInputs inputs,
    List<ContextItem> output,
  ) {
    output.add(
      ContextItem(
        category: ContextCategory.history,
        id: 'content.current',
        mediaType: 'application/json',
        content: const JcsCanonicalizer().canonicalize(<String, Object?>{
          'contentSetDigest': contentSetDigest.value,
          'catalogDigest': inputs.catalog.digest.value,
          'topologyDigest': inputs.topology.digest.value,
          if (inputs.motion != null)
            'motionDigest': inputs.motion!.digest.value,
          'selection': selection.toJson(),
        }),
      ),
    );
  }

  void _changeCandidates(ContextSelection selection, List<ContextItem> output) {
    final digest = selection.changeSetDigest;
    if (digest == null) return;
    output.add(
      ContextItem(
        category: ContextCategory.changes,
        id: 'changeset.selected',
        mediaType: 'application/json',
        content: const JcsCanonicalizer().canonicalize(<String, Object?>{
          'changeSetDigest': digest.value,
          'contentIncluded': false,
        }),
      ),
    );
  }
}

bool _containsSelectedValue(Object? value, Set<String> selected) {
  if (value is String) return selected.contains(value);
  if (value is List<Object?>) {
    return value.any((item) => _containsSelectedValue(item, selected));
  }
  if (value is Map<String, Object?>) {
    return value.values.any((item) => _containsSelectedValue(item, selected));
  }
  return false;
}

Object? _sanitize(Object? value) {
  if (value is List<Object?>) {
    return value.map(_sanitize).toList(growable: false);
  }
  if (value is Map<String, Object?>) {
    final output = <String, Object?>{};
    for (final entry in value.entries) {
      if (_sensitiveKey(entry.key)) {
        output[entry.key] = '[REDACTED]';
      } else {
        output[entry.key] = _sanitize(entry.value);
      }
    }
    return output;
  }
  if (value is String && _sensitiveValue(value)) return '[REDACTED]';
  return value;
}

bool _sensitiveKey(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
      .toLowerCase();
  return normalized.contains('authorization') ||
      normalized.contains('cookie') ||
      normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('password') ||
      normalized.contains('apikey') ||
      normalized.contains('privatekey') ||
      normalized.contains('connectionstring') ||
      normalized == 'dsn';
}

bool _sensitiveValue(String value) =>
    RegExp(
      r'\bbearer\s+[A-Za-z0-9._~+/=-]+',
      caseSensitive: false,
    ).hasMatch(value) ||
    RegExp(
      r'\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis)://[^\s]+',
      caseSensitive: false,
    ).hasMatch(value) ||
    value.contains('-----BEGIN PRIVATE KEY-----') ||
    value.contains('-----BEGIN RSA PRIVATE KEY-----');

int _min(int left, int right) => left < right ? left : right;
