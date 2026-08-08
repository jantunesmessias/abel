# MCP read-only v1

O servidor stdio `devex mcp serve` implementa o core stateless MCP
`2026-07-28`. Cada request operacional inclui versão, client info e
capabilities em `_meta`; `server/discover` permite descoberta antecipada.

Métodos:

- `server/discover`;
- `tools/list`, em ordem determinística e com cache metadata;
- `tools/call`.

Tools:

- `devex.source.inspect`;
- `devex.source.diff`;
- `devex.impact.plan`;
- `devex.bundle.verify`.

Todos têm `readOnlyHint=true`. Não há ferramenta de mutation, apply, seal,
publish, credential, Gateway ou sessão. Paths são relativos ao workspace root
fixado no composition root, lines têm 1 MiB e resultados não carregam secrets.

Referências: [MCP 2026-07-28 — Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools),
[Discovery](https://modelcontextprotocol.io/specification/2026-07-28/server/discover) e
[Transports](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports).
