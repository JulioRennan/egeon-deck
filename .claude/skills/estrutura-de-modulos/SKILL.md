---
name: estrutura-de-modulos
description: Onde código novo vive no Egeon Deck — o mapa dos módulos, as regras de colocação (módulo/Models/Views/Controllers) e o processo de mudança. Consultar SEMPRE antes de criar arquivo, mover código ou decidir onde uma feature mora.
---

# Estrutura de módulos do Egeon Deck

O app é modular com MVC por dentro de cada módulo. Esta skill decide **onde
código novo vai** e **como mudanças de estrutura são feitas**. Ela é a fonte;
o CLAUDE.md aponta para cá.

## A forma

```
app/Sources/EgeonDeck/
├── Core/                    ← FORA de Features: o que as features dividem
│   ├── Models/                 Flavor · AppEnvironment · TerminalDrop
│   ├── Views/                  Glass · ToolbarButton
│   ├── Controllers/            Log · ControlSocket · Peer · AppControl
│   └── Features/EgeonCLI/      o comando `egeon`
├── Features/                ← todo módulo mora aqui
│   ├── Canvas/                 grid, arestas, toolbar do canvas
│   ├── Dispatch/               fila, injeção, Target, guardas de cadeia
│   ├── Home/                   RootView, ViewToolbar, WorkbenchShell, Sidebar
│   ├── Mosaic/                 o modo mosaico
│   ├── Nodes/                  NodeConfig, NodeView e os concretos
│   │   └── Features/
│   │       ├── AgentNode/      contrato genérico de agente (AgentProfile)
│   │       │   └── Features/ClaudeCode/   o que é SÓ do Claude Code
│   │       └── EditorNode/     EditorNode + CodeServer
│   ├── Notifications/          Activity, HookEvent, Spinner, AttentionSound
│   └── Workbench/              WorkbenchConfig, Store, Template, worktree
└── main.swift               ← único remanescente; vira módulo App aos poucos
```

**Dentro de módulo é sempre e somente:** `Models/` · `Views/` · `Controllers/`
· `Features/` (este quando nascer submódulo — a convenção é recursiva).
NUNCA papel-primeiro (`Views/Canvas/` está errado; `Canvas/Views/` está certo).

Hoje módulo é pasta num target só. Promover módulo a target SPM é passo
futuro, um por vez, quando a fronteira estiver limpa — nunca big-bang: foi
tentado e não compilou mais.

## Regras de colocação

1. **Módulo é quem tem assunto.** Novo código entra no módulo do assunto dele,
   não no do vizinho que o chamou.
2. **M/V/C pelo papel:** dado e derivação de dado → `Models` (Flavor,
   TerminalDrop); NSView e desenho → `Views`; comportamento e serviço —
   escrever, servir, resolver, orquestrar → `Controllers` (Log, EdgeController).
3. **Compartilhado por 2+ features → `Core`.** Glass e ToolbarButton estão lá
   por isso. Não duplicar; não deixar no módulo que usou primeiro.
4. **Específico de um CLI de agente → submódulo em `AgentNode/Features/`.**
   Gancho, flag, formato de transcript do Claude Code moram em `ClaudeCode/`.
   O contrato genérico (AgentProfile e configs) não sabe de CLI nenhum.
5. **Preset mora com o que preseta.** `WorkbenchTemplate` na bancada,
   `NodeTemplate` no nó. Não agrupar por parecença.
6. **Nó é vértice; a bancada é o grafo.** Arestas vivem em
   `WorkbenchConfig.edges`, nunca no nó — toda operação de aresta é global
   (ciclo, teto de visitas, desenho da camada).
7. **Controller não é dono de estado.** O padrão é o EdgeController: lê e
   escreve por closures; o `workbenches.json` tem um dono só. Canvas resolvido
   na hora quando a operação vale para bancada sem shell na tela.
8. **Disco não acompanha rename de código.** `components.json`, chave
   `component`, `sessionId` legado: renomear tipo não muda formato gravado.
   Migração de disco é decisão separada, com absorção na carga.

## O processo de mudança

- **Incremental obrigatório:** um passo por commit, app compilando em cada um.
  Passo que não compila em 30 min reverte — nunca "conserta em cima".
- **Mover é mover.** Passo de reorganização não muda comportamento. Refatorar
  de verdade é outro passo, outro commit.
- **Teste unitário é parte da entrega.** Código novo com lógica testável —
  modelo, parsing, guarda, controller — nasce com teste em `EgeonDeckTests`;
  lógica que se move ganha teste junto. Controller testável é o que não segura
  estado: injete config/persistência por closures, como o EdgeController, e o
  teste roda sem tela. `swift test` antes de todo commit.
- **Verificar é executar:** `./app/dev.sh`, e conferir pelo socket
  (`/targets`, `/dispatch` + `/peek`, `/edge`) e pelo
  `~/egeon-dev.log`. Compilar não é verificar.
- A cada refactor, relatar o que mudou e o que testar à mão.

## Fronteiras conhecidas (não tropece)

- `Target` e `Dispatcher` dividem `fileprivate` de propósito — vivem no mesmo
  arquivo até a refatoração abrir essa fronteira deliberadamente.
- `NodeWorktreePlanner.ask` monta NSAlert dentro do Models — dívida anotada no
  import; sai quando o diálogo de worktree ganhar view própria.
- O modo chat foi removido para ser refeito do zero. O que ficou dele:
  `NodeConfig.transcript` (gravado pelo gancho via `/conversation`) e o decode
  tolerante do `ViewMode` — `view:"chat"` gravado cai em canvas. O chat novo
  nasce como módulo em `Features/`, e leitor de transcript claude-specific
  nasce direto em `ClaudeCode/`.
