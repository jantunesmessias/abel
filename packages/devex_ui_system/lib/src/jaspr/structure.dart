import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

final class DevExPageHeader extends StatelessComponent {
  const DevExPageHeader({
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
  Component build(BuildContext context) => header(
    classes: 'dx-page-header',
    <Component>[
      div(classes: 'dx-page-header__copy', <Component>[
        if (eyebrow case final value?)
          p(classes: 'dx-eyebrow', <Component>[Component.text(value)]),
        h1(<Component>[Component.text(title)]),
        p(classes: 'dx-page-header__description', <Component>[
          Component.text(description),
        ]),
      ]),
      if (actions.isNotEmpty) div(classes: 'dx-page-header__actions', actions),
    ],
  );
}

final class DevExBreadcrumbItem {
  const DevExBreadcrumbItem({required this.label, this.href});

  final String label;
  final String? href;
}

final class DevExBreadcrumbs extends StatelessComponent {
  const DevExBreadcrumbs({required this.items, super.key});

  final List<DevExBreadcrumbItem> items;

  @override
  Component build(BuildContext context) => nav(
    classes: 'dx-breadcrumbs',
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

final class DevExDefinitionList extends StatelessComponent {
  const DevExDefinitionList({required this.items, super.key});

  final List<(String, String)> items;

  @override
  Component build(BuildContext context) =>
      dl(classes: 'dx-definition-list', <Component>[
        for (final item in items) ...<Component>[
          dt(<Component>[Component.text(item.$1)]),
          dd(<Component>[Component.text(item.$2)]),
        ],
      ]);
}
