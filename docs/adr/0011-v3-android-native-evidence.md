# ADR-0011 — V3 evidence nativa Android correlacionada

Status: aceita em 2026-08-09.

## Contexto

V3 precisava capturar screenshot, semântica, logs, vídeo e performance no app
host-native sem criar uma segunda hierarquia de evidence, sem afirmar
attestation do device e sem transformar a ausência de uma modalidade em falha
de todas as outras. Capturas visuais e logs também não poderiam introduzir PII
ou secrets no CAS por conveniência operacional.

## Decisão

1. Toda modalidade produz `Artifact` dentro do mesmo `Evidence`, com um único
   `ExecutionFingerprint`. `AndroidEvidenceManifest` registra a correlação,
   ambiente e o estado independente `collected`, `unavailable`, `failed` ou
   `policyDenied` de cada modalidade.
2. Emulador Android é sempre `hostNative`; V3 não possui nem infere
   `deviceAttested`. A imagem é identificada por descriptor e digest semântico
   de AVD, build fingerprint, API e ABI — não por claim criptográfica.
3. Semântica persiste estrutura, flags, bounds e SHA-256 de text,
   content-description e resource-id. Logcat persiste somente sequence,
   priority e SHA-256 de tag/message. Os valores crus nunca entram no CAS.
4. Screenshot, screen recording e Perfetto exigem
   `syntheticDataConfirmed=true`; sem a confirmação cada modalidade recebe
   `policyDenied` e as modalidades sanitizadas continuam.
5. O fingerprint inclui renderer, locale, timezone, ADB, build Android, Dart,
   digest do ambiente, digest do containment report, inputs adicionais e
   source revision quando fornecida. `gatewayOnly` permanece honesto para
   `adb reverse`; V3 não eleva o Android a `targetEnforced`.
6. Comparação visual opera sobre RGBA normalizado e policy versionada de delta
   por canal/razão de pixels. Comparação semântica opera sobre snapshots JCS e
   policy versionada de nodes, com opção explícita de ignorar bounds.
7. O provider aceita somente emulador gerenciado e containment report executado
   do mesmo target. O workspace operacional do AVD e o workspace proprietário
   do CAS/release podem ser distintos e são ambos explícitos.
8. Processos ADB têm output limitado, timeout proprietário e encerramento
   TERM→KILL. Bootstrap aguarda boot completo, animação parada e Package Manager
   responsivo. Arquivos remotos de vídeo/Perfetto são removidos em `finally`.

## Consequências

- Falta de Perfetto degrada somente `android.performance-trace`.
- Captura raw em ambiente não sintético é negada antes do comando ADB.
- Hashes preservam comparação de igualdade, mas não permitem reconstruir
  conteúdo textual; debug textual deve acontecer fora do artifact publicável.
- O diretório de trace é `/data/misc/perfetto-traces`, compatível com o domínio
  SELinux `shell` observado no Android API 35.
- Vídeo e trace podem aumentar bundle e retenção, mas continuam sujeitos ao CAS
  e às quotas existentes.

## Evidência

- `tool/verify_v3.sh` e o modo `DEVEX_V3_EVIDENCE=1` do gate Android;
- `android_evidence_contracts_test.dart`;
- `android_evidence_provider_test.dart`;
- `evidence_comparison_service_test.dart`;
- `android_target_provider_test.dart`, inclusive morte real de processo;
- execução host-native registrada em `docs/architecture/v3-results.md`.
