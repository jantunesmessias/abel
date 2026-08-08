# Resultados do spike descartável do Studio Jaspr

Data: 2026-08-10. Escopo: fase J2 da ADR-0016. O código permanece em
`.dart_tool/devex/spikes/` e não integra a Distribution.

Este relatório descreve somente o que foi executado. Ele não promove o visual
do spike a produto e não comprova o cutover de `apps/devex_studio`.

## Confirmed

- Jaspr `0.23.3` e `jaspr_router` `0.9.0` resolveram em um Pub Workspace
  descartável com dois packages;
- `dart analyze` passou e `jaspr build` produziu uma SPA client-side estática;
- rota direta `/journeys/understand-runtime-configuration` sobreviveu a
  navegação e refresh após tornar CSS e entrypoint root-relative;
- o Host real aceitou bootstrap CORS somente para a origem `39012`, autenticou
  o primeiro RPC, descreveu e abriu revision 2 do workspace;
- o cliente validou media type, tamanho e SHA-256 do resource antes de criar
  `WorkspaceSnapshot`;
- ao derrubar o Host do spike, a mesma página preservou o snapshot como
  `stale`; ao iniciar outro Host, ela obteve bootstrap/token novos e voltou a
  `Host conectado` sem reload manual;
- bootstrap sem `Origin` e com origem atacante respondeu `403`; a origem
  allowlisted respondeu `200`;
- o iframe em `39013` enviou primeiro envelope inválido com session/nonce e
  sequence incorretos e depois envelope válido; o pai aceitou somente sequence
  1;
- scan do allowlist não encontrou o token real em HTML, JS ou CSS, nem usos de
  `localStorage`, `sessionStorage`, IndexedDB ou cookie;
- o allowlist release não continha source maps;
- duas builds anteriores à inclusão do segundo package tiveram bytes idênticos
  no allowlist, incluindo `index.html`, JS e quatro folhas CSS.

Evidência visual local do spike técnico:

| Estado | Arquivo de trabalho |
|---|---|
| Host conectado | `/tmp/devex-jaspr-spike/01-overview.png` |
| deep link direto | `/tmp/devex-jaspr-spike/04-deep-link-waited.png` |
| envelope inválido rejeitado | `/tmp/devex-jaspr-spike/07-target-negative.png` |
| snapshot stale | `/tmp/devex-jaspr-spike/08-host-stale.png` |
| sessão recuperada | `/tmp/devex-jaspr-spike/09-host-recovered.png` |

## Partial

- a CSP foi exercitada como meta tag; headers da Distribution ainda não foram
  implementados;
- o Host Client do spike reproduz apenas o mínimo do protocolo. O vertical
  final deve reutilizar `devex_contracts` e o Host Client tipado do Studio;
- o output bruto `build/jaspr` inclui assets de tooling/packages que não são
  referenciados pelo HTML. A Distribution precisa publicar um allowlist
  explícito, não copiar o diretório bruto;
- o teste de iframe provou schema/session/nonce/sequence, mas ainda falta
  mensagem proveniente de source/origin efetivamente diferentes;
- a reprodutibilidade deve ser repetida depois da composição final do Pub
  Workspace; a prova já executada precede o segundo package;
- os warnings da CLI sobre opções de build removidas foram não bloqueantes,
  mas precisam desaparecer ou ser aceitos explicitamente no tooling final.

## Unverified

- package, entrypoint e build reais de `apps/devex_studio`;
- UI System Jaspr, componentes, temas, foco, teclado e acessibilidade;
- fluxos completos de initialize/events/resume/preview collection;
- supervisor `devex dev`, readiness, shutdown e distribuição headless;
- performance, reflow 360 px, texto 200%, contraste e reduced motion;
- stale → collect → fresh do AutoPreview com PNG real;
- duas builds finais e audit completo da Distribution.

## Failed e corrigido durante o spike

- deep link abriu uma página sem estilo/entrypoint porque assets eram relativos;
  URLs root-relative corrigiram a falha e o refresh direto passou;
- `jaspr build` na raiz agregadora falhou por ausência de dependência direta em
  Jaspr; a invocação correta é no member do app. O comando final deve esconder
  essa distinção do usuário.

Não há finding aberto que impeça a fase J3. O gate J2 permanece `Partial` até a
reprodutibilidade pós-workspace e o negativo real de source/origin do iframe.
