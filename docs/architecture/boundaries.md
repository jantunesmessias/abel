# Boundaries

As regras normativas completas estão em
[`ARCHITECTURE.md`](../../ARCHITECTURE.md). Este mapa localiza os boundaries
físicos usados pelo gate de arquitetura.

| Boundary | Ownership |
|---|---|
| `apps/` | composition roots, processos e superfícies executáveis |
| `libs/` | contracts, engine, runtime e UI reutilizáveis |
| `examples/` | consumers de referência, nunca dependência de produção |
| `schemas/` | formatos externos agrupados por domínio |
| `tests/` | conformance, integração, consumers externos e fixtures |
| `tools/` | automação transversal e fitness functions |

Regras essenciais:

- apps podem compor libs, mas não dependem de outros apps;
- libs não dependem de apps;
- produção não importa `tests/` ou `tools/`;
- nenhum package importa o `src/` privado de outro package;
- interfaces públicas não transportam paths, comandos ou autoridades quando
  IDs semânticos e resolução pelo Host bastam;
- exceções são estreitas, explícitas e verificadas por
  `tools/gates/architecture_guard.dart`.

Use `melos run check` para a verificação portátil do boundary e consulte
[`decisions/`](decisions/README.md) antes de ampliar uma exceção.
