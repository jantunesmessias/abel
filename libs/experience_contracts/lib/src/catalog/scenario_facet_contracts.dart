import '../digest.dart';
import '../preview/preview_contracts.dart';
import 'catalog_contracts.dart';

final class ScenarioKindId extends OpaqueId {
  factory ScenarioKindId(String value) {
    _facetOpaqueId(value, 'ScenarioKind');
    return ScenarioKindId._(value);
  }

  const ScenarioKindId._(super.value);
}

final class ExperienceSurfaceId extends OpaqueId {
  factory ExperienceSurfaceId(String value) {
    _facetOpaqueId(value, 'ExperienceSurface');
    return ExperienceSurfaceId._(value);
  }

  const ExperienceSurfaceId._(super.value);
}

final class ScenarioStateId extends OpaqueId {
  factory ScenarioStateId(String value) {
    _facetOpaqueId(value, 'ScenarioState');
    return ScenarioStateId._(value);
  }

  const ScenarioStateId._(super.value);
}

final class OwnershipAreaId extends OpaqueId {
  factory OwnershipAreaId(String value) {
    _facetOpaqueId(value, 'OwnershipArea');
    return OwnershipAreaId._(value);
  }

  const OwnershipAreaId._(super.value);
}

final class ScenarioTagId extends OpaqueId {
  factory ScenarioTagId(String value) {
    _facetOpaqueId(value, 'ScenarioTag');
    return ScenarioTagId._(value);
  }

  const ScenarioTagId._(super.value);
}

final class ExperienceComponentId extends OpaqueId {
  factory ExperienceComponentId(String value) {
    _facetOpaqueId(value, 'ExperienceComponent');
    return ExperienceComponentId._(value);
  }

  const ExperienceComponentId._(super.value);
}

final class ScenarioFixtureId extends OpaqueId {
  factory ScenarioFixtureId(String value) {
    _facetOpaqueId(value, 'ScenarioFixture');
    return ScenarioFixtureId._(value);
  }

  const ScenarioFixtureId._(super.value);
}

final class FormFactorId extends OpaqueId {
  factory FormFactorId(String value) {
    _facetOpaqueId(value, 'FormFactor');
    return FormFactorId._(value);
  }

  const FormFactorId._(super.value);
}

final class PresentationFrameId extends OpaqueId {
  factory PresentationFrameId(String value) {
    _facetOpaqueId(value, 'PresentationFrame');
    return PresentationFrameId._(value);
  }

  const PresentationFrameId._(super.value);
}

final class RenderProviderId extends OpaqueId {
  factory RenderProviderId(String value) {
    _facetOpaqueId(value, 'RenderProvider');
    return RenderProviderId._(value);
  }

  const RenderProviderId._(super.value);
}

final class RenderHarnessId extends OpaqueId {
  factory RenderHarnessId(String value) {
    _facetOpaqueId(value, 'RenderHarness');
    return RenderHarnessId._(value);
  }

  const RenderHarnessId._(super.value);
}

enum ScenarioLifecycle { concept, current, historical }

enum ScenarioRenderSourceKind {
  previewDescriptor,
  executionBinding,
  externalHarness,
  archiveArtifact,
}

enum PresentationFrameKind { device, browser, desktopWindow, component, none }

final class ScenarioKindDefinition {
  ScenarioKindDefinition({required this.id, required this.displayName}) {
    _facetText(displayName, 'ScenarioKindDefinition.displayName');
  }

  final ScenarioKindId id;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
  };

  factory ScenarioKindDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'ScenarioKindDefinition');
    _facetOnly(json, const <String>{
      'id',
      'displayName',
    }, 'ScenarioKindDefinition');
    return ScenarioKindDefinition(
      id: ScenarioKindId(_facetString(json, 'id', 'ScenarioKindDefinition')),
      displayName: _facetString(
        json,
        'displayName',
        'ScenarioKindDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class ExperienceSurfaceDefinition {
  ExperienceSurfaceDefinition({
    required this.id,
    required this.applicationId,
    required this.displayName,
  }) {
    _facetText(displayName, 'ExperienceSurfaceDefinition.displayName');
  }

  final ExperienceSurfaceId id;
  final ApplicationId applicationId;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'applicationId': applicationId.value,
    'displayName': displayName,
  };

  factory ExperienceSurfaceDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'ExperienceSurfaceDefinition');
    _facetOnly(json, const <String>{
      'id',
      'applicationId',
      'displayName',
    }, 'ExperienceSurfaceDefinition');
    return ExperienceSurfaceDefinition(
      id: ExperienceSurfaceId(
        _facetString(json, 'id', 'ExperienceSurfaceDefinition'),
      ),
      applicationId: ApplicationId(
        _facetString(json, 'applicationId', 'ExperienceSurfaceDefinition'),
      ),
      displayName: _facetString(
        json,
        'displayName',
        'ExperienceSurfaceDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class ScenarioStateDefinition {
  ScenarioStateDefinition({
    required this.id,
    required this.surfaceId,
    required this.displayName,
  }) {
    _facetText(displayName, 'ScenarioStateDefinition.displayName');
  }

  final ScenarioStateId id;
  final ExperienceSurfaceId surfaceId;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'surfaceId': surfaceId.value,
    'displayName': displayName,
  };

  factory ScenarioStateDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'ScenarioStateDefinition');
    _facetOnly(json, const <String>{
      'id',
      'surfaceId',
      'displayName',
    }, 'ScenarioStateDefinition');
    return ScenarioStateDefinition(
      id: ScenarioStateId(_facetString(json, 'id', 'ScenarioStateDefinition')),
      surfaceId: ExperienceSurfaceId(
        _facetString(json, 'surfaceId', 'ScenarioStateDefinition'),
      ),
      displayName: _facetString(
        json,
        'displayName',
        'ScenarioStateDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class OwnershipAreaDefinition {
  OwnershipAreaDefinition({required this.id, required this.displayName}) {
    _facetText(displayName, 'OwnershipAreaDefinition.displayName');
  }

  final OwnershipAreaId id;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
  };

  factory OwnershipAreaDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'OwnershipAreaDefinition');
    _facetOnly(json, const <String>{
      'id',
      'displayName',
    }, 'OwnershipAreaDefinition');
    return OwnershipAreaDefinition(
      id: OwnershipAreaId(_facetString(json, 'id', 'OwnershipAreaDefinition')),
      displayName: _facetString(
        json,
        'displayName',
        'OwnershipAreaDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class ScenarioTagDefinition {
  ScenarioTagDefinition({required this.id, required this.displayName}) {
    _facetText(displayName, 'ScenarioTagDefinition.displayName');
  }

  final ScenarioTagId id;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
  };

  factory ScenarioTagDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'ScenarioTagDefinition');
    _facetOnly(json, const <String>{
      'id',
      'displayName',
    }, 'ScenarioTagDefinition');
    return ScenarioTagDefinition(
      id: ScenarioTagId(_facetString(json, 'id', 'ScenarioTagDefinition')),
      displayName: _facetString(
        json,
        'displayName',
        'ScenarioTagDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class ExperienceComponentDefinition {
  ExperienceComponentDefinition({
    required this.id,
    required this.applicationId,
    required this.displayName,
  }) {
    _facetText(displayName, 'ExperienceComponentDefinition.displayName');
  }

  final ExperienceComponentId id;
  final ApplicationId applicationId;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'applicationId': applicationId.value,
    'displayName': displayName,
  };

  factory ExperienceComponentDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'ExperienceComponentDefinition');
    _facetOnly(json, const <String>{
      'id',
      'applicationId',
      'displayName',
    }, 'ExperienceComponentDefinition');
    return ExperienceComponentDefinition(
      id: ExperienceComponentId(
        _facetString(json, 'id', 'ExperienceComponentDefinition'),
      ),
      applicationId: ApplicationId(
        _facetString(json, 'applicationId', 'ExperienceComponentDefinition'),
      ),
      displayName: _facetString(
        json,
        'displayName',
        'ExperienceComponentDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class ScenarioFixtureDefinition {
  ScenarioFixtureDefinition({
    required this.id,
    required this.applicationId,
    required this.displayName,
  }) {
    _facetText(displayName, 'ScenarioFixtureDefinition.displayName');
  }

  final ScenarioFixtureId id;
  final ApplicationId applicationId;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'applicationId': applicationId.value,
    'displayName': displayName,
  };

  factory ScenarioFixtureDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'ScenarioFixtureDefinition');
    _facetOnly(json, const <String>{
      'id',
      'applicationId',
      'displayName',
    }, 'ScenarioFixtureDefinition');
    return ScenarioFixtureDefinition(
      id: ScenarioFixtureId(
        _facetString(json, 'id', 'ScenarioFixtureDefinition'),
      ),
      applicationId: ApplicationId(
        _facetString(json, 'applicationId', 'ScenarioFixtureDefinition'),
      ),
      displayName: _facetString(
        json,
        'displayName',
        'ScenarioFixtureDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class FormFactorDefinition {
  FormFactorDefinition({required this.id, required this.displayName}) {
    _facetText(displayName, 'FormFactorDefinition.displayName');
  }

  final FormFactorId id;
  final String displayName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
  };

  factory FormFactorDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'FormFactorDefinition');
    _facetOnly(json, const <String>{
      'id',
      'displayName',
    }, 'FormFactorDefinition');
    return FormFactorDefinition(
      id: FormFactorId(_facetString(json, 'id', 'FormFactorDefinition')),
      displayName: _facetString(
        json,
        'displayName',
        'FormFactorDefinition',
        maxLength: 512,
      ),
    );
  }
}

final class PresentationFrameDefinition {
  PresentationFrameDefinition({
    required this.id,
    required this.displayName,
    required this.kind,
    this.formFactorId,
  }) {
    _facetText(displayName, 'PresentationFrameDefinition.displayName');
    if ((kind == PresentationFrameKind.none) != (formFactorId == null)) {
      throw ArgumentError(
        'PresentationFrame kind none must omit formFactorId; all other kinds require it',
      );
    }
  }

  final PresentationFrameId id;
  final String displayName;
  final PresentationFrameKind kind;
  final FormFactorId? formFactorId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id.value,
    'displayName': displayName,
    'kind': kind.name,
    if (formFactorId != null) 'formFactorId': formFactorId!.value,
  };

  factory PresentationFrameDefinition.fromJson(Object? value) {
    final json = _facetObject(value, 'PresentationFrameDefinition');
    _facetOnly(json, const <String>{
      'id',
      'displayName',
      'kind',
      'formFactorId',
    }, 'PresentationFrameDefinition');
    final rawFormFactor = _facetOptionalString(
      json,
      'formFactorId',
      'PresentationFrameDefinition',
    );
    return PresentationFrameDefinition(
      id: PresentationFrameId(
        _facetString(json, 'id', 'PresentationFrameDefinition'),
      ),
      displayName: _facetString(
        json,
        'displayName',
        'PresentationFrameDefinition',
        maxLength: 512,
      ),
      kind: _facetEnum(
        PresentationFrameKind.values,
        _facetString(json, 'kind', 'PresentationFrameDefinition'),
        'PresentationFrameDefinition.kind',
      ),
      formFactorId: rawFormFactor == null ? null : FormFactorId(rawFormFactor),
    );
  }
}

sealed class ScenarioRenderSource {
  const ScenarioRenderSource();

  ScenarioRenderSourceKind get kind;

  Map<String, Object?> toJson();

  factory ScenarioRenderSource.fromJson(Object? value) {
    final json = _facetObject(value, 'ScenarioRenderSource');
    final kind = _facetEnum(
      ScenarioRenderSourceKind.values,
      _facetString(json, 'kind', 'ScenarioRenderSource'),
      'ScenarioRenderSource.kind',
    );
    return switch (kind) {
      ScenarioRenderSourceKind.previewDescriptor =>
        PreviewDescriptorRenderSource.fromJson(json),
      ScenarioRenderSourceKind.executionBinding =>
        ExecutionBindingRenderSource.fromJson(json),
      ScenarioRenderSourceKind.externalHarness =>
        ExternalHarnessRenderSource.fromJson(json),
      ScenarioRenderSourceKind.archiveArtifact =>
        ArchiveArtifactRenderSource.fromJson(json),
    };
  }
}

final class PreviewDescriptorRenderSource extends ScenarioRenderSource {
  const PreviewDescriptorRenderSource({required this.previewId});

  final AutoPreviewId previewId;

  @override
  ScenarioRenderSourceKind get kind =>
      ScenarioRenderSourceKind.previewDescriptor;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'previewId': previewId.value,
  };

  factory PreviewDescriptorRenderSource.fromJson(Object? value) {
    final json = _facetObject(value, 'PreviewDescriptorRenderSource');
    _facetOnly(json, const <String>{
      'kind',
      'previewId',
    }, 'PreviewDescriptorRenderSource');
    if (json['kind'] != ScenarioRenderSourceKind.previewDescriptor.name) {
      throw const FormatException('Invalid PreviewDescriptorRenderSource kind');
    }
    return PreviewDescriptorRenderSource(
      previewId: AutoPreviewId(
        _facetString(json, 'previewId', 'PreviewDescriptorRenderSource'),
      ),
    );
  }
}

final class ExecutionBindingRenderSource extends ScenarioRenderSource {
  const ExecutionBindingRenderSource({required this.bindingId});

  final ScenarioExecutionBindingId bindingId;

  @override
  ScenarioRenderSourceKind get kind =>
      ScenarioRenderSourceKind.executionBinding;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'bindingId': bindingId.value,
  };

  factory ExecutionBindingRenderSource.fromJson(Object? value) {
    final json = _facetObject(value, 'ExecutionBindingRenderSource');
    _facetOnly(json, const <String>{
      'kind',
      'bindingId',
    }, 'ExecutionBindingRenderSource');
    if (json['kind'] != ScenarioRenderSourceKind.executionBinding.name) {
      throw const FormatException('Invalid ExecutionBindingRenderSource kind');
    }
    return ExecutionBindingRenderSource(
      bindingId: ScenarioExecutionBindingId(
        _facetString(json, 'bindingId', 'ExecutionBindingRenderSource'),
      ),
    );
  }
}

final class ExternalHarnessRenderSource extends ScenarioRenderSource {
  const ExternalHarnessRenderSource({
    required this.providerId,
    required this.harnessId,
  });

  final RenderProviderId providerId;
  final RenderHarnessId harnessId;

  @override
  ScenarioRenderSourceKind get kind => ScenarioRenderSourceKind.externalHarness;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'providerId': providerId.value,
    'harnessId': harnessId.value,
  };

  factory ExternalHarnessRenderSource.fromJson(Object? value) {
    final json = _facetObject(value, 'ExternalHarnessRenderSource');
    _facetOnly(json, const <String>{
      'kind',
      'providerId',
      'harnessId',
    }, 'ExternalHarnessRenderSource');
    if (json['kind'] != ScenarioRenderSourceKind.externalHarness.name) {
      throw const FormatException('Invalid ExternalHarnessRenderSource kind');
    }
    return ExternalHarnessRenderSource(
      providerId: RenderProviderId(
        _facetString(json, 'providerId', 'ExternalHarnessRenderSource'),
      ),
      harnessId: RenderHarnessId(
        _facetString(json, 'harnessId', 'ExternalHarnessRenderSource'),
      ),
    );
  }
}

final class ArchiveArtifactRenderSource extends ScenarioRenderSource {
  const ArchiveArtifactRenderSource({required this.artifactDigest});

  final Digest artifactDigest;

  @override
  ScenarioRenderSourceKind get kind => ScenarioRenderSourceKind.archiveArtifact;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'artifactDigest': artifactDigest.value,
  };

  factory ArchiveArtifactRenderSource.fromJson(Object? value) {
    final json = _facetObject(value, 'ArchiveArtifactRenderSource');
    _facetOnly(json, const <String>{
      'kind',
      'artifactDigest',
    }, 'ArchiveArtifactRenderSource');
    if (json['kind'] != ScenarioRenderSourceKind.archiveArtifact.name) {
      throw const FormatException('Invalid ArchiveArtifactRenderSource kind');
    }
    return ArchiveArtifactRenderSource(
      artifactDigest: Digest(
        _facetString(json, 'artifactDigest', 'ArchiveArtifactRenderSource'),
      ),
    );
  }
}

final class ScenarioFacet {
  ScenarioFacet({
    required this.scenarioId,
    required this.lifecycle,
    required this.scenarioKindId,
    required this.surfaceId,
    required this.stateId,
    required this.ownershipAreaId,
    required Iterable<ScenarioTagId> tagIds,
    required Iterable<ExperienceComponentId> componentIds,
    required this.fixtureId,
    required this.renderSource,
    required Iterable<PresentationFrameId> presentationFrameIds,
    required this.preferredPresentationFrameId,
  }) : tagIds = _facetSortedIds(
         tagIds,
         'ScenarioFacet.tagIds',
         minItems: 1,
         maxItems: 256,
       ),
       componentIds = _facetSortedIds(
         componentIds,
         'ScenarioFacet.componentIds',
         minItems: 1,
         maxItems: 256,
       ),
       presentationFrameIds = _facetSortedIds(
         presentationFrameIds,
         'ScenarioFacet.presentationFrameIds',
         minItems: 1,
         maxItems: 32,
       ) {
    if (!this.presentationFrameIds.contains(preferredPresentationFrameId)) {
      throw ArgumentError(
        'ScenarioFacet.preferredPresentationFrameId must be listed in presentationFrameIds',
      );
    }
    if (renderSource.kind == ScenarioRenderSourceKind.archiveArtifact &&
        lifecycle != ScenarioLifecycle.historical) {
      throw ArgumentError(
        'ScenarioFacet archiveArtifact render source requires historical lifecycle',
      );
    }
  }

  final ScenarioId scenarioId;
  final ScenarioLifecycle lifecycle;
  final ScenarioKindId scenarioKindId;
  final ExperienceSurfaceId surfaceId;
  final ScenarioStateId stateId;
  final OwnershipAreaId ownershipAreaId;
  final List<ScenarioTagId> tagIds;
  final List<ExperienceComponentId> componentIds;
  final ScenarioFixtureId fixtureId;
  final ScenarioRenderSource renderSource;
  final List<PresentationFrameId> presentationFrameIds;
  final PresentationFrameId preferredPresentationFrameId;

  Map<String, Object?> toJson() => <String, Object?>{
    'scenarioId': scenarioId.value,
    'lifecycle': lifecycle.name,
    'scenarioKindId': scenarioKindId.value,
    'surfaceId': surfaceId.value,
    'stateId': stateId.value,
    'ownershipAreaId': ownershipAreaId.value,
    'tagIds': tagIds.map((id) => id.value).toList(growable: false),
    'componentIds': componentIds.map((id) => id.value).toList(growable: false),
    'fixtureId': fixtureId.value,
    'renderSource': renderSource.toJson(),
    'presentationFrameIds': presentationFrameIds
        .map((id) => id.value)
        .toList(growable: false),
    'preferredPresentationFrameId': preferredPresentationFrameId.value,
  };

  factory ScenarioFacet.fromJson(Object? value) {
    final json = _facetObject(value, 'ScenarioFacet');
    _facetOnly(json, const <String>{
      'scenarioId',
      'lifecycle',
      'scenarioKindId',
      'surfaceId',
      'stateId',
      'ownershipAreaId',
      'tagIds',
      'componentIds',
      'fixtureId',
      'renderSource',
      'presentationFrameIds',
      'preferredPresentationFrameId',
    }, 'ScenarioFacet');
    return ScenarioFacet(
      scenarioId: ScenarioId(_facetString(json, 'scenarioId', 'ScenarioFacet')),
      lifecycle: _facetEnum(
        ScenarioLifecycle.values,
        _facetString(json, 'lifecycle', 'ScenarioFacet'),
        'ScenarioFacet.lifecycle',
      ),
      scenarioKindId: ScenarioKindId(
        _facetString(json, 'scenarioKindId', 'ScenarioFacet'),
      ),
      surfaceId: ExperienceSurfaceId(
        _facetString(json, 'surfaceId', 'ScenarioFacet'),
      ),
      stateId: ScenarioStateId(_facetString(json, 'stateId', 'ScenarioFacet')),
      ownershipAreaId: OwnershipAreaId(
        _facetString(json, 'ownershipAreaId', 'ScenarioFacet'),
      ),
      tagIds: _facetStringList(
        json,
        'tagIds',
        'ScenarioFacet',
        minItems: 1,
        maxItems: 256,
      ).map(ScenarioTagId.new),
      componentIds: _facetStringList(
        json,
        'componentIds',
        'ScenarioFacet',
        minItems: 1,
        maxItems: 256,
      ).map(ExperienceComponentId.new),
      fixtureId: ScenarioFixtureId(
        _facetString(json, 'fixtureId', 'ScenarioFacet'),
      ),
      renderSource: ScenarioRenderSource.fromJson(json['renderSource']),
      presentationFrameIds: _facetStringList(
        json,
        'presentationFrameIds',
        'ScenarioFacet',
        minItems: 1,
        maxItems: 32,
      ).map(PresentationFrameId.new),
      preferredPresentationFrameId: PresentationFrameId(
        _facetString(json, 'preferredPresentationFrameId', 'ScenarioFacet'),
      ),
    );
  }
}

/// Closed, catalog-bound taxonomy used by Inventory and other read models.
///
/// Consumer-owned IDs keep open product vocabularies extensible. Only portable
/// protocol semantics (lifecycle, render-source kind and frame kind) are enums.
final class ScenarioFacetManifest {
  ScenarioFacetManifest({
    required CatalogManifest catalog,
    required Iterable<ScenarioKindDefinition> scenarioKinds,
    required Iterable<ExperienceSurfaceDefinition> surfaces,
    required Iterable<ScenarioStateDefinition> states,
    required Iterable<OwnershipAreaDefinition> ownershipAreas,
    required Iterable<ScenarioTagDefinition> tags,
    required Iterable<ExperienceComponentDefinition> components,
    required Iterable<ScenarioFixtureDefinition> fixtures,
    required Iterable<FormFactorDefinition> formFactors,
    required Iterable<PresentationFrameDefinition> presentationFrames,
    required Iterable<ScenarioFacet> scenarioFacets,
  }) : catalogDigest = catalog.digest,
       scenarioKinds = _facetSorted(
         scenarioKinds,
         (item) => item.id.value,
         'ScenarioFacetManifest.scenarioKinds',
         maxItems: 10000,
       ),
       surfaces = _facetSorted(
         surfaces,
         (item) => item.id.value,
         'ScenarioFacetManifest.surfaces',
         maxItems: 10000,
       ),
       states = _facetSorted(
         states,
         (item) => item.id.value,
         'ScenarioFacetManifest.states',
         maxItems: 100000,
       ),
       ownershipAreas = _facetSorted(
         ownershipAreas,
         (item) => item.id.value,
         'ScenarioFacetManifest.ownershipAreas',
         maxItems: 10000,
       ),
       tags = _facetSorted(
         tags,
         (item) => item.id.value,
         'ScenarioFacetManifest.tags',
         maxItems: 100000,
       ),
       components = _facetSorted(
         components,
         (item) => item.id.value,
         'ScenarioFacetManifest.components',
         maxItems: 100000,
       ),
       fixtures = _facetSorted(
         fixtures,
         (item) => item.id.value,
         'ScenarioFacetManifest.fixtures',
         maxItems: 100000,
       ),
       formFactors = _facetSorted(
         formFactors,
         (item) => item.id.value,
         'ScenarioFacetManifest.formFactors',
         maxItems: 10000,
       ),
       presentationFrames = _facetSorted(
         presentationFrames,
         (item) => item.id.value,
         'ScenarioFacetManifest.presentationFrames',
         maxItems: 10000,
       ),
       scenarioFacets = _facetSorted(
         scenarioFacets,
         (item) => item.scenarioId.value,
         'ScenarioFacetManifest.scenarioFacets',
         maxItems: 100000,
       ) {
    _validateScenarioFacetManifest(this, catalog);
  }

  static const int schemaVersion = 1;

  final Digest catalogDigest;
  final List<ScenarioKindDefinition> scenarioKinds;
  final List<ExperienceSurfaceDefinition> surfaces;
  final List<ScenarioStateDefinition> states;
  final List<OwnershipAreaDefinition> ownershipAreas;
  final List<ScenarioTagDefinition> tags;
  final List<ExperienceComponentDefinition> components;
  final List<ScenarioFixtureDefinition> fixtures;
  final List<FormFactorDefinition> formFactors;
  final List<PresentationFrameDefinition> presentationFrames;
  final List<ScenarioFacet> scenarioFacets;

  late final Digest digest = Digest.semantic(toJson(includeDigest: false));

  Map<String, Object?> toJson({bool includeDigest = true}) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': 'ScenarioFacetManifest',
    'catalogDigest': catalogDigest.value,
    'scenarioKinds': scenarioKinds.map((item) => item.toJson()).toList(),
    'surfaces': surfaces.map((item) => item.toJson()).toList(),
    'states': states.map((item) => item.toJson()).toList(),
    'ownershipAreas': ownershipAreas.map((item) => item.toJson()).toList(),
    'tags': tags.map((item) => item.toJson()).toList(),
    'components': components.map((item) => item.toJson()).toList(),
    'fixtures': fixtures.map((item) => item.toJson()).toList(),
    'formFactors': formFactors.map((item) => item.toJson()).toList(),
    'presentationFrames': presentationFrames
        .map((item) => item.toJson())
        .toList(),
    'scenarioFacets': scenarioFacets.map((item) => item.toJson()).toList(),
    if (includeDigest) 'digest': digest.value,
  };

  factory ScenarioFacetManifest.fromJson(
    Object? value, {
    required CatalogManifest catalog,
  }) {
    final json = _facetObject(value, 'ScenarioFacetManifest');
    _facetOnly(json, const <String>{
      'schemaVersion',
      'kind',
      'catalogDigest',
      'scenarioKinds',
      'surfaces',
      'states',
      'ownershipAreas',
      'tags',
      'components',
      'fixtures',
      'formFactors',
      'presentationFrames',
      'scenarioFacets',
      'digest',
    }, 'ScenarioFacetManifest');
    if (json['schemaVersion'] != schemaVersion ||
        json['kind'] != 'ScenarioFacetManifest') {
      throw const FormatException(
        'ScenarioFacetManifest has invalid schemaVersion or kind',
      );
    }
    final declaredCatalogDigest = Digest(
      _facetString(json, 'catalogDigest', 'ScenarioFacetManifest'),
    );
    if (declaredCatalogDigest != catalog.digest) {
      throw const FormatException(
        'ScenarioFacetManifest catalogDigest mismatch',
      );
    }
    final manifest = ScenarioFacetManifest(
      catalog: catalog,
      scenarioKinds: _facetList(
        json,
        'scenarioKinds',
        'ScenarioFacetManifest',
        maxItems: 10000,
      ).map(ScenarioKindDefinition.fromJson),
      surfaces: _facetList(
        json,
        'surfaces',
        'ScenarioFacetManifest',
        maxItems: 10000,
      ).map(ExperienceSurfaceDefinition.fromJson),
      states: _facetList(
        json,
        'states',
        'ScenarioFacetManifest',
        maxItems: 100000,
      ).map(ScenarioStateDefinition.fromJson),
      ownershipAreas: _facetList(
        json,
        'ownershipAreas',
        'ScenarioFacetManifest',
        maxItems: 10000,
      ).map(OwnershipAreaDefinition.fromJson),
      tags: _facetList(
        json,
        'tags',
        'ScenarioFacetManifest',
        maxItems: 100000,
      ).map(ScenarioTagDefinition.fromJson),
      components: _facetList(
        json,
        'components',
        'ScenarioFacetManifest',
        maxItems: 100000,
      ).map(ExperienceComponentDefinition.fromJson),
      fixtures: _facetList(
        json,
        'fixtures',
        'ScenarioFacetManifest',
        maxItems: 100000,
      ).map(ScenarioFixtureDefinition.fromJson),
      formFactors: _facetList(
        json,
        'formFactors',
        'ScenarioFacetManifest',
        maxItems: 10000,
      ).map(FormFactorDefinition.fromJson),
      presentationFrames: _facetList(
        json,
        'presentationFrames',
        'ScenarioFacetManifest',
        maxItems: 10000,
      ).map(PresentationFrameDefinition.fromJson),
      scenarioFacets: _facetList(
        json,
        'scenarioFacets',
        'ScenarioFacetManifest',
        maxItems: 100000,
      ).map(ScenarioFacet.fromJson),
    );
    final declaredDigest = Digest(
      _facetString(json, 'digest', 'ScenarioFacetManifest'),
    );
    if (declaredDigest != manifest.digest) {
      throw const FormatException('ScenarioFacetManifest digest mismatch');
    }
    return manifest;
  }

  void validateAgainst(CatalogManifest catalog) {
    if (catalog.digest != catalogDigest) {
      throw ArgumentError('ScenarioFacetManifest catalogDigest mismatch');
    }
    _validateScenarioFacetManifest(this, catalog);
  }
}

void _validateScenarioFacetManifest(
  ScenarioFacetManifest manifest,
  CatalogManifest catalog,
) {
  if (manifest.catalogDigest != catalog.digest) {
    throw ArgumentError('ScenarioFacetManifest catalogDigest mismatch');
  }
  final applications = catalog.applications.map((item) => item.id).toSet();
  final scenarios = <ScenarioId, Scenario>{
    for (final scenario in catalog.scenarios) scenario.id: scenario,
  };
  final kinds = <ScenarioKindId, ScenarioKindDefinition>{
    for (final item in manifest.scenarioKinds) item.id: item,
  };
  final surfaces = <ExperienceSurfaceId, ExperienceSurfaceDefinition>{
    for (final item in manifest.surfaces) item.id: item,
  };
  final states = <ScenarioStateId, ScenarioStateDefinition>{
    for (final item in manifest.states) item.id: item,
  };
  final owners = <OwnershipAreaId, OwnershipAreaDefinition>{
    for (final item in manifest.ownershipAreas) item.id: item,
  };
  final tags = <ScenarioTagId, ScenarioTagDefinition>{
    for (final item in manifest.tags) item.id: item,
  };
  final components = <ExperienceComponentId, ExperienceComponentDefinition>{
    for (final item in manifest.components) item.id: item,
  };
  final fixtures = <ScenarioFixtureId, ScenarioFixtureDefinition>{
    for (final item in manifest.fixtures) item.id: item,
  };
  final formFactors = <FormFactorId, FormFactorDefinition>{
    for (final item in manifest.formFactors) item.id: item,
  };
  final frames = <PresentationFrameId, PresentationFrameDefinition>{
    for (final item in manifest.presentationFrames) item.id: item,
  };
  final executionBindings =
      <ScenarioExecutionBindingId, ScenarioExecutionBinding>{
        for (final item in catalog.executionBindings) item.id: item,
      };

  final facetScenarioIds = manifest.scenarioFacets
      .map((item) => item.scenarioId)
      .toSet();
  if (facetScenarioIds.length != scenarios.length ||
      scenarios.keys.any((id) => !facetScenarioIds.contains(id))) {
    throw ArgumentError(
      'ScenarioFacetManifest must cover every Catalog Scenario exactly once',
    );
  }
  for (final surface in manifest.surfaces) {
    if (!applications.contains(surface.applicationId)) {
      throw ArgumentError(
        'ExperienceSurface ${surface.id} references an unknown Application',
      );
    }
  }
  for (final state in manifest.states) {
    if (!surfaces.containsKey(state.surfaceId)) {
      throw ArgumentError(
        'ScenarioState ${state.id} references an unknown ExperienceSurface',
      );
    }
  }
  for (final component in manifest.components) {
    if (!applications.contains(component.applicationId)) {
      throw ArgumentError(
        'ExperienceComponent ${component.id} references an unknown Application',
      );
    }
  }
  for (final fixture in manifest.fixtures) {
    if (!applications.contains(fixture.applicationId)) {
      throw ArgumentError(
        'ScenarioFixture ${fixture.id} references an unknown Application',
      );
    }
  }
  for (final frame in manifest.presentationFrames) {
    if (frame.formFactorId != null &&
        !formFactors.containsKey(frame.formFactorId)) {
      throw ArgumentError(
        'PresentationFrame ${frame.id} references an unknown FormFactor',
      );
    }
  }

  for (final facet in manifest.scenarioFacets) {
    final scenario = scenarios[facet.scenarioId];
    final surface = surfaces[facet.surfaceId];
    final state = states[facet.stateId];
    final fixture = fixtures[facet.fixtureId];
    if (scenario == null) {
      throw ArgumentError(
        'ScenarioFacet ${facet.scenarioId} references an unknown Scenario',
      );
    }
    if (!kinds.containsKey(facet.scenarioKindId) ||
        surface == null ||
        state == null ||
        !owners.containsKey(facet.ownershipAreaId) ||
        fixture == null ||
        facet.tagIds.any((id) => !tags.containsKey(id)) ||
        facet.componentIds.any((id) => !components.containsKey(id)) ||
        facet.presentationFrameIds.any((id) => !frames.containsKey(id))) {
      throw ArgumentError(
        'ScenarioFacet ${facet.scenarioId} has an unknown taxonomy reference',
      );
    }
    if (surface.applicationId != scenario.applicationId ||
        state.surfaceId != facet.surfaceId ||
        fixture.applicationId != scenario.applicationId ||
        facet.componentIds.any(
          (id) => components[id]!.applicationId != scenario.applicationId,
        )) {
      throw ArgumentError(
        'ScenarioFacet ${facet.scenarioId} has a cross-Application or cross-Surface reference',
      );
    }
    final source = facet.renderSource;
    if (source is ExecutionBindingRenderSource) {
      final binding = executionBindings[source.bindingId];
      if (binding == null || binding.scenarioId != facet.scenarioId) {
        throw ArgumentError(
          'ScenarioFacet ${facet.scenarioId} has an invalid execution binding render source',
        );
      }
    }
  }
}

void _facetOpaqueId(String value, String kind) {
  if (value.length > 256) {
    throw FormatException('$kind ID exceeds 256 characters');
  }
  OpaqueId.validate(value, kind);
}

void _facetText(String value, String path, {int maxLength = 512}) {
  if (value.isEmpty || value.length > maxLength) {
    throw ArgumentError('$path must be a bounded non-empty string');
  }
}

Map<String, Object?> _facetObject(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object');
  }
  return value;
}

void _facetOnly(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) throw FormatException('Unknown $path.$key');
  }
}

String _facetString(
  Map<String, Object?> json,
  String key,
  String path, {
  int maxLength = 256,
}) {
  final value = json[key];
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw FormatException('$path.$key must be a bounded non-empty string');
  }
  return value;
}

String? _facetOptionalString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  if (!json.containsKey(key)) return null;
  return _facetString(json, key, path);
}

List<Object?> _facetList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int maxItems,
}) {
  final value = json[key];
  if (value is! List<Object?> || value.length > maxItems) {
    throw FormatException('$path.$key must be a bounded array');
  }
  return value;
}

List<String> _facetStringList(
  Map<String, Object?> json,
  String key,
  String path, {
  required int minItems,
  required int maxItems,
}) {
  final values = _facetList(json, key, path, maxItems: maxItems);
  if (values.length < minItems ||
      values.any(
        (value) => value is! String || value.isEmpty || value.length > 256,
      )) {
    throw FormatException('$path.$key contains invalid IDs');
  }
  final output = values.cast<String>();
  if (output.toSet().length != output.length) {
    throw FormatException('$path.$key contains duplicate IDs');
  }
  return output;
}

T _facetEnum<T extends Enum>(Iterable<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$path has an unsupported value: $name');
}

List<T> _facetSorted<T>(
  Iterable<T> values,
  String Function(T) key,
  String path, {
  required int maxItems,
}) {
  final output = List<T>.of(values)
    ..sort((left, right) => key(left).compareTo(key(right)));
  if (output.length > maxItems ||
      output.map(key).toSet().length != output.length) {
    throw ArgumentError('$path IDs must be unique and bounded');
  }
  return List<T>.unmodifiable(output);
}

List<T> _facetSortedIds<T extends OpaqueId>(
  Iterable<T> values,
  String path, {
  required int minItems,
  required int maxItems,
}) {
  final output = List<T>.of(values)
    ..sort((left, right) => left.value.compareTo(right.value));
  if (output.length < minItems ||
      output.length > maxItems ||
      output.map((item) => item.value).toSet().length != output.length) {
    throw ArgumentError('$path IDs must be unique and bounded');
  }
  return List<T>.unmodifiable(output);
}
