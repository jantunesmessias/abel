# Source & Automation v1

Os documentos externos são governados por
`schemas/source/source-automation.schema.json` e têm identidade JCS/SHA-256.

## Fluxo

```text
filesystem ou Git
  -> SourceSnapshot (complete | partial | unknown)
  -> ChangeSet
  -> SourceBinding[]
  -> ImpactPlan
  -> gate / ContextBundle / ReleaseSeal
  -> AgentTask (ContextBundle + base + TTL + effects)
  -> AgentProposal (task + base + ChangeSet; preview only)
```

Regras:

- commit Git é lido sem checkout; worktree inclui arquivos rastreados e não
  rastreados, exceto diretórios de tooling/state declarados;
- symlink, arquivo ilegível ou limit excedido torna o snapshot parcial;
- diff completo requer os dois snapshots completos;
- impacto direto usa globs normalizados; dependentes são propagados até ponto
  fixo;
- binding/repository desconhecido ou snapshot incompleto zera
  `reusableSubjects` e marca todos os bindings impactados;
- ContextBundle nunca significa “repo inteiro”: paths são explícitos, UTF-8,
  conferidos por digest e sanitizados antes do output.

`SourceBinding.symbol` está reservado como refinement conservador. O contrato atual não usa
ausência de mudança simbólica para liberar evidence.

## Boundary de agentes

`AgentTask` é um envelope imutável e expirável, ligado ao digest de um
`ContextBundle` sanitizado e ao digest exato do snapshot base. Seu principal é
explícito, o objetivo tem limite de 4.096 caracteres, o TTL máximo é 24 horas e
os únicos effects possíveis são `inspect` e `propose`. Não existe effect
`apply`, `approve`, `seal` ou `publish`.

`AgentProposal` liga `taskId` e `taskDigest` ao `baseSnapshotDigest` e ao
`changeSetDigest`. O campo fechado `requiresExplicitApply: true` faz parte do
digest do documento. A aplicação ocorre em operação separada, com preview,
expected digest atual e grant humano ou de CI; uma proposta nunca é autoridade
para modificar fonte.

Texto do objetivo, arquivos e output de ferramenta permanecem dados não
confiáveis. Parsers rejeitam campos desconhecidos, effects duplicados, datas
não UTC, TTL inválido, elevação de effect e qualquer divergência de digest.
