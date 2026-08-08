# ADR-0018 — Content-set atômico e taxonomia adjacente de Scenario

- Status: aceita em 2026-08-13; vertical conteúdo atômico e Inventory executado em 2026-08-13
- Preserva: `CatalogManifest` v1, `WorkspaceSnapshot` v1,
  `ExperienceTopologyBundle` v1, endpoints legados e autoridade do Host

## Contexto

Journey e Inventory precisam consultar lifecycle, kind, surface, state, owner,
tags, component, fixture, render source e frame. Esses eixos pertencem ao
consumer e não podem ser inferidos de IDs, títulos, paths, lanes, payloads ou
nomes de módulos. Adicioná-los silenciosamente ao `CatalogManifest` v1 mudaria
um wire já publicado; armazená-los apenas no Studio criaria um banco paralelo
sem autoridade.

Topologia/layout já viajam em um recurso adjacente ao WorkspaceSnapshot. Abrir
snapshot, topologia e taxonomia por descrições independentes permitiria ao
Studio observar revisões diferentes entre chamadas, mesmo quando cada recurso
isolado fosse válido. Esse split-brain é especialmente incorreto para
Inventory: a consulta semântica e suas occurrences espaciais poderiam apontar
para catálogos distintos.

## Decisão

### `ScenarioFacetManifest` adjacente

conteúdo atômico e Inventory introduz `ScenarioFacetManifest` v1, ligado a exatamente um
`CatalogManifest.digest`. Ele mantém os eixos de produto em registries
consumer-owned, com IDs opacos e tipados:

- Scenario kind;
- experience surface e state;
- ownership area e tags;
- experience component e fixture;
- form factor e presentation frame.

Somente semânticas portáteis do protocolo são enums fechados:

- lifecycle `concept`, `current` e `historical`;
- render source `previewDescriptor`, `executionBinding`, `externalHarness` e
  `archiveArtifact`;
- frame `device`, `browser`, `desktopWindow`, `component` e `none`.

Quando o manifest existe, cada Scenario do catálogo possui exatamente uma
`ScenarioFacet`. Ausência do manifest permanece explícita. Nenhum reader pode
preencher eixos ausentes por heurística ou default implícito. Referências
cross-Application, state fora da surface, component/fixture de outra
Application, frame inconsistente, binding de outro Scenario e archive fora de
lifecycle historical falham antes da publicação.

O documento é fechado, limitado, canônico por JCS e possui digest próprio. O
authoring v2 e o compiler são adjacentes: Catalog e ExperienceTopology v1
continuam byte e semanticamente idênticos com ou sem taxonomia.

### Inventory sem banco paralelo

`ScenarioInventoryIndex` recebe somente o Catalog e seu FacetManifest. Ele
indexa todos os Scenarios canônicos e combina filtros com OR dentro de um eixo
e AND entre eixos. Uma `ProjectionKind.inventory` continua sendo uma lens
autoral de NodeInstances; ela pode conter apenas parte dos Scenarios e não
define a completude do Inventory semântico.

Cross-links usam `ScenarioId`. Um deep link espacial só é escolhido
automaticamente quando existe exatamente uma NodeInstance correspondente na
lens alvo. Zero ou múltiplas occurrences permanecem explícitas.

### Geração de conteúdo atômica

O Host compila Catalog, Topology/Layout e Facets a partir da mesma lista
imutável de documentos. Todos os novos documentos são validados antes de uma
única troca de geração; falha deixa a geração anterior integralmente intacta.

Para clientes novos, o Host publica:

- `experience.content.describe`;
- `experience.content.open`;
- `experience.content.changed`.

`open` exige exatamente `expectedRevision`, `catalogDigest` e
`contentSetDigest`. O content-set identifica:

- digest do Catalog;
- digest do WorkspaceSnapshot;
- digest opcional do ExperienceTopologyBundle;
- digest opcional do ScenarioFacetManifest.

`contentSetDigest` é JCS sobre esses digests de conteúdo; a revisão é fencing
separado e não altera a identidade de bytes equivalentes. `open` captura uma
única geração e concede handles imutáveis separados para os recursos presentes
em uma operação de quota tudo-ou-nada. Um handle concedido não muda quando o
Host promove uma geração posterior.

Mudança de Catalog, layout/topologia, Facets, Variant/Evidence ou renovação dos
handles visuais incrementa a revisão de conteúdo e emite o evento. O Studio só
publica o novo trio em memória após baixar, validar origin, purpose, media type,
size, expiração, digest de bytes, codec e todos os digests semânticos.

### Compatibilidade

`workspace.describe/open` e `experience.describe/open` permanecem
disponíveis e conservam seus wires. O Studio prefere o content-set quando a
capability pair está completa. Hosts legados continuam operáveis pelo caminho
anterior; capability parcial é erro explícito, não fallback silencioso.

## Alternativas rejeitadas

### Inferir taxonomia de ID, title, Source ou layout

Rejeitada porque converteria convenções locais em semântica canônica, faria
filters variarem por renderer e acoplaria o core a vocabulários de consumers.

### Colocar Facets diretamente no Catalog v1

Rejeitada porque quebraria compatibilidade e faria um eixo adjacente reescrever
bytes/digest de um documento publicado.

### Abrir três endpoints e reconciliar no browser

Rejeitada porque validação individual não prova que os três recursos pertencem
à mesma geração. Retry no cliente apenas reduz a janela; não fornece
atomicidade.

### Um único JSON agregado duplicando todos os documentos

Rejeitada porque aumentaria cópia, quotas e churn de wires. Handles separados
preservam limites e codecs independentes sem perder a geração comum.

## Consequências

- Inventory pode consultar os oito eixos sem conhecer o domínio do consumer;
- ausência de Facets ou de Projection continua representável;
- uma lens espacial parcial não apaga Scenarios do Inventory canônico;
- snapshot, topologia e taxonomia nunca são publicados como trio misto no
  Studio novo;
- Evidence permanece no WorkspaceSnapshot v1, mas participa da identidade da
  geração pelo digest do snapshot;
- há custo adicional de resources, revisão/evento e corpus de conformance;
- futuros documentos adjacentes precisam entrar em uma versão compatível do
  content-set, nunca em um map irrestrito.

## Rollout e evidência requerida

1. contracts, schema, compiler, corpus negativo e preservação dos wires v1;
2. content-set Host com quota atômica e fencing stale;
3. transport/controller Studio com preservação do trio anterior em falha;
4. reference consumer com cobertura 1:1 de todos os Scenarios;
5. Inventory canônico + projection espacial, filtros por URL e deep links;
6. RPC probe compara os bytes novos aos endpoints legados;
7. browser real prova cards canônicos, occurrence lens, filtros, a11y e ausência
   de erros severos.

Resultados executados pertencem ao plano/resultados de conformance; esta ADR
registra a decisão normativa e não, por si só, promove o gate conteúdo atômico e Inventory.
