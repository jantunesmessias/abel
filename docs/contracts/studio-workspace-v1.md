# Studio workspace v1

Status: contrato ativo e exercitado em Host/Studio no SR0–SR9. Decisão:
ADR-0014.

## Escopo

Este contrato define o read model autoritativo que o Host entrega ao DevEx
Studio. Ele agrega domínio existente sem criar outro bounded context: catálogo,
Variants, composição modular e Evidence continuam pertencendo aos seus modelos
canônicos.

O Studio consome documentos tipados e `ResourceHandle`. Ele não recebe paths do
workspace, staging ou CAS, não compila catálogo e não escolhe capabilities que
o `ResolvedKitPlan` desabilitou.

Os documentos externos conformam
`schemas/v1/studio-workspace.schema.json`; o catálogo agregado conforma também
`schemas/v1/catalog-manifest.schema.json`.

## Documentos

| Documento | Responsabilidade |
|-----------|------------------|
| `CatalogManifest` | catálogo compilado, validado e referencialmente íntegro |
| `VariantManifest` | Variants canônicas e a fonte explícita de cada definição |
| `VisualEvidenceProviderState` | health, fidelities suportadas e capacidade de coleta |
| `ProviderBinding` | seleção explícita e ordenada dos providers de uma capability |
| `VisualEvidenceProjection` | vínculo `Scenario × Variant × Provider` ou Evidence explicitamente unbound |
| `ResourceHandle` | capability HTTP scoped/TTL para snapshot ou artifact |
| `WorkspaceSnapshot` | revisão canônica que agrega os documentos publicados ao Studio |

Todos os documentos raiz têm versão/kind, digest semântico, ordem canônica e
decoder estrito. Campos desconhecidos, digest divergente, versão adjacente,
referência ausente e lista acima do limite falham fechados.

## Catálogo

`CatalogManifest.fromJson` decodifica todos os tipos públicos do catálogo. O
decoder valida:

- `Application → Workspace`;
- `Journey → Application` e todos os Scenarios ordenados;
- `Scenario → Application` e source references;
- `Transition → Journey` e Scenarios pertencentes à mesma Journey;
- `ScenarioExecutionBinding → Scenario`;
- `ReviewGuide`, steps e bindings na mesma Application.

Identidade, ordem ou nome visual não autorizam corrigir uma referência inválida.

## Variants

`VariantManifest` liga cada `VariantId` a pelo menos uma
`VariantDefinitionSource`, identificada por `sourceId` e `sourceDigest`. O
manifest carrega o digest do catálogo para impedir composição acidental entre
revisões diferentes.

Uma `Variant` pertence a uma Application do catálogo. Estados semânticos como
`ready`, `empty`, `failed` e `authenticated` continuam Scenarios; não viram
Variants apenas para produzir imagens diferentes.

## Projeção visual

Uma projeção bound possui `scenarioId`, `variantId` e `providerId`. Status
fechados:

```text
unbound | collected | missing | failed | unsupported | policyDenied
```

Somente `collected` expõe conjuntamente artifact, fidelity, instante observado
e handle do PNG. `executionFingerprintDigest`, `capturePolicyId` e `captureKey`
preservam a proveniência operacional sem copiar o documento Evidence para o
read model. Freshness é `fresh` ou `stale`; status de falha nunca seleciona
pixels de outro provider. Evidence histórica sem associação demonstrável usa
`unbound`, mesmo quando o artifact ainda existe.

O provider `evidence.auto-preview` suporta apenas
`RuntimeFidelity.structural`. Decoder, schema e construtor rejeitam qualquer
elevação para `simulated`, `hostNative` ou `deviceAttested`.

## ResourceHandle

`ResourceHandle` contém URL HTTP(S) com identificador opaco sob
`/resources/{capability}`, digest, media type, tamanho, purpose e expiração UTC.
O wire não contém path local, query token, fragment ou user info. O contrato
limita o documento a 64 MiB; a autorização efetiva de audience, Origin,
classificação, use count e revogação pertence ao Host e ao protocolo.

O handle é transporte temporário, não identidade persistente de Evidence. O
Studio reabre o snapshot quando o handle expira.

## WorkspaceSnapshot

O snapshot possui revisão monotônica positiva e agrega exatamente um catálogo,
um manifest de Variants, um `EffectiveKitManifest`, os `ProviderBinding`
resolvidos, providers, projeções e diagnósticos. O construtor valida:

- `VariantManifest.catalogDigest == CatalogManifest.digest`;
- cada Variant pertence a uma Application conhecida;
- cada provider existe no `EffectiveKitManifest`;
- cada binding visual referencia providers disponíveis e, quando scoped, uma
  Application conhecida;
- cada projeção usa provider declarado;
- Scenario e Variant da projeção pertencem à mesma Application.

A revisão é usada para ordenação de updates; o digest é usado para identidade
do conteúdo. Nenhum dos dois substitui validação do documento recebido.

## Limites e segurança

Arrays públicos têm limites explícitos antes da construção de domínio. Strings,
IDs, diagnósticos, URLs e media types também são bounded. Digests são
recalculados após o parse e documentos são profundamente imutáveis.

Essas garantias não transformam o Studio em trust boundary de filesystem. O
Host continua responsável por capabilities imprevisíveis, TTL, Origin, digest
do blob, content type, quotas, revogação e ausência de symlink/traversal.

## Compatibilidade

Mudança incompatível exige schema/reader adjacente. Adicionar status, mudar
semântica de binding, elevar fidelity ou permitir novo formato de resource não
pode ser feito silenciosamente em v1. O protocolo que publica estes documentos
é versionado separadamente em `docs/protocol/studio-host-v1.md`.
