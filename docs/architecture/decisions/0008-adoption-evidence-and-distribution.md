# ADR-0008: DISTRIBUTION LIFECYCLE adoption, EvidenceProvider e distribuicao standalone

- Status: aceita
- Data: 2026-08-09
- Decisoes afetadas: D-024, D-034, Q-02, Q-11, Q-12

## Decisao

### Adoption

- `init` e preview-first; somente `--apply` cria `workspace.yaml` e documentos no
  content root. Nao altera entrypoint, fonte do app, `pubspec.yaml` ou lockfile.
- Cada arquivo criado recebe role e digest em `AdoptionManifest` fora do content
  root. `adoption-report` compara bytes observados com ownership registrado.
- `detach` e dry-run por default. Em apply, remove apenas arquivo cujo digest
  ainda e o registrado; arquivo modificado permanece e continua com owner no
  manifest ate remocao explicita do consumidor.
- Paths absolutos, traversal, symlinks e overwrite de arquivo preexistente
  falham fechados.

### EvidenceProvider

- O primeiro provider e `dart-test-json-v1`, sobre o reporter oficial JSON
  `0.1.1` de `dart test`/`flutter test --machine`.
- O provider executa o runner diretamente, sem shell, com targets relativos,
  timeout e quotas de line/event/stderr/artifact. Exige exatamente um `done`
  coerente com exit code.
- O CAS recebe um summary JCS sanitizado. Output bruto, nomes de testes e paths
  absolutos nao sao persistidos. Artifact adicional so entra por marker
  `TEST_ARTIFACT_JSON` explicito, relativo, classificado e limitado.

### Distribuicao

- O bundle Linux preview contem CLI, Host e Gateway AOT, Studio web release e
  `DistributionReleaseManifest` canonico com inventario SHA-256 fechado.
- Install usa releases imutaveis versionadas, launchers logicos e ponteiro
  `current`. Update preserva a versao anterior; rollback troca o ponteiro apos
  verificar novamente todos os bytes.
- `workspace` e aliases apontam para o mesmo executavel. Machine JSON, exit code e
  digests nao dependem do nome usado para invoca-lo.
- State v0 migra para v1 somente com preview/apply, backup, verificacao e undo.
  Bundle adulterado, arquivo extra, link ou versao colidindo falha antes de
  mudar a instalacao atual.
- DISTRIBUTION LIFECYCLE suporta pacote standalone Linux x64 em canal preview. Assinatura de
  imagem/artefato e matriz stable continuam gates de web/Android/hosted control plane, sem transformar a
  ausencia de assinatura local em attestation.

## Q-02, Q-11 e Q-12

- Q-02: `DistributionDescriptor`/`ConsumerLayout` v1 agora possuem codec
  fechado, IDs/aliases/paths validados e fixtures default, monorepo e layout
  customizado.
- Q-11: o reporter JSON do runner Dart/Flutter foi escolhido por ser public
  seam versionada e preservar o runner como owner da execucao.
- Q-12: instalacao local Linux e versioned-directory + manifest de bytes +
  ponteiro atomico, com rollback e migration rehearsal. Canais posteriores
  acrescentam assinatura/provenance sem mudar essa identidade.

## Evidencia e rollback

O resultado executado esta em `docs/architecture/distribution-lifecycle-results.md`. Rollback do
produto usa o comando de distribuicao; rollback desta decisao remove commands
de adoption/provider sem invalidar Catalog, Evidence ou bundles plataforma local anteriores.
