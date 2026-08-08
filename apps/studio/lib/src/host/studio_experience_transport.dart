import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';

import 'studio_host_client.dart';

void requireStudioExperienceContentTransport(Set<String> capabilities) {
  const describe = 'experience.content.describe';
  const open = 'experience.content.open';
  final hasDescribe = capabilities.contains(describe);
  final hasOpen = capabilities.contains(open);
  if (!hasDescribe || !hasOpen) {
    throw const FormatException(
      'Workspace Host must expose the complete Experience content-set capability',
    );
  }
}

bool observesExperienceGenerationEvent({
  required Set<String> capabilities,
  required String method,
}) {
  requireStudioExperienceContentTransport(capabilities);
  return method == 'experience.content.changed';
}

/// A fenced describe/open pair whose resource grants were validated before
/// any bytes are decoded or published to Studio state.
final class StudioExperienceContentOpen {
  StudioExperienceContentOpen._({
    required this.description,
    required this.opened,
  });

  final ExperienceContentSetDescription description;
  final ExperienceContentSetOpenResult opened;

  ExperienceContentSetIdentity get identity => opened.identity;

  factory StudioExperienceContentOpen.fromRpc({
    required ExperienceContentSetDescription description,
    required Object? openResponse,
    required Uri hostOrigin,
    required DateTime nowUtc,
  }) {
    final opened = ExperienceContentSetOpenResult.fromJson(openResponse);
    if (!_sameContentIdentity(opened.identity, description.identity)) {
      throw const FormatException(
        'Experience content changed while opening its resources',
      );
    }
    _validateContentResource(
      opened.workspaceSnapshot,
      hostOrigin: hostOrigin,
      nowUtc: nowUtc,
      purpose: 'workspace-snapshot',
      maxBytes: 16 * 1024 * 1024,
    );
    final topology = opened.experienceTopologyBundle;
    if (topology != null) {
      _validateContentResource(
        topology,
        hostOrigin: hostOrigin,
        nowUtc: nowUtc,
        purpose: 'experience-topology-bundle',
        maxBytes: 64 * 1024 * 1024,
      );
    }
    final facets = opened.scenarioFacetManifest;
    if (facets != null) {
      _validateContentResource(
        facets,
        hostOrigin: hostOrigin,
        nowUtc: nowUtc,
        purpose: 'scenario-facet-manifest',
        maxBytes: 64 * 1024 * 1024,
      );
    }
    final lab = opened.scenarioLabManifest;
    if (lab != null) {
      _validateContentResource(
        lab,
        hostOrigin: hostOrigin,
        nowUtc: nowUtc,
        purpose: 'scenario-lab-manifest',
        maxBytes: 64 * 1024 * 1024,
      );
    }
    final motion = opened.motionManifest;
    if (motion != null) {
      _validateContentResource(
        motion,
        hostOrigin: hostOrigin,
        nowUtc: nowUtc,
        purpose: 'motion-manifest',
        maxBytes: 64 * 1024 * 1024,
      );
    }
    return StudioExperienceContentOpen._(
      description: description,
      opened: opened,
    );
  }

  StudioWorkspaceContent decode({
    required List<int> workspaceSnapshotBytes,
    List<int>? experienceTopologyBundleBytes,
    List<int>? scenarioFacetManifestBytes,
    List<int>? scenarioLabManifestBytes,
    List<int>? motionManifestBytes,
  }) {
    final snapshot = WorkspaceSnapshot.fromJson(
      _decodeRequiredResource(
        opened.workspaceSnapshot,
        workspaceSnapshotBytes,
        'WorkspaceSnapshot',
      ),
    );
    if (snapshot.digest != identity.workspaceSnapshotDigest ||
        snapshot.workspaceContentDigest != identity.workspaceContentDigest ||
        snapshot.catalog.digest != identity.catalogDigest) {
      throw const FormatException(
        'WorkspaceSnapshot does not match its content-set identity',
      );
    }

    final topologyJson = _decodeOptionalResource(
      opened.experienceTopologyBundle,
      experienceTopologyBundleBytes,
      'ExperienceTopologyBundle',
    );
    final experienceBundle = topologyJson == null
        ? null
        : ExperienceTopologyBundle.fromJson(
            topologyJson,
            catalog: snapshot.catalog,
          );
    if (experienceBundle?.digest != identity.experienceTopologyBundleDigest) {
      throw const FormatException(
        'ExperienceTopologyBundle does not match its content-set identity',
      );
    }

    final facetsJson = _decodeOptionalResource(
      opened.scenarioFacetManifest,
      scenarioFacetManifestBytes,
      'ScenarioFacetManifest',
    );
    final scenarioFacets = facetsJson == null
        ? null
        : ScenarioFacetManifest.fromJson(facetsJson, catalog: snapshot.catalog);
    if (scenarioFacets?.digest != identity.scenarioFacetManifestDigest) {
      throw const FormatException(
        'ScenarioFacetManifest does not match its content-set identity',
      );
    }

    final labJson = _decodeOptionalResource(
      opened.scenarioLabManifest,
      scenarioLabManifestBytes,
      'ScenarioLabManifest',
    );
    final scenarioLab = labJson == null
        ? null
        : ScenarioLabManifest.fromJson(labJson, catalog: snapshot.catalog);
    if (scenarioLab?.digest != identity.scenarioLabManifestDigest) {
      throw const FormatException(
        'ScenarioLabManifest does not match its content-set identity',
      );
    }

    final motionJson = _decodeOptionalResource(
      opened.motionManifest,
      motionManifestBytes,
      'MotionManifest',
    );
    final motion = motionJson == null
        ? null
        : MotionManifest.fromJson(
            motionJson,
            catalog: snapshot.catalog,
            topology:
                experienceBundle?.topology ??
                (throw const FormatException(
                  'MotionManifest requires Experience topology',
                )),
          );
    if (motion?.digest != identity.motionManifestDigest) {
      throw const FormatException(
        'MotionManifest does not match its content-set identity',
      );
    }

    return StudioWorkspaceContent(
      snapshot: snapshot,
      experienceBundle: experienceBundle,
      scenarioFacets: scenarioFacets,
      scenarioLab: scenarioLab,
      motion: motion,
      identity: identity,
    );
  }
}

bool _sameContentIdentity(
  ExperienceContentSetIdentity left,
  ExperienceContentSetIdentity right,
) =>
    left.revision == right.revision &&
    left.catalogDigest == right.catalogDigest &&
    left.workspaceSnapshotDigest == right.workspaceSnapshotDigest &&
    left.workspaceContentDigest == right.workspaceContentDigest &&
    left.experienceTopologyBundleDigest ==
        right.experienceTopologyBundleDigest &&
    left.scenarioFacetManifestDigest == right.scenarioFacetManifestDigest &&
    left.scenarioLabManifestDigest == right.scenarioLabManifestDigest &&
    left.motionManifestDigest == right.motionManifestDigest &&
    left.contentSetDigest == right.contentSetDigest;

void _validateContentResource(
  ResourceHandle resource, {
  required Uri hostOrigin,
  required DateTime nowUtc,
  required String purpose,
  required int maxBytes,
}) {
  if (resource.purpose != purpose ||
      resource.mediaType != 'application/json' ||
      resource.uri.origin != hostOrigin.origin ||
      resource.size < 1 ||
      resource.size > maxBytes ||
      resource.isExpiredAt(nowUtc)) {
    throw FormatException('$purpose resource handle is not allowed');
  }
}

Object? _decodeRequiredResource(
  ResourceHandle resource,
  List<int> bytes,
  String path,
) {
  if (bytes.length != resource.size || Digest.bytes(bytes) != resource.digest) {
    throw FormatException('$path resource bytes do not match their handle');
  }
  return jsonDecode(utf8.decode(bytes));
}

Object? _decodeOptionalResource(
  ResourceHandle? resource,
  List<int>? bytes,
  String path,
) {
  if (resource == null && bytes == null) return null;
  if (resource == null || bytes == null) {
    throw FormatException('$path resource and bytes must be present together');
  }
  return _decodeRequiredResource(resource, bytes, path);
}

/// Strict, lightweight identity returned before opening the bounded Experience
/// resource. It is intentionally separate from [WorkspaceSnapshot].
final class StudioExperienceDescription {
  StudioExperienceDescription._({
    required this.revision,
    required this.catalogDigest,
    required this.topologyDigest,
    required this.layoutDigests,
    required this.bundleDigest,
  });

  final int revision;
  final Digest catalogDigest;
  final Digest? topologyDigest;
  final Map<ExperienceProjectionId, Digest> layoutDigests;
  final Digest? bundleDigest;

  bool get isAbsent => bundleDigest == null;

  factory StudioExperienceDescription.fromJson(
    Object? value, {
    required CatalogManifest catalog,
  }) {
    final json = _experienceObject(value, 'ExperienceDescription');
    _experienceOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'status',
      'revision',
      'catalogDigest',
      'topologyDigest',
      'layoutDigests',
      'bundleDigest',
    }, 'ExperienceDescription');
    if (json['schemaVersion'] != 1 || json['kind'] != 'ExperienceDescription') {
      throw const FormatException(
        'ExperienceDescription has invalid schemaVersion or kind',
      );
    }
    final status = _experienceString(json, 'status', 'ExperienceDescription');
    if (status != 'ready' && status != 'absent') {
      throw const FormatException('ExperienceDescription.status is invalid');
    }
    final revision = _experienceInteger(
      json,
      'revision',
      'ExperienceDescription',
    );
    if (revision < 1 || revision > 9007199254740991) {
      throw const FormatException(
        'ExperienceDescription.revision must be a safe positive integer',
      );
    }
    final catalogDigest = Digest(
      _experienceString(json, 'catalogDigest', 'ExperienceDescription'),
    );
    if (catalogDigest != catalog.digest) {
      throw const FormatException(
        'ExperienceDescription belongs to another CatalogManifest',
      );
    }

    final rawLayouts = json['layoutDigests'];
    final layouts = <ExperienceProjectionId, Digest>{};
    if (rawLayouts != null) {
      if (rawLayouts is! List<Object?> || rawLayouts.length > 50000) {
        throw const FormatException(
          'ExperienceDescription.layoutDigests must be a bounded array',
        );
      }
      for (final rawLayout in rawLayouts) {
        final layout = _experienceObject(
          rawLayout,
          'ExperienceDescription.layoutDigests[]',
        );
        _experienceOnly(layout, const <String>{
          'projectionId',
          'digest',
        }, 'ExperienceDescription.layoutDigests[]');
        final projectionId = ExperienceProjectionId(
          _experienceString(
            layout,
            'projectionId',
            'ExperienceDescription.layoutDigests[]',
          ),
        );
        final digest = Digest(
          _experienceString(
            layout,
            'digest',
            'ExperienceDescription.layoutDigests[]',
          ),
        );
        if (layouts.containsKey(projectionId)) {
          throw const FormatException(
            'ExperienceDescription.layoutDigests contains duplicate Projections',
          );
        }
        layouts[projectionId] = digest;
      }
    }

    final topologyDigest = json['topologyDigest'] == null
        ? null
        : Digest(
            _experienceString(json, 'topologyDigest', 'ExperienceDescription'),
          );
    final bundleDigest = json['bundleDigest'] == null
        ? null
        : Digest(
            _experienceString(json, 'bundleDigest', 'ExperienceDescription'),
          );
    if (status == 'absent') {
      if (topologyDigest != null ||
          bundleDigest != null ||
          layouts.isNotEmpty) {
        throw const FormatException(
          'Absent ExperienceDescription must not declare content digests',
        );
      }
    } else if (topologyDigest == null ||
        bundleDigest == null ||
        rawLayouts == null) {
      throw const FormatException(
        'Ready ExperienceDescription requires all content digests',
      );
    }
    return StudioExperienceDescription._(
      revision: revision,
      catalogDigest: catalogDigest,
      topologyDigest: topologyDigest,
      layoutDigests: Map<ExperienceProjectionId, Digest>.unmodifiable(layouts),
      bundleDigest: bundleDigest,
    );
  }

  void validateBundle(ExperienceTopologyBundle bundle) {
    if (isAbsent ||
        bundle.catalogDigest != catalogDigest ||
        bundle.digest != bundleDigest ||
        bundle.topology.digest != topologyDigest) {
      throw const FormatException(
        'ExperienceTopologyBundle identity does not match its description',
      );
    }
    final actualLayouts = <ExperienceProjectionId, Digest>{
      for (final layout in bundle.layouts) layout.projectionId: layout.digest,
    };
    if (actualLayouts.length != layoutDigests.length ||
        layoutDigests.entries.any(
          (entry) => actualLayouts[entry.key] != entry.value,
        )) {
      throw const FormatException(
        'ExperienceTopologyBundle layouts do not match its description',
      );
    }
  }
}

/// Strict identity wrapper returned by `experience.open`.
final class StudioExperienceOpen {
  StudioExperienceOpen._({
    required this.revision,
    required this.bundleDigest,
    required this.resource,
  });

  final int revision;
  final Digest bundleDigest;
  final ResourceHandle resource;

  factory StudioExperienceOpen.fromJson(
    Object? value, {
    required StudioExperienceDescription description,
    required Uri hostOrigin,
    required DateTime nowUtc,
  }) {
    if (description.isAbsent) {
      throw const FormatException('Cannot open an absent Experience topology');
    }
    final json = _experienceObject(value, 'ExperienceOpen');
    _experienceOnly(json, const <String>{
      'revision',
      'bundleDigest',
      'resource',
    }, 'ExperienceOpen');
    final revision = _experienceInteger(json, 'revision', 'ExperienceOpen');
    final bundleDigest = Digest(
      _experienceString(json, 'bundleDigest', 'ExperienceOpen'),
    );
    if (revision != description.revision ||
        bundleDigest != description.bundleDigest) {
      throw const FormatException(
        'Experience topology changed while opening its bundle',
      );
    }
    final resource = ResourceHandle.fromJson(json['resource']);
    if (resource.purpose != 'experience-topology-bundle' ||
        resource.mediaType != 'application/json' ||
        resource.uri.origin != hostOrigin.origin ||
        resource.size <= 0 ||
        resource.size > 64 * 1024 * 1024 ||
        resource.isExpiredAt(nowUtc)) {
      throw const FormatException(
        'Experience topology resource handle is not allowed',
      );
    }
    return StudioExperienceOpen._(
      revision: revision,
      bundleDigest: bundleDigest,
      resource: resource,
    );
  }
}

Map<String, Object?> _experienceObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _experienceOnly(
  Map<String, Object?> value,
  Set<String> allowed,
  String path,
) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

String _experienceString(Map<String, Object?> value, String key, String path) {
  final item = value[key];
  if (item is! String || item.trim().isEmpty || item.length > 4096) {
    throw FormatException('$path.$key must be a bounded non-empty string');
  }
  return item;
}

int _experienceInteger(Map<String, Object?> value, String key, String path) {
  final item = value[key];
  if (item is! int) throw FormatException('$path.$key must be an integer');
  return item;
}
