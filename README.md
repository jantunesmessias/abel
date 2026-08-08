# FlutterDevExKit

Implementação Dart/Flutter local-first para documentar, executar e comprovar
jornadas de produto sobre aplicativos reais. A arquitetura normativa vive em
[`ARCHITECTURE.md`](ARCHITECTURE.md).

## Estado

P0–V3 estão implementados e aprovados para a matriz local web/Android. V4
hosted multi-tenant e V5 remote runtime web/Android também estão implementados
com contracts, PostgreSQL/RLS, recovery, Helm, scheduler/worker, streaming e
cleanup executáveis.

Implementação não é confundida com certificação de infraestrutura: a claim V4
`production-certified` ainda exige PITR/object store/IdP/cluster reais; a claim
V5 `device-farm-certified` exige CNI/admission/Gateway API e pool Linux/KVM
reais. Os gates e resultados estão em
[`ARCHITECTURE.md`](ARCHITECTURE.md),
[`v4-results.md`](docs/architecture/v4-results.md) e
[`v5-results.md`](docs/architecture/v5-results.md). A matriz completa
requisito→evidência está em
[`master-plan-audit.md`](docs/architecture/master-plan-audit.md).

A composição modular MC0–MC6 e o vertical AutoPreview AP0–AP4 também estão
implementados. Um único `ResolvedKitPlan` seleciona Modules/Providers e governa
CLI, Host, Studio e Distribution; Module desabilitado não registra superfície
nem inicia recurso. Resultados:
[`modular-composition-results.md`](docs/architecture/modular-composition-results.md)
e [`auto-preview-results.md`](docs/architecture/auto-preview-results.md).

Essas claims continuam escopadas: MC6 comprova o seam de contributions/rotas e
AP4 a projeção visual tipada em memória. O vertical SR0–SR9 agora entrega a
cadeia operacional completa na matriz local: `devex dev` supervisiona Host e
Studio, a SPA Jaspr consome catálogo/Evidence reais por handles, o Journey Map
funciona com/sem screenshots e AutoPreview percorre
stale→collect→fresh. Plano e evidência:
[`devex-studio-reconstruction-plan.md`](docs/architecture/devex-studio-reconstruction-plan.md)
e
[`devex-studio-reconstruction-results.md`](docs/architecture/devex-studio-reconstruction-results.md).

## Composição do Kit

Profiles built-in:

| Profile | Uso |
|---------|-----|
| `journey-preview` | Studio + catálogo + Journey Map + coleta AutoPreview estrutural |
| `journey-android` | Studio + Journey Map + provider Android independente; coleta Studio ainda não anunciada |
| `gateway-lab` | Sessions + Gateway + Studio shell |
| `gateway-lab-headless` | Sessions + Gateway sem Studio |
| `full-local` | superfície local completa |
| `legacy-full-local-v1` | compatibilidade da configuração v1 |

O único Studio é `apps/devex_studio`, em Jaspr client-side. O profile decide se
as contributions `studio.shell`, `studio.journey-map`, `studio.target`,
`studio.gateway`, `studio.remote-session` e `studio.hosted` existem; não há
seleção de renderer nem fallback Flutter. `devex_ui_system` é Jaspr/HTML/CSS e
`devex_ux_system` permanece Dart puro. Flutter continua somente nos consumers e
adapters permitidos, incluindo `devex_preview`.

Detalhes: [matriz de capabilities](docs/architecture/studio-capability-matrix.md)
e [guia para contribuidores](docs/operations/studio-contributing.md).

Exemplo mínimo `devex.yaml` v2:

```yaml
schemaVersion: 2
content:
  root: .devex
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

Inspeção e migração:

```bash
devex modules list --profile journey-preview
devex modules explain --profile journey-preview \
  --module evidence.auto-preview
devex modules doctor --profile journey-preview
devex config migrate --to 2 --dry-run
devex config migrate --to 2 --apply
```

Config v1 continua legível e é traduzida em memória pelo mesmo resolver. A
migração aplicada é atômica e preserva `devex.yaml.v1.bak`.

## AutoPreview

`AutoPreview`/`AutoMultiPreview` especializam as annotations oficiais do
Flutter. A mesma factory serve ao Widget Previewer interativo e ao compiler
DevEx; screenshots são gerados separadamente por um runner `flutter test`
isolado, pois o Previewer não possui API pública de exportação.

```bash
devex evidence collect-previews \
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

Limites preservados: `flutter-test` é somente `structural`; no Flutter 3.44.8
o detector LSP do Previewer falha e o workaround comprovado é
`--legacy-preview-detection`; Widget Previewer continua interativo e não exporta
PNG. Allowlist, timeout e staging não provam containment: rede/memória dependem
do sandbox do host e, sem prova, o fingerprint permanece
`NetworkContainment.unconstrained`. AutoPreview não prova plugins nativos, SO,
permissões ou teclado.

## Showcase completo

`examples/` contém um consumer deliberadamente genérico, mas executável de
ponta a ponta: a aplicação Flutter **Delivery Lab**, uma API Shelf própria,
catálogo com cinco Scenarios, AutoPreviews, ReviewGuide, LaunchProfile web e
três presets de Gateway. O profile default é `full-local`; os 17 Modules
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
flutter pub get
./tool/check.sh
./tool/verify_v01_gateway.sh
./tool/verify_v02_containment.sh
./tool/verify_v03_distribution.sh
./tool/verify_modular_distribution.sh
./tool/verify_auto_preview.sh
./tool/verify_studio_vertical.sh
./tool/benchmark_journey_map.sh
./tool/verify_v1_release.sh
./tool/verify_v2.sh
./tool/verify_v3.sh
./tool/verify_kubernetes_manifests.sh
./tool/verify_supply_chain.sh
```

O check executa formatação, análise estrita, fitness functions e as suites Dart,
Jaspr/Google Chrome, Flutter dos adapters/consumers, Host, Gateway, hosted,
remote worker e session gateway. Para hot reload do Studio, use `jaspr serve`
com o bootstrap `/devex/bootstrap.json`, conforme
[`studio-startup.md`](docs/operations/studio-startup.md); o build de distribuição
é `jaspr build` e não carrega Flutter no Studio.

Um consumer pode executar o fluxo local de Evidence a partir de seu diretorio:

```bash
dart run ../../apps/devex_cli/bin/devex.dart --json validate
dart run ../../apps/devex_cli/bin/devex.dart --json capture \
  --input /caminho/captura.png \
  --launch-profile sample-web \
  --target local-chrome \
  --renderer canvaskit
dart run ../../apps/devex_cli/bin/devex.dart --json release build
```

`capture` também é exercitado pela integração Session/App Adapter e pelos
providers de evidence; uma captura observada não vira Approval automaticamente.

Um consumer pode declarar `GatewayScope`, `GatewayPreset`, `GatewayRoute` e
`GatewayFixture` no content root. `gateway run <preset-ref>` compila a autoria,
materializa fixtures sinteticas no CAS e anexa o sidecar a uma Session pronta;
os detalhes e limites estao em `docs/architecture/v01-results.md`.

No V0.2, routes `upstreamOnly` usam apenas profiles allowlisted de
`devex.local.yaml`. `gateway doctor` verifica a configuracao local sem imprimir
URLs/handles; `gateway sync --provider <id>` publica somente provider generico
normalizado. A prova Chromium de `targetEnforced`, seus requisitos e limites
estao em `docs/architecture/v02-results.md`.

Adoption é preview-first (`init`, `adoption-report`, `detach`). Evidence de
testes usa `evidence collect-tests`; bundles standalone usam `distribution
verify-bundle/install/status/rollback/migrate-state`. O rehearsal completo esta
em `docs/architecture/v03-results.md`.

V4 adiciona `auth login/logout/status`, `workspace link/push/pull` e `publish`.
V5 é acionado por `RemoteExecutionRequest` tipado; worker aceita somente web
build ou APK por digest — nunca source ou comando arbitrário. O contrato de
wire/estado está em
[`hosted-remote-v1.md`](docs/contracts/hosted-remote-v1.md).
