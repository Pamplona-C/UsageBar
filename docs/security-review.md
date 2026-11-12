# Revisão para publicação pública

Revisão local em 12/11/2026. Este registro descreve o que foi verificado e não equivale a uma garantia de ausência
de vulnerabilidades. A publicação deve considerar também os metadados do histórico Git.

## Escopo

- Código Swift, scripts do bridge, instalação/remoção, empacotamento e workflows.
- Arquivos rastreados e novos que podem entrar no commit; arquivos ignorados não entram na exportação pública.
- Histórico alcançável pelas referências Git locais, incluindo tags.
- Fixtures, documentação, imagens e conteúdo do `.app` de distribuição.
- Dependências: o pacote Swift não declara bibliotecas de terceiros. O símbolo OpenAI possui atribuição MIT
  copiada da licença oficial de Bootstrap Icons. Os CLIs e frameworks do sistema são dependências externas e não
  foram auditados internamente.

## Verificações e correções

- Gitleaks 8.30.1, obtido da release oficial e verificado por SHA-256, sem segredos detectados nas varreduras do
  código/histórico. Os relatórios detalhados permanecem fora dos arquivos publicados.
- Verificação adicional de nomes de arquivos sensíveis, caminhos pessoais, endereços de email, URLs com
  credenciais, chaves privadas, links simbólicos e metadados de imagens.
- Imagens do README geradas pelos componentes nativos usando dados fictícios, sem captura da área de trabalho.
  Exportação em sRGB sem EXIF, XMP ou campos de texto; nenhuma imagem usa a conta real.
- Fixtures do Codex usam valores de exemplo; não contêm identificadores da conta. O email da fixture de login
  do Claude usa domínio de exemplo.
- Bridge: diretório e executável privados, arquivos e backups com permissões restritas, backups únicos e quoting
  POSIX de caminhos. Links simbólicos nos arquivos gerenciados são recusados. O comando original não é impresso.
- Migração do quoting antigo preserva o comando original e evita encadear o bridge nele mesmo.
- Login do Claude, assim como o do Codex, usa um diretório temporário exclusivo e privado.
- Parsers rejeitam percentuais/datas extremos e contadores inválidos; somas de tokens não causam overflow fatal.
- Consultas ao Claude e descoberta do Codex têm saída e tempo limitados, com encerramento de processos que ignoram
  SIGTERM. A consulta JSON-RPC do Codex já tinha um prazo e limite de buffer.
- `.gitignore` cobre credenciais locais, backups, logs, relatórios privados e artefatos gerados.
- Workflows usam checkout fixado por commit, sem persistir credenciais. A release depende do gate de segurança,
  que executa Gitleaks e a verificação de privacidade, incluindo emails nos metadados dos commits.
- Testes de regressão cobrem injeção por caminhos, permissões, backups, migração, links simbólicos, valores extremos,
  overflow, timeout e saída excessiva. A suíte completa passou com **153 testes**.

## Metadados do histórico original aprovados

O histórico anterior contém um email pessoal nos campos de autoria/commit. Nenhuma chave ou token foi identificado,
mas esse endereço continuaria visível ao publicar esse histórico. Alterar só o código ou adicionar `.gitignore`
não remove metadados antigos.

O mantenedor autorizou expressamente a publicação com esses metadados em 12/11/2026. Os 35 commits revisados estão
listados por hash em `.publication-policy.json`, limitados aos ancestrais do commit anterior à integração.
O gate `python3 tools/check-publication.py --history` continua bloqueando emails pessoais nos novos commits,
exceções fora do histórico aprovado e arquivos com dados privados. Nenhum email é adicionado ao arquivo de política.
O histórico e as tags anteriores são preservados; os novos commits usam a identidade `noreply` do GitHub.

Uma exportação sem `.git` pode ser preparada com:

```bash
python3 tools/check-publication.py --export .build/public-source
```

A pasta de destino deve ser nova. A exportação copia somente os arquivos candidatos que passaram na checagem,
sem histórico, configurações Git, caches ou relatórios locais. Ela ainda deve passar pelo scanner de segredos e
ser inicializada com uma identidade pública antes de receber commits.

O código próprio do projeto ainda não possui uma licença de distribuição definida. A licença do símbolo de
terceiro não define automaticamente a licença do restante do projeto.
