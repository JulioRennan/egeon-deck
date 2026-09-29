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
│   ├── Workbench/       WorkbenchConfig, Store, WorkbenchTemplate, worktree
│   └── Workspace/       workspace → projeto: WorkspaceConfig, Store, Tree,
│                        pastilha (imagem/inicial) e formulário (ADR-043)
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

- **Workspace → Projeto → Bancada** (ADR-043) — workspace é nome + foto (ou a
  inicial) + pastas; cada pasta é um projeto; a bancada guarda o `project`
  (id) a que pertence. Bancada em worktree é do projeto do repositório
  principal. Todos os workspaces ficam à vista na barra, expansíveis; o
  arquivo é `workspaces.json`, e `GET /workspaces` devolve a árvore. Os três
  níveis se **reposicionam arrastando** na barra — bancada muda de projeto, e
  o mapa de índices leva junto os terminais na tela (ADR-051); `GET /move`
  faz o mesmo de fora. Cada workspace tem uma **gaveta**: projeto guardado
  (escolha sua, arrastando ou pelo menu — nunca por tempo sem uso) sai da
  lista de cima; a gaveta aparece mesmo vazia, porque é o alvo do arrasto
  (ADR-052).
- **Bancada** — uma frente de trabalho: pasta + nós abertos sobre ela.
- **Nó** — um card: `editor` · `shell` · `agent` · `web`. `NodeConfig` é a
  montagem; conversa nunca é copiada junto (`withoutConversation`).
- **Endereço** — `bancada/id` (ex. `deck/revisor`); estável. A bancada tem
  ainda um `id` próprio (8 hex) que sobrevive a rename e não se repete — é por
  ele que o app guarda o que é de uma bancada (`shells`, `edgeControllers`,
  abas); posição na lista envelhece, e `WorkbenchLookup` faz a tradução.
- **Aresta** — `from` pode acionar `to`. Vive na **bancada**, não no nó; nasce
  bidirecional; guardas: aresta obrigatória, `maxSends`, `maxVisits`, fila.
- **Conversa** — `conversationId` por nó agente; o CLI chama de sessão.
- **Visualização** — canvas · mosaico · chat (⌥⌘1/2/3); o card é o MESMO
  `NodeView` reparentado, o dono é o `WorkbenchShell`. Em chat o canvas fica
  montado por baixo, coberto (o pty precisa do passe de layout).
- **Abas** (ADR-061) — as bancadas ABERTAS numa faixa no topo do conteúdo, com
  os mesmos badges da barra lateral; a lateral continua sendo o catálogo (tudo
  que existe). **Fechar a aba não encerra a bancada**: sai da faixa, os
  terminais seguem rodando e ela volta pela lateral. `openTabs` (à vista) e
  `shells` (de pé) são conjuntos diferentes. ⌘]/⌘[ percorrem a faixa, ⌘1…⌘9 vão
  direto, ⌘W fecha a aba, ⌘→/⌘← vão para a aba do lado (desabilitados dentro de
  caixa de texto, onde a seta é da edição). **Arrastar a aba reordena**
  (ADR-062): a pastilha acompanha o cursor e as vizinhas deslizam — a linha de
  inserção fica só na barra lateral, onde o destino é ambíguo. A faixa vai para
  o disco (`tabOrder`/`tabActive`) e volta no arranque, com teto de seis.
  Confere-se por `GET /tabs` (`?close=<bancada>` fecha,
  `?move=<bancada>&to=<n>` reordena).
- **Chat** — spec em `docs/03-spec-chat.md`. Participantes com cor própria e
  estado, composer estilo Slack, envio real, thread por turno com passos e
  citações. **Linha do tempo plana** (ADR-042): cada turno de cada agente é
  uma bolha, inclusive o que veio de outro agente ("✦ front" em cima); a marca
  é só o `@destinatário`, e só quando a mensagem não é contínua; nada
  aninha. A thread é um `NSTableView` com **uma linha por bloco** da cadeia
  (`ChatBlock`), alturas medidas na fila de fundo (`ChatBlockLayout`) e diff
  por id entre montagens (`ChatThreadController`). A bolha desenha a
  **cadeia** do turno na ordem (prosa, passo, diff, prosa — `ChatTurn.parts`)
  — passo de comando nasce **recolhido**, só o título com `▸`, e clique abre;
  passos contíguos viram **uma capa** ("⚙ 3 passos"), e o clique nela
  aprofunda — resumo, títulos, tudo aberto (ADR-049) —, mas fecha se você já
  abriu um passo à mão, e "tudo aberto" abre os passos de verdade, cada um
  ainda seu (ADR-053); o passo da capa é
  sub-bolha, recuada um tab e com caixa própria (ADR-050);
  **diff nunca recolhe** (o `DiffView` lado a lado está sempre lá) e leitura
  mostra o arquivo com o formatador (ADR-044/046) — e cresce ao vivo enquanto
  o agente trabalha, lendo a cauda do transcript dele — a partir do prompt do
  turno — só nesse intervalo (ADR-039). O que já fechou sai do
  **histórico do app** (`ChatHistory`,
  `workbenches/<id>/chat.jsonl`, gravado no `Stop`), não do transcript do
  CLI. Botão de limpar a bancada (barra lateral, botão direito): `clear` do perfil em cada
  agente e, **depois de eles assentarem**, chat arquivado como
  `chat-archive/chat-<início>_<fim>.jsonl` e trilha como
  `trace-archive/trace-<início>_<fim>.md`
  (`POST /workbench/clear`, que só responde no fim; só o chat:
  `POST /chat/clear`) (ADR-037/059). Enquanto isso a bancada fica com a cortina
  de "um instante" (`BusyOverlay`) e não aceita clique; no fim o chat esquece o
  que guardava em memória (`clearedHistory` — eco não confirmado e turno ao
  vivo), que era a bolha órfã que sobrava. A thread
  desce sozinha quando você está no fim: o fim é medido depois do passe de
  layout, a descida animada em curso conta como fim, e enviar sempre desce
  (ADR-045).

## Funcionalidades, por cima

- Agentes conversam via `egeon peers` / `egeon send` — topologia consultada em
  tempo real; quem falou vem do pid do socket, nunca do texto. `egeon status` diz
  ao agente quem ELE é (endereço, papel, bancada) e `egeon peek <endereço>` lê a
  tela do vizinho sem interromper — só de quem ele já pode acionar. No Claude
  Code o app publica uma **skill** (`ClaudeSkill` → `skills/egeon/SKILL.md` no
  root de CADA `~/.claude*`, porque skill é por configuração e cada nó escolhe a
  sua) para que "pede pro fulano" acione o vizinho em vez de abrir um subagente
  do CLI (ADR-054). Quem **recebe** um pedido de outro agente responde a ele ao
  terminar — e avisa antes de parar para perguntar ao usuário (ADR-058).
- Estado do terminal por gancho do CLI (`stop`/`ask`/`prompt` → `/activity`);
  laranja interrompe (permissão), verde só informa (terminou), e a ampulheta
  "⏳ em segundo plano" é o turno que fechou com `[[ED:wait]]` — trabalho de
  fundo rodando, o agente volta sozinho (ADR-063).
- Worktree por bancada E por terminal (formulário decide pela branch).
- Modelo, esforço e ultracode por nó de agente: formulário e uma faixa própria
  no cabeçalho (`accessoryRow` → `ModelRow`), à direita. Os modelos e os níveis
  que cada um aceita vêm da tabela **dentro do binário do Claude Code**
  (`ClaudeModelCatalog`, cache em `claude-models.json`); sem ela, os apelidos
  do `agents.json`. Ultracode ocupa o `--effort`, e o nível vai por
  `CLAUDE_CODE_EFFORT_LEVEL`. Trocar reinicia o processo e retoma a conversa
  (ADR-064).
- **Papel e regras** são campos separados (ADR-056): papel é quem o terminal é;
  regra é como se trabalha, e a da **bancada** (menu de contexto na barra) vale
  para todos os agentes dela, somada à do nó. No system prompt as regras entram
  DEPOIS do papel — é o que faz a restrição valer sobre a diretriz geral.
  Editar reinicia o agente e retoma a conversa, como a troca de modelo.
- Templates de bancada e de nó copiam valores na criação, nunca ficam atados. O
  **componente de nó é cross-CLI** (ADR-057): `name`, `kind`, `cwd`, `prompt` e
  `rules` valem em qualquer um; comando, config e modelo moram em `byAgent`, e
  a regra de um CLI SUBSTITUI a geral.
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
  A cobertura hoje é pequena (190 testes); a regra existe para ela só crescer.
- **Verificar é executar, compilar não é verificar**: dispare por `/dispatch`,
  confira por `/peek` e pelo log. Rotas úteis: `/targets` `/dispatch` `/peek`
  `/chat` `/compose` `/edge` `/layout` `/geometry` `/status` `/workspaces` —
  socket unix, HTTP mínimo:
  `curl --unix-socket ~/.egeon-dev/sock http://eg/targets`
- Config do usuário em `~/.egeon/` (tudo editável à mão); `bin/egeon`,
  `agent-hook.sh` e `claude-hooks.json` são regenerados a cada arranque.

## Regras

- **Comentário só de porquê** — decisão contraintuitiva, armadilha de
  plataforma. Nada de narrar código, numerar etapas ou `// MARK:` de 3 linhas.
- **Onde se clica, o ponteiro diz** — mão (`HandCursor`) em toda view que
  responde a clique; seta só onde se arrasta ou não há ação (ADR-048).
- **Português** em comentários, docs, logs e commits.
- **Toda mudança visível entra no `CHANGELOG.md`** no mesmo commit, em
  `[Unreleased]`, na seção certa (`Adicionado` · `Alterado` · `Corrigido` ·
  `Removido`), uma linha do ponto de vista de quem usa, com o ADR entre
  parênteses. Refactor, teste e docs internos não entram. Formato Keep a
  Changelog, versões SemVer: no release, `[Unreleased]` vira `[X.Y.Z] - data`,
  a versão do `app/make.sh` (`CFBundleShortVersionString`) acompanha, a tag é
  `vX.Y.Z` e os links de comparação no rodapé são atualizados.
- **Decisões viram ADR** em `docs/01-decisoes.md` — leia antes de propor rota
  para editor, portal de janela, tmux ou detecção de ociosidade: já custaram
  protótipo.
- Licença **AGPL-3.0-only** (copyleft de rede). Dependência incompatível —
  proprietária ou GPL-2-only — não entra.
