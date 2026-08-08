import 'package:interaction_model/interaction_model.dart' show PresentationTone;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

enum StudioThemeMode { system, light, dark }

extension on PresentationTone {
  String get cssClass => switch (this) {
    PresentationTone.neutral => 'is-neutral',
    PresentationTone.accent => 'is-accent',
    PresentationTone.info => 'is-info',
    PresentationTone.positive => 'is-positive',
    PresentationTone.warning => 'is-warning',
    PresentationTone.critical => 'is-critical',
  };
}

final class StudioTheme extends StatelessComponent {
  const StudioTheme({
    required this.child,
    this.mode = StudioThemeMode.system,
    super.key,
  });

  final Component child;
  final StudioThemeMode mode;

  @override
  Component build(BuildContext context) => div(
    classes: 'studio-ui-theme',
    attributes: <String, String>{'data-theme': mode.name},
    <Component>[child],
  );
}

final class StudioPill extends StatelessComponent {
  const StudioPill({
    required this.label,
    this.tone = PresentationTone.neutral,
    super.key,
  });

  final String label;
  final PresentationTone tone;

  @override
  Component build(BuildContext context) =>
      StudioStatusPill(label: label, tone: tone);
}

final class StudioStatusPill extends StatelessComponent {
  const StudioStatusPill({
    required this.label,
    this.tone = PresentationTone.neutral,
    this.live = false,
    super.key,
  });

  final String label;
  final PresentationTone tone;
  final bool live;

  @override
  Component build(BuildContext context) => span(
    classes: 'studio-ui-status-pill ${tone.cssClass}',
    attributes: <String, String>{
      'role': 'status',
      if (live) 'aria-live': 'polite',
    },
    <Component>[Component.text(label)],
  );
}

final class StudioPanel extends StatelessComponent {
  const StudioPanel({
    required this.children,
    this.title,
    this.description,
    this.actions = const <Component>[],
    this.classes,
    this.id,
    super.key,
  });

  final String? title;
  final String? description;
  final List<Component> actions;
  final List<Component> children;
  final String? classes;
  final String? id;

  @override
  Component build(BuildContext context) => section(
    id: id,
    classes: 'studio-ui-panel${classes == null ? '' : ' $classes'}',
    <Component>[
      if (title != null || description != null || actions.isNotEmpty)
        header(classes: 'studio-ui-panel__header', <Component>[
          div(classes: 'studio-ui-panel__heading', <Component>[
            if (title case final value?) h2(<Component>[Component.text(value)]),
            if (description case final value?)
              p(<Component>[Component.text(value)]),
          ]),
          if (actions.isNotEmpty)
            div(classes: 'studio-ui-panel__actions', actions),
        ]),
      div(classes: 'studio-ui-panel__body', children),
    ],
  );
}

final class StudioMetric extends StatelessComponent {
  const StudioMetric({
    required this.label,
    required this.value,
    this.detail,
    this.tone = PresentationTone.neutral,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final PresentationTone tone;

  @override
  Component build(
    BuildContext context,
  ) => article(classes: 'studio-ui-metric ${tone.cssClass}', <Component>[
    p(classes: 'studio-ui-metric__label', <Component>[Component.text(label)]),
    p(classes: 'studio-ui-metric__value', <Component>[Component.text(value)]),
    if (detail case final text?)
      p(classes: 'studio-ui-metric__detail', <Component>[Component.text(text)]),
  ]);
}

final class StudioEmptyState extends StatelessComponent {
  const StudioEmptyState({
    required this.title,
    required this.message,
    this.action,
    this.tone = PresentationTone.neutral,
    this.live = false,
    super.key,
  });

  final String title;
  final String message;
  final Component? action;
  final PresentationTone tone;
  final bool live;

  @override
  Component build(BuildContext context) => section(
    classes: 'studio-ui-empty-state ${tone.cssClass}',
    attributes: <String, String>{
      'role': tone == PresentationTone.critical ? 'alert' : 'status',
      if (live) 'aria-live': 'polite',
    },
    <Component>[
      h2(<Component>[Component.text(title)]),
      p(<Component>[Component.text(message)]),
      if (action case final value?)
        div(classes: 'studio-ui-empty-state__action', <Component>[value]),
    ],
  );
}

final class StudioProgress extends StatelessComponent {
  const StudioProgress({required this.label, super.key});

  final String label;

  @override
  Component build(BuildContext context) => div(
    classes: 'studio-ui-progress',
    attributes: <String, String>{'role': 'status', 'aria-live': 'polite'},
    <Component>[
      progress(
        classes: 'studio-ui-progress__bar',
        attributes: <String, String>{'aria-label': label},
        const <Component>[],
      ),
      span(<Component>[Component.text(label)]),
    ],
  );
}

final class StudioFeedbackBanner extends StatelessComponent {
  const StudioFeedbackBanner({
    required this.title,
    required this.message,
    this.tone = PresentationTone.info,
    this.action,
    this.live = false,
    super.key,
  });

  final String title;
  final String message;
  final PresentationTone tone;
  final Component? action;
  final bool live;

  @override
  Component build(BuildContext context) => aside(
    classes: 'studio-ui-feedback-banner ${tone.cssClass}',
    attributes: <String, String>{
      'role': tone == PresentationTone.critical ? 'alert' : 'status',
      if (live) 'aria-live': 'polite',
    },
    <Component>[
      div(<Component>[
        strong(<Component>[Component.text(title)]),
        p(<Component>[Component.text(message)]),
      ]),
      ?action,
    ],
  );
}

final class StudioDivider extends StatelessComponent {
  const StudioDivider({this.label, super.key});

  final String? label;

  @override
  Component build(BuildContext context) => div(
    classes: 'studio-ui-divider',
    attributes: const <String, String>{'role': 'separator'},
    <Component>[
      if (label case final value?) span(<Component>[Component.text(value)]),
    ],
  );
}

final class StudioDeviceFrame extends StatelessComponent {
  const StudioDeviceFrame({
    required this.child,
    required this.label,
    super.key,
  });

  final Component child;
  final String label;

  @override
  Component build(BuildContext context) => figure(
    classes: 'studio-ui-device-frame',
    attributes: <String, String>{'aria-label': label},
    <Component>[
      div(classes: 'studio-ui-device-frame__screen', <Component>[child]),
      figcaption(classes: 'sr-only', <Component>[Component.text(label)]),
    ],
  );
}
