# Abel Architecture

| Campo | Valor |
|-------|-------|
| Status | **plataforma local, Gateway, distribuição, Studio Jaspr e capacidades de experiência aprovados na matriz portátil; control plane e execução remota implementados com certificações externas explicitamente pendentes** |
| Última atualização | 2026-08-17 |
| Stack alvo | **Dart / Jaspr para o Studio / Flutter para adapters e consumers** |
| Estado do projeto | **Studio Jaspr, Host e AutoPreview operacionais localmente; integrações hosted/device-farm aguardam certificação em infraestrutura real** |

Este documento é a **constituição arquitetural e o índice normativo** do
Abel. Ele contém o produto alvo, o baseline comportamental do gateway
seletivo legado, os limites dos bounded contexts, decisões aceitas,
alternativas rejeitadas, critérios de paridade e regras de distribuição.

A fonte de verdade é um conjunto versionado, não a suposição de que todo
conhecimento permanecerá para sempre em um único arquivo:

1. decisões aceitas e ainda vigentes neste registro ou em ADR referenciado;
2. este documento e seu registro de contratos normativos;
3. schemas, protocolos e policies executáveis por ele governados;
4. conformance tests que provam esses contratos;
5. implementação.

Um nível inferior que contradiz um superior está incorreto. ADR, schema ou
protocolo só se torna normativo quando este arquivo registra seu ownership,
versão e relação de precedência. Enquanto um contrato não for extraído, a seção
correspondente deste arquivo permanece suficiente e normativa.

O comportamento relevante do legado foi traduzido para contratos Dart puros,
runtime Dart VM, Studio Jaspr e adapters Flutter isolados.
A stack web PHP anterior (framework, templates, CLI, reverse proxy local e
suite de testes) é apenas detalhe da implementação substituída e não faz
parte do runtime alvo.

Somente capacidades ligadas a evidência no registro §27.4 são implementadas; o
restante continua alvo ou plano. Os termos têm quatro graus de
compromisso:

- **decisão**: restrição aceita para orientar a implementação;
- **proposta**: desenho preferido que precisa ser provado por um vertical;
- **experimento**: spike descartável que responde uma questão e não vira
  produção por inércia;
- **adiado**: compatibilidade preservada, mas fora da fase indicada.

`DEVE`, `NÃO DEVE`, `DEVERIA`, `PODE` e equivalentes em tabelas expressam força
normativa. Exemplos, nomes de biblioteca e pseudocódigo são informativos, salvo
quando uma decisão os torna parte explícita de um contrato.

## Mapa de leitura

- §§1–4: produto, escopo, princípios e experiência;
- §§5–10: sistema, modelo, Studio, execution runtime e Gateway;
- §§11–16: backend, evidência, release, adoção, componentes e automação;
- §§17–21: segurança, roadmap, cobertura do gateway legado, qualidade e verificação;
- §§22–27: operação, decisões, riscos, questões abertas, glossário e governança;
- §28: standards e referências oficiais que fundamentam decisões revisáveis.

---

## 1. Resumo executivo

O Abel é uma plataforma local-first de desenvolvimento mobile para transformar
jornadas de produto em experiências:

- compreensíveis por Product, UX, engenharia e QA;
- executáveis com o app real;
- controláveis por capabilities declaradas;
- conectadas à implementação e ao backend;
- verificáveis por evidências com proveniência;
- compartilháveis como releases imutáveis.

Ele mantém três dimensões relacionadas:

```text
Intenção                    Implementação                 Evidência
Product e UX       <->      App e backend        <->      Execução observada
```

O produto possui duas macro-capabilities complementares:

1. **Experience Lifecycle** — catálogo, Journey Map, Run, Review, execução,
   evidência e documentação viva;
2. **Backend Gateway** — mock seletivo, proxy para ambiente não produtivo,
   presets, isolamento, verify ≡ API e observabilidade de rede.

Elas são materializadas por quatro bounded contexts: `Catalog & Docs`,
`Sessions`, `Backend Gateway` e `Evidence & Release`. `Source & Automation` é
supporting capability transversal; `Workspace Host` é boundary de aplicação/deploy,
não domínio.

```text
                        Abel Studio
             +---------------+---------------+
             |                               |
             v                               v
      Experience Lifecycle           Backend Gateway
      Journey / Scenario             GatewayScope / GatewayPreset
      Explore / Run / Review         mock | passthrough
      Execution / Evidence           verify | traffic | probe
             |                               |
             +---------------+---------------+
                             |
                             v
                      App cliente real
```

A plataforma não reconstrói o app em outra tecnologia. Ela executa o código real
do consumidor e substitui apenas fronteiras externas declaradas.

### 1.1 Destino do produto

**Abel é a identidade humana do produto.** O profile `full-local` compõe a
superfície local completa; o nome de um diretório de trabalho não é contrato.
`workspace` é o namespace estável para schemas, kinds, packages, APIs, protocolo,
machine output, artifacts e media types. Nomes e diretórios humanos pertencem
ao `ConsumerLayout` da distribuição.

O mesmo núcleo `workspace` pode gerar distribuições diferentes:

```text
núcleo e contratos workspace
  +-- distribuição Abel
  +-- distribuição Helix
  +-- distribuição de terceiros
```

Uma distribuição pode mudar nome, ícone, instalador, endpoint de updates,
config filename, content root, tooling entrypoint e aliases de executável. Ela
não renomeia schemas, kinds, digests ou contratos.
Essa composição substitui um hardfork semântico e preserva atualização entre
upstream e distribuições.

O gateway legado:

- é referência de comportamento;
- foi implementado em uma stack web PHP;
- não é dependência de build, runtime ou teste;
- não será copiado nem embarcado no núcleo novo.

Distribuições branded futuras permanecem Dart/Jaspr com adapters Flutter
opcionais e usam os mesmos
contratos `workspace`.

### 1.2 Baseline legado e tradução para o alvo

O gateway legado era um gateway local de mocks com console operacional. Ele ficava
entre um app real e backends não produtivos para preservar login/sessão reais
enquanto controlava apenas o fluxo sob desenvolvimento.

| Dimensão | gateway legado | Abel / distribuição exemplo |
|----------|-------------|------------------------------|
| Objeto central | request HTTP mockada ou proxied | Journey/Scenario/Evidence + Backend Gateway |
| Runtime do app | app real; APIs apontadas ao gateway local | app real em ExecutionTarget |
| Backend | preset mock + proxy do restante | Gateway Dart em `isolated` ou `hybrid` |
| UI da ferramenta | console web operacional | Studio Jaspr Explore/Run/Review |
| Instalação | scripts e reverse proxy do host | CLI `workspace` + bootstrap opt-in |
| Fidelidade | implícita | runtime fidelity e backend mode ortogonais |
| Estado | arquivo local mutável | fontes autorais + GatewaySession + digests |

Tradução obrigatória:

| Conceito legado | Alvo |
|-----------------|------|
| middleware/controllers HTTP | Backend Gateway Dart |
| console web | Studio Jaspr + CLI |
| scenario store local | GatewaySession + storage por digest |
| feature tests | conformance e integration tests Dart |
| script de lifecycle | CLI bootstrap/sync/verify/stop |
| produto mock | GatewayScope |
| flow preset | GatewayPreset |
| bundle | CompiledGatewayPlan |

Não são portados: framework PHP, templates web, rotas do console legado,
estrutura de classes, CLI da stack anterior, schema SQL embutido ou
configuração de reverse proxy local. Requisitos observáveis, como isolation, hybrid, verify ≡ API,
traffic, probe, lifecycle e hygiene, são definidos neste documento.

### 1.3 Menor produto coerente

O primeiro vertical não é uma plataforma hosted completa. É um sistema local
capaz de:

1. compilar uma descrição pequena de jornada;
2. exibir um Journey Map estático e uma leitura linear equivalente;
3. iniciar um target Flutter existente;
4. executar uma sessão controlada com capabilities honestas;
5. capturar uma evidência identificada;
6. explicar target, configuração e fidelidade usados.

O Gateway é organizado por capacidades verificáveis:

- dimensões `backendMode`/`networkContainment` e fingerprint no vertical local;
- contratos e runtime Gateway isolated no isolamento do Gateway;
- modo hybrid na contenção do Gateway;
- host-native e substituição operacional na evidência web/Android.

---

## 2. Problema, tese e resultados esperados

### 2.1 Problema de produto

O conhecimento de uma experiência se fragmenta:

1. intenção nasce em Product e UX;
2. mobile implementa UI, navegação e estado;
3. backend implementa contratos e comportamentos;
4. QA reconstrói cenários em ferramentas separadas;
5. screenshots e documentação envelhecem;
6. stakeholders perdem uma forma executável de compreender a entrega.

Além disso, estados de backend relevantes costumam ser difíceis de reproduzir:

- uma resposta rara;
- uma falha específica;
- uma operação pendente;
- um timeout;
- uma sequência mutável de requests;
- uma sessão real que precisa coexistir com respostas simuladas.

Fixtures isoladas resolvem parte do problema. Um proxy puro também. Nenhum dos
dois, sozinho, oferece a combinação:

```text
sessão real + estado simulado específico + explicação + evidência
```

### 2.2 Tese

Uma jornada deve acompanhar o produto durante sua vida, em vez de terminar
como um desenho entregue à engenharia.

A plataforma conecta:

- intenção versionada;
- código e contratos relacionados;
- app real em execução;
- fronteiras simuladas;
- backend real ou seletivamente substituído;
- evidências e decisões humanas.

O Gateway não é um fake backend universal. Ele é uma capability oficial e
opt-in para controlar a fronteira HTTP sem duplicar o produto inteiro.

### 2.3 Resultados esperados

Para uma pessoa revisora:

- abrir um link ou bundle no contexto correto;
- entender jornada, cenário, dados e fidelidade;
- experimentar uma sessão quando permitido;
- distinguir evidência de aprovação.

Para engenharia:

- iniciar com pouco acoplamento;
- evoluir de launch manual para controle determinístico;
- reproduzir estados por GatewayPreset;
- saber se cada request foi mock ou passthrough;
- remover a integração de forma explicável.

Para QA:

- navegar cenários em linguagem de produto;
- aplicar estado controlado;
- verificar contrato e evidência;
- cobrir falha, recuperação e runtime mutável.

### 2.4 Non-goals iniciais

Não fazem parte do núcleo inicial:

- substituir a arquitetura do app consumidor;
- hospedar produção do consumidor;
- copiar contratos OpenAPI/AsyncAPI como segunda fonte;
- inferir jornadas automaticamente como verdade;
- depender de LLM;
- editor visual livre completo;
- device farm;
- colaboração multiusuário hosted;
- suporte universal a frameworks no primeiro vertical;
- compatibilidade runtime com a stack PHP anterior;
- portar templates web, controllers HTTP ou a suite de testes da stack PHP anterior;
- enviar push de teste pelo núcleo;
- gerar pacote instalável do aplicativo pelo Studio;
- manter painel de uso de IA;
- copiar snapshots de feature flags como fonte autoral;
- alterar código do app ou serviços remotos por default;
- atuar como framework E2E universal.

Push de teste, build de aplicativo e snapshots de flags podem surgir como
plugins opcionais de distribuição. Eles não bloqueiam web local e Android nem pertencem ao
Backend Gateway.

---

## 3. Princípios arquiteturais

### 3.1 Identidade técnica estável e stack Dart/Jaspr com adapters Flutter

**Decisão.**

- `Abel` identifica projeto, repositório e distribuição de referência;
- `workspace` é o namespace técnico permanente dos contratos;
- distribuições podem escolher nomes de configuração, diretórios e aliases
  humanos por `ConsumerLayout`;
- schema kinds, URNs, protocolo e machine output continuam `workspace`;
- Studio e Review mode: Jaspr client-side com HTML/CSS próprios;
- domínio, documentos e Application Services: pure Dart;
- CLI, Gateway e infraestrutura local: Dart VM;
- integração app-facing: package Flutter;
- nenhum runtime PHP no produto novo.

Defaults da distribuição Abel:

| Superfície | Nome técnico |
|------------|-------------|
| Projeto | `Abel` |
| Repositório | `full-local` |
| Configuração raiz | `workspace.yaml` |
| Conteúdo versionado | `.experience/` ou `content.root` |
| Override local | `workspace.local.yaml` |
| Cache no workspace | `.dart_tool/workspace/` |
| Estado por usuário | `<state-dir>/workspace/` |
| Variável de descoberta | `WORKSPACE_CONFIG` |
| CLI | `workspace` |
| Aplicação web Jaspr | `studio` |
| Sidecar | `gateway_sidecar` |
| Packages iniciais | `experience_contracts`, `experience_engine`, `execution_runtime`, `flutter_app_adapter` |
| Schema namespace | `https://github.com/jantunesmessias/abel/schemas/<domain>` |

Esses nomes descrevem a distribuição de referência. Outra distribuição pode
usar, por exemplo, `helix.yaml`, `.helix/` e o alias `helix`, mas normaliza tudo para
o mesmo modelo `workspace`. Prefixos organizacionais exigidos por um registry ficam
na publicação, não nos kinds e tipos de domínio.

### 3.2 Uma implementação do produto consumidor

O app interativo usa UI, navegação e regras reais do consumidor.

Mocks, simuladores e Gateway substituem fronteiras externas declaradas, não o
produto inteiro.

### 3.3 Local-first

Catálogo, Studio, sessões locais, Gateway isolated, evidência e bundle não
dependem de conta, nuvem ou tenancy.

Hosting futuro compõe ports públicos; não redefine o núcleo.

### 3.4 Protocolo agnóstico, adapters específicos

Documentos e contratos canônicos não dependem de Flutter. Cada tecnologia
implementa um adapter compatível.

Flutter é o primeiro adapter de primeira classe, não a definição do protocolo.

### 3.5 Valor progressivo e reversível

Um consumidor pode:

1. documentar;
2. executar um target existente;
3. controlar app e backend;
4. comprovar por evidência e policies.

Capabilities ausentes limitam a claim; não invalidam o projeto inteiro.

### 3.6 Fontes e derivados não se confundem

| Classe | Exemplos | Regra |
|--------|----------|-------|
| Fonte autoral | DistributionDescriptor, Journey, Scenario, GatewayPreset, layouts, policies | editável explicitamente |
| Fonte executável | código, config de execution target, contratos externos | pertence ao consumidor |
| Derivado | manifest, CompiledGatewayPlan, captura, trace, verify | regenerável |
| Decisão | approval, rejection, waiver, finding | imutável e ligada a digest |
| Segredo local | token, URL não produtiva, credencial | nunca entra em release |

### 3.7 Uma interpretação canônica

Studio, CLI, CI e agentes usam o mesmo `ExperienceEngine` e os mesmos command/query
handlers. Nenhuma superfície mantém uma interpretação paralela de Journey,
Gateway ou Release.

Operações locais mutáveis pertencem ao `Workspace Host`, um processo Dart VM sob a
identidade do usuário. O Studio é cliente desse Host inclusive quando empacotado
como desktop; ele não ganha uma segunda implementação de filesystem, processo,
Gateway ou release. O CLI pode instanciar o mesmo engine in-process para uma
operação one-shot ou conectar-se ao Host durante `dev`.

### 3.8 Estado semântico não é variante visual

- mudança de significado cria outro `Scenario`;
- viewport, tema, locale e escala são `Variant`;
- screenshot é evidência, não cenário;
- `GatewayPreset` prepara backend, não substitui `Scenario`.

### 3.9 Intenção e observação são separadas

`Journey` declara caminho pretendido. `SessionTrace` registra o observado.

Uma execução divergente não reescreve silenciosamente a jornada.

### 3.10 Toda claim declara fidelidade

Fidelidade de runtime:

| Nível | Significado |
|-------|-------------|
| `structural` | superfície isolada; composição, sem host completo |
| `simulated` | app real com fronteiras controladas |
| `hostNative` | app em emulador, simulador ou host real |
| `deviceAttested` | dispositivo físico identificado |

Modo de backend é uma dimensão separada:

| Modo | Significado |
|------|-------------|
| `none` | Gateway ausente |
| `isolated` | o Gateway nunca faz passthrough; nele, cada request vira mock ou deny |
| `hybrid` | subset mock + proxy autenticado para upstream não produtivo |

Contenção de rede do target é uma terceira dimensão:

| Nível | Significado |
|-------|-------------|
| `unconstrained` | o Abel não controla todo o egress do app |
| `gatewayOnly` | APIs redirecionadas ao Gateway estão contidas; outras conexões do app não são garantidas |
| `targetEnforced` | adapter do target prova que todo egress está negado ou allowlisted pela policy |

`hybrid` não aumenta automaticamente a fidelidade visual e nunca significa
produção.

`backendMode: isolated` sozinho **não** autoriza as claims “offline”, “sem
egress” ou “reproduzível”. Essas claims exigem `networkContainment:
targetEnforced`, bootstrap controlado e fingerprint completo.

`contractProbe` é uma operação de desenvolvimento separada. Não é nível de
fidelidade nem modo de routing do app.

### 3.11 Hybrid é explícito e não reproduzível por default

Hybrid é suportado porque preserva sessão real enquanto controla o fluxo
sob teste. Ele também introduz drift, egress e credenciais.

Consequências:

- policy de rede obrigatória;
- upstreams e sessão não entram na release em claro;
- evidência declara modo hybrid;
- release seal não aceita hybrid como prova determinística por default;
- um target pode definir policy específica mais restrita.

### 3.12 Verify ≡ API

Quando Gateway responde mock, o JSON mostrado em verify passa pelo mesmo
handler e pelo mesmo pipeline que responde ao app.

Builder paralelo apenas para preview é proibido.

### 3.13 Um GatewayScope ativo por GatewaySession

Por default, somente um `GatewayScope` pode controlar routing em uma
`GatewaySession`. Outros scopes permanecem passthrough ou bloqueados pela
policy.

Essa exclusividade pertence ao Gateway; várias Journey e Scenario continuam
válidas no catálogo.

### 3.14 Grafo e layout são documentos diferentes

Journey e Transition definem significado. Projection e Layout definem
geometria. Recompilar o catálogo não destrói curadoria do Journey Map.

### 3.15 Journey Map estático; Run vivo

O Journey Map usa capturas estáticas e metadados. Não mantém uma instância viva do
app em cada node.

Run hospeda uma única sessão interativa.

### 3.16 Evidência não é aprovação

Automação prova observação em um ambiente. Aprovação é decisão humana separada.

### 3.17 Núcleo determinístico; IA externa

Compilação, digests, routing, verify, policies, release e gates funcionam sem
LLM.

Agentes consultam fatos e propõem patches; nunca criam verdade, approval ou
release por autoridade implícita.

### 3.18 Segurança e privacidade por construção

- dados sintéticos em fixtures;
- menor privilégio;
- rede negada ou allowlisted;
- logs sanitizados;
- artifacts identificados;
- contexto mínimo para agentes;
- nenhum segredo em catálogo ou release.

### 3.19 Sem domínio do consumidor na arquitetura do produto

O núcleo não conhece produtos, squads, hubs ou jornadas reais de um
consumidor. Exemplos do repositório usam domínios hipotéticos.

### 3.20 Fluxo unidirecional e estado explícito

Views Flutter renderizam estado imutável e enviam intents/commands. ViewModels
ou presentation controllers transformam streams de projeções em view state; não
executam filesystem, processo, proxy ou regra de release. Mutação segue:

```text
View -> Command -> Application Service -> Domain/Port -> Event/Projection -> ViewState
```

Estado assíncrono distingue pelo menos `initial`, `loading`, `data`, `empty`,
`failure` e `refreshing`; lista vazia nunca representa erro ou dado ausente.

### 3.21 Recursos assíncronos têm owner

Processo, listener, subscription, stream, timer, isolate, arquivo temporário,
lease e token efêmero pertencem a um scope explícito. O owner cancela e limpa
recursos em sucesso, falha, timeout e shutdown. “Fire-and-forget” é proibido em
operações que afetam sessão, evidence, release ou Gateway.

### 3.22 Integridade não é autenticidade

Digest prova identidade de bytes ou modelo canônico; não prova quem produziu o
conteúdo. Assinatura/attestation, quando habilitada, é um contrato separado com
signer, algoritmo, key ID, policy e verificação. UI e machine output nunca
apresentam “verificado” quando apenas o hash confere.

### 3.23 Compatibilidade é explícita

Schema, protocolo, CLI JSON, artifact media type e release manifest possuem
versões independentes. Capabilities são negociadas; campos obrigatórios não são
inferidos da versão do aplicativo. Mudança incompatível exige migration,
conformance e janela declarada, nunca fallback silencioso.

### 3.24 Composição do Kit é explícita

O Kernel é mínimo; valor opcional entra por `Module` built-in registrado em
compile-time. `Capability` declara o contrato fornecido ou requerido e
`Provider` seleciona uma implementação. `Profile` é somente overlay
declarativo. `Plugin` continua extensão externa out-of-process e `Grant`
continua autorização, não disponibilidade.

Distribution informa o que está `packaged`; configuração informa o que está
`enabled`; lifecycle/health informam o que está `ready`; grants informam o que
está `authorized`. As quatro dimensões não se substituem. CLI, Host e Studio
observam um único `ResolvedKitPlan` por digest e módulo desabilitado produz zero
comando, RPC, rota, processo, porta, device access ou artifact.

---

## 4. Arquitetura da experiência

### 4.1 Públicos e jobs

| Público | Job principal |
|---------|---------------|
| Product | compreender objetivo, caminhos e resultado |
| UX | comparar intenção, implementação e divergência |
| Mobile | executar, diagnosticar, controlar e recapturar |
| Backend | relacionar contratos e observar participação no fluxo |
| QA | preparar estado, percorrer alternativas e registrar evidência |
| Stakeholder | experimentar e decidir sem operar toolchain |

### 4.2 Dois modos sobre o mesmo aplicativo

#### Review mode

Entrada read-only em relação a fontes autorais, configuração e routing. Permite:

- abrir release, journey, scenario ou ReviewGuide;
- navegar Explore;
- iniciar uma sessão efêmera a partir de um `ScenarioExecutionBinding`
  previamente concedido e imutável;
- comparar evidência;
- registrar decisão quando houver grant.

Não oferece:

- sync de upstreams;
- mudança de routing;
- edição de fixture;
- publish;
- bootstrap de host.

Iniciar uma sessão concedida pode materializar target, checkpoint e
GatewayPreset de forma atômica. Isso é uma mutação efêmera do runtime, não uma
edição: a pessoa revisora não escolhe outro preset, não altera `RoutingTable` e
não persiste configuração. Reset e dispose permanecem permitidos dentro da
sessão concedida.

#### Authoring mode

Acrescenta:

- autoria;
- diagnóstico;
- targets e sessions;
- backend configuration;
- captura;
- release;
- CLI equivalente;
- ferramentas de Gateway.

Os modos projetam o mesmo modelo. `Abel Studio` é o nome da distribuição de
referência e pode receber branding sem alterar rotas ou contratos `workspace`.

### 4.3 Contextos de trabalho

#### Explore

- visão espacial da Journey;
- outline linear equivalente;
- filtros por lifecycle, coverage, fidelity e freshness;
- nenhum runtime iniciado implicitamente.

#### Run

- uma `Session`;
- Guided ou Explore freely;
- device controls;
- Backend panel;
- trace;
- reset;
- capture.

#### Review

- comparação;
- evidence;
- findings;
- approval separado;
- explicação de fidelidade e dados.

### 4.4 Continuidade de contexto

`WorkspaceContext` preserva:

- workspace;
- application;
- release;
- journey;
- scenario;
- variant;
- projection;
- target;
- session quando compatível;
- camera/selection em Explore.

Trocar Explore → Run → Review não devolve a pessoa a uma home genérica.

### 4.5 Backend panel

Superfície funcional do Studio para controlar a fronteira HTTP:

| Job | Projeção |
|-----|----------|
| Ativar GatewayScope | seletor de scope no Run |
| Aplicar GatewayPreset | action no Scenario Sheet / Run |
| Ver routing | resumo mock/passthrough |
| Verify ≡ API | request/response e diff |
| Traffic | filtro de `TrafficEvent` no trace |
| Upstreams | status sanitizado; sem URL/secret em Review |
| Probe | ferramenta de dev no Studio |
| Sync | comando explícito / painel Sistema |
| Qualidade | ReviewGuide + binding concedido que abre sessão já configurada |
| Documentação legado | import sanitizado como draft de Journey/Scenario Sheet |
| Bootstrap/status | CLI `gateway bootstrap/status/doctor` |

No Run, a ordem operacional é:

1. selecionar/ativar GatewayScope;
2. aplicar GatewayPreset;
3. verificar JSON e routing;
4. usar traffic, probe ou fault controls quando necessário.

Review mode não altera routing depois de materializar o binding concedido. Push,
build de aplicativo, snapshot de flags e
painel de IA não fazem parte do núcleo; uma distribuição pode expô-los por
plugin sem alterar os Application Services canônicos.

### 4.6 Progressive disclosure

Informação aparece na ordem:

1. o que está sendo mostrado;
2. por que importa;
3. o que é possível fazer;
4. qual fidelidade e dados sustentam a claim;
5. detalhes técnicos (digest, target, routing, logs).

### 4.7 Grants e capabilities

- `ActionGrant`: quem pode executar uma ação;
- `CapabilityDescriptor`: o que o runtime suporta.

Um target capaz de mudar routing não autoriza uma pessoa a fazê-lo.

Papéis são presets de grants, não enums rígidos do domínio.

Toda ação pública declara uma classe de efeito:

| `ActionEffect` | Exemplos | Review mode |
|----------------|----------|-------------|
| `query` | abrir, filtrar, comparar, exportar leitura | permitido |
| `ephemeral` | iniciar/resetar/dispor sessão concedida, capturar evidence local | permitido por grant e policy |
| `authoring` | editar Journey, fixture, layout ou binding | proibido |
| `infrastructure` | sync, routing livre, bootstrap, publish | proibido |
| `decision` | approval, rejection, waiver, finding | permitido por grant; append-only fora da Release |

Grant sem capability falha; capability sem grant não autoriza. O backend
revalida ambos — ocultar um botão não é controle de acesso.

---

## 5. Visão do sistema

### 5.1 Bounded contexts

```text
                        clientes
     +---------------------------------------------------+
     | Studio Jaspr  | CLI | CI | agentes | Review      |
     +--------------------------+------------------------+
                                |
                 contratos de entrada versionados
     +---------------------------------------------------+
     | Host RPC | CLI JSON | bundle reader | agent API   |
     +--------------------------+------------------------+
                                |
                                v
     +---------------------------------------------------+
     | Workspace Host / Application Services                 |
     | authz, commands, queries, supervision, unit of work|
     +--------------------------+------------------------+
                                |
              +-----------------+-----------------+
              |                                   |
              v                                   v
     +-------------------------+-------------------------+
     | Catalog & Docs                                    |
     | documentos, grafo, projections, compilação        |
     +------------+--------------------------+-----------+
                  |                          |
                  v                          v
     +------------------------+  +------------------------+
     | Sessions               |  | Backend Gateway        |
     | lifecycle, commands,   |  | Gateway                |
     | capabilities, trace    |  | mock, proxy, verify    |
     +------------+-----------+  +------------+-----------+
                  |                           |
                  +-------------+-------------+
                                |
                                v
     +---------------------------------------------------+
     | Evidence & Release                                |
     | artifacts, freshness, manifests, policies, CAS    |
     +---------------------------------------------------+
                                |
                           ports/adapters
                                v
     +---------------------------------------------------+
     | app consumidor + fronteiras reais/simuladas       |
     +---------------------------------------------------+

     Source & Automation: serviço transversal sobre os mesmos
     Application Services, sem criar outro domínio.

     Hosted Collaboration & Remote Execution:
     application/deploy planes opcionais sobre os mesmos contracts/engine;
     não são dependência do núcleo local.
```

O Host é boundary de aplicação e deploy, não bounded context de negócio. O
Gateway é bounded context e também sidecar de processo. Essas classificações
não se confundem.

### 5.2 Workspace Host

Processo Dart VM local que:

- resolve distribuição, workspace, principal, grants e capabilities;
- instancia os Application Services canônicos;
- serializa commands mutáveis por workspace/session;
- supervisiona target, Gateway e recursos temporários;
- expõe queries/projeções e eventos ao Studio;
- serve artifacts por handles com escopo e expiração;
- encerra filhos e revoga tokens no shutdown.

O Studio nunca recebe path arbitrário, credential handle materializado ou
permissão para iniciar processo. Ele envia referências tipadas. Review bundle
read-only pode funcionar sem Host; qualquer ação local mutável exige Host.

### 5.3 Catalog & Docs

Responsável por:

- parse e validação;
- modelo semântico;
- Journey/Scenario/Transition;
- projections;
- living docs;
- compilation e manifest.

Não conhece Flutter, processos ou credenciais.

### 5.4 Sessions

Responsável por:

- lifecycle;
- capabilities;
- commands;
- checkpoints;
- trace append-only;
- relação com target e runtime configuration.

Não implementa transporte concreto nem servidor HTTP.

### 5.5 Backend Gateway

Responsável por:

- interceptar HTTP;
- resolver mock/passthrough;
- isolamento;
- runtime de preset;
- verify;
- traffic;
- upstream status;
- probe opt-in.

Implementado em Dart.

### 5.6 Evidence & Release

Responsável por:

- artifacts;
- fingerprints;
- freshness;
- comparison;
- evidence;
- release e bundle;
- CAS e policy.

Não inicia processos.

### 5.7 Source & Automation

Responsável por:

- source snapshots;
- change sets;
- bindings;
- impact;
- context bundles;
- projections para CI/agentes.

É transversal e determinístico.

### 5.8 Regra de dependência

```text
UI/adapters/infrastructure
          |
          v
Application Services
          |
          v
Domínio e documentos

Domínio --X--> Flutter
Domínio --X--> filesystem
Domínio --X--> processo
Domínio --X--> GitHub
Domínio --X--> RemoteConfigVendor
Domínio --X--> LLM
```

### 5.9 Transações entre contexts

Application Services coordenam casos de uso, por exemplo:

```text
ApplyGatewayPreset
  -> valida GatewayPreset
  -> inicia/atualiza GatewaySession
  -> grava RoutingTable derivada
  -> emite evento para SessionTrace
  -> invalida evidências dependentes

CaptureEvidence
  -> solicita capture à Session
  -> recebe artifact
  -> lê ExecutionFingerprint (inclui Gateway)
  -> grava Evidence
```

Nenhum context altera storage de outro diretamente.

### 5.10 Hosted e remote planes

hosted control plane/remote execution não adicionam um segundo domínio local. Eles acrescentam composition
roots e adapters:

```text
Studio/CLI -- HTTPS/WSS --> hosted control plane
                              |-- PostgreSQL + forced RLS
                              |-- S3-compatible object store
                              |-- OTLP
                              `-- Kubernetes API
                                      `-- namespace/Job por remote run
```

`HostedCollaborationService` e `RemoteSchedulerService` vivem no engine pure
Dart. PostgreSQL, S3, OIDC HTTP, Kubernetes, worker e gateway de sessão vivem no
runtime/apps. O hosted plane não chama filesystem/CAS local; o worker não chama
PostgreSQL; o Studio não recebe credencial de infraestrutura.

Boundaries de deploy não redefinem bounded contexts. Uma revisão hosted ainda é
Catalog/Source; um artifact remoto ainda é Evidence; um target remoto ainda é
Sessions. Tenant, autorização, scheduling e cleanup são policies de aplicação
e infraestrutura em torno desses contratos.

---

## 6. Contratos canônicos por bounded context

### 6.1 Contrato de documentos

Cada bounded context possui seu próprio contrato pure Dart, independente de
Flutter e de transporte. Não existe um agregado universal que precise evoluir
Experience, Sessions, Gateway, Evidence, Source e agentes em conjunto.

Contexts se relacionam apenas por referências tipadas, digests e eventos
coordenados pela camada de aplicação. As categorias autoral, compilado,
runtime, derivado e segredo continuam explícitas dentro de cada context.

Documentos publicáveis:

- JSON Schema Draft 2020-12;
- fontes YAML ou JSON;
- normalização para JSON;
- `kind`, `id`, `$schema`, `schemaVersion`;
- extensões namespaced;
- duplicate keys e custom tags rejeitados;
- limites de tamanho/profundidade;
- serialização canônica RFC 8785/JCS para digest semântico.

Pipeline canônico v1:

```text
YAML/JSON autorizado
  -> AST segura sem aliases recursivos/custom tags
  -> validação estrutural
  -> modelo JSON semântico I-JSON
  -> normalização de strings/IDs/enums definida pelo schema
  -> JCS UTF-8
  -> sha256:<hex>
```

JCS não normaliza significado. O schema v1 rejeita `NaN`, infinidades, zero
negativo, inteiros fora do intervalo interoperável e timestamps/decimais
dependentes de locale; precisão arbitrária, decimal, duration e instant são
strings com formato canônico. Digest de `Artifact` usa bytes brutos; digest de
documento usa o modelo semântico canônico. Ambos declaram algoritmo.

Schemas usam URNs técnicas estáveis, por exemplo
`https://github.com/jantunesmessias/abel/schemas/journey`. Nome de distribuição, hostname do
repositório e publisher nunca participam de `$schema`, `kind` ou digest.

### 6.2 Identidade

- ID acompanha a entidade entre revisões;
- digest identifica conteúdo imutável;
- `SubjectRef` combina workspace, application quando aplicável, kind, ID e
  digest;
- IDs são opacos e tipados;
- posição do Journey Map nunca faz parte do ID.

### 6.3 Distribuição e layout do consumidor

| Entidade | Responsabilidade |
|----------|------------------|
| `DistributionDescriptor` | identidade, versão upstream, branding, policies, plugins e layout default |
| `ConsumerLayout` | config file/env, content root, local config, tooling entrypoint e command aliases |

`DistributionDescriptor` não redefine domínio. Ele pode escolher superfícies
humanas, mas deve preservar:

- schemas `https://github.com/jantunesmessias/abel/schemas/<domain>`;
- kinds e semântica;
- CLI JSON e exit codes;
- digests e conformance suite;
- compatibilidade declarada com a versão do core.

`ConsumerLayout` é resolvido antes do parse do catálogo e depois normalizado:

```text
launcher/distribution defaults
  + config explícita do consumidor
  -> paths autorizados e normalizados
  -> modelo canônico workspace
```

### 6.4 Entidades de catálogo e experiência

| Entidade | Responsabilidade |
|----------|------------------|
| `Workspace` | raiz lógica da integração; pode conter várias aplicações |
| `Application` | unidade executável do consumidor dentro do workspace |
| `Journey` | caminhos em torno de objetivo |
| `Scenario` | estado semântico observável |
| `Transition` | relação dirigida entre cenários |
| `Board` | agrupamento autoral de projections de uma Application |
| `ExperienceProjection` | lens tipada do grafo (`journey`, `inventory`, `history`, `comparison` ou `changeset`) |
| `NodeInstance` | occurrence visual estável de um Scenario em uma projection |
| `EdgeInstance` | materialização visual de uma Transition entre NodeInstances compatíveis |
| `ProjectionLayoutManifest` | geometria curada independente da topologia semântica |
| `ScenarioFacetManifest` | taxonomia consumer-owned, fechada e ligada ao digest do Catalog |
| `ScenarioLabManifest` | controls, scripts, critérios, Evidence requerida e comparação declarativos, ligados ao Catalog |
| `ExperienceContentSet` | identidade atômica do WorkspaceSnapshot e manifests adjacentes presentes |
| `Variant` | ambiente visual sem mudar significado |
| `ReviewGuide` | narrativa humana curada |
| `IntentReference` | referência versionada à intenção |
| `BackendContract` | referência a OpenAPI/AsyncAPI |
| `SourceBinding` | relação autoral com fonte executável |
| `ScenarioExecutionBinding` | composição explícita de Scenario, target, checkpoint/launch e GatewayPreset opcional |

`CatalogManifest` v1 permanece a autoridade semântica de
Workspace/Application/Journey/Scenario/Transition. Topologia, layout e facets
são documentos adjacentes com digests próprios; não adicionam campos ao wire
v1. Quando `ScenarioFacetManifest` existe, ele cobre cada Scenario exatamente
uma vez. Kind/surface/state/owner/tag/component/fixture/form factor são
registries tipados fornecidos pelo consumer; lifecycle, render-source kind e
frame kind são enums portáteis fechados. Ausência nunca autoriza inferência por
ID, título, Source ou geometria.

O Host compila esses documentos da mesma lista imutável de authoring e publica
uma única geração. `experience.content.open` exige revision,
`catalogDigest` e `contentSetDigest`, então concede WorkspaceSnapshot,
ExperienceTopologyBundle e ScenarioFacetManifest presentes por handles
imutáveis em lote. A revisão faz fencing; `contentSetDigest` identifica os
digests de conteúdo e não muda apenas porque a mesma geração foi observada com
outra revisão. Contratos e compatibilidade estão em ADR-0017 e ADR-0018.

`ScenarioLabManifest` também é um documento adjacente e não altera o
`CatalogManifest` v1. Ele permite um Lab apenas com script/binding e adiciona
controls, operations, required Evidence, policies, baseline/candidate,
supplemental artifacts e aprovação humana somente quando declarados. O
compiler e os codecs estão ativos. O vertical Scenario Lab acrescenta publicação
atômica pelo Host, planner/executor, relay App Adapter tipado, resultados
duráveis e as superfícies Lab/Quality do Studio. O manifest continua sendo
plano declarativo: run, Evidence, comparação, aceitação automatizada e decisão
humana mantêm identidades e lifecycles próprios.

### 6.5 Entidades de execução

| Entidade | Responsabilidade |
|----------|------------------|
| `ExecutionTarget` | launch/render/control/capture/reset de uma Application |
| `LaunchProfile` | iniciar sem claim de estado reproduzível |
| `ConsumerAppFactory` | factory consumer-owned reutilizada por produção e tooling, sem import workspace |
| `ApplicationBootstrapPolicy` | tratamento explícito de dependências antes do app ficar ready |
| `RuntimeConfigurationOverlay` | overrides efêmeros e não secretos para tooling |
| `NetworkContainmentDescriptor` | nível efetivo, enforcement adapter e policy de egress do target |
| `Checkpoint` | preparar/reconhecer Scenario |
| `CapabilityDescriptor` | capabilities efetivas |
| `Session` | lifecycle efêmero |
| `SessionTrace` | observações append-only |
| `InteractionScript` | inputs/eventos/expectativas |
| `DeviceProfile` | dimensões/capacidades de device |
| `Fixture` | dados sintéticos determinísticos do target |

### 6.6 Entidades do Gateway

| Entidade | Tipo | Responsabilidade |
|----------|------|------------------|
| `GatewayScope` | autoral | conjunto isolado de rotas controláveis |
| `GatewayPreset` | autoral | estado nomeado da fronteira HTTP |
| `GatewayRoute` | autoral | method/path/id + `appliesTo` |
| `CompiledGatewayPlan` | compilado | payloads, policies e routing por digest |
| `GatewayConfiguration` | autoral/local | modo, ports, policy e provider refs |
| `GatewaySession` | runtime | instância isolada ligada à Session |
| `RoutingTable` | compilado/runtime | route → mock/passthrough/deny |
| `VerificationReport` | derivado | request/response produzidos pelo mesmo pipeline |
| `TrafficEvent` | observado | request sanitizada + outcome |
| `UpstreamProfile` | local | aliases não produtivos; secrets fora do catálogo |
| `ContractProbePlan` | autoral | cadeia de probes para desenvolvimento |
| `FaultProfile` | autoral | latency/failure/forced status |

### 6.7 Relações que não podem colidir

```text
Scenario
  estado semântico da jornada
      |
      v
ScenarioExecutionBinding
      +-- ExecutionTarget
      +-- LaunchProfile ou Checkpoint
      +-- GatewayPresetRef opcional
      +-- Fixture/FaultProfile opcionais

GatewayPreset
  estado da fronteira HTTP
      |
      +-- compila CompiledGatewayPlan + RoutingTable

LaunchProfile
  como iniciar target, sem reconhecer estado

Checkpoint
  como preparar/reconhecer Scenario
```

`GatewayScope.id` não é `Workspace.id` nem `Application.id`.
`ReviewGuide` pode sugerir um `ScenarioExecutionBinding`, mas não contém
comando mutável nem controla Gateway diretamente.

### 6.8 Entidades de evidência e release

| Entidade | Responsabilidade |
|----------|------------------|
| `Artifact` | blob por media type e digest |
| `ExecutionFingerprint` | target, runtime, toolchain e fronteiras efetivas |
| `EvidenceProvider` | adapter para importar execução observada de ferramenta existente |
| `Evidence` | observação + subject + ExecutionFingerprint + policy |
| `Approval` | decisão humana sobre digest |
| `Finding` | divergência/risco identificados |
| `Release` | manifest imutável |
| `ReleaseBundle` | embalagem verificável de Release e artifacts |
| `PublicationView` | release + decisões externas |
| `CatalogManifest` | compilação determinística |
| `ComparisonPolicy` | regra de diff |

### 6.9 Source e automação

| Entidade | Responsabilidade |
|----------|------------------|
| `SourceRepository` | identidade/config da fonte |
| `SourceSnapshot` | árvore virtual + completude |
| `ChangeSet` | diferença entre snapshots |
| `ReleaseDiff` | diferença semântica entre releases compiladas |
| `ImpactPlan` | o que reutilizar/reconstruir |
| `ContextBundle` | contexto sanitizado por digest |
| `AgentTask` | envelope externo tipado, mínimo, expirável e limitado a inspect/propose |
| `AgentProposal` | draft imutável ligado à task/base/ChangeSet; apply é grant separado |

### 6.10 Estados ortogonais

| Dimensão | Estados mínimos |
|----------|-----------------|
| Scenario lifecycle | `concept`, `current`, `historical` |
| Evidence freshness | `missing`, `fresh`, `stale`, `invalid` |
| Verification | `notRun`, `passed`, `failed`, `error` |
| Human decision | `unreviewed`, `approved`, `rejected`, `superseded` |
| Runtime fidelity | `structural`, `simulated`, `hostNative`, `deviceAttested` |
| Backend mode | `none`, `isolated`, `hybrid` |
| Network containment | `unconstrained`, `gatewayOnly`, `targetEnforced` |
| Bootstrap assessment | `unassessed`, `declared`, `controlled`, `failed` |
| Gateway outcome | `mock`, `passthrough`, `denied`, `unmatched`, `error` |

Não existe um status único “green”.

### 6.11 Compilação

```text
fontes autorais
  -> parse
  -> schema validation
  -> semantic resolution
  -> compile GatewayPreset / graph
  -> CatalogManifest
  -> índices e derivados descartáveis
```

Migrations são explícitas, versionadas e testáveis. `validate` nunca reescreve
fonte autoral.

### 6.12 Modelo Dart

- tipos de domínio e DTOs são imutáveis;
- estados fechados usam `sealed class`/`enum` e switches exaustivos;
- invariantes nascem em factories/constructors validados, não em widgets;
- falhas esperadas atravessam boundaries como `OperationFailure` tipada com código,
  contexto sanitizado e recoverability; exceptions representam defeito ou
  falha inesperada e são convertidas uma vez na borda;
- APIs públicas usam tipos nomeados; records permanecem conveniência interna;
- relógio, random, ID generator, filesystem, processo e rede são ports;
- datas de domínio são UTC/RFC 3339; duração e ordenação runtime usam relógio
  monotônico;
- nenhum package público expõe tipo de `dart:io`, Flutter ou biblioteca de
  serialização através de boundary pure Dart.

### 6.13 Evolução de contrato

Cada payload declara `schemaVersion`; cada protocolo negocia um range e
capabilities. Antes de 1.0, mudanças incompatíveis ainda exigem migration e
fixture de compatibilidade. Depois de 1.0:

- minor adiciona comportamento opcional e mantém leitura da minor anterior;
- major pode remover ou reinterpretar somente com migration e release notes;
- extensões usam namespace e budget de tamanho;
- campo desconhecido fora de extension point falha fechado;
- writer nunca emite versão que o reader negociado não entende;
- conformance contém fixtures válidas, inválidas e de versões adjacentes.

### 6.14 Contratos hosted e remote

hosted control plane acrescenta `Organization`, `Principal`, `Membership`,
`HostedWorkspaceLink`, `WorkspaceRevision`, `WorkspaceChangeSet`,
`WorkspaceConflict`, `CollaborationEvent`, `PresenceLease`, `CommentThread`,
`AuditEvent`, `IdempotencyRecord` e `HostedBlobDescriptor`.

remote execution acrescenta `RemoteExecutionRequest`, `RemoteExecutionPlan`,
`RemoteWorkerDescriptor`, `RemoteLease`, `DeviceImageDescriptor`, `RemoteRun`,
`RemoteArtifactManifest`, `RemoteContainmentReport`, `RemoteSessionTicket` e o
framing de stream.

Invariantes comuns:

- documento persistido possui tenant e identidade tipados;
- JSON externo usa schema fechado e canonicalização/digest canônicos;
- mudança autoral usa expected digest; conflito nunca é last-write-wins;
- plano, capability e ticket vinculam tenant/run/audience/expiry;
- sequence/timestamp de stream são inteiros portáveis até `2^53-1`, preservando
  o wire de 64 bits entre Dart VM e JavaScript;
- artifact executável remoto é somente web build ou APK por digest;
- containment report authoritative nasce no scheduler, não é aceito como
  verdade por declaração livre do worker.

---

## 7. Autoria, configuração e storage

### 7.1 Estrutura de consumidor

Defaults do Abel:

```text
workspace.yaml                      # configuração versionada
workspace.local.yaml                # overrides locais; gitignored
.experience/                         # content.root default e configurável
├── journeys/
├── scenarios/
├── guides/
├── layouts/
├── references/
├── gateway/
│   ├── scopes/
│   ├── presets/
│   ├── routes/
│   └── probes/
└── baselines/
```

Em configuração v2, `launchProfiles` pode declarar comandos versionados e
confinados por Application. A declaração permanece inerte até autorização
explícita de Session, executa sem shell, recusa overlay semelhante a secret e
não substitui `ScenarioExecutionBinding` ou `Checkpoint`. No target web, o
contexto efêmero de sessão é entregue no fragmento do iframe com
`no-referrer`; nunca em query, log do servidor ou catálogo.

Uma distribuição pode trocar todo o layout humano. Exemplo da distribuição
Helix:

```text
helix.yaml
.helix/
├── journeys/
├── scenarios/
├── guides/
├── layouts/
├── references/
├── gateway/
│   ├── scopes/
│   ├── presets/
│   ├── routes/
│   └── probes/
└── baselines/
tools/helix/
├── distribution.yaml
├── branding/
├── policies/
├── adapters/
└── migrations/
```

`tools/helix/distribution.yaml` é uma camada de composição, não uma cópia do
core:

```yaml
schemaVersion: 1
id: helix
displayName: Helix
extends:
  distribution: full-local
consumerLayout:
  configFile: helix.yaml
  configEnvironmentVariable: HELIX_CONFIG
  contentRoot: .helix
  localConfigFile: helix.local.yaml
  toolingEntrypoint: tool/helix_main.dart
  commandAliases:
    - helix
```

O arquivo raiz do consumidor suporta monorepos e múltiplas aplicações:

```yaml
schemaVersion: 1
distribution:
  id: helix
  path: tools/helix
content:
  root: .helix
workspace:
  id: sample
applications:
  primary:
    root: apps/primary
    target: local
  companion:
    root: apps/companion
    target: local
```

Consumer config v2 mantém esses campos e acrescenta uma seleção modular
fechada. Profile é overlay, não branch de código:

```yaml
schemaVersion: 2
content: {root: .experience}
workspace: {id: sample}
applications:
  sample: {root: ., target: web}
kit:
  profile: journey-preview
  modules:
    evidence.auto-preview:
      enabled: true
      settings: {renderer: flutter-test, capturePolicy: static-v1}
  providerBindings: []
  startupPolicy: fail-required-v1
```

O arquivo principal usa exclusivamente `schemaVersion: 2`; versões anteriores
ao contrato publicado são recusadas antes da resolução e de qualquer efeito.

`content.root` é relativo ao arquivo de configuração por default e pode apontar
para qualquer diretório autorizado dentro do workspace. Nenhuma regra presume
`tools/`, monorepo Dart, dot-directory ou um nome de produto.

Estado e derivados:

```text
.dart_tool/workspace/<distribution-id>/ # cache e derivados reconstruíveis
<distribution>.local.yaml           # aliases/paths locais, sem credenciais
<state-dir>/workspace/<distribution-id>/
├── sessions/
├── traffic/
└── cas/
```

`<state-dir>` segue a convenção da plataforma, como XDG state no Linux e
Application Support no macOS. Tokens ficam em keychain/credential store ou
memória com TTL; não em YAML ou JSON do projeto. `.helix/`, `.experience/` ou qualquer
outro content root contém somente fonte autoral versionável.

### 7.2 Descoberta e precedência

Invocação canônica `workspace`:

1. `--config <path>`;
2. `WORKSPACE_CONFIG`;
3. busca ascendente por `workspace.yaml`.

Um launcher de distribuição conhece seu descriptor antes de carregar o
catálogo. `helix`, por exemplo:

1. respeita `--config`;
2. traduz `HELIX_CONFIG`, quando definido, para config explícita;
3. usa o `configFile` default do descriptor (`helix.yaml`);
4. mantém `WORKSPACE_CONFIG` e `workspace.yaml` como fallbacks canônicos.

Logo:

```text
helix validate
  == workspace --distribution tools/helix --config helix.yaml validate
```

```text
defaults de schema
  < DistributionDescriptor / ConsumerLayout
  < config do consumidor
  < config local da distribuição
  < CLI explícita
  < input da operação
```

Na composição do Kit, a precedência normalizada é:

```text
Kernel < Distribution < Profile < Workspace < local < startup
```

Cada camada é validada antes da seguinte. `WorkspaceConfigurationLoader`
descobre arquivos; `KitPlanResolver` interpreta e produz um único
`ResolvedKitPlan`. Module ausente, setting inválido, dependency/provider
ambíguo, conflito, cycle, platform incompatível, secret literal ou path fora da
raiz falham antes de qualquer effect.

`explain` mostra distribuição, arquivo descoberto, layout normalizado, origem e
precedência. Alias humano nunca altera machine output.

### 7.3 Dados publicáveis vs locais

| Dado | Publicável |
|------|------------|
| GatewayScope / GatewayPreset / route IDs | sim |
| Payload sintético | sim, conforme policy |
| Upstream logical ref | sim |
| URL concreta de upstream | não |
| token/header auth | não |
| traffic sanitizado | opcional |
| response remota crua | não por default |
| Verify de fixture sintética | sim |

### 7.4 Store local

O primeiro storage é filesystem:

- escrita atômica;
- lock por workspace e lock fino por sessão/publicação;
- optimistic concurrency por digest esperado em toda alteração autoral;
- CAS por digest;
- índices reconstruíveis;
- runtime state separado de fontes;
- nenhuma base opaca como fonte autoral;
- canonicalização de path antes de autorização;
- symlink/hardlink e TOCTOU tratados no adapter de plataforma;
- staging e fsync/rename quando a plataforma oferecer a garantia;
- quotas, retention e GC mark-and-sweep preservando manifests alcançáveis.

SQLite pode ser usado como índice local depois de medição, nunca como verdade
exclusiva.

Uma query não adquire lock de escrita nem cria diretório. Uma operação mutável
declara arquivos pretendidos, base digest, owner e rollback/cleanup. Crash entre
staging e commit deixa material recuperável e nunca publica manifest parcial.

### 7.5 Persistência hosted

PostgreSQL é fonte transacional para organization/membership, revisions/heads,
evidence/releases/findings/approvals, comments/presence/audit/outbox/idempotency
e scheduler remoto. Toda tabela inclui `tenant_id` em PK/FK/índice, usa RLS
forçada e é acessada pela role da aplicação `NOBYPASSRLS` em transação com
`SET LOCAL control_plane.tenant_id`.

O banco guarda somente metadata de blob: digest, tamanho, media type,
classification, retention e object key derivada. Bytes vivem no object storage
versionado. Event/outbox compartilham commit; `LISTEN/NOTIFY` apenas desperta o
dispatcher. Migrations seguem expand → switch → contract e são verificadas
contra cobertura RLS antes do deploy.

---

## 8. Studio e arquitetura de informação

Status de implementação: o vertical local comprovou o produto mínimo; a
composição modular comprovou o seam de gating e o AutoPreview, a projeção
tipada. O cutover Jaspr implementou a cadeia operacional
local: entrypoint sem sample, Host autoritativo, bootstrap/RPC, resources,
shell, Journey Map, Inspector, AutoPreview, Target/Gateway condicionais e viewer
Remote fail-closed.
O resultado executado está em
`docs/architecture/studio-reconstruction-results.md`; as subseções que
descrevem Review/Run/hosted além desse vertical continuam arquitetura-alvo e não
são promovidas por SR.

### 8.1 Aplicação única

Review mode e Authoring mode vivem no mesmo app Jaspr client-side. Rotas,
contributions e grants escolhem a experiência; modelos e serviços são
compartilhados. Não existe renderer selecionável nem fallback Flutter.

O Studio Jaspr empacotado é servido em origin local próprio pelo supervisor; o
Host permanece em outro origin loopback autorizado. Em checkout,
`--studio-dev-origin` pode autorizar um servidor Jaspr externo para hot reload:
o Host expõe bootstrap CORS somente àquele origin, enquanto WebSocket e handles
preservam a mesma audience. A URL de bootstrap é pública; token e grants nunca
entram em define/URL. A supervisão do Studio implementa startup, bootstrap e shutdown em
`workspace dev`; `--plan-only` preserva a inspeção sem efeitos. O target Flutter web
full-page roda em terceiro origin dentro de iframe. Empacotamento desktop pode
vir depois, mas reutiliza Views/ViewModels e Host RPC — não cria acesso direto a
filesystem/processo. Review bundle estático reutiliza as rotas read-only sem
Host.

### 8.2 Navegação

Rotas estáveis:

```text
/workspaces/{workspace}
/applications/{application}
/releases/{release}
/journeys/{journey}
/scenarios/{scenario}
/run/{session}
/review/{subject}
/lab
/lab/scenarios/{scenario}/scripts/{script}
/quality
/quality/scenarios/{scenario}/scripts/{script}?runId={run}
```

URLs não carregam action grant.

### 8.3 Journey Map

- nodes = Scenarios; captura é projeção visual opcional, não identidade;
- zoom semântico;
- virtualização;
- outline acessível equivalente;
- projection e layout separados;
- runtime não inicia no scroll/hover.

`JourneyMapNodeViewData` resolve `Scenario × Variant` para handle temporário,
provider, fidelity, freshness/status e diagnóstico. O Studio nunca recebe path
do CAS. `collected`, `stale`, `missing`, `failed`, `unsupported` e
`policyDenied` são distintos; falha não seleciona automaticamente pixels de
outro item. Em baixo zoom prevalecem shape/título/status; thumbnail e device
frame aparecem apenas no LOD apropriado.

### 8.4 Sheets

#### Journey Sheet

- objetivo;
- atores;
- caminhos;
- alternativas;
- coverage;
- fontes;
- release/freshness.

#### Scenario Sheet

- objetivo/estado;
- critérios;
- GatewayPreset relacionado;
- target/checkpoint;
- implementação;
- evidence/findings;
- ações permitidas.

### 8.5 Run layout

Quatro regiões:

1. context bar;
2. runtime/device frame;
3. guidance/controls;
4. diagnostics (trace/backend).

Em viewport compacto, o runtime fica em foco e diagnostics viram sheets.

No vertical Scenario Lab, a rota Lab seleciona Scenario, script e Variant, inicia um
Target Host-owned em porta efêmera e monta exatamente um iframe vivo. Controls,
reset, captura e leituras trafegam pelo relay com origin, nonce e geração
fenced. Chamadas de dados passam pelo Gateway ligado ao run. Resultado
terminal, cleanup, Evidence e comparação permanecem Host-authoritative.

### 8.6 Review

Review mostra:

- referência;
- atual;
- diff;
- execution fingerprint/fidelity;
- evidence;
- findings;
- decisão.

Routing, tokens e controles mutáveis ficam fora do Review mode.

A rota Quality abre um run terminal imutável por `runId`, resolve
baseline, candidate, diff e supplemental artifacts por resource handles e
projeta freshness/currentness sem reescrever o histórico. Aceitação
automatizada não muda quando uma decisão humana é aprovada ou superseded por
rejeição. A cadeia humana é append-only, atribuída e protegida por expected
digests. Findings, concepts, edição de layout e review authoring amplo são
tratados pela capacidade de autoria e review.

### 8.7 Acessibilidade

Target para chrome e documentos: WCAG 2.2 AA.

- teclado;
- foco;
- reflow;
- text scaling;
- reduced motion;
- alternativa a drag;
- status messages;
- saída explícita de iframe/runtime.

Não transfere claim de acessibilidade ao app consumidor.

O gate local de Scenario Lab e Quality de 2026-08-17 verificou, nas rotas exercitadas,
HTML sem controles focáveis anônimos, navegação por teclado, modal nativo com
foco/escape/retorno ao opener, reflow a 200%, reduced motion e ausência de
overflow horizontal ou logs severos. Esse escopo automatizado não é auditoria
WCAG, não cobre tecnologia assistiva ou contraste integral e não certifica o
Studio nem o consumer.

### 8.8 Arquitetura interna do Studio Jaspr

O Studio segue separação de responsabilidades e fluxo unidirecional:

| Camada | Responsabilidade | Não faz |
|--------|------------------|---------|
| View | composição, layout, foco, animação e tradução de input | I/O, regra de negócio, parse |
| ViewModel/Controller | estado imutável, commands, navegação e mensagens apresentáveis | acessar filesystem/processo/Gateway |
| Host Client Repository | cache de projeções e contrato RPC tipado | reinterpretar domínio |
| Workspace Host | Application Services e efeitos autorizados | renderizar UI |
| Engine | domínio, policies, commands/queries e ports | depender de Jaspr, Flutter ou transporte |

Views recebem um view state fechado e callbacks/commands. Controllers não
expõem DOM element, Component, controller visual ou exception de infraestrutura.
Dependências entram por constructor/factory no composition root; service
locator global, singleton mutável e leitura de container dentro de domínio são
proibidos.

A biblioteca de state management é uma decisão de implementação do Studio, não
um contrato do produto. Ela precisa provar:

- estado imutável e updates rastreáveis;
- cancelamento/dispose determinístico;
- override de dependências em teste sem global state;
- selectors para evitar rebuild amplo;
- suporte a deep link/restoration;
- ausência de dependência no `experience_engine`.

Commands de UI expõem `idle`, `running`, `succeeded` e `failed`, impedem double
submit por `operationId` e nunca escondem falha em lista vazia. Optimistic UI só
é permitida quando há rollback definido e a projeção do Host continua
autoritativa.

### 8.9 Navegação, adaptação e internacionalização

- URLs e route state são a fonte de navegação compartilhável;
- `WorkspaceContext` é serializável/restaurável sem incluir segredo ou grant;
- layout responde a espaço disponível, input e accessibility features, não a
  uma lista rígida de devices;
- teclado, mouse, touch e assistive technology recebem caminhos equivalentes;
- textos visíveis não são IDs, selectors ou códigos de erro;
- strings são externalizadas desde plataforma local; locale do Studio e `Variant.locale` do
  consumidor são conceitos separados;
- animação respeita reduced motion e nunca é necessária para compreender
  mudança de estado.

### 8.10 Performance de UI

Nenhum parse grande, canonicalização, diff de imagem ou layout de grafo pesado
roda no UI isolate. Em Dart Native, CPU work medido pode usar worker isolate; em
web, usa Web Worker/adapter compatível ou processamento incremental, pois
Flutter web não oferece a mesma semântica de isolates nativos.

Journey Map virtualiza nodes/edges fora do viewport, usa cache bounded por
digest e separa semantic zoom de rebuild do documento. Performance é validada
em profile/release, nunca inferida de debug mode.

---

## 9. Execution runtime e Sessions

### 9.1 Definição

O execution runtime prepara ou anexa o app real a uma `Session`.

Componentes:

| Componente | Papel |
|------------|-------|
| App Adapter | controle/observação opt-in dentro do app |
| Runner | processo/browser/device lifecycle |
| Transport | mensagens, sem semântica |
| Target Provider | alocação local/remota |
| Simulator | fronteira externa não HTTP |
| Backend Gateway | fronteira HTTP seletiva |

### 9.2 Control plane

Decisão:

- JSON-RPC 2.0;
- namespace versionado;
- Studio ↔ Host por WebSocket loopback autenticado durante `dev`;
- CLI one-shot in-process; attach de CLI por Host RPC;
- Host ↔ processo filho por stdio quando o lifecycle for parent-owned;
- Studio page ↔ target web por `postMessage`; o Host autoriza commands e o
  Studio atua apenas como bridge tipado para o App Adapter;
- MCP não é protocolo runtime;
- artifacts grandes via HTTP/arquivo por handle scoped, digest e TTL;
- protocolo nunca transporta path arbitrário ou secret materializado.

Handshake negocia `protocolVersion`, capabilities, `sessionId`, principal,
limits e heartbeat. WebSocket valida Origin e token efêmero; `postMessage`
usa `targetOrigin` exato, valida `event.origin` e `event.source`, associa nonce
à Session e rejeita wildcard, replay, payload fora do schema e mensagem acima
do limite. O iframe roda em origin separado do Studio.

Métodos conceituais:

```text
initialize
reset
openCheckpoint
dispatchInput
injectEvent
setRuntimeConfiguration
requestCapture
dispose
```

### 9.3 Lifecycle

```text
allocated -> starting -> ready -> active -> stopping -> terminated
                |          |        |           |
                +----------+--------+-----------+--> failed

active -> resetting -> ready
active -> reconnecting -> active
```

Comandos mutáveis:

- `sessionId`;
- `operationId`;
- precondition;
- idempotência declarada;
- sequence monotônica;
- timeout e cancellation.

Cada command produz exatamente um terminal result (`succeeded`, `failed` ou
`cancelled`) e pode produzir progress events ordenados. Reconnect usa cursor de
evento e snapshot; nunca reaplica command mutável sem idempotency contract.

### 9.4 Checkpoints

Estratégias:

- `seedBeforeBoot`;
- `restoreSanctionedState`;
- `navigate`;
- `recognize`;
- `applyGatewayPreset` (quando Gateway disponível).

Sem acesso arbitrário a internals.

### 9.5 ApplicationBootstrapPolicy

Apps reais podem inicializar configuração remota, feature flags, app attestation,
analytics, update checks, captcha ou outros SDKs antes de alcançar APIs de
negócio. Redirecionar somente a base URL não torna esse bootstrap isolado.

`ApplicationBootstrapPolicy` classifica cada dependência declarada:

| Tratamento | Significado |
|------------|-------------|
| `required` | precisa ficar ready por adapter controlado |
| `allowlisted` | egress explícito permitido, com host e finalidade |
| `simulated` | adapter determinístico substitui a dependência |
| `disabled` | inicialização omitida de forma sancionada |

Regras:

- `targetEnforced` falha antes do launch quando resta dependência
  `allowlisted` incompatível ou não declarada;
- `backendMode: isolated` sem adapter de contenção resulta no nível
  `gatewayOnly`, não em claim de egress total;
- dependência não declarada nunca recebe egress por uma policy gerada pelo
  Abel; em target não contido, aparece como risco não avaliado;
- policy, readiness e adapters efetivos entram no `ExecutionFingerprint`;
- a sequência default é hybrid → controlar bootstrap → Gateway isolated →
  targetEnforced quando a claim exigir e o adapter puder provar;
- production bootstrap continua sendo a fonte funcional do app.

`RuntimeConfigurationOverlay` transporta apenas overrides efêmeros e não
secretos, por launch define, arquivo temporário restrito ou App Adapter. Ele
tem precedência explícita sobre configuração remota somente no target de
tooling e desaparece no cleanup.

### 9.6 Estratégias de execução

| Estratégia | Uso |
|------------|-----|
| Target existente | menor impacto; launch/attach |
| Flutter web target | Run interativo plataforma local |
| Embedded | componentes/superfícies compatíveis |
| Sidecar local | processo externo controlado |
| Host runner | Android emulator; outros hosts exigem ADR e gate próprios |
| Remote runtime | web/Android remote execution por request/plano assinado e Job efêmero |

### 9.7 Flutter App Adapter

- única interface app-facing;
- sem annotations/build_runner obrigatórios;
- sem singleton global;
- múltiplas engines possíveis;
- `Semantics.identifier` para automação controlada;
- texto e `Key` não são selector público principal.

O consumidor expõe uma factory/bootstrap neutra reutilizada pelo entrypoint de
produção e pelo `ConsumerLayout.toolingEntrypoint`. Somente o entrypoint de
tooling importa `flutter_app_adapter`; duplicar a inicialização do app é proibido.

plataforma local usa Flutter web full-page em iframe de origin separado. Host-native entra no
web/Android.

O App Adapter expõe apenas comandos semânticos e observações necessárias. Ele
não oferece service locator, leitura arbitrária de provider/container, eval,
reflection de widget tree ou acesso genérico a estado interno. Selectors de
automação públicos usam `Semantics.identifier`; `Key`, texto traduzido e ordem
visual não são contrato runtime.

### 9.8 Render plane

Control plane e render plane são separados.

Render declara:

- viewport;
- DPR;
- transform;
- input mode;
- capture support.

### 9.9 Concorrência e ownership de Session

Uma `Session` é um actor lógico: commands mutáveis são serializados por
`sessionId`; queries podem concorrer sobre snapshots imutáveis. Estado não é
compartilhado entre isolates/processos. Eventos recebem sequence monotônica por
sessão e timestamp monotônico; timestamp civil é metadado, nunca ordenação.

O Host possui o scope da Session e seus filhos. Cancelar ou encerrar a Session:

1. rejeita novos commands;
2. cancela operações cooperativas;
3. para input/capture;
4. encerra target e Gateway com deadline;
5. revoga tokens e handles;
6. preserva trace sanitizado e marca cleanup incompleto quando necessário.

Trabalho CPU-bound medido sai do UI isolate. Isolate é otimização interna, não
boundary de segurança; processo continua sendo o boundary do Gateway e de
execução de código não confiável.

### 9.10 Remote Session e device farm

Uma `RemoteRun` usa state machine persistente:

```text
queued -> scheduled -> provisioning -> running -> uploading
   |          |              |            |           |
   +----------+--------------+------------+-----------+
                    failed | cancelled | unknown
                                      ou succeeded após upload validado
```

Lease/generation tornam a tentativa exclusiva; heartbeat renova somente a
generation corrente. Batch pode ser retentado após cleanup. Sessão interativa
perdida termina `unknown`, porque repetir input humano não é idempotente.

Cada tentativa materializa namespace/Job próprios. Worker recebe JWS do plano,
capability JWT curto e artifacts por digest; não recebe acesso ao banco. Web
interativo usa target direto atrás do gateway. Android usa emulator/ADB e
scrcpy H.264/control; WebCodecs decodifica quando suportado e o fallback por PNG
é explicitamente read-only. Ticket é autenticado no primeiro frame WSS, nunca
em query string.

Todo terminal cria cleanup durável de namespace/Job/Secret/volume/route/lease.
Retry permanece bloqueado enquanto existir cleanup debt; DELETE 404 é sucesso
idempotente, mas o reconciler só confirma após observar namespace ausente.

---

## 10. Backend Gateway

### 10.1 Status

**Decisão:** bounded context oficial, opt-in, implementado em Dart.

É a capacidade necessária para uma distribuição futura substituir
operacionalmente o gateway legado.

### 10.2 Responsabilidades

1. interceptar requests dos upstream groups configurados;
2. resolver `mock`, `passthrough` ou `denied`;
3. aplicar GatewayPreset e isolation;
4. responder fixture pelo mesmo pipeline usado em verify;
5. manter runtime mutável da sessão;
6. registrar traffic sanitizado;
7. capturar hints de sessão allowlisted;
8. executar probe de contrato opt-in;
9. reportar status ao Studio/CLI.

### 10.3 Fora de responsabilidade

- definir Journey;
- aprovar evidence;
- copiar OpenAPI;
- controlar UI do app;
- hospedar produção;
- guardar secrets em release;
- substituir simulator de hardware não HTTP.

### 10.4 Arquitetura interna

O Gateway roda como **sidecar Dart em processo separado por GatewaySession**,
iniciado e encerrado pelo Host/Runner. O processo isola sockets, credenciais,
estado e falhas do Studio e de outras sessões. Cada processo recebe um
listener/porta e runtime state próprios; não existe singleton global entre
sessões. Otimizar futuramente para processo compartilhado exige ADR, medição e
isolamento equivalente provado por conformance.

Data plane e control plane são separados:

- **data plane**: tráfego HTTP do app;
- **control plane**: status, apply preset, reset, verify e traffic.

O control plane usa transporte local autenticado por token efêmero ou stdio.
Ele não compartilha o listener do app por conveniência.

`backendMode: isolated` restringe o egress **do sidecar** e o comportamento das
requests que chegam a ele. Bloquear conexões que o app faça fora do Gateway é
responsabilidade do `NetworkContainmentDescriptor` e do adapter do target.

```text
Studio / CLI / Application Services
                 |
                 v
       Gateway control plane
                 |
                 v
HTTP listener
     |
     v
RequestNormalizer
     |
     v
RouteRegistry -----> Active GatewayScope / GatewayPreset
     |                         |
     |                         v
     |                   RoutingTable
     v
Policy + Resolver
  |        |        |
  |        |        +--> deny
  |        +-----------> UpstreamProxyPort
  +--------------------> MockHandlerPort
                              |
                              v
                         MockResponse

todos outcomes -> TrafficSink -> SessionTrace projection
```

Ports públicos:

- `UpstreamProxyPort`: passthrough para upstream allowlisted;
- `MockHandlerPort`: resposta mock usada por data plane e verify;
- `RemoteConfigProvider`: resolve aliases e status de upstream;
- `GatewayCatalogPort`: lê scopes/presets/routes compilados do content root;
- `TrafficSink`: persiste projeção sanitizada;
- `SessionCapturePort`: captura apenas headers/hints allowlisted.

### 10.5 Algoritmo de decisão

Para cada request:

1. validar listener e GatewaySession;
2. normalizar method, path e upstream group lógico;
3. avaliar policy de interceptação;
4. localizar endpoint ou prefixo explicitamente declarado no registry;
5. se Gateway/GatewayScope está inativo:
   - passthrough somente quando o modo é `hybrid` e a rota/prefixo possui
     upstream allowlisted e sua policy permite passthrough;
   - deny nos demais casos;
6. se a rota pertence ao GatewayScope ativo, aplica ao GatewayPreset e routing é
   `mock`:
   - aplicar latency/failure configuradas;
   - executar mock handler;
7. caso contrário:
   - passthrough somente se a rota compilada declarar `passthrough`, o modo for
     `hybrid` e o upstream for permitido;
   - deny em qualquer outro caso;
8. sanitizar e emitir `TrafficEvent`;
9. decorar response com metadado de diagnóstico quando permitido.

Policies explícitas cobrem os comportamentos especiais do legado sem
hardcoding no core:

- `localOnly`: quando incluída no preset/scope ativo, sempre mock local; sem
  plano ativo ou handler disponível, deny — nunca passthrough;
- `mockWhenOverridden`: mock condicional somente quando scope, preset,
  `appliesTo` e overrides efetivos coincidirem; senão passthrough em hybrid;
- `upstreamOnly`: passthrough de todas as rotas allowlisted do preset;
- `catalogControlled`: algoritmo normal de RoutingTable.

Nenhuma route recebe uma dessas policies por nome/path implícito. A
distribuição exemplo declara a compatibilidade no catálogo.

### 10.6 Invariantes

- exatamente zero ou um GatewayScope ativo por GatewaySession;
- route só mocka se `appliesTo` contém o GatewayPreset;
- GatewayPreset compila plano completo, sem merge cego com estado anterior;
- outro GatewayScope não herda routing;
- verify usa o mesmo mock handler;
- passthrough nunca ocorre em `isolated`;
- rota desconhecida que chega ao Gateway é `denied`, nunca proxy implícito;
- uma GatewaySession não lê estado, token ou traffic de outra;
- upstream de produção é proibido por policy;
- URL/token de upstream nunca entra em manifest;
- log nunca guarda authorization por default;
- sampler/verify nunca chama fixture builder fora do MockHandlerPort;
- trocar preset substitui o plano completo e reseta runtime anterior;
- `upstreamOnly` continua sujeito à allowlist e nunca funciona em isolated.

Matriz de isolamento:

| Route policy | Mock quando | Senão |
|--------------|-------------|-------|
| `catalogControlled` | scope ativo + route no preset + routing mock | passthrough somente em hybrid/allowlist; caso contrário deny |
| `mockWhenOverridden` | condições do preset e overrides satisfeitas | passthrough somente em hybrid/allowlist |
| `localOnly` | scope ativo + route no preset + handler declarado | deny; nunca passthrough |
| `upstreamOnly` | nunca | passthrough somente em hybrid/allowlist |
| fora do registry | nunca | deny |

### 10.7 GatewayPreset

`GatewayPreset` declara:

- ID e descrição humana;
- GatewayScope;
- endpoints aplicáveis;
- fixture refs;
- initial runtime state;
- FaultProfile;
- dependencies;
- reset policy.

Compilação:

```text
GatewayPreset + GatewayRoute + Fixture
      -> CompiledGatewayPlan (digest)
      -> RoutingTable
```

### 10.8 Runtime mutável

Estado mutável pertence à GatewaySession:

- workflow state;
- epochs/polls;
- resources criados;
- operações canceladas;
- counters;
- clock/seed quando necessário.

Trocar preset encerra/reseta runtime anterior.

O estado não altera fonte autoral. Se participar de evidence, seu snapshot e
digest entram no `ExecutionFingerprint`.

### 10.9 FaultProfile

Pode declarar:

- latency fixa/range determinístico;
- timeout;
- status forçado;
- body de erro;
- disconnect;
- retry sequence.

Random sem seed é proibido quando a operação produz evidence.

### 10.10 Verify ≡ API

`VerificationReport` é produzido por request sintética através do pipeline normal:

```text
Verify request
  -> resolver
  -> mock handler
  -> serializers/adapters
  -> response bytes
```

O Studio pode formatar JSON para leitura, mas preserva digest dos bytes
originais.

Preview e data plane consomem o mesmo `ResolvedResponse`. Testes de contrato
chamam o Gateway real e comparam status, headers selecionados e body bruto.
Headers dinâmicos de transporte são excluídos por policy explícita. Respostas
stateful são verificadas a partir do mesmo estado inicial e da mesma sequência
de requests.

### 10.11 Traffic e diagnóstico

`TrafficEvent` mínimo:

- sequence;
- session/gateway IDs;
- timestamp monotônico;
- method;
- route template (não URL sensível);
- endpoint ID;
- outcome;
- status;
- duration;
- request/response sizes;
- error code;
- redaction summary.

Body e headers são omitidos por default. Captura explícita exige policy.

Quando habilitado apenas para tooling, o response pode expor:

| Header | Uso |
|--------|-----|
| `X-Gateway-Mode` | `mock`, `passthrough` ou `denied` |
| `X-Gateway-Preset` | ID opaco do GatewayPreset ativo |

Esses headers são diagnóstico, não contrato do backend consumidor. Podem ser
removidos por policy e nunca carregam URL, account, token ou payload.

### 10.12 UpstreamProfile e sync

`UpstreamProfile` usa nomes lógicos. URLs concretas ficam em configuração
local; credenciais ficam somente no credential store ou em memória.

Providers de sync implementam port:

```text
RemoteConfigProvider
  -> resolve(logical keys)
  -> validate(no localhost loop, no missing required)
  -> store aliases + credential handles
```

Um provedor de configuração remota pode ser o primeiro adapter; o domínio usa apenas a port genérica.

Existem dois lados independentes:

| Lado | Responsabilidade |
|------|------------------|
| Application overlay | apontar APIs selecionadas ao listener local |
| UpstreamProfile | mapear os mesmos aliases para upstreams não produtivos |

O app não lê estado local do Gateway e o Gateway não persiste alteração no
serviço remoto. `GatewayEndpointResolver` gera o overlay por target.

Status de sync:

| Status | Significado |
|--------|-------------|
| `missing` | provider/config local ausente |
| `empty` | provider respondeu sem aliases |
| `incomplete` | alias obrigatório ausente |
| `invalid` | URL, scheme, loop local ou policy inválida |
| `ready` | aliases exigidos validados e armazenados |

Um sync pode aceitar intencionalmente aliases já apontados ao gateway somente
com flag explícita equivalente a `allowLocalGateway`; loops de proxy continuam
proibidos.

### 10.13 Sessão capturada

Em hybrid/probe, o Gateway pode capturar headers e hints allowlisted:

- TTL curto;
- memória por default;
- persistência opt-in e protegida;
- redaction;
- nunca em release/CAS público;
- invalidada ao trocar target/account context;
- principal informado no Studio.

TTL default recomendado: 30 minutos. Params manuais e estáveis não carregam
headers de autenticação capturados.

### 10.14 Contract probe

Probe:

- usa `BackendContract` + `ContractProbePlan`;
- filtra routes pelo GatewayPreset;
- ordena dependências;
- extrai parâmetros de responses anteriores;
- usa sessão capturada com grant;
- é ferramenta de Studio/CLI, não Review mode;
- não transforma response remota em fixture automaticamente.

Importar uma response produz draft sanitizado, nunca fonte autoral automática.

`ContractProbePlan` pode declarar:

| Campo | Uso |
|-------|-----|
| `order` | ordem base |
| `after` | dependência por route ID |
| `extract` | parâmetro → path na response anterior |
| `requestBodyTemplate` | body para POST/PATCH |

`extract` aceita path, lista de paths candidatos ou `{from, path}`. A resolução
de parâmetros segue:

```text
manual
  > sessão capturada com TTL
  > parâmetros estáveis locais e gitignored
  > defaults do GatewayScope
```

É proibido manter lista fixa de routes que ignore `appliesTo` do preset ativo.
Probe não se torna documentação, não muda routing do app e não cria fixture
automaticamente.

### 10.15 Subconjunto HTTP inicial

Antes de habilitar hybrid, o contrato suportado deve ficar fechado:

- HTTP/1.1 request/response;
- methods e status declarados no registry;
- bodies com limites e streaming bounded;
- cookies preservados somente quando allowlisted;
- remoção de hop-by-hop headers;
- redirects bloqueados ou revalidados contra a allowlist;
- compressão tratada sem alterar silenciosamente a claim de verify.

Gateway containment não promete CONNECT/MITM TLS, WebSocket, gRPC ou proxy HTTP/2
end-to-end. Multipart e streaming prolongado exigem teste/limite próprios.
Request fora do subconjunto falha de forma explícita.

### 10.16 Pareamento host

Gateway isolado escuta em loopback/port explícito para web.

Esse pareamento prova `networkContainment: gatewayOnly`. Ele não prova que o
browser ou app não alcançou outros hosts. Claim `targetEnforced` requer adapter
de contenção e teste negativo observando a fronteira de rede do target.

A paridade web/Android deve oferecer bootstrap host-native:

- Android: `adb reverse` quando compatível; `10.0.2.2` como fallback;
- TLS local quando necessário;
- port conflict;
- firewall;
- cleanup;
- dry-run e undo.

Reverse proxies locais de terceiros não são requisitos canônicos. Um adapter de reverse proxy pode
usá-los, mas a implementação padrão deve preferir servidor Dart e configuração
mínima.

### 10.17 Integração com Sessions

`ExecutionTarget` referencia `GatewayConfiguration`.

Ao iniciar:

1. resolve ApplicationBootstrapPolicy e RuntimeConfigurationOverlay;
2. Application Service solicita ao Runner um sidecar e uma GatewaySession;
3. aplica GatewayPreset se solicitado;
4. injeta endpoint/overlay por launch config ou App Adapter;
5. inicia app e valida bootstrap readiness;
6. liga TrafficEvent ao SessionTrace;
7. cleanup encerra Gateway e remove overlay/state efêmero.

Sessions e Gateway não chamam um ao outro diretamente. A camada de aplicação
coordena ambos e mantém a direção das dependências.

### 10.18 ExecutionFingerprint

Sempre inclui:

- DistributionDescriptor ID/version e core version;
- Application/ExecutionTarget/LaunchProfile;
- ApplicationBootstrapPolicy digest;
- adapters e readiness de bootstrap;
- RuntimeConfigurationOverlay digest sanitizado;
- NetworkContainmentDescriptor e resultado de enforcement;
- backend mode (`none`, `isolated` ou `hybrid`);
- toolchain e platform.

Quando Gateway ativo, acrescenta:

- CompiledGatewayPlan digest;
- RoutingTable digest;
- FaultProfile digest;
- runtime state digest quando capturado;
- upstream logical set digest (sem URLs);
- gateway version;
- network policy digest.

### 10.19 Playbook de extensão de GatewayScope

Ordem canônica para adicionar um scope:

1. declarar ID, grupo, routes, presets e policies no catálogo autoral;
2. implementar MockHandlerPort e fixtures sintéticas;
3. declarar GatewayPreset completo, `appliesTo`, routing e reset policy;
4. implementar runtime mutável somente quando o fluxo exigir;
5. provar verify ≡ API pelo data plane real;
6. ligar ação de execução ao ScenarioExecutionBinding;
7. escrever living docs e ReviewGuide em linguagem de produto;
8. declarar ContractProbePlan quando necessário;
9. executar conformance e testes específicos do scope;
10. validar isolation, hygiene, distribuição e remoção.

Escolha o padrão técnico pelo comportamento, não pelo domínio:

| Necessidade | Padrão |
|------------|--------|
| HTTP simples + verify | handler + fixtures + preset estático |
| poll/materialização | runtime epoch + clock/seed |
| workflow mutável | GatewaySession state + contrato por etapa |
| cadeia remota | ContractProbePlan com `after`/`extract` |
| múltiplos aliases | registry por prefixo + isolation |
| checklist customizado | ReviewGuide + catálogo de colunas |

Checklist de aceite:

- [ ] ID único e descoberta no grupo correto;
- [ ] zero/um scope ativo; ativar este desativa o anterior na sessão;
- [ ] verify não inclui route fora de `appliesTo`;
- [ ] upstreams concretos vêm de sync/config local, nunca do catálogo;
- [ ] docs abrem na Journey/Scenario Sheet;
- [ ] ReviewGuide descreve jornada, não endpoint/JSON;
- [ ] probe é filtrado pelo preset;
- [ ] conformance e testes do scope passam;
- [ ] nenhuma fonte, secret, cache ou binário aparece fora dos roots permitidos.

### 10.20 Anti-padrões do Gateway

| Erro | Correção |
|------|----------|
| routing mock em todo o catálogo | mock somente nas routes do preset ativo |
| dois scopes ativos na mesma sessão | exclusividade por GatewaySession |
| verify/sampler chama builder direto | request pelo mesmo MockHandlerPort/data plane |
| merge de estado antigo ao aplicar preset | CompiledGatewayPlan completo + reset |
| URL concreta hardcoded | UpstreamProfile + sync/config local |
| lista fixa de routes no probe | filtro por preset e `appliesTo` |
| mock condicional sem overrides efetivos | passthrough allowlisted ou deny |
| fixture com dump ou PII | contrato e valores sintéticos |
| estado runtime vira fonte autoral | snapshot/digest apenas como evidence |
| proxy implícito de rota desconhecida | deny |
| mutação de routing em Review | ação somente em Run/Authoring com grant |
| configuração/agente de distribuição na raiz do consumidor | tooling entrypoint da distribuição |

---

## 11. Integração com backend e contratos

### 11.1 BackendContract

Relaciona Journey/Transition a contratos externos:

- OpenAPI + operationId;
- AsyncAPI + operation/channel/message;
- URI + revision/digest;
- ownership.

A plataforma não copia o contrato como segunda fonte.

### 11.2 Estratégias de backend por target

| Estratégia | Uso |
|------------|-----|
| fake do consumidor | reutilizar seam existente |
| sandbox controlado | ambiente externo dedicado |
| Gateway isolated | determinismo da fronteira roteada ao Gateway |
| Gateway hybrid | sessão real + subset controlado |
| contract probe | comparar remoto sem rotear app |

Consumidor pode usar fake próprio; Gateway não é monopólio.

### 11.3 Relação com Journey

Uma Transition pode relacionar:

```text
input humano
  -> command semântico
  -> BackendContract
  -> outcomes
  -> Scenario destino
```

Essa relação explica; não transforma endpoint em Journey.

### 11.4 Tracing

W3C Trace Context/OpenTelemetry podem correlacionar SessionTrace e backend.

- opcional;
- sanitizado;
- policy de acesso;
- sem payload de produção por default.

### 11.5 Checklist de Qualidade

`ReviewGuide` pode conter steps em linguagem de produto e referenciar um
`ScenarioExecutionBinding`:

```text
OpenExecutionBinding(bindingRef)
Observe(criteriaRef)
Capture(evidencePolicyRef)
```

O binding é autoral; o Application Service resolve GatewayPreset, checkpoint e
target no momento da execução. `ReviewGuide` continua narrativa e não carrega
comando operacional. No Review mode, `OpenExecutionBinding` é uma ação
`ephemeral`: materializa exatamente o binding concedido em target seguro, sem
expor escolha ou alteração posterior de routing.

Regras de copy:

- formato preferido: `Ao …, vejo …` ou `Ao …, consigo …`;
- textos visíveis do app entre aspas retas;
- nenhum endpoint, JSON, variável, classe, Swagger/OpenAPI ou detalhe de
  infraestrutura no texto de produto;
- a preparação efêmera vive no binding (`applyGatewayPreset`), não na narrativa
  nem em um controle livre de Review.

Capacidades:

- toggle de cenário resolve binding e preset;
- captura/evidência local segue EvidencePolicy;
- export gera checklist sem secret ou detalhe operacional;
- colunas customizadas são schema autoral, não campos ad hoc da UI;
- envio de push permanece plugin opcional de distribuição.

---

## 12. Documentação viva e evidência

### 12.1 Quatro camadas

| Camada | Conteúdo |
|--------|----------|
| Intenção | objetivo, critérios, IntentReference |
| Implementação | sources, widgets, contratos, GatewayPreset |
| Evidência | build, trace, capture, verify |
| Decisão | approval, finding, waiver |

### 12.2 Unidade de leitura

Journey Sheet e Scenario Sheet são rotas estáveis. Painéis são projections.

### 12.3 Freshness

Dependências explícitas:

```text
source/config/fixture/routing/toolchain
        -> fingerprint
        -> evidence freshness
```

Mudança relevante marca evidence stale. Mudança desconhecida degrada
conservadoramente.

### 12.4 Captura visual

- PNG lossless é master da tela;
- device chrome é vetorial;
- thumbnails são derivados;
- renderer e target entram no fingerprint;
- recapture não aprova;
- web não é nativo.

### 12.5 Identidades de captura

- blob digest;
- pixel digest;
- ExecutionFingerprint.

### 12.6 Evidence Gateway

Evidence de Gateway pode incluir:

- VerificationReport;
- traffic slice sanitizado;
- routing digest;
- CompiledGatewayPlan digest;
- resultado de contract test.

Nunca inclui secret ou raw auth.

### 12.7 Regras de authoring e import legado

O content root aceita documentação textual leve: Markdown, texto e HTML
sanitizado. PNG, APK, MP4 e outros binários não são fonte versionada de
documentação; evidência visual pertence ao artifact store/CAS.

HTML importado do console legado:

- entra como draft, nunca como verdade automática;
- recebe ID estável de guia e navegação/TOC normalizados;
- não executa script remoto;
- usa referências de artifact para screenshots;
- é ligado a Journey/Scenario por binding explícito;
- pode ser convertido para Markdown sem alterar a fonte original até revisão.

Evidência de Qualidade pode mencionar o nome de um artifact, mas não versiona
`<img>` ou binário dentro do guia.

---

## 13. Release e entrega

### 13.1 Release

Manifest imutável e content-addressed que referencia:

- CatalogManifest;
- source snapshot;
- journeys/scenarios;
- mock/gateway documents;
- targets;
- builds;
- artifacts;
- evidence;
- DistributionDescriptor digest e core version;
- toolchain;
- policies.

O digest não é embutido no próprio manifest.
Config filename, content root e command alias entram como proveniência, não
alteram sozinhos o digest semântico de Journey/Scenario.

Release v1 usa `sha256` sobre JCS do manifest sem o próprio digest. Isso prova
integridade e identidade. `ReleaseAttestation` opcional assina o digest e
declara signer, key ID, algoritmo, timestamp, policy e subject; assinatura não é
Approval e Approval não substitui assinatura.

Uma claim de reprodução declara, no mínimo, runtime fidelity, backend mode,
network containment, bootstrap assessment, toolchain, source revision,
artifacts e policies. Campo ausente degrada a claim; não recebe default
otimista.

### 13.2 Hybrid na release

Release pode declarar que uma evidence foi produzida em hybrid, mas:

- não embute upstream URL/token;
- não afirma determinismo;
- registra network policy e logical upstream digest;
- seal policy default não a usa como única evidência de reproducibilidade.

### 13.3 PublicationView

Combina Release por digest com approvals/findings/waivers externos. Decisão
nova não muta release.

### 13.4 Bundle

`ReleaseBundle` empacota release e artifacts. Continua verificável sem Git,
Flutter SDK do consumidor ou serviço hosted.

Hybrid interativo não precisa funcionar no bundle compartilhado; Review deve
explicar essa limitação.

### 13.5 Publicação transacional

1. staging;
2. validar media type/tamanho/digest;
3. gravar blobs idempotentes;
4. validar refs;
5. gravar manifest;
6. mover channel atomicamente.

### 13.6 Modos de entrega de release

| Modo | Escopo |
|------|--------|
| Local | obrigatório; offline após deps |
| Bundle estático | Review/fixtures compatíveis |
| Hosted | opcional; colaboração hosted control plane e runtime remoto remote execution implementados, com promoção condicionada aos gates §27.6 |

### 13.7 Distribution do Kit

Release de produto e Distribution do Kit são contratos distintos.
`DistributionReleaseManifest` registra `ModuleCatalog`, Modules, Profiles,
components, entrypoints e ownership de files. CLI é obrigatória; Host, Gateway
e Studio são components condicionais às surfaces dos Modules do profile.

O único reader/installer só ativa o bundle após validar JCS/digest,
paths, catálogo físico/semântico, Module ownership e correspondência entre
profile/component/file. Bundles `full-local` e enxutos precisam de rebuild
byte-idêntico, verify, install/update/rollback. Module solicitado mas não
empacotado falha antes de iniciar component.

---

## 14. Adoção e integração do consumidor

### 14.1 Trilhas

| Trilha | Mudança | Valor | Limite |
|--------|---------|-------|--------|
| Documentar | config + docs | Journey Map/sheets | sem runtime |
| Pré-visualizar | `flutter_preview` + factory real anotada | thumbnails estruturais no Journey Map | sem prova host-native |
| Executar | LaunchProfile | Run manual | sem checkpoint |
| Controlar app | App Adapter | checkpoint/eventos | capabilities declaradas |
| Controlar backend | Gateway config | preset/verify/traffic | policy de rede |
| Comprovar | CI/policies/targets | evidence/gates | maior custo |

Não são enum canônico; capabilities reais governam.

### 14.2 Integração isolada

Default:

- nenhum import do Flutter App Adapter no entrypoint de produção;
- composition root de tooling;
- fixtures/simulators/gateway config fora das features;
- nenhuma annotation obrigatória;
- generated em diretório ignorado;
- dry-run antes de patch.

Documentar e Review precisam funcionar sem editar `pubspec.yaml`, workspace,
lockfile ou código do app. Controle avançado usa preferencialmente um
entrypoint de tooling definido pelo `ConsumerLayout`, como
`tool/target_main.dart` ou `tool/helix_main.dart`. Ele importa
`flutter_app_adapter` e uma `ConsumerAppFactory` pública e neutra. O entrypoint de
produção reutiliza a mesma factory, mas não conhece a plataforma.

Pré-visualizar é opt-in e pode acrescentar `flutter_preview` fora do grafo do
entrypoint de produção. `AutoPreview` reutiliza a factory real e não autoriza
uma implementação paralela da tela. O provider não exige App Adapter, Session,
Gateway ou Android.

### 14.3 Reutilização antes de autoria

Pode referenciar:

- screenshots/goldens;
- integration/E2E tests;
- deep links;
- fake servers;
- fixtures;
- OpenAPI/AsyncAPI;
- accessibility IDs.

Importer produz artifact/ref/draft; nunca verdade automática. Testes existentes
permanecem em seu runner original e entram por `EvidenceProvider`; não são
reescritos para criar uma segunda suíte.

### 14.4 Reversibilidade

`init`, migration e detach:

- dry-run;
- patch exato;
- ownership de arquivos;
- não apaga arquivo editado;
- relatório de remoção;
- upgrade separado da release do consumidor.

### 14.5 Backend Gateway adoption

Sequência default:

1. schema/config apenas;
2. launch de target existente, sem Gateway;
3. hybrid local para APIs selecionadas;
4. classificar e controlar dependências de bootstrap;
5. isolated + `targetEnforced` quando não restar egress não declarado;
6. host-native;
7. distribuição operacional com paridade do legado.

`doctor --require gateway.hybrid` transforma ausência em erro de CI quando o
projeto escolher essa requirement.

### 14.6 Monorepos e múltiplas aplicações

`Workspace` é first-class e pode declarar várias `Application`. Cada aplicação
possui root, toolchain, launch profiles, execution targets e bindings próprios,
enquanto Journey, referências e GatewayScopes podem ser compartilhados de
forma explícita.

O CLI sempre aceita `--application`; omissão só é válida quando existe uma
única aplicação ou um default declarado. Detecção de Pub workspace, monorepo
misto ou repositório simples é read-only e não adiciona membros ao workspace
sem patch e `--apply`.

Uma `Session` pertence a uma Application. Uma Journey pode ligar cenários de
Applications diferentes, mas a transição cria boundary explícito de sessão,
target e fingerprint. Orquestração simultânea de múltiplos apps exige capability
própria; nunca é inferida do grafo.

### 14.7 Golden path de desenvolvimento

O fluxo default do consumidor precisa caber nestas operações:

```text
workspace validate
workspace compile
workspace doctor --application primary
workspace dev --application primary
workspace session start <binding-ref>
workspace capture
workspace release build
```

Adoção ciclo de distribuição acrescenta, antes do fluxo:

```text
workspace init --dry-run
workspace init --apply
```

Uma distribuição pode projetar o mesmo fluxo:

```text
helix validate
helix dev --application primary
```

Esses aliases invocam os mesmos Application Services e retornam os mesmos exit
codes e JSON do CLI `workspace`.

`init` detecta estrutura e propõe `workspace.yaml`; não altera código sem
`--apply`. `dev` supervisiona Host, Studio, target, sidecars e cleanup como uma
operação única, exibe URLs/ports efetivos e preserva logs correlacionados. Se
algum processo já estiver saudável, ele é anexado ou reutilizado conforme
workspace/principal/policy, nunca duplicado silenciosamente.

O nível Documentar encerra aí. Para Run controlado, o consumidor adiciona o
Flutter App Adapter em entrypoint de tooling. Para Gateway, declara
GatewayConfiguration e GatewayPreset; não precisa editar URLs remotas a cada
sessão. CI usa os mesmos commands e machine output, sem Studio.

### 14.8 Seam de configuração de rede

O Gateway não pode depender de alteração manual e persistente em configuração
remota, arquivo de produção ou URL hard-coded por plataforma. Um
`GatewayEndpointResolver` resolve o endpoint local para cada ExecutionTarget:

1. launch-time define/config quando suportado;
2. dependency override no entrypoint de tooling;
3. adapter explícito para o mecanismo de configuração do consumidor.

`doctor` explica estratégia, valor efetivo, origem e undo sem revelar secret.
Android emulator e web são os adapters suportados ate remote execution; qualquer adapter iOS
ou desktop exige nova ADR. Endereços especiais não vazam para documentos
canônicos.

O resolver produz `RuntimeConfigurationOverlay`; não edita serviço remoto nem
fonte do consumidor. URLs lógicas podem ser sobrepostas, tokens não.

### 14.9 Testes existentes como evidência

Runners de UI automation, integration tests, golden tests e equivalentes implementam
`EvidenceProvider`.

O provider:

- referencia a fonte original por path/revision;
- executa ou importa resultado sem alterar a suíte;
- relaciona resultado a Scenario/Variant/ExecutionTarget;
- normaliza logs, screenshots e status como artifacts;
- registra toolchain e configuração no `ExecutionFingerprint`;
- não converte sucesso técnico em Approval.

---

## 15. Arquitetura física Dart/Flutter

### 15.1 Estratégia

Monólito modular com múltiplos executáveis e packages apenas nos boundaries de
publicação/runtime. O repositório usa **Pub Workspaces** e uma resolução
compartilhada; packages internos não podem ser alcançados por imports em
`lib/src` de outro package.

Separar package não cria bounded context. Cada BC mantém módulo, API interna e
testes próprios dentro de `experience_engine`; extração futura exige necessidade de
publicação, runtime incompatível ou owner/deploy independente.

### 15.2 Módulos lógicos

| Módulo | Conteúdo | Proibido |
|--------|----------|----------|
| Documents | schemas, parse, migrations | Flutter/I/O |
| Catalog | grafo, compile, queries | UI |
| Sessions | lifecycle, capabilities, trace | transports |
| Gateway | routing, presets, verify contracts | UI/secrets concretos |
| Evidence | digests, freshness, release | runners |
| Application | commands, queries, policies e orchestration | detalhes concretos/UI |
| Source | snapshots/bindings | provider APIs |
| Automation | diff/impact/context | SDK de LLM |
| Hosted | tenancy, collaboration, outbox, authz ports | HTTP/PostgreSQL concretos |
| Remote | scheduler, leases, cleanup e signed-plan policy | Kubernetes/scrcpy concretos |
| Protocol | DTOs/codecs/version negotiation | widgets/domain behavior |
| Infrastructure | fs/process/http/Git/providers | decisão de produto |

### 15.3 Estrutura física inicial

```text
<repository>/
├── ARCHITECTURE.md
├── pubspec.yaml                # Pub Workspace; publish_to: none
├── analysis_options.yaml       # strict casts/raw types + lints estáveis
├── schemas/
├── apps/
│   ├── studio/           # SPA Jaspr client-side; branding por distribuição
│   ├── workspace_cli/              # CLI Dart; executável `workspace`
│   ├── workspace_host/             # Host local Dart VM / supervisor
│   ├── gateway_sidecar/        # sidecar executável Dart
│   ├── hosted_control_plane/   # composition root hosted control plane
│   ├── remote_worker/          # worker remote execution sem acesso ao banco
│   └── remote_session_gateway/ # WSS/iframe/scrcpy por run
├── libs/
│   ├── experience_contracts/        # pure Dart: DTOs, codecs, protocol e refs
│   ├── experience_engine/           # pure Dart: domain, policies e app services
│   ├── execution_runtime/          # Dart VM: fs/process/http/Host/Gateway adapters
│   ├── studio_ui/        # Jaspr/HTML/CSS; sem domínio ou Flutter
│   ├── interaction_model/        # pure Dart: layout/interação/motion/windowing
│   ├── flutter_app_adapter/          # integração pública opt-in do consumidor
│   ├── flutter_preview/          # AutoPreview Flutter isolado
│   └── testing_support/          # conformance/fakes; nunca dependência de produção
├── examples/
│   └── sample_flutter/         # domínio hipotético
├── deploy/helm/control-plane/   # deploy portátil e remote RBAC opt-in
├── docs/security/              # threat models normativos
└── tests/
    ├── conformance/
    └── consumers/
        └── friction_flutter/
```

Dependências permitidas:

```text
experience_contracts <- experience_engine <- execution_runtime <- apps VM
       ^               ^
       |               +-------------- studio Host client
       +------------------------------ flutter_app_adapter

testing_support -> contracts/engine/runtime somente em dev/test
```

`studio` depende do client protocol e de modelos de apresentação, não de
`dart:io`. `flutter_app_adapter` não depende do engine nem do runtime. Cycles de
package são proibidos. API pública é exportada explicitamente; classes geradas
ou internas não vazam em assinatura pública.

### 15.4 Gateway sidecar

Contrato vive em `experience_contracts`/`experience_engine`; implementação em
`execution_runtime`.

O executável `apps/gateway_sidecar` é sempre um processo Dart separado **por
GatewaySession**, supervisionado pelo Host/Runner. Essa fronteira isola crash,
sockets, credenciais e estado e permite diferentes distribuições sem acoplar o
Studio. Um isolate pode ser usado internamente pelo sidecar, mas não substitui
o boundary de processo. PHP não é opção.

### 15.5 Consumidores mantidos

#### `sample_flutter`

- usa só APIs públicas;
- demonstra uma Journey hipotética;
- possui Gateway fixtures sintéticas;
- roda fora do workspace contra packages empacotados.

#### `friction_flutter`

- deliberadamente comum/acoplado;
- mede adoção, diff, tempo e remoção;
- não recebe friend APIs.

### 15.6 Distribuições, soft fork e hardfork

Uma distribuição compatível é um **soft fork por composição**:

- fixa versão/range do Abel;
- adiciona branding, policies, adapters, migrations e aliases;
- escolhe `ConsumerLayout`;
- não copia `experience_engine` ou `execution_runtime`;
- executa a conformance suite upstream;
- mantém schemas e machine contracts `workspace`.

Ela pode viver no consumidor, como `tools/helix`, porque contém integração
organizacional, não o motor inteiro.

Alterar invariantes, schemas ou semântica incompatível caracteriza hardfork.
Nesse caso:

- o fork vive em repositório próprio;
- recebe namespace e conformance próprios;
- não afirma compatibilidade automática com Abel;
- não é vendorizado silenciosamente dentro de `tools/`.

Um diretório ocupado por implementação legada só é substituído após o gate de
paridade. Durante a migração, legado e distribuição nova permanecem
distinguíveis; update nunca sobrescreve o legado in-place.

### 15.7 Regras de engenharia Dart/Flutter

- SDK/Flutter são pinados no CI e registrados no fingerprint; o documento não
  fixa patch version eterna;
- `dart format`, analyzer com strict casts/raw types e lints estáveis são gates;
- warning não é silenciado sem justificativa localizada e prazo quando
  temporário;
- domínio não usa `dynamic`; payload externo é validado antes de conversão;
- APIs async aceitam deadline/cancellation quando possuem efeito prolongado;
- stream/subscription/controller são fechados pelo owner;
- `BuildContext` não atravessa a View;
- widget não chama filesystem, processo, HTTP do Gateway ou credential store;
- `Semantics.identifier` e contratos de teste ficam próximos da superfície
  pública, sem reutilizar texto traduzido;
- code generation interna é permitida quando determinística, mas o consumidor
  não precisa de annotation/build step para simplesmente integrar o Abel;
- dependência nova declara owner, licença, função, alternativas, risco de
  supply chain e impacto VM/web antes de entrar no lockfile.

Import-boundary tests e analyzer verificam as dependências proibidas. Um
package verde isoladamente não prova a experiência: cada vertical fecha também
Studio, Host, target, Gateway quando aplicável e release artifact.

### 15.8 Topologia hosted/remote

O control plane roda non-root, root filesystem read-only, seccomp RuntimeDefault
e ServiceAccount sem automount. Quando remote está habilitado, recebe token
Kubernetes projetado de 600 segundos e signing key por Secret read-only. O
launcher relê o token a cada request para acompanhar rotação.

Jobs web seguem Pod Security restricted. Jobs Android usam RuntimeClass e
extended resource KVM em pool dedicado; não montam `/dev/kvm` por hostPath nem
solicitam `privileged`. Cada namespace recebe ServiceAccount sem token,
capability Secret imutável, trust ConfigMap imutável, emptyDir bounded e
NetworkPolicy deny-default. O ClusterRole não possui list/watch/update, mas RBAC
Kubernetes não restringe nomes em `create`; admission policy para
`workspace-run-*` é portanto gate obrigatório do cluster, não claim do chart.

Imagens e RuntimeClass são configuração de deploy, nunca tipos do domínio.
Todas as imagens OCI, system image Android e scrcpy server são pinados por
digest; tag mutável falha antes de materializar Job.

---

## 16. CLI, CI e agentes

### 16.1 CLI conceitual

plataforma local:

```text
workspace validate
workspace explain
workspace compile
workspace doctor [--require <capability>]
workspace dev
workspace session start <binding-ref>
workspace capture
workspace release build
```

ciclo de distribuição — adoção:

```text
workspace init [--dry-run|--apply]
workspace adoption-report
workspace detach --dry-run
```

Distribuição:

```text
workspace --distribution <path> --config <file> <command>
<alias> [--config <file>] <command>
```

Gateway:

```text
workspace gateway status
workspace gateway run
workspace gateway apply-preset <ref>
workspace gateway verify
workspace gateway traffic
workspace gateway sync
workspace gateway reset
workspace gateway doctor
workspace gateway bootstrap [--dry-run|--apply]
workspace gateway stop
```

Paridade de jobs de lifecycle:

| Job histórico | Contrato novo |
|---------------|---------------|
| configure/install | `gateway bootstrap --apply` + `gateway run` |
| update | update da distribuição + bootstrap idempotente |
| remove | `gateway stop` + undo explícito do bootstrap |
| verify | `gateway verify` + conformance suite |
| sync | `gateway sync` |
| provider status | `gateway status`/`doctor` com `missing`, `empty`, `incomplete`, `invalid` ou `ready` |
| deactivate all/reset isolation | `gateway reset` |

Pós-plataforma local:

```text
workspace source inspect
workspace source diff
workspace plan
workspace context export
workspace gate
workspace release seal
workspace publish
workspace mcp serve
```

Composição e AutoPreview:

```text
workspace modules list
workspace modules explain --module <id>
workspace modules doctor
workspace evidence collect-previews --application <id> --profile <id>
workspace dev --profile <id>
```

`modules`, version/init e operações de Distribution são
bootstrap commands. Os demais comandos/subcomandos são registrados somente se
o plano habilitar o Module que contribui sua superfície.

hosted control plane hosted:

```text
workspace auth login|logout|status
workspace workspace link|push|pull
workspace publish
```

Credentials ficam fora do workspace com permissão restrita. O hosted link
contém apenas URL/tenant/workspace e nunca bearer token. remote execution é acionado pelas
APIs/Studio sobre `RemoteExecutionRequest`; o CLI não expõe atalho que aceite
source ou comando arbitrário.

`workspace` é a identidade técnica do CLI. Distribuições podem instalar aliases,
mas scripts e saída JSON usam o contrato `workspace`.

`compile` produz `CatalogManifest`; `release build` produz Release/Bundle.
“Build do aplicativo consumidor” não é significado implícito de nenhum dos
dois. Um target pode declarar prepare/build command consumer-owned, executado
como processo não confiável e registrado no fingerprint.

### 16.2 Contrato operacional

- saída JSON versionada;
- exit codes estáveis;
- saída humana não parseável por scripts;
- commands mutáveis explícitos;
- `--apply`/confirmação;
- `--dry-run` sem escrita para operações de integração/bootstrap;
- correlation ID;
- versions efetivas;
- distribution ID, core version e config source efetivos;
- cancelamento;
- nenhuma escrita em queries.

Durante `dev`, o CLI supervisiona `workspace_host` e pode anexar ao processo
saudável do mesmo workspace/principal. Fora de `dev`, commands one-shot usam os
mesmos handlers in-process. Paridade é provada comparando resultado semântico,
exit code e machine output, não o transporte interno.

### 16.3 CI

Pipeline alvo:

```text
validate -> compile -> affected unit/widget/contract tests
         -> integration/security/performance gates por capability
         -> capture -> release build -> seal -> publish
```

Cada fase omite gates de capability ainda inexistente; não os marca como pass.
plataforma local executa seu pipeline completo sem hosted e sem IA.

Após `melos run check` construir Studio e Target release do consumer de
referência, o CI executa os verticais browser de Studio e Scenario Lab em
sequência. O gate de Scenario Lab usa `SCENARIO_LAB_SKIP_BUILD=1` somente para reutilizar esses
artefatos: serviços, Chrome, Target/Gateway, runs, Evidence, Quality,
currentness, cancelamento e cleanup continuam sendo executados. O gate ainda
reconstrói um Target alterado em diretório isolado e exige restauração byte a
byte de fontes, builds e estado temporariamente substituídos.

### 16.4 Agent Interface

Ordem:

1. CLI JSON;
2. ContextBundle;
3. MCP local read-only;
4. session tools;
5. drafts/proposals;
6. hosted por API/CLI autenticada; remote somente por request tipado.

Agente:

- pode explicar, diagnosticar e propor;
- não aprova, sela ou publica por default;
- não recebe repo inteiro;
- não transforma texto hostil em grant;
- não lê secrets do Gateway.

Agentes/skills específicos de uma distribuição ficam sob seu tooling entrypoint
(por exemplo, `tools/helix/.cursor/`), nunca na raiz do consumidor por efeito
colateral. Um agente de lifecycle executa o CLI com confirmação e mostra
resultado estruturado; não apenas escreve instruções e nunca cola configuração
remota, token ou authorization no chat.

---

## 17. Segurança e isolamento

### 17.1 Escopo e premissas

Local-first não significa input confiável. O Abel assume:

- a pessoa dona da conta do sistema operacional controla seus próprios
  arquivos, mas uma Journey, bundle, plugin ou repositório aberto pode ser
  malicioso;
- build e aplicativo consumidor são código não confiável em relação ao Host;
- target, iframe, upstream, provider, agent e artifact importado podem mentir,
  travar, consumir recursos ou tentar exfiltrar dados;
- loopback reduz exposição, mas não autentica sozinho outro processo local;
- digest prova integridade, não autoria;
- hosted/remote são fronteiras não confiáveis adicionais e seguem o threat
  model normativo `docs/security/hosted-remote-threat-model.md`.

Produção é upstream proibido. O núcleo não oferece flag de escape para
desabilitar essa policy; uma distribuição incompatível assume outro namespace
e conformance.

### 17.2 Data flow e trust boundaries

```text
 fontes/bundle não confiáveis
          |
          v  TB-1 parse, schema, path policy
 +----------------------+        TB-2 RPC        +----------------------+
 | Studio Jaspr         | <--------------------> | Workspace Host           |
 | origin/UI não confiável| token/origin/schema  | principal + authz    |
 +----------+-----------+                        +---+---------+--------+
            | TB-3 postMessage                       |         |
            v                                        |         |
 +----------------------+                   TB-4     |         | TB-5
 | target/app consumidor| <-------------------------+         v
 | código não confiável | overlay/adapter             +------------------+
 +----------+-----------+                             | Gateway sidecar  |
            | TB-6 network policy                     | por sessão       |
            v                                         +--------+---------+
 internet/upstream não produtivo <-----------------------------+
                                      allowlist/TLS/redaction

 Workspace Host -- TB-7 --> workspace/state/CAS/credential handles
 Workspace Host -- TB-8 --> agent/plugin/processo filho não confiável
```

Cada boundary declara autenticação, autorização, validação, limites,
observabilidade e cleanup. Boundary ausente é finding, não detalhe futuro.

### 17.3 Assets e principals

Assets protegidos:

- código e arquivos do workspace fora do ownership do Abel;
- tokens, cookies, sessão capturada, URLs privadas e credential handles;
- integridade de schemas, plans, routing, artifacts, evidence e releases;
- autoridade de pessoa, CI, agent, distribuição e Review;
- disponibilidade do Host, target e Gateway;
- privacidade de traffic, traces e capturas;
- fronteira que impede produção e egress não autorizado.

Principal local v1 deriva da identidade do processo/OS e da invocação. Pessoa,
CI, agent e processo filho recebem principals distintos. Alias de distribuição,
conteúdo do workspace e prompt nunca elevam principal. `ActionGrant` é avaliado
no Host no momento do efeito, ligado a subject, scope, expiry e policy digest.

### 17.4 Threat register mínimo

| ID | Ameaça | Controle obrigatório | Evidência |
|----|--------|----------------------|----------|
| T-01 | traversal/symlink escapa do workspace | canonical path, allowed roots, no-follow/TOCTOU-safe adapter | testes com `..`, symlink, race e path de plataforma |
| T-02 | command/shell injection | executable + argv estruturados, sem shell interpolation, allowlist de env/cwd | testes com metacharacters e args hostis |
| T-03 | RPC spoof/replay local | token efêmero, Origin, nonce/session binding, sequence e expiry | cliente sem token/origin/replay é negado |
| T-04 | iframe forja controle/evidence | origin/source exatos, handshake, schema, limits e operation/session IDs | frame/origin vizinho e replay falham |
| T-05 | SSRF, redirect ou DNS rebinding | upstream lógico, allowlist, scheme/port policy, resolução/IP revalidada e redirect opt-in | metadata/private/unlisted/redirect escape falham |
| T-06 | secret aparece em log/artifact/chat | credential handles, redaction deny-by-default, scanners e retention | canaries não aparecem em exports/CAS/logs |
| T-07 | artifact/bundle adulterado | digest na leitura, refs fechadas, staging e media/size policy | bit flip/ref ausente falha antes de Review |
| T-08 | cross-session leak | processo, token, port, state e storage por sessão | testes concorrentes com IDs/credentials distintos |
| T-09 | target contorna Gateway | NetworkContainment explícito; claim degradada sem enforcement | teste de egress fora do Gateway por target |
| T-10 | payload/traffic causa DoS | limits de bytes, profundidade, rate, concurrency, timeout e buffer bounded | fuzz/property/load nos limites |
| T-11 | decisão ou release atribuída incorretamente | principal, subject digest, append-only, assinatura separada | mutation/replay/wrong-subject negados |
| T-12 | plugin/agent executa efeito indevido | processo isolado, ContextBundle mínimo, effect class, preview/grant | prompt/plugin hostil não obtém grant |
| T-13 | publish/authoring perde update por race | expected digest, lock, staging e atomic commit | writers concorrentes: um vence, outro conflita |
| T-14 | produção usada como upstream | policy não sobrescrevível + classificação/allowlist | hostname/IP/cert de produção canary é negado |

Threats entram na conformance quando o boundary aparece. Finding aceito possui
owner, rationale, compensating control, expiry e revisão; “risco conhecido” sem
isso não fecha gate.

### 17.5 Requisitos gerais

- parse seguro antes de resolver referências;
- paths autorizados e normalizados por adapter de plataforma;
- args estruturados, sem shell interpolation;
- limites CPU, memória, bytes, profundidade, tempo e concorrência;
- cleanup de sessões órfãs e recovery no startup;
- origin separado para Studio/iframe e CSP mínima quando aplicável;
- CAS verificado em toda leitura, não apenas na gravação;
- logs sanitizados, estruturados e com retention limitada;
- principal, ActionEffect, grant e capability revalidados no Host;
- DistributionDescriptor/ConsumerLayout confinados ao workspace;
- dados sintéticos e reserved test domains;
- código consumidor nunca executa dentro do processo do Host/Gateway.

### 17.6 Gateway e contenção de rede

#### Sidecar e control plane

- processo por GatewaySession;
- data plane em endereço explícito, loopback por default e nunca LAN implícita;
- control plane por stdio parent-owned; attach alternativo exige socket local ou
  loopback autenticado;
- token/porta/credential handle não são reutilizados;
- shutdown revoga token, fecha listener e apaga state efêmero;
- loop para o próprio Gateway é rejeitado;
- response/debug header nunca expõe host, account, token ou payload.

#### `backendMode: isolated`

- sidecar sem upstream/credential materializado;
- qualquer request recebida termina em mock ou deny;
- bodies são sintéticos;
- nível mínimo reportado é `gatewayOnly`;
- somente `targetEnforced` permite claim de egress total do app.

#### `backendMode: hybrid`

- opt-in por grant e policy;
- somente upstream não produtivo allowlisted;
- TLS e hostname verificados;
- redirect desabilitado por default ou revalidado a cada hop;
- DNS resolve/revalida IP e bloqueia ranges/protocolos proibidos;
- request/response headers seguem allowlist independente;
- cookies/auth ficam em memória com TTL e principal;
- traffic é redacted e body permanece off por default;
- Review não oferece routing/sync/probe livres.

`targetEnforced` é capability de adapter. No web pode exigir browser context e
network policy controlados; em host-native pode exigir proxy/VPN/firewall ou
instrumentação equivalente. Se o ambiente não puder provar, reporta
`gatewayOnly` ou `unconstrained` e a release seal policy degrada a claim.

### 17.7 Host, iframe e bootstrap

- Host RPC usa schema, version negotiation, token efêmero e Origin allowlist;
- Host nunca aceita path/executable arbitrário vindo diretamente do Studio;
- artifacts usam handle scoped/TTL e são revalidados por digest;
- iframe usa `targetOrigin` exato e valida origin/source/nonce/session;
- CSP/sandbox são tão restritivos quanto o Flutter target permitir e qualquer
  relaxamento entra no fingerprint;
- bootstrap privilegiado mostra plano antes de autenticação, comando mínimo,
  arquivos afetados e undo;
- não instala daemon global nem edita config desconhecida silenciosamente;
- sudo/auth falho não é repetido automaticamente;
- port, firewall, certificate trust e cleanup são verificados.

### 17.8 Secrets, privacidade e retention

Nunca versionar nem colocar em chat, log ou artifact público:

- `.env` e configuração local de provider remoto;
- UpstreamProfile materializado com URLs concretas;
- parâmetros de probe que identifiquem contas/recursos;
- sessão capturada, cookies e authorization;
- service accounts, tokens de push e certificados privados;
- traffic/body bruto ou evidence não sanitizada.

Esses itens vivem no credential store ou memória com TTL; config mantém apenas
credential handle opaco. Fixtures usam `example.test`, IDs `mock-*` e dados
reservados de teste, nunca dump de ambiente ou PII. Traffic, trace, capture e
CAS possuem classification, retention, export policy e delete/GC verificável.
Redaction ocorre antes de persistir; remover depois não é controle suficiente.

AutoPreview executa código do consumidor em subprocesso. Environment, tempo,
saída e artifact são limitados; source/staging são confinados; PNG é validado;
persistência de pixels exige confirmação de dados sintéticos. Allowlist de
environment não equivale a sandbox de filesystem/rede/memória: containment só
é declarado quando o host a comprova.

### 17.9 Plugins e agentes

Plugin é código, não “configuração”. plataforma local não carrega plugin de terceiros
in-process. Adapter/distribuição trusted é pinado no build; extensão dinâmica
futura roda em processo separado com manifest de capabilities, protocolo
versionado, limits e grants.

Agente recebe `ContextBundle` mínimo e sanitizado. Texto do repositório, tool
output e prompt são dados não confiáveis. Agente pode consultar e propor patch;
apply exige preview, expected digest e grant humano/CI correspondente.
Identidade de agente ≠ CI ≠ pessoa. Nenhum deles herda credential store do Host.

### 17.10 Supply chain

- Dart/Flutter e toolchain pinados no CI;
- Pub Workspace com lockfile único e revisão de dependency diff;
- checksums, origem, licença e publisher de dependências registrados;
- versões do core, distribuição e adapters pinadas;
- soft fork não copia core nem carrega secret;
- build e publish usam lanes/principals separados;
- artifact é verificado por digest; assinatura prova signer separadamente;
- release produz provenance suficiente para reconstruir inputs;
- provider externo não redefine Release, Approval ou grant.

### 17.11 Processo de threat modeling

O threat model é vivo. Cada novo data flow, privilege, parser, provider,
transport, plugin ou target atualiza diagrama, threats, mitigations e testes
antes da implementação. Revisão responde:

1. o que mudou e quais assets atravessam boundaries?
2. o que pode dar errado, inclusive abuso e falha acidental?
3. qual controle reduz probabilidade/impacto?
4. qual teste negativo prova o controle e qual risco residual permanece?

validação fundacional exige T-01…T-14 classificados; a fase que introduz um boundary exige seus
testes executáveis. Hosted/remote execution seguem HR-01…HR-24 no threat model
independente. Finding cross-tenant, bypass de RLS, replay de capability ou
escape de namespace bloqueia promoção.

### 17.12 Tenancy, Kubernetes e sessão remota

- identidade autenticada determina tenant/principal; header/payload não eleva
  contexto;
- autorização da API e RLS são controles independentes e ambos obrigatórios;
- object key, event cursor, cache key, artifact e worker sempre incluem tenant;
- `SECURITY DEFINER` fixa search path, revoga `PUBLIC` e retorna somente o
  mínimo necessário ao scheduler;
- capability, plan, lease e session ticket são curtos, audience-bound e
  generation/nonce-bound;
- control plane não aceita containment forjado nem sucesso após lease expirada;
- CNI, admission, Gateway API, RuntimeClass/KVM e bucket policy precisam prova
  no ambiente real; render/schema não equivalem a enforcement;
- fallback de vídeo sem WebCodecs não aceita pointer/key/text;
- telemetry normaliza rotas e nunca usa tenant/run/worker como nome de span.

---

## 18. Capacidades implementadas e evidência

### 18.0 Validação fundacional da arquitetura

Antes de código de produção:

- este documento aprovado e decisões críticas aceitas;
- questões abertas classificadas por fase, owner e experimento;
- contracts v1 mínimos e version negotiation delineados;
- discovery de DistributionDescriptor/ConsumerLayout delineado;
- T-01…T-14 revisadas;
- zero dependência da stack PHP anterior;
- quatro spikes timeboxed concluídos ou explicitamente adiados:

| Spike | Pergunta | Evidência de saída |
|-------|----------|--------------------|
| S-01 Canonical contracts | JSON Schema 2020-12 + JCS são corretos em VM/web? | fixtures oficiais, errata, digest idêntico |
| S-02 Host/iframe | Studio ↔ Host ↔ target funciona com origin/nonce/reconnect? | vertical descartável + testes negativos T-03/T-04 |
| S-03 Consumer seam | factory neutra evita duplicar bootstrap de produção? | sample mínimo e diff de adoção |
| S-04 Journey Map | grafo/outline satisfaz frame, teclado e Semantics budgets? | profile build + benchmark/a11y audit |

S-01…S-04 foram promovidos conscientemente em 2026-08-09. Resultados, ambiente,
comandos e budgets estão em `docs/architecture/foundation-validation-results.md`; decisões de
toolchain, plataforma e protocolo estão em ADR-0001…ADR-0005. O Gateway isolado
e a resolução de Q-06/Q-07 estão em ADR-0006. Gateway hybrid, provider,
captura temporária e a resolução de Q-08/Q-09/Q-10 estão em ADR-0007 e
`docs/architecture/gateway-containment-results.md`. Spikes futuros
vivem em área experimental e são removidos ou promovidos após registrar
resultado. “Funcionou no spike” isoladamente não é evidência de produção.

### 18.1 Vertical local de experiência

Objetivo: provar **uma** tarefa humana ponta a ponta:

> abrir uma Journey pequena, compreender um Scenario, executar um target
> Flutter web real, capturar evidence e abrir a Release local que explica o que
> foi executado.

O vertical local é um gate de aceitação por capacidades, não um único lote.

**Contratos headless**

1. Pub Workspace Dart/Jaspr/Flutter-adapters e boundaries de packages;
2. contracts mínimos: DistributionDescriptor, ConsumerLayout, Workspace,
   Application, Journey, Scenario, Transition, LaunchProfile, ExecutionTarget,
   ApplicationBootstrapPolicy, NetworkContainmentDescriptor,
   ScenarioExecutionBinding, Evidence e Release;
3. parser seguro, compiler e CatalogManifest determinístico;
4. CLI `validate`, `explain` e `compile`;

**Compreensão estática**

5. Studio Jaspr com Explore mínimo;
6. Journey Map read-only + outline;
7. sheets projetadas do mesmo manifest;

**Execução**

8. Workspace Host local + target Flutter web por LaunchProfile;
9. App Adapter mínimo + Host RPC + JSON-RPC/postMessage seguro;
10. uma capability simulada, lifecycle, cancellation e SessionTrace;

**Evidence e release**

11. captura PNG + fingerprint;
12. release/bundle local mínimo;
13. CLI `doctor`, `dev`, `session start`, `capture` e `release build`;
14. `sample_flutter` usando apenas APIs públicas e packages empacotados.

Cada slice precisa ficar utilizável e testado antes do próximo. Gateway possui
seu próprio vertical no Gateway isolado e não é requisito oculto do vertical local.

As quatro capacidades possuem implementação e suites executadas em 2026-08-09. O consumer
`sample_flutter` compila o tooling target, renderiza em Chrome, produz PNG,
Evidence e ReleaseBundle local verificável por `tools/verify/verify_web_evidence_flow.sh`.
Resultados e digests de referência estão em
`docs/architecture/local-platform-results.md`. A entrega direta Session/App Adapter →
Artifact foi exercitada até o CAS, e a auditoria assistiva manual do Studio foi
executada com Orca/AT-SPI em Chromium/Wayland; assim, o gate local está fechado.

Não inclui:

- hybrid;
- host-native;
- GitHub;
- MCP;
- hosted;
- runtime remoto;
- editor livre;
- impact engine completo;
- init/adoption-report/detach;
- EvidenceProvider de runner externo;
- friction consumer;
- garantia de egress total.

### 18.2 Gateway isolado — Local Gateway

Objetivo: provar mock local determinístico sem upstream. Inclui:

- Gateway Dart em processo por sessão;
- contracts GatewayScope/GatewayPreset/GatewayRoute/CompiledGatewayPlan;
- `backendMode: isolated` com `networkContainment: gatewayOnly`;
- isolation;
- appliesTo;
- VerificationReport;
- traffic events;
- latency/failure;
- runtime mutável e reset determinístico;
- Backend panel;
- contract/security tests, inclusive T-05/T-08/T-09.

Gateway isolado nunca afirma isolamento de toda a rede do app. Ele prova que o Gateway não
faz passthrough e que tráfego roteado a ele é mock/deny.

### 18.3 Gateway containment — Hybrid Gateway

Inclui:

- passthrough;
- UpstreamProfile;
- RemoteConfigProvider adapter;
- RuntimeConfigurationOverlay;
- enforcement adapters para ApplicationBootstrapPolicy já declarada no vertical local;
- primeiro enforcement adapter capaz de reportar `targetEnforced`, ou
  degradação explícita quando o ambiente não permitir;
- session capture;
- policy de rede;
- backend mode `hybrid`, ortogonal à fidelidade;
- sanitização/auditoria.

Após Gateway containment, o núcleo cobre as capacidades centrais de gateway do legado, mas
ainda não sua integração host-native.

Gateway containment foi fechado em 2026-08-09 com passthrough allowlisted, provider generico,
captura em memoria e containment web executado. `CompiledGatewayPlan` continua
honestamente `gatewayOnly`; somente o report do adapter Linux em namespace pode
elevar a execucao observada a `targetEnforced` (ADR-0007).

### 18.4 ciclo de distribuição — adoção, distribuição e reuso de evidência

Inclui:

- `init --dry-run|--apply`, `adoption-report` e `detach --dry-run`;
- `friction_flutter` sem friend API;
- primeiro `EvidenceProvider` sobre runner existente;
- launcher/alias de distribuição compatível;
- conformance de package publicado fora do workspace;
- upgrade/migration e rollback local;
- budgets de adoção e cleanup medidos.

ciclo de distribuição foi fechado em 2026-08-09: adoption ownership-aware, provider do reporter
Dart/Flutter, binarios AOT + Studio web, install/update/rollback/migration e
conformance publica fora do workspace passaram o gate executado. A decisao e
os hashes de referencia estao em ADR-0008 e
`docs/architecture/distribution-lifecycle-results.md`.

### 18.5 Paridade operacional web/Android

Inclui:

- Android emulator → host;
- TLS local quando necessário;
- bootstrap/update/remove/verify;
- contract probe chain;
- Quality → GatewayPreset;
- migração/import genérico de configs legadas sem domínio;
- pacote, DistributionDescriptor, launcher e aliases estáveis;
- distribuição exemplo por composição, sem cópia do core;
- critérios §19 E-01…E-20 completos.

Somente uma distribuição que complete esses critérios pode afirmar substituição
operacional do legado. Nenhum rename ou fork altera o contrato `workspace`.

A paridade web/Android foi comprovada em 2026-08-09. O gate integral executou web real,
Android Emulator API 35 gerenciado, App Adapter capture, Gateway, contenção,
migração, retenção, consumidor externo e distribuição stable. O manifesto da
distribuição final tem
`sha256:dc662892982f2ff48bb03cee8a7486a2813bca0a1e92050a68c0cde5191cd0e1`.
A decisão, a matriz E-01…E-20 e os resultados estão em ADR-0009,
`docs/quality/platform-evidence-matrix.md` e `docs/architecture/web-android-results.md`.

### 18.6 source automation, Android Evidence, hosted control plane e remote execution — evolução implementada e promoção

| Fase | Escopo |
|------|--------|
| source automation | bundles compartilháveis ricos + source impact |
| Android Evidence | evidência nativa ampliada |
| hosted control plane | hosted collaboration |
| remote execution | remote runtime/device farm |

Cada fase entrega valor isolado.

source automation foi fechado em 2026-08-09 com `.evidence.zip` byte-reproduzível, verificação
offline, adapters filesystem/Git, impact conservador, ContextBundle sanitizado,
plugins one-shot em sandbox e MCP stateless read-only. O corpus rotulado teve
zero falso negativo e zero falso positivo em 14 decisões. Decisões e evidência
estão em ADR-0010 e `docs/architecture/source-automation-results.md`.

Android Evidence foi fechado em 2026-08-09 no Android Emulator API 35 gerenciado. Screenshot,
semântica e logcat sanitizados, screen recording e Perfetto foram correlacionados
no mesmo `Evidence`/`ExecutionFingerprint`, comparados por policies versionadas,
incluídos em Release e verificados em `.evidence.zip`. O gate preservou
`runtimeFidelity: hostNative`, `networkContainment: gatewayOnly`, nunca afirmou
`deviceAttested` e removeu AVD, pareamento, TLS e processos. Decisão e evidência
estão em ADR-0011 e `docs/architecture/android-native-evidence-results.md`.

### 18.7 hosted control plane — SaaS multi-tenant e colaboração otimista

hosted control plane foi implementado em 2026-08-09 com control plane Dart, PostgreSQL/RLS,
object storage S3-compatible, OIDC/PKCE, role matrix, expected digest,
idempotency, event/outbox, presence/comments/approvals, CLI hosted, Helm,
OpenTelemetry e supply chain assinável.

O rehearsal local criou backup de 82.096 bytes, verificou checksum, restaurou
em banco isolado, provou cobertura RLS/cross-tenant/no-context e mediu RPO/RTO
dentro de 15 minutos/4 horas. Isso prova o mecanismo lógico; PITR/WAL, object
versions, IdP/bucket e failover reais continuam gates externos e impedem a
claim `production-certified`.

Q-19 foi fechado pelo threat model independente HR-01…HR-24. Decisão, evidência
e runbook estão em ADR-0004, `docs/architecture/hosted-control-plane-results.md`,
`docs/security/hosted-remote-threat-model.md` e
`docs/operations/hosted-recovery.md`.

### 18.8 remote execution — remote runtime e device farm web/Android

remote execution foi implementado em 2026-08-09 com scheduler persistente, quota/prioridade,
lease/generation, cancellation/retry, Job por tentativa, worker sem banco,
plano/capability assinados, runtime web/Android, gateway de sessão, WebCodecs,
scrcpy control, fallback read-only e cleanup durável.

Contracts, PostgreSQL real, 80 runs de soak/reconciliation e seis cenários em
Chromium passaram. Helm/kubeconform validaram 7/7 recursos default, 9/9 remote
e 26/26 recursos core das quatro variantes web/Android × batch/interativo.
HTTPRoute passou validação estrutural, não server-side.

Cluster Linux/KVM real, CNI, admission, Gateway API, RuntimeClass/device plugin,
E2E e node-loss permanecem gates externos e impedem a claim
`device-farm-certified`. remote execution não inclui source build, iOS nem dispositivo físico.
Decisão e evidência estão em ADR-0005 e `docs/architecture/remote-execution-results.md`.

### 18.9 Composição modular e AutoPreview

A composição modular foi implementada em 2026-08-10 para transformar a composição
estática do Kit em Module/Capability/Provider/Profile sem criar novo bounded
context nem redefinir Plugin. ADR-0012 fixa taxonomia, configuração modular
canônica, `ResolvedKitPlan`, `EffectiveKitManifest`, lifecycle e Distribution
modular.

CLI, Host e Studio consomem o mesmo plano/manifest; módulos desabilitados não
registram comandos, RPCs ou rotas e não iniciam recursos. Gateway, Android,
tests/source/plugins/MCP, hosted/remote e release foram catalogados como módulos
built-in. A Distribution canônica produz bundles `full-local` e enxutos por
profile com o mesmo reader/install/rollback.

O vertical AutoPreview também foi implementado. `AutoPreview` é o primeiro
Module/EvidenceProvider novo: especializa Widget Preview para autoria, usa
Analyzer e runner `flutter-test` isolado para PNG/Evidence estrutural e projeta
Scenario × Variant no Journey Map sem exigir App Adapter, Gateway ou Android.
Plano e evidências executadas estão em
`docs/architecture/modular-kit-refactor-plan.md`,
`docs/architecture/modular-composition-results.md` e
`docs/architecture/auto-preview-results.md`. As claims todas as capacidades históricas não foram
reescritas.

A composição entrega o seam condicionado pelo `EffectiveKitManifest`; o
AutoPreview entrega contratos e projector. O cutover Jaspr posterior comprovou catálogo real Host →
Studio, resource handles, shell, device frames, Inspector/provider selection,
AutoPreview ponta a ponta e supervisão conjunta na matriz local.

### 18.10 Reconstrução operacional do Studio

A reconstrução operacional integra composição modular e AutoPreview sem criar
novo bounded context.
O Host torna-se autoridade de `WorkspaceSnapshot`, catálogo, variants, visual
Evidence e resource handles; o Studio remove o sample de produção e passa a
renderizar shell, Journey Map e inspector sobre essa projeção real.

O rollout seguiu contracts → Host/resources → bootstrap/supervisão → shell →
Journey Map → inspector/providers → AutoPreview operacional → matriz modular →
conformance/promoção. A reconstrução e o cutover ADR-0016 estão concluídos na matriz
local: o cliente Jaspr consome o snapshot real, device frames ficam fora dos
PNGs, providers e Variants são explícitos e o E2E Google Chrome valida duas capturas, stale→fresh,
execução sem provider, CSP e cleanup.

Plano, decisão e resultado:
`docs/architecture/studio-reconstruction-plan.md`, ADR-0014 e
`docs/architecture/studio-reconstruction-results.md`. AutoPreview mantém
fidelity `structural`; rede/memória continuam dependentes de sandbox comprovado
pelo host.

### 18.11 Plataforma de experiência agnóstica

Topologia e layouts, o consumer de referência, Inventory, Scenario Lab,
Quality, autoria/review, Motion/Context, MCP, distribuição externa e a matriz
de escala foram executados na matriz portátil local até 2026-08-18. Journey e
Inventory compartilham a mesma topologia; Lab → Run → Quality opera no mesmo
Studio Jaspr e sobre os mesmos digests de conteúdo.

O gate no-skip `tools/verify/verify_scenario_lab_vertical.sh` passou em Linux/Chrome
release com Target Flutter e API/Gateway reais. Ele comprovou relay v2 fenced
com 6/6 resultados reconhecidos, Evidence fresh, comparação visual,
aprovação humana seguida de rejeição superseding, persistência após reinício,
cancelamento e cleanup. Uma mutação temporária do layout autoral e da cor do
Target tornou o run
histórico stale e indisponível para review. A recollection atual falhou por
comparação, preservando aceitação automatizada dos demais critérios e
projetando Quality `changed` + `failing`. Fontes, builds, estado e ports foram
restaurados pelo gate.

Essa promoção é local e portátil. Não é evidência de produção, hosted,
device farm, dispositivo físico ou conformidade WCAG. Os gates de autoria e
review, Motion/Context, MCP, distribuição externa, escala e auditoria terminal
possuem evidência própria e mantêm os mesmos limites externos.

---

## 19. Matriz de cobertura do gateway legado

Esta matriz preserva o significado observável do legado. Uma capacidade só é
considerada entregue quando o critério de aceite correspondente passa; possuir
um tipo ou comando com nome semelhante não basta.

| ID | Capacidade | Significa | Decisão | Fase | Critério de aceite |
|----|------------|-----------|---------|------|--------------------|
| E-01 | Gateway seletivo | por request: mock, passthrough allowlisted ou deny | absorver | Gateway isolado e containment | route do preset mocka; route permitida fora dele só faz passthrough em hybrid; desconhecida nega |
| E-02 | Scope isolation | zero/um GatewayScope ativo e nenhum estado cross-session | absorver | Gateway isolado | ativar scope desativa o anterior; processo/token/state de outra sessão não mudam |
| E-03 | Preset | estado de negócio compila plano completo + routing | absorver | Gateway isolado | aplicar preset substitui plano e reseta runtime, sem merge cego |
| E-04 | `appliesTo` | route existe apenas no subset de presets declarado | absorver | Gateway isolado | routing, verify e probe excluem route fora do preset |
| E-05 | Verify ≡ API | preview e app recebem os mesmos bytes do handler real | absorver | Gateway isolado | contract test compara status, headers selecionados e body bruto |
| E-06 | Hybrid | sessão/login reais coexistem com mock apenas do fluxo | absorver com policy | Gateway containment | sidecar acessa só upstream não produtivo allowlisted; mode/containment aparecem no fingerprint |
| E-07 | Upstream sync | aliases remotos vêm de provider/config local, não hardcode | absorver | Gateway containment | sync valida e publica status `ready`; partial/invalid não substitui profile válido |
| E-08 | Pareamento host | app em emulador/simulador alcança sidecar local | absorver | web/Android | Android e primeiro host-native suportado passam bootstrap, health e cleanup |
| E-09 | Traffic | mock/passthrough/deny são auditáveis e sanitizados | absorver | Gateway isolado | TrafficEvent ordenado e diagnóstico sem secret |
| E-10 | Session capture | auth/hints allowlisted e temporários alimentam probe/hybrid | absorver restrito | Gateway containment | TTL, principal, redaction e invalidação por target/account |
| E-11 | Probe chain | cadeia remota ordenada e filtrada pelo preset | absorver | web/Android | `after`/`extract` resolvem params; route fora de `appliesTo` não executa |
| E-12 | Quality → preset | checklist humano abre binding concedido que prepara estado | absorver via ReviewGuide + binding | web/Android | ação efêmera materializa exatamente o binding; Review não recebe routing livre |
| E-13 | Docs leves | texto/HTML sanitizado sem binários no content root | absorver em living docs | plataforma local | import vira draft; evidência usa artifact ref |
| E-14 | Runtime mutável | workflow/epoch muda somente dentro da GatewaySession | absorver | Gateway isolado | reset é reproduzível; evidence inclui state digest quando relevante |
| E-15 | Faults | latency, timeout e falha forçada por route | absorver | Gateway isolado | FaultProfile determinístico passa testes por endpoint |
| E-16 | Extensão de scope | playbook completo: catálogo, handler, verify, docs, QA, probe, testes | absorver | Gateway isolado e extensões | checklist §10.19 completo |
| E-17 | Lifecycle host | bootstrap/update/remove/verify/sync seguros | substituir por CLI Dart | web/Android | operações idempotentes, dry-run/undo e doctor explicável |
| E-18 | Hygiene | secrets só locais; fixtures exclusivamente sintéticas | absorver | desde plataforma local | scanners e testes negativos não encontram secret/PII em fonte, log ou artifact |
| E-19 | Console operacional | ativar, preset, verify, traffic, QA, probe, sync e status | Studio/CLI | Gateway isolado até Android | jobs §4.5 acessíveis com grants e sem duplicar fonte autoral |
| E-20 | Arquitetura neutra | nenhum domínio, host, ID ou inventário real de consumidor | manter | sempre | gate anti-vazamento §27.3 passa |

Capacidades periféricas do console legado — push de teste, build de aplicativo, snapshot de
flags e painel de IA — não pertencem ao núcleo e não bloqueiam E-01…E-20.
Distribuições podem implementá-las como plugins opcionais, sujeitos aos mesmos
grants, hygiene e conformance.

E-02 é isolamento semântico/de sessão do Gateway; não é sinônimo de contenção
de toda a rede do target. Qualquer claim de egress total segue
`NetworkContainmentDescriptor` e T-09.

---

## 20. Atributos de qualidade e budgets

### 20.1 Qualidades obrigatórias

| Qualidade | Cenário | Evidência |
|-----------|---------|-----------|
| Determinismo | mesmos inputs → mesmo manifest | digest repetido |
| Verify parity | verify = API mock | contract test byte/JSON |
| Session isolation | scope/preset/token/state não vazam | testes matriciais e concorrentes |
| Security hybrid | egress fora da allowlist falha | testes negativos |
| Network honesty | claim corresponde ao containment efetivo | egress probe fora do Gateway |
| Reset | sessão retorna a estado conhecido | sequência repetida |
| Portabilidade | core roda sem Flutter | Dart VM tests |
| Reversibilidade | integração removível | detach report |
| Degradação | capability ausente afeta só action | descriptor matrix |
| Explicabilidade | config/routing justificáveis | doctor/explain tests |
| Paridade de distribuição | alias e CLI canônico produzem o mesmo modelo | manifest/JSON/exit code iguais |
| Bootstrap controlado | targetEnforced não fica ready com dependência não declarada | testes negativos de startup |
| Reuso de testes | suíte existente não é duplicada | EvidenceProvider conformance |
| Operação offline | bundle estático e execução selada não dependem de hosted | teste em network namespace bloqueado |
| Tenant isolation | API, RLS, object key, event e worker não cruzam tenant | dois principals + PostgreSQL NOBYPASSRLS + negative tests |
| Concorrência hosted | writers não perdem update e replay não duplica efeito | expected digest + idempotency/cursor tests |
| Remote safety | worker perdido e containment não observado nunca viram sucesso | state machine, fencing e reconciler tests |
| Cleanup | terminal/cancel/crash não deixa credencial ou runtime lógico órfão | soak + cleanup debt zero |
| Observabilidade | falha correlacionada | structured logs/trace |
| Acessibilidade | Studio/Review operável | WCAG audit |
| Independência IA | pipeline sem modelo | CI with agents disabled |
| Privacidade | sem secret no artifact | scanners/testes negativos |
| Composição honesta | Module disabled produz zero superfície/efeito | gates de ausência CLI/Host/Studio/resources |
| Plano único | CLI/Host/Studio observam o mesmo digest | transporte + EffectiveKitManifest |
| Preview honesto | renderer estrutural não afirma integração host-native | fingerprint/fidelity + conformance AP |

### 20.2 Budgets de aceitação por fase

Budget sem corpus, build mode, hardware e protocolo de medição não é gate. O
repositório mantém um `BenchmarkEnvironment` versionado com SDKs, OS, CPU,
memória, browser/device, warmup, amostras e corpus. CI de performance reporta
mediana, p95/p99 quando aplicável e variância; debug mode não vale.

Ceilings provisórios — alteráveis somente por decisão com nova baseline:

| Fase | Métrica/corpus de referência | Budget |
|------|------------------------------|--------|
| plataforma local | `compile` cold: 1.000 docs/5.000 transitions | p95 ≤ 2 s |
| plataforma local | recompile após um doc sem mudança estrutural | p95 ≤ 300 ms |
| plataforma local | primeiro frame útil do Map após manifest local | p95 ≤ 1,5 s |
| plataforma local | pan/zoom no Map, target 60 Hz | frame build+raster p95 ≤ 16,7 ms; p99 ≤ 33,3 ms |
| plataforma local | Session ready com build web já disponível | p95 ≤ 5 s |
| plataforma local | 20 ciclos start/reset/dispose | nenhum recurso órfão; crescimento retido ≤ 10% após GC estabilizado |
| Gateway isolado | overhead mock local, body ≤ 256 KiB, sem FaultProfile | p95 ≤ 10 ms; p99 ≤ 25 ms |
| Gateway isolado | buffer de TrafficEvent por sessão | ≤ 10.000 eventos ou 64 MiB; eviction explícita |
| ciclo de distribuição | Documentar | zero mudança em código/pubspec/lockfile do app |
| ciclo de distribuição | detach | zero arquivo modificado apagado; zero resíduo sem owner |
| MC | Module desabilitado | zero comando/RPC/rota/processo/listener/porta/device/rede |
| MC | startup falho/cancelado | rollback inverso e zero capability/resource exportado |
| AP | capture policy | frames/duração/timeout bounded; animação infinita não bloqueia o lote |
| AP | persistência | zero PNG sem confirmação sintética; item failed sem artifact |
| hosted control plane | presence default | TTL 60 s; heartbeat expirado não aparece |
| hosted control plane | backup freshness | RPO ≤ 15 min; alerta antes de 10 min sem WAL arquivado |
| hosted control plane | recovery rehearsal | RTO ≤ 4 h até RLS/object/API smoke aprovados |
| remote execution | lease heartbeat | expiração nunca renova generation antiga nem produz sucesso |
| remote execution | sessão interativa | exclusiva e limitada pelo `RemoteExecutionPlan.expiresAt` |
| remote execution | terminal/retry | cleanup durável concluído antes de nova tentativa |
| remote execution | soak | zero task/lease/token/namespace lógico órfão após corpus misto |

Cada medição falha de modo explícito quando o ambiente não corresponde ao
manifest; ela não produz um “pass” incomparável. Budgets são revistos após o
primeiro vertical apenas com raw results preservados.

Bloqueadores funcionais independentes de número:

- Documentar exige SDK no app;
- optional capability bloqueia Journey Map;
- produção importa Flutter App Adapter por default;
- Gateway isolated faz passthrough;
- `targetEnforced` possui bootstrap dependency não resolvida;
- alias de distribuição altera machine output;
- content root versionado recebe secret ou cache;
- verify diverge da API;
- CLI não explica undo.
- role da aplicação PostgreSQL possui BYPASSRLS ou transação sem tenant context;
- object key, cursor, cache/session ticket ou worker não é tenant-scoped;
- remote worker recebe source, comando arbitrário ou acesso ao banco;
- retry começa com cleanup pendente ou generation antiga aceita heartbeat;
- fallback screenshot aceita input;
- manifest usa imagem/tag mutável ou token Kubernetes estático.
- Module desabilitado ainda registra superfície ou inicia recurso;
- CLI, Host e Studio observam plan digests diferentes;
- AutoPreview `flutter-test` declara fidelity acima de `structural`;
- captura de preview persiste pixels sem confirmação sintética.

---

## 21. Estratégia de verificação e conformance

### 21.1 Portfólio de testes

O nível mais baixo que atravessa o risco real é preferido. Coverage auxilia
descoberta, mas não é gate isolado. Teste deriva expected result de schema,
invariante, fixture oficial ou cálculo independente — nunca copia o algoritmo
de produção.

#### Unit/property

- IDs/digests;
- graph;
- schema/migration;
- routing;
- appliesTo;
- canonical JSON;
- redaction;
- state machines;
- typed failures, clocks, cancellation e cleanup.

#### Architecture/static

- `dart format` e analyzer strict;
- imports/package boundaries;
- ausência de Flutter/I/O no engine;
- ausência de `dynamic` em domínio e API pública;
- API surface/semver;
- secret/license/dependency scans.

#### Jaspr component/browser accessibility

- View ↔ Controller sem I/O;
- loading/empty/failure/refreshing;
- teclado, foco, reflow e text scaling;
- HTML semântico, nomes acessíveis e AX tree;
- navegação, deep link e state restoration;
- screenshot apenas como complemento a assertions semânticas.

#### Contract

- CLI JSON;
- DistributionDescriptor/ConsumerLayout;
- protocol handshake;
- Gateway ports;
- MockHandler;
- RemoteConfigProvider;
- RuntimeConfigurationOverlay;
- EvidenceProvider;
- verify ≡ API;
- source adapters;
- hosted documents/role matrix/expected-digest conflict;
- signed remote plan, capability/ticket audience e binary framing.
- ModuleCatalog/ResolvedKitPlan/EffectiveKitManifest e configuração/distribuição canônicas;
- PreviewManifest/PreviewCaptureManifest/report e adjacent versions.

#### Integration

- Studio + Host + Session;
- Runner + Adapter;
- Gateway + app web;
- launcher de distribuição + config customizada;
- runner existente + EvidenceProvider;
- hybrid + fake upstream;
- capture + Evidence;
- release rebuild;
- OIDC/API + PostgreSQL RLS + S3 grant com dois tenants;
- scheduler + PostgreSQL + dispatcher/worker/reconciler;
- gateway WSS + Studio iframe/WebCodecs/fallback.
- profiles com ausência/presença de CLI/Host/Studio/Gateway/Android;
- Analyzer + registry + processo Flutter + PNG/CAS/Evidence + Journey Map.

#### Performance/recovery

- benchmarks §20.2 em profile/release;
- start/reset/dispose repetido;
- crash do target/Gateway/Host child;
- port conflict, disk full, partial staging e stale lock;
- cancel durante capture/publish/sync;
- no orphan process/token/file após deadline;
- backup/restore/RLS e replay por cursor;
- cancel remote em provisioning/running/uploading, lease expiry e node loss;
- soak de cleanup sem task/lease/token/namespace lógico órfão.

#### End-to-end

- tarefa humana plataforma local;
- Gateway isolado isolated;
- Gateway containment hybrid;
- ciclo de distribuição adoption/detach/EvidenceProvider;
- web/Android host-native;
- hosted control plane hosted com dois tenants e credenciais distintas;
- remote execution web/Android batch/interativo no cluster certificado.

### 21.2 Gateway conformance suite

Deve cobrir:

1. match method/path;
2. route params/query;
3. zero/um GatewayScope ativo;
4. appliesTo;
5. preset switch/reset;
6. mock response;
7. passthrough;
8. deny;
9. latency/timeout/disconnect;
10. mutation/poll;
11. header/body redaction;
12. redirect policy;
13. cancellation;
14. verify parity;
15. traffic sequence;
16. cleanup;
17. upstream unavailable;
18. secret absence em artifacts.
19. processo/token/state por sessão;
20. `isolated` sem passthrough;
21. containment report honesto;
22. malformed/oversized request bounded.

Cada GatewayScope também executa um gate de paridade:

1. preset aplicado produz o CompiledGatewayPlan esperado;
2. requests foco pelo data plane correspondem às fixtures/contratos;
3. VerificationReport é idêntico ao response do item 2;
4. estado legado/migrado é normalizado ou rejeitado de forma explícita;
5. route do preset reporta `mock` e route fora dele reporta
   `passthrough` somente em hybrid/allowlist, ou `denied`.

### 21.3 Protocol conformance

- version negotiation;
- partial capabilities;
- lifecycle;
- idempotency;
- out-of-order;
- timeout;
- crash;
- lease expiry;
- resync;
- large artifact refs.
- authentication/origin/nonce;
- replay e reconnect cursor;
- cancellation terminal exactly-once;
- unknown method/version fail-closed.

### 21.4 Consumers

`sample_flutter`:

- só APIs públicas;
- packages empacotados;
- demonstra journey e gateway.

`friction_flutter`:

- começa sem adapter;
- Documentar;
- Executar;
- adicionar uma capability;
- adicionar Gateway isolated;
- adoption/detach report.

### 21.5 Segurança

T-01…T-14 e HR-01…HR-24 mapeiam diretamente para negative/abuse tests. Fuzzing cobre parsers,
codecs, routes, canonicalização e redaction com corpus limitado e seeds
preservadas. Scanner sem finding não substitui teste de autorização, egress ou
boundary.

### 21.6 Usabilidade

Tarefas com Product, UX, mobile, backend e QA:

- localizar cenário;
- entender fidelity/backend mode;
- iniciar Run;
- aplicar preset;
- verificar resultado;
- voltar sem perder contexto;
- distinguir evidence/approval.

Inclui pessoas que usam teclado/screen reader e pessoas que não conhecem a
toolchain. Resultado registra task completion, erro, tempo, abandono e
compreensão de fidelity/backend/containment; preferência visual não substitui
critério de tarefa.

### 21.7 Confiabilidade e resultado

- time, random, network e filesystem são controlados;
- teste que depende de retry para passar continua flaky/falhando;
- teste de regressão deve falhar contra a violação quando a reprodução segura
  existir;
- E2E não mascara ausência de contract/unit test menor;
- falha é classificada como produto, teste, ambiente, flaky, preexistente ou
  não resolvida com evidência de baseline;
- command, ambiente, exit status e artifacts relevantes ficam ligados ao gate;
- green parcial não vira Pass global: requisito sem camada necessária é
  `Partial` ou `Inconclusive`.

### 21.8 Architecture fitness functions

CI torna boundaries observáveis:

| Invariante | Fitness function |
|------------|------------------|
| engine pure Dart | import graph rejeita Flutter, `dart:io` e adapters |
| Studio sem privilégio | import graph rejeita `dart:io`/runtime; integração usa Host client |
| consumidor desacoplado | entrypoint de produção não importa `execution_*`; tooling importa só `flutter_app_adapter` |
| interpretação única | CLI one-shot e Host RPC geram mesmo resultado/machine output |
| compile determinístico | N rebuilds + ordem de arquivo variada produzem mesmo digest |
| Gateway por sessão | conformance prova PID/token/port/state distintos |
| verify ≡ API | byte/status/header contract pelo data plane real |
| Review sem routing livre | autorização negativa para todos effects infrastructure/authoring |
| claim honesta | seal rejeita fingerprint sem containment/bootstrap exigidos |
| tenant obrigatório | migration audit + PostgreSQL real rejeitam contexto ausente/cross-tenant |
| worker sem banco/source | import/env/plan guards e contract tests |
| tentativa exclusiva | lease generation e completion fencing |
| cleanup antes de retry | durable cleanup queue + soak/reconciler |
| supply chain imutável | scan de Dockerfile/Actions/Helm + SBOM/provenance/cosign workflow |
| neutralidade | anti-vazamento §27.3 e scanners |

Fitness function falha junto com o contrato que protege. Exceção temporária
exige decision/owner/expiry; comentário ou skip permanente não é solução.

---

## 22. Falhas e operabilidade

### 22.1 Taxonomia

- authoring validation;
- incompatibility;
- capability missing;
- precondition;
- timeout;
- consumer failure;
- target failure;
- transport failure;
- gateway resolution;
- upstream unavailable;
- policy denied;
- internal.

### 22.2 Mensagem de erro

Studio/CLI mostram:

- failure code estável e category;
- operação;
- workspace/application/release/target/session;
- gateway mode/preset quando relevante;
- network containment/bootstrap assessment quando relevante;
- fato;
- impacto;
- capabilities restantes;
- retry/reset safety;
- próxima ação;
- logs/artifacts preservados.

Stack trace e exception concreta ficam no diagnóstico local sanitizado, não na
mensagem pública nem no machine contract. Retry só é sugerido quando idempotente
ou quando o estado observado permite retomada segura.

### 22.3 Logs

- estruturados;
- correlation ID;
- sem body/token default;
- local retention limitada;
- export sanitizado;
- cleanup de sessões órfãs no startup.

### 22.4 Health

Gateway status:

- listener;
- configuration;
- active scope/preset;
- mode;
- process/session identity e containment report;
- upstream logical readiness;
- traffic buffer;
- session TTL;
- policy.

Host health acrescenta workspace/principal, protocol version, child processes,
leases/handles, pending operations e cleanup debt sem revelar secret/path fora
do workspace.

Hosted health acrescenta database/object-store/issuer readiness, migration
version, outbox lag e exporter status sem consultar dado de outro tenant.
Remote health acrescenta queue por target, quota, workers/leases expirados e
cleanup debt. Tenant/run/worker aparecem em atributos bounded de diagnóstico,
nunca em route name ou metric label de cardinalidade irrestrita.

Kernel health acrescenta plan/catalog digest e, por Module, lifecycle, health,
capabilities efetivas e diagnósticos sanitizados. Somente `ready`/`degraded`
exportam capabilities; `disabled` não representa falha. O Host publica
`composition.describe` e `composition.health` mesmo no profile mínimo.

### 22.5 Recovery

- start idempotente;
- stop idempotente;
- port conflict explicável;
- stale runtime reset;
- upstream retry bounded;
- partial sync não substitui UpstreamProfile válido;
- release publish transacional.
- Host restart reconcilia child PID/lease sem assumir ownership de processo
  desconhecido;
- operation interrompida termina como failed/cancelled/unknown, nunca succeeded
  por ausência de erro.
- PostgreSQL usa base backup + WAL/PITR para RPO ≤ 15 min; restore isolado prova
  checksum, migrations, RLS, object inventory e API antes de abrir tráfego;
- object storage usa versioning, encryption, retention e inventário;
- remote startup reconcilia lease expirada e cleanup pendente antes de
  dispatch; retry espera namespace ausente;
- Job DELETE 404 é idempotente, mas falha/timeout de confirmação mantém cleanup
  debt e alerta operacional;
- signing key/worker token comprometidos são revogados por `kid`/TTL e novas
  leases param até rotação segura.

### 22.6 Runbook do Gateway

Setup:

1. resolver distribuição/config e executar `doctor`;
2. executar bootstrap em dry-run e aplicar com confirmação;
3. sincronizar/validar UpstreamProfile quando hybrid for necessário;
4. resolver/aplicar RuntimeConfigurationOverlay, bootstrap assessment,
   NetworkContainment e pareamento de rede;
5. iniciar Gateway e Application target;
6. em hybrid, autenticar no upstream real por passthrough;
7. confirmar health/readiness antes de ativar scope.

Loop de desenvolvimento:

1. ativar um GatewayScope e aplicar preset;
2. abrir verify;
3. exercitar a jornada no app;
4. reiniciar o target se ele cachear overlay/configuração;
5. consultar traffic se o outcome divergir;
6. executar probe apenas quando comparar o remoto for necessário;
7. executar testes/conformance após mudar handler, fixture ou routing.

| Sintoma | Diagnóstico/ação |
|---------|------------------|
| listener não abre | `doctor`; conflito de porta/firewall/bootstrap |
| app não conecta | conferir overlay, host mapping e readiness |
| sync falha | inspecionar status `missing`, `empty`, `incomplete` ou `invalid` |
| mock não aplica | scope ativo, preset, `appliesTo`, routing e header diagnóstico |
| scopes interferem | `gateway reset`; verificar isolamento por GatewaySession |
| verify diverge do app | detectar bypass do MockHandlerPort ou estado inicial diferente |
| passthrough inesperado | traffic + backend mode + allowlist + policy da route |
| claim offline inesperada | comparar containment report com egress probe T-09 |
| bootstrap deixa resíduo | `stop` + undo idempotente; preservar logs sanitizados |

---

## 23. Registro de decisões

`Aceita` orienta implementação. `Proposta` exige vertical. `Adiada` preserva
compatibilidade. `Substituída` mantém histórico e aponta para a decisão vigente.

### 23.1 Decisões fundamentais

| ID | Status | Decisão |
|----|--------|---------|
| D-001 | Aceita | núcleo local-first; hosted separado |
| D-002 | Aceita | stack alvo Dart, Studio Jaspr e adapters/consumers Flutter; sem PHP |
| D-003 | Aceita | modular monolith antes de splits |
| D-004 | Aceita | protocolo/documentos agnósticos; adapters específicos |
| D-005 | Aceita | app real; mocks só nas fronteiras |
| D-006 | Aceita | Journey Map estático; Run com uma sessão |
| D-007 | Aceita | Explore, Run, Review como contextos |
| D-008 | Aceita | Review/Studio no mesmo app/modelo |
| D-009 | Aceita | fontes/derivados/decisões/secrets separados |
| D-010 | Aceita | JSON Schema 2020-12 + canonical JSON |
| D-011 | Aceita | JSON-RPC 2.0 no control plane |
| D-012 | Aceita | capabilities negociadas + lifecycle explícito |
| D-013 | Aceita | Flutter é primeiro adapter; semantics ID para automação |
| D-014 | Aceita | fidelity/freshness/result/approval ortogonais |
| D-015 | Aceita | Release por digest; bundle é mecanismo de entrega |
| D-016 | Aceita | valor antes do App Adapter |
| D-017 | Aceita | integration em composition root isolado |
| D-018 | Aceita | núcleo funciona sem IA |
| D-019 | Aceita | dados sintéticos, menor privilégio, rede controlada |
| D-020 | Aceita | BackendContract referencia OpenAPI/AsyncAPI |
| D-021 | Aceita | CLI JSON é contrato base de automação |
| D-022 | Aceita | toolchain pinada; upgrade separado da release |
| D-023 | Aceita | Git é adapter local opcional; provider não entra no domínio |
| D-024 | Aceita | plataforma local prova uma Journey/Scenario/Run/Evidence/Release; adoção ampla fica em ciclo de distribuição |
| D-025 | Substituída | hosted/remote deixaram de ser adiados; ver D-041…D-047 e ADR-0004/0005 |
| D-026 | Aceita | Abel identifica o projeto; `workspace` é o namespace técnico estável |
| D-027 | Aceita | Workspace contém múltiplas Application sem exigir mutação do workspace do consumidor |
| D-028 | Aceita | DistributionDescriptor define branding/plugins; ConsumerLayout define config, content root, entrypoint e aliases |
| D-029 | Aceita | distribuição compatível compõe o core sem copiá-lo; hardfork incompatível vive em outro repositório |
| D-030 | Aceita | ApplicationBootstrapPolicy + NetworkContainment efetivos são obrigatórios antes de claim de egress total |
| D-031 | Aceita | testes existentes entram por EvidenceProvider e não são duplicados |
| D-032 | Aceita | Workspace Host é autoridade local para efeitos; Studio é client Jaspr sem I/O privilegiado |
| D-033 | Aceita | Studio usa view state imutável, fluxo unidirecional, ViewModels e constructor DI |
| D-034 | Aceita | monorepo usa Pub Workspaces e packages nos boundaries de publicação/runtime |
| D-035 | Aceita | backend mode, network containment, runtime fidelity e bootstrap assessment são dimensões ortogonais |
| D-036 | Aceita | recursos async têm owner/cancellation/cleanup; Session serializa commands mutáveis |
| D-037 | Aceita | digest prova integridade; assinatura/attestation e Approval são contratos separados |
| D-038 | Aceita | arquitetura governa conjunto normativo versionado; ADR/schema só ganha autoridade por registro |
| D-039 | Aceita | JCS v1 usa I-JSON restrito, errata aplicada e `sha256:<hex>` declarado |
| D-040 | Aceita | quatro BCs: Catalog & Docs, Sessions, Backend Gateway e Evidence & Release; Host não é BC |
| D-041 | Aceita | hosted é plane opcional; PostgreSQL/RLS forced e S3 reforçam tenant em controles independentes |
| D-042 | Aceita | OIDC Authorization Code + PKCE; role matrix explícita e nenhum password store Abel |
| D-043 | Aceita | expected digest + idempotency + event/outbox substituem last-write-wins, CRDT e dual write |
| D-044 | Aceita | remote scheduler é persistente; lease generation e cleanup durável precedem retry |
| D-045 | Aceita | cada tentativa remota é Kubernetes Job/namespace isolado; worker recebe plano/capability e nunca banco/source |
| D-046 | Aceita | Android interativo usa scrcpy H.264/control; WebCodecs ou fallback PNG read-only explícito |
| D-047 | Aceita | hosted control plane/remote execution implementados não equivalem a produção/device-farm certificados sem PITR/CNI/admission/KVM E2E |
| D-048 | Aceita | Kit usa Modules built-in compile-time, providers e profiles resolvidos em um único plan digest; plugins permanecem out-of-process |
| D-049 | Aceita | AutoPreview especializa Widget Preview para autoria, mas usa runner isolado próprio e declara fidelidade estrutural |
| D-050 | Aceita | Host é autoridade do WorkspaceSnapshot; Studio consome catálogo/Evidence por contracts e resource handles, sem filesystem/CAS path ou sample em produção |
| D-051 | Aceita | existe um único `apps/studio` Jaspr client-side; UI System é Jaspr, UX System é Dart puro e não há renderer/fallback Flutter |

### 23.2 Decisões Gateway

| ID | Status | Decisão |
|----|--------|---------|
| D-G01 | Aceita | Backend Gateway é BC oficial opt-in |
| D-G02 | Aceita | hybrid suportado com backend mode e network policy |
| D-G03 | Aceita | Gateway é Dart VM; distribuições usam Studio Jaspr e adapters Flutter somente quando selecionados |
| D-G04 | Aceita | verify ≡ API é invariante |
| D-G05 | Aceita | um GatewayScope ativo por GatewaySession |
| D-G06 | Aceita | GatewayPreset, LaunchProfile e Scenario são conceitos distintos |
| D-G07 | Aceita | contract probe chain declarativa, filtrada pelo preset e executada no data plane real |
| D-G08 | Aceita | bootstrap host-native Android gerenciado, reversível e ownership-aware |
| D-G09 | Aceita | núcleo `workspace` estável; branding por distribuição, sem hardfork semântico |
| D-G10 | Aceita | consumidor pode trazer fake próprio; Gateway é capability, não monopólio |
| D-G11 | Aceita | hybrid não satisfaz determinismo nem torna seal válido por default |
| D-G12 | Aceita | Gateway é sidecar Dart por processo e GatewaySession, supervisionado pelo Host/Runner |
| D-G13 | Aceita | GatewayEndpointResolver produz RuntimeConfigurationOverlay sem mutar configuração remota |
| D-G14 | Substituída | ver D-035: isolated restringe o Gateway; containment/bootstrap governam claim do target |
| D-G15 | Aceita | isolated nunca faz passthrough, inclusive com scope inativo |
| D-G16 | Aceita | control plane parent-owned usa stdio; attach alternativo exige autenticação local |
| D-G17 | Aceita | Review materializa binding concedido atomicamente e não oferece routing livre |

### 23.3 Resolução dos conflitos de fusão

| ID | Tensão | Resolução |
|----|--------|-----------|
| C-01 | simulação no consumidor vs gateway central | Backend Gateway oficial e opt-in; fake do consumidor continua permitido |
| C-02 | hybrid real vs determinismo | backend mode `hybrid` separado de fidelity; egress/policy explícitos e seal não válido por default |
| C-03 | legado PHP vs stack alvo | reimplementação Dart/Flutter; sidecar Dart, nunca subtree/runtime da stack PHP anterior |
| C-04 | console operacional vs Studio | mapear jobs para Studio/CLI; não portar templates do console legado nem criar segunda fonte |
| C-05 | estado mutável vs release por digest | estado pertence à GatewaySession; snapshot só entra por ExecutionFingerprint |
| C-06 | nome upstream vs distribuição branded | `workspace` é contrato estável; Helix é distribuição exemplo por ConsumerLayout/Descriptor |
| C-07 | instalação privilegiada vs CLI reversível | bootstrap host-native opt-in, dry-run/undo, necessário apenas no web/Android |
| C-08 | um produto mock vs catálogo aditivo | exclusividade é policy da GatewaySession; catálogo pode conter várias Journeys/scopes |
| C-09 | Review read-only vs execução interativa | Review permite efeito efêmero prebound, sem autoria/configuração/routing livre |
| C-10 | fonte canônica vs arquivo monolítico | ARCHITECTURE governa índice normativo; contratos extraídos mantêm ownership e precedência registrados |

Alternativas rejeitadas:

| Alternativa | Motivo |
|-------------|--------|
| manter Studio e gateway legado como solução final | dois runtimes e nenhuma substituição operacional |
| remover hybrid e oferecer só fixtures | perde sessão real e não cobre E-06/E-07 |
| portar a stack PHP anterior ou gerar PHP | quebra stack, distribuição e conformance |
| renomear schemas/kinds por distribuição | fragmenta digests e machine contracts |
| usar estado runtime mutável como fonte de release | destrói reproducibilidade |
| permitir proxy implícito para route desconhecida | cria risco de segurança e comportamento não auditável |
| tratar `isolated` como prova automática de rede offline | Gateway não observa conexões que o target faz fora dele |
| permitir Studio acessar filesystem/processo diretamente | duplica Application Services e expande a superfície privilegiada |
| carregar plugin de terceiros in-process no plataforma local | extensão equivale a execução de código com privilégios do Host |

Uma decisão alterada recebe status `Substituída`; não se edita significado em
silêncio.

---

## 24. Riscos arquiteturais

| Risco | Mitigação / sinal de revisão |
|-------|-------------------------------|
| Escopo infinito | roadmap por vertical; hosted/remote opt-in e certificados por gates separados |
| Studio sem Gateway não substitui o gateway legado | matriz E-01…E-20 + gate web/Android |
| Gateway engolir Sessions | BCs e ports separados |
| Host virar god object | Host só compõe handlers/ports; regras ficam nos BCs e import tests |
| GatewayPreset colidir com Scenario | modelo/nomes explícitos |
| Hybrid criar falsa confiança | backend mode visível + seal policy |
| Isolated prometer rede offline | NetworkContainment separado + T-09 + claim degradation |
| Hybrid vazar secrets | local profile, TTL, redaction, allowlist |
| SSRF/proxy aberto | bind/policy/host validation/redirect checks |
| Verify divergir | mesmo handler + conformance |
| Runtime mutável destruir reprodutibilidade | state digest + reset |
| Portar a stack PHP anterior | D-G03 + scan de dependências |
| Flutter contaminar core | pure Dart modules/tests |
| Studio duplicar engine/efeitos | Host authoritative + client repository tipado |
| plataforma local ainda grande | limitar CLI/source/agents; tarefa humana única |
| Journey Map virar mural | projection/zoom/outline |
| Execution runtime virar backdoor | seams públicas/checkpoints honestos |
| Tooling vazar produção | composition root + import scans |
| Living docs apodrecer | bindings/freshness |
| LLM virar verdade | deterministic core/proposals |
| Branding quebrar compatibilidade | marca fora de schema/kind/CLI JSON/digest |
| Layout customizado quebrar discovery | launcher resolve descriptor antes do catálogo + explain |
| Dot-directory misturar fonte e estado | content root só autoral; cache/state fora dele |
| Soft fork virar cópia permanente | version pin + conformance + proibição de copiar core |
| Bootstrap externo inviabilizar targetEnforced | ApplicationBootstrapPolicy + adoção hybrid-first |
| Override local vazar produção | tooling target + overlay efêmero + cleanup |
| Journey multi-app esconder troca de runtime | boundary explícito de Session/Application |
| App exemplo privilegiado | packages empacotados + friction consumer |
| Bootstrap danificar host | dry-run/undo/minimal privilege |
| Artifact store crescer | CAS/retention/GC |
| Documento voltar a ser monólito inconsistente | índice normativo + ADR/spec ownership + link/reference checks |
| Package sprawl | modular monolith; extração só por publicação/runtime/owner |
| API experimental do Widget Preview mudar | adapter `flutter_preview` isolado, compatibilidade Flutter estreita e conformance por upgrade |
| Combinações de módulos explodirem | profiles normativos, cobertura pairwise e gates de ausência por módulo com efeito |
| Plugin comprometer Host | sem plugin dinâmico in-process; process/capability boundary |
| Configuração modular virar flags dispersas | um `ResolvedKitPlan` canônico governa CLI, Host, Studio e fingerprint |
| Module virar service locator | `ModuleContext` tipado expõe somente Kernel e capabilities declaradas |
| Module desabilitado ainda produzir efeitos | conformance de ausência mede comando/RPC/rota/processo/porta/artifact zero |
| Dependency graph habilitar efeito oculto | dependência resource-bearing ausente falha; adoption só propõe patch em dry-run |
| CLI, Host e Studio divergirem | plan digest único e `EffectiveKitManifest` observado pelas três superfícies |
| Profile virar branch especial | profiles são overlays normalizados pelo mesmo resolver da configuração explícita |
| Configuração antiga chegar ao runtime | `workspace.yaml` canônico exige schema 2 e falha antes da resolução ou de efeitos |
| Tenant filter esquecido | forced RLS + NOBYPASSRLS + tenant PK/FK/index + API authz independente |
| Pool conserva tenant anterior | transação + SET LOCAL + no-context denial test |
| Object URL vira confused deputy | key tenant+digest, descriptor, origin/bucket fixos, TTL e policy externa |
| Outbox perde evento | event/outbox no mesmo commit; notify só wake-up; replay por cursor |
| Control plane Kubernetes comprometido | token projetado curto + verbs mínimos + admission namespace obrigatória |
| Android/KVM amplia blast radius | node pool/RuntimeClass dedicado, sem hostPath/privileged, wipe/cleanup |
| Stream/session cross-tenant | ticket first-frame audience/run/nonce/TTL + origin exato + replay denial |
| Node loss fabrica sucesso | state machine terminal explícita + lease fencing + containment authoritative |
| Cleanup órfão concorre com retry | durable cleanup queue, confirmação de namespace ausente e soak |
| Configuração confundida com enforcement | gates externos separados para PITR, bucket, CNI, admission, Gateway API e KVM |

Risco técnico central da plataforma local: controlar app real com API pequena e honesta.

Risco técnico central do Gateway isolado e containment: implementar mock/proxy seguro sem tornar
Gateway uma segunda aplicação de backend.

Risco técnico central do hosted control plane: qualquer dimensão sem tenant — API, transação,
object key, cursor, cache ou telemetry — pode furar a separação mesmo quando as
outras estão corretas.

Risco técnico central do remote execution: KVM e controle remoto aumentam privilégio; por isso
worker é descartável, não recebe banco/source e retry nunca antecede cleanup.

---

## 25. Questões em aberto

Devem ser resolvidas por vertical, não abstração especulativa:

Já resolvidas e não reabertas sem substituir decisão:

- Gateway é sidecar Dart por processo/GatewaySession e control plane parent-owned
  usa stdio (D-G12/D-G16);
- Studio é client do Workspace Host, não owner de I/O privilegiado (D-032);
- ReviewGuide + binding concedido materializam sessão sem routing livre
  (D-G17);
- backend mode e network containment são dimensões diferentes (D-035);
- config autoral do Gateway vive no content root escolhido pelo ConsumerLayout,
  não dentro de package publicado;
- implementação legada pode coexistir até o gate §27.2, sem overwrite in-place;
- hybrid é backend mode, não nível de fidelity nem seal automático.
- Q-01: `json_schema` fica encapsulado pelo perfil fechado Draft 2020-12 e JCS
  pertence a `experience_contracts` (ADR-0001 e perfil v1);
- Q-03: Host RPC usa JSON-RPC 2.0/WebSocket e target web usa envelope
  `postMessage` autenticado (ADR-0003 e protocol v1);
- Q-04: factory neutra e consumer-owned é compartilhada entre entrypoints; só
  tooling importa `flutter_app_adapter` (resultado S-03);
- Q-05: Journey Map usa DOM/CSS Jaspr, windowing bounded, LOD de interação e
  Outline HTML acessível; o baseline Flutter S-04 é apenas histórico.
- Q-06: `shelf`/`dart:io` permanece no data plane após conformance de limites,
  request abortada, disconnect, lifecycle e benchmark AOT (ADR-0006).
- Q-07: `CompiledGatewayPlan` v1 usa JCS/digest e handles CAS lazy; plano e
  control message têm limite de 1 MiB e fixture de 256 KiB (ADR-0006).
- Q-08: provider remoto inicial é JSON genérico e transacional, configurado
  apenas localmente (ADR-0007).
- Q-09: `targetEnforced` web exige dois probes reais em namespace de rede;
  config sem execução permanece `gatewayOnly` (ADR-0007).
- Q-10: sessão capturada vive apenas em memória, TTL máximo de 30 minutos,
  binding contextual e invalidação por restart/target/principal (ADR-0007).
- Q-02: descriptor/layout v1 usa codec fechado e tres layouts de conformance
  (ADR-0008).
- Q-11: primeiro EvidenceProvider ingere o reporter JSON publico do runner
  Dart/Flutter e artifacts explicitamente referenciados (ADR-0008).
- Q-12: distribuicao preview Linux usa releases imutaveis, manifest SHA-256,
  aliases, ponteiro atual, migration e rollback verificados (ADR-0008).
- Q-13: TLS local usa CA por workspace somente em Android Emulator gerenciado,
  com install/verify/remove, expiração e undo (ADR-0009).
- Q-15: artifacts de ContractProbe são efêmeros por default; CAS exige
  classificação explícita e root temporário expirável (ADR-0009).
- Q-16: retenção local usa quota default de 10 GiB, temporários por sete dias,
  grace de 24 horas para blobs inalcançáveis e releases/estado como roots
  (ADR-0009).
- Q-17: plugins são descobertos por manifest JCS, negociados por protocolo v1
  e executados one-shot fora do processo em sandbox Linux/bubblewrap; mutations
  exigem preview digest e grant (ADR-0010).
- Q-18: impact usa snapshots filesystem/Git, globs e dependências; qualquer
  incerteza invalida reuso. Corpus rotulado: 14 decisões, zero falso negativo e
  zero falso positivo no gate source automation (ADR-0010).
- Q-19: hosted usa OIDC/PKCE, role matrix, tenant context transacional,
  PostgreSQL forced RLS/NOBYPASSRLS, S3 tenant+digest e threat model HR-01…HR-24
  (ADR-0004 e `docs/security/hosted-remote-threat-model.md`).

Questões restantes possuem gate e método de decisão:

| ID | Questão | Bloqueia | Como resolver |
|----|---------|----------|---------------|
| Q-14 | iOS Simulator mapping | pós-remote execution | nova ADR, execução em macOS real + cleanup |

validação fundacional foi fechado com resultado para Q-01, Q-03, Q-04 e Q-05. As demais não
bloqueiam começar a fase anterior, mas bloqueiam a primeira fase indicada na
coluna.

---

## 26. Glossário

| Termo | Significado |
|-------|-------------|
| ActionEffect | query, ephemeral, authoring, infrastructure ou decision |
| Application | unidade executável do consumidor dentro de um Workspace |
| ApplicationBootstrapPolicy | tratamento explícito das dependências necessárias antes de ready |
| Attestation | afirmação assinada sobre um subject digest; separada de Approval |
| Flutter App Adapter | integração opt-in dentro do app |
| BackendContract | referência externa a contrato |
| Backend mode | none/isolated/hybrid; contract probe é operação separada |
| CompiledGatewayPlan | routing, fixtures e policies compiladas por digest |
| Capability | operação/observação suportada |
| EffectiveKitManifest | estado observado dos Modules, capabilities e superfícies após startup |
| Kernel | infraestrutura mínima obrigatória de configuração, lifecycle, health e segurança |
| Module | unidade funcional built-in, empacotada e habilitável do Kit |
| Profile | overlay declarativo de seleção e settings de Modules |
| Provider | implementação selecionável de uma capability requerida |
| ResolvedKitPlan | plano canônico e digerido de Modules, bindings, settings e ordem de startup |
| CAS | storage content-addressed |
| Cleanup debt | recurso remoto terminal ainda não confirmado como removido; bloqueia retry |
| Checkpoint | preparar/reconhecer Scenario |
| ContractProbePlan | sequência autoral de probes de contrato |
| ConsumerAppFactory | factory neutra e consumer-owned compartilhada por produção e tooling |
| ConsumerLayout | nomes e paths humanos escolhidos pela distribuição |
| DistributionDescriptor | composição versionada de branding, plugins, policies e layout |
| Evidence | observação ligada a ExecutionFingerprint/subject |
| EvidenceProvider | adapter de um runner existente para artifacts/evidence canônicos |
| AutoPreview | annotation Flutter opcional para Widget Previewer e Evidence estrutural via runner de auto-preview separado |
| Variant | dimensão visual canônica de viewport, DPR, brightness, locale, text scale e theme de um Scenario |
| Distribuição | composição de marca, instalador e update channel sobre o núcleo `workspace` |
| gateway legado | gateway seletivo anterior usado só como referência |
| ExecutionTarget | forma de iniciar, controlar e capturar uma Application |
| ExecutionFingerprint | identidade efetiva de target, runtime, toolchain e fronteiras |
| Hosted plane | deploy opcional de colaboração/tenancy sobre os mesmos contracts/engine |
| Integridade | conteúdo corresponde ao digest esperado; não identifica autor |
| Explore | contexto espacial |
| FaultProfile | falhas, latência e status forçados de uma rota |
| GatewayConfiguration | configuração local de modo, ports, policy e providers |
| GatewayPreset | estado nomeado da fronteira HTTP |
| GatewayRoute | rota HTTP autoral e sua aplicabilidade |
| GatewayScope | conjunto isolado de rotas controláveis |
| Backend Gateway | BC de rede mock/proxy, abreviado como Gateway |
| GatewaySession | runtime efêmero do Gateway |
| Hybrid | mock seletivo + passthrough para upstream não produtivo |
| Isolated | Gateway sem passthrough; não prova egress total do target |
| Journey | grafo de caminhos |
| Journey Map | projeção espacial estática de uma Journey |
| LaunchProfile | launch sem claim de estado |
| Abel | projeto, repositório e distribuição de referência do namespace `workspace` |
| Workspace Host | processo Dart VM local que autoriza e supervisiona efeitos/Application Services |
| NetworkContainment | enforcement de rede do target: unconstrained, gatewayOnly ou targetEnforced |
| Passthrough | request encaminhada ao upstream |
| Projection | lente do grafo |
| NodeInstance | occurrence visual de um Scenario dentro de uma Projection |
| ScenarioFacetManifest | taxonomia consumer-owned, completa e ligada ao Catalog por digest |
| ScenarioLabManifest | plano declarativo catalog-bound para Lab e Quality; não é resultado de execução |
| ExperienceContentSet | geração atômica de snapshot, topologia e manifests adjacentes |
| Release | manifest imutável por digest |
| ReleaseBundle | embalagem verificável de Release e artifacts |
| RemoteRun | execução web/Android hosted com state machine e tentativa fenced |
| RemoteExecutionPlan | plano assinado e expirável que limita target, artifacts e capabilities do worker |
| Review | contexto de comparação/decisão |
| ReviewGuide | narrativa humana |
| RoutingTable | decisão compilada de mock, passthrough ou deny por rota |
| RuntimeConfigurationOverlay | overrides efêmeros e não secretos de um tooling target |
| Run | sessão interativa |
| Scenario | estado semântico da jornada |
| SessionTrace | observações append-only |
| Tenant context | tenant autenticado aplicado localmente à transação e reforçado por RLS |
| TrafficEvent | observação sanitizada de uma request processada |
| Soft fork | distribuição por composição que preserva contratos e conformance workspace |
| Hardfork | implementação incompatível com namespace/conformance próprios |
| Hub | alias lógico de uma API/base URL do app; nunca inventário real do consumidor |
| Upstream group | conjunto lógico de routes que compartilha um alias de upstream |
| UpstreamProfile | aliases locais de upstream, sem credenciais publicáveis |
| Variant | diferença ambiental sem mudança semântica |
| VerificationReport | request e response produzidas pelo pipeline real de mock |
| Verify ≡ API | paridade entre preview e response mock |
| Workspace | raiz lógica da integração; pode conter várias Applications |

### 26.1 Tradução terminológica do legado

| Termo legado | Termo canônico |
|--------------|----------------|
| LegacyScope | GatewayScope |
| LegacyPreset | GatewayPreset |
| LegacyRoute | GatewayRoute |
| LegacyBundle | CompiledGatewayPlan |
| LegacyRouting | RoutingTable |
| LegacyVerifySnapshot | VerificationReport |
| LegacyTrafficEvent | TrafficEvent |
| LegacyUpstreamSet | UpstreamProfile |
| LegacyProbePlan | ContractProbePlan |
| scenario store | runtime da GatewaySession, não Scenario |
| legacy fixture-only mode | backend mode `isolated` |
| legacy hybrid upstream mode | backend mode `hybrid` |
| LegacyLaunchPreset | LaunchProfile |
| harness | execution runtime / Sessions |
| canvas | Journey Map |

Uma fixture de Gateway é payload/contrato referenciado pelo
CompiledGatewayPlan. Uma fixture de ExecutionTarget descreve dados/ambiente do
target. Elas não são intercambiáveis.

---

## 27. Governança deste documento

Enquanto este for o documento arquitetural principal:

- implementação não demonstrada continua descrita como plano;
- decisão aceita recebe ID;
- mudança de decisão marca a anterior como substituída;
- capability nova declara adoção, ausência e remoção;
- exemplos são hipotéticos;
- nenhum domínio de consumidor entra neste arquivo;
- branding pode alterar config filename, content root, tooling entrypoint e
  aliases via ConsumerLayout;
- branding não altera schemas, kinds, digests, CLI JSON, exit codes ou
  protocolo `workspace`;
- content root nunca contém cache, sessão ou secret;
- nenhum runtime PHP é introduzido;
- cada fase tem tarefa humana, prova e non-goals;
- novas abstrações exigem segundo caso ou boundary de deploy;
- referências externas são revisadas antes da implementação;
- ADR separado é obrigatório quando uma decisão aceita é substituída, um spike
  escolhe entre trade-offs relevantes, um public contract muda ou ownership
  atravessa bounded context;
- este arquivo mantém resultado, invariantes, status e link; ADR mantém contexto
  e alternativas, sem duplicar especificação executável;
- schema/protocolo/conformance têm owner e versão no registro §27.4.

### 27.1 Gate para iniciar implementação

Este gate foi aprovado em 2026-08-09:

- [x] baseline implementado e stack Dart/Jaspr/Flutter-adapters está explícita;
- [x] quatro BCs e o boundary não-domínio do Workspace Host estão no diagrama;
- [x] mock/passthrough/deny, isolation e verify ≡ API têm invariantes;
- [x] backend mode e NetworkContainment estão separados e T-09 possui plano;
- [x] matriz E-01…E-20 contém significado, fase e critério;
- [x] hybrid é backend mode explícito, com policy e sem seal default;
- [x] GatewayPreset, LaunchProfile e Scenario são distintos;
- [x] jobs operacionais estão mapeados a Studio/CLI sem portar UI legado;
- [x] consumidor pode continuar usando fake próprio;
- [x] plataforma local task e non-goals estão aceitos;
- [x] D-026…D-040 e D-G01…D-G17 não têm proposta bloqueante;
- [x] T-01…T-14 foram revisadas e possuem fase/evidência;
- [x] S-01…S-04 possuem resultado registrado;
- [x] Q-01, Q-03, Q-04 e Q-05 foram fechadas;
- [x] Pub Workspace, package boundaries, sample e Workspace Host foram definidos;
- [x] checklist anti-vazamento §27.3 passa;
- [x] registro normativo §27.4 não possui contrato órfão ou contraditório.

### 27.2 Gate para afirmar substituição do gateway legado

Este gate foi aprovado para web/Android em 2026-08-09 após web/Android provar:

- [x] E-01…E-20;
- [x] host-native Android gerenciado;
- [x] hybrid seguro;
- [x] containment report honesto e `targetEnforced` somente quando provado;
- [x] verify parity;
- [x] lifecycle bootstrap/update/remove;
- [x] migração testada;
- [x] DistributionDescriptor/ConsumerLayout conformes;
- [x] distribuição sem cópia oculta do core;
- [x] bootstrap dependencies classificadas;
- [x] adoção/removal report;
- [x] nenhuma dependência da stack PHP anterior.

A claim é limitada à matriz web/Android documentada em
`docs/architecture/web-android-results.md`; não inclui iOS, dispositivo físico, hosted
ou device farm.

### 27.3 Gate anti-vazamento

Falha a revisão se este documento, schemas ou exemplos genéricos contiverem:

- nome de organização, marca, monorepo, app, módulo, squad ou produto real;
- nome de ferramenta proprietária anterior ou distribuição interna de um
  consumidor específico;
- path, alias, config filename ou entrypoint reais de um consumidor;
- slug real de GatewayScope;
- host, path ou chave de configuração remota reais;
- documento, conta, token, header ou ID copiado de ambiente;
- inventário de journeys, APIs ou hubs de consumidor;
- vendor/SDK citados como se fossem dependência obrigatória do núcleo;
- secret, cache, sessão ou estado local no content root.

São permitidos somente exemplos evidentemente hipotéticos, como a distribuição
fictícia `Helix`, `widgets-catalog`, `EXAMPLE_API_URL`, `example.test`,
`10.0.2.2`, `@example.test`, IDs `mock-*` e nomes lógicos sem correspondência
com consumidor ou organização.

Validação mecânica mínima:

1. buscar marcas, monorepos, hosts e paths internos conhecidos;
2. buscar nomes de ferramentas/distribuições proprietárias;
3. buscar secrets e credenciais;
4. confirmar que termos legados fora do baseline §1.2, decisões §23.3 e
   tradução §26.1 estão acompanhados do termo canônico;
5. validar links, numeração e referências de seção;
6. confirmar que todo artifact normativo está no registro §27.4 e é publicável
   sem identificar consumidor.

### 27.4 Registro normativo inicial

| Artifact | Status atual | Owner | Governado por |
|----------|--------------|-------|---------------|
| `ARCHITECTURE.md` | ativo | architecture owner | inteiro |
| `schemas/{catalog,distribution,evidence,gateway,hosted,runtime,source}/*.schema.json` | contratos ativos organizados por domínio | Contracts | §§6–7 |
| `docs/contracts/json-schema-profile.md` | ativo v1 | Contracts | §§5–7, ADR-0001 |
| `docs/protocols/host-app-adapter.md` | ativo v1 | Sessions/Protocol | §9, ADR-0003 |
| `schemas/runtime/session-runtime.schema.json` | ativo | Sessions/Contracts | §§6.5, 9, ADR-0003 |
| `schemas/distribution/kit-composition.schema.json` | composição modular ativa | Architecture/Contracts | §§3.24, 18.9, ADR-0012 |
| `schemas/evidence/preview-capture.schema.json` | AutoPreview ativo | Evidence/Contracts | §§12, 18.9, ADR-0013 |
| `schemas/catalog/catalog-manifest.schema.json` | catálogo ativo | Catalog/Contracts | §§6.2, 8, 18.10, ADR-0014 |
| `docs/architecture/decisions/0017-experience-topology-and-projection-layout.md` | decisão aceita; topologia/layout executados | Catalog/Studio | §§3.14, 6.4, 8, ADR-0017 |
| `docs/architecture/decisions/0018-atomic-experience-content-and-scenario-facets.md` | decisão aceita; conteúdo/facets executados | Catalog/Host/Studio | §§6.4, 8, ADR-0018 |
| `schemas/runtime/experience-content-set.schema.json` | conteúdo de experiência ativo | Studio/Contracts | §§6.4, 8, ADR-0018 |
| `schemas/catalog/scenario-facet-manifest.schema.json` | facets de cenário ativos | Catalog/Contracts | §§6.4, 8, ADR-0018 |
| `schemas/catalog/scenario-lab-manifest.schema.json` | Scenario Lab ativo e executado localmente | Catalog/Contracts | §§6.4–6.5, 8, 9, 18.11 |
| `docs/architecture/distribution-agnostic-experience-platform-plan.md` | rastreador não normativo ativo | Architecture | §§1–27, ADR-0017, ADR-0018 |
| `schemas/runtime/studio-workspace.schema.json` | workspace do Studio ativo | Studio/Contracts | §§6.2, 8, 18.10, ADR-0014 |
| `schemas/distribution/consumer-config.schema.json` | configuração de consumer ativa | Architecture/Contracts | §§7, 18.9, ADR-0012 |
| `schemas/distribution/distribution-descriptor.schema.json` | contrato canônico | Distribution/Contracts | §§6.3, 13, 18.9, ADR-0012 |
| `schemas/distribution/distribution-release.schema.json` | contrato canônico | Distribution/Contracts | §§13–14, 18.9, ADR-0012 |
| `docs/contracts/module-composition.md` | composição modular ativa | Architecture/Contracts | §§3.24, 18.9, ADR-0012 |
| `docs/contracts/consumer-configuration.md` | configuração de consumer ativa | Architecture/Contracts | §§7, 18.9, ADR-0012 |
| `docs/contracts/distribution-release.md` | contrato canônico | Distribution/Contracts | §§13–14, 18.9, ADR-0012 |
| `docs/contracts/auto-preview.md` | AutoPreview ativo | Evidence/Contracts | §§12, 18.9, ADR-0013 |
| `docs/contracts/studio-workspace.md` | workspace do Studio ativo | Studio/Contracts | §§6.2, 8, 18.10, ADR-0014 |
| `docs/protocols/studio-host.md` | transporte e startup do Studio ativos | Studio/Host/Protocol | §§8, 9.2, 17, 18.10, ADR-0014 |
| `docs/architecture/decisions/0013-auto-preview-evidence-provider.md` | decisão aceita para AutoPreview | Evidence/Architecture | §§12, 18.9, ADR-0013 |
| `docs/quality/module-conformance.md` | conformance ativa MC | Architecture/QA | §§18.9, 21, ADR-0012 |
| `docs/quality/auto-preview-conformance.md` | conformance ativa AP | Evidence/QA | §§12, 18.9, 21, ADR-0013 |
| `docs/security/auto-preview-threat-model.md` | contenção do AutoPreview ativa | Evidence/Security | §§17, 18.9, ADR-0013 |
| `docs/operations/module-startup.md` | runbook modular ativo | Architecture/Operations | §§18.9, 22, ADR-0012 |
| `docs/architecture/foundation-validation-results.md` | evidência validação fundacional | Architecture/QA | §§18.0, 20.2 |
| `docs/architecture/local-platform-results.md` | evidência plataforma local | Architecture/QA | §§18.1, 20–21 |
| `docs/architecture/gateway-isolation-results.md` | evidência Gateway isolado | Gateway/QA | §§10, 18.2, 20–21 |
| `docs/architecture/gateway-containment-results.md` | evidência Gateway containment | Gateway/Security/QA | §§10, 17, 18.3, 20–21 |
| `docs/architecture/distribution-lifecycle-results.md` | evidência ciclo de distribuição | Distribution/Evidence/QA | §§11–14, 18.4, 20–21 |
| `docs/architecture/web-android-results.md` | evidência web/Android | Architecture/QA | §§18.5, 19–21, 27.2 |
| `docs/architecture/source-automation-results.md` | evidência source automation | Source/Automation/QA | §§13, 16–18, 20–21 |
| `docs/architecture/android-native-evidence-results.md` | evidência Android Evidence Android | Evidence/Sessions/QA | §§9, 12–13, 18, 20–21 |
| `docs/architecture/hosted-control-plane-results.md` | evidência portátil hosted control plane | Hosted/Security/QA | §§5–7, 16–18, 20–22, ADR-0004 |
| `docs/architecture/remote-execution-results.md` | evidência portátil remote execution | Remote/Security/QA | §§5–6, 9, 15–18, 20–22, ADR-0005 |
| `docs/architecture/platform-capability-audit.md` | auditoria todas as capacidades históricas + MC/AP | Architecture/QA | §§18, 20–21, 27.6 |
| `docs/architecture/modular-kit-refactor-plan.md` | plano MC/AP executado | Architecture/QA | §§3.24, 18.9, ADR-0012 |
| `docs/architecture/modular-composition-results.md` | evidência da composição modular | Architecture/QA | §§18.9, 20–21, ADR-0012 |
| `docs/architecture/auto-preview-results.md` | evidência do AutoPreview | Evidence/QA | §§12, 18.9, 20–21, ADR-0013 |
| `docs/architecture/studio-reconstruction-plan.md` | plano executado do Studio | Studio/Architecture/QA | §§8, 18.10, 20–21, ADR-0014 |
| `docs/architecture/decisions/0014-host-authoritative-studio-workspace.md` | decisão aceita para o Studio autoritativo | Studio/Architecture | §§8, 9.2, 17, 18.10 |
| `docs/security/studio-host-threat-model.md` | transporte e startup do Studio ativos | Studio/Host/Security | §§8, 17, 18.10, ADR-0014 |
| `docs/operations/studio-startup.md` | runbook de startup do Studio ativo | Studio/Host/Operations | §§8, 18.10, 22, ADR-0014 |
| `docs/security/hosted-remote-threat-model.md` | ativo hosted control plane/remote execution | Security + Hosted/Remote | §17, ADR-0004/0005 |
| `docs/operations/hosted-recovery.md` | ativo hosted control plane | Hosted Operations | §§18.7, 20, 22, ADR-0004 |
| `docs/quality/platform-evidence-matrix.md` | matriz executável web/Android | Gateway/QA | §§19–21, ADR-0009 |
| `docs/contracts/evidence-release.md` | ativo v1 | Evidence & Release | §§12–13 |
| `schemas/gateway/gateway-plan.schema.json` | ativo | Gateway | §10, ADR-0006 |
| `docs/contracts/gateway-runtime.md` | ativo v1 | Gateway/Contracts | §§6.6, 10, 17, ADR-0006/0007 |
| `schemas/gateway/containment-report.schema.json` | ativo | Sessions/Target | §§9–10, ADR-0007 |
| `schemas/distribution/adoption.schema.json` | ativo | Distribution | §14, ADR-0008 |
| `schemas/evidence/test-evidence-summary.schema.json` | ativo | Evidence | §§11–12, ADR-0008 |
| `schemas/evidence/app-adapter-capture-command.schema.json` | ativo | Sessions/Evidence | §§9, 12, ADR-0009 |
| `schemas/source/source-automation.schema.json` | ativo | Source & Automation | §§6.9, 16, ADR-0010 |
| `schemas/evidence/evidence-bundle.schema.json` | ativo | Evidence & Release | §§12–13, ADR-0010 |
| `schemas/source/plugin-manifest.schema.json` | ativo | Source & Automation | §§16–17, ADR-0010 |
| `schemas/evidence/android-evidence.schema.json` | ativo | Evidence/Sessions | §§9, 12–13, ADR-0011 |
| `schemas/hosted/hosted-collaboration.schema.json` | ativo | Hosted/Contracts | §§6.14, 7.5, ADR-0004 |
| `schemas/hosted/remote-execution.schema.json` | ativo | Remote/Contracts | §§6.14, 9.10, ADR-0005 |
| `docs/contracts/source-automation.md` | ativo v1 | Source & Automation | §§6.9, 16, ADR-0010 |
| `docs/contracts/evidence-bundle.md` | ativo v1 | Evidence & Release | §13, ADR-0010 |
| `docs/protocols/mcp-read-only.md` | ativo v1 | Source & Automation | §16, ADR-0010 |
| `docs/contracts/android-evidence.md` | ativo v1 | Evidence/Sessions | §§9, 12–13, ADR-0011 |
| `docs/contracts/hosted-remote.md` | ativo v1 | Hosted/Remote/Contracts | §§6.14, 9.10, ADR-0004/0005 |
| `deploy/helm/control-plane/` | deploy hosted control plane/remote execution | Hosted/Remote Operations | §§15.8, 17.12, 22 |
| `.github/workflows/release-images.yml` | supply chain hosted control plane/remote execution | Release Engineering | §§17.10, 18.7–18.8 |
| `schemas/evidence/evidence-release.schema.json` | ativo | Evidence & Release | §§12–13 |
| `libs/experience_contracts/tool/standards_conformance.dart` | ativo validação fundacional | Contracts | §§5, 20–21 |
| `tests/conformance/` e suites de contracts | ativo por vertical | owners dos contratos | §21 |
| `docs/architecture/decisions/0001`…`0014` | ativos | owners das decisões | §§23 e 27 |

Artifact planejado não é fingido como existente. Ao ser criado, recebe versão,
compatibility policy, fixtures e link exato neste registro. Remover ou renomear
sem atualizar o registro falha CI documental.

### 27.5 Mudança arquitetural

Toda mudança material informa:

1. decisão/invariante afetada;
2. producers, consumers e compatibility window;
3. threat/risk e rollback;
4. migration de fonte/runtime/artifact quando houver;
5. conformance e evidence necessárias;
6. fase e claim que passam a ser permitidas ou proibidas.

Uma checkbox de gate só recebe `[x]` após evidence executada e ligada ao
artifact/revision. Planejamento ou confiança não contam como conclusão.

### 27.6 Claims hosted control plane/remote execution e gates externos

Estados distintos evitam que implementação portátil seja confundida com
certificação operacional:

| Claim | Estado | Evidência / condição |
|-------|--------|----------------------|
| `hosted control plane implemented` | permitido | contracts/API/CLI, PostgreSQL/RLS real, recovery lógico, Helm/supply chain |
| `hosted control plane production-certified` | proibido | exige PITR/WAL, object versions, IdP/bucket, failover e cluster reais |
| `remote execution implemented` | permitido | scheduler/worker/gateway/Studio, PG real, soak e manifests strict |
| `remote execution device-farm-certified` | proibido | exige CNI/admission/Gateway API/KVM E2E e node-loss/soak reais |

Gates portáteis executados:

- [x] dois tenants, role matrix, expected digest, cursor e object key;
- [x] role PostgreSQL `NOBYPASSRLS`, forced RLS e no-context denial;
- [x] backup/checksum/restore/RLS dentro de RPO/RTO local;
- [x] quota/lease/generation/cancel/retry e cleanup durável;
- [x] worker sem banco/source, plano/capability assinados e artifacts por digest;
- [x] WSS/iframe/H.264/WebCodecs/fallback read-only em Chromium;
- [x] Helm lint, kubeconform e supply-chain gates.

Gates de infraestrutura não executados neste repositório:

- [ ] PITR/WAL e object-store versionado em produção;
- [ ] instalação server-side, CNI e admission policy no cluster alvo;
- [ ] Gateway API/HTTPRoute e TLS WSS reais;
- [ ] web/Android batch/interativo e node-loss em pool KVM dedicado;
- [ ] soak prolongado, userdata wipe e capacidade/fairness multi-tenant.

Detalhes e comandos estão em `docs/architecture/hosted-control-plane-results.md` e
`docs/architecture/remote-execution-results.md`. A rastreabilidade integral do plano mestre,
incluindo requisitos portáteis e gates externos, está em
`docs/architecture/platform-capability-audit.md`.

---

## 28. Standards e referências oficiais

Estas referências fundamentam escolhas e devem ser revisadas antes da primeira
implementação e em upgrades de SDK. Elas não alteram o contrato automaticamente;
mudança externa só entra por decisão registrada.

Última revisão das referências: 2026-08-09.

| Tema | Referência |
|------|------------|
| Flutter app architecture | <https://docs.flutter.dev/app-architecture/recommendations> |
| Flutter web full-page/iframe embedding | <https://docs.flutter.dev/platform-integration/web/embedding-flutter-web> |
| Flutter accessibility testing | <https://docs.flutter.dev/ui/accessibility/accessibility-testing> |
| Dart Pub Workspaces | <https://dart.dev/tools/pub/workspaces> |
| Dart concurrency/isolate model | <https://dart.dev/language/concurrency> |
| JSON Schema Draft 2020-12 | <https://json-schema.org/draft/2020-12> |
| JSON Canonicalization Scheme | <https://www.rfc-editor.org/rfc/rfc8785.html> |
| RFC 8785 verified errata | <https://www.rfc-editor.org/errata/rfc8785> |
| JSON-RPC 2.0 | <https://www.jsonrpc.org/specification> |
| WCAG 2.2 | <https://www.w3.org/TR/WCAG22/> |
| OWASP Threat Modeling | <https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html> |
| OWASP SSRF Prevention | <https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html> |
| OAuth 2.0 PKCE | <https://www.rfc-editor.org/rfc/rfc7636> |
| PostgreSQL Row Security Policies | <https://www.postgresql.org/docs/current/ddl-rowsecurity.html> |
| Kubernetes Jobs | <https://kubernetes.io/docs/concepts/workloads/controllers/job/> |
| Kubernetes Pod Security Admission | <https://kubernetes.io/docs/concepts/security/pod-security-admission/> |
| Kubernetes NetworkPolicy | <https://kubernetes.io/docs/concepts/services-networking/network-policies/> |
| Kubernetes projected ServiceAccount token | <https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/> |
| Helm charts e lint | <https://helm.sh/docs/topics/charts/> |
| scrcpy developer protocol | <https://github.com/Genymobile/scrcpy/blob/master/doc/develop.md> |
| WebCodecs | <https://www.w3.org/TR/webcodecs/> |
