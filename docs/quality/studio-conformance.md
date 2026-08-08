# Abel Studio conformance v1

Status: suite Jaspr ativa; última execução completa do vertical em 2026-08-13.

## Escopo da claim

A conformance cobre o único `apps/studio`, uma SPA Jaspr conectada a um
Host real do sample. Ela não promove o baseline Flutter histórico a evidência
Jaspr e não certifica toda combinação hosted/device-farm.

## Gate oficial

```bash
./tools/verify/verify_studio_vertical.sh
```

O gate cria portas e diretórios temporários, inicia Host e Studio release,
executa Google Chrome headless por Chrome DevTools Protocol e valida:

1. architecture guard: Studio/UI sem Flutter, Material, Cupertino, `dart:io`,
   engine ou runtime;
2. build Jaspr client-side e bootstrap `/studio/bootstrap.json`;
3. origin/CORS, RPC e `WorkspaceSnapshot` por resource handle;
4. profile `journey-preview` com oito Scenarios, dez descriptors e três
   Variants AutoPreview;
5. dez PNGs válidos, digests, leases Blob e requests de resource esperadas;
6. content-set atômico, Journey e Inventory sobre os mesmos digests de
   catálogo/topologia/layout/facets;
7. deep links de NodeInstance, branch/merge, mapa/outline, zoom, filtros por
   URL e Inspector;
8. confirmation dialog nativo, foco inicial, Escape e restauração do opener;
9. stale→collect→fresh após source impact real;
10. profile sem Evidence preservando Journey/Inventory e sem requests
    indevidos;
11. DOM semântico, `main`, `nav`, `h1`, live region e zero elementos Flutter;
12. navegação Tab, nomes acessíveis e alvos interativos;
13. reflow em 360 px com texto a 200%, sem overflow horizontal do documento;
14. `prefers-reduced-motion` com duração efetiva próxima de zero;
15. AX tree e ausência de logs severos;
16. load/FCP/bytes transferidos e 20 interações de zoom com p95 abaixo de
    100 ms;
17. encerramento sem listener, subprocesso ou token órfão criado pelo gate.

Resultado fresco do vertical executado após Target/Gateway/Remote e windowing:

| Evidência | Resultado |
|---|---:|
| Scenarios / descriptors / Variants | 8 / 10 / 3 |
| PNGs validados | 10 |
| fidelity | `structural` |
| source impact | stale→fresh |
| Journey / Inventory spatial nodes | 5 / 5 |
| Journey / Inventory edges | 5 / 0 |
| Inventory facets | 8 Scenarios / 11 eixos |
| focusables sem nome | 0 de 31 |
| menor alvo interativo | 48 px |
| Tab stops distintos | 8 |
| overflow do documento a 200% | não |
| map interaction p95 | 43,1 ms |
| DOMContentLoaded / load / FCP | 290,8 / 292,9 / 340 ms |
| bytes transferidos | 635.949 |
| logs severos | 0 |

Métricas de sessões de desenvolvimento com DWDS permanecem separadas das
métricas acima: o gate oficial sempre usa assets release para não confundir
tooling com distribuição.

## Windowing e mapa denso

`SequenceWindowPolicy` é testada com 10.000 Scenarios e limita o canvas a
24 itens ao redor da seleção. O Outline completo continua o modelo acessível e
os boundaries orientam a navegação. O browser gate mede o corpus real do sample;
ele não mede layout/renderização de 10.000 cards simultâneos, pois esse DOM é
deliberadamente proibido pelo windowing.

```bash
./tools/benchmarks/journey_map_benchmark.sh
```

O benchmark é um wrapper do vertical e registra separadamente a prova pura de
bounded DOM e a performance do browser.

## Capabilities condicionais

| Contribution | Superfície | Gate atual |
|---|---|---|
| `studio.shell` | bootstrap, shell, Overview | browser real |
| `studio.journey-map` | Journey/Inspector/AutoPreview | browser real ponta a ponta |
| `studio.inventory` | catálogo canônico, filtros e projection espacial | browser real com e sem Evidence provider |
| `studio.target` | Session + iframe sandboxed | sample real pré-compilado, health HTTP, headers e teardown |
| `studio.gateway` | preset guiado, start/status/traffic/reset/stop | sidecar real, target pelo `dataOrigin`, CORS exato e ownership cascade |
| `studio.remote-session` | grant one-time, WebSocket, iframe/screenshot/H.264 | protocol/machine/component/build; endpoint hosted real fora da matriz local |
| `studio.hosted` | status de vinculação | capability gating; control plane real fora da matriz local |
| Review | `ReviewGuide` do catálogo | component/catalog; sample não publica guide |

Remote/Hosted continuam explicitamente `Partial` onde o ambiente local não
fornece endpoint, grant, KVM ou control plane. Target/Gateway do sample não
dependem mais de IDs ou digests digitados manualmente. Nenhuma ausência externa
é convertida em Pass.

## Limites mantidos

- AutoPreview `flutter-test` prova composição estrutural, não host-native;
- Widget Previewer é autoria interativa e não exporta PNG;
- Flutter 3.47.0 apresenta regressão do Previewer neste Pub Workspace; spike do AutoPreview não
  é promovido a Pass pelo runner estrutural independente;
- sandbox portátil de rede/memória depende do host;
- o gate não é auditoria WCAG completa nem certificação hosted/device-farm;
- comparação Atlas sustenta decisões observadas, não superioridade universal.
