# Changelog

Todas as mudanças notáveis do Egeon Deck ficam neste arquivo.

O formato segue o [Keep a Changelog 1.1.0](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adota o [Versionamento Semântico 2.0.0](https://semver.org/lang/pt-BR/).
O porquê de cada decisão está nos ADRs de [`docs/01-decisoes.md`](docs/01-decisoes.md),
citados entre parênteses.

## [Unreleased]

### Adicionado

- Notificação do macOS, com som, quando um agente precisa de você ou termina, com o Egeon Deck fora da frente: mostra a bancada, o terminal e o que está esperando; clicar abre a bancada. Segundo plano e "aguardando vizinho" não notificam.
- A bancada que terminou ganha borda verde parada na barra lateral, na pastilha do trilho e na aba; o laranja de "precisa de você" tem prioridade sobre ela.
- Perguntas do agente com opções (a ferramenta de pergunta do Claude Code) aparecem no chat com as opções como botões, e a resposta vai direto para ele; o Claude passa a ser orientado a perguntar assim (ADR-068).
- Pedidos de permissão aparecem no chat, acima da caixa de mensagem, com o comando que o agente quer rodar e os botões **Permitir**, **Sempre** e **Negar**; responder no terminal continua valendo, e o pedido some do chat (ADR-068).

### Alterado

- O agente que acionou outro e parou esperando a resposta não apita mais nem fica "terminou": o card mostra **⏳ aguardando <vizinho>** até a resposta chegar, ou "terminou" quando o vizinho encerra sem responder (ADR-067).
- O card do maestro não tem mais o `+` de puxar ligação: ele já alcança todos os terminais da bancada (ADR-066).
- A bancada que precisa de você ganha uma borda laranja que gira devagar — na barra lateral, na pastilha do trilho e na aba —, no lugar do aro parado: chama o olho sem piscar. Com "reduzir movimento" do sistema, fica só a borda.
- A ampulheta de "em segundo plano" passa a vir do próprio Claude Code — o que ainda está rodando de fundo —, e não mais do marcador que o agente lembra de escrever (ADR-067).

### Corrigido

- ⌘-clique em caminho relativo no terminal abre o arquivo mesmo com a pontuação da frase grudada (`docs/a.md.`, `(README.md)`), e passa a funcionar também em nome solto, sem barra (`README.md`, `main.swift:42`), quando o arquivo existe na pasta do terminal.

## [1.2.0] - 2026-10-06

### Adicionado

- Terminal **maestro**: marque "Maestro" no formulário de um agente e ele monta a bancada sozinho — cria terminais, escolhe CLI, modelo, esforço, papel e regras de cada um, liga as arestas e define as regras da bancada, tudo num plano validado inteiro antes de aplicar (`egeon bench`, `egeon models`, `egeon plan`, `egeon apply`) (ADR-066).
- O maestro é o mestre da bancada: alcança todo terminal e recebe a resposta de todos sem setas no canvas — as setas ficam para quem conversa entre si (ADR-066).
- O maestro abre terminais normais — servidor de dev, watcher, log — com o comando de cada um, roda comandos neles com `egeon send` e lê a saída com `egeon peek` (ADR-066).
- Quando o maestro monta ou desmonta o time, os cards se arrumam sozinhos: ele fica onde você o pôs, os agentes à direita seguindo as setas (quem recebe vai para a direita, no meio de quem manda; quem conversa nos dois sentidos fica empilhado), com espaço para as setas, e os shells embaixo. Ele também move e redimensiona qualquer terminal (ADR-066).
- O card do maestro é dourado — borda mais grossa, título e controles — e o cabeçalho mostra "· maestro" (ADR-066).
- Skill `egeon-maestro` para o Claude Code (e `egeon guide` para os outros CLIs): o manual de como desenhar uma bancada — quando vale um time, topologias, modelo e esforço por papel, como escrever papel e regras, limites de conversa e o formato do plano (ADR-066).

### Corrigido

- A ligação entre dois cards um embaixo do outro não dá mais a volta inteira por baixo para entrar pela esquerda: ela desce reta da base do de cima ao topo do de baixo, e os controles dela (direção, limite, remover) aparecem centrados no meio da linha.
- Remover uma bancada apagando as worktrees não congela mais o app: o git e o disco trabalham em segundo plano, a bancada mostra "removendo…" na barra lateral e uma cortina por cima até sair da lista, e as outras bancadas seguem usáveis enquanto isso.

## [1.1.1] - 2026-10-01

### Corrigido

- A faixa "Copiando o que o git não versiona…" não fica mais presa na tela quando outra bancada é removida (ou a lista muda) durante a cópia: ela é apagada na bancada que pediu, pelo id, e não pela posição na lista.

## [1.1.0] - 2026-10-01

### Adicionado

- Multi-projetos no formulário do workspace: dê um nome e escolha algumas das pastas; a bancada dele abre todas juntas numa pasta só, e em worktree cria a mesma branch em cada repositório, lado a lado — ou uma branch própria no repo que você quiser, sem mudar a pasta (ADR-065).
- O seletor de modelo mostra os modelos pelo nome ("Opus 5.5", "Fable 5.1"), lidos do Claude Code instalado — atualizar o CLI atualiza a lista; versões anteriores ficam num submenu e os apelidos seguem disponíveis como "sempre o mais recente" (ADR-064).
- O slider de esforço mostra só os níveis que o modelo aceita, com o "auto" dizendo o padrão dele (ex.: "auto (medium)"); modelo sem esforço deixa o slider desligado (ADR-064).
- A faixa de modelo e esforço só aparece quando há o que escolher: Codex e Gemini, sem lista de modelos no `agents.json`, ficam com o cabeçalho de antes (ADR-064).
- Botão de ultracode na faixa do cabeçalho, independente do nível de esforço; também por `/model?target=…&ultracode=on|off` (ADR-064).
- Modelo e esforço (`--effort`: low · medium · high · xhigh · max) numa faixa própria no cabeçalho do card de agente, embaixo do nome: o esforço é um slider com uma marca por nível (a primeira é o auto, o padrão do modelo), que também responde à rolagem e só aplica 1s depois de você soltar. Também no formulário e por `/model?target=…&effort=…`; trocar reinicia o terminal e a conversa continua (ADR-064).

### Alterado

- Copiar para a worktree nova o que o git não versiona ficou uns 6× mais rápido: cada entrada (ex.: `node_modules`) é clonada inteira de uma vez no APFS, em vez de arquivo por arquivo, e sem pausa entre os repositórios — `nexus-web-app` + `nexus-backend` de ~21 s para ~3 s. Quem personalizou o `worktree-copy.sh` continua com o script dele.
- Bancada de multi-projeto só nasce em worktree: o + do multi-projeto abre direto o formulário de worktree, e "Nova bancada…" não aparece para ele (ADR-065).
- Modelo, esforço e ultracode ficam numa barra à parte embaixo do cabeçalho do card, com fundo próprio e o rótulo em cima de cada controle (ADR-064).
- Terminal novo sugere a configuração do CLI (ex.: `~/.claude-agro`) escolhida por último naquele workspace; escolher o padrão apaga a lembrança. O padrão aparece pelo caminho que o CLI usa sem configuração (`~/.claude`, `~/.codex`), não mais como "padrão da CLI".
- Formulário de terminal refeito: Shell e Agente viram abas, e os campos seguem a aba — shell tem nome, comando e pasta; agente tem CLI em radios, modelo e esforço, configuração (popup com as descobertas, e um + ao lado do título para outra), pasta, e papel e regras lado a lado. Campo que o CLI não tem não aparece.
- A pasta do terminal é uma lista de radios — root e as subpastas da bancada que são repositório (em multi-projeto, cada repo), sempre relativas —, com um + ao lado do título para outra pasta (ADR-065).

### Corrigido

- Abrir o chat de uma bancada com histórico longo não carrega mais centenas de mensagens de uma vez: a descida animada até o fim passava pelo topo e disparava o "carregar mais" a cada quadro; agora entram só as 60 do fim (ADR-045).
- O comando de um terminal shell agora é guardado: antes ele se perdia ao salvar como componente e ao editar o terminal.
- Depois de trocar de modelo, o seletor do cabeçalho não mostra mais o modelo antigo (ex.: "haiku (fable)") até o novo responder: só conta resposta dada depois do arranque atual.
- Trocar de bancada pelo teclado (⌘1…⌘9, ⌘]/⌘[, ⌘→/⌘←) não apaga mais a ampulheta de "em segundo plano" do terminal que estava focado: atalho do app deixou de contar como você digitando nele (ADR-063).

## [1.0.0] - 2026-09-28

Primeira versão estável. Consolida tudo o que existe até aqui: um canvas macOS em
que cada nó é uma ferramenta de trabalho real, feito para dirigir vários agentes de
IA em paralelo.

### Adicionado

#### Canvas e vistas
- Canvas infinito com quatro tipos de nó: editor (code-server), terminal, terminal
  com agente de IA e navegador. O canvas cresce quando se arrasta ou rola além da
  borda, e um botão enquadra todos os nós.
- Três vistas dos **mesmos** nós, sem reiniciar processo: canvas, mosaico (arranjo
  arrastável) e chat, com ⌥⌘1/2/3 (ADR-016, ADR-023, ADR-029).
- Barras flutuantes em vidro; a barra lateral recolhe com ⌘/ (ADR-025).
- Mão do ponteiro em tudo que responde a clique (ADR-048).

#### Organização do trabalho
- Hierarquia workspace → projeto → bancada, com foto ou inicial no workspace,
  reposicionamento por arrasto nos três níveis, selos de contagem e gaveta para
  projetos guardados (ADR-043, ADR-051, ADR-052).
- Abas com as bancadas abertas no topo, com os mesmos badges da barra lateral.
  Fechar a aba não encerra a bancada. Arrastar reordena; ⌘1…⌘9, ⌘]/⌘[, ⌘→/⌘← e ⌘W
  navegam; a faixa volta no arranque (ADR-061, ADR-062).
- Worktree git por bancada e por terminal, e remover a bancada oferece apagar as
  worktrees dela (ADR-017, ADR-018, ADR-021).
- Templates de bancada e de nó, com componente de nó independente de CLI
  (`byAgent`) (ADR-057).

#### Agentes
- Agente plugável por `~/.egeon/agents.json`, com `claude`, `codex`, `opencode` e
  `gemini` já configurados (ADR-009).
- Prompt injetado na sessão viva do CLI, com fila por terminal (ADR-007).
- Estado de cada terminal pelos ganchos do CLI: preparando, trabalhando,
  ⏳ em segundo plano, terminou (verde) e precisa de você (laranja, com som)
  (ADR-024, ADR-034).
- Protocolo de fim de turno pedido ao modelo: `[[ED:ok]]`, `[[ED:ask]]` e
  `[[ED:wait]]` (ADR-011, ADR-063).
- Modelo por nó, trocado pelo cabeçalho, que mostra o modelo literal em uso; trocar
  reinicia o processo e retoma a conversa (ADR-035).
- Papel e regras separados, com regra da bancada somada à do nó, entrando depois do
  papel no system prompt (ADR-056).
- A conversa de cada agente sobrevive a rebuild e reinício do app (ADR-014).

#### Coordenação entre agentes
- Arestas desenhadas no canvas dizem quem pode acionar quem; o par nasce
  bidirecional (ADR-012, ADR-028).
- Comando `egeon` dentro dos terminais: `peers`, `send`, `status`, `peek` e
  `trace`. A identidade de quem chama vem do pid da conexão, nunca do texto
  (ADR-040, ADR-054).
- Guardas de cadeia fora do prompt: aresta obrigatória, `maxSends` por aresta,
  `maxVisits` por bancada e teto de fila (ADR-012).
- Skill `egeon` publicada no Claude Code, para que "pede pro fulano" acione o
  vizinho em vez de um subagente; mensagens chegam com o envelope `[ED]`, e quem
  recebe responde ao remetente (ADR-054, ADR-055, ADR-058).

#### Chat
- Modo chat da bancada: participantes com cor e estado, composer com `@menção`,
  linha do tempo plana e turno ao vivo lido do transcript (ADR-039, ADR-042).
- Passos de ferramenta recolhidos, agrupados numa capa que aprofunda ao clique; diff
  lado a lado sempre visível; leitura com realce por linguagem (ADR-041, ADR-044,
  ADR-046, ADR-049, ADR-050, ADR-053).
- Histórico persistido pelo app por bancada, e "Limpar a bancada", que espera os
  agentes e arquiva chat e trilha (ADR-037, ADR-059).

#### Trilha da bancada
- `egeon trace` grava um Markdown por bancada, carimbado com quem, CLI, modelo e
  conversa; o shell registra os comandos sozinho (ADR-036).

#### Terminal
- Arrastar arquivo para o terminal cola o caminho; imagem vira anexo no Claude Code
  (ADR-026).
- ⌘-clique em caminho de arquivo ou URL abre, com sublinhado e mão ao passar o
  mouse; ⌘-clique no caminho do card abre a pasta no Finder.
- Voz pelo CLI dentro do terminal, com o microfone pedido pelo app (ADR-027).

#### Editor
- code-server embutido no canvas (ADR-003) e extensão própria de review inline de
  Markdown, com comentários ancorados em conteúdo (ADR-004, ADR-005, ADR-005b).

#### Operação
- Socket de controle HTTP em `~/.egeon/sock`, que é como se dirige e se testa o app
  de fora.
- Dois flavors que convivem, estável e dev, com config, socket, log e porta próprios
  (ADR-015, ADR-033).
- `install.sh`, `dist.sh` (zip universal e arm64) e `cert.sh` (identidade de
  assinatura estável).

### Corrigido
- O fim de turno não é mais lido cedo demais quando o gancho `Stop` chega antes da
  última linha do transcript, o que deixava o card em "terminou" (ADR-063).
- Limpar a bancada espera os agentes assentarem antes de arquivar (ADR-059).
- Remoção de worktree em que o git desiste no meio não é mais dada como falha
  (ADR-060).

## [0.4.0] - 2026-08-26

Pré-release.

### Adicionado
- Modo chat: participantes, composer estilo Slack, envio real e respostas dos
  agentes.
- Trilha da bancada com `egeon trace`, e histórico do chat persistido com
  "Limpar a bancada".
- Modelo por nó de agente, com o modelo literal no cabeçalho.
- Estado "preparando" até o `SessionStart` do CLI.
- Linha de ida e volta entre agentes com ponta nas duas extremidades.
- Arrastar arquivo para o terminal.

### Corrigido
- Uma segunda instância do mesmo flavor não sobe mais.
- O socket de controle confere se continua dono do arquivo dele.
- O `install.sh` instala só em `/Applications` e denuncia cópias gêmeas.

## [0.2.0] - 2026-08-18

### Adicionado
- Primeiro empacotamento para distribuição: zip universal e zip arm64.

## [0.1.0] - 2026-08-18

Primeira versão para passar adiante (tag `v0`).

### Adicionado
- Canvas infinito com nós de editor, terminal, agente de IA e navegador.
- Canvas e mosaico como duas vistas dos mesmos nós.
- Worktree por sessão e por terminal.
- Ligações entre agentes com quatro guardas, e `egeon peers` / `egeon send`.
- Aviso de "terminou" e "precisa de você" vindo do gancho do CLI.
- Socket de controle em `~/.egeon/sock`.

[Unreleased]: https://github.com/JulioRennan/egeon-deck/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/JulioRennan/egeon-deck/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/JulioRennan/egeon-deck/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/JulioRennan/egeon-deck/compare/v0.4...v1.0.0
[0.4.0]: https://github.com/JulioRennan/egeon-deck/compare/v0.2...v0.4
[0.2.0]: https://github.com/JulioRennan/egeon-deck/compare/v0...v0.2
[0.1.0]: https://github.com/JulioRennan/egeon-deck/releases/tag/v0
