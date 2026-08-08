# Resultado executado do V0 local

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64 e Google
Chrome Stable headless com CanvasKit.

## Slices implementados

| Slice | Resultado atual | Evidencia executavel |
|---|---|---|
| V0-A contracts headless | implementado | schemas/fixtures, compiler deterministico, CAS/locks e CLI validate/explain/compile |
| V0-B compreensao estatica | implementado | Studio, deep links, estados imutaveis, a11y widgets, Journey Map benchmark e auditoria Orca/Chromium |
| V0-C execucao web | implementado | Host RPC real, origins separados, lifecycle/cancel/reset e 20 ciclos sem residuo |
| V0-D evidence/release | implementado | PNG validado, pixel digest, freshness, CAS, PublicationView, bundle offline e CLI capture/release build |

O caminho direto de captura tambem foi fechado: `devex.capture.request` emite
um handle loopback one-shot ligado a Session/origin; o App Adapter captura um
`RepaintBoundary`, faz upload bounded e o Host valida o PNG antes de publicar o
receipt e persistir os bytes em CAS. O teste de integracao le o mesmo blob pelo
digest produzido pelo Host. O protocolo e limites estao em
`docs/protocol/host-app-adapter-v1.md`.

## Consumer real e fluxo V0-D

Execute:

```bash
./tool/verify_v0_flow.sh
```

O gate compila `examples/sample_flutter/tool/devex_main.dart`, serve o build em
loopback pelo runtime, captura 1280x720 no Chrome e chama o CLI publico a partir
do consumer. Execucao de referencia desta revisao:

- CatalogManifest: `sha256:ee0fc7dcc5d5cbf66a924b4b0c8ab6f25ec5f728b348bd96bb7c8dea7c2aad36`;
- PNG: `sha256:3192449ecadf9bed9dbd1dac908a82eb2f640929a2340764d6cd08b4b6439c91`;
- pixel digest: `sha256:203f80cf8e829898fcfc206e2efaed757fee43c8317d42df8eb0d27b0bdfbbc7`;
- Evidence: `sha256:0eb98c8e61874fb3d9f872a0b33e0d34b437099720565c3517840d74b377cb23`;
- Release: `sha256:244d707d766996dd4714d4ab80ff6aa74bc92343106f9bf2444b280609ffb987`;
- ReleaseBundle: `sha256:87d4b66806f083e51e5eab7dfd234ad38e241d5f1ec2a570636d8c07b3f1bb1c`.

Esses digests identificam a execucao observada, nao um golden global: timestamp,
IDs de Evidence/Release e bytes produzidos pelo renderer pertencem ao
fingerprint da execucao.

## Gate assistivo executado

Em 2026-08-09, Orca 50.2 sobre AT-SPI 2.60.6 e Chromium 151.0.7922.108 no
Niri/Wayland percorreu Explore → Journey → Estrutura → Scenario. Nomes, roles,
ordem de foco e selecao corrente foram anunciados. A auditoria detectou e
corrigiu o idioma acessivel, agora `pt-BR`; o leitor selecionou a voz
`Portuguese (Brazil)`. Zoom real de browser a 200% preservou viewport sem
overflow horizontal, em claro e escuro. Evidencia e comandos reproduziveis
estao em `docs/quality/studio-accessibility-v0.md`.

## Limites remanescentes

- O smoke prova build/render/capture/evidence/release do consumer, mas ainda nao
  automatiza a navegacao Studio Journey -> Scenario nem correlaciona o PNG a uma
  SessionTrace real.
- O resultado deste arquivo nao faz claim de Gateway; o vertical posterior
  V0.1 esta registrado separadamente em `docs/architecture/v01-results.md`.
  Host-native, Android e iOS continuam fora desta evidencia V0.
