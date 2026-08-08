# Consumer configuration v2

Status: schema, loader e resolver ativos na composição modular.

`schemas/distribution/consumer-config.schema.json` define o único formato publicado do
arquivo principal, com `distribution`, `content`, `workspace`, `applications`,
`launchProfiles` opcional e `kit` fechado:

```yaml
schemaVersion: 2
content:
  root: .experience
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
    overlay: {SAMPLE_MODE: full}
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

O `workspace dev` fornece esses profiles ao Host. No target web, o Studio injeta
`SESSION_ID`, nonce e sua origem exata em um fragmento base64url do
iframe. O fragmento não é enviado ao servidor HTTP e o iframe usa
`no-referrer`; o adapter valida origem, source, sessão, nonce e sequência antes
de aceitar comandos.

O loader recusa qualquer outra revisão antes da resolução do plano e antes de
efeitos. Não houve configuração externa publicada que exigisse migrador no
produto. O profile pode ser sobrescrito no startup (`--profile`) sem alterar o
arquivo autoral.
