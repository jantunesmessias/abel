# Resultado executado do FOUNDATION

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64,
Google Chrome/Chromium profile com CanvasKit.

| Spike | Resultado | Evidencia reproduzivel |
|---|---|---|
| S-01 contracts | aprovado | `tools/verify/verify_standards.sh`; 1.076/1.076 casos JSON Schema do perfil e 6/6 JCS |
| S-02 Host/Studio/iframe | aprovado | testes reais WebSocket, auth/origin, oversize, reconnect/replay e teste Chrome de `postMessage` |
| S-03 factory consumer-owned | aprovado | production entrypoint sem tooling; tooling target web compilado |
| S-04 Journey Map | aprovado | widget/semantics e benchmark profile abaixo |

## Benchmark S-04

Corpus deterministico: 1.000 nodes e 5.000 transitions, viewport 1440x1000,
warmup separado e 171 frames de pan em regime estavel. Resultado da execucao de
referencia:

- primeiro frame: 494,4 ms (budget 1.500 ms);
- pan build+raster p95: 12,1 ms (budget 16,7 ms);
- pan build+raster p99: 18,1 ms (budget 33,3 ms);
- build p95: 1,9 ms; raster p95: 10,6 ms.

O renderer usa tiles para detalhe estatico, arestas somente com ambos os
endpoints materializados e LOD por pontos durante o gesto. O benchmark exclui
somente os frames de troca detalhe/LOD do intervalo de pan; primeiro render e
transicoes permanecem exercitados fora desse percentil.

Execute `tools/benchmarks/journey_map_benchmark.sh`. Resultados ficam em
stdout e nao sao tratados como fonte versionada. Os números acima preservam o
spike histórico FOUNDATION; o comando atual executa o corpus escala e auditoria terminal e seus budgets, não
reproduz a antiga implementação Flutter/CustomPainter.
