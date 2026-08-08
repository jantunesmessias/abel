# Abel examples

Este diretório é o consumer de referência do Abel. Ele é genérico o
suficiente para não impor um domínio real, mas completo o suficiente para
exercitar as fronteiras do Kit sobre uma aplicação verdadeira.

```text
sample_flutter (Delivery Lab)
        |
        | HTTP direto ou via Gateway
        v
sample_api (Shelf, estado em memória)
        ^
        |
Gateway: hybrid | offline | unavailable | failure
        ^
        |
Workspace Host <-> Jaspr Studio
```

## Início rápido

Na raiz do repositório:

```bash
dart run examples/tool/showcase.dart
```

Portas deliberadamente fixas tornam o showcase manual reproduzível. Runs do
Scenario Lab usam um segundo LaunchProfile com porta efêmera Host-owned para
não disputar a Session interativa:

| Processo | Origem |
|---|---|
| Sample API | `http://127.0.0.1:8181` |
| Workspace Host | `http://127.0.0.1:7367` |
| Abel Studio | `http://127.0.0.1:7368` |
| Flutter target interativo | `http://127.0.0.1:8080` |
| Flutter target do Scenario Lab | loopback efêmero, descoberto por readiness |

O launcher falha antes de iniciar se uma porta estiver ocupada, cria
`sample_flutter/workspace.local.yaml` a partir do template loopback somente quando
ele não existe, compila os quatro planos do Gateway no CAS e prepara um build web
release do Target quando os inputs mudaram. Um watchdog supervisiona API,
Host/Studio e reinicia o stack com backoff limitado ao detectar saída do child
ou três health checks consecutivos falhos; o browser permanece aberto. No
`Ctrl+C`, os filhos são encerrados em ordem.

Opções:

```bash
dart run examples/tool/showcase.dart --check
dart run examples/tool/showcase.dart --build-studio
dart run examples/tool/showcase.dart --build-target
dart run examples/tool/showcase.dart --no-open
```

Com os serviços ativos, o smoke real inicia e encerra um Target, cria o Gateway
hybrid, lê um endpoint upstream e uma fixture pelo mesmo data plane e verifica
os TrafficEvents, sem imprimir o token do Host:

```bash
dart run examples/tool/showcase_smoke.dart
```

## O que o exemplo demonstra

O `workspace.yaml` usa `full-local`; `showcase.dart --check` resolve o plano pelas
APIs públicas e comprova que todos os Modules empacotados estão habilitados.
Habilitado não significa pronto ou certificado:

| Grupo | Demonstração local |
|---|---|
| Catalog, Board, Journey Map e Review | 8 Scenarios catalogados; 1 Board, 2 Projections sobre os mesmos 5 Scenarios, 10 NodeInstances, 5 Transitions/EdgeInstances, 2 layouts curados, 4 execution bindings e 1 ReviewGuide |
| Scenario Lab e Quality | 1 plano `dashboard-ready`, Target/Gateway/run reais, controls e relay tipados, captura/App Adapter, baseline/candidate/diff, freshness/currentness, falha parcial e decisão humana append-only separada da aceitação automatizada |
| Motion e Context Builder | 1 sequência temporal com 2 transitions em full/reduced/none, equivalente estático completo e export Host-side por seleção semântica, com 5 budgets independentes e omissões tipadas |
| AutoPreview | matriz `ready/loading/empty/stale/unavailable/failure`, ready responsivo em três Variants e Semantics por estado; fidelidade `structural` |
| Sessions + App Adapter | LaunchProfiles web de Session e Lab, iframe isolado e captura por `RepaintBoundary` |
| Gateway | passthrough para API real, fixtures offline, `503 unavailable` recuperável e `500 failure` não recuperável |
| Evidence, source e release | comandos públicos usam o mesmo catálogo/CAS do consumer |
| Android | Module ativo; execução exige SDK, AVD e autorização locais |
| Plugins, MCP, hosted e remote | superfícies ativas; operações externas ainda exigem plugin, credencial, control plane ou worker reais |

O `showcase.dart --check` continua deliberadamente estático. Ele preserva o
profile sem EvidenceProvider sem
autoridade de decisão e valida a instrução e o critério exatos do ReviewGuide.
Ele não inicia o Host, não publica um `EffectiveKitManifest`, não comprova os
RPCs de Quality e não executa aprovação ou rejeição humana no Studio.

O vertical executável separado fecha esse limite em Linux com Chrome/Chromium:

```bash
./tools/verify/verify_scenario_lab_vertical.sh
```

O gate constrói Studio/Target release, importa a baseline consumer-owned,
executa Lab → Run → Quality no browser, passa o Target pelo Gateway, verifica
capture/diff/freshness, aprovação seguida de rejeição superseding, reinício,
cancelamento e uma recollection que falha explicitamente por comparação. Ele
verifica dois PNGs por digest e restaura fontes, builds, state, processos e
ports. O CI reutiliza builds anteriores com
`SCENARIO_LAB_SKIP_BUILD=1`, sem pular o runtime.

Essa evidência é local e cobre somente as rotas exercitadas. Os checks de
teclado, foco/modal, reflow a 200%, reduced motion, overflow e logs severos não
constituem auditoria WCAG e não certificam produção, hosted, device farm,
dispositivo físico ou acessibilidade do app consumidor.

Motion e Context Builder têm um vertical read-only próprio:

```bash
./tools/verify/verify_motion_context_vertical.sh
```

Ele exercita full/reduced/none e o equivalente estático no Studio real, exporta
o mesmo contexto duas vezes após reload e exige digest idêntico, depois omite
Evidence e exige uma omissão declarada. O gate usa uma cópia privada do content
root, valida screenshot e logs e remove processos, listeners e estado temporário.

O entrypoint `sample_flutter/lib/main.dart` não importa Abel. O tooling vive
em `tool/target_main.dart`, previews reutilizam `createSampleApp`, e a mesma
classe `HttpShowcaseApi` é usada no app normal e no target controlado.

O mesmo consumer também fecha o transporte MCP local em uma cópia privada:

```bash
./tools/verify/verify_mcp_experience_vertical.sh
```

O gate sobe `workspace mcp serve` por stdio, lê os seis resources tipados, exercita
queries de catálogo/grafo/contexto/Evidence, executa teste e importa uma captura
PNG com capability curta, e percorre draft, review, finding, concept e aceitação
automatizada. O fluxo prova revogação e consumo na primeira tentativa; a
aceitação permanece separada de decisão humana e não torna o review promovível.
Ele não abre listener de rede, não captura um device ativo e não trata
`clientInfo` como autenticação remota.

## Target e Gateway Lab

O fluxo do Studio é guiado e não pede Session ID ou artifact digest:

1. abra **Target**, mantenha `sample-web` e `http://127.0.0.1:8080`, e inicie a
   Session;
2. abra **Gateway Lab**; a Session proprietária é derivada do Target e os
   presets compilados são fornecidos pelo Host;
3. escolha `showcase-hybrid`, `showcase-offline`, `showcase-unavailable` ou
   `showcase-failure` e inicie o Gateway;
4. use **Abrir Target com Gateway** para recarregar a aplicação com a
   `dataOrigin` exata do sidecar;
5. atualize o tráfego para inspecionar método, path, decisão e status;
6. pare o Gateway ou pare o Target; ownership da Session remove o sidecar em
   cascata e o Studio desmonta o iframe antes do teardown.

O Target não usa `flutter run`/DDC no caminho interativo. O launcher compila
`tool/target_main.dart` em release e o LaunchProfile inicia um servidor Dart
consumer-owned confinado ao `build/web`, com health endpoint, SPA fallback,
GET/HEAD, `no-store`, `nosniff` e CSP `frame-ancestors` contendo apenas a origin
do Studio. Quando o Gateway cria uma origin aleatória, o Host injeta essa origin
no Target e o data plane responde CORS exato, sem wildcard.

Presets:

- `showcase-hybrid`: `/v1/dashboard` e mutações passam para `sample_api`; a
  configuração de runtime vem de fixture;
- `showcase-offline`: dashboard e mutação são respondidos somente por fixtures;
- `showcase-unavailable`: `/v1/dashboard` responde `503` recuperável;
- `showcase-failure`: `/v1/dashboard` responde `500` não recuperável.

URLs concretas existem somente no `workspace.local.yaml` ignorado. O catálogo usa
`UpstreamProfileId: showcase-api`; loopback é permitido explicitamente apenas
para este ambiente de desenvolvimento.

## Evidência e validação

No diretório `examples/sample_flutter`:

```bash
dart run ../../apps/workspace_cli/bin/workspace.dart --json validate
dart run ../../apps/workspace_cli/bin/workspace.dart --json modules list
dart run ../../apps/workspace_cli/bin/workspace.dart --json evidence collect-previews \
  --application sample \
  --synthetic-data-confirmed
```

AutoPreview continua sendo evidência `structural`; App Adapter e Android são
providers independentes. Hosted/remote ativos sem infraestrutura não recebem
claims artificiais de readiness.

Detalhes dos componentes:

- [`sample_flutter/README.md`](sample_flutter/README.md)
- [`sample_api/README.md`](sample_api/README.md)
