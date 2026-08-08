# ADR-0016 — Um único Abel Studio em Jaspr

- Status: Aceita e implementada localmente em 2026-08-11
- Data: 2026-08-10
- Substitui: detalhes de renderer e tooling de Studio das ADRs 0014 e 0015
- Preserva: autoridade do Host, contracts canônicos e separação UI/UX

## Contexto

O baseline anterior comprovou um Studio Flutter web conectado ao Host, com
Journey Map, Inspector, AutoPreview e distribuição local. Ele também expôs um
custo estrutural: o Studio é uma ferramenta web orientada a informação,
navegação, foco, texto, tabelas, painéis, SVG e iframes, enquanto Flutter pinta
um runtime próprio. Mesmo sem Material/Cupertino, o baseline ainda depende do
SDK Flutter, de Semantics adaptada e de tooling específico para build e serve.

O produto requer HTML semântico, CSS próprio, acessibilidade web nativa,
integração direta com history/URL e uma distribuição que não carregue Flutter
quando somente o Studio está habilitado. Manter dois Studios, um renderer
selecionável ou fallback de distribuição criaria duas interpretações de estado
e duplicaria conformance.

Jaspr 0.23.3 suporta aplicações inteiramente client-side e produz HTML/CSS/JS
normais. O pacote não fornece componentes visuais pré-estilizados. O router
oficial `jaspr_router` 0.9.0 oferece rotas, deep links, history e links HTML
acessíveis. As versões foram resolvidas pelo Pub e pelo scaffold oficial em
2026-08-10; o índice web público ainda exibia a release anterior durante a
primeira consulta:

- [Jaspr](https://pub.dev/packages/jaspr)
- [Client-Side Jaspr](https://docs.jaspr.site/dev/client)
- [Rendering Modes](https://docs.jaspr.site/dev/modes)
- [Jaspr Router](https://pub.dev/packages/jaspr_router)
- [Jaspr CLI e build](https://docs.jaspr.site/dev/cli)

## Decisão

### Um produto, um renderer

`apps/studio` será o único Studio e usará Jaspr em modo `client`. Não
existirá outro app, configuração `studio.renderer`, fallback Flutter ou seleção
de renderer. `ResolvedKitPlan` decide se o Studio existe; Jaspr é um detalhe
interno do Module `studio.shell`.

O cutover removeu o baseline Flutter depois de um vertical Jaspr provar, no
mesmo protocolo real, bootstrap, RPC, WebSocket, resources, reconexão, rotas e
iframe isolado. O archive histórico não é uma opção de runtime ou distribuição.

### Client-side sem SSR

O `pubspec.yaml` final declara:

```yaml
jaspr:
  mode: client
```

O browser executa toda a apresentação. `jaspr build` produz assets estáticos
para o supervisor e a Distribution. Não haverá entrypoint de servidor Jaspr,
SSR, SSG nem Dart VM dentro do Studio.

O modo `static` foi rejeitado neste vertical, apesar de também produzir assets
estáticos, porque pré-renderização não resolve uma necessidade do Studio local
autenticado e introduziria outro ambiente de execução. SSR/SSG só pode entrar
por novo ADR, threat model e gates de segredo/origin/cache.

### Fronteiras de package

```text
apps/studio          Jaspr SPA, controllers e Host Client
libs/studio_ui  Jaspr + HTML/CSS, sem regra de domínio
libs/interaction_model  Dart puro, sem Jaspr ou Flutter
```

O Studio pode depender de `experience_contracts`, `studio_ui`,
`interaction_model`, `jaspr`, `jaspr_router`, `web` e transporte WebSocket web.
Ele não pode importar Flutter, Material, Cupertino, `dart:io`, `experience_engine`
ou `execution_runtime`.

Controllers e ViewModels permanecem imutáveis e testáveis em Dart. O Host
Client é a única fronteira para bootstrap, RPC, events, handles, reconnect e
cache stale. Regras de domínio continuam no Engine/Host e não são
reinterpretadas pelo browser.

### UI e CSS próprios

`studio_ui` expõe componentes Jaspr e classes semânticas. CSS global é
organizado em arquivos externos por responsabilidade:

```text
styles/tokens.css
styles/reset.css
styles/typography.css
styles/layout.css
styles/components.css
styles/utilities.css
styles/accessibility.css
```

Tokens são CSS custom properties. Elementos nativos são preferidos para
button, link, input, select, tabs, dialog e landmarks. ARIA complementa HTML;
não corrige semântica ausente por desenho. Nenhum framework visual externo é
permitido. Uma biblioteca consistente de ícones pode ser encapsulada pelo UI
System.

### Journey Map

O mapa usa nós/thumbnails em DOM, CSS, windowing bounded ao redor da seleção e
um Outline HTML equivalente. Canvas ou `CustomPainter` não fazem parte da UI
final. Scenario permanece a
identidade; screenshot continua projeção opcional por
`Scenario × Variant × Provider`.

### Trust boundaries

O browser nunca recebe path do CAS nem autoridade local. O bootstrap contém o
token apenas no body `no-store`; o token permanece em memória e é enviado
somente no primeiro `workspace.initialize`. URLs, HTML, build defines, logs,
source maps e storage persistente não podem materializá-lo.

O target consumidor permanece em iframe com origin separado e `postMessage`
validado por origin/schema. Flutter embedding do Jaspr é explicitamente
proibido para essa fronteira.

## Consequências

- build e serve do Studio passam de Flutter tooling para Jaspr CLI;
- guards e scripts de distribuição validam o output estático Jaspr;
- testes Flutter do Studio foram substituídos por Dart, Jaspr component tests e
  browser gates;
- performance deixa de ser medida em build/raster Flutter e passa a observar
  bootstrap, DOM, layout, interação e uso de memória;
- a acessibilidade histórica Flutter permanece evidência do baseline, não da
  implementação Jaspr;
- AutoPreview, consumidores e runners continuam Flutter e não são afetados por
  esta decisão.

## Rollout e rollback

O rollout é descrito em
`docs/architecture/jaspr-studio-migration.md`. O spike vive somente em
`.dart_tool/experience_platform/spikes/`. Antes do cutover, rollback significa descartar o
spike ou restaurar o baseline no mesmo worktree; depois do cutover, a
recuperação é o histórico Git, nunca um segundo Studio distribuído.

Nenhum arquivo do baseline será apagado até o vertical Jaspr executar contra o
Host real. Como o worktree contém trabalho não rastreado do usuário, um ponto
de recuperação Git só será criado quando autorizado e sem limpar alterações.

## Evidência exigida para concluir

- spike client-side compila e serve no Pub Workspace;
- rotas e deep links sobrevivem a refresh;
- bootstrap CORS, WebSocket autenticado e resources funcionam com Host real;
- reconexão preserva estado stale e troca token revogado;
- iframe rejeita `postMessage` de origin incorreto;
- duas builds estáticas têm manifest e bytes idênticos;
- guards provam ausência das dependências proibidas;
- browser real cobre os fluxos canônicos, reflow, texto 200%, teclado e
  reduced motion;
- AutoPreview executa stale → collect → fresh ponta a ponta;
- distribuição headless contém zero asset/processo/porta do Studio;
- comparação atual com Atlas registra vantagens e trade-offs por fluxo.

O cutover e o vertical local estão `Confirmed`. Integrações Remote/Hosted/KVM e
target de consumers sem LaunchProfile permanecem `Partial` conforme a matriz de
conformance; não rebaixam o fato arquitetural de existir um único Studio Jaspr.
