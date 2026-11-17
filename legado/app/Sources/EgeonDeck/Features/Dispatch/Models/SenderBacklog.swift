import Foundation

/// Quantas mensagens de UM remetente podem esperar leitura num terminal
/// (ADR-077).
///
/// A fila cheia é a guarda que segura agente em laço: a cadeia só avança na
/// entrega, então quem dispara `egeon send` em sequência manda tudo antes de o
/// destino ler a primeira, e as outras guardas nem contam. O teto era por
/// destino (cinco, fosse de quem fosse), e isso não separava o laço de um
/// remetente do time respondendo junto: com 14 agentes entregando ao maestro,
/// a sexta resposta legítima era recusada. O limite é o `maxSends` da
/// própria ligação; sem ele (↻ ∞), não há teto.
enum SenderBacklog {
    /// Mensagens de `sender` na fila, pela cadeia de cada uma: o remetente é o
    /// penúltimo elo (o último é o próprio destino).
    static func count(from sender: String, in chains: [[String]]) -> Int {
        chains.filter { $0.dropLast().last == sender }.count
    }
}
