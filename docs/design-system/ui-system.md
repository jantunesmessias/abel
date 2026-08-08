# Studio UI System

Status: implementação Jaspr ativa em 2026-08-11.

O UI System é a linguagem visual executável do único Abel Studio. O package
`studio_ui` depende de Jaspr, HTML/CSS, Lucide e do `interaction_model`; não
depende de Flutter e não reexporta Material/Cupertino. O guard
`tools/gates/architecture_guard.dart` torna essa fronteira executável.

## Foundations

- grade espacial de 4 px e tokens CSS próprios;
- superfícies base, elevada, interativa e muted;
- raios de 6, 10, 14 e 20 px;
- foco visível de 2 px e seleção de 3 px;
- tipografia de ferramenta responsiva, sem fonte remota;
- temas claro/escuro por `prefers-color-scheme`;
- tons `neutral`, `info`, `positive`, `warning` e `critical`;
- ícones Lucide tree-shakeable encapsulados por `StudioIconName`.

Os tokens vivem em `apps/studio/web/styles/tokens.css`; reset, primitives,
components e layout permanecem em folhas locais separadas. Nenhum asset visual
é carregado de CDN.

## Componentes públicos atuais

- `StudioTheme`, `StudioPanel`, `StudioMetric` e `StudioStatusPill`;
- `StudioButton`, `StudioIconButton`, `StudioTextInput`, `StudioSearchField` e
  `StudioSelect`;
- `StudioTabs`, `StudioBreadcrumbs`, `StudioDefinitionList` e `StudioPageHeader`;
- `StudioFeedbackBanner`, `StudioEmptyState`, `StudioProgress` e `StudioDivider`;
- `StudioDialog`, implementado com `<dialog>` nativo, `showModal`, Escape,
  autofocus e restauração do foco no opener;
- `StudioDeviceFrame`, cujo frame permanece fora do PNG canônico.

Navegação, tabs, links, selects e inputs preservam alvo interativo mínimo de
48 px no browser. Imagens de Evidence usam `object-fit: contain` e respeitam a
orientação; o UI System não recorta a prova para preencher o device frame.

As superfícies do produto usam HTML semântico (`main`, `nav`, headings, listas,
forms, links e buttons). `aria-*` complementa semântica nativa; não existe DOM
Flutter nem canvas para a UI do Studio. Canvas só aparece como transporte H.264
da capability Remote.

## Regras de adoção

1. Uma feature usa os componentes acima antes de criar primitive local.
2. Estados disabled, busy, failure, stale e empty devem ser explícitos.
3. Todo controle recebe nome acessível e alvo mínimo exercitado pelo gate.
4. Motion usa tokens e zera duração sob `prefers-reduced-motion`.
5. Texto a 200% deve refluir sem overflow horizontal do documento.
6. Iframes usam origin separado, sandbox e `no-referrer`.
7. Novos ícones entram por `StudioIconName`; SVG inline artesanal é proibido.

## Evidência e limites

`tools/probes/studio_jaspr_cdp_probe.dart`, executado com Google Chrome, verifica DOM
semântico, nomes acessíveis, Tab, reflow a 200%, redução de motion, `<dialog>`,
AX tree, logs severos e performance de interação. Component tests vivem em
`libs/studio_ui/test` e `apps/studio/test/jaspr`.

Na execução oficial de 2026-08-11, o menor alvo medido foi 48 px, nenhum dos 29
controles focáveis ficou sem nome, oito Tab stops distintos foram visitados,
360 px com texto a 200% não produziu overflow do documento, reduced motion
resultou em 0,00001 s e o p95 de 20 interações no mapa foi 33,4 ms. Esses
números pertencem ao build release exercitado e não são garantias abstratas de
qualquer tela futura.

Esses gates cobrem o vertical e os componentes exercitados. Eles não equivalem
a uma certificação WCAG completa nem substituem testes com leitores de tela em
cada plataforma.
