# ADR-0009 — V1 web/Android: target, probes, bindings e retenção

- Status: aceito
- Data: 2026-08-09
- Decisões afetadas: D-G07, D-G08, Q-13, Q-15, Q-16

## Contexto

V1 precisa elevar o produto de preview local para uma matriz operacional
suportada web/Android, sem enfraquecer os limites estabelecidos em V0–V0.3.
Os riscos centrais são confundir emulador anexado com alvo possuído, instalar
confiança TLS sem undo, permitir que Review invente routing, persistir respostas
de diagnóstico indefinidamente e apagar artifacts ainda alcançáveis.

## Decisão

### Android

O provider aceita somente seriais `emulator-*` observados por ADB. Um alvo é
`managed` apenas quando sua identidade coincide com o estado de lifecycle
criado pelo DevExKit; conhecer o serial ou ter bootstrap anterior não concede
ownership. Install, launch, reset e PNG usam argv direto, sem shell. Launch só
termina quando o processo existe e o componente exato está resumed.

O pareamento é um contrato resolvido por launch: `adb reverse` ou alias do host
do Android Emulator. O domínio da aplicação recebe somente o origin efêmero;
nenhum host de consumidor pertence ao código ou catálogo.

Start persiste AVD, serial e PID antes de esperar boot. Stop atua apenas sobre a
identidade possuída. Se o processo morreu, estado residual só é removido após
provar que o PID não existe. Havendo estado TLS, o mesmo AVD deve ser reiniciado
para executar o undo antes de liberar ownership.

### TLS local

Quando necessário, OpenSSL gera uma CA RSA por workspace com validade de 30
dias e leaf de 7 dias para `localhost`, `127.0.0.1` e `10.0.2.2`. Chaves têm
modo `0600`; apenas a CA pública entra no emulador. A instalação privilegiada é
permitida somente em alvo `managed` e imagem rootable. Imagens Play Store
falham fechadas e não deixam material local se nenhuma cópia remota ocorreu.

O estado registra digest, expiração e o único path remoto autorizado. Falha
após possível cópia preserva recovery state até o undo exato. Verify observa
bytes, validade e arquivo remoto; remove apaga primeiro o certificado e depois
o material privado local.

Q-13 está fechada por teste unitário e execução real de install/verify/remove em
AVD efêmero API 35 `google_apis`.

### Probe e Review

`ContractProbePlan` é um DAG fechado por `after`. Extrações usam JSON Pointer e
precedência explícita: defaults, stable, captured, extracted e manual. Cada
route deve pertencer ao preset e ao `appliesTo` do `CompiledGatewayPlan` antes
de qualquer request. O transporte é direto, sem redirect e com body limitado.

Resposta de probe é efêmera por default. Opt-in CAS exige classificação não
pública; um root temporário de 7 dias evita coleta prematura. Q-15 está fechada
por contratos, execução no data plane real e teste de retenção.

`ReviewGuide` contém narrativa de revisão e referências tipadas. O Host resolve
um `ScenarioExecutionBinding` contra o digest exato do `CatalogManifest` e
materializa target, launch profile ou checkpoint e, opcionalmente, um único
GatewayPreset. Review não recebe API de routing livre.

### Migração e retenção

Migração legada aceita YAML/JSON limitado e um mapping declarativo de JSON
Pointer/literal. Não há avaliação de código nem taxonomia de consumidor. Apply
faz backup CAS, publica o diretório inteiro atomicamente, verifica ownership e
recusa rollback se a saída foi modificada.

Retenção local usa 10 GiB por default, temporários por 7 dias e grace de 24
horas para blobs não alcançáveis. State, migrations ativas e releases são
roots; releases permanecem pinadas. Sweep é uma transação move-to-trash com
recovery. Se conteúdo alcançável exceder a quota, o report declara quota não
atendida em vez de apagar evidência. Q-16 está fechada por corpus simulado de
30 dias e recovery de transação interrompida.

## Consequências

- A claim V1 é somente `web/Android`; Q-14/iOS permanece pós-V5.
- O gate Android precisa de Linux x86_64, KVM, imagem rootable pinada e ao menos
  8 GiB no parent efêmero do AVD.
- A distribuição pode avançar para `stable` somente após o gate composto V1.
- Capturas Android continuam `hostNative`; emulador nunca é `deviceAttested`.
- Evidência nativa além de PNG pertence a V3.
