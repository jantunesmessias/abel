# Plano de execução — plataforma de experiência agnóstica

Status: concluído no corte portátil em 2026-08-18. Este documento é um rastreador de execução
subordinado ao [`ARCHITECTURE.md`](../../ARCHITECTURE.md); ele não redefine
contratos, decisões ou claims. Quando houver divergência, a arquitetura, a ADR
aplicável, os schemas e a conformance executável prevalecem.

## Resultado terminal

Uma distribuição externa deve conseguir compor, exclusivamente por APIs
públicas do Abel, um catálogo espacial de experiências, execução real,
Evidence, revisão, autoria, automação e distribuição. O núcleo não conhece o
domínio, os paths, a marca ou a infraestrutura de qualquer consumidor.

O consumer de referência em `examples/` é a prova executável dessa direção:

```text
examples (domínio e dados sintéticos)
  -> APIs públicas do Abel
  -> Host autoritativo
  -> único Studio Jaspr

Abel -/-> examples ou qualquer consumer externo
```

## Estados da matriz

- `Confirmed`: implementação e evidência executada existem no escopo indicado;
- `Partial`: existe uma primitiva real, mas o fluxo terminal não está provado;
- `Open`: o contrato ou o vertical ainda não existe;
- `External gate`: depende legitimamente de infraestrutura fora da matriz
  portátil e permanece sem promoção implícita.

## Matriz requisito -> estado -> mudança -> prova

| ID | Requisito | Estado atual | Lacuna / mudança necessária | Prova de saída | Estado |
|---|---|---|---|---|---|
| EP-01 | Núcleo independente de distribuição e consumer | `DistributionDescriptor`, `ConsumerLayout`, Modules e Providers existem | Remover hardcodes restantes do builder; provar composição consumer-owned fora do workspace | guard de dependências + consumer externo + dois bundles branded reproduzíveis | Partial |
| EP-02 | Workspace e múltiplas Applications | `CatalogManifest` v1 possui ambos | Exercitar múltiplas Applications no reference consumer e nas lenses | schema/round-trip + Host/Studio/browser | Partial |
| EP-03 | Journey/Scenario e grafo não linear tipado | Journey, Scenario e Transition existem | Classificar transitions e validar pertença à Journey/Application | corpus positivo/negativo + grafo ramificado real | Partial |
| EP-04 | Boards e múltiplas projections | `ExperienceTopologyManifest` v1, compiler, Host e Studio publicam Board e duas projections | Ampliar o corpus para history/comparison/changeset nos cortes correspondentes | schema/digest + Journey e Inventory sobre o mesmo catálogo no Chrome | Confirmed |
| EP-05 | Node instance separado de Scenario | 10 NodeInstances independentes materializam 5 Scenarios nas duas projections | Exercitar repetição adicional no corpus de escala | referências cruzadas + browser com IDs de occurrence distintos | Confirmed |
| EP-06 | Layout independente por projection | `ProjectionLayoutManifest` v1 possui digest e geometria separados da topologia | A edição/persistência autoral pertence ao autoria e review | corpus prova layout próprio; browser valida digest e geometria CSP-safe | Confirmed |
| EP-07 | Groups, lanes, annotations e camera | Contratos fechados e dois layouts curados contêm 3 groups, 5 lanes, 2 annotations e cameras | Autoria dessas entidades pertence ao autoria e review | round-trip, negativos geométricos e viewport real | Confirmed |
| EP-08 | Roles/lifecycle/taxonomia | `ComparisonRole`, `ScenarioLifecycle` e registries de facets estão tipados e validados | Exercitar roles e lifecycles não atuais em projections history/comparison do reference consumer | contracts negativos + Inventory com 8/8 facets no browser | Partial |
| EP-09 | Source/component/fixture/render/frame/variants | Source refs e Variants existem em contratos separados | Referências tipadas e composição sem duplicar identidade | impact seletivo + render source explícito | Partial |
| EP-10 | Controls, scripts, critérios e Evidence requerida | Manifest/compilers, Host content-set atômico, planner/executor, relay App Adapter, resultados e UI Lab/Quality executam o plano catalog-bound | Cobertura de escala e extensões autorais seguem nos cortes próprios | contracts/engine/runtime/Studio + vertical Chrome success/cancel/failure explícita | Confirmed |
| EP-11 | Artifacts, proveniência e supplemental evidence | Evidence/CAS/fingerprint, baseline suplementar pinada, candidate/diff e review set preservam digests e proveniência | Providers externos continuam fora da matriz local | gate verifica CAS, handles, artifact/provenance digests, restart e freshness | Confirmed |
| EP-12 | Journey espacial | Journey autoral ramificada usa topologia/layout Host-authoritative, outline e windowing | Pan/zoom em corpus grande será revalidado no escala e auditoria terminal | Chrome: deep link, teclado, 5 edges renderizadas, branch/merge, reflow e CSP | Confirmed |
| EP-13 | Inventory | Lens canônica de 8 Scenarios e projection espacial de 5 occurrences usam catálogo/facets/topologia comuns | Busca de escala permanece no escala e auditoria terminal | Chrome Journey ↔ Inventory, URL/filter reset, 11 eixos e perfis com/sem provider | Confirmed |
| EP-14 | Scenario Lab | Scenario, Variant, controls, script, Target, Gateway e resultado terminal estão integrados no Studio real | Escala e outros tipos de control/script seguem escala e auditoria terminal | Chrome release com um iframe vivo, relay 6/6, Gateway real, cancelamento e cleanup | Confirmed |
| EP-15 | Quality | Baseline/candidate/diff, required Evidence, currentness, estados e decisão automatizada/humana estão integrados | Auditoria assistiva e policies/providers externos não são inferidos | fresh/passing, historical stale, recollect changed/failing e approve→reject preservado após restart | Confirmed |
| EP-16 | Motion | Manifest adjacente, compiler, content-set atômico do Host e Studio publicam sequências, duração, easing, scripts/observações e modos full/reduced/none | Autoria visual de Motion não pertence ao corte portátil executado | Chrome prova os três modos e equivalente estático completo | Confirmed |
| EP-17 | Context Builder | Seleção semântica Host-side, 5 inclusões/budgets independentes, uso, omissões e bundle sanitizado determinístico estão integrados | Providers externos e seleção de changeset sem head disponível permanecem explicitamente omitidos | dois exports pós-reload byte-idênticos + omissão tipada no Chrome | Confirmed |
| EP-18 | Viewer/Author e edição de layout | Authority Host-derived, draft durável, CAS monotônico, undo/redo/reset e promoção de um ProjectionLayout estão integrados | Edição de groups/lanes/annotations e providers não locais não pertencem ao v1 | duas conexões Chrome, writer stale, source exata e recovery/fault gates | Confirmed |
| EP-19 | Findings, concepts, comments e decisões append-only | ReviewPacket liga ChangeSet/ReviewGuide; findings, concepts não atuais, comments, acceptance e decisões superseding persistem com grants | Policies/providers externos e auditoria assistiva continuam delimitados | reject→approve, head/histórico, restart, grant/replay e vertical Chrome | Confirmed |
| EP-20 | SPI do consumer | Modules/Providers são reais; catálogo/factories ainda têm seams codificados | Contributions tipadas para fontes, factories, fixtures, capture, theme, locale e policies | dois providers fictícios sem branch no Host | Partial |
| EP-21 | MCP read-only | Quatro tools históricos mais Catalog/search/get/neighborhood/graph, Context, source excerpt, Evidence/capture e seis resources tipados plan-gated | Providers externos e paginação de escala permanecem nos cortes próprios | conformance stdio real, geração atômica, determinismo, redaction e path/link negativos | Confirmed |
| EP-22 | MCP com efeitos | Test/capture, capability curta single-use/revogável e Authoring/Review com grants do domínio estão integrados | Batch é sequencial não atômico; device capture, auth remota e efeitos hosted não são inferidos | revogação, primeira tentativa, attribution/audit, grant replay, finding/concept/acceptance e promoção ainda human-gated | Confirmed |
| EP-23 | Instalação/update/rollback/headless | Specification/inventory, compositor público e CLI operam a distribuição própria fora do monorepo | Assinatura, publicação e Module code arbitrário permanecem fora do corte local | instalação externa, status, update, rollback, Host headless e reversibilidade | Confirmed |
| EP-24 | Reference consumer completo | API/Flutter/Target/Gateway reais e Journey/Inventory/Lab/Quality/Authoring/Review/Motion/Context/MCP/distribuição executados | Infraestrutura externa continua fora do escopo portátil | matriz integral dos gates locais com cleanup e consumer externo | Confirmed |
| EP-25 | Escala real | Corpus determinístico possui 2.000 nodes/scenarios e 20.000 edges/transitions | Não há claim além dos budgets e ambiente medidos | dois compilers/exports + Host/Studio/Chrome com DOM, RSS, tempo e bytes limitados | Confirmed |
| EP-26 | Determinismo e impacto incremental | Dois workspaces e exports limpos são byte-idênticos; impacto direto+transitivo seleciona 8/2.000 bindings | Providers externos continuam fora do gate | comparação limpa, worker aquecido, falha isolada e nenhuma raiz runtime órfã | Confirmed |
| EP-27 | Acessibilidade e responsividade | Chrome real cobre teclado, foco visível, landmarks, alternativa a drag, texto 200%, 360 px, contraste essencial e reduced motion | Tecnologia assistiva e certificação WCAG permanecem externas | automação browser delimitada, captura inspecionada e zero log severo | Confirmed |
| EP-28 | Segurança e privacidade | Limits de arquivo/frame/DOM, nofollow, input adversarial, scan de marcadores sensíveis e cleanup estão ativos | Sandbox de socket/kernel e providers remotos não são inferidos | corpus adversarial local, isolamento de descriptor e ausência de path/secret no DOM | Confirmed |
| EP-29 | Contratos canônicos | Configuração, releases e estado instalado usam somente os formatos canônicos pré-lançamento | Evoluções futuras exigem estratégia explícita quando houver consumidores ou estado publicado | rejeição fail-closed de formatos desconhecidos e prova do formato atual | Confirmed |
| EP-30 | Documentação e ausência de resíduos | Resultados por capacidade distinguem prova, budgets, limites e gates externos; a matriz portátil terminal e os testes de reversibilidade passaram em 2026-08-18 | Somente gates que exigem infraestrutura externa permanecem explicitamente não certificados | root gate, verticais Chrome/stdio/consumer externo, reversibilidade, diff check e auditoria final | Confirmed |

## Ordem de cortes verticais

Cada corte termina em comportamento observável antes do próximo começar.

| Corte | Vertical | Saída terminal |
|---|---|---|
| validação fundacional | Baseline e matriz | arquitetura/ADRs/gates lidos, matriz registrada e baseline verde |
| topologia e layouts | Topologia + layout | contratos adjacentes, autoria, compiler, Host snapshot e Journey espacial ramificada no reference consumer |
| consumer de referência | Reference Consumer Conformance | estados success/loading/empty/stale/unavailable/failure, gate E2E e packages sem depender de `examples/` |
| conteúdo atômico e Inventory | Inventory | mesma seleção e catálogo em Journey/Inventory, facets e deep links |
| Scenario Lab e Quality | Lab -> Run -> Quality | target/gateway/script/capture/diff/freshness com falha parcial e cleanup |
| autoria e review | Authoring e Review | draft/layout/undo/redo/promote/findings/concepts/decisões append-only |
| Motion e Context | Motion e Context | visualização de motion e export semântico determinístico |
| MCP de experiência | MCP completo | leitura, operações e mutações capability-gated/auditáveis |
| distribuição externa | Distribuição externa | composição branded, install/update/rollback/headless fora do monorepo |
| escala e auditoria terminal | Escala e fechamento | corpus grande real, budgets configuráveis, determinismo, a11y e auditoria terminal |

## Checkpoint executado — topologia e layouts e conteúdo atômico e Inventory

Hipótese: um documento semântico de topologia e um documento de layout por
projection permitem Journey espacial, Inventory e autoria sem acoplar
geometria ao `Scenario` ou invalidar Evidence quando apenas a posição muda.

Invariantes do corte:

1. `CatalogManifest` v1 e `WorkspaceSnapshot` v1 permanecem byte e
   semanticamente compatíveis;
2. node instance referencia Scenario; nunca o substitui;
3. edge instance referencia Transition e seus endpoints precisam corresponder;
4. topology não contém coordenadas; layout não redefine semântica;
5. layout declara o digest da topology e a projection exata;
6. documento ausente é estado explícito, não layout gerado promovido a fonte;
7. Host continua autoridade; Studio não lê content root;
8. o example usa somente imports públicos e dados sintéticos;
9. moving/layout authoring não altera `CatalogManifest.digest` nem freshness de
   Evidence;
10. unknown fields, versão adjacente, digest divergente, bounds e referências
    pendentes falham fechados.

Gates de promoção de topologia e layouts:

```bash
dart test libs/experience_contracts
dart test libs/experience_engine
dart test libs/execution_runtime
dart test apps/studio/test
dart run examples/tool/showcase.dart --check
./tools/verify/verify_studio_vertical.sh
dart run tools/gates/architecture_guard.dart
flutter analyze --fatal-infos --fatal-warnings
git diff --check
```

Em 2026-08-13, as suites completas de contracts+engine passaram 195/195 e o
Studio passou 58/58 antes do gate. `examples/tool/showcase.dart --check`
confirmou 1 Board, 2 Projections, 10 NodeInstances, 5 EdgeInstances, 2 layouts
e 8 Scenarios integralmente faceted.

`tools/verify/verify_studio_vertical.sh` passou em Chrome release após detectar e
corrigir dois defeitos reais: um breadcrumb de 46,125 px e a ausência de
`studio.inventory` no profile sem provider. O resultado promovido comprovou:

- 10 PNGs válidos, `structural`, e duas sequências stale→fresh;
- Journey com 5 nodes, 5 edges arbitrárias, branch/merge, group, 3 lanes e
  annotation;
- Inventory canônica com 8 Scenarios e 11 eixos, mais projection espacial com
  5 nodes, 0 edges, 2 groups, 2 lanes e annotation;
- digests de topologia, layouts e facets idênticos nos profiles com e sem
  Evidence provider;
- geometria CSP-safe sem `style` inline, deep links, filtro/reset por URL,
  teclado, target mínimo de 48 px, reflow a 200%, reduced motion e zero logs
  severos;
- p95 de 43,1 ms nas 20 interações medidas e cleanup dos processos/ports
  criados pelo gate.

topologia e layouts e conteúdo atômico e Inventory estão promovidos no escopo descrito. Edição/persistência de layout,
projections adicionais e escala continuam nos cortes próprios; nenhum desses
itens é inferido do resultado browser pequeno.

## Checkpoint executado — consumer de referência

Em 2026-08-13, `tools/verify/verify_reference_consumer.sh` passou com 8 Scenarios, 3
Variants, 10 capturas atuais fresh/structural, 24 entradas históricas
explicitamente `unbound`, os seis estados do dashboard, Target Flutter real e
quatro presets de Gateway. Hybrid provou mutação upstream; offline provou
isolamento por fixture; unavailable e failure conservaram semânticas distintas.
O trap encerrou Session/Gateway/API/Host/Studio e liberou 7367/7368/8080/8181.

O resultado detalhado e os limites de claim estão em
[`reference-consumer-conformance-results.md`](reference-consumer-conformance-results.md).
O gate foi incorporado a `melos run check`; CI usa o mesmo check. EP-24 permanece
`Partial` porque “reference consumer completo” também inclui as superfícies e
efeitos dos cortes seguintes, não porque falte conformance aos estados consumer de referência.

## Checkpoint executado — Scenario Lab e Quality

`ScenarioLabManifest` v1 e `ScenarioLabCompiler` continuam sendo a camada
pública, fechada e catalog-bound. O vertical adicionou publicação Host atomic
v2, planner/executor, store durável de runs, relay v2 tipado e fenced, Target
Flutter Host-owned, Gateway ligado ao run, Evidence/comparison e as rotas
Lab/Quality do Studio Jaspr. A decisão humana usa grant curto, expected digest,
atribuição e journal append-only. Ela não substitui aceitação automatizada.

Em 2026-08-17, o gate no-skip abaixo saiu com status `passed` em Linux/Chrome
release:

```bash
scenario_capture_dir="$(mktemp -d /tmp/scenario-lab-ep4.XXXXXX)"
env -u SCENARIO_LAB_SKIP_BUILD \
  SCENARIO_LAB_CAPTURE_DIR="$scenario_capture_dir" \
  ./tools/verify/verify_scenario_lab_vertical.sh
```

Evidência executada do run baseline:

- Target em um iframe, relay v2 ready/fenced, Hello aceito e 6/6 resultados
  reconhecidos;
- Gateway com 1 GET, 1 resposta 2xx e zero acesso direto do Target à API;
- terminal/cleanup `succeeded`, Evidence `collected` + `fresh` e comparação
  visual aprovada em 617.984 pixels, com 283 pixels alterados e delta máximo
  210 dentro da policy;
- Quality automatizado `passed`; decisão humana `approved` seguida por
  `rejected`, duas entradas e supersession/head preservados após reinício;
- segundo run cancelado com cleanup, dois PNGs de 1440×913 validados por digest,
  zero focusable anônimo, nenhum overflow a 200%, reduced motion ativo e zero
  log severo.

O gate então alterou temporariamente o layout autoral e a cor do Target. A nova
geração mudou `contentSetDigest` e layout, manteve catálogo, facets, manifest
Lab e conteúdo semântico, marcou o run anterior `stale` e bloqueou seu review.
A recollection atual recebeu 6/6 ACKs e Gateway 1/1, coletou Evidence fresh e
terminou `acceptanceFailed` porque 307.602 de 617.984 pixels mudaram (razão
aproximada 0,49775; delta máximo 221). O campo de verificação automatizada do
run permaneceu `passed`, enquanto Quality projetou `current`, `changed` e
`failing`, sem converter falha parcial em sucesso.

O cleanup parou writers, liberou ports e restaurou byte a byte fontes, build
do Studio, builds baseline/alterado do Target e workspace state. O CI executa
o mesmo gate depois de `melos run check` e do vertical Studio, reutilizando os
builds já produzidos com `SCENARIO_LAB_SKIP_BUILD=1`. Somente a etapa de
build inicial é omitida.

EP-10, EP-11, EP-14 e EP-15 estão promovidos para `Confirmed` nesse escopo
portátil local. Isso não promove automaticamente autoria/review, Motion/Context,
MCP, distribuição ou escala, nem certifica WCAG, produção,
hosted, device farm, dispositivo físico ou provider externo.

## Checkpoint executado — autoria e review

O corte introduziu contratos fechados de Authoring/Review, `LayoutDraftEngine`,
store durável, authority local, 16 RPCs tipados e a rota
`/authoring/:projectionId`. O Studio recebe somente subject, manifests e views
sanitizadas. Authority, policy, principal e grant permanecem stack-local no
facade browser e não entram em controller, URL, DOM ou logs do gate.

A promoção v1 modifica um único `ProjectionLayout` v2. O Host resolve o
arquivo dentro do content root configurado, recompõe o candidate e exige
catálogo/topologia estáveis. CAS, journal hash-chained, WAL, grant consumption,
source metadata e um slot privado cercam restart e falhas. O provider executado
é Linux x64 com `renameat2(RENAME_EXCHANGE)`; plataformas ou filesystems sem
essa primitiva retornam `unsupported`, sem fallback destrutivo. O boundary
completo está em [ADR-0019](decisions/0019-local-experience-authoring-authority.md).

Em 2026-08-17, os gates focados executados passaram:

- 129/129 testes de store, promotion coordinator e service;
- 13/13 testes de Host runtime/composição, incluindo os 16 RPCs, epoch e evento
  somente depois do commit durável;
- 21/21 testes puros/Jaspr de Authoring e 2/2 do facade browser real;
- `dart analyze` dos libs/tools alterados, `jaspr build`, `shellcheck` e
  `git diff --check` sem issues.

O vertical dedicado executado foi:

```bash
capture_dir="$(mktemp -d /tmp/authoring-review-ep5.XXXXXX)"
AUTHORING_CAPTURE_DIR="$capture_dir" \
  ./tools/verify/verify_authoring_review_vertical.sh
```

Ele abriu duas conexões Chrome reais sobre uma cópia privada do consumer. O
primeiro writer abriu o draft e moveu `journey-dashboard-ready`; o segundo foi
rejeitado como stale. Undo, redo, reset e novo move preservaram o head. O fluxo
materializou o ReviewGuide, anexou um finding, um concept explicitamente não
atual e um comment, executou acceptance estrutural, registrou reject e approve
append-only com uma decisão superseded e promoveu o head aprovado.

A prova de source recompilou baseline e cópia promovida: catálogo, topologia e
o layout não relacionado ficaram estáveis; exatamente um frame mudou, apenas
`x + 20`. O journal ficou privado `0600`, a captura PNG foi 1440×857, logs
severos e markers transitórios foram zero. Cleanup removeu a cópia, estado,
processos e listeners. `tools/verify/authoring_review_reversibility_test.sh` repetiu
o fluxo com falha injetada após a mutação e confirmou o mesmo rollback do gate.

EP-18 e EP-19 ficam `Confirmed` no escopo local portátil executado. Isso não
promove Motion/Context, MCP, distribuição ou escala; não certifica WCAG nem
atomicidade contra um processo same-uid que ignore deliberadamente o lock.

## Checkpoint executado — Motion e Context

Motion é um documento autoral v2 adjacente ao catálogo e à topologia. O Host o
compila na mesma geração do content-set e publica um resource opcional com
digest exato; o Studio só troca a geração depois de validar todos os resources.
Cada sequência declara steps, transitions, easing, scripts e observações, e
sempre carrega um resumo estático completo. `full`, `reduced` e `none` alteram
somente duração; `none` totaliza exatamente zero mesmo quando steps posteriores
possuem `startMs`.

Context Builder é uma projeção read-only do Host. O request aceita apenas IDs
semânticos de board, projection, journey, scenario e changeset, cercados pelo
`contentSetDigest`. Fontes, imagens, Evidence, história e mudanças possuem
budgets e uso independentes. Dados ausentes, recusados pelo request ou cortados
por budget viram omissões tipadas; nenhum path é recebido do browser.

Em 2026-08-17, contratos/schema, compiler/builder, Host, transport e rotas
Studio passaram os testes focados. `showcase.dart --check` validou o consumer
sem abrir serviços. O vertical executado foi:

```bash
capture_dir="$(mktemp -d /tmp/motion-context.capture.XXXXXX)"
chmod 700 "$capture_dir"
MOTION_CONTEXT_CAPTURE_DIR="$capture_dir" \
  ./tools/verify/verify_motion_context_vertical.sh
```

O Chrome real provou 2 steps e 2 observações, full/reduced/none, duração none de
0 ms e o equivalente estático preservado. O Context Builder exportou 19 itens;
dois exports equivalentes separados por reload tiveram digest idêntico. Ao
desmarcar Evidence, o bundle mudou e declarou a omissão; o resumo final contou
28 omissões, zero logs severos e screenshot 1440×857. O teste de reversibilidade
injetou falha depois do fluxo browser e confirmou os três ports livres, nenhum
runtime root novo e os bytes do consumer inalterados.

EP-16 e EP-17 ficam `Confirmed` nesse escopo local. O gate não prova autoria de
Motion, qualidade do conteúdo exportado para um modelo específico, WCAG,
provider externo, hosted ou infraestrutura de produção. O boundary normativo
está em [ADR-0020](decisions/0020-motion-and-context-builder.md).

## Checkpoint executado — MCP de experiência

O MCP Experience é uma extensão adjacente ao servidor read-only v1. O CLI
resolve `workspace.yaml` e o profile, compila uma geração de conteúdo e publica por
stdio apenas resources/tools cujos Modules estão habilitados. O transporte não
abre listener: o launcher local é a autoridade do pipe e `clientInfo` serve
somente para atribuição, não para autenticação remota.

Queries aceitam IDs semânticos, digests e budgets fechados. Source excerpts,
targets de teste, bundles e PNGs são confinados ao workspace sem symlink;
commands e endpoints arbitrários não existem no schema. Efeitos genéricos usam
capability de dois minutos, single-use e revogável, ligada a principal, tool,
content-set e payload. Authoring reutiliza o journal, ownership, grants, CAS e
promotion do autoria e review. `batchMutate` é bounded, sequencial e declara
`atomic=false`; somente a promoção preserva a transação autoral própria.

Em 2026-08-17, os testes focados do backend/server e o teste de reversibilidade
passaram. O vertical executado foi:

```bash
./tools/verify/verify_mcp_experience_vertical.sh
```

O processo real publicou 35 tools e 6 resources. A prova executou 9 queries,
exportou Context determinístico com 14 itens e 32 omissões, redigiu um secret,
rejeitou path externo, rodou 1 teste Dart e importou/diffou um PNG 1×1. Uma
capability revogada não executou; mismatch consumiu a primeira tentativa. O
fluxo autoral abriu/replayou/moveu o draft, preparou review, registrou finding e
concept não atual e gravou acceptance `passed`. O pacote continuou sem decisão
humana e não promovível. O audit encadeado foi persistido e a cópia isolada foi
removida pelo gate.

EP-21 e EP-22 ficam `Confirmed` nesse escopo local. Não há claim de autenticação
remota, sandbox de CPU/memória/rede, hosted, device capture, batch atômico ou
qualidade de contexto para um modelo. O boundary normativo está no
[ADR-0021](decisions/0021-mcp-experience-automation.md) e o wire em
[MCP Experience](../protocols/mcp-experience.md).

## Checkpoint executado — distribuição externa

`ConsumerDistributionSpec` e `ConsumerDistributionInventory` tornam explícitas
a identidade do consumer, compatibilidade core/schemas/Modules, profile, modo
Studio, configuração, catálogo, plano e inventário de conteúdo. O compositor
reusa somente um release base v2 verificado, recompila o catálogo autoral e
resolve Modules/Providers antes de criar qualquer output.

Em 2026-08-17, o vertical criou um package consumer em `/tmp`, copiou somente os
packages públicos e rejeitou import de `src/`. A API pública e o CLI AOT
produziram três bundles 1.0.0 byte-idênticos. O bundle `acme-experience` levou
CLI, Host e Gateway, nenhum asset Studio, o catálogo próprio e o profile
`gateway-lab-headless`.

```bash
./tools/verify/verify_external_distribution_vertical.sh
```

O release foi instalado, consultado, atualizado para 1.0.1, revertido para
1.0.0 e teve state v0 migrado, desfeito e reaplicado. O Host instalado iniciou
com o ModuleCatalog e ResolvedKitPlan empacotados, zero contribuição Studio e o
workspace externo como autoridade viva. A injeção de falha durante readiness
confirmou encerramento do Host e remoção do runtime root.

EP-23 fica `Confirmed` nesse escopo Linux x64 local. Não há assinatura,
publicação, Module code arbitrário, hosted nem claim de supply-chain. O boundary
normativo está em [ADR-0022](decisions/0022-external-consumer-distribution.md) e o
contrato em
[consumer-distribution.md](../contracts/consumer-distribution.md).

## Checkpoint executado — escala e auditoria terminal

O gerador de escala cria dois workspaces externos canônicos com 44.004
documentos autorais cada, 2.000 `Scenario`/`NodeInstance` e 20.000
`Transition`/`EdgeInstance`. O loader aplica limites configuráveis de arquivos,
bytes por arquivo e bytes agregados antes do parse. O compiler e o export são
executados duas vezes e os workspaces e exports precisam ser byte-idênticos.

```bash
./tools/verify/verify_scale_accessibility_security_vertical.sh
```

Em 2026-08-17, o gate terminou em 9.326 ms no processo medido, observou
812.437.504 bytes de RSS e produziu export de 6.623.188 bytes. A janela espacial
reteve 24 nós, 10 arestas renderizáveis e 256 de 480 arestas diagnósticas de
fronteira. O Host e o Studio reais abriram a seleção profunda no Chromium: DOM
de 1.373 elementos, outline 48/2.000, mapa 64 nós e 40 arestas, 256/1.200
diagnósticos de fronteira, sem overflow global a 360 px ou texto 200%, contraste
mínimo 7,37:1 nos cinco controles essenciais amostrados, reduced motion ativo e
zero log severo.

O impact planner marcou 8 de 2.000 bindings por impacto direto+transitivo. Um
único isolate aquecido processou quatro batches e isolou um descriptor inválido:
255 sucessos, uma falha e sucesso posterior. A falha injetada em `host-ready`
provou encerramento dos grupos, liberação das três portas e remoção da raiz
privada. EP-24 a EP-28 ficam `Confirmed` somente nesse escopo local portátil.
Tempos/RSS são observações, não SLO; a prova automatizada não certifica WCAG,
tecnologia assistiva, sandbox de kernel ou infraestrutura remota. O relatório
detalhado está em
[scale-accessibility-security-results.md](scale-accessibility-security-results.md).

## Checkpoint terminal executado — Fase 1 portátil

Em 2026-08-18, a matriz portátil integral foi repetida no worktree da Fase 1,
sem commit, branch, tag, stash, ref ou publicação. O gate raiz executou
formatação, analyzer, supply chain, conformance, testes, builds, consumers de
referência e contenção. As suites reportaram 1.152 testes: contracts 201,
engine 90, runtime 553 em ordem serial por inspecionar descritores e listeners
globais, Flutter 16, preview 2, UX 14, UI 5, testkit 1, Studio 226, CLI 30,
Host 1, Gateway 3, hosted 5, session Gateway 2 e remote worker 3.

```bash
melos run check
STUDIO_SKIP_BUILD=1 ./tools/verify/verify_studio_vertical.sh
SCENARIO_LAB_SKIP_BUILD=1 ./tools/verify/verify_scenario_lab_vertical.sh
./tools/verify/verify_authoring_review_vertical.sh
./tools/verify/verify_motion_context_vertical.sh
./tools/verify/verify_mcp_experience_vertical.sh
./tools/verify/verify_external_distribution_vertical.sh
SCALE_SKIP_STUDIO_BUILD=1 \
  ./tools/verify/verify_scale_accessibility_security_vertical.sh
```

Os oito gates terminaram com status `passed`. O Studio validou 10 captures em
Chrome release, stale→fresh com e sem provider e cleanup. Scenario Lab
reconheceu 6/6 resultados tipados nos dois runs, roteou o Target exclusivamente
pelo Gateway, preservou decisão humana append-only no restart e separou o run
histórico stale da recollection atual `changed`/`failing`. Authoring comprovou
duas conexões, stale writer, undo/redo/reset, ReviewGuide, finding, concept,
comment, decisão superseding e promoção de um layout.

Motion/Context provou 2 steps, 2 observações, os modos full/reduced/none,
equivalente estático, 19 itens e 28 omissões tipadas. O MCP real publicou 35
tools e 6 resources, executou 9 queries e preservou redaction, confinement,
revogação, single-use e replay. A distribuição externa passou install,
status, update, rollback e Host headless sem assets do
Studio nem friend APIs.

O corpus final conteve 44.004 arquivos autorais, 2.000 nodes/scenarios e 20.000
edges/transitions. Mediu 9.355 ms totais, p95 de janela de 7.641 µs,
833.011.712 bytes de RSS observados e export de 6.623.188 bytes, todos dentro
dos budgets declarados. O browser manteve DOM de 1.373 elementos, windowing
64/2.000, outline 48/2.000, contraste essencial mínimo de 7,37:1, navegação
sem drag, foco visível, reduced motion, zero overflow a 360 px e texto 200%,
zero log severo e nenhum runtime artifact órfão.

Os seis helpers `tools/verify/*_reversibility_test.sh` correspondentes também
passaram. Eles injetaram falhas em source/state/process/build e confirmaram
restauração ou remoção apenas dos alvos privados de cada gate. A auditoria
terminal confirmou dependência unidirecional: libs/apps do Abel não
importam `examples/` nem qualquer consumer real; `examples/` permanece o
consumer sintético de referência e usa somente APIs públicas.

Esse checkpoint não certifica WCAG, tecnologia assistiva, dispositivo físico,
device farm, KVM, cluster, IdP, object store, provider remoto, hosted de
produção ou supply chain publicada. Tempos e memória são observações deste
ambiente, não SLOs. Essas fronteiras externas permanecem registradas sem
aprovação implícita.
