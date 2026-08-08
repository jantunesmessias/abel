# Threat model Studio ↔ Host

Status: ativo e revisado no gate Jaspr em 2026-08-11. Owners: Studio + Host +
Security. Decisão: ADR-0014.

## Escopo e assets

Protegemos workspace, catálogo, CAS, artifacts, processos e token do Host
contra uma página web não autorizada, URL previsível, documento adulterado,
path traversal, resource expirado e Module desabilitado.

Trust boundaries:

```text
browser/Studio ──HTTP+WS──> Host loopback ──filesystem/process/device──> host OS
```

O browser e seus pixels não são autoridade. O Host e Modules built-in são
trusted code local. Plugin externo, consumer preview e target executam fora do
Host conforme seus próprios boundaries.

## Ameaças e controles

| Ameaça | Controle | Evidência |
|--------|----------|-----------|
| site malicioso abre WebSocket | Origin exato + token somente no `initialize`; query proibida | negativos de Origin/token/query/pre-auth |
| resposta RPC causa exaustão | frame/response/event limit de 64 KiB | oversized response/event tests |
| URL de artifact é enumerável | capability aleatória, não digest/path | contract + registry tests |
| grant é reutilizado de outro site | audience Origin + CORS exato | 403 para attacker Origin |
| token vaza em URL/output | bootstrap body `no-store`; output omite token | CLI/supervisor tests |
| site lê bootstrap de hot reload | endpoint opt-in, loopback, CORS e `Origin` exatos; query proibida | negativos sem Origin/attacker/query |
| snapshot é forjado | schema fechado + digest + cross-reference | contracts corpus negativo |
| CAS muda após grant | bytes owned e digest revalidado | registry invariant |
| resource sobrevive ao run | TTL/revoke/clear no shutdown | cleanup/port tests |
| Module disabled deixa superfície | registro por plan; provider disabled filtrado | matrix negativa focada |
| path/link escapa assets | root resolvido e links recusados | server validation |
| Evidence eleva fidelity | provider-neutral projection e AutoPreview structural-only | constructor/schema tests |
| script remoto altera o Studio | CSP `script-src self` e assets Jaspr locais, sem CDN | Google Chrome release sem log severo |

## Bootstrap local

No modo empacotado, o bootstrap exige `Sec-Fetch-Site: same-origin`, não aceita
query, não habilita CORS e nunca é cacheável. No hot reload, ele é exposto pelo
Host somente quando `--studio-dev-origin` foi configurado com um origin HTTP
loopback; exige `Origin` exato, responde com CORS para essa única audience,
mantém `no-store` e continua proibindo query. `STUDIO_BOOTSTRAP_URL`
contém apenas o endpoint, nunca o token.

Esses controles impedem leitura por outra página no modelo do browser. Não
constituem autenticação contra outro processo local capaz de forjar HTTP headers
ou inspecionar a memória do usuário. O Host local assume o mesmo usuário do
sistema como boundary operacional; ambientes multiusuário ou hostis precisam
acrescentar isolamento de OS ou um canal nativo autenticado.

Essa limitação é explícita: não se descreve Fetch Metadata como containment de
processo local.

## Resource classification

O registry aceita `public` e `internal`; `sensitive` falha antes de criar grant.
Isso não classifica automaticamente pixels do consumer. O provider deve exigir
policy de dados sintéticos antes da persistência e o Host só emite handle para
artifact já autorizado.

## AutoPreview

O runner continua subprocesso. Environment allowlisted, timeout, staging e
limites de output reduzem impacto, mas não provam sandbox portátil. Rede e
memória dependem do sandbox do host; sem prova, o fingerprint permanece
`NetworkContainment.unconstrained`. `flutter-test` declara somente
`structural`. A UI repete essa limitação e não trata fingerprint como prova de
plugins, SO, permissões, teclado ou comportamento host-native.

## Riscos residuais

- malware no mesmo usuário pode observar processos/memória ou forjar requests;
- DoS local pode consumir portas/CPU antes dos limites de aplicação;
- segurança dos assets depende da integridade verificada da Distribution;
- screenshot autorizado ainda pode conter dados que o consumer marcou
  incorretamente como sintéticos;
- browser extensions e debugging local estão fora do boundary v1.
- o servidor Jaspr/DWDS de hot reload é tooling de desenvolvimento e não substitui
  a integridade/CSP do bundle release usado pela conformance.

## Gates executados

- negativos de Origin, query/token, pre-auth, frame oversized, resource
  expirado/forjado/media type e Module desabilitado;
- CSP release Jaspr self-only e hash DWDS exato somente no hot reload;
- browser E2E com Host real, handles/PNGs reais e zero log severo;
- resources bounded, digest verificado, `sensitive` negado e cache `no-store`;
- vinte ciclos Host + Studio e shutdown por sinal sem listener residual;
- Distribution slim canônica e supply-chain/architecture guards; reproduções Jaspr
  modular e full passaram com bundles de mesmo digest, incluindo headless sem
  Studio.

Esses gates são locais e portáteis; não alteram os riscos residuais nem
certificam sandbox de OS, host multiusuário ou infraestrutura hosted control plane/remote execution.
