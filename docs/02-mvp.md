# Egeon Deck — escopo do MVP

Base: as decisões em [01-decisoes.md](01-decisoes.md). Alvo macOS, uso pessoal.

> **Estado:** entregue. A [ordem de construção](#ordem-de-construção) fechou nos
> cinco passos, e o que veio depois está em [Depois do MVP](#depois-do-mvp).
> "Workspace" virou **sessão** — mesmo conceito, nome que aceita duas frentes no
> mesmo repositório.

## O que o MVP entrega

Um app com **sessões na barra lateral**. Cada sessão tem um canvas com nós:

- **1+ editor** — code-server apontando para a pasta do workspace
- **N terminais com IA** — cada um roda um agente CLI e é endereçável por id
- **N terminais comuns** — shell normal, para build/log/git

E um fluxo de **request changes** sobre arquivos `.md` que o agente escreveu:
você comenta inline no diff, aperta um botão, os comentários viram um prompt
único na sessão viva do agente.

## Modelo de nós

Um vocabulário só:

| tipo | o que é | endereçável por dispatch |
|---|---|---|
| `editor` | WKWebView com code-server | não |
| `shell` | terminal comum (SwiftTerm + pty) | sim |
| `agent` | **terminal com IA** — shell rodando um agente CLI | sim |
| `web` | navegador no canvas, com perfil de navegação próprio | não |

`agent` é um `shell` com perfil de agente anexado. A diferença não é o terminal —
é que ele sabe como injetar prompt (bracketed paste), como detectar ocupação
(silêncio) e como se anunciar na UI. Nada no código menciona um agente
específico.

Os dois seguram o pty direto, sem tmux ([ADR-010](01-decisoes.md#adr-010--sem-tmux-o-terminal-morre-com-o-app)):
fechou o app, os terminais morrem. Toda a criação de pty vive num arquivo só,
para que trocar por tmux mais tarde seja mudança localizada.

## sessions.json

`~/.egeon/sessions.json` — era `workspaces.json`, migrado no primeiro
arranque, com o arquivo antigo preservado onde está.

```jsonc
[
  {
    "name": "deck",
    "path": "~/Documents/projetos/deck",
    "nodes": [
      { "type": "editor", "id": "code" },

      { "type": "agent",  "id": "claude-1", "agent": "claude",
        "cwd": "deck-backend" },

      { "type": "agent",  "id": "claude-2", "agent": "claude",
        "cwd": "deck-web-app" },

      { "type": "shell",  "id": "back",  "cwd": "deck-backend",
        "cmd": "make dev" },

      { "type": "shell",  "id": "front", "cwd": "deck-web-app",
        "cmd": "npm run dev" }
    ]
  }
]
```

Endereço de dispatch é `workspace/id` — `deck/claude-1`. Estável, independe de
título de janela ou de ordem na tela.

## Perfis de agente

`~/.egeon/agents.json`. Trocar de agente é editar este arquivo.

```jsonc
{
  "claude": {
    "displayName": "Claude Code",
    "command": ["claude"],
    "idle": { "strategy": "silence", "ms": 1500 },
    "inject": { "mode": "bracketed-paste", "submit": "\r" },
    "resume": ["--resume", "{sessionId}"]
  },

  "codex": {
    "displayName": "Codex CLI",
    "command": ["codex"],
    "idle": { "strategy": "silence", "ms": 1500 },
    "inject": { "mode": "bracketed-paste", "submit": "\r" }
  },

  "opencode": {
    "displayName": "OpenCode",
    "command": ["opencode"],
    "idle": { "strategy": "silence", "ms": 1200 },
    "inject": { "mode": "bracketed-paste", "submit": "\r" }
  }
}
```

Campos que existem porque agentes divergem:

- `inject.mode` — `bracketed-paste` para TUI; `plain` para CLI que lê linha a linha
- `idle.strategy` — hoje só `silence`; deixa espaço para `prompt-pattern` se
  algum agente vier com marcador confiável de fim de turno
- `resume` — opcional, só para quem suporta retomar sessão
- `systemPrompt` — como passar texto no system prompt pela linha de comando.
  Ausente = o CLI não sabe receber, e o que iria nele vira primeira mensagem

## Carregando e "precisa de você"

Cada terminal tem um estado, deduzido do pty ([ADR-011](01-decisoes.md#adr-011--precisa-de-você-vem-de-um-marcador-que-nós-pedimos-não-da-tela)):

| estado | no cabeçalho do nó | quando |
|---|---|---|
| `starting` | `⠹ subindo` | processo subiu, ainda no `warmupMs` ou sem primeiro byte |
| `working` | `⠹ trabalhando` | saiu byte agora há pouco |
| `ready` | *(nada)* | parado, sem ter feito nada que valha aviso |
| `waiting` | `● terminou` (verde) | o turno acabou e ninguém está esperando você |
| `asking` | `● precisa de você` (laranja) | parou dependendo de você: marcador, `pattern` ou pedido de permissão |
| `dead` | `✕ processo encerrado` | o processo saiu |

Só `asking` interrompe: borda do card laranja e som, uma vez por parada. `waiting`
fica no cabeçalho e na barra lateral, em verde, sem som — e some quando você entra
ou sai da sessão. Só terminal `agent` chama; `shell` mostra o spinner e nada mais.
Ver ADR-024.

### O protocolo de marcador

Todo nó `agent` recebe, no system prompt, um pedido de encerrar cada resposta com
`[[ED:ok]]` (terminei) ou `[[ED:ask]]` (dependo de você). É o sinal primário —
o silêncio do pty continua como rede quando o marcador não aparece.

```jsonc
"attention": {
  "sound": "Tink",         // /System/Library/Sounds; null desliga o som
  "volume": 0.3,           // 0…1 — é o volume, mais que o som, que faz o aviso discreto
  "minWorkMs": 2000,       // rajada mínima antes do silêncio valer aviso
  "marker": {
    "enabled": true,
    "done": "[[ED:ok]]",
    "ask":  "[[ED:ask]]",
    "instruction": "…{done}…{ask}…"   // o que vai no system prompt
  },
  "patterns": []           // regex para o diálogo de permissão do próprio CLI
}
```

`patterns` fica vazio de propósito: casar desenho de TUI quebra a cada release
do CLI. Ele existe para o único caso que o marcador não alcança — o diálogo de
permissão é desenhado pelo programa, não é mensagem do modelo. Preencher é opção
sua, e a manutenção também.

O app não valida nomes: se o binário existe no PATH, roda.

## Ligações entre terminais

Uma aresta desenhada no canvas diz que um terminal **pode acionar** outro. Sempre
de mão única; ida e volta são duas arestas. Detalhes e o porquê em
[ADR-012](01-decisoes.md#adr-012--agente-aciona-agente-por-aresta-desenhada-nunca-por-encaminhamento).

```jsonc
{
  "edges": [
    { "from": "pm", "to": "frontend", "maxSends": 5 },
    { "from": "frontend", "to": "pm" }            // herda o padrão, 2
  ],
  "maxVisits": 4
}
```

O agente recebe no system prompt o elenco que pode acionar — endereço, CLI e papel
de cada vizinho — e a linha de comando para acionar. **Ele decide quando e para
quem.** Nada é encaminhado automaticamente.

```
POST /message?from=<id>&target=<sessão/id>     corpo = texto puro
```

Quatro guardas, todas no app e nenhuma no texto do prompt:

| guarda | o que segura |
|---|---|
| aresta obrigatória | agente falando com quem você não ligou |
| `maxSends` na aresta | idas e voltas do par — é o botão do dia a dia |
| `maxVisits` na sessão | ciclo de 3+ nós, onde cada seta dispara uma vez só |
| fila ≤ 5 no destino | agente disparando em laço |

A cadeia zera quando **você** digita no terminal. Cadeia sem humano no meio tem
vida finita por construção.

## Protocolo de dispatch

Socket unix em `~/.egeon/sock` (não porta TCP — nada exposto na rede).

```jsonc
POST /dispatch
{
  "target": "deck/claude-1",
  "kind": "review",              // "review" | "task" | "raw"
  "file": "specs/pagamentos.md",
  "comments": [
    { "line": 12, "quote": "- [ ] retry no webhook", "body": "backoff exponencial, máx 5" },
    { "line": 28, "quote": "## Idempotência",        "body": "falta dizer qual header" }
  ]
}
```

Vira um prompt só:

```
[egeon] review de specs/pagamentos.md

L12  > - [ ] retry no webhook
     backoff exponencial, máx 5

L28  > ## Idempotência
     falta dizer qual header

Reescreva o arquivo endereçando cada ponto. Ao terminar, anote em uma
linha o que mudou.
```

Entra na fila do alvo, sai quando o pty ficar em silêncio pelo tempo do perfil.

## Ciclo de review

```
1. clique no .md     → abre no custom editor egeon.spec, renderizado
2. comenta inline    → thread desenhada por nós, ancorada por conteúdo
3. "Request changes" → comentários pendentes viram um prompt na sessão do agente
4. agente edita      → preview recarrega sozinho
5. comenta de novo   → volta ao passo 2
```

O preview é editável: clicar num bloco abre edição, salva via `WorkspaceEdit`.
Comentário enviado some da vista; o rodapé do painel reexibe quando você quiser.

Para ver o que o agente mudou, o Source Control e o diff editor do próprio
VSCode estão a um clique no mesmo workspace.

Detalhes e o que foi descartado em
[ADR-005](01-decisoes.md#adr-005--review-acontece-num-custom-editor-nosso-não-na-comments-api)
e [ADR-005b](01-decisoes.md#adr-005b--comentário-ancora-em-conteúdo-nunca-em-número-de-linha).

## Ordem de construção

1. ~~**Dispatcher**: socket + fila + detector de silêncio + writer com bracketed
   paste.~~ ✅ verificado ponta a ponta.
2. ~~**Nó agent**: SwiftTerm + perfil, registrado como alvo do dispatcher.~~ ✅
   prompt entra na sessão viva do Claude Code e é respondido.
3. ~~**Nó editor**: code-server + WKWebView.~~ ✅ workbench, código e diff
   renderizando dentro do canvas.
4. ~~**Extensão VSIX**: custom editor `egeon.spec` (render + edição +
   threads) e cliente do socket.~~ ✅ `.md` abre renderizado em um clique,
   comentário vira thread em sidecar, *Request changes* entrega na sessão viva.
5. ~~**Snapshots** e o ciclo de review completo.~~ **removido** — foi construído
   e retirado por poluir o preview. Ver
   [ADR-006](01-decisoes.md#adr-006--baseline-de-diff-por-snapshot-implementado-e-removido).
   Para ver o que mudou, o Source Control e o diff editor do próprio VSCode
   estão a um clique no mesmo workspace.

Os passos 1 e 2 já produzem algo usável: dá para mandar prompt para uma sessão
específica sem sair do lugar. O resto é conforto.

## Depois do MVP

Construído depois de o escopo acima fechar. Duas dessas linhas estavam listadas
como fora do MVP e mudaram de lado — fica registrado que mudaram, e por quê.

**Sessões, templates e componentes.** Criar, renomear e remover deixaram de exigir
edição de JSON. Template é preset de canvas inteiro; componente é preset de um
terminal (agente, comando, pasta, papel). Os dois copiam valores na criação:
editar o preset depois não mexe em quem já nasceu.

**Worktree por sessão** — *estava listado como fora do MVP*, com a justificativa de
que todos os nós compartilham a mesma working copy "de propósito". Continuam
compartilhando dentro de uma sessão; o que mudou é que abrir uma segunda frente
virou um botão, em vez de um `git worktree add` na mão seguido de remontar o
canvas. Leva o commit, o que não está commitado e o que o git não versiona.

**Carregando e "precisa de você"** — spinner por nó, aviso quando o agente para,
som, e contagem na barra lateral. Ver a seção acima e o ADR-011.

**Nó `web`** — navegador no canvas com perfil de navegação isolado por nome.

**Ligações entre terminais** — *também estava listado como fora do MVP*, na forma
"stdout de um agente virando stdin de outro". Foi construído em outra forma, e a
diferença é o ponto: encaminhar saída automaticamente não tem terminador, e é a
topologia que já queimou US$ 47 mil em 11 dias num caso público. Aqui a aresta
concede uma **capacidade** — o agente decide quando e para quem falar — e o
Egeon Deck conta a cadeia. Ver [ADR-012](01-decisoes.md#adr-012--agente-aciona-agente-por-aresta-desenhada-nunca-por-encaminhamento).

## Fora do MVP

- Zoom bonito no nó de editor (ver decisão aberta em 01-decisoes.md)
- Sessão remota, multi-máquina
- Windows e Linux

## Pendências declaradas

**Catálogo de ligações só é montado no arranque do terminal.** Desenhar uma aresta
nova não avisa quem já está rodando; o nó precisa ser recriado para o agente saber
que ganhou um vizinho.

Ficou menos urgente do que era: pelo [ADR-014](01-decisoes.md#adr-014--a-conversa-do-agente-sobrevive-ao-rebuild-e-segue-quem-você-escolhe)
o system prompt é remontado e reenviado na retomada, então reiniciar aplica o
catálogo novo **sem perder a conversa**. O que falta é o caso de não querer
reiniciar.

*Resolvida:* `agents.json` prometia `resume` e ninguém lia. Implementado no
ADR-014.
