import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sample_flutter/showcase_api.dart';
import 'package:sample_flutter/showcase_models.dart';

@immutable
final class SampleAppConfig {
  const SampleAppConfig({required this.apiBaseUrl, required this.environment});

  const SampleAppConfig.production()
    : apiBaseUrl = 'http://127.0.0.1:8181',
      environment = 'local-production';

  final String apiBaseUrl;
  final String environment;
}

Widget createSampleApp(SampleAppConfig config, {ShowcaseApi? api}) => SampleApp(
  config: config,
  api: api ?? HttpShowcaseApi(baseUrl: config.apiBaseUrl),
);

final class SampleApp extends StatelessWidget {
  const SampleApp({required this.config, required this.api, super.key});

  final SampleAppConfig config;
  final ShowcaseApi api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Delivery Lab',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: ShowcaseDashboardPage(config: config, api: api),
  );
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

final class ShowcaseDashboardPage extends StatefulWidget {
  const ShowcaseDashboardPage({
    required this.config,
    required this.api,
    super.key,
  });

  final SampleAppConfig config;
  final ShowcaseApi api;

  @override
  State<ShowcaseDashboardPage> createState() => _ShowcaseDashboardPageState();
}

final class _ShowcaseDashboardPageState extends State<ShowcaseDashboardPage> {
  ShowcaseDashboard? _dashboard;
  Object? _error;
  var _loading = true;
  final Set<String> _mutatingTasks = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dashboard = await widget.api.loadDashboard();
      if (!mounted) return;
      setState(() => _dashboard = dashboard);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(ShowcaseProject project, ShowcaseTask task) async {
    final operationId = '${project.id}.${task.id}';
    setState(() => _mutatingTasks.add(operationId));
    try {
      await widget.api.toggleTask(project.id, task.id);
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _mutatingTasks.remove(operationId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Delivery Lab'),
          Text(
            'DevExKit complete showcase',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh dashboard',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Semantics(
        identifier: 'showcase.dashboard',
        child: switch ((_loading, _dashboard, _error)) {
          (true, null, _) => const _LoadingState(),
          (_, null, final error?) => _ErrorState(error: error, onRetry: _load),
          (_, final dashboard?, _) => _DashboardContent(
            config: widget.config,
            dashboard: dashboard,
            mutatingTasks: _mutatingTasks,
            onToggle: _toggle,
            warning: _error,
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    ),
  );
}

final class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      identifier: 'showcase.loading',
      liveRegion: true,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading delivery workspace…'),
        ],
      ),
    ),
  );
}

final class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      identifier: 'showcase.error',
      liveRegion: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'The workspace API is unavailable',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Start the sample API or activate a deterministic Gateway preset.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

final class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.config,
    required this.dashboard,
    required this.mutatingTasks,
    required this.onToggle,
    required this.warning,
  });

  final SampleAppConfig config;
  final ShowcaseDashboard dashboard;
  final Set<String> mutatingTasks;
  final void Function(ShowcaseProject, ShowcaseTask) onToggle;
  final Object? warning;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 980;
      final content = <Widget>[
        _HeroSummary(summary: dashboard.summary),
        if (warning != null) ...<Widget>[
          const SizedBox(height: 16),
          _InlineWarning(message: '$warning'),
        ],
        const SizedBox(height: 20),
        Text('Active projects', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final project in dashboard.projects) ...<Widget>[
          _ProjectCard(
            project: project,
            mutatingTasks: mutatingTasks,
            onToggle: onToggle,
          ),
          const SizedBox(height: 12),
        ],
      ];
      final activity = _ActivityPanel(
        activity: dashboard.activity,
        config: config,
        revision: dashboard.revision,
      );
      return SingleChildScrollView(
        padding: EdgeInsets.all(wide ? 28 : 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 7, child: Column(children: content)),
                      const SizedBox(width: 20),
                      Expanded(flex: 3, child: activity),
                    ],
                  )
                : Column(children: <Widget>[...content, activity]),
          ),
        ),
      );
    },
  );
}

final class _HeroSummary extends StatelessWidget {
  const _HeroSummary({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[scheme.primaryContainer, scheme.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'A workspace you can observe end to end',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Real HTTP, deterministic fixtures, visual evidence and executable journeys in one consumer.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _Metric(label: 'Projects', value: '${summary.projects}'),
              _Metric(
                label: 'Completed',
                value: '${summary.completedTasks}/${summary.totalTasks}',
              ),
              _Metric(
                label: 'Need attention',
                value: '${summary.atRiskProjects}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 120),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

final class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.mutatingTasks,
    required this.onToggle,
  });

  final ShowcaseProject project;
  final Set<String> mutatingTasks;
  final void Function(ShowcaseProject, ShowcaseTask) onToggle;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      project.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(project.summary),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _HealthChip(health: project.health),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: LinearProgressIndicator(
                  value: project.progress,
                  borderRadius: BorderRadius.circular(8),
                  minHeight: 8,
                ),
              ),
              const SizedBox(width: 12),
              Text('${(project.progress * 100).round()}%'),
            ],
          ),
          const SizedBox(height: 12),
          Text('Owner · ${project.owner}'),
          const Divider(height: 28),
          for (final task in project.tasks)
            Semantics(
              identifier: 'showcase.task.${project.id}.${task.id}',
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: task.completed,
                onChanged: mutatingTasks.contains('${project.id}.${task.id}')
                    ? null
                    : (_) => onToggle(project, task),
                title: Text(task.title),
              ),
            ),
        ],
      ),
    ),
  );
}

final class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.health});

  final ProjectHealth health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (health) {
      ProjectHealth.onTrack => (
        'On track',
        Icons.check_circle_outline,
        scheme.primary,
      ),
      ProjectHealth.atRisk => ('At risk', Icons.warning_amber, scheme.tertiary),
      ProjectHealth.blocked => ('Blocked', Icons.block, scheme.error),
    };
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}

final class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.activity,
    required this.config,
    required this.revision,
  });

  final List<ShowcaseActivity> activity;
  final SampleAppConfig config;
  final int revision;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final item in activity)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.tone == 'positive'
                        ? Icons.check_circle_outline
                        : Icons.warning_amber,
                  ),
                  title: Text(item.label),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Semantics(
          identifier: 'showcase.runtime',
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Runtime', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _RuntimeRow(label: 'Environment', value: config.environment),
                _RuntimeRow(label: 'API', value: config.apiBaseUrl),
                _RuntimeRow(label: 'Revision', value: '$revision'),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

final class _RuntimeRow extends StatelessWidget {
  const _RuntimeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        SelectableText(value),
      ],
    ),
  );
}

final class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          const Icon(Icons.warning_amber),
          const SizedBox(width: 12),
          Expanded(child: Text('The last operation failed: $message')),
        ],
      ),
    ),
  );
}
