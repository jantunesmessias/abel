# Resultado hosted control plane — SaaS multi-tenant e colaboração otimista

Status: implementação e gates portáteis concluídos em 2026-08-09
(`America/Sao_Paulo`). Promoção para produção permanece condicionada aos gates
externos listados no fim deste documento.

## Vertical entregue

- control plane Dart como modular monolith sobre `experience_engine`;
- contratos fechados para organization, principal, membership, hosted link,
  revision/change set/conflict, event, presence, comment, audit, idempotency e
  blob descriptor;
- PostgreSQL para estado transacional, com `tenant_id` em PK/FK/índices,
  `ENABLE/FORCE ROW LEVEL SECURITY` e tenant context por transação;
- object storage S3-compatible somente para blobs, com key derivada de
  tenant+digest e URL temporária;
- OIDC Authorization Code + PKCE S256 e roles owner/admin/editor/reviewer/viewer;
- `auth login/logout/status`, `workspace link/push/pull` e `publish`;
- expected digest, conflito base/current/proposed e idempotency sem overwrite;
- event table + outbox para replay; presença por TTL, comentários e approvals
  ligados ao subject digest;
- migrations expand/contract, Helm TLS ingress opt-in, NetworkPolicy,
  OpenTelemetry OTLP, backup/restore, imagens imutáveis, SBOM, provenance e
  assinatura keyless;
- threat model independente em `docs/security/hosted-remote-threat-model.md`.

O core local e `.evidence.zip` não dependem do control plane hosted.

## Evidência executada

Comandos de contracts/runtime/API/CLI:

```bash
dart test libs/experience_contracts/test/hosted_contracts_test.dart
dart test libs/execution_runtime/test/hosted_collaboration_service_test.dart \
  libs/execution_runtime/test/oidc_pkce_authenticator_test.dart \
  libs/execution_runtime/test/s3_object_store_test.dart
dart test apps/hosted_control_plane
dart test apps/workspace_cli
```

Resultado: 2 contracts, 8 testes combinados de colaboração/OIDC/S3, 5 do
control plane e 14 do CLI passaram. A matriz de roles prova autoridade de
owner/admin e menor privilégio de editor/reviewer/viewer. Telemetry exportou
OTLP protobuf com rota normalizada e sem IDs de tenant/worker/run.

PostgreSQL 18.4 local, com role `control_plane_app NOBYPASSRLS`, recebeu as seis
migrations. Os gates executados foram:

```bash
./tools/hosted/verify_postgres_rls.sh
dart run tools/hosted/verify_remote_scheduler_postgres.dart
./tools/hosted/backup_postgres.sh
./tools/hosted/restore_rehearsal.sh
```

Resultados observados no rehearsal UTC `20260810T010232Z`:

- backup custom/zstd: 82.096 bytes, checksum SHA-256 verificado;
- idade do backup: 0 s contra RPO máximo de 900 s;
- restore + RLS: 0 s medido contra RTO máximo de 14.400 s;
- cobertura de toda tabela `tenant_id`, negação sem contexto, leitura isolada e
  escrita cross-tenant rejeitada;
- banco de rehearsal removido ao final.

Deploy/supply chain:

```bash
./tools/verify/verify_supply_chain.sh
./tools/verify/verify_kubernetes_manifests.sh
```

Helm lint passou nos perfis default/remote; kubeconform strict validou 7/7 e
9/9 recursos Kubernetes 1.36.2. Bases e GitHub Actions são imutáveis; o workflow
de release gera SBOM SPDX, provenance, attestation e assinatura Cosign.

## Gate hosted control plane

| Critério | Resultado |
|----------|-----------|
| API/repository/RLS sem acesso cross-tenant | Pass no corpus e PostgreSQL real |
| object key e grant tenant-scoped | Pass em contract e S3 adapter test; policy do bucket é gate externo |
| reconnect por cursor | Pass por sequência monotônica e replay `after` sem duplicação |
| conflito sem overwrite | Pass com base/current/proposed e teste de dois writers |
| RPO ≤ 15 min / RTO ≤ 4 h | Pass no rehearsal lógico local; PITR real é gate externo |
| core local e bundle offline sem hosted | Preservado pelos gates plataforma local–Android Evidence/CLI |

## Gates externos para promoção de produção

Não foram convertidos em “pass” por configuração ou mock:

1. exercício PITR com base backup + WAL no provedor real;
2. versionamento, inventário e restauração do object storage real;
3. IdP real, rotação/revogação de chaves e redirect URIs de produção;
4. policy/ACL do bucket, collector OTel e retenção de logs;
5. failover multi-réplica do outbox e teste de carga/capacidade;
6. instalação Helm server-side no cluster alvo, com CNI e ingress reais.

Esses itens bloqueiam a claim “production-certified”, mas não deixam código ou
contrato do plano mestre sem implementação.
