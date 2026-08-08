# Resultados — AutoPreview AP0–AP4

Status: implementação e gates locais aprovados em 2026-08-10 para Flutter
3.44.8 / Dart 3.12.2.

Escopo: AP4 comprova o contract/projector do Journey Map com handles fornecidos
por teste. A integração operacional CAS → Host → Studio, device frames,
inspector e coleta iniciada pelo Studio pertencem ao vertical SR0–SR9 e não são
claim deste resultado.

Atualização de proveniência: o vertical posterior SR0–SR9 implementou e
aprovou essa integração operacional. Isso não reescreve o gate AP4; a evidência
nova está em `devex-studio-reconstruction-results.md`.

## Resultado entregue

`devex_preview` oferece `AutoPreview`, `AutoMultiPreview` e
`AutoPreviewVariant` sobre `Preview`/`MultiPreview` oficiais. O
`examples/sample_flutter` anota a factory real `createSampleApp`. O corpus
atual cobre os cinco Scenarios do Journey com sete descriptors e três Variants:
`phone.light.en-us`, `phone.dark.en-us` e `desktop.light.en-us`; o entrypoint de
produção não importa DevExKit.

Analyzer descobre as annotations const, o engine compila manifest/registry em
`.dart_tool`, e um runner `flutter test` isolado captura cada descriptor sob
`RepaintBoundary`. PNGs passam pelo inspector e CAS; manifest/report registram
Scenario, Variant, renderer, fingerprint, capture key, status e digests.

## Gates AP0–AP4

| Gate | Resultado observado |
|------|---------------------|
| AP0 | Widget Previewer oficial encontrou as annotations e Variants com `--legacy-preview-detection` |
| AP1 | API Flutter, `Variant`, descriptors/manifests/report e schema v1 conformes |
| AP2 | scanner fail-closed e registry efêmero; sem build_runner ou geração em `lib/` |
| AP3 | subprocesso por descriptor, PNGs reais, falha parcial, timeout, quotas, CAS e Evidence |
| AP4 | projeção Journey Map in-memory com handle injetado, fidelidade e status/freshness explícitos |

O detector LSP default do Widget Previewer falhou dentro do Flutter Tool 3.44.8;
o detector legado funcionou. O runner não depende de nenhum detector do
Previewer e não usa APIs internas de exportação.

## Evidência executada

```text
./tool/verify_auto_preview.sh exit 0
./tool/check.sh               exit 0
```

O gate focado passou no baseline AP0–AP4:

- 2 testes da API Flutter;
- 5 testes do compiler;
- 8 testes de scanner/runner, incluindo processo Flutter real com duas
  Variants;
- o sample montando a factory real.

Atualização operacional de 2026-08-11: o vertical do Studio coletou sete
descriptors/PNGs, selecionou somente projections válidas por Variant e mostrou
Evidence para todos os cinco Scenarios. Uma invocação isolada de um Scenario
terminou normalmente em 83,68 s e não deixou processo órfão; portanto o custo de
startup é backlog de performance, não evidência de deadlock. Eventual worker
aquecido ou batching deve preservar a falha parcial e o isolamento que este
gate exige.

O check integral repetiu a integração de captura no conjunto de 161 testes do
runtime e passou os 22 testes VM + 7 Chromium do Studio. A projeção recusa
artifact para status de falha e diferencia `collected`, `stale`, `missing`,
`failed`, `unsupported` e `policyDenied`.

## Claim permitida

O renderer `flutter-test` entrega Evidence `structural`. Ele não comprova
plugins nativos, sistema operacional, teclado/permissões, Gateway/backend real,
emulador ou device. AutoPreview não substitui App Adapter nem Android; é o
provider visual opcional e barato do profile `journey-preview`.

Persistência de pixels exige confirmação de dados sintéticos. Contenção de
rede continua dependente do host e nunca é inferida apenas da allowlist de
environment.

O Widget Previewer permanece a experiência interativa e não é exportador de
PNG. No Flutter 3.44.8 o detector LSP default falha; o gate interativo usa
`--legacy-preview-detection`. Allowlist, timeout e staging não provam isolamento
portátil de rede/memória; sem sandbox comprovado o fingerprint permanece
`NetworkContainment.unconstrained`.
