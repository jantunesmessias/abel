# Threat model do DevEx Studio Jaspr

Status: ativo; controles locais revalidados em 2026-08-11. Decisão: ADR-0016.

## Assets e boundaries

Protegemos token de sessão, grants Remote, catálogo, Evidence, artifacts,
workspace, CAS, processos, Gateway e target consumidor.

```text
Studio Jaspr no browser
  ├─ HTTP bootstrap/resources + WebSocket RPC ─> Host loopback
  ├─ iframe sandboxed ─> target consumidor em outro origin
  └─ WSS/HTTPS com grant efêmero ─> remote session gateway

Host ─> Engine/Runtime/CAS/filesystem/processos/Gateway
```

O browser não é autoridade de domínio, filesystem ou fidelity. O Studio é
client-side; não existe SSR com acesso adicional a segredos.

## Invariantes

1. token existe somente no bootstrap `no-store` e memória volátil;
2. token não entra em URL, HTML, JS gerado, defines, logs, storage ou cookie;
3. primeiro frame RPC é `devex.initialize`;
4. Origin é exato em bootstrap, WebSocket e resources;
5. handles são opacos, purpose/TTL/size/media/digest-bound;
6. Studio não recebe path CAS, não importa `dart:io` e não inicia processo;
7. target iframe usa origin separado, sandbox e `no-referrer`;
8. postMessage valida origin, source, session, nonce e sequence monotônica;
9. Remote grant é expirável, one-time e seleciona exatamente um transporte;
10. Module disabled deixa zero rota, RPC, process, listener, port ou probe;
11. payload desconhecido, oversized ou fora de versão falha fechado;
12. reconnect obtém novo bootstrap e não promove snapshot stale a fresh.

## Ameaças e evidência

| Ameaça | Controle | Evidência/status |
|---|---|---|
| site lê bootstrap | loopback, Origin/CORS exatos, query proibida, no-store | negativos Host + bootstrap real: Confirmed local |
| token persiste | resposta/memória apenas; build sem token/maps | scan/build: Confirmed local |
| RPC sem auth/replay | initialize obrigatório e token efêmero | Host negatives: Confirmed local |
| handle forjado/expirado | purpose/origin/type/size/expiry/digest antes de Blob | component + browser resources: Confirmed local |
| path traversal/symlink | browser não recebe path; Host resolve root | Host tests: Confirmed local |
| XSS exfiltra token | escaping Jaspr, sem raw HTML, CSP self | architecture/CSP/Chrome logs: Confirmed local |
| DWDS amplia CSP release | hash exato somente no index dev; release self | build/headers: Confirmed local |
| iframe toma autoridade | sandbox, no-referrer, source/origin/envelope | contracts/component: Confirmed; consumer real é environment-dependent |
| Gateway usa plan/path arbitrário | owner Session ready + digest CAS + JCS canônico | Host lifecycle: Confirmed local |
| Remote reutiliza credential | vault `take`, expiry, one transport, close cleanup | pure/component/protocol: Confirmed; endpoint real Partial |
| H.264 exaure browser | sizes protocol, queue <=8, canvas dimensions <=16384 | state machine/build: Partial sem stream externo real |
| payload exaure DOM | Host limits + canvas window <=24 + Outline | 10k policy + browser sample: Confirmed bounded DOM |
| module disabled deixa surface | plan/contribution gating e headless bundle | matrix/components + dois bundles reproduzíveis; headless sem Studio: Confirmed local |

## CSP

Release opera com `default-src 'none'`, `script-src 'self'`, styles/fonts self,
`img-src 'self' blob: data:`, connect/frame origins derivados da topologia,
`base-uri 'none'`, `form-action 'none'` e `frame-ancestors 'none'`.

Hot reload Jaspr usa policy distinta e somente o hash exato do loader DWDS.
`unsafe-inline` e `unsafe-eval` permanecem proibidos. Upgrade Jaspr/DWDS exige
novo hash e conformance.

## Negativos obrigatórios

- Origin ausente/incorreto e query no bootstrap;
- token ausente/inválido/expirado/replay e frame pre-auth;
- handle expirado/forjado/purpose/media/type/digest incorretos;
- URI absoluta/esquema/path/symlink não autorizados;
- postMessage com source/origin/session/nonce/sequence incorretos;
- Remote grant expirado/duplicado, metadata/frame fora de ordem ou oversized;
- Gateway sem owner ready ou plan CAS/JCS válido;
- JSON desconhecido/oversized e shutdown com recurso residual;
- scan de secrets em HTML, JS, CSS, maps, logs e manifests.

## Riscos residuais

- processo malicioso do mesmo usuário pode observar memória/requests locais;
- extensão/debugger do browser está fora do boundary v1;
- pixels podem conter dados classificados incorretamente pelo consumer;
- supply chain web exige revisão a cada upgrade;
- CSP dev não equivale à CSP release;
- sandbox portátil não certifica contenção de OS, rede ou memória;
- Remote/Hosted/KVM reais exigem seus ambientes externos.

Nenhum controle Partial é convertido em aceito por causa do baseline Flutter
histórico.
