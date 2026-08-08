import '../digest.dart';
import 'catalog_contracts.dart';
import 'experience_topology_contracts.dart';
import 'projection_layout_contracts.dart';

/// Portable root document for a catalog-bound Experience topology and its
/// independently versioned projection layouts.
///
/// Layout order is canonical by Projection ID. The semantic topology and each
/// layout retain their own digest so a layout-only refresh can be distinguished
/// from a topology or catalog change without inspecting nested fields.
final class ExperienceTopologyBundle {
  ExperienceTopologyBundle({
    required CatalogManifest catalog,
    required this.topology,
    required Iterable<ProjectionLayoutManifest> layouts,
  }) : catalogDigest = catalog.digest,
       layouts = List<ProjectionLayoutManifest>.unmodifiable(
         List<ProjectionLayoutManifest>.of(layouts)..sort(
           (left, right) =>
               left.projectionId.value.compareTo(right.projectionId.value),
         ),
       ) {
    topology.validateAgainst(catalog);
    final projectionIds = <ExperienceProjectionId>{};
    for (final layout in this.layouts) {
      if (!projectionIds.add(layout.projectionId)) {
        throw ArgumentError(
          'ExperienceTopologyBundle permits one layout per Projection',
        );
      }
      layout.validateAgainst(topology);
    }
  }

  static const int schemaVersion = 1;

  final Digest catalogDigest;
  final ExperienceTopologyManifest topology;
  final List<ProjectionLayoutManifest> layouts;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceTopologyBundle',
    'catalogDigest': catalogDigest.value,
    'topology': topology.toJson(),
    'layouts': <Object?>[for (final layout in layouts) layout.toJson()],
    if (includeDigest) 'digest': digest.value,
  };

  /// Decodes a closed v1 document and revalidates every nested reference
  /// against the caller-supplied canonical [CatalogManifest].
  factory ExperienceTopologyBundle.fromJson(
    Object? value, {
    required CatalogManifest catalog,
  }) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('ExperienceTopologyBundle must be an object');
    }
    const allowed = <String>{
      'schemaVersion',
      'kind',
      'catalogDigest',
      'topology',
      'layouts',
      'digest',
    };
    for (final key in value.keys) {
      if (!allowed.contains(key)) {
        throw FormatException('Unknown ExperienceTopologyBundle.$key');
      }
    }
    if (value['schemaVersion'] != schemaVersion ||
        value['kind'] != 'ExperienceTopologyBundle') {
      throw const FormatException(
        'ExperienceTopologyBundle has invalid schemaVersion or kind',
      );
    }
    final declaredCatalogDigest = _bundleDigest(value, 'catalogDigest');
    if (declaredCatalogDigest != catalog.digest) {
      throw const FormatException(
        'ExperienceTopologyBundle catalogDigest mismatch',
      );
    }
    final rawLayouts = value['layouts'];
    if (rawLayouts is! List<Object?> || rawLayouts.length > 50000) {
      throw const FormatException(
        'ExperienceTopologyBundle.layouts must be a bounded array',
      );
    }
    final bundle = ExperienceTopologyBundle(
      catalog: catalog,
      topology: ExperienceTopologyManifest.fromJson(
        value['topology'],
        catalog: catalog,
      ),
      layouts: rawLayouts
          .map(ProjectionLayoutManifest.fromJson)
          .toList(growable: false),
    );
    final declaredDigest = _bundleDigest(value, 'digest');
    if (declaredDigest != bundle.digest) {
      throw const FormatException('ExperienceTopologyBundle digest mismatch');
    }
    return bundle;
  }
}

Digest _bundleDigest(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('ExperienceTopologyBundle.$key must be a digest');
  }
  return Digest(value);
}
