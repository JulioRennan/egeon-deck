/// O que o gancho do CLI relata pelo socket — o contrato das rotas `/activity`
/// e `/conversation` (ADR-014, ADR-024).
///
/// Era string solta até aqui, e string solta é como contrato apodrece: um evento
/// novo entrava por um `default` silencioso em vez de obrigar quem recebe a
/// decidir o que fazer com ele. Tipado, o desconhecido morre na borda do socket,
/// com resposta dizendo o que a rota aceita.
enum HookEvent: String, CaseIterable {
    /// Gancho `Stop`: o turno acabou. O gancho diz QUANDO; o marcador na tela
    /// diz QUAL das duas paradas é.
    case stop
    /// Gancho `UserPromptSubmit`: não é aviso — diz qual conversa está aberta,
    /// e de quebra prova que o gancho chega neste terminal.
    case prompt
    /// Gancho `Notification`: pedido de permissão (ou o "você sumiu há 60s",
    /// que o `Target` descarta pelo turno).
    case ask
    /// Gancho `SessionStart`: a TUI subiu e está pronta para receber prompt.
    /// Até ele chegar o terminal está "iniciando" — o aquecimento por relógio
    /// acabava antes de o CLI terminar de carregar, e o card ficava sem rótulo
    /// com o programa ainda subindo.
    case start

    /// Para a mensagem de erro da rota: o que ela aceita, por extenso.
    static var expected: String {
        allCases.map(\.rawValue).joined(separator: "|")
    }

    /// Com que marcador o turno fechou, quando o `stop` consegue dizer. Vem
    /// do transcript, não da tela: é o que separa "terminou" de "precisa de
    /// você" sem depender do que a TUI já pintou.
    enum Marker: String {
        case ok, ask
    }
}
