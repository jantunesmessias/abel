# ADR-0012 — Composição modular configurável do Abel

Status: aceita em 2026-08-10.

## Contexto

O Abel implementou progressivamente catálogo, Studio, Sessions, App
Adapter, Gateway, Evidence, Android, source impact, plugins, hosted e remote.
Essas capabilities possuem contratos e alguns pontos de configuração próprios,
mas a composição do produto ainda é majoritariamente estática:

- a CLI registra todos os comandos em um parser e dispatcher únicos;
- o Host constrói store, processos, Sessions, captura e Gateway diretamente;
- o Studio declara rotas fixas;
- a distribuição v1 exige CLI, Host, Gateway e Studio;
- loaders diferentes voltam a ler `workspace.local.yaml` para necessidades locais.

Esse arranjo não materializa a propriedade central de um Kit: consumidores
com necessidades diferentes devem poder selecionar somente as superfícies,
providers e efeitos que desejam. AutoPreview introduziria mais um caminho de
captura e, se fosse apenas ligado à composição atual, ampliaria o monólito em
vez de corrigir o problema.

A composição também não pode reutilizar `Plugin` como sinônimo de feature.
Plugins v1 são extensões externas não confiáveis, one-shot e out-of-process.
Módulos built-in são código confiável, empacotado e registrado estaticamente.
Da mesma forma, `CapabilityDescriptor` de Sessions continua descrevendo
operações efetivas de um `ExecutionTarget` e não passa a representar módulos.

## Decisão

### 1. Taxonomia

- `Kernel` é a infraestrutura mínima obrigatória de configuração, resolução,
  lifecycle, health, segurança, protocolo, logging e diagnóstico.
- `Module` é uma unidade funcional built-in que pode ser habilitada.
- `Capability` é um contrato estável fornecido ou requerido por módulos.
- `Provider` é uma implementação selecionável de uma capability.
- `Profile` é um overlay declarativo de seleção e settings.
- `Plugin` permanece extensão externa out-of-process.
- `Grant` autoriza uma ação já disponível; não habilita Module nem Capability.

As dimensões `packaged`, `enabled`, `ready` e `authorized` são independentes.

### 2. Catálogo e seleção

Módulos built-in são registrados em catálogo compile-time. Configuração nunca
carrega Dart arbitrário, usa reflexão ou transforma path de consumer em código
in-process. Um módulo lógico só se torna package quando publicação, Flutter,
runtime, owner ou deploy boundary justificarem a extração.

Profiles não contêm branches especiais de produto. Eles expandem para a mesma
seleção declarativa aceita pela configuração explícita. Módulo que produz
efeitos ou consome recursos não é habilitado silenciosamente para satisfazer
outro módulo: a resolução falha com dependência ausente, e ferramentas de
adoção podem propor o patch completo em dry-run.

### 3. Plano canônico

Configuração e catálogo empacotado são normalizados em `ResolvedKitPlan`
antes de filesystem mutável, subprocesso, device, listener ou rede. O plano é
fechado, canônico, digerido e define módulos, provider bindings, settings e
ordem de startup.

CLI, Host e Studio usam o mesmo plan digest. O Host publica
`EffectiveKitManifest` com o estado observado, health, capabilities, comandos,
RPCs e contribuições do Studio. Nenhuma superfície resolve uma topologia
alternativa por conta própria.

### 4. Configuração canônica

O consumer config publicado inclui `kit`, profiles, modules e provider
bindings. Uma única revisão atravessa o resolver e o composition root; revisões
anteriores ao contrato publicado falham antes de efeitos. Não existe runtime
legado paralelo.

A precedência é:

```text
Kernel defaults
< Distribution defaults
< Profile
< Workspace config
< local config
< startup overrides
```

Depois do startup, a topologia é imutável. Settings só podem mudar sem restart
quando o contrato do módulo declarar explicitamente essa possibilidade.

### 5. Lifecycle e ausência

O lifecycle é `resolve → validate → prepare → start → ready → stop → disposed`.
Falha durante startup interrompe dependentes e desfaz módulos já iniciados em
ordem inversa. Todo recurso assíncrono continua com owner, cancellation e
cleanup explícitos.

Módulo desabilitado produz zero comando, RPC, rota, processo, porta, probe,
acesso a device e artifact. Ausência é comportamento verificável, não apenas
um booleano de UI.

### 6. Composition roots

- a CLI usa parsing bootstrap em duas etapas e contribuições de comandos;
- o Host recebe `ResolvedKitPlan`, registra RPCs por contribuição e permanece
  autoridade local para efeitos;
- o Studio lê `EffectiveKitManifest` e compõe navegação/rotas declarativas;
- Gateway, Android e AutoPreview continuam adapters/providers sob os bounded
  contexts existentes, sem criar novo domínio.

Módulos recebem configuração tipada e capabilities declaradas por
`ModuleContext`; não recebem service locator irrestrito e não releem arquivos
de configuração.

### 7. Distribuição

A evolução ocorre em duas etapas:

1. a distribuição completa continua empacotando os componentes atuais, mas o
   runtime inicia apenas módulos selecionados;
2. Distribution registra ModuleCatalog e permite bundles enxutos com
   componentes condicionais e composition entrypoints gerados somente em
   `.dart_tool`.

CLI permanece o launcher obrigatório. Configuração que habilita módulo não
empacotado falha antes de efeitos.

### 8. Primeiro vertical

Gateway é o primeiro recurso existente extraído, porque já possui opcionalidade
parcial, processo, porta e lifecycle observáveis. AutoPreview é o primeiro
recurso novo construído diretamente como Module e EvidenceProvider. Esses dois
casos satisfazem a regra de governança que exige segundo caso para uma nova
abstração.

## Alternativas consideradas

### Manter o monólito com flags

Rejeitada. Flags dispersas não fornecem dependency graph, provider resolution,
rollback, composição consistente entre processos nem prova de ausência.

### Transformar todas as features em plugins externos

Rejeitada. Perderia APIs tipadas, aumentaria IPC e confundiria extensão não
confiável com composição de produto confiável. O boundary de Plugin atual é
preservado.

### Carregamento dinâmico in-process

Rejeitada. Amplia supply-chain e privilégio do Host, complica AOT e contradiz a
decisão de plugins out-of-process.

### Resolver módulos separadamente em cada aplicativo

Rejeitada. CLI, Host e Studio poderiam divergir sobre disponibilidade, settings
e claims. `ResolvedKitPlan` é deliberadamente único.

## Consequências

- Consumer config adota uma única revisão canônica; Distribution preserva sua
  política própria de leitura e instalação.
- A CLI e o Host deixam de ser composition roots monolíticos.
- O Studio passa a distinguir indisponibilidade de falta de autorização.
- ExecutionFingerprint inclui o plan digest relevante para a execução.
- Testes passam a cobrir ausência, dependency graph e rollback além do caminho
  habilitado.
- Existe custo de descriptors, schemas e conformance, mitigado por módulos
  coarse-grained e proibição de package sprawl.
- Resultados todas as capacidades históricas continuam evidência histórica e não são reescritos.

## Rollout e rollback

1. composition root novo em shadow mode;
2. consumer config canônico antes de qualquer consumer externo publicado;
3. Distribution modular opt-in e depois default;
4. remoção do registro estático somente após paridade completa.

Rollback usa a distribuição imutável anterior e não reescreve o arquivo
autoral do consumer.

## Evidência requerida

- schemas/codecs e resolver determinístico;
- CLI, Host e Studio observando o mesmo plan digest;
- profiles `journey-preview`, `journey-android`, `gateway-lab` e `full-local`;
- ausência sem efeitos por módulo;
- failure injection e rollback inverso;
- Gateway, AutoPreview e Android isolados e combinados;
- distribuição completa e enxuta reproduzíveis;
- gates históricos todas as capacidades históricas preservados.

O plano de implementação e a matriz documental vivem em
`docs/architecture/modular-kit-refactor-plan.md`. Resultado só será registrado
depois da execução dos gates, em artifacts separados de evidência.
