# Plano de reconstrução do único DevEx Studio

Status em 2026-08-11: cutover Jaspr implementado; gates finais de distribuição e
documentação em fechamento.

Este plano substitui o plano SR0–SR9 orientado ao renderer Flutter. O objetivo é
um Kit modular no qual configuração seleciona capabilities, não tecnologia de
renderização do Studio.

## Invariantes

1. um único `apps/devex_studio`, client-side Jaspr;
2. nenhum Flutter/Material/Cupertino no Studio ou UI System;
3. UX System Dart puro;
4. Host mantém contratos, effects, CAS, resources e supervision;
5. target consumidor permanece em iframe/origin separados;
6. AutoPreview continua adapter Flutter estrutural;
7. module desabilitado produz zero superfície e zero efeito;
8. intenção, mecanismo, evidência e lacuna são documentados separadamente.

## Fases e estado

| Fase | Entrega | Estado |
|---|---|---|
| J0 | ADR-0016, baseline, archive, Atlas e threat model | concluída |
| J1 | controllers/contracts Dart puros e Host Client | concluída |
| J2 | spike client-side, router, bootstrap, WebSocket, CORS e static build | concluída |
| J3 | UI System Jaspr + UX System puro | concluída |
| J4 | pubspec/entrypoint Jaspr e remoção Flutter | concluída |
| J5 | Shell, reconnect, Overview e capability gating | concluída |
| J6 | Journey Map, Outline, windowing, Inspector e responsive | concluída |
| J7 | AutoPreview dialog/collect/cancel/stale→fresh/artifacts | concluída |
| J8 | Target, Gateway, Review, Remote e Hosted condicionais | implementada; integrações externas permanecem Partial |
| J9 | supervisor, distribuição Jaspr, docs e gates finais | em fechamento |

## Composition atual

```text
ResolvedKitPlan
  -> HostModuleKernel
     -> EffectiveKitManifest.studioContributions
        -> Jaspr Router + navegação

studio.shell           bootstrap, shell, Overview
studio.journey-map     Journey, Inspector, Evidence
studio.target          Session + target iframe
studio.gateway         Gateway sidecar controls
studio.remote-session  viewer com grant efêmero
studio.hosted          estado de colaboração
Review                 ReviewGuide do CatalogManifest
```

Review não cria um bounded context/module paralelo: é conteúdo canônico do
catálogo. `studio.target` pertence a `sessions.local`; `studio.gateway` pertence
a `gateway.interceptor`.

## Gates de saída

- `dart format --set-exit-if-changed`;
- `flutter analyze --fatal-infos --fatal-warnings` no workspace misto;
- architecture guard;
- suites contracts/engine/runtime/UI/UX/Studio e adapters Flutter;
- `jaspr build` duas vezes e comparação de manifest/distribuição;
- `verify_modular_distribution.sh` e `verify_v03_distribution.sh`;
- `verify_studio_vertical.sh` e `benchmark_journey_map.sh`;
- Google Chrome: semantics, keyboard, 200%, reduced motion, AX, performance,
  dialog/focus, resources e severe logs;
- Atlas e prototype na mesma comparação visual;
- Host/Studio finais abertos para validação humana.

## Critérios por integração externa

Uma surface pode ser `Partial` sem bloquear o cutover se o ambiente local não
possui o sistema externo, desde que:

- route/navigation sejam capability-gated;
- credenciais e mensagens falhem fechadas;
- protocolo/state machine/build/component tests passem;
- a lacuna não seja relatada como ponta a ponta.

Target real, Remote hosted, Hosted collaboration, KVM e ReviewGuide de consumer
seguem essa regra. AutoPreview e Journey Map, por outro lado, possuem ambiente
local e devem passar ponta a ponta.

## Limitações preservadas

- `flutter-test` é fidelity `structural`, nunca host-native;
- Widget Previewer é interativo, não exportador de PNG;
- Flutter 3.44.8 requer `--legacy-preview-detection`;
- containment de rede/memória depende do sandbox do host;
- “melhor que Atlas”, “acessível” e “production-ready” exigem evidência além
  deste plano e não são claims automáticas.
