# 05 · node — cards de agente, shell, fila e web

> Módulo: `ui/lib/features/node` (`card/`, `agent/`, `terminal/`, `queue/`,
> `web/`). Os widgets de apresentação saem; cubits, repositórios, o terminal
> (pintor, métricas, teclado) e o comportamento do porte ficam. Referência:
> **Nós — agente** (`Nos-A-maestro.dc.html`, `Nos-Shell.dc.html`) e os cards
> da v3 (tela `V3-canvas-padrao` do canvas da v3).

Pré-requisitos: E1, E4 (superfície onde o card mora).

## N1 · Moldura do card

- **O quê:** fundo `graphite`, raio 10 (a referência vence: todos os cards do
  canvas são #15181B r10); corpo do terminal em `termBg`. Estados da moldura:
  - **precisa de você:** borda `attention` a 70%, anel de 3px `attentionSoft`,
    sombra maior;
  - **maestro:** faixa na cor dele no topo, cabeçalho tingido, borda na cor a
    90%, anel de 4px e brilho mais fortes, card um pouco maior;
  - arrastado: `shadow.drag`.
- **Pronto quando:** os três estados se distinguem sem depender só da cor.

## N2 · Cabeçalho do agente

- **O quê:** dot de estado (Trabalhando `running` com spinner, Precisa de você
  `attention` pulsando, Concluído `success`, Parado `textDisabled`, Erro
  `danger`) · nome na cor de identidade (`AgentName`) · etiqueta **maestro**
  (tooltip "monta o time, define quem fala com quem e aprova as permissões") ·
  caminho curto `~/…/a/b` (tooltip com o completo) · ações no hover: Rodar
  numa worktree, Editar papel e regras, Fechar.

## N3 · Linha de controles do agente

- **O quê:** pastilhas clicáveis **modelo** · **esforço** · **auto** ·
  **ultracode** · **contexto N%** (+ limpar).
  - **Modelo:** menu com padrão (o da bancada), e os modelos do CLI com
    descrição curta; check no atual; nota "Trocar retoma a conversa no novo modelo."
  - **Esforço:** barras crescentes (baixo, médio, alto, máximo) + nota "Mais
    esforço pensa mais antes de agir e gasta mais."
  - **auto / ultracode:** toggles (auto = shift+tab).
  - **Contexto:** `ContextRing` (accent; `attention` a partir de 80%), popover
    com "Nk de 200k tokens", "Compacta sozinho perto de 90%." e "Limpar
    contexto…" → `Dialog` "Limpar o contexto de <nome>?" / "A conversa recomeça
    do zero com o mesmo papel e regras. A trilha da bancada continua." · Cancelar · Limpar.
- **Depende do core?** lista de modelos/esforços por CLI (vem do `egeon models`
  do core?), ultracode, % de contexto e limpar: verificar o que o socket entrega.

## N4 · Card de shell

- **O quê:** mesmo cabeçalho, neutro: ícone de terminal no lugar da cor, sem
  linha de controles; estado no pontinho do ícone; ações Editar nome e comando,
  Recarregar (reinicia e roda o comando configurado), Fechar.

## N5 · Terminal

- **O quê:** o terminal usa a paleta nova (`egeon_terminal_palette`), fonte
  JetBrains Mono 14/20, seleção `termSelection`, cursor `termCursor`. O pintor
  e o teclado não mudam.
- **Pronto quando:** o terminal antigo deixa de ler o `terminal_palette` velho.

## N6 · Fila de prompts

- **O quê:** card "Fila de prompts para <agente> · N de M", itens com estado
  (em trabalho com spinner), fechar; painel lateral da fila no visual novo.

## N7 · Web

- **O quê:** cabeçalho no padrão N2/N4 e o campo de endereço com `TextField`.

## Some daqui

Os widgets de `card/`, `agent/` (`agent_strip`, `effort_dial`,
`context_indicator`, `agent_accessory`), `queue/` e `web/` com o visual antigo.
