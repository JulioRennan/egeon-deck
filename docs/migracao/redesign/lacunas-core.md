# Lacunas do core — porte pendente × novo da v3

> Levantamento (só leitura), 2026-11-19. Fonte da lista: `progresso.md`.
> Régua: o Swift de `legado/app/Sources/EgeonDeck` (o porte é fiel; o que o
> Swift não faz é **evolução**, e evolução passa pelo Julio —
> `3-proposta.html`). "Onde entraria" aponta para o Rust de
> `rust/crates/egeon-core/src`.

**(a)** o Swift já faz → porte pendente (código, sem decisão nova).
**(b)** novo da v3 → proposta para o Julio.
**(UI)** não é lacuna do core: o dado existe ou a regra é de tela.

## Resumo

| Classe | Itens |
|---|---|
| **(a) porte pendente** | subtítulo do card da fila ("N pendentes") — feito |
| **(b) novo da v3 — dado já existe no core** | "parada há X" / paradas recolhíveis · flag `maestro` no participante · modelo por resposta na meta da mensagem |
| **(b) novo da v3 — dado novo** | stack do projeto · log por turno, "N turnos", branch no painel, "Abrir Consumo e custo" · envios usados por aresta (N/M) · cor por componente salvo · descrição dos modelos · auto mode · "Recarregar"/selo do shell · CPU e memória por processo · anexar arquivo no chat · Encerrar terminais |
| **(UI)** | cor por agente · modelo/esforço do destinatário · "Parado" no chip · Abrir no Finder · Recolher tudo · cores da bancada (24 × 12) |

## Tabela

| # | Lacuna (progresso.md) | O que o Swift faz | Classe | Onde entraria no Rust | Nota |
|---|---|---|---|---|---|
| 1 | **Subtítulo do card da fila** — **FEITO** (autorizado) | `QueueNode.swift:143-144`: o cabeçalho do card mostra "nada pendente" / "N pendente(s)". Texto também em `ChatQueue.swift:32-34` | **(a)** | O texto já existe (`pending_summary`, `runtime/actor/queue_commands.rs:270`, só no detalhe `node/…/fila`). Falta levá-lo ao retrato dos nós do canvas: campo `subtitle` em `NodeView` (`protocol/org.rs`, preenchido para `NodeKind::Queue` a partir de `actor.queue` em `Actor::nodes_state`, `runtime/actor.rs`). A UI só mostra (`CanvasCard.subtitle`), sem segundo cubit | **Corrige o que eu havia classificado como "evolução"**: o Swift mostra "N pendentes" no card; o que é evolução é o formato "para revisor · 2 de 4" (v3). Recomendo fazer o (a) já e deixar o formato da v3 como proposta |
| 2 | Subtítulo da fila no formato da v3 ("para revisor · 2 de 4") | Não existe (só "N pendentes") | **(b)** — decisão 50 de `3-proposta.html` | O mesmo campo do item 1, com outro texto (`pending_summary` em `features/queue/`) | Muda o texto do Swift: só com OK do Julio |
| 3 | **"Parada há X"** (decisão 47) (idade da última atividade por bancada) e "N paradas há mais de X" recolhíveis na árvore; filtro "Recolher paradas há mais de…" | `ActiveWorkbenches.swift:9-35`: só a janela de 24 h da aba Ativas (recentes × paradas). Não há texto "há X" nem recolher na árvore | **(b)**, com dado já no core | `features/workbench/clock.rs:82-86` já guarda `last_active` (porte do `WorkbenchClock.lastActive`, `WorkbenchClock.swift:11-24`). Expor no retrato da bancada: `last_active` em `WorkbenchView` (`protocol/org.rs:85`, preenchido em `runtime/org.rs workspaces_state`). A UI formata o "há X" e agrupa | Expor o dado é barato; o agrupamento/recolher é desenho novo |
| 4 | **Stack do projeto** (selos Rs/TS/Cs…) | Nada (`Sidebar.swift` só tem o ícone de pasta/projeto múltiplo) | **(b)** | Detector por arquivos do repo em `features/workspace/` (campo `stack` em `ProjectView`, `protocol/org.rs`) | Cores e siglas já estão no HTML da v3; a UI tem o lugar (`SidebarProject.stacks`) |
| 5 | **Log por turno** (hora, agente, o que fez, modelo, tokens, custo, "precisa de você") | `UsageLedger.swift:9-18`: só acumulado por nó e tarifa (`byNode`) + cursores; não guarda turno | **(b)** | Livro novo em `features/usage/` (uma entrada por turno, lida do transcript) e rota/tópico novo — formato de socket é decisão (`3-proposta.html`) | Sem ele não há visão Log, "Clique para filtrar o log", escopo/Limpar |
| 6 | **"N turnos"** no painel | Não existe (o ledger não conta turno) | **(b)** | Mesmo livro do item 5 (contagem) | Sai quase de graça junto do log |
| 7 | **Branch no topo do painel de consumo** | `UsagePanel.swift` não mostra branch (a worktree/branch só aparece em `NodeView.swift:88,174`, botão de worktree) | **(b)** | Campo `branch` no retrato do consumo (`features/usage/`), lido do git da bancada (`features/worktree/git.rs`) | Pequeno |
| 8 | **"Abrir Consumo e custo"** (link do rodapé) | Não existe tela de consumo própria no Swift (o painel é um popover; não há destino) | **(b)** | Depende de definir a tela — produto, não core | Sem destino, o link não entra |
| 9 | **"Parado"** (segundo tempo do chip) | `WorkbenchClock.swift:11-16`: fases `running`, `waiting`, `failed` | **(UI)** | Dado existe: `waiting` (mão, "esperando você") e `failed` | "Parado" é o nome da v3 para a fase `waiting`; é nomenclatura/decisão de rótulo, não dado |
| 10 | **Envios usados por aresta** ("N/M", estados running/gasto) | `Dispatcher.swift:1165-1170,1208`: a contagem existe **por cadeia**, em tempo de envio; `Edge.swift:589` (`drawLimitPill`) mostra só o limite. Nada persistido por aresta | **(b)** | Contador por aresta no `dispatch` (`features/dispatch/`, hoje `send_count` por cadeia) e campo no retrato das ligações (`LinkView`, `protocol/org.rs`) | É estado novo (o que "usado" significa fora de uma cadeia é decisão) |
| 11 | **Cor por componente salvo** | `NodeTemplate.swift` não tem cor | **(b)** | Campo `color` no template (`features/node/`, formato do `~/.egeon` — compatibilidade a decidir) | Hoje a UI usa a cor do agente pelo nome |
| 12 | **Descrição curta dos modelos** ("mais capaz", "equilibrado") | Não achei (só `description` de comandos/skills em `ClaudeCommandRegistry.swift:107`) | **(b)** | `features/agent/` — catálogo de modelos (`ModelCatalog`) ganharia a frase; o texto vem do CLI ou de uma tabela nossa | A v3 usa "o da bancada / mais capaz / equilibrado / rápido" |
| 13 | **Auto mode** (aprovar ações sozinho, shift+tab) | Não existe no Swift | **(b)** | Precisaria de estado do CLI (ainda desconhecido) e rota de comando | A pastilha saiu da UI; o "Automático" do esforço continua no menu |
| 14 | **"Recarregar" do shell e selo rodando/exit/ocioso** | O nó web tem recarregar (`WebNode.swift:87`); shell não tem selo | **(b)** | `features/terminal/` (estado do processo no retrato do nó) | Só o shell; o web já é do porte |
| 15 | **Cor por agente** | `ChatParticipant.swift:16,42-61`: cor por hash do id (`AgentPalette.color(for:)`) | **(UI)** | — | A UI deriva do id como o Swift (`agentIdentity`); a v3 troca a paleta, não o dado |
| 16 | **Flag `maestro` no participante do chat** | O chat não distingue o maestro (só a cor por hash) | **(b)**, com dado já no core | `NodeConfig.maestro` existe (`features/node`); expor em `ChatParticipantInfo` (`features/chat/runtime.rs`) | Para o maestro ficar `sand` também no chat/composer |
| 17 | **Modelo da resposta na meta da mensagem** | `ChatBlockLayout.swift:31-34`: a meta é hora + custo | **(b)**, com dado já no core | O transcript (`features/agent/claude/transcript.rs`) já lê modelo por turno; entra no bloco `header` do chat (`features/chat/`) | A v3 mostra "Opus 5.5 · 23:08 · US$ 1,12" |
| 18 | **Modelo/esforço do destinatário ao lado do enviar** | — | **(UI)** | — | Resolvido na UI pelo estado do agente (`AgentStatus`) |
| 19 | **Anexar arquivo no chat** (+ do composer) | Não existe no chat do Swift | **(b)** | Rota nova de chat (`features/chat/`) | O "+" saiu até existir |
| 20 | **CPU e memória por processo** | `ProcessScanner.swift`/`ProcessTable.swift`: pid, nó, órfão, idade, comando (nenhuma métrica) | **(b)** | Coleta no driver de processos (`egeon-driver/procs/`) e campo em `ProcessRow` (`features/processes/`) | Driver, por ser API do sistema |
| 21 | **Encerrar terminais** (menu da bancada) | Não existe (`Sidebar.swift:415-435`: Renomear, Duplicar em worktree, Regras, Cor, Limpar, Remover) | **(b)** | Comando novo em `features/node/` (matar os pty da bancada sem removê-la) | "Limpar a bancada…" é o mais próximo |
| 22 | **Abrir no Finder / Renomear projeto / Recolher tudo** (menus) | Não existem (`Sidebar.swift:752-782`); Finder só via ⌘-clique no subtítulo do card | **(UI)** / **(b)** | Abrir no Finder e Recolher tudo: só UI (o recolher já é estado no core, `cubit.toggle…`). Renomear projeto: rota nova em `features/workspace/` | Só Renomear projeto precisa do core |
| 23 | **Cores da bancada: 24 nomes × 12 identidades** | `WorkbenchColor.swift:11-30`: 24 cores Material 400, 7 automáticas | **(b)** | O mapeamento (hoje na UI) viraria migração do formato em `features/workbench/` | Decisão pendente com o Julio (`progresso.md`) |

## O que fazer já

1. **Item 1 é porte (a):** o card da fila no Swift mostra "N pendentes" e o Rust
   já tem o texto — falta só entregá-lo no retrato dos nós. Posso fazer no
   core (`NodeView.subtitle`, fmt/clippy/test) e a UI só mostra, sem segundo
   cubit.
2. **Dados que o core já tem e só faltam no fio** (3, 16, 17): expor é barato,
   mas mudam o formato do socket — passam pelo Julio com os demais.
3. O resto é (b): entra em `3-proposta.html` como evolução, uma linha por item.
