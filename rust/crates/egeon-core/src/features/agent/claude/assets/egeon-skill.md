---
name: egeon
description: >-
  Falar com os outros terminais desta bancada do Egeon Deck — os agentes
  que o usuário vê no canvas ao lado deste. Use quando o pedido envolver
  outro agente — mandar trabalho, pedir revisão, perguntar algo, ver o
  que ele está fazendo, dividir trabalho entre agentes.
when_to_use: >-
  Quando o usuário disser "pede pro <nome>", "manda o <nome> fazer",
  "fala com o <nome>", "avisa o <nome>", "o que o <nome> está fazendo",
  "pergunta pro <nome>", "divide isso entre os agentes", "monta um time",
  "usa outro agente", "delega isso", "roda em paralelo", "chama um
  revisor", ou citar um terminal da bancada pelo nome ou endereço.
user-invocable: false
---

# Os outros terminais desta bancada

<!-- Escrito pelo Egeon Deck a cada arranque do app. Editar aqui não
     adianta: a próxima subida sobrescreve. -->

Você é um nó de uma bancada do Egeon Deck. Ao seu lado, no canvas que o
usuário está vendo, há outros terminais — cada um com o seu agente, o seu
papel e a sua conversa. Eles são endereçáveis pelo comando `egeon`, que
já está no PATH.

## Antes de criar um agente, olhe os que existem

**Quando o pedido for para outro agente, rode `egeon peers` primeiro.**
Se há um vizinho com o papel certo, o trabalho é dele: ele já está aberto,
o usuário o vê trabalhar, e o que ele fizer fica na conversa dele.

Um subagente do próprio CLI (a ferramenta Task/Agent) é outra coisa: roda
escondido dentro do SEU turno, morre no fim dele e não aparece no canvas.
Vale para uma busca ampla que você mesmo vai consumir — não vale como
resposta a "pede pro fulano", "delega isso" ou "monta um time". Isso é o
vizinho.

Se a lista vier vazia, ninguém está ligado a você agora: diga isso ao
usuário — a ligação é uma aresta que ele desenha no canvas — em vez de
inventar um substituto.

## Os comandos

    egeon peers                     quem você pode acionar agora
    egeon status                    quem VOCÊ é: endereço, papel, bancada
    egeon peek <endereço> [linhas]  o que ele mostra agora, sem interromper
    egeon send <endereço> <<'MB'    manda o texto para ele
    (o que você quer dizer)
    MB
    egeon trace <<'MB'              registra na trilha da bancada
    pedido: … — entrega: …
    MB

`peers` devolve `address`, `cli` e `role` de cada vizinho — escolha pelo
papel, não pela ordem. O endereço é `bancada/id`; entre irmãos da mesma
bancada o `id` sozinho basta.

## Mandar trabalho

`egeon send` **entrega e volta na hora**: ele enfileira a mensagem, não
espera a resposta. Ao mandar, **diga o que você espera de volta** — o
outro não vê a sua tela nem a sua conversa. Depois, encerre o seu turno
dizendo ao usuário para quem você passou; quem avisa quando o vizinho
termina é o app, não você. Não fique em laço de `peek` esperando.

Use `egeon peek` quando quiser mesmo conferir o estado de alguém sem
mandar nada: ele lê a tela do vizinho e não interrompe o trabalho dele.

**Comando do CLI vai direto:** mensagem que começa com `/` (`/clear`,
`/compact`, `/model sonnet`) chega crua no terminal do vizinho e roda
como comando dele, depois de um aviso dizendo que foi você. Mande só o
comando, sem texto em volta. Comando não tem resposta: não espere uma.
Evite os que abrem painel (`/cost`, `/model` sem argumento): o vizinho
fica parado nele até alguém fechar.

## Quem te acionou continua esperando

Mensagem que chega marcada com `[ED] mensagem de <alguém>` é o pedido de
um terminal que parou e ficou esperando o seu resultado. **Ele não vê a
sua tela, não lê a sua conversa e não é avisado de nada que você faça.**

**Termine respondendo a ele**, com `egeon send <quem mandou>`: uma ou
duas linhas com o que você entregou, ou por que não deu. É isso que
fecha o ciclo — sem a volta, ele não sabe se você entendeu o pedido, se
ainda está trabalhando ou se desistiu, e o usuário fica com dois
terminais parados sem saber qual deles esperar.

**Se você parar para perguntar algo ao usuário, avise o remetente
antes.** Parar com o marcador de pergunta chama o USUÁRIO, não o
vizinho: mande uma linha dizendo que empacou e no quê, e só então pare.
Parar calado no meio de um pedido de outro agente é o que deixa o outro
lado esperando por horas.

**A volta fecha o ciclo, não abre outro.** Responda o resultado e pare:
nada de responder a um agradecimento, nem de devolver pergunta que o
usuário resolve. As guardas de cadeia cortam quando a conversa dá voltas
demais, e o corte chega justamente na hora em que você teria algo útil a
dizer.

## Tarefas de uma fila

Prompt que termina com `[ED] tarefa <id> da fila <nome>` veio de uma
**fila de prompts**: a lista de tarefas que o usuário anotou e vai
mandando uma a uma. Cada tarefa é uma thread que ele lê no card da fila:

    egeon tasks                     as tarefas das filas ligadas a você
    egeon task done <id> [nota]     marca a tarefa como feita
    egeon task ask <id> <<'MB'      pergunta sobre ela — aparece na tarefa
    (a pergunta)
    MB
    egeon task note <id> <<'MB'     comenta nela: achado, decisão, o que fez
    (o comentário)
    MB

**Ao concluir, marque**: é o que fecha a tarefa e deixa a fila mandar a
próxima. Com dúvida que só o usuário resolve, **pergunte pela tarefa**
(`ask`) e encerre o turno com o marcador de pergunta: a pergunta fica
na thread dela, a fila espera, e a resposta volta para você como prompt
com o id da tarefa.

A topologia muda enquanto você trabalha — consulte na hora, não confie no
que viu no começo da conversa. Endereço fora da lista é recusado, e uma
cadeia longa demais de agentes falando entre si também: quando isso
acontecer, volte a falar com o usuário em vez de insistir.
