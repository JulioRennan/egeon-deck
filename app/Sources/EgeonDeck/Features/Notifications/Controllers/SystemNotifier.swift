import AppKit
import UserNotifications

/// Manda o `SystemNotice` para a central de notificações e traz você de volta
/// para o terminal certo quando o aviso é clicado.
///
/// Só com o app fora da frente: olhando para ele, a borda e o som já dizem
/// tudo, e a notificação por cima seria o mesmo aviso duas vezes.
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()

    /// Abre a bancada e o terminal do aviso clicado.
    var onOpen: ((_ workbench: String, _ node: String) -> Void)?

    private var authorized = false
    private var asked = false

    /// O `UNUserNotificationCenter` derruba o processo fora de um bundle
    /// `.app` — o `swift test` é um.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    }

    func start() {
        guard let center else { return }
        center.delegate = self
        authorize()
    }

    private func authorize() {
        guard let center, !asked else { return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.authorized = granted
                Log.write("notificação: \(granted ? "autorizada" : "negada")"
                          + (error.map { " — \($0.localizedDescription)" } ?? ""))
            }
        }
    }

    /// Vai sair notificação com som — e aí o `AttentionSound` cala, para não
    /// tocar o aviso em dobro.
    var willSound: Bool {
        center != nil && authorized && !NSApp.isActive
    }

    func post(_ notice: SystemNotice) {
        guard let center else { return }
        guard !NSApp.isActive else {
            Log.write("notificação[\(notice.workbench)/\(notice.node)]: app na frente, só a borda")
            return
        }
        guard authorized else {
            // Negada no arranque e liberada depois nos Ajustes: reconsulta.
            center.getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized else {
                    Log.write("notificação: sem autorização (status \(settings.authorizationStatus.rawValue))",
                              key: "notify.denied")
                    return
                }
                DispatchQueue.main.async {
                    self.authorized = true
                    self.post(notice)
                }
            }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.userInfo = ["workbench": notice.workbench, "node": notice.node]
        content.sound = .default
        center.add(UNNotificationRequest(identifier: notice.identifier, content: content, trigger: nil)) { error in
            Log.write("notificação[\(notice.workbench)/\(notice.node)]: "
                      + (error.map { "falhou — \($0.localizedDescription)" } ?? notice.body))
        }
    }

    /// O terminal foi visto ou voltou a trabalhar: o aviso dele não vale mais.
    func withdraw(address: String) {
        guard let center else { return }
        center.removeDeliveredNotifications(withIdentifiers: ["egeon.\(address)"])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let workbench = info["workbench"] as? String, let node = info["node"] as? String {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                self.onOpen?(workbench, node)
            }
        }
        completionHandler()
    }
}
