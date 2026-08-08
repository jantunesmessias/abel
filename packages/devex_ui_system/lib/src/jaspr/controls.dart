import 'package:jaspr/dom.dart';
import 'package:jaspr/dom.dart' as dom show label;
import 'package:jaspr/jaspr.dart';

import 'icons.dart';

enum DevExButtonKind { primary, secondary, quiet, danger }

final class DevExButton extends StatelessComponent {
  const DevExButton({
    required this.label,
    required this.onPressed,
    this.kind = DevExButtonKind.primary,
    this.disabled = false,
    this.autofocus = false,
    this.leadingIcon,
    this.id,
    this.ariaLabel,
    this.attributes = const <String, String>{},
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final DevExButtonKind kind;
  final bool disabled;
  final bool autofocus;
  final DevExIconName? leadingIcon;
  final String? id;
  final String? ariaLabel;
  final Map<String, String> attributes;

  @override
  Component build(BuildContext context) => button(
    id: id,
    type: ButtonType.button,
    disabled: disabled,
    autofocus: autofocus,
    classes: 'dx-button dx-button--${kind.name}',
    attributes: <String, String>{...attributes, 'aria-label': ?ariaLabel},
    onClick: disabled ? null : onPressed,
    <Component>[
      if (leadingIcon case final icon?) DevExIcon(name: icon),
      Component.text(label),
    ],
  );
}

final class DevExIconButton extends StatelessComponent {
  const DevExIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.disabled = false,
    this.kind = DevExButtonKind.quiet,
    super.key,
  });

  final String label;
  final DevExIconName icon;
  final VoidCallback? onPressed;
  final bool disabled;
  final DevExButtonKind kind;

  @override
  Component build(BuildContext context) => button(
    type: ButtonType.button,
    disabled: disabled,
    classes: 'dx-icon-button dx-button--${kind.name}',
    attributes: <String, String>{'aria-label': label, 'title': label},
    onClick: disabled ? null : onPressed,
    <Component>[DevExIcon(name: icon)],
  );
}

final class DevExNavigationItem extends StatelessComponent {
  const DevExNavigationItem({
    required this.href,
    required this.label,
    required this.icon,
    this.selected = false,
    super.key,
  });

  final String href;
  final String label;
  final DevExIconName icon;
  final bool selected;

  @override
  Component build(BuildContext context) => a(
    href: href,
    classes: 'dx-navigation-item${selected ? ' is-selected' : ''}',
    attributes: <String, String>{if (selected) 'aria-current': 'page'},
    <Component>[
      DevExIcon(name: icon),
      span(<Component>[Component.text(label)]),
    ],
  );
}

final class DevExTextInput extends StatelessComponent {
  const DevExTextInput({
    required this.id,
    required this.label,
    required this.value,
    required this.onInput,
    this.placeholder,
    this.hint,
    this.type = InputType.text,
    super.key,
  });

  final String id;
  final String label;
  final String value;
  final ValueChanged<String> onInput;
  final String? placeholder;
  final String? hint;
  final InputType type;

  @override
  Component build(BuildContext context) => div(classes: 'dx-field', <Component>[
    dom.label(htmlFor: id, <Component>[Component.text(label)]),
    input<String>(
      id: id,
      type: type,
      value: value,
      onInput: onInput,
      classes: 'dx-input',
      attributes: <String, String>{
        'placeholder': ?placeholder,
        'aria-describedby': ?(hint == null ? null : '$id-hint'),
      },
    ),
    if (hint case final text?)
      p(id: '$id-hint', classes: 'dx-field__hint', <Component>[
        Component.text(text),
      ]),
  ]);
}

final class DevExSearchField extends StatelessComponent {
  const DevExSearchField({
    required this.id,
    required this.label,
    required this.value,
    required this.onInput,
    this.placeholder,
    super.key,
  });

  final String id;
  final String label;
  final String value;
  final ValueChanged<String> onInput;
  final String? placeholder;

  @override
  Component build(BuildContext context) =>
      div(classes: 'dx-field dx-search-field', <Component>[
        dom.label(htmlFor: id, <Component>[Component.text(label)]),
        div(classes: 'dx-search-field__control', <Component>[
          const DevExIcon(name: DevExIconName.search),
          input<String>(
            id: id,
            type: InputType.search,
            value: value,
            onInput: onInput,
            classes: 'dx-input',
            attributes: <String, String>{'placeholder': ?placeholder},
          ),
        ]),
      ]);
}

final class DevExSelectOption {
  const DevExSelectOption({
    required this.value,
    required this.label,
    this.disabled = false,
  });

  final String value;
  final String label;
  final bool disabled;
}

final class DevExSelect extends StatelessComponent {
  const DevExSelect({
    required this.id,
    required this.label,
    required this.value,
    required this.options,
    required this.onChange,
    this.disabled = false,
    super.key,
  });

  final String id;
  final String label;
  final String value;
  final List<DevExSelectOption> options;
  final ValueChanged<String> onChange;
  final bool disabled;

  @override
  Component build(BuildContext context) => div(classes: 'dx-field', <Component>[
    dom.label(htmlFor: id, <Component>[Component.text(label)]),
    select(
      id: id,
      value: value,
      disabled: disabled,
      classes: 'dx-select',
      onChange: (values) {
        if (values case [final selected, ...]) onChange(selected);
      },
      <Component>[
        for (final item in options)
          option(
            value: item.value,
            selected: item.value == value,
            disabled: item.disabled,
            <Component>[Component.text(item.label)],
          ),
      ],
    ),
  ]);
}

final class DevExTab {
  const DevExTab({required this.id, required this.label});

  final String id;
  final String label;
}

final class DevExTabs extends StatelessComponent {
  const DevExTabs({
    required this.label,
    required this.tabs,
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  final String label;
  final List<DevExTab> tabs;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Component build(BuildContext context) => div(
    classes: 'dx-tabs',
    attributes: <String, String>{'role': 'tablist', 'aria-label': label},
    <Component>[
      for (final tab in tabs)
        button(
          id: '${tab.id}-tab',
          type: ButtonType.button,
          classes: 'dx-tab${tab.id == selectedId ? ' is-selected' : ''}',
          attributes: <String, String>{
            'role': 'tab',
            'aria-selected': '${tab.id == selectedId}',
            'aria-controls': '${tab.id}-panel',
            'tabindex': tab.id == selectedId ? '0' : '-1',
          },
          onClick: () => onSelect(tab.id),
          <Component>[Component.text(tab.label)],
        ),
    ],
  );
}
