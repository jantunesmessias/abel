# Resultados — composição modular MC0–MC6

Status: implementação e gates locais aprovados em 2026-08-10.

Atualização de proveniência: o vertical posterior SR0–SR9 consumiu este seam e
aprovou o Studio operacional. As claims MC0–MC6 abaixo permanecem no escopo
histórico original; o resultado novo está em
`devex-studio-reconstruction-results.md`.

Atualização de 2026-08-11: o único Studio foi migrado para Jaspr e
`sessions.local`/`gateway.interceptor` passaram a publicar, respectivamente,
`studio.target` e `studio.gateway`. Os digests Flutter abaixo permanecem
evidência histórica; novas distribuições usam `jaspr build`.

## Resultado entregue

O DevExKit deixou de interpretar a superfície local como um bloco único. O
catálogo built-in possui 17 Modules, seis Profiles, requirements por
capability, provider bindings e settings schemas. Consumer config v1/v2
convergem para o mesmo `KitPlanResolver`; o `ResolvedKitPlan` canônico governa
CLI, Host e Studio, e o estado observado é publicado em
`EffectiveKitManifest`.

Não foi criado carregamento dinâmico de Dart. O inventário e as factories são
compile-time; configuração seleciona apenas Modules empacotados.

## Evidência por gate

| Gate | Resultado observado |
|------|---------------------|
| MC1 | contracts/schemas v1/v2 fechados, JCS/digest/ordem estáveis e adjacent-version tests |
| MC2 | config v2, precedência, profile override, tradução v1 e migration atômica/rollbackável |
| MC3 | lifecycle prepare/start/stop/dispose, cancel, rollback reverso, resource owner e health |
| MC4 | parser/dispatch condicionais; bootstrap commands universais; comandos ausentes quando Module disabled |
| MC5 | plano transportado com path/digest; Host com RPCs condicionais; 20 ciclos e Gateway sidecar sem resíduo |
| MC6 | seam de routes/contributions condicionado pelo manifest; Grant não habilita Module; plan digest único |
| AP4 | projector in-memory funciona sem imagem e preserva visual Evidence/status quando injetado |

No profile `journey-preview`, o Host expôs apenas
`devex.kit.describe`/`devex.kit.health`, não abriu capture bridge nem Gateway e
persistiu um manifest com o mesmo plan digest. No CLI, Android, Gateway,
Sessions, source/plugins/MCP/hosted/remote e release não foram registrados.

## Distribution v2

`DistributionReleaseCodec` lê v1/v2. O builder v2 grava ModuleCatalog,
Modules, Profiles, components, entrypoints e ownership de files.

Execuções reais:

- `full-local` `0.1.0-preview.1`: duas reconstruções, 35 arquivos e mesmo
  manifest/release digest
  `sha256:31e0bfecfb2ac3d9d8320658a413b8873fba68c747e5ca0651bb940169abb5fa`;
- install, update para `0.1.0-preview.2`, rollback para preview.1, aliases e
  consumidor externo passaram;
- `journey-preview` `0.2.0-preview.1`: duas reconstruções, 35 arquivos, recursos
  Flutter self-hosted, sem
  Gateway, digest
  `sha256:0fd00f05ba173ddb0b2cf54cbff5cf6c0282fccde90a40f7c06f6e937e98beb2`;
- `gateway-lab-headless`: CLI/Host/Gateway, sem Studio, quatro files no
  manifest, digest
  `sha256:eed50a81dad363ef7f825e6654d8c3aa802da5b960354c0dd0a2f443fc0636bf`.

## Gates executados

```text
./tool/check.sh                       exit 0
./tool/verify_modular_distribution.sh exit 0
./tool/verify_v03_distribution.sh     exit 0
```

O check integral passou format/analyze fatal, architecture/supply-chain,
contracts (69), engine (35), runtime (161), adapters Flutter/AutoPreview,
Studio VM/Chromium, CLI, Host, Gateway, hosted/remote, containment netns e os
consumers sample/friction.

## Limites

- O catálogo é built-in; esta entrega não torna Module um plugin de código
  arbitrário.
- Os gates são locais/portáteis. As restrições externas V4/V5 e suas claims de
  certificação permanecem inalteradas.
- `gateway-lab-headless` foi acrescentado para expressar distribuição sem UI;
  `gateway-lab` continua incluindo Studio shell.
- MC6 não comprova shell de produto, catálogo Host → Studio, artifact handles,
  inspector/provider selection ou `devex dev` supervisionado. Esses requisitos
  são SR0–SR9.
- AP4 não comprova a cadeia operacional CAS → Host → Studio; somente o seam de
  projeção tipado/in-memory foi exercitado neste resultado.
