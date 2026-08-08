import 'package:experience_contracts/experience_contracts.dart';

import 'authoring_parser.dart';
import 'catalog_compiler.dart';

/// Compiles adjacent authoring v2 into a closed, catalog-bound Scenario facet
/// manifest. Catalog authoring and its v1 wire remain untouched.
final class ScenarioFacetCompiler {
  const ScenarioFacetCompiler();

  bool hasAuthoring(Iterable<AuthoringDocument> source) =>
      source.any((document) => _scenarioFacetKinds.contains(document.kind));

  ScenarioFacetManifest compile(
    Iterable<AuthoringDocument> source, {
    required CatalogManifest catalog,
  }) {
    final documents = source
        .where((document) => _scenarioFacetKinds.contains(document.kind))
        .toList(growable: false);
    final issues = <String>[];
    final keys = <String>{};
    for (final document in documents) {
      if (document.schemaVersion != 2) {
        issues.add(
          '${document.sourceName}: Scenario facet authoring must use v2',
        );
      }
      final key = '${document.kind.name}:${document.id}';
      if (!keys.add(key)) issues.add('duplicate document $key');
      _validateSpecShape(document, issues);
    }

    final scenarioKinds = <ScenarioKindDefinition>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.scenarioKindDefinition,
    )) {
      _capture(document, issues, () {
        scenarioKinds.add(
          ScenarioKindDefinition(
            id: ScenarioKindId(document.id),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final surfaces = <ExperienceSurfaceDefinition>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.experienceSurface,
    )) {
      _capture(document, issues, () {
        surfaces.add(
          ExperienceSurfaceDefinition(
            id: ExperienceSurfaceId(document.id),
            applicationId: ApplicationId(
              _requiredString(document, 'applicationId'),
            ),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final states = <ScenarioStateDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.scenarioState)) {
      _capture(document, issues, () {
        states.add(
          ScenarioStateDefinition(
            id: ScenarioStateId(document.id),
            surfaceId: ExperienceSurfaceId(
              _requiredString(document, 'surfaceId'),
            ),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final ownershipAreas = <OwnershipAreaDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.ownershipArea)) {
      _capture(document, issues, () {
        ownershipAreas.add(
          OwnershipAreaDefinition(
            id: OwnershipAreaId(document.id),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final tags = <ScenarioTagDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.scenarioTag)) {
      _capture(document, issues, () {
        tags.add(
          ScenarioTagDefinition(
            id: ScenarioTagId(document.id),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final components = <ExperienceComponentDefinition>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.experienceComponent,
    )) {
      _capture(document, issues, () {
        components.add(
          ExperienceComponentDefinition(
            id: ExperienceComponentId(document.id),
            applicationId: ApplicationId(
              _requiredString(document, 'applicationId'),
            ),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final fixtures = <ScenarioFixtureDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.scenarioFixture)) {
      _capture(document, issues, () {
        fixtures.add(
          ScenarioFixtureDefinition(
            id: ScenarioFixtureId(document.id),
            applicationId: ApplicationId(
              _requiredString(document, 'applicationId'),
            ),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final formFactors = <FormFactorDefinition>[];
    for (final document in _ofKind(documents, AuthoringKind.formFactor)) {
      _capture(document, issues, () {
        formFactors.add(
          FormFactorDefinition(
            id: FormFactorId(document.id),
            displayName: _requiredString(document, 'displayName'),
          ),
        );
      });
    }

    final presentationFrames = <PresentationFrameDefinition>[];
    for (final document in _ofKind(
      documents,
      AuthoringKind.presentationFrame,
    )) {
      _capture(document, issues, () {
        final rawFormFactor = _optionalString(document, 'formFactorId');
        presentationFrames.add(
          PresentationFrameDefinition(
            id: PresentationFrameId(document.id),
            displayName: _requiredString(document, 'displayName'),
            kind: _enumValue(
              PresentationFrameKind.values,
              _requiredString(document, 'frameKind'),
              'frameKind',
            ),
            formFactorId: rawFormFactor == null
                ? null
                : FormFactorId(rawFormFactor),
          ),
        );
      });
    }

    final scenarioFacets = <ScenarioFacet>[];
    for (final document in _ofKind(documents, AuthoringKind.scenarioFacet)) {
      _capture(document, issues, () {
        final scenarioId = ScenarioId(_requiredString(document, 'scenarioId'));
        if (document.id != scenarioId.value) {
          throw const FormatException(
            'metadata.id must equal spec.scenarioId for ScenarioFacet',
          );
        }
        scenarioFacets.add(
          ScenarioFacet(
            scenarioId: scenarioId,
            lifecycle: _enumValue(
              ScenarioLifecycle.values,
              _requiredString(document, 'lifecycle'),
              'lifecycle',
            ),
            scenarioKindId: ScenarioKindId(
              _requiredString(document, 'scenarioKindId'),
            ),
            surfaceId: ExperienceSurfaceId(
              _requiredString(document, 'surfaceId'),
            ),
            stateId: ScenarioStateId(_requiredString(document, 'stateId')),
            ownershipAreaId: OwnershipAreaId(
              _requiredString(document, 'ownershipAreaId'),
            ),
            tagIds: _stringList(document, 'tagIds').map(ScenarioTagId.new),
            componentIds: _stringList(
              document,
              'componentIds',
            ).map(ExperienceComponentId.new),
            fixtureId: ScenarioFixtureId(
              _requiredString(document, 'fixtureId'),
            ),
            renderSource: ScenarioRenderSource.fromJson(
              _requiredObject(document, 'renderSource'),
            ),
            presentationFrameIds: _stringList(
              document,
              'presentationFrameIds',
            ).map(PresentationFrameId.new),
            preferredPresentationFrameId: PresentationFrameId(
              _requiredString(document, 'preferredPresentationFrameId'),
            ),
          ),
        );
      });
    }

    ScenarioFacetManifest? manifest;
    _captureSynthetic('scenario-facet-manifest', issues, () {
      manifest = ScenarioFacetManifest(
        catalog: catalog,
        scenarioKinds: scenarioKinds,
        surfaces: surfaces,
        states: states,
        ownershipAreas: ownershipAreas,
        tags: tags,
        components: components,
        fixtures: fixtures,
        formFactors: formFactors,
        presentationFrames: presentationFrames,
        scenarioFacets: scenarioFacets,
      );
    });
    if (issues.isNotEmpty || manifest == null) {
      throw CatalogCompileException(issues);
    }
    return manifest!;
  }
}

const Set<AuthoringKind> _scenarioFacetKinds = <AuthoringKind>{
  AuthoringKind.scenarioKindDefinition,
  AuthoringKind.experienceSurface,
  AuthoringKind.scenarioState,
  AuthoringKind.ownershipArea,
  AuthoringKind.scenarioTag,
  AuthoringKind.experienceComponent,
  AuthoringKind.scenarioFixture,
  AuthoringKind.formFactor,
  AuthoringKind.presentationFrame,
  AuthoringKind.scenarioFacet,
};

Iterable<AuthoringDocument> _ofKind(
  Iterable<AuthoringDocument> documents,
  AuthoringKind kind,
) => documents.where((document) => document.kind == kind);

void _capture(
  AuthoringDocument document,
  List<String> issues,
  void Function() body,
) {
  try {
    body();
  } on ArgumentError catch (error) {
    issues.add('${document.sourceName}: ${error.message}');
  } on FormatException catch (error) {
    issues.add('${document.sourceName}: ${error.message}');
  }
}

void _captureSynthetic(
  String sourceName,
  List<String> issues,
  void Function() body,
) {
  try {
    body();
  } on ArgumentError catch (error) {
    issues.add('$sourceName: ${error.message}');
  } on FormatException catch (error) {
    issues.add('$sourceName: ${error.message}');
  }
}

String _requiredString(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('spec.$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('spec.$key must be a non-empty string');
  }
  return value;
}

List<String> _stringList(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value is! List<Object?> ||
      value.any((item) => item is! String || item.trim().isEmpty)) {
    throw FormatException('spec.$key must be an array of non-empty strings');
  }
  return value.cast<String>();
}

Map<String, Object?> _requiredObject(AuthoringDocument document, String key) {
  final value = document.spec[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('spec.$key must be an object');
  }
  return value;
}

T _enumValue<T extends Enum>(Iterable<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('spec.$field has an unsupported value: $name');
}

void _validateSpecShape(AuthoringDocument document, List<String> issues) {
  final allowed = switch (document.kind) {
    AuthoringKind.scenarioKindDefinition ||
    AuthoringKind.ownershipArea ||
    AuthoringKind.scenarioTag ||
    AuthoringKind.formFactor => const <String>{'displayName'},
    AuthoringKind.experienceSurface ||
    AuthoringKind.experienceComponent ||
    AuthoringKind.scenarioFixture => const <String>{
      'applicationId',
      'displayName',
    },
    AuthoringKind.scenarioState => const <String>{'surfaceId', 'displayName'},
    AuthoringKind.presentationFrame => const <String>{
      'displayName',
      'frameKind',
      'formFactorId',
    },
    AuthoringKind.scenarioFacet => const <String>{
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
    },
    _ => const <String>{},
  };
  for (final key in document.spec.keys) {
    if (!allowed.contains(key)) {
      issues.add('${document.sourceName}: unknown field spec.$key');
    }
  }
}
