# ADR-0019 — Autoridade local de autoria e promoção de layout

- Status: aceito
- Data: 2026-08-17
- Decisões afetadas: autoria, review, content root, grants e persistência local

## Contexto

Autoria de Experience precisa permitir que um consumer altere seu layout sem
dar ao Studio acesso ao filesystem, sem transformar capability em efeito e sem
misturar aceitação automatizada com decisão humana. Uma promoção também não
pode inferir paths, reescrever documentos sem relação com o changeset ou perder
o head durável quando Host, processo ou resposta falham.

## Decisão

`studio.authoring` oferece somente a superfície de consulta e apresentação.
`authoring.local` é a autoridade de efeito. O Host deriva authority, policy,
principal, content root e arquivo fonte do plano resolvido e do subject tipado.
Requests não carregam path, comando, endpoint ou routing livre.

Draft, operações, cursor de undo/redo, ChangeSet, ReviewPacket, grants, attempts
e receipts formam um journal canônico com hash chain e CAS monotônico. Grants
são curtos, single-use, ligados a connection epoch, request/payload/head/source
digests e consumidos na primeira tentativa estruturalmente válida. Replay
exato retorna o resultado terminal; reconnect revoga apenas grants não usados.

O v1 promove um único documento `ProjectionLayout` v2. O Host recompõe o
candidate com `LayoutDraftEngine`, preserva todos os campos exceto `x` e `y`,
recompila catálogo e topologia e exige identidade semântica estável. Automated
acceptance usa somente `projection-layout-safety.v1`: bounds, geometria e
ausência de overlap. Ela não afirma fidelidade visual nem substitui a decisão
humana append-only no head corrente.

No provider local comprovado, a transação mantém um lock de workspace,
persiste CAS e WAL antes do efeito, e troca fonte/slot privado com
`renameat2(RENAME_EXCHANGE)` em Linux x64. Traversal por file descriptor,
`O_NOFOLLOW`, ownership, link count, metadata, fsync de arquivos/diretórios e
rebind de roots cercam o efeito. Recuperação classifica o par fonte/slot e nunca
adivinha um terceiro digest. Outros sistemas operacionais ou filesystems sem a
primitiva falham como `unsupported`; não existe fallback destrutivo.

## Boundary de atomicidade

A garantia cobre writers Abel que cooperam pelo lock do workspace. Um processo
same-uid que deliberadamente ignora esse lock e altera um inode já aberto não
é convertido em uma falsa promessa de digest-CAS de kernel. Quando uma
ambiguidade é observável depois da linearização, a operação preserva WAL e o
par de arquivos e retorna `outcomeUnknown`. Esse boundary é uma limitação
explícita, não uma certificação contra writers hostis locais.

## Consequências

- Viewer continua funcional sem authority de mutação.
- Catálogo injetado é consultável, mas não ganha source authority por inferência.
- ReviewGuide, scenario, binding e artifact são resolvidos contra digests exatos.
- Findings, concepts, comments e decisões permanecem históricos; somente refs
  correntes perdem promotability após nova mutação.
- O Studio sanitiza attribution e grants antes de manter estado ou renderizar.
- O gate browser opera sobre cópia privada do consumer e prova cleanup e
  reversibilidade sem modificar o content root versionado.
