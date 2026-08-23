import Foundation

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
