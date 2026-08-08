# DevEx Studio

O único DevEx Studio é uma SPA Jaspr client-side. Não há renderer ou fallback
Flutter neste app.

```bash
jaspr serve --release \
  --port 39012 \
  --dart-define=DEVEX_STUDIO_BOOTSTRAP_URL=http://127.0.0.1:39011/devex/bootstrap.json
```

O Host correspondente deve autorizar exatamente
`http://127.0.0.1:39012` por `--studio-dev-origin`. Para release:

```bash
jaspr build
```

Leia [operação](../../docs/operations/studio-startup.md),
[contribuição](../../docs/operations/studio-contributing.md),
[UI System](../../docs/design-system/ui-system.md) e
[conformance](../../docs/quality/studio-conformance-v1.md).
