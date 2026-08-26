import Foundation

/// Um turno como o chat o mostra, pronto para ficar no disco: o `ChatTurn`
/// peneirado (prompt, passos em uma linha, resposta em prosa) mais o carimbo
/// de quem o produziu. É o espelho do que você vê — não o transcript do CLI,
/// que traz `tool_result`, `thinking` e snapshot e passa de dezenas de MB
/// (ADR-037).
struct ChatRecord: Equatable, Codable {
    /// Id do nó dentro da bancada; a bancada é o arquivo.
    let node: String
    var conversation: String? = nil
    var cli: String? = nil
    var model: String? = nil
    let turn: ChatTurn

    /// Dois `Stop` do mesmo turno não podem virar duas linhas: o uuid do
    /// prompt no CLI identifica o turno, e o nó separa dois CLIs que por acaso
    /// gerem o mesmo.
    var key: String { "\(node)#\(turn.id)" }
}
