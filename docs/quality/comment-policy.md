# Política de comentários

Código first-party deve comunicar intenção por nomes, tipos, estrutura e testes.
O gate lexical em `tools/gates/comment_policy.dart` usa o tokenizer do analyzer
para Dart e scanners com estados de strings, heredocs e blocos para as demais
linguagens mantidas.

As exceções são:

- documentação de API nos packages reutilizáveis em `libs/*/lib/`;
- shebangs, diretivas do analyzer, ShellCheck, formatter e coverage;
- markers de arquivos gerados e notices legais obrigatórios;
- justificativas dentro de `catch` vazios exigidas pelo analyzer;
- comentários dos arquivos de interoperabilidade e segurança enumerados em
  `CommentPolicy.securityRationaleFiles`;
- proveniência operacional, persistência e supply chain nos arquivos
  enumerados em `CommentPolicy.operationalRationaleFiles`;
- arquivos exatos do scaffold Flutter/Android enumerados por `_isGeneratedFile`.

Strings, URIs, regexes, dados YAML em block scalars e conteúdo de heredocs não
são classificados como comentários. Uma nova exceção exige path e motivo
específicos no gate.
