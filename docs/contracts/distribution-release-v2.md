# Distribution descriptor e release v2

Status: schemas, codec, builder, verifier, install/update/rollback e bundles
por profile ativos.

Distribution v2 separa disponibilidade física de habilitação no workspace:

- `DistributionDescriptor` referencia `ModuleCatalog` por path/digest e declara
  default profile;
- `DistributionReleaseManifestV2` referencia o mesmo catálogo, profiles
  empacotados, components, entrypoints e files;
- CLI é o único entrypoint obrigatório;
- Host, Gateway e Studio são components condicionais;
- cada component declara os Module IDs que materializa.

`schemas/v2/distribution-descriptor.schema.json` e
`schemas/v2/distribution-release.schema.json` são incompatíveis no writer com
v1. `DistributionReleaseCodec` lê v1/v2 e install/verify/rollback v1 permanecem
ativos. O reader v2 valida paths
relativos, digests, unicidade, presença do ModuleCatalog, Modules dos profiles e
correspondência component/file antes de ativar uma release.

O builder recebe `--profile` e materializa somente components necessários às
surfaces dos Modules selecionados. CLI é sempre empacotada; Host, Gateway e
Studio são opcionais. `gateway-lab-headless`, por exemplo, contém CLI/Host/
Gateway e não contém Studio; `journey-preview` contém CLI/Host/Studio e não
contém Gateway.

O component Studio é construído com `jaspr build` a partir do único
`apps/devex_studio/build/jaspr`. O builder usa lock exclusivo, rejeita links e
registra apenas regular files. Flutter não é dependência do component Studio;
continua disponível somente nos adapters/consumers selecionados pelo workspace.

Cada `DistributionFile` v2 declara ownership por `moduleIds`. O catálogo
canônico empacotado tem digest validado tanto física quanto semanticamente.
Habilitar Module ausente falha antes de executar qualquer component.

Gates:

```bash
./tool/verify_modular_distribution.sh  # slim + rebuild byte-idêntico
./tool/verify_v03_distribution.sh      # full + install/update/rollback v1/v2
```
