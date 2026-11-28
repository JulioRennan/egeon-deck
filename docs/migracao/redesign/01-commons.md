# 01 · commons — componentes base

> Módulo: `ui/lib/commons/widgets`. Tudo que existe hoje lá sai
> (`glass_panel`, `toolbar_button`, `app_text_field`, `spinner`,
> `attention_ring`, `count_seal`, `context_menu`…). Os componentes novos seguem
> os do DS, com os mesmos nomes, e são widgets próprios — sem `ElevatedButton`,
> sem ripple, uma borda por elemento.

Pré-requisito: fase 0 (`../4-design-system.md`) pronta.

## C1 · Ícones

- **O quê:** conjunto `EgIcon` com `lucide_icons` (traço 1.5, grade 16) e os
  ícones próprios do canvas que o Lucide não tem: martelo, mão e octógono do
  cronômetro; terminal de agente (com antena e olhos); fila; template;
  worktree; enquadrar.
- **Referência:** DS `Icon`; SVGs da barra de ações e do rodapé de consumo na v3.
- **Pronto quando:** cada ícone usado na v3 existe por nome, em 16/14/12, na
  cor do texto ao redor.

## C2 · Botões

- **O quê:** `Button` (primário, secundário, fantasma, perigo; sm 30 / md 36 /
  lg 42), `IconButton` (36, só ícone, tooltip obrigatório), `ToolButton` (o da
  barra: ligado = `accentSoft` + `accent`).
- **Estados:** hover `steel`, pressionado `steelActive` e −2%, foco 2px
  `accent` na mesma borda, desabilitado 40%, carregando (spinner no lugar do ícone).
- **Referência:** DS `Button`; barra de ações da v3; Permitir · Sempre · Negar.
- **Pronto quando:** os quatro tipos em três tamanhos, todos os estados, mão no
  ponteiro (ADR-048).

## C3 · Superfícies flutuantes

- **O quê:** `Popover`, `Menu` (itens de 32, separador, atalho à direita,
  item perigo), `Tooltip`, `Dialog` (raio 14, `shadow.modal`, `scrim`),
  `Toast`. Uma camada de overlay única com fechamento por Esc e clique fora.
- **Referência:** DS `Popover`, `Menu`, `Dialog`, `Toast`, `Tooltip`; menus
  Template ▾, cor, componentes salvos, "Limpar o contexto?".
- **Vidro:** menus e popovers usam `EgeonGlass` (fundo, borda, fio de luz,
  blur gaussiano 20 com saturação 130%) e `EgeonShadow.glass`. Um
  `GlassSurface` comum a barra, painéis, menus e popovers. Diálogos são sólidos.
- **Pronto quando:** abre ancorado, se reposiciona na borda da janela, 140 ms
  na entrada, foco preso no diálogo.

## C4 · Campos

- **O quê:** `TextField`, `TextArea`, `Select`, `Checkbox`, `Radio`,
  `Toggle`, `Slider`, `SegmentedControl` (Canvas | Chat; Log | Por agente |
  Por modelo; Todas | Ativas).
- **Referência:** DS dos mesmos nomes.
- **Pronto quando:** fundo `carbon`, borda `lineStrong` → `lineHover` →
  `accent`, erro em `danger` com mensagem.

## C5 · Estado do agente

- **O quê:** `StatusDot` (precisa de você, terminou, falhou, parado),
  `Spinner` (trabalhando), ampulheta (segundo plano), `AttentionRing` (halo
  pulsante 1600 ms), `Counter`/`Badge`, `WorkbenchClock` (martelo · mão ·
  octógono com `mm:ss`), `ContextRing` (contexto em uso).
- **Referência:** DS dos mesmos nomes; cabeçalho dos cards; trilho de bancadas.
- **Pronto quando:** cada estado tem cor **e** forma; com movimento reduzido o
  halo e o spinner desaceleram (halo 3200 ms, spinner 1800 ms), como o DS.

## C6 · Identidade e texto

- **O quê:** `AgentName` (nome na cor de identidade), `InfoPill`
  (modelo · esforço · contexto), `EdgeLabel`, `CodeBlock`, `DiffView`
  (lado a lado e unificado), `UsageBar`.
- **Referência:** DS dos mesmos nomes; cards e chat da v3.
- **Pronto quando:** dot redondo nunca é identidade; números com algarismos
  tabulares.

## C7 · Galeria de componentes

- **O quê:** página só do modo dev que mostra todos os componentes acima, em
  todos os estados, para revisar lado a lado com o DS.
- **Pronto quando:** cada componente do DS tem a sua seção.

## Fora daqui

Composer, item da barra lateral, card de nó, painel de consumo: são do módulo
que os usa (`chat`, `sidebar`, `node`, `usage`), montados com estes.
