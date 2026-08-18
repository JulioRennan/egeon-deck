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
unzip EgeonDeck-v0.2-universal.zip -d /Applications
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

1. `+` na barra da esquerda cria uma sessão — uma pasta e os nós abertos sobre ela.
2. Na barra de baixo, escolha a ferramenta e clique (ou arraste) no canvas para criar
   o nó: terminal, editor, navegador.
3. O nó de terminal tem um endereço — `sessão/id`, por exemplo `deck/claude-1`. É por
   ele que se manda prompt de fora.
4. Arraste a porta `+` de um card até outro para **ligar** dois agentes: dali em
   diante o primeiro pode acionar o segundo com `egeon send`.

Atalhos que valem saber: `⌥⌘1`/`⌥⌘2` trocam canvas e mosaico, `⌘/` recolhe a barra de
sessões, `⌘1`…`⌘4` escolhem a ferramenta.

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

Tudo em `~/.egeon/`, e todo arquivo é feito para ser editado à mão: `sessions.json`,
`agents.json`, `templates.json`, `components.json`, `web-profiles.json`. O log fica em
`~/egeon.log` e é zerado a cada arranque — é a fonte de verdade quando algo não subiu,
porque `open -a` descarta stdout.

## Dois apps lado a lado

O app segura os pty direto, então **todo rebuild mata as sessões de agente em
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
