# Resultados — único DevEx Studio Jaspr

Data da evidência: 2026-08-11.

Este documento substitui a claim operacional SR0–SR9 baseada no Studio Flutter.
A evidência Flutter de 2026-08-10 permanece baseline histórico no archive de
migração; não descreve o produto atual.

## Resultado arquitetural

- existe somente `apps/devex_studio`;
- o app é Jaspr 0.23.3 em modo client-side;
- `devex_ui_system` usa Jaspr/HTML/CSS e Lucide;
- `devex_ux_system` é Dart puro;
- Studio/UI não dependem de Flutter, Material, Cupertino, `dart:io`, engine ou
  runtime;
- não existe `studio.renderer`, app paralelo ou fallback Flutter;
- Flutter permanece em `devex_preview`, `devex_flutter` e consumers permitidos;
- Host continua autoridade para plan, RPC, effects, resources, CAS e Evidence;
- target consumidor continua em iframe/origin separados.

O baseline removido foi arquivado em
`.dart_tool/devex/migration/flutter-studio-ui-baseline-20260810.tar.gz`, digest
`sha256:60fdf81d9a26dd00fdaf3e185cf3ad5bca9ad457d0fe164afdd51bb430907fde`.

## Produto implementado

### Shell e Overview

- bootstrap seguro, reconnect e snapshot stale;
- navegação e rotas client-side;
- workspace, revisão, módulos, aplicações, Journeys, Scenarios e cobertura;
- states loading/empty/failure/stale;
- contribution gating derivada do `EffectiveKitManifest`.

### Journey Map e Inspector

- mapa e lista, Outline completo, deep link e seleção;
- zoom 75–150%, fit e alternativa sem drag;
- windowing do canvas em 24 Scenarios ao redor da seleção;
- thumbnails por Blob URL verificada, device frame separado do PNG;
- filtros de Variant, provider, status, freshness e fidelity;
- tabs Geral, Evidence e Módulos;
- diagnostics, digests, capture key, fingerprint e status explícitos;
- `missing`, `stale`, `failed`, `unsupported` e `policyDenied` preservados.

### AutoPreview

- confirmação explícita de dados sintéticos com `<dialog>` nativo;
- coleta, polling, cancelamento, progresso e falha parcial;
- stale→fresh e refresh do workspace;
- cinco Scenarios, sete descriptors e três Variants
  (`phone.light.en-us`, `phone.dark.en-us` e `desktop.light.en-us`) no sample;
- fidelity `structural`, sem promoção host-native.

### Capabilities condicionais

- `sessions.local` publica `studio.target`: form de LaunchProfile/origin,
  start/reset/stop, readiness HTTP e `TargetFrame` sandboxed;
- o sample serve um build Flutter web release pré-compilado por servidor Dart
  confinado, com SPA fallback, headers e `frame-ancestors` exato;
- `gateway.interceptor` publica `studio.gateway`: presets fornecidos pelo Host,
  start/status/traffic/reset/stop usando owner Session e digest de
  `CompiledGatewayPlan` no CAS sem entrada manual de IDs/digests;
- Review renderiza `ReviewGuide`/steps do catálogo quando existem;
- Remote consome grant efêmero exatamente uma vez, autentica WebSocket e suporta
  web iframe, screenshots read-only e H.264/WebCodecs com controle concedido;
- Hosted mostra apenas o estado negociado; não inventa control plane local.

Target/Gateway/Remote/Hosted não aparecem no profile `journey-preview`. Modules
desabilitados continuam com zero rota de navegação, RPC registrado, processo,
porta, probe ou acesso a device/network.

## Segurança implementada

- bootstrap exato `/devex/bootstrap.json`, Origin allowlisted e token efêmero;
- workspace/PNG por handle com purpose, origin, media type, tamanho, expiry e
  digest;
- Blob URL local revogada no dispose;
- CSP release `script-src 'self'`; hot reload usa o hash exato do loader DWDS;
- iframes `sandbox="allow-scripts allow-same-origin allow-forms"` e
  `no-referrer`;
- postMessage valida origin, source, session, nonce e sequence monotônica;
- Remote grant é one-time, expirável e escolhe exatamente um transporte;
- subprocessos e listeners continuam supervisionados pelo Host.

## Evidência executada

### Análise e components

- `dart analyze apps/devex_studio packages/devex_ui_system
  packages/devex_ux_system packages/devex_runtime`: Pass;
- architecture guard: Pass;
- component/pure tests do Studio, UI e UX: Pass;
- policy de windowing com 10.000 itens e máximo 24: Pass;
- Host Session/Gateway lifecycle e composition tests: Pass;
- `jaspr build`: Pass.

### Browser real

`tool/studio_jaspr_cdp_probe.dart` com Google Chrome passou após o cutover e
após a extensão Remote:

| Métrica | Resultado observado |
|---|---:|
| DOM Flutter | 0 |
| focusables sem nome | 0 / 29 |
| menor alvo interativo | 48 px |
| Tab stops distintos | 8 |
| texto 200% em 360 px | sem overflow do documento |
| reduced motion | 0,00001 s |
| zoom samples | 20 |
| zoom p95 | 33,4 ms |
| DOMContentLoaded / load / FCP release | 113,5 / 114,7 / 136 ms |
| bytes transferidos release | 492.608 |
| logs severos | 0 |
| resources PNG | 7 |

O vertical oficial atual cobriu cinco Scenarios, expandiu sete descriptors em
três Variants, validou sete PNGs, confirmou stale→fresh, o profile sem provider
e limpeza sem resíduos. A auditoria visual de 2026-08-11 foi preservada em
`.artifacts/ux-audit/2026-08-11/final` sem convertê-la em asset de produção.

O showcase adicional comprovou Target direto e via Gateway, TrafficEvents,
CORS de origin exato, unmount do iframe antes do stop e cleanup em cascata. Seu
launcher supervisiona API, Host e Studio e reinicia o stack com backoff após
falha observada, preservando o browser.

### Distribuição

O builder foi migrado de `flutter build web` para `jaspr build`. Profiles
headless continuam sem `studio/`; profiles com Studio registram assets Jaspr em
`distribution.json`. Em 2026-08-11, `verify_modular_distribution.sh` passou com
dois bundles `journey-preview` byte-idênticos e `gateway-lab-headless` sem
Studio. `verify_v03_distribution.sh` também passou com dois bundles `full-local`
de mesmo digest, verificação, instalação, atualização, rollback e consumer
externo.

## Comparação Atlas

A comparação visual atual foi feita no mesmo Google Chrome e viewport com o
Atlas local. O DevExKit apresenta vantagem verificável para o domínio próprio:
fidelity/freshness/provider por Scenario, AutoPreview ponta a ponta, module
gating e diagnóstico do Host. Atlas permanece referência útil de densidade e
hierarquia. Não há claim de superioridade universal ou de feature parity fora
dos fluxos comparados.

## Lacunas explicitamente não promovidas

- o Target real comprovado pertence ao `sample_flutter`; outros consumers ainda
  precisam fornecer LaunchProfile e binding próprios;
- Remote/Hosted reais dependem de control plane e grants externos;
- KVM/device farm e containment de rede não são provados pela matriz local;
- Review precisa de `ReviewGuide` real no catálogo do consumer;
- acessibilidade observada não equivale a auditoria WCAG completa;
- no layout mobile, a navegação ainda ocupa altura excessiva e o Journey deve
  evoluir para Lista-first com mapa secundário;
- a coleta isolada AutoPreview termina sem órfãos, porém uma coleta de um
  Scenario foi medida em 83,68 s; otimização por worker aquecido ou lote só pode
  avançar preservando a atual semântica de isolamento de falha;
- build local não é certificação de infraestrutura de produção.
