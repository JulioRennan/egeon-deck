import AppKit

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
