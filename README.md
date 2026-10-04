# Egeon Deck

App macOS: um **canvas infinito onde cada nó é uma ferramenta de trabalho real** —
editor de código, terminal comum, terminal rodando um agente de IA, navegador. Você
monta a bancada uma vez por projeto e ela fica em pé.

O ponto não é "mais um workspace manager". É **dirigir vários agentes de IA em
paralelo sem perder o fio**: cada agente vive num terminal endereçável, recebe prompt
por injeção programática, e avisa quando parou e precisa de você.

Uso pessoal, um usuário, macOS. Não há multiusuário, telemetria, nem servidor.

## O que você precisa antes

| | por quê |
|---|---|
| macOS 14+ | as barras usam vidro (`NSGlassEffectView`) no 26+; abaixo disso caem sozinhas num fundo semiopaco |
| Xcode ou Command Line Tools | só se for compilar. Há zip pronto nas [releases](https://github.com/JulioRennan/egeon-deck/releases), mas o app é Swift/SPM e quem clona compila |
| [`code-server`](https://github.com/coder/code-server) | é o nó de editor. `brew install code-server`. Procurado em `/opt/homebrew/bin`, `/usr/local/bin` e `~/.local/bin` |
| um CLI de agente | o que você já usa. Vêm configurados `claude`, `codex`, `opencode` e `gemini`; qualquer outro entra em `~/.egeon/agents.json` |

Nenhum deles é verificado no arranque: sem `code-server` o nó de editor não sobe e o
resto funciona igual.

## Instalar

O que mudou em cada versão está no [`CHANGELOG.md`](CHANGELOG.md).

Duas rotas: baixar o zip pronto, ou clonar e compilar. Compilar é o que anda junto
com o repositório — o zip é de uma versão marcada.

### Baixar

Cada release traz dois zips, e a diferença é só o que vai dentro do executável:

| arquivo | para quem |
|---|---|
| `EgeonDeck-<versão>-universal.zip` | qualquer Mac — Apple Silicon e Intel |
| `EgeonDeck-<versão>-arm.zip` | só Apple Silicon, 1,4 MB menor |

Universal **não** é mais lento: o binário carrega as duas fatias e o macOS executa só
a nativa. O que dobra é o tamanho do executável, não o tempo de nada.

```bash
unzip EgeonDeck-v1.0.0-universal.zip -d /Applications
xattr -dr com.apple.quarantine "/Applications/Egeon Deck.app"
```

O `xattr` não é opcional. O bundle vai assinado ad-hoc e sem notarização; o macOS põe
quarentena em tudo que veio da internet e recusa abrir, dizendo que o app está
"danificado" — mensagem enganosa, porque o arquivo está inteiro e o que falta é o
carimbo da Apple.

### Compilar

```bash
git clone git@github.com:JulioRennan/egeon-deck.git
cd egeon-deck
./app/install.sh          # compila em release, instala em /Applications e abre
```

O script encerra qualquer instância antes de mexer no bundle, e confere no fim se o
processo que subiu é mesmo o novo.

Para gerar os zips de release em vez de instalar aqui, `./app/dist.sh universal` ou
`./app/dist.sh arm` — eles empacotam em `app/dist/` e não encostam em
`/Applications`.

**O macOS vai pedir permissões de novo a cada build.** A assinatura é ad-hoc, e para
o sistema um bundle reassinado é outro app. Para parar com isso, use um certificado
de code signing:

```bash
security find-identity -v -p codesigning
export EG_SIGN_ID="nome-do-certificado"
```

## Primeiro uso

1. `+` na barra da esquerda cria uma bancada — uma pasta e os nós abertos sobre ela.
2. Na barra de baixo, escolha a ferramenta e clique (ou arraste) no canvas para criar
   o nó: terminal, editor, navegador.
3. O nó de terminal tem um endereço — `bancada/id`, por exemplo `deck/claude-1`. É por
   ele que se manda prompt de fora.
4. Arraste a porta `+` de um card até outro para **ligar** dois agentes: dali em
   diante o primeiro pode acionar o segundo com `egeon send`.

Atalhos que valem saber: `⌥⌘1`/`⌥⌘2` trocam canvas e mosaico, `⌘/` recolhe a barra de
bancadas, `⌘1`…`⌘4` escolhem a ferramenta.

## O comando `egeon` e a trilha da bancada

Todo terminal do app tem um `egeon` no PATH. É por ele que um agente fala com o app —
e o app sabe **quem** está falando pelo processo do outro lado do socket, não por
nada que o agente escreva:

```bash
egeon peers                 # quem este terminal pode acionar agora
egeon status                # quem ele é: endereço, papel, bancada, modelo
egeon peek deck/revisor 10  # o que o vizinho mostra agora, sem interromper
egeon send deck/revisor <<'MB'
revisa o diff da branch
MB
egeon trace "pedido: … — entrega: …"   # registra na trilha da bancada
```

`peek` só alcança quem o terminal já pode acionar — a aresta do canvas é a mesma
que autoriza o `send`. De fora (o seu `curl` no socket) alcança qualquer nó.

No Claude Code o app ainda **publica uma skill** chamada `egeon`. Ela existe
porque prosa no system prompt não compete com a ferramenta de subagente do CLI:
quando você diz "pede pro revisor", o que decide o caminho é a descrição de uma
ferramenta. A skill entra nessa disputa e manda olhar os vizinhos primeiro.

É o **único** lugar em que o app escreve na sua configuração do Claude Code:
`skills/egeon/SKILL.md` (e `skills/egeon-maestro/SKILL.md`, abaixo) no root de cada base path que existir — `~/.claude`,
`~/.claude-agro`, qualquer `~/.claude*` — porque skill é por configuração e cada
nó escolhe a sua no formulário. A pasta é reescrita a cada arranque do app (o
arquivo avisa isso no corpo); para se livrar dela, apague `skills/egeon/` com o
app fechado.

### O maestro: um terminal que monta a bancada

Marque **Maestro** no formulário de um terminal de agente (⚙ no card) e ele passa a
poder desenhar a bancada sozinho — de preferência um modelo forte, como o Opus com
esforço alto. Peça "monta a bancada para migrar o backend" e ele decide quantos
terminais, o papel, o modelo, o esforço e as regras de cada um, quem fala com quem,
mostra o desenho e aplica:

```bash
egeon bench                 # a bancada: regras, nós, arestas, estado de cada um
egeon models                # CLIs, modelos e esforços que cada um aceita hoje
egeon plan  <<'JSON'        # valida o plano e mostra o que mudaria
{"nodes":[{"id":"back","cwd":"api","model":"sonnet","effort":"medium","role":"…"}]}
JSON
egeon apply <<'JSON'        # o mesmo plano, aplicado
…
JSON
egeon guide                 # o manual do maestro
```

O plano é validado inteiro antes de qualquer efeito: CLI, modelo e esforço têm de
existir no catálogo, a pasta tem de existir, e terminal em turno não é reiniciado.
Terminal novo nasce ligado ao maestro nos dois sentidos; as guardas de cadeia valem
como sempre. O maestro não mexe em si mesmo e não faz outros maestros — isso é só
seu. Cada `apply` deixa uma linha na trilha. O manual de desenho (topologias,
modelo e esforço por papel, como escrever papel e regras) é a skill
`egeon-maestro`, publicada junto da `egeon` (ADR-066).

A **trilha** é a memória da bancada: `~/.egeon/workbenches/<id>/trace.md`, um
Markdown só por bancada, que se lê de cima a baixo para auditar quem fez o quê. A
pasta é o **id** da bancada (oito hex, gerado na criação), não o nome: apagar e
recriar uma bancada com o mesmo nome é outra bancada, com outra trilha; o nome fica
logo abaixo do título do arquivo. O
agente escreve uma ou duas linhas ao fim de cada turno (o system prompt pede); o app
carimba hora, nó, CLI, modelo em uso e id da conversa. Terminal comum também entra:
cada comando que você roda vira uma linha (o comando, nunca a saída — `preexec` do
zsh, injetado por `ZDOTDIR` sem tocar no seu `.zshrc`). Sobrevive à conversa, à
worktree e ao rebuild.

### Configuração específica do Claude Code

O que segue é config **do Claude Code**, não do Egeon: o arquivo, o formato e a
sintaxe das regras são deles, e mudam com o CLI. O `egeon` roda pela ferramenta de
shell do agente, e o Claude Code pede aprovação para cada comando novo. Para não
aprovar um por um, libere o prefixo uma vez em `~/.claude/settings.json` (ou no
diretório que o seu `CLAUDE_CONFIG_DIR` apontar) — vale para todos os projetos:

```json
{
  "permissions": {
    "allow": ["Bash(egeon:*)"]
  }
}
```

Alternativa: responder "Yes, and don't ask again" no primeiro pedido. O Claude Code
grava `Bash(egeon trace *)` em `.claude/settings.local.json` **da pasta da bancada**,
que é local e não entra no git — mas aí é uma regra por subcomando e por projeto.

Codex, Gemini e OpenCode têm o equivalente nas próprias configs de aprovação; o
Egeon não escreve em nenhuma delas.

## Dirigir de fora

O app fala HTTP por um socket unix em `~/.egeon/sock`. É como a extensão do editor
conversa com ele, e é como se testa o app sem tocar na tela:

```bash
curl --unix-socket ~/.egeon/sock http://eg/targets
curl --unix-socket ~/.egeon/sock -X POST http://eg/dispatch \
     -d '{"target":"deck/claude-1","kind":"raw","text":"oi"}'
curl --unix-socket ~/.egeon/sock "http://eg/peek?target=deck/claude-1"
```

## Onde ficam as coisas

Tudo em `~/.egeon/`, e todo arquivo é feito para ser editado à mão: `workbenches.json`,
`agents.json`, `templates.json`, `components.json`, `web-profiles.json`. O que é **de
uma bancada** fica em `~/.egeon/workbenches/<id>/`, onde `id` é o da bancada em
`workbenches.json`: a trilha (`trace.md`), a conversa corrente do chat (`chat.jsonl`) e as arquivadas
(`chat-archive/chat-<início>_<fim>.jsonl`, nomeadas pelo período da conversa). Botão direito na
bancada › **Limpar a bancada…** roda o `/clear` de cada agente e move a conversa corrente
e a trilha para o arquivo (`trace-archive/trace-<início>_<fim>.md`) — nada é apagado do disco. O histórico é
o que o chat mostra, gravado pelo app a cada turno; não depende de o CLI manter o transcript
dele. O
log fica em `~/egeon.log` e é zerado a cada arranque — é a fonte de verdade quando algo
não subiu, porque `open -a` descarta stdout.

## Dois apps lado a lado

O app segura os pty direto, então **todo rebuild mata as bancadas de agente em
andamento**. Por isso existem dois flavors: o estável, que segura os agentes de
verdade, e o dev, que é o que se derruba.

```bash
./app/dev.sh              # reconstrói o DEV, não encosta no estável
./app/dev.sh debug stable # mexe no estável — mata seus agentes
```

O dev usa `~/.egeon-dev/`, socket próprio, log próprio e outra porta de code-server.

## Mais fundo

`CLAUDE.md` descreve como o app é montado, arquivo por arquivo.
`docs/01-decisoes.md` registra o que foi decidido e **por quê**, incluindo o que foi
descartado — vale ler antes de propor rota diferente para editor, portal de janela,
tmux ou detecção de ociosidade: essas já custaram protótipo.

## Licença

AGPL-3.0-only, texto completo em [`LICENSE`](LICENSE). Copyleft forte e **de rede**: o
app é um servidor (socket de controle em HTTP, code-server numa porta), e sob GPL
comum quem o hospedasse como serviço não deveria nada a ninguém. Não impede vender nem
usar comercialmente; impede fechar o fonte.
