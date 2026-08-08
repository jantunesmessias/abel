# Resultado executado — reference consumer conformance

Data da evidência: 2026-08-13. Baseline local: Flutter 3.47.0, Dart 3.13.0,
Linux x86_64. Escopo: `examples/sample_api`, `examples/sample_flutter` e os
serviços locais compostos exclusivamente pelas APIs públicas do Abel.

## Resultado

O Delivery Lab funciona como consumer de referência executável, não apenas
como catálogo de demonstração. O gate oficial é:

```bash
./tools/verify/verify_reference_consumer.sh
```

Ele analisa e testa os dois packages do consumer, compila conteúdo e quatro
Gateway presets, constrói o Studio Jaspr e o Target Flutter release, inicia
API/Host/Studio, coleta Evidence e exerce o fluxo real antes de encerrar os
processos e verificar os listeners.

Resultado observado:

| Evidência | Resultado |
|---|---:|
| estados da API | `ready`, `loading`, `empty`, `stale`, `unavailable`, `failure` |
| códigos HTTP | 200, 202, 200, 200, 503, 500 |
| Scenarios / Variants | 8 / 3 |
| capturas atuais | 10 de 10 |
| PNGs validados por handle/digest | 10 |
| fidelity / freshness | `structural` / `fresh` |
| Evidence histórica preservada | 24 entradas `unbound` |
| Gateway presets | hybrid, offline, unavailable, failure |
| eventos de tráfego por preset | 3, 2, 1, 1 |
| Target | Flutter web release servido pelo Session owner |
| cleanup | portas 7367, 7368, 8080 e 8181 liberadas |

O preset hybrid encaminhou dashboard e mutação à API real, mas respondeu a
configuração de runtime por fixture sintética. A mutação ficou observável na
API upstream. O preset offline respondeu dashboard e mutação por fixtures sem
alterar a API. `unavailable` permaneceu recuperável e distinto de `failure`
não recuperável.

A lista de Evidence é append-only: o gate exige exatamente as dez bindings
atuais e valida separadamente entradas antigas `unbound`; ele não exige um CAS
vazio nem apaga proveniência para obter uma contagem conveniente.

## Boundary público

O gate chama `tools/gates/architecture_guard.dart`. Produção em `apps/` e `libs/`
não pode referenciar paths ou packages de `examples/`; os testes do runtime
usam consumer temporário próprio. O fluxo de runtime é sempre:

```text
examples -> APIs públicas/schemas/CLI do Abel -> Host -> resources/Evidence
```

Nenhuma claim de `hostNative`, aprovação humana, WCAG completa, hosted,
device-farm ou isolamento de kernel é derivada deste resultado. A captura
AutoPreview continua `structural`, e a conformance visual do Studio permanece
no gate Chrome separado.

## Falha browser preservada e resolução

Uma execução anterior de `tools/verify/verify_studio_vertical.sh` validou RPC,
digests, topologia, cinco NodeInstances, cinco EdgeInstances, branch/merge,
group, lanes e annotation, mas falhou corretamente: o CSP `style-src 'self'`
bloqueou estilos inline usados pela geometria espacial e deixou as arestas com
largura zero. Esse resultado não é promovido. O renderer deve ficar compatível
com o CSP e o gate precisa ser repetido sem afrouxar a política ou suprimir
logs.

O follow-up de 2026-08-13 removeu estilos inline do renderer espacial e
repetiu o gate integral. A primeira repetição encontrou um breadcrumb de
46,125 px; a segunda encontrou `studio.inventory` ausente somente no profile
sem provider. Ambos foram corrigidos na causa, sem reduzir assertions. A
execução final passou com:

| Evidência browser | Resultado |
|---|---:|
| Journey | 5 NodeInstances, 5 EdgeInstances, branch e merge |
| Inventory canônica | 8 Scenarios, 11 eixos de facets |
| Inventory espacial | 5 NodeInstances, 0 EdgeInstances |
| geometria inline / logs severos | 0 / 0 |
| menor alvo interativo | 48 px |
| map interaction p95, 20 amostras | 43,1 ms |
| DOMContentLoaded / load / FCP | 290,8 / 292,9 / 340 ms |
| screenshot Inventory | 1440×1000, `sha256:aaff3dabc2167b4d39fc87374f71112e24f10383f0df1d2bb05406a232f67fd0` |
| provider/no-provider | mesmos digests de topologia, layouts e facets |
| cleanup criado pelo gate | verificado |

A captura foi inspecionada visualmente: filtros, outline, canvas espacial,
seleção, preview estrutural e inspector estavam visíveis sem overflow global.
O resultado não é certificação WCAG nem benchmark de catálogo grande.
