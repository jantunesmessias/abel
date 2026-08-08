# Resultado executado do V1 web/Android

Data: 2026-08-09. Baseline: Flutter 3.44.8, Dart 3.12.2, Linux x86_64.

## Android Target Provider e App Adapter

Commands entregues:

```text
devex target android discover
devex target android start|managed-status|stop
devex target android bootstrap|update|remove|verify
devex target android install|launch|reset|capture
devex target android tls-install|tls-verify|tls-remove
```

O provider rejeita dispositivo físico e shell, distingue `attached` de
`managed` pelo lifecycle persistido, valida boot/identidade e só encerra alvo
possuído. Estado residual de processo morto possui recovery seguro; estado TLS
impede abandono do AVD antes do undo.

O sample Android usa package `dev.devexkit.sample_flutter`. Somente o
entrypoint de tooling importa `devex_flutter`; o plugin nativo lê extras
`DEVEX_*` limitados e rejeita nomes secret-like. O build de produção continua
na factory neutra do consumidor.

Execução real de `tool/verify_v1_android.sh`:

- imagem efêmera `system-images;android-35;google_apis;x86_64`;
- AVD, userdata e nome criados em tmpfs e removidos pelo gate;
- `adb reverse` host `45901` → target `55901`;
- Activity exata resumed e `Semantics.identifier=devex.gateway.health`;
- UI observada: `Gateway: ready:android-ok`;
- APK tooling:
  `sha256:27e3217f6cac00140e78b42583fda0ddff8dcd1a2ec842a79d97025817e1314f`;
- captura PNG no CAS:
  `sha256:7b5c26eae8aaef59812096c083cb6c9c54fd442d803d6c8799a684276d670ff8`;
- summary do run `179843`:
  `sha256:18697957c9e9b2141b0333e5e88206045e56c1bf511cebddd83d3da2edb8b177`;
- reset confirmou ausência do processo do package;
- stop confirmou ausência de device, processo, porta, state e AVD temporário.

Uma imagem Play Store foi exercitada negativamente: a escrita do trust store
falhou por permissão e não deixou CA, chave ou state local. Na imagem rootable,
install/verify/remove da CA passou, com digest e path remoto exatos; o path não
existia após o undo.

## ContractProbePlan e Review binding

`ContractProbePlan` suporta `after`, JSON Pointer com candidatos, body/query/path
templates e precedência de parâmetros. O executor usa o data plane HTTP real,
nega redirect, limita body e rejeita route fora do preset antes da rede.
Artifacts são efêmeros por default; CAS exige classificação e recebe root
temporário expirável.

`ScenarioExecutionBinding` e `ReviewGuide` entraram no manifest canônico. O
resolver confere digest, step, grant, scenario/application e produz uma
materialização imutável com target, launch profile/checkpoint e preset exatos.

## Migração e retenção

Commands entregues:

```text
devex migrate legacy|verify|rollback
devex retention status|gc
```

Migração é declarativa, limitada, com backup CAS, output atômico, marker de
ownership, verify e rollback recuperável. O backup ativo permanece root de
retention. Testes cobrem modificação pós-migração e recusa de overwrite.

Retention foi executada sobre corpus temporal de 30 dias: temporários de 7
dias expiram, blobs recebem grace de 24 horas, releases e state são roots, quota
default é 10 GiB e transação interrompida é restaurada antes do próximo sweep.

## App Adapter capture e acessibilidade do Studio

O caminho direto Studio/Host → App Adapter web → PNG → upload loopback → CAS
foi executado com origin, session, nonce, sequence, capability URL one-shot,
TTL, limite de 32 MiB e validação estrutural do PNG. Replay, origin incorreta,
sessão cruzada, expiração e payload inválido falham fechados; o token não entra
em evento, status ou CAS. Vinte ciclos de lifecycle terminaram sem handles
pendentes.

O Studio foi auditado em Chromium 151/Wayland com Orca 50.2, AT-SPI2 2.60.6 e
Speech Dispatcher/eSpeak NG. Navegação de teclado e anúncios reais cobriram
Explore, Journey, Structure e Scenario; zoom do browser até 200% não gerou
overflow horizontal global; light/dark, reduced motion e contraste foram
verificados. A locale exposta foi corrigida para `pt_BR`. O driver CDP
reproduzível está em `tool/studio_accessibility_driver.dart`; ele complementa,
mas não substitui, o teste manual com leitor de tela.

## Gate e limites

A correspondência E-01…E-20 está em `docs/quality/e01-e20-v1.md`. O gate local
composto também reconstrói distribuição `0.1.0`, executa conformance externa e
compara alias/canônico.

Execução integral final de `tool/verify_v1_release.sh`:

- web capture: PNG `sha256:3192449ecadf9bed9dbd1dac908a82eb2f640929a2340764d6cd08b4b6439c91`;
- distribution manifest canônico:
  `sha256:dc662892982f2ff48bb03cee8a7486a2813bca0a1e92050a68c0cde5191cd0e1`;
- arquivo `distribution.json` final:
  `sha256:8d08483af17c3f410b6ca7c034478f1b2819808a4b4246175bd414ca1b623657`;
- consumidor externo: analyze e testes públicos aprovados;
- cleanup final: nenhum device ADB, listener, AVD tmpfs ou processo gerenciado
  residual.

V1 afirma somente web/Android. Não afirma iOS, dispositivo físico, assinatura
de package/OCI, evidence Android ampliada, hosted ou device farm. Q-13, Q-15 e
Q-16 estão fechadas; Q-14 continua formalmente pós-V5.
