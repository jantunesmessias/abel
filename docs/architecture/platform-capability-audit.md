# Auditoria do plano mestre FOUNDATION–remote execution

Status: auditoria normativa atualizada em 2026-08-11
(`America/Sao_Paulo`).

Este documento rastreia o plano mestre de implementação até evidência no
worktree. Ele distingue três estados:

- **Pass**: implementação e gate executável existem no repositório;
- **Pass portátil**: o comportamento de produto foi implementado e verificado
  sem depender da infraestrutura de produção;
- **Gate externo**: certificação operacional exige infraestrutura que não é
  simulada nem declarada como aprovada.

`Pass portátil` não autoriza as claims `production-certified` ou
`device-farm-certified`. Os comandos da execução de fechamento da revisão
corrente ficam em [Registro final](#registro-final-da-revisão).

## 1. Fundação, contratos e organização

| ID | Requisito do plano | Estado | Evidência autoritativa |
|----|--------------------|--------|------------------------|
| F-01 | Marco terminal remote execution; local web/Android; iOS pós-remote execution | Pass | ADR-0002, `ARCHITECTURE.md` §§2.3, 18 e 27.6; validações remote rejeitam iOS/físico |
| F-02 | hosted control plane SaaS multi-tenant portátil em Kubernetes | Pass portátil | `apps/hosted_control_plane`, migrations, chart `deploy/helm/control-plane`, ADR-0004 e `hosted-control-plane-results.md` |
| F-03 | Colaboração por digest/presença/comentário/approval, sem CRDT | Pass | `HostedCollaborationService`, hosted contracts/schema e ADR-0004 |
| F-04 | remote execution browser remoto e Android efêmero, batch/interativo, sem físico | Pass portátil | scheduler/worker/session gateway, remote schema, Job renderer e ADR-0005 |
| F-05 | Core local offline e independente de hosted | Pass | gates plataforma local–Android Evidence e bundles offline; dependências de packages não apontam para o control plane |
| F-06 | Dart 3.12.2, Flutter adapters 3.44.8 e Jaspr Studio 0.23.3 pinados; upgrades isolados | Pass | workspace constraints/lock, ADR-0001/0016 e gates |
| F-07 | Pub Workspace compartilhado e boundaries sem `core/shared/common` | Pass | `pubspec.yaml`, libs/apps físicos e `tools/gates/architecture_guard.dart` |
| F-08 | `shelf`/WebSocket nos servidores; Jaspr somente UI/composition | Pass | apps Host/Gateway/Studio, imports e fitness functions |
| F-09 | DTO/codecs internos gerados sem vazar como API; domínio com invariantes explícitas | Pass | APIs públicas de `experience_contracts`, factories/constructors e architecture guard |
| F-10 | PostgreSQL + S3-compatible + outbox/leases; OIDC Code + PKCE | Pass portátil | migrations 0001–0006, repositories PG/S3, OIDC authenticator e testes hosted control plane/remote execution |
| F-11 | ADRs 0001–0005 antes das decisões materiais | Pass | `docs/architecture/decisions/0001`…`0005` e registro normativo §27.4 |
| F-12 | Q-14 adiada; nenhuma claim iOS/substituição genérica | Pass | ADR-0002, `ARCHITECTURE.md` §§18.5, 24 e 27.6 |
| F-13 | Apps/libs/consumers plataforma local e extensões hosted control plane/remote execution preservam direção de dependência | Pass | árvore §15, Pub Workspace e architecture guard |
| F-14 | Tipos públicos locais por bounded context | Pass | exports de `libs/experience_contracts/lib`; schemas de Session/Gateway/Source; round-trip de `Session`, `Checkpoint`, `GatewaySession`, `UpstreamProfile`, `AgentTask` e `AgentProposal` |
| F-15 | JSON Schema 2020-12, JCS próprio, validator encapsulado e falha fechada | Pass | `verify_standards.sh`, `canonical_json.dart`, schema profile e 1.076 + 6 casos |
| F-16 | Schemas/fixtures normativos, IDs tipados e digests SHA-256 | Pass | `schemas/` organizado por domínio, fixtures de conformance e value objects de contracts |
| F-17 | API pública sem `dart:io`, Flutter, servidor ou serializador gerado | Pass | architecture guard, import-boundary tests e conformance do consumer externo |
| F-18 | Envelope/exit codes CLI e mesmos Application Services in-process | Pass | CLI contracts/parser/service composition e tests `apps/workspace_cli` |
| F-19 | JSON-RPC WS/stdio, `postMessage` estrito e blob handles limitados | Pass | Host RPC, Gateway sidecar, TargetFrame web, capture bridge e protocol tests |
| F-20 | Hosted WSS/HTTPS temporário; negotiation/idempotency/digest/cursor/cancel/terminal único | Pass portátil | hosted API/repositories, S3 adapter, scheduler/gateway e contract tests |
| F-21 | Contratos hosted control plane/remote execution e `tenantId`/`expectedDigest` | Pass | schemas `hosted-collaboration`/`remote-execution`, `hosted-remote.md` e migrations |

## 2. FOUNDATION — fechamento arquitetural e spikes

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| FOUNDATION-01 | Workspace, strict analysis, CI, dependências e estrutura normativa | Pass | root workspace, `analysis_options.yaml`, workflows e architecture guard |
| FOUNDATION-02 / S-01 | Corpus JSON Schema 2020-12 + JCS/RFC 8785 | Pass | `tools/verify/verify_standards.sh`; `foundation-validation-results.md` |
| FOUNDATION-03 / S-02 | Host–Studio–iframe com WS, JSON-RPC, reconnect, origin/nonce, limits e cleanup | Pass | Host/Studio web tests e `target_frame_web_test.dart` |
| FOUNDATION-04 / S-03 | Factory consumer-owned compartilhada; tooling traduz overlay | Pass | `examples/sample_flutter`, production/tooling entrypoints e import tests |
| FOUNDATION-05 / S-04 | Journey Map Flutter do baseline com controller/painter/outline | Pass histórico; substituído | baseline archive/result; implementação atual é JS-07 |
| FOUNDATION-06 | Fechar Q-01/Q-03/Q-04/Q-05, threats e registro normativo | Pass | decisões §23, riscos §24 e registro §27.4 |
| FOUNDATION-G | Quatro spikes VM/web, ADR e sem decisão de biblioteca/protocolo pendente | Pass | `docs/architecture/foundation-validation-results.md`, ADR-0001…0005 e gates FOUNDATION |

## 3. plataforma local — produto local vertical

### Contratos headless

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| LOCAL-CONTRACTS-01 | Schemas comuns, distribuição/layout, catálogo, source refs e machine output | Pass | schemas v1, contracts e CLI tests |
| LOCAL-CONTRACTS-02 | Parser YAML/JSON seguro, normalização, migrations e compiler determinístico | Pass | engine parser/compiler/migration tests |
| LOCAL-CONTRACTS-03 | FS store, locks, staging atômico, CAS e índices reconstruíveis | Pass | `FilesystemWorkspaceStore` e tests |
| LOCAL-CONTRACTS-04 | `validate`, `explain`, `compile` | Pass | CLI parser/application services/tests |
| LOCAL-CONTRACTS-05 | Q-02 com default, multi-app e distribuição customizada | Pass | compiler/layout fixtures e decisão §23 |
| LOCAL-CONTRACTS-06 | Import boundaries, schema conformance e rebuild determinístico | Pass | architecture guard, standards e engine/runtime tests |
| LOCAL-CONTRACTS-G | 1.000 documentos/5.000 transitions no budget; ordem estável; query não escreve | Pass | `catalog_compiler_test.dart`, store tests e `local-platform-results.md` |

### Studio e compreensão estática

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| LOCAL-STUDIO-01 | Rotas estáveis, Host Client e controllers | Pass | Jaspr router/client/controllers e component tests |
| LOCAL-STUDIO-02 | Overview, Journey Map e Inspector sobre manifest | Pass | Jaspr components/models/browser vertical |
| LOCAL-STUDIO-03 | Loading, empty, failure, stale e refreshing | Pass | workspace state/controller/component/browser tests |
| LOCAL-STUDIO-04 | Teclado, foco, reflow, text scale, reduced motion e Outline | Pass local | Google Chrome CDP, AX tree e component tests |
| LOCAL-STUDIO-05 | Review/Authoring com modelo comum e grants distintos | Pass | presentation authorization tests/contracts |
| LOCAL-STUDIO-G | Deep link/restoration, budgets e WCAG 2.2 AA por teste + auditoria assistiva | Pass | Chromium/Orca audit, widget tests e Journey benchmark |

### Host, runtime e App Adapter web

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| LOCAL-EXECUTION-01 | Host como composition root/autoridade | Pass | `apps/workspace_host` e runtime ports |
| LOCAL-EXECUTION-02 | Lifecycle, sequence, cancellation, reconnect e cleanup | Pass | session coordinator/Host RPC tests |
| LOCAL-EXECUTION-03 | Studio e target em origins separados | Pass | Host origin model e browser tests |
| LOCAL-EXECUTION-04 | Flutter Adapter mínimo, capabilities e `Semantics.identifier` | Pass | `libs/flutter_app_adapter` e sample tooling target |
| LOCAL-EXECUTION-05 | Launch profile, capability simulada, trace, reset e capture request | Pass | contracts/runtime/capture bridge tests |
| LOCAL-EXECUTION-06 | `doctor`, `dev`, `session start` | Pass | CLI commands/tests |
| LOCAL-EXECUTION-G | 20 ciclos sem resíduo; origin/replay/oversize falham fechados | Pass | session/capture/browser integration tests e `local-platform-results.md` |

### Evidence, release e consumidor

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| LOCAL-EVIDENCE-01 | PNG lossless, artifact CAS e fingerprint | Pass | PNG inspector, evidence repository e capture tests |
| LOCAL-EVIDENCE-02 | Freshness, Evidence, Release v1, PublicationView e bundle local | Pass | evidence/release contracts/runtime/tests |
| LOCAL-EVIDENCE-03 | `capture` e `release build` | Pass | CLI tests e `verify_web_evidence_flow.sh` |
| LOCAL-EVIDENCE-04 | `sample_flutter` usa somente APIs públicas | Pass | sample imports e external consumer verifier |
| LOCAL-EVIDENCE-05 | Journey→Scenario→Run→Capture→Evidence→Release→Review | Pass | plataforma local integration flow e `local-platform-results.md` |
| LOCAL-EVIDENCE-06 | Operação local offline após dependências | Pass | bundle/local gates sem hosted |
| plataforma local-G | Budgets/cleanup; documentar sem Adapter; sem claim Gateway/host-native | Pass | plataforma local result, claims de fase e gates plataforma local |

## 4. GATEWAY ISOLATED–DISTRIBUTION LIFECYCLE — Gateway, contenção, adoção e distribuição

### GATEWAY ISOLATED — Gateway isolated

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| GATEWAY-ISOLATION-01 | Sidecar por sessão e control plane stdio parent-owned | Pass | Gateway process/session runtime tests |
| GATEWAY-ISOLATION-02 | Preset→plano/routing com CAS handles lazy | Pass | compiler/contracts/tests |
| GATEWAY-ISOLATION-03 | HTTP method/path/query/`appliesTo`, mock/deny/reset/fault | Pass | Gateway engine/data-plane tests |
| GATEWAY-ISOLATION-04 | Verify e API usam o mesmo handler | Pass | conformance test E-05 |
| GATEWAY-ISOLATION-05 | Traffic sanitizado, limits, quotas e eviction | Pass | gateway runtime tests |
| GATEWAY-ISOLATION-06 | Sete commands `gateway` | Pass | CLI tests |
| GATEWAY-ISOLATION-07 | Q-06/Q-07: streaming/cancel/large payload/digests | Pass | ADR-0006, protocol/runtime tests e benchmark AOT |
| GATEWAY-ISOLATION-G | Isolated sem passthrough; verify bytes reais; sessão isolada | Pass | `verify_gateway_benchmark.sh` e `gateway-isolation-results.md` |

### GATEWAY CONTAINMENT — Gateway hybrid e contenção

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| GATEWAY-CONTAINMENT-01 | Passthrough somente route/host allowlisted; unknown deny | Pass | safe upstream/runtime tests |
| GATEWAY-CONTAINMENT-02 | Provider genérico local por credential handle | Pass | remote config provider e tests |
| GATEWAY-CONTAINMENT-03 | Sync transacional com cinco estados | Pass | provider repository/tests |
| GATEWAY-CONTAINMENT-04 | Captura temporária TTL/principal/redaction/invalidation | Pass | credential capture tests |
| GATEWAY-CONTAINMENT-05 | SSRF/redirect/DNS rebinding/hop-by-hop/oversize | Pass | abuse suites em runtime |
| GATEWAY-CONTAINMENT-06 | Browser em netns, Gateway dual-homed e egress probe | Pass | `verify_target_containment.sh` executa `unshare --net` e probe Chromium |
| GATEWAY-CONTAINMENT-07 | Q-08/Q-09/Q-10 fechadas | Pass | ADR-0007 e decisões §23 |
| GATEWAY-CONTAINMENT-G | Hybrid allowlisted, sem secrets e `targetEnforced` somente após probe | Pass | containment report schema/tests e gate real netns |

### DISTRIBUTION LIFECYCLE — adoção, evidência de teste e distribuição

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| DISTRIBUTION-01 | `init`, `adoption-report`, `detach --dry-run` | Pass | adoption service/CLI tests |
| DISTRIBUTION-02 | Documentar sem alterar código/pubspec/lockfile | Pass | friction consumer e adoption tests |
| DISTRIBUTION-03 | `DartTestEvidenceProvider` com machine reporter/artifacts | Pass | provider/tests e CLI vertical |
| DISTRIBUTION-04 | `friction_flutter` sem friend APIs | Pass | consumer e architecture guard |
| DISTRIBUTION-05 | AOT CLI/Host/Gateway + assets Studio | Pass | distribution builder/gate |
| DISTRIBUTION-06 | Descriptor, alias, update, rollback e migration | Pass | distribution services/tests/rehearsal |
| DISTRIBUTION-07 | Packages independentes e conformance fora do monorepo | Pass | `verify_external_consumer.dart` |
| DISTRIBUTION-08 | Q-11/Q-12 fechadas | Pass | ADR-0008 e decisões §23 |
| DISTRIBUTION-G | Detach preserva modificado; alias/canônico equivalentes | Pass | `verify_distribution_lifecycle.sh` e adoption tests |

## 5. Paridade web/Android

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| web/Android-01 | Android provider com ADB/emulator/install/launch/reset/capture/overlay | Pass | provider/runtime/CLI e gate real API 35 |
| web/Android-02 | `10.0.2.2`/`adb reverse` por launch profile, sem domínio hardcoded | Pass | target contracts/provider tests |
| web/Android-03 | bootstrap/update/remove/verify dry-run/undo/idempotente | Pass | Android bootstrap service/tests |
| web/Android-04 | CA/leaf por workspace, em AVD gerenciado, expiração e undo | Pass | TLS service/tests e rehearsal rootable/Play Store negativo |
| web/Android-05 | Probe plan com `after`/extract/preset/artifact | Pass | contracts/executor tests |
| web/Android-06 | ReviewGuide→binding atômico, sem routing livre | Pass | resolver/tests |
| web/Android-07 | Import/migration legado genérico | Pass | migration service/CLI tests |
| web/Android-08 | Retention 10 GiB/7 dias/24 h/releases pinadas | Pass | retention service/tests |
| web/Android-09 | E-01…E-20 web/Android | Pass | `docs/quality/platform-evidence-matrix.md`, `verify_release.sh` |
| web/Android-G | Release web/Android, lifecycle/hybrid/containment/migration/distribuição; Q-13/15/16 fechadas e Q-14 adiada | Pass | ADR-0009 e `web-android-results.md` |

## 6. source automation — bundles, source, plugins e automação

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| source automation-01 | `.evidence.zip` determinístico/JCS/CAS/ZIP fail-closed/offline | Pass | bundle implementation/contracts/tests |
| source automation-02 | Source adapters filesystem/Git revision/worktree | Pass | local source adapters/tests |
| source automation-03 | SourceBinding repository/glob/symbol opcional | Pass | source contracts/engine tests |
| source automation-04 | Impact direto/transitivo e invalidação conservadora | Pass | impact engine, corpus Q-18 e verifier |
| source automation-05 | Seis commands source/plan/context/gate/seal | Pass | CLI vertical source automation |
| source automation-06 | Q-18 com corpus e métricas | Pass | `verify_source_impact.dart`: 14 decisões, zero FP/FN |
| source automation-07 | Plugins out-of-process, manifest/version/timeout/grants | Pass | process host + bubblewrap hostile test |
| source automation-08 | Q-17 e MCP read-only; mutation preview+grant | Pass | MCP server/tests e plugin policy |
| source automation-G | Bundle reproduzível/offline; impact conservador; plugin sem effects indevidos | Pass | `verify_source_automation.sh`, ADR-0010 e `source-automation-results.md` |

## 7. Android Evidence — evidência Android ampliada

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| Android Evidence-01 | Screenshot, semantics, logcat, recording e Perfetto | Pass | Android evidence provider e gate real API 35 |
| Android Evidence-02 | Mesmo Evidence/fingerprint | Pass | contracts/repository/provider tests |
| Android Evidence-03 | Image/API/ABI/renderer/locale/timezone/toolchain | Pass | environment manifest/schema/tests |
| Android Evidence-04 | Comparação visual/semântica versionada | Pass | comparison service/tests |
| Android Evidence-05 | Emulador nunca `deviceAttested`; usa `hostNative` + containment | Pass | contracts, policy e Android Evidence rehearsal |
| Android Evidence-G | Artifacts correlacionados/sanitizados; capability ausente degrada isoladamente | Pass | `verify_android_native_evidence.sh`, ADR-0011 e `android-native-evidence-results.md` |

## 8. hosted control plane — SaaS multi-tenant e colaboração

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| hosted control plane-01 | Control plane Dart como modular monolith sobre o engine | Pass | `apps/hosted_control_plane` e imports |
| hosted control plane-02 | Todas as famílias transacionais PostgreSQL | Pass | migrations 0001–0006 e PG repositories |
| hosted control plane-03 | `tenant_id`, PK/FK/índices, FORCE RLS e contexto transacional | Pass portátil | SQL migrations + verifier PostgreSQL com role `NOBYPASSRLS` |
| hosted control plane-04 | Blobs somente S3; banco guarda metadata/policy | Pass portátil | S3 adapter, blob descriptors e schema/repositories |
| hosted control plane-05 | OIDC/PKCE e cinco roles | Pass portátil | authenticator, role matrix e tests |
| hosted control plane-06 | `workspace link/push/pull`, `auth login/logout/status`, `publish` | Pass | CLI commands/tests |
| hosted control plane-07 | Expected digest e conflito base/current/proposed | Pass | collaboration engine/repository/API tests |
| hosted control plane-08 | Event+outbox durável; LISTEN/NOTIFY só wake-up | Pass | migration/repository/outbox worker tests |
| hosted control plane-09 | Presence TTL, comments e approvals por subject digest | Pass | contracts/service/tests |
| hosted control plane-10 | Helm, expand/contract, backup/restore, TLS/NetworkPolicy, SBOM/signature/OTel | Pass portátil | chart, migrations, recovery scripts, workflow e telemetry tests |
| hosted control plane-11 | Q-19 por threat model independente | Pass | `hosted-remote-threat-model.md` HR-01…HR-24 e ADR-0004 |
| hosted control plane-G1 | Zero cross-tenant em API/RLS/object key/cache/event | Pass portátil | two-tenant tests + PostgreSQL RLS verifier; bucket policy real é gate externo |
| hosted control plane-G2 | Cursor sem perda/duplicação; conflito sem overwrite | Pass | event replay/two-writer tests |
| hosted control plane-G3 | RPO ≤15 min/RTO ≤4 h | Pass portátil | backup/checksum/restore local; PITR/WAL real é gate externo |
| hosted control plane-G4 | Core/bundle offline sem hosted control plane | Pass | plataforma local–Android Evidence gates independentes |

## 9. remote execution — remote runtime e device farm web/Android

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| remote execution-01 | Scheduler persistente, quotas/prioridades/leases/heartbeat/cancel/retry | Pass portátil | engine scheduler, PG repository and tests |
| remote execution-02 | Cada tentativa materializa Kubernetes Job finito | Pass portátil | Job materializer/dispatcher e rendered manifests |
| remote execution-03 | Worker só recebe plano assinado/artifact digest/token curto; sem DB | Pass portátil | JOSE security, worker ports/Dockerfile/tests |
| remote execution-04 | Somente web build/APK; source/build arbitrário rejeitado | Pass | request validation/worker tests |
| remote execution-05 | Web pod isolado, iframe, batch Adapter e interativo direto | Pass portátil | Job plan, worker backend e browser bootstrap tests |
| remote execution-06 | Android KVM/image+AVD pinados/userdata efêmero/APK digest/batch ADB | Pass portátil | Android Job/runtime backend and manifests; KVM real é gate externo |
| remote execution-07 | scrcpy vídeo/control, WSS autenticado, WebCodecs e fallback read-only | Pass portátil | session gateway, scrcpy parser/control tests e Chromium WebCodecs tests |
| remote execution-08 | Namespace/SA/NetworkPolicy; restricted web/control e perfil KVM mínimo | Pass portátil | Job/Helm manifests e kubeconform; admission/CNI reais são gate externo |
| remote execution-09 | Egress deny-default com endpoints permitidos | Pass portátil | NetworkPolicy generation/tests; CNI real é gate externo |
| remote execution-10 | Containment report, logs/trace/screenshot/vídeo/manifest | Pass portátil | worker evidence pipeline/contracts/tests |
| remote execution-11 | Cleanup de Job/pod/lease/token/volume/route após crash/cancel | Pass portátil | durable cleanup/reconciler/PG verifier/80-run soak; resources reais são gate externo |
| remote execution-G1 | Batch preserva semântica Run/Evidence local | Pass portátil | worker/contracts; E2E cluster é gate externo |
| remote execution-G2 | Interativo exclusivo/TTL; isolamento de stream/artifact/worker | Pass portátil | lease/ticket/gateway/S3/RLS tests |
| remote execution-G3 | Base restaurada; node loss nunca sucesso implícito; soak sem órfãos | Pass portátil | image/emptyDir plan + reconciler/soak; KVM/node reais são gate externo |
| remote execution-G4 | Sem iOS, físico ou source build | Pass | validações fail-closed e non-goals normativos |

## 10. Pipeline, matriz e promoção

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| T-01 | format/analyze → unit/property → conformance → widget/a11y → integration → abuse → perf/recovery → E2E → package/evidence | Pass portátil | `melos run check`, capability verifiers, recovery/Kubernetes/supply-chain gates e result docs |
| T-02 | Dart VM Linux e Flutter web/Chromium | Pass | workspace tests + browser suites reais |
| T-03 | Android Emulator API/ABI pinados | Pass | web/Android/Android Evidence API 35 x86_64 rehearsals |
| T-04 | Packages dentro/fora do workspace | Pass | workspace check + external consumer verifier |
| T-05 | Kubernetes local/cluster KVM | Gate externo parcial | manifests validados; server-side/KVM E2E não executados |
| T-06 | Hosted com dois tenants/credenciais | Pass portátil | API/repository/RLS/object-store isolation tests |
| T-07 | Canonicalização/schema/compile order/rebuild | Pass | standards + engine/runtime tests |
| T-08 | Negotiation/replay/timeout/reconnect/cancel e crashes | Pass portátil | protocol/session/scheduler/reconciler tests; node real é gate externo |
| T-09 | Traversal/ZIP bomb/SSRF/oversize/secrets | Pass | security/abuse suites and fitness functions |
| T-10 | Verify≡API, isolated/hybrid e containment honesto | Pass | Gateway conformance + real netns probe |
| T-11 | Dois writers, RLS/S3 isolation e cancelamento por fase | Pass portátil | hosted/remote vertical tests; cluster resource cancellation é gate externo |
| T-12 | Cleanup disk/port/lock/lease/node loss | Pass portátil | local failure tests + remote reconciler; real node loss é gate externo |
| T-13 | Promoção liga comando/ambiente/status/artifacts e atualiza norma/threats | Pass | result docs, ADRs, threat model e este audit; external claims permanecem proibidas |

## 11. Rollout, compatibilidade e premissas

| ID | Requisito | Estado | Evidência |
|----|-----------|--------|-----------|
| R-01 | Canais nightly/preview/stable e source automation–remote execution por flag/canary | Pass | distribution contracts, release policy e optional hosted/remote configuration |
| R-02 | Fase não é SemVer; versões próprias de libs/protocolos | Pass | library/schema/protocol versions e ADRs |
| R-03 | Reader aceita minor anterior; writer negocia antes de emitir | Pass | compatibility fixtures/protocol negotiation tests |
| R-04 | Migration local inspect/dry-run/backup/apply/verify/rollback | Pass | migration/adoption/distribution services/tests |
| R-05 | PostgreSQL expand→backfill→switch→contract | Pass portátil | migrations/runbook and recovery tests |
| R-06 | OCI/artifacts por digest + SBOM/provenance | Pass portátil | Dockerfiles, release workflow e supply-chain gate |
| R-07 | Retention hosted defaults | Pass | hosted contracts/config/policies |
| R-08 | Tokens curtos tenant/run/artifact scoped | Pass | OIDC/JOSE/session ticket/capability tests |
| R-09 | KVM x86_64 e CNI NetworkPolicy como preconditions | Pass documental; Gate externo | chart values/ADR/threat model; cluster alvo não certificado |
| R-10 | Sem CRDT/físico/source build/iOS e produto completo só web/Android | Pass | contracts/validators/claims §27.6 |

## 12. Gates externos de certificação

Estes requisitos pertencem à promoção operacional, não são reduzidos a mocks e
permanecem abertos até existir o ambiente alvo:

| ID | Gate | Estado |
|----|------|--------|
| EXT-hosted control plane-01 | PITR com base backup + WAL e failover no PostgreSQL real de produção | Gate externo |
| EXT-hosted control plane-02 | Versionamento/inventário/restore e policy cross-tenant do bucket real | Gate externo |
| EXT-hosted control plane-03 | IdP, redirects, rotação/revogação e TLS ingress reais | Gate externo |
| EXT-hosted control plane-04 | Collector/retention e carga multi-réplica/outbox | Gate externo |
| EXT-remote execution-01 | Helm server-side com Gateway API, CNI e admission | Gate externo |
| EXT-remote execution-02 | Quatro variantes web/Android × batch/interativo em Linux/KVM | Gate externo |
| EXT-remote execution-03 | Cancel/crash/node-loss e cleanup de recursos reais | Gate externo |
| EXT-remote execution-04 | Soak prolongado, wipe inter-tenant, capacidade/latência/fairness | Gate externo |

Enquanto qualquer linha acima estiver aberta, somente `hosted control plane implemented` e
`remote execution implemented` são claims válidas. A taxonomia normativa e as checkboxes
correspondentes estão em `ARCHITECTURE.md` §27.6.

## Registro final da revisão

O fechamento deve registrar resultados da revisão corrente para, no mínimo:

```text
melos run check
./tools/verify/verify_standards.sh
./tools/verify/verify_web_evidence_flow.sh
./tools/benchmarks/gateway_benchmark.sh
./tools/verify/verify_target_containment.sh
./tools/verify/verify_distribution_lifecycle.sh
./tools/verify/verify_release.sh
./tools/verify/verify_source_automation.sh
./tools/verify/verify_android_native_evidence.sh
./tools/verify/verify_kubernetes_manifests.sh
./tools/verify/verify_supply_chain.sh
```

Também exige PostgreSQL real para RLS/scheduler/recovery e um build release do
Studio. A ausência de um gate externo não invalida a implementação portátil,
mas proíbe a claim de certificação correspondente.

### Resultado observado

Fechamento executado em 2026-08-09 (`America/Sao_Paulo`; parte dos artifacts
usa UTC 2026-08-10):

- `melos run check`: exit 0; format, analyze fatal, architecture/supply-chain,
  libs/apps, Studio VM e sete cenários Chromium, contenção netns e dois
  consumers passaram;
- auditoria mecânica da superfície normativa: 56/56 tipos públicos esperados
  encontrados, sem contrato ausente;
- standards: JSON Schema 1.076/1.076 dentro do perfil e JCS 6/6;
- plataforma local: build web real, PNG 1280×720, Evidence e ReleaseBundle produzidos;
- GATEWAY ISOLATED: AOT p95/p99 máximos 2,613/3,541 ms contra 10/25 ms;
- GATEWAY CONTAINMENT: `targetEnforced`, Gateway alcançável e egress direto negado;
- DISTRIBUTION LIFECYCLE: 34 arquivos publicáveis, duas reconstruções com manifest
  byte-idêntico, três executáveis AOT, Studio release,
  install/update/rollback e consumer externo;
- web/Android stable: Android API 35 x86_64, install/launch/semantics/capture/reset/TLS
  undo/stop e distribuição `0.1.0`; `distribution.json`
  `sha256:8d08483af17c3f410b6ca7c034478f1b2819808a4b4246175bd414ca1b623657`;
- source automation: 14 decisões no corpus, zero falso positivo/negativo e plugin hostil
  confinado;
- Android Evidence: cinco modalidades `collected`, 2.592.000 pixels e 14 nodes comparados
  sem mudança, `.evidence.zip` de 584.667 bytes verificado offline;
- PostgreSQL 18.4: RLS/no-context/cross-tenant, cleanup durável e retry fencing;
  backup de 82.096 bytes, checksum e restore em 0 s, contra RPO 900 s/RTO
  14.400 s;
- Helm/kubeconform: 7/7 default, 9/9 remote e 26/26 recursos de Jobs válidos
  para Kubernetes 1.36.2; HTTPRoute validado estruturalmente;
- `shellcheck`, `actionlint`, supply chain e build web release do Studio:
  exit 0;
- Journey Map profile: first frame 494,4 ms, pan p95 12,1 ms e p99 18,1 ms
  contra budgets 1.500/16,7/33,3 ms.

A primeira invocação web/Android sem `ANDROID_SDK_ROOT` e a primeira conexão Dart ao
PostgreSQL local sem `sslmode=disable` falharam por precondição antes do trecho
avaliado. As repetições com SDK/Chromium explícitos e TLS desabilitado somente
no PostgreSQL efêmero local passaram integralmente. Produção continua exigindo
TLS.

Conclusão da auditoria: todos os requisitos de implementação FOUNDATION–remote execution possuem
evidência executada na revisão. Permanecem abertos exclusivamente os gates
EXT-hosted control plane/EXT-remote execution acima, que bloqueiam certificação operacional, não as claims
`hosted control plane implemented` e `remote execution implemented`.

## 13. MC/AP — composição modular e AutoPreview

Esta extensão de 2026-08-10 audita o refactor sem alterar a matriz histórica
FOUNDATION–remote execution acima.

| ID | Requisito | Status | Evidência |
|----|-----------|--------|-----------|
| MC-01 | Module/Capability/Provider/Profile canônicos e fechados | Pass | contracts/schema, ADR-0012 e 69 testes de contracts |
| MC-02 | configuração canônica, precedência e resolução única | Pass | loader/resolver e suites runtime/CLI |
| MC-03 | lifecycle, health, rollback reverso e resources owned | Pass | module lifecycle tests, Host 20 ciclos e check integral |
| MC-04 | CLI deriva help/dispatch do plano | Pass | profile `journey-preview` remove comandos disabled antes do dispatch |
| MC-05 | Host valida plano e publica somente RPCs/processos habilitados | Pass | transporte JCS/digest e profile mínimo com apenas kernel RPCs |
| MC-06 | Studio deriva o seam de routes/contributions do EffectiveKitManifest | Pass no escopo MC; shell operacional é SR | 22 testes VM, rotas ausentes e grants ortogonais |
| MC-07 | Distribution full/slim canônica e rollbackável | Pass | dois gates de distribuição, digests e install/update/rollback |
| AP-01 | autoria oficial Preview/MultiPreview sem UI duplicada | Pass com limitação upstream | sample real; detector legado funciona, LSP default Flutter 3.44.8 falha |
| AP-02 | scanner/compiler determinísticos e source tree limpo | Pass | Analyzer negative corpus e registry somente `.dart_tool` |
| AP-03 | captura isolada, PNG/CAS/Evidence e falha parcial | Pass | baseline com múltiplas Variants, policy denied, timeout/quotas e 161 testes runtime; sample atual 5 Scenarios/7 descriptors/3 Variants |
| AP-04 | projector in-memory preserva fidelity/freshness/status | Pass no escopo AP; CAS→Host→Studio é SR | projector/view data e suites Studio |

Gates executados:

```text
melos run check                       exit 0
tools/verify/verify_auto_preview.sh          exit 0
tools/verify/verify_modular_distribution.sh  exit 0
tools/verify/verify_distribution_lifecycle.sh      exit 0
```

Claims válidas: composição modular e AutoPreview implementados para a matriz
local Flutter 3.44.x. AutoPreview `flutter-test` é Evidence `structural`, não
host-native/device-attested. O detector LSP do Previewer e sandbox portátil de
rede/memória permanecem limites explícitos, não requisitos fingidos como
concluídos.

Essas claims não promoviam, por si, o Abel Studio operacional completo. A
extensão do Studio abaixo registra a evidência posterior sem reescrever os gates anteriores.

## 14. Reconstrução do Abel Studio

Extensão executada em 2026-08-10 para o baseline local do Studio Flutter. A
substituição Jaspr está registrada na seção 15 e não reaproveita esta evidência
como se fosse do renderer atual.

| ID | Requisito | Status | Evidência |
|----|-----------|--------|-----------|
| SR-01 | contracts/schemas, catálogo e Variants autoritativos | Pass | decoder/corpus negativo, `WorkspaceSnapshot` e schema v1 |
| SR-02 | Host/resources/bootstrap e `workspace dev` | Pass | Origin/token/TTL/digest, deep links, readiness e supervisor |
| SR-03 | shell/filters/states sem sample de produção | Pass | widget suites e release Chromium sobre catálogo real |
| SR-04 | Journey Map com/sem pixels, LOD/frame/outline/cache | Pass | vertical com dois PNGs e run sem provider; cache 256/64 MiB |
| SR-05 | inspector Variant/provider/Evidence/source/modules | Pass | fidelity, freshness, fingerprint e capture policy tipados |
| SR-06 | AutoPreview pelo Host | Pass | confirmação, progresso/cancel, falha parcial e stale→fresh |
| SR-07 | matriz modular e ausência de efeitos disabled | Pass | todos os profiles, combinações e Host `journey-android` negativo |
| SR-08 | segurança/lifecycle/distribution | Pass | token fora da URL, CSP self-hosted, 20 ciclos e bundles slim |
| SR-09 | browser/a11y/performance/promoção | Pass local | Chromium real, Semantics/reflow e benchmark profile |

Resultados observados:

- `melos run check`: exit 0 na revisão SR; 313 arquivos formatados, analyze fatal,
  85 contracts, 35 engine, 173 runtime, Studio VM/Chromium, 21 CLI,
  Host/Gateway/hosted/remote, containment e consumers;
- `tools/verify/verify_studio_vertical.sh`: sample atual com 5 Scenarios, 7 descriptors,
  3 Variants e 7 PNGs validados, fidelity `structural`, fingerprint/policy
  presentes, stale→fresh, run sem provider, CSP sem log severo e cleanup
  verificado;
- `tools/benchmarks/journey_map_benchmark.sh`: 1.000 nodes/5.000 transitions, first frame
  345,9 ms, pan p95 11,3 ms e p99 12,0 ms contra budgets
  1.500/16,7/33,3 ms;
- 20 ciclos completos Host + Studio, com os dois listeners recusando conexão
  após cada shutdown;
- Distribution `journey-preview` reproduzível e sem Gateway;
  `gateway-lab-headless` sem Studio;
- `flutter-test` permanece `structural`; detector LSP/legacy e sandbox
  host-dependent permanecem limitações, não claims concluídas.

Resultado detalhado:
`docs/architecture/studio-reconstruction-results.md`.

## 15. JS — cutover do único Studio Jaspr

Extensão executada em 2026-08-11 sob ADR-0016.

| ID | Requisito | Status | Evidência |
|---|---|---|---|
| JS-01 | único `apps/studio` client-side | Pass | pubspec/entrypoint Jaspr; sources Flutter removidos |
| JS-02 | UI System Jaspr e UX System Dart puro | Pass | package graph, guard e tests |
| JS-03 | zero Flutter/Material/Cupertino/renderer no Studio | Pass | `tools/gates/architecture_guard.dart` e scan |
| JS-04 | Host bootstrap/RPC/resources/reconnect reais | Pass local | vertical e Google Chrome CDP |
| JS-05 | Overview/Journey/Inspector/AutoPreview | Pass local | 5 Scenarios, 7 descriptors/PNGs, 3 Variants, stale→fresh e no-provider |
| JS-06 | semantics/keyboard/200%/motion/dialog/AX | Pass local | CDP: 0 unnamed, 7 Tab stops, no overflow, 296 AX, 0 severe |
| JS-07 | Journey DOM bounded e Outline completo | Pass | policy 10.000→24 + browser interaction p95 ~33,4 ms |
| JS-08 | Target/Gateway capability-gated | Pass no sample/consumer-specific | Target release real, Gateway guided, traffic, exact CORS, lifecycle e component tests |
| JS-09 | Remote/Hosted/Review fail-closed | Pass contracts/Partial external | one-time grant, protocol/build/components; sistemas externos ausentes |
| JS-10 | build/distribuição Jaspr | Pass | `jaspr build`; bundles modular/full reproduzíveis; install/update/rollback e consumer externo |

Claims atuais: o cutover arquitetural e o vertical `journey-preview` estão
comprovados localmente. Target/Gateway estão comprovados no sample e continuam
consumer-specific; Remote/Hosted reais, KVM e integrações externas permanecem
Partial e são relatados como tal.

Atualização operacional de 2026-08-11: o consumer de referência passou a
fornecer Target web release real e Gateway guiado com presets do Host,
TrafficEvents, CORS de origin exato e cleanup por ownership. Essa prova remove a
lacuna Target/Gateway para o sample, mas não transforma a implementação
consumer-specific em readiness universal de qualquer aplicação. Remote/Hosted,
KVM e infraestrutura externa continuam Partial.
