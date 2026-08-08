import 'dart:convert';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  const catalogCompiler = CatalogCompiler();
  const labCompiler = ScenarioLabCompiler();
  const topologyCompiler = ExperienceTopologyCompiler();
  const facetCompiler = ScenarioFacetCompiler();

  late List<AuthoringDocument> catalogDocuments;
  late CatalogManifest catalog;

  setUp(() {
    catalogDocuments = _catalogDocuments();
    catalog = catalogCompiler.compile(catalogDocuments);
  });

  test('compiles closed authoring v2 into a catalog-bound Lab manifest', () {
    final documents = _labDocuments();

    final manifest = labCompiler.compile(documents, catalog: catalog);

    expect(labCompiler.hasAuthoring(documents), isTrue);
    expect(documents, everyElement(_hasSchemaVersion(2)));
    expect(manifest.catalogDigest, catalog.digest);
    expect(manifest.appAdapterCapabilities.single.id, 'sample.locale');
    expect(manifest.controls.single.domain, isA<ChoiceScenarioControlDomain>());
    expect(manifest.scripts.single.steps.map((step) => step.id), <String>[
      'prepare',
      'set-locale',
      'collect',
      'reset-locale',
    ]);
    expect(manifest.automatedAcceptanceCriteria, hasLength(3));
    expect(manifest.humanApprovalRequirements, hasLength(1));
  });

  test('is deterministic when all Lab documents are reversed', () {
    final documents = _labDocuments();

    final forward = labCompiler.compile(documents, catalog: catalog);
    final reverse = labCompiler.compile(documents.reversed, catalog: catalog);

    expect(reverse.toJson(), forward.toJson());
    expect(reverse.digest, forward.digest);
    expect(
      const JcsCanonicalizer().canonicalize(reverse.toJson()),
      const JcsCanonicalizer().canonicalize(forward.toJson()),
    );
  });

  test(
    'compiles a composable binding-only Lab without controls or Quality',
    () {
      final manifest = labCompiler.compile(
        _bindingOnlyDocuments(),
        catalog: catalog,
      );

      expect(manifest.scripts, hasLength(1));
      expect(
        manifest.scripts.single.steps.single,
        isA<ExecutionBindingScenarioScriptStep>(),
      );
      expect(manifest.appAdapterCapabilities, isEmpty);
      expect(manifest.controls, isEmpty);
      expect(manifest.operations, isEmpty);
      expect(manifest.automatedAcceptanceCriteria, isEmpty);
      expect(manifest.requiredEvidence, isEmpty);
      expect(manifest.comparisonBindings, isEmpty);
      expect(manifest.visualComparisonPolicies, isEmpty);
      expect(manifest.humanApprovalRequirements, isEmpty);
    },
  );

  test('rejects optional registries when they are orphaned', () {
    final orphanedCapability = <AuthoringDocument>[
      ..._bindingOnlyDocuments(),
      _v2('AppAdapterCapability', 'orphaned.capability', <String, Object?>{
        'version': 1,
        'operations': <String>['read'],
      }),
    ];

    expect(
      () => labCompiler.compile(orphanedCapability, catalog: catalog),
      _throwsCompileIssue('unused capability'),
    );
  });

  test('parser reserves Scenario Lab kinds for adjacent v2 only', () {
    final parsed = _parse(
      schemaVersion: 2,
      kind: 'AppAdapterCapability',
      id: 'sample.locale',
      spec: <String, Object?>{
        'version': 1,
        'operations': <String>['read', 'write'],
      },
    );

    expect(parsed.kind, AuthoringKind.appAdapterCapability);
    expect(
      () => _parse(
        schemaVersion: 1,
        kind: 'AppAdapterCapability',
        id: 'sample.locale',
        spec: const <String, Object?>{},
      ),
      throwsA(isA<AuthoringParseException>()),
    );
    expect(
      () => _parse(
        schemaVersion: 2,
        kind: 'Scenario',
        id: 'ready',
        spec: const <String, Object?>{},
      ),
      throwsA(isA<AuthoringParseException>()),
    );
  });

  test('rejects unknown fields, duplicate documents and plan ID mismatch', () {
    final unknown = _labDocuments();
    _replace(
      unknown,
      AuthoringKind.supplementalArtifact,
      'design-note',
      additions: <String, Object?>{'path': '/tmp/design-note.png'},
    );
    expect(
      () => labCompiler.compile(unknown, catalog: catalog),
      _throwsCompileIssue('unknown field spec.path'),
    );

    final duplicate = _labDocuments();
    duplicate.add(duplicate.first);
    expect(
      () => labCompiler.compile(duplicate, catalog: catalog),
      _throwsCompileIssue('duplicate document appAdapterCapability'),
    );

    final mismatch = _labDocuments();
    _replace(
      mismatch,
      AuthoringKind.scenarioLabPlan,
      'ready',
      replacementId: 'different',
    );
    expect(
      () => labCompiler.compile(mismatch, catalog: catalog),
      _throwsCompileIssue('metadata.id must equal spec.scenarioId'),
    );
  });

  test(
    'rejects open operations, dynamic values and missing timeout policy',
    () {
      final openOperation = _labDocuments();
      _replace(
        openOperation,
        AuthoringKind.scenarioLabOperation,
        'set-locale',
        additions: <String, Object?>{'kind': 'invokeCapability'},
      );
      expect(
        () => labCompiler.compile(openOperation, catalog: catalog),
        _throwsCompileIssue('unsupported value'),
      );

      final dynamicValue = _labDocuments();
      _replace(
        dynamicValue,
        AuthoringKind.scenarioLabOperation,
        'set-locale',
        additions: <String, Object?>{
          'value': <String, Object?>{
            'kind': 'dynamic',
            'value': <String, Object?>{'locale': 'pt-br'},
          },
        },
      );
      expect(
        () => labCompiler.compile(dynamicValue, catalog: catalog),
        _throwsCompileIssue('unsupported value'),
      );

      final missingTimeout = _labDocuments();
      final scriptIndex = missingTimeout.indexWhere(
        (document) => document.kind == AuthoringKind.scenarioScript,
      );
      final script = missingTimeout[scriptIndex];
      final spec = _deepCopy(script.spec);
      final steps = spec['steps']! as List<Object?>;
      (steps[1]! as Map<String, Object?>).remove('timeoutOutcome');
      missingTimeout[scriptIndex] = AuthoringDocument(
        schemaVersion: script.schemaVersion,
        kind: script.kind,
        id: script.id,
        spec: spec,
        sourceName: script.sourceName,
      );
      expect(
        () => labCompiler.compile(missingTimeout, catalog: catalog),
        _throwsCompileIssue(
          'timeoutOutcome must be a bounded non-empty string',
        ),
      );
    },
  );

  test(
    'rejects stale Evidence, undeclared operations and loose policy refs',
    () {
      final stale = _labDocuments();
      _replace(
        stale,
        AuthoringKind.requiredEvidence,
        'ready-visual',
        additions: <String, Object?>{'freshness': 'stale'},
      );
      expect(
        () => labCompiler.compile(stale, catalog: catalog),
        _throwsCompileIssue('must require fresh Evidence'),
      );

      final undeclaredOperation = _labDocuments();
      final scriptIndex = undeclaredOperation.indexWhere(
        (document) => document.kind == AuthoringKind.scenarioScript,
      );
      final script = undeclaredOperation[scriptIndex];
      final spec = _deepCopy(script.spec);
      final steps = spec['steps']! as List<Object?>;
      (steps[1]! as Map<String, Object?>)['operationId'] = 'arbitrary';
      undeclaredOperation[scriptIndex] = AuthoringDocument(
        schemaVersion: script.schemaVersion,
        kind: script.kind,
        id: script.id,
        spec: spec,
        sourceName: script.sourceName,
      );
      expect(
        () => labCompiler.compile(undeclaredOperation, catalog: catalog),
        _throwsCompileIssue('invalid operation step'),
      );

      final missingPolicy = _labDocuments();
      _replace(
        missingPolicy,
        AuthoringKind.requiredEvidence,
        'ready-visual',
        additions: <String, Object?>{
          'comparisonPolicy': <String, Object?>{
            'kind': 'visual',
            'policyId': 'missing',
          },
        },
      );
      expect(
        () => labCompiler.compile(missingPolicy, catalog: catalog),
        _throwsCompileIssue('unknown Scenario/policy'),
      );
    },
  );

  test('rejects capability operations outside the AppAdapter allowlist', () {
    final documents = _labDocuments();
    _replace(
      documents,
      AuthoringKind.scenarioControl,
      'locale',
      additions: <String, Object?>{'writeOperationId': 'undeclared'},
    );

    expect(
      () => labCompiler.compile(documents, catalog: catalog),
      _throwsCompileIssue('unknown Scenario/capability operation'),
    );
  });

  test('Catalog, TopologyBundle and Facets v1 ignore Lab authoring bytes', () {
    final lab = _labDocuments();
    final catalogWithout = catalogCompiler.compile(catalogDocuments);
    final catalogWith = catalogCompiler.compile(<AuthoringDocument>[
      ...catalogDocuments,
      ...lab,
    ]);
    expect(catalogWith.toJson(), catalogWithout.toJson());
    expect(catalogWith.digest, catalogWithout.digest);
    expect(
      utf8.encode(jsonEncode(catalogWith.toJson())),
      utf8.encode(jsonEncode(catalogWithout.toJson())),
    );
    expect(CatalogManifest.schemaVersion, 1);

    final topologyDocuments = _topologyDocuments();
    final topologyWithout = topologyCompiler.compile(
      topologyDocuments,
      catalog: catalog,
    );
    final topologyWith = topologyCompiler.compile(<AuthoringDocument>[
      ...topologyDocuments,
      ...lab,
    ], catalog: catalog);
    final bundleWithout = ExperienceTopologyBundle(
      catalog: catalog,
      topology: topologyWithout.topology,
      layouts: topologyWithout.layouts,
    );
    final bundleWith = ExperienceTopologyBundle(
      catalog: catalog,
      topology: topologyWith.topology,
      layouts: topologyWith.layouts,
    );
    expect(bundleWith.toJson(), bundleWithout.toJson());
    expect(bundleWith.digest, bundleWithout.digest);
    expect(
      utf8.encode(jsonEncode(bundleWith.toJson())),
      utf8.encode(jsonEncode(bundleWithout.toJson())),
    );
    expect(ExperienceTopologyBundle.schemaVersion, 1);

    final facetDocuments = _facetDocuments();
    final facetsWithout = facetCompiler.compile(
      facetDocuments,
      catalog: catalog,
    );
    final facetsWith = facetCompiler.compile(<AuthoringDocument>[
      ...facetDocuments,
      ...lab,
    ], catalog: catalog);
    expect(facetsWith.toJson(), facetsWithout.toJson());
    expect(facetsWith.digest, facetsWithout.digest);
    expect(
      utf8.encode(jsonEncode(facetsWith.toJson())),
      utf8.encode(jsonEncode(facetsWithout.toJson())),
    );
    expect(ScenarioFacetManifest.schemaVersion, 1);
  });
}

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
    id: 'delivery-app',
    spec: <String, Object?>{
      'workspaceId': 'delivery-lab',
      'displayName': 'Delivery app',
      'root': 'apps/delivery',
      'target': 'web',
    },
  ),
  _parse(
    schemaVersion: 1,
    kind: 'Scenario',
    id: 'ready',
    spec: <String, Object?>{
      'applicationId': 'delivery-app',
      'title': 'Ready deliveries',
      'sourceReferences': <Object?>[],
    },
  ),
  _parse(
    schemaVersion: 1,
    kind: 'ScenarioExecutionBinding',
    id: 'ready-web',
    spec: <String, Object?>{
      'scenarioId': 'ready',
      'targetId': 'chrome',
      'launchProfileId': 'delivery-web',
    },
  ),
  _parse(
    schemaVersion: 1,
    kind: 'ReviewGuide',
    id: 'ready-review',
    spec: <String, Object?>{
      'applicationId': 'delivery-app',
      'title': 'Ready review',
      'steps': <Object?>[
        <String, Object?>{
          'id': 'inspect-ready',
          'instruction': 'Inspect the ready delivery list.',
          'observationCriteria': 'The delivery cards are complete and legible.',
          'scenarioId': 'ready',
          'bindingId': 'ready-web',
        },
      ],
    },
  ),
];

List<AuthoringDocument> _labDocuments() => <AuthoringDocument>[
  _v2('AppAdapterCapability', 'sample.locale', <String, Object?>{
    'version': 1,
    'operations': <String>['read', 'write', 'reset'],
  }),
  _v2('ScenarioControl', 'locale', <String, Object?>{
    'scenarioId': 'ready',
    'displayName': 'Locale',
    'capability': <String, Object?>{'id': 'sample.locale', 'version': 1},
    'readOperationId': 'read',
    'writeOperationId': 'write',
    'resetOperationId': 'reset',
    'domain': <String, Object?>{
      'kind': 'choice',
      'defaultValue': 'en-us',
      'choices': <Object?>[
        <String, Object?>{'id': 'en-us', 'displayName': 'English'},
        <String, Object?>{'id': 'pt-br', 'displayName': 'Portuguese'},
      ],
    },
  }),
  _v2('VisualComparisonPolicy', 'pixel-v1', <String, Object?>{
    'maxChannelDelta': 8,
    'maxChangedPixelRatio': 0.01,
  }),
  _v2('RequiredEvidence', 'ready-visual', <String, Object?>{
    'scenarioId': 'ready',
    'providerId': 'evidence.auto-preview',
    'fidelity': 'structural',
    'variantId': 'phone-light',
    'freshness': 'fresh',
    'allowedClassifications': <String>['public', 'internal'],
    'evidencePolicyId': 'static-v1',
    'comparisonPolicy': <String, Object?>{
      'kind': 'visual',
      'policyId': 'pixel-v1',
    },
  }),
  _v2('ScenarioComparisonBinding', 'ready-comparison', <String, Object?>{
    'scenarioId': 'ready',
    'requiredEvidenceId': 'ready-visual',
    'baseline': <String, Object?>{
      'kind': 'artifact',
      'artifactId': 'design-note',
    },
    'candidate': <String, Object?>{
      'kind': 'evidence',
      'evidenceDigest': Digest.semantic('ready-candidate-evidence').value,
      'provenanceDigest': Digest.semantic('ready-candidate-provenance').value,
      'classification': 'internal',
    },
  }),
  _v2('ScenarioLabOperation', 'set-locale', <String, Object?>{
    'scenarioId': 'ready',
    'kind': 'assignControl',
    'controlId': 'locale',
    'value': <String, Object?>{'kind': 'choice', 'value': 'pt-br'},
  }),
  _v2('ScenarioLabOperation', 'collect-ready', <String, Object?>{
    'scenarioId': 'ready',
    'kind': 'collectEvidence',
    'evidenceRequirementId': 'ready-visual',
  }),
  _v2('ScenarioLabOperation', 'reset-locale', <String, Object?>{
    'scenarioId': 'ready',
    'kind': 'resetControl',
    'controlId': 'locale',
  }),
  _v2('ScenarioScript', 'exercise-ready', <String, Object?>{
    'scenarioId': 'ready',
    'displayName': 'Exercise ready state',
    'timeoutMs': 30000,
    'timeoutOutcome': 'fail',
    'cancellationPolicy': 'afterCurrentStep',
    'steps': <Object?>[
      <String, Object?>{
        'id': 'prepare',
        'kind': 'executionBinding',
        'bindingId': 'ready-web',
        'timeoutMs': 10000,
        'timeoutOutcome': 'cancel',
      },
      <String, Object?>{
        'id': 'set-locale',
        'kind': 'operation',
        'operationId': 'set-locale',
        'timeoutMs': 2000,
        'timeoutOutcome': 'fail',
      },
      <String, Object?>{
        'id': 'collect',
        'kind': 'operation',
        'operationId': 'collect-ready',
        'timeoutMs': 10000,
        'timeoutOutcome': 'fail',
      },
      <String, Object?>{
        'id': 'reset-locale',
        'kind': 'operation',
        'operationId': 'reset-locale',
        'timeoutMs': 2000,
        'timeoutOutcome': 'fail',
      },
    ],
  }),
  _v2('AutomatedAcceptanceCriterion', 'script-succeeds', <String, Object?>{
    'scenarioId': 'ready',
    'displayName': 'Script succeeds',
    'kind': 'scriptSucceeded',
    'scriptId': 'exercise-ready',
  }),
  _v2('AutomatedAcceptanceCriterion', 'visual-accepted', <String, Object?>{
    'scenarioId': 'ready',
    'displayName': 'Visual Evidence is accepted',
    'kind': 'evidenceAccepted',
    'evidenceRequirementId': 'ready-visual',
  }),
  _v2('AutomatedAcceptanceCriterion', 'locale-restored', <String, Object?>{
    'scenarioId': 'ready',
    'displayName': 'Locale is restored',
    'kind': 'controlEquals',
    'controlId': 'locale',
    'expectedValue': <String, Object?>{'kind': 'choice', 'value': 'en-us'},
  }),
  _v2('HumanApprovalRequirement', 'approve-ready', <String, Object?>{
    'scenarioId': 'ready',
    'reviewGuideId': 'ready-review',
    'reviewGuideStepId': 'inspect-ready',
    'scope': 'evidenceSet',
  }),
  _v2('SupplementalArtifact', 'design-note', <String, Object?>{
    'scenarioId': 'ready',
    'requiredEvidenceId': 'ready-visual',
    'role': 'comparisonBaseline',
    'artifactDigest': Digest.semantic('design-note').value,
    'provenanceDigest': Digest.semantic('design-note-provenance').value,
    'classification': 'internal',
  }),
  _v2('ScenarioLabPlan', 'ready', <String, Object?>{
    'scenarioId': 'ready',
    'executionBindingIds': <String>['ready-web'],
    'controlIds': <String>['locale'],
    'operationIds': <String>['set-locale', 'collect-ready', 'reset-locale'],
    'scriptIds': <String>['exercise-ready'],
    'automatedAcceptanceCriterionIds': <String>[
      'script-succeeds',
      'visual-accepted',
      'locale-restored',
    ],
    'requiredEvidenceIds': <String>['ready-visual'],
    'comparisonBindingIds': <String>['ready-comparison'],
    'humanApprovalRequirementIds': <String>['approve-ready'],
    'supplementalArtifactIds': <String>['design-note'],
  }),
];

List<AuthoringDocument> _bindingOnlyDocuments() => <AuthoringDocument>[
  _v2('ScenarioScript', 'open-ready', <String, Object?>{
    'scenarioId': 'ready',
    'displayName': 'Open ready state',
    'timeoutMs': 10000,
    'timeoutOutcome': 'fail',
    'cancellationPolicy': 'immediate',
    'steps': <Object?>[
      <String, Object?>{
        'id': 'prepare',
        'kind': 'executionBinding',
        'bindingId': 'ready-web',
        'timeoutMs': 10000,
        'timeoutOutcome': 'cancel',
      },
    ],
  }),
  _v2('ScenarioLabPlan', 'ready', <String, Object?>{
    'scenarioId': 'ready',
    'executionBindingIds': <String>['ready-web'],
    'controlIds': <String>[],
    'operationIds': <String>[],
    'scriptIds': <String>['open-ready'],
    'automatedAcceptanceCriterionIds': <String>[],
    'requiredEvidenceIds': <String>[],
    'comparisonBindingIds': <String>[],
    'humanApprovalRequirementIds': <String>[],
    'supplementalArtifactIds': <String>[],
  }),
];

List<AuthoringDocument> _topologyDocuments() => <AuthoringDocument>[
  _v2('Board', 'delivery-board', <String, Object?>{
    'applicationId': 'delivery-app',
    'title': 'Delivery board',
    'projectionIds': <String>['delivery-inventory'],
  }),
  _v2('ExperienceProjection', 'delivery-inventory', <String, Object?>{
    'boardId': 'delivery-board',
    'applicationId': 'delivery-app',
    'title': 'Delivery inventory',
    'projectionKind': 'inventory',
    'nodeInstanceIds': <String>['ready-node'],
    'edgeInstanceIds': <String>[],
  }),
  _v2('NodeInstance', 'ready-node', <String, Object?>{
    'projectionId': 'delivery-inventory',
    'scenarioId': 'ready',
  }),
  _v2('ProjectionLayout', 'delivery-inventory', <String, Object?>{
    'projectionId': 'delivery-inventory',
    'nodeFrames': <Object?>[
      <String, Object?>{
        'nodeInstanceId': 'ready-node',
        'x': 0,
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

List<AuthoringDocument> _facetDocuments() => <AuthoringDocument>[
  _v2('ScenarioKindDefinition', 'observable-state', <String, Object?>{
    'displayName': 'Observable state',
  }),
  _v2('ExperienceSurface', 'delivery-dashboard', <String, Object?>{
    'applicationId': 'delivery-app',
    'displayName': 'Delivery dashboard',
  }),
  _v2('ScenarioState', 'ready', <String, Object?>{
    'surfaceId': 'delivery-dashboard',
    'displayName': 'Ready',
  }),
  _v2('OwnershipArea', 'experience-team', <String, Object?>{
    'displayName': 'Experience team',
  }),
  _v2('ScenarioTag', 'dashboard', <String, Object?>{
    'displayName': 'Dashboard',
  }),
  _v2('ExperienceComponent', 'dashboard-page', <String, Object?>{
    'applicationId': 'delivery-app',
    'displayName': 'Dashboard page',
  }),
  _v2('ScenarioFixture', 'delivery.ready', <String, Object?>{
    'applicationId': 'delivery-app',
    'displayName': 'Ready deliveries',
  }),
  _v2('FormFactor', 'phone', <String, Object?>{'displayName': 'Phone'}),
  _v2('PresentationFrame', 'phone-device', <String, Object?>{
    'displayName': 'Phone device',
    'frameKind': 'device',
    'formFactorId': 'phone',
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
    'fixtureId': 'delivery.ready',
    'renderSource': <String, Object?>{
      'kind': 'executionBinding',
      'bindingId': 'ready-web',
    },
    'presentationFrameIds': <String>['phone-device'],
    'preferredPresentationFrameId': 'phone-device',
  }),
];

AuthoringDocument _v2(String kind, String id, Map<String, Object?> spec) =>
    _parse(schemaVersion: 2, kind: kind, id: id, spec: spec);

AuthoringDocument _parse({
  required int schemaVersion,
  required String kind,
  required String id,
  required Map<String, Object?> spec,
}) => const SafeAuthoringParser().parse(
  jsonEncode(<String, Object?>{
    'schemaVersion': schemaVersion,
    'kind': kind,
    'metadata': <String, Object?>{'id': id},
    'spec': spec,
  }),
  sourceName: '$id.json',
);

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

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;
