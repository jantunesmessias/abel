enum ProjectHealth { onTrack, atRisk, blocked }

enum DashboardState { ready, loading, empty, stale, unavailable, failure }

final class ShowcaseTask {
  const ShowcaseTask({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  ShowcaseTask copyWith({bool? completed}) => ShowcaseTask(
    id: id,
    title: title,
    completed: completed ?? this.completed,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'completed': completed,
  };
}

final class ShowcaseProject {
  ShowcaseProject({
    required this.id,
    required this.name,
    required this.summary,
    required this.owner,
    required this.health,
    required List<ShowcaseTask> tasks,
  }) : tasks = List<ShowcaseTask>.unmodifiable(tasks);

  final String id;
  final String name;
  final String summary;
  final String owner;
  final ProjectHealth health;
  final List<ShowcaseTask> tasks;

  double get progress => tasks.isEmpty
      ? 0
      : tasks.where((task) => task.completed).length / tasks.length;

  ShowcaseProject copyWith({List<ShowcaseTask>? tasks}) => ShowcaseProject(
    id: id,
    name: name,
    summary: summary,
    owner: owner,
    health: health,
    tasks: tasks ?? this.tasks,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'summary': summary,
    'owner': owner,
    'health': health.name,
    'progress': progress,
    'tasks': <Object?>[for (final task in tasks) task.toJson()],
  };
}

final class ShowcaseRepository {
  ShowcaseRepository() {
    reset();
  }

  late List<ShowcaseProject> _projects;
  var _revision = 0;

  int get revision => _revision;
  List<ShowcaseProject> get projects =>
      List<ShowcaseProject>.unmodifiable(_projects);

  ShowcaseProject? project(String id) {
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  ShowcaseProject? toggleTask(String projectId, String taskId) {
    final projectIndex = _projects.indexWhere(
      (project) => project.id == projectId,
    );
    if (projectIndex < 0) return null;
    final project = _projects[projectIndex];
    final taskIndex = project.tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex < 0) return null;
    final tasks = project.tasks.toList(growable: false);
    tasks[taskIndex] = tasks[taskIndex].copyWith(
      completed: !tasks[taskIndex].completed,
    );
    final updated = project.copyWith(tasks: tasks);
    _projects[projectIndex] = updated;
    _revision += 1;
    return updated;
  }

  void reset() {
    _projects = <ShowcaseProject>[
      ShowcaseProject(
        id: 'mobile-foundation',
        name: 'Mobile foundation',
        summary: 'Ship the shared application shell and first user journey.',
        owner: 'Core team',
        health: ProjectHealth.onTrack,
        tasks: const <ShowcaseTask>[
          ShowcaseTask(
            id: 'navigation',
            title: 'Navigation shell',
            completed: true,
          ),
          ShowcaseTask(
            id: 'design-system',
            title: 'Design system tokens',
            completed: true,
          ),
          ShowcaseTask(
            id: 'offline-state',
            title: 'Offline state',
            completed: false,
          ),
        ],
      ),
      ShowcaseProject(
        id: 'checkout-observability',
        name: 'Checkout observability',
        summary: 'Make payment failures visible and reproducible.',
        owner: 'Experience team',
        health: ProjectHealth.atRisk,
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
        summary: 'Unblock the recovery flow while identity work is pending.',
        owner: 'Identity team',
        health: ProjectHealth.blocked,
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
    _revision += 1;
  }

  Map<String, Object?> dashboard() {
    final tasks = _projects.expand((project) => project.tasks).toList();
    return <String, Object?>{
      'revision': _revision,
      'summary': <String, Object?>{
        'projects': _projects.length,
        'completedTasks': tasks.where((task) => task.completed).length,
        'totalTasks': tasks.length,
        'atRiskProjects': _projects
            .where((project) => project.health != ProjectHealth.onTrack)
            .length,
      },
      'projects': <Object?>[for (final project in _projects) project.toJson()],
      'activity': const <Object?>[
        <String, Object?>{
          'id': 'activity-1',
          'label': 'Gateway contracts validated',
          'tone': 'positive',
        },
        <String, Object?>{
          'id': 'activity-2',
          'label': 'Account recovery needs attention',
          'tone': 'warning',
        },
      ],
    };
  }
}
