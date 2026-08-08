import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const catalogCompiler = CatalogCompiler();
  const facetCompiler = ScenarioFacetCompiler();
  const topologyCompiler = ExperienceTopologyCompiler();

  late List<AuthoringDocument> catalogDocuments;
  late CatalogManifest catalog;

  setUp(() {
    catalogDocuments = _catalogDocuments();
    catalog = catalogCompiler.compile(catalogDocuments);
  });

  test('compiles closed authoring v2 into a catalog-bound manifest', () {
    final documents = _facetDocuments();

    final manifest = facetCompiler.compile(documents, catalog: catalog);

    expect(facetCompiler.hasAuthoring(documents), isTrue);
    expect(documents, everyElement(_hasSchemaVersion(2)));
    expect(manifest.catalogDigest, catalog.digest);
    expect(manifest.scenarioFacets, hasLength(2));
    expect(manifest.scenarioKinds.single.id.value, 'observable-state');
    expect(
      manifest.scenarioFacets
          .singleWhere((item) => item.scenarioId.value == 'loading')
          .renderSource,
      isA<PreviewDescriptorRenderSource>(),
    );
  });

  test('is deterministic when all taxonomy documents are reversed', () {
    final documents = _facetDocuments();

    final forward = facetCompiler.compile(documents, catalog: catalog);
    final reverse = facetCompiler.compile(documents.reversed, catalog: catalog);

    expect(reverse.toJson(), forward.toJson());
    expect(reverse.digest, forward.digest);
  });

  test('CatalogManifest v1 is byte and digest identical with taxonomy v2', () {
    final v1Only = catalogCompiler.compile(catalogDocuments);
    final withFacets = catalogCompiler.compile(<AuthoringDocument>[
      ...catalogDocuments,
      ..._facetDocuments(),
    ]);

    expect(withFacets.toJson(), v1Only.toJson());
    expect(withFacets.digest, v1Only.digest);
    expect(
      const JcsCanonicalizer().canonicalize(withFacets.toJson()),
      const JcsCanonicalizer().canonicalize(v1Only.toJson()),
    );
    expect(
      utf8.encode(jsonEncode(withFacets.toJson())),
      utf8.encode(jsonEncode(v1Only.toJson())),
    );
    expect(CatalogManifest.schemaVersion, 1);
  });

  test(
    'ExperienceTopologyBundle v1 is byte and digest identical with taxonomy v2',
    () {
      final topologyDocuments = _topologyDocuments();
      final withoutFacets = topologyCompiler.compile(
        topologyDocuments,
        catalog: catalog,
      );
      final withFacets = topologyCompiler.compile(<AuthoringDocument>[
        ...topologyDocuments,
        ..._facetDocuments(),
      ], catalog: catalog);
      final withoutBundle = ExperienceTopologyBundle(
        catalog: catalog,
        topology: withoutFacets.topology,
        layouts: withoutFacets.layouts,
      );
      final withBundle = ExperienceTopologyBundle(
        catalog: catalog,
        topology: withFacets.topology,
        layouts: withFacets.layouts,
      );

      expect(withBundle.toJson(), withoutBundle.toJson());
      expect(withBundle.digest, withoutBundle.digest);
      expect(
        utf8.encode(jsonEncode(withBundle.toJson())),
        utf8.encode(jsonEncode(withoutBundle.toJson())),
      );
      expect(ExperienceTopologyBundle.schemaVersion, 1);
    },
  );

  test('Inventory applies OR within axes and AND across typed axes', () {
    final manifest = facetCompiler.compile(_facetDocuments(), catalog: catalog);
    final index = ScenarioInventoryIndex(catalog: catalog, facets: manifest);

    expect(index.entries.map((entry) => entry.scenario.id.value), <String>[
      'loading',
      'ready',
    ]);
    expect(
      index
          .query(
            ScenarioInventoryQuery(
              stateIds: <ScenarioStateId>[ScenarioStateId('loading')],
              frameKinds: <PresentationFrameKind>[PresentationFrameKind.device],
            ),
          )
          .single
          .scenario
          .id
          .value,
      'loading',
    );
    expect(
      index
          .query(
            ScenarioInventoryQuery(
              tagIds: <ScenarioTagId>[
                ScenarioTagId('dashboard'),
                ScenarioTagId('async-state'),
              ],
            ),
          )
          .map((entry) => entry.scenario.id.value),
      <String>['loading', 'ready'],
    );
    expect(
      index
          .query(
            ScenarioInventoryQuery(
              tagIds: <ScenarioTagId>[ScenarioTagId('dashboard')],
              formFactorIds: <FormFactorId>[FormFactorId('desktop')],
            ),
          )
          .single
          .scenario
          .id
          .value,
      'ready',
    );
    expect(
      index
          .query(ScenarioInventoryQuery(text: 'pending dashboard'))
          .single
          .scenario
          .id
          .value,
      'loading',
    );
    expect(index.byScenarioId(ScenarioId('missing')), isNull);
  });

  test('parser reserves taxonomy kinds for adjacent v2', () {
    final parsed = _parse(
      schemaVersion: 2,
      kind: 'ScenarioKindDefinition',
      id: 'observable-state',
      spec: <String, Object?>{'displayName': 'Observable state'},
    );

    expect(parsed.kind, AuthoringKind.scenarioKindDefinition);
    expect(
      () => _parse(
        schemaVersion: 1,
        kind: 'ScenarioKindDefinition',
        id: 'observable-state',
        spec: <String, Object?>{'displayName': 'Observable state'},
      ),
      throwsA(isA<AuthoringParseException>()),
    );
    expect(
      () => _parse(
        schemaVersion: 2,
        kind: 'Scenario',
        id: 'loading',
        spec: const <String, Object?>{},
      ),
      throwsA(isA<AuthoringParseException>()),
    );
  });

  test('rejects metadata mismatch, unknown fields and duplicate documents', () {
    final metadataMismatch = _facetDocuments();
    _replace(
      metadataMismatch,
      AuthoringKind.scenarioFacet,
      'loading',
      replacementId: 'loading-facets',
    );
    expect(
      () => facetCompiler.compile(metadataMismatch, catalog: catalog),
      _throwsCompileIssue('metadata.id must equal spec.scenarioId'),
    );

    final unknown = _facetDocuments();
    _replace(
      unknown,
      AuthoringKind.scenarioTag,
      'dashboard',
      additions: <String, Object?>{'metadata': <String, Object?>{}},
    );
    expect(
      () => facetCompiler.compile(unknown, catalog: catalog),
      _throwsCompileIssue('unknown field spec.metadata'),
    );

    final duplicates = _facetDocuments();
    final tag = duplicates.singleWhere(
      (document) =>
          document.kind == AuthoringKind.scenarioTag &&
          document.id == 'dashboard',
    );
    duplicates.add(
      _parse(
        schemaVersion: 2,
        kind: 'ScenarioTag',
        id: tag.id,
        spec: tag.spec,
        sourceName: 'duplicate-dashboard.json',
      ),
    );
    expect(
      () => facetCompiler.compile(duplicates, catalog: catalog),
      _throwsCompileIssue('duplicate document scenarioTag:dashboard'),
    );
  });

  test('rejects negative reference, enum, render and limits corpus', () {
    final missingState = _facetDocuments();
    _replace(
      missingState,
      AuthoringKind.scenarioFacet,
      'loading',
      additions: <String, Object?>{'stateId': 'missing-state'},
    );
    expect(
      () => facetCompiler.compile(missingState, catalog: catalog),
      _throwsCompileIssue('unknown taxonomy reference'),
    );

    final invalidLifecycle = _facetDocuments();
    _replace(
      invalidLifecycle,
      AuthoringKind.scenarioFacet,
      'loading',
      additions: <String, Object?>{'lifecycle': 'deprecated'},
    );
    expect(
      () => facetCompiler.compile(invalidLifecycle, catalog: catalog),
      _throwsCompileIssue('unsupported value: deprecated'),
    );

    final openRenderSource = _facetDocuments();
    _replace(
      openRenderSource,
      AuthoringKind.scenarioFacet,
      'loading',
      additions: <String, Object?>{
        'renderSource': <String, Object?>{
          'kind': 'previewDescriptor',
          'previewId': 'sample.dashboard.loading',
          'metadata': <String, Object?>{},
        },
      },
    );
    expect(
      () => facetCompiler.compile(openRenderSource, catalog: catalog),
      _throwsCompileIssue('Unknown PreviewDescriptorRenderSource.metadata'),
    );

    final excessiveTags = _facetDocuments();
    _replace(
      excessiveTags,
      AuthoringKind.scenarioFacet,
      'loading',
      additions: <String, Object?>{
        'tagIds': <String>[
          for (var index = 0; index < 257; index += 1) 'tag-$index',
        ],
      },
    );
    expect(
      () => facetCompiler.compile(excessiveTags, catalog: catalog),
      _throwsCompileIssue('IDs must be unique and bounded'),
    );
  });
}

Matcher _hasSchemaVersion(int version) => isA<AuthoringDocument>().having(
  (document) => document.schemaVersion,
  'schemaVersion',
  version,
);

Matcher _throwsCompileIssue(String fragment) => throwsA(
  isA<CatalogCompileException>().having(
    (error) => error.issues.join('\n'),
    'issues',
    contains(fragment),
  ),
);

List<AuthoringDocument> _catalogDocuments() => <AuthoringDocument>[
  _parse(
    schemaVersion: 1,
    kind: 'Workspace',
    id: 'delivery-lab',
    spec: <String, Object?>{'displayName': 'Delivery Lab'},
  ),
  _parse(
    schemaVersion: 1,
    kind: 'Application',
    id: 'sample-flutter',
    spec: <String, Object?>{
      'workspaceId': 'delivery-lab',
      'displayName': 'Delivery Lab Flutter',
      'root': 'examples/sample_flutter',
      'target': 'web',
    },
  ),
  _parse(
    schemaVersion: 1,
    kind: 'Scenario',
    id: 'loading',
    spec: <String, Object?>{
      'applicationId': 'sample-flutter',
      'title': 'Loading dashboard',
      'description': 'Pending dashboard response',
      'sourceReferences': <Object?>[],
    },
  ),
  _parse(
    schemaVersion: 1,
    kind: 'Scenario',
    id: 'ready',
    spec: <String, Object?>{
      'applicationId': 'sample-flutter',
      'title': 'Ready dashboard',
      'sourceReferences': <Object?>[],
    },
  ),
  _parse(
    schemaVersion: 1,
    kind: 'Journey',
    id: 'delivery',
    spec: <String, Object?>{
      'applicationId': 'sample-flutter',
      'title': 'Delivery',
      'scenarioIds': <String>['loading', 'ready'],
    },
  ),
  _parse(
    schemaVersion: 1,
    kind: 'Transition',
    id: 'loading-ready',
    spec: <String, Object?>{
      'journeyId': 'delivery',
      'from': 'loading',
      'to': 'ready',
      'label': 'Loaded',
    },
  ),
];

List<AuthoringDocument> _facetDocuments() => <AuthoringDocument>[
  _v2('ScenarioKindDefinition', 'observable-state', <String, Object?>{
    'displayName': 'Observable state',
  }),
  _v2('ExperienceSurface', 'delivery-dashboard', <String, Object?>{
    'applicationId': 'sample-flutter',
    'displayName': 'Delivery dashboard',
  }),
  _v2('ScenarioState', 'loading', <String, Object?>{
    'surfaceId': 'delivery-dashboard',
    'displayName': 'Loading',
  }),
  _v2('ScenarioState', 'ready', <String, Object?>{
    'surfaceId': 'delivery-dashboard',
    'displayName': 'Ready',
  }),
  _v2('OwnershipArea', 'experience-team', <String, Object?>{
    'displayName': 'Experience team',
  }),
  _v2('ScenarioTag', 'async-state', <String, Object?>{
    'displayName': 'Async state',
  }),
  _v2('ScenarioTag', 'dashboard', <String, Object?>{
    'displayName': 'Dashboard',
  }),
  _v2('ExperienceComponent', 'dashboard-page', <String, Object?>{
    'applicationId': 'sample-flutter',
    'displayName': 'Dashboard page',
  }),
  _v2('ScenarioFixture', 'sample.dashboard.pending', <String, Object?>{
    'applicationId': 'sample-flutter',
    'displayName': 'Pending dashboard',
  }),
  _v2('ScenarioFixture', 'sample.dashboard.synthetic', <String, Object?>{
    'applicationId': 'sample-flutter',
    'displayName': 'Synthetic ready dashboard',
  }),
  _v2('FormFactor', 'desktop', <String, Object?>{'displayName': 'Desktop'}),
  _v2('FormFactor', 'phone', <String, Object?>{'displayName': 'Phone'}),
  _v2('PresentationFrame', 'desktop-browser', <String, Object?>{
    'displayName': 'Desktop browser',
    'frameKind': 'browser',
    'formFactorId': 'desktop',
  }),
  _v2('PresentationFrame', 'phone-device', <String, Object?>{
    'displayName': 'Phone device',
    'frameKind': 'device',
    'formFactorId': 'phone',
  }),
  _v2('ScenarioFacet', 'loading', <String, Object?>{
    'scenarioId': 'loading',
    'lifecycle': 'current',
    'scenarioKindId': 'observable-state',
    'surfaceId': 'delivery-dashboard',
    'stateId': 'loading',
    'ownershipAreaId': 'experience-team',
    'tagIds': <String>['dashboard', 'async-state'],
    'componentIds': <String>['dashboard-page'],
    'fixtureId': 'sample.dashboard.pending',
    'renderSource': <String, Object?>{
      'kind': 'previewDescriptor',
      'previewId': 'sample.dashboard.loading',
    },
    'presentationFrameIds': <String>['phone-device'],
    'preferredPresentationFrameId': 'phone-device',
  }),
  _v2('ScenarioFacet', 'ready', <String, Object?>{
    'scenarioId': 'ready',
    'lifecycle': 'current',
    'scenarioKindId': 'observable-state',
    'surfaceId': 'delivery-dashboard',
    'stateId': 'ready',
    'ownershipAreaId': 'experience-team',
    'tagIds': <String>['dashboard'],
    'componentIds': <String>['dashboard-page'],
    'fixtureId': 'sample.dashboard.synthetic',
    'renderSource': <String, Object?>{
      'kind': 'previewDescriptor',
      'previewId': 'sample.dashboard.ready',
    },
    'presentationFrameIds': <String>['phone-device', 'desktop-browser'],
    'preferredPresentationFrameId': 'phone-device',
  }),
];

List<AuthoringDocument> _topologyDocuments() => <AuthoringDocument>[
  _v2('Board', 'delivery-board', <String, Object?>{
    'applicationId': 'sample-flutter',
    'title': 'Delivery board',
    'projectionIds': <String>['delivery-journey'],
  }),
  _v2('ExperienceProjection', 'delivery-journey', <String, Object?>{
    'boardId': 'delivery-board',
    'applicationId': 'sample-flutter',
    'title': 'Delivery journey',
    'journeyId': 'delivery',
    'projectionKind': 'journey',
    'nodeInstanceIds': <String>['loading-node', 'ready-node'],
    'edgeInstanceIds': <String>['loading-ready-edge'],
  }),
  _v2('NodeInstance', 'loading-node', <String, Object?>{
    'projectionId': 'delivery-journey',
    'scenarioId': 'loading',
  }),
  _v2('NodeInstance', 'ready-node', <String, Object?>{
    'projectionId': 'delivery-journey',
    'scenarioId': 'ready',
  }),
  _v2('EdgeInstance', 'loading-ready-edge', <String, Object?>{
    'projectionId': 'delivery-journey',
    'transitionId': 'loading-ready',
    'fromNodeId': 'loading-node',
    'toNodeId': 'ready-node',
  }),
  _v2('ProjectionLayout', 'delivery-journey', <String, Object?>{
    'projectionId': 'delivery-journey',
    'nodeFrames': <Object?>[
      <String, Object?>{
        'nodeInstanceId': 'loading-node',
        'x': 0,
        'y': 0,
        'width': 320,
        'height': 240,
      },
      <String, Object?>{
        'nodeInstanceId': 'ready-node',
        'x': 400,
        'y': 0,
        'width': 320,
        'height': 240,
      },
    ],
    'groups': <Object?>[],
    'lanes': <Object?>[],
    'annotations': <Object?>[],
    'camera': <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
  }),
];

AuthoringDocument _v2(String kind, String id, Map<String, Object?> spec) =>
    _parse(schemaVersion: 2, kind: kind, id: id, spec: spec);

AuthoringDocument _parse({
  required int schemaVersion,
  required String kind,
  required String id,
  required Map<String, Object?> spec,
  String? sourceName,
}) => const SafeAuthoringParser().parse(
  jsonEncode(<String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind,
    'metadata': <String, Object?>{'id': id},
    'spec': spec,
  }),
  sourceName: sourceName ?? '$id.json',
);

void _replace(
  List<AuthoringDocument> documents,
  AuthoringKind kind,
  String existingId, {
  String? replacementId,
  Map<String, Object?> additions = const <String, Object?>{},
}) {
  final index = documents.indexWhere(
    (document) => document.kind == kind && document.id == existingId,
  );
  final current = documents[index];
  documents[index] = AuthoringDocument(
    schemaVersion: current.schemaVersion,
    kind: current.kind,
    id: replacementId ?? current.id,
    spec: <String, Object?>{...current.spec, ...additions},
    sourceName: current.sourceName,
  );
}
