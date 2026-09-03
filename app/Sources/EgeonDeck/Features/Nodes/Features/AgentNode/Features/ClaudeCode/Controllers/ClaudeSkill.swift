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
/// Publicada numa pasta nossa e entregue por `--add-dir`, nunca escrita no
/// `~/.claude` do usuário — a configuração dele não é lugar para o app mexer, a
/// mesma regra dos ganchos. Por isso a pasta apontada guarda só isto: `--add-dir`
/// também dá acesso de arquivo, e o que ela contém é o que o agente ganha.
enum ClaudeSkill {
    /// A pasta entregue ao CLI. Por flavor: o dev publica o texto dele sem
    /// mexer no que os agentes do estável estão lendo.
    static var directory: URL { Flavor.current.config("claude") }
    static var skillFile: URL { skillFile(in: directory) }

    /// Onde o CLI procura, dentro da pasta que recebe: é este caminho exato que
    /// o `--add-dir` faz o Claude Code varrer.
    static func skillFile(in directory: URL) -> URL {
        directory.appendingPathComponent(".claude/skills/egeon/SKILL.md")
    }

    /// Escrita a cada arranque, como o `bin/egeon` e o `claude-hooks.json`: o
    /// texto acompanha a versão do app que subiu, não o que ficou no disco.
    @discardableResult
    static func install(into directory: URL = ClaudeSkill.directory) -> URL? {
        let file = skillFile(in: directory)
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

    /// `user-invocable: false` porque isto não é um comando que você digita: é o
    /// que o agente precisa saber quando VOCÊ falar em outro agente. `when_to_use`
    /// carrega as frases de gatilho — é o campo que o CLI lê para decidir.
    static var body: String {
        """
        ---
        name: egeon
        description: Falar com os outros terminais desta bancada do Egeon Deck — \
        os agentes que o usuário vê no canvas ao lado deste. Use quando o pedido \
        envolver outro agente: mandar trabalho, pedir revisão, perguntar algo, \
        ver o que ele está fazendo, ou montar/dividir trabalho entre agentes.
        when_to_use: >
          Quando o usuário disser "pede pro <nome>", "manda o <nome> fazer",
          "fala com o <nome>", "avisa o <nome>", "o que o <nome> está fazendo",
          "pergunta pro <nome>", "divide isso entre os agentes", "monta um time",
          "usa outro agente", "delega isso", "roda em paralelo", "chama um
          revisor", ou citar um terminal da bancada pelo nome ou endereço.
        user-invocable: false
        ---

        # Os outros terminais desta bancada

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
        espera a resposta. Depois de mandar, o normal é encerrar o seu turno
        dizendo ao usuário para quem você passou — quem avisa quando o vizinho
        termina é o app, não você. Não fique em laço de `peek` esperando.

        Use `egeon peek` quando quiser mesmo conferir o estado de alguém sem
        mandar nada: ele lê a tela do vizinho e não interrompe o trabalho dele.

        A topologia muda enquanto você trabalha — consulte na hora, não confie no
        que viu no começo da conversa. Endereço fora da lista é recusado, e uma
        cadeia longa demais de agentes falando entre si também: quando isso
        acontecer, volte a falar com o usuário em vez de insistir.
        """
    }
}
