# Consumer configuration v2

Status: schema, loader, resolver e migration ativos MC1–MC4.

`schemas/v2/consumer-config.schema.json` preserva distribution, content,
workspace e applications de v1 e acrescenta `launchProfiles` opcional e `kit`
fechado:

```yaml
schemaVersion: 2
content:
  root: .devex
workspace:
  id: sample
applications:
  sample:
    root: .
    target: web
launchProfiles:
  sample-web:
    applicationId: sample
    platform: web
    command: flutter
    arguments: [run, -d, web-server, --web-port=8080]
    workingDirectory: .
    overlay: {DEVEX_EXAMPLE_MODE: full}
    bootstrapPolicy: {api: production, gateway: overlay}
kit:
  profile: journey-preview
  modules:
    catalog:
      enabled: true
    evidence.auto-preview:
      enabled: true
      settings:
        renderer: flutter-test
        capturePolicy: static-v1
  providerBindings: []
  startupPolicy: fail-required-v1
```

Precedência normativa:

```text
Kernel < Distribution < Profile < Workspace < local < startup
```

Cada camada é normalizada e validada antes da próxima. Módulos não são
habilitados implicitamente. Settings desconhecidos são validados pelo schema do
Module após composição; secret literal é recusado e configuração usa apenas
referências de secret autorizadas. Paths permanecem relativos/confinados e
symlink nunca amplia o workspace.

`launchProfiles` descreve somente como iniciar um target; ele não declara um
Scenario nem reconhece estado. O key é o ID canônico, `applicationId` deve
existir, `platform` é `web` ou `androidEmulator`, e `workingDirectory` é
relativo/confinado ao workspace. `command` e `arguments` são entregues a
`Process.start` sem shell somente quando o usuário inicia uma Session. Overlay
aceita apenas strings e recusa keys semelhantes a secrets; material sensível
continua fora do documento versionado. `bootstrapPolicy` classifica cada
dependência como `production`, `overlay`, `simulated` ou `blocked`.

O `devex dev` fornece esses profiles ao Host. No target web, o Studio injeta
`DEVEX_SESSION_ID`, nonce e sua origem exata em um fragmento base64url do
iframe. O fragmento não é enviado ao servidor HTTP e o iframe usa
`no-referrer`; o adapter valida origem, source, sessão, nonce e sequência antes
de aceitar comandos.

Config v1 não é reescrita durante leitura. O translator produz em memória
uma seleção equivalente ao profile `legacy-full-local-v1`, e ambos os formatos
seguem para o mesmo `ResolvedKitPlan`. Migration autoral permanece
preview-first, ownership-aware e rollbackável.

O comando operacional é:

```bash
devex config migrate --to 2 --dry-run
devex config migrate --to 2 --apply
```

`--dry-run` é puro. `--apply` escreve o documento v2 por troca atômica e
preserva `devex.yaml.v1.bak`; uma configuração já v2 é idempotente. O profile
pode ser sobrescrito no startup (`--profile`) sem alterar o arquivo autoral.
