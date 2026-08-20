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
    /// Processo encerrado.
    case dead

    /// Estados que INTERROMPEM: borda laranja e som. Só a pergunta entra aqui.
    /// "Terminou" você lê quando olhar; tratar os dois como o mesmo alarme é o
    /// que fazia o aviso virar barulho de fundo (ADR-024).
    var needsAttention: Bool { self == .asking }

    /// Sufixo do cabeçalho do nó. `nil` quando não vale ocupar a linha.
    var label: String? {
        switch self {
        case .starting: return "\(Spinner.current) subindo"
        case .working:  return "\(Spinner.current) trabalhando"
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
    var working = 0
    var attention = 0
    var done = 0
}

// MARK: - Carregando

/// Quadro do "negocinho rodando".
///
/// Derivado do relógio em vez de um contador próprio: todos os spinners da tela
/// giram em fase, nenhum precisa guardar estado, e um nó que entra ou sai da
/// hierarquia não começa do zero.
enum Spinner {
    private static let frames = Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    private static let frameDuration: TimeInterval = 0.09

    static var current: Character {
        let step = Int(Date().timeIntervalSinceReferenceDate / frameDuration)
        return frames[abs(step) % frames.count]
    }
}

// MARK: - Barulhinho

enum AttentionSound {
    /// Quatro agentes parando no mesmo tick tocariam quatro sons sobrepostos —
    /// isso é ruído, não aviso.
    private static var lastPlayed = Date.distantPast
    private static let minimumInterval: TimeInterval = 1.5

    /// Um `NSSound` por nome: recriar a cada aviso relê o arquivo do disco à toa.
    private static var cache: [String: NSSound] = [:]

    /// `name` é um som do sistema (`/System/Library/Sounds`) ou seu, em
    /// `~/Library/Sounds`. Nomes de fábrica: Basso, Blow, Bottle, Frog, Funk,
    /// Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink.
    ///
    /// `volume` é 0…1 sobre o volume de alerta do sistema. É ele, mais que a
    /// escolha do som, que decide se o aviso é discreto: qualquer som do
    /// catálogo em 0,3 vira um toque de fundo.
    static func play(_ name: String?, volume: Double) {
        guard let name, !name.isEmpty, volume > 0 else { return }
        guard Date().timeIntervalSince(lastPlayed) >= minimumInterval else { return }

        let sound: NSSound
        if let cached = cache[name] {
            sound = cached
        } else {
            guard let loaded = NSSound(named: name) else {
                Log.write("atenção: som \"\(name)\" não existe — veja os nomes em "
                          + "/System/Library/Sounds", key: "sound.\(name)")
                return
            }
            cache[name] = loaded
            sound = loaded
        }

        sound.volume = Float(min(max(volume, 0), 1))
        lastPlayed = Date()
        // Aviso em cima de aviso: `play` num som já tocando devolve false e o
        // segundo sumiria. Reiniciar do zero é o comportamento esperado.
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
