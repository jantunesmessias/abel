# Module conformance v1

Status: suite ativa MC1–MC6.

## Objetivo

Comprovar que disponibilidade física, habilitação, autorização e estado
operacional permanecem dimensões distintas, e que um único `ResolvedKitPlan`
governa CLI, Host, Studio, providers e Distribution.

## Matriz obrigatória

| Área | Propriedade observável |
|------|------------------------|
| Contracts | round-trip fechado, digest JCS, ordem estável e versões adjacentes |
| Resolver | missing/multiple provider, cycle, conflict, platform, settings, precedence e ordem topológica |
| Segurança | traversal, symlink, secret literal, digest divergente e Module não empacotado falham antes de efeitos |
| Lifecycle | prepare/start/stop/dispose, cancel, rollback reverso, cleanup idempotente e health coerente |
| Ausência | Module desabilitado registra zero comando, RPC, rota, processo, listener, porta, probe ou acesso device/network |
| Transporte | Host valida path, tamanho, digest, catálogo e JCS do plano transportado |
| Superfícies | CLI help/dispatch, Host RPC e Studio routes derivam do mesmo plan/manifest digest |
| Profiles | profiles canônicos e combinações pairwise preservam dependências/bindings |
| Distribution | v1 legível; v2 full/slim verificável, reproduzível, instalável, atualizável e rollbackável |

## Profiles canônicos

| Profile | Prova principal |
|---------|-----------------|
| `journey-preview` | Journey Map + AutoPreview; sem Sessions, Gateway ou Android |
| `journey-android` | Journey Map + target/evidence Android; sem AutoPreview implícito |
| `gateway-lab` | Sessions + Gateway + Studio shell |
| `gateway-lab-headless` | Sessions + Gateway sem component Studio |
| `full-local` | superfície completa empacotada |
| `legacy-full-local-v1` | tradução de consumer config v1 pelo mesmo resolver |

`gateway-lab-headless` é a variante de distribuição sem UI; `gateway-lab`
preserva a experiência interativa original.

## Invariantes de ausência

Para um Module desabilitado, não basta retornar erro quando invocado. Sua
superfície não existe: help e parser não registram o comando; Host não publica
o RPC; Studio não registra route; nenhum owner inicia processo, listener,
device ou rede. Grant não altera essa disponibilidade.

Os únicos RPCs universais do Host são o kernel de inspeção:

```text
devex.kit.describe
devex.kit.health
```

## Gates executáveis

```bash
./tool/check.sh
./tool/verify_modular_distribution.sh
./tool/verify_v03_distribution.sh
```

As suites focadas vivem nos testes de contracts, engine, runtime, CLI, Host e
Studio. Falha de qualquer invariant acima bloqueia promoção de composição ou
de um novo profile.

## Entrada de um novo Module

Um Module só entra no catálogo quando possui:

1. ID, capability/version, surfaces, effects e resources explícitos;
2. factory compile-time e settings schema quando aplicável;
3. requirements e provider bindings sem dependência implícita;
4. testes enabled/disabled, failure/cleanup e pelo menos um profile/pairwise;
5. ownership em Distribution components/files;
6. operação, segurança e documentação atualizadas.
