import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const catalogCompiler = CatalogCompiler();
  const topologyCompiler = ExperienceTopologyCompiler();

  late CatalogManifest catalog;

  setUp(() {
    catalog = catalogCompiler.compile(_catalogDocuments());
  });

  test('parses v2 into one topology and two independent layouts', () {
    final documents = _experienceDocuments();

    final compilation = topologyCompiler.compile(documents, catalog: catalog);

    expect(documents, everyElement(hasSchemaVersion(2)));
    expect(compilation.topology.catalogDigest, catalog.digest);
    expect(compilation.topology.boards, hasLength(1));
    expect(compilation.topology.projections, hasLength(2));
    expect(compilation.topology.nodes, hasLength(3));
    expect(compilation.topology.edges, hasLength(1));
    expect(
      compilation.topology.projections
          .singleWhere((projection) => projection.id.value == 'journey-map')
          .journeyId
          ?.value,
      'delivery',
    );
    expect(
      compilation.layouts.map((layout) => layout.projectionId.value),
      <String>['inventory-map', 'journey-map'],
    );
    expect(
      compilation.layouts,
      everyElement(
        predicate<ProjectionLayoutManifest>(
          (layout) => layout.topologyDigest == compilation.topology.digest,
        ),
      ),
    );
  });

  test('is deterministic when v2 document order is reversed', () {
    final documents = _experienceDocuments();

    final forward = topologyCompiler.compile(documents, catalog: catalog);
    final reverse = topologyCompiler.compile(
      documents.reversed,
      catalog: catalog,
    );

    expect(reverse.topology.digest, forward.topology.digest);
    expect(reverse.topology.toJson(), forward.topology.toJson());
    expect(
      reverse.layouts.map((layout) => layout.digest),
      forward.layouts.map((layout) => layout.digest),
    );
    expect(reverse.digest, forward.digest);
  });

  test('moving layout geometry does not change the topology digest', () {
    final original = topologyCompiler.compile(
      _experienceDocuments(),
      catalog: catalog,
    );
    final moved = topologyCompiler.compile(
      _experienceDocuments(journeyStartX: 144),
      catalog: catalog,
    );
    final originalLayouts = <String, ProjectionLayoutManifest>{
      for (final layout in original.layouts) layout.projectionId.value: layout,
    };
    final movedLayouts = <String, ProjectionLayoutManifest>{
      for (final layout in moved.layouts) layout.projectionId.value: layout,
    };

    expect(moved.topology.digest, original.topology.digest);
    expect(
      movedLayouts['journey-map']!.digest,
      isNot(originalLayouts['journey-map']!.digest),
    );
    expect(
      movedLayouts['inventory-map']!.digest,
      originalLayouts['inventory-map']!.digest,
    );
  });

  test('rejects duplicate layout authoring for one Projection', () {
    final documents = _experienceDocuments();
    final layout = documents.singleWhere(
      (document) =>
          document.kind == AuthoringKind.projectionLayout &&
          document.id == 'journey-map',
    );
    documents.add(
      _parseDocument(
        schemaVersion: 2,
        kind: 'ProjectionLayout',
        id: layout.id,
        spec: layout.spec,
        sourceName: 'duplicate-journey-layout.json',
      ),
    );

    expect(
      () => topologyCompiler.compile(documents, catalog: catalog),
      _throwsCompileIssue('duplicate document projectionLayout:journey-map'),
    );
  });

  test('rejects ProjectionLayout metadata.id different from projectionId', () {
    final documents = _experienceDocuments();
    final layout = _removeDocument(
      documents,
      AuthoringKind.projectionLayout,
      'journey-map',
    );
    documents.add(
      _parseDocument(
        schemaVersion: 2,
        kind: 'ProjectionLayout',
        id: 'journey-layout',
        spec: layout.spec,
        sourceName: 'mismatched-layout.json',
      ),
    );

    expect(
      () => topologyCompiler.compile(documents, catalog: catalog),
      _throwsCompileIssue('metadata.id must equal spec.projectionId'),
    );
  });

  test('rejects unknown v2 spec fields', () {
    final documents = _experienceDocuments();
    _replaceSpec(
      documents,
      AuthoringKind.board,
      'product-board',
      <String, Object?>{'unsupported': true},
    );

    expect(
      () => topologyCompiler.compile(documents, catalog: catalog),
      _throwsCompileIssue('unknown field spec.unsupported'),
    );
  });

  test('rejects dangling catalog references', () {
    final documents = _experienceDocuments();
    _replaceSpec(
      documents,
      AuthoringKind.nodeInstance,
      'journey-end',
      <String, Object?>{'scenarioId': 'missing-scenario'},
    );

    expect(
      () => topologyCompiler.compile(documents, catalog: catalog),
      _throwsCompileIssue('NodeInstance journey-end has an unknown'),
    );
  });

  test('rejects cross-Application node references', () {
    final documents = _experienceDocuments();
    _replaceSpec(
      documents,
      AuthoringKind.nodeInstance,
      'journey-end',
      <String, Object?>{'scenarioId': 'other-app-scenario'},
    );

    expect(
      () => topologyCompiler.compile(documents, catalog: catalog),
      _throwsCompileIssue('cross-Application'),
    );
  });

  test('rejects EdgeInstance endpoints that disagree with Transition', () {
    final documents = _experienceDocuments();
    _replaceSpec(
      documents,
      AuthoringKind.edgeInstance,
      'journey-next',
      <String, Object?>{
        'fromNodeId': 'journey-end',
        'toNodeId': 'journey-start',
      },
    );

    expect(
      () => topologyCompiler.compile(documents, catalog: catalog),
      _throwsCompileIssue('does not match its Transition/Journey endpoints'),
    );
  });

  test('CatalogCompiler v1 ignores adjacent v2 documents semantically', () {
    final v1Documents = _catalogDocuments();
    final v1Only = catalogCompiler.compile(v1Documents);
    final withV2 = catalogCompiler.compile(<AuthoringDocument>[
      ...v1Documents,
      ..._experienceDocuments(),
    ]);

    expect(withV2.digest, v1Only.digest);
    expect(withV2.toJson(), v1Only.toJson());
  });
}

Matcher hasSchemaVersion(int version) => isA<AuthoringDocument>().having(
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
  _parseDocument(
    schemaVersion: 1,
    kind: 'Workspace',
    id: 'sample',
    spec: <String, Object?>{'displayName': 'Sample workspace'},
  ),
  _parseDocument(
    schemaVersion: 1,
    kind: 'Application',
    id: 'app-a',
    spec: <String, Object?>{
      'workspaceId': 'sample',
      'displayName': 'Application A',
      'root': 'apps/a',
      'target': 'local',
    },
  ),
  _parseDocument(
    schemaVersion: 1,
    kind: 'Application',
    id: 'app-b',
    spec: <String, Object?>{
      'workspaceId': 'sample',
      'displayName': 'Application B',
      'root': 'apps/b',
      'target': 'local',
    },
  ),
  _parseDocument(
    schemaVersion: 1,
    kind: 'Scenario',
    id: 'journey-start',
    spec: <String, Object?>{'applicationId': 'app-a', 'title': 'Journey start'},
  ),
  _parseDocument(
    schemaVersion: 1,
    kind: 'Scenario',
    id: 'journey-end',
    spec: <String, Object?>{'applicationId': 'app-a', 'title': 'Journey end'},
  ),
  _parseDocument(
    schemaVersion: 1,
    kind: 'Scenario',
    id: 'other-app-scenario',
    spec: <String, Object?>{
      'applicationId': 'app-b',
      'title': 'Other application',
    },
  ),
  _parseDocument(
    schemaVersion: 1,
    kind: 'Journey',
    id: 'delivery',
    spec: <String, Object?>{
      'applicationId': 'app-a',
      'title': 'Delivery',
      'scenarioIds': <String>['journey-start', 'journey-end'],
    },
  ),
  _parseDocument(
    schemaVersion: 1,
    kind: 'Transition',
    id: 'next',
    spec: <String, Object?>{
      'journeyId': 'delivery',
      'from': 'journey-start',
      'to': 'journey-end',
    },
  ),
];

List<AuthoringDocument> _experienceDocuments({double journeyStartX = 0}) =>
    <AuthoringDocument>[
      _parseDocument(
        schemaVersion: 2,
        kind: 'Board',
        id: 'product-board',
        spec: <String, Object?>{
          'applicationId': 'app-a',
          'title': 'Product board',
          'projectionIds': <String>['journey-map', 'inventory-map'],
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'ExperienceProjection',
        id: 'journey-map',
        spec: <String, Object?>{
          'boardId': 'product-board',
          'applicationId': 'app-a',
          'title': 'Delivery journey',
          'projectionKind': 'journey',
          'journeyId': 'delivery',
          'nodeInstanceIds': <String>['journey-start', 'journey-end'],
          'edgeInstanceIds': <String>['journey-next'],
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'ExperienceProjection',
        id: 'inventory-map',
        spec: <String, Object?>{
          'boardId': 'product-board',
          'applicationId': 'app-a',
          'title': 'Scenario inventory',
          'projectionKind': 'inventory',
          'nodeInstanceIds': <String>['inventory-start'],
          'edgeInstanceIds': <String>[],
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'NodeInstance',
        id: 'journey-start',
        spec: <String, Object?>{
          'projectionId': 'journey-map',
          'scenarioId': 'journey-start',
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'NodeInstance',
        id: 'journey-end',
        spec: <String, Object?>{
          'projectionId': 'journey-map',
          'scenarioId': 'journey-end',
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'NodeInstance',
        id: 'inventory-start',
        spec: <String, Object?>{
          'projectionId': 'inventory-map',
          'scenarioId': 'journey-start',
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'EdgeInstance',
        id: 'journey-next',
        spec: <String, Object?>{
          'projectionId': 'journey-map',
          'transitionId': 'next',
          'fromNodeId': 'journey-start',
          'toNodeId': 'journey-end',
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'ProjectionLayout',
        id: 'journey-map',
        spec: <String, Object?>{
          'projectionId': 'journey-map',
          'nodeFrames': <Object?>[
            <String, Object?>{
              'nodeInstanceId': 'journey-start',
              'x': journeyStartX,
              'y': 0,
              'width': 320,
              'height': 180,
            },
            <String, Object?>{
              'nodeInstanceId': 'journey-end',
              'x': 480,
              'y': 0,
              'width': 320,
              'height': 180,
            },
          ],
          'groups': <Object?>[],
          'lanes': <Object?>[],
          'annotations': <Object?>[],
          'camera': <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
        },
      ),
      _parseDocument(
        schemaVersion: 2,
        kind: 'ProjectionLayout',
        id: 'inventory-map',
        spec: <String, Object?>{
          'projectionId': 'inventory-map',
          'nodeFrames': <Object?>[
            <String, Object?>{
              'nodeInstanceId': 'inventory-start',
              'x': 24,
              'y': 48,
              'width': 320,
              'height': 180,
            },
          ],
          'groups': <Object?>[],
          'lanes': <Object?>[],
          'annotations': <Object?>[],
          'camera': <String, Object?>{'x': 0, 'y': 0, 'zoom': 1},
        },
      ),
    ];

AuthoringDocument _parseDocument({
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
  sourceName: sourceName ?? '$kind-$id.json',
);

AuthoringDocument _removeDocument(
  List<AuthoringDocument> documents,
  AuthoringKind kind,
  String id,
) {
  final index = documents.indexWhere(
    (document) => document.kind == kind && document.id == id,
  );
  if (index < 0) throw StateError('missing test document ${kind.name}:$id');
  return documents.removeAt(index);
}

void _replaceSpec(
  List<AuthoringDocument> documents,
  AuthoringKind kind,
  String id,
  Map<String, Object?> changes,
) {
  final original = _removeDocument(documents, kind, id);
  documents.add(
    _parseDocument(
      schemaVersion: original.schemaVersion,
      kind: original.kind.name,
      id: original.id,
      spec: <String, Object?>{...original.spec, ...changes},
      sourceName: original.sourceName,
    ),
  );
}
