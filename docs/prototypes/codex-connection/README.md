# Protótipos: conectar Claude e Codex

Abra `index.html` diretamente no navegador. A página funciona localmente, sem build, servidor ou dependências.

Três alternativas interativas:

- **A — Abas sempre à mão:** Claude e Codex lado a lado. Recomendada pela proximidade com o app atual.
- **B — Uma conta de cada vez:** seletor compacto com as contas e a opção de conectar.
- **C — Símbolos como atalhos:** acesso pelos símbolos dos serviços.

Experimente selecionar o Codex, clicar em **Conectar Codex**, iniciar o login e usar os controles de simulação para concluir ou falhar. Também é possível cancelar, tentar novamente, abrir configurações, desconectar, trocar o período dos tokens e alternar entre temas claro e escuro. Cada proposta mantém seu estado separado. Os controles acima da comparação permitem visualizar as três já conectadas ou reiniciar a demonstração.

Todo login, plano, percentual, horário e número de tokens é ilustrativo. As janelas do Codex e a visualização de tokens precisam ser ajustadas ao payload real na implementação. O protótipo não consulta contas, não inicia autenticação e não altera o app Swift ou as configurações dos CLIs. O meio exato pelo qual o login do Codex será iniciado fica para a implementação; o protótipo representa a jornada e seus estados.

## Arquivos

- `index.html`: comparação das propostas e símbolos SVG.
- `styles.css`: materiais, tipografia, temas e layout responsivo.
- `prototype.js`: estados e interações da demonstração.

## Crédito do símbolo

Símbolo OpenAI de [Bootstrap Icons](https://github.com/twbs/icons/blob/main/icons/openai.svg), distribuído sob licença MIT, copyright The Bootstrap Authors. O símbolo Claude é uma representação vetorial para estudo de interface. As marcas pertencem aos respectivos titulares.
