import 'package:experience_contracts/experience_contracts.dart';

final class PreviewCompileException implements Exception {
  PreviewCompileException(Iterable<String> issues)
    : issues = List<String>.unmodifiable(issues);

  final List<String> issues;

  @override
  String toString() => issues.join('\n');
}

final class PreviewVariantCandidate {
  const PreviewVariantCandidate({
    required this.id,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.brightness,
    required this.localeTag,
    required this.textScaleFactor,
    this.themeId,
  });

  final String id;
  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;
  final PreviewBrightness brightness;
  final String localeTag;
  final double textScaleFactor;
  final String? themeId;
}

/// Flutter-independent representation emitted by the source scanner.
final class PreviewDeclarationCandidate {
  PreviewDeclarationCandidate({
    required this.id,
    required this.scenarioId,
    required this.sourceUri,
    required this.declarationName,
    required this.capturePolicyId,
    required List<PreviewVariantCandidate> variants,
    this.fixtureRef,
  }) : variants = List<PreviewVariantCandidate>.unmodifiable(variants);

  final String id;
  final String scenarioId;
  final String sourceUri;
  final String declarationName;
  final String capturePolicyId;
  final String? fixtureRef;
  final List<PreviewVariantCandidate> variants;
}

final class PreviewDescriptorCompiler {
  const PreviewDescriptorCompiler();

  List<PreviewDescriptor> compile({
    required PreviewDeclarationCandidate candidate,
    required CatalogManifest catalog,
  }) {
    final issues = <String>[];
    final scenario = catalog.scenarios
        .where((value) => value.id.value == candidate.scenarioId)
        .firstOrNull;
    if (scenario == null) {
      issues.add(
        '${candidate.sourceUri}#${candidate.declarationName}: unknown '
        'Scenario ${candidate.scenarioId}',
      );
    }
    if (candidate.variants.isEmpty) {
      issues.add(
        '${candidate.sourceUri}#${candidate.declarationName}: '
        'AutoMultiPreview variants must not be empty',
      );
    }

    AutoPreviewId? previewId;
    ScenarioId? scenarioId;
    try {
      previewId = AutoPreviewId(candidate.id);
    } on FormatException catch (error) {
      issues.add(error.message);
    }
    try {
      scenarioId = ScenarioId(candidate.scenarioId);
    } on FormatException catch (error) {
      issues.add(error.message);
    }
    final source = Uri.tryParse(candidate.sourceUri);
    if (source == null || source.scheme != 'package') {
      issues.add(
        '${candidate.sourceUri}#${candidate.declarationName}: source URI '
        'must be a canonical package URI',
      );
    }

    final descriptors = <PreviewDescriptor>[];
    final variantIds = <String>{};
    for (final value in candidate.variants) {
      if (!variantIds.add(value.id)) {
        issues.add(
          '${candidate.sourceUri}#${candidate.declarationName}: duplicate '
          'Variant ${value.id}',
        );
        continue;
      }
      if (scenario == null || previewId == null || scenarioId == null) continue;
      try {
        descriptors.add(
          PreviewDescriptor(
            id: previewId,
            scenarioId: scenarioId,
            variant: Variant(
              id: VariantId(value.id),
              applicationId: scenario.applicationId,
              logicalWidth: value.logicalWidth,
              logicalHeight: value.logicalHeight,
              devicePixelRatio: value.devicePixelRatio,
              brightness: value.brightness,
              localeTag: value.localeTag,
              textScaleFactor: value.textScaleFactor,
              themeId: value.themeId,
            ),
            sourceUri: candidate.sourceUri,
            declarationName: candidate.declarationName,
            capturePolicyId: candidate.capturePolicyId,
            fixtureRef: candidate.fixtureRef,
          ),
        );
      } on ArgumentError catch (error) {
        issues.add(
          '${candidate.sourceUri}#${candidate.declarationName}: '
          '${error.message}',
        );
      } on FormatException catch (error) {
        issues.add(
          '${candidate.sourceUri}#${candidate.declarationName}: '
          '${error.message}',
        );
      }
    }
    if (issues.isNotEmpty) throw PreviewCompileException(issues);
    return List<PreviewDescriptor>.unmodifiable(descriptors);
  }
}

final class PreviewManifestCompiler {
  const PreviewManifestCompiler({
    this.descriptorCompiler = const PreviewDescriptorCompiler(),
  });

  final PreviewDescriptorCompiler descriptorCompiler;

  PreviewManifest compile({
    required Iterable<PreviewDeclarationCandidate> candidates,
    required CatalogManifest catalog,
    required String flutterCompatibility,
  }) {
    final descriptors = <PreviewDescriptor>[];
    final issues = <String>[];
    for (final candidate in candidates) {
      try {
        descriptors.addAll(
          descriptorCompiler.compile(candidate: candidate, catalog: catalog),
        );
      } on PreviewCompileException catch (error) {
        issues.addAll(error.issues);
      }
    }
    if (descriptors.isEmpty && issues.isEmpty) {
      issues.add('Preview source set does not declare any AutoPreview');
    }
    if (issues.isNotEmpty) throw PreviewCompileException(issues);

    try {
      return PreviewManifest(
        catalogDigest: catalog.digest,
        flutterCompatibility: flutterCompatibility,
        descriptors: descriptors,
      );
    } on ArgumentError catch (error) {
      throw PreviewCompileException(<String>['${error.message}']);
    } on FormatException catch (error) {
      throw PreviewCompileException(<String>[error.message]);
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
