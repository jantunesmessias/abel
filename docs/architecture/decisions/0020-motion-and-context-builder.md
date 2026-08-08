# ADR-0020 — Motion adjacente e Context Builder semântico

- Status: aceita e vertical local executado em 2026-08-17
- Preserva: `CatalogManifest` v1, `ExperienceTopologyBundle` v1 e o authoring
  de layout v1

## Contexto

Motion precisa descrever comportamento temporal sem tornar movimento necessário
para compreender uma jornada. Context Builder precisa produzir contexto bounded
para automação e IA sem aceitar paths, despejar o workspace ou misturar gerações
de catálogo, topologia, Evidence e histórico.

Adicionar Motion aos contratos v1 publicados quebraria seus digests. Derivar
Context no Studio criaria um segundo banco, exporia autoridade de filesystem e
permitiria combinar recursos de revisões distintas.

## Decisão

`MotionManifest` é um documento autoral v2 adjacente e opcional no content-set
v2. Ele liga cada sequência a uma projection e transitions/nodes existentes,
declara steps, easing, observações e durações full/reduced, além de um resumo
estático obrigatório. O modo none tem duração zero por definição; scripts e
observações continuam visíveis em todos os modos.

Context Builder roda no Host sobre uma geração já compilada. O request contém
somente seleção semântica, `expectedContentSetDigest`, cinco flags de inclusão e
cinco budgets independentes. O Host resolve documentos e artifacts, sanitiza
conteúdo, contabiliza bytes/itens e materializa omissões tipadas. Respostas são
canônicas, limitadas e determinísticas para entradas equivalentes.

Motion e Context usam Modules separados de apresentação e autoridade local:
`studio.motion`, `motion.local`, `studio.context` e `context.builder.local`.
Desabilitar o Module remove sua contribution/RPC. Context é read-only e não
emite grant; Motion não estende o contrato congelado de edição de layout.

## Consequências

- conteúdo temporal participa da identidade atômica sem reescrever v1;
- full/reduced/none compartilham a mesma semântica e equivalente estático;
- seleção Context é navegável e consumer-agnostic, mas nunca é routing livre;
- budgets de uma categoria não consomem silenciosamente o budget de outra;
- omissão é dado de primeira classe, não ausência ambígua;
- providers externos e autoria de Motion exigem cortes próprios.

## Evidência e limites

Contracts/schema, compiler, Host, Studio e consumer têm testes focados. O gate
`tools/verify/verify_motion_context_vertical.sh` executa Chrome/Host/Studio reais sobre
uma cópia privada do consumer, compara exports após reload, força uma omissão e
verifica screenshot, logs e cleanup. Essa prova local não certifica WCAG,
provider externo, qualidade de prompt/modelo, hosted ou produção.
