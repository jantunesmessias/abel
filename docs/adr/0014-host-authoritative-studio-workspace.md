# ADR-0014 — Workspace autoritativo do Host para o DevEx Studio

Status: aceita em 2026-08-10; rollout SR0–SR9 concluído na matriz local.

Nota de evolução: a decisão de autoridade do Host, RPC/WebSocket autenticado e
resource handles permanece vigente. Renderer e tooling do Studio são regidos
pela ADR-0016; o baseline Flutter SR0–SR9 permanece histórico nos resultados.

## Contexto

O DevEx Studio atual possui uma UI mínima e usa um catálogo demonstrativo em
memória quando o caller não injeta um repository. O Host publica composição,
Sessions, Capture e Gateway, mas não publica o catálogo compilado, variants ou a
projeção de visual Evidence. `devex dev` retorna instruções para iniciar Host e
Studio separadamente, em vez de supervisionar a experiência.

MC0–MC6 e AP0–AP4 entregaram fundamentos importantes, mas MC6 comprovou o seam
de contributions/rotas e AP4 a projeção tipada em memória. Esses gates não
comprovam a experiência operacional CAS → Host → Studio.

O Studio não pode corrigir esse gap lendo `devex.yaml`, `.devex`, `.dart_tool`
ou CAS diretamente: isso duplicaria discovery/compilation, levaria autoridade
de filesystem ao browser e criaria uma segunda interpretação do
`ResolvedKitPlan`.

## Decisão

### 1. Host é a autoridade de workspace

O Host recebe o mesmo `ResolvedKitPlan` resolvido pelo CLI, usa
`WorkspaceCatalogLoader`/`CatalogCompiler`, observa EvidenceProviders enabled e
produz um `WorkspaceSnapshot` canônico. O Studio consome somente esse snapshot e
eventos subsequentes.

Produção não possui fallback para `sampleCatalogManifest`. Fixtures em memória
permanecem permitidas em testes, golden harnesses e demonstrações explicitamente
marcadas.

### 2. Snapshot não duplica domínio

`WorkspaceSnapshot` agrega `CatalogManifest`, `VariantManifest`,
`EffectiveKitManifest` e `VisualEvidenceProjection`. Ele é um read model de
application boundary, não novo bounded context e não redefine Scenario,
Variant, Evidence ou Module.

`VisualEvidenceProjection` é provider-neutral. Provider-specific manifests
continuam a fonte de associação. Captura sem binding explícito permanece
`unbound`; não se infere Scenario/Variant por filename, título, ordem ou layout.

### 3. Control plane bounded; resources por capability

WebSocket JSON-RPC transporta initialize/resume, descriptions, commands e
eventos bounded. Snapshots e PNGs usam `GET /resources/{opaque-capability}`.
Capabilities são aleatórias, purpose/audience-bound, têm TTL, tamanho/media
type/classification allowlisted, Origin exato e digest revalidado. O Studio não
recebe path do CAS nem token persistido em URL.

RPCs iniciais:

```text
devex.workspace.describe
devex.workspace.open
devex.workspace.refresh
devex.preview.collect
devex.preview.status
devex.preview.cancel
```

Evento: `devex.workspace.changed`.

Cada RPC, resource route e Studio contribution pertence a um Module. Module
disabled não registra sua superfície.

### 4. Startup e topology

`devex dev` resolve configuração e compila catálogo antes de efeitos, inicia o
Host, serve o Studio Jaspr empacotado no origin autorizado, espera
readiness, abre o navegador salvo `--no-open` e supervisiona shutdown reverso.
Sem `studio.shell`, assets/bootstrap/rota não existem.

Em checkout de desenvolvimento, `--studio-dev-origin` substitui os assets
empacotados por uma origem HTTP loopback externa, tipicamente `jaspr serve`. O
Host autoriza exatamente esse origin para bootstrap CORS, WebSocket e resource
handles. O cliente recebe a URL pública do bootstrap por
`DEVEX_STUDIO_BOOTSTRAP_URL`; token e grants não entram no define ou na URL. Os
modos externo e empacotado são mutuamente exclusivos, e a conformance release
continua usando o bundle empacotado.

A topologia do Kit permanece imutável no run. Alteração estrutural requer
restart controlado; settings só podem mudar live quando o descriptor declarar
essa semântica e o lifecycle correspondente.

### 5. Projeção visual e fidelidade

Scenario é identidade; pixels são projeção opcional por
`Scenario × Variant × Provider`. Provider default vem de `ProviderBinding`; uma
escolha temporária no inspector não altera o plan. Ausência/falha não causa
fallback silencioso.

AutoPreview `flutter-test` declara somente `structural`. App Adapter e Android
preservam bindings e claims independentes. Device frame é presentation chrome
do Studio fora do PNG e não modifica Evidence.

### 6. Atlas como referência

O Tarski Atlas é referência funcional read-only. Este rollout não importa seu
código, packages ou assets, não o usa como upstream/migration source e não o
adiciona ao CI do DevExKit.

## Limitações normativas

- Widget Previewer continua experiência interativa, não exportador de PNG;
- o runner DevEx não usa API interna do Previewer;
- Flutter 3.44.8 requer `--legacy-preview-detection` porque o detector LSP
  default falha;
- `flutter-test` não fornece fidelity host-native;
- allowlist, timeout e staging não provam containment de rede/memória;
- sem sandbox comprovado, o fingerprint permanece
  `NetworkContainment.unconstrained`.

## Alternativas rejeitadas

### Studio lê o workspace diretamente

Rejeitada por duplicar autoridade, parser, plan resolution e filesystem access.

### Enviar todo catálogo pelo WebSocket

Rejeitada como contrato geral: o limite atual é 64 KiB e workspaces reais podem
excedê-lo. Resource handles preservam bounded control plane.

### Colocar CAS path ou digest na URL

Rejeitada. Path revela storage e digest é identificador previsível, não
capability. A URI usa identificador opaco scoped/TTL.

### Tratar qualquer extensão como Plugin

Rejeitada. Module/Provider built-in trusted e Plugin externo não compartilham
trust boundary ou lifecycle.

### Copiar o Atlas

Rejeitada. Referência de interação não autoriza acoplamento entre projetos.

## Consequências

- Host ganha loader/compiler/projection/resource responsibilities explícitas;
- Studio pode ser testado por repository in-memory, mas produção exige Host;
- contracts adicionais precisam de decoder/schema/digest/limits;
- Evidence antiga sem binding continua visível como unbound;
- `devex dev` passa de planner para supervisor com cleanup obrigatório;
- distribuição precisa empacotar assets do Studio somente quando o Module
  correspondente estiver enabled/packaged;
- resultados MC/AP continuam válidos no escopo original, mas não promovem SR.

## Rollout e rollback

O rollout segue SR0–SR9 em
`docs/architecture/devex-studio-reconstruction-plan.md`. Cada gate é promovido
somente com testes focados e regressão proporcional. Rollback desabilita as
novas contributions/rotas e preserva CLI/Host headless, catálogo, CAS e
providers existentes; nunca reativa o catálogo sample no entrypoint de
produção.

## Evidência requerida

- contracts/schemas fechados e corpus negativo;
- catálogo real compilado e idêntico no Host/Studio;
- resource handles com negativos de Origin/TTL/media type/classification;
- `devex dev --no-open` e shutdown sem orphan;
- Studio release em Chromium com Journey/Scenario reais;
- duas Variants/PNGs AutoPreview, inspector e stale→fresh;
- mapa sem provider e matriz de profiles isolados/combinados;
- teclado/Semantics/reflow, performance de 1.000+ nodes e cache bounded;
- ausência de import/assets/CI do Atlas;
- auditoria requisito→mudança→teste→status antes da claim SR9.

O registro executado requisito por requisito está em
`docs/architecture/devex-studio-reconstruction-results.md`. A decisão não
promove o renderer AutoPreview acima de `structural` nem transforma gates
locais em certificação de sandbox ou infraestrutura.
