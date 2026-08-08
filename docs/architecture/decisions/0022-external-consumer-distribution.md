# ADR-0022 — Distribuição composta por consumer externo

Status: aceita em 2026-08-17.

## Contexto

Bundles modulares e o manager local já provavam build, install, update,
rollback e migração. O consumer externo, porém, apenas compilava os barrels
públicos; ele não produzia uma distribuição própria nem iniciava seu Host com o
catálogo e plano empacotados.

## Decisão

1. Um release base v2 verificado fornece os executáveis e o catálogo de Modules.
2. `ConsumerDistributionSpec` declara identidade, versão, profile, layout, modo
   Studio e compatibilidade explícita.
3. O compositor público recompila o catálogo autoral do consumer, resolve seu
   plano, cria catálogo de Modules sob a identidade própria e inventaria todos
   os arquivos por digest.
4. Assets Studio existem somente quando `studio.shell` está habilitado e o base
   os contém; headless remove component, entrypoint e árvore física.
5. O Host aceita catálogo e plano canônicos por paths locais cercados. O
   workspace vivo não é o template dentro da release imutável.
6. O mesmo fluxo é exposto por `distribution compose-consumer`; nenhum command,
   endpoint ou path é derivado de conteúdo autoral livre.

## Consequências

- Um projeto fora do monorepo compõe e instala sua própria identidade, aliases,
  catálogo e conteúdo usando apenas APIs públicas.
- Modules e Providers continuam declarativos e plan-gated; o compositor não
  passa a carregar código arbitrário.
- O fluxo permanece local, sem assinatura, publicação ou claim de supply chain.
- A prova headless ainda configura um origin loopback como fence do protocolo
  Host, mas não serve nem empacota Studio.

## Evidência

- `libs/experience_contracts/test/consumer_distribution_contracts_test.dart`;
- `libs/execution_runtime/test/local_consumer_distribution_composer_test.dart`;
- `tools/verify/verify_external_distribution_vertical.sh`;
- `tools/verify/external_distribution_reversibility_test.sh`.
