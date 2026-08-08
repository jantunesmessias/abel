# ADR-0003: Contratos local e hosted

- Status: aceita
- Data: 2026-08-09
- Decisoes afetadas: D-011, D-012, D-021, D-032

## Decisao

- JSON-RPC 2.0 e o control plane local e hosted.
- Studio e Host local usam WebSocket loopback autenticado.
- Host e filhos parent-owned usam stdio.
- CLI one-shot chama os mesmos handlers in-process; attach usa Host RPC.
- Hosted usa WSS para commands/eventos e HTTPS para handles de artifacts.
- Protocolos negociam versao/capabilities e exigem operation ID, idempotencia,
  deadline/cancelamento e exatamente um terminal result.
- Blobs nunca trafegam inline acima do limite negociado.

## Consequencias

Transportes nao reinterpretam dominio. Reconnect usa cursor e snapshot; comando
mutavel nao e repetido sem contrato de idempotencia.
