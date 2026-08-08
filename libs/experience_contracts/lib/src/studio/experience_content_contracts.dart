import '../digest.dart';
import 'studio_workspace_contracts.dart';

/// Immutable identity for one atomically published Experience content set.
///
/// [revision] is an observation/fencing value. It is deliberately excluded
/// from [contentSetDigest]. [workspaceSnapshotDigest] binds the exact snapshot
/// bytes, while [workspaceContentDigest] gives equivalent semantic snapshots a
/// stable identity across observation metadata and renewed transport grants.
final class ExperienceContentSetIdentity {
  ExperienceContentSetIdentity({
    required this.revision,
    required this.catalogDigest,
    required this.workspaceSnapshotDigest,
    required this.workspaceContentDigest,
    this.experienceTopologyBundleDigest,
    this.scenarioFacetManifestDigest,
    this.scenarioLabManifestDigest,
    this.motionManifestDigest,
  }) {
    if (revision < 1 || revision > 9007199254740991) {
      throw ArgumentError.value(
        revision,
        'revision',
        'must be a positive JSON-safe integer',
      );
    }
  }

  final int revision;
  final Digest catalogDigest;
  final Digest workspaceSnapshotDigest;
  final Digest workspaceContentDigest;
  final Digest? experienceTopologyBundleDigest;
  final Digest? scenarioFacetManifestDigest;
  final Digest? scenarioLabManifestDigest;
  final Digest? motionManifestDigest;

  late final Digest contentSetDigest = Digest.semantic(_digestJson());

  Map<String, Object?> _digestJson() => <String, Object?>{
    'catalogDigest': catalogDigest.value,
    'workspaceContentDigest': workspaceContentDigest.value,
    if (experienceTopologyBundleDigest != null)
      'experienceTopologyBundleDigest': experienceTopologyBundleDigest!.value,
    if (scenarioFacetManifestDigest != null)
      'scenarioFacetManifestDigest': scenarioFacetManifestDigest!.value,
    if (scenarioLabManifestDigest != null)
      'scenarioLabManifestDigest': scenarioLabManifestDigest!.value,
    if (motionManifestDigest != null)
      'motionManifestDigest': motionManifestDigest!.value,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'revision': revision,
    'workspaceSnapshotDigest': workspaceSnapshotDigest.value,
    ..._digestJson(),
    'contentSetDigest': contentSetDigest.value,
  };

  factory ExperienceContentSetIdentity.fromJson(
    Map<String, Object?> json,
    String path,
  ) {
    _contentOnly(json, const <String>{
      'revision',
      'catalogDigest',
      'workspaceSnapshotDigest',
      'workspaceContentDigest',
      'experienceTopologyBundleDigest',
      'scenarioFacetManifestDigest',
      'scenarioLabManifestDigest',
      'motionManifestDigest',
      'contentSetDigest',
    }, path);
    final revision = json['revision'];
    if (revision is! int) {
      throw FormatException('$path.revision must be an integer');
    }
    final identity = ExperienceContentSetIdentity(
      revision: revision,
      catalogDigest: Digest(_contentString(json, 'catalogDigest', path)),
      workspaceSnapshotDigest: Digest(
        _contentString(json, 'workspaceSnapshotDigest', path),
      ),
      workspaceContentDigest: Digest(
        _contentString(json, 'workspaceContentDigest', path),
      ),
      experienceTopologyBundleDigest: _contentOptionalDigest(
        json,
        'experienceTopologyBundleDigest',
        path,
      ),
      scenarioFacetManifestDigest: _contentOptionalDigest(
        json,
        'scenarioFacetManifestDigest',
        path,
      ),
      scenarioLabManifestDigest: _contentOptionalDigest(
        json,
        'scenarioLabManifestDigest',
        path,
      ),
      motionManifestDigest: _contentOptionalDigest(
        json,
        'motionManifestDigest',
        path,
      ),
    );
    if (Digest(_contentString(json, 'contentSetDigest', path)) !=
        identity.contentSetDigest) {
      throw FormatException('$path.contentSetDigest does not match content');
    }
    return identity;
  }
}

final class ExperienceContentSetDescription {
  const ExperienceContentSetDescription({required this.identity});

  static const int schemaVersion = 2;
  final ExperienceContentSetIdentity identity;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceContentSetDescription',
    'status': 'ready',
    ...identity.toJson(),
  };

  factory ExperienceContentSetDescription.fromJson(Object? value) {
    final json = _contentObject(value, 'ExperienceContentSetDescription');
    _contentOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'status',
      'revision',
      'catalogDigest',
      'workspaceSnapshotDigest',
      'workspaceContentDigest',
      'experienceTopologyBundleDigest',
      'scenarioFacetManifestDigest',
      'scenarioLabManifestDigest',
      'motionManifestDigest',
      'contentSetDigest',
    }, 'ExperienceContentSetDescription');
    _contentHeader(json, 'ExperienceContentSetDescription', status: true);
    return ExperienceContentSetDescription(
      identity: ExperienceContentSetIdentity.fromJson(
        _identityFields(json),
        'ExperienceContentSetDescription',
      ),
    );
  }
}

/// Atomic set of bounded resources for one immutable generation.
///
/// Resource URLs and expiry timestamps are transport grants and never
/// participate in [ExperienceContentSetIdentity.contentSetDigest].
final class ExperienceContentSetOpenResult {
  ExperienceContentSetOpenResult({
    required this.identity,
    required this.workspaceSnapshot,
    this.experienceTopologyBundle,
    this.scenarioFacetManifest,
    this.scenarioLabManifest,
    this.motionManifest,
  }) {
    _paired(
      identity.experienceTopologyBundleDigest,
      experienceTopologyBundle,
      'Experience topology',
    );
    _paired(
      identity.scenarioFacetManifestDigest,
      scenarioFacetManifest,
      'Scenario facet',
    );
    _paired(
      identity.scenarioLabManifestDigest,
      scenarioLabManifest,
      'Scenario Lab',
    );
    _paired(identity.motionManifestDigest, motionManifest, 'Motion');
    _validateResource(workspaceSnapshot, 'workspace-snapshot');
    if (experienceTopologyBundle != null) {
      _validateResource(
        experienceTopologyBundle!,
        'experience-topology-bundle',
      );
    }
    if (scenarioFacetManifest != null) {
      _validateResource(scenarioFacetManifest!, 'scenario-facet-manifest');
    }
    if (scenarioLabManifest != null) {
      _validateResource(scenarioLabManifest!, 'scenario-lab-manifest');
    }
    if (motionManifest != null) {
      _validateResource(motionManifest!, 'motion-manifest');
    }
  }

  static const int schemaVersion = 2;
  final ExperienceContentSetIdentity identity;
  final ResourceHandle workspaceSnapshot;
  final ResourceHandle? experienceTopologyBundle;
  final ResourceHandle? scenarioFacetManifest;
  final ResourceHandle? scenarioLabManifest;
  final ResourceHandle? motionManifest;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ExperienceContentSetOpenResult',
    ...identity.toJson(),
    'resources': <String, Object?>{
      'workspaceSnapshot': workspaceSnapshot.toJson(),
      if (experienceTopologyBundle != null)
        'experienceTopologyBundle': experienceTopologyBundle!.toJson(),
      if (scenarioFacetManifest != null)
        'scenarioFacetManifest': scenarioFacetManifest!.toJson(),
      if (scenarioLabManifest != null)
        'scenarioLabManifest': scenarioLabManifest!.toJson(),
      if (motionManifest != null) 'motionManifest': motionManifest!.toJson(),
    },
  };

  factory ExperienceContentSetOpenResult.fromJson(Object? value) {
    final json = _contentObject(value, 'ExperienceContentSetOpenResult');
    _contentOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'revision',
      'catalogDigest',
      'workspaceSnapshotDigest',
      'workspaceContentDigest',
      'experienceTopologyBundleDigest',
      'scenarioFacetManifestDigest',
      'scenarioLabManifestDigest',
      'motionManifestDigest',
      'contentSetDigest',
      'resources',
    }, 'ExperienceContentSetOpenResult');
    _contentHeader(json, 'ExperienceContentSetOpenResult');
    final resources = _contentObject(
      json['resources'],
      'ExperienceContentSetOpenResult.resources',
    );
    _contentOnly(resources, const <String>{
      'workspaceSnapshot',
      'experienceTopologyBundle',
      'scenarioFacetManifest',
      'scenarioLabManifest',
      'motionManifest',
    }, 'ExperienceContentSetOpenResult.resources');
    if (!resources.containsKey('workspaceSnapshot')) {
      throw const FormatException(
        'ExperienceContentSetOpenResult.resources.workspaceSnapshot is required',
      );
    }
    return ExperienceContentSetOpenResult(
      identity: ExperienceContentSetIdentity.fromJson(
        _identityFields(json),
        'ExperienceContentSetOpenResult',
      ),
      workspaceSnapshot: ResourceHandle.fromJson(
        resources['workspaceSnapshot'],
      ),
      experienceTopologyBundle: _optionalResource(
        resources,
        'experienceTopologyBundle',
      ),
      scenarioFacetManifest: _optionalResource(
        resources,
        'scenarioFacetManifest',
      ),
      scenarioLabManifest: _optionalResource(resources, 'scenarioLabManifest'),
      motionManifest: _optionalResource(resources, 'motionManifest'),
    );
  }

  static void _paired(Digest? digest, ResourceHandle? resource, String name) {
    if ((digest == null) != (resource == null)) {
      throw ArgumentError('$name digest and resource must be present together');
    }
  }

  static void _validateResource(ResourceHandle resource, String purpose) {
    if (resource.purpose != purpose ||
        resource.mediaType != 'application/json' ||
        resource.size < 1) {
      throw ArgumentError(
        'Content resource must be non-empty and use purpose $purpose and application/json',
      );
    }
  }
}

Map<String, Object?> _identityFields(Map<String, Object?> json) =>
    <String, Object?>{
      for (final key in const <String>{
        'revision',
        'catalogDigest',
        'workspaceSnapshotDigest',
        'workspaceContentDigest',
        'experienceTopologyBundleDigest',
        'scenarioFacetManifestDigest',
        'scenarioLabManifestDigest',
        'motionManifestDigest',
        'contentSetDigest',
      })
        if (json.containsKey(key)) key: json[key],
    };

ResourceHandle? _optionalResource(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) return null;
  return ResourceHandle.fromJson(json[key]);
}

Map<String, Object?> _contentObject(Object? value, String path) {
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

void _contentOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw FormatException('$path has unknown fields: ${unknown.join(', ')}');
  }
}

void _contentHeader(
  Map<String, Object?> json,
  String kind, {
  bool status = false,
}) {
  if (json['schemaVersion'] != 2 || json['kind'] != kind) {
    throw FormatException('$kind has an invalid schemaVersion or kind');
  }
  if (status && json['status'] != 'ready') {
    throw FormatException('$kind.status must be ready');
  }
}

String _contentString(Map<String, Object?> json, String key, String path) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > 512) {
    throw FormatException('$path.$key must be a bounded string');
  }
  return value;
}

Digest? _contentOptionalDigest(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return Digest(_contentString(json, key, path));
}
