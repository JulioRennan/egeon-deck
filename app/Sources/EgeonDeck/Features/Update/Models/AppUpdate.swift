import CryptoKit
import Foundation

/// Número de versão comparável: `v1.10.0` é maior que `1.9.2`, o que comparar
/// como texto erraria.
struct AppVersion: Comparable, Equatable {
    let parts: [Int]

    init?(_ text: String) {
        let bare = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        for index in 0..<max(a.parts.count, b.parts.count) {
            let left = index < a.parts.count ? a.parts[index] : 0
            let right = index < b.parts.count ? b.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// Uma versão publicada, lida da release do GitHub.
struct AvailableUpdate: Equatable {
    static let zipName = "EgeonDeck.zip"
    static let signatureName = "EgeonDeck.zip.sig"

    let version: String
    let notes: String
    let page: URL
    let zip: URL
    /// Nil em release sem assinatura — que o app não instala.
    let signature: URL?

    /// Nil quando o JSON não é uma release com o zip de nome fixo.
    static func parse(release data: Data) -> AvailableUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, AppVersion(tag) != nil,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        func asset(_ name: String) -> URL? {
            assets.first { $0["name"] as? String == name }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        guard let zip = asset(zipName) else { return nil }
        let bare = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return AvailableUpdate(version: bare, notes: json["body"] as? String ?? "", page: page,
                               zip: zip, signature: asset(signatureName))
    }

    func isNewer(than installed: String) -> Bool {
        guard let mine = AppVersion(installed), let theirs = AppVersion(version) else { return false }
        return theirs > mine
    }
}

/// A prova de que o zip saiu da máquina que faz as releases.
///
/// Sem assinatura da Apple, nada mais diz de onde o zip veio, e o atualizador
/// executa o que baixa: uma conta do GitHub invadida viraria código rodando em
/// toda máquina. A chave privada fica no Keychain de quem publica
/// (`tools/release-key.swift`), nunca no repositório nem no GitHub.
enum UpdateSignature {
    static let publicKey = "VnRyK5/qnhQEzUb0yD0lEN+If86U8P8cu43jynviXaU="

    static func isValid(_ zip: Data, signature base64: String, publicKey: String = UpdateSignature.publicKey) -> Bool {
        let text = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: publicKey), let signature = Data(base64Encoded: text),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: zip)
    }
}

/// O script que troca o bundle depois de o app sair.
///
/// Precisa ser outro processo: o app não se substitui estando de pé. A troca são
/// dois `mv` no mesmo volume, como no `install.sh`, e por isso o novo já espera ao
/// lado do destino; se o segundo falhar, o antigo volta.
enum UpdateSwapScript {
    /// Argumentos: pid do app, bundle novo, destino, `1` para reabrir.
    static let body = #"""
    #!/bin/sh
    pid="$1"; novo="$2"; destino="$3"; reabrir="$4"
    antigo="$destino.antigo"
    tentativas=0
    while kill -0 "$pid" 2>/dev/null; do
      tentativas=$((tentativas + 1))
      if [ "$tentativas" -gt 300 ]; then echo "o app não saiu; troca cancelada"; exit 1; fi
      sleep 0.2
    done
    rm -rf "$antigo"
    if ! mv "$destino" "$antigo"; then echo "não movi o bundle atual"; exit 1; fi
    if ! mv "$novo" "$destino"; then
      mv "$antigo" "$destino"
      echo "não movi o bundle novo; o atual voltou"
      exit 1
    fi
    rm -rf "$antigo"
    xattr -dr com.apple.quarantine "$destino" 2>/dev/null
    echo "atualizado: $destino"
    if [ "$reabrir" = 1 ]; then open "$destino"; fi
    """#
}

/// O que fazer ao saber que há versão nova — depende de quem perguntou e da
/// opção do menu.
enum UpdatePolicy {
    enum Reason { case launch, periodic, manual }
    enum Action: Equatable {
        /// Nada novo, e ninguém perguntou.
        case nothing
        /// Pediu pelo menu e já está na última: diz isso.
        case sayUpToDate
        /// Avisa e deixa você escolher.
        case prompt
        /// Só o item do menu muda: aviso modal fica para quando o app abre.
        case showInMenu
        /// Baixa sem perguntar, e a troca fica para quando você fechar o app.
        case downloadQuietly
    }

    static func action(newer: Bool, reason: Reason, auto: Bool) -> Action {
        guard newer else { return reason == .manual ? .sayUpToDate : .nothing }
        if reason == .manual { return .prompt }
        if auto { return .downloadQuietly }
        return reason == .launch ? .prompt : .showInMenu
    }
}
