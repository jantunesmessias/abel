# Componentes

Mapa físico dos componentes principais. A descrição normativa e os fluxos
detalhados permanecem em [`ARCHITECTURE.md`](../../ARCHITECTURE.md).

| Componente | Localização | Responsabilidade |
|---|---|---|
| Workspace CLI | `apps/workspace_cli` | comandos locais, composição e diagnóstico |
| Workspace Host | `apps/workspace_host` | autoridade local, RPC e ciclo do workspace |
| Studio | `apps/studio` | UI Jaspr e projeções públicas do Host |
| Gateway sidecar | `apps/gateway_sidecar` | tráfego controlado entre Target e backend |
| Hosted control plane | `apps/hosted_control_plane` | tenancy e coordenação hosted |
| Remote session gateway | `apps/remote_session_gateway` | entrada de sessões remotas |
| Remote worker | `apps/remote_worker` | execução remota e cleanup |
| Experience contracts | `libs/experience_contracts` | modelos e codecs públicos fechados |
| Experience engine | `libs/experience_engine` | compilação e transformações determinísticas |
| Execution runtime | `libs/execution_runtime` | execução, evidência e autoridades locais |
| Studio UI | `libs/studio_ui` | componentes visuais reutilizáveis |
| Interaction model | `libs/interaction_model` | estado de interação Dart puro |
| Flutter adapters | `libs/flutter_app_adapter`, `libs/flutter_preview` | integração permitida com consumers Flutter |

Consumers executáveis ficam em `examples/`. Verificações externas e fixtures
vivem em `tests/`, e nenhum dos dois diretórios é uma dependência oculta dos
componentes de produção.
