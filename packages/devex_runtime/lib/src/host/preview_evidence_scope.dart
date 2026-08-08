import 'package:devex_contracts/devex_contracts.dart';

/// Binds one persisted capture to the current descriptor set.
///
/// The resulting manifests intentionally preserve the capture scope. A
/// collection filtered to one Scenario or Variant must be compared with that
/// same scoped manifest, not with every preview currently declared by the
/// Application.
final class PreviewEvidenceScope {
  PreviewEvidenceScope._({
    required Map<String, PreviewDescriptor> descriptors,
    required this.manifestsByApplication,
    required this.hasUnboundItems,
  }) : _descriptors = Map<String, PreviewDescriptor>.unmodifiable(descriptors);

  factory PreviewEvidenceScope.bind({
    required PreviewCaptureManifest capture,
    required Iterable<PreviewDescriptor> currentDescriptors,
    required Digest catalogDigest,
    required String flutterCompatibility,
  }) {
    final available = <String, PreviewDescriptor>{
      for (final descriptor in currentDescriptors)
        _key(descriptor.id, descriptor.scenarioId, descriptor.variant.id):
            descriptor,
    };
    final bound = <String, PreviewDescriptor>{};
    final scoped = <ApplicationId, Map<String, PreviewDescriptor>>{};
    var hasUnboundItems = false;
    for (final item in capture.items) {
      final key = _key(item.previewId, item.scenarioId, item.variantId);
      final descriptor = available[key];
      if (descriptor == null) {
        hasUnboundItems = true;
        continue;
      }
      bound[key] = descriptor;
      scoped.putIfAbsent(
        descriptor.variant.applicationId,
        () => <String, PreviewDescriptor>{},
      )[key] = descriptor;
    }
    return PreviewEvidenceScope._(
      descriptors: bound,
      manifestsByApplication: <ApplicationId, PreviewManifest>{
        for (final entry in scoped.entries)
          entry.key: PreviewManifest(
            catalogDigest: catalogDigest,
            flutterCompatibility: flutterCompatibility,
            descriptors: entry.value.values.toList(growable: false),
          ),
      },
      hasUnboundItems: hasUnboundItems,
    );
  }

  final Map<String, PreviewDescriptor> _descriptors;
  final Map<ApplicationId, PreviewManifest> manifestsByApplication;
  final bool hasUnboundItems;

  PreviewDescriptor? descriptorFor(PreviewCaptureItem item) =>
      _descriptors[_key(item.previewId, item.scenarioId, item.variantId)];

  static String _key(
    AutoPreviewId previewId,
    ScenarioId scenarioId,
    VariantId variantId,
  ) => '${previewId.value}:${scenarioId.value}:${variantId.value}';
}
