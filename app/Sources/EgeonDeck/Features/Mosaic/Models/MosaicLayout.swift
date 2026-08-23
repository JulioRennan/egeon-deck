import Foundation

/// As proporções que você arrastou no mosaico.
///
/// Fração e não ponto: a janela muda de tamanho entre um arranque e outro, e
/// posição de divisor em pontos reabriria o mosaico torto.
///
/// Aplicada só quando a contagem casa com o que está na tela. Nó criado ou
/// removido invalida a proporção salva, e aplicar uma lista de tamanho errado
/// entortaria o layout em vez de deixá-lo dividir igual.
struct MosaicLayout: Codable, Equatable {
    /// Largura de cada coluna, na ordem em que o mosaico as monta.
    var columns: [Double]?
    /// Altura de cada linha, coluna por coluna.
    var rows: [[Double]]?
    /// Quem está em qual painel: ids de nó, por coluna.
    ///
    /// Existe porque o arranjo deixou de ser derivado do tipo do nó. Derivado, não
    /// havia como trocar dois cards de lugar — a única ordem possível era
    /// editores, terminais, web, e dentro da coluna a do `workbenches.json`. Nulo, ou
    /// com id que não está mais na bancada, cai de volta na regra de tipo, que
    /// continua sendo o arranjo de quem nunca arrastou nada.
    var slots: [[String]]?
}
