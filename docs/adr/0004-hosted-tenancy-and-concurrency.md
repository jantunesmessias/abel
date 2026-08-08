# ADR-0004: tenancy, identidade e concorrência hosted

- Status: aceita e implementada em V4; promoção de produção condicionada
- Data: 2026-08-09
- Decisões afetadas: D-001, D-025, D-041, Q-19

## Contexto

O hosted precisa compartilhar revisões, releases e decisões entre organizações
sem transformar a disponibilidade do SaaS em requisito do core local. O maior
risco não é a latência: é uma autorização esquecida produzir acesso
cross-tenant ou um push concorrente sobrescrever autoria silenciosamente.

## Decisão

1. V4 é um modular monolith Dart que reutiliza Application Services do engine;
   não duplica regras em controllers nem divide serviços prematuramente.
2. PostgreSQL é o store transacional. Toda entidade persistida inclui
   `tenant_id` em identidade, FK e índice. A role da aplicação é
   `NOBYPASSRLS`; cada operação usa transação com tenant context local; todas as
   tabelas usam `ENABLE` e `FORCE ROW LEVEL SECURITY`.
3. Blobs não entram no banco. O object store S3-compatible usa chave derivada
   `tenants/<tenant>/blobs/sha256/<digest>`, descriptor validado e URL curta.
4. Identidade usa OIDC Authorization Code + PKCE S256. DevExKit não gerencia
   senha. Issuer/origin, state, nonce, algoritmo, audience e JWKS falham
   fechados.
5. Roles são owner, admin, editor, reviewer e viewer. Owner/admin têm autoridade
   completa; editor pode ler/comentar/push/publish; reviewer pode
   ler/comentar/aprovar; viewer somente lê.
6. Toda mutação autoral exige `expectedDigest`. Conflito retorna
   base/current/proposed; não existe merge automático nem CRDT. Idempotency key
   só reproduz resposta quando o request digest é idêntico.
7. Event table e outbox são gravados na mesma transação. `LISTEN/NOTIFY` é
   apenas wake-up; replay usa cursor monotônico por tenant/workspace.
8. Presence tem heartbeat/TTL. Comentários, findings e approvals se ligam a
   subject digest. Audit deriva da ação autenticada, não de documento enviado
   pelo cliente.
9. Migrations seguem expand → backfill/switch → contract. Backup/restore, RLS,
   OpenTelemetry, TLS ingress, NetworkPolicy, SBOM, provenance e assinatura são
   parte do gate de deploy.
10. O threat model independente em
    `docs/security/hosted-remote-threat-model.md` governa auth/tenancy e resolve
    Q-19.

## Alternativas rejeitadas

- filtro de tenant apenas na aplicação: uma query esquecida basta para vazar;
- schema ou banco por tenant desde o início: eleva operação/migration sem
  eliminar a necessidade de autorização na API/object store;
- senha própria: aumenta superfície de credencial sem necessidade;
- last-write-wins ou merge implícito: apaga intenção e invalida evidence;
- CRDT: não é necessário para presença/comentários/push por revisão;
- broker antes da outbox: adiciona duas fontes de verdade e dual write;
- guardar blobs em `bytea`: mistura lifecycle, backup e policy de objetos com o
  estado transacional.

## Consequências e rollback

Repositories precisam sempre de `HostedRequestContext`; bypass de RLS é defeito
de release. A outbox pode ganhar um broker depois sem alterar a verdade
transacional. Desabilitar V4 remove link/auth hosted, mas não migra nem invalida
catálogo, CAS ou bundles locais. Rollback de migration nunca apaga coluna/dado
antes de todos os readers antigos saírem da compatibility window.

## Evidência

- schema `hosted-collaboration.schema.json` e contracts tests;
- migrations `0001`/`0002` e verifier PostgreSQL/RLS real;
- suites collaboration, OIDC, S3, hosted control plane e CLI;
- rehearsal em `docs/architecture/v4-results.md` e runbook de recovery;
- Helm/kubeconform e release-images supply-chain gates.

PITR/WAL, bucket/IdP reais e failover no cluster continuam gates externos; não
são inferidos de unit tests.
