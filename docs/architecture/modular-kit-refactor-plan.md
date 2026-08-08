# Plano de refatoração — composição modular e AutoPreview

Status: fundações MC0–MC6 e AP0–AP4 implementadas em 2026-08-10; MC6/AP4 não
incluem a integração operacional completa do Studio, planejada separadamente
em SR0–SR9.

Este documento operacional implementa ADR-0012 sem reescrever a evidência
histórica P0–V5. O objetivo é tornar o DevExKit um Kit configurável por Module,
Capability, Provider e Profile, e entregar AutoPreview como primeiro vertical
novo sobre essa fundação.

## 1. Resultado observável

O mesmo `ResolvedKitPlan` deve comandar comandos CLI, RPCs/processos do Host,
rotas do Studio, EvidenceProviders, devices, rede, distribuição e claims.

Profiles mínimos:

| Profile | Modules |
|---------|---------|
| `journey-preview` | `catalog`, `artifact-store.local`, `studio.shell`, `studio.journey-map`, `evidence.auto-preview` |
| `journey-android` | `catalog`, artifact store, Studio/Journey, Sessions, Android target/evidence |
| `gateway-lab` | `catalog`, artifact store, Sessions, Gateway e Studio shell |
| `gateway-lab-headless` | `catalog`, artifact store, Sessions e Gateway, sem Studio |
| `full-local` | superfície local completa atual |
| `legacy-full-local-v1` | tradução interna da consumer config v1 |

Config v2 explícita:

```yaml
schemaVersion: 2
kit:
  modules:
    catalog:
      enabled: true
    artifact-store.local:
      enabled: true
    studio.journey-map:
      enabled: true
    evidence.auto-preview:
      enabled: true
      settings:
        renderer: flutter-test
        capturePolicy: static-v1
    target.android:
      enabled: false
    gateway.interceptor:
      enabled: false
```

## 2. Baseline MC0

Worktree inicial:

- branch `main` um commit ahead e um behind de `origin/main`;
- `ARCHITECTURE.md` possui mudanças preexistentes P0–V5;
- a maior parte da implementação está presente como conteúdo não rastreado;
- essas mudanças são preservadas e não atribuídas a este refactor.

Gate executado em 2026-08-10:

```text
./tool/check.sh → exit 0
```

Cobertura observada: format, analyze fatal, architecture/supply-chain,
contracts, engine, runtime, Flutter adapter, Studio VM/Chromium, CLI, Host,
Gateway, hosted, remote, contenção Linux netns e consumers `sample_flutter` e
`friction_flutter`.

## 3. Gates e ordem crítica

```text
MC0 → MC1 → MC2 → MC3
                  ├──→ MC4 CLI
                  ├──→ MC5 Host/Gateway
                  └──→ AP0–AP3
MC5 → MC6 Studio
AP3 + MC6 → AP4 Journey Map
depois → Android/restante → Distribution v2 → estabilização
```

### MC0 — baseline e decisão

- [x] registrar worktree e gate existente;
- [x] criar ADR-0012;
- [x] criar este plano;
- [x] atualizar princípios, riscos, roadmap e registro normativo;
- [x] ratificar a taxonomia; IDs e dependency graph serão codificados no
  primeiro fixture de contracts MC1.

### MC1 — contracts e schemas

Adicionar em `devex_contracts`:

- `ModuleId`, `ModuleCapabilityRef`, `ModuleRequirement`;
- `ModuleDescriptor`, `ModuleCatalog`;
- `KitProfile`, `KitSelection`, `ProviderBinding`;
- `ResolvedKitPlan`, `EffectiveKitManifest`;
- estados, health e diagnósticos fechados.

Schemas:

- `schemas/v1/kit-composition.schema.json`;
- `schemas/v1/preview-capture.schema.json` no AP1;
- `schemas/v2/consumer-config.schema.json`;
- `schemas/v2/distribution-descriptor.schema.json`;
- `schemas/v2/distribution-release.schema.json`.

Gate: round-trip fechado, canonicalização, digest, ordem estável, fixtures
válidas/inválidas e versões adjacentes, sem mudança funcional.

### MC2 — config v2 e resolver

`devex_engine` recebe normalizer, profile expander, provider resolution,
conflicts/cycles/platform checks e topological order determinística.
`devex_runtime` recebe `WorkspaceConfigurationLoader`; filesystem discovery e
interpretação tornam-se responsabilidades separadas. Loaders de Gateway e
providers deixam de reler configuração por conta própria.

Config v1 é traduzida para `legacy-full-local-v1` e atravessa o mesmo resolver.
Precedência: Kernel < Distribution < Profile < Workspace < local < startup.

Gate: v1 equivalente, digest independente de ordem, paths confinados, secrets
literais rejeitados e toda falha anterior a efeitos.

### MC3 — Kernel e lifecycle

Implementar catálogo/factory registry compile-time, `ModuleContext`,
contributions, lifecycle coordinator e health registry. Não existe reflection,
dynamic Dart loading nem service locator irrestrito.

Gate: módulo desabilitado produz zero comando/RPC/rota/processo/porta/artifact;
failure injection desfaz startup em ordem inversa e não deixa orphan.

### MC4 — CLI

Separar bootstrap parser, plan loader, command registry e contribuições por
módulo. Bootstrap commands funcionam sem workspace: `version`, `init`,
distribution, `modules` e `config migrate`.

Comandos novos:

```text
devex modules list
devex modules explain
devex modules doctor
devex config migrate --to 2 --dry-run|--apply
```

Gate: help e dispatch derivados do plano, machine output v1 compatível e erro
estruturado para Module indisponível.

### MC5 — Host, Sessions, Capture e Gateway

O Host valida um `ResolvedKitPlan` transportado por staging autorizado, monta
RPC contributions e publica `EffectiveKitManifest`. Kernel RPC:
`devex.kit.describe`, `devex.kit.health` e evento `devex.kit.changed`.

Extrair na ordem Sessions, App Adapter Capture e Gateway. Gate: combinações
com/sem Gateway, vinte ciclos, failure injection, shutdown concorrente, child
death e zero resíduo.

### MC6 — Studio

Adicionar repository do manifest e contributions de navegação/rotas. O Studio
não inicia módulos. Deep link indisponível recebe estado estruturado; Grant e
Module availability continuam ortogonais.

Gate: Journey on/off, sem/com visual Evidence, grants cruzados, teclado, screen
reader, reconnect e um único plan digest.

Escopo comprovado: repository seam, routes/contributions condicionais e
projeção in-memory. Shell completo, catálogo real vindo do Host, resource
handles, inspector/provider selection e startup supervisionado não fazem parte
de MC6; pertencem a
`docs/architecture/devex-studio-reconstruction-plan.md`.

## 4. AutoPreview AP0–AP4

### AP0 — spike

No `sample_flutter`, usar uma factory real top-level com `@AutoPreview`, provar
Widget Previewer oficial, descoberta Analyzer e duas capturas via `flutter
test`, sem `build_runner`, geração em `lib/` ou import DevExKit no `main.dart`.

### AP1 — API e contracts

Criar package `devex_preview` dependente apenas de Flutter e contracts.
Implementar `AutoPreview`, `AutoMultiPreview`, `AutoPreviewVariant` e marker de
compatibilidade Flutter 3.44.x. Contracts: `Variant`, descriptors, manifests,
capture items/report, status e capture key. Ratificar ADR-0013.

### AP2 — scanner/compiler

Analyzer e filesystem ficam no runtime; normalização permanece no engine.
Suporte inicial: função pública top-level, retorno Widget/WidgetBuilder,
argumentos const, `lib/**/*.dart`, IDs explícitos e registry efêmero somente em
`.dart_tool`.

### AP3 — runner/Evidence

Scaffold efêmero `flutter test`, stabilization policy limitada,
RepaintBoundary, subprocesso, env allowlist, no secrets, sandbox/rede quando
disponível, quotas, failure isolation, PNG inspector, CAS e EvidenceProvider.

### AP4 — Journey Map

Projetar Scenario × Variant para artifact handle, provider, fidelity,
freshness e diagnóstico. Studio nunca recebe CAS path. LOD, placeholders e
último artifact válido mantêm estado explícito. Source Impact invalida apenas
previews afetados.

Escopo comprovado: contracts/projector e estados exercitados em teste. A cadeia
operacional CAS → Host → Studio e a apresentação em device frames pertencem a
SR2–SR7.

## 5. Migração e distribuição

Após Gateway e AutoPreview, extrair Android target/evidence, test evidence,
source impact, plugins, MCP, hosted/remote clients e release local. Cada
extração remove o registro estático correspondente, testa ausência e mantém o
profile legado.

Distribution v2 começa completa/configurável e depois aceita bundles enxutos.
Manifest registra modules, profiles, components, files e ModuleCatalog digest.
CLI é obrigatória; Host, Gateway e Studio são condicionais. Builders geram
entrypoint apenas em `.dart_tool` e provam rebuild byte-idêntico, install,
update e rollback v1/v2.

## 6. Conformance

Suites obrigatórias:

- contracts/schemas e adjacent versions;
- resolver: missing/multiple provider, cycles, conflicts, platform, optional,
  precedence, order e digest;
- lifecycle: prepare/start failure, rollback, cancellation e shutdown;
- ausência por Module;
- profiles principais e cobertura pairwise adicional;
- traversal, symlink, secret, digest, unbundled module e preview hostil;
- Studio routes/deep links/a11y/fidelity/freshness;
- performance baseline e budgets ratificados em resultado executado.

Ferramentas ativas:

```text
tool/verify_auto_preview.sh
tool/verify_modular_distribution.sh
tool/verify_v03_distribution.sh
```

Gates P0–V5 existentes permanecem; gate novo não substitui evidência anterior.

## 7. Atualização documental

Criar durante o vertical correspondente:

- ADR-0013 AutoPreview;
- `docs/contracts/module-composition-v1.md`;
- `docs/contracts/consumer-configuration-v2.md`;
- `docs/contracts/distribution-release-v2.md`;
- `docs/contracts/auto-preview-v1.md`;
- `docs/quality/module-conformance-v1.md`;
- `docs/quality/auto-preview-conformance-v1.md`;
- `docs/security/auto-preview-threat-model.md`;
- `docs/operations/module-startup.md`.

Somente após gates executados:

- `docs/architecture/modular-composition-results.md`;
- `docs/architecture/auto-preview-results.md`;
- nova seção MC/AP no master-plan audit.

`ARCHITECTURE.md` recebe a decisão, contracts, config/precedence, composition
roots, Studio, Gateway/AutoPreview, distribuição, adoção, CLI, segurança,
roadmap, budgets, conformance, health, riscos, glossário e registro normativo.
README recebe profiles, config v2, commands, compatibility e comparação entre
AutoPreview, App Adapter e Android. Result docs P0–V5 não têm claims alteradas.

## 8. Definition of Done

- [x] v1/v2 convergem para o mesmo resolver;
- [x] CLI/Host/Studio observam o mesmo plan digest;
- [x] nenhum recurso fica registrado fora de Module contribution;
- [x] profiles principais e combinações focadas passam;
- [x] disabled significa zero efeitos;
- [x] Gateway, AutoPreview e Android são selecionáveis isoladamente/combinados;
- [x] Journey Map funciona sem screenshot;
- [x] AutoPreview não exige App Adapter;
- [x] Android/Gateway não são dependências implícitas;
- [x] Grant não habilita Module;
- [x] bundles completo/enxuto são reproduzíveis;
- [x] config/distribution v1 continuam migráveis e rollbackáveis;
- [x] gates históricos e novos estão verdes;
- [x] norma e results correspondem à evidência atual.
