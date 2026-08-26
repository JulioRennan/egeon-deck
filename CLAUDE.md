# Egeon Deck

App macOS de uso pessoal: um **canvas infinito onde cada nó é uma ferramenta de
trabalho real** — editor, terminal, agente de IA, navegador. O ponto é dirigir
vários agentes em paralelo: cada um vive num terminal endereçável, recebe prompt
por injeção e avisa quando precisa de você. Um usuário, sem distribuição.

```
app/          executável Swift (SPM) → EgeonDeck.app
extension/    extensão VSCode/code-server — review inline de markdown
docs/         00-prior-art · 01-decisoes (ADRs) · 02-mvp
poc/          protótipos descartados
```

## Módulos

Modular com MVC por dentro: todo módulo em `Features/`, sempre
`Models/ · Views/ · Controllers/ · Features/` (submódulo, recursivo). `Core`
fica fora — é o que as features dividem.

```
app/Sources/EgeonDeck/
├── Core/            Flavor · Log · ControlSocket · Peer · AppControl · Glass
│                    └ Features/EgeonCLI (o comando `egeon`)
├── Features/
│   ├── Canvas/          grid, arestas (EdgeController), toolbar
│   ├── Chat/            o modo chat — participantes, composer, thread
│   ├── Code/            código como texto — DiffHunk/DiffView (lado a lado),
│   │                    Language (por extensão), SyntaxLite (realce por linha)
│   ├── Dispatch/        fila, injeção, Target, guardas de cadeia
│   ├── Home/            RootView, ViewToolbar, WorkbenchShell, Sidebar
│   ├── Mosaic/          o modo mosaico
│   ├── Nodes/           NodeConfig, NodeView, NodeTemplate + concretos
│   │   └ Features/AgentNode (contrato genérico → Features/ClaudeCode)
│   │   └ Features/EditorNode (EditorNode + CodeServer)
│   ├── Notifications/   Activity, HookEvent, Spinner, AttentionSound
│   ├── Trace/           trilha da bancada — TraceEntry, TraceLog, ShellHook
│   └── Workbench/       WorkbenchConfig, Store, WorkbenchTemplate, worktree
└── main.swift       AppDelegate — único fora de módulo; vira App aos poucos
```

## Skills

- **`estrutura-de-modulos`** (`.claude/skills/`) — onde código novo vive, as
  regras de colocação e o processo de mudança. **Consultar antes de criar
  arquivo, mover código ou decidir onde uma feature mora.**
- **`protocolo-entre-agentes`** (`.claude/skills/`) — o mapa da camada de
  coordenação: marcadores `[[ED:*]]`, ganchos, `egeon`, guardas de cadeia,
  envelope. **Consultar antes de mexer em Dispatch, Notifications, EgeonCLI ou
  arestas.**

## Conceitos, em uma linha cada

- **Bancada** — uma frente de trabalho: pasta + nós abertos sobre ela.
- **Nó** — um card: `editor` · `shell` · `agent` · `web`. `NodeConfig` é a
  montagem; conversa nunca é copiada junto (`withoutConversation`).
- **Endereço** — `bancada/id` (ex. `deck/revisor`); estável. A bancada tem
  ainda um `id` próprio (8 hex) que sobrevive a rename e não se repete.
- **Aresta** — `from` pode acionar `to`. Vive na **bancada**, não no nó; nasce
  bidirecional; guardas: aresta obrigatória, `maxSends`, `maxVisits`, fila.
- **Conversa** — `conversationId` por nó agente; o CLI chama de sessão.
- **Visualização** — canvas · mosaico · chat (⌥⌘1/2/3); o card é o MESMO
  `NodeView` reparentado, o dono é o `WorkbenchShell`. Em chat o canvas fica
  montado por baixo, coberto (o pty precisa do passe de layout).
- **Chat** — spec em `docs/03-spec-chat.md`. Participantes com cor própria e
  estado, composer estilo Slack, envio real, thread por turno com passos e
  citações. A bolha desenha a **cadeia** do turno na ordem (prosa, grupo de
  passos, prosa — `ChatTurn.parts`) e cresce ao vivo enquanto o agente
  trabalha, lendo a cauda do transcript dele só nesse intervalo (ADR-039). O
  que já fechou sai do **histórico do app** (`ChatHistory`,
  `workbenches/<id>/chat.jsonl`, gravado no `Stop`), não do transcript do
  CLI. Botão de limpar a bancada (barra lateral, botão direito): `clear` do perfil em cada
  agente + chat arquivado como `chat-archive/chat-<início>_<fim>.jsonl` e trilha
  como `trace-archive/trace-<início>_<fim>.md`
  (`POST /workbench/clear`; só o chat: `POST /chat/clear`) (ADR-037).

## Funcionalidades, por cima

- Agentes conversam via `egeon peers` / `egeon send` — topologia consultada em
  tempo real; quem falou vem do pid do socket, nunca do texto.
- Estado do terminal por gancho do CLI (`stop`/`ask`/`prompt` → `/activity`);
  laranja interrompe (permissão), verde só informa (terminou).
- Worktree por bancada E por terminal (formulário decide pela branch).
- Modelo por nó de agente: formulário e pull-down no cabeçalho; trocar reinicia
  o processo e retoma a conversa. Lista vem do `agents.json` (`models`).
- Templates de bancada e de nó copiam valores na criação, nunca ficam atados.
- Trilha da bancada: ao fim de cada turno o agente roda `egeon trace` (uma ou
  duas linhas); o app carimba quem/CLI/modelo/conversa e anexa em
  `~/.egeon*/workbenches/<id>/trace.md` — um arquivo por bancada, para
  auditar (ADR-036). Tudo que é DE uma bancada mora na pasta dela, e a pasta é
  o `id` (8 hex, nasce com a bancada), não o nome.
- Drag & drop de arquivo → paste no terminal (imagem vira anexo no Claude Code).
- Voz pelo CLI dentro do pty (mic atribuído ao bundle do app).

## Desenvolvimento

| | estável | dev |
|---|---|---|
| bundle | `/Applications/Egeon Deck.app` | `app/build/EgeonDeck Dev.app` |
| config · socket | `~/.egeon/` | `~/.egeon-dev/` |
| log | `~/egeon.log` | `~/egeon-dev.log` |
| code-server | 8391 | 8392 |

- `./app/dev.sh` reconstrói o DEV. **Rebuild do estável mata os agentes em
  andamento** — só com pedido explícito (`./app/install.sh`).
- Todo caminho novo passa por `Flavor.current.config(_:)`.
- **Encerre o app antes de tocar no bundle dele** — `rm -rf` num app vivo pula
  o `applicationWillTerminate`, que grava o workbenches.json.
- **Teste unitário é parte da entrega**: código novo com lógica testável —
  modelo, parsing, guarda, controller — nasce com teste em `EgeonDeckTests`,
  e lógica que se move ganha teste junto. `swift test` antes de commitar.
  A cobertura hoje é pequena (118 testes); a regra existe para ela só crescer.
- **Verificar é executar, compilar não é verificar**: dispare por `/dispatch`,
  confira por `/peek` e pelo log. Rotas úteis: `/targets` `/dispatch` `/peek`
  `/chat` `/compose` `/edge` `/layout` `/geometry` `/status` — socket unix,
  HTTP mínimo:
  `curl --unix-socket ~/.egeon-dev/sock http://eg/targets`
- Config do usuário em `~/.egeon/` (tudo editável à mão); `bin/egeon`,
  `agent-hook.sh` e `claude-hooks.json` são regenerados a cada arranque.

## Regras

- **Comentário só de porquê** — decisão contraintuitiva, armadilha de
  plataforma. Nada de narrar código, numerar etapas ou `// MARK:` de 3 linhas.
- **Português** em comentários, docs, logs e commits.
- **Decisões viram ADR** em `docs/01-decisoes.md` — leia antes de propor rota
  para editor, portal de janela, tmux ou detecção de ociosidade: já custaram
  protótipo.
- Licença **AGPL-3.0-only** (copyleft de rede). Dependência incompatível —
  proprietária ou GPL-2-only — não entra.
