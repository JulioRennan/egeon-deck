# Redesign da UI — índice

> Rascunho para planejar. Cada arquivo desta pasta é um módulo de `ui/lib`
> com as tarefas grandes que o canvas pede. Nada aqui está decidido.

## Ordem

| Fase | Arquivo | O quê |
|---|---|---|
| 0 | [`../4-design-system.md`](../4-design-system.md) | tokens, cores, fontes, tamanhos, bordas, tema |
| 1 | [`01-commons.md`](01-commons.md) | componentes base do DS, usados por todos os módulos |
| 2 | [`02-home.md`](02-home.md) | moldura da janela: barra de topo, trilho de bancadas, gaveta, Canvas \| Chat |
| 3 | [`03-sidebar.md`](03-sidebar.md) | a barra lateral (vira a gaveta de bancadas) |
| 4 | [`04-canvas.md`](04-canvas.md) | superfície, barra de ações, menus da barra, cor da bancada |
| 5 | [`05-node.md`](05-node.md) | cards de agente, shell, fila e web |
| 6 | [`06-chat.md`](06-chat.md) | conversa, passos, diff, permissão, composer |
| 7 | [`07-usage.md`](07-usage.md) | consumo: chip, painel Log / Por agente / Por modelo |
| 8 | [`08-demais.md`](08-demais.md) | tabs, workbench, workspace, processes, update: o que muda sem tela própria no canvas |

A fase 0 vem antes de tudo. A 1 antes das telas. Da 2 em diante, a ordem
segue a dependência: a moldura recebe as outras.

## Fonte

Canvas https://claude.ai/artifact/Q5FupA96prhWvMX4LQmSc7 — a página
**"v3 — canvas final (todos os cenários)"** é a referência. As outras páginas
são explorações; delas só vale o que a v3 importa.

| Tela da v3 | Estado que ela mostra | Módulos |
|---|---|---|
| Canvas · padrão | bancada aberta, cursor, nada aberto | home, canvas, node, usage, chat (composer) |
| Canvas · gaveta de bancadas aberta | gaveta da barra lateral sobre o canvas | home, sidebar |
| Canvas · outra bancada selecionada | cor e brilho da moldura trocam com a bancada | home, canvas |
| Barra · menu do terminal de agente | segurar ⌘3: componentes salvos | canvas |
| Barra · Template ▾ | salvar / atualizar template | canvas |
| Barra · cor da bancada | 12 cores de identidade | canvas |
| Custo · Log / por agente / por modelo | painel de consumo aberto | usage |
| Chat · permissão acima do composer | pedido de permissão | chat |
| Chat · passos expandidos | passos do agente | chat |
| Chat · gaveta / custo | gaveta e consumo também no chat | home, sidebar, usage |
| Canvas · composer com rascunho | composer no canvas, "Para maestro" | chat |

Outras páginas que a v3 usa:

| Página | Tela | Uso |
|---|---|---|
| Barra lateral | `Sidebar` | importada pela v3 como gaveta |
| Nós — agente | A · com e sem maestro; Shell | cabeçalho e controles dos cards |

Explorações que **não** entram (ficaram para trás): Custos D/E/F, Consumo G/H,
Preço C, Lateral com tabs e com ⋯ (a `Sidebar` é a consolidada).

## O que mudou de lugar

- **A barra de abas de bancada some.** No lugar: voltar/avançar, a trilha
  `projeto / bancada` e um **trilho vertical** de bancadas (iniciais na cor da
  bancada, contador de "precisa de você"), com a gaveta "Todas as bancadas".
- **O composer aparece no canvas também**, embaixo, com destinatário.
- **Consumo vira um chip no canto** que abre um painel com três visões.
- **A cor da bancada tinge a moldura** (borda e brilho internos).

## Divergências entre canvas e DS

| Ponto | Canvas | DS | Proposta |
|---|---|---|---|
| Vidro | barra de ações, painel de consumo e popovers com `backdrop-filter: blur(20px)` | dizia "sem blur nem vidro" | **decidido (2026-11-19):** vidro do canvas entra no DS (v21) — `glass`, `glass-border`, `glass-highlight`, `shadow-glass`, `blur-glass`; só no que flutua |
| Hover dos botões da barra | `#ffffff0f` | `steel` | usar `steel`, ou registrar o tom no DS |

## Como cada arquivo está escrito

Por tarefa: **o que é**, **telas de referência**, **componentes do 01 que usa**,
**depende do core?** (dado que talvez o socket ainda não entregue) e **pronto
quando**. Tarefas grandes; o detalhe fino sai quando cada uma começar.
