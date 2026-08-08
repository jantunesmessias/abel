# Contribuindo no Abel Studio Jaspr

Status: guia pós-cutover, 2026-08-11.

## Estrutura

```text
apps/studio/
  lib/main.client.dart
  lib/src/jaspr/             app, shell e capability pages
  lib/src/controllers/       estado/commands Dart puros
  lib/src/host/              bootstrap, RPC e resource leases
  lib/src/journey_map/       projections de presentation
  lib/src/target_frame/      iframe/postMessage condicional web
  lib/src/remote/            grant, machine, transport e surface web
  web/index.html
  web/styles/                tokens/reset/type/layout/components/a11y
libs/studio_ui/    components Jaspr reutilizáveis
libs/interaction_model/    policies Dart puras
```

O archive Flutter em `.dart_tool/experience_platform/migration` é recuperação histórica, não
fonte para copiar widgets de volta.

## Regras

- não importar Flutter, Material, Cupertino, `dart:io`, `experience_engine` ou
  `execution_runtime` no Studio/UI;
- não criar app ou renderer alternativo;
- regras de domínio ficam em contracts/engine/Host;
- controllers são Dart puros; APIs browser usam conditional exports;
- usar HTML semântico e componentes do UI System;
- usar Lucide via `StudioIconName`, sem SVG artesanal;
- iframe requer sandbox, no-referrer, origin separado e validação de mensagem;
- resources Host viram Blob URL somente após type/size/expiry/digest;
- ações/rotas dependem de contribution efetiva;
- states disabled/loading/empty/stale/failure/partial são explícitos.

## Fluxo de mudança

1. localize component/policy existente;
2. adicione ou ajuste policy pura quando a decisão for reutilizável;
3. implemente component Jaspr e CSS por tokens;
4. adicione component/pure test;
5. para browser API, mantenha stub VM fail-closed;
6. rode análise, guard, build e Chrome gate;
7. atualize conformance, threat model e matriz se a surface mudar.

```bash
dart format apps/studio libs/studio_ui libs/interaction_model
dart analyze apps/studio libs/studio_ui libs/interaction_model
dart run tools/gates/architecture_guard.dart
dart test apps/studio/test
dart test libs/studio_ui
dart test libs/interaction_model
cd apps/studio && jaspr build
```

Pare `jaspr serve` antes do build release no mesmo checkout.

## Nova capability

Uma nova superfície exige, na mesma mudança:

1. ModuleDescriptor/surfaces/resources/effects;
2. ModuleContribution única no Host lifecycle;
3. getter em `StudioComposition`;
4. rota e navegação capability-gated;
5. Host Client tipado sem duplicar regra de domínio;
6. negative test com Module disabled;
7. profile/distribution ownership atualizado;
8. security e cleanup tests proporcionais ao efeito.

ReviewGuide não é capability nova: é dado canônico do catálogo. Target pertence
a Sessions; Gateway pertence ao Module Gateway; Remote/Hosted preservam seus
boundaries externos.

## Validação visual

Use Google Chrome, o browser escolhido para a conformance. Screenshot isolada
não basta: compare referência Atlas e prototype no mesmo input/viewport, corrija
layout e reexecute semantics/keyboard/reflow. Não use Playwright sem decisão
explícita do projeto.
