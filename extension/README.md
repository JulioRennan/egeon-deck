# Extensão Egeon Spec

Editor de markdown com review inline. Comenta trechos do documento e manda tudo
como **um prompt só** para a sessão de agente que já está rodando — sem copiar,
colar, nem abrir terminal.

Aparece na lista de extensões como **Egeon Spec** — é o nome da extensão,
não um documento de especificação.

## Instalação

```bash
cd extension
npm install
./install.sh          # symlink para a pasta de extensões do code-server
```

Reinicie o app (ou o code-server) para carregar. Não passa por marketplace:
é código nosso, o code-server varre a pasta de extensões
([ADR-004](../docs/01-decisoes.md)).

## Uso

| ação | como |
|---|---|
| abrir renderizado | clicar no `.md` — é o editor padrão para markdown |
| comentar | selecionar o trecho → balão → escrever → **Comentar** (ou `Cmd+Enter`) |
| enviar ao agente | **Request changes** na barra de cima |
| editar um bloco | duplo clique no bloco → editar → `Cmd+Enter` (Esc cancela) |
| ver o markdown cru | **Ver fonte** |
| trocar a sessão alvo | paleta → `egeon: Escolher sessão de agente alvo` |

O trecho comentado fica **pintado no texto**: amarelo enquanto pendente, azul
depois de enviado. Clicar no destaque leva à thread; clicar na thread pisca o
destaque.

## Configuração

```jsonc
{
  // Sessão que recebe os comentários. Vazio pergunta na primeira vez e guarda.
  "egeon.target": "deck/claude-back",
  "egeon.socketPath": "~/.egeon/sock"
}
```

Os endereços vêm do próprio app (`GET /targets`), então a lista nunca fica
desatualizada em relação aos workspaces abertos.

Para ver o que o agente mudou, use o **Source Control** e o diff editor do
próprio VSCode — estão a um clique no mesmo workspace. Já existiu um baseline
próprio aqui; foi removido por poluir o preview
([ADR-006](../docs/01-decisoes.md)).

## Onde as coisas moram

```
.egeon/reviews/<caminho do arquivo>.json   threads, fora do .md
```

O markdown é o produto e fica limpo — nada de marcador HTML dentro do arquivo
([ADR-005](../docs/01-decisoes.md)).

Cada thread guarda o **trecho citado**, não o número da linha. O agente
reescreve o arquivo; uma âncora por linha passaria a apontar para outra coisa.
Thread cujo trecho sumiu vira **órfã**, aparece em vermelho e continua visível —
nunca some calada.

## O que acontece ao clicar em Request changes

```
comentários pendentes
  → POST ~/.egeon/sock /dispatch  {kind: "review", file, comments}
  → app monta UM prompt com cabeçalho, trecho citado e instrução
  → fila do alvo, solta quando a sessão fica em silêncio
  → bracketed paste no pty + Enter
```

Os comentários enviados ganham `sentAt`, param de contar como pendentes e mudam
de cor. O botão mostra quantos estão na fila.

Se o app não estiver rodando, o botão falha em 5 s com a mensagem de erro em vez
de pendurar.

## Autoteste

O webview do custom editor é iframe isolado e não pode ser dirigido de fora.
Para exercitar o mesmo caminho do botão sem clicar, largue um arquivo:

```jsonc
// .egeon/selftest.json — review
{ "file": "docs/spec.md", "quote": "trecho exato", "line": 12,
  "body": "o que mudar", "target": "deck/claude-back" }

// .egeon/selftest.json — edição de bloco
{ "action": "edit", "file": "docs/spec.md",
  "line": 2, "lineEnd": 3, "text": "novo conteúdo" }
```

O resultado sai em `.egeon/selftest-result.json` e o gatilho é consumido.

## Estrutura

```
src/extension.js   custom editor, mensagens do webview, autoteste
src/render.js      markdown-it com data-line por bloco (token.map)
src/review.js      sidecar, reancoragem por conteúdo, payload do dispatch
src/socket.js      http sobre unix socket
media/preview.js   seleção, balão, threads, destaque, edição
media/preview.css  tema herdado das variáveis do VSCode
```

Renderizar no extension host (e não no webview) é o que dá acesso ao `token.map`
do markdown-it — as linhas de origem de cada bloco. É isso que liga um parágrafo
renderizado de volta ao arquivo, e o que torna a edição por bloco possível.
