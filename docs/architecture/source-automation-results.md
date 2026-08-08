# Resultado executado do source automation

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64.

## Entregue

- `.evidence.zip` determinístico e offline, com manifest JCS, blobs por digest e
  reader ZIP fail-closed sem extração;
- adapters de source filesystem, Git commit e Git worktree;
- `SourceBinding`, diff direto/transitivo, `ImpactPlan`, gate conservador e
  `ContextBundle` sanitizado;
- commands `source inspect`, `source diff`, `plan`, `context export`, `gate`,
  `release bundle`, `release verify-bundle` e `release seal`;
- discovery de plugins por manifest JCS, negociação v1, timeout, resultado
  terminal único, grants e execução Linux em bubblewrap;
- `mcp serve` stateless `2026-07-28`, read-only por construção.

## Gate observado

`tools/verify/verify_source_automation.sh` terminou com exit `0`. Ele executou formatter, analyzer,
architecture guard, suites Dart/Flutter, widget/accessibility, Chromium real,
Gateway/containment, consumers e os testes source automation.

O corpus rotulado Q-18 registrou:

```json
{"cases":10,"decisions":14,"falseNegatives":0,"falsePositives":0,"falseNegativeRate":0,"falsePositiveRate":0}
```

O teste hostil de plugin executou processo real no sandbox. O processo não
observou o arquivo do workspace nem variável sensível herdada; mutation sem
preview/grant foi negada antes de spawn. Q-17 e Q-18 estão fechadas.

## Limites honestos

source automation não afirma assinatura/attestation, plugin dinâmico fora de Linux/bubblewrap,
análise AST/symbol, hosted, remote runtime ou evidence Android ampliada. Seal é
integridade por policy, não Approval.
