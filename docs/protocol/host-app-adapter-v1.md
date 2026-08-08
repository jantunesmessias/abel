# Host e App Adapter protocol v1

## Transporte e autenticacao

- Host escuta apenas em loopback e publica `/health` e `/rpc`.
- `/rpc` usa JSON-RPC 2.0 sobre WebSocket.
- O cliente apresenta token de sessao de alta entropia e `Origin` exato. Ambos
  sao verificados antes do upgrade; comparacao do token nao depende de early
  return por byte.
- Target web usa `postMessage` com origin, `source`, session ID, nonce e
  sequencia exatos. Wildcard origin e proibido.

## Negociacao

`initialize` antecede operacoes de dominio e devolve versao, capabilities e
limites efetivos. Versao incompatível e capability ausente falham antes de
qualquer efeito. `ping` e seguro e idempotente.

## Replay e lifecycle

- Eventos recebem sequencia monotona e ficam num journal bounded.
- `resume` aceita o ultimo cursor observado e devolve eventos posteriores.
- Cursor expirado produz falha explicita e exige novo snapshot.
- Shutdown encerra conexoes, cancela subscriptions e libera o socket.
- Frames nao suportados e mensagens acima do limite fecham a conexao com
  codigos da aplicacao e sem manter sessao residual.

### Documentos de lifecycle

`schemas/v1/session-runtime.schema.json` governa os documentos externos
`Session` e `Checkpoint`. Ambos usam `schemaVersion: 1`, kind fechado,
JCS/SHA-256 e datas UTC canônicas.

- `Session` é o nome público canônico; `SessionSnapshot` permanece alias de
  compatibilidade para os consumidores do primeiro vertical.
- `Checkpoint` é o nome público canônico; `SessionCheckpoint` permanece alias
  de compatibilidade.
- A sequência da trace cresce estritamente e seus timestamps permanecem
  ordenados dentro da janela `createdAt`–`updatedAt`.
- `failed` exige `terminalReason`; estados não terminais o proíbem.
- `ExecutionTarget.origin` aceita apenas origin HTTP(S) canônica, sem
  userinfo, path, query ou fragment, e capability IDs não se repetem.
- Campos desconhecidos, digest divergente e data não canônica falham fechados.

## Captura binaria App Adapter → Host

`devex.capture.request` devolve um `AppAdapterCaptureCommand` fechado e
versionado. O comando contem request/session IDs, formato PNG, limite de bytes,
expiracao UTC e um upload handle HTTP em loopback. O handle e uma capability
URL curta, ligada ao origin exato do target e consumida uma unica vez.

Fluxo:

1. Studio pede a captura ao Host para uma Session pronta e com
   `capture.png`;
2. Studio envia o comando ao iframe em `PostMessageEnvelope` autenticado;
3. App Adapter captura o `RepaintBoundary` losslessly e faz `PUT image/png` no
   handle sem seguir redirect;
4. bridge valida origin, token em tempo constante, TTL, tamanho e PNG completo;
5. Host grava os bytes em CAS, publica receipt sem credencial e permite polling
   por `devex.capture.status`;
6. reset, stop, cancel, expiracao ou morte do processo descartam handles
   pendentes da Session.

O limite v1 e 32 MiB, TTL default de dois minutos e quota default de 32 uploads
pendentes. Preflight CORS aceita apenas `PUT` e `content-type` para o origin
concedido. Token e URL completa nunca entram no journal, evento, CAS ou status;
somente o comando efemero os carrega. Replay, session crossing, origin incorreto,
media type invalido, PNG malformado e overflow falham fechados.

Blobs grandes nao trafegam inline no JSON-RPC ou `postMessage`: somente comandos
pequenos, handles efemeros e receipts com digest, tamanho e media type atravessam
esses canais.
