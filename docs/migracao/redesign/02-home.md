# 02 · home — a moldura da janela

> Módulo: `ui/lib/features/home` (hoje `root_layout`, `workbench_shell`,
> `view_toolbar`, `usage_corner`, `shell_curtains`, `app_menu`,
> `shell_shortcuts`). A moldura é o que fica em volta de canvas e chat em
> qualquer bancada. Os widgets atuais saem; cubits e atalhos ficam se servirem.

Referência: v3, telas **Canvas · padrão**, **Canvas · gaveta**, **Canvas ·
outra bancada**, **Chat · gaveta**.

## H1 · Janela sem barra de título

- **O quê:** conteúdo por baixo da barra do macOS; semáforos dentro da faixa
  de 44 (`size.titlebar`); arrastar pela faixa vazia. Linux/Windows: botões de
  janela à direita, `ghost` só ícone de 36.
- **Depende de:** escolher `window_manager` ou `macos_window_utils` (entra na
  proposta).
- **Pronto quando:** a janela arrasta, maximiza com duplo clique e os
  semáforos não cobrem nada.

## H2 · Barra de topo

- **O quê:** voltar / avançar (⌘[ / ⌘]), `SegmentedControl` Canvas | Chat
  (⌥⌘1 / ⌥⌘2) e a trilha `projeto / bancada` com o nome da bancada na cor
  dela; clicar na trilha troca de bancada.
- **Substitui:** a barra de abas de bancada (`features/tabs`) — ver `08-demais.md`.
- **Depende do core?** histórico de navegação entre bancadas: verificar se o
  core guarda ou se é só da UI.
- **Pronto quando:** os quatro controles funcionam por clique e atalho.

## H3 · Trilho de bancadas

- **O quê:** coluna estreita à esquerda com as bancadas abertas: iniciais na
  cor da bancada, fundo tingido na atual, traço de 2px na atual, estado
  (precisa de você / terminou / em trabalho / parada), contador total de
  "precisa de você", botão "Nova bancada" e "Todas as bancadas" (abre a gaveta).
- **Regras:** "terminou" some quando você entra na bancada; só agente chama.
- **Depende do core?** contagem por estado por bancada — já vem no evento de
  atividade? verificar.
- **Pronto quando:** clicar troca de bancada, o tooltip diz nome e estado, e a
  troca não pisca.

## H4 · Gaveta de bancadas

- **O quê:** a `Sidebar` (arquivo `03-sidebar.md`) aberta por cima, a partir
  do trilho; só abre e fecha (sem fixar; o botão de recolher fica no cabeçalho da barra lateral).
- **Pronto quando:** abre e fecha em 200 ms, Esc fecha.

## H5 · Moldura com a cor da bancada

- **O quê:** a área de conteúdo ganha borda interna de 1px e brilho interno na
  cor da bancada (`cor 18%` na borda, `cor 14%` no brilho de 32px). Trocar de
  bancada troca a cor.
- **Depende de:** cor da bancada vinda do core (definida no menu de cor do
  canvas, `04-canvas.md`).
- **Pronto quando:** a cor acompanha a troca de bancada nos dois modos.

## H6 · Camadas fixas

- **O quê:** lugar fixo de cada coisa que flutua sobre canvas e chat: barra de
  ações (topo, centro), chip de consumo (canto), composer (embaixo), pedidos de
  permissão (acima do composer), toasts. Uma pilha só, para nada se cobrir.
- **Pronto quando:** abrir o painel de consumo, um menu da barra e um pedido de
  permissão ao mesmo tempo não sobrepõe nada.

## H6b · Overlay sob o tema

- **O quê:** a casca hoje usa `builder` sem `Navigator`, então não há `Overlay`
  abaixo do `Theme`. Pôr um `Overlay` na casca para Tooltip, Menu, Popover,
  Dialog e Toast abrirem nas telas (apontado pelo dev na E1).
- **Pronto quando:** os componentes flutuantes da E1 abrem dentro do app, não só na galeria.

## H7 · Atalhos e menu do app

- **O quê:** ⌥⌘1/2, ⌥⌘P (processos), ⌘[ ⌘], ⌘1–4 das ferramentas, ⌘−/⌘=/⌘0
  de zoom, ⌘K busca de bancada; menu do macOS com os mesmos itens.
- **Pronto quando:** cada atalho da v3 tem a sua ação e aparece no tooltip.

## Some daqui

`usage_corner` (vira `07-usage.md`), `view_toolbar` (vira H2),
`shell_curtains` e o layout atual de raiz.
