# Threat model hosted e remote

Status: normativo para V4/V5. Revisão: 2026-08-09. Owner: Security +
Hosted/Remote Runtime. Este modelo é independente do threat register local do
§17 de `ARCHITECTURE.md` e resolve Q-19 no escopo implementado.

## Escopo e claims

O escopo inclui control plane hosted, OIDC/PKCE, PostgreSQL, object storage
S3-compatible, API/CLI de colaboração, scheduler, Kubernetes API, workers web e
Android/KVM, gateway de sessão, Studio web e pipelines de imagem/recovery. O
core local e a verificação offline de `.devexbundle` não atravessam essas
fronteiras e continuam disponíveis quando V4/V5 estão indisponíveis.

O modelo não transforma em evidência executada uma configuração declarada. As
seguintes claims exigem ambiente de produção ou cluster dedicado: isolamento
real do CNI, política de admissão que limite namespaces `devex-run-*`,
RuntimeClass/KVM, Gateway API/HTTPRoute, identidade do IdP, PITR/WAL e
versionamento/restauração do object storage.

## Data flow e trust boundaries

```text
Browser/CLI
  |  OIDC code + PKCE / bearer curto / HTTPS-WSS
  v
Ingress TLS -> Hosted control plane -> PostgreSQL (RLS forced)
                       |              -> S3-compatible object store
                       |              -> OTLP collector
                       v
               Kubernetes API (token projetado e rotativo)
                       |
             namespace efêmero por run
             +-------------------------+
             | Job worker + sidecar    |
             | emptyDir + secret curto |
             +-------------------------+
                       |
             HTTPS artifacts/control e WSS session gateway
                       |
                    Studio
```

Fronteiras distintas:

1. usuário não autenticado → IdP/redirect loopback;
2. principal autenticado → tenant e role autorizados;
3. processo da API → transação PostgreSQL com `devex.tenant_id` local;
4. API → object store por chave derivada de tenant e digest;
5. control plane → Kubernetes API com credencial projetada de 600 segundos;
6. cluster geral → namespace/run efêmero;
7. worker → endpoints concedidos por plano/capability token;
8. viewer → gateway de sessão, nunca diretamente ao worker;
9. pipeline de release → registry, provenance, SBOM e assinatura keyless;
10. produção → repositórios de backup/WAL e inventário versionado de objetos.

## Assets e classificação

| Asset | Classificação | Invariante |
|-------|---------------|------------|
| access/refresh/session/worker token e signing JWK | secret | nunca em URL, log, CAS, manifest público ou ConfigMap |
| membership, tenant context e audit | sensitive | autorização e RLS concordam; audit não é editável pelo cliente |
| revision/release/evidence/findings/approvals | internal ou sensitive | tenant + subject digest; alteração autoral usa expected digest |
| blob | conforme descriptor | chave exata `tenants/<tenant>/blobs/sha256/<digest>` e URL temporária |
| plano remoto | internal, assinado | tenant/run/artifacts/capabilities/expiração não podem ser substituídos |
| stream, screenshot, vídeo e input | sensitive | run/tenant/role/origin/TTL vinculados; fallback não aceita controle |
| node Android/KVM e userdata | privileged | pool dedicado; volume efêmero; cleanup antes de retry |
| backup/WAL/object versions | sensitive | criptografia, acesso separado, checksum e restore isolado |

Principals: usuário OIDC, owner, admin, editor, reviewer, viewer, aplicação
hosted, migration operator, backup operator, scheduler, worker por run,
session viewer e pipeline OIDC do GitHub. Nenhum ID vindo de header ou payload
substitui a identidade autenticada.

## Threat register

| ID | Ameaça / caminho de abuso | Controle implementado e evidência | Risco residual / próximo gate |
|----|---------------------------|----------------------------------|-------------------------------|
| HR-01 | issuer falso, code interception, state replay ou algoritmo JWT fraco | discovery no mesmo origin HTTPS, Authorization Code + PKCE S256, state/nonce one-shot, allowlist de algoritmos e JWKS; testes de OIDC negativos | IdP, redirect URI e rotação de chaves devem ser validados no ambiente real |
| HR-02 | cliente escolhe outro `tenantId`/principal no payload | contexto deriva do token; `_sameContext`, role matrix e IDs tenant-scoped; API e testes de dois tenants | provisioning de organization/membership exige processo administrativo auditado |
| HR-03 | conexão pooled conserva tenant anterior | `SET LOCAL devex.tenant_id` dentro de transação; commit/rollback obrigatório; usuário da aplicação é `NOBYPASSRLS` | monitorar conexões sem transação e falhar startup se role puder bypassar RLS |
| HR-04 | query, FK, índice ou tabela nova escapa do tenant | `tenant_id` em PK/FK/índices, RLS `ENABLE` + `FORCE`, auditoria mecânica de cobertura e teste PostgreSQL real | migration nova deve entrar no gate de cobertura antes do deploy |
| HR-05 | função `SECURITY DEFINER` enumera ou altera outro tenant | funções do scheduler retornam somente tenant candidato, têm search path fixo, `PUBLIC` revogado e não retornam conteúdo | restringir `EXECUTE` à role exata após toda migration; revisar funções novas |
| HR-06 | object key ou URL assinada vira confused deputy cross-tenant | key derivada de tenant+digest, descriptor valida tenant, origin/bucket fixos, TTL e headers assinados; teste S3 cross-tenant | policy real do bucket e credencial por workload são gates externos |
| HR-07 | lost update ou idempotency-key reuse sobrescreve revisão | expected/base/current/proposed digests, transação atômica e replay só para request digest idêntico | cliente ainda resolve conflito explicitamente; não há merge automático/CRDT |
| HR-08 | cursor/outbox perde, duplica ou mistura eventos | sequência monotônica por tenant/workspace, replay `after`, outbox na mesma transação e `LISTEN/NOTIFY` somente como wake-up | dispatcher multi-réplica precisa rehearsal de failover no cluster |
| HR-09 | presença/comentário/approval é ligado a subject ou role indevidos | TTL bounded, subject digest, role matrix explícita e tenant transaction | moderação/retention legal dependem da implantação |
| HR-10 | secret/PII vaza por erro, telemetry ou artifact | rotas OTel normalizadas, body/token ausentes, scanners, descritores públicos sem capability e logs sanitizados | collector e backend de logs precisam ACL/retention externos |
| HR-11 | backup restaura dados incompletos ou abre serviço sem RLS | dump checksum, idade ≤ 15 min, restore isolado, cobertura/RLS/cross-tenant e RTO ≤ 4 h; runbook PITR | rehearsal local não prova WAL, object versions nem tempo de infraestrutura real |
| HR-12 | control plane usa token Kubernetes estático roubável | token projetado de 600 s, lido a cada request, symlink limitado ao root confiável, automount desabilitado | comprometimento do pod durante o TTL ainda permite operações RBAC concedidas |
| HR-13 | RBAC permite workload fora do namespace/run | verbs mínimos sem list/watch/update; nomes de namespace são hash opaco; manifests têm labels e cleanup | RBAC não restringe nome em `create`; admission policy para `devex-run-*` é gate obrigatório do cluster |
| HR-14 | worker recebe source arbitrário, imagem/tag mutável ou artifact trocado | somente web build/APK, OCI e device image por digest, plano assinado, artifact por digest, scrcpy server com hash | registry mirror e admission de assinatura devem ser exercitados no cluster |
| HR-15 | capability/lease/plano é roubado, reusado ou aceita generation antiga | JWT curto vinculado a tenant/run/worker/generation/artifacts, lease heartbeat/expiry e fencing de retry | clock skew e rotação de signing key requerem rehearsal operacional |
| HR-16 | pod web/Android escapa ou alcança rede arbitrária | namespace e SA por run, token SA off, root FS read-only, capabilities drop, seccomp, NetworkPolicy deny-default e CIDRs explícitos | CNI/admission/runtime precisam provar enforcement; Android/KVM mantém risco maior |
| HR-17 | `/dev/kvm`, host mount ou node Android expõe host/outro tenant | extended resource via RuntimeClass, pool/nodeSelector dedicado, nenhum hostPath/privileged, um run por lease | hardening do RuntimeClass/device plugin e isolamento do node são gates dedicados |
| HR-18 | viewer sequestra WSS/iframe ou observa outro run | ticket no primeiro frame, nunca URL; origin exato, run/role/nonce/TTL, grant de bootstrap one-shot e cookie no-store | TLS/Gateway API e afinidade/timeout devem ser validados em cluster |
| HR-19 | input scrcpy injeta payload inválido ou fallback ganha controle | framing bounded/ordered, comandos estritos traduzidos ao wire oficial; screenshot fallback é read-only; WebCodecs tem timeout | fuzz adicional acompanha mudanças do protocolo scrcpy |
| HR-20 | worker perdido produz sucesso implícito ou retry concorre com cleanup | state machine terminal explícita, lease fencing, cleanup durável, retry bloqueado, reconciliação/backoff e containment authoritative | falha do próprio control plane exige HA e banco recuperável |
| HR-21 | cancel/crash deixa namespace, token, volume, route ou userdata | cleanup idempotente, DELETE 404 aceito, confirmação de namespace ausente, soak e retry após cleanup | finalizers/admission/CNI defeituosos exigem alerta de cleanup debt e ação operacional |
| HR-22 | DoS por prioridade, sessão longa, payload ou stream | quotas tenant/pool, duração e tamanho bounded, capacidade/lease, backpressure e frame maxima | autoscaling e fairness sob carga real são gates de capacidade |
| HR-23 | imagem/action/dependência comprometida | bases/actions pinadas, SBOM SPDX, provenance, attestation e cosign keyless | release real precisa policy de verificação no registry/admission |
| HR-24 | ingress se torna origem não confiável por selector amplo | policy seleciona namespace e pod labels explícitos e TLS ingress é opt-in | labels reais do ingress controller devem ser fixados por ambiente |

## Regras de promoção e resposta

- Finding cross-tenant, bypass de RLS, replay de capability ou escape de
  namespace bloqueia release; não há aceitação temporária silenciosa.
- Falha de cleanup bloqueia retry do mesmo run e gera cleanup debt observável.
- Perda de worker termina em `failed`, `cancelled` ou `unknown`, nunca
  `succeeded` por ausência de sinal.
- Incidente de signing key revoga o `kid`, interrompe novas leases e invalida
  sessões; imagens e planos já emitidos são tratados pelo TTL, não por confiança
  indefinida.
- Mudança em auth, tenant context, schema/RLS, object key, RBAC, RuntimeClass,
  framing, session bootstrap ou supply chain exige atualização deste documento,
  teste negativo e owner explícito.

## Evidência ligada

- `tool/hosted/verify_postgres_rls.sh` e
  `tool/hosted/verify_remote_scheduler_postgres.dart`;
- `tool/hosted/backup_postgres.sh`, `restore_rehearsal.sh` e
  `docs/operations/hosted-recovery.md`;
- suites `hosted_*`, `s3_object_store`, `remote_*`, `kubernetes_remote_job`,
  `scrcpy_remote_session` e `remote_session_surface_web_test`;
- `tool/verify_kubernetes_manifests.sh` e `tool/verify_supply_chain.sh`;
- ADR-0004, ADR-0005, resultados V4/V5 e gates de `ARCHITECTURE.md`.
