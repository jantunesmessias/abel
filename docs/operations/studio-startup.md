# Operação local do Abel Studio

Status: runbook Jaspr validado em 2026-08-11.

O Studio é uma SPA Jaspr client-side. O Host e o Studio usam origens loopback
separadas durante hot reload; em distribuição, o Host serve os assets estáticos
Jaspr. Não existe comando Flutter para construir ou servir o Studio.

## Pré-requisitos

```bash
melos bootstrap
dart run tools/gates/architecture_guard.dart
melos run studio:build
```

Flutter continua necessário no workspace para consumers e AutoPreview, não
para `apps/studio` ou `studio_ui`.

## Hot reload em duas origens

Terminal 1, no consumer `examples/sample_flutter`:

```bash
dart ../../apps/workspace_cli/bin/workspace.dart --json dev \
  --config workspace.yaml \
  --profile journey-preview \
  --host-port 39011 \
  --studio-dev-origin http://127.0.0.1:39012 \
  --no-open
```

Terminal 2, em `apps/studio`:

```bash
jaspr serve --release \
  --port 39012 \
  --dart-define=STUDIO_BOOTSTRAP_URL=http://127.0.0.1:39011/studio/bootstrap.json
```

Abra a rota do Studio em `http://127.0.0.1:39012`. O bootstrap correto é
exatamente `/studio/bootstrap.json`; `/studio/bootstrap` não existe.

O Host autoriza somente o `Origin` declarado por `--studio-dev-origin`. Um
`curl` sem `Origin` receber `403` é comportamento esperado. Probe manual:

```bash
curl -i \
  -H 'Origin: http://127.0.0.1:39012' \
  http://127.0.0.1:39011/studio/bootstrap.json
```

Nunca registre o body completo: ele contém o token efêmero da sessão RPC.

## Build e distribuição

Pare `jaspr serve` antes de um build release no mesmo checkout; o build daemon
do Jaspr é exclusivo por package.

```bash
melos run studio:build
```

O resultado fica em `apps/studio/build/jaspr`. O builder de distribuição
executa esse mesmo comando sob lock, copia apenas regular files, rejeita links e
registra todos os digests em `distribution.json`.

```bash
melos run distribution
```

Profiles sem qualquer module na surface `studio` não geram diretório `studio/`,
entrypoint, listener ou browser open.

## Readiness e recuperação

Sequência de readiness:

1. o plan resolve modules e contributions;
2. Host sobe RPC/resource server;
3. bootstrap responde somente ao origin autorizado;
4. Studio busca o bootstrap, inicializa RPC e abre um `WorkspaceSnapshot` por
   handle validado;
5. a UI anuncia `Host conectado`.

Se o Host cair após um snapshot válido, a UI conserva o snapshot como `stale`,
fecha o transporte anterior e tenta uma nova conexão. A falha da primeira
conexão também entra no retry automático; `Reconectar` permanece disponível
como ação imediata. HTML recebido por endpoint incorreto é diagnosticado como
resposta inválida e nunca interpretado como workspace JSON.

Se o Studio cair durante recompilação:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Origin: http://127.0.0.1:39012' \
  http://127.0.0.1:39011/studio/bootstrap.json
```

Um `200` confirma que o Host está vivo; reinicie somente `jaspr serve`. Não é
necessário reiniciar o Host nem invalidar Evidence.

## CSP, CORS e resources

- release: `script-src 'self'`, sem CDN e sem `unsafe-inline`;
- hot reload: o `index.html` contém somente o hash exato do loader DWDS usado
  pelo Jaspr 0.23.3;
- bootstrap/RPC/resources aceitam somente a origem autorizada;
- workspace e PNG usam handles temporários com purpose, origin, media type,
  tamanho, expiry e digest verificados;
- o browser renderiza PNG a partir de Blob URL local e o revoga no dispose;
- target e web Remote usam iframe sandboxed com `no-referrer` e origin separado.
- o target web recebe sessão/nonce/origem controladora por fragmento efêmero;
  o servidor do consumer não recebe esse bootstrap e o App Adapter falha
  fechado para `postMessage` divergente.

Alterar Jaspr/DWDS exige recalcular o hash e reexecutar o gate CSP; nunca troque
o hash por `unsafe-inline`.

## Diagnóstico rápido

| Sintoma | Causa provável | Ação |
|---|---|---|
| `Unexpected token '<'` | endpoint de bootstrap apontou para HTML | use `/studio/bootstrap.json` |
| bootstrap `403` | Origin ausente ou divergente | alinhe `--studio-dev-origin` e porta Jaspr |
| Studio vazio após rebuild | `jaspr serve` encerrou ou ainda compila | aguarde `Serving at` e recarregue |
| CSP bloqueia script inline | hash DWDS mudou | atualizar hash exato e reexecutar Chrome gate |
| imagem não aparece | handle expirado/digest inválido | atualizar workspace; não usar URI crua |
| build trava com serve ativo | dois build daemons no mesmo package | pare o serve, build, reinicie |
| coleta nunca termina | runner/fixture/animação | cancelar; consultar diagnostics e timeout |

## Gate browser

O gate oficial usa Google Chrome via Chrome DevTools Protocol, sem ChromeDriver
ou Playwright:

```bash
./tools/verify/verify_studio_vertical.sh
./tools/benchmarks/journey_map_benchmark.sh
```

Ele cobre conexão, dois profiles, sete artifacts PNG, dialog nativo/foco,
teclado, alvos mínimos de 48 px, reflow a 200%, redução de motion, AX tree,
logs, windowing/interaction e stale→fresh. AutoPreview `flutter-test` continua
`structural`; no Flutter 3.47.0 o Widget Previewer apresenta uma regressão neste
Pub Workspace e o fluxo interativo permanece bloqueado. Ele não é o exportador de PNG.
Contenção portátil de rede/memória depende do sandbox do host.
