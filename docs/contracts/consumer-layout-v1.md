# ConsumerLayout e descoberta v1

O launcher canônico procura `devex.yaml` do diretório atual até a raiz, salvo
quando `--config` fornece um arquivo explícito. O diretório do arquivo de
configuração é o workspace root efetivo.

Precedência e normalização:

1. `--config` explícito;
2. config canônica descoberta;
3. `content.root` relativo ao workspace;
4. documentos YAML/JSON sob o content root, sem seguir links.

Paths absolutos ou resolvidos fora do workspace, symlinks no content root,
campos desconhecidos e versões não suportadas falham fechados. Queries
`validate` e `explain` não criam cache. `compile` usa lock, staging atômico e
grava derivados somente em `.dart_tool/devex/<distribution-id>/`.

As fixtures normativas em `test/fixtures/layouts/` cobrem layout default,
monorepo multi-app e distribuição hipotética com layout customizado. Branding
altera paths humanos; nunca muda kinds, schemas, machine output ou digests.
