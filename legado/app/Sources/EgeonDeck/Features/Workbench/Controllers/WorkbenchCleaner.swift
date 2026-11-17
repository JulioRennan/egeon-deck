import Foundation

// MARK: - Limpar a bancada

/// Limpar a bancada tem duração, e a ordem importa (ADR-059).
///
/// O `clear` de cada agente vai pela fila do Dispatcher: terminal ocupado só
/// recebe quando ficar livre, e até lá o turno que ele ainda escreve continua
/// caindo no `chat.jsonl`. Arquivar no mesmo instante do disparo — o que se
/// fazia — deixava o rabo da conversa velha dentro da conversa nova, e a tela
/// ficava com bolha órfã. Aqui a limpeza espera: manda o `clear`, espera os
/// agentes assentarem, ARQUIVA e só então se diz pronta.
///
/// Sem estado próprio de bancada: quem sabe despachar, quem sabe se um
/// terminal está ocupado e quem sabe arquivar entram por closure, como no
/// EdgeController — é o que deixa o passo inteiro testável sem tela.
final class WorkbenchCleaner {
    struct Agent {
        let id: String
        let address: String
        /// O `clear` do perfil. Vazio ou nulo = CLI que não declara — pulado,
        /// nunca morto.
        let command: String?
    }

    /// Onde a limpeza está. É o que o loading mostra.
    enum Phase: Equatable {
        /// Esperando `remaining` agentes terminarem o que estavam fazendo e
        /// engolirem o `clear`.
        case clearing(remaining: Int)
        /// Movendo chat e trilha para `chat-archive/` e `trace-archive/`.
        case archiving
        case done

        var label: String? {
            switch self {
            case .clearing(let remaining) where remaining > 0:
                return "Limpando \(remaining) agente\(remaining == 1 ? "" : "s")…"
            case .clearing:  return "Limpando os agentes…"
            case .archiving: return "Arquivando o chat e a trilha…"
            case .done:      return nil
            }
        }
    }

    struct Result {
        var cleared: [String] = []
        var skipped: [String] = []
        var chat: URL?
        var trace: URL?
        /// Algum agente não assentou dentro do teto: arquivou-se assim mesmo.
        var timedOut = false

        var payload: [String: Any] {
            ["ok": true, "cleared": cleared, "skipped": skipped,
             "archived": chat?.path ?? NSNull(), "trace": trace?.path ?? NSNull(),
             "timeout": timedOut]
        }
    }

    /// Um terminal ainda pode engolir o `clear` sozinho?
    ///
    /// `asking` é não: ele parou pedindo permissão e depende de VOCÊ, não da
    /// limpeza — a fila dele não anda enquanto a caixa estiver na tela, e
    /// esperar significava esperar o teto inteiro com a cortina de pé. Visto no
    /// DEV: agente pediu permissão no meio do trabalho e a limpeza ficou 45 s
    /// parada. O `clear` continua na fila e é entregue quando você responder.
    static func isBusy(activity: Activity, pending: Int) -> Bool {
        guard activity != .asking else { return false }
        return pending > 0 || activity == .working || activity == .starting
    }

    private let agents: [Agent]
    private let dispatch: (Agent) -> Bool
    private let isBusy: (Agent) -> Bool
    private let archive: () -> (chat: URL?, trace: URL?)
    private let onPhase: (Phase) -> Void
    private let onFinish: (Result) -> Void

    /// Antes disto ninguém conta como assentado: o texto acabou de ser colado
    /// na TUI e o gancho de início de turno ainda não chegou. Sem a folga, a
    /// primeira olhada via todo mundo parado e arquivava na hora — o bug que
    /// este controller existe para tirar.
    private let grace: TimeInterval
    /// Teto. Agente atolado numa tarefa longa não pode prender o loading para
    /// sempre: estourou, arquiva-se com o que há e o resultado diz que estourou.
    private let timeout: TimeInterval

    private var startedAt = Date.distantPast
    private var result = Result()
    private(set) var phase = Phase.done
    private var timer: Timer?

    init(agents: [Agent],
         dispatch: @escaping (Agent) -> Bool,
         isBusy: @escaping (Agent) -> Bool,
         archive: @escaping () -> (chat: URL?, trace: URL?),
         onPhase: @escaping (Phase) -> Void = { _ in },
         onFinish: @escaping (Result) -> Void,
         grace: TimeInterval = 2.5,
         timeout: TimeInterval = 45) {
        self.agents = agents
        self.dispatch = dispatch
        self.isBusy = isBusy
        self.archive = archive
        self.onPhase = onPhase
        self.onFinish = onFinish
        self.grace = grace
        self.timeout = timeout
    }

    /// Dispara e cuida do próprio relógio. Os testes usam `start`/`tick`.
    func run() {
        start()
        guard phase != .done else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.tick()
            if self.phase == .done { timer.invalidate() }
        }
    }

    func start(now: Date = Date()) {
        startedAt = now
        result = Result()
        for agent in agents {
            guard let command = agent.command, !command.isEmpty, dispatch(agent) else {
                result.skipped.append(agent.id)
                continue
            }
            result.cleared.append(agent.id)
        }
        phase = .clearing(remaining: result.cleared.count)
        onPhase(phase)
        // Bancada sem agente que aceite `clear` não tem o que esperar.
        if result.cleared.isEmpty { finish() }
    }

    func tick(now: Date = Date()) {
        guard case .clearing = phase else { return }
        let elapsed = now.timeIntervalSince(startedAt)
        let busy = agents.filter { result.cleared.contains($0.id) && isBusy($0) }
        if elapsed >= timeout {
            result.timedOut = true
            Log.write("limpar: \(busy.count) agente(s) ainda ocupado(s) depois de "
                      + "\(Int(timeout))s — arquivando assim mesmo")
            finish()
            return
        }
        guard elapsed >= grace, busy.isEmpty else {
            let next = Phase.clearing(remaining: busy.count)
            if next != phase { phase = next; onPhase(next) }
            return
        }
        finish()
    }

    private func finish() {
        phase = .archiving
        onPhase(phase)
        let archived = archive()
        result.chat = archived.chat
        result.trace = archived.trace
        phase = .done
        onPhase(phase)
        onFinish(result)
    }
}
