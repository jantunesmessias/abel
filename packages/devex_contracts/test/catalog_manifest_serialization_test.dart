import 'dart:convert';
import 'dart:io';

import 'package:devex_contracts/devex_contracts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('CatalogManifest serialization', () {
    test('round-trips every catalog entity and verifies its digest', () {
      final source = _manifest();

      final decoded = CatalogManifest.fromJson(source.toJson());

      expect(decoded.digest, source.digest);
      expect(decoded.toJson(), source.toJson());
      expect(decoded.applications.single.id, ApplicationId('sample'));
      expect(decoded.journeys.single.scenarioIds, <ScenarioId>[
        ScenarioId('ready'),
      ]);
      expect(
        decoded.scenarios.single.sourceReferences.single.symbol,
        'ReadyPage',
      );
      expect(decoded.transitions.single.label, 'Open');
      expect(decoded.executionBindings.single.launchProfileId, 'sample-web');
      expect(decoded.reviewGuides.single.steps.single.id, 'inspect-ready');
    });

    test('conforms to the public catalog manifest schema', () {
      final validator = Draft202012Validator(
        jsonDecode(
              File(
                p.join(
                  _root(),
                  'schemas',
                  'v1',
                  'catalog-manifest.schema.json',
                ),
              ).readAsStringSync(),
            )
            as Object,
      );

      final result = validator.validate(_manifest().toJson());

      expect(result.isValid, isTrue, reason: result.issues.join('\n'));
    });

    test('canonicalizes top-level entity order', () {
      final base = _manifest();
      final second = Application(
        id: ApplicationId('another'),
        workspaceId: base.workspace.id,
        displayName: 'Another',
        root: 'apps/another',
        target: 'web',
      );

      final manifest = CatalogManifest(
        distribution: base.distribution,
        layout: base.layout,
        workspace: base.workspace,
        applications: <Application>[base.applications.single, second],
        journeys: const <Journey>[],
        scenarios: const <Scenario>[],
        transitions: const <Transition>[],
      );

      expect(manifest.applications.map((item) => item.id.value), <String>[
        'another',
        'sample',
      ]);
    });

    test('rejects unknown fields and a forged digest', () {
      final unknown = _manifest().toJson()..['unexpected'] = true;
      expect(
        () => CatalogManifest.fromJson(unknown),
        throwsA(isA<FormatException>()),
      );

      final forged = _manifest().toJson()..['digest'] = _digest('forged').value;
      expect(
        () => CatalogManifest.fromJson(forged),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('digest mismatch'),
          ),
        ),
      );
    });

    test('rejects an unknown cross-reference even with a valid digest', () {
      final document = _manifest().toJson();
      final scenarios = document['scenarios']! as List<Object?>;
      final scenario = scenarios.single! as Map<String, Object?>;
      scenario['applicationId'] = 'missing';
      document['digest'] = _documentDigest(document).value;

      expect(
        () => CatalogManifest.fromJson(document),
        throwsA(
          isA<ArgumentError>().having(
            (error) => '${error.message}',
            'message',
            contains('unknown Application'),
          ),
        ),
      );
    });

    test(
      'rejects an oversized applications array before allocation in domain',
      () {
        final document = _manifest().toJson();
        document['applications'] = List<Object?>.filled(
          10001,
          document['applications']! as List<Object?>,
        );

        expect(
          () => CatalogManifest.fromJson(document),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('exceeds 10000 items'),
            ),
          ),
        );
      },
    );
  });
}

CatalogManifest _manifest() {
  final workspaceId = WorkspaceId('workspace');
  final applicationId = ApplicationId('sample');
  final scenarioId = ScenarioId('ready');
  final bindingId = ScenarioExecutionBindingId('ready-web');
  final layout = ConsumerLayout.devexDefault;
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'devex-kit',
      displayName: 'DevExKit',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: workspaceId, displayName: 'Workspace'),
    applications: <Application>[
      Application(
        id: applicationId,
        workspaceId: workspaceId,
        displayName: 'Sample',
        root: 'apps/sample',
        target: 'web',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('launch'),
        applicationId: applicationId,
        title: 'Launch',
        scenarioIds: <ScenarioId>[scenarioId],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(
        id: scenarioId,
        applicationId: applicationId,
        title: 'Ready',
        description: 'The application is ready.',
        sourceReferences: const <SourceReference>[
          SourceReference(
            repository: 'workspace',
            path: 'lib/ready_page.dart',
            symbol: 'ReadyPage',
          ),
        ],
      ),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('open-ready'),
        journeyId: JourneyId('launch'),
        from: scenarioId,
        to: scenarioId,
        label: 'Open',
      ),
    ],
    executionBindings: <ScenarioExecutionBinding>[
      ScenarioExecutionBinding(
        id: bindingId,
        scenarioId: scenarioId,
        targetId: 'chrome',
        launchProfileId: 'sample-web',
      ),
    ],
    reviewGuides: <ReviewGuide>[
      ReviewGuide(
        id: ReviewGuideId('launch-review'),
        applicationId: applicationId,
        title: 'Launch review',
        steps: <ReviewGuideStep>[
          ReviewGuideStep(
            id: 'inspect-ready',
            instruction: 'Open the application and inspect the initial state',
            observationCriteria: 'The expected content is visible',
            scenarioId: scenarioId,
            bindingId: bindingId,
          ),
        ],
      ),
    ],
  );
}

Digest _documentDigest(Map<String, Object?> document) {
  final withoutDigest = Map<String, Object?>.of(document)..remove('digest');
  return Digest.semantic(withoutDigest);
}

Digest _digest(String value) =>
    Digest.semantic(<String, Object?>{'value': value});

String _root() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: devex_workspace')) {
      return directory.path;
    }
    if (directory.parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = directory.parent;
  }
}
