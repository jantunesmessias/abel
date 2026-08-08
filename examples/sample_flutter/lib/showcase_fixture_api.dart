import 'package:sample_flutter/showcase_api.dart';
import 'package:sample_flutter/showcase_models.dart';

final class SyntheticShowcaseApi implements ShowcaseApi {
  SyntheticShowcaseApi({ShowcaseDashboardResult? result})
    : result = result ?? ShowcaseDashboardResult.ready(syntheticDashboard());

  final ShowcaseDashboardResult result;

  @override
  Future<ShowcaseDashboardResult> loadDashboard() =>
      Future<ShowcaseDashboardResult>.value(result);

  @override
  Future<void> toggleTask(String projectId, String taskId) =>
      Future<void>.value();
}

ShowcaseDashboardResult syntheticDashboardResult(
  ShowcaseDashboardState state,
) => switch (state) {
  ShowcaseDashboardState.ready => ShowcaseDashboardResult.ready(
    syntheticDashboard(),
  ),
  ShowcaseDashboardState.loading => const ShowcaseDashboardResult.loading(),
  ShowcaseDashboardState.empty => const ShowcaseDashboardResult.empty(),
  ShowcaseDashboardState.stale => ShowcaseDashboardResult.stale(
    syntheticDashboard(),
    staleSince: DateTime.utc(2026, 8, 13, 12),
  ),
  ShowcaseDashboardState.unavailable =>
    const ShowcaseDashboardResult.unavailable(
      errorCode: 'SAMPLE_DEPENDENCY_UNAVAILABLE',
    ),
  ShowcaseDashboardState.failure => const ShowcaseDashboardResult.failure(
    errorCode: 'SAMPLE_API_FAILURE',
  ),
};

ShowcaseDashboard syntheticDashboard({
  bool deliveryTaskCompleted = false,
  bool gatewayTrafficObserved = false,
}) {
  final projects = <ShowcaseProject>[
    ShowcaseProject(
      id: 'mobile-foundation',
      name: 'Mobile foundation',
      summary: 'Ship the shared application shell and first user journey.',
      owner: 'Core team',
      health: ProjectHealth.onTrack,
      progress: deliveryTaskCompleted ? 1 : 2 / 3,
      tasks: <ShowcaseTask>[
        const ShowcaseTask(
          id: 'navigation',
          title: 'Navigation shell',
          completed: true,
        ),
        const ShowcaseTask(
          id: 'design-system',
          title: 'Design system tokens',
          completed: true,
        ),
        ShowcaseTask(
          id: 'offline-state',
          title: 'Offline state',
          completed: deliveryTaskCompleted,
        ),
      ],
    ),
    ShowcaseProject(
      id: 'checkout-observability',
      name: 'Checkout observability',
      summary: 'Make payment failures visible and reproducible.',
      owner: 'Experience team',
      health: ProjectHealth.atRisk,
      progress: 1 / 3,
      tasks: const <ShowcaseTask>[
        ShowcaseTask(
          id: 'gateway-contracts',
          title: 'Gateway contracts',
          completed: true,
        ),
        ShowcaseTask(
          id: 'failure-fixtures',
          title: 'Failure fixtures',
          completed: false,
        ),
        ShowcaseTask(
          id: 'release-evidence',
          title: 'Release evidence',
          completed: false,
        ),
      ],
    ),
    ShowcaseProject(
      id: 'account-recovery',
      name: 'Account recovery',
      summary: 'Unblock recovery while identity work is pending.',
      owner: 'Identity team',
      health: ProjectHealth.blocked,
      progress: 0.5,
      tasks: const <ShowcaseTask>[
        ShowcaseTask(
          id: 'threat-model',
          title: 'Threat model',
          completed: true,
        ),
        ShowcaseTask(
          id: 'provider-contract',
          title: 'Identity provider contract',
          completed: false,
        ),
      ],
    ),
  ];
  return ShowcaseDashboard(
    revision: deliveryTaskCompleted || gatewayTrafficObserved ? 2 : 1,
    summary: DashboardSummary(
      projects: 3,
      completedTasks: deliveryTaskCompleted ? 5 : 4,
      totalTasks: 8,
      atRiskProjects: 2,
    ),
    projects: projects,
    activity: <ShowcaseActivity>[
      if (deliveryTaskCompleted)
        const ShowcaseActivity(
          id: 'activity-task',
          label: 'Offline state completed through the production client',
          tone: 'positive',
        ),
      if (gatewayTrafficObserved) ...const <ShowcaseActivity>[
        ShowcaseActivity(
          id: 'activity-gateway-upstream',
          label: 'Dashboard response passed through the sample API',
          tone: 'positive',
        ),
        ShowcaseActivity(
          id: 'activity-gateway-fixture',
          label: 'Runtime configuration served by a Gateway fixture',
          tone: 'warning',
        ),
      ] else ...const <ShowcaseActivity>[
        ShowcaseActivity(
          id: 'activity-1',
          label: 'Gateway contracts validated',
          tone: 'positive',
        ),
        ShowcaseActivity(
          id: 'activity-2',
          label: 'Account recovery needs attention',
          tone: 'warning',
        ),
      ],
    ],
  );
}
