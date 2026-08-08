# ADR-0002: Plataformas suportadas ate remote execution

- Status: aceita
- Data: 2026-08-09
- Decisoes afetadas: D-G08, Q-14, gate 27.2

## Contexto

O plano de implementacao escolheu web e Android, sem infraestrutura macOS/iOS.
A arquitetura anterior incluia iOS Simulator no significado amplo de web/Android.

## Decisao

- web/Android significa paridade operacional na matriz Flutter web e Android emulator.
- source automation-remote execution preservam essa matriz; o farm remoto oferece web e Android emulator.
- iOS e dispositivos Android fisicos permanecem fora do escopo ate nova ADR.
- Nenhuma release afirma paridade iOS ou substituicao multiplataforma.

## Consequencias

Q-14 continua adiada. Evidencia e machine output declaram a matriz efetiva. O
gate de substituicao so pode ser afirmado como `web/Android`.
