# ADR-0021 — MCP Experience local, tipado e capability-gated

- Status: aceita e vertical local executado em 2026-08-17
- Adjace: `mcp-read-only`; não altera seus quatro tools históricos

## Contexto

Automação precisa consultar Catalog, grafo, Context, Evidence e captures sem
receber um dump do workspace. Efeitos de teste, captura e autoria precisam
preservar as mesmas cercas de identidade, grants e revisão usadas pelo Host,
sem criar um segundo modelo de autoridade ou um endpoint de comandos livres.

O MCP read-only v1 era deliberadamente stateless e insuficiente para esse
corte. Transformar `clientInfo` em credencial, aceitar paths/endpoints arbitrários
ou manter capabilities reutilizáveis ampliaria autoridade sem prova.

## Decisão

`workspace mcp serve --config <workspace.yaml> [--profile <id>]` resolve o plano do
consumer e abre somente stdio. O processo que entrega o pipe é a autoridade
local; `clientInfo` produz atribuição estável, mas não é autenticação
criptográfica remota. Não existe listener TCP/HTTP neste transporte.

O backend publica seis resources imutáveis da mesma geração e um conjunto de
tools derivado dos Modules realmente habilitados. Desabilitar Context,
Evidence ou Authoring remove o tool da descoberta e também rejeita dispatch
forjado. Queries recebem IDs semânticos e limites fechados. Paths, quando uma
operação necessariamente lê um arquivo, são relativos ao workspace fixado pelo
launcher, sem links e sem escape.

Efeitos genéricos usam capability de dois minutos ligada a principal, tool,
`expectedContentSetDigest` e digest do payload. Ela é single-use, revogável e
consumida na primeira tentativa, inclusive mismatch e falha. O journal local é
JCS, encadeado por digest e limitado a 10.000 registros. Authoring não usa essa
capability genérica: reutiliza os grants duráveis, ownership, CAS, review e
promotion do domínio autoria e review. Aceitação automatizada continua distinta da decisão
humana e não autoriza promoção.

`batchMutate` v1 é sequencial, bounded a 16 requests e fail-stop; ele declara
`atomic=false`. A promoção de um layout permanece a transação atômica própria
do Runtime. `quality.capture` importa um PNG já existente no workspace; captura
ativa de device/browser depende de provider ou de outro vertical.

## Consequências

- automação recebe documentos tipados e bounded, nunca um shell ou endpoint;
- plano e content-set cercam descoberta e execução na mesma geração;
- restart ou fechamento revoga authority efêmera da conexão;
- a trilha genérica torna início/resultado auditáveis, mas não converte stdio
  local em identidade remota ou sandbox de sistema;
- testes usam apenas runner `dart|flutter` e targets relativos confinados;
- artifacts continuam no CAS e results/lines respeitam o limite de 1 MiB.

## Evidência e limites

`tools/verify/verify_mcp_experience_vertical.sh` executa o CLI real sobre uma cópia
privada do reference consumer. O gate prova 35 tools, 6 resources, nove queries,
Context determinístico, redaction, path confinement, teste Dart, capture/diff,
revogação, consumo por mismatch e o fluxo de Authoring até aceitação estrutural.
`tools/verify/mcp_experience_reversibility_test.sh` injeta falha e exige remoção
do runtime isolado.

A prova é local e não certifica autenticação remota, hosted, device capture,
atomicidade do batch, containment de CPU/memória/rede ou qualidade de contexto
para um modelo específico. O wire e os limites estão em
[`mcp-experience.md`](../../protocols/mcp-experience.md).
