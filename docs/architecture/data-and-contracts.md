# Dados e contratos

O Abel separa fontes autorais, contratos de transporte e estado gerado. A
especificação normativa está em [`ARCHITECTURE.md`](../../ARCHITECTURE.md).

## Fontes e identidade

- o content root configurado contém documentos autorais de experiência;
- manifests são compilados para contracts tipados e identidades por digest;
- `.dart_tool/workspace/` contém estado local gerado e recuperável, não fonte
  autoral;
- `build/` e `.artifacts/` são saídas regeneráveis e não pertencem ao Git.

## Contratos externos

- [`schemas/`](../../schemas/) agrupa JSON Schemas por domínio;
- [`docs/contracts/`](../contracts/) documenta formatos públicos e regras de
  compatibilidade;
- [`docs/protocols/`](../protocols/) documenta Host, App Adapter e MCP;
- `libs/experience_contracts` é a implementação Dart pública dos codecs;
- `libs/experience_engine` compila e valida sem adquirir autoridade de I/O.

Mudanças incompatíveis exigem um formato canônico novo e remoção deliberada do
formato substituído. Compatibilidade não publicada não deve virar fallback
permanente. Rode `melos run schemas` e `melos run test` para validar schema,
codec e semântica.
