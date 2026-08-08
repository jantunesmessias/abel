import 'package:devex_contracts/devex_contracts.dart';

final class ReviewExecutionMaterialization {
  const ReviewExecutionMaterialization({
    required this.catalogDigest,
    required this.guideId,
    required this.stepId,
    required this.scenarioId,
    required this.binding,
    required this.grantDigest,
  });

  final Digest catalogDigest;
  final ReviewGuideId guideId;
  final String stepId;
  final ScenarioId scenarioId;
  final ScenarioExecutionBinding binding;
  final Digest grantDigest;

  Map<String, Object?> toJson() => <String, Object?>{
    'catalogDigest': catalogDigest.value,
    'guideId': guideId.value,
    'stepId': stepId,
    'scenarioId': scenarioId.value,
    'binding': binding.toJson(),
    'grantDigest': grantDigest.value,
  };
}

final class ReviewExecutionResolver {
  ReviewExecutionResolver(CatalogManifest manifest) : _manifest = manifest {
    _guides = <ReviewGuideId, ReviewGuide>{
      for (final guide in manifest.reviewGuides) guide.id: guide,
    };
    _bindings = <ScenarioExecutionBindingId, ScenarioExecutionBinding>{
      for (final binding in manifest.executionBindings) binding.id: binding,
    };
    if (_guides.length != manifest.reviewGuides.length ||
        _bindings.length != manifest.executionBindings.length) {
      throw ArgumentError('Review execution IDs must be unique');
    }
  }

  final CatalogManifest _manifest;
  late final Map<ReviewGuideId, ReviewGuide> _guides;
  late final Map<ScenarioExecutionBindingId, ScenarioExecutionBinding>
  _bindings;

  ReviewExecutionMaterialization open({
    required ReviewGuideId guideId,
    required String stepId,
    required Digest expectedCatalogDigest,
  }) {
    if (expectedCatalogDigest != _manifest.digest) {
      throw StateError(
        'Review catalog changed; refresh before opening an execution binding',
      );
    }
    final guide = _guides[guideId];
    if (guide == null) {
      throw StateError('Unknown ReviewGuide');
    }
    final steps = guide.steps.where((step) => step.id == stepId).toList();
    if (steps.length != 1) {
      throw StateError('Unknown or ambiguous ReviewGuide step');
    }
    final step = steps.single;
    final binding = _bindings[step.bindingId];
    if (binding == null || binding.scenarioId != step.scenarioId) {
      throw StateError('ReviewGuide binding grant is invalid');
    }
    final grantDigest = Digest.semantic(<String, Object?>{
      'operation': 'OpenExecutionBinding',
      'catalogDigest': _manifest.digest.value,
      'guideId': guide.id.value,
      'stepId': step.id,
      'scenarioId': step.scenarioId.value,
      'binding': binding.toJson(),
    });
    return ReviewExecutionMaterialization(
      catalogDigest: _manifest.digest,
      guideId: guide.id,
      stepId: step.id,
      scenarioId: step.scenarioId,
      binding: binding,
      grantDigest: grantDigest,
    );
  }
}
