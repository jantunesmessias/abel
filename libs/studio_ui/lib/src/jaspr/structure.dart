import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

final class StudioPageHeader extends StatelessComponent {
  const StudioPageHeader({
    required this.title,
    required this.description,
    this.eyebrow,
    this.actions = const <Component>[],
    super.key,
  });

  final String title;
  final String description;
  final String? eyebrow;
  final List<Component> actions;

  @override
  Component build(BuildContext context) =>
      header(classes: 'studio-ui-page-header', <Component>[
        div(classes: 'studio-ui-page-header__copy', <Component>[
          if (eyebrow case final value?)
            p(classes: 'studio-ui-eyebrow', <Component>[Component.text(value)]),
          h1(<Component>[Component.text(title)]),
          p(classes: 'studio-ui-page-header__description', <Component>[
            Component.text(description),
          ]),
        ]),
        if (actions.isNotEmpty)
          div(classes: 'studio-ui-page-header__actions', actions),
      ]);
}

final class StudioBreadcrumbItem {
  const StudioBreadcrumbItem({required this.label, this.href});

  final String label;
  final String? href;
}

final class StudioBreadcrumbs extends StatelessComponent {
  const StudioBreadcrumbs({required this.items, super.key});

  final List<StudioBreadcrumbItem> items;

  @override
  Component build(BuildContext context) => nav(
    classes: 'studio-ui-breadcrumbs',
    attributes: const <String, String>{'aria-label': 'Breadcrumb'},
    <Component>[
      ol(<Component>[
        for (final (index, item) in items.indexed)
          li(
            attributes: <String, String>{
              if (index == items.length - 1) 'aria-current': 'page',
            },
            <Component>[
              if (item.href case final href?)
                a(href: href, <Component>[Component.text(item.label)])
              else
                Component.text(item.label),
            ],
          ),
      ]),
    ],
  );
}

final class StudioDefinitionList extends StatelessComponent {
  const StudioDefinitionList({required this.items, super.key});

  final List<(String, String)> items;

  @override
  Component build(BuildContext context) =>
      dl(classes: 'studio-ui-definition-list', <Component>[
        for (final item in items) ...<Component>[
          dt(<Component>[Component.text(item.$1)]),
          dd(<Component>[Component.text(item.$2)]),
        ],
      ]);
}
