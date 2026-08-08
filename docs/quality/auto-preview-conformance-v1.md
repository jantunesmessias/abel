# AutoPreview conformance v1

Status: suite ativa AP0–AP4 para Flutter 3.44.x; a integração operacional
Host/Studio foi aprovada separadamente no gate SR0–SR9.

## Propriedades verificadas

| Gate | Evidência exigida |
|------|-------------------|
| API | `AutoPreview` é `Preview`; `AutoMultiPreview` é `MultiPreview`; metadata permanece const |
| AP0 | mesma factory real aparece no Widget Previewer e não é importada pelo `main.dart` |
| Scanner | função pública top-level `Widget`/`WidgetBuilder`; annotation resolvida; links e source inválido recusados |
| Compiler | IDs/catálogo/Scenario/Variant validados; expansão e digest determinísticos |
| Registry | geração somente em `.dart_tool`, imports confinados e cleanup |
| Runner | subprocesso por descriptor, env/saída/tempo/artifact limitados e protocol token autenticando a saída local |
| Pixels | viewport/DPR/locale/brightness/text scale, PNG válido, pixel digest e CAS |
| Falha parcial | um descriptor falho não elimina um item coletado independente |
| Policy | sem confirmação sintética produz `policyDenied` e zero pixels persistidos |
| Evidence | manifest/report/fingerprint/capture key coerentes e fidelidade estrutural |
| Journey Map AP4 | collected/stale/missing/failed/unsupported/policyDenied distintos com handle injetado; nunca path CAS |
| Journey Map SR | handle emitido pelo Host, PNG real no Studio, device frame, provider selection e stale→fresh ponta a ponta |

## Gate automatizado

```bash
./tool/verify_auto_preview.sh
```

Ele executa testes do package Flutter, compiler, scanner, runner unitário e
integração real isolada, além do sample consumer. O corpus atual do sample tem
cinco Scenarios, sete descriptors e três Variants; a exigência mínima do gate
de isolamento continua sendo mais de um descriptor independente.

O gate operacional complementar é:

```bash
./tool/verify_studio_vertical.sh
```

Ele não muda a claim AP0–AP4: comprova a cadeia posterior
Evidence/CAS → Host → `WorkspaceSnapshot`/handles → Studio/Chromium, incluindo
fingerprint, capture policy, stale→fresh e execução sem provider.

O AP0 interativo também deve ser repetido em cada minor de Flutter suportado:

```bash
flutter widget-preview start --legacy-preview-detection
```

No Flutter 3.44.8, o detector LSP default falhou dentro do Flutter Tool; o
detector legado encontrou os previews. Essa limitação upstream não é tratada
como prova de exportação de screenshots nem é mascarada pelo runner.

## Falhas bloqueantes

- preview detectado apenas por nome textual e não pelo tipo resolvido;
- geração/import em production source;
- captura sem timeout ou com rede/secrets não controlados;
- artifact em status não coletado;
- claim acima de `structural` no renderer `flutter-test`;
- substituição silenciosa de captura failed/stale por outro artifact;
- resultado dependente da ordem de execução do lote.
