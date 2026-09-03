import Foundation

/// A skill que ensina o Claude Code a usar os vizinhos da bancada.
///
/// O catálogo do system prompt (`main.swift`) diz o que o `egeon` faz, e não
/// basta: quando você escreve "pede pro revisor olhar isso" ou "monta um time",
/// o que decide o caminho é a DESCRIÇÃO de uma ferramenta, não prosa que entrou
/// no prompt há vinte mensagens. Sem uma skill, a única descrição que casa com
/// essas frases é a do subagente do próprio CLI — e o agente spawna um subagente
/// invisível em vez de falar com o terminal ao lado, que é o que você está vendo
/// na tela. A skill entra na mesma disputa, com as suas palavras (ADR-054).
///
/// Skill é **por configuração do CLI**, e uma máquina tem várias: `~/.claude`,
/// `~/.claude-agro`, a que cada nó escolhe no formulário. Então ela é escrita no
/// root de CADA base path que existe no disco — é lá que o Claude Code procura,
/// e um caminho só deixaria o agente que aponta para outra config sem ela.
///
/// É a exceção à regra de não escrever na config do usuário (os ganchos vão por
/// `--settings`, um arquivo nosso): não há flag que entregue skill de fora, e
/// `--add-dir` — a porta que existe — sombreia mal quando as duas coexistem e
/// não alcança nó com `cmd` trocado, que não recebe flag nenhuma. Escrever
/// alcança os dois casos. Uma pasta só, com nome nosso, reescrita a cada
/// arranque; nada mais na config é tocado (ADR-054).
enum ClaudeSkill {
    /// O nome da pasta é o nome da skill: é dele que sai o `/egeon`.
    static let name = "egeon"

    /// Onde o CLI procura dentro de um base path.
    static func skillFile(in config: URL) -> URL {
        config.appendingPathComponent("skills/\(name)/SKILL.md")
    }

    /// As configurações do Claude Code que existem agora: as do padrão
    /// `~/.claude*` (o mesmo `configGlob` que o formulário do nó oferece) mais a
    /// do ambiente, que pode estar fora dele.
    static func configDirectories(of profile: AgentProfile = .claudeCode) -> [URL] {
        var out = profile.discoveredConfigs
        if let named = profile.configEnv.flatMap({ ProcessInfo.processInfo.environment[$0] }),
           !named.isEmpty {
            let url = URL(fileURLWithPath: (named as NSString).expandingTildeInPath)
            if !out.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                out.append(url)
            }
        }
        return out
    }

    /// Escrita a cada arranque, como o `bin/egeon` e o `claude-hooks.json`: o
    /// texto acompanha a versão do app que subiu, não o que ficou no disco.
    /// Devolve onde escreveu.
    @discardableResult
    static func install(into configs: [URL] = ClaudeSkill.configDirectories()) -> [URL] {
        // Primeira tentativa: a skill morava numa pasta nossa, entregue por
        // `--add-dir`. Deixá-la ali é ter duas cópias da mesma skill em disco,
        // e um dia elas divergem.
        try? FileManager.default.removeItem(at: Flavor.current.config("claude"))

        return configs.compactMap { config in
            let file = skillFile(in: config)
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try body.write(to: file, atomically: true, encoding: .utf8)
                return file
            } catch {
                Log.write("skill: não consegui escrever \(file.path) — \(error)")
                return nil
            }
        }
    }

    /// `user-invocable: false` porque isto não é um comando que você digita: é o
    /// que o agente precisa saber quando VOCÊ falar em outro agente. `when_to_use`
    /// carrega as frases de gatilho — é o campo que o CLI lê para decidir.
    static var body: String {
        """
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

        A topologia muda enquanto você trabalha — consulte na hora, não confie no
        que viu no começo da conversa. Endereço fora da lista é recusado, e uma
        cadeia longa demais de agentes falando entre si também: quando isso
        acontecer, volte a falar com o usuário em vez de insistir.
        """
    }
}
