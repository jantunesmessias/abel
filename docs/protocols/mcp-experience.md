# MCP Experience v2

Extensão adjacente ao [MCP read-only v1](mcp-read-only.md), transportada por
stdio no protocolo MCP `2026-07-28`. O servidor mantém os quatro tools v1 e
adiciona resources e tools conforme o `ResolvedKitPlan` do consumer.

## Transporte, identidade e limites

- o launcher local abre o processo e controla o pipe; não há listener de rede;
- `_meta.clientInfo` é atribuição, não autenticação remota;
- cada line e cada result canônico têm no máximo 1 MiB;
- captures têm no máximo 64 MiB e precisam ser PNG válido;
- source excerpt tem no máximo 64 KiB e passa por redaction;
- audit genérico aceita no máximo 10.000 records;
- page, graph, batch e listas possuem limites próprios e rejeitam unknown fields.

## Resources

- `experience://content-set`
- `experience://catalog`
- `experience://topology`
- `experience://facets`
- `experience://scenario-lab`
- `experience://motion`

Cada resource pertence à mesma geração compilada. Ausência do Module/documento
remove ou torna o resource indisponível; o servidor não fabrica conteúdo.

## Tools read-only

O core v1 preserva `source.inspect`, `source.diff`, `impact.plan` e
`bundle.verify`. O backend Experience acrescenta:

- Catalog: `catalog.list`, `catalog.search`, `catalog.get`,
  `catalog.neighborhood`, `catalog.graph`;
- Context/source: `context.export`, `source.excerpt`;
- Evidence/capture: `evidence.index`, `capture.index`, `quality.validate`,
  `quality.capture.diff`, `quality.bundle.verify`, `quality.evidence.verify`;
- Authoring query: `authoring.describe`, `authoring.getHead`,
  `authoring.getDraft`, `authoring.getChangeSet`, `authoring.getReview`.

Queries aceitam somente IDs, digests, seleção e budgets fechados. Nenhum tool
aceita command, endpoint, URI de authority, content root ou path absoluto.

## Capabilities e efeitos

`capability.issue` emite capability genérica para
`quality.tests.run` ou `quality.capture`. Ela liga principal, tool,
content-set esperado e payload digest, expira em dois minutos, é single-use e
pode ser encerrada por `capability.revoke`. A primeira tentativa consome
a capability mesmo quando o payload, digest, tool ou estado divergem.

`quality.tests.run` aceita runner fechado `dart|flutter` e até 32 targets
relativos. `quality.capture` importa um PNG workspace-local para o CAS; não
dirige câmera, browser ou device.

Authoring usa grants do contrato de domínio e expõe:

- `authoring.grant`, `authoring.openDraft`, `authoring.layout.edit`;
- `authoring.layout.batchMutate`, bounded a 16, sequencial e `atomic=false`;
- `authoring.review.prepare`, `authoring.finding.record`,
  `authoring.concept.propose`;
- `quality.acceptance.record`;
- `authoring.layout.promote`.

Grant, owner, source/content/draft/review digests e connection epoch são
validados pelo Runtime. Resultados e erros são codecs fechados. Acceptance é
Host-evaluated; sem decisão humana `approve` no head atual, promotion permanece
negada.

## Falhas e privacidade

Tool failures retornam `isError=true` e `structuredContent.errorCode`; erros de
Authoring incluem o documento tipado em `details`. Outputs públicos não devem
conter capability/grant/principal/authority, paths, handles ou secrets. Source
usa allowlist semântica, confinamento regular-file/no-link e redaction antes do
resultado. Desabilitar um Module remove discovery e dispatch, não apenas UI.

## Conformance local

```bash
./tools/verify/mcp_experience_reversibility_test.sh
./tools/verify/verify_mcp_experience_vertical.sh
```

O segundo comando é uma prova de integração local do reference consumer. Não é
claim de transporte remoto autenticado, sandbox, hosted ou captura ativa.
