# Egeon Deck

App macOS de uso pessoal: um **canvas infinito onde cada nó é uma ferramenta de
trabalho real** — editor de código, terminal comum, terminal rodando um agente de
IA, navegador. Você monta a bancada uma vez por projeto e ela fica em pé.

O ponto não é "mais um workspace manager". É **dirigir vários agentes de IA em
paralelo sem perder o fio**: cada agente vive num terminal endereçável, recebe
prompt por injeção programática, e avisa quando parou e precisa de você.

Uso pessoal, um usuário, macOS. Não há multiusuário, telemetria, nem plano de
distribuição.

---

## Como está montado

```
app/          executável Swift (SPM) empacotado em EgeonDeck.app
extension/    extensão do VSCode/code-server — review inline de markdown
docs/         00-prior-art · 01-decisoes (ADRs) · 02-mvp
poc/          protótipos descartados
```

`app/Sources/EgeonDeck/`, por responsabilidade:

| arquivo | o que é |
|---|---|
| `main.swift` | `AppDelegate`, menu, ciclo de vida, criação/edição de sessão, worktree, laço de UI |
| `Session.swift` | modelos `SessionConfig` / `NodeConfig`, persistência, `AppControl` |
| `Canvas.swift` | `NodeView` (card base), `TerminalNode`, `CanvasContainer` (pan/zoom/grid), `MBTerminalView` |
| `SessionShell.swift` | a sessão na tela: barra superior de visualização e o dono dos nós |
| `Mosaic.swift` | o modo mosaico — `ViewMode`, `MosaicLayout` e o split view com mínimo por painel |
| `Chat.swift` | o modo chat por dentro — `AgentColor`, `ChatNode` e a junção dos transcripts |
| `Transcript.swift` | leitor do JSONL do CLI: mensagem, bloco de código, diff |
| `ChatView.swift` | o thread — vocabulário visual, chip de agente e as linhas |
| `ChatComposer.swift` | a caixa de escrever: destinatário, Tab, `@` e a lista de menção |
| `ChatPanel.swift` | "na sessão" — agentes, processos e a gaveta de saída |
| `ChatContainer.swift` | o modo montado: thread, caixa, painel e o laço de leitura |
| `Dispatcher.swift` | `Target` (o terminal endereçável) e `Dispatcher` — fila, injeção, ociosidade, estado, cadeia |
| `Attention.swift` | `Activity`, `Spinner`, `AttentionSound` — vocabulário de "carregando / precisa de você" |
| `Edge.swift` | `EdgeConfig`, traçado das ligações (`EdgeCurve`, `EdgeLayerView`) e a porta `+` do card |
| `AgentProfile.swift` | perfis de agente e `agents.json` |
| `ControlSocket.swift` | socket unix de controle |
| `Editor.swift` / `CodeServer.swift` | nó de editor (WKWebView) e o processo do code-server |
| `WebNode.swift` | nó de navegador, com perfil de navegação isolado |
| `Sidebar.swift` / `Toolbar.swift` | lista de sessões e barra de ferramentas do canvas |
| `Glass.swift` | `GlassPanel` — o vidro das barras flutuantes, e o interruptor dele |
| `Drop.swift` | arrastar arquivo para o terminal: o que o arrasto trouxe, virado em caminho |
| `Component.swift` / `Template.swift` | presets de nó e de sessão |
| `Worktree.swift` | criar worktree do git e abrir sessão nela |
| `NodeWorktree.swift` | worktree por terminal: o plano de cada nó e a lista do formulário |
| `Environment.swift` | PATH e env dos processos filhos |
| `Flavor.swift` | estável vs dev: diretório de config, log, socket, porta |
| `AgentHooks.swift` | gancho que faz o CLI relatar qual conversa está aberta |
| `Peer.swift` | quem está do outro lado do socket, pelo pid do processo |
| `EgeonCLI.swift` | o comando `egeon`, que o agente usa para achar e acionar vizinhos |

## Conceitos

**Sessão** — uma frente de trabalho: uma pasta e os nós abertos sobre ela. Duas
sessões podem apontar para o mesmo repositório em worktrees diferentes. O nome é
único porque é a primeira parte do endereço de dispatch.

**Nó** — um card no canvas. Quatro tipos: `editor` (code-server em WKWebView),
`shell` (terminal comum), `agent` (shell rodando um agente CLI) e `web`.

**Endereço de dispatch** — `sessão/id`, ex. `deck/revisor`. Estável: independe de
título de janela, posição na tela ou ordem. `shell` e `agent` são endereçáveis.

**Conversa** — cada nó `agent` tem um `conversationId` próprio, gerado na primeira
subida, que sobrevive ao rebuild. O CLI chama isso de sessão; aqui não, porque "sessão"
já é a frente de trabalho e já era o terminal endereçável do Dispatcher — que agora é
`Target` (ADR-030). Arquivo gravado antes disso trazia `sessionId`, e é absorvido na
carga. Ao lado dele mora o `transcript`, o caminho do JSONL
que o CLI grava — é dele que o modo chat monta o thread (ADR-029). Se você trocar de conversa dentro da TUI
(`/resume`, `/clear`, fork), o CLI avisa o app por um gancho `UserPromptSubmit` e o
`sessionId` acompanha. Ver ADR-014.

**Componente** — preset de nó (agente, comando, pasta, papel). **Template** —
preset de sessão inteira. Os dois copiam valores no momento da criação; editar o
preset depois não mexe em quem já nasceu — por isso a barra tem duas ações
separadas, "salvar como template" (cria) e "atualizar template" (regrava o de
origem, e só aparece quando existe um).

Copiar um nó — por template ou duplicando a sessão numa worktree — copia a
montagem e **nunca a conversa**: `NodeConfig.withoutConversation` zera o
`conversationId`. Com ele junto, duas sessões apontam para a mesma conversa e a
segunda a subir não consegue abri-la — o card fica com a TUI desenhada e o
processo morto, sem erro à vista. Duplicar para worktree leva também as arestas e
o `maxVisits`: a rede é parte da montagem.

**Aresta** — ligação entre dois terminais: `from` **pode acionar** `to`. Desenhada
arrastando a porta `+` de um card até outro. Não é um cano — o agente descobre o
endereço com `egeon peers` e decide quando usar. Ver ADR-012.

Por baixo cada sentido é uma aresta dirigida, e continua sendo: é o que faz o ciclo
de dois e o de três serem o mesmo mecanismo. **Na tela o par é uma linha só**, com
ponta em cada extremidade que tem sentido — `───▶`, `◀───` ou `◀───▶` —, e é ali
que se lê a direção. Ligação nova **nasce nos dois sentidos**; o botão no meio da
linha cicla ida → ida e volta → volta, e o X ao lado leva os dois. Ver ADR-028.

## Worktree

Uma frente de trabalho raramente é um repositório só: o card do frontend abre no
repo da sessão, e o do backend abre num repo vizinho. Então a worktree é **por
sessão e por terminal**.

Duplicar a sessão para worktree abre um formulário que lista **todos os
terminais** com o repositório de cada um. No topo, a branch da sessão; mudá-la
re-sugere o nome para as linhas que você não editou à mão.

Na linha de cada terminal só existe **a branch**, e é ela que decide: igual à da
sessão, ele vai junto pelo `cwd` relativo; outra branch, ele ganha worktree própria
no repositório dele; em branco, fica no repositório original. Vale para shell,
agente e editor sem distinção — quem abre pasta está na lista. Terminal dentro do
repo da sessão com branch própria ganha worktree própria do mesmo repo: é a tarefa
no front que precisa de um ajuste no back. **Não há campo de pasta** — ela sai da
branch pela convenção de sempre e aparece como texto, para conferir. Ver ADR-020.

O ícone de ramificação no cabeçalho de um terminal — ou o botão direito nele — leva
**só ele** para uma worktree, fora de qualquer duplicação. O card é reapontado, não clonado: id, papel, arestas e
posição continuam; o processo reinicia, porque não há como trocar o diretório de
um pty em curso, e a conversa é zerada porque era da pasta antiga.

Remover a sessão oferece apagar **todas** as worktrees dela — a da sessão e a de
cada terminal que abre fora dela —, numa caixinha só, listando repositório · branch
· quem usa. Worktree que é pasta de outra sessão fica, marcada como MANTIDA: apagar
levaria trabalho de quem não foi consultado. Falha em qualquer uma e a sessão não
sai da lista. Ver ADR-021.

A worktree nasce em `<pai do repo>/worktrees/<repo>/<branch>` — fora do
repositório, agrupada por repositório, e **sem ponto no nome**: o Finder esconde
pasta que começa com ponto, e esta é pasta que se abre à mão (ADR-022).

Dois terminais no mesmo repo vizinho com o mesmo nome de branch dividem uma
worktree; com nomes diferentes, viram duas. A worktree sai **sempre do checkout
principal** (`Worktree.mainRepo`), nunca de uma worktree ligada — partir dela
aninha worktree dentro de worktree, e apagar a de fora leva a de dentro.

O `cwd` de um nó aceita três formas, e todas têm motivo: relativo (o caso normal,
é o que faz o nó valer em qualquer checkout), absoluto (repo vizinho, que não tem
equivalente dentro da worktree) e relativo saindo da raiz com `..` — este último
é onde mora a armadilha, porque o mesmo texto significa pastas diferentes em
checkouts diferentes. `cwd` que não resolve cai na raiz da sessão **falando**: log
e banner. Ver ADR-017, que registra o dia que o silêncio custou.

O nome de branch que você escreve vale como escrito, e é ele que decide o que
acontece: branch que não existe nasce do HEAD da origem; branch que já existe
local abre **nela**, no commit dela; branch que só existe no remoto nasce
seguindo a ref; branch já aberta em outra worktree não cria nada — é aquela
pasta. Worktree reaproveitada não recebe a cópia do `.gitignore` (`.env`,
`node_modules`), e o stash das mudanças não commitadas só vai junto quando a
branch nasce agora. O formulário diz qual dos quatro casos é, a cada tecla. Ver
ADR-018.

## Visualização

Três maneiras de olhar a mesma sessão, na barra de cima (⌥⌘1 / ⌥⌘2 / ⌥⌘3):

**Canvas** — a bancada livre: posição, tamanho, zoom, arestas desenhadas.
**Mosaico** — os mesmos nós dividindo a janela inteira, sem sobreposição e sem
zoom. Colunas empilhadas, divisores arrastáveis, coluna sem nó não aparece.
**Chat** — a sessão como conversa, sem card nenhum. Ver a seção abaixo.

No mosaico o arranjo é seu: **arraste o cabeçalho de um card sobre outro e os dois
trocam de painel**, em qualquer direção, inclusive entre colunas. O painel que vai
receber acende antes de você soltar. Quem nunca arrastou nada vê o arranjo por tipo
— editor · terminais · web, na ordem do `sessions.json` —, e é dele que o resto
parte. O que você montou vive em `mosaic.slots`, ids de nó por coluna; nó criado
depois entra na coluna de quem é do mesmo tipo, sem desfazer o resto. Ver ADR-023.

**Não são cópias do nó.** Em qualquer modo o card é o MESMO `NodeView`, e o
que muda é quem lhe dá o frame. Reparentar uma view não toca no processo — o pty
segue ligado ao SwiftTerm e o WKWebView não recarrega —, então dá para trocar de
modo com cinco agentes trabalhando. É por isso que o dono dos nós é o
`SessionShell` e não o canvas: com dois containers disputando o mesmo card, a
lista tem de viver acima dos dois.

O que o mosaico desliga no card, por `NodeView.isFreeform`: arrasto pelo
cabeçalho, alça de resize e porta de aresta. Ali quem dá a posição é o split view,
e o arrasto chamaria `onRequestSpace`, que desloca o mundo do canvas.

Modo e proporções são **por sessão**, gravados no `sessions.json` (`view`,
`mosaic`) e copiados por template e por duplicação em worktree. A geometria dos
nós no arquivo continua sendo sempre a do canvas: `syncFrames` só roda em canvas,
senão a montagem inteira seria regravada com o tamanho dos painéis.

Ver ADR-016.

## Modo chat

Canvas e mosaico mostram a **montagem**. Com cinco agentes ela é a parte que já está
pronta, e o que falta é o **fio**: o que aconteceu, e em que ordem. Cada card só sabe
do próprio turno, então esse fio não está em nenhum deles.

O chat é um thread por sessão. Ele sai do **transcript JSONL que o CLI grava** — o
caminho vem no payload do gancho (`transcript_path`) e fica em `NodeConfig.transcript`,
ao lado do `sessionId`. A tela do terminal não serve para isso: ela é TUI e mente
(ADR-011). Como o thread é remontado dos arquivos, ele **volta inteiro no arranque
seguinte** e o app não guarda mensagem nenhuma.

A unidade do thread é o **turno**, não a mensagem: um bloco por pedido, com tudo o que
o agente fez a respeito dentro dele. Mensagem solta ordenada por tempo intercala duas
conversas, e a resposta do A cai no meio da sua terceira pergunta ao B — a análise de
conversa chama isso de **cisma de piso**, e quem está num piso não se orienta pela
troca de turnos do outro. O bloco não cinde.

Dentro do bloco, **bolha dentro de bolha**: seu pedido, o **caminho** dobrado no meio
(`▸ 12 passos · 3 arquivos`), e a **resposta**. Todas as bolhas encostam à esquerda e
levam **o nome de quem falou dentro delas**, como mensagem de grupo no WhatsApp —
`você`, `claude`, ou o par `claude → claude-2` quando a fala é entre agentes. Cada nome
na cor do agente; `você` em branco, porque você não é um nó da sessão.

O lado dizia quem falava enquanto eram duas pontas; com a cadeia entre agentes no mesmo
cartão passaram a ser quatro, e aí `claude → claude-2` e `claude-2 → claude` caíam no
mesmo lado e se confundiam. Com o nome dentro, a bolha se explica sozinha.

O caminho nasce dobrado: turno de trinta ferramentas viraria um cartão que não cabe na
tela. O corte da resposta é na prosa FINAL do turno, e não na primeira, porque o agente
narra enquanto trabalha e narração é caminho.

O thread **gruda no fim** até você rolar para cima, e volta a grudar quando você volta.
Não dá para resolver rolando depois de montar: a primeira medida acontece com a largura
ainda em zero, e a posição calculada ali não vale quando o layout de verdade chega — o
último bloco ficava cortado na borda de baixo.

**Turno acionado por outro agente não é bloco de primeiro nível** — ele entra **no mesmo
cartão** e usa a MESMA bolha. Nem seta de aninhamento, nem recuo, nem caixa própria:
recuar cada volta fazia três voltas virarem uma escada dentro do cartão, e o desenho
passava a falar da topologia em vez da conversa.

No título, **direção só onde houve entrega**. O app monta o envelope de toda entrega,
então de um PEDIDO ele sabe as duas pontas — `você → claude`, `claude → claude-2`. De uma
RESPOSTA ele sabe só quem falou: o turno acabar não quer dizer que o agente devolveu algo
a quem o acionou. Se devolveu, aquilo é outra entrega e aparece como o pedido da fala
seguinte.

Sem o destinatário no pedido, uma cadeia de três não diz quem estava falando com quem:
`claude-2` sozinho não conta se ele foi acionado pelo `claude` ou pelo `qa`.

**O contraste diz a hierarquia**, e com tudo alinhado é ele que faz esse trabalho. A
resposta final para você é a superfície mais clara do cartão, com um fio na cor do
agente; o seu pedido fica um degrau abaixo; e o que os agentes trocaram entre si recua
para quase preto. Sem essa escada, a resposta que o
agente te deu e a que ele deu ao vizinho pesavam igual, e achar a conclusão num cartão
com cadeia exigia ler tudo. A letra segue clara nas três — o que muda é o quanto a bolha
chama.

E a regra da dobra é uma só, em todo nível: **resposta sempre à vista, só o caminho
dobra**. Cada fala da cadeia tem a própria linha `▸ N passos`. Dobrar a fala inteira
escondia exatamente o que faltava saber — o agente dizia "perguntei ao vizinho quanto é
7 vezes 6" e a resposta dele ficava atrás do clique.

A ligação é pelo remetente e pelo tempo, não pelo texto: o envelope diz quem falou, e um
agente só pode ter acionado alguém durante um turno dele que já tinha começado. É
recursivo, então a volta de B para A é mais uma dobra dentro da primeira — o ciclo de
dois se desenha com o mesmo mecanismo do de três. Solto na linha do tempo, esse
trabalho afogava a conversa que você pediu.

Quem lê o transcript é um **adapter por CLI** (`ChatAdapter`), escolhido pela chave do
`agents.json`. Hoje só `claude` tem um; os outros não rendem thread, e o vazio diz
isso. O formato é de cada um, e sem esta costura o modo inteiro ficaria preso a um
programa.

O que aparece: sua pergunta com os destinatários; a prosa do agente; `Edit` e `Write`
como diff com `+n −m`; `Bash` como o comando; o resto como uma linha (`leu
Canvas.swift`). O que não aparece, e cada um por um motivo: `thinking` é rascunho,
`tool_result` não é ninguém falando, subagente é trabalho interno, e o marcador
`[[ED:ok]]` é conversa do app com o app.

**Enquanto o turno corre, o chat não fica mudo.** O bloco do que você mandou entra na
hora, apagado, com `entregando…` — ele sai quando o de verdade volta do transcript, ou
por tempo se nunca voltar. E o cabeçalho do bloco aberto ganha três pontos pulsando e
**o que ele está fazendo agora**: `pensando`, `lendo
Canvas.swift`, `$ npx vitest`. Esse detalhe é o `live` do adapter, e é o que separa
isto de um spinner — ele diz que o trabalho ANDOU desde a última vez que você olhou.
O raciocínio entra aqui e não no histórico: lá é rascunho longo, aqui é a única coisa
que existe para mostrar.

**Agente falando com agente vira uma linha recolhida no meio do thread**, `A → B`, que
abre no que foi dito. O app não grava esse tráfego: uma entrada que começa com
`[egeon] mensagem de <endereço>` é entrega de aresta, e o envelope é montado por ele
em `DispatchRequest.agentEnvelope` — então é o app quem diz quem falou, não o texto.

A **mesma frase entregue a vários** volta como uma mensagem só com vários
destinatários: um envio para `todos` é gravado em cada transcript, e sem juntar sua
pergunta apareceria três vezes seguidas.

Na caixa de escrever o destinatário está na tela porque aqui ele não é implícito:
**Tab cicla**, `@` oferece quem existe, Enter envia, Shift+Enter quebra linha. Ela
nasce com **duas linhas** — vazia com uma só ela parece campo de busca, e o que se
escreve aqui é prompt —, é **ancorada embaixo e cresce para cima** até seis linhas, e
daí em diante rola por dentro. Quem cede área é o **histórico**: o thread termina onde
a caixa começa. O teto é o menor entre seis linhas e 38% da altura útil, sempre em
linhas inteiras.

Quem pede o frame novo é a caixa, e ela compara a altura que quer com a altura que
**está usando** — não com uma segunda medida do texto. Medir duas vezes depois da
tecla dá sempre igual, o container nunca era avisado, e o vidro crescia dentro do frame
de uma linha: passava da borda de baixo e a caixa parecia crescer para BAIXO.

**Clique em qualquer lugar da caixa põe o teclado no texto**, e clique no fundo do
thread também. O recuo, a linha do destinatário e a faixa do botão são `NSView` comum,
que não aceita foco: clicar ali não devolvia o teclado, e quem tivesse roubado
continuava com ele — daí "clico no chat e não consigo digitar", com o teclado num
terminal coberto pelo chat. Tecla que chega ao container, e não à caixa, é foco perdido
num rebuild: vai para a caixa em vez de virar beep. `/chat` devolve `focus` — quem tem o
teclado, se está dentro do chat e se a janela é key — porque ladrão de foco é invisível
na tela.

`POST /compose?target=ws[&send=1]` escreve na caixa — e com `send=1` aperta o Enter —
devolvendo a geometria. É a única forma de conferir de fora que ela cresce para cima,
para no teto e devolve a área ao histórico, porque tecla sintética exige
Acessibilidade (ADR-003). Clicar
num agente no painel da direita também aponta. Até você escolher, o padrão é o
primeiro agente — e é **re-derivado**, não fixado: os alvos entram no Dispatcher na
ordem em que os nós sobem, e fixar na primeira leitura grudava no terminal comum.

À direita, o que o canvas dava de graça e o chat esconderia: **agentes** com estado,
cor e os chips de `alcança` — as arestas, aqui só de leitura —, e **processos**, que
são os terminais comuns, com a saída numa gaveta. Cor de agente é derivada do id
(FNV-1a, estável entre execuções): o acento do card diz o TIPO, então dois agentes
teriam a mesma.

Pedido de permissão **não aparece no chat**. O aviso já existe e funciona: borda
laranja no card, som, bolinha na barra lateral (ADR-024). Um card aqui só saberia
apontar para o terminal, e aviso duplicado que não age é ruído.

E o **canvas continua montado por baixo**, coberto pelo chat opaco. Não é preguiça:
nó fora da hierarquia nunca recebe passe de layout, e sem layout o pty sobe com zero
colunas — sessão que abre em chat ficava com os terminais em branco para sempre.

Ver ADR-029.

## As barras

A barra de sessões é de vidro (`NSGlassEffectView`, macOS 26), e onde ela pousa
depende do modo: **no canvas flutua** sobre o grid, **fora dele fica ao lado** do
container — mosaico e chat.

As três superfícies do chat — painel da direita, caixa de escrever e gaveta de
processo — são o **mesmo `GlassPanel`**, com o mesmo raio, a mesma borda, o mesmo
recuo de 12pt e a mesma saída por `EGEON_GLASS=0`. Elas não pintam fundo próprio:
fundo no `contentView` deixa o vidro invisível, porque ele reamostra o que está
ATRÁS. O botão de recolher o painel é o `ToolbarButton` da barra de sessões, com os
mesmos símbolos espelhados — `sidebar.trailing` de um lado, `sidebar.leading` do
outro. A largura do painel é **cedida**; a da caixa, **não**: à direita haveria
mensagem coberta o tempo todo, e embaixo o thread já reserva a folga. A bancada do canvas tem sobra de espaço e a barra por cima dele é o efeito
desejado; no mosaico os cards dividem a janela inteira, e sobreposição ali é terminal
coberto. A barra do canvas e o banner de aviso usam o mesmo `GlassPanel`. A barra de
visualização, no topo, segue opaca e encostada.

No canvas o conteúdo **não cede nada**: o grid vai até a borda e corre por baixo do
vidro — é isso que faz a barra parecer flutuando. Reservar uma faixa ali pintava ela
com o fundo da `RootView`, cinza neutro 0.09, mais claro que o azulado do canvas: dava
uma moldura cinza em volta do vidro com cara de resto da barra antiga. No mosaico o
conteúdo cede a largura de verdade, e recolher devolve 180pt aos cards.

A barra de visualização faz o que a barra de título faria, porque é ela que ocupa
aquela faixa: **arrastar move a janela** e **duplo clique maximiza** — respeitando a
escolha em Ajustes › Área de Trabalho e Dock, que também pode ser minimizar ou nada.
Sem isso a faixa do topo do app era a única do sistema onde os dois gestos morriam. O
nome e o caminho da sessão saem do hit test para não roubar o clique: rótulo é
`NSControl` mesmo sem ser editável.

A barra começa abaixo da barra de visualização, que corre de borda a borda e é ela que
passa por baixo dos botões da janela — por isso o título dela recua quando a sessão
encosta na esquerda (`ViewToolbar.titleInset`, decidido pela posição e não pelo modo).

Recolher é **só sua escolha**: `⌘/` ou o botão no cabeçalho da barra. Nem o modo nem o
mouse passando por cima mexem nisso — barra fechada só abre por clique ou tecla, e
continua fechada até você dizer o contrário.

⌘/ é cedido quando o cursor está **dentro do editor** — lá a tecla comenta linha, e
key equivalent de menu é consultado antes do responder chain. No terminal ela não tem
dono, e ali a barra responde.

No trilho o `+` sai (menu saindo de uma faixa de 52pt cai sobre os cards) e as **bolinhas
continuam** — os três avisos em 10pt sob a pastilha, mais o aro da pastilha, onde
laranja de "te espera" vence o verde de "está de pé". O que a largura tira é o nome,
que vira a inicial: sessão inativa não desenha nada na tela, e essa linha é a única
pista que ela tem.

`EGEON_GLASS=0` volta as três para o fundo semiopaco, sem rebuild — vidro reamostra
o backdrop a cada quadro, e elas ficam por cima de cards que redesenham dez vezes
por segundo. O mesmo caminho é o fallback abaixo do macOS 26. Ver ADR-025.

## Ligações entre agentes

Um agente pergunta com quem pode falar e fala, pelo comando `egeon`:

```bash
egeon peers                     # quem este terminal pode acionar, agora
egeon send deck/revisor <<'MB' # corpo em texto puro
(o que você quer dizer)
MB
```

Perguntado em tempo de execução e não entregue no system prompt: a lista do
arranque congelava a topologia daquele instante, e aresta criada depois nunca
chegava — a seta aparecia no canvas e a ligação estava morta.

Quatro guardas, todas no app: aresta obrigatória, `maxSends` por aresta,
`maxVisits` por sessão, e teto de fila no destino. A cadeia zera quando **você**
digita no terminal.

**Nenhuma delas depende do que o agente escreve.** Quem falou vem do
`LOCAL_PEERPID` do socket, subindo a cadeia de `ppid` até o `shellPid` de um
terminal conhecido — o `egeon` nem tem parâmetro para dizer quem é. Foi campo do
pedido até hoje, e ali as guardas não seguravam nada: omitir o campo fazia o app
concluir "veio do usuário" e entregar direto, e preencher com o nome de um vizinho
emprestava as arestas dele.

A entrega diz ao receptor que quem falou foi outro agente e que isso não autoriza
nada — sem essa regra, um agente barrado numa permissão pede ao vizinho.

## Arrastar arquivo para o terminal

Soltar arquivos sobre um terminal escreve o caminho deles na caixa de input, sem
Enter — arrastar é entregar o arquivo, não mandar o agente trabalhar.

Em terminal com IA o texto entra como **paste**, e não como digitação: é só no
evento de paste que o Claude Code reconhece caminho de imagem (`png` · `jpg` ·
`jpeg` · `gif` · `webp`), lê o arquivo e troca o caminho por `[Image #1]` — imagem
anexada de verdade, em vez de um `Read`. Digitado, o mesmo caminho fica texto cru.
Quem decide é o `injectConfig.mode` do perfil, o mesmo do dispatch: shell recebe
digitação, porque ali o marcador de paste volta literal.

Extensão que o CLI não reconhece — `.pdf`, `.swift` — entra como texto, e é o que
se quer. Imagem arrastada de dentro do navegador não tem arquivo deste lado: vira
PNG num rascunho em `$TMPDIR/egeon-drop/`, fora de `~/.egeon`, que é pasta para se
editar à mão. Arrastar áudio só entrega o caminho: o CLI tem o vocabulário de
`[Audio #N]` mas passa `onAudioPaste: void 0` no chat. Ver ADR-026.

## Voz

O modo de voz do CLI grava pelo módulo nativo dele, dentro do pty que este app
segura — e o TCC atribui o microfone ao processo **responsável**, que é o bundle do
Egeon e não o `claude`. Por isso o `Info.plist` leva
`NSMicrophoneUsageDescription`: sem a chave não há negativa nem diálogo, o sistema
aborta o processo. Segurar espaço não pede nada do terminal — o CLI conta os espaços
do auto-repeat e usa timeout de silêncio como "soltou". A permissão morre a cada
build ad-hoc; `EG_SIGN_ID` com certificado fixo resolve. Ver ADR-027.

## Dispatch

Um prompt entra pelo socket, vira texto, entra numa fila, e só é entregue quando o
terminal está de fato pronto:

```
/dispatch → DispatchRequest.buildPrompt() → Session.enqueue()
          → laço de 0,25s → Session.drain() → bracketed paste → Enter
```

O laço vive em `Dispatcher.start()` e roda `drain()` + `updateActivity()` em cada
alvo. Nada disso pergunta à TUI se ela está pronta — ver ADR-007/008.

## Estado do terminal

`Activity`: `starting` → `working` → `waiting` / `asking` → `ready` / `dead`.

Quem diz que o turno acabou é o **CLI, por gancho**: `Stop` ("acabei") e
`Notification` ("estou pedindo permissão") chegam pela rota `/activity`. O
marcador `[[ED:ok]]` / `[[ED:ask]]` não saiu, mas mudou de papel — o gancho diz
**quando**, a tela diz **qual dos dois**. Terminal sem gancho (shell, outro CLI)
continua no silêncio do pty, como antes. Quem tem gancho **não é julgado pela tela
em momento nenhum** — nem no arranque: quem monta a linha de comando é o app,
então ele já sabe quem leva `--settings`, e não precisa descobrir no primeiro
relato. A tela mente de dois jeitos, e os dois foram medidos: o texto colado
empurra o marcador do turno passado e a assinatura muda sozinha; e o **recap** do
CLI escreve marcador sem disparar gancho nenhum, então há marcador na tela que não
corresponde a turno de ninguém.

Os dois avisos não pesam igual, e a mesma bolinha separa os dois pela cor —
glifos diferentes obrigam a ler o cabeçalho, a cor se reconhece de longe. `asking`
é o que interrompe: `●` laranja, borda do card laranja e som. `waiting` é
`● terminou` em verde, sem borda e sem som — você lê quando olhar.

Na barra lateral os três convivem, encostados na direita da linha e sempre na
mesma ordem: spinner do que está rodando, `●` laranja do que te espera, `●` verde
do que acabou, com a contagem quando é mais de um. Uma sessão tem vários nós e os
três são fatos independentes; escolher um para mostrar escondia os outros dois.

O verde some quando você **entra na sessão ou sai dela** — é aviso que não pede
nada, e chegar ali já é ter visto. O laranja não some assim: ele espera que você
olhe o TERMINAL, e passar pela sessão não é ler a pergunta que ele te fez.

E **fim de turno de quem acabou de acionar um vizinho não avisa nada**: o trabalho
seguiu para o outro card, e te chamar ali é te puxar para o meio de uma conversa
entre agentes. Pergunta avisa sempre, inclusive no meio de uma cadeia — permissão
não se delega. Detalhes: ADR-011 e ADR-024.

## Socket de controle

`~/.egeon/sock` — unix domain socket falando HTTP/1.1 mínimo. É como a
extensão do VSCode conversa com o app, como o `egeon` fala por dentro, e é como
se testa o app de fora.

```bash
curl --unix-socket ~/.egeon/sock http://eg/targets
curl --unix-socket ~/.egeon/sock -X POST http://eg/dispatch \
     -d '{"target":"deck/claude-1","kind":"raw","text":"oi"}'
curl --unix-socket ~/.egeon/sock "http://eg/peek?target=deck/claude-1"
```

Rotas: `/targets` `/dispatch` `/peek` `/chat` `/compose` `/geometry` `/layout` `/mosaic`
`/sidebar` `/edge` `/worktree` `/remove` `/activate` `/open` `/view` `/file` `/change`
`/activity` `/message` `/peers` `/status`. As três últimas
respondem sobre **quem perguntou**, resolvido pelo processo do outro lado da
conexão — uma chamada sua pelo terminal não é terminal nenhum, e entrega sem as
guardas de cadeia. **`/peek` e `/dispatch` são as ferramentas de teste** — dá
para verificar comportamento de agente ponta a ponta sem tocar na UI.

`/chat?target=ws` devolve o thread do modo chat como dados — autor, ordem e blocos de
cada mensagem — mais o estado de cada nó, que é o que o painel da direita e o `para:`
da caixa mostram. Existe pelo mesmo motivo do `/peek`: o thread é montado de vários
transcripts cruzados por tempo, e conferir isso na tela é conferir o resultado sem ver
a conta (ADR-029).

`/layout?mode=canvas|mosaic|chat` troca a visualização da sessão ativa, e `/geometry`
começa dizendo em que modo está: em mosaico o `docFrame` é o do painel e o
`grabPoint` não arrasta nada. `/mosaic?target=ws&swap=id1,id2` troca dois cards de
painel — o mesmo que arrastar um cabeçalho sobre o outro, e a única forma de
verificar isso de fora, porque evento de mouse sintético depende de permissão de
Acessibilidade, que a assinatura ad-hoc perde a cada build (ADR-003).
`/sidebar?collapsed=0|1|toggle` existe pelo mesmo motivo: recolher é tecla de menu e
clique, e nenhum dos dois é dirigível de fora. `toggle` é exatamente o que o ⌘/ e o
botão fazem.

`/edge?target=ws&from=a&to=b[&direction=->|<-|<->|cycle|none]` é a mesma história com
as ligações: criar é arrasto e trocar direção é clique num botão de 32pt. Sem
`direction` é consulta quando a ligação existe, e criação com o padrão da casa quando
não — é o que permite verificar que ela nasce bidirecional. `cycle` é o botão da
linha; `none` é o X.

`/targets` lista só terminais **de pé** — nó com processo morto continua no canvas
mas não é destino. Com `?folder=<path>` responde `{targets, all, session}`: quem é
da sessão dona daquela pasta, quem existe no app inteiro, e qual sessão casou. É
como a extensão do editor sabe o que sugerir sem oferecer terminal de outro
projeto; a pasta vira sessão pelas pastas que os nós de editor abriram, e só
depois por prefixo do caminho da sessão (o mais longo ganha, senão worktree perde
para o checkout principal). Ver ADR-019.

`/worktree?target=ws[/id]&branch=X` abre worktree da sessão — levando os terminais
junto — ou de um terminal só. `&nodes=back:fix/api,sub:spike` customiza a branch de
terminais específicos, e `back:` sem nome deixa aquele terminal onde está; é o
mesmo que digitar nas linhas do formulário (ADR-020). Existe porque o fluxo passa por
`NSAlert`, que não é dirigível de fora: sem ela não haveria como verificar que
cada terminal foi para a pasta certa, que é justamente o defeito do ADR-017. A
resposta traz `path` e `reused`, e o `path` é o da worktree que de fato ficou —
com branch que já existia, ela pode não ser a que o app sugeriu (ADR-018).

`/remove?target=ws[&worktrees=1]` remove a sessão, e só com `worktrees=1` apaga as
worktrees dela do disco — o padrão é não apagar, porque do outro lado é `worktree
remove --force`. Responde o que apagou, o que manteve e por quê (ADR-021).

## Configuração

Tudo em `~/.egeon/`, e todo arquivo é feito para ser editado à mão:
`sessions.json`, `agents.json`, `templates.json`, `components.json`,
`web-profiles.json`. Log em `~/egeon.log` (zerado a cada arranque).

O app também escreve ali o que os processos filhos precisam: `bin/egeon`,
`agent-hook.sh` e `claude-hooks.json`. São gerados a cada arranque — apagar
não quebra nada.

## Flavors

Dois apps instalados lado a lado, porque o app segura os pty direto e **todo
rebuild mata as sessões de agente em andamento** (ADR-010). O estável segura os
agentes de verdade e é de lá que se pede a mudança; o dev é o que se derruba.

| | estável | dev |
|---|---|---|
| bundle | `/Applications/Egeon Deck.app` | `app/build/EgeonDeck Dev.app` |
| id | `dev.duckcoder.egeondeck` | `…egeondeck.dev` |
| config | `~/.egeon/` | `~/.egeon-dev/` |
| socket | `~/.egeon/sock` | `~/.egeon-dev/sock` |
| log | `~/egeon.log` | `~/egeon-dev.log` |
| code-server | 8391 | 8392 |

`Flavor.current` resolve do sufixo do bundle id — um binário só, o que muda é o
Info.plist que o `make.sh` escreve. Sem bundle (`swift run`), assume estável.

**Todo caminho novo passa por `Flavor.current.config(_:)`.** Caminho fixo faz os
dois apps brigarem pelo mesmo arquivo, e o pior caso não é óbvio: a porta do
code-server. O segundo a subir acha a porta tomada, conclui que é órfã de execução
anterior — que é o caso comum, e há código para tratá-lo — e mata o code-server do
outro app.

## Desenvolvimento

```bash
./app/dev.sh                  # reconstrói o DEV, não encosta no estável
./app/dev.sh debug stable     # mexe no estável — mata seus agentes
./app/install.sh              # release + instala em /Applications
```

`~/egeon.log` (ou `~/egeon-dev.log`) é a fonte de verdade sobre o que aconteceu —
`open -a` descarta stdout.

**Encerre o app antes de tocar no bundle dele.** `make.sh` faz `rm -rf`, e apagar
o executável de um app vivo o mata na validação de assinatura, pulando o
`applicationWillTerminate` — que é onde o sessions.json é gravado e o code-server
encerrado. `dev.sh` e `install.sh` já fazem isso na ordem certa; script novo que
mexa em bundle precisa fazer também.

## Licença

AGPL-3.0-only. Texto completo em `LICENSE`. Copyright do autor — sem
contribuidor externo até aqui, então o dual-license segue possível.

Copyleft forte e **de rede**, não só de distribuição: o app é um servidor
(socket de controle em HTTP, code-server numa porta), e sob GPL comum quem o
hospedasse como serviço não deveria nada a ninguém — nunca distribui binário. A
seção 13 da AGPL fecha isso. Não impede vender nem usar comercialmente; impede
fechar o fonte.

Vale para o `app/` e para a `extension/`. Dependência nova de licença
incompatível — qualquer coisa proprietária, ou GPL-2-only — não entra.

---

# Regras

## Comentário

**Não narre o código.** Comentário que descreve o que a linha seguinte faz é
ruído: o leitor já sabe ler Swift.

Comente **por que**, e só quando o porquê não é óbvio: uma decisão contraintuitiva,
uma armadilha de plataforma, um valor que parece arbitrário, o motivo de a
alternativa evidente não funcionar. Se sumir o comentário e ninguém quebrar o
código por engano, o comentário não precisava existir.

Nada de comentário-índice numerando etapas (`// 1. …`, `// 2. …`), nada de
`// MARK:` para seções de três linhas, nada de repetir a assinatura da função em
prosa.

```swift
// ruim — narra
// Pega a magnificação e divide o delta
let magnification = enclosingScrollView?.magnification ?? 1

// bom — explica o que morde
// O nó vive num documento magnificado: 10px de mouse viram 20 unidades de
// documento a 0.5x. Sem dividir, a alça foge do cursor.
let magnification = enclosingScrollView?.magnification ?? 1
```

Doc comment (`///`) em tipo ou método público vale quando diz algo que a
assinatura não diz. Em `private var x: Int` que só guarda um contador, não vale.

## Idioma

Código, identificadores e mensagens de commit em português quando já forem —
seguir o que está no arquivo. Comentários, docs e logs em **português**.

## Decisões

`docs/01-decisoes.md` registra o que foi decidido e **por quê**, incluindo o que
foi descartado e o motivo. Decisão de arquitetura nova, ou reversão de uma
antiga, vira ADR ali. Antes de propor rota diferente para editor, portal de
janela, tmux, ou detecção de ociosidade, leia — essas já custaram protótipo.

## Verificação

Não dizer que funciona sem evidência. O socket e o log existem para isso: dispare
por `/dispatch`, confirme por `/peek` e por `~/egeon.log`. Compilar não é
verificar.
