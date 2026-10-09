import CoreGraphics
import Foundation

enum NodeKind: String, Codable {
    case editor   // code-server no WKWebView
    case shell    // terminal comum
    case agent    // terminal com IA
    case web      // navegador no canvas, com perfil próprio
}

struct NodeConfig: Codable {
    let type: NodeKind
    let id: String
    /// Chave em agents.json. Só usado por `type: agent`.
    var agent: String?
    /// Relativo à raiz da bancada.
    var cwd: String?
    /// Comando inicial. Em `agent`, o padrão vem do perfil.
    var cmd: String?
    /// Pasta de configuração do CLI — com qual conjunto de plugins, MCP e
    /// settings este terminal sobe. Absoluto, e entregue pela variável que o
    /// perfil declara em `configEnv`. Nulo é o padrão da CLI.
    var config: String?
    /// Modelo pedido ao CLI, pela flag que o perfil declara em `model`. Nulo é
    /// o padrão do CLI. Só usado por `type: agent`; trocar reinicia o processo,
    /// mas a conversa fica — o CLI retoma a mesma sessão com outro modelo.
    var model: String?
    /// Esforço pedido ao CLI, pela flag que o perfil declara em `effort`. Nulo
    /// é o padrão do CLI; trocar reinicia e retoma, como o modelo.
    var effort: String?
    /// Ultracode ligado — o modo do Claude Code que roda workflow dinâmico em
    /// toda tarefa. Não é nível: vale em qualquer esforço, por isso campo à parte.
    var ultracode: Bool?
    /// Só usado por `type: web`.
    var url: String?
    /// Nome do perfil em web-profiles.json. Só usado por `type: web`.
    var profile: String?

    /// Mensagem entregue ao agente quando ele sobe — o papel deste terminal.
    /// Entra na fila do Dispatcher, que espera a TUI aceitar stdin.
    var prompt: String?

    /// As regras que valem para este terminal, somadas às da bancada.
    ///
    /// Separadas do papel porque não são a mesma coisa: papel é quem o agente é
    /// e muda de nó para nó; regra é como se trabalha aqui, e a maior parte
    /// delas é da bancada inteira. E porque a ordem importa — elas entram DEPOIS
    /// do papel no system prompt, que é o que faz a restrição específica valer
    /// contra a diretriz geral (ADR-056).
    var rules: String?

    /// Este terminal pode montar e reconfigurar a própria bancada pelo `egeon`
    /// — criar nós, trocar modelo, esforço, papel e regras, desenhar arestas
    /// (ADR-066). Só você liga isto, no formulário: o plano do maestro não tem
    /// este campo, senão um maestro faria outros.
    var maestro: Bool?

    var isMaestro: Bool { type == .agent && maestro == true }

    /// O que você configurou para CADA CLI neste terminal.
    ///
    /// `prompt` e `rules` acima são os GERAIS — valem em qualquer CLI. Aqui fica
    /// a exceção de cada um, mais o comando, a configuração e o modelo, que não
    /// atravessam CLI nenhum. Trocar para o Codex, ajustar o dele e voltar ao
    /// Claude Code devolve o que o Claude tinha, sem reconfigurar (ADR-057).
    ///
    /// `cmd`, `config` e `model` soltos continuam sendo o que vale agora: é
    /// deles que o arranque monta a linha de comando, e nó gravado antes disto
    /// só os tem ali.
    var byAgent: [String: NodeTemplate.Overrides]?

    /// O papel que sobe de fato: o do CLI em uso quando ele tem um próprio, o
    /// geral quando não.
    var effectivePrompt: String? {
        agent.flatMap { byAgent?[$0]?.prompt } ?? prompt
    }
    /// As regras que sobem de fato — mesma regra do papel.
    var effectiveRules: String? {
        agent.flatMap { byAgent?[$0]?.rules } ?? rules
    }
    /// Componente que originou o nó. Só registro: os valores foram copiados, e
    /// editar o componente depois não mexe em quem já nasceu.
    var component: String?

    /// Conversa deste terminal no CLI do agente. Gerado na primeira subida e
    /// guardado daí em diante — é o que permite retomar depois de um rebuild.
    ///
    /// Vive no NÓ e não é derivado da pasta de propósito: dois agentes na mesma
    /// worktree têm conversas separadas, e o `--continue` do Claude Code, que pega
    /// a mais recente do diretório, entregaria a mesma para os dois.
    var conversationId: String?

    /// Onde o CLI está gravando esta conversa.
    ///
    /// Relatado pelo gancho, que recebe `transcript_path` no payload, e guardado
    /// aqui para quem lê a conversa como dados poder achá-la no arranque — antes
    /// do primeiro prompt não haveria gancho nenhum e a conversa cheia pareceria
    /// vazia.
    ///
    /// Não é derivado do id da conversa mais convenção de pasta: isso amarraria o app
    /// ao `CLAUDE_CONFIG_DIR` do usuário, que é config de CLI e não é assunto
    /// nosso. Quem sabe onde grava é quem grava.
    var transcript: String?

    /// O terminal já subiu uma vez com esta conversa?
    ///
    /// Separado do id porque a estreia usa flag diferente da retomada. Sem isso a
    /// primeira subida tentaria retomar uma conversa que não existe e mostraria
    /// "No conversation found" antes de criar — funciona, mas suja a tela toda vez
    /// que você cria um terminal.
    var conversationStarted: Bool?

    /// Ausente significa "nunca subiu": nó gravado antes deste campo existir não
    /// o tem.
    var hasStartedConversation: Bool { conversationStarted ?? false }

    /// Os nomes antigos dos dois campos acima. **Não use**: eles existem só para ler
    /// arquivo gravado por versão anterior, são absorvidos na carga por
    /// `migratingLegacyNames` e nunca voltam ao disco — o encoder sintetizado omite
    /// opcional nulo.
    ///
    /// O campo se chamava `sessionId` porque o CLI chama a conversa de sessão. Aqui
    /// dentro isso colidia com a bancada do app e com o `Target` do Dispatcher: três
    /// coisas diferentes, uma palavra.
    ///
    /// Internos e não `private` porque propriedade privada torna PRIVADO o init
    /// membro-a-membro sintetizado, e é por ele que todo nó nasce.
    var sessionId: String?
    var sessionStarted: Bool?

    /// O nó com os nomes antigos absorvidos.
    var migratingLegacyNames: NodeConfig {
        var copy = self
        if copy.conversationId == nil { copy.conversationId = copy.sessionId }
        if copy.conversationStarted == nil { copy.conversationStarted = copy.sessionStarted }
        copy.sessionId = nil
        copy.sessionStarted = nil
        return copy
    }

    /// O nó saído do formulário, com o que o formulário não mostra de volta.
    ///
    /// O formulário remonta o nó do zero pelo componente, e componente não tem
    /// conversa, ultracode nem URL: sem isto, renomear ou marcar maestro subia o
    /// agente numa conversa nova. A conversa só fica com o mesmo CLI na mesma
    /// pasta — o Claude Code guarda a conversa por diretório, e outro CLI não a lê.
    func keepingState(of previous: NodeConfig) -> NodeConfig {
        var copy = self
        if copy.url == nil { copy.url = previous.url }
        if copy.profile == nil { copy.profile = previous.profile }
        guard copy.type == previous.type, copy.agent == previous.agent else { return copy }
        if copy.ultracode == nil { copy.ultracode = previous.ultracode }
        guard copy.cwd == previous.cwd else { return copy }
        copy.conversationId = previous.conversationId
        copy.conversationStarted = previous.conversationStarted
        copy.transcript = previous.transcript
        return copy
    }

    /// O mesmo nó, sem a conversa — pronto para nascer em outro lugar.
    ///
    /// Copiar um nó é copiar a montagem, nunca o que foi dito dentro dele. Com o
    /// `conversationId` junto, o clone e o original apontam para a MESMA conversa e o
    /// segundo a subir não consegue abri-la: o terminal mostra a TUI desenhada e
    /// morre em seguida, sem erro visível no app. Vale para o template e para a
    /// duplicação em worktree.
    var withoutConversation: NodeConfig {
        var copy = self
        copy.conversationId = nil
        copy.conversationStarted = nil
        // O transcript é da conversa, não da montagem: mantê-lo faria o clone
        // apontar para a conversa do original.
        copy.transcript = nil
        return copy
    }

    /// Posição e tamanho no canvas. Ausente na primeira vez: o app calcula o
    /// layout automático e grava o resultado, então a partir daí o que manda é
    /// onde o nó está de fato.
    var x: Double?
    var y: Double?
    var w: Double?
    var h: Double?

    var frame: CGRect? {
        guard let x, let y, let w, let h, w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    mutating func setFrame(_ rect: CGRect) {
        x = Double(rect.minX.rounded())
        y = Double(rect.minY.rounded())
        w = Double(rect.width.rounded())
        h = Double(rect.height.rounded())
    }
}

