# `.devexbundle` v1

Um `.devexbundle` é ZIP determinístico com arquivos regulares, sem diretórios
explícitos, ordenados lexicograficamente. O perfil v1 exige:

- método `stored` (sem compressão), UTF-8, sem encryption/data descriptor;
- timestamp DOS `1980-01-01T00:00:00`, atributos Unix de arquivo `0644`;
- sem extra, comment, ZIP64, multi-disk, gaps ou trailing bytes;
- limites: 10.000 entries, 512 MiB por entry e 512 MiB expandido;
- paths relativos normalizados, sem `..`, `.`, backslash, NUL ou duplicata;
- local headers e central directory idênticos e em ordem canônica.

Payload mínimo:

```text
manifest.json
bundle.json
release.json
publication.json
blobs/sha256/<hex>
```

`manifest.json` é JCS e declara digest/tamanho/media type de todo payload, mas
não de si próprio. O verificador processa offsets e bytes em memória limitada;
ele não extrai o ZIP no filesystem.

Integridade, seal e attestation são diferentes:

- archive digest: identidade exata dos bytes ZIP;
- `ReleaseSeal`: release + archive + source/impact sob uma policy;
- attestation: declaração assinada opcional e ausente em V2;
- Approval: decisão humana externa, nunca inferida de build/seal.
