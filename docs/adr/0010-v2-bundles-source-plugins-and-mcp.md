# ADR-0010 — V2 bundles, source impact, plugins e MCP

Status: aceita em 2026-08-09.

## Contexto

V2 precisava tornar releases portáveis, ligar mudanças de fonte a evidence e
abrir extensibilidade sem transformar o Host em carregador de código
privilegiado. As decisões também fecham Q-17 e Q-18.

## Decisão

1. `.devexbundle` usa um perfil ZIP armazenado, sem compressão nem ZIP64. Paths,
   ordem, timestamps DOS, flags, atributos, offsets e inventário são canônicos.
   O reader não extrai arquivos e rejeita traversal, links implícitos, gaps,
   sobreposição, trailing data, entradas duplicadas e limits excedidos.
2. `manifest.json` é JCS e distingue integridade de attestation. Ausência de
   assinatura é representada como `attestation.status=absent`; `ReleaseSeal`
   não cria Approval nem afirma signer.
3. Filesystem e Git (commit ou worktree) produzem o mesmo `SourceSnapshot`.
   Snapshot parcial, repository desconhecido ou dependência de binding ausente
   invalida conservadoramente todo reuso de evidence.
4. `SourceBinding.symbol` é hint opcional. V1 do impact engine decide por path
   glob e dependências declaradas; uma mudança de arquivo nunca é desconsiderada
   porque o símbolo não pôde ser provado.
5. `ContextBundle` exige seleção explícita, verifica digest contra o snapshot,
   limita bytes, recusa binário e path secret-like e redige padrões sensíveis
   antes de produzir o documento por digest.
6. Plugin dinâmico é descoberto por manifest JCS, negocia protocolo v1 e roda
   one-shot fora do processo. Em V2 o sandbox suportado é Linux/bubblewrap, sem
   workspace, home, ambiente herdado ou rede. Efeito mutável exige preview
   digest e grant explícito.
7. `mcp serve` é stateless conforme MCP `2026-07-28` e expõe somente ferramentas
   read-only de inspect/diff/impact/verify. Workspace root é fixado pelo owner;
   não existem ferramentas MCP de seal, publish, apply ou plugin invoke.

## Consequências

- Bundles são byte-reproduzíveis e verificáveis offline.
- Incerteza aumenta trabalho, nunca autoriza reuso inseguro.
- Plugins não são portáveis para hosts sem sandbox equivalente; a capability
  falha fechada nesses hosts.
- O protocolo MCP poderá ganhar versões adjacentes por nova decisão e
  conformance; não há fallback silencioso para handshake legado.

## Evidência

- `tool/verify_v2.sh`;
- `test/fixtures/v2/source-impact-corpus.json`;
- suites `source_and_v2_contracts_test`, `source_impact_engine_test`,
  `deterministic_devex_bundle_test`, `local_source_adapters_test`,
  `read_only_mcp_server_test` e `plugin_process_host_test`;
- vertical CLI V2 em `apps/devex_cli/test/devex_cli_test.dart`.
