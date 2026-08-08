# Abel

Implementação Dart/Flutter local-first para documentar, executar e comprovar
jornadas de produto sobre aplicativos reais. A arquitetura normativa vive em
[`ARCHITECTURE.md`](ARCHITECTURE.md).

## Estado

A plataforma local, o Gateway, a distribuição e a evidência web/Android estão
implementados e aprovados na matriz local. O control plane multi-tenant e a
execução remota web/Android também possuem contracts, PostgreSQL/RLS, recovery,
Helm, scheduler/worker, streaming e cleanup executáveis.

Implementação não é confundida com certificação de infraestrutura: a claim do control plane
`production-certified` ainda exige PITR/object store/IdP/cluster reais; a claim
de execução remota `device-farm-certified` exige CNI/admission/Gateway API e pool Linux/KVM
reais. Os gates e resultados estão em
[`ARCHITECTURE.md`](ARCHITECTURE.md),
[`hosted-control-plane-results.md`](docs/architecture/hosted-control-plane-results.md) e
[`remote-execution-results.md`](docs/architecture/remote-execution-results.md). A matriz completa
requisito→evidência está em
[`platform-capability-audit.md`](docs/architecture/platform-capability-audit.md).

A composição modular e o vertical AutoPreview também estão implementados. Um
único `ResolvedKitPlan` seleciona Modules/Providers e governa
CLI, Host, Studio e Distribution; Module desabilitado não registra superfície
nem inicia recurso. Resultados:
[`modular-composition-results.md`](docs/architecture/modular-composition-results.md)
e [`auto-preview-results.md`](docs/architecture/auto-preview-results.md).

Essas claims continuam escopadas: a composição comprova o seam de
contributions/rotas, enquanto o AutoPreview comprova a projeção visual tipada.
A reconstrução operacional do Studio entrega a cadeia completa na matriz local:
`workspace dev` supervisiona Host e Studio, a SPA Jaspr consome
catálogo/Evidence reais por handles, o Journey Map funciona com/sem screenshots
e AutoPreview percorre stale→collect→fresh. Plano e evidência:
[`studio-reconstruction-plan.md`](docs/architecture/studio-reconstruction-plan.md)
e
[`studio-reconstruction-results.md`](docs/architecture/studio-reconstruction-results.md).

## Composição do Kit

Profiles built-in:

| Profile | Uso |
|---------|-----|
| `journey-preview` | Studio + catálogo + Journey Map + coleta AutoPreview estrutural |
| `journey-android` | Studio + Journey Map + provider Android independente; coleta Studio ainda não anunciada |
| `gateway-lab` | Sessions + Gateway + Studio shell |
| `gateway-lab-headless` | Sessions + Gateway sem Studio |
| `full-local` | superfície local completa |

O único Studio é `apps/studio`, em Jaspr client-side. O profile decide se
as contributions `studio.shell`, `studio.journey-map`, `studio.target`,
`studio.gateway`, `studio.remote-session` e `studio.hosted` existem; não há
seleção de renderer nem fallback Flutter. `studio_ui` é Jaspr/HTML/CSS e
`interaction_model` permanece Dart puro. Flutter continua somente nos consumers e
adapters permitidos, incluindo `flutter_preview`.

Detalhes: [matriz de capabilities](docs/architecture/studio-capability-matrix.md)
e [guia para contribuidores](docs/operations/studio-contributing.md).

Exemplo mínimo `workspace.yaml` v2:

```yaml
schemaVersion: 2
content:
  root: .experience
workspace:
  id: sample
applications:
  sample:
    root: .
    target: web
kit:
  profile: journey-preview
  modules:
    evidence.auto-preview:
      enabled: true
      settings:
        renderer: flutter-test
        capturePolicy: static-v1
  providerBindings: []
  startupPolicy: fail-required-v1
```

Inspeção da composição:

```bash
workspace modules list --profile journey-preview
workspace modules explain --profile journey-preview \
  --module evidence.auto-preview
workspace modules doctor --profile journey-preview
```

O arquivo principal `workspace.yaml` exige `schemaVersion: 2`. A configuração
local do Gateway permanece um documento separado e ignorado pelo Git; ela não
é um fallback para versões anteriores do arquivo principal.

## AutoPreview

`AutoPreview`/`AutoMultiPreview` especializam as annotations oficiais do
Flutter. A mesma factory serve ao Widget Previewer interativo e ao compiler
desenvolvimento; screenshots são gerados separadamente por um runner `flutter test`
isolado, pois o Previewer não possui API pública de exportação.

```bash
workspace evidence collect-previews \
  --application sample \
  --profile journey-preview \
  --synthetic-data-confirmed
```

| Provider | Custo/foco | Claim visual |
|----------|------------|--------------|
| AutoPreview | factory Flutter isolada, sem Session/App Adapter | `structural` |
| App Adapter | aplicação controlada em execução | `simulated`, conforme fingerprint |
| Android | emulador/dispositivo gerenciado | `hostNative`; nunca attested implicitamente |

O Journey Map funciona sem screenshot. Captura `failed`, `stale`, `missing`,
`unsupported` ou `policyDenied` permanece explícita e nunca é substituída
silenciosamente.

Limites preservados: `flutter-test` é somente `structural`; no Flutter 3.47.0
o Previewer oficial falha neste Pub Workspace e o antigo detector legado não
está mais disponível. O provider de auto-preview continua sendo o caminho comprovado de
captura; Widget Previewer é interativo e não exporta PNG. Allowlist, timeout e
staging não provam containment: rede/memória dependem do sandbox do host e, sem
prova, o fingerprint permanece
`NetworkContainment.unconstrained`. AutoPreview não prova plugins nativos, SO,
permissões ou teclado.

## Showcase completo

`examples/` contém um consumer deliberadamente genérico, mas executável de
ponta a ponta: a aplicação Flutter **Delivery Lab**, uma API Shelf própria,
catálogo com oito Scenarios, dez AutoPreviews, ReviewGuide, LaunchProfile web e
quatro presets de Gateway. O profile default é `full-local`; os 28 Modules
empacotados ficam habilitados no mesmo `ResolvedKitPlan`.

```bash
dart run examples/tool/showcase.dart
```

O launcher compila catálogo/fixtures no CAS, prepara o Target Flutter web
release quando necessário, inicia API, Host e Studio em loopback, abre o browser
e mantém ownership dos processos até `Ctrl+C`. Um watchdog reinicia o stack com
backoff quando um child cai ou perde health repetidamente. Use `--check` para
validar sem abrir listeners, `--build-studio` para reconstruir os assets Jaspr,
`--build-target` para forçar o Target release e `--no-open` para não abrir outra
janela. Ativar um Module não falsifica readiness: Android depende de SDK/AVD, e
hosted/remote dependem de credenciais e infraestrutura externas.

Runbook e matriz do exemplo: [`examples/README.md`](examples/README.md).

## Comandos de desenvolvimento

```bash
dart pub global activate melos 8.3.0
melos bootstrap
melos run check
melos run ci
```

O Melos 8.3.0 está fixado também no `pubspec.yaml` e no lockfile. A configuração
fica no `pubspec.yaml` raiz, junto ao Pub Workspace, sem uma segunda lista de
packages. `melos run check` executa formatação, análise estrita, fitness
functions, testes Dart/Flutter, build do Studio, containment e o consumer de
referência. `melos run ci` acrescenta os verticais portáteis usados pelo CI.

Gates focados permanecem disponíveis pelo mesmo entrypoint:

```bash
melos run studio:browser
melos run scenario-lab
melos run authoring-review
melos run motion-context
melos run mcp-experience
melos run auto-preview
melos run gateway:benchmark
melos run gateway:containment
melos run distribution
melos run distribution:external
melos run web:wasm
melos run schemas
melos run kubernetes
melos run supply-chain
melos run source-automation
melos run android:evidence
melos run release
```

Para hot reload do Studio, use `jaspr serve` com o bootstrap
`/studio/bootstrap.json`, conforme
[`studio-startup.md`](docs/operations/studio-startup.md); o build de distribuição
é `jaspr build` e não carrega Flutter no Studio.

O gate de escala gera dois workspaces externos determinísticos, cada um com
2.000 cenários/nós e 20.000 transições/arestas, compara os exports e abre a
Journey profunda no Chrome real. Budgets, ambiente, medições e limites da prova
executada estão em
[`scale-accessibility-security-results.md`](docs/architecture/scale-accessibility-security-results.md).

Um consumer pode executar o fluxo local de Evidence a partir de seu diretorio:

```bash
dart run ../../apps/workspace_cli/bin/workspace.dart --json validate
dart run ../../apps/workspace_cli/bin/workspace.dart --json capture \
  --input /caminho/captura.png \
  --launch-profile sample-web \
  --target local-chrome \
  --renderer canvaskit
dart run ../../apps/workspace_cli/bin/workspace.dart --json release build
```

`capture` também é exercitado pela integração Session/App Adapter e pelos
providers de evidence; uma captura observada não vira Approval automaticamente.

Um consumer pode declarar `GatewayScope`, `GatewayPreset`, `GatewayRoute` e
`GatewayFixture` no content root. `gateway run <preset-ref>` compila a autoria,
materializa fixtures sinteticas no CAS e anexa o sidecar a uma Session pronta;
os detalhes e limites estao em `docs/architecture/gateway-isolation-results.md`.

No Gateway containment, routes `upstreamOnly` usam apenas profiles allowlisted de
`workspace.local.yaml`. `gateway doctor` verifica a configuracao local sem imprimir
URLs/handles; `gateway sync --provider <id>` publica somente provider generico
normalizado. A prova Chromium de `targetEnforced`, seus requisitos e limites
estao em `docs/architecture/gateway-containment-results.md`.

Adoption é preview-first (`init`, `adoption-report`, `detach`). Evidence de
testes usa `evidence collect-tests`; bundles standalone usam `distribution
verify-bundle/compose-consumer/install/status/rollback`. O
rehearsal standalone está em `docs/architecture/distribution-lifecycle-results.md`; a composição
externa versionada está em
[`consumer-distribution.md`](docs/contracts/consumer-distribution.md).

hosted control plane adiciona `auth login/logout/status`, `workspace link/push/pull` e `publish`.
remote execution é acionado por `RemoteExecutionRequest` tipado; worker aceita somente web
build ou APK por digest — nunca source ou comando arbitrário. O contrato de
wire/estado está em
[`hosted-remote.md`](docs/contracts/hosted-remote.md).
