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
| `Dispatcher.swift` | `Session` (alvo endereçável) e `Dispatcher` — fila, injeção, ociosidade, estado, cadeia |
| `Attention.swift` | `Activity`, `Spinner`, `AttentionSound` — vocabulário de "carregando / precisa de você" |
| `Edge.swift` | `EdgeConfig`, traçado das ligações (`EdgeCurve`, `EdgeLayerView`) e a porta `+` do card |
| `AgentProfile.swift` | perfis de agente e `agents.json` |
| `ControlSocket.swift` | socket unix de controle |
| `Editor.swift` / `CodeServer.swift` | nó de editor (WKWebView) e o processo do code-server |
| `WebNode.swift` | nó de navegador, com perfil de navegação isolado |
| `Sidebar.swift` / `Toolbar.swift` | lista de sessões e barra de ferramentas do canvas |
| `Glass.swift` | `GlassPanel` — o vidro das barras flutuantes, e o interruptor dele |
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

**Conversa** — cada nó `agent` tem um `sessionId` próprio, gerado na primeira
subida, que sobrevive ao rebuild. Se você trocar de conversa dentro da TUI
(`/resume`, `/clear`, fork), o CLI avisa o app por um gancho `UserPromptSubmit` e o
`sessionId` acompanha. Ver ADR-014.

**Componente** — preset de nó (agente, comando, pasta, papel). **Template** —
preset de sessão inteira. Os dois copiam valores no momento da criação; editar o
preset depois não mexe em quem já nasceu — por isso a barra tem duas ações
separadas, "salvar como template" (cria) e "atualizar template" (regrava o de
origem, e só aparece quando existe um).

Copiar um nó — por template ou duplicando a sessão numa worktree — copia a
montagem e **nunca a conversa**: `NodeConfig.withoutConversation` zera o
`sessionId`. Com ele junto, duas sessões apontam para a mesma conversa e a
segunda a subir não consegue abri-la — o card fica com a TUI desenhada e o
processo morto, sem erro à vista. Duplicar para worktree leva também as arestas e
o `maxVisits`: a rede é parte da montagem.

**Aresta** — ligação de mão única entre dois terminais: `from` **pode acionar**
`to`. Desenhada arrastando a porta `+` de um card até outro. Não é um cano — o
agente descobre o endereço com `egeon peers` e decide quando usar. Ida e volta
são duas arestas. Ver ADR-012.

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

Duas maneiras de olhar a mesma sessão, na barra de cima (⌥⌘1 / ⌥⌘2):

**Canvas** — a bancada livre: posição, tamanho, zoom, arestas desenhadas.
**Mosaico** — os mesmos nós dividindo a janela inteira, sem sobreposição e sem
zoom. Colunas empilhadas, divisores arrastáveis, coluna sem nó não aparece.

No mosaico o arranjo é seu: **arraste o cabeçalho de um card sobre outro e os dois
trocam de painel**, em qualquer direção, inclusive entre colunas. O painel que vai
receber acende antes de você soltar. Quem nunca arrastou nada vê o arranjo por tipo
— editor · terminais · web, na ordem do `sessions.json` —, e é dele que o resto
parte. O que você montou vive em `mosaic.slots`, ids de nó por coluna; nó criado
depois entra na coluna de quem é do mesmo tipo, sem desfazer o resto. Ver ADR-023.

**Não são duas cópias do nó.** Em qualquer modo o card é o MESMO `NodeView`, e o
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
nós no arquivo continua sendo sempre a do canvas: `syncFrames` não roda em
mosaico, senão a montagem inteira seria regravada com o tamanho dos painéis.

Ver ADR-016.

## As barras

A barra de sessões **flutua sobre o conteúdo**, em vidro (`NSGlassEffectView`,
macOS 26). A barra do canvas e o banner de aviso usam o mesmo `GlassPanel`. A barra
de visualização, no topo, segue opaca e encostada.

O conteúdo cede à esquerda só a largura do **trilho recolhido** — o que se abre além
dele passa por cima. Reservar a barra aberta devolveria a coluna fixa; não reservar
nada faria o painel esquerdo do mosaico nascer debaixo dela, e mosaico é o modo onde
nada fica coberto.

Recolher é automático **pelo modo**, que é por sessão: mosaico recolhe, canvas não.
Abre no hover com 0,18s de atraso, e ⌥⌘S fixa aberta. No trilho as **bolinhas
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
concluir "veio do Julio" e entregar direto, e preencher com o nome de um vizinho
emprestava as arestas dele.

A entrega diz ao receptor que quem falou foi outro agente e que isso não autoriza
nada — sem essa regra, um agente barrado numa permissão pede ao vizinho.

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

Rotas: `/targets` `/dispatch` `/peek` `/geometry` `/layout` `/mosaic` `/sidebar`
`/worktree` `/remove` `/activate` `/open` `/view` `/file` `/change` `/activity`
`/message` `/peers` `/status`. As três últimas
respondem sobre **quem perguntou**, resolvido pelo processo do outro lado da
conexão — uma chamada sua pelo terminal não é terminal nenhum, e entrega sem as
guardas de cadeia. **`/peek` e `/dispatch` são as ferramentas de teste** — dá
para verificar comportamento de agente ponta a ponta sem tocar na UI.

`/layout?mode=canvas|mosaic` troca a visualização da sessão ativa, e `/geometry`
começa dizendo em que modo está: em mosaico o `docFrame` é o do painel e o
`grabPoint` não arrasta nada. `/mosaic?target=ws&swap=id1,id2` troca dois cards de
painel — o mesmo que arrastar um cabeçalho sobre o outro, e a única forma de
verificar isso de fora, porque evento de mouse sintético depende de permissão de
Acessibilidade, que a assinatura ad-hoc perde a cada build (ADR-003).
`/sidebar?pin=0|1` existe pelo mesmo motivo: a barra de sessões abre no hover, e sem
esta rota não há como conferir de fora o que ela faz por cima de um card.

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
