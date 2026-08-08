# Perfil JSON Schema DevExKit v1

O contrato externo usa JSON Schema Draft 2020-12, com um perfil deliberadamente
fechado em torno do conjunto comprovado pelo validator encapsulado.

## Suportado

- vocabularios oficiais core, applicator, validation, metadata, format e
  content;
- referencias locais por fragmento;
- keywords e combinadores cobertos pelos testes oficiais aceitos;
- `$schema` ausente ou exatamente
  `https://json-schema.org/draft/2020-12/schema`.

## Rejeitado antes da validacao

- `$dynamicAnchor`, `$dynamicRef`, `contentSchema` e `unevaluatedItems`;
- referencias externas ou absolutas;
- `enum` vazio;
- keywords de contagem com representacao JSON nao inteira;
- metaschema diferente e vocabulario desconhecido marcado como obrigatorio;
- chaves de schema que nao sejam strings.

Essa rejeicao e parte do contrato: nenhum recurso fora do perfil e aceito de
forma parcial ou silenciosa. A ferramenta `tool/verify_standards.sh` baixa
commits pinados dos corpora oficiais e atualmente comprova 1.076/1.076 casos do
perfil JSON Schema e 6/6 vetores JCS. Os 192 casos restantes sao classificados
explicitamente como fora do perfil, nao como aprovados.
