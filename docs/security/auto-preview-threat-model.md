# Threat model — AutoPreview v1

Status: ativo para `evidence.auto-preview` / renderer `flutter-test`.

## Boundary e premissa

Uma preview executa código Dart/Flutter do consumidor. Mesmo sendo autoria do
workspace, esse código é tratado como não confiável pelo Host. Scanner e
compiler leem source; o runner inicia um subprocesso Flutter e ingere somente
o protocolo/PNG esperados.

```text
workspace source -> Analyzer/compiler -> registry/scaffold efêmero
                                     -> flutter test subprocess
                                     -> protocolo limitado -> PNG inspector
                                     -> CAS + manifest/report
```

Assets protegidos: secrets e environment do usuário, filesystem fora do
workspace/staging, integridade do CAS/manifests, disponibilidade do Host e
privacidade dos pixels.

## Threat register

| ID | Threat | Controle v1 | Risco residual |
|----|--------|-------------|----------------|
| AP-T01 | source/path escapa por traversal ou symlink | raiz canônica, `lib` confinado, links proibidos, registry/staging confinado | TOCTOU do filesystem local hostil |
| AP-T02 | preview lê secrets do processo pai | environment allowlisted; nenhum secret configurado pelo Abel | código pode ler credenciais já acessíveis ao mesmo usuário por outros meios |
| AP-T03 | loop/animação causa DoS | policy e processo com timeout; lote serial; limites de frames/duração | subprocesso pode consumir CPU/memória até o limite do SO |
| AP-T04 | stdout/stderr ou PNG exaure disco/memória | budgets de diagnóstico/artifact, truncation e PNG inspector | quota forte de memória depende do sandbox do host |
| AP-T05 | protocolo forjado ou path arbitrário | token imprevisível por scaffold, chaves allowlisted e paths precomputados | código no mesmo subprocesso pode observar a fonte gerada |
| AP-T06 | PNG malformado contamina CAS | regular-file check, parser PNG, dimensões/digest antes do CAS | decoder Flutter continua parte da TCB |
| AP-T07 | pixels reais/sensíveis persistem | confirmação explícita `syntheticDataConfirmed`; policy denied por item | declaração sintética é responsabilidade do operador |
| AP-T08 | rede exfiltra dados | nenhum credential/network target é fornecido; contenção deny-default quando disponível | `flutter test` local não garante sandbox de rede portátil |
| AP-T09 | falha deixa processos ou staging | subprocess kill/timeout e cleanup `finally` por descriptor | crash/kill -9 do processo supervisor requer coleta posterior de `.dart_tool` |
| AP-T10 | resultado recebe fidelidade indevida | provider fixa `structural`; fingerprint registra renderer/toolchain | UI estrutural ainda pode divergir do runtime real |

## Regras fail-closed

- source link, path absoluto inesperado, digest divergente e PNG inválido são
  recusados;
- output truncado não é interpretado parcialmente como sucesso;
- item não coletado não contém artifact;
- erro de um preview não autoriza reutilizar pixels de outro;
- o Studio recebe handle HTTP(S) temporário, nunca path local do CAS;
- rede negada só pode ser declarada quando houver containment observado.

## Operação segura

Execute previews apenas em workspace confiável, sem secrets no código/fixtures,
com dados sintéticos e limites adequados. Em CI multi-tenant, envolva o runner
em sandbox de processo/filesystem/rede do executor; a allowlist de environment
isoladamente não equivale a sandbox.

Upgrade de Flutter, Analyzer, parser PNG ou política de contenção requer revisão
deste model e reexecução da conformance.
