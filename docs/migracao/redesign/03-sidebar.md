# 03 · sidebar — a barra lateral (gaveta de bancadas)

> Módulo: `ui/lib/features/sidebar` (hoje `sidebar_panel`, `sidebar_segments`,
> `sidebar_tree_view`, `sidebar_active_view`, `bench_row`, `group_row`,
> `drawer_row`, `bench_actions`, `group_actions`, `sidebar_drop`,
> `drag_hooks`). Os widgets saem; cubit, repositório e regras de arrastar
> ficam se servirem. Referência: tela **Sidebar** do canvas
> (tela `Sidebar` do canvas da v3), que a v3 importa
> como gaveta (340 de largura).

Pré-requisitos: E1 (componentes base) e E2 (H4: a gaveta que recebe esta barra).

## S1 · Cabeçalho

- **O quê:** `SegmentedControl` **Todas N | Ativas N** (com dot de atenção se
  alguma precisa de você), busca (⌘K, abre campo "Buscar bancada ou projeto"
  com fechar), filtros (contador de filtros ligados), "Novo" (workspace,
  projeto ou bancada), recolher a gaveta (ícone de painel, `Recolher barra lateral`).
- **Pronto quando:** ⌘K foca a busca, Esc fecha, a busca filtra por nome de
  bancada, projeto e workspace.

## S2 · Painel de filtros

- **O quê:** popover com **Mostrar** (vivas, precisa de você, em trabalho,
  erro, paradas, terminou — cada uma com contagem), **Agrupar por** (árvore ou
  atividade), **Recolher paradas há mais de** (24 h, 3 dias, 1 semana, nunca) e
  **Workspace** (todos ou um, com inicial). Resumo do filtro ativo com "Limpar".
- **Vazio:** "Nenhuma bancada com esses filtros." + "Limpar filtros".
- **Depende do core?** idade da última atividade por bancada ("Parada há 3 d")
  e flag "viva": verificar se o socket entrega.

## S3 · Árvore workspace → projeto → bancada

- **Workspace:** inicial em quadrado, nome, "N bancadas", dot se algo precisa
  de você, ⋯ no hover, recolher.
- **Projeto:** nome, selos de stack (até 5: Rs, Dt, TS, Cs, Ht, Py, Sh, Sq, com
  cor própria), contagem, "Nova bancada neste projeto", ⋯, recolher.
- **Bancada:** nome na cor dela (600 quando selecionada), fundo da cor a 12% e
  traço de 2px à esquerda na selecionada; estado em texto curto (N em
  trabalho / N esperando você / terminou) ou "Parada há X"; custo; ⋯.
  "Terminou" some ao entrar na bancada.
- **Paradas antigas:** agrupadas no fim do projeto, "N paradas há mais de X",
  abre e fecha.
- **Gaveta do workspace:** "Gaveta · N" (projetos guardados) ou "Gaveta vazia".
- **Depende do core?** stack do projeto (detecção por arquivos do repo) e custo
  por bancada: verificar.

## S4 · Visão "Ativas"

- **O quê:** lista plana agrupada por atividade: **Últimas 24 horas** e
  **Paradas há mais de 24 horas**, cada bancada com a inicial do workspace e o
  projeto.

## S5 · Menus ⋯

| Nível | Itens |
|---|---|
| Bancada | Abrir ↵ · Renomear… F2 · Mudar cor… · Salvar como template · Nova bancada numa worktree · — · Limpar bancada · Encerrar terminais · — · Remover bancada… (perigo) |
| Projeto | Nova bancada ⌘N · Abrir no Finder · Copiar caminho · Renomear… · — · Guardar na gaveta · — · Remover projeto… (perigo) |
| Workspace | Novo projeto… · Editar nome e foto… · Recolher tudo · — · Remover workspace… (perigo) |

- Ações destrutivas pedem confirmação com `Dialog` destrutivo.
- **Pronto quando:** cada item chama a ação que já existe no app (ou fica
  listado como pendente de core).

## S6 · Arrastar e soltar

- **O quê:** manter o que o módulo já faz (reordenar, mover bancada/projeto,
  soltar pasta para criar projeto) com o visual novo: `shadow.drag` no item
  arrastado e linha de inserção em `accent`.

## Some daqui

Os widgets atuais de `features/sidebar/presentation/widgets`. A troca de
segmentos antiga vira S1.
