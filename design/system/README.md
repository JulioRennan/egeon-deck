**Egeon · Session orchestration platform · Graphite design system**

Egeon é a mesa de trabalho de quem dirige vários agentes de IA ao mesmo tempo. O visual é grafite: quatro camadas de cinza levemente frio, quase sem cor, e um azul raro que marca a ação principal. A interface é uma ferramenta, não uma vitrine; o terminal e o trabalho dos agentes ficam em primeiro plano. Este sistema é a base do app desktop em Flutter (macOS primeiro, depois Linux e Windows).

## Princípios

1. **Grafite primeiro, cor rara.** A tela é quase toda cinza. O azul do acento ocupa cerca de 3%; quando aparece, todo mundo vê.
2. **Menos coisas à vista.** O secundário (cronômetro e custo na barra lateral, custo e hora da mensagem, ações em linha) aparece no hover ou sob demanda.
3. **Hierarquia por camada, peso e tom.** Separe pelas quatro superfícies, pelo respiro e pelo peso da fonte; não empilhe caixas dentro de caixas.
4. **Uma borda por elemento.** Estado, foco e seleção recolorem a borda que já existe, sem segundo contorno com vão.
5. **Corpo de verdade.** Controles com altura e respiro de desktop: botão de 36px, 14px nas laterais, raio de 8px.
6. **Sombras discretas.** A sombra existe para dar profundidade às superfícies elevadas, não para decorar.
7. **Só uma coisa chama.** O laranja de `attention` com halo pulsante é o único sinal que disputa a atenção.

## Paleta grafite

| Camada | Token | Valor | Uso |
| --- | --- | --- | --- |
| Obsidian | `obsidian` | `#0D0F11` | Fundo do app: barra lateral, barra de título e abas, fundo do terminal |
| Graphite | `graphite` | `#15181B` | Superfície principal: canvas, chat, painéis de conteúdo |
| Carbon | `carbon` | `#1C2024` | Superfície elevada: inputs, cards, menus, popovers, diálogos, botão secundário |
| Steel | `steel` | `#252A30` | Superfície de hover: itens de lista, abas, botões fantasma, linhas de tabela |

- `steel-active` (`#2D333A`) é o pressionado e o trilho de toggles e sliders.
- Os fios são `line-subtle`, `line` e `line-strong`, do mais leve ao mais forte.
- A borda de input fica abaixo de 3:1 de propósito, para a tela ficar calma; o campo também se distingue pelo fundo `carbon` e pelo rótulo.

## Acento azul

| Tom | Token | Valor | Uso |
| --- | --- | --- | --- |
| Primary | `primary` | `#3f6d98` | Botão primário: azul-aço sólido com texto branco (5.4:1) |
| Accent | `accent` | `#a4c2dc` | Anel de foco, controles ligados (toggle, checkbox, slider), links |
| Accent soft | `accent-soft` | azul a 10% | Fundo da seleção: aba, item da barra lateral, ferramenta ativa |

- `primary-hover` (`#4776a1`) e `primary-pressed` (`#396791`) completam o botão.
- **Um primário por região.** Se uma tela tem três botões azuis, dois deles são secundários.

## Cores de tipografia

| Papel | Token | Valor | Uso |
| --- | --- | --- | --- |
| Primary | `text-primary` | `#E8E8E6` | Conteúdo e rótulos principais (≥ 11.7:1 em todas as superfícies) |
| Secondary | `text-secondary` | `#92999F` | Rótulos, ícones e metadados que precisam ser lidos (≥ 5:1) |
| Muted | `text-muted` | `#626A72` | Placeholders, hora, atalhos, fases zeradas |

`text-muted` vem da paleta original e fica em 3.25:1 sobre graphite, abaixo dos 4.5:1 recomendados para texto. Use-o só no que o usuário não precisa ler para agir. Endereços, custos e tempos que importam vão em `text-secondary`. `text-disabled` (`#4A5058`) é só para controles desabilitados.

## Distribuição visual das cores

Uma proporção de presença na tela, não uma regra de pixels:

| Camada | Presença |
| --- | --- |
| Graphite / superfícies | ~65% |
| Carbon / superfícies elevadas | ~20% |
| Textos e elementos neutros | ~12% |
| Azul / acento e primário | ~3% |

As cores de estado e de identidade dos agentes ficam dentro dos 12% de elementos pequenos: dots, glifos, nomes, contadores.

## Estados do agente

Cada estado tem cor e forma, para nunca depender só da cor:

| Estado | Token | Forma |
| --- | --- | --- |
| Precisa de você (permissão, pergunta) | `attention` (laranja) | dot com halo pulsante, contador, mão no cronômetro |
| Trabalhando | `running` | spinner |
| Terminou | `success` | dot verde ou check; some quando você entra na bancada |
| Em segundo plano / aguardando vizinho | `waiting` | ampulheta |
| Tentando de novo (erro de API) | `text-secondary` | ⟳ com a hora e a tentativa (2/3) |
| Falhou | `danger` | dot vermelho, octógono no cronômetro |
| Parado / encerrado | `text-disabled` / `line-strong` | dot vazado |

- "Precisa de você" é laranja, como no app e no site.
- Só agente de IA chama. Shell mostra o spinner e nada mais, e uma cadeia entre agentes não chama você.

## Identidade dos agentes

Doze cores, de `id-sky` a `id-moss`, com a mesma luminosidade e o mesmo croma (oklch L 0.74, C 0.075).

- A identidade de um agente ou de uma bancada é **o nome escrito na cor dele** (`AgentName`), e nada mais. Dot redondo é sempre estado.
- A bancada usa a mesma paleta, no traço de 2px da aba ativa e no nome quando ela está selecionada.
- A escolha automática segue a ordem de `identities`. `rose`, `clay` e `moss` (as mais próximas de erro, atenção e terminou) ficam para escolha manual.

## Código e terminal

- O terminal usa `term-bg` (obsidian) dentro da superfície graphite, para afundar, e a paleta ANSI `term-*`. A seleção é azul translúcido.
- `syn-*` realça a sintaxe (comentários em itálico).
- `diff-*` pinta os diffs: fundo de linha, fundo de palavra e cor do sinal.

## Tipografia

- **Noto Sans** na interface: humanista, de aberturas largas, calma e sem enfeite. Em tela, humanistas são lidas mais rápido que grotescas.
- **JetBrains Mono** no terminal, no código e nos números.
- `body` (14/22) e `label` (14/20, 500) no dia a dia; `heading` (15/22, 600), `title` (20/28), `display` (28/34) só em estados vazios e totais.
- `small` (13/18), `caption` (12/16, 500), `terminal` (14/20), `code` (13/20) e `mono-meta` (12/16), sempre com algarismos tabulares.

## Espaço, tamanho e forma

- **Grade de 4px.** O respiro é de 12 nos campos, 14 a 16 nos botões e listas, 20 nos popovers e 24 nos diálogos.
- **Controles:** 36px (`size-control-md`); `sm` tem 30 e `lg` 42. Linhas de 32 (`size-row`), barra de abas de 40 e barra de título de 44.
- **Raios:** 4 (checkbox), 6 (badges, abas, itens), 8 (botões, inputs), 12 (menus, popovers, código), 14 (diálogos e barra flutuante), e redondo só para dots.
- **Sombras:**
  - `shadow-raised` (0 1px 2px) para superfícies carbon fixas;
  - `shadow-float` para o que flutua;
  - `shadow-modal` para diálogos.
  - Superfícies graphite não têm sombra.

## Vidro

O que flutua sobre o canvas e o chat é de vidro: a barra de ações, o painel de consumo, os menus e os popovers.

- Fundo `glass` (obsidian a 62%) sobre desfoque gaussiano `blur-glass` (20px) com saturação a 130%.
- Borda de 1px em `glass-border` e um fio de luz `glass-highlight` no topo interno; sombra `shadow-glass`.
- Raio 14 na barra e nos painéis, 12 nos menus e popovers.
- Só no que flutua. Superfícies fixas (barra lateral, cards, diálogos) continuam sólidas.

## Estados de interação

| Estado | Como aparece |
| --- | --- |
| Hover | fundo `steel`, o texto sobe um degrau; revela ações ocultas |
| Pressionado | fundo `steel-active` e o botão afunda 2%; o primário vai a `primary-pressed` |
| Foco (teclado) | anel de 2px em `accent` colado ao controle, sem vão; no primário, o anel é claro |
| Selecionado | fundo `accent-soft` |
| Desabilitado | campos e texto em `text-disabled`; botões a 40% de opacidade |
| Carregando | spinner no lugar do ícone; o controle não muda de tamanho |
| Erro | borda e mensagem em `danger`; a mensagem diz o que fazer |

## Movimento

- 80ms para hover, 140ms para menus, abas e toggles, 200ms para diálogos e para a troca Canvas | Chat.
- Animação contínua só no spinner e no halo de atenção.
- Com "reduzir movimento" ligado, as transições viram troca direta.

## Vocabulário do produto

- **workspace → projeto → bancada**; **nó** (terminal, agente, navegador, fila de prompts).
- **endereço** `bancada/id` (ex.: `loja/front`); **aresta** (quem aciona quem, e quantas vezes).
- **maestro**, **trilha**, **worktree**.
- **Canvas | Chat** (⌥⌘1 / ⌥⌘2) e **processos** (⌥⌘P).

## Iconografia

Ícones de linha em grade de 16px, traço de 1.5px, na cor do texto. O cronômetro usa martelo (trabalhando), mão (esperando você) e octógono (erro). Sem emoji, sem sparkles, sem ilustração. Botão só ícone sempre tem tooltip.

## Marca

O ícone do app mora em `design/brand` e pode ser refeito sem mexer em nada daqui: a paleta é definida pelos tokens, não pelo ícone. O nome se escreve "Egeon", em Noto Sans 600.

## Escrita

- Português do Brasil, caixa de frase. Botões com verbo no infinitivo; permissão sempre **Permitir · Sempre · Negar**.
- Dinheiro em `US$ 1,19`, tempo em `mm:ss`, tokens abreviados (`14,1K`).
- Erro em uma frase: o que aconteceu e o que fazer.
