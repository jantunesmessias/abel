# ADR-0001: Toolchain e dependencias de fundacao

- Status: aceita
- Data: 2026-08-09
- Decisoes afetadas: baseline P0, Q-01, Q-05

## Decisao

- O workspace usa Flutter 3.44.8 e Dart 3.12.2. Mudancas de baseline sao
  isoladas, revisadas e acompanhadas de lockfile.
- Pub Workspace fornece uma unica resolucao para apps, packages, examples e
  consumidores de conformance.
- `devex_contracts` encapsula `json_schema`; o perfil externo e documentado e
  falha fechado para recursos nao conformes.
- JCS e identidade por SHA-256 pertencem a `devex_contracts`.
- `shelf`, `shelf_web_socket` e `web_socket_channel` implementam os transportes
  locais; nenhum desses tipos vaza para o engine.
- O Studio usa Jaspr 0.23.3 client-side; Flutter 3.44.8 permanece pinado para
  adapters e consumers. Mudanças de qualquer baseline são isoladas e
  acompanhadas de lockfile.
- O Journey Map usa DOM/CSS Jaspr, windowing bounded e LOD. O Outline HTML é o
  modelo acessível completo. Esta regra substitui o mecanismo Flutter histórico
  de Q-05 sem alterar a identidade Scenario/Transition.

## Consequencias

`pubspec.lock`, testes contra corpora oficiais e o benchmark profile fazem
parte do gate. Dependencias geradas ou frameworks de estado nao se tornam API
publica de dominio.
