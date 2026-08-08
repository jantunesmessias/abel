# Auditoria de acessibilidade do Studio plataforma local

Status: aprovada em 2026-08-09 para o gate plataforma local Flutter histórico. O renderer foi
removido; a evidência do Studio Jaspr atual está em
`docs/quality/studio-conformance.md`.

Escopo histórico: esta auditoria cobre o Explore/Journey/Scenario mínimo e o
Journey Map plataforma local com catálogo fixture. Ela não comprova o shell SR, catálogo real
do Host, thumbnails/device frames, filtros, inspector ou seleção de providers.
Essas superfícies exigem nova conformance de acessibilidade em conformance e promoção do Studio; este
resultado não é reescrito nem promovido para elas.

## Ambiente observado

- Flutter 3.44.8 stable, Dart 3.12.2;
- Chromium 151.0.7922.108 Arch Linux;
- Orca 50.2, AT-SPI2 2.60.6 e Speech Dispatcher 0.12.1/eSpeak NG 1.52.0;
- Niri 26.04, Wayland, Linux x86_64;
- build web release servido somente em `127.0.0.1`;
- Orca e sintetizador executados de uma raiz portatil temporaria, sem instalacao
  global.

## Automacao

`apps/studio/test/accessibility_test.dart` cobre targets rotulados,
tamanho mínimo Android, teclado, reflow em 360 px com texto a 200%, contraste
nos temas claro/escuro e propagacao de reduced motion sem animacao persistente.
O Journey Map publica identificadores e acoes por `CustomPainterSemantics`; a
projecao `Estrutura` materializa o grafo como lista linear independente do
canvas.

`tools/probes/studio_accessibility_driver.dart` usa Chrome DevTools Protocol somente
para dirigir teclas, capturar a AX tree e registrar metricas/screenshot. A
leitura e os eventos de foco foram processados pelo Orca real via AT-SPI.

## Resultado manual assistivo

| Verificacao | Resultado observado |
|---|---|
| Explore → Journey | Orca anunciou `Atualizar catálogo`/`button`; AT-SPI registrou foco em `Primeira jornada 3 cenários` antes da abertura |
| Mapa/Estrutura | foco chegou aos dois seletores; Orca anunciou item corrente e `Estrutura da jornada`, `panel` |
| Estrutura → Scenario | item `1 Descobrir discover` foi anunciado como button e abriu o Scenario Sheet |
| Tab/Shift+Tab | AX focus avancou e retornou entre `Atualizar catálogo` e `Primeira jornada 3 cenários`, sem salto de ordem |
| idioma | finding corrigido: `<html lang="pt-BR">` + locale Flutter; Orca selecionou `Portuguese (Brazil)` |
| zoom 200% | Chromium passou de 948×1064 CSS/1x para 474×532 CSS/2x; `scrollWidth == innerWidth == 474` |
| temas | screenshots clara/escura inspecionadas sem clipping; guideline de contraste passou em ambas |
| reduced motion | nenhum autoplay; `disableAnimations` propagado e zero callback transiente apos settle |
| deep link | refresh preservou `#/journeys/sample/scenarios/discover` e reconstruiu Scenario Sheet |

O zoom foi aplicado com cinco atalhos reais `Ctrl++` pelo browser: 110%, 125%,
150%, 175% e 200%. A captura final mostrou todo o conteudo do Scenario Sheet em
uma unica coluna, sem scroll horizontal global.

Comandos centrais da reproducao:

```bash
flutter build web --release --no-wasm-dry-run
dart run tools/probes/studio_accessibility_driver.dart \
  --port 38292 \
  --target-url-prefix http://127.0.0.1:38291 \
  --enable-flutter-semantics \
  --keys Tab,Enter,Tab,Tab,Enter,Tab,Enter
dart run tools/probes/studio_accessibility_driver.dart \
  --port 38292 \
  --target-url-prefix http://127.0.0.1:38291 \
  --keys Ctrl++,Ctrl++,Ctrl++,Ctrl++,Ctrl++
flutter test apps/studio/test/accessibility_test.dart
```

O driver pressupoe Chromium iniciado com DevTools remoto e
`--force-renderer-accessibility`; ele nao substitui o leitor de tela. O finding
de idioma foi corrigido e reexecutado antes desta aprovacao. Nenhuma claim e
feita para NVDA, ChromeVox, Windows ou mobile screen readers neste gate Linux.

## Integração posterior conformance e promoção do Studio

O vertical operacional do Studio não reclassifica esta auditoria histórica como se o leitor de
tela tivesse sido repetido em todas as novas superfícies. Ele acrescenta as
seguintes evidências automatizadas para o shell atual:

- `accessibility_test.dart`: labels/tap targets, foco de teclado, contraste,
  reflow em 360 px com texto a 200% e reduced motion;
- `journey_map_test.dart`: culling visual sem perder a projeção outline completa;
- `verify_studio_vertical.sh`: build release, catálogo/PNGs reais, Semantics
  habilitado por Chromium, deep link e zero log severo;
- controles de pan/zoom/fit/reset e navegação do mapa por setas, Enter, Espaço,
  `+`, `-`, `0` e `F`.

A claim conformance e promoção do Studio é, portanto, conformance automatizada de teclado/Semantics/reflow
na matriz Chromium executada. Uma nova auditoria manual assistiva específica do
inspector, filtros e coleta continua necessária antes de ampliar a claim para
outros leitores de tela ou plataformas.
