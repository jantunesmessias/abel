# Migração do único DevEx Studio para Jaspr

Status: cutover executado em 2026-08-11; distribuição/gates finais registrados
em `devex-studio-reconstruction-results.md`. Decisão: ADR-0016. Este documento
preserva o baseline e o diário histórico; não descreve a UI atual como Flutter.

## 1. Estado inicial preservado

Baseline registrado em 2026-08-10:

- branch `main`, HEAD `6ff25a977467d45f0bdce91a6ef635621742d25f`;
- branch local estava `ahead 1, behind 1` em relação a `origin/main`;
- `ARCHITECTURE.md` modificado e o restante do produto majoritariamente não
  rastreado; nada foi limpo, resetado ou atribuído ao rollout;
- Host ativo em `127.0.0.1:39001` e Studio Flutter de desenvolvimento em
  `127.0.0.1:39002`;
- health do Host respondeu `200` com `status=ready` e protocol version 1;
- bootstrap respondeu JSON válido, `no-store`, CORS exato para a origem do
  Studio e token somente no body;
- Chrome mostrou `Host conectado`, Journey Map, duas Scenarios, AutoPreview
  estrutural e Inspector;
- `./tool/check.sh` passou integralmente antes do início da migração.

Capturas válidas no mesmo viewport de 1948 × 1108:

| Produto/estado | Arquivo de trabalho | SHA-256 |
|---|---|---|
| Atlas, Journey board | `/tmp/devex-ux-audit-round-2/04-atlas.png` | `311b47ee14236c0cfb047f11b04a478a6cb91327e3e7c2208c7719b2a9217914` |
| DevExKit, Journey conectado | `/tmp/devex-host-recovery/host-session-current.png` | `4012e00137ab5693fed5de567d9e728c13c9b95935bdcea509d2a001bb888c35` |

Essas capturas são baseline local, não golden e não prova da futura UI Jaspr.
Elas foram inspecionadas e rejeitariam estados vazios, loading ou janela
incorreta.

## 2. Matriz Atlas × baseline DevExKit

Status visual atual, antes do cutover:

| Critério | Atlas | DevExKit Flutter baseline | Direção Jaspr | Status |
|---|---|---|---|---|
| Entrada da tarefa | board denso e fluxo ativo imediatamente visíveis | busca e árvore de aplicação claras, mas Journey exige contexto prévio | Overview com ação prioritária e continuidade para Journey | Partial |
| Arquitetura da informação | explorer, mapa, lanes e detalhe coexistem | explorer, mapa e inspector coexistem com menos densidade | preservar três painéis com disclosure responsivo | Partial |
| Densidade útil | 63 stories e contagens visíveis | dois Scenarios com grande área ociosa | LOD, outline e métricas sem preencher espaço artificialmente | Partial |
| Journey/Scenario | lanes e stories são rápidos de escanear | identidade e transições são explícitas | manter identidade, numerar ordem e tornar gaps acionáveis | Partial |
| Cobertura visual | missing captures aparece como total global | `1/2 com imagem` e placeholder por Scenario | filtros e callout levam diretamente à coleta | Confirmed no baseline, Unverified em Jaspr |
| Evidence | não mostra provenance equivalente na captura observada | provider, fidelity, freshness e Inspector explícitos | preservar vantagem e expor digests sob disclosure | Confirmed no baseline, Unverified em Jaspr |
| Navegação do mapa | toolbar rica e modos mouse/trackpad | pan/zoom/fit/reset e outline separados | DOM/SVG, teclado e alternativa a drag | Partial |
| Filtros | botão e busca, com contagens por lanes | filtros presentes, estado ainda pouco resumido | chips removíveis, URL compartilhável sem segredos | Partial |
| Inspector | área direita vazia até seleção, lanes ocupam painel central | Scenario selecionado abre abas e status | manter ação/contexto persistente em telas largas, sheet em estreitas | Partial |
| Falha/recovery | não observada nesta captura | reconnect foi exercitado; sessão cliente recuperou com Host ainda ready | stale cache, backoff e token renovado com estados explícitos | Partial |
| Web semântico | implementação do Atlas não é claim deste repo | Semantics Flutter adaptada | landmarks/HTML nativos e AX tree browser | Unverified |
| Performance | não medida nesta rodada | benchmark Flutter 1k nodes aprovado | novos budgets DOM/layout/memória necessários | Unverified |

Não existe claim de “melhor que Atlas” nesta fase. O DevExKit já possui uma
vantagem funcional observável em provenance de Evidence; o Atlas mantém
vantagem em densidade, visão geral e velocidade de scan no board.

## 3. Métricas e critérios

Os budgets Jaspr iniciais serão medidos em Chromium release, após o spike:

| Métrica | Budget inicial | Estado |
|---|---:|---|
| bootstrap até shell útil, local | ≤ 1.500 ms | Unverified |
| interação pan/zoom p95 | ≤ 16,7 ms | Unverified |
| interação pan/zoom p99 | ≤ 33,3 ms | Unverified |
| route/deep-link após warm load p95 | ≤ 100 ms | Unverified |
| reconnect visível após Host retornar | ≤ 2 s + backoff documentado | Unverified |
| mapa de 1.000 nodes | sem long task > 200 ms após estabilização | Unverified |
| texto 200%/360 px | zero overflow horizontal global | Unverified |
| contraste | WCAG 2.2 AA para texto/controles essenciais | Unverified |

Budgets podem ser ajustados somente com medida, justificativa e atualização do
gate; não por conveniência de implementação.

Resultado após o cutover, preservando a tabela acima como hipótese inicial:

| Métrica | Resultado 2026-08-11 | Classificação |
|---|---:|---|
| load event / FCP release | 170,1 / 212 ms | Confirmed local |
| interação de zoom, 20 amostras | p95 33,5 ms | Confirmed local |
| windowing de 10.000 Scenarios | 24 nodes no canvas | Confirmed por policy test |
| texto 200% em 360 px | sem overflow global | Confirmed no Chrome |
| reconnect e snapshot stale | controller + spike browser | Confirmed funcional; tempo <= 2 s não promovido |
| contraste WCAG completo | não auditado integralmente | Partial |

O probe de zoom espera dois `requestAnimationFrame`: um para aplicar o estado e
outro para observar o frame pintado. Por isso, o budget inicial de 16,7 ms, que
representava um único frame, não descreve a medida end-to-end. O gate ratificado
é p95 menor que 100 ms; o resultado de 33,5 ms não usa esse ajuste para esconder
uma regressão e permanece registrado explicitamente.

## 4. Fases e gates

### Fase J0 — Constituição e baseline

- ADR-0016;
- este baseline e matriz;
- threat model Jaspr;
- inventário de contracts/fluxos;
- captura de ponto de recuperação quando autorizada.

Gate: documentos não confundem baseline Flutter com evidência Jaspr e o
worktree do usuário permanece intacto.

### Fase J1 — Responsabilidades em Dart

- extrair estado imutável e commands de classes Flutter;
- estabilizar Host Client tipado e projections;
- caracterizar bootstrap/RPC/events/resources com fixtures reais;
- bloquear duplicação de regras do domínio.

Gate: testes `dart test` cobrem modelos/controllers/transporte sem Flutter.

Estado em 2026-08-10: `Partial`. `CatalogController`,
`StudioFiltersController`, `StudioWorkspaceController`, seus estados e as
projections de Journey/Evidence já são Dart puro. O guard bloqueia Flutter,
Riverpod, Jaspr, Engine e Runtime nessas fronteiras. Oito testes Dart cobrem
refresh, concorrência, stale, filtros, eventos e reconnect. Host Client e
bootstrap transport já eram Dart/browser, mas ainda falta remover seus adapters
Flutter no cutover.

### Fase J2 — Spike descartável

Local: `.dart_tool/devex/spikes/jaspr_studio/`.

Provar Pub Workspace, `mode: client`, routing, bootstrap, WebSocket, Origin,
CORS, reconnect, handle, iframe isolado e `jaspr build`. O spike não vira app,
Module, Provider nem artifact de distribuição.

Gate: relatório executado com `Confirmed/Partial/Unverified/Failed`; qualquer
falha de fronteira retorna para J1 antes do cutover.

Estado em 2026-08-10: `Partial`, com relatório executado em
`docs/architecture/jaspr-studio-spike-results.md`. O vertical real pode começar;
reprodutibilidade pós-workspace e negativo de source/origin continuam gates de
J2 antes da conclusão.

### Fase J3 — UI/UX System

- preservar `devex_ux_system` Dart puro;
- reimplementar `devex_ui_system` com Jaspr/HTML/CSS;
- tokens, temas, primitives, controls, overlays e patterns;
- testes de componente, foco, teclado, contraste, reflow e reduced motion.

Gate: zero Flutter/Material/Cupertino/framework visual e todos os estados dos
componentes mínimos demonstrados.

### Fase J4 — Cutover do app e shell

- trocar `apps/devex_studio/pubspec.yaml` e entrypoint;
- migrar bootstrap, Host Client, router, shell, Overview e capability gating;
- manter nome, rotas públicas e identidade;
- ajustar `devex dev` para hot reload/readiness Jaspr.

Gate: Host real abre o único Studio Jaspr, reconecta e não materializa token.
Somente então remover a implementação Flutter da árvore atual.

### Fase J5 — Journey Map, Inspector e AutoPreview

- DOM/SVG/virtualização/outline;
- pan, zoom, fit, reset, LOD, seleção e teclado;
- abas Geral, Variants, Evidence, Código e Módulos;
- filtros por status/freshness/fidelity;
- coleta, cancelamento, falha parcial e stale → fresh.

Gate: fluxos canônicos 4–19 executados no browser real com Host e PNGs reais.

### Fase J6 — Capabilities, distribuição e limpeza

- journey-android, gateway-lab, full-local, remote, Review e hosted;
- build estático, supervisor, startup/shutdown e rollback;
- bundle reproduzível e matriz headless;
- remover Flutter residual, assets e testes do Studio;
- atualizar guards e toda a documentação pública.

Gate: suites do workspace, security negatives, duas builds, audit de secrets,
browser/a11y/performance e comparação final com Atlas.

## 5. Registro de ciclos

| Ciclo | Melhoria | Evidência | Lacuna | Próximo problema |
|---|---|---|---|---|
| J0.1 | baseline e decisão Jaspr formalizados | Host/Studio atuais, screenshots e full check Flutter | nenhuma evidência Jaspr executada | spike client-side |
| J1.1 | catálogo, filtros, estado de workspace e reconnect extraídos para Dart puro | `dart analyze`, 8 testes Dart, guard arquitetural e 16 regressões Flutter | adapters Riverpod ainda existem no baseline | consumir os controllers no Jaspr |
| J2.1 | SPA Jaspr client em Pub Workspace | analyze/build e deep link direto | app ainda descartável | UI System real |
| J2.2 | protocolo real no browser | bootstrap, initialize, RPC, handle e digest com Host real | protocolo mínimo duplicado no spike | reutilizar Host Client canônico |
| J2.3 | recovery sem perder contexto | screenshots stale e recovered na mesma página | backoff final não medido | controller canônico Jaspr |
| J2.4 | iframe com envelope adversarial | sequence 100 inválida ignorada; sequence 1 aceita | falta source/origin realmente diferente | negativo cross-origin final |
| J2.5 | inspeção do build | token/storage/maps ausentes no allowlist e duas builds pré-workspace idênticas | output bruto contém assets não publicados | empacotador por allowlist |
| J3/J4 | UI/UX System próprios e único app Jaspr | guard, analyze, components e Chrome sem DOM Flutter | auditoria WCAG completa segue Partial | Journey/Inspector |
| J5 | Journey/Inspector/AutoPreview e DOM bounded | duas Variants/PNGs, stale→fresh, no-provider, 10k→24 | target consumer-specific | capabilities |
| J6 | Target/Gateway/Remote/Hosted condicionais e distribuição | components, vertical, bundles modular/full reproduzíveis e rollback | endpoints externos seguem Partial | validação do usuário |

Novas linhas são adicionadas somente após execução observável.

### Atualização operacional pós-cutover — 2026-08-11

As linhas J5/J6 acima preservam a evidência histórica que promoveu o cutover.
O vertical corrente expandiu o sample para cinco Scenarios, sete descriptors e
três Variants/7 PNGs. O Target consumer-specific também foi comprovado com
build Flutter web release pré-compilado, e o Gateway com seleção guiada de
preset, target pelo origin do sidecar e TrafficEvents. Esses resultados não
reescrevem o gate histórico; a evidência atual está em
`devex-studio-reconstruction-results.md` e `studio-conformance-v1.md`.
