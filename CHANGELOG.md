# Changelog

Todas as mudanças notáveis do Egeon Deck ficam neste arquivo.

O formato segue o [Keep a Changelog 1.1.0](https://keepachangelog.com/pt-BR/1.1.0/),
e o projeto adota o [Versionamento Semântico 2.0.0](https://semver.org/lang/pt-BR/).
O porquê de cada decisão está nos ADRs de [`docs/01-decisoes.md`](docs/01-decisoes.md),
citados entre parênteses.

## [Unreleased]

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

[Unreleased]: https://github.com/JulioRennan/egeon-deck/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/JulioRennan/egeon-deck/compare/v0.4...v1.0.0
[0.4.0]: https://github.com/JulioRennan/egeon-deck/compare/v0.2...v0.4
[0.2.0]: https://github.com/JulioRennan/egeon-deck/compare/v0...v0.2
[0.1.0]: https://github.com/JulioRennan/egeon-deck/releases/tag/v0
