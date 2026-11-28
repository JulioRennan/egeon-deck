# 07 · usage — consumo da bancada

> Módulo: `ui/lib/features/usage` (hoje `usage_pill`, `usage_popover`,
> `usage_panel`, `bench_cost`). Cubit e repositório ficam; widgets saem.
> Referência: v3 **Custo · painel aberto, Log**, **Custo · por agente**,
> **Custo · por modelo**, **Chat · painel de custo aberto**
> (tela `V3-canvas-padrao` do canvas da v3; dados de
> exemplo e regras de filtro no script: `LOG`, `summarize`, `pickF`).

Pré-requisitos: E1, E2 (lugar fixo do chip no canto, H6).

## U1 · Chip de consumo

- **O quê:** no canto, em vidro: `WorkbenchClock` (martelo `running` com o
  tempo trabalhando, mão `attention` com o tempo esperando você) e o custo
  `US$ 11,49` em mono 12/16 w500. Clique abre o painel (U2); aberto, o chip
  fica marcado. Aparece no canvas e no chat.

## U2 · Painel de consumo

- **O quê:** painel de vidro sobre o chip ("Consumo da bancada <nome>"):
  - topo: nome da bancada na cor + branch (ícone worktree), recolher;
  - tempos: **Trabalhando** `mm:ss` · **Parado** `mm:ss` · **Total** com o
    custo mostrado e o escopo ("9 turnos" ou "<filtro> · N de M turnos");
  - `SegmentedControl` **Log | Por agente | Por modelo** + "Limpar" quando há filtro;
  - rodapé: "Abrir Consumo e custo" (link) e "Zerar cronômetro" (perigo).

## U3 · Visão Log

- **O quê:** linha por turno: agente na cor, hora, "precisa de você" quando
  esperando, custo; o que fez; "modelo · tokens entrada / saída". Filtrável
  pela visão por agente ou por modelo.

## U4 · Por agente e Por modelo

- **O quê:** linha por agente (ou modelo): nome na cor (modelo em `accent`),
  custo, "N turnos", tokens entrada/saída e barra de proporção (`UsageBar`);
  "Clique para filtrar o log": clicar filtra o Log e volta a ele; clicar de
  novo tira o filtro.

## U5 · Formatos

- **O quê:** dinheiro `US$ 1,19` (vírgula), tokens abreviados (`14,1K`,
  `168K`), tempo `mm:ss` (ou `h:mm:ss`), sempre com algarismos tabulares.

## Depende do core?

Log por turno (hora, agente, o que fez, modelo, tokens, custo), tempos
trabalhando/parado da bancada e zerar cronômetro: verificar o que o socket já
entrega (o `usage` e o relógio da bancada existem no porte). O que faltar fica
na lista, sem rota nova.

## Some daqui

`usage_pill`, `usage_popover`, `usage_panel`, `bench_cost` com o visual antigo.
