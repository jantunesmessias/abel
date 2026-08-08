# Resultado executado do DISTRIBUTION LIFECYCLE adoption, evidence e distribuicao

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64.

## Adoption reversivel

Commands entregues:

```text
workspace init [--dry-run|--apply]
workspace adoption-report
workspace detach [--dry-run|--apply]
```

O teste vertical prova preview sem criar `.dart_tool`, apply de quatro arquivos
documentais, zero mudanca nos bytes de `pubspec.yaml`/lockfile, preservacao de
arquivo editado durante detach e limpeza final do manifest/diretorios quando o
consumidor remove o ultimo conflito. Preexistencia e content root symlinkado
falham antes de overwrite.

`tests/consumers/friction_flutter` continua sem import Abel em producao e
serve como baseline de zero integracao privilegiada.

## DartTestEvidenceProvider

Command entregue:

```text
workspace evidence collect-tests --target <path-relativo>
```

O gate executou o reporter real `dart test --reporter json`, negociou protocolo
`0.1.1`, observou uma suite VM/um teste aprovado e armazenou summary normalizado
por digest. Fixtures negativas cobrem stream incompleto, traversal, marker
desconhecido, limits e incoerencia terminal. Artifact referenciado e lido com
limite incremental e comparado aos bytes do CAS.

## Pacote standalone e rehearsal

Execute:

```bash
./tools/verify/verify_distribution_lifecycle.sh
```

Resultado observado em 2026-08-09:

- bundle preview.1: 34 arquivos publicáveis; `.last_build_id` incremental não
  integra a distribuição;
- segunda reconstrução da mesma versão produziu manifest byte-idêntico;
- manifest preview.1:
  `sha256:9a45902026af2992554a8bdcfb8d5060a2ecfce453efdf7f984f55beb94b1a95`;
- CLI, Host e Gateway compilados AOT;
- Studio compilado `flutter build web --release`;
- `workspace` e `full-local` produziram JSON identico;
- Gateway standalone anunciou apenas capabilities implementadas;
- Host standalone falhou com exit 2 sem as variaveis obrigatorias;
- update rehearsal preview.2:
  `sha256:14bdd47749deade4d45ee84453b7c230cdd305178b867ef2e45c511f94e03cb6`;
- rollback restaurou preview.1 com status healthy;
- bundle adulterado, extra e symlink foram negados em testes.

O relabel preview.2 existe apenas no rehearsal de update com os mesmos bytes;
release de producao deve reconstruir a partir de inputs pinados.
O Studio usa bootstrap explícito sem o `serviceWorkerVersion` aleatório do
template default; o build ocorre em output canônico sob lock e o marcador
incremental do Flutter não é empacotado.

## Conformance fora do monorepo

O mesmo gate copia as cinco bibliotecas publicas para fora do Pub Workspace,
remove apenas a diretiva de resolucao do monorepo, liga suas dependencias por
path e executa `flutter pub get`, analyze fatal e teste de imports publicos. O
resultado passou para `experience_contracts`, `experience_engine`, `execution_runtime`,
`flutter_app_adapter` e `testing_support`, sem import de `lib/src`.

## Limites honestos

DISTRIBUTION LIFECYCLE nao afirma Android, host-native, CA local, signing stable, package publicado
num registry, hosted, iOS ou device farm. A distribuicao e preview Linux x64; a
matriz operacional web/Android e os criterios E-01...E-20 pertencem a web/Android.
