# Ferramentas do repositório

`tools/` contém automação transversal. Ferramentas pertencentes a um único
package permanecem no `tool/` singular daquele package.

- `gates/`: policy-as-code e fitness functions determinísticas;
- `verify/`: verificações de contracts, builds e verticais executáveis;
- `probes/`: clientes e drivers de observação, sem autoridade de produto;
- `benchmarks/`: medições com budgets explícitos;
- `generators/`: geração first-party usada pelos gates;
- `hosted/`: operações e verificações que dependem do control plane hosted.

Os entrypoints públicos são os scripts do Melos no `pubspec.yaml` raiz. Arquivos
deste diretório são implementação desses scripts, não uma segunda matriz de CI.
Os gates `policy` e `comments` também integram `melos run check`.

Os testes de reversibilidade em `verify/*_reversibility_test.sh` são companions
de fault injection dos verticais correspondentes. Eles são executáveis
diretamente quando a alteração toca cleanup, restauração de fontes, processos,
ports ou estado privado do gate.
