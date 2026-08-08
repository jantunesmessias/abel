# Plano de refatoração — composição modular e AutoPreview

Status: composição modular e AutoPreview implementados em 2026-08-10. Os gates
iniciais do Studio e da projeção do Journey Map não incluíam a integração
operacional completa, comprovada posteriormente pela reconstrução do Studio.

Este documento operacional implementa ADR-0012 sem reescrever a evidência
histórica anterior. O objetivo é tornar o Abel um Kit configurável por Module,
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

## 2. Baseline da composição

Worktree inicial:

- branch `main` um commit ahead e um behind de `origin/main`;
- `ARCHITECTURE.md` possui mudanças preexistentes FOUNDATION–remote execution;
- a maior parte da implementação está presente como conteúdo não rastreado;
- essas mudanças são preservadas e não atribuídas a este refactor.

Gate executado em 2026-08-10:

```text
melos run check → exit 0
```

Cobertura observada: format, analyze fatal, architecture/supply-chain,
contracts, engine, runtime, Flutter adapter, Studio VM/Chromium, CLI, Host,
Gateway, hosted, remote, contenção Linux netns e consumers `sample_flutter` e
`friction_flutter`.

## 3. Gates e ordem crítica

```text
baseline → contratos → configuração e resolver → kernel e lifecycle
                                      ├──→ CLI
                                      ├──→ Host, Sessions e Gateway
                                      └──→ scanner, runner e Evidence do AutoPreview
Host, Sessions e Gateway → composição do Studio
Evidence do AutoPreview + composição do Studio → projeção no Journey Map
depois → Android/restante → distribuição → estabilização
```

### baseline da composição — baseline e decisão

- [x] registrar worktree e gate existente;
- [x] criar ADR-0012;
- [x] criar este plano;
- [x] atualizar princípios, riscos, roadmap e registro normativo;
- [x] ratificar a taxonomia; IDs e dependency graph serão codificados no
  primeiro fixture de contracts de composição.

### contratos de composição — contracts e schemas

Adicionar em `experience_contracts`:

- `ModuleId`, `ModuleCapabilityRef`, `ModuleRequirement`;
- `ModuleDescriptor`, `ModuleCatalog`;
- `KitProfile`, `KitSelection`, `ProviderBinding`;
- `ResolvedKitPlan`, `EffectiveKitManifest`;
- estados, health e diagnósticos fechados.

Schemas:

- `schemas/distribution/kit-composition.schema.json`;
- `schemas/evidence/preview-capture.schema.json` nos contratos do AutoPreview;
- `schemas/distribution/consumer-config.schema.json`;
- `schemas/distribution/distribution-descriptor.schema.json`;
- `schemas/distribution/distribution-release.schema.json`.

Gate: round-trip fechado, canonicalização, digest, ordem estável, fixtures
válidas/inválidas e versões adjacentes, sem mudança funcional.

### configuração e resolver modular — config v2 e resolver

`experience_engine` recebe normalizer, profile expander, provider resolution,
conflicts/cycles/platform checks e topological order determinística.
`execution_runtime` recebe `WorkspaceConfigurationLoader`; filesystem discovery e
interpretação tornam-se responsabilidades separadas. Loaders de Gateway e
providers deixam de reler configuração por conta própria.

O arquivo principal canônico atravessa um único resolver. Precedência: Kernel
< Distribution < Profile < Workspace < local < startup.

Gate: schema canônico obrigatório, digest independente de ordem, paths
confinados, secrets literais rejeitados e toda falha anterior a efeitos.

### kernel e lifecycle modular — Kernel e lifecycle

Implementar catálogo/factory registry compile-time, `ModuleContext`,
contributions, lifecycle coordinator e health registry. Não existe reflection,
dynamic Dart loading nem service locator irrestrito.

Gate: módulo desabilitado produz zero comando/RPC/rota/processo/porta/artifact;
failure injection desfaz startup em ordem inversa e não deixa orphan.

### CLI modular — CLI

Separar bootstrap parser, plan loader, command registry e contribuições por
módulo. Bootstrap commands funcionam sem workspace: `version`, `init`,
distribution e `modules`.

Comandos novos:

```text
workspace modules list
workspace modules explain
workspace modules doctor
```

Gate: help e dispatch derivados do plano, machine output v1 compatível e erro
estruturado para Module indisponível.

### Host, Sessions e Gateway modulares — Host, Sessions, Capture e Gateway

O Host valida um `ResolvedKitPlan` transportado por staging autorizado, monta
RPC contributions e publica `EffectiveKitManifest`. Kernel RPC:
`composition.describe`, `composition.health` e evento `composition.changed`.

Extrair na ordem Sessions, App Adapter Capture e Gateway. Gate: combinações
com/sem Gateway, vinte ciclos, failure injection, shutdown concorrente, child
death e zero resíduo.

### composição do Studio — Studio

Adicionar repository do manifest e contributions de navegação/rotas. O Studio
não inicia módulos. Deep link indisponível recebe estado estruturado; Grant e
Module availability continuam ortogonais.

Gate: Journey on/off, sem/com visual Evidence, grants cruzados, teclado, screen
reader, reconnect e um único plan digest.

Escopo comprovado: repository seam, routes/contributions condicionais e
projeção in-memory. Shell completo, catálogo real vindo do Host, resource
handles, inspector/provider selection e startup supervisionado não fazem parte
de composição do Studio; pertencem a
`docs/architecture/studio-reconstruction-plan.md`.

## 4. AutoPreview

### spike do AutoPreview — spike

No `sample_flutter`, usar uma factory real top-level com `@AutoPreview`, provar
Widget Previewer oficial, descoberta Analyzer e duas capturas via `flutter
test`, sem `build_runner`, geração em `lib/` ou import Abel no `main.dart`.

### contratos do AutoPreview — API e contracts

Criar package `flutter_preview` dependente apenas de Flutter e contracts.
Implementar `AutoPreview`, `AutoMultiPreview`, `AutoPreviewVariant` e marker de
compatibilidade Flutter 3.44.x. Contracts: `Variant`, descriptors, manifests,
capture items/report, status e capture key. Ratificar ADR-0013.

### scanner e compiler do AutoPreview — scanner/compiler

Analyzer e filesystem ficam no runtime; normalização permanece no engine.
Suporte inicial: função pública top-level, retorno Widget/WidgetBuilder,
argumentos const, `lib/**/*.dart`, IDs explícitos e registry efêmero somente em
`.dart_tool`.

### runner e Evidence do AutoPreview — runner/Evidence

Scaffold efêmero `flutter test`, stabilization policy limitada,
RepaintBoundary, subprocesso, env allowlist, no secrets, sandbox/rede quando
disponível, quotas, failure isolation, PNG inspector, CAS e EvidenceProvider.

### projeção do AutoPreview no Journey Map — Journey Map

Projetar Scenario × Variant para artifact handle, provider, fidelity,
freshness e diagnóstico. Studio nunca recebe CAS path. LOD, placeholders e
último artifact válido mantêm estado explícito. Source Impact invalida apenas
previews afetados.

Escopo comprovado: contracts/projector e estados exercitados em teste. A cadeia
operacional CAS → Host → Studio e a apresentação em device frames pertencem à
integração operacional do Studio.

## 5. Migração e distribuição

Após Gateway e AutoPreview, extrair Android target/evidence, test evidence,
source impact, plugins, MCP, hosted/remote clients e release local. Cada
extração remove o registro estático correspondente, testa ausência e mantém o
profile legado.

Distribution começa completa/configurável e depois aceita bundles enxutos.
Manifest registra modules, profiles, components, files e ModuleCatalog digest.
CLI é obrigatória; Host, Gateway e Studio são condicionais. Builders geram
entrypoint apenas em `.dart_tool` e provam rebuild byte-idêntico, install,
update e rollback.

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
tools/verify/verify_auto_preview.sh
tools/verify/verify_modular_distribution.sh
tools/verify/verify_distribution_lifecycle.sh
```

Gates FOUNDATION–remote execution existentes permanecem; gate novo não substitui evidência anterior.

## 7. Atualização documental

Criar durante o vertical correspondente:

- ADR-0013 AutoPreview;
- `docs/contracts/module-composition.md`;
- `docs/contracts/consumer-configuration.md`;
- `docs/contracts/distribution-release.md`;
- `docs/contracts/auto-preview.md`;
- `docs/quality/module-conformance.md`;
- `docs/quality/auto-preview-conformance.md`;
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
AutoPreview, App Adapter e Android. Resultados anteriores não têm claims alteradas.

## 8. Definition of Done

- [x] configuração e distribuição convergem para resolvers canônicos;
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
