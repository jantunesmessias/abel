# Matriz executável E-01…E-20 — paridade web/Android

Esta matriz liga cada critério normativo a uma evidência executável. O gate
composto é `tools/verify/verify_release.sh`; o vertical Android real é
`tools/verify/verify_android_evidence.sh`.

| ID | Evidência principal | Assert observado |
|---|---|---|
| E-01 | `gateway_plan_compiler_test`, `gateway_runtime_test`, `safe_http_upstream_test` | mock, passthrough explicitamente allowlisted e deny desconhecido |
| E-02 | `sidecar_stdio_test`, `workspace_host_test` | processo, token, listener, runtime e traffic isolados por sessão |
| E-03 | `workspace_gateway_plan_compiler_test`, CLI Gateway | preset substitui plano compilado e reset não faz merge implícito |
| E-04 | `gateway_plan_compiler_test`, `contract_probe_executor_test` | route fora de `appliesTo` falha antes do data plane |
| E-05 | `gateway_runtime_test`, `gateway_http_server_test` | verify e API atravessam o mesmo handler e preservam bytes/digest |
| E-06 | `sidecar_stdio_test`, `verify_target_containment.sh` | hybrid só delega decisão explícita; containment é reportado sem exagero |
| E-07 | `remote_config_provider_test` | provider genérico publica somente snapshot completo e válido |
| E-08 | `verify_android_evidence.sh` | APK alcança Gateway por `adb reverse`, UI anuncia ready e cleanup zera recursos |
| E-09 | `gateway_runtime_test`, `gateway_contracts_test` | traffic é ordenado, limitado e sem headers sensíveis |
| E-10 | `session_capture_vault_test`, `app_adapter_capture_bridge_test`, `target_binding_test` | TTL, principal, target, origin, capability one-shot e invalidação limitam captura temporária/direta |
| E-11 | `contract_probe_contracts_test`, `contract_probe_executor_test` | DAG `after`, extração, precedência e filtro de preset no HTTP real |
| E-12 | `review_execution_resolver_test` | digest e grant exatos materializam um binding sem routing livre |
| E-13 | parser/compiler e bundle plataforma local | content root contém documentos; binários entram apenas como artifact digest |
| E-14 | `gateway_runtime_test`, CLI reset | runtime state pertence à GatewaySession e reset recompõe estado conhecido |
| E-15 | `gateway_http_server_test`, `gateway_runtime_test` | latency, timeout/falha e disconnect seguem FaultProfile determinístico |
| E-16 | schemas, fixtures e gates Gateway isolado até Android | extensão atravessa catálogo, compile, handler, verify, docs, probe e testes |
| E-17 | `android_target_provider_test`, `verify_android_evidence.sh` | dry-run/apply/verify/remove idempotentes, ownership e crash recovery |
| E-18 | contratos de overlay, sanitização, CAS e architecture guard | secret-like keys, headers e fixtures não entram em output/artifact |
| E-19 | CLI machine output e `ReviewExecutionResolver` | run/status/preset/verify/traffic/reset/sync/probe e grants usam serviços canônicos |
| E-20 | `architecture_guard.dart` e corpus sintético | boundaries e nomes permanecem neutros, sem host/ID/inventário real |

Ausência de App Adapter continua válida para Documentar. Quando a captura direta
é concedida, o PNG atravessa App Adapter, upload loopback e CAS por handle, sem
binário inline no RPC. `targetEnforced` só é emitido pelo adapter de containment
após os probes reais. Android gerenciado é `hostNative`, nunca
`deviceAttested`.
