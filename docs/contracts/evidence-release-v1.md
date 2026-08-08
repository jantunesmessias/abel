# Contrato Evidence & Release v1

Status: ativo. Owner: Evidence & Release. Schema externo:
`schemas/v1/evidence-release.schema.json`.

## Identidade e serializacao

- `Artifact.digest` e SHA-256 dos bytes exatos do blob.
- Captura PNG possui tambem `pixelDigest`, calculado sobre largura, altura e
  pixels RGBA8 normalizados; filtro e compressao nao alteram essa identidade.
- `ExecutionFingerprint.digest`, `Evidence.digest` e `ReleaseBundle.digest`
  usam SHA-256 sobre JCS sem o campo `digest` do proprio documento.
- O manifest `Release` nunca embute seu proprio digest. O `ReleaseBundle`
  carrega `releaseDigest` e o reader deve recalcula-lo antes de aceitar a
  Release.
- Readers v1 falham fechados para kind, versao, enum ou campo desconhecido.

## Freshness e claims

Freshness possui quatro estados ortogonais: `missing`, `fresh`, `stale` e
`invalid`. Uma Evidence e fresh somente quando seu subject e o catalog do
fingerprint coincidem com o subject atual e todos os artifacts verificam por
digest, tamanho e identidade especifica do media type.

`structural`, `simulated`, `hostNative` e `deviceAttested` nao sao sinonimos de
freshness. Campos ausentes de source revision, inputs ou policies degradam uma
claim de reproducao; nunca recebem default otimista.

## Captura PNG V0

O perfil fechado aceita PNG estatico, nao interlacado, RGB/RGBA de 8 bits. O
reader valida assinatura, ordem e limites de chunks, CRC, IDAT, dimensoes e
scanlines antes de materializar o Artifact. APNG, palette, grayscale e formatos
fora do perfil falham explicitamente em vez de serem reinterpretados.

## Bundle local

O diretorio local contem exatamente:

```text
bundle.json
release.json
publication.json
blobs/sha256/<digest>
```

A publicacao usa staging no mesmo filesystem, verifica o bundle completo e so
entao faz rename e atualiza `releases/latest.json` atomicamente. Arquivo extra,
ausente, symlink, JSON nao canonico, digest/tamanho divergente ou identidade PNG
divergente invalida o bundle.

`PublicationView` combina a Release imutavel com decisoes externas. Por default
ela omite metadata de Artifact `sensitive`; isso nao muta a Release nem apaga o
blob do bundle local.

## Compatibilidade

Writers atuais emitem somente v1. Mudanca aditiva que altere o conjunto fechado
de campos exige uma nova versao negociada e fixtures adjacentes. Mudanca de
algoritmo de digest, normalizacao de pixels ou semantica de freshness e breaking
independentemente de ser representavel no mesmo JSON.
