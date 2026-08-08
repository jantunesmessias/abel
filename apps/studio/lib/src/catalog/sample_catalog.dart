import 'package:experience_contracts/experience_contracts.dart';

CatalogManifest sampleCatalogManifest() {
  final layout = ConsumerLayout.standard;
  return CatalogManifest(
    distribution: DistributionDescriptor(
      id: 'full-local',
      displayName: 'Abel',
      coreCompatibility: '^0.1.0',
      defaultLayout: layout,
    ),
    layout: layout,
    workspace: Workspace(id: WorkspaceId('sample'), displayName: 'Sample'),
    applications: <Application>[
      Application(
        id: ApplicationId('sample-app'),
        workspaceId: WorkspaceId('sample'),
        displayName: 'Sample App',
        root: '.',
        target: 'local',
      ),
    ],
    journeys: <Journey>[
      Journey(
        id: JourneyId('sample'),
        applicationId: ApplicationId('sample-app'),
        title: 'Primeira jornada',
        scenarioIds: <ScenarioId>[
          ScenarioId('discover'),
          ScenarioId('understand'),
          ScenarioId('review'),
        ],
      ),
    ],
    scenarios: <Scenario>[
      Scenario(
        id: ScenarioId('discover'),
        applicationId: ApplicationId('sample-app'),
        title: 'Descobrir',
        description: 'Encontre a experiência relevante.',
      ),
      Scenario(
        id: ScenarioId('understand'),
        applicationId: ApplicationId('sample-app'),
        title: 'Compreender',
        description: 'Leia intenção e contexto.',
      ),
      Scenario(
        id: ScenarioId('review'),
        applicationId: ApplicationId('sample-app'),
        title: 'Revisar',
        description: 'Compare a evidência.',
      ),
    ],
    transitions: <Transition>[
      Transition(
        id: TransitionId('discover-understand'),
        journeyId: JourneyId('sample'),
        from: ScenarioId('discover'),
        to: ScenarioId('understand'),
      ),
      Transition(
        id: TransitionId('understand-review'),
        journeyId: JourneyId('sample'),
        from: ScenarioId('understand'),
        to: ScenarioId('review'),
      ),
    ],
  );
}
