# Sample Flutter — Delivery Lab

Aplicação Flutter consumer-owned usada pelo showcase completo. Ela contém uma
factory real, cliente HTTP real, matriz tipada `ready`, `loading`, `empty`,
`stale`, `unavailable` e `failure`, layout responsivo e uma mutação observável.

```bash
flutter run -d chrome \
  --dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181 \
  --dart-define=EXAMPLE_DASHBOARD_STATE=ready
```

`EXAMPLE_DASHBOARD_STATE` aceita os seis nomes da matriz e é enviado como
query tipada ao `sample_api`; o default é `ready`.

`lib/main.dart` é o entrypoint normal e não importa Abel.
`tool/target_main.dart` é a closure de tooling: lê o bootstrap efêmero web ou o
overlay Android, instala `TargetBinding` e preserva a mesma
`createSampleApp`/`HttpShowcaseApi`.

Os arquivos em `lib/previews/` usam `SyntheticShowcaseApi` apenas como fixture
de dados e montam a UI real. Eles aparecem no Widget Previewer oficial e são
descobertos pelo compiler de auto-preview. No Flutter 3.47.0, o Previewer interativo está
bloqueado pela combinação atual de detector LSP e Pub Workspace; exportação PNG
continua responsabilidade do runner de auto-preview `flutter-test`, que possui gate
independente.

O corpus de referência contém oito Scenarios e oito annotations, expandidos em
dez descriptors e três Variants: `phone.light.en-us`,
`phone.dark.en-us` e `desktop.light.en-us`. A Variant ready reutiliza a mesma
factory em phone light/dark e desktop. Os seis estados da matriz têm previews
e Semantics próprios; em particular, `unavailable` é recuperável e não é
colapsado com `failure`. A topologia permanece sobre seus cinco Scenarios,
com NodeInstances independentes nas projections Journey e Inventory.

Configuração:

- `workspace.yaml`: v2, profile `full-local`, LaunchProfiles separados para
  Session e Scenario Lab, e provider binding;
- `workspace.local.example.yaml`: upstream loopback sem secrets;
- `.experience/`: Board/projections/layouts, Journey, Scenarios, bindings,
  ReviewGuide e quatro presets Gateway;
- `authoring.local`: autoridade Host-derived para draft de layout, review
  append-only e promoção do documento `ProjectionLayout` do próprio content
  root, sem aceitar path ou routing do Studio;
- `journey-no-evidence.yaml`: profile mínimo usado para provar Journey
  Map e Inventory sem EvidenceProvider.

## Target web controlado

O showcase prepara o Target com:

```bash
flutter build web --release \
  --target=tool/target_main.dart \
  --dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181 \
  --dart-define=TARGET_CONTROLLER_ORIGIN=http://127.0.0.1:7368
```

`tool/target_server.dart` serve os assets pré-compilados em loopback. O
servidor recusa traversal/symlinks fora da raiz e métodos além de GET/HEAD,
publica health/SPA fallback e usa `frame-ancestors` exato para permitir somente
o Studio configurado. Isso remove o custo e a instabilidade de inicializar o
frontend server de debug a cada Session sem transformar esse servidor em uma
solução de produção genérica.

O relay tipado só é criado quando o launch fragment contém
`SCENARIO_LAB_RUN_ID` e esse ID coincide exatamente com a Session do
Target. Frames ordinários permanecem sem relay. Cada carregamento gera um
`adapterInstanceId` efêmero e anuncia apenas o controle e o provider de captura
declarados pelo consumer.

O comando recomendado permanece o launcher da raiz:

```bash
dart run examples/tool/showcase.dart
```
