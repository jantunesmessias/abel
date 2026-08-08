# DevEx UX System

Status: implementação Dart pura ativa em 2026-08-11.

`devex_ux_system` concentra políticas de experiência sem Jaspr, Flutter,
browser ou I/O. Views consomem os resultados; não duplicam decisões de layout,
motion ou windowing.

## Políticas implementadas

- `DevExWorkspaceLayoutPolicy`: classe de viewport e apresentação de Explorer
  e Inspector. Os breakpoints canônicos são 576 px (`medium`), 832 px (`wide`),
  1.280 px (`expansive`), 1.072 px para Inspector em rail e 832 px para
  Inspector empilhado;
- `DevExInteractionPolicy`: alvos mínimos por modalidade;
- `DevExMotionPolicy`: durações e redução de motion;
- `DevExZoomPolicy`: limites e nível de detalhe do Journey Map;
- `DevExSequenceWindowPolicy`: limita o DOM visual do mapa a 24 Scenarios ao
  redor da seleção, preservando o Outline completo como navegação acessível;
- `DevExTone`: vocabulário semântico canônico (`neutral`, `accent`, `info`,
  `positive`, `warning` e `critical`) compartilhado com qualquer renderer;
- vocabulário de ênfase, disclosure e feedback.

O gate de windowing usa uma sequência de 10.000 itens e prova tamanho constante,
seleção centralizada e limites inicial/final. No Studio, boundaries informam
quantos Scenarios ficaram antes/depois e orientam a seleção pelo Outline.

## Regras de experiência

- Overview responde o que existe e o que requer atenção;
- Journey Map responde onde estou, o próximo estado e qual Evidence sustenta a
  tela;
- detalhe técnico é progressive disclosure;
- ações e rotas só aparecem quando o Host publica a contribution;
- `missing`, `stale`, `failed`, `unsupported` e `policyDenied` não são
  colapsados;
- a seleção visual usa somente uma projeção válida do
  `Scenario × Variant × Provider`; mudar o filtro nunca pode mostrar pixels de
  outra Variant como se fossem do filtro atual;
- mapa, lista e Outline oferecem caminhos equivalentes sem depender de drag;
- deep links e seleção programática revelam o card selecionado no viewport;
- target consumidor permanece em iframe/origin separados;
- grants Remote são efêmeros e consumidos uma única vez;
- comportamento responsivo deriva de políticas e tokens compartilhados.

As políticas são cobertas por `dart test packages/devex_ux_system`. CSS e DOM
responsivos são verificados separadamente no browser real; uma policy pura não
é, sozinha, evidência de layout renderizado.

## Responsabilidade e backlog de experiência

O UX System decide significado, prioridade, comportamento responsivo e
invariantes. O UI System materializa essas decisões em componentes e tokens;
features não reproduzem breakpoints, tons ou regras de seleção localmente.

O estado mobile atual é funcional e reflui sem overflow a 200%, mas ainda não é
o destino de design: a navegação ocupa altura excessiva e o Journey abre na
visualização mais densa. A evolução ratificada é uma navegação compacta e
recolhível e `Lista` como visualização inicial em telas compactas, mantendo o
mapa como alternativa explícita. Essa lacuna não é promovida a capability
concluída.
