# Resultado executado do GATEWAY ISOLATED Gateway isolated

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64.

## Vertical fechado

O fluxo exercitado e:

```text
GatewayScope/Preset/Route/Fixture autorais
  -> GatewayPlanCompiler -> JCS/CAS handles
  -> CLI -> Host RPC autenticado
  -> sidecar exclusivo -> HTTP loopback
  -> MockHandlerPort compartilhado por API/verify
  -> TrafficEvent / verify body artifact
  -> stop da Session encerra processo e listener
```

Entregas verificadas:

- commands `gateway run/status/apply-preset/verify/traffic/reset/stop`;
- schema `schemas/gateway/gateway-plan.schema.json` e codecs fail-closed;
- `backendMode: isolated`, `networkContainment: gatewayOnly` e unknown deny;
- method/path/query/`appliesTo`, latency, forced status e disconnect real;
- fixture sintetica lazy por digest, maximo 256 KiB, sem body inline no plano;
- stdio incremental limitado a 1 MiB e Host RPC limitado a 64 KiB;
- verify body armazenado no CAS e comparado por digest/tamanho;
- buffer de 10.000 eventos ou 64 MiB com eviction contabilizada;
- dois sidecars simultaneos com process, port, fixture, state e traffic distintos;
- encerramento do owner Session sem processo/listener residual.

## Benchmark AOT de referencia

Execute:

```bash
./tools/benchmarks/gateway_benchmark.sh
```

Resultado observado em 2026-08-09, 50 amostras por corpo apos 10 warmups:

| Body | p50 | p95 | p99 | Budget |
|---:|---:|---:|---:|---:|
| 1 KiB | 0,204 ms | 0,611 ms | 1,053 ms | p95 <= 10 ms; p99 <= 25 ms |
| 256 KiB | 1,746 ms | 2,613 ms | 3,541 ms | p95 <= 10 ms; p99 <= 25 ms |

O gate recompila o benchmark como executavel AOT; os numeros sao evidencia da
maquina identificada, nao promessa universal. Regressao falha explicitamente.

## Resolucao de Q-06 e Q-07

- Q-06: `shelf`/`dart:io` foi mantido apos conformance de limites, headers,
  request abortada, disconnect, lifecycle e benchmark.
- Q-07: o plano fechado v1 usa digest semantico e handles CAS lazy; plano e
  control message sao limitados a 1 MiB, fixture a 256 KiB e bytes de verify nao
  atravessam inline o Host RPC.

O resultado nao faz claim de passthrough, upstream, `targetEnforced` ou
substituicao operacional do gateway legado; esses gates pertencem a GATEWAY CONTAINMENT/web/Android.
