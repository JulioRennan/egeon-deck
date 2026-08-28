# Modo Chat do Egeon Deck — prompt de design

Você vai desenhar o **modo chat** do Egeon Deck, um app macOS. Junto com este
texto vai um print do modo canvas atual do app: é dele que sai a linguagem
visual — respeite-a. Sua tarefa é desenhar a tela do chat, não implementá-la.
Tudo o que você precisa está neste documento.

## Contexto do produto

- Egeon Deck é um app macOS pessoal para dirigir vários agentes de IA em
  paralelo.
- **Bancada** (workbench) é uma frente de trabalho: uma pasta + nós abertos
  sobre ela (terminal, agente de IA, editor, web).
- Cada agente vive num terminal endereçável (`bancada/id`, ex. `deck/revisor`),
  tem um papel (prompt de sistema), uma cor própria e uma conversa (transcript
  gravado pelo CLI).
- Agentes conversam entre si quando há uma aresta ligando os dois — o front
  pode pedir algo ao back e receber a resposta dentro do próprio fluxo.
- A bancada tem visualizações intercambiáveis: canvas (cards livres), mosaico
  (janela dividida) e o chat desta spec — ⌥⌘1/2/3. Mesmo conteúdo, jeitos
  diferentes de olhar.

## Linguagem visual atual (ver print do canvas)

- Tema escuro: fundo quase-preto azulado com grid sutil de linhas.
- Barra superior: nome da bancada em branco bold + caminho em monospace
  acinzentado; seletor de modo em pill central, item ativo em azul.
- Cards de nó: cantos arredondados, borda de 1px na COR do agente; cabeçalho
  escuro com "✦ nome" na cor do agente e caminho em monospace; ícones de ação
  à direita.
- Painéis flutuantes em vidro claro (sidebar, toolbar) sobre o fundo escuro.
- A cor do agente é identidade: borda do card, nome no cabeçalho. No chat ela
  deve continuar sendo o fio condutor de quem é quem.

## Conceito

A bancada vista como um **grupo de WhatsApp**: os agentes são os
participantes, o usuário dirige a conversa. Sem cards e sem terminal na tela —
os terminais continuam rodando por trás; o chat lê as conversas e envia
prompts.

## Layout — três regiões

1. **Coluna esquerda — participantes.** Abaixo do cabeçalho da bancada, a
   lista dos agentes envolvidos no workbench. Cada linha: cor + nome (id do
   nó), papel resumido e estado atual. Clicar numa linha foca o composer
   naquele agente.
2. **Centro — a conversa.** Thread única, cronológica, mesclando as conversas
   de todos os agentes. Bolhas de mensagem: usuário à direita, agentes à
   esquerda, cada agente na sua cor.
3. **Rodapé — composer.** Campo de texto multiline + indicação clara de PARA
   QUEM estou falando agora (o foco). Nesta versão a mensagem vai SEMPRE para
   um único agente: um controle de alternância troca o destinatário
   rapidamente (clique no participante ou Tab no composer), e o foco atual
   fica sempre visível junto do campo, na cor do agente. Enter envia (injeta
   o prompt no terminal do agente). Multi-destinatário fica para depois —
   não desenhar.

## Anatomia da bolha do agente — o coração da spec

Uma resposta de agente não é texto plano: é a resposta final + o caminho até
ela.

1. **Cabeçalho:** nome do agente na cor dele + horário.
2. **Citação**, quando as regras de reply abaixo pedirem.
3. **Stack de passos (colapsável):** os passos que o agente tomou — comandos,
   edições de arquivo (com +adições/−remoções), chamadas de ferramenta.
   Fechado por padrão com um resumo ("n passos"); expande inline dentro da
   bolha.
4. **Sub-conversas aninhadas:** se o agente falou com OUTRO agente no meio do
   trabalho (front pediu algo ao back), a resposta do back aparece DENTRO da
   bolha do front, como bolha aninhada na cor do back, no ponto do stack em
   que aconteceu. Encadeia recursivamente: se o back falou com um terceiro,
   aninha de novo. Objetivo: ler a resposta do front para mim e ver ali
   dentro o que o back respondeu a ele, sem trocar de tela.
5. **Corpo final:** a resposta em si — prosa, blocos de código, diffs.

Implementado (ADR-039): stack e corpo não são dois blocos — a bolha desenha a
**cadeia** na ordem em que saiu (parágrafo, grupo de passos fechado, parágrafo…),
e enquanto o turno corre ela cresce ao vivo, com o que o agente está fazendo
agora numa linha de status no fim (`⠋ $ Roda os testes`, `⠋ pensando…`).

**Superado (ADR-042): o item 4 não existe mais.** A linha do tempo é plana,
como num grupo do WhatsApp: a mensagem do front para o back é uma bolha do
front ("✦ front" em cima, na cor do front, à esquerda), e a resposta do back é
uma bolha do back. Nada aninha. A marca é só o `@destinatário` no começo do
texto — e só quando a mensagem não é contínua (consecutivo é limpo,
intercalado é marcado). Sem seta. A thread é um `NSTableView` com uma linha
por bloco da cadeia.

## Regras de reply — não misturar conversas

- **Caso 1 — um agente só, fluxo linear:** meu prompt, resposta dele logo
  abaixo, uma coisa embaixo da outra. Sem citação nenhuma.
- **Caso 2 — dois ou mais agentes intercalados:** quando a resposta NÃO vem
  imediatamente após o prompt dela, a bolha carrega uma citação estilo
  WhatsApp no topo: mini-card com o trecho do prompt a que ela responde e
  quem perguntou. Clicar na citação rola até a mensagem original. O mesmo
  mecanismo marca meus prompts quando dois papos correm ao mesmo tempo.
- Regra geral: **consecutivo = limpo; intercalado = citado.**

## Estados do agente (já existem no app; o chat os mostra)

- **Trabalhando:** indicador de "digitando…" na thread + spinner na linha do
  participante.
- **Atenção (laranja):** o agente parou esperando permissão ou resposta — o
  estado que interrompe. Precisa gritar na lista e na thread.
- **Terminou (verde):** só informa, discreto.
- **Morto:** terminal fechado — participante acinzentado.

## O que o design NÃO precisa resolver

- Terminal embutido na thread — não existe; o chat é leitura + envio.
- Multi-destinatário: nesta versão eu falo com um agente por vez, sempre. O
  gerenciamento de mandar para vários vem depois e não entra no desenho.
- Edição de mensagem, reações, busca.
- Multi-bancada: o chat é sempre de UMA bancada.

## Questões em aberto — decida no design e proponha

1. Stack fechado: só o contador ("7 passos") ou preview dos últimos 3?
2. Aninhamento fundo (3+ níveis): renderizar tudo inline ou cortar em "ver
   cadeia completa"?
3. Shells não-agente entram na lista de participantes (dá para mandar
   comando)? Editor e web ficam fora?
4. A citação mostra quanto do prompt original?
5. Coluna de participantes: vidro claro como a sidebar do canvas, ou escura
   integrada à thread?

## O que eu espero de você

A tela do modo chat em alta fidelidade, no tema escuro do print, com dados de
exemplo realistas. Cubra os dois casos de reply:

1. **Conversa 1:1** — eu e um agente, prompts e respostas empilhados, sem
   citação.
2. **Dois agentes intercalados** — citações marcando quem responde o quê, e
   pelo menos uma bolha de agente com o stack de passos expandido contendo
   uma sub-conversa aninhada (ex.: `front` mostrando dentro dela a resposta
   do `back`).

Mostre também o composer nos dois momentos: focado num agente e trocando de
destinatário. Onde este documento deixa questão em aberto, escolha e mostre a
escolha no desenho.
