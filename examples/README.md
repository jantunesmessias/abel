# DevExKit examples

Este diretório é o consumer de referência do DevExKit. Ele é genérico o
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
Gateway: hybrid | offline | failure
        ^
        |
DevEx Host <-> Jaspr Studio
```

## Início rápido

Na raiz do repositório:

```bash
dart run examples/tool/showcase.dart
```

Portas deliberadamente fixas tornam LaunchProfile e App Adapter reproduzíveis:

| Processo | Origem |
|---|---|
| Sample API | `http://127.0.0.1:8181` |
| DevEx Host | `http://127.0.0.1:7367` |
| DevEx Studio | `http://127.0.0.1:7368` |
| Flutter target | `http://127.0.0.1:8080` |

O launcher falha antes de iniciar se uma porta estiver ocupada, cria
`sample_flutter/devex.local.yaml` a partir do template loopback somente quando
ele não existe, compila os três planos do Gateway no CAS e prepara um build web
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

O `devex.yaml` usa `full-local`; `devex modules list` comprova 17 Modules
habilitados. Habilitado não significa pronto ou certificado:

| Grupo | Demonstração local |
|---|---|
| Catalog, Journey Map e Review | 1 Journey, 5 Scenarios, 4 Transitions, 2 execution bindings e 1 ReviewGuide |
| AutoPreview | loading, ready responsivo em três Variants e failure; fidelidade `structural` |
| Sessions + App Adapter | LaunchProfile web real, iframe isolado e captura por `RepaintBoundary` |
| Gateway | passthrough para API real, fixtures offline e resposta 503 determinística |
| Evidence, source e release | comandos públicos usam o mesmo catálogo/CAS do consumer |
| Android | Module ativo; execução exige SDK, AVD e autorização locais |
| Plugins, MCP, hosted e remote | superfícies ativas; operações externas ainda exigem plugin, credencial, control plane ou worker reais |

O entrypoint `sample_flutter/lib/main.dart` não importa DevExKit. O tooling vive
em `tool/devex_main.dart`, previews reutilizam `createSampleApp`, e a mesma
classe `HttpShowcaseApi` é usada no app normal e no target controlado.

## Target e Gateway Lab

O fluxo do Studio é guiado e não pede Session ID ou artifact digest:

1. abra **Target**, mantenha `sample-web` e `http://127.0.0.1:8080`, e inicie a
   Session;
2. abra **Gateway Lab**; a Session proprietária é derivada do Target e os
   presets compilados são fornecidos pelo Host;
3. escolha `showcase-hybrid`, `showcase-offline` ou `showcase-failure` e inicie
   o Gateway;
4. use **Abrir Target com Gateway** para recarregar a aplicação com a
   `dataOrigin` exata do sidecar;
5. atualize o tráfego para inspecionar método, path, decisão e status;
6. pare o Gateway ou pare o Target; ownership da Session remove o sidecar em
   cascata e o Studio desmonta o iframe antes do teardown.

O Target não usa `flutter run`/DDC no caminho interativo. O launcher compila
`tool/devex_main.dart` em release e o LaunchProfile inicia um servidor Dart
consumer-owned confinado ao `build/web`, com health endpoint, SPA fallback,
GET/HEAD, `no-store`, `nosniff` e CSP `frame-ancestors` contendo apenas a origin
do Studio. Quando o Gateway cria uma origin aleatória, o Host injeta essa origin
no Target e o data plane responde CORS exato, sem wildcard.

Presets:

- `showcase-hybrid`: `/v1/dashboard` e mutações passam para `sample_api`; a
  configuração de runtime vem de fixture;
- `showcase-offline`: dashboard e mutação são respondidos somente por fixtures;
- `showcase-failure`: `/v1/dashboard` responde `503` de forma determinística.

URLs concretas existem somente no `devex.local.yaml` ignorado. O catálogo usa
`UpstreamProfileId: showcase-api`; loopback é permitido explicitamente apenas
para este ambiente de desenvolvimento.

## Evidência e validação

No diretório `examples/sample_flutter`:

```bash
dart run ../../apps/devex_cli/bin/devex.dart --json validate
dart run ../../apps/devex_cli/bin/devex.dart --json modules list
dart run ../../apps/devex_cli/bin/devex.dart --json evidence collect-previews \
  --application sample \
  --synthetic-data-confirmed
```

AutoPreview continua sendo evidência `structural`; App Adapter e Android são
providers independentes. Hosted/remote ativos sem infraestrutura não recebem
claims artificiais de readiness.

Detalhes dos componentes:

- [`sample_flutter/README.md`](sample_flutter/README.md)
- [`sample_api/README.md`](sample_api/README.md)
