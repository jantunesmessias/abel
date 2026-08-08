# Resultado remote execution — remote runtime web/Android

Status: implementação e gates portáteis concluídos em 2026-08-09
(`America/Sao_Paulo`). Certificação de device farm permanece condicionada a um
cluster Linux/KVM dedicado.

## Vertical entregue

- scheduler persistente com quota, prioridade, state machine, lease/generation,
  heartbeat, cancellation, retry idempotente e terminais explícitos;
- PostgreSQL e repository in-memory com o mesmo contrato transacional;
- `RemoteExecutionRequest/Plan`, worker/image/lease/run/artifact/containment e
  session ticket em schema fechado, JCS/digest e assinatura;
- worker sem acesso ao banco, limitado a plano assinado, capability token curto
  e artifact imutável por digest;
- execução somente de web build ou APK pronto; source/build remoto é rejeitado;
- quatro variantes de Kubernetes Job: web/Android × batch/interativo;
- namespace, ServiceAccount, Secret imutável, ConfigMap trust, emptyDir,
  NetworkPolicy e cleanup por run;
- web batch/interativo e Android emulator/ADB/scrcpy no backend do worker;
- gateway WSS autenticado, ticket no primeiro frame, nonce/role/run/TTL,
  bootstrap web one-shot e iframe sandboxed sem segredo na URL;
- framing binário portable VM/JavaScript, vídeo H.264 + control e fallback PNG
  read-only;
- cleanup durável, reconciliação com backoff, retry bloqueado até limpeza,
  cancelamento em fases distintas e node-loss sem sucesso implícito;
- token Kubernetes projetado/rotativo de 600 s e RBAC sem
  list/watch/update;
- OCI/device/scrcpy por digest, SBOM/provenance/signature no release workflow.

## Evidência executada

Contracts e runtime:

```bash
dart test libs/experience_contracts/test/remote_execution_contracts_test.dart
dart test libs/execution_runtime/test/remote_scheduler_service_test.dart \
  libs/execution_runtime/test/remote_kubernetes_dispatcher_test.dart \
  libs/execution_runtime/test/remote_worker_service_test.dart \
  libs/execution_runtime/test/system_remote_worker_backend_test.dart \
  libs/execution_runtime/test/scrcpy_remote_session_test.dart \
  libs/execution_runtime/test/kubernetes_remote_job_test.dart \
  libs/execution_runtime/test/remote_cleanup_reconciler_test.dart
dart test apps/remote_session_gateway
dart test apps/remote_worker
dart test apps/hosted_control_plane/test/remote_control_plane_test.dart
```

Resultado: 4 contracts, 22 testes runtime, 2 do gateway de sessão, 3 do worker
HTTP e 1 vertical OIDC/control-plane passaram. O soak de 80 runs em fases
terminais mistas terminou sem cleanup task pendente. Node loss gera retry
somente depois da limpeza; lease/retry antigo é fenced por generation.

Browser real Chromium 151:

```bash
cd apps/studio
CHROME_EXECUTABLE=/usr/bin/chromium \
  flutter test --platform chrome tests/remote_session_surface_web_test.dart
```

Seis cenários passaram: capability probe bounded, perfil H.264, decodificação
WebCodecs real com drain, bootstrap web/iframe, fallback PNG read-only e ingestão
H.264 com `session.end`. O teste descobriu e corrigiu três incompatibilidades
reais: `setUint64/getUint64` no backend JavaScript, codec AVC hexadecimal em
lowercase e `prefer-hardware` indisponível no Chromium headless.

PostgreSQL real:

```bash
dart run tools/hosted/verify_remote_scheduler_postgres.dart
```

Passou RLS, cleanup durável, geração/fencing de retry e ordem segura de remoção.
Completion com namespace forjado é rejeitada antes de persistir sucesso; o
containment authoritative é gravado na mesma transação que revoga a lease.

Kubernetes/supply chain:

```bash
./tools/verify/verify_kubernetes_manifests.sh
./tools/verify/verify_supply_chain.sh
```

- Helm default: 7/7 recursos válidos;
- Helm remote: 9/9 recursos válidos;
- Jobs core: 26/26 recursos válidos nas quatro variantes;
- 2 HTTPRoutes passaram checks estruturais;
- Kubernetes alvo de schema: 1.36.2;
- imagens, Actions, Android image e scrcpy server são pinados por digest.

## Gate remote execution

| Critério | Resultado |
|----------|-----------|
| batch web/Android usa Run/Evidence canônicos | Pass em worker/contracts; execução cluster é gate externo |
| sessão interativa exclusiva e com TTL | Pass em lease/session gateway |
| tenant não observa stream/artifact/worker alheio | Pass em API, ticket, S3 e PostgreSQL |
| imagem base/userdata restaurados | design por image digest + emptyDir/cleanup; KVM real é gate externo |
| worker perdido nunca implica sucesso | Pass em state machine/reconciler |
| soak sem lease/token/namespace lógico órfão | Pass em 80 runs; recursos reais dependem de cluster |
| sem iOS, físico ou source build | Pass por validações fail-closed e non-goals explícitos |

## Gates externos para certificação do device farm

1. aplicar chart e Jobs server-side num cluster com Gateway API instalada;
2. provar CNI deny-default, DNS e somente endpoints control/artifact/gateway;
3. aplicar admission policy que restrinja o ClusterRole a namespaces
   `workspace-run-*` com labels imutáveis;
4. executar web batch/interativo e Android batch/interativo em node pool
   Linux x86_64/KVM com RuntimeClass/device plugin reais;
5. cancelar durante provisionamento, execução e upload contra recursos reais;
6. matar pod/node/control plane e provar cleanup de Job, pod, route, Secret,
   volume e namespace;
7. executar soak prolongado e inspeção do userdata/AVD entre tenants;
8. medir capacidade, latência de vídeo/input e fairness sob quota.

Esses gates bloqueiam “device-farm certified”. Não são substituídos por YAML
renderizado ou mocks e estão ligados ao threat model hosted control plane/remote execution.
