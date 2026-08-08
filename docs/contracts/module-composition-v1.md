# Module composition v1

Status: contrato e runtime ativos MC1–MC6. Decisão: ADR-0012.

## Escopo

Este contrato define composição built-in confiável. Não substitui
`PluginManifest`, não altera `CapabilityDescriptor` de ExecutionTarget e não
cria bounded context. Os documentos externos conformam a
`schemas/v1/kit-composition.schema.json` e usam JSON canônico/digest DevExKit.

## Documentos

| Documento | Responsabilidade |
|-----------|------------------|
| `ModuleDescriptor` | capabilities, requirements, platforms, surfaces, efeitos e recursos |
| `KitProfile` | overlay declarativo de Modules e provider bindings |
| `ModuleCatalog` | Modules/profiles empacotados por Distribution/platform |
| `ResolvedKitPlan` | plano anterior a efeitos, com ordem de startup |
| `EffectiveKitManifest` | estado/health e superfícies observadas após startup |

Value objects aninhados são `ModuleCapabilityRef`, `ModuleRequirement`,
`KitModuleSelection`, `KitSelection`, `ProviderBinding`, `ResolvedModule`,
`ModuleDiagnostic` e `EffectiveModuleState`.

## Identidade e compatibilidade

- Module/Profile/Capability usam opaque ID público;
- Module usa SemVer exata e caret compatibility com core;
- capability possui versão inteira positiva própria;
- platform é explícita; `any` é o único wildcard v1;
- digest cobre o documento sem o próprio campo `digest`;
- listas semanticamente não ordenadas são normalizadas antes do digest;
- `dependencyOrder` é deliberadamente ordenada e cobre cada Module habilitado
  exatamente uma vez.

Unknown field, versão/kind incorretos, digest divergente, referência de profile
a Module não empacotado, provider desabilitado ou health incompatível falham
fechados.

## Resolução

`ModuleDescriptor.requires` e `optionalRequires` referenciam capabilities, não
implementações. `ProviderBinding` seleciona uma lista ordenada de Module IDs
para uma capability global ou por Application. Policies v1:

- `orderedFirstAvailable`: respeita a ordem autoral e escolhe o primeiro
  provider elegível/ready;
- `all`: todos os providers selecionados participam da capability composta.

Provider Module precisa estar explicitamente habilitado. O resolver não ativa
Module resource-bearing para reparar dependência ausente.

## Estados

```text
disabled | notPackaged | unsupported | dependencyMissing | policyDenied
starting | ready | degraded | failed | stopping | stopped
```

Health é ortogonal, porém coerente com lifecycle:

- `ready`: `healthy` ou `degraded`;
- `degraded`: `degraded`;
- `failed`: `unhealthy`;
- `starting`/`stopping`: `unknown`;
- estados inativos: `notApplicable`.

Somente `ready`/`degraded` expõem effective capabilities.

## Segurança e mutabilidade

Settings são JSON profundamente copiado e imutável. Validação semântica do
settings usa o schema built-in referenciado pelo descriptor na fase MC2.
`configurationSchema` é identidade absoluta; não autoriza download ou `$ref`
remoto. Diagnósticos têm código opaco, severity fechada e mensagem limitada;
boundaries de aplicação continuam responsáveis por sanitização.

## Contributions do Studio

`EffectiveKitManifest.studioContributions` é a única fonte para navegação e
rotas do Studio Jaspr:

| Module | Contribution |
|---|---|
| `studio.shell` | `studio.shell` |
| `studio.journey-map` | `studio.journey-map` |
| `sessions.local` | `studio.target` |
| `gateway.interceptor` | `studio.gateway` |
| `remote.execution` | `studio.remote-session` |
| `hosted.collaboration` | `studio.hosted` |

`ReviewGuide` é conteúdo do `CatalogManifest`, não Module/contribution novo.
Grant não habilita contribution ausente. `studio.target` e `studio.gateway`
também não tornam Session ou Gateway executáveis sem seus RPCs efetivos.

## Compatibilidade

Novos documentos começam em schemaVersion 1. Consumer config e Distribution
mudam para v2 por serem contratos existentes incompatíveis. Readers v1 não são
alterados. Antes de 1.0, qualquer mudança incompatível neste wire ainda exige
schema adjacente, migration e conformance.
