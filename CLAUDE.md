# Egeon Deck

Um **canvas infinito onde cada nó é uma ferramenta de trabalho real** — terminal,
agente de IA, navegador. O ponto é dirigir vários agentes em paralelo: cada um
vive num terminal endereçável, recebe prompt por injeção e avisa quando precisa
de você.

## Estado: migração em curso

Nesta branch (`migracao-flutter`) o app está sendo reescrito de ponta a ponta,
**sem transição**: sai de Swift/AppKit e vai para Rust + Flutter.

```
rust/      o app novo, lado Rust — core, terminal, driver, montagem e o `egeon`
ui/        o app novo, lado Flutter — a interface
legado/    o app Swift de hoje (app/, tools/, poc/) — só referência para o porte
docs/      00-prior-art · 01-decisoes (ADRs) · 02-mvp · 03-spec-chat · migracao/
design/    a marca (logo, ícone) e o design system Graphite — o descritivo
site/      a página do projeto
```

Cada pasta tem o seu `CLAUDE.md`. Por enquanto `rust/` e `ui/` têm só a
fundação: compilam, mas não há lógica portada.

## Onde está cada coisa

| Para saber | Leia |
|---|---|
| O que foi decidido na migração e o que ainda está aberto | `docs/migracao/3-proposta.html` |
| O que o app faz hoje, arquivo por arquivo, rota por rota | `docs/migracao/1-hoje.html` |
| Como o Swift está montado por dentro | `docs/migracao/2-arquitetura-atual.html` |
| Conceitos e funcionalidades do produto (a especificação do porte) | `legado/CLAUDE.md` |
| Por que cada decisão antiga foi tomada | `docs/01-decisoes.md` |
| A marca e o manual do design system | `design/README.md` |

## Os componentes do app novo

```
UI (Flutter) ──socket──▶ CORE (Rust) ──interfaces──▶ DRIVER (Rust, por plataforma)
                              │
                              └────interface de tela──▶ TERMINAL (Rust + libghostty-vt)
```

- **Core** — todas as lógicas do app, inclusive o protocolo do socket, arquivos,
  git e rede. Não conhece driver, terminal nem UI; define as interfaces.
- **Driver** — só o acesso ao sistema operacional que muda por plataforma (pty,
  processos, conexão local, notificação, TCC). Se precisa de `cfg` por sistema,
  é driver.
- **Terminal** — só o emulador. O pty é do driver.
- **UI** — mostra e captura gesto; é mais um cliente do socket, como o `egeon`
  e o `curl`. Sem bridge e sem FFI entre Dart e Rust.
- **Montagem** (`egeon-app`) — o executável do core, que a UI lança ao abrir e
  que roda sozinho sem janela.

## Skills

- **`padrao-rust`** — os crates, core × driver, estrutura por features, regras
  de código. **Consultar antes de criar arquivo, crate ou dependência em `rust/`.**
- **`estrutura-flutter`** — features/core/commons/theme, papel de cada peça,
  lista de features, eventos. **Consultar antes de criar arquivo, widget, cubit
  ou dependência em `ui/`.**
- `estrutura-de-modulos` e `protocolo-entre-agentes` — descrevem o Swift de
  `legado/`. Úteis para entender o que está sendo portado.

## Regras da migração

- **Porte fiel.** O comportamento do Swift é portado como está. Nada é corrigido
  nem evoluído em `legado/`; defeito encontrado é anotado, não consertado.
- **Lógica portada traz os testes junto.** Os 633 testes de
  `legado/app/Tests` são a régua de paridade.
- **Os arquivos de `~/.egeon` continuam abrindo.** Mesmos caminhos, mesmos
  formatos, com as migrações de formato que o Swift carrega.
- **O socket mantém as rotas de hoje** — agentes e scripts existentes não podem
  perceber a troca.
- **Decisão nova entra em `docs/migracao/3-proposta.html`** antes de virar
  código; nada vai para "decidido" sem passar pelo Julio.
- **Sem gerador de código no Dart** (`freezed`, `json_serializable`,
  `build_runner`…). No Rust, macros `derive` são aceitas.
- **O app novo tem identificador próprio** (`dev.duckcoder.egeondeck.next`) até
  o corte, para não se confundir com o Egeon estável em uso.

## Verificar

| Onde | Comando |
|---|---|
| `rust/` | `cargo fmt --all --check && cargo clippy --workspace --all-targets -- -D warnings && cargo test --workspace` |
| `ui/` | `fvm flutter analyze && fvm flutter test` |

**Verificar é executar, compilar não é verificar.** O core roda sem janela e
responde pelo socket; quando houver rota, confira por `curl`, como se faz hoje
no Swift.

O Egeon estável instalado (`/Applications/Egeon Deck.app`, `~/.egeon/`) é o que
está em uso: não tocar no bundle nem nos arquivos dele.

## Regras gerais

- **Comentário só de porquê** — decisão contraintuitiva, armadilha de
  plataforma. Nada de narrar código ou numerar etapas.
- **Onde se clica, o ponteiro diz** — mão em tudo que responde a clique; seta só
  onde se arrasta ou não há ação (ADR-048).
- **Português** em comentários, docs, logs e commits.
- **Toda mudança visível entra no `CHANGELOG.md`** no mesmo commit, em
  `[Unreleased]`, na seção certa (`Adicionado` · `Alterado` · `Corrigido` ·
  `Removido`), uma linha do ponto de vista de quem usa, com o ADR entre
  parênteses. Refactor, teste, docs internos e o trabalho de porte que não muda
  o que o usuário vê não entram. Formato Keep a Changelog, versões SemVer.
  **Versão só sobe com tag lançada a pedido**: sem pedido explícito de
  release/nova versão, tudo fica em `[Unreleased]`. O processo está em
  "Lançar uma versão", abaixo; o do Swift, em `legado/CLAUDE.md`.
- **Decisões viram ADR** em `docs/01-decisoes.md` — leia antes de propor rota
  para editor, portal de janela, tmux ou detecção de ociosidade: já custaram
  protótipo.
- Licença **AGPL-3.0-only** (copyleft de rede). Dependência incompatível —
  proprietária ou GPL-2-only — não entra, em Rust ou em Dart.

## Lançar uma versão

Decisão 52. O GitHub Actions (`.github/workflows/release.yml`) compila e a
máquina do Julio assina e publica (`scripts/release.sh`). Alvos por enquanto:
**macOS Apple Silicon** (`EgeonDeck-macos-arm64.zip`), **Linux x86_64**
(`EgeonDeck-linux-x86_64.AppImage` e `egeon-deck_X.Y.Z_amd64.deb`) e **Windows
x64** (`EgeonDeck-windows-x86_64.zip`, sem atualização automática). Só com
pedido explícito do Julio.

Beta é versão com sufixo (`2.0.0-beta.1`): sai como **pré-release**, fora da
"mais recente", e o atualizador de quem está na estável não a vê.

1. Versão igual nos dois lados: `version` do `[workspace.package]` em
   `rust/Cargo.toml` e `version:` do `ui/pubspec.yaml` (`2.0.0-beta.1+1`).
2. No `CHANGELOG.md`, o `[Unreleased]` vira `## [2.0.0-beta.1] - AAAA-MM-DD`
   (as notas da release saem dessa seção), com um `[Unreleased]` vazio em cima.
3. Verificação das duas pastas, commit e push.
4. `scripts/release.sh tag 2.0.0-beta.1`: confere versões e CHANGELOG e
   empurra a tag `v2.0.0-beta.1`, que dispara o CI.
5. Acompanhe: `gh run watch $(gh run list -w release -L 1 --json databaseId -q '.[0].databaseId')`.
   O último job cria a release como rascunho de pré-release.
6. `scripts/release.sh publish 2.0.0-beta.1`: reassina o app do macOS com o
   certificado `egeon-dev`, assina o zip e o AppImage com a chave do Keychain
   (`.sig`) e publica.

Para validar o pipeline sem release, empurre uma branch `ci/<nome>`: o CI
compila tudo e guarda os arquivos como artefatos do run, sem o job de release.
O mesmo container do CI roda local: `scripts/linux/run.sh scripts/linux/package.sh <arch>`
na arquitetura da máquina. O x86_64 emulado num Mac (`EGEON_LINUX_PLATFORM=linux/amd64`)
não roda o Zig sob o Rosetta nem o appimagetool: compile o libghostty-vt cruzado
no container ARM e passe a pasta em `EGEON_GHOSTTY_VT_DIR`; sai só o .deb.
