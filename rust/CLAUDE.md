# Egeon Deck — lado Rust

O core, o terminal, o driver, a montagem e o comando `egeon` do app novo. A
visão geral da migração está no `CLAUDE.md` da raiz.

**Antes de criar arquivo, crate ou dependência aqui, consulte a skill
`padrao-rust`.** Ela é o padrão a seguir; este arquivo é só o mapa.

## Crates

```
crates/
├─ egeon-core/        toda a lógica do app
│  └─ src/  ports/ · features/ · protocol/ · runtime/ · commons/
├─ egeon-terminal/    emulador de terminal, sobre o libghostty-vt
├─ egeon-driver/      acesso ao sistema que muda por plataforma
├─ egeon-app/         montagem — o executável do core
└─ egeon-cli/         o binário `egeon` — CLI dos agentes e ganchos
```

Hoje é só a fundação: os crates compilam e não têm lógica.

## Quem conhece quem

- `egeon-core` não depende de `egeon-driver` nem de `egeon-terminal`: define as
  interfaces em `ports/` e os dois as implementam.
- `egeon-app` é o único que conhece todos; só cria as peças e as liga.
- `egeon-cli` só usa o protocolo do socket.
- Dependência entre crates e de terceiros é declarada em
  `[workspace.dependencies]`, no `Cargo.toml` da raiz, e só quando o código que
  a usa entra — o compilador avisa de dependência sem uso.

## Core ou driver?

Se o código precisa de `cfg` por sistema operacional, é **driver**. Se não, é
**core** — inclusive arquivos, git, rede, relógio e o protocolo do socket.

## Portar do Swift

1. Ache o código em `legado/app/Sources/EgeonDeck/` e o destino dele nas tabelas
   de `docs/migracao/1-hoje.html`.
2. Porte o comportamento como está, sem corrigir.
3. Traga os testes de `legado/app/Tests/EgeonDeckTests/` junto.
4. Arquivo de `~/.egeon` lido aqui tem de abrir igual: as migrações de formato
   estão em `docs/migracao/1-hoje.html`, seção "Arquivos em disco".

## Comandos

```
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo build --workspace
```

Os três primeiros passam antes de todo commit.

## Regras que mais pegam

- `unsafe` só em `egeon-driver` e `egeon-terminal`; os outros têm
  `#![forbid(unsafe_code)]`.
- Sem `unwrap`, `expect` ou `panic` em caminho normal: um nó com problema não
  pode derrubar os outros agentes.
- Um dono do estado: uma tarefa única recebe mensagens por canal. Nada de
  `Arc<Mutex<…>>` espalhado.
- Lógica que depende de tempo recebe a hora como parâmetro, para o teste
  avançar o relógio.
- Comentário só de porquê, em português.
