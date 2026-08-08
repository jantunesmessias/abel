import 'package:devex_ux_system/devex_ux_system.dart' show DevExTone;
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

enum DevExThemeMode { system, light, dark }

extension on DevExTone {
  String get cssClass => switch (this) {
    DevExTone.neutral => 'is-neutral',
    DevExTone.accent => 'is-accent',
    DevExTone.info => 'is-info',
    DevExTone.positive => 'is-positive',
    DevExTone.warning => 'is-warning',
    DevExTone.critical => 'is-critical',
  };
}

final class DevExTheme extends StatelessComponent {
  const DevExTheme({
    required this.child,
    this.mode = DevExThemeMode.system,
    super.key,
  });

  final Component child;
  final DevExThemeMode mode;

  @override
  Component build(BuildContext context) => div(
    classes: 'dx-theme',
    attributes: <String, String>{'data-theme': mode.name},
    <Component>[child],
  );
}

final class DevExPill extends StatelessComponent {
  const DevExPill({
    required this.label,
    this.tone = DevExTone.neutral,
    super.key,
  });

  final String label;
  final DevExTone tone;

  @override
  Component build(BuildContext context) =>
      DevExStatusPill(label: label, tone: tone);
}

final class DevExStatusPill extends StatelessComponent {
  const DevExStatusPill({
    required this.label,
    this.tone = DevExTone.neutral,
    this.live = false,
    super.key,
  });

  final String label;
  final DevExTone tone;
  final bool live;

  @override
  Component build(BuildContext context) => span(
    classes: 'dx-status-pill ${tone.cssClass}',
    attributes: <String, String>{
      'role': 'status',
      if (live) 'aria-live': 'polite',
    },
    <Component>[Component.text(label)],
  );
}

final class DevExPanel extends StatelessComponent {
  const DevExPanel({
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
    classes: 'dx-panel${classes == null ? '' : ' $classes'}',
    <Component>[
      if (title != null || description != null || actions.isNotEmpty)
        header(classes: 'dx-panel__header', <Component>[
          div(classes: 'dx-panel__heading', <Component>[
            if (title case final value?) h2(<Component>[Component.text(value)]),
            if (description case final value?)
              p(<Component>[Component.text(value)]),
          ]),
          if (actions.isNotEmpty) div(classes: 'dx-panel__actions', actions),
        ]),
      div(classes: 'dx-panel__body', children),
    ],
  );
}

final class DevExMetric extends StatelessComponent {
  const DevExMetric({
    required this.label,
    required this.value,
    this.detail,
    this.tone = DevExTone.neutral,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final DevExTone tone;

  @override
  Component build(BuildContext context) =>
      article(classes: 'dx-metric ${tone.cssClass}', <Component>[
        p(classes: 'dx-metric__label', <Component>[Component.text(label)]),
        p(classes: 'dx-metric__value', <Component>[Component.text(value)]),
        if (detail case final text?)
          p(classes: 'dx-metric__detail', <Component>[Component.text(text)]),
      ]);
}

final class DevExEmptyState extends StatelessComponent {
  const DevExEmptyState({
    required this.title,
    required this.message,
    this.action,
    this.tone = DevExTone.neutral,
    this.live = false,
    super.key,
  });

  final String title;
  final String message;
  final Component? action;
  final DevExTone tone;
  final bool live;

  @override
  Component build(BuildContext context) => section(
    classes: 'dx-empty-state ${tone.cssClass}',
    attributes: <String, String>{
      'role': tone == DevExTone.critical ? 'alert' : 'status',
      if (live) 'aria-live': 'polite',
    },
    <Component>[
      h2(<Component>[Component.text(title)]),
      p(<Component>[Component.text(message)]),
      if (action case final value?)
        div(classes: 'dx-empty-state__action', <Component>[value]),
    ],
  );
}

final class DevExProgress extends StatelessComponent {
  const DevExProgress({required this.label, super.key});

  final String label;

  @override
  Component build(BuildContext context) => div(
    classes: 'dx-progress',
    attributes: <String, String>{'role': 'status', 'aria-live': 'polite'},
    <Component>[
      progress(
        classes: 'dx-progress__bar',
        attributes: <String, String>{'aria-label': label},
        const <Component>[],
      ),
      span(<Component>[Component.text(label)]),
    ],
  );
}

final class DevExFeedbackBanner extends StatelessComponent {
  const DevExFeedbackBanner({
    required this.title,
    required this.message,
    this.tone = DevExTone.info,
    this.action,
    this.live = false,
    super.key,
  });

  final String title;
  final String message;
  final DevExTone tone;
  final Component? action;
  final bool live;

  @override
  Component build(BuildContext context) => aside(
    classes: 'dx-feedback-banner ${tone.cssClass}',
    attributes: <String, String>{
      'role': tone == DevExTone.critical ? 'alert' : 'status',
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

final class DevExDivider extends StatelessComponent {
  const DevExDivider({this.label, super.key});

  final String? label;

  @override
  Component build(BuildContext context) => div(
    classes: 'dx-divider',
    attributes: const <String, String>{'role': 'separator'},
    <Component>[
      if (label case final value?) span(<Component>[Component.text(value)]),
    ],
  );
}

final class DevExDeviceFrame extends StatelessComponent {
  const DevExDeviceFrame({required this.child, required this.label, super.key});

  final Component child;
  final String label;

  @override
  Component build(BuildContext context) => figure(
    classes: 'dx-device-frame',
    attributes: <String, String>{'aria-label': label},
    <Component>[
      div(classes: 'dx-device-frame__screen', <Component>[child]),
      figcaption(classes: 'sr-only', <Component>[Component.text(label)]),
    ],
  );
}
