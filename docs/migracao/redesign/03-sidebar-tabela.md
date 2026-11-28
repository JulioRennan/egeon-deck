# Gaveta de bancadas — referência (Sidebar.dc.html) × app

Fonte: tela `Sidebar` do canvas da v3 (340 de largura).
Cores sempre pelos tokens (`context.eg`, `EgeonColors.overlayN`); nenhum hex solto.

| Elemento | Referência | App |
|---|---|---|
| Painel | 340, raio 14, vidro (`rgba(13,15,17,.62)`, blur 20, borda 6%, sombra), padding 12/10/10 | `BenchDrawer` → `GlassSurface` (raio 14, `EgeonGlass`); o respiro é do cabeçalho (8 em cima) e da lista (10+2 nas laterais, 10 embaixo). Sem título "Bancadas" nem ✕ |
| Flutuar | painel sobre o canvas; só abre e fecha | idem (sem fixar); no chat fica ao lado do conteúdo (decisão 46) |
| Linha do topo | uma linha: abas à esquerda; buscar, filtrar, +, recolher à direita; fio de 6% embaixo de borda a borda, padding 8 / 10 | `SidebarHeader`: mesma linha e fio (`lineSubtle`), padding 8/8/10/8, gap 4 |
| Abas | 92 × 36, texto 13 w500 `textSecondary` (hover primary, ligada accent), contagem mono 11 `textMuted`, raio 7 | `_Tab`: mesmas medidas e cores |
| Sublinhado | 64 × 2, accent, raio 2, `left 14`, desliza 92 em 200 ms | `_Tabs`: `AnimatedPositioned` (200 ms, `easeStandard`), mesmo `left`/tamanho, sobre o fio |
| Ponto de atenção na Ativas | 6 px laranja, `top 7 right 8`, pulsa | `StatusDot(attention, sm, animated)` no mesmo lugar |
| Botões `.sb-ib` | 30 × 30, raio 8, `textSecondary`; hover `overlay6` + primary; ligado accentSoft/accent; ícone 16 (o + é 14) | `_HeaderButton`: idem |
| Filtro com contador | selo 14 accent, mono 10 w600, `right 2 top 2` | `_FilterBadge`: idem |
| Buscar | troca as abas pelo campo na mesma linha: 32, raio 8, fundo 3,5%, lupa à esquerda, ✕ 28 à direita, foco com borda accent; Esc fecha | `_SearchField`: mesmo; Esc e ✕ fecham; ⌘K abre e foca |
| Último botão | ícone de painel, `aria-label`/`title` "Recolher barra lateral" | `EgIcons.sidebar`, tooltip e semântica "Recolher barra lateral" → fecha a gaveta |
| Resumo do filtro | 12/16 `textSecondary`, "Limpar" link accent, padding 0 10 | `SidebarFilterSummary`: idem (20 de inset) |
| Workspace | min 44, padding 6/8, gap 8; seta 12; avatar 26 raio 7 `steelActive` (letra 12 w600); nome 13/18 w600; "N bancadas" 12/16 `textMuted`; ponto 6 laranja; hover 4% | `SidebarItem.workspace` + `WorkspaceMark`: idem (hover `overlay4`) |
| ⋯ | 26, aparece no hover, `top 10` (ws), 4 (projeto), 8 (bancada) | idem (IconButton compacto) |
| Projeto | min 32, padding 4/8/4/12, gap 8; seta 12; pasta 14; nome 13/18 **w500 `textPrimary`**; contagem mono 12 `textMuted` sempre visível; `+` 14 no hover depois da contagem | `_ProjectBody`: idem; o `+` abre "nova bancada" (hit 30 sobre o vão de 14) |
| Selos de stack | 16 × 16, raio 4, sigla 7,5 w600 sobre `steelActive`, até 5, gap 4, `margin-top 3` | `StackBadges` + `SidebarProject.stacks`: **lugar previsto, sem dado** (ver pendências) |
| Lista de bancadas | margem `6 0 14 18`, padding-left 10, fio 6% à esquerda, gap 4, **sem fios entre bancadas** | idem (removi os fios que o app tinha entre elas) |
| Bancada (cartão) | padding 12/14, raio **6**; selecionada e hover: cor da bancada a 12% | `_BenchBody`: raio 6, 12% |
| Traço da bancada | 2 px na cor dela, **11 px à esquerda do cartão** (sobre o fio); curto (12/12) a 60% em repouso, inteiro a 100% no hover/selecionada | `Positioned(left: -11)`; mesma animação de altura/opacidade |
| Nome | 14/20 w500 na cor dela (600 selecionada), até 2 linhas, `padding-right 26` | idem (`EgeonType.label`) |
| Estados | todos que existem, lado a lado (wrap, 12 × 4): **esperando você** (ponto laranja pulsando + texto laranja w500), **terminou/terminaram** (verde w500; some ao entrar), **N em trabalho** (giro + texto primary); **Parada** só se nenhum | `BenchStatusLine`: mesmos, juntos (antes mostrava um só); chaves `state-needs/done/work/idle` |
| Custo | mono 12 `textPrimary`, na ponta direita | `BenchCostLabel` (já era) |
| Gaveta do workspace | `.sb-gv` 28, padding-left 30, ícone gaveta 14 + texto 12/16 w500 `textMuted`; "Gaveta vazia" / "Gaveta · N" | `DrawerRow`: idem (com projetos guardados a seta cabe no recuo de 30) |
| Espaço entre workspaces | 18 | 18 |
| Ativas: grupo | rótulo 12 w500 `textMuted` com a contagem em mono, padding 12/10/2; bancadas no mesmo fio (margem `2 0 10 8`) | `SidebarActiveView`: idem |
| Ativas: origem | inicial do workspace 14 × 14 raio 4 + projeto 12 `textSecondary`, entre o nome e os estados | `_Origin`: idem |
| Vazio | "Nenhuma bancada com esses filtros." + "Limpar filtros" | já existia (`_Empty`) |
| Menus ⋯ / filtros | popover vidro 232/264, itens 32, kbd mono 11 | já nos componentes do DS (`showMenu`/popover), sem mudança |

## O que depende do core (não inventei)

- **Selos de stack** (`Rs`, `TS`, `Cs`…): o core não detecta a stack do projeto. `SidebarProject.stacks` existe vazio; com dado, os selos aparecem.
- **"Parada há X"** (idade da última atividade por bancada): o core não manda. A linha diz só "Parada".
- **"N paradas há mais de X" recolhível** na árvore e o filtro "Recolher paradas há mais de…": dependem da mesma idade. A aba Ativas já separa "Últimas 24 horas" / "Paradas há mais de 24 horas" com o que o core manda.
- **Logos de TypeScript e Flutter** nos selos (imagens da referência): sem dado de stack não há onde usá-las.

## Fora da referência (mantido do app)

- "preparando…" (terminais subindo) e "removendo…": estados do core que a v3 não desenha.
- Arrastar para reordenar/mover e a linha de inserção; soltar pasta para criar projeto.
- Menus de contexto completos (S5) e botão direito.
