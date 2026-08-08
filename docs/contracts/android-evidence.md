# Android Evidence v1

`AndroidEvidenceManifest` complementa, sem substituir, `Evidence` e
`ExecutionFingerprint`. Seu schema público é
`schemas/evidence/android-evidence.schema.json`.

## Correlação e ambiente

Um manifest contém:

- `correlationId` único da coleta;
- `targetId` do emulador gerenciado;
- `runtimeFidelity: hostNative` fixo;
- ambiente com AVD/build fingerprint, digest semântico da imagem, API, ABI,
  renderer, locale, timezone e toolchain;
- digest do `TargetContainmentReport` executado;
- confirmação explícita de dados sintéticos;
- exatamente uma observação por modalidade solicitada/suportada.

`imageDigest` identifica o descriptor observado; não é digest byte a byte de
uma imagem de sistema nem attestation. Emulador nunca recebe
`deviceAttested`.

## Estados por modalidade

- `collected`: exige `artifactDigest` presente;
- `unavailable`: comando/capability não existe no target;
- `failed`: capability existia, mas a coleta/validação falhou;
- `policyDenied`: policy impediu executar a coleta.

Estados diferentes de `collected` proíbem `artifactDigest`. A ausência de uma
capability não invalida artifacts coletados por outras modalidades.

## Privacidade

- `android.semantics`: documento JCS `AndroidSemanticsSnapshot`; text,
  content-description e resource-id aparecem somente como SHA-256;
- `android.logcat`: documento JCS `AndroidLogcatSnapshot`; tag e message aparecem
  somente como SHA-256;
- `android.screenshot`, `android.screen-recording` e
  `android.performance-trace`: exigem confirmação de dados sintéticos.

O provider não oferece opção para persistir o XML/UIAutomator ou logcat crus.

## Comparação

`VisualComparisonPolicy` e `SemanticComparisonPolicy` são inputs versionados.
`EvidenceComparisonReport` registra digests de expected, actual e policy,
métricas, unidades comparadas/alteradas e decisão. Falha de policy usa exit code
`4` na CLI; erro de formato continua distinto da diferença observada.

## CLI

```text
workspace target android evidence ...
workspace evidence export-artifact ...
workspace evidence compare-visual ...
workspace evidence compare-semantics ...
```

O comando Android exige `--catalog-digest`, `--containment-report`, package,
serial gerenciado e confirmação sintética para mídia raw. `--evidence-workspace`
define quem possui CAS, ponteiro de frescor e release.
