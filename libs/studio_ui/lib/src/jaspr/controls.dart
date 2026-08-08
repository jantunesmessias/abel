import 'package:jaspr/dom.dart';
import 'package:jaspr/dom.dart' as dom show label;
import 'package:jaspr/jaspr.dart';

import 'icons.dart';

enum StudioButtonKind { primary, secondary, quiet, danger }

final class StudioButton extends StatelessComponent {
  const StudioButton({
    required this.label,
    required this.onPressed,
    this.kind = StudioButtonKind.primary,
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
  final StudioButtonKind kind;
  final bool disabled;
  final bool autofocus;
  final StudioIconName? leadingIcon;
  final String? id;
  final String? ariaLabel;
  final Map<String, String> attributes;

  @override
  Component build(BuildContext context) => button(
    id: id,
    type: ButtonType.button,
    disabled: disabled,
    autofocus: autofocus,
    classes: 'studio-ui-button studio-ui-button--${kind.name}',
    attributes: <String, String>{...attributes, 'aria-label': ?ariaLabel},
    onClick: disabled ? null : onPressed,
    <Component>[
      if (leadingIcon case final icon?) StudioIcon(name: icon),
      Component.text(label),
    ],
  );
}

final class StudioIconButton extends StatelessComponent {
  const StudioIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.disabled = false,
    this.kind = StudioButtonKind.quiet,
    super.key,
  });

  final String label;
  final StudioIconName icon;
  final VoidCallback? onPressed;
  final bool disabled;
  final StudioButtonKind kind;

  @override
  Component build(BuildContext context) => button(
    type: ButtonType.button,
    disabled: disabled,
    classes: 'studio-ui-icon-button studio-ui-button--${kind.name}',
    attributes: <String, String>{'aria-label': label, 'title': label},
    onClick: disabled ? null : onPressed,
    <Component>[StudioIcon(name: icon)],
  );
}

final class StudioNavigationItem extends StatelessComponent {
  const StudioNavigationItem({
    required this.href,
    required this.label,
    required this.icon,
    this.selected = false,
    super.key,
  });

  final String href;
  final String label;
  final StudioIconName icon;
  final bool selected;

  @override
  Component build(BuildContext context) => a(
    href: href,
    classes: 'studio-ui-navigation-item${selected ? ' is-selected' : ''}',
    attributes: <String, String>{if (selected) 'aria-current': 'page'},
    <Component>[
      StudioIcon(name: icon),
      span(<Component>[Component.text(label)]),
    ],
  );
}

final class StudioTextInput extends StatelessComponent {
  const StudioTextInput({
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
  Component build(BuildContext context) =>
      div(classes: 'studio-ui-field', <Component>[
        dom.label(htmlFor: id, <Component>[Component.text(label)]),
        input<String>(
          id: id,
          type: type,
          value: value,
          onInput: onInput,
          classes: 'studio-ui-input',
          attributes: <String, String>{
            'placeholder': ?placeholder,
            'aria-describedby': ?(hint == null ? null : '$id-hint'),
          },
        ),
        if (hint case final text?)
          p(id: '$id-hint', classes: 'studio-ui-field__hint', <Component>[
            Component.text(text),
          ]),
      ]);
}

final class StudioSearchField extends StatelessComponent {
  const StudioSearchField({
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
      div(classes: 'studio-ui-field studio-ui-search-field', <Component>[
        dom.label(htmlFor: id, <Component>[Component.text(label)]),
        div(classes: 'studio-ui-search-field__control', <Component>[
          const StudioIcon(name: StudioIconName.search),
          input<String>(
            id: id,
            type: InputType.search,
            value: value,
            onInput: onInput,
            classes: 'studio-ui-input',
            attributes: <String, String>{'placeholder': ?placeholder},
          ),
        ]),
      ]);
}

final class StudioSelectOption {
  const StudioSelectOption({
    required this.value,
    required this.label,
    this.disabled = false,
  });

  final String value;
  final String label;
  final bool disabled;
}

final class StudioSelect extends StatelessComponent {
  const StudioSelect({
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
  final List<StudioSelectOption> options;
  final ValueChanged<String> onChange;
  final bool disabled;

  @override
  Component build(BuildContext context) =>
      div(classes: 'studio-ui-field', <Component>[
        dom.label(htmlFor: id, <Component>[Component.text(label)]),
        select(
          id: id,
          value: value,
          disabled: disabled,
          classes: 'studio-ui-select',
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

final class StudioTab {
  const StudioTab({required this.id, required this.label});

  final String id;
  final String label;
}

final class StudioTabs extends StatelessComponent {
  const StudioTabs({
    required this.label,
    required this.tabs,
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  final String label;
  final List<StudioTab> tabs;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Component build(BuildContext context) => div(
    classes: 'studio-ui-tabs',
    attributes: <String, String>{'role': 'tablist', 'aria-label': label},
    <Component>[
      for (final tab in tabs)
        button(
          id: '${tab.id}-tab',
          type: ButtonType.button,
          classes: 'studio-ui-tab${tab.id == selectedId ? ' is-selected' : ''}',
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
