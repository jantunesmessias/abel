# ADR-0015 — UI System e UX System próprios do DevExKit

- Status: Aceita
- Data: 2026-08-10

Nota de evolução: a separação entre UI System e UX System continua aceita. A
implementação Flutter do `devex_ui_system` descrita neste ADR é substituída pela
ADR-0016. Este documento permanece como registro do baseline executado e não
autoriza Flutter no Studio ou no UI System após o cutover Jaspr.

## Contexto

O Studio foi iniciado sobre Material 3. Isso acelerou o primeiro vertical, mas
misturou linguagem de produto, decisões de interação e implementação de um
design system externo. O DevExKit precisa suportar uma identidade própria,
densidade de ferramenta e evolução multiplataforma sem herdar mudanças de
Material ou Cupertino.

## Decisão

Criamos duas fronteiras independentes:

- `devex_ux_system`: Dart puro; contém políticas de layout, interação, motion,
  disclosure, feedback e níveis de detalhe. Não depende de Flutter.
- `devex_ui_system`: depende de Flutter `widgets`/`rendering`, do UX System e de
  uma iconografia neutra. Contém tokens e primitives visuais. Importar
  `package:flutter/material.dart` ou `package:flutter/cupertino.dart` é proibido.

O Studio migrou incrementalmente por superfícies. O estado concluído proíbe
Material/Cupertino também em `apps/devex_studio/lib`; o gate executável em
`tool/architecture_guard.dart` impede regressão. O histórico incremental explica
os commits intermediários, mas não autoriza adapters no runtime atual.

## Invariantes

1. Tokens DevEx são a única fonte de cor, tipografia, espaçamento, raio, stroke
   e motion das primitives novas.
2. UX decide o padrão; UI o renderiza; features não repetem breakpoints.
3. Estados `hover`, `pressed`, `focused`, `disabled`, `selected`, erro e
   progresso são explícitos e testáveis.
4. Toda ação possui contrato de teclado, foco visível, Semantics e alvo mínimo.
5. Redução de motion é uma política, não uma animação alternativa ad hoc.
6. O UI System não cria um catálogo de domínio paralelo: Scenario, Variant,
   Evidence e Module continuam vindo de `devex_contracts`.
7. A conclusão da migração exige zero imports Material/Cupertino no Studio e nos
   dois systems, além de testes visuais, responsivos, teclado e Semantics.

## Iconografia

O UI System expõe somente um subconjunto semântico por `DevExIcons`. A fonte é
Lucide sob licença MIT; features não importam o package de ícones diretamente.
Isso permite trocar a fonte sem contaminar o produto.

## Consequências

- O custo inicial é maior do que tematizar Material.
- Componentes complexos — menu, seleção de texto, overlay, navegação e campos —
  precisam de conformance própria antes da remoção do adapter.
- O Studio passa a ter linguagem e contratos estáveis, sem depender de defaults
  ou mudanças de Material/Cupertino.

## Estado de implementação

Em 2026-08-10, o vertical executável passou a usar `WidgetsApp.router`, tokens,
controles, tabs, overlays, estados vazios, bootstrap e Remote Session próprios.
O Studio, o UI System e o UX System possuem zero imports de Material/Cupertino.
Essa afirmação é uma fronteira de implementação coberta pelo architecture guard;
não é uma alegação de maturidade final de todos os componentes possíveis.
