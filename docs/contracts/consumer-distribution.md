# Consumer distribution v1

Status: contrato, compositor local, CLI e gate externo ativos.

`ConsumerDistributionSpec` é uma configuração fechada e versionada para derivar
uma distribuição de um release base v2 já verificado. Ela declara identidade,
versão, profile, aliases, layout, modo de assets Studio e compatibilidade com:

- core;
- schema de release;
- schema da configuração do consumer;
- schemas dos documentos autorais.

O workspace precisa usar configuração v2, ligar exatamente o mesmo
`distribution.id` e não pode conter `workspace.local.yaml`. O compositor carrega os
documentos por `WorkspaceCatalogLoader`, recompila `CatalogManifest`, clona o
`ModuleCatalog` sob a identidade do consumer e resolve Modules, Providers e
settings pelo `KitPlanResolver`. Compatibilidade de cada Module com o core e a
plataforma é validada antes de qualquer output.

`ConsumerDistributionInventory` liga por digest:

- specification e release base;
- catálogo de Modules e plano resolvido;
- configuração e catálogo autoral compilado;
- módulos efetivamente habilitados, suas versões, compatibilidade e surfaces;
- cada arquivo de configuração ou conteúdo empacotado.

O manifest externo continua sendo o inventário fechado de todos os bytes. A
mesma base, specification e workspace produzem bundle byte-idêntico. O profile
headless não leva diretório, entrypoint ou component Studio. CLI e Host são
obrigatórios; Gateway continua condicionado ao profile.

O bundle carrega `consumer/workspace` como template verificável. O workspace
vivo permanece fora de `releases/<version>` para que caches, journals e Evidence
não alterem uma release imutável. O Host pode receber o `ModuleCatalog` e o
`ResolvedKitPlan` empacotados por ambiente local; ambos são JCS, limitados e
cercados por digest.

Comandos:

```bash
workspace --json distribution compose-consumer \
  --base-bundle /path/base \
  --workspace /path/consumer \
  --specification /path/consumer-distribution.json \
  --output /path/release

./tools/verify/verify_external_distribution_vertical.sh
./tools/verify/external_distribution_reversibility_test.sh
```

O gate cria o consumer fora do monorepo, copia somente packages públicos, nega
imports `src/`, compõe por API pública e por CLI AOT, inicia o Host headless e
exercita install, status, update e rollback no formato canônico.

Este contrato não publica, assina ou atesta releases, não carrega código de
Module arbitrário e não transforma o origin loopback exigido pelo Host em prova
de que uma UI Studio existe. Ele prova composição e operação local Linux x64.
