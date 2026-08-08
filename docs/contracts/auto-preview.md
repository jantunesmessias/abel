# AutoPreview v1

Status: contrato ativo do AutoPreview, incluindo a projeção no Journey Map. Decisão: ADR-0013.

## Escopo

AutoPreview é a camada Flutter de autoria do provider opcional
`evidence.auto-preview`. A mesma função anotada é visível no Widget Previewer
oficial e descobrível pelo Auto-preview compiler. A exportação de PNG não usa
uma API interna do Previewer: pertence ao runner isolado do Abel.

O package `flutter_preview` depende apenas de Flutter e de contracts. Analyzer,
filesystem, subprocesso, staging, CAS e Evidence permanecem fora da API de
autoria.

## API Flutter

```dart
@AutoPreview(
  id: 'sample.launch',
  scenarioId: 'launch-sample',
  variantId: 'phone.light.pt-br',
  size: Size(390, 844),
  localeTag: 'pt-BR',
  brightness: Brightness.light,
  devicePixelRatio: 3,
  fixtureRef: 'sample.launch.synthetic',
  capturePolicyId: 'static-v1',
)
Widget launchPreview() => createSampleApp(previewConfig);
```

`AutoPreview` estende `Preview`. `AutoMultiPreview` estende `MultiPreview` e
expande uma lista const de `AutoPreviewVariant`. A compatibilidade corrente é
`Flutter 3.47.x` e `widgetPreviewApi: experimental-v2`. A classificação da API
permanece experimental porque seus tipos públicos mudaram nesta linha, mesmo
com a ferramenta interativa anunciada como estável.

Restrições da descoberta inicial:

- função pública top-level, sem parâmetros;
- retorno `Widget` ou `WidgetBuilder`;
- annotation e argumentos avaliáveis como constantes;
- source sob `lib/**/*.dart`, sem symlink;
- `id`, `scenarioId` e `variantId` explícitos;
- a factory deve reutilizar a UI real; a annotation não autoriza uma segunda
  implementação da tela;
- AutoPreview referencia um Scenario do catálogo e nunca o cria.

`AutoMultiPreview` representa Variants visuais do mesmo Scenario. Estados
semânticos diferentes continuam sendo Scenarios diferentes.

## Contratos canônicos

Todos os documentos conformam `schemas/evidence/preview-capture.schema.json`, usam
JSON canônico e incluem digest semântico quando são documentos raiz.

| Tipo | Responsabilidade |
|------|------------------|
| `Variant` | viewport lógico, DPR, brightness, locale, text scale e theme |
| `PreviewDescriptor` | identidade, Scenario, Variant, source, factory, fixture e policy |
| `PreviewManifest` | lote normalizado e vínculo ao catálogo/Flutter |
| `PreviewCaptureItem` | resultado fechado de uma captura individual |
| `PreviewCaptureManifest` | renderer, fingerprint, toolchain e itens do lote |
| `PreviewCaptureReport` | tempos, contagens e diagnósticos da execução |

A chave de um descriptor é `AutoPreviewId:VariantId`. Um AutoPreview não pode
abranger mais de um Scenario. Uma Variant reutilizada por fontes distintas
precisa ter o mesmo digest canônico.

Status fechados por item:

```text
collected | invalid | failed | unsupported | policyDenied
```

Somente `collected` contém, conjuntamente, `artifactDigest`, `pixelDigest`,
`pixelWidth` e `pixelHeight`. Resultado de falha nunca contém artifact parcial.

## Descoberta e compilação

O scanner usa Analyzer e reconhece o tipo resolvido no package oficial
`flutter_preview`; semântica por nome textual isolado não basta. O compiler:

1. valida a assinatura e os valores const;
2. expande AutoMultiPreview;
3. normaliza Variant e descriptor;
4. confronta Application/Scenario com o catálogo;
5. ordena e produz `PreviewManifest`;
6. gera registry efêmero em `.dart_tool/workspace/preview/<plan-digest>/`.

Não há `build_runner`, geração em `lib/`, reflection ou import pelo entrypoint
de produção.

## Captura e Evidence

O renderer v1 é `flutter-test`. Cada descriptor roda em subprocesso isolado e
serial, configura viewport/DPR/locale/brightness/text scale, monta a factory em
`RepaintBoundary` e aplica uma policy limitada. O default `static-v1` usa
frames fixos. Duração fixa e `pumpAndSettle` possuem limites e timeout.

O runner valida PNG, calcula digest dos pixels, persiste o blob no CAS e gera
manifest/report. O `captureKey` inclui descriptor/manifest, plan, toolchain,
policy e inputs declarados. Renderer distinto constitui fingerprint distinto;
igualdade de pixels entre Skia e Chrome não é prometida.

Persistir pixels exige `syntheticDataConfirmed: true`. Sem a confirmação, cada
item recebe `policyDenied` e nenhum PNG é ingerido.

## Fidelity e limites da claim

O renderer `flutter-test` declara somente `RuntimeFidelity.structural`. Ele
comprova composição Flutter controlada, não:

- plugin ou integração nativa;
- teclado, permissão, chrome ou navegação do sistema operacional;
- rede, Gateway ou backend real;
- execução em dispositivo/emulador;
- fidelidade `hostNative` ou `deviceAttested`.

App Adapter e Android permanecem providers independentes e selecionáveis.
Journey Map funciona também sem qualquer visual Evidence.

## Compatibilidade

Mudança incompatível exige schema/reader adjacente. Upgrade do Flutter exige
conformance do package `flutter_preview`, do scanner e do spike no Previewer; não
altera automaticamente os contracts de Evidence ou composição.
