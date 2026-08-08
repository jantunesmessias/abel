# Conformance do AutoPreview

Status: suite automatizada do AutoPreview ativa para Flutter 3.47.x; o fluxo interativo
está bloqueado pela regressão do Widget Previewer descrita abaixo. A integração
operacional Host/Studio foi aprovada separadamente no gate do Studio.

## Propriedades verificadas

| Gate | Evidência exigida |
|------|-------------------|
| API | `AutoPreview` é `Preview`; `AutoMultiPreview` é `MultiPreview`; metadata permanece const |
| spike do AutoPreview | mesma factory real aparece no Widget Previewer e não é importada pelo `main.dart` |
| Scanner | função pública top-level `Widget`/`WidgetBuilder`; annotation resolvida; links e source inválido recusados |
| Compiler | IDs/catálogo/Scenario/Variant validados; expansão e digest determinísticos |
| Registry | geração somente em `.dart_tool`, imports confinados e cleanup |
| Runner | subprocesso por descriptor, env/saída/tempo/artifact limitados e protocol token autenticando a saída local |
| Pixels | viewport/DPR/locale/brightness/text scale, PNG válido, pixel digest e CAS |
| Falha parcial | um descriptor falho não elimina um item coletado independente |
| Policy | sem confirmação sintética produz `policyDenied` e zero pixels persistidos |
| Evidence | manifest/report/fingerprint/capture key coerentes e fidelidade estrutural |
| Journey Map | collected/stale/missing/failed/unsupported/policyDenied distintos com handle injetado; nunca path CAS |
| Integração Studio | handle emitido pelo Host, PNG real no Studio, device frame, provider selection e stale→fresh ponta a ponta |

## Gate automatizado

```bash
./tools/verify/verify_auto_preview.sh
```

Ele executa testes do package Flutter, compiler, scanner, runner unitário e
integração real isolada, além do sample consumer. O corpus atual do sample tem
oito Scenarios, dez descriptors e três Variants; a exigência mínima do gate
de isolamento continua sendo mais de um descriptor independente.

O gate operacional complementar é:

```bash
./tools/verify/verify_studio_vertical.sh
```

Ele não muda a claim do AutoPreview: comprova a cadeia posterior
Evidence/CAS → Host → `WorkspaceSnapshot`/handles → Studio/Chromium, incluindo
fingerprint, capture policy, stale→fresh e execução sem provider.

O fluxo interativo do AutoPreview deve ser repetido em cada minor de Flutter suportado:

```bash
flutter widget-preview start --web-server --no-pub
```

No Flutter 3.47.0, a execução na raiz inicia o serviço, mas falha no gerador LSP
ao encontrar um preview sem `packageName`; dentro de `sample_flutter`, a
resolução do scaffold conflita com `resolution: workspace`. A opção
`--legacy-preview-detection` não existe mais. O fluxo interativo permanece bloqueado até uma
correção upstream ou um adapter dedicado; essa falha não é mascarada pelo
runner do AutoPreview, que continua sendo validado separadamente.

## Falhas bloqueantes

- preview detectado apenas por nome textual e não pelo tipo resolvido;
- geração/import em production source;
- captura sem timeout ou com rede/secrets não controlados;
- artifact em status não coletado;
- claim acima de `structural` no renderer `flutter-test`;
- substituição silenciosa de captura failed/stale por outro artifact;
- resultado dependente da ordem de execução do lote.
