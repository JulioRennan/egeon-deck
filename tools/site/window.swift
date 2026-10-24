// Id e moldura da janela principal do Egeon Dev, para o `screencapture -l`
// (que não pede Acessibilidade, só Gravação de Tela).
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Egeon Deck (dev)"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
let windows = list.filter {
    ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0
}
let best = windows.max { a, b in
    let ra = a[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let rb = b[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (ra["Width"] ?? 0) * (ra["Height"] ?? 0) < (rb["Width"] ?? 0) * (rb["Height"] ?? 0)
}
guard let best, let id = best[kCGWindowNumber as String] as? Int,
      let r = best[kCGWindowBounds as String] as? [String: Double] else {
    let names = Set(list.compactMap { $0[kCGWindowOwnerName as String] as? String }).sorted()
    FileHandle.standardError.write("janela não achada; donos: \(names)\n".data(using: .utf8)!)
    exit(1)
}
print(id, Int(r["X"]!), Int(r["Y"]!), Int(r["Width"]!), Int(r["Height"]!))
