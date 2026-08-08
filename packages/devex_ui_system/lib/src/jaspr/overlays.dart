import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'dialog_runtime.dart';
import 'icons.dart';

/// Modal confirmation surface rendered with the native dialog element.
///
/// The application owns visibility so dismissals remain explicit state
/// transitions. The runtime promotes the native element with `showModal()`,
/// establishes initial focus, handles Escape and restores focus to the opener.
final class DevExDialog extends StatefulComponent {
  const DevExDialog({
    required this.id,
    required this.title,
    required this.description,
    required this.actions,
    required this.onDismiss,
    this.children = const <Component>[],
    super.key,
  });

  final String id;
  final String title;
  final String description;
  final List<Component> children;
  final List<Component> actions;
  final VoidCallback onDismiss;

  @override
  State<DevExDialog> createState() => _DevExDialogState();
}

final class _DevExDialogState extends State<DevExDialog> {
  @override
  void dispose() {
    restoreModalFocus(component.id);
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    activateModal(component.id);
    return div(
      classes: 'dx-dialog-layer',
      attributes: const <String, String>{'data-modal-layer': 'true'},
      <Component>[
        dialog(
          id: component.id,
          classes: 'dx-dialog',
          attributes: <String, String>{
            'aria-modal': 'true',
            'aria-labelledby': '${component.id}-title',
            'aria-describedby': '${component.id}-description',
          },
          events: <String, EventCallback>{
            'cancel': (event) {
              event.preventDefault();
              component.onDismiss();
            },
          },
          <Component>[
            header(classes: 'dx-dialog__header', <Component>[
              h2(id: '${component.id}-title', <Component>[
                Component.text(component.title),
              ]),
              p(id: '${component.id}-description', <Component>[
                Component.text(component.description),
              ]),
            ]),
            if (component.children.isNotEmpty)
              div(classes: 'dx-dialog__body', component.children),
            footer(classes: 'dx-dialog__actions', component.actions),
          ],
        ),
      ],
    );
  }
}

final class DevExSheet extends StatelessComponent {
  const DevExSheet({
    required this.id,
    required this.title,
    required this.child,
    required this.onClose,
    super.key,
  });

  final String id;
  final String title;
  final Component child;
  final VoidCallback onClose;

  @override
  Component build(BuildContext context) => aside(
    id: id,
    classes: 'dx-sheet',
    attributes: <String, String>{
      'role': 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': '$id-title',
    },
    <Component>[
      header(classes: 'dx-sheet__header', <Component>[
        h2(id: '$id-title', <Component>[Component.text(title)]),
        button(
          type: ButtonType.button,
          classes: 'dx-icon-button dx-button--quiet',
          attributes: const <String, String>{'aria-label': 'Fechar'},
          onClick: onClose,
          const <Component>[DevExIcon(name: DevExIconName.close)],
        ),
      ]),
      div(classes: 'dx-sheet__body', <Component>[child]),
    ],
  );
}

final class DevExTooltip extends StatelessComponent {
  const DevExTooltip({
    required this.id,
    required this.message,
    required this.child,
    super.key,
  });

  final String id;
  final String message;
  final Component child;

  @override
  Component build(BuildContext context) =>
      span(classes: 'dx-tooltip', <Component>[
        span(
          attributes: <String, String>{'aria-describedby': id},
          <Component>[child],
        ),
        span(
          id: id,
          classes: 'dx-tooltip__content',
          attributes: const <String, String>{'role': 'tooltip'},
          <Component>[Component.text(message)],
        ),
      ]);
}
