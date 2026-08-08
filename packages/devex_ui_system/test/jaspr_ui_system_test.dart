@TestOn('vm')
library;

import 'package:devex_ui_system/devex_ui_system.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';

void main() {
  testComponents('renders semantic status, panel and actions', (tester) async {
    tester.pumpComponent(
      DevExPanel(
        title: 'Evidence',
        description: 'Estado canônico do Host',
        actions: <Component>[DevExButton(label: 'Atualizar', onPressed: () {})],
        children: const <Component>[
          DevExStatusPill(label: 'Desatualizada', tone: DevExTone.warning),
        ],
      ),
    );

    expect(find.tag('section'), findsOneComponent);
    expect(find.tag('h2'), findsOneComponent);
    expect(find.tag('button'), findsOneComponent);
    expect(find.tag('span'), findsOneComponent);
    expect(find.text('Evidence'), findsOneComponent);
    expect(find.text('Desatualizada'), findsOneComponent);
  });

  testComponents('connects labels to native input and select', (tester) async {
    tester.pumpComponent(
      div(<Component>[
        DevExTextInput(
          id: 'query',
          label: 'Buscar',
          value: '',
          onInput: (_) {},
        ),
        DevExSelect(
          id: 'provider',
          label: 'Provider',
          value: 'auto-preview',
          options: const <DevExSelectOption>[
            DevExSelectOption(value: 'auto-preview', label: 'AutoPreview'),
          ],
          onChange: (_) {},
        ),
      ]),
    );

    expect(find.tag('label'), findsNComponents(2));
    expect(find.tag('input'), findsOneComponent);
    expect(find.tag('select'), findsOneComponent);
    expect(find.tag('option'), findsOneComponent);
  });

  testComponents('exposes tabs as native buttons with tab semantics', (
    tester,
  ) async {
    tester.pumpComponent(
      DevExTabs(
        label: 'Detalhes do Scenario',
        tabs: const <DevExTab>[
          DevExTab(id: 'general', label: 'Geral'),
          DevExTab(id: 'evidence', label: 'Evidence'),
        ],
        selectedId: 'evidence',
        onSelect: (_) {},
      ),
    );

    expect(find.tag('button'), findsNComponents(2));
    expect(find.text('Geral'), findsOneComponent);
    expect(find.text('Evidence'), findsOneComponent);
  });

  testComponents('renders an explicitly labelled native dialog', (
    tester,
  ) async {
    tester.pumpComponent(
      DevExDialog(
        id: 'preview-confirmation',
        title: 'Coletar AutoPreview?',
        description: 'Confirme que a tela usa dados sintéticos.',
        onDismiss: () {},
        actions: <Component>[
          DevExButton(label: 'Cancelar', onPressed: () {}),
          DevExButton(
            label: 'Confirmo dados sintéticos',
            autofocus: true,
            onPressed: () {},
          ),
        ],
      ),
    );

    expect(find.tag('dialog'), findsOneComponent);
    expect(find.tag('h2'), findsOneComponent);
    expect(find.tag('button'), findsNComponents(2));
    expect(find.text('Coletar AutoPreview?'), findsOneComponent);
    expect(find.text('Confirmo dados sintéticos'), findsOneComponent);
  });

  testComponents('publishes the complete owned component surface', (
    tester,
  ) async {
    tester.pumpComponent(
      DevExTheme(
        child: div(<Component>[
          DevExNavigationItem(
            href: '/',
            label: 'Visão geral',
            icon: DevExIconName.overview,
            selected: true,
          ),
          DevExSearchField(
            id: 'search',
            label: 'Buscar',
            value: '',
            onInput: (_) {},
          ),
          DevExIconButton(
            label: 'Atualizar',
            icon: DevExIconName.refresh,
            onPressed: () {},
          ),
          const DevExPill(label: 'Atual', tone: DevExTone.positive),
          const DevExFeedbackBanner(
            title: 'Snapshot atualizado',
            message: 'O Host publicou uma nova revisão.',
          ),
          const DevExDivider(label: 'Detalhes'),
          const DevExDeviceFrame(
            label: 'Phone light',
            child: Component.text('Preview'),
          ),
          DevExSheet(
            id: 'inspector-sheet',
            title: 'Inspector',
            child: const Component.text('Evidence'),
            onClose: () {},
          ),
          DevExTooltip(
            id: 'refresh-tip',
            message: 'Atualiza o workspace',
            child: DevExIconButton(
              label: 'Atualizar outra vez',
              icon: DevExIconName.refresh,
              onPressed: () {},
            ),
          ),
        ]),
      ),
    );

    expect(find.tag('svg'), findsNComponents(5));
    expect(find.tag('input'), findsOneComponent);
    expect(find.tag('figure'), findsOneComponent);
    expect(find.tag('aside'), findsNComponents(2));
    expect(find.text('Atualiza o workspace'), findsOneComponent);
    expect(find.text('Snapshot atualizado'), findsOneComponent);
  });
}
