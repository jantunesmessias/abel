@TestOn('vm')
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:studio_ui/studio_ui.dart';

void main() {
  testComponents('renders semantic status, panel and actions', (tester) async {
    tester.pumpComponent(
      StudioPanel(
        title: 'Evidence',
        description: 'Estado canônico do Host',
        actions: <Component>[
          StudioButton(label: 'Atualizar', onPressed: () {}),
        ],
        children: const <Component>[
          StudioStatusPill(
            label: 'Desatualizada',
            tone: PresentationTone.warning,
          ),
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
        StudioTextInput(
          id: 'query',
          label: 'Buscar',
          value: '',
          onInput: (_) {},
        ),
        StudioSelect(
          id: 'provider',
          label: 'Provider',
          value: 'auto-preview',
          options: const <StudioSelectOption>[
            StudioSelectOption(value: 'auto-preview', label: 'AutoPreview'),
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
      StudioTabs(
        label: 'Detalhes do Scenario',
        tabs: const <StudioTab>[
          StudioTab(id: 'general', label: 'Geral'),
          StudioTab(id: 'evidence', label: 'Evidence'),
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
      StudioDialog(
        id: 'preview-confirmation',
        title: 'Coletar AutoPreview?',
        description: 'Confirme que a tela usa dados sintéticos.',
        onDismiss: () {},
        actions: <Component>[
          StudioButton(label: 'Cancelar', onPressed: () {}),
          StudioButton(
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
      StudioTheme(
        child: div(<Component>[
          StudioNavigationItem(
            href: '/',
            label: 'Visão geral',
            icon: StudioIconName.overview,
            selected: true,
          ),
          StudioSearchField(
            id: 'search',
            label: 'Buscar',
            value: '',
            onInput: (_) {},
          ),
          StudioIconButton(
            label: 'Atualizar',
            icon: StudioIconName.refresh,
            onPressed: () {},
          ),
          const StudioPill(label: 'Atual', tone: PresentationTone.positive),
          const StudioFeedbackBanner(
            title: 'Snapshot atualizado',
            message: 'O Host publicou uma nova revisão.',
          ),
          const StudioDivider(label: 'Detalhes'),
          const StudioDeviceFrame(
            label: 'Phone light',
            child: Component.text('Preview'),
          ),
          StudioSheet(
            id: 'inspector-sheet',
            title: 'Inspector',
            child: const Component.text('Evidence'),
            onClose: () {},
          ),
          StudioTooltip(
            id: 'refresh-tip',
            message: 'Atualiza o workspace',
            child: StudioIconButton(
              label: 'Atualizar outra vez',
              icon: StudioIconName.refresh,
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
