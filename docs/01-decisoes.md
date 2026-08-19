# Egeon Deck — decisões de arquitetura

Registro do que foi decidido, o que foi descartado, e **por quê**. Cada decisão
aqui custou investigação ou protótipo — a intenção é não redecidir a mesma coisa
daqui a três meses.

Data: 2026-08-09. Alvo: macOS, uso pessoal.

---

## ADR-001 — Janela de outro app não entra dentro da nossa

**Decisão:** aceitar que o VSCode.app nunca ficará dentro de uma view nossa.

**Motivo:** macOS não tem reparenting de janela entre processos (não existe
equivalente ao XEmbed do X11). A Accessibility API permite mover, redimensionar
e focar janela alheia — nunca contê-la.

**Consequência:** "canvas de apps" no sentido literal não existe. Nem no Maestri,
que só desenha nós próprios (terminais, notas, sketches) e não embute app nenhum.

---

## ADR-002 — Fork do VSCode: rejeitado para o MVP, não rejeitado em definitivo

**Decisão:** não forkar agora.

**Motivo:** fork não resolve o ADR-001 — continua sendo Electron, processo
separado, janela top-level. Zero ganho no problema real. E fork **perde as mesmas
extensões** que o code-server (Marketplace da Microsoft é proibido fora de
produtos MS), então extensão não desempata nada entre os dois.

**Onde o fork ainda faz sentido:** é a única rota para "o canvas ser o layout
raiz e editores/terminais reais do VSCode serem nós dentro dele" — trocando o
grid do workbench (`vs/base/browser/ui/grid`, `editorGroupsService`) por um
canvas. Explorer, Search, SCM e Debug sobreviveriam intocados por serem partes
laterais. Custo: semanas, build do fonte, assinar e notarizar.

**Alívio que vale registrar:** fork pessoal não precisa acompanhar release mensal.
Trava numa versão e rebase quando quiser. O custo que quebra Cursor e Windsurf é
competitivo, não técnico.

---

## ADR-003 — Rota do editor: code-server em WKWebView

**Decisão:** o nó de editor é um `WKWebView` apontando para um `code-server`
local, um `?folder=` por workspace.

**Descartado — portal via Accessibility API.** Foi implementado e funcionou
(janela real do VSCode ancorada e seguindo pan/arrasto do nó). Rejeitado por três
defeitos estruturais:

1. **Z-order.** macOS não intercala janelas entre apps. Para a janela real
   aparecer "no buraco", nossa janela tem que viver em nível backdrop, atrás de
   tudo — e nunca poder vir para frente.
2. **Permissão frágil.** TCC guarda a autorização de Acessibilidade por
   *identidade de código*. Assinatura ad-hoc muda o hash a cada build, então
   **toda recompilação invalida a permissão** — a caixinha continua marcada nos
   Ajustes e não vale nada. Só conserta com certificado fixo.
3. **Zoom quebra.** Nó de terminal escala junto com o canvas; janela ancorada
   apenas redimensiona. Dois comportamentos diferentes no mesmo canvas.

**Preço aceito:** code-server usa OpenVSX. Copilot e Pylance não existem lá
(proibição de licença da Microsoft, não limitação técnica).

**Impacto real no stack deste projeto:** pequeno.

| ferramenta | situação |
|---|---|
| Dart / Flutter | disponível no OpenVSX (publisher oficial Dart-Code) |
| Go | disponível no OpenVSX (publisher oficial golang) |
| Python | perde Pylance; usa Pyright (mesmo motor, sem as extras proprietárias) |
| Copilot | **perdido** |
| Claude Code | irrelevante — roda em nó de terminal, não é extensão |

**Nota:** usar `code-server` (Coder), **não** `openvscode-server` — este último
foi descontinuado em julho de 2026.

### Como ficou, na prática

Instalado com `brew install code-server` (4.112.0, Code 1.112.0). Uma instância
só serve todos os workspaces em `127.0.0.1:8391`; cada nó de editor abre a mesma
origem com `?folder=` diferente.

Quatro coisas que precisaram de conserto e não são óbvias:

1. **`security.workspace.trust.enabled: false`.** Sem isso todo workspace abre em
   Restricted Mode atrás de um diálogo de confiança, e o SCM fica limitado. As
   pastas são as que o próprio usuário configurou. O app semeia esse
   `settings.json` uma vez; edições posteriores do usuário são preservadas.
2. **`NSAllowsLocalNetworking` no Info.plist.** O ATS bloqueia HTTP, e o
   `code-server` local é HTTP. Sem a exceção, o WKWebView só mostra erro.
3. **Esperar o `healthz` antes de carregar.** WKWebView que bate em porta morta
   mostra página de erro e não tenta de novo sozinho.
4. **Janela ocluída não pinta o Monaco.** O WebKit estrangula
   `requestAnimationFrame` quando a janela está atrás, e o editor fica em branco
   — inclusive em screenshot. Só afeta captura automatizada; em uso normal a
   janela está à frente.

Dirigir o editor de fora se faz por `?folder=` e por clique no DOM: os comandos
do VSCode não são alcançáveis por JavaScript da página. Daí os endpoints
`/open`, `/view` e `/change`.

---

## ADR-004 — Extensão própria não passa por marketplace

**Decisão:** a extensão do Egeon Deck é VSIX local, instalada direto no diretório
de extensões.

**Motivo:** a restrição do Marketplace vale para extensões da Microsoft. Código
nosso a gente instala como quiser. Vale igual no code-server e no VSCode.app.

---

## ADR-005 — Review acontece num custom editor nosso, não na Comments API

> Revisado. A primeira versão desta decisão escolhia a Comments API do VSCode;
> ela não funciona onde o review precisa acontecer. Motivo abaixo.

**Decisão:** um `registerCustomEditorProvider` com viewType `egeon.spec`,
registrado como editor padrão de `*.md`. Ele renderiza o markdown, permite
edição, e desenha as threads de review — tudo dentro do nosso webview.

```jsonc
"workbench.editorAssociations": { "*.md": "egeon.spec" }
```

Um clique no Explorer já abre renderizado. `View: Reopen Editor With…` volta ao
fonte quando precisar.

**Descartado — Comments API (`createCommentController`).** Ela só anexa em
**editor de texto**, não em webview. Como o review tem que acontecer no preview,
e o preview é webview, ela fica inalcançável.

**Descartado — preview embutido + `markdown.previewScripts`.** Dá para injetar
script no preview do VSCode, mas `acquireVsCodeApi()` só pode ser chamado **uma
vez por webview** e a extensão de markdown embutida já chamou. O script
contribuído desenha UI e não tem canal de volta para o extension host. Some-se a
isso o preview embutido ser somente-leitura, e a rota morre.

**Edição:** o custom editor aplica `WorkspaceEdit` sobre o `TextDocument`. Nunca
gravar o arquivo por baixo — passando pela API do VSCode, undo, dirty state e
save continuam corretos, e edição não salva no editor de texto não é atropelada.

**Custo aceito:** a UI de thread é nossa, desenhada à mão. Perde-se o visual
nativo de comentário. Ganha-se preview editável, um clique só, e comportamento
idêntico no code-server — que é onde isso vai rodar.

**Onde os comentários moram:** sidecar em `.egeon/reviews/<arquivo>.json`.
Não dentro do `.md` — o markdown é o produto e tem que ficar limpo. (O
[md-redline](https://github.com/dejuknow/md-redline) faz o contrário, gravando
marcador HTML invisível no arquivo; é uma escolha válida, só não a nossa.)

## ADR-005b — Comentário ancora em conteúdo, nunca em número de linha

**Decisão:** cada thread guarda o trecho citado e um hash do bloco. Na releitura,
reancora por match difuso.

**Motivo:** o agente **reescreve o arquivo**. Um comentário preso a "linha 12"
aponta para o lugar errado assim que ele insere um parágrafo acima — e apontar
para o lugar errado é pior do que não apontar.

**Regra:** thread que não reancora vira **órfã** e aparece no topo do documento,
com o trecho original citado. Nunca some calada.

---

## ADR-006 — Baseline de diff por snapshot: implementado e **removido**

> Status: **revertido**. Construído, testado, e retirado a pedido do usuário por
> ficar estranho no uso. Registrado aqui para não ser reconstruído por engano.

**O que era:** ao clicar em *Request changes*, a extensão gravava o conteúdo do
arquivo em `.egeon/snapshots/<arquivo>.base`. Depois, os blocos alterados
ganhavam marca verde na margem direita, a barra mostrava `+N −M desde o pedido`,
e clicar abria o diff editor nativo do VSCode comparando baseline ↔ atual.

**A ideia continua defensável:** "o que o agente mudou nesta rodada" não é
"diff vs HEAD" — git depende do staging e mistura suas mudanças com as dele.

**Por que saiu:** na prática o preview ficou carregado demais. Duas margens com
significados diferentes (comentário à esquerda, mudança à direita), mais um
contador na barra, competindo com a leitura do documento — que é o ponto do
preview.

**O que sobrou no lugar:** nada. O VSCode já tem Source Control e diff editor
nativos a um clique de distância no mesmo workspace. Duplicar isso dentro do
preview não pagava o ruído visual.

**Se voltar um dia,** a lição é sobre forma, não sobre mecânica: o diff por LCS
de linhas funcionava bem (inserir parágrafo no meio marcava só as linhas novas,
não o documento inteiro). O problema era onde e como aquilo aparecia.

---

## ADR-007 — Injetar na sessão viva, não `claude -p`

**Decisão:** o prompt é escrito no pty da sessão interativa que já está rodando.

**Motivo:** `claude -p` sobe processo novo com contexto zerado — perde conversa,
arquivos já lidos, plano em andamento. `claude --resume` preserva contexto mas a
saída vai para outro processo, então você perde o "ver trabalhando" no painel.

**Mecânica obrigatória — bracketed paste:**

```
\e[200~  <payload multilinha>  \e[201~
\r
```

Sem isso, cada `\n` do prompt vira um submit separado na TUI e a mensagem chega
picada. Escrevemos esses bytes direto no pty master — sem tmux no meio
([ADR-010](#adr-010--sem-tmux-o-terminal-morre-com-o-app)).

**Três coisas que só apareceram testando** (por isso `/peek` existe: sem ver o
que o terminal exibe, "entreguei o prompt" e "o agente recebeu o prompt" são
indistinguíveis de fora):

1. **zsh não aceita bracketed paste vindo por injeção.** O shell exibe os
   marcadores literais (`^[[200~ … ^[[201~`) e nada executa. Terminal sem perfil
   usa `plain`; bracketed paste fica para TUI de agente, que ativa o modo.
2. **O Enter precisa de pausa depois do paste.** A TUI do Claude Code é Ink e
   processa entrada de forma assíncrona: `\r` enviado no mesmo instante do fim
   do paste é descartado e o prompt fica parado na caixa de input. 150 ms
   resolve — daí `InjectConfig.submitDelayMs`.
3. **O ambiente precisa ser higienizado.** O app herda o ambiente de quem o
   lançou. Se isso inclui `CLAUDE_CODE_*`, o agente aberto pelo canvas se acha
   sessão filha e desliga transcript, entre outras esquisitices. Essas variáveis
   são removidas antes de subir o pty.

---

## ADR-008 — Ocupação detectada por silêncio, nunca por parsing de tela

**Decisão:** a sessão é considerada ociosa após ~1,5 s sem bytes no pty. Fila
segura os disparos até lá.

**Motivo:** TUI de agente redesenha a tela com ANSI, spinner e movimento de
cursor. Extrair significado disso quebra a cada release do CLI. Silêncio é
barato e estável.

**Corolário:** o retorno do agente **não** vem de ler a tela. Vem dele editar o
arquivo — o que ele já sabe fazer. O spec vira o canal de volta.

### Silêncio sozinho mente

Descoberto entregando prompt numa sessão de ~25 s de vida: o log disse
"entregue" e a TUI ficou vazia. Uma pausa durante o boot passa por ociosidade, e
o prompt vai para um pty que ainda não tem leitor — some sem rastro.

Duas condições a mais, então:

1. **Aquecimento** (`idle.warmupMs`, 4 s) e **`sawOutput`**: a sessão precisa ter
   escrito alguma coisa antes de ser considerada utilizável.
2. **Confirmação de entrega**: se a TUI recebeu a entrada, ela redesenha — texto
   ecoa na caixa de input ou o agente começa a trabalhar. De um jeito ou de
   outro saem bytes no pty. Silêncio total 1,5 s após uma entrega significa que
   ninguém leu; reenvia até 3 vezes e registra.

Repare que a confirmação **não parseia a tela** — só compara o instante do
último byte com o instante do envio. Continua valendo a regra de não depender do
desenho da TUI.

E uma entrega por vez: empilhar prompts sem saber se o anterior chegou é
exatamente como o primeiro sumiu sem ninguém notar.

---

## ADR-009 — Agente é plugável, não hardcoded

**Decisão:** nenhum ponto do código conhece "Claude Code". O que existe é um nó
do tipo **terminal com IA**, configurado por um perfil de agente.

**Motivo:** trocar para OpenCode, Codex CLI ou Gemini CLI tem que ser edição de
JSON, não refactor.

Detalhes do modelo em [02-mvp.md](02-mvp.md#perfis-de-agente).

---

## ADR-010 — Sem tmux. O terminal morre com o app.

**Decisão:** o app segura o pty master diretamente (SwiftTerm + `forkpty`). Se o
app fecha ou crasha, os terminais morrem junto. Comportamento esperado, não bug.

**Motivo:** o único jeito de um agente sobreviver ao app é um terceiro processo
segurar o pty master — e esse processo seria o tmux (ou um daemon nosso, que é
reimplementar tmux pior). Soltar o filho com `setsid` não resolve: sem ninguém do
outro lado, o terminal deixa de existir e a TUI do agente quebra igual.

Sobrevivência de sessão não vale a camada extra de emulação agora.

**O que se perde, explicitamente:**

- rebuild do app durante o desenvolvimento mata as sessões de agente em andamento
- crash no meio de uma tarefa longa perde o trabalho em voo (o histórico ainda
  volta com `--resume`, a tarefa não)
- não dá para reconectar de fora (`tmux attach`) quando o app trava

**Implementação:** não construir abstração de backend agora. Criar o pty em **um
único arquivo**, para que trocar por tmux depois seja uma mudança localizada e
não uma caçada. Interface prematura aqui é custo sem retorno.

---

## ADR-011 — "Precisa de você" vem de um marcador que nós pedimos, não da tela

**Decisão:** o agente termina cada resposta com um marcador que o Egeon Deck
escolheu (`[[ED:ok]]` ou `[[ED:ask]]`), pedido por system prompt. O silêncio do
pty continua valendo como rede de segurança.

### O problema

O [ADR-008](#adr-008--ocupação-detectada-por-silêncio-nunca-por-parsing-de-tela)
resolveu "o agente está ocupado?" com silêncio no pty, e isso segue de pé. Mas
para avisar o usuário falta uma distinção que o silêncio não dá:

| situação | como fica o pty |
|---|---|
| terminou a tarefa | parou de sair byte |
| está te fazendo uma pergunta | parou de sair byte |
| o CLI abriu um diálogo de permissão | parou de sair byte |

São o mesmo sinal. E as três **precisam de você** — então o aviso funciona sem
distinguir; o que se perde é dizer *o que* te espera.

### O que foi descartado

**Casar o desenho da TUI.** É o que o ADR-008 já tinha rejeitado, pelo mesmo
motivo: `❯ 1. Yes` e a moldura do diálogo mudam a cada release do CLI, e cada
release vira manutenção de regex.

### A rota escolhida

Inverter quem define o formato. Em vez de adivinhar o que o CLI desenha, o
Egeon Deck anexa ao system prompt uma instrução de terminar toda resposta com um
marcador. O sinal passa a ser **nosso**, e nada em `claude`, `codex` ou `gemini`
pode quebrá-lo mudando de layout.

O texto vai em `--append-system-prompt` (perfil `claude`) e por isso não gasta
turno da conversa, não aparece no histórico e não se dilui depois de vinte
mensagens — que é exatamente por que a mesma instrução como primeira *mensagem*
valeria pouco.

Sobre `--append-system-prompt` sempre presente: antes ele só entrava quando o nó
tinha papel definido. Agora entra em todo nó `agent`, com o protocolo primeiro e
o papel depois. A flag continua sendo anexada **só quando a linha de comando
ainda começa com o binário do perfil** — quem trocou o `cmd` do nó pode ter
trocado de programa, e a flag num programa que não a conhece mata o terminal no
arranque.

### As três camadas, nessa ordem

1. **Marcador na tela** — sinal explícito. Diz se terminou (`[[ED:ok]]`) ou se
   depende de você (`[[ED:ask]]`). Com os dois na tela, manda o de baixo: o
   terminal escreve para baixo, então o de baixo é o mais recente.
2. **`attention.patterns`** — regex sobre as últimas linhas, **vazio por
   padrão**. Existe por um caso que o marcador não alcança: o diálogo de
   permissão é desenhado pelo próprio CLI, não é mensagem do modelo, e nenhum
   marcador chega lá. Preencher é opção sua, e é você que mantém quando o CLI
   mudar.
3. **Silêncio** — quando não há marcador nem padrão casando. Aí vale a rajada:
   a saída precisa ter durado pelo menos `attention.minWorkMs` (2 s) antes do
   silêncio, senão o eco de uma tecla ou um `clear` contariam como "terminou".

A camada 3 é o que cobre as falhas da 1: agente que esqueceu o marcador, CLI sem
flag de system prompt, marcador quebrado em duas linhas por uma janela estreita.
Nunca há um estado em que o terminal para e ninguém avisa.

### O marcador não espera o silêncio

A camada 1 vale **antes** de o pty se calar. O agente escreve a resposta, o
marcador já está na tela — e a TUI continua cuspindo byte por segundos: hook que
roda depois, chamada de MCP, contador de tokens, `✻ Cogitated for 2s`. Esperar o
`idle.ms` inteiro aí é segurar um aviso que já está pronto, e quanto mais o CLI
cozinha depois da resposta, pior fica.

Então enquanto o terminal trabalha, a tela é lida a cada 0,4 s procurando
marcador. O perigo óbvio: **o marcador do turno passado continua visível**
enquanto o agente pensa no turno atual, e aceitá-lo dispararia o aviso no
primeiro instante de toda tarefa.

O que resolve é a **assinatura**: o marcador mais as três linhas acima dele.
Quando a rajada abre, ela é fotografada uma vez; durante o trabalho só vale um
marcador cuja assinatura seja **diferente** da fotografada. O marcador é idêntico
em todo turno — o texto da resposta acima dele é que muda. Duas respostas
idênticas em sequência não se distinguem, e aí sobra o silêncio: caso raro, e o
prejuízo é só chegar mais tarde.

Uma trava a mais, para o estado não piscar: turno dado por encerrado não se
desfaz porque chegaram bytes. O rabo de TUI da **mesma rajada** mantém o aviso;
só uma rajada nova devolve o terminal para `working`. Sem isso o card alternaria
entre "trabalhando" e "precisa de você", e o som tocaria a cada volta.

### Rajada do boot não é trabalho

O banner da TUI leva ~2,7 s para desenhar — mais que o `minWorkMs` — e sai
sozinho, sem ninguém ter pedido nada. Sem tratamento, todo arranque do app e toda
sessão materializada avisavam "terminei", com som. Rajada que **começa dentro do
aquecimento** é descartada: `warmupMs` já existia para não entregar prompt antes
de haver quem o leia, e delimita exatamente a mesma janela.

### O que o usuário vê

Nada de Central de Notificações, e nada de badge no Dock. Os dois canais são
dentro do app, onde você já está olhando:

- **nó no canvas** — spinner enquanto roda, `● precisa de você` quando para, e a
  borda do card fica laranja. A borda existe porque com zoom out o cabeçalho
  vira ilegível muito antes de o card sumir, e é aí que achar quem parou importa.
- **barra lateral** — spinner ou `●` com contagem por sessão. É o único canal das
  sessões inativas: o canvas delas sai da hierarquia de views e não desenha nada,
  mas o pty continua rodando. Por isso o resumo mora no `Dispatcher`, que conhece
  todos os alvos, e não no canvas.

Mais um som do sistema, com intervalo mínimo de 1,5 s entre toques — quatro
agentes parando no mesmo tick tocariam quatro sons sobrepostos, e isso é ruído,
não aviso.

O padrão é `Tink` a `volume: 0.3`, e a escolha é deliberada: isto dispara o dia
inteiro, então tem de ser notável sem interromper. `Tink` é o mais curto do
catálogo (~0,2 s); `Glass` e `Hero` sobressaltam. E o **volume pesa mais que o
timbre** — qualquer som do catálogo em 0,3 vira toque de fundo, e é por isso que
o campo existe em vez de só a lista de nomes.

**Só terminal com IA chama.** Shell mostra o spinner e nada mais: um
`npm run dev` fica quieto entre um rebuild e outro, e avisar a cada pausa dele
transformaria o aviso em barulho de fundo.

**Foco conta como ciência.** Enquanto o cursor do teclado está dentro do
terminal, o silêncio é você lendo ou digitando — alarme sobre o que já está na
sua frente é ruído. Ao focar, a parada é marcada como vista, e só um byte novo
volta a armar o aviso. Sem isso, o alerta dispararia atrasado, no instante em que
você clicasse em outro lugar.

### Decorrência: decode tolerante a chave faltando

O `Decodable` sintetizado do Swift **não** usa o valor padrão da propriedade —
chave ausente é `keyNotFound` e o decode inteiro joga. Como `AgentStore.load`
cai no `try?` e regrava os padrões, um `agents.json` editado à mão com uma chave
a menos era **apagado e substituído sem aviso**. Isso valia desde sempre para
`idle` e `inject`; `attention` só aumentaria a superfície.

`IdleConfig`, `InjectConfig`, `MarkerConfig` e `AttentionConfig` ganharam
`init(from:)` explícito com `decodeIfPresent`. Vai em extensão, e não no corpo do
struct: declarar `init(from:)` dentro do corpo apaga o init memberwise.

Em `attention.sound`, chave ausente e `null` explícito são coisas diferentes —
ausente herda o padrão, `null` desliga o som e mantém o aviso visual.

---

## ADR-012 — Agente aciona agente por aresta desenhada, nunca por encaminhamento

**Decisão:** uma aresta no canvas concede a um terminal a **capacidade** de acionar
outro. O agente decide quando e para quem falar. Nada é encaminhado sozinho.

### O que foi descartado, e por quê importa

**Encaminhar a saída.** A forma óbvia — "vincula A a B e as respostas de A vão para
B" — não tem terminador: toda resposta de A é entrada de B, que responde, que é
entrada de A. É a topologia de dois agentes LangChain que rodou 11 dias e gerou
US$ 47 mil de conta em novembro de 2025. Multi-agente já custa ~15× o token de um
chat; sem terminador o teto é o cartão.

Matou-a um caso concreto, e não a teoria: com um PM refinando tarefas **com você**,
todo turno dele viraria mensagem para o frontend. Só o agente sabe distinguir
"estou pensando com o usuário" de "agora vai".

**Mensageria nativa do Claude Code.** Ela existe (v2.1.224+) e já funcionava entre
os terminais do app — verificado: um agente listou os irmãos com `/list-agents`.
Rejeitada por três motivos. É só Claude, o que fere o [ADR-009](#adr-009--agente-é-plugável-não-hardcoded)
justamente quando outros CLIs entram. É invisível ao Egeon Deck, que não desenha
nem registra o que passou. E ela nomeia sessão pela pasta de trabalho: dois
terminais na mesma worktree viram `minha-branch-2-c9` e `minha-branch-2-f8`, sem
pista de qual é o revisor. O app sabe; o CLI não.

**Tipo "bidirecional".** Cobriria só o ciclo de dois e deixaria `A→B→C→A` sem
tratamento. Com uma seta por sentido, os dois são o mesmo mecanismo — e o ciclo
aparece desenhado em vez de escondido num campo.

### Aresta é catálogo, não cano

O agente recebe no system prompt o elenco que pode acionar, com endereço, CLI e o
papel de cada vizinho. O papel entra junto porque sem ele sobra uma lista de
identificadores sem como escolher entre eles.

Enviar é `POST /message?from=…&target=…` com o corpo em texto puro. Rota separada
do `/dispatch` porque quem chama é um agente escrevendo por heredoc: montar JSON à
mão no meio de um texto livre é onde ele erra.

A entrega usa o mesmo envelope do review, com um rodapé a mais — quem escreveu foi
outro agente, não o usuário, e isso não autoriza nada. É a regra que a Anthropic
aplica entre sessões do Claude Code, e existe por um motivo específico: sem ela um
agente barrado numa permissão pede ao vizinho para fazer por ele.

### Quatro guardas, nenhuma no texto do prompt

O [MAST](https://arxiv.org/abs/2503.13657) mediu 1600+ traces em 7 frameworks:
desalinhamento entre agentes é ~40% das falhas. E os autores tentaram consertar
com prompt e topologia melhores, ganhando +5% e +15% — concluíram que precisa de
redesenho estrutural. Ou seja: **capricho no texto do apêndice não é garantia.**

| guarda | segura |
|---|---|
| aresta obrigatória | agente falando com quem você não ligou |
| `maxSends` na aresta | idas e voltas do par |
| `maxVisits` na sessão | ciclo de 3+ nós |
| fila ≤ 5 no destino | agente disparando em laço |

`maxSends` conta quantas vezes **aquela seta** dispara na mesma cadeia; é o botão
do dia a dia. `maxVisits` conta revisitas de um terminal na cadeia inteira, e é
rede: só ele segura `A→B→C→A`, onde cada seta dispara uma vez só e o limite dela
nunca chega perto. Contar revisita e não comprimento é deliberado —
`pm → front → pm → back → pm` é orquestração normal, e cortar por comprimento
estrangularia trabalho legítimo.

A guarda de fila apareceu **testando**, não desenhando: a cadeia só avança na
entrega, então sete disparos seguidos passaram todos como "envio 1/2".
Profundidade não segura volume.

**A cadeia zera quando você digita.** Entrada humana é o único sinal exato de que
uma conversa nova começou — tentei separar "TUI se assentando" de "agente voltou ao
trabalho" por duração de rajada e não existe corte; ver ADR-011.

### Os padrões: 2 na aresta, 4 na sessão

Números de framework não servem direto: o `max_iter: 15` do CrewAI conta iteração
de ferramenta de um agente, não ida e volta entre agentes.

O 2 é baixo de propósito. Desempenho de agente degrada conforme as rodadas
aumentam **mesmo sobrando contexto** — a inércia conversacional medida em
[arXiv:2602.03664](https://arxiv.org/pdf/2602.03664) —, e cada volta é uma chance
nova para os 40% de desalinhamento do MAST. Somando que isto roda enquanto ninguém
olha: errar para menos custa pedir uma rodada a mais; errar para mais custa token
sem supervisão. Duas idas e voltas cobrem delega → recebe → ajusta → recebe, e a
terceira já costuma ser repetição.

O 4 da sessão é folgado para uma orquestração de três nós não esbarrar nele. O
corte que se sente no dia a dia deve vir da aresta.

### Desenho: rota, não parâmetro

Aresta para trás não é a mesma curva com outros números — é **outra rota**. Lido do
`getEdgeRenderData.ts` do n8n: quando `sourceX - 20 > targetX`, eles abandonam a
Bézier e desenham um caminho ortogonal de cantos arredondados que sai pela direita,
desce e volta. Ida e volta ocupam faixas diferentes e por isso não têm como se
cruzar — e o retorno parece um retorno.

Duas adaptações. O `EDGE_PADDING_BOTTOM` de 130 deles é fixo porque um nó do n8n
tem ~100pt de altura; um terminal aqui passa de 380, e 130 abaixo da porta ainda
cai dentro do card, escondendo a volta atrás dele — a faixa é medida da base do
card mais baixo. E dois terminais empilhados na mesma coluna fazem as duas direções
virarem loop, com as mesmas portas em x e a mesma faixa: medido, 0pt de distância.
Uma volta desce e a outra sobe.

Os controles da aresta vivem numa área invisível que desce colando na linha. Sem
ela o realce é decidido só pela distância à curva, e subir o mouse para clicar
apaga os botões antes de o cursor chegar.

---

## ADR-013 — O nome: Egeon Deck

**Decisão:** o app se chama **Egeon Deck**; `egeon` é o identificador técnico
(diretório de config, log, socket, envelope de prompt).

### Por que sair de mega-brain

O nome estava tomado, e por vizinhos: `thiagofinch/mega-brain`,
`marcosrodsa/mega-brain` e `guhcostan/claude-mega-brain` — este último no mesmo
nicho —, mais `megabrain` no npm.

### O que foi descartado, e por quê

Cada um destes morreu por um motivo concreto, e ficam registrados para não serem
propostos de novo:

| candidato | motivo |
|---|---|
| **octopus** | quatro projetos diretos já usam, dois rodando agentes de IA em tmux — esta ideia. Mais Octopus Deploy, marca em ferramenta de dev |
| **kraken** | é o maior darknet market em língua russa (sucessor do Hydra), mais a exchange de cripto, mais GitKraken. E a raiz está saturada em dev tooling: KrakenD, Kraken CI, uber/kraken, openkraken, kraken-build, krakenjs, kraken (OCR) |
| **mega-kraken** | "mega" e "kraken" são os dois nomes de darknet market; a busca devolve `kraken-maket/mega-darknet` |
| **orochi** | npm tomado, biblioteca da AMD (GPUOpen), ferramenta de forense de memória, e cultura pop pesada |
| **moirai** | melhor fit conceitual de todos — as Moiras fiam, medem e **cortam** o fio, que é a guarda de ciclo do ADR-012 — e o mais tomado: Nike, CEA-LIST, e moiraicloud.ai, que é orquestração de infra |
| **kraken-helm** | `helm` é o gerenciador de pacotes do Kubernetes, e "kraken helm" já é frase de busca densa significando "Helm chart de algum Kraken" |
| **kraken-board** | três repos já usam, e "board" em software significa quadro de tarefas — sugere o que o app não é |
| **briareus** | npm tomado, oito letras, e pronúncia ambígua em português |

O padrão que apareceu depois de ~50 nomes testados: **nome mitológico bonito e
óbvio já foi usado.** Sobra o que é bom mas menos óbvio.

### A mitologia, com a divergência explícita

Na *Ilíada*, Aquiles fala do monstro de cem braços *"que os deuses chamam
Briareu, mas os homens, Egeon"*. Ficamos com o nome dos mortais.

**Duas tradições concorrem, e é fácil confundi-las numa frase só** — foi o que a
primeira versão desta decisão fez:

| | Hesíodo / Homero | tradição marinha |
|---|---|---|
| pais | Urano e Gaia | **Gaia e Ponto**, ou filho de Tálassa |
| corpo | cem braços, cinquenta cabeças | braços que "dominam baleias" (Ovídio) |
| onde | com os irmãos Coto e Giges | no mar, governa Egeia na Eubeia |
| de que lado | **aliado de Zeus** contra os Titãs | **do lado dos Titãs**, inimigo de Posêidon |
| e ainda | — | **inventor dos navios de guerra** |
| fonte | *Teogonia*, *Ilíada* | *Titanomaquia* (perdida), Ion de Quios frag. 741, escólios a Apolônio de Rodes |

**Filho de Gaia** e **muitos braços** valem nas duas; o resto diverge. O
"inventor dos navios" — a parte que mais serve a uma ferramenta — pertence só à
versão marinha, aquela em que ele luta do lado que perdeu.

### O marcador é `[[ED:ok]]` / `[[ED:ask]]`

Iniciais do app, em maiúscula. Duas letras porque o marcador tem de caber numa
linha só: comprido, a TUI o quebra quando a janela é estreita, e marcador partido
em duas linhas não casa mais.

### A migração existiu e foi removida

`~/.mega-brain` foi **copiado** para `~/.egeon` — no nível do diretório, não
arquivo por arquivo. O código saiu do repo depois de cumprir o papel; o diretório
antigo continua no disco como backup manual, e não há mais nada apontando para o
nome velho.

Duas armadilhas de plataforma apareceram rodando, não lendo, e ficam registradas
porque valem para qualquer cópia de árvore de config no macOS:

1. **`copyItem` falha em socket unix** com `EOPNOTSUPP`, e o code-server deixa um
   dentro de `user-data/`. Pular só o nível de cima não basta: a cópia tem de ser
   recursiva e levar apenas diretório e arquivo comum.
2. **Uma falha abortava a cópia inteira**, e um diretório meio-copiado bastava
   para a condição "já existe" nunca mais tentar — `components.json` e
   `web-profiles.json` ficaram atrás. Conclusão marcada por arquivo próprio, e
   cada item falhando por conta própria, resolvem os dois.

E uma terceira, que é a menos óbvia das três: **valor de config gravado em disco
não muda quando o padrão do struct muda.** O marcador estava no `agents.json`, e o
decoder lê o arquivo. Trocar o padrão no código não alcança quem já tem o arquivo
— é preciso migrar o valor, e só o que casa exatamente com o padrão anterior, para
não atropelar quem escolheu o próprio.

---

## ADR-014 — A conversa do agente sobrevive ao rebuild, e segue quem você escolhe

**Decisão:** cada nó `agent` tem um `sessionId` próprio, gravado no
`sessions.json`. A estreia cria a conversa com esse id; as subidas seguintes a
retomam.

### O problema

Pelo [ADR-010](#adr-010--sem-tmux-o-terminal-morre-com-o-app) o terminal morre com
o app, então todo rebuild apagava a conversa. O histórico existia no CLI e o app
não sabia voltar nele — o campo `resume` estava no `agents.json` desde o começo e
nenhum código o lia.

### Por que o id é nosso, e não capturado

`--session-id` aceita um UUID que **nós** escolhemos, então não há nada a
capturar: o app grava antes de o processo existir. Capturar significaria raspar a
tela — que muda a cada release, o mesmo motivo do ADR-008 — ou caçar o `.jsonl`
mais recente em `~/.claude/projects`, que quebra com dois agentes na mesma pasta.

Pela mesma razão o id vive no NÓ e não é derivado do diretório: `--continue` pega
a conversa mais recente da pasta, e dois agentes na mesma worktree receberiam a
mesma.

### Criar e retomar são flags diferentes

Medido no Claude Code 2.1.229: `--session-id` num id que já existe responde
`Session ID ... is already in use` e sai com 1. Daí `newSession` ao lado de
`resume` no perfil, e um `sessionStarted` no nó para saber qual usar — sem ele a
estreia tentaria retomar o que não existe e mostraria "No conversation found"
antes de criar.

A linha fica `resume || cria`. Não é excesso de zelo: **disparou no primeiro teste
real.** Conversa sem nenhum turno não é persistida pelo CLI, então o nó que subiu e
não trocou mensagem falha no resume e é recriado com o mesmo id, em vez de deixar
o terminal morto.

O `||` obriga o zsh a ficar vivo em vez de dar exec no CLI, o que põe o agente um
nível mais fundo na árvore de processos. Testado se vaza: encerrando o app, zero
órfãos — o SIGHUP do pty leva o zsh e o neto junto.

### O app segue a SUA escolha

Escrever o id uma vez não basta: `/resume`, `/clear` ou fork feitos por você
dentro da TUI ficariam invisíveis, e o arranque seguinte desfaria a escolha.

O CLI avisa, por um gancho `UserPromptSubmit` que traz `session_id` no payload e
chama um script que faz um curl no socket que já existe. **`UserPromptSubmit` e
não `SessionStart`**: dispara a cada prompt, então o app se corrige no turno
seguinte mesmo que uma transição escape. `SessionStart` seria mais preciso e mais
frágil.

O arquivo de settings é nosso, passado por `--settings`. Nada é escrito no
`~/.claude/settings.json` do usuário. E isso não é só cortesia: `EGEON_TARGET` é
herdado pelo Bash do agente — verificado —, então um gancho instalado no settings
do projeto faria um `claude` aninhado reportar o id DELE e sobrescrever a conversa
do nó. O `--settings` é o que garante que só o processo de topo relate.

Verificado que `--settings` **soma** e não substitui: o `env` declarado no
settings do usuário continua valendo no Bash de um agente subido com o nosso
arquivo. Vale saber ao escolher o que se põe ali.

**Três regras do `UserPromptSubmit` que o script tem de respeitar**, lidas antes de
escrever porque nenhuma perdoa:

- o **stdout entra no contexto do prompt**. Uma linha solta ali vira texto que o
  agente lê em toda mensagem sua
- **exit 2 apaga o prompt** que o usuário acabou de digitar, e qualquer código
  não-zero mostra aviso na tela dele
- o hook **roda síncrono e bloqueia** o prompt. Daí `--max-time 1`: app fora do ar
  não pode fazer o usuário esperar

E o app só grava quando o valor muda de fato — senão seria uma reescrita do
`sessions.json` por mensagem.

### O que isso arruma de graça

O system prompt é passado de novo na retomada, e sobrevive — verificado. Então
catálogo de arestas novo e papel editado entram em vigor no restart, que era
metade da pendência "catálogo só é montado no arranque".

---

## ADR-015 — Dois flavors, para o app ser desenvolvido enquanto é usado

**Decisão:** estável e dev instalados lado a lado, isolados em tudo que grava ou
escuta.

**Motivo:** o app segura os pty direto (ADR-010), então todo rebuild mata as
sessões de agente em andamento — inclusive a sessão em que você está pedindo a
mudança. Com dois apps, o estável segura os agentes de verdade e o dev é o que se
derruba.

**Resolvido do bundle, não de flag de compilação.** É um binário só; o que muda é
o Info.plist que o `make.sh` escreve, e `Flavor.current` lê o sufixo do bundle id.
Trocar de flavor não recompila. Sem bundle (`swift run`), assume estável — o menos
surpreendente, e evita que um teste solto escreva no diretório do dev.

### O que precisou ser separado

`~/.egeon` e `~/.egeon-dev`, e com eles socket e log. Com um diretório só, o dev
subiria os MESMOS terminais nas mesmas pastas e os dois brigariam para gravar o
`sessions.json`.

**A porta do code-server, 8391 e 8392.** Este é o que não aparece numa busca por
caminho e seria o pior: o segundo a subir encontra a porta tomada, conclui que é
um órfão da execução anterior — que é o caso comum, e há código dedicado a
tratá-lo — e **mata o code-server do outro app**.

O socket dentro do `agent-hook.sh`, senão o agente do dev reportaria a conversa
dele para o estável, corrompendo o `sessions.json` em uso.

### O que NÃO se separa: a config de cada CLI

**Descartado — derivar `CLAUDE_CONFIG_DIR` por flavor** (`~/.claude-agro` →
`~/.claude-agro-egeon-dev`, com symlink para plugins e cópia de settings). Foi
implementado e funcionou — conversa do dev isolada, plugins compartilhados, medido
por `CLAUDE_CONFIG_DIR` do processo e pela contagem de conversas do estável — e foi
**removido de propósito**.

O Egeon Deck é um gerenciador de terminais com IA. A config de cada CLI é do
usuário, é análoga entre as instâncias, e duplicá-la põe o app no negócio de
gerenciar o Claude Code — que não é o dele. O preço concreto ficou claro na hora:
o Claude Code guarda a credencial no Keychain com um item **por pasta de config**
(`Claude Code-credentials-<hash>`), então cada pasta derivada nasce deslogada e
cobra um `/login`. Duplicar config para ganhar isolamento que ninguém pediu é
trocar um problema teórico por um atrito real a cada pasta nova.

A fronteira, então: o app separa **o que é dele** — `~/.egeon` e `~/.egeon-dev`,
com sessions, agents, templates, components, web-profiles, socket, log e porta,
cada um gerenciado pela instância que o criou. O que é da CLI fica como está.

O ícone, dessaturado no dev. Sem isso você fala com o app errado.

### Encerrar antes de tocar no bundle

`make.sh` faz `rm -rf` no bundle, e apagar o executável de um app vivo o mata na
validação de assinatura da página seguinte, pulando o `applicationWillTerminate` —
que é onde o `sessions.json` é gravado e o code-server encerrado.

Isto está registrado porque **custou uma vez**: o `install.sh` na primeira versão
avisava depois de rodar o `make.sh`, matou o app estável e os agentes junto. O que
salvou foi a gravação ser debounced e já ter rodado, mais o ADR-014 trazendo as
conversas de volta.

Script novo que mexa em bundle precisa encerrar primeiro, e encerrar todos os que
rodam daquele flavor — o de `build/` e o instalado são o mesmo app.

## ADR-016 — Mosaico é outra vista dos mesmos nós, não outro conjunto de nós

**Contexto.** O canvas é bom para montar e para enxergar a rede de agentes, e
ruim para trabalhar horas dentro de um editor: sobra grid onde deveria haver
código, e todo redimensionamento é manual. A pergunta era um segundo modo de
apresentação — VSCode à esquerda, terminais empilhados à direita, enchendo a
janela.

**Decisão.** Uma barra superior alterna entre `canvas` e `mosaic`. Nos dois modos
o card é o **mesmo `NodeView`**; o que muda é quem lhe dá o frame. A troca é um
`removeFromSuperview` seguido de `addSubview` no outro container.

**Por quê assim.** Porque reparentar uma view não toca no processo: o pty segue
ligado ao SwiftTerm e o WKWebView não recarrega. Medido ponta a ponta — um `echo`
disparado em mosaico e outro em canvas aparecem no MESMO scrollback do `/peek`, e
o editor registra uma única carga no log depois de quatro trocas de modo. A
alternativa óbvia — reconstruir os nós no layout novo — mataria todo agente em
andamento a cada clique, que é exatamente o que o ADR-010 já cobra caro no
rebuild.

**O que precisou sair do canvas.** O dono dos nós. Ele era `doc.subviews`, e com
dois containers disputando o mesmo card a sessão passava a parecer vazia para
todo mundo que contava nós pelo canvas: spinner do cabeçalho, `/geometry`,
persistência. A lista subiu para o `SessionShell`, que é também quem carrega a
barra e o banner.

**As quatro armadilhas, todas de geometria.**

`syncFrames` grava no `sessions.json` o que está na tela. Em mosaico o frame do
card é o do painel, e deixá-lo rodar achataria a montagem inteira do canvas — na
volta, cada nó nasceria do tamanho da coluna em que estava. Roda só em canvas, e
o shell guarda um retrato dos frames para restaurar.

Arrasto de cabeçalho e alça de resize chamam `onRequestSpace` e `onFrameChanged`,
que deslocam o mundo do canvas e persistem. Desligados por `isFreeform`, junto da
porta de aresta — não há espaço livre onde soltar uma ligação no mosaico.

`applyContentsScale` precisa ser refeito na entrada: o card chega com a escala do
último zoom do canvas, e sem reajustar o code-server aparece embaçado.

E o `NSSplitView`: painel nasce com frame zero, e o `adjustSubviews` distribui em
proporção ao tamanho anterior — de zero não sai proporção nenhuma. A primeira
versão deu **0pt de largura à coluna do editor** e 1350pt de janela vazios. Por
isso a distribuição inicial é escrita frame a frame (`MosaicSplit.spread`), e a
proporção salva é recusada quando alguma fração vem degenerada.

**Escopo.** Layout automático por tipo de nó — editor · terminais · web, ordem do
`sessions.json` dentro da coluna. Árvore de splits arrastável foi adiada: exige
drop zones, serialização de árvore e reparent no meio da árvore, e o arranjo
automático já é o que se queria montar à mão em 90% dos casos.

## ADR-017 — Worktree é por terminal, não só por sessão

**O que aconteceu primeiro.** Um dia de trabalho perdido, com o sintoma "os paths
dos terminais se embaralharam e as sessões também". A suspeita era o flavor dev
interferindo no estável. **Não era.** O isolamento de app estava completo —
diretório, socket, log, porta, PATH, ganchos do CLI, `user-data-dir` e
`extensions-dir` do code-server, store do WebKit por bundle id — e o dev nunca
escreveu em `~/.egeon`. O que embaralhou foi o fluxo de worktree, que acontece
igual sem o dev existir.

**A prova.** No `sessions.json` em uso, a sessão `develop-6` — worktree de
`nexus-web-app` — tinha um nó `nexus-backend` com `cwd: "../nexus-backend"`. Na
origem, `..` era a pasta de projetos e resolvia no repo do backend. Na worktree,
`..` passou a ser `.worktrees/nexus-web-app/`, que não tem backend nenhum. Os
quatro processos daquela sessão estavam **todos** na mesma pasta: o agente do
backend trabalhando no frontend, sem um erro em lugar nenhum.

**Os quatro defeitos, uma família.**

`relativized` só olhava `cwd` começando com `/` ou `~`, então `../nexus-backend`
atravessava a duplicação literal — e o comentário da própria função dizia o que
ela existia para impedir.

`directory(for:)` caía na raiz da sessão **em silêncio** quando o `cwd` não
resolvia. É este que transforma um caminho errado em "embaralhou" em vez de
"quebrou", e é o que custou o dia. Agora fala: log com o caminho tentado, e banner
listando os nós na hora de montar a sessão.

`ComponentDialog.relative` decapitava a barra de um caminho absoluto digitado no
campo de pasta — `~/Documents/x` virava `Users/você/Documents/x`, que nunca
resolve. Mesmo silêncio.

`--show-toplevel` devolve a raiz da worktree LIGADA quando você está dentro de
uma. Usá-la para criar a próxima aninhou worktree dentro de worktree, medido em
`.worktrees/back/.worktrees/so-o-back/vazamento`. Legal para o git, desastre em
disco: apagar a de fora leva a de dentro. Agora tudo passa por
`Worktree.mainRepo`.

**A decisão.** A worktree passa a ser por sessão **e por terminal**. Duplicar
lista todos os terminais com o repositório de cada um; a branch da sessão fica no
topo e re-sugere para quem você não editou. Terminal fora do repositório da
sessão, com a worktree recusada, **segue apontando para o repositório original** —
o que inverte o comportamento anterior, e por isso está aqui. Jogá-lo na raiz da
worktree transformava o card do backend numa cópia do card ao lado, que é
exatamente o estrago descrito acima.

Fora da duplicação, o botão direito no cabeçalho leva um terminal só. Reaponta em
vez de clonar: id, papel, arestas e posição continuam, o processo reinicia porque
pty não muda de diretório, e a conversa é zerada porque era da pasta antiga.

**Três defeitos que só a verificação ponta a ponta achou.** Nenhum deles aparece
em código que compila, e todos são anteriores a esta mudança:

*Shell interativo ignora SIGTERM.* `prepareForRemoval` mandava `terminate()` e
seguia em frente, e o `/bin/zsh -l` continuava vivo, filho do app, com a pasta
antiga. Medido: 7 processos para 6 nós depois de um reaponte. Agora escala para
SIGKILL no grupo — com guarda de `getpgid(pid) == pid`, porque se o pgid não fosse
o do shell o sinal poderia levar o app inteiro.

*O deinit apagava o registro do sucessor.* Trocar um card por outro com o mesmo id
— reconfigurar, reapontar — registra o novo antes de o antigo ser liberado, e o
`deinit` do antigo desfazia o registro do novo. `/targets` ficava vazio e o
terminal parava de receber dispatch, sem sinal nenhum.

*A ponta de escrita de um `Pipe` é herdada por qualquer processo lançado depois.*
`Worktree.run` lia com `readDataToEndOfFile`, que só retorna quando todas as
cópias do fd fecham. O script de cópia da worktree roda minutos fora da main
thread com `node_modules` no meio; herdada por ele, uma chamada de milissegundos
travava o app inteiro — 2min30 num `git rev-parse`, destravando no segundo em que
a cópia terminou. Agora a saída vai para arquivo temporário, cujo fd herdado não
prende ninguém.

## ADR-018 — A worktree abre na branch que você escreveu, mesmo que ela já exista

**O sintoma.** Sessão na `develop`, tarefa numa `AGROS-3323` que já existia e
tinha trabalho dentro. Pedir worktree para `AGROS-3323` produzia uma worktree na
branch `AGROS-3323-2` — nova, vazia, saída do HEAD da `develop`, sem uma linha do
que estava na branch de verdade. Sem erro, e o nome trocado só aparecia no log.

**Por que fazia isso.** `freeBranch` existia para não colidir: nome ocupado ganhava
sufixo. E `Worktree.create` só sabia um caminho — `worktree add -b <nova> <pasta>
HEAD` —, então "a branch já existe" era sempre um problema a contornar, nunca uma
resposta. A recusa do git em ter a mesma branch em duas worktrees virava
`branchInUse` com o texto "escolha outro nome", quando "ela já está aberta ali, e
é essa pasta que você quer" é justamente o que se precisava ouvir.

**A decisão.** O nome pedido vai como veio, e é ele que decide o caminho:

| o nome | o que acontece |
|---|---|
| não existe | nasce do HEAD da origem — o comportamento antigo |
| existe local, livre | a worktree abre **nela**, no commit dela |
| só existe no remoto | a local nasce seguindo `origin/x` |
| já aberta em outra worktree | nada é criado; é aquela pasta |

O último caso deixa de ser erro e passa a ser reaproveitamento (`Created.reused`).
`freeBranch` sumiu — sufixo automático é a forma de o app entregar algo que
ninguém pediu.

**O que muda de junto.** Worktree reaproveitada não recebe a cópia do que o
`.gitignore` esconde: passar `.env` e `node_modules` por cima de uma pasta com
trabalho dentro é estragar o que se pediu para reusar. E o stash das mudanças não
commitadas só é aplicado quando a branch nasce agora: em branch com histórico
próprio ele pode conflitar, e resolver conflito numa pasta recém-aberta não era o
pedido — o objeto do stash fica criado e o log diz o comando para aplicá-lo à mão.

**Dizer antes de fazer.** Como as quatro saídas mudam o que o botão faz, o
formulário ganhou uma linha embaixo do campo de branch que se atualiza a cada
tecla: qual dos quatro casos é, de onde a worktree sai, e o que acontece com as
mudanças não commitadas. Laranja quando não é branch nova. Com a branch já aberta
em algum lugar, o campo da pasta vira leitura — ela não é escolha — e, se aquela
pasta já for uma sessão do app, a linha avisa pelo nome: dois code-servers na
mesma pasta e dois agentes editando sem saber um do outro continuam permitidos,
mas não em silêncio. O botão passou de "Criar" para "Abrir" pelo mesmo motivo.

O `git worktree list` + `branch` + `for-each-ref` é lido **uma vez** por
formulário, em `Worktree.index`: perguntar por tecla digitada seriam três
processos por caractere na thread que segura o modal. O índice também roda
`worktree prune` quando encontra registro cuja pasta foi apagada à mão —
reaproveitar um desses mandaria a sessão para um caminho que não existe.

**Verificação.** Pelo socket, que é o único jeito de exercitar um fluxo que passa
por `NSAlert`: `/worktree?target=…&branch=…` devolve `path` e `reused`, e a pasta
vem da sessão que nasceu, não do que o formulário sugeriu — com branch existente
as duas divergem, e é essa divergência que precisa ser conferível.

## ADR-019 — O editor pergunta quem pode acionar a partir da pasta dele

**Dois defeitos no mesmo botão.** O "Request changes" da extensão resolvia o alvo
uma vez e gravava no settings do workspace. Nó apagado ou renomeado deixava ali um
endereço morto, e o app respondia "alvo desconhecido" — para sempre, porque a
extensão insistia no mesmo valor gravado. A única saída era o comando de escolher
alvo, que nem aparece na preview. E a lista oferecida na primeira vez era global:
o editor de um projeto oferecia terminal de outro, que não tem nada a ver com o
arquivo aberto.

**A decisão.** `GET /targets?folder=<pasta>` responde os terminais da sessão dona
daquela pasta, com a lista inteira em `all` ao lado. O filtro é do **app** de
propósito: a extensão só conhece a pasta do workspace, e com worktree o nome da
sessão não sai do nome da pasta. Quem casa as duas é o `AppDelegate`
(`AppControl.sessionOwning`) — primeiro pelas pastas que os nós de editor de fato
abriram, que é resposta exata, e só depois por prefixo do caminho da sessão, onde
o mais longo ganha: senão a worktree perde para o checkout principal.

Conferir usa a lista inteira; sugerir usa a da sessão. Atravessar sessão é
legítimo, e apagar essa escolha a cada envio seria desfazer na surdina o que o
usuário pediu — as outras ficam atrás de um "outra sessão…" na escolha. Alvo que
sumiu do `all` é limpo do settings, e o próximo clique pergunta em vez de repetir
a falha; o app rejeitando na entrega limpa também, porque o nó pode morrer entre a
conferência e o envio.

A troca de alvo passou a ser um badge com o endereço na barra da preview — antes
só a paleta de comandos fazia isso, e ela não aparece para quem está lendo o
documento renderizado.

`/targets` também deixou de listar terminal morto: o card continua na tela e pode
reviver, mas oferecê-lo como destino é oferecer um buraco — a fila enche e ninguém
lê.

**O degrau para o app velho.** Bundle anterior a esta rota responde 404 a
`/targets?folder=`, e sem tratamento a extensão nova concluiria "nenhum terminal
ativo" contra um app cheio de terminais vivos. `listTargets` cai para a lista
global nesse caso e devolve `scoped: false`, e o título da escolha para de
prometer um escopo que não existe.

## ADR-020 — No formulário de worktree, a branch por terminal é o único controle

**Revisa a UI do ADR-017**, não a decisão dele: worktree continua sendo por sessão
e por terminal. O que muda é o que o formulário pergunta.

**O que estava errado.** Cada linha de terminal tinha uma caixinha "criar worktree
própria" ao lado do campo de branch, e o formulário — o da sessão e o de um
terminal só — tinha um campo de **pasta da worktree** editável. Três problemas:

1. **Estado com duas representações.** Marcado com a branch da sessão escrita não
   quer dizer nada; desmarcado com outra branch escrita mente sobre o que vai
   acontecer. Duas caixas para uma decisão só.
2. **Terminal dentro da sessão não podia divergir.** A caixinha vinha desabilitada
   e o campo de branch escondido, com "segue a worktree da sessão". Mas divergir é
   um caso real e frequente: a tarefa é no front, e no meio dela aparece um ajuste
   pequeno no back — que quer branch própria, não a da sessão.
3. **A pasta era escolha sem consequência boa.** Dava para apontar a worktree para
   qualquer lugar do disco, e ninguém precisa disso: a convenção
   (`<pai do repo>/worktrees/<repo>/<branch>`) é o que torna a pasta previsível e
   fácil de apagar. Pior, com a branch já aberta em outra worktree o campo virava
   somente-leitura — então metade das vezes ele não era escolha nenhuma.

**A decisão.** Uma linha por terminal, e nela só a branch:

| o que você escreve | o que acontece |
|---|---|
| a branch da sessão | vai junto com ela, pelo `cwd` relativo |
| outra branch | worktree própria, no repositório **daquele** terminal |
| nada | fica no repositório original |

Vale igual para shell, agente e editor — quem abre pasta entra na lista, e nenhum
fica atrás por causa do tipo. `web` continua fora: não abre pasta nenhuma.

Terminal **dentro** do repo da sessão com outra branch ganha worktree própria do
mesmo repo. É o caso do "ajuste no back" quando back e front moram no mesmo
checkout, e o git aceita: duas worktrees do mesmo repositório em branches
diferentes. Na mesma branch ele não pode ganhar pasta própria — aí seriam duas
worktrees para a mesma branch, e o git recusa a segunda.

O campo de pasta saiu dos dois formulários. Continua **visível**, como texto: é
informação de conferência, e some junto com a chance de errar. Com a branch já
aberta em worktree, mostra aquela pasta — que é o que o ADR-018 já dizia.

**Verificação.** `/worktree` ganhou `&nodes=back:fix/api,sub:spike`, que é o mesmo
que digitar nas linhas. Sem isso o caminho novo não teria como ser verificado de
fora — as linhas moram num `NSAlert`, e é a mesma razão pela qual a rota existe.
Quatro cenários rodados contra repositórios de verdade: padrão (sessão + vizinho),
branch por terminal (um nó de dentro em worktree própria do mesmo repo), branch
vazia (fica onde está) e terminal solto.

## ADR-021 — Remover a sessão oferece apagar TODAS as worktrees dela

**O defeito.** A remoção chamava `Worktree.remove` uma vez, no caminho da sessão.
Desde o worktree por terminal (ADR-017) uma sessão pode ter aberto worktree em três
repositórios, e as outras duas ficavam no disco e registradas no git, sem nada na
tela que lembrasse delas. Pior: a caixinha só aparecia quando a **pasta da sessão**
era worktree — terminal que ganhou worktree pelo botão direito, numa sessão que é o
checkout principal, não era nem mencionado.

**A decisão.** O diálogo levanta toda worktree **ligada** que a sessão usa — a dela
e a de cada nó que abre fora dela — e lista, por linha, repositório · branch · quem
usa. Uma caixinha só, para todas. Nó dentro da pasta da sessão não entra: é a mesma
worktree, e removê-la duas vezes erraria na segunda. Checkout principal nunca entra:
oferecer apagá-lo seria oferecer apagar o repositório.

**Worktree que é pasta de outra sessão fica.** Apagá-la levaria trabalho de quem não
foi consultado, e a outra sessão continuaria na lista apontando para o vazio. Ela
aparece na lista marcada como MANTIDA, com o nome da sessão dona — dizer por que
algo não vai ser apagado importa tanto quanto dizer o que vai.

O aviso de perda passou a ter uma seção por worktree. Com três repositórios
envolvidos, somar os números num total só não diria em qual deles está o trabalho
que você não quer perder. E se alguma remoção falhar, a sessão **não** sai da lista:
o diálogo diz o que já foi apagado e o que resistiu, em vez de deixar você sem a
sessão e com a pasta.

**Verificação.** `GET /remove?target=ws[&worktrees=1]` faz a remoção sem diálogo —
mesma razão de `/worktree` existir. Sem `worktrees=1` nada em disco é tocado; é
`worktree remove --force` do outro lado, e o padrão de uma rota destrutiva tem de
ser o inofensivo. Rodado contra repositórios de verdade: sessão com três worktrees
em dois repos (a dela, uma de nó no mesmo repo, uma em repo vizinho) — as três
identificadas, as duas dela apagadas do registro do git e do disco, e a
compartilhada com outra sessão preservada.

## ADR-022 — A pasta das worktrees não começa com ponto

`<pai do repo>/.worktrees/<repo>/<branch>` virou `<pai do repo>/worktrees/…`.

O ponto fazia uma coisa só: esconder a pasta do Finder. E worktree é pasta que se
abre à mão — para arrastar arquivo, olhar build, conferir o que ficou. Esconder o
que se precisa abrir troca um problema pequeno (uma pasta a mais na lista) por um
chato (`⌘⇧.` toda vez, ou `defaults write` mostrando todo arquivo oculto do sistema).

As três coisas que o ADR-017 queria continuam: fora do repositório, agrupada por
repositório, previsível. É o agrupamento que faz a pasta ser fácil de achar e de
apagar, não o ponto.

**Descartado — `~/worktrees/<repo>/<branch>`,** raiz única no home, que é o que
gerenciadores de worktree usam. Junta grupos de projeto que não têm nada em comum, e
manda a worktree para outro volume quando o repositório está em disco externo.

**Descartado — `<repo>-<branch>` irmão do repositório**, o padrão dos scripts
caseiros: uma pasta por branch no meio dos repositórios de verdade, que é exatamente
o que se queria evitar.

Worktree criada antes disto continua onde está e funcionando — o git guarda caminho
absoluto, e a sessão guarda o `cwd`. Por um tempo as duas pastas coexistem; mover as
antigas é `git worktree move` mais reescrita de `cwd`, e não vale automatizar por
enquanto.

## ADR-023 — No mosaico, o arranjo é arrastado, não derivado do tipo

**Revisa o ADR-016.** O mosaico continua sendo outra vista dos mesmos nós; o que
muda é quem decide onde cada um fica.

**O que estava errado.** A coluna de um card saía do tipo dele — editor à esquerda,
terminais no meio, web na ponta — e a ordem dentro da coluna era a do
`sessions.json`. Reordenar era editar o arquivo à mão. Para uma bancada de trabalho
isso é o avesso do útil: quem está lendo o diff quer o editor grande à esquerda, e
quinze minutos depois quer o agente que está falando naquele lugar. Trocar dois
cards de lugar não deveria passar por um editor de texto.

**A decisão.** Arrastar o cabeçalho de um card sobre outro troca os dois de painel,
em qualquer direção, inclusive entre colunas. O painel que vai receber acende antes
de soltar — sem isso o gesto é cego, e você descobre com quem trocou depois de já
ter trocado.

O arranjo passa a viver em `mosaic.slots`, ids de nó por coluna. Nulo, ou com id que
não está mais na sessão, cai na regra de tipo — que segue sendo o arranjo de quem
nunca arrastou nada. Cobertura parcial é o caso normal, não exceção: você cria um
terminal depois de ter arrumado a tela, e ele entra na coluna de quem é do mesmo
tipo sem desfazer o resto.

**Troca, e não inserção.** Os dois cards existem e os dois painéis existem, então
trocar preserva a contagem de painéis por coluna — e com ela as proporções que você
já arrastou. Inserir mudaria o número de linhas de duas colunas ao mesmo tempo e
jogaria fora os dois conjuntos de frações, o que faz a tela dar um pulo a cada
reordenação. O mínimo de largura de uma coluna passou a ser o MAIOR entre os nós
dela: depois de uma troca o editor pode ser o segundo card, e abaixo de 520pt o
workbench perde o explorer.

**Resize.** O divisor desenha 8pt para ler como espaço entre os cards, e a mão erra
isso. A área efetiva de arrasto sai 6pt para cada lado
(`splitView(_:effectiveRect:forDrawnRect:ofDividerAt:)`), então o cursor aparece
antes de você acertar o fio — e o corpo do card não perde nada, porque esses 6pt
são de margem.

**Verificação.** O gesto de mouse não é dirigível de fora: evento sintético exige
permissão de Acessibilidade, que a assinatura ad-hoc perde a cada build (ADR-003).
Então `/mosaic?target=ws&swap=id1,id2` faz a troca por id, que é o que tem risco —
arranjo, mínimos e persistência. Verificado no dev com troca entre colunas de
tamanhos diferentes: `slots` gravado, geometria dos três cards casando com ele, e o
contador de trocas parado quando ninguém mexe (o eco do `publish` de volta pelo
`sessions.json` não remonta nada).

## ADR-024 — O aviso nasce de gancho do CLI, e cadeia entre agentes não te chama

**Decisão:** os dois avisos vêm dos ganchos `Stop` e `Notification` do CLI, pela
rota `/activity`. A leitura de tela deixa de ser gatilho e vira qualificador. Fim
de turno de um terminal que acabou de acionar um vizinho não avisa nada.

### O problema

O [ADR-011](#adr-011--precisa-de-você-vem-de-um-marcador-que-nós-pedimos-não-da-tela)
montou três camadas sobre a tela e o pty, e as duas de cima acendiam sozinhas.

A **camada 3** (silêncio depois de uma rajada de `minWorkMs`) não distingue
trabalho de qualquer outra coisa que escreva por dois segundos: um `npm test`
rodando dentro do agente, um `/resume`, a TUI se redesenhando. Tudo virava
"precisa de você".

A **camada 1** (marcador ao vivo) era pior, porque acendia no instante da
ENTREGA. Medido:

```
10:47:15 dispatch[nitidez/claude]: entregue (0 restando)
10:47:16 atenção[nitidez/claude]: terminou — por marcador ao vivo, rajada de 1.5s
```

Um segundo depois de o turno COMEÇAR, o app anunciou que ele tinha acabado. A
assinatura do marcador é o marcador mais as três linhas acima dele, e o texto
colado empurra o marcador do turno passado tela acima: as linhas em volta trocam,
a assinatura muda, e a defesa contra "marcador velho" — que era justamente essa
assinatura — desmonta sozinha sem o agente ter escrito nada.

E as duas paradas tinham o mesmo peso: borda laranja e som tanto para "terminei"
quanto para "dependo de você". Aviso que dispara o dia inteiro para as duas
coisas deixa de ser aviso.

### A rota: quem sabe o que aconteceu é o programa

O mesmo movimento do ADR-011, levado até o fim. Lá se parou de adivinhar o
*desenho* do CLI e se passou a pedir um sinal ao **modelo**; aqui se para de
adivinhar o *ritmo* dele e se passa a perguntar ao **programa**. O canal já
existia inteiro — o `claude-hooks.json` que vai por `--settings` e o
`EGEON_TARGET` no ambiente —, faltava usar mais dois eventos:

| gancho | quando dispara | vira |
|---|---|---|
| `Stop` | o turno acabou | `/activity?event=stop` |
| `Notification` | o CLI está pedindo permissão | `/activity?event=ask` |

O `Notification` fecha o buraco que o marcador nunca alcançou e que a camada 2
(`attention.patterns`) cobria com regex mantida à mão: o diálogo de permissão é
desenhado pelo programa, não é mensagem do modelo, e por isso nenhum marcador
chega lá. Agora chega, e sem casar pixel nenhum.

**O marcador não sai — muda de papel.** Ele era o gatilho; passa a ser o
qualificador. O gancho diz **quando** o turno acabou; a tela, lida naquele
instante, diz **qual dos dois** foi: `[[ED:ask]]` visível é pergunta, o resto é
fim de tarefa.

Em quem tem gancho, as camadas que liam a tela **calam** — e calam desde o
arranque, não a partir do primeiro relato. Quem monta a linha de comando é o app:
ele já sabe quem leva `--settings`, e descobrir isso empiricamente custava uma
janela. Entre a subida e o primeiro prompt a tela ainda mandava, e é exatamente
ali que mora a conversa RETOMADA, com o fim do turno anterior redesenhado.

Não é redundância barata que se perde: elas erravam para mais, e o custo de um
falso positivo aqui é o mesmo do alarme de carro.

Terminal que não leva gancho — shell, outro CLI, `cmd` trocado por outro programa
— continua exatamente como antes. É o único jeito de não ficar cego onde o canal
não existe.

### O recap, e por que a tela não serve nem como rede

O CLI gera um resumo quando você volta depois de um tempo fora. É texto do
**modelo**, então obedece o protocolo e escreve marcador; e como o resumo termina
dizendo qual é o próximo passo, o marcador que sai costuma ser `[[ED:ask]]`. Um
terminal livre passava a dizer "precisa de você".

Medido com `/recap` num terminal do dev: o recap aparece na tela com marcador e
**não dispara gancho nenhum** — nem `UserPromptSubmit`, nem `Stop`. Isso fecha a
questão de onde ele pode fazer estrago: só na tela.

Foi por isso que a primeira tentativa de defesa saiu do código. Era uma trava no
`Stop` — "turno que não responde a prompt nenhum é texto que o agente gerou
sozinho, ignore" — e protegia de um caminho que o recap não usa, enquanto criava um
jeito novo de PERDER aviso de verdade: um `UserPromptSubmit` que se perdesse
deixava o `Stop` seguinte mudo, e mudo é o defeito caro. Trocada pelo `speaksHooks`
desde o arranque, que ataca o lugar certo.

Cheguei a pôr `"ccrRecap": false` no settings que o app escreve, para o recap nem
existir nos terminais que o app dirige. Saiu de novo, e o motivo vale registrar: a
medição acima já diz que quem tem gancho está protegido, então a chave não comprava
nada — e é chave não documentada num arquivo que sobe em TODO terminal de agente.
O que esse arquivo quebrar, quebra tudo de uma vez. Risco sem contrapartida não
entra.

### `Notification` são dois avisos num, e só um interessa

Ele dispara para permissão **e** para "você sumiu há 60s". O segundo não traz
notícia nenhuma: o fim do turno já veio pelo `Stop` e ali já se decidiu se valia
chamar. Sem separar, toda cadeia silenciada voltava a apitar um minuto depois.

A separação não olha o texto da mensagem — casar string do CLI é o que estes ADRs
vêm evitando. Olha o **estado**: permissão interrompe trabalho, então o terminal
está `working`; a ociosidade só pode existir depois que o turno acabou, com o
terminal já parado.

Tentei antes cortar pelo relógio — "saiu byte há menos de dez segundos é
permissão" — e não segura: no minuto da ociosidade a TUI está redesenhando, o
byte é recente, e o aviso passava. Pior, passava **calado**: com o latch já
armado pelo `Stop`, o `attend` não reanuncia nem loga, só troca o estado — e o
card virava laranja sem uma linha no log dizendo por quê. Foi assim que apareceu,
numa barra lateral marcando dois em atenção com um dos dois exibindo `[[ED:ok]]`
na tela.

### As duas paradas não pesam igual

`asking` interrompe: borda laranja, `●` laranja na barra lateral, som. `waiting`
é `● terminou` em verde, sem borda e sem som — você lê quando olhar, e "terminou"
não é urgente por definição: se fosse, alguém estaria esperando.

A mesma bolinha nos dois, separada pela cor. Glifo diferente (`✓` para um, `●`
para outro) obriga a ler o cabeçalho; a cor se reconhece de longe, que é
justamente quando o aviso serve — com o zoom afastado ou pelo canto do olho.

Isso pediu uma correção na barra lateral, que comparava só o TEXTO antes de
redesenhar, para não repintar a cada quadro do spinner. Com a mesma bolinha em
dois estados, `●` laranja e `●` verde viraram a mesma string: a sessão que
terminasse e depois passasse a perguntar ficaria verde para sempre.

### Os três avisos convivem

Uma sessão tem vários nós, e é normal ter um rodando, um te esperando e um que já
acabou. A barra lateral mostrava só o mais urgente — e como a laranja ganhava
sempre, o que ficava escondido era justamente se ainda há trabalho em curso.

Agora os três aparecem juntos, encostados na direita da linha, em ordem FIXA:
spinner, laranja, verde. Ordenar por urgência faria a bolinha trocar de lugar
conforme a sessão anda, e badge que se move é badge que se procura em vez de se
reconhecer.

### O verde some ao entrar ou sair da sessão

"Terminou" não pede nada de você: chegar na sessão já é ter visto, e sair dela
também — ela estava na sua frente. Então trocar de sessão apaga o verde das duas
pontas, a que você abre e a que você deixa.

O laranja não cai assim, e é a diferença que importa: ele espera que você olhe o
TERMINAL. Passar pela sessão não é ler a pergunta que ele te fez, e apagar o aviso
sem que você a tenha lido é perder o pedido.

### Cadeia entre agentes não te chama

Um agente falando com outro é conversa entre eles. Se A aciona B e B responde a
A, nada disso é assunto seu — mas se B para porque precisa de uma permissão, é.

A regra não lê o que o agente escreveu. Ler texto de agente para decidir foi
descartado pelo [ADR-012](#adr-012--agente-aciona-agente-por-aresta-desenhada-nunca-por-encaminhamento)
e pelas guardas de cadeia, pelo mesmo motivo: é o próprio agente que escreve, e
guarda pendurada em texto dele não é guarda. O que o app usa é um fato que ele
mesmo observou — **este terminal acionou um vizinho neste turno?** O `egeon send`
passa pelo `Dispatcher`, então a resposta é dele, não de ninguém mais.

- **pergunta** → avisa sempre, cadeia ou não. Permissão não se delega, e é
  justamente por ela que o vizinho precisa de você.
- **fim de turno** → avisa **só se o terminal não acionou ninguém**. Acionou,
  passou o bastão: o trabalho continua no card do outro.

A tentação era usar a cadeia que o pedido já carrega — "veio de agente, então
cala". Erra o caso mais comum: em `A→B→A`, o A que fecha o trabalho está atendendo
uma mensagem de agente, e é exatamente o momento em que você quer saber. Quem
acerta os dois é o handoff, porque ele pergunta pela SAÍDA, não pela entrada.

Um terminal que recebe de outro, termina e não responde a ninguém avisa — é ponta
de linha, e cadeia que morre em silêncio é pior que aviso a mais.

### Verificado

Dois agentes ligados nos dois sentidos, no flavor dev. `A` recebeu um pedido meu,
consultou `B`, `B` respondeu, `A` fechou:

```
10:50:14 dispatch[nitidez/claude]: entregue        ← e nenhum aviso durante 15s
10:50:30 cadeia[nitidez/claude → nitidez/claude-2]: envio 1/2
                                                   ← A terminou aqui, e calou
10:50:43 cadeia[nitidez/claude-2 → nitidez/claude]: envio 1/2
                                                   ← B terminou aqui, e calou
10:50:47 atenção[nitidez/claude]: terminou — por gancho Stop, rajada de 4.1s
```

Um aviso para a tarefa inteira, no fim dela. E com `B` parando para perguntar em
vez de responder:

```
10:51:25 cadeia[nitidez/claude → nitidez/claude-2]: envio 1/2   ← A calou
10:51:40 atenção[nitidez/claude-2]: precisa de você — por gancho Stop
```

O falso positivo da entrega não aparece mais em nenhum dos dois.

### O que se perde

Gancho que não chega ao app custa o aviso daquele turno, porque a rede da tela
está desligada em quem leva gancho. É o preço de não ter os dois: enquanto a tela
valia como rede, ela acendia sozinha — e alarme que dispara sem motivo custa mais
que aviso que falta, porque o primeiro te ensina a ignorar todos.

O `~/egeon.log` registra cada gancho recebido (`gancho[endereço]: prompt|stop|ask`),
então "o CLI parou de relatar" é uma pergunta com resposta em vez de um silêncio
inexplicável.

## Decisões ainda abertas

- **Assinatura de código.** Enquanto for ad-hoc, qualquer coisa que dependa de
  TCC quebra a cada build. Só vira problema de novo se o portal voltar.
- **Duas sessões na mesma pasta de projeto.** Vale entre flavors e entre duas
  sessões do mesmo flavor: dois checkouts do mesmo lugar, dois code-servers vigiando
  os mesmos arquivos. O worktree por terminal (ADR-017) é a saída para quem quer
  separar; não há guarda impedindo. Aviso só no formulário de worktree, quando a
  branch pedida já está aberta numa pasta que é sessão (ADR-018) — abrir a mesma
  pasta por outro caminho segue silencioso.
- **Reordenar nó dentro da coluna do mosaico.** Hoje a ordem é a do
  `sessions.json`, e mudá-la é editar o arquivo.
- **Um code-server para todos os workspaces, ou um por workspace.** Um só é mais
  leve; um por workspace isola travamento e facilita perfis distintos.
- **Zoom no nó de editor.** WKWebView sob transform fica borrado. Alternativa
  conhecida: manter o webview vivo em zoom ≈ 1 e trocar por bitmap quando afasta
  (truque padrão de canvas com embed).

## ADR-025 — As barras flutuam sobre o canvas, em vidro, e a de sessões recolhe

**Decisão:** a barra de sessões deixa de ser uma coluna fixa e passa a flutuar
sobre o conteúdo, em `NSGlassEffectView`. A barra do canvas e o banner de aviso
ganham o mesmo vidro. A barra de visualização, no topo, fica opaca e encostada
como estava.

**Por que vidro de verdade e não uma imitação.** `NSGlassEffectView` existe a
partir do macOS 26, e a máquina é 26.5. Copiar o efeito com camadas e alfa dá um
retângulo cinza que não reage ao que passa por trás — e aqui o que passa por trás é
justamente o trabalho: terminal branco, editor, página web. O `contentView` entra
como `contentView` do efeito, e nunca por `addSubview`: o header da AppKit é
explícito em que só ele tem z-order garantido dentro do vidro, e o sintoma de
errar isso é uma barra que desaparece sem erro nenhum.

**O interruptor.** `EGEON_GLASS=0` volta as três barras para o fundo semiopaco de
antes, sem rebuild. Vidro reamostra o backdrop a cada quadro, e essas barras ficam
por cima de cards que redesenham dez vezes por segundo com cinco agentes
trabalhando — se algum dia isso custar caro, a saída não pode depender de recompilar.
O mesmo caminho serve de fallback abaixo do macOS 26, então o alvo do pacote
continua em 14.

**Sombra com `shadowPath` explícito.** O vidro desenha em camada própria, e o
AppKit tira a sombra do canal alfa da camada — que aqui está vazio. Sem o
`shadowPath`, a barra fica sem sombra e volta a parecer mais um nó pousado no grid.

**Onde a barra pousa depende do modo.** No canvas ela FLUTUA e o conteúdo não cede
nada: o grid vai até a borda da janela e corre por baixo do vidro. No mosaico ela fica
AO LADO do container, que cede a largura de verdade — ali os cards dividem a janela
inteira, e sobreposição significa terminal coberto. Recolher, no mosaico, devolve
180pt aos cards.

**Faixa reservada é moldura cinza.** A primeira versão reservava no canvas a largura
do trilho, para o grid não passar por baixo do vidro. O efeito foi o contrário do
pretendido: a faixa é pintada com o fundo da `RootView`, cinza neutro 0.09, e o
documento do canvas é azulado (0.06/0.07/0.09) e mais escuro — media-se (27,27,27)
contra (19,22,28). O resultado era um L cinza em volta do vidro, com cara exata de
resto da barra antiga. Flutuar não é "quase encostar": ou o conteúdo passa por baixo,
ou aparece a moldura. No mosaico o problema não existe porque o fundo do shell é o
mesmo 0.09 da raiz.

**O título da barra de cima recua sozinho.** Com o conteúdo indo até a borda, a barra
de visualização passou a correr por baixo dos botões da janela, e o nome da sessão
cairia em cima deles. Quem decide o recuo é a POSIÇÃO — `convert(.zero, to: nil).x` do
shell —, e não o modo: assim o `RootView` continua sendo o único dono de onde a sessão
começa, sem um segundo lugar combinando o mesmo por convenção.

Foi flutuante nos dois modos por algumas horas, com a barra recolhida no mosaico para
não cobrir nada. Não se sustentou: abrir a barra em mosaico é justamente quando você
quer ver a lista, e ali ela caía em cima do painel que você estava lendo.

**O topo desvia dos botões da janela.** A barra começa em y=44. Com
`fullSizeContentView` os semáforos moram no canto superior esquerdo, e vidro por
baixo deles fica ilegível. Antes disso quem desviava era o cabeçalho de 66pt da
própria barra, que agora pode ser curto porque a barra não passa mais por ali.

**Recolher é só a sua escolha.** ⌘/ ou o botão no cabeçalho da barra, e nada mais:
nem o modo, nem o mouse. Barra fechada só abre por clique ou tecla.

**Descartado: abrir no hover.** Chegou a existir, com 0,18s de atraso para não
escancarar a barra quando o mouse só passava a caminho de um card. Duas coisas
mataram: com a barra ao lado no mosaico, a razão de ser dela — não cobrir nada —
deixou de existir; e barra que se abre sozinha é barra que se abre na hora errada,
porque o caminho até o card mais à esquerda passa exatamente por cima dela. Junto com
o hover saíram o `NSTrackingArea` refeito a cada layout, o timer, e a distinção entre
estado pegajoso e estado na tela — três coisas que só existiam para o gesto.

**Botão além da tecla.** Atalho não se descobre olhando a tela, e barra que recolhe
sem dizer como voltar é barra que alguém vai achar que quebrou. O ícone é o
`sidebar.leading`/`trailing` do sistema, que é o idioma que o Finder e o Xcode já usam.

**⌘/ é cedido dentro do editor.** No workbench a tecla comenta linha, e key
equivalent de menu é consultado ANTES do responder chain: habilitado com o cursor lá
dentro, ⌘/ deixaria de comentar. `SessionShell.focusIsInsideEditor` decide — e mora no
shell, não no canvas, porque em mosaico o canvas está fora da hierarquia e `window`
seria nulo, respondendo sempre falso. No terminal a tecla não tem dono, e ali a barra
continua respondendo, que é o caso comum: o foco vive num terminal.

**No trilho as bolinhas continuam.** É o ponto que quase se perdeu: uma sessão
inativa não desenha nada na tela, e a linha da barra é a única pista que ela tem
(ADR-011, ADR-024). Então o trilho mantém os três avisos, em 10pt sob a pastilha, e
o que a largura tira é o NOME — que vira a inicial numa pastilha de 26pt. O aro da
pastilha carrega o resto: laranja de "te espera" vence o verde de "está de pé",
porque um pede coisa e o outro só informa.

**Verificação.** `/sidebar?collapsed=0|1|auto|toggle` existe pelo mesmo motivo que
`/mosaic?swap=` (ADR-023): a barra recolhe por tecla de menu, clique e hover, e
nenhum dos três é dirigível de fora — evento sintético exige permissão de
Acessibilidade, que a assinatura ad-hoc perde a cada build (ADR-003). `toggle` cobre
exatamente o caminho do ⌘/ e do botão.
Com ela, screenshot de tela real no dev mostrou o que precisava ser respondido: o
vidro **amostra o `WKWebView`** — a barra fixada por cima do card do code-server
mostra o conteúdo dele desfocado, sem buraco preto, que era o risco real de
composição fora do processo. Verificado também o trilho com terminal em trabalho
(spinner sob a pastilha, aro verde), três `toggle` seguidos alternando, e — por número,
não por screenshot, porque o app estava em uso — o card mais à esquerda andando
exatamente 180pt no mosaico ao recolher, e 0pt no canvas, que é a diferença entre
ceder espaço e flutuar. A moldura cinza foi diagnosticada e conferida por AMOSTRA DE
PIXEL no bitmap de `/shot?target=window`: o que era (27,27,27) em volta do vidro virou
o azulado do canvas, e a coluna vertical mostra a barra de cima até y=46, canvas de 46
a 54, e o painel a partir de 54.

---

## ADR-026 — Arrastar arquivo para o terminal injeta o caminho, colado

**Decisão:** o `MBTerminalView` passa a ser destino de arrasto. Soltar arquivos
sobre um terminal escreve os **caminhos** na caixa de input dele, sem Enter. Em
terminal com IA o texto entra como **paste**; em shell, como digitação. Imagem
arrastada de dentro do navegador — que vem como PNG ou TIFF cru, sem arquivo do
lado de cá — é gravada num rascunho em `$TMPDIR/egeon-drop/` e o que entra é o
caminho dela.

**O que estava quebrado.** O SwiftTerm não implementa `NSDraggingDestination` em
nenhuma das views do `Mac/` — nenhum `registerForDraggedTypes`, nenhum
`performDragOperation`. O arrasto era engolido pela janela sem sinal nenhum, e a
única forma de dar uma imagem a um agente era descobrir o caminho dela à mão e
digitar.

**Colado, e não digitado — o padrão do CLI.** O Claude Code já tem um caminho para
isso, e a telemetria dele o chama de `input_image_drag`: ele espera que o terminal
insira o caminho num **paste**, e é só ali que a detecção roda. O texto colado é
quebrado por `/ (?=\/|[A-Za-z]:\\)/` — espaço antes de caminho absoluto — e por
`\n`; cada pedaço perde as aspas que o envolvem (`"` ou `'`), desfaz escape de
barra invertida (`\ ` → espaço, preservando `\\`) e é testado contra
`/\.(png|jpe?g|gif|webp)$/i`. Casando, o CLI lê o arquivo, converte BMP, ajusta ao
orçamento de bytes, e chama `onImagePaste` com `{mediaType, filename, dimensions,
sourcePath}`: o caminho **desaparece** da caixa e no lugar dele fica `[Image #1]`,
com a imagem anexada de verdade. Não casando — ou falhando a leitura —, o pedaço
volta como texto, que é exatamente o que se quer para `.pdf` ou `.swift`.

Isso decide o modo de injeção, e não é preferência de estilo: digitado byte a byte,
o mesmo caminho fica texto cru na caixa e o agente precisa abrir com `Read`. O drop
segue então o `injectConfig.mode` do perfil — `bracketed-paste` em terminal com IA,
`plain` no shell, onde o marcador volta literal (ADR-007). Um interruptor próprio
seria uma segunda fonte de verdade para a mesma pergunta.

**Por que não o clipboard.** Havia um caminho de fidelidade igual e mais curto:
escrever o PNG no `NSPasteboard` e mandar `0x16` — no macOS, um paste **vazio** faz
o CLI ler a imagem direto do clipboard, que é como o ctrl+v (`chat:imagePaste`)
funciona. Descartado por dois motivos: sobrescreve o clipboard do usuário, que não
é do app para gastar, e vale só em terminal com IA, enquanto metade dos cards aqui
é shell comum, onde o que serve é o caminho. Uma regra que vale nos dois tipos de
terminal ganha da que vale em um.

**Áudio ficou de fora porque o CLI o desligou.** O vocabulário existe — `[Audio
#N]`, regex de `mp3|m4a|wav|ogg|opus|flac|aac|webm` — mas no input do chat a versão
2.1.235 passa `onAudioPaste: void 0`. Arrastar um `.wav` hoje entrega o caminho como
texto, e é o máximo que há para entregar.

**Sem Enter, e o foco vai junto.** Arrastar é entregar o arquivo, não mandar o
agente trabalhar: quem submete é você, depois de escrever a frase que acompanha.
Por isso o texto termina em espaço, e por isso o drop toma o first responder — sem
isso o caminho cai neste card e o teclado continua no card de onde você veio, com
a frase indo para o terminal errado.

**Aspas só quando precisam.** Citar sempre seria mais simples, mas do outro lado
nem sempre há shell: no terminal com IA o caminho é lido por um modelo, e `'…'` em
volta é ruído que não protege nada. Caminho sem espaço nem caractere de shell vai
cru; o resto vira `'…'` com `'` interno virando `'\''` — que o `Xqa` do CLI desfaz
e o zsh também. Resta uma borda conhecida: caminho citado com um espaço seguido de
barra (`'/tmp/a /b.png'`) é quebrado pelo split do CLI antes do unquote, e degrada
para texto em vez de virar anexo.

**Rascunho fora de `~/.egeon`.** A pasta de configuração é feita para ser aberta e
editada à mão — todo arquivo dela é seu. PNG despejado ali só atrapalha quem for
ler, então a imagem sem arquivo vai para o temporário do sistema, em pasta por
flavor. O nome leva milissegundos e não segundos: duas imagens arrastadas em
seguida ganhariam o mesmo nome, e a segunda apagaria a primeira antes de o agente
ter lido qualquer uma.

**Verificação.** Duas metades, as duas medidas.

O que o arrasto produz foi verificado por um harness que usa o MESMO `Drop.swift`
contra um `NSPasteboard` real: arquivo simples sai cru; caminho com espaço e
apóstrofo sai citado, e o `eval` num shell de verdade resolveu o arquivo certo;
dois arquivos saem separados por espaço; TIFF cru virou PNG em disco com magic
`89504e470d0a1a0a`; texto puro é recusado por `accepts`.

O que o CLI faz com aquilo foi verificado num pty próprio, subindo o `claude` de
verdade fora do app e sem nunca mandar Enter — nada foi submetido. Colado, a tela
mostrou `Pasting…` e depois `[Image #1]`, com o caminho fora da caixa: virou anexo.
Digitado byte a byte, o mesmo caminho ficou na caixa como texto e nenhum `[Image
#N]` apareceu. É a diferença que o `dropAsPaste` carrega.

O gesto em si não é dirigível de fora — evento sintético exige Acessibilidade, que
a assinatura ad-hoc perde a cada build (ADR-003) —, então o drop registra no log o
caminho que injetou, e é ali que o arrasto de verdade se confere.

---

## ADR-027 — O microfone é pedido pelo app, porque o TCC não pergunta ao CLI

**Decisão:** o `Info.plist` que o `make.sh` escreve passa a levar
`NSMicrophoneUsageDescription`. É o que faltava para o modo de voz do CLI
funcionar dentro de um terminal do Egeon.

**O sintoma.** `/voice` não funcionava, e não havia erro à vista. O motivo é que o
macOS atribui o microfone ao processo **responsável** — o bundle que iniciou a
cadeia —, e não a quem chamou a API. Quem grava é o módulo nativo do CLI, filho de
um pty que este app segura: para o TCC, quem pede é o Egeon Deck. Sem a chave não
existe negativa nem diálogo, e o que acontece é pior — o sistema **aborta** o
processo. Medido com um binário de teste rodado de dentro de um terminal do app, e o
relatório de crash é explícito:

```
namespace: TCC
"This app has crashed because it attempted to access privacy-sensitive data
 without a usage description. ... NSMicrophoneUsageDescription"
responsibleProc: EgeonDeck
```

É por isso que o mesmo `claude` grava no Terminal.app: aquele bundle tem a chave, e
o diálogo aparece em nome dele.

**O CLI já tinha uma saída, e ela não serve para nós.** Para sessões `--bg` ele cria
um `ClaudeCode.app` com a chave e se re-executa com `macDisclaimResponsibility`,
soltando a responsabilidade do pai (`CLAUDE_BG_TCC_DISCLAIMED`). Sessão interativa
não passa por ali, e não há como pedir de fora que passe.

**Segurar espaço não exige nada do terminal.** Era o outro risco, e não se
concretizou: o push-to-talk não depende de evento de key-release — que num pty não
existe — nem do protocolo de teclado do Kitty. O CLI conta os espaços do auto-repeat
(`Fds === L$.repeat(Fds.length)`) e usa um timeout de silêncio como "soltou". O que
o SwiftTerm já entrega basta.

**A permissão morre a cada build.** O TCC guarda por identidade de código, e a
assinatura ad-hoc gera uma nova em cada build — a mesma dor do ADR-003. Com
`EG_SIGN_ID` apontando para um certificado fixo, a concessão sobrevive.

**Verificação.** Antes: exit 134 e relatório de crash com `responsibleProc:
EgeonDeck`. Depois, com o mesmo binário despachado por `/dispatch` para um shell do
app dev e lido por `/peek`: `status inicial: notDetermined` · `requestAccess: true`
· `status final: authorized`.
