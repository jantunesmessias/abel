# ADR-0006: Gateway GATEWAY ISOLATED, HTTP e plano por artifacts

- Status: aceita
- Data: 2026-08-09
- Decisoes afetadas: D-G12, D-G16, Q-06, Q-07

## Decisao

- Cada `GatewaySession` possui um processo sidecar, um listener IPv4 loopback,
  estado e traffic buffer exclusivos.
- O control plane parent-owned usa JSON-RPC/stdio com framing UTF-8 incremental,
  limite de 1 MiB e timeout de 15 segundos. Nenhum shell participa do launch.
- O data plane GATEWAY ISOLATED usa `shelf`/`dart:io`, aceita bodies de ate 256 KiB e fecha
  a conexao fisicamente quando `FaultProfile.disconnect` esta ativo.
- `CompiledGatewayPlan` e JCS com digest semantico e no maximo 1 MiB. Bodies nao
  entram inline: `GatewayFixture` carrega digest, tamanho e media type; o CAS e
  consultado lazy e o primeiro resultado validado vira bytes imutaveis em cache
  limitada a 64 MiB.
- `verify` usa o mesmo `GatewayRuntime`/`MockHandlerPort` do HTTP. Ao cruzar o
  Host RPC de 64 KiB, o body vira artifact CAS e somente seu handle e devolvido.
- Requests desconhecidas negam; `isolated` nao possui codigo de passthrough.

## Evidencia e rollback

Schemas fechados, testes de bytes maximos, request abortada, disconnect, framing
oversized, quotas e dois sidecars isolados cobrem a decisao. O benchmark AOT
mede 1 KiB e 256 KiB e falha acima de p95 10 ms ou p99 25 ms.

Rollback remove a capability Gateway do Host e seus comandos; Catalog, Session
e Evidence plataforma local continuam funcionais sem reinterpretar seus contratos.
