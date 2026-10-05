import Foundation

/// O manual do maestro (ADR-066): como desenhar uma bancada e o formato exato
/// do plano.
///
/// Um texto só, servido de dois jeitos: como skill do Claude Code
/// (`skills/egeon-maestro/SKILL.md`, publicada pelo `ClaudeSkill`) e pelo
/// `egeon guide`, que é como um CLI sem skill — Codex, Gemini — chega nele.
/// Mora aqui e não no submódulo do Claude porque o conteúdo não é de CLI
/// nenhum; o que é do Claude é só o frontmatter.
enum MaestroGuide {
    static let skillName = "egeon-maestro"

    /// O frontmatter vai em bloco (`>-`): português com dois-pontos e
    /// travessão num escalar solto derruba o YAML inteiro, calado (ver
    /// `ClaudeSkillTests`).
    static var skill: String {
        """
        ---
        name: \(skillName)
        description: >-
          Montar e reconfigurar a bancada do Egeon Deck sendo o terminal maestro
          — decidir quantos agentes, o papel, o modelo, o esforço e as regras de
          cada um, quem fala com quem, e aplicar tudo com `egeon apply`. Só vale
          quando `egeon status` mostra maestro true.
        when_to_use: >-
          Quando o usuário pedir para montar, configurar, organizar ou
          reconfigurar a bancada ou um time de agentes — "monta a bancada para",
          "configura os terminais", "cria os agentes", "desenha o time",
          "organiza quem faz o quê", "troca o modelo do", "põe o revisor em
          opus", "aumenta o esforço do", "tira o terminal", "define as regras
          da bancada" — ou quando você for o maestro e o trabalho pedir mais de
          um agente.
        ---

        """ + text
    }

    static var text: String {
        #"""
        # Maestro — montar a bancada

        <!-- Escrito pelo Egeon Deck a cada arranque do app. Editar aqui não
             adianta: a próxima subida sobrescreve. `egeon guide` imprime o
             mesmo texto. -->

        Você está num terminal do Egeon Deck: um canvas onde cada card é um
        terminal real com um agente dentro, e o usuário vê todos ao mesmo
        tempo. Uma **bancada** é uma frente de trabalho — uma pasta e os
        terminais abertos sobre ela. O **maestro** é o terminal que o usuário
        autorizou a desenhar essa bancada: criar terminais, escolher o CLI, o
        modelo e o esforço de cada um, escrever o papel e as regras, ligar
        quem fala com quem — e depois reger o trabalho.

        **Confira antes:** `egeon status` tem de mostrar `"maestro": true`.
        Se não mostrar, você não tem esse poder: diga ao usuário que ele liga
        isso no formulário do terminal (⚙ no card → "Maestro") e, enquanto
        isso, use só `egeon peers`/`egeon send` com quem já existe.

        ## Os comandos

            egeon bench          a bancada agora: regras, maxVisits, nós, arestas, estado
            egeon models         CLIs, modelos e níveis de esforço que cada um aceita
            egeon plan <<'JSON'  valida um plano e mostra o que mudaria (não muda nada)
            { ... }
            JSON
            egeon apply <<'JSON' valida e aplica — o mesmo plano
            { ... }
            JSON
            egeon guide          este texto

        E os de sempre: `egeon peers`, `egeon send`, `egeon peek`,
        `egeon status`, `egeon trace`.

        ## O fluxo

        1. **Entenda o pedido.** Qual é o objetivo, onde mora o código (que
           pastas, que repositórios), o que é entregável, o que não pode
           acontecer. Se faltar algo que muda o desenho, pergunte — uma vez,
           tudo junto.
        2. **Leia o terreno.** `egeon bench` (o que já existe — não recrie o que
           está lá) e `egeon models` (o que se pode pedir HOJE: os modelos e os
           níveis vêm do binário instalado, não da sua memória).
        3. **Desenhe** — seções abaixo: quantos, quais papéis, que modelo e
           esforço, que regras, que arestas.
        4. **Prévia.** `egeon plan` com o plano. Corrija até voltar `ok: true`.
        5. **Mostre ao usuário** o desenho numa tabela curta (id · CLI ·
           modelo/esforço · papel em uma linha) e as arestas, e pare para ele
           confirmar — a menos que ele já tenha dito para aplicar direto.
        6. **Aplique.** `egeon apply` com o MESMO plano.
        7. **Dê o trabalho.** Os terminais novos sobem em alguns segundos;
           `egeon send` já enfileira e entrega quando estiverem prontos. Uma
           mensagem por terminal, com a tarefa dele.
        8. **Termine o turno.** Diga ao usuário quem está fazendo o quê e pare
           com o marcador de trabalho em segundo plano — você volta quando os
           terminais responderem pelo `egeon send`.

        ## Quando NÃO montar um time

        Cada agente a mais custa contexto, tokens e coordenação — e boa parte
        das falhas de sistemas multiagente é desalinhamento entre eles, não
        falta de capacidade. Monte time quando o trabalho **se divide de
        verdade**:

        - partes independentes que andam em paralelo (front e back, três
          módulos que não se tocam);
        - um olhar separado que vale o custo (revisor que não escreveu o
          código, testador que não conhece a implementação);
        - repositórios diferentes, cada um com o seu terminal na pasta certa.

        Tarefa pequena, sequencial ou que exige ter tudo na cabeça ao mesmo
        tempo: faça você mesmo, ou com UM ajudante. Dois a quatro terminais
        resolvem quase tudo; passar de seis raramente compensa.

        ## Topologias

        - **Estrela (padrão).** Você no centro, cada terminal ligado só a você,
          ida e volta. Você distribui, recebe e integra. É o que o `apply` faz
          sozinho: todo agente novo nasce ligado a você nos dois sentidos.
        - **Autor → revisor.** O implementador manda direto ao revisor, que
          devolve a ele; você só recebe o resultado final. Ligue os dois entre
          si (`both: true`).
        - **Pipeline.** A → B → C, cada um entrega ao próximo, o último
          responde a você. Bom para etapas com formato fixo (levantar →
          implementar → testar).
        - **Por repositório.** Um terminal por pasta (`cwd`), cada um dono do
          seu repo, e você costurando o contrato entre eles.

        Ligue terminais entre si só quando eles precisam conversar sem você no
        meio. Aresta a mais é conversa a mais.

        ## Modelo e esforço por papel

        Use os ids e apelidos que `egeon models` devolver. Prefira o apelido da
        família (`opus`, `sonnet`, `haiku`, `fable`) — ele acompanha a versão
        nova do CLI; fixe o id inteiro só quando o usuário pedir uma versão.

        | papel | modelo | esforço |
        |---|---|---|
        | arquitetura, decisão difícil, depurar o que ninguém entende | o mais forte (opus/fable) | high; xhigh/max só para o que é realmente duro |
        | revisar mudança arriscada (segurança, dados, concorrência) | o mais forte | high |
        | implementar tarefa bem especificada | sonnet | medium |
        | escrever e rodar testes, corrigir lint, migração mecânica | sonnet ou haiku | low/medium |
        | buscar no código, resumir log, levantar inventário | haiku | sem esforço / low |

        - O nível tem de estar em `efforts` do modelo escolhido (`egeon models`);
          modelo com `efforts` vazio não aceita `effort`.
        - Esforço alto deixa o terminal mais lento e mais caro em TODO turno;
          suba onde o erro custa caro, não por precaução.
        - `ultracode` (quando o CLI tem) liga um modo que dispara fluxos com
          vários subagentes em toda tarefa: caro. Só com pedido do usuário ou
          para uma tarefa grande e autônoma.
        - Sem `model`/`effort` o terminal fica no padrão do CLI — escolha
          legítima quando você não tem motivo para outra.

        ## Terminais normais (`shell`)

        Nem tudo na bancada é agente. Um terminal comum é o lugar de um processo
        que fica rodando e que todos precisam ver: o servidor de dev, um watcher
        de testes, o `docker compose`, um `tail -f` de log. Também é onde você
        roda um comando sem gastar o turno de ninguém.

        - **Crie** com `"kind": "shell"`, a pasta em `cwd` e, se for um processo
          longo, o comando em `cmd` (`"npm run dev"`). Sem `cmd`, é um zsh de
          login esperando comando. Processo que deve durar vai em `cmd`, não
          por `egeon send`: o `cmd` volta sozinho quando o terminal reinicia (o
          app reabre, você muda a pasta); o que foi mandado, não.
        - Ele nasce ligado a VOCÊ, só de ida: shell não responde mensagem.
        - **Rode comando** com `egeon send <id>`: o texto chega CRU, como se
          você digitasse, e cada linha é executada. Um comando por vez, nada
          interativo (editor, prompt de senha, `git` com pager — use
          `--no-pager`).
        - **Leia a saída** com `egeon peek <id> 40`. Sem laço de peek: rode,
          espere o razoável, olhe uma vez.
        - Para dar a um AGENTE acesso ao shell (o testador lendo o log do
          servidor), ligue os dois: `{ "from": "testador", "to": "dev" }` — ele
          passa a poder `egeon peek dev` e mandar comando.
        - Shell com saída correndo aparece como `working` em `egeon bench`;
          reiniciar ou remover pede `"force": true`.
        - Comando em shell roda com as permissões de sistema do usuário, sem o
          pedido de permissão do CLI. Ele te deu esse poder ao te fazer maestro:
          nada destrutivo (apagar, `push`, `reset --hard`, banco de produção)
          sem ele pedir.

        ## Escrever o papel (`role`)

        O papel entra no system prompt do terminal e vale a conversa inteira.
        É **quem ele é**, não a tarefa de hoje — a tarefa vai por `egeon send`.
        Curto (5 a 12 linhas), concreto, na segunda pessoa:

        - **quem é e o que é dele:** "Você é o dono do backend em `api/`."
        - **o que entrega e para quem:** "Ao terminar, responda ao maestro com
          `egeon send maestro`: o que mudou, onde, e o que ficou pendente."
        - **critério de pronto:** "Pronto é teste passando e nada fora de
          `api/` alterado."
        - **o que não é dele:** "O front é do terminal `web`; precisando de
          mudança lá, peça a ele."

        Use os ids reais da bancada nos papéis — é por eles que os terminais
        se acham.

        ## Escrever regras (`rules`)

        Regra é **como se trabalha**, e entra no system prompt DEPOIS do papel:
        em conflito, vale a regra. Duas camadas:

        - `rules` no topo do plano: da **bancada inteira**, somadas às de cada
          terminal ("peça ao usuário antes de commitar", "não rode nada que
          apague dados").
        - `rules` num nó: só dele ("só leia; não edite arquivo nenhum").

        Uma por linha, poucas, dizendo o que FAZER e o porquê quando não for
        óbvio — "peça antes de commitar" adere muito melhor que "não commite".
        Regra demais dilui todas. Trocar as regras da bancada reinicia os
        outros agentes (com a mesma conversa); as suas valem no seu próximo
        arranque.

        ## Arestas e limites de conversa

        O app só deixa um terminal acionar outro por **aresta**, e corta
        cadeias longas:

        - `maxSends` (por aresta, padrão 2): quantas vezes aquela seta dispara
          numa mesma cadeia. Com 2, você manda, ele responde, você manda,
          ele responde — e a próxima é recusada. Se você vai iterar com um
          terminal (pedir, revisar, pedir ajuste), suba a SUA aresta com ele
          para 4–6.
        - `maxVisits` (da bancada, padrão 4): quantas vezes um mesmo terminal
          pode reaparecer numa cadeia. Em fases sequenciais (A, depois B,
          depois revisão, cada um voltando a você) você reaparece a cada
          volta: para uma orquestração de várias fases, 8 é um bom número.
        - A cadeia zera quando o usuário digita. Recusa por limite não é erro
          seu para contornar: volte a falar com o usuário.

        ## O plano

        Um JSON. Todos os campos são opcionais; mande só o que muda. Nos
        exemplos, `maestro` é o SEU id — use o que `egeon status` mostrar.

        ```json
        {
          "rules": "regras da bancada — null apaga",
          "maxVisits": 8,
          "nodes": [
            {
              "id": "back",
              "kind": "agent",
              "cli": "claude",
              "model": "sonnet",
              "effort": "medium",
              "ultracode": false,
              "cwd": "api",
              "config": "~/.claude-agro",
              "role": "Você é ...",
              "rules": "Só dentro de api/."
            },
            { "id": "dev", "kind": "shell", "cwd": "web", "cmd": "npm run dev" }
          ],
          "remove": ["velho"],
          "edges": [
            { "from": "back", "to": "revisor", "both": true },
            { "from": "maestro", "to": "back", "both": true, "maxSends": 6 }
          ],
          "unlink": [ { "from": "web", "to": "back", "both": true } ],
          "force": false
        }
        ```

        **`nodes`** — cria ou atualiza pelo `id`:

        | campo | o quê |
        |---|---|
        | `id` | minúsculo, letras/números/`-`/`_`; vira o endereço `bancada/id` |
        | `kind` | `agent` (padrão) ou `shell`; não muda depois de criado |
        | `cli` | chave de `egeon models` (`claude`, `codex`…); padrão `claude`. Trocar de CLI zera a conversa |
        | `model` | id ou apelido do catálogo daquele CLI |
        | `effort` | um dos `efforts` do modelo |
        | `ultracode` | `true`/`false`, se o CLI tiver |
        | `cwd` | pasta onde o terminal abre, relativa à raiz da bancada (ou absoluta); tem de existir |
        | `config` | uma das `configs` daquele CLI em `egeon models`; padrão: a que o workspace usa |
        | `role` | o papel (system prompt) |
        | `rules` | as regras só deste terminal |
        | `cmd` | só `shell`: o comando que ele roda ao subir; sem ele, um zsh de login |

        Num nó que já existe: **campo ausente fica como está; `null` volta ao
        padrão.** Mudar `model`, `effort`, `ultracode`, `role` ou `rules`
        reinicia o terminal com a MESMA conversa. Mudar `cwd`, `config` ou
        `cli` reinicia com conversa NOVA — o CLI guarda a conversa por pasta e
        por configuração. Mudar o `cmd` de um shell o reinicia (o processo
        antigo morre).
        Copiar um nó do `egeon bench` funciona: `state`, `you` e `maestro`
        são ignorados.

        **`remove`** — ids que saem, com as arestas deles.

        **`edges`** — `from`, `to`, `both` (as duas setas) e `maxSends`
        (de 1 a 10; tirar o limite é só do usuário). Aresta que já existe só
        tem o limite ajustado. `maxVisits` vai de 1 a 12. **`unlink`** — `from`, `to`, `both`.

        **`force`** — `true` deixa reiniciar ou remover terminal em segundo
        plano (veja abaixo). Nunca vale para terminal em turno.

        **O que o app recusa** (o plano INTEIRO, com a lista de erros — nada
        é aplicado pela metade):

        - campo com nome errado (`"modle"`), id que não é slug, id repetido;
        - CLI, modelo ou esforço que não estão em `egeon models`;
        - pasta que não existe; aresta para nó que não existe;
        - mexer em você mesmo (`nodes` ou `remove` com o seu id) — reiniciar
          quem está aplicando mataria o turno; peça ao usuário, no card;
        - mexer em outro maestro, ou em card de editor e navegador;
        - `config` fora das `configs` do CLI em `egeon models`;
        - reiniciar ou remover terminal em turno ou pedindo permissão
          (`state` `working` ou `asking` em `egeon bench`) — espere;
        - reiniciar ou remover terminal em segundo plano (`state:
          background`, ou shell com saída correndo) sem `"force": true`. Segundo plano tanto pode ser
          "esperando um vizinho" (interromper não custa nada) quanto um
          processo rodando (custa): olhe com `egeon peek <id>` e decida. Não
          fique esperando ele sair desse estado — ele só sai quando recebe
          mensagem nova.

        Ninguém vira maestro pelo plano: isso é só do usuário.

        ## Depois do apply

        Cada `apply` deixa uma linha na trilha da bancada com o resumo. Os
        terminais novos aparecem no canvas e sobem sozinhos. Mande a cada um
        a tarefa com tudo que ele precisa — ele não vê a sua conversa:

        - o objetivo e o contexto (arquivos, decisões já tomadas);
        - o que entregar e em que formato;
        - "responda com `egeon send <seu id>` quando terminar".

        Não fique em laço de `egeon peek` esperando: encerre o turno com o
        marcador de segundo plano; a resposta de cada um chega como mensagem
        nova. **Não mande recibo** ("recebi, obrigado, aguarde"): cada
        mensagem gasta uma ida da aresta, acorda o outro terminal à toa e o
        deixa parado "esperando" algo que não vem. Só mande quando houver
        trabalho novo para ele. Quando chegarem, integre, confira, e só então devolva ao
        usuário.

        **Respeite o que é do usuário.** Remova só terminais que você criou ou
        que ele pediu para tirar. Reconfigurar um terminal dele que está no
        meio de outro assunto é tomar o lugar dele: pergunte antes.

        ## Exemplo

        Pedido: "monta a bancada para adicionar login com Google — front em
        `web/`, back em `api/`".

        ```bash
        egeon plan <<'JSON'
        {
          "rules": "Peça ao usuário antes de commitar ou instalar dependência.\nRode os testes da sua pasta antes de dizer que terminou.",
          "maxVisits": 8,
          "nodes": [
            { "id": "back", "cwd": "api", "model": "sonnet", "effort": "medium",
              "role": "Você é o dono do backend em api/: rotas, sessão e integração OAuth.\nAo terminar, responda ao maestro com egeon send maestro: o que mudou, onde, e o contrato da API (rotas, payloads).\nO front é do terminal web." },
            { "id": "web", "cwd": "web", "model": "sonnet", "effort": "medium",
              "role": "Você é o dono do front em web/: tela de login e estado de sessão.\nUse o contrato que o maestro passar; não invente rota.\nAo terminar, responda ao maestro com egeon send maestro." },
            { "id": "revisor", "model": "opus", "effort": "high",
              "role": "Você revisa mudanças de autenticação: segurança, sessão, tratamento de erro.\nSó lê; aponte problema com arquivo:linha e a correção sugerida.\nResponda a quem pediu a revisão.",
              "rules": "Não edite arquivos." }
          ],
          "edges": [
            { "from": "maestro", "to": "back", "both": true, "maxSends": 4 },
            { "from": "maestro", "to": "web", "both": true, "maxSends": 4 },
            { "from": "back", "to": "revisor", "both": true },
            { "from": "web", "to": "revisor", "both": true }
          ]
        }
        JSON
        ```

        Prévia ok → mostrar a tabela ao usuário → `egeon apply` com o mesmo
        JSON → `egeon send back` com a tarefa → `egeon send web` dizendo para
        esperar o contrato (ou com um contrato provisório) → encerrar o turno
        em segundo plano.
        """#
    }
}
