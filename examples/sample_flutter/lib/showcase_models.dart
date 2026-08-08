import 'package:flutter/foundation.dart';

enum ProjectHealth { onTrack, atRisk, blocked }

@immutable
final class ShowcaseTask {
  const ShowcaseTask({
    required this.id,
    required this.title,
    required this.completed,
  });

  factory ShowcaseTask.fromJson(Map<String, Object?> json) => ShowcaseTask(
    id: json['id']! as String,
    title: json['title']! as String,
    completed: json['completed']! as bool,
  );

  final String id;
  final String title;
  final bool completed;

  ShowcaseTask copyWith({bool? completed}) => ShowcaseTask(
    id: id,
    title: title,
    completed: completed ?? this.completed,
  );
}

@immutable
final class ShowcaseProject {
  ShowcaseProject({
    required this.id,
    required this.name,
    required this.summary,
    required this.owner,
    required this.health,
    required this.progress,
    required List<ShowcaseTask> tasks,
  }) : tasks = List<ShowcaseTask>.unmodifiable(tasks);

  factory ShowcaseProject.fromJson(Map<String, Object?> json) =>
      ShowcaseProject(
        id: json['id']! as String,
        name: json['name']! as String,
        summary: json['summary']! as String,
        owner: json['owner']! as String,
        health: ProjectHealth.values.byName(json['health']! as String),
        progress: (json['progress']! as num).toDouble(),
        tasks: (json['tasks']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(ShowcaseTask.fromJson)
            .toList(growable: false),
      );

  final String id;
  final String name;
  final String summary;
  final String owner;
  final ProjectHealth health;
  final double progress;
  final List<ShowcaseTask> tasks;

  ShowcaseProject copyWith({double? progress, List<ShowcaseTask>? tasks}) =>
      ShowcaseProject(
        id: id,
        name: name,
        summary: summary,
        owner: owner,
        health: health,
        progress: progress ?? this.progress,
        tasks: tasks ?? this.tasks,
      );
}

@immutable
final class DashboardSummary {
  const DashboardSummary({
    required this.projects,
    required this.completedTasks,
    required this.totalTasks,
    required this.atRiskProjects,
  });

  factory DashboardSummary.fromJson(Map<String, Object?> json) =>
      DashboardSummary(
        projects: json['projects']! as int,
        completedTasks: json['completedTasks']! as int,
        totalTasks: json['totalTasks']! as int,
        atRiskProjects: json['atRiskProjects']! as int,
      );

  final int projects;
  final int completedTasks;
  final int totalTasks;
  final int atRiskProjects;
}

@immutable
final class ShowcaseActivity {
  const ShowcaseActivity({
    required this.id,
    required this.label,
    required this.tone,
  });

  factory ShowcaseActivity.fromJson(Map<String, Object?> json) =>
      ShowcaseActivity(
        id: json['id']! as String,
        label: json['label']! as String,
        tone: json['tone']! as String,
      );

  final String id;
  final String label;
  final String tone;
}

@immutable
final class ShowcaseDashboard {
  ShowcaseDashboard({
    required this.revision,
    required this.summary,
    required List<ShowcaseProject> projects,
    required List<ShowcaseActivity> activity,
  }) : projects = List<ShowcaseProject>.unmodifiable(projects),
       activity = List<ShowcaseActivity>.unmodifiable(activity);

  factory ShowcaseDashboard.fromJson(Map<String, Object?> json) =>
      ShowcaseDashboard(
        revision: json['revision']! as int,
        summary: DashboardSummary.fromJson(
          json['summary']! as Map<String, Object?>,
        ),
        projects: (json['projects']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(ShowcaseProject.fromJson)
            .toList(growable: false),
        activity: (json['activity']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(ShowcaseActivity.fromJson)
            .toList(growable: false),
      );

  final int revision;
  final DashboardSummary summary;
  final List<ShowcaseProject> projects;
  final List<ShowcaseActivity> activity;
}
