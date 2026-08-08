# Resultado executado do GATEWAY CONTAINMENT Gateway hybrid e containment

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64.

## Vertical fechado

O fluxo exercitado e:

```text
GatewayRoute upstreamOnly + UpstreamProfileId
  -> workspace.local.yaml ignorado + credential handle
  -> sidecar hybrid -> DNS validado/pinado -> upstream allowlisted
  -> API e verify pelo mesmo UpstreamHandlerPort
  -> TrafficEvent sanitizado

RemoteConfigProvider -> assessment -> normalizacao JCS/CAS -> troca atomica

Chromium/target sem rota em netns
  -> frontend Gateway loopback -> stdio herdado -> broker/upstream externo
  -> direct egress probe negado -> TargetContainmentReport targetEnforced
```

Entregas verificadas:

- passthrough somente em plan `hybrid`, route ativa e profile explicito;
- unknown route e profile ausente negam sem tentativa de rede;
- allowlist exata, resposta DNS integralmente validada e conexao IP-pinned;
- redirect, proxy, encoding, headers perigosos e body maior que 1 MiB negados;
- `gateway doctor` reporta somente booleans/IDs; `gateway sync` nao imprime o
  documento nem a credencial;
- estados `missing`, `empty`, `incomplete`, `invalid` e `ready`, com preservacao
  transacional do ultimo digest ativo;
- captura em memoria com TTL, principal/target/generation, allowlist de hints,
  invalidacao e resolver `session:authorization` exercitado por request real;
- sidecar hybrid real, API/verify, deny desconhecido e traffic sanitizado;
- contrato/schema `TargetContainmentReport` impede claim sem os dois probes.

## Containment web de referencia

Execute:

```bash
./tools/verify/verify_target_containment.sh
```

Resultado observado em 2026-08-09:

```json
{"adapterId":"linux-netns-stdio-gateway-v1","networkContainment":"targetEnforced","platform":"web","probes":[{"detailCode":"allowlisted_passthrough_204","kind":"gatewayReachable","passed":true},{"detailCode":"no_default_route","kind":"directEgressDenied","passed":true}],"targetId":"chromium-linux-netns"}
```

O report completo inclui UTC e digest JCS, portanto muda a cada execucao. O
probe nao infere containment a partir de config: Chromium realmente alcanca o
upstream apenas pela fronteira Gateway e falha ao tentar egress direto para um
endereco de documentacao. Ambiente sem user/network namespace, `ip` ou Chromium
falha o gate; execucao local comum continua declarando somente `gatewayOnly`.

## Resolucao de Q-08, Q-09 e Q-10

- Q-08: provider inicial generico, orientado a contrato e sem vendor no engine.
- Q-09: `targetEnforced` exige report executado fora do Gateway com sucesso de
  passthrough e negacao de bypass direto.
- Q-10: sessao capturada nao possui storage/crypto persistente: memoria do
  processo, TTL maximo 30 minutos, binding contextual, restart invalida e
  credenciais duraveis ficam no mecanismo do sistema referenciado por handle.

O resultado nao faz claim de integracao Android, host-native, TLS local,
substituicao operacional do gateway legado nem suporte iOS; esses gates
continuam em web/Android ou depois de remote execution, conforme o registro arquitetural.
