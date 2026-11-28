---
name: padrao-rust
description: O padrão do código Rust do Egeon Deck (pasta rust/) — os cinco crates, o que é core e o que é driver, a estrutura por features, as interfaces em ports e as regras de código. Consultar SEMPRE antes de criar arquivo, crate ou dependência em rust/, e antes de decidir se algo é core, driver ou terminal.
---

# Padrão Rust do Egeon Deck

Decidido em `docs/migracao/3-proposta.html` (decisões 3 a 7, 10 e 13 a 15). Esta
skill é o resumo operacional; em caso de dúvida, a proposta manda.

## Os crates

```
rust/
├─ Cargo.toml            manifesto virtual — versões de dependência e lints num lugar só
└─ crates/
   ├─ egeon-core/        toda a lógica do app
   ├─ egeon-terminal/    emulador, sobre o libghostty-vt
   ├─ egeon-driver/      acesso ao sistema que muda por plataforma
   ├─ egeon-app/         montagem — o executável do core
   └─ egeon-cli/         o binário `egeon` — CLI dos agentes e ganchos
```

- Crates numa pasta só, sem aninhar; nome da pasta igual ao nome do crate.
- Só vira crate o que tem fronteira de verdade. Dentro do crate, módulo.
- Dependência nova entra em `[workspace.dependencies]` e o crate usa
  `nome.workspace = true`. Licença tem de ser compatível com AGPL-3.0-only.

## Quem pode depender de quem

| Crate | Pode usar | Não pode usar |
|---|---|---|
| `egeon-core` | só bibliotecas portáveis | driver, terminal, qualquer API de sistema |
| `egeon-driver` | `egeon-core` (as interfaces), API do sistema | lógica do app |
| `egeon-terminal` | `egeon-core` (a interface de tela), libghostty-vt | pty, API do sistema |
| `egeon-app` | todos | — |
| `egeon-cli` | `egeon-core` (só `protocol`) | o resto |

O core não conhece o driver nem o terminal. Quem liga os três é o `egeon-app`.

## Core ou driver?

- **Core** — todas as lógicas do app, incluindo o protocolo e as rotas do
  socket, arquivos, git, rede e relógio.
- **Driver** — só o que dá acesso a coisas do sistema operacional que podem
  diferir por plataforma: pty e sinais, tabela de processos, escuta local e pid
  do par, notificação e som, TCC, apps abertos, troca do app instalado, aviso de
  arquivo alterado.
- **Teste prático** — se o código precisa de `cfg` por sistema, é driver; se
  não, é core.
- **Terminal** — só o emulador: recebe bytes, mantém a tela. O pty é do driver.

## Por dentro do core

```
egeon-core/src/
├─ ports/        interfaces que driver e terminal implementam
├─ features/     um módulo por feature, planos, agrupados quando fizer sentido
│  └─ <feature>/
│     ├─ model.rs     entidades e leitura/gravação tolerante
│     ├─ store.rs     persistência em disco
│     └─ service.rs   regras e casos de uso
├─ protocol/     mensagens do socket — comandos, respostas, eventos, rotas
├─ runtime/      o laço único dono do estado
└─ commons/      caminhos, flavor, utilitários
```

Feature só ganha as camadas de que precisa; feature sem disco não tem `store.rs`.

## Por dentro do driver

Um módulo por capacidade e, dentro dele, um arquivo por plataforma escolhido
na compilação:

```
egeon-driver/src/
├─ pty/          mod.rs (implementa o trait do core) · unix.rs · windows.rs
├─ procs/        mod.rs · macos.rs · linux.rs
└─ …
```

Enquanto só houver macOS, cada módulo tem um arquivo de plataforma.

## Regras de código

1. **Interfaces no core, implementação fora.** O trait fica em `ports/`, com o
   formato do que o core precisa, não o da API do sistema.
2. **Só abstrair o que varia.** Arquivo, git, rede e relógio o core usa direto.
3. **Um dono do estado.** Uma tarefa única guarda o estado e recebe mensagens
   por canal. Leitores de pty, socket e vigias só mandam mensagens para ela.
4. **Um ator, não um por feature** — atores que se chamam em ciclo travam.
5. **Canais com limite.**
6. **Lógica com tempo recebe a hora como parâmetro** (injeção, nova tentativa,
   fila, cronômetro) e devolve o que fazer. Só onde o tempo importa; o resto é
   código assíncrono comum.
7. **Erros tipados no core** (`thiserror`), um tipo por feature. Erro genérico
   só na borda (`egeon-app`, `egeon-cli`).
8. **Sem `panic`, `unwrap` ou `expect` em caminho normal** — um nó com problema
   não derruba os outros agentes. O clippy do workspace avisa.
9. **Tipos próprios para o que tem regra** — endereço de nó, id de bancada, nome
   de branch — com construtor que valida.
10. **`unsafe` só em `egeon-driver` e `egeon-terminal`.** Os demais têm
    `#![forbid(unsafe_code)]`.
11. **O core recebe driver e terminal como objeto de trait (`dyn`)**, uma vez,
    na partida.
12. **`tokio`** é o runtime; **`serde`** lê e grava JSON. Macros `derive` são
    aceitas no Rust.
13. **A montagem é mínima** — só cria as peças e as liga.

## Porte do Swift

- O Swift saiu desta branch; a referência do comportamento antigo é a `main`
  (`git show main:app/...`).
- Os arquivos de `~/.egeon` têm de continuar abrindo: as migrações de formato
  estão em `docs/migracao/1-hoje.html`, seção "Arquivos em disco".

## Antes de commitar

```
cd rust && cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace
```

Comentário só de porquê, em português — as regras do `CLAUDE.md` valem aqui.
