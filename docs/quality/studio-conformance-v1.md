# DevEx Studio conformance v1

Status: suite Jaspr ativa; última execução completa do vertical em 2026-08-11.

## Escopo da claim

A conformance cobre o único `apps/devex_studio`, uma SPA Jaspr conectada a um
Host real do sample. Ela não promove o baseline Flutter histórico a evidência
Jaspr e não certifica toda combinação hosted/device-farm.

## Gate oficial

```bash
./tool/verify_studio_vertical.sh
```

O gate cria portas e diretórios temporários, inicia Host e Studio release,
executa Google Chrome headless por Chrome DevTools Protocol e valida:

1. architecture guard: Studio/UI sem Flutter, Material, Cupertino, `dart:io`,
   engine ou runtime;
2. build Jaspr client-side e bootstrap `/devex/bootstrap.json`;
3. origin/CORS, RPC e `WorkspaceSnapshot` por resource handle;
4. profile `journey-preview` com cinco Scenarios, sete descriptors e três
   Variants AutoPreview;
5. sete PNGs válidos, digests, leases Blob e requests de resource esperadas;
6. deep link de Scenario, mapa/lista, zoom e Inspector;
7. confirmation dialog nativo, foco inicial, Escape e restauração do opener;
8. stale→collect→fresh após source impact real;
9. profile sem Evidence, sem botão/requests indevidos;
10. DOM semântico, `main`, `nav`, `h1`, live region e zero elementos Flutter;
11. navegação Tab, nomes acessíveis e alvos interativos;
12. reflow em 360 px com texto a 200%, sem overflow horizontal do documento;
13. `prefers-reduced-motion` com duração efetiva próxima de zero;
14. AX tree e ausência de logs severos;
15. load/FCP/bytes transferidos e 20 interações de zoom com p95 abaixo de
    100 ms;
16. encerramento sem listener, subprocesso ou token órfão.

Resultado fresco do vertical executado após Target/Gateway/Remote e windowing:

| Evidência | Resultado |
|---|---:|
| Scenarios / descriptors / Variants | 5 / 7 / 3 |
| PNGs validados | 7 |
| fidelity | `structural` |
| source impact | stale→fresh |
| dialog initial focus | `Confirmo dados sintéticos` |
| focus após Escape | `Coletar novamente` |
| focusables sem nome | 0 de 29 |
| menor alvo interativo | 48 px |
| Tab stops distintos | 8 |
| overflow do documento a 200% | não |
| map interaction p95 | 33,4 ms |
| DOMContentLoaded / load / FCP | 113,5 / 114,7 / 136 ms |
| bytes transferidos | 492.608 |
| logs severos | 0 |

Métricas de sessões de desenvolvimento com DWDS permanecem separadas das
métricas acima: o gate oficial sempre usa assets release para não confundir
tooling com distribuição.

## Windowing e mapa denso

`DevExSequenceWindowPolicy` é testada com 10.000 Scenarios e limita o canvas a
24 itens ao redor da seleção. O Outline completo continua o modelo acessível e
os boundaries orientam a navegação. O browser gate mede o corpus real do sample;
ele não mede layout/renderização de 10.000 cards simultâneos, pois esse DOM é
deliberadamente proibido pelo windowing.

```bash
./tool/benchmark_journey_map.sh
```

O benchmark é um wrapper do vertical e registra separadamente a prova pura de
bounded DOM e a performance do browser.

## Capabilities condicionais

| Contribution | Superfície | Gate atual |
|---|---|---|
| `studio.shell` | bootstrap, shell, Overview | browser real |
| `studio.journey-map` | Journey/Inspector/AutoPreview | browser real ponta a ponta |
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
- Flutter 3.44.8 requer `--legacy-preview-detection` no gate interativo;
- sandbox portátil de rede/memória depende do host;
- o gate não é auditoria WCAG completa nem certificação hosted/device-farm;
- comparação Atlas sustenta decisões observadas, não superioridade universal.
