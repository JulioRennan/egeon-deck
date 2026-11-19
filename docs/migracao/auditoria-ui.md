# Auditoria da UI: Flutter (`ui/lib`) × Swift (`legado/app/Sources/EgeonDeck`) — 2ª rodada

Data: 2026-11-18 · branch `migracao-flutter`, árvore de trabalho **sem commit** (depois de ui-di, ui-bench, ui-chat) · só leitura de código, nada rodado.
1ª rodada: commit `502586a`. Cada linha traz agora **status** (ok / metade / falta / diferente / regrediu; "era …" diz como estava na 1ª rodada).

Abreviações: **`L/`** = `legado/app/Sources/EgeonDeck/` · **`U/`** = `ui/lib/` · **`R/`** = `rust/crates/egeon-core/src/`.
Gravidade: **bloqueia uso** · **incomoda** · **detalhe** · **ok**. ✔ = reconferido à mão depois da varredura. A árvore mudou durante a leitura; linhas podem andar.

## O que ainda impede o uso

Nenhum dos 7 bloqueios da 1ª rodada segue aberto: remover bancada, criar em worktree (4 caminhos), multi-worktree, templates, formulário/edição de nó, shell no chat e ⌘V de print na fila estão ligados da tela ao core (✔ removal_plan, app_forms, bench_forms, node_form, chat_commands).

O que mais pesa agora (incomoda, perto de bloquear):

| # | lacuna | onde | só UI? |
|---|---|---|---|
| 1 | ✔ **`/` do chat sempre vazio**: o core não carrega o catálogo do CLI (`ChatHost::slash` devolve `None`) | R/runtime/actor/chat_commands.rs:124-127 | não (core) |
| 2 | **Atalhos dependem de foco na casca** (não executado): `CallbackShortcuts` sem nenhum `autofocus`/`requestFocus` em home/canvas; com página web focada ou sem foco, ⌘W/⌘1…9/⇧⌘T/⌥⌘P/⌘= provavelmente não chegam. No Swift são key equivalents do menu | U/features/home/presentation/page/home_shell_page.dart:204 · ui/macos/Runner/Web/ | sim — conferir rodando |
| 3 | **Abrir/fechar o painel da fila no chat apaga o texto do compositor e rouba o foco** | U/features/chat/presentation/page/chat_page.dart:211-233 · chat_composer.dart:174 | sim |
| 4 | **Clicar no vazio de uma tarefa aberta a fecha** enquanto se escreve | U/features/node/queue/presentation/widgets/queue_body.dart:149-152 | sim |
| 5 | **"Configurar novo terminal…" cria o nó no layout padrão** (coluna da largura da janela, pode sobrepor/cair fora da vista); Swift usa `spawnRect` | workbench_canvas.dart:120 → `create_node` sem frame → R/features/workbench/frames.rs:24-54 | UI (mandar o frame) |
| 6 | ✔ **"Remover bancada…" fica segundos mudo**: o core roda `git status` em toda worktree antes do 1º diálogo, sem cortina | R/runtime/actor/node_commands.rs:782-803 | core + UI |
| 7 | **Janela Processos é modal** e trava o app | U/features/processes/presentation/widgets/processes_panel.dart:17-29 | sim |
| 8 | **Nó web só interativo a 100% de zoom** | U/features/canvas/presentation/widgets/canvas_surface.dart:54,456-461 | sim |
| 9 | ✔ Faixa laranja (ciclo, cópia de worktree) **cobre o cronômetro** (top 64 × 110 no Swift) | home_shell_page.dart:191 | sim |
| 10 | + da configuração no formulário de nó **não mostra pastas ocultas** (`~/.claude-*`) | U/core/adapters/path_picker.dart:25-37 | sim |

## Canvas

Paridade confirmada no que **não** existe em nenhum dos dois: menu de contexto do fundo
e da aresta, duplo-clique no canvas, teclas Delete/Esc/setas/espaço no canvas, soltar
arquivo no fundo. Nenhum TODO nem handler vazio no canvas.

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ✔ Botão "Salvar este canvas como um template novo" | **ok** (era falta) | L/Features/Canvas/Views/CanvasToolbar.swift:45-47,97 · L/main.swift:2357-2405 | U/features/canvas/presentation/widgets/canvas_toolbar.dart:121-132 → U/features/home/presentation/widgets/workbench_canvas.dart:144-145 → U/features/home/presentation/forms/app_forms.dart:69-70,358-403 | `save_template` (`dry_run` dá o plano; R/runtime/actor/bench_forms.rs:59-115) | ok | Canvas vazio, nome sugerido, "Já existe…/Substituir" como no Swift |
| Botão "Atualizar o template de origem" | **ok** (era falta) | CanvasToolbar.swift:48-50,100-105,218-224 · main.swift:2415-2451 | canvas_toolbar.dart:133-141 → workbench_canvas.dart:146-149 → app_forms.dart:71-72,406-442 | `save_template` sem `name` | ok | Só com `bench.template` (U/features/home/domain/entities/shell_snapshot.dart:44-51) |
| Botão "Nova bancada numa worktree desta" | **ok** (era falta na barra) | CanvasToolbar.swift:51-53,107 · main.swift:2983-2986 | canvas_toolbar.dart:142-147 → workbench_canvas.dart:150-151 → app_forms.dart:63-68,154-200 | `worktree_info` + `worktree` | ok | |
| Barra informativa (cronômetro + custo) sob a barra de ações (ADR-085) | metade | L/Features/Canvas/Views/CanvasInfoBar.swift:5-47 · CanvasContainer.swift:74-77,493-502 | `ClockChip` montado: workbench_canvas.dart:109-119 → U/features/canvas/presentation/widgets/canvas_surface.dart:359-365 | `clock` da organização | detalhe | Custo segue no topo (U/features/home/presentation/page/home_shell_page.dart:171); sem fundo de vidro nem dica "…clique para zerar" (L/Features/Workbench/Views/ClockChip.swift:40) |
| Zerar o cronômetro | **ok** (era falta) | main.swift:2954-2957 · ClockChip.swift:57-66 | U/features/workbench/presentation/widgets/clock_chip.dart:23-31 → workbench_canvas.dart:113-116 → U/features/workbench/domain/usecase/reset_clock.dart | `reset_clock` (R/runtime/actor/node_commands.rs:95-103) | ok | Menu abre no ponto do clique (Swift: sob a pastilha) |
| Atalhos ⌘= / ⌘- / ⌘0 | **ok** (era falta) | main.swift:4317-4319,4078-4080 | U/features/home/presentation/widgets/shell_shortcuts.dart:121-126 (ligados em home_shell_page.dart:216-218) | n/a | detalhe | Itens do menu seguem sem `shortcut:` (U/features/home/presentation/widgets/app_menu.dart:241-257): o menu não mostra a tecla |
| Atalhos das ferramentas ⌘1/⌘2/⌘3 | falta | main.swift:4313-4315 | app_menu.dart:224-238 sem atalho; ⌘1…9 trocam de aba (shell_shortcuts.dart:114-115) | n/a | detalhe | No Swift ⌘1…9 já colidem com "Aba n" (main.swift:4246-4251) — defeito do Swift, anotar |
| Itens do canvas desligados com foco dentro de nó | metade (piorou) | main.swift:4130-4146 | app_menu.dart:99-101,234-257 (só no chat) | n/a | detalhe | ⌘=/⌘-/⌘0 são da casca inteira e o terminal ignora ⌘ (U/features/node/terminal/presentation/widgets/terminal_view.dart:158-171): com terminal em foco o canvas dá zoom; no nó web, deveriam ser da página |
| ⌘ + dois dedos no trackpad = zoom no cursor | **ok** (era diferente) | CanvasContainer.swift:282-288,467-485 | canvas_surface.dart:296-306; fundo (398-402) e terminal (terminal_view.dart:373-379) não rolam com ⌘ | n/a | ok | |
| Zoom/pan mantidos ao trocar aba ou canvas↔chat | **ok** (era diferente) | main.swift:2870-2875 | U/features/canvas/presentation/cubit/canvas_memory.dart:8-21 (único, U/features/canvas/di/canvas_injection.dart:33); restaura em canvas_cubit.dart:36-44, guarda em :534; ferramenta em canvas_tool_cubit.dart:25,118-125 | n/a | ok | Memória nunca esquece bancada removida (vazamento pequeno) |
| Botão direito no botão Terminal abre os componentes | **ok** (era falta) | L/Core/Views/ToolbarButton.swift:73-76 | canvas_toolbar.dart:255-261 | `components` | detalhe | Segurar 500 ms × 0,35 s; menu abre no ponteiro × sob o botão (CanvasToolbar.swift:206-208) |
| Tooltips da barra | **ok** (era falta) | CanvasToolbar.swift:43-57,90 · CanvasTool.swift:23-30 | canvas_toolbar.dart:79,95,103,112,130,138,145,193 (`AppTooltip`) | n/a | ok | ClockChip ainda sem dica |
| Aviso "Ciclo: a → b → c → a" (3+ nós) | **ok** (era falta) | L/Features/Canvas/Controllers/EdgeController.swift:58-66 · L/Features/Home/Views/WorkbenchShell.swift:364 | shell_snapshot.dart:53 → `ShellBanner` (home_shell_page.dart:190-191) | `link` calcula (R/runtime/actor/node_commands.rs:469-510) → `set_banner` 6 s (R/runtime/actor/org_commands.rs:439-452) | ok | Faixa laranja da casca, como no Swift. Posição: ver "Novos" |
| Clicar no fundo tira o foco do terminal | falta | CanvasContainer.swift:303 | canvas_surface.dart:382-389 (fundo só pana) | n/a | detalhe | Pesa mais agora: a borda de foco na cor da bancada não sai |
| Botão do meio sobre terminal: canvas pana e terminal não recebe | diferente | CanvasContainer.swift:307-311 | terminal_view.dart:221-224,259-266 | n/a | detalhe | Sem mudança |
| Reenquadrar depois do `arrange` do maestro | falta | CanvasContainer.swift:719-728 · main.swift:3091-3097 | canvas_cubit.dart:140-180 | n/a | detalhe | Sem mudança |
| Overlay de criação só com botão esquerdo | falta | CanvasContainer.swift:285-311,919-945 | U/features/canvas/presentation/widgets/tool_overlay.dart:27-39 | `create_node` | detalhe | Com ferramenta armada, ⌥+arrasto ou botão do meio pana **e** cria o nó ao soltar |
| Cor da ferramenta selecionada | diferente | ToolbarButton.swift:80-82 (accent) | canvas_toolbar.dart:266-277 (branco) | n/a | detalhe | |
| Ferramenta Terminal sem componente abre o formulário antes de criar | **ok** (era já sabido) | main.swift:3486-3517 | canvas_tool_cubit.dart:104-108 → canvas_surface.dart:150-152 → workbench_canvas.dart:121-122 (`showNodeForm` com o retângulo) → U/features/node/agent/domain/repository/socket_node_form_repository.dart:65-83 | `create_node` com `form` + `frame` (R/runtime/actor/node_commands.rs:187-200) | ok | |
| Fundo, grid 40, brilho (ADR-086); zoom 25–300%, detente, −/+, % → 100%, enquadrar; ⌘+roda, pinça, pan, ⌥+arrastar, botão do meio, espaço cresce; ferramentas e criação; arrastar/redimensionar nó; porta "+", arestas, direção, limite, X; menu Canvas; foco avisado ao core | ok | CanvasContainer.swift · CanvasGlow.swift · CanvasToolbar.swift · Edge.swift · EdgeController.swift · NodeView.swift:11-52,565-620 · main.swift:4300-4319 | canvas_surface.dart:268-482; canvas_toolbar.dart:92-216; canvas_cubit.dart:220-512; canvas_tool_cubit.dart:73-116; card_frame.dart:192,248; edge_controls.dart; workbench_canvas.dart:237-259; app_menu.dart:205-260 | `create_node`, `move_node`, `link`, `set_edge`, `unlink`, `ui_focus` | ok | Pinça com detente; ⌥ e ⌘+roda também agem sobre a barra (Swift exclui, CanvasContainer.swift:327-332) |

### Canvas — novos nesta rodada

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ✔ A faixa laranja cobre a barra informativa (cronômetro) | **regrediu** | WorkbenchShell.swift:324-327 (no canvas, `topInset + 110`) | home_shell_page.dart:191 (`top: 64`) × faixa informativa em canvas_surface.dart:359-365 (top 62) | n/a | incomoda | Aviso de ciclo e cópia de worktree tapam o cronômetro; deveria ficar perto de 110 |
| "Configurar novo terminal…" nasce fora da vista | diferente | main.swift:3555-3574 · CanvasContainer.swift:883-894 (`spawnRect`: canto visível +40, diagonal) | workbench_canvas.dart:120 → `showNodeForm` sem frame → `create_node` sem `frame` | core usa a coluna do layout padrão (node_commands.rs:192-200) | incomoda | Com canvas rolado ou com zoom, o nó cai fora da tela |
| Componente que sumiu entre abrir o menu e clicar | diferente | main.swift:3491-3497 (cai no formulário) | canvas_tool_cubit.dart:110-115 (erro do core engolido) | `create_node` | detalhe | Clique sem efeito e sem aviso |
| Dicas das ferramentas prometem ⌘V/⌘T/⌘W | defeito do Swift copiado | CanvasTool.swift:25-27 | U/features/canvas/domain/entities/canvas_tool.dart:15-17 | n/a | detalhe | No Flutter ⌘W fecha a aba e ⌘V cola — anotar |
## Nós

O caminho do formulário de nó está ligado de ponta a ponta: lápis, menu do botão direito,
ferramenta Terminal e "Configurar novo terminal…" → `showNodeForm` → `NodeFormCubit` →
`SocketNodeFormRepository` → `node_form`, `node_form_screen`, `node_folder`,
`create_node{form}`, `apply_node`, `components` → R/runtime/actor/node_commands.rs:128-134 →
R/runtime/actor/node_form.rs (regras em R/features/node/form.rs). Formatos do fio batem
entre Dart e Rust. Nenhum TODO nem handler vazio.

### Moldura e cabeçalho do card

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ✔ Lápis "Configurar este nó" | **ok** (era falta) | L/Features/Nodes/Views/NodeView.swift:83-84,263-266 | U/features/node/card/presentation/widgets/card_frame.dart:300-305 → U/features/canvas/presentation/widgets/canvas_surface.dart:547-552 → U/features/home/presentation/widgets/workbench_canvas.dart:123-124 | `node_form` / `apply_node` (R/runtime/actor/node_form.rs:211,366) | ok | Só shell e agente, como no Swift; renomear vem pelo NOME |
| Menu do botão direito: "Configurar \<id\>…" | **ok** (era falta) | NodeView.swift:289-300 | card_frame.dart:207-228 (botão direito 239-241) | idem | ok | Web e fila sem menu, como no Swift |
| Menu do botão direito: "Nova worktree para este terminal…" | **ok** (era falta) | NodeView.swift:301-304 · L/main.swift:3763-3795 | card_frame.dart:219-220 → workbench_canvas.dart:129-130,161-199 → U/features/workbench/presentation/widgets/node_worktree_form.dart | `worktree_info` / `worktree` com `node` (R/runtime/actor/bench_forms.rs:185-195; node_commands.rs:1470-1472) | ok | |
| Menu do botão direito: "Remover \<id\>…" | **ok** (era falta) | NodeView.swift:305-308 | card_frame.dart:221-222 | `remove_node` | ok | |
| Botão de worktree no cabeçalho do terminal | **ok** (era falta) | NodeView.swift:88-90,267-270 | card_frame.dart:292-298 | idem | ok | |
| X do nó + confirmação por tipo | ok | NodeView.swift:80 · main.swift:3425-3449 | card_frame.dart:306-311; workbench_canvas.dart:262-288 | `remove_node` | detalhe | Tooltip e título (id) corrigidos; aviso do web ainda sem o nome do perfil (WebNode.swift:144-147) |
| Título com glifo (✦ ▸ ◍ ☰) e "· maestro" | falta | L/Features/Nodes/Views/TerminalNode.swift:231-234,432 · WebNode.swift:99 · QueueNode.swift:40 | U/features/canvas/domain/entities/canvas_card.dart:78 (`title: id`) | n/a | detalhe | Sem mudança |
| Tooltip do título (endereço · CLI) | **ok** (era falta) | TerminalNode.swift:243 · WebNode.swift:105 | canvas_card.dart:48-51; card_frame.dart:337-341,370-377 | n/a | ok | |
| Subtítulo do web "perfil: X" / da fila "N pendentes" | falta | WebNode.swift:104 · QueueNode.swift:144 | canvas_card.dart:81-83 | n/a | detalhe | Sem mudança |
| ⌘-clique no subtítulo abre a pasta no Finder | **ok** (era falta) | NodeView.swift:98-150,581-586 | U/features/node/card/presentation/widgets/subtitle_link.dart:52-104; card_frame.dart:361; canvas_surface.dart:516-522; workbench_canvas.dart:131-136 | `open_node_folder` (node_commands.rs:94,513-526) | ok | Sublinhado, mão e tooltip como no Swift |
| Status de retry: "Tentar agora" / "Cancelar tentativa" | **ok** (era falta) | TerminalNode.swift:474-489 | U/features/node/card/presentation/widgets/card_status.dart:36-58; canvas_surface.dart:530-538; workbench_canvas.dart:137-142 | `retry` (node_commands.rs:87-93) | ok | Menu abre no clique (Swift: sob o rótulo) |
| Borda de foco na cor da bancada (ADR-086) | **ok** (era falta) | NodeView.swift:337-377 | card_frame.dart:139-152 (`focusColor`, canvas_surface.dart:555) | n/a | ok | |
| Borda do maestro mais grossa (2 / 0,95) | metade | TerminalNode.swift:236-248 | card_frame.dart:147 (dourado; largura 1, opacidade 0,55) | n/a | detalhe | |
| Porta "+" escondida no maestro | falta | TerminalNode.swift:269 | segue `card.port`; core inclui o maestro (R/features/canvas/edges.rs:44-49) | n/a | detalhe | |
| Faixa do agente só existe se houver o que mostrar | falta | TerminalNode.swift:245-260 | workbench_canvas.dart:69-77; card_frame.dart:131-133 (reserva 46 px) | n/a | detalhe | |
| Status, anel de atenção, arrastar, resize | ok | TerminalNode.swift:423-455 · AttentionRing.swift · Spinner.swift | card_status.dart:60-95; U/commons/widgets/attention_ring.dart; spinner.dart | `move_node` | ok | Anel ignora "reduzir movimento" (AttentionRing.swift:162-163) — detalhe |

### Terminal

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ⌘ sobre link mostra a mão | metade | TerminalNode.swift:46-74 | U/features/node/terminal/presentation/widgets/terminal_view.dart:230-259 | `link_hover` | detalhe | Sem sublinhado; sem foco, ⌘ parado não acende |
| Seleção; ⌘C/⌘V/⌘A; ⌘-clique; arrastar arquivo; rolagem, IME, bell, OSC 52 | ok | SwiftTerm · TerminalNode.swift:106-176 · main.swift:4290-4292 | terminal_view.dart:148-490; U/features/node/terminal/presentation/page/terminal_page.dart:32-42 | `pointer`, `copy`, `paste`, `select_all`, `drop`, `scroll`, `input`, `clipboard_reply` | ok | ⌘ + dois dedos agora é zoom do canvas (373-377) |
| Busca, zoom de fonte, menu no corpo | ok | não existem | não existem | n/a | ok | Paridade |

### Faixa do agente

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ✔ Confirmação "Limpar a conversa de \"X\"?" | **ok** (era falta) | main.swift:3212-3223 | workbench_canvas.dart:74-75,206-220 | `node_clear` | ok | Mesmo texto e botão |
| Esforço por rolagem no trackpad | **ok** (era falta) | L/Features/Nodes/Features/AgentNode/Views/EffortDial.swift:129-141 | U/features/node/agent/presentation/widgets/effort_dial.dart:95-109,163-176 | `effort_move` | ok | |
| Menu de modelo: submenu "Versões anteriores", cabeçalho "sempre o mais recente" | metade | L/Features/Nodes/Features/AgentNode/Views/ModelRow.swift:188-195 | U/features/node/agent/presentation/widgets/agent_strip.dart:126-160 | n/a | detalhe | Lista plana com separadores |
| Tooltips (modelo, esforço, auto, ultracode, contexto, limpar) | **ok** (era falta) | ModelRow.swift:292 · EffortDial.swift:195-212 · ContextIndicator.swift:20,33 | agent_strip.dart:71,163,216,262; effort_dial.dart:145,193 | n/a | ok | |
| Modelo, esforço, ultracode, contexto, limpar | ok | ModelRow.swift:48-357 · EffortDial.swift:143-180 | agent_strip.dart; effort_dial.dart; context_indicator.dart | `set_node`, `effort_*`, `node_clear` | ok | |

### Nó web

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| Página interativa em qualquer zoom | falta | WebNode.swift · NodeView.swift:393-445 | canvas_surface.dart:54,456-461 (vivo só a 100%, salvo a flag de compilação `EGEON_WEB_LIVE_ZOOM`) | n/a | incomoda | Sem mudança |
| Barra de endereço, voltar/avançar/recarregar, URL gravada | ok | WebNode.swift:85-113,182-209 | U/features/node/web/presentation/widgets/web_body.dart:63-98; address_field.dart | `web_navigate`, `web_navigated` | ok | Voltar/Avançar/Recarregar sem tooltip (`_NavButton`) — detalhe |
| Menu de perfil (✓, "Novo perfil…") | ok | WebNode.swift:91,213-266 | web_body.dart:189-245 | `web_set_profile` | ok | Com tooltip |

### Formulário de nó (NodeTemplateDialog), campo a campo

F/ = U/features/node/agent/presentation/widgets/node_form.dart · C/ = U/features/node/agent/presentation/cubit/node_form_cubit.dart · N/ = L/Features/Nodes/Views/NodeTemplateDialog.swift

| campo / ação | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| Título "Novo terminal"/"Configurar \<id\>", Criar/Aplicar/Cancelar | ok | N/:175-185 · main.swift:3555-3566,3597-3607 | F/:181-198 | — | ok | |
| Enter no NOME confirma | falta | N/:176-185 (botão padrão do NSAlert) | F/:236-243 (sem `onSubmitted`) | — | detalhe | Esc cancela (app_dialog.dart:51-52) |
| Abas "Criar do zero" / "Começar de outro" | ok | N/:221-236 | F/:204-211 | — | ok | |
| Tipo Shell × Agente | ok | N/:60-61,244-247,500 | F/:229-234 | `finish` (R/features/node/form.rs:264-306) | ok | |
| NOME (vazio vira o CLI ou "sh") | ok | N/:62,189-192,249-250 | F/:236-243 | form.rs:266-270 | ok | |
| COMANDO (só shell; vazio abre o zsh) | ok | N/:63,252-254,205-211 | F/:259-268 | form.rs:295-302 | ok | |
| CLI (radios, ordem estável) | ok | N/:64-65,258-264,345-353 | F/:275-292 | `node_form` (node_form.rs:229-266) | ok | |
| Trocar de CLI guarda a tela (ADR-057) | ok | N/:487-498,634-652 | F/:122-133,286 → C/:54-63 | `node_form_screen` (form.rs:81-96,169-174) | ok | |
| MODELO (padrão, catálogo, apelidos, valor à mão) | ok | N/:354-360,578-602 | F/:298-313 | form.rs:103-145 | ok | Só com mais de um item |
| ESFORÇO | ok | N/:361-367,613-627 | F/:316-332 | form.rs:147-166 | ok | |
| Maestro — monta a bancada | ok | N/:90-91,286-290,372-375 | F/:339-344 | form.rs:288-292 | detalhe | Sem o tooltip longo (N/:287-290) |
| CONFIGURAÇÃO — \<ENV\> (popup; sugestão do workspace ao criar) | ok | N/:71,376-384,510-540 · main.swift:3540-3549 | F/:346-363 | form.rs:181-216; node_form.rs:131-141,333-363 | ok | Em "Começar de outro" ao criar, o core cai na sugestão do workspace; o Swift (N/:159) usa só a do componente — detalhe |
| + da configuração (painel de pasta) | metade | N/:72,547-560 (`showsHiddenFiles = true`) | F/:158-164 → C/:66-75; seletor em U/core/adapters/path_picker.dart:25-37 sem arquivos ocultos | `node_form_screen{config}` | incomoda | `~/.claude-*` não aparece sem ⌘⇧. no painel |
| PASTA relativa à raiz (raiz, subpastas, a atual) | ok | N/:76-82,392-396,664-698 | F/:367-401 | node_form.rs:236-246 | ok | |
| + da pasta | metade | N/:712-762 | F/:150-156 → C/:112-130 | `node_folder` (node_form.rs:294-302; form.rs:236-249) | detalhe | Abre sempre na raiz; Swift abre na pasta marcada (N/:736-743) |
| ✔ Normalizar a pasta ao confirmar (absoluto vira `~`) | metade | N/:201,781-786 | — | `normalized_folder` (form.rs:252) só usada em teste; `finish` não chama (form.rs:283-287) | detalhe | |
| PAPEL / REGRAS (só agente) | ok | N/:83-86,100-101,399-413 | F/:405-438 | form.rs:86-94 | ok | |
| Salvar como componente reutilizável | ok | N/:87-88,213,415-416 | F/:249-254 → C/:133-164 | `form_component` → `components::put` (node_form.rs:311-331) | ok | |
| "Começar de outro": cards, vazio, clique preenche e volta à aba 1 | ok | N/:153-173,421-473,843-921 | F/:443-590 → C/:78-109 | `components` | detalhe | Card sem tooltip "Papel: …" (N/:881) |
| Editar nó existente (captura, mantém estado, "mesmo processo", reinicia) | ok | main.swift:3597-3664 | workbench_canvas.dart:81-88,123-124 → C/:133-164 → socket_node_form_repository.dart:85-97 | `apply_node` (node_form.rs:366-405; form.rs:309-325; node_commands.rs:303-320) | ok | |
| Renomear (nome vira id novo e livre) | ok | main.swift:3615-3620 | idem | node_form.rs:380-385 | ok | Arestas com id antigo não são renomeadas, igual ao Swift |
| Ferramenta Terminal sem componente abre o formulário com o retângulo | ok | main.swift:3490-3517 | U/features/canvas/presentation/cubit/canvas_tool_cubit.dart:104-109 → canvas_surface.dart:150-152 → workbench_canvas.dart:121-122 | `create_node{frame,form}` | ok | |
| Menu de segurar do botão Terminal com componentes | ok | L/Features/Canvas/Views/CanvasToolbar.swift:70,188-214 | U/features/canvas/presentation/widgets/canvas_toolbar.dart:83-87,151-170,254-260; workbench_canvas.dart:91-95,108 | `components` + `create_node{component}` | ok | Abre no cursor, não sob o botão — detalhe |
| "Configurar novo terminal…" / Criar sem frame | metade | CanvasToolbar.swift:202-212 · main.swift:3555-3594 · L/Features/Canvas/Views/CanvasContainer.swift:883-894 (`spawnRect` 720×460 na área visível, em diagonal) | canvas_toolbar.dart:163-166 → workbench_canvas.dart:120 → socket_node_form_repository.dart:64-83 sem `frame` | `create_node{form}` sem frame → `apply_default_frames` (R/features/workbench/frames.rs:24-54) | incomoda | Nó nasce em coluna do layout padrão (largura da janela, altura dividida), pode cair sobre outro card ou fora da vista. Comentários do Flutter dizem "primeiro lugar livre", o que não é verdade |
## Barra lateral

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ✔ Menu do + (topo): "Nova bancada a partir de worktree…" | **ok** (era no-op) | L/Features/Home/Views/Sidebar.swift:1474 → L/main.swift:923-993 | U/features/sidebar/presentation/widgets/sidebar_panel.dart:96-99 → U/features/home/presentation/page/home_shell_page.dart:238 → U/features/home/presentation/forms/app_forms.dart:61-62,139-201 | `worktree_info`/`worktree_plan` sem bancada (R/runtime/actor/bench_forms.rs:119-230); `worktree` sem bancada (R/runtime/actor/node_commands.rs:1514-1552 → R/features/worktree/from_folder.rs) | ok | Seletor sem o título "Repositório de origem" (file_selector não permite) |
| Menu do projeto: "Nova bancada em worktree…" | **ok** (era no-op) | Sidebar.swift:776 | U/features/sidebar/presentation/widgets/group_row.dart:111-114 → app_forms.dart:141-142 | idem | ok | |
| + do projeto multi: direto para a worktree | **ok** (era no-op) | Sidebar.swift:750 | group_row.dart:299-303 | idem | ok | |
| + do projeto comum: menu de 2 itens | **ok** | Sidebar.swift:748-758 | group_row.dart:313-334 | `create_workbench` / `worktree` | ok | |
| Clique em projeto vazio | **ok** (era no-op) | Sidebar.swift:743 | group_row.dart:84-95 (comum abre o menu, multi vai à worktree) | — | ok | |
| Menu do + (topo): "Nova bancada…" (pasta livre) | metade | Sidebar.swift:1473 → main.swift:819-868 | sidebar_panel.dart:95 → app_forms.dart:104-129 | `create_workbench` | detalhe | Seletor sem título; pasta de links de multi: core recusa depois do formulário de nome (node_commands.rs:645-665) — a saída agora existe pelo + do projeto |
| Menu da bancada: "Remover bancada…" | **ok** (era quebrado) | Sidebar.swift:435 → main.swift:1652-1760 | U/features/sidebar/presentation/widgets/bench_row.dart:73 → app_forms.dart:283-354 | `plan_remove_workbench`, `remove_workbench` | ok | Ver Formulários e "Novos" (lentidão) |
| Menu da bancada: "Duplicar em nova worktree…" | **ok** (era metade) | Sidebar.swift:418 → main.swift:1103-1131 | bench_row.dart:58-61 → home_shell_page.dart:255 → app_forms.dart:63-68,154-201 | `worktree_info`, `worktree_plan`, `worktree` | ok | Multi vai ao formulário multi (app_forms.dart:178-181); fora do git avisa na hora (:164-166) |
| Menu da bancada: "Cor da bancada…" | diferente | Sidebar.swift:422-425,447-454 (popover) | bench_row.dart:63-69 → U/features/workbench/presentation/widgets/color_palette_dialog.dart:8 (diálogo centrado) | `set_workbench{color}` | detalhe | |
| Menu do projeto: "Nova bancada…" só se não for multi | metade | Sidebar.swift:772-775 | group_row.dart:110; `isMulti` em U/features/sidebar/domain/entities/sidebar_tree.dart:33 | `create_workbench` | detalhe | Multi sem membros resolvidos vira comum |
| "Remover workspace…" / "Tirar projeto do workspace…" | metade | main.swift:2288-2334 | app_forms.dart:484-528 | `remove_workspace`, `remove_project` | detalhe | Título "X ainda tem N bancada(s)" segue "Não foi possível" + texto do core |
| Arrastar bancada órfã para um projeto | **ok** (era falta) | Sidebar.swift:1076,1139 | U/features/sidebar/presentation/widgets/sidebar_tree_view.dart:418-420 | `move`, `plan_move` | ok | Sem teste da UI para esse arrasto |
| Custo da bancada na linha (ADR-085) | **ok** (era falta) | Sidebar.swift:15-17,158-165,215 | bench_row.dart:249 → U/features/usage/presentation/widgets/bench_cost.dart:12-42 (assina `workbench/<id>/usage`, com tooltip) | tópico de uso | ok | Some no modo recolhido, como no Swift |
| Aba Todas/Ativas lembrada entre aberturas | falta | Sidebar.swift:960-962,1312 | U/features/sidebar/presentation/cubit/sidebar_state.dart:12; sidebar_cubit.dart:28 | n/a | detalhe | |
| Aba Ativas: animação ao reordenar | falta | Sidebar.swift:1292-1304 | falta | n/a | detalhe | |
| Tooltips (+ topo, + projeto, caminho, cronômetro, recolher "⌘/") | falta | Sidebar.swift:99,124,231,573-575,909,977-979 | só o do custo em U/features/sidebar | n/a | detalhe | `AppTooltip` já existe; falta usar |
| Subtítulo de multi sem pasta "nenhuma pasta" | falta | Sidebar.swift:557-558 | group_row.dart:149-153 | — | detalhe | |
| Novo workspace/projeto, editar, gaveta, recolher, renomear, regras, limpar, clique abre aba; arrastar com guia; abas Todas/Ativas, seções, trilho, badges, cronômetro, selo, "Sem projeto" | ok | Sidebar.swift · SidebarTabs.swift | sidebar_panel.dart:93; group_row.dart:104-125; bench_row.dart:57-73; drawer_row.dart; sidebar_tree_view.dart; sidebar_segments.dart; sidebar_active_view.dart | `save_workspace`, `create_project`, `move`, `plan_move`, `set_*`, `clear_workbench`, `open_workbench` | ok | |

## Abas

Nenhum arquivo em U/features/tabs mudou: status e linhas da 1ª rodada valem.

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| Quando a faixa aparece | diferente | L/Features/Home/Views/WorkbenchTabsBar.swift:263 (some só com 0) | U/features/tabs/presentation/page/tabs_page.dart:19 (some com < 2) | — | detalhe | Com uma aba só não há faixa nem ✕ |
| ✕ fechar | metade | WorkbenchTabsBar.swift:121,147-154 | U/features/tabs/presentation/widgets/workbench_tab_pill.dart:137,185-209 | `close_workbench` | detalhe | Área de clique 10 pt sem as 6 de folga |
| Clique, arrastar, badges, largura; ⌘W, ⌘1…9, próxima/anterior | ok | WorkbenchTabsBar.swift:66-160,272-353 | workbench_tabs_bar.dart:73-189; workbench_tab_pill.dart:42-106; tabs_cubit.dart:43-64 | `activate_workbench`, `move_tab`, `close_workbench` | ok | |
| Menu de contexto da aba | ok | não existe | não existe | n/a | ok | Paridade |

## Formulários

O formulário de nó (NodeTemplateDialog) está na seção Nós, campo a campo.

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ✔ Remover bancada: plano de remoção | **ok** (era quebrado) | main.swift:1660-1662 | U/features/workbench/domain/entities/removal_plan.dart:61-71 (lê a lista); app_forms.dart:283-288 | `plan_remove_workbench` (R/runtime/actor/node_commands.rs:772-826) | ok | Fixtures corrigidas: R/protocol/org_fixtures.rs:971-985 e `fixtures/protocol/replies.json:306-340`; teste da UI lê a fixture real (ui/test/core/organization_socket_test.dart:346-348) |
| Remover: caixa "Também apagar a(s) worktree(s)" | **ok** (era metade) | main.swift:1694-1700 | app_forms.dart:295-318 | `remove_workbench{worktrees}` | ok | Conta só as sem `used_by` |
| Remover: lista "repo · branch · donos / MANTIDA…" | **ok** (era falta) | main.swift:1702-1723 | app_forms.dart:298-305; `optionHint` em U/commons/widgets/standard_dialogs.dart:155-245 | dado do plano | detalhe | Diálogo de 360 (Swift 420): linhas longas quebram |
| Remover: 2ª confirmação "Isto apaga trabalho não commitado" | **ok** (era falta) | main.swift:1744-1753,2045-2056 | app_forms.dart:337-348 | `losses` (só das apagáveis) | ok | |
| Remover: "Nenhuma pasta é tocada." / "…de outras bancadas e ficam." | **ok** (era falta) | main.swift:1724-1730 | app_forms.dart:320-324 | — | ok | |
| ✔ Worktree a partir de pasta/projeto (com template) | **ok** (era falta) | main.swift:923-993,1499-1510 | app_forms.dart:139-201; U/features/workbench/presentation/widgets/worktree_form.dart:38-66,244-253; template_pick_list.dart | bench_forms.rs:119-230; R/features/worktree/form.rs:97-112; from_folder.rs:103-158 | ok | O core aplica o `view` do template (from_folder.rs:144-147); o Swift não — desvio pequeno do core |
| MultiWorktreeForm + "Nenhuma worktree foi criada" / "Algumas ficaram de fora" | **ok** (era falta) | L/Features/Workspace/Views/MultiWorktreeForm.swift:8-111 · main.swift:1016-1029 | U/features/workbench/presentation/widgets/multi_worktree_form.dart:31-184; multi_worktree_form_state.dart:25-34; app_forms.dart:178-181,205-235 | `Worktree.repos` (R/protocol/org.rs:585-588); from_folder.rs:71-100; routes.rs:164-190; resposta `failed` (node_commands.rs:1581-1608) | ok | |
| Worktree (duplicar): linha por terminal / em branco | metade (era diferente) | main.swift:1450-1484 · L/Features/Workbench/Views/NodeWorktreeRow.swift:20-80 | worktree_form.dart:223-313; U/features/workbench/domain/entities/worktree_info.dart:68-106; worktree_form_state.dart:21-34 | vazio = desligado (R/features/worktree/node.rs:64-70) | detalhe | "Não levar", detalhe por linha e "pasta não existe" ok; falta o veredito por linha ("worktree própria · cria/abre…") e o laranja |
| Worktree (duplicar): título | **ok** (era diferente) | main.swift:1325 | app_forms.dart:185 (`info.repo`) | `repo` em form.rs | ok | |
| Workspace: aviso pós-salvar "Projeto com bancadas fica" / imagem | **ok** (era falta) | main.swift:2240-2255 | app_forms.dart:550-572; U/features/workspace/domain/entities/workspace_saved.dart:6-12; socket_workspace_repository.dart:64-85 | `save_workspace` (node_commands.rs:1231-1235) | ok | Sem fixture de resposta com `refused`/`warning` (ver Novos) |
| Workspace: mensagem do seletor | falta | WorkspaceForm.swift:180-197 | U/features/workspace/presentation/widgets/workspace_form.dart:80 | — | detalhe | |
| Novo projeto: recusa sem estilo de aviso | metade | NewProjectForm.swift:31-40 | app_forms.dart:575-615 | `create_project` | detalhe | |
| Paleta de cor: tooltip por cor | falta | WorkbenchColorView.swift:22-155 | color_palette_dialog.dart | n/a | detalhe | |
| Workspace, Multi-projeto, Novo projeto, Nova bancada, Renomear, Limpar, Regras, WorkspaceBadge, ClockText | ok | WorkspaceForm.swift · MultiProjectEditor.swift · NewProjectForm.swift · main.swift:1568-1631,3255-3402 | inalterados | `save_workspace`, `multi_name`, `create_project`, `templates`, `create_workbench`, `set_workbench*`, `clear_workbench` | ok | |

### Barra lateral, abas e formulários — novos nesta rodada

| item | status | Swift | Flutter / core | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ✔ "Remover bancada…" demora sem nenhum aviso | **regrediu** | main.swift:1734-1741 (perdas só depois da caixa marcada, com a cortina "Conferindo o que se perde…") | R/runtime/actor/node_commands.rs:782-803 roda `loss_lines` (git status/ls-files) em toda worktree antes de abrir o diálogo | — | incomoda | Com node_modules, o clique fica segundos sem nada na tela |
| Duplo clique em "Remover" abre dois diálogos | falta | main.swift:1655-1656 (`removalInFlight`) | app_forms.dart:283-288 sem trava | — | detalhe | Possível enquanto o plano é calculado |
| Erro de multi sem membros com título errado | metade | main.swift:1009-1013 ("\"X\" não junta pasta nenhuma") | app_forms.dart:164-166 ("Não consegui ler o repositório" / "…não é um repositório git"; motivo certo no corpo) | — | detalhe | |
| Comentário desatualizado no core | — | — | R/protocol/org.rs:559-560 diz "vazio é a branch da bancada"; no comportamento vazio é "não levar" (node.rs:64-70) | — | detalhe | |
| Fixtures sem as respostas novas | falta | — | sem reply de `save_workspace` com `refused`/`warning` nem de `worktree` multi com `failed`; `worktree_criada` (org_fixtures.rs:1143) só tem `{workbench}` | — | detalhe | O formato lido nesses casos não tem contrato testado — foi esse tipo de lacuna que quebrou a remoção na 1ª rodada |
## Chat

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| Clicar num shell mostra o terminal no lugar da thread | **ok** (era falta) | L/Features/Chat/Controllers/ChatContainer.swift:651-679 | U/features/chat/presentation/page/chat_page.dart:106-109,133-140 · U/features/chat/presentation/cubit/chat_composer_cubit.dart:69-85 (`TerminalBody` real) | `screen`; envio ao shell R/features/chat/routes.rs:221-243 | ok | Shell morto devolve a thread |
| Links da resposta abrem | **ok** (era metade) | ChatRowView.swift:99-104 | chat_page.dart:154 → chat_conversation_cubit.dart:89 → socket_chat_repository.dart:93; md_text.dart:32-42 | `open_url` (R/runtime/actor/app_commands.rs:78-85) | ok | `TapGestureRecognizer` nunca descartado (detalhe) |
| Recuperação de `rev` perdido | **ok** | — | socket_chat_repository.dart:37-46 | snapshot completo (R/features/chat/view.rs:291-295) | ok | |
| "Recusar" da pergunta | **ok** | PermissionTray.swift:156-159 | permission_tray.dart:147-151,174,193 | `permission_answer` deny | ok | |
| Vários pedidos empilhados | **ok** | PermissionTray.swift:30-45 | chat_page.dart:162-183 | lista (R/runtime/actor/dispatch_commands.rs:93-111) | ok | |
| Botões da bandeja desabilitam ao clicar | falta | PermissionTray.swift:174-183 | permission_tray.dart:113-143,202-250 | — | detalhe | Clique duplo manda duas respostas |
| Estado do participante na linha | **ok** | ParticipantsColumn.swift:327-350 | participants_column.dart:134-140,187-198 | `status`/`statusTone` (R/features/chat/thread.rs:116-147) | ok | |
| Tab/destinatário só entre vivos | **ok** | ChatContainer.swift:297-299,647-649 | chat_composer_cubit.dart:43-58,95-100 | n/a | ok | |
| Seta "ir ao fim" | **ok** | ChatContainer.swift:104-111 | chat_thread_view.dart:45-54,299-345 | n/a | ok | |
| Clicar na citação leva à mensagem, com destaque | **ok** | ChatContainer.swift:121-130 | chat_thread_view.dart:187-235 | n/a | ok | |
| Foco no compositor ao entrar / clicar participante | **ok** | ChatContainer.swift:220-223 | chat_composer.dart:173-174 | n/a | ok | Efeito colateral: ver Novos |
| ✔ Autocompletar /slash | metade | ChatContainer.swift:987-1029 | completion_menu.dart:40-89,199-206 (título, glifos, 620 px, segue a seleção) | **não**: `slash` devolve `None` (R/runtime/actor/chat_commands.rs:124-127) | incomoda | UI pronta; no app real o `/` volta vazio |
| ✔ Busca na lista de comandos (⌘F) | falta | ChatContainer.swift:1031-1045 | `complete(…, search:)` existe (chat_composer_cubit.dart:114-121), mas o compositor recebe `onComplete: composer.complete` só com texto e cursor (chat_page.dart:206) | `chat_complete{search}` | detalhe | Título do menu promete "busque" |
| Chip "PARA ▾"; placeholder "Prompt para X…", dica, "Sem conversa ainda"; tooltip do custo | falta | ChatComposer.swift:49,101-105,256-316 · ChatHeaderRow.swift:34 | chat_composer.dart:175-177,252-278; chat_block_view.dart:156-204 | n/a | detalhe | |
| Passo (▸/▾, resumo, realce); diff lado a lado | metade | ChatBlockLayout.swift:140-171 · DiffView.swift | chat_block_view.dart:286-468 | `chat_step` | detalhe | Sem mudança |
| Participante morto esmaecido; custo por agente; relógio na coluna | metade | ParticipantsColumn.swift:21-58,280-325 | participants_column.dart:141-148 | `usage.agents` | detalhe | Sem clique, mas não esmaece |
| Enter/⇧Enter, Esc/setas, @menção, carregar mais, rolagem, coluna, ⌥⌘1/2 | ok | — | chat_composer.dart:106-144; chat_thread_view.dart:65-182; chat_scroll.dart | `chat_send`, `chat_complete`, `chat_more` | ok | Sem regressão da refatoração |

### Chat — novos

| item | status | Swift | Flutter | gravidade | nota |
|---|---|---|---|---|---|
| Abrir/fechar painel da fila apaga o texto do compositor e rouba o foco | regrediu (foco) | ChatContainer.swift:681-697 | chat_page.dart:211-233; chat_composer.dart:174 | incomoda | |
| Alternar shell↔agente remonta a thread e perde a posição | diferente | ChatContainer.swift:670-679 | chat_page.dart:133-157 | detalhe | |
| Glifo de estado na coluna (⌛, ✕ cinza, ponto apagado) | falta | ParticipantsColumn.swift:352-372 | participants_column.dart:213-246 | detalhe | Morto ganha ● vermelho |
| Mão em toda linha da thread; toque disputa com `SelectableRegion` | diferente | ChatRowView.swift:318-341 | chat_thread_view.dart:270-294 | detalhe | Não conferido rodando |
| `chat_step` não converte erro de socket | falta | — | socket_chat_repository.dart:59-65; chat_conversation_cubit.dart:92-93 | detalhe | Erro assíncrono não tratado |

## Fila

### Nó fila

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| ⌘V de print (editor, resposta, linha nova) | **ok** (era falta) | QueueNode.swift:82-86,552,588,1078-1082,1138-1142 | queue_text_field.dart:81-104 → U/commons/widgets/pasted_image.dart:23-42 → ui/macos/Runner/Drop/EgeonImageDropPlugin.swift:37-38,69-80 → queue_cubit.dart:195-230 | `queue_attach` png/path (R/runtime/actor/queue_commands.rs:336-362) | ok | Depende de o ⌘V chegar antes do "Colar" do menu nativo — não executado |
| Miniatura (200 px); clicar abre o print | **ok** | QueueNode.swift:677-727,815-818 | queue_row.dart:228-245,339-435; queue_cubit.dart:160-161 | `queue_open_image` | ok | |
| Comentar pendente; "Apagar" oculto em enviada; "Voltar para pendente" só se não travada; rótulos "Mover para cima/baixo" | **ok** | QueueNode.swift:633,827-835 | queue_row.dart:101-113,251-282 | `queue_*` | ok | |
| Lixeira na tarefa aberta | falta | QueueNode.swift:513,656 | queue_row.dart:283-299 | `queue_remove` | detalhe | |
| Reordenar arrastando direto | falta | QueueNode.swift:204-229 | queue_body.dart:204-213 (segurar antes) | `queue_move` | detalhe | |
| Marcas/meta com hora; placeholders | metade | QueueNode.swift:505,619-675 | queue_row.dart:118-129,173,216 | — | detalhe | |
| Barra, aviso, criar, abrir/fechar, bolinha, enviar, responder, thread, arrastar print | ok | QueueNode.swift:17-336 | queue_bar.dart; queue_body.dart:54-133; queue_notice_cubit.dart | `queue_*` | ok | Barra sem tooltips |
| **Novo:** clicar no vazio de tarefa aberta fecha a tarefa | diferente | QueueNode.swift:762-769 | queue_body.dart:149-152 | n/a | incomoda | |
| **Novo:** teclado da fila (Esc na resposta, Esc na nova, devolver foco, focar resposta de enviada) | falta | QueueNode.swift:265-273,587,748-757,1137 | queue_row.dart:77-85,260-280; queue_body.dart:305-312 | n/a | detalhe | |

### Fila no chat

| item | status | Swift | Flutter | gravidade | nota |
|---|---|---|---|---|---|
| Largura sobrevive a reiniciar | falta | ChatContainer.swift:33-38 | U/features/chat/presentation/cubit/queue_panel_width.dart:6-12 | detalhe | |
| Tooltip do fechar | falta | ChatContainer.swift:39-40 | queue_bar.dart:83-92 | detalhe | |
| Teclado vai para "Nova tarefa" ao abrir | falta (piorou) | ChatContainer.swift:695 | queue_body.dart:305-312 | incomoda | Compositor pega o foco |
| Painel volta aberto depois do canvas | falta | ChatContainer.swift:712-724 | chat_queue_panel_cubit.dart:33; chat_page.dart:50-52 | detalhe | |
| FILAS, abrir/fechar, "+ Nova fila", divisória, corpo | ok | ParticipantsColumn.swift:76-197 | participants_column.dart:71-81,250-364; chat_queue_panel_cubit.dart:49-70; queue_side_panel.dart:42-96 | ok | `chat_new_queue` |
## Menus do app e atalhos

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| Copiar alvos de dispatch ⇧⌘T | **ok** (era falta) | main.swift:4211-4216,4255-4257 | app_menu.dart:150-153; shell_cubit.dart:50 → copy_dispatch_targets.dart:12 → socket_menu_repository.dart:14; U/core/adapters/clipboard_writer.dart | `copy_targets` (R/runtime/actor/menu_commands.rs:13-17) | ok | Sem core, falha calada |
| Processos… ⌥⌘P | **ok** (era falta) | main.swift:4258-4259 | app_menu.dart:154-157; shell_shortcuts.dart:119-120 | `processes` | ok | Abre 2º painel por cima do 1º |
| ⌘= / ⌘- / ⌘0 | **ok** (era falta) | main.swift:4317-4319 | shell_shortcuts.dart:121-126 → canvas_commands.dart:31-35 | n/a | ok | Valem também com foco em nó (Swift devolve a tecla ao nó) — detalhe |
| ⌘1-3 das ferramentas | falta | main.swift:4313-4315 | shell_shortcuts.dart:114-115 (abas) | n/a | detalhe | Quase paridade (no Swift a aba vence) |
| ⌘→/⌘← e ⌘W desabilitados conforme abas; ✓ de modo e de barra recolhida | metade | main.swift:4101-4134,4234-4244 | app_menu.dart:134-145,210-221 | n/a | detalhe | |
| Menu não mostra nenhuma tecla (fora Editar) | falta | todo item com keyEquivalent | app_menu.dart:15-17 (por escolha) | n/a | detalhe | |
| Sobre o Egeon Deck: crédito AGPL-3.0-only | falta | main.swift:4153-4163 | item do sistema; bundle diz "All rights reserved" (ui/macos/Runner/Configs/AppInfo.xcconfig:14) | n/a | detalhe | Contradiz a licença |
| Atalhos com página web focada / sem foco na casca | falta (provável) | key equivalents do menu | `CallbackShortcuts` (home_shell_page.dart:204), sem autofocus; nada em ui/macos/Runner/Web repassa ⌘ | n/a | incomoda | **Não executado** |
| Com diálogo/Processos aberto nenhum atalho vale; Processos empilha | metade | `ProcessesWindow.present()` reaproveita | app_dialog.dart:51-55; processes_panel.dart:17 | n/a | detalhe | |
| ⌘]/⌘→ sem aba percorre todas as bancadas | falta | main.swift:4055-4061 | tabs_cubit.dart:48-50 | n/a | detalhe | |
| Return confirma o padrão; clique fora não cancela | metade | NSAlert | app_dialog.dart:51-64; standard_dialogs.dart:149 | n/a | detalhe | |
| Atualizações, automático ✓, ⌘]/⌘[, Aba 1…9, órfãos ✓, Sair, Editar, ⌘/, ⌥⌘1/2 | ok | main.swift:4229-4306 | app_menu.dart:119-239; shell_shortcuts.dart:58-127 | `update_*`, `reaper_enabled` | ok | |

## Diálogos, processos, atualização, uso

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| Templates: "Canvas vazio" / "Salvar como template" / "Já existe" / "Atualizar o template X?" | **ok** (era falta) | main.swift:2357-2451 | app_forms.dart:358-442 | `save_template` | ok | |
| "A bancada não foi removida"; títulos de presentError | **ok** (era falta) | main.swift:1557-1563,1756-1764 | app_forms.dart:160-166,199,221,349-353 | R/runtime/actor/node_commands.rs:1081-1106 | ok | |
| "já está aberto" (2ª instância) | falta (por desenho) | main.swift:101-117 | U/core/adapters/egeon_app_launcher.dart:56 | n/a | detalhe | |
| Janela Processos | metade | L/Features/Processes/Views/ProcessesWindow.swift:43-171 | processes_panel.dart:17-29,68 (modal 900×480) | `processes` | incomoda | Título com flavor resolvido; ainda modal, sem redimensionar nem guardar frame, sem dica do comando |
| Encerrar órfãos/selecionados; `/processes?show=1` | ok | ProcessesWindow.swift:173-205 · ControlSocket.swift:629 | processes_panel.dart:105-180; update_host.dart:87-88 | `processes_reap`, `processes_kill` | ok | |
| Aviso de versão traz o app para a frente | falta | main.swift:4191-4201 | update_host.dart:92-109 | `update_answer` | detalhe | |
| Aviso de versão, "última versão", encerrar após troca | ok | UpdatePrompt.swift · UpdateController.swift | update_prompt_body.dart; update_host.dart:79-115 | sim | ok | |
| Pastilha de uso com tooltip | metade | UsagePill.swift:25,40 | usage_pill.dart:38-78 (sem dica); lateral usa (bench_cost.dart:25) | `tooltip` vem do core | detalhe | |
| `/usage?show=1`, `/workbench/color?show=1`, `/about` abrem algo | falta | ControlSocket.swift:565-569,877-881,904-906 | falta | efeitos descartados (R/runtime/actor/chat_commands.rs:163-166; org_commands.rs:501) | detalhe | |
| Painel de uso | ok | UsagePanel.swift:128-235 | usage_popover.dart; usage_panel.dart | sim | ok | |

## Avisos e cortinas

| item | status | Swift | Flutter | core tem? | gravidade | nota |
|---|---|---|---|---|---|---|
| Cortina "um instante" (limpar, remover) | **ok** (era nunca aparecia) | BusyOverlay.swift · main.swift:1808-1811,3311 | shell_snapshot.dart:52 ← organization.dart:98; home_shell_page.dart:192; shell_curtains.dart:9-52 | R/runtime/org.rs:421-425; R/runtime/actor/node_clean.rs:79-97 | detalhe | Falta "Conferindo o que se perde…"; cobre só o conteúdo, não a barra da vista nem as abas (WorkbenchShell.swift:344-348) |
| Cortina de acesso: "O macOS está perguntando"; Return = "Abrir Ajustes" | metade | AccessOverlay.swift:8-70 | shell_curtains.dart:98-160; `asking` nunca preenchido (shell_snapshot.dart:55) | sem campo `asking` | detalhe | Abrir Ajustes / Pedir de novo ok |
| Faixa "Copiando o que o git não versiona…" | **ok** (era falta) | main.swift:1234-1250 | shell_curtains.dart:54-96; home_shell_page.dart:190-191 | R/runtime/actor/worktree_copy.rs:21-99 | ok | Posição: ver item 9 do topo |
| Faixa "Ciclo: …" | **ok** (era falta) | EdgeController.swift:60 | ShellBanner | R/runtime/actor/node_commands.rs:492-505; org_commands.rs:439-451 | ok | Apagar após 6 s leva junto a faixa de cópia — defeito do Swift portado, anotado no core |
| Faixas "Caminho não existe" / "Pasta inexistente" | falta | main.swift:2824,2842 | só `pathExists` na lateral | não emite | detalhe | |
| Barra da vista como titlebar, título oculto, abre maximizada | falta | ViewToolbar.swift:227-248 · main.swift:143-166 | ui/macos/Runner/MainFlutterWindow.swift | n/a | detalhe | |
| Pílula canvas/chat, nome + bolinha, dica; notificação, som | ok | ViewToolbar.swift · SystemNotifier.swift | view_toolbar.dart:44-104; MainFlutterWindow.swift:23-30 | sim | ok | |

### Tooltips

✔ `U/commons/widgets/app_tooltip.dart` é usado em 14 lugares de 9 arquivos (barra do canvas, cabeçalho do card, subtítulo, retry, faixa do agente, esforço, perfil web, custo na lateral). Ainda faltam: barra da vista (caminho, Canvas/Chat, cor); lateral (badge, caminho, +, recolher ⌘/, "Nova bancada em worktree"); chat (Enviar, custo do turno, bandeja de permissão, consumo do agente, fechar painel); fila (barra, apagar, print); web (Voltar/Avançar/Recarregar); pastilha de uso; relógio "clique para zerar"; paleta; Processos; formulário de nó (Maestro, "Papel: …", os dois + — `PlusButton` só tem Semantics, U/commons/widgets/form_controls.dart:251-264).

## Listas finais

**Comandos que o core tem e a UI não usava** — resolvidos: `set_node`/formulário (`node_form`, `apply_node`…), `worktree` sem bancada e por terminal, `queue_attach` colado, `permission_answer` deny, `save_workspace` refused/warning. Seguem sem uso: `chat_complete{search}` (assinatura existe, ninguém passa), `chat_clear` (paridade), `close_terminal`, `create_workspace`, `add_project`, `multi_project` (cobertos por outros comandos).

**O que falta também no core** — resolvidos: `save_template`, `reset_clock`, `retry`, `open_node_folder`, `queue_open_image`, `copy_targets`, `open_url`, `worktree_info`/`plan` sem bancada, branch por repositório, banner de ciclo, fase de limpeza, vários pedidos de permissão, fixture de `worktrees`. **Seguem:** catálogo `/` do CLI (`slash` → `None`); efeitos `show` de `/usage`, `/workbench/color` e `/about`; `asking` da cortina de acesso; faixas "Caminho não existe"; `finish` do formulário não normaliza cwd absoluto (R/features/node/form.rs:283-287); plano de remoção calcula perdas antes do 1º diálogo; fixtures sem `save_workspace` refused/warning nem `worktree` multi `failed`; comentário desatualizado em R/protocol/org.rs:559-560.
