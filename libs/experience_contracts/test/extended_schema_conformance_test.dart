import 'dart:convert';
import 'dart:io';

import 'package:experience_contracts/experience_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = _root();

  test('canonical schemas are grouped by domain and compile', () {
    final schemasRoot = Directory(p.join(root, 'schemas'));
    final domains =
        schemasRoot
            .listSync(followLinks: false)
            .whereType<Directory>()
            .map((directory) => p.basename(directory.path))
            .toList()
          ..sort();
    expect(domains, const <String>[
      'catalog',
      'distribution',
      'evidence',
      'gateway',
      'hosted',
      'runtime',
      'source',
    ]);
    final files =
        schemasRoot
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.schema.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    expect(files, hasLength(43));
    for (final file in files) {
      expect(
        () =>
            Draft202012Validator(jsonDecode(file.readAsStringSync()) as Object),
        returnsNormally,
        reason: file.path,
      );
    }
  });

  test('consumer config accepts modules and rejects removed revisions', () {
    final validator = _validator(
      root,
      'distribution',
      'consumer-config.schema.json',
    );
    final document = <String, Object?>{
      'schemaVersion': 2,
      'content': <String, Object?>{'root': '.experience'},
      'workspace': <String, Object?>{'id': 'sample', 'displayName': 'Sample'},
      'applications': <String, Object?>{
        'sample': <String, Object?>{'root': '.', 'target': 'web'},
      },
      'launchProfiles': <String, Object?>{
        'sample-web': <String, Object?>{
          'applicationId': 'sample',
          'platform': 'web',
          'command': 'flutter',
          'arguments': <String>['run', '-d', 'web-server'],
          'workingDirectory': '.',
          'overlay': <String, String>{'SAMPLE_MODE': 'full'},
          'bootstrapPolicy': <String, String>{
            'api': 'production',
            'gateway': 'overlay',
          },
        },
      },
      'kit': <String, Object?>{
        'profile': 'journey-preview',
        'modules': <String, Object?>{
          'catalog': <String, Object?>{'enabled': true},
          'evidence.auto-preview': <String, Object?>{
            'enabled': true,
            'settings': <String, Object?>{
              'renderer': 'flutter-test',
              'capturePolicy': 'static-v1',
            },
          },
        },
      },
    };
    expect(validator.validate(document).isValid, isTrue);
    expect(
      validator.validate(<String, Object?>{
        ...document,
        'schemaVersion': 1,
      }).isValid,
      isFalse,
    );
    expect(
      validator.validate(<String, Object?>{
        ...document,
        'unknown': true,
      }).isValid,
      isFalse,
    );
    expect(
      validator.validate(<String, Object?>{
        ...document,
        'distribution': <String, Object?>{
          'id': 'sample',
          'path': 'tools/sample',
        },
      }).isValid,
      isFalse,
    );
  });

  test('topology authoring is discriminated and closed', () {
    final validator = _validator(
      root,
      'source',
      'experience-authoring-document.schema.json',
    );
    final board = <String, Object?>{
      'schemaVersion': 2,
      'kind': 'Board',
      'metadata': <String, Object?>{'id': 'delivery-flow'},
      'spec': <String, Object?>{
        'applicationId': 'sample',
        'title': 'Delivery flow',
        'projectionIds': <String>['primary-journey'],
      },
    };
    expect(validator.validate(board).isValid, isTrue);
    expect(
      validator.validate(<String, Object?>{
        ...board,
        'kind': 'NodeInstance',
      }).isValid,
      isFalse,
    );
    expect(
      validator.validate(<String, Object?>{
        ...board,
        'spec': <String, Object?>{
          ...(board['spec']! as Map<String, Object?>),
          'unknown': true,
        },
      }).isValid,
      isFalse,
    );
  });

  test('MotionSequence authoring is closed and preserves static meaning', () {
    final validator = _validator(
      root,
      'source',
      'experience-authoring-document.schema.json',
    );
    final motion = _v2Document(
      'MotionSequence',
      'delivery-review-motion',
      <String, Object?>{
        'projectionId': 'delivery-journey',
        'title': 'Delivery review motion',
        'staticSummary': 'Loading is followed by ready.',
        'steps': <Object?>[
          <String, Object?>{
            'id': 'loading-to-ready',
            'transitionId': 'loading-to-ready',
            'fromNodeId': 'journey-dashboard-loading',
            'toNodeId': 'journey-dashboard-ready',
            'startMs': 0,
            'fullDurationMs': 420,
            'reducedDurationMs': 80,
            'easing': 'easeInOut',
            'observations': <Object?>[
              <String, Object?>{
                'id': 'ready-visible',
                'label': 'Ready state is visible',
                'atFraction': 1,
                'kind': 'stateVisible',
              },
            ],
          },
        ],
      },
    );
    expect(validator.validate(motion).isValid, isTrue);
    expect(
      validator.validate(<String, Object?>{
        ...motion,
        'spec': <String, Object?>{
          ...(motion['spec']! as Map<String, Object?>),
          'motionRequiredForComprehension': true,
        },
      }).isValid,
      isFalse,
    );
    expect(
      validator.validate(<String, Object?>{
        ...motion,
        'spec': <String, Object?>{
          ...(motion['spec']! as Map<String, Object?>),
          'path': '/tmp/forbidden',
        },
      }).isValid,
      isFalse,
    );
  });

  test('Scenario taxonomy authoring is discriminated and closed', () {
    final validator = _validator(
      root,
      'source',
      'experience-authoring-document.schema.json',
    );
    final facet = <String, Object?>{
      'schemaVersion': 2,
      'kind': 'ScenarioFacet',
      'metadata': <String, Object?>{'id': 'dashboard-ready'},
      'spec': <String, Object?>{
        'scenarioId': 'dashboard-ready',
        'lifecycle': 'current',
        'scenarioKindId': 'observable-state',
        'surfaceId': 'delivery-dashboard',
        'stateId': 'ready',
        'ownershipAreaId': 'experience-team',
        'tagIds': <String>['dashboard'],
        'componentIds': <String>['showcase-dashboard-page'],
        'fixtureId': 'sample.dashboard.synthetic',
        'renderSource': <String, Object?>{
          'kind': 'previewDescriptor',
          'previewId': 'sample.dashboard.ready',
        },
        'presentationFrameIds': <String>['phone-device'],
        'preferredPresentationFrameId': 'phone-device',
      },
    };
    expect(validator.validate(facet).isValid, isTrue);
    expect(
      validator.validate(<String, Object?>{
        ...facet,
        'spec': <String, Object?>{
          ...(facet['spec']! as Map<String, Object?>),
          'metadata': <String, Object?>{},
        },
      }).isValid,
      isFalse,
    );
    expect(
      validator.validate(<String, Object?>{
        ...facet,
        'spec': <String, Object?>{
          ...(facet['spec']! as Map<String, Object?>),
          'renderSource': <String, Object?>{
            'kind': 'futureRenderer',
            'previewId': 'sample.dashboard.ready',
          },
        },
      }).isValid,
      isFalse,
    );
    expect(
      validator.validate(<String, Object?>{
        'schemaVersion': 2,
        'kind': 'PresentationFrame',
        'metadata': <String, Object?>{'id': 'unframed'},
        'spec': <String, Object?>{
          'displayName': 'Unframed',
          'frameKind': 'none',
          'formFactorId': 'phone',
        },
      }).isValid,
      isFalse,
    );
  });

  test('Scenario Lab authoring is sealed, bounded and closed', () {
    final validator = _validator(
      root,
      'source',
      'experience-authoring-document.schema.json',
    );
    final digest = Digest.semantic('lab-input').value;
    final documents = <Map<String, Object?>>[
      _v2Document('AppAdapterCapability', 'sample.locale', <String, Object?>{
        'version': 1,
        'operations': <String>['read', 'write', 'reset'],
      }),
      _v2Document('ScenarioControl', 'locale', <String, Object?>{
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
      _v2Document('ScenarioLabOperation', 'set-locale', <String, Object?>{
        'scenarioId': 'ready',
        'kind': 'assignControl',
        'controlId': 'locale',
        'value': <String, Object?>{'kind': 'choice', 'value': 'pt-br'},
      }),
      _v2Document('ScenarioScript', 'exercise-ready', <String, Object?>{
        'scenarioId': 'ready',
        'displayName': 'Exercise ready',
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
        ],
      }),
      _v2Document(
        'AutomatedAcceptanceCriterion',
        'script-succeeds',
        <String, Object?>{
          'scenarioId': 'ready',
          'displayName': 'Script succeeds',
          'kind': 'scriptSucceeded',
          'scriptId': 'exercise-ready',
        },
      ),
      _v2Document('RequiredEvidence', 'ready-visual', <String, Object?>{
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
      _v2Document(
        'ScenarioComparisonBinding',
        'ready-comparison',
        <String, Object?>{
          'scenarioId': 'ready',
          'requiredEvidenceId': 'ready-visual',
          'baseline': <String, Object?>{
            'kind': 'artifact',
            'artifactId': 'ready-baseline',
          },
          'candidate': <String, Object?>{
            'kind': 'evidence',
            'evidenceDigest': digest,
            'provenanceDigest': digest,
            'classification': 'internal',
          },
        },
      ),
      _v2Document('VisualComparisonPolicy', 'pixel-v1', <String, Object?>{
        'maxChannelDelta': 8,
        'maxChangedPixelRatio': 0.01,
      }),
      _v2Document('SemanticComparisonPolicy', 'semantic-v1', <String, Object?>{
        'maxChangedNodes': 0,
        'ignoreBounds': true,
      }),
      _v2Document(
        'HumanApprovalRequirement',
        'approve-ready',
        <String, Object?>{
          'scenarioId': 'ready',
          'reviewGuideId': 'ready-review',
          'reviewGuideStepId': 'inspect-ready',
          'scope': 'evidenceSet',
        },
      ),
      _v2Document('SupplementalArtifact', 'ready-baseline', <String, Object?>{
        'scenarioId': 'ready',
        'requiredEvidenceId': 'ready-visual',
        'role': 'comparisonBaseline',
        'artifactDigest': digest,
        'provenanceDigest': digest,
        'classification': 'internal',
      }),
      _v2Document('ScenarioLabPlan', 'ready', <String, Object?>{
        'scenarioId': 'ready',
        'executionBindingIds': <String>['ready-web'],
        'controlIds': <String>['locale'],
        'operationIds': <String>['set-locale'],
        'scriptIds': <String>['exercise-ready'],
        'automatedAcceptanceCriterionIds': <String>['script-succeeds'],
        'requiredEvidenceIds': <String>['ready-visual'],
        'comparisonBindingIds': <String>['ready-comparison'],
        'humanApprovalRequirementIds': <String>['approve-ready'],
        'supplementalArtifactIds': <String>['ready-baseline'],
      }),
    ];

    for (final document in documents) {
      final result = validator.validate(document);
      expect(
        result.isValid,
        isTrue,
        reason: '${document['kind']}: ${result.issues.join('\n')}',
      );
    }

    final bindingOnlyPlan = _v2Document(
      'ScenarioLabPlan',
      'binding-only',
      <String, Object?>{
        'scenarioId': 'binding-only',
        'executionBindingIds': <String>['binding-only-web'],
        'controlIds': <String>[],
        'operationIds': <String>[],
        'scriptIds': <String>['open-binding-only'],
        'automatedAcceptanceCriterionIds': <String>[],
        'requiredEvidenceIds': <String>[],
        'comparisonBindingIds': <String>[],
        'humanApprovalRequirementIds': <String>[],
        'supplementalArtifactIds': <String>[],
      },
    );
    expect(validator.validate(bindingOnlyPlan).isValid, isTrue);

    final operation = documents.singleWhere(
      (document) => document['kind'] == 'ScenarioLabOperation',
    );
    expect(
      validator.validate(<String, Object?>{
        ...operation,
        'spec': <String, Object?>{
          'scenarioId': 'ready',
          'kind': 'invokeCapability',
          'capability': <String, Object?>{},
        },
      }).isValid,
      isFalse,
    );
    final artifact = documents.singleWhere(
      (document) => document['kind'] == 'SupplementalArtifact',
    );
    expect(
      validator.validate(<String, Object?>{
        ...artifact,
        'spec': <String, Object?>{
          ...(artifact['spec']! as Map<String, Object?>),
          'path': '/tmp/baseline.png',
        },
      }).isValid,
      isFalse,
    );
  });
}

Map<String, Object?> _v2Document(
  String kind,
  String id,
  Map<String, Object?> spec,
) => <String, Object?>{
  'schemaVersion': 2,
  'kind': kind,
  'metadata': <String, Object?>{'id': id},
  'spec': spec,
};

Draft202012Validator _validator(String root, String domain, String name) =>
    Draft202012Validator(
      jsonDecode(File(p.join(root, 'schemas', domain, name)).readAsStringSync())
          as Object,
    );

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains(
          'name: experience_platform_workspace',
        )) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
