# ADR-0005: remote execution, isolamento e streaming

- Status: aceita e implementada em remote execution; certificação condicionada a cluster KVM
- Data: 2026-08-09
- Decisões afetadas: D-025, D-042…D-047

## Contexto

remote execution precisa executar targets web e Android efêmeros em batch ou interativamente
sem transformar worker em build service, dar acesso ao banco ou aceitar sucesso
na ausência de evidência. Android/KVM amplia privilégio e streaming introduz
credenciais, framing e input remotos adicionais.

## Decisão

1. O scheduler é persistente e tenant-scoped. A state machine contém queued,
   scheduled, provisioning, running, uploading e terminais succeeded, failed,
   cancelled ou unknown. Quota, prioridade, lease, heartbeat, generation,
   cancellation e retry são transacionais.
2. Cada tentativa é um Kubernetes Job num namespace opaco por tenant/run.
   ServiceAccount sem token, Secret imutável, trust ConfigMap, emptyDir,
   NetworkPolicy e HTTPRoute/Service interativos pertencem à tentativa.
3. Worker nunca acessa PostgreSQL. Ele recebe plano JWS assinado, capability JWT
   curto e artifacts imutáveis por digest, e reporta somente pelos endpoints
   concedidos. Generation antiga falha por fencing.
4. O único input executável é web build ou APK pronto. Source, package manager e
   build arbitrário falham fechados.
5. Web usa Chromium/App Adapter para batch; interativo serve o target via
   gateway/iframe autenticado. Android usa emulator/ADB e imagem/AVD pinados;
   KVM vem de RuntimeClass + extended resource, nunca hostPath privilegiado.
6. Android interativo segue o protocolo scrcpy: H.264 e control são canais
   separados, bounded e ordered. Studio usa WebCodecs quando o perfil é
   suportado. Captura PNG periódica é fallback somente leitura, nunca um canal
   de controle degradado silenciosamente.
7. Ticket viewer e worker são audience/role/run/tenant/nonce/TTL-bound. Ticket é
   enviado no primeiro frame WSS, não na URL. Bootstrap web é one-shot, vira
   cookie `HttpOnly/Secure/SameSite` e o iframe usa sandbox/referrer policy.
8. Web/control plane seguem Pod Security restricted. Android usa perfil mínimo
   dedicado em node pool Linux x86_64/KVM. Egress é deny-default e limitado aos
   endpoints control/artifact/gateway/DNS declarados.
9. Completion enviada pelo worker é validada contra namespace, SA, pod profile
   e endpoint classes esperados. O scheduler grava o containment authoritative
   e revoga a lease na mesma transação.
10. Todo terminal gera cleanup durável. Retry espera limpeza; reconciler aceita
    DELETE 404, confirma namespace ausente e usa backoff bounded. Worker/node
    perdido jamais implica sucesso.
11. O control plane usa token Kubernetes projetado de 600 s, relido por request;
    RBAC concede apenas create/get/delete necessários e não list/watch/update.
12. Images OCI, Android image e scrcpy server são pinados por digest. Release
    produz SBOM, provenance, attestation e assinatura.

## Alternativas rejeitadas

- worker long-lived compartilhado: aumenta estado residual e blast radius;
- worker com acesso ao banco: rompe least privilege e cria segundo repository;
- source/build remoto: transforma remote execution em execução arbitrária de supply chain;
- VNC/RDP genérico: superfície maior e sem contrato alinhado ao target;
- polling de screenshot com input: latência e semântica ambígua; fallback fica
  explicitamente read-only;
- token de cluster estático: credencial longa e difícil de revogar;
- retry antes do cleanup: permite duas tentativas observarem o mesmo recurso;
- marcar unknown como succeeded: fabrica evidência na ausência de observação.

## Consequências e rollback

remote execution requer CNI NetworkPolicy, Gateway API e, para Android, RuntimeClass/device
plugin/pool KVM dedicados. Desabilitar `remote.enabled` remove RBAC/token e deixa
hosted control plane/local intactos. Uma tentativa pode ser finalizada como unknown quando a
verdade não é recuperável; isso é comportamento correto, não erro a mascarar.
Cleanup debt é operável e bloqueia retry do run afetado.

## Evidência

- schema `remote-execution.schema.json`, codecs e fixtures;
- scheduler/repository PostgreSQL, Jobs, worker, gateway e Studio browser tests;
- soak/reconciliation/node-loss e completion forjada;
- render das quatro variantes, Helm lint e kubeconform strict;
- `docs/architecture/remote-execution-results.md` e threat model hosted/remote.

CNI, admission, Gateway API server-side, web/Android E2E e node-loss em KVM real
continuam gates externos de certificação; YAML válido não os substitui.
