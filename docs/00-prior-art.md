# Egeon Deck — prior art (pesquisa 2026-08-09)

Problema: uma aplicação só que gerencia N "tabs de projeto"; cada tab = layout salvo com
vários terminais (back/front/claude code) + VSCode. Mais: spec em markdown onde clicar
numa linha dispara a mudança na sessão certa, sem copiar/colar em terminal.

## Parte A — orquestração de terminais/painéis por projeto

| Ferramenta | O que faz | Gap p/ nossa ideia |
|---|---|---|
| **Claude Code Desktop (redesign abr/2026)** | workspace com N sessões paralelas, painéis drag-and-drop, terminal integrado, editor de arquivos, worktree git por sessão | **sem VSCode**; editor próprio minimalista; 1 terminal integrado por sessão, não N shells arbitrários; janela única |
| **Wave Terminal** | workspace em blocos, layout persistido (ex: 3 SSH + logs + AI chat), preview inline de arquivos, AI por bloco | não é editor de código; sem noção de "sessão de agente"; sem dispatch de spec |
| **Zellij / tmux** | layouts declarativos, panes/tabs, session resurrection, plugins | headless, sem GUI unificada, sem VSCode, sem spec-click |
| **Tabby** | emulador com tabs/split panes, plugins, base web | terminal puro |
| **vscode-terminal-workspaces / CodeMux (vscode-mux)** | extensão VSCode: gerencia sessões de terminal via sidebar; tmux/zellij como terminal padrão do VSCode | resolve "terminais dentro do VSCode", não multi-projeto nem spec-click |

### Maestri — o mais próximo da ideia (achado depois)

App nativo macOS, Swift puro + Metal, **sem Electron e sem webview**. Canvas
infinito com nós arrastáveis: terminais, notas markdown, sketches à mão. As
linhas entre nós são pipes PTY reais — stdout de um agente vira stdin de outro.
Workspaces em JSON local, política "zero cloud". Agnóstico de agente (Claude
Code, Codex, OpenCode).

**O buraco:** não tem editor nenhum, e **não embute app nenhum** — todos os nós
são views que ele mesmo desenha. "Canvas de apps" não existe nem lá.

## Parte B — orquestradores de agentes paralelos

- **Conductor** (conductor.build): app Mac, agentes paralelos em worktrees isolados, integra Linear. Fechado, mac-only.
- **Crystal** (Stravu): Electron MIT, sessões paralelas Claude Code/Codex por worktree. **Deprecado fev/2026** → sucessor pago fechado **Nimbalyst**.
- **Vibe Kanban**: board kanban, card = task atribuída a agente (agnóstico: Claude Code, Codex, Gemini). bloop fechou abr/2026, projeto seguiu Apache 2.0 comunitário/local.
- **Claude Squad**: opção mais enxuta, terminal.
- **Munder Difflin**: "hive" com memória compartilhada + orquestrador.

Padrão comum: **1 sessão = 1 git worktree**. Ninguém trata "tab = perfil de projeto com N terminais nomeados + VSCode".

## Parte C — spec markdown → ação no agente

- **md-redline** — o mais próximo do que você descreveu. Renderiza o markdown, você **seleciona texto e comenta inline**; o comentário vira marcador HTML invisível *dentro do próprio .md* (sem DB, sem sidecar). Traz **MCP server** com 4 tools: `mdr_request_review`, `mdr_review`, `mdr_ask`, `mdr_wait`. Funciona com Claude Code, Claude Desktop, Codex CLI, Gemini CLI.
  - Gap: é feedback de *review* (agente lê o arquivo e resolve), não "clique nesta linha → manda ESTA ordem para a sessão X do painel Y".
- **TASKS.md** (tasksmd): spec de fila de tarefas em checkbox markdown, IDs kebab-case, campo "Blocked by", pensado p/ múltiplos agentes reivindicarem linhas distintas. Companion do AGENTS.md.

## Conclusão da pesquisa

Nenhuma ferramenta cobre a **união**: gerenciador de workspaces (N terminais nomeados + editor real por projeto) **+** roteador de spec markdown que dispara prompt na sessão específica. As peças existem separadas. O diferencial do Egeon Deck é a **cola**: mapa `linha de spec → sessão/pane alvo`.

## Restrição técnica dura: VSCode não embute

VSCode real é Electron; **não dá para embutir dentro de outro app**. Caminhos possíveis:

1. **code-server / openvscode-server em `<webview>`** — funciona, mas iframe quebra partes do client web (abrir pasta depende da URL da location bar). Extensões que dependem de UI nativa sofrem. Existe precedente (`Code-Server-Electron-App`).
2. **Lançar VSCode real como janela externa** e só orquestrar/focar/tilar via API de Acessibilidade do macOS (estilo yabai). Frágil, mas usa o VSCode de verdade.
3. **Inverter o host**: o Egeon Deck vira **extensão do VSCode**. Terminais já viram grid com `terminalLocation: "editor"`. Mais barato, mas amarra ao VSCode.
4. **Editor próprio** (Monaco/CodeMirror) — perde extensões, debugger, Copilot etc.

## Fontes

- [Claude Code Desktop Redesign guide (miraflow)](https://miraflow.ai/blog/claude-code-desktop-redesign-parallel-sessions-routines-workspace-guide)
- [Claude Code Desktop Redesign: Parallel Agents (eigent)](https://www.eigent.ai/blog/claude-code-desktop-redesign)
- [Best tools to run multiple Claude Code agents (2026)](https://munderdiffl.in/blog/best-claude-code-multi-agent-tools/)
- [Vibe Kanban alternatives (2026)](https://aq.dev/alternatives/vibe-kanban/)
- [md-redline](https://github.com/dejuknow/md-redline)
- [TASKS.md](https://github.com/tasksmd/tasks.md)
- [vscode-terminal-workspaces](https://github.com/cybersader/vscode-terminal-workspaces)
- [vscode-mux / CodeMux](https://github.com/jellydn/vscode-mux)
- [Zellij features](https://zellij.dev/features/)
- [Wave Terminal review (2026)](https://moltamp.com/blog/wave-terminal-review-2026/)
- [code-server embed in iframe (issue #621)](https://github.com/coder/code-server/issues/621)
