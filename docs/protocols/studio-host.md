# Protocolo Studio ↔ Host v1

Status: ativo e exercitado pelo Studio Jaspr em 2026-08-11. Decisões:
ADR-0014, ADR-0016 e ADR-0018.

## Autoridade e transporte

O Host é a única autoridade de workspace, catálogo, CAS, processes e devices.
O Studio usa:

- HTTP same-origin para assets/bootstrap empacotados, ou CORS de origem exata
  para o bootstrap do modo de hot reload;
- WebSocket JSON-RPC para control plane bounded;
- HTTP scoped para snapshots e artifacts grandes.

O protocolo v1 opera apenas em listeners loopback. Host e Studio têm origins
distintos; o Host aceita exatamente o origin do Studio iniciado pelo mesmo
supervisor.

## Startup

`workspace dev` resolve o `ResolvedKitPlan` e compila o catálogo antes de iniciar
listeners. Se `studio.shell` estiver enabled, existem dois modos mutuamente
exclusivos:

1. **empacotado:** o supervisor inicia o servidor de assets, autoriza seu origin
   no Host e serve bootstrap same-origin;
2. **hot reload:** `--studio-dev-origin` autoriza a origem loopback externa do
   servidor Jaspr e o Host serve somente o bootstrap de desenvolvimento com
   CORS para esse origin exato.

Nos dois casos o bootstrap só fica válido depois do manifest efetivo. O
supervisor publica readiness e, salvo `--no-open`, tenta abrir o origin do
Studio.

O bootstrap é obtido por:

```http
GET /studio/bootstrap.json
```

Ele contém `protocolVersion`, `hostOrigin`, `rpcPath`, token de sessão e
`EffectiveKitManifest`. A resposta usa `Cache-Control: no-store`; o token não
aparece na URL, output do CLI, arquivo de plan ou logs.

No modo empacotado, `Sec-Fetch-Site: same-origin` é obrigatório e CORS não é
habilitado. No hot reload, a requisição deve carregar `Origin` exatamente igual
a `--studio-dev-origin`; a resposta usa `Access-Control-Allow-Origin` exato e
`Vary: Origin`. Query string falha nos dois modos. A URL absoluta do bootstrap
é configuração pública de transporte; o token continua somente no body.

Sem `studio.shell`, assets, listener e bootstrap do Studio não são criados. Um
Host headless ainda recebe um origin explicitamente allowlisted para clientes
RPC autorizados.

## Handshake JSON-RPC

O Studio abre `/rpc` sem query com `Origin` exato e envia primeiro:

```json
{
  "jsonrpc": "2.0",
  "id": "initialize-1",
  "method": "workspace.initialize",
  "params": {
    "protocolVersion": 1,
    "sessionToken": "credencial-efemera-do-bootstrap"
  }
}
```

O token só existe no body `no-store` do bootstrap e nos parâmetros do primeiro
RPC; URL, output do CLI, `ResolvedKitPlan`, logs e resources não o carregam. O
Host rejeita query em `/rpc`, compara o token em tempo constante e só marca a
conexão como inicializada após versão e token exatos.

Antes do initialize, todos os demais métodos, inclusive `ping` e `resume`,
retornam `-32001`. Events só são enviados a conexões inicializadas. A resposta
informa capabilities efetivas, cursor, heartbeat e limite de mensagem. Frames
não texto e mensagens acima de 64 KiB fecham a conexão. Respostas maiores que
o limite viram erro bounded; não são truncadas silenciosamente.

Métodos core:

```text
workspace.initialize
connection.resume
connection.ping
composition.describe
composition.health
```

Métodos do Module `catalog`:

```text
workspace.describe
workspace.open
workspace.refresh
experience.describe
experience.open
experience.content.describe
experience.content.open
```

`describe` retorna revisão e digests, nunca o snapshot inteiro. `open` aceita
`expectedRevision` e retorna um `ResourceHandle`. Divergência de revisão exige
novo describe. `refresh` recompila o catálogo e atualiza as projeções dos
providers de forma fail-closed. Mudança de catálogo, source/assets/toolchain,
Variant ou Evidence incrementa a revisão e publica `workspace.changed`.

`experience.describe/open` preserva o transporte v1 adjacente de
`ExperienceTopologyBundle`. Clientes novos usam o par
`experience.content.describe/open`: `open` exige exatamente
`expectedRevision`, `catalogDigest` e `contentSetDigest`, captura uma geração e
concede em lote handles separados para `WorkspaceSnapshot`,
`ExperienceTopologyBundle` e `ScenarioFacetManifest` quando presentes. Quota,
input inválido ou falha de alocação não publica subset do lote. O digest do
content-set liga os digests de conteúdo; a revisão continua fencing separado.

Mudança observável de qualquer documento da geração, Variant/Evidence ou
renovação de handle visual publica `experience.content.changed`. O Studio
só troca sua geração depois de validar todos os recursos. A capability pair
incompleta é erro; Host legado sem o par continua pelo caminho v1 anterior.

RPCs do AutoPreview, registrados somente quando o Module está efetivo:

```text
preview.collect
preview.status
preview.cancel
```

`collect` exige `applicationId`, confirmação explícita de dados sintéticos e
filtros opcionais de Scenario/Variant. Ele retorna `operationId` e progresso
bounded. `status` observa o estado terminal; `cancel` propaga cancelamento ao
runner e encerra o subprocesso ativo. Falha de um descriptor não apaga
capturas independentes. O evento `preview.changed` publica progresso; a
operação só fica terminal depois do refresh autoritativo do snapshot.

## Events e reconnect

Events recebem sequência monotônica no `HostEventJournal`. O Studio persiste
somente o cursor em memória e usa `connection.resume`. Cursor expirado retorna código
`1001`; o cliente marca a view stale, abre novo snapshot e só então volta a
`content`. Event acima do limite não é journaled.

O cliente mantém o último snapshot visível como `stale` durante reconnect. Um
novo `describe` + `open` é obrigatório antes de voltar a `content`; grants
antigos não são tratados como estado atual.

## Resources

Um handle possui URL `/resources/{capability-opaca}`, digest dos bytes, media
type, tamanho, purpose e expiração UTC. Regras v1:

- capability aleatória com ao menos 32 caracteres e sem relação com digest;
- audience Origin exata;
- TTL positivo de no máximo 15 minutos;
- no máximo 64 MiB por resource, 128 MiB e 1.024 grants ativos por Host;
- classification `sensitive` negada ao Studio;
- somente GET, sem query, `Cache-Control: no-store`, CORS exato e `nosniff`;
- bytes copiados na emissão e digest revalidado na entrega;
- expiry, revoke e shutdown removem o grant;
- resource desconhecido/expirado responde como não encontrado.

`workspace-snapshot`, `experience-topology-bundle` e
`scenario-facet-manifest` usam `application/json`. Artifact visual collected
usa `image/png` e purpose `visual-artifact`. O handle nunca contém path de CAS
ou workspace.

## Rotas do Studio

O servidor entrega `index.html` para GETs sem extensão que representam deep
links da SPA Jaspr (`/journeys/...`, `/inventory/...`, `/target`, `/gateway`,
`/reviews`, `/remote/...` e `/hosted`). Um asset com extensão ausente continua
404; não há fallback amplo. O Studio usa path URL strategy e preserva a rota
inicial de produção. Assets e bootstrap recebem `no-store`,
`nosniff`, COOP/referrer policy e CSP; o build Jaspr empacota somente HTML, CSS
e JS locais e não libera scripts de CDN.

## Shutdown

`SIGINT`/`SIGTERM` acionam shutdown reverso: Host revoga resources, fecha RPC,
processes e modules; depois o servidor Studio fecha. O comando não persiste
token e o modo supervisionado não cria diretório de run. `--plan-only` é o modo
explícito que persiste um `ResolvedKitPlan` para inspeção sem iniciar serviços.

## Compatibilidade

Protocol v1, schemas dos documentos e versions de capabilities são eixos
independentes. Um método ou event incompatível exige nova versão de protocolo;
um novo `WorkspaceSnapshot` incompatível exige schema/reader adjacente.
