# Operação do startup modular

Status: runbook ativo MC2–MC6.

## Pipeline canônico

```text
Distribution/ModuleCatalog
          + consumer config/local/startup overlays
          -> WorkspaceConfigurationLoader
          -> KitPlanResolver
          -> ResolvedKitPlan + digest
          -> staging .dart_tool/devex/run/<run-id>/resolved-kit-plan.json
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
devex modules list --profile journey-preview
devex modules explain --profile journey-preview --module evidence.auto-preview
devex modules doctor --profile journey-preview
devex dev --profile journey-preview
```

Durante execução, o Host oferece `devex.kit.describe` e
`devex.kit.health`. O manifest efetivo também é persistido em
`.dart_tool/devex/effective-kit.json` para diagnóstico local. Settings e
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

## Migração de configuração

```bash
devex config migrate --to 2 --dry-run
devex config migrate --to 2 --apply
```

O preview é puro. `--apply` usa troca atômica e preserva
`devex.yaml.v1.bak`. Leitura v1 continua disponível por
`legacy-full-local-v1`; migração não é condição para rollback de Distribution.
