# Sample Flutter — Delivery Lab

Aplicação Flutter consumer-owned usada pelo showcase completo. Ela contém uma
factory real, cliente HTTP real, estados loading/ready/failure, layout
responsivo e uma mutação observável.

```bash
flutter run -d chrome \
  --dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181
```

`lib/main.dart` é o entrypoint normal e não importa DevExKit.
`tool/devex_main.dart` é a closure de tooling: lê o bootstrap efêmero web ou o
overlay Android, instala `DevExFlutterBinding` e preserva a mesma
`createSampleApp`/`HttpShowcaseApi`.

Os arquivos em `lib/previews/` usam `SyntheticShowcaseApi` apenas como fixture
de dados e montam a UI real. Eles aparecem no Widget Previewer oficial e são
descobertos pelo compiler DevEx. Para Flutter 3.44.8, a experiência interativa
usa `--legacy-preview-detection`; exportação PNG continua responsabilidade do
runner DevEx `flutter-test`.

O corpus de referência cobre todos os cinco Scenarios com cinco annotations,
sete descriptors expandidos e três Variants: `phone.light.en-us`,
`phone.dark.en-us` e `desktop.light.en-us`. A Variant ready reutiliza a mesma
factory em phone light/dark e desktop; loading, mutação concluída, tráfego de
Gateway e failure são Scenarios distintos.

Configuração:

- `devex.yaml`: v2, profile `full-local`, LaunchProfile e provider binding;
- `devex.local.example.yaml`: upstream loopback sem secrets;
- `.devex/`: Journey, Scenarios, bindings, ReviewGuide e três presets Gateway;
- `devex.journey-no-evidence.yaml`: profile mínimo usado para provar Journey
  Map sem EvidenceProvider.

## Target web controlado

O showcase prepara o Target com:

```bash
flutter build web --release \
  --target=tool/devex_main.dart \
  --dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181 \
  --dart-define=DEVEX_CONTROLLER_ORIGIN=http://127.0.0.1:7368
```

`tool/devex_target_server.dart` serve os assets pré-compilados em loopback. O
servidor recusa traversal/symlinks fora da raiz e métodos além de GET/HEAD,
publica health/SPA fallback e usa `frame-ancestors` exato para permitir somente
o Studio configurado. Isso remove o custo e a instabilidade de inicializar o
frontend server de debug a cada Session sem transformar esse servidor em uma
solução de produção genérica.

O comando recomendado permanece o launcher da raiz:

```bash
dart run examples/tool/showcase.dart
```
