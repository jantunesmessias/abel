import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sample_flutter/showcase_api.dart';
import 'package:sample_flutter/showcase_models.dart';

@immutable
final class SampleAppConfig {
  const SampleAppConfig({
    required this.apiBaseUrl,
    required this.environment,
    this.dashboardState = ShowcaseDashboardState.ready,
  });

  const SampleAppConfig.production()
    : apiBaseUrl = 'http://127.0.0.1:8181',
      environment = 'local-production',
      dashboardState = ShowcaseDashboardState.ready;

  final String apiBaseUrl;
  final String environment;
  final ShowcaseDashboardState dashboardState;
}

Widget createSampleApp(
  SampleAppConfig config, {
  ShowcaseApi? api,
  ValueListenable<bool>? readyHighlight,
}) => SampleApp(
  config: config,
  api:
      api ??
      HttpShowcaseApi(
        baseUrl: config.apiBaseUrl,
        dashboardState: config.dashboardState,
      ),
  readyHighlight: readyHighlight,
);

final class SampleApp extends StatelessWidget {
  const SampleApp({
    required this.config,
    required this.api,
    required this.readyHighlight,
    super.key,
  });

  final SampleAppConfig config;
  final ShowcaseApi api;
  final ValueListenable<bool>? readyHighlight;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Delivery Lab',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: ShowcaseDashboardPage(
      config: config,
      api: api,
      readyHighlight: readyHighlight,
    ),
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
    required this.readyHighlight,
    super.key,
  });

  final SampleAppConfig config;
  final ShowcaseApi api;
  final ValueListenable<bool>? readyHighlight;

  @override
  State<ShowcaseDashboardPage> createState() => _ShowcaseDashboardPageState();
}

final class _ShowcaseDashboardPageState extends State<ShowcaseDashboardPage> {
  ShowcaseDashboardResult _result = const ShowcaseDashboardResult.loading();
  Object? _mutationError;
  final Set<String> _mutatingTasks = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _result = const ShowcaseDashboardResult.loading();
      _mutationError = null;
    });
    try {
      final result = await widget.api.loadDashboard();
      if (!mounted) return;
      setState(() => _result = result);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _result = ShowcaseDashboardResult.failure(
          errorCode: _loadFailureCode(error),
        ),
      );
    }
  }

  Future<void> _toggle(ShowcaseProject project, ShowcaseTask task) async {
    final operationId = '${project.id}.${task.id}';
    setState(() {
      _mutatingTasks.add(operationId);
      _mutationError = null;
    });
    try {
      await widget.api.toggleTask(project.id, task.id);
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _mutationError = error);
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
            'Abel complete showcase',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh dashboard',
          onPressed: _result.state == ShowcaseDashboardState.loading
              ? null
              : _load,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: Semantics(
        identifier: 'showcase.dashboard',
        child: switch (_result.state) {
          ShowcaseDashboardState.loading => const _LoadingState(),
          ShowcaseDashboardState.empty => _EmptyState(onRefresh: _load),
          ShowcaseDashboardState.unavailable => _UnavailableState(
            errorCode: _result.errorCode!,
            onRetry: _load,
          ),
          ShowcaseDashboardState.failure => _FailureState(
            errorCode: _result.errorCode!,
            onRetry: _load,
          ),
          ShowcaseDashboardState.ready ||
          ShowcaseDashboardState.stale => _DashboardContent(
            config: widget.config,
            dashboard: _result.dashboard!,
            state: _result.state,
            staleSince: _result.staleSince,
            readyHighlight: widget.readyHighlight,
            mutatingTasks: _mutatingTasks,
            onToggle: _toggle,
            warning: _mutationError,
          ),
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
      identifier: 'showcase.state.loading',
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

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => _StateMessage(
    identifier: 'showcase.state.empty',
    icon: Icons.inbox_outlined,
    title: 'No delivery projects yet',
    description:
        'The workspace is available and returned a successful empty result.',
    actionLabel: 'Refresh',
    onAction: onRefresh,
  );
}

final class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.errorCode, required this.onRetry});

  final String errorCode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _StateMessage(
    identifier: 'showcase.state.unavailable',
    icon: Icons.cloud_off_outlined,
    title: 'The workspace API is unavailable',
    description:
        'This dependency outage is recoverable. Start the sample API or activate the unavailable Gateway preset.',
    diagnosticCode: errorCode,
    actionLabel: 'Try again',
    onAction: onRetry,
  );
}

final class _FailureState extends StatelessWidget {
  const _FailureState({required this.errorCode, required this.onRetry});

  final String errorCode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _StateMessage(
    identifier: 'showcase.state.failure',
    icon: Icons.bug_report_outlined,
    title: 'The dashboard could not be loaded',
    description:
        'The API reported an unexpected failure. Inspect the diagnostic code before retrying.',
    diagnosticCode: errorCode,
    actionLabel: 'Try again',
    onAction: onRetry,
    errorTone: true,
  );
}

final class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.identifier,
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    this.diagnosticCode,
    this.errorTone = false,
  });

  final String identifier;
  final IconData icon;
  final String title;
  final String description;
  final String? diagnosticCode;
  final String actionLabel;
  final VoidCallback onAction;
  final bool errorTone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Semantics(
        identifier: identifier,
        liveRegion: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 48,
                    color: errorTone ? scheme.error : scheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(description, textAlign: TextAlign.center),
                  if (diagnosticCode != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Diagnostic · $diagnosticCode',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh),
                    label: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.config,
    required this.dashboard,
    required this.state,
    required this.staleSince,
    required this.readyHighlight,
    required this.mutatingTasks,
    required this.onToggle,
    required this.warning,
  });

  final SampleAppConfig config;
  final ShowcaseDashboard dashboard;
  final ShowcaseDashboardState state;
  final DateTime? staleSince;
  final ValueListenable<bool>? readyHighlight;
  final Set<String> mutatingTasks;
  final void Function(ShowcaseProject, ShowcaseTask) onToggle;
  final Object? warning;

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      identifier: 'showcase.state.${state.name}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final content = <Widget>[
            if (state == ShowcaseDashboardState.stale) ...<Widget>[
              _StaleNotice(staleSince: staleSince!),
              const SizedBox(height: 16),
            ],
            _HeroSummary(summary: dashboard.summary),
            if (warning != null) ...<Widget>[
              const SizedBox(height: 16),
              _InlineWarning(message: '$warning'),
            ],
            const SizedBox(height: 20),
            Text(
              'Active projects',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
      ),
    );
    final highlight = readyHighlight;
    if (highlight == null) {
      return _ReadyHighlightFrame(enabled: false, child: content);
    }
    return ValueListenableBuilder<bool>(
      valueListenable: highlight,
      child: content,
      builder: (context, enabled, child) => _ReadyHighlightFrame(
        enabled: state == ShowcaseDashboardState.ready && enabled,
        child: child!,
      ),
    );
  }
}

final class _ReadyHighlightFrame extends StatelessWidget {
  const _ReadyHighlightFrame({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      identifier: 'showcase.control.dashboard-ready-highlight',
      label: 'Delivery readiness highlight',
      value: enabled ? 'enabled' : 'disabled',
      child: DecoratedBox(
        key: ValueKey<String>(
          'showcase.control.dashboard-ready-highlight.${enabled ? 'enabled' : 'disabled'}',
        ),
        decoration: BoxDecoration(
          color: enabled
              ? scheme.primaryContainer.withValues(alpha: 0.34)
              : scheme.surfaceContainerLowest,
          border: Border.all(
            color: enabled ? scheme.primary : Colors.transparent,
            width: 4,
          ),
        ),
        child: child,
      ),
    );
  }
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

final class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.staleSince});

  final DateTime staleSince;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: 'showcase.stale.notice',
    liveRegion: true,
    child: Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            const Icon(Icons.history),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Showing a stale snapshot from ${staleSince.toUtc().toIso8601String()}.',
              ),
            ),
          ],
        ),
      ),
    ),
  );
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

String _loadFailureCode(Object error) => switch (error) {
  ShowcaseApiException() => error.code,
  TimeoutException() => 'CLIENT_TIMEOUT',
  _ => 'CLIENT_LOAD_FAILURE',
};
