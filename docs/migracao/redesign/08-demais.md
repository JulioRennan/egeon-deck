# 08 · demais módulos e limpeza do tema antigo

> O que o canvas não desenha, mas tem de vestir o DS, e a remoção de tudo que
> ficou da UI provisória. Levantamento de 2026-11-19, depois da E6: ainda
> importam o tema antigo (`app_colors`, `app_theme`, `code_palette`,
> `workbench_palette`) 13 arquivos de `commons/widgets` e 23 de features
> (chat 2, home 3, node 3, processes 1, tabs 2, update 1, usage 4,
> workbench 5, workspace 2). Os números mudam com a E7; refazer o grep ao começar.

Pré-requisito: E1–E7 aprovadas.

## D1 · Formulários (workbench, workspace, nó)

- **O quê:** `new_bench_form`, `node_worktree_form`, os de worktree múltipla,
  `new_project_form`, `workspace_form`, `multi_project_editor` e o
  `node_form` com `Dialog` (variante form), `TextField`, `Select`,
  `Checkbox`, `Toggle` e `Button` do E1. Rótulos e erros como o DS manda
  ("Erro em uma frase: o que aconteceu e o que fazer").
- **Some:** `app_text_field`, `form_label`, `form_controls`, `pick_list`
  (se o `Select` cobrir) e o `standard_dialogs` antigo.

## D2 · Processos (⌥⌘P)

- **O quê:** `processes_panel` com o `ProcessTable` do DS (comando, nó com a
  cor, estado, PID, CPU, memória, tempo; órfão destacado; ordenação), em painel
  `Dialog` ou lateral como hoje.

## D3 · Atualização do app

- **O quê:** `update_host` e afins com `NoticeBanner`/`Toast` do E1.

## D4 · Módulo tabs

- **O quê:** a barra de abas saiu da casca na E2. Remover os widgets de
  `features/tabs` e o que só eles usavam; manter o que o trilho/atalhos ainda
  usam (reordenar, ⌘1–⌘9) ou movê-lo para onde é usado.
- **Depende de:** decisão do Julio sobre ⌘1–⌘4 × ⌘1–⌘9.

## D5 · Limpeza do tema e dos widgets antigos

- **O quê:** apagar `theme/app_colors.dart`, `app_theme.dart`,
  `code_palette.dart`, `workbench_palette.dart` e os widgets antigos de
  `commons/widgets` sem uso (`glass_panel`, `toolbar_button`, `spinner`,
  `attention_ring`, `count_seal`, `context_menu`, `app_tooltip`, `glyphs`,
  `workspace_badge`…), trocando os últimos usos pelos do E1.
- **Pronto quando:** `grep` pelo tema antigo em `ui/lib` e `ui/test` não acha
  nada; nenhum hex solto fora de `theme/`; `analyze` e `test` limpos.

## D6 · Fechamento

- **O quê:** `ui/CLAUDE.md` e a skill `estrutura-flutter` descrevem o tema
  novo, `commons/widgets/eg/`, `ShellLayers` e as regras de widget do DS;
  `CHANGELOG.md` com as linhas visíveis do redesign; a página de amostra e a
  galeria seguem no modo dev.
- **Conferência visual:** abrir o app em modo dev e comparar cada tela da v3
  (precisa do Julio ou de captura autorizada; nada abre na tela sem pedido).
