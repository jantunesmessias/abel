# Contribuindo

A arquitetura normativa começa em [ARCHITECTURE.md](ARCHITECTURE.md). O índice
especializado fica em [docs/README.md](docs/README.md).

## Preparação

O repositório usa Dart Pub Workspaces e Melos 8.3.0. O `pubspec.yaml` raiz é a
única fonte para membros e scripts do monorepo.

```bash
dart pub global activate melos 8.3.0
melos bootstrap
```

Não crie `melos.yaml`, `pubspec_overrides.yaml` ou uma lista paralela de
packages. O lockfile da raiz faz parte da reprodução do workspace.

## Ciclo local

Antes de entregar uma alteração:

```bash
melos run format
melos run analyze
melos run test
melos run check
git diff --check
```

Use o gate focado correspondente durante a implementação. `melos run --list`
mostra Studio, Gateway, distribuição, schemas, supply chain, Kubernetes,
AutoPreview e os verticais de browser. `melos run ci` reproduz a matriz portátil
do job principal do GitHub Actions.

## Boundaries

- `apps/` contém composition roots e executáveis.
- `libs/` contém packages reutilizáveis.
- `examples/` contém consumers de referência.
- `tests/` contém conformance, integração, consumers externos e fixtures.
- `tools/` contém automação transversal.
- `schemas/` contém os contratos externos agrupados por domínio.

Apps não dependem de outros apps. Libs não dependem de apps. Código de produção
não importa `tests/` ou `tools/`, e nenhum package importa o `src/` privado de
outro package. Os gates `tools/gates/architecture_guard.dart` e
`tools/gates/repository_policy.dart` protegem essas fronteiras. A política de
comentários first-party fica em
[docs/quality/comment-policy.md](docs/quality/comment-policy.md) e é aplicada
por `melos run comments`.

## Evidência e segurança

Não transforme build verde em claim de runtime, infraestrutura ou dispositivo.
Registre separadamente testes focados, browser, serviços externos e limitações
ambientais. Não grave tokens, grants, handles, paths locais ou payloads privados
em logs, snapshots, HTML ou fixtures. Artefatos regeneráveis ficam fora do Git,
incluindo `.artifacts/`, `.dart_tool/` e `build/`.
