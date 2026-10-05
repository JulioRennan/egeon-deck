---
name: protocolo-entre-agentes
description: O mapa completo da camada de coordenação e segurança entre agentes do Egeon Deck — marcadores [[ED:ok]]/[[ED:ask]], ganchos do CLI, o comando `egeon`, as guardas de cadeia (aresta, maxSends, maxVisits, fila) e o envelope de procedência. Consultar antes de mexer em Dispatch, Notifications, EgeonCLI, EdgeConfig, ou em qualquer coisa que decida "quem chama quem" e "quando o usuário é avisado".
---

# Protocolo entre agentes do Egeon Deck

Cada nó agente é um terminal com um CLI de IA dentro. O app **não lê a tela**
para saber o que o agente está fazendo (ADR-008/011): ele pede ao modelo um
sinal próprio, recebe ganchos do CLI, e só deixa agente acionar agente por
aresta desenhada, com limites que o texto do prompt não consegue burlar
(ADR-012/024). Esta skill lista cada peça, onde mora e a regra exata.

Caminhos relativos a `app/Sources/EgeonDeck/`.

## 1. Fim de turno — o marcador `[[ED:*]]`

| peça | onde | regra |
|---|---|---|
| `MarkerConfig` | `Features/Nodes/Features/AgentNode/Models/AgentProfile.swift` | `done = "[[ED:ok]]"`, `ask = "[[ED:ask]]"`, `wait = "[[ED:wait]]"`, `enabled = true`; instrução em `defaultInstruction`, `{done}`/`{ask}`/`{wait}` substituídos em `resolvedInstruction` (instrução antiga sem `{wait}` ganha `waitLine`). `latest(in:)` devolve o mais baixo dos três. ASCII curto numa linha só: TUI estreita quebra marcador longo. |
| injeção | `…/ClaudeCode/Models/ClaudeProfile.swift:20` | `["--append-system-prompt", "{prompt}"]` — vai no system prompt, não gasta turno. Perfil sem `systemPrompt` (codex/gemini/opencode) não recebe marcador. |
| leitura | `Features/Dispatch/Controllers/Dispatcher.swift` `verdict(from:)` (~l.511) | Espia as últimas 24 linhas do pty. Com mais de um marcador na tela, vale o **mais baixo** (mais recente). Sem marcador, cai em `questionPatterns` do perfil; sem nada → `.unknown` ("silêncio"). |
| limpeza no chat | `…/ClaudeCode/Models/ClaudeTranscript.swift:134` | Regex `\[\[ED:(ok|ask|wait)\]\]` removida do texto exibido — marcador é para o app, não para quem lê. |

Semântica que o agente recebe (é o texto que aparece no seu próprio system
prompt quando você roda dentro do Deck):

- `[[ED:ok]]` — terminei e não dependo de você.
- `[[ED:ask]]` — parei e dependo de resposta sua (dúvida, escolha, permissão,
  informação). **Pergunta ao usuário ⇒ sempre `ask`.**
- `[[ED:wait]]` — parei, mas deixei trabalho rodando em segundo plano (comando
  em background, subagente, vizinho acionado) e volto sozinho (ADR-063).
- Um marcador só, sozinho, na última linha.

## 2. Ganchos do CLI → estado do terminal

Gerados a cada arranque em `~/.egeon*/` (`agent-hook.sh`, `claude-hooks.json`)
por `…/ClaudeCode/Controllers/ClaudeHooks.swift`. O script faz POST no socket
**sem dizer quem é**: o app resolve o terminal pelo pid da conexão, como no
`egeon` (ADR-040). `EGEON_TARGET` no ambiente só diz "estou dentro do Egeon";
`target=` na query é reserva (curl seu, script antigo) e deixa linha no log.
Antes o alvo ia cru na URL e bancada com espaço ("SPEI + SPI") sumia sem log.

| gancho Claude Code | `HookEvent` | rota | efeito em `Target.hookReported` |
|---|---|---|---|
| `SessionStart` | `.start` | `/activity?event=start` | `sessionUp = true`. Com gancho, o terminal fica `.starting` ("preparando") até isto chegar (teto `bootCeiling` 45 s), nunca menos que `warmupMs`. (ADR-034) |
| `UserPromptSubmit` | `.prompt` | `/conversation?id=&transcript=` | `turnInFlight = true`; informa o `conversationId` aberto (ADR-014). Não é aviso. |
| `Stop` | `.stop` | `/activity?event=stop&transcript=<path>` | `turnInFlight = false`; gancho diz **quando**, marcador no **transcript** diz **qual** (`ClaudeTranscript.lastMarker`, `settleStop`): linha mais velha que o `prompt` do turno → relê a cada 250 ms até 6×; sem transcript → tela. `ask` → `.asking`, `wait` → `.background` (latch `inBackground`), senão `.waiting`. Linha deste turno sem marcador também relê — o `Stop` chega antes da linha final (ADR-034/063). Assentado, chama `AppControl.turnEnded` → `ClaudeTranscript.lastTurn` → `ChatHistory.append` (ADR-037). |
| `Notification` (`matcher: permission_prompt`) | `.ask` | `/activity?event=ask` | Só vale se `turnInFlight || working || starting` — separa "pedido de permissão" (antes do Stop) do "você sumiu há 60s" (depois). → `.asking`. |

`HookEvent` é enum tipado (`Features/Notifications/Models/HookEvent.swift`):
evento desconhecido morre na borda do socket com `expected = "stop|prompt|ask|start"`.

### `Activity` (`Features/Notifications/Models/Activity.swift`)

| estado | rótulo | cor | interrompe? |
|---|---|---|---|
| `starting` | ⟳ preparando | acento | não — na Sidebar conta em `ActivitySummary.starting`, não em `working`; bancada só com estes mostra "preparando bancada…" |
| `ready` | — | acento | não |
| `working` | ⟳ trabalhando | acento | não |
| `background` | ⏳ em segundo plano | acento | não — trabalho de fundo; contagem própria no resumo (`ActivitySummary.background`), ⏳ na barra e nas abas. Cai com `prompt`, `Stop`, entrada nova (ADR-063) |
| `waiting` | ● terminou | verde | **não** — você lê quando olhar |
| `asking` | ● precisa de você | laranja | **sim** — som (`AttentionConfig.sound`, padrão `Tink`) |
| `dead` | ✕ processo encerrado | vermelho | não |

`needsAttention == (self == .asking)`. Tratar "terminou" como alarme virava
barulho de fundo (ADR-024).

### Latches no `Target` (Dispatcher.swift)

- `attentionHeld` — aviso não resolvido. **Não cai por tempo**; só com entrada
  nova: você olhando o terminal, você digitando, ou prompt entregue pelo
  Dispatcher (`inputArrived()`).
- `announced` — assinatura da última parada; garante **um som por turno**.
- `handedOff` — este terminal acabou de acionar um vizinho; seu próximo
  `waiting` vira `ready` em silêncio (`attend`, ~l.455). Pergunta (`asking`)
  ainda chama: permissão não se delega.
- `doneSeen` — mesmo efeito para `waiting` depois de já ter mostrado "terminou".
- **Com gancho (`speaksHooks`), `working = turnInFlight`** — byte no pty não
  vira spinner (redraw de foco/cursor não é trabalho). Sem gancho: `idle.ms`
  (1500) de silêncio, `warmupMs` (4000), `liveCheck` pelo marcador na tela,
  `minWorkMs`.

## 3. O comando `egeon` (agente → app)

`Core/Features/EgeonCLI/Controllers/EgeonCLI.swift`, regenerado em
`~/.egeon*/bin/egeon`. Curl no socket unix; **não recebe identidade**: o app
descobre quem fala pelo pid do outro lado da conexão
(`Peer.pid(of:)` → `Peer.owner` → `Target.target(callingOn:)`).

| subcomando | rota | resposta |
|---|---|---|
| `egeon peers` | `GET /peers` | lista `{address, cli, role}` das arestas **saindo** do chamador (`peers(of:)`). Vazia = ninguém ligado agora; muda em tempo real. Conexão fora de terminal → `[]`. |
| `egeon send <endereço> <<'MB' … MB` | `POST /message?target=` (endereço percent-encoded por `enc()`) corpo = texto puro (heredoc, sem JSON para o agente não errar escape) | `enfileirado para X; N na fila; envio a/b` ou erro de guarda |
| `egeon peek <endereço> [linhas]` | `GET /peek?target=&lines=` | o que o vizinho exibe agora, sem interromper. `Dispatcher.mayPeek`: de dentro de um terminal só alcança quem está em `peers(of:)` (ou ele mesmo) — 403 `não existe ligação de você para 'X'`; de fora (origem nil) alcança qualquer nó (ADR-054) |
| `egeon status` | `GET /status` | quem ELE é e como está: `address`, `role`, `workbench`, `cli`, `model`, `pending`, `peers`. Fora de terminal: `"esta conexão não veio de um terminal"` |
| `egeon trace [texto]` (ou heredoc) | `POST /trace` corpo = texto puro | `{ok, address, file}`; anexa em `workbenches/<WorkbenchConfig.id>/trace.md` com carimbo hora · endereço (pid) · CLI · modelo · conversa (`AppControl.nodeIdentity`, ADR-036). Vazio → 400; fora de terminal → 403. O system prompt pede uma chamada ao fim de TODO turno, antes do marcador. No Claude Code o comando passa pela permissão de Bash: `Bash(egeon:*)` em `permissions.allow` (README, seção do `egeon`). |

`resolve(_:siblingOf:)`: agente pode escrever só o `id` do vizinho; o app
completa `bancada/id` — barrar por isso seria pedantismo.

### Os comandos do maestro (ADR-066)

Só respondem a nó com `NodeConfig.maestro == true` (o checkbox do formulário,
ou `GET /maestro?target=&on=1` **de fora** — de dentro de um terminal a rota
recusa, senão um agente se promoveria). Quem chama sai do pid, como sempre.

| subcomando | rota | o quê |
|---|---|---|
| `egeon bench` | `GET /maestro/bench` | `MaestroSnapshot.bench` — nós no vocabulário do plano (`cli`, `role`), `state` (`working`/`background`/`idle`/`done`/`asking`…), arestas, regras, `you` |
| `egeon models` | `GET /maestro/models` | `MaestroSnapshot.models` — por CLI do `agents.json`: modelos do catálogo (ADR-064) com `efforts`, `configs` |
| `egeon plan` | `POST /maestro/apply?dry=1` | `MaestroPlanner.plan` sem efeito; devolve o resumo e a bancada resultante |
| `egeon apply` | `POST /maestro/apply` | valida e aplica: commit → dispose/restart/spawn → arestas → persist → trilha |
| `egeon guide` | — (embutido no script) | `MaestroGuide.text`, o mesmo da skill `egeon-maestro` |

Regras do planejador (todas com teste em `MaestroPlanTests`): plano vale inteiro
ou nada (erros acumulados, 422); chave desconhecida é erro; campo ausente mantém,
`null` volta ao padrão; o maestro não entra em `nodes`/`remove`; `maestro` não é
campo do plano; nó em turno (`working`) não reinicia nem sai; em segundo plano só
com `"force": true`; agente novo nasce com `maestro ↔ novo` (`maxSends` padrão,
ajustável no mesmo plano); regras da bancada reiniciam os outros agentes, nunca o
maestro. **A guarda 1 (aresta) tem uma exceção: o maestro.** `MaestroLinks.effective`
soma às arestas desenhadas as implícitas maestro → todo agente/shell e agente →
maestro, sem `maxSends` (só o `maxVisits` vale); `AppControl.workbenchEdges`
devolve essas, então `link(from:to:)`, `peers(of:)` e `mayPeek` as enxergam, e o
canvas não as desenha. Plano que cria/remove nó rearruma o canvas
(`MaestroLayout`, `"layout"` no plano). Shell entra como alvo de
verdade: `cmd` no plano, aresta só maestro → shell, e `egeon send` para shell
chega cru (`DispatchRequest.message(from:toShell:)`, sem envelope e sem
`handedOff`).

## 4. Guardas de cadeia (`Dispatcher.dispatch(_:from:)`)

`origin == nil` (extensão VSCode, seu `curl`, teste, composer do chat) **é
você**: cadeia nova, entrega direta, nenhuma guarda. Todo o resto passa, nesta
ordem:

| # | guarda | fonte | erro devolvido ao agente (`DispatchError`) |
|---|---|---|---|
| 0 | alvo existe | `targets[request.target]` | `alvo desconhecido 'X'. disponíveis: …` |
| 1 | **aresta obrigatória** `from → to` | `link(from:to:)` em `EdgeConfig` da bancada (`Features/Canvas/Models/EdgeConfig.swift`; nasce bidirecional, ADR-028) | `não existe ligação de A para B — desenhe a aresta no canvas` |
| 2 | **fila do destino** `< 5` | `maxPendingFromAgents = 5` | `cadeia recusada: X ainda tem N mensagens por ler. Espere ele responder antes de mandar outra.` |
| 3 | **`maxSends` da aresta** — vezes que ESTA seta disparou nesta cadeia | `EdgeConfig.maxSends`, padrão `defaultSends = 2`; `nil` = ∞ (mostrado como `↻ ∞` na aresta) | `cadeia recusada: a ligação A → B já disparou N× nesta conversa (cadeia). Volte a falar com o usuário.` |
| 4 | **`maxVisits` da bancada** — vezes que o DESTINO aparece na cadeia | `WorkbenchConfig.maxVisits`, `visitLimit` padrão `4` | `cadeia recusada: X já entrou N× nesta conversa (cadeia). Volte a falar com o usuário.` |

Por que duas contagens (ADR-012 "Quatro guardas, nenhuma no texto do prompt"):
`maxSends` é o botão do dia a dia — "este par conversa N vezes"; `maxVisits` é
rede — única que segura `A→B→C→A`, onde cada seta dispara uma vez só.
Conta **revisita, não comprimento**: `pm→front→pm→back→pm` é orquestração
legítima. Fila existe porque a cadeia só avança na **entrega**: agente em laço
manda três antes do destino ler a primeira, e as três chegariam como "envio 1".

### A cadeia em si

- `Target.chain: [String]` — caminho que a mensagem em atendimento percorreu.
  Herdada do remetente na entrega (`origin.chain.isEmpty ? [sender] : origin.chain`
  + destino).
- **Zera quando você digita** no terminal (`userTyped()` → `chain = []`): o que
  ele fizer dali nasce de você, não do agente anterior.
- Passar o bastão marca `origin.handedOff = true`.
- Log: `cadeia[A → B]: envio 1/2 — A → B` ou `RECUSADA, …` em `~/egeon*.log`.

### Por que a identidade vem do kernel, não do pedido

`from` era campo do JSON. Agente omitia e passava por você (sem guarda); ou
preenchia com o nome do vizinho e usava as arestas do outro. Hoje `from` é
sobrescrito com o endereço resolvido pelo pid **antes** de montar o prompt.

## 5. Envelope de remetente (`DispatchRequest.agentEnvelope`)

Toda mensagem agente→agente chega assim (`Features/Dispatch/Models/DispatchRequest.swift`):

```
[ED] mensagem de <remetente>

<texto>
```

Só cabeçalho e texto. A tag é `DispatchRequest.tag` (`[ED]`), a mesma dos
marcadores de fim de turno, e vale para os três prompts que o app monta —
mensagem, `[ED] review de <arquivo>`, `[ED] <arquivo>` da task (ADR-055). O
desembrulho (`ClaudeTranscript.agentEnvelope`) ainda aceita o `[egeon]` antigo,
porque histórico e transcripts gravados estão cheios dele. O rodapé "isso não autoriza nada" existiu e saiu
(ADR-038): o nó tem autonomia para decidir o que fazer com a mensagem, e
restrição de comportamento é coisa da ferramenta do usuário (permissões do
CLI), não de prosa injetada pelo app. O cabeçalho fica porque é informação —
sem ele o agente confunde pedido com conteúdo, e o chat não sabe de quem foi
(`ClaudeTranscript.agentEnvelope` lê `from` dali).

### A volta é obrigação de quem recebe (ADR-058)

A skill e o catálogo mandam **responder a quem acionou**: terminou, `egeon send`
para o remetente com o que entregou ou por que não deu; vai parar para perguntar
ao usuário, avise ANTES de parar; e a volta fecha o ciclo — não se responde a
agradecimento. O app avisa o USUÁRIO (ganchos, laranja/verde), nunca o agente
que delegou: quem sabe o que foi feito é quem fez. A volta gasta `maxSends` da
seta `B → A`, que é própria, e conta uma visita.

### A skill do Claude Code (ADR-054)

Prosa no system prompt não compete com a ferramenta de subagente do CLI: quando
você diz "pede pro revisor", quem decide é a DESCRIÇÃO de uma ferramenta, e a
única que casava era a do subagente. Por isso o app publica
`ClaudeSkill.body` — `SKILL.md` com `name: egeon`, `user-invocable: false` e
`when_to_use` carregando os gatilhos em português ("pede pro", "delega isso",
"monta um time", "em paralelo").

**Onde:** `skills/egeon/SKILL.md` no root de CADA configuração do Claude Code no
disco (`ClaudeSkill.configDirectories`: o `configGlob` `~/.claude*` mais a do
ambiente). Skill é por configuração, e o formulário do nó deixa escolher qual o
terminal usa — escrever numa só deixaria sem skill o agente apontado para a
outra. É a única coisa que o app escreve na config do usuário, e a exceção é
consciente: `--add-dir` (a alternativa) entra como skill de projeto, sombreia com
a pessoal e não alcança nó com `cmd` trocado. Reescrita a cada arranque, como
`bin/egeon` e `claude-hooks.json`; o corpo avisa que é gerado. Guardada por
`ClaudeSkillTests`.

### A ordem do system prompt (ADR-056)

`AgentProfile.systemPromptText(role:catalog:rules:)` monta, nesta ordem:
**marcador** (formato) → **catálogo** (topologia) → **PAPEL** (`NodeConfig.prompt`)
→ **REGRAS** (`AgentRules.block`, que soma `WorkbenchConfig.rules` e
`NodeConfig.rules`). As regras por último não é arranjo: diretriz geral em
conflito com restrição específica é resolvida a favor da ação, então a restrição
tem de vir depois do que ela limita — e `AgentRules.header` diz a precedência.
Editar regras reinicia o agente (`sameProcess` no nó, `restartAgents` na
bancada); a conversa fica.

Texto que o agente vê no system prompt sobre a topologia:
`main.swift:~1403` ("Este terminal é um nó do Egeon Deck e tem vizinhos
endereçáveis…") — instrui `egeon peers`/`send`, avisa que lista vazia é normal,
que endereço fora da lista é recusado, e que cadeia longa demais também: nesse
caso, **voltar a falar com o usuário**.

## 6. Rotas do socket (`Core/Controllers/ControlSocket.swift`)

`curl --unix-socket ~/.egeon-dev/sock http://eg/<rota>`

| rota | quem chama | papel |
|---|---|---|
| `POST /dispatch` (JSON `DispatchRequest`) | extensão, chat, testes | entrega de você; `kind: review\|task\|raw` |
| `POST /message?target=` (texto) | agente via `egeon send` | entrega com guardas |
| `GET /peers` | agente via `egeon peers` | topologia saindo do chamador |
| `GET /maestro/bench` · `/maestro/models` · `POST /maestro/apply[?dry=1]` | maestro via `egeon bench/models/plan/apply` | montar a bancada (ADR-066) |
| `GET /maestro?target=&on=1\|0` | você (só de fora) | liga/desliga o maestro de um nó; reinicia o agente |
| `POST /activity?target=&event=stop\|ask` | `agent-hook.sh` | estado do terminal |
| `POST /conversation?target=&…` | `agent-hook.sh` (`UserPromptSubmit`) | `conversationId` aberto |
| `GET /status` | agente | estado do próprio terminal |
| `POST /trace` (texto) | agente via `egeon trace`; shell via `preexec` (`ShellHook`, `ZDOTDIR`) | trilha da bancada, carimbada |
| `POST /chat/clear?target=<bancada>` | você | arquiva `chat.jsonl` em `chat-archive/` e começa outra conversa (ADR-037) |
| `POST /workbench/clear?target=<bancada>` | você (o menu da bancada, sem diálogo) | `AgentProfile.clear` (`/clear`) pela fila do Dispatcher em todo agente que declara, + arquiva o chat como `chat-<início>_<fim>.jsonl` e a trilha como `trace-archive/trace-<início>_<fim>.md` (ADR-037) |
| `GET /targets` | você | endereços conhecidos |
| `GET /edge?…` | você | ler/editar arestas e `maxSends` |
| `GET /peek?target=` | você | o que o terminal exibe |
| `GET /chat?target=ws[&focus=id][&scroll=]` · `/layout?mode=` | você | modo chat / trocar vista |

## 7. Fluxo resumido de um turno com acionamento

```
você digita em A ──► chain=[]; attentionHeld=false
A trabalha ──► working
A roda `egeon peers` ──► [B]           (aresta A→B existe)
A roda `egeon send B` ──► guardas 0–4 ──► B.enqueue(envelope, chain=[A,B])
                                        A.handedOff=true
A termina, escreve [[ED:ok]] ──► hook Stop ──► waiting, mas handedOff ⇒ ready, sem som
B recebe prompt quando idle+warmup ──► working
B escreve [[ED:ask]] ──► hook Stop ──► asking ──► laranja + Tink   (pergunta chama)
B tenta `egeon send A` 3ª vez ──► tooManySends (limite 2) ──► "Volte a falar com o usuário."
```

## 8. Testes existentes (`app/Tests/EgeonDeckTests/`)

`HookEventTests` (enum/expected) · `EdgeLinkTests` (maxSends, par bidirecional)
· `EdgeControllerTests` · `DispatchRequestTests` (envelopes) ·
`AgentProfileTests` (decode tolerante, `MarkerConfig`) · `ActivityTests` ·
`WorkbenchConfigTests` · `TranscriptMarkerTests` (marcador + timestamp lidos da
cauda do transcript) · `TraceTests` (carimbo da entrada, um arquivo por bancada,
ordem entre agentes) · `ChatHistoryTests` (corrente na raiz, arquivo, dedupe,
`lastTurn` com cauda cortada).

**Sem teste hoje**: as quatro guardas em `dispatch(_:from:)` (`sendCount`,
`visitLimit`, fila), `verdict(from:)`, `attend`/latches. Mudança ali nasce com
teste — é a regra do CLAUDE.md.

## 9. ADRs que sustentam tudo isto (`docs/01-decisoes.md`)

- **ADR-007** — injetar na sessão viva, não `claude -p`.
- **ADR-008** — ocupação por silêncio, nunca por parsing de tela.
- **ADR-009** — agente plugável (`agents.json`).
- **ADR-011** — "precisa de você" vem de marcador pedido, não da tela.
- **ADR-012** — agente aciona agente por aresta desenhada; quatro guardas fora do prompt; padrões 2/4.
- **ADR-013** — o nome e o marcador `[[ED:ok]]`/`[[ED:ask]]`.
- **ADR-014** — conversa sobrevive ao rebuild (`UserPromptSubmit` → `/conversation`).
- **ADR-024** — aviso nasce de gancho do CLI; cadeia entre agentes não te chama, pergunta sim.
- **ADR-028** — par é uma linha só, nasce bidirecional.
- **ADR-029** — modo Chat: transcript do CLI como fonte (marcador removido do texto).
- **ADR-032** — socket é dono do arquivo dele.
- **ADR-034** — com gancho, estado por turno e marcador pelo transcript; byte só sem gancho.
- **ADR-038** — envelope sem rodapé de aviso; restrição é da ferramenta do usuário, guardas estruturais ficam.
- **ADR-040** — gancho identificado pelo pid da conexão, como o `egeon`; `EGEON_TARGET` não é identidade.
- **ADR-063** — `[[ED:wait]]`: parou com trabalho de fundo; ampulheta, sem som.
- **ADR-066** — maestro: um nó que monta a bancada por plano JSON validado inteiro.
- **ADR-039** — turno em curso lido ao vivo da cauda do transcript (só enquanto `working`); a bolha do chat desenha a cadeia na ordem.

`docs/03-spec-chat.md` — o chat como vista dessa mesma conversa.
