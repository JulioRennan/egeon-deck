import AppKit

// MARK: - Estado de um terminal, visto pelo pty

/// O que um terminal está fazendo. Deduzido só do fluxo de bytes do pty — nada
/// aqui olha o desenho da TUI (ADR-008, ADR-011).
enum Activity: Equatable {
    /// Subiu, mas ainda está no aquecimento ou não escreveu o primeiro byte.
    case starting
    /// Aqueceu e está parado sem ter feito nada de substancial.
    case ready
    /// Saiu byte agora há pouco.
    case working
    /// Trabalhou e parou: terminou a tarefa, ou está esperando uma resposta
    /// sua. Do pty os dois são o mesmo sinal — ver ADR-011.
    case waiting
    /// Parou, e as últimas linhas casaram um padrão declarado no perfil. É um
    /// `waiting` com mais informação, não um estado diferente de fato.
    case asking
    /// Parou, mas deixou trabalho rodando por baixo — comando em background,
    /// subagente, vizinho acionado — e volta sozinho quando ele acabar. É o
    /// `[[ED:wait]]`: sem ele, o card dizia "terminou" (ou nada) com o agente
    /// ainda de pé, e você não sabia se esperava ou se entrava (ADR-063).
    case background
    /// Processo encerrado.
    case dead

    /// Estados que INTERROMPEM: borda laranja e som. Só a pergunta entra aqui.
    /// "Terminou" você lê quando olhar; tratar os dois como o mesmo alarme é o
    /// que fazia o aviso virar barulho de fundo (ADR-024).
    var needsAttention: Bool { self == .asking }

    /// Sufixo do cabeçalho do nó. `nil` quando não vale ocupar a linha.
    var label: String? {
        switch self {
        case .starting: return "\(Spinner.current) preparando"
        case .working:  return "\(Spinner.current) trabalhando"
        case .background: return "\(Spinner.hourglass) em segundo plano"
        case .waiting:  return "● terminou"
        case .asking:   return "● precisa de você"
        case .dead:     return "✕ processo encerrado"
        case .ready:    return nil
        }
    }

    /// Cor do rótulo. `nil` = mantém o acento do tipo de nó.
    var color: NSColor? {
        switch self {
        // A mesma bolinha das duas paradas, e a cor é que separa: verde
        // terminou, laranja depende de você. Glifos diferentes obrigavam a ler
        // o cabeçalho; a cor você reconhece de longe, que é quando importa.
        case .waiting: return .systemGreen
        case .asking:  return .systemOrange
        case .dead:    return .systemRed
        default:       return nil
        }
    }
}

/// Quantos terminais de uma bancada estão em cada situação. É o que a barra
/// lateral mostra das bancadas que não estão na tela.
struct ActivitySummary: Equatable {
    /// Subindo ainda: o CLI não relatou `SessionStart`. Separado de `working`
    /// porque bancada que acabou de abrir não está trabalhando — está
    /// preparando, e o spinner de trabalho ali era um falso "ocupado".
    var starting = 0
    var working = 0
    /// Parados com trabalho de fundo (`[[ED:wait]]`). Contagem própria, e não
    /// somada a `working`: somada, a barra mostrava o spinner comum e a
    /// ampulheta só existia dentro do card (ADR-063).
    var background = 0
    var attention = 0
    var done = 0

    /// Só terminais subindo, nada mais a dizer: é a bancada se preparando.
    var isPreparing: Bool {
        starting > 0 && working == 0 && background == 0 && attention == 0 && done == 0
    }
}
