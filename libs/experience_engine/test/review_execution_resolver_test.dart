import 'package:experience_contracts/experience_contracts.dart';
import 'package:experience_engine/experience_engine.dart';
import 'package:test/test.dart';

void main() {
  test('materializes exactly the digest-bound ReviewGuide grant', () {
    final manifest = _manifest();
    final resolver = ReviewExecutionResolver(manifest);

    final materialized = resolver.open(
      guideId: ReviewGuideId('first-review'),
      stepId: 'open-ready',
      expectedCatalogDigest: manifest.digest,
    );

    expect(materialized.scenarioId, ScenarioId('ready'));
    expect(materialized.binding.targetId, 'android-emulator');
    expect(materialized.binding.gatewayPresetId, 'ready-state');
    expect(materialized.binding.launchProfileId, 'sample-android');
    expect(
      materialized.grantDigest,
      Digest.semantic(<String, Object?>{
        'operation': 'OpenExecutionBinding',
        'catalogDigest': manifest.digest.value,
        'guideId': 'first-review',
        'stepId': 'open-ready',
        'scenarioId': 'ready',
        'binding': materialized.binding.toJson(),
      }),
    );
  });

  test('stale catalog and ungranted steps cannot choose routing', () {
    final manifest = _manifest();
    final resolver = ReviewExecutionResolver(manifest);

    expect(
      () => resolver.open(
        guideId: ReviewGuideId('first-review'),
        stepId: 'open-ready',
        expectedCatalogDigest: Digest.semantic('stale'),
      ),
      throwsStateError,
    );
    expect(
      () => resolver.open(
        guideId: ReviewGuideId('first-review'),
        stepId: 'free-routing',
        expectedCatalogDigest: manifest.digest,
      ),
      throwsStateError,
    );
  });

  test('compiler rejects narrative infrastructure and crossed bindings', () {
    final parser = const SafeAuthoringParser();
    final documents = <AuthoringDocument>[
      ..._baseDocuments(parser),
      parser.parse('''
schemaVersion: 1
kind: ScenarioExecutionBinding
metadata: {id: ready-binding}
spec:
  scenarioId: other
  targetId: android-emulator
  launchProfileId: sample-android
''', sourceName: 'binding.yaml'),
      parser.parse('''
schemaVersion: 1
kind: ReviewGuide
metadata: {id: review}
spec:
  applicationId: sample
  title: Review
  steps:
    - id: open
      instruction: Ao abrir, vejo o endpoint HTTP
      observationCriteria: O estado aparece
      scenarioId: ready
      bindingId: ready-binding
''', sourceName: 'review.yaml'),
    ];

    expect(
      () => const CatalogCompiler().compile(documents),
      throwsA(isA<CatalogCompileException>()),
    );
  });
}

CatalogManifest _manifest() {
  final application = ApplicationId('sample');
  final scenario = ScenarioId('ready');
  final binding = ScenarioExecutionBinding(
    id: ScenarioExecutionBindingId('ready-binding'),
    scenarioId: scenario,
    targetId: 'android-emulator',
    launchProfileId: 'sample-android',
    gatewayPresetId: 'ready-state',
  );
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: ConsumerLayout.standard,
    ),
    layout: ConsumerLayout.standard,
    workspace: Workspace(
      id: WorkspaceId('workspace'),
      displayName: 'Workspace',
    ),
    applications: <Application>[
      Application(
        id: application,
        workspaceId: WorkspaceId('workspace'),
        displayName: 'Sample',
        root: '.',
        target: 'local',
      ),
    ],
    journeys: const <Journey>[],
    scenarios: <Scenario>[
      Scenario(id: scenario, applicationId: application, title: 'Ready'),
    ],
    transitions: const <Transition>[],
    executionBindings: <ScenarioExecutionBinding>[binding],
    reviewGuides: <ReviewGuide>[
      ReviewGuide(
        id: ReviewGuideId('first-review'),
        applicationId: application,
        title: 'First review',
        steps: <ReviewGuideStep>[
          ReviewGuideStep(
            id: 'open-ready',
            instruction: 'Ao abrir o aplicativo, vejo o estado preparado',
            observationCriteria: 'O conteúdo esperado aparece',
            scenarioId: scenario,
            bindingId: binding.id,
          ),
        ],
      ),
    ],
  );
}

List<AuthoringDocument> _baseDocuments(SafeAuthoringParser parser) =>
    <AuthoringDocument>[
      parser.parse('''
schemaVersion: 1
kind: Workspace
metadata: {id: workspace}
spec: {displayName: Workspace}
''', sourceName: 'workspace.yaml'),
      parser.parse('''
schemaVersion: 1
kind: Application
metadata: {id: sample}
spec:
  workspaceId: workspace
  displayName: Sample
  root: .
  target: local
''', sourceName: 'application.yaml'),
      for (final id in <String>['ready', 'other'])
        parser.parse('''
schemaVersion: 1
kind: Scenario
metadata: {id: $id}
spec:
  applicationId: sample
  title: $id
''', sourceName: '$id.yaml'),
    ];
