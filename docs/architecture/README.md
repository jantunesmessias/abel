# Arquitetura

[`ARCHITECTURE.md`](../../ARCHITECTURE.md) é a especificação normativa da
plataforma. Este diretório organiza mapas de leitura, decisões, planos e
resultados que apoiam essa especificação.

## Mapas

- [Boundaries](boundaries.md): ownership e regras de dependência.
- [Componentes](components.md): entrypoints físicos por responsabilidade.
- [Dados e contratos](data-and-contracts.md): fontes canônicas, schemas e
  protocolos.
- [Decisões](decisions/README.md): índice dos ADRs aceitos.

## Evidência e histórico

Arquivos `*-results.md` registram evidência de uma execução específica. Eles
não substituem os gates atuais nem certificam continuamente o ambiente.
Arquivos `*-plan.md` preservam decisões e escopo histórico enquanto ainda
forem referenciados. Estado implementado, limitações e questões abertas devem
ser conferidos primeiro em `ARCHITECTURE.md` e pelos comandos listados por
`melos run --list`.
