# Sample API

API local da aplicação genérica Delivery Lab. Usa Shelf e `shelf_router`, sem
code generation, banco ou credenciais. A escolha reduz o custo operacional do
showcase e mantém a fronteira HTTP independente do framework; substituir Shelf
por Dart Frog não mudaria GatewayScope, routes ou o cliente Flutter.

```bash
dart run examples/sample_api/bin/server.dart --port 8181
curl http://127.0.0.1:8181/health
curl http://127.0.0.1:8181/v1/dashboard
```

Endpoints:

| Método | Path | Uso |
|---|---|---|
| GET | `/health` | readiness local |
| GET | `/v1/dashboard` | snapshot agregado consumido pelo Flutter |
| GET | `/v1/projects` | lista de projetos |
| GET | `/v1/projects/:id` | detalhe |
| POST | `/v1/projects/:id/tasks/:taskId/toggle` | mutação observável |
| POST | `/v1/reset` | restaura seed determinístico |
| GET | `/v1/runtime/configuration` | compara upstream e fixture |
| GET | `/v1/failure` | erro recuperável intencional |

O listener aceita somente endereço loopback por CLI. CORS reflete apenas
origens HTTP(S) loopback; respostas externas recebem `403`. Estado é em memória
e é descartado ao encerrar o processo.
