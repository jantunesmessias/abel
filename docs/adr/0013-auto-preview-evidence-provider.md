# ADR-0013 — AutoPreview como autoria Flutter e EvidenceProvider estrutural

Status: aceita em 2026-08-10.

## Contexto

O Journey Map precisa associar uma representação visual a `Scenario × Variant`
sem tornar App Adapter, navegador controlado ou Android dependências implícitas.
O Flutter 3.44.8 oferece o Widget Previewer experimental e permite especializar
as classes públicas `Preview` e `MultiPreview`. A mesma API, porém, não expõe
um contrato público para exportar screenshots, manifests ou Evidence em lote.

Usar somente o Previewer oficial deixaria a coleta dependente de uma ferramenta
interativa e de detalhes internos do Flutter. Criar uma segunda linguagem de
autoria, por outro lado, duplicaria metadados e impediria que o consumidor
visualizasse a mesma factory no Previewer.

O spike AP0 no `examples/sample_flutter` comprovou que uma annotation
especializada pode:

- aparecer no Widget Previewer oficial;
- expandir duas Variants da mesma factory real;
- manter o entrypoint de produção sem import do DevExKit;
- ser montada e capturada por um teste Flutter controlado.

No Flutter 3.44.8, a execução comprovada exigiu o diretório raiz do workspace,
entries explícitas no workspace e `--legacy-preview-detection`. O detector LSP
falhou dentro do Flutter Tool e permanece uma limitação de compatibilidade a ser
acompanhada pelo adapter, não pelo Kernel.

## Decisão

### 1. Duas saídas a partir da mesma autoria

`AutoPreview` e `AutoMultiPreview` especializam, respectivamente, `Preview` e
`MultiPreview`. A annotation possui duas utilizações independentes:

1. o Widget Previewer oficial oferece exploração interativa;
2. o DevEx Preview Compiler descobre os metadados const e produz um
   `PreviewManifest` canônico para um runner controlado.

O DevExKit não chama APIs internas do Previewer e não trata sua interface como
exportador de PNG. O runner de captura é uma implementação separada.

### 2. Boundary de package

`devex_preview` isola a dependência experimental do Flutter. O package depende
somente de Flutter e `devex_contracts`; não depende de `dart:io`, engine ou
runtime. Scanner, filesystem e subprocessos pertencem ao runtime. Normalização
e compilação puras pertencem ao engine.

A compatibilidade inicial é fechada em Flutter `3.44.x`. Cada nova linha do
Flutter requer conformance específica do adapter. Falha de compatibilidade não
altera contracts de catálogo, Evidence ou composição.

### 3. Identidade e modelo

- `id`, `scenarioId` e `variantId` são explícitos e estáveis;
- a função inicial é pública, top-level e retorna `Widget` ou `WidgetBuilder`;
- os argumentos da annotation e de suas Variants são `const`;
- `AutoMultiPreview` expande Variants de um único Scenario;
- estados semânticos como `ready`, `empty` e `failed` são Scenarios distintos,
  não Variants de viewport;
- uma Variant de mesmo ID deve ter definição canônica idêntica em todas as
  fontes;
- a factory anotada reutiliza UI real; uma implementação paralela da página
  não satisfaz o contrato.

AutoPreview referencia Scenarios existentes; descoberta não os cria.

### 4. Descoberta e código efêmero

O runtime usa Analyzer sobre `lib/**/*.dart`, sem `build_runner`, reflexão ou
carregamento arbitrário de Dart. Registry e scaffold são escritos somente em:

```text
.dart_tool/devex/preview/<plan-digest>/
```

O entrypoint de produção não importa arquivos de preview. O architecture guard
verifica essa ausência.

### 5. Captura

O renderer inicial usa um scaffold efêmero de `flutter test`. Para cada
descriptor, ele configura viewport, DPR, locale, brightness e text scale,
monta a factory real sob `RepaintBoundary`, aplica uma política de estabilização
limitada e grava o PNG primeiro em staging autorizado.

A política padrão usa quantidade fixa de frames. Duração fixa é limitada e
`pumpAndSettle` é opt-in com timeout. Uma falha é registrada por item e não
invalida capturas válidas do mesmo lote.

Renderer, toolchain, policy, fixture, source snapshot, assets/fonts e lockfile
participam do `captureKey` ou do fingerprint. Renderers distintos não prometem
igualdade de pixels.

### 6. Evidence e fidelidade

AutoPreview é um provider de Evidence de baixo custo. A execução produz
`PreviewCaptureManifest`, PNGs validados/deduplicados no CAS e report temporal.
O manifest associa explicitamente:

```text
AutoPreview × Scenario × Variant → status × artifact digest
```

O provider `flutter-test` declara fidelidade `structural`. AutoPreview não pode
declarar `hostNative` ou `deviceAttested` e não prova plugins nativos, teclado,
permissões, chrome de sistema, navegação host-native ou integração real com
serviços externos. Uma eventual implementação Chrome controlada poderá, com
fixtures adequadas, declarar no máximo fidelidade `simulated`.

### 7. Composição e Journey Map

`evidence.auto-preview` é Module e EvidenceProvider opcional. Ele requer
catálogo e artifact store, mas não App Adapter, Gateway ou Android. O Journey
Map continua funcional sem screenshot e escolhe imagem somente por binding,
ordem de provider, status, freshness e policy explícitos.

O Studio recebe um artifact handle temporário, nunca o path do CAS. Estados
`missing`, `stale`, `failed` e `policyDenied` permanecem visualmente distintos.

### 8. Segurança

O runner executa código do consumidor em subprocesso, com environment
allowlisted, sem secrets, staging confinado, limites de tempo/saída/artifact e
cleanup obrigatório. Rede é negada quando o host oferecer contenção
comprovável. Persistência de pixels requer policy de dados sintéticos. Path
absoluto, traversal, symlink de escape e PNG inválido falham fechados.

## Alternativas consideradas

### Usar o Widget Previewer como exportador

Rejeitada. O Flutter 3.44.8 não oferece interface pública de exportação e seus
detalhes internos são experimentais.

### Usar apenas golden tests escritos pelo consumidor

Rejeitada como autoria principal. Goldens continuam úteis, mas não fornecem
descoberta canônica, associação `Scenario × Variant`, captura parcial e
manifest de Evidence sem convenções adicionais.

### Exigir App Adapter ou Android

Rejeitada. Aumentaria custo e invalidaria o profile mínimo `journey-preview`.
Esses providers continuam opções de maior fidelidade selecionáveis.

### Adotar `build_runner`

Rejeitada na primeira versão. Analyzer e registry efêmero atendem a descoberta
sem modificar o source tree nem acrescentar geração ao build do consumidor.

## Consequências

- uma única annotation atende exploração interativa e coleta determinística;
- o Flutter experimental fica isolado em um adapter pequeno;
- screenshots do AutoPreview são evidência estrutural, não prova de integração;
- o runner possui custo de isolamento, quotas, lifecycle e conformance próprios;
- alterações do Flutter podem exigir atualização do adapter e do detector;
- consumidores podem combinar AutoPreview, App Adapter e Android por binding,
  sem precedência silenciosa.

## Rollout e rollback

O rollout usa gates AP0–AP4: spike, API/contracts, scanner/compiler,
runner/Evidence e projeção no Journey Map. Até AP3 passar, nenhum resultado é
promovido a Evidence/Release. Rollback desabilita `evidence.auto-preview` e
mantém catálogo, Journey Map e outros providers intactos.

## Evidência requerida

- conformance com `Preview`/`MultiPreview` no Flutter suportado;
- scanner positivo e casos negativos fail-closed;
- duas Variants da mesma factory real;
- captura válida, determinismo semântico e falha parcial;
- isolamento, quotas, timeout e ausência de resíduos;
- CAS, capture key, fingerprint e freshness;
- Journey Map com/sem AutoPreview e sem App Adapter;
- architecture guard assegurando source tree e entrypoint de produção limpos.

Resultados executados serão registrados somente em
`docs/architecture/auto-preview-results.md` após os gates correspondentes.
