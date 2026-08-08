# Gateway runtime v1

Os documentos públicos `GatewaySession` e `UpstreamProfile` são governados por
`schemas/v1/gateway-plan.schema.json`, usam `schemaVersion: 1`, kinds fechados,
datas UTC canônicas e identidade JCS/SHA-256.

## GatewaySession

Cada sidecar possui ID opaco, owner `Session`, digest do
`CompiledGatewayPlan`, timestamps e estado fechado:

- `created`: sem scope ativo ou terminal reason;
- `running`: exige exatamente um `activeScopeId` e não aceita terminal reason;
- `stopped`: não retém scope ativo;
- `failed`: não retém scope ativo e exige terminal reason.

`updatedAt` nunca precede `createdAt`. Campo desconhecido, data não canônica,
estado inconsistente ou digest divergente falha fechado.

## UpstreamProfile

O profile é configuração local e efêmera. Ele não pertence ao catálogo,
Evidence, Release ou export e não pode declarar ambiente de produção. V1 aceita
somente `development`, `test` e `staging`.

Cada alias aponta para uma origin HTTP(S) canônica, sem userinfo, path, query ou
fragment. Credencial nunca é materializada no documento: quando necessária,
apenas um `credentialHandleId` opaco referencia o credential store. As origins
concretas não entram em chat, log, CAS ou artifact público.
