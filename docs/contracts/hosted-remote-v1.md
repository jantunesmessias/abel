# Hosted e remote contracts v1

Status: normativo. Owners: Hosted/Remote + Contracts. Schemas externos:
`schemas/v1/hosted-collaboration.schema.json` e
`schemas/v1/remote-execution.schema.json`.

## Compatibilidade

Todo documento usa JSON Schema Draft 2020-12, `schemaVersion: 1` quando possui
header, campos fechados e JCS/RFC 8785 para identidade semântica. Writers v1
não emitem campo desconhecido; readers rejeitam extensão fora de extension
point. Minor futura deve continuar lendo a minor anterior. Mudança de enum,
invariante ou canonicalização exige nova versão/migration.

IDs são opacos; conteúdo usa `sha256:<hex>`. UTC é RFC 3339 terminado em `Z`.
Nenhum payload público contém type de Flutter, `dart:io`, PostgreSQL, S3,
Kubernetes ou library de serialização.

## Hosted v1

Kinds do schema: Principal, Organization, Membership, HostedWorkspaceLink,
WorkspaceRevision, WorkspaceChangeSet, WorkspaceConflict, CollaborationEvent,
PresenceLease, CommentThread, AuditEvent, IdempotencyRecord e
HostedBlobDescriptor.

Regras:

- `tenantId` participa de toda identidade persistida; ele vem do principal
  autenticado e deve coincidir com payload/repository;
- owner/admin: todos os effects hosted; editor: read/comment/push/publish;
  reviewer: read/comment/approve; viewer: read;
- push requer base/expected/proposed digest e idempotency key;
- key repetida com request digest diferente falha; com digest igual reproduz a
  resposta sem repetir o efeito;
- conflito devolve base/current/proposed e não altera head;
- event sequence é monotônica por tenant/workspace; replay `after=N` retorna
  somente `sequence > N` em ordem, no máximo 1.000;
- presence TTL permitido é 10–300 s, default 60 s;
- comment, approval, finding, evidence e release ligam-se a subject digest;
- blob key é exatamente
  `tenants/<tenant>/blobs/sha256/<digest-sem-prefixo>`; bytes não entram no
  documento nem no PostgreSQL.

## Remote v1

Kinds do schema: RemoteExecutionRequest, RemoteExecutionPlan, RemoteRun,
RemoteLease, RemoteSessionTicket, RemoteArtifactManifest e
RemoteContainmentReport. Worker descriptor e signed-plan/capability envelopes
são contratos internos tipados governados por ADR-0005.

Matriz válida:

| Target | Mode | Transport |
|--------|------|-----------|
| web | batch | none |
| web | interactive | webDirect |
| androidEmulator | batch | none |
| androidEmulator | interactive | scrcpyH264Control ou periodicScreenshotReadOnly |

Somente roles de artifact `webBuild`/`androidApk`, `interactionScript` e
`gatewayPlan` são aceitos. Web exige webBuild; Android exige androidApk e
DeviceImageDescriptor pinado. Source archive, build command e imagem/tag
mutável não são extension points.

State machine e terminais:

```text
queued -> scheduled -> provisioning -> running -> uploading -> succeeded
   \          \             \            \           \
                    failed | cancelled | unknown
```

`succeeded` exige manifest e containment validados. Worker/node perdido não é
sucesso. Lease possui generation 1–10, token e expiry; mutation da generation
anterior falha. Interactive run não é retentado como se input fosse idempotente.

Session ticket dura no máximo dois minutos, vincula tenant/run/principal/role,
transport e nonce. A grant efêmera do Studio contém endpoint WSS sem query ou
userinfo; compact ticket é enviado como primeiro frame `authenticate`.

## Framing de stream v1

Frame `DVX1`:

| Offset | Bytes | Campo |
|--------|-------|-------|
| 0 | 4 | magic `DVX1` big-endian |
| 4 | 1 | channel 1..4 |
| 5 | 3 | reservado zero |
| 8 | 8 | sequence big-endian, 1..`2^53-1` |
| 16 | 4 | payload length big-endian |
| 20 | N | payload |

Channels: H.264 ≤ 4 MiB, control/metadata ≤ 64 KiB e PNG ≤ 16 MiB. Sequence é
estritamente `last+1`. O codec escreve os oito bytes como high/low uint32 para
portabilidade Dart VM/JavaScript sem alterar o wire.

Pacote H.264 `H264` usa header equivalente de 20 bytes: flags configuration,
keyFrame e hasTimestamp; timestamp é 0..`2^53-1`. Configuration não tem
timestamp; frame tem timestamp; bytes são Annex B. Metadata `video.session`
define codec `avc1`, width/height e resize. Control aceita somente o conjunto
traduzível ao protocolo scrcpy oficial; fallback PNG não negocia channel de
controle.

## Segurança e evidência

Unknown field/version, payload oversized, sequence gap, timestamp não portátil,
ticket replay, origin/role/run divergente, artifact digest errado ou
containment forjado falham fechados. Threats e gates estão em ADR-0004/0005,
`docs/security/hosted-remote-threat-model.md` e resultados V4/V5.
