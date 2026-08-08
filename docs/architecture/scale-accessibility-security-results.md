# Resultado executado — escala, acessibilidade e segurança

Data: 2026-08-17. Este documento registra uma prova local portátil. Ele separa
os números observados dos budgets configurados e não os promove a SLO,
certificação WCAG ou garantia de sandbox.

## Comando autoritativo

```bash
./tools/verify/verify_scale_accessibility_security_vertical.sh
```

O gate gera dois workspaces limpos fora do repositório, compila e exporta ambos,
compara as árvores e os exports byte a byte, inicia Host e Studio reais e audita
a Journey profunda no Chromium por WebDriver. O teste de reversibilidade é:

```bash
./tools/verify/scale_accessibility_security_reversibility_test.sh
```

## Ambiente observado

- Linux 6.18.44-1-lts x86_64;
- Dart 3.13.0 stable, linux_x64;
- Chromium 151.0.7922.137 e ChromeDriver 151.0.7922.137;
- 8 processadores lógicos;
- 33.291.661.312 bytes de memória física reportada.

Esses valores descrevem a execução registrada. O report JSON também grava o
ambiente de cada execução para impedir comparação sem contexto.

## Corpus e determinismo

| Medida | Resultado |
|---|---:|
| documentos autorais | 44.004 |
| bytes autorais | 9.266.612 |
| Scenario / NodeInstance | 2.000 / 2.000 |
| Transition / EdgeInstance | 20.000 / 20.000 |
| bytes do export | 6.623.188 |
| builds limpos comparados | 2 |
| exports limpos comparados | 2 |

As duas árvores e os dois exports foram byte-idênticos. O grafo é não linear e
os dados são JCS com newline canônico. A execução não escreve no consumer de
referência nem deixa a árvore de corpus no repositório.

## Baseline e budgets

| Limite | Observado | Budget configurável |
|---|---:|---:|
| arquivos autorais | 44.004 | 50.000 |
| bytes por arquivo | abaixo de 1 MiB | 1.048.576 |
| bytes autorais agregados | 9.266.612 | 33.554.432 |
| tempo total do verificador | 9.326 ms | 30.000 ms |
| RSS observado | 812.437.504 | 1.610.612.736 |
| bytes do export | 6.623.188 | 16.777.216 |
| windowing p95, 9 amostras | 13.200 µs | 50.000 µs |

Na mesma execução, load levou 4.311 ms, Catalog 1.622 ms, topology 2.451 ms e
export 733 ms. O budget usa margem sobre a medição e continua configurável por
variável de ambiente. Uma regressão que ultrapasse qualquer limite falha sem
relaxamento automático.

## Virtualização e impacto

- policy pura: 24 itens, 10 arestas renderizáveis e 256 de 480 arestas de
  fronteira retidas;
- Chrome: DOM 1.373, outline 48/2.000, mapa 64 nós, 40 arestas e 256 de 1.200
  diagnósticos de fronteira;
- impacto incremental: 8 bindings impactados e 1.992 reutilizáveis;
- descriptors: um isolate aquecido, quatro batches, 256 entradas, 255 sucessos,
  uma falha isolada e sucesso após a falha.

O outline e as listas de fallback usam uma janela máxima de 48. O mapa limita
itens a 64, arestas renderizáveis a 256 e diagnósticos de fronteira a 256, mas
preserva contagens totais para comunicar omissões sem materializá-las.

## Browser e captura

O Chromium real provou teclado, foco visível, landmarks nomeados, navegação sem
drag, reflow a 360 px, texto a 200%, reduced motion e ausência de overflow
global. Cinco controles essenciais visíveis tiveram contraste textual mínimo
calculado de 7,37:1. Não houve marcador sensível no HTML nem log severo.

A captura 1440×857 teve digest
`sha256:9b8a0d0e4a7dbcea362e9e045539dd8508fde73f37bc39b45b5adb66255c68dd`
e foi inspecionada em resolução original: outline, mapa e inspector estavam
legíveis, sem sobreposição ou corte horizontal. Os cards sem imagem exibiam o
estado explícito do corpus sintético. A captura temporária foi removida após a
inspeção.

## Segurança, reversibilidade e limites

O loader rejeita links e arquivos mutáveis durante a leitura e aplica limites
antes do parse. O worker rejeita descriptor com chave de path e mantém as
entradas seguintes. O browser procura marcadores de authority, policy,
principal, grant, content root, credenciais e chaves privadas. A injeção em
`host-ready` terminou com status 97, liberou Host, Studio e ChromeDriver e
removeu a raiz privada.

O gate não prova tecnologia assistiva, todos os temas/idiomas, WCAG integral,
device farm, comportamento de providers externos, isolamento de socket/kernel
ou cargas acima do corpus e budgets registrados. Essas fronteiras permanecem
externas e não são descritas como aprovadas.
