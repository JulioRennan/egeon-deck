# 04 · canvas — superfície e barra de ações

> Módulo: `ui/lib/features/canvas` (hoje `canvas_surface`, `canvas_grid`,
> `canvas_glow`, `canvas_toolbar`, `tool_overlay`, `tool_glyphs`,
> `edge_painter`, `edge_controls`, `canvas_bench_actions`). Os cubits de
> ferramenta, movimento e memória ficam; os widgets saem. Referência: v3
> **Canvas · padrão**, **Barra · menu do terminal de agente**, **Barra ·
> Template ▾**, **Barra · cor da bancada**, **Canvas · outra bancada**
> (tela `V3-canvas-padrao` do canvas da v3).

Pré-requisitos: E1, E2 (moldura com a cor da bancada e camadas fixas).

## V1 · Superfície

- **O quê:** fundo `graphite` com grade de pontos `line` a cada 24px (raio
  1px), que acompanha pan e zoom. Sem sombra na superfície.
- **Pronto quando:** a grade não treme no zoom e não pesa no FPS com 10+ nós.

## V2 · Barra de ações (vidro, topo central)

- **Grupos** (separados por fio vertical de 1px a 8% de branco):
  1. Cursor ⌘1 · Shell ⌘2 · Terminal de agente ⌘3 (com canto ◢ indicando menu) ·
     Web ⌘4 · Fila de prompts
  2. Afastar ⌘− · `100%` (volta a 100%, ⌘0) · Aproximar ⌘=
  3. Template da bancada ▾ · Cor da bancada (quadradinho na cor) ·
     Nova bancada numa worktree desta
  4. Enquadrar todos os nós
- **Visual:** `GlassSurface` raio 14, padding 4, botões `ToolButton` de 36
  (ligado = `accentSoft` + `accent`). Zoom em mono 12.
- **Dica:** com ferramenta de criar ligada, aparece a dica abaixo da barra
  ("Clique ou arraste no canvas para criar um shell" etc.) com "Esc cancela".

## Pendente antes de começar

- **Atalhos ⌘1–⌘4:** a v3 os dá às ferramentas; o porte fiel os usa para ir à
  aba/bancada n (⌘1–⌘9). Decidir com o Julio.

## V3 · Menu do terminal de agente (segurar ⌘3)

- **O quê:** clique curto liga a ferramenta; segurar 380 ms abre o menu
  **Componentes salvos** (nome na cor, meta "CLI · modelo · esforço") e
  "Configurar novo terminal…".
- **Depende do core?** lista de componentes salvos (templates de nó): verificar.

## V4 · Menu Template ▾

- **O quê:** "Salvar como template…" e "Atualizar “<template atual>”".
- **Depende do core?** template atual da bancada.

## V5 · Menu de cor da bancada

- **O quê:** título "Cor da bancada <nome>", grade das 12 cores de identidade
  (Sky, Slate, Iris, Orchid, Mauve, Rose, Clay, Sand, Olive, Moss, Jade, Teal),
  selecionada com anel duplo. Trocar a cor muda na hora a moldura (E2/H5), o
  trilho e a barra lateral.
- **Depende do core?** gravar a cor da bancada.

## V6 · Nós e arestas na superfície

- **O quê:** arestas com `edge` (1.5px) em repouso, `accent` selecionada,
  `running` com tráfego, `line` com limite atingido; `EdgeLabel` com usos/limite.
  Nós fora do foco a `opacity.muted` quando um nó está isolado. Arrastar nó
  com `shadow.drag`.
- O card do nó é do `05-node.md`.

## V7 · Enquadrar e zoom

- **O quê:** enquadrar todos os nós; zoom nos passos do porte (25…300%), ⌘0 volta a 100%.

## Some daqui

`canvas_toolbar`, `tool_glyphs`, `canvas_grid`, `canvas_glow` (vira E2/H5),
`edge_controls` e `canvas_bench_actions` com o visual antigo.
