# Operação do startup modular

Status: runbook ativo configuração e resolver modular–composição do Studio.

## Pipeline canônico

```text
Distribution/ModuleCatalog
          + consumer config/local/startup overlays
          -> WorkspaceConfigurationLoader
          -> KitPlanResolver
          -> ResolvedKitPlan + digest
          -> staging .dart_tool/workspace/run/<run-id>/resolved-kit-plan.json
          -> CLI/Host
          -> ModuleLifecycleCoordinator
          -> EffectiveKitManifest
          -> Host RPC/Studio composition
```

Precedência: Kernel < Distribution < Profile < Workspace < local < startup.
Toda validação ocorre antes de effects. O arquivo transportado usa JCS, tamanho
limitado, path explícito e digest fora de banda. O Host rejeita symlink, plano
de outro catálogo ou digest divergente.

## Inspeção

```bash
workspace modules list --profile journey-preview
workspace modules explain --profile journey-preview --module evidence.auto-preview
workspace modules doctor --profile journey-preview
workspace dev --profile journey-preview
```

Durante execução, o Host oferece `composition.describe` e
`composition.health`. O manifest efetivo também é persistido em
`.dart_tool/workspace/effective-kit.json` para diagnóstico local. Settings e
diagnósticos nunca devem conter secret literal.

## Lifecycle

Modules são preparados/iniciados em `dependencyOrder`. Cada factory recebe
somente settings imutáveis, capabilities declaradas, cancellation token,
resource owner e health reporter.

Em falha:

1. o Module ativo vira `failed` com diagnóstico limitado;
2. `stop`, `dispose` e cleanups registrados são tentados;
3. Modules já prontos são desfeitos em ordem inversa;
4. Modules ainda não iniciados recebem `dependencyMissing`;
5. nenhuma capability do startup incompleto permanece exportada.

No shutdown, cancelamento é sinalizado e a mesma ordem inversa é usada.
Cleanup é best-effort e falhas aparecem em health; não são ocultadas.

## Diagnóstico por sintoma

| Sintoma | Verificação |
|---------|-------------|
| comando ausente | confirmar Module/surface no `modules explain`; ausência pode ser intencional |
| `notPackaged` | profile/config pede Module fora da Distribution; instalar bundle compatível |
| `dependencyMissing` | revisar capability requirement e provider binding |
| `policyDenied` | revisar startup policy, platform e confirmação de dados |
| Host rejeita plano | conferir os dois digests e o catálogo empacotado; não editar staging |
| rota Studio ausente | verificar contribution no EffectiveKitManifest; Grant não habilita Module |
| processo/listener residual | coletar health/logs e tratar como falha de conformance/lifecycle |

## Configuração canônica

O arquivo principal `workspace.yaml` exige `schemaVersion: 2` e uma seleção
`kit` explícita. Uma revisão anterior ao contrato publicado é recusada antes
do plano e do lifecycle. Rollback de Distribution continua independente do
arquivo autoral do consumer.
