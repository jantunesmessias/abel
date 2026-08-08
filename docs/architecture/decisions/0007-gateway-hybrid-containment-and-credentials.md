# ADR-0007: Gateway GATEWAY CONTAINMENT hybrid, containment e credenciais

- Status: aceita
- Data: 2026-08-09
- Decisoes afetadas: D-035, D-G03, D-G05, D-G06, Q-08, Q-09, Q-10

## Decisao

- `hybrid` permite passthrough apenas numa `GatewayRoute` ativa com policy
  `upstreamOnly` e `UpstreamProfileId` explicito. Route desconhecida continua
  deny; nao existe fallback implicito para rede.
- Endpoints concretos vivem somente em `workspace.local.yaml`, que e ignorado pelo
  versionamento. O plano autoral carrega apenas o ID logico. Host, environment,
  limits e credential handle sao validados antes do primeiro request.
- O cliente HTTP usa allowlist exata, `DIRECT`, sem redirects, sem
  auto-decompression, com timeout/body limit. Todas as respostas DNS precisam
  ser permitidas e o IP escolhido fica pinado na conexao; TLS preserva o
  hostname original.
- O provider remoto inicial e generico: JSON `{schemaVersion, items}`. Seu
  adapter classifica `missing`, `empty`, `incomplete`, `invalid` e `ready`.
  Apenas documento normalizado valido/empty entra no CAS; falha preserva o
  ultimo digest ativo e persiste somente assessment sanitizado.
- Credencial persistente e apenas handle `env:UPPERCASE_NAME`; valor nunca entra em
  config, status, CAS ou traffic. Captura de sessao usa memoria do processo,
  TTL maximo de 30 minutos e binding exato a principal, target e geracao. O
  handle `session:authorization` resolve a captura apenas nesse contexto.
- `CompiledGatewayPlan` local permanece `gatewayOnly`. `targetEnforced` so pode
  vir de `TargetContainmentReport` com os probes `gatewayReachable` e
  `directEgressDenied` executados e aprovados.
- O adapter web Linux de referencia executa Chromium/target num network
  namespace sem rota. Seu frontend Gateway local atravessa um canal stdio
  herdado ate um broker externo allowlisted, que alcanca o upstream separado.
  Sem esse adapter ou sem ambos os probes, a claim degrada para `gatewayOnly`.

## Seguranca e limites

Hosts de aparencia produtiva sao rejeitados; staging exige HTTPS. Enderecos
loopback, privados, link-local, multicast, reservados e IPv4-mapped sao negados,
salvo opt-in local explicito para ambiente de desenvolvimento. Headers do
request nao sao copiados: apenas a credencial configurada e inserida. Headers
hop-by-hop, cookies e redirects nao atravessam a resposta.

A limpeza da captura sobrescreve os bytes mutaveis em best effort; o runtime
Dart e o sistema operacional nao oferecem garantia criptografica sobre copias
transitorias. Por isso nao ha persistencia nem recuperacao apos restart.

## Evidencia e rollback

Testes unitarios, sidecar real, CLI `gateway doctor/sync`, DNS adversarial,
provider transacional, captura contextual e o probe Chromium em namespace
cobrem a decisao. O resultado executado esta em
`docs/architecture/gateway-containment-results.md`.

Rollback desabilita `gateway.hybrid` e o adapter de containment. Planos isolated,
CAS, evidence e sessoes GATEWAY ISOLATED permanecem legiveis sem reinterpretacao.
