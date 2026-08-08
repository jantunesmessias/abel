# Matriz de capabilities do Studio

Status: matriz implementada em 2026-08-11.

O `ResolvedKitPlan` seleciona Modules. Depois do lifecycle, o Host publica
`EffectiveKitManifest.studioContributions`; o Studio Jaspr não infere
capability por nome de profile, grant ou presença de dados.

## Profiles built-in

| Profile | Contributions esperadas | Efeitos ausentes por design |
|---|---|---|
| `journey-preview` | shell, Journey Map | sem Session, Target, Gateway, Android, Remote ou Hosted |
| `journey-android` | shell, Journey Map, Target | sem AutoPreview e sem Gateway; Android Evidence é provider independente |
| `gateway-lab` | shell, Target, Gateway | sem Journey Map/Evidence por default |
| `gateway-lab-headless` | nenhuma | sem assets, route, browser, bootstrap ou listener do Studio |
| `full-local` | shell, Journey Map, Target, Gateway, Remote, Hosted | integrações externas ainda dependem de ambiente/grant |
| `legacy-full-local-v1` | igual a `full-local` após tradução | nenhuma semântica paralela de renderer |

Overlays podem ligar/desligar Modules individualmente; a contribuição efetiva
é sempre derivada do manifest pós-lifecycle.

## Contribution → superfície

| Contribution/dado | Navegação/rota | Operação |
|---|---|---|
| `studio.shell` | `/` | bootstrap, reconnect, Overview |
| `studio.journey-map` | `/journeys/:id[/scenarios/:id]` | mapa/lista/Inspector/visual Evidence |
| `studio.target` | `/target` | Session start/reset/stop + readiness + iframe isolado |
| `studio.gateway` | `/gateway` | presets do Host + start/status/traffic/reset/stop |
| `CatalogManifest.reviewGuides` não vazio | `/reviews` | steps/criteria ligados a Scenario/binding |
| `studio.remote-session` | `/remote/:runId` | one-time grant, WSS, iframe/screenshot/H.264 |
| `studio.hosted` | `/hosted` | estado de vinculação ao control plane |

Uma URL direta para uma contribution ausente mostra boundary explícito; ela não
registra RPC nem produz efeito. Esconder um link é UX, não autorização: Host e
ModuleKernel continuam validando capability e parâmetros.

## Evidence providers

Provider selection é ortogonal à contribution Journey Map. O mapa funciona sem
provider e preserva `unbound/missing`. `evidence.auto-preview` anuncia coleta;
`evidence.android` e `capture.app-adapter` não herdam essa ação. Fidelity vem do
provider/fingerprint, nunca da UI.

No consumer de referência, Gateway deriva a Session do Target ativo e recebe
descriptors dos presets compilados pelo Host; o usuário não transporta IDs nem
digests manualmente entre superfícies. Ao parar a Session, resources owned
incluindo Gateway são removidos em cascata.

## Configuração

Não existe:

```yaml
studio:
  renderer: flutter
```

Existe seleção modular:

```yaml
kit:
  profile: journey-preview
  modules:
    studio.shell:
      enabled: true
    studio.journey-map:
      enabled: true
    sessions.local:
      enabled: false
```

Jaspr é implementação interna de `studio.shell`, não opção de configuração.
