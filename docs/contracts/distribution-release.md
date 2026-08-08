# Distribution descriptor e release

Status: schemas, codec, builder, verifier, install/update/rollback e bundles
por profile ativos.

A release canônica separa disponibilidade física de habilitação no workspace:

- `DistributionReleaseDescriptor` referencia `ModuleCatalog` por path/digest e declara
  default profile;
- `DistributionReleaseManifest` referencia o mesmo catálogo, profiles
  empacotados, components, entrypoints e files;
- CLI é o único entrypoint obrigatório;
- Host, Gateway e Studio são components condicionais;
- cada component declara os Module IDs que materializa.

`schemas/distribution/distribution-descriptor.schema.json` e
`schemas/distribution/distribution-release.schema.json` guardam a única revisão aceita.
O campo `schemaVersion: 2` permanece como fence técnico de serialização; o
reader antigo nunca publicado foi removido. O codec valida paths relativos,
digests, unicidade, presença do ModuleCatalog, Modules dos profiles e
correspondência component/file antes de ativar uma release.

O builder recebe `--profile` e materializa somente components necessários às
surfaces dos Modules selecionados. CLI é sempre empacotada; Host, Gateway e
Studio são opcionais. `gateway-lab-headless`, por exemplo, contém CLI/Host/
Gateway e não contém Studio; `journey-preview` contém CLI/Host/Studio e não
contém Gateway.

O component Studio é construído com `jaspr build` a partir do único
`apps/studio/build/jaspr`. O builder usa lock exclusivo, rejeita links e
registra apenas regular files. Flutter não é dependência do component Studio;
continua disponível somente nos adapters/consumers selecionados pelo workspace.

Cada `DistributionFile` declara ownership por `moduleIds`. O catálogo
canônico empacotado tem digest validado tanto física quanto semanticamente.
Habilitar Module ausente falha antes de executar qualquer component.

Gates:

```bash
./tools/verify/verify_modular_distribution.sh  # slim + rebuild byte-idêntico
./tools/verify/verify_distribution_lifecycle.sh      # full + install/update/rollback
./tools/verify/verify_external_distribution_vertical.sh # consumer externo + headless
```

Uma release base verificada pode ser composta por um consumer externo por
meio do contrato adjacente
[`consumer-distribution.md`](consumer-distribution.md). O compositor não
altera a semântica do manifest: configuração, conteúdo, catálogo compilado,
plano resolvido e inventory tornam-se arquivos do inventário fechado da release.
