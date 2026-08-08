# ADR-0017 — Topologia de experiência e layout por projection

- Status: aceita em 2026-08-13; vertical topologia e layouts executado em 2026-08-13
- Preserva: `CatalogManifest` v1, `WorkspaceSnapshot` v1, autoridade do Host e
  separação Module/Provider/Plugin

## Contexto

A arquitetura já determina que Journey/Transition definem significado e que
Projection/Layout definem geometria. A implementação pública, porém, expõe
apenas cascas de `Projection` e `Layout`: elas não possuem codec, schema,
digest, compiler, autoria, persistência ou transporte Host -> Studio. O Journey
Map atual ordena Scenarios em uma sequência visual, portanto não representa
ramificações, reencontros, instâncias repetidas nem curadoria espacial.

Adicionar coordenadas a `Scenario`, ou reinterpretar ordem de `scenarioIds`
como layout, misturaria identidade semântica e apresentação. Também faria uma
mudança puramente visual alterar o digest do catálogo e potencialmente marcar
Evidence como stale.

Alterar silenciosamente `CatalogManifest` ou `WorkspaceSnapshot` v1 violaria a
regra de readers adjacentes. Duplicar todo o catálogo em uma classe v2 antes de
haver necessidade semântica criaria dois modelos de Workspace/Application/
Journey/Scenario para manter.

## Decisão

### Documentos adjacentes

topologia e layouts introduz dois documentos no bounded context Catalog & Docs:

- `ExperienceTopologyManifest` v1 referencia um `CatalogManifest.digest` e
  contém Boards, Projections, NodeInstances e EdgeInstances;
- `ProjectionLayoutManifest` v1 referencia o digest da topologia e exatamente
  uma Projection, contendo geometria curada, groups, lanes, annotations e
  camera.

São documentos canônicos, fechados, limitados e digeridos por JCS. Eles não são
extension maps e não alteram o wire v1 existente. Um snapshot agregado capaz de
transportá-los usa uma versão adjacente; reader v1 não ganha campos novos.

### Identidade e referências

- `Scenario` permanece estado semântico observável;
- `NodeInstance` é uma ocorrência visual estável de um Scenario em uma
  Projection; o mesmo Scenario pode ter várias instâncias;
- `Transition` permanece relação semântica dirigida;
- `EdgeInstance` materializa uma Transition entre duas NodeInstances e valida
  os endpoints semânticos;
- `Board` pertence a uma Application e organiza Projections;
- `Projection` é uma lens tipada sobre uma Application/Board e lista
  explicitamente suas instâncias;
- posição, tamanho, lane, group e camera nunca participam desses IDs.

IDs são opacos e tipados. Relações cross-Application, instâncias órfãs,
Transition fora da Journey, duplicatas e digests divergentes falham antes da
publicação.

### Tipos de projection e ausência

Kinds iniciais são `journey`, `inventory`, `history`, `comparison` e
`changeset`. O enum é fechado; novo kind incompatível exige versão adjacente.

Layout autoral ausente continua ausente. Um algoritmo pode produzir uma
proposta derivada em memória, identificada como tal, mas ela não vira fonte
autoral nem é persistida implicitamente.

### Host e Studio

O loader resolve os documentos uma única vez no Host. O Studio recebe apenas
read models canônicos por resource handles e não lê paths, YAML, staging ou
CAS. Seleção, deep link, Outline e Inspector usam a mesma Projection. O canvas
pode virtualizar apresentação, mas não descartar entidades do Outline
acessível.

### Compatibilidade e autoria

Fontes autorais novas possuem schema discriminado. A adoção é aditiva:
workspaces v1 continuam válidos sem topologia. Quando um formato autoral for
substituído, migration será preview-first, determinística, ownership-aware e
rollbackável; não há migration fictícia apenas para a ausência opcional de um
novo documento.

## Alternativas rejeitadas

### Coordenadas em Scenario ou Journey

Rejeitada porque mistura semântica/layout, impede múltiplas projections e
invalida digests semânticos por edição visual.

### Ordem de `Journey.scenarioIds` como grafo/layout

Rejeitada porque não representa branch/merge, instâncias repetidas ou lenses
distintas e transforma uma conveniência de leitura em autoridade espacial.

### Modelo próprio no Studio

Rejeitada porque faria o browser reinterpretar catálogo e disputar autoridade
com o Host.

### `Map<String, dynamic>` namespaced para toda a capacidade

Rejeitada porque não oferece invariantes, exhaustive switches, limites,
referential integrity ou conformance publicável.

## Consequências

- mover um node não altera `CatalogManifest.digest`;
- Journey e Inventory podem compartilhar semântica sem compartilhar geometria;
- o Host passa a agregar documentos sem criar outro bounded context;
- snapshots e schemas do Studio evoluem por versão adjacente;
- há custo explícito de codecs, schemas, compiler, corpus negativo e migration
  policy;
- Evidence antiga nunca é reatada por posição, título ou ordem.

## Rollout e rollback

1. contracts/schemas e corpus negativo;
2. parser/compiler e reference consumer com grafo branch/merge;
3. Host publica topology/layout por handle;
4. Studio renderiza a Projection espacial e Outline equivalente;
5. browser gate mede deep link, arestas, seleção, reflow e cleanup;
6. somente então as próximas lenses reutilizam o read model.

Rollback remove a contribution/read model v2 e mantém o catálogo/snapshot v1
operacionais. Fontes novas permanecem preservadas; nenhuma rotina as apaga ou
as converte silenciosamente.

## Evidência requerida

- round-trip, schema, JCS/digest e versões adjacentes;
- negativos de unknown field, limites, número não finito, IDs duplicados,
  cross-Application e referências pendentes;
- compile determinístico em qualquer ordem de fontes;
- topology igual com layouts diferentes mantém o mesmo digest;
- Host/Studio sobre o consumer de referência, com branch e merge reais;
- funcionamento com e sem pixels/provider;
- browser real, Outline, teclado, reflow 200%, reduced motion e DOM bounded;
- root regressions e ausência de dependência de `libs/` para `examples/`.

O rastreamento requisito -> mudança -> teste -> estado está em
`docs/architecture/distribution-agnostic-experience-platform-plan.md`.
