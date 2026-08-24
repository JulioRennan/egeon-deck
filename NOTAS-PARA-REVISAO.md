# Notas para revisão — rodada de testes unitários (2026-08-23)

O que encontrei de confuso ou contraintuitivo escrevendo os testes, para você
decidir. Nada aqui foi mudado no código — só anotado.

## 1. Teste escreve no log REAL do estável

`swift test` roda sem bundle → `Flavor.current` = estável → todo `Log.write`
disparado por teste anexa em `~/egeon.log` de verdade
(`Core/Controllers/Log.swift:6`). Os testes do `EdgeController` fazem isso hoje.
Inofensivo (o app zera o log no arranque), mas é vazamento de teste para o
ambiente real. Opções: sink injetável no `Log`, ou um flavor `test` quando
`XCTestConfigurationFilePath` está no ambiente.

O mesmo vale para qualquer Store em teste: `AgentStore.load()` leria o
`~/.egeon/agents.json` REAL. Os testes atuais evitam os Stores por isso —
nenhum teste chama `load()`/`save()` de Store.

## 2. `identifier(from:)` come acentos

`NodeTemplateStore.identifier` (`Features/Nodes/Models/NodeTemplate.swift:95`):
"QA Ágil" → `qa-gil`. Acento não está no conjunto permitido, vira hífen e o
colapso engole — "Ágil" perde o Á e vira "gil". Funciona, mas o id fica
irreconhecível. Transliterar antes (á→a, ç→c) daria `qa-agil`. Decidir se vale.

## 3. Regra do MosaicLayout mora na view

"Aplicada só quando a contagem casa" (doc do
`Features/Mosaic/Models/MosaicLayout.swift`) é imposta pelo `MosaicSplit`
(view), não pelo model — então não tem teste unitário. Uma função pura
`applies(to count:)` no model deixaria a regra testável e a view só a chamaria.

## 4. Quoting misto no drop

`TerminalDrop.text` põe aspas SÓ no caminho que precisa: `'/tmp/um arquivo.pdf'
/tmp/outro.swift `. Intencional (menos ruído no terminal), mas é sutil — o
teste documenta o comportamento real. Conferir se era isso mesmo.

## 5. Limite de aresta divergente: a→b vence

`EdgeLink.collapse` (`Features/Canvas/Models/EdgeConfig.swift:129`): editando o
`workbenches.json` à mão com `maxSends` diferente em cada sentido, a tela mostra
o de a→b (ordem alfabética do par!) — não o maior, não o menor. Documentado no
código, testado, mas fácil de tropeçar editando à mão.

## 6. Empate de timestamp no aninhamento do chat

`ChatThread.nest` (`Features/Chat/Models/Chat.swift:145`) casa o turno provocado
com "o último turno do remetente com `at <=` o dele". Dois turnos do provocador
no MESMO milissegundo (acontece em replay/compactação) podem aninhar no turno
errado — o desempate é só por ordem na lista. Raro; anotado porque é o tipo de
bug que ninguém acha depois.

## 7. O que ficou sem teste unitário, e por quê

| área | motivo |
|---|---|
| Views (todas) | NSView precisa de tela; a verificação é pelo socket + dev, como manda o CLAUDE.md |
| `ControlSocket` | servidor real; verificado por `curl` no dev a cada refactor |
| `Target`/`Dispatcher` | pty + views + `fileprivate` compartilhado; a máquina de estados (verdict/screen) merece ser extraída pura na refatoração — aí ganha teste |
| `Worktree` | git de verdade; teste seria de integração com repo temporário (dá para fazer, se você quiser) |
| `CodeServer` / `EgeonCLI` / `ClaudeHooks` | processo/arquivos reais em `~/.egeon`; testável só com diretório injetado (ver nota 1) |
| `Peer` | resolução por pid de processo vivo |
| `NodeWorktreePlanner.inspect/materialize` | chama git no disco; `decided` (a regra pura) está testado |

## 8. Apontamentos do revisor (2026-08-24)

A suíte passou por revisão independente (architect): **APROVADO**, com três
correções aplicadas — teste tautológico do Spinner removido, o de cores
apertado de `>1` para `>=4` distintas, e `<command-message>` incluído no teste
de ruído. Sobraram dele:

- **Spinner sem teste**: `Spinner.current` lê `Date()` direto; testar a fase
  exige relógio injetável. Decidir se vale a indireção.
- **Funções puras pequenas ainda sem teste**: `AgentProfile.resolvedEnvironment`
  (expansão de `~`/`$HOME`), `runsOwnBinary`, `systemPromptText`, e
  `ChatTurn.conversationSpan`. Nenhuma crítica; ficam para a próxima leva.

## 9. Dívidas já anotadas no código (desta migração)

- `NodeWorktreePlanner.ask` monta NSAlert dentro de Models (import comenta).
- `ClaudeAdapter` deve descer para `ClaudeCode/` na refatoração do chat.
- `Target`+`Dispatcher` num arquivo por `fileprivate` — separar é decisão de
  desenho, não de endereço.
