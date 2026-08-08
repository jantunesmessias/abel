# Documentação

[ARCHITECTURE.md](../ARCHITECTURE.md) é a entrada normativa da arquitetura. Os
documentos abaixo aprofundam responsabilidades específicas sem substituí-la.

- [Arquitetura](architecture/README.md): components, boundaries, dados e
  decisões arquiteturais.
- [Contratos](contracts/): formatos públicos, configuração, Evidence,
  distribuição e workspace.
- [Protocolos](protocols/): Host, App Adapter e MCP.
- [Qualidade](quality/): gates, matrizes de evidência e conformance.
- [Operações](operations/): startup, módulos e recuperação.
- [Segurança](security/): threat models por boundary.
- [Design system](design-system/): linguagem visual e interação do Studio.

Resultados datados em `architecture/` são evidência de uma execução específica,
não certificação contínua. Comandos canônicos atuais são expostos por
`melos run --list` e usados pelo CI.
